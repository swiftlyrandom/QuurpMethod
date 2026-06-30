-- CombatBrain.lua – smoothed chase-and-break with timed phases
local Players = game:GetService("Players")
local player = Players.LocalPlayer

local CombatBrain = {}
local LOCK_RANGE = 1200
local MIN_ENEMY_SPEED = 100

local currentTargetEnemy = nil
local hasLock = false
local combatMode = "chase"
local breakDirection = 1

-- Timers for chase / break phases (seconds)
local CHASE_DURATION = 5.0
local BREAK_DURATION = 2.0
local phaseTimer = 0

-- Velocity smoothing (exponential moving average)
local smoothedVelocity = Vector3.zero
local VEL_SMOOTH_FACTOR = 0.3   -- lower = smoother but more lag

-- Distance thresholds only used to switch break side or force break if too close
local MIN_DIST = 150   -- if closer than this, force break immediately

local function findClosestEnemy(bodyPos)
    local closest, closestDist = nil, LOCK_RANGE
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr == player then continue end
        if plr.Team and player.Team and plr.Team == player.Team then continue end
        local char = plr.Character
        local hrp = char and char:FindFirstChild("HumanoidRootPart")
        if hrp then
            local speed = hrp.AssemblyLinearVelocity.Magnitude
            if speed < MIN_ENEMY_SPEED then continue end
            local dist = (hrp.Position - bodyPos).Magnitude
            if dist < closestDist then
                closestDist = dist
                closest = hrp
            end
        end
    end
    return closest
end

function CombatBrain.update(body, dt)
    local enemyHRP = findClosestEnemy(body.Position)

    if not enemyHRP then
        currentTargetEnemy = nil
        hasLock = false
        combatMode = "chase"
        phaseTimer = 0
        smoothedVelocity = Vector3.zero
        return nil, nil
    end

    -- Lock acquisition
    if enemyHRP ~= currentTargetEnemy then
        currentTargetEnemy = enemyHRP
        hasLock = true
        combatMode = "chase"
        phaseTimer = 0
        breakDirection = math.random(0, 1) == 0 and -1 or 1
        smoothedVelocity = enemyHRP.AssemblyLinearVelocity   -- initialise with current
    end

    -- Smooth the enemy velocity
    local rawVel = enemyHRP.AssemblyLinearVelocity
    smoothedVelocity = smoothedVelocity:Lerp(rawVel, VEL_SMOOTH_FACTOR)

    local enemyPos = enemyHRP.Position
    local dist = (enemyPos - body.Position).Magnitude

    -- Phase timer
    phaseTimer = phaseTimer + dt

    -- Force break if too close
    if combatMode == "chase" and dist < MIN_DIST then
        combatMode = "break"
        phaseTimer = 0
        breakDirection = math.random(0, 1) == 0 and -1 or 1
    end

    -- Timed phase transitions
    if combatMode == "chase" and phaseTimer >= CHASE_DURATION then
        combatMode = "break"
        phaseTimer = 0
        breakDirection = math.random(0, 1) == 0 and -1 or 1
    elseif combatMode == "break" and phaseTimer >= BREAK_DURATION then
        combatMode = "chase"
        phaseTimer = 0
    end

    -- Compute target
    local targetY = body.Position.Y

    if combatMode == "chase" then
        -- Use enemy position with smoothed velocity for lead
        return Vector3.new(enemyPos.X, targetY, enemyPos.Z), smoothedVelocity

    else  -- "break"
        local awayFromEnemy = (body.Position - enemyPos).Unit
        if awayFromEnemy.Magnitude < 0.1 then
            awayFromEnemy = Vector3.new(1, 0, 0)
        end
        local lateral = Vector3.new(-awayFromEnemy.Z, 0, awayFromEnemy.X).Unit * (150 * breakDirection)
        local climb = Vector3.new(0, 150, 0)
        local breakTarget = body.Position + awayFromEnemy * 200 + lateral + climb
        return breakTarget, nil
    end
end

function CombatBrain.getLockedEnemy()
    if hasLock and currentTargetEnemy and currentTargetEnemy.Parent then
        return currentTargetEnemy
    end
    return nil
end

return CombatBrain
