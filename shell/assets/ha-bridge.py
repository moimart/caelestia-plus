#!/usr/bin/env python3
"""A bridge between the shell and one Home Assistant instance.

    ha-bridge.py <url> <token file>

Keeps one WebSocket connection to Home Assistant, the token never leaving
this process, and talks JSON lines with the shell:

  in (stdin), one object per line:
    {"op": "watch", "ids": [...]}          live states for these entities
    {"op": "call", "id": n, "domain", "service", "data", "target"}
    {"op": "entities", "id": n}             every entity: id, name, domain, state
    {"op": "dashboards", "id": n}           the Lovelace dashboards
    {"op": "cards", "id": n, "dashboard": url_path or null}
                                            every card of a dashboard, flattened
  out (stdout):
    {"type": "status", "connected": bool, "error"?: str, "version"?: str}
    {"type": "states", "states": {id: {state, attributes, last_changed}}}
                                            the watched entities that changed
    {"type": "result", "id": n, "ok": bool, "result"?: ..., "error"?: str}

It reconnects on its own, with a growing pause, and exits when stdin closes.
"""

import asyncio
import json
import os
import sys

import websockets

url, token_file = sys.argv[1].rstrip("/"), os.path.expanduser(sys.argv[2])
ws_url = ("wss" if url.startswith("https") else "ws") + url[url.index(":"):] + "/api/websocket"

watched: set[str] = set()
states: dict[str, dict] = {}
conn = None
next_id = 1
pending: dict[int, asyncio.Future] = {}
subscription = None
connected = None  # an asyncio.Event, set while connected


def emit(obj) -> None:
    sys.stdout.write(json.dumps(obj, separators=(",", ":")) + "\n")
    sys.stdout.flush()


def read_token() -> str:
    with open(token_file) as f:
        return f.read().strip()


async def request(msg: dict):
    """One command over the socket; its result."""
    global next_id
    if conn is None:
        # Requests sent before (or between) connections wait for one
        await asyncio.wait_for(connected.wait(), 20)
    mid = next_id
    next_id += 1
    fut = asyncio.get_running_loop().create_future()
    pending[mid] = fut
    await conn.send(json.dumps({**msg, "id": mid}))
    return await asyncio.wait_for(fut, 30)


def compact(s: dict) -> dict:
    """The part of a state the shell uses."""
    return {"state": s.get("state"), "attributes": s.get("attributes", {}), "last_changed": s.get("last_changed")}


async def resubscribe() -> None:
    """Live states for the watched entities (HA's subscribe_entities)."""
    global subscription
    if conn is None:
        return
    if subscription is not None:
        try:
            await request({"type": "unsubscribe_events", "subscription": subscription})
        except Exception:
            pass
        subscription = None
    if not watched:
        return
    global next_id
    mid = next_id
    next_id += 1
    subscription = mid
    await conn.send(json.dumps({"id": mid, "type": "subscribe_entities", "entity_ids": sorted(watched)}))


def apply_entities_event(event: dict) -> None:
    """subscribe_entities sends compressed states: a(dd), c(hange), r(emove)."""
    changed = {}
    for eid, s in (event.get("a") or {}).items():
        states[eid] = {"state": s.get("s"), "attributes": s.get("a", {}), "last_changed": s.get("lc")}
        changed[eid] = states[eid]
    for eid, diff in (event.get("c") or {}).items():
        cur = states.setdefault(eid, {"state": None, "attributes": {}, "last_changed": None})
        plus, minus = diff.get("+", {}), diff.get("-", {})
        if "s" in plus:
            cur["state"] = plus["s"]
        if "a" in plus:
            cur["attributes"] = {**cur["attributes"], **plus["a"]}
        for key in minus.get("a", []):
            cur["attributes"].pop(key, None)
        if "lc" in plus:
            cur["last_changed"] = plus["lc"]
        changed[eid] = cur
    for eid in event.get("r") or []:
        states.pop(eid, None)
        changed[eid] = None
    if changed:
        emit({"type": "states", "states": changed})


