/* Runs in Chrome's isolated extension world; never reads cookies or page internals. */
globalThis.YTSubsReader = {
  count(text) {
    const normalized = String(text).trim().replace(/[٠-٩۰-۹]/g, c => String(c.charCodeAt(0) - (c <= '٩' ? 0x660 : 0x6f0)));
    // Accept whole digits or consistent thousands groups. Reject compact/decimal counts.
    if (!/^(?:[0-9]+|[0-9]{1,3}([,.\s\u00a0\u202f٬])[0-9]{3}(?:\1[0-9]{3})*)$/.test(normalized)) return null;
    const value = Number(normalized.replace(/[,\.\s\u00a0\u202f٬]/g, ''));
    return Number.isSafeInteger(value) && value >= 0 ? String(value) : null;
  },
  read(doc, url) {
    const match = new URL(url).pathname.match(/^\/channel\/(UC[\w-]{22})\/?$/);
    if (!match || new URL(url).origin !== 'https://studio.youtube.com') return null;
    const counter = doc.querySelector('ytcd-channel-facts-item .metric-value-big');
    const avatar = doc.querySelector('ytcp-navigation-drawer img.thumbnail');
    const channelLink = doc.querySelector('ytcp-navigation-drawer a#overlay-link-to-youtube');
    // Reject a redirect to another channel even if its counter is valid.
    if (!counter || !avatar || !channelLink || new URL(channelLink.href).pathname.replace(/\/$/, '') !== '/channel/' + match[1]) return null;
    const count = this.count(counter.textContent);
    const title = avatar.alt.trim();
    if (count === null || !title) return null;
    let avatarURL = null;
    try {
      const image = new URL(avatar.src);
      if (image.protocol === 'https:' && ['yt3.ggpht.com', 'yt3.googleusercontent.com'].includes(image.hostname)) avatarURL = image.href;
    } catch {}
    return {channelID: match[1], count, title: title.slice(0, 200), avatarURL};
  }
};
