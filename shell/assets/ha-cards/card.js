// One Home Assistant custom card, on a page of its own in headless Chromium
// (see host.py). Ported from docker-home's custom card host: the dashboard's
// resources (the cards' scripts) load from HA through host.py, then the card is
// made the way HA makes it, `el.setConfig(config); el.hass = hass`, with a
// stand-in `hass` whose states come live from HA. The few HA frontend elements
// cards lean on (ha-card, ha-icon...) get small stand-ins.
"use strict";

const BOOT = window.__CAELESTIA_CARD__;
const ENTITY_RE = /^[a-z_]+\.[a-z0-9_]+$/;

// --- Talking to Home Assistant, through host.py -----------------------------

const hub = {
    sock: null,
    nextId: 1,
    waiting: new Map(),
    listeners: new Map(),
    open: null,

    connect() {
        this.open = new Promise((resolve) => {
            this.sock = new WebSocket(`ws://${location.host}/_ws`);
            this.sock.onopen = () => resolve();
            this.sock.onmessage = (e) => this.receive(JSON.parse(e.data));
            this.sock.onclose = () => setTimeout(() => location.reload(), 3000);
        });
    },

    receive(m) {
        if (m.reload) {
            setTimeout(() => location.reload(), 1000);
            return;
        }
        if ("event" in m) {
            this.listeners.get(m.id)?.(m.event);
            return;
        }
        const w = this.waiting.get(m.id);
        if (!w)
            return;
        this.waiting.delete(m.id);
        if ("error" in m)
            w.reject(new Error(m.error));
        else
            w.resolve(m.result);
    },

    async send(msg, listener) {
        await this.open;
        const id = this.nextId++;
        if (listener)
            this.listeners.set(id, listener);
        const p = new Promise((resolve, reject) => this.waiting.set(id, {resolve, reject}));
        this.sock.send(JSON.stringify({id, msg}));
        return {id, result: await p};
    },

    async ws(msg) {
        return (await this.send(msg)).result;
    },

    async subscribeMessage(cb, msg) {
        const {id} = await this.send(msg, cb);
        return async () => {
            this.listeners.delete(id);
            this.sock.send(JSON.stringify({unsub: id}));
        };
    },

    call(domain, service, data, target) {
        return this.ws({type: "call_service", domain, service, service_data: data || {}, target});
    },
};

// --- Live states ---------------------------------------------------------------

const states = {};
const iso = (t) => (t ? new Date(t * 1000).toISOString() : undefined);

function applyEntities(ev) {
    const changed = [];
    for (const [id, s] of Object.entries(ev.a || {})) {
        states[id] = {
            entity_id: id, state: s.s, attributes: s.a || {}, context: s.c,
            last_changed: iso(s.lc), last_updated: iso(s.lu || s.lc),
        };
        changed.push(id);
    }
    for (const [id, d] of Object.entries(ev.c || {})) {
        const cur = states[id];
        if (!cur)
            continue;
        const plus = d["+"] || {};
        const next = {...cur, attributes: {...cur.attributes}};
        if ("s" in plus)
            next.state = plus.s;
        if (plus.a)
            Object.assign(next.attributes, plus.a);
        for (const k of (d["-"] || {}).a || [])
            delete next.attributes[k];
        if (plus.lc) {
            next.last_changed = iso(plus.lc);
            next.last_updated = iso(plus.lc);
        }
        if (plus.lu)
            next.last_updated = iso(plus.lu);
        states[id] = next;
        changed.push(id);
    }
    for (const id of ev.r || []) {
        delete states[id];
        changed.push(id);
    }
    return changed;
}

// --- Stand-ins for HA frontend elements ---------------------------------------

const mdiCache = new Map();
function mdiPath(icon) {
    const key = String(icon || "").replace(/^(mdi|hass):/, "");
    if (!mdiCache.has(key))
        mdiCache.set(key, fetch(`/_mdi/${encodeURIComponent(key)}`).then((r) => (r.ok ? r.text() : null)).catch(() => null));
    return mdiCache.get(key);
}

const DOMAIN_ICON = {
    light: "lightbulb", switch: "toggle-switch-variant", fan: "fan", sensor: "eye", binary_sensor: "checkbox-blank-circle-outline",
    climate: "thermostat", cover: "window-shutter", lock: "lock", media_player: "cast", person: "account", sun: "white-balance-sunny",
    weather: "weather-partly-cloudy", camera: "video", script: "script-text", scene: "palette", automation: "robot",
    input_boolean: "toggle-switch-outline", button: "gesture-tap-button", vacuum: "robot-vacuum",
};
const entityIcon = (s, id) => s?.attributes?.icon || `mdi:${DOMAIN_ICON[(id || "").split(".")[0]] || "bookmark"}`;

