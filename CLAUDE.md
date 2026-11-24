# Quickshell config: macOS-style bar + Dynamic Island notch

QML shell for Quickshell 0.3 on niri (Wayland, Fedora). Entry point: `shell.qml`.
Since 2026-11-23 (built on the `menu-bar` branch, merged into main on 2026-11-24; the previous island-only
design is the `v0.1-island` tag, pushed so the README's pointer works) the shell
is a top bar like macOS's with a notch in the middle like the iPhone's Dynamic Island:
- the **bar**: the focused app and the workspaces at the left; the tray, Bluetooth, Wi-Fi, battery, quick
  settings and the clock at the right, white over a black-to-transparent gradient. Each icon opens its
  **dropdown** right under it (Wi-Fi, Bluetooth, battery, quick settings, calendar): calm, Mac-menu-like
  (a title, a switch, the list), in the light / dark theme.
- the **notch** shows only what happens *now*: volume / brightness / mic feedback, alerts (low battery,
  charging, Wi-Fi connected, headphones, messages, goodbye) and the music playing (its base layer). A click
  on the music grows it into the media controls; a click on the resting notch opens the notification center.
- **notifications** drop in from above the screen's edge as cards under the notch, several at once, and
  stay in a history (the center) saved across reboots. Screenshots are cards that pile up.
Why (the user): discoverability. Everything was hidden behind the island and the launcher; "it's easy
for me because I know all the things. not everyone will". The island-centred design (idle island, calm
mode, panels inside the island, blur) was dropped on purpose: don't bring it back. (A separate "drop"
island + liquid shader existed even before; also removed on purpose.)

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
shell.qml              entry point: ONE top window (Overlay layer, the whole screen tall, reserves bar.height,
                       takes the pointer only where something is drawn: `mask`), holding Bar, the notification
                       stack, the dropdown card and the notch (Island + AllModes); islandState (= Activity.current,
                       else "rest"), root.open(name, byKeyboard), keyboard focus, IPC; the click-outside layer
