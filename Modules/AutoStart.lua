-- AutoStart.lua - HTTP Version
local HttpService = game:GetService("HttpService")

local SERVER_URL = "http://127.0.0.1:8765"
local MainController = nil
local connected = false
local action = nil
local running = false

local function poll()
    while running do
        local success, response = pcall(function()
            return HttpService:GetAsync(SERVER_URL .. "/poll")
        end)
        
        if success and response and response ~= "" then
            local success2, data = pcall(function()
                return HttpService:JSONDecode(response)
            end)
            if success2 then
                action = data
            end
        end
        
        task.wait(0.05)  -- 50ms poll rate
    end
end

local function startPolling()
    if running then return end
    running = true
    task.spawn(poll)
end

local function connect()
    MainController = _G._Modules.MainController
    
    -- Test connection
    local success, response = pcall(function()
        return HttpService:GetAsync(SERVER_URL .. "/ping")
    end)
    
    if success then
        print("✅ Connected to RL server via HTTP")
        startPolling()
        
        local WSPolicy = {}
        function WSPolicy.selectAction(obs)
            -- Send observation and get action
            local json = HttpService:JSONEncode({
                observation = obs,
                timestamp = tick()
            })
            
            local success, response = pcall(function()
                return HttpService:PostAsync(SERVER_URL .. "/action", json, Enum.HttpContentType.ApplicationJson)
            end)
            
            if success then
                local actionData = HttpService:JSONDecode(response)
                return actionData
            end
            
            -- Fallback
            return {pitch=0, yaw=0, throttle=0, fire_guns=0, drop_bomb=0}
        end
        
        MainController.setRLMode(true)
        MainController.setRLPolicy(WSPolicy)
        return true
    else
        warn("⚠️ Failed to connect to RL server")
        return false
    end
end

-- Auto-start
game.Players.LocalPlayer.CharacterAdded:Connect(function()
    task.wait(2)
    connect()
end)

return { connectNow = connect }
