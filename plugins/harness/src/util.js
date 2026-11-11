'use strict';

/** Small helpers shared by the Harness plugin modules. */

function clip(text, limit) {
  const value = typeof text === 'string' ? text : String(text === undefined || text === null ? '' : text);
  if (!limit || value.length <= limit) {
    return value;
  }
  return `${value.slice(0, limit)}\n…[已截断 ${value.length - limit} 字符]`;
}

function stamp(value) {
  const date = value ? new Date(value) : new Date();
  if (Number.isNaN(date.getTime())) {
    return '';
  }
  const pad = (number) => (number < 10 ? `0${number}` : String(number));
  return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())} ` +
    `${pad(date.getHours())}:${pad(date.getMinutes())}`;
}

function parseJson(text, fallback) {
  if (typeof text !== 'string' || text.length === 0) {
    return fallback;
  }
  try {
    return JSON.parse(text);
  } catch (error) {
    return fallback;
  }
}

function isObject(value) {
  return !!value && typeof value === 'object' && !Array.isArray(value);
}

function text(value) {
  if (typeof value === 'string') {
    return value;
  }
  if (value === undefined || value === null) {
    return '';
  }
  return String(value);
}

function normalizePath(value) {
  return text(value).trim().replace(/\\/g, '/').replace(/^\/+/, '');
}

function basename(path) {
  const value = text(path);
  const slash = value.lastIndexOf('/');
  return slash < 0 ? value : value.slice(slash + 1);
}

function dirname(path) {
  const value = text(path);
  const slash = value.lastIndexOf('/');
  return slash < 0 ? '' : value.slice(0, slash);
}

function errorText(error) {
  if (!error) {
    return '未知错误';
  }
  if (typeof error === 'string') {
    return error;
  }
  const message = typeof error.message === 'string' ? error.message : String(error);
  const code = typeof error.code === 'string' && error.code.length > 0 ? `${error.code}: ` : '';
  return message.indexOf('E_') === 0 ? message : `${code}${message}`;
}

/** One-line argument preview for the chat transcript. */
function previewArguments(name, args) {
  if (name === 'search_notes' || name === 'read_note' || name === 'create_note' ||
      name === 'update_note' || name === 'append_to_note' || name === 'rename_note' ||
      name === 'delete_note' || name === 'open_note') {
    return text(args.path || args.query || '');
  }
  if (name === 'todo_write') {
    const todos = Array.isArray(args.todos) ? args.todos : [];
    return `${todos.length} 项`;
  }
  if (name === 'skill') {
    return text(args.name || '');
  }
  return '';
}

module.exports = {
  clip,
  stamp,
  parseJson,
  isObject,
  text,
  normalizePath,
  basename,
  dirname,
  errorText,
  previewArguments
};
