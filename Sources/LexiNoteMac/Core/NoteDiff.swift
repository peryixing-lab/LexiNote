import Foundation

// MARK: - Snapshot hash & line diff engine

enum RevisionReason: String, Codable, Hashable, CaseIterable {
    case autosave = "autosave"
    case manual = "manual"
    case restoreBackup = "restore-backup"
    case conflictBackup = "conflict-backup"
    case crashRecovery = "crash-recovery"

    var label: String {
        switch self {
        case .autosave: return "自动快照"
        case .manual: return "手动快照"
        case .restoreBackup: return "恢复前备份"
        case .conflictBackup: return "冲突备份"
        case .crashRecovery: return "异常恢复"
        }
    }
}

enum DiffLineKind: String, Hashable {
    case same
    case added
    case removed
}

struct NoteDiffLine: Identifiable, Hashable {
    let id: Int
    let kind: DiffLineKind
    let text: String
    let oldLineNumber: Int?
    let newLineNumber: Int?
}

struct NoteDiffResult: Hashable {
    let titleChanged: Bool
    let oldTitle: String
    let newTitle: String
    let tagsChanged: Bool
    let oldTags: [String]
    let newTags: [String]
    let addedCount: Int
    let removedCount: Int
    let unchangedCount: Int
    let lines: [NoteDiffLine]

    var hasAnyChange: Bool {
        titleChanged || tagsChanged || addedCount > 0 || removedCount > 0
    }
}

enum NoteHistoryHash {
    static func normalize(_ text: String) -> String {
        text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
    }

    static func byteSize(of text: String) -> Int {
        text.lengthOfBytes(using: .utf8)
    }

    static func canonicalPayload(title: String,
                                 content: String,
                                 tags: [String],
                                 properties: [NoteProperty] = []) -> String {
        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedContent = normalize(content)
        let normalizedTags = tags.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .sorted()
            .joined(separator: ",")
        let normalizedProps = properties
            .map { "\($0.key)=\($0.value)" }
            .sorted()
            .joined(separator: ";")
        return "\(normalizedTitle)\u{0000}\(normalizedTags)\u{0000}\(normalizedProps)\u{0000}\(normalizedContent)"
    }

    static func computeSnapshotHash(title: String,
                                    content: String,
                                    tags: [String],
                                    properties: [NoteProperty] = []) -> String {
        let payload = canonicalPayload(title: title, content: content, tags: tags, properties: properties)
        var hash: UInt64 = 0xcbf29ce484222325
        let prime: UInt64 = 0x100000001b3
        for byte in payload.utf8 {
            hash ^= UInt64(byte)
            hash &*= prime
        }
        return String(format: "%016llx-%d", hash, payload.utf8.count)
    }

    static func computeNoteHash(_ note: Note) -> String {
        computeSnapshotHash(title: note.title,
                            content: note.content,
                            tags: note.tags,
                            properties: note.properties)
    }

    static func formatBytes(_ bytes: Int) -> String {
        let safe = max(0, bytes)
        if safe < 1024 { return "\(safe) B" }
        let kb = Double(safe) / 1024.0
        if kb < 1024 { return String(format: "%.1f KB", kb) }
        let mb = kb / 1024.0
        if mb < 1024 { return String(format: "%.2f MB", mb) }
        return String(format: "%.2f GB", mb / 1024.0)
    }
}

