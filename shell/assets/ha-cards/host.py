#!/usr/bin/env python3
"""Home Assistant custom cards (HACS and the like) for the shell.

Custom cards are JavaScript written for Home Assistant's web frontend, so the
shell can't draw them itself, and a webview can't live inside Quickshell. This
draws them in one headless Chromium and hands the shell pictures of them.

As in docker-home, Home Assistant's own UI is never loaded. Each card gets a
small page of ours (card.js) that loads the dashboard's resources (the cards'
scripts, proxied from HA), creates the card element and gives it a stand-in
`hass` object. The HA token stays in this process: the page talks to
HA through it, and only the calls in READ and SUBSCRIBE (plus call_service)
get through.

Chromium is driven over its DevTools protocol: one tab per card, sized to the
widget in device pixels with the page zoomed by the screen's scale (screencast
frames ignore a device scale factor, so the zoom does its job), on a
transparent background. Frames come from Page.startScreencast as the card
paints, at most FPS a second, as PNGs in $XDG_RUNTIME_DIR/caelestia-cards.
Paused tabs are frozen.

stdin, JSON lines from the shell:
  {"op": "open", "id", "instance": {"id", "url", "tokenFile"}, "card": {...},
   "width", "height", "scale", "theme": {css variables}}
  {"op": "resize", "id", "width", "height", "scale"}
  {"op": "pause" | "resume" | "close", "id"}
stdout, JSON lines:
  {"id", "frame": path}          a new picture of the card
  {"id", "status": "loading" | "ready" | "error", "error"?}
"""

import asyncio
import base64
import json
import os
import re
import shutil
import sys
import tempfile
import time
import urllib.parse
import urllib.request
from pathlib import Path

import websockets
from websockets.datastructures import Headers
from websockets.http11 import Response

HERE = Path(__file__).resolve().parent
# Frames a second at most: each is a PNG that Chromium encodes, this passes on
# and the shell decodes
FPS = 15

# What a card may ask Home Assistant, as in docker-home's server
READ = re.compile(
    r"^(get_config|get_services|get_states|history/history_during_period|"
    r"recorder/(statistics_during_period|statistic_during_period|get_statistics_metadata|list_statistic_ids)|"
    r"logbook/get_events|config/(entity_registry/(list_for_display|get)|device_registry/list|area_registry/list|"
    r"floor_registry/list|label_registry/list)|energy/(get_prefs|info|fossil_energy_consumption)|"
    r"weather/convertible_units|frontend/get_translations|lovelace/(resources|config|dashboards/list)|"
    r"search/related|calendar/event/list)$"
)
SUBSCRIBE = re.compile(
    r"^(render_template|weather/subscribe_forecast|history/stream|logbook/event_stream|"
    r"subscribe_entities|energy/solar_forecast)$"
)
PROXIED = re.compile(r"^/(local|hacsfiles|static)/|^/api/(camera_proxy|image_proxy|media_player_proxy)/")


def emit(obj):
    sys.stdout.write(json.dumps(obj) + "\n")
    sys.stdout.flush()


def log(*args):
    print("ha-cards:", *args, file=sys.stderr, flush=True)


