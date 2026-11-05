#!/usr/bin/env bash
# Safe per-user installer for Wall-Seperator. GPL-3.0-only; see repository LICENSE.
set -Eeuo pipefail

usage() {
    cat <<'EOF'
Wall-Seperator installer

Usage:
  ./install.sh                    Install only the plugin and metadata helper
  ./install.sh --with-shell-overlay
                                  Also install the optional >wallpaper integration
  ./install.sh --update           Back up and update an existing Wall-Seperator install
  ./install.sh --update --with-shell-overlay
                                  Back up/update the plugin and install the shell overlay
  ./install.sh --help

The installer never silently replaces an existing plugin or helper. Updates are backed up under
~/.local/state. The optional shell overlay is interactive and does not edit shell.json.
EOF
}

WITH_OVERLAY=0
UPDATE=0
while (($#)); do
    case "$1" in
        --with-shell-overlay) WITH_OVERLAY=1 ;;
        --update) UPDATE=1 ;;
        --help|-h) usage; exit 0 ;;
        *) printf 'Unknown option: %s\n\n' "$1" >&2; usage >&2; exit 2 ;;
    esac
    shift
done

PLUGIN_SOURCE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
OVERLAY_SOURCE="$PLUGIN_SOURCE/user-config"
DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
PLUGIN_DEST="$DATA_HOME/caelestia/plugins/xlonely-wallseperator"
HELPER_SOURCE="$PLUGIN_SOURCE/tools/wall-seperator-metadata"
HELPER_DEST="$HOME/.local/bin/wall-seperator-metadata"
USER_SHELL="$CONFIG_HOME/quickshell/caelestia"
BACKUP_ROOT="$STATE_HOME/caelestia/wall-seperator/backups"
BACKUP_DIR=""

die() {
    printf 'Wall-Seperator installer: %s\n' "$1" >&2
    exit 1
}

[[ -f "$PLUGIN_SOURCE/manifest.json" && -x "$HELPER_SOURCE" ]] || die "Run this script from the Wall-Seperator plugin directory."

PLUGIN_ALREADY=0
PLUGIN_UPDATE=0
if [[ -L "$PLUGIN_DEST" ]]; then
    die "${PLUGIN_DEST} is a symlink. It was left untouched."
elif [[ -e "$PLUGIN_DEST" ]]; then
    if [[ -d "$PLUGIN_DEST" ]] && diff -qr "$PLUGIN_SOURCE" "$PLUGIN_DEST" >/dev/null 2>&1; then
        PLUGIN_ALREADY=1
    elif ((UPDATE)) && [[ -d "$PLUGIN_DEST" ]]; then
        if find "$PLUGIN_DEST" -type l -print -quit | grep -q .; then
            die "${PLUGIN_DEST} contains symlinks. It was left untouched; remove or resolve them before updating."
        fi
        python3 - "$PLUGIN_DEST/manifest.json" <<'PY' || die "${PLUGIN_DEST} is not the Wall-Seperator plugin; it was left untouched."
import json
import sys
try:
    manifest = json.load(open(sys.argv[1], encoding="utf-8"))
except (OSError, json.JSONDecodeError):
    raise SystemExit(1)
raise SystemExit(0 if manifest.get("name") == "wallseperator" and manifest.get("author", "").lower() == "xlonely" else 1)
PY
        PLUGIN_UPDATE=1
    else
        die "${PLUGIN_DEST} already exists and differs from this plugin. It was left untouched; rerun with --update to back it up and update it."
    fi
fi

HELPER_ALREADY=0
HELPER_UPDATE=0
if [[ -L "$HELPER_DEST" ]]; then
    die "${HELPER_DEST} is a symlink. It was left untouched."
elif [[ -e "$HELPER_DEST" ]]; then
    if [[ -f "$HELPER_DEST" ]] && cmp -s "$HELPER_SOURCE" "$HELPER_DEST"; then
        HELPER_ALREADY=1
    elif ((UPDATE)) && [[ -f "$HELPER_DEST" ]]; then
        HELPER_UPDATE=1
    else
        die "${HELPER_DEST} already exists and differs from this helper. It was left untouched; rerun with --update to back it up and update it."
    fi
fi

SHELL_BASE=""
SHELL_WILL_BE_CREATED=0
OVERLAY_REPLACEMENTS=()
OVERLAY_FILES=(
    services/Wallpapers.qml
    modules/launcher/Content.qml
    modules/launcher/WallpaperList.qml
    modules/launcher/ColorFilterBar.qml
    modules/launcher/items/WallpaperItem.qml
)

