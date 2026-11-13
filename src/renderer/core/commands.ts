export interface CommandDef {
  id: string;
  title: string;
  group: string;
  hint?: string;
  shortcut?: string;
}

/** Command catalog used by the desktop ribbon, palette and settings. */
export const COMMANDS: CommandDef[] = [
  { id: 'palette', title: '打开命令面板', group: '基本', shortcut: 'Ctrl+P' },
  { id: 'switcher', title: '快速切换文档', group: '基本', shortcut: 'Ctrl+O' },
  { id: 'save', title: '保存当前文件', group: '基本', shortcut: 'Ctrl+S' },
  { id: 'new', title: '新建 Markdown 笔记', group: '基本', shortcut: 'Ctrl+N' },
  { id: 'quick', title: '新建快速笔记', group: '基本', shortcut: 'Ctrl+Shift+N' },
  { id: 'study', title: '新建学习笔记', group: '基本' },
  { id: 'daily', title: '打开今日笔记', group: '基本' },
  { id: 'templates', title: '从模板新建笔记', group: '基本' },
  { id: 'save-template', title: '将当前笔记保存为模板', group: '基本' },
  { id: 'split', title: '在右侧分屏打开当前文档', group: '基本' },
  { id: 'close-split', title: '关闭右侧分屏', group: '基本' },
  { id: 'sidebar', title: '显示或隐藏侧边栏', group: '基本', shortcut: 'Ctrl+\\' },
  { id: 'close-tab', title: '保存并关闭当前标签', group: '基本', shortcut: 'Ctrl+W' },
  { id: 'tab-prev', title: '转到上一个标签页', group: '基本', shortcut: 'Ctrl+Shift+Tab' },
  { id: 'tab-next', title: '转到下一个标签页', group: '基本', shortcut: 'Ctrl+Tab' },
  { id: 'map', title: '新建思维导图', group: '可视化' },
  { id: 'canvas', title: '新建白板', group: '可视化' },
  { id: 'convert', title: '将当前笔记转为思维导图', group: '可视化' },
  { id: 'graph', title: '打开笔记关联', group: '可视化' },
  { id: 'library', title: '打开文档管理', group: '可视化' },
  { id: 'workspaces', title: '管理工作区与项目', group: '工作区' },
  { id: 'trash', title: '打开回收站', group: '工作区' },
  { id: 'light', title: '使用浅色外观', group: '外观' },
  { id: 'dark', title: '使用深色外观', group: '外观' },
  { id: 'system', title: '跟随系统外观', group: '外观' },
  { id: 'theme-picker', title: '选择主题色', group: '外观' },
  { id: 'zoom-in', title: '放大界面', group: '外观', shortcut: 'Ctrl+=' },
  { id: 'zoom-out', title: '缩小界面', group: '外观', shortcut: 'Ctrl+-' },
  { id: 'zoom-reset', title: '重置界面缩放', group: '外观', shortcut: 'Ctrl+0' },
  { id: 'font-increase', title: '增大正文字号', group: '外观' },
  { id: 'font-decrease', title: '减小正文字号', group: '外观' },
  { id: 'width-toggle', title: '切换正文限宽', group: '外观' },
  { id: 'ribbon-toggle', title: '显示或隐藏功能区', group: '外观' },
  { id: 'reading', title: '切换编辑与阅读', group: '编辑器', shortcut: 'Ctrl+E' },
  { id: 'source-toggle', title: '切换源码 / 实时预览', group: '编辑器' },
  { id: 'editor-bold', title: '加粗 / 取消加粗', group: '编辑器', shortcut: 'Ctrl+B' },
  { id: 'editor-italic', title: '倾斜 / 取消倾斜', group: '编辑器', shortcut: 'Ctrl+I' },
  { id: 'editor-strike', title: '添加删除线', group: '编辑器' },
  { id: 'editor-highlight', title: '高亮', group: '编辑器' },
  { id: 'editor-h1', title: '设为小标题 1', group: '编辑器' },
  { id: 'editor-h2', title: '设为小标题 2', group: '编辑器' },
  { id: 'editor-todo', title: '插入待办事项', group: '编辑器' },
  { id: 'editor-hr', title: '插入分隔线', group: '编辑器' },
  { id: 'editor-table', title: '插入表格', group: '编辑器' },
  { id: 'editor-code', title: '插入代码块', group: '编辑器' },
  { id: 'editor-formula', title: '插入数学块', group: '编辑器' },
  { id: 'editor-callout', title: '插入标注', group: '编辑器' },
  { id: 'find', title: '在当前笔记中查找', group: '编辑器', shortcut: 'Ctrl+F' },
  { id: 'replace', title: '在当前笔记中查找并替换', group: '编辑器', shortcut: 'Ctrl+H' },
  { id: 'focus-editor', title: '将焦点切换至编辑区', group: '编辑器' },
  { id: 'outline', title: '大纲：打开当前文件的大纲', group: '编辑器' },
  { id: 'backlinks', title: '反向链接：显示反向链接列表', group: '编辑器' },
  { id: 'outgoing', title: '出链：显示出链列表', group: '编辑器' },
  { id: 'properties', title: '属性列表：显示当前笔记的属性', group: '编辑器' },
  { id: 'rename', title: '编辑文件名', group: '文件', shortcut: 'F2' },
  { id: 'duplicate', title: '复制当前文件', group: '文件' },
  { id: 'copy-uri', title: '复制知萤 URI', group: '文件' },
  { id: 'copy-path', title: '复制当前文件路径', group: '文件' },
  { id: 'delete-file', title: '删除当前文件', group: '文件' },
  { id: 'move-file', title: '将文件移动到其他文件夹', group: '文件' },
  { id: 'export-md', title: '导出工作区 Markdown', group: '数据' },
  { id: 'backup', title: '导出完整备份', group: '数据' },
  { id: 'restore', title: '从备份恢复', group: '数据' },
  { id: 'import', title: '导入文件', group: '数据' },
  { id: 'export-pdf', title: '导出为 PDF', group: '数据' },
  { id: 'back', title: '返回', group: '导航', shortcut: 'Alt+←' },
  { id: 'forward', title: '前进', group: '导航', shortcut: 'Alt+→' },
  { id: 'settings', title: '打开设置', group: '帮助', shortcut: 'Ctrl+,' },
  { id: 'help', title: '打开使用说明', group: '帮助', shortcut: 'F1' },
  { id: 'about', title: '关于知萤 LexiNote', group: '帮助' }
];

export const COMMAND_MAP: Map<string, CommandDef> = new Map(COMMANDS.map((command) => [command.id, command]));

export const DEFAULT_HOTKEYS: Record<string, string> = COMMANDS.reduce<Record<string, string>>((acc, command) => {
  if (command.shortcut) acc[command.id] = command.shortcut;
  return acc;
}, {});

export const RIBBON_COMMANDS = ['vault', 'switcher', 'commands', 'reading', 'graph'] as const;

export interface EditorCommandPreset {
  prefix: string;
  suffix: string;
  linePrefix?: string;
}

export const INLINE_FORMATS: Record<string, EditorCommandPreset> = {
  'editor-bold': { prefix: '**', suffix: '**' },
  'editor-italic': { prefix: '*', suffix: '*' },
  'editor-strike': { prefix: '~~', suffix: '~~' },
  'editor-highlight': { prefix: '==', suffix: '==' }
};
