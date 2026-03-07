#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════
#  setup-proot.sh — Ubuntu proot environment setup
#
#  Installs XFCE desktop, VSCode, Chromium (Debian .deb — NOT snap),
#  Blender, GIMP, LibreOffice, GParted, Python, Android SDK/ADB,
#  Arduino CLI, Node.js, and more development tools.
#  Customizes desktop (black bg, Humanity icons, dock bar with all apps).
#
#  Run INSIDE the Ubuntu proot:
#    proot-distro login ubuntu-oldlts   (or whichever alias)
#    bash /root/setup-proot.sh
#
#  Safe to re-run — detects existing installs and won't double-wrap.
# ═══════════════════════════════════════════════════════════════════════
set -uo pipefail

# ── Colors ────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; DIM='\033[2m'; NC='\033[0m'
msg()  { printf "\n${CYAN}[*]${NC} %s\n" "$*"; }
ok()   { printf "  ${GREEN}✔${NC} %s\n" "$*"; }
warn() { printf "  ${YELLOW}⚠${NC} %s\n" "$*"; }
err()  { printf "  ${RED}✖${NC} %s\n" "$*"; }
skip() { printf "  ${DIM}─ %s (already installed)${NC}\n" "$*"; }

# ── Helper: check if a dpkg package is installed ─────────────────────
_is_installed() { dpkg -s "$1" &>/dev/null; }

# ── Helper: check if ALL named packages are installed ───────────────
_all_installed() {
    for _pkg in "$@"; do
        _is_installed "$_pkg" || return 1
    done
    return 0
}

printf "${BOLD}${CYAN}"
cat <<'BANNER'
  ╔═══════════════════════════════════════════════════════════╗
  ║   Proot Ubuntu Desktop — Environment Setup               ║
  ║   XFCE + VSCode + Chromium + Dev Tools + more            ║
  ╚═══════════════════════════════════════════════════════════╝
BANNER
printf "${NC}\n"

# ── Architecture detection ────────────────────────────────────────────
ARCH="$(dpkg --print-architecture 2>/dev/null || uname -m)"
case "$ARCH" in
    amd64|x86_64)  DEB_ARCH="amd64" ;;
    arm64|aarch64) DEB_ARCH="arm64" ;;
    armhf|armv7*)  DEB_ARCH="armhf" ;;
    *)             DEB_ARCH="arm64"; warn "Unknown arch '$ARCH' — defaulting to arm64" ;;
esac
ok "Architecture: $ARCH (deb: $DEB_ARCH)"

# ── Detect Ubuntu version ────────────────────────────────────────────
UBUNTU_CODENAME="$(lsb_release -cs 2>/dev/null || (. /etc/os-release 2>/dev/null && echo "$VERSION_CODENAME") || echo "unknown")"
UBUNTU_VERSION="$(lsb_release -rs 2>/dev/null || (. /etc/os-release 2>/dev/null && echo "$VERSION_ID") || echo "unknown")"
ok "Ubuntu: $UBUNTU_VERSION ($UBUNTU_CODENAME)"


# ══════════════════════════════════════════════════════════════════════
#  SECTION 0: Fix apt sources.list
# ══════════════════════════════════════════════════════════════════════
msg "Fixing apt sources.list..."

SOURCES=/etc/apt/sources.list
if [[ -f "$SOURCES" ]]; then
    # Backup once
    [[ ! -f "${SOURCES}.bak" ]] && cp "$SOURCES" "${SOURCES}.bak"

    # Replace ftp mirrors with archive.ubuntu.com (more reliable in proot)
    if grep -qE 'ftp[^[:space:]]*\.ubuntu\.com' "$SOURCES"; then
        sed -i -E 's|ftp[^[:space:]]*\.ubuntu\.com|archive.ubuntu.com|g' "$SOURCES"
        ok "Replaced ftp mirror(s) with archive.ubuntu.com"
    else
        ok "No ftp mirrors found — sources.list OK."
    fi

    # Remove duplicate deb lines
    BEFORE=$(grep -cE '^[[:space:]]*deb' "$SOURCES" 2>/dev/null || true)
    TMP=$(mktemp)
    awk '
        /^[[:space:]]*$/ { print; next }
        /^[[:space:]]*#/ { print; next }
        !seen[$0]++      { print; next }
                         { print "# [dup removed] " $0 }
    ' "$SOURCES" > "$TMP" && mv "$TMP" "$SOURCES"
    AFTER=$(grep -cE '^[[:space:]]*deb' "$SOURCES" 2>/dev/null || true)
    REMOVED=$((BEFORE - AFTER))
    [[ "$REMOVED" -gt 0 ]] && ok "Removed $REMOVED duplicate line(s)"
fi

# Also handle newer deb822-format sources (Ubuntu 24.04+ uses ubuntu.sources)
if [[ -f /etc/apt/sources.list.d/ubuntu.sources ]]; then
    ok "Found deb822-format sources (ubuntu.sources) — leaving as-is."
fi

msg "Running apt update & upgrade..."
# Only run full update/upgrade if XFCE isn't installed yet (first run)
# On re-runs, skip the slow apt update/upgrade since packages are present
if ! _is_installed xfce4-session; then
    apt-get update -y
    apt-get upgrade -y
    ok "System updated."
else
    ok "Existing proot environment detected — skipping apt update/upgrade."
    ok "(Re-run mode: will check packages & refresh config.)"
fi


# ── Create /dev/shm (needed by Chromium/Electron apps in proot) ──────
msg "Creating /dev/shm..."
mkdir -p /dev/shm 2>/dev/null || true
chmod 1777 /dev/shm 2>/dev/null || true
ok "/dev/shm directory ensured."


# ══════════════════════════════════════════════════════════════════════
#  SECTION 1: Install XFCE Desktop Environment + VNC
# ══════════════════════════════════════════════════════════════════════
msg "Installing XFCE desktop environment + TigerVNC..."

# NOTE: We use --no-install-recommends to prevent apt from pulling in
# elementary-xfce-icon-theme (10k+ icon files that hang dpkg in proot).
# We explicitly install the icon themes we need afterwards.

# Check key packages from this group to decide if install is needed
if _all_installed xfce4-session xfce4-terminal tigervnc-standalone-server dbus-x11; then
    skip "XFCE desktop + TigerVNC"
else
    DEBIAN_FRONTEND=noninteractive apt-get install -y \
        --no-install-recommends \
        -o Dpkg::Options::="--force-confdef" \
        -o Dpkg::Options::="--force-confold" \
        xfce4 xfce4-terminal \
        xfce4-whiskermenu-plugin xfce4-clipman-plugin \
        xfce4-screenshooter xfce4-taskmanager \
        xfce4-notifyd xfce4-power-manager \
        thunar-archive-plugin \
        dbus dbus-x11 \
        tigervnc-standalone-server tigervnc-common \
        xfonts-base xfonts-100dpi xfonts-75dpi \
        sudo wget curl nano git \
        at-spi2-core libglib2.0-0 \
        locales \
        pulseaudio libpulse0 alsa-utils \
        xfce4-pulseaudio-plugin pavucontrol \
        libusb-1.0-0 usbutils \
        desktop-file-utils shared-mime-info \
        xdg-utils exo-utils

    ok "XFCE desktop + TigerVNC + PulseAudio + USB tools installed."
fi


# ══════════════════════════════════════════════════════════════════════
#  SECTION 2: Install Icon Themes (Humanity + fallbacks)
# ══════════════════════════════════════════════════════════════════════
msg "Installing icon themes (Humanity + fallbacks)..."

# Humanity is the Ubuntu-origin theme that provides the best icon
# coverage for XFCE menu categories (Settings, Accessories, Multimedia,
# System) in proot.  We install several fallback themes plus rebuild
# all icon caches so the panel and menus render correctly.

if _is_installed humanity-icon-theme; then
    skip "Icon themes"
else
    DEBIAN_FRONTEND=noninteractive apt-get install -y \
        --no-install-recommends \
        -o Dpkg::Options::="--force-confdef" \
        -o Dpkg::Options::="--force-confold" \
        humanity-icon-theme \
        adwaita-icon-theme-full \
        hicolor-icon-theme \
        tango-icon-theme \
        ubuntu-mono 2>/dev/null || \
    DEBIAN_FRONTEND=noninteractive apt-get install -y \
        --no-install-recommends \
        humanity-icon-theme \
        adwaita-icon-theme \
        hicolor-icon-theme \
        tango-icon-theme 2>/dev/null || \
    warn "Some icon theme packages could not be installed — menus may have missing icons."

    ok "Icon theme packages installed."
fi

