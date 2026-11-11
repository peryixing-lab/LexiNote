import { i18n } from '@kit.LocalizationKit';
import { LEXI_ENGLISH } from './LexiEnglish';
import { LexiStorageService } from './LexiStorageService';

/** Interface language is separate from note content, filenames, and plugin-owned copy. */
export class LexiI18n {
  static language(): string {
    const selected = AppStorage.get<string>('lexiLanguage');
    if (selected === 'en' || selected === 'zh-Hans') { return selected; }
    return LexiI18n.systemLanguage();
  }

  private static systemLanguage(): string {
    try {
      const preferred = i18n.System.getAppPreferredLanguage();
      const resolved = preferred && preferred !== 'default' ? preferred : i18n.System.getSystemLanguage();
      return resolved.toLowerCase().startsWith('en') ? 'en' : 'zh-Hans';
    } catch {
      return 'zh-Hans';
    }
  }

  static initialize(): void {
    AppStorage.setOrCreate<string>('lexiLanguage', LexiI18n.language());
  }

  static async load(): Promise<void> {
    const selected = await LexiStorageService.getSetting('language', LexiI18n.systemLanguage());
    AppStorage.setOrCreate<string>('lexiLanguage', selected === 'en' ? 'en' : 'zh-Hans');
  }

  static async select(language: string): Promise<void> {
    if (language !== 'en' && language !== 'zh-Hans') { return; }
    await LexiStorageService.setSetting('language', language);
    AppStorage.setOrCreate<string>('lexiLanguage', language);
  }

  static text(source: string, language: string = '', args: string[] = []): string {
    const selected = language || LexiI18n.language();
    let translated = selected === 'en' ? (LEXI_ENGLISH[source] ?? source) : source;
    for (let index = 0; index < args.length; index++) {
      translated = translated.split('{' + index.toString() + '}').join(args[index]);
    }
    return translated;
  }
}
