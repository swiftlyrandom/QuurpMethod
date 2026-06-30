-- ============================================================
--  BootLoader.lua  (QuurpMethod Vehicle Controller)
--  Dynamic role switching – pilot / gunner, controlled from MasterControl.
-- ============================================================

local GITHUB_USER   = "swiftlyrandom"
local GITHUB_REPO   = "QuurpMethod"
local GITHUB_BRANCH = "main"
local MODULES_PATH  = "Modules"

-- All modules – both roles will be loaded
local ALL_MODULES = {
    "VehicleConfig",
    "PredictionUtils",
    "MovementController",
    "WorldScanner",
    "AutoSeater",
    "ObjectiveResolver",
    "NetworkController",
    "RPGWeapon",
    "GunnerController",
    "MainController",
}

local RAW_BASE = string.format(
    "https://raw.githubusercontent.com/%s/%s/refs/heads/%s/%s/",
    GITHUB_USER, GITHUB_REPO, GITHUB_BRANCH, MODULES_PATH
)

_G._Modules = _G._Modules or {}

local function fetchModule(name)
    local url = RAW_BASE .. name .. ".lua"
    print("[BootLoader] Fetching:", name)

    local ok, result = pcall(function()
        return request({ Url = url, Method = "GET" })
    end)
    if not ok then error("[BootLoader] request() failed for: " .. url) end
    if result.StatusCode ~= 200 then
        error(string.format("[BootLoader] HTTP %d for: %s", result.StatusCode, url))
    end

    local fn, err = loadstring(result.Body, name)
    if not fn then error("[BootLoader] Compile error in " .. name .. ": " .. tostring(err)) end
    local mod = fn()
    if type(mod) ~= "table" then error("[BootLoader] " .. name .. " did not return a table.") end
    _G._Modules[name] = mod
    print("[BootLoader] Loaded:", name)
end

-- Load all modules upfront
print("[BootLoader] Loading all modules...")
for _, name in ipairs(ALL_MODULES) do
    local success, err = pcall(fetchModule, name)
    if not success then
        warn("[BootLoader] Failed to load " .. name .. ": " .. tostring(err))
        return
    end
end

-- ===== Dynamic role monitor =====
local player = game:GetService("Players").LocalPlayer
local HttpService = game:GetService("HttpService")
local Network = _G._Modules.NetworkController

local botId = player.Name
local currentRole = nil   -- "pilot" or "gunner"
local activeModule = nil

local function fetchRole()
    local url = string.format("%s/get-command?id=%s",
        _G._Modules.VehicleConfig.COMMAND_URL,
        HttpService:UrlEncode(botId))
    local ok, resp = pcall(function()
        return request({ Url = url, Method = "GET",
                         Headers = { ["ngrok-skip-browser-warning"] = "true" } })
    end)
    if ok and resp and resp.StatusCode == 200 then
        local data = HttpService:JSONDecode(resp.Body)
        if data and data.pair_with then
            return "gunner", data.pair_with
        end
    end
    return "pilot", nil
end

local function switchTo(newRole, pairWith)
    if newRole == currentRole then return end

    -- Stop previous module
    if activeModule and activeModule.stop then
        activeModule.stop()
        activeModule = nil
    end

    currentRole = newRole

    if newRole == "gunner" then
        print("[BootLoader] Switching to GUNNER...")
        local gunner = _G._Modules.GunnerController
        gunner.start()
        activeModule = gunner
    else
        print("[BootLoader] Switching to PILOT...")
        local pilot = _G._Modules.MainController
        pilot.start()
        activeModule = pilot
    end
end

-- Initial registration (so we appear in MasterControl)
local teamName = player.Team and player.Team.Name or "Unknown"
Network.register(botId, teamName)

-- Start with whatever the server says (default pilot)
local initialRole, initialPair = fetchRole()
switchTo(initialRole, initialPair)

-- Monitor for changes every 5 seconds
task.spawn(function()
    while true do
        task.wait(5)
        local newRole, pairWith = fetchRole()
        if newRole ~= currentRole then
            print("[BootLoader] Role change detected:", currentRole, "→", newRole)
            switchTo(newRole, pairWith)
        end
    end
end)

print("[BootLoader] Dynamic role switching active.")
