// Deliberately interpreted expressions: vault files never become JavaScript code.
import {parse} from 'yaml';
export function parseBase(text){const data=parse(text);if(!data||typeof data!=='object')throw new Error('Invalid Base YAML');return data}
export function property(row,name){name=name.replace(/^note\./,'');if(name==='file.name')return row.title;if(name==='file.path')return row.path;if(name==='file.ext')return row.ext;if(name==='file.size')return row.size;if(name==='file.mtime')return new Date(row.modified*1000);return row.properties?.[name]??null}
function value(raw,row){raw=raw.trim();if(raw==='null')return null;if(raw==='true')return true;if(raw==='false')return false;if(raw==='today()'){const d=new Date();d.setHours(0,0,0,0);return d.getTime()}const date=/^date\((.*)\)$/.exec(raw);if(date){const v=value(date[1],row);return v==null?null:new Date(v).getTime()}if(/^(["']).*\1$/.test(raw))return raw.slice(1,-1);if(/^-?\d+(\.\d+)?$/.test(raw))return Number(raw);if(/^(?:note\.)?[\w.-]+$/.test(raw))return property(row,raw);throw new Error('Unsupported Base expression: '+raw)}
export function matches(filter,row){
 if(!filter)return true;if(Array.isArray(filter))return filter.every(f=>matches(f,row));if(typeof filter==='object'){if(filter.and)return filter.and.every(f=>matches(f,row));if(filter.or)return filter.or.some(f=>matches(f,row));if(filter.not)return !matches(filter.not,row);throw new Error('Unsupported filter group')}
 const folder=/^file\.inFolder\(["'](.+)["']\)$/.exec(filter);if(folder)return row.path.startsWith(folder[1]+'/');
 const comparison=/^(.+?)\s*(==|!=|<=|>=|<|>)\s*(.+)$/.exec(filter);if(!comparison)throw new Error('Unsupported Base filter: '+filter);
 const a=value(comparison[1],row),b=value(comparison[3],row);switch(comparison[2]){case '==':return a===b;case '!=':return a!==b;case '<=':return a!==null&&b!==null&&a<=b;case '>=':return a!==null&&b!==null&&a>=b;case '<':return a!==null&&b!==null&&a<b;case '>':return a!==null&&b!==null&&a>b;}
}
export function baseFolder(data,fallback){const match=JSON.stringify(data.filters||{}).match(/file\.inFolder\(\\?["'](.+?)\\?["']\)/);return match?match[1]:fallback}
