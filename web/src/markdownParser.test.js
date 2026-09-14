import {test} from 'node:test';import assert from 'node:assert/strict';
import {markdownHTML,markdownSections} from './markdownParser.js';
test('section rendering preserves reference links, footnotes, tasks, tables and fences',()=>{const content='# First\n\n[Early reference][last]\n\n- [ ] First task\n\n'+Array.from({length:50},(_,i)=>`## Section ${i}\n\nText with **formatting**, [[A note]], and note[^one].\n\n- [x] Task ${i}\n\n| One | Two |\n| --- | --- |\n| a | b |\n\n\`\`\`js\nlet x = ${i};\n\`\`\`\n\n`).join('')+'[last]: https://example.org\n\n[^one]: A footnote after every section.\n';const document=markdownSections(content,1000);assert.ok(document.sections.length>2);const html=document.sections.map((_,i)=>document.render(i)).join('');assert.equal(html,markdownHTML(content));assert.match(html,/href="https:\/\/example.org"/);const tasks=[...html.matchAll(/data-task-source="(\d+)"/g)].map(m=>Number(m[1]));assert.deepEqual(tasks,Array.from({length:51},(_,i)=>i));assert.ok(document.sections.some(s=>s.headings.includes('Section 40')))});

test('multi-megabyte code blocks are bounded without dropping or changing code',()=>{const code=('a'.repeat(30000)+'😀\n').repeat(70),document=markdownSections('```text\n'+code+'```');assert.ok(document.sections.length>100);assert.ok(document.sections.every(s=>s.characters<=16000));const text=document.sections.map((_,i)=>document.render(i).match(/<code[^>]*>([\s\S]*?)<\/code>/)[1]).join('');assert.equal(text,code);assert.equal(document.sections[0].codeSegment,'first');assert.equal(document.sections.at(-1).codeSegment,'last')});

test('chat renders document citations even when a model wraps the reference in inline code',()=>{
 const raw='See `[[Field notes/A note.md]]` and `[[Ideas/Good questions.md|Good questions]]`.';
 const html=markdownHTML(raw,{chat:true});
 assert.equal((html.match(/data-wiki=/g)||[]).length,2);
 assert.match(html,/>A note<\/a>/);assert.match(html,/>Good questions<\/a>/);
 assert.doesNotMatch(html,/<code>/);
 assert.match(markdownHTML(raw),/<code>\[\[Field notes/);
 assert.match(markdownHTML('`const ref = "[[A note]]";`',{chat:true}),/<code>/);
 assert.match(markdownHTML('```md\n[[A note]]\n```',{chat:true}),/<code/);
});
test('chat recovers local document links with spaces and balanced parentheses',()=>{
 for(const path of ['Field notes/A note.md','Books/Some book (2026).pdf','Ideas/A note.md#An idea']){
  const html=markdownHTML(`[Reading](${path})`,{chat:true});
  assert.ok(html.includes(`data-wiki="${path}"`));assert.match(html,/>Reading<\/a>/);
 }
 assert.match(markdownHTML('[Reading](<Field notes/A note.md>)',{chat:true}),/href="Field%20notes\/A%20note.md"/);
 assert.match(markdownHTML('[Web](https://example.org)',{chat:true}),/href="https:\/\/example.org"/);
 assert.doesNotMatch(markdownHTML('[Unsafe](javascript:alert(1) file.md)',{chat:true}),/data-wiki=|href="javascript:/);
 assert.doesNotMatch(markdownHTML('[[A "><img src=x>.md]]',{chat:true}),/<img/);
 assert.match(markdownHTML('[[A note',{chat:true}),/\[\[A note/);
});

test('bare Python filenames and inline code references never become websites',()=>{
 for(const name of ['baseline.py','model.rs','train.sh']){
  const html=markdownHTML(name);assert.match(html,/data-wiki=/);assert.doesNotMatch(html,/href="https?:/);
 }
 for(const name of ['baseline.py','experiments/model.ipynb','../scripts/train.py']){
  assert.ok(markdownHTML('`'+name+'`').includes(`data-wiki="${name}"`));
 }
 assert.match(markdownHTML('https://baseline.py'),/href="https:\/\/baseline.py"/);
 assert.match(markdownHTML('[Website](https://example.org/model.ipynb)'),/href="https:\/\/example.org\/model.ipynb"/);
 assert.doesNotMatch(markdownHTML('`print("model.py")`'),/data-wiki=/);
});
test('notebook paths with spaces, escaped characters, parent folders and wiki aliases stay local',()=>{
 for(const path of ['Notebooks/00 Launch Pad.ipynb','../Notebooks/Modules/V02 - A reproducible Python research laboratory.ipynb','Labs/A study (2026)/baseline.py']){
  const html=markdownHTML(`[Open](${path})`);assert.ok(html.includes(`data-wiki="${path}"`));assert.doesNotMatch(html,/href="https?:/);
 }
 assert.match(markdownHTML('[Open](Notebooks/00%20Launch%20Pad.ipynb)'),/href="Notebooks\/00%20Launch%20Pad.ipynb"/);
 assert.match(markdownHTML('[[Notebooks/00 Launch Pad.ipynb|Open notebook]]'),/data-wiki="Notebooks\/00 Launch Pad.ipynb"/);
});
