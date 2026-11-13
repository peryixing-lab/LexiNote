import { LEXI_ENGLISH } from './english';
import { UI_ENGLISH } from './ui-english';

export type UiLanguage = 'zh-Hans' | 'en';

let activeLanguage: UiLanguage = 'zh-Hans';

export function setActiveLanguage(language: UiLanguage): void {
  activeLanguage = language;
}

export function tr(source: string, language: UiLanguage = activeLanguage, args: (string | number)[] = []): string {
  let translated = language === 'en' ? LEXI_ENGLISH[source] ?? UI_ENGLISH[source] ?? source : source;
  for (let index = 0; index < args.length; index++) {
    translated = translated.split(`{${index}}`).join(String(args[index]));
  }
  return translated;
}

export function formatDateTime(timestamp: number, language: UiLanguage = activeLanguage): string {
  const date = new Date(timestamp);
  const today = new Date();
  const sameDay =
    date.getFullYear() === today.getFullYear() &&
    date.getMonth() === today.getMonth() &&
    date.getDate() === today.getDate();
  const time = `${String(date.getHours()).padStart(2, '0')}:${String(date.getMinutes()).padStart(2, '0')}`;
  if (sameDay) return language === 'en' ? `Today ${time}` : `今天 ${time}`;
  const locale = language === 'en' ? 'en-US' : 'zh-CN';
  return new Intl.DateTimeFormat(locale, { month: 'short', day: 'numeric' }).format(date);
}
