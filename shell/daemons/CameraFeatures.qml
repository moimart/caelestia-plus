pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import Caelestia
import Caelestia.Config
import Caelestia.I18n
import qs.services
import qs.utils
import qs.modules.lock

// What the shell does with the webcam (services/Camera.qml does the talking):
//   presence   while you're idle, check whether you're there: hold off idle
//              actions if so, lock if you've left; while locked, wake the
//              screen and start face unlock when you sit back down
//   light      now and then, read the room's light to set monitor brightness
//              (and optionally the light/dark scheme)
//   gestures   run the configured action for each hand gesture
//   snapshots  a photo after repeated wrong passwords, shown once unlocked
Scope {
    id: root

    required property Lock lock

    readonly property bool locked: lock.lock.locked
    readonly property bool available: GlobalConfig.camera.enabled && Camera.running && Camera.hasCamera
    // Presence needs the face model (ONNX Runtime); light and photos don't
    readonly property bool canSee: available && Camera.vision

    property bool idle
    property bool present
    property int awayChecks
    property real lastWake

    readonly property var gestureNames: ({
            palm: Tr.tr("Open palm"),
            swipe_left: Tr.tr("Swipe left"),
            swipe_right: Tr.tr("Swipe right"),
            thumbs_up: Tr.tr("Thumbs up"),
            thumbs_down: Tr.tr("Thumbs down")
        })

    property int failures
    property list<string> photos

    function checkPresence(): void {
        Camera.presence(res => {
            if (!res.ok) {
                // Another app has the camera, most likely you on a call
                root.present = res.reason === "busy";
                return;
            }
            if (res.faces > 0) {
                root.present = true;
                root.awayChecks = 0;
                return;
            }
            root.present = false;
            root.awayChecks++;
            if (root.awayChecks >= GlobalConfig.camera.presence.awayAfter && GlobalConfig.camera.presence.lockWhenAway && !root.locked)
                root.lock.lock.locked = true;
        });
    }

    function checkReturn(): void {
        Camera.presence(res => {
            if (!res.ok || res.faces === 0 || Date.now() - root.lastWake < 20000)
                return;
            root.lastWake = Date.now();
            Hypr.dispatch(Hypr.usingLua ? `hl.dsp.dpms({ action = "enable" })` : "dpms on");
            // Someone just sat down: a fresh set of tries, whatever failed before
            const howdy = root.lock.pam.howdy;
            if (!howdy.active)
                howdy.reset();
            if (howdy.canAttempt && !howdy.active)
                howdy.start();
        });
    }

    function readLight(): void {
        Camera.light(res => {
            if (!res.ok)
                return;
            const cfg = GlobalConfig.camera.light;
            const span = Math.max(0.01, cfg.brightLevel - cfg.darkLevel);
            const t = Math.max(0, Math.min(1, (res.level - cfg.darkLevel) / span));
            if (cfg.adjustBrightness) {
                const target = cfg.minBrightness + (cfg.maxBrightness - cfg.minBrightness) * t;
                for (const m of Brightness.monitors)
                    if (Math.abs(m.brightness - target) > 0.04)
                        m.setBrightness(target);
            }
            if (cfg.switchScheme) {
                if (res.level < cfg.darkLevel && Colours.light)
                    Colours.setMode("dark");
                else if (res.level > cfg.brightLevel && !Colours.light)
                    Colours.setMode("light");
            }
        });
    }

    function runAction(action: string): string {
        const p = Players.active;
        switch (action) {
        case "":
        case "none":
            return "";
        case "media.toggle":
            {
                const wasPlaying = p?.isPlaying ?? false;
                p?.togglePlaying();
                return wasPlaying ? Tr.tr("Paused") : Tr.tr("Playing");
            }
        case "media.next":
            p?.next();
            return Tr.tr("Next track");
        case "media.previous":
            p?.previous();
            return Tr.tr("Previous track");
        case "media.stop":
            p?.stop();
            return Tr.tr("Stopped");
        default:
            Quickshell.execDetached(["sh", "-c", action]);
            return action;
        }
    }

    function stamp(): string {
        const d = new Date();
        const p = n => String(n).padStart(2, "0");
        return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())}_${p(d.getHours())}-${p(d.getMinutes())}-${p(d.getSeconds())}`;
    }

    onLockedChanged: {
        if (locked) {
            failures = 0;
            photos = [];
            return;
        }
        if (photos.length === 0)
            return;
        const last = photos[photos.length - 1];
        Quickshell.execDetached(["notify-send", "-a", "caelestia-shell", "-u", "critical", "-i", "camera-photo", "-h", `STRING:image-path:${last}`, Tr.tr("%1 wrong passwords while locked").arg(failures), Tr.tr("Photo saved to %1").arg(Paths.shortenHome(last))]);
        failures = 0;
        photos = [];
    }

    IdleMonitor {
        enabled: root.canSee && GlobalConfig.camera.presence.enabled
        timeout: GlobalConfig.camera.presence.checkAfter
        respectInhibitors: false
        onIsIdleChanged: {
            root.idle = isIdle;
            root.present = false;
            root.awayChecks = 0;
        }
    }

    Timer {
        running: root.canSee && GlobalConfig.camera.presence.enabled && root.idle && !root.locked
        interval: GlobalConfig.camera.presence.interval * 1000
        repeat: true
        triggeredOnStart: true
        onTriggered: root.checkPresence()
    }

    Timer {
        running: root.canSee && GlobalConfig.camera.presence.enabled && GlobalConfig.camera.presence.wakeOnReturn && root.locked
        interval: GlobalConfig.camera.presence.lockedInterval * 1000
        repeat: true
        onTriggered: root.checkReturn()
    }

    // You're there but not typing: don't dim, blank or lock
    IdleInhibitor {
        enabled: GlobalConfig.camera.presence.keepAwake && root.idle && root.present && !root.locked
        window: PanelWindow {
            implicitWidth: 0
            implicitHeight: 0
            color: "transparent"
            mask: Region {}
        }
    }

    Timer {
        running: root.available && GlobalConfig.camera.light.enabled && !root.idle && !root.locked
        interval: GlobalConfig.camera.light.interval * 1000
        repeat: true
        triggeredOnStart: true
        onTriggered: root.readLight()
    }

    Connections {
        function onGesture(name: string): void {
            // The tutorial is just practice
            if (Camera.tutorial)
                return;
            const g = GlobalConfig.camera.gestures;
            const action = {
                palm: g.palm,
                swipe_left: g.swipeLeft,
                swipe_right: g.swipeRight,
                thumbs_up: g.thumbsUp,
                thumbs_down: g.thumbsDown
            }[name] ?? "none";
            const did = root.runAction(action);
            if (did)
                Toaster.toast(root.gestureNames[name] ?? name, did, name === "palm" ? "back_hand" : name.startsWith("thumbs") ? "thumb_up" : "swipe");
        }

        // Gestures pause for as long as another app shows interest in the camera
        function onSteppedAside(seconds: int): void {
            if (GlobalConfig.camera.gestures.enabled)
                Toaster.toast(Tr.tr("Camera handed over"), Tr.tr("Gestures pause while another app wants the camera"), "videocam");
        }

        target: Camera
    }

    Connections {
        function onPasswordFailed(): void {
            const cfg = GlobalConfig.camera.snapshots;
            root.failures++;
            // A photo when the threshold is reached, and once more if it carries on
            if (!root.available || !cfg.enabled || (root.failures !== cfg.afterFailures && root.failures !== cfg.afterFailures * 2))
                return;
            Camera.snapshot(`${Paths.absolutePath(cfg.dir)}/${root.stamp()}.jpg`, res => {
                if (res.ok)
                    root.photos = [...root.photos, res.path];
            });
        }

        target: root.lock.pam
    }
}
