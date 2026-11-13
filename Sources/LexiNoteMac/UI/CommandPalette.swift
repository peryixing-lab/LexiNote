import SwiftUI
import AppKit

struct CommandPalettePanel: View {
    @ObservedObject var model: AppModel
    @ObservedObject var settings: SettingsStore
    @Environment(\.lexiPalette) private var palette

    @State private var query = ""
    @State private var selected = 0
    @State private var monitor: Any?
    @FocusState private var searchFocused: Bool

    private var commands: [LexiCommand] {
        CommandCatalog.filtered(query)
    }

    private var quickResults: [QuickResult] {
        model.quickResults(query)
    }

    private var isCommands: Bool { model.paletteMode == .commands }

    private var resultCount: Int {
        isCommands ? commands.count : quickResults.count
    }

    var body: some View {
        ZStack {
            Rectangle()
                .fill(Color.black.opacity(palette.isDark ? 0.42 : 0.28))
                .ignoresSafeArea()
                .onTapGesture { close() }

            VStack(spacing: 0) {
                header
                VStack(spacing: 12) {
                    searchField
                    Text(isCommands ? "↑ ↓ 选择 · Enter 执行 · Esc 关闭"
                                    : "支持 tag:#标签 type:study notebook:分类 · Enter 打开")
                        .font(.system(size: 11.5))
                        .foregroundStyle(palette.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(spacing: 2) {
                                if isCommands {
                                    ForEach(Array(commands.enumerated()), id: \.element.id) { index, command in
                                        commandRow(command, index: index)
                                            .id(command.id)
                                    }
                                } else {
                                    ForEach(Array(quickResults.enumerated()), id: \.element.id) { index, result in
                                        quickRow(result, index: index)
                                            .id(result.id)
                                    }
                                }
                                if resultCount == 0 {
                                    emptyState
                                }
                            }
                            .padding(.bottom, 4)
                        }
                        .scrollIndicators(.automatic)
                        .onChange(of: selected) { _, value in
                            let identifier = isCommands
                                ? commands[safe: value]?.id
                                : quickResults[safe: value]?.id
                            guard let identifier else { return }
                            withAnimation(.easeOut(duration: 0.1)) {
                                proxy.scrollTo(identifier, anchor: .center)
                            }
                        }
                    }
                    .frame(maxHeight: .infinity)
                }
                .padding(.leading, 24)
                .padding(.trailing, 24)
                .padding(.top, 16)
                .padding(.bottom, 20)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .frame(width: 720, height: 560)
            .background(palette.workspacePage)
            .background {
                if settings.useMaterial {
                    LiquidGlassLayer(cornerRadius: 16, tint: palette.brand.opacity(0.06))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(palette.workspaceLine, lineWidth: 1)
            )
            .shadow(color: palette.shadow, radius: 34, x: 0, y: 20)
            .shadow(color: Color.black.opacity(palette.isDark ? 0.2 : 0.06), radius: 3, y: 1)
        }
        .onAppear {
            query = ""
            selected = 0
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
                searchFocused = true
            }
            installMonitor()
        }
        .onDisappear {
            removeMonitor()
        }
        .onChange(of: query) { _, _ in
            selected = 0
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(isCommands ? "命令面板" : "快速切换")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                Text(isCommands ? "\(resultCount) 个命令" : "\(resultCount) 个文档")
                    .font(.system(size: 11))
                    .foregroundStyle(palette.textSecondary)
            }
            Spacer()
            Button {
                close()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(palette.textSecondary)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(palette.hoverFill))
            }
            .buttonStyle(.plain)
            .help("关闭命令面板")
        }
        .padding(.leading, 24)
        .padding(.trailing, 18)
        .padding(.vertical, 14)
        .background(palette.workspaceSidebar)
        .overlay(alignment: .bottom) {
            Rectangle().fill(palette.workspaceLine).frame(height: 0.5)
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(palette.textSecondary)
            TextField(isCommands ? "搜索命令…" : "搜索笔记、导图或白板…", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 15))
                .foregroundStyle(palette.textPrimary)
                .focused($searchFocused)
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(palette.textSecondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 44)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(palette.softSurface)
        )
    }

    private func commandRow(_ command: LexiCommand, index: Int) -> some View {
        let active = selected == index
        return Button {
            execute(command)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: command.symbol)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(active ? palette.brandInk : palette.textSecondary)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 3) {
                    Text(command.title)
                        .font(.system(size: 14, weight: active ? .medium : .regular))
                        .foregroundStyle(palette.textPrimary)
                        .lineLimit(1)
                    if !command.shortcut.isEmpty {
                        Text("\(command.group) · \(command.shortcut)")
                            .font(.system(size: 10.5))
                            .foregroundStyle(palette.textSecondary)
                    } else {
                        Text(command.group)
                            .font(.system(size: 10.5))
                            .foregroundStyle(palette.textSecondary)
                    }
                }
                Spacer(minLength: 8)
            }
            .padding(.horizontal, 12)
            .frame(height: 52)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(active ? palette.brandSoft : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { inside in
            if inside { selected = index }
        }
    }

    private func quickRow(_ result: QuickResult, index: Int) -> some View {
        let active = selected == index
        return Button {
            choose(result)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: result.symbol)
                    .font(.system(size: 13))
                    .foregroundStyle(active ? palette.brandInk : palette.textSecondary)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 3) {
                    Text(result.title)
                        .font(.system(size: 14, weight: active ? .medium : .regular))
                        .foregroundStyle(palette.textPrimary)
                        .lineLimit(1)
                    Text(result.subtitle)
                        .font(.system(size: 10.5))
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                if result.kind == .create {
                    KeyboardHint(text: "↵")
                } else {
                    Image(systemName: "arrow.turn.down.left")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(palette.textSecondary.opacity(active ? 0.9 : 0.45))
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 52)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(active ? palette.brandSoft : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { inside in
            if inside { selected = index }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: isCommands ? "command" : "magnifyingglass")
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(palette.textSecondary.opacity(0.7))
            Text(isCommands ? "没有匹配的命令" : "没有匹配的文档")
                .font(.system(size: 15))
                .foregroundStyle(palette.textSecondary)
            if !isCommands && !query.trimmingCharacters(in: .whitespaces).isEmpty {
                Button {
                    model.createNote(title: query.trimmingCharacters(in: .whitespaces), type: .markdown)
                    close()
                } label: {
                    Text("新建「\(query.trimmingCharacters(in: .whitespaces))」")
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(palette.brand)
                        .padding(.horizontal, 16)
                        .frame(height: 38)
                        .background(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(palette.brandSoft)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 46)
    }

    // MARK: Actions

    private func move(_ delta: Int) {
        let count = resultCount
        guard count > 0 else { return }
        selected = (selected + delta + count) % count
    }

    private func submit() {
        if isCommands {
            guard let command = commands[safe: selected] else { return }
            execute(command)
        } else if let result = quickResults[safe: selected] {
            choose(result)
        } else if !query.trimmingCharacters(in: .whitespaces).isEmpty {
            model.createNote(title: query.trimmingCharacters(in: .whitespaces), type: .markdown)
            close()
        }
    }

    private func execute(_ command: LexiCommand) {
        close()
        guard command.id != "palette" else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            CommandRouter.perform(command, model: model)
        }
    }

    private func choose(_ result: QuickResult) {
        close()
        switch result.kind {
        case .note: model.openNote(result.id)
        case .map: model.openMap(result.id)
        case .canvas: model.openCanvas(result.id)
        case .create:
            let title = query.trimmingCharacters(in: .whitespaces)
            model.createNote(title: title.isEmpty ? "无标题笔记" : title, type: .markdown)
        }
    }

    private func close() {
        model.dismissPalette()
    }

    // MARK: Keyboard monitor

    private func installMonitor() {
        removeMonitor()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard model.paletteVisible else { return event }
            switch event.keyCode {
            case 126:
                move(-1)
                return nil
            case 125:
                move(1)
                return nil
            case 36, 76:
                submit()
                return nil
            case 53:
                close()
                return nil
            default:
                return event
            }
        }
    }

    private func removeMonitor() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