class Instance:
    """One Home Assistant: its WebSocket, and the local server its card pages
    load from (their absolute /local and /hacsfiles URLs need an origin of
    their own per instance)."""

    def __init__(self, iid, url, token_file):
        self.id = iid
        self.url = url.rstrip("/")
        self.token = Path(os.path.expanduser(token_file)).read_text().strip()
        self.ws = None
        self.next_id = 1
        self.pending = {}  # HA id -> future
        self.subs = {}  # HA id -> page connection, page id
        self.connected = asyncio.Event()
        self.port = 0
        self.pages = set()
        self.cards = {}  # card id -> page config
        self.mdi_meta = None
        self.mdi_chunks = {}

    async def start(self):
        server = await websockets.serve(
            self.page_ws, "127.0.0.1", 0, process_request=self.http, max_size=None
        )
        self.port = server.sockets[0].getsockname()[1]
        asyncio.create_task(self.run())

    # Home Assistant

    async def run(self):
        ws_url = self.url.replace("http", "ws", 1) + "/api/websocket"
        delay = 2
        while True:
            try:
                async with websockets.connect(ws_url, max_size=None) as ws:
                    await ws.recv()
                    await ws.send(json.dumps({"type": "auth", "access_token": self.token}))
                    if json.loads(await ws.recv()).get("type") != "auth_ok":
                        log(self.id, "auth failed")
                        await asyncio.sleep(60)
                        continue
                    self.ws = ws
                    self.connected.set()
                    delay = 2
                    async for raw in ws:
                        msg = json.loads(raw)
                        mid = msg.get("id")
                        if msg.get("type") == "event" and mid in self.subs:
                            conn, pid = self.subs[mid]
                            await self.to_page(conn, {"id": pid, "event": msg.get("event")})
                        elif mid in self.pending:
                            fut = self.pending.pop(mid)
                            if not fut.done():
                                fut.set_result(msg)
            except Exception as e:  # noqa: BLE001 - any failure means reconnect
                log(self.id, "connection:", e)
            self.ws = None
            self.connected.clear()
            for fut in self.pending.values():
                if not fut.done():
                    fut.set_result({"success": False, "error": {"message": "disconnected"}})
            self.pending.clear()
            self.subs.clear()
            # Pages start afresh once it's back
            for conn in list(self.pages):
                await self.to_page(conn, {"reload": True})
            await asyncio.sleep(delay)
            delay = min(delay * 2, 60)

    async def forget(self, mid):
        try:
            await self.ha({"type": "unsubscribe_events", "subscription": mid})
        except Exception:  # noqa: BLE001 - gone with the connection anyway
            pass

    async def ha(self, msg, before=None):
        await asyncio.wait_for(self.connected.wait(), 20)
        mid = self.next_id
        self.next_id += 1
        if before:
            before(mid)
        fut = asyncio.get_running_loop().create_future()
        self.pending[mid] = fut
        await self.ws.send(json.dumps({**msg, "id": mid}))
        return mid, await asyncio.wait_for(fut, 30)

    # The pages' WebSocket: HA calls, checked against the allowlists

    async def to_page(self, conn, obj):
        try:
            await conn.send(json.dumps(obj))
        except Exception:  # noqa: BLE001 - the page went away
            pass

    async def page_ws(self, conn):
        self.pages.add(conn)
        mine = set()
        try:
            async for raw in conn:
                req = json.loads(raw)
                asyncio.create_task(self.page_request(conn, req, mine))
        except Exception:  # noqa: BLE001
            pass
        finally:
            self.pages.discard(conn)
            for mid in mine:
                if self.subs.pop(mid, None) and self.ws:
                    asyncio.create_task(self.forget(mid))

    async def page_request(self, conn, req, mine):
        pid = req.get("id")
        if "unsub" in req:
            for mid, (c, p) in list(self.subs.items()):
                if c is conn and p == req["unsub"]:
                    self.subs.pop(mid, None)
                    mine.discard(mid)
                    if self.ws:
                        await self.ha({"type": "unsubscribe_events", "subscription": mid})
            return
        msg = req.get("msg") or {}
        kind = str(msg.get("type", ""))
        subscribe = bool(SUBSCRIBE.match(kind))
        if not (subscribe or READ.match(kind) or kind == "call_service"):
            await self.to_page(conn, {"id": pid, "error": f"{kind} isn't available to cards here"})
            return
        try:
            def register(mid):
                # Events can come before the result: known before it's sent
                self.subs[mid] = (conn, pid)
                mine.add(mid)

            _, res = await self.ha(msg, register if subscribe else None)
            if res.get("success", True):
                await self.to_page(conn, {"id": pid, "result": res.get("result")})
            else:
                await self.to_page(conn, {"id": pid, "error": (res.get("error") or {}).get("message", "failed")})
        except Exception as e:  # noqa: BLE001
            await self.to_page(conn, {"id": pid, "error": str(e) or "failed"})

    # Plain HTTP on the same port: the page, its script, icons, and HA's files

    async def http(self, conn, request):
        if request.headers.get("Upgrade", "").lower() == "websocket":
            return None
        path = request.path
        bare = urllib.parse.urlsplit(path).path
        try:
            if bare.startswith("/card/"):
                cid = urllib.parse.unquote(bare[6:])
                if cid not in self.cards:
                    return self.reply(404, b"no such card", "text/plain")
                return self.reply(200, self.page(cid).encode(), "text/html; charset=utf-8")
            if bare == "/_card.js":
                return self.reply(200, (HERE / "card.js").read_bytes(), "text/javascript; charset=utf-8")
            if bare.startswith("/_mdi/"):
                d = await self.mdi(urllib.parse.unquote(bare[6:]))
                return self.reply(200 if d else 404, (d or "").encode(), "text/plain")
            if PROXIED.match(bare):
                return await asyncio.to_thread(self.proxy, path)
        except Exception as e:  # noqa: BLE001
            log(self.id, "http", bare, e)
            return self.reply(502, str(e).encode(), "text/plain")
        return self.reply(404, b"not here", "text/plain")

    def reply(self, status, body, ctype, extra=None):
        h = Headers()
        h["Content-Type"] = ctype
        h["Content-Length"] = str(len(body))
        h["Cache-Control"] = "no-store" if ctype.startswith("text/html") else "max-age=3600"
        for k, v in (extra or {}).items():
            h[k] = v
        return Response(status, "OK" if status < 400 else "Error", h, body)

    def proxy(self, path):
        req = urllib.request.Request(self.url + path, headers={"Authorization": f"Bearer {self.token}"})
        try:
            with urllib.request.urlopen(req, timeout=20) as r:
                body = r.read()
                return self.reply(r.status, body, r.headers.get("Content-Type", "application/octet-stream"))
        except urllib.error.HTTPError as e:
            return self.reply(e.code, b"", "text/plain")

    async def mdi(self, name):
        # HA's own icon files: a list of parts, each a JSON of name -> path
        name = name.removeprefix("mdi:").removeprefix("hass:")
        if self.mdi_meta is None:
            self.mdi_meta = await asyncio.to_thread(self.fetch_json, "/static/mdi/iconMetadata.json")
        parts = self.mdi_meta.get("parts", [])
        part = parts[0] if parts else None
        for p in parts[1:]:
            if p.get("start", "") <= name:
                part = p
            else:
                break
        if not part:
            return None
        f = part["file"]
        if f not in self.mdi_chunks:
            self.mdi_chunks[f] = await asyncio.to_thread(self.fetch_json, f"/static/mdi/{f}.json")
        return self.mdi_chunks[f].get(name)

    def fetch_json(self, path):
        with urllib.request.urlopen(self.url + path, timeout=20) as r:
            return json.loads(r.read())

    def page(self, cid):
        c = self.cards[cid]
        theme = "".join(f"{k}:{v};" for k, v in (c.get("theme") or {}).items() if re.match(r"^--[\w-]+$", k))
        boot = json.dumps({"card": c["card"]}).replace("</", "<\\/")
        return f"""<!doctype html>
<html><head><meta charset="utf-8">
<style>
:root{{{theme}--card-background-color:transparent;--ha-card-background:transparent;--ha-card-border-width:0;
--ha-card-box-shadow:none;color-scheme:dark light}}
html,body{{margin:0;background:transparent;overflow:hidden;color:var(--primary-text-color);
font-family:var(--paper-font-body1_-_font-family,sans-serif)}}
#fit{{transform-origin:top center}}#host>*{{display:block}}
.msg{{padding:12px;font-size:13px;opacity:.8;text-align:center}}
</style>
<script>window.__CAELESTIA_CARD__ = {boot};
window.caelestiaZoom = (z) => {{ document.documentElement.style.zoom = z; dispatchEvent(new Event("resize")); }};
document.documentElement.style.zoom = {c.get("zoom", 1)};</script>
<script src="/_card.js"></script>
</head><body><div id="fit"><div id="host"></div></div></body></html>"""


