pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Google Chrome's and Chromium's colour, from the colour scheme: the nearest
// of Chrome's own colours, through their BrowserThemeColor policy, rewritten
// on every scheme change and picked up by a running browser. The policy files live in root's folders; the one-time
// setup (assets/chrome-theme-setup.sh, with sudo) makes them and hands them to
// you. Until then this does nothing.
Singleton {
    id: root

    readonly property list<string> paths: ["/etc/opt/chrome/policies/managed/caelestia-theme.json", "/etc/chromium/policies/managed/caelestia-theme.json"]
    // Chrome's own colours (its Customize Chrome presets: the swatch, and the
    // seed that makes it), and the one nearest the scheme. Each preset also
    // comes muted (Material's neutral variant), which a policy can't ask for:
    // these are the vivid ones, plus brown and rose, which are muted already
    readonly property var presets: [
        {
            swatch: "#a3c3f5",
            seed: "#08429d"
        },
        {
            swatch: "#71d3c7",
            seed: "#004f48"
        },
        {
            swatch: "#9dd08e",
            seed: "#234f1b"
        },
        {
            swatch: "#d9c261",
            seed: "#524601"
        },
        {
            swatch: "#f9b484",
            seed: "#6e3705"
        },
        {
            swatch: "#d9bdae",
            seed: "#564136",
            muted: true
        },
        {
            swatch: "#f9aebc",
            seed: "#722f40"
        },
        {
            swatch: "#d8bcbf",
            seed: "#554144",
            muted: true
        },
        {
            swatch: "#f1ade5",
            seed: "#673362"
        },
        {
            swatch: "#cfb7fa",
            seed: "#4f3a78"
        }
    ]
    // Nearest by hue as the eye sees it (OKLCH); brown and rose only for a
    // muted scheme, orange and pink otherwise
    readonly property var preset: {
        const key = oklch(Colours.palette.m3primary_paletteKeyColor);
        const muted = key.c < 0.07;
        let best = presets[0];
        let bestScore = Infinity;
        for (const p of presets) {
            const h = oklch(Qt.color(p.swatch)).h;
            const dh = Math.abs(key.h - h);
            const score = Math.min(dh, 360 - dh) + ((p.muted ?? false) === muted ? 0 : 25);
            if (score < bestScore) {
                best = p;
                bestScore = score;
            }
        }
        return best;
    }
    readonly property string colour: preset.seed
    readonly property string text: JSON.stringify({
        BrowserThemeColor: colour
    }, null, 4) + "\n"
    // Whether the setup has been done (for Settings)
    readonly property bool enabled: {
        for (let i = 0; i < files.count; i++)
            if (files.objectAt(i)?.present)
                return true;
        return false;
    }

    // A colour's lightness, chroma and hue (degrees) in OKLCH
    function oklch(c: color): var {
        const lin = v => v <= 0.04045 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4);
        const r = lin(c.r);
        const g = lin(c.g);
        const b = lin(c.b);
        const l = Math.cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b);
        const m = Math.cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b);
        const s = Math.cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b);
        const A = 1.9779984951 * l - 2.428592205 * m + 0.4505937099 * s;
        const B = 0.0259040371 * l + 0.7827717662 * m - 0.808675766 * s;
        return {
            l: 0.2104542553 * l + 0.793617785 * m - 0.0040720468 * s,
            c: Math.hypot(A, B),
            h: (Math.atan2(B, A) * 180 / Math.PI + 360) % 360
        };
    }

    Instantiator {
        id: files

        model: root.paths

        FileView {
            required property string modelData
            property bool present
            readonly property string wanted: root.text

            function sync(): void {
                if (present && /^#[0-9a-f]{6}$/i.test(root.colour) && text() !== root.text)
                    setText(root.text);
            }

            path: modelData
            // In place: the file is yours, its folder root's (a safe write
            // goes through a new file in the folder)
            atomicWrites: false
            printErrors: false
            watchChanges: true
            onFileChanged: reload()
            onLoaded: {
                present = true;
                sync();
            }
            onLoadFailed: present = false
            onWantedChanged: sync()
        }
    }

    // A file that isn't there can't be watched: they're looked for again
    // until they are (the setup is usually run while the shell is)
    Timer {
        running: !root.enabled
        repeat: true
        interval: 5000
        onTriggered: {
            for (let i = 0; i < files.count; i++)
                files.objectAt(i)?.reload();
        }
    }
}
