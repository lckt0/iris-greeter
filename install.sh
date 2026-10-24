#!/usr/bin/env bash
# iris — install the login screen, the lock screen, and the backdrop that
# matches them.
#
#   ./install.sh                  install everything, select the two themes
#   ./install.sh --activate-lock  ALSO switch the lock screen over (see below)
#   ./install.sh --sddm           login screen only
#   ./install.sh --lock           lock screen files only
#   ./install.sh --no-select      install the files, leave the selections
#   ./install.sh --no-splash      leave the Plasma start-up splash alone
#   ./install.sh --no-check       skip tools/check.sh (not advised)
#
# WHAT A PLAIN INSTALL TOUCHES, exhaustively:
#
#   /usr/share/sddm/themes/iris/                      new directory
#   /usr/share/plasma/shells/iris/                    new directory
#   ~/.local/share/plasma/wallpapers/org.lckt0.iris/  new directory
#   ~/.local/share/plasma/look-and-feel/org.lckt0.iris/   new directory
#   ~/.config/ksplashrc                 [KSplash] Theme
#   /etc/sddm.conf.d/kde_settings.conf  [Theme] Current
#   ~/.config/kscreenlockerrc           [Greeter] WallpaperPlugin  (+ caption)
#   ~/.local/share/iris-greeter/previous.conf         what to put back
#
# None of that changes how anything authenticates or how the session starts.
# The two config keys are selections, and uninstall.sh restores the values
# recorded before the first install rather than guessing a default.
#
# WHAT --activate-lock ADDS, and why it is a separate flag:
#
#   ~/.config/systemd/user/plasma-kwin_wayland.service.d/iris.conf
#       [Service]
#       Environment=PLASMA_DEFAULT_SHELL=iris
#
# On Wayland, KWin owns the lock screen, and the QML it loads comes from the
# Plasma shell package named by PLASMA_DEFAULT_SHELL. There is no config key
# for it: kscreenlocker_greet's --shell option is documented in its own help as
# "only in Testing mode", and the production path reads the environment
# variable only. So the single supported way to give the lock screen a
# different look is to change KWin's environment — which is a change to how
# the session starts, not to how it looks, and therefore gets its own
# deliberate step rather than riding along with a theme install.
#
# The drop-in is scoped to KWin alone. plasmashell is a separate unit and does
# not inherit it, which is what keeps the panel layout out of this: plasmashell
# derives its applet config filename from the shell package id, so moving it
# to another package would reset the desktop and panels.
#
# It takes effect at the next login: KWin cannot be restarted in place.
#
# IF THE LOCK SCREEN EVER FAILS TO DRAW: LockScreen.qml loads the interface
# through a Loader and falls back to a plain password prompt if it will not
# load. Should even that fail, switch to a TTY with Ctrl+Alt+F3, log in, and
#     rm ~/.config/systemd/user/plasma-kwin_wayland.service.d/iris.conf
#     loginctl unlock-session
set -euo pipefail

here="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

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
STATE_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/iris-greeter"
STATE="${STATE_DIR}/previous.conf"

CAPTION="${IRIS_CAPTION:-$(id -un)@$(cat /etc/hostname 2>/dev/null || uname -n)}"

do_sddm=1
do_lock=1
do_select=1
do_check=1
do_activate=0
do_splash=1
for arg in "$@"; do
    case "$arg" in
        --sddm)           do_lock=0 ;;
        --lock)           do_sddm=0 ;;
        --no-select)      do_select=0 ;;
        --no-check)       do_check=0 ;;
        --activate-lock)  do_activate=1 ;;
        --no-splash)      do_splash=0 ;;
        -h|--help)        sed -n '2,60p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *)                echo "unknown option: $arg" >&2; exit 2 ;;
    esac
done

say() { printf '  %s\n' "$*"; }

