#!/usr/bin/env bash
# Safe per-user uninstaller for Wall-Seperator. GPL-3.0-only; see repository LICENSE.
set -Eeuo pipefail

usage() {
    cat <<'EOF'
Wall-Seperator uninstaller

Usage:
  ./uninstall.sh                         Remove plugin and helper only
  ./uninstall.sh --with-shell-overlay    Also restore/remove the optional launcher overlay
  ./uninstall.sh --dry-run               Show planned actions without changing files
  ./uninstall.sh --help

The uninstaller makes a safety copy of the plugin and helper before removing them. Shell overlay
files are restored from the installer's backups when available; otherwise only unchanged bundled
files are reverted. It never edits shell.json, system config files, or plugins.json.
EOF
}

WITH_OVERLAY=0
DRY_RUN=0
while (($#)); do
    case "$1" in
        --with-shell-overlay) WITH_OVERLAY=1 ;;
        --dry-run) DRY_RUN=1 ;;
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
HELPER_DEST="$HOME/.local/bin/wall-seperator-metadata"
USER_SHELL="$CONFIG_HOME/quickshell/caelestia"
BACKUP_ROOT="$STATE_HOME/caelestia/wall-seperator/backups"
OVERLAY_FILES=(
    services/Wallpapers.qml
    modules/launcher/Content.qml
    modules/launcher/WallpaperList.qml
    modules/launcher/ColorFilterBar.qml
    modules/launcher/items/WallpaperItem.qml
)

die() {
    printf 'Wall-Seperator uninstaller: %s\n' "$1" >&2
    exit 1
}

UNINSTALL_BACKUP=""
make_backup_dir() {
    if [[ -z "$UNINSTALL_BACKUP" ]]; then
        mkdir -p "$BACKUP_ROOT"
        UNINSTALL_BACKUP="$(mktemp -d "$BACKUP_ROOT/uninstall-$(date '+%Y%m%d-%H%M%S')-XXXXXX")"
    fi
}

find_original_backup() {
    local rel="$1" dir candidate
    local -a dirs=()
    [[ -d "$BACKUP_ROOT" ]] || return 1
    mapfile -t dirs < <(find "$BACKUP_ROOT" -mindepth 1 -maxdepth 1 -type d ! -name 'uninstall-*' -print | sort)
    for dir in "${dirs[@]}"; do
        for candidate in "$dir/user-config/$rel" "$dir/$rel"; do
            if [[ -f "$candidate" && ! -L "$candidate" ]]; then
                printf '%s\n' "$candidate"
                return 0
            fi
        done
    done
    return 1
}

SHELL_BASE=""
OVERLAY_MARKER="$USER_SHELL/.wall-seperator-overlay"
if [[ -f "$OVERLAY_MARKER" ]]; then
    IFS= read -r SHELL_BASE < "$OVERLAY_MARKER" || true
fi
if [[ -z "$SHELL_BASE" && -L "$USER_SHELL/shell.qml" ]]; then
    shell_target="$(readlink -f -- "$USER_SHELL/shell.qml" 2>/dev/null || true)"
    [[ -n "$shell_target" ]] && SHELL_BASE="$(dirname -- "$shell_target")"
fi
if [[ -z "$SHELL_BASE" ]]; then
    IFS=: read -r -a CONFIG_DIRS <<< "${XDG_CONFIG_DIRS:-/etc/xdg}"
    for config_base in "${CONFIG_DIRS[@]}" /etc/xdg; do
        candidate="$config_base/quickshell/caelestia"
        if [[ -f "$candidate/shell.qml" ]]; then
            SHELL_BASE="$candidate"
            break
        fi
    done
fi

PLUGIN_PRESENT=0
HELPER_PRESENT=0
if [[ -L "$PLUGIN_DEST" ]]; then
    die "$PLUGIN_DEST is a symlink. It was left untouched."
elif [[ -e "$PLUGIN_DEST" ]]; then
    [[ -d "$PLUGIN_DEST" ]] || die "$PLUGIN_DEST is not a directory. It was left untouched."
    PLUGIN_PRESENT=1
