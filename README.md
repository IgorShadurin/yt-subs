# YT Subs

A native Swift macOS menu bar app for YouTube subscriber counts. Choose **YouTube Studio via Chrome** for exact counts or **YouTube Data API** for rounded public counts. Requires macOS 13+; builds with Swift 6 / Xcode 16+. No server or paid analytics service.

## Features

- Menu bar: `1,526` below 10,000, then `10.1k`, `1.2m`, etc. The popover always shows the full number received.
- Every increase, even one subscriber, starts a 30-second green pulse in the menu bar and a green count with a pulsing outline in the popup. Another increase restarts the 30 seconds. Decreases flash red three times over two seconds. First readings and switching channels or data sources do not animate.
- One-minute checks by default, or a custom interval in minutes/hours.
- Channel name and avatar are fetched automatically for either source. Metadata persists locally; avatar images are cached on disk by channel, reused across launches, and refreshed when their URL changes or after 24 hours. Switching channels clears the previous channel's display.
- An opaque, readable popover shows the channel, source, subscriber count, last successful update, and next check. Click **YouTube Studio** to open the configured channel in your default browser.
- Failed checks show a red error with the attempt time, keep the last successful count, and retry after the configured interval capped at ten minutes.
- Checks resume after waking. Polling pauses while the Mac sleeps.

## Build

```sh
swift test
node --test extension/tests.cjs
./scripts/build-app.sh
open "dist/YT Subs.app"
```

For a stable installation in your user Applications folder, run `./scripts/install-app.sh`. Launch that installed copy before enabling launch at login.

The script builds an ad-hoc-signed app for the current Mac's architecture. The app is not notarized for public binary distribution. You can open `Package.swift` in Xcode or copy the resulting app to Applications. For a separate dashboard window, launch with `open "dist/YT Subs.app" --args --dashboard`; `--settings` opens settings at launch. Enable **Launch YT Subs at login** in Settings to start automatically after signing into your Mac. This uses macOS Login Items; disabling the toggle unregisters it. The blue **Update now** button fetches the latest count immediately without waiting for the scheduled check. Chrome must still be running for Studio checks.

## Exact counts: Chrome + YouTube Studio

1. Build the app and run `./scripts/install-bridge.sh`. This installs the local Swift native-messaging host for Google Chrome.
2. In Chrome, open `chrome://extensions`, enable **Developer mode**, click **Load unpacked**, and select this repository's `extension` folder. Keep that folder in place. Its ID is fixed by the public key in its manifest.
3. Sign into the correct channel in [YouTube Studio](https://studio.youtube.com/) using the same Chrome profile as the extension.
4. In YT Subs Settings, choose **YouTube Studio (exact)**, enter a channel ID or HTTPS `/channel/` URL, and save.

Chrome must be running with at least one regular window (it can be minimized). Studio does **not** need to remain open. Each check creates an inactive Studio dashboard tab, reads the rendered current-subscriber count, channel name, and avatar URL, then closes that tab. The tab can briefly appear in the tab strip. The extension does not click, type, change the clipboard, focus windows, or activate tabs. If you select its temporary tab or navigate it elsewhere, cleanup leaves it alone.

The extension uses your existing Chrome sign-in without copying cookies, passwords, or tokens. It requests access only to `studio.youtube.com`, script injection there, local extension storage, timers, and its native-messaging connector. No general browsing-history or cookie permission is requested. Use one Chrome profile for this integration.

If you are signed out, have the wrong channel permissions, lose connectivity, or Studio changes its markup, the app retains the previous count and shows an error. The extension does not silently replace an exact count with the public rounded API count. Exact means the value Studio displays at the successful check; it is not a guarantee of instantaneous updates between checks.

### Extension maintenance

After updating extension files, click **Reload** on its card in `chrome://extensions`. After updating native bridge code, rerun `./scripts/install-bridge.sh` and reload the extension. The bridge launches when the extension connects and shuts down when Chrome closes its connection. Requests originate in the app; the extension reconnects automatically if needed. Disable/remove the extension to stop its Chrome integration.

The connector lives in `~/Library/Application Support/YT Subs/YTSubsBridge`; its Chrome registration is `~/Library/Application Support/Google/Chrome/NativeMessagingHosts/com.ytsubs.studio.json`. Removing these files after disabling the extension uninstalls the connector.

## Public counts: free YouTube API key

1. Sign into the [Google Cloud Console](https://console.cloud.google.com/), and create or select a project.
2. Under **APIs & Services → Library**, enable **YouTube Data API v3**.
3. Under **Credentials → Create credentials → API key**, create a key.
4. Restrict it to **YouTube Data API v3**. Desktop requests cannot use website referrer restrictions; leave application restrictions unset unless using a compatible fixed outbound IP restriction.
5. In app Settings choose **YouTube API (rounded)** and paste the key. It is saved in macOS Keychain.

The standard quota requires no paid analytics service or billing setup. `channels.list` costs one unit: a one-minute interval uses approximately 1,440 units/day within the default 10,000-unit allowance for these endpoints. Other apps in the project and manual refreshes share the quota.

**YouTube rounds API counts down to three significant figures**, including 1,000–9,999. Thus Studio may show 1,526 while the API returns 1,520. OAuth does not provide a documented unrounded version of this field. Use Studio mode for individual subscriber changes.

References: [subscriber-count precision](https://developers.google.com/youtube/v3/docs/channels#statistics.subscriberCount), [quota](https://developers.google.com/youtube/v3/getting-started), [credentials](https://developers.google.com/youtube/registering_an_application), [Chrome native messaging](https://developer.chrome.com/docs/extensions/develop/concepts/native-messaging).

## Privacy and local storage

No telemetry or intermediary backend. API mode sends its key directly to Google's HTTPS API in a request header. Studio mode reads only the selected channel's visible dashboard metadata and sends it locally through Chrome native messaging. Avatars are downloaded automatically from YouTube image hosts.

Settings and the most recent successful snapshot are stored in local preferences. Avatar files live in `~/Library/Caches/com.ytsubs.mac/avatars`. Bridge requests and responses live in `~/Library/Application Support/YT Subs/Bridge` with user-only permissions. API credentials remain in Keychain (`com.ytsubs.mac`, account `youtube-api-key`), never in preferences or source control. Removing the app does not remove that Keychain item. Public installs have no bundled channel, key, or personal data.

## Tests

Swift tests cover count formatting, channel validation, retry policy, API parsing, old-cache migration, exact response validation, stale requests, and wrong channels. Node tests cover locale separators, rejection of compact counts, exact DOM selectors, inactive tab creation, cleanup on failure, and preserving user-selected/navigated tabs. Live Studio integration additionally requires the unpacked extension and an authorized Chrome session.
