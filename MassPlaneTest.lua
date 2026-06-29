-- ============================================================
--  VehicleController.lua
--  Self-contained vehicle flight controller.
--  Movement system is inlined — no external module loader.
-- ============================================================

-- ============================================================
--  CONFIG
-- ============================================================
local BASE_URL    = "https://scholar-sustained-wasp.ngrok-free.dev"
local COMMAND_URL  = BASE_URL .. "/get-command"
local REGISTER_URL = BASE_URL .. "/register"
local ACK_URL      = BASE_URL .. "/ack-team"

local PLANE_CONFIG = {
    difficulty     = "Elite",
    vehicleName    = "Bomber",
    fovRadius      = 2000,
    engineSpeed    = 8652.419607067108,
    engineThrottle = 1.2,
    engineAltitude = 40,
    debugPrint     = false,

    offsetRangeMin = -300,
    offsetRangeMax =  300,
}

-- ============================================================
--  MOVEMENT SYSTEM  (inlined from FlightController)
-- ============================================================
local MOVE = {}

local MC = {
    gyroDampening     = 0.8,
    gyroMaxTorque     = 5e5,

    lerpAttack        = 0.08,
    lerpCruise        = 0.05,
    lerpClimb         = 0.07,

    cruiseSpeed       = 120,
    combatSpeed       = 120,
    climbSpeed        = 120,

    minSafeAltitude   = 80,
    maxAltitude       = 800,
    preferredAltitude = 350,

    leadCoeff         = 1.2,
}

-- Points the plane toward a world position via BodyGyro or AlignOrientation
local function setHeading(body, targetPos, lerpFactor)
    local gyro = body:FindFirstChild("BodyGyro")
    if not gyro then return end

    local dir = targetPos - body.Position
    if dir.Magnitude < 0.1 then return end

    local desired = CFrame.new(body.Position, targetPos)

    if gyro:IsA("BodyGyro") then
        gyro.CFrame    = gyro.CFrame:Lerp(desired, math.clamp(lerpFactor or 0.10, 0, 1))
        gyro.D         = MC.gyroDampening
        gyro.MaxTorque = Vector3.new(MC.gyroMaxTorque, MC.gyroMaxTorque, MC.gyroMaxTorque)
    elseif gyro:IsA("AlignOrientation") then
        gyro.CFrame         = desired
        gyro.Responsiveness = math.clamp((lerpFactor or 0.10) * 200, 1, 200)
        gyro.MaxTorque      = math.huge
    end
end

-- Drives the plane forward along its look vector at the given speed
local function setSpeed(body, speed)
    local vel = body:FindFirstChild("BodyVelocity")
    if not vel then return end
    local moveDir = body.CFrame.LookVector * speed
    if vel:IsA("BodyVelocity") then
        vel.Velocity = moveDir
        vel.MaxForce = Vector3.new(1e5, 1e5, 1e5)
    elseif vel:IsA("LinearVelocity") then
        vel.VectorVelocity = moveDir
        vel.MaxForce       = 1e5
    end
end

-- Clamps a target's Y so the plane never aims into the ground
local function safeTarget(body, targetPos)
    local floor = MC.minSafeAltitude + 15
    local safeY = math.max(targetPos.Y, floor)
    if body.Position.Y < floor then
        safeY = math.max(safeY, body.Position.Y + 60)
    end
    return Vector3.new(targetPos.X, safeY, targetPos.Z)
end

-- Emergency pull-up; returns true if triggered so callers can bail early
local function emergencyClimbIfNeeded(body)
    if body.Position.Y >= MC.minSafeAltitude then return false end
    local pullUp = body.Position + body.CFrame.LookVector * 100
                   + Vector3.new(0, 200, 0)
    setHeading(body, pullUp, MC.lerpClimb * 1.3)
    setSpeed(body, MC.climbSpeed)
    return true
end

-- Lead-prediction intercept: aims ahead of a moving target
local function predictIntercept(targetPos, targetVel, myPos, mySpeed)
    local dist = (targetPos - myPos).Magnitude
    local t    = (dist / math.max(mySpeed, 1)) * MC.leadCoeff
    return targetPos + targetVel * t
end

-- Steer toward a position (with optional target velocity for lead prediction)
function MOVE.intercept(body, targetPos, targetVel, dt)
    if emergencyClimbIfNeeded(body) then return end
    targetVel = targetVel or Vector3.zero

    local intercept = predictIntercept(targetPos, targetVel, body.Position, MC.combatSpeed)
    if body.Position.Y < MC.minSafeAltitude then
        intercept = intercept + Vector3.new(0, MC.minSafeAltitude - body.Position.Y + 20, 0)
    end

    local finalAim = safeTarget(body, intercept)
    setHeading(body, finalAim, MC.lerpAttack)
    setSpeed(body, MC.combatSpeed)
