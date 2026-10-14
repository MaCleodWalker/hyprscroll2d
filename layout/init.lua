if rawget(_G, "__omalattice_layout_registered") then return true end

local function current_dir()
    local source = debug and debug.getinfo(1, "S").source
    if type(source) ~= "string" or source:sub(1, 1) ~= "@" then
        error("omalattice: unable to resolve layout directory")
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
local overview_status_path = os.getenv("XDG_RUNTIME_DIR")
    and (os.getenv("XDG_RUNTIME_DIR") .. "/omalattice-overview")

local last_overview_status = nil

local function json_string(value)
    return '"' .. tostring(value):gsub('[%c"\\]', function(char)
        return string.format("\\u%04x", char:byte())
    end) .. '"'
end

-- The shell reads this JSON to draw the overview. "payload" carries the
-- scroll bars and the window tiles while an overview is open.
local function write_overview_status(key, enabled, payload)
    if not overview_status_path then
        return nil, "XDG_RUNTIME_DIR is not set"
    end

    local status = string.format('{"workspace":%s,"overview":%s%s}',
        json_string(key), enabled and "true" or "false", enabled and payload or "")
    if status == last_overview_status then return true end

    local file, err = io.open(overview_status_path, "w")
    if not file then return nil, err end
    local ok, write_err = file:write(status)
    local closed, close_err = file:close()
    if not ok then return nil, write_err end
    if not closed then return nil, close_err end
    last_overview_status = status
    return true
end

local function overview_payload(ctx, state, descriptors, tiles)
    local bars = core.overview_scrollbars(state, ctx.area, config)
    local entries = {}
    for _, id in ipairs(state.ids) do
        local descriptor, tile = descriptors[id], tiles[id]
        if descriptor and descriptor.address and tile then
            table.insert(entries, string.format('{"address":%s,"x":%.2f,"y":%.2f,"w":%.2f,"h":%.2f}',
                json_string(descriptor.address), tile.x, tile.y, tile.w, tile.h))
        end
    end

    return string.format(
        ',"thumbnails":%s,"area":{"x":%.2f,"y":%.2f,"w":%.2f,"h":%.2f},"bars":[%.4f,%.4f,%.4f,%.4f],"tiles":[%s]',
        config.overview_thumbnails ~= false and "true" or "false",
        ctx.area.x, ctx.area.y, ctx.area.w, ctx.area.h,
        bars.x.start, bars.x.size, bars.y.start, bars.y.size,
        table.concat(entries, ","))
end

if overview_status_path then
    local ok, err = write_overview_status("none", false)
    if not ok then
        io.stderr:write("omalattice: unable to reset overview status: " .. tostring(err) .. "\n")
    end
end

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

local function active_state()
    local ok, window = pcall(hl.get_active_window)
    if not ok or not window then return nil end

    local workspace = safe_field(window, "workspace")
    local id = safe_field(workspace, "id")
    local name = safe_field(workspace, "name")
    return id and workspaces["workspace:" .. tostring(id)]
        or name and workspaces["workspace-name:" .. tostring(name)]
        or workspaces.global
end

_G.__omalattice_is_overview_active = function()
    local state = active_state()
    return state and state.overview == true or false
end

-- Pans a scrollable overview while the pointer rests near the edge of the viewport.
local AUTOSCROLL_MS = 16
local autoscroll_timer = nil

local function autoscroll_tick()
    local state = active_state()
    local area = state and state.overview and state.view_area
    if not area then return end

    local ok, point = pcall(hl.get_cursor_pos)
    if not ok or not point then return end
    local vx, vy = core.edge_scroll_velocity(point, area, config)
    if vx == 0 and vy == 0 then return end

    local seconds = AUTOSCROLL_MS / 1000
    if core.scroll_overview_by(state, vx * seconds, vy * seconds, area, config) then
        hl.dispatch(hl.dsp.layout("refresh"))
    end
end

local function set_autoscroll(enabled)
    local speed = config.overview_autoscroll_speed
    if type(speed) ~= "number" or speed <= 0 then return end
    if not autoscroll_timer then
        if not enabled then return end
        autoscroll_timer = hl.timer(autoscroll_tick, { timeout = AUTOSCROLL_MS, type = "repeat" })
    end
    autoscroll_timer:set_enabled(enabled)
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

local function overview_changed()
    local state = active_state()
    set_autoscroll(state ~= nil and state.overview == true)
    local callback = rawget(_G, "__omalattice_overview_changed")
    if callback then pcall(callback) end
