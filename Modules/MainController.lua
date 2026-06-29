-- MainController.lua
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local player = Players.LocalPlayer

local Config       = _G._Modules.VehicleConfig
local MOVE         = _G._Modules.MovementController
local WorldScanner = _G._Modules.WorldScanner
local AutoSeater   = _G._Modules.AutoSeater
local ObjResolver  = _G._Modules.ObjectiveResolver
local Network      = _G._Modules.NetworkController
local RPGWeapon = _G._Modules.RPGWeapon

local NETWORK_INTERVAL = 1.0
local lastNetworkCheck = 0

local function boot()
    print("[Main] Waiting for team...")
    while not player.Team do task.wait(0.5) end
    local myTeamName = player.Team.Name
    print("[Main] Team:", myTeamName)

    Network.BOT_ID = player.Name
    Network.register(Network.BOT_ID, myTeamName)

    local objectives = WorldScanner.scan(myTeamName)
    ObjResolver.setObjectives(objectives)

    -- Re‑scan on map reload
    local isRescanning = false
    workspace.ChildAdded:Connect(function(child)
        if child.Name ~= "Island" then return end
        if isRescanning then return end
        isRescanning = true
        task.spawn(function()
            task.wait(3)
            print("[Main] Map reload — re‑scanning objectives...")
            local objectives = WorldScanner.scan(myTeamName)
            ObjResolver.setObjectives(objectives)
            ObjResolver.currentTarget = nil
            ObjResolver.currentObjLabel = nil
            isRescanning = false
        end)
    end)

    AutoSeater.start()
    -- Try to seat immediately if a vehicle exists
    local veh = AutoSeater.getVehicle()
    if not veh then
        -- spawnVehicle is called inside AutoSeater.start's periodic check
    end

    print("[Main] Main loop starting...")

    RunService.Heartbeat:Connect(function(dt)
        lastNetworkCheck = lastNetworkCheck + dt
        if lastNetworkCheck >= NETWORK_INTERVAL then
            lastNetworkCheck = 0
            task.spawn(function()
                local success, mode, altitude, objLabel, reqTeam = Network.pollCommands()
                if not success then return end

                if reqTeam and reqTeam ~= "" and reqTeam ~= player.Team.Name then
                    -- Team change takes priority, pause other updates
                    print("[Main] Team change requested:", reqTeam)
                    Network.walkAndChangeTeam(reqTeam, function()
                        local newTeam = player.Team and player.Team.Name or reqTeam
                        Network.ackTeamChange(Network.BOT_ID, newTeam)
                    end)
                    return
                end

                if mode ~= ObjResolver.mode then
                    print("[Main] Mode:", ObjResolver.mode:upper(), "→", mode:upper())
                end
                ObjResolver.mode = mode
                ObjResolver.currentAlt = altitude

                if mode == "objective" and objLabel then
                    ObjResolver.resolveObjective(objLabel, altitude)
                end
            end)
        end

        local vehicle = AutoSeater.getVehicle()
        if not vehicle or not vehicle.Parent then return end

        local body = vehicle.PrimaryPart
            or vehicle:FindFirstChild("MainBody")
            or vehicle:FindFirstChildWhichIsA("BasePart")
        if not body then return end

        MOVE.tickCorkscrew(dt)

        local target = ObjResolver.getTarget(body, dt)
        if target then
            target = target + MOVE.getCorkscrewOffset(body.CFrame.LookVector)
            MOVE.intercept(body, target, Vector3.zero, dt)
        else
            MOVE.cruise(body)
        end

        local rpgConfig = Config.RPG_CONFIG
        if rpgConfig and rpgConfig.enabled then
            RPGWeapon.update(body)
        end
            
    end)
end

local ok, err = pcall(boot)
if not ok then
    warn("[MainController] Boot failed:", err)
end
