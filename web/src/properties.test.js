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
test('editing one property leaves the source text of every other property alone', () => {
  const original = '---\n# keep this comment\nid: 007\nversion: 1.10\nserial: 12345678901234567890\ntitle: "Quoted: title"\nstatus: draft\n---\n\nBody.\n';
  const {properties} = frontmatter(original);
  const updated = updateProperties(original, {...properties, status: 'done'});
  assert.equal(updated, original.replace('status: draft', 'status: done'));
  const added = updateProperties(original, {...properties, reviewed: true});
  assert.ok(added.includes('id: 007\nversion: 1.10\nserial: 12345678901234567890\ntitle: "Quoted: title"\nstatus: draft\nreviewed: true\n---'));
  const {status, ...rest} = properties;
  assert.equal(updateProperties(original, rest), original.replace('status: draft\n', ''));
});
test('a note without frontmatter gains one when its first property is added', () => {
  assert.equal(updateProperties('# Note\n', {status: 'draft'}), '---\nstatus: draft\n---\n\n# Note\n');
});
test('multi-line values, trailing comments and empty values are replaced or removed whole', () => {
  const original = '---\ntags:\n  - one\n  - two\n# about the title\ntitle: Old # inline note\nempty:\nnested:\n  a: 1\n  b: [x, y]\nlast: 1\n---\n\nBody.\n';
  const {properties} = frontmatter(original);
  assert.equal(updateProperties(original, {...properties, tags: ['three']}), original.replace('tags:\n  - one\n  - two\n', 'tags:\n  - three\n'));
  assert.equal(updateProperties(original, {...properties, title: 'New'}), original.replace('title: Old # inline note\n', 'title: New\n'));
  assert.equal(updateProperties(original, {...properties, empty: 'filled'}), original.replace('empty:\n', 'empty: filled\n'));
  const {nested, ...withoutNested} = properties;
  assert.equal(updateProperties(original, withoutNested), original.replace('nested:\n  a: 1\n  b: [x, y]\n', ''));
  assert.deepEqual(frontmatter(updateProperties(original, {...properties, last: 2})).properties, {...properties, last: 2});
});
test('flow-style frontmatter is still editable', () => {
  const updated = updateProperties('---\n{a: 1, b: 2}\n---\n\nBody.\n', {a: 1, b: 3});
  assert.deepEqual(frontmatter(updated).properties, {a: 1, b: 3});
  assert.equal(frontmatter(updated).body, '\nBody.\n');
});
test('an undefined value removes the property rather than writing a placeholder', () => {
  assert.equal(updateProperties('---\na: 1\nb: 2\n---\n\nBody\n', {a: 1, b: undefined}), '---\na: 1\n---\n\nBody\n');
  assert.equal(updateProperties('---\na: 1\n---\n\nBody\n', {a: 1, c: undefined}), '---\na: 1\n---\n\nBody\n');
});
