import AppKit
import Foundation
import Darwin
import PDFKit
import SwiftUI

@MainActor
enum SelfTest {
    static func runHistorySafetyOnly(root: URL) -> Bool {
        try? FileManager.default.removeItem(at: root)
        let failures = runVersionHistoryAndSafetyTests(baseRoot: root)
        if failures.isEmpty {
            print("HISTORY_SELFTEST PASS")
            return true
        }
        for failure in failures { print("FAIL \(failure)") }
        return false
    }

    static func runDiscoveryFeaturesOnly(root: URL) -> Bool {
        try? FileManager.default.removeItem(at: root)
        let failures = runDiscoveryFeaturesSelfTests(baseRoot: root)
        if failures.isEmpty {
            print("DISCOVERY_SELFTEST PASS")
            return true
        }
        for failure in failures { print("FAIL \(failure)") }
        return false
    }

    static func run(root: URL) -> Bool {
        var failures: [String] = []
        func check(_ condition: Bool, _ message: String) {
            if !condition { failures.append(message) }
        }

        try? FileManager.default.removeItem(at: root)
        let suiteName = "com.lexinote.mac.selftest"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defaults.removePersistentDomain(forName: suiteName)

        let settings = SettingsStore(defaults: defaults)
        settings.showWelcome = false
        settings.useMaterial = false

        let model = AppModel(settings: settings, storageRoot: root, inMemory: false)
        check(model.vaults.count == 1, "全新安装应有 1 个空工作区，实际 \(model.vaults.count)")
        check(model.notes.isEmpty, "全新安装不应包含笔记，实际 \(model.notes.count)")
        check(model.maps.isEmpty, "全新安装不应包含导图，实际 \(model.maps.count)")
        check(model.canvases.isEmpty, "全新安装不应包含白板，实际 \(model.canvases.count)")

        let target = model.createNote(title: "链接目标",
                                      content: "# 链接目标\n\n动态规划的核心状态定义。",
                                      type: .markdown, notebook: "测试")
        check(model.saveNoteNow(target.id), "目标笔记应能保存")

        let note = model.createNote(title: "自动化测试笔记",
                                    content: "# 自动化测试笔记\n\n这是第一版内容，链接到 [[链接目标]]。",
                                    type: .markdown, notebook: "测试", tags: ["测试", "自动化"])
        check(model.saveNoteNow(note.id), "新建笔记应能保存")
        let vaultName = model.vaults.first?.name ?? "我的工作区"
        let fileURL = root.appendingPathComponent("\(vaultName)/测试/自动化测试笔记.md")
        check(FileManager.default.fileExists(atPath: fileURL.path), "Markdown 文件应写入磁盘：\(fileURL.path)")
        if let text = try? String(contentsOf: fileURL, encoding: .utf8) {
            check(text.contains("id: \"\(note.id)\""), "frontmatter 应包含稳定主键")
            check(text.contains("# 自动化测试笔记"), "文件应包含正文")
        } else {
            failures.append("无法读取刚写入的 Markdown 文件")
        }

        model.updateNoteContent(note.id, content: "# 自动化测试笔记\n\n第二版内容，引用 [[链接目标]]。")
        model.saveNoteNow(note.id)
        model.flushAll()

        let reloaded = AppModel(settings: settings, storageRoot: root, inMemory: false)
        guard let restored = reloaded.note(note.id) else {
            print("FAIL 重新载入后找不到测试笔记")
            return false
        }
        check(restored.content.contains("第二版内容"), "重新载入后正文应更新")
        check(restored.tags.contains("自动化"), "重新载入后标签应保留")
        check(restored.notebook == "测试", "重新载入后笔记本应保留")
        check(restored.path == "测试/自动化测试笔记.md", "相对路径应正确，实际 \(restored.path)")

        check(!reloaded.searchHits("动态规划").isEmpty, "搜索「动态规划」应有结果")
        check(!reloaded.searchHits("tag:#测试").isEmpty, "标签搜索应命中测试笔记")
        if let targetNote = reloaded.note(target.id) {
            check(!reloaded.backlinks(for: targetNote).isEmpty, "链接目标应有反向链接")
        } else {
            failures.append("缺少链接目标笔记")
        }
        if let sourceNote = reloaded.note(note.id) {
            check(!reloaded.outgoingLinks(for: sourceNote).isEmpty, "自动化测试笔记应有出链")
        } else {
            failures.append("缺少自动化测试笔记")
        }
        check(!reloaded.graphData().nodes.isEmpty, "图谱应有节点")
        check(!reloaded.graphData().edges.isEmpty, "图谱应有连线")

        reloaded.trashNote(note.id)
        reloaded.flushAll()
        let trashReload = AppModel(settings: settings, storageRoot: root, inMemory: false)
        check(trashReload.note(note.id)?.isTrashed == true, "回收站状态应持久化")
        trashReload.restoreNote(note.id)
        trashReload.flushAll()
        let restoreReload = AppModel(settings: settings, storageRoot: root, inMemory: false)
        check(restoreReload.note(note.id)?.isTrashed == false, "恢复后状态应持久化")

        restoreReload.createMap(title: "自动化测试导图")
        restoreReload.flushAll()
        let mapReload = AppModel(settings: settings, storageRoot: root, inMemory: false)
        check(mapReload.maps.contains(where: { $0.title == "自动化测试导图" }), "导图应持久化")

        // Workspace open-mode prompt, per-workspace settings, and multi-window isolation tests
        let primaryVaultID = mapReload.activeVaultID
        let vault2 = mapReload.createVault(name: "独立测试工作区", openInCurrent: false)
        check(mapReload.vaults.count == 2, "新建工作区后应有 2 个工作区")

        settings.appearance = .dark
        settings.editorFontSize = 20
        settings.defaultPresentation = .reading
        settings.showSidebar = false
        settings.newNoteNotebook = "工作笔记"

        check(settings.workspaceOpenMode == .ask, "初始工作区打开方式应为每次询问")
        mapReload.requestOpenWorkspace(vault2)
        check(mapReload.workspacePromptVault?.id == vault2.id, "点击工作区在每次询问模式下应弹出询问框")

        var newWindowVaults: [String] = []
        mapReload.onOpenNewWindow = { newWindowVaults.append($0) }
        mapReload.confirmOpenWorkspace(vault2, mode: .new, remember: true)
        check(mapReload.workspacePromptVault == nil, "确认打开后应关闭询问框")
        check(newWindowVaults == [vault2.id], "选择新窗口打开应触发打开新窗口")
        check(settings.workspaceOpenMode == .new, "勾选下次不再提示应保存全局打开方式为 .new")

        mapReload.openWorkspaceInCurrentWindow(vault2.id)
        check(mapReload.activeVaultID == vault2.id, "当前窗口切换工作区后 activeVaultID 应更新")
        check(settings.workspaceOpenMode == .new, "「下次不再提示」不应随工作区切换重置")
        check(settings.appearance == .system, "不同工作区应拥有独立外观默认设置")
        check(settings.editorFontSize == 16, "不同工作区应拥有独立字号默认设置")
        check(settings.defaultPresentation == .live, "不同工作区应拥有独立默认视图设置")
        check(settings.showSidebar == true, "不同工作区应拥有独立侧栏显示设置")
        check(settings.newNoteNotebook == "笔记", "不同工作区应拥有独立默认笔记本")

        settings.appearance = .light
        settings.editorFontSize = 14
        settings.defaultPresentation = .source
        settings.newNoteNotebook = "实验笔记"

        // Re-select open mode in Editor settings back to .ask (globally)
        settings.workspaceOpenMode = .ask
        mapReload.openWorkspaceInCurrentWindow(primaryVaultID)
        check(settings.workspaceOpenMode == .ask, "设置编辑器重选的打开方式应对所有工作区全局生效")
        check(settings.appearance == .dark, "切回主工作区后应恢复主工作区的外观设置")
        check(settings.editorFontSize == 20, "切回主工作区后应恢复主工作区的字号设置")
        check(settings.defaultPresentation == .reading, "切回主工作区后应恢复主工作区的默认视图")
        check(settings.showSidebar == false, "切回主工作区后应恢复主工作区的侧栏状态")
        check(settings.newNoteNotebook == "工作笔记", "切回主工作区后应恢复主工作区的默认笔记本")

        mapReload.requestOpenWorkspace(vault2)
        check(mapReload.workspacePromptVault?.id == vault2.id, "重设为每次询问后点击工作区应再次弹出询问框")
        mapReload.confirmOpenWorkspace(vault2, mode: .current, remember: false)
        check(settings.workspaceOpenMode == .ask, "未勾选下次不再提示时应保持 .ask")
        check(mapReload.activeVaultID == vault2.id, "未记住选择时仍应在当前窗口打开所选工作区")

        // Multi-window shared library with independent per-window SettingsStore
        let win1Settings = SettingsStore(defaults: defaults, vaultID: primaryVaultID)
        let win1Model = AppModel(settings: win1Settings, sharedLibrary: mapReload.library,
                                 initialVaultID: primaryVaultID, isPrimaryWindow: true)
        let win2Settings = SettingsStore(defaults: defaults, vaultID: vault2.id)
        let win2Model = AppModel(settings: win2Settings, sharedLibrary: mapReload.library,
                                 initialVaultID: vault2.id, isPrimaryWindow: false)
        check(win1Model.activeVaultID == primaryVaultID && win2Model.activeVaultID == vault2.id,
              "多窗口实例应保持各自独立的工作区绑定")
        check(win1Settings.appearance == .dark && win2Settings.appearance == .light,
              "多窗口应各自加载所绑定工作区的外观设置")
        check(win1Settings.editorFontSize == 20 && win2Settings.editorFontSize == 14,
              "多窗口应各自加载所绑定工作区的编辑器设置")

        let win2Note = win2Model.createNote(title: "工作区 B 笔记", content: "# 工作区 B")
        check(win1Model.notes.contains(where: { $0.id == win2Note.id }), "多窗口应共享知识库数据")
        check(!win1Model.visibleNotes.contains(where: { $0.id == win2Note.id }), "窗口 1 侧栏仅展示其当前工作区笔记")
        check(win2Model.visibleNotes.contains(where: { $0.id == win2Note.id }), "窗口 2 侧栏展示工作区 B 笔记")

        win1Settings.workspaceOpenMode = .new
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        check(win2Settings.workspaceOpenMode == .new, "全局打开方式变更应同步至其他打开中的窗口")

        // Legacy flat-key migration check
        let migSuiteName = "com.lexinote.mac.selftest.migration"
        let migDefaults = UserDefaults(suiteName: migSuiteName) ?? .standard
        migDefaults.removePersistentDomain(forName: migSuiteName)
        migDefaults.set("dark", forKey: "lexi.mac.appearance")
        migDefaults.set(19.0, forKey: "lexi.mac.editorFontSize")
        let migratedPrimary = SettingsStore(defaults: migDefaults, vaultID: "default-vault")
        let freshSecondary = SettingsStore(defaults: migDefaults, vaultID: vault2.id)
        check(migratedPrimary.appearance == .dark, "旧版全局偏好应迁移到初始工作区")
        check(migratedPrimary.editorFontSize == 19.0, "旧版编辑器字号应迁移到初始工作区")
        check(freshSecondary.appearance == .system, "新增工作区不应继承旧版全局外观设置")
        migDefaults.removePersistentDomain(forName: migSuiteName)

        // MindMap .org layout, collapse, reorder & createNoteFromMindNode
        mapReload.openWorkspaceInCurrentWindow(primaryVaultID)
        mapReload.createMap(title: "导图高级测试")
        if let createdMap = mapReload.maps.first(where: { $0.title == "导图高级测试" }),
           let n1 = mapReload.addMindNode(mapID: createdMap.id, parentID: createdMap.rootNodeID, text: "分支一"),
           let n2 = mapReload.addMindNode(mapID: createdMap.id, parentID: createdMap.rootNodeID, text: "分支二"),
           let g1 = mapReload.addMindNode(mapID: createdMap.id, parentID: n1, text: "孙节点") {
            if var updatedMap = mapReload.map(createdMap.id) {
                updatedMap.layout = .org
                mapReload.updateMap(updatedMap)
                let orgLayout = MindMapLayoutEngine.compute(map: updatedMap)
                let rootPos = orgLayout.positions[updatedMap.rootNodeID] ?? .zero
                let n1Pos = orgLayout.positions[n1] ?? .zero
                let n2Pos = orgLayout.positions[n2] ?? .zero
                let g1Pos = orgLayout.positions[g1] ?? .zero
                check(n1Pos.y > rootPos.y && g1Pos.y > n1Pos.y, "组织架构布局应自上而下排布节点")
                check(abs(n1Pos.x - n2Pos.x) > 10, "同级分支节点在组织架构布局下应横向分离")
            }
            mapReload.toggleMindNodeCollapsed(mapID: createdMap.id, nodeID: n1)
            if let collapsedMap = mapReload.map(createdMap.id) {
                let collapsedLayout = MindMapLayoutEngine.compute(map: collapsedMap)
                check(collapsedLayout.visibleNodes.contains(where: { $0.id == n1 }), "折叠后父节点本身应保持可见")
                check(!collapsedLayout.visibleNodes.contains(where: { $0.id == g1 }), "折叠后子节点应从可见列表隐藏")
            }
            mapReload.toggleMindNodeCollapsed(mapID: createdMap.id, nodeID: n1)
            mapReload.moveMindNodeOrder(mapID: createdMap.id, nodeID: n2, delta: -1)
            if let reordered = mapReload.map(createdMap.id) {
                check(reordered.children(of: reordered.rootNodeID).first?.id == n2, "上移同级节点应调整顺序")
            }
            let linked = mapReload.createNoteFromMindNode(mapID: createdMap.id, nodeID: n1)
            check(linked != nil && mapReload.map(createdMap.id)?.nodes.first(where: { $0.id == n1 })?.noteRefID == linked?.id,
                  "从导图节点新建并关联笔记应双向写入 noteRefID")
        } else {
            failures.append("无法创建导图测试节点")
        }

        // New SettingsStore fields & custom hotkey dispatch
        settings.showRibbon = false
        settings.hiddenRibbonCommands = ["reading"]
        settings.interfaceZoom = 120
        settings.editorShowTitle = false
        settings.editorDefaultTier = .pro
        settings.cssSnippets = [CssSnippet(id: "snippet-1", name: "测试样式", css: "p { line-height: 1.8; }", enabled: true)]
        settings.hotkeyOverrides["graph"] = ["Meta+Shift+Y"]
        let reloadedSettings = SettingsStore(defaults: defaults, vaultID: primaryVaultID)
        check(reloadedSettings.showRibbon == false, "showRibbon 应按工作区持久化")
        check(reloadedSettings.hiddenRibbonCommands == ["reading"], "hiddenRibbonCommands 应按工作区持久化")
        check(reloadedSettings.interfaceZoom == 120, "interfaceZoom 应按工作区持久化")
        check(reloadedSettings.editorShowTitle == false, "editorShowTitle 应按工作区持久化")
        check(reloadedSettings.editorDefaultTier == .pro, "editorDefaultTier 应按工作区持久化")
        check(reloadedSettings.cssSnippets.count == 1 && reloadedSettings.cssSnippets.first?.enabled == true,
              "cssSnippets 应按工作区持久化")
        check(reloadedSettings.hotkeyOverrides["graph"] == ["Meta+Shift+Y"], "自定义快捷键覆盖应全局持久化")
        settings.showRibbon = true
        check(CommandRouter.performCustomHotkey(canonical: "Meta+Shift+Y", model: mapReload, settings: reloadedSettings),
              "自定义快捷键路由应命中 graph 命令")
        check(mapReload.selectedTabID == "graph:all", "触发自定义快捷键后应打开关系图谱")

        // Version history, diff, restore auto-backup, retention pruning, disk-full, crash WAL & multi-window conflict tests
        let historyFailures = runVersionHistoryAndSafetyTests(baseRoot: root)
        failures.append(contentsOf: historyFailures)

        // Plugin subsystem E2E tests (LexiNote native Harness ZIP + Obsidian compatibility plugin ZIP)
        let pluginFailures = runPluginSelfTests(root: root)
        failures.append(contentsOf: pluginFailures)

        let pluginSecurityFailures = runPluginSecuritySelfTests(root: root)
        failures.append(contentsOf: pluginSecurityFailures)

        let featureFailures = runMathPdfOpenSaveSelfTests(root: root)
        failures.append(contentsOf: featureFailures)

        let discoveryFailures = runDiscoveryFeaturesSelfTests(baseRoot: root)
        failures.append(contentsOf: discoveryFailures)
        failures.append(contentsOf: runEditorScrollingTests())

        defaults.removePersistentDomain(forName: suiteName)

        print("SELFTEST notes=\(mapReload.notes.count) maps=\(mapReload.maps.count) vaults=\(mapReload.vaults.count)")
        if failures.isEmpty {
            print("SELFTEST PASS")
        } else {
            for failure in failures { print("FAIL \(failure)") }
        }
        return failures.isEmpty
    }