ScreenCorners.qml      rounded screen corners (config screenCorners): 4 click-through overlay windows per screen
surfaces/
  Bar.qml              the bar: gradient, app name + workspace dots (left), tray + status icons + clock (right,
                       BarItems with their dropdown's name); anchorFor(name) = where a dropdown hangs
  Dropdown.qml         the dropdowns' card: an Island (attached false, corner role "menu", theme colors) holding
                       AllDropdowns; hangs under Bar.anchorFor(Activity.dropdown), else under the notch; appears
                       at its size from nothing (fade + panel.appear.scale), springs size + x between dropdowns
  NotificationStack.qml under the notch: the banners (ListView over Inbox.banners: drop in from above the screen,
                       others spring down) and the center (black pill + count + Clear all, NEW / OLD chips,
                       Inbox.model; Escape closes it)
config/
  schema.json          every setting described (section, group, label, type, default...). The defaults ARE
                       the shipped shell
  config.jsonc         the user's values. JSON with comments + trailing commas (Config.jsonc). Lists every
                       setting commented out at its default (`// "radius": 40,`); only the curated ones the
                       desktop settings app exposes are active (island.shape, island.cornerSmoothing,
                       <alert>.enabled...). Object { } lines always stay active, so uncommenting one line works.
                       Prose comments only in the /* */ header (the checker uncomments every `//` line).
                       Regenerate with `python3 tools/check-config.py --rewrite` (keeps active lines; always lays the file
                       out in the schema's order). Its first key "$schema": "./config.schema.json" tells Zed / VS
                       Code that comments and trailing commas are allowed
  config.schema.json   that editor schema (allowComments, allowTrailingCommas). Not the settings' schema
services/              singletons (registered in services/qmldir)
  Config.qml           schema defaults + config.jsonc; Config.<section>.<key>. Also the corner helpers
                       (Config.corner / inner / restCorner / restHeight / attached), the theme (Config.dark,
                       Config.theme = colors.light / colors.dark, systemScheme set by Sys) and the font's axes
                       (Config.axes(size, weight)). Each section is a `readonly property var foo: data.foo` line
  Sys.qml              ALL system data and actions: niri (one event stream: workspaces, focusedApp, overview,
                       fullscreen; focusWorkspace / toggleOverview), battery + power profile + time left, audio
                       output + volume + mic + the outputs list (audioOutputs / setAudioOutput), brightness, Wi-Fi,
                       Bluetooth, media (MPRIS; mediaLevels from cava; mediaColor), clock (+ calendarMonth,
                       weekdayNames, formatStamp), tray (trayItems, trayActivate / trayMenu), apps, files, pins,
                       wallpapers, screenshots, shutdown, desktop settings (gsettings: accent, clock format,
                       color scheme, Focus), notifications (the server, opening their window)
  Activity.qml         what is open (one at a time: `dropdown`, the notification `center`, the notch `panel`
                       "media" / "shelf" / "search"; open / toggle / isOpen / closeAll; unknown names ignored, "time" =
                       "calendar")
                       and what the notch shows: one queue, priorities (island.priority), timers, the music as
                       the base layer, sounds, `osd` IPC, do not disturb (gsettings show-banners)
  Inbox.qml            the notifications: history (ListModel `model`, newest first, saved in
                       Quickshell.statePath("notifications.json"), historyLimit), the cards on screen (ListModel
                       `banners`, each with its own paused-on-hover time), NEW / OLD (lastSeen), the screenshot
                       pile, open / action / dismiss / hide / clearAll; `revision` bumps on any change
island/
  Island.qml           the springing surface (notch and dropdown card): a path shape (continuous corners,
                       attached = notch flares), the active mode's size, the palette its content inherits
                       (fill / text / secondary), keepSize (the card fading out), jumping (no spring)
  IslandMode.qml       base type for modes: active state, requestState, keyboard focus, Escape, transition
modes/                 one file per mode (name = Activity kind / dropdown name)
  AllModes.qml         the notch's modes: RestMode (the small empty notch: hover grows it, click = center, a dot
                       while notifications are new), MediaMode, VolumeMode, BrightnessMode, MicrophoneMode,
                       MessageMode, LowBatteryMode, ChargingMode, WifiConnectedMode, HeadphonesMode,
                       NowPlayingMode (cover, nowPlaying.gap, bars), GoodbyeMode
  AllDropdowns.qml     the dropdowns: WifiMode, BluetoothMode, BatteryMode, CalendarMode, QuickSettingsMode,
                       SearchMode, WallpaperMode, ScreenshotsMode
widgets/               reusable pieces
  StyledText  Icon (every assets/icons SVG: `name` + `color`, drawn as a vector Shape)
  BarItem (a bar item: hover / open highlight, opens its dropdown, hover-switches while one is open)
  PanelHeader (a dropdown's title + something at the right)  Switch (the header's on / off)
  NotificationCard (one card: time, title, message, picture / app icon; urgent = red; screenshot = a pile;
  hover = whole text, buttons, ×; drag / scroll up = away)
  Badge  TitleStack  Battery  Wifi  Bluetooth (the bar's icons, always white there)  CutoutBadge (a glyph cut
  into a thing's corner: the battery's bolt)  CornerShape  Speaker  LevelSlider  LevelRow  QuickToggle
  MenuBadge  MediaBars  MediaCover  PictureCarousel  PanelList (the Wi-Fi / Bluetooth list chrome)
  RollingName (the carousels' title)  ScrollFade (a list's edge fades, in palette.window)
  RowHighlight (a list's lit row: springs while shown, fades out in place, jumps when it shows again)
  MovedHover (a HoverHandler reporting only real pointer moves: a still pointer leaves the keys in charge)
  DropZone (the drop zone's drawing: live in DropMode, muted as the empty shelf)  NotchTabs  Switch
assets/icons/          SVG icons, referenced by file name from the config: Material Symbols Rounded, ALL filled,
                       weight 400, optical size 20, from one source so their strokes match (2026-11-23: the set
                       mixed Material icons on its 960 grid with others drawn on a 24 grid, heavier or lighter;
                       the user: "make sure they are all at the same optical stroke length"):
                       fonts.gstatic.com/s/i/short-term/release/materialsymbolsrounded/<name>/fill1/20px.svg.
                       A new icon: the same URL, nothing else. One exception, the user's call (2026-11-24): the
                       bar's quick settings icon is the outlined page_info (page-info-outline.svg, the URL's
                       `default` instead of `fill1`). Kept as they were: battery.svg, gauge-balanced.svg,
                       skip-triangle.svg (adjusted / derived),
                       volume-level0 / level1.svg (volume-up's speaker at its place, the right left empty: Material
                       centres each, so the bright level slid off the dim full speaker under it, 2026-11-24), the distro logos. Phosphor was tried the same day
                       ("looks off here"); SF Symbols can't be shipped (Apple's licence).
                       Drawn by widgets/Icon: <path> elements only, a viewBox, no transforms, no strokes. A path
                       starting with a relative "m x y" + more pairs works (Config._svg adds the "l")
assets/fonts/          Allo (AlloVariable.ttf, OFL, assets/fonts/OFL.txt): axes opsz 9-32, wght 100-900, ROND 0-100
assets/sounds/         the sounds (WAV), generated by tools/make-sounds.py
assets/handwriting/    stroked SVGs written by GoodbyeMode
bin/screenshots        the screenshots picker's helper: `list`, `transfer` (file transfer portal keys)
bin/wallpaper          lists the wallpapers, reads / sets the current one
tools/make-sounds.py   synthesizes assets/sounds
tools/check-config.py  validates config.jsonc against schema.json, QML Config reads, section exposure, icons;
                       RETIRED keys (what niri-settings may still write) only warn
tools/readme-images.py the README's pictures (docs/*.png) from a staged scratch copy: see Release
tools/scratch-copy.py  builds a safe test copy (stubbed commands, no keyboard, no reserved space, a grabbable
                       `scene`, an optional Tester.qml): see Testing a change
```

Import paths are relative folders: modes use `import "../services"`, `"../island"`, `"../widgets"`;
surfaces use `"../services"`, `"../island"`, `"../modes"`, `"../widgets"`. Only `services/` has a
hand-written `qmldir` (for the singletons).

## Workflows

### Adding or changing a setting (always all steps)
1. Read it in QML as `Config.<section>.<key>` (never a literal).
2. Add an entry to `config/schema.json` in the right section/group:
   `key`, `label`, `description` (plain language: what it changes, for a non-developer), `type`,
   `default` (the shipped value), and `min`/`max`/`step`/`unit` for numbers.
   Mark technical knobs `"advanced": true`. Types are listed in the schema's `types` block.
3. `python3 tools/check-config.py --rewrite` lists it in config.jsonc, commented out at its default (don't
   hand-add active values there: an active line is the user's override, not a default).
   A corner: never a raw `radius:` or a new radius setting; pick a role, `Config.corner("row", height)`.
   A color that differs between light and dark: a `colors.light.x` + `colors.dark.x` pair, read as
   `Config.theme.x` (white / black things that never change: `Config.colors.*`).
4. A brand-new top-level section also needs `readonly property var foo: data.foo` in `services/Config.qml`.
5. Run `python3 tools/check-config.py`; it must print `OK`.

Section/group placement follows what the user would look for, not the code: Appearance (font, colors,
light and dark), Bar (+ tray), Notch (`island.*`: shape, rest size, behavior), Animation, Pop-ups
(`activity.*`), Dropdowns (`panel.*`: width, header, switch, lists, opening), then one section per
dropdown / alert. Editing the JSON files with a script: build the whole text first, then write it at once
(temp file + rename; the live shell reloads on save). schema.json is written with indent=2 and
ensure_ascii=False (anything else rewrites the whole file). The live shell's log.log can stop updating
after a flood of warnings: read the whole log with `qs log <by-id dir>/log.qslog`. config.jsonc isn't
plain JSON: parse it with the checker's `jsonc()`.

### Adding a dropdown
1. `modes/FooMode.qml`: root `IslandMode`, `implicitWidth: Config.panel.width`, `implicitHeight` added up
   from its parts (never a positioner), content in an `Item` padded by `Config.panel.padding`. Calm: a
   `PanelHeader` (title + a `Switch` or a value) then the list (`PanelList`) or rows. Colors from the
   palette (`palette.windowText` / `placeholderText` / `window`), the theme (`Config.theme.*`) or the
   accents (`Config.colors.accent`...): never Config.colors.text for text, it's white in light mode too.
   Keyboard: `keyTarget: mode`, Up / Down / Enter / Space; Escape closes by itself.
2. Register it in `modes/AllDropdowns.qml` (`FooMode { name: "foo" }`) and add "foo" to
   `Activity.dropdowns`. `launcher: Config.foo.launcher` lists it in the search.
3. A way in: a `BarItem { dropdown: "foo" }` in Bar.qml (and add it to `anchorFor`, so the card hangs
   under it), and/or IPC (`qs ipc call island toggle foo`). Not from the bar = under the notch.
4. Its settings: a "Foo dropdown" section in schema.json (+ the Config.qml line), then `--rewrite`.

### Adding a notch activity (something the system or a key puts up)
1. `modes/FooMode.qml`: root `IslandMode`. One-line activities are `island.restHeight` tall
   (= island.activityHeight), two-line ones `Config.activity.tallHeight`; something as small as the
   resting notch sets `belowMinimum: true`. Register it in `modes/AllModes.qml`.
   Its own entrance animation starts from `onAppeared`, never `onActiveChanged` (at activation the content
   is still invisible). Before `appeared`, hold the start pose; `hasAppeared` tells whether it's on screen.
   Something the system triggers just before the pop-up (Activity.bumped) is sent after `feedback` and held
   until it's on screen (LevelRow `starting` / `live`).
2. Show it through Activity: `Activity.show("foo", key, cls, data, timeout)`. Same key = updates in place;
   `cls` is its priority class, listed in `island.priority` (config + schema description). Keep user
   interaction above system things, nowPlaying last. Give it a `foo.enabled` setting (default true, active
   in config.jsonc) checked where Activity shows it.
3. Data and actions go through Sys. A mode that shows Activity data latches it on `Activity.onCurrentChanged`
   (see MessageMode), so it stays right while fading out.
4. Keys: niri binds `qs ipc call osd ...` (Activity's IpcHandler). Caps lock was dropped on purpose: only
   polling can see it, and the user won't trade deep CPU idle for it.
Notifications are not notch activities: they go through Inbox (cards + center).

### Testing a change
- The running shell live-reloads on save (it runs whatever is on disk, mid-edit included). A new schema
  section (or a new `readonly property var foo: data.foo` in Config.qml) can reload with the old
  settings: every new Config.foo.* read undefined, and on 2026-11-23 the shell then spun at 100 % CPU,
  frozen (no IPC, no notifications). After adding a section, check the live log; if it says "Cannot read
  property ... of undefined", restart it: `kill <pid>; setsid -f quickshell` (Island now ignores NaN sizes).
  A test copy given a new section while running DID get it (2026-11-24): the trigger of the stale case is
  still unknown, so no "fix" was kept. Its log: the
  newest `/run/user/1000/quickshell/by-id/*/log.log` with "Reloading" in it; `touch shell.qml` triggers a
  clean reload, judge only warnings after it. Editing only an SVG doesn't reload: add then remove a newline
  at the end of shell.qml.
- Quick load check: `timeout -s INT 4 qs -p . 2>&1 | grep -E "WARN|ERROR"` (SIGINT so the output flushes;
  "Could not register notification server" is expected for a second instance).
- **Scratch copy** (the default way to test): `python3 tools/scratch-copy.py <scratchpad>/copy --tester
  T.qml [--shelf DIR] [--light]` builds it: every command stubbed (search actions, files, the bar menus,
  the shelf's trash / clipboard), Sys's sounds / wallpaper / opening stubbed (they log "TEST ..."), the
  user's config.jsonc left out, its own shelf folder, `exclusiveZone: 0` (else the user's windows move)
  AND `keyboardFocus: None` (an open dropdown takes the keyboard exclusively: on 2026-11-23 the user's
  typing reached a test copy's Wi-Fi dropdown and Space switched their Wi-Fi off and on), the visual
  children in `Item { id: scene }`, and T.qml as a `Tester {}` (Timers: `Activity.open("wifi")`, `Activity.feedback(...)`, `Activity.show(...)`,
  `Inbox._insert(row) + Inbox._showBanner(uid, 0)` for fake notifications, `Inbox._screenshot({ summary },
  path, w, h)` for the pile). Run a step, wait ~1 s, `scene.grabToImage(...)`, run the next step from the
  grab's callback (grabbing then changing state in the same handler captures the new state). The grab is
  transparent: composite it over a wallpaper with PIL. A test-copy history / pins live in its own
  `~/.local/state/quickshell/by-shell/<id>`: delete that folder afterwards. Logs: `console.warn`.
- Light mode: `--light` (never the user's gsettings).
- Fake data for stress tests goes in the copy's Sys. Nothing in a test may connect, run commands or change
  the system. Never `niri msg action screenshot-screen` (it overwrites the user's clipboard).
- Real input: `qs ipc call island toggle <name>` is harmless but a toggle. Never send real keys (`wtype`).
  The real mouse wheel / hover can't be tested from here: test the maths instead and say so.
- Measure before fixing "it feels slow/buggy" (property-change counters, `Date.now()` timings, standalone
  benchmarks). Report before/after numbers.
- Transitions: a Timer switching repeatedly + `grabToImage` every ~30 ms, tiled. Check several switches in
  a row.

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
  over the ListView, gradients in the surface's color (palette.window). (A MultiEffect mask, used while the
  island could be blurred, needs maskThresholdMin 0.5 + maskSpreadAtMin 1 for a smooth ramp.)
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
The font ships with the shell: Allo (assets/fonts/AlloVariable.ttf since the bar redesign, 2026-11-23;
Google Sans Flex before; OFL 1.1, assets/fonts/OFL.txt; axes opsz 9-32, wght, ROND), loaded by Config's FontLoader (font.bundled) before any text asks, so
it looks the same without the font installed. A font file loaded by the app registers only its default
weight: every text also sets the variable `wght` axis to its weight, next to `ROND` (StyledText does
it by hand in _syncAxes: a binding reading font.weight into the same font looped; the two TextInputs and
RollingNumber's metrics set both axes). Checked with a fontconfig that hides ~/.local/share/fonts:
(checked 2026-11-17 with Google Sans Flex) the bundled file renders like the installed one; without it,
Noto Sans. The file is a
`fontFile` setting: check-config.py fails if it's missing from assets/fonts.
Never a bare `Text {}`. `widgets/StyledText.qml` applies `Config.font` (family, size, weight, color, and
`roundness` = the font's `ROND` axis via `font.variableAxes`, rounding the letter ends; `opsz` follows the
size: Config.axes(size, weight)). One font everywhere: never give a mode its own font family or roundness (the user
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

### Language
Each piece keeps the layout that suits it, but they all follow these rules.
- The bar: white icons and text (`Config.colors.text`) always, whatever the light / dark mode, over the
  gradient (bar.gradient: Apple's trick, readable on any wallpaper). The shade follows a curve,
  opacity * (1 - y)^curve over nine stops (0.3 at the top, ~0.2 behind the icons, a long soft tail over
  110 px): a straight two-stop fade ended in a visible line (the user, 2026-11-23). Status icons use the "dim base +
  bright level" look (bar.overlayOpacity: Wifi, Battery). A BarItem lights a pill behind it on hover and
  while its dropdown is open; hovering another item while a dropdown is open switches to its dropdown
  (like the macOS menu bar).
- The notch: black, white text; pop-ups follow the activity language: content hugs both ends, the middle
  stays empty; one-line activities are `island.restHeight` tall, two-line ones `activity.tallHeight`;
  badges concentric with the notch's rounded end (`activity.inset`), soft (tint at `activity.badgeOpacity`)
  or solid ("this is on", glyph from `Config.onColor`); two lines = TitleStack (grey caption over white).
  Each activity has an accent: red = danger / muted, yellow = power saver, green = charging, blue =
  Wi-Fi / info / connected. Never dim text with opacity for "secondary": use the secondary color.
- The dropdowns (2026-11-23, the user: "simpler and calmer, just a little toggle and the list, not a full
  huge icon"): the macOS menu's calm. A title at the left and a switch (or the value) at the right
  (PanelHeader), then the list with small grey group titles, a springing highlight, a blue check on what's
  in use. No big symbols, gauges or pills: the big instruments of the island era (the battery's arc gauge,
  the Wi-Fi and Bluetooth symbols drawn as strokes, the time panel's day arc) were removed with it.
  Light / dark from the desktop (Config.theme); accents stay the same, except the light theme's darker
  charging green and power saver yellow (theme.charging / theme.powerSaver).
- The cards (notifications, 2026-11-23, the user's reference: an "Alerts 3" pill under a notch, NEW / OLD
  chips, white cards with the time in grey on top, the title, a picture at the right): the theme's card
  color (white in light mode), a soft shadow, `menu` corners; urgent ones filled red, text white.

### The bar
- bar.height 38 with the notch at 32 (2026-11-23: the notch touching the windows felt wrong while music
  played; the user said "taller bar or smaller notch, pick one": the bar, because a smaller notch would
  shrink the music's cover to a speck).
- Left: the distribution's logo (Sys.distro from /etc/os-release, bar.logo.icons -> Simple Icons logos;
  its menu, "system": Files, Settings, Search, Wallpaper, Screenshots, Notifications, then Lock / Log out /
  Restart / Shut down, the last three asking for a second click), the focused app's name (Sys.focusedApp,
  bold; its menu, "app": the window's title, Fullscreen, Maximize, Float, Center, Close, by niri id {id};
  niri has no minimize). Rows follow the window (2026-11-24, "it stays maximize even when maximized"):
  a menuList row with `state` shows `onTitle` / `onIcon` while Sys.focusedState[state] is on (Float ->
  Tile, Maximize -> Restore, Fullscreen -> Exit fullscreen). niri gives is_floating; fullscreen and
  maximized are measured (window = output size; column >= bar.appMenu.maximizedShare of its width) and the workspaces (Sys.workspaces, dots, the active one a longer pill). Both menus
  are MenuMode with a menuList setting (bar.logo.items / bar.appMenu.items).
  Sys.focusedApp falls back to the focused workspace's active window: while the bar's window has the
  keyboard (a dropdown open) niri reports no focused window, and the app's name vanished (2026-11-23).
- Workspaces: ONE TapHandler (the BarItem's) decides from where the click landed (dots.itemAt(i).contains):
  on a dot = focus-workspace, elsewhere = toggle-overview. A dot's own TapHandler fired and then the item's
  too: it switched, then opened the overview (2026-11-23). Each dot's target includes half the gap.
- Hover only promises what a click does (the user asked, 2026-11-23): BarItem lights its pill and shows the
  hand only when `clickable` (by default: it has a dropdown). Anything passive in the bar must not. Tray
  icons: a click (left or right) opens the app's menu when it has one (macOS menu bar extras; DashBeam did
  nothing on "activate"), else its main action; middle click = the main action; clickable =
  Sys.trayClickable. The menu is drawn by the shell: the "tray" dropdown (TrayMenuMode, Activity.trayId
  = which app; QsMenuOpener over Sys.trayMenu(id); submenus with a Back row; mnemonic _ / & stripped),
  under its icon (Bar.anchorFor("tray")), hover-switching between tray icons like the rest
  (BarItem.lit / switchable, Bar.aimTo("tray:<id>")). The system's own drawing (item.display) needs
  `//@ pragma UseQApplication` (Quickshell as a widgets app): without it, it silently did nothing.
- List highlights in every dropdown follow one rule (2026-11-23): shown while the pointer is over the
  list, or after an arrow key (then it stays); when the pointer leaves, it fades out where it is (its
  row is kept: dropping to the first row slid it up while fading), and when it shows again it jumps to
  its row instead of sliding from the old one (the y Behavior is off while invisible). PanelList.keyShown,
  BatteryMode / MenuMode / TrayMenuMode shownRow, MenuBadge shownRow + _byKey.
  One selection per list, driven by both: the pointer sets it only when it really moves (its scene
  position changed: HoverHandler.onPointChanged + lastScene, never plain hover), so with the pointer
  resting on a row the arrow keys take over, and its next move takes the highlight back (the user,
  2026-11-23). A key with the pointer inside moves at once; with it outside, the first key only shows the
  highlight (on the first usable row if it sat on a greyed one).
  The tray menu missed this rule until 2026-11-24 (the user: "the tray icon menu doesn't have the
  hover/focus fix"): its rows change under a still pointer (a submenu, Back, the app updating its
  menu, hovering to another app's icon while it's open) and the highlight lit whatever row the old index
  fell on. Now TrayMenuMode.pointerFresh: the pointer lights a row only after it has moved over the rows
  shown now (reset on open, on entries / inSub changes, on trayId changes, which also reset the
  selection like an opening). Any list whose rows can change while the pointer rests on it needs the
  same; check every menu when the rule changes, not only the one being fixed.
  RowHighlight (battery, bar and tray menus) still slid up as it faded (the user, 2026-11-24): a row
  going unlit changes `shown` and `rowY` (row 0's place, the lists' "none") in one go, and when Qt
  applied rowY first the highlight took it while still shown. It now takes a new place only after the
  change is over (Qt.callLater), if still shown: measured, it fades at its row (y 60 throughout).
  PanelList and MenuBadge keep their place by themselves (no fallback row).
- Switching dropdowns along the bar waits while the pointer heads into the open card (Bar.aimTo, the
  "menu aim" triangle: from where the pointer came from to the card's top corners widened by bar.aim.slack;
  inside it, wait bar.aim.delay and switch only if the pointer stopped on the other item). Measured in a
  scratch copy: quick settings -> down-left across the battery = aiming (waits); sideways along the bar =
  switches at once. shell.qml also adds the gap between the bar and the card to the window's input
  (bridgeArea), so the pointer never crosses "nothing" on the way down.
- Right, in order: tray (Sys.trayItems; click = activate, or the menu for menu-only items; right click =
  the item's own menu via `item.display(window, x, y)`, drawn by the system; tray.monochrome off by
  default: colorizing an icon drawn on a filled square gave a white square), Bluetooth (dim while off),
  Wi-Fi (bars; wifi-off.svg while off), battery (the bolt / plus cut into its end:
  bar.battery.badge; in the alerts' color, Sys.battery.color, percentage included, since 2026-11-24: "make
  the battery icon the same as in the alerts"; bar.battery.colored off = white like the rest), quick settings (tune.svg), the
  clock (bar.clock.dateFormat "ddd d MMM" + the time). No volume icon (the user: "no sound slider in the
  top bar"): the volume is in quick settings and the notch.
- Fullscreen (Sys.fullscreen: the active window of the active workspace is the output's logical size,
  overview closed): the bar slides up and fades (bar.hideInFullscreen); the notch stays. Resting the
  pointer on the top bar.reveal.edge px (shell.qml's revealEdge, in the input mask only while hidden)
  brings it back after bar.reveal.showDelay (2026-11-24, "so that the top bar is still accessible"); it
  stays while the pointer is on it or a dropdown is open, and leaves bar.reveal.hideDelay after.
- The window reserves bar.height; it is the whole screen tall so the dropdowns and cards hang below
  the bar in the same window (one keyboard focus, z order by declaration: bar < cards < dropdown < notch).

### The notch
- What it is (2026-11-23, second design round): what happens now AND what it holds. Notifications left it
  for the clock (the user agreed: macOS pairs them with the calendar).
- At rest (RestMode): island.rest.width x height (120 x 28: "a bit less wide and less tall, so it's
  calmer when it has nothing"); the music keeps its own 140 x 32 (nowPlaying.width / height).
- Opening the notch (2026-11-23, after a peek design was tried and dropped: "no preview mode at all";
  hover opening was dropped too, "click only"): a click on the resting notch or the music opens the real
  player (MediaMode) or the real shelf (ShelfMode), Activity.openNotch: the shelf when something was put
  on it in the last island.tabs.recent s (Sys.shelfTouched), else the player when music plays, else the
  shelf. When both have something (Activity.notchTabs), tabs show in a small black pill of their own
  just under the open notch, NookNotch-style (the user's reference, 2026-11-23; a navbar inside the notch
  came first): widgets/NotchTabs in shell.qml, riding the notch's bottom edge (y = island bottom +
  island.tabs.gap), in the window's input mask (tabsArea). The open tab shows its icon and name ("Music",
  "Shelf"), the other its icon. Switching (2026-11-23, "animate the tabs better"): the old name fades out
  at once, widths / the lit pill / the icon's place ease (island.tabs.resize, InOutCubic: springs read as
  jumpy here), the new name fades in after island.tabs.labelDelay (an imperative animation: a Behavior's
  timing can't depend on the change it animates). A click or Tab switches, the notch morphing between
  the two sizes. Chosen over stacking both (a ~450 px slab every click). No hover effect at all
  (a widening on hover was removed: the music's cover and bars snapped to the new width while the notch
  eased).
- The drop area is not the notch (shell.qml's DropArea `dropZone`, 2026-11-23): sized like the notch,
  but while a drag is over it, held at the size the notch had when it came (or the drop zone's, if
  bigger), in the input mask (dropHold), and a drag must stay out island.drop.leaveDelay to count as
  gone. As part of the notch, dragging over the big open shelf looped: the notch shrank to the drop zone,
  out from under the pointer, the drag "left", the shelf grew back under it, the drag "entered"...
- The empty shelf is the drop zone, muted (2026-11-24, "smaller, just the drop area but muted"):
  widgets/DropZone is the zone's drawing, live in DropMode (accent arrow bobbing), muted in ShelfMode when
  empty (grey, still, island.drop.mutedOpacity, at the zone's size).
- The drop zone (DropMode, class "drop", first in island.priority; 2026-11-23: "more inviting, and not as
  big"): while something is dragged over the notch (Activity.dropping) it's a 280 x 92 notch with a
  dashed outline, a bobbing download arrow, "Drop to keep it" and the folder's name. Dropped: bin/shelf
  add, then Sys.shelfAdded opens the shelf focused on the new file (Sys.shelfFocus).
- The shelf (ShelfMode, notch panel "shelf"; 2026-11-23: "the island holds screenshots. it should have
  a folder dedicated to it"): the files of shelf.folder (~/Island), newest first, in PictureCarousel
  (the old screenshots picker's interface, which it replaced). Two ways in: dropped on the notch (a
  DropArea over the Island in shell.qml: Activity.dropping opens the shelf, "Drop to keep it here";
  bin/shelf add copies files, downloads http(s) addresses, "name 2.ext" for taken names, the copy dated
  now so it sorts as new) and every screenshot (Inbox._screenshot -> Sys.shelfKeep -> bin/shelf keep: a
  hard link, no extra space, else a copy). Each card: a picture as itself, else the desktop's thumbnail
  (bin/shelf list runs the installed /usr/share/thumbnailers into ~/.cache/thumbnails/large, the
  freedesktop cache Files uses: PDFs, videos, office files, fonts), else the type's icon + name
  (PictureCarousel previews / icons / names; carousel.file.*). The icon is found by bin/shelf in the
  gsettings icon theme, then Adwaita, hicolor: Quickshell.iconPath(name, true) returned "" for every
  type icon (it doesn't know the desktop's theme; app icons work because they're in hicolor).
  Click / Enter = open, right click / Shift+Enter = show in Files, Ctrl+C = copy a picture, Delete or the
  dark × on the front card (PictureCarousel.removeIcon: drawn in the card, so it moves with it; the
  carousel's own tap ignores it) = shelf.removeCommand. Removing: the card shrinks and fades
  (PictureCarousel.leavingPath, carousel.leave.*), then it's taken off Sys.shelf at once (no wait for the
  trash and a re-read), the selection stays at its place and the card taking it slides in from its side
  (PictureCarousel.relocate; before, followNewest jumped back to the newest) (gio trash: never deleted outright), drag the front card
  out = the file (portal key for sandboxed apps, as before). Real drops from other apps onto the notch
  are untested from here (they need a real drag).
  Listing never waits for thumbnails (2026-11-23: the shelf opened "empty", focused on nothing, for the
  second a dropped PDF's preview took): `bin/shelf list --cached` comes at once, `bin/shelf thumbnails`
  then makes the missing ones and the folder is read again; a dropped file is put at the front of
  Sys.shelf the moment the copy is done. It grows island.rest.hoverGrow under the pointer (it can be clicked) and a
  click toggles the notification center; a small dot (colors.notificationDot) while some are new.
- The music (NowPlayingMode, 2026-11-23): the base layer, nowPlaying last in island.priority: shown the
  whole time music plays, every alert covers it, then it comes back; paused, it stays nowPlaying.linger s.
  nowPlaying.width x height (140 x 32), cover at the left, bars at the right. Not while you're in the player (nowPlaying.hideWhenFocused,
  Sys.mediaFocused): the MPRIS player's desktop entry / identity against niri's focused app id; for a
  browser (nowPlaying.browsers) the tab in front must be the playing one, judged from the window's title
  (= the active tab's): it holds the track's title, or a music site's name (nowPlaying.musicSites; Zen on
  YouTube Music titles its window just "YouTube Music — Zen Browser"). Can't tell = keep showing it. Click = the media controls (MediaMode) grow out of the notch.
- Pop-ups (volume, brightness, mic, alerts, messages, goodbye): as before; the notch grows to
  island.activityHeight (38) for them.

### Dropdowns
- One card (surfaces/Dropdown.qml) hosts them all with the island engine: switching from one to another
  morphs the card (size, and place under the new icon: anchorX spring) while the contents only crossfade
  (Island.plainFade: no scale-to-fit, no pop, no blur; 2026-11-23, the user: "just fade and morph": Wi-Fi
  and the calendar used to pop in with the notch's scale). Opening from nothing jumps to the right size and
  place and fades in; closing fades out in place (Island.keepSize holds the size; the anchor isn't moved
  for "": it slid to the screen's middle as it faded). Centred under its bar item,
  kept panel.margin inside the screen; search / wallpaper / screenshots hang under the notch.
- Closing: Escape, a click outside (the click-catcher layer on the Top layer, mapped while
  Activity.anyOpen), clicking its icon again. No auto-close when the mouse leaves (Mac menus don't).
- Wi-Fi / Bluetooth: "Wi-Fi" + switch, then PanelList (saved, then others; Wi-Fi's password field inline
  under its row, Bluetooth's pairing / connecting states, as before). Nothing found yet: "Searching…".
  Scanning / discovery only while open (Binding on Sys.wifiScan / bluetoothScan).
- Battery: "Battery" + the percentage (green while charging, red when low), the time left / to full /
  "Fully charged" in grey, then "Power mode" and the three modes as rows (icon, name, check; Up / Down /
  Enter).
- Calendar (2026-11-23, replaced the time panel): the month (Sys.calendarMonth(offset)), ‹ › and the wheel /
  Left / Right move months, a click on the title comes back (a tap area over the title only: on the whole
  header it also caught the arrows, and › never left the year); weekday letters; six weeks always (constant
  height); today in a time.accent circle; optional week numbers.
- The wallpaper picker lives in the notch too (2026-11-24, the user's call; it's the shelf's carousel
  sibling): a notch panel, not a tab (it's reached from the logo's menu, the launcher, IPC). Its title
  and the shelf's share panel.nameSize (16).
- Search lives in the notch (2026-11-23, decided with the user over a vertically centred floating card:
  the notch is the place you talk to the system, and it was a notch mode once already): a notch panel
  (Activity.notchPanels), dark like the notch, growing downward with its results; the notch Island's
  extraModes = the dropdowns', so the launcher still lists them. The tabs pill hides while it's open.
- Search: Raycast-style launcher: magnifier, hairline, results grouped under grey section titles (groups ordered
  by best match), icons on soft rounded tiles, kind at the right, "Open ↵" keycap on the selection; scrolls.
  Pins (2026-11-15): with nothing typed it shows the pinned panels / apps / commands as tiles (icon + name,
  search.pins.columns per row, each row centred (a short last row sits in the middle, 2026-11-19; Up / Down go to the tile visually above / below, SearchMode.pinMoveRow, and hovering the empty space beside a short row selects nothing, tileAt); no title above them: the user asked for just the tiles), with the lists'
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
  then the browser comes forward (2026-11-19, search.web.focusBrowser: a running browser opened the tab
  behind or on another workspace, "it seems to have done nothing"): the default browser's desktop file
  (search.web.browserCommand) matched against niri's windows like a notification's sender (_senderWindow),
  its most recently focused window gets niri's focus-window;
  alone, it's what Enter picks. Not pinnable, not in file search.
- Quick settings dropdown (the bar's quick settings icon; designed 2026-11-14 as an island panel, the
  same inside the dropdown card since 2026-11-23, plus the sound output line). What follows is its
  original description; "panel" = the dropdown, "island" = the card:
  Quick settings (2026-11-14): nothing boxed, like the other panels (a grid of grey Control Center tiles was
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
  Badge click = toggle; the word under Wi-Fi / Bluetooth opens their panel. Ways in: the bar, Mod+S in niri, the launcher. Chosen over widgets in the empty launcher (two jobs in one place, keyboard
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
  Sound output (2026-11-23, the bar has no volume icon on purpose): under the volume, "Sound output" and
  the output in use; a click unfolds Sys.audioOutputs (Pipewire sinks, plain values) to pick another
  (Sys.setAudioOutput -> Pipewire.preferredDefaultAudioSink). Keyboard (2026-11-24): the line is a spot
  after the level rows (Space / Enter unfold, focus on the output in use; again folds), each output a
  spot while unfolded (Space / Enter pick it); the focus highlight takes the rows' own hover rectangle.
- Media controls (2026-11-14, Apple's expanded "now playing"; since 2026-11-23 the one panel that grows
  out of the notch, from a click on the music playing in it): cover (rounded tile, a note without one), title in white
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
  no timing (MediaMode.hasTimeline). Tested with a fake player (2026-11-15).
  Untimed (2026-11-19, "broken half the time"): Firefox / Zen build both Position and mpris:length from
  the page's navigator.mediaSession.setPositionState (GetPositionSeconds is 0 and the length key is left
  out without it); YouTube Music in Zen often sends none, even across track changes (checked with
  busctl). The row then stayed hidden and the panel changed height whenever the timing came or went,
  which read as broken. Now the progress row is always there and the panel never changes height (iOS
  shows --:--, Plasma disables its bar): untimed = empty bar, not draggable, media.progress.unknownTime
  for both times. The old resize-with-the-row animation (resizing / timelineRoom / rowIn / rowOut) is
  gone. Sys prefers a player with a track: one left with no title never hides one that has one.
  Dragging only previews; the seek is sent on release (the wheel: debounced).
  Space / Left / Right. Ways in: the music in the notch, the launcher, IPC.
  Fullscreen (a double-click grew the island to the screen, the cover flying to a big picture over a
  blurred backdrop) was removed on 2026-11-19 with everything it needed (IslandMode.fullscreen,
  Island.expansion, the fullscreen springs, SwapImage): the user found it not worth its complexity.
  Don't bring it back.
  Covers (MediaCover) have smoothed corners (Config.roundedRectPath, island.cornerSmoothing).
  The bars follow the real sound through cava (`sudo dnf install cava`; media.bars.realSound; Fedora's cava
  has no PipeWire input: `method = pulse`, through pipewire-pulse), run by Sys
  only while music plays and a MediaBars is running (Sys.mediaLevelUsers); without cava they dance on their
  own. Tested with a fake cava + fake player; never seek the user's real player to test.
- Wallpaper picker (a dropdown under the notch since 2026-11-23; 2026-11-16, the user's reference: a tilting card carousel): pictures of wallpaper.folders
  (default ~/Pictures/[Ww]allpaper*, the Settings app's folder) as landscape cards in the screen's
  proportions; the selected one in front, side.count neighbours behind on each side (smaller, turned,
  darker), the next fading in from further out. Only 2 * side.count + 3 card items exist; each takes the
  next picture as it leaves one end (`pic` = the window index congruent to its slot). Width and padding are
  the launcher's (search.width / padding, 2026-11-17: the user wanted the same size); the front card's
  width is what the side cards leave (no card width setting). Hover tilt + shine: removed on 2026-11-17
  ("preferred it plain"), brought back on 2026-11-24 at the user's request (the old code was gone, never
  committed): the card under the pointer (any card, 2026-11-24) tilts toward it, each on its own spring
  (carousel.tilt.*: up to 9 degrees, a
  Matrix4x4 with a real perspective, viewer carousel.tilt.depth px away, because Qt's Rotation puts it
  1024 px away and the tilt was invisible; its z row is identity, not rotated (rotated: the card went
  "behind" its neighbours and got cut) and not zero (singular: the vector icons on the card vanished)),
  and a radial shine follows the pointer in the card's outline (carousel.shine.*): on any card the pointer
  is over, not only the front one (each card maps the pointer into itself), wide and faint, a sheen
  rather than a spot ("less shiny neon like": opacity 0.12, radius 1.6, a middle stop at 0.3 at
  half-way, fading in / out over shine.fade; 2026-11-24). Left / Right,
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
- Screenshots picker (a dropdown under the notch since 2026-11-23; 2026-11-17, "the same way wallpaper does"): ScreenshotsMode = PictureCarousel over
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
  blur 14, spread 1: "just a little bit so it's distinguishable"). Since 2026-11-24 the default is "glow"
  again, at the user's request, softer (opacity 0.45, side 0.35, brightness 0.15, spread 12). Tried: "glow" (each card's own
  picture blurred and brightened under it; "way too strong", kept as a choice) and a spotlight behind
  the front card (too weak, removed).
  Each opening lands on the newest (followNewest, until you move), also when the list read on opening
  brings a new one. A panel reacting to a new list does it from the carousel's own onPicturesChanged:
  the mode's handler ran before the carousel had the list, and its selection named the old picture
  (both panels, fixed 2026-11-17).

### Notifications
- macOS look (2026-11-23, "more like Apple's, come from the right and be dismissed right too"): banners at
  the top right under the bar (notifications.margin), sliding in from the right edge and out to it.
  Swipes (2026-11-24, the user's rule): right (drag, or scroll sideways) DELETES it, out of the history
  too; up (a banner only: drag, or scroll up) only takes it off the screen, kept in the history. The drag
  locks to the way it starts (notifications.swipe.lock). A timed-out banner slides right but is kept.
  Two fingers on a touchpad (2026-11-24, "the same way, in history and pop-up") move the card like a
  drag: pixel deltas follow the content's direction, ScrollEnd (or notifications.swipe.scrollEnd ms of
  quiet) decides like a drag release; momentum events are ignored. A mouse wheel's notch (angle delta
  only) sends it at once (swipe.wheel). Two WheelHandlers: Horizontal always, Vertical only on banners
  (in the center up / down scrolls the list); the old single handler was Horizontal, so up never fired.
  AND a WheelHandler takes only mice by default: without `acceptedDevices: PointerDevice.Mouse |
  PointerDevice.TouchPad` the user's touchpad (device type 4) never reached it ("I'm swiping and it doesn't
  do anything", found with a log while they swiped). Every WheelHandler sets it; a touchpad sends many
  small steps, so anything stepping (the calendar's months) adds up angleDelta and steps per 120.
  Throws (2026-11-24, "it doesn't feel like you threw it but it stayed"): a drag or two-finger swipe is
  judged where it would land, not where it was let go: NotificationCard.track() keeps a running speed
  (each move weighs exp(-dt / (swipe.velocityWindow / 3)), so a pull back at the end shows in a few
  events), release() goes when position + speed * swipe.projection passes swipe.distance, unless it's
  moving back faster than swipe.backSpeed; a pointer resting longer than the window before letting go
  throws nothing. A touchpad ends on ScrollEnd (holding still waits for it); the quiet timer
  (swipe.scrollEnd) is only for scrolling without phases. Tested with timed fake events: a 32 px flick
  at ~450 px/s deletes, a slow 20 px push and a throw pulled back stay, fast-then-held stays.
  Smoothness (2026-11-24, "jittery", "doesn't keep the velocity", measured per frame in a test copy): the
  input sets a target (_toX / _toY) and a FrameAnimation chases it (swipe.follow, 25 ms): moved on each
  touchpad event it stepped (events don't fall on frames): now ~5.5 px every frame. The exit starts at
  the throw's speed: a cubic Bezier (0,0) (1/3, m/3) (2/3, 1) (1,1), duration 3 * distance / speed held
  in [swipe.minLeave, leaveDuration], m = speed * duration / distance (unthrown m = 3 = OutCubic); a
  fixed OutCubic took a 360 px/s throw to 3600 px/s at once, now 360 -> 386 -> rising; a 1250 px/s
  flick leaves at 1250. An open card stays open while swiped (_keepOpen): sliding out from under a still
  pointer collapsed it mid-swipe.
  The stack routes two-finger swipes (2026-11-24, found with a log of the user's real swipes: cards froze
  mid-swipe, half transparent, and a hard swipe slid off screen but was never deleted): two fingers
  don't move the pointer, so a card sliding away left it behind, and the rest of the swipe, its end
  (ScrollEnd, no movement) included, went to whatever was under it; a Horizontal WheelHandler never gets
  the end either. Now NotificationStack's two WheelHandlers pick the card under the pointer when a swipe
  starts (cardAt) and send it every event (NotificationCard.scrollEvent) until it's done; the card has
  none of its own. In the history the list (a Flickable) takes scroll events before the stack, so it
  has its own pair inside it (on its contentItem, ahead of it): sideways always, vertical only while a
  card is being swiped (else up / down is the list's). Checked with a log of the user's swipes. A swipe whose end never comes is judged after swipe.lostEnd ms (no throw). Made-up
  events never showed this: test input paths with the user's real events (a log) when it's input.
  Hover opens a card only on real pointer moves (Inbox.pointerMoves, bumped by the stack's MovedHover):
  cards gliding up under a still pointer after a dismissal opened and closed as they passed ("they
  jitter a bit when going up"); the glide itself measured smooth per frame. The card: app icon at the left (a soft glyph
  tile without one; urgent = a red tile and a red title, not a red card), bold title with a relative age
  at the right ("now", "5m ago", notifications.age.*), grey message, picture at the right, hairline edge
  (notifications.edge*) + shadow. The center's header: two chips in the cards' color ("Notifications",
  Clear all), not the black pill ("it feels weird just being full black"); the dark theme's surfaces
  were lightened (#262628 / #2c2c2e) and the dropdowns got a hairline edge (panel.edge*).
- The center lives under the clock (2026-11-23): Activity.center = the calendar dropdown being open;
  NotificationStack hangs the center under the calendar's card (`under`, its width, right-aligned), the
  banners still drop in under the notch. A dot after the clock while some are new (bar.clock.unseenDot).
  IPC "notifications" (and "time") open the calendar; "screenshots" opens the shelf.
- A card's height follows its content through an eased `shownHeight` (notifications.hoverDuration), so
  hover opening (the whole message, the buttons) grows and shrinks smoothly; its text is clipped to the
  card meanwhile.
- The history's NEW / OLD chips (2026-11-24, "everything animated"): not ListView sections (they can't
  animate: the chip vanished, everything jumped). Each center row is an Item drawing a chip above its card
  when it's the first of its section (`headed`, from the neighbours' section, guarded for the stale
  index of a row being removed). A headed card leaving with others in its section keeps the chip still
  while it folds under it; once removed, the next row is headed at the very same spot (removeDisplaced
  is empty: nothing moves on a removal, the fold already did it). The section's last card folds the chip
  with it (chipShown = card.fold). Clear all cascades: the cards on screen sweep() out right
  notifications.center.clearStagger apart, the chips fade (clearFade, always animated), then Inbox.clearAll.
- Leaving cards play their own exit (2026-11-23: "the history doesn't animate well when something is
  deleted, it just snaps up"; the ListView's remove / removeDisplaced transitions never ran): a banner
  whose time is up gets `leaving` in Inbox.banners, a swipe or the × call NotificationCard.away: it slides
  out right from where it is (mid-swipe included), then `fold`s its height to minus the list's gap so the
  cards below glide up, then Inbox._dropBanner (off the screen) or Inbox.dismiss (gone). Every row of
  both models has the `leaving` role (the card requires it).
- Hovering the cards pauses their time (Inbox.hovered, from the stack's HoverHandler). The stack item
  must be as tall as the cards (height = banners.contentHeight): a HoverHandler only feels the pointer
  inside its own item, and the stack had no height, so nothing ever paused and cards vanished under the
  pointer (2026-11-24).
- Banner timing (Inbox._elapse): the time since the last tick is charged to the cards already there
  BEFORE a new one is added. Charged to the new card too, it was hours after a quiet spell, so every
  notification expired the moment it came and went straight to the center (2026-11-23; tests never saw it:
  a test shell is always freshly started; to test, set Inbox._tickedAt an hour back).
- The shell is the notification server (Sys.NotificationServer -> notified -> Inbox). Each notification
  becomes a plain row in Inbox.model (newest first) and, unless Focus is on (critical ones still drop in,
  dndAllowsCritical) or it's low urgency (showLowUrgency), a banner: it drops in from above the screen's
  edge (ListView add transition from `above`) and settles under the notch; the others spring down
  (displaced); after its time it slides back up (Inbox keeps it). notifications.maxVisible at once.
  Hovering the cards pauses every banner's time (Inbox.hovered); leaving gives each at least
  island.leaveDelay. Drag / scroll a card up: a banner leaves the screen, a center card is dismissed.
- The center (Activity.center; a click on the clock or `toggle calendar`): the banners go,
  a black pill ("Notifications", Clear all, the count, a dot while new), then NEW (time > lastSeen) and
  OLD chips over the cards; it scrolls. Closing it marks everything seen (lastSeen = now). Escape closes it.
- Saved across reboots (the user asked): notifications.json, plain values; a picture that came as data
  (not a file) is dropped when saved. Live notification objects are kept by uid while the app has them
  (actions, the window that sent it); after a restart, a click brings up the app by its name / entry.
  An app closing its notification (CloseRequested) removes it; one updating it updates the card.
- Screenshots (niri's "Screenshot captured", screenshot.summaries): Sys.findScreenshot finds the file;
  the latest screenshot card still in the history gets it on top of its pile (the card comes back on top,
  banner again), else a new card. The user: "bring up the latest unclosed screenshot notification and add
  the current image to it in a pile". Clicking it opens the screenshots picker. niri's own notification is
  closed at once (the card holds the file).
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

### Shape (the notch, the dropdowns, the cards)
- Screen corners: niri only rounds windows (`geometry-corner-radius`), so the shell paints the screen's corners
  (`ScreenCorners.qml`, Overlay layer, empty input mask, reserves no space), smoothed like the notch's
  (screenCorners.smoothing; the corner maths, Config.cornerParams / cornerSvg, is shared with Island).
- Drawn as an SVG path (`Island.shapePath`) in a `Shape` with the CurveRenderer: Figma-style corner smoothing
  (`island.cornerSmoothing`); smoothing gives way when space is short, so the resting pill keeps half circles.
  Smoothing 0 (and not attached) = a plain `Rectangle` instead (`Island.plain`): measured 14.8 % vs 18.6 % of
  a core while the island springs nonstop, same at rest. For older laptops.
- Corners: one size per role, `corners.*` (2026-11-23: the four corner styles island.shape / shapes were
  removed, "this makes the code clearer"). The open notch: 32 (18 was tried: "nahhh more border
  radius"); dropdowns and cards: 18. Before that, 4 hand-tuned styles (square / soft / round / full)
  each gave
  a corner per role: `island`, `attached`, `flare`, `pill` (buttons, slider, search field, the center's
  pill, bar highlights; 100 = always a pill), `row` (list/search highlights), `menu` (the dropdowns'
  card and the notification cards, 2026-11-23), `tile` (launcher tiles, pictures), `small` (keycaps, and
  the floor below). Code reads `Config.corner(role, size)` = the style's value,
  at most half the size. Never add a per-widget radius setting: pick a role. Intent: square = small but never
  0; soft = a bit more, the resting island's ends slightly squared; round = resting island a pill, panels
  not fully round; full = pills everywhere.
  Things hugging the island's edge are concentric with it instead: `Config.inner(outer, inset, size)` =
  outer corner minus the gap, never below `small`, at most half the size: activity badges (Badge:
  `restCorner`, `activity.inset` by default; `outerCorner` / `inset` override it, e.g. the Wi-Fi password
  field's × badge), a card's picture. Circles by meaning stay circles (today in the calendar, battery
  ticks, the switch's knob); screen corners (screenCorners.radius) are the display's. Rejected before: a
  0-1 roundness slider (scaling every corner; in-between values couldn't all be checked).
- `island.style` (2026-11-23, default "notch"): flat top glued to the screen edge, concave flares (the
  style's `flare` corner) joining it to the edge, bottom corners the style's `attached` corner; "pill" floats
  island.gap below the edge with `island` corners all round. The flares are drawn outside the island's
  bounds (not clickable). (It replaced island.attachToTop.)
- Content is clipped to the island's rectangle (`host`), not to the curved path.
- The shape is drawn with each edge on the nearest device pixel (`Island.drawnX/Y/Width/Height`): at 1.25
  the 3 px gap and 38 px island put both edges mid-pixel, a faint row above and below that small corners
  (Square style) made obvious. Each edge snaps on its own (not position + size), so the content stays centred.
  Layout and transitions keep the exact size. Corner smoothing and blur weren't the cause (tested).
- No blur (2026-11-23: island.blur was removed, "against the design"). niri-settings may still write
  island.blur / blurOpacity / attachToTop into config.jsonc: check-config.py lists them as RETIRED (a
  note, not a failure) and --rewrite drops them.

## Behaviour

### Transitions (IslandMode: the notch and the dropdown card)
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
  the list collapsed). On `active` going false a mode freezes its data (WifiMode.networks,
  BluetoothMode.devices, MediaMode.media + position: `x = x` breaks the binding, `Qt.binding` restores it on
  open) and keeps its look; resets, menus closing, animations stopping wait for `onScreen` (IslandMode:
  active or still fading) to go false. Moving things (music bars, the low battery pulse, ripples) keep
  moving until then. New modes follow the same rule.
- Motion was made a touch smoother on 2026-11-23 ("make all animation a bit smoother"): island.expand
  0.55 s / 0.84, shrink 0.42 / 0.88 (niri's window-open / close mirrored: stiffness 131 / 224), list
  highlight 0.42 / 0.84, fades +20-40 ms (fadeIn 300, fadeOut 280, colorFade 300, hoverFade 160).
- Closing must react on the first frame (Apple-style): fast-start curves (OutCubic, springs from rest) for
  anything leaving, never an ease-in, and `shrinkDelay` stays 0 by default. A hold or an ease-in at the start
  reads as lag.
- Closing (2026-11-19): a scripted closing bounce was built and tuned at length (a quick dip under the
  idle width, a spring out past it, the idle content fading in and scaling with it; island.exit.*), then
  removed: compared side by side, the plain spring won (Apple's island settles more than it bounces,
  closing happens on every pop-up so a flourish gets old, and it was ~250 ms slower). island.shrink stays at 0.85 (QML's SpringAnimation doesn't overshoot there): a landing overshoot was
  tried at 0.7 (3 px under in width and height) and the user found the scale-down too noticeable;
  0.75 was ~1 px, 0.65 dipped the height 7.5 px.
- Island: grow and shrink use different springs per axis; the `shrinkDelay` hold applies only within 150 ms
  of a mode switch, not to a mode resizing itself. A mode whose size follows its content (search) grows at once
  and shrinks after a short debounce (`search.shrinkDebounce`) so the island doesn't pump while typing.

### Conventions
- A key that closes a mode or hands focus back (Escape, Enter in search) must call `mode.holdKeyboard()` right
  before `requestState`/acting (`mode.close()` does both). shell.qml then keeps keyboard focus (on `keyCatcher`)
  until that key is released: niri passes keys still held at a focus change to the next window (Escape made
  fullscreen videos exit fullscreen). Only hold it when the mode really closes/switches.
- Keyboard focus of the window (shell.qml `keyboardFocus`): opened from the keyboard (launcher, IPC) =
  Exclusive; opened with the mouse = Exclusive too when `island.clickTakesKeyboard`, else OnDemand; nothing
  open = None. Notch activities and cards never take it. "From the keyboard" = `keyHeld` at the moment of
  `requestState`, or an IPC toggle.
- One thing open at a time (Activity.open): a dropdown, the center or the media controls.
- Handlers that react to a change must read the changed value itself, not a binding derived from it (it
  may not have updated yet): Dropdown.onNameChanged read `shown` and faded the card the wrong way
  (2026-11-23).
- niri's window open/close animations mirror the notch springs (`~/.config/niri/config.kdl`, `animations`
  block): window-open = `island.expand`, window-close = `island.shrink`, with stiffness = (2π / response)²,
  damping-ratio = dampingFraction. When either spring changes, update niri too (and run `niri validate`).
  The camera/travel animations stay on niri's defaults (the user tried island-style springs there).
- Battery color priority: charging (green) > power saver (yellow) > low battery (red) > performance (red) >
  balanced (white). Computed once in `Sys.battery.color` (the alerts and the bar's battery, unless bar.battery.colored is off).
- Each file starts with a short comment saying what it is. Keep it accurate when you change the file.

### System settings (2026-11-16)
- The planned desktop settings app writes the system's settings (gsettings, logind...), never the island's
  config for shared values: the island follows the system. Today: the accent (gsettings accent-color, a
  name, mapped to a color by colors.systemAccents; Config.colors.accent returns it while
  colors.followSystemAccent) and the 12 / 24-hour clock (clock-format -> Sys.hour24, used by every clock;
  time.followSystemClock; the bar's clock has bar.clock.timeFormat and timeFormat12h), and light / dark
  (color-scheme -> Config.systemScheme -> Config.dark / Config.theme, unless colors.scheme forces one). One `gsettings
  monitor` stream + a read at start, nothing polls. Focus (do not disturb) is GNOME's
  org.gnome.desktop.notifications show-banners (false = Focus on): Sys.systemFocus / setSystemFocus. Fedora's default clock-format is 12h (locale default,
  not user-set): set to 24h on 2026-11-16 to keep the user's island. Test with an isolated dconf db
  (DCONF_PROFILE=<file containing `user-db:test`> for both qs and gsettings; delete ~/.config/dconf/test
  afterwards), never the user's.

### Sounds (2026-11-15)
- Only for what's worth hearing when you're not looking: notifications and alerts (Activity.sound, called
  by show() for a new notch activity, not an update in place, and by Inbox for a card that drops in). Never clicks, panels, toggles or the music controls
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
  power button). Activity then clears the queue and closes whatever is open and refuses any other activity; GoodbyeMode
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
v0.2.0 (2026-11-24) is the bar + notch redesign (on main since that day); v0.1.0 is the island-only
version, and the `v0.1-island` tag its last state. Release notes follow v0.1.0's shape: what's in it,
niri-settings, what you need, install (gh release create, the tag on main).
Published as https://github.com/NiteChill/niri-island (public, GPL-3.0-or-later, release v0.1.0), with
the Settings app as https://github.com/NiteChill/niri-settings. README.md is for users: what it does,
how it works with niri-settings, what it needs (Fedora / Arch packages), install (clone into
~/.config/quickshell, niri spawn + binds). Keep it true when a dependency, a panel or an IPC call
changes. THIRD-PARTY.md credits Material Symbols. Commits use GitHub's noreply address.
docs/hero.png, panels.png and shelf.png (the README's pictures) are made here since 2026-11-24:
`python3 tools/readme-images.py` (a scratch copy staged with made-up data: 9:41 on Tue 9 June, "Home" /
"Buds", a made-up song from the start (a real one leaked into a first run when the demo song was toggled
per scene), made-up notifications and shelf photos, no tray, "Files"; each scene set up only after the
previous grab is saved; composed over a generated wallpaper). Look at every picture for anything
private before it's committed. Remake them when the look changes. (The Settings app's own
tools/capture-island.py still stages the island-only version for its showcase: not ours.)

## Reviews (the user's way, 2026-11-17)
When asked to review something (a mode, a change, the day's work): first give it a grade out of 10 with
the reasons in a few lines (what works, what holds it back), then rewrite / fix what holds it back to raise
the grade, and end with the new grade and what changed. Not a list of suggestions left for later: do the
work that augments the grade (checks, tests, CLAUDE.md, notify as usual).

## QML gotchas (each one caused a real bug here)
- `visible` reads the *effective* visibility: every child of a hidden item reads false. Never lay out from a
  child's `visible` when the parent can be hidden (MediaMode's title block, once hidden, centred the
  title as if there were no artist).
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
- Item already has `top` / `bottom` / `left` / `right` (anchor lines, FINAL) and `data`: don't name
  properties after them (a test's `property int left` failed to load: "Cannot override FINAL property").
- A `point` (or other value type) read from a property can stay tied to it: `const v = _speed; _speed =
  Qt.point(0, 0)` and v.x read 0 (every throw was judged motionless). Copy the numbers out first.
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
