const fs=require('fs');
require('esbuild').buildSync({entryPoints:['node_modules/@supabase/supabase-js/dist/index.mjs'],bundle:true,format:'iife',globalName:'supabase',outfile:'dist/vendor/supabase.js',minify:true,platform:'browser'});
fs.writeFileSync('index.html',fs.readFileSync('dist/index.html','utf8').replaceAll('./icons/','./dist/icons/').replace('src="./vendor/','src="./dist/vendor/').replace('src="./app.js','src="./dist/app.js'));
const manifest=JSON.parse(fs.readFileSync('dist/manifest.webmanifest','utf8'));for(const icon of manifest.icons)icon.src='dist/'+icon.src;fs.writeFileSync('manifest.webmanifest',JSON.stringify(manifest,null,2));
fs.copyFileSync('dist/sw.js','sw.js');fs.writeFileSync('.nojekyll','');
