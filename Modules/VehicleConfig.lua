-- VehicleConfig.lua (fixed)
local BASE_URL = "https://scholar-sustained-wasp.ngrok-free.dev"

return {
    BASE_URL       = BASE_URL,
    REGISTER_URL   = BASE_URL .. "/register",
    ACK_URL        = BASE_URL .. "/ack-team",
    COMMAND_URL    = BASE_URL .. "/get-command",

    PLANE_CONFIG = {
        difficulty     = "Elite",
        vehicleName    = "Bomber",
        fovRadius      = 2000,
        engineSpeed    = 8652.419607067108,
        engineThrottle = 1.2,
        engineAltitude = 40,
        debugPrint     = false,
        offsetRangeMin = -300,
        offsetRangeMax = 300,
        corkscrewRadius     = 30,   -- studs
        corkscrewDegPerSec  = 120,  -- degrees per second of rotation
    },

    PLANE_NAMES = {
        ["Bomber"]         = true,
        ["Torpedo Bomber"] = true,
        ["Large Bomber"]   = true,
    },
    
    RPG_CONFIG = {
        enabled        = true,
        bulletSpeed    = 225,
        fireCooldown   = 0.2,
        maxRange       = 1800,
        minTargetSpeed = 100,
    },

    GUNNER_CONFIG = {
        bulletSpeed   = 600,
        shootDuration = 2,
        shootBreak    = 1,
        ownerName     = "B3X0Z",        -- the pilot's username
        bomberName    = "Large Bomber",
        maxRange      = 1400,
        setupDelay    = 8,
        enemySpeed    = 100,
    }
}
