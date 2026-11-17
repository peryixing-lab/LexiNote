import SwiftUI

struct NoteHistorySheet: View {
    @ObservedObject var model: AppModel
    @ObservedObject var settings: SettingsStore
    let noteID: String

    @Environment(\.dismiss) private var dismiss
    @Environment(\.lexiPalette) private var palette

    private enum VersionChoice: Hashable {
        case currentLive
        case conflictMine
        case conflictTheirs
        case revision(String)
    }

    @State private var selectedRevisionID: String?
    @State private var baseChoice: VersionChoice?
    @State private var targetChoice: VersionChoice = .currentLive
    @State private var onlyChangedLines: Bool = false

    private var currentNote: Note? { model.note(noteID) }
    private var conflict: NoteConflictInfo? { model.noteConflict(for: noteID) }
    private var crashDraft: CrashRecoveryDraft? { model.crashRecoveryDraft(for: noteID) }
    private var revisions: [NoteRevision] {
        _ = model.historyRevisionTick
        return model.noteRevisions(for: noteID)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            if let conflict {
                conflictBanner(conflict)
            }
            if let crashDraft {
                crashBanner(crashDraft)
            }
            contentBody
        }
        .frame(width: 900, height: 610)
        .background(palette.workspacePage)
        .environment(\.lexiPalette, palette)
        .preferredColorScheme(settings.preferredColorScheme)
        .tint(palette.brand)
        .onAppear { syncDefaultSelections() }
        .onChange(of: model.historyRevisionTick) { _, _ in
            syncDefaultSelections()
        }
    }

    // MARK: Header & banners

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text("版本历史与差异对比")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(palette.textPrimary)
                    if let currentNote {
                        Text("· \(currentNote.displayTitle)")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(palette.textSecondary)
                            .lineLimit(1)
                    }
                }
                Text("保留 \(settings.historyMaxAgeDays) 天 · 每篇最多 \(settings.historyMaxCountPerNote) 条 · 恢复前自动备份当前内容")
                    .font(.system(size: 10.5))
                    .foregroundStyle(palette.textSecondary)
            }
            Spacer()
            Button {
                model.createManualSnapshot(for: noteID)
            } label: {
                Label("保存手动快照", systemImage: "camera")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(palette.brandInk)
                    .padding(.horizontal, 12)
                    .frame(height: 28)
                    .background(Capsule().fill(palette.brandSoft))
            }
            .buttonStyle(.plain)

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(palette.textSecondary)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 22)
        .frame(height: 60)
        .background(palette.workspaceTabs.opacity(0.6))
        .overlay(alignment: .bottom) {
            Rectangle().fill(palette.workspaceLine).frame(height: 0.5)
        }
    }

    private func conflictBanner(_ info: NoteConflictInfo) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 13))
                .foregroundStyle(palette.warning)
            VStack(alignment: .leading, spacing: 2) {
                Text("检测到\(info.sourceLabel)冲突，已暂停自动覆盖并备份双方内容")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(palette.textPrimary)
                Text("可直接对比「我的修改」与「最新/磁盘版本」，再安全合并或保留副本。")
                    .font(.system(size: 10.5))
                    .foregroundStyle(palette.textSecondary)
            }
            Spacer()
            Button("对比双方") {
                baseChoice = .conflictTheirs
                targetChoice = .conflictMine
            }
            .buttonStyle(.plain)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(palette.brandInk)
            .padding(.horizontal, 10)
            .frame(height: 25)
            .background(Capsule().fill(palette.brandSoft))

            Button("保留我的版本") {
                model.resolveNoteConflict(noteID, mode: .keepMineBackupTheirs)
            }
            .buttonStyle(.plain)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(palette.inverseText)
            .padding(.horizontal, 10)
            .frame(height: 25)
            .background(Capsule().fill(palette.brand))

            Button("采用最新/磁盘") {
                model.resolveNoteConflict(noteID, mode: .takeTheirsBackupMine)
            }
            .buttonStyle(.plain)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(palette.textPrimary)
            .padding(.horizontal, 10)
            .frame(height: 25)
            .background(Capsule().fill(palette.softSurface))

            Button("另存冲突副本") {
                model.resolveNoteConflict(noteID, mode: .saveConflictCopy)
            }
            .buttonStyle(.plain)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(palette.warning)
            .padding(.horizontal, 10)
            .frame(height: 25)
            .background(Capsule().fill(palette.warning.opacity(0.14)))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(palette.warning.opacity(0.10))
        .overlay(alignment: .bottom) {
            Rectangle().fill(palette.workspaceLine).frame(height: 0.5)
        }
    }

    private func crashBanner(_ draft: CrashRecoveryDraft) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.clockwise.heart")
                .font(.system(size: 13))
                .foregroundStyle(palette.brandInk)
            VStack(alignment: .leading, spacing: 2) {
                Text("已恢复上次异常退出前的未保存草稿（\(formatDate(draft.updatedAt))）")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(palette.textPrimary)
                Text("旧版本已在历史中备份，可对比后保留草稿或还原。")
                    .font(.system(size: 10.5))
                    .foregroundStyle(palette.textSecondary)
            }
            Spacer()
            Button("保留恢复草稿") {
                model.dismissCrashRecovery(noteID)
            }
            .buttonStyle(.plain)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(palette.brandInk)
            .padding(.horizontal, 10)
            .frame(height: 25)
            .background(Capsule().fill(palette.brandSoft))

            Button("还原异常前版本") {
                model.revertCrashRecovery(noteID)
            }
            .buttonStyle(.plain)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(palette.textSecondary)
            .padding(.horizontal, 10)
            .frame(height: 25)
            .background(Capsule().fill(palette.softSurface))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 9)
        .background(palette.brandSoft.opacity(0.5))
        .overlay(alignment: .bottom) {
            Rectangle().fill(palette.workspaceLine).frame(height: 0.5)
        }
    }

    // MARK: Split body

    private var contentBody: some View {
        HStack(spacing: 0) {
            revisionSidebar
                .frame(width: 280)
                .background(palette.workspaceSidebar.opacity(0.45))
                .overlay(alignment: .trailing) {
                    Rectangle().fill(palette.workspaceLine).frame(width: 0.5)
                }

            diffPanel
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var revisionSidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("历史快照")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(palette.textSecondary)
                Spacer()
                Text("\(revisions.count) 条")
                    .font(.system(size: 11))
                    .foregroundStyle(palette.textSecondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .overlay(alignment: .bottom) {
                Rectangle().fill(palette.workspaceLine.opacity(0.65)).frame(height: 0.5)
            }

            if revisions.isEmpty {
                Spacer()
                VStack(spacing: 10) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 26, weight: .light))
                        .foregroundStyle(palette.brandInk.opacity(0.7))
                    Text("暂无历史快照")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(palette.textPrimary)
                    Text("编辑并保存或点击右上角“保存手动快照”后会在这里记录每次修改。")
                        .font(.system(size: 11))
                        .foregroundStyle(palette.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 20)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(revisions) { rev in
                            revisionCard(rev)
                        }
                    }
                    .padding(10)
                }
                .scrollIndicators(.automatic)
            }
        }
    }

    private func revisionCard(_ rev: NoteRevision) -> some View {
        let isSelected = selectedRevisionID == rev.id
        return Button {
            selectedRevisionID = rev.id
            baseChoice = .revision(rev.id)
        } label: {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(formatDate(rev.createdAt))
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(palette.textPrimary)
                    Spacer()
                    Text(NoteHistoryHash.formatBytes(rev.byteSize))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(palette.textSecondary)
                }

                HStack(spacing: 6) {
                    reasonBadge(rev.reason)
                    Text(rev.title.isEmpty ? "无标题笔记" : rev.title)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(palette.textPrimary)
                        .lineLimit(1)
                }

                Text(rev.previewText)
                    .font(.system(size: 11))
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? palette.brandSoft.opacity(0.65) : palette.workspacePage)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(isSelected ? palette.brand : palette.workspaceLine, lineWidth: isSelected ? 1.2 : 0.6)
            )
        }
        .buttonStyle(.plain)
    }

    private func reasonBadge(_ reason: RevisionReason) -> some View {
        let color: Color
        switch reason {
        case .autosave: color = palette.brandInk
        case .manual: color = palette.success
        case .restoreBackup: color = palette.brand
        case .conflictBackup: color = palette.warning
        case .crashRecovery: color = palette.error
        }
        return Text(reason.label)
            .font(.system(size: 9.5, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.12)))
    }

    // MARK: Diff panel

    private var diffPanel: some View {
        let baseData = resolvePayload(baseChoice)
        let targetData = resolvePayload(targetChoice)
        let diff = NoteDiffEngine.diff(
            oldTitle: baseData.title,
            oldContent: baseData.content,
            oldTags: baseData.tags,
            newTitle: targetData.title,
            newContent: targetData.content,
            newTags: targetData.tags
        )
        let visibleLines = onlyChangedLines ? diff.lines.filter { $0.kind != .same } : diff.lines

        return VStack(spacing: 0) {
            diffControlsBar(diff: diff)

            if diff.titleChanged || diff.tagsChanged {
                metadataDiffStrip(diff: diff)
            }

            if visibleLines.isEmpty {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 24, weight: .light))
                        .foregroundStyle(palette.success)
                    Text(diff.hasAnyChange ? "正文中没有行级文本差异" : "所选两个版本内容完全一致")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(palette.textSecondary)
                }
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(visibleLines) { line in
                            diffLineRow(line)
                        }
                    }
                    .padding(.vertical, 6)
                }
                .scrollIndicators(.automatic)
            }

            restoreFooterBar
        }
    }

    private func diffControlsBar(diff: NoteDiffResult) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text("基准版本 (旧)")
                    .font(.system(size: 10))
                    .foregroundStyle(palette.textSecondary)
                Picker("基准版本", selection: Binding(
                    get: { baseChoice ?? .currentLive },
                    set: { baseChoice = $0 }
                )) {
                    versionPickerItems
                }
                .labelsHidden()
                .frame(width: 215)
            }

            Image(systemName: "arrow.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(palette.textSecondary)
                .padding(.top, 14)

            VStack(alignment: .leading, spacing: 3) {
                Text("对比版本 (新)")
                    .font(.system(size: 10))
                    .foregroundStyle(palette.textSecondary)
                Picker("对比版本", selection: $targetChoice) {
                    versionPickerItems
                }
                .labelsHidden()
                .frame(width: 215)
            }

            Spacer()

            HStack(spacing: 6) {
                Text("+\(diff.addedCount)")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(palette.success)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(palette.success.opacity(0.12)))

                Text("-\(diff.removedCount)")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(palette.error)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(palette.error.opacity(0.12)))
            }

            Toggle("仅看变更", isOn: $onlyChangedLines)
                .toggleStyle(.checkbox)
                .font(.system(size: 11.5))
                .foregroundStyle(palette.textPrimary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(palette.softSurface.opacity(0.35))
        .overlay(alignment: .bottom) {
            Rectangle().fill(palette.workspaceLine.opacity(0.75)).frame(height: 0.5)
        }
    }

    @ViewBuilder
    private var versionPickerItems: some View {
        Text("当前编辑版本").tag(VersionChoice.currentLive)
        if conflict != nil {
            Text("冲突 · 我的未写入修改").tag(VersionChoice.conflictMine)
            Text("冲突 · 最新/磁盘版本").tag(VersionChoice.conflictTheirs)
        }
        ForEach(revisions) { rev in
            Text("\(formatShortDate(rev.createdAt)) · \(rev.reason.label)").tag(VersionChoice.revision(rev.id))
        }
    }

    private func metadataDiffStrip(diff: NoteDiffResult) -> some View {
        HStack(spacing: 12) {
            if diff.titleChanged {
                HStack(spacing: 5) {
                    Text("标题:")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(palette.textSecondary)
                    Text(diff.oldTitle.isEmpty ? "无标题" : diff.oldTitle)
                        .font(.system(size: 11))
                        .strikethrough()
                        .foregroundStyle(palette.error)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 9))
                        .foregroundStyle(palette.textSecondary)
                    Text(diff.newTitle.isEmpty ? "无标题" : diff.newTitle)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(palette.success)
                }
            }
            if diff.tagsChanged {
                HStack(spacing: 5) {
                    Text("标签:")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(palette.textSecondary)
                    Text(diff.oldTags.joined(separator: ", "))
                        .font(.system(size: 11))
                        .foregroundStyle(palette.error)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 9))
                        .foregroundStyle(palette.textSecondary)
                    Text(diff.newTags.joined(separator: ", "))
                        .font(.system(size: 11))
                        .foregroundStyle(palette.success)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 7)
        .background(palette.softSurface.opacity(0.25))
        .overlay(alignment: .bottom) {
            Rectangle().fill(palette.workspaceLine.opacity(0.6)).frame(height: 0.5)
        }
    }

    private func diffLineRow(_ line: NoteDiffLine) -> some View {
        let bg: Color
        let sign: String
        let signColor: Color
        switch line.kind {
        case .added:
            bg = palette.success.opacity(0.11)
            sign = "+"
            signColor = palette.success
        case .removed:
            bg = palette.error.opacity(0.11)
            sign = "-"
            signColor = palette.error
        case .same:
            bg = .clear
            sign = " "
            signColor = palette.textSecondary.opacity(0.55)
        }

        return HStack(alignment: .top, spacing: 0) {
            Text(line.oldLineNumber.map(String.init) ?? "")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(palette.textSecondary.opacity(0.65))
                .frame(width: 38, alignment: .trailing)
                .padding(.trailing, 6)

            Text(line.newLineNumber.map(String.init) ?? "")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(palette.textSecondary.opacity(0.65))
                .frame(width: 38, alignment: .trailing)
                .padding(.trailing, 8)

            Text(sign)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(signColor)
                .frame(width: 16, alignment: .center)

            Text(line.text.isEmpty ? " " : line.text)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(palette.textPrimary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.trailing, 14)
        }
        .padding(.vertical, 2.5)
        .background(bg)
    }

    private var restoreFooterBar: some View {
        let restoreTargetRevID: String? = {
            if let selectedRevisionID, revisions.contains(where: { $0.id == selectedRevisionID }) {
                return selectedRevisionID
            }
            if case .revision(let id) = baseChoice { return id }
            return nil
        }()

        return HStack(spacing: 12) {
            Image(systemName: "shield.checkmark")
                .font(.system(size: 12))
                .foregroundStyle(palette.brandInk)
            Text("恢复前将自动把当前版本（含未保存内容）存入历史快照，随时可再次回退。")
                .font(.system(size: 11))
                .foregroundStyle(palette.textSecondary)
                .lineLimit(1)
            Spacer()
            if let revID = restoreTargetRevID {
                LexiPrimaryButton(title: "恢复选中版本", symbol: "clock.arrow.circlepath") {
                    if model.restoreNoteVersion(noteID: noteID, revisionID: revID) {
                        targetChoice = .currentLive
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(palette.workspaceTabs.opacity(0.55))
        .overlay(alignment: .top) {
            Rectangle().fill(palette.workspaceLine).frame(height: 0.5)
        }
    }

    // MARK: Data helpers

    private func syncDefaultSelections() {
        if let conflict {
            _ = conflict
            if baseChoice == nil { baseChoice = .conflictTheirs }
            if targetChoice == .currentLive { targetChoice = .conflictMine }
        }
        if let first = revisions.first {
            if selectedRevisionID == nil || !revisions.contains(where: { $0.id == selectedRevisionID }) {
                selectedRevisionID = first.id
            }
            if baseChoice == nil {
                if revisions.count >= 2,
                   let currentNote,
                   first.contentHash == NoteHistoryHash.computeNoteHash(currentNote) {
                    baseChoice = .revision(revisions[1].id)
                    selectedRevisionID = revisions[1].id
                } else {
                    baseChoice = .revision(first.id)
                }
            }
        } else {
            selectedRevisionID = nil
            if baseChoice == nil {
                baseChoice = .currentLive
            }
        }
    }

    private func resolvePayload(_ choice: VersionChoice?) -> (title: String, content: String, tags: [String]) {
        switch choice {
        case .currentLive, .none:
            return (currentNote?.title ?? "", currentNote?.content ?? "", currentNote?.tags ?? [])
        case .conflictMine:
            if let conflict {
                return (conflict.mineTitle, conflict.mineContent, conflict.mineTags)
            }
            return (currentNote?.title ?? "", currentNote?.content ?? "", currentNote?.tags ?? [])
        case .conflictTheirs:
            if let conflict {
                return (conflict.theirsTitle, conflict.theirsContent, conflict.theirsTags)
            }
            return (currentNote?.title ?? "", currentNote?.content ?? "", currentNote?.tags ?? [])
        case .revision(let id):
            if let rev = revisions.first(where: { $0.id == id }) {
                return (rev.title, rev.content, rev.tags)
            }
            return (currentNote?.title ?? "", currentNote?.content ?? "", currentNote?.tags ?? [])
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: date)
    }

    private func formatShortDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd HH:mm:ss"
        return formatter.string(from: date)
    }
}
