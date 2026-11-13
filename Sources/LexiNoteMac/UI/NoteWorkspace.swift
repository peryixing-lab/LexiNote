import SwiftUI
import AppKit

struct NoteWorkspaceView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var settings: SettingsStore
    let note: Note

    @Environment(\.lexiPalette) private var palette
    @Environment(\.lexiSnapshot) private var snapshotMode

    @StateObject private var editorController = EditorController()
    @State private var mode: EditorPresentation
    @State private var findVisible = false
    @State private var findText = ""
    @State private var findMessage = ""
    @State private var jumpTarget: String?
    @State private var tagPopover = false
    @State private var newTag = ""
    @State private var metaHovering = false
    @State private var showCapture = false
    @State private var prompt: PromptRequest?
    @FocusState private var findFocused: Bool

    init(model: AppModel, settings: SettingsStore, note: Note) {
        self.model = model
        self.settings = settings
        self.note = note
        _mode = State(initialValue: model.presentationOverride ?? settings.preferredPresentation)
    }

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                toolbar(paneWidth: geometry.size.width)
                if findVisible {
                    findBar
                }
                content(paneWidth: geometry.size.width)
                if settings.showStatusBar {
                    statusBar(paneWidth: geometry.size.width)
                }
            }
        }
        .background(palette.workspacePage)
        .onReceive(NotificationCenter.default.publisher(for: .lexiEditorCommand)) { notification in
            guard let command = notification.userInfo?["command"] as? String,
                  model.currentNote?.id == note.id else { return }
            handle(command: command)
        }
        .onReceive(NotificationCenter.default.publisher(for: .lexiFindInNote)) { _ in
            guard model.currentNote?.id == note.id else { return }
            openFind()
        }
        .onChange(of: model.pendingJump) { _, jump in
            guard let jump, jump.noteID == note.id else { return }
            jumpTarget = jump.headingID
            if mode == .source {
                editorController.selectLine(jump.line)
            } else if mode == .live {
                editorController.selectLine(jump.line)
            }
            model.pendingJump = nil
        }
        .sheet(isPresented: $showCapture) {
            QuickCaptureSheet(palette: palette) { text in
                insertCapture(text)
            }
        }
        .sheet(item: $prompt) { request in
            TextPromptSheet(request: request)
        }
        .popover(isPresented: $tagPopover, arrowEdge: .bottom) {
            tagEditor
        }
        .onAppear {
            LexiEditorBridge.shared.isCurrentNoteReading = (mode == .reading)
            if note.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && mode == .live {
                mode = .source
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
                    editorController.focus()
                }
            }
        }
        .onChange(of: mode) { _, newMode in
            LexiEditorBridge.shared.isCurrentNoteReading = (newMode == .reading)
            model.plugins.notifyActiveLeafChanged()
        }
        .onChange(of: note.id) { _, _ in
            LexiEditorBridge.shared.isCurrentNoteReading = (mode == .reading)
        }
    }

    // MARK: Toolbar

    private func toolbar(paneWidth: CGFloat) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "folder")
                .font(.system(size: 12))
                .foregroundStyle(palette.textSecondary)
            Text(note.notebook.isEmpty ? "知识库" : note.notebook)
                .font(.system(size: 12))
                .foregroundStyle(palette.textSecondary)
                .lineLimit(1)
            Text("/")
                .font(.system(size: 12))
                .foregroundStyle(palette.textSecondary.opacity(0.8))
            Text(note.displayTitle)
                .font(.system(size: 12))
                .foregroundStyle(palette.textPrimary)
                .lineLimit(1)
            Spacer(minLength: 12)

            LexiToolButton(title: mode == .source ? "实时预览" : "源码",
                           active: mode == .source, compact: true) {
                withAnimation(.easeOut(duration: 0.15)) {
                    mode = mode == .source ? .live : .source
                }
            }

            Menu {
                toolMenuItems
            } label: {
                Text("工具")
                    .font(.system(size: 12))
                    .foregroundStyle(palette.brandInk)
                    .padding(.horizontal, 11)
                    .frame(height: 30)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(palette.workspaceSelection)
                    )
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()

            Menu {
                Button(mode == .reading ? "退出阅读视图" : "阅读视图") {
                    withAnimation(.easeOut(duration: 0.15)) {
                        mode = mode == .reading ? .live : .reading
                    }
                }
                Button("查找…") { openFind() }
                Divider()
                Button("生成思维导图") { model.convertNoteToMap(note) }
                Button("导出 Markdown…") { model.exportCurrentMarkdown() }
                Button("复制文件路径") { model.copyNotePath(note.id) }
                Button("在 Finder 中显示") { model.revealNoteInFinder(note.id) }
                Divider()
                Button("重命名…") {
                    prompt = PromptRequest(title: "重命名笔记", placeholder: "笔记标题",
                                           initial: note.title, confirmTitle: "重命名") { value in
                        model.updateNoteTitle(note.id, title: value)
                        _ = model.saveNoteNow(note.id)
                    }
                }
                Button("移到回收站", role: .destructive) { model.trashNote(note.id) }
            } label: {
                Text("更多")
                    .font(.system(size: 12))
                    .foregroundStyle(palette.textSecondary)
                    .padding(.horizontal, 9)
                    .frame(height: 30)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .padding(.leading, 28)
        .padding(.trailing, 16)
        .frame(height: Metrics.editorToolbarHeight)
        .overlay(alignment: .bottom) {
            Rectangle().fill(palette.workspaceLine).frame(height: 0.5)
        }
    }

    private var toolMenuItems: some View {
        Group {
            Button("加粗") { apply(.bold) }
            Button("倾斜") { apply(.italic) }
            Button("删除线") { apply(.strike) }
            Button("高亮") { apply(.highlight) }
            Divider()
            Button("小标题 1") { apply(.h1) }
            Button("小标题 2") { apply(.h2) }
            Button("待办事项") { apply(.todo) }
            Button("表格") { apply(.table) }
            Divider()
            Button("代码块") { apply(.code) }
            Button("数学公式") { apply(.formula) }
            Button("标注") { apply(.callout) }
            Button("双向链接") { apply(.link) }
            Divider()
            Button("插入日期") { apply(.date) }
            Button("插入时间") { apply(.time) }
        }
    }

    // MARK: Content

    @ViewBuilder
    private func content(paneWidth: CGFloat) -> some View {
        switch mode {
        case .source:
            VStack(spacing: 0) {
                documentHeader(maxWidth: settings.limitEditorWidth ? 688 : nil, horizontalPadding: 56)
                editorPane(horizontalPadding: 56)
            }
        default:
            VStack(spacing: 0) {
                documentHeader(maxWidth: settings.limitEditorWidth ? 688 : nil, horizontalPadding: 56)
                MarkdownPreview(blocks: displayBlocks,
                                note: note, fontSize: CGFloat(settings.editorFontSize),
                                vaultURL: model.activeVault.map { model.vaultFolder($0) },
                                jumpTarget: jumpTarget,
                                onOpenTarget: { model.openWikiLink($0) },
                                onToggleTodo: { model.toggleTodo(noteID: note.id, line: $0) },
                                liveEditing: mode == .live,
                                onEditBlock: { jumpToSource($0) })
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(palette.workspacePage)
            }
        }
    }

    private var displayBlocks: [MDBlock] {
        var blocks = MarkdownParser.parse(note.content)
        if let first = blocks.first,
           case .heading(let level, let content, _) = first.kind,
           level == 1,
           MarkdownParser.inlinePlain(content).trimmingCharacters(in: .whitespacesAndNewlines)
            .caseInsensitiveCompare(note.displayTitle) == .orderedSame {
            blocks.removeFirst()
        } else if let first = blocks.first,
                  case .heading(let level, _, _) = first.kind,
                  level == 1 {
            blocks.removeFirst()
        }
        return blocks
    }

    private func documentHeader(maxWidth: CGFloat?, horizontalPadding: CGFloat = 56) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            if settings.editorShowTitle {
                TextField("无标题笔记", text: titleBinding)
                    .textFieldStyle(.plain)
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1)
                    .padding(.top, 2)
            }

            HStack(spacing: 8) {
                Text(note.type.label)
                    .font(.system(size: 11))
                    .foregroundStyle(palette.brandInk)
                Text("·")
                    .font(.system(size: 11))
                    .foregroundStyle(palette.textSecondary)
                Text("\(note.characterCount) 字符")
                    .font(.system(size: 11))
                    .foregroundStyle(palette.textSecondary)
                ForEach(note.tags.prefix(3), id: \.self) { tag in
                    Text("#\(tag)")
                        .font(.system(size: 11))
                        .foregroundStyle(palette.brandInk)
                        .help("标签 \(tag)")
                }
                if metaHovering {
                    Button {
                        tagPopover = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(palette.textSecondary)
                            .frame(width: 16, height: 16)
                            .background(Circle().fill(palette.controlFill))
                    }
                    .buttonStyle(.plain)
                    .help("添加标签")
                    .transition(.opacity)
                }
                Spacer()
            }
            .onHover { metaHovering = $0 }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, horizontalPadding)
        .padding(.top, 34)
        .padding(.bottom, 16)
        .frame(maxWidth: maxWidth.map { $0 + horizontalPadding * 2 } ?? .infinity, alignment: .center)
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private func editorPane(horizontalPadding: CGFloat) -> some View {
        let content = model.note(note.id)?.content ?? note.content
        return MarkdownTextEditor(text: contentBinding,
                                  palette: palette,
                                  fontSize: CGFloat(settings.editorFontSize),
                                  lineHeight: CGFloat(settings.editorLineHeight),
                                  design: settings.editorDesign,
                                  spellCheck: settings.spellCheck,
                                  controller: editorController,
                                  onTextChange: { model.updateNoteContent(note.id, content: $0) })
            .padding(.horizontal, horizontalPadding)
            .padding(.top, 2)
            .padding(.bottom, 20)
            .frame(maxWidth: settings.limitEditorWidth ? 800 : .infinity, alignment: .center)
            .frame(maxWidth: .infinity, alignment: .center)
            .overlay(alignment: .topLeading) {
                if content.isEmpty {
                    Text("从一个想法开始。支持 Markdown、#标签 与 [[双向链接]]。")
                        .font(.system(size: CGFloat(settings.editorFontSize), design: settings.editorDesign.design))
                        .foregroundStyle(palette.textSecondary.opacity(0.65))
                        .padding(.leading, horizontalPadding)
                        .padding(.top, 12)
                        .allowsHitTesting(false)
                }
            }
    }

    // MARK: Status bar

    private func statusBar(paneWidth: CGFloat) -> some View {
        HStack(spacing: paneWidth >= 600 ? 16 : 8) {
            Button {
                showCapture = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 11.5, weight: .medium))
                    Text("语音记录")
                        .font(.system(size: 12))
                }
                .foregroundStyle(palette.brandInk)
                .frame(width: 104, height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(palette.softSurface)
                )
            }
            .buttonStyle(.plain)
            .help("打开语音速记面板")

            if settings.editorViewStatus {
                Button {
                    withAnimation(.easeOut(duration: 0.15)) {
                        mode = mode == .reading ? .live : .reading
                    }
                } label: {
                    Text(modeLabel)
                        .font(.system(size: 11))
                        .foregroundStyle(palette.textSecondary)
                        .frame(height: 28)
                        .padding(.horizontal, 4)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(mode == .reading ? "回到实时预览" : "进入阅读视图")
            }

            if paneWidth >= 720 {
                Text("\(model.backlinks(for: note).count) 个反向链接")
                    .font(.system(size: 11))
                    .foregroundStyle(palette.textSecondary)
            }
            if paneWidth >= 520 {
                Text("\(note.characterCount) 字符")
                    .font(.system(size: 11))
                    .foregroundStyle(palette.textSecondary)
            }
            Spacer(minLength: 8)
            Button {
                if model.saveState != .saving {
                    _ = model.saveNoteNow(note.id)
                    if !settings.autoSave || model.saveState == .unsaved {
                        model.showToast("已保存到本机", symbol: "checkmark.circle")
                    }
                }
            } label: {
                HStack(spacing: 5) {
                    if model.saveState == .saving {
                        ProgressView().controlSize(.mini).scaleEffect(0.6)
                    } else if model.saveState == .unsaved {
                        Image(systemName: "pencil.circle")
                            .font(.system(size: 9))
                            .foregroundStyle(palette.warning)
                    }
                    Text(saveLabel)
                        .font(.system(size: 11))
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(1)
                }
            }
            .buttonStyle(.plain)
            .help("点击立即保存")
        }
        .padding(.leading, paneWidth >= 600 ? 24 : 12)
        .padding(.trailing, paneWidth >= 600 ? 20 : 12)
        .frame(height: Metrics.editorStatusHeight)
        .overlay(alignment: .top) {
            Rectangle().fill(palette.workspaceLine).frame(height: 0.5)
        }
    }

    private var modeLabel: String {
        switch mode {
        case .source: return "Markdown 源码"
        case .live: return "实时预览"
        case .reading: return "阅读视图"
        }
    }

    private var saveLabel: String { model.saveState.label }

    // MARK: Find bar

    private var findBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundStyle(palette.textSecondary)
            TextField("查找内容", text: $findText)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(palette.textPrimary)
                .focused($findFocused)
                .onSubmit { findNext() }
            if !findMessage.isEmpty {
                Text(findMessage)
                    .font(.system(size: 10.5))
                    .foregroundStyle(palette.error)
            }
            Button("上一个") { findPrevious() }
                .buttonStyle(.plain)
                .font(.system(size: 11))
                .foregroundStyle(palette.brandInk)
            Button("下一个") { findNext() }
                .buttonStyle(.plain)
                .font(.system(size: 11))
                .foregroundStyle(palette.brandInk)
            Button {
                findVisible = false
                findMessage = ""
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(palette.textSecondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .frame(height: 38)
        .background(palette.softSurface.opacity(palette.isDark ? 0.4 : 0.55))
        .overlay(alignment: .bottom) {
            Rectangle().fill(palette.workspaceLine).frame(height: 0.5)
        }
    }

    // MARK: Tags popover

    private var tagEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("添加标签")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(palette.textPrimary)
            TextField("例如 学习/算法", text: $newTag)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12))
                .frame(width: 200)
                .onSubmit { commitTag() }
            HStack {
                Spacer()
                Button("添加") { commitTag() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(newTag.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(14)
        .background(palette.surface)
    }

    private func commitTag() {
        let tag = newTag.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "#", with: "")
        guard !tag.isEmpty else { return }
        var tags = note.tags
        if !tags.contains(tag) { tags.append(tag) }
        model.updateNoteTags(note.id, tags: tags)
        newTag = ""
        tagPopover = false
    }

    // MARK: Actions

    private var titleBinding: Binding<String> {
        Binding(get: { model.note(note.id)?.title ?? note.title },
                set: { model.updateNoteTitle(note.id, title: $0) })
    }

    private var contentBinding: Binding<String> {
        Binding(get: { model.note(note.id)?.content ?? note.content },
                set: { model.updateNoteContent(note.id, content: $0) })
    }

    private func jumpToSource(_ line: Int) {
        withAnimation(.easeOut(duration: 0.15)) { mode = .source }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            editorController.selectLine(max(0, line))
        }
    }

    private func apply(_ command: EditorCommand) {
        if mode == .reading { mode = .source }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
            editorController.focus()
            editorController.apply(command)
        }
    }

    private func openFind() {
        findVisible = true
        if mode != .source { mode = .source }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            findFocused = true
        }
    }

    private func findNext() {
        guard !findText.isEmpty else { return }
        let found = editorController.findNext(findText)
        findMessage = found ? "" : "没有匹配内容"
    }

    private func findPrevious() {
        guard !findText.isEmpty else { return }
        let range = editorController.selectedRange()
        let ns = (model.note(note.id)?.content ?? "") as NSString
        let start = range.location
        let searchRange = NSRange(location: 0, length: max(0, start))
        let found = ns.range(of: findText, options: [.caseInsensitive, .backwards], range: searchRange)
        if found.location != NSNotFound {
            editorController.setSelection(found)
            findMessage = ""
        } else {
            findMessage = "没有匹配内容"
        }
    }

    private func insertCapture(_ text: String) {
        guard !text.isEmpty else { return }
        if mode == .reading { mode = .source }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            editorController.focus()
            editorController.insert("\n" + text + "\n")
        }
    }

    private func handle(command: String) {
        guard let editorCommand = EditorCommand(rawValue: command) else { return }
        switch editorCommand {
        case .reading:
            mode = mode == .reading ? .live : .reading
        case .source:
            mode = .source
        case .split:
            mode = .live
        case .find:
            openFind()
        case .focus:
            editorController.focus()
        default:
            apply(editorCommand)
        }
    }
}

