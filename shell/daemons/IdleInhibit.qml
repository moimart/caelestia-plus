import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Caelestia.Services
import Caelestia.State

Scope {
    id: root

    Connections {
        function onInhibitIdleChanged(): void {
            if (RuntimeState.inhibitIdle)
                RuntimeState.inhibitingIdleSince = new Date().getTime();
        }

        target: RuntimeState
    }

    // For other programs that watch for idle, like hypridle. The compositor only
    // honours an inhibitor on a surface it can see, so this takes a real (if
    // invisible) window: 0 x 0 never appears. The shell's own idle steps don't
    // rely on it (IdleMonitors).
    LazyLoader {
        active: RuntimeState.inhibitIdle

        Scope {
            PanelWindow {
                id: inhibitWindow

                implicitWidth: 1
                implicitHeight: 1
                color: "transparent"
                exclusionMode: ExclusionMode.Ignore
                mask: Region {}
                WlrLayershell.namespace: "caelestia-keep-awake"
            }

            IdleInhibitor {
                enabled: true
                window: inhibitWindow
            }
        }
    }

    // The system's own idle sleep and other users' requests: those don't go
    // through the compositor
    Binding {
        target: SessionManager
        property: "holdSleep"
        value: RuntimeState.inhibitIdle
    }

    IpcHandler {
        function isEnabled(): bool {
            return RuntimeState.inhibitIdle;
        }

        function toggle(): void {
            RuntimeState.inhibitIdle = !RuntimeState.inhibitIdle;
        }

        function enable(): void {
            RuntimeState.inhibitIdle = true;
        }

        function disable(): void {
            RuntimeState.inhibitIdle = false;
        }

        target: "idleInhibitor"
    }
}