# Rebuild icon caches so XFCE finds all icons immediately
msg "Rebuilding icon caches..."
for theme_dir in /usr/share/icons/*/; do
    if [[ -d "$theme_dir" ]]; then
        gtk-update-icon-cache -f -t "$theme_dir" 2>/dev/null || true
    fi
done
ok "Icon caches rebuilt."

# Update desktop & MIME databases so menu categories populate
update-desktop-database /usr/share/applications 2>/dev/null || true
update-mime-database /usr/share/mime 2>/dev/null || true
ok "Desktop and MIME databases updated."


# ── Set locale ────────────────────────────────────────────────────────
msg "Configuring locale..."
sed -i 's/^# *en_US.UTF-8/en_US.UTF-8/' /etc/locale.gen 2>/dev/null || true
locale-gen en_US.UTF-8 2>/dev/null || true
update-locale LANG=en_US.UTF-8 2>/dev/null || true
ok "Locale set to en_US.UTF-8"


# ── Configure VNC xstartup ────────────────────────────────────────────
msg "Configuring VNC xstartup..."
mkdir -p ~/.vnc

cat > ~/.vnc/xstartup <<'XSTARTUP'
#!/bin/bash
export PULSE_SERVER=127.0.0.1
LANG=en_US.UTF-8
export LANG
export NO_AT_BRIDGE=1
export LIBGL_ALWAYS_SOFTWARE=1
export ELECTRON_DISABLE_SANDBOX=1
export ELECTRON_DISABLE_GPU=1
export MOZ_FAKE_NO_SANDBOX=1
dbus-launch --exit-with-session /usr/bin/startxfce4
XSTARTUP
chmod +x ~/.vnc/xstartup
ok "VNC xstartup configured (dbus-launch --exit-with-session)."

# ── Create .Xauthority (prevents "does not exist" warnings) ──────────
touch /root/.Xauthority
chmod 600 /root/.Xauthority
ok ".Xauthority created."


# ══════════════════════════════════════════════════════════════════════
#  SECTION 3: Install Chromium (from Debian repos — NOT snap)
# ══════════════════════════════════════════════════════════════════════
msg "Installing Chromium..."

# Ubuntu's chromium-browser is a snap stub that doesn't work in proot.
# We install the real .deb Chromium from Debian repos instead.
# Strategy: try newest first (Bookworm ~120+), fall back to older releases.
# The user gets to choose: newest-possible vs proven-stable (Buster v89).

_import_debian_gpg_keys() {
    msg "Importing Debian archive GPG keys..."
    local _keys=(
        "DCC9EFBF77E11517"   # Debian 10 (Buster) Release Key
        "648ACFD622F3D138"   # Debian 11 (Bullseye) Archive Key
        "AA8E81B4331F7F50"   # Debian 10 (Buster) Archive Key
        "112695A0E562B32A"   # Debian Security Archive Key
        "A7236886F3CCCAAD"   # Debian 12 (Bookworm) Release Key
        "4CB50190207B4758"   # Debian 12 (Bookworm) Archive Key
    )

    if command -v apt-key >/dev/null 2>&1; then
        for _key in "${_keys[@]}"; do
            apt-key adv --keyserver keyserver.ubuntu.com --recv-keys "$_key" 2>/dev/null || true
        done
        ok "GPG keys imported via apt-key."
    else
        mkdir -p /usr/share/keyrings
        rm -f /usr/share/keyrings/debian-archive-all.gpg
        for _key in "${_keys[@]}"; do
            gpg --keyserver keyserver.ubuntu.com --recv-keys "$_key" 2>/dev/null && \
                gpg --export "$_key" >> /usr/share/keyrings/debian-archive-all.gpg 2>/dev/null || true
        done
        ok "GPG keys imported to keyring."
    fi
}

_set_debian_repo() {
    local release="$1" url="$2"
    if command -v apt-key >/dev/null 2>&1; then
        cat > /etc/apt/sources.list.d/debian-chromium.list <<DEBREPO
# Debian ${release} — ONLY for Chromium .deb (Ubuntu snap doesn't work in proot)
deb ${url} ${release} main
DEBREPO
    else
        cat > /etc/apt/sources.list.d/debian-chromium.list <<DEBREPO
# Debian ${release} — ONLY for Chromium .deb (Ubuntu snap doesn't work in proot)
deb [signed-by=/usr/share/keyrings/debian-archive-all.gpg] ${url} ${release} main
DEBREPO
    fi
}

_try_install_chromium() {
    local release="$1" url="$2"
    msg "Trying Chromium from Debian ${release}..."

    _set_debian_repo "$release" "$url"
    apt-get update -y 2>/dev/null

    DEBIAN_FRONTEND=noninteractive apt-get install -y \
        -o Dpkg::Options::="--force-confdef" \
        -o Dpkg::Options::="--force-confold" \
        chromium chromium-common 2>/dev/null && {
        ok "Chromium installed from Debian ${release}."
        return 0
    }

    # Retry with just 'chromium'
    DEBIAN_FRONTEND=noninteractive apt-get install -y \
        -o Dpkg::Options::="--force-confdef" \
        -o Dpkg::Options::="--force-confold" \
        chromium 2>/dev/null && {
        ok "Chromium installed from Debian ${release} (minimal)."
        return 0
    }

    return 1
}

_install_chromium_from_debian() {
    # Remove Ubuntu's snap-based chromium stub if present
    apt-get remove -y chromium-browser 2>/dev/null || true

    _import_debian_gpg_keys

    # APT pinning: only allow chromium packages from Debian
    cat > /etc/apt/preferences.d/debian-chromium.pref <<'PINNING'
Package: chromium chromium-common chromium-sandbox chromium-l10n
Pin: release o=Debian
Pin-Priority: 900

Package: *
Pin: release o=Debian
Pin-Priority: -1
PINNING

    # Allow archived repos with expired Release files
    cat > /etc/apt/apt.conf.d/99no-check-valid-until <<'APTCONF'
Acquire::Check-Valid-Until "false";
APTCONF

    # ── Ask user which Chromium version strategy to use ──
    printf "\n  ${BOLD}Chromium version preference:${NC}\n\n"
    printf "  ${BOLD}[1]${NC} Newest possible ${DIM}(Bookworm ~v120+ → Bullseye ~v100 → Buster v89 fallback)${NC}\n"
    printf "  ${BOLD}[2]${NC} Proven stable ${DIM}(Buster v89 — same as Andronix, guaranteed to work)${NC}\n\n"
    printf "  Choice [1]: "
    read -r _chromium_choice

    if [[ "${_chromium_choice:-1}" == "2" ]]; then
        msg "Installing proven-stable Chromium from Debian Buster (v89)..."
        _try_install_chromium "buster" "http://archive.debian.org/debian" && return 0
        err "Buster install failed."
        return 1
    fi

    # Strategy 1: try newest first, fall back
    msg "Trying newest Chromium available..."

    _try_install_chromium "bookworm" "http://deb.debian.org/debian" && return 0
    warn "Bookworm failed — trying Bullseye..."

    _try_install_chromium "bullseye" "http://deb.debian.org/debian" && return 0
    warn "Bullseye failed — trying Buster (v89, guaranteed)..."

    _try_install_chromium "buster" "http://archive.debian.org/debian" && return 0

    err "Failed to install Chromium from any Debian release."
    return 1
}

# Check if we already have a working (non-snap) chromium binary
CHROMIUM_OK=0
if command -v chromium >/dev/null 2>&1; then
    CHROMIUM_PATH="$(command -v chromium)"
    # Check it's real: either an ELF binary, a script, or a wrapper we already created
    if file "$CHROMIUM_PATH" 2>/dev/null | grep -qi "ELF\|script"; then
        # Make sure it's not a snap stub
        if ! head -5 "$CHROMIUM_PATH" 2>/dev/null | grep -qi "snap"; then
            CHROMIUM_OK=1
            ok "Chromium already installed (real binary)."
        fi
    fi
fi

if [[ "$CHROMIUM_OK" -eq 0 ]]; then
    _install_chromium_from_debian
fi


# ── Chromium proot wrapper ────────────────────────────────────────────
msg "Creating Chromium proot wrapper..."

CHROMIUM_BIN=""
[[ -e /usr/bin/chromium ]]         && CHROMIUM_BIN="/usr/bin/chromium"
[[ -e /usr/bin/chromium-browser ]] && CHROMIUM_BIN="/usr/bin/chromium-browser"

if [[ -n "$CHROMIUM_BIN" ]]; then
    if head -n 5 "$CHROMIUM_BIN" 2>/dev/null | grep -q "chromium.*\.real\|proot.*wrapper"; then
        ok "Chromium wrapper already in place."
    else
        CHROMIUM_REAL="${CHROMIUM_BIN}.real"
        if [[ ! -f "$CHROMIUM_REAL" ]]; then
            if [[ -L "$CHROMIUM_BIN" ]]; then
                CHROMIUM_REAL="$(readlink -f "$CHROMIUM_BIN")"
            else
                cp "$CHROMIUM_BIN" "$CHROMIUM_REAL"
                chmod +x "$CHROMIUM_REAL"
            fi
        fi

        cat > "$CHROMIUM_BIN" <<WRAPPER
#!/bin/sh
# proot Chromium wrapper — all flags needed for proot environment
export TMPDIR=/tmp
export XDG_RUNTIME_DIR=\${XDG_RUNTIME_DIR:-/tmp/runtime-\$(whoami)}
mkdir -p \$XDG_RUNTIME_DIR 2>/dev/null
exec "$CHROMIUM_REAL" \\
  --no-sandbox \\
  --disable-dev-shm-usage \\
  --disable-gpu \\
  --disable-software-rasterizer \\
  --no-zygote \\
  --disable-setuid-sandbox \\
  --password-store=basic \\
  --use-mock-keychain \\
  --no-first-run \\
  --no-default-browser-check \\
  --disable-breakpad \\
  --disable-features=WebAuthentication,WebAuthn,SecurePaymentConfirmation \\
  "\$@"
WRAPPER
        chmod +x "$CHROMIUM_BIN"
        ok "Chromium proot wrapper created (calls $CHROMIUM_REAL)"
    fi

    # Create a debug/fallback launcher at /usr/local/bin/chromium-default
    # This is what XFCE's exo-open calls via helpers.rc
    # Matches the Andronix working chromium-default (full env logging)
    cat > /usr/local/bin/chromium-default <<DEBUGWRAPPER
#!/bin/sh
# Chromium debug/XFCE helper wrapper for proot
# All output → log file for debugging launch failures
exec >>/tmp/chromium-default.log 2>&1
echo "----- \$(date) -----"
echo "UID=\$(id -u) USER=\${USER:-root}"
echo "ARGS: \$*"
echo "DISPLAY=\${DISPLAY:-unset}"
echo "XAUTHORITY=\${XAUTHORITY:-unset}"
echo "XDG_RUNTIME_DIR=\${XDG_RUNTIME_DIR:-unset}"
echo "DBUS_SESSION_BUS_ADDRESS=\${DBUS_SESSION_BUS_ADDRESS:-unset}"
echo "PATH=\$PATH"
echo "PWD=\$(pwd)"
echo "which chromium: \$(command -v chromium)"
ls -l /usr/bin/chromium 2>/dev/null

# Ensure runtime dir exists (Chromium needs it for IPC sockets)
export XDG_RUNTIME_DIR="\${XDG_RUNTIME_DIR:-/tmp/runtime-root}"
mkdir -p "\$XDG_RUNTIME_DIR"
chmod 700 "\$XDG_RUNTIME_DIR" 2>/dev/null || true

exec $CHROMIUM_BIN \\
  --no-sandbox \\
  --disable-dev-shm-usage \\
  --disable-gpu \\
  --disable-software-rasterizer \\
  --no-zygote \\
  "\$@"
DEBUGWRAPPER
    chmod +x /usr/local/bin/chromium-default
    ok "Debug wrapper created at /usr/local/bin/chromium-default"

    # Patch .desktop files
    for df in /usr/share/applications/chromium*.desktop; do
        [[ -f "$df" ]] || continue
        [[ ! -f "${df}.bak" ]] && cp "$df" "${df}.bak"
        sed -i "s|^Exec=.*|Exec=$CHROMIUM_BIN --no-sandbox --disable-dev-shm-usage %U|" "$df"
        ok "Patched: $(basename "$df")"
    done

    # Configure chromium.d directory — sourced by the stock Debian launcher (chromium.real)
    # Three files matching the Andronix working configuration
    mkdir -p /etc/chromium.d 2>/dev/null || true

    # default-flags — core Chromium flags
    cat > /etc/chromium.d/default-flags <<'CHROMIUMD'
export CHROMIUM_FLAGS="$CHROMIUM_FLAGS --show-component-extension-options"
export CHROMIUM_FLAGS="$CHROMIUM_FLAGS --enable-gpu-rasterization"
export CHROMIUM_FLAGS="$CHROMIUM_FLAGS --no-default-browser-check"
export CHROMIUM_FLAGS="$CHROMIUM_FLAGS --disable-pings"
export CHROMIUM_FLAGS="$CHROMIUM_FLAGS --media-router=0"
CHROMIUMD

    # apikeys — Debian's public Google API credentials for Chromium
    # (These are the standard Debian package keys, publicly documented)
    cat > /etc/chromium.d/apikeys <<'APIKEYS'
export GOOGLE_API_KEY="AIzaSyCkfPOPZXDKNn8hhgu3JrA62wIgC93d44k"
export GOOGLE_DEFAULT_CLIENT_ID="811574891467.apps.googleusercontent.com"
export GOOGLE_DEFAULT_CLIENT_SECRET="kdloedMFGdGla2P1zacGjAQh"
APIKEYS

    # extensions — enable remote extension loading
    cat > /etc/chromium.d/extensions <<'EXTENSIONS'
export CHROMIUM_FLAGS="$CHROMIUM_FLAGS --enable-remote-extensions"
export CHROMIUM_FLAGS="$CHROMIUM_FLAGS --load-extension=$(ls -dm /usr/share/chromium/extensions/* 2>/dev/null | tr -d '\n')"
EXTENSIONS

    ok "Chromium flags, API keys, and extensions configured (3 files in /etc/chromium.d/)."

    # Set Chromium as the default browser via multiple methods
    # 1. XFCE helpers.rc
    mkdir -p /root/.config/xfce4
    cat > /root/.config/xfce4/helpers.rc <<HELPERSRC
WebBrowserCommand=/usr/local/bin/chromium-default "%s"
WebBrowser=chromium
HELPERSRC
    ok "XFCE helpers.rc configured (Chromium as default browser)."

    # 2. Detect .desktop name
    CHROMIUM_DESKTOP_NAME=""
    [[ -f /usr/share/applications/chromium.desktop ]] && CHROMIUM_DESKTOP_NAME="chromium.desktop"
    [[ -f /usr/share/applications/chromium-browser.desktop ]] && CHROMIUM_DESKTOP_NAME="chromium-browser.desktop"

    if [[ -n "$CHROMIUM_DESKTOP_NAME" ]]; then
        # xdg-settings / xdg-mime
        command -v xdg-settings >/dev/null 2>&1 && \
            xdg-settings set default-web-browser "$CHROMIUM_DESKTOP_NAME" 2>/dev/null || true
        if command -v xdg-mime >/dev/null 2>&1; then
            for mime in x-scheme-handler/http x-scheme-handler/https text/html; do
                xdg-mime default "$CHROMIUM_DESKTOP_NAME" "$mime" 2>/dev/null || true
            done
        fi
    fi

    # 3. update-alternatives
    update-alternatives --install /usr/bin/x-www-browser x-www-browser "$CHROMIUM_BIN" 200 2>/dev/null || true
    update-alternatives --set x-www-browser "$CHROMIUM_BIN" 2>/dev/null || true

    # 4. mimeapps.list
    mkdir -p /root/.local/share/applications
    cat > /root/.local/share/applications/mimeapps.list <<MIMEAPPS
[Default Applications]
x-scheme-handler/http=${CHROMIUM_DESKTOP_NAME:-chromium.desktop}
x-scheme-handler/https=${CHROMIUM_DESKTOP_NAME:-chromium.desktop}
text/html=${CHROMIUM_DESKTOP_NAME:-chromium.desktop}
MIMEAPPS
    ok "Chromium set as default browser (xdg + alternatives + mimeapps)."
fi

# ── Guarantee Chromium .desktop file exists AND is correct (needed for start menu) ──
msg "Ensuring Chromium start menu shortcut..."
_chromium_exec=""
[[ -e /usr/bin/chromium ]]         && _chromium_exec="/usr/bin/chromium"
[[ -e /usr/bin/chromium-browser ]] && _chromium_exec="/usr/bin/chromium-browser"
[[ -z "$_chromium_exec" ]] && _chromium_exec="/usr/bin/chromium"

# Always write the .desktop file to ensure it's correct (idempotent)
if [[ -n "$_chromium_exec" ]] && [[ -e "$_chromium_exec" ]]; then
    cat > /usr/share/applications/chromium.desktop <<CHROMDESK
[Desktop Entry]
Type=Application
Name=Chromium Web Browser
Comment=Access the Internet
GenericName=Web Browser
Exec=$_chromium_exec --no-sandbox --disable-dev-shm-usage %U
Icon=chromium
Terminal=false
Categories=Network;WebBrowser;
MimeType=text/html;text/xml;application/xhtml+xml;x-scheme-handler/http;x-scheme-handler/https;
StartupNotify=true
StartupWMClass=Chromium-browser
Actions=new-window;new-private-window;

[Desktop Action new-window]
Name=New Window
Exec=$_chromium_exec --no-sandbox --disable-dev-shm-usage

[Desktop Action new-private-window]
Name=New Incognito Window
Exec=$_chromium_exec --no-sandbox --disable-dev-shm-usage --incognito
CHROMDESK
    ok "Chromium .desktop file written to /usr/share/applications/"
fi

# Update desktop database so start menu picks up all .desktop files
update-desktop-database /usr/share/applications 2>/dev/null || true


# ══════════════════════════════════════════════════════════════════════
#  SECTION 3b: Install Google Chrome
# ══════════════════════════════════════════════════════════════════════
msg "Installing Google Chrome..."

# Google Chrome for Linux — available for amd64 (and sometimes arm64).
# On unsupported architectures it gracefully skips.

CHROME_INSTALLED=0
if [[ -f /opt/google/chrome/google-chrome ]] || command -v google-chrome-stable >/dev/null 2>&1; then
    CHROME_INSTALLED=1
    ok "Google Chrome already installed."
fi

if [[ "$CHROME_INSTALLED" -eq 0 ]]; then
    # Add Google Chrome signing key
    if [[ ! -f /usr/share/keyrings/google-chrome.gpg ]]; then
        wget -qO- https://dl.google.com/linux/linux_signing_key.pub \
            | gpg --dearmor > /usr/share/keyrings/google-chrome.gpg 2>/dev/null || true
    fi

    # Add Google Chrome repo
    echo "deb [arch=${DEB_ARCH} signed-by=/usr/share/keyrings/google-chrome.gpg] https://dl.google.com/linux/chrome/deb/ stable main" \
        > /etc/apt/sources.list.d/google-chrome.list

    apt-get update -qq

    DEBIAN_FRONTEND=noninteractive apt-get install -y \
        -o Dpkg::Options::="--force-confdef" \
        -o Dpkg::Options::="--force-confold" \
        google-chrome-stable 2>/dev/null && {
        CHROME_INSTALLED=1
        ok "Google Chrome installed."
    } || {
        warn "Google Chrome not available for $DEB_ARCH — using Chromium only."
        rm -f /etc/apt/sources.list.d/google-chrome.list
    }
fi

# ── Google Chrome proot wrapper ───────────────────────────────────────
if [[ "$CHROME_INSTALLED" -eq 1 ]]; then
    msg "Creating Google Chrome proot wrapper..."

    CHROME_BIN=""
    [[ -f /usr/bin/google-chrome-stable ]] && CHROME_BIN="/usr/bin/google-chrome-stable"
    [[ -f /usr/bin/google-chrome ]]        && CHROME_BIN="/usr/bin/google-chrome"

    if [[ -n "$CHROME_BIN" ]]; then
        already_wrapped=0
        head -n 5 "$CHROME_BIN" 2>/dev/null | grep -q "proot.*wrapper\|no-sandbox.*disable-gpu" && already_wrapped=1

        if [[ "$already_wrapped" -eq 0 ]]; then
            # Find the real Chrome binary
            CHROME_REAL=""
            if [[ -f /opt/google/chrome/google-chrome ]]; then
                CHROME_REAL="/opt/google/chrome/google-chrome"
            elif [[ -f "${CHROME_BIN}.real" ]]; then
                CHROME_REAL="${CHROME_BIN}.real"
            else
                cp "$CHROME_BIN" "${CHROME_BIN}.real"
                chmod +x "${CHROME_BIN}.real"
                CHROME_REAL="${CHROME_BIN}.real"
            fi

            cat > "$CHROME_BIN" <<CHRWRAPPER
#!/bin/sh
# proot Google Chrome wrapper
export TMPDIR=/tmp
export XDG_RUNTIME_DIR=\${XDG_RUNTIME_DIR:-/tmp/runtime-\$(whoami)}
mkdir -p \$XDG_RUNTIME_DIR 2>/dev/null
exec "$CHROME_REAL" \\
  --no-sandbox \\
  --disable-dev-shm-usage \\
  --disable-gpu \\
  --disable-software-rasterizer \\
  --no-zygote \\
  --disable-setuid-sandbox \\
  --password-store=basic \\
  --use-mock-keychain \\
  --no-first-run \\
  --no-default-browser-check \\
  --disable-breakpad \\
  --disable-features=WebAuthentication,WebAuthn,SecurePaymentConfirmation \\
  "\$@"
CHRWRAPPER
            chmod +x "$CHROME_BIN"
            ok "Google Chrome proot wrapper created (calls $CHROME_REAL)"
        else
            ok "Google Chrome wrapper already in place."
        fi

        # Patch .desktop files
        for df in /usr/share/applications/google-chrome*.desktop; do
            [[ -f "$df" ]] || continue
            [[ ! -f "${df}.bak" ]] && cp "$df" "${df}.bak"
            sed -i "s|^Exec=.*|Exec=$CHROME_BIN --no-sandbox --disable-dev-shm-usage %U|" "$df"
            ok "Patched: $(basename "$df")"
        done

        # Ensure at least one .desktop file for Chrome in start menu
        if [[ ! -f /usr/share/applications/google-chrome.desktop ]] && [[ ! -f /usr/share/applications/google-chrome-stable.desktop ]]; then
            cat > /usr/share/applications/google-chrome-stable.desktop <<CHRDESK
[Desktop Entry]
Type=Application
Name=Google Chrome
Comment=Access the Internet
GenericName=Web Browser
Exec=$CHROME_BIN --no-sandbox --disable-dev-shm-usage %U
Icon=google-chrome
Terminal=false
Categories=Network;WebBrowser;
MimeType=text/html;text/xml;application/xhtml+xml;x-scheme-handler/http;x-scheme-handler/https;
StartupNotify=true
CHRDESK
            ok "Created google-chrome-stable.desktop"
        fi

        update-desktop-database /usr/share/applications 2>/dev/null || true
    fi

    ok "Google Chrome configuration complete."
fi

# Detect Chrome .desktop name for panel launcher (used in Section 7)
CHROME_DESKTOP=""
[[ -f /usr/share/applications/google-chrome-stable.desktop ]] && CHROME_DESKTOP="google-chrome-stable.desktop"
[[ -f /usr/share/applications/google-chrome.desktop ]]        && CHROME_DESKTOP="google-chrome.desktop"


# ══════════════════════════════════════════════════════════════════════
#  SECTION 4: Install Visual Studio Code
# ══════════════════════════════════════════════════════════════════════
msg "Installing Visual Studio Code..."

_vscode_needs_install=1
if [[ -f /usr/share/code/code ]]; then
    _vscode_needs_install=0
    ok "VSCode binary already present at /usr/share/code/code"
fi

if [[ "$_vscode_needs_install" -eq 1 ]]; then
    # Install prerequisites
    apt-get install -y wget gpg apt-transport-https ca-certificates

    # Add Microsoft GPG key
    if [[ ! -f /usr/share/keyrings/microsoft-archive-keyring.gpg ]]; then
        wget -qO- https://packages.microsoft.com/keys/microsoft.asc \
            | gpg --dearmor > /usr/share/keyrings/microsoft-archive-keyring.gpg 2>/dev/null
        ok "Microsoft GPG key added."
    fi

    # Add VSCode apt repository
    if [[ ! -f /etc/apt/sources.list.d/vscode.list ]]; then
        echo "deb [arch=${DEB_ARCH} signed-by=/usr/share/keyrings/microsoft-archive-keyring.gpg] https://packages.microsoft.com/repos/code stable main" \
            > /etc/apt/sources.list.d/vscode.list
        ok "VSCode apt repository added."
    fi

    # Install VSCode + dependencies
    # Try with libasound2t64 first (Ubuntu 24.04+), fall back to libasound2
    apt-get update -qq
    DEBIAN_FRONTEND=noninteractive apt-get install -y \
        -o Dpkg::Options::="--force-confdef" \
        -o Dpkg::Options::="--force-confold" \
        libsecret-1-0 libgbm1 libasound2t64 libxss1 libnss3 \
        libatk-bridge2.0-0 libgtk-3-0 gnome-keyring code 2>/dev/null || \
    DEBIAN_FRONTEND=noninteractive apt-get install -y \
        -o Dpkg::Options::="--force-confdef" \
        -o Dpkg::Options::="--force-confold" \
        libsecret-1-0 libgbm1 libasound2 libxss1 libnss3 \
        libatk-bridge2.0-0 libgtk-3-0 gnome-keyring code

    ok "VSCode installed."
fi

# ── VSCode proot wrapper ──────────────────────────────────────────────
msg "Creating VSCode proot wrapper..."

# Find the real code binary
CODE_REAL_BIN=""
if [[ -f /usr/share/code/bin/code ]]; then
    CODE_REAL_BIN="/usr/share/code/bin/code"
elif [[ -f /usr/share/code/code ]]; then
    CODE_REAL_BIN="/usr/share/code/code"
elif [[ -L /usr/bin/code ]]; then
    CODE_REAL_BIN="$(readlink -f /usr/bin/code)"
fi

if [[ -n "$CODE_REAL_BIN" ]]; then
    already_wrapped=0
    head -n 6 /usr/bin/code 2>/dev/null | grep -q "proot VSCode wrapper\|no-sandbox.*disable-gpu" && already_wrapped=1

    if [[ "$already_wrapped" -eq 1 ]]; then
        ok "VSCode wrapper already in place."
    else
        # Remove symlink or stock launcher
        rm -f /usr/bin/code

        cat > /usr/bin/code <<WRAPPER
#!/bin/sh
# proot VSCode wrapper — all flags needed for proot
exec $CODE_REAL_BIN \\
  --no-sandbox \\
  --disable-gpu \\
  --disable-gpu-compositing \\
  --disable-dev-shm-usage \\
  --disable-software-rasterizer \\
  --password-store=basic \\
  --user-data-dir="/root/.vscode" \\
  "\$@"
WRAPPER
        chmod +x /usr/bin/code
        ok "VSCode proot wrapper created (calls $CODE_REAL_BIN)"
    fi
else
    warn "Could not locate VSCode binary — wrapper not created."
    warn "You may need to install VSCode manually."
fi

# ── VSCode argv.json ──────────────────────────────────────────────────
msg "Configuring VSCode argv.json..."

_write_argv() {
    local vscode_dir="$1"
    mkdir -p "$vscode_dir"
    cat > "$vscode_dir/argv.json" <<'JSON'
{
    "disable-hardware-acceleration": true,
    "password-store": "basic",
    "disable-chromium-sandbox": true
}
JSON
    ok "Configured: $vscode_dir/argv.json"
}

# Write to both possible locations
_write_argv "/root/.vscode"
_write_argv "/root/.config/Code"
for d in /home/*/; do
    [[ -d "$d" ]] && _write_argv "$d/.config/Code"
    [[ -d "$d" ]] && _write_argv "$d/.vscode"
