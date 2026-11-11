/**
 * Type declarations for the supported Obsidian compatibility subset.
 * See README.md for the exact differences from upstream Obsidian.
 */

export interface EditorPosition {
  line: number;
  ch: number;
}

export interface FileStat {
  ctime: number;
  mtime: number;
  size: number;
}

export interface HeadingCache {
  heading: string;
  level: number;
}

export interface LinkCache {
  link: string;
  original: string;
  displayText: string;
}

export interface TagCache {
  tag: string;
}

export interface CachedMetadata {
  headings: HeadingCache[];
  links: LinkCache[];
  tags: TagCache[];
}

export class EventRef {
  readonly name: string;
  off(): void;
}

export class Events {
  on(name: string, callback: (...args: unknown[]) => void): EventRef;
  off(name: string, callback: (...args: unknown[]) => void): void;
  offref(ref: EventRef): void;
  trigger(name: string, ...args: unknown[]): number;
}

export class TAbstractFile {
  path: string;
  name: string;
  parent: TFolder | null;
  vault: Vault;
}

export class TFile extends TAbstractFile {
  basename: string;
  extension: string;
  stat: FileStat;
}

export class TFolder extends TAbstractFile {
  children: Array<TFile | TFolder>;
  isRoot(): boolean;
}

export class Vault {
  readonly name: string;
  /** Throws E_UNSUPPORTED_API: no filesystem adapter exists in the runtime. */
  readonly adapter: never;
  getRoot(): TFolder;
  getFiles(): Array<TFile | TFolder>;
  getAllLoadedFiles(): Array<TFile | TFolder>;
  getMarkdownFiles(): TFile[];
  getAbstractFileByPath(path: string): TFile | TFolder | null;
  read(file: TFile): Promise<string>;
  cachedRead(file: TFile): Promise<string>;
  create(path: string, data: string): Promise<TFile>;
  modify(file: TFile, data: string): Promise<void>;
  append(file: TFile, data: string): Promise<void>;
  /** Soft delete: the note goes to the LexiNote recycle bin. */
  delete(file: TFile, force?: boolean): Promise<void>;
  rename(file: TFile, newPath: string): Promise<TFile>;
  on(name: 'create' | 'modify' | 'rename' | 'delete' | string, callback: (...args: unknown[]) => void): EventRef;
  off(name: string, callback: (...args: unknown[]) => void): void;
  offref(ref: EventRef): void;
}

export class MetadataCache {
  getFileCache(file: TFile): CachedMetadata | null;
  getCache(path: string): CachedMetadata | null;
  getFirstLinkpathDest(linkpath: string, sourcePath: string): TFile | null;
}

export class Editor {
  file: TFile | null;
  getValue(): string;
  getCursor(which?: 'from' | 'anchor' | 'head'): EditorPosition;
  getSelection(): { anchor: EditorPosition; head: EditorPosition };
  setSelection(anchor: EditorPosition, head: EditorPosition): void;
  replaceSelection(text: string): Promise<void>;
  replaceRange(text: string, from: EditorPosition | number, to: EditorPosition | number): Promise<void>;
  setValue(value: string): Promise<void>;
  getLine(line: number): string;
  lineCount(): number;
  posToOffset(position: EditorPosition): number;
  offsetToPos(offset: number): EditorPosition;
}

export class WorkspaceLeaf {
  view: ItemView | null;
  setViewState(state: { type: string; active?: boolean }): Promise<void>;
  getViewState(): { type: string; active: boolean };
  detach(): Promise<void>;
  viewType: string;
}

export class ItemView extends Component {
  constructor(leaf: WorkspaceLeaf);
  readonly app: App;
  readonly leaf: WorkspaceLeaf;
  containerEl: HTMLElement | null;
  contentEl: HTMLElement;
  getViewType(): string;
  getDisplayText(): string;
}

export class MarkdownView extends ItemView {
  file: TFile | null;
  editor: Editor | null;
}

export class Workspace {
  readonly activeEditor: MarkdownView | null;
  readonly activeLeaf: WorkspaceLeaf | null;
  getActiveFile(): TFile | null;
  getActiveViewOfType<T extends ItemView>(type: new (...args: never[]) => T): T | null;
  openLinkText(linkpath: string, sourcePath: string): Promise<void>;
  getLeavesOfType(type: string): WorkspaceLeaf[];
  getRightLeaf(split?: boolean): WorkspaceLeaf;
  getLeftLeaf(split?: boolean): WorkspaceLeaf;
  getLeaf(): WorkspaceLeaf;
  readonly layoutReady: boolean;
  onLayoutReady(callback: () => void): void;
  revealLeaf(leaf: WorkspaceLeaf): Promise<void>;
  detachLeavesOfType(type: string): Promise<void[]>;
  on(name: 'file-open' | 'active-leaf-change' | string, callback: (...args: unknown[]) => void): EventRef;
}

