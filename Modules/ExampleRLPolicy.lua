-- ExampleRLPolicy.lua
-- Simple example RL policy for testing the RL integration
-- Replace this with your actual trained model

local ExampleRLPolicy = {}

-- Action space:
-- { pitch, yaw, throttle, fireGuns, dropBomb }
-- pitch: -1 to 1 (nose up/down)
-- yaw: -1 to 1 (nose left/right)
-- throttle: 0 or 1 (stop or full speed)
-- fireGuns: 0 or 1
-- dropBomb: 0 or 1

-- Select action based on observation
-- observation: table from MainController.getObservation()
-- dt: delta time
function ExampleRLPolicy.selectAction(observation, dt)
    if not observation then
        return {
            pitch = 0,
            yaw = 0,
            throttle = 1,
            fireGuns = 0,
            dropBomb = 0,
        }
    end
    
    -- Simple heuristic placeholder
    -- Replace with actual neural network inference
    local action = {
        pitch = 0,
        yaw = 0,
        throttle = 1,  -- Always moving
        fireGuns = 0,
        dropBomb = 0,
    }
    
    -- If enemy is locked, try to point at them
    if observation.enemyLocked and observation.enemyRelativePos then
        local relPos = observation.enemyRelativePos
        
        -- Calculate desired pitch/yaw to face enemy
        -- This is a simple proportional controller
        local lookVector = observation.orientation.LookVector
        local rightVector = observation.orientation.RightVector
        local upVector = observation.orientation.UpVector
        
        -- Project enemy position onto local axes
        local forwardDot = lookVector:Dot(relPos.Unit)
        local rightDot = rightVector:Dot(relPos.Unit)
        local upDot = upVector:Dot(relPos.Unit)
        
        -- Turn towards enemy (proportional control)
        action.yaw = math.clamp(rightDot * 2, -1, 1)
        action.pitch = math.clamp(-upDot * 2, -1, 1)
        
        -- Fire if pointing roughly at enemy
        if forwardDot > 0.95 then
            action.fireGuns = 1
        end
    else
        -- No enemy: fly straight with slight adjustments
        action.pitch = 0.1  -- Slight climb
        action.yaw = 0
    end
    
    -- Altitude control: maintain preferred altitude
    local currentAlt = observation.altitude
    local preferredAlt = 350
    if currentAlt < preferredAlt - 50 then
        action.pitch = math.max(action.pitch, 0.3)  -- Climb
    elseif currentAlt > preferredAlt + 50 then
        action.pitch = math.min(action.pitch, -0.2)  -- Descend
    end
    
    -- Safety: pull up if too low
    if currentAlt < 100 then
        action.pitch = 0.5  -- Emergency climb
    end
    
    return action
end

return ExampleRLPolicy
