#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════
#  gdrive-mount.sh — Google Drive sync via rclone (proot-compatible)
#
#  Installs rclone, guides Google Drive OAuth setup, creates sync
#  wrapper scripts, Thunar bookmark, and desktop shortcut.
#
#  FUSE mount is NOT available inside proot (no kernel module), so
#  this script uses rclone sync/copy/bisync for file transfer.
#
#  Run INSIDE the Ubuntu proot:
#    bash /root/gdrive-mount.sh
#
#  Safe to re-run — detects existing config and skips accordingly.
# ═══════════════════════════════════════════════════════════════════════
set -uo pipefail

# ── Colors ────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; DIM='\033[2m'; NC='\033[0m'
msg()  { printf "\n${CYAN}[*]${NC} %s\n" "$*"; }
ok()   { printf "  ${GREEN}✔${NC} %s\n" "$*"; }
warn() { printf "  ${YELLOW}⚠${NC} %s\n" "$*"; }
err()  { printf "  ${RED}✖${NC} %s\n" "$*"; }
skip() { printf "  ${DIM}─ %s (already done)${NC}\n" "$*"; }

GDRIVE_DIR="$HOME/GoogleDrive"
REMOTE_NAME="gdrive"
RCLONE_CONF="$HOME/.config/rclone/rclone.conf"
SYNC_SCRIPTS_DIR="$HOME/.local/bin"

printf "${BOLD}${CYAN}"
cat <<'BANNER'
  ╔═══════════════════════════════════════════════════════════╗
  ║   Google Drive Sync — rclone Setup                        ║
  ║   Sync files between proot and Google Drive               ║
  ╚═══════════════════════════════════════════════════════════╝
BANNER
printf "${NC}\n"

warn "FUSE mount is not available inside proot (no kernel module)."
warn "This script sets up rclone SYNC-based access instead."
printf "  ${DIM}Your Google Drive files will live in ~/GoogleDrive${NC}\n"
printf "  ${DIM}Use the provided sync scripts to push/pull changes.${NC}\n\n"

# ══════════════════════════════════════════════════════════════════════
#  1. Install rclone
# ══════════════════════════════════════════════════════════════════════
msg "Installing rclone..."

if command -v rclone &>/dev/null; then
    skip "rclone $(rclone --version 2>/dev/null | head -1 | awk '{print $2}')"
else
    # Try package manager first, fall back to official installer
    if apt-get install -y rclone 2>/dev/null; then
        ok "rclone installed via apt."
    else
        msg "apt package not found — installing via official rclone script..."
        apt-get install -y curl unzip 2>/dev/null || true
        curl -fsSL https://rclone.org/install.sh | bash
        ok "rclone installed via official installer."
    fi
fi

rclone --version 2>/dev/null | head -1 && true

# ══════════════════════════════════════════════════════════════════════
#  2. Create local GoogleDrive directory
# ══════════════════════════════════════════════════════════════════════
msg "Setting up ~/GoogleDrive directory..."

if [[ -d "$GDRIVE_DIR" ]]; then
    skip "~/GoogleDrive directory"
else
    mkdir -p "$GDRIVE_DIR"
    ok "Created ~/GoogleDrive"
fi

# ══════════════════════════════════════════════════════════════════════
#  3. Configure rclone Google Drive remote
# ══════════════════════════════════════════════════════════════════════
msg "Configuring Google Drive remote..."

_remote_exists() {
    rclone listremotes 2>/dev/null | grep -q "^${REMOTE_NAME}:$"
}

if _remote_exists; then
    skip "rclone remote '$REMOTE_NAME' already configured"
    printf "\n"
    printf "  ${BOLD}Current remotes:${NC}\n"
    rclone listremotes 2>/dev/null | sed 's/^/    /'
    printf "\n"

    printf "  ${BOLD}Reconfigure?${NC}\n"
    printf "    1) Keep existing config (default)\n"
    printf "    2) Delete and reconfigure\n"
    printf "  ${BOLD}Choice [1]:${NC} "
    read -r _reconfig_choice
    if [[ "${_reconfig_choice:-1}" == "2" ]]; then
        rclone config delete "$REMOTE_NAME"
        ok "Removed old '$REMOTE_NAME' remote."
    fi
