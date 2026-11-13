import SwiftUI
import AppKit

struct CanvasWorkspaceView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var settings: SettingsStore
    let board: CanvasBoard
    @Environment(\.lexiPalette) private var palette

    @State private var selectedCard: CanvasCard?
    @State private var editingCard: CanvasCard?
    @State private var dragOffsets: [String: CGSize] = [:]
    @State private var zoom: CGFloat = 1
    @State private var pan: CGSize = .zero

    private var current: CanvasBoard { model.canvas(board.id) ?? board }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            GeometryReader { geometry in
                canvas(viewport: geometry.size)
            }
            .background(palette.workspacePage)
        }
        .background(palette.workspacePage)
        .sheet(item: $editingCard) { card in
            CanvasCardEditorSheet(card: card, notes: model.notes.filter { !$0.isTrashed }) { title, content, note in
                update(card: card, title: title, content: content, note: note)
            }
        }
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            TextField("未命名白板", text: titleBinding)
                .textFieldStyle(.plain)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(palette.textPrimary)
                .frame(maxWidth: 260, alignment: .leading)
            Text("\(current.cards.count) 张卡片 · \(current.edges.count) 条连线")
                .font(.system(size: 11))
                .foregroundStyle(palette.textSecondary)
            Spacer()
            LexiToolButton(title: "添加卡片", symbol: "plus", compact: true) {
                addCard()
            }
            LexiToolButton(title: "编辑", symbol: "pencil", compact: true) {
                if let selectedCard { editingCard = selectedCard }
            }
            LexiIconButton(symbol: "arrow.up.left.and.arrow.down.right", size: 12, frame: 28, help: "重置视图") {
                withAnimation(.easeOut(duration: 0.2)) {
                    zoom = 1
                    pan = .zero
                }
            }
            Menu {
                Button("删除选中卡片", role: .destructive) {
                    if let selectedCard { delete(card: selectedCard) }
                }
                Button("整理卡片位置") { tidyCards() }
            } label: {
                Text("更多")
                    .font(.system(size: 11.5))
                    .foregroundStyle(palette.textSecondary)
                    .padding(.horizontal, 8)
                    .frame(height: 28)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .padding(.horizontal, 20)
        .frame(height: 48)
        .overlay(alignment: .bottom) {
            Rectangle().fill(palette.workspaceLine).frame(height: 0.5)
        }
    }

    private func canvas(viewport: CGSize) -> some View {
        let contentSize = canvasSize()
        return ZStack {
            dotGrid
            ZStack(alignment: .topLeading) {
                Canvas { context, _ in
                    for edge in current.edges {
                        guard let from = current.cards.first(where: { $0.id == edge.fromID }),
                              let to = current.cards.first(where: { $0.id == edge.toID }) else { continue }
                        let start = cardCenter(from)
                        let end = cardCenter(to)
                        var path = Path()
                        path.move(to: start)
                        let midY = (start.y + end.y) / 2
                        path.addCurve(to: end,
                                      control1: CGPoint(x: start.x, y: midY),
                                      control2: CGPoint(x: end.x, y: midY))
                        context.stroke(path,
                                       with: .color(palette.brand.opacity(0.32)),
                                       style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                        let labelPoint = CGPoint(x: (start.x + end.x) / 2, y: midY)
                        context.draw(Text(edge.label)
                                        .font(.system(size: 9.5, weight: .medium))
                                        .foregroundColor(palette.brandInk.opacity(0.8)),
                                     at: labelPoint)
                    }
                }
                .frame(width: contentSize.width, height: contentSize.height)

                ForEach(current.cards) { card in
                    CanvasCardView(card: card,
                                   palette: palette,
                                   selected: selectedCard?.id == card.id,
                                   hasNote: card.noteRefID != nil,
                                   onOpenNote: {
                                       if let id = card.noteRefID { model.openNote(id) }
                                   })
                        .frame(width: 220, height: 112)
                        .position(cardCenter(card))
                        .gesture(dragGesture(card))
                        .onTapGesture { selectedCard = card }
                        .onTapGesture(count: 2) { editingCard = card }
                        .contextMenu {
                            Button("编辑卡片") { editingCard = card }
                            if let id = card.noteRefID {
                                Button("打开关联笔记") { model.openNote(id) }
                            }
                            Divider()
                            Button("删除卡片", role: .destructive) { delete(card: card) }
                        }
                }
            }
            .frame(width: contentSize.width, height: contentSize.height)
            .scaleEffect(zoom)
            .position(x: viewport.width / 2 + pan.width,
                      y: viewport.height / 2 + pan.height)

            VStack {
                Spacer()
                HStack {
                    Text("拖动卡片整理思路 · 双击编辑 · 拖动空白平移")
                        .font(.system(size: 10))
                        .foregroundStyle(palette.textSecondary.opacity(0.85))
                        .padding(.horizontal, 10)
                        .frame(height: 24)
                        .background(Capsule().fill(palette.workspacePage.opacity(0.9)))
                    Spacer()
                    Text("\(Int(zoom * 100))%")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(palette.textSecondary)
                }
                .padding(16)
            }
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture()
                .onChanged { value in
                    pan = CGSize(width: value.translation.width, height: value.translation.height)
                }
        )
        .simultaneousGesture(
            MagnificationGesture()
                .onChanged { value in zoom = clamp(value, 0.35, 2) }
        )
        .background(palette.workspacePage)
    }

    private var dotGrid: some View {
        Canvas { context, size in
            let step: CGFloat = 22
            var x: CGFloat = 0
            while x < size.width {
                var y: CGFloat = 0
                while y < size.height {
                    context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 1.3, height: 1.3)),
                                 with: .color(palette.workspaceLine.opacity(0.45)))
                    y += step
                }
                x += step
            }
        }
        .allowsHitTesting(false)
    }

    private var titleBinding: Binding<String> {
        Binding(get: { current.title }, set: { value in
            var copy = current
            copy.title = value
            copy.updatedAt = Date()
            model.updateCanvas(copy)
        })
    }

    private func canvasSize() -> CGSize {
        let maxX = current.cards.map { $0.x + 220 }.max() ?? 600
        let maxY = current.cards.map { $0.y + 112 }.max() ?? 400
        return CGSize(width: max(880, maxX + 180), height: max(520, maxY + 160))
    }

    private func cardCenter(_ card: CanvasCard) -> CGPoint {
        let offset = dragOffsets[card.id] ?? .zero
        return CGPoint(x: card.x + 110 + offset.width, y: card.y + 56 + offset.height)
    }

    private func dragGesture(_ card: CanvasCard) -> some Gesture {
        DragGesture()
            .onChanged { value in
                dragOffsets[card.id] = CGSize(width: value.translation.width / zoom,
                                              height: value.translation.height / zoom)
            }
            .onEnded { _ in
                let offset = dragOffsets[card.id] ?? .zero
                dragOffsets[card.id] = nil
                guard var copy = model.canvas(current.id),
                      let index = copy.cards.firstIndex(where: { $0.id == card.id }) else { return }
                copy.cards[index].x += offset.width
                copy.cards[index].y += offset.height
                copy.updatedAt = Date()
                model.updateCanvas(copy)
            }
    }

    private func addCard() {
        guard var copy = model.canvas(current.id) else { return }
        let count = copy.cards.count
        let colors = NoteColorTag.allCases
        let card = CanvasCard(id: "card-\(UUID().uuidString.lowercased())",
                              title: "新卡片", content: "写下这张卡片想表达的内容。",
                              noteRefID: nil, noteRefTitle: nil,
                              x: 60 + Double(count % 3) * 250,
                              y: 70 + Double(count / 3) * 150,
                              colorTag: colors[count % colors.count])
        copy.cards.append(card)
        copy.updatedAt = Date()
        model.updateCanvas(copy)
        selectedCard = card
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            editingCard = card
        }
    }

    private func update(card: CanvasCard, title: String, content: String, note: Note?) {
        guard var copy = model.canvas(current.id),
              let index = copy.cards.firstIndex(where: { $0.id == card.id }) else { return }
        copy.cards[index].title = title
        copy.cards[index].content = content
        copy.cards[index].noteRefID = note?.id
        copy.cards[index].noteRefTitle = note?.displayTitle
        copy.updatedAt = Date()
        model.updateCanvas(copy)
        selectedCard = copy.cards[index]
    }

    private func delete(card: CanvasCard) {
        guard var copy = model.canvas(current.id) else { return }
        copy.cards.removeAll { $0.id == card.id }
        copy.edges.removeAll { $0.fromID == card.id || $0.toID == card.id }
        copy.updatedAt = Date()
        model.updateCanvas(copy)
        if selectedCard?.id == card.id { selectedCard = nil }
        model.showToast("已删除卡片", symbol: "trash")
    }

    private func tidyCards() {
        guard var copy = model.canvas(current.id), !copy.cards.isEmpty else { return }
        let columns = max(1, Int(sqrt(Double(copy.cards.count))))
        for index in copy.cards.indices {
            copy.cards[index].x = 60 + Double(index % columns) * 250
            copy.cards[index].y = 70 + Double(index / columns) * 150
        }
        copy.updatedAt = Date()
        model.updateCanvas(copy)
        dragOffsets = [:]
        withAnimation(.easeInOut(duration: 0.2)) { pan = .zero; zoom = 1 }
    }
}

