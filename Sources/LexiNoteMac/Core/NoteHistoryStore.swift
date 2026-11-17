import Foundation
import Darwin

// MARK: - Safe atomic disk I/O & disk-full detection

enum LexiSafeIO {
    /// Test hook signature for injecting write/rename failures before atomic commit.
    typealias WriteHook = (_ data: Data, _ tempURL: URL, _ targetURL: URL) throws -> Void

    static func isDiskFullError(_ error: Error) -> Bool {
        var visited: [NSError] = [error as NSError]
        var idx = 0
        while idx < visited.count {
            let current = visited[idx]
            idx += 1
            if current.domain == NSPOSIXErrorDomain &&
                (current.code == Int(ENOSPC) || current.code == Int(EDQUOT)) {
                return true
            }
            if current.domain == NSCocoaErrorDomain &&
                current.code == NSFileWriteOutOfSpaceError {
                return true
            }
            let desc = current.localizedDescription.lowercased()
            if desc.contains("no space left") ||
                desc.contains("out of space") ||
                desc.contains("enospc") ||
                desc.contains("edquot") ||
                desc.contains("磁盘空间") {
                return true
            }
            if let underlying = current.userInfo[NSUnderlyingErrorKey] as? NSError {
                visited.append(underlying)
            }
            if let multiple = current.userInfo[NSMultipleUnderlyingErrorsKey] as? [NSError] {
                visited.append(contentsOf: multiple)
            }
        }
        return false
    }

    static func friendlyWriteError(_ error: Error, target: String? = nil) -> String {
        let label = target.map { "「\($0)」" } ?? "文件"
        if isDiskFullError(error) {
            return "磁盘空间不足，无法写入\(label)，请清理磁盘空间后重试"
        }
        return "无法写入\(label)：\(error.localizedDescription)"
    }

    static func atomicWriteData(_ data: Data,
                                to targetURL: URL,
                                hook: WriteHook? = nil) throws {
        let dirURL = targetURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dirURL, withIntermediateDirectories: true)

        let tempName = ".lexi-tmp-\(UUID().uuidString.lowercased())"
        let tempURL = dirURL.appendingPathComponent(tempName, isDirectory: false)
        defer {
            if FileManager.default.fileExists(atPath: tempURL.path) {
                try? FileManager.default.removeItem(at: tempURL)
            }
        }

        FileManager.default.createFile(atPath: tempURL.path, contents: nil, attributes: nil)
        let handle = try FileHandle(forWritingTo: tempURL)
        do {
            try handle.write(contentsOf: data)
            try handle.synchronize()
            try handle.close()
        } catch {
            try? handle.close()
            throw error
        }

        if let hook {
            try hook(data, tempURL, targetURL)
        }

        if Darwin.rename(tempURL.path, targetURL.path) != 0 {
            let code = POSIXErrorCode(rawValue: errno) ?? .EIO
            throw POSIXError(code)
        }
    }

    static func atomicWriteText(_ text: String,
                                to targetURL: URL,
                                hook: WriteHook? = nil) throws {
        guard let data = text.data(using: .utf8) else {
            throw CocoaError(.fileWriteInapplicableStringEncoding)
        }
        try atomicWriteData(data, to: targetURL, hook: hook)
    }
}

// MARK: - History models & retention policy

struct NoteRevision: Identifiable, Codable, Hashable {
    var id: String
    var noteID: String
    var vaultID: String
    var title: String
    var content: String
    var tags: [String]
    var properties: [NoteProperty]
    var notebook: String
    var reason: RevisionReason
    var contentHash: String
    var byteSize: Int
    var createdAt: Date

    var previewText: String {
        let cleaned = content
            .replacingOccurrences(of: "\r\n", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .prefix(2)
            .joined(separator: " ")
        return cleaned.isEmpty ? "（空白内容）" : String(cleaned.prefix(120))
    }
}

struct HistoryRetentionPolicy: Codable, Hashable {
    var maxAgeDays: Int
    var maxCountPerNote: Int
    var maxBytesPerNote: Int
    var maxTotalBytes: Int

    static let `default` = HistoryRetentionPolicy(
        maxAgeDays: 30,
        maxCountPerNote: 30,
        maxBytesPerNote: 2 * 1024 * 1024,
        maxTotalBytes: 50 * 1024 * 1024
    )

