-- AutoStart.lua
-- Automatically connects to RL WebSocket server when character spawns
-- Place this in _G._Modules and require it from BotLoader or a LocalScript

local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")

if not HttpService.HttpEnabled then
    warn("⚠️ HTTP Service not enabled! Enable 'HTTP Requests' in Game Settings > Security")
end

-- Configuration - CHANGE THIS TO YOUR PC'S IP
local SERVER_IP = "192.168.1.100"  -- Replace with your actual PC IP
local SERVER_PORT = 8765
local MAX_RETRIES = 5
local RETRY_DELAY = 1.0

local WSClient = nil
local MainController = nil

local function getModules()
    if not WSClient then
        WSClient = require(_G._Modules.RLWebSocketClient)
    end
    if not MainController then
        MainController = require(_G._Modules.MainController)
    end
    return WSClient, MainController
end

local function connectWithRetry()
    local ws, mc = getModules()
    local url = string.format("ws://%s:%d", SERVER_IP, SERVER_PORT)
    
    print("🚀 RL AutoStart: Attempting to connect to", url)
    
    for attempt = 1, MAX_RETRIES do
        print(string.format("🔌 Connection attempt (%d/%d)...", attempt, MAX_RETRIES))
        
        local success, err = pcall(function()
            ws.connect(url)
        end)
        
        -- Give it a moment to establish
        task.wait(0.5)
        
        if success and ws.isConnected() then
            print("✅ Connected to RL server!")
            
            -- Create WebSocket-backed policy
            local WSPolicy = {}
            function WSPolicy.selectAction(obs)
                if not ws.isConnected() then
                    -- Fallback to zeros if disconnected
                    return {pitch=0, yaw=0, throttle=0, fire_guns=0, drop_bomb=0}
                end
                
                ws.sendObservation(obs)
                task.wait(0.03)  -- Small delay for response
                
                local action = ws.receiveAction()
                if action then
                    return action
                else
                    -- Timeout or error, return safe defaults
                    return {pitch=0, yaw=0, throttle=0, fire_guns=0, drop_bomb=0}
                end
            end
            
            -- Activate RL mode
            mc.setRLMode(true)
            mc.setRLPolicy(WSPolicy)
            print("🤖 RL Mode activated with WebSocket policy")
            return true
        end
        
        warn("❌ Connection failed:", err or "unknown error")
        if attempt < MAX_RETRIES then
            print("⏳ Retrying in", RETRY_DELAY, "seconds...")
            task.wait(RETRY_DELAY)
        end
    end
    
    warn("⚠️ Failed to connect after", MAX_RETRIES, "attempts.")
    warn("⚠️ Running in heuristic mode instead.")
    
    -- Ensure we're in heuristic mode
    mc.setRLMode(false)
    return false
end

-- Connect when character spawns
local function onCharacterAdded(character)
    -- Wait a bit for modules to fully load
    task.delay(2.0, connectWithRetry)
end

-- Hook into CharacterAdded
game.Players.LocalPlayer.CharacterAdded:Connect(onCharacterAdded)

-- Also try immediately if character already exists
if game.Players.LocalPlayer.Character then
    onCharacterAdded(game.Players.LocalPlayer.Character)
end

print("🎯 RL AutoStart initialized. Will connect when character spawns.")
print("   Server:", SERVER_IP .. ":" .. SERVER_PORT)
print("   To change IP, edit Modules/AutoStart.lua")

return {
    connectNow = connectWithRetry,
    setServerIP = function(ip) SERVER_IP = ip end,
    setServerPort = function(port) SERVER_PORT = port end,
}
