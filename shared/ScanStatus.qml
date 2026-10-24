/*
    iris — howdy message interpreter.

    pam_howdy writes plain English through the PAM conversation. SDDM forwards
    it as sddm.informationMessage; the Plasma lock screen forwards it as
    authenticator.infoMessage. Same sentences, two doors.

    The strings below match pam_howdy from howdy-next 3.4.0; unknown lines
    are still handled by `classify`.

    The interface says "eye", never "face": known lines are rewritten and
    unknown ones get a word-level pass for face/facial.

    SPDX-FileCopyrightText: 2026 lckt0
    SPDX-License-Identifier: LGPL-2.0-or-later
*/

import QtQuick

QtObject {
    id: interpreter

    /* Longest first: "Face verification skipped: no enrolled face model" has
       to be tested before the bare "Face verification skipped" prefix, or the
       generic branch swallows the specific one. */
    readonly property var table: [
        { m: "Starting face verification",                            p: "scanning",    t: "Scanning iris",                 f: false },
        { m: "Face verification succeeded",                           p: "matched",     t: "Iris verified",                 f: true  },
        { m: "Face matched user",                                     p: "matched",     t: "Iris matched",                  f: true  },
        { m: "Face verification failed: camera image too dark",       p: "dark",        t: "Too dark to read your iris",    f: true  },
        { m: "Camera image is too dark for detection",                p: "dark",        t: "Too dark to read your iris",    f: false },
        { m: "Face verification failed: cannot open configured camera", p: "nocamera",  t: "Eye scanner not responding",    f: true  },
        { m: "Face verification failed: unknown error",               p: "failed",      t: "Iris scan failed",              f: true  },
        { m: "Face verification unavailable: no enrolled face model", p: "unavailable", t: "No iris enrolled",              f: true  },
        { m: "Face verification skipped: no enrolled face model",     p: "unavailable", t: "No iris enrolled",              f: true  },
        { m: "Face verification skipped: lid is closed",              p: "unavailable", t: "Lid shut, scanner asleep",      f: true  },
        { m: "Face verification skipped: Howdy is disabled",          p: "unavailable", t: "Eye scan is switched off",      f: true  },
        { m: "Face verification skipped: invalid username",           p: "unavailable", t: "Eye scan unavailable",          f: true  },
        { m: "Face verification skipped for SSH session",             p: "unavailable", t: "Eye scan unavailable",          f: true  },
        { m: "Face verification skipped",                             p: "unavailable", t: "Eye scan unavailable",          f: true  },
        { m: "Face verification timed out",                           p: "failed",      t: "Iris not recognised",           f: true  },
        { m: "Face verification aborted",                             p: "failed",      t: "Eye scan cancelled",            f: true  },
        { m: "Authentication eligibility failed",                     p: "failed",      t: "Eye scan not permitted",        f: true  },
        { m: "Howdy auth helper",                                     p: "failed",      t: "Eye scanner error",             f: true  }
    ]

    /* PAM's own password prompt is not a status: it is the thing the password
       field already is. Swallow it rather than printing "Password:" above a
       box that says Password. */
    function isPasswordPrompt(raw) {
        const s = raw.trim().toLowerCase().replace(/:$/, "");
        return s === "password" || s === "password for" || s.startsWith("password for ");
    }

    /* Last line of defence for a sentence this build has never seen. */
    function rewrite(raw) {
        return raw
            .replace(/facial recognition/gi, "iris scan")
            .replace(/facial/gi, "iris")
            .replace(/\bfaces\b/gi, "eyes")
            .replace(/\bface\b/gi, "eye")
            .replace(/\bFace\b/g, "Eye");
    }

    /*  Returns:
          null                       — not ours, leave the screen alone
          { phase, text, final }     — phase may be "" meaning "text only"

        `final` marks a verdict: the caller stops the scan on it. A non-final
        hit (the opening notice, the dark-frame warning) is progress, and the
        scanner keeps running. */
    function classify(raw) {
        if (!raw) {
            return null;
        }
        const line = String(raw).trim();
        if (line.length === 0 || isPasswordPrompt(line)) {
            return null;
        }

        for (let i = 0; i < table.length; ++i) {
            if (line.indexOf(table[i].m) === 0) {
                return { phase: table[i].p, text: table[i].t, final: table[i].f };
            }
        }

        return { phase: "", text: rewrite(line), final: false };
    }
}