    func clamped() -> HistoryRetentionPolicy {
        HistoryRetentionPolicy(
            maxAgeDays: min(365, max(1, maxAgeDays)),
            maxCountPerNote: min(500, max(1, maxCountPerNote)),
            maxBytesPerNote: min(128 * 1024 * 1024, max(4 * 1024, maxBytesPerNote)),
            maxTotalBytes: min(1024 * 1024 * 1024, max(16 * 1024, maxTotalBytes))
        )
    }
}

struct HistoryUsageSummary: Hashable {
    var noteCount: Int
    var revisionCount: Int
    var totalBytes: Int
}

struct CrashRecoveryDraft: Identifiable, Codable, Hashable {
    var noteID: String
    var vaultID: String
    var title: String
    var content: String
    var tags: [String]
    var properties: [NoteProperty]
    var notebook: String
    var baseHash: String
    var updatedAt: Date

    var id: String { noteID }
}

enum ConflictResolutionMode {
    case keepMineBackupTheirs
    case takeTheirsBackupMine
    case saveConflictCopy
}

struct NoteConflictInfo: Identifiable, Hashable {
    var noteID: String
    var sourceLabel: String
    var mineTitle: String
    var mineContent: String
    var mineTags: [String]
    var mineProperties: [NoteProperty]
    var mineNotebook: String
    var theirsTitle: String
    var theirsContent: String
    var theirsTags: [String]
    var theirsProperties: [NoteProperty]
    var theirsNotebook: String
    var detectedAt: Date

    var id: String { noteID }
}

// MARK: - Per-note snapshot & WAL store

@MainActor
final class NoteHistoryStore {
    private struct NoteHistoryEnvelope: Codable {
        var noteID: String
        var revisions: [NoteRevision]
    }

    let storageRoot: URL
    let inMemory: Bool
    var writeHook: LexiSafeIO.WriteHook?

    private var memoryHistory: [String: [NoteRevision]] = [:]
    private var memoryWal: [String: CrashRecoveryDraft] = [:]

    private let encoder: JSONEncoder = {
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys]
        enc.dateEncodingStrategy = .iso8601
        return enc
    }()

    private let decoder: JSONDecoder = {
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return dec
    }()

    init(storageRoot: URL, inMemory: Bool = false) {
        self.storageRoot = storageRoot
        self.inMemory = inMemory
    }

    var historyDir: URL { storageRoot.appendingPathComponent(".lexinote-history", isDirectory: true) }
    var recoveryDir: URL { storageRoot.appendingPathComponent(".lexinote-recovery", isDirectory: true) }

    // MARK: Queries

    func revisions(for noteID: String) -> [NoteRevision] {
        if inMemory {
            return (memoryHistory[noteID] ?? []).sorted { $0.createdAt > $1.createdAt }
        }
        let url = historyFileURL(for: noteID)
        guard let data = try? Data(contentsOf: url) else { return [] }
        if let envelope = try? decoder.decode(NoteHistoryEnvelope.self, from: data) {
            return envelope.revisions.sorted { $0.createdAt > $1.createdAt }
        }
        return []
    }

    func usageSummary() -> HistoryUsageSummary {
        let all = loadAllNoteHistories()
        var noteCount = 0
        var revCount = 0
        var totalBytes = 0
        for (_, list) in all where !list.isEmpty {
            noteCount += 1
            revCount += list.count
            totalBytes += list.reduce(0) { $0 + max(0, $1.byteSize) }
        }
        return HistoryUsageSummary(noteCount: noteCount, revisionCount: revCount, totalBytes: totalBytes)
    }

    // MARK: Snapshots & pruning

    @discardableResult
    func recordRevision(for note: Note,
                        reason: RevisionReason,
                        policy: HistoryRetentionPolicy,
                        now: Date = Date()) -> (revision: NoteRevision?, warning: String?) {
        let clampedPolicy = policy.clamped()
        var current = revisions(for: note.id)
        let normalizedContent = NoteHistoryHash.normalize(note.content)
        let hash = NoteHistoryHash.computeSnapshotHash(title: note.title,
                                                       content: normalizedContent,
                                                       tags: note.tags,
                                                       properties: note.properties)
        if let latest = current.first, latest.contentHash == hash {
            return (latest, nil)
        }

        let payloadBytes = NoteHistoryHash.byteSize(of: note.title)
            + NoteHistoryHash.byteSize(of: normalizedContent)
            + note.tags.reduce(0) { $0 + NoteHistoryHash.byteSize(of: $1) }
            + note.properties.reduce(0) { $0 + NoteHistoryHash.byteSize(of: $1.key) + NoteHistoryHash.byteSize(of: $1.value) }
            + 64

        let revision = NoteRevision(
            id: "rev-\(UUID().uuidString.lowercased())",
            noteID: note.id,
            vaultID: note.vaultID,
            title: note.title,
            content: normalizedContent,
            tags: note.tags,
            properties: note.properties,
            notebook: note.notebook,
            reason: reason,
            contentHash: hash,
            byteSize: max(64, payloadBytes),
            createdAt: now
        )

        current.insert(revision, at: 0)
        current = pruneNoteRevisions(current, policy: clampedPolicy, now: now)

        if let warning = persistWithDiskFullCompaction(noteID: note.id,
                                                         revisions: current,
                                                         policy: clampedPolicy,
                                                         now: now) {
            return (nil, warning)
        }
        _ = enforceGlobalByteLimit(policy: clampedPolicy, now: now)
        return (revision, nil)
    }

