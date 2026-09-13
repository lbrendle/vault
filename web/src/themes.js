export const defaultAppearance={theme:'graphite',mode:'system',font:'sans',fontSize:15,readingWidth:880,motion:'full',density:'comfortable'};
export const themes=[
 {id:'graphite',name:'Graphite',description:'Quiet, clean, familiar.',light:['#ffffff','#f7f7f8','#f0f0f1','#e8e8eb','#ffffff','#202123','#68696d','#9a9b9f','#e6e6e8','#55565c','#ececef'],dark:['#212121','#171717','#2f2f2f','#3a3a3a','#2b2b2b','#ececec','#a2a2a2','#707070','#353535','#d0d0d0','#363636']},
 {id:'linen',name:'Linen',description:'A little warmth. Space to think.',light:['#fcfaf6','#f2efe8','#ebe6dc','#e4ddcf','#fffdf8','#34312b','#827a6c','#aaa08e','#e7e0d4','#8b7251','#eee5d5'],dark:['#25221e','#1b1916','#332f28','#403a30','#2c2923','#e9e3d8','#a79e8e','#756c5d','#3c372f','#c5ac83','#3e3528']},
 {id:'sage',name:'Sage',description:'Soft greens, grounded focus.',light:['#fafcf9','#eff3ed','#e6ede2','#dbe6d6','#ffffff','#28352a','#748272','#a0ad9c','#dfe7dc','#55795b','#e2edde'],dark:['#202520','#171c18','#2b342c','#354337','#262e27','#e0e8df','#97a694','#6c7d69','#354035','#a0bea0','#314635']},
 {id:'ocean',name:'Ocean',description:'Clear blue, open horizons.',light:['#fbfcfe','#eef3f8','#e5edf5','#d9e5f0','#ffffff','#253443','#718498','#9caeba','#dee7ee','#467fa7','#e0edf7'],dark:['#1c242b','#141b22','#29343e','#334352','#252e38','#dfe8f0','#93a7b7','#607889','#303e4a','#91bbd6','#293e50']},
 {id:'iris',name:'Iris',description:'A thoughtful shade of violet.',light:['#fdfbff','#f2eff8','#eae4f3','#e0d8ed','#ffffff','#332c43','#847990','#aaa0b6','#e6dff0','#8b72b0','#eee5f7'],dark:['#25212b','#1b171f','#342e3d','#41384d','#2d2734','#e9e2f0','#a497b2','#766885','#3c3348','#bba4d3','#41304f']},
 {id:'rose',name:'Rose',description:'Warm blush, restrained detail.',light:['#fffafb','#f8eff1','#f2e5e9','#ebd9df','#fffefe','#432e35','#967c86','#b89fa9','#efdee4','#ac6f87','#f5e2e9'],dark:['#2b2226','#20181c','#3b2e34','#4c3a42','#33282e','#f0e0e7','#b39aa5','#876f7b','#46343d','#d0a0b3','#4b303b']},
 {id:'slate',name:'Slate',description:'Crisp edges, cool neutrals.',light:['#f9fbfc','#edf0f2','#e4e8eb','#d8dfe3','#ffffff','#29323a','#737e87','#9ba6af','#dde3e8','#677e90','#e3ebf1'],dark:['#202429','#15191e','#2c3239','#38414b','#272c33','#e0e5eb','#96a1ae','#6a7582','#353d46','#a3b5c7','#31404d']},
 {id:'cocoa',name:'Cocoa',description:'Deep browns, a slower pace.',light:['#fdf9f5','#f5ece4','#eddfd3','#e5d2c3','#fffdfb','#423229','#917764','#b39885','#ecddd0','#a27653','#f1e0d0'],dark:['#29211c','#1e1713','#3a2d24','#49382c','#312720','#eee0d3','#b49b86','#846e5c','#46352b','#ccaa87','#4a3524']}
];
// Palettes share semantic roles; color families keep their own paper and ink.
function hsl(h,s,l){s/=100;l/=100;const a=s*Math.min(l,1-l),f=n=>{const k=(n+h/30)%12;return Math.round(255*(l-a*Math.max(-1,Math.min(k-3,9-k,1)))).toString(16).padStart(2,'0')};return '#'+f(0)+f(8)+f(4)}
const additions=[
 ['butter','Butter','Sunlit pages, soft gold.',46,68,'Warm'],['peach','Peach','A little afternoon sunshine.',22,62,'Warm'],['terracotta','Terracotta','Clay, copper, and warm paper.',14,47,'Warm'],['amber','Amber','Honeyed light, deep evenings.',36,65,'Warm'],
 ['forest','Forest','Evergreen, calm and collected.',152,35,'Nature'],['matcha','Matcha','Fresh greens, creamy paper.',85,36,'Nature'],['moss','Moss','A quiet walk through the woods.',112,20,'Nature'],['sandstone','Sandstone','Desert light and warm stone.',32,28,'Nature'],
 ['riviera','Riviera','Coastal blue with a sunlit edge.',205,64,'Cool'],['glacier','Glacier','Icy blue, crystalline focus.',187,48,'Cool'],['blue-hour','Blue Hour','The stillness before nightfall.',227,43,'Cool'],['midnight','Midnight','Deep navy, a luminous accent.',237,45,'Cool'],
 ['cherry','Cherry','Rich red with porcelain pages.',351,48,'Jewel'],['orchid','Orchid','A bloom of violet and pink.',293,36,'Jewel'],['plum','Plum','Inky purple, velvet evenings.',275,31,'Jewel'],['ink','Ink','Paper white, editorial black.',220,6,'Neutral']
];
for(const [id,name,description,h,s,family] of additions){themes.push({id,name,description,family,
 light:[hsl(h,s*.32,98),hsl(h,s*.4,95),hsl(h,s*.38,91),hsl(h,s*.36,86),hsl(h,s*.22,99),hsl(h,s*.45,18),hsl(h,s*.22,39),hsl(h,s*.15,43),hsl(h,s*.25,87),hsl(h,s,36),hsl(h,s*.55,90)],
 dark:[hsl(h,s*.24,12),hsl(h,s*.28,9),hsl(h,s*.27,17),hsl(h,s*.28,23),hsl(h,s*.24,15),hsl(h,s*.22,91),hsl(h,s*.18,69),hsl(h,s*.12,61),hsl(h,s*.22,24),hsl(h,s*.72,74),hsl(h,s*.43,24)]})}
