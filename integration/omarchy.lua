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
