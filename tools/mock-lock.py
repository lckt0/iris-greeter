#!/usr/bin/env python3
"""
Stage the lock-screen shell package as real files and mock kscreenlocker's side
of it: the `authenticator` object, the kscreenlocker_userName context property
and SessionManagement (which would otherwise want logind over DBus).

Same trick as tools/mock.py: the stubs are injected as properties on
LockScreenUi.qml's own root, and QML resolves an unqualified name against the
enclosing components of the same file, so not one reference in the file is
rewritten. `root` is not stubbed — it is the real LockScreen.qml, reached
through the context chain exactly as it is in production.
"""
import pathlib
import shutil
import sys

SRC = pathlib.Path(__file__).resolve().parent.parent
STAGE = pathlib.Path(sys.argv[1])
OUT = sys.argv[2]

if STAGE.exists():
    shutil.rmtree(STAGE)
STAGE.mkdir(parents=True)

src_dir = SRC / "lockscreen" / "contents" / "lockscreen"
for f in sorted(src_dir.iterdir()):
    if f.is_file():
        shutil.copy(f, STAGE / f.name)      # follows symlinks

MODE = sys.argv[3] if len(sys.argv) > 3 else ""
FALLBACK = MODE == "fallback"
TESTMODE = MODE == "test"

if FALLBACK:
    # Break LockScreenUi on purpose. This is the only way to prove the safety
    # net in LockScreen.qml actually catches: a Loader error, not a runtime
    # one. If this mode ever renders the real interface, the net is not armed.
    (STAGE / "LockScreenUi.qml").write_text(
        "import QtQuick\n"
        "import ThisModuleDoesNotExist 9.9\n"
        "Item { }\n"
    )

    fb = (STAGE / "FallbackUi.qml").read_text()
    anchor = "Item {\n    id: fallback\n"
    assert fb.count(anchor) == 1
    fb = fb.replace(anchor, anchor + """
    /* ==== MOCK ONLY ==== */
    property QtObject authenticator: QtObject {
        signal succeeded()
        signal failed(int kind)
        property string infoMessage: ""
        property string errorMessage: ""
        function startAuthenticating() { }
        function respond(secret) { }
    }
    property string kscreenlocker_userName: "user"

    Timer {
        running: true
        interval: 900
        onTriggered: {
            fallback.authenticator.infoMessage = "Face verification timed out";
            grabTimer.restart();
        }
    }
    Timer {
        id: grabTimer
        interval: 300
        onTriggered: fallback.grabToImage(function (r) {
            r.saveToFile("OUTDIR/fallback.png");
            Qt.quit();
        }, Qt.size(fallback.width, fallback.height))
    }
    /* ==== end mock ==== */
""")
    (STAGE / "FallbackUi.qml").write_text(fb.replace("OUTDIR", OUT))

    (STAGE / "MockWindow.qml").write_text("""import QtQuick
import QtQuick.Window

Window {
    width: 1600
    height: 900
    visible: true
    color: "#000000"

    LockScreen {
        anchors.fill: parent
    }
}
""")
    print(f"fallback UI mock ready: {STAGE}")
    sys.exit(0)

ui = (STAGE / "LockScreenUi.qml").read_text()

# ---- SessionManagement wants DBus; a stub does not -------------------------
old_sm = "    SessionManagement { id: sessionManagement }\n"
assert ui.count(old_sm) == 1
new_sm = """    property QtObject sessionManagement: QtObject {
        signal aboutToSuspend()
        readonly property bool canSuspend: true
        readonly property bool canHibernate: true
        readonly property bool canSwitchUser: true
        function suspend() { }
        function hibernate() { }
        function switchUser() { }
    }
"""
ui = ui.replace(old_sm, new_sm)

# ---- the authenticator contract, as kscreenlocker presents it --------------
anchor = "    focus: true\n"
assert ui.count(anchor) == 1
stubs = anchor + """
    /* ==== MOCK ONLY — injected by tools/mock-lock.py, never installed ==== */

    property QtObject authenticator: QtObject {
        id: mockAuth

        signal succeeded()
        signal failed(int kind)
        signal noninteractiveError(int kind, var authenticator)

        property string infoMessage: ""
        property string errorMessage: ""
        property string prompt: ""
        property bool promptForSecret: false
        property bool hadPrompt: false
        property bool graceLocked: false
        readonly property int authenticatorTypes: 1

        /* PamAuthenticators::AuthenticatorsState: Idle = 0, Authenticating = 1. */
        property int state: 0

        /* Conversations actually opened, so a test can tell a real start from
           a swallowed one. */
        property int startCount: 0

        function startAuthenticating() {
            /* Same guard as PamAuthenticators::startAuthenticating(): no-op
               while a conversation is open. */
            if (mockAuth.state === 1) {
                return;
            }
            mockAuth.state = 1;
            mockAuth.startCount++;
        }

        function respond(secret) { }

        /* kscreenlocker drops back to Idle when the conversation ends. The
           driver and the tests go through these rather than emitting the
           signals raw, so the state never lies. */
        function mockFail(kind) {
            mockAuth.state = 0;
            mockAuth.failed(kind);
        }

        function mockSucceed() {
            mockAuth.state = 0;
            mockAuth.succeeded();
        }
    }

    property string kscreenlocker_userName: "user"
    property string kscreenlocker_userImage: ""
    /* ==== end mock ==== */
"""
ui = ui.replace(anchor, stubs)

