-- WorldScanner.lua
local workspace = game:GetService("Workspace")

local function getModelPosition(name)
    local model = workspace:FindFirstChild(name)
    if model then
        local primary = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")
        if primary then return primary.Position end
    end
    return nil
end

return function(myTeamName)
    print("[WorldScanner] Scanning world for objectives...")
    local found = {}
    local friendlyDockName = (myTeamName == "USA") and "USDock" or "JapanDock"
    local enemyDockName    = (myTeamName == "USA") and "JapanDock" or "USDock"
    local friendlyPos = getModelPosition(friendlyDockName)
    local enemyPos    = getModelPosition(enemyDockName)

    if friendlyPos then found["harbour_friendly"] = friendlyPos end
    if enemyPos then    found["harbour_enemy"]    = enemyPos end

    for _, obj in ipairs(workspace:GetChildren()) do
        if obj.Name ~= "Island" then continue end
        local codeVal = obj:FindFirstChild("IslandCode")
        if not codeVal then continue end
        local primary = obj.PrimaryPart or obj:FindFirstChildWhichIsA("BasePart")
        if not primary then continue end
        local key = "island_" .. tostring(codeVal.Value):lower()
        found[key] = primary.Position
    end
    return found
end