fi
if [[ -L "$HELPER_DEST" ]]; then
    die "$HELPER_DEST is a symlink. It was left untouched."
elif [[ -e "$HELPER_DEST" ]]; then
    [[ -f "$HELPER_DEST" ]] || die "$HELPER_DEST is not a regular file. It was left untouched."
    HELPER_PRESENT=1
fi

declare -A OVERLAY_ACTION=()
if ((WITH_OVERLAY)) && [[ -L "$USER_SHELL" ]]; then
    die "$USER_SHELL is a symlink. The shell overlay was left untouched."
fi
if ((WITH_OVERLAY)) && [[ -d "$USER_SHELL" ]]; then
    for rel in "${OVERLAY_FILES[@]}"; do
        dest="$USER_SHELL/$rel"
        original="$(find_original_backup "$rel" || true)"
        if [[ ! -e "$dest" && ! -L "$dest" ]]; then
            if [[ -n "$original" ]]; then
                OVERLAY_ACTION["$rel"]="restore backup"
            elif [[ -f "$OVERLAY_MARKER" && -n "$SHELL_BASE" && -f "$SHELL_BASE/$rel" ]]; then
                OVERLAY_ACTION["$rel"]="restore shell package version"
            fi
            continue
        fi

        parent="$USER_SHELL"
        safe_parent=1
        IFS=/ read -r -a pieces <<< "$(dirname -- "$rel")"
        for piece in "${pieces[@]}"; do
            parent="$parent/$piece"
            if [[ -L "$parent" ]]; then
                safe_parent=0
                break
            fi
        done
        if ((!safe_parent)); then
            OVERLAY_ACTION["$rel"]="preserve (parent is a symlink)"
            continue
        fi
        if [[ -L "$dest" ]]; then
            OVERLAY_ACTION["$rel"]="preserve (file is a symlink)"
        elif [[ -f "$dest" ]]; then
            if [[ -n "$original" ]]; then
                OVERLAY_ACTION["$rel"]="restore backup"
            elif [[ -f "$OVERLAY_SOURCE/$rel" ]] && cmp -s "$dest" "$OVERLAY_SOURCE/$rel"; then
                if [[ -n "$SHELL_BASE" && -f "$SHELL_BASE/$rel" ]]; then
                    OVERLAY_ACTION["$rel"]="restore shell package version"
                else
                    OVERLAY_ACTION["$rel"]="remove bundled file"
                fi
            else
                OVERLAY_ACTION["$rel"]="preserve (custom or no original available)"
            fi
        else
            OVERLAY_ACTION["$rel"]="preserve (not a regular file)"
        fi
    done
fi

printf 'Wall-Seperator uninstall plan:\n'
if ((PLUGIN_PRESENT)); then printf '  - remove plugin after saving a safety copy\n'; else printf '  - plugin not found\n'; fi
if ((HELPER_PRESENT)); then printf '  - remove metadata helper after saving a safety copy\n'; else printf '  - metadata helper not found\n'; fi
if ((WITH_OVERLAY)); then
    if [[ -d "$USER_SHELL" ]]; then
        for rel in "${OVERLAY_FILES[@]}"; do
            [[ -n "${OVERLAY_ACTION[$rel]:-}" ]] && printf '  - %s: %s\n' "$rel" "${OVERLAY_ACTION[$rel]}"
        done
        if [[ -f "$OVERLAY_MARKER" ]]; then
            printf '  - remove the install-created user overlay links if their directories are otherwise empty\n'
        else
            printf '  - preserve the existing user shell config structure\n'
        fi
    else
        printf '  - user shell overlay not found\n'
    fi
else
    printf '  - user shell overlay will be left in place (pass --with-shell-overlay to reverse it)\n'
fi
printf '  - shell.json and plugins.json will not be edited\n'

if ((DRY_RUN)); then
    exit 0
