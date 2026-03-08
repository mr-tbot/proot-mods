#!/bin/bash
# ╔════════════════════════════════════════════════════════════════════╗
# ║  VSCode Repair Script — Proot Ubuntu                             ║
# ║  Restores proot wrapper, argv.json, settings.json, .desktop     ║
# ║  files, and ~/.bashrc alias after a VSCode auto-update.          ║
# ║                                                                  ║
# ║  VSCode updates regularly and overwrites:                        ║
# ║    • /usr/bin/code          (our proot wrapper → symlink)        ║
# ║    • /usr/share/applications/code.desktop   (Exec= lines)       ║
# ║    • /usr/share/applications/code-url-handler.desktop            ║
# ║                                                                  ║
# ║  This script re-applies all proot fixes in seconds.              ║
# ║                                                                  ║
# ║  Run INSIDE the proot environment:                               ║
# ║    bash /root/vscode-repair.sh                                   ║
# ╚════════════════════════════════════════════════════════════════════╝
set -euo pipefail

# ── Colors ────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'; CYAN='\033[0;36m'
BOLD='\033[1m'; DIM='\033[2m'; NC='\033[0m'

msg()  { printf "  ${CYAN}▸${NC} %s\n" "$*"; }
ok()   { printf "  ${GREEN}✔${NC} %s\n" "$*"; }
warn() { printf "  ${YELLOW}⚠${NC} %s\n" "$*"; }
err()  { printf "  ${RED}✘${NC} %s\n" "$*"; }
die()  { err "$*"; exit 1; }

printf "\n${BOLD}╔════════════════════════════════════════════════════════════╗${NC}\n"
printf "${BOLD}║   VSCode Repair — Proot Ubuntu                            ║${NC}\n"
printf "${BOLD}║   Restores wrapper + configs after auto-update             ║${NC}\n"
printf "${BOLD}╚════════════════════════════════════════════════════════════╝${NC}\n\n"

# ── Must run as root inside proot ─────────────────────────────────────
[[ "$(id -u)" -eq 0 ]] || die "Must run as root. Try: sudo bash $0"


# ══════════════════════════════════════════════════════════════════════
#  PHASE 1: Locate VSCode binary
# ══════════════════════════════════════════════════════════════════════
printf "\n${BOLD}Phase 1: Locating VSCode binary...${NC}\n\n"

CODE_REAL_BIN=""
if [[ -f /usr/share/code/bin/code ]]; then
    CODE_REAL_BIN="/usr/share/code/bin/code"
elif [[ -f /usr/share/code/code ]]; then
    CODE_REAL_BIN="/usr/share/code/code"
elif [[ -L /usr/bin/code ]]; then
    CODE_REAL_BIN="$(readlink -f /usr/bin/code)"
fi

if [[ -z "$CODE_REAL_BIN" ]]; then
    die "VSCode binary not found. Is VSCode installed? Run setup-proot.sh first."
fi

ok "VSCode binary found: $CODE_REAL_BIN"

# Detect version
_VSCODE_VERSION="$("$CODE_REAL_BIN" --version 2>/dev/null | head -1 || echo 'unknown')"
ok "VSCode version: $_VSCODE_VERSION"


# ══════════════════════════════════════════════════════════════════════
#  PHASE 2: Create/restore proot wrapper at /usr/bin/code
# ══════════════════════════════════════════════════════════════════════
printf "\n${BOLD}Phase 2: Creating proot wrapper...${NC}\n\n"

if [[ -f /usr/bin/code ]]; then
    if head -n 6 /usr/bin/code 2>/dev/null | grep -q "proot VSCode wrapper"; then
        ok "Proot wrapper already in place — refreshing anyway."
    else
        msg "VSCode update overwrote /usr/bin/code — replacing with proot wrapper."
    fi
fi

# Remove whatever is at /usr/bin/code (symlink, stock launcher, or old wrapper)
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
ok "Proot wrapper created: /usr/bin/code → $CODE_REAL_BIN"


