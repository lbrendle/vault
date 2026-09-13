import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import postcss from 'postcss';
test('every shipped stylesheet has valid, nonempty selectors',()=>{
 for(const file of ['style.css','product.css','workspace.css','glass.css','reader.css']) {
  const root=postcss.parse(fs.readFileSync(new URL(file,import.meta.url),'utf8'));
  root.walkRules(rule=>assert.ok(rule.selector?.trim(),`${file}: selectorless CSS rule`));
 }
});
