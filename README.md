# Proot Mods — Ubuntu Desktop on Android via Termux

Run a full **XFCE desktop** with **VSCode**, **Chromium**, **Chrome**, development tools, media editors, network utilities, **Wine**, and **Google Drive sync** on Android — no root required.

Uses `proot-distro` to install Ubuntu, then applies sandbox/GPU/keyring mods that Electron, Chromium, and Wine need to function inside proot.

## What You Get

| Category | Apps & Features |
|---|---|
| **OS** | Ubuntu 22.04 LTS or latest (user choice) via `proot-distro` |
| **Desktop** | XFCE4 — dark theme, Humanity icons, bottom dock panel, solid black wallpaper |
| **Display** | TigerVNC (preferred) or Termux:X11 — interactive resolution presets |
| **Browsers** | Chromium (newest from Debian repos) + Google Chrome — both with `--no-sandbox` wrappers |
| **Code Editor** | Visual Studio Code with `--no-sandbox`, `password-store=basic` |
| **Office** | LibreOffice (Writer, Calc, Impress, Draw, Base) |
| **Graphics** | GIMP, Blender (software rendering) |
| **Video** | Kdenlive, Shotcut |
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
| **Panel** | Applications | Settings | Terminal | Thunar | Chrome | Thunderbird | VSCode | Chromium | LibreOffice | GIMP | Blender | Spotify | Tasklist | Volume | Clock (LCD) |
| **Architecture** | arm64 primary, amd64/armhf fallback |

## Quick Start

```bash
# 1. Clone / copy this folder into Termux
# 2. Run the Termux-side setup
bash setup-termux.sh

# 3. It will automatically:
#    - Install proot-distro + Ubuntu (choice of version)
#    - Copy setup-proot.sh + gdrive-mount.sh into the proot
#    - Create launcher scripts in ~/

# 4. Enter the proot and run desktop setup
proot-distro login ubuntu-oldlts    # (or your chosen alias)
bash /root/setup-proot.sh           # Installs ~30 apps + desktop customization

# 5. (Optional) Set up Google Drive
bash /root/gdrive-mount.sh          # Interactive rclone setup

# 6. Exit proot and start the desktop
exit
bash ~/start-ubuntu-vnc.sh          # VNC → connect RealVNC to localhost:5901
# or
bash ~/start-ubuntu-x11.sh          # Termux:X11 app

# 7. Stop
bash ~/stop-ubuntu.sh
```

All scripts are **idempotent** — safe to re-run. They detect existing installs and skip what's already present.

## File Structure

```
proot-mods/
├── setup-termux.sh      # Step 1: Run in Termux — installs Ubuntu, creates launchers
├── setup-proot.sh       # Step 2: Run inside proot — installs desktop + all apps + mods
├── gdrive-mount.sh      # Step 3 (optional): Run inside proot — Google Drive rclone sync
├── proot-backup.sh      # Backup/restore the entire Ubuntu environment
├── instructions.md      # Full documentation (architecture, troubleshooting, etc.)
└── README.md            # This file
```

### setup-termux.sh
Runs in Termux. Installs `proot-distro`, downloads Ubuntu (version choice + re-use detection), copies scripts in, and creates convenience launcher scripts:
- `~/start-ubuntu-vnc.sh` — Start VNC server (resolution presets, PulseAudio, exit trap)
- `~/start-ubuntu-x11.sh` — Start via Termux:X11
- `~/stop-ubuntu.sh` — Kill VNC / X11 / PulseAudio, release wake-lock
- `~/login-ubuntu.sh` — Shell-only login (no desktop)

### setup-proot.sh
Runs inside Ubuntu proot. Installs and configures:
- XFCE4 desktop + TigerVNC with bottom dock panel
- Chromium (newest from Debian Bookworm → Bullseye → Buster fallback, with user choice)
- Google Chrome with proot wrapper
- VSCode with proot wrapper (`--no-sandbox`, `--password-store=basic`)
- Blender, GIMP, LibreOffice, GParted, Kdenlive, Shotcut, Thunderbird, Spotify
- App Store (GNOME Software), WireGuard VPN, Conky desktop system monitor
- Full Android SDK (cmdline-tools, sdkmanager, platform-tools, build-tools, platforms)
- Arduino IDE + Arduino CLI
- Dev tools: ADB, Node.js, Arduino CLI, cmake, gdb, clang, make, tmux, jq, sqlite3, Java, Ruby
- Network tools: nmap, traceroute, whois, dnsutils, Angry IP Scanner
- Wine (+ box64 on arm64) with Notepad++
- Environment variables (`ELECTRON_DISABLE_SANDBOX`, `LIBGL_ALWAYS_SOFTWARE`, etc.)
- Desktop customization (dark theme, Humanity icons, all app launchers in panel, LCD clock, DPMS off, Conky widgets)

### gdrive-mount.sh
Runs inside Ubuntu proot. Sets up Google Drive sync via rclone:
- Installs rclone, walks through Google Drive OAuth
- Creates sync commands: `gdrive-pull`, `gdrive-push`, `gdrive-copy`, `gdrive-bisync`, `gdrive-status`
- Adds Thunar bookmark and desktop shortcut
- Optional auto-pull on login

> FUSE mount is not available in proot — uses rclone sync/copy instead.

### proot-backup.sh
Run in Termux (not inside proot):
```bash
bash proot-backup.sh backup          # Full backup → ~/storage/shared/proot-backups/
bash proot-backup.sh backup --quick  # Skip caches/tmp
bash proot-backup.sh restore <file>  # Restore from archive
bash proot-backup.sh list            # List available backups
bash proot-backup.sh info <file>     # Show backup metadata
```

## Sound

PulseAudio runs in Termux and streams audio to Android speakers over TCP. Both VNC and X11 methods use the same approach.

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

Files sync to `~/GoogleDrive` inside the proot. Use `gdrive-pull Documents` or `gdrive-push Projects` to sync specific subfolders.

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

See [instructions.md](instructions.md) Section 11 for detailed troubleshooting, including:
- VNC black screen fixes
- VSCode crash resolution
- Chromium launch failures
- apt/dpkg lock issues
- Storage permission problems
- Wine/Notepad++ issues
- Google Drive auth problems
- Error 9 (Termux killed by Android)

## License

MIT
