/*
    iris — what wakes the lock screen, and what the footer's eye really does.

      · any key wakes the resting screen (Enter included);
      · the mouse does NOT wake it (tests 006 and 007);
      · SCAN AGAIN does not reset the screen while a PAM conversation is
        already open (tests 008 and 009).

    `visible: true` is not decoration: a TestCase is invisible by default, an
    invisible item receives no mouse events, and every mouse assertion below
    would pass for the wrong reason without it.

    Run by tools/check.sh through qmltestrunner.
*/

import QtQuick
import QtTest

TestCase {
    id: tc

    name: "lock-wake"
    when: windowShown
    visible: true
    width: 1200
    height: 700

    LockScreen {
        id: screen
        anchors.fill: parent
    }

    /* Back to a dark screen with PAM idle and the conversation counter at
       zero, so every test below can assert absolute numbers instead of
       deltas from whatever the test before it left behind. */
    function rest() {
        const ui = screen.uiItem;
        ui.t_surface.uiVisible = false;
        ui.t_auth.state = 0;
        ui.t_auth.startCount = 0;
        /* A rejected secret arms a three-second timer that re-opens the
           conversation. Left running it would land in the middle of whichever
           test came next, so each test starts without one pending. */
        ui.t_grace.stop();
        ui.t_field.clear();
        /* Wait for the fade-out to finish rather than a fixed delay. */
        tryVerify(function () { return ui.t_stage.opacity === 0; }, 3000,
                  "UI fade-out did not finish");
        wait(60);
        return ui;
    }

    /* Wake the screen the way a person does, and let the fade finish so the
       footer is actually hittable. */
    function woken() {
        const ui = rest();
        keyClick(Qt.Key_Return);
        wait(tc.animationDuration());
        return ui;
    }

    function centreOf(item) {
        return item.mapToItem(tc, item.width / 2, item.height / 2);
    }

    function test_001_rests_without_stealing_focus() {
        const ui = screen.uiItem;
        verify(ui !== null, "LockScreenUi loaded");
        compare(ui.t_surface.uiVisible, false, "screen starts resting");
        verify(!ui.t_field.hasFocus,
               "password field must NOT hold focus while resting");
        verify(ui.t_wake.activeFocus,
               "wake catcher must hold focus while resting");
    }

    function test_002_enter_wakes_the_screen() {
        const ui = rest();
        keyClick(Qt.Key_Return);
        wait(60);
        compare(ui.t_surface.uiVisible, true, "Enter woke the screen");
        verify(ui.t_field.hasFocus, "focus moved to the password field on wake");
        compare(ui.t_field.text, "", "Enter typed nothing into the field");
    }

    function test_003_printable_key_wakes_and_is_typed() {
        const ui = rest();
        keyClick(Qt.Key_K);
        wait(60);
        compare(ui.t_surface.uiVisible, true, "a letter wakes it too");
        compare(ui.t_field.text, "k", "the waking key was typed into the field");
    }

    function test_004_resting_layer_is_what_is_shown() {
        const ui = rest();
        verify(ui.t_stage.opacity < 0.5, "UI hidden while resting");
        keyClick(Qt.Key_Return);
        wait(tc.animationDuration());
        verify(ui.t_stage.opacity > 0.5, "UI visible after waking");
    }

    /* The status line must not clear while a scan is still running. */
    function test_005_scan_survives_the_status_timer() {
        const ui = rest();
        ui.t_surface.uiVisible = true;
        wait(60);

        ui.t_auth.infoMessage = "";
        ui.t_auth.infoMessage = "Starting face verification";
        wait(80);
        compare(ui.t_phase, "scanning", "scan started");

        // Past the hold timer, still well inside a ten-second scan.
        wait(ui.t_holdMs + 700);

        compare(ui.t_phase, "scanning",
                "phase must survive while scanning (status timer must not clear it)");
        verify(ui.t_status.length > 0,
               "status text must stay while scanning");
    }

    /* ------------------------------------------------------------------ */
    /*  the mouse must leave it resting                                    */
    /* ------------------------------------------------------------------ */

    /* Two moves to different places: a single one proves nothing. */
    function test_006_mouse_movement_does_not_wake() {
        const ui = rest();

        mouseMove(tc, 400, 300);
        wait(60);
        mouseMove(tc, 700, 420);
        wait(120);

        compare(ui.t_surface.uiVisible, false,
                "moving the mouse must NOT wake the screen");
        verify(ui.t_stage.opacity < 0.5, "UI must stay hidden");
        compare(ui.t_auth.startCount, 0,
                "mouse movement must not start a PAM conversation");
    }

    function test_007_mouse_click_does_not_wake_but_a_key_still_does() {
        const ui = rest();

        mouseClick(tc, 600, 350);
        wait(120);
        compare(ui.t_surface.uiVisible, false,
                "a mouse click must NOT wake the screen");
        compare(ui.t_auth.startCount, 0,
                "a click must not start a PAM conversation");

        /* The other half of the same claim: this must be a change to the mouse
           and not a screen that stopped waking altogether. */
        keyClick(Qt.Key_Return);
        wait(60);
        compare(ui.t_surface.uiVisible, true,
                "keyboard must still wake the screen");
        compare(ui.t_auth.startCount, 1, "waking opened exactly one conversation");
    }

    /* ------------------------------------------------------------------ */
    /*  SCAN AGAIN tells the truth                                         */
    /* ------------------------------------------------------------------ */

    /* With a conversation already open, kscreenlocker ignores
       startAuthenticating(). The button must leave the scan alone and say why. */
    function test_008_scan_again_is_honest_while_a_conversation_is_open() {
        const ui = woken();

        ui.t_auth.infoMessage = "";
        ui.t_auth.infoMessage = "Starting face verification";
        wait(80);
        compare(ui.t_phase, "scanning", "scan running");
        compare(ui.t_auth.state, 1, "PAM conversation open");

        const opened = ui.t_auth.startCount;
        const said = ui.t_status;
        mouseClick(tc, centreOf(ui.t_scan).x, centreOf(ui.t_scan).y);
        wait(120);

        compare(ui.t_auth.startCount, opened,
                "kscreenlocker would ignore it: must not count as a start");
        compare(ui.t_phase, "scanning",
                "running scan must not be reset");
        compare(ui.t_status, said,
                "PAM's message must not be cleared");
        verify(ui.t_hint.length > 0,
               "must explain why it cannot scan");
    }

    /* Once PAM is idle again the button opens a new conversation. */
    function test_009_scan_again_really_starts_one_when_pam_is_idle() {
        const ui = woken();

        ui.t_auth.mockFail(0);
        wait(80);
        compare(ui.t_auth.state, 0, "rejected attempt closed the conversation");

        const opened = ui.t_auth.startCount;
        mouseClick(tc, centreOf(ui.t_scan).x, centreOf(ui.t_scan).y);
        wait(120);

        compare(ui.t_auth.startCount, opened + 1,
                "with PAM idle the button starts a new scan");
        compare(ui.t_auth.state, 1, "conversation opened");
    }

    /* Exercise the fallback used when `authenticator.state` is missing. */
    function test_010_the_screen_tracks_the_conversation_itself() {
        const ui = woken();
        compare(ui.t_open, true, "waking opened the conversation");

        ui.t_auth.mockFail(0);
        wait(80);
        compare(ui.t_open, false, "rejected attempt closed the conversation");

        /* kind != 0 is a non-interactive authenticator (a fingerprint reader,
           say) reporting for itself. The interactive conversation is not its
           to close, and treating it as though it were would leave the button
           offering a scan that PAM would ignore. */
        ui.t_grace.stop();
        ui.t_surface.uiVisible = false;
        ui.t_surface.uiVisible = true;
        wait(60);
        compare(ui.t_open, true, "screen woke again, conversation open");

        ui.t_auth.failed(1);
        wait(60);
        compare(ui.t_open, true,
                "another authenticator failing must not close the conversation");
    }

    function animationDuration() {
        return 1400;
    }
}
