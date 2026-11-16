export function validSubscription(sub:any){try{
 const u=new URL(sub.endpoint),h=u.hostname;
 return u.protocol==='https:'&&!u.port&&!u.username&&!u.password&&!u.hash&&u.href.length<2048
 &&(h==='web.push.apple.com'||h.endsWith('.push.apple.com')||h==='fcm.googleapis.com'||h==='updates.push.services.mozilla.com'||h.endsWith('.notify.windows.com'))
 &&/^[A-Za-z0-9_-]{87}=?$/.test(sub.keys?.p256dh)&&/^[A-Za-z0-9_-]{22}={0,2}$/.test(sub.keys?.auth);
}catch{return false;}}
export function validAppUrl(value:string){try{const u=new URL(value);return !u.search&&!u.hash&&!u.username&&!u.password&&((u.origin==='https://anzosafe-oss.github.io'&&u.pathname==='/mylist/')||(u.origin==='https://mylist-anzo-preview.zota-andrei.chatgpt.site'&&u.pathname==='/'));}catch{return false;}}
export function notificationBody(job:any){
 if(job.kind==='list_shared')return 'Ai acces la o listă partajată.';
 if(job.kind==='list_completed')return 'Toate produsele au fost cumpărate. Lista este în Istoric.';
 if(job.kind==='item_toggled')return job.event_count===1?'Un produs a fost bifat sau debifat.':`${job.event_count} produse au fost bifate sau debifate.`;
 return job.event_count===1?`${job.last_name} a fost adăugat pe listă.`:`${job.event_count} produse adăugate · ${job.last_name}`;
}
