import { PluginCapability, PluginInstallResult, PluginRecord, PluginState } from '../model/PluginModels';
import { PluginManager } from '../core/PluginManager';

class PluginCapabilityRow {
  name: string = '';
  label: string = '';
  granted: boolean = false;
}

class PluginRow {
  id: string = '';
  name: string = '';
  version: string = '';
  kindLabel: string = '';
  stateLabel: string = '';
  state: string = '';
  enabled: boolean = false;
  canEnable: boolean = false;
  lastError: string = '';
  capabilities: PluginCapabilityRow[] = [];
  diagnostics: string[] = [];
  expanded: boolean = false;
  allGranted: boolean = false;
  permissionReady: boolean = false;
}

/**
 * Native plugin settings surface (P08).
 *
 * Everything here is ArkUI; the panel only talks to PluginManager. There is no WebView in
 * this view, so plugin code cannot draw its own chrome over native settings.
 */
@Component
export struct LexiPluginSettingsPanel {
  @StorageProp('lexiPluginRevision') @Watch('reload') private pluginRevision: number = 0;
  @StorageProp('lexiAbilityForeground') @Watch('refreshInstalled') private abilityForeground: boolean = true;
  @State private rows: PluginRow[] = [];
  @State private status: string = '';
  @State private runtimeLabel: string = '未就绪';
  @State private busy: boolean = false;
  @State private permissionUiRevision: number = 0;
  private permissionPromptOpen: boolean = false;

  aboutToAppear(): void {
    this.reload();
    this.refreshInstalled();
  }

  private refreshInstalled(): void {
    if (!this.abilityForeground) { return; }
    PluginManager.refreshInstalled().then((): void => { this.reload(); }).catch((): void => {
      this.status = '已安装插件列表刷新失败，请重试。';
    });
  }

  private reload(): void {
    const records = PluginManager.records();
    const rows: PluginRow[] = [];
    for (const record of records) {
      const row = new PluginRow();
      row.id = record.id;
      row.name = record.name || record.id;
      row.version = record.version;
      row.kindLabel = PluginManager.kindLabel(record.kind);
      row.state = record.state;
      row.enabled = record.state === PluginState.ACTIVE;
      row.canEnable = record.state === PluginState.INSTALLED_DISABLED || record.state === PluginState.FAILED;
      row.stateLabel = this.stateLabel(record.state);
      row.lastError = record.lastError;
      const previous = this.rows.find((item: PluginRow): boolean => item.id === record.id);
      row.expanded = previous ? previous.expanded : false;
      row.allGranted = record.requestedCapabilities.length > 0 &&
        record.requestedCapabilities.every((capability: string): boolean => record.grantedCapabilities.includes(capability));
      row.permissionReady = row.allGranted && row.state === PluginState.FAILED && row.lastError.includes('E_PERMISSION_DENIED');
      if (row.permissionReady) { row.stateLabel = '待启用'; }
      for (const capability of record.requestedCapabilities) {
        const item = new PluginCapabilityRow();
        item.name = capability;
        item.label = this.capabilityLabel(capability);
        item.granted = record.grantedCapabilities.includes(capability);
        row.capabilities.push(item);
      }
      row.diagnostics = PluginManager.diagnosticsOf(record.id);
      rows.push(row);
    }
    this.rows = rows;
    this.runtimeLabel = PluginManager.runtimeLabel();
  }

  private stateLabel(state: string): string {
    if (state === PluginState.ACTIVE) { return '已启用'; }
    if (state === PluginState.STARTING) { return '启动中'; }
    if (state === PluginState.STOPPING) { return '停止中'; }
    if (state === PluginState.FAILED) { return '启动失败'; }
    if (state === PluginState.VALIDATING) { return '校验中'; }
    if (state === PluginState.UNINSTALLING) { return '卸载中'; }
    return '已停用';
  }

