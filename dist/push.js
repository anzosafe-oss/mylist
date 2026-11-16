/* MyList Push: device opt-in, account-scoped preferences and safe deep links. */
const MyListPush=(()=>{
 let registration=null,owner=null,enabled=false,working=false,ready=false,message='',prefs={item_toggled:false},listPrefs={},generation=0;
 const supported=()=>isSecureContext&&'serviceWorker'in navigator&&'PushManager'in window&&'Notification'in window;
 const ios=()=>/iPad|iPhone|iPod/.test(navigator.userAgent)||(navigator.platform==='MacIntel'&&navigator.maxTouchPoints>1);
 const standalone=()=>matchMedia('(display-mode: standalone)').matches||navigator.standalone===true;
 const base=()=>new URL('./',location.href).href;
 const opted=uid=>localStorage.getItem('mylist-push:'+uid)==='on';
 function paint(){const el=document.getElementById('pushSettings');if(el)el.outerHTML=settings();}
 function settings(){
  const available=supported()&&(!ios()||standalone());
  const hint=!supported()?'Notificările Push nu sunt disponibile în acest browser.':ios()&&!standalone()?'Pe iPhone/iPad, adaugă MyList pe ecranul principal și deschide aplicația de acolo.':Notification.permission==='denied'?'Notificările sunt blocate. Permite-le din setările browserului sau ale telefonului.':'Primești alerte și când MyList este închisă. Setările listelor se aplică pe toate dispozitivele tale.';
  const sharedLists=typeof lists==='undefined'?[]:lists.filter(l=>shared(l));
  return `<div class="settings-section" id="pushSettings"><h3>Notificări</h3><label class="setting-row"><span>Push pe acest dispozitiv</span><input type="checkbox" aria-label="Push pe acest dispozitiv" ${enabled?'checked':''} ${!available||working?'disabled':''} onchange="MyListPush.toggle(this.checked)"></label><p>${esc(hint)}</p><p class="push-message" role="status">${esc(message)}</p>${ready?`<label class="setting-row"><span>Produse bifate / debifate</span><input type="checkbox" ${prefs.item_toggled?'checked':''} ${working?'disabled':''} onchange="MyListPush.preference(this.checked)"></label><p>Produsele adăugate, partajarea și finalizarea listelor sunt incluse automat.</p>${sharedLists.length?'<p>Liste partajate</p>'+sharedLists.map(l=>`<label class="setting-row"><span class="push-list-name">${esc(l.name)}</span><input type="checkbox" aria-label="Notificări pentru ${esc(l.name)}" ${listPrefs[l.id]!==false?'checked':''} ${working?'disabled':''} onchange="MyListPush.listPreference('${l.id}',this.checked)"></label>`).join(''):'<p>Listele partajate vor apărea aici.</p>'}`:''}</div>`;
 }
 async function api(body){const r=await sb.functions.invoke('mylist-push',{body});if(r.error){let text='Notificările nu au putut fi actualizate.';try{text=(await r.error.context.json()).error||text;}catch{}throw Error(text);}return r.data;}
 let workerTask=null;async function worker(){if(!supported())return null;
  if(!workerTask)workerTask=(async()=>{registration=await navigator.serviceWorker.register('./sw.js',{updateViaCache:'none'});const pending=registration.installing||registration.waiting;
   if(pending&&pending.state!=='activated')await new Promise((resolve,reject)=>{const timer=setTimeout(()=>reject(Error('Workerul se actualizează. Reîncearcă activarea.')),10000);const check=()=>{if(pending.state==='activated'){clearTimeout(timer);resolve();}else if(pending.state==='redundant'){clearTimeout(timer);reject(Error('Actualizarea notificărilor nu a reușit.'));}};pending.addEventListener('statechange',check);check();});
   return navigator.serviceWorker.ready;})().catch(e=>{workerTask=null;throw e;});return workerTask;}

 async function bind(uid,expected=generation){const reg=await worker();if(!reg||expected!==generation)return;const sw=reg.active;if(!sw)throw Error('Notificările se pregătesc. Încearcă din nou.');
  await new Promise((resolve,reject)=>{const channel=new MessageChannel(),timer=setTimeout(()=>reject(Error('Notificările nu sunt pregătite.')),5000);channel.port1.onmessage=()=>{clearTimeout(timer);channel.port1.close();resolve();};sw.postMessage({type:'MYLIST_PUSH_ACCOUNT',userId:uid},[channel.port2]);});}
 function keyBytes(key){const raw=atob(key.replace(/-/g,'+').replace(/_/g,'/'));return Uint8Array.from(raw,c=>c.charCodeAt(0));}
 async function refresh(){if(!user)return;const uid=user.id;try{
  const result=await Promise.all([sb.from('mylist_push_preferences').select('*').eq('user_id',uid).maybeSingle(),sb.from('mylist_push_list_preferences').select('list_id,enabled').eq('user_id',uid)]);
  for(const r of result)if(r.error)throw r.error;if(user?.id!==uid)return;
  prefs=result[0].data||{item_toggled:false};listPrefs=Object.fromEntries(result[1].data.map(p=>[p.list_id,p.enabled]));ready=true;
 }catch{message='Setările notificărilor nu sunt încă disponibile.';ready=false;}paint();}
 async function init(){if(!user)return;const uid=user.id,g=++generation;owner=uid;enabled=false;message='';await refresh();if(g!==generation)return;
  if(!supported()||(ios()&&!standalone()))return;
  try{await bind(opted(uid)&&Notification.permission==='granted'?uid:null,g);const reg=await worker();let sub=await reg.pushManager.getSubscription();
   if(g!==generation)return;
   if(opted(uid)&&Notification.permission==='granted'){
    const c=await api({action:'config'});if(g!==generation)return;
    if(sub){const stored=sub.options.applicationServerKey;if(stored&&btoa(String.fromCharCode(...new Uint8Array(stored))).replace(/\+/g,'-').replace(/\//g,'_').replace(/=+$/,'')!==c.publicKey){await sub.unsubscribe();sub=null;}}
    if(!sub)sub=await reg.pushManager.subscribe({userVisibleOnly:true,applicationServerKey:keyBytes(c.publicKey)});
    if(g!==generation){await sub.unsubscribe();return;}
    await api({action:'subscribe',subscription:sub.toJSON(),appUrl:base()});
    if(g!==generation)return;await bind(uid,g);if(g!==generation)return;enabled=true;
   }else if(sub){await sub.unsubscribe();}
  }catch{if(g!==generation)return;try{await bind(null,g);}catch{}message='Push nu este conectat. Activează-l din nou când ai conexiune.';}paint();
 }
 async function disable(){
  // Hide all previously delivered notifications before any network request.
  enabled=false;await bind(null);const reg=await worker(),sub=await reg?.pushManager.getSubscription();
  if(sub){let failure;try{await api({action:'unsubscribe',endpoint:sub.endpoint});}catch(e){failure=e;}
   const removed=await sub.unsubscribe();if(!removed&&failure)throw failure;}
  enabled=false;
 }
 async function toggle(on){if(working||!user)return;const uid=user.id;working=true;message='';paint();
  // Permission request is made directly in the user's gesture, before any await.
  const permission=on?Notification.requestPermission():Promise.resolve(null);
  try{if(on){if(await permission!=='granted')throw Error('Permisiunea pentru notificări nu a fost acordată.');
    localStorage.setItem('mylist-push:'+uid,'on');await init();if(!enabled)throw Error(message||'Push nu a putut fi activat.');message='Notificări activate.';
   }else{localStorage.removeItem('mylist-push:'+uid);await disable();message='Notificări oprite pe acest dispozitiv.';}
  }catch(e){if(on){localStorage.removeItem('mylist-push:'+uid);try{await disable();}catch{}}message=e.message;}finally{working=false;paint();}
 }
 async function save(table,row){if(working||!user)return;working=true;message='';paint();const uid=user.id;try{const r=await sb.from(table).upsert({...row,user_id:uid});if(r.error)throw r.error;await refresh();message='Preferință salvată.';}catch{message='Preferința nu a fost salvată. Încearcă din nou.';}finally{working=false;paint();}}
 let archiveTarget=null;function revealArchive(){if(!archiveTarget)return;const el=document.querySelector('.push-archive-target');if(el){el.querySelector('details').open=true;el.scrollIntoView({block:'start'});archiveTarget=null;}}
 function openPendingList(){const url=new URL(location.href),id=url.searchParams.get('list');if(!id||!user)return;
  const recipient=url.searchParams.get('push_user');url.searchParams.delete('list');url.searchParams.delete('push_user');history.replaceState(null,'',url);if(recipient&&recipient!==user.id){toast('Notificarea aparține altui cont.');return;}
  const l=lists.find(l=>l.id===id);if(!l){toast('Lista nu mai este disponibilă pentru acest cont.');return;}
  selected=l.id;view=l.completed_at?'history':'lists';archiveTarget=l.completed_at?l.id:null;
 }
 async function clear(){generation++;owner=null;enabled=false;ready=false;prefs={item_toggled:false};listPrefs={};if(supported()){try{await bind(null);}catch{}}}
 async function logout(){generation++;if(owner)localStorage.removeItem('mylist-push:'+owner);if(supported()){try{await disable();}catch{try{await bind(null);}catch{}}}await clear();}
 window.addEventListener('load',()=>{if(supported())worker().then(r=>r?.update()).catch(()=>{});});
 navigator.serviceWorker?.addEventListener('message',e=>{if(e.data?.type==='MYLIST_OPEN_LIST'&&user){const u=new URL(e.data.url,location.href);if(u.origin!==location.origin)return;history.replaceState(null,'',u);openPendingList();render();}});
 return {settings,init,refresh,clear,logout,openPendingList,revealArchive,archiveId:()=>archiveTarget,toggle,preference:v=>save('mylist_push_preferences',{item_toggled:v}),listPreference:(id,v)=>save('mylist_push_list_preferences',{list_id:id,enabled:v})};
})();
