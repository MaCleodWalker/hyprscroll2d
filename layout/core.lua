local M = {}

local DIRECTIONS = {
    left = { dc = -1, dr = 0 },
    right = { dc = 1, dr = 0 },
    up = { dc = 0, dr = -1 },
    down = { dc = 0, dr = 1 },
}

local function clamp(value, minimum, maximum)
    return math.max(minimum, math.min(maximum, value))
end

local function contains(values, wanted)
    for _, value in ipairs(values or {}) do
        if value == wanted then
            return true
        end
    end
    return false
end

local function position_key(col, row)
    return tostring(col) .. ":" .. tostring(row)
end

local function occupied_positions(state, except_id)
    local occupied = {}
    for id, position in pairs(state.positions) do
        if id ~= except_id then
            occupied[position_key(position.col, position.row)] = id
        end
    end
    return occupied
end

local function find_open_right(state, anchor)
    local occupied = occupied_positions(state)
    local col = anchor.col + 1
    while occupied[position_key(col, anchor.row)] do
        col = col + 1
    end
    return { col = col, row = anchor.row }
end

local function first_id(state)
    return state.ids[1]
end

function M.new_state()
    return {
        ids = {},
        positions = {},
        width_step_by_id = {},
        height_step_by_id = {},
        focused_id = nil,
        observed_active_id = nil,
        camera = { col = 0, row = 0 },
        overview = false,
    }
end

function M.sync(state, ids, active_id, config)
    local present = {}
    local unique_ids = {}

    for _, id in ipairs(ids or {}) do
        if not present[id] then
            present[id] = true
            table.insert(unique_ids, id)
        end
    end

    for id in pairs(state.positions) do
        if not present[id] then
            state.positions[id] = nil
            state.width_step_by_id[id] = nil
            state.height_step_by_id[id] = nil
        end
    end

    state.ids = unique_ids

    for _, id in ipairs(unique_ids) do
        if not state.positions[id] then
            local anchor_id = active_id and state.positions[active_id] and active_id
                or state.focused_id and state.positions[state.focused_id] and state.focused_id
                or first_id(state)
            local anchor = anchor_id and state.positions[anchor_id]

            if anchor then
                state.positions[id] = find_open_right(state, anchor)
            else
                state.positions[id] = { col = 0, row = 0 }
            end

            state.width_step_by_id[id] = config.default_width_step
            state.height_step_by_id[id] = config.default_height_step
        end
    end

    local focus_changed = false
    if active_id and present[active_id] then
        focus_changed = state.observed_active_id ~= active_id
        state.observed_active_id = active_id
        state.focused_id = active_id
    elseif not state.focused_id or not present[state.focused_id] then
        state.focused_id = unique_ids[1]
        state.observed_active_id = state.focused_id
        focus_changed = state.focused_id ~= nil
    end

    if focus_changed and state.focused_id and state.positions[state.focused_id] then
        local focused = state.positions[state.focused_id]
        state.camera.col = focused.col
        state.camera.row = focused.row
    end
end

local function directional_metrics(origin, candidate, direction)
    local dc = candidate.col - origin.col
    local dr = candidate.row - origin.row

    if direction == "left" and dc >= 0 then return nil end
    if direction == "right" and dc <= 0 then return nil end
    if direction == "up" and dr >= 0 then return nil end
    if direction == "down" and dr <= 0 then return nil end

    local along = (direction == "left" or direction == "right") and math.abs(dc) or math.abs(dr)
    local across = (direction == "left" or direction == "right") and math.abs(dr) or math.abs(dc)

    return {
        aligned = across == 0 and 0 or 1,
        across = across,
        along = along,
        distance = math.abs(dc) + math.abs(dr),
    }
end

local function metrics_less(a, b)
    if a.aligned ~= b.aligned then return a.aligned < b.aligned end
    if a.across ~= b.across then return a.across < b.across end
    if a.along ~= b.along then return a.along < b.along end
    if a.distance ~= b.distance then return a.distance < b.distance end
    return tostring(a.id) < tostring(b.id)
