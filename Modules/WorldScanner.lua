-- WorldScanner.lua
local workspace = game:GetService("Workspace")

local WorldScanner = {}

local function getModelPosition(name)
    local model = workspace:FindFirstChild(name)
    if model then
        local primary = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")
        if primary then return primary.Position end
    end
    return nil
end

function WorldScanner.scan(myTeamName)
    print("[WorldScanner] Scanning world for objectives...")
    local found = {}

    local friendlyDockName = (myTeamName == "USA") and "USDock" or "JapanDock"
    local enemyDockName    = (myTeamName == "USA") and "JapanDock" or "USDock"

    local friendlyPos = getModelPosition(friendlyDockName)
    local enemyPos    = getModelPosition(enemyDockName)

    if friendlyPos then
        found["harbour_friendly"] = friendlyPos
        print("[WorldScanner] harbour_friendly:", tostring(friendlyPos))
    else
        warn("[WorldScanner] Could not find friendly harbour:", friendlyDockName)
    end

    if enemyPos then
        found["harbour_enemy"] = enemyPos
        print("[WorldScanner] harbour_enemy:", tostring(enemyPos))
    else
        warn("[WorldScanner] Could not find enemy harbour:", enemyDockName)
    end

    for _, obj in ipairs(workspace:GetChildren()) do
        if obj.Name ~= "Island" then continue end
        local codeVal = obj:FindFirstChild("IslandCode")
        if not codeVal then continue end
        local primary = obj.PrimaryPart or obj:FindFirstChildWhichIsA("BasePart")
        if not primary then continue end
        local key = "island_" .. tostring(codeVal.Value):lower()
        found[key] = primary.Position
        print("[WorldScanner] Mapped", key, "->", tostring(primary.Position))
    end

    return found
end

return WorldScanner
