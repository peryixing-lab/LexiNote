'use strict';

function serviceHost(baseUrl) {
  const match = /^https?:\/\/([^\s/?#@]+)(?:[/?#]|$)/i.exec(String(baseUrl || '').trim());
  return match ? match[1].toLowerCase().replace(/:\d+$/, '') : '';
}

/** Identify the configured service by its address, never by the model's name. */
function serviceName(status, customName) {
  if (typeof customName === 'string' && customName.trim()) { return customName.trim(); }
  const host = serviceHost(status && status.baseUrl);
  const vendors = [
    ['deepseek.com', 'DeepSeek'], ['openrouter.ai', 'OpenRouter'],
    ['openai.com', 'OpenAI'], ['anthropic.com', 'Anthropic'],
    ['bigmodel.cn', '智谱 GLM'], ['z.ai', 'Z.ai'], ['kimi.com', 'Kimi'],
    ['moonshot.cn', '月之暗面'], ['moonshot.ai', 'Moonshot'],
    ['minimaxi.com', 'MiniMax'], ['minimax.io', 'MiniMax'],
    ['dashscope.aliyuncs.com', '阿里云百炼'], ['generativelanguage.googleapis.com', 'Google Gemini']
  ];
  for (const [domain, label] of vendors) {
    if (host === domain || host.endsWith(`.${domain}`)) { return label; }
  }
  return host || '模型服务';
}

module.exports = { serviceHost, serviceName };
