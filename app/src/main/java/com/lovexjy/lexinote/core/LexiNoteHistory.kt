package com.lovexjy.lexinote.core

import kotlin.math.max
import kotlin.math.min

data class LexiHistoryRetentionPolicy(
    var maxAgeDays: Int = 30,
    var maxCountPerNote: Int = 30,
    var maxBytesPerNote: Int = 2 * 1024 * 1024,
    var maxTotalBytes: Int = 50 * 1024 * 1024
)

data class LexiHistoryUsageSummary(
    var noteCount: Int = 0,
    var revisionCount: Int = 0,
    var totalBytes: Int = 0
)

data class LexiHistoryNoteEntry(
    var noteId: String = "",
    var revisions: MutableList<NoteRevision> = mutableListOf()
)

data class LexiDiffLine(
    var kind: String = "equal", // 'equal' | 'add' | 'remove'
    var oldLine: Int = 0,
    var newLine: Int = 0,
    var text: String = ""
)

data class LexiDiffResult(
    var titleChanged: Boolean = false,
    var oldTitle: String = "",
    var newTitle: String = "",
    var tagsChanged: Boolean = false,
    var oldTags: MutableList<String> = mutableListOf(),
    var newTags: MutableList<String> = mutableListOf(),
    var addedCount: Int = 0,
    var removedCount: Int = 0,
    var unchangedCount: Int = 0,
    var lines: MutableList<LexiDiffLine> = mutableListOf()
)

data class LexiDraftWalEntry(
    var noteId: String = "",
    var vaultId: String = "",
    var projectId: String = "",
    var title: String = "",
    var content: String = "",
    var notebook: String = "速记收件箱",
    var editorLevel: String = "simple",
    var tags: MutableList<String> = mutableListOf(),
    var properties: MutableList<NoteProperty> = mutableListOf(),
    var baseTitle: String = "",
    var baseContent: String = "",
    var baseUpdatedAt: Long = 0L,
    var updatedAt: Long = 0L,
    var windowId: String = ""
)

data class LexiHistoryPruneResult(
    var entries: MutableList<LexiHistoryNoteEntry> = mutableListOf(),
    var removedCount: Int = 0,
    var totalBytes: Int = 0
)

private const val MILLIS_PER_DAY = 24L * 60L * 60L * 1000L

/**
 * Exact 1:1 port of LexiNoteHistory.ets.
 */
object LexiNoteHistory {
    fun defaultPolicy(): LexiHistoryRetentionPolicy = LexiHistoryRetentionPolicy()

    fun clampPolicy(raw: LexiHistoryRetentionPolicy): LexiHistoryRetentionPolicy {
        return LexiHistoryRetentionPolicy(
            maxAgeDays = max(1, min(365, if (raw.maxAgeDays > 0) raw.maxAgeDays else 30)),
            maxCountPerNote = max(3, min(200, if (raw.maxCountPerNote > 0) raw.maxCountPerNote else 30)),
            maxBytesPerNote = max(256 * 1024, min(20 * 1024 * 1024, if (raw.maxBytesPerNote > 0) raw.maxBytesPerNote else 2 * 1024 * 1024)),
            maxTotalBytes = max(1024 * 1024, min(500 * 1024 * 1024, if (raw.maxTotalBytes > 0) raw.maxTotalBytes else 50 * 1024 * 1024))
        )
    }

    fun utf8Bytes(text: String): Int {
        var total = 0
        var i = 0
        while (i < text.length) {
            val code = text[i].code
            when {
                code <= 0x7f -> total += 1
                code <= 0x7ff -> total += 2
                code in 0xd800..0xdbff -> {
                    total += 4
                    i += 1
                }
                else -> total += 3
            }
            i++
        }
        return total
    }

    fun fnv1aHex(text: String): String {
        var hash = 0x811c9dc5.toInt()
        for (i in text.indices) {
            hash = hash xor text[i].code
            hash *= 0x01000193
        }
        return hash.toUInt().toString(16).padStart(8, '0')
    }

    fun snapshotSignature(note: NoteItem): String {
        val props = note.properties.joinToString("|") { "${it.key}=${it.propValue}" }
        val tags = note.tags.joinToString(",")
        return "${note.title}\n---\n$tags\n---\n$props\n---\n${note.content}"
    }