if TESTMODE:
    # Expose the internals the key-injection test needs to assert on, and skip
    # the screenshot driver entirely: qmltestrunner drives this one.
    probe = """
    /* ==== MOCK ONLY: handles for tools/tst_lockwake.qml ==== */
    property var t_surface: surface
    property var t_wake: wakeCatcher
    property var t_field: passwordField
    property var t_stage: stage
    property var t_auth: authenticator
    property var t_scan: scanButton
    property var t_grace: graceLockTimer
    property string t_phase: lockScreenUi.scanPhase
    property string t_status: lockScreenUi.statusText
    property string t_hint: lockScreenUi.hintText
    property bool t_open: lockScreenUi.conversationOpen
    property int t_holdMs: tok.holdMs
    /* ==== end mock ==== */
"""
    last = ui.rstrip().rfind("}")
    ui = ui[:last] + probe + "\n}\n"
    (STAGE / "LockScreenUi.qml").write_text(ui)

    # Reach the loaded interface from outside.
    entry = (STAGE / "LockScreen.qml").read_text()
    a = "    Loader {\n        id: ui\n"
    assert entry.count(a) == 1
    entry = entry.replace("    property bool fellBack: false\n",
                          "    property bool fellBack: false\n\n"
                          "    // MOCK ONLY\n    property alias uiItem: ui.item\n")
    (STAGE / "LockScreen.qml").write_text(entry)

    shutil.copy(SRC / "tools" / "tst_lockwake.qml", STAGE / "tst_lockwake.qml")
    print(f"lock wake test ready: {STAGE}")
    sys.exit(0)

# ---- the driver ------------------------------------------------------------
driver = """
    /* ==== MOCK ONLY ==== */
    property int shotIndex: 0
    readonly property var script: [
        { at: 400,  act: null,        grab: "1-dark"    },
        { at: 500,  act: "@wake",     grab: null        },
        { at: 1300, act: null,        grab: "2-idle"    },
        { at: 1400, act: "Starting face verification",  grab: null },
        { at: 2400, act: null,        grab: "3-scanning" },
        { at: 2500, act: "Face verification timed out", grab: null },
        { at: 2600, act: "@fail",     grab: null        },
        { at: 3400, act: null,        grab: "4-failed"  },
        { at: 3500, act: "Starting face verification",  grab: null },
        { at: 4300, act: "Face matched user user",     grab: null },
        { at: 5100, act: null,        grab: "5-matched" },
        { at: 5200, act: "@succeed",  grab: null        },
        { at: 6000, act: null,        grab: "6-unlock-offer" }
    ]

    Timer {
        id: driver
        running: true
        repeat: false
        interval: lockScreenUi.script[0].at
        onTriggered: {
            const step = lockScreenUi.script[lockScreenUi.shotIndex];

            if (step.act === "@wake") {
                surface.uiVisible = true;
            } else if (step.act === "@fail") {
                lockScreenUi.authenticator.mockFail(0);
            } else if (step.act === "@succeed") {
                lockScreenUi.authenticator.hadPrompt = false;
                lockScreenUi.authenticator.mockSucceed();
            } else if (step.act !== null) {
                // Clear first: setting a property to the value it already has
                // emits nothing, and the same notice is sent more than once.
                lockScreenUi.authenticator.infoMessage = "";
                lockScreenUi.authenticator.infoMessage = step.act;
            }

            const advance = function () {
                const prev = lockScreenUi.script[lockScreenUi.shotIndex].at;
                lockScreenUi.shotIndex++;
                if (lockScreenUi.shotIndex >= lockScreenUi.script.length) {
                    Qt.quit();
                    return;
                }
                driver.interval = Math.max(16, lockScreenUi.script[lockScreenUi.shotIndex].at - prev);
                driver.restart();
            };

            if (step.grab !== null) {
                lockScreenUi.grabToImage(function (r) {
                    r.saveToFile("OUTDIR/lock-" + step.grab + ".png");
                    advance();
                }, Qt.size(lockScreenUi.width, lockScreenUi.height));
            } else {
                advance();
            }
        }
    }
    /* ==== end mock ==== */
"""
driver = driver.replace("OUTDIR", OUT)
last = ui.rstrip().rfind("}")
ui = ui[:last] + driver + "\n}\n"
(STAGE / "LockScreenUi.qml").write_text(ui)

# ---- a window to give it a real size ---------------------------------------
(STAGE / "MockWindow.qml").write_text("""import QtQuick
import QtQuick.Window

Window {
    width: 1600
    height: 900
    visible: true
    color: "#000000"

    LockScreen {
        anchors.fill: parent
    }
}
""")

print(f"lock screen mock ready: {STAGE}")
