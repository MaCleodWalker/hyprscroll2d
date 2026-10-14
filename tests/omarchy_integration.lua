local source = debug.getinfo(1, "S").source:sub(2)
local tests_dir = source:match("^(.*)/[^/]+$") or "tests"
local root = tests_dir:match("^(.*)/tests$") or "."

local state_home = os.tmpname()
os.remove(state_home)
assert(os.execute("mkdir -p '" .. state_home .. "'"))
local original_getenv = os.getenv
os.getenv = function(name)
    if name == "XDG_STATE_HOME" then return state_home end
    return original_getenv(name)
end

local function saved_workspaces()
    local file = io.open(state_home .. "/hyprscroll2d/workspaces", "r")
    if not file then return "" end
    local content = file:read("*a")
    file:close()
    return content
end

local bindings = {}
local dispatched = {}
local gestures = {}
local active_layout = "lua:hyprscroll2d"
local active_workspace = { id = 3, tiled_layout = "dwindle", special = false }
local workspace_rules = {}
local terminal_launches = 0
local terminal_action_creations = 0
local overview_active = false
_G.__hyprscroll2d_is_overview_active = function()
    return overview_active
end

_G.o = {
    bind = function(keys, _, action)
        bindings[keys] = action
    end,
    launch_terminal = function()
        terminal_action_creations = terminal_action_creations + 1
        return function()
            terminal_launches = terminal_launches + 1
        end
    end,
}

local scroll_binds = {}

_G.hl = {
    bind = function(keys, action)
        local bind = { keys = keys, action = action, enabled = true }
        function bind:set_enabled(value) self.enabled = value end
        scroll_binds[keys] = bind
        return bind
    end,
    layout = {
        register = function() end,
    },
    on = function()
        return true
    end,
    unbind = function() end,
    gesture = function(spec)
        table.insert(gestures, spec)
    end,
    workspace_rule = function(rule)
        table.insert(workspace_rules, rule)
    end,
    get_active_workspace = function()
        return active_workspace
    end,
    get_active_window = function()
        return { layout = { name = active_layout } }
    end,
    dispatch = function(value)
        table.insert(dispatched, value)
    end,
    dsp = {
        layout = function(message) return { kind = "layout", message = message } end,
        exec_cmd = function(command) return { kind = "exec", command = command } end,
        focus = function(options) return { kind = "focus", direction = options.direction } end,
        window = {
            swap = function(options) return { kind = "swap", direction = options.direction } end,
            resize = function(options) return { kind = "resize", options = options } end,
        },
        group = {
            prev = function() return { kind = "group-prev" } end,
            next = function() return { kind = "group-next" } end,
        },
    },
}