end

-- Steady forward cruise with altitude correction
function MOVE.cruise(body)
    local forward = body.Position + body.CFrame.LookVector * 300
    local alt = body.Position.Y
    if alt < MC.preferredAltitude - 50 then
        forward = forward + Vector3.new(0, 60, 0)
    elseif alt > MC.preferredAltitude + 50 then
        forward = forward - Vector3.new(0, 40, 0)
    end
    forward = safeTarget(body, forward)
    setHeading(body, forward, MC.lerpCruise)
    setSpeed(body, MC.cruiseSpeed)
end

-- ============================================================
--  SERVICES
-- ============================================================
local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService       = game:GetService("HttpService")
local RunService        = game:GetService("RunService")
local player            = Players.LocalPlayer

-- ============================================================
--  WORLD SCAN  (objectives: islands + harbours)
-- ============================================================
local function getModelPosition(name)
    local model = workspace:FindFirstChild(name)
    if model then
        local primary = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")
        if primary then return primary.Position end
    end
    return nil
end

local function scanObjectives(myTeamName)
    print("[VehicleController] Scanning world for objectives...")
    local found = {}

    local friendlyDockName = (myTeamName == "USA") and "USDock" or "JapanDock"
    local enemyDockName    = (myTeamName == "USA") and "JapanDock" or "USDock"

    local friendlyPos = getModelPosition(friendlyDockName)
    local enemyPos    = getModelPosition(enemyDockName)

    if friendlyPos then
        found["harbour_friendly"] = friendlyPos
        print("[VehicleController] harbour_friendly:", tostring(friendlyPos))
    else
        warn("[VehicleController] Could not find friendly harbour:", friendlyDockName)
    end

    if enemyPos then
        found["harbour_enemy"] = enemyPos
        print("[VehicleController] harbour_enemy:", tostring(enemyPos))
    else
        warn("[VehicleController] Could not find enemy harbour:", enemyDockName)
    end

    for _, obj in ipairs(workspace:GetChildren()) do
        if obj.Name ~= "Island" then continue end
        local codeVal = obj:FindFirstChild("IslandCode")
        if not codeVal then continue end
        local primary = obj.PrimaryPart or obj:FindFirstChildWhichIsA("BasePart")
        if not primary then continue end
        local key = "island_" .. tostring(codeVal.Value):lower()
        found[key] = primary.Position
        print("[VehicleController] Mapped", key, "->", tostring(primary.Position))
    end

    return found
end

-- ============================================================
--  AUTO SEATER
-- ============================================================
local RESPAWN_COOLDOWN = 2
local SPAWN_COOLDOWN   = 5
local currentVehicle   = nil
local lastSpawnTime    = 0
local seatConnection   = nil

local PLANE_NAMES = {
    ["Bomber"]         = true,
    ["Torpedo Bomber"] = true,
    ["Large Bomber"]   = true,
}

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
    if not spawnPart then
        warn("[AutoSeater] Could not find spawn part.")
        return
    end
    lastSpawnTime = tick()
    local ev = ReplicatedStorage:FindFirstChild("Event")
    if not ev then
        warn("[AutoSeater] ReplicatedStorage.Event not found.")
        return
    end
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

    if seatConnection then
        seatConnection:Disconnect()
        seatConnection = nil
    end

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

local function startAutoSeater()
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

-- ============================================================
--  OBJECTIVE RESOLVER & FLIGHT STATE
-- ============================================================
local objectives      = {}
local currentTarget   = nil
local currentObjLabel = nil
local currentAlt      = 200

local orbitAngle   = math.random() * math.pi * 2
local ORBIT_RADIUS = 250
local ORBIT_SPEED  = 0.25

local sineTimer   = 0
local SINE_AMP    = 50
local SINE_PERIOD = 12

local function resolveObjective(label, altitude)
    local base = objectives[label]
    if not base then
        warn("[VehicleController] Unknown objective label:", label)
        return nil
    end
    local target = Vector3.new(base.X, altitude, base.Z)
    print(string.format("[VehicleController] Resolved '%s' -> (%.1f, %.1f, %.1f)",
        label, target.X, target.Y, target.Z))
    return target
end

-- ============================================================
--  FLIGHT CALCULATORS
-- ============================================================
local function calcOrbitTarget(base, dt)
    orbitAngle = orbitAngle + ORBIT_SPEED * dt
    local ox = math.cos(orbitAngle) * ORBIT_RADIUS
    local oz = math.sin(orbitAngle) * ORBIT_RADIUS
    return Vector3.new(base.X + ox, base.Y, base.Z + oz)
