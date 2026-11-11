'use strict';

/**
 * Bundled skills. Skills are prompt fragments the model can load on demand through the
 * `skill` tool. They are plain data: no code, no file access, no network.
 *
 * Ported from the built-in Harness catalogue and trimmed to the Markdown-only surface a
 * plugin actually has (no mind map / canvas / form tools).
 */

const SKILLS = [
  {
    name: 'note-organizer',
    description: '整理单篇笔记：摘要、结构、待办、双链与标签建议',
    whenToUse: '用户要求整理、润色、提炼、拆分或补全一篇笔记时',
    content: [
      '# 笔记整理',
      '',
      '## 步骤',
      '1. 先用 `read_note` 读取原文，不要凭标题猜测内容。',
      '2. 给出 3-6 条要点摘要，保留原文事实，不补充原文没有的信息。',
      '3. 指出结构问题：标题层级、重复段落、过长列表、缺失的结论。',
      '4. 提取未完成任务（`- [ ]`）并整理成可执行行动项。',
      '5. 建议 1-3 条 `[[双链]]`：只能引用 `list_notes` / `search_notes` 里真实存在的笔记。',
      '6. 建议标签时优先复用笔记里已有的标签。',
      '',
      '## 写入规则',
      '- 默认只给建议，不改原文。',
      '- 用户明确说“写回去/应用修改”时才用 `update_note` 或 `append_to_note`。',
      '- 写回前说明改了哪些部分；遇到 `E_CONFLICT` 就重新读取后再写。',
      '- 不删除用户的段落，除非用户明确要求。'
    ].join('\n')
  },
  {
    name: 'daily-review',
    description: '生成今日回顾：今日改动、未完成任务、下一步',
    whenToUse: '用户询问“今天做了什么”“今日回顾”“这周进展”时',
    content: [
      '# 今日回顾',
      '',
      '## 步骤',
      '1. 用 `list_notes` 获取笔记列表，按 mtime 找出今天/本周更新的笔记。',
      '2. 对 3-5 篇最重要的笔记用 `read_note` 读取，提炼进展。',
      '3. 汇总未完成任务（`- [ ]`），按“今天 / 本周 / 稍后”分组。',
      '4. 给出 1-3 个下一步建议，每条都能在 30 分钟内开始。',
      '5. 如果用户要求保存，用 `create_note` 写入 `今日/<日期>.md`（目录必须已存在，否则写根目录）。',
      '',
      '## 约束',
      '- 没有数据的日期不要编造；明确写“没有找到相关记录”。',
      '- 不做价值判断，只陈述笔记里的内容。'
    ].join('\n')
  },
  {
    name: 'knowledge-graph',
    description: '查找相关笔记并补充真实存在的双链',
    whenToUse: '用户要求找关联、建立知识图谱、补充反向链接时',
    content: [
      '# 知识关联',
      '',
      '## 步骤',
      '1. 用 `read_note` 读取目标笔记，提取 3-8 个核心概念。',
      '2. 用 `search_notes` 分别搜索这些概念，记录命中的真实路径。',
      '3. 只保留确实相关的笔记，说明关联理由（共同概念/因果/上下游）。',
      '4. 给出建议插入的双链位置（引用原句或标题）。',
      '5. 用户确认后才写入；写入时保持原有 Markdown 结构。',
      '',
      '## 红线',
      '- 绝不链接不存在的笔记（不要凭想象创建 `[[标题]]`）。',
      '- 不批量改写；一次只处理用户指定的笔记。'
    ].join('\n')
  }
];

function findSkill(name) {
  const target = typeof name === 'string' ? name.trim().toLowerCase() : '';
  return SKILLS.find((skill) => skill.name === target) || null;
}

function catalog() {
  return SKILLS.map((skill) => `- ${skill.name}：${skill.description}`).join('\n');
}

module.exports = { SKILLS, findSkill, catalog };
