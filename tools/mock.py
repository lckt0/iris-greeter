#!/usr/bin/env python3
"""
Stage the SDDM theme into a directory of real files (no symlinks, exactly what
install.sh writes) and build a mock of Main.qml that stands in for the context
objects the greeter injects: sddm, userModel, sessionModel, screenModel, config
and keyboard.

The mock injects those as properties on Main.qml's own root. QML resolves an
unqualified name against the enclosing components *of the same file*, so every
`sddm.login(...)` and `config.caption` in Main.qml binds to the stub without a
single reference in the file being rewritten. The only patch to the body is the
screenModel Repeater, because a stub cannot carry a QAbstractItemModel role.
"""
import pathlib
import shutil
import sys

SRC = pathlib.Path(__file__).resolve().parent.parent
STAGE = pathlib.Path(sys.argv[1])
OUT = sys.argv[2]

# ---- stage: dereference every symlink, as install(1) does -------------------
if STAGE.exists():
    shutil.rmtree(STAGE)
STAGE.mkdir(parents=True)
for f in sorted((SRC / "sddm").iterdir()):
    if f.is_file():
        shutil.copy(f, STAGE / f.name)   # copy() follows symlinks

main = (STAGE / "Main.qml").read_text()

# ---- patch 1: the one thing a stub cannot be ------------------------------
old_repeater = """    Repeater {
        model: screenModel

        delegate: Backdrop {
            id: screen

            /* ScreenModel exposes exactly one role, "geometry". */
            required property rect geometry

            x: screen.geometry.x
            y: screen.geometry.y
            width: screen.geometry.width
            height: screen.geometry.height
            caption: config.caption
            showCaption: config.showCaption === "true"
        }
    }"""
new_repeater = """    Backdrop {
        anchors.fill: parent
        caption: config.caption
        showCaption: config.showCaption === "true"
    }"""
assert main.count(old_repeater) == 1, "screenModel Repeater changed, update the mock"
main = main.replace(old_repeater, new_repeater)

# ---- patch 2: the stubs ----------------------------------------------------
anchor = "    focus: true\n"
assert main.count(anchor) == 1
stubs = anchor + """
    /* ==== MOCK ONLY — injected by tools/mock.py, never installed ==== */

    property QtObject sddm: QtObject {
        signal informationMessage(string message)
        signal loginFailed()
        signal loginSucceeded()

        readonly property bool canSuspend: true
        readonly property bool canReboot: true
        readonly property bool canPowerOff: true

        function login(user, secret, session) { }
        function suspend() { }
        function reboot() { }
        function powerOff() { }
    }

    property QtObject userModel: QtObject {
        readonly property string lastUser: "user"
    }

    property QtObject sessionModel: QtObject {
        readonly property int lastIndex: 0
        function rowCount() { return 2; }
        function index(r, c) { return r; }
        function data(i, role) { return i === 0 ? "Plasma (Wayland)" : "Plasma (X11)"; }
    }

    property QtObject config: QtObject {
        readonly property string caption: "user@host"
        readonly property string showCaption: "true"
        readonly property string showClock: "true"
    }

    property QtObject keyboard: QtObject {
        property int currentLayout: 0
        readonly property var layouts: [{ shortName: "us" }, { shortName: "tr" }]
    }
    /* ==== end mock ==== */
"""
main = main.replace(anchor, stubs)

# ---- patch 3: the driver ---------------------------------------------------
driver = """
    /* ==== MOCK ONLY: drive PAM's side of the conversation ==== */
    property int shotIndex: 0
    readonly property var script: [
        { at: 400,  say: null,                              grab: "1-idle"     },
        { at: 500,  say: "@enter",                          grab: null         },
        { at: 2100, say: null,                              grab: "2-scanning" },
        { at: 2200, say: "Starting face verification",      grab: null         },
        { at: 3000, say: null,                              grab: "3-notice"   },
        { at: 3100, say: "Face matched user user",         grab: null         },
        { at: 3900, say: null,                              grab: "4-matched"  },
        { at: 4200, say: "@fail",                           grab: null         },
        { at: 4400, say: "Face verification timed out",     grab: null         },
        { at: 5200, say: null,                              grab: "5-timeout"  },
        { at: 5500, say: "@fail",                           grab: null         },
        { at: 5700, say: "Face verification failed: cannot open configured camera", grab: null },
        { at: 6500, say: null,                              grab: "6-nocamera" }
    ]

    Timer {
        id: driver
        running: true
        repeat: false
        interval: root.script[0].at
        onTriggered: {
            const step = root.script[root.shotIndex];
            if (step.say === "@enter") {
                root.beginLogin("");
            } else if (step.say === "@fail") {
                root.sddm.loginFailed();
            } else if (step.say !== null) {
                root.sddm.informationMessage(step.say);
            }

            const advance = function () {
                const prev = root.script[root.shotIndex].at;
                root.shotIndex++;
                if (root.shotIndex >= root.script.length) {
                    Qt.quit();
                    return;
                }
                driver.interval = Math.max(16, root.script[root.shotIndex].at - prev);
                driver.restart();
            };

            if (step.grab !== null) {
                root.grabToImage(function (r) {
                    r.saveToFile("OUTDIR/mock-" + step.grab + ".png");
                    advance();
                }, Qt.size(root.width, root.height));
            } else {
                advance();
            }
        }
    }
    /* ==== end mock ==== */
"""
driver = driver.replace("OUTDIR", OUT)
last = main.rstrip().rfind("}")
main = main[:last] + driver + "\n}\n"

(STAGE / "Main.qml").write_text(main)
print(f"mock ready: {STAGE}")
