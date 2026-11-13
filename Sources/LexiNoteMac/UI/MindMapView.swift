import SwiftUI

struct MindMapWorkspaceView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var settings: SettingsStore
    let map: MindMap

    @Environment(\.lexiPalette) private var palette
    @State private var selectedNodeID: String?
    @State private var inlineEditingNodeID: String?
    @State private var inlineText: String = ""
    @State private var outlineMode: Bool = false
    @State private var inspectorVisible: Bool = true
    @State private var zoomScale: CGFloat = 1.0
    @State private var panOffset: CGSize = .zero
    @GestureState private var dragDelta: CGSize = .zero
    @GestureState private var pinchDelta: CGFloat = 1.0
    @State private var undoStack: [MindMap] = []
    @State private var redoStack: [MindMap] = []
    @FocusState private var inlineFocused: Bool

    private var rootNode: MindNode {
        map.nodes.first(where: { $0.id == map.rootNodeID }) ?? map.nodes.first ?? MindNode(text: map.title)
    }

    private var activeNode: MindNode? {
        guard let selectedNodeID else { return rootNode }
        return map.nodes.first(where: { $0.id == selectedNodeID }) ?? rootNode
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            HStack(spacing: 0) {
                Group {
                    if outlineMode {
                        outlineEditor
                    } else {
                        canvasArea
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                if inspectorVisible {
                    NodeInspectorPanel(
                        model: model,
                        map: map,
                        node: activeNode ?? rootNode,
                        selectedNodeID: $selectedNodeID,
                        onMutate: { recordUndoAndRun($0) }
                    )
                    .frame(width: 236)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            statusBar
        }
        .background(palette.workspacePage)
        .onAppear {
            if selectedNodeID == nil {
                selectedNodeID = rootNode.id
            }
        }
        .onChange(of: map.id) { _, _ in
            selectedNodeID = rootNode.id
            undoStack.removeAll()
            redoStack.removeAll()
            zoomScale = 1.0
            panOffset = .zero
        }
    }

    // MARK: - Top Toolbar (48pt)

    private var toolbar: some View {
        HStack(spacing: 8) {
            Image(systemName: "point.3.connected.trianglepath.dotted")
                .font(.system(size: 13))
                .foregroundStyle(palette.brand)
            Text(map.title)
                .font(.system(size: 13.5, weight: .semibold))
                .foregroundStyle(palette.textPrimary)
                .lineLimit(1)

            Spacer(minLength: 8)

            // Layout switcher
            HStack(spacing: 2) {
                ForEach(MindMapLayout.allCases) { layout in
                    let active = map.layout == layout
                    Button {
                        recordUndoAndRun {
                            var updated = map
                            updated.layout = layout
                            model.updateMap(updated)
                        }
                    } label: {
                        Text(layout.shortLabel)
                            .font(.system(size: 11, weight: active ? .medium : .regular))
                            .foregroundStyle(active ? palette.brandInk : palette.textSecondary)
                            .padding(.horizontal, 8)
                            .frame(height: 24)
                            .background(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(active ? palette.surface : Color.clear)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(2)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(palette.softSurface.opacity(palette.isDark ? 0.45 : 0.7))
            )

            // Add child / sibling
            LexiToolButton(title: "+ 子主题", active: false, compact: true) {
                let parentId = activeNode?.id ?? rootNode.id
                recordUndoAndRun {
                    if let createdId = model.addMindNode(mapID: map.id, parentID: parentId, text: "新分支主题") {
                        selectedNodeID = createdId
                    }
                }
            }

            LexiToolButton(title: "+ 同级", active: false, compact: true) {
                guard let current = activeNode, current.id != rootNode.id, !current.parentID.isEmpty else {
                    return
                }
                recordUndoAndRun {
                    if let createdId = model.addMindNode(mapID: map.id, parentID: current.parentID, text: "新同级主题") {
                        selectedNodeID = createdId
                    }
                }
            }
            .disabled(activeNode?.id == rootNode.id)
            .opacity(activeNode?.id == rootNode.id ? 0.45 : 1.0)

            // Undo / Redo
            LexiIconButton(symbol: "arrow.uturn.backward", size: 12.5, frame: 26,
                           active: false, help: "撤销") {
                performUndo()
            }
            .disabled(undoStack.isEmpty)
            .opacity(undoStack.isEmpty ? 0.38 : 1.0)

            LexiIconButton(symbol: "arrow.uturn.forward", size: 12.5, frame: 26,
                           active: false, help: "重做") {
                performRedo()
            }
            .disabled(redoStack.isEmpty)
            .opacity(redoStack.isEmpty ? 0.38 : 1.0)

            // Outline / Map toggle
            LexiToolButton(title: outlineMode ? "导图" : "大纲", active: outlineMode, compact: true) {
                withAnimation(.easeOut(duration: 0.14)) {
                    outlineMode.toggle()
                }
            }

            // More Menu
            Menu {
                Button("适应画布") {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                        zoomScale = 1.0
                        panOffset = .zero
                    }
                }
                Divider()
                Button("导出 Markdown 大纲…") {
                    model.exportMindMapOutline(map)
                }
                Button("导出 JSON 数据…") {
                    model.exportMindMapJSON(map)
                }
                Divider()
                Button("删除思维导图", role: .destructive) {
                    model.deleteMap(map.id)
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 14))
                    .foregroundStyle(palette.textSecondary)
                    .frame(width: 28, height: 28)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()

            // Docked Inspector Toggle
            LexiIconButton(symbol: "sidebar.trailing", size: 13.5, frame: 28,
                           active: inspectorVisible, help: inspectorVisible ? "隐藏节点属性" : "显示节点属性") {
                withAnimation(.easeInOut(duration: 0.16)) {
                    inspectorVisible.toggle()
                }
            }
        }
        .padding(.horizontal, 16)
        .frame(height: Metrics.editorToolbarHeight)
        .overlay(alignment: .bottom) {
            Rectangle().fill(palette.workspaceLine).frame(height: 0.5)
        }
    }

    // MARK: - Mind Map Canvas

    private var canvasArea: some View {
        let layoutResult = MindMapLayoutEngine.compute(map: map)
        let effectiveScale = clampScale(zoomScale * pinchDelta)
        let effectiveOffset = CGSize(
            width: panOffset.width + dragDelta.width,
            height: panOffset.height + dragDelta.height
        )

        return GeometryReader { geo in
            ZStack {
                palette.workspacePage
                    .contentShape(Rectangle())
                    .onTapGesture {
                        inlineEditingNodeID = nil
                        selectedNodeID = rootNode.id
                    }

                // Subtle grid dots
                Canvas { context, size in
                    let step: CGFloat = 24
                    let dotColor = palette.workspaceLine.opacity(0.45)
                    var x = (effectiveOffset.width).truncatingRemainder(dividingBy: step)
                    while x < size.width {
                        var y = (effectiveOffset.height).truncatingRemainder(dividingBy: step)
                        while y < size.height {
                            context.fill(Path(ellipseIn: CGRect(x: x - 0.6, y: y - 0.6, width: 1.2, height: 1.2)), with: .color(dotColor))
                            y += step
                        }
                        x += step
                    }
                }
                .allowsHitTesting(false)

                // World layer
                ZStack {
                    // Curved branches
                    Canvas { context, _ in
                        for edge in layoutResult.edges {
                            guard let from = layoutResult.positions[edge.parentId],
                                  let to = layoutResult.positions[edge.childId] else { continue }
                            var path = Path()
                            path.move(to: from)
                            if map.layout == .org {
                                let midY = (from.y + to.y) / 2
                                path.addCurve(to: to,
                                              control1: CGPoint(x: from.x, y: midY),
                                              control2: CGPoint(x: to.x, y: midY))
                            } else {
                                let midX = (from.x + to.x) / 2
                                path.addCurve(to: to,
                                              control1: CGPoint(x: midX, y: from.y),
                                              control2: CGPoint(x: midX, y: to.y))
                            }
                            context.stroke(path, with: .color(palette.brand.opacity(0.38)), lineWidth: 1.8)
                        }
                    }

                    // Nodes
                    ForEach(layoutResult.visibleNodes) { node in
                        if let pos = layoutResult.positions[node.id] {
                            let level = layoutResult.levels[node.id] ?? 0
                            nodeCard(node: node, level: level)
                                .position(pos)
                        }
                    }
                }
                .frame(width: layoutResult.canvasSize.width, height: layoutResult.canvasSize.height)
                .position(x: geo.size.width / 2 + effectiveOffset.width,
                          y: geo.size.height / 2 + effectiveOffset.height)
                .scaleEffect(effectiveScale, anchor: .center)

                // Floating Zoom Pill
                zoomPill(effectiveScale: effectiveScale)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(16)
            }
            .clipped()
            .gesture(
                DragGesture(minimumDistance: 4)
                    .updating($dragDelta) { value, state, _ in
                        state = value.translation
                    }
                    .onEnded { value in
                        panOffset.width += value.translation.width
                        panOffset.height += value.translation.height
                    }
            )
            .simultaneousGesture(
                MagnificationGesture()
                    .updating($pinchDelta) { value, state, _ in
                        state = value
                    }
                    .onEnded { value in
                        zoomScale = clampScale(zoomScale * value)
                    }
            )
        }
    }

    @ViewBuilder
    private func nodeCard(node: MindNode, level: Int) -> some View {
        let isRoot = node.id == rootNode.id
        let isSelected = selectedNodeID == node.id
        let isEditing = inlineEditingNodeID == node.id
        let accent = Color(hex: node.colorTag.hex)
        let children = map.children(of: node.id)

        HStack(spacing: 6) {
            if !isRoot {
                Circle()
                    .fill(accent)
                    .frame(width: 7, height: 7)
            }

            if isEditing {
                TextField("主题", text: $inlineText)
                    .textFieldStyle(.plain)
                    .font(.system(size: isRoot ? 14 : 12.5, weight: isRoot ? .semibold : .medium))
                    .foregroundStyle(isRoot ? palette.inverseText : palette.textPrimary)
                    .focused($inlineFocused)
                    .frame(minWidth: 72, maxWidth: 200)
                    .onSubmit {
                        commitInlineEdit(for: node)
                    }
            } else {
                Text(node.text.isEmpty ? "未命名主题" : node.text)
                    .font(.system(size: isRoot ? 14 : (level == 1 ? 13 : 12), weight: isRoot ? .semibold : (level == 1 ? .medium : .regular)))
                    .foregroundStyle(isRoot ? palette.inverseText : palette.textPrimary)
                    .lineLimit(2)
            }

            if let nid = node.noteRefID, model.note(nid) != nil {
                Button {
                    model.openNote(nid)
                } label: {
                    Image(systemName: "doc.text.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(isRoot ? palette.inverseText.opacity(0.9) : palette.brandInk)
                }
                .buttonStyle(.plain)
                .help("打开关联笔记")
            }

            if !(node.note ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Image(systemName: "text.alignleft")
                    .font(.system(size: 9.5))
                    .foregroundStyle(isRoot ? palette.inverseText.opacity(0.8) : palette.textSecondary)
            }

            if !children.isEmpty {
                Button {
                    recordUndoAndRun {
                        model.toggleMindNodeCollapsed(mapID: map.id, nodeID: node.id)
                    }
                } label: {
                    Text(node.collapsed ? "+\(countDescendants(node.id))" : "−")
                        .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(palette.brandInk)
                        .padding(.horizontal, 5)
                        .frame(height: 16)
                        .background(Capsule().fill(isRoot ? palette.inverseText.opacity(0.92) : palette.brandSoft))
                }
                .buttonStyle(.plain)
                .help(node.collapsed ? "展开分支" : "折叠分支")
            }
        }
        .padding(.horizontal, isRoot ? 16 : 12)
        .padding(.vertical, isRoot ? 9 : 7)
        .background(
            RoundedRectangle(cornerRadius: isRoot ? 10 : 8, style: .continuous)
                .fill(isRoot ? palette.brand : palette.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: isRoot ? 10 : 8, style: .continuous)
                .stroke(isSelected ? (isRoot ? palette.brandInk : palette.brand) : palette.workspaceLine,
                        lineWidth: isSelected ? 2 : 0.8)
        )
        .shadow(color: palette.shadow.opacity(isSelected ? 1.1 : 0.4), radius: isSelected ? 8 : 3, y: 2)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            selectedNodeID = node.id
            inlineEditingNodeID = node.id
            inlineText = node.text
            inlineFocused = true
        }
        .onTapGesture {
            if let editingId = inlineEditingNodeID, editingId != node.id,
               let previous = map.nodes.first(where: { $0.id == editingId }) {
                commitInlineEdit(for: previous)
            }
            selectedNodeID = node.id
        }
    }

    private func zoomPill(effectiveScale: CGFloat) -> some View {
        HStack(spacing: 4) {
            Button {
                withAnimation(.easeOut(duration: 0.14)) {
                    zoomScale = clampScale(zoomScale - 0.15)
                }
            } label: {
                Image(systemName: "minus")
                    .font(.system(size: 11, weight: .medium))
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)

            Button {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                    zoomScale = 1.0
                    panOffset = .zero
                }
            } label: {
                Text("\(Int(round(effectiveScale * 100)))%")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .frame(minWidth: 42, minHeight: 24, maxHeight: 24)
            }
            .buttonStyle(.plain)
            .help("重置为 100% 并居中")

            Button {
                withAnimation(.easeOut(duration: 0.14)) {
                    zoomScale = clampScale(zoomScale + 0.15)
                }
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .medium))
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
        }
        .foregroundStyle(palette.textPrimary)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(
            Capsule()
                .fill(palette.surface.opacity(0.95))
                .overlay(Capsule().stroke(palette.workspaceLine, lineWidth: 0.7))
        )
        .shadow(color: palette.shadow.opacity(0.55), radius: 8, y: 2)
    }

    // MARK: - Outline View Mode

    private var outlineEditor: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                OutlineNodeRow(
                    model: model,
                    map: map,
                    node: rootNode,
                    depth: 0,
                    selectedNodeID: $selectedNodeID,
                    onMutate: { recordUndoAndRun($0) }
                )
            }
            .padding(24)
            .frame(maxWidth: 780, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Status Bar

    private var statusBar: some View {
        let total = max(1, map.nodes.count)
        return HStack(spacing: 12) {
            Text("\(total) 个主题节点")
                .font(.system(size: 11))
                .foregroundStyle(palette.textSecondary)
            Text("·")
                .foregroundStyle(palette.textSecondary.opacity(0.5))
            Text(map.layout.label)
                .font(.system(size: 11))
                .foregroundStyle(palette.textSecondary)
            Spacer()
            Text("拖拽画布平移 · 滚轮/捏合缩放 · 双击节点重命名")
                .font(.system(size: 11))
                .foregroundStyle(palette.textSecondary.opacity(0.8))
        }
        .padding(.horizontal, 16)
        .frame(height: 28)
        .background(palette.workspacePage)
        .overlay(alignment: .top) {
            Rectangle().fill(palette.workspaceLine).frame(height: 0.5)
        }
    }

    // MARK: - Undo / Redo & Tree Helpers

    private func recordUndoAndRun(_ mutation: () -> Void) {
        undoStack.append(map)
        if undoStack.count > 40 { undoStack.removeFirst() }
        redoStack.removeAll()
        mutation()
    }

    private func performUndo() {
        guard let prev = undoStack.popLast() else { return }
        redoStack.append(map)
        model.updateMap(prev)
    }

    private func performRedo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(map)
        model.updateMap(next)
    }

    private func commitInlineEdit(for node: MindNode) {
        let cleaned = inlineText.trimmingCharacters(in: .whitespacesAndNewlines)
        inlineEditingNodeID = nil
        guard !cleaned.isEmpty, cleaned != node.text else { return }
        let linked = node.noteRefID.flatMap { model.note($0) }
        recordUndoAndRun {
            model.updateMindNode(mapID: map.id, nodeID: node.id, text: cleaned,
                                 note: node.note, colorTag: node.colorTag, noteRef: linked)
        }
    }

    private func clampScale(_ scale: CGFloat) -> CGFloat {
        min(2.2, max(0.4, scale))
    }

    private func countDescendants(_ nodeID: String) -> Int {
        var total = 0
        var stack = map.children(of: nodeID).map(\.id)
        var visited = Set<String>([nodeID])
        while let next = stack.popLast() {
            guard !visited.contains(next) else { continue }
            visited.insert(next)
            total += 1
            stack.append(contentsOf: map.children(of: next).map(\.id))
        }
        return total
    }
}

// MARK: - Docked Node Inspector Panel (236pt)

private struct NodeInspectorPanel: View {
    @ObservedObject var model: AppModel
    let map: MindMap
    let node: MindNode
    @Binding var selectedNodeID: String?
    let onMutate: (() -> Void) -> Void

    @Environment(\.lexiPalette) private var palette
    @State private var draftText: String = ""
    @State private var draftNote: String = ""

    private var rootID: String {
        map.nodes.first(where: { $0.id == map.rootNodeID })?.id ?? map.nodes.first?.id ?? node.id
    }

    private var isRoot: Bool { node.id == rootID }

    private var linkedNote: Note? {
        guard let id = node.noteRefID else { return nil }
        return model.note(id)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("节点属性")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(palette.textPrimary)
                    Spacer()
                    if isRoot {
                        Text("根节点")
                            .font(.system(size: 10))
                            .foregroundStyle(palette.brandInk)
                            .padding(.horizontal, 6)
                            .frame(height: 18)
                            .background(Capsule().fill(palette.brandSoft))
                    }
                }

                // Title
                VStack(alignment: .leading, spacing: 5) {
                    Text("主题文字")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(palette.textSecondary)
                    TextField("输入主题内容", text: $draftText)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12))
                        .onSubmit { saveTextAndNote() }
                        .onChange(of: draftText) { _, newValue in
                            guard newValue != node.text, !newValue.isEmpty else { return }
                            model.updateMindNode(mapID: map.id, nodeID: node.id, text: newValue,
                                                 note: draftNote, colorTag: node.colorTag, noteRef: linkedNote)
                        }
                }

                // Memo
                VStack(alignment: .leading, spacing: 5) {
                    Text("节点备注")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(palette.textSecondary)
                    TextEditor(text: $draftNote)
                        .font(.system(size: 11.5))
                        .scrollContentBackground(.hidden)
                        .padding(6)
                        .frame(minHeight: 74, maxHeight: 120)
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(palette.softSurface.opacity(0.65))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                                        .stroke(palette.workspaceLine, lineWidth: 0.6)
                                )
                        )
                        .onChange(of: draftNote) { _, newValue in
                            guard newValue != (node.note ?? "") else { return }
                            model.updateMindNode(mapID: map.id, nodeID: node.id, text: node.text,
                                                 note: newValue, colorTag: node.colorTag, noteRef: linkedNote)
                        }
                }

                // Actions row
                VStack(alignment: .leading, spacing: 6) {
                    Text("分支操作")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(palette.textSecondary)
                    HStack(spacing: 6) {
                        if !map.children(of: node.id).isEmpty {
                            actionChip(node.collapsed ? "展开" : "折叠", symbol: node.collapsed ? "chevron.down" : "chevron.up") {
                                onMutate {
                                    model.toggleMindNodeCollapsed(mapID: map.id, nodeID: node.id)
                                }
                            }
                        }
                        if !isRoot {
                            actionChip("上移", symbol: "arrow.up") {
                                onMutate { model.moveMindNodeOrder(mapID: map.id, nodeID: node.id, delta: -1) }
                            }
                            actionChip("下移", symbol: "arrow.down") {
                                onMutate { model.moveMindNodeOrder(mapID: map.id, nodeID: node.id, delta: 1) }
                            }
                        }
                    }
                    if !isRoot {
                        Button(role: .destructive) {
                            let fallbackId = rootID
                            onMutate {
                                model.deleteMindNode(mapID: map.id, nodeID: node.id)
                                selectedNodeID = fallbackId
                            }
                        } label: {
                            Label("删除此节点及子分支", systemImage: "trash")
                                .font(.system(size: 11))
                                .foregroundStyle(palette.error)
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 2)
                    }
                }

                // Color Tag
                VStack(alignment: .leading, spacing: 6) {
                    Text("颜色标记")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(palette.textSecondary)
                    HStack(spacing: 8) {
                        ForEach(NoteColorTag.allCases) { tag in
                            Button {
                                onMutate {
                                    model.updateMindNode(mapID: map.id, nodeID: node.id, text: node.text,
                                                         note: node.note, colorTag: tag, noteRef: linkedNote)
                                }
                            } label: {
                                ZStack {
                                    Circle()
                                        .fill(Color(hex: tag.hex))
                                        .frame(width: 22, height: 22)
                                    if node.colorTag == tag {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 10, weight: .bold))
                                            .foregroundStyle(Color.white)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                            .help(tag.label)
                        }
                    }
                }

                // Linked Note
                VStack(alignment: .leading, spacing: 6) {
                    Text("关联笔记")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(palette.textSecondary)

                    if let note = linkedNote {
                        HStack(spacing: 6) {
                            Button {
                                model.openNote(note.id)
                            } label: {
                                HStack(spacing: 5) {
                                    Image(systemName: "doc.text")
                                        .font(.system(size: 11))
                                    Text(note.displayTitle)
                                        .font(.system(size: 11.5, weight: .medium))
                                        .lineLimit(1)
                                }
                                .foregroundStyle(palette.brandInk)
                            }
                            .buttonStyle(.plain)
                            Spacer()
                            Button {
                                onMutate {
                                    model.updateMindNode(mapID: map.id, nodeID: node.id, text: node.text,
                                                         note: node.note, colorTag: node.colorTag, noteRef: nil)
                                }
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 9))
                                    .foregroundStyle(palette.textSecondary)
                            }
                            .buttonStyle(.plain)
                            .help("解除关联")
                        }
                        .padding(8)
                        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(palette.brandSoft))
                    } else {
                        Button {
                            onMutate {
                                if let created = model.createNoteFromMindNode(mapID: map.id, nodeID: node.id) {
                                    model.openNote(created.id)
                                }
                            }
                        } label: {
                            Label("新建并关联笔记", systemImage: "plus.rectangle.on.folder")
                                .font(.system(size: 11.5, weight: .medium))
                                .foregroundStyle(palette.brandInk)
                                .frame(maxWidth: .infinity)
                                .frame(height: 30)
                                .background(
                                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                                        .fill(palette.workspaceSelection)
                                )
                        }
                        .buttonStyle(.plain)

                        let notes = model.visibleNotes
                        if !notes.isEmpty {
                            Menu("关联已有笔记…") {
                                ForEach(notes.prefix(30)) { item in
                                    Button(item.displayTitle) {
                                        onMutate {
                                            model.updateMindNode(mapID: map.id, nodeID: node.id, text: node.text,
                                                                 note: node.note, colorTag: node.colorTag, noteRef: item)
                                        }
                                    }
                                }
                            }
                            .font(.system(size: 11))
                        }
                    }
                }
            }
            .padding(14)
        }
        .background(palette.workspaceInspector)
        .overlay(alignment: .leading) {
            Rectangle().fill(palette.workspaceLine).frame(width: 0.5)
        }
        .onAppear { syncDrafts() }
        .onChange(of: node.id) { _, _ in syncDrafts() }
    }

    private func syncDrafts() {
        draftText = node.text
        draftNote = node.note ?? ""
    }

    private func saveTextAndNote() {
        let trimmed = draftText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        onMutate {
            model.updateMindNode(mapID: map.id, nodeID: node.id, text: trimmed,
                                 note: draftNote, colorTag: node.colorTag, noteRef: linkedNote)
        }
    }

    private func actionChip(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 3) {
                Image(systemName: symbol).font(.system(size: 9.5))
                Text(title).font(.system(size: 11))
            }
            .foregroundStyle(palette.textPrimary)
            .padding(.horizontal, 8)
            .frame(height: 24)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(palette.softSurface))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Outline Mode Row

