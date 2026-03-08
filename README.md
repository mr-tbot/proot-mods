# Proot Dev Mods — Ubuntu Desktop on Android via Termux

Run a full **XFCE desktop** with **VSCode**, **Chromium/Firefox** (user choice), **Chrome**, development tools, media editors, network utilities, **Wine**, and **Google Drive sync** on Android — no root required.

Uses `proot-distro` to install Ubuntu, then applies sandbox/GPU/keyring mods that Electron, Chromium, and Wine need to function inside proot.

## What You Get

| Category | Apps & Features |
|---|---|
| **OS** | Ubuntu 22.04 LTS or latest (user choice) via `proot-distro` |
| **Desktop** | XFCE4 — dark theme, Humanity icons, bottom dock panel, solid black wallpaper |
| **Display** | TigerVNC (preferred) or Termux:X11 — interactive resolution presets |
| **Browsers** | Chromium v89 and/or Firefox (user choice) + Google Chrome — all with proot wrappers/flags |
| **Code Editor** | Visual Studio Code with `--no-sandbox`, `password-store=basic` |
| **Office** | LibreOffice (Writer, Calc, Impress, Draw, Base) |
| **Graphics** | GIMP, Blender (software rendering) |
| **Video** | Kdenlive, Shotcut, OBS Studio |
| **Email** | Thunderbird |
| **Music** | Spotify (official client on amd64, spotifyd + spotify-tui on arm64) |
| **App Store** | GNOME Software (or GNOME PackageKit fallback) — graphical package manager |
| **VPN** | WireGuard (`wg`, `wg-quick`) |
| **System Monitor** | Conky desktop widgets (CPU, RAM, Storage, Network, Top Processes) |
| **Network** | nmap, traceroute, whois, dig, Angry IP Scanner |
| **Windows** | Wine (+ box64 on arm64), Notepad++ |
| **Cloud** | Google Drive sync via rclone (pull/push/bisync) |
| **Dev Tools** | Android SDK (full: cmdline-tools, sdkmanager, platform-tools, build-tools), ADB, Node.js, Arduino CLI + IDE, cmake, gdb, clang, make, tmux, jq, sqlite3, Java JDK, Ruby, Python 3 |
| **Sound** | PulseAudio over TCP (plays through Android speakers) |
| **USB** | OTG devices via bind-mounted `/dev/bus/usb` |
| **Panel** | Applications | Settings | Terminal | Thunar | Chromium/Firefox | Chrome | Thunderbird | VSCode | LibreOffice | GIMP | Blender | Spotify | Tasklist | Volume | Clock (LCD) |
| **Architecture** | arm64 primary, amd64/armhf fallback |

## Quick Start

### 1. Install F-Droid and Termux

**First, install F-Droid** (open-source app store):
1. Go to **https://f-droid.org** on your Android browser
2. Download and install the F-Droid APK
3. Android may warn about "unknown sources" — allow it (this is expected for apps outside the Play Store)
4. You may need to disable **Google Play Protect** temporarily if it blocks the install

