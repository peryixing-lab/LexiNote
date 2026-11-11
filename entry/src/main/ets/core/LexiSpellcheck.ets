import { util } from '@kit.ArkTS';
import { common } from '@kit.AbilityKit';

export class LexiSpellingIssue {
  word: string = '';
  suggestions: string[] = [];
}
/** Offline English dictionary; note contents never leave the device. */
export class LexiSpellcheck {
  private static dictionary: Set<string> = new Set<string>();
  static async check(context: common.UIAbilityContext, text: string): Promise<LexiSpellingIssue[]> {
    if (LexiSpellcheck.dictionary.size === 0) {
      const bytes = await context.resourceManager.getRawFileContent('lexinote_spell_en.txt');
      const raw = util.TextDecoder.create('utf-8').decodeToString(bytes);
      LexiSpellcheck.dictionary = new Set<string>(raw.toLowerCase().split(/\r?\n/));
    }
    const seen = new Set<string>(); const result: LexiSpellingIssue[] = [];
    const words = text.replace(/```[\s\S]*?```|`[^`]*`|https?:\/\/\S+/g, ' ').match(/[A-Za-z]{3,}/g) || [];
    for (const word of words) {
      const key = word.toLowerCase();
      if (seen.has(key) || LexiSpellcheck.dictionary.has(key) || /^[A-Z]+$/.test(word)) { continue; }
      seen.add(key); const issue = new LexiSpellingIssue(); issue.word = word;
      for (let i = 0; i + 1 < key.length && issue.suggestions.length < 5; i++) {
        const swapped = key.substring(0, i) + key[i + 1] + key[i] + key.substring(i + 2);
        if (LexiSpellcheck.dictionary.has(swapped) && !issue.suggestions.includes(swapped)) { issue.suggestions.push(swapped); }
      }
      for (let i = 0; i <= key.length && issue.suggestions.length < 5; i++) {
        const removed = key.substring(0, i) + key.substring(i + 1);
        if (LexiSpellcheck.dictionary.has(removed) && !issue.suggestions.includes(removed)) { issue.suggestions.push(removed); }
        for (const character of 'abcdefghijklmnopqrstuvwxyz') {
          const replaced = key.substring(0, i) + character + key.substring(i + 1);
          if (LexiSpellcheck.dictionary.has(replaced) && !issue.suggestions.includes(replaced)) { issue.suggestions.push(replaced); }
          const inserted = key.substring(0, i) + character + key.substring(i);
          if (LexiSpellcheck.dictionary.has(inserted) && !issue.suggestions.includes(inserted)) { issue.suggestions.push(inserted); }
          if (issue.suggestions.length >= 5) { break; }
        }
      }
      result.push(issue); if (result.length >= 40) { break; }
    }
    return result;
  }
}
