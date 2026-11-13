import React, { useEffect, useMemo, useState } from 'react';
import { useStore } from '../store/AppStore';
import { Icon } from './Icon';
import { CloseGlyph } from './Symbols';

interface Template {
  id: string;
  title: string;
  description: string;
  notebook: string;
  type: 'markdown' | 'study' | 'quick';
  content: string;
}

function todayKey(): string {
  const date = new Date();
  return `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, '0')}-${String(date.getDate()).padStart(2, '0')}`;
}

function buildTemplates(): Template[] {
  return [
    {
      id: 'blank',
      title: '空白笔记',
      description: '从一张白纸开始，支持 Markdown 与双向链接。',
      notebook: '笔记',
      type: 'markdown',
      content: '# 无标题笔记\n\n'
    },
    {
      id: 'daily',
      title: '每日笔记',
      description: '记录今天做了什么、学到什么，以及明天的重点。',
      notebook: '日记',
      type: 'markdown',
      content: `# ${todayKey()}\n\n## 今天做了什么\n\n- \n\n## 学到什么\n\n- \n\n## 明天的重点\n\n- [ ] \n\n## 随手记录\n\n`
    },
    {
      id: 'meeting',
      title: '会议记录',
      description: '参会人、议题、结论与行动项，一目了然。',
      notebook: '工作',
      type: 'markdown',
      content: `# 会议记录 · ${todayKey()}\n\n## 会议信息\n\n- 时间：\n- 参会人：\n- 主持人：\n\n## 议题\n\n1. \n\n## 讨论要点\n\n- \n\n## 结论\n\n> \n\n## 行动项\n\n- [ ] @负责人 · 截止日期\n`
    },
    {
      id: 'reading',
      title: '读书笔记',
      description: '书名、核心观点、摘录与行动，把书读成自己的知识。',
      notebook: '阅读',
      type: 'markdown',
      content: `# 《书名》读书笔记\n\n- 作者：\n- 读完日期：${todayKey()}\n- 评分：★★★★☆\n\n## 一句话总结\n\n> \n\n## 核心观点\n\n1. \n\n## 原文摘录\n\n> \n\n## 我的思考\n\n\n\n## 行动清单\n\n- [ ] \n`
    },
    {
      id: 'project',
      title: '项目计划',
      description: '目标、范围、里程碑与风险，用清单推进。',
      notebook: '工作',
      type: 'markdown',
      content: `# 项目名称\n\n## 目标\n\n\n\n## 范围\n\n- 包含：\n- 不包含：\n\n## 里程碑\n\n| 阶段 | 产出 | 截止 |\n| --- | --- | --- |\n| 设计 | | |\n| 开发 | | |\n| 验收 | | |\n\n## 风险与依赖\n\n- \n\n## 待办\n\n- [ ] \n`
    },
    {
      id: 'study',
      title: '学习笔记',
      description: '学习目标、核心概念、例题与自测清单。',
      notebook: '计算机课程',
      type: 'study',
      content: `# 学习笔记 · 主题\n\n## 学习目标\n\n- \n\n## 核心概念\n\n\n\n## 例题与推导\n\n$$\n\n$$\n\n## 自测清单\n\n- [ ] 能用自己的话解释\n- [ ] 能独立推导\n- [ ] 能联系到已有知识 [[相关笔记]]\n`
    },
    {
      id: 'review',
      title: '每周复盘',
      description: '回顾本周成果、问题与下周计划。',
      notebook: '日记',
      type: 'markdown',
      content: `# 每周复盘 · ${todayKey()}\n\n## 本周成果\n\n- \n\n## 遇到的问题\n\n- \n\n## 收获与改进\n\n> \n\n## 下周计划\n\n- [ ] \n`
    }
  ];
}

export function TemplateDialog(): JSX.Element {
  const { actions, derived } = useStore();
  const { tr } = derived;
  const [saved, setSaved] = useState<{ title: string; content: string }[]>([]);

  useEffect(() => {
    try {
      const raw = localStorage.getItem('lexinote-templates');
      setSaved(raw ? (JSON.parse(raw) as { title: string; content: string }[]) : []);
    } catch {
      setSaved([]);
    }
  }, []);

  const templates = useMemo(() => buildTemplates(), []);

  const create = (template: Template): void => {
    const id = actions.createNote(template.type, template.title === '每日笔记' ? `每日笔记 ${todayKey()}` : template.title);
    actions.updateNote(id, { content: template.content, notebook: template.notebook });
    actions.setTemplatesOpen(false);
  };

  const createSaved = (template: { title: string; content: string }): void => {
    const id = actions.createNote('markdown', template.title);
    actions.updateNote(id, { content: template.content, notebook: '模板' });
    actions.setTemplatesOpen(false);
  };

  return (
    <div className="overlay dialog-overlay" onPointerDown={(event) => {
      if (event.target === event.currentTarget) actions.setTemplatesOpen(false);
    }}>
      <div className="dialog template-dialog" role="dialog" aria-modal="true" aria-label={tr('从模板新建笔记')}>
        <div className="dialog-head">
          <div>
            <h2>{tr('从模板新建笔记')}</h2>
            <p>{tr('模板会在当前工作区创建一篇新笔记，不会修改模板本身。')}</p>
          </div>
          <button type="button" className="icon-btn tiny" aria-label={tr('关闭')} onClick={() => actions.setTemplatesOpen(false)}>
            <CloseGlyph size={12} color="var(--text-2)" />
          </button>
        </div>
        <div className="dialog-body template-body">
          <div className="template-grid">
            {templates.map((template) => (
              <button key={template.id} type="button" className="template-card" onClick={() => create(template)}>
                <Icon name={template.type === 'study' ? 'study' : 'note'} size={18} />
                <strong>{tr(template.title)}</strong>
                <span>{tr(template.description)}</span>
                <small>{tr('文件夹：{0}', [tr(template.notebook)])}</small>
              </button>
            ))}
          </div>
          {saved.length > 0 ? (
            <>
              <h3 className="template-subtitle">{tr('我保存的模板')}</h3>
              <div className="template-grid">
                {saved.map((template, index) => (
                  <button
                    key={`${template.title}-${index}`}
                    type="button"
                    className="template-card saved"
                    onClick={() => createSaved(template)}
                  >
                    <Icon name="star" size={18} />
                    <strong>{template.title}</strong>
                    <span>{template.content.split('\n').slice(0, 2).join(' ')}</span>
                    <small>{tr('来自「将当前笔记保存为模板」')}</small>
                  </button>
                ))}
              </div>
            </>
          ) : null}
        </div>
        <div className="dialog-foot">
          <span className="foot-hint">{tr('你可以在命令面板中把当前笔记保存为模板。')}</span>
          <button type="button" className="small-btn" onClick={() => actions.setTemplatesOpen(false)}>
            {tr('取消')}
          </button>
        </div>
      </div>
    </div>
  );
}