    private static func runEditorScrollingTests() -> [String] {
        var failures: [String] = []
        func check(_ condition: Bool, _ message: String) {
            if !condition { failures.append("编辑器滚动：\(message)") }
        }
        let controller = EditorController()
        let body = (0..<160).map { index in
            "第 \(index) 行 " + String(repeating: "用于验证长笔记换行与光标定位。", count: 5)
        }.joined(separator: "\n") + "\n末尾定位标记"
        let editor = MarkdownTextEditor(text: .constant(body), palette: ThemeEngine.original(dark: false),
                                        fontSize: 16, lineHeight: 1.75, design: .system, spellCheck: false,
                                        controller: controller, onTextChange: { _ in },
                                        documentHeader: AnyView(Text("滚动标题").frame(height: 104)),
                                        contentMaxWidth: 760)
        let hosting = NSHostingView(rootView: editor)
        let window = NSWindow(contentRect: NSRect(x: 80, y: 80, width: 640, height: 360),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        window.orderFrontRegardless()
        defer { window.orderOut(nil); window.contentView = nil }
        hosting.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.12))
        guard let textView = controller.textView,
              let scrollView = textView.enclosingScrollView as? MarkdownEditorScrollView else {
            return ["编辑器滚动：原生文本框应与标题共享同一个滚动容器"]
        }
        scrollView.layoutDocument()
        check(textView.frame.minY >= 104, "标题应位于正文前方的文档区域内")
        scrollView.contentView.scroll(to: NSPoint(x: 0, y: 240))
        scrollView.reflectScrolledClipView(scrollView.contentView)
        check(scrollView.documentVisibleRect.minY > textView.frame.minY, "下滚后标题应离开可视区域")

        func selectionIsVisible() -> Bool {
            guard let manager = textView.layoutManager else { return false }
            let glyph = manager.glyphIndexForCharacter(at: textView.selectedRange().location)
            var line = manager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
            line.origin.y += textView.textContainerOrigin.y
            let documentLine = textView.convert(line, to: scrollView.editorDocument)
            let visible = scrollView.documentVisibleRect
            return documentLine.minY >= visible.minY - 1 && documentLine.maxY <= visible.maxY + 1
        }
        controller.selectLine(140)
        check(selectionIsVisible(), "目录跳转应将正文中的目标行滚动到可视区域")
        check(controller.findNext("末尾定位标记", fromSelection: false), "正文查找应能找到末尾内容")
        check(selectionIsVisible(), "查找末尾内容后光标应保持可见")
        let oldHeight = scrollView.editorDocument.frame.height
        window.setContentSize(NSSize(width: 480, height: 280))
        hosting.layoutSubtreeIfNeeded()
        scrollView.layoutDocument()
        check(scrollView.editorDocument.frame.height > oldHeight, "缩窄窗口后应重新换行并更新文档高度")
        controller.selectLine(140)
        check(selectionIsVisible(), "窗口缩放后目录定位仍应正确")