fi

if ! _remote_exists; then
    printf "\n"
    printf "  ${BOLD}═══ Google Drive OAuth Setup ═══${NC}\n\n"
    printf "  ${YELLOW}IMPORTANT — READ BEFORE CONTINUING:${NC}\n\n"
    printf "  Since we're in a proot environment, the OAuth browser flow\n"
    printf "  may or may not work directly. Two approaches:\n\n"
    printf "  ${BOLD}Option A — Auto (if Chromium/Chrome works):${NC}\n"
    printf "    rclone config will try to open a browser inside proot.\n"
    printf "    If the VNC desktop is running and Chromium works, this\n"
    printf "    should open a Google sign-in page automatically.\n\n"
    printf "  ${BOLD}Option B — Manual / Remote auth:${NC}\n"
    printf "    During rclone config, when asked about auto config, say ${BOLD}N${NC}.\n"
    printf "    rclone will print a URL — open it in any browser (phone,\n"
    printf "    laptop, etc), sign into Google, paste the token back.\n\n"
    printf "  ${BOLD}How would you like to configure?${NC}\n"
    printf "    1) Interactive (rclone config wizard) — recommended\n"
    printf "    2) Quick auto-config (minimal prompts)\n"
    printf "  ${BOLD}Choice [1]:${NC} "
    read -r _config_choice

    case "${_config_choice:-1}" in
        2)
            msg "Running quick auto-config..."
            printf "\n"
            printf "  ${DIM}This creates a Google Drive remote named '${REMOTE_NAME}'.${NC}\n"
            printf "  ${DIM}You'll be asked to sign into your Google account.${NC}\n"
            printf "  ${DIM}When asked 'Use auto config?', answer based on your setup:${NC}\n"
            printf "  ${DIM}  - Y if VNC desktop + Chromium is running${NC}\n"
            printf "  ${DIM}  - N if running headless (paste token manually)${NC}\n\n"

            # Create the remote with type=drive, then trigger authorize
            rclone config create "$REMOTE_NAME" drive \
                --non-interactive 2>/dev/null || true

            # If non-interactive create worked but has no token, need to authorize
            if ! rclone lsd "${REMOTE_NAME}:" &>/dev/null 2>&1; then
                warn "Auto-config created the remote but it needs authorization."
                warn "Running 'rclone config reconnect ${REMOTE_NAME}:' ..."
                printf "\n"
                rclone config reconnect "${REMOTE_NAME}:" || {
                    err "Authorization failed. Try option 1 (interactive wizard) instead."
                    rclone config delete "$REMOTE_NAME" 2>/dev/null || true
                }
            fi
            ;;
        *)
            msg "Launching rclone config wizard..."
            printf "\n"
            printf "  ${BOLD}Follow these steps in the wizard:${NC}\n"
            printf "  ${DIM}  1. n  (New remote)${NC}\n"
            printf "  ${DIM}  2. Name: ${REMOTE_NAME}${NC}\n"
            printf "  ${DIM}  3. Storage type: drive  (or enter the number for Google Drive)${NC}\n"
            printf "  ${DIM}  4. client_id: (leave blank — press Enter)${NC}\n"
            printf "  ${DIM}  5. client_secret: (leave blank — press Enter)${NC}\n"
            printf "  ${DIM}  6. scope: 1  (Full access)${NC}\n"
            printf "  ${DIM}  7. root_folder_id: (leave blank)${NC}\n"
            printf "  ${DIM}  8. service_account_file: (leave blank)${NC}\n"
            printf "  ${DIM}  9. Edit advanced config? n${NC}\n"
            printf "  ${DIM} 10. Use auto config?${NC}\n"
            printf "  ${DIM}     - Y if desktop+browser available${NC}\n"
            printf "  ${DIM}     - N to get a URL for manual auth${NC}\n"
            printf "  ${DIM} 11. Configure as team drive? n${NC}\n"
            printf "  ${DIM} 12. y  (confirm)${NC}\n"
            printf "  ${DIM} 13. q  (quit config)${NC}\n\n"

            rclone config
            ;;
    esac

    if _remote_exists; then
        ok "Google Drive remote '$REMOTE_NAME' configured successfully!"
    else
        warn "Remote '$REMOTE_NAME' was not created."
        warn "You can re-run this script or run 'rclone config' manually."
    fi
