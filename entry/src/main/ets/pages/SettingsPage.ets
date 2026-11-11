import { LexiSettingsWindow } from '../components/LexiSettingsWindow';
import { LexiSettingsActions } from '../core/LexiSettingsActions';
import { PluginRuntimeHost } from '../plugin/runtime/PluginRuntimeHost';

@Builder
export function settingsPageBuilder() {
  SettingsPage()
}

/**
 * Phone settings route.
 *
 * Deliberately a NavDestination, exactly like the trash page, so it inherits
 * the platform's push/pop transition and back gesture instead of a custom
 * overlay animation.
 */
@Component
export struct SettingsPage {
  @StorageProp('lexiSettingsInitialCategory') private initialCategory: string = 'about';
  @StorageProp('lexiSettingsWorkspaceName') private workspaceName: string = '';
  @StorageProp('lexiSettingsStorageLocation') private storageLocation: string = 'internal';
  @StorageProp('lexiSettingsTheme') private theme: string = 'system';
  @StorageProp('lexiSettingsDefaultTier') private defaultTier: string = 'simple';
  @StorageProp('lexiSettingsBusy') private busy: boolean = false;
  @StorageProp('lexiSettingsDataStatus') private dataStatus: string = '';
  @StorageProp('lexiSettingsLastBackup') private lastBackup: string = '';
  @StorageProp('lexiPluginRuntimeNeeded') private pluginRuntimeNeeded: boolean = false;
  private pathStack: NavPathStack = new NavPathStack();

  build() {
    NavDestination() {
      Stack({ alignContent: Alignment.TopStart }) {
        LexiSettingsWindow({
          pageMode: true,
          initialCategory: this.initialCategory,
          workspaceName: this.workspaceName,
          storageLocation: this.storageLocation,
          theme: this.theme,
          defaultTier: this.defaultTier,
          busy: this.busy,
          dataStatus: this.dataStatus,
          lastBackup: this.lastBackup,
          onSelectTheme: (value: string): void => { LexiSettingsActions.selectTheme(value); },
          onSelectTier: (value: string): void => { LexiSettingsActions.selectTier(value); },
          onExportBackup: (): void => { LexiSettingsActions.exportBackup(); },
          onExportMarkdown: (): void => { LexiSettingsActions.exportMarkdown(); },
          onImportFiles: (): void => { LexiSettingsActions.importFiles(); },
          onRebuildIndex: (): void => { LexiSettingsActions.rebuildIndex(); },
          onChooseStorage: (): void => { LexiSettingsActions.chooseStorage(); },
          onOpenHelp: (): void => { this.pathStack.pushPathByName('help', undefined); },
          onOpenTrash: (): void => { this.pathStack.pushPathByName('trash', undefined); },
          onShowInfo: (title: string, message: string): void => { LexiSettingsActions.showInfo(title, message); },
          onClose: (): void => { this.pathStack.pop(); }
        })
        // Phones have no workspace rail: this page owns the runtime page while it is open,
        // so "启用/停用" in plugin settings has somewhere to boot the plugin (1x1, no hits).
        if (this.pluginRuntimeNeeded) { PluginRuntimeHost() }
      }.width('100%').height('100%')
    }
    .hideTitleBar(true)
    .backgroundColor($r('app.color.workspace_page'))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .onReady((context: NavDestinationContext): void => {
      this.pathStack = context.pathStack;
    })
    .onBackPressed((): boolean => {
      this.pathStack.pop();
      return true;
    })
  }
}