private struct CanvasCardView: View {
    let card: CanvasCard
    let palette: ThemePalette
    let selected: Bool
    let hasNote: Bool
    let onOpenNote: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Circle()
                    .fill(card.colorTag.color)
                    .frame(width: 7, height: 7)
                Text(card.title)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            Text(card.content)
                .font(.system(size: 10.5))
                .foregroundStyle(palette.textSecondary)
                .lineSpacing(2)
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)
            Spacer(minLength: 0)
            if let title = card.noteRefTitle, hasNote {
                Button(action: onOpenNote) {
                    HStack(spacing: 4) {
                        Image(systemName: "link").font(.system(size: 8))
                        Text(title)
                            .font(.system(size: 9.5))
                            .lineLimit(1)
                    }
                    .foregroundStyle(palette.brandInk)
                    .padding(.horizontal, 6)
                    .frame(height: 18)
                    .background(Capsule().fill(palette.brandSoft))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(palette.surface)
        )
        .overlay(alignment: .top) {
            UnevenRoundedRectangle(topLeadingRadius: 12, bottomLeadingRadius: 0,
                                   bottomTrailingRadius: 0, topTrailingRadius: 12)
                .fill(card.colorTag.color.opacity(0.75))
                .frame(height: 3)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(selected ? palette.brand : palette.workspaceLine, lineWidth: selected ? 2 : 1)
        )
        .shadow(color: palette.shadow.opacity(0.6), radius: 8, x: 0, y: 4)
    }
}