export class Component {
  registerEvent(ref: EventRef): EventRef;
  registerInterval(id: number): number;
  registerDomEvent(el: { addEventListener: Function; removeEventListener: Function }, type: string, callback: (...args: unknown[]) => void, options?: unknown): void;
  addChild<T extends Component>(child: T): T;
  removeChild<T extends Component>(child: T): T;
  load(): Promise<void>;
  unload(): Promise<void>;
  onload(): void | Promise<void>;
  onunload(): void | Promise<void>;
}

export interface Command {
  id: string;
  name?: string;
  callback?: () => unknown;
  editorCallback?: (editor: Editor | null) => unknown;
  checkCallback?: (checking: boolean) => boolean | void;
}

export interface PluginManifest {
  id: string;
  name: string;
  version: string;
  minAppVersion: string;
  description: string;
  author: string;
  isDesktopOnly: boolean;
}

export class Plugin extends Component {
  readonly app: App;
  readonly manifest: PluginManifest;
  onload(): void | Promise<void>;
  onunload(): void | Promise<void>;
  loadData(): Promise<unknown>;
  saveData(data: unknown): Promise<void>;
  addCommand(command: Command): { dispose(): void };
  addRibbonIcon(icon: string, title: string, callback: (event?: MouseEvent) => void): HTMLElement;
  addStatusBarItem(): HTMLElement;
  addSettingTab(tab: PluginSettingTab): void;
  registerView(type: string, factory: (leaf: WorkspaceLeaf) => ItemView): void;
  registerMarkdownPostProcessor(): never;
  registerEditorExtension(): never;
}

export class Notice {
  constructor(message: string, timeout?: number);
  hide(): void;
}

/** DOM surfaces are available in the desktop runtime, and reject headless use. */
export class Modal {
  constructor(app?: App);
  contentEl: HTMLElement;
  titleEl: HTMLElement;
  setTitle(text: string): this;
  setContent(text: string): this;
  open(): void;
  close(): void;
  onOpen(): void;
  onClose(): void;
}

export class PluginSettingTab {
  constructor(app: App, plugin: Plugin);
  app: App;
  plugin: Plugin;
  containerEl: HTMLElement;
  display(): void | Promise<void>;
  hide(): void;
}

export interface LexiSettingControl {
  inputEl: HTMLInputElement | HTMLSelectElement | HTMLButtonElement | HTMLTextAreaElement;
  setValue(value: string | boolean | number): this;
  setPlaceholder(text: string): this;
  setDisabled(disabled: boolean): this;
  setButtonText(text: string): this;
  setCta(): this;
  setWarning(): this;
  setTooltip(text: string): this;
  onClick(callback: (event: MouseEvent) => void): this;
  onChange(callback: (value: string | boolean) => void): this;
  addOption(value: string, label: string): this;
  addOptions(options: Record<string, string>): this;
  setLimits(min: number, max: number, step: number): this;
  setDynamicTooltip(): this;
}

export class Setting {
  constructor(containerEl: HTMLElement);
  settingEl: HTMLElement;
  controlEl: HTMLElement;
  setName(text: string): this;
  setDesc(text: string | DocumentFragment): this;
  setHeading(): this;
  setClass(name: string): this;
  setDisabled(disabled: boolean): this;
  addText(callback: (control: LexiSettingControl) => void): this;
  addTextArea(callback: (control: LexiSettingControl) => void): this;
  addToggle(callback: (control: LexiSettingControl) => void): this;
  addDropdown(callback: (control: LexiSettingControl) => void): this;
  addButton(callback: (control: LexiSettingControl) => void): this;
  addSlider(callback: (control: LexiSettingControl) => void): this;
}

export interface App {
  readonly vault: Vault;
  readonly workspace: Workspace;
  readonly metadataCache: MetadataCache;
}

export const Platform: Readonly<{
  isDesktopApp: false;
  isMobile: true;
  isAndroidApp: false;
  isIosApp: false;
  isMacOS: false;
  isWin: false;
  isLinux: false;
  isPhone: true;
  isTablet: false;
  isDesktop: false;
  isHarmonyOS: true;
}>;

export function normalizePath(path: string): string;

/** Throws E_UNSUPPORTED_API: plugins have no network access. */
export function requestUrl(...args: never[]): never;
