-- ObjectiveResolver.lua
local ORBIT_RADIUS = 500
local ORBIT_SPEED  = 0.15
local SINE_AMP    = 50
local SINE_PERIOD = 12
local DIVE_TARGET_ALT = 100

local module = {}
module.objectives = {}
module.currentTarget = nil
module.currentObjLabel = nil
module.currentAlt = 200
module.mode = "cruise"

local orbitAngle = math.random() * math.pi * 2
local sineTimer  = 0

function module.setObjectives(objs)
    module.objectives = objs
end

function module.resolveObjective(label, altitude)
    local base = module.objectives[label]
    if not base then return nil end
    module.currentObjLabel = label
    module.currentAlt = altitude
    module.currentTarget = Vector3.new(base.X, altitude, base.Z)
    return module.currentTarget
end

function module.calcOrbitTarget(base, dt)
    orbitAngle = orbitAngle + ORBIT_SPEED * dt
    local ox = math.cos(orbitAngle) * ORBIT_RADIUS
    local oz = math.sin(orbitAngle) * ORBIT_RADIUS
    return Vector3.new(base.X + ox, base.Y, base.Z + oz)
end

function module.calcSineTarget(vehiclePart, dt)
    sineTimer = sineTimer + dt
    local wave    = math.sin((sineTimer / SINE_PERIOD) * math.pi * 2) * SINE_AMP
    local forward = vehiclePart.CFrame.LookVector * 300
    return Vector3.new(
        vehiclePart.Position.X + forward.X,
        module.currentAlt + wave,
        vehiclePart.Position.Z + forward.Z
    )
end

function module.calcClimbTarget(vehiclePart)
    local forward = vehiclePart.CFrame.LookVector * 200
    return Vector3.new(
        vehiclePart.Position.X + forward.X,
        module.currentAlt + 300,
        vehiclePart.Position.Z + forward.Z
    )
end

function module.calcDiveTarget(vehiclePart)
    local forward = vehiclePart.CFrame.LookVector * 300
    return Vector3.new(
        vehiclePart.Position.X + forward.X,
        DIVE_TARGET_ALT,
        vehiclePart.Position.Z + forward.Z
    )
end

-- Returns the appropriate target based on current mode and state
function module.getTarget(vehiclePart, dt)
    if module.mode == "objective" then
        if module.currentTarget then
            return module.calcOrbitTarget(module.currentTarget, dt)
        else
            return module.calcSineTarget(vehiclePart, dt)
        end
    elseif module.mode == "cruise" then
        return module.calcSineTarget(vehiclePart, dt)
    elseif module.mode == "climb" then
        return module.calcClimbTarget(vehiclePart)
    elseif module.mode == "dive" then
        return module.calcDiveTarget(vehiclePart)
    end
end

return module
