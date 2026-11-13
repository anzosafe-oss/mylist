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
 try{
 const body=await req.json();const email=String(body.email||'').trim().toLowerCase();
 const kind=body.kind==='administrator'?'administrator':'family';
 if(!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)||email.length>254)return answer(400,{error:'Adresă de e-mail invalidă'});
 const {data:reservation,error:reserveError}=await admin.rpc('mylist_reserve_invite',{actor:user.id,recipient:email,invite_kind:kind});
 if(reserveError)return answer(400,{error:reserveError.message});
 let delivered=false;
 try{
 const redirectTo=origin==='https://anzosafe-oss.github.io'?'https://anzosafe-oss.github.io/mylist/':'https://mylist-anzo-preview.zota-andrei.chatgpt.site/';
 let sent=await admin.auth.admin.inviteUserByEmail(email,{redirectTo});
 if(sent.error&&(sent.error.code==='email_exists'||sent.error.code==='user_already_exists')){
  const client=createClient(url,Deno.env.get('SUPABASE_ANON_KEY')!,{auth:{persistSession:false}});
  const result=await client.auth.signInWithOtp({email,options:{shouldCreateUser:false,emailRedirectTo:redirectTo}});
  if(result.error)throw Error('E-mailul nu a fost trimis. Încearcă din nou.');
 }else if(sent.error)throw Error('E-mailul nu a fost trimis. Încearcă din nou.');
 delivered=true;
 }finally{const {error:finishError}=await admin.rpc('mylist_finish_invite',{invitation_id:reservation.id,delivery:reservation.delivery_key,delivered});if(finishError)console.error('mylist_finish_invite',finishError.code);}
 return answer(200,{message:'Invitația a fost trimisă prin e-mail'});
 }catch{return answer(400,{error:'Invitația nu a fost trimisă. Încearcă din nou.'})}
});
