-- AutoSeater.lua
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local player = Players.LocalPlayer
local Config = require(script.Parent.VehicleConfig)

local PLANE_CONFIG = Config.PLANE_CONFIG
local PLANE_NAMES  = Config.PLANE_NAMES

local RESPAWN_COOLDOWN = 2
local SPAWN_COOLDOWN   = 5

local currentVehicle = nil
local lastSpawnTime  = 0
local seatConnection = nil

local function isMyVehicle(v)
    local owner = v:FindFirstChild("Owner")
    return owner and owner:IsA("StringValue") and owner.Value == player.Name
end

local function getSpawnPart()
    local teamName = player.Team and player.Team.Name or ""
    local dockName = teamName:lower():find("japan") and "JapanDock" or "USDock"
    local dock = workspace:FindFirstChild(dockName)
    if not dock then return end
    local vsp = dock:FindFirstChild("VehicleSP")
    if not vsp then return end
    return vsp:FindFirstChild("Airport")
end

local function spawnVehicle()
    if tick() - lastSpawnTime < SPAWN_COOLDOWN then return end
    if currentVehicle and currentVehicle.Parent then return end
    local spawnPart = getSpawnPart()
    if not spawnPart then return end
    lastSpawnTime = tick()
    local ev = ReplicatedStorage:FindFirstChild("Event")
    if not ev then return end
    pcall(function()
        ev:FireServer("VSpawn", { spawnPart, PLANE_CONFIG.vehicleName, 2 })
    end)
    print("[AutoSeater] Spawn requested:", PLANE_CONFIG.vehicleName)
end

local function findSeat(vehicle)
    for _, v in ipairs(vehicle:GetDescendants()) do
        if v:IsA("VehicleSeat") or v:IsA("Seat") then return v end
    end
end

local function seatPlayer(vehicle)
    if not vehicle or not vehicle.Parent then return end
    local char = player.Character
    if not char then return end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    local hum = char:FindFirstChild("Humanoid")
    if not hrp or not hum or hum.Health <= 0 then return end
    local seat = findSeat(vehicle)
    if not seat then return end

    if seatConnection then seatConnection:Disconnect() seatConnection = nil end

    hrp.CFrame = seat.CFrame + Vector3.new(0, 1, 0)
    task.wait(0.2)

    if not vehicle.Parent then return end
    char = player.Character
    if not char then return end
    hrp = char:FindFirstChild("HumanoidRootPart")
    hum = char:FindFirstChild("Humanoid")
    if not hrp or not hum or hum.Health <= 0 then return end

    seat:Sit(hum)
    seatConnection = seat:GetPropertyChangedSignal("Occupant"):Connect(function()
        if seat.Occupant == nil then
            task.delay(RESPAWN_COOLDOWN, function() seatPlayer(vehicle) end)
        end
    end)
    print("[AutoSeater] Seated in:", vehicle.Name)
end

local function findExistingVehicle()
    for _, v in ipairs(workspace:GetChildren()) do
        if PLANE_NAMES[v.Name] and isMyVehicle(v) then return v end
    end
end

function startAutoSeater()
    workspace.ChildAdded:Connect(function(child)
        if not PLANE_NAMES[child.Name] then return end
        task.wait(0.5)
        if isMyVehicle(child) then
            currentVehicle = child
            seatPlayer(child)
        end
    end)

    workspace.ChildRemoved:Connect(function(child)
        if child == currentVehicle then
            print("[AutoSeater] Vehicle lost")
            currentVehicle = nil
            task.delay(RESPAWN_COOLDOWN, spawnVehicle)
        end
    end)

    player.CharacterAdded:Connect(function(char)
        char:WaitForChild("HumanoidRootPart")
        local hum = char:WaitForChild("Humanoid")
        task.wait(RESPAWN_COOLDOWN)
        if currentVehicle then
            seatPlayer(currentVehicle)
        else
            spawnVehicle()
        end
        hum.Died:Connect(function()
            task.delay(RESPAWN_COOLDOWN, function()
                if not currentVehicle then spawnVehicle() end
            end)
        end)
    end)

    task.spawn(function()
        while true do
            task.wait(3)
            if not currentVehicle or not currentVehicle.Parent then
                currentVehicle = findExistingVehicle()
                if not currentVehicle then spawnVehicle() end
            end
        end
    end)
end

-- Expose for external use
function getCurrentVehicle()
    return currentVehicle
end

return {
    start = startAutoSeater,
    getVehicle = getCurrentVehicle
}