function defineOnce(name, ctor) {
    if (!customElements.get(name))
        customElements.define(name, class extends ctor {});
}

const SVG_STYLE = `:host{display:inline-flex;align-items:center;justify-content:center;position:relative;vertical-align:middle;
  fill:currentColor;width:var(--mdc-icon-size,24px);height:var(--mdc-icon-size,24px)}svg{width:100%;height:100%;pointer-events:none;display:block}`;

class SvgIconBase extends HTMLElement {
    constructor() {
        super();
        this.attachShadow({mode: "open"}).innerHTML = `<style>${SVG_STYLE}</style><svg viewBox="0 0 24 24"><path></path></svg>`;
    }
    paint(d) {
        this.shadowRoot.querySelector("path").setAttribute("d", d || "");
    }
}

class HaSvgIcon extends SvgIconBase {
    static observedAttributes = ["path"];
    get path() { return this._path; }
    set path(v) { this._path = v; this.paint(v); }
    attributeChangedCallback(_, __, v) { this.path = v; }
}

class HaIcon extends SvgIconBase {
    static observedAttributes = ["icon"];
    get icon() { return this._icon; }
    set icon(v) {
        this._icon = v || "";
        if (!this._icon) {
            this.paint(null);
            return;
        }
        const want = this._icon;
        mdiPath(want).then((d) => { if (this._icon === want) this.paint(d); });
    }
    attributeChangedCallback(_, __, v) { this.icon = v; }
}

class HaStateIcon extends HaIcon {
    static observedAttributes = ["icon"];
    set stateObj(s) { this._stateObj = s; this.update(); }
    get stateObj() { return this._stateObj; }
    set hass(_) {}
    set stateIcon(v) { this._override = v; this.update(); }
    attributeChangedCallback(_, __, v) { this._override = v; this.update(); }
    update() {
        super.icon = this._override || entityIcon(this._stateObj, this._stateObj?.entity_id);
    }
}

class HaCard extends HTMLElement {
    static observedAttributes = ["header"];
    constructor() {
        super();
        this.attachShadow({mode: "open"}).innerHTML = `<style>
      :host{display:block;position:relative;background:var(--ha-card-background,var(--card-background-color,transparent));
        border-radius:var(--ha-card-border-radius,12px);border:var(--ha-card-border-width,0) solid var(--ha-card-border-color,transparent);
        box-shadow:var(--ha-card-box-shadow,none);color:var(--primary-text-color)}
      .card-header{font-size:var(--ha-card-header-font-size,1.2em);color:var(--ha-card-header-color,var(--primary-text-color));
        padding:12px 16px 4px;font-weight:600}
      .card-header:empty{display:none}
    </style><div class="card-header"></div><slot></slot>`;
    }
    set header(v) { this.shadowRoot.querySelector(".card-header").textContent = v || ""; }
    attributeChangedCallback(_, __, v) { this.header = v; }
}

function relTime(v) {
    const t = new Date(v).getTime();
    if (!t)
        return "";
    const s = Math.round((Date.now() - t) / 1000);
    const f = new Intl.RelativeTimeFormat(navigator.language, {numeric: "auto"});
    if (Math.abs(s) < 60) return f.format(-s, "second");
    if (Math.abs(s) < 3600) return f.format(-Math.round(s / 60), "minute");
    if (Math.abs(s) < 86400) return f.format(-Math.round(s / 3600), "hour");
    return f.format(-Math.round(s / 86400), "day");
}

class HaRelativeTime extends HTMLElement {
    set datetime(v) { this._dt = typeof v === "string" ? v : v?.toISOString?.(); this.render(); }
    connectedCallback() { this.t = setInterval(() => this.render(), 30000); this.render(); }
    disconnectedCallback() { clearInterval(this.t); }
    render() { this.textContent = relTime(this._dt); }
}

class HaIconButton extends HTMLElement {
    static observedAttributes = ["icon", "path", "label"];
    constructor() {
        super();
        this.attachShadow({mode: "open"}).innerHTML = `<style>
      :host{display:inline-flex;--mdc-icon-size:24px}button{all:unset;display:grid;place-items:center;
        width:var(--mdc-icon-button-size,40px);height:var(--mdc-icon-button-size,40px);border-radius:50%;color:inherit}
    </style><button><ha-icon></ha-icon></button>`;
    }
    set icon(v) { this.shadowRoot.querySelector("ha-icon").icon = v; }
    set path(v) {
        const b = this.shadowRoot.querySelector("button");
        b.innerHTML = "";
        const i = document.createElement("ha-svg-icon");
        i.path = v;
        b.appendChild(i);
    }
    set label(v) { this.shadowRoot.querySelector("button").setAttribute("aria-label", v || ""); }
    attributeChangedCallback(n, _, v) { this[n] = v; }
}

