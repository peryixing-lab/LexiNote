import SwiftUI
import AppKit

struct GraphWorkspaceView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var settings: SettingsStore
    @Environment(\.lexiPalette) private var palette

    @State private var filter = ""
    @State private var hovered: String?
    @State private var selected: String?
    @State private var zoom: CGFloat = 1
    @State private var pan: CGSize = .zero
    @State private var dragOffsets: [String: CGSize] = [:]
    @State private var dragStart: [String: CGSize] = [:]
    @State private var seed = 0

    private var graph: GraphData { model.graphData() }

    private var visibleIDs: Set<String> {
        guard !filter.trimmingCharacters(in: .whitespaces).isEmpty else {
            return Set(graph.nodes.map(\.id))
        }
        return Set(graph.nodes.filter {
            NoteSearch.rank($0.title, filter) >= 0 || $0.notebook.localizedCaseInsensitiveContains(filter)
        }.map(\.id))
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            GeometryReader { geometry in
                if graph.nodes.isEmpty {
                    EmptyStatePanel(symbol: "point.3.connected.trianglepath.dotted",
                                    title: "还没有可以连接的笔记",
                                    detail: "用 [[双向链接]] 把笔记串联起来，图谱会在这里生长。")
                } else {
                    graphCanvas(size: geometry.size)
                }
            }
            .background(palette.workspacePage)
        }
        .background(palette.workspacePage)
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            Text("关系图谱")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(palette.textPrimary)
            Text("\(graph.nodes.count) 篇笔记 · \(graph.edges.count) 条连接")
                .font(.system(size: 11))
                .foregroundStyle(palette.textSecondary)
            Spacer()
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 10))
                    .foregroundStyle(palette.textSecondary)
                TextField("筛选笔记", text: $filter)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11.5))
                    .frame(width: 130)
            }
            .padding(.horizontal, 9)
            .frame(height: 28)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(palette.softSurface)
            )
            LexiIconButton(symbol: "minus.magnifyingglass", size: 13, frame: 28, help: "缩小") {
                withAnimation(.easeOut(duration: 0.15)) { zoom = max(0.45, zoom - 0.1) }
            }
            Text("\(Int(zoom * 100))%")
                .font(.system(size: 10.5, design: .monospaced))
                .foregroundStyle(palette.textSecondary)
                .frame(width: 36)
            LexiIconButton(symbol: "plus.magnifyingglass", size: 13, frame: 28, help: "放大") {
                withAnimation(.easeOut(duration: 0.15)) { zoom = min(2, zoom + 0.1) }
            }
            LexiIconButton(symbol: "arrow.counterclockwise", size: 12, frame: 28, help: "重新布局") {
                withAnimation(.easeInOut(duration: 0.3)) {
                    seed += 1
                    dragOffsets = [:]
                    zoom = 1
                    pan = .zero
                }
            }
        }
        .padding(.horizontal, 20)
        .frame(height: 48)
        .overlay(alignment: .bottom) {
            Rectangle().fill(palette.workspaceLine).frame(height: 0.5)
        }
    }

    private func graphCanvas(size: CGSize) -> some View {
        let layout = ForceGraphLayout.compute(nodes: graph.nodes, edges: graph.edges, size: size, seed: seed)
        let positions = finalPositions(layout)
        let focused = hovered ?? selected
        return ZStack {
            dotGrid
            Canvas { context, _ in
                for edge in graph.edges {
                    guard let from = positions[edge.source], let to = positions[edge.target] else { continue }
                    let highlighted = focused == edge.source || focused == edge.target
                    let visible = visibleIDs.contains(edge.source) && visibleIDs.contains(edge.target)
                    var path = Path()
                    let mid = CGPoint(x: (from.x + to.x) / 2, y: (from.y + to.y) / 2)
                    let dx = to.x - from.x
                    let dy = to.y - from.y
                    let normal = CGVector(dx: -dy, dy: dx)
                    let length = max(sqrt(dx * dx + dy * dy), 1)
                    let bend = min(26, length * 0.12)
                    let control = CGPoint(x: mid.x + normal.dx / length * bend, y: mid.y + normal.dy / length * bend)
                    path.move(to: from)
                    path.addQuadCurve(to: to, control: control)
                    context.stroke(path,
                                   with: .color(highlighted ? palette.brand.opacity(0.65) : palette.workspaceLine.opacity(visible ? 0.9 : 0.35)),
                                   lineWidth: highlighted ? 1.6 : 1)
                }
            }
            .allowsHitTesting(false)

            ForEach(graph.nodes) { node in
                if let position = positions[node.id] {
                    GraphNodeView(node: node,
                                  palette: palette,
                                  highlighted: focused == node.id,
                                  dimmed: !visibleIDs.contains(node.id) || (focused != nil && !neighbors(of: focused).contains(node.id) && focused != node.id),
                                  isSelected: selected == node.id)
                        .position(position)
                        .gesture(nodeDrag(node.id))
                        .onHover { inside in
                            hovered = inside ? node.id : (hovered == node.id ? nil : hovered)
                        }
                        .onTapGesture(count: 2) {
                            model.openNote(node.id)
                        }
                        .onTapGesture {
                            selected = selected == node.id ? nil : node.id
                        }
                        .help("\(node.title) · \(node.notebook) · 双击打开")
                }
            }

            VStack {
                Spacer()
                HStack(alignment: .bottom) {
                    legend
                    Spacer()
                    Text("拖动节点调整布局 · 双击打开 · 拖动空白平移")
                        .font(.system(size: 10))
                        .foregroundStyle(palette.textSecondary.opacity(0.8))
                        .padding(.horizontal, 10)
                        .frame(height: 24)
                        .background(Capsule().fill(palette.workspacePage.opacity(0.85)))
                }
                .padding(16)
            }
        }
        .scaleEffect(zoom)
        .offset(pan)
        .clipped()
        .contentShape(Rectangle())
        .gesture(
            DragGesture()
                .onChanged { value in
                    pan = CGSize(width: value.translation.width, height: value.translation.height)
                }
        )
        .gesture(
            MagnificationGesture()
                .onChanged { value in zoom = clamp(value, 0.45, 2) }
        )
        .onTapGesture {
            selected = nil
        }
        .background(palette.workspacePage)
    }

    private var dotGrid: some View {
        Canvas { context, size in
            let step: CGFloat = 22
            var x: CGFloat = 0
            while x < size.width {
                var y: CGFloat = 0
                while y < size.height {
                    let rect = CGRect(x: x, y: y, width: 1.4, height: 1.4)
                    context.fill(Path(ellipseIn: rect), with: .color(palette.workspaceLine.opacity(0.55)))
                    y += step
                }
                x += step
            }
        }
        .allowsHitTesting(false)
    }

    private var legend: some View {
        HStack(spacing: 10) {
            ForEach(Array(Set(graph.nodes.map(\.notebook))).sorted().prefix(5), id: \.self) { notebook in
                if let node = graph.nodes.first(where: { $0.notebook == notebook }) {
                    HStack(spacing: 4) {
                        Circle().fill(node.colorTag.color).frame(width: 7, height: 7)
                        Text(notebook)
                            .font(.system(size: 9.5))
                            .foregroundStyle(palette.textSecondary)
                    }
                }
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 24)
        .background(Capsule().fill(palette.workspacePage.opacity(0.88)))
        .overlay(Capsule().stroke(palette.workspaceLine.opacity(0.7), lineWidth: 0.6))
    }

    private func finalPositions(_ layout: [String: CGPoint]) -> [String: CGPoint] {
        var result: [String: CGPoint] = [:]
        for (id, point) in layout {
            let offset = dragOffsets[id] ?? .zero
            result[id] = CGPoint(x: point.x + offset.width, y: point.y + offset.height)
        }
        return result
    }

    private func neighbors(of id: String?) -> Set<String> {
        guard let id else { return [] }
        var result: Set<String> = [id]
        for edge in graph.edges {
            if edge.source == id { result.insert(edge.target) }
            if edge.target == id { result.insert(edge.source) }
        }
        return result
    }

    private func nodeDrag(_ id: String) -> some Gesture {
        DragGesture()
            .onChanged { value in
                if dragStart[id] == nil { dragStart[id] = dragOffsets[id] ?? .zero }
                let base = dragStart[id] ?? .zero
                dragOffsets[id] = CGSize(width: base.width + value.translation.width / zoom,
                                         height: base.height + value.translation.height / zoom)
            }
            .onEnded { _ in
                dragStart[id] = nil
            }
    }
}

