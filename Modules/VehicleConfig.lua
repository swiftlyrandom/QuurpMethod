-- VehicleConfig.lua
return {
    BASE_URL      = "https://scholar-sustained-wasp.ngrok-free.dev",
    REGISTER_URL  = function() return VehicleConfig.BASE_URL .. "/register" end,
    ACK_URL       = function() return VehicleConfig.BASE_URL .. "/ack-team" end,
    COMMAND_URL   = function() return VehicleConfig.BASE_URL .. "/get-command" end,

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