end

function M.focus(state, direction)
    if not DIRECTIONS[direction] or not state.focused_id then
        return nil
    end

    local origin = state.positions[state.focused_id]
    if not origin then return nil end

    local candidates = {}
    for id, position in pairs(state.positions) do
        if id ~= state.focused_id then
            local metrics = directional_metrics(origin, position, direction)
            if metrics then
                metrics.id = id
                table.insert(candidates, metrics)
            end
        end
    end

    table.sort(candidates, metrics_less)
    local target = candidates[1]
    if not target then return nil end

    state.focused_id = target.id
    if not state.overview then M.follow(state) end
    return target.id
end

function M.move(state, direction)
    local vector = DIRECTIONS[direction]
    local focused_id = state.focused_id
    local focused = focused_id and state.positions[focused_id]
    if not vector or not focused then return false end

    local destination_col = focused.col + vector.dc
    local destination_row = focused.row + vector.dr
    local destination_id = occupied_positions(state, focused_id)[position_key(destination_col, destination_row)]

    if destination_id then
        local other = state.positions[destination_id]
        other.col, focused.col = focused.col, other.col
        other.row, focused.row = focused.row, other.row
    else
        focused.col = destination_col
        focused.row = destination_row
    end

    M.follow(state)
    return true
end

function M.follow(state)
    local focused = state.focused_id and state.positions[state.focused_id]
    if not focused then return false end
    state.camera.col = focused.col
    state.camera.row = focused.row
    return true
end

function M.set_overview(state, enabled)
    state.overview = not not enabled
    if not state.overview then M.follow(state) end
    return state.overview
end

function M.pan(state, direction)
    local vector = DIRECTIONS[direction]
    if not vector then return false end
    state.camera.col = state.camera.col + vector.dc
    state.camera.row = state.camera.row + vector.dr
    return true
end

