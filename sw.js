/* MyList push worker: no offline page cache, no cached credentials. */
const ASSET_BASE='dist/';
const DB_NAME='mylist-push:'+self.registration.scope;
function database(){return new Promise((resolve,reject)=>{const r=indexedDB.open(DB_NAME,1);r.onupgradeneeded=()=>{r.result.createObjectStore('state');r.result.createObjectStore('seen');};r.onsuccess=()=>resolve(r.result);r.onerror=()=>reject(r.error);});}
async function read(store,key){const db=await database();try{return await new Promise((resolve,reject)=>{const tx=db.transaction(store),r=tx.objectStore(store).get(key);r.onsuccess=()=>resolve(r.result);r.onerror=()=>reject(r.error);});}finally{db.close();}}
async function write(store,key,value){const db=await database();try{await new Promise((resolve,reject)=>{const tx=db.transaction(store,'readwrite');tx.objectStore(store).put(value,key);tx.oncomplete=()=>resolve();tx.onerror=()=>reject(tx.error);});}finally{db.close();}}
async function account(userId){const previous=await read('state','user');if(previous===userId)return;const db=await database();try{await new Promise((resolve,reject)=>{const tx=db.transaction(['state','seen'],'readwrite');tx.objectStore('state').put(userId,'user');tx.objectStore('seen').clear();tx.oncomplete=resolve;tx.onerror=()=>reject(tx.error);});}finally{db.close();}
 const shown=await self.registration.getNotifications();shown.forEach(n=>n.close());}
self.addEventListener('install',()=>self.skipWaiting());
self.addEventListener('activate',event=>event.waitUntil(self.clients.claim()));
self.addEventListener('message',event=>{if(event.data?.type==='MYLIST_PUSH_ACCOUNT')event.waitUntil(account(event.data.userId||null).then(()=>event.ports[0]?.postMessage({ok:true})));});
self.addEventListener('push',event=>event.waitUntil((async()=>{
 let data;try{data=event.data.json();}catch{return;}
 if(!data?.id||!data.userId||!data.listId)return;
 const uid=await read('state','user');if(uid!==data.userId)return;
 const url=new URL(data.url,self.registration.scope),scope=new URL(self.registration.scope);
 if(url.origin!==scope.origin||url.pathname!==scope.pathname)return;
 const seen=await read('seen',String(data.id));if(seen&&Date.now()-seen<7*86400000)return;
 await self.registration.showNotification(String(data.title||'MyList').slice(0,160),{body:String(data.body||'Lista a fost actualizată.').slice(0,300),icon:new URL(ASSET_BASE+'icons/icon-192.png',scope).href,tag:'mylist-'+data.id,renotify:false,data:{url:url.href,userId:uid,listId:data.listId}});
 await write('seen',String(data.id),Date.now());
 // Bounded retention without retaining list contents or credentials.
 const db=await database();try{await new Promise((resolve,reject)=>{const tx=db.transaction('seen','readwrite'),r=tx.objectStore('seen').openCursor();r.onsuccess=()=>{const c=r.result;if(c){if(c.value<Date.now()-7*86400000)c.delete();c.continue();}};tx.oncomplete=resolve;tx.onerror=()=>reject(tx.error);});}finally{db.close();}
})()));
self.addEventListener('notificationclick',event=>{event.notification.close();event.waitUntil((async()=>{
 const d=event.notification.data;if(!d||await read('state','user')!==d.userId)return;
 const url=new URL(d.url),scope=new URL(self.registration.scope);if(url.origin!==scope.origin||url.pathname!==scope.pathname)return;
 const windows=await self.clients.matchAll({type:'window',includeUncontrolled:true});
 const client=windows.find(c=>new URL(c.url).origin===scope.origin&&new URL(c.url).pathname===scope.pathname);
 if(client){await client.focus();client.postMessage({type:'MYLIST_OPEN_LIST',url:url.href});}else await self.clients.openWindow(url.href);
})());});
