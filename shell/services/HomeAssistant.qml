pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import QtQml
import Quickshell
import Quickshell.Io
import Caelestia.Config
import qs.utils

// Home Assistant instances, one or more, each through its own bridge
// (assets/ha-bridge.py): one WebSocket to it, live states for the entities
// something here shows, service calls, its dashboards and their cards.
//
// The instances are in ~/.config/caelestia/home-assistant.json:
//   { "instances": [{ "id", "name", "url", "tokenFile" }],
//     "shortcuts": [{ "id", "instance", "entity", "name", "icon" }] }
// (shortcuts are buttons for the right bar: they act like tapping the entity)
// Tokens stay in their files (chmod 600); only the bridge reads them.
// Settings → Home Assistant edits all this.
Singleton {
    id: root

    readonly property string configPath: `${Paths.config}/home-assistant.json`
    readonly property string tokenDir: `${Paths.config}/ha`
    readonly property string bridgePath: `${Quickshell.shellDir}/assets/ha-bridge.py`

    // [{ id, name, url, tokenFile }]
    property var instances: []
    // [{ id, instance, entity, name, icon }]: the right bar's buttons for them
    property var shortcuts: []
    property bool loaded
    // Only when home-assistant.json doesn't exist yet: carry lock-ha.json over
    property bool migrate
    // instance id -> [{ id, name, domain, state, icon }] (see entityList), and when
    property var entityLists: ({})
    property var entityListTimes: ({})

    // id -> its live connection (see Connection below)
    readonly property var connections: {
        const out = {};
        for (let i = 0; i < connectionInstances.count; i++) {
            const c = connectionInstances.objectAt(i);
            if (c)
                out[c.instanceId] = c;
        }
        return out;
    }

    // The instance to use when a card or widget doesn't name one
    readonly property string defaultId: instances[0]?.id ?? ""

    function connection(id: string): var {
        return connections[id || defaultId] ?? null;
    }

    // An entity's live state: { state, attributes, last_changed }, or null
    function entity(instanceId: string, entityId: string): var {
        return connection(instanceId)?.states[entityId] ?? null;
    }

    // Something (a card, a widget) wants these entities kept live
    function watch(consumer: string, instanceId: string, ids: var): void {
        connection(instanceId)?.watch(consumer, ids);
    }

    function unwatch(consumer: string, instanceId: string): void {
        connection(instanceId)?.unwatch(consumer);
    }

    function call(instanceId: string, domain: string, service: string, data: var, target: var): void {
        connection(instanceId)?.request("call", {
            domain: domain,
            service: service,
            data: data ?? {},
            target: target ?? null
        }, null);
    }

    // Toggles, presses or runs an entity, as its domain does it
    function activate(instanceId: string, entityId: string): void {
        const domain = entityId.split(".")[0];
        const services = {
            button: "press",
            input_button: "press",
            script: "turn_on",
            scene: "turn_on",
            automation: "trigger",
            lock: entity(instanceId, entityId)?.state === "locked" ? "unlock" : "lock",
            cover: "toggle"
        };
        const service = services[domain] ?? "toggle";
        call(instanceId, ["button", "input_button", "script", "scene", "automation", "lock", "cover"].includes(domain) ? domain : "homeassistant", service, {}, {
            entity_id: entityId
        });
    }

    // Asks an instance for something: "entities", "dashboards", "cards"
    function request(instanceId: string, op: string, args: var, cb: var): void {
        const c = connection(instanceId);
        if (!c) {
            cb?.({
                ok: false,
                error: "no such instance"
            });
            return;
        }
        c.request(op, args ?? {}, cb);
    }

    // Every entity of an instance, for pickers: fetched once a minute at most
    function entityList(instanceId: string, cb: var): void {
        const id = instanceId || defaultId;
        if (entityLists[id] && Date.now() - (entityListTimes[id] ?? 0) < 60000) {
            cb(entityLists[id]);
            return;
        }
        request(id, "entities", {}, msg => {
            if (!msg.ok) {
                cb(entityLists[id] ?? []);
                return;
            }
            const lists = Object.assign({}, entityLists), times = Object.assign({}, entityListTimes);
            lists[id] = msg.result.sort((a, b) => a.name.localeCompare(b.name));
            times[id] = Date.now();
            entityLists = lists;
            entityListTimes = times;
            cb(lists[id]);
        });
    }

    // The URL of an entity's picture (a camera's frame), token included by HA
    function pictureUrl(instanceId: string, entityId: string): string {
        const picture = entity(instanceId, entityId)?.attributes?.entity_picture ?? "";
        const inst = instances.find(i => i.id === (instanceId || defaultId));
        if (!picture || !inst)
            return "";
        return picture.startsWith("http") ? picture : `${inst.url.replace(/\/+$/, "")}${picture}`;
    }

    // Editing instances (Settings)
    function save(next: var): void {
        instances = next;
        writeConfig();
    }

    function writeConfig(): void {
        configFile.setText(JSON.stringify({
            instances: instances,
            shortcuts: shortcuts
        }, null, 4) + "\n");
    }

    // A right bar button for an entity; its id, to put on the bar
    function addShortcut(instanceId: string, entityId: string, name: string): string {
        let id = `ha-${entityId.replace(/[^a-z0-9]+/g, "-")}`, n = 2;
        while (shortcuts.some(s => s.id === id))
            id = `ha-${entityId.replace(/[^a-z0-9]+/g, "-")}-${n++}`;
        shortcuts = [...shortcuts,
            {
                id: id,
                instance: instanceId || defaultId,
                entity: entityId,
                name: name || ""
            }
        ];
        writeConfig();
        return id;
    }

    function removeShortcut(id: string): void {
        shortcuts = shortcuts.filter(s => s.id !== id);
        writeConfig();
    }

    function addInstance(name: string, url: string, token: string): string {
        let base = name.toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "") || "home";
        let id = base, n = 2;
        while (instances.some(i => i.id === id))
            id = `${base}-${n++}`;
        const tokenFile = `${tokenDir}/${id}.token`;
        writeToken(tokenFile, token);
        save([...instances,
            {
                id: id,
                name: name || id,
                url: url.replace(/\/+$/, ""),
                tokenFile: Paths.shortenHome(tokenFile)
            }
        ]);
        return id;
    }

    function updateInstance(id: string, changes: var, token: string): void {
        const inst = instances.find(i => i.id === id);
        if (!inst)
            return;
        const next = Object.assign({}, inst, changes);
        if (token) {
            next.tokenFile = Paths.shortenHome(`${tokenDir}/${id}.token`);
            writeToken(Paths.absolutePath(next.tokenFile), token);
        }
        save(instances.map(i => i.id === id ? next : i));
        connection(id)?.restart();
    }

    function removeInstance(id: string): void {
        save(instances.filter(i => i.id !== id));
    }

    // A token goes to its file through stdin, never on a command line, and
    // the file is only readable by you
    function writeToken(path: string, token: string): void {
        tokenWriter.pending.push({
            path: path,
            token: token.trim()
        });
        tokenWriter.next();
    }

    IpcHandler {
        // The instances as JSON: [{ id, name, url, connected, error, version, watched }]
        function instances(): string {
            return JSON.stringify(root.instances.map(i => {
                const c = root.connections[i.id];
                return {
                    id: i.id,
                    name: i.name,
                    url: i.url,
                    connected: !!c?.connected,
                    error: c?.error ?? "",
                    version: c?.version ?? "",
                    watched: Object.keys(c?.states ?? {}).length
                };
            }));
        }

        // An entity's state as JSON (it's kept live for a while after asking)
        function state(instanceId: string, entityId: string): string {
            root.watch(`ipc:${entityId}`, instanceId, [entityId]);
            return JSON.stringify(root.entity(instanceId, entityId));
        }

        // Toggles, presses or runs an entity, as its domain does
        function activate(instanceId: string, entityId: string): void {
            root.activate(instanceId, entityId);
        }

        // A right bar shortcut for an entity, put on the bar; its id
        function shortcut(instanceId: string, entityId: string, name: string): string {
            const id = root.addShortcut(instanceId, entityId, name);
            GlobalConfig.rightBar.actions = [...GlobalConfig.rightBar.actions, id];
            return id;
        }

        function removeShortcut(id: string): void {
            GlobalConfig.rightBar.actions = GlobalConfig.rightBar.actions.filter(a => a !== id);
            root.removeShortcut(id);
        }

        target: "homeAssistant"
    }

    Instantiator {
        id: connectionInstances

        model: root.instances

        Connection {
            required property var modelData

            instanceId: modelData.id
            url: modelData.url
            tokenFile: Paths.absolutePath(modelData.tokenFile)
        }
    }

    FileView {
        id: configFile

        path: root.configPath
        printErrors: false
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                const data = JSON.parse(text());
                root.instances = data.instances ?? [];
                root.shortcuts = data.shortcuts ?? [];
            } catch (e) {
                console.warn(`HomeAssistant: bad home-assistant.json: ${e}`);
            }
            root.loaded = true;
        }
        onLoadFailed: root.migrate = true
    }

    // Before home-assistant.json there was lock-ha.json's url and tokenFile:
    // that instance carries over, as "Home"
    FileView {
        id: legacy

        // No path, so nothing loads, until home-assistant.json is found missing
        path: root.migrate ? `${Paths.config}/lock-ha.json` : ""
        printErrors: false
        onLoaded: {
            try {
                const old = JSON.parse(text());
                if (old.url && root.instances.length === 0)
                    root.save([
                        {
                            id: "home",
                            name: "Home",
                            url: old.url.replace(/\/+$/, ""),
                            tokenFile: old.tokenFile ?? "~/.config/caelestia/ha-token"
                        }
                    ]);
            } catch (e) {}
            root.loaded = true;
        }
        onLoadFailed: root.loaded = true
    }

    Process {
        id: tokenWriter

        property var pending: []
        property var current: null

        function next(): void {
            if (running || pending.length === 0)
                return;
            current = pending.shift();
            command = ["sh", "-c", 'umask 077 && mkdir -p "$(dirname "$1")" && cat > "$1"', "sh", current.path];
            running = true;
        }

        stdinEnabled: true
        onStarted: {
            write(current.token + "\n");
            stdinEnabled = false;
        }
        onExited: {
            stdinEnabled = true;
            root.connections[root.instances.find(i => Paths.absolutePath(i.tokenFile) === current?.path)?.id ?? ""]?.restart();
            current = null;
            next();
        }
    }

    component Connection: QtObject {
        id: conn

        required property string instanceId
        required property string url
        required property string tokenFile

        property bool connected
        property string error
        property string version
        // entity id -> { state, attributes, last_changed }
        property var states: ({})
        // consumer -> [entity ids]
        property var watchers: ({})
        property int nextRequest: 1
        property var callbacks: ({})

        readonly property Process proc: Process {
            running: true
            command: ["python3", "-I", root.bridgePath, conn.url, conn.tokenFile]
            stdinEnabled: true
            stdout: SplitParser {
                onRead: line => conn.handle(line)
            }
            stderr: SplitParser {
                onRead: line => console.warn(`ha-bridge ${conn.instanceId}:`, line)
            }
            onStarted: conn.sendWatch()
            onExited: {
                conn.connected = false;
                retry.restart();
            }
        }

        readonly property Timer retry: Timer {
            interval: 5000
            onTriggered: conn.proc.running = true
        }

        // Watch changes are gathered, then sent once
        readonly property Timer watchDebounce: Timer {
            interval: 150
            onTriggered: conn.sendWatch()
        }

        function restart(): void {
            proc.running = false;
            retry.restart();
        }

        function send(obj: var): void {
            if (proc.running)
                proc.write(JSON.stringify(obj) + "\n");
        }

        function sendWatch(): void {
            const ids = new Set();
            for (const list of Object.values(watchers))
                for (const id of list)
                    ids.add(id);
            send({
                op: "watch",
                ids: [...ids]
            });
        }

        function watch(consumer: string, ids: var): void {
            const next = Object.assign({}, watchers);
            next[consumer] = ids.filter(id => id);
            watchers = next;
            watchDebounce.restart();
        }

        function unwatch(consumer: string): void {
            if (!(consumer in watchers))
                return;
            const next = Object.assign({}, watchers);
            delete next[consumer];
            watchers = next;
            watchDebounce.restart();
        }

        function request(op: string, args: var, cb: var): void {
            const id = nextRequest++;
            if (cb) {
                const next = Object.assign({}, callbacks);
                next[id] = cb;
                callbacks = next;
            }
            send(Object.assign({
                op: op,
                id: id
            }, args));
        }

        function handle(line: string): void {
            let msg;
            try {
                msg = JSON.parse(line);
            } catch (e) {
                return;
            }
            if (msg.type === "status") {
                connected = msg.connected;
                error = msg.error ?? "";
                if (msg.version)
                    version = msg.version;
            } else if (msg.type === "states") {
                const next = Object.assign({}, states);
                for (const [id, s] of Object.entries(msg.states)) {
                    if (s === null)
                        delete next[id];
                    else
                        next[id] = s;
                }
                states = next;
            } else if (msg.type === "result") {
                const cb = callbacks[msg.id];
                if (cb) {
                    const next = Object.assign({}, callbacks);
                    delete next[msg.id];
                    callbacks = next;
                    cb(msg);
                }
            }
        }
    }
}
