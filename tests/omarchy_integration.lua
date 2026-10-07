local source = debug.getinfo(1, "S").source:sub(2)
local tests_dir = source:match("^(.*)/[^/]+$") or "tests"
local root = tests_dir:match("^(.*)/tests$") or "."

local bindings = {}
local dispatched = {}
local active_layout = "lua:hyprscroll2d"

_G.o = {
    bind = function(keys, _, action)
        bindings[keys] = action
    end,
}

_G.hl = {
    unbind = function() end,
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

bindings["SUPER + M"]()
assert(dispatched[#dispatched].message == "overview", "overview toggle did not reach the layout")
bindings["SUPER + RETURN"]()
assert(dispatched[#dispatched].message == "overview-exit", "Enter did not exit the overview")
bindings["SUPER + ESCAPE"]()
assert(dispatched[#dispatched].message == "overview-exit", "Escape did not exit the overview")

active_layout = "scrolling"
bindings["SUPER + LEFT"]()
assert(dispatched[#dispatched].kind == "focus", "normal layout fallback did not run")
assert(dispatched[#dispatched].direction == "l", "wrong normal focus direction")
local dispatch_count = #dispatched
bindings["SUPER + M"]()
assert(#dispatched == dispatch_count, "overview toggle should not run in another layout")

active_layout = "lua:hyprscroll2d"
bindings["SUPER + SHIFT + code:21"]()
assert(dispatched[#dispatched].message == "resize height grow", "wrong height resize message")

print("ok - mocked Omarchy integration")
