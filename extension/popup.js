chrome.runtime.sendMessage({action: 'reconnect'}).catch(() => {});
chrome.storage.local.get('lastCheck').then(({lastCheck}) => {
  if (!lastCheck) return;
  const el = document.getElementById('status');
  el.textContent = lastCheck.error || `${Number(lastCheck.count).toLocaleString()} subscribers · ${new Date(lastCheck.at).toLocaleTimeString()}`;
  if (lastCheck.error) el.style.color = '#b42318';
});