done

# ── Patch code.desktop ────────────────────────────────────────────────
msg "Patching code.desktop for proot..."

CODE_DESKTOP="/usr/share/applications/code.desktop"
if [[ -f "$CODE_DESKTOP" ]]; then
    [[ ! -f "${CODE_DESKTOP}.bak" ]] && cp "$CODE_DESKTOP" "${CODE_DESKTOP}.bak"
    # Replace ALL Exec= lines with the full proot flags
    sed -i 's|^Exec=.*|Exec=/usr/share/code/code --disable-gpu --disable-gpu-compositing --no-sandbox --user-data-dir="/root/.vscode" %F|' "$CODE_DESKTOP"
    ok "code.desktop Exec= lines patched with proot flags."
fi

# Also patch code-url-handler.desktop if present
CODE_URL_DESKTOP="/usr/share/applications/code-url-handler.desktop"
if [[ -f "$CODE_URL_DESKTOP" ]]; then
    [[ ! -f "${CODE_URL_DESKTOP}.bak" ]] && cp "$CODE_URL_DESKTOP" "${CODE_URL_DESKTOP}.bak"
    sed -i 's|^Exec=.*|Exec=/usr/share/code/code --disable-gpu --disable-gpu-compositing --no-sandbox --user-data-dir="/root/.vscode" --open-url %U|' "$CODE_URL_DESKTOP"
    ok "code-url-handler.desktop patched."
