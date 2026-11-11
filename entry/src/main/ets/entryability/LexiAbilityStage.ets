import { AbilityStage, Want } from '@kit.AbilityKit';

/** A distinct process keeps AppStorage, editor state, plugins and theme local to each window. */
export default class LexiAbilityStage extends AbilityStage {
  onNewProcessRequest(want: Want): string {
    const requested = want.parameters?.workspaceWindowKey;
    const key = typeof requested === 'string' && /^[a-zA-Z0-9_]{1,100}$/.test(requested) ? requested :
      `document_${Date.now()}_${Math.floor(Math.random() * 1000000)}`;
    return `lexi_${key}`;
  }
}
