#!/usr/bin/env bash
# iris — verify the theme before it is allowed anywhere near a login screen.
#
# Three passes, cheapest first:
#
#   1. stage   — copy both packages into a scratch directory exactly as
#                install.sh writes them: every symlink dereferenced, so what
#                is checked is what is installed and not a source tree that
#                only resolves because of where its files happen to sit;
#   2. lint    — qmllint over the staged files;
#   3. run     — build a mock of the SDDM context objects, drive a whole
#                pam_howdy conversation through it offscreen, and fail on any
#                QML error. This is the pass that earns its keep: a binding to
#                a read-only property and an attached property resolved in the
#                wrong scope both lint clean and both break the greeter.
#
# Nothing here touches the running session, opens a window, or needs root.
set -euo pipefail

here="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

qmllint="/usr/lib/qt6/bin/qmllint"
[[ -x "$qmllint" ]] || { echo "qmllint not found: $qmllint" >&2; exit 1; }

fail=0
note() { printf '  %s\n' "$*"; }

# ---- 1. stage ---------------------------------------------------------------
echo "stage"
mkdir -p "$work/sddm" "$work/wallpaper/contents/ui" "$work/wallpaper/contents/config"
cp -L "$here"/sddm/*.qml "$here"/sddm/theme.conf "$here"/sddm/metadata.desktop "$work/sddm/"
cp -L "$here"/wallpaper/contents/ui/*.qml "$work/wallpaper/contents/ui/"
cp -L "$here"/wallpaper/contents/config/main.xml "$work/wallpaper/contents/config/"
cp -L "$here"/wallpaper/metadata.json "$work/wallpaper/"
mkdir -p "$work/splash/contents/splash"
cp -L "$here"/splash/contents/splash/*.qml "$work/splash/contents/splash/"
cp -L "$here"/splash/metadata.json "$work/splash/"
note "$(find "$work" -type f | wc -l) files staged"

if find "$work" -type l | grep -q .; then
    note "ERROR: staged tree still contains symlinks"
    fail=1
fi

# ---- metadata ---------------------------------------------------------------
python3 -c "import json,sys; json.load(open('$work/wallpaper/metadata.json'))" \
    && note "metadata.json valid" || { note "metadata.json INVALID"; fail=1; }
python3 -c "import xml.dom.minidom as m; m.parse('$work/wallpaper/contents/config/main.xml')" \
    && note "main.xml valid" || { note "main.xml INVALID"; fail=1; }

# ---- theme metadata ---------------------------------------------------------
# SDDM reads metadata.desktop to decide which greeter binary runs the theme:
# QtVersion=6 selects /usr/bin/sddm-greeter-qt6, anything else falls back to
# /usr/bin/sddm-greeter, which is Qt5 and cannot parse Qt6 QML. When that
# happens the theme does not load, SDDM switches to its embedded theme, and
# that has no layer-shell under kwin_wayland — a black screen with a dead
# keyboard.
echo "metadata"
for pair in "QtVersion=6" "Theme-API=2.0" "Type=sddm-theme" "MainScript=Main.qml" "ConfigFile=theme.conf"; do
    if grep -qxF "$pair" "$work/sddm/metadata.desktop"; then
        note "metadata.desktop $pair"
    else
        note "ERROR: '$pair' missing from metadata.desktop"
        fail=1
    fi
done

# ---- 2. lint ----------------------------------------------------------------
# Main.qml is linted through the mock instead: on its own, every reference to
# an SDDM context object (sddm, userModel, config, ...) is an unqualified
# access that qmllint cannot resolve and that is not a defect.
echo "lint"
shared_out="$("$qmllint" -I "$work/sddm" \
    "$work"/sddm/{Tokens,Backdrop,IrisScanner,ScanStatus,PasswordField,GlyphButton}.qml 2>&1 || true)"
if [[ -n "$shared_out" ]]; then
    printf '%s\n' "$shared_out" | sed 's/^/  /'
    fail=1
else
    note "shared components clean"
fi

wall_out="$("$qmllint" -I "$work/wallpaper/contents/ui" \
    "$work"/wallpaper/contents/ui/{main,config}.qml 2>&1 | grep -vE 'plasmoid|kirigami|Kirigami|QQC2' || true)"
if [[ -n "$wall_out" ]]; then
    printf '%s\n' "$wall_out" | sed 's/^/  /'
else
    note "wallpaper package clean"
fi

# ---- lock screen package ----------------------------------------------------
mkdir -p "$work/lock"
cp -L "$here"/lockscreen/contents/lockscreen/*.qml "$work/lock/"
cp -L "$here"/lockscreen/contents/lockscreen/qmldir "$work/lock/"
cp -L "$here"/lockscreen/contents/lockscreen/config.xml "$work/lock/"
cp -L "$here"/lockscreen/metadata.json "$work/lock/"
python3 -c "import json; json.load(open('$work/lock/metadata.json'))" \
    && note "lock package metadata.json valid" || { note "lock metadata.json INVALID"; fail=1; }
python3 -c "import xml.dom.minidom as m; m.parse('$work/lock/config.xml')" \
    && note "lock config.xml valid" || { note "lock config.xml INVALID"; fail=1; }

# FallbackUi and LockScreenUi are linted by running them instead: every
# reference they make to authenticator / root / kscreenlocker_userName is a
# context object qmllint cannot resolve and that is not a defect.
python3 -c "import json; json.load(open('$work/splash/metadata.json'))" \
    && note "splash metadata.json valid" || { note "splash metadata.json INVALID"; fail=1; }
splash_out="$("$qmllint" -I "$work/splash/contents/splash" "$work"/splash/contents/splash/Splash.qml 2>&1 || true)"
if [[ -n "$splash_out" ]]; then
    printf '%s\n' "$splash_out" | sed 's/^/  /'
    fail=1
else
    note "splash package clean"
fi

lock_out="$("$qmllint" -I "$work/lock" "$work"/lock/{LockScreen,PasswordSync,Caption}.qml 2>&1 || true)"
if [[ -n "$lock_out" ]]; then
    printf '%s\n' "$lock_out" | sed 's/^/  /'
    fail=1
else
    note "lock screen entry point and fallback UI clean"
fi

# ---- 3. run -----------------------------------------------------------------
echo "run"
shots="$work/shots"
mkdir -p "$shots"
python3 "$here/tools/mock.py" "$work/mock" "file://$shots" >/dev/null

# QT_FORCE_STDERR_LOGGING is not optional: without it every QML warning goes to
# journald and this pass reports success on a greeter that never drew.
run_out="$(QT_FORCE_STDERR_LOGGING=1 QT_QPA_PLATFORM=offscreen \
    timeout 60 qml6 "$work/mock/Main.qml" 2>&1 | grep -v 'modifierkeyinfo' || true)"

if [[ -n "$run_out" ]]; then
    printf '%s\n' "$run_out" | sed 's/^/  /'
    fail=1
fi

python3 "$here/tools/mock-lock.py" "$work/mock-lock" "file://$shots" >/dev/null
lock_run="$(QT_FORCE_STDERR_LOGGING=1 QT_QPA_PLATFORM=offscreen \
    timeout 60 qml6 "$work/mock-lock/MockWindow.qml" 2>&1 | grep -v 'modifierkeyinfo' || true)"
if [[ -n "$lock_run" ]]; then
    printf '%s\n' "$lock_run" | sed 's/^/  /'
    fail=1
fi
lock_count="$(find "$shots" -name 'lock-*.png' | wc -l)"
if [[ "$lock_count" -eq 6 ]]; then
    note "lock screen: all 6 frames rendered (dark, idle, scanning, failed, matched, unlock)"
else
    note "ERROR: expected 6 lock screen frames, got $lock_count"
    fail=1
fi

# The safety net, proved rather than assumed: break LockScreenUi on purpose
# and check that LockScreen.qml's Loader falls back to the plain prompt.
python3 "$here/tools/mock-lock.py" "$work/mock-fb" "file://$shots" fallback >/dev/null
QT_FORCE_STDERR_LOGGING=1 QT_QPA_PLATFORM=offscreen \
    timeout 40 qml6 "$work/mock-fb/MockWindow.qml" >/dev/null 2>&1 || true
if [[ -f "$shots/fallback.png" ]]; then
    note "fallback UI took over (LockScreenUi broken on purpose)"
else
    note "ERROR: fallback UI did not render when LockScreenUi was broken"
    fail=1
fi

shot_count="$(find "$shots" -name 'mock-*.png' | wc -l)"
if [[ "$shot_count" -eq 6 ]]; then
    note "all 6 frames rendered (idle, scanning, notice, matched, timeout, nocamera)"
else
    note "ERROR: expected 6 frames, got $shot_count"
    fail=1
fi

# ---- 4. the real greeter ----------------------------------------------------
# Everything above runs the QML under plain qml6, which is not what SDDM does:
# it never exercises the greeter's own context objects (sddm, userModel,
# sessionModel, screenModel, config, keyboard) and it never goes through
# SDDM's choice of greeter binary. This pass does both, with the real binary,
# on the offscreen platform so it cannot touch the display.
if [[ "${IRIS_SKIP_GREETER:-0}" == "1" ]]; then
    echo "greeter  (skipped: IRIS_SKIP_GREETER=1)"
elif [[ -x /usr/bin/sddm-greeter-qt6 ]]; then
    echo "greeter"
    # To a file, not a pipe: SIGTERM from timeout discards an unflushed pipe.
    greeter_log="$work/greeter.log"
    QT_FORCE_STDERR_LOGGING=1 QT_QPA_PLATFORM=offscreen \
        timeout 12 /usr/bin/sddm-greeter-qt6 --test-mode --theme "$work/sddm" \
        >"$greeter_log" 2>&1 || true
    greeter_out="$(cat "$greeter_log")"

    if ! printf '%s' "$greeter_out" | grep -q "Loading file.*Main.qml"; then
        note "ERROR: the greeter never started loading Main.qml"
        printf '%s\n' "$greeter_out" | tail -15 | sed 's/^/    /'
        fail=1
    fi
    # The tell-tale of a theme that failed to parse or load.
    if printf '%s' "$greeter_out" | grep -qiE 'Fallback to embedded theme|Expected token|is not a type|module .* is not installed'; then
        note "ERROR: the greeter could not load the theme"
        printf '%s\n' "$greeter_out" | grep -iE 'Fallback to embedded|Expected token|is not a type|is not installed|\.qml:' | head -12 | sed 's/^/    /'
        fail=1
    fi
    qml_errs="$(printf '%s' "$greeter_out" | grep -E '/iris/.*\.qml:[0-9]+' | grep -viE 'deprecated' || true)"
    if [[ -n "$qml_errs" ]]; then
        note "ERROR: QML error in the greeter"
        printf '%s\n' "$qml_errs" | head -12 | sed 's/^/    /'
        fail=1
    fi
    [[ "$fail" -eq 0 ]] && note "the real greeter loaded the theme without errors"
else
    note "WARNING: /usr/bin/sddm-greeter-qt6 not found, greeter pass skipped"
fi

# ---- 4b. does a key wake the lock screen ------------------------------------
# A screenshot cannot answer this: the bug was focus ownership, and the only
# thing that proves it is a real key event delivered to a real focus chain.
if [[ -x /usr/lib/qt6/bin/qmltestrunner ]]; then
    echo "wake"
    python3 "$here/tools/mock-lock.py" "$work/mock-test" "file://$shots" test >/dev/null
    wake_log="$work/wake.log"
    QT_FORCE_STDERR_LOGGING=1 QT_QPA_PLATFORM=offscreen \
        timeout 90 /usr/lib/qt6/bin/qmltestrunner -input "$work/mock-test" \
        >"$wake_log" 2>&1 || true
    if grep -q "^Totals: .* 0 failed" "$wake_log"; then
        note "$(grep -o 'Totals:.*' "$wake_log" | head -1)"
    else
        note "ERROR: lock screen wake test failed"
        grep -E '^(FAIL|Totals)' "$wake_log" | head -8 | sed 's/^/    /'
        fail=1
    fi
else
    note "WARNING: qmltestrunner not found, wake test skipped"
fi

# ---- 4c. the real splash ----------------------------------------------------
# ksplashqml exits 0 and prints nothing BOTH for a good package and for a path
# that does not exist — checked deliberately. So the file has to be asserted
# present first, or a wrong path would read as a pass.
if [[ "${IRIS_SKIP_GREETER:-0}" == "1" ]]; then
    echo "splash  (skipped: IRIS_SKIP_GREETER=1)"
elif [[ -x /usr/bin/ksplashqml ]]; then
    echo "splash"
    sp="$work/splashpkg/share/plasma/look-and-feel/org.lckt0.iris"
    mkdir -p "$sp/contents/splash"
    cp -L "$here"/splash/metadata.json "$sp/"
    cp -L "$here"/splash/contents/splash/*.qml "$sp/contents/splash/"

    if [[ ! -f "$sp/contents/splash/Splash.qml" ]]; then
        note "ERROR: Splash.qml missing from the splash package"
        fail=1
    else
        splash_log="$work/splash.log"
        QT_FORCE_STDERR_LOGGING=1 QT_QPA_PLATFORM=offscreen \
            timeout 15 /usr/bin/ksplashqml --test --nofork "$sp" >"$splash_log" 2>&1
        rc=$?
        if [[ "$rc" -ne 0 || -s "$splash_log" ]]; then
            note "ERROR: ksplashqml could not load the splash (exit $rc)"
            head -8 "$splash_log" | sed 's/^/    /'
            fail=1
        else
            note "ksplashqml loaded the splash without errors"
        fi
    fi
else
    note "WARNING: /usr/bin/ksplashqml not found, splash pass skipped"
fi

# ---- 5. the real lock screen ------------------------------------------------
# kscreenlocker_greet resolves the shell package through KPackage, so the
# package is staged under a throwaway XDG_DATA_DIRS instead of being installed.
# offscreen again: with no platform window there is nothing to show and nothing
# to grab, and the actual locking is done by KSldApp inside KWin, which is not
# involved here.
#
if [[ "${IRIS_SKIP_GREETER:-0}" == "1" ]]; then
    echo "lock greeter  (skipped: IRIS_SKIP_GREETER=1)"
elif [[ -x /usr/lib/kscreenlocker_greet ]]; then
    echo "lock greeter"
    xdg="$work/xdg"
    pkg="$xdg/plasma/shells/iris"
    mkdir -p "$pkg/contents/lockscreen"
    cp -L "$here"/lockscreen/metadata.json "$pkg/"
    cp -L "$here"/lockscreen/contents/lockscreen/*.qml \
          "$here"/lockscreen/contents/lockscreen/qmldir \
          "$here"/lockscreen/contents/lockscreen/config.xml "$pkg/contents/lockscreen/"

    lock_log="$work/lock-greeter.log"
    XDG_DATA_DIRS="$xdg:${XDG_DATA_DIRS:-/usr/local/share:/usr/share}" \
    QT_FORCE_STDERR_LOGGING=1 QT_QPA_PLATFORM=offscreen \
        timeout 15 /usr/lib/kscreenlocker_greet --testing --shell iris \
        >"$lock_log" 2>&1 || true

    # Noise that belongs to the offscreen platform or to unrelated packages.
    lock_errs="$(grep -vE 'legacy metadata\.desktop|modifierkeyinfo|Could not find any platform plugin|does not support raise|unsupported clipboard|^Locked at ' "$lock_log" || true)"
    if [[ -n "$lock_errs" ]]; then
        note "ERROR: the lock screen greeter printed errors"
        printf '%s\n' "$lock_errs" | head -12 | sed 's/^/    /'
        fail=1
    elif grep -q '^Locked at ' "$lock_log"; then
        note "the real lock greeter built the UI without errors"
    else
        note "ERROR: the lock greeter never built the UI"
        tail -10 "$lock_log" | sed 's/^/    /'
        fail=1
    fi
else
    note "WARNING: /usr/lib/kscreenlocker_greet not found, lock greeter pass skipped"
fi

echo
if [[ "$fail" -eq 0 ]]; then
    echo "OK — theme is ready to install"
else
    echo "FAILED — do not install until the above is fixed"
fi
exit "$fail"