private struct GraphNodeView: View {
    let node: GraphNode
    let palette: ThemePalette
    let highlighted: Bool
    let dimmed: Bool
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                Circle()
                    .fill(node.colorTag.color.opacity(highlighted || isSelected ? 1 : 0.82))
                    .frame(width: radius * 2, height: radius * 2)
                if highlighted || isSelected {
                    Circle()
                        .stroke(node.colorTag.color.opacity(0.35), lineWidth: 5)
                        .frame(width: radius * 2 + 10, height: radius * 2 + 10)
                }
                if highlighted || isSelected {
                    Text("\(node.degree)")
                        .font(.system(size: 8, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.92))
                }
            }
            Text(node.title)
                .font(.system(size: 11, weight: highlighted || isSelected ? .semibold : .regular))
                .foregroundStyle(palette.textPrimary)
                .lineLimit(1)
                .padding(.horizontal, 6)
                .frame(height: 18)
                .background(
                    Capsule().fill(palette.workspacePage.opacity(0.92))
                )
        }
        .opacity(dimmed ? 0.32 : 1)
        .scaleEffect(highlighted || isSelected ? 1.06 : 1)
        .animation(.easeOut(duration: 0.12), value: highlighted)
        .animation(.easeOut(duration: 0.12), value: isSelected)
    }

    private var radius: CGFloat {
        clamp(8 + CGFloat(node.degree) * 2.1, 8, 17)
    }
}

