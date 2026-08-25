--[[
    RLWebSocketClient.lua
    WebSocket client for connecting Roblox to Python RL bot server.
    Uses Delta executor's WebSocket support.
    
    Usage:
        local WSClient = require(_G._Modules.RLWebSocketClient)
        WSClient.connect("ws://192.168.1.100:8765")  -- Your Termux IP
        WSClient.sendObservation(observationTable)
        local action = WSClient.receiveAction()
--]]

local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")

local WebSocketClient = {}
WebSocketClient.__index = WebSocketClient

-- Configuration
local DEFAULT_HOST = "192.168.1.100"  -- Change to your Termux/server IP
local DEFAULT_PORT = 8765
local CONNECTION_TIMEOUT = 5.0  -- seconds
local RECONNECT_DELAY = 2.0  -- seconds

-- State
local websocket = nil
local connected = false
local lastAction = nil
local connectionError = nil

-- Create WebSocket connection
function WebSocketClient.connect(host, port)
    host = host or DEFAULT_HOST
    port = port or DEFAULT_PORT
    
    local url = string.format("ws://%s:%d", host, port)
    print("[RLWebSocket] Connecting to:", url)
    
    local success, err = pcall(function()
        -- Delta executor WebSocket API
        websocket = WebSocket.new(url)
        
        -- Wait for connection with timeout
        local startTime = tick()
        while not websocket.IsConnected and (tick() - startTime) < CONNECTION_TIMEOUT do
            task.wait(0.1)
        end
        
        if not websocket.IsConnected then
            error("Connection timeout")
        end
        
        connected = true
        connectionError = nil
        print("[RLWebSocket] Connected successfully!")
        
        -- Start message listener
        task.spawn(function()
            WebSocketClient._messageListener()
        end)
        
    end)
    
    if not success then
        connected = false
        connectionError = err or "Unknown connection error"
        print("[RLWebSocket] Connection failed:", connectionError)
        return false, connectionError
    end
    
    return true
end

-- Listen for incoming messages (runs in background)
function WebSocketClient._messageListener()
    while connected and websocket do
        local success, message = pcall(function()
            return websocket:Receive()
        end)
        
        if success and message then
            local success, data = pcall(function()
                return HttpService:JSONDecode(message)
            end)
            
            if success then
                lastAction = data
            else
                warn("[RLWebSocket] Failed to parse JSON:", message)
            end
        elseif not success then
            -- Connection likely closed
            connected = false
            break
        end
        
        task.wait(0.001)  -- Small delay to prevent tight loop
    end
end

-- Send observation data to server
function WebSocketClient.sendObservation(observation)
    if not connected or not websocket then
        connectionError = "Not connected"
        return false, connectionError
    end
    
    local success, json = pcall(function()
        return HttpService:JSONEncode(observation)
    end)
    
    if not success then
        connectionError = "Failed to encode JSON: " .. tostring(json)
        return false, connectionError
    end
    
    local sendSuccess, err = pcall(function()
        websocket:Send(json)
    end)
    
    if not sendSuccess then
        connected = false
        connectionError = err or "Send failed"
        return false, connectionError
    end
    
    return true
end

-- Receive latest action from server (non-blocking)
function WebSocketClient.receiveAction()
    if not lastAction then
        return nil
    end
    
    local action = lastAction
    lastAction = nil  -- Clear after reading
    return action
end

-- Check if connected
function WebSocketClient.isConnected()
    return connected and websocket ~= nil and websocket.IsConnected
end

-- Get last error
function WebSocketClient.getLastError()
    return connectionError
end

-- Disconnect
function WebSocketClient.disconnect()
    if websocket then
        pcall(function()
            websocket:Close()
        end)
        websocket = nil
    end
    connected = false
    print("[RLWebSocket] Disconnected")
end

-- Reconnect with backoff
function WebSocketClient.reconnect(host, port)
    WebSocketClient.disconnect()
    task.wait(RECONNECT_DELAY)
    return WebSocketClient.connect(host, port)
end

-- Helper: Create observation table from game state
function WebSocketClient.createObservation(vehicle, enemy, worldScanner)
    local obs = {
        -- Self state
        position = {vehicle.Position.X, vehicle.Position.Y, vehicle.Position.Z},
        velocity = {vehicle.AssemblyLinearVelocity.X, vehicle.AssemblyLinearVelocity.Y, vehicle.AssemblyLinearVelocity.Z},
        orientation = {vehicle.CFrame:ToOrientation()},
        alive = vehicle.HP.Value > 0,
        
        -- Enemy state (if locked)
        enemy_position = nil,
        enemy_velocity = nil,
        enemy_alive = false,
        enemy_distance = nil,
    }
    
    if enemy and enemy.PrimaryPart then
        local enemyPos = enemy.PrimaryPart.Position
        obs.enemy_position = {enemyPos.X, enemyPos.Y, enemyPos.Z}
        obs.enemy_velocity = {enemy.AssemblyLinearVelocity.X, enemy.AssemblyLinearVelocity.Y, enemy.AssemblyLinearVelocity.Z}
        obs.enemy_alive = true
        obs.enemy_distance = (vehicle.Position - enemyPos).Magnitude
    end
    
    -- Add timestamp for synchronization
    obs.timestamp = tick()
    obs.dt = RunService.RenderStepped:Wait()
    
    return obs
end

return WebSocketClient