**Then install Termux from F-Droid** — **NOT** the Play Store version (it's outdated and will not work). The Termux developer officially recommends the F-Droid build.

Also install **Termux:API** from F-Droid and a VNC viewer — **RealVNC Viewer** (Play Store) is recommended.

> **Android 12+ users**: You must disable the Phantom Process Killer or Termux will be killed randomly. See [instructions.md](instructions.md) Section 3 for the full fix.

### 2. Clone the repo

```bash
pkg update && pkg upgrade -y
pkg install git -y
git clone https://github.com/user/proot-dev-mods.git
```

### 3. Run the Termux setup

```bash
cd proot-dev-mods
chmod +x setup-termux.sh
bash setup-termux.sh
```

Follow the on-screen instructions — the script will:
- Install `proot-distro`, TigerVNC, PulseAudio, Termux:X11 support
- Download and install Ubuntu (you choose the version)
- Copy all scripts into the proot environment
- Let you configure resolution presets for your device(s)
- Create launcher scripts in your Termux home (`~/`)

### 4. Set up the desktop inside Ubuntu

```bash
proot-distro login ubuntu-oldlts    # (or your chosen alias)
bash /root/setup-proot.sh           # Installs ~30 apps + desktop customization
```

This takes 15–30 minutes depending on internet speed. Follow the prompts (browser choice, etc.).

### 5. Exit proot and start the desktop

```bash
exit
bash ~/start-ubuntu-vnc.sh          # Starts VNC in the background
```

Open **RealVNC Viewer** → New Connection → `localhost:5901`

The VNC server runs **in the background** — your Termux shell stays usable. Use `bash ~/stop-ubuntu.sh` when you're done.

### 6. (Optional) Set up Google Drive

```bash
proot-distro login ubuntu-oldlts
bash /root/gdrive-mount.sh          # Interactive rclone setup
```

All scripts are **idempotent** — safe to re-run. They detect existing installs and skip what's already present.

## File Structure

```
proot-dev-mods/
├── setup-termux.sh       # Step 1: Run in Termux — installs Ubuntu, creates launchers
├── setup-proot.sh        # Step 2: Run inside proot — installs desktop + all apps + mods
├── gdrive-mount.sh       # Step 3 (optional): Run inside proot — Google Drive rclone sync
├── proot-backup.sh       # Backup/restore the entire Ubuntu environment
├── chromium-repair.sh    # Fix: reinstall Chromium v89 / Firefox / both (user choice)
├── vscode-repair.sh      # Fix: restore VSCode proot wrapper + configs after updates
├── instructions.md       # Full documentation (architecture, troubleshooting, etc.)
└── README.md             # This file
```

### Launcher scripts (created by setup-termux.sh)

| Script | Purpose |
|---|---|
| `~/start-ubuntu-vnc.sh` | Start VNC desktop in the **background** — choose resolution, PulseAudio, USB passthrough |
| `~/start-ubuntu-x11.sh` | Start desktop via Termux:X11 in the **background** |
| `~/stop-ubuntu.sh` | Stop everything — VNC, X11, PulseAudio, proot sessions, wake-lock |
| `~/login-ubuntu.sh` | Shell-only proot login (no desktop) |

### Repair scripts (inside proot at /root/)

| Script | Purpose |
|---|---|
| `/root/chromium-repair.sh` | Reinstall Chromium v89 from Debian Buster with proot wrapper chain. Run after browser issues or snap contamination. |
| `/root/vscode-repair.sh` | Restore VSCode proot wrapper, `argv.json`, `settings.json`, and `.desktop` patches. Run after any VSCode update. |

### setup-proot.sh
Runs inside Ubuntu proot. Installs and configures:
- XFCE4 desktop + TigerVNC with bottom dock panel
- Browser choice: Chromium v89 (Debian Buster .deb + 14 compat libraries + 4-layer proot wrapper chain) and/or Firefox (Mozilla APT + proot wrapper)
- Google Chrome with proot wrapper
- VSCode with proot wrapper (`--no-sandbox`, `--password-store=basic`)
- Blender, GIMP, LibreOffice, GParted, Kdenlive, Shotcut, OBS Studio, Thunderbird, Spotify
- App Store (GNOME Software), WireGuard VPN, Conky desktop system monitor
- Full Android SDK (cmdline-tools, sdkmanager, platform-tools, build-tools, platforms)
- Arduino IDE + Arduino CLI
- Dev tools: ADB, Node.js, cmake, gdb, clang, make, tmux, jq, sqlite3, Java, Ruby
- Network tools: nmap, traceroute, whois, dnsutils, Angry IP Scanner
- Wine (+ box64 on arm64) with Notepad++
- Environment variables (`ELECTRON_DISABLE_SANDBOX`, `LIBGL_ALWAYS_SOFTWARE`, etc.)
- Desktop customization (dark theme, Humanity icons, all app launchers in panel, LCD clock, DPMS off, Conky widgets)

## Daily Usage

### Starting

```bash
bash ~/start-ubuntu-vnc.sh       # Start VNC (background) → connect to localhost:5901
# or
bash ~/start-ubuntu-x11.sh       # Start X11 (background) → switch to Termux:X11 app
```

Both launchers run in the **background** and return you to the Termux shell immediately. You can continue using the terminal while the desktop runs.

### Stopping

```bash
bash ~/stop-ubuntu.sh            # Stops VNC/X11/PulseAudio, kills proot sessions, releases wake-lock
```

### Shell-only access (no desktop)

```bash
bash ~/login-ubuntu.sh
# or:
proot-distro login ubuntu-oldlts
```

### After a VSCode update

VSCode updates regularly and overwrites the proot wrapper and `.desktop` files. Run the repair script inside proot:

```bash
bash /root/vscode-repair.sh
```

### After browser issues

If Chromium won't launch or snap stubs contaminate the install:

```bash
bash /root/chromium-repair.sh
```

## Sound

PulseAudio runs in Termux and streams audio to Android speakers over TCP. Works with both VNC and X11.

- Volume control widget is in the XFCE panel
- Run `pavucontrol` for advanced mixing
- Test: `paplay /usr/share/sounds/freedesktop/stereo/bell.oga`

> VNC does NOT carry audio — sound plays directly through the device. Since you're on the same physical device, this works perfectly.

## USB

USB OTG devices are bind-mounted into proot automatically by the launcher scripts.

```bash
# Inside proot
lsusb              # List connected USB devices

# In Termux
termux-usb -l      # List USB devices Android sees
```

When you plug in a USB device, Android will prompt you to grant access to Termux — tap Allow.

## Google Drive

```bash
# Inside proot (after running gdrive-mount.sh):
gdrive-pull              # Download Google Drive → ~/GoogleDrive
gdrive-push              # Upload ~/GoogleDrive → Drive (destructive sync)
gdrive-copy ~/file dst   # Safe one-way copy (no deletes)
gdrive-bisync            # Two-way bidirectional sync
gdrive-status            # Show connection info + usage
```

## Backup & Restore

```bash
# In Termux:
bash ~/proot-backup.sh backup          # Full backup → ~/storage/shared/proot-backups/
bash ~/proot-backup.sh backup --quick  # Skip caches/tmp
bash ~/proot-backup.sh restore <file>  # Restore from archive
bash ~/proot-backup.sh list            # List available backups
bash ~/proot-backup.sh info <file>     # Show backup metadata
```

## Display Options

### VNC (Recommended)
1. Install **RealVNC Viewer** from Play Store
2. `bash ~/start-ubuntu-vnc.sh`
3. Choose resolution from presets
4. Connect to `localhost:5901`
5. Set VNC password on first run when prompted

### Termux:X11
1. Install **Termux:X11** companion app
2. `bash ~/start-ubuntu-x11.sh`
3. Switch to the Termux:X11 app

## Known Limitations

| What | Why |
|---|---|
| No `systemd` | proot is not a real VM — use `service` commands instead |
| No `snap` packages | Snap requires systemd + kernel features |
| No `docker` | Needs kernel namespaces — use remote Docker |
| No FUSE mounts | No kernel FUSE module — use rclone sync instead |
| No GDM/LightDM login screen | Display managers need PAM/logind/systemd |
| Harmless sandbox warnings | "Failed to move to new namespace" — expected, can ignore |
| No GPU acceleration | Software rendering only (`LIBGL_ALWAYS_SOFTWARE=1`) |
| USB auto-mount | Raw libusb access works; kernel-level mount needs manual steps |
| VSCode keyring dialog | Cancel it — `password-store=basic` is already active |

## Troubleshooting

See [instructions.md](instructions.md) Section 12 for detailed troubleshooting, including:
- VNC black screen fixes
- VSCode crash resolution
- Chromium/browser launch failures
- apt/dpkg lock issues
- Storage permission problems
- Wine/Notepad++ issues
- Google Drive auth problems
- Error 9 / Signal 9 (Phantom Process Killer — see Section 3 of instructions.md)

## License

MIT