// MARK: - Quick capture

struct QuickCaptureSheet: View {
    @Environment(\.dismiss) private var dismiss
    let palette: ThemePalette
    let onInsert: (String) -> Void

    @State private var text = ""
    @State private var focus: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("语音记录")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(palette.textPrimary)
                    Text("macOS 版通过系统听写输入（键盘设置中启用听写），也可以直接写下要插入的内容。")
                        .font(.system(size: 11.5))
                        .foregroundStyle(palette.textSecondary)
                }
                Spacer()
                Button("关闭") { dismiss() }
                    .buttonStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundStyle(palette.textSecondary)
            }

            TextEditor(text: $text)
                .font(.system(size: 13))
                .scrollContentBackground(.hidden)
                .padding(10)
                .frame(height: 150)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(palette.softSurface.opacity(palette.isDark ? 0.45 : 0.65))
                )
                .overlay(alignment: .topLeading) {
                    if text.isEmpty {
                        Text("写下一句话…")
                            .font(.system(size: 13))
                            .foregroundStyle(palette.textSecondary.opacity(0.6))
                            .padding(.horizontal, 15)
                            .padding(.vertical, 18)
                            .allowsHitTesting(false)
                    }
                }

            HStack(spacing: 8) {
                quickChip("日期") {
                    text += LexiDate.dayKey()
                }
                quickChip("时间") {
                    let formatter = DateFormatter()
                    formatter.dateFormat = "HH:mm"
                    text += formatter.string(from: Date())
                }
                quickChip("待办") {
                    text += text.isEmpty ? "- [ ] " : "\n- [ ] "
                }
                quickChip("引用") {
                    text += text.isEmpty ? "> " : "\n> "
                }
                Spacer()
            }

            HStack {
                Spacer()
                Button("取消") { dismiss() }
                    .buttonStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(palette.textSecondary)
                Button {
                    onInsert(text.trimmingCharacters(in: .whitespacesAndNewlines))
                    dismiss()
                } label: {
                    Text("插入到笔记")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(palette.inverseText)
                        .padding(.horizontal, 16)
                        .frame(height: 30)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(palette.brand.opacity(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.4 : 1))
                        )
                }
                .buttonStyle(.plain)
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(22)
        .frame(width: 520)
        .background(palette.workspacePage)
        .tint(palette.brand)
    }

    private func quickChip(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11))
                .foregroundStyle(palette.brandInk)
                .padding(.horizontal, 10)
                .frame(height: 26)
                .background(Capsule().fill(palette.brandSoft))
        }
        .buttonStyle(.plain)
    }
}
