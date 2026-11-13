import { AbilityConstant, Configuration, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { LexiTheme } from '../core/LexiTheme';
import { window } from '@kit.ArkUI';
import { LexiOfflineSpeech } from '../core/LexiOfflineSpeech';
import { LexiShareService } from '../core/LexiShareService';
import { LexiStorageService } from '../core/LexiStorageService';
import { LexiI18n } from '../core/LexiI18n';
import { LexiAppearanceSettings } from '../core/LexiAppearanceSettings';
import { LexiEditorSettings } from '../core/LexiEditorSettings';
import { LexiInterfaceSettings } from '../core/LexiInterfaceSettings';
import { LexiHotkeySettings } from '../core/LexiHotkeySettings';

// A separate ability gives each requested document its own native desktop window.
export default class DocumentAbility extends UIAbility {
  private documentId: string = '';
  private mainWindow: window.Window | undefined;
  private windowKey: string = `DocumentAbility:${Date.now()}:${Math.floor(Math.random() * 10000)}`;
  onBackground(): void {
    LexiOfflineSpeech.interruptAll();
    LexiShareService.unregisterWindow(this.windowKey);
  }
  onForeground(): void {
    LexiShareService.registerWindow(this.windowKey, this.context, this.mainWindow);
  }
  onCreate(want: Want, _launchParam: AbilityConstant.LaunchParam): void {
    this.onConfigurationUpdate(this.context.config);
    this.documentId = (want.parameters?.noteId as string) || '';
  }
  onConfigurationUpdate(configuration: Configuration): void {
    AppStorage.setOrCreate('lexiColorMode', configuration.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK ? 1 : 0);
    LexiTheme.refresh();
  }
  onWindowStageCreate(stage: window.WindowStage): void {
    this.loadWindow(stage).catch((): void => { this.context.terminateSelf(); });
  }
  private async loadWindow(stage: window.WindowStage): Promise<void> {
    await LexiStorageService.init(this.context);
    const doc = this.documentId.startsWith('map:') ?
      await LexiStorageService.getMindMapById(this.documentId.substring(4)) : await LexiStorageService.getNoteById(this.documentId);
    if (!doc) { throw new Error('文档已不存在'); }
    LexiStorageService.bindWindowWorkspace(doc.vaultId);
    await LexiI18n.load();
    await LexiAppearanceSettings.load();
    await LexiEditorSettings.load();
    await LexiHotkeySettings.load();
    await LexiInterfaceSettings.load();
    const theme = await LexiStorageService.getSetting('theme', 'system');
    this.context.getApplicationContext().setColorMode(theme === 'dark' ? ConfigurationConstant.ColorMode.COLOR_MODE_DARK :
      theme === 'light' ? ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT : ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
    const storage = new LocalStorage();
    storage.setOrCreate<string>('documentNoteId', this.documentId);
    stage.loadContent('pages/DocumentWindow', storage).then((): void => {
      const main = stage.getMainWindowSync();
      this.mainWindow = main;
      LexiTheme.bindWindow(main);
      LexiInterfaceSettings.attachStage(stage);
      main.setWindowDecorHeight(52); main.setWindowDecorVisible(false);
      LexiShareService.registerWindow(this.windowKey, this.context, this.mainWindow);
    }).catch((): void => { this.context.terminateSelf(); });
  }
  onWindowStageDestroy(): void {
    LexiTheme.bindWindow(undefined);
    LexiInterfaceSettings.detachStage();
    LexiShareService.unregisterWindow(this.windowKey);
    this.mainWindow = undefined;
  }
}
