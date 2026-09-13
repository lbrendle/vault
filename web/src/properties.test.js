import {test} from 'node:test';
import assert from 'node:assert/strict';
import {frontmatter, updateProperties} from './markdownParser.js';
import {propertyTags, propertyDraft, parsePropertyDraft} from './propertyValues.js';

test('YAML tags display consistently as unique names, including nested and Unicode tags', () => {
  for (const source of ['tags: [research, "#ideas", research/memory, café, research]', 'tags:\n  - research\n  - "#ideas"\n  - research/memory\n  - café\n  - research', 'tags: "research, #ideas research/memory café research"']) {
    const {properties} = frontmatter('---\n' + source + '\n---\nBody');
    assert.deepEqual(propertyTags(properties.tags), ['research', 'ideas', 'research/memory', 'café']);
  }
});
test('editing tags saves real YAML arrays without changing body or unrelated properties', () => {
  const original = '---\ntags: [one]\ncode: "001"\n---\n\n# Note\n\nText.\n';
  const {properties, body} = frontmatter(original);
  properties.tags = parsePropertyDraft('tags', '#one, ideas/memory, café, one', properties.tags);
  const updated = frontmatter(updateProperties(original, properties));
  assert.deepEqual(updated.properties, {tags: ['one','ideas/memory','café'], code:'001'});
  assert.equal(updated.body, body);
  assert.equal(propertyDraft('tags', properties.tags), 'one, ideas/memory, café');
  assert.deepEqual(parsePropertyDraft('tags', '[one, two]', []), ['one', 'two']);
  assert.throws(() => parsePropertyDraft('tags', '[{wrong: value}]', []));
  assert.equal(parsePropertyDraft('code', '001', 'old'), '001');
});
