if rawget(_G, "__omalattice_omarchy_integrated") then return true end

local function safe_field(value, field)
    if value == nil then return nil end
    local ok, result = pcall(function() return value[field] end)
    if ok then return result end
end

local function is_omalattice_active()
    local ok, window = pcall(hl.get_active_window)
    if not ok or not window then return false end
    local layout = safe_field(window, "layout")
    return safe_field(layout, "name") == "lua:omalattice"
end

local function route(message, fallback)
    return function()
        local text = type(message) == "function" and message() or message
        local active_layout = is_omalattice_active()
        local overview_active = rawget(_G, "__omalattice_is_overview_active")
        if active_layout and (text ~= "overview-exit" or (overview_active and overview_active())) then
            hl.dispatch(hl.dsp.layout(text))
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
    error("omalattice: unable to resolve integration directory")
end
local integration_dir = source:sub(2):match("^(.*)/[^/]*$")
local workspaces = dofile(integration_dir .. "/workspaces.lua")
local config = dofile(integration_dir:match("^(.*)/integration$") .. "/layout/config.lua")

local TOGGLE_LAYOUT = "omarchy-hyprland-workspace-layout-toggle"
-- Same icon Omarchy uses when it announces a workspace layout change.
local LAYOUT_ICON = "\243\177\130\172"

local sync_horizontal_gestures

-- The toggle script changes the layout asynchronously and no event announces it,
-- so layout-dependent state is refreshed shortly afterwards.
local function resync_later()
    hl.timer(function()
        sync_horizontal_gestures()
        local hover = rawget(_G, "__omalattice_hover")
        if type(hover) == "table" then hover.sync() end
    end, { timeout = 400, type = "oneshot" })
end

_G.__omalattice_resync_later = resync_later

-- Extends Omarchy's dwindle <-> scrolling toggle into
-- dwindle -> scrolling -> Omalattice -> dwindle for the focused workspace.
local function rotate_layout()
    local ok, workspace = pcall(hl.get_active_workspace)
    local id = ok and safe_field(workspace, "id") or nil
    local current = ok and safe_field(workspace, "tiled_layout") or nil

    if current == "scrolling" and not safe_field(workspace, "special") and id then
        if workspaces.add(id) then
            workspaces.apply(id)
            hl.dispatch(hl.dsp.exec_cmd(
                "omarchy-notification-send -g " .. LAYOUT_ICON .. " 'Workspace layout set to omalattice'"
            ))
            resync_later()
            return
        end
    elseif current == workspaces.LAYOUT and id then
        local overview_active = rawget(_G, "__omalattice_is_overview_active")
        if overview_active and overview_active() then
            hl.dispatch(hl.dsp.layout("overview-exit"))
        end
        workspaces.remove(id)
    end

    hl.dispatch(hl.dsp.exec_cmd(TOGGLE_LAYOUT))
    resync_later()
end

hl.unbind("SUPER + L")
o.bind("SUPER + L", "Toggle workspace layout", rotate_layout)
_G.__omalattice_rotate_layout = rotate_layout

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

local GESTURE_FINGERS = config.gesture_fingers or 3

-- With natural scrolling the content follows the fingers, so swiping up
-- reveals the window below. The touchpad setting is read on every swipe.
local function natural_scroll()
    local ok, value = pcall(hl.get_config, "input.touchpad.natural_scroll")
    return ok and value == true
end

local function swipe_focus(swipe, natural_target)
    return function()
        return "focus " .. (natural_scroll() and natural_target or swipe)
    end
end

hl.gesture({
    fingers = GESTURE_FINGERS,
    direction = "up",
    action = route(swipe_focus("up", "down")),
})
hl.gesture({
    fingers = GESTURE_FINGERS,
    direction = "down",
    action = route(swipe_focus("down", "up")),
})

-- Hyprland has a single gesture per direction and no fallback, and a horizontal
-- swipe is normally taken by the workspace swipe. Swap it for left/right focus
-- gestures while an Omalattice workspace is active, then restore it. Hyprland
-- cannot report which gestures exist and logs an error for removing a missing
-- one, so this only happens when config.workspace_swipe says there is one.
local focus_gestures = {
    { fingers = GESTURE_FINGERS, direction = "left", action = route(swipe_focus("left", "right")) },
    { fingers = GESTURE_FINGERS, direction = "right", action = route(swipe_focus("right", "left")) },
}
local workspace_gesture = { fingers = GESTURE_FINGERS, direction = "horizontal", action = "workspace" }
local swap_workspace_swipe = config.workspace_swipe ~= false
local horizontal_focus = false

local function unset(gesture)
    hl.gesture({ fingers = gesture.fingers, direction = gesture.direction, action = "unset" })
end

function sync_horizontal_gestures()
    if not swap_workspace_swipe then return end

    local ok, workspace = pcall(hl.get_active_workspace)
    local want = ok and safe_field(workspace, "tiled_layout") == workspaces.LAYOUT
        and not safe_field(workspace, "special") or false
    if want == horizontal_focus then return end
    horizontal_focus = want

    if want then
        unset(workspace_gesture)
        for _, gesture in ipairs(focus_gestures) do hl.gesture(gesture) end
    else
        for _, gesture in ipairs(focus_gestures) do unset(gesture) end
        hl.gesture(workspace_gesture)
    end
end

if not swap_workspace_swipe then
    for _, gesture in ipairs(focus_gestures) do hl.gesture(gesture) end
end

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
    local overview_active = rawget(_G, "__omalattice_is_overview_active")
    local enabled = overview_active ~= nil and overview_active() == true
    if enabled == scroll_binds_enabled then return end
    scroll_binds_enabled = enabled
    for _, bind in ipairs(scroll_binds) do bind:set_enabled(enabled) end
end

_G.__omalattice_overview_changed = sync_scroll_binds
hl.on("workspace.active", sync_scroll_binds)
hl.on("window.active", sync_scroll_binds)

hl.on("workspace.active", sync_horizontal_gestures)
hl.on("monitor.focused", sync_horizontal_gestures)
hl.on("window.active", sync_horizontal_gestures)
sync_horizontal_gestures()

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

_G.__omalattice_omarchy_integrated = true
return true
