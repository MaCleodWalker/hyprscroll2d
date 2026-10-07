local source = debug.getinfo(1, "S").source:sub(2)
local tests_dir = source:match("^(.*)/[^/]+$") or "tests"
local root = tests_dir:match("^(.*)/tests$") or "."

local registered = nil
local dispatched = {}
local active_callback = nil
local dispatch_context = nil
local cursor = nil

_G.__hyprscroll2d_focus_subscription = nil
_G.hl = {
    layout = {
        register = function(name, provider)
            registered = { name = name, provider = provider }
        end,
    },
    on = function(_, callback)
        active_callback = callback
        return true
    end,
    get_active_window = function()
        return { workspace = { id = 9 } }
    end,
    dispatch = function(dispatcher)
        table.insert(dispatched, dispatcher)
        if dispatcher.kind == "layout" and dispatch_context then
            registered.provider.layout_msg(dispatch_context, dispatcher.message)
            registered.provider.recalculate(dispatch_context)
        elseif dispatcher.kind == "cursor" then
            cursor = { x = dispatcher.x, y = dispatcher.y }
        end
        return { ok = true }
    end,
    dsp = {
        layout = function(message)
            return { kind = "layout", message = message }
        end,
        focus = function(options)
            return { kind = "focus", window = options.window }
        end,
        cursor = {
            move = function(options)
                return { kind = "cursor", x = options.x, y = options.y }
            end,
        },
    },
}

assert(loadfile(root .. "/layout/init.lua"))()
assert(registered and registered.name == "hyprscroll2d", "layout did not register")

local function target(id, active, workspace)
    return {
        window = {
            stable_id = id,
            address = "0x" .. id,
            active = active,
            mapped = true,
            workspace = { id = workspace or 9 },
            layout = { name = "lua:hyprscroll2d" },
        },
        place = function(self, box)
            self.placed = box
            self.window.at = { x = box.x, y = box.y }
            self.window.size = { x = box.w, y = box.h }
        end,
    }
end

local a = target("A", true)
local b = target("B", false)
local ctx = {
    area = { x = 0, y = 0, w = 1000, h = 800 },
    targets = { a, b },
}

registered.provider.recalculate(ctx)
assert(a.placed and b.placed, "recalculate did not place every target")
assert(a.placed.x < b.placed.x, "new targets should initially extend right")

local response = registered.provider.layout_msg(ctx, "focus right")
assert(response == true, "focus command was rejected")
assert(dispatched[#dispatched].kind == "focus", "focus command did not dispatch")
assert(dispatched[#dispatched].window == "address:0xB", "focus targeted the wrong window")

response = registered.provider.layout_msg(ctx, "resize height shrink")
assert(response == true, "height resize command was rejected")

response = registered.provider.layout_msg(ctx, "resize height sideways")
assert(type(response) == "string", "invalid resize command should return an error")

response = registered.provider.layout_msg(ctx, "overview")
assert(response == true, "overview command was rejected")
assert(_G.__hyprscroll2d_is_overview_active(), "overview state was not exposed to keybindings")
registered.provider.recalculate(ctx)
assert(a.placed.x >= 0 and b.placed.x + b.placed.w <= ctx.area.w, "overview windows should fit the viewport")

a.window.active = false
b.window.active = true
local dispatch_count = #dispatched
active_callback(b.window)
assert(#dispatched == dispatch_count, "mouse selection should not exit overview")

response = registered.provider.layout_msg(ctx, "overview-exit")
assert(response == true, "overview exit command was rejected")
assert(not _G.__hyprscroll2d_is_overview_active(), "overview state remained active after exit")
registered.provider.recalculate(ctx)
assert(b.placed.x > a.placed.x, "overview exit should restore the normal layout")

local function activate(context, selected)
    for _, item in ipairs(context.targets) do
        item.window.active = item == selected
    end
end

local function under_cursor(context)
    for _, item in ipairs(context.targets) do
        local box = item.placed
        if cursor.x >= box.x and cursor.x < box.x + box.w
            and cursor.y >= box.y and cursor.y < box.y + box.h then
            return item
        end
    end
end

for index, direction in ipairs({ "right", "left", "down", "up" }) do
    local vertical = direction == "down" or direction == "up"
    local forward = direction == "right" or direction == "down"
    local items = {}
    for i = 1, 4 do
        items[i] = target(direction .. i, i == 1, 20 + index)
    end
    local context = {
        area = { x = 100, y = 200, w = 1000, h = 800 },
        targets = items,
    }
    registered.provider.recalculate(context)
    if vertical then
        for i = 2, #items do
            activate(context, items[i])
            for _ = 1, i - 1 do
                registered.provider.layout_msg(context, "move down")
            end
            for _ = 1, i - 1 do
                registered.provider.layout_msg(context, "move left")
            end
        end
    end
    activate(context, items[forward and 1 or 4])
    registered.provider.recalculate(context)
    cursor = {
        x = vertical and 600 or (forward and 1080 or 120),
        y = vertical and (forward and 980 or 220) or 600,
    }
    local next_window = items[forward and 2 or 3]
    assert(under_cursor(context) == next_window, direction .. " peek should show the next window")

    dispatch_context = context
    activate(context, next_window)
    active_callback(next_window.window)
    assert(under_cursor(context) == next_window,
        direction .. " mouse focus must stop at the next window after scrolling")
    assert(next_window.window.active, direction .. " next window should remain focused")
    assert(cursor.x == 600 and cursor.y == 600,
        direction .. " cursor should use the centered geometry, not the old peek")
    dispatch_context = nil
end

dispatch_count = #dispatched
active_callback({ layout = { name = "dwindle" } })
assert(#dispatched == dispatch_count, "other layouts should not move the cursor")

print("ok - mocked Hyprland adapter")
