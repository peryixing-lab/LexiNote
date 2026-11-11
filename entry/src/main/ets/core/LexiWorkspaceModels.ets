import { NoteLink, NoteProperty, OutlineHeading } from './LexiModels';

export class LexiWorkspaceInspectorSnapshot {
  noteId: string = '';
  title: string = '';
  headings: OutlineHeading[] = [];
  outgoing: NoteLink[] = [];
  backlinks: NoteLink[] = [];
  properties: NoteProperty[] = [];
}

export class LexiWorkspaceSelection { start: number = 0; end: number = 0; }
// Each open document owns its editor and save boundary. Switching tabs never reloads a draft.
export class LexiWorkspaceEditorController {
  ownerId: string = '';
  flush: () => Promise<void> = async (): Promise<void> => {};
  toggleReading: () => void = (): void => {};
  format: (action: string) => void = (_action: string): void => {};
  selection: () => string = (): string => '';
  selectionRange: () => LexiWorkspaceSelection = (): LexiWorkspaceSelection => new LexiWorkspaceSelection();
  focus: () => void = (): void => {};
  inspectorSnapshot: () => LexiWorkspaceInspectorSnapshot = (): LexiWorkspaceInspectorSnapshot => new LexiWorkspaceInspectorSnapshot();
  revealHeading: (heading: OutlineHeading) => void = (_heading: OutlineHeading): void => {};
  openTarget: (target: string) => Promise<void> = async (_target: string): Promise<void> => {};
}

export class LexiWorkspaceTab {
  noteId: string;
  controller: LexiWorkspaceEditorController = new LexiWorkspaceEditorController();

  constructor(noteId: string) {
    this.noteId = noteId;
  }
}