class Browser:
    """One headless Chromium, over its DevTools protocol."""

    def __init__(self):
        self.ws = None
        self.next_id = 1
        self.pending = {}
        self.handlers = {}  # session id -> callable(method, params)
        self.proc = None
        self.profile = None

    async def start(self):
        exe = next((shutil.which(b) for b in ("chromium", "google-chrome-stable", "google-chrome", "chromium-browser") if shutil.which(b)), None)
        if not exe:
            raise RuntimeError("no Chromium or Chrome found")
        self.profile = tempfile.mkdtemp(prefix="caelestia-cards-")
        self.proc = await asyncio.create_subprocess_exec(
            # On the GPU where there's one (Chromium falls back to software
            # where there isn't): half the CPU for the same frames
            exe, "--headless=new", "--use-gl=angle", "--use-angle=gl-egl", "--ignore-gpu-blocklist",
            "--enable-gpu-rasterization", "--remote-debugging-port=0", f"--user-data-dir={self.profile}",
            "--no-first-run", "--no-default-browser-check", "--disable-extensions", "--disable-sync",
            "--disable-background-networking", "--hide-scrollbars", "--mute-audio",
            "--disable-features=Translate,MediaRouter", "about:blank",
            stdout=asyncio.subprocess.DEVNULL, stderr=asyncio.subprocess.PIPE,
        )
        endpoint = None
        while endpoint is None:
            line = await asyncio.wait_for(self.proc.stderr.readline(), 30)
            if not line:
                raise RuntimeError("Chromium exited")
            m = re.search(rb"DevTools listening on (ws://\S+)", line)
            if m:
                endpoint = m.group(1).decode()
        asyncio.create_task(self.drain())
        self.ws = await websockets.connect(endpoint, max_size=None)
        asyncio.create_task(self.read())

    async def drain(self):
        while await self.proc.stderr.readline():
            pass

    async def read(self):
        async for raw in self.ws:
            msg = json.loads(raw)
            if "id" in msg and msg["id"] in self.pending:
                fut = self.pending.pop(msg["id"])
                if not fut.done():
                    fut.set_result(msg)
            elif "method" in msg:
                h = self.handlers.get(msg.get("sessionId"))
                if h:
                    h(msg["method"], msg.get("params", {}))
        log("Chromium went away")
        os._exit(1)

    async def send(self, method, params=None, session=None):
        mid = self.next_id
        self.next_id += 1
        fut = asyncio.get_running_loop().create_future()
        self.pending[mid] = fut
        msg = {"id": mid, "method": method, "params": params or {}}
        if session:
            msg["sessionId"] = session
        await self.ws.send(json.dumps(msg))
        res = await asyncio.wait_for(fut, 30)
        if "error" in res:
            raise RuntimeError(f"{method}: {res['error'].get('message')}")
        return res.get("result", {})

    def stop(self):
        if self.proc and self.proc.returncode is None:
            self.proc.kill()
        if self.profile:
            shutil.rmtree(self.profile, ignore_errors=True)


