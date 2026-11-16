/* MyList Push: subscription starts inside the user's click, including on iOS. */
const MyListPush=(()=>{
 const defaults={item_added:true,list_shared:true,list_completed:true,item_toggled:false};
 const events=[['item_added','Produse adăugate'],['list_shared','Listă partajată'],['list_completed','Listă finalizată'],['item_toggled','Produse bifate / debifate']];
 let registration=null,owner=null,enabled=false,working=false,ready=false,message='',prefs={...defaults},listPrefs={},generation=0;
 let deviceReady=false,preparing=false,publicKey=null,pending=null,prepareTask=null;
 const supported=()=>isSecureContext&&'serviceWorker'in navigator&&'Notification'in window;
 const ios=()=>/iPad|iPhone|iPod/.test(navigator.userAgent)||(navigator.platform==='MacIntel'&&navigator.maxTouchPoints>1);
 const standalone=()=>matchMedia('(display-mode: standalone)').matches||navigator.standalone===true;
 const base=()=>new URL('./',location.href).href;
 const opted=uid=>localStorage.getItem('mylist-push:'+uid)==='on';
 function paint(){const el=document.getElementById('pushSettings');if(el)el.outerHTML=settings();}
 function settings(){
  const available=supported()&&(!ios()||standalone());
  const hint=ios()&&!standalone()?'Pe iPhone/iPad, deschide MyList din iconul de pe ecranul principal.':!supported()?'Notificările Push nu sunt disponibile în acest browser.':Notification.permission==='denied'?'Notificările sunt blocate. Permite-le din setările browserului sau ale telefonului.':'Fiecare eveniment activat produce o notificare separată, inclusiv când MyList este închisă.';
  const badgeHint=/Android/i.test(navigator.userAgent)?'<p>Pe Android, bulina de pe iconiță este controlată de browser și de setările ecranului principal.</p>':'';
  const sharedLists=typeof lists==='undefined'?[]:lists.filter(l=>shared(l));
  return `<div class="settings-section" id="pushSettings"><h3>Notificări</h3><label class="setting-row"><span>Push pe acest dispozitiv</span><input type="checkbox" aria-label="Push pe acest dispozitiv" ${(pending??enabled)?'checked':''} ${!available||working||preparing||!deviceReady?'disabled':''} onclick="MyListPush.toggle(this.checked)"></label><p>${esc(hint)}</p>${badgeHint}<p class="push-message" role="status" aria-live="polite">${esc(preparing?'Se pregătesc notificările…':message)}</p>${available&&!deviceReady&&!preparing?'<button type="button" class="outline" onclick="MyListPush.init()">Reîncearcă activarea</button>':''}${ready?events.map(([kind,label])=>`<label class="setting-row"><span>${label}</span><input type="checkbox" aria-label="${label}" ${prefs[kind]?'checked':''} ${working?'disabled':''} onchange="MyListPush.preference('${kind}',this.checked)"></label>`).join('')+(sharedLists.length?'<p>Liste partajate</p>'+sharedLists.map(l=>`<label class="setting-row"><span class="push-list-name">${esc(l.name)}</span><input type="checkbox" aria-label="Notificări pentru ${esc(l.name)}" ${listPrefs[l.id]!==false?'checked':''} ${working?'disabled':''} onchange="MyListPush.listPreference('${l.id}',this.checked)"></label>`).join(''):'<p>Listele partajate vor apărea aici.</p>'):''}</div>`;
 }
 async function api(body){let timer;try{
  const r=await Promise.race([sb.functions.invoke('mylist-push',{body}),new Promise((_,reject)=>{timer=setTimeout(()=>reject(Error('Conexiunea a durat prea mult. Încearcă din nou.')),15000);})]);
  if(r.error){let text='Notificările nu au putut fi actualizate.';try{text=(await r.error.context.json()).error||text;}catch{}throw Error(text);}return r.data;
 }finally{clearTimeout(timer);}}
 let workerTask=null;async function worker(){if(!supported())return null;
  if(!workerTask)workerTask=(async()=>{registration=await navigator.serviceWorker.register('./sw.js',{updateViaCache:'none'});const update=registration.installing||registration.waiting;
   if(update&&update.state!=='activated')await new Promise((resolve,reject)=>{const timer=setTimeout(()=>reject(Error('Workerul se actualizează. Reîncearcă activarea.')),10000);const check=()=>{if(update.state==='activated'){clearTimeout(timer);resolve();}else if(update.state==='redundant'){clearTimeout(timer);reject(Error('Actualizarea notificărilor nu a reușit.'));}};update.addEventListener('statechange',check);check();});
   return navigator.serviceWorker.ready;})().catch(e=>{workerTask=null;throw e;});return workerTask;}
 async function bind(uid,expected=generation){const reg=await worker();if(!reg||expected!==generation)return;const sw=reg.active;if(!sw)throw Error('Notificările se pregătesc. Încearcă din nou.');
  await new Promise((resolve,reject)=>{const channel=new MessageChannel(),timer=setTimeout(()=>{channel.port1.close();reject(Error('Notificările nu sunt pregătite.'));},5000);channel.port1.onmessage=()=>{clearTimeout(timer);channel.port1.close();resolve();};sw.postMessage({type:'MYLIST_PUSH_ACCOUNT',userId:uid},[channel.port2]);});}
 function keyBytes(key){const raw=atob(key.replace(/-/g,'+').replace(/_/g,'/'));return Uint8Array.from(raw,c=>c.charCodeAt(0));}
 async function refresh(){if(!user)return;const uid=user.id;try{
  const result=await Promise.all([sb.from('mylist_push_preferences').select('*').eq('user_id',uid).maybeSingle(),sb.from('mylist_push_list_preferences').select('list_id,enabled').eq('user_id',uid)]);
  for(const r of result)if(r.error)throw r.error;if(user?.id!==uid)return;
  prefs={...defaults,...result[0].data};listPrefs=Object.fromEntries(result[1].data.map(p=>[p.list_id,p.enabled]));ready=true;
 }catch{if(user?.id!==uid)return;message='Setările notificărilor nu sunt încă disponibile.';ready=false;}paint();}
 function failure(e){if(e?.name==='NotAllowedError')return Notification.permission==='denied'?'Notificările sunt blocate. Permite-le din setările telefonului.':'Activarea nu a fost permisă. Apasă din nou și acceptă notificările.';return e?.message||'Notificările nu au putut fi activate.';}
 function init(){if(working)return Promise.resolve();if(prepareTask&&owner===user?.id)return prepareTask;
  const task=prepare().finally(()=>{if(prepareTask===task)prepareTask=null;});prepareTask=task;return task;
 }
 async function prepare(){if(!user)return;const uid=user.id,g=++generation;owner=uid;enabled=false;deviceReady=false;preparing=true;message='';paint();
  try{
   await refresh();if(g!==generation)return;
   if(!supported()||(ios()&&!standalone()))return;
   const [reg,c]=await Promise.all([worker(),api({action:'config'})]);if(g!==generation)return;
   if(!reg?.pushManager?.subscribe)throw Error('Acest browser nu oferă abonare Push.');
   publicKey=c.publicKey;let sub=await reg.pushManager.getSubscription();if(g!==generation)return;
   const stored=sub?.options?.applicationServerKey;
   if(stored&&btoa(String.fromCharCode(...new Uint8Array(stored))).replace(/\+/g,'-').replace(/\//g,'_').replace(/=+$/,'')!==publicKey){await sub.unsubscribe();sub=null;}
   if(opted(uid)&&Notification.permission==='granted'&&sub){
    await api({action:'subscribe',subscription:sub.toJSON(),appUrl:base()});if(g!==generation)return;
    await bind(uid,g);if(g!==generation)return;enabled=true;await markRead();
   }else{
    await bind(null,g);if(sub)await sub.unsubscribe();
    if(opted(uid))message='Apasă pentru a reactiva Push pe acest dispozitiv.';
   }
   if(g===generation)deviceReady=true;
  }catch(e){if(g!==generation)return;message=failure(e);try{await bind(null,g);}catch{}}
  finally{if(g===generation){preparing=false;paint();}}
 }
 async function disable(){
  enabled=false;await bind(null);const reg=await worker(),sub=await reg?.pushManager.getSubscription();
  if(sub){let error;try{await api({action:'unsubscribe',endpoint:sub.endpoint});}catch(e){error=e;}
   const removed=await sub.unsubscribe();if(!removed&&error)throw error;}
 }
 async function toggle(on){if(working||preparing||!user)return;const uid=user.id,g=generation;working=true;pending=on;message=on?'Se activează notificările…':'Se opresc notificările…';
  try{
   if(on){
    if(!deviceReady||!registration?.pushManager||!publicKey)throw Error('Notificările se pregătesc. Reîncearcă activarea.');
    // This call MUST run synchronously inside the click. subscribe() itself requests permission.
    // No requestPermission(), network call, DOM replacement or await precedes it.
    const subscribing=registration.pushManager.subscribe({userVisibleOnly:true,applicationServerKey:keyBytes(publicKey)});
    paint();const sub=await subscribing;if(g!==generation||user?.id!==uid)return;
    await api({action:'subscribe',subscription:sub.toJSON(),appUrl:base()});if(g!==generation)return;
    await bind(uid,g);if(g!==generation)return;
    localStorage.setItem('mylist-push:'+uid,'on');enabled=true;await markRead();message='Notificări activate.';
   }else{paint();localStorage.removeItem('mylist-push:'+uid);await disable();message='Notificări oprite pe acest dispozitiv.';}
  }catch(e){if(g!==generation)return;if(on){localStorage.removeItem('mylist-push:'+uid);try{await disable();}catch{}}message=failure(e);}
  finally{if(g===generation){working=false;pending=null;paint();}}
 }
 async function save(table,row){if(working||!user)return;working=true;message='';paint();const uid=user.id;try{const r=await sb.from(table).upsert({...row,user_id:uid});if(r.error)throw r.error;if(user?.id!==uid)return;await refresh();message='Preferință salvată.';}catch{if(user?.id===uid)message='Preferința nu a fost salvată. Încearcă din nou.';}finally{working=false;paint();}}
 let archiveTarget=null;function revealArchive(){if(!archiveTarget)return;const el=document.querySelector('.push-archive-target');if(el){el.querySelector('details').open=true;el.scrollIntoView({block:'start'});archiveTarget=null;}}
 function openPendingList(){const url=new URL(location.href),id=url.searchParams.get('list');if(!id||!user)return;
  const recipient=url.searchParams.get('push_user');url.searchParams.delete('list');url.searchParams.delete('push_user');history.replaceState(null,'',url);if(recipient&&recipient!==user.id){toast('Notificarea aparține altui cont.');return;}
  const l=lists.find(l=>l.id===id);if(!l){toast('Lista nu mai este disponibilă pentru acest cont.');return;}
  selected=l.id;view=l.completed_at?'history':'lists';archiveTarget=l.completed_at?l.id:null;
 }
 async function markRead(){if(!user||document.visibilityState==='hidden')return;try{const reg=await worker();if(user&&enabled)reg?.active?.postMessage({type:'MYLIST_PUSH_READ',userId:user.id});if(navigator.clearAppBadge)await navigator.clearAppBadge();}catch{}}
 async function clear(){generation++;owner=null;enabled=false;ready=false;prefs={...defaults};listPrefs={};working=false;pending=null;preparing=false;deviceReady=false;publicKey=null;if(supported()){try{await bind(null);}catch{}}}
 async function logout(){generation++;if(owner)localStorage.removeItem('mylist-push:'+owner);if(supported()){try{await disable();}catch{try{await bind(null);}catch{}}}await clear();}
 document.addEventListener('visibilitychange',()=>{if(document.visibilityState==='visible'&&user&&enabled)markRead();});
 window.addEventListener('online',()=>{if(user&&!working)init();});
 window.addEventListener('load',()=>{if(supported())worker().then(r=>r?.update()).catch(()=>{});});
 navigator.serviceWorker?.addEventListener('message',e=>{if(e.data?.type==='MYLIST_OPEN_LIST'&&user){const u=new URL(e.data.url,location.href);if(u.origin!==location.origin)return;history.replaceState(null,'',u);openPendingList();render();}});
 return {settings,init,refresh,clear,logout,openPendingList,markRead,revealArchive,archiveId:()=>archiveTarget,toggle,preference:(kind,v)=>{if(events.some(e=>e[0]===kind))return save('mylist_push_preferences',{...Object.fromEntries(events.map(([key])=>[key,!!prefs[key]])),[kind]:v})},listPreference:(id,v)=>save('mylist_push_list_preferences',{list_id:id,enabled:v})};
})();
