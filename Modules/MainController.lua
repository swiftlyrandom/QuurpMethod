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
local RPGWeapon    = _G._Modules.RPGWeapon
local CombatBrain  = _G._Modules.CombatBrain
local GunSystem    = _G._Modules.GunSystem

local NETWORK_INTERVAL = 1.0
local lastNetworkCheck = 0

-- MainController.lua – wrapped for dynamic start/stop

local MainController = {}
local heartbeatConnection = nil
local networkPollConnection = nil

local function boot()
    print("[Main] Waiting for team...")
    while not player.Team do task.wait(0.5) end
    local myTeamName = player.Team.Name
    print("[Main] Team:", myTeamName)

    Network.BOT_ID = player.Name
    Network.register(Network.BOT_ID, myTeamName)

    local objectives = WorldScanner.scan(myTeamName)
    ObjResolver.setObjectives(objectives)

    if objectives["harbour_enemy"] then
        RPGWeapon.addStaticTarget(objectives["harbour_enemy"], 1)
    end

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
            RPGWeapon.clearStaticTargets()
            if objectives["harbour_enemy"] then
                RPGWeapon.addStaticTarget(objectives["harbour_enemy"], 1)
            end
            isRescanning = false
        end)
    end)

    AutoSeater.start()
    local veh = AutoSeater.getVehicle()
    if not veh then
        -- spawn is handled inside AutoSeater.start's periodic check
    end

    print("[Main] Main loop starting...")

    -- Heartbeat for flight + RPG
    heartbeatConnection = RunService.Heartbeat:Connect(function(dt)
        lastNetworkCheck = lastNetworkCheck + dt
        if lastNetworkCheck >= NETWORK_INTERVAL then
            lastNetworkCheck = 0
            task.spawn(function()
                local success, mode, altitude, objLabel, reqTeam = Network.pollCommands()
                if not success then return end
                if reqTeam and reqTeam ~= "" and reqTeam ~= player.Team.Name then
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

        local hp = vehicle:FindFirstChild("HP")
        if hp and hp.Value <= 0 then
            for _, child in ipairs(vehicle:GetDescendants()) do
                if child:IsA("BodyVelocity") or child:IsA("BodyGyro") or child:IsA("AlignOrientation") or child:IsA("LinearVelocity") or child:IsA("AngularVelocity") then
                    child:Destroy()
                end
            end
            return
        end

        local body = vehicle.PrimaryPart
            or vehicle:FindFirstChild("MainBody")
            or vehicle:FindFirstChildWhichIsA("BasePart")
        if not body then return end

        MOVE.tickCorkscrew(dt)

               -- Decide what to fly toward
        local target
        local combatTarget = CombatBrain.update(body, dt)
        if combatTarget then
            target = combatTarget
        else
            -- Only use parabolic arc if NOT in combat
            target = MOVE.getParabolicAimPoint(body.Position, dt)
            if not target then
                local objTarget = ObjResolver.getTarget(body, dt)
                if objTarget then
                    MOVE.setParabolicTarget(body.Position, objTarget, ObjResolver.currentAlt)
                    target = MOVE.getParabolicAimPoint(body.Position, dt)
                end
            end
        end

        -- Apply corkscrew offset (reduced during chase for tighter aim)
        if target then
            local forwardDir = (target - body.Position).Unit
            local nearPoint = body.Position + forwardDir * 80
            local corkscrewOffset = MOVE.getCorkscrewOffset(forwardDir)
            if combatTarget then
                corkscrewOffset = corkscrewOffset * 0.05   -- tighter during combat chase
            end
            target = nearPoint + corkscrewOffset
            MOVE.intercept(body, target, Vector3.zero, dt)
        else
            MOVE.cruise(body)
        end
                 local rpgConfig = Config.RPG_CONFIG
                 if rpgConfig and rpgConfig.enabled then
                     RPGWeapon.update(body)
                 end
            
                 -- Forward guns: fire whenever the nose is on the locked enemy
                 local lockedEnemy = CombatBrain.getLockedEnemy()
                 if lockedEnemy then
                     GunSystem.update(body, lockedEnemy)
                 else
                     GunSystem.stopFiring()
                 end
            end)
        end

-- PUBLIC API
function MainController.start()
    if heartbeatConnection then return end  -- already running
    boot()
end

function MainController.stop()
    if heartbeatConnection then
        heartbeatConnection:Disconnect()
        heartbeatConnection = nil
    end
    -- Kill the vehicle if we own one
    local vehicle = AutoSeater.getVehicle()
    if vehicle then
        -- Remove BodyMovers so it falls/dies
        for _, child in ipairs(vehicle:GetDescendants()) do
            if child:IsA("BodyVelocity") or child:IsA("BodyGyro") or child:IsA("AlignOrientation") or child:IsA("LinearVelocity") or child:IsA("AngularVelocity") then
                child:Destroy()
            end
        end
    end
    print("[Main] Stopped.")
end

return MainController
