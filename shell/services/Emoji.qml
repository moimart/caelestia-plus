pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Caelestia
import Caelestia.I18n
import qs.services
import qs.utils

// The emoji picker's data: every emoji (assets/emoji/emoji.json, built by
// make-emoji.py), search, recently used, remembered skin tones, and typing the
// chosen emoji into the app that had focus.
Singleton {
    id: root

    property bool panelOpen
    property bool loaded
    // [{ name, icon, emojis: [{ e, n, k, v? }] }]
    property var groups: []
    // { emoji: { count, last } }
    property var recent: ({})
    // { base emoji: skin tone index 0-5 (0 = none) }, and the last tone picked
    property var tones: ({})
    property int lastTone: 0
    // An emoji waiting for the picker to close before it's typed
    property bool pending
    // The window that had focus when the picker opened: it gets the emoji
    property string target
    property string targetClass
    // Ctrl+V doesn't paste in terminals, but typing works there
    readonly property var terminals: ["kitty", "foot", "footclient", "alacritty", "org.wezfurlong.wezterm", "com.mitchellh.ghostty", "konsole", "org.kde.konsole", "org.gnome.console", "org.gnome.terminal", "gnome-terminal-server", "xterm", "urxvt", "st", "st-256color", "tilix", "terminator", "ptyxis", "org.gnome.ptyxis"]

    // Most used first, recent use breaking ties
    readonly property var recentEmojis: {
        const byEmoji = {};
        for (const g of groups)
            for (const e of g.emojis)
                byEmoji[e.e] = e;
        return Object.keys(recent).filter(e => byEmoji[e]).sort((a, b) => score(recent[b]) - score(recent[a])).slice(0, 27).map(e => byEmoji[e]);
    }

    readonly property var icons: ({
            "Smileys & Emotion": "mood",
            "People & Body": "emoji_people",
            "Animals & Nature": "pets",
            "Food & Drink": "restaurant",
            "Travel & Places": "flight",
            "Activities": "sports_soccer",
            "Objects": "lightbulb",
            "Symbols": "emoji_symbols",
            "Flags": "flag"
        })

    function score(r: var): real {
        // A use counts half as much after a week
        const days = (Date.now() - r.last) / 86400000;
        return r.count * Math.pow(0.5, days / 7);
    }

    // The emoji as it should be typed: with its remembered skin tone
    function toned(e: var): string {
        const t = tones[e.e] ?? 0;
        return t > 0 && e.v ? e.v[t - 1] : e.e;
    }

    function search(text: string): var {
        const words = text.toLowerCase().split(/\s+/).filter(w => w);
        if (words.length === 0)
            return [];
        const hits = [];
        for (const g of groups)
            for (const e of g.emojis) {
                const name = e.n.toLowerCase();
                let s = 0;
                for (const w of words) {
                    if (name === w)
                        s += 6;
                    else if (name.startsWith(w))
                        s += 4;
                    else if (` ${name}`.includes(` ${w}`))
                        s += 3;
                    else if (` ${e.k}`.includes(` ${w}`))
                        s += 2;
                    else if (name.includes(w) || e.k.includes(w))
                        s += 1;
                    else {
                        s = 0;
                        break;
                    }
                }
                if (s > 0)
                    hits.push({
                        e: e,
                        s: s + (recent[e.e] ? 1 : 0)
                    });
            }
        return hits.sort((a, b) => b.s - a.s).map(h => h.e);
    }

    function setTone(e: var, tone: int): void {
        const t = Object.assign({}, tones);
        t[e.e] = tone;
        tones = t;
        lastTone = tone;
        save();
    }

    // Closes the picker, then types the emoji into the window that had focus
    function insert(e: var): void {
        const r = Object.assign({}, recent);
        r[e.e] = {
            count: (r[e.e]?.count ?? 0) + 1,
            last: Date.now()
        };
        recent = r;
        save();
        type(toned(e));
    }

    // The picker holds the keyboard until its window is gone, so while it's
    // open, typing waits for it to close (EmojiPanel calls flush())
    function type(text: string): void {
        typer.text = text;
        if (!panelOpen)
            targetClass = Hypr.activeToplevel?.lastIpcObject.class ?? "";
        typer.mode = terminals.includes(targetClass.toLowerCase()) ? "wtype" : "paste";
        if (panelOpen) {
            pending = true;
            panelOpen = false;
        } else {
            typeTimer.restart();
        }
    }

    function flush(): void {
        if (!pending)
            return;
        pending = false;
        // Hyprland doesn't hand the keyboard back after an exclusive layer
        // closes, so focus the window again, then type once it has settled
        if (target)
            Hypr.dispatch(Hypr.usingLua ? `hl.dsp.focus({ window = "address:0x${target}" })` : `focuswindow address:0x${target}`);
        typeTimer.restart();
    }

    // No wtype (or it failed): leave it on the clipboard instead
    function copyInstead(text: string, missing: bool): void {
        Quickshell.clipboardText = text;
        Toaster.toast(Tr.tr("Emoji copied"), missing ? Tr.tr("Install wtype to type emoji straight into apps") : Tr.tr("Couldn't type it; paste it with Ctrl+V"), "content_copy");
    }

    function save(): void {
        stateFile.setText(JSON.stringify({
            recent: recent,
            tones: tones,
            lastTone: lastTone
        }));
    }

    function ensureLoaded(): void {
        if (!loaded)
            dataFile.reload();
    }

    FileView {
        id: dataFile

        path: Quickshell.shellPath("assets/emoji/emoji.json")
        blockLoading: false
        onLoaded: {
            const data = JSON.parse(text());
            root.groups = data.groups.map(g => Object.assign({
                    icon: root.icons[g.name] ?? "category"
                }, g));
            root.loaded = true;
        }
    }

    FileView {
        id: stateFile

        path: `${Paths.state}/emoji.json`
        printErrors: false
        onLoaded: {
            try {
                const s = JSON.parse(text());
                root.recent = s.recent ?? {};
                root.tones = s.tones ?? {};
                root.lastTone = s.lastTone ?? 0;
            } catch (e) {}
        }
    }

    Timer {
        id: typeTimer

        interval: 150
        onTriggered: typer.running = true
    }

    // Types it with wtype, or pastes it (see type-emoji.sh)
    Process {
        id: typer

        property string text
        property string mode

        command: ["sh", Quickshell.shellPath("assets/emoji/type-emoji.sh"), mode, text]
        onExited: code => {
            if (code === 0)
                return;
            root.copyInstead(text, code === 127);
        }
    }
}