class Card:
    """One card: a tab, its frames, paused or not."""

    def __init__(self, host, cid):
        self.host = host
        self.id = cid
        self.session = None
        self.target = None
        self.paused = False
        self.seq = 0
        self.last_emit = 0.0
        self.pending = None
        self.flush_handle = None
        self.fps = FPS
        self.last_ack = 0.0
        # Its CSS animations: most of what a card costs (the compositor runs
        # them at 60 frames a second). Without, it changes with its data only
        self.animate = False
        safe = re.sub(r"[^\w.-]", "_", cid)
        self.files = [host.frames / f"{safe}-0.png", host.frames / f"{safe}-1.png"]
        self.size = (1, 1, 1.0)

    async def open(self, inst, width, height, scale):
        b = self.host.browser
        # Opened at the card's page itself: navigating there from about:blank
        # moves it to another renderer, which drops this session's page
        url = f"http://127.0.0.1:{inst.port}/card/{urllib.parse.quote(self.id)}"
        self.target = (await b.send("Target.createTarget", {"url": url}))["targetId"]
        self.session = (await b.send("Target.attachToTarget", {"targetId": self.target, "flatten": True}))["sessionId"]
        b.handlers[self.session] = self.event
        self.loaded = asyncio.get_running_loop().create_future()
        await b.send("Page.enable", {}, self.session)
        self.size = (max(1, int(width)), max(1, int(height)), float(scale or 1))
        await self.emulate()
        # The page's errors go to the log
        await b.send("Runtime.enable", {}, self.session)
        await b.send("Log.enable", {}, self.session)
        # The page loading in its own renderer resets the emulation: again
        # once it has
        try:
            await asyncio.wait_for(asyncio.shield(self.loaded), 15)
        except TimeoutError:
            pass
        await self.emulate()
        if not self.animate:
            await b.send("Animation.enable", {}, self.session)
            await b.send("Animation.setPlaybackRate", {"playbackRate": 0}, self.session)
        if not self.paused:
            await self.screencast(True, thaw=False)

    async def metrics(self, width, height, scale):
        self.size = (max(1, int(width)), max(1, int(height)), float(scale or 1))
        await self.emulate()

    # The widget's size in device pixels, the page zoomed to the screen's
    # scale, on a transparent background
    async def emulate(self):
        b = self.host.browser
        w, h, scale = self.size
        self.host_card()["zoom"] = scale
        await b.send("Emulation.setDeviceMetricsOverride", {
            "width": round(w * scale), "height": round(h * scale), "deviceScaleFactor": 1, "mobile": False,
        }, self.session)
        await b.send("Emulation.setDefaultBackgroundColorOverride", {"color": {"r": 0, "g": 0, "b": 0, "a": 0}}, self.session)
        try:
            await b.send("Runtime.evaluate", {"expression": f"window.caelestiaZoom && caelestiaZoom({scale})"}, self.session)
        except RuntimeError:
            pass

    def host_card(self):
        for inst in self.host.instances.values():
            if self.id in inst.cards:
                return inst.cards[self.id]
        return {}

    async def lifecycle(self, state):
        # Frozen: no scripts, timers or painting at all. Best effort: a page
        # still loading can't be frozen yet
        try:
            await self.host.browser.send("Page.setWebLifecycleState", {"state": state}, self.session)
        except RuntimeError as e:
            log(self.id, e)

    async def screencast(self, on, thaw=True):
        b = self.host.browser
        if on:
            if thaw:
                await self.lifecycle("active")
            await b.send("Page.startScreencast", {"format": "png", "everyNthFrame": 1}, self.session)
            # The current picture straight away, not at the next repaint
            shot = await b.send("Page.captureScreenshot", {"format": "png"}, self.session)
            self.frame(shot["data"])
        else:
            await b.send("Page.stopScreencast", {}, self.session)
            await self.lifecycle("frozen")

    def event(self, method, params):
        if method == "Page.loadEventFired" and not self.loaded.done():
            self.loaded.set_result(True)
        elif method == "Page.screencastFrame":
            if not self.paused:
                self.frame(params["data"])
            # Chromium sends the next frame once this one is acknowledged:
            # acknowledging at the card's rate is what keeps it from
            # encoding frames nobody will see
            wait = max(0.0, 1 / self.fps - (time.monotonic() - self.last_ack))
            asyncio.get_running_loop().call_later(wait, self.ack, params["sessionId"])
        elif method == "Runtime.consoleAPICalled" and params.get("type") in ("error", "warning"):
            log(self.id, "console:", " ".join(str(a.get("value", a.get("description", ""))) for a in params.get("args", []))[:300])
        elif method == "Runtime.exceptionThrown":
            d = params.get("exceptionDetails", {})
            log(self.id, "exception:", (d.get("exception") or {}).get("description", d.get("text", ""))[:300])
        # (Not the 404s of resources HA still lists but no longer has)
        elif method == "Log.entryAdded" and params.get("entry", {}).get("level") == "error" \
                and not params["entry"].get("text", "").startswith("Failed to load resource"):
            e = params["entry"]
            log(self.id, "log:", e.get("text", "")[:200], e.get("url", ""))

    def ack(self, frame_session):
        self.last_ack = time.monotonic()
        asyncio.create_task(self.host.browser.send("Page.screencastFrameAck", {"sessionId": frame_session}, self.session))

    def frame(self, data):
        # At most FPS a second; after a burst, the last frame always gets out
        self.pending = data
        wait = 1 / self.fps - (time.monotonic() - self.last_emit)
        if wait <= 0:
            self.flush()
        elif self.flush_handle is None:
            self.flush_handle = asyncio.get_running_loop().call_later(wait, self.flush)

    def flush(self):
        self.flush_handle = None
        if self.pending is None or self.paused:
            return
        path = self.files[self.seq % 2]
        path.write_bytes(base64.b64decode(self.pending))
        self.pending = None
        self.seq += 1
        self.last_emit = time.monotonic()
        emit({"id": self.id, "frame": str(path), "seq": self.seq})

    async def close(self):
        try:
            await self.host.browser.send("Target.closeTarget", {"targetId": self.target})
        except Exception:  # noqa: BLE001
            pass
        self.host.browser.handlers.pop(self.session, None)
        for f in self.files:
            f.unlink(missing_ok=True)


