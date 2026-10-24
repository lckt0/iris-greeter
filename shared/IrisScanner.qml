pragma ComponentBehavior: Bound

/*
    iris — the scanner.

    A reticle, an eye, and a progress ring that is an honest promise: it fills
    over exactly the number of milliseconds pam_howdy is allowed for one scan
    (Tokens.scanMs, which tracks /etc/howdy/config.ini [video] timeout). If PAM
    answers early the ring is cut short; it must never complete before PAM does.

    `phase` is the only input. It is deliberately not called `state`: Item
    already has a `state` property with its own semantics, and every visual
    here is a plain binding with a Behavior rather than a State block, so that
    what you read is what gets drawn — no implicit reverse transitions.

    Nothing here uses an icon theme. The greeter runs as the sddm user and
    cannot see a home-directory icon set, so every glyph is drawn from paths.

    SPDX-FileCopyrightText: 2026 lckt0
    SPDX-License-Identifier: LGPL-2.0-or-later
*/

import QtQuick
import QtQuick.Shapes

Item {
    id: scanner

    /* idle | scanning | working | matched | failed | dark | nocamera | unavailable

       "working" is the splash's phase: the eye is open and its iris turns,
       but nothing is being scanned — there is no sweep line and no sensor
       readout, because the session is loading, not reading you. */
    property string phase: "idle"

    implicitWidth: 200
    implicitHeight: 200

    Tokens { id: tok }

    readonly property real s: Math.min(width, height)
    readonly property real cx: width / 2
    readonly property real cy: height / 2

    readonly property bool scanning: phase === "scanning"
    readonly property bool working: phase === "working"
    readonly property bool matched: phase === "matched"
    readonly property bool dark: phase === "dark"
    readonly property bool shut: phase === "failed" || phase === "nocamera" || phase === "unavailable"
    readonly property bool noCamera: phase === "nocamera"

    /* ---- geometry, all derived from the short edge ---- */
    readonly property real eyeHalfWidth: s * 0.290
    readonly property real lidMax: s * 0.185
    readonly property real irisR: s * 0.115
    readonly property real pupilR: s * 0.046
    readonly property real ringR: s * 0.160
    readonly property real reticle: s * 0.40      // half-side of the corner box
    readonly property real armLen: s * 0.085

    /* ---- animated scalars ----
       lid is a product of two independent sources so neither has to fight a
       binding for ownership: lidTarget is the phase's resting aperture, blink
       is the idle animation multiplying it. */
    property real lidTarget: shut ? 0.05 : dark ? 0.52 : 1.0
    property real blink: 1.0
    readonly property real lid: lidTarget * blink
    readonly property real lidH: lidMax * lid

    Behavior on lidTarget {
        NumberAnimation { duration: tok.base; easing.type: Easing.OutCubic }
    }

    property real ringSweep: 0

    /* When >= 0, the ring shows this fraction instead of running its own
       timer. The splash drives it from the session's start-up
       stage, which is a real measure of progress rather than a guess. */
    property real progress: -1
    readonly property real ringShown: progress >= 0 ? progress : ringSweep
    property real bracketPull: 0
    property real striae: 0
    property real scanPos: 0
    property int  noiseTick: 0

    property color live: dark ? tok.line28 : shut ? tok.line16 : tok.line86

    Behavior on live {
        ColorAnimation { duration: tok.base }
    }

    /* ------------------------------------------------------------------ */
    /*  animations                                                         */
    /* ------------------------------------------------------------------ */

    /* Idle blink. Long pause, quick shut, quick open — the timing is what
       makes it read as a blink rather than a pulse. */
    SequentialAnimation {
        running: scanner.phase === "idle"
        loops: Animation.Infinite

        onRunningChanged: if (!running) scanner.blink = 1.0

        PauseAnimation { duration: 3800 }
        NumberAnimation { target: scanner; property: "blink"; to: 0.04; duration: 90; easing.type: Easing.InQuad }
        NumberAnimation { target: scanner; property: "blink"; to: 1.0; duration: 150; easing.type: Easing.OutQuad }
    }

    /* The ring is the clock. One pass, no loop: a second lap would claim the
       scan restarted, which it never does. */
    NumberAnimation {
        id: ringFill
        target: scanner
        property: "ringSweep"
        from: 0
        to: 1
        duration: tok.scanMs
        easing.type: Easing.Linear
        running: scanner.scanning
    }

    /* Brackets close in while the scan runs, snap outward on a match. */
    Behavior on bracketPull {
        NumberAnimation { duration: tok.base; easing.type: Easing.OutBack }
    }

    NumberAnimation {
        target: scanner
        property: "striae"
        from: 0
        to: 360
        duration: Math.round(tok.scanMs * 2.2)
        loops: Animation.Infinite
        running: scanner.scanning || scanner.working
    }

    /* The sweep line. Down, up, repeat — a single direction reads as a wipe,
       a return stroke reads as a sensor. */
    SequentialAnimation {
        running: scanner.scanning
        loops: Animation.Infinite

        onRunningChanged: if (!running) scanner.scanPos = 0

        NumberAnimation { target: scanner; property: "scanPos"; from: -1; to: 1; duration: tok.sweepMs; easing.type: Easing.InOutSine }
        NumberAnimation { target: scanner; property: "scanPos"; from: 1; to: -1; duration: tok.sweepMs; easing.type: Easing.InOutSine }
    }

    Timer {
        running: scanner.scanning
        interval: 80
        repeat: true
        onTriggered: scanner.noiseTick++
    }

    onPhaseChanged: {
        if (phase === "scanning") {
            bracketPull = s * 0.045;
        } else if (phase === "matched") {
            /* Complete the ring rather than letting it stop where it was:
               PAM said yes, so the arc has earned its last degrees. */
            ringSweep = 1;
            bracketPull = -s * 0.030;
            flare.restart();
        } else {
            bracketPull = 0;
            /* Nothing to fade when the ring is not ours to animate. */
            if (progress < 0) {
                ringFade.restart();
            }
        }
    }

    SequentialAnimation {
        id: flare
        NumberAnimation { target: scanner; property: "bracketPull"; to: -scanner.s * 0.030; duration: tok.fast; easing.type: Easing.OutQuad }
        NumberAnimation { target: scanner; property: "bracketPull"; to: 0; duration: tok.slow; easing.type: Easing.OutCubic }
    }

    NumberAnimation {
        id: ringFade
        target: scanner
        property: "ringSweep"
        to: 0
        duration: tok.slow
        easing.type: Easing.OutCubic
    }

    /* ------------------------------------------------------------------ */
    /*  reticle brackets                                                   */
    /* ------------------------------------------------------------------ */

    Repeater {
        model: 4

        delegate: Item {
            id: bracket

            required property int index

            readonly property bool atRight: index % 2 === 1
            readonly property bool atBottom: index >= 2
            readonly property real bx: scanner.cx + (atRight ? 1 : -1) * (scanner.reticle - scanner.bracketPull)
            readonly property real by: scanner.cy + (atBottom ? 1 : -1) * (scanner.reticle - scanner.bracketPull)

            Rectangle {
                x: bracket.atRight ? bracket.bx - width : bracket.bx
                y: bracket.by - 1
                width: scanner.armLen
                height: 2
                color: scanner.matched ? tok.line86 : tok.line42
                Behavior on color { ColorAnimation { duration: tok.base } }
            }

            Rectangle {
                x: bracket.bx - 1
                y: bracket.atBottom ? bracket.by - height : bracket.by
                width: 2
                height: scanner.armLen
                color: scanner.matched ? tok.line86 : tok.line42
                Behavior on color { ColorAnimation { duration: tok.base } }
            }
        }
    }

    /* ------------------------------------------------------------------ */
    /*  the eye                                                            */
    /* ------------------------------------------------------------------ */

    /* Iris and pupil live inside a rectangular clip whose height is the lid
       aperture. The almond is at its full height across the middle, which is
       exactly where the iris sits, so a rectangular cut is indistinguishable
       from the real lid closing over it — and it costs no mask layer. */
    Item {
        id: aperture

        width: scanner.eyeHalfWidth * 2
        height: Math.max(0, scanner.lidH * 2)
        x: scanner.cx - width / 2
        y: scanner.cy - height / 2
        clip: true

        Item {
            id: irisBody

            width: scanner.irisR * 2
            height: scanner.irisR * 2
            x: aperture.width / 2 - width / 2
            y: aperture.height / 2 - height / 2

            /* On a match the iris steps back so the verdict glyph drawn over
               it is the thing being read, not a texture competing with it. */
            opacity: scanner.matched ? 0.22 : 1
            Behavior on opacity { NumberAnimation { duration: tok.base } }

            /* Radial striations. A ring of hairlines is what separates an iris
               from a doughnut; they turn only while the scan is running. */
            Item {
                anchors.fill: parent
                rotation: scanner.striae
                opacity: (scanner.scanning || scanner.working) ? 1 : 0.45
                Behavior on opacity { NumberAnimation { duration: tok.base } }

                Repeater {
                    model: 32

                    delegate: Item {
                        id: stria

                        required property int index

                        anchors.fill: parent
                        rotation: index * (360 / 32)

                        Rectangle {
                            anchors.horizontalCenter: parent.horizontalCenter
                            y: 0
                            width: 1
                            height: stria.height * (stria.index % 2 === 0 ? 0.30 : 0.18)
                            color: scanner.live
                            opacity: 0.55
                        }
                    }
                }
            }

            /* Iris rim */
            Rectangle {
                anchors.fill: parent
                radius: width / 2
                color: "transparent"
                border.width: 1.5
                border.color: scanner.live
            }

            /* Pupil. Contracts under the scan light, the way a real one would. */
            Rectangle {
                width: scanner.pupilR * 2 * (scanner.scanning ? 0.72 : 1)
                height: width
                radius: width / 2
                anchors.centerIn: parent
                color: scanner.live

                Behavior on width {
                    NumberAnimation { duration: tok.slow; easing.type: Easing.OutCubic }
                }
            }
        }
    }

    /* The almond. Two quadratic arcs sharing their endpoints; a quad's peak
       deviation is half its control offset, so the control points sit at
       twice the aperture to land the curve exactly on lidH. */
    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            strokeColor: scanner.live
            strokeWidth: 1.6
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            joinStyle: ShapePath.RoundJoin

            /* A shut eye alone cannot tell "it failed" from "it was never
               available"; the dashes carry that difference at a glance, and
               the status line spells it out underneath. */
            strokeStyle: scanner.phase === "unavailable" ? ShapePath.DashLine
                                                         : ShapePath.SolidLine
            dashPattern: [3, 3]

            startX: scanner.cx - scanner.eyeHalfWidth
            startY: scanner.cy

            PathQuad {
                x: scanner.cx + scanner.eyeHalfWidth
                y: scanner.cy
                controlX: scanner.cx
                controlY: scanner.cy - scanner.lidH * 2
            }

            PathQuad {
                x: scanner.cx - scanner.eyeHalfWidth
                y: scanner.cy
                controlX: scanner.cx
                controlY: scanner.cy + scanner.lidH * 2
            }
        }
    }

    /* ------------------------------------------------------------------ */
    /*  progress ring                                                      */
    /* ------------------------------------------------------------------ */

    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        opacity: scanner.ringShown > 0 ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: tok.fast } }

        /* Track */
        ShapePath {
            strokeColor: tok.line10
            strokeWidth: 2
            fillColor: "transparent"

            PathAngleArc {
                centerX: scanner.cx
                centerY: scanner.cy
                radiusX: scanner.ringR
                radiusY: scanner.ringR
                startAngle: 0
                sweepAngle: 360
            }
        }

        /* Filled arc */
        ShapePath {
            strokeColor: scanner.matched ? tok.line86 : tok.line62
            strokeWidth: 2
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap

            PathAngleArc {
                centerX: scanner.cx
                centerY: scanner.cy
                radiusX: scanner.ringR
                radiusY: scanner.ringR
                startAngle: -90
                sweepAngle: 360 * scanner.ringShown
            }
        }
    }

    /* ------------------------------------------------------------------ */
    /*  sweep line                                                         */
    /* ------------------------------------------------------------------ */

    Item {
        width: scanner.reticle * 2 - scanner.armLen
        height: 18
        x: scanner.cx - width / 2
        y: scanner.cy + scanner.scanPos * scanner.reticle * 0.70 - height / 2
        visible: scanner.scanning
        opacity: scanner.scanning ? 1 : 0

        Behavior on opacity { NumberAnimation { duration: tok.fast } }

        /* Soft body above and below the filament, drawn as two mirrored
           gradients so the line reads as light rather than as a rule. */
        Rectangle {
            anchors.fill: parent
            gradient: Gradient {
                GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0.0) }
                GradientStop { position: 0.5; color: Qt.rgba(1, 1, 1, 0.10) }
                GradientStop { position: 1.0; color: Qt.rgba(1, 1, 1, 0.0) }
            }
        }

        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width
            height: 1

            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.00; color: Qt.rgba(1, 1, 1, 0.00) }
                GradientStop { position: 0.18; color: Qt.rgba(1, 1, 1, 0.62) }
                GradientStop { position: 0.50; color: Qt.rgba(1, 1, 1, 0.92) }
                GradientStop { position: 0.82; color: Qt.rgba(1, 1, 1, 0.62) }
                GradientStop { position: 1.00; color: Qt.rgba(1, 1, 1, 0.00) }
            }
        }
    }

    /* ------------------------------------------------------------------ */
    /*  verdict glyphs                                                     */
    /* ------------------------------------------------------------------ */

    /* Check, drawn inside the ring on a match. */
    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        opacity: scanner.matched ? 1 : 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: tok.base; easing.type: Easing.OutCubic } }

        ShapePath {
            strokeColor: tok.line86
            strokeWidth: 2.4
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            joinStyle: ShapePath.RoundJoin

            startX: scanner.cx - scanner.s * 0.072
            startY: scanner.cy + scanner.s * 0.004

            PathLine { x: scanner.cx - scanner.s * 0.020; y: scanner.cy + scanner.s * 0.056 }
            PathLine { x: scanner.cx + scanner.s * 0.080; y: scanner.cy - scanner.s * 0.062 }
        }
    }

    /* Slash, for a scanner that is not there at all. */
    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        opacity: scanner.noCamera ? 1 : 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: tok.base } }

        ShapePath {
            strokeColor: tok.line42
            strokeWidth: 1.6
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap

            startX: scanner.cx - scanner.eyeHalfWidth * 0.92
            startY: scanner.cy + scanner.lidMax * 1.35

            PathLine {
                x: scanner.cx + scanner.eyeHalfWidth * 0.92
                y: scanner.cy - scanner.lidMax * 1.35
            }
        }
    }

    /* ------------------------------------------------------------------ */
    /*  sensor readout                                                     */
    /* ------------------------------------------------------------------ */

    /* Deterministic hash rather than Math.random(): the bars have to be
       reproducible frame to frame or the Behaviors have nothing to ease
       between, and a greeter is not the place for an unseeded RNG. */
    function noise(i, t) {
        const x = Math.sin(i * 12.9898 + t * 4.1414) * 43758.5453;
        return x - Math.floor(x);
    }

    Row {
        id: readout

        spacing: Math.max(2, Math.round(scanner.s * 0.012))
        anchors.horizontalCenter: parent.horizontalCenter
        y: scanner.cy + scanner.reticle + scanner.s * 0.045
        opacity: scanner.scanning ? 1 : 0
        visible: opacity > 0

        Behavior on opacity { NumberAnimation { duration: tok.base } }

        Repeater {
            model: 21

            delegate: Rectangle {
                required property int index

                width: 1
                height: scanner.s * (0.012 + 0.048 * scanner.noise(index, scanner.noiseTick))
                anchors.verticalCenter: parent.verticalCenter
                color: tok.line62

                Behavior on height {
                    NumberAnimation { duration: 80; easing.type: Easing.OutQuad }
                }
            }
        }
    }
}
