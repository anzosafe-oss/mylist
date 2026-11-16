import {test} from 'node:test';import assert from 'node:assert/strict';
import {validSubscription,validAppUrl,notificationBody} from '../supabase/functions/mylist-push/logic.ts';
const sub=host=>({endpoint:'https://'+host+'/token',keys:{p256dh:'B'.repeat(87),auth:'a'.repeat(22)}});
test('only supported HTTPS push providers; reject SSRF and malformed keys',()=>{
 for(const host of ['fcm.googleapis.com','web.push.apple.com','foo.push.apple.com','updates.push.services.mozilla.com','wns.notify.windows.com'])assert.equal(validSubscription(sub(host)),true,host);
 for(const host of ['127.0.0.1','169.254.169.254','fcm.googleapis.com.evil.test','evil.test'])assert.equal(validSubscription(sub(host)),false,host);
 assert.equal(validSubscription({...sub('fcm.googleapis.com'),endpoint:'http://fcm.googleapis.com/a'}),false);
 assert.equal(validSubscription({...sub('fcm.googleapis.com'),endpoint:'https://user:pass@fcm.googleapis.com/a'}),false);
 assert.equal(validSubscription({...sub('fcm.googleapis.com'),keys:{auth:'x',p256dh:'x'}}),false);
});
test('notification links restricted to MyList roots',()=>{
 assert.equal(validAppUrl('https://anzosafe-oss.github.io/mylist/'),true);
 assert.equal(validAppUrl('https://mylist-anzo-preview.zota-andrei.chatgpt.site/'),true);
 for(const u of ['https://evil.test/','https://anzosafe-oss.github.io/mycar/','https://anzosafe-oss.github.io/mylist/?token=secret','https://user@anzosafe-oss.github.io/mylist/'])assert.equal(validAppUrl(u),false,u);
});
test('Romanian payloads for four events and grouped additions',()=>{
 assert.match(notificationBody({kind:'item_added',event_count:1,last_name:'Lapte'}),/Lapte/);
 assert.match(notificationBody({kind:'item_added',event_count:3,last_name:'Ouă'}),/3 produse/);
 assert.match(notificationBody({kind:'list_shared'}),/acces/);
 assert.match(notificationBody({kind:'list_completed'}),/Istoric/);
 assert.match(notificationBody({kind:'item_toggled',event_count:2}),/2 produse/);
});
