import {test} from 'node:test';import assert from 'node:assert/strict';import vm from 'node:vm';import {readFileSync} from 'node:fs';
function setup(url){const messages=[],ctx={URL,location:new URL(url),isSecureContext:false,localStorage:{getItem(){return null}},navigator:{userAgent:'Desktop'},matchMedia:()=>({matches:false}),document:{addEventListener(){},visibilityState:'visible',getElementById:()=>null},window:{addEventListener(){}},history:{replaceState(a,b,u){ctx.location=new URL(u)}},user:{id:'alice'},lists:[{id:'active',name:'Shared <list>'},{id:'archive',completed_at:'today'}],shared:l=>l.id==='active',esc:s=>String(s).replace(/</g,'&lt;').replace(/>/g,'&gt;'),toast:t=>messages.push(t),selected:null,view:'settings'};vm.runInNewContext(readFileSync(new URL('../dist/push.js',import.meta.url),'utf8')+'\nthis.push=MyListPush;',ctx);return {ctx,messages,push:ctx.push};}
test('deep link selects accessible list and consumes query',()=>{const s=setup('https://app.example/?list=active&push_user=alice');s.push.openPendingList();assert.equal(s.ctx.selected,'active');assert.equal(s.ctx.view,'lists');assert.equal(s.ctx.location.search,'');});
test('completed list opens history; wrong account and revoked list are rejected once',()=>{
 let s=setup('https://app.example/?list=archive&push_user=alice');s.push.openPendingList();assert.equal(s.ctx.view,'history');assert.equal(s.push.archiveId(),'archive');
 s=setup('https://app.example/?list=active&push_user=bob');s.push.openPendingList();s.push.openPendingList();assert.equal(s.ctx.selected,null);assert.equal(s.messages.length,1);
 s=setup('https://app.example/?list=revoked&push_user=alice');s.push.openPendingList();assert.equal(s.ctx.selected,null);assert.match(s.messages[0],/disponibilă/);
});
test('unsupported browser remains usable and never requests permission',()=>{const s=setup('https://app.example/');assert.match(s.push.settings(),/nu sunt disponibile/);assert.match(s.push.settings(),/disabled/);});

function iosDevice({failSubscribe=false}={}){
 const trace=[],storage=new Map(),data={mylist_push_preferences:null,mylist_push_list_preferences:[]};let sub=null;
 const reg={active:{postMessage(data,ports){if(ports)ports[0].postMessage({ok:true});else trace.push('worker:'+data.type)}},pushManager:{async getSubscription(){return sub},subscribe(){trace.push('subscribe');if(failSubscribe)throw Object.assign(Error('gesture'),{name:'NotAllowedError'});sub={options:{},endpoint:'https://web.push.apple.com/device',toJSON(){return {endpoint:this.endpoint}},async unsubscribe(){sub=null;return true}};return Promise.resolve(sub)}}};
 class Channel{constructor(){this.port1={onmessage:null,close(){}};this.port2={postMessage:()=>queueMicrotask(()=>this.port1.onmessage?.({data:{ok:true}}))};}}
 const ctx={URL,Promise,Uint8Array,ArrayBuffer,MessageChannel:Channel,queueMicrotask,setTimeout,clearTimeout,atob,btoa,location:new URL('https://anzosafe-oss.github.io/mylist/'),isSecureContext:true,localStorage:{getItem:k=>storage.get(k)||null,setItem:(k,v)=>storage.set(k,v),removeItem:k=>storage.delete(k)},Notification:{permission:'default',requestPermission(){throw Error('Permission must be requested by subscribe itself')}},navigator:{clearAppBadge:async()=>trace.push('badge:clear'),userAgent:'iPhone',platform:'iPhone',standalone:true,serviceWorker:{register:async()=>reg,ready:Promise.resolve(reg),addEventListener(){}}},matchMedia:()=>({matches:false}),document:{addEventListener(){},visibilityState:'visible',getElementById:()=>({set outerHTML(s){trace.push('paint')},get outerHTML(){return ''}})},window:{Notification:{},addEventListener(){}},user:{id:'alice'},lists:[],shared:()=>true,esc:String,history:{replaceState(){}},toast(){},sb:{functions:{async invoke(name,{body}){trace.push('api:'+body.action);return {data:body.action==='config'?{publicKey:'B'.repeat(87)}:{ok:true}}}},from(table){const q={select(){return q},eq(){return q},maybeSingle(){return Promise.resolve({data:data[table]})},then(fn){return Promise.resolve({data:data[table]}).then(fn)},async upsert(row){data[table]=row;return {data:row}}};return q}}};
 vm.runInNewContext(readFileSync(new URL('../dist/push.js',import.meta.url),'utf8')+'\nthis.push=MyListPush;',ctx);
 return {ctx,trace,data,push:ctx.push};
}
test('iOS preloads worker/key, then subscribes before any await, API call or repaint',async()=>{
 const s=iosDevice();await s.push.init();assert.ok(s.trace.includes('api:config'));assert.ok(!s.trace.includes('subscribe'),'initialization must not subscribe without a gesture');s.trace.length=0;
 const pending=s.push.toggle(true);assert.equal(s.trace[0],'subscribe');await pending;assert.match(s.push.settings(),/Notificări activate/);assert.match(s.push.settings(),/aria-label="Push pe acest dispozitiv" checked/);
 await s.push.toggle(false);assert.match(s.push.settings(),/Notificări oprite/);assert.doesNotMatch(s.push.settings(),/aria-label="Push pe acest dispozitiv" checked/);
});
test('synchronous Safari rejection releases the toggle and shows an error',async()=>{
 const s=iosDevice({failSubscribe:true});await s.push.init();await s.push.toggle(true);assert.match(s.push.settings(),/Activarea nu a fost permisă/);assert.doesNotMatch(s.push.settings(),/aria-label="Push pe acest dispozitiv"[^>]*disabled/);
});
test('four separate defaults and independent preference writes',async()=>{
 const s=iosDevice();await s.push.init();let html=s.push.settings();for(const label of ['Produse adăugate','Listă partajată','Listă finalizată'])assert.match(html,new RegExp('aria-label="'+label+'" checked'));
 assert.doesNotMatch(html,/aria-label="Produse bifate \/ debifate" checked/);
 await s.push.preference('item_added',false);await s.push.preference('list_completed',false);await s.push.preference('item_toggled',true);
 assert.deepEqual(JSON.parse(JSON.stringify(s.data.mylist_push_preferences)),{item_added:false,list_shared:true,list_completed:false,item_toggled:true,user_id:'alice'});
});

test('foreground reading clears badge; hidden app preserves it',async()=>{const s=iosDevice();await s.push.init();await s.push.toggle(true);assert.ok(s.trace.includes('worker:MYLIST_PUSH_READ'));s.trace.length=0;s.ctx.document.visibilityState='hidden';await s.push.markRead();assert.deepEqual(s.trace,[]);s.ctx.document.visibilityState='visible';await s.push.markRead();assert.ok(s.trace.includes('worker:MYLIST_PUSH_READ'));assert.ok(s.trace.includes('badge:clear'));});