        // Cursor stability checks during mid-document edits, IME composition, header title editing, and commands
        let cursorSuiteName = "com.lexinote.mac.selftest.cursor"
        let cursorDefaults = UserDefaults(suiteName: cursorSuiteName) ?? .standard
        cursorDefaults.removePersistentDomain(forName: cursorSuiteName)
        defer { cursorDefaults.removePersistentDomain(forName: cursorSuiteName) }
        let editSettings = SettingsStore(defaults: cursorDefaults)
        editSettings.showWelcome = false
        editSettings.useMaterial = false
        editSettings.defaultPresentation = .source
        editSettings.editorDefaultMode = "source"
        let editModel = AppModel(settings: editSettings, inMemory: true, seedDemo: false)
        let editNote = editModel.createNote(
            title: "测试标题光标",
            content: "第一段内容，在这里输入文字，后面的内容\n第二行正文",
            notebook: "测试"
        )
        let workspaceView = NoteWorkspaceView(model: editModel, settings: editSettings, note: editNote)
            .environment(\.lexiPalette, ThemeEngine.original(dark: false))
        let editHosting = NSHostingView(rootView: workspaceView)
        let editWindow = NSWindow(contentRect: NSRect(x: 120, y: 120, width: 760, height: 520),
                                  styleMask: [.titled], backing: .buffered, defer: false)
        editWindow.isReleasedWhenClosed = false
        editWindow.contentView = editHosting
        editWindow.orderFrontRegardless()
        editWindow.makeKey()
        defer { editWindow.orderOut(nil); editWindow.contentView = nil }
        editHosting.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.12))

        func findEditableTextField(in view: NSView) -> NSTextField? {
            if let field = view as? NSTextField, field.isEditable { return field }
            for sub in view.subviews {
                if let found = findEditableTextField(in: sub) { return found }
            }
            return nil
        }

        if let activeController = EditorController.active,
           let activeTV = activeController.textView,
           let docView = activeTV.superview as? MarkdownEditorDocumentView {
            // 1. Mid-document typing + SwiftUI re-render keeps cursor in place
            editWindow.makeFirstResponder(activeTV)
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
            activeTV.setSelectedRange(NSRange(location: 11, length: 0))
            activeTV.insertText("X", replacementRange: activeTV.selectedRange())
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
            editModel.saveState = .saving
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
            editModel.saveState = .saved(Date())
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
            check(activeTV.selectedRange() == NSRange(location: 12, length: 0),
                  "正文中段输入并触发重绘后光标应保持在 12，实际 \(activeTV.selectedRange())")

            // 2. IME marked text survives autosave/SwiftUI updateNSView without jumping cursor
            activeTV.setMarkedText("ceshi",
                                   selectedRange: NSRange(location: 5, length: 0),
                                   replacementRange: activeTV.selectedRange())
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
            editModel.saveState = .saving
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
            editModel.saveState = .saved(Date())
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
            check(activeTV.hasMarkedText(), "输入法组字期间触发 SwiftUI 更新不应清空 markedText")
            let marked = activeTV.markedRange()
            let markedSlice = marked.location != NSNotFound
                ? (activeTV.string as NSString).substring(with: marked)
                : ""
            check(markedSlice == "ceshi", "输入法候选拼音文本应完整保留，实际「\(markedSlice)」")
            check(activeTV.selectedRange() == NSRange(location: 17, length: 0),
                  "输入法组字期间光标不应向后跳变，实际 \(activeTV.selectedRange())")
            activeTV.insertText("测试", replacementRange: activeTV.markedRange())
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
            check(!activeTV.hasMarkedText() && activeTV.selectedRange() == NSRange(location: 14, length: 0),
                  "输入法上屏提交后光标应停留在提交词末尾 14，实际 \(activeTV.selectedRange())")

            // 3. Heading command keeps caret on transformed line before trailing newline
            let line2Start = (activeTV.string as NSString).range(of: "第二行正文").location
            if line2Start != NSNotFound {
                activeTV.setSelectedRange(NSRange(location: line2Start, length: 0))
                activeController.apply(.h1)
                RunLoop.current.run(until: Date().addingTimeInterval(0.05))
                let expectedEnd = line2Start + ("# 第二行正文" as NSString).length
                check(activeTV.selectedRange() == NSRange(location: expectedEnd, length: 0),
                      "设置标题格式后光标应留在当前行末尾，实际 \(activeTV.selectedRange())，期望 \(expectedEnd)")
            }

            // 4. Header title TextField keeps cursor in place across typing + model update
            if let titleField = findEditableTextField(in: docView) {
                editWindow.makeFirstResponder(titleField)
                RunLoop.current.run(until: Date().addingTimeInterval(0.05))
                if let fieldEditor = titleField.currentEditor() as? NSTextView {
                    fieldEditor.setSelectedRange(NSRange(location: 2, length: 0))
                    fieldEditor.insertText("中", replacementRange: fieldEditor.selectedRange())
                    RunLoop.current.run(until: Date().addingTimeInterval(0.08))
                    let postSelection = (titleField.currentEditor() as? NSTextView)?.selectedRange()
                    check(titleField.stringValue == "测试中标题光标",
                          "标题编辑后内容应为「测试中标题光标」，实际「\(titleField.stringValue)」")
                    check(postSelection == NSRange(location: 3, length: 0),
                          "标题中间输入文字后光标应保持在 3 而不是跳到末尾，实际 \(String(describing: postSelection))")
                } else {
                    failures.append("编辑器滚动：未能获取标题输入框的 fieldEditor")
                }
            } else {
                failures.append("编辑器滚动：未找到文档头部标题输入框")
            }

            // 5. External content update (e.g. version restore / link insert) still updates textView when not composing
            editWindow.makeFirstResponder(activeTV)
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
            activeTV.setSelectedRange(NSRange(location: 4, length: 0))
            let updatedExternal = "外部同步内容：保留光标在合法范围内"
            editModel.updateNoteContent(editNote.id, content: updatedExternal)
            RunLoop.current.run(until: Date().addingTimeInterval(0.08))
            check(activeTV.string == updatedExternal,
                  "外部更新正文时应同步到编辑器，实际「\(activeTV.string)」")
            check(activeTV.selectedRange() == NSRange(location: 4, length: 0),
                  "外部更新正文后光标应保持在 4，实际 \(activeTV.selectedRange())")
        } else {
            failures.append("编辑器滚动：未能挂载 NoteWorkspaceView 源码编辑器以测试光标稳定性")
        }

        if failures.isEmpty { print("EDITOR_SCROLL_SELFTEST PASS") }
        return failures
    }

    private static func runPluginSelfTests(root: URL) -> [String] {
        final class Recorder {
            var failures: [String] = []
            var finished = false
            func check(_ condition: Bool, _ message: String) {
                if !condition { failures.append(message) }
            }
        }
        let rec = Recorder()
        let suiteName = "com.lexinote.mac.selftest.plugins"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defaults.removePersistentDomain(forName: suiteName)

        let pluginRoot = root.appendingPathComponent("plugin-sandbox", isDirectory: true)
        let pluginSettings = SettingsStore(defaults: defaults)
        pluginSettings.showWelcome = false
        pluginSettings.useMaterial = false
        let manager = PluginManager(ephemeral: false, storageRoot: pluginRoot)
        defer { manager.clearTestSecrets() }
        let model = AppModel(settings: pluginSettings, storageRoot: pluginRoot, inMemory: false, plugins: manager)
        let vault1ID = model.activeVaultID
        let vault2 = model.createVault(name: "插件隔离工作区", openInCurrent: false)
        _ = model.createNote(title: "插件沙盒笔记", content: "# 插件沙盒笔记\n\n测试内容", notebook: "笔记")

        func pumpUntil(timeout: TimeInterval = 6.0, _ predicate: () -> Bool) -> Bool {
            let deadline = Date().addingTimeInterval(timeout)
            while !predicate() && Date() < deadline {
                RunLoop.main.run(until: Date().addingTimeInterval(0.02))
            }
            return predicate()
        }

        func asyncWait(_ timeout: TimeInterval = 4.0, _ predicate: () -> Bool) async -> Bool {
            let deadline = Date().addingTimeInterval(timeout)
            while !predicate() && Date() < deadline {
                try? await Task.sleep(nanoseconds: 25_000_000)
            }
            return predicate()
        }

        Task { @MainActor in
            defer { rec.finished = true }

            // 1. LexiNote native plugin test using the repository's Harness build.
            let harnessPath = ProcessInfo.processInfo.environment["LEXINOTE_HARNESS_ZIP"]
                ?? "tests/fixtures/harness-lexinote-harness.zip"
            let harnessZip = URL(fileURLWithPath: harnessPath).standardizedFileURL
            if FileManager.default.fileExists(atPath: harnessZip.path) {
                do {
                    let harnessRecord = try await manager.installFromZip(url: harnessZip)
                    rec.check(harnessRecord.id == "lexinote.harness", "Harness 插件 ID 应为 lexinote.harness")
                    rec.check(harnessRecord.manifest.kind == .lexinote, "Harness 应识别为知萤原生插件")
                    rec.check(harnessRecord.state == .installed, "刚安装的插件应处于 installed 待启用状态")
                    rec.check(manager.missingCapabilities(for: "lexinote.harness").count == harnessRecord.manifest.capabilities.count,
                              "默认拒绝原则：新装插件未授权权限数量应等于声明权限总数")

                    do {
                        try manager.requireCapability(pluginId: "lexinote.harness", capability: PluginCapability.vaultRead.rawValue)
                        rec.failures.append("未授权时 requireCapability 应拒绝访问 vault.read")
                    } catch let err as PluginHostError {
                        rec.check(err.code == PluginErrorCode.permissionDenied, "未授权异常码应为 E_PERMISSION_DENIED")
                    } catch {
                        rec.failures.append("未授权应抛出 PluginHostError，实际 \(error)")
                    }

                    manager.grantAllCapabilities(for: "lexinote.harness")
                    rec.check(manager.missingCapabilities(for: "lexinote.harness").isEmpty, "全部授权后应无缺失权限")

                    try await manager.enable(pluginId: "lexinote.harness")
                    rec.check(manager.record(for: "lexinote.harness")?.state == .running,
                              "授权后启用 Harness 应进入 running 状态，实际 \(manager.record(for: "lexinote.harness")?.state.rawValue ?? "nil") (\(manager.record(for: "lexinote.harness")?.lastError ?? ""))")

                    let registered = await asyncWait(5.0) {
                        PluginViewRegistry.shared.views.contains(where: { $0.pluginId == "lexinote.harness" && $0.viewId == "harness" }) &&
                        PluginCommandRegistry.shared.commands.contains(where: { $0.pluginId == "lexinote.harness" })
                    }
                    rec.check(registered, "Harness 应在 WKWebView 启动后向宿主注册 harness 视图与命令")

                    await manager.presentView(pluginId: "lexinote.harness", viewId: "harness")
                    rec.check(manager.record(for: "lexinote.harness")?.state == .running, "渲染 Harness 视图后应保持运行态")

                    // Verify editor snapshot carries both noteId and live selection range
                    if let firstNoteId = model.currentNote?.id ?? model.notes.first?.id {
                        model.openNote(firstNoteId)
                        let snapDict = LexiEditorBridge.shared.snapshotDictionary(model: model)
                        rec.check((snapDict?["noteId"] as? String) == firstNoteId, "snapshotDictionary 应包含 noteId 字段")
                        let selDict = snapDict?["selection"] as? [String: Any]
                        rec.check(selDict?["from"] is Int && selDict?["to"] is Int, "snapshotDictionary 应包含 selection {from,to}")
                    } else {
                        rec.failures.append("插件沙盒工作区应存在至少一篇可选笔记以验证 snapshotDictionary")
                    }

                    // Verify event capability mapping & permission gate on manager
                    rec.check(PluginCapability.requiredCapability(forEvent: "editor.changed") == PluginCapability.editorRead.rawValue,
                              "editor.changed 应映射为 editor.read 能力")
                    rec.check(PluginCapability.requiredCapability(forEvent: "workspace.active-file-changed") == PluginCapability.workspaceViews.rawValue,
                              "workspace.active-file-changed 应映射为 workspace.views 能力")
                    rec.check(PluginCapability.requiredCapability(forEvent: "vault.modified") == PluginCapability.vaultRead.rawValue,
                              "vault.modified 应映射为 vault.read 能力")
                    rec.check(manager.hasGrantedCapability(pluginId: "lexinote.harness", capability: PluginCapability.editorRead.rawValue),
                              "全部授权后 hasGrantedCapability(editor.read) 应为 true")
                    manager.setCapability(PluginCapability.editorRead.rawValue, granted: false, for: "lexinote.harness")
                    rec.check(!manager.hasGrantedCapability(pluginId: "lexinote.harness", capability: PluginCapability.editorRead.rawValue),
                              "撤销 editor.read 后 hasGrantedCapability 应立即返回 false")
                    do {
                        try manager.requireCapability(pluginId: "lexinote.harness", capability: PluginCapability.requiredCapability(forEvent: "editor.changed"))
                        rec.failures.append("撤销 editor.read 后 requireCapability 应拒绝 editor.changed 订阅")
                    } catch let err as PluginHostError {
                        rec.check(err.code == PluginErrorCode.permissionDenied, "事件权限拒绝应抛出 E_PERMISSION_DENIED")
                    } catch {
                        rec.failures.append("事件权限拒绝应抛出 PluginHostError，实际 \(error)")
                    }
                    manager.setCapability(PluginCapability.editorRead.rawValue, granted: true, for: "lexinote.harness")
                    _ = await asyncWait(4.0) { manager.record(for: "lexinote.harness")?.state == .running }

                    let secret = "sk-lexi-host-only-secret-999"
                    let aiProfile = PluginAiProfile(
                        profileId: "ds-test",
                        name: "DeepSeek 测试",
                        provider: "openai-compatible",
                        baseUrl: "https://api.deepseek.com",
                        model: "deepseek-chat",
                        maxTokens: 4096,
                        temperature: 0.3
                    )
                    try manager.saveAiProfile(pluginId: "lexinote.harness", profile: aiProfile, apiKey: secret)
                    rec.check(manager.aiHasSecret(pluginId: "lexinote.harness", profileId: "ds-test"),
                              "宿主应保存插件 AI 密钥")
                    let statusDict = manager.aiStatus(for: "lexinote.harness")
                    rec.check((statusDict["configured"] as? Bool) == true, "保存服务商与密钥后 aiStatus.configured 应为 true")
                    if let statusData = try? JSONSerialization.data(withJSONObject: statusDict),
                       let statusText = String(data: statusData, encoding: .utf8) {
                        rec.check(!statusText.contains(secret), "aiStatus 返回载荷绝不能向插件暴露 API Key 明文")
                    }

                    // Switch to vault2 and verify per-workspace plugin enablement & permission isolation
                    model.openWorkspaceInCurrentWindow(vault2.id)
                    _ = await asyncWait(2.0) { manager.session(for: "lexinote.harness") == nil }
                    rec.check(!manager.isEnabled("lexinote.harness"), "工作区 A 启用的插件不应自动在工作区 B 启用")
                    rec.check(manager.missingCapabilities(for: "lexinote.harness").count == harnessRecord.manifest.capabilities.count,
                              "工作区 B 应独立维持默认拒绝权限状态")

                    model.openWorkspaceInCurrentWindow(vault1ID)
                    _ = await asyncWait(4.0) { manager.record(for: "lexinote.harness")?.state == .running }

                    // Partial capability revocation must keep Harness running when core capabilities remain
                    let beforePartialSession = manager.session(for: "lexinote.harness")
                    manager.setCapability(PluginCapability.vaultRead.rawValue, granted: false, for: "lexinote.harness")
                    manager.setCapability(PluginCapability.uiCommands.rawValue, granted: false, for: "lexinote.harness")
                    _ = await asyncWait(4.0) {
                        manager.session(for: "lexinote.harness") !== beforePartialSession &&
                            manager.record(for: "lexinote.harness")?.state == .running
                    }
                    rec.check(manager.record(for: "lexinote.harness")?.state == .running && !manager.missingCapabilities(for: "lexinote.harness").isEmpty,
                              "部分非核心能力未授权时 Harness 应保持运行态且不报异常")

                    // Revoking all puts enabled plugin into E_PERMISSION_DENIED, then grantAll restores running and clears lastError
                    manager.revokeAllCapabilities(for: "lexinote.harness")
                    _ = await asyncWait(3.0) {
                        let r = manager.record(for: "lexinote.harness")
                        return r?.state == .crashed && (r?.lastError.contains(PluginErrorCode.permissionDenied) == true)
                    }
                    manager.grantAllCapabilities(for: "lexinote.harness")
                    _ = await asyncWait(4.0) {
                        let r = manager.record(for: "lexinote.harness")
                        return r?.state == .running && (r?.lastError.isEmpty == true)
                    }
                    rec.check(manager.record(for: "lexinote.harness")?.state == .running &&
                              (manager.record(for: "lexinote.harness")?.lastError.isEmpty == true),
                              "全部授权后应自动重新激活并清除权限错误")

                    await manager.uninstall(pluginId: "lexinote.harness")
                    rec.check(manager.record(for: "lexinote.harness") == nil, "卸载后应清除插件记录")
                } catch {
                    rec.failures.append("Harness 插件自测异常：\(error.localizedDescription)")
                }
            } else {
                rec.failures.append("未找到 Harness 插件测试包，请下载或构建 ZIP 并设置 LEXINOTE_HARNESS_ZIP：\(harnessZip.path)")
            }

            // 2. Obsidian compatibility plugin ZIP E2E test
            let obsSrc = pluginRoot.appendingPathComponent("obs-selftest-src", isDirectory: true)
            let obsZip = pluginRoot.appendingPathComponent("obsidian-selftest.zip")
            try? FileManager.default.removeItem(at: obsSrc)
            try? FileManager.default.removeItem(at: obsZip)
            try? FileManager.default.createDirectory(at: obsSrc, withIntermediateDirectories: true)

            let obsManifest = """
            {
              "id": "obsidian-selftest-plugin",
              "name": "Obsidian 兼容测试插件",
              "version": "1.0.0",
              "minAppVersion": "1.4.0",
              "description": "Verify Obsidian Plugin API shim",
              "author": "LexiNote SelfTest",
              "main": "main.js",
              "styles": "styles.css"
            }
            """
            let obsStyles = ".obs-selftest-box { color: #6E44D9; font-weight: 600; }\n"
            let obsMain = """
            const { Plugin, Notice } = require('obsidian');
            module.exports = class SelfTestObsidianPlugin extends Plugin {
              async onload() {
                this.addCommand({
                  id: 'create-and-save',
                  name: 'Obsidian 创建笔记并写入私有存储',
                  callback: async () => {
                    await this.app.vault.create('测试/Obsidian创建.md', '# Obsidian 测试笔记\\n\\n由兼容层创建');
                    await this.saveData({ count: 42, ok: true });
                    new Notice('Obsidian 命令已执行');
                  }
                });
                this.registerView('selftest-view', (leaf) => ({
                  getViewType: () => 'selftest-view',
                  getDisplayText: () => 'Obsidian 自测视图',
                  async onOpen() {
                    leaf.containerEl.innerHTML = '<div class="obs-selftest-box">Obsidian View Ready</div>';
                  }
                }));
              }
            };
            """

            do {
                try obsManifest.write(to: obsSrc.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
                try obsStyles.write(to: obsSrc.appendingPathComponent("styles.css"), atomically: true, encoding: .utf8)
                try obsMain.write(to: obsSrc.appendingPathComponent("main.js"), atomically: true, encoding: .utf8)

                let zipProc = Process()
                zipProc.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
                zipProc.arguments = ["-q", "-j", obsZip.path,
                                     obsSrc.appendingPathComponent("manifest.json").path,
                                     obsSrc.appendingPathComponent("styles.css").path,
                                     obsSrc.appendingPathComponent("main.js").path]
                try zipProc.run()
                zipProc.waitUntilExit()
                rec.check(zipProc.terminationStatus == 0 && FileManager.default.fileExists(atPath: obsZip.path),
                          "应成功构建合成 Obsidian 插件 ZIP 测试包")

                let obsRecord = try await manager.installFromZip(url: obsZip)
                rec.check(obsRecord.manifest.kind == .obsidian, "无 lexinote 声明的插件包应识别为 Obsidian 兼容插件")
                rec.check(!manager.missingCapabilities(for: "obsidian-selftest-plugin").isEmpty,
                          "Obsidian 插件同样应遵守默认拒绝权限原则")

                // Grant only ui.commands & ui.views, leaving vault.write denied
                manager.setCapability(PluginCapability.uiCommands.rawValue, granted: true, for: "obsidian-selftest-plugin")
                manager.setCapability(PluginCapability.uiViews.rawValue, granted: true, for: "obsidian-selftest-plugin")
                try await manager.enable(pluginId: "obsidian-selftest-plugin")

                let cmdReady = await asyncWait(4.0) {
                    PluginCommandRegistry.shared.commands.contains(where: { $0.qualifiedId == "obsidian-selftest-plugin:create-and-save" })
                }
                rec.check(cmdReady, "授予 ui.commands 后 Obsidian 插件应成功注册命令")

                await manager.runCommand(qualifiedId: "obsidian-selftest-plugin:create-and-save")
                try? await Task.sleep(nanoseconds: 200_000_000)
                rec.check(!model.notes.contains(where: { $0.title == "Obsidian创建" }),
                          "未授予 vault.write 权限时 Obsidian vault.create 应被宿主拦截")

                // Now grant all capabilities, reboot, run command, verify created note & isolated storage
                manager.grantAllCapabilities(for: "obsidian-selftest-plugin")
                await manager.bootPlugin(pluginId: "obsidian-selftest-plugin")
                let obsReadyAgain = await asyncWait(4.0) {
                    manager.record(for: "obsidian-selftest-plugin")?.state == .running &&
                    PluginCommandRegistry.shared.commands.contains(where: { $0.qualifiedId == "obsidian-selftest-plugin:create-and-save" }) &&
                    PluginViewRegistry.shared.views.contains(where: { $0.pluginId == "obsidian-selftest-plugin" })
                }
                rec.check(obsReadyAgain, "全量授权重启后 Obsidian 插件应就绪且已注册侧栏回退视图")

                await manager.runCommand(qualifiedId: "obsidian-selftest-plugin:create-and-save")
                let createdInVault = await asyncWait(4.0) {
                    model.notes.contains(where: { $0.vaultID == vault1ID && $0.title == "Obsidian创建" && !$0.isTrashed }) &&
                    (manager.storage.loadPluginDataMap(workspaceID: vault1ID, pluginId: "obsidian-selftest-plugin")["plugin-data"]?.contains("42") ?? false)
                }
                rec.check(createdInVault, "授权后 Obsidian addCommand 应通过 app.vault.create 写入当前工作区并经 saveData 持久化到隔离存储")

                await manager.presentView(pluginId: "obsidian-selftest-plugin", viewId: "obsidian-main")
                rec.check(manager.record(for: "obsidian-selftest-plugin")?.state == .running, "渲染 Obsidian 侧栏视图应保持运行态")

                // Verify storage isolation in vault2
                let v2Data = manager.storage.loadPluginDataMap(workspaceID: vault2.id, pluginId: "obsidian-selftest-plugin")
                rec.check(v2Data["plugin-data"] == nil, "工作区 B 不应读取到工作区 A 的插件存储数据")

                await manager.uninstall(pluginId: "obsidian-selftest-plugin")
                rec.check(manager.record(for: "obsidian-selftest-plugin") == nil, "Obsidian 插件卸载后应清理完毕")
            } catch {
                rec.failures.append("Obsidian 插件自测异常：\(error.localizedDescription)")
            }
        }

        _ = pumpUntil(timeout: 25.0) { rec.finished }
        if !rec.finished {
            rec.failures.append("插件异步自测超时未完成")
        }
        defaults.removePersistentDomain(forName: suiteName)
        return rec.failures
    }

    private static func runVersionHistoryAndSafetyTests(baseRoot: URL) -> [String] {
        var failures: [String] = []
        func check(_ condition: Bool, _ message: String) {
            if !condition { failures.append(message) }
        }

        let safetyRoot = baseRoot.appendingPathComponent("history-safety-vault", isDirectory: true)
        try? FileManager.default.removeItem(at: safetyRoot)
        let suiteName = "com.lexinote.mac.selftest.history"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defaults.removePersistentDomain(forName: suiteName)

        let settings = SettingsStore(defaults: defaults)
        settings.showWelcome = false
        settings.autoSave = true

        let model = AppModel(settings: settings, storageRoot: safetyRoot, inMemory: false)
        let doc = model.createNote(title: "历史与容错测试",
                                   content: "第1行：初始版本\n第2行：共同上下文",
                                   type: .markdown, notebook: "安全验证", tags: ["v1"])
        check(model.saveNoteNow(doc.id), "安全测试笔记应能保存")

        model.updateNoteContent(doc.id, content: "第1行：第二次修订\n第2行：共同上下文\n第3行：新增段落")
        check(model.saveNoteNow(doc.id), "第二次修订应能保存")

        let countAfterTwo = model.noteRevisions(for: doc.id).count
        check(countAfterTwo >= 2, "保存两次不同版本后应至少有 2 条快照，实际 \(countAfterTwo)")

        // Saving identical content should deduplicate
        check(model.saveNoteNow(doc.id), "重复保存应成功")
        check(model.noteRevisions(for: doc.id).count == countAfterTwo, "内容未变更时不应产生重复快照")

        // Diff comparison check
        let revsBeforeRestore = model.noteRevisions(for: doc.id)
        if revsBeforeRestore.count >= 2 {
            let oldest = revsBeforeRestore.last!
            let newest = revsBeforeRestore.first!
            let diff = NoteDiffEngine.diff(
                oldTitle: oldest.title, oldContent: oldest.content, oldTags: oldest.tags,
                newTitle: newest.title, newContent: newest.content, newTags: newest.tags
            )
            check(diff.addedCount >= 2 && diff.removedCount >= 1 && diff.unchangedCount >= 1,
                  "差异对比应准确识别新增、删除与未变更行")

            // Restore with unsaved draft should auto-backup the unsaved live edit BEFORE restoring
            settings.autoSave = false
            model.updateNoteContent(doc.id, content: "第1行：未保存草稿-恢复前必须备份\n第2行：共同上下文")
            check(model.restoreNoteVersion(noteID: doc.id, revisionID: oldest.id), "恢复最早版本应成功")
            check(model.note(doc.id)?.content == oldest.content, "恢复后当前正文应等于目标历史版本")

            let afterRestore = model.noteRevisions(for: doc.id)
            check(afterRestore.contains(where: { $0.reason == .restoreBackup && $0.content.contains("未保存草稿-恢复前必须备份") }),
                  "恢复历史版本前应自动把当前未保存草稿保存为 restore-backup 快照")
        }

        // Retention policy cleanup (age + count + storage bytes)
        let now = Date()
        let oldRev = NoteRevision(
            id: "rev-expired",
            noteID: "retention-note",
            vaultID: model.activeVaultID,
            title: "过期",
            content: "超过30天的快照",
            tags: [],
            properties: [],
            notebook: "测试",
            reason: .autosave,
            contentHash: "old-hash",
            byteSize: 2048,
            createdAt: now.addingTimeInterval(-35 * 86_400)
        )
        let midRev = NoteRevision(
            id: "rev-mid",
            noteID: "retention-note",
            vaultID: model.activeVaultID,
            title: "较早",
            content: String(repeating: "A", count: 6000),
            tags: [],
            properties: [],
            notebook: "测试",
            reason: .autosave,
            contentHash: "mid-hash",
            byteSize: 6000,
            createdAt: now.addingTimeInterval(-60)
        )
        let recentRev = NoteRevision(
            id: "rev-recent",
            noteID: "retention-note",
            vaultID: model.activeVaultID,
            title: "最新",
            content: String(repeating: "B", count: 5000),
            tags: [],
            properties: [],
            notebook: "测试",
            reason: .autosave,
            contentHash: "recent-hash",
            byteSize: 5000,
            createdAt: now
        )
        let pruned = model.library.historyStore.pruneNoteRevisions(
            [recentRev, midRev, oldRev],
            policy: HistoryRetentionPolicy(maxAgeDays: 30, maxCountPerNote: 30, maxBytesPerNote: 8192, maxTotalBytes: 50 * 1024 * 1024),
            now: now
        )
        check(!pruned.contains(where: { $0.id == "rev-expired" }), "超过 30 天的历史快照应被按时间清理")
        check(pruned.count == 1 && pruned.first?.id == "rev-recent",
              "超出单篇容量上限时应淘汰较早快照并保留最新快照")

        // Disk-full (ENOSPC) atomic save guarantee & zero temp leftover
        settings.autoSave = true
        let safeDoc = model.createNote(title: "磁盘满防护", content: "安全稳妥版本", type: .markdown, notebook: "安全验证")
        check(model.saveNoteNow(safeDoc.id), "正常写入应成功")
        guard let savedPath = model.note(safeDoc.id)?.path,
              let vault = model.vault(safeDoc.vaultID) else {
            failures.append("找不到磁盘满测试笔记路径")
            defaults.removePersistentDomain(forName: suiteName)
            return failures
        }
        let targetURL = model.vaultFolder(vault).appendingPathComponent(savedPath)
        let folderDir = targetURL.deletingLastPathComponent()

        model.library.writeHook = { _, _, url in
            if url.path == targetURL.path {
                throw POSIXError(.ENOSPC)
            }
        }
        model.updateNoteContent(safeDoc.id, content: "磁盘写满时的未落盘新编辑")
        let saveWhileFull = model.saveNoteNow(safeDoc.id)
        check(!saveWhileFull, "ENOSPC 时 saveNoteNow 必须返回 false 而不是假报成功")
        if case .failed(let errMsg) = model.saveState {
            check(errMsg.contains("磁盘空间不足"), "ENOSPC 错误文案应明确提示磁盘空间不足，实际：\(errMsg)")
        } else {
            failures.append("ENOSPC 失败后 saveState 应保持 .failed")
        }
        check(model.hasUnsavedDirty(safeDoc.id), "写失败的笔记应继续保留 dirty 标记以便重试")
        let diskIntact = (try? String(contentsOf: targetURL, encoding: .utf8)) ?? ""
        check(diskIntact.contains("安全稳妥版本") && !diskIntact.contains("未落盘新编辑"),
              "ENOSPC 写入失败绝不能破坏磁盘上原有的 Markdown 文件")
        let dirContents = (try? FileManager.default.contentsOfDirectory(atPath: folderDir.path)) ?? []
        check(!dirContents.contains(where: { $0.hasPrefix(".lexi-tmp-") }),
              "ENOSPC 写入失败后应自动清理所有临时文件")

        model.library.writeHook = nil
        check(model.saveNoteNow(safeDoc.id), "恢复磁盘空间后重试验存应成功")

        // Real OS read-only directory write failure (POSIX EACCES) must also fail cleanly without data loss
        try? FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: folderDir.path)
        model.updateNoteContent(safeDoc.id, content: "只读目录拦截期间的新修改")
        let readOnlySave = model.saveNoteNow(safeDoc.id)
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folderDir.path)
        check(!readOnlySave, "无写入权限目录保存时应返回 false 而不是假报成功")
        let diskAfterReadOnly = (try? String(contentsOf: targetURL, encoding: .utf8)) ?? ""
        check(diskAfterReadOnly.contains("磁盘写满时的未落盘新编辑") && !diskAfterReadOnly.contains("只读目录拦截"),
              "权限失败期间磁盘原文件应保持完整不受破坏")
        check(model.saveNoteNow(safeDoc.id), "恢复写权限后应能继续保存最新编辑")

        // Global storage limit (maxTotalBytes) pruning across multiple notes
        let nA = model.createNote(title: "全局配额A", content: String(repeating: "X", count: 9000), type: .markdown, notebook: "安全验证")
        _ = model.saveNoteNow(nA.id)
        let nB = model.createNote(title: "全局配额B", content: String(repeating: "Y", count: 9000), type: .markdown, notebook: "安全验证")
        _ = model.saveNoteNow(nB.id)
        model.library.historyPolicy = HistoryRetentionPolicy(maxAgeDays: 30, maxCountPerNote: 30, maxBytesPerNote: 500_000, maxTotalBytes: 24_000)
        let usageAfterPrune = model.pruneHistoryNow()
        check(usageAfterPrune.totalBytes <= 24_000,
              "全量历史清理后总存储应不超过 24KB 配额，实际 \(usageAfterPrune.totalBytes)")
        model.library.historyPolicy = .default

        // Crash WAL recovery across simulated restart
        settings.autoSave = false
        model.updateNoteContent(safeDoc.id, content: "进程异常退出前刚键入的未保存草稿")
        model.flushCrashWalNow()
        let diskBeforeCrash = (try? String(contentsOf: targetURL, encoding: .utf8)) ?? ""
        check(!diskBeforeCrash.contains("异常退出前刚键入"), "模拟断电前主 Markdown 文件尚未刷入该草稿")

        // Also simulate an orphan new note whose .md never existed on disk before crash
        let orphanWal = CrashRecoveryDraft(
            noteID: "note-crash-orphan",
            vaultID: safeDoc.vaultID,
            title: "崩溃前新建的未落盘笔记",
            content: "只在 WAL 中存在的珍贵内容",
            tags: ["恢复"],
            properties: [],
            notebook: "安全验证",
            baseHash: "",
            updatedAt: Date()
        )
        _ = model.library.historyStore.writeWalDraft(orphanWal)

        let crashReloaded = AppModel(settings: settings, storageRoot: safetyRoot, inMemory: false)
        check(crashReloaded.note(safeDoc.id)?.content == "进程异常退出前刚键入的未保存草稿",
              "重启后应从 WAL 自动恢复异常退出前的未保存草稿")
        check(crashReloaded.recoveredCrashDrafts.contains(where: { $0.noteID == safeDoc.id }),
              "重启后应标记已恢复的异常草稿供用户对比确认")
        check(crashReloaded.note("note-crash-orphan")?.content == "只在 WAL 中存在的珍贵内容",
              "哪怕崩溃前连 Markdown 文件都还没来得及建立，WAL 也应重建该笔记")
        check(crashReloaded.noteRevisions(for: safeDoc.id).contains(where: { $0.reason == .crashRecovery }),
              "异常恢复的草稿应同步写入版本历史")

        // Resolve/save crash recovery and test multi-window + external disk conflict protection
        crashReloaded.dismissCrashRecovery(safeDoc.id)
        crashReloaded.dismissCrashRecovery("note-crash-orphan")

        let win1 = crashReloaded
        let win2 = AppModel(settings: SettingsStore(defaults: defaults, vaultID: win1.activeVaultID),
                            sharedLibrary: win1.library,
                            initialVaultID: win1.activeVaultID,
                            isPrimaryWindow: false)
        settings.autoSave = true
        let sharedDoc = win1.createNote(title: "双窗口并发验证", content: "初始共享版本 v0", type: .markdown, notebook: "安全验证")
        check(win1.saveNoteNow(sharedDoc.id), "共享文档应能保存")
        win1.openNote(sharedDoc.id)
        win2.openNote(sharedDoc.id)

        win1.updateNoteContent(sharedDoc.id, content: "窗口一先提交的内容 v1")
        check(win1.saveNoteNow(sharedDoc.id), "窗口一保存应成功")

        // Window 2 still holds stale v0 base and tries concurrent edit -> must NOT silently overwrite Window 1
        win2.updateNoteContent(sharedDoc.id, content: "窗口二并发输入的内容 v2")
        check(win2.note(sharedDoc.id)?.content == "窗口一先提交的内容 v1",
              "窗口二并发编辑时绝不能静默覆盖窗口一已保存的内容")
        check(win2.noteConflict(for: sharedDoc.id) != nil,
              "并发编辑冲突必须显式进入 pendingConflicts 待处理队列")

        let conflictCopy = win2.resolveNoteConflict(sharedDoc.id, mode: .saveConflictCopy)
        check(conflictCopy != nil && conflictCopy?.content == "窗口二并发输入的内容 v2",
              "选择另存冲突副本后应完整保留窗口二修改且不丢失窗口一内容")
        check(win1.note(sharedDoc.id)?.content == "窗口一先提交的内容 v1",
              "原笔记中窗口一的修改应保持完好无损")

        // External disk edit conflict protection
        if let sharedPath = win1.note(sharedDoc.id)?.path,
           let sharedVault = win1.vault(sharedDoc.vaultID) {
            let sharedDiskURL = win1.vaultFolder(sharedVault).appendingPathComponent(sharedPath)
            var diskNote = win1.note(sharedDoc.id)!
            diskNote.content = "外部编辑器在磁盘上直接写入的内容 v3"
            try? NoteCodec.encode(diskNote).write(to: sharedDiskURL, atomically: true, encoding: .utf8)

            win1.updateNoteContent(sharedDoc.id, content: "应用内存尝试直接覆盖的内容 v4")
            let overwriteAttempt = win1.saveNoteNow(sharedDoc.id)
            check(!overwriteAttempt, "磁盘文件被外部进程修改后 saveNoteNow 应拒绝静默覆盖")
            check(win1.noteConflict(for: sharedDoc.id) != nil, "外部磁盘冲突应记录到待处理冲突")
            let currentDisk = (try? String(contentsOf: sharedDiskURL, encoding: .utf8)) ?? ""
            check(currentDisk.contains("外部编辑器在磁盘上直接写入的内容 v3"),
                  "发生外部修改冲突时绝不能静默覆盖外部磁盘文件")
            _ = win1.resolveNoteConflict(sharedDoc.id, mode: .takeTheirsBackupMine)
            check(win1.note(sharedDoc.id)?.content == "外部编辑器在磁盘上直接写入的内容 v3",
                  "选择采用最新磁盘版本应更新编辑器并将内存修改存入历史")
            check(win1.noteRevisions(for: sharedDoc.id).contains(where: { $0.reason == .conflictBackup && $0.content.contains("v4") }),
                  "冲突解决前应自动将落选版本备份到历史快照中")
        }

        try? FileManager.default.removeItem(at: safetyRoot)
        defaults.removePersistentDomain(forName: suiteName)
        return failures
    }

    private static func runPluginSecuritySelfTests(root: URL) -> [String] {
        var failures: [String] = []
        func check(_ cond: Bool, _ msg: String) {
            if !cond { failures.append(msg) }
        }

        let secRoot = root.appendingPathComponent("plugin-security-selftest", isDirectory: true)
        try? FileManager.default.removeItem(at: secRoot)
        let storage = PluginStorage(storageRoot: secRoot, ephemeral: false)
        defer {
            storage.clearTestSecrets()
            try? FileManager.default.removeItem(at: secRoot)
        }

        let aiDir = secRoot.appendingPathComponent(".plugins/ai", isDirectory: true)
        try? FileManager.default.createDirectory(at: aiDir, withIntermediateDirectories: true)

        // 1. DeepSeek-Harness Credential Separation (0600 owner-only file, no secret in binding.json)
        do {
            let service = PluginAiService(storage: storage)
            let created = try service.configure(pluginId: "lexinote.harness", params: [
                "action": "create",
                "profileId": "p1",
                "name": "DeepSeek",
                "provider": "openai-compatible",
                "baseUrl": "https://api.deepseek.com",
                "model": "deepseek-chat",
                "apiKey": "sk-deepseek-harness-secret-9988"
            ])
            check((created["credentialRef"] as? String) == "DEEPSEEK_API_KEY",
                  "DeepSeek 配置应自动推导 credentialRef = DEEPSEEK_API_KEY")
            let expectedMask = PluginAiService.maskCredential("sk-deepseek-harness-secret-9988")
            check(expectedMask == "sk-deeps•••••••••••••••••••9988",
                  "maskCredential 算法应与 deepseek-harness 完全一致（actual=\(expectedMask)）")
            check((created["maskedApiKey"] as? String) == expectedMask,
                  "aiStatus 应返回 maskedApiKey 脱敏预览")
            let credInfo = created["credential"] as? [String: Any]
            check((credInfo?["configured"] as? Bool) == true &&
                  (credInfo?["source"] as? String) == "store" &&
                  (credInfo?["writable"] as? Bool) == true &&
                  (credInfo?["masked"] as? String) == expectedMask,
                  "CredentialInfo 应准确返回 configured/source/writable/masked")

            let bindingURL = storage.bindingFileURL(pluginId: "lexinote.harness")
            let bindingText = (try? String(contentsOf: bindingURL, encoding: .utf8)) ?? ""
            check(!bindingText.contains("sk-deepseek-harness-secret-9988") &&
                  bindingText.contains("DEEPSEEK_API_KEY"),
                  "binding.json 只存 credentialRef，绝不能写入明文 API Key")

            let credURL = storage.credentialsFileURL(pluginId: "lexinote.harness")
            let attrs = try FileManager.default.attributesOfItem(atPath: credURL.path)
            let perm = (attrs[.posixPermissions] as? NSNumber)?.uint16Value ?? 0
            check((perm & 0o777) == 0o600, "credentials.json 权限必须为仅属主可读写 0600")

            // Loose permissions (0644) must be rejected cleanly matching dsh assertOwnerOnly
            try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: credURL.path)
            do {
                _ = try storage.resolveStoredSecret(pluginId: "lexinote.harness", profileId: "p1")
                failures.append("permissions 0644 的 credentials.json 应被拒绝读取")
            } catch let err as PluginHostError {
                check(err.code == PluginErrorCode.io && err.message.contains("chmod 600"),
                      "permissions 0644 应抛出明确的属主权限提示")
            }
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: credURL.path)

            // Dynamic env fallback when stored key cleared
            service.envOverrides["DEEPSEEK_API_KEY"] = "sk-from-env-layer-1234567890"
            _ = try service.configure(pluginId: "lexinote.harness", params: [
                "action": "clearCredential",
                "profileId": "p1"
            ])
            let envStatus = service.statusDictionary(pluginId: "lexinote.harness")
            check((envStatus["credentialSource"] as? String) == "env" &&
                  (envStatus["configured"] as? Bool) == true,
                  "清空已存密钥后若存在匹配环境变量应自动回退至 source=env")

            storage.clearAiConfig(pluginId: "lexinote.harness")
            check(storage.loadAiSecret(pluginId: "lexinote.harness", profileId: "p1").isEmpty,
                  "clearAiConfig 后私密凭据文件应彻底删除")
        } catch {
            failures.append("deepseek-harness 凭据隔离验证失败: \(error.localizedDescription)")
        }

        // 2. apiKeyFailure & dsh compat/retryPolicy checks
        do {
            let service = PluginAiService(storage: storage)
            for badKey in ["   ", "\"sk-quoted-12345678\"", "DEEPSEEK_API_KEY=sk-123456789", "sk-invalid key with spaces\n"] {
                do {
                    _ = try service.validateApiKey(badKey)
                    failures.append("非法 API Key 输入应被拒绝: \(badKey)")
                } catch {}
            }
            let compatBody = PluginAiService.openAiChatBody(
                model: "gpt-5",
                system: "sys-rule",
                messages: [["role": "user", "content": "hi"]],
                tools: nil,
                maxTokens: 1024,
                temperature: 0.2,
                compat: PluginAiCompatConfig(maxTokensField: "max_completion_tokens", thinkingFormat: "openai", supportsDeveloperRole: true)
            )
            let compatMsgs = compatBody["messages"] as? [[String: Any]] ?? []
            check(compatBody["max_completion_tokens"] as? Int == 1024 &&
                  compatBody["max_tokens"] == nil &&
                  (compatMsgs.first?["role"] as? String) == "developer",
                  "compat.maxTokensField 与 supportsDeveloperRole 应正确映射 OpenAI 请求体")
        }

        // 3. Boot payload sanitization & redaction validation
        let rawBootData = "{\"harness.providers.v1\":{\"secret\":\"sk-old\"},\"harness.settings.v2\":{\"theme\":\"dark\"}}"
        let cleanBootData = PluginManager.sanitizedBootDataJson(pluginId: "lexinote.harness", raw: rawBootData)
        check(!cleanBootData.contains("harness.providers.v1") && !cleanBootData.contains("sk-old"),
              "macOS 插件启动时必须从 dataJson 剥离旧版 harness.providers.v1")
        check(cleanBootData.contains("harness.settings.v2"),
              "剥离旧凭据数据时应保留其余插件数据")

        let aiService = PluginAiService(storage: storage)
        do {
            _ = try aiService.validateApiKey("sk-invalid key with spaces\n")
            failures.append("包含空白/换行的 API Key 应被拒绝")
        } catch {}

        let leaked = "Authorization: Bearer sk-secret999999 / x-api-key: my-key-888"
        let redacted = PluginAiService.redactSecrets(leaked, knownSecret: "my-key-888")
        check(!redacted.contains("sk-secret999999") && !redacted.contains("my-key-888"),
              "错误脱敏应遮蔽 Bearer/sk- 与已知明文 Key")

        // 4. Refuse HTTP 302 redirects to avoid leaking Bearer/x-api-key headers
        let serverFD = socket(AF_INET, SOCK_STREAM, 0)
        if serverFD >= 0 {
            var opt: Int32 = 1
            setsockopt(serverFD, SOL_SOCKET, SO_REUSEADDR, &opt, socklen_t(MemoryLayout<Int32>.size))
            var addr = sockaddr_in()
            addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
            addr.sin_family = sa_family_t(AF_INET)
            addr.sin_port = 0
            addr.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))
            let bound = withUnsafePointer(to: &addr) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    bind(serverFD, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
            if bound == 0, listen(serverFD, 1) == 0 {
                var boundAddr = sockaddr_in()
                var addrLen = socklen_t(MemoryLayout<sockaddr_in>.size)
                _ = withUnsafeMutablePointer(to: &boundAddr) {
                    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                        getsockname(serverFD, $0, &addrLen)
                    }
                }
                let port = UInt16(bigEndian: boundAddr.sin_port)
                DispatchQueue.global().async {
                    var clientAddr = sockaddr_in()
                    var clientLen = socklen_t(MemoryLayout<sockaddr_in>.size)
                    let clientFD = withUnsafeMutablePointer(to: &clientAddr) {
                        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                            accept(serverFD, $0, &clientLen)
                        }
                    }
                    if clientFD >= 0 {
                        // Drain request bytes before responding so closing clientFD does not emit a TCP RST race.
                        var reqBuf = [UInt8](repeating: 0, count: 2048)
                        _ = recv(clientFD, &reqBuf, reqBuf.count, 0)
                        let body = "HTTP/1.1 302 Found\r\nLocation: http://127.0.0.1:\(port)/should-not-follow\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
                        _ = body.withCString { ptr in
                            send(clientFD, ptr, strlen(ptr), 0)
                        }
                        shutdown(clientFD, SHUT_WR)
                        usleep(50_000)
                        close(clientFD)
                    }
                    close(serverFD)
                }

                final class RedirectTestState {
                    var done = false
                    var errorText = ""
                }
                let rec = RedirectTestState()
                Task { @MainActor in
                    defer { rec.done = true }
                    do {
                        _ = try aiService.configure(pluginId: "redirect.test", params: [
                            "provider": "openai-compatible",
                            "baseUrl": "http://127.0.0.1:\(port)/v1",
                            "model": "m",
                            "apiKey": "sk-redirect-secret-check"
                        ])
                        _ = try await aiService.listModels(pluginId: "redirect.test")
                        rec.errorText = "UNEXPECTED_SUCCESS"
                    } catch {
                        rec.errorText = error.localizedDescription
                    }
                }
                let deadline = Date().addingTimeInterval(5)
                while !rec.done && Date() < deadline {
                    RunLoop.current.run(until: Date().addingTimeInterval(0.02))
                }
                check(rec.done && rec.errorText != "UNEXPECTED_SUCCESS" && rec.errorText.contains("重定向"),
                      "模型 HTTP 请求必须拒绝 30x 重定向（actual=\(rec.errorText)）")
                storage.clearAiConfig(pluginId: "redirect.test")
            } else {
                close(serverFD)
                failures.append("无法绑定本地回环端口用于重定向测试")
            }
        }

        // 5. ai.configure create/save/select/remove lifecycle & needsApiKey accuracy
        do {
            let pid = "harness.config.test"
            let created1 = try aiService.configure(pluginId: pid, params: [
                "action": "create",
                "name": "DeepSeek",
                "provider": "openai-compatible",
                "baseUrl": "https://api.deepseek.com/",
                "model": "deepseek-chat",
                "apiKey": "sk-ds-primary-123"
            ])
            let id1 = created1["profileId"] as? String ?? ""
            check(!id1.isEmpty && id1 != "default", "action=create 未传 profileId 时应自动生成唯一服务商标识")
            check((created1["configured"] as? Bool) == true && (created1["needsApiKey"] as? Bool) == false,
                  "保存有效密钥后 configured 应为 true 且 needsApiKey 应为 false")
            check((created1["baseUrl"] as? String) == "https://api.deepseek.com", "Base URL 尾部斜杠应规范化移除")

            let created2 = try aiService.configure(pluginId: pid, params: [
                "action": "create",
                "profileId": "service_anthropic_2",
                "name": "Anthropic",
                "provider": "anthropic-compatible",
                "baseUrl": "https://api.anthropic.com",
                "model": "claude-sonnet-4-20250514",
                "apiKey": "sk-ant-secondary-456",
                "select": false
            ])
            check((created2["profileId"] as? String) == id1, "select=false 创建第二服务商时应保持原活跃服务商不变")
            let listAfter2 = created2["profiles"] as? [[String: Any]] ?? []
            check(listAfter2.count == 2, "profiles 列表应包含两个服务商")

            // Update inactive second profile without apiKey and switch model cleanly
            let saved2 = try aiService.configure(pluginId: pid, params: [
                "action": "save",
                "profileId": "service_anthropic_2",
                "model": "claude-opus-4-20250514",
                "select": false
            ])
            check((saved2["profileId"] as? String) == id1, "select=false 更新非活跃服务商不应切换当前活跃服务商")
            let listSaved2 = saved2["profiles"] as? [[String: Any]] ?? []
            let secondItem = listSaved2.first(where: { ($0["profileId"] as? String) == "service_anthropic_2" })
            check((secondItem?["model"] as? String) == "claude-opus-4-20250514" &&
                  (secondItem?["baseUrl"] as? String) == "https://api.anthropic.com" &&
                  (secondItem?["provider"] as? String) == "anthropic-compatible" &&
                  (secondItem?["needsApiKey"] as? Bool) == false,
                  "action=save 部分更新应保留原有协议与地址且保持无需补填密钥状态")

            // Quick model switch omitting action & profileId preserves baseUrl/provider/secret
            let switchedModel = try aiService.configure(pluginId: pid, params: ["model": "deepseek-reasoner"])
            check((switchedModel["profileId"] as? String) == id1 &&
                  (switchedModel["model"] as? String) == "deepseek-reasoner" &&
                  (switchedModel["baseUrl"] as? String) == "https://api.deepseek.com" &&
                  (switchedModel["configured"] as? Bool) == true,
                  "仅传 model 切换模型时应保留原服务商地址与已存密钥")

            // Changing Base URL without re-entering apiKey must be refused
            do {
                _ = try aiService.configure(pluginId: pid, params: [
                    "action": "save",
                    "profileId": id1,
                    "baseUrl": "https://evil.example.com"
                ])
                failures.append("更换 Base URL 未重新填写 API Key 时应被宿主拒绝")
            } catch let err as PluginHostError {
                check(err.code == PluginErrorCode.invalidArgument, "更换 Base URL 缺省密钥应抛出 E_INVALID_ARGUMENT")
            }

            let selected2 = try aiService.configure(pluginId: pid, params: [
                "action": "select",
                "profileId": "service_anthropic_2"
            ])
            check((selected2["profileId"] as? String) == "service_anthropic_2", "action=select 应切换到目标服务商")

            let afterRemove = try aiService.configure(pluginId: pid, params: [
                "action": "remove",
                "profileId": "service_anthropic_2"
            ])
            check((afterRemove["profileId"] as? String) == id1 &&
                  ((afterRemove["profiles"] as? [[String: Any]])?.count == 1),
                  "移除当前活跃服务商后应回退至剩余服务商")

            storage.clearAiConfig(pluginId: pid)
        } catch {
            failures.append("ai.configure 多服务商增删改验证失败: \(error.localizedDescription)")
        }

        // 6. OpenAI & Anthropic wire serialization for plugin tools & tool-call messages
        let sampleTools: [[String: Any]] = [
            [
                "name": "read_note",
                "description": "Read a markdown note",
                "parameters": [
                    "type": "object",
                    "properties": ["path": ["type": "string"]],
                    "required": ["path"]
                ]
            ]
        ]
        let sampleMessages: [[String: Any]] = [
            ["role": "system", "content": "msg-sys"],
            ["role": "user", "content": "hi"],
            [
                "role": "assistant",
                "content": "",
                "toolCalls": [
                    ["id": "call_1", "name": "read_note", "arguments": "{\"path\":\"a.md\"}"]
                ]
            ],
            ["role": "tool", "toolCallId": "call_1", "content": "note body"]
        ]

        let openAiBody = PluginAiService.openAiChatBody(
            model: "deepseek-chat",
            system: "top-sys",
            messages: sampleMessages,
            tools: sampleTools,
            maxTokens: 2048,
            temperature: 0.3
        )
        let wireOpenAiTools = openAiBody["tools"] as? [[String: Any]] ?? []
        let firstOpenAiToolFn = wireOpenAiTools.first?["function"] as? [String: Any]
        check((wireOpenAiTools.first?["type"] as? String) == "function" &&
              (firstOpenAiToolFn?["name"] as? String) == "read_note",
              "OpenAI 请求体 tools[0] 必须包含 type=function 与 nested function")
        let wireOpenAiMsgs = openAiBody["messages"] as? [[String: Any]] ?? []
        let assistantWire = wireOpenAiMsgs.first(where: { ($0["role"] as? String) == "assistant" })
        let wireToolCalls = assistantWire?["tool_calls"] as? [[String: Any]] ?? []
        let toolReplyWire = wireOpenAiMsgs.first(where: { ($0["role"] as? String) == "tool" })
        check((wireToolCalls.first?["type"] as? String) == "function" &&
              (wireToolCalls.first?["id"] as? String) == "call_1" &&
              (toolReplyWire?["tool_call_id"] as? String) == "call_1",
              "OpenAI 请求体必须将 assistant.toolCalls 与 tool.toolCallId 转换为标准 snake_case 字段")
        check((try? JSONSerialization.data(withJSONObject: openAiBody)) != nil, "OpenAI 请求体应能正常序列化为 JSON")

        let anthropicBody = PluginAiService.anthropicChatBody(
            model: "claude-sonnet-4-20250514",
            system: "top-sys",
            messages: sampleMessages,
            tools: sampleTools,
            maxTokens: 2048,
            temperature: 0.3
        )
        let anthropicTools = anthropicBody["tools"] as? [[String: Any]] ?? []
        check((anthropicTools.first?["name"] as? String) == "read_note" &&
              anthropicTools.first?["input_schema"] != nil,
              "Anthropic 请求体 tools 必须映射为 input_schema")
        let anthropicSys = anthropicBody["system"] as? String ?? ""
        check(anthropicSys.contains("top-sys") && anthropicSys.contains("msg-sys"),
              "Anthropic 请求体应合并 system 消息")
        let anthropicMsgs = anthropicBody["messages"] as? [[String: Any]] ?? []
        let antAssistantBlocks = (anthropicMsgs.first(where: { ($0["role"] as? String) == "assistant" })?["content"] as? [[String: Any]]) ?? []
        let antToolResultBlocks = (anthropicMsgs.last(where: { ($0["role"] as? String) == "user" })?["content"] as? [[String: Any]]) ?? []
        check((antAssistantBlocks.first?["type"] as? String) == "tool_use" &&
              (antToolResultBlocks.first?["type"] as? String) == "tool_result" &&
              (antToolResultBlocks.first?["tool_use_id"] as? String) == "call_1",
              "Anthropic 请求体必须转换 tool_use 与 tool_result 块")

        return failures
    }

    private static func imageHasVisibleInk(_ image: NSImage) -> Bool {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              cg.width > 0, cg.height > 0 else {
            return false
        }
        let w = min(cg.width, 300)
        let h = min(cg.height, 200)
        var buffer = [UInt8](repeating: 0, count: w * h * 4)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: &buffer,
            width: w,
            height: h,
            bitsPerComponent: 8,
            bytesPerRow: w * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return false
        }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        return buffer.contains { $0 > 4 }
    }

    private static func runMathPdfOpenSaveSelfTests(root: URL) -> [String] {
        var failures: [String] = []
        func check(_ condition: Bool, _ message: String) {
            if !condition { failures.append(message) }
        }

        // 1. Markdown math parser coverage (dollar, parens, brackets, align/cases, escaped currency)
        let mdSample = """
        价格 \\$100 和 \\$200 不应识别为公式，但 $100 和 $200 之间存在空格同样不应误判。

        行内公式 $E = mc^2$ 以及 \\(\\alpha + \\beta = \\gamma\\) 应当识别。

        \\[
        \\int_{0}^{1} x^2\\,dx = \\frac{1}{3}
        \\]

        \\begin{align*}
        a &= b + c \\\\
        d &= e + f
        \\end{align*}
        """
        let parsedBlocks = MarkdownParser.parse(mdSample)
        let mathBlocks = parsedBlocks.compactMap { block -> String? in
            if case .math(let formula) = block.kind { return formula }
            return nil
        }
        check(mathBlocks.count == 2, "Markdown 应识别 2 个块级公式（实际 \(mathBlocks.count)）")
        check(mathBlocks.first?.contains("\\int_{0}^{1}") == true, "应支持 \\[...\\] 块级公式")
        check(mathBlocks.last?.contains("\\begin{align*}") == true, "应支持 align* 块级公式")

        let paragraphInlines = parsedBlocks.compactMap { block -> [MDInline]? in
            if case .paragraph(let inlines) = block.kind { return inlines }
            return nil
        }
        check(paragraphInlines.count == 2, "货币文本段和公式段应正确分段")
        let currencyHasMath = (paragraphInlines.first ?? []).contains {
            if case .math = $0 { return true }
            return false
        }
        check(!currencyHasMath, "价格文本 '$100 和 $200' 不应误识别为行内公式")
        let formulaInlines = (paragraphInlines.last ?? []).compactMap { inline -> String? in
            if case .math(let tex) = inline { return tex }
            return nil
        }
        check(formulaInlines == ["E = mc^2", "\\alpha + \\beta = \\gamma"],
              "应同时识别 $...$ 与 \\(...\\) 行内公式（实际 \(formulaInlines)）")

        // 2. Offline KaTeX + MathJax WebKit renderer & PDF export verification
        check(LexiMathService.shared.isRendererAvailable, "macOS 捆绑离线 KaTeX/MathJax 资源应可用")

        final class AsyncState {
            var done = false
            var inlineResult: Result<RenderedMathBitmap, NSError>?
            var blockResult: Result<RenderedMathBitmap, NSError>?
            var mathJaxFallbackResult: Result<RenderedMathBitmap, NSError>?
            var invalidResult: Result<RenderedMathBitmap, NSError>?
            var pdfData: Data?
            var pdfError: String?
        }

        let featureRoot = root.appendingPathComponent("math-pdf-open-save", isDirectory: true)
        try? FileManager.default.createDirectory(at: featureRoot, withIntermediateDirectories: true)

        let state = AsyncState()
        let pdfOutURL = featureRoot.appendingPathComponent("formula-export.pdf")
        let testNote = Note(
            id: "note-pdf-math-test",
            vaultID: "v-test",
            notebook: "数学",
            title: "微积分与线性代数测试",
            content: """
            # 微积分与线性代数测试

            设矩阵 $A \\in \\R^{2 \\times 2}$，特征多项式为 $\\det(\\lambda I - A) = 0$。

            $$
            \\int_{-\\infty}^{\\infty} e^{-x^2}\\,dx = \\sqrt{\\pi}
            $$

            \\begin{cases}
            x^2, & x \\ge 0 \\\\
            0, & x < 0
            \\end{cases}

            > [!NOTE] 公式说明
            > 这是导出的 PDF 测试段落，验证 KaTeX 公式与中文混排。
            """,
            tags: ["数学", "PDF导出"]
        )

        Task { @MainActor in
            defer { state.done = true }
            state.inlineResult = await LexiMathService.shared.renderFormula(
                latex: "\\frac{a+b}{c}",
                displayMode: false,
                fontSize: 16,
                colorHex: "#231b36"
            )
            state.blockResult = await LexiMathService.shared.renderFormula(
                latex: "\\begin{cases} x^2, & x \\ge 0 \\\\ 0, & x < 0 \\end{cases}",
                displayMode: true,
                fontSize: 18,
                colorHex: "#231b36"
            )
            state.mathJaxFallbackResult = await LexiMathService.shared.renderFormula(
                latex: "\\dv{f}{x} = \\lim_{h \\to 0} \\frac{f(x+h)-f(x)}{h}",
                displayMode: true,
                fontSize: 18,
                colorHex: "#231b36"
            )
            state.invalidResult = await LexiMathService.shared.renderFormula(
                latex: "\\frac{1}{",
                displayMode: false,
                fontSize: 16,
                colorHex: "#231b36"
            )
            do {
                state.pdfData = try await LexiPdfExportService.shared.exportPDF(
                    note: testNote,
                    vaultURL: featureRoot,
                    to: pdfOutURL
                )
            } catch {
                state.pdfError = error.localizedDescription
            }
        }

        let deadline = Date().addingTimeInterval(25)
        while !state.done && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        }
        check(state.done, "异步 KaTeX 渲染与 PDF 导出应在 25 秒内完成")

        switch state.inlineResult {
        case .success(let bmp):
            check(bmp.engine == "katex", "常规行内分式应走 KaTeX 引擎，实际 \(bmp.engine)")
            check(bmp.size.width > 4 && bmp.size.height > 4, "行内公式渲染尺寸应有效")
            check(bmp.descent >= 0, "行内公式基线 descent 应非负")
            check(imageHasVisibleInk(bmp.image), "行内公式快照图像应包含可见像素（确认坐标与字体正确）")
        case .failure(let err):
            failures.append("行内 KaTeX 公式渲染失败：\(err.localizedDescription)")
        case nil:
            failures.append("行内 KaTeX 公式渲染未返回结果")
        }

        switch state.blockResult {
        case .success(let bmp):
            check(bmp.size.width > 10 && bmp.size.height > 10, "块级分段函数渲染尺寸应有效")
            check(imageHasVisibleInk(bmp.image), "块级公式图像应包含可见像素")
        case .failure(let err):
            failures.append("块级公式渲染失败：\(err.localizedDescription)")
        case nil:
            failures.append("块级公式渲染未返回结果")
        }

        switch state.mathJaxFallbackResult {
        case .success(let bmp):
            check(bmp.engine == "mathjax", "physics \\dv 宏应自动回退至 MathJax SVG 引擎，实际 \(bmp.engine)")
            check(imageHasVisibleInk(bmp.image), "MathJax 回退公式应包含可见像素")
        case .failure(let err):
            failures.append("MathJax 扩展语法回退渲染失败：\(err.localizedDescription)")
        case nil:
            failures.append("MathJax 回退渲染未返回结果")
        }

        if case .success = state.invalidResult {
            failures.append("非法 LaTeX 语法不应静默成功")
        }

        if let pdfError = state.pdfError {
            failures.append("PDF 导出失败：\(pdfError)")
        } else if let pdfData = state.pdfData {
            check(pdfData.starts(with: Data("%PDF-".utf8)), "导出的 PDF 应包含标准 %PDF- 文件头")
            check(FileManager.default.fileExists(atPath: pdfOutURL.path), "PDF 文件应写入磁盘")
            let doc = PDFDocument(data: pdfData)
            check((doc?.pageCount ?? 0) >= 1, "导出的 PDF 页数应至少为 1")
            check((doc?.string ?? "").contains("微积分与线性代数测试"), "导出的 PDF 应保留可选中的标题矢量文本")
        } else {
            failures.append("未生成 PDF 数据")
        }

        // 3. Save status timestamps + file open/error reporting checks
        let testSuiteName = "com.lexinote.mac.selftest.opensave"
        let testDefaults = UserDefaults(suiteName: testSuiteName) ?? .standard
        testDefaults.removePersistentDomain(forName: testSuiteName)
        let testSettings = SettingsStore(defaults: testDefaults)
        testSettings.showWelcome = false
        let openSaveModel = AppModel(settings: testSettings, storageRoot: featureRoot.appendingPathComponent("vaults"), inMemory: false)
        openSaveModel.bootstrapSession()

        let created = openSaveModel.createNote(title: "保存提示验证", content: "初始内容", notebook: "测试")
        check(openSaveModel.saveNoteWithFeedback(created.id), "手动保存应成功")
        let savedState = openSaveModel.effectiveSaveState(for: created.id)
        check(savedState.label.hasPrefix("已保存到本机 ") && savedState.label.contains(":"),
              "已保存状态应带 HH:mm:ss 时间戳，实际：\(savedState.label)")
        check(openSaveModel.toast?.message.contains(":") == true,
              "手动保存提示应包含精确时间：\(openSaveModel.toast?.message ?? "")")

        testSettings.autoSave = false
        let cleanPeer = openSaveModel.createNote(title: "未修改对照笔记", content: "干净内容", notebook: "测试", open: false)
        _ = openSaveModel.saveNoteNow(cleanPeer.id)
        openSaveModel.openNote(created.id)
        openSaveModel.updateNoteContent(created.id, content: "手动保存模式下尚未保存的修改")
        check(openSaveModel.effectiveSaveState(for: created.id) == .unsaved,
              "关闭自动保存编辑后应准确显示尚未保存")
        openSaveModel.openNote(cleanPeer.id)
        if case .saved = openSaveModel.effectiveSaveState(for: cleanPeer.id) {
            // Expected: switching to a clean note preserves accurate saved status
        } else {
            failures.append("切换到未修改笔记时不应误报为尚未保存")
        }

        // Missing note open feedback
        openSaveModel.openNote("note-does-not-exist")
        check(openSaveModel.toast?.message.contains("无法打开") == true,
              "打开不存在的笔记时应提示失败原因")

        // External file open: good .md + missing file + unsupported extension
        let externalMD = featureRoot.appendingPathComponent("外部分析笔记.md")
        try? "# 外部导入文档\n\n行内公式 $\\alpha + \\beta$".write(to: externalMD, atomically: true, encoding: .utf8)
        let missingFile = featureRoot.appendingPathComponent("missing-note.md")
        let unsupportedFile = featureRoot.appendingPathComponent("archive.bin")
        try? Data([0, 1, 2]).write(to: unsupportedFile)

        let openOutcome = openSaveModel.ingestExternalFiles(
            [externalMD, missingFile, unsupportedFile],
            includeJsonBackups: true,
            sourceLabel: "打开文件"
        )
        check(openOutcome.openedNotes == 1 && openOutcome.failedCount == 1,
              "混合打开外部文件应精准统计成功与失败数量（实际 \(openOutcome)）")
        check(openSaveModel.dataStatusMessage.contains("missing-note.md") && openSaveModel.dataStatusMessage.contains("不支持"),
              "混合打开外部文件状态提示应汇报失败原因与跳过项（实际：\(openSaveModel.dataStatusMessage)）")

        // Vault scan warning capture on unreadable/corrupt JSON mindmap
        if let firstVault = openSaveModel.vaults.first {
            let mapDir = openSaveModel.library.vaultFolder(firstVault).appendingPathComponent("思维导图", isDirectory: true)
            try? FileManager.default.createDirectory(at: mapDir, withIntermediateDirectories: true)
            try? Data("not-valid-json{{{".utf8).write(to: mapDir.appendingPathComponent("broken.mindmap.json"))
            openSaveModel.rebuildIndex()
            check(!openSaveModel.library.loadWarnings.isEmpty, "损坏的导图文件应进入 loadWarnings 提醒")
        }

        testDefaults.removePersistentDomain(forName: testSuiteName)
        return failures
    }

    private static func runDiscoveryFeaturesSelfTests(baseRoot: URL) -> [String] {
        var failures: [String] = []
        func check(_ condition: Bool, _ message: String) {
            if !condition { failures.append(message) }
        }

        let suiteName = "com.lexinote.mac.selftest.discovery"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defaults.removePersistentDomain(forName: suiteName)
        let discoveryRoot = baseRoot.appendingPathComponent("discovery-features", isDirectory: true)
        try? FileManager.default.removeItem(at: discoveryRoot)

        // 1. Highlight terms, non-overlapping segments, anchored snippet
        let terms = NoteSearch.highlightTerms("-excluded type:markdown #algo dynamic \"state transition\"")
        check(terms == ["state transition", "dynamic", "algo"],
              "高亮关键词解析应过滤排除项与结构化字段并去重排序，实际：\(terms)")
        let segments = NoteSearch.highlightSegments("Dynamic Programming uses state transition in #algo",
                                                    query: "-excluded type:markdown #algo dynamic \"state transition\"")
        let highlightedTexts = segments.filter(\.highlighted).map(\.text)
        check(highlightedTexts == ["Dynamic", "state transition", "algo"],
              "高亮分段应精准匹配大小写与多词片段，实际：\(highlightedTexts)")

        let settings = SettingsStore(defaults: defaults)
        settings.showWelcome = false
        let model = AppModel(settings: settings, storageRoot: discoveryRoot, inMemory: false)
        model.bootstrapSession()

        let longPrefix = String(repeating: "基础定义与上下文铺垫文本。", count: 8)
        let alpha = model.createNote(
            title: "动态规划",
            content: """
            # 动态规划

            \(longPrefix) 关键转移方程在这里出现，便于摘要居中截取。

            ## 前置知识
            递推与记忆化搜索。

            ## 状态转移
            dp[i] = max(dp[i-1], dp[i-2] + val[i])，只抽取本节预览。
            """,
            notebook: "算法",
            tags: ["算法", "dp"],
            open: false
        )
        _ = model.saveNoteNow(alpha.id)

        let snippetHit = alpha.snippet(matching: "转移方程", maxLength: 56)
        check(snippetHit.contains("转移方程") && snippetHit.hasPrefix("..."),
              "长正文搜索摘要应围绕关键词窗口截取，实际：\(snippetHit)")

        let source = model.createNote(
            title: "算法导论读书笔记",
            content: "# 算法导论读书笔记\n\n参考 [[动态规划#状态转移]]，忽略 [[不存在的目标]]。",
            notebook: "算法",
            tags: ["算法"],
            open: false
        )
        _ = model.saveNoteNow(source.id)

        // 2. Sort by recently accessed without mutating updatedAt / .md file / version history
        guard let vault = model.vaults.first else {
            failures.append("发现功能自测缺少默认工作区")
            defaults.removePersistentDomain(forName: suiteName)
            return failures
        }
        let vaultFolder = model.library.vaultFolder(vault)
        let alphaURL = vaultFolder.appendingPathComponent(alpha.path)
        let alphaDiskBefore = try? String(contentsOf: alphaURL, encoding: .utf8)
        let alphaUpdatedBefore = alpha.updatedAt
        let historyBefore = model.noteRevisions(for: alpha.id).count

        // Simulate source being updated later than alpha, then opening alpha even later
        Thread.sleep(forTimeInterval: 0.02)
        model.updateNoteContent(source.id, content: source.content + "\n补充一节。")
        _ = model.saveNoteNow(source.id)

        let laterAccess = Date().addingTimeInterval(120)
        model.library.recordNoteOpened(alpha.id, at: laterAccess)
        settings.sidebarSortMode = .accessed

        check(model.visibleNotes.first?.id == alpha.id,
              "最近访问排序应让最新打开的「动态规划」排在第一位")
        check(model.quickResults("").first?.id == alpha.id,
              "Quick Switcher 空查询应按最近访问排序")
        if let reloadedAlpha = model.note(alpha.id) {
            check(abs(reloadedAlpha.updatedAt.timeIntervalSince(alphaUpdatedBefore)) < 0.001,
                  "记录访问时间不应改写 updatedAt")
        }
        let alphaDiskAfter = try? String(contentsOf: alphaURL, encoding: .utf8)
        check(alphaDiskBefore == alphaDiskAfter, "记录访问时间不应改写磁盘 .md 文件")
        check(model.noteRevisions(for: alpha.id).count == historyBefore,
              "记录访问时间不应产生多余版本历史快照")

        // Verify persistence across AppModel / SettingsStore reload
        let settingsReloaded = SettingsStore(defaults: defaults)
        let modelReloaded = AppModel(settings: settingsReloaded, storageRoot: discoveryRoot, inMemory: false)
        check(settingsReloaded.sidebarSortMode == .accessed, "侧栏排序偏好应持久化保存")
        check(modelReloaded.visibleNotes.first?.id == alpha.id, "重启重载后最近访问顺序应从 note-access.json 恢复")

        // 3. Link target quick preview (existing anchor + missing link)
        let anchorPreview = model.linkTargetPreview(rawTarget: "动态规划#状态转移")
        check(anchorPreview.exists && anchorPreview.noteID == alpha.id && anchorPreview.anchor == "状态转移",
              "链接快速预览应精准解析标题与 #锚点")
        check(anchorPreview.snippet.contains("dp[i]") && !anchorPreview.snippet.contains("记忆化搜索"),
              "带 #锚点 的快速预览摘要应定位到对应小节，实际：\(anchorPreview.snippet)")
        check(anchorPreview.backlinkCount == 1, "目标笔记反链计数应为 1，实际 \(anchorPreview.backlinkCount)")

        let missingPreview = model.linkTargetPreview(rawTarget: "尚未创建的笔记")
        check(!missingPreview.exists && missingPreview.noteID == nil && missingPreview.title == "尚未创建的笔记",
              "未创建双链应返回 exists == false 的创建提示预览")

        // 4. Unconnected notes detection, unresolved links excluded, trashed notes excluded, 1-click link connect
        let isolated = model.createNote(
            title: "孤立随想",
            content: "# 孤立随想\n\n这里讨论动态规划的边界条件，还提到 [[不存在的笔记]]。",
            notebook: "算法",
            tags: ["算法"],
            open: false
        )
        let trashedIsolated = model.createNote(
            title: "回收站孤立笔记",
            content: "# 回收站孤立笔记",
            notebook: "算法",
            open: false
        )
        model.trashNote(trashedIsolated.id)

        let unconnectedIDs = Set(model.unconnectedNotes().map(\.id))
        check(unconnectedIDs.contains(isolated.id), "仅有未创建外链的活跃笔记仍应识别为未连接笔记")
        check(!unconnectedIDs.contains(alpha.id) && !unconnectedIDs.contains(source.id),
              "已建立有效双向连接的笔记不应列入未连接列表")
        check(!unconnectedIDs.contains(trashedIsolated.id), "回收站笔记不应计入未连接提示")

        model.unconnectedOnly = true
        check(model.visibleNotes.map(\.id) == [isolated.id], "开启未连接筛选应仅显示孤立笔记")
        model.unconnectedOnly = false

        let candidates = model.suggestLinkCandidates(for: isolated)
        check(candidates.first?.noteID == alpha.id,
              "正文提及「动态规划」且共享标签同笔记本的候选应排在第一位，实际：\(candidates.first?.title ?? "nil")")

        model.insertWikiLink(alpha.displayTitle, into: isolated.id)
        check(!model.isNoteUnconnected(model.note(isolated.id)!),
              "一键插入 [[\(alpha.displayTitle)]] 后孤立笔记应变为已连接")

        defaults.removePersistentDomain(forName: suiteName)
        return failures
    }
}
