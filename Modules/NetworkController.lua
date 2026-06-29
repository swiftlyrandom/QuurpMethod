-- NetworkController.lua
local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local player = Players.LocalPlayer
local Config = _G._Modules.VehicleConfig

local REGISTER_URL = Config.REGISTER_URL()
local ACK_URL      = Config.ACK_URL()
local COMMAND_URL  = Config.COMMAND_URL()

local NETWORK_TIMEOUT  = 5
local isFetching = false

local module = {}
module.BOT_ID = nil

function module.register(botId, teamName)
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
    print("[Network] Registered as:", botId)
end

function module.ackTeamChange(botId, newTeam)
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
    print("[Network] Acked team change:", newTeam)
end

-- Walks to team changer and teleporter, then calls onComplete
function module.walkAndChangeTeam(requestedTeam, onComplete)
    local character = player.Character or player.CharacterAdded:Wait()
    local humanoid  = character:WaitForChild("Humanoid")
    if not humanoid or humanoid.Health <= 0 then return end

    local lobby      = workspace:WaitForChild("Lobby", 10)
    if not lobby then warn("[Network] Lobby not found"); return end
    local teamChange = lobby:WaitForChild("TeamChange", 5)
    local teleporter = lobby:WaitForChild("Teleporter", 5)
    if not teamChange or not teleporter then return end

    local targetPart
    if requestedTeam == "USA" then
        targetPart = teamChange:WaitForChild("ToUSA", 5)
    else
        targetPart = teamChange:WaitForChild("ToJapan", 5)
    end
    if not targetPart then return end

    humanoid:MoveTo(targetPart.Position)
    humanoid.MoveToFinished:Wait()
    task.wait(1.5)

    character = player.Character or player.CharacterAdded:Wait()
    humanoid  = character:WaitForChild("Humanoid")
    humanoid:MoveTo(teleporter.Position)
    humanoid.MoveToFinished:Wait()
    task.wait(2)

    if onComplete then onComplete() end
end

-- Returns: success, mode, altitude, objective, team
function module.pollCommands()
    if isFetching or not module.BOT_ID then return false end
    isFetching = true

    local url = string.format("%s?id=%s",
        COMMAND_URL,
        HttpService:UrlEncode(module.BOT_ID)
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

    if not ok or not response or response.StatusCode ~= 200 then
        if not ok then warn("[Network] Request failed:", response) end
        return false
    end

    local ok2, data = pcall(function()
        return HttpService:JSONDecode(response.Body)
    end)
    if not ok2 or not data then return false end

    return true,
           data.mode      or "cruise",
           data.altitude  or 200,
           data.objective,
           data.team
end

return module
