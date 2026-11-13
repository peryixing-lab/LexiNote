import SwiftUI
import AppKit

// MARK: - Text prompt

struct TextPromptSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.lexiPalette) private var palette
    let request: PromptRequest
    @State private var text: String
    @FocusState private var focused: Bool

    init(request: PromptRequest) {
        self.request = request
        _text = State(initialValue: request.initial)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(request.title)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(palette.textPrimary)
            TextField(request.placeholder, text: $text)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 13))
                .focused($focused)
                .onSubmit { confirm() }
            HStack {
                Spacer()
                Button("取消") { dismiss() }
                    .buttonStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(palette.textSecondary)
                Button {
                    confirm()
                } label: {
                    Text(request.confirmTitle)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(palette.inverseText)
                        .padding(.horizontal, 16)
                        .frame(height: 30)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(palette.brand.opacity(text.trimmingCharacters(in: .whitespaces).isEmpty ? 0.4 : 1))
                        )
                }
                .buttonStyle(.plain)
                .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(22)
        .frame(width: 420)
        .background(palette.workspacePage)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { focused = true }
        }
    }

    private func confirm() {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        request.onConfirm(value)
        dismiss()
    }
}

// MARK: - Template picker

struct TemplatePickerSheet: View {
    @ObservedObject var model: AppModel
    @ObservedObject var settings: SettingsStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.lexiPalette) private var palette

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("从模板新建")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(palette.textPrimary)
                    Text("选择一个结构，从第一行开始写。")
                        .font(.system(size: 11))
                        .foregroundStyle(palette.textSecondary)
                }
                Spacer()
                Button("关闭") { dismiss() }
                    .buttonStyle(.plain)
                    .font(.system(size: 11.5))
                    .foregroundStyle(palette.textSecondary)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            .background(palette.workspaceSidebar)
            .overlay(alignment: .bottom) {
                Rectangle().fill(palette.workspaceLine).frame(height: 0.5)
            }

            ScrollView {
                LazyVGrid(columns: columns, spacing: 12) {
                    Button {
                        model.createNote(title: "无标题笔记", type: .markdown)
                        dismiss()
                    } label: {
                        templateCard(icon: "doc.badge.plus", title: "空白笔记", category: "自由",
                                     detail: "不做任何预设，直接从空白页开始。", highlighted: true)
                    }
                    .buttonStyle(.plain)

                    ForEach(TemplateLibrary.builtins) { template in
                        Button {
                            let title = defaultTitle(for: template)
                            model.createFromTemplate(template, title: title)
                            dismiss()
                        } label: {
                            templateCard(icon: icon(for: template.category),
                                         title: template.title,
                                         category: template.category,
                                         detail: detail(for: template),
                                         highlighted: false)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(20)
            }
        }
        .frame(width: 700, height: 590)
        .background(palette.workspacePage)
    }

    private func templateCard(icon: String, title: String, category: String, detail: String, highlighted: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(palette.brandInk)
                    .frame(width: 26, height: 26)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(palette.brandSoft)
                    )
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                Spacer()
                Text(category)
                    .font(.system(size: 9.5))
                    .foregroundStyle(palette.textSecondary)
                    .padding(.horizontal, 6)
                    .frame(height: 18)
                    .background(Capsule().fill(palette.controlFill))
            }
            Text(detail)
                .font(.system(size: 10.5))
                .foregroundStyle(palette.textSecondary)
                .lineSpacing(3)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(13)
        .frame(maxWidth: .infinity, minHeight: 108, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(highlighted ? palette.brandSoft.opacity(palette.isDark ? 0.45 : 0.6) : palette.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .stroke(highlighted ? palette.brand.opacity(0.35) : palette.workspaceLine, lineWidth: 1)
        )
    }

    private func defaultTitle(for template: NoteTemplate) -> String {
        if template.id == "builtin-daily" { return model.todayTitle() }
        if template.id == "builtin-meeting" { return "会议纪要 \(LexiDate.dayKey())" }
        return template.title
    }

    private func icon(for category: String) -> String {
        switch category {
        case "日常": return "sun.max"
        case "计划": return "calendar"
        case "代码": return "chevron.left.forwardslash.chevron.right"
        case "学习": return "book.closed"
        case "会议": return "person.2"
        case "项目": return "square.stack.3d.up"
        default: return "doc.text"
        }
    }

    private func detail(for template: NoteTemplate) -> String {
        let line = template.content
            .components(separatedBy: "\n")
            .first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty && !$0.hasPrefix("# ") })
            ?? template.content.components(separatedBy: "\n").first ?? ""
        return line.replacingOccurrences(of: "#", with: "").trimmingCharacters(in: .whitespaces)
    }
}

// MARK: - Welcome

