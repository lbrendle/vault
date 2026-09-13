import {cpSync,mkdirSync} from 'node:fs';
import {defineConfig} from 'vite';
export default defineConfig({base:'./',plugins:[{name:'local-pdf-resources',closeBundle(){for(const name of ['cmaps','standard_fonts','wasm','iccs']){mkdirSync('../Sources/VaultApp/Resources/web/pdf',{recursive:true});cpSync('node_modules/pdfjs-dist/'+name,'../Sources/VaultApp/Resources/web/pdf/'+name,{recursive:true})}}}],build:{outDir:'../Sources/VaultApp/Resources/web',emptyOutDir:true,chunkSizeWarningLimit:1200}});
