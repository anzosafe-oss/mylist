import {createClient} from 'npm:@supabase/supabase-js@2.119.0';
const origins=new Set(['https://anzosafe-oss.github.io','https://mylist-anzo-preview.zota-andrei.chatgpt.site']);
Deno.serve(async req=>{
 const origin=req.headers.get('Origin')||'';
 const headers={'Access-Control-Allow-Origin':origins.has(origin)?origin:'https://anzosafe-oss.github.io','Access-Control-Allow-Headers':'authorization, apikey, content-type, x-client-info','Content-Type':'application/json','Vary':'Origin'};
 const answer=(status:number,data:unknown)=>new Response(JSON.stringify(data),{status,headers});
 if(req.method==='OPTIONS')return new Response('ok',{headers});
 if(req.method!=='POST'||!origins.has(origin))return answer(403,{error:'Cerere nepermisă'});
 const token=req.headers.get('Authorization')?.replace(/^Bearer /,'');if(!token)return answer(401,{error:'Autentificare necesară'});
 const url=Deno.env.get('SUPABASE_URL')!;
 const admin=createClient(url,Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,{auth:{persistSession:false}});
 const {data:{user},error}=await admin.auth.getUser(token);
 if(error||!user)return answer(401,{error:'Sesiune expirată'});
 const database=createClient(url,Deno.env.get('SUPABASE_ANON_KEY')!,{global:{headers:{Authorization:`Bearer ${token}`}},auth:{persistSession:false}});
 const {data:account,error:accountError}=await database.from('mylist_accounts').select('is_admin').eq('user_id',user.id).not('accepted_at','is',null).maybeSingle();
 if(accountError){console.error('mylist_admin_lookup',accountError.code);return answer(500,{error:'Verificarea rolului de administrator a eșuat. Încearcă din nou.'})}
 if(!account?.is_admin)return answer(403,{error:'Doar administratorul poate trimite invitații'});
 try{
 const body=await req.json();const email=String(body.email||'').trim().toLowerCase();
 if(!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)||email.length>254)return answer(400,{error:'Adresă de e-mail invalidă'});
 const {data:old}=await database.from('mylist_accounts').select('email,accepted_at,invited_at').eq('email',email).maybeSingle();
 if(old?.accepted_at)return answer(409,{error:'Persoana are deja acces la MyList'});
 if(old&&Date.now()-Date.parse(old.invited_at)<60000)return answer(429,{error:'Așteaptă un minut înainte să retrimiți invitația'});
 const {error:insertError}=await database.from('mylist_accounts').insert({email});
 if(insertError&&insertError.code!=='23505')return answer(500,{error:'Invitația nu a putut fi înregistrată'});
 const redirectTo=origin==='https://anzosafe-oss.github.io'?'https://anzosafe-oss.github.io/mylist/':'https://mylist-anzo-preview.zota-andrei.chatgpt.site/';
 let sent=await admin.auth.admin.inviteUserByEmail(email,{redirectTo});
 if(sent.error&&(sent.error.code==='email_exists'||sent.error.code==='user_already_exists')){
  const client=createClient(url,Deno.env.get('SUPABASE_ANON_KEY')!,{auth:{persistSession:false}});
  const result=await client.auth.signInWithOtp({email,options:{shouldCreateUser:false,emailRedirectTo:redirectTo}});
  if(result.error)return answer(400,{error:'E-mailul nu a fost trimis. Verifică setările SMTP și încearcă din nou.'});
 }else if(sent.error)return answer(400,{error:'E-mailul nu a fost trimis. Verifică setările SMTP și adresele de redirecționare în Supabase.'});
 return answer(200,{message:'Invitația a fost trimisă prin e-mail'});
 }catch{return answer(400,{error:'Cerere invalidă'})}
});
