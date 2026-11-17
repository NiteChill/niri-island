# niri-island

A Dynamic Island-style top bar for the [niri](https://github.com/YaLTeR/niri) Wayland compositor, built
with [Quickshell](https://quickshell.org). One island at the top of the screen that springs between
shapes: at rest it shows the time and your status icons; it opens into panels you ask for, and it
shows what happens on the computer as it happens.

It is a community project, not part of niri.

## What it does

**Panels** (click the island, a shortcut, or its launcher):

- **Search**: a launcher for apps, files, calculations, web searches, the island's panels and the
  desktop's settings (with [niri-settings](https://github.com/NiteChill/niri-settings)), with pinned
  favourites.
- **Quick settings**: Wi-Fi, Bluetooth, Focus (do not disturb), microphone, power mode, brightness and
  volume.
- **Wi-Fi** and **Bluetooth**: nearby networks and devices, connect, pair.
- **Battery**, **Time** (with the day and the week), **Now playing** (cover, controls, a fullscreen view).
- **Wallpaper** and **Screenshots**: a carousel of pictures. Pick a wallpaper; copy a screenshot with
  Enter (Shift+Enter shows it in Files) or drag it out of the island into an app.

**Pop-ups** (the island shows them, in order of importance):

- Volume, brightness and microphone feedback for your keys (it replaces an OSD like swayosd).
- **Notifications**: the island is your notification server (it replaces mako, dunst or swaync).
  Clicking one brings up the window that sent it, or the Settings page for system messages.
- Screenshots as you take them, low battery, charging, headphones, Wi-Fi connected, music starting.
- A handwritten goodbye when you power off or restart.

Everything you can see is a setting: sizes, colours, corners, springs, timings, icons, texts.
`config/schema.json` describes every one of them; your choices go in `config/config.jsonc`.

## Works with niri-settings

[niri-settings](https://github.com/NiteChill/niri-settings) is a settings app for niri, the system
and this island, made to go with it. Each works without the other; together:

- The Settings app has a **Dynamic Island** page (the island's look, which alerts show, search) and
  island options spread where you'd look for them (notifications, sound, appearance).
- They share the system's settings: the accent colour, the 12 / 24-hour clock, Focus and the wallpaper
  are the desktop's, so changing one in either place changes both.
- The island's search finds the Settings app's settings ("night light" opens that page).
- Clicking a system notification (network, Bluetooth, printers...) opens the matching Settings page.

Without the island, niri-settings simply hides the island's options; without the Settings app, the
island's settings are in `config/config.jsonc`.

## What you need

Required:

| What | Fedora | Arch |
|---|---|---|
| niri (tested with 26.04) | `niri` | `niri` |
| Quickshell 0.3 or newer, built with Qt 6.9 or newer | [COPR `errornointernet/quickshell`](https://copr.fedorainfracloud.org/coprs/errornointernet/quickshell/) | `quickshell` (AUR) |
| PipeWire with its PulseAudio server (`pactl`, `pw-play`) | `pipewire-utils`, `pipewire-pulseaudio`, `pulseaudio-utils` | `pipewire`, `pipewire-pulse`, `libpulse` |
| GLib tools (`gsettings`, `gdbus`) and the desktop's setting schemas | `glib2`, `gsettings-desktop-schemas` | `glib2`, `gsettings-desktop-schemas` |
| UPower, NetworkManager, BlueZ (battery, Wi-Fi, Bluetooth) | `upower`, `NetworkManager`, `bluez` | `upower`, `networkmanager`, `bluez` |
| Python 3 | `python3` | `python` |
| `wl-copy`, `file`, `find` | `wl-clipboard`, `file`, `findutils` | `wl-clipboard`, `file`, `findutils` |

Optional:

- **Google Sans Flex**, the island's font ([Google Fonts](https://fonts.google.com/specimen/Google+Sans+Flex),
  into `~/.local/share/fonts`). Without it, the system's sans-serif font is used.
- `brightnessctl`: brightness keys and the brightness slider (laptops).
- `cava`: the music bars follow the real sound (otherwise they dance on their own).
- `python3-gobject` (Fedora) / `python-gobject` (Arch): drag screenshots into sandboxed apps (Flatpaks).
- A file manager that supports "show in folder" (Files, Dolphin...), and `xdg-utils`.
- [niri-settings](https://github.com/NiteChill/niri-settings).

Turn off any other notification daemon (mako, dunst, swaync) and OSD (swayosd): the island takes their
place.

## Install

1. Put the island where Quickshell looks for its default config (move an existing
   `~/.config/quickshell` aside first):

   ```sh
   git clone https://github.com/NiteChill/niri-island ~/.config/quickshell
   ```

2. Start it with niri, and give it your keys, in `~/.config/niri/config.kdl`:

   ```kdl
   spawn-at-startup "qs"

   binds {
       Mod+Space { spawn "qs" "ipc" "call" "island" "toggle" "search"; }
       Mod+S     { spawn "qs" "ipc" "call" "island" "toggle" "quickSettings"; }
       XF86AudioRaiseVolume allow-when-locked=true { spawn "qs" "ipc" "call" "osd" "volume" "up"; }
       XF86AudioLowerVolume allow-when-locked=true { spawn "qs" "ipc" "call" "osd" "volume" "down"; }
       XF86AudioMute        allow-when-locked=true { spawn "qs" "ipc" "call" "osd" "volume" "mute"; }
       XF86AudioMicMute     allow-when-locked=true { spawn "qs" "ipc" "call" "osd" "mic" "mute"; }
       XF86MonBrightnessUp   allow-when-locked=true { spawn "qs" "ipc" "call" "osd" "brightness" "up"; }
       XF86MonBrightnessDown allow-when-locked=true { spawn "qs" "ipc" "call" "osd" "brightness" "down"; }
   }
   ```

   (Put the binds inside your existing `binds { }` block.) Any panel opens with
   `qs ipc call island toggle <name>`: `search`, `quickSettings`, `wifi`, `bluetooth`, `battery`, `time`,
   `media`, `wallpaper`, `screenshots`. niri-settings' Keyboard > Shortcuts page can set all of these
   for you.

3. Log out and back in, or start it now with `qs &`.

Optional: for the island's background blur, turn on niri's blur (niri 26.04) and the island's
`island.blur` setting.

**Update:** `git -C ~/.config/quickshell pull` (the island reloads by itself).
**Uninstall:** remove `~/.config/quickshell` and the lines above.

## Settings

`config/config.jsonc` lists every setting, commented out at its default: uncomment a line to change it.
The island reloads as soon as you save. `config/schema.json` explains each one (what it changes, its
range). After editing, `python3 tools/check-config.py` checks the file.

## Licence

GNU General Public License v3.0 or later: see `LICENSE`. The icons are Material Symbols (Apache-2.0):
see `THIRD-PARTY.md`.