fi


# ══════════════════════════════════════════════════════════════════════
#  SECTION 5: Install Additional Applications
# ══════════════════════════════════════════════════════════════════════
msg "Installing additional applications..."
msg "This may take a while (Blender, GIMP, LibreOffice, GParted, Kdenlive, Shotcut, Thunderbird, Python)..."

if _all_installed blender gimp libreoffice-common gparted python3 kdenlive shotcut thunderbird; then
    skip "Additional applications (Blender, GIMP, LibreOffice, GParted, Kdenlive, Shotcut, Thunderbird, Python)"
else
    DEBIAN_FRONTEND=noninteractive apt-get install -y \
        --no-install-recommends \
        -o Dpkg::Options::="--force-confdef" \
        -o Dpkg::Options::="--force-confold" \
        blender \
        gimp \
        libreoffice \
        gparted \
        kdenlive \
        shotcut \
        thunderbird \
        python3 python3-pip python3-venv python3-dev \
        build-essential \
        file-roller \
        htop \
        tree \
        unzip zip \
        net-tools \
        openssh-client

    ok "Additional applications installed."
fi

# Python: make 'python' available as a command
if ! command -v python >/dev/null 2>&1 && command -v python3 >/dev/null 2>&1; then
    update-alternatives --install /usr/bin/python python /usr/bin/python3 1 2>/dev/null || \
        ln -sf /usr/bin/python3 /usr/bin/python 2>/dev/null || true
    ok "python → python3 symlink created."
fi


# ══════════════════════════════════════════════════════════════════════
#  SECTION 5b: Install Development Tools
# ══════════════════════════════════════════════════════════════════════
msg "Installing development tools..."

# ── Android SDK platform-tools (adb, fastboot) ──────────────────────
if command -v adb >/dev/null 2>&1; then
    skip "Android platform-tools (adb)"
else
    msg "Installing Android SDK platform-tools..."
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        adb fastboot 2>/dev/null || \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        android-tools-adb android-tools-fastboot 2>/dev/null || \
    warn "Android platform-tools not in repos. Download from: https://developer.android.com/tools/releases/platform-tools"
fi

# ── Node.js + npm ─────────────────────────────────────────────────────
if command -v node >/dev/null 2>&1; then
    skip "Node.js + npm"
else
    msg "Installing Node.js + npm..."
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        nodejs npm 2>/dev/null || \
    warn "Node.js not available from repos. Install via nvm: curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash"
fi

# ── Arduino CLI ───────────────────────────────────────────────────────
if command -v arduino-cli >/dev/null 2>&1; then
    skip "Arduino CLI"
else
    msg "Installing Arduino CLI..."
    curl -fsSL https://raw.githubusercontent.com/arduino/arduino-cli/master/install.sh 2>/dev/null \
        | BINDIR=/usr/local/bin sh 2>/dev/null && \
    ok "Arduino CLI installed." || \
    warn "Arduino CLI install failed. Get it from: https://arduino.github.io/arduino-cli/"
fi

# ── Additional dev tools (compilers, debuggers, utilities) ─────────
msg "Installing additional development tools..."
if _all_installed cmake gdb tmux; then
    skip "Additional dev tools (cmake, gdb, tmux, jq, etc.)"
else
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        -o Dpkg::Options::="--force-confdef" \
        -o Dpkg::Options::="--force-confold" \
        cmake \
        gdb \
        clang \
        make \
        pkg-config \
        autoconf automake libtool \
        strace ltrace \
        tmux screen \
        jq \
        sqlite3 libsqlite3-dev \
        libssl-dev libffi-dev \
        default-jdk-headless \
        ruby \
        2>/dev/null || warn "Some dev tools could not be installed (non-fatal)."
    ok "Additional development tools installed."
fi

ok "Development tools section complete."


# ══════════════════════════════════════════════════════════════════════
#  SECTION 5c: Network Tools + Wine / Notepad++
# ══════════════════════════════════════════════════════════════════════

# ── Network scanning tools (nmap + Angry IP Scanner) ───────────────
msg "Installing network scanning tools..."

if command -v nmap >/dev/null 2>&1; then
    skip "nmap"
else
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        nmap traceroute whois dnsutils iputils-ping 2>/dev/null || \
    warn "Some network tools could not be installed."
    ok "Network tools installed (nmap, traceroute, whois, dig)."
fi

# Angry IP Scanner — Java-based GUI network scanner (arch-independent .deb)
if command -v ipscan >/dev/null 2>&1; then
    skip "Angry IP Scanner"
else
    msg "Installing Angry IP Scanner..."
    # Requires Java (installed in dev tools section above)
    # Fetch latest release .deb from GitHub
    _ipscan_installed=0
    IPSCAN_DEB="/tmp/ipscan.deb"

    # Try to get the latest release URL from GitHub API
    IPSCAN_URL=$(curl -fsSL https://api.github.com/repos/angryip/ipscan/releases/latest 2>/dev/null \
        | grep -oP '"browser_download_url":\s*"\K[^"]+_all\.deb' | head -1) || true

    if [[ -n "$IPSCAN_URL" ]]; then
        wget -qO "$IPSCAN_DEB" "$IPSCAN_URL" 2>/dev/null && \
            dpkg -i "$IPSCAN_DEB" 2>/dev/null && _ipscan_installed=1
        apt-get install -f -y 2>/dev/null || true  # fix any missing deps
        [[ $_ipscan_installed -eq 1 ]] && ok "Angry IP Scanner installed from GitHub release."
    fi

    if [[ $_ipscan_installed -eq 0 ]]; then
        # Fallback: try a known recent version
        wget -qO "$IPSCAN_DEB" "https://github.com/angryip/ipscan/releases/download/3.9.1/ipscan_3.9.1_all.deb" 2>/dev/null && \
            dpkg -i "$IPSCAN_DEB" 2>/dev/null && _ipscan_installed=1
        apt-get install -f -y 2>/dev/null || true
        [[ $_ipscan_installed -eq 1 ]] && ok "Angry IP Scanner 3.9.1 installed."
    fi

    [[ $_ipscan_installed -eq 0 ]] && warn "Angry IP Scanner install failed. Get it from: https://angryip.org/download/"
    rm -f "$IPSCAN_DEB" 2>/dev/null
fi

# ── Wine + Notepad++ ───────────────────────────────────────────────
# Wine allows running Windows .exe apps inside the proot.
# On arm64 this needs box64/box86 to translate x86 calls.
# We try to install Wine and set up Notepad++ if it works.
msg "Installing Wine (for Windows app support)..."

WINE_OK=0
if command -v wine >/dev/null 2>&1 || command -v wine64 >/dev/null 2>&1; then
    WINE_OK=1
    skip "Wine"
else
    # Enable 32-bit arch on amd64 (needed for wine32)
    if [[ "$DEB_ARCH" == "amd64" ]]; then
        dpkg --add-architecture i386 2>/dev/null || true
        apt-get update -qq 2>/dev/null
    fi

    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        wine wine64 2>/dev/null && WINE_OK=1 || true

    # Fallback: try wine-stable or wine-development
    if [[ $WINE_OK -eq 0 ]]; then
        DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
            wine-stable 2>/dev/null && WINE_OK=1 || true
    fi
    if [[ $WINE_OK -eq 0 ]]; then
        DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
            wine-development 2>/dev/null && WINE_OK=1 || true
    fi

    # arm64: try box64 + wine-i386-to-arm64 approach
    if [[ $WINE_OK -eq 0 && "$DEB_ARCH" == "arm64" ]]; then
        warn "Native Wine not available for arm64."
        msg "Trying box64 + Wine (x86-on-arm64 translation)..."

        # Install box64 from its PPA / repo if available
        if ! command -v box64 >/dev/null 2>&1; then
            # Try Ubuntu PPA
            if ! apt-get install -y box64 2>/dev/null; then
                # Try from Ryanfortner's repo (popular for arm64 proot)
                wget -qO- https://ryanfortner.github.io/box64-debs/box64.list 2>/dev/null \
                    > /etc/apt/sources.list.d/box64.list && \
                wget -qO- https://ryanfortner.github.io/box64-debs/KEY.gpg 2>/dev/null \
                    | gpg --dearmor > /usr/share/keyrings/box64-archive-keyring.gpg 2>/dev/null && \
                sed -i 's|^deb |deb [signed-by=/usr/share/keyrings/box64-archive-keyring.gpg] |' \
                    /etc/apt/sources.list.d/box64.list 2>/dev/null && \
                apt-get update -qq 2>/dev/null && \
                apt-get install -y box64-generic-arm 2>/dev/null || \
                apt-get install -y box64 2>/dev/null || true
            fi
        fi

        # With box64 available, install x86_64 Wine
        if command -v box64 >/dev/null 2>&1; then
            ok "box64 available — x86_64 emulation enabled."
            # Try installing wine through box64
            apt-get install -y wine64 2>/dev/null && WINE_OK=1 || true
        fi

        [[ $WINE_OK -eq 0 ]] && warn "Wine on arm64 requires box64. Install manually: https://box86.org"
    fi

    [[ $WINE_OK -eq 1 ]] && ok "Wine installed." || warn "Wine could not be installed — Notepad++ will be skipped."
fi

# ── Notepad++ via Wine ───────────────────────────────────────────
NPP_INSTALLED=0
if [[ $WINE_OK -eq 1 ]]; then
    NPP_DIR="$HOME/.wine/drive_c/Program Files/Notepad++"
    if [[ -f "$NPP_DIR/notepad++.exe" ]]; then
        NPP_INSTALLED=1
        skip "Notepad++ (Wine)"
    else
        msg "Installing Notepad++ via Wine..."
        # Initialize Wine prefix (suppress first-run dialogs)
        WINEDEBUG=-all DISPLAY=:1 wineboot --init 2>/dev/null || \
            WINEDEBUG=-all wineboot --init 2>/dev/null || true

        NPP_EXE="/tmp/npp-installer.exe"
        # Download Notepad++ installer (portable/silent)
        NPP_DL_URL=$(curl -fsSL https://api.github.com/repos/notepad-plus-plus/notepad-plus-plus/releases/latest 2>/dev/null \
            | grep -oP '"browser_download_url":\s*"\K[^"]+Installer\.x64\.exe' | head -1) || true

        if [[ -n "$NPP_DL_URL" ]]; then
            wget -qO "$NPP_EXE" "$NPP_DL_URL" 2>/dev/null
        else
            # Fallback to a known version
            wget -qO "$NPP_EXE" "https://github.com/notepad-plus-plus/notepad-plus-plus/releases/download/v8.6.9/npp.8.6.9.Installer.x64.exe" 2>/dev/null || true
        fi

        if [[ -f "$NPP_EXE" && -s "$NPP_EXE" ]]; then
            # Silent install via Wine
            WINEDEBUG=-all wine "$NPP_EXE" /S 2>/dev/null && NPP_INSTALLED=1 || true
            sleep 3
            # Check if it installed
            if [[ -f "$NPP_DIR/notepad++.exe" ]]; then
                NPP_INSTALLED=1
                ok "Notepad++ installed via Wine."
            else
                warn "Notepad++ silent install may not have completed."
                warn "Try running manually:  wine '$NPP_EXE'"
            fi
        else
            warn "Could not download Notepad++ installer."
        fi
        rm -f "$NPP_EXE" 2>/dev/null
    fi

    # Create a .desktop shortcut for Notepad++ if installed
    if [[ $NPP_INSTALLED -eq 1 ]]; then
        cat > /usr/share/applications/notepadpp.desktop <<'NPPDESK'
