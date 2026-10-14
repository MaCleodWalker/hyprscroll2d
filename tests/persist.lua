local source = debug.getinfo(1, "S").source:sub(2)
local tests_dir = source:match("^(.*)/[^/]+$") or "tests"
local root = tests_dir:match("^(.*)/tests$") or "."

local dir = os.tmpname()
os.remove(dir)
assert(os.execute("mkdir -p '" .. dir .. "'"))
local original_getenv = os.getenv
os.getenv = function(name)
    if name == "XDG_STATE_HOME" then return dir end
    return original_getenv(name)
end

local persist = assert(loadfile(root .. "/layout/persist.lua"))()
local config = assert(loadfile(root .. "/layout/config.lua"))()

assert(next(persist.load()) == nil, "a missing file should load as empty")

local saved = {
    ["workspace:3"] = {
        camera = { col = 1, row = 0 },
        windows = {
            { class = "web", title = 'say "hi"\nnow', col = 0, row = 0, w = 2, h = 3 },
            { class = "term", title = "", col = 1, row = 0, w = 4, h = 5 },
        },
    },
    ["workspace:4"] = { windows = {} },
}
assert(persist.write(saved))
local loaded = persist.load()
assert(loaded["workspace:4"] == nil, "empty workspaces should not be stored")
local entry = loaded["workspace:3"]
assert(#entry.windows == 2 and entry.camera.col == 1, "saved grid did not round-trip")
assert(entry.windows[1].title == 'say "hi"\nnow', "titles must survive quoting")

-- A file with code or bad values never runs code and only keeps valid windows.
local file = assert(io.open(dir .. "/omalattice/layouts", "w"))
file:write([[os.execute("touch ]] .. dir .. [[/pwned") return {
    ["workspace:1"] = { windows = { { class = "a", title = "b", col = 0, row = 0, w = 1, h = 1 },
                                    { class = "a", col = 0.5, row = 0, w = 1, h = 1 } } },
    [5] = { windows = {} },
}]])
file:close()
assert(next(persist.load()) == nil, "a file that runs code must be ignored")
file = assert(io.open(dir .. "/omalattice/layouts", "w"))
file:write([[return {
    ["workspace:1"] = { windows = { { class = "a", title = "b", col = 0, row = 0, w = 1, h = 1 },
                                    { class = "a", col = 0.5, row = 0, w = 1, h = 1 } } },
    [5] = { windows = {} },
}]])
file:close()
loaded = persist.load()
assert(#loaded["workspace:1"].windows == 1 and loaded[5] == nil, "invalid entries were kept")
assert(not io.open(dir .. "/pwned", "r"), "the saved file must not run code")

-- Matching prefers the same class and title, and respects the saved sizes.
local state = {
    ids = {}, positions = {}, width_step_by_id = {}, height_step_by_id = {}, camera = { col = 0, row = 0 },
    restore = persist.begin_restore({
        camera = { col = 1, row = 0 },
        windows = {
            { class = "web", title = "docs", col = 0, row = 0, w = 1, h = 1 },
            { class = "web", title = "mail", col = 1, row = 0, w = 99, h = 2 },
        },
    }),
}
local infos = { x = { class = "web", title = "mail" }, y = { class = "web", title = "other" } }
local done = persist.claim(state, { "x", "y" }, infos, config)
assert(state.positions.x.col == 1 and state.width_step_by_id.x == #config.width_steps,
    "the window with the same title should take its place and a clamped size")
assert(state.positions.y.col == 0, "a same-class window should take the remaining place")
assert(done and not persist.restoring(state), "the restore should end once every place is taken")
persist.finish(state)
assert(state.restore == nil and state.camera.col == 1, "the camera was not restored")

os.getenv = original_getenv
os.execute("rm -rf '" .. dir .. "'")
print("ok - saved layouts")
