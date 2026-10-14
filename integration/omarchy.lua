if rawget(_G, "__hyprscroll2d_omarchy_integrated") then return true end

local function safe_field(value, field)
    if value == nil then return nil end
    local ok, result = pcall(function() return value[field] end)
    if ok then return result end
end

local function is_hyprscroll2d_active()
    local ok, window = pcall(hl.get_active_window)
    if not ok or not window then return false end
    local layout = safe_field(window, "layout")
    return safe_field(layout, "name") == "lua:hyprscroll2d"
end

local function route(message, fallback)
    return function()
        local active_layout = is_hyprscroll2d_active()
        local overview_active = rawget(_G, "__hyprscroll2d_is_overview_active")
        if active_layout and (message ~= "overview-exit" or (overview_active and overview_active())) then
            hl.dispatch(hl.dsp.layout(message))
        elseif fallback then
            local dispatcher = fallback()
            if dispatcher then hl.dispatch(dispatcher) end
        end
    end
end

local function replace(keys, description, message, fallback)
    hl.unbind(keys)
    o.bind(keys, description, route(message, fallback))
end

local terminal_action = type(o.launch_terminal) == "function" and o.launch_terminal() or nil

local source = debug and debug.getinfo(1, "S").source
if type(source) ~= "string" or source:sub(1, 1) ~= "@" then
    error("hyprscroll2d: unable to resolve integration directory")
end
local workspaces = dofile(source:sub(2):match("^(.*)/[^/]*$") .. "/workspaces.lua")

local TOGGLE_LAYOUT = "omarchy-hyprland-workspace-layout-toggle"
-- Same icon Omarchy uses when it announces a workspace layout change.
local LAYOUT_ICON = "\243\177\130\172"

-- Extends Omarchy's dwindle <-> scrolling toggle into
-- dwindle -> scrolling -> Hyprscroll2D -> dwindle for the focused workspace.
local function rotate_layout()
    local ok, workspace = pcall(hl.get_active_workspace)
    local id = ok and safe_field(workspace, "id") or nil
    local current = ok and safe_field(workspace, "tiled_layout") or nil

    if current == "scrolling" and not safe_field(workspace, "special") and id then
        if workspaces.add(id) then
            workspaces.apply(id)
            hl.dispatch(hl.dsp.exec_cmd(
                "omarchy-notification-send -g " .. LAYOUT_ICON .. " 'Workspace layout set to hyprscroll2d'"
            ))
            return
        end
    elseif current == workspaces.LAYOUT and id then
        local overview_active = rawget(_G, "__hyprscroll2d_is_overview_active")
        if overview_active and overview_active() then
            hl.dispatch(hl.dsp.layout("overview-exit"))
        end
        workspaces.remove(id)
    end

    hl.dispatch(hl.dsp.exec_cmd(TOGGLE_LAYOUT))
end

hl.unbind("SUPER + L")
o.bind("SUPER + L", "Toggle workspace layout", rotate_layout)
_G.__hyprscroll2d_rotate_layout = rotate_layout

replace("SUPER + LEFT", "Focus left", "focus left", function()
    return hl.dsp.focus({ direction = "l" })
end)
replace("SUPER + RIGHT", "Focus right", "focus right", function()
    return hl.dsp.focus({ direction = "r" })
end)
replace("SUPER + UP", "Focus up", "focus up", function()
    return hl.dsp.focus({ direction = "u" })
end)
replace("SUPER + DOWN", "Focus down", "focus down", function()
    return hl.dsp.focus({ direction = "d" })
end)

replace("SUPER + M", "Toggle 2D overview", "overview")
replace("SUPER + RETURN", "Select overview window", "overview-exit", function()
    if type(terminal_action) == "function" then
        return terminal_action()
    end
    return hl.dsp.exec_cmd("omarchy-launch-terminal")
end)
replace("SUPER + ESCAPE", "Exit 2D overview", "overview-exit")

replace("SUPER + SHIFT + LEFT", "Move window left", "move left", function()
    return hl.dsp.window.swap({ direction = "l" })
end)
replace("SUPER + SHIFT + RIGHT", "Move window right", "move right", function()
    return hl.dsp.window.swap({ direction = "r" })
end)
replace("SUPER + SHIFT + UP", "Move window up", "move up", function()
    return hl.dsp.window.swap({ direction = "u" })
end)
replace("SUPER + SHIFT + DOWN", "Move window down", "move down", function()
    return hl.dsp.window.swap({ direction = "d" })
end)

replace("SUPER + CTRL + LEFT", "Pan 2D canvas left", "pan left", function()
    return hl.dsp.group.prev()
end)
replace("SUPER + CTRL + RIGHT", "Pan 2D canvas right", "pan right", function()
    return hl.dsp.group.next()
end)
replace("SUPER + CTRL + UP", "Pan 2D canvas up", "pan up")
replace("SUPER + CTRL + DOWN", "Pan 2D canvas down", "pan down")

hl.gesture({
    fingers = 3,
    direction = "up",
    action = route("focus up"),
})
hl.gesture({
    fingers = 3,
    direction = "down",
    action = route("focus down"),
})

-- Wheel and touchpad scrolling pan a scrollable overview. Scroll binds consume
-- the event, so they are only enabled while the focused workspace shows its
-- overview and applications scroll normally the rest of the time.
local scroll_binds = {}
local scroll_binds_enabled = nil
for key, message in pairs({
    mouse_down = "scroll down",
    mouse_up = "scroll up",
    mouse_right = "scroll right",
    mouse_left = "scroll left",
}) do
    local bind = hl.bind(key, function() hl.dispatch(hl.dsp.layout(message)) end)
    bind:set_enabled(false)
    table.insert(scroll_binds, bind)
end

local function sync_scroll_binds()
    local overview_active = rawget(_G, "__hyprscroll2d_is_overview_active")
    local enabled = overview_active ~= nil and overview_active() == true
    if enabled == scroll_binds_enabled then return end
    scroll_binds_enabled = enabled
    for _, bind in ipairs(scroll_binds) do bind:set_enabled(enabled) end
end

_G.__hyprscroll2d_overview_changed = sync_scroll_binds
hl.on("workspace.active", sync_scroll_binds)
hl.on("window.active", sync_scroll_binds)

replace("SUPER + code:20", "Grow window width", "resize width grow", function()
    return hl.dsp.window.resize({ x = -100, y = 0, relative = true })
end)
replace("SUPER + code:21", "Shrink window width", "resize width shrink", function()
    return hl.dsp.window.resize({ x = 100, y = 0, relative = true })
end)
replace("SUPER + SHIFT + code:20", "Shrink window height", "resize height shrink", function()
    return hl.dsp.window.resize({ x = 0, y = -100, relative = true })
end)
replace("SUPER + SHIFT + code:21", "Grow window height", "resize height grow", function()
    return hl.dsp.window.resize({ x = 0, y = 100, relative = true })
end)

_G.__hyprscroll2d_omarchy_integrated = true
return true