fi
[[ -t 0 ]] || die "An interactive terminal is required to confirm removal. Use --dry-run to inspect the plan."
read -r -p 'Proceed? A safety copy will be kept under ~/.local/state. [y/N] ' answer
[[ "$answer" =~ ^[Yy]([Ee][Ss])?$ ]] || die "Cancelled; no files were changed."

if ((PLUGIN_PRESENT)); then
    make_backup_dir
    cp -a "$PLUGIN_DEST" "$UNINSTALL_BACKUP/plugin"
    rm -r -- "$PLUGIN_DEST"
    printf 'Removed plugin; safety copy: %s/plugin\n' "$UNINSTALL_BACKUP"
fi
if ((HELPER_PRESENT)); then
    make_backup_dir
    mkdir -p "$UNINSTALL_BACKUP/helper"
    cp -a "$HELPER_DEST" "$UNINSTALL_BACKUP/helper/wall-seperator-metadata"
    rm -- "$HELPER_DEST"
    printf 'Removed helper; safety copy: %s/helper/wall-seperator-metadata\n' "$UNINSTALL_BACKUP"
fi

if ((WITH_OVERLAY)) && [[ -d "$USER_SHELL" ]]; then
    for rel in "${OVERLAY_FILES[@]}"; do
        action="${OVERLAY_ACTION[$rel]:-}"
        [[ -n "$action" ]] || continue
        dest="$USER_SHELL/$rel"
        case "$action" in
            "restore backup")
                original="$(find_original_backup "$rel")"
                make_backup_dir
                safety_file="$UNINSTALL_BACKUP/current-user-config/$rel"
                mkdir -p "$(dirname -- "$safety_file")"
                [[ ! -e "$dest" && ! -L "$dest" ]] || cp -a "$dest" "$safety_file"
                mkdir -p "$(dirname -- "$dest")"
                cp -a "$original" "$dest"
                printf 'Restored %s from its pre-install backup. Current copy saved under %s.\n' "$rel" "$UNINSTALL_BACKUP/current-user-config"
                ;;
            "restore shell package version")
                make_backup_dir
                safety_file="$UNINSTALL_BACKUP/current-user-config/$rel"
                mkdir -p "$(dirname -- "$safety_file")"
                cp -a "$dest" "$safety_file"
                rm -- "$dest"
                ln -s "$SHELL_BASE/$rel" "$dest"
                printf 'Restored %s to the installed shell version. Previous copy saved under %s.\n' "$rel" "$UNINSTALL_BACKUP/current-user-config"
                ;;
            "remove bundled file")
                make_backup_dir
                safety_file="$UNINSTALL_BACKUP/current-user-config/$rel"
                mkdir -p "$(dirname -- "$safety_file")"
                cp -a "$dest" "$safety_file"
                rm -- "$dest"
                printf 'Removed bundled-only file %s; previous copy saved under %s.\n' "$rel" "$UNINSTALL_BACKUP/current-user-config"
                ;;
            *)
                printf 'Preserved %s unchanged (%s).\n' "$rel" "$action"
                ;;
        esac
    done

    if [[ -f "$OVERLAY_MARKER" && -n "$SHELL_BASE" ]]; then
        # The installer-created overlay contains only symlinks to the base shell and its local
        # wallpaper overrides. Remove only links whose targets exactly match that base.
        remove_matching_link() {
            local path="$1" target="$2"
            if [[ -L "$path" && "$(readlink -- "$path")" == "$target" ]]; then
                rm -- "$path"
            fi
        }

        overlay_tree_is_installer_owned() {
            local entry name
            for entry in "$USER_SHELL"/*; do
                [[ -e "$entry" || -L "$entry" ]] || continue
                name="${entry##*/}"
                case "$name" in
                    modules|services) [[ -d "$entry" && ! -L "$entry" ]] || return 1 ;;
                    *) [[ -L "$entry" && "$(readlink -- "$entry")" == "$SHELL_BASE/$name" ]] || return 1 ;;
                esac
            done
            for entry in "$USER_SHELL/modules"/*; do
                [[ -e "$entry" || -L "$entry" ]] || continue
                name="${entry##*/}"
                if [[ "$name" == launcher ]]; then
                    [[ -d "$entry" && ! -L "$entry" ]] || return 1
                else
                    [[ -L "$entry" && "$(readlink -- "$entry")" == "$SHELL_BASE/modules/$name" ]] || return 1
                fi
            done
            for entry in "$USER_SHELL/modules/launcher"/*; do
                [[ -e "$entry" || -L "$entry" ]] || continue
                name="${entry##*/}"
                if [[ "$name" == items ]]; then
                    [[ -d "$entry" && ! -L "$entry" ]] || return 1
                else
                    [[ -L "$entry" && "$(readlink -- "$entry")" == "$SHELL_BASE/modules/launcher/$name" ]] || return 1
                fi
            done
            for entry in "$USER_SHELL/modules/launcher/items"/*; do
                [[ -e "$entry" || -L "$entry" ]] || continue
                name="${entry##*/}"
                [[ -L "$entry" && "$(readlink -- "$entry")" == "$SHELL_BASE/modules/launcher/items/$name" ]] || return 1
            done
            for entry in "$USER_SHELL/services"/*; do
                [[ -e "$entry" || -L "$entry" ]] || continue
                name="${entry##*/}"
                [[ -L "$entry" && "$(readlink -- "$entry")" == "$SHELL_BASE/services/$name" ]] || return 1
            done
            return 0
        }

        if overlay_tree_is_installer_owned; then
        for entry in "$USER_SHELL"/*; do
            [[ -e "$entry" || -L "$entry" ]] || continue
            name="${entry##*/}"
            case "$name" in modules|services|.wall-seperator-overlay) continue ;; esac
            remove_matching_link "$entry" "$SHELL_BASE/$name"
        done
        for entry in "$USER_SHELL/modules"/*; do
            [[ -e "$entry" || -L "$entry" ]] || continue
            name="${entry##*/}"
            [[ "$name" == launcher ]] && continue
            remove_matching_link "$entry" "$SHELL_BASE/modules/$name"
        done
        for entry in "$USER_SHELL/modules/launcher"/*; do
            [[ -e "$entry" || -L "$entry" ]] || continue
            name="${entry##*/}"
            [[ "$name" == items ]] && continue
            remove_matching_link "$entry" "$SHELL_BASE/modules/launcher/$name"
        done
        for entry in "$USER_SHELL/modules/launcher/items"/*; do
            [[ -e "$entry" || -L "$entry" ]] || continue
            name="${entry##*/}"
            remove_matching_link "$entry" "$SHELL_BASE/modules/launcher/items/$name"
        done
        for entry in "$USER_SHELL/services"/*; do
            [[ -e "$entry" || -L "$entry" ]] || continue
            name="${entry##*/}"
            remove_matching_link "$entry" "$SHELL_BASE/services/$name"
        done

        rmdir "$USER_SHELL/modules/launcher/items" 2>/dev/null || true
        rmdir "$USER_SHELL/modules/launcher" 2>/dev/null || true
        rmdir "$USER_SHELL/modules" 2>/dev/null || true
        rmdir "$USER_SHELL/services" 2>/dev/null || true
        rm -- "$OVERLAY_MARKER"
        rmdir "$USER_SHELL" 2>/dev/null || {
            # Keep the marker so a later run can identify and clean only its own remaining links.
            printf '%s\n' "$SHELL_BASE" > "$OVERLAY_MARKER"
            printf 'Kept %s because it contains other user files.\n' "$USER_SHELL"
        }
        else
            printf 'Kept the overlay directory because it contains files or links not created by this installer.\n'
        fi
    fi
fi

printf '\nUninstall complete. If Wall-Seperator is still enabled, disable it in Nexus → Plugins.\n'
printf 'Reload Caelestia with: caelestia shell -r\n'
if [[ -n "$UNINSTALL_BACKUP" ]]; then
    printf 'Safety copies are under: %s\n' "$UNINSTALL_BACKUP"
fi
