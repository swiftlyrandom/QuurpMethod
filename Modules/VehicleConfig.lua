-- VehicleConfig.lua (fixed)
local BASE_URL = "https://scholar-sustained-wasp.ngrok-free.dev"

return {
    BASE_URL      = BASE_URL,
    REGISTER_URL  = BASE_URL .. "/register",
    ACK_URL       = BASE_URL .. "/ack-team",
    COMMAND_URL   = BASE_URL .. "/get-command",

    PLANE_CONFIG = {
        difficulty     = "Elite",
        vehicleName    = "Bomber",
        fovRadius      = 2000,
        engineSpeed    = 8652.419607067108,
        engineThrottle = 1.2,
        engineAltitude = 40,
        debugPrint     = false,
        offsetRangeMin = -300,
        offsetRangeMax =  300,
    },

    PLANE_NAMES = {
        ["Bomber"]         = true,
        ["Torpedo Bomber"] = true,
        ["Large Bomber"]   = true,
    }
}
