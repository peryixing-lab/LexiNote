import Foundation
import Compression

struct ZipExtractedEntry {
    let relativePath: String
    let data: Data
}

enum PluginZip {
    /// Extracts a ZIP archive into validated in-memory entries (checking entry count, file sizes, total size, and safe relative paths).
    static func readEntries(from zipURL: URL) throws -> [ZipExtractedEntry] {
        guard FileManager.default.fileExists(atPath: zipURL.path) else {
            throw PluginHostError(PluginErrorCode.notFound, "找不到插件安装包：\(zipURL.lastPathComponent)")
        }
        let archiveData: Data
        do {
            archiveData = try Data(contentsOf: zipURL)
        } catch {
            throw PluginHostError(PluginErrorCode.io, "无法读取插件压缩包：\(error.localizedDescription)")
        }
        guard archiveData.count <= PluginLimits.maxZipTotalBytes else {
            throw PluginHostError(PluginErrorCode.installRejected, "插件包体积超出 32 MB 上限")
        }

        let eocdOffset = findEndOfCentralDirectory(in: archiveData)
        guard eocdOffset >= 0 else {
            throw PluginHostError(PluginErrorCode.installRejected, "无效的 ZIP 压缩包：缺少目录尾标识")
        }

        let totalEntries = Int(readUInt16LE(archiveData, at: eocdOffset + 10))
        let cdOffset = Int(readUInt32LE(archiveData, at: eocdOffset + 16))
        guard totalEntries > 0, totalEntries <= PluginLimits.maxZipFiles else {
            throw PluginHostError(PluginErrorCode.installRejected, "插件文件数量超出限制（最多 \(PluginLimits.maxZipFiles) 个）")
        }
        guard cdOffset >= 0, cdOffset < archiveData.count else {
            throw PluginHostError(PluginErrorCode.installRejected, "ZIP 中央目录偏移无效")
        }

        var rawEntries: [(name: String, method: UInt16, compressedSize: Int, uncompressedSize: Int, localHeaderOffset: Int, mode: UInt32)] = []
        var cursor = cdOffset
        for _ in 0..<totalEntries {
            guard cursor + 46 <= archiveData.count,
                  readUInt32LE(archiveData, at: cursor) == 0x02014B50 else {
                throw PluginHostError(PluginErrorCode.installRejected, "ZIP 中央目录格式损坏")
            }
            let method = readUInt16LE(archiveData, at: cursor + 10)
            let compressedSize = Int(readUInt32LE(archiveData, at: cursor + 20))
            let uncompressedSize = Int(readUInt32LE(archiveData, at: cursor + 24))
            let nameLen = Int(readUInt16LE(archiveData, at: cursor + 28))
            let extraLen = Int(readUInt16LE(archiveData, at: cursor + 30))
            let commentLen = Int(readUInt16LE(archiveData, at: cursor + 32))
            let externalAttr = readUInt32LE(archiveData, at: cursor + 38)
            let localOffset = Int(readUInt32LE(archiveData, at: cursor + 42))

            let nameStart = cursor + 46
            let nameEnd = nameStart + nameLen
            guard nameEnd + extraLen + commentLen <= archiveData.count else {
                throw PluginHostError(PluginErrorCode.installRejected, "ZIP 目录条目越界")
            }
            let nameData = archiveData.subdata(in: nameStart..<nameEnd)
            let name = String(data: nameData, encoding: .utf8) ?? String(decoding: nameData, as: UTF8.self)
            rawEntries.append((name, method, compressedSize, uncompressedSize, localOffset, externalAttr >> 16))
            cursor = nameEnd + extraLen + commentLen
        }

        // Detect common single top-level wrapper folder (e.g. plugin-name/manifest.json)
        let fileNames = rawEntries.map(\.name).filter { !$0.hasSuffix("/") && !$0.hasPrefix("__MACOSX/") && !$0.hasSuffix(".DS_Store") }
        let stripPrefix = commonTopFolderPrefix(fileNames)

        var totalExtractedBytes = 0
        var results: [ZipExtractedEntry] = []

        for entry in rawEntries {
            if entry.name.hasSuffix("/") || entry.name.hasPrefix("__MACOSX/") || entry.name.hasSuffix("/.DS_Store") || entry.name == ".DS_Store" {
                continue
            }
            // Reject UNIX symlinks (S_IFLNK = 0o120000)
            if (entry.mode & 0o170000) == 0o120000 {
                throw PluginHostError(PluginErrorCode.installRejected, "插件包包含不安全的符号链接：\(entry.name)")
            }

            var relative = entry.name
            if !stripPrefix.isEmpty && relative.hasPrefix(stripPrefix) {
                relative = String(relative.dropFirst(stripPrefix.count))
            }
            guard let cleanPath = sanitizeRelativePath(relative) else {
                throw PluginHostError(PluginErrorCode.installRejected, "插件包含非法路径：\(entry.name)")
            }

            guard entry.uncompressedSize >= 0, entry.uncompressedSize <= PluginLimits.maxFileBytes else {
                throw PluginHostError(PluginErrorCode.installRejected, "文件「\(cleanPath)」超出 5 MB 单文件上限")
            }
            totalExtractedBytes += entry.uncompressedSize
            guard totalExtractedBytes <= PluginLimits.maxZipTotalBytes else {
                throw PluginHostError(PluginErrorCode.installRejected, "解压后插件总大小超出 32 MB 上限")
            }

            let lh = entry.localHeaderOffset
            guard lh + 30 <= archiveData.count,
                  readUInt32LE(archiveData, at: lh) == 0x04034B50 else {
                throw PluginHostError(PluginErrorCode.installRejected, "ZIP 本地文件头损坏：\(cleanPath)")
            }
            let lhNameLen = Int(readUInt16LE(archiveData, at: lh + 26))
            let lhExtraLen = Int(readUInt16LE(archiveData, at: lh + 28))
            let payloadStart = lh + 30 + lhNameLen + lhExtraLen
            let payloadEnd = payloadStart + entry.compressedSize
            guard payloadStart >= 0, payloadEnd <= archiveData.count else {
                throw PluginHostError(PluginErrorCode.installRejected, "ZIP 文件载荷越界：\(cleanPath)")
            }
            let compressedSlice = archiveData.subdata(in: payloadStart..<payloadEnd)
            let inflated = try decompress(compressedSlice, method: entry.method, expectedSize: entry.uncompressedSize, fileName: cleanPath)
            results.append(ZipExtractedEntry(relativePath: cleanPath, data: inflated))
        }

        return results
    }

