-- RPGWeapon.lua – Auto‑equip & fire RPG at enemies + static objectives (harbour)
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local player = Players.LocalPlayer

local RPGWeapon = {}
local bulletSpeed = 225
local fireCooldown = 3
local maxRange = 2000
local minSpeed = 100
local lastFireTime = 0

-- Static targets (e.g. enemy harbour)
local staticTargets = {}

-- ---- Prediction (unchanged) ----
local function solveQuadratic(a, b, c)
    local d = b*b - 4*a*c
    if d < 0 then return nil end
    local sqrtD = math.sqrt(d)
    local t1 = (-b - sqrtD) / (2*a)
    local t2 = (-b + sqrtD) / (2*a)
    return (t1 > 0 and t1) or (t2 > 0 and t2) or nil
end

local function getAimPosition(gunPos, targetPos, targetVel)
    local dp = targetPos - gunPos
    local a = targetVel:Dot(targetVel) - bulletSpeed*bulletSpeed
    local b = 2 * dp:Dot(targetVel)
    local c = dp:Dot(dp)
    local t = solveQuadratic(a, b, c)
    if not t then return nil end
    return targetPos + targetVel * t
end

-- ---- Tool handling ----
local function equipTool(toolName)
    local character = player.Character
    if not character then return end
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    if not humanoid then return end

    local equipped = character:FindFirstChildOfClass("Tool")
    if equipped and equipped.Name == toolName then
        return equipped
    end

    local backpack = player:FindFirstChild("Backpack")
    if not backpack then return end

    local tool = backpack:FindFirstChild(toolName) or character:FindFirstChild(toolName)
    if not tool then
        return nil
    end

    humanoid:UnequipTools()
    humanoid:EquipTool(tool)
    return tool
end

-- ---- Fire one shot ----
local function fireAt(aimPos)
    local event = ReplicatedStorage:FindFirstChild("Event")
    if event then
        event:FireServer("fireRPG", { aimPos })
    end
end

-- ---- Add / remove static targets ----
function RPGWeapon.addStaticTarget(pos, priority)
    table.insert(staticTargets, {position = pos, priority = priority or 1})
end

function RPGWeapon.clearStaticTargets()
    staticTargets = {}
end

-- ---- Called every heartbeat from MainController ----
function RPGWeapon.update(vehicleBody)
    local now = tick()
    if now - lastFireTime < fireCooldown then return end

    local tool = equipTool("RPG")
    if not tool then return end

    local origin = vehicleBody.Position

    -- 1) Check static targets (e.g. enemy harbour) within range
    local bestStatic = nil
    local bestStaticDist = maxRange
    for _, st in ipairs(staticTargets) do
        local d = (st.position - origin).Magnitude
        if d < bestStaticDist then
            bestStaticDist = d
            bestStatic = st.position
        end
    end

    if bestStatic then
        fireAt(bestStatic)
        lastFireTime = now
        return
    end

    -- 2) Check moving enemies
    local targetHRP = nil
    local targetDist = maxRange
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= player and plr.Team ~= player.Team then
            local char = plr.Character
            local hrp = char and char:FindFirstChild("HumanoidRootPart")
            if hrp then
                local vel = hrp.AssemblyLinearVelocity
                if vel.Magnitude > minSpeed then
                    local dist = (hrp.Position - origin).Magnitude
                    if dist < targetDist then
                        targetDist = dist
                        targetHRP = hrp
                    end
                end
            end
        end
    end

    if targetHRP then
        local aimPos = getAimPosition(
            origin,
            targetHRP.Position,
            targetHRP.AssemblyLinearVelocity
        )
        if aimPos then
            fireAt(aimPos)
            lastFireTime = now
        end
    end
end

return RPGWeapon