enum ForceGraphLayout {
    static func compute(nodes: [GraphNode], edges: [GraphEdge], size: CGSize, seed: Int = 0) -> [String: CGPoint] {
        guard !nodes.isEmpty else { return [:] }
        let width = max(size.width, 320)
        let height = max(size.height, 240)
        let center = CGPoint(x: width / 2, y: height / 2)
        var positions: [String: CGPoint] = [:]
        var velocities: [String: CGVector] = [:]

        for (index, node) in nodes.enumerated() {
            let angle = (Double(index) / Double(nodes.count)) * 2 * Double.pi
            let radius = min(width, height) * 0.27
            let jitter = pseudoRandom(node.id, seed) * 26
            positions[node.id] = CGPoint(x: center.x + CGFloat(cos(angle)) * (radius + jitter),
                                         y: center.y + CGFloat(sin(angle)) * (radius + jitter))
            velocities[node.id] = .zero
        }
        guard nodes.count > 1 else {
            positions[nodes[0].id] = center
            return positions
        }

        let area = width * height
        let k = sqrt(area / CGFloat(nodes.count)) * 0.9
        let idSet = Set(nodes.map(\.id))
        let iterations = nodes.count > 28 ? 190 : 300

        for iteration in 0..<iterations {
            let temperature = 1.0 - Double(iteration) / Double(iterations)
            var forces: [String: CGVector] = [:]
            for id in idSet { forces[id] = .zero }

            for i in 0..<nodes.count {
                for j in (i + 1)..<nodes.count {
                    let idA = nodes[i].id
                    let idB = nodes[j].id
                    guard let a = positions[idA], let b = positions[idB] else { continue }
                    var dx = a.x - b.x
                    var dy = a.y - b.y
                    var distance = sqrt(dx * dx + dy * dy)
                    if distance < 0.6 { dx = 0.6; dy = 0.4; distance = 0.72 }
                    let repulsion = (k * k) / distance * 0.85
                    let fx = dx / distance * repulsion
                    let fy = dy / distance * repulsion
                    if var forceA = forces[idA] {
                        forceA.dx += fx; forceA.dy += fy; forces[idA] = forceA
                    }
                    if var forceB = forces[idB] {
                        forceB.dx -= fx; forceB.dy -= fy; forces[idB] = forceB
                    }
                }
            }

            for edge in edges {
                guard idSet.contains(edge.source), idSet.contains(edge.target),
                      let a = positions[edge.source], let b = positions[edge.target] else { continue }
                var dx = b.x - a.x
                var dy = b.y - a.y
                var distance = sqrt(dx * dx + dy * dy)
                if distance < 0.8 { dx = 0.8; dy = 0.5; distance = 0.94 }
                let attraction = (distance * distance) / k * 0.48
                let fx = dx / distance * attraction
                let fy = dy / distance * attraction
                if var forceA = forces[edge.source] {
                    forceA.dx += fx; forceA.dy += fy; forces[edge.source] = forceA
                }
                if var forceB = forces[edge.target] {
                    forceB.dx -= fx; forceB.dy -= fy; forces[edge.target] = forceB
                }
            }

            for node in nodes {
                guard var force = forces[node.id], var velocity = velocities[node.id],
                      let point = positions[node.id] else { continue }
                force.dx += (center.x - point.x) * 0.022
                force.dy += (center.y - point.y) * 0.022
                velocity.dx = (velocity.dx + force.dx * 0.06) * 0.84
                velocity.dy = (velocity.dy + force.dy * 0.06) * 0.84
                let speed = sqrt(velocity.dx * velocity.dx + velocity.dy * velocity.dy)
                let limit = 34 * temperature + 2
                if speed > limit {
                    velocity.dx = velocity.dx / speed * limit
                    velocity.dy = velocity.dy / speed * limit
                }
                let marginX: CGFloat = 120
                let marginY: CGFloat = 96
                let nextX = clamp(point.x + velocity.dx, marginX, width - marginX)
                let nextY = clamp(point.y + velocity.dy, marginY, height - marginY)
                positions[node.id] = CGPoint(x: nextX, y: nextY)
                velocities[node.id] = velocity
            }
        }
        return positions
    }

    private static func pseudoRandom(_ id: String, _ seed: Int) -> CGFloat {
        var hash: UInt64 = 1469598103934665603
        for byte in id.utf8 {
            hash = (hash ^ UInt64(byte)) &* 1099511628211
        }
        hash = (hash ^ UInt64(abs(seed))) &* 1099511628211
        let value = Double(hash % 10_000) / 10_000.0
        return CGFloat(value - 0.5) * 2
    }
}