[Desktop Entry]
Type=Application
Name=Notepad++
Comment=Source code editor (Windows, via Wine)
Exec=wine "C:\\Program Files\\Notepad++\\notepad++.exe" %F
Icon=notepad
Terminal=false
Categories=Development;TextEditor;
MimeType=text/plain;text/x-csrc;text/x-c++src;text/x-python;
NPPDESK
        update-desktop-database /usr/share/applications 2>/dev/null || true
        ok "Notepad++ .desktop shortcut created."
    fi
else
    warn "Wine not available — skipping Notepad++ installation."
    warn "To install later: apt install wine && wine npp-installer.exe /S"
fi

ok "Network tools + Wine section complete."


# ══════════════════════════════════════════════════════════════════════
#  SECTION 5d: Spotify
# ══════════════════════════════════════════════════════════════════════
msg "Installing Spotify..."

if command -v spotify >/dev/null 2>&1 || test -f /usr/share/spotify/spotify; then
    skip "Spotify"
else
    # Spotify ships an official Debian repo for amd64.
    # For arm64 (most Android devices), we use spotifyd + spotify-tui or
    # the snap-less .deb repack from GitHub, or the official repo if amd64.
    _spotify_installed=0

    if [[ "$DEB_ARCH" == "amd64" ]]; then
        # Official Spotify repo (amd64 only)
        msg "Adding official Spotify apt repository (amd64)..."
        curl -fsSL https://download.spotify.com/debian/pubkey_C85668DF69375001.gpg 2>/dev/null \
            | gpg --dearmor -o /usr/share/keyrings/spotify-archive-keyring.gpg 2>/dev/null || true
        echo "deb [signed-by=/usr/share/keyrings/spotify-archive-keyring.gpg] http://repository.spotify.com stable non-free" \
            > /etc/apt/sources.list.d/spotify.list
        apt-get update -y 2>/dev/null || true
        if DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends spotify-client 2>/dev/null; then
            _spotify_installed=1
            ok "Spotify installed from official repo (amd64)."
        fi
    fi

    if [[ $_spotify_installed -eq 0 ]]; then
        # On arm64: install spotifyd (background daemon) + spotify-tui (ncurses client)
        # Or try the snap-less approach via spotify-launcher (Flatpak alt)
        msg "Trying arm64/alternative Spotify install..."

        # Method 1: spotify-launcher from GitHub (Rust-based official-ish launcher)
        # This downloads the official client and patches it to run
        if command -v cargo >/dev/null 2>&1 || apt-get install -y --no-install-recommends cargo 2>/dev/null; then
            if cargo install spotify-launcher 2>/dev/null; then
                _spotify_installed=1
                ok "spotify-launcher installed via cargo."
            fi
        fi
    fi

    if [[ $_spotify_installed -eq 0 ]]; then
        # Method 2: spotifyd + spotify-tui (lightweight TUI client)
        msg "Installing spotifyd + spotify-tui (terminal client)..."

        # spotifyd - Spotify daemon (plays music)
        _spotifyd_url=""
        case "$DEB_ARCH" in
            arm64) _spotifyd_url="https://github.com/Spotifyd/spotifyd/releases/latest/download/spotifyd-linux-aarch64-slim.tar.gz" ;;
            amd64) _spotifyd_url="https://github.com/Spotifyd/spotifyd/releases/latest/download/spotifyd-linux-x86_64-slim.tar.gz" ;;
            armhf) _spotifyd_url="https://github.com/Spotifyd/spotifyd/releases/latest/download/spotifyd-linux-armhf-slim.tar.gz" ;;
        esac

        if [[ -n "$_spotifyd_url" ]]; then
            if curl -fsSL "$_spotifyd_url" 2>/dev/null | tar xz -C /usr/local/bin/ 2>/dev/null; then
                chmod +x /usr/local/bin/spotifyd 2>/dev/null || true
                ok "spotifyd installed."
            else
                warn "Could not download spotifyd."
            fi
        fi

        # spotify-tui (spt) - TUI interface
        _spt_url=""
        case "$DEB_ARCH" in
            arm64) _spt_url="https://github.com/Rigellute/spotify-tui/releases/latest/download/spotify-tui-linux-aarch64.tar.gz" ;;
            amd64) _spt_url="https://github.com/Rigellute/spotify-tui/releases/latest/download/spotify-tui-linux.tar.gz" ;;
            armhf) _spt_url="https://github.com/Rigellute/spotify-tui/releases/latest/download/spotify-tui-linux-armv7.tar.gz" ;;
        esac

        if [[ -n "$_spt_url" ]]; then
            if curl -fsSL "$_spt_url" 2>/dev/null | tar xz -C /usr/local/bin/ 2>/dev/null; then
                chmod +x /usr/local/bin/spt 2>/dev/null || true
                _spotify_installed=1
                ok "spotify-tui (spt) installed."
            else
                warn "Could not download spotify-tui."
            fi
        fi
    fi

    # Create a wrapper script called 'spotify' that launches the best available option
    if [[ $_spotify_installed -eq 1 ]]; then
        if ! command -v spotify >/dev/null 2>&1; then
            cat > /usr/local/bin/spotify <<'SPOTIFY_WRAPPER'
#!/usr/bin/env bash
# Spotify launcher — uses best available client
if command -v spotify-launcher &>/dev/null; then
    exec spotify-launcher "$@"
elif [[ -f /usr/share/spotify/spotify ]]; then
    exec /usr/share/spotify/spotify --no-sandbox --disable-gpu "$@"
elif command -v spt &>/dev/null; then
    # Start spotifyd if not running
    if command -v spotifyd &>/dev/null && ! pgrep -x spotifyd &>/dev/null; then
        echo "Starting spotifyd daemon..."
        spotifyd --no-daemon &
        sleep 1
    fi
    exec spt
else
    echo "No Spotify client found. Install with: apt install spotify-client (amd64)"
    echo "Or use the web player: https://open.spotify.com"
    exit 1
fi
SPOTIFY_WRAPPER
            chmod +x /usr/local/bin/spotify
            ok "Created 'spotify' launcher wrapper."
        fi

        # .desktop shortcut
        cat > /usr/share/applications/spotify.desktop <<'SPOTIFY_DESKTOP'
[Desktop Entry]
Type=Application
Name=Spotify
GenericName=Music Player
Comment=Stream music with Spotify
Exec=spotify %U
Icon=spotify-client
Terminal=false
Categories=Audio;Music;Player;
MimeType=x-scheme-handler/spotify;
SPOTIFY_DESKTOP
        # Try to find a suitable icon
        if [[ ! -f /usr/share/icons/hicolor/256x256/apps/spotify-client.png ]]; then
            mkdir -p /usr/share/icons/hicolor/256x256/apps
            curl -fsSL -o /usr/share/icons/hicolor/256x256/apps/spotify-client.png \
                "https://upload.wikimedia.org/wikipedia/commons/thumb/8/84/Spotify_icon.svg/256px-Spotify_icon.svg.png" 2>/dev/null || true
        fi
        update-desktop-database /usr/share/applications 2>/dev/null || true
        ok "Spotify .desktop shortcut created."
    else
        warn "Spotify could not be installed automatically."
        warn "Options:"
        warn "  - Web player: https://open.spotify.com (via Chromium)"
        warn "  - Manual install: https://www.spotify.com/download/linux/"
    fi
fi

ok "Spotify section complete."


# ══════════════════════════════════════════════════════════════════════
#  SECTION 5e: App Store, WireGuard, Android SDK, Arduino IDE, Conky
# ══════════════════════════════════════════════════════════════════════

# ── App Store (GNOME Software / gnome-packagekit) ────────────────────
msg "Installing app store..."

if _is_installed gnome-software || _is_installed gnome-packagekit; then
    skip "App store (GNOME Software / PackageKit)"
else
    # Try gnome-software first (full-featured app store), fall back to gnome-packagekit
    if DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        gnome-software gnome-software-plugin-flatpak 2>/dev/null; then
        ok "GNOME Software (app store) installed."
    elif DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        gnome-packagekit 2>/dev/null; then
        ok "GNOME PackageKit (app store) installed."
    else
        warn "Could not install app store. Install manually:"
        warn "  apt install gnome-software   OR   apt install gnome-packagekit"
    fi
fi

# ── WireGuard VPN ────────────────────────────────────────────────────
msg "Installing WireGuard..."

if command -v wg >/dev/null 2>&1; then
    skip "WireGuard"
else
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        wireguard-tools 2>/dev/null && \
    ok "WireGuard tools installed." || \
    warn "WireGuard install failed. Install manually: apt install wireguard-tools"
fi

# ── Android SDK (command-line tools + extras) ────────────────────────
msg "Installing Android SDK components..."

ANDROID_SDK_ROOT="/opt/android-sdk"

if [[ -d "$ANDROID_SDK_ROOT/cmdline-tools" ]] || command -v sdkmanager >/dev/null 2>&1; then
    skip "Android SDK command-line tools"
else
    msg "Downloading Android SDK command-line tools..."
    mkdir -p "$ANDROID_SDK_ROOT"

    # Download commandlinetools (works on both amd64 and arm64 since it's Java-based)
    _cmdtools_zip="/tmp/commandlinetools.zip"
    _cmdtools_url="https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip"
    if curl -fsSL -o "$_cmdtools_zip" "$_cmdtools_url" 2>/dev/null; then
        mkdir -p "$ANDROID_SDK_ROOT/cmdline-tools"
        unzip -qo "$_cmdtools_zip" -d "$ANDROID_SDK_ROOT/cmdline-tools/" 2>/dev/null
        # Google's zip extracts to 'cmdline-tools/' — rename to 'latest'
        if [[ -d "$ANDROID_SDK_ROOT/cmdline-tools/cmdline-tools" ]]; then
            mv "$ANDROID_SDK_ROOT/cmdline-tools/cmdline-tools" "$ANDROID_SDK_ROOT/cmdline-tools/latest"
        fi
        rm -f "$_cmdtools_zip"
        ok "Android SDK command-line tools installed."

        # Add to PATH and set ANDROID_SDK_ROOT
        _sdk_profile="/etc/profile.d/android-sdk.sh"
        cat > "$_sdk_profile" <<SDKENV
export ANDROID_SDK_ROOT=$ANDROID_SDK_ROOT
export ANDROID_HOME=$ANDROID_SDK_ROOT
export PATH="\$PATH:$ANDROID_SDK_ROOT/cmdline-tools/latest/bin:$ANDROID_SDK_ROOT/platform-tools"
SDKENV
        chmod +x "$_sdk_profile"
        export ANDROID_SDK_ROOT ANDROID_HOME="$ANDROID_SDK_ROOT"
        export PATH="$PATH:$ANDROID_SDK_ROOT/cmdline-tools/latest/bin:$ANDROID_SDK_ROOT/platform-tools"

        # Accept licenses non-interactively
        if command -v sdkmanager >/dev/null 2>&1; then
            yes 2>/dev/null | sdkmanager --licenses 2>/dev/null || true
            # Install essential SDK packages
            msg "Installing SDK platform-tools and build-tools..."
            sdkmanager "platform-tools" 2>/dev/null && ok "platform-tools installed." || true
            sdkmanager "build-tools;34.0.0" 2>/dev/null && ok "build-tools;34.0.0 installed." || true
            sdkmanager "platforms;android-34" 2>/dev/null && ok "platforms;android-34 installed." || true
        fi
    else
        warn "Could not download Android SDK command-line tools."
        warn "Download manually from: https://developer.android.com/studio#command-tools"
    fi
fi

# Also ensure adb/fastboot is available (lightweight platform-tools)
if ! command -v adb >/dev/null 2>&1; then
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        adb fastboot 2>/dev/null || \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        android-tools-adb android-tools-fastboot 2>/dev/null || true
fi

# ── Arduino IDE ──────────────────────────────────────────────────────
msg "Installing Arduino IDE..."

if _is_installed arduino || test -f /usr/local/bin/arduino-ide; then
    skip "Arduino IDE"