fi

# ══════════════════════════════════════════════════════════════════════
#  4. Test connection
# ══════════════════════════════════════════════════════════════════════
if _remote_exists; then
    msg "Testing Google Drive connection..."
    if rclone lsd "${REMOTE_NAME}:" --max-depth 1 2>/dev/null | head -5; then
        ok "Google Drive is accessible! (showing up to 5 top-level folders)"
    else
        warn "Could not list Google Drive contents."
        warn "Check your internet connection or re-run rclone config."
    fi
fi

# ══════════════════════════════════════════════════════════════════════
#  5. Create sync wrapper scripts
# ══════════════════════════════════════════════════════════════════════
msg "Creating sync wrapper scripts in ~/.local/bin/ ..."

mkdir -p "$SYNC_SCRIPTS_DIR"

# ── gdrive-pull: Download from Drive → local ─────────────────────────
cat > "$SYNC_SCRIPTS_DIR/gdrive-pull" <<'PULL_SCRIPT'
#!/usr/bin/env bash
# gdrive-pull — Download Google Drive → ~/GoogleDrive
# Usage: gdrive-pull [subfolder]
#   gdrive-pull              Sync entire Drive
#   gdrive-pull Documents    Sync only Documents folder
set -uo pipefail
REMOTE="gdrive"
LOCAL="$HOME/GoogleDrive"

SUBFOLDER="${1:-}"
SRC="${REMOTE}:${SUBFOLDER}"
DST="${LOCAL}/${SUBFOLDER}"

mkdir -p "$DST"

echo "⬇ Pulling from Google Drive${SUBFOLDER:+/$SUBFOLDER} → ~/GoogleDrive${SUBFOLDER:+/$SUBFOLDER}"
echo "  (This may take a while for large folders...)"
echo ""

rclone sync "$SRC" "$DST" \
    --progress \
    --transfers 4 \
    --checkers 8 \
    --drive-chunk-size 64M \
    --fast-list \
    --exclude ".Trash-*/**" \
    --exclude ".~lock.*" \
    "$@"

echo ""
echo "✔ Pull complete."
PULL_SCRIPT
chmod +x "$SYNC_SCRIPTS_DIR/gdrive-pull"
ok "Created gdrive-pull"

# ── gdrive-push: Upload local → Drive  ──────────────────────────────
cat > "$SYNC_SCRIPTS_DIR/gdrive-push" <<'PUSH_SCRIPT'
#!/usr/bin/env bash
# gdrive-push — Upload ~/GoogleDrive → Google Drive
# Usage: gdrive-push [subfolder]
#   gdrive-push              Sync entire local to Drive
#   gdrive-push Documents    Sync only Documents folder
#
# WARNING: This syncs the remote to match local. Files on Drive
#          that don't exist locally WILL BE DELETED from Drive.
#          Use gdrive-copy for safe one-way upload.
set -uo pipefail
REMOTE="gdrive"
LOCAL="$HOME/GoogleDrive"

SUBFOLDER="${1:-}"
SRC="${LOCAL}/${SUBFOLDER}"
DST="${REMOTE}:${SUBFOLDER}"

if [[ ! -d "$SRC" ]]; then
    echo "✖ Source not found: $SRC"
    exit 1
fi

echo "⬆ Pushing ~/GoogleDrive${SUBFOLDER:+/$SUBFOLDER} → Google Drive${SUBFOLDER:+/$SUBFOLDER}"
echo "  ⚠ Files on Drive not present locally will be DELETED!"
echo ""
read -p "  Continue? [y/N] " confirm
if [[ "${confirm,,}" != "y" ]]; then
    echo "Cancelled."
    exit 0
