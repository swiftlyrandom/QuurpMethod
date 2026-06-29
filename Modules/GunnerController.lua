-- GunnerController.lua – back gunner AI for heavy bomber
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local LocalPlayer = Players.LocalPlayer
local Event = ReplicatedStorage:WaitForChild("Event")

local Config = _G._Modules.VehicleConfig.GUNNER_CONFIG
local PredUtils = _G._Modules.PredictionUtils
local Network = _G._Modules.NetworkController   -- for registration

local BULLET_SPEED    = Config.bulletSpeed or 600
local SHOOT_DURATION  = Config.shootDuration or 2
local SHOOT_BREAK     = Config.shootBreak or 1
local OWNER_NAME      = Config.ownerName or "B3X0Z"
local BOMBER_NAME     = Config.bomberName or "Large Bomber"
local MAX_RANGE       = Config.maxRange or 1400
local SETUP_DELAY     = Config.setupDelay or 8
local ENEMY_SPEED     = Config.enemySpeed or 100

local heartbeatConn = nil
local currentBomber = nil
local currentSeat = nil

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
        if math.abs(speed - ENEMY_SPEED) > 20 then continue end  -- intentional filter

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
                local predicted = PredUtils.getAimPosition(
                    gunPos,
                    targetHRP.Position,
                    targetHRP.AssemblyLinearVelocity,
                    BULLET_SPEED
                )
                if predicted then
                    aim(predicted)
                end
            end

            shootTimer = shootTimer + dt
            if not shootState then
                if shootTimer >= SHOOT_BREAK then
                    shootTimer = 0
                    shootState = true
                    setShoot(true)
                end
            else
                if shootTimer >= SHOOT_DURATION then
                    shootTimer = 0
                    shootState = false
                    setShoot(false)
                end
            end
        else
            if shootState then
                shootState = false
                setShoot(false)
            end
            shootTimer = 0
        end
    end)

    -- When bomber is destroyed or we leave, clean up
    bomber.AncestryChanged:Connect(function()
        if not bomber.Parent then
            stopEngagement()
        end
    end)
end

-- ---- Bomber setup ----
local function setupBomber(bomber)
    task.wait(2)
    local ownerVal = bomber:FindFirstChild("Owner")
    if not ownerVal or ownerVal.Value ~= OWNER_NAME then
        warn("[Gunner] Owner check failed.")
        return
    end

    local seat = bomber:FindFirstChild("SBTurretSeat")
    if not seat then
        warn("[Gunner] SBTurretSeat not found.")
        return
    end

    print("[Gunner] Bomber found. Waiting " .. SETUP_DELAY .. " seconds...")
    task.wait(SETUP_DELAY)

    if not bomber.Parent then
        print("[Gunner] Bomber destroyed during wait.")
        return
    end

    local character = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
    local hrp = character:WaitForChild("HumanoidRootPart")
    hrp.CFrame = seat.CFrame
    print("[Gunner] Teleported. Engaging.")

    startEngagement(seat, bomber)
end

-- ---- Init ----
local function init()
    -- Register with MasterControl (so it appears in the swarm list)
    -- Use a unique ID: player name + "-gunner" to avoid conflict with pilot
    local botId = LocalPlayer.Name .. "-Gunner"
    Network.BOT_ID = botId
    local teamName = LocalPlayer.Team and LocalPlayer.Team.Name or "Unknown"
    Network.register(botId, teamName)

    -- Listen for bomber spawns
    workspace.ChildAdded:Connect(function(child)
        if child.Name == BOMBER_NAME then
            task.spawn(setupBomber, child)
        end
    end)

    local existing = workspace:FindFirstChild(BOMBER_NAME)
    if existing then
        task.spawn(setupBomber, existing)
    end
end

init()

return {}   -- satisfy BootLoader