else
    # Try the apt package first (Arduino IDE 1.x — lighter, still very functional)
    if DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        arduino 2>/dev/null; then
        ok "Arduino IDE installed via apt."
    else
        # Arduino IDE 2.x is an Electron app — download AppImage or .deb
        msg "Arduino IDE not in repos. Trying Arduino IDE 2.x download..."
        _arduino_installed=0

        # Try to get latest Arduino IDE 2.x release info
        _ard_api="https://api.github.com/repos/arduino/arduino-ide/releases/latest"
        _ard_json=$(curl -fsSL "$_ard_api" 2>/dev/null || echo "")

        if [[ -n "$_ard_json" ]]; then
            # Look for Linux arm64 or amd64 zip
            _ard_suffix=""
            case "$DEB_ARCH" in
                amd64) _ard_suffix="Linux_64bit.zip" ;;
                arm64) _ard_suffix="Linux_ARM64.zip" ;;
            esac

            if [[ -n "$_ard_suffix" ]]; then
                _ard_url=$(echo "$_ard_json" | grep -o "https://[^\"]*${_ard_suffix}" | head -1)
                if [[ -n "$_ard_url" ]]; then
                    msg "Downloading Arduino IDE 2.x..."
                    _ard_zip="/tmp/arduino-ide.zip"
                    if curl -fsSL -o "$_ard_zip" "$_ard_url" 2>/dev/null; then
                        mkdir -p /opt/arduino-ide
                        unzip -qo "$_ard_zip" -d /opt/arduino-ide/ 2>/dev/null
                        # Find the binary
                        _ard_bin=$(find /opt/arduino-ide -name "arduino-ide" -type f 2>/dev/null | head -1)
                        if [[ -n "$_ard_bin" ]]; then
                            ln -sf "$_ard_bin" /usr/local/bin/arduino-ide
                            chmod +x "$_ard_bin"
                            _arduino_installed=1
                            ok "Arduino IDE 2.x installed to /opt/arduino-ide/"
                        fi
                        rm -f "$_ard_zip"
                    fi
                fi
            fi
        fi

        if [[ $_arduino_installed -eq 0 ]]; then
            warn "Arduino IDE could not be installed automatically."
            warn "Arduino CLI is still available (arduino-cli)."
            warn "For the IDE: https://www.arduino.cc/en/software"
        fi
    fi
fi

# Ensure Arduino CLI is also available
if ! command -v arduino-cli >/dev/null 2>&1; then
    msg "Installing Arduino CLI..."
    curl -fsSL https://raw.githubusercontent.com/arduino/arduino-cli/master/install.sh 2>/dev/null \
        | BINDIR=/usr/local/bin sh 2>/dev/null && \
    ok "Arduino CLI installed." || \
    warn "Arduino CLI install failed. Get it from: https://arduino.github.io/arduino-cli/"
fi

# ── Desktop Performance Widgets (Conky) ──────────────────────────────
msg "Installing desktop performance widgets (Conky)..."

if command -v conky >/dev/null 2>&1; then
    skip "Conky system monitor"
else
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        conky-all 2>/dev/null || \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        conky 2>/dev/null || \
    warn "Conky install failed. Install manually: apt install conky-all"
fi

# Create a nice default conky config
CONKY_DIR="/root/.config/conky"
CONKY_CONF="$CONKY_DIR/conky.conf"
mkdir -p "$CONKY_DIR"

cat > "$CONKY_CONF" <<'CONKY_CFG'
conky.config = {
    alignment = 'top_right',
    background = true,
    border_width = 0,
    cpu_avg_samples = 2,
    default_color = 'white',
    default_outline_color = 'white',
    default_shade_color = 'black',
    double_buffer = true,
    draw_borders = false,
    draw_graph_borders = true,
    draw_outline = false,
    draw_shades = true,
    extra_newline = false,
    font = 'DejaVu Sans Mono:size=10',
    gap_x = 20,
    gap_y = 50,
    minimum_height = 300,
    minimum_width = 250,
    net_avg_samples = 2,
    no_buffers = true,
    out_to_console = false,
    out_to_ncurses = false,
    out_to_stderr = false,
    out_to_x = true,
    own_window = true,
    own_window_class = 'Conky',
    own_window_type = 'desktop',
    own_window_transparent = true,
    own_window_argb_visual = true,
    own_window_argb_value = 0,
    own_window_hints = 'undecorated,below,sticky,skip_taskbar,skip_pager',
    show_graph_range = false,
    show_graph_scale = false,
    stippled_borders = 0,
    update_interval = 2.0,
    uppercase = false,
    use_spacer = 'none',
    use_xft = true,
};

