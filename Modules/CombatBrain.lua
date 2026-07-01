-- CombatBrain.lua – high‑orbit with evasive climb
local Players = game:GetService("Players")
local player = Players.LocalPlayer

local CombatBrain = {}
local LOCK_RANGE = 1400
local MIN_ENEMY_SPEED = 100
local ORBIT_RADIUS = 250
local ORBIT_ALTITUDE_OFFSET = 800   -- studs above the enemy
local ORBIT_SPEED = 0.15            -- rad/s

-- Weave during climb
local WEAVE_AMPLITUDE = 80          -- studs left/right
local WEAVE_INTERVAL  = 1.5         -- seconds between direction flips

local currentTargetEnemy = nil
local hasLock = false
local orbitAngle = 0
local isClimbing = false            -- true when we haven't reached orbit height yet
local weaveTimer = 0
local weaveDir = 1                  -- 1 = right, -1 = left

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
        isClimbing = false
        return nil, nil
    end

    -- Lock onto new enemy → start climbing to orbit height
    if enemyHRP ~= currentTargetEnemy then
        currentTargetEnemy = enemyHRP
        hasLock = true
        orbitAngle = math.random() * math.pi * 2
        isClimbing = true
        weaveTimer = 0
        weaveDir = (math.random(0, 1) == 0) and -1 or 1
    end

    local enemyPos = enemyHRP.Position
    local myPos = body.Position
    local targetOrbitY = enemyPos.Y + ORBIT_ALTITUDE_OFFSET

    -- Decide if we've reached orbit height yet
    if isClimbing and math.abs(myPos.Y - targetOrbitY) < 60 then
        isClimbing = false   -- switch to smooth orbit
    end

    if isClimbing then
        -- lateral weave timer
        weaveTimer = weaveTimer + dt
        if weaveTimer >= WEAVE_INTERVAL then
            weaveTimer = 0
            weaveDir = (math.random(0, 1) == 0) and -1 or 1
        end

        -- direction toward the point above enemy
        local toTarget = (Vector3.new(enemyPos.X, targetOrbitY, enemyPos.Z) - myPos).Unit
        -- perpendicular horizontal direction
        local right = Vector3.new(-toTarget.Z, 0, toTarget.X).Unit
        local climbTarget = Vector3.new(enemyPos.X, targetOrbitY, enemyPos.Z)
                           + right * weaveDir * WEAVE_AMPLITUDE

        return climbTarget, nil

    else
        -- Orbit phase (smooth circle)
        orbitAngle = orbitAngle + ORBIT_SPEED * dt

        local ox = math.cos(orbitAngle) * ORBIT_RADIUS
        local oz = math.sin(orbitAngle) * ORBIT_RADIUS
        local targetPos = Vector3.new(enemyPos.X + ox, targetOrbitY, enemyPos.Z + oz)

        return targetPos, nil
    end
end

function CombatBrain.getLockedEnemy()
    if hasLock and currentTargetEnemy and currentTargetEnemy.Parent then
        return currentTargetEnemy
    end
    return nil
end

return CombatBrain