class HaSpinner extends HTMLElement {
    constructor() {
        super();
        this.attachShadow({mode: "open"}).innerHTML = `<style>:host{display:inline-block;width:28px;height:28px}
      div{width:100%;height:100%;border-radius:50%;border:3px solid color-mix(in srgb,var(--primary-color) 25%,transparent);
      border-top-color:var(--primary-color)}</style><div></div>`;
    }
}

class HaSwitch extends HTMLElement {
    constructor() {
        super();
        this._checked = false;
        this.attachShadow({mode: "open"}).innerHTML = `<style>
      :host{display:inline-block}span{display:block;width:36px;height:20px;border-radius:10px;position:relative;
        background:color-mix(in srgb,var(--primary-text-color) 25%,transparent)}
      span::after{content:'';position:absolute;top:2px;left:2px;width:16px;height:16px;border-radius:50%;background:#fff}
      :host([checked]) span{background:var(--switch-checked-color,var(--primary-color))}:host([checked]) span::after{transform:translateX(16px)}
    </style><span></span>`;
    }
    get checked() { return this._checked; }
    set checked(v) { this._checked = !!v; this.toggleAttribute("checked", this._checked); }
}

// A built-in card nested in a custom one (stack-in-card and the like): the
// shell draws built-in cards itself, but not inside a picture of another
function unsupported(text) {
    const d = document.createElement("div");
    d.className = "msg";
    d.textContent = text;
    return d;
}

function installShims() {
    defineOnce("ha-svg-icon", HaSvgIcon);
    defineOnce("ha-icon", HaIcon);
    defineOnce("ha-state-icon", HaStateIcon);
    defineOnce("ha-card", HaCard);
    defineOnce("ha-relative-time", HaRelativeTime);
    defineOnce("ha-icon-button", HaIconButton);
    defineOnce("ha-circular-progress", HaSpinner);
    defineOnce("ha-spinner", HaSpinner);
    defineOnce("ha-switch", HaSwitch);
    window.customCards ||= [];
    window.loadCardHelpers ||= async () => ({
        createCardElement(config) {
            const type = String(config?.type || "");
            if (type.startsWith("custom:") && customElements.get(type.slice(7))) {
                const el = document.createElement(type.slice(7));
                try { el.setConfig(config); } catch (e) { console.error(e); }
                return el;
            }
            return unsupported(type);
        },
        createRowElement(config) { return this.createCardElement({type: "entities", entities: [config]}); },
        createHuiElement(config) { return this.createCardElement(config); },
    });
}

function loadResources(resources) {
    installShims();
    const failed = [];
    return Promise.all(resources.map((r) => new Promise((resolve) => {
        if (r.type === "css") {
            const l = document.createElement("link");
            l.rel = "stylesheet";
            l.href = r.url;
            l.onload = l.onerror = () => resolve();
            document.head.appendChild(l);
            return;
        }
        if (r.type === "html") {
            resolve();
            return;
        }
        const s = document.createElement("script");
        if (r.type === "module")
            s.type = "module";
        s.src = r.url;
        s.onload = () => resolve();
        s.onerror = () => { failed.push(r.url); resolve(); };
        document.head.appendChild(s);
    }))).then(() => failed);
}

// --- The `hass` object ---------------------------------------------------------

