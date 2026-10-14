local M = {}

local LAYOUT = "lua:hyprscroll2d"

local function shell_quote(value)
    return "'" .. tostring(value):gsub("'", "'\\''") .. "'"
end

local function state_dir()
    local base = os.getenv("XDG_STATE_HOME")
    if not base or base == "" then
        local home = os.getenv("HOME")
        if not home or home == "" then return nil end
        base = home .. "/.local/state"
    end
    return base .. "/hyprscroll2d"
end

local function state_path()
    local dir = state_dir()
    return dir and (dir .. "/workspaces")
end

local function valid(id)
    return type(id) == "number" and id >= 1 and id % 1 == 0
end

function M.list()
    local ids = {}
    local path = state_path()
    local file = path and io.open(path, "r")
    if not file then return ids end
    for line in file:lines() do
        local id = tonumber(line)
        if valid(id) then ids[#ids + 1] = id end
    end
    file:close()
    return ids
end

local function write(ids)
    local dir = state_dir()
    if not dir then return nil, "no state directory" end

    local mkdir = io.popen("mkdir -p " .. shell_quote(dir))
    if mkdir then mkdir:close() end

    local file, err = io.open(state_path(), "w")
    if not file then return nil, err end
    for _, id in ipairs(ids) do file:write(id, "\n") end
    return file:close()
end

function M.apply(id)
    hl.workspace_rule({ workspace = tostring(id), layout = LAYOUT })
end

function M.add(id)
    if not valid(id) then return nil, "invalid workspace" end
    local ids = M.list()
    for _, existing in ipairs(ids) do
        if existing == id then return true end
    end
    ids[#ids + 1] = id
    return write(ids)
end

function M.remove(id)
    local kept = {}
    for _, existing in ipairs(M.list()) do
        if existing ~= id then kept[#kept + 1] = existing end
    end
    return write(kept)
end

function M.restore()
    for _, id in ipairs(M.list()) do M.apply(id) end
end

M.LAYOUT = LAYOUT

return M
