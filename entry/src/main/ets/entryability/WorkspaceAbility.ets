import { AbilityConstant, Want } from '@kit.AbilityKit';
import EntryAbility from './EntryAbility';
import { LexiStorageService } from '../core/LexiStorageService';

/** Reuse the complete workspace and native window chrome in an isolated process. */
export default class WorkspaceAbility extends EntryAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    const vaultId = want.parameters?.vaultId;
    if (typeof vaultId !== 'string' || !vaultId) { this.context.terminateSelf(); return; }
    LexiStorageService.bindWindowWorkspace(vaultId);
    super.onCreate(want, launchParam);
  }
}