  private capabilityLabel(capability: string): string {
    if (capability === PluginCapability.VAULT_READ) { return '读取知识库文件'; }
    if (capability === PluginCapability.VAULT_WRITE) { return '创建/修改知识库文件'; }
    if (capability === PluginCapability.METADATA_READ) { return '读取元数据（标题/链接/标签）'; }
    if (capability === PluginCapability.EDITOR_READ) { return '读取当前编辑器'; }
    if (capability === PluginCapability.EDITOR_WRITE) { return '修改当前编辑器'; }
    if (capability === PluginCapability.WORKSPACE_VIEWS) { return '读取工作区与标签页'; }
    if (capability === PluginCapability.UI_NOTICE) { return '显示通知'; }
    if (capability === PluginCapability.UI_MODAL) { return '显示确认对话框'; }
    if (capability === PluginCapability.UI_COMMANDS) { return '注册命令'; }
    if (capability === PluginCapability.AI_INFERENCE) { return '调用模型（由知萤代办请求）'; }
    if (capability === PluginCapability.UI_VIEWS) { return '在侧栏显示插件视图'; }
    if (capability === PluginCapability.PLUGIN_STORAGE) { return '保存插件私有设置'; }
    if (capability === PluginCapability.NETWORK) { return '访问网络（实验版不开放）'; }
    return capability;
  }

  private toast(message: string): void {
    this.getUIContext().getPromptAction().showToast({ message: message });
  }

  private applyResult(result: PluginInstallResult): void {
    if (result.ok) {
      this.toast(`已安装 ${result.pluginId}`);
      // 多条提示都要看见（例如"未授权能力"+"仅桌面声明"），只显示第一条会漏掉关键信息。
      this.status = result.warnings.join('；');
    } else {
      this.toast(result.error.length > 0 ? result.error : '安装未完成');
      this.status = result.error;
    }
    this.reload();
  }

  private async run(action: () => Promise<void>): Promise<void> {
    if (this.busy) { return; }
    this.busy = true;
    this.status = '';
    try {
      await action();
    } catch (error) {
      this.status = (error as Error).message;
      this.toast((error as Error).message);
    } finally {
      this.busy = false;
      this.reload();
    }
  }

  private toggleCapability(row: PluginRow, capability: PluginCapabilityRow): void {
    this.run(async (): Promise<void> => {
      if (capability.granted) {
        await PluginManager.revoke(row.id, capability.name);
      } else {
        await PluginManager.grant(row.id, capability.name);
      }
    });
  }

  private async toggleAllPermissions(row: PluginRow, allow: boolean): Promise<void> {
    if (this.busy || this.permissionPromptOpen || allow === row.allGranted) { return; }
    if (!allow) {
      await this.run(async (): Promise<void> => {
        await PluginManager.revokeAll(row.id);
        this.status = `已撤回「${row.name}」的全部权限，插件已停用。`;
      });
      this.permissionUiRevision += 1;
      return;
    }
    this.permissionPromptOpen = true;
    let confirmed: boolean = false;
    try {
      const abilities = row.capabilities.map((capability: PluginCapabilityRow): string => capability.label).join('、');
      const choice = await this.getUIContext().getPromptAction().showDialog({
        title: `授予「${row.name}」全部权限？`,
        message: `将允许此插件使用它声明的全部能力：${abilities}。\n\n若包含知识库或编辑器写入能力，插件可以修改、删除笔记或替换编辑器内容。请只为你信任的插件开启。\n\n授权仅适用于此插件。正在运行的插件会重新启动，使权限生效。`,
        buttons: [
          { text: '取消', color: $r('app.color.text_secondary') },
          { text: '确认授予', color: $r('app.color.error') }
        ]
      });
      confirmed = choice.index === 1;
    } catch (error) {
      // Dismissing the risk dialog never grants a capability.
    } finally {
      this.permissionPromptOpen = false;
    }
    if (confirmed) {
      await this.run(async (): Promise<void> => {
        await PluginManager.grantAll(row.id);
        if (row.state === PluginState.ACTIVE) {
          await PluginManager.disable(row.id);
          await PluginManager.enable(row.id);
        } else if (row.state === PluginState.FAILED && row.lastError.includes('E_PERMISSION_DENIED')) {
          await PluginManager.disable(row.id);
        }
        this.status = row.state === PluginState.ACTIVE ? `已更新「${row.name}」的权限。` :
          `已授予「${row.name}」全部声明权限，可点击启用。`;
      });
    }
    this.permissionUiRevision += 1;
    this.reload();
  }