fi

rclone sync "$SRC" "$DST" \
    --progress \
    --transfers 4 \
    --checkers 8 \
    --drive-chunk-size 64M \
    --fast-list \
    --exclude ".Trash-*/**" \
    --exclude ".~lock.*" \
    "$@"

echo ""
echo "✔ Push complete."
PUSH_SCRIPT
chmod +x "$SYNC_SCRIPTS_DIR/gdrive-push"
ok "Created gdrive-push"

# ── gdrive-copy: Safe one-way upload (no deletes) ───────────────────
cat > "$SYNC_SCRIPTS_DIR/gdrive-copy" <<'COPY_SCRIPT'
#!/usr/bin/env bash
# gdrive-copy — Copy local files to Google Drive (no deletes)
# Usage: gdrive-copy <source> [dest-on-drive]
#   gdrive-copy ~/Documents              Copy to Drive root
#   gdrive-copy ~/project Backups/proj   Copy to Drive:Backups/proj
set -uo pipefail
REMOTE="gdrive"

SRC="${1:-}"
DST="${2:-}"

if [[ -z "$SRC" ]]; then
    echo "Usage: gdrive-copy <source> [dest-on-drive]"
    echo "  gdrive-copy ~/Documents              → Drive root"
    echo "  gdrive-copy ~/project Backups/proj   → Drive:Backups/proj"
    exit 1
fi

echo "📋 Copying $SRC → ${REMOTE}:${DST:-/}"
rclone copy "$SRC" "${REMOTE}:${DST}" \
    --progress \
    --transfers 4 \
    --checkers 8 \
    --drive-chunk-size 64M \
    --fast-list \
    "$@"

echo ""
echo "✔ Copy complete."
COPY_SCRIPT
chmod +x "$SYNC_SCRIPTS_DIR/gdrive-copy"
ok "Created gdrive-copy"

# ── gdrive-bisync: Two-way sync ─────────────────────────────────────
cat > "$SYNC_SCRIPTS_DIR/gdrive-bisync" <<'BISYNC_SCRIPT'
#!/usr/bin/env bash
# gdrive-bisync — Two-way sync between local and Google Drive
# Usage: gdrive-bisync [--resync]
#   gdrive-bisync            Normal bidirectional sync
#   gdrive-bisync --resync   First-time / full resync (resolves conflicts)
set -uo pipefail
REMOTE="gdrive"
LOCAL="$HOME/GoogleDrive"

EXTRA_ARGS=()
if [[ "${1:-}" == "--resync" ]]; then
    echo "🔄 Running FULL bidirectional resync (first-time setup)..."
    EXTRA_ARGS+=(--resync)
    shift
else
    echo "🔄 Running bidirectional sync..."
fi

rclone bisync "$LOCAL" "${REMOTE}:" \
    --progress \
    --transfers 4 \
    --checkers 8 \
    --drive-chunk-size 64M \
    --fast-list \
    --exclude ".Trash-*/**" \
    --exclude ".~lock.*" \
    "${EXTRA_ARGS[@]}" \
    "$@"

echo ""
echo "✔ Bisync complete."
BISYNC_SCRIPT
chmod +x "$SYNC_SCRIPTS_DIR/gdrive-bisync"
ok "Created gdrive-bisync"

# ── gdrive-status: Show remote info ─────────────────────────────────
cat > "$SYNC_SCRIPTS_DIR/gdrive-status" <<'STATUS_SCRIPT'
#!/usr/bin/env bash
# gdrive-status — Show Google Drive connection info and usage
set -uo pipefail
REMOTE="gdrive"
LOCAL="$HOME/GoogleDrive"

echo "═══ Google Drive Status ═══"
echo ""

echo "Local directory: $LOCAL"
if [[ -d "$LOCAL" ]]; then
    LOCAL_COUNT=$(find "$LOCAL" -type f 2>/dev/null | wc -l)
    LOCAL_SIZE=$(du -sh "$LOCAL" 2>/dev/null | cut -f1)
    echo "  Files: $LOCAL_COUNT"
    echo "  Size:  $LOCAL_SIZE"
