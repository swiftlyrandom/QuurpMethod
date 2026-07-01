-- CombatBrain.lua – simple high‑orbit for pilot AI (defense by backgunner)
local Players = game:GetService("Players")
local player = Players.LocalPlayer

local CombatBrain = {}
local LOCK_RANGE = 1200
local MIN_ENEMY_SPEED = 100
local ORBIT_RADIUS = 250
local ORBIT_ALTITUDE_OFFSET = 1200   -- studs above the enemy
local ORBIT_SPEED = 0.4             -- rad/s

local currentTargetEnemy = nil
local hasLock = false
local orbitAngle = 0

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
        return nil, nil
    end

    -- Lock onto new enemy
    if enemyHRP ~= currentTargetEnemy then
        currentTargetEnemy = enemyHRP
        hasLock = true
        -- Start orbit from a random angle so multiple bombers spread out
        orbitAngle = math.random() * math.pi * 2
    end

    -- Advance orbit
    orbitAngle = orbitAngle + ORBIT_SPEED * dt

    local enemyPos = enemyHRP.Position
    local orbitY = enemyPos.Y + ORBIT_ALTITUDE_OFFSET   -- stay safely above

    local ox = math.cos(orbitAngle) * ORBIT_RADIUS
    local oz = math.sin(orbitAngle) * ORBIT_RADIUS
    local targetPos = Vector3.new(enemyPos.X + ox, orbitY, enemyPos.Z + oz)

    -- No velocity needed for a static orbit point
    return targetPos, nil
end

function CombatBrain.getLockedEnemy()
    if hasLock and currentTargetEnemy and currentTargetEnemy.Parent then
        return currentTargetEnemy
    end
    return nil
end

return CombatBrain
