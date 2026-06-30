-- GunSystem.lua – forward gun control (plane‑mounted weapon)
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Event = ReplicatedStorage:WaitForChild("Event")

local GunSystem = {}

local BULLET_SPEED = 600
local AIM_ANGLE_THRESHOLD = 10   -- degrees off‑nose before we stop firing

local _isFiring = false

local function aimError(body, aimPos)
    local dir = aimPos - body.Position
    if dir.Magnitude < 0.1 then return 180 end
    local dot = math.max(-1, math.min(1, body.CFrame.LookVector:Dot(dir.Unit)))
    return math.deg(math.acos(dot))
end

local function predictAimPoint(bodyPos, targetPos, targetVel)
    local dist = (targetPos - bodyPos).Magnitude
    local travelTime = dist / BULLET_SPEED
    local ping = Players.LocalPlayer:GetNetworkPing()
    local leadTime = travelTime + ping * 0.5
    return targetPos + targetVel * leadTime
end

function GunSystem.update(body, enemyHRP)
    if not enemyHRP or not enemyHRP.Parent then
        GunSystem.stopFiring()
        return
    end

    local targetPos = enemyHRP.Position
    local targetVel = enemyHRP.AssemblyLinearVelocity

    local aimPos = predictAimPoint(body.Position, targetPos, targetVel)
    local errorDeg = aimError(body, aimPos)

    if errorDeg <= AIM_ANGLE_THRESHOLD then
        if not _isFiring then
            Event:FireServer("shoot", { true })
            _isFiring = true
        end
    else
        if _isFiring then
            Event:FireServer("shoot", { false })
            _isFiring = false
        end
    end
end

function GunSystem.stopFiring()
    if _isFiring then
        Event:FireServer("shoot", { false })
        _isFiring = false
    end
end

return GunSystem