    fun computeSnapshotHash(note: NoteItem): String {
        return fnv1aHex(snapshotSignature(note))
    }

    fun computeRevisionBytes(snapshot: NoteItem): Int {
        val raw = snapshotSignature(snapshot)
        return max(utf8Bytes(raw) + 128, 64)
    }

    fun cloneNote(note: NoteItem): NoteItem = note.deepCopy()

    fun normalizeRevision(raw: NoteRevision): NoteRevision {
        val snapshot = cloneNote(raw.snapshot)
        val savedAt = when {
            raw.savedAt > 0L -> raw.savedAt
            snapshot.updatedAt > 0L -> snapshot.updatedAt
            else -> System.currentTimeMillis()
        }
        return NoteRevision(
            id = raw.id,
            savedAt = savedAt,
            reason = raw.reason.ifEmpty { "autosave" },
            snapshot = snapshot,
            contentHash = raw.contentHash.ifEmpty { computeSnapshotHash(snapshot) },
            byteSize = if (raw.byteSize > 0) raw.byteSize else computeRevisionBytes(snapshot)
        )
    }

    fun buildRevision(id: String, snapshot: NoteItem, savedAt: Long, reason: String = "autosave"): NoteRevision {
        val cloned = cloneNote(snapshot)
        return NoteRevision(
            id = id,
            savedAt = if (savedAt > 0L) savedAt else System.currentTimeMillis(),
            reason = reason.ifEmpty { "autosave" },
            snapshot = cloned,
            contentHash = computeSnapshotHash(cloned),
            byteSize = computeRevisionBytes(cloned)
        )
    }

    fun sameContent(a: NoteItem, b: NoteItem): Boolean {
        if (a.title != b.title || a.content != b.content) return false
        val tagsA = a.tags.joinToString("\u0000")
        val tagsB = b.tags.joinToString("\u0000")
        if (tagsA != tagsB) return false
        val propsA = a.properties.joinToString("\u0000") { "${it.key}\u0001${it.propValue}" }
        val propsB = b.properties.joinToString("\u0000") { "${it.key}\u0001${it.propValue}" }
        return propsA == propsB
    }

    fun appendAndPrune(
        existing: List<NoteRevision>,
        candidate: NoteRevision,
        policy: LexiHistoryRetentionPolicy,
        now: Long = System.currentTimeMillis(),
        allowDuplicateReason: Boolean = false
    ): MutableList<NoteRevision> {
        val normalized = existing.map { normalizeRevision(it) }.sortedByDescending { it.savedAt }.toMutableList()
        val nextCandidate = normalizeRevision(candidate)
        if (!allowDuplicateReason && normalized.isNotEmpty() &&
            sameContent(normalized[0].snapshot, nextCandidate.snapshot)
        ) {
            if (nextCandidate.reason != "autosave" && normalized[0].reason == "autosave") {
                normalized[0].reason = nextCandidate.reason
                normalized[0].savedAt = max(normalized[0].savedAt, nextCandidate.savedAt)
            }
            return pruneRevisions(normalized, policy, now)
        }
        val combined = mutableListOf(nextCandidate).apply { addAll(normalized) }
        return pruneRevisions(combined, policy, now)
    }

    fun pruneRevisions(
        revisions: List<NoteRevision>,
        policy: LexiHistoryRetentionPolicy,
        now: Long = System.currentTimeMillis()
    ): MutableList<NoteRevision> {
        val clamped = clampPolicy(policy)
        val normalized = revisions.map { normalizeRevision(it) }.sortedByDescending { it.savedAt }
        if (normalized.isEmpty()) return mutableListOf()
        val minTimestamp = if (clamped.maxAgeDays > 0) now - clamped.maxAgeDays * MILLIS_PER_DAY else 0L
        val kept = mutableListOf<NoteRevision>()
        var usedBytes = 0
        for (entry in normalized) {
            if (kept.size >= clamped.maxCountPerNote) break
            if (minTimestamp > 0L && entry.savedAt in 1 until minTimestamp) continue
            if (kept.isNotEmpty() && usedBytes + entry.byteSize > clamped.maxBytesPerNote) break
            kept.add(entry)
            usedBytes += entry.byteSize
        }
        return kept
    }

