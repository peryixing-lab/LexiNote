import Foundation

@MainActor
enum SelfTest {
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

        // Plugin subsystem E2E tests (LexiNote native Harness ZIP + Obsidian compatibility plugin ZIP)
        let pluginFailures = runPluginSelfTests(root: root)
        failures.append(contentsOf: pluginFailures)

        defaults.removePersistentDomain(forName: suiteName)

        print("SELFTEST notes=\(mapReload.notes.count) maps=\(mapReload.maps.count) vaults=\(mapReload.vaults.count)")
        if failures.isEmpty {
            print("SELFTEST PASS")
        } else {
            for failure in failures { print("FAIL \(failure)") }
        }
        return failures.isEmpty
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
                ?? "../plugins/harness/dist/harness-lexinote-harness.zip"
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
                    await manager.uninstall(pluginId: "lexinote.harness")
                    rec.check(manager.record(for: "lexinote.harness") == nil, "卸载后应清除插件记录")
                } catch {
                    rec.failures.append("Harness 插件自测异常：\(error.localizedDescription)")
                }
            } else {
                rec.failures.append("未找到 Harness 插件测试包，请先运行 node plugins/harness/build.cjs：\(harnessZip.path)")
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
}
