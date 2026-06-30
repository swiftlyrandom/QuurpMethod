-- GunnerController.lua – back gunner AI, paired via MasterControl
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")

local LocalPlayer = Players.LocalPlayer
local Event = ReplicatedStorage:WaitForChild("Event")

local Config = _G._Modules.VehicleConfig.GUNNER_CONFIG
local PredUtils = _G._Modules.PredictionUtils
local Network = _G._Modules.NetworkController

local BULLET_SPEED    = Config.bulletSpeed or 600
local SHOOT_DURATION  = Config.shootDuration or 2
local SHOOT_BREAK     = Config.shootBreak or 1
local MAX_RANGE       = Config.maxRange or 1400
local SETUP_DELAY     = Config.setupDelay or 8
local ENEMY_SPEED     = Config.enemySpeed or 100

local botId = LocalPlayer.Name
local currentPairWith = nil
local heartbeatConn = nil
local currentBomber = nil
local currentSeat = nil

-- ---- Prediction from shared module ----
local getAimPosition = PredUtils.getAimPosition

-- ---- Target selection ----
local function getTarget(gunPos)
    local bestPlayer = nil
    local bestDist = MAX_RANGE
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr == LocalPlayer then continue end
        local char = plr.Character
        if not char then continue end
        if plr.Team and LocalPlayer.Team and plr.Team == LocalPlayer.Team then continue end
        local hrp = char:FindFirstChild("HumanoidRootPart")
        if not hrp then continue end
        local dist = (hrp.Position - gunPos).Magnitude
        if dist > MAX_RANGE then continue end
        local speed = hrp.AssemblyLinearVelocity.Magnitude
        if math.abs(speed - ENEMY_SPEED) > 20 then continue end
        if dist < bestDist then
            bestDist = dist
            bestPlayer = plr
        end
    end
    return bestPlayer
end

-- ---- Fire control ----
local function aim(position)
    Event:FireServer("aim", { Vector3.new(position.X, position.Y, position.Z) })
end

local function setShoot(state)
    Event:FireServer("shoot", { state })
end

local function stopEngagement()
    if heartbeatConn then
        heartbeatConn:Disconnect()
        heartbeatConn = nil
    end
    setShoot(false)
    currentSeat = nil
    currentBomber = nil
    currentPairWith = nil
end

local function startEngagement(seat, bomber)
    stopEngagement()
    currentSeat = seat
    currentBomber = bomber

    local shootTimer = 0
    local shootState = false

    heartbeatConn = RunService.Heartbeat:Connect(function(dt)
        if not seat or not seat.Parent or not bomber or not bomber.Parent then
            stopEngagement()
            return
        end
        local gunPos = seat.Position
        local target = getTarget(gunPos)
        if target and target.Character then
            local targetHRP = target.Character:FindFirstChild("HumanoidRootPart")
            if targetHRP then
                local predicted = getAimPosition(gunPos, targetHRP.Position, targetHRP.AssemblyLinearVelocity, BULLET_SPEED)
                if predicted then aim(predicted) end
            end
            shootTimer = shootTimer + dt
            if not shootState then
                if shootTimer >= SHOOT_BREAK then
                    shootTimer = 0; shootState = true; setShoot(true)
                end
            else
                if shootTimer >= SHOOT_DURATION then
                    shootTimer = 0; shootState = false; setShoot(false)
                end
            end
        else
            if shootState then setShoot(false); shootState = false end
            shootTimer = 0
        end
    end)

    bomber.AncestryChanged:Connect(function()
        if not bomber.Parent then stopEngagement() end
    end)
end

-- ---- Find bomber by owner name ----
local function findBomberByOwner(ownerName)
    for _, obj in ipairs(workspace:GetChildren()) do
        if obj.Name == "Large Bomber" then
            local ownerVal = obj:FindFirstChild("Owner")
            if ownerVal and ownerVal.Value == ownerName then
                return obj
            end
        end
    end
    return nil
end

-- ---- Command polling loop ----
local function pollCommands()
    while true do
        local success, mode, altitude, objLabel, reqTeam, pairWith = Network.pollCommands()
        -- We hijack Network.pollCommands to also return the pair_with field.
        -- We'll modify NetworkController.lua to support this (see snippet below).
        -- For now, we assume a custom poll that returns pairWith.
        -- We'll implement a direct HTTP call here instead of modifying Network.
        task.wait(1)
    end
end

-- Simpler: call the server directly for our own command
local function fetchPairCommand()
    local url = string.format("%s/get-command?id=%s",
        _G._Modules.VehicleConfig.COMMAND_URL,
        HttpService:UrlEncode(botId))
    local ok, response = pcall(function()
        return request({Url=url, Method="GET", Headers={["ngrok-skip-browser-warning"]="true"}})
    end)
    if ok and response and response.StatusCode == 200 then
        local data = HttpService:JSONDecode(response.Body)
        if data and data.pair_with then
            return data.pair_with
        end
    end
    return nil
end

-- ---- Initialisation ----
local function init()
    local teamName = LocalPlayer.Team and LocalPlayer.Team.Name or "Unknown"
    Network.register(botId, teamName)

    -- Poll for pair_with every 2 seconds
    task.spawn(function()
        while true do
            local newPairWith = fetchPairCommand()
            if newPairWith ~= currentPairWith then
                currentPairWith = newPairWith
                if currentPairWith then
                    local bomber = findBomberByOwner(currentPairWith)
                    if bomber then
                        local seat = bomber:FindFirstChild("SBTurretSeat")
                        if seat then
                            local character = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
                            local hrp = character:WaitForChild("HumanoidRootPart")
                            hrp.CFrame = seat.CFrame
                            startEngagement(seat, bomber)
                        end
                    end
                else
                    stopEngagement()
                end
            end
            task.wait(2)
        end
    end)
end

init()
return {}