end

local function recalculate(ctx)
    local state, descriptors = context(ctx)
    local placements
    state.view_area = state.overview and ctx.area or nil
    if state.overview then
        local tiles = core.overview_placements(state, ctx.area, config)
        write_overview_status(workspace_key(ctx), true, overview_payload(ctx, state, descriptors, tiles))
        if config.overview_thumbnails ~= false then
            -- The shell draws the thumbnails, so the windows keep their size. They are
            -- stacked on screen because the compositor only captures visible windows.
            placements = {}
            for id, box in pairs(core.placements(state, ctx.area, config)) do
                placements[id] = {
                    x = ctx.area.x + (ctx.area.w - box.w) / 2,
                    y = ctx.area.y + (ctx.area.h - box.h) / 2,
                    w = box.w,
                    h = box.h,
                }
            end
        else
            placements = tiles
        end
    else
        placements = core.placements(state, ctx.area, config)
    end

    for id, descriptor in pairs(descriptors) do
        local placement = placements[id]
        if placement then descriptor.target:place(placement) end
    end

    -- A click in the overview leaves the pointer over its thumbnail, so move it
    -- into the window that was just entered.
    if state.recenter_cursor and not state.overview then
        state.recenter_cursor = nil
        local active = placements[state.focused_id]
        if active then
            hl.dispatch(hl.dsp.cursor.move({ x = active.x + active.w / 2, y = active.y + active.h / 2 }))
        end
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
        local enabled = not state.overview
        local ok, err = write_overview_status(workspace_key(ctx), enabled)
        if not ok then return "omalattice: unable to update overview status: " .. tostring(err) end
        core.set_overview(state, enabled)
        overview_changed()
    elseif command == "refresh" then
        return true
    elseif command == "overview-exit" then
        state.recenter_cursor = argument == "click" or nil
        local ok, err = write_overview_status(workspace_key(ctx), false)
        if not ok then return "omalattice: unable to update overview status: " .. tostring(err) end
        core.set_overview(state, false)
        overview_changed()
    elseif command == "scroll" then
        if state.overview then core.scroll_overview(state, argument, ctx.area, config) end
    elseif command == "resize" and argument == "width" then
        if extra ~= "grow" and extra ~= "shrink" then
            return "omalattice: resize width expects grow or shrink"
        end
        core.resize_width(state, config, extra == "grow" and 1 or -1)
    elseif command == "resize" and argument == "height" then
        if extra ~= "grow" and extra ~= "shrink" then
            return "omalattice: resize height expects grow or shrink"
        end
        core.resize_height(state, config, extra == "grow" and 1 or -1)
    else
        return "omalattice: expected focus/move/pan/scroll <direction>, resize width/height grow/shrink, or center"
    end

    return true
end

local function window_layout_name(window)
    local layout = safe_field(window, "layout")
    return safe_field(layout, "name")
end

if not rawget(_G, "__omalattice_focus_subscription") then
    local ok, subscription = pcall(function()
        return hl.on("window.active", function(window)
            if window_layout_name(window) == "lua:omalattice" then
                local workspace = safe_field(window, "workspace")
                local id = safe_field(workspace, "id")
                local name = safe_field(workspace, "name")
                local state = id and workspaces["workspace:" .. tostring(id)]
                    or name and workspaces["workspace-name:" .. tostring(name)]
                    or workspaces.global
                if not (state and state.overview) then
                    local result = hl.dispatch(hl.dsp.layout("follow"))
                    if result.ok and window.mapped and window.active then
                        local at, size = window.at, window.size
                        if at and size and size.x > 0 and size.y > 0 then
                            -- Leave the peek after scrolling so it cannot focus the next window.
                            hl.dispatch(hl.dsp.cursor.move({
                                x = at.x + size.x / 2,
                                y = at.y + size.y / 2,
                            }))
                        end
                    end
                end
            end
        end)
    end)
    if ok then _G.__omalattice_focus_subscription = subscription or true end
end

if not rawget(_G, "__omalattice_hover") then
    local ok, hover = pcall(function()
        return load_relative("hover.lua").start(config, _G.__omalattice_is_overview_active)
    end)
    if ok then
        _G.__omalattice_hover = hover or true
    else
        io.stderr:write("omalattice: unable to start hover focus: " .. tostring(hover) .. "\n")
    end
end

hl.layout.register("omalattice", {
    recalculate = recalculate,
    layout_msg = layout_msg,
})

_G.__omalattice_layout_registered = true
return true
