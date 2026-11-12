const fs=require('fs');
require('esbuild').buildSync({entryPoints:['node_modules/@supabase/supabase-js/dist/index.mjs'],bundle:true,format:'iife',globalName:'supabase',outfile:'dist/vendor/supabase.js',minify:true,platform:'browser'});
fs.writeFileSync('index.html',fs.readFileSync('dist/index.html','utf8').replace('src="./vendor/supabase.js"','src="./dist/vendor/supabase.js"').replace('src="./app.js"','src="./dist/app.js"'));
fs.writeFileSync('.nojekyll','');