    static func readEntries(fromDirectory folderURL: URL) throws -> [ZipExtractedEntry] {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: folderURL.path, isDirectory: &isDir), isDir.boolValue else {
            throw PluginHostError(PluginErrorCode.notFound, "找不到插件目录：\(folderURL.path)")
        }
        guard let enumerator = FileManager.default.enumerator(
            at: folderURL,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey],
            options: []
        ) else {
            throw PluginHostError(PluginErrorCode.io, "无法遍历插件目录")
        }

        let resolvedRoot = folderURL.standardizedFileURL.path
        var results: [ZipExtractedEntry] = []
        var totalBytes = 0
        for case let url as URL in enumerator {
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
            if values?.isSymbolicLink == true {
                throw PluginHostError(PluginErrorCode.installRejected, "插件目录包含不允许的符号链接：\(url.lastPathComponent)")
            }
            guard values?.isRegularFile == true else { continue }
            if url.lastPathComponent == ".DS_Store" { continue }
            let full = url.standardizedFileURL.path
            guard full.hasPrefix(resolvedRoot + "/") else {
                throw PluginHostError(PluginErrorCode.installRejected, "插件目录包含越界路径")
            }
            let rel = String(full.dropFirst(resolvedRoot.count + 1))
            guard let clean = sanitizeRelativePath(rel) else {
                throw PluginHostError(PluginErrorCode.installRejected, "包含非法文件路径：\(rel)")
            }
            let data = try Data(contentsOf: url)
            guard data.count <= PluginLimits.maxFileBytes else {
                throw PluginHostError(PluginErrorCode.installRejected, "文件「\(clean)」超出 5 MB 上限")
            }
            totalBytes += data.count
            guard totalBytes <= PluginLimits.maxZipTotalBytes, results.count < PluginLimits.maxZipFiles else {
                throw PluginHostError(PluginErrorCode.installRejected, "插件文件总数或体积超出限制")
            }
            results.append(ZipExtractedEntry(relativePath: clean, data: data))
        }
        return results
    }

    static func sanitizeRelativePath(_ path: String) -> String? {
        let normalized = path.replacingOccurrences(of: "\\", with: "/")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty, !normalized.hasPrefix("/"), !normalized.contains("\0") else {
            return nil
        }
        let segments = normalized.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        var clean: [String] = []
        for seg in segments {
            if seg.isEmpty || seg == "." || seg == ".." { return nil }
            clean.append(seg)
        }
        return clean.joined(separator: "/")
    }

    private static func commonTopFolderPrefix(_ paths: [String]) -> String {
        if paths.contains(where: { $0 == "manifest.json" }) { return "" }
        guard let firstSlash = paths.first?.firstIndex(of: "/") else { return "" }
        let candidate = String(paths[0][...firstSlash])
        if paths.allSatisfy({ $0.hasPrefix(candidate) }),
           paths.contains(where: { $0 == candidate + "manifest.json" }) {
            return candidate
        }
        return ""
    }

    private static func decompress(_ input: Data, method: UInt16, expectedSize: Int, fileName: String) throws -> Data {
        if method == 0 {
            guard input.count == expectedSize || expectedSize == 0 else {
                throw PluginHostError(PluginErrorCode.installRejected, "ZIP 条目大小校验失败：\(fileName)")
            }
            return input
        }
        guard method == 8 else {
            throw PluginHostError(PluginErrorCode.installRejected, "不支持的 ZIP 压缩算法（method=\(method)）：\(fileName)")
        }
        if expectedSize == 0 { return Data() }

        let cap = max(expectedSize, 64)
        var dst = Data(count: cap)
        let decodedCount: Int = dst.withUnsafeMutableBytes { dstBuf in
            input.withUnsafeBytes { srcBuf in
                guard let dstPtr = dstBuf.baseAddress?.assumingMemoryBound(to: UInt8.self),
                      let srcPtr = srcBuf.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                    return 0
                }
                return compression_decode_buffer(dstPtr, cap, srcPtr, input.count, nil, COMPRESSION_ZLIB)
            }
        }
        guard decodedCount > 0 else {
            throw PluginHostError(PluginErrorCode.installRejected, "无法解压 ZIP 条目：\(fileName)")
        }
        dst.count = decodedCount
        return dst
    }

    private static func findEndOfCentralDirectory(in data: Data) -> Int {
        guard data.count >= 22 else { return -1 }
        let minOffset = max(0, data.count - 65_557)
        var pos = data.count - 22
        while pos >= minOffset {
            if readUInt32LE(data, at: pos) == 0x06054B50 {
                return pos
            }
            pos -= 1
        }
        return -1
    }

    private static func readUInt16LE(_ data: Data, at offset: Int) -> UInt16 {
        UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
    }

    private static func readUInt32LE(_ data: Data, at offset: Int) -> UInt32 {
        UInt32(data[offset])
            | (UInt32(data[offset + 1]) << 8)
            | (UInt32(data[offset + 2]) << 16)
            | (UInt32(data[offset + 3]) << 24)
    }
}
