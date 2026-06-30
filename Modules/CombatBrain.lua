-- CombatBrain.lua – deterministic orbit around nearest enemy within range
local Players = game:GetService("Players")
local player = Players.LocalPlayer

local CombatBrain = {}
local LOCK_RANGE = 1200
local ORBIT_RADIUS = 250
local ORBIT_SPEED = 0.5   -- rad/s around enemy

local currentTargetEnemy = nil   -- HRP of locked enemy
local orbitAngle = 0
local hasLock = false

-- find nearest enemy HRP within LOCK_RANGE
local function findClosestEnemy(bodyPos)
    local closest, closestDist = nil, LOCK_RANGE
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr == player then continue end
        if plr.Team and player.Team and plr.Team == player.Team then continue end
        local char = plr.Character
        local hrp = char and char:FindFirstChild("HumanoidRootPart")
        if hrp then
            local dist = (hrp.Position - bodyPos).Magnitude
            if dist < closestDist then
                closestDist = dist
                closest = hrp
            end
        end
    end
    return closest
end

-- Called every heartbeat from MainController
function CombatBrain.update(body, dt)
    local enemyHRP = findClosestEnemy(body.Position)

    if enemyHRP then
        if enemyHRP ~= currentTargetEnemy then
            -- new enemy – set orbit starting angle based on current relative position
            currentTargetEnemy = enemyHRP
            local toEnemy = enemyHRP.Position - body.Position
            orbitAngle = math.atan2(toEnemy.Z, toEnemy.X)  -- start from approach direction
            hasLock = true
        else
            -- same enemy – advance orbit
            orbitAngle = orbitAngle + ORBIT_SPEED * dt
        end
    else
        -- no enemy in range → lose lock, revert to objective
        currentTargetEnemy = nil
        hasLock = false
    end

    if hasLock and currentTargetEnemy then
        local enemyPos = currentTargetEnemy.Position
        local targetY = body.Position.Y   -- maintain current altitude
        local offset = Vector3.new(
            math.cos(orbitAngle) * ORBIT_RADIUS,
            0,
            math.sin(orbitAngle) * ORBIT_RADIUS
        )
        return Vector3.new(enemyPos.X + offset.X, targetY, enemyPos.Z + offset.Z)
    end

    return nil   -- fall back to objective
end

return CombatBrain
