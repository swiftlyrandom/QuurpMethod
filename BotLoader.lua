-- ============================================================
--  BootLoader.lua  (QuurpMethod – Pilot Only)
--  Fetches modules from GitHub, retries on failure, boots pilot.
-- ============================================================

-- ---------- CONFIG ----------
local GITHUB_USER   = "swiftlyrandom"
local GITHUB_REPO   = "QuurpMethod"
local GITHUB_BRANCH = "main"
local MODULES_PATH  = "Modules"

-- Modules needed for the pilot (no GunnerController, no dynamic checks)
local MODULE_NAMES = {
    "VehicleConfig",
    "PredictionUtils",
    "MovementController",
    "WorldScanner",
    "AutoSeater",
    "ObjectiveResolver",
    "NetworkController",
    "RPGWeapon",
    "CombatBrain",
    "GunSystem",
    "MainController",
}

-- ---------- LOADER ----------
local RAW_BASE = string.format(
    "https://raw.githubusercontent.com/%s/%s/refs/heads/%s/%s/",
    GITHUB_USER, GITHUB_REPO, GITHUB_BRANCH, MODULES_PATH
)

_G._Modules = _G._Modules or {}

local function fetchModule(name, retries)
    retries = retries or 3
    local url = RAW_BASE .. name .. ".lua"
    print("[Boot] Fetching:", name)

    for attempt = 1, retries do
        local ok, result = pcall(function()
            return request({ Url = url, Method = "GET" })
        end)

        if ok and result and result.StatusCode == 200 then
            local fn, err = loadstring(result.Body, name)
            if not fn then
                error("[Boot] Compile error in " .. name .. ": " .. tostring(err))
            end

            local mod = fn()
            if type(mod) ~= "table" then
                error("[Boot] " .. name .. " did not return a table.")
            end

            _G._Modules[name] = mod
            print("[Boot] Loaded:", name)
            return
        else
            if attempt < retries then
                warn("[Boot] Attempt " .. attempt .. " failed for " .. name .. ", retrying...")
                task.wait(1)
            else
                error("[Boot] Failed to load " .. name .. " after " .. retries .. " attempts.")
            end
        end
    end
end

-- ---------- MAIN ----------
print("[Boot] Loading pilot modules...")

for _, name in ipairs(MODULE_NAMES) do
    local success, err = pcall(fetchModule, name, 3)
    if not success then
        warn("[Boot] FATAL: " .. tostring(err))
        return
    end
end

print("[Boot] All modules loaded. Starting pilot...")
_G._Modules.MainController.start()
