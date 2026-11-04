pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import Caelestia.I18n
import Caelestia.Services
import qs.components
import qs.components.controls
import qs.services
import qs.utils

// A performance dial, as in the dashboard's Performance tab: how busy the CPU
// or GPU is, or how full the memory or a disk. On the desktop it's the
// dashboard's gauge, drawn at the widget's size (not stretched); in a bar
// (bar: "left"/"right") it's a small ring with the figure under it.
//
// Its service only runs while something shows it (ServiceRef), and nothing
// here animates between readings unless asked: the window it's in is redrawn
// whole for every frame of an animation.
//
// Settings: animate, background, backgroundOpacity (%), disk (storage: a mount
// point, the dashboard's disk otherwise)
Item {
    id: root

    // "cpu", "gpu", "memory" or "storage"
    required property string resource
    property var settings: ({})
    property string bar
    property bool editing

    readonly property bool inBar: bar !== ""
    readonly property var disk: {
        const mount = settings.disk ?? "";
        return (mount ? Storage.disks.find(d => d.mount === mount) : null) ?? Storage.primaryDisk ?? null;
    }
    readonly property bool hasGpu: Gpu.type !== GpuType.None

    readonly property var spec: ({
            cpu: {
                icon: "memory",
                label: Tr.tr("CPU"),
                accent: Colours.palette.m3primary
            },
            gpu: {
                icon: "desktop_windows",
                label: Tr.tr("GPU"),
                accent: Colours.palette.m3secondary
            },
            memory: {
                icon: "memory_alt",
                label: Tr.tr("Memory"),
                accent: Colours.palette.m3tertiary
            },
            storage: {
                icon: "hard_drive",
                label: Tr.tr("Storage"),
                accent: Colours.palette.m3secondary
            }
        })[resource] ?? {
        icon: "help",
        label: resource,
        accent: Colours.palette.m3primary
    }

    // 0-1, NaN while there's no reading
    readonly property real value: {
        switch (resource) {
        case "cpu":
            return Cpu.percentage;
        case "gpu":
            return hasGpu ? Gpu.percentage : NaN;
        case "memory":
            return Memory.percentage;
        case "storage":
            return disk?.perc ?? NaN;
        }
        return NaN;
    }
    // Under the figure: the temperature, or how much is used of how much
    readonly property real temperature: resource === "cpu" ? HostSensors.cpuTemperature : resource === "gpu" ? Gpu.temperature : NaN
    readonly property string detail: {
        switch (resource) {
        case "cpu":
        case "gpu":
            return temperature > 0 ? Units.formatSensorTemp(temperature) : "";
        case "memory":
            return Memory.total > 0 ? Units.formatKibUsage(Memory.used, Memory.total) : "";
        case "storage":
            return disk ? Units.formatKibUsage(disk.used, disk.total) : Tr.tr("No disks detected");
        }
        return "";
    }
    readonly property string figure: isNaN(value) ? (resource === "gpu" && !hasGpu && !Gpu.detecting ? Tr.trCtx("None", "GPU name") : "…") : Strings.percentOne(value)
    readonly property bool hot: temperature > 90
    readonly property bool animate: settings.animate ?? false

    // Fits the desktop face into the widget's box, like the clock
    readonly property real fitScale: Math.max(0.1, Math.min(width / Math.max(1, measure.implicitWidth), height / Math.max(1, measure.implicitHeight)))

    implicitWidth: inBar ? Tokens.sizes.bar.innerWidth : 200
    implicitHeight: inBar ? barFace.implicitHeight : 230

    ServiceRef {
        service: root.resource === "cpu" ? Cpu : root.resource === "gpu" ? Gpu : root.resource === "memory" ? Memory : Storage
    }

    // In a bar: a ring with the icon, the figure under it
    Column {
        id: barFace

        anchors.horizontalCenter: parent.horizontalCenter
        visible: root.inBar
        spacing: Tokens.spacing.extraSmall / 2

        CircularProgress {
            id: barRing

            anchors.horizontalCenter: parent.horizontalCenter
            implicitSize: Tokens.sizes.bar.innerWidth - Tokens.padding.small
            startAngle: -225
            sweepAngle: 270
            strokeWidth: Math.max(2, Tokens.padding.extraSmall)
            spacing: Tokens.spacing.extraSmall
            fgColour: root.hot ? Colours.palette.m3error : root.spec.accent
            value: root.inBar ? root.value : 0

            Behavior on clampedVal {
                enabled: root.animate

                Anim {}
            }

            MaterialIcon {
                anchors.centerIn: parent
                anchors.verticalCenterOffset: Tokens.padding.extraSmall / 2
                text: root.spec.icon
                color: barRing.fgColour
                fontStyle: Tokens.font.icon.small
            }
        }

        StyledText {
            anchors.horizontalCenter: parent.horizontalCenter
            // Short, to fit the bar: "42%"
            text: isNaN(root.value) ? "–" : `${Math.round(root.value * 100)}%`
            color: Colours.palette.m3onSurface
            font: Tokens.font.label.small
        }
    }

    // On the desktop: measured at scale 1, drawn at the widget's size
    Face {
        id: measure

        visible: false
        faceScale: 1
    }

    Face {
        anchors.centerIn: parent
        visible: !root.inBar
        faceScale: root.fitScale
    }

    component Face: Item {
        id: face

        property real faceScale: 1

        implicitWidth: layout.implicitWidth + Tokens.padding.extraLarge * 2 * faceScale
        implicitHeight: layout.implicitHeight + Tokens.padding.large * 2 * faceScale
        width: implicitWidth
        height: implicitHeight

        StyledRect {
            anchors.fill: parent
            visible: root.settings.background ?? true
            radius: Tokens.rounding.extraLarge * face.faceScale
            color: Colours.palette.m3surfaceContainer
            opacity: (root.settings.backgroundOpacity ?? 85) / 100
        }

        ColumnLayout {
            id: layout

            anchors.centerIn: parent
            spacing: Tokens.spacing.small * face.faceScale

            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                spacing: Tokens.spacing.small * face.faceScale

                MaterialIcon {
                    text: root.spec.icon
                    fill: 1
                    color: root.spec.accent
                    fontStyle: Tokens.font.icon.builders.medium.scale(face.faceScale).build()
                }

                StyledText {
                    text: root.resource === "storage" && root.disk && root.settings.disk ? root.disk.mount : root.spec.label
                    font: Tokens.font.title.builders.medium.scale(face.faceScale).build()
                    color: Colours.palette.m3onSurface
                }
            }

            CircularProgress {
                id: ring

                Layout.alignment: Qt.AlignHCenter
                implicitSize: (figureColumn.implicitHeight + Tokens.padding.extraLarge * 2.4 * face.faceScale) + thickness
                startAngle: -225
                sweepAngle: 270
                strokeWidth: Tokens.padding.small * face.faceScale
                spacing: Tokens.spacing.small * face.faceScale
                fgColour: root.hot ? Colours.palette.m3error : root.spec.accent
                value: root.value

                Behavior on clampedVal {
                    enabled: root.animate

                    Anim {}
                }

                ColumnLayout {
                    id: figureColumn

                    anchors.centerIn: parent
                    anchors.verticalCenterOffset: Tokens.padding.extraSmall * face.faceScale
                    spacing: 0

                    StyledText {
                        Layout.alignment: Qt.AlignHCenter
                        text: root.figure
                        font: Tokens.font.title.builders.large.scale(1.15 * face.faceScale).width(90).build()
                        color: ring.fgColour
                    }

                    StyledText {
                        Layout.alignment: Qt.AlignHCenter
                        text: root.resource === "cpu" || root.resource === "gpu" ? Tr.trCtx("Usage", "resource usage") : Tr.trCtx("Used", "memory used")
                        font: Tokens.font.body.builders.small.scale(face.faceScale).build()
                        color: Colours.palette.m3onSurfaceVariant
                    }
                }
            }

            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                visible: root.detail !== ""
                spacing: Tokens.spacing.extraSmall * face.faceScale

                MaterialIcon {
                    visible: root.resource === "cpu" || root.resource === "gpu"
                    text: root.hot ? "thermometer_alert" : "thermometer"
                    fill: 1
                    color: root.hot ? Colours.palette.m3error : root.spec.accent
                    fontStyle: Tokens.font.icon.builders.small.scale(face.faceScale).build()
                }

                StyledText {
                    text: root.detail
                    font: Tokens.font.body.builders.medium.scale(face.faceScale).build()
                    color: Colours.palette.m3onSurface
                }
            }
        }
    }
}