function buildHass(boot, onAccess) {
    const snapshot = {...states};
    // Reading an entity counts as watching it: its changes repaint the card
    const proxied = new Proxy(snapshot, {
        get(t, k) {
            if (typeof k === "string" && ENTITY_RE.test(k))
                onAccess(k);
            return Reflect.get(t, k);
        },
    });
    const lang = (navigator.language || "en").split("-")[0];
    const dark = matchMedia("(prefers-color-scheme: dark)").matches;
    return {
        states: proxied,
        entities: boot.entities,
        devices: {}, areas: {}, floors: {}, services: {}, panels: {},
        config: boot.config,
        connected: true,
        language: lang,
        selectedLanguage: lang,
        translationMetadata: {fragments: [], translations: {[lang]: {nativeName: lang, isRTL: false}, en: {nativeName: "English", isRTL: false}}},
        locale: {language: lang, number_format: "language", time_format: "language", date_format: "language", first_weekday: "language", time_zone: "local"},
        themes: {darkMode: dark, theme: "caelestia", default_theme: "default", default_dark_theme: null, themes: {}},
        selectedTheme: {theme: "caelestia", dark},
        user: {id: "caelestia", name: "Caelestia", is_admin: false, is_owner: false, credentials: [], mfa_modules: []},
        dockedSidebar: "docked",
        vibrate: false,
        debugConnection: false,
        suspendWhenHidden: true,
        enableShortcuts: false,
        localize: (key) => (String(key).split(".").pop() || "").replace(/_/g, " "),
        hassUrl: (path = "") => path,
        formatEntityState: (s, state) => {
            const v = state ?? s?.state;
            const unit = s?.attributes?.unit_of_measurement;
            return unit && v !== undefined ? `${v} ${unit}` : String(v ?? "");
        },
        formatEntityAttributeValue: (s, attr, value) => {
            const v = value ?? s?.attributes?.[attr];
            if (attr === "brightness" && typeof v === "number")
                return `${Math.round((v / 255) * 100)} %`;
            return Array.isArray(v) ? v.join(", ") : v == null ? "" : String(v);
        },
        formatEntityAttributeName: (_, attr) => attr.replace(/_/g, " ").replace(/^./, (c) => c.toUpperCase()),
        formatEntityName: (s) => s?.attributes?.friendly_name || s?.entity_id,
        callService: (domain, service, data, target) => hub.call(domain, service, data, target),
        callWS: (msg) => hub.ws(msg),
        callApi: async (method, path) => { throw new Error(`callApi ${method} ${path} isn't available here`); },
        fetchWithAuth: (path, init) => fetch(path, init),
        connection: {
            subscribeMessage: (cb, msg) => hub.subscribeMessage(cb, msg),
            sendMessagePromise: (msg) => hub.ws(msg),
            subscribeEvents: async () => () => {},
            addEventListener: () => {},
            removeEventListener: () => {},
            haVersion: boot.config?.version,
        },
    };
}

// --- Fitting the card into the widget ----------------------------------------

// Taller than the widget: shrunk to fit, centred, never stretched
// (the page is zoomed to the screen's scale: the room is in unzoomed pixels)
function fit() {
    const box = document.getElementById("fit");
    box.style.transform = "";
    const room = innerHeight / (parseFloat(document.documentElement.style.zoom) || 1);
    const h = box.scrollHeight;
    const s = h > room ? room / h : 1;
    box.style.transform = s < 1 ? `scale(${s})` : "";
}

// --- The card ------------------------------------------------------------------

async function main() {
    const host = document.getElementById("host");
    const cfg = BOOT.card;
    const tag = String(cfg.type || "").replace(/^custom:/, "");
    const say = (text) => host.replaceChildren(unsupported(text));

    hub.connect();
    say(`Loading ${tag}…`);

    const [config, resources, registry] = await Promise.all([
        hub.ws({type: "get_config"}),
        hub.ws({type: "lovelace/resources"}).catch(() => []),
        hub.ws({type: "config/entity_registry/list_for_display"}).catch(() => ({entities: []})),
    ]);
    const entities = {};
    for (const e of registry.entities || [])
        entities[e.ei] = {entity_id: e.ei, device_id: e.di, area_id: e.ai, name: e.en, icon: e.ic, hidden: e.hn};
    const boot = {config, entities};

    // Every entity the config names, and later every one the card reads
    const watched = new Set();
    const walk = (v) => {
        if (typeof v === "string" && ENTITY_RE.test(v)) watched.add(v);
        else if (Array.isArray(v)) v.forEach(walk);
        else if (v && typeof v === "object") Object.values(v).forEach(walk);
    };
    walk(cfg);

    let el = null;
    let queued = false;
    const push = () => {
        queued = false;
        if (el)
            el.hass = buildHass(boot, (id) => watched.add(id));
    };
    const schedule = () => {
        if (!queued) {
            queued = true;
            setTimeout(push, 100);
        }
    };

    let first = true;
    await hub.subscribeMessage((ev) => {
        const changed = applyEntities(ev);
        if (first || changed.some((id) => watched.has(id)))
            schedule();
        first = false;
    }, {type: "subscribe_entities"});

    const failed = await loadResources(resources);
    if (!customElements.get(tag)) {
        const defined = await Promise.race([
            customElements.whenDefined(tag).then(() => true),
            new Promise((r) => setTimeout(() => r(false), 8000)),
        ]);
        if (!defined) {
            say(failed.length
                ? `${tag} didn't load (${failed.length} resource(s) failed)`
                : `No Home Assistant resource defines ${tag}`);
            return;
        }
    }

    el = document.createElement(tag);
    try {
        el.setConfig?.(structuredClone(cfg));
    } catch (e) {
        say(`Card config error: ${e.message}`);
        return;
    }
    host.replaceChildren(el);
    push();
    new ResizeObserver(fit).observe(host);
    addEventListener("resize", fit);
}

// card.js loads in <head>: the card's box exists once the document does
addEventListener("DOMContentLoaded", () => main().catch((e) => {
    document.getElementById("host").replaceChildren(unsupported(String(e.message || e)));
}));