local function resize_step(state, map, steps, delta)
    local id = state.focused_id
    if not id or not state.positions[id] then return false end
    local current = map[id] or #steps
    local next_step = clamp(current + delta, 1, #steps)
    map[id] = next_step
    return next_step ~= current
end

function M.resize_width(state, config, delta)
    return resize_step(state, state.width_step_by_id, config.width_steps, delta)
end

function M.resize_height(state, config, delta)
    return resize_step(state, state.height_step_by_id, config.height_steps, delta)
end

function M.placements(state, area, config)
    local peek_x = clamp(config.peek_x or 0, 0, math.max(0, (area.w - 1) / 2))
    local peek_y = clamp(config.peek_y or 0, 0, math.max(0, (area.h - 1) / 2))
    local maximum_width = math.max(1, area.w - (peek_x * 2))
    local maximum_height = math.max(1, area.h - (peek_y * 2))
    local gap_x = math.max(0, config.gap_x or 0)
    local gap_y = math.max(0, config.gap_y or 0)
    local center_x = area.x + (area.w / 2)
    local center_y = area.y + (area.h / 2)
    local placements = {}
    local dimensions = {}
    local column_widths = {}
    local row_heights = {}
    local min_col, max_col = state.camera.col, state.camera.col
    local min_row, max_row = state.camera.row, state.camera.row

    for id, position in pairs(state.positions) do
        local width_step = clamp(state.width_step_by_id[id] or config.default_width_step, 1, #config.width_steps)
        local height_step = clamp(state.height_step_by_id[id] or config.default_height_step, 1, #config.height_steps)
        local width = maximum_width * config.width_steps[width_step]
        local height = maximum_height * config.height_steps[height_step]

        dimensions[id] = { w = width, h = height }
        column_widths[position.col] = math.max(column_widths[position.col] or 0, width)
        row_heights[position.row] = math.max(row_heights[position.row] or 0, height)
        min_col = math.min(min_col, position.col)
        max_col = math.max(max_col, position.col)
        min_row = math.min(min_row, position.row)
        max_row = math.max(max_row, position.row)
    end

    local default_width = maximum_width * config.width_steps[config.default_width_step]
    local default_height = maximum_height * config.height_steps[config.default_height_step]
    for col = min_col, max_col do
        column_widths[col] = column_widths[col] or default_width
    end
    for row = min_row, max_row do
        row_heights[row] = row_heights[row] or default_height
    end

    local column_centers = { [state.camera.col] = center_x }
    for col = state.camera.col + 1, max_col do
        column_centers[col] = column_centers[col - 1]
            + (column_widths[col - 1] / 2) + gap_x + (column_widths[col] / 2)
    end
    for col = state.camera.col - 1, min_col, -1 do
        column_centers[col] = column_centers[col + 1]
            - (column_widths[col + 1] / 2) - gap_x - (column_widths[col] / 2)
    end

    local row_centers = { [state.camera.row] = center_y }
    for row = state.camera.row + 1, max_row do
        row_centers[row] = row_centers[row - 1]
            + (row_heights[row - 1] / 2) + gap_y + (row_heights[row] / 2)
    end
    for row = state.camera.row - 1, min_row, -1 do
        row_centers[row] = row_centers[row + 1]
            - (row_heights[row + 1] / 2) - gap_y - (row_heights[row] / 2)
    end

    for id, position in pairs(state.positions) do
        local size = dimensions[id]

        placements[id] = {
            x = column_centers[position.col] - (size.w / 2),
            y = row_centers[position.row] - (size.h / 2),
            w = size.w,
            h = size.h,
        }
    end

    return placements
end

function M.overview_placements(state, area, config)
    local min_col, max_col, min_row, max_row
    for _, position in pairs(state.positions) do
        min_col = math.min(min_col or position.col, position.col)
        max_col = math.max(max_col or position.col, position.col)
        min_row = math.min(min_row or position.row, position.row)
        max_row = math.max(max_row or position.row, position.row)
    end

    if not min_col then return {} end

    local columns = max_col - min_col + 1
    local rows = max_row - min_row + 1
    local padding_x = math.min(area.w * 0.04, area.w / 2)
    local padding_y = math.min(area.h * 0.04, area.h / 2)
    local usable_width = area.w - (padding_x * 2)
    local usable_height = area.h - (padding_y * 2)
    local gap_x = columns > 1 and math.min(config.gap_x or 0, usable_width / (columns - 1)) or 0
    local gap_y = rows > 1 and math.min(config.gap_y or 0, usable_height / (rows - 1)) or 0
    local cell_width = math.max(1, (usable_width - (gap_x * (columns - 1))) / columns)
    local cell_height = math.max(1, (usable_height - (gap_y * (rows - 1))) / rows)
    local placements = {}

    for id, position in pairs(state.positions) do
        local width_step = clamp(state.width_step_by_id[id] or config.default_width_step, 1, #config.width_steps)
        local height_step = clamp(state.height_step_by_id[id] or config.default_height_step, 1, #config.height_steps)
        local width = cell_width * config.width_steps[width_step]
        local height = cell_height * config.height_steps[height_step]
        local cell_x = area.x + padding_x + ((position.col - min_col) * (cell_width + gap_x))
        local cell_y = area.y + padding_y + ((position.row - min_row) * (cell_height + gap_y))

        placements[id] = {
            x = cell_x + ((cell_width - width) / 2),
            y = cell_y + ((cell_height - height) / 2),
            w = width,
            h = height,
        }
    end

    return placements
end

function M.position_of(state, id)
    return state.positions[id]
end

function M.size_steps_of(state, id)
    return state.width_step_by_id[id], state.height_step_by_id[id]
end

function M.has_id(state, id)
    return contains(state.ids, id)
end

return M
