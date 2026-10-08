local source = debug.getinfo(1, "S").source:sub(2)
local tests_dir = source:match("^(.*)/[^/]+$") or "tests"
local root = tests_dir:match("^(.*)/tests$") or "."
local core = assert(loadfile(root .. "/layout/core.lua"))()
local config = assert(loadfile(root .. "/layout/config.lua"))()
local passed = 0

local function test(name, fn)
    local ok, err = pcall(fn)
    if not ok then
        io.stderr:write("FAIL: " .. name .. "\n" .. tostring(err) .. "\n")
        os.exit(1)
    end
    passed = passed + 1
    print("ok - " .. name)
end

local function equal(actual, expected, label)
    if actual ~= expected then
        error((label or "value") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
    end
end

local function fresh(ids, active)
    local state = core.new_state()
    core.sync(state, ids, active, config)
    return state
end

test("first window starts at origin", function()
    local state = fresh({ "A" }, "A")
    equal(core.position_of(state, "A").col, 0)
    equal(core.position_of(state, "A").row, 0)
end)

test("new windows extend to the right", function()
    local state = fresh({ "A", "B", "C" }, "A")
    equal(core.position_of(state, "B").col, 1)
    equal(core.position_of(state, "C").col, 2)
end)

test("moving down creates a second row", function()
    local state = fresh({ "A", "B" }, "B")
    assert(core.move(state, "down"))
    equal(core.position_of(state, "B").col, 1)
    equal(core.position_of(state, "B").row, 1)
    equal(state.camera.row, 1)
end)

test("moving into an occupied cell swaps windows", function()
    local state = fresh({ "A", "B" }, "B")
    assert(core.move(state, "left"))
    equal(core.position_of(state, "B").col, 0)
    equal(core.position_of(state, "A").col, 1)
end)

test("focus prefers a window aligned on the requested axis", function()
    local state = fresh({ "A", "B", "C" }, "A")
    core.move(state, "down")
    state.focused_id = "A"
    core.follow(state)
    equal(core.focus(state, "right"), "B")
end)

test("focus moves vertically", function()
    local state = fresh({ "A", "B" }, "B")
    core.move(state, "down")
    state.focused_id = "A"
    core.follow(state)
    equal(core.focus(state, "down"), "B")
end)

test("overview fits every window and preserves arrow selection until exit", function()
    local state = fresh({ "A", "B", "C" }, "B")
    core.move(state, "down")
    core.set_overview(state, true)
    local area = { x = 0, y = 0, w = 1000, h = 800 }
    local placements = core.overview_placements(state, area, config)

    for _, placement in pairs(placements) do
        assert(placement.x >= area.x and placement.y >= area.y)
        assert(placement.x + placement.w <= area.x + area.w)
        assert(placement.y + placement.h <= area.y + area.h)
    end

    local camera_col, camera_row = state.camera.col, state.camera.row
    equal(core.focus(state, "left"), "A")
    equal(state.camera.col, camera_col, "overview camera column")
    equal(state.camera.row, camera_row, "overview camera row")
    core.set_overview(state, false)
    equal(state.camera.col, core.position_of(state, "A").col, "camera follows selected window")
    equal(state.camera.row, core.position_of(state, "A").row, "camera follows selected window")
end)

test("overview packs sparse positions into dense rows and columns", function()
    local state = fresh({ "A", "B", "C" }, "A")
    state.positions.A = { col = -1000, row = 50 }
    state.positions.B = { col = 1000, row = -90 }
    state.positions.C = { col = 1000000, row = 10000 }
    local placements = core.overview_placements(state, { x = 0, y = 0, w = 300, h = 200 }, config)

    for _, placement in pairs(placements) do
        assert(placement.x >= 0 and placement.y >= 0)
        assert(placement.x + placement.w <= 300)
        assert(placement.y + placement.h <= 200)
    end
end)

test("overview caps gaps when the viewport is too small for all cells", function()
    local state = fresh({ "A", "B", "C", "D", "E", "F", "G", "H", "I", "J" }, "A")
    for index, id in ipairs(state.ids) do
        state.positions[id] = { col = index * 1000, row = index * -1000 }
    end
    local overview_config = {
        width_steps = { 1 },
        height_steps = { 1 },
        default_width_step = 1,
        default_height_step = 1,
        gap_x = 1000,
        gap_y = 1000,
    }
    local area = { x = 0, y = 0, w = 50, h = 40 }
    local placements = core.overview_placements(state, area, overview_config)

    for _, placement in pairs(placements) do
        assert(placement.x >= area.x and placement.y >= area.y)
        assert(placement.x + placement.w <= area.x + area.w)
        assert(placement.y + placement.h <= area.y + area.h)
    end
end)

test("width and height presets are independent", function()
    local state = fresh({ "A" }, "A")
    core.resize_width(state, config, 1)
    core.resize_height(state, config, -1)
    local width_step, height_step = core.size_steps_of(state, "A")
    equal(width_step, 3)
    equal(height_step, 2)
end)

test("resize clamps at preset boundaries", function()
    local state = fresh({ "A" }, "A")
    for _ = 1, 10 do core.resize_width(state, config, -1) end
    local width_step = core.size_steps_of(state, "A")
    equal(width_step, 1)
    for _ = 1, 10 do core.resize_width(state, config, 1) end
    width_step = core.size_steps_of(state, "A")
    equal(width_step, #config.width_steps)
end)

test("maximum cell leaves horizontal and vertical peeks", function()
    local state = fresh({ "A", "B" }, "A")
    state.width_step_by_id.A = #config.width_steps
    state.height_step_by_id.A = #config.height_steps
    state.width_step_by_id.B = #config.width_steps
    state.height_step_by_id.B = #config.height_steps
    state.focused_id = "B"
    core.move(state, "down")
    state.focused_id = "A"
    core.follow(state)
    local placements = core.placements(state, { x = 0, y = 0, w = 1000, h = 800 }, config)
    equal(placements.A.x, 48)
    equal(placements.A.y, 48)
    equal(placements.A.w, 904)
    equal(placements.A.h, 704)
    equal(placements.B.y, 764)
end)

test("smaller presets keep neighboring rows visible", function()
    local state = fresh({ "A", "B" }, "A")
    state.focused_id = "B"
    core.move(state, "down")
    state.focused_id = "A"
    core.follow(state)
    local placements = core.placements(state, { x = 0, y = 0, w = 1000, h = 800 }, config)
    assert(placements.B.y < 800, "the next row should peek into the viewport")
    assert(placements.B.y > placements.A.y, "the next row should remain below the focused row")
end)

test("camera follows focus in both dimensions", function()
    local state = fresh({ "A", "B" }, "B")
    core.move(state, "down")
    equal(state.camera.col, 1)
    equal(state.camera.row, 1)
end)

test("manual camera pan survives ordinary synchronization", function()
    local state = fresh({ "A" }, "A")
    core.pan(state, "down")
    core.sync(state, { "A" }, "A", config)
    equal(state.camera.row, 1)
end)

test("closed windows are removed without disturbing survivors", function()
    local state = fresh({ "A", "B", "C" }, "B")
    local original = core.position_of(state, "C").col
    core.sync(state, { "A", "C" }, "C", config)
    assert(not core.has_id(state, "B"))
    equal(core.position_of(state, "C").col, original)
end)

print(string.format("hyprscroll2d: %d tests passed", passed))
