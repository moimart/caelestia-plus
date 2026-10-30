pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Caelestia
import Caelestia.Config
import Caelestia.I18n
import qs.services

// Window cards: two windows paired into one that flips over (modules/cards
// animates it) to show the other. The side not showing waits on a special
// workspace of its own (special:caelestia-cards, never shown). A flip brings
// it onto the workspace beside the front (inside the front's own slot), swaps
// the two and sends the front away, so the other takes exactly its place.
// (Not a swap straight from the special workspace: Hyprland sometimes leaves
// a window swapped in that way suspended, frozen on its last frame.) They're ordinary windows
// otherwise: their borders, focus and rules as any other's. The pairing lives
// in Hyprland -- both carry the caelestia-card tag and a tag of their pair --
// so it survives shell restarts. The Lua helpers below are installed into
// Hyprland on start and after every config reload.
//
// (Cards used to be locked Hyprland groups without decorations, to hide the
// group's tabs, which took the focus border too. Such pairs are made over
// into the new kind when found.)
Singleton {
    id: root

    readonly property string tag: "caelestia-card"
    readonly property string stash: "special:caelestia-cards"

    // [{ front, back }] of HyprlandToplevels; front is the side showing now
    readonly property var cards: {
        const pairs = {};
        for (const t of Hypr.toplevels.values) {
            const tags = t.lastIpcObject?.tags ?? [];
            const id = tags.map(x => String(x).replace(/\*$/, "")).find(x => x.startsWith(`${tag}-p`));
            if (tags.some(x => String(x).replace(/\*$/, "") === tag) && id)
                (pairs[id] = pairs[id] ?? []).push(t);
        }
        const out = [];
        for (const members of Object.values(pairs)) {
            if (members.length !== 2)
                continue;
            const front = members.find(m => m.lastIpcObject.workspace?.name !== stash) ?? members[0];
            out.push({
                front: front,
                back: members.find(m => m !== front)
            });
        }
        return out;
    }

    // Set while choosing the back of a new card; the front is the focused window
    property HyprlandToplevel pickFront
    readonly property bool picking: pickFront !== null
    // The card being flipped, while the animation runs
    property var flipping: null

    function cardFor(toplevel: HyprlandToplevel): var {
        if (!toplevel)
            return null;
        return cards.find(c => c.front === toplevel || c.back === toplevel) ?? null;
    }

    function isGrouped(toplevel: HyprlandToplevel): bool {
        return (toplevel?.lastIpcObject.grouped?.length ?? 0) > 0;
    }

    // Starts choosing a window to pair with the focused one
    function startPairing(): void {
        if (!usable())
            return;
        Hyprland.refreshToplevels();
        const front = Hypr.activeToplevel;
        if (!front) {
            Toaster.toast(Tr.tr("No window to pair"), Tr.tr("Focus the window that should be the front of the card"), "flip");
            return;
        }
        if (cardFor(front)) {
            Toaster.toast(Tr.tr("Already a card"), Tr.tr("Flip it, or unpair it first"), "flip");
            return;
        }
        if (isGrouped(front)) {
            Toaster.toast(Tr.tr("Window is in a group"), Tr.tr("Take it out of its group to make a card"), "tab_group");
            return;
        }
        pickFront = front;
    }

    function cancelPairing(): void {
        pickFront = null;
    }

    function pair(front: HyprlandToplevel, back: HyprlandToplevel): void {
        pickFront = null;
        if (!front || !back || front === back || isGrouped(front) || isGrouped(back))
            return;
        lua(`caelestia_cards.pair("0x${front.address}", "0x${back.address}", "${tag}-p${Date.now().toString(36)}")`);
    }

    function unpair(toplevel: HyprlandToplevel): void {
        const card = cardFor(toplevel ?? Hypr.activeToplevel);
        if (!card) {
            Toaster.toast(Tr.tr("Not a card"), Tr.tr("Focus a card to unpair it"), "flip");
            return;
        }
        lua(`caelestia_cards.unpair("0x${card.front.address}", "0x${card.back.address}")`);
        Hyprland.refreshToplevels();
    }

    // Asks modules/cards to flip the card holding this (or the focused) window
    function flip(toplevel: HyprlandToplevel): void {
        if (!usable() || flipping)
            return;
        // The focused window is the side showing (a group's hidden window can't
        // have focus); the toplevel list's visibility can lag a flip behind
        // (Hyprland.activeToplevel is only known after a focus change, so fall back
        // to the focus history the toplevel list carries, e.g. right after a restart)
        const target = toplevel ?? Hyprland.activeToplevel ?? Hypr.toplevels.values.find(t => t.lastIpcObject.focusHistoryID === 0) ?? null;
        const card = cardFor(target);
        if (!card) {
            Toaster.toast(Tr.tr("Not a card"), Tr.tr("Pair two windows into a card first"), "flip");
            return;
        }
        const showing = card.back === target || card.front === target ? target : card.front;
        flipping = {
            front: showing,
            back: showing === card.front ? card.back : card.front
        };
    }

    // Steps the animation drives; addresses are taken from the card being flipped
    // Swaps the back into the front's place, the front hidden away, in one go
    function showOther(card: var): void {
        lua(`caelestia_cards.turn("0x${card.front.address}", "0x${card.back.address}")`);
    }

    // Makes a window invisible (or visible again) without Hyprland's fade, by
    // tagging it for the rules install() sets up. Mid-flip a window has no
    // border either: borders are drawn outside the window, where the flip's
    // card doesn't cover, and would flash
    function hide(toplevel: HyprlandToplevel): void {
        lua(`caelestia_cards.hide("0x${toplevel.address}")`);
    }

    function show(toplevel: HyprlandToplevel): void {
        lua(`caelestia_cards.show("0x${toplevel.address}")`);
        settleTimer.addresses = [...settleTimer.addresses, toplevel.address];
        settleTimer.restart();
    }

    function usable(): bool {
        if (!GlobalConfig.cards.enabled)
            return false;
        if (!Hypr.usingLua) {
            Toaster.toast(Tr.tr("Cards need Hyprland's Lua config"), Tr.tr("Window cards use Hyprland 0.55+ Lua"), "flip");
            return false;
        }
        return true;
    }

    // Hyprland's socket takes one line per request, and Lua doesn't need newlines
    // (so no -- comments in the Lua here). Windows go to the stash with
    // follow = false: otherwise Hyprland would open the special workspace.
    function lua(code: string): void {
        Hypr.extras.message(`eval ${code.replace(/\s*\n\s*/g, " ")}`);
    }

    function install(): void {
        if (!Hypr.usingLua)
            return;
        lua(`caelestia_cards = {
  untag = function(x)
    local w = hl.get_window("address:" .. x)
    if not w then return end
    local tags = type(w.tags) == "table" and w.tags or {}
    for _, t in ipairs(tags) do
      t = tostring(t):gsub("%*$", "")
      if t:sub(1, #"${tag}") == "${tag}" then
        hl.dispatch(hl.dsp.window.tag({ tag = "-" .. t, window = "address:" .. x }))
      end
    end
  end,
  pair = function(a, b, id)
    local A, B = hl.get_window("address:" .. a), hl.get_window("address:" .. b)
    if not A or not B or A.group or B.group then return end
    for _, x in ipairs({ a, b }) do
      hl.dispatch(hl.dsp.window.tag({ tag = "+${tag}", window = "address:" .. x }))
      hl.dispatch(hl.dsp.window.tag({ tag = "+" .. id, window = "address:" .. x }))
    end
    hl.dispatch(hl.dsp.window.move({ workspace = "${stash}", window = "address:" .. b, follow = false }))
    hl.dispatch(hl.dsp.focus({ window = "address:" .. a }))
  end,
  hide = function(a)
    hl.dispatch(hl.dsp.window.tag({ tag = "+${tag}-hidden", window = "address:" .. a }))
  end,
  show = function(a)
    hl.dispatch(hl.dsp.window.tag({ tag = "+${tag}-shown", window = "address:" .. a }))
    hl.dispatch(hl.dsp.window.tag({ tag = "-${tag}-hidden", window = "address:" .. a }))
  end,
  turn = function(a, b)
    local A = hl.get_window("address:" .. a)
    if not A or not A.workspace then return end
    hl.dispatch(hl.dsp.window.tag({ tag = "+${tag}-hidden", window = "address:" .. a }))
    hl.dispatch(hl.dsp.window.tag({ tag = "+${tag}-shown", window = "address:" .. b }))
    hl.dispatch(hl.dsp.focus({ window = "address:" .. a }))
    hl.dispatch(hl.dsp.window.move({ workspace = tostring(A.workspace.id), window = "address:" .. b, follow = false }))
    hl.dispatch(hl.dsp.window.swap({ window = "address:" .. a, target = "address:" .. b }))
    hl.dispatch(hl.dsp.window.move({ workspace = "${stash}", window = "address:" .. a, follow = false }))
    hl.dispatch(hl.dsp.focus({ window = "address:" .. b }))
  end,
  settle = function(a)
    hl.dispatch(hl.dsp.window.tag({ tag = "-${tag}-shown", window = "address:" .. a }))
  end,
  release = function(a, ws)
    local w = hl.get_window("address:" .. a)
    if w and w.workspace and w.workspace.name == "${stash}" then
      hl.dispatch(hl.dsp.window.move({ workspace = tostring(ws), window = "address:" .. a, follow = false }))
    end
  end,
  unpair = function(a, b)
    local A, B = hl.get_window("address:" .. a), hl.get_window("address:" .. b)
    caelestia_cards.untag(a)
    caelestia_cards.untag(b)
    if A and B then
      if B.workspace and B.workspace.name == "${stash}" and A.workspace then caelestia_cards.release(b, A.workspace.id) end
      if A.workspace and A.workspace.name == "${stash}" and B.workspace then caelestia_cards.release(a, B.workspace.id) end
    end
  end,
  ungroup = function(a, b)
    local A, B = hl.get_window("address:" .. a), hl.get_window("address:" .. b)
    if A and A.group then
      hl.dispatch(hl.dsp.focus({ window = "address:" .. a }))
      hl.dispatch(hl.dsp.group.lock({ action = "disable" }))
    end
    if A and B and A.group and B.group == A.group then A.group:remove(B) end
    for _, w in ipairs({ A, B }) do
      if w and w.group then hl.dispatch(hl.dsp.group.toggle({ window = "address:" .. w.address })) end
    end
  end,
}
hl.window_rule({ name = "${tag}", match = { tag = "${tag}" }, decorate = true })
hl.window_rule({ name = "${tag}-hidden", match = { tag = "${tag}-hidden" }, opacity = "0 override", no_anim = true, border_size = 0 })
hl.window_rule({ name = "${tag}-shown", match = { tag = "${tag}-shown" }, no_anim = true, border_size = 0 })`);
        // Separate, so an older Hyprland rejecting it can't take the rest down
        lua(`hl.layer_rule({ name = "caelestia-cards", match = { namespace = "caelestia-cards" }, no_anim = true })`);
    }

    // A card whose other window closed is just a lone window again (brought
    // back if it was the one waiting); cards from before, which were groups,
    // become cards of the new kind
    function tidy(): void {
        const paired = new Set();
        for (const c of cards) {
            paired.add(c.front);
            paired.add(c.back);
        }
        const ws = Hyprland.focusedWorkspace?.id ?? 1;
        for (const t of Hypr.toplevels.values) {
            const ipc = t.lastIpcObject;
            if (!ipc?.tags?.some(x => String(x).replace(/\*$/, "") === tag))
                continue;
            const grouped = ipc.grouped ?? [];
            if (grouped.length === 2) {
                if (grouped[0] !== `0x${t.address}`)
                    continue;
                const other = Hypr.toplevels.values.find(o => `0x${o.address}` === grouped[1]);
                const showing = ipc.visible ? t : other;
                const hidden = showing === t ? other : t;
                if (!other)
                    continue;
                lua(`caelestia_cards.ungroup("0x${t.address}", "0x${other.address}")`);
                lua(`caelestia_cards.untag("0x${t.address}")`);
                lua(`caelestia_cards.untag("0x${other.address}")`);
                lua(`caelestia_cards.pair("0x${showing.address}", "0x${hidden.address}", "${tag}-p${Date.now().toString(36)}${t.address.slice(-4)}")`);
            } else if (!paired.has(t)) {
                lua(`caelestia_cards.untag("0x${t.address}")`);
                lua(`caelestia_cards.release("0x${t.address}", ${ws})`);
            }
        }
        Hyprland.refreshToplevels();
    }

    Component.onCompleted: {
        install();
        startTidy.start();
    }

    Connections {
        function onConfigReloaded(): void {
            root.install();
        }

        // At login the shell can start before it knows Hyprland runs Lua
        function onUsingLuaChanged(): void {
            root.install();
        }

        target: Hypr
    }

    Connections {
        function onRawEvent(event: HyprlandEvent): void {
            if (event.name === "closewindow")
                tidyTimer.restart();
        }

        target: Hyprland
    }

    // Once a shown window is back, let it animate normally again
    Timer {
        id: settleTimer

        property var addresses: []

        interval: 600
        onTriggered: {
            for (const a of addresses)
                root.lua(`caelestia_cards.settle("0x${a}")`);
            addresses = [];
        }
    }

    // Once the windows' details are in
    Timer {
        id: startTidy

        interval: 2500
        onTriggered: root.tidy()
    }

    Timer {
        id: tidyTimer

        interval: 300
        onTriggered: root.tidy()
    }
}