struct WelcomeSheet: View {
    @ObservedObject var model: AppModel
    @ObservedObject var settings: SettingsStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.lexiPalette) private var palette

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 12) {
                LexiLogoMark(size: 64)
                    .padding(.top, 30)
                Text("欢迎使用知萤")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                Text("想记就记，需要时足够专业。")
                    .font(.system(size: 13))
                    .foregroundStyle(palette.textSecondary)
                    .padding(.bottom, 10)
            }

            HStack(spacing: 12) {
                feature(icon: "square.and.pencil", title: "记录", detail: "Markdown 与实时预览，支持公式、代码块、待办与标注；悬停段落点「编辑」即可改源码。")
                feature(icon: "link", title: "连接", detail: "用 [[双向链接]] 把笔记织成网络，随时查看出链与反向链接。")
                feature(icon: "point.3.connected.trianglepath.dotted", title: "整理", detail: "文件夹、标签、关系图谱与思维导图，让知识自然生长。")
            }
            .padding(.horizontal, 28)

            Spacer(minLength: 18)

            HStack(spacing: 14) {
                Text("笔记以标准 Markdown 保存在本机，随时可以迁移。")
                    .font(.system(size: 10.5))
                    .foregroundStyle(palette.textSecondary)
                Spacer()
                Button("稍后再说") {
                    settings.markWelcomeSeen()
                    dismiss()
                }
                .buttonStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(palette.textSecondary)
                Button {
                    settings.markWelcomeSeen()
                    model.welcomeVisible = false
                    model.createNote(title: "我的第一篇笔记",
                                     content: "# 我的第一篇笔记\n\n> 从今天开始，把想法一条条连接起来。\n\n- [ ] 写下第一个灵感\n- [ ] 试试 `[[双向链接]]`\n",
                                     type: .markdown)
                    dismiss()
                } label: {
                    Text("开始记录")
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(palette.inverseText)
                        .padding(.horizontal, 22)
                        .frame(height: 34)
                        .background(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(palette.brand)
                        )
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 24)
        }
        .frame(width: 760, height: 480)
        .onDisappear {
            settings.markWelcomeSeen()
        }
        .background(
            ZStack {
                palette.workspacePage
                RadialGradient(colors: [palette.brandSoft.opacity(palette.isDark ? 0.5 : 0.8), .clear],
                               center: .top, startRadius: 10, endRadius: 380)
            }
        )
    }

    private func feature(icon: String, title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .light))
                .foregroundStyle(palette.brandInk)
                .frame(width: 34, height: 34)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(palette.brandSoft)
                )
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(palette.textPrimary)
            Text(detail)
                .font(.system(size: 10.8))
                .foregroundStyle(palette.textSecondary)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 172, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(palette.surface.opacity(palette.isDark ? 0.75 : 0.92))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .stroke(palette.workspaceLine, lineWidth: 1)
        )
    }
}

// MARK: - Workspace open-mode prompt

struct WorkspaceOpenPromptSheet: View {
    @ObservedObject var model: AppModel
    @ObservedObject var settings: SettingsStore
    let vault: Vault

    @Environment(\.dismiss) private var dismiss
    @Environment(\.lexiPalette) private var palette
    @State private var rememberChoice = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "macwindow.on.rectangle")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(palette.brandInk)
                    .frame(width: 34, height: 34)
                    .background(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(palette.brandSoft)
                    )
                VStack(alignment: .leading, spacing: 2) {
                    Text("选择工作区打开方式")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(palette.textPrimary)
                    Text("选择在当前窗口切换，或打开一个新的窗口。")
                        .font(.system(size: 11.5))
                        .foregroundStyle(palette.textSecondary)
                }
                Spacer()
            }

            HStack(spacing: 10) {
                Image(systemName: "folder.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(palette.brandInk)
                VStack(alignment: .leading, spacing: 2) {
                    Text(vault.name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(palette.textPrimary)
                    Text(vault.detail)
                        .font(.system(size: 10.5))
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(1)
                }
                Spacer()
                if vault.id == model.activeVaultID {
                    Text("当前工作区")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(palette.brandInk)
                        .padding(.horizontal, 8)
                        .frame(height: 20)
                        .background(Capsule().fill(palette.brandSoft))
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(palette.surface.opacity(palette.isDark ? 0.7 : 0.92))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(palette.workspaceLine, lineWidth: 1)
            )

            VStack(alignment: .leading, spacing: 5) {
                Toggle("下次不再提示", isOn: $rememberChoice)
                    .toggleStyle(.checkbox)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(palette.textPrimary)
                Text("所有工作区共用此打开方式（不按工作区保存），之后可在「设置 → 编辑器」中重新选择。")
                    .font(.system(size: 10.5))
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 2)

            HStack(spacing: 10) {
                Button("取消") {
                    model.workspacePromptVault = nil
                    dismiss()
                }
                .buttonStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(palette.textSecondary)
                .padding(.horizontal, 10)
                .frame(height: 32)

                Spacer()

                Button {
                    model.confirmOpenWorkspace(vault, mode: .current, remember: rememberChoice)
                    dismiss()
                } label: {
                    Text("在当前窗口打开")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(palette.textPrimary)
                        .padding(.horizontal, 14)
                        .frame(height: 32)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(palette.softSurface)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(palette.workspaceLine, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)

                Button {
                    model.confirmOpenWorkspace(vault, mode: .new, remember: rememberChoice)
                    dismiss()
                } label: {
                    Text("在新窗口打开")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(palette.inverseText)
                        .padding(.horizontal, 16)
                        .frame(height: 32)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(palette.brand)
                        )
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 4)
        }
        .padding(22)
        .frame(width: 440)
        .background(palette.workspacePage)
        .environment(\.lexiPalette, palette)
        .preferredColorScheme(settings.preferredColorScheme)
        .tint(palette.brand)
    }
}