# Load the theme that is actually on disk with the actual greeter binary, on
# the offscreen platform so it cannot reach the display. Returns non-zero if
# the greeter refuses it.
#
# A theme the greeter cannot load leaves SDDM on its embedded fallback, which
# may draw nothing; better to find out before the next logout.
verify_installed_theme() {
    local dir="$1"
    [[ -x /usr/bin/sddm-greeter-qt6 ]] || { say "sddm-greeter-qt6 not found, skipping verification"; return 0; }

    local out log
    log="$(mktemp)"
    # A file, not a pipe: SIGTERM from timeout discards an unflushed pipe.
    QT_FORCE_STDERR_LOGGING=1 QT_QPA_PLATFORM=offscreen \
        timeout 12 /usr/bin/sddm-greeter-qt6 --test-mode --theme "$dir" \
        >"$log" 2>&1 || true
    out="$(cat "$log")"
    rm -f "$log"

    if printf '%s' "$out" | grep -qiE 'Fallback to embedded theme|Expected token|is not a type|module .* is not installed'; then
        say "THE GREETER REJECTED THE THEME:"
        printf '%s\n' "$out" | grep -iE 'Fallback to embedded|Expected token|is not a type|is not installed|\.qml:' | head -10 | sed 's/^/      /'
        return 1
    fi
    if ! printf '%s' "$out" | grep -q "Loading file.*Main.qml"; then
        say "THE GREETER NEVER LOADED Main.qml"
        printf '%s\n' "$out" | tail -10 | sed 's/^/      /'
        return 1
    fi
    say "verified   the greeter loaded the theme"
    return 0
}

if (( do_check )); then
    echo "Check"
    "$here/tools/check.sh" | sed 's/^/  /'
    echo
fi

# Record what is there now, before anything is selected. Written once: running
# install twice must not overwrite the original values with iris's own.
# Per key, not per file: an install that adds a new piece must record what
# that piece is replacing without overwriting what an earlier install already
# recorded — otherwise the second run saves iris's own values as "previous"
# and uninstall has nothing to go back to.
mkdir -p "$STATE_DIR"
record() {
    local key="$1" val="$2"
    [[ -f "$STATE" ]] || echo "# written by iris install.sh on $(date -Is)" > "$STATE"
    grep -q "^${key}=" "$STATE" && return 0
    echo "${key}=${val}" >> "$STATE"
    say "recorded   ${key}=${val}"
}

if (( do_sddm )); then
    record SDDM_THEME "$(sudo kreadconfig6 --file "$SDDM_CONF" --group Theme --key Current 2>/dev/null || echo breeze)"
fi
if (( do_lock )); then
    record LOCK_PLUGIN "$(kreadconfig6 --file kscreenlockerrc --group Greeter --key WallpaperPlugin 2>/dev/null || echo org.kde.image)"
fi
if (( do_splash )); then
    record SPLASH_THEME "$(kreadconfig6 --file ksplashrc --group KSplash --key Theme 2>/dev/null || echo org.kde.breeze.desktop)"
fi