    func deleteHistory(for noteID: String) {
        if inMemory {
            memoryHistory.removeValue(forKey: noteID)
            memoryWal.removeValue(forKey: noteID)
            return
        }
        let url = historyFileURL(for: noteID)
        try? FileManager.default.removeItem(at: url)
        clearWalDraft(for: noteID)
    }

    @discardableResult
    func pruneAll(policy: HistoryRetentionPolicy, now: Date = Date()) -> HistoryUsageSummary {
        let clampedPolicy = policy.clamped()
        var all = loadAllNoteHistories()
        for (noteID, list) in all {
            all[noteID] = pruneNoteRevisions(list, policy: clampedPolicy, now: now)
        }
        enforceGlobalCap(on: &all, maxTotalBytes: clampedPolicy.maxTotalBytes)
        saveAllHistories(all)

        var noteCount = 0
        var revCount = 0
        var totalBytes = 0
        for (_, list) in all where !list.isEmpty {
            noteCount += 1
            revCount += list.count
            totalBytes += list.reduce(0) { $0 + max(0, $1.byteSize) }
        }
        return HistoryUsageSummary(noteCount: noteCount, revisionCount: revCount, totalBytes: totalBytes)
    }

    func pruneNoteRevisions(_ list: [NoteRevision],
                            policy: HistoryRetentionPolicy,
                            now: Date = Date()) -> [NoteRevision] {
        let clamped = policy.clamped()
        let maxAgeSeconds = TimeInterval(clamped.maxAgeDays) * 86_400.0
        var sorted = list.sorted { $0.createdAt > $1.createdAt }
        sorted.removeAll { now.timeIntervalSince($0.createdAt) > maxAgeSeconds }
        if sorted.count > clamped.maxCountPerNote {
            sorted = Array(sorted.prefix(clamped.maxCountPerNote))
        }
        var totalBytes = sorted.reduce(0) { $0 + max(0, $1.byteSize) }
        while totalBytes > clamped.maxBytesPerNote && sorted.count > 1 {
            if let dropped = sorted.popLast() {
                totalBytes -= max(0, dropped.byteSize)
            }
        }
        return sorted
    }

    // MARK: Crash-recovery WAL

    @discardableResult
    func writeWalDraft(_ draft: CrashRecoveryDraft) -> String? {
        if inMemory {
            memoryWal[draft.noteID] = draft
            return nil
        }
        do {
            let data = try encoder.encode(draft)
            try LexiSafeIO.atomicWriteData(data, to: walFileURL(for: draft.noteID), hook: writeHook)
            return nil
        } catch {
            return LexiSafeIO.friendlyWriteError(error, target: "崩溃恢复日志")
        }
    }

    func clearWalDraft(for noteID: String) {
        if inMemory {
            memoryWal.removeValue(forKey: noteID)
            return
        }
        try? FileManager.default.removeItem(at: walFileURL(for: noteID))
    }