# ══════════════════════════════════════════════════════════════════════
#  PHASE 3: Configure argv.json (disable hardware acceleration)
# ══════════════════════════════════════════════════════════════════════
printf "\n${BOLD}Phase 3: Configuring argv.json...${NC}\n\n"

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

_write_argv "/root/.vscode"
_write_argv "/root/.config/Code"
for d in /home/*/; do
    [[ -d "$d" ]] && _write_argv "$d/.config/Code"
    [[ -d "$d" ]] && _write_argv "$d/.vscode"
done


# ══════════════════════════════════════════════════════════════════════
#  PHASE 4: Configure settings.json (fix signature verification)
# ══════════════════════════════════════════════════════════════════════
printf "\n${BOLD}Phase 4: Configuring settings.json...${NC}\n\n"

# VSCode in proot shows "Signature verification failed" errors for
# extensions because the sandbox can't verify signatures properly.
# We also disable workspace trust since proot is always single-user root.

_write_vscode_settings() {
    local settings_dir="$1/User"
    mkdir -p "$settings_dir"
    local settings_file="$settings_dir/settings.json"
    if [[ -f "$settings_file" ]]; then
        # Merge into existing settings — add our keys if not present
        if ! grep -q '"extensions.verifySignature"' "$settings_file" 2>/dev/null; then
            sed -i 's/}$/,\n    "extensions.verifySignature": false\n}/' "$settings_file"
        fi
        if ! grep -q '"security.workspace.trust.enabled"' "$settings_file" 2>/dev/null; then
            sed -i 's/}$/,\n    "security.workspace.trust.enabled": false\n}/' "$settings_file"
        fi
        ok "Updated: $settings_file"
    else
        cat > "$settings_file" <<'VSCODE_SETTINGS'
{
    "extensions.verifySignature": false,
    "security.workspace.trust.enabled": false
}
VSCODE_SETTINGS
        ok "Created: $settings_file"
    fi
}

_write_vscode_settings "/root/.vscode"
_write_vscode_settings "/root/.config/Code"
for d in /home/*/; do
    [[ -d "$d" ]] && _write_vscode_settings "$d/.config/Code"
    [[ -d "$d" ]] && _write_vscode_settings "$d/.vscode"
done


# ══════════════════════════════════════════════════════════════════════
#  PHASE 5: Patch .desktop files
# ══════════════════════════════════════════════════════════════════════
printf "\n${BOLD}Phase 5: Patching .desktop files...${NC}\n\n"

# VSCode updates overwrite the .desktop files and remove our proot flags.
# We patch all Exec= lines to include the necessary flags.

CODE_DESKTOP="/usr/share/applications/code.desktop"
if [[ -f "$CODE_DESKTOP" ]]; then
    [[ ! -f "${CODE_DESKTOP}.bak" ]] && cp "$CODE_DESKTOP" "${CODE_DESKTOP}.bak"
    sed -i 's|^Exec=.*|Exec=/usr/share/code/code --disable-gpu --disable-gpu-compositing --no-sandbox --user-data-dir="/root/.vscode" %F|' "$CODE_DESKTOP"
    ok "Patched: code.desktop"
else
    warn "code.desktop not found — creating it."
    mkdir -p /usr/share/applications
    cat > "$CODE_DESKTOP" <<'CODEDESK'
[Desktop Entry]
Type=Application
Name=Visual Studio Code
Comment=Code Editing. Redefined.
GenericName=Text Editor
Exec=/usr/share/code/code --disable-gpu --disable-gpu-compositing --no-sandbox --user-data-dir="/root/.vscode" %F
Icon=vscode
Terminal=false
Categories=Development;IDE;TextEditor;
MimeType=text/plain;inode/directory;
StartupNotify=true
StartupWMClass=Code
Actions=new-empty-window;

[Desktop Action new-empty-window]
Name=New Empty Window
Exec=/usr/share/code/code --disable-gpu --disable-gpu-compositing --no-sandbox --user-data-dir="/root/.vscode" --new-window %F
CODEDESK
    ok "Created: code.desktop"
fi

