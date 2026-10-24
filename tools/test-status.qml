import QtQuick

QtObject {
    id: harness

    property var interp: ScanStatus {}

    /* Every user-visible sentence in pam_howdy.so 3.4.0, plus the traps. */
    readonly property var cases: [
        "Starting face verification",
        "Face verification succeeded",
        "Face matched user user",
        "Face verification failed: camera image too dark",
        "Camera image is too dark for detection",
        "Face verification failed: cannot open configured camera",
        "Face verification failed: unknown error",
        "Face verification unavailable: no enrolled face model",
        "Face verification skipped: no enrolled face model",
        "Face verification skipped: lid is closed",
        "Face verification skipped: Howdy is disabled",
        "Face verification skipped: invalid username",
        "Face verification skipped for SSH session",
        "Face verification timed out",
        "Face verification aborted",
        "Authentication eligibility failed",
        "Howdy auth helper failed: boom",
        "Password:",
        "Password: ",
        "password for user:",
        "",
        "   ",
        "Some future line about your face and facial recognition"
    ]

    Component.onCompleted: {
        let bad = 0;
        for (let i = 0; i < cases.length; ++i) {
            const r = interp.classify(cases[i]);
            const shown = r === null
                ? "(null)"
                : "[" + (r.phase === "" ? "-" : r.phase) + (r.final ? " final" : "") + "] " + r.text;
            console.log(JSON.stringify(cases[i]).padEnd(58) + " -> " + shown);
            if (r !== null && /face|facial/i.test(r.text)) {
                console.log("   !! LEAK: 'face' reached the UI");
                bad++;
            }
        }
        console.log(bad === 0 ? "\nNO LEAKS" : "\n" + bad + " LEAKS");
        Qt.exit(bad === 0 ? 0 : 1);
    }
}