    func loadAllWalDrafts() -> [CrashRecoveryDraft] {
        if inMemory {
            return Array(memoryWal.values).sorted { $0.updatedAt > $1.updatedAt }
        }
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: recoveryDir,
            includingPropertiesForKeys: nil
        ) else {
            return []
        }
        var drafts: [CrashRecoveryDraft] = []
        for url in files where url.pathExtension.lowercased() == "json" {
            guard let data = try? Data(contentsOf: url),
                  let draft = try? decoder.decode(CrashRecoveryDraft.self, from: data) else {
                continue
            }
            drafts.append(draft)
        }
        return drafts.sorted { $0.updatedAt > $1.updatedAt }
    }

    // MARK: Internal helpers

    private func persistWithDiskFullCompaction(noteID: String,
                                               revisions: [NoteRevision],
                                               policy: HistoryRetentionPolicy,
                                               now: Date) -> String? {
        if inMemory {
            memoryHistory[noteID] = revisions
            return nil
        }
        do {
            try saveNoteHistory(noteID: noteID, revisions: revisions)
            return nil
        } catch {
            guard LexiSafeIO.isDiskFullError(error) else {
                return LexiSafeIO.friendlyWriteError(error, target: "版本历史")
            }
            // Attempt automatic compaction before reporting warning.
            var all = loadAllNoteHistories()
            for (otherID, otherList) in all where otherID != noteID {
                let compacted = pruneNoteRevisions(otherList, policy: policy, now: now)
                let trimmed = compacted.count > 2 ? Array(compacted.prefix(max(1, compacted.count / 2))) : compacted
                all[otherID] = trimmed
            }
            saveAllHistories(all)

            let reducedSelf = revisions.count > 1
                ? Array(revisions.prefix(max(1, min(revisions.count / 2, 5))))
                : revisions
            do {
                try saveNoteHistory(noteID: noteID, revisions: reducedSelf)
                return nil
            } catch let retryError {
                return LexiSafeIO.friendlyWriteError(retryError, target: "历史快照")
            }
        }
    }

    private func enforceGlobalByteLimit(policy: HistoryRetentionPolicy, now: Date) -> Bool {
        var all = loadAllNoteHistories()
        let changed = enforceGlobalCap(on: &all, maxTotalBytes: policy.maxTotalBytes)
        if changed {
            saveAllHistories(all)
        }
        return changed
    }

    @discardableResult
    private func enforceGlobalCap(on all: inout [String: [NoteRevision]], maxTotalBytes: Int) -> Bool {
        var changed = false
        var totalBytes = all.values.reduce(0) { sum, list in
            sum + list.reduce(0) { $0 + max(0, $1.byteSize) }
        }
        while totalBytes > maxTotalBytes {
            // Prefer trimming from notes with >1 snapshot first, then oldest overall.
            var candidateNoteID: String?
            var candidateDate = Date.distantFuture
            var foundMulti = false

            for (noteID, list) in all where !list.isEmpty {
                let oldest = list.last!
                let isMulti = list.count > 1
                if isMulti && !foundMulti {
                    foundMulti = true
                    candidateNoteID = noteID
                    candidateDate = oldest.createdAt
                } else if isMulti == foundMulti && oldest.createdAt < candidateDate {
                    candidateNoteID = noteID
                    candidateDate = oldest.createdAt
                }
            }

            guard let dropNoteID = candidateNoteID,
                  var list = all[dropNoteID],
                  let dropped = list.popLast() else {
                break
            }
            all[dropNoteID] = list
            totalBytes -= max(0, dropped.byteSize)
            changed = true
        }
        return changed
    }

    private func loadAllNoteHistories() -> [String: [NoteRevision]] {
        if inMemory {
            return memoryHistory
        }
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: historyDir,
            includingPropertiesForKeys: nil
        ) else {
            return [:]
        }
        var map: [String: [NoteRevision]] = [:]
        for url in files where url.pathExtension.lowercased() == "json" {
            guard let data = try? Data(contentsOf: url),
                  let env = try? decoder.decode(NoteHistoryEnvelope.self, from: data) else {
                continue
            }
            map[env.noteID] = env.revisions.sorted { $0.createdAt > $1.createdAt }
        }
        return map
    }

    private func saveAllHistories(_ all: [String: [NoteRevision]]) {
        if inMemory {
            memoryHistory = all.filter { !$0.value.isEmpty }
            return
        }
        for (noteID, list) in all {
            if list.isEmpty {
                try? FileManager.default.removeItem(at: historyFileURL(for: noteID))
            } else {
                try? saveNoteHistory(noteID: noteID, revisions: list)
            }
        }
    }

    private func saveNoteHistory(noteID: String, revisions: [NoteRevision]) throws {
        let url = historyFileURL(for: noteID)
        if revisions.isEmpty {
            try? FileManager.default.removeItem(at: url)
            return
        }
        let envelope = NoteHistoryEnvelope(noteID: noteID, revisions: revisions)
        let data = try encoder.encode(envelope)
        try LexiSafeIO.atomicWriteData(data, to: url, hook: writeHook)
    }

    private func historyFileURL(for noteID: String) -> URL {
        historyDir.appendingPathComponent("\(safeID(noteID)).json", isDirectory: false)
    }

    private func walFileURL(for noteID: String) -> URL {
        recoveryDir.appendingPathComponent("\(safeID(noteID)).json", isDirectory: false)
    }

    private func safeID(_ raw: String) -> String {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-")
        var sanitized = ""
        for scalar in raw.unicodeScalars {
            if allowed.contains(scalar) {
                sanitized.append(Character(scalar))
            } else {
                sanitized.append("_")
            }
        }
        if sanitized.isEmpty { sanitized = "note" }
        if sanitized == raw { return sanitized }
        let suffix = NoteHistoryHash.computeSnapshotHash(title: "", content: raw, tags: []).prefix(8)
        return "\(String(sanitized.prefix(48)))-\(suffix)"
    }
}