private struct CanvasCardEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.lexiPalette) private var palette
    let card: CanvasCard
    let notes: [Note]
    let onSave: (String, String, Note?) -> Void

    @State private var title: String
    @State private var content: String
    @State private var noteID: String

    init(card: CanvasCard, notes: [Note], onSave: @escaping (String, String, Note?) -> Void) {
        self.card = card
        self.notes = notes
        self.onSave = onSave
        _title = State(initialValue: card.title)
        _content = State(initialValue: card.content)
        _noteID = State(initialValue: card.noteRefID ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("编辑卡片")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                Spacer()
                Button("关闭") { dismiss() }
                    .buttonStyle(.plain)
                    .font(.system(size: 11.5))
                    .foregroundStyle(palette.textSecondary)
            }
            TextField("卡片标题", text: $title)
                .textFieldStyle(.plain)
                .font(.system(size: 15, weight: .semibold))
            TextEditor(text: $content)
                .font(.system(size: 12.5))
                .scrollContentBackground(.hidden)
                .padding(8)
                .frame(height: 110)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(palette.softSurface.opacity(palette.isDark ? 0.4 : 0.6))
                )
            HStack(spacing: 8) {
                Text("关联笔记")
                    .font(.system(size: 11.5))
                    .foregroundStyle(palette.textSecondary)
                Menu {
                    Button("无") { noteID = "" }
                    Divider()
                    ForEach(notes) { note in
                        Button(note.displayTitle) { noteID = note.id }
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "link").font(.system(size: 9))
                        Text(notes.first(where: { $0.id == noteID })?.displayTitle ?? "选择笔记")
                            .font(.system(size: 11.5))
                            .lineLimit(1)
                        Image(systemName: "chevron.down").font(.system(size: 7, weight: .semibold))
                    }
                    .foregroundStyle(palette.brandInk)
                    .padding(.horizontal, 8)
                    .frame(height: 26)
                    .background(Capsule().fill(palette.brandSoft))
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                Spacer()
            }
            HStack {
                Spacer()
                Button("取消") { dismiss() }
                    .buttonStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(palette.textSecondary)
                Button {
                    onSave(title.isEmpty ? "未命名卡片" : title,
                           content,
                           notes.first(where: { $0.id == noteID }))
                    dismiss()
                } label: {
                    Text("保存")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(palette.inverseText)
                        .padding(.horizontal, 18)
                        .frame(height: 30)
                        .background(RoundedRectangle(cornerRadius: 8).fill(palette.brand))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(22)
        .frame(width: 480)
        .background(palette.workspacePage)
    }
}