def flatten_cards(config: dict) -> list:
    """Every card of a dashboard, with where it is, stacks opened up."""
    out = []

    def walk(card, path, view_title):
        if not isinstance(card, dict):
            return
        out.append({"path": path, "view": view_title, "type": card.get("type", ""), "title": card.get("title") or card.get("name") or "", "card": card})
        for i, child in enumerate(card.get("cards") or []):
            walk(child, f"{path}.{i}", view_title)

    for vi, view in enumerate(config.get("views") or []):
        title = view.get("title") or view.get("path") or f"View {vi + 1}"
        for ci, card in enumerate(view.get("cards") or []):
            walk(card, f"{vi}.{ci}", title)
        for si, section in enumerate(view.get("sections") or []):
            for ci, card in enumerate(section.get("cards") or []):
                walk(card, f"{vi}.s{si}.{ci}", title)
    return out


async def handle_command(cmd: dict) -> None:
    op, rid = cmd.get("op"), cmd.get("id")
    try:
        if op == "watch":
            new = set(cmd.get("ids") or [])
            if new != watched:
                watched.clear()
                watched.update(new)
                await resubscribe()
            return
        if op == "call":
            msg = {"type": "call_service", "domain": cmd["domain"], "service": cmd["service"], "service_data": cmd.get("data") or {}}
            if cmd.get("target"):
                msg["target"] = cmd["target"]
            result = await request(msg)
        elif op == "entities":
            raw = await request({"type": "get_states"})
            result = [{"id": s["entity_id"], "name": s.get("attributes", {}).get("friendly_name", s["entity_id"]),
                       "domain": s["entity_id"].split(".")[0], "state": s.get("state"),
                       "icon": s.get("attributes", {}).get("icon", "")} for s in raw]
        elif op == "dashboards":
            result = [{"url_path": None, "title": "Overview"}] + [
                {"url_path": d.get("url_path"), "title": d.get("title") or d.get("url_path")}
                for d in await request({"type": "lovelace/dashboards/list"})]
        elif op == "cards":
            msg = {"type": "lovelace/config"}
            if cmd.get("dashboard"):
                msg["url_path"] = cmd["dashboard"]
            result = flatten_cards(await request(msg))
        else:
            raise ValueError(f"unknown op {op}")
        if rid is not None:
            emit({"type": "result", "id": rid, "ok": True, "result": result})
    except Exception as e:
        if rid is not None:
            emit({"type": "result", "id": rid, "ok": False, "error": str(e) or type(e).__name__})


async def read_stdin() -> None:
    loop = asyncio.get_running_loop()
    reader = asyncio.StreamReader()
    await loop.connect_read_pipe(lambda: asyncio.StreamReaderProtocol(reader), sys.stdin)
    while line := await reader.readline():
        try:
            cmd = json.loads(line)
        except json.JSONDecodeError:
            continue
        asyncio.create_task(handle_command(cmd))
    os._exit(0)  # the shell went away


async def connect_forever() -> None:
    global conn, subscription
    pause = 1
    while True:
        try:
            async with websockets.connect(ws_url, max_size=32 * 1024 * 1024, open_timeout=10) as ws:
                hello = json.loads(await ws.recv())
                await ws.send(json.dumps({"type": "auth", "access_token": read_token()}))
                auth = json.loads(await ws.recv())
                if auth.get("type") != "auth_ok":
                    emit({"type": "status", "connected": False, "error": "the token was refused"})
                    await asyncio.sleep(60)
                    continue
                conn, pause = ws, 1
                connected.set()
                emit({"type": "status", "connected": True, "version": auth.get("ha_version") or hello.get("ha_version")})
                subscription = None
                await resubscribe()
                async for raw in ws:
                    msg = json.loads(raw)
                    if msg.get("type") == "result" and msg.get("id") in pending:
                        fut = pending.pop(msg["id"])
                        if not fut.done():
                            if msg.get("success"):
                                fut.set_result(msg.get("result"))
                            else:
                                fut.set_exception(RuntimeError((msg.get("error") or {}).get("message", "failed")))
                    elif msg.get("type") == "event" and msg.get("id") == subscription:
                        apply_entities_event(msg.get("event") or {})
        except FileNotFoundError:
            emit({"type": "status", "connected": False, "error": f"no token file at {token_file}"})
        except Exception as e:
            emit({"type": "status", "connected": False, "error": str(e) or type(e).__name__})
        conn = None
        connected.clear()
        for fut in pending.values():
            if not fut.done():
                fut.set_exception(ConnectionError("disconnected"))
        pending.clear()
        await asyncio.sleep(pause)
        pause = min(pause * 2, 60)


async def main() -> None:
    global connected
    connected = asyncio.Event()
    await asyncio.gather(read_stdin(), connect_forever())


if __name__ == "__main__":
    asyncio.run(main())
