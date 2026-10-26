pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Caelestia.Config
import Caelestia.I18n
import qs.components
import qs.components.controls
import qs.services
import qs.modules.nexus.common

// Displays, like macOS's: the arrangement on top, then the selected display's
// resolution, refresh rate, scale, rotation, VRR, mirroring, and whether the
// shell (bar, wallpaper, widgets) runs on it.
PageBase {
    id: root

    property string selected: Hypr.focusedMonitor?.name ?? Displays.monitors[0]?.name ?? ""
    readonly property var m: Displays.monitor(selected)
    readonly property var mode: m ? Displays.currentMode(m) : null
    readonly property bool mirroring: !!m && !!m.mirrorOf && m.mirrorOf !== "none"
    // Displays that are on; the last one can't be turned off
    readonly property int onCount: Displays.monitors.filter(d => !d.disabled).length
    // Screens with the shell; the last one keeps it
    readonly property int shellCount: Displays.monitors.filter(d => GlobalConfig.forScreen(d.name).enabled).length
    readonly property bool shellHere: !!m && GlobalConfig.forScreen(m.name).enabled

    function rateText(rate: real): string {
        return Tr.tr("%1 Hz").arg(Math.abs(rate - Math.round(rate)) < 0.02 ? Math.round(rate) : rate.toFixed(2));
    }

    function scaleText(scale: real): string {
        const s = Math.round(scale * 100) / 100;
        return `×${s}`;
    }

    // A new resolution: the same refresh rate if it has it (else its fastest),
    // and a scale that still divides it into whole pixels
    function pickResolution(width: int, height: int): void {
        const rates = Displays.rates(m, width, height);
        if (rates.length === 0)
            return;
        const same = rates.find(r => Math.abs(r.rate - (mode?.rate ?? 0)) < 0.5) ?? rates[0];
        const fields = {
            mode: same.mode
        };
        const valid = Displays.scalesFor(width, height);
        if (!valid.some(s => Math.abs(s - m.scale) < 0.001))
            fields.scale = valid.reduce((a, b) => Math.abs(b - m.scale) < Math.abs(a - m.scale) ? b : a, 1);
        Displays.change(m.name, fields);
    }

    title: Tr.tr("Displays")

    Component.onCompleted: Displays.refresh()

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        ConnectedRect {
            Layout.fillWidth: true
            first: true
            last: true
            implicitHeight: arrangement.implicitHeight

            Arrangement {
                id: arrangement

                anchors.fill: parent
                selected: root.selected
                onPicked: name => root.selected = name
            }
        }

        StyledText {
            Layout.fillWidth: true
            Layout.topMargin: Tokens.spacing.small
            Layout.leftMargin: Tokens.padding.large
            visible: Displays.monitors.length > 1
            text: Tr.tr("Drag a display to arrange it; it snaps against the others.")
            color: Colours.palette.m3outline
            font: Tokens.font.label.small
            wrapMode: Text.WordWrap
        }

        // Every display, also the ones that are off or mirroring
        SectionHeader {
            text: Tr.tr("Displays")
        }

        Repeater {
            model: Displays.monitors

            RowButton {
                id: displayRow

                required property var modelData
                required property int index

                Layout.fillWidth: true
                first: index === 0
                last: index === Displays.monitors.length - 1
                icon: modelData.disabled ? "desktop_access_disabled" : "monitor"
                text: `${modelData.name}: ${[modelData.make, modelData.model].filter(s => s).join(" ") || modelData.description}`
                subtext: {
                    const d = modelData;
                    if (d.disabled)
                        return Tr.tr("Off");
                    if (d.mirrorOf && d.mirrorOf !== "none")
                        return Tr.tr("Mirroring %1").arg(d.mirrorOf);
                    const parts = [`${d.width} × ${d.height}`, root.rateText(d.refreshRate), root.scaleText(d.scale)];
                    if (!GlobalConfig.forScreen(d.name).enabled)
                        parts.push(Tr.tr("no shell"));
                    return parts.join(" · ");
                }
                trailingIcon: root.selected === modelData.name ? "check" : ""
                onClicked: root.selected = modelData.name
            }
        }

        SectionHeader {
            visible: !!root.m
            text: root.m ? root.m.name : ""
        }

        ToggleRow {
            visible: !!root.m
            first: true
            text: Tr.tr("Use this display")
            subtext: root.onCount <= 1 && !root.m?.disabled ? Tr.tr("The only display that's on") : Tr.tr("When off, it gets no picture")
            enabled: !(root.onCount <= 1 && !root.m?.disabled)
            checked: !!root.m && !root.m.disabled
            onToggled: Displays.change(root.m.name, {
                disabled: !checked
            })
        }

        ToggleRow {
            visible: !!root.m
            text: Tr.tr("Caelestia shell on this display")
            subtext: root.shellHere && root.shellCount <= 1 ? Tr.tr("The only display with the shell") : Tr.tr("The bar, wallpaper, widgets and panels")
            enabled: !(root.shellHere && root.shellCount <= 1)
            checked: root.shellHere
            onToggled: Displays.setShell(root.m.name, checked)
        }

        SelectRow {
            visible: !!root.m && !root.m.disabled
            label: Tr.tr("Mirror")
            subtext: Tr.tr("Show another display's picture instead")
            menuItems: [noMirror, ...mirrorItems.instances]
            active: root.mirroring ? (mirrorItems.instances.find(i => i.value === root.m.mirrorOf) ?? noMirror) : noMirror
            onSelected: item => Displays.change(root.m.name, {
                    mirror: item.value
                })

            MenuItem {
                id: noMirror

                text: Tr.tr("Off")
                value: ""
            }

            Variants {
                id: mirrorItems

                model: Displays.monitors.filter(d => d.name !== root.selected && !d.disabled && (!d.mirrorOf || d.mirrorOf === "none"))

                MenuItem {
                    required property var modelData

                    text: modelData.name
                    value: modelData.name
                }
            }
        }

        SelectRow {
            visible: !!root.m && !root.m.disabled && !root.mirroring
            label: Tr.tr("Resolution")
            menuItems: resolutionItems.instances
            active: resolutionItems.instances.find(i => i.value === `${root.m?.width}x${root.m?.height}`) ?? null
            fallbackText: root.m ? `${root.m.width} × ${root.m.height}` : ""
            onSelected: item => {
                const [w, h] = item.value.split("x").map(Number);
                root.pickResolution(w, h);
            }

            Variants {
                id: resolutionItems

                model: root.m ? Displays.resolutions(root.m) : []

                MenuItem {
                    required property var modelData

                    text: `${modelData.width} × ${modelData.height}`
                    value: `${modelData.width}x${modelData.height}`
                }
            }
        }

        SelectRow {
            visible: !!root.m && !root.m.disabled && !root.mirroring
            label: Tr.tr("Refresh rate")
            menuItems: rateItems.instances
            active: rateItems.instances.find(i => i.value === root.mode?.mode) ?? null
            fallbackText: root.m ? root.rateText(root.m.refreshRate) : ""
            onSelected: item => Displays.change(root.m.name, {
                    mode: item.value
                })

            Variants {
                id: rateItems

                model: root.m ? Displays.rates(root.m, root.m.width, root.m.height) : []

                MenuItem {
                    required property var modelData

                    text: root.rateText(modelData.rate)
                    value: modelData.mode
                }
            }
        }

        SelectRow {
            visible: !!root.m && !root.m.disabled && !root.mirroring
            label: Tr.tr("Scale")
            subtext: root.m ? Tr.tr("Looks like %1 × %2").arg(Displays.logicalSize(root.m).width).arg(Displays.logicalSize(root.m).height) : ""
            menuItems: scaleItems.instances
            active: scaleItems.instances.find(i => Math.abs(i.value - (root.m?.scale ?? 0)) < 0.001) ?? null
            fallbackText: root.m ? root.scaleText(root.m.scale) : ""
            onSelected: item => Displays.change(root.m.name, {
                    scale: item.value
                })

            Variants {
                id: scaleItems

                model: root.m ? Displays.scalesFor(root.m.width, root.m.height) : []

                MenuItem {
                    required property real modelData

                    text: `${root.scaleText(modelData)}  (${Math.round(root.m.width / modelData)} × ${Math.round(root.m.height / modelData)})`
                    value: modelData
                }
            }
        }

        SelectRow {
            visible: !!root.m && !root.m.disabled && !root.mirroring
            label: Tr.tr("Rotation")
            menuItems: rotationItems.instances
            active: rotationItems.instances.find(i => i.value === (root.m?.transform ?? 0)) ?? null
            onSelected: item => Displays.change(root.m.name, {
                    transform: item.value
                })

            Variants {
                id: rotationItems

                model: [Tr.tr("Standard"), Tr.tr("90°"), Tr.tr("180°"), Tr.tr("270°")].map((text, i) => ({
                            text: text,
                            transform: i
                        }))

                MenuItem {
                    required property var modelData

                    text: modelData.text
                    value: modelData.transform
                }
            }
        }

        ToggleRow {
            visible: !!root.m && !root.m.disabled && !root.mirroring
            text: Tr.tr("Variable refresh rate")
            subtext: Tr.tr("Adaptive sync (FreeSync, G-Sync compatible)")
            checked: !!root.m?.vrr
            onToggled: Displays.change(root.m.name, {
                vrr: checked ? 1 : 0
            })
        }

        InfoRow {
            visible: !!root.m
            last: !(root.m && Displays.isCustomised(root.m.name))
            label: Tr.tr("Display")
            value: root.m ? (root.m.description || root.m.name) : ""
        }

        RowButton {
            visible: !!root.m && Displays.isCustomised(root.m.name)
            Layout.fillWidth: true
            last: true
            icon: "restart_alt"
            text: Tr.tr("Reset to the config's settings")
            subtext: Tr.tr("Forget what you changed here; back to your Hyprland config's rule")
            onClicked: Displays.reset(root.m.name)
        }
    }
}
