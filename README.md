# YT Subs

A small native macOS menu bar app that keeps a YouTube channel's subscriber count beside the clock. Written in Swift, SwiftUI, and AppKit. Requires macOS 13 or later and Swift 6 / Xcode 16 or later to build. No external dependencies, server, or paid analytics service.

## Features

- Full numbers below 10,000 (`1,526`, `9,999`); compact numbers above (`10k`, `10.1k`, `1.2m`). Compact values truncate to one decimal place.
- Three green flashes for an increase or red flashes for a decrease, across two seconds. Initial data does not flash.
- Checks every minute by default. Choose a custom interval in minutes or hours.
- Failed requests retain the last successful count and retry after the configured interval, capped at ten minutes. No error popups or false zero counts.
- Setup opens on first launch or when the channel/key is missing. Settings persist; the API key stays in macOS Keychain.
- A popover shows the channel, last successful update, next check, and manual refresh.
- Checks resume after waking. macOS does not run polling while the computer is asleep.

## Subscriber precision

The app uses the official YouTube Data API v3 `channels.list` endpoint. **YouTube rounds subscriber counts down to three significant figures**, including between 1,000 and 9,999. For example, YouTube may return `1,520` for a channel with 1,526 subscribers. The app displays the real API value and does not invent the missing digits. Exact single-subscriber changes are observable below 1,000; larger channels flash only when the API's reported value changes. YouTube can also delay updates.

See [channel statistics](https://developers.google.com/youtube/v3/docs/channels#statistics.subscriberCount) and [channels.list](https://developers.google.com/youtube/v3/docs/channels/list).

## Build and run

```sh
swift test
./scripts/build-app.sh
open "dist/YT Subs.app"
```

You can also open `Package.swift` in Xcode. The build script creates a locally ad-hoc-signed app for the current Mac architecture. It is not notarized for public binary distribution. Copy the app to Applications if desired. To start at login, add it in System Settings → General → Login Items.

Click the menu bar icon → Settings to enter a channel ID or an HTTPS `/channel/` URL and your API key. Handle URLs are not supported. New installs have no bundled channel or API credential.

## Get a free YouTube API key

1. Sign into the [Google Cloud Console](https://console.cloud.google.com/).
2. Create a project, or select one you own.
3. Open **APIs & Services → Library**, find **YouTube Data API v3**, and enable it.
4. Open **APIs & Services → Credentials → Create credentials → API key**.
5. Give it a recognizable name. Under **API restrictions**, restrict it to **YouTube Data API v3**. A desktop app cannot use website referrer restrictions; leave application restrictions unset unless you configure a compatible fixed outbound IP restriction.
6. Copy the key into YT Subs Settings and choose **Save & Connect**. Do not commit it or share it in screenshots.

No paid service or billing setup is required for the standard YouTube Data API quota. One `channels.list` request costs one unit. A one-minute interval uses approximately 1,440 units per day, within the default 10,000-unit daily allowance for these endpoints. Other apps in the same Google project share its quota; manual refreshes consume additional units. Google can change quotas and access requirements.

Official references: [getting started and quota](https://developers.google.com/youtube/v3/getting-started), [credentials](https://developers.google.com/youtube/registering_an_application).

## Privacy and storage

The app sends the channel ID and API key directly to Google's HTTPS API. There is no telemetry or intermediary backend. The key is sent in a request header and stored only in Keychain, never in the repository or preferences. Channel settings and the last successful snapshot are stored in local preferences. Cached snapshots older than 30 days are not loaded. Quit the app before resetting its preferences. Removing the app does not automatically remove its Keychain item (`com.ytsubs.mac`, account `youtube-api-key`).

## Development

`YTSubsCore` contains formatting, channel validation, retry policy, and API decoding. Tests cover boundary values, invalid/missing/hidden counts, legitimate zero counts, and retry timing. `YTSubs` owns native UI, lifecycle, polling, and Keychain persistence. Requests are cancelled and guarded against stale results when settings change.
