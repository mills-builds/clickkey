# ClickKey

A tiny, open-source macOS menu-bar app that remaps extra mouse buttons to keystrokes or media keys: a minimal alternative to SteerMouse for people who only need button → key.

- Map middle, back, forward and any extra button to **Return, Escape, Tab, Space, Delete, ⌘C, ⌘V, ⌘Z, ⇧⌘Z**, any recorded shortcut, or **Play/Pause, Next, Previous, Volume Up/Down, Mute**
- Mapped buttons are swallowed (down and up), so the app underneath never sees the click
- Per-mapping toggles, a global on/off switch in the menu bar, and launch at login
- macOS 13 Ventura or later, Apple silicon or Intel

## Example: Wispr Flow

[Wispr Flow](https://wisprflow.ai) lets you dictate with a mouse button. Here's a setup that works well with ClickKey:

| Mouse button | What it does |
|---|---|
| Button 3 (Middle) | Hold to dictate with Wispr Flow (set this up in Wispr; don't map it in ClickKey) |
| Button 4 (Back) | **Return** via ClickKey, to submit what you just dictated |

So you dictate with one thumb and send with the other, without touching the keyboard.

## Install

1. Build it (see [Building from source](#building-from-source)), e.g. `scripts/build.sh /Applications`.
2. Open **ClickKey.app**. A mouse icon appears in the menu bar. There's no Dock icon.
3. Grant Accessibility access when prompted (see below).
4. Open the menu bar icon → **Settings…** → **Add Mapping…**, press a mouse button, then choose an action.

## Accessibility permission

ClickKey uses a `CGEventTap` to see mouse button presses and post keystrokes, and macOS requires **Accessibility** access for that. On first launch an onboarding window explains this and offers **Open System Settings**. Turn ClickKey on under *Privacy & Security → Accessibility*. ClickKey checks once per second and starts working as soon as access is granted. You don't need to relaunch.

### After rebuilding or updating

The build is ad-hoc signed, so **every rebuild produces a new code signature** and macOS stops honoring the old grant, even though ClickKey still shows as enabled in the list. If mappings stop working after a rebuild:

1. Open *System Settings → Privacy & Security → Accessibility*.
2. Select ClickKey and remove it with **–**.
3. Add it again with **+** (or relaunch ClickKey and click **Open System Settings**), then switch it on.

## Conflicts with other remappers

Only one tool should handle a given button. If you also run SteerMouse, BetterTouchTool, Karabiner-Elements, Logi Options+, or a home-made event tap (for example an old **LaunchAgent** running a prototype script), that tool may grab the button first, or both may fire. Remove or disable the other mapping. To look for leftover agents:

```sh
ls ~/Library/LaunchAgents
launchctl list | grep -i <name>
launchctl bootout gui/$(id -u) ~/Library/LaunchAgents/<name>.plist
```

## Building from source

Requires macOS 13+ and Xcode or the Command Line Tools (Swift 5.9+).

```sh
scripts/build.sh                       # -> build/ClickKey.app (arm64)
scripts/build.sh /Applications         # build and copy to /Applications (or DEST=/Applications)
ARCH=x86_64 scripts/build.sh           # Intel; ARCH=universal for both
```

The script runs `swift build -c release`, assembles `ClickKey.app` with `Resources/Info.plist` (`LSUIElement`, bundle ID `com.millsbuilds.clickkey`), and ad-hoc signs it with `codesign -s -`.

For development, `swift run` also works, but run the bundled app if you want permissions and launch at login to behave as they will for real use.

### Screenshots without Screen Recording permission

```sh
build/ClickKey.app/Contents/MacOS/ClickKey --snapshot ./shots
```

This renders the Settings view (with sample mappings) and the onboarding view to PNG at 2× and then exits. It writes `settings.png` and `onboarding.png` using `ImageRenderer`, plus `*-appkit.png` drawn from an offscreen `NSHostingView`. The second set exists because `ImageRenderer` can't draw some native controls.

## Privacy

ClickKey runs entirely on your Mac. It makes **no network connections** and has **no telemetry, analytics, or crash reporting**. Your mappings are stored in `UserDefaults` (`com.millsbuilds.clickkey`). The event tap only listens for non-left/right mouse button events and never sees what you type.

## License

MIT © 2026 mills-builds. See [LICENSE](LICENSE).
