-- CombatBrain.lua – simple combat AI: lock onto nearest enemy within range
local Players = game:GetService("Players")
local player = Players.LocalPlayer

local CombatBrain = {}
local LOCK_RANGE = 1200
local ORBIT_RADIUS = 250
local ORBIT_SPEED = 0.5   -- rad/s around enemy

local orbitAngle = 0
local currentTargetEnemy = nil   -- the HRP of the enemy we're orbiting

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

-- called every heartbeat from MainController
function CombatBrain.update(body, dt)
    -- update orbit angle continuously
    orbitAngle = orbitAngle + ORBIT_SPEED * dt

    -- find a new enemy to lock onto
    local enemyHRP = findClosestEnemy(body.Position)
    if enemyHRP then
        currentTargetEnemy = enemyHRP
    end

    -- if we have a locked enemy, compute orbit target around it
    if currentTargetEnemy then
        local enemyPos = currentTargetEnemy.Position
        -- simple horizontal circle at the plane's own altitude to maintain height
        local targetY = body.Position.Y   -- maintain current altitude
        local offset = Vector3.new(
            math.cos(orbitAngle) * ORBIT_RADIUS,
            0,
            math.sin(orbitAngle) * ORBIT_RADIUS
        )
        return Vector3.new(enemyPos.X + offset.X, targetY, enemyPos.Z + offset.Z)
    end

    return nil   -- no combat target, fall back to objective
end

return CombatBrain