  private rowKey(row: PluginRow): string {
    const grants = row.capabilities.map((capability: PluginCapabilityRow): string => `${capability.name}:${capability.granted}`).join(',');
    return `${row.id}-${row.state}-${row.lastError}-${row.expanded}-${grants}-${this.permissionUiRevision}`;
  }

  private toggleExpanded(row: PluginRow): void {
    const next: PluginRow[] = [];
    for (const item of this.rows) {
      const copy = item;
      if (item.id === row.id) { copy.expanded = !item.expanded; }
      next.push(copy);
    }
    this.rows = next;
  }

  @Builder
  private actionButton(label: string, enabled: boolean, action: () => void) {
    Button(label)
      .height(30)
      .padding({ left: 12, right: 12 })
      .fontSize(12)
      .fontColor($r('app.color.text_primary'))
      .backgroundColor($r('app.color.soft_surface'))
      .borderRadius(6)
      .enabled(enabled && !this.busy)
      .opacity(enabled && !this.busy ? 1 : 0.45)
      .onClick((): void => { action(); })
  }

  @Builder
  private capabilityRow(row: PluginRow, capability: PluginCapabilityRow) {
    Row({ space: 8 }) {
      Toggle({ type: ToggleType.Switch, isOn: capability.granted })
        .selectedColor($r('app.color.brand'))
        .onChange((): void => { this.toggleCapability(row, capability); })
      Text(capability.label)
        .fontSize(12)
        .fontColor(capability.granted ? $r('app.color.text_primary') : $r('app.color.text_secondary'))
        .layoutWeight(1)
    }
    .width('100%')
    .height(34)
  }