if (( do_sddm )); then
    echo "Login screen"
    sudo install -d -m 0755 "$SDDM_DIR"
    # install(1) dereferences: the *.qml glob includes symlinks into shared/,
    # and what lands in the theme directory is a real file.
    sudo install -m 0644 "$here"/sddm/*.qml "$SDDM_DIR/"
    sudo install -m 0644 "$here"/sddm/metadata.desktop "$SDDM_DIR/"
    [[ -f "$here/sddm/preview.png" ]] && sudo install -m 0644 "$here/sddm/preview.png" "$SDDM_DIR/"

    sudo install -m 0644 "$here"/sddm/theme.conf "$SDDM_DIR/"
    sudo sed -i "s|^caption=.*|caption=${CAPTION}|" "$SDDM_DIR/theme.conf"
    say "installed  $SDDM_DIR"

    # Verify before selecting, never after: the selection is the point of no
    # return, because the next greeter to start is the one you have to log in
    # through.
    if ! verify_installed_theme "$SDDM_DIR"; then
        echo
        echo "ABORTED: the theme is installed but has NOT been selected." >&2
        echo "The login screen is untouched. Fix the errors above and re-run." >&2
        exit 1
    fi

    if (( do_select )); then
        sudo kwriteconfig6 --file "$SDDM_CONF" --group Theme --key Current "$THEME_ID"
        say "selected   $SDDM_CONF  [Theme] Current=$THEME_ID"
        say "takes effect at the next login screen"
    fi
fi

if (( do_lock )); then
    echo "Lock screen"

    # -- the shell package: the lock screen proper --------------------------
    sudo install -d -m 0755 "$SHELL_DIR/contents/lockscreen"
    sudo install -m 0644 "$here"/lockscreen/metadata.json "$SHELL_DIR/"
    sudo install -m 0644 "$here"/lockscreen/contents/lockscreen/*.qml "$SHELL_DIR/contents/lockscreen/"
    sudo install -m 0644 "$here"/lockscreen/contents/lockscreen/qmldir "$SHELL_DIR/contents/lockscreen/"
    sudo install -m 0644 "$here"/lockscreen/contents/lockscreen/config.xml "$SHELL_DIR/contents/lockscreen/"
    # The lock screen gets no configuration of its own, so the caption is
    # compiled in. Same string SDDM's theme.conf gets.
    sudo sed -i "s|^\( *readonly property string text: \).*|\1\"${CAPTION}\"|" \
        "$SHELL_DIR/contents/lockscreen/Caption.qml"
    say "installed  $SHELL_DIR"

    # -- the wallpaper: backdrop for the stock lock screen ------------------
    # Kept even though the shell package draws its own backdrop, so that the
    # screen still looks right if the shell package is ever deactivated.
    install -d -m 0755 "$WALLPAPER_DIR/contents/ui" "$WALLPAPER_DIR/contents/config"
    install -m 0644 "$here"/wallpaper/metadata.json "$WALLPAPER_DIR/"
    install -m 0644 "$here"/wallpaper/contents/ui/*.qml "$WALLPAPER_DIR/contents/ui/"
    install -m 0644 "$here"/wallpaper/contents/config/main.xml "$WALLPAPER_DIR/contents/config/"
    say "installed  $WALLPAPER_DIR"

    if (( do_select )); then
        kwriteconfig6 --file "$LOCK_CONF" --group Greeter --key WallpaperPlugin "$WALLPAPER_ID"
        kwriteconfig6 --file "$LOCK_CONF" \
            --group Greeter --group Wallpaper --group "$WALLPAPER_ID" --group General \
            --key Caption "$CAPTION"
        kwriteconfig6 --file "$LOCK_CONF" \
            --group Greeter --group Wallpaper --group "$WALLPAPER_ID" --group General \
            --key ShowCaption "true"
        say "selected   $LOCK_CONF  [Greeter] WallpaperPlugin=$WALLPAPER_ID"
    fi
fi

if (( do_splash )); then
    echo "Splash"
    install -d -m 0755 "$SPLASH_DIR/contents/splash"
    install -m 0644 "$here"/splash/metadata.json "$SPLASH_DIR/"
    install -m 0644 "$here"/splash/contents/splash/*.qml "$SPLASH_DIR/contents/splash/"
    sed -i "s|^\( *readonly property string text: \).*|\1\"${CAPTION}\"|" \
        "$SPLASH_DIR/contents/splash/Caption.qml"
    say "installed  $SPLASH_DIR"

    if (( do_select )); then
        # A look-and-feel package selected through ksplashrc changes the
        # start-up picture only. It is not applied as a global theme, so
        # colours, icons, and the desktop layout are untouched.
        kwriteconfig6 --file ksplashrc --group KSplash --key Theme "$SPLASH_ID"
        kwriteconfig6 --file ksplashrc --group KSplash --key Engine KSplashQML
        say "selected   ksplashrc [KSplash] Theme=$SPLASH_ID"
        say "takes effect at the next session start"
    fi
fi

if (( do_activate )); then
    echo "Lock screen activation  (this is the behavioural one)"
    if [[ "${XDG_SESSION_TYPE:-}" != "wayland" ]]; then
        say "NOTE: session type is '${XDG_SESSION_TYPE:-unknown}', not wayland."
        say "      On X11 the locker is spawned by ksmserver, so the drop-in"
        say "      would belong to plasma-ksmserver.service.d instead."
    fi
    mkdir -p "$DROPIN_DIR"
    cat > "$DROPIN" <<DROPIN_EOF
# Installed by iris (${here}). Remove this file to put the stock lock
# screen back; it is the only thing that activates the iris one.
[Service]
Environment=PLASMA_DEFAULT_SHELL=${SHELL_ID}
DROPIN_EOF
    say "wrote      $DROPIN"
    systemctl --user daemon-reload
    say "reloaded   systemd user manager"
    say "TAKES EFFECT AT THE NEXT LOGIN — KWin cannot be restarted in place."
fi

echo
echo "Caption: $CAPTION"
echo
if (( do_lock )) && (( ! do_activate )); then
    echo "The lock screen files are installed but NOT active yet."
    echo "To switch the lock screen over:"
    echo "  $here/install.sh --activate-lock --no-check"
    echo
fi
echo "Preview the login screen without logging out:"
echo "  sddm-greeter-qt6 --test-mode --theme $SDDM_DIR"
echo "Preview the lock screen without logging out (this really locks the screen):"
echo "  kscreenlocker_greet --testing --shell $SHELL_ID"
echo "Undo everything:"
echo "  $here/uninstall.sh"
