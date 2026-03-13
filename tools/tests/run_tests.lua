local function dirname(path)
    if not path or path == "" then return "." end
    local dir = path:match("^(.*)[/\\][^/\\]+$")
    return dir or "."
end

local function join_path(a, b)
    if not a or a == "" then return b end
    if not b or b == "" then return a end
    local sep = "/"
    if a:sub(-1) == "/" or a:sub(-1) == "\\" then
        return a .. b
    end
    return a .. sep .. b
end

local function parse_args(argv)
    local opts = {}
    local i = 1
    while i <= #argv do
        local v = argv[i]
        if v == "--mod-root" then
            opts.mod_root = argv[i + 1]
            i = i + 2
        else
            i = i + 1
        end
    end
    return opts
end

local function fail(msg)
    error(msg or "test failed", 2)
end

local function assert_true(value, msg)
    if not value then
        fail(msg or ("expected true, got " .. tostring(value)))
    end
end

local function assert_equal(actual, expected, msg)
    if actual ~= expected then
        local prefix = msg and (msg .. " | ") or ""
        fail(prefix .. "expected=" .. tostring(expected) .. ", actual=" .. tostring(actual))
    end
end

local function assert_type(value, expected, msg)
    local actual = type(value)
    if actual ~= expected then
        local prefix = msg and (msg .. " | ") or ""
        fail(prefix .. "expected type=" .. tostring(expected) .. ", actual=" .. tostring(actual))
    end
end

local function build_env()
    local env = {}
    setmetatable(env, {__index = _G})
    env.getText = env.getText or function(key) return key end
    env.require = env.require or function()
        return true
    end
    env.ZombRand = env.ZombRand or function(minValue, maxValue)
        if maxValue == nil then
            return 0
        end
        return minValue or 0
    end
    local function new_event()
        return {
            Add = function()
            end,
            Remove = function()
            end
        }
    end
    env.Events = env.Events or setmetatable({
        OnClientCommand = new_event(),
        OnServerStarted = new_event(),
        EveryHours = new_event(),
        OnInitGlobalModData = new_event()
    }, {
        __index = function(t, key)
            local event = new_event()
            rawset(t, key, event)
            return event
        end
    })
    return env
end

local function load_module(path, env)
    env = env or build_env()
    local chunk, loadErr = loadfile(path, "t", env)
    if not chunk then
        return nil, nil, "loadfile failed for " .. tostring(path) .. ": " .. tostring(loadErr)
    end

    local ok, runErr = pcall(chunk)
    if not ok then
        return nil, nil, "runtime failed for " .. tostring(path) .. ": " .. tostring(runErr)
    end

    if type(env.BurdJournals) ~= "table" then
        return nil, nil, "BurdJournals table missing after load for " .. tostring(path)
    end

    return env.BurdJournals, env, nil
end

local function load_shared_module(path)
    return load_module(path, build_env())
end

local function require_shared_module(path)
    local mod, env, err = load_shared_module(path)
    if err then
        fail(err)
    end
    return mod, env
end

local function require_server_module(shared_path, server_path)
    local _, env = require_shared_module(shared_path)
    env.require = function(name)
        if name == "BurdJournals_Shared" then
            return env.BurdJournals
        end
        return true
    end

    local mod, serverEnv, err = load_module(server_path, env)
    if err then
        fail(err)
    end
    return mod, serverEnv
end

local function require_client_module(shared_path, client_path)
    local _, env = require_shared_module(shared_path)
    env.require = function(name)
        if name == "BurdJournals_Shared" then
            return env.BurdJournals
        end
        return true
    end

    local mod, clientEnv, err = load_module(client_path, env)
    if err then
        fail(err)
    end
    return mod, clientEnv
end

local script_dir = dirname(arg and arg[0] or "")
local options = parse_args(arg or {})
local default_mod_root = join_path(join_path(script_dir, "../.."), "Contents/mods/BurdSurvivalJournals")
local mod_root = options.mod_root or default_mod_root

local tests = {}
local function test(name, fn)
    tests[#tests + 1] = {name = name, fn = fn}
end

_G.BSJ_TEST = {
    test = test,
    fail = fail,
    assert_true = assert_true,
    assert_equal = assert_equal,
    assert_type = assert_type,
    join_path = join_path,
    mod_root = mod_root,
    load_module = load_module,
    load_shared_module = load_shared_module,
    require_shared_module = require_shared_module,
    require_server_module = require_server_module,
    require_client_module = require_client_module
}

local function load_test_file(path)
    local ok, loadErr = pcall(dofile, path)
    if not ok then
        io.stderr:write("Failed loading test file " .. tostring(path) .. ": " .. tostring(loadErr) .. "\n")
        os.exit(1)
    end
end

load_test_file(join_path(script_dir, "starter_tests.lua"))
load_test_file(join_path(script_dir, "migration_smoke_tests.lua"))

local passed = 0
local failed = 0

print("========================================")
print("BSJ Lua Test Runner")
print("Mod root: " .. tostring(mod_root))
print("Tests registered: " .. tostring(#tests))
print("========================================")

for i, entry in ipairs(tests) do
    local testOk, testErr = pcall(entry.fn)
    if testOk then
        passed = passed + 1
        print(string.format("[PASS] %02d - %s", i, entry.name))
    else
        failed = failed + 1
        print(string.format("[FAIL] %02d - %s", i, entry.name))
        print("       " .. tostring(testErr))
    end
end

print("========================================")
print(string.format("Result: %d passed, %d failed", passed, failed))
print("========================================")

if failed > 0 then
    os.exit(1)
end

os.exit(0)
