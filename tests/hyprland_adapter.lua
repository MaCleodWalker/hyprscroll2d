local source = debug.getinfo(1, "S").source:sub(2)
local tests_dir = source:match("^(.*)/[^/]+$") or "tests"
local root = tests_dir:match("^(.*)/tests$") or "."

local registered = nil
local dispatched = {}
local active_callback = nil
local dispatch_context = nil
local cursor = nil
local timer_callback = nil
local timer_enabled = nil
local overview_status = nil
local original_getenv = os.getenv
local original_open = io.open

os.getenv = function(name)
    if name == "XDG_RUNTIME_DIR" then return "/tmp" end
    return original_getenv(name)
end
io.open = function(path, mode)
    assert(path == "/tmp/omalattice-overview" and mode == "w", "unexpected overview status path")
    return {
        write = function(_, value)
            overview_status = value
            return true
        end,
        close = function()
            return true
        end,
    }
end

_G.__omalattice_focus_subscription = nil
_G.hl = {
    layout = {
        register = function(name, provider)
            registered = { name = name, provider = provider }
        end,
    },
    on = function(event, callback)
        if event == "window.active" and not active_callback then active_callback = callback end
        return true
    end,
    get_active_window = function()
        return { workspace = { id = 9 } }
    end,
    get_cursor_pos = function() return cursor end,
    timer = function(callback)
        timer_callback = callback
        return { set_enabled = function(_, value) timer_enabled = value end }
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
assert(registered and registered.name == "omalattice", "layout did not register")
assert(overview_status == '{"workspace":"none","overview":false}', "overview status was not reset on load")

local function target(id, active, workspace)
    return {
        window = {
            stable_id = id,
            address = "0x" .. id,
            active = active,
            mapped = true,
            workspace = { id = workspace or 9 },
            layout = { name = "lua:omalattice" },
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
assert(_G.__omalattice_is_overview_active(), "overview state was not exposed to keybindings")
assert(overview_status == '{"workspace":"workspace:9","overview":true}', "overview status was not published")
local normal_width = a.placed.w
registered.provider.recalculate(ctx)

-- The shell draws scaled tiles inside the viewport; the real windows keep their size.
local function tile(address)
    local x, y, w, h = overview_status:match('"address":"' .. address .. '","x":([%-%d.]+),"y":([%-%d.]+),"w":([%d.]+),"h":([%d.]+)')
    return tonumber(x), tonumber(y), tonumber(w), tonumber(h)
end
local ax, _, aw = tile("0xA")
local bx, _, bw = tile("0xB")
assert(ax and bx, "overview tiles were not published: " .. tostring(overview_status))
assert(ax >= 0 and bx + bw <= ctx.area.w, "overview tiles should fit the viewport")
assert(aw < normal_width, "overview tiles should be smaller than the windows")
assert(a.placed.w == normal_width, "overview should not resize the real windows")
assert(a.placed.x >= 0 and a.placed.x + a.placed.w <= ctx.area.w, "overview windows should stay on screen to be captured")
assert(a.placed.x == b.placed.x, "overview windows should be stacked")
assert(overview_status:find('"thumbnails":true', 1, true), "thumbnails should be enabled by default")

a.window.active = false
b.window.active = true
local dispatch_count = #dispatched
active_callback(b.window)
assert(#dispatched == dispatch_count, "mouse selection should not exit overview")

response = registered.provider.layout_msg(ctx, "overview-exit")
assert(response == true, "overview exit command was rejected")
assert(not _G.__omalattice_is_overview_active(), "overview state remained active after exit")
assert(overview_status == '{"workspace":"workspace:9","overview":false}', "overview exit status was not published")
registered.provider.recalculate(ctx)
assert(b.placed.x > a.placed.x, "overview exit should restore the normal layout")

-- A workspace too large for the minimum cell size scrolls and reports scroll bars.
local overview_changes = 0
_G.__omalattice_overview_changed = function() overview_changes = overview_changes + 1 end
local crowded_targets = {}
for i = 1, 8 do crowded_targets[i] = target("crowd" .. i, i == 1, 30) end
local crowded = { area = { x = 0, y = 0, w = 1000, h = 800 }, targets = crowded_targets }
registered.provider.recalculate(crowded)
assert(registered.provider.layout_msg(crowded, "scroll right") == true, "scroll command was rejected")

response = registered.provider.layout_msg(crowded, "overview")
assert(response == true, "overview command was rejected for the crowded workspace")
assert(overview_changes == 1, "overview change was not announced")
registered.provider.recalculate(crowded)
local x_start, x_size = overview_status:match('"bars":%[([%d.]+),([%d.]+),')
assert(x_start and tonumber(x_size) < 1, "scroll bars were not published: " .. tostring(overview_status))

local before_scroll = tile("0xcrowd1")
assert(registered.provider.layout_msg(crowded, "scroll right") == true, "scroll command was rejected")
registered.provider.recalculate(crowded)
assert(tile("0xcrowd1") < before_scroll, "scrolling right should move the tiles left")

response = registered.provider.layout_msg(crowded, "overview-exit")
assert(response == true and overview_changes == 2, "overview exit was not announced")
assert(overview_status == '{"workspace":"workspace:30","overview":false}', "overview exit should clear the scroll bars")
_G.__omalattice_overview_changed = nil

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
            -- Gaps close up, so the next window is always one column from the stack.
            registered.provider.layout_msg(context, "move left")
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

-- Without thumbnails the overview resizes the real windows, as before.
local real_loadfile = loadfile
_G.__omalattice_layout_registered = nil
_G.loadfile = function(path)
    local chunk, err = real_loadfile(path)
    if chunk and path:match("config%.lua$") then
        return function()
            local loaded = chunk()
            loaded.overview_thumbnails = false
            return loaded
        end
    end
    return chunk, err
end
assert(real_loadfile(root .. "/layout/init.lua"))()
_G.loadfile = real_loadfile

local legacy_a = target("legacyA", true, 40)
local legacy_b = target("legacyB", false, 40)
local legacy = { area = { x = 0, y = 0, w = 1000, h = 800 }, targets = { legacy_a, legacy_b } }
registered.provider.recalculate(legacy)
local full_width = legacy_a.placed.w
assert(registered.provider.layout_msg(legacy, "overview") == true, "legacy overview command was rejected")
registered.provider.recalculate(legacy)
assert(legacy_a.placed.w < full_width, "legacy overview should resize the real windows")
assert(overview_status:find('"thumbnails":false', 1, true), "legacy overview should not request thumbnails")

-- A crowded overview pans on its own while the pointer rests near an edge.
local crowded9_targets = {}
for i = 1, 8 do crowded9_targets[i] = target("auto" .. i, i == 1, 9) end
local crowded9 = { area = { x = 100, y = 200, w = 1000, h = 800 }, targets = crowded9_targets }
registered.provider.recalculate(crowded9)
assert(registered.provider.layout_msg(crowded9, "overview") == true, "overview command was rejected")
assert(timer_callback and timer_enabled == true, "auto-scroll did not start with the overview")
dispatch_context = crowded9
registered.provider.recalculate(crowded9)
local first_tile = tile("0xauto1")

cursor = { x = 600, y = 600 }
dispatch_count = #dispatched
timer_callback()
assert(#dispatched == dispatch_count, "a centred pointer should not scroll")

cursor = { x = 1099, y = 600 }
timer_callback()
assert(dispatched[#dispatched].message == "refresh", "an edge pointer did not refresh the overview")
assert(tile("0xauto1") < first_tile, "the overview did not pan toward the pointer")

cursor = { x = 500, y = 600 }
for _ = 1, 400 do
    cursor = { x = 1099, y = 600 }
    timer_callback()
end
dispatch_count = #dispatched
timer_callback()
assert(#dispatched == dispatch_count, "scrolling should stop at the end of the content")

-- Clicking a thumbnail closes the overview and moves the pointer into the window.
cursor = { x = 5, y = 5 }
registered.provider.layout_msg(crowded9, "overview-exit click")
assert(timer_enabled == false, "auto-scroll kept running after the overview closed")
registered.provider.recalculate(crowded9)
local entered = crowded9_targets[1].placed
assert(cursor.x == entered.x + entered.w / 2 and cursor.y == entered.y + entered.h / 2,
    "the pointer did not move into the entered window")
dispatch_context = nil

os.getenv = original_getenv
io.open = original_open

print("ok - mocked Hyprland adapter")