conky.text = [[
${color #88aaff}SYSTEM ${hr 2}${color}
Host:  ${nodename}
OS:    ${sysname} ${machine}
Uptime:${uptime_short}

${color #88aaff}CPU ${hr 2}${color}
Usage: ${cpu}% ${cpubar 8}
${cpugraph 30,250 444444 88aaff}
Core 1: ${cpu cpu1}%  Core 2: ${cpu cpu2}%
Core 3: ${cpu cpu3}%  Core 4: ${cpu cpu4}%

${color #88aaff}MEMORY ${hr 2}${color}
RAM:  ${mem}/${memmax} ${membar 8}
Swap: ${swap}/${swapmax} ${swapbar 8}
${memgraph 30,250 444444 88aaff}

${color #88aaff}STORAGE ${hr 2}${color}
Root: ${fs_used /}/${fs_size /} ${fs_bar 8 /}
Home: ${fs_used /root}/${fs_size /root} ${fs_bar 8 /root}

${color #88aaff}NETWORK ${hr 2}${color}
${if_existing /sys/class/net/eth0}eth0: ${addr eth0}
  Up: ${upspeed eth0}  Down: ${downspeed eth0}${endif}
${if_existing /sys/class/net/wlan0}wlan0: ${addr wlan0}
  Up: ${upspeed wlan0}  Down: ${downspeed wlan0}${endif}

${color #88aaff}TOP PROCESSES ${hr 2}${color}
${color #ffaa88}Name               CPU%  MEM%${color}
${top name 1} ${top cpu 1} ${top mem 1}
${top name 2} ${top cpu 2} ${top mem 2}
${top name 3} ${top cpu 3} ${top mem 3}
${top name 4} ${top cpu 4} ${top mem 4}
${top name 5} ${top cpu 5} ${top mem 5}
]];
CONKY_CFG

ok "Conky config created at $CONKY_CONF"

# Create autostart entry so conky launches with the desktop
AUTOSTART_DIR="/root/.config/autostart"
mkdir -p "$AUTOSTART_DIR"

cat > "$AUTOSTART_DIR/conky.desktop" <<'CONKY_AUTO'
[Desktop Entry]
Type=Application
Name=Conky System Monitor
Comment=Desktop performance widgets
Exec=bash -c 'sleep 5 && conky -d'
Hidden=false
NoDisplay=false
X-GNOME-Autostart-enabled=true
CONKY_AUTO
ok "Conky set to autostart with desktop (5s delay)."

# Create a .desktop entry for manually launching conky
cat > /usr/share/applications/conky.desktop <<'CONKY_DESK'
[Desktop Entry]
Type=Application
Name=System Monitor (Conky)
Comment=Desktop performance and system monitoring widgets
Exec=conky -d
Icon=utilities-system-monitor
Terminal=false
Categories=System;Monitor;
CONKY_DESK
update-desktop-database /usr/share/applications 2>/dev/null || true
ok "Conky .desktop shortcut created."

ok "App store + WireGuard + Android SDK + Arduino IDE + Conky section complete."


# ══════════════════════════════════════════════════════════════════════
#  SECTION 6: Proot Environment Tweaks
# ══════════════════════════════════════════════════════════════════════
msg "Applying proot environment tweaks..."

# Helper: add/update a variable in /etc/environment
_add_env() {
    local var="$1" val="$2"
    if grep -q "^${var}=" /etc/environment 2>/dev/null; then
        sed -i "s|^${var}=.*|${var}=${val}|" /etc/environment
    else
        echo "${var}=${val}" >> /etc/environment
    fi
}

_add_env "LIBGL_ALWAYS_SOFTWARE"                   "1"
_add_env "ELECTRON_DISABLE_GPU"                    "1"
_add_env "ELECTRON_DISABLE_SANDBOX"                "1"
_add_env "ELECTRON_DISABLE_SECURITY_WARNINGS"      "1"
_add_env "VSCODE_KEYTAR_USE_BASIC_TEXT_ENCRYPTION"  "1"
_add_env "NO_AT_BRIDGE"                            "1"
_add_env "PULSE_SERVER"                            "127.0.0.1"
_add_env "MOZ_FAKE_NO_SANDBOX"                     "1"
ok "/etc/environment updated with proot-safe variables."

# Helper: add export to ~/.bashrc if not present
_add_bashrc() {
    grep -qF "export $1=" ~/.bashrc 2>/dev/null || echo "export $1=\"$2\"" >> ~/.bashrc
}

_add_bashrc "ELECTRON_DISABLE_SANDBOX" "1"
_add_bashrc "VSCODE_KEYRING"           "basic"
_add_bashrc "PULSE_SERVER"             "127.0.0.1"
_add_bashrc "MOZ_FAKE_NO_SANDBOX"      "1"

# Add code alias to .bashrc for terminal usage
if ! grep -qF 'alias code=' ~/.bashrc 2>/dev/null; then
    cat >> ~/.bashrc <<'ALIAS'
alias code='code --disable-gpu --disable-gpu-compositing --no-sandbox --user-data-dir="$HOME/.vscode"'
ALIAS
fi
ok "~/.bashrc exports and aliases added."


# ══════════════════════════════════════════════════════════════════════
#  SECTION 7: XFCE Desktop Customization
# ══════════════════════════════════════════════════════════════════════
msg "Customizing XFCE desktop..."

XFCE_XML_DIR="/root/.config/xfce4/xfconf/xfce-perchannel-xml"
mkdir -p "$XFCE_XML_DIR"

# ── 7a. Set desktop background to solid black ─────────────────────────
msg "Setting desktop wallpaper to solid black..."

cat > "$XFCE_XML_DIR/xfce4-desktop.xml" <<'DESKTOP_XML'
<?xml version="1.0" encoding="UTF-8"?>

<channel name="xfce4-desktop" version="1.0">
  <property name="backdrop" type="empty">
    <property name="screen0" type="empty">
      <property name="monitorscreen" type="empty">
        <property name="workspace0" type="empty">
          <property name="color-style" type="int" value="0"/>
          <property name="image-style" type="int" value="0"/>
          <property name="last-image" type="string" value=""/>
          <property name="color1" type="array">
            <value type="uint" value="0"/>
            <value type="uint" value="0"/>
            <value type="uint" value="0"/>
            <value type="uint" value="65535"/>
          </property>
        </property>
        <property name="workspace1" type="empty">
          <property name="color-style" type="int" value="0"/>
          <property name="image-style" type="int" value="0"/>
          <property name="last-image" type="string" value=""/>
          <property name="color1" type="array">
            <value type="uint" value="0"/>
            <value type="uint" value="0"/>
            <value type="uint" value="0"/>
            <value type="uint" value="65535"/>
          </property>
        </property>
        <property name="workspace2" type="empty">
          <property name="color-style" type="int" value="0"/>
          <property name="image-style" type="int" value="0"/>
          <property name="last-image" type="string" value=""/>
          <property name="color1" type="array">
            <value type="uint" value="0"/>
            <value type="uint" value="0"/>
            <value type="uint" value="0"/>
            <value type="uint" value="65535"/>
          </property>
        </property>
        <property name="workspace3" type="empty">
          <property name="color-style" type="int" value="0"/>
          <property name="image-style" type="int" value="0"/>
          <property name="last-image" type="string" value=""/>
          <property name="color1" type="array">
            <value type="uint" value="0"/>
            <value type="uint" value="0"/>
            <value type="uint" value="0"/>
            <value type="uint" value="65535"/>
          </property>
        </property>
      </property>
      <property name="monitordisplay" type="empty">
        <property name="workspace0" type="empty">
          <property name="color-style" type="int" value="0"/>
          <property name="image-style" type="int" value="0"/>
          <property name="last-image" type="string" value=""/>
          <property name="color1" type="array">
            <value type="uint" value="0"/>
            <value type="uint" value="0"/>
            <value type="uint" value="0"/>
            <value type="uint" value="65535"/>
          </property>
        </property>
      </property>
    </property>
  </property>
</channel>
DESKTOP_XML
ok "Desktop background set to solid black."

# ── 7b. XFCE bottom dock with all application launchers ───────────────
msg "Configuring XFCE bottom dock with application launchers..."

# Detect .desktop file names
CHROMIUM_DESKTOP=""
[[ -f /usr/share/applications/chromium.desktop ]]         && CHROMIUM_DESKTOP="chromium.desktop"
[[ -f /usr/share/applications/chromium-browser.desktop ]] && CHROMIUM_DESKTOP="chromium-browser.desktop"

LIBREOFFICE_DESKTOP=""
[[ -f /usr/share/applications/libreoffice-startcenter.desktop ]] && LIBREOFFICE_DESKTOP="libreoffice-startcenter.desktop"
[[ -f /usr/share/applications/libreoffice-writer.desktop ]] && LIBREOFFICE_DESKTOP="libreoffice-writer.desktop"

BLENDER_DESKTOP=""
[[ -f /usr/share/applications/blender.desktop ]] && BLENDER_DESKTOP="blender.desktop"

GIMP_DESKTOP=""
for gd in /usr/share/applications/gimp*.desktop; do
    [[ -f "$gd" ]] && GIMP_DESKTOP="$(basename "$gd")" && break
done

# CHROME_DESKTOP was set in Section 3b (empty string if Chrome not installed)
CHROME_DESKTOP="${CHROME_DESKTOP:-}"

cat > "$XFCE_XML_DIR/xfce4-panel.xml" <<PANEL_XML
<?xml version="1.0" encoding="UTF-8"?>

<channel name="xfce4-panel" version="1.0">
  <property name="configver" type="int" value="2"/>
  <property name="panels" type="array">
    <value type="int" value="1"/>
    <property name="dark-mode" type="bool" value="true"/>
    <property name="panel-1" type="empty">
      <property name="position" type="string" value="p=10;x=0;y=0"/>
      <property name="length" type="uint" value="100"/>
      <property name="position-locked" type="bool" value="true"/>
      <property name="icon-size" type="uint" value="0"/>
      <property name="size" type="uint" value="40"/>
      <property name="mode" type="uint" value="0"/>
      <property name="autohide-behavior" type="uint" value="0"/>
      <property name="plugin-ids" type="array">
        <value type="int" value="1"/>
        <value type="int" value="16"/>
        <value type="int" value="2"/>
        <value type="int" value="3"/>
        <value type="int" value="14"/>
        <value type="int" value="17"/>
        <value type="int" value="5"/>
        <value type="int" value="4"/>
        <value type="int" value="6"/>
        <value type="int" value="7"/>
        <value type="int" value="8"/>
        <value type="int" value="15"/>
        <value type="int" value="9"/>
        <value type="int" value="10"/>
        <value type="int" value="11"/>
        <value type="int" value="12"/>
        <value type="int" value="13"/>
      </property>
    </property>
  </property>
  <property name="plugins" type="empty">
    <property name="plugin-1" type="string" value="applicationsmenu">
      <property name="show-tooltips" type="bool" value="true"/>
      <property name="show-button-title" type="bool" value="true"/>
    </property>
    <property name="plugin-16" type="string" value="launcher">
      <property name="items" type="array">
        <value type="string" value="xfce4-settings-manager.desktop"/>
      </property>
    </property>
    <property name="plugin-2" type="string" value="launcher">
      <property name="items" type="array">
        <value type="string" value="xfce4-terminal.desktop"/>
      </property>
    </property>
    <property name="plugin-3" type="string" value="launcher">
      <property name="items" type="array">
        <value type="string" value="thunar.desktop"/>
      </property>
    </property>
    <property name="plugin-4" type="string" value="launcher">
      <property name="items" type="array">
        <value type="string" value="${CHROMIUM_DESKTOP:-chromium.desktop}"/>
      </property>
    </property>
    <property name="plugin-14" type="string" value="launcher">
      <property name="items" type="array">
        <value type="string" value="${CHROME_DESKTOP:-google-chrome-stable.desktop}"/>
      </property>
    </property>
    <property name="plugin-17" type="string" value="launcher">
      <property name="items" type="array">
        <value type="string" value="thunderbird.desktop"/>
      </property>
    </property>
    <property name="plugin-5" type="string" value="launcher">
      <property name="items" type="array">
        <value type="string" value="code.desktop"/>
      </property>
    </property>
    <property name="plugin-6" type="string" value="launcher">
      <property name="items" type="array">
        <value type="string" value="${LIBREOFFICE_DESKTOP:-libreoffice-startcenter.desktop}"/>
      </property>
    </property>
    <property name="plugin-7" type="string" value="launcher">
      <property name="items" type="array">
        <value type="string" value="${GIMP_DESKTOP:-gimp.desktop}"/>
      </property>
    </property>
    <property name="plugin-8" type="string" value="launcher">
      <property name="items" type="array">
        <value type="string" value="${BLENDER_DESKTOP:-blender.desktop}"/>
      </property>
    </property>
    <property name="plugin-15" type="string" value="launcher">
      <property name="items" type="array">
        <value type="string" value="spotify.desktop"/>
      </property>
    </property>
    <property name="plugin-9" type="string" value="tasklist">
      <property name="flat-buttons" type="bool" value="true"/>
      <property name="show-handle" type="bool" value="false"/>
      <property name="show-labels" type="bool" value="true"/>
    </property>
    <property name="plugin-10" type="string" value="separator">
      <property name="expand" type="bool" value="true"/>
      <property name="style" type="uint" value="0"/>
    </property>
    <property name="plugin-11" type="string" value="systray">
      <property name="known-legacy-items" type="array">
        <value type="string" value="task manager"/>
      </property>
    </property>
    <property name="plugin-12" type="string" value="pulseaudio">
      <property name="enable-keyboard-shortcuts" type="bool" value="true"/>
      <property name="show-notifications" type="bool" value="false"/>
    </property>
    <property name="plugin-13" type="string" value="clock">
      <property name="mode" type="uint" value="2"/>
      <property name="digital-format" type="string" value="%R"/>
    </property>
  </property>
</channel>
PANEL_XML
ok "Bottom dock: Applications | Settings | Terminal | Thunar | Chrome | Thunderbird | VSCode | Chromium | LibreOffice | GIMP | Blender | Spotify | Tasklist | Systray | Volume | Clock (LCD)"

# ── 7b2. Create panel launcher directories ────────────────────────────
# Some XFCE versions need .desktop files in ~/.config/xfce4/panel/launcher-N/
msg "Creating panel launcher directories..."

PANEL_DIR="/root/.config/xfce4/panel"
mkdir -p "$PANEL_DIR"

_link_launcher() {
    local plugin_id=$1 desktop_name=$2
    local launcher_dir="$PANEL_DIR/launcher-$plugin_id"
    mkdir -p "$launcher_dir"
    local src="/usr/share/applications/$desktop_name"
    if [[ -f "$src" ]]; then
        cp "$src" "$launcher_dir/"
        ok "Launcher $plugin_id: $desktop_name"
    fi
}

_link_launcher 16 "xfce4-settings-manager.desktop"
_link_launcher 2  "xfce4-terminal.desktop"
_link_launcher 3  "thunar.desktop"
_link_launcher 14 "${CHROME_DESKTOP:-google-chrome-stable.desktop}"
_link_launcher 17 "thunderbird.desktop"
_link_launcher 5  "code.desktop"
_link_launcher 4  "${CHROMIUM_DESKTOP:-chromium.desktop}"
_link_launcher 6  "${LIBREOFFICE_DESKTOP:-libreoffice-startcenter.desktop}"
_link_launcher 7  "${GIMP_DESKTOP:-gimp.desktop}"
_link_launcher 8  "${BLENDER_DESKTOP:-blender.desktop}"
_link_launcher 15 "spotify.desktop"
ok "Panel launcher directories created."

# ── 7c. Apply dark theme with Humanity icons ──────────────────────────
msg "Setting dark theme with Humanity icons..."

cat > "$XFCE_XML_DIR/xsettings.xml" <<'XSETTINGS_XML'
<?xml version="1.0" encoding="UTF-8"?>

<channel name="xsettings" version="1.0">
  <property name="Net" type="empty">
    <property name="ThemeName" type="string" value="Adwaita-dark"/>
    <property name="IconThemeName" type="string" value="Humanity"/>
    <property name="CursorThemeName" type="string" value="Adwaita"/>
    <property name="CursorSize" type="int" value="24"/>
    <property name="EnableEventSounds" type="bool" value="false"/>
    <property name="EnableInputFeedbackSounds" type="bool" value="false"/>
  </property>
  <property name="Xft" type="empty">
    <property name="Antialias" type="int" value="1"/>
    <property name="Hinting" type="int" value="1"/>
    <property name="HintStyle" type="string" value="hintslight"/>
    <property name="RGBA" type="string" value="rgb"/>
    <property name="DPI" type="int" value="96"/>
  </property>
</channel>
XSETTINGS_XML

cat > "$XFCE_XML_DIR/xfwm4.xml" <<'XFWM4_XML'
<?xml version="1.0" encoding="UTF-8"?>

<channel name="xfwm4" version="1.0">
  <property name="general" type="empty">
    <property name="theme" type="string" value="Default-hdpi"/>
    <property name="title_font" type="string" value="Sans Bold 10"/>
    <property name="workspace_count" type="int" value="4"/>
    <property name="use_compositing" type="bool" value="false"/>
    <property name="cycle_draw_frame" type="bool" value="true"/>
    <property name="cycle_raise" type="bool" value="true"/>
  </property>
</channel>
XFWM4_XML

# ── 7d. XFCE session config ─────────────────────────────────────────
cat > "$XFCE_XML_DIR/xfce4-session.xml" <<'SESSION_XML'
<?xml version="1.0" encoding="UTF-8"?>

<channel name="xfce4-session" version="1.0">
  <property name="general" type="empty">
    <property name="FailsafeSessionName" type="string" value="Failsafe"/>
    <property name="LockCommand" type="string" value=""/>
    <property name="SaveOnExit" type="bool" value="false"/>
  </property>
  <property name="sessions" type="empty">
    <property name="Failsafe" type="empty">
      <property name="IsFailsafe" type="bool" value="true"/>
      <property name="Count" type="int" value="5"/>
      <property name="Client0_Command" type="array">
        <value type="string" value="xfwm4"/>
      </property>
      <property name="Client0_PerScreen" type="bool" value="false"/>
      <property name="Client1_Command" type="array">
        <value type="string" value="xfsettingsd"/>
      </property>
      <property name="Client1_PerScreen" type="bool" value="false"/>
      <property name="Client2_Command" type="array">
        <value type="string" value="xfce4-panel"/>
      </property>
      <property name="Client2_PerScreen" type="bool" value="false"/>
      <property name="Client3_Command" type="array">
        <value type="string" value="Thunar"/>
        <value type="string" value="--daemon"/>
      </property>
      <property name="Client3_PerScreen" type="bool" value="false"/>
      <property name="Client4_Command" type="array">
        <value type="string" value="xfdesktop"/>
      </property>
      <property name="Client4_PerScreen" type="bool" value="false"/>
    </property>
  </property>
</channel>
SESSION_XML

# ── 7e. Disable display power management (DPMS / screensaver) ────────
msg "Disabling display power management..."

cat > "$XFCE_XML_DIR/xfce4-power-manager.xml" <<'POWER_XML'
<?xml version="1.0" encoding="UTF-8"?>

<channel name="xfce4-power-manager" version="1.0">
  <property name="xfce4-power-manager" type="empty">
    <property name="dpms-enabled" type="bool" value="false"/>
    <property name="blank-on-ac" type="int" value="0"/>
    <property name="dpms-on-ac-sleep" type="uint" value="0"/>
    <property name="dpms-on-ac-off" type="uint" value="0"/>
    <property name="blank-on-battery" type="int" value="0"/>
    <property name="dpms-on-battery-sleep" type="uint" value="0"/>
    <property name="dpms-on-battery-off" type="uint" value="0"/>
    <property name="lock-screen-suspend-hibernate" type="bool" value="false"/>
    <property name="logind-handle-lid-switch" type="bool" value="false"/>
  </property>
</channel>
POWER_XML

# Also disable xfce4-screensaver if present
if command -v xfce4-screensaver-command >/dev/null 2>&1; then
    xfce4-screensaver-command --deactivate 2>/dev/null || true
fi

# xset dpms off for good measure (applied at session start via xstartup)
if grep -qF 'xset' /root/.vnc/xstartup 2>/dev/null; then
    if ! grep -qF 'dpms' /root/.vnc/xstartup 2>/dev/null; then
        sed -i '/startxfce4/i xset s off -dpms 2>/dev/null || true' /root/.vnc/xstartup
        ok "Added 'xset s off -dpms' to VNC xstartup."
    fi
else
    ok "xset dpms will be handled by power manager config."
fi

ok "Display power management disabled."
ok "Dark theme + Humanity icons + session config applied."


# ══════════════════════════════════════════════════════════════════════
#  SECTION 8: Final Validation
# ══════════════════════════════════════════════════════════════════════
msg "Validating installation..."
echo ""

_check() {
    local name="$1" cmd="$2" ver_cmd="$3"
    if eval "$cmd" >/dev/null 2>&1; then
        local ver
        ver=$(eval "$ver_cmd" 2>/dev/null || echo "ok")
        printf "  ${GREEN}✔${NC} %-30s %s\n" "$name" "$ver"
    else
        printf "  ${RED}✖${NC} %-30s ${DIM}not found${NC}\n" "$name"
    fi
}

printf "  ${BOLD}Desktop & Display${NC}\n"
printf "  ${DIM}──────────────────────────────────────────────${NC}\n"
_check "XFCE Desktop"       "command -v startxfce4"   "echo 'installed'"
_check "TigerVNC Server"    "command -v vncserver"     "vncserver -version 2>&1 | head -1"
echo ""

printf "  ${BOLD}Applications${NC}\n"
printf "  ${DIM}──────────────────────────────────────────────${NC}\n"
_check "Chromium"           "command -v chromium || command -v chromium-browser" "echo 'installed'"
_check "Google Chrome"      "command -v google-chrome-stable || command -v google-chrome" "echo 'installed'"
_check "Visual Studio Code" "test -f /usr/share/code/code"  "/usr/share/code/code --version 2>/dev/null | head -1 || echo 'installed'"
_check "Blender"            "command -v blender"       "blender --version 2>/dev/null | head -1"
_check "GIMP"               "command -v gimp"          "gimp --version 2>/dev/null | head -1"
_check "LibreOffice"        "command -v libreoffice"   "libreoffice --version 2>/dev/null | head -1"
_check "GParted"            "command -v gparted"       "echo 'installed'"
_check "Kdenlive"           "command -v kdenlive"      "echo 'installed'"
_check "Shotcut"            "command -v shotcut"       "echo 'installed'"
_check "Thunderbird"        "command -v thunderbird"   "thunderbird --version 2>/dev/null | head -1"
_check "Spotify"            "command -v spotify || command -v spt || test -f /usr/share/spotify/spotify" "echo 'installed'"
_check "App store"          "command -v gnome-software || command -v gpk-application"  "echo 'installed'"
_check "Python"             "command -v python3"       "python3 --version"
_check "Git"                "command -v git"           "git --version"
echo ""

printf "  ${BOLD}Proot Mods${NC}\n"
printf "  ${DIM}──────────────────────────────────────────────${NC}\n"
_check "Environment vars"   "grep -q ELECTRON_DISABLE_SANDBOX /etc/environment"                                    "echo '/etc/environment'"
_check "VSCode argv.json"   "test -f /root/.vscode/argv.json"                                                      "echo 'configured'"
_check "VSCode wrapper"     "grep -q 'proot VSCode wrapper' /usr/bin/code 2>/dev/null"                            "echo '/usr/bin/code'"
_check "Chromium wrapper"   "grep -q 'proot.*[Cc]hromium.*wrapper' /usr/bin/chromium 2>/dev/null || grep -q 'proot.*wrapper' /usr/bin/chromium-browser 2>/dev/null" "echo 'wrapped'"
_check "Chrome wrapper"     "grep -q 'proot.*[Cc]hrome.*wrapper' /usr/bin/google-chrome-stable 2>/dev/null || grep -q 'proot.*wrapper' /usr/bin/google-chrome 2>/dev/null" "echo 'wrapped'"
_check "/dev/shm"           "test -d /dev/shm"                                                                  "echo 'exists'"
_check ".Xauthority"        "test -f /root/.Xauthority"                                                         "echo 'exists'"
_check "Default browser"    "test -f /root/.config/xfce4/helpers.rc"                                                "echo 'Chromium'"
echo ""

printf "  ${BOLD}Audio & USB${NC}\n"
printf "  ${DIM}──────────────────────────────────────────────${NC}\n"
_check "PulseAudio client"  "command -v pactl"         "pactl --version 2>/dev/null | head -1"
_check "PULSE_SERVER env"   "grep -q PULSE_SERVER /etc/environment"   "echo '127.0.0.1 (Termux TCP)'"
_check "pavucontrol"        "command -v pavucontrol"   "echo 'installed'"
_check "lsusb"             "command -v lsusb"         "echo 'installed'"
_check "libusb"            "dpkg -s libusb-1.0-0 2>/dev/null | grep -q installed" "echo 'installed'"
echo ""

printf "  ${BOLD}Development Tools${NC}\n"
printf "  ${DIM}──────────────────────────────────────────────${NC}\n"
_check "Android adb"        "command -v adb"            "adb --version 2>/dev/null | head -1"
_check "Node.js"            "command -v node"           "node --version 2>/dev/null"
_check "npm"                "command -v npm"            "npm --version 2>/dev/null"
_check "Arduino CLI"        "command -v arduino-cli"    "arduino-cli version 2>/dev/null | head -1"
_check "Java JDK"           "command -v javac || command -v java"  "java -version 2>&1 | head -1"
_check "CMake"              "command -v cmake"          "cmake --version 2>/dev/null | head -1"
_check "GDB"                "command -v gdb"            "gdb --version 2>/dev/null | head -1"
_check "Clang"              "command -v clang"          "clang --version 2>/dev/null | head -1"
_check "tmux"               "command -v tmux"           "tmux -V 2>/dev/null"
_check "Ruby"               "command -v ruby"           "ruby --version 2>/dev/null"
echo ""

printf "  ${BOLD}Network & Windows Apps${NC}\n"
printf "  ${DIM}──────────────────────────────────────────────${NC}\n"
_check "nmap"               "command -v nmap"           "nmap --version 2>/dev/null | head -1"
_check "Angry IP Scanner"   "command -v ipscan"         "echo 'installed'"
_check "Wine"               "command -v wine || command -v wine64"  "wine --version 2>/dev/null || wine64 --version 2>/dev/null"
_check "box64 (arm64)"      "command -v box64"          "box64 --version 2>/dev/null | head -1 || echo 'installed'"
_check "Notepad++ (Wine)"   "test -f \"$HOME/.wine/drive_c/Program Files/Notepad++/notepad++.exe\"" "echo 'installed'"
_check "WireGuard"          "command -v wg"             "wg --version 2>/dev/null || echo 'installed'"
echo ""

printf "  ${BOLD}Android SDK & Arduino${NC}\n"
printf "  ${DIM}──────────────────────────────────────────────${NC}\n"
_check "Android SDK"        "test -d /opt/android-sdk/cmdline-tools || command -v sdkmanager" "echo '/opt/android-sdk'"
_check "sdkmanager"         "command -v sdkmanager"     "echo 'installed'"
_check "Android adb"        "command -v adb"            "adb --version 2>/dev/null | head -1"
_check "Arduino IDE"        "command -v arduino || test -f /usr/local/bin/arduino-ide" "echo 'installed'"
_check "Arduino CLI"        "command -v arduino-cli"    "arduino-cli version 2>/dev/null | head -1"
echo ""

printf "  ${BOLD}Desktop Customization${NC}\n"
printf "  ${DIM}──────────────────────────────────────────────${NC}\n"
_check "Black wallpaper"    "test -f $XFCE_XML_DIR/xfce4-desktop.xml"   "echo 'configured'"
_check "Panel + launchers"  "test -f $XFCE_XML_DIR/xfce4-panel.xml"     "echo 'bottom dock'"
_check "Launcher dirs"      "test -d /root/.config/xfce4/panel/launcher-2" "echo 'configured'"
_check "Humanity icons"     "test -d /usr/share/icons/Humanity"          "echo 'Humanity'"
_check "Dark theme"         "test -f $XFCE_XML_DIR/xsettings.xml"       "echo 'Adwaita-dark'"
_check "DPMS disabled"      "test -f $XFCE_XML_DIR/xfce4-power-manager.xml" "echo 'power mgmt off'"
_check "Conky widgets"      "command -v conky"          "echo 'installed'"
_check "Conky config"       "test -f /root/.config/conky/conky.conf"     "echo 'configured'"
_check "VNC xstartup"       "test -f /root/.vnc/xstartup"               "echo 'configured'"
echo ""


# ══════════════════════════════════════════════════════════════════════
#  Done
# ══════════════════════════════════════════════════════════════════════
printf "${GREEN}${BOLD}"
printf '═%.0s' {1..60}
printf "\n  Proot setup complete!\n"
printf '═%.0s' {1..60}
printf "${NC}\n\n"

cat <<'DONE'
  Next steps:

    1. Exit proot:
         exit

    2. Start the desktop (pick one):

       VNC (recommended):
         bash ~/start-ubuntu-vnc.sh
         → Open RealVNC Viewer → connect to localhost:5901

       Termux:X11:
         bash ~/start-ubuntu-x11.sh
         → Open the Termux:X11 app

    3. Inside the desktop:
       • Bottom dock: Applications | Settings | Terminal | Thunar | Chrome |
                     Thunderbird | VSCode | Chromium | LibreOffice |
                     GIMP | Blender | Spotify | Tasklist | Volume |
                     Clock (LCD)
       • Or launch from terminal:
           code .
           chromium
           google-chrome-stable
           gimp
           blender
           libreoffice
           kdenlive
           shotcut
           spotify

    4. Development tools available:
         adb              — Android Debug Bridge
         sdkmanager       — Android SDK manager
         arduino-cli      — Arduino board programming
         arduino          — Arduino IDE (if installed)
         node / npm       — JavaScript runtime
         python3 / pip    — Python development
         cmake / make     — Build systems
         gdb              — GNU debugger
         clang / gcc      — C/C++ compilers
         javac            — Java compiler
         ruby             — Ruby interpreter
         tmux             — Terminal multiplexer
         git              — Version control
         wg               — WireGuard VPN
         conky            — Desktop system monitor

    5. To stop:
         bash ~/stop-ubuntu.sh

  Sound:
    Audio plays through Android device speakers via PulseAudio TCP.
    • Termux starts PulseAudio server; proot connects at 127.0.0.1
    • Works with both VNC and Termux:X11 display methods
    • Volume control is in the panel (speaker icon)
    • For advanced mixing: run  pavucontrol

  USB:
    USB OTG devices are accessible if Termux has USB permission.
    • The launcher scripts bind-mount /dev/bus/usb into proot
    • Run  lsusb  inside proot to list connected devices
    • For USB permission: plug in device → Android will prompt
      → Grant access to Termux
    • Also try:  termux-usb -l  in Termux to list USB devices

  Chromium troubleshooting:
    If Chromium shows "Input/output error":
    → Check /tmp/chromium-default.log for detailed launch diagnostics
    → Try running directly:  /usr/bin/chromium.real --no-sandbox --disable-dev-shm-usage
    → If that fails, the Buster binary may be incompatible — file a bug

    Chromium launch chain (for debugging):
    → exo-open / panel click
    → /usr/local/bin/chromium-default  (logs env, adds 5 flags)
    → /usr/bin/chromium                (proot wrapper, adds 9 flags)
    → /usr/bin/chromium.real           (stock Debian launcher, sources /etc/chromium.d/)
    → /usr/lib/chromium/chromium       (actual ELF binary)

  Expected harmless proot warnings (ignore these):
    - "Failed to move to new namespace..."
    - "SUID sandbox helper binary not found"
    - dbus / netlink / udev / inotify warnings

  If VSCode shows a keyring unlock dialog:
    → Just cancel it. password-store=basic is already configured.

  VNC won't connect on second launch?
    → Run:  bash ~/stop-ubuntu.sh  first, then start again.
    → The stop script cleans up stale VNC locks and PID files.

  Termux keeps getting killed (error 9)?
    → Disable battery optimization for Termux in Android Settings:
      Settings → Apps → Termux → Battery → Unrestricted
    → Also ensure Termux has a persistent notification (wake lock).

  Google Chrome not available?
    → Chrome for Linux may not support your CPU architecture.
    → Chromium works the same way and is always available.

DONE