class Host:
    def __init__(self):
        self.browser = Browser()
        self.instances = {}
        self.cards = {}
        run = os.environ.get("XDG_RUNTIME_DIR") or tempfile.gettempdir()
        self.frames = Path(run) / "caelestia-cards"
        self.frames.mkdir(parents=True, exist_ok=True)
        self.started = None

    async def ensure(self):
        if self.started is None:
            self.started = asyncio.ensure_future(self.browser.start())
        await self.started

    async def instance(self, spec):
        key = f"{spec['id']}|{spec['url']}"
        if key not in self.instances:
            inst = Instance(spec["id"], spec["url"], spec["tokenFile"])
            await inst.start()
            self.instances[key] = inst
        return self.instances[key]

    async def handle(self, req):
        op, cid = req.get("op"), req.get("id")
        card = self.cards.get(cid)
        try:
            if op == "open":
                if card:
                    await card.close()
                emit({"id": cid, "status": "loading"})
                await self.ensure()
                inst = await self.instance(req["instance"])
                inst.cards[cid] = {"card": req["card"], "theme": req.get("theme")}
                card = Card(self, cid)
                card.paused = bool(req.get("paused"))
                card.animate = bool(req.get("animate"))
                self.cards[cid] = card
                await card.open(inst, req["width"], req["height"], req.get("scale", 1))
                emit({"id": cid, "status": "ready"})
            elif not card:
                return
            elif op == "resize":
                await card.metrics(req["width"], req["height"], req.get("scale", 1))
            elif op == "pause" and not card.paused:
                card.paused = True
                await card.screencast(False)
            elif op == "resume" and card.paused:
                card.paused = False
                await card.screencast(True)
            elif op == "close":
                self.cards.pop(cid, None)
                await card.close()
        except Exception as e:  # noqa: BLE001
            log(op, cid, e)
            emit({"id": cid, "status": "error", "error": str(e)})

    async def main(self):
        loop = asyncio.get_running_loop()
        reader = asyncio.StreamReader()
        await loop.connect_read_pipe(lambda: asyncio.StreamReaderProtocol(reader), sys.stdin)
        try:
            while line := await reader.readline():
                try:
                    req = json.loads(line)
                except ValueError:
                    continue
                # One at a time per card, in order
                await self.handle(req)
        finally:
            self.browser.stop()
            shutil.rmtree(self.frames, ignore_errors=True)


if __name__ == "__main__":
    host = Host()
    try:
        asyncio.run(host.main())
    except KeyboardInterrupt:
        pass
    finally:
        host.browser.stop()