  @Builder
  private pluginCard(row: PluginRow) {
    Column({ space: 8 }) {
      // The state badge leads the row so it can never be clipped by a narrow settings pane.
      Row({ space: 10 }) {
        Text(row.stateLabel)
          .fontSize(11)
          .fontColor(row.enabled ? $r('app.color.success') : (row.state === PluginState.FAILED && !row.permissionReady
            ? $r('app.color.error') : $r('app.color.text_secondary')))
          .padding({ left: 8, right: 8, top: 3, bottom: 3 })
          .backgroundColor($r('app.color.surface'))
          .borderRadius(10)
          .constraintSize({ minWidth: 52 })
          .textAlign(TextAlign.Center)
        Column({ space: 2 }) {
          Text(row.name).fontSize(14).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary'))
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
          Text(`${row.id} · v${row.version} · ${row.kindLabel}`)
            .fontSize(11).fontColor($r('app.color.text_secondary'))
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
      }.width('100%')

      Row({ space: 12 }) {
        Toggle({ type: ToggleType.Switch, isOn: row.allGranted })
          .id(`plugin-all-permissions-${row.id}`).selectedColor($r('app.color.brand'))
          .enabled(!this.busy && row.capabilities.length > 0 && (row.canEnable || row.enabled))
          .accessibilityText(`${row.name}：授予全部权限`)
          .onChange((allow: boolean): void => { this.toggleAllPermissions(row, allow); })
        Column({ space: 3 }) {
          Text('授予全部权限').fontSize(12).fontColor($r('app.color.text_primary'))
          Text('仅对当前插件生效；关闭将撤回全部权限并停用。')
            .fontSize(11).fontColor($r('app.color.text_secondary')).width('100%')
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
      }.width('100%').padding({ top: 8, bottom: 8 })

      if (row.lastError.length > 0) {
        Text(row.permissionReady ? '权限已授予，点击启用重新加载插件。' : row.lastError).fontSize(11)
          .fontColor(row.permissionReady ? $r('app.color.text_secondary') : $r('app.color.error'))
          .width('100%').maxLines(3).textOverflow({ overflow: TextOverflow.Ellipsis })
      }

      Row({ space: 8 }) {
        this.actionButton(row.enabled ? '停用' : '启用', row.enabled || row.canEnable, () => {
          if (row.enabled) {
            this.run(async (): Promise<void> => { await PluginManager.disable(row.id); });
          } else {
            this.run(async (): Promise<void> => { await PluginManager.enable(row.id); });
          }
        })
        this.actionButton(row.expanded ? '收起权限' : '能力与诊断', true, () => { this.toggleExpanded(row); })
        this.actionButton('卸载', true, () => {
          this.run(async (): Promise<void> => { await PluginManager.uninstall(row.id, false); });
        })
      }.width('100%')

      if (row.expanded) {
        Column({ space: 2 }) {
          Text('能力授权（取消勾选立即生效）')
            .fontSize(11).fontColor($r('app.color.text_secondary')).width('100%')
          ForEach(row.capabilities, (capability: PluginCapabilityRow) => {
            this.capabilityRow(row, capability)
          }, (capability: PluginCapabilityRow): string => `${row.id}-${capability.name}`)
          if (row.capabilities.length === 0) {
            Text('该插件未声明任何能力').fontSize(11).fontColor($r('app.color.text_secondary')).width('100%')
          }
          Text('诊断日志')
            .fontSize(11).fontColor($r('app.color.text_secondary')).width('100%').margin({ top: 8 })
          if (row.diagnostics.length === 0) {
            Text('暂无日志').fontSize(11).fontColor($r('app.color.text_secondary')).width('100%')
          } else {
            ForEach(row.diagnostics, (line: string, index: number) => {
              Text(line).fontSize(10).fontColor($r('app.color.text_secondary'))
                .width('100%').maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
            }, (line: string, index: number): string => `${row.id}-log-${index}`)
          }
        }.width('100%').alignItems(HorizontalAlign.Start)
      }
    }
    .width('100%')
    .padding(12)
    .borderRadius(10)
    .backgroundColor($r('app.color.soft_surface'))
    .alignItems(HorizontalAlign.Start)
  }

  build() {
    Column({ space: 12 }) {
      Text('插件').fontSize(18).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary'))
        .width('100%')
      Text('兼容 LexiNote 协议和 Obsidian 协议。')
        .id('plugin-protocol-support').fontSize(13).fontColor($r('app.color.text_primary')).width('100%')
      Text('已安装插件在所有工作区中可见，启用和停用状态由各工作区独立保存。')
        .id('plugin-workspace-policy').fontSize(12).fontColor($r('app.color.text_secondary')).width('100%')
      Text('实验性插件支持：仅安装你自己编写或已审查的插件。Obsidian 兼容层只覆盖已测试的 API 子集，未实现的能力会返回明确错误。')
        .fontSize(12).fontColor($r('app.color.text_secondary')).width('100%')

      Row({ space: 8 }) {
        Text(`运行时：${this.runtimeLabel}`).fontSize(12).fontColor($r('app.color.text_secondary'))
        Text(`已安装 ${this.rows.length} 个`).fontSize(12).fontColor($r('app.color.text_secondary'))
        Blank()
        this.actionButton('从本地安装 ZIP…', true, () => {
          this.run(async (): Promise<void> => {
            const result = await PluginManager.installFromPicker();
            this.applyResult(result);
          });
        })
      }.width('100%')

      if (this.status.length > 0) {
        Text(this.status)
          .fontSize(11).fontColor($r('app.color.warning'))
          .width('100%').maxLines(4)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }

      if (this.rows.length === 0) {
        Text('尚未安装插件。请自行下载插件，再通过「从本地安装 ZIP…」导入。')
          .fontSize(13).fontColor($r('app.color.text_secondary')).width('100%').padding({ top: 12 })
      } else {
        ForEach(this.rows, (row: PluginRow) => {
          this.pluginCard(row)
        }, (row: PluginRow): string => this.rowKey(row))
      }

      if (this.rows.some((row: PluginRow): boolean => row.capabilities.some((capability: PluginCapabilityRow): boolean =>
        capability.name === PluginCapability.AI_INFERENCE))) {
        Text('模型能力说明：插件只提交消息与工具定义，HTTP 请求、API Key 与超时都由知萤宿主管理；插件仍然拿不到网络，也读不回 Key。只为你信任的插件开启。')
          .fontSize(11).fontColor($r('app.color.text_secondary')).width('100%').margin({ top: 8 })
      }
      Text('安全说明：插件只能通过受控 RPC 访问当前授权的知识库；不支持 Node.js/Electron 模块、绝对路径或网络能力。禁用插件会立即释放其事件、命令与运行时资源。')
        .fontSize(11).fontColor($r('app.color.text_secondary')).width('100%').margin({ top: 8 })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({ bottom: 24 })
  }
}
