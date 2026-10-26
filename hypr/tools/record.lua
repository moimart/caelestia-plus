-- Runs a Hyprland Lua config outside Hyprland and prints every call it makes
-- to `hl`, one per line, in order: binds, rules, monitors, env, config, execs.
-- Two configs that print the same thing configure Hyprland the same way.
--
--   lua5.4 hypr/tools/record.lua <hyprland.lua> > calls.txt
--
-- `hl` is a fake that accepts anything. Queries (hl.get_*) return nothing,
-- and functions passed to hl.bind/hl.on are recorded, not run. os.execute is
-- recorded too, so nothing outside the config runs.

local entry = assert(arg[1], "usage: record.lua <hyprland.lua>")
local out = {}

local function show(v, depth)
    depth = depth or 0
    local t = type(v)
    if t == "string" then
        return string.format("%q", v)
    elseif t == "table" then
        if rawget(v, "__desc") then
            return v.__desc
        end
        if depth > 6 then
            return "{...}"
        end
        local keys = {}
        for k in pairs(v) do
            keys[#keys + 1] = k
        end
        table.sort(keys, function(a, b)
            return tostring(a) < tostring(b)
        end)
        local parts = {}
        for _, k in ipairs(keys) do
            parts[#parts + 1] = tostring(k) .. "=" .. show(v[k], depth + 1)
        end
        return "{" .. table.concat(parts, ", ") .. "}"
    elseif t == "function" then
        local info = debug.getinfo(v, "S")
        return "fn@" .. (info.short_src:match("[^/]+$") or "?") .. ":" .. info.linedefined
    end
    return tostring(v)
end

-- A table that records calls to any path under it: hl.dsp.exec_cmd("x") gives
-- a value describing itself; hl.bind(...) is logged.
local function fake(path, log)
    return setmetatable({}, {
        __index = function(self, k)
            local child = fake(path .. "." .. k, log)
            rawset(self, k, child)
            return child
        end,
        __call = function(_, ...)
            local args = table.pack(...)
            local shown = {}
            for i = 1, args.n do
                shown[i] = show(args[i])
            end
            local desc = path .. "(" .. table.concat(shown, ", ") .. ")"
            local name = path:match("[^.]+$")
            if path:match("^hl%.get_") or path:match("^hl%.dsp%.") or path:match("^hl%.plugin%.[%w_]+%.") then
                -- Queries and dispatcher builders: values, not actions
                if path:match("^hl%.get_") then
                    return nil
                end
                return setmetatable({ __desc = desc }, getmetatable(fake(desc, log)))
            end
            if log then
                out[#out + 1] = desc
            end
            if name == "load" then
                return true
            end
            return setmetatable({ __desc = desc }, { __index = function() return function() end end })
        end,
    })
end

hl = fake("hl", true)
os.execute = function(cmd)
    out[#out + 1] = "os.execute(" .. string.format("%q", cmd) .. ")"
    return true
end

local chunk = assert(loadfile(entry))
local ok, err = pcall(chunk)
if not ok then
    out[#out + 1] = "ERROR " .. tostring(err)
end
for _, line in ipairs(out) do
    print(line)
end
