-- MovementController.lua
local MC = {
    gyroDampening     = 0.8,
    gyroMaxTorque     = 5e5,
    lerpAttack        = 0.08,
    lerpCruise        = 0.05,
    lerpClimb         = 0.07,
    cruiseSpeed       = 120,
    combatSpeed       = 120,
    climbSpeed        = 120,
    minSafeAltitude   = 80,
    maxAltitude       = 800,
    preferredAltitude = 350,
    leadCoeff         = 1.2,
}

-- Parabolic path state
local pathProgress = 0        -- 0 to 1 fraction of the arc completed
local pathTotalTime = 15      -- seconds for a full arc (adjust as desired)
local pathStartPos = nil      -- world position where the arc began
local pathTargetPos = nil     -- final objective position
local pathTargetAlt = 200     -- commanded altitude at the destination

local corkscrewAngle = 0

local function setHeading(body, targetPos, lerpFactor)
    local gyro = body:FindFirstChild("BodyGyro")
    if not gyro then return end
    local dir = targetPos - body.Position
    if dir.Magnitude < 0.1 then return end
    local desired = CFrame.new(body.Position, targetPos)
    if gyro:IsA("BodyGyro") then
        gyro.CFrame    = gyro.CFrame:Lerp(desired, math.clamp(lerpFactor or 0.10, 0, 1))
        gyro.D         = MC.gyroDampening
        gyro.MaxTorque = Vector3.new(MC.gyroMaxTorque, MC.gyroMaxTorque, MC.gyroMaxTorque)
    elseif gyro:IsA("AlignOrientation") then
        gyro.CFrame         = desired
        gyro.Responsiveness = math.clamp((lerpFactor or 0.10) * 200, 1, 200)
        gyro.MaxTorque      = math.huge
    end
end

local function setSpeed(body, speed)
    local vel = body:FindFirstChild("BodyVelocity")
    if not vel then return end
    local moveDir = body.CFrame.LookVector * speed
    if vel:IsA("BodyVelocity") then
        vel.Velocity = moveDir
        vel.MaxForce = Vector3.new(1e5, 1e5, 1e5)
    elseif vel:IsA("LinearVelocity") then
        vel.VectorVelocity = moveDir
        vel.MaxForce       = 1e5
    end
end

local function safeTarget(body, targetPos)
    local floor = MC.minSafeAltitude + 15
    local safeY = math.max(targetPos.Y, floor)
    if body.Position.Y < floor then
        safeY = math.max(safeY, body.Position.Y + 60)
    end
    return Vector3.new(targetPos.X, safeY, targetPos.Z)
end

local function emergencyClimbIfNeeded(body)
    if body.Position.Y >= MC.minSafeAltitude then return false end
    local pullUp = body.Position + body.CFrame.LookVector * 100 + Vector3.new(0, 200, 0)
    setHeading(body, pullUp, MC.lerpClimb * 1.3)
    setSpeed(body, MC.climbSpeed)
    return true
end

local function predictIntercept(targetPos, targetVel, myPos, mySpeed)
    local dist = (targetPos - myPos).Magnitude
    local t    = (dist / math.max(mySpeed, 1)) * MC.leadCoeff
    return targetPos + targetVel * t
end

local MOVE = {}

function MOVE.intercept(body, targetPos, targetVel, dt)
    if emergencyClimbIfNeeded(body) then return end
    targetVel = targetVel or Vector3.zero
    local intercept = predictIntercept(targetPos, targetVel, body.Position, MC.combatSpeed)
    if body.Position.Y < MC.minSafeAltitude then
        intercept = intercept + Vector3.new(0, MC.minSafeAltitude - body.Position.Y + 20, 0)
    end
    local finalAim = safeTarget(body, intercept)
    setHeading(body, finalAim, MC.lerpAttack)
    setSpeed(body, MC.combatSpeed)
end

function MOVE.cruise(body)
    local forward = body.Position + body.CFrame.LookVector * 300
    local alt = body.Position.Y
    if alt < MC.preferredAltitude - 50 then
        forward = forward + Vector3.new(0, 60, 0)
    elseif alt > MC.preferredAltitude + 50 then
        forward = forward - Vector3.new(0, 40, 0)
    end
    forward = safeTarget(body, forward)
    setHeading(body, forward, MC.lerpCruise)
    setSpeed(body, MC.cruiseSpeed)
end

-- call this each frame with dt
function MOVE.tickCorkscrew(dt)
    local degPerSec = _G._Modules.VehicleConfig.PLANE_CONFIG.corkscrewDegPerSec or 120
    corkscrewAngle = corkscrewAngle + degPerSec * dt
end

-- returns a Vector3 offset to be added to the target position
function MOVE.getCorkscrewOffset(forward)
    local radius = _G._Modules.VehicleConfig.PLANE_CONFIG.corkscrewRadius or 30
    -- compute right vector perpendicular to forward (avoid world up singularity)
    local right = forward:Cross(Vector3.new(0, 1, 0))
    if right.Magnitude < 0.001 then
        right = Vector3.new(1, 0, 0)
    else
        right = right.Unit
    end
    local up = forward:Cross(right).Unit
    local rad = math.rad(corkscrewAngle % 360)
    return (right * math.cos(rad) + up * math.sin(rad)) * radius
end

-- parabolic aim point: climbs from start to peak, then descends to target
function MOVE.getParabolicAimPoint(bodyPos, dt)
    -- If no path is defined, return nil (caller falls back to direct intercept)
    if not pathStartPos or not pathTargetPos then return nil end

    -- Advance progress
    pathProgress = pathProgress + (dt / pathTotalTime)
    if pathProgress >= 1.0 then
        pathProgress = 1.0
        -- Once arrived, clear path so we switch to normal orbit/cruise
        pathStartPos = nil
        pathTargetPos = nil
        return nil
    end

    -- Fraction along the straight line (0 → 1)
    local t = pathProgress

    -- Base point on the line from start to target (X and Z only)
    local linePoint = Vector3.new(
        pathStartPos.X + (pathTargetPos.X - pathStartPos.X) * t,
        0,   -- Y will be overridden
        pathStartPos.Z + (pathTargetPos.Z - pathStartPos.Z) * t
    )

    -- Parabolic height: start at startPos.Y, peak at maxHeight, end at targetAlt
    local startY = pathStartPos.Y
    local peakY = math.max(startY, pathTargetAlt) * 2   -- peak at double the higher of start or target
    local endY = pathTargetAlt

    -- Parabolic interpolation: y = (1-t)^2*startY + 2*(1-t)*t*peakY + t^2*endY
    local parabolicY = (1-t)*(1-t)*startY + 2*(1-t)*t*peakY + t*t*endY

    return Vector3.new(linePoint.X, parabolicY, linePoint.Z)
end

function MOVE.setParabolicTarget(startPos, targetPos, targetAlt)
    pathStartPos = startPos
    pathTargetPos = targetPos
    pathTargetAlt = targetAlt
    pathProgress = 0
end

return MOVE
