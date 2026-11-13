import Foundation

enum PluginManifestService {
    private static let idPattern = try! NSRegularExpression(pattern: "^[a-z0-9][a-z0-9._-]{0,63}$")
    private static let allowedTargets: Set<String> = ["macos", "desktop", "harmonyos", "all"]

    static func parseAndValidate(entries: [ZipExtractedEntry]) throws -> PluginManifest {
        guard let manifestEntry = entries.first(where: { $0.relativePath == "manifest.json" }),
              let rawJson = String(data: manifestEntry.data, encoding: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: manifestEntry.data) as? [String: Any] else {
            throw PluginHostError(PluginErrorCode.installRejected, "插件缺少有效的 manifest.json")
        }

        let rawID = (obj["id"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard isValidPluginId(rawID) else {
            throw PluginHostError(PluginErrorCode.installRejected, "插件 ID 格式无效：仅允许小写字母、数字、点、下划线与连字符")
        }

        let name = (obj["name"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 120 else {
            throw PluginHostError(PluginErrorCode.installRejected, "插件名称不能为空且不超过 120 字")
        }

        let version = (obj["version"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !version.isEmpty, version.count <= 40 else {
            throw PluginHostError(PluginErrorCode.installRejected, "插件版本号缺失")
        }

        let lexinoteSection = obj["lexinote"] as? [String: Any]
        let explicitFormat = (obj["format"] as? String ?? "").lowercased()
        let explicitKind = ((obj["kind"] as? String) ?? (lexinoteSection?["kind"] as? String) ?? "").lowercased()
        let declaredCapsRaw = (obj["capabilities"] as? [String])
            ?? (lexinoteSection?["capabilities"] as? [String])
        let kind: PluginKind
        if explicitKind == "lexinote" || explicitFormat.hasPrefix("lexinote") || declaredCapsRaw != nil || lexinoteSection != nil {
            kind = .lexinote
        } else {
            kind = .obsidian
        }

        let mainRel = ((obj["main"] as? String) ?? (lexinoteSection?["main"] as? String) ?? "main.js")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let cleanMain = PluginZip.sanitizeRelativePath(mainRel) else {
            throw PluginHostError(PluginErrorCode.installRejected, "插件入口路径不合法：\(mainRel)")
        }
        guard let mainEntry = entries.first(where: { $0.relativePath == cleanMain }) else {
            throw PluginHostError(PluginErrorCode.installRejected, "插件包缺少入口脚本：\(cleanMain)")
        }

        var stylesRel: String?
        if let rawStyles = (obj["styles"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !rawStyles.isEmpty {
            guard let cleanStyles = PluginZip.sanitizeRelativePath(rawStyles) else {
                throw PluginHostError(PluginErrorCode.installRejected, "插件样式路径不合法：\(rawStyles)")
            }
            if entries.contains(where: { $0.relativePath == cleanStyles }) {
                stylesRel = cleanStyles
            }
        } else if entries.contains(where: { $0.relativePath == "styles.css" }) {
            stylesRel = "styles.css"
        }

        let targets = (obj["targets"] as? [String])
            ?? (lexinoteSection?["targets"] as? [String])
            ?? []
        if !targets.isEmpty {
            let normalizedTargets = Set(targets.map { $0.lowercased() })
            if normalizedTargets.isDisjoint(with: allowedTargets) {
                throw PluginHostError(PluginErrorCode.installRejected, "插件目标平台与 macOS 不兼容：\(targets.joined(separator: ", "))")
            }
        }

        var capabilities: [String] = []
        if let caps = declaredCapsRaw {
            for cap in caps {
                let trimmed = cap.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed == "network" {
                    throw PluginHostError(PluginErrorCode.installRejected, "禁止插件声明直接网络访问能力（network）；请改用宿主代理 ai.inference")
                }
                guard PluginCapability(rawValue: trimmed) != nil else {
                    throw PluginHostError(PluginErrorCode.installRejected, "插件声明了未知权限：\(trimmed)")
                }
                if !capabilities.contains(trimmed) {
                    capabilities.append(trimmed)
                }
            }
        } else {
            // Obsidian plugins inherit the standard desktop compatibility capability set,
            // subject to per-workspace deny-by-default approval before running.
            capabilities = [
                PluginCapability.vaultRead.rawValue,
                PluginCapability.vaultWrite.rawValue,
                PluginCapability.notesMetadataRead.rawValue,
                PluginCapability.editorRead.rawValue,
                PluginCapability.editorWrite.rawValue,
                PluginCapability.workspaceViews.rawValue,
                PluginCapability.uiCommands.rawValue,
                PluginCapability.uiViews.rawValue,
                PluginCapability.uiModal.rawValue,
                PluginCapability.uiNotice.rawValue,
                PluginCapability.pluginStorage.rawValue
            ]
        }

        var commands: [PluginCommandDeclaration] = []
        let rawCommands = (obj["commands"] as? [[String: Any]])
            ?? (lexinoteSection?["commands"] as? [[String: Any]])
            ?? []
        for item in rawCommands {
            let cid = (item["id"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let cname = (item["name"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !cid.isEmpty && !cname.isEmpty {
                commands.append(PluginCommandDeclaration(
                    id: cid,
                    name: cname,
                    hotkeys: item["hotkeys"] as? [String]
                ))
            }
        }

        var views: [PluginViewDeclaration] = []
        let rawViews = (obj["views"] as? [[String: Any]])
            ?? (lexinoteSection?["views"] as? [[String: Any]])
            ?? []
        for item in rawViews {
            let vid = (item["id"] as? String ?? item["type"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let vtype = (item["type"] as? String ?? vid).trimmingCharacters(in: .whitespacesAndNewlines)
            let vtitle = (item["title"] as? String ?? vid).trimmingCharacters(in: .whitespacesAndNewlines)
            let vEntry = (item["entry"] as? String).flatMap { PluginZip.sanitizeRelativePath($0) }
            if let vEntry, !entries.contains(where: { $0.relativePath == vEntry }) {
                throw PluginHostError(PluginErrorCode.installRejected, "插件视图入口文件缺失：\(vEntry)")
            }
            if !vid.isEmpty {
                views.append(PluginViewDeclaration(
                    id: vid,
                    type: vtype,
                    title: vtitle,
                    icon: item["icon"] as? String,
                    location: item["location"] as? String,
                    entry: vEntry
                ))
            }
        }

        var warnings = scanWarnings(mainData: mainEntry.data, kind: kind, entries: entries)
        if obj["isDesktopOnly"] as? Bool == true {
            warnings.append("插件标记 isDesktopOnly=true（macOS 桌面环境已满足，但部分 Node/Electron 专属接口可能受限）")
        }

        return PluginManifest(
            id: rawID,
            name: name,
            version: version,
            kind: kind,
            description: obj["description"] as? String ?? "",
            author: obj["author"] as? String ?? "",
            authorUrl: obj["authorUrl"] as? String,
            minAppVersion: obj["minAppVersion"] as? String,
            main: cleanMain,
            styles: stylesRel,
            capabilities: capabilities,
            commands: commands,
            views: views,
            targets: targets,
            isDesktopOnly: obj["isDesktopOnly"] as? Bool ?? false,
            warnings: warnings,
            rawJson: rawJson
        )
    }

    static func isValidPluginId(_ id: String) -> Bool {
        let range = NSRange(location: 0, length: (id as NSString).length)
        return idPattern.firstMatch(in: id, options: [], range: range) != nil
    }

    private static func scanWarnings(mainData: Data, kind: PluginKind, entries: [ZipExtractedEntry]) -> [String] {
        guard let source = String(data: mainData, encoding: .utf8) else { return [] }
        var warnings: [String] = []
        let patterns: [(String, String)] = [
            ("require(\"child_process\")", "检测到 child_process 调用，macOS 插件沙盒已屏蔽子进程启动"),
            ("require('child_process')", "检测到 child_process 调用，macOS 插件沙盒已屏蔽子进程启动"),
            ("require(\"fs\")", "检测到 Node fs 调用，沙盒中仅支持通过 Vault API 访问当前工作区"),
            ("require('fs')", "检测到 Node fs 调用，沙盒中仅支持通过 Vault API 访问当前工作区"),
            ("require(\"electron\")", "检测到 Electron 原生 API 引用，已通过兼容垫片降级处理"),
            ("require('electron')", "检测到 Electron 原生 API 引用，已通过兼容垫片降级处理"),
            ("require(\"http\")", "检测到 Node http/https 调用，沙盒环境禁止插件直接联网"),
            ("require('https')", "检测到 Node https 调用，沙盒环境禁止插件直接联网")
        ]
        for (needle, msg) in patterns where source.contains(needle) {
            if !warnings.contains(msg) { warnings.append(msg) }
        }
        if kind == .obsidian && entries.count > 1 && source.contains("fetch(") {
            warnings.append("检测到 fetch 网络请求；沙盒默认拦截外网直连")
        }
        return warnings
    }
}
