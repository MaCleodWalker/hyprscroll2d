if rawget(_G, "__hyprscroll2d_layout_registered") then return true end

local function current_dir()
    local source = debug and debug.getinfo(1, "S").source
    if type(source) ~= "string" or source:sub(1, 1) ~= "@" then
        error("hyprscroll2d: unable to resolve layout directory")
    end
    return source:sub(2):match("^(.*)/[^/]*$")
end

local function load_relative(filename)
    local chunk, err = loadfile(current_dir() .. "/" .. filename)
    if not chunk then error(err) end
    return chunk()
end

local config = load_relative("config.lua")
local core = load_relative("core.lua")
local workspaces = {}

local function safe_field(value, field)
    if value == nil then return nil end
    local ok, result = pcall(function() return value[field] end)
    if ok then return result end
end

local function target_id(target, index)
    local window = safe_field(target, "window")
    local stable_id = safe_field(window, "stable_id")
    if stable_id ~= nil then return tostring(stable_id) end
    local address = safe_field(window, "address")
    if address then return "address:" .. tostring(address) end
    return "target:" .. tostring(safe_field(target, "index") or index)
end

local function workspace_key(ctx)
    for _, target in ipairs(ctx.targets or {}) do
        local window = safe_field(target, "window")
        local workspace = safe_field(window, "workspace")
        local id = safe_field(workspace, "id")
        if id ~= nil then return "workspace:" .. tostring(id) end
        local name = safe_field(workspace, "name")
        if name then return "workspace-name:" .. tostring(name) end
    end
    return "global"
end

local function describe(ctx)
    local descriptors = {}
    local active_id = nil

    for index, target in ipairs(ctx.targets or {}) do
        local window = safe_field(target, "window")
        local id = target_id(target, index)
        descriptors[id] = {
            id = id,
            target = target,
            window = window,
            address = safe_field(window, "address"),
        }
        if safe_field(window, "active") then active_id = id end
    end

    return descriptors, active_id
end

local function context(ctx)
    local key = workspace_key(ctx)
    local state = workspaces[key]
    if not state then
        state = core.new_state()
        workspaces[key] = state
    end

    local descriptors, active_id = describe(ctx)
    local ids = {}
    for _, target in ipairs(ctx.targets or {}) do
        table.insert(ids, target_id(target, #ids + 1))
    end
    core.sync(state, ids, active_id, config)

    return state, descriptors
end

local function focus_descriptor(descriptor)
    if not descriptor or not descriptor.address then return end
    hl.dispatch(hl.dsp.focus({ window = "address:" .. descriptor.address }))
end

local function recalculate(ctx)
    local state, descriptors = context(ctx)
    local placements = state.overview
        and core.overview_placements(state, ctx.area, config)
        or core.placements(state, ctx.area, config)

    for id, descriptor in pairs(descriptors) do
        local placement = placements[id]
        if placement then descriptor.target:place(placement) end
    end
end

local function layout_msg(ctx, message)
    local state, descriptors = context(ctx)
    local command, argument, extra = message:match("^(%S+)%s*(%S*)%s*(%S*)$")

    if command == "focus" then
        local id = core.focus(state, argument)
        focus_descriptor(id and descriptors[id])
    elseif command == "move" then
        core.move(state, argument)
    elseif command == "pan" then
        core.pan(state, argument)
    elseif command == "follow" or command == "center" then
        core.follow(state)
    elseif command == "overview" then
        core.set_overview(state, not state.overview)
    elseif command == "overview-exit" then
        core.set_overview(state, false)
    elseif command == "resize" and argument == "width" then
        if extra ~= "grow" and extra ~= "shrink" then
            return "hyprscroll2d: resize width expects grow or shrink"
        end
        core.resize_width(state, config, extra == "grow" and 1 or -1)
    elseif command == "resize" and argument == "height" then
        if extra ~= "grow" and extra ~= "shrink" then
            return "hyprscroll2d: resize height expects grow or shrink"
        end
        core.resize_height(state, config, extra == "grow" and 1 or -1)
    else
        return "hyprscroll2d: expected focus/move/pan <direction>, resize width/height grow/shrink, or center"
    end

    return true
end

local function window_layout_name(window)
    local layout = safe_field(window, "layout")
    return safe_field(layout, "name")
end

if not rawget(_G, "__hyprscroll2d_focus_subscription") then
    local ok, subscription = pcall(function()
        return hl.on("window.active", function(window)
            if window_layout_name(window) == "lua:hyprscroll2d" then
                local workspace = safe_field(window, "workspace")
                local id = safe_field(workspace, "id")
                local name = safe_field(workspace, "name")
                local state = id and workspaces["workspace:" .. tostring(id)]
                    or name and workspaces["workspace-name:" .. tostring(name)]
                    or workspaces.global
                if not (state and state.overview) then
                    hl.dispatch(hl.dsp.layout("follow"))
                end
            end
        end)
    end)
    if ok then _G.__hyprscroll2d_focus_subscription = subscription or true end
end

hl.layout.register("hyprscroll2d", {
    recalculate = recalculate,
    layout_msg = layout_msg,
})

_G.__hyprscroll2d_layout_registered = true
return true
