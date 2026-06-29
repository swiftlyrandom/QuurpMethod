-- RPGWeapon.lua – Auto‑equip & fire RPG at the closest fast‑moving enemy
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local player = Players.LocalPlayer

local RPGWeapon = {}
local bulletSpeed = 225
local fireCooldown = 3
local maxRange = 2000
local minSpeed = 100
local lastFireTime = 0

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

    -- Already holding the right tool
    local equipped = character:FindFirstChildOfClass("Tool")
    if equipped and equipped.Name == toolName then
        return equipped
    end

    local backpack = player:FindFirstChild("Backpack")
    if not backpack then return end

    local tool = backpack:FindFirstChild(toolName) or character:FindFirstChild(toolName)
    if not tool then
        return nil  -- tool not available
    end

    humanoid:UnequipTools()
    humanoid:EquipTool(tool)
    return tool
end

-- ---- Target selection ----
local function getClosestValidTarget(origin)
    local closest, closestDist = nil, maxRange
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= player and plr.Team ~= player.Team then
            local char = plr.Character
            local hrp = char and char:FindFirstChild("HumanoidRootPart")
            if hrp then
                local vel = hrp.AssemblyLinearVelocity
                if vel.Magnitude > minSpeed then
                    local dist = (hrp.Position - origin).Magnitude
                    if dist < closestDist then
                        closestDist = dist
                        closest = hrp
                    end
                end
            end
        end
    end
    return closest
end

-- ---- Fire one shot ----
local function fireAt(aimPos)
    local event = ReplicatedStorage:FindFirstChild("Event")
    if event then
        event:FireServer("fireRPG", { aimPos })
    end
end

-- ---- Called every heartbeat from MainController ----
function RPGWeapon.update(vehicleBody)
    local now = tick()
    if now - lastFireTime < fireCooldown then return end

    local tool = equipTool("RPG")
    if not tool then return end   -- can't fire without the tool

    local targetHRP = getClosestValidTarget(vehicleBody.Position)
    if not targetHRP then return end

    local aimPos = getAimPosition(
        vehicleBody.Position,
        targetHRP.Position,
        targetHRP.AssemblyLinearVelocity
    )
    if aimPos then
        fireAt(aimPos)
        lastFireTime = now
    end
end

return RPGWeapon
