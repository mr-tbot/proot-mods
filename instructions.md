# Proot Ubuntu Desktop Environment — Full Setup Guide

> **Goal**: Install Ubuntu (22.04 or latest) via Termux `proot-distro`, set up a full XFCE desktop with VSCode, Chromium, Chrome, development tools, media editors, network utilities, Wine, and more — all working correctly inside proot — accessible via **TigerVNC** (recommended) or **Termux:X11**.

---

## Table of Contents

1. [Prerequisites](#1-prerequisites)
2. [Install Termux & Companion Apps](#2-install-termux--companion-apps)
3. [Termux-Side Setup (setup-termux.sh)](#3-termux-side-setup)
4. [Proot-Side Setup (setup-proot.sh)](#4-proot-side-setup)
5. [Google Drive Sync (gdrive-mount.sh)](#5-google-drive-sync)
6. [Display Access Options](#6-display-access-options)
7. [XFCE Desktop Customization](#7-xfce-desktop-customization)
8. [Daily Usage](#8-daily-usage)
9. [Sound & USB](#9-sound--usb)
10. [Backup & Restore](#10-backup--restore)
11. [Troubleshooting](#11-troubleshooting)
12. [What Works / What Doesn't in Proot](#12-what-works--what-doesnt-in-proot)

---

## 1. Prerequisites

| Requirement | Details |
|---|---|
| **Android device** | ARM64 (aarch64) — most modern phones/tablets |
| **Free storage** | ~6-10 GB minimum (more for all apps) |
| **Termux** | From **F-Droid** or GitHub releases (NOT Play Store) |
| **VNC viewer** | RealVNC Viewer (recommended) or AVNC |
| *OR* **Termux:X11** | Alternative display method (from F-Droid/GitHub) |

---

## 2. Install Termux & Companion Apps

### Termux (Required)

> **Do NOT use the Play Store version** — it is outdated and will not work.

Install from one of:
- **F-Droid**: https://f-droid.org/en/packages/com.termux/
- **GitHub Releases**: https://github.com/termux/termux-app/releases

After first launch:
```bash
termux-setup-storage    # Grant storage permission
pkg update && pkg upgrade -y
```

### Termux:API (Recommended)

Enables wake-lock to prevent Android from killing the session:
```bash
pkg install termux-api
```
Also install the **Termux:API** companion app from F-Droid.

### VNC Viewer (Pick One)

| App | Notes |
|---|---|
| **RealVNC Viewer** | Play Store — polished, reliable, author's preference |
| **AVNC** | F-Droid — open source, supports `vnc://` URIs |

### OR: Termux:X11 (Alternative to VNC)

- **GitHub**: https://github.com/niceforbear/niceforbear.apk/blob/main/niceforbear-termux-x11-arm64-v8a-debug-1.02.apk
- Better performance than VNC but requires the companion Termux package (installed by the script)

---

## 3. Termux-Side Setup

> **Script:** `setup-termux.sh` — Run in Termux (NOT inside proot).

### What It Does

The script is fully idempotent (safe to re-run). It performs these steps:

| Section | Description |
|---|---|
| **1. Update Termux** | `pkg update && pkg upgrade` |
| **2. Install packages** | `proot-distro`, `pulseaudio`, `tigervnc`, `termux-x11-nightly`, `termux-api` — skips if already present |
| **2b. Storage** | Runs `termux-setup-storage` to grant Android storage permission |
| **3. Install Ubuntu** | Offers Ubuntu version choice (22.04 LTS or latest). If Ubuntu is already installed, prompts to **re-use** or **wipe and reinstall** |
| **4. Copy scripts** | Copies `setup-proot.sh`, `gdrive-mount.sh`, and `proot-backup.sh` into the proot rootfs |
| **5. Resolution presets** | Interactive resolution chooser — add as many device presets as you like (phone, tablet, fold, desktop) |
| **6. VNC launcher** | Creates `~/start-ubuntu-vnc.sh` with PulseAudio, thorough cleanup, exit trap, battery warning |
| **7. X11 launcher** | Creates `~/start-ubuntu-x11.sh` for Termux:X11 |
| **8. Stop script** | Creates `~/stop-ubuntu.sh` — kills VNC/X11/PulseAudio, releases wake-lock |
| **9. Shell login** | Creates `~/login-ubuntu.sh` — shell-only (no desktop) |

### Re-run Detection

- Checks if core Termux packages are already installed and skips `pkg install` if so
- Detects if Ubuntu is already installed via `proot-distro list --installed`
- Offers interactive choice: "Use existing" (default) or "Remove and reinstall"

### Running

```bash
# Download or place setup-termux.sh in Termux home:
bash ~/setup-termux.sh
```

### Created Launcher Scripts

After running, you'll have these in `~/` (Termux home):

| Script | Purpose |
|---|---|
| `~/start-ubuntu-vnc.sh` | Start VNC desktop — choose resolution, starts PulseAudio + proot + VNC on :1 |
| `~/start-ubuntu-x11.sh` | Start via Termux:X11 — same setup but uses X11 display |
| `~/stop-ubuntu.sh` | Kill all sessions (VNC + X11 + PulseAudio), release wake-lock |
| `~/login-ubuntu.sh` | Shell-only login — no desktop, just bash in proot |

### VNC Launcher Features

- **Resolution picker**: Shows saved presets on each launch, option to add new ones
- **Battery warning**: Reminds to disable battery optimization for Termux
- **Lock cleanup**: Removes stale VNC/X lock files before starting
- **Exit trap**: Automatically cleans up VNC server when you `Ctrl+C`
- **PulseAudio**: Starts TCP server for audio passthrough to Android

---

## 4. Proot-Side Setup

> **Script:** `setup-proot.sh` — Run inside the Ubuntu proot environment.

### What It Does

The script is fully idempotent (safe to re-run). Uses `_is_installed()` / `_all_installed()` helpers to skip already-installed packages.

#### Section 0: System Setup
- Fixes apt sources.list (no-change-plans, ftp → http)
- Conditional `apt update && apt upgrade` (skips if recently done)
- Creates `/dev/shm` (needed for Chromium shared memory)
- Creates `~/.Xauthority` (needed for X11 session)

#### Section 1: XFCE Desktop + VNC
- Installs: `xfce4`, `xfce4-goodies`, `dbus-x11`, `tigervnc-standalone-server`, fonts, locale
- Configures VNC xstartup with dbus and `startxfce4`

#### Section 2: Icon Themes
- Installs `elementary-xfce-icon-theme` and `humanity-icon-theme`
- Skips if already present

#### Section 3: Chromium Browser
**Newest-first strategy** from Debian repositories:
1. Imports Debian GPG keys + adds repo
2. Tries **Bookworm** (Debian 12) first — newest Chromium (~v120+)
3. Falls back to **Bullseye** (Debian 11) — if Bookworm fails
4. Falls back to **Buster** (Debian 10) — proven stable (v89)
5. User can also choose: `[1] Try newest first` or `[2] Use Buster directly (stable)`

**Chromium launch chain** (matches Andronix architecture):
```
chromium-default (debug wrapper with env logging)
  → /usr/bin/chromium (main wrapper — adds --no-sandbox, --no-zygote, etc.)
    → chromium.real (stock Debian launcher)
      → chromium.d/ config files (default-flags, apikeys, extensions)
        → /usr/lib/chromium/chromium (ELF binary)
```

**Key flags**: `--no-sandbox`, `--no-zygote`, `--in-process-gpu`, `--disable-gpu`, `--disable-software-rasterizer`, `--disable-dev-shm-usage`, `--no-first-run`

Sets Chromium as default browser via `xdg-settings`, `update-alternatives`, and `mimeapps.list`.

#### Section 3b: Google Chrome
- Installs `google-chrome-stable` from Google's apt repo
- Creates `--no-sandbox` wrapper similar to Chromium

#### Section 4: Visual Studio Code
- Installs from Microsoft apt repo
- Creates wrapper with `--no-sandbox --password-store=basic --disable-gpu`
- Patches `argv.json` for basic password store
- Creates/fixes `.desktop` shortcut

#### Section 5: Productivity & Media Apps

| App | Package / Method |
|---|---|
| **Blender** | `apt install blender` |
| **GIMP** | `apt install gimp` |
| **LibreOffice** | `apt install libreoffice` |
| **GParted** | `apt install gparted` |
| **Kdenlive** | `apt install kdenlive` |
| **Shotcut** | `apt install shotcut` |
| **Thunderbird** | `apt install thunderbird` |
| **Spotify** | Official client (amd64) or spotifyd + spotify-tui (arm64) |
| **App Store** | GNOME Software (or GNOME PackageKit fallback) |
| **Python 3** | `apt install python3 python3-pip python3-venv` |
| **Build tools** | `build-essential`, `pkg-config`, etc. |

Each app is skip-checked — won't reinstall if already present.

#### Section 5b: Developer Tools

| Tool | Method |
|---|---|
| **Android SDK** | Full SDK: cmdline-tools from Google + sdkmanager |
| **ADB / fastboot** | `android-tools-adb android-tools-fastboot` packages |
| **Node.js + npm** | NodeSource LTS repository |
| **Arduino CLI** | Official GitHub release binary |
| **cmake** | `apt install cmake` |
| **gdb** | `apt install gdb` |
| **clang** | `apt install clang` |
| **make** | `apt install make` |
| **tmux** | `apt install tmux` |
| **jq** | `apt install jq` |
| **sqlite3** | `apt install sqlite3` |
| **Java (JDK)** | `default-jdk` |
| **Ruby** | `apt install ruby-full` |

#### Section 5d: Spotify

Tiered install — tries official repo first (amd64), then spotify-launcher via Cargo, then spotifyd + spotify-tui for arm64.

#### Section 5e: App Store, VPN, SDK, Arduino IDE, System Widgets

| Tool | Method |
|---|---|
| **App Store** | `gnome-software` (primary) or `gnome-packagekit` (fallback) — graphical package manager |
| **WireGuard** | `wireguard-tools` — VPN client (`wg`, `wg-quick`) |
| **Android SDK (Full)** | cmdline-tools from dl.google.com, sdkmanager installs platform-tools, build-tools;34.0.0, platforms;android-34. Installed to `/opt/android-sdk` |
| **Arduino IDE** | `arduino` apt package, or Arduino IDE 2.x from GitHub releases (AppImage/zip) |
| **Conky** | `conky-all` — desktop system monitor with custom config (CPU, RAM, Storage, Network, Top Processes) + autostart |

#### Section 5c: Network & Windows Tools

| Tool | Method |
|---|---|
| **nmap** | `apt install nmap` |
| **traceroute** | `apt install traceroute` |
| **whois** | `apt install whois` |
| **dnsutils** (dig) | `apt install dnsutils` |
| **Angry IP Scanner** | Latest `.deb` from GitHub releases |
| **Wine** | `apt install wine` (+ box64 on arm64 for x86 translation) |
| **Notepad++** | Silent install via Wine + .desktop shortcut |

#### Section 6: Environment Tweaks
- `/etc/environment`: `LIBGL_ALWAYS_SOFTWARE=1`, `ELECTRON_DISABLE_SANDBOX=1`, `NO_AT_BRIDGE=1`, etc.
- `~/.bashrc`: Same exports + PulseAudio server address

#### Section 7: XFCE Customization
- **Background**: Solid black
- **Panel**: Bottom dock bar (40px) with launchers for ALL installed apps
- **Theme**: Adwaita-dark with Humanity icon theme
- **Session**: xfce4-session config for clean startup

#### Section 8: Validation
- Checks every installed component (binaries, wrappers, .desktop files, configs)
- Reports what's present and what's missing
- Prints helpful next-steps and expected harmless warnings

### Running

```bash
# Enter the proot:
proot-distro login ubuntu-oldlts   # (or your chosen alias)

# Run the setup:
bash /root/setup-proot.sh
```

The script takes 15-30 minutes depending on internet speed and device.

---

## 5. Google Drive Sync

> **Script:** `gdrive-mount.sh` — Run inside the Ubuntu proot environment.

### Why Sync Instead of Mount?

FUSE mounting (`rclone mount`) requires a kernel FUSE module, which is **not available** inside proot. Instead, this script uses rclone's **sync/copy/bisync** commands to transfer files between Google Drive and a local `~/GoogleDrive` directory.

### What It Does

| Section | Description |
|---|---|
| **1. Install rclone** | Via apt or official installer script |
| **2. Create directory** | `~/GoogleDrive` local sync folder |
| **3. Configure remote** | Interactive OAuth setup — works with VNC browser or manual token paste |
| **4. Test connection** | Lists top-level Drive folders to confirm access |
| **5. Sync scripts** | Creates 5 wrapper commands in `~/.local/bin/` |
| **6. Thunar bookmark** | Adds GoogleDrive to file manager sidebar |
| **7. Desktop shortcut** | Interactive menu: open folder, pull, push, bisync, status, config |
| **8. Auto-sync** | Optional: auto-pull from Drive on each proot login |

### OAuth Authentication

Two methods available during setup:

**Option A — Browser (if VNC desktop is running):**
rclone opens Chromium/Chrome inside the proot for Google sign-in.

**Option B — Manual token (headless):**
rclone prints a URL. Open it on any device (phone, laptop), sign in, paste the token back.

### Sync Commands

After setup, these commands are available from anywhere in the proot:

| Command | Description |
|---|---|
| `gdrive-pull` | Download Google Drive → `~/GoogleDrive` |
| `gdrive-pull Documents` | Sync only a specific subfolder |
| `gdrive-push` | Upload `~/GoogleDrive` → Google Drive (**destructive** — deletes remote files not present locally) |
| `gdrive-push Projects` | Push only a specific subfolder |
| `gdrive-copy ~/file Drive/path` | One-way copy (safe, no deletes) |
| `gdrive-bisync` | Two-way bidirectional sync |
| `gdrive-bisync --resync` | First-time bisync (resolves conflicts) |
| `gdrive-status` | Show Drive connection info, usage, top folders |

### Running

```bash
# Enter the proot:
proot-distro login ubuntu-oldlts

# Run the setup:
bash /root/gdrive-mount.sh
```

### Direct rclone Commands

You can also use rclone directly for advanced operations:

```bash
rclone ls gdrive:               # List all files
rclone lsd gdrive:              # List directories
rclone copy file.txt gdrive:    # Upload a single file
rclone config                   # Reconfigure remotes
rclone config show              # Show current config
rclone about gdrive:            # Show storage usage
```

---

## 6. Display Access Options

### Option A: TigerVNC + RealVNC Viewer (Recommended)

This is the author's preferred method. Reliable, works well over local connections.

**Start:**
```bash
# In Termux:
bash ~/start-ubuntu-vnc.sh
```

**Connect:**
1. Open **RealVNC Viewer** on Android
2. Add new connection: `localhost:5901`
3. Connect — set VNC password on first run when prompted

**Custom resolution:**
Resolution presets are configured during setup (Section 3 step 5). You'll be offered a choice each time you start. To add more presets later, edit `~/.proot-resolutions.conf`.

**Manual VNC start** (inside proot, for debugging):
```bash
vncserver :1 -geometry 1920x1080 -depth 24 -localhost no
```

### Option B: Termux:X11

Better performance than VNC but requires the companion app.

**Start:**
```bash
# In Termux:
bash ~/start-ubuntu-x11.sh
```

Then switch to the **Termux:X11** app on Android.

### Comparison

| Feature | VNC | Termux:X11 |
|---|---|---|
| Setup effort | Lower — just install RealVNC | Needs sideloaded APK |
| Performance | Good | Better (native Wayland) |
| Multi-display | Yes (multiple :display) | No |
| Copy-paste | Bidirectional | One-way (X11→Android) |
| Audio | Via PulseAudio TCP | Same |
| Recommended for | Most users | Performance-sensitive use |

---

## 7. XFCE Desktop Customization

The setup script auto-configures the desktop:

### Background
Solid black — set via `xfce4-desktop.xml` for all 4 workspaces.

### Panel (Bottom Dock)
A single bottom panel (40px height) with these items:

| Position | Plugin | Details |
|---|---|---|
| 1 | Applications | `applicationsmenu` — shows "Applications" text label |
| 2 | Settings | Launcher → `xfce4-settings-manager` |
| 3 | Terminal | `xfce4-terminal` |
| 4 | Thunar | File manager |
| 5 | Chrome | Launcher → `google-chrome-stable` |
| 6 | Thunderbird | Email client |
| 7 | VSCode | Launcher → `code` wrapper |
| 8 | Chromium | Launcher → `chromium-default` wrapper |
| 9 | LibreOffice | `libreoffice-writer` |
| 10 | GIMP | Image editor |
| 11 | Blender | 3D modeling |
| 12 | Spotify | Music streaming |
| 13 | Task List | `tasklist` — window list |
| 14 | Separator | Expandable spacer |
| 15 | Systray | `systray` |
| 16 | PulseAudio | Volume control |
| 17 | Clock | `clock` (LCD mode) |

### Theme
- **Window theme**: Adwaita-dark
- **Icon theme**: Humanity (with elementary-xfce available)
- **Clock**: LCD mode
- **App menu**: Shows "Applications" text label
- **Display power management**: Disabled (DPMS off)
- **Compositing**: Disabled (not useful in VNC/proot)

### Manual Customization
```bash
# Inside proot:
xfce4-settings-manager  # Full settings GUI
xfce4-panel --preferences  # Panel preferences
xfconf-query -c xfce4-desktop -p /backdrop/screen0/monitorscreen/workspace0/last-image -s ""  # Remove wallpaper
```

---

## 8. Daily Usage

### Starting Your Session
```bash
# In Termux:
bash ~/start-ubuntu-vnc.sh

# Open RealVNC Viewer → localhost:5901
```

### Working in the Desktop
- **VSCode**: Panel icon or `code /path/to/project` in terminal
- **Chromium**: Panel icon or `chromium-default` in terminal
- **Chrome**: Panel icon or `google-chrome-stable` in terminal
- **Terminal**: Panel icon or right-click desktop → Terminal
- **File Manager**: Thunar panel icon or `thunar` in terminal
- **Blender**: Panel icon or `blender` in terminal
- **GIMP**: Panel icon or `gimp` in terminal
- **LibreOffice**: Panel icon or `libreoffice` in terminal
- **Kdenlive**: Panel icon or `kdenlive` in terminal
- **Shotcut**: Panel icon or `shotcut` in terminal
- **Thunderbird**: Panel icon or `thunderbird` in terminal
- **Spotify**: Panel icon or `spotify` in terminal
- **Notepad++**: Desktop shortcut or `wine ~/.wine/drive_c/Program\ Files/Notepad++/notepad++.exe`
- **Angry IP Scanner**: `ipscan` or Angry IP Scanner desktop shortcut
- **App Store**: GNOME Software from panel or `gnome-software` in terminal
- **WireGuard**: `wg show` to list interfaces, `wg-quick up wg0` to connect
- **Conky**: Auto-starts on desktop — shows CPU, RAM, Storage, Network, Top Processes
- **Settings**: Panel icon or `xfce4-settings-manager` in terminal

### Google Drive Sync
```bash
gdrive-pull              # Download from Drive
gdrive-push              # Upload to Drive (destructive)
gdrive-copy ~/file dst   # Safe copy to Drive
gdrive-bisync            # Two-way sync
gdrive-status            # Connection info
```

### Development Tools
```bash
# Android SDK
adb devices              # List connected devices
sdkmanager --list        # List available SDK packages
sdkmanager --update      # Update installed packages

# Node.js
node --version && npm --version

# Arduino
arduino-cli version
arduino-cli board list
arduino                  # Launch Arduino IDE (if installed)

# WireGuard VPN
wg show                  # Show VPN interfaces
wg-quick up wg0          # Start VPN (after config)

# Build tools
cmake --version
make --version
gcc --version
clang --version
gdb --version

# Languages
java -version
ruby --version
python3 --version

# Utilities
tmux                     # Terminal multiplexer
jq --version             # JSON processor
sqlite3 --version        # SQLite database
```

### Network Tools
```bash
nmap -sP 192.168.1.0/24       # Scan local network
traceroute google.com          # Trace route
dig google.com                 # DNS lookup
whois example.com              # WHOIS lookup
```

### Shell-Only Access (No Desktop)
```bash
# In Termux:
bash ~/login-ubuntu.sh
# or:
proot-distro login ubuntu-oldlts
```

### Stopping Your Session
```bash
# In Termux:
bash ~/stop-ubuntu.sh
```

---

## 9. Sound & USB

### Sound (PulseAudio)

PulseAudio runs in Termux and streams audio to Android speakers over TCP. Both VNC and X11 methods use the same approach.

```
Termux PulseAudio → TCP socket → Proot apps → Android speakers
```

- Volume control widget is in the XFCE panel (PulseAudio Plugin)
- Run `pavucontrol` for advanced mixing
- Test: `paplay /usr/share/sounds/freedesktop/stereo/bell.oga`

> VNC does NOT carry audio — sound plays directly through the device. Since you're on the same physical device, this works perfectly.

**Troubleshooting sound:**
```bash
# In Termux (make sure it's running):
pulseaudio --start

# Inside proot (check connection):
pactl info | grep "Server Name"
paplay /usr/share/sounds/freedesktop/stereo/bell.oga
```

### USB

USB OTG devices are bind-mounted into proot automatically by the launcher scripts.

```bash
# Inside proot
lsusb              # List connected USB devices

# In Termux
termux-usb -l      # List USB devices Android sees
```

When you plug in a USB device, Android will prompt you to grant access to Termux — tap Allow.

**USB Device Compatibility:**

| Device Type | Works? | Notes |
|---|---|---|
| USB keyboard/mouse | ✔ | Android handles input directly |
| USB drive | ⚠ | Raw access via libusb; kernel-level mount needs root |
| Arduino (serial) | ✔ | Via `/dev/ttyUSB*` or `/dev/ttyACM*` |
| ADB device | ✔ | Via `adb` in proot |
| USB camera | ⚠ | Depends on Android USB API |

---

## 10. Backup & Restore

> **Script:** `proot-backup.sh` — Run in Termux (NOT inside proot).

### Setup

The script is placed at `~/proot-backup.sh` automatically by `setup-termux.sh`. Make sure storage permission is granted:
```bash
termux-setup-storage    # If not already done
chmod +x ~/proot-backup.sh
```

### Commands

```bash
bash ~/proot-backup.sh backup          # Full backup → ~/storage/shared/proot-backups/
bash ~/proot-backup.sh backup --quick  # Skip caches/tmp (smaller, faster)
bash ~/proot-backup.sh restore <file>  # Restore from archive
bash ~/proot-backup.sh list            # List available backups
bash ~/proot-backup.sh info <file>     # Show backup metadata
```

### Backup Details

- **Location**: `Internal Storage/proot-backups/` (accessible from Android file manager)
- **Format**: `.tar.gz` with `.meta.txt` sidecar containing metadata
- **Typical sizes**: 1.5–2.5 GB (quick), 2.5–4 GB (full)

### Getting Backups Off Device

| Method | Command / Steps |
|---|---|
| Android file manager | Browse to `Internal Storage/proot-backups/` |
| USB to PC | Connect USB, browse to `proot-backups/` |
| ADB pull | `adb pull /sdcard/proot-backups/ ./` |
| SCP | `scp ~/storage/shared/proot-backups/*.tar.gz user@host:~/` |
| rclone (Google Drive) | `rclone copy ~/storage/shared/proot-backups/ gdrive:proot-backups/` |
| termux-share | `termux-share ~/storage/shared/proot-backups/*.tar.gz` |

### Restoring on a Different Device

1. Install Termux on the new device
2. Run `setup-termux.sh` to install proot-distro and Ubuntu
3. Transfer the `.tar.gz` backup to `Internal Storage/proot-backups/`
4. Run `bash ~/proot-backup.sh restore <filename>`
5. Choose "wipe and replace" or "overwrite/merge" when prompted
6. Start desktop: `bash ~/start-ubuntu-vnc.sh`

### Custom Distro

```bash
PROOT_DISTRO=debian bash ~/proot-backup.sh backup
PROOT_BACKUP_DIR=~/my-backups bash ~/proot-backup.sh backup
```

---

## 11. Troubleshooting

### Common Issues

| Issue | Solution |
|---|---|
| **VSCode crashes on launch** | Run `code --verbose --no-sandbox` to see errors. Usually missing libs: `apt install libnss3 libxss1 libatk-bridge2.0-0 libgtk-3-0 libgbm1 libasound2` |
| **Keyring unlock popup** | Cancel it — `password-store=basic` is already configured |
| **Chromium won't start** | Run `chromium-default` in terminal to see errors. Check wrapper: `head -10 /usr/bin/chromium`. Must have `--no-sandbox` |
| **Chromium I/O error** | Check `/dev/shm` exists: `ls -la /dev/shm`. If missing: `mkdir -p /dev/shm && chmod 1777 /dev/shm` |
| **Black screen in VNC** | Kill & restart: stop script + start script. Or manually: `vncserver -kill :1` then re-run |
| **Icons missing in panel** | `apt install adwaita-icon-theme-full hicolor-icon-theme humanity-icon-theme && gtk-update-icon-cache /usr/share/icons/Adwaita` |
| **Panel not showing correctly** | Delete `~/.config/xfce4/panel/` and `~/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-panel.xml`, then restart session |
| **"SUID sandbox helper" error** | Normal proot noise — harmless, ignore it |
| **apt update errors** | Re-run `setup-proot.sh` or manually fix `/etc/apt/sources.list` |
| **No audio** | Start PulseAudio in Termux first: `pulseaudio --start`. Inside proot: `pactl info` |
| **Termux:X11 blank screen** | `pkill -f termux.x11; bash ~/start-ubuntu-x11.sh` |
| **VNC "connection refused"** | VNC may not have started. Enter proot and run `vncserver :1 -geometry 1920x1080 -depth 24 -localhost no` |
| **Error 9 (Termux killed)** | Disable battery optimization for Termux in Android settings |
| **Wine/Notepad++ not working** | On arm64, needs box64: check `dpkg -l box64`. Reinstall if missing from ryanfortner repo |
| **Angry IP Scanner missing** | Re-run `setup-proot.sh` — it auto-downloads the latest from GitHub |
| **Google Drive auth failed** | Run `rclone config` inside proot to reconfigure. Use manual token if browser doesn't work |
| **gdrive-pull/push not found** | Ensure `~/.local/bin` is in PATH: `export PATH="$HOME/.local/bin:$PATH"` |
| **Conky not showing** | Kill and restart: `killall conky; sleep 2; conky -d -c ~/.config/conky/conky.conf` |
| **Android SDK not found** | Source the profile: `source /etc/profile.d/android-sdk.sh` or check `/opt/android-sdk/cmdline-tools/` |
| **WireGuard no interface** | Create config at `/etc/wireguard/wg0.conf` first, then `wg-quick up wg0` |
| **Arduino IDE won't start** | Run `arduino` in terminal for errors. On arm64, the IDE 2.x may need `--no-sandbox` |

### Harmless Proot Warnings (Ignore These)

```
Failed to move to new namespace: PID namespaces supported, ...
dbus / netlink / udev / inotify warnings
SUID sandbox helper binary not found
Received signal 11 (rare — retry launch)
libGL error: failed to open /dev/dri/...
```

### Debug Chromium

The `chromium-default` wrapper logs full environment info:
```bash
# Check the debug log:
cat /tmp/chromium-debug.log

# Run with verbose output:
chromium-default 2>&1 | head -50
```

---

## 12. What Works / What Doesn't in Proot

### Works

- **Desktop**: XFCE4 with bottom dock, dark theme, Humanity icons
- **Browsers**: Chromium (from Debian repos) + Google Chrome (both with `--no-sandbox`)
- **Code editors**: VSCode (with `--no-sandbox --password-store=basic`)
- **Office**: LibreOffice (Writer, Calc, Impress, Draw, Base)
- **Graphics**: GIMP, Blender (software rendering)
- **Video**: Kdenlive, Shotcut
- **Email**: Thunderbird
- **Music**: Spotify (official client on amd64, spotifyd + spotify-tui on arm64)
- **Network**: nmap, traceroute, whois, dig, Angry IP Scanner
- **Windows apps**: Wine + Notepad++ (box64 on arm64)
- **Cloud**: Google Drive via rclone sync/copy/bisync
- **Sound**: PulseAudio over TCP (plays through Android speakers)
- **USB**: OTG devices via bind-mounted `/dev/bus/usb`
- **Languages**: Python 3, Node.js, Java (JDK), Ruby
- **Dev tools**: Android SDK (full), ADB, Arduino CLI + IDE, cmake, gdb, clang, make, tmux, jq, sqlite3
- **VPN**: WireGuard (`wg`, `wg-quick`)
- **System monitor**: Conky desktop widgets (CPU, RAM, Storage, Network, Top Processes)
- **App store**: GNOME Software (graphical package manager)
- **Version control**: Git, SSH, GPG
- **Build systems**: Gradle, Flutter CLI, npm, pip, gem, Maven

### Does NOT Work

| Tool | Why | Alternative |
|---|---|---|
| Docker | Needs kernel namespaces | Remote Docker or Podman (limited) |
| Snap | Needs systemd | Use apt or .deb packages |
| Android Emulator | Needs KVM | Use physical device via ADB |
| Hardware GPU | No `/dev/dri` in proot | Software rendering (`LIBGL_ALWAYS_SOFTWARE=1`) |
| FUSE mounts | No kernel FUSE module | Use rclone sync/copy instead of rclone mount |
| USB auto-mount | Needs kernel driver | Manual mount or raw libusb access |
| GDM/LightDM | Display managers need systemd | VNC xstartup with `startxfce4` |
| systemd services | No systemd in proot | Use `service` commands instead |

> **Note on GDM**: GDM (GNOME Display Manager) cannot run in proot because it requires systemd, PAM, and logind — none of which work in proot. XFCE launched directly via `startxfce4` in the VNC xstartup is the correct approach.

> **Note on FUSE**: `rclone mount` requires FUSE, which needs a kernel module not available in proot. Use `gdrive-pull` / `gdrive-push` / `gdrive-bisync` for Google Drive sync instead.

---

## Quick Reference Card

```bash
# ── Start / Stop ──────────────────────────────────────
bash ~/start-ubuntu-vnc.sh       # Start VNC desktop
bash ~/start-ubuntu-x11.sh      # Start X11 desktop
bash ~/stop-ubuntu.sh            # Stop everything
bash ~/login-ubuntu.sh           # Shell only (no desktop)

# ── Inside Proot ──────────────────────────────────────
bash /root/setup-proot.sh        # (Re)run proot setup
bash /root/gdrive-mount.sh       # Set up Google Drive sync

# ── Google Drive ──────────────────────────────────────
gdrive-pull                      # Download Drive → ~/GoogleDrive
gdrive-push                      # Upload ~/GoogleDrive → Drive
gdrive-copy ~/file Drive/path    # Safe copy (no deletes)
gdrive-bisync                    # Two-way sync
gdrive-status                    # Connection info

# ── Backup / Restore (Termux) ────────────────────────
bash ~/proot-backup.sh backup           # Full backup
bash ~/proot-backup.sh backup --quick   # Quick backup
bash ~/proot-backup.sh restore <file>   # Restore
bash ~/proot-backup.sh list             # List backups

# ── Sound ─────────────────────────────────────────────
paplay /usr/share/sounds/freedesktop/stereo/bell.oga   # Test
pavucontrol                      # Volume mixer

# ── USB ───────────────────────────────────────────────
lsusb                            # List USB devices (proot)
termux-usb -l                    # List USB devices (Termux)
```