end

local function calcSineTarget(vehiclePart, dt)
    sineTimer = sineTimer + dt
    local wave    = math.sin((sineTimer / SINE_PERIOD) * math.pi * 2) * SINE_AMP
    local forward = vehiclePart.CFrame.LookVector * 300
    return Vector3.new(
        vehiclePart.Position.X + forward.X,
        currentAlt + wave,
        vehiclePart.Position.Z + forward.Z
    )
end

local function calcClimbTarget(vehiclePart)
    local forward = vehiclePart.CFrame.LookVector * 200
    return Vector3.new(
        vehiclePart.Position.X + forward.X,
        currentAlt + 300,
        vehiclePart.Position.Z + forward.Z
    )
end

local DIVE_TARGET_ALT = 100
local function calcDiveTarget(vehiclePart)
    local forward = vehiclePart.CFrame.LookVector * 300
    return Vector3.new(
        vehiclePart.Position.X + forward.X,
        DIVE_TARGET_ALT,
        vehiclePart.Position.Z + forward.Z
    )
end

-- ============================================================
--  NETWORK — MASTER COMMAND POLLING
-- ============================================================
local currentMode      = "cruise"
local isFetching       = false
local NETWORK_INTERVAL = 1.0
local NETWORK_TIMEOUT  = 5
local lastNetworkCheck = 0
local BOT_ID           = nil

local function registerWithServer(botId, teamName)
    local url = string.format("%s?id=%s&team=%s",
        REGISTER_URL,
        HttpService:UrlEncode(botId),
        HttpService:UrlEncode(teamName)
    )
    pcall(function()
        request({
            Url     = url,
            Method  = "GET",
            Timeout = NETWORK_TIMEOUT,
            Headers = { ["ngrok-skip-browser-warning"] = "true" }
        })
    end)
    print("[VehicleController] Registered as:", botId)
end

-- Notifies MasterControl that the team change completed so it clears
-- the pending badge and stops sending the team field.
local function ackTeamChange(botId, newTeam)
    local url = string.format("%s?id=%s&team=%s",
        ACK_URL,
        HttpService:UrlEncode(botId),
        HttpService:UrlEncode(newTeam)
    )
    pcall(function()
        request({
            Url     = url,
            Method  = "GET",
            Timeout = NETWORK_TIMEOUT,
            Headers = { ["ngrok-skip-browser-warning"] = "true" }
        })
    end)
    print("[VehicleController] Acked team change:", newTeam)
end

-- Walks the character to the correct TeamChange part then the Teleporter.
-- Blocks (via task.wait loops) until the walk finishes or times out.
local function walkToTeam(requestedTeam)
    local character = player.Character or player.CharacterAdded:Wait()
    local humanoid  = character:WaitForChild("Humanoid")
    if not humanoid or humanoid.Health <= 0 then return end

    local lobby      = workspace:WaitForChild("Lobby", 10)
    if not lobby then warn("[TeamWalk] Lobby not found"); return end

    local teamChange = lobby:WaitForChild("TeamChange", 5)
    local teleporter = lobby:WaitForChild("Teleporter", 5)
    if not teamChange or not teleporter then
        warn("[TeamWalk] TeamChange or Teleporter not found in Lobby")
        return
    end

    -- Pick the correct part based on requested team.
    -- If we're already on USA we walk to ToJapan and vice versa.
    local currentTeamName = player.Team and player.Team.Name or ""
    local targetPart
    if requestedTeam == "USA" then
        targetPart = teamChange:WaitForChild("ToUSA", 5)
    else
        targetPart = teamChange:WaitForChild("ToJapan", 5)
    end

    if not targetPart then
        warn("[TeamWalk] Target team part not found:", requestedTeam)
        return
    end

    print("[TeamWalk] Walking to team changer:", targetPart.Name)
    humanoid:MoveTo(targetPart.Position)
    humanoid.MoveToFinished:Wait()
    print("[TeamWalk] Reached team changer")

    task.wait(1.5)  -- brief pause so the team changer triggers

    print("[TeamWalk] Walking to teleporter")
    -- Re-fetch humanoid in case character refreshed after team change
    character = player.Character or player.CharacterAdded:Wait()
    humanoid  = character:WaitForChild("Humanoid")
    humanoid:MoveTo(teleporter.Position)
    humanoid.MoveToFinished:Wait()
    print("[TeamWalk] Reached teleporter")

    task.wait(2)  -- wait for teleport to fire and character to land
end