    fun pruneAllEntries(
        entries: List<LexiHistoryNoteEntry>,
        policy: LexiHistoryRetentionPolicy,
        now: Long = System.currentTimeMillis()
    ): LexiHistoryPruneResult {
        val clamped = clampPolicy(policy)
        val result = LexiHistoryPruneResult()
        val working = mutableListOf<LexiHistoryNoteEntry>()
        var totalBytes = 0

        for (entry in entries) {
            val normalized = entry.revisions.map { normalizeRevision(it) }
            val pruned = pruneRevisions(normalized, clamped, now)
            result.removedCount += max(0, entry.revisions.size - pruned.size)
            if (pruned.isNotEmpty()) {
                working.add(LexiHistoryNoteEntry(entry.noteId, pruned))
                for (rev in pruned) {
                    totalBytes += rev.byteSize
                }
            }
        }

        while (totalBytes > clamped.maxTotalBytes) {
            var oldestNoteIdx = -1
            var oldestRevIdx = -1
            var oldestTime = Long.MAX_VALUE
            for (i in working.indices) {
                val list = working[i].revisions
                if (list.size <= 1) continue
                val idx = list.size - 1
                if (list[idx].savedAt <= oldestTime) {
                    oldestTime = list[idx].savedAt
                    oldestNoteIdx = i
                    oldestRevIdx = idx
                }
            }
            if (oldestNoteIdx < 0) {
                for (i in working.indices) {
                    val list = working[i].revisions
                    if (list.isEmpty()) continue
                    val idx = list.size - 1
                    if (list[idx].savedAt <= oldestTime) {
                        oldestTime = list[idx].savedAt
                        oldestNoteIdx = i
                        oldestRevIdx = idx
                    }
                }
            }
            if (oldestNoteIdx < 0 || oldestRevIdx < 0) break
            val evicted = working[oldestNoteIdx].revisions.removeAt(oldestRevIdx)
            totalBytes -= evicted.byteSize
            result.removedCount += 1
        }

        result.entries = working.filter { it.revisions.isNotEmpty() }.toMutableList()
        result.totalBytes = max(0, totalBytes)
        return result
    }

    fun summarize(entries: List<LexiHistoryNoteEntry>): LexiHistoryUsageSummary {
        val summary = LexiHistoryUsageSummary()
        for (entry in entries) {
            if (entry.revisions.isEmpty()) continue
            summary.noteCount += 1
            for (revRaw in entry.revisions) {
                val rev = normalizeRevision(revRaw)
                summary.revisionCount += 1
                summary.totalBytes += rev.byteSize
            }
        }
        return summary
    }

    fun diffVersions(
        oldTitle: String,
        oldContent: String,
        newTitle: String,
        newContent: String,
        oldTags: List<String> = emptyList(),
        newTags: List<String> = emptyList()
    ): LexiDiffResult {
        val result = LexiDiffResult(
            oldTitle = oldTitle,
            newTitle = newTitle,
            titleChanged = oldTitle.trim() != newTitle.trim(),
            oldTags = oldTags.toMutableList(),
            newTags = newTags.toMutableList(),
            tagsChanged = oldTags.joinToString(",") != newTags.joinToString(",")
        )
        val oldLines = if (oldContent.isEmpty()) emptyList() else oldContent.split("\n")
        val newLines = if (newContent.isEmpty()) emptyList() else newContent.split("\n")
        val rawDiff = computeLineDiff(oldLines, newLines)
        result.lines = rawDiff.toMutableList()
        for (line in rawDiff) {
            when (line.kind) {
                "add" -> result.addedCount += 1
                "remove" -> result.removedCount += 1
                else -> result.unchangedCount += 1
            }
        }
        return result
    }