else
    echo "  (not found)"
fi
echo ""

echo "Remote: ${REMOTE}:"
if rclone about "${REMOTE}:" 2>/dev/null; then
    true
else
    echo "  ✖ Could not connect. Check 'rclone config' or internet."
fi
echo ""

echo "Top-level folders on Drive:"
rclone lsd "${REMOTE}:" --max-depth 1 2>/dev/null | awk '{print "  " $NF}' | head -20
STATUS_SCRIPT
chmod +x "$SYNC_SCRIPTS_DIR/gdrive-status"
ok "Created gdrive-status"

# Ensure ~/.local/bin is in PATH
if ! echo "$PATH" | grep -q "$HOME/.local/bin"; then
    for _rc in "$HOME/.bashrc" "$HOME/.profile"; do
        if [[ -f "$_rc" ]] && ! grep -q '\.local/bin' "$_rc"; then
            printf '\n# Added by gdrive-mount.sh\nexport PATH="$HOME/.local/bin:$PATH"\n' >> "$_rc"
            ok "Added ~/.local/bin to PATH in $(basename "$_rc")"
            break
        fi
    done
    export PATH="$HOME/.local/bin:$PATH"
fi

# ══════════════════════════════════════════════════════════════════════
#  6. Thunar bookmark for ~/GoogleDrive
# ══════════════════════════════════════════════════════════════════════
msg "Adding Thunar bookmark..."

BOOKMARKS_FILE="$HOME/.config/gtk-3.0/bookmarks"
BOOKMARK_ENTRY="file://$GDRIVE_DIR GoogleDrive"

mkdir -p "$(dirname "$BOOKMARKS_FILE")"

if [[ -f "$BOOKMARKS_FILE" ]] && grep -q "GoogleDrive" "$BOOKMARKS_FILE"; then
    skip "Thunar bookmark"
else
    echo "$BOOKMARK_ENTRY" >> "$BOOKMARKS_FILE"
    ok "Added GoogleDrive bookmark to Thunar sidebar"
fi

# ══════════════════════════════════════════════════════════════════════
#  7. Desktop shortcut
# ══════════════════════════════════════════════════════════════════════
msg "Creating desktop shortcut..."

DESKTOP_DIR="$HOME/Desktop"
mkdir -p "$DESKTOP_DIR"

cat > "$DESKTOP_DIR/google-drive.desktop" <<'DESKTOP'
[Desktop Entry]
Version=1.0
Type=Application
Name=Google Drive
Comment=Open Google Drive folder and show sync options
Icon=folder-remote
Terminal=true
Exec=bash -c '\
echo "═══ Google Drive ═══"; \
echo ""; \
echo "1) Open folder in Thunar"; \
echo "2) Pull from Drive (download)"; \
echo "3) Push to Drive (upload)"; \
echo "4) Bidirectional sync"; \
echo "5) Show Drive status"; \
echo "6) Open rclone config"; \
echo ""; \
read -p "Choice [1]: " c; \
case "${c:-1}" in \
  1) thunar ~/GoogleDrive ;; \
  2) gdrive-pull ;; \
  3) gdrive-push ;; \
  4) gdrive-bisync ;; \
  5) gdrive-status ;; \
  6) rclone config ;; \
  *) thunar ~/GoogleDrive ;; \
esac; \
echo ""; read -p "Press Enter to close..."'
Categories=Network;FileTransfer;
StartupNotify=false
DESKTOP
chmod +x "$DESKTOP_DIR/google-drive.desktop"
ok "Created Google Drive desktop shortcut"

# ══════════════════════════════════════════════════════════════════════
#  8. Auto-sync helper (optional cron-like via bashrc)
# ══════════════════════════════════════════════════════════════════════
msg "Auto-sync setup..."