private struct OutlineNodeRow: View {
    @ObservedObject var model: AppModel
    let map: MindMap
    let node: MindNode
    let depth: Int
    @Binding var selectedNodeID: String?
    let onMutate: (() -> Void) -> Void

    @Environment(\.lexiPalette) private var palette

    var body: some View {
        let children = map.children(of: node.id)
        VStack(alignment: .leading, spacing: 4) {
            let selected = selectedNodeID == node.id
            HStack(spacing: 8) {
                if !children.isEmpty {
                    Button {
                        onMutate { model.toggleMindNodeCollapsed(mapID: map.id, nodeID: node.id) }
                    } label: {
                        Image(systemName: node.collapsed ? "chevron.right" : "chevron.down")
                            .font(.system(size: 9.5, weight: .semibold))
                            .foregroundStyle(palette.textSecondary)
                            .frame(width: 16, height: 16)
                    }
                    .buttonStyle(.plain)
                } else {
                    Circle()
                        .fill(Color(hex: node.colorTag.hex))
                        .frame(width: 6, height: 6)
                        .padding(.horizontal, 5)
                }

                Text(node.text.isEmpty ? "未命名" : node.text)
                    .font(.system(size: depth == 0 ? 15 : 13, weight: depth == 0 ? .semibold : .regular))
                    .foregroundStyle(palette.textPrimary)

                Spacer()

                Button {
                    onMutate {
                        if let nid = model.addMindNode(mapID: map.id, parentID: node.id, text: "新子主题") {
                            selectedNodeID = nid
                        }
                    }
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 10.5))
                        .foregroundStyle(palette.brandInk)
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .help("添加子主题")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(selected ? palette.workspaceSelection : Color.clear)
            )
            .contentShape(Rectangle())
            .onTapGesture { selectedNodeID = node.id }
            .padding(.leading, CGFloat(depth * 20))

            if !node.collapsed {
                ForEach(children) { child in
                    OutlineNodeRow(
                        model: model,
                        map: map,
                        node: child,
                        depth: depth + 1,
                        selectedNodeID: $selectedNodeID,
                        onMutate: onMutate
                    )
                }
            }
        }
    }
}

