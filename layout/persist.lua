-- Remembers each workspace's grid across Hyprland restarts.
--
-- Windows get new identities every session, so a saved window is matched to a
-- new one by its class, preferring the same title. The file is a plain Lua
-- table under $XDG_STATE_HOME/omalattice, read without access to any globals.
local M = {}

-- How long saved positions wait for their windows to come back.
M.RESTORE_SECONDS = 45

local MAX_TEXT = 200

local function state_dir()
    local base = os.getenv("XDG_STATE_HOME")
    if not base or base == "" then
        local home = os.getenv("HOME")
        if not home or home == "" then return nil end
        base = home .. "/.local/state"
    end
    return base .. "/omalattice"
end

function M.path()
    local dir = state_dir()
    return dir and (dir .. "/layouts")
end

local function integer(value)
    if type(value) == "number" and value == value and value % 1 == 0
        and value > -1000000 and value < 1000000 then
        return value
    end
end

local function text(value)
    if type(value) ~= "string" then return "" end
    return value:sub(1, MAX_TEXT)
end

local function clean_workspace(entry)
    if type(entry) ~= "table" or type(entry.windows) ~= "table" then return nil end

    local windows = {}
    for _, window in ipairs(entry.windows) do
        local col, row = integer(window.col), integer(window.row)
        local w, h = integer(window.w), integer(window.h)
        if col and row and w and h and w >= 1 and h >= 1 then
            table.insert(windows, {
                class = text(window.class),
                title = text(window.title),
                col = col, row = row, w = w, h = h,
            })
        end
    end

    local camera = type(entry.camera) == "table"
        and integer(entry.camera.col) and integer(entry.camera.row)
        and { col = entry.camera.col, row = entry.camera.row } or nil
    return { camera = camera, windows = windows }
end

-- Returns the saved workspaces by key, or an empty table.
function M.load()
    local path = M.path()
    if not path then return {} end

    local chunk = loadfile(path, "t", {})
    if not chunk then return {} end
    local ok, result = pcall(chunk)
    if not ok or type(result) ~= "table" then return {} end

    local saved = {}
    for key, entry in pairs(result) do
        local clean = type(key) == "string" and clean_workspace(entry)
        if clean then saved[key] = clean end
    end
    return saved
end

-- A deterministic description of a workspace, used to skip redundant writes.
function M.snapshot(state, infos)
    local windows = {}
    for _, id in ipairs(state.ids) do
        local position, info = state.positions[id], infos[id]
        if position and info then
            table.insert(windows, {
                class = text(info.class),
                title = text(info.title),
                col = position.col,
                row = position.row,
                w = state.width_step_by_id[id],
                h = state.height_step_by_id[id],
            })
        end
    end
    table.sort(windows, function(a, b)
        if a.row ~= b.row then return a.row < b.row end
        if a.col ~= b.col then return a.col < b.col end
        return a.class < b.class
    end)
    return { camera = { col = state.camera.col, row = state.camera.row }, windows = windows }
end

local function encode_workspace(key, entry)
    local lines = {}
    for _, window in ipairs(entry.windows) do
        table.insert(lines, string.format(
            "            { class = %q, title = %q, col = %d, row = %d, w = %d, h = %d },",
            window.class, window.title, window.col, window.row, window.w, window.h))
    end
    local camera = entry.camera or { col = 0, row = 0 }
    return string.format("    [%q] = {\n        camera = { col = %d, row = %d },\n        windows = {\n%s\n        },\n    },\n",
        key, camera.col, camera.row, table.concat(lines, "\n"))
end

function M.encode(saved)
    local keys = {}
    for key, entry in pairs(saved) do
        if #entry.windows > 0 then table.insert(keys, key) end
    end
    table.sort(keys)

    local parts = { "-- Written by Omalattice to restore workspace grids. Safe to delete.\nreturn {\n" }
    for _, key in ipairs(keys) do table.insert(parts, encode_workspace(key, saved[key])) end
    table.insert(parts, "}\n")
    return table.concat(parts)
end

local function shell_quote(value)
    return "'" .. tostring(value):gsub("'", "'\\''") .. "'"
end

function M.write(saved)
    local dir, path = state_dir(), M.path()
    if not dir then return nil, "no state directory" end

    -- Titles can be private, so the directory and file are owner-only, including
    -- ones created by earlier versions with default permissions.
    local prepare = io.popen("umask 077; mkdir -p " .. shell_quote(dir)
        .. " && chmod 700 " .. shell_quote(dir)
        .. " && touch " .. shell_quote(path)
        .. " && chmod 600 " .. shell_quote(path))
    if prepare then prepare:close() end

    local file, err = io.open(path, "w")
    if not file then return nil, err end
    local ok, write_err = file:write(M.encode(saved))
    local closed, close_err = file:close()
    if not ok then return nil, write_err end
    if not closed then return nil, close_err end
    return true
end

-- Starts waiting for the windows of a saved workspace to come back.
function M.begin_restore(entry)
    if not entry or #entry.windows == 0 then return nil end
    local pending = {}
    for index, window in ipairs(entry.windows) do pending[index] = window end
    return {
        pending = pending,
        camera = entry.camera,
        deadline = os.time() + M.RESTORE_SECONDS,
    }
end

function M.restoring(state)
    local restore = state.restore
    return restore ~= nil and #restore.pending > 0 and os.time() < restore.deadline
end

local function clamp(value, minimum, maximum)
    return math.max(minimum, math.min(maximum, value))
end

local function take_match(pending, info)
    local best = nil
    for index, window in ipairs(pending) do
        if window.class == info.class then
            if window.title == info.title then
                best = index
                break
            end
            best = best or index
        end
    end
    return best and table.remove(pending, best)
end

-- Gives windows that are new to `state` the position and sizes saved for them.
-- Call this before core.sync. Returns true once the restore is over.
function M.claim(state, ids, infos, config)
    local restore = state.restore
    if not restore then return true end

    local occupied = {}
    for _, position in pairs(state.positions) do
        occupied[position.col .. ":" .. position.row] = true
    end

    for _, id in ipairs(ids) do
        local info = infos[id]
        if not state.positions[id] and info and #restore.pending > 0 then
            local window = take_match(restore.pending, info)
            if window and not occupied[window.col .. ":" .. window.row] then
                occupied[window.col .. ":" .. window.row] = true
                state.positions[id] = { col = window.col, row = window.row }
                state.width_step_by_id[id] = clamp(window.w, 1, #config.width_steps)
                state.height_step_by_id[id] = clamp(window.h, 1, #config.height_steps)
            end
        end
    end

    return not M.restoring(state)
end

-- Puts the camera back where it was once the restore is over.
function M.finish(state)
    local restore = state.restore
    state.restore = nil
    local camera = restore and restore.camera
    if not camera then return end
    for _, position in pairs(state.positions) do
        if position.col == camera.col and position.row == camera.row then
            state.camera.col, state.camera.row = camera.col, camera.row
            return
        end
    end
end

return M
