#!/usr/bin/env bash
# iris — remove everything and put the previous selections back.
#
#   ./uninstall.sh            remove all of it
#   ./uninstall.sh --lock-only
#                             only deactivate the iris lock screen (removes the
#                             systemd drop-in), leaving the themes installed
#
# The values restored are the ones install.sh recorded before it changed
# anything, not defaults: if the login screen was on something other than
# breeze, that is what comes back.
set -euo pipefail

THEME_ID="iris"
SHELL_ID="iris"
WALLPAPER_ID="org.lckt0.iris"
SDDM_DIR="/usr/share/sddm/themes/${THEME_ID}"
SHELL_DIR="/usr/share/plasma/shells/${SHELL_ID}"
SDDM_CONF="/etc/sddm.conf.d/kde_settings.conf"
WALLPAPER_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/plasma/wallpapers/${WALLPAPER_ID}"
SPLASH_ID="org.lckt0.iris"
SPLASH_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/plasma/look-and-feel/${SPLASH_ID}"
LOCK_CONF="${XDG_CONFIG_HOME:-$HOME/.config}/kscreenlockerrc"
DROPIN_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user/plasma-kwin_wayland.service.d"
DROPIN="${DROPIN_DIR}/iris.conf"
X11_DROPIN="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user/plasma-ksmserver.service.d/iris.conf"
STATE_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/iris-greeter"
STATE="${STATE_DIR}/previous.conf"

lock_only=0
for arg in "$@"; do
    case "$arg" in
        --lock-only) lock_only=1 ;;
        -h|--help)   sed -n '2,12p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *)           echo "unknown option: $arg" >&2; exit 2 ;;
    esac
done

say() { printf '  %s\n' "$*"; }

# The drop-in goes first, always: it is the one thing whose absence is the
# difference between a stock lock screen and a broken one.
echo "Lock screen activation"
removed_dropin=0
for f in "$DROPIN" "$X11_DROPIN"; do
    if [[ -f "$f" ]]; then
        rm -f "$f"
        rmdir "$(dirname "$f")" 2>/dev/null || true
        say "removed    $f"
        removed_dropin=1
    fi
done
if (( removed_dropin )); then
    systemctl --user daemon-reload
    say "reloaded   systemd user manager"
    say "the stock lock screen comes back at the next login"
else
    say "nothing to deactivate"
fi

if (( lock_only )); then
    echo
    echo "Left the themes installed. Run without --lock-only to remove them too."
    exit 0
fi

SDDM_THEME="breeze"
LOCK_PLUGIN="org.kde.image"
SPLASH_THEME="org.kde.breeze.desktop"
if [[ -f "$STATE" ]]; then
    # shellcheck disable=SC1090
    source "$STATE"
    say "restoring from $STATE"
else
    say "no record found; falling back to breeze / org.kde.image"
fi

echo "Login screen"
current="$(sudo kreadconfig6 --file "$SDDM_CONF" --group Theme --key Current 2>/dev/null || true)"
if [[ "$current" == "$THEME_ID" ]]; then
    sudo kwriteconfig6 --file "$SDDM_CONF" --group Theme --key Current "$SDDM_THEME"
    say "selected   $SDDM_THEME"
else
    say "left alone: selection is '$current', not $THEME_ID"
fi
if [[ -d "$SDDM_DIR" ]]; then
    sudo rm -rf "$SDDM_DIR"
    say "removed    $SDDM_DIR"
fi

echo "Lock screen"
current_plugin="$(kreadconfig6 --file kscreenlockerrc --group Greeter --key WallpaperPlugin 2>/dev/null || true)"
if [[ "$current_plugin" == "$WALLPAPER_ID" ]]; then
    kwriteconfig6 --file "$LOCK_CONF" --group Greeter --key WallpaperPlugin "$LOCK_PLUGIN"
    say "selected   $LOCK_PLUGIN"
else
    say "left alone: selection is '$current_plugin', not $WALLPAPER_ID"
fi
if [[ -d "$WALLPAPER_DIR" ]]; then
    rm -rf "$WALLPAPER_DIR"
    say "removed    $WALLPAPER_DIR"
fi
if [[ -d "$SHELL_DIR" ]]; then
    sudo rm -rf "$SHELL_DIR"
    say "removed    $SHELL_DIR"
fi

echo "Splash"
current_splash="$(kreadconfig6 --file ksplashrc --group KSplash --key Theme 2>/dev/null || true)"
if [[ "$current_splash" == "$SPLASH_ID" ]]; then
    kwriteconfig6 --file ksplashrc --group KSplash --key Theme "$SPLASH_THEME"
    say "selected   $SPLASH_THEME"
else
    say "left alone: selection is '$current_splash', not $SPLASH_ID"
fi
if [[ -d "$SPLASH_DIR" ]]; then
    rm -rf "$SPLASH_DIR"
    say "removed    $SPLASH_DIR"
fi

rm -f "$STATE"
rmdir "$STATE_DIR" 2>/dev/null || true

echo
echo "Done. The login screen changes at the next greeter, the lock screen at the next login."
