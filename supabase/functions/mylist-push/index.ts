import { createClient } from 'npm:@supabase/supabase-js@2.57.4';
import webpush from 'npm:web-push@3.6.7';
import { validSubscription, notificationBody, validAppUrl } from './logic.ts';
const db=createClient(Deno.env.get('SUPABASE_URL')!,Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,{auth:{persistSession:false}});
const origins=new Set(['https://anzosafe-oss.github.io','https://mylist-anzo-preview.zota-andrei.chatgpt.site']);
const checked=(r:any)=>{if(r.error)throw r.error;return r.data};
async function config(){
 let row=checked(await db.from('mylist_push_config').select('keys,enabled').eq('id',true).maybeSingle());
 if(!row){const keys={...webpush.generateVAPIDKeys(),dispatchToken:crypto.randomUUID()+crypto.randomUUID()};
 checked(await db.from('mylist_push_config').upsert({id:true,keys,enabled:true},{onConflict:'id',ignoreDuplicates:true}));
 row=checked(await db.from('mylist_push_config').select('keys,enabled').eq('id',true).single());}return row;
}
async function dispatch(keys:any){
 const jobs=checked(await db.rpc('mylist_push_claim'));let sent=0,failed=0,discarded=0;
 // Bounded concurrency and atomic database leases; retries retain the same delivery ID.
 const queue=[...jobs];await Promise.all(Array.from({length:4},async()=>{
 while(queue.length){const job=queue.shift();try{
  const target=checked(await db.rpc('mylist_push_target',{job:job.id,token:job.claim_token}));
  if(!target){checked(await db.from('mylist_push_queue').update({finished_at:new Date().toISOString(),outcome:'access_or_preference'}).eq('id',job.id).eq('claim_token',job.claim_token));discarded++;continue;}
  if(!validSubscription(target.subscription)||!validAppUrl(target.app_url)){
   checked(await db.from('mylist_push_subscriptions').delete().eq('id',target.subscription_id));discarded++;continue;
  }
  const url=new URL(target.app_url);url.searchParams.set('list',job.list_id);url.searchParams.set('push_user',target.user_id);
  const payload={id:String(job.id),userId:target.user_id,listId:job.list_id,title:'MyList · '+target.list_name,body:notificationBody(job),url:url.href};
  const request=webpush.generateRequestDetails(target.subscription,JSON.stringify(payload),{TTL:300,urgency:'normal',vapidDetails:{subject:'mailto:apps.anzo@gmail.com',publicKey:keys.publicKey,privateKey:keys.privateKey}});
  const response=await fetch(request.endpoint,{method:request.method,headers:request.headers,body:request.body,redirect:'error',signal:AbortSignal.timeout(12000)});
  if([404,410].includes(response.status)){checked(await db.from('mylist_push_subscriptions').delete().eq('id',target.subscription_id));discarded++;continue;}
  if(!response.ok){let reason='';try{const value=(await response.json()).reason;if(typeof value==='string'&&/^[A-Za-z][A-Za-z0-9_]{0,60}$/.test(value))reason='_'+value;}catch{}throw Error('provider_'+response.status+reason);}
  checked(await db.from('mylist_push_queue').update({finished_at:new Date().toISOString(),outcome:'sent'}).eq('id',job.id).eq('claim_token',job.claim_token));sent++;
 }catch(error){
  // Store only a whitelisted provider code; never endpoint tokens, keys or payloads.
  const code=error instanceof Error&&/^provider_[0-9]{3}(?:_[A-Za-z0-9_]{1,61})?$/.test(error.message)?error.message:'transport_or_runtime';
  const terminal=job.attempts>=5;
  failed++;checked(await db.from('mylist_push_queue').update({locked_until:null,finished_at:terminal?new Date().toISOString():null,due_at:new Date(Date.now()+Math.min(300000,10000*2**job.attempts)).toISOString(),outcome:(terminal?'failed:':'retry:')+code}).eq('id',job.id).eq('claim_token',job.claim_token).is('finished_at',null));
 }}
 }));return {sent,failed,discarded};
}
Deno.serve(async(req:Request)=>{
 const origin=req.headers.get('origin');const headers:Record<string,string>={'Content-Type':'application/json','Vary':'Origin','Access-Control-Allow-Headers':'authorization, apikey, content-type, x-client-info','Access-Control-Allow-Methods':'POST, OPTIONS'};
 if(origin&&origins.has(origin))headers['Access-Control-Allow-Origin']=origin;
 const reply=(body:unknown,status=200)=>new Response(JSON.stringify(body),{status,headers});
 if(origin&&!origins.has(origin))return reply({error:'Origine nepermisă'},403);
 if(req.method==='OPTIONS')return new Response(null,{status:204,headers});
 if(req.method!=='POST')return reply({error:'Metodă nepermisă'},405);
 try{
  const worker=req.headers.get('x-mylist-dispatch');
  if(worker){const c=checked(await db.from('mylist_push_config').select('keys,enabled').eq('id',true).maybeSingle());
   if(!c||worker!==c.keys.dispatchToken)return reply({error:'Neautorizat'},401);
   if(!c.enabled)return reply({error:'Notificările nu sunt încă publicate'},503);
   return reply(await dispatch(c.keys));}
  const authHeader=req.headers.get('authorization')||'',token=authHeader.replace(/^Bearer /i,'');
  if(!authHeader.match(/^Bearer /i))return reply({error:'Autentificare necesară'},401);
  const auth=await db.auth.getUser(token);if(auth.error||!auth.data.user)return reply({error:'Sesiune expirată'},401);
  let sid;try{sid=JSON.parse(atob(token.split('.')[1].replace(/-/g,'+').replace(/_/g,'/'))).session_id;}catch{return reply({error:'Sesiune invalidă'},401);}
  const uid=auth.data.user.id;
  if(!sid||!checked(await db.rpc('mylist_push_session',{uid,sid})))return reply({error:'Accesul la MyList nu este activ'},403);
  if(Number(req.headers.get('content-length')||0)>8192)return reply({error:'Cerere prea mare'},413);
  const raw=await req.text();if(raw.length>8192)return reply({error:'Cerere prea mare'},413);const body=JSON.parse(raw);
  if(body.action==='unsubscribe'){
   checked(await db.from('mylist_push_subscriptions').delete().eq('user_id',uid).eq('endpoint',String(body.endpoint||'')));return reply({ok:true});
  }
  const c=await config();if(!c.enabled)return reply({error:'Notificările nu sunt încă disponibile'},503);
  if(body.action==='config')return reply({publicKey:c.keys.publicKey});
  if(body.action==='subscribe'){
   if(!validSubscription(body.subscription)||!validAppUrl(body.appUrl))return reply({error:'Abonament Push invalid'},400);
   // Knowing the full browser subscription (including its private auth capability) permits account switching on that device.
   const prior=checked(await db.from('mylist_push_subscriptions').select('id,user_id,subscription,session_id').eq('endpoint',body.subscription.endpoint).maybeSingle());
   if(prior&&prior.user_id!==uid&&(prior.subscription.keys.p256dh!==body.subscription.keys.p256dh||prior.subscription.keys.auth!==body.subscription.keys.auth))return reply({error:'Abonament asociat altui dispozitiv'},409);
   if(prior&&(prior.user_id!==uid||prior.session_id!==sid))checked(await db.from('mylist_push_subscriptions').delete().eq('id',prior.id));
   if(!prior&&(checked(await db.from('mylist_push_subscriptions').select('id').eq('user_id',uid))).length>=12)return reply({error:'Limita de dispozitive a fost atinsă'},429);
   checked(await db.from('mylist_push_subscriptions').upsert({user_id:uid,session_id:sid,endpoint:body.subscription.endpoint,subscription:body.subscription,app_url:body.appUrl,updated_at:new Date().toISOString()},{onConflict:'endpoint'}));
   return reply({ok:true});
  }
  return reply({error:'Acțiune invalidă'},400);
 }catch{return reply({error:'Notificările nu au putut fi actualizate. Încearcă din nou.'},500);}
});
