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
local pathProgress = 0
local pathTotalTime = 15
local pathStartPos = nil
local pathTargetPos = nil
local pathTargetAlt = 1750
local pathPeakY = nil      -- added: locked peak altitude

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

-- RL Direct Control Interface
-- Applies raw control values directly to vehicle physics
-- pitch: -1 to 1 (nose up/down)
-- yaw: -1 to 1 (nose left/right)
-- throttle: 0 or 1 (stop or full speed ~115 studs/sec)
local function setDirectControl(body, pitch, yaw, throttle)
    local gyro = body:FindFirstChild("BodyGyro")
    local vel = body:FindFirstChild("BodyVelocity")
    
    if not gyro or not vel then return end
    
    -- Apply pitch and yaw by rotating the look vector
    local currentCFrame = body.CFrame
    local lookVector = currentCFrame.LookVector
    local rightVector = currentCFrame.RightVector
    local upVector = currentCFrame.UpVector
    
    -- Calculate rotation from pitch and yaw
    local pitchAngle = pitch * 0.15  -- Max ~8.6 degrees per frame at 60 FPS
    local yawAngle = yaw * 0.15
    
    -- Rotate look vector by pitch (around right axis)
    local rotatedLook = lookVector * math.cos(pitchAngle) + upVector * math.sin(pitchAngle)
    
    -- Rotate by yaw (around up axis)
    local newUp = upVector * math.cos(yawAngle) - rightVector * math.sin(yawAngle)
    rotatedLook = rotatedLook * math.cos(yawAngle) + rightVector * math.sin(yawAngle)
    
    -- Normalize and create new CFrame
    rotatedLook = rotatedLook.Unit
    local newRight = rotatedLook:Cross(newUp).Unit
    newUp = newRight:Cross(rotatedLook).Unit
    
    local targetCFrame = CFrame.fromMatrix(body.Position, newRight, newUp, -rotatedLook)
    
    -- Apply rotation
    if gyro:IsA("BodyGyro") then
        gyro.CFrame = targetCFrame
        gyro.D = MC.gyroDampening
        gyro.MaxTorque = Vector3.new(MC.gyroMaxTorque, MC.gyroMaxTorque, MC.gyroMaxTorque)
    elseif gyro:IsA("AlignOrientation") then
        gyro.CFrame = targetCFrame
        gyro.Responsiveness = 200
        gyro.MaxTorque = math.huge
    end
    
    -- Apply throttle (binary: 0 or full speed)
    local speed = throttle > 0.5 and MC.combatSpeed or 0
    local moveDir = rotatedLook * speed
    
    if vel:IsA("BodyVelocity") then
        vel.Velocity = moveDir
        vel.MaxForce = Vector3.new(1e5, 1e5, 1e5)
    elseif vel:IsA("LinearVelocity") then
        vel.VectorVelocity = moveDir
        vel.MaxForce = 1e5
    end
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
    if not pathStartPos or not pathTargetPos then
        -- print("[Arc] No active path")  -- uncomment if you want to see when it's idle
        return nil
    end

    pathProgress = pathProgress + (dt / pathTotalTime)
    if pathProgress >= 1.0 then
        pathProgress = 1.0
        pathStartPos = nil
        pathTargetPos = nil
        pathPeakY = nil
        return nil
    end

    local t = pathProgress
    local linePoint = Vector3.new(
        pathStartPos.X + (pathTargetPos.X - pathStartPos.X) * t,
        0,
        pathStartPos.Z + (pathTargetPos.Z - pathStartPos.Z) * t
    )

    local startY = pathStartPos.Y
    local peakY = pathPeakY
    local endY = pathTargetAlt
    local parabolicY = (1-t)*(1-t)*startY + 2*(1-t)*t*peakY + t*t*endY

    return Vector3.new(linePoint.X, parabolicY, linePoint.Z)
end
function MOVE.setParabolicTarget(startPos, targetPos, targetAlt)
    pathStartPos = startPos
    pathTargetPos = targetPos
    pathTargetAlt = targetAlt
    pathProgress = 0

    -- If we're already above the target, don't climb any further.
    -- Use the current altitude as the peak so we only descend.
    if startPos.Y > targetAlt then
        pathPeakY = startPos.Y
    else
        pathPeakY = math.max(startPos.Y, targetAlt) * 3
    end
end

-- Export direct control for RL
MOVE.setDirectControl = setDirectControl

return MOVE