assert(loadfile(root .. "/integration/omarchy.lua"))()
assert(terminal_action_creations == 1, "terminal binding should be captured during integration setup")
assert(#gestures == 2, "three-finger vertical focus gestures were not installed")
assert(gestures[1].fingers == 3 and gestures[1].direction == "up", "wrong upward focus gesture")
assert(gestures[2].fingers == 3 and gestures[2].direction == "down", "wrong downward focus gesture")

assert(type(bindings["SUPER + LEFT"]) == "function", "left binding was not installed")
bindings["SUPER + LEFT"]()
assert(dispatched[#dispatched].kind == "layout", "2D layout did not receive focus")
assert(dispatched[#dispatched].message == "focus left", "wrong 2D focus message")

bindings["SUPER + RETURN"]()
assert(terminal_launches == 1, "Enter should launch the terminal outside overview")

bindings["SUPER + M"]()
assert(dispatched[#dispatched].message == "overview", "overview toggle did not reach the layout")
overview_active = true
bindings["SUPER + RETURN"]()
assert(dispatched[#dispatched].message == "overview-exit", "Enter did not exit the overview")
assert(terminal_launches == 1, "Enter should not launch a terminal in overview")
overview_active = false
bindings["SUPER + ESCAPE"]()
assert(dispatched[#dispatched].message == "overview-exit", "Escape did not exit the overview")

active_layout = "scrolling"
bindings["SUPER + LEFT"]()
assert(dispatched[#dispatched].kind == "focus", "normal layout fallback did not run")
assert(dispatched[#dispatched].direction == "l", "wrong normal focus direction")
local dispatch_count = #dispatched
bindings["SUPER + M"]()
assert(#dispatched == dispatch_count, "overview toggle should not run in another layout")
bindings["SUPER + RETURN"]()
assert(terminal_launches == 2, "Enter should launch the Omarchy terminal outside Hyprscroll2D")

active_layout = "lua:hyprscroll2d"
gestures[1].action()
assert(dispatched[#dispatched].kind == "layout", "up gesture did not focus in Hyprscroll2D")
assert(dispatched[#dispatched].message == "focus up", "up gesture sent the wrong layout command")
gestures[2].action()
assert(dispatched[#dispatched].message == "focus down", "down gesture sent the wrong layout command")

active_layout = "scrolling"
local gesture_dispatch_count = #dispatched
gestures[1].action()
gestures[2].action()
assert(#dispatched == gesture_dispatch_count, "vertical gestures should not affect other layouts")

active_layout = "lua:hyprscroll2d"
bindings["SUPER + SHIFT + code:21"]()
assert(dispatched[#dispatched].message == "resize height grow", "wrong height resize message")

local function last_exec()
    local item = dispatched[#dispatched]
    return item.kind == "exec" and item.command or nil
end

assert(type(bindings["SUPER + L"]) == "function", "layout rotation binding was not installed")
assert(_G.__hyprscroll2d_rotate_layout == bindings["SUPER + L"], "layout rotation was not exposed")

-- dwindle -> scrolling is left to Omarchy's own toggle.
active_workspace = { id = 3, tiled_layout = "dwindle", special = false }
bindings["SUPER + L"]()
assert(last_exec() == "omarchy-hyprland-workspace-layout-toggle", "dwindle should use Omarchy's toggle")
assert(saved_workspaces() == "", "dwindle step should not save a workspace")

-- scrolling -> Hyprscroll2D on the focused workspace only.
active_workspace = { id = 3, tiled_layout = "scrolling", special = false }
bindings["SUPER + L"]()
assert(#workspace_rules == 1 and workspace_rules[1].workspace == "3"
    and workspace_rules[1].layout == "lua:hyprscroll2d", "scrolling did not rotate into Hyprscroll2D")
assert(saved_workspaces() == "3\n", "rotated workspace was not saved")
assert(last_exec():find("omarchy-notification-send", 1, true), "rotation did not notify")

-- Hyprscroll2D -> dwindle, forgetting the workspace and leaving overview first.
active_workspace = { id = 3, tiled_layout = "lua:hyprscroll2d", special = false }
overview_active = true
bindings["SUPER + L"]()
assert(dispatched[#dispatched - 1].message == "overview-exit", "overview should exit before leaving the layout")
assert(last_exec() == "omarchy-hyprland-workspace-layout-toggle", "Hyprscroll2D should hand back to Omarchy")
assert(saved_workspaces() == "", "workspace was not forgotten")
overview_active = false

-- Special workspaces never rotate into Hyprscroll2D.
active_workspace = { id = -98, tiled_layout = "scrolling", special = true }
bindings["SUPER + L"]()
assert(last_exec() == "omarchy-hyprland-workspace-layout-toggle", "special workspace should use Omarchy's toggle")
assert(saved_workspaces() == "", "special workspace was saved")

-- Scroll binds are consuming, so they stay off until an overview is open.
for _, key in ipairs({ "mouse_down", "mouse_up", "mouse_left", "mouse_right" }) do
    assert(scroll_binds[key] and not scroll_binds[key].enabled, key .. " scroll bind should start disabled")
end
overview_active = true
_G.__hyprscroll2d_overview_changed()
for _, key in ipairs({ "mouse_down", "mouse_up", "mouse_left", "mouse_right" }) do
    assert(scroll_binds[key].enabled, key .. " scroll bind should enable with the overview")
end
scroll_binds.mouse_down.action()
assert(dispatched[#dispatched].message == "scroll down", "wheel down did not scroll the overview")
scroll_binds.mouse_left.action()
assert(dispatched[#dispatched].message == "scroll left", "wheel left did not scroll the overview")
overview_active = false
_G.__hyprscroll2d_overview_changed()
assert(not scroll_binds.mouse_down.enabled, "scroll bind should disable when the overview closes")

-- The plugin restores saved workspaces and pins nothing by default.
local workspace_file = assert(io.open(state_home .. "/hyprscroll2d/workspaces", "w"))
workspace_file:write("5\n7\n")
workspace_file:close()
workspace_rules = {}
assert(loadfile(root .. "/integration/plugin.lua"))()
assert(#workspace_rules == 2 and workspace_rules[1].workspace == "5" and workspace_rules[2].workspace == "7",
    "plugin did not restore saved workspaces")
workspace_rules = {}
assert(loadfile(root .. "/integration/plugin.lua"))()
assert(#workspace_rules == 2, "plugin reload did not reapply saved workspaces")

local config = assert(loadfile(root .. "/layout/config.lua"))()
assert(config.workspace == nil, "Hyprscroll2D should not pin a workspace by default")

os.getenv = original_getenv
os.execute("rm -rf '" .. state_home .. "'")

print("ok - mocked Omarchy integration")
