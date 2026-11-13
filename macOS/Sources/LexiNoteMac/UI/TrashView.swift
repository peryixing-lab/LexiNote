import SwiftUI

/// Trash is a modal panel on macOS, matching the desktop mockup. It is not a document tab.
struct TrashSheet: View {
    @ObservedObject var model: AppModel
    @ObservedObject var settings: SettingsStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.lexiPalette) private var palette
    @State private var confirmEmpty = false

    var body: some View {
        VStack(spacing: 0) {
            header
            VStack(alignment: .leading, spacing: 0) {
                Text("删除的笔记会保留在这里，可恢复或永久删除。")
                    .font(.system(size: 11.5))
                    .foregroundStyle(palette.textSecondary)
                    .padding(.top, 18)
                    .padding(.bottom, 10)

                if model.trashedNotes.isEmpty {
                    Spacer()
                    VStack(spacing: 12) {
                        ZStack {
                            Circle().fill(palette.brandSoft).frame(width: 58, height: 58)
                            Image(systemName: "trash")
                                .font(.system(size: 23, weight: .light))
                                .foregroundStyle(palette.brandInk)
                        }
                        Text("回收站是空的")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(palette.textPrimary)
                        Text("删除的笔记会先来到这里，随时可以恢复。")
                            .font(.system(size: 11.5))
                            .foregroundStyle(palette.textSecondary)
                    }
                    .frame(maxWidth: .infinity)
                    Spacer()
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(model.trashedNotes) { note in
                                row(note)
                                Rectangle().fill(palette.workspaceLine.opacity(0.65)).frame(height: 0.5)
                            }
                        }
                    }
                    .scrollIndicators(.automatic)
                }
            }
            .padding(.horizontal, 24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .frame(width: 760, height: 560)
        .background(palette.workspacePage)
        .environment(\.lexiPalette, palette)
        .preferredColorScheme(settings.preferredColorScheme)
        .tint(palette.brand)
        .confirmationDialog("清空回收站？", isPresented: $confirmEmpty, titleVisibility: .visible) {
            Button("永久删除 \(model.trashedNotes.count) 篇笔记", role: .destructive) {
                model.emptyTrash()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("此操作不可撤销，对应的 Markdown 文件也会被删除。")
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text("回收站")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                Text("\(model.trashedNotes.count) 篇已删除笔记")
                    .font(.system(size: 10.5))
                    .foregroundStyle(palette.textSecondary)
            }
            Spacer()
            if !model.trashedNotes.isEmpty {
                Button {
                    confirmEmpty = true
                } label: {
                    Text("清空")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(palette.error)
                        .padding(.horizontal, 13)
                        .frame(height: 28)
                        .background(Capsule().fill(palette.error.opacity(0.09)))
                }
                .buttonStyle(.plain)
            }
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
            .help("关闭")
        }
        .padding(.horizontal, 20)
        .frame(height: 64)
        .background(palette.workspaceSidebar)
        .overlay(alignment: .bottom) {
            Rectangle().fill(palette.workspaceLine).frame(height: 0.5)
        }
    }

    private func excerpt(_ note: Note) -> String {
        var raw = note.plainText.replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let title = note.displayTitle
        if raw.hasPrefix(title) {
            raw = String(raw.dropFirst(title.count)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if raw.isEmpty {
            return "\(note.notebook) · " + (note.trashedAt.map { "\(LexiDate.relative($0))移入回收站" } ?? "已删除")
        }
        return String(raw.prefix(140))
    }

    private func row(_ note: Note) -> some View {
        HStack(spacing: 12) {
            Image(systemName: note.type.symbol)
                .font(.system(size: 15))
                .foregroundStyle(palette.textSecondary)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 3) {
                Text(note.displayTitle)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1)
                Text(excerpt(note))
                    .font(.system(size: 10.5))
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1)
            }
            Spacer()
            Button("恢复") {
                model.restoreNote(note.id)
            }
            .buttonStyle(.plain)
            .font(.system(size: 11.5, weight: .medium))
            .foregroundStyle(palette.brandInk)
            .padding(.horizontal, 12)
            .frame(height: 26)
            .background(Capsule().fill(palette.brandSoft))

            Button {
                model.deleteNotePermanently(note.id)
            } label: {
                Text("永久删除")
                    .font(.system(size: 11.5))
                    .foregroundStyle(palette.error)
                    .padding(.horizontal, 10)
                    .frame(height: 26)
            }
            .buttonStyle(.plain)
            .help("永久删除")
        }
        .padding(.vertical, 11)
        .contentShape(Rectangle())
        .help("\(note.notebook) · " + (note.trashedAt.map { "\(LexiDate.relative($0))移入回收站" } ?? "已删除"))
        .contextMenu {
            Button("恢复") { model.restoreNote(note.id) }
            Button("永久删除", role: .destructive) { model.deleteNotePermanently(note.id) }
        }
    }
}

/// Only reachable if an old session still contains a trash tab. Trash now opens as a sheet.
struct TrashWorkspaceView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var settings: SettingsStore
    @Environment(\.lexiPalette) private var palette

    var body: some View {
        VStack(spacing: 14) {
            EmptyStatePanel(symbol: "trash",
                            title: "回收站现在以弹窗打开",
                            detail: "点击左侧回收站图标，或使用「视图 → 回收站」。")
            Button("打开回收站") { model.openTrash() }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(palette.brandInk)
                .padding(.horizontal, 14)
                .frame(height: 30)
                .background(Capsule().fill(palette.brandSoft))
        }
    }
}
