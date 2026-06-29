-- ============================================================
--  BootLoader.lua  (QuurpMethod Vehicle Controller)
--  Place in your executor. Fetches all modules from GitHub,
--  loads them in order, then boots the main controller.
-- ============================================================

-- ===== CONFIG =====
local GITHUB_USER   = "swiftlyrandom"
local GITHUB_REPO   = "QuurpMethod"
local GITHUB_BRANCH = "main"
local MODULES_PATH  = "Modules"          -- folder containing all .lua files

-- Module file names (without .lua) – load order matters!
local LOAD_ORDER = {
    "VehicleConfig",
    "MovementController",
    "WorldScanner",
    "AutoSeater",
    "ObjectiveResolver",
    "NetworkController",
    "RPGWeapon",
    "MainController",
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

    -- Compile & run in the global environment
    local fn, err = loadstring(result.Body, name)
    if not fn then
        error("[BootLoader] Compile error in " .. name .. ": " .. tostring(err))
    end

    local mod = fn()   -- each module must return a table
    if type(mod) ~= "table" then
        error("[BootLoader] " .. name .. " did not return a table.")
    end

    _G._Modules[name] = mod
    print("[BootLoader] Loaded:", name)
end

-- ===== MAIN =====
print("[BootLoader] Starting module load...")

for _, name in ipairs(LOAD_ORDER) do
    local success, err = pcall(fetchModule, name)
    if not success then
        warn("[BootLoader] Failed to load " .. name .. ": " .. tostring(err))
        return
    end
end

print("[BootLoader] All modules loaded. Booting MainController...")

-- MainController's boot is triggered automatically (its file runs at once)
-- or you can call a boot function if you prefer.
-- The MainController.lua already contains a boot() call at the bottom,
-- so it will run on load.

print("[BootLoader] BootLoader finished.")
