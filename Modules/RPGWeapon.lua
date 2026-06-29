-- RPGWeapon.lua – Auto-shoots RPG at closest fast-moving enemy
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local player = Players.LocalPlayer

local RPGWeapon = {}
local bulletSpeed = 225
local fireCooldown = 0.2
local maxRange = 1800
local minSpeed = 100            -- only target enemies moving faster than this

-- ----- prediction maths (from your script) -----
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
    return targetPos + targetVel * t       -- no acceleration term
end

-- ----- target selection -----
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

-- ----- fire one shot -----
local function fireAt(aimPos)
    local event = ReplicatedStorage:FindFirstChild("Event")
    if event then
        event:FireServer("fireRPG", { aimPos })
    end
end

-- ----- called every heartbeat from MainController -----
function RPGWeapon.update(vehicleBody)
    local targetHRP = getClosestValidTarget(vehicleBody.Position)
    if not targetHRP then return end

    local aimPos = getAimPosition(
        vehicleBody.Position,
        targetHRP.Position,
        targetHRP.AssemblyLinearVelocity
    )
    if aimPos then
        fireAt(aimPos)
    end
end

return RPGWeapon
