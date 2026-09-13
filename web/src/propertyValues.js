import {parse, stringify} from 'yaml';

export const isTagProperty = key => ['tags', 'tag'].includes(key.toLowerCase());

export function propertyTags(value) {
  const values = Array.isArray(value) ? value : [value];
  return [...new Set(values.flatMap(item => typeof item === 'string'
    ? item.split(/[\s,]+/).map(tag => tag.replace(/^#+/, '').trim()).filter(Boolean)
    : typeof item === 'number' ? [String(item)] : []))];
}

export function propertyText(value) {
  if (value == null) return '';
  if (typeof value === 'object') return stringify(value).trimEnd();
  return String(value);
}

export function propertyDraft(key, value) {
  return isTagProperty(key) ? propertyTags(value).join(', ') : propertyText(value);
}

export function parsePropertyDraft(key, draft, previous) {
  if (isTagProperty(key)) {
    // Accept both an ordinary comma-separated edit and pasted YAML lists.
    const text = draft.trim();
    if (text.startsWith('[') || /^-\s/.test(text)) {
      const values = parse(text);
      if (!Array.isArray(values) || values.some(v => !['string', 'number'].includes(typeof v))) {
        throw new Error('Enter tags separated by commas, or a list of tag names.');
      }
      return propertyTags(values);
    }
    return propertyTags(text);
  }
  // Text properties such as "001" and "false" must remain text when edited.
  return typeof previous === 'string' ? draft : parse(draft);
}
