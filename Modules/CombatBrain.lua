-- CombatBrain.lua – chase-and-break combat AI for forward guns
local Players = game:GetService("Players")
local player = Players.LocalPlayer

local CombatBrain = {}
local LOCK_RANGE = 1200
local MIN_ENEMY_SPEED = 100

local currentTargetEnemy = nil
local hasLock = false
local combatMode = "chase"       -- "chase" or "break"
local breakDirection = 1         -- 1 = right, -1 = left (randomised each break)

-- Hysteresis thresholds to prevent oscillation
local CHASE_TO_BREAK_DIST = 200   -- switch to break when closer than this
local BREAK_TO_CHASE_DIST = 350   -- switch back to chase when farther than this

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
        -- No enemy in range – clear lock and revert to objective
        currentTargetEnemy = nil
        hasLock = false
        combatMode = "chase"
        return nil
    end

    -- Update lock
    if enemyHRP ~= currentTargetEnemy then
        currentTargetEnemy = enemyHRP
        hasLock = true
        combatMode = "chase"
        breakDirection = math.random(0, 1) == 0 and -1 or 1   -- randomise break side
    end

    local enemyPos = enemyHRP.Position
    local dist = (enemyPos - body.Position).Magnitude

    -- State transitions with hysteresis
    if combatMode == "chase" and dist < CHASE_TO_BREAK_DIST then
        combatMode = "break"
        breakDirection = math.random(0, 1) == 0 and -1 or 1   -- new random side each break
    elseif combatMode == "break" and dist > BREAK_TO_CHASE_DIST then
        combatMode = "chase"
    end

    -- Compute target based on mode
    local targetY = body.Position.Y   -- maintain current altitude during chase/break

    if combatMode == "chase" then
        -- Directly at enemy – MovementController.intercept handles lead/prediction
        return Vector3.new(enemyPos.X, targetY, enemyPos.Z)

    else  -- "break"
        -- Disengage behind the plane with a climb and randomised lateral offset
        local behind = body.CFrame.LookVector * -200          -- 200 studs behind
        local lateral = body.CFrame.RightVector * (150 * breakDirection)  -- left/right offset
        local climb = Vector3.new(0, 150, 0)                  -- climb
        local breakTarget = body.Position + behind + lateral + climb
        return breakTarget
    end
end

function CombatBrain.getLockedEnemy()
    if hasLock and currentTargetEnemy and currentTargetEnemy.Parent then
        return currentTargetEnemy
    end
    return nil
end

return CombatBrain
