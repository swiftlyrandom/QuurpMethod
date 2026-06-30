-- ============================================================
--  BootLoader.lua  (QuurpMethod Vehicle Controller)
--  Place in your executor. Fetches all modules from GitHub,
--  detects role (pilot / gunner) from MasterControl, then boots
--  the appropriate controller.
-- ============================================================

-- ===== CONFIG =====
local GITHUB_USER   = "swiftlyrandom"
local GITHUB_REPO   = "QuurpMethod"
local GITHUB_BRANCH = "main"
local MODULES_PATH  = "Modules"

-- Modules that BOTH pilot and gunner need
local SHARED_MODULES = {
    "VehicleConfig",
    "PredictionUtils",
    "MovementController",
    "WorldScanner",
    "AutoSeater",
    "ObjectiveResolver",
    "NetworkController",
    "RPGWeapon",
    "GunnerController",
}

-- ===== GITHUB URL =====
local RAW_BASE = string.format(
    "https://raw.githubusercontent.com/%s/%s/refs/heads/%s/%s/",
    GITHUB_USER, GITHUB_REPO, GITHUB_BRANCH, MODULES_PATH
)

-- ===== SHARED MODULE TABLE =====
_G._Modules = _G._Modules or {}

-- ===== FETCH & LOAD =====
local function fetchModule(name)
    local url = RAW_BASE .. name .. ".lua"
    print("[BootLoader] Fetching:", name)

    local ok, result = pcall(function()
        return request({ Url = url, Method = "GET" })
    end)
    if not ok then
        error("[BootLoader] request() failed for: " .. url)
    end

    if result.StatusCode ~= 200 then
        error(string.format("[BootLoader] HTTP %d for: %s", result.StatusCode, url))
    end

    local fn, err = loadstring(result.Body, name)
    if not fn then
        error("[BootLoader] Compile error in " .. name .. ": " .. tostring(err))
    end

    local mod = fn()
    if type(mod) ~= "table" then
        error("[BootLoader] " .. name .. " did not return a table.")
    end

    _G._Modules[name] = mod
    print("[BootLoader] Loaded:", name)
end

-- ===== MAIN =====
print("[BootLoader] Starting module load...")

for _, name in ipairs(SHARED_MODULES) do
    local success, err = pcall(fetchModule, name)
    if not success then
        warn("[BootLoader] Failed to load " .. name .. ": " .. tostring(err))
        return
    end
end

-- ===== ROLE DETECTION =====
local player = game:GetService("Players").LocalPlayer
local HttpService = game:GetService("HttpService")
local Network = _G._Modules.NetworkController

local botId = player.Name
local teamName = player.Team and player.Team.Name or "Unknown"

-- Register with MasterControl (so we appear in the instance list)
Network.register(botId, teamName)

-- Give the server a moment, then check our own command
task.wait(3)

local function getRole()
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
            return "gunner"
        end
    end
    return "pilot"
end

local role = getRole()
print("[BootLoader] Detected role:", role)

if role == "gunner" then
    -- Run gunner controller only – no flight code
    print("[BootLoader] Starting GunnerController...")
    _G._Modules.GunnerController.start()
    return  -- stop here, do NOT load MainController
end

-- ===== PILOT PATH =====
print("[BootLoader] Loading MainController for pilot...")
local success, err = pcall(fetchModule, "MainController")
if not success then
    warn("[BootLoader] Failed to load MainController: " .. tostring(err))
    return
end

-- MainController.lua already calls boot() at the bottom
print("[BootLoader] Pilot booted.")
