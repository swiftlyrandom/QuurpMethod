-- PredictionUtils.lua – shared prediction math for RPG & gunner
local PredictionUtils = {}

function PredictionUtils.solveQuadratic(a, b, c)
    local d = b*b - 4*a*c
    if d < 0 then return nil end
    local sqrtD = math.sqrt(d)
    local t1 = (-b - sqrtD) / (2*a)
    local t2 = (-b + sqrtD) / (2*a)
    return (t1 > 0 and t1) or (t2 > 0 and t2) or nil
end

function PredictionUtils.getAimPosition(gunPos, targetPos, targetVel, bulletSpeed)
    local dp = targetPos - gunPos
    local a = targetVel:Dot(targetVel) - bulletSpeed*bulletSpeed
    local b = 2 * dp:Dot(targetVel)
    local c = dp:Dot(dp)
    local t = PredictionUtils.solveQuadratic(a, b, c)
    if not t then return nil end
    return targetPos + targetVel * t   -- no acceleration term
end

return PredictionUtils