printf "\n"
printf "  ${BOLD}Would you like to auto-pull from Drive on each login?${NC}\n"
printf "  ${DIM}This adds a gdrive-pull call to ~/.bashrc (runs once per session).${NC}\n"
printf "    1) No auto-sync (default) — use sync scripts manually\n"
printf "    2) Yes — auto-pull on login\n"
printf "  ${BOLD}Choice [1]:${NC} "
read -r _autosync_choice

if [[ "${_autosync_choice:-1}" == "2" ]]; then
    AUTOSYNC_MARKER="# gdrive-mount.sh auto-sync"
    if grep -q "$AUTOSYNC_MARKER" "$HOME/.bashrc" 2>/dev/null; then
        skip "Auto-sync already in .bashrc"
    else
        cat >> "$HOME/.bashrc" <<AUTOSYNC

$AUTOSYNC_MARKER
if command -v rclone &>/dev/null && rclone listremotes 2>/dev/null | grep -q "^${REMOTE_NAME}:\$"; then
    if [[ ! -f "/tmp/.gdrive-synced-\$\$" ]]; then
        echo "⬇ Auto-syncing Google Drive..."
        gdrive-pull 2>/dev/null &
        touch "/tmp/.gdrive-synced-\$\$"
    fi
fi
AUTOSYNC
        ok "Auto-pull on login enabled"
    fi
else
    ok "No auto-sync. Use gdrive-pull / gdrive-push manually."
fi

# ══════════════════════════════════════════════════════════════════════
#  9. Summary
# ══════════════════════════════════════════════════════════════════════

printf "\n"
printf "${BOLD}${GREEN}"
cat <<'DONE'
  ╔═══════════════════════════════════════════════════════════╗
  ║   Google Drive Setup Complete!                            ║
  ╚═══════════════════════════════════════════════════════════╝
DONE
printf "${NC}\n"

printf "  ${BOLD}Available commands:${NC}\n"
printf "    ${CYAN}gdrive-pull${NC}    Download Drive → ~/GoogleDrive\n"
printf "    ${CYAN}gdrive-push${NC}    Upload ~/GoogleDrive → Drive  ${DIM}(destructive sync)${NC}\n"
printf "    ${CYAN}gdrive-copy${NC}    Copy files to Drive  ${DIM}(safe, no deletes)${NC}\n"
printf "    ${CYAN}gdrive-bisync${NC}  Two-way sync  ${DIM}(first run: gdrive-bisync --resync)${NC}\n"
printf "    ${CYAN}gdrive-status${NC}  Show connection info & usage\n"
printf "\n"
printf "  ${BOLD}Subfolder sync:${NC}\n"
printf "    ${DIM}gdrive-pull Documents${NC}    ← sync only Documents\n"
printf "    ${DIM}gdrive-push Projects${NC}     ← push only Projects\n"
printf "\n"
printf "  ${BOLD}Quick reference:${NC}\n"
printf "    ${DIM}rclone ls gdrive:${NC}            ← list all files\n"
printf "    ${DIM}rclone lsd gdrive:${NC}           ← list directories\n"
printf "    ${DIM}rclone config${NC}                ← reconfigure remotes\n"
printf "    ${DIM}rclone config show${NC}           ← show current config\n"
printf "\n"
printf "  ${BOLD}Local directory:${NC} ~/GoogleDrive\n"
printf "  ${BOLD}Desktop shortcut:${NC} Google Drive (on desktop)\n"
printf "  ${BOLD}File manager:${NC} GoogleDrive bookmark in Thunar sidebar\n"
printf "\n"

if _remote_exists; then
    printf "  ${GREEN}✔ Remote '${REMOTE_NAME}' is configured and ready.${NC}\n"
    printf "  ${DIM}Run 'gdrive-pull' to download your files.${NC}\n"
else
    printf "  ${YELLOW}⚠ Remote not configured yet.${NC}\n"
    printf "  ${DIM}Run 'rclone config' to set up Google Drive access,${NC}\n"
    printf "  ${DIM}then run 'gdrive-pull' to download your files.${NC}\n"
fi
printf "\n"
