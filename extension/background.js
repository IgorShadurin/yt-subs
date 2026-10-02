let port;
let busy = false;
const HOST = 'com.ytsubs.studio';

async function closeOwnedTab(tabID, channelID) {
  try {
    const tab = await chrome.tabs.get(tabID);
    // If the user starts using or navigates this tab, leave it alone.
    const url = new URL(tab.url || tab.pendingUrl || 'about:blank');
    if (!tab.active && url.origin === 'https://studio.youtube.com' && url.pathname.replace(/\/$/, '') === `/channel/${channelID}`) {
      await chrome.tabs.remove(tabID);
    }
  } catch {}
}
async function cleanup() {
  const { owned } = await chrome.storage.session.get('owned');
  if (owned) await closeOwnedTab(owned.tabID, owned.channelID);
  await chrome.storage.session.remove('owned');
}
async function check(request) {
  if (busy || !/^[\w-]{36}$/.test(request.requestID || '') || !/^UC[\w-]{22}$/.test(request.channelID || '') || Date.now()/1000 - request.createdAt > 50) return;
  busy = true;
  const reply = {requestID: request.requestID, channelID: request.channelID};
  let tabID;
  try {
    // Never launch or focus a window. Defer checks if no regular Chrome window exists.
    const windows = await chrome.windows.getAll({windowTypes: ['normal']});
    const window = windows.find(w => w.focused) || windows[0];
    if (!window) throw new Error('Open a Chrome window to check YouTube Studio.');
    const tab = await chrome.tabs.create({windowId: window.id, url: `https://studio.youtube.com/channel/${request.channelID}`, active: false});
    tabID = tab.id;
    await chrome.storage.session.set({owned: {tabID, channelID: request.channelID}});
    await chrome.alarms.create('cleanup', {when: Date.now() + 45000});
    const deadline = Date.now() + 10000;
    while (Date.now() < deadline) {
      const state = await chrome.tabs.get(tabID);
      if (state.status === 'complete') break;
      await new Promise(resolve => setTimeout(resolve, 250));
    }
    const state = await chrome.tabs.get(tabID);
    if (!state.url?.startsWith(`https://studio.youtube.com/channel/${request.channelID}`)) throw new Error('Sign in to the channel in YouTube Studio, then retry.');
    const results = await chrome.scripting.executeScript({target: {tabId: tabID}, files: ['parser.js', 'reader.js']});
    const result = results[0]?.result;
    if (!result || result.channelID !== request.channelID || !/^\d+$/.test(result.count)) throw new Error('Exact counter not found. Check your Studio access and sign-in.');
    Object.assign(reply, result);
  } catch {
    reply.error = 'Could not read YouTube Studio. Check your connection, channel access, and Chrome sign-in.';
  } finally {
    if (tabID !== undefined) await closeOwnedTab(tabID, request.channelID);
    await chrome.storage.session.remove('owned');
    await chrome.alarms.clear('cleanup');
    busy = false;
    try { port?.postMessage(reply); } catch {}
    await chrome.storage.local.set({lastCheck: {at: Date.now(), count: reply.count, error: reply.error}});
  }
}
function connect() {
  if (port) return;
  port = chrome.runtime.connectNative(HOST);
  port.onMessage.addListener(check);
  port.onDisconnect.addListener(() => { void chrome.runtime.lastError; port = undefined; });
}
chrome.runtime.onInstalled.addListener(async () => {
  await cleanup();
  await chrome.alarms.create('reconnect', {periodInMinutes: 1});
  connect();
});
chrome.runtime.onStartup.addListener(async () => {
  await cleanup();
  await chrome.alarms.create('reconnect', {periodInMinutes: 1});
  connect();
});
chrome.alarms.onAlarm.addListener(async alarm => {
  if (alarm.name === 'cleanup') await cleanup();
  else connect();
});
connect();
