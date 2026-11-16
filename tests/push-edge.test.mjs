import {test} from 'node:test';import assert from 'node:assert/strict';import vm from 'node:vm';import {readFileSync} from 'node:fs';import {stripTypeScriptTypes} from 'node:module';
import {validSubscription,validAppUrl,notificationBody} from '../supabase/functions/mylist-push/logic.ts';
const sub={endpoint:'https://fcm.googleapis.com/a',keys:{p256dh:'B'.repeat(87),auth:'a'.repeat(22)}};
const uid='11111111-1111-4111-8111-111111111111',sid='22222222-2222-4222-8222-222222222222';
const jwt='x.'+Buffer.from(JSON.stringify({session_id:sid})).toString('base64url')+'.x';
function setup(options={}){
 const calls=[],config={enabled:true,keys:{publicKey:'public',privateKey:'private',dispatchToken:'worker'}};
 const db={auth:{getUser:async token=>({data:{user:token===jwt?{id:uid}:null},error:token===jwt?null:Error('invalid')})},rpc:async(name,args)=>{
  calls.push({rpc:name,args});return {data:name==='mylist_push_session'?options.session!==false:name==='mylist_push_claim'?[{id:7,list_id:'44444444-4444-4444-8444-444444444444',kind:'item_added',event_count:2,last_name:'Lapte',claim_token:'lease',attempts:1}]:options.noAccess?null:{subscription_id:'sub',user_id:uid,subscription:sub,app_url:'https://anzosafe-oss.github.io/mylist/',list_name:'Familie'}};
 },from(table){const q={op:'select',select(){return q},eq(){return q},is(){return q},upsert(value){q.op='upsert';q.value=value;return q},delete(){q.op='delete';return q},update(value){q.op='update';q.value=value;return q},maybeSingle(){q.one=true;return Promise.resolve(result())},single(){return Promise.resolve(result())},then(resolve){resolve(result())}};function result(){calls.push({table,op:q.op,value:q.value});return {data:table==='mylist_push_config'?config:table==='mylist_push_subscriptions'&&q.op==='select'?q.one?(options.prior||null):[]:[]}}return q}};
 let handler,fetches=0;
 const context={Request,Response,URL,atob,AbortSignal,crypto,console,validSubscription,validAppUrl,notificationBody,createClient:()=>db,webpush:{generateRequestDetails:()=>({endpoint:sub.endpoint,method:'POST',headers:{},body:'encrypted'})},fetch:async()=>{fetches++;return new Response('',{status:options.status||201})},Deno:{env:{get:()=> 'server-only'},serve:fn=>handler=fn}};
 const source=readFileSync(new URL('../supabase/functions/mylist-push/index.ts',import.meta.url),'utf8').replace(/^import .*;\n/gm,'');
 vm.runInNewContext(stripTypeScriptTypes(source),context);
 return {calls,get fetches(){return fetches},request:async(body,headers={Authorization:'Bearer '+jwt})=>handler(new Request('https://edge.example/mylist-push',{method:'POST',headers:{'Content-Type':'application/json',...headers},body:JSON.stringify(body)}))};
}
test('unauthenticated, forged session, unsupported endpoint and origin rejected',async()=>{
 let s=setup();assert.equal((await s.request({action:'config'},{})).status,401);
 s=setup({session:false});assert.equal((await s.request({action:'config'})).status,403);
 s=setup();assert.equal((await s.request({action:'subscribe',subscription:{...sub,endpoint:'https://127.0.0.1/'},appUrl:'https://anzosafe-oss.github.io/mylist/'})).status,400);
 assert.equal((await s.request({action:'config'},{Authorization:'Bearer '+jwt,Origin:'https://evil.test'})).status,403);
});
test('config returns only public VAPID key',async()=>{const r=await setup().request({action:'config'});assert.deepEqual(await r.json(),{publicKey:'public'});});
test('subscription binds verified user and session; rejects takeover with wrong capability',async()=>{
 let s=setup();assert.equal((await s.request({action:'subscribe',subscription:sub,appUrl:'https://anzosafe-oss.github.io/mylist/'})).status,200);
 const saved=s.calls.find(c=>c.op==='upsert').value;assert.equal(saved.user_id,uid);assert.equal(saved.session_id,sid);
 s=setup({prior:{user_id:'other',subscription:{keys:{auth:'other',p256dh:'other'}}}});assert.equal((await s.request({action:'subscribe',subscription:sub,appUrl:'https://anzosafe-oss.github.io/mylist/'})).status,409);
});
test('worker token, revoked access and expired provider subscriptions',async()=>{
 let s=setup();assert.equal((await s.request({},{'x-mylist-dispatch':'wrong'})).status,401);
 s=setup({noAccess:true});assert.equal((await s.request({},{'x-mylist-dispatch':'worker'})).status,200);assert.equal(s.fetches,0);
 s=setup({status:410});assert.equal((await (await s.request({},{'x-mylist-dispatch':'worker'})).json()).discarded,1);assert.ok(s.calls.some(c=>c.table==='mylist_push_subscriptions'&&c.op==='delete'));
});
test('success finalizes claim; transient failure schedules bounded retry',async()=>{
 let s=setup();assert.equal((await (await s.request({},{'x-mylist-dispatch':'worker'})).json()).sent,1);assert.ok(s.calls.some(c=>c.value?.outcome==='sent'));
 s=setup({status:503});assert.equal((await (await s.request({},{'x-mylist-dispatch':'worker'})).json()).failed,1);assert.ok(s.calls.some(c=>c.value?.outcome==='retry'));
});