local function fetchMasterCommands()
    if isFetching then return end
    if not BOT_ID   then return end
    isFetching = true

    local url = string.format("%s?id=%s",
        COMMAND_URL,
        HttpService:UrlEncode(BOT_ID)
    )

    local ok, response = pcall(function()
        return request({
            Url     = url,
            Method  = "GET",
            Timeout = NETWORK_TIMEOUT,
            Headers = { ["ngrok-skip-browser-warning"] = "true" }
        })
    end)

    isFetching = false

    if not ok then
        warn("[VehicleController] Network request failed:", tostring(response))
        return
    end

    if not response or response.StatusCode ~= 200 then
        warn("[VehicleController] Bad response:", response and response.StatusCode or "nil")
        return
    end

    local decodeOk, data = pcall(function()
        return HttpService:JSONDecode(response.Body)
    end)

    if not decodeOk or not data then
        warn("[VehicleController] JSON decode failed:", tostring(data))
        return
    end

    local newMode  = data.mode      or currentMode
    local newAlt   = data.altitude  or currentAlt
    local newLabel = data.objective
    local newTeam  = data.team  -- nil means no change pending

    -- Team switch takes priority — pause everything and walk
    if newTeam and newTeam ~= "" and newTeam ~= (player.Team and player.Team.Name or "") then
        print("[VehicleController] Team change requested:", newTeam)
        task.spawn(function()
            walkToTeam(newTeam)
            local confirmedTeam = player.Team and player.Team.Name or newTeam
            ackTeamChange(BOT_ID, confirmedTeam)
        end)
        return  -- skip mode/objective update this tick; next poll will be clean
    end

    if newMode ~= currentMode then
        print("[VehicleController] Mode:", currentMode:upper(), "->", newMode:upper())
    end

    currentMode = newMode

    if currentMode == "objective" and newLabel then
        local changed = (newLabel ~= currentObjLabel) or (newAlt ~= currentAlt)
        currentAlt      = newAlt
        currentObjLabel = newLabel
        if changed then
            currentTarget = resolveObjective(newLabel, newAlt)
        end
    else
        currentAlt    = newAlt
        currentTarget = nil
    end
end

-- ============================================================
--  BOOT
-- ============================================================
local function boot()
    print("[VehicleController] Waiting for team assignment...")
    local teamWaitStart = tick()
    while not player.Team do
        if tick() - teamWaitStart > 30 then
            warn("[VehicleController] Timed out waiting for team.")
            break
        end
        task.wait(0.5)
    end

    local myTeamName = player.Team and player.Team.Name or "Unknown"
    print("[VehicleController] Team:", myTeamName)

    BOT_ID = player.Name
    print("[VehicleController] ID:", BOT_ID)
    registerWithServer(BOT_ID, myTeamName)

    objectives = scanObjectives(myTeamName)

    -- Re-scan if the map reloads mid-session
    local isRescanning = false
    workspace.ChildAdded:Connect(function(child)
        if child.Name ~= "Island" then return end
        if isRescanning then return end
        isRescanning = true
        task.spawn(function()
            task.wait(3)
            print("[VehicleController] Map reload — re-scanning objectives...")
            objectives    = scanObjectives(myTeamName)
            currentTarget = nil
            currentObjLabel = nil
            isRescanning  = false
        end)
    end)

    startAutoSeater()
    currentVehicle = findExistingVehicle()
    if not currentVehicle then
        spawnVehicle()
    else
        seatPlayer(currentVehicle)
    end

    print("[VehicleController] Main loop starting...")

    RunService.Heartbeat:Connect(function(dt)
        -- Poll server on interval
        lastNetworkCheck = lastNetworkCheck + dt
        if lastNetworkCheck >= NETWORK_INTERVAL then
            lastNetworkCheck = 0
            task.spawn(fetchMasterCommands)
        end

        if not currentVehicle or not currentVehicle.Parent then return end

        local body = currentVehicle.PrimaryPart
            or currentVehicle:FindFirstChild("MainBody")
            or currentVehicle:FindFirstChildWhichIsA("BasePart")
        if not body then return end

        -- Route to appropriate flight calculator, then hand off to movement system
        local target

        if currentMode == "objective" then
            if currentTarget then
                target = calcOrbitTarget(currentTarget, dt)
            else
                target = calcSineTarget(body, dt)
            end
        elseif currentMode == "cruise" then
            target = calcSineTarget(body, dt)
        elseif currentMode == "climb" then
            target = calcClimbTarget(body)
        elseif currentMode == "dive" then
            target = calcDiveTarget(body)
        end

        if target then
            MOVE.intercept(body, target, Vector3.zero, dt)
        else
            MOVE.cruise(body)
        end
    end)

    print("[VehicleController] Running.")
end

local ok, err = pcall(boot)
if not ok then
    warn("[VehicleController] BOOT FAILED:", err)
end