if ((WITH_OVERLAY)); then
    [[ -t 0 ]] || die "--with-shell-overlay requires an interactive terminal so you can review and approve the shell-file changes."
    [[ -d "$OVERLAY_SOURCE" ]] || die "The bundled user-config overlay is missing."

    if [[ -L "$USER_SHELL" ]]; then
        die "$USER_SHELL is a symlink. The overlay was not installed; use a real user config directory so no system files can be changed."
    fi

    if [[ ! -d "$USER_SHELL" ]]; then
        IFS=: read -r -a CONFIG_DIRS <<< "${XDG_CONFIG_DIRS:-/etc/xdg}"
        for config_base in "${CONFIG_DIRS[@]}" /etc/xdg; do
            candidate="$config_base/quickshell/caelestia"
            if [[ -f "$candidate/shell.qml" ]]; then
                SHELL_BASE="$candidate"
                break
            fi
        done
        [[ -n "$SHELL_BASE" ]] || die "Could not find the installed Caelestia shell config. Create $USER_SHELL from your shell package's config, then rerun this installer."
        [[ ! -L "$SHELL_BASE" ]] || die "The installed shell config is a symlink. No files were changed."
        for dir in modules modules/launcher modules/launcher/items services; do
            [[ ! -L "$SHELL_BASE/$dir" ]] || die "$SHELL_BASE/$dir is a symlink. No files were changed."
        done
        for rel in "${OVERLAY_FILES[@]}"; do
            [[ ! -L "$SHELL_BASE/$rel" ]] || die "$SHELL_BASE/$rel is a symlink. No files were changed."
        done
        SHELL_WILL_BE_CREATED=1
    else
        [[ -f "$USER_SHELL/shell.qml" ]] || die "$USER_SHELL exists but has no shell.qml. It was left untouched; complete your user shell config before installing the overlay."
        for dir in modules modules/launcher modules/launcher/items services; do
            [[ ! -L "$USER_SHELL/$dir" ]] || die "$USER_SHELL/$dir is a symlink. No files were changed. Make a local copy of that directory before installing the overlay."
        done
    fi

    for rel in "${OVERLAY_FILES[@]}"; do
        src="$OVERLAY_SOURCE/$rel"
        [[ -f "$src" ]] || die "Missing overlay file: $src"
        dest="$USER_SHELL/$rel"
        [[ ! -L "$dest" ]] || die "$dest is a symlink. No files were changed. Make a local copy before installing the overlay."
        if [[ -e "$dest" ]] && ! cmp -s "$src" "$dest"; then
            OVERLAY_REPLACEMENTS+=("$rel")
        fi
    done

    printf 'Optional shell overlay will replace these files in %s:\n' "$USER_SHELL"
    if ((${#OVERLAY_REPLACEMENTS[@]})); then
        printf '  - %s\n' "${OVERLAY_REPLACEMENTS[@]}"
        printf 'Changed files will be backed up under %s.\n' "$BACKUP_ROOT"
    else
        printf '  - no existing files differ\n'
    fi
    if ((SHELL_WILL_BE_CREATED)); then
        printf 'An update-linked user overlay will be created from %s; unchanged shell files will stay linked to the installed config.\n' "$SHELL_BASE"
    fi
    printf 'The installer will not edit ~/.config/caelestia/shell.json or restart the running shell.\n'
    read -r -p 'Install this shell overlay? [y/N] ' answer
    [[ "$answer" =~ ^[Yy]([Ee][Ss])?$ ]] || die "Cancelled; no files were changed."
fi

make_backup_dir() {
    if [[ -z "$BACKUP_DIR" ]]; then
        mkdir -p "$BACKUP_ROOT"
        BACKUP_DIR="$(mktemp -d "$BACKUP_ROOT/$(date '+%Y%m%d-%H%M%S')-XXXXXX")"
    fi
}

if ((PLUGIN_UPDATE)); then
    make_backup_dir
    cp -a "$PLUGIN_DEST" "$BACKUP_DIR/plugin"
    printf 'Backed up existing plugin to: %s/plugin\n' "$BACKUP_DIR"
fi
if ((HELPER_UPDATE)); then
    make_backup_dir
    mkdir -p "$BACKUP_DIR/helper"
    cp -a "$HELPER_DEST" "$BACKUP_DIR/helper/wall-seperator-metadata"
    printf 'Backed up existing helper to: %s/helper/wall-seperator-metadata\n' "$BACKUP_DIR"
fi

if ((PLUGIN_ALREADY)); then
    printf 'Plugin already matches the repository; leaving it unchanged.\n'
elif ((PLUGIN_UPDATE)); then
    cp -a "$PLUGIN_SOURCE/." "$PLUGIN_DEST/"
    printf 'Updated plugin in place: %s\n' "$PLUGIN_DEST"
else
    mkdir -p "$(dirname -- "$PLUGIN_DEST")"
    cp -a "$PLUGIN_SOURCE" "$PLUGIN_DEST"
    printf 'Installed plugin: %s\n' "$PLUGIN_DEST"
fi

if ((HELPER_ALREADY)); then
    printf 'Metadata helper already matches the repository; leaving it unchanged.\n'
elif ((HELPER_UPDATE)); then
    install -m 755 "$HELPER_SOURCE" "$HELPER_DEST"
    printf 'Updated metadata helper: %s\n' "$HELPER_DEST"
else
    install -D -m 755 "$HELPER_SOURCE" "$HELPER_DEST"
    printf 'Installed metadata helper: %s\n' "$HELPER_DEST"
fi

if ((WITH_OVERLAY)); then
    if ((SHELL_WILL_BE_CREATED)); then
        mkdir -p "$(dirname -- "$USER_SHELL")"
        mkdir -p "$USER_SHELL/modules/launcher/items" "$USER_SHELL/services"

        for entry in "$SHELL_BASE"/*; do
            [[ -e "$entry" ]] || continue
            name="${entry##*/}"
            case "$name" in
                modules|services) continue ;;
            esac
            ln -s "$entry" "$USER_SHELL/$name"
        done

        for entry in "$SHELL_BASE/modules"/*; do
            [[ -e "$entry" ]] || continue
            name="${entry##*/}"
            [[ "$name" == launcher ]] && continue
            ln -s "$entry" "$USER_SHELL/modules/$name"
        done

        for entry in "$SHELL_BASE/modules/launcher"/*; do
            [[ -e "$entry" ]] || continue
            name="${entry##*/}"
            case "$name" in
                Content.qml|WallpaperList.qml|ColorFilterBar.qml|items) continue ;;
            esac
            ln -s "$entry" "$USER_SHELL/modules/launcher/$name"
        done

        for entry in "$SHELL_BASE/modules/launcher/items"/*; do
            [[ -e "$entry" ]] || continue
            name="${entry##*/}"
            [[ "$name" == WallpaperItem.qml ]] && continue
            ln -s "$entry" "$USER_SHELL/modules/launcher/items/$name"
        done

        for entry in "$SHELL_BASE/services"/*; do
            [[ -e "$entry" ]] || continue
            name="${entry##*/}"
            [[ "$name" == Wallpapers.qml ]] && continue
            ln -s "$entry" "$USER_SHELL/services/$name"
        done
    fi

    if ((${#OVERLAY_REPLACEMENTS[@]})); then
        make_backup_dir
        for rel in "${OVERLAY_REPLACEMENTS[@]}"; do
            backup_file="$BACKUP_DIR/user-config/$rel"
            mkdir -p "$(dirname -- "$backup_file")"
            cp -a "$USER_SHELL/$rel" "$backup_file"
        done
        printf 'Backed up replaced shell files under: %s/user-config\n' "$BACKUP_DIR"
    fi

    for rel in "${OVERLAY_FILES[@]}"; do
        dest="$USER_SHELL/$rel"
        mkdir -p "$(dirname -- "$dest")"
        if [[ ! -e "$dest" ]] || ! cmp -s "$OVERLAY_SOURCE/$rel" "$dest"; then
            install -m 644 "$OVERLAY_SOURCE/$rel" "$dest"
        fi
    done
    printf 'Installed optional launcher integration in: %s\n' "$USER_SHELL"
fi

printf '\nNext steps:\n'
printf '  1. Enable Wall-Seperator in Nexus → Plugins.\n'
printf '  2. Install ffmpeg and python-pillow if video thumbnails are needed (Arch: sudo pacman -S ffmpeg python-pillow).\n'
printf '  3. Reload Caelestia with: caelestia shell -r\n'
if ((WITH_OVERLAY)); then
    printf '  4. Optional: merge "wallpaperTransition": "Crossfade" into the existing background object in %s/shell.json.\n' "$CONFIG_HOME/caelestia"
    printf '  5. The five bundled QML overrides are version-specific and may need updating after Caelestia changes.\n'
fi
