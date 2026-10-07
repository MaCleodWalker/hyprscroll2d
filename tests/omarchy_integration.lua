local source = debug.getinfo(1, "S").source:sub(2)
local tests_dir = source:match("^(.*)/[^/]+$") or "tests"
local root = tests_dir:match("^(.*)/tests$") or "."

local bindings = {}
local dispatched = {}
local active_layout = "lua:hyprscroll2d"
local workspace_rule = nil
local terminal_launches = 0
local overview_active = false
_G.__hyprscroll2d_is_overview_active = function()
    return overview_active
end

_G.o = {
    bind = function(keys, _, action)
        bindings[keys] = action
    end,
    launch_terminal = function()
        return function()
            terminal_launches = terminal_launches + 1
        end
    end,
}

_G.hl = {
    layout = {
        register = function() end,
    },
    on = function()
        return true
    end,
    unbind = function() end,
    workspace_rule = function(rule)
        workspace_rule = rule
    end,
    get_active_window = function()
        return { layout = { name = active_layout } }
    end,
    dispatch = function(value)
        table.insert(dispatched, value)
    end,
    dsp = {
        layout = function(message) return { kind = "layout", message = message } end,
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
bindings["SUPER + SHIFT + code:21"]()
assert(dispatched[#dispatched].message == "resize height grow", "wrong height resize message")

assert(loadfile(root .. "/integration/plugin.lua"))()
local config = assert(loadfile(root .. "/layout/config.lua"))()
assert(workspace_rule and workspace_rule.workspace == tostring(config.workspace),
    "plugin did not use the configured workspace")
workspace_rule = nil
assert(loadfile(root .. "/integration/plugin.lua"))()
assert(workspace_rule and workspace_rule.workspace == tostring(config.workspace),
    "plugin reload did not reapply the configured workspace")

print("ok - mocked Omarchy integration")