enum NoteDiffEngine {
    static func diff(oldTitle: String,
                     oldContent: String,
                     oldTags: [String],
                     newTitle: String,
                     newContent: String,
                     newTags: [String]) -> NoteDiffResult {
        let oldLines = NoteHistoryHash.normalize(oldContent).components(separatedBy: "\n")
        let newLines = NoteHistoryHash.normalize(newContent).components(separatedBy: "\n")

        var prefix = 0
        while prefix < oldLines.count,
              prefix < newLines.count,
              oldLines[prefix] == newLines[prefix] {
            prefix += 1
        }

        var suffix = 0
        while (oldLines.count - suffix) > prefix,
              (newLines.count - suffix) > prefix,
              oldLines[oldLines.count - 1 - suffix] == newLines[newLines.count - 1 - suffix] {
            suffix += 1
        }

        let oldMid = Array(oldLines[prefix..<(oldLines.count - suffix)])
        let newMid = Array(newLines[prefix..<(newLines.count - suffix)])

        var resultLines: [NoteDiffLine] = []
        resultLines.reserveCapacity(oldLines.count + newLines.count)
        var nextID = 0
        var addedCount = 0
        var removedCount = 0
        var unchangedCount = 0

        func push(_ kind: DiffLineKind, text: String, oldLine: Int?, newLine: Int?) {
            resultLines.append(NoteDiffLine(id: nextID,
                                            kind: kind,
                                            text: text,
                                            oldLineNumber: oldLine,
                                            newLineNumber: newLine))
            nextID += 1
            switch kind {
            case .same: unchangedCount += 1
            case .added: addedCount += 1
            case .removed: removedCount += 1
            }
        }

        for idx in 0..<prefix {
            push(.same, text: oldLines[idx], oldLine: idx + 1, newLine: idx + 1)
        }

        if oldMid.isEmpty {
            for idx in 0..<newMid.count {
                push(.added, text: newMid[idx], oldLine: nil, newLine: prefix + idx + 1)
            }
        } else if newMid.isEmpty {
            for idx in 0..<oldMid.count {
                push(.removed, text: oldMid[idx], oldLine: prefix + idx + 1, newLine: nil)
            }
        } else if oldMid.count * newMid.count <= 160_000 {
            let m = oldMid.count
            let n = newMid.count
            var dp = Array(repeating: Array(repeating: 0, count: n + 1), count: m + 1)
            for i in stride(from: m - 1, through: 0, by: -1) {
                for j in stride(from: n - 1, through: 0, by: -1) {
                    if oldMid[i] == newMid[j] {
                        dp[i][j] = dp[i + 1][j + 1] + 1
                    } else {
                        dp[i][j] = max(dp[i + 1][j], dp[i][j + 1])
                    }
                }
            }
            var i = 0
            var j = 0
            while i < m && j < n {
                if oldMid[i] == newMid[j] {
                    push(.same, text: oldMid[i], oldLine: prefix + i + 1, newLine: prefix + j + 1)
                    i += 1
                    j += 1
                } else if dp[i + 1][j] >= dp[i][j + 1] {
                    push(.removed, text: oldMid[i], oldLine: prefix + i + 1, newLine: nil)
                    i += 1
                } else {
                    push(.added, text: newMid[j], oldLine: nil, newLine: prefix + j + 1)
                    j += 1
                }
            }
            while i < m {
                push(.removed, text: oldMid[i], oldLine: prefix + i + 1, newLine: nil)
                i += 1
            }
            while j < n {
                push(.added, text: newMid[j], oldLine: nil, newLine: prefix + j + 1)
                j += 1
            }
        } else {
            // Bounded lookahead fallback for very large files to stay responsive.
            var i = 0
            var j = 0
            let lookahead = 32
            while i < oldMid.count && j < newMid.count {
                if oldMid[i] == newMid[j] {
                    push(.same, text: oldMid[i], oldLine: prefix + i + 1, newLine: prefix + j + 1)
                    i += 1
                    j += 1
                    continue
                }
                var foundNewMatch: Int?
                let maxSearchJ = min(newMid.count, j + lookahead)
                for k in (j + 1)..<maxSearchJ where newMid[k] == oldMid[i] {
                    foundNewMatch = k
                    break
                }
                var foundOldMatch: Int?
                let maxSearchI = min(oldMid.count, i + lookahead)
                for k in (i + 1)..<maxSearchI where oldMid[k] == newMid[j] {
                    foundOldMatch = k
                    break
                }
                if let matchJ = foundNewMatch,
                   foundOldMatch == nil || (matchJ - j) <= (foundOldMatch! - i) {
                    while j < matchJ {
                        push(.added, text: newMid[j], oldLine: nil, newLine: prefix + j + 1)
                        j += 1
                    }
                } else if let matchI = foundOldMatch {
                    while i < matchI {
                        push(.removed, text: oldMid[i], oldLine: prefix + i + 1, newLine: nil)
                        i += 1
                    }
                } else {
                    push(.removed, text: oldMid[i], oldLine: prefix + i + 1, newLine: nil)
                    push(.added, text: newMid[j], oldLine: nil, newLine: prefix + j + 1)
                    i += 1
                    j += 1
                }
            }
            while i < oldMid.count {
                push(.removed, text: oldMid[i], oldLine: prefix + i + 1, newLine: nil)
                i += 1
            }
            while j < newMid.count {
                push(.added, text: newMid[j], oldLine: nil, newLine: prefix + j + 1)
                j += 1
            }
        }

        let suffixOldStart = oldLines.count - suffix
        let suffixNewStart = newLines.count - suffix
        for idx in 0..<suffix {
            push(.same,
                 text: oldLines[suffixOldStart + idx],
                 oldLine: suffixOldStart + idx + 1,
                 newLine: suffixNewStart + idx + 1)
        }

        return NoteDiffResult(titleChanged: oldTitle != newTitle,
                              oldTitle: oldTitle,
                              newTitle: newTitle,
                              tagsChanged: oldTags.sorted() != newTags.sorted(),
                              oldTags: oldTags,
                              newTags: newTags,
                              addedCount: addedCount,
                              removedCount: removedCount,
                              unchangedCount: unchangedCount,
                              lines: resultLines)
    }
}
