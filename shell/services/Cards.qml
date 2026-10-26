pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Caelestia
import Caelestia.Config
import Caelestia.I18n
import qs.services

// Window cards: two windows paired into one Hyprland group that flips over
// (modules/cards animates it) to show the other. The pairing lives entirely in
// Hyprland -- a two-window group whose members carry the caelestia-card tag
// and no decorations -- so it survives shell restarts. The Lua helpers below
// are installed into Hyprland on start and after every config reload.
Singleton {
    id: root

    readonly property string tag: "caelestia-card"

    // [{ front, back }] of HyprlandToplevels; front is the side showing now
    readonly property var cards: {
        const byAddr = {};
        for (const t of Hypr.toplevels.values)
            byAddr[`0x${t.address}`] = t;
        const out = [];
        const seen = new Set();
        for (const t of Hypr.toplevels.values) {
            const ipc = t.lastIpcObject;
            if (!ipc?.tags?.includes(tag) || seen.has(t.address))
                continue;
            const members = (ipc.grouped ?? []).map(a => byAddr[a]).filter(m => m);
            members.forEach(m => seen.add(m.address));
            if (members.length !== 2)
                continue;
            const front = members.find(m => m.lastIpcObject.visible) ?? members[0];
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
        lua(`caelestia_cards.pair("0x${front.address}", "0x${back.address}")`);
    }

    function unpair(toplevel: HyprlandToplevel): void {
        const card = cardFor(toplevel ?? Hypr.activeToplevel);
        if (!card) {
            Toaster.toast(Tr.tr("Not a card"), Tr.tr("Focus a card to unpair it"), "flip");
            return;
        }
        lua(`caelestia_cards.unpair("0x${card.front.address}", "0x${card.back.address}")`);
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
    // Hides the front (so Hyprland's group switch can't ghost it) and shows the back, in one go
    function showOther(card: var): void {
        lua(`caelestia_cards.turn("0x${card.front.address}")`);
    }

    // Makes a window invisible (or visible again) without Hyprland's fade, by
    // tagging it for the rules install() sets up
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
            Toaster.toast(Tr.tr("Cards need Hyprland's Lua config"), Tr.tr("Window cards use Hyprland 0.55+ Lua groups"), "flip");
            return false;
        }
        return true;
    }

    // Hyprland's socket takes one line per request, and Lua doesn't need newlines
    // (so no -- comments in the Lua here). The card group is locked when paired,
    // or group:auto_group would drop newly opened windows into it.
    function lua(code: string): void {
        Hypr.extras.message(`eval ${code.replace(/\s*\n\s*/g, " ")}`);
    }

    function install(): void {
        if (!Hypr.usingLua)
            return;
        lua(`caelestia_cards = {
  pair = function(a, b)
    local A, B = hl.get_window("address:" .. a), hl.get_window("address:" .. b)
    if not A or not B or A.group or B.group then return end
    hl.dispatch(hl.dsp.group.toggle({ window = "address:" .. a }))
    if not A.group then return end
    A.group:add(B)
    for _, x in ipairs({ a, b }) do
      hl.dispatch(hl.dsp.window.tag({ tag = "+${tag}", window = "address:" .. x }))
    end
    hl.dispatch(hl.dsp.group.active({ index = 1, window = "address:" .. a }))
    hl.dispatch(hl.dsp.focus({ window = "address:" .. a }))
    hl.dispatch(hl.dsp.group.lock_active({ action = "enable" }))
  end,
  hide = function(a)
    hl.dispatch(hl.dsp.window.tag({ tag = "+${tag}-hidden", window = "address:" .. a }))
  end,
  show = function(a)
    hl.dispatch(hl.dsp.window.tag({ tag = "+${tag}-shown", window = "address:" .. a }))
    hl.dispatch(hl.dsp.window.tag({ tag = "-${tag}-hidden", window = "address:" .. a }))
  end,
  turn = function(a)
    hl.dispatch(hl.dsp.window.tag({ tag = "+${tag}-hidden", window = "address:" .. a }))
    hl.dispatch(hl.dsp.group.next({ window = "address:" .. a }))
  end,
  settle = function(a)
    hl.dispatch(hl.dsp.window.tag({ tag = "-${tag}-shown", window = "address:" .. a }))
  end,
  unpair = function(a, b)
    for _, x in ipairs({ a, b }) do
      if hl.get_window("address:" .. x) then
        for _, t in ipairs({ "${tag}", "${tag}-hidden", "${tag}-shown" }) do
          hl.dispatch(hl.dsp.window.tag({ tag = "-" .. t, window = "address:" .. x }))
        end
      end
    end
    local A, B = hl.get_window("address:" .. a), hl.get_window("address:" .. b)
    if A and A.group then
      hl.dispatch(hl.dsp.focus({ window = "address:" .. a }))
      hl.dispatch(hl.dsp.group.lock_active({ action = "disable" }))
    end
    if A and B and A.group and B.group == A.group then A.group:remove(B) end
    for _, w in ipairs({ A, B }) do
      if w and w.group then hl.dispatch(hl.dsp.group.toggle({ window = "address:" .. w.address })) end
    end
  end,
}
hl.window_rule({ name = "${tag}", match = { tag = "${tag}" }, decorate = false })
hl.window_rule({ name = "${tag}-hidden", match = { tag = "${tag}-hidden" }, opacity = "0 override", no_anim = true })
hl.window_rule({ name = "${tag}-shown", match = { tag = "${tag}-shown" }, no_anim = true })`);
        // Separate, so an older Hyprland rejecting it can't take the rest down
        lua(`hl.layer_rule({ name = "caelestia-cards", match = { namespace = "caelestia-cards" }, no_anim = true })`);
    }

    // A card whose other window closed is just a lone window again
    function tidy(): void {
        for (const t of Hypr.toplevels.values) {
            const ipc = t.lastIpcObject;
            if (ipc?.tags?.includes(tag) && (ipc.grouped?.length ?? 0) < 2)
                lua(`caelestia_cards.unpair("0x${t.address}", "")`);
        }
    }

    Component.onCompleted: install()

    Connections {
        function onConfigReloaded(): void {
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

    Timer {
        id: tidyTimer

        interval: 300
        onTriggered: root.tidy()
    }
}
