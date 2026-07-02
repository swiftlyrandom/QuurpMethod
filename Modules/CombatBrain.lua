-- CombatBrain.lua – two‑phase climb + high‑orbit
local Players = game:GetService("Players")
local player = Players.LocalPlayer

local CombatBrain = {}
local LOCK_RANGE = 1200
local MIN_ENEMY_SPEED = 100
local ORBIT_RADIUS = 250
local ORBIT_ALTITUDE_OFFSET = 800   -- studs above the enemy
local ORBIT_SPEED = 0.15            -- rad/s

-- Retreat (climb) weaving
local WEAVE_AMPLITUDE = 80          -- studs left/right
local WEAVE_INTERVAL  = 1.5         -- seconds between direction flips
local RETREAT_ALTITUDE_FRACTION = 0.90   -- reach 75% of target height before orbiting

local currentTargetEnemy = nil
local hasLock = false
local orbitAngle = 0
local phase = "retreat"             -- "retreat" or "orbit"
local weaveTimer = 0
local weaveDir = 1                  -- 1 or -1

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
        phase = "retreat"
        return nil, nil
    end

    -- Lock onto new enemy → start retreat
    if enemyHRP ~= currentTargetEnemy then
        currentTargetEnemy = enemyHRP
        hasLock = true
        orbitAngle = math.random() * math.pi * 2
        phase = "retreat"
        weaveTimer = 0
        weaveDir = (math.random(0, 1) == 0) and -1 or 1
    end

    local enemyPos = enemyHRP.Position
    local myPos = body.Position
    local targetOrbitY = enemyPos.Y + ORBIT_ALTITUDE_OFFSET
    local heightFraction = (myPos.Y - enemyPos.Y) / ORBIT_ALTITUDE_OFFSET   -- 0 to 1

    -- Phase transition: switch to orbit when we reach 75% of target height
    if phase == "retreat" and heightFraction >= RETREAT_ALTITUDE_FRACTION then
        phase = "orbit"
        orbitAngle = math.random() * math.pi * 2   -- random start angle for orbit
    end

    if phase == "retreat" then
        -- Retreat: fly away from enemy while climbing, with lateral weave
        weaveTimer = weaveTimer + dt
        if weaveTimer >= WEAVE_INTERVAL then
            weaveTimer = 0
            weaveDir = (math.random(0, 1) == 0) and -1 or 1
        end

        -- Base direction: directly away from the enemy
        local awayDir = (myPos - enemyPos).Unit
        if awayDir.Magnitude < 0.1 then
            awayDir = body.CFrame.LookVector   -- fallback
        end

        -- Perpendicular horizontal direction for weave
        local right = Vector3.new(-awayDir.Z, 0, awayDir.X).Unit

        -- Retreat point: behind us + climb + lateral weave
        local retreatTarget = myPos
                            + awayDir * 200                      -- move away
                            + Vector3.new(0, 150, 0)             -- climb
                            + right * weaveDir * WEAVE_AMPLITUDE -- weave

        return retreatTarget, nil

    else  -- "orbit"
        -- Orbit above the enemy
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