    private fun computeLineDiff(oldLines: List<String>, newLines: List<String>): List<LexiDiffLine> {
        val n = oldLines.size
        val m = newLines.size
        if (n == 0 && m == 0) return emptyList()
        var prefix = 0
        while (prefix < n && prefix < m && oldLines[prefix] == newLines[prefix]) {
            prefix += 1
        }
        var suffix = 0
        while (suffix < n - prefix && suffix < m - prefix &&
            oldLines[n - 1 - suffix] == newLines[m - 1 - suffix]
        ) {
            suffix += 1
        }

        val lines = mutableListOf<LexiDiffLine>()
        for (i in 0 until prefix) {
            lines.add(LexiDiffLine("equal", i + 1, i + 1, oldLines[i]))
        }

        val midOldCount = n - prefix - suffix
        val midNewCount = m - prefix - suffix

        if (midOldCount.toLong() * midNewCount.toLong() <= 60000L) {
            val rows = midOldCount + 1
            val cols = midNewCount + 1
            val dp = IntArray(rows * cols)
            for (i in midOldCount - 1 downTo 0) {
                val aLine = oldLines[prefix + i]
                for (j in midNewCount - 1 downTo 0) {
                    if (aLine == newLines[prefix + j]) {
                        dp[i * cols + j] = dp[(i + 1) * cols + (j + 1)] + 1
                    } else {
                        val down = dp[(i + 1) * cols + j]
                        val right = dp[i * cols + (j + 1)]
                        dp[i * cols + j] = if (down >= right) down else right
                    }
                }
            }
            var i = 0
            var j = 0
            while (i < midOldCount || j < midNewCount) {
                if (i < midOldCount && j < midNewCount && oldLines[prefix + i] == newLines[prefix + j]) {
                    lines.add(LexiDiffLine("equal", prefix + i + 1, prefix + j + 1, oldLines[prefix + i]))
                    i += 1
                    j += 1
                } else if (j < midNewCount && (i == midOldCount || dp[i * cols + (j + 1)] >= dp[(i + 1) * cols + j])) {
                    lines.add(LexiDiffLine("add", 0, prefix + j + 1, newLines[prefix + j]))
                    j += 1
                } else {
                    lines.add(LexiDiffLine("remove", prefix + i + 1, 0, oldLines[prefix + i]))
                    i += 1
                }
            }
        } else {
            val anchorMap = mutableMapOf<String, MutableList<Int>>()
            for (j in 0 until midNewCount) {
                val key = newLines[prefix + j]
                anchorMap.getOrPut(key) { mutableListOf() }.add(j)
            }
            var oi = 0
            var ni = 0
            while (oi < midOldCount && ni < midNewCount) {
                if (oldLines[prefix + oi] == newLines[prefix + ni]) {
                    lines.add(LexiDiffLine("equal", prefix + oi + 1, prefix + ni + 1, oldLines[prefix + oi]))
                    oi += 1
                    ni += 1
                    continue
                }
                val matches = anchorMap[oldLines[prefix + oi]]
                var nextMatch = -1
                if (matches != null) {
                    for (k in matches) {
                        if (k >= ni && k - ni <= 64) {
                            nextMatch = k
                            break
                        }
                    }
                }
                if (nextMatch >= 0) {
                    while (ni < nextMatch) {
                        lines.add(LexiDiffLine("add", 0, prefix + ni + 1, newLines[prefix + ni]))
                        ni += 1
                    }
                } else {
                    lines.add(LexiDiffLine("remove", prefix + oi + 1, 0, oldLines[prefix + oi]))
                    oi += 1
                }
            }
            while (oi < midOldCount) {
                lines.add(LexiDiffLine("remove", prefix + oi + 1, 0, oldLines[prefix + oi]))
                oi += 1
            }
            while (ni < midNewCount) {
                lines.add(LexiDiffLine("add", 0, prefix + ni + 1, newLines[prefix + ni]))
                ni += 1
            }
        }

        for (s in suffix - 1 downTo 0) {
            val oldIdx = n - 1 - s
            val newIdx = m - 1 - s
            lines.add(LexiDiffLine("equal", oldIdx + 1, newIdx + 1, oldLines[oldIdx]))
        }
        return lines
    }

    fun reasonLabel(reason: String): String {
        return when (reason) {
            "manual" -> "手动快照"
            "restore-backup" -> "恢复前自动备份"
            "conflict-backup" -> "并发冲突备份"
            "crash-recovery" -> "异常退出恢复"
            else -> "自动保存"
        }
    }

    fun formatBytes(bytes: Int): String {
        if (bytes < 1024) return "$bytes B"
        if (bytes < 1024 * 1024) return String.format(java.util.Locale.US, "%.1f KB", bytes / 1024.0)
        return String.format(java.util.Locale.US, "%.2f MB", bytes / (1024.0 * 1024.0))
    }
}
