# Quickshell config: Dynamic Island style top bar

QML shell for Quickshell 0.3 on niri (Wayland, Fedora). Entry point: `shell.qml`.
One island at the top of the screen that morphs between modes, designed to feel like Apple's Dynamic Island.
Everything shows in it: panels the user opens (battery, Wi-Fi, Bluetooth, search, time) and activities (volume, brightness,
microphone, messages, notifications, alerts; it replaced swayosd and mako). Activity queues them and picks one by
priority (`island.priority`): what the user does interrupts what the system does. (A separate "drop" island +
liquid shader existed before; it was removed on purpose, don't bring it back.)

## Non-negotiable rules (read first)

1. **Every value is a setting** (described in `config/schema.json`, listed in `config/config.jsonc`). Sizes, paddings, gaps, colors, opacities, durations,
   delays, springs, counts, text sizes, icon names, formats, thresholds: if it's a number, color or string
   that shapes how something looks or behaves, it comes from `Config.<section>.<key>`, never a literal in QML.
   When in doubt, expose it. The user wants everything customizable.
2. **Every setting gets a description in `config/schema.json`, in the same change.** No exceptions, including
   small tweaks and settings added while fixing something else. The entry needs `key`, `label`, a plain-language
   `description` (what the user sees change, written for a non-developer), `type`, `default` (the shipped
   value: the schema holds the defaults), `min`/`max`/`step`/`unit` for numbers, `"advanced": true` for technical knobs, and the
   right section/group. Renaming or removing a setting means updating the schema, then
   `python3 tools/check-config.py --rewrite`.
3. **Run `python3 tools/check-config.py` before you finish.** It must print `OK`. It fails on undocumented
   values, out-of-range values, QML reading a `Config` path that isn't in the schema, a schema section not
   exposed in `services/Config.qml`, a setting missing from config.jsonc (or listed there with a stale commented
   default), and an SVG icon Icon can't draw (transform, stroke, non-path shape).
4. **Notify the user when you're done** with a task: send a notification to the running island, the
   desktop's notification server (`notify-send -a "Claude Code" "Done" "<one line: what changed>"`). Every
   time, at the very end, after the checks pass.

The only literals allowed in QML: 0 / 1 / 0.5-style maths (centering, halves, full opacity), easing curve
names, and logic constants that are not a preference (e.g. array indexes, 6 degrees per second). Nothing visual.

## Structure

```
shell.qml              entry point: top-bar window, Island + AllModes, islandState (= Activity.current), IPC
ScreenCorners.qml      rounded screen corners (config screenCorners): 4 click-through overlay windows per screen
config/
  schema.json          every setting described (section, group, label, type, default...). The defaults ARE
                       the shipped island (2026-11-12: set to the user's island; not blurred, every alert on)
  config.jsonc         the user's values. JSON with comments + trailing commas (Config.jsonc). Lists every
                       setting commented out at its default (`// "radius": 40,`); only the curated ones the
                       future desktop settings app exposes are active: island.shape,
                       island.cornerSmoothing, island.blur, island.blurOpacity, island.attachToTop,
                       <alert>.enabled. Object { } lines always stay active, so uncommenting one line works.
                       Prose comments only in the /* */ header (the checker uncomments every `//` line).
                       Regenerate with `python3 tools/check-config.py --rewrite` (keeps active lines).
                       Named .jsonc (a .json with comments: "Comments are not permitted in JSON" in Zed);
                       its first key "$schema": "./config.schema.json" tells Zed/VS Code that comments and
                       trailing commas are allowed (tested with Zed's own JSON server: clean)
  config.schema.json   that editor schema (allowComments, allowTrailingCommas). Not the settings' schema
services/              singletons (registered in services/qmldir)
  Config.qml           schema defaults + config.jsonc; Config.<section>.<key>. Also the corner helpers
                       (Config.corner / inner / restCorner / restHeight, see Island shape)
                       Each section is a `readonly property var foo: data.foo` line: a new section needs one
  Sys.qml              ALL system data and actions: battery + power profile + time left, audio output +
                       volume + mic, brightness, Wi-Fi (state, nearby networks, connect), Bluetooth (state,
                       devices, discovery, connect / pair), media (MPRIS: Sys.media; the position as an
                       anchor + rate, mediaPositionNow(); mediaLevels from cava while bars are shown;
                       mediaColor from the cover), clock + week, apps,
                       files, shutdown (logind delay lock + PrepareForShutdown), desktop settings (gsettings accent-color +
                       clock-format: `gsettings monitor`; Sys.hour24, Config.colors.accent), notifications (UPower, Pipewire, Networking, Bluetooth, pactl, brightnessctl, find, the
                       notification server), and the derived values (battery percentage/color, week, limits)
  Activity.qml         what the island shows: one queue (open panel + activities), priorities
                       (island.priority), timers, `osd` IPC, do not disturb (`doNotDisturb`, the Focus tile:
                       gsettings notifications show-banners via Sys.systemFocus, survives restarts),
                       draggingOut (a picture dragged out of a carousel: keeps the panel, hides the click catcher)
island/                the island engine
  Island.qml           the shape (a path: Apple-style continuous corners, optional attach-to-top with concave
                       flares) that springs to the active mode's size, and holds every mode (config "island")
  IslandMode.qml       base type for modes: active state, requestState, keyboard focus, Escape, transition
modes/                 one file per island mode (what's shown inside the island; name = Activity kind)
  AllModes.qml         every mode, by name, + which ones are panels: the one registration list
  panels:      IdleMode  BatteryMode  WifiMode (symbol + network list, scans only while open)
               BluetoothMode (rune + device list, discovery only while open)
               SearchMode (scrollable, grouped results)  TimeMode (rolling time, date, day bar, week; seconds only while open)
               QuickSettingsMode (round switches row: Wi-Fi, Bluetooth, Focus, mic, power; two level bands)
               MediaMode (now playing: cover, title / artist, MediaBars, progress, previous / play / next)
               WallpaperMode (carousel of the wallpaper folder's pictures: arrows pick, Enter applies)
               ScreenshotsMode (carousel of screenshot.folder, newest first: Enter / click copies, drag out drops the file)
  activities:  VolumeMode  BrightnessMode  MicrophoneMode  MessageMode  NotificationMode
               LowBatteryMode  ChargingMode  WifiConnectedMode  HeadphonesMode  NowPlayingMode (alerts: Activity watches
               Sys for the change, ignoring what is already there at startup, system.startupQuiet)
               ScreenshotMode (niri's "Screenshot captured": the picture itself; click opens it)
               GoodbyeMode (power off / restart: writes "bye bye" by hand, then lets the system go down)
widgets/               reusable pieces used by modes
  StyledText  Icon (every assets/icons SVG: `name` + `color`, drawn as a vector Shape)
  Badge (concentric round/capsule badge, soft or solid; optional `label`: glyph + word capsule)  TitleStack (grey caption over white title)
  Clock  IconSlot (pill + fade + click)  Battery (the idle one charging: white + a bolt, CutoutBadge)
  CutoutBadge (a small glyph on a thing's bottom-right corner, the thing cut away around it by an inverted
  MultiEffect mask: real transparency, fine on the blurred island; a hollow glyph needs its filled silhouette
  as the cut, or the content peeks through the hollow)
  CornerShape (one rounded screen corner, for ScreenCorners)
  ArcGauge (the curved, ticked bar of the battery and time panels; look in `panel.arc.*`)
  Wifi (dim bars + real level; idle island and Wi-Fi panel rows)  Speaker (same look for the volume)  Bluetooth (idle icon)
  RollingNumber (odometer digits)  ScrollFade (a list's edge fades: island-color gradient, or an opacity mask
  when the island is blurred)
  LevelSlider (volume/brightness bar: drag, scroll; past the ends it bumps: grows a few px, springs back)  LevelRow (icon + LevelSlider + value: the
  volume / brightness pop-ups and quick settings share it; drives Sys, bounces on Activity.bumped)
  GlyphMotion (the Wi-Fi / Bluetooth panels' symbol motion: light-up, ripple, shake, opaque part colors)
  ExpandPill ("Networks · 6 ⌄" pill that unfolds a panel's list)  RollingName (panel title that rolls)
  PillButton (labelled soft / solid capsule toggle, e.g. "Power saver"; look in `panel.button.*`)
  QuickToggle (round switch + one grey state word; the word can open a panel; `quickSettings.toggle.*`)
  MenuBadge (a QuickToggle whose badge sinks when pressed, then morphs into a dropdown of choices:
  position, size + corner on one non-overshooting spring, rows staggered in and clipped to the shape; the
  mode blurs what's behind with its `t`; `quickSettings.power.menu.*`)
  MediaBars (the "now playing" bars: real levels from cava, else a dance; move only while `running`)
  MediaCover (the track's cover as a rounded tile, a note without one; media panel + NowPlayingMode)
  SwapImage (two Images taking turns: keeps the previous picture until the next has loaded; draw `current`
  through an effect. The fullscreen picture and backdrop: a plain Image went blank on each track change)
  PictureCarousel (the wallpaper / screenshots card row: selection spring, bump, press, drag / wheel, check
  badge, optional drag-out of the front card as a real file drag; look in `carousel.*`)
  PanelList (the Wi-Fi / Bluetooth list chrome: group titles, springing highlight, pointer selection,
  scrolling, edge fades; look in `panel.list.*`; the panel brings the model, rows and scroll maths)
assets/icons/          SVG icons, referenced by file name from the config (new ones: Material Symbols Rounded,
                       filled). Drawn as vectors by widgets/Icon: <path> elements only, a viewBox, no transforms,
                       no strokes (flatten in Inkscape; battery.svg's offset was moved into its viewBox)
assets/sounds/         the island's sounds (WAV), generated by tools/make-sounds.py (edit and rerun it to retune them)
assets/handwriting/    stroked SVGs written by GoodbyeMode (Config.handwriting, a ShapePath with `trim`): <path>
                       elements in drawing order, a viewBox fitted to the line; stroke width/color come from config
bin/screenshots        the screenshots panel's helper: `list` (newest first, sizes from headers), `transfer`
                       (paths on stdin -> file transfer portal keys, for drag and drop into sandboxed apps)
bin/wallpaper          lists the wallpapers, reads / sets the current one (Sys runs it): the Settings app's own
                       swaybg line in ~/.config/niri/settings.kdl (rewritten whole, then swaybg restarted)
tools/make-sounds.py   synthesizes assets/sounds (pure Python): layered soft sine tones, dark, one motif per
                       alert, all at the same loudness
tools/check-config.py  validates config.jsonc against schema.json, QML Config reads (also via aliases), section
                       exposure in Config.qml, icons drawable by Icon
```

Import paths are relative folders: modes use `import "../services"`, `"../island"`, `"../widgets"`;
widgets and island use `"../services"`. Quickshell generates the qmldir for plain folders; only `services/`
has a hand-written `qmldir` (for the singletons).

## Workflows

### Adding or changing a setting (always all steps)
1. Read it in QML as `Config.<section>.<key>` (never a literal).
2. Add an entry to `config/schema.json` in the right section/group:
   `key`, `label`, `description` (plain language: what it changes, for a non-developer), `type`,
   `default` (the shipped value), and `min`/`max`/`step`/`unit` for numbers.
   Mark technical knobs `"advanced": true`. Types are listed in the schema's `types` block.
3. `python3 tools/check-config.py --rewrite` lists it in config.jsonc, commented out at its default (don't
   hand-add active values there: an active line is the user's override, not a default).
   A corner: never a raw `radius:` or a new radius setting; pick a role, `Config.corner("row", height)`
   (see Island shape).
4. A brand-new top-level section also needs `readonly property var foo: data.foo` in `services/Config.qml`
   (otherwise every `Config.foo.x` is undefined at runtime).
5. Run `python3 tools/check-config.py`; it must print `OK`.

Section/group placement follows what the user would look for, not the code:
Appearance (font, colors), Bar, Island (shape, layout, behavior), Animation (springs, content transition,
small animations), Pop-ups (`activity.*`, the shared look), Panels (`panel.*`: what the battery, Wi-Fi and
Bluetooth panels share: width, padding, symbol motion, list pill), then one section per mode. JSON paths stay grouped
by the code that uses them. Editing the JSON files with a script: build the whole text first, then write it at once (temp file + rename;
the live shell reloads on save and logs "config.jsonc is not valid JSON" if it catches a half-written file;
harmless, it keeps the previous values). config.jsonc isn't plain JSON: parse it with the checker's `jsonc()`.

### Adding a new mode (panel)
1. `modes/FooMode.qml`: root `IslandMode { ... }`, set `implicitWidth`/`implicitHeight` (from `Config.foo.*`),
   lay out content at that size inside a padded `Item`. The base provides `requestState(name)`, `close()`
   (Escape: holds the key, goes idle), `active`, focus handling. If the mode uses the keyboard, set `keyTarget`
   (the item that takes focus: `mode` itself, or a `TextInput`); Escape then works by itself.
   `autoClose` (stay open when the mouse leaves) and `escapeCloses` (false = Escape emits `escaped()` instead of
   closing, e.g. to cancel a password field first) can be bindings: `autoClose: asking === ""`.
2. Register it in `modes/AllModes.qml` with just `FooMode { name: "foo" }` (and add "foo" to its `panels`
   list); Island wires the signals.
   `requestState("foo")` goes through `Activity.openPanel`: a panel is the activity class `panel` in the queue.
   Set `launcher: Config.foo.launcher` so it's listed in the search launcher, and add
   `foo.launcher { title, subtitle, keywords, icon }` as an "In the launcher" group in schema.json.
3. A way in: a clickable `IconSlot` in `IdleMode` (`onClicked: mode.requestState("foo")`; the clock opens the
   time panel this way) and/or IPC (`qs ipc call island toggle foo` works for every registered mode).
4. Its settings: a "Foo panel" section in schema.json (+ the Config.qml line), then `--rewrite`.
   Optional per-mode transition tweaks: `foo.transition` (object) + `trOverride: Config.foo.transition`.
5. If it's taller than `island.maxHeight`, raise that.
6. Design: follow the design language below. Look at the user's references first (see Design).

### Adding an activity (something the system or a key puts up in the island)
1. `modes/FooMode.qml`: root `IslandMode`. One-line activities are `island.restHeight` tall (read it from
   `island`), two-line ones `Config.activity.tallHeight`. Register it inside `Island { }` with `name: "foo"`.
   It may be narrower than `island.minWidth`: centre its content in the mode's width.
   Register it in `modes/AllModes.qml`.
   Its own entrance animation (a wiggle, a fill, a bounce) starts from `onAppeared` (IslandMode: the content
   is on screen, `island.transition.contentStart` through its fade-in), never `onActiveChanged`: at
   activation the content is still invisible (handoff + fade), so the mic's wiggle played unseen. Before
   `appeared`, hold the start pose (empty fill, small icon); `hasAppeared` tells whether it's on screen.
   Something the system triggers just before the pop-up (Activity.bumped) is sent after `feedback` and held
   until it's on screen (LevelRow `starting` / `live`).
2. Show it through Activity: `Activity.show("foo", key, cls, data, timeout)`. Same key = updates in place;
   `cls` is its priority class, listed in `island.priority` (config + schema description). Keep user
   interaction (key feedback, `panel`) above system things. Covered activities keep their remaining time.
   Give it a `foo.enabled` setting (default true, active in config.jsonc) checked where Activity shows it:
   every activity can be switched off (the settings app lists them).
3. Data and actions still go through Sys. A mode that shows Activity data latches it on
   `Activity.onCurrentChanged` (see MessageMode), so it stays right while fading out.
4. Keys: niri binds `qs ipc call osd ...` (Activity's IpcHandler). Caps lock was dropped on purpose: only
   polling can see it, and the user won't trade deep CPU idle for it.

### Testing a change
- The running shell live-reloads on save. Its log: the newest `/run/user/1000/quickshell/by-id/*/log.log`
  that doesn't mention the scratchpad (test copies write logs there too). A reload while files are half-edited
  can fail or warn ("X is not a type", "undefined"); Quickshell keeps the old version running. `touch shell.qml`
  triggers a clean reload; judge only warnings timestamped after it.
  Find the live log with `grep -l Reloading .../by-id/*/log.log` (newest): short scratch-copy logs don't always
  mention the scratchpad. Editing only an SVG (assets/icons) doesn't reload the shell, and neither does `touch`
  or rewriting a file unchanged: add then remove a newline at the end of shell.qml.
- Quick load check: `timeout -s INT 4 qs -p . 2>&1 | grep -E "WARN|ERROR"` (SIGINT so the output flushes).
  A second instance can't own the notification name ("Could not register notification server": expected).
  The SIGINT also ends a bash `&&`/`;` chain it's part of: run follow-up commands in a separate call, or launch
  test copies in the background `(timeout -s INT 8 qs -p <copy> >/dev/null 2>&1 &); sleep 9`.
- **Scratch copy** (the default way to test): copy `assets config island modes services tools widgets shell.qml ScreenCorners.qml`
  to the scratchpad, replace every `search.actions[].command` and `search.files.open/revealCommand` with
  `["true"]`, then drive it from Timers added before `IdleMode {` in the copy's shell.qml: `root.open("wifi",
  true)`, `Activity.feedback(...)`, `Activity.show(...)` (a fake notification is a plain JS object with the
  Notification fields + expire/dismiss), set fields on modes (give them an `id` in the copy). Expose internals
  for the test with `readonly property var listView: view` in the copy only. Logs: `console.warn`
  (`console.log` is hidden).
- Fake data for stress tests goes in the copy's Sys (e.g. push 20 fake networks into `wifiNetworks`) so the
  real UI code runs on it. Nothing in a test may connect, run commands or change the system.
- Images: `island.grabToImage(r => r.saveToFile(...))` (grabToImage doesn't work on a PanelWindow's
  contentItem). It captures on the next frame: don't change state in the same handler after calling it.
  Tile frames with PIL. Prefer this to `niri msg action screenshot-screen`, which also overwrites the user's
  clipboard (their next paste becomes our screenshot).
- Real input: `qs ipc call island toggle <mode>` is harmless (no keys), but it's a *toggle*. Never send real
  keys (`wtype`) while testing: if the mode was already open it closes and the keys land in the user's terminal.
  The real mouse wheel / hover can't be tested from here: test the maths instead (map a scene point, compare
  the row the code picks with the row actually drawn there) and say so.
- Measure before fixing "it feels slow/buggy": count how often a property changes (a `Connections` counter over
  a few seconds), time an action with `Date.now()`, benchmark one delegate built several ways in a tiny
  standalone `ShellRoot { FloatingWindow { ... } }` with `createObject` in a loop. Report before/after numbers.
- Transitions: Timer that switches modes repeatedly + `grabToImage` every ~30 ms, tiled into one image. Always
  check several switches in a row (see gotchas).

## Rules

### Data: always `Sys`
- Every piece of system data comes from `services/Sys.qml` (`Sys.battery.*`, `Sys.wifi.*`, `Sys.wifiNetworks`,
  `Sys.audio.*`, `Sys.time`, `Sys.week`, `Sys.apps`, `Sys.files`...). Running and changing things goes through it
  too (`Sys.run`, `Sys.openFile`, `Sys.setPowerProfile("balanced")`, `Sys.setWifiEnabled`, `Sys.connectWifi(name,
  psk)`). Modes and widgets never import `Quickshell.Services.*`, `Quickshell.Networking`, `Quickshell.Bluetooth`,
  use `DesktopEntries`/`ToplevelManager`, run `Process`es, or call `new Date()`.
- Never hand a service object (a network, a device) to a mode to keep: it can be destroyed between updates. Pass
  plain values and let Sys look the live object up when acting (`connectWifi` takes the network's name).
- Derived values shared by several components live in Sys once (e.g. `Sys.battery.color`), not recomputed
  in each widget.
- Adding new data: the least CPU possible while staying (almost) instant. In order of preference:
  1. a binding on a Quickshell service (UPower, Pipewire, Networking, Bluetooth, DesktopEntries,
     `SystemClock`...): event-driven, zero cost while nothing changes;
  2. a long-running event stream (`pactl subscribe`, `niri msg --json event-stream`, `udevadm monitor`,
     `dbus-monitor`...) that triggers a one-shot read, debounced with a short Timer
     (`Config.system.*`), and restarted `onExited` (`Config.system.restartDelay`);
  3. polling only if nothing can notify you: the slowest interval that still feels instant, and only
     while something visible needs it (bind `running` to the mode being open).
  Never spawn a process per frame / per keystroke; cache results (e.g. `Sys.apps` is filtered once, not
  on every search). Pick the coarsest precision that's enough. Expose only what's used.
- Data a panel needs only while open is switched on by the panel: `Binding { target: Sys; property: "wifiScan"
  (radio scanning) / "bluetoothScan" (Bluetooth discovery) / "timeSeconds" (per-second clock); value: mode.active }`. Never always on.
- Noisy sources: publish only what's shown, and only when it changes. `Sys.wifiNetworks` quantizes signal to
  bars, merges same-name access points, sorts stably (connected, saved, bars, name) and is replaced only when
  its JSON signature changes (signal strength moves several times a second while scanning). Anything derived
  from the clock that only changes daily depends on a date string (`Sys._today`), not on `time`.

### Lists
- A list that can grow is a `ListView`, not a `Repeater` over a JS array: a Repeater creates every delegate up
  front (54 Wi-Fi rows froze the panel for 650 ms), and a new array rebuilds all of them. Feed the ListView a
  `ListModel` updated in place (append / set / remove by index; see `WifiMode.syncRows`). If the model only needs
  a role for sections, the delegate can read its data from the JS array by `index` (see SearchMode).
- Don't cap lists for layout reasons: grow up to a `visibleRows` setting, then scroll (the user wants the free
  Wi-Fi 20 rows down to be reachable). Edge fades (`scrollFade`) show there's more: `widgets/ScrollFade.qml`
  over the ListView, plus `layer.enabled: edgeFade.masked; layer.effect: edgeFade.effect` on it. Opaque island:
  gradients in the island color (free). Blurred island: that band would be a dark stripe over the blur, so the
  list fades through a MultiEffect mask (its layer exists only while blur is on). The mask needs
  maskThresholdMin 0.5 + maskSpreadAtMin 1 for a smooth ramp (the defaults show any alpha above 0 fully).
- Keyboard scrolling: compute row positions yourself (headers, row height, an expanded row) and animate
  `contentY` to them, clamped to the content; ListView only estimates rows it hasn't created. Reveal on keyboard
  moves only, never on hover. Scrolling with the wheel re-selects the row under the pointer; the keyboard's own
  scroll animation doesn't.
- Selection follows the item, not the index: when the list reorders, find the selected name again.
- ListView gotchas: an Item declared inside a ListView stays a child of the view (it doesn't scroll and gets
  clipped: give it `parent: view.contentItem`, like the search highlight), while a pointer handler declared
  inside lands on `contentItem` (its `point.position` already includes the scroll: map `point.scenePosition` to
  the view and add `contentY` once). Setting `currentIndex` doesn't scroll the view; ListView changes it by
  itself on inserts, so set it imperatively instead of binding it.

### Performance
- Icons from assets/icons: always `Icon { name: Config.x.icon; color: ... }`, never `IconImage`/`Image`.
  IconImage (QtQuick.Controls.impl) rasterizes, recolors on the CPU and rescales to the 1.25 screen scale:
  blurry edges, and it never draws larger than the SVG's own size. Icon is a `Shape` (CurveRenderer) built from
  the file's path data, parsed once and cached by `Config.glyph`: sharp at any size, keeps the SVG's
  proportions, `color` animates. Cost: ~0.04 ms to create, ~0.08 ms more on its first frame (200 icons:
  33 ms vs 16 ms to the next frame), negligible at ~30 on screen. `VectorImage` was sharp too but can't be
  tinted and costs 0.36 ms each. App icons from the theme (`Quickshell.iconPath`) stay `Image`.
- Never leave an `IconImage` with an empty `source` in something created often: ~21 ms to create (13 launcher
  rows froze the island for 300 ms). Doesn't apply to Icon (an empty `name` draws nothing, for free).
- A binding that returns a new array/object always notifies, even if equal: compare a signature and assign
  imperatively when only some changes matter.
- The island shape is a path rebuilt while the island springs: ~10% more CPU than a plain rectangle during
  animation, nothing at rest. Fine; don't add per-frame work on top of it.
- Every mode is always instantiated, so anything in a mode that reads `island.width/height` runs on every
  frame of every spring, 15 times over. IslandMode's `progress`, `scale` and `x` return early for a hidden mode
  (not active, faded out) before touching the island's size (2026-11-13: -17 % main-thread CPU while switching
  modes). Keep that order in new per-mode bindings, and skip work for features that are off (`blurCorner`).
- Noisy service values (signal strength, battery %) feed a small int/bool property first (`Sys._wifiBars`),
  so the object built from them is only replaced when what's shown changes.
- Every frame the island window draws costs ~2 ms of CPU, whatever changed (2026-11-15: a bare Quickshell
  window with a 2 px rectangle changing 30x/s = 46 ticks per 9 s; ours 55; the window's width didn't
  matter). So what costs is how many frames are drawn: never run an animation for something that only
  moves by sub-pixels, and don't stack an animation on top of a stream that already updates. Fixed then:
  the music bars eased each cava frame with a 60 fps animation (now a per-frame step toward the level,
  same calm look: idle with music 119 -> 57 ticks / 9 s); the media progress was a 60 fps animation to the
  track's end (now a Timer to the next pixel or whole second: 121 -> 14, then half a pixel (media.progress.stepPixels); panel open with music 130 -> 66).
- Measured 2026-11-13 (scratch copy, 26 mode switches in 15 s): ~220 CPU ticks (1/100 s), main thread ~125,
  render ~50; transition blur ~20 % of it. At rest: 0 ticks in 20 s, ~0.3 wake-ups/s. Search: <= 3 ms per
  keystroke. Benchmark copies must be stopped with SIGTERM/SIGKILL and checked (`pgrep -ax qs`): a backgrounded
  `qs` ignores SIGINT and stays on screen.

### Text: always `StyledText`
The font ships with the island (2026-11-17, for the public release): assets/fonts/GoogleSansFlex-Variable.ttf
(OFL 1.1, assets/fonts/OFL.txt), loaded by Config's FontLoader (font.bundled) before any text asks, so
it looks the same without the font installed. A font file loaded by the app registers only its default
weight: every text also sets the variable `wght` axis to its weight, next to `ROND` (StyledText does
it by hand in _syncAxes: a binding reading font.weight into the same font looped; the two TextInputs and
RollingNumber's metrics set both axes). Checked with a fontconfig that hides ~/.local/share/fonts:
bundled = semibold Google Sans Flex, identical to the installed one; without it, Noto Sans.
Never a bare `Text {}`. `widgets/StyledText.qml` applies `Config.font` (family, size, weight, color, and
`roundness` = the font's `ROND` axis via `font.variableAxes`; Google Sans Flex, the default since 2026-11-13,
rounds its letter ends). One font everywhere: never give a mode its own font family or roundness (the user
said so); only size/weight/color are overridden per use.
Only override what differs (`font.pixelSize: Config.activity.titleSize`, `color: Config.colors.secondary`).
Never hardcode a font family. (`TextInput` can't use it: set its font from `Config.font` by hand, `variableAxes` included.)
A text bound to data that can be briefly missing gets `|| ""` (assigning undefined to a string warns).
Names (networks, devices, files, paths) elide in the middle (`Text.ElideMiddle`, like the Finder: the end
often tells two apart, "_5G", ".pdf"); sentences (notifications, descriptions) elide at the end.

### Config: nothing tweakable in code
- Sizes, paddings, colors, opacities, durations, icon names, counts, delays, springs: config + schema.
- Reuse `Config.colors.*` (`text`, `secondary`, `accent`, `danger`, `charging`, `powerSaver`...) instead of new
  hex copies. Icons: file name in JSON, shown with `Icon { name: Config.x.icon }`.
- Springs are Apple-style `{ "response": s, "dampingFraction": 0-1 }`, converted with `Config.spring()`.
- Components read `Config` directly; don't pass config down as properties. A shorthand is fine only as
  `readonly property var layout: Config.search` (the checker follows that exact form and validates
  `layout.x`); any other aliasing hides reads from the checker.
- An object setting that overrides another (e.g. `battery.transition` over `island.transition`) gets
  `"overrides": "island.transition"` in the schema, so its keys and values are validated too.

## Design

### References
The user wants Apple's Dynamic Island feel (and NotchNook for the attached-to-top look). References live in
their Cosmos collection https://www.cosmos.so/achille.puissant/solstice-os (Dynamic Island sheets, expanded live
activities, Raycast-style launchers, macOS Control Center, dark lists). Pasted images don't reach us: fetch with
`curl -sL -A "Mozilla/5.0" <url>`, grep `https://cdn.cosmos.so/<uuid>`, download with `?format=jpeg&w=900`
(a single pin `cosmos.so/e/<id>` has its image in `og:image`). Look at them before designing a mode.

### Language (shared look, not a shared template)
Each mode keeps the layout that suits it, but they all follow these rules. Shared values: `Config.activity.*`
("Pop-ups" section) and `Config.colors.*`.
- Content hugs both ends, the middle stays empty: a leading glyph or badge at the far left, a trailing value at the
  far right (`activity.edge` from the edge).
- One-line activities are exactly `island.restHeight` tall (the island only widens); two-line ones are
  `activity.tallHeight`.
- Badges (`widgets/Badge.qml`) sit `activity.inset` from the edge with height `restHeight - 2 * inset`, so they're
  concentric with the island's rounded end. Soft = tint at `activity.badgeOpacity`; solid = "this is on", its glyph white on a dark or saturated
  fill (blue, red) and black on a light one (yellow, green, white): `Config.onColor(fill)`, Badge's default (muted
  mic, power saver on, Wi-Fi on, the active power mode).
- Two lines = `widgets/TitleStack.qml`: grey caption (`colors.secondary`) above a white title.
- Each activity has an accent, used for its glyph and trailing value: red = danger/muted, yellow = power saver,
  green = charging, blue (`colors.accent`) = Wi-Fi/info/connected. Titles stay white. Never dim text with opacity
  for "secondary": use `colors.secondary`.
- Signal/level icons use the idle look: the full icon dimmed (`idle.overlayOpacity`) with the real level bright
  on top (`widgets/Wifi.qml`, `Battery.qml`).

### Panels (same language, bigger)
- Battery panel height comes from its content (number, "Full in", bar, `battery.gauge.saver.gap`, button):
  a fixed height setting broke the layout whenever a size changed.
- Battery (2026-11-13, "an instrument": bold, simple, a bit playful; refs: a ruler with a tag above its
  needle, a timer's filled arc band): a thick band bent into a gentle arc (`battery.gauge.arc.bend`), filled
  in the accent up to the level with the band's own rounded ends (100 % covers it exactly; the white needle was
  removed so it matches the Wi-Fi symbol, 2026-11-13);
  a few chunky ticks, cut into the fill and grey on the empty part; on top, centred, the real percentage,
  `widgets/RollingNumber.qml` with a subtle roll when the level changes (it doesn't follow the
  needle or count up with the sweep: the user asked for that); in grey under it, "Full in 1h 20m" while charging (`Sys.batteryTimeToFull`), "3h 10m left" on battery (`Sys.batteryTimeToEmpty`), each
  its own minute-rounded int. One labelled
  "Power saver" capsule (PillButton) centred under it (solid yellow when on, Space toggles; a round icon-only
  badge felt empty and unclear). No caption text. Opening sweeps the
  needle from 0 with the fill (one spring). Rejected along the way: a fine ruler with a lens
  swell (too detailed) and a big odometer number (too much). The three power modes left the panel on
  purpose: they belong in the planned quick settings. Settings `battery.gauge.*`. The previous panel
  (live-activity card + three capsules) was deleted once this one was accepted.
- Tried and rolled back (2026-11-13): the panel's button top left + a close badge top right (battery, Wi-Fi).
  It broke the centred one-number / one-instrument / one-button composition, the × was redundant (mouse
  leave, click outside, Escape all close), and a corner ⏻ read as system power. Keep the button centred.
- Search: Raycast-style launcher: magnifier, hairline, results grouped under grey section titles (groups ordered
  by best match), icons on soft rounded tiles, kind at the right, "Open ↵" keycap on the selection; scrolls.
  Pins (2026-11-15): with nothing typed it shows the pinned panels / apps / commands as tiles (icon + name,
  search.pins.columns per row; no title above them: the user asked for just the tiles), with the lists'
  sliding highlight; arrows move, Enter opens, Ctrl+Left / Right or dragging a tile reorders (tiles are a
  ListModel moved in place, so each slides to its new slot with the highlight's spring; the dragged one
  follows the pointer), Ctrl+P (search.pins.key) or a right-click pins / unpins a result or tile; pinned
  results show a small pin. Saved system.saveDelay after the last change. Stored by Sys (Sys.pins, pins.json in Quickshell.statePath: per shell
  copy, so a scratch copy has its own; delete the copy's file after a test). Files and calculations can't
  be pinned.
  Kinds (2026-11-16): calculator, files, settings and the web each have search.<kind>.mode: "always"
  (mixed in; files and settings their best search.<kind>.mixedResults, files by name only), "prefix"
  (only after one of search.<kind>.prefixes) or "off". A prefix of any kind that isn't off turns into
  that kind's pill (search.<kind>.label / pillIcon / placeholder) and searches only it. Defaults: files
  prefix, the rest always. Settings come from the desktop Settings app (Sys.settingsIndex, read from
  search.settings.indexCommand = `settings --index` each time the search opens; Enter runs
  search.settings.openCommand = `settings <page>`); without the app, none show. Each setting shows its
  page's icon from the Settings app (the index's iconFile, an absolute path: Config.glyph reads a name
  starting with "/" as a file; `flip` = drawn upside down, like the app's sidebar), unless
  search.settings.pageIcons is off (then search.settings.icon).
  Web (2026-11-15): the last result is always a web search for what's typed (search.web.*, Google by
  default, Sys.openUrl through xdg-open), or opening it when it looks like an address ("rust-lang.org");
  alone, it's what Enter picks. Not pinnable, not in file search.
- Wi-Fi (2026-11-13, the battery panel's language): the network's name on top, centred (rolls when it
  changes); the Wi-Fi icon as the instrument: wifi3.svg's dot + two round-capped arcs
  redrawn as strokes with the icon's own measured proportions (24-unit grid: dot r 2.5 in the icon, 2.2 here as an optical correction (a solid dot reads bigger than the arcs), arcs 3 thick, radii
  9.9 / 15.75 around a centre 2.8 below the dot (3.2 here: the smaller dot sits a hair closer to the arcs), 73° / 78° wide) times `wifi.hero.glyph.scale`. The dot is the
  first bar, like the small icons. Opening / joining fades the parts from grey to blue, dot first (only the
  color moves: shrinking a round-capped arc stalls as a dot, then pops); searching / connecting runs a ripple
  out through them; a failed join shakes it red. Tried and rejected: a filled wedge with stripes (the user
  preferred the strokes). The symbol is the Wi-Fi switch (click or Space; brightens on hover, sinks on
  press; off fades the lit bands back to grey, outer first); no separate button (it took ~55 px for a rare action). A pill "Networks · N" unfolds the
  list (saved, then others; rows with bars, lock, blue check / "Connecting…" / red error; password field
  inline under its row, × / Escape / arrows cancel); Up/Down/Enter unfold it from the keyboard; scrolls past
  `panel.visibleRows`. Settings `wifi.hero.*` (glyph, texts), `panel.*` (shared), the row/list `wifi.*` keys. The previous Control Center-style panel was deleted
  once this one was accepted.
- Bluetooth (2026-11-13, the Wi-Fi panel's sibling): the connected device's name on top; the Bluetooth rune
  redrawn as round strokes with bluetooth.svg's proportions (24-unit grid: stroke 2, stem 16, chevrons 4 right,
  arms 5.6 left, `bluetooth.hero.glyph.*`) in 3 parts (stem, upper zigzag, lower zigzag), blue while a device is
  connected; the rune is the switch; a pill "Devices · N" unfolds "My devices" (paired; connected first) then
  "Other devices" (named devices found by discovery; "Searching…" until one shows up); rows with a device-kind
  icon, battery % when reported, "Pairing…" / "Connecting…" / red error, blue check. Click: connect a saved
  one, pair + trust + connect a new one, disconnect a connected one (`bluetooth.clickDisconnects`). Sys tracks
  the attempt (paired / state signals + `bluetooth.attemptTimeout`). No BlueZ agent is registered, so devices
  that need a PIN or a code to confirm can't pair (they fail); the rest pair "just works". Ways in: launcher,
  `qs ipc call island toggle bluetooth`, the idle Bluetooth icon (any device connected,
  headphones included). The previous Control Center-style panel was deleted once
  this one was accepted.
- Quick settings (2026-11-14): nothing boxed, like the other panels (a grid of grey Control Center tiles was
  built first; the user found it foreign: cards, equal weights, text everywhere, left-aligned). One centred
  row of round switches (activity-badge look, solid = on): Wi-Fi, Bluetooth, Focus (= do not disturb),
  microphone (solid blue = live; soft white, crossed out = muted), power mode; every "on" is the same blue
  (Focus was purple: changed 2026-11-15); one grey word under each, the state only (the symbol says
  what it is). The power badge is a MenuBadge: it morphs into a dropdown, down and to the left
  (its right edge on the badge's cell, kept inside the panel), and the rest of the panel blurs behind it
  (quickSettings.power.menu.backdropBlur; 2026-11-15, the plain dropdown over a sharp panel didn't look
  right). Escape and clicks elsewhere close it first. Tried and dropped (2026-11-15): the badge spreading
  across the row into three badges while the other switches stepped back (the user preferred a dropdown). Balanced's
  icon is gauge-balanced.svg: speed.svg (performance) with its needle straight up (a scales icon felt odd). Under the row, brightness (only with a backlight) and volume as the pop-ups'
  own LevelRow (icon left, value right; 2026-11-14: bars, ruler bands and an accent track with a white thumb
  were tried first). While quick settings is on screen, nothing it already shows gets a pop-up
  (`Activity._inQuickSettings`): volume / brightness (the bars bounce instead), mic, Wi-Fi connected,
  Bluetooth headphones. Wired headphones, battery and notifications still pop up. Calm mode will be a sixth switch once it exists.
  Its padding is its own (`quickSettings.padding` 28, more air around small things than `panel.padding`).
  Badge click = toggle; the word under Wi-Fi / Bluetooth opens their panel. Ways in: the empty middle of
  the idle island (`idle.middleOpensQuickSettings`; no hover pill or glyph on purpose: the user wants an
  onboarding to explain it), Mod+S in niri, the launcher. Chosen over widgets in the empty launcher (two jobs in one place, keyboard
  ambiguity). Fully keyboard-usable (2026-11-15): one focus spot, shown by one grey
  highlight (a switch's whole tile, badge + word, or a level row) that springs from spot to spot like the
  Wi-Fi / Bluetooth lists' (panel.list.highlight / selectedOpacity; rings around the badges were tried and
  dropped; a tile's highlight reaches quickSettings.focus.tileOverhang past its cell, the tiles show no
  edge so it may overlap a neighbour; the power menu's lit row slides the same way); selected on the first switch when opened from the keyboard (island.keyboardOpened, set by
  shell.qml before the panel activates), else shown from the first arrow / Tab; Left / Right move along the
  switches or change a level (bumping at the ends), Up / Down between the switches and the level rows,
  Tab / Shift+Tab through everything, Space toggles (the volume row: mute), Enter also opens Wi-Fi /
  Bluetooth's panel and the power menu (Up / Down / Enter inside it, Escape closes it). Settings
  quickSettings.focus.padding. Keys go through QuickSettingsMode.handleKey(event), so a test copy drives it with
  plain { key, accepted } objects (never real keys). The power menu keeps the badge's soft color (the tint
  over the island, opaque), no outline.
- Media (2026-11-14, Apple's expanded "now playing"): cover (rounded tile, a note without one), title in white
  over the artist in grey, MediaBars at the far right in the cover's color (Sys.mediaColor: ColorQuantizer,
  local covers only; https covers use media.accent.fallback); progress = elapsed, LevelSlider (drag seeks,
  debounced), "-time left"; previous / play-pause (bigger, glyphs swap with a scale) / next, centred. Previous / next are
  one triangle drawn twice (media.icons.skip): skipping (click or arrow key) grows a new triangle in at the
  back while the front one is pushed out (media.controls.skipDuration; previous mirrored). The
  shown position is read from Sys's anchor at the next device pixel of the fill or the next whole second (a
  Timer, not a per-frame animation), re-armed whenever Sys's
  anchor moves (players only report a seek, play / pause, a new track: nothing polls). Quickshell's own
  position estimate isn't trusted between reports: it jumps when the rate changes, and Zen/Firefox (YouTube
  Music) set Rate 0 for a moment after a seek while "Playing", which froze the bar until pause / play
  (2026-11-15); Sys takes rate 0 while playing as 1. Zen's Position property is often 0 or stale; its Seeked
  signals carry the truth. Firefox only knows a length when the site reports it (YouTube Music doesn't) or
  when it can guess from the tab's media element, and it gives up while the tab has more than one (Firefox
  source: MediaPlaybackStatus "Count != 1"; YouTube Music's song-page clip, YouTube's previews): no length,
  Position 0, no signals. A track that had a length keeps it (Sys._knownLength, same player + title +
  artist) and Sys counts the time itself, no seeking (media.lengthGuessed); a track that never had one has
  no progress row (MediaMode.hasTimeline). Tested with a fake player (2026-11-15).
  When the length arrives or goes while the panel is open (Zen sends it once the page's clip element goes,
  often on a pause), the island springs to the new height with the controls riding its bottom edge (the
  content follows island.height while `resizing`; an animated implicitHeight made the controls move first and
  the island follow late), then the row fades and scales in; going, the reverse, the row keeping its last
  length (rowLength) while it fades. Dragging only previews; the seek is sent on release (the wheel: debounced).
  Space / Left / Right. Ways in: the idle bars, the "now playing" alert, the launcher, IPC.
  Fullscreen (2026-11-16, first step): double-click an empty spot (media.fullscreen.*): the island
  itself grows to the screen (IslandMode.fullscreen; Island.expansion morphs its corners into the
  screen's and drops the gap past island.maxHeight; shell.qml grows the window meanwhile). MediaMode
  blends its layout with `fs` (0 panel, 1 screen, from the island's live height): the top row fades, the
  progress row stretches + grows and the controls grow at the bottom; the cover flies (`hero`, starts
  square-cropped like MediaCover so the swap doesn't show) to a big picture with its own ratio
  (fullscreen.art.*) centred above the progress row, and back to the cover's spot on exit; behind,
  a very blurry copy (decoded tiny, MultiEffect blur, overscan, dimmed; masked to the island's corner)
  that comes in over the first topRowFade of the growth and goes over the last (the user disliked it
  fading all the way out on exit; the stretched, pixelated picture was rejected); black without a
  picture. Own springs: island.fullscreenExpand / fullscreenShrink (Island.fsMotion). The island never
  exceeds the screen (its overshoot moved the centred island across a pixel as it settled) and `fs` is 1
  within half a device pixel. At full size its corners are the screen's minus screenCorners.islandOverlap
  (reaches under them: same-place antialiased edges left a thin line), smoothing turning into
  screenCorners.smoothing; the backdrop is masked by Island.shapePath. The big picture's corner grows
  from the cover's `tile` into the `island` role. A soft shadow under it (RectangularShadow, fullscreen.art.shadow.*, softened on request,
  growing in with `fs` so the small cover has none).
  Title / artist fly too (flyTitle / flyArtist: drawn at the full size, fullscreen.text.*Scale, scaled
  down at the start, so they're sharp once there), centred under the picture; they ride the picture's bottom
  edge (stage.flyY / flyX: a straight path let the title climb onto the shrinking picture on the way back,
  read as a jump) and only in the last fullscreen.text.riseShare slide up to the right of the cover; the picture + text group
  is centred above the progress row. Covers (MediaCover, the big picture) have smoothed corners
  (Config.roundedRectPath, island.cornerSmoothing). Exit: top-right badge,
  Escape, double-click again. Reset once the panel is off screen (a volume pop-up over it ends it). After
  exiting, it stays open until the pointer comes back (holdOpen). A new track's picture replaces the old
  one once loaded (SwapImage); with other proportions it springs to its new shape (fullscreen.art.resize,
  only in fullscreen), the text riding along.
  Idle bars (2026-11-15): on the left right after the clock (idle.media.left; with four icons on the right
  the island looked lopsided: left = what's going on, right = the machine's status). Headphones have no idle
  icon any more (2026-11-15: the alert says it; a badge on the bars was tried and was too small to read,
  bigger looked odd); Bluetooth headphones still show the Bluetooth rune. White (a cover-colored dot next to the green battery looked messy; a cover beside
  them was tried and dropped, the color belongs where the cover is), moving while it plays, then still for
  idle.media.linger after a pause / the end so a click can restart it. NowPlayingMode = the iPhone's compact
  activity: cover at the far left, cover-colored bars at the far right, nothing between; Activity shows it
  only when music starts after nowPlaying.quietGap of silence (no alert per playlist track or quick resume),
  never over a panel, and pausing takes it down. A separate bubble beside the island was considered and not
  done (the separate island was removed on purpose).
  The bars follow the real sound through cava (`sudo dnf install cava`; media.bars.realSound; Fedora's cava
  has no PipeWire input: `method = pulse`, through pipewire-pulse), run by Sys
  only while music plays and a MediaBars is running (Sys.mediaLevelUsers); without cava they dance on their
  own. Tested with a fake cava + fake player; never seek the user's real player to test.
- Wallpaper (2026-11-16, the user's reference: a tilting card carousel): pictures of wallpaper.folders
  (default ~/Pictures/[Ww]allpaper*, the Settings app's folder) as landscape cards in the screen's
  proportions; the selected one in front, side.count neighbours behind on each side (smaller, turned,
  darker), the next fading in from further out. Only 2 * side.count + 3 card items exist; each takes the
  next picture as it leaves one end (`pic` = the window index congruent to its slot). Width and padding are
  the launcher's (search.width / padding, 2026-11-17: the user wanted the same size); the front card's
  width is what the side cards leave (no card width setting). No tilt or shine
  on hover (2026-11-17: tried on the cards and the media cover; the user preferred it plain). Left / Right,
  wheel, drag, click a side card pick; Enter or a click on the front card applies (Sys.setWallpaper ->
  bin/wallpaper set: same line the Settings app writes, so it agrees; it watches settings.kdl). A check
  badge marks the wallpaper in use (read back after applying, so a failed save doesn't stay); each
  opening starts on it. The name sits on top by default like Wi-Fi / Bluetooth (wallpaper.name.position,
  2026-11-17: the user may prefer it under). The side cards' turn stays (the user likes it: "it's fun").
  The card row is widgets/PictureCarousel (2026-11-17, shared with the screenshots panel; its look moved
  from wallpaper.side / move / bump / drag / apply / current / card / name.position+gap to carousel.*,
  apply -> press, current -> mark).
  Pictures listed folder by folder, sorted by path, wallpaper.depth 3; the Settings app's Appearance
  page lists the same ones with the same rules and these settings (its own copy of the code: change both).
  Ways in: launcher, IPC. Tested in a scratch
  copy with a folder of symlinks and setWallpaper stubbed (never apply a real wallpaper to test).
- Screenshots panel (2026-11-17, "the same way wallpaper does"): ScreenshotsMode = PictureCarousel over
  Sys.screenshots (bin/screenshots list: screenshot.folder, screenshots.extensions, newest first, sizes
  from the files' headers; read when it opens). Each card takes its picture's proportions held between
  screenshots.card.minRatio / maxRatio (the user: cards flex, but a thin one stays a normal rectangle,
  cropped around its centre); pictures always fill their card (a first version letterboxed them whole:
  rejected). PictureCarousel spaces neighbours so each shows the same strip behind the front card.
  "Today at 19:52" above (screenshots.name.*, Sys.hour24). Enter / click on the front card copies it as an
  image (Sys.copyImage: screenshots.copyCommand, wl-copy with the file's mime type) and tags it with a
  copy glyph + "Copied" (screenshots.copied.*; a bare check didn't say what happened: Badge now takes a
  `label` and widens into a capsule, activity.badgeLabel.*). Shift+Enter or a right click on the front
  card shows it in Files, selected (Sys.revealFile; screenshots.revealCloses). Drag the front card up / down (sideways slides the row) out of the island: a real Wayland
  drag (Drag.Automatic) offering application/vnd.portal.filetransfer (+ .files) = a file transfer portal
  key, then text/uri-list; no text/plain (a text field took the path as text). The key is the fix for
  sandboxed apps: Zen is a Flatpak that can read only Downloads, so a file:// path dropped into Gmail
  became a link (the user: "not just the link"); through the portal it gets its own copy, the way Files
  hands files over. Sys.offerFile asks bin/screenshots transfer (running only while the panel is on
  screen, Sys.fileTransfer) for a key as soon as a picture is in front. Checked: a key retrieved from
  inside Zen's sandbox gives /run/user/1000/doc/<id>/<file> (flatpak run --command=sh ... gdbus
  RetrieveFiles; flatpak document-unexport the test file afterwards). While the drag runs
  Activity.draggingOut keeps the panel from auto-closing and unmaps the click-outside layer (it would
  take the drop). That flag must outlive the DragHandler: the system drag takes the pointer and the
  handler goes inactive at once (the first version bound both to it, so the layer came straight back over
  the browser; the user: "the backdrop is blocking the browser"). Now: lift goes active -> draggingOut,
  the layer unmaps, carousel.dragOut.startDelay later Drag.active = true + Drag.startDrag() (blocks in a
  nested event loop until the drop), then draggingOut goes false and the layer comes back. Never start
  that drag in a test: without a real button held it never ends, and quitting mid-drag aborts Quickshell
  ("destroyed while a signal handler is in progress"; a reload mid-drag would do the same).
  Where drops land (checked with the user, 2026-11-17): native Wayland apps yes (Zed; Figma once run on
  Wayland: FIGMA_USE_WAYLAND=1 in niri's environment block, its launcher defaults to X11). X11 apps
  (through xwayland-satellite: niri lists their window under satellite's pid) get no drops from
  Wayland apps. Zen (Flatpak, native Wayland) refuses file drops from every app, Files included: not
  ours; copy + Ctrl+V works there. Ways in: launcher, IPC `toggle screenshots`. Tested in a scratch copy with fake
  pictures (copy stubbed: never touch the clipboard); the drop itself needs a real pointer.
  Standing out (2026-11-17, "a bit hard to distinguish from the background", outline refused): a faint
  light under every card (carousel.backing.style "lift": a white RectangularShadow at lift.opacity 0.07,
  blur 14, spread 1: "just a little bit so it's distinguishable"). Tried: "glow" (each card's own
  picture blurred and brightened under it; "way too strong", kept as a choice) and a spotlight behind
  the front card (too weak, removed).
  Each opening lands on the newest (followNewest, until you move), also when the list read on opening
  brings a new one. A panel reacting to a new list does it from the carousel's own onPicturesChanged:
  the mode's handler ran before the carousel had the list, and its selection named the old picture
  (both panels, fixed 2026-11-17).
- Clicking a notification (2026-11-17, "bring you to the page who issued them"): Sys.openNotification:
  its default action if any; a system sender without one (notifications.open.systemApps: normalized app
  name -> Settings page) opens the Settings app there; else the sender's window comes to the front (niri
  windows JSON + focus-window): the window of the sender's process or one of its parents (sender-pid hint,
  /proc chain read synchronously at arrival in Sys._noteSender, since notify-send is gone by the click:
  Claude Code's notify-send -> bash -> claude -> zed = Zed's window), else a window whose app id matches
  the desktop entry / app name / entry's StartupWMClass (most recently focused); no window and no default
  action: the app is started (DesktopEntry.execute, exact desktop id or name only). Tested 2026-11-17 in a
  scratch copy with the real window list. A test of openNotification must stub DesktopEntry.execute too
  (it started a real Files window once).
- Notifications (2026-11-17, "the now seems redundant, the feel is a bit cheap"): the two-line language,
  no third tier. Leading: the picture (a person, a cover) with the app's icon cut into its bottom-right
  corner (an OddEven hole in the picture's mask, notifications.appBadge.*; iPhone-style), else the app's
  icon, else a soft bell tile (the badges' look: tint at activity.badgeOpacity; red with
  notifications.criticalIcon for urgent ones, the island's danger accent); corners concentric with the
  island's end (Config.inner). The app's name shows above the title when nothing else says who it's from
  (no icon, no picture). Title white (the
  app's name when there's none), message grey (colors.secondary, no opacity), one line, all of it on hover.
  No "now" and no app name by default (the icon says it; notifications.showAppName): the age shows only
  once it waited notifications.ageAfter (behind a panel...). Arrival from onAppeared: the icon springs up
  from appear.iconFrom, the text rises in appear.textDelay later; replayed when another notification takes
  the place. Tested with fake notifications (a JS object with the Notification fields).
- Screenshot (2026-11-17, the user's reference: the iPhone's island holding a card, without the check
  under it): niri's "Screenshot captured" notification (screenshot.summaries) becomes ScreenshotMode, the
  picture alone in a tile with the screenshot's proportions (screenshot.height, at most maxWidth),
  island around it (paddingX 36 / paddingY 32, height 96) and corners that scale with the picture
  (screenshot.roundness 0.1, a share of its height: small on purpose, a card; the one corner not from
  a style role), and the island 1.8x rounder than the style around it (screenshot.islandRoundness ->
  IslandMode.cornerScale; Island eases between scales over island.cornerMorph, at most half the height;
  a full oval was tried and dropped): a card held in the
  island, not concentric on purpose (the user: "it's basically a square in a pill"); the island keeps its
  own corners (an oval island was tried and dropped, 2026-11-17), springing up from appear.from; click = Sys.openFile (the default image viewer) +
  dismiss; right-click = Sys.revealFile (its folder) + dismiss; scroll up dismisses. One Activity key
  ("screenshot"): a new one takes the place of the one shown (springs in again; the older notification is
  dismissed); a timeout expires niri's notification too (it stayed in the server before). Activity asks Sys.findScreenshot first: the file from the notification
  (image / icon given as a path), else the newest file saved in screenshot.folder in the last
  screenshot.recent s, and its size from `file`'s header line, so the island opens straight to the right
  shape; no file = the normal notification. Shown in Focus (you just took it); class `screenshot` in
  island.priority, after charging. Tested with fake notifications only: never take a real screenshot to
  test (it overwrites the clipboard).
- Lists show right away by default (`panel.collapsibleList` off: function first for a public release; the
  pill version is opt-in). While off, the title reads "Tap to turn on" (the symbol is the switch).
- Wi-Fi and Bluetooth share their motion and pieces: `widgets/GlyphMotion.qml` (light-up part by part,
  fade-out latch, ripple, failure shake + red flash) colors each part with an opaque blend (grey or the
  accent over the island color: overlapping see-through strokes doubled up into bright spots; side effect:
  with island.blur on, the unlit symbol is a solid dark grey, not see-through), `ExpandPill`, `RollingName`,
  `PanelList` (the list chrome; rows and their maths stay in each panel), and the Panels settings
  (`panel.*`: one width, `panel.width` 350, for the battery, time, Wi-Fi and Bluetooth
  panels, so switching between them only changes the island's height; they all use its padding and share
  the gauge: `widgets/ArcGauge.qml`, `panel.arc.*`). Battery and time have the same top (2026-11-13, made
  cohesive on purpose): big number, small grey part beside it (% / seconds, same weight), grey line under
  it, gauge, with the same sizes and gaps from `panel.number.*`, `panel.caption.*`, `panel.arc.gapAbove/Below`.
  Never give one of them its own copy of these.
- Time (click the idle clock, 2026-11-13, the battery panel's language): the time big, hours and minutes as
  RollingNumber wheels (roll only on a normal +1; 59 -> 00 / 23 -> 0 / anything else jumps), seconds small
  and grey (per second only while open), the month and year in grey (not the full date: the week row
  already shows the weekday and the day; + optional week number, `Sys.weekNumber`); the day
  on an ArcGauge, midnight to midnight, orange up to now (per minute), a tick per hour; the week row with
  today in an orange circle. The analog clock face was dropped (two instruments in one panel).

### Island shape
- Screen corners: niri only rounds windows (`geometry-corner-radius`), so the shell paints the screen's corners
  (`ScreenCorners.qml`, Overlay layer, empty input mask, reserves no space), smoothed like the island's
  (screenCorners.smoothing; the corner maths, Config.cornerParams / cornerSvg, is shared with Island).
- Drawn as an SVG path (`Island.shapePath`) in a `Shape` with the CurveRenderer: Figma-style corner smoothing
  (`island.cornerSmoothing`); smoothing gives way when space is short, so the resting pill keeps half circles.
  Smoothing 0 (and not attached) = a plain `Rectangle` instead (`Island.plain`): measured 14.8 % vs 18.6 % of
  a core while the island springs nonstop, same at rest. For older laptops.
- Corner styles (`island.shape`: square / soft / round / full, default full = the user's tuned island;
  2026-11-13, the user chose 4 hand-tuned presets over a 0-1 roundness slider, "for a deliverable open-source
  project": every look a user can pick has been seen). Each style (`island.shapes.<style>`, advanced) gives
  a corner per role: `island`, `attached`, `flare`, `pill` (buttons, list pill, slider, search field, close
  buttons; 100 = always a pill), `row` (list/search highlights), `tile` (launcher tiles, notification
  pictures), `small` (keycaps, and the floor below). Code reads `Config.corner(role, size)` = the style's value,
  at most half the size. Never add a per-widget radius setting: pick a role. Intent: square = small but never
  0; soft = a bit more, the resting island's ends slightly squared; round = resting island a pill, panels
  not fully round; full = pills everywhere.
  Things hugging the island's edge are concentric with it instead: `Config.inner(outer, inset, size)` =
  outer corner minus the gap, never below `small`, at most half the size. Idle hover pills (IconSlot:
  `Config.restCorner`, `island.pillInset`), activity badges (Badge: `restCorner`, `activity.inset` by default;
  `outerCorner` / `inset` override it, e.g. the Wi-Fi password field's × badge). ArcGauge's band (track and
  fill) is a filled outline, not a stroke (caps can only be round or flat): its end corners are the style's
  `pill` corner (half circles in round / full, softened in soft / square), exact on the curved band. In
  every style the band reaches half its thickness past the end ticks (the end ticks keep the room they have
  in round / full; only the corners change), the fill as far past the level, so 100 % covers the track. The fill's outline is rebuilt per frame of the
  sweep (0.025 ms each). Circles by meaning stay circles (clock face, hands, today dot, battery ticks); screen corners
  (screenCorners.radius) are the display's, not the island's. Rejected before: a 0-1 roundness slider
  (scaling every corner; in-between values couldn't all be checked), and earlier named presets (`island.style`).
- `island.attachToTop` (off by default): flat top glued to the screen edge, concave flares
  (the style's `flare` corner) joining it to the edge, bottom corners the style's `attached` corner; shell.qml then drops
  the gap above the island. The flares are drawn outside the island's bounds (not clickable).
- Content is clipped to the island's rectangle (`host`), not to the curved path.
- The shape is drawn with each edge on the nearest device pixel (`Island.drawnX/Y/Width/Height`): at 1.25
  the 3 px gap and 38 px island put both edges mid-pixel, a faint row above and below that small corners
  (Square style) made obvious. Each edge snaps on its own (not position + size), so the content stays centred.
  Layout and transitions keep the exact size. Corner smoothing and blur weren't the cause (tested).
- Idle: the clock pill sits `island.pillInset` from the left edge, like the icons from the right
  (`island.paddingLeft` was removed: 4 px left vs 2 px top showed in Square).
- `island.blur` (off by default): the fill becomes `island.color` at `island.blurOpacity` and the top-bar window
  asks the compositor to blur behind the island (`BackgroundEffect.blurRegion`, ext-background-effect; niri
  26.04 supports it, its strength is niri's `blur { }` block). The region is a rounded rectangle on the island
  (`Island.blurCorner` = the clamped corner radius: the smoothed outline stays within 0.5 px of it; using the
  smoothing's start point instead left a ~10 px unblurred band). Turning blur on in the compositor itself
  (other desktops) is planned as a separate script. The flares aren't blurred.

## Behaviour

### Island transitions (IslandMode)
- Every mode is always instantiated; the leaving and the incoming mode coexist during a switch.
- Leaving: fades/blurs over `transition.fadeOut`, shrinks toward `outScale`, loosely follows the island (`outFit`).
- Incoming: waits until the leaving one is below `transition.handoff` and the island is `fadeInStart` grown,
  then fades in over `fadeIn` (opacity first, blur clears last) with a bouncy `pop` if it's opening.
- `minScale` (the smallest incoming content looks) maps the island's growth onto minScale -> 1; it must
  not clamp (`max(fit, minScale)` held the content still, then it jumped into motion: a mid-opening pause).
- Once open, content stops scaling with the island (`fitWeight`), so a mode resizing itself (search results)
  just reveals/clips instead of shrinking its content.
- A leaving mode is frozen (2026-11-15): nothing it shows may change while it animates out (the time
  panel's seconds jumped to :00 when the per-second clock switched off, the Wi-Fi list's highlight jumped and
  the list collapsed). On `active` going false a mode freezes its data (TimeMode.now, WifiMode.networks,
  BluetoothMode.devices, MediaMode.media + position: `x = x` breaks the binding, `Qt.binding` restores it on
  open) and keeps its look; resets, menus closing, animations stopping wait for `onScreen` (IslandMode:
  active or still fading) to go false. Moving things (music bars, the low battery pulse, ripples) keep
  moving until then. New modes follow the same rule.
- Closing must react on the first frame (Apple-style): fast-start curves (OutCubic, springs from rest) for
  anything leaving, never an ease-in, and `shrinkDelay` stays 0 by default. A hold or an ease-in at the start
  reads as lag.
- Island: grow and shrink use different springs per axis; the `shrinkDelay` hold applies only within 150 ms
  of a mode switch, not to a mode resizing itself. A mode whose size follows its content (search) grows at once
  and shrinks after a short debounce (`search.shrinkDebounce`) so the island doesn't pump while typing.

### Conventions
- A key that closes a mode or hands focus back (Escape, Enter in search) must call `mode.holdKeyboard()` right
  before `requestState`/acting (`mode.close()` does both). shell.qml then keeps keyboard focus (on `keyCatcher`)
  until that key is released: niri passes keys still held at a focus change to the next window (Escape made
  fullscreen videos exit fullscreen). Only hold it when the mode really closes/switches: holding moves focus
  away from the mode (that bug made the launcher stop responding after Enter with no result).
- Keyboard focus follows `Activity.panel` (a panel is open, even if covered by the volume), not islandState:
  activities never take the keyboard.
- Keyboard focus of the island window (shell.qml `keyboardFocus`): opened from the keyboard (launcher, IPC) =
  Exclusive; opened with the mouse = Exclusive too when `island.clickTakesKeyboard` (on: Escape closes a clicked
  panel right away), else OnDemand (the app keeps the keyboard until you click in the panel); idle = None.
  Activities never take it. "From the keyboard" = `keyHeld` at the moment of `requestState`.
- Panels opened from the keyboard (launcher, IPC) set `root.pinned`: they don't auto-close until the mouse has
  entered the island once (or Escape). Mouse-opened panels close `island.collapseDelay` after the mouse leaves
  (only while the panel itself is on screen, `Activity.panelShown`, and while the mode's `autoClose` is true).
- Click outside closes any open panel (`island.clickOutsideCloses`): shell.qml maps a transparent full-screen
  window on the Top layer (under the island's Overlay) only while `Activity.panel` is set. It must stay on a
  lower layer than the island: on the same layer, a surface mapped later would cover it.
- niri's window open/close animations mirror the island springs (`~/.config/niri/config.kdl`, `animations` block):
  window-open = `island.expand`, window-close = `island.shrink`, with stiffness = (2π / response)², damping-ratio =
  dampingFraction. When either spring changes, update niri too (and run `niri validate`).
  Only those two are mirrored. The camera/travel animations (`horizontal-view-movement`, `window-movement`,
  `window-resize`, `workspace-switch`) stay on niri's defaults: the user tried island-style springs there and
  didn't like it. Don't customize them.
- Battery color priority: charging (green) > power saver (yellow) > low battery (red) > performance (red) >
  balanced (white). Computed once in `Sys.battery.color`; every battery widget uses it, except the idle
  island's (`Sys.battery.idleColor`, 2026-11-15): there a bolt cut into its corner says charging
  (idle.battery.badge; power saver also gets a plus there), so the body keeps the next color in line (white when balanced) instead of green.
  The charging alert keeps its green battery and gets the same bolt once its fill sweep lands (charging.bolt),
  so the handoff to the idle island only changes the color.
- Idle: the clock (time only by default, `idle.clock.dateFormat` empty) and the status icons sit in `IconSlot`s
  (hover pill + fade + click) with the "dim base + bright overlay" look. The slot decides visibility (`shown`);
  the widget inside never hides itself. A slot's width springs open with the island's spring, so a new icon makes
  room exactly where it goes, then fades in. Spacing between icons is the slots' `gap` = `island.spacing`
  (0: the pills only show on hover, a gap would be dead space).
- Each file starts with a short comment saying what it is. Keep it accurate when you change the file.

### System settings (2026-11-16)
- The planned desktop settings app writes the system's settings (gsettings, logind...), never the island's
  config for shared values: the island follows the system. Today: the accent (gsettings accent-color, a
  name, mapped to a color by colors.systemAccents; Config.colors.accent returns it while
  colors.followSystemAccent) and the 12 / 24-hour clock (clock-format -> Sys.hour24, used by every clock;
  time.followSystemClock; the idle clock has idle.clock.timeFormat and timeFormat12h). One `gsettings
  monitor` stream + a read at start, nothing polls. Focus (do not disturb) is GNOME's
  org.gnome.desktop.notifications show-banners (false = Focus on): Sys.systemFocus / setSystemFocus. Fedora's default clock-format is 12h (locale default,
  not user-set): set to 24h on 2026-11-16 to keep the user's island. Test with an isolated dconf db
  (DCONF_PROFILE=<file containing `user-db:test`> for both qs and gsettings; delete ~/.config/dconf/test
  afterwards), never the user's.

### Sounds (2026-11-15)
- Only for what's worth hearing when you're not looking: notifications and alerts (Activity._sound, called
  by show() for a new activity, not an update in place). Never clicks, panels, toggles or the music controls
  (desktop clicks are silent; a skip sound would play over the music). Defaults: notification, low battery,
  charging on; headphones, Wi-Fi connected off. Quiet during Focus except low battery; one sound per
  sounds.minGap (a burst of notifications = one sound); nothing while the output is muted.
- Played by Sys.playSound(file): `pw-play --volume sounds.volume` (detached, one short process per sound).
- The sounds are our own (tools/make-sounds.py, no license questions). Retuned after studying bencho.dev
  (the user's reference for good UI sound; it synthesizes its sounds live with Web Audio, credits no source,
  free ones MIT / the rest a Pro licence, so nothing copied): pure sines, a faint octave "sparkle" on
  the last note, a soft gliding triangle body under some, every layer quiet; 0.6-0.9 s. Then made flatter
  ("it really wakes you up"): an octave lower, then 3 semitones more (notes ~260-660 Hz), low-passed ~1.1-1.4 kHz, no sparkle, 24-30 ms attacks,
  even note levels, under half the first loudness, sounds.volume 0.45. They should just exist, not startle. Soft, short, never a beep; each
  alert a recognisable motif (notification: rising fourth; low battery: falling third, mellower; charging:
  rising arpeggio; headphones: rising fifth; Wi-Fi: one high note). Tests: stub playSound in the copy (log
  instead of playing); `pw-play --volume 0 file` checks a file plays without a sound.

### Goodbye (power off / restart, 2026-11-13)
- The user didn't like the instant shutdown (it could freeze the launcher mid-close). Sys holds a logind
  *delay* lock on shutdown (`systemd-inhibit --what=shutdown --mode=delay ... cat`, stdin kept open: the lock
  dies with the shell, so a crash never delays a shutdown) and listens to `gdbus monitor --system` for
  `PrepareForShutdown (true,)`. That catches every shutdown that goes through logind (launcher, systemctl,
  power button). Activity then clears the queue and the panel and refuses any other activity; GoodbyeMode
  writes "bye bye" (iOS "hello"-style: one round stroke revealed with ShapePath `trim.end`), holds, and calls
  `Sys.releaseShutdown()`. logind waits at most InhibitDelayMaxSec (5 s default): delay + duration + hold
  must stay under it; `goodbye.maxWait` releases anyway. `PrepareForShutdown (false,)` (cancelled) gives the
  island back and takes the lock again.
- The handwriting (assets/handwriting/byebye.svg) was drawn for this after Apple's "hello" (the user's
  reference): thin monoline (stroke ~1/6 of the x-height, goodbye.strokeWidth 3.5 at size 64), ~11° slant,
  round wide bowls, tall narrow ascender loops, short descenders, long low lead-ins; one stroke per word
  (a joined "byebye" read as one word). The first version (upright, fat stroke, 2.2 s) felt slow and heavy. Tested only in a scratch copy (`Sys._shutdownAnnounced(true)`, lock
  command swapped for `cat`); never trigger a real shutdown to test.

## Release (2026-11-17)
Published as https://github.com/NiteChill/niri-island (public, GPL-3.0-or-later, release v0.1.0), with
the Settings app as https://github.com/NiteChill/niri-settings. README.md is for users: what it does,
how it works with niri-settings, what it needs (Fedora / Arch packages), install (clone into
~/.config/quickshell, niri spawn + binds). Keep it true when a dependency, a panel or an IPC call
changes. THIRD-PARTY.md credits Material Symbols. Commits use GitHub's noreply address.
docs/hero.png and docs/panels.png (the README's pictures) are made from the Settings app's repository:
tools/capture-island.py (stages a copy of this island with made-up data and grabs each state) then
tools/readme-images.py; remake them when the island's look changes.

## Reviews (the user's way, 2026-11-17)
When asked to review something (a mode, a change, the day's work): first give it a grade out of 10 with
the reasons in a few lines (what works, what holds it back), then rewrite / fix what holds it back to raise
the grade, and end with the new grade and what changed. Not a list of suggestions left for later: do the
work that augments the grade (checks, tests, CLAUDE.md, notify as usual).

## QML gotchas (each one caused a real bug here)
- `visible` reads the *effective* visibility: every child of a hidden item reads false. Never lay out from a
  child's `visible` when the parent can be hidden (MediaMode's title block, hidden during the fullscreen
  flight, centred the title as if there were no artist: the flying text aimed 10 px low, then jumped).
  Use the condition itself (`artist.text !== ""`).
- Never size a mode from a positioner (`column.implicitHeight`, `childrenRect`): a Column skips hidden
  children, and a mode is hidden until it fades in, so the island sprang to a smaller size, then changed
  course mid-opening (quick settings: 153 -> 189 px; notifications: 66 -> 82 px; a visible jolt). Add up the
  content's sizes instead (see BatteryMode, QuickSettingsMode, NotificationMode.textHeight).
- Never give a `Behavior` a `duration` (or any setting) that depends on the same state change that triggers it,
  e.g. `duration: active ? 0 : 300`. Qt doesn't guarantee update order: works on the first switch, then uses the
  stale value. Drive such animations imperatively from `on<Prop>Changed` (see `IslandMode.presence`). To jump
  without animating, disable the Behavior, assign, re-enable (see TimeMode, HeadphonesMode).
- Same root cause: inside `onFooChanged`, another binding that depends on `foo` may not have updated yet.
  Compute what you need from `foo` itself (SearchMode reads `viewHeightFor(placed.height)`, not `viewHeight`;
  reading the binding left the launcher closed on its first results).
- When `island.current` changes, the incoming and leaving modes' `onActiveChanged` run in an order Qt picks.
  Nothing may decide from the other mode's state synchronously there: IslandMode arms the incoming fade-in
  from `Qt.callLater` (`appearArmed`). Before that, volume -> brightness crossfaded at once while brightness ->
  volume waited for the handoff (2026-11-14).
- Animate only the normal step; jump on anything bigger. The time panel's second hand animated the gap between
  the per-minute clock (:00) and the first per-second tick, spinning round in a second. Same idea after suspend.
- A parent `TapHandler` also fires for taps on its children's TapHandlers: a parent that does something else
  (dismiss, open a panel) must ignore taps on its controls (`child.contains(child.mapFromItem(mode, pos))`, see
  LowBatteryMode, NotificationMode).
- Names that clash: a property named `enabled` on an Item shadows Item.enabled (WifiMode uses `wifiOn`); an id
  named `text` is asking for trouble; a function named `onSomething` looks like a signal handler.
  Inside a delegate/child that has a property of the same name, an id is shadowed: Icon has `glyph`, so
  `glyph.x` inside an Icon read the Icon's own (a CutoutBadge cut drew nothing; its id is now `mark`).
- Item already has `top` / `bottom` (anchor lines, FINAL) and `data`: don't name properties after them.
- Inline components (`component Hand: Rectangle {}`) go at the document root and can't see ids of the enclosing
  file: pass what they need as properties. Inside a `Rotation`, `angle: angle` binds the Rotation to itself:
  qualify (`hand.turn`).
- Don't read `host.children` in a binding that affects rendering: a blur layer adds children and causes a
  binding loop. `Island.modeList` is captured once at startup instead.
- A `SpringAnimation` inside a `SequentialAnimation` jumps straight to its end (it has no fixed duration). For
  "push, then spring back", start the spring from the first animation's `onFinished` (see LevelSlider.bump).
  Inside a `Behavior` it's fine.
- When a value must be updated only after a flag (e.g. spring direction), set the flag first and then the
  animated property imperatively (see `Island._w/_h`), instead of binding both.
- `Screen.devicePixelRatio` reports 2 on the 1.25 laptop output; the real ratio is
  `Window.window.devicePixelRatio` (1.25). Battery snaps its body to device pixels with it (Icon `fixedScale`,
  body bounds from `Config.glyph(...).parts`). Never draw a dim copy of an icon under a bright one: the two
  antialiased edges stack into a dark fringe; clip each part of a single copy instead.
- Selecting on plain hover is wrong whenever rows change under a still pointer (typing, scan updates): select
  only when the pointer's scene position actually moved (see the HoverHandlers in SearchMode / widgets/PanelList).
