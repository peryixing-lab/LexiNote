import React from 'react';
import { useStore } from '../store/AppStore';
import { COMMANDS } from '../core/commands';
import { CloseGlyph } from './Symbols';

export function HelpDialog(): JSX.Element {
  const { state, actions, derived } = useStore();
  const { tr } = derived;

  return (
    <div className="overlay dialog-overlay" onPointerDown={(event) => {
      if (event.target === event.currentTarget) actions.setHelpOpen(false);
    }}>
      <div className="dialog help-dialog" role="dialog" aria-modal="true" aria-label={tr('使用帮助')}>
        <div className="dialog-head">
          <div>
            <h2>{tr('使用帮助')}</h2>
            <p>{tr('知萤 LexiNote · Windows 版')}</p>
          </div>
          <button type="button" className="icon-btn tiny" aria-label={tr('关闭')} onClick={() => actions.setHelpOpen(false)}>
            <CloseGlyph size={12} color="var(--text-2)" />
          </button>
        </div>
        <div className="dialog-body help-body">
          <section>
            <h3>{tr('快速开始')}</h3>
            <ol>
              <li>{tr('左侧栏浏览知识库、文件夹与可视化空间；顶部标签页同时打开多篇笔记。')}</li>
              <li>{tr('点击右上角「新建」创建笔记、导图或白板。')}</li>
              <li>{tr('实时预览中点击任意段落就地编辑；「源码」按钮显示完整 Markdown。')}</li>
              <li>{tr('按 Ctrl+P 打开命令面板，Ctrl+O 快速切换文档。')}</li>
              <li>{tr('输入 [[笔记标题]] 建立双向链接，右侧栏会显示出链与反向链接。')}</li>
            </ol>
          </section>

          <section>
            <h3>{tr('快捷键')}</h3>
            <div className="help-kbd-grid">
              {COMMANDS.filter((command) => command.shortcut).map((command) => (
                <React.Fragment key={command.id}>
                  <span>{tr(command.title)}</span>
                  <kbd>{command.shortcut}</kbd>
                </React.Fragment>
              ))}
            </div>
          </section>

          <section>
            <h3>Markdown</h3>
            <table className="help-table">
              <thead>
                <tr>
                  <th>{tr('语法')}</th>
                  <th>{tr('效果')}</th>
                </tr>
              </thead>
              <tbody>
                <tr><td><code># 标题</code></td><td>{tr('一级标题，## 为二级标题')}</td></tr>
                <tr><td><code>**加粗**</code></td><td><strong>加粗</strong></td></tr>
                <tr><td><code>*斜体*</code></td><td><em>斜体</em></td></tr>
                <tr><td><code>==高亮==</code></td><td><mark className="highlight-yellow">高亮</mark></td></tr>
                <tr><td><code>- [ ] 待办</code></td><td>{tr('可点击的待办事项')}</td></tr>
                <tr><td><code>&gt; [!TIP]</code></td><td>{tr('标注块（NOTE / TIP / WARNING）')}</td></tr>
                <tr><td><code>$E=mc^2$</code></td><td>{tr('行内公式（KaTeX 离线排版）')}</td></tr>
                <tr><td><code>$$\int_0^1 x^2 dx$$</code></td><td>{tr('块级公式')}</td></tr>
                <tr><td><code>[[笔记标题]]</code></td><td>{tr('双向链接，可带 #标题 定位')}</td></tr>
                <tr><td><code>```typescript</code></td><td>{tr('代码块，带语法高亮')}</td></tr>
                <tr><td><code>| 列 | 列 |</code></td><td>{tr('表格')}</td></tr>
              </tbody>
            </table>
          </section>

          <section>
            <h3>{tr('Windows 版与鸿蒙版的差异')}</h3>
            <table className="help-table">
              <thead>
                <tr>
                  <th>{tr('鸿蒙能力')}</th>
                  <th>{tr('Windows 实现')}</th>
                </tr>
              </thead>
              <tbody>
                <tr><td>{tr('HDS 沉浸光感 / 液态玻璃材质')}</td><td>{tr('替换为纯色与半透明普通材质，无模糊与镜面反射')}</td></tr>
                <tr><td>{tr('系统分享剪藏')}</td><td>{tr('导入 Markdown 文件，或从剪贴板粘贴')}</td></tr>
                <tr><td>{tr('桌面服务卡片')}</td><td>{tr('暂未提供，可用快速笔记与今日笔记代替')}</td></tr>
                <tr><td>{tr('离线语音识别')}</td><td>{tr('使用系统语音输入（Win+H）')}</td></tr>
                <tr><td>{tr('ArkWeb 插件运行时')}</td><td>{tr('尚未移植，设置中保留插件说明')}</td></tr>
                <tr><td>{tr('多窗口与跨设备接续')}</td><td>{tr('单窗口标签页；数据保存在本机')}</td></tr>
              </tbody>
            </table>
          </section>

          <section>
            <h3>{tr('数据与备份')}</h3>
            <p>
              {tr(
                '笔记与导图以 JSON 保存在本机数据目录，随时可以在「设置 → 文件与链接」导出工作区 Markdown 或完整备份。'
              )}
            </p>
            <p className="mono help-path">{state.runtime?.dataPath ?? ''}</p>
          </section>
        </div>
        <div className="dialog-foot">
          <span className="foot-hint">GPL-3.0 · 知萤 LexiNote</span>
          <button type="button" className="primary-btn" onClick={() => actions.setHelpOpen(false)}>
            {tr('知道了')}
          </button>
        </div>
      </div>
    </div>
  );
}
