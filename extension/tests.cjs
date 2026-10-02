const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
require('./parser.js');

test('whole counts, separators, zero, and localized digits', () => {
  for (const [text, result] of [['1,526','1526'],['9 999','9999'],['1.526','1526'],['1\u202f526','1526'],['١٬٥٢٦','1526'],['0','0'],['1234567','1234567']]) {
    assert.equal(YTSubsReader.count(text),result);
  }
  for (const text of ['1.52K','1.52','1,52','1,234.567','—','-1','', 'Infinity', '9007199254740992']) assert.equal(YTSubsReader.count(text),null);
});
test('only the selected channel and specific subscriber card are accepted', () => {
  const id = 'UCabcdefghijklmnopqrstuv';
  const elements = {
    'ytcd-channel-facts-item .metric-value-big': {textContent:'1,526'},
    'ytcp-navigation-drawer img.thumbnail': {alt:'Channel',src:'https://yt3.ggpht.com/a'},
    'ytcp-navigation-drawer a#overlay-link-to-youtube': {href:`https://youtube.com/channel/${id}/`}
  };
  const doc = {querySelector:s => elements[s]};
  assert.equal(YTSubsReader.read(doc,`https://studio.youtube.com/channel/${id}`).count,'1526');
  assert.equal(YTSubsReader.read(doc,`https://studio.youtube.com/channel/UCxxxxxxxxxxxxxxxxxxxxxx`),null);
  elements['ytcd-channel-facts-item .metric-value-big'].textContent='1.52k';
  assert.equal(YTSubsReader.read(doc,`https://studio.youtube.com/channel/${id}`),null);
});
function harness({fail = false, tabActive = false, navigated = false} = {}) {
  const events = [], messages = [], storage = {};
  const hook = {addListener:()=>{}};
  const chrome = {
    runtime: {connectNative:()=>({onMessage:hook,onDisconnect:hook,postMessage:r=>messages.push(r)}), onInstalled:hook,onStartup:hook},
    windows:{getAll:async()=>[{id:5,focused:true}]},
    tabs:{create:async options=>{events.push(['create',options]);return{id:44}}, get:async()=>({status:'complete',active:tabActive,url:navigated?'https://example.com':`https://studio.youtube.com/channel/UCabcdefghijklmnopqrstuv`}),remove:async id=>events.push(['remove',id])},
    storage:{session:{get:async()=>storage,set:async v=>Object.assign(storage,v),remove:async k=>delete storage[k]},local:{set:async()=>{}}},
    alarms:{create:async()=>{},clear:async()=>{},onAlarm:hook},
    scripting:{executeScript:async()=>{if(fail)throw Error('network');return[{result:{channelID:'UCabcdefghijklmnopqrstuv',count:'1526',title:'Channel'}}]}}
  };
  const context=vm.createContext({chrome,URL,setTimeout,console});
  vm.runInContext(fs.readFileSync(__dirname+'/background.js','utf8'),context);
  return {events,messages,run:()=>vm.runInContext('check({requestID:"11111111-1111-1111-1111-111111111111",channelID:"UCabcdefghijklmnopqrstuv",createdAt:Date.now()/1000})',context)};
}
test('background checks never activate tabs and close only their own tab',async()=>{
  const h=harness();await h.run();assert.equal(h.events[0][1].active,false);assert.deepEqual(h.events[1],['remove',44]);assert.equal(h.messages[0].count,'1526');
});
test('failures close owned tab and report an error without a fabricated count',async()=>{
  const h=harness({fail:true});await h.run();assert.deepEqual(h.events[1],['remove',44]);assert.ok(h.messages[0].error);assert.equal(h.messages[0].count,undefined);
});
test('user-activated or navigated tabs are never closed',async()=>{
  for(const options of [{tabActive:true},{navigated:true}]) { const h=harness(options);await h.run();assert.equal(h.events.filter(e=>e[0]==='remove').length,0); }
});