// MARK: - Layout Engine (.right / .balanced / .org + collapse)

struct MindMapEdge: Identifiable {
    let id: String
    let parentId: String
    let childId: String
}

struct MindMapLayoutResult {
    var positions: [String: CGPoint]
    var levels: [String: Int]
    var visibleNodes: [MindNode]
    var edges: [MindMapEdge]
    var canvasSize: CGSize
}

enum MindMapLayoutEngine {
    static func compute(map: MindMap) -> MindMapLayoutResult {
        let root = map.nodes.first(where: { $0.id == map.rootNodeID }) ?? map.nodes.first ?? MindNode(text: map.title)
        var positions: [String: CGPoint] = [:]
        var levels: [String: Int] = [:]
        var visible: [MindNode] = []
        var edges: [MindMapEdge] = []
        var visited = Set<String>()

        func collect(_ node: MindNode, level: Int) {
            guard !visited.contains(node.id) else { return }
            visited.insert(node.id)
            levels[node.id] = level
            visible.append(node)
            guard !node.collapsed else { return }
            for child in map.children(of: node.id) {
                edges.append(MindMapEdge(id: "\(node.id)->\(child.id)", parentId: node.id, childId: child.id))
                collect(child, level: level + 1)
            }
        }
        collect(root, level: 0)

        switch map.layout {
        case .org:
            func subtreeWidth(_ node: MindNode) -> CGFloat {
                let kids = map.children(of: node.id)
                if node.collapsed || kids.isEmpty { return 165 }
                return max(165, kids.reduce(0) { $0 + subtreeWidth($1) })
            }
            func placeOrg(_ node: MindNode, centerX: CGFloat, y: CGFloat) {
                positions[node.id] = CGPoint(x: centerX, y: y)
                let kids = map.children(of: node.id)
                guard !node.collapsed, !kids.isEmpty else { return }
                let totalW = subtreeWidth(node)
                var cursorX = centerX - totalW / 2
                for child in kids {
                    let w = subtreeWidth(child)
                    placeOrg(child, centerX: cursorX + w / 2, y: y + 88)
                    cursorX += w
                }
            }
            placeOrg(root, centerX: 0, y: 0)

        case .right, .balanced:
            func subtreeHeight(_ node: MindNode) -> CGFloat {
                let kids = map.children(of: node.id)
                if node.collapsed || kids.isEmpty { return 54 }
                return max(54, kids.reduce(0) { $0 + subtreeHeight($1) })
            }
            func placeBranch(_ node: MindNode, x: CGFloat, centerY: CGFloat, dir: CGFloat) {
                positions[node.id] = CGPoint(x: x, y: centerY)
                let kids = map.children(of: node.id)
                guard !node.collapsed, !kids.isEmpty else { return }
                let totalH = subtreeHeight(node)
                var cursorY = centerY - totalH / 2
                for child in kids {
                    let h = subtreeHeight(child)
                    placeBranch(child, x: x + dir * 210, centerY: cursorY + h / 2, dir: dir)
                    cursorY += h
                }
            }

            if map.layout == .right || root.collapsed {
                placeBranch(root, x: 0, centerY: 0, dir: 1)
            } else {
                positions[root.id] = .zero
                let rootKids = map.children(of: root.id)
                let rightChildren = rootKids.enumerated().compactMap { $0.offset % 2 == 0 ? $0.element : nil }
                let leftChildren = rootKids.enumerated().compactMap { $0.offset % 2 == 1 ? $0.element : nil }

                func placeSide(_ items: [MindNode], dir: CGFloat) {
                    let totalH = items.reduce(0) { $0 + subtreeHeight($1) }
                    var cursorY = -totalH / 2
                    for child in items {
                        let h = subtreeHeight(child)
                        placeBranch(child, x: dir * 220, centerY: cursorY + h / 2, dir: dir)
                        cursorY += h
                    }
                }
                placeSide(rightChildren, dir: 1)
                placeSide(leftChildren, dir: -1)
            }
        }

        // Normalize into positive world canvas
        let allPoints = Array(positions.values)
        let minX = (allPoints.map(\.x).min() ?? 0) - 180
        let maxX = (allPoints.map(\.x).max() ?? 0) + 180
        let minY = (allPoints.map(\.y).min() ?? 0) - 120
        let maxY = (allPoints.map(\.y).max() ?? 0) + 120
        let width = max(720, maxX - minX)
        let height = max(480, maxY - minY)
        let centerX = (minX + maxX) / 2
        let centerY = (minY + maxY) / 2
        let shiftX = width / 2 - centerX
        let shiftY = height / 2 - centerY

        var shifted: [String: CGPoint] = [:]
        for (id, pt) in positions {
            shifted[id] = CGPoint(x: pt.x + shiftX, y: pt.y + shiftY)
        }

        return MindMapLayoutResult(
            positions: shifted,
            levels: levels,
            visibleNodes: visible,
            edges: edges,
            canvasSize: CGSize(width: width, height: height)
        )
    }
}
