.pragma library

// Display arrangement, in desktop pixels. rects: [{ name, x, y, width, height }].

// Where display `name`, dropped at (x, y), ends up. Within `snapDistance` of
// another's edge it goes flush against it, overlapping along that edge, and
// lines up starts, ends and centres within `alignDistance`; further away it
// stays where it was dropped. It never overlaps another display.
function snap(rects, name, x, y, snapDistance, alignDistance) {
    const me = rects.find(r => r.name === name);
    const others = rects.filter(r => r.name !== name);
    if (!me)
        return { x: x, y: y };
    if (others.length === 0)
        return { x: me.x, y: me.y };
    const w = me.width, h = me.height;
    const minOverlap = 40;
    const clamp = (v, lo, hi) => Math.max(lo, Math.min(hi, v));
    const align = (v, start, length, size) => {
        for (const t of [start, start + length - size, start + (length - size) / 2])
            if (Math.abs(v - t) < alignDistance)
                return t;
        return v;
    };
    const overlaps = (cx, cy) => others.some(o => cx < o.x + o.width && cx + w > o.x && cy < o.y + o.height && cy + h > o.y);

    let best = null;
    for (const o of others) {
        const vy = align(clamp(y, o.y - h + minOverlap, o.y + o.height - minOverlap), o.y, o.height, h);
        const vx = align(clamp(x, o.x - w + minOverlap, o.x + o.width - minOverlap), o.x, o.width, w);
        for (const c of [[o.x + o.width, vy], [o.x - w, vy], [vx, o.y + o.height], [vx, o.y - h]]) {
            const p = { x: Math.round(c[0]), y: Math.round(c[1]) };
            if (overlaps(p.x, p.y))
                continue;
            const d = Math.hypot(p.x - x, p.y - y);
            if (!best || d < best.d)
                best = { p: p, d: d };
        }
    }
    if (!best)
        return { x: me.x, y: me.y };
    const free = { x: Math.round(x), y: Math.round(y) };
    if (best.d > snapDistance && !overlaps(free.x, free.y))
        return free;
    return best.p;
}

// The displays the pointer can't reach from `from` (the focused display; else
// the largest): displays only connect where they share a stretch of edge
function unreachable(rects, from) {
    if (rects.length < 2)
        return [];
    const touching = (a, b) => {
        const xTouch = a.x === b.x + b.width || b.x === a.x + a.width;
        const yTouch = a.y === b.y + b.height || b.y === a.y + a.height;
        const xOverlap = a.x < b.x + b.width && b.x < a.x + a.width;
        const yOverlap = a.y < b.y + b.height && b.y < a.y + a.height;
        return (xTouch && yOverlap) || (yTouch && xOverlap);
    };
    const start = rects.find(r => r.name === from) ?? rects.reduce((a, b) => b.width * b.height > a.width * a.height ? b : a);
    const seen = new Set([start.name]);
    const queue = [start];
    while (queue.length > 0) {
        const r = queue.shift();
        for (const o of rects)
            if (!seen.has(o.name) && touching(r, o)) {
                seen.add(o.name);
                queue.push(o);
            }
    }
    return rects.filter(r => !seen.has(r.name)).map(r => r.name);
}