CODE_URL_DESKTOP="/usr/share/applications/code-url-handler.desktop"
if [[ -f "$CODE_URL_DESKTOP" ]]; then
    [[ ! -f "${CODE_URL_DESKTOP}.bak" ]] && cp "$CODE_URL_DESKTOP" "${CODE_URL_DESKTOP}.bak"
    sed -i 's|^Exec=.*|Exec=/usr/share/code/code --disable-gpu --disable-gpu-compositing --no-sandbox --user-data-dir="/root/.vscode" --open-url %U|' "$CODE_URL_DESKTOP"
    ok "Patched: code-url-handler.desktop"
fi

update-desktop-database /usr/share/applications 2>/dev/null || true


# ══════════════════════════════════════════════════════════════════════
#  PHASE 6: Ensure ~/.bashrc alias
# ══════════════════════════════════════════════════════════════════════
printf "\n${BOLD}Phase 6: Ensuring ~/.bashrc alias...${NC}\n\n"

# The alias lets users type `code .` in terminal and get proot flags
# automatically, without needing to remember the full flag list.

if ! grep -qF 'alias code=' ~/.bashrc 2>/dev/null; then
    cat >> ~/.bashrc <<'ALIAS'
alias code='code --disable-gpu --disable-gpu-compositing --no-sandbox --user-data-dir="$HOME/.vscode"'
ALIAS
    ok "Added code alias to ~/.bashrc"
else
    ok "~/.bashrc code alias already present"
fi


# ══════════════════════════════════════════════════════════════════════
#  Final verification
# ══════════════════════════════════════════════════════════════════════
printf "\n${BOLD}Final verification...${NC}\n\n"

PASS=0; FAIL=0
_verify() {
    local label="$1" cmd="$2"
    if eval "$cmd" >/dev/null 2>&1; then
        ok "$label"; PASS=$((PASS + 1))
    else
        err "$label"; FAIL=$((FAIL + 1))
    fi
}

_verify "VSCode binary exists"         "test -f /usr/share/code/code || test -f /usr/share/code/bin/code"
_verify "Proot wrapper active"         "head -6 /usr/bin/code 2>/dev/null | grep -q 'proot VSCode wrapper'"
_verify "argv.json exists"             "test -f /root/.vscode/argv.json"
_verify "argv.json has basic store"    "grep -q 'password-store.*basic' /root/.vscode/argv.json"
_verify "argv.json disables HW accel"  "grep -q 'disable-hardware-acceleration.*true' /root/.vscode/argv.json"
_verify "settings.json exists"         "test -f /root/.vscode/User/settings.json"
_verify "settings.json has sig fix"    "grep -q 'extensions.verifySignature.*false' /root/.vscode/User/settings.json"
_verify "code.desktop patched"         "grep -q 'no-sandbox' /usr/share/applications/code.desktop 2>/dev/null"
_verify "bashrc code alias"            "grep -qF 'alias code=' ~/.bashrc"

printf "\n  ─────────────────────────────────────────────\n"
if [[ "$FAIL" -eq 0 ]]; then
    printf "  ${GREEN}${BOLD}ALL ${PASS} CHECKS PASSED${NC}\n"
else
    printf "  ${GREEN}${PASS} passed${NC}, ${RED}${FAIL} failed${NC}\n"
fi

printf "\n${BOLD}  Launch VSCode:${NC}\n"
printf "    code .                     (from terminal)\n"
printf "    Click icon in panel/menu   (from desktop)\n"
printf "\n"

printf "${DIM}  What this script fixed:${NC}\n"
printf "${DIM}    • /usr/bin/code           → proot wrapper (--no-sandbox etc.)${NC}\n"
printf "${DIM}    • argv.json               → disable HW accel, basic password store${NC}\n"
printf "${DIM}    • settings.json           → disable signature verification${NC}\n"
printf "${DIM}    • code.desktop            → Exec= with proot flags${NC}\n"
printf "${DIM}    • ~/.bashrc               → code alias with proot flags${NC}\n"
printf "\n"
printf "${DIM}  Run this script again any time VSCode updates break things.${NC}\n\n"