const families={graphite:'Neutral',linen:'Warm',sage:'Nature',ocean:'Cool',iris:'Jewel',rose:'Jewel',slate:'Neutral',cocoa:'Warm'};
const rgb=hex=>[1,3,5].map(i=>parseInt(hex.slice(i,i+2),16));
function luminance(hex){return rgb(hex).map(n=>n/255).map(v=>v<=.04045?v/12.92:((v+.055)/1.055)**2.4).reduce((s,v,i)=>s+v*[.2126,.7152,.0722][i],0)}
export function contrast(a,b){const x=luminance(a),y=luminance(b);return(Math.max(x,y)+.05)/(Math.min(x,y)+.05)}
function readable(color,ink,backgrounds){const a=rgb(color),b=rgb(ink);for(let step=0;step<=100;step++){const t=step/100,c='#'+a.map((v,i)=>Math.round(v+(b[i]-v)*t).toString(16).padStart(2,'0')).join('');if(backgrounds.every(bg=>contrast(c,bg)>=4.5))return c}return ink}
for(const theme of themes){theme.family??=families[theme.id];for(const mode of ['light','dark']){const v=theme[mode],backgrounds=[v[0],v[1],v[2],v[3],v[4],v[10]];for(const i of [6,7,9])v[i]=readable(v[i],v[5],backgrounds)}}
export function appearanceTokens(preferences={}) {
 const p={...defaultAppearance,...preferences},theme=themes.find(t=>t.id===p.theme)||themes[0];
 const dark=p.mode==='dark'||(p.mode==='system'&&matchMedia('(prefers-color-scheme: dark)').matches);
 const names=['bg','sidebar','surface','hover','elevated','text','muted','faint','border','accent','accent-soft'];
 return Object.fromEntries(names.map((name,i)=>['--'+name,theme[dark?'dark':'light'][i]]));
}
let recolorFrame;
export function applyAppearance(preferences={}){
 // Palette switches are atomic. Cancel in-flight hover/color transitions so
 // WebKit cannot retain a mixture of old and new theme colors on cached layers.
 document.documentElement.dataset.recoloring='true';

 const p={...defaultAppearance,...preferences};const theme=themes.find(t=>t.id===p.theme)||themes[0];
 const dark=p.mode==='dark'||(p.mode==='system'&&matchMedia('(prefers-color-scheme: dark)').matches);
 Object.entries(appearanceTokens(p)).forEach(([name,value])=>document.documentElement.style.setProperty(name,value));
 const root=document.documentElement;root.dataset.mode=dark?'dark':'light';root.dataset.theme=theme.id;root.dataset.motion=p.motion;root.dataset.density=p.density;
 root.style.colorScheme=dark?'dark':'light';root.style.setProperty('--document-size',p.fontSize+'px');root.style.setProperty('--reading-width',p.readingWidth+'px');root.style.setProperty('--document-font',p.font==='serif'?'Georgia, Charter, serif':p.font==='mono'?'ui-monospace, SFMono-Regular, Menlo, monospace':'-apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif');
 void document.documentElement.offsetHeight;
 cancelAnimationFrame(recolorFrame);
 recolorFrame=requestAnimationFrame(()=>{delete document.documentElement.dataset.recoloring});
 return dark?'dark':'light';
}
