# Mailpit Menubar

A tiny native macOS menubar app for [Mailpit](https://mailpit.axllent.org). It listens to
Mailpit's event stream and posts a macOS notification whenever a new message arrives.
Clicking the notification opens that message in Mailpit's web UI.

The menubar icon shows the unread count and drops down a list of recent messages, each of
which opens in the browser.

## Requirements

- macOS 14 or later
- Xcode 16+ command line tools (Swift 6)
- Mailpit running somewhere reachable (default `http://localhost:8025`)

## Build and run

```sh
make run        # builds a release binary, wraps it in an .app bundle and launches it
make install    # same, but copies the bundle to /Applications first
```

Notifications only work from a real `.app` bundle, so `swift run` on its own will not show
them. Always launch via `make run`, `make install`, or by opening the bundle in `build/`.

On first launch macOS asks whether to allow notifications from Mailpit Menubar. If you
dismissed that, enable it under System Settings → Notifications.

## Usage

- **Open Mailpit** (⌘O) opens the web UI.
- Recent messages appear in the menu. Unread ones are bold with a dot. Click one to view it.
- **Mark All as Read** calls Mailpit's API to clear the unread state.
- **Mailpit URL…** (⌘,) changes the base URL, e.g. if Mailpit runs in Docker on another port or
  behind a webroot such as `http://localhost:8025/mailpit`.
- **Launch at Login** registers the app as a login item. This works best once it is installed
  in `/Applications`.
- **Check for Updates…** asks Sparkle to check the release feed now. Sparkle also checks on
  launch once you have allowed automatic checks.

## How it works

The app opens a websocket to `/api/events`. Mailpit sends a `new` event for each message and
`stats` events with the total and unread counts. If the socket drops (say, Mailpit restarts)
the app reconnects with exponential backoff and re-syncs the recent list via
`/api/v1/messages`, notifying about anything that arrived while it was disconnected.

## Releasing

Updates ship through [Sparkle](https://sparkle-project.org) from GitHub Releases: the app reads
`SUFeedURL` from `Resources/Info.plist`, which points at the `appcast.xml` asset on the latest
release, and installs whatever it advertises after verifying the EdDSA signature against
`SUPublicEDKey`.

1. Bump `CFBundleShortVersionString` and `CFBundleVersion` in `Resources/Info.plist`. Sparkle
   compares `CFBundleVersion`, so it must increase every release.
2. Commit, then run `Scripts/release.sh`. It builds with the Developer ID identity and hardened
   runtime, notarizes and staples the app, wraps it in a DMG, notarizes that too, runs
   `generate_appcast` over `releases/` (kept locally so delta updates can be produced), and
   creates a `v<version>` GitHub release carrying the DMG, any deltas, and `appcast.xml`.

One-time prerequisites are listed in the script header (Developer ID certificate, `notarytool`
keychain profile, Sparkle EdDSA key in the login Keychain, `gh` signed in with push access).

`make bundle` on its own signs ad hoc, which is fine for local use; Sparkle will not install
updates over an ad-hoc build because the signatures do not match the published one.

## License

MIT. See [LICENSE](LICENSE).
