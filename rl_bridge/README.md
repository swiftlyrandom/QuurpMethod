# RL Bridge - WebSocket Communication Layer

Connects your Roblox dogfight bot (via Delta executor) to a Python RL bot running on Termux or any server.

## Architecture

```
Roblox Client (Delta Executor) <--WebSocket--> Python Server (Termux/PC)
     |                                              |
     v                                              v
RLWebSocketClient.lua                         server.py
- Sends observations                       - Receives observations
- Receives actions                         - Runs RL policy inference
                                           - Sends actions back
```

## Setup

### 1. Install Python Dependencies

On Termux (Android) or your PC:

```bash
pip install -r requirements.txt
```

Or manually:
```bash
pip install websockets numpy
```

### 2. Configure Network

**Find your Termux/PC IP address:**
- On Termux: `ifconfig` or `ip addr`
- On PC: `ipconfig` (Windows) or `ifconfig` (Linux/Mac)

**Important:** Both Roblox client and Python server must be on the same network, or you need to set up port forwarding.

### 3. Start Python Server

```bash
cd rl_bridge
python server.py --host 0.0.0.0 --port 8765
```

Options:
- `--host`: IP to bind to (use `0.0.0.0` to accept from any interface)
- `--port`: Port number (default: 8765)

### 4. Configure Roblox Side

Edit `Modules/RLWebSocketClient.lua`:
```lua
local DEFAULT_HOST = "192.168.1.100"  -- Your Termux/PC IP
local DEFAULT_PORT = 8765
```

### 5. Enable RL Mode in Bot

In your Roblox executor console:
```lua
local WSClient = require(_G._Modules.RLWebSocketClient)
local MainController = _G._Modules.MainController

-- Connect to Python server
local success, err = WSClient.connect()
if not success then
    warn("Failed to connect:", err)
end

-- Create wrapper policy that uses WebSocket
local WSPolicy = {}
function WSPolicy.selectAction(observation)
    -- Send observation to server
    WSClient.sendObservation(observation)
    
    -- Wait for action (with timeout)
    local startTime = tick()
    while not WSClient.receiveAction() and (tick() - startTime) < 0.5 do
        task.wait(0.01)
    end
    
    local action = WSClient.receiveAction()
    if action then
        return action
    else
        -- Fallback: return zeros if no response
        return {pitch=0, yaw=0, throttle=0, fire_guns=0, drop_bomb=0}
    end
end

-- Enable RL mode
MainController.setRLMode(true)
MainController.setRLPolicy(WSPolicy)
```

## Data Format

### Observation (Roblox → Python)
```json
{
  "position": [x, y, z],
  "velocity": [vx, vy, vz],
  "orientation": [roll, pitch, yaw],
  "alive": true,
  "enemy_position": [x, y, z],
  "enemy_velocity": [vx, vy, vz],
  "enemy_alive": true,
  "enemy_distance": 150.5,
  "timestamp": 1234567.89,
  "dt": 0.016
}
```

### Action (Python → Roblox)
```json
{
  "pitch": 0.5,      // -1.0 to 1.0
  "yaw": -0.3,       // -1.0 to 1.0
  "throttle": 1.0,   // 0 or 1
  "fire_guns": 0.0,  // 0 or 1
  "drop_bomb": 0.0   // 0 or 1
}
```

## Troubleshooting

### Connection Refused
- Check firewall settings on Python server
- Verify IP address is correct
- Ensure both devices are on same network

### Timeout Errors
- Increase `CONNECTION_TIMEOUT` in RLWebSocketClient.lua
- Check network latency

### WebSocket API Issues (Delta Executor)
Delta's WebSocket API may differ slightly. Check documentation for:
- Constructor: `WebSocket.new(url)` vs `WebSocket(url)`
- Connection check: `.IsConnected` vs `.Connected`
- Methods: `:Send()`, `:Receive()`, `:Close()`

## Performance Tips

1. **Run Python server on PC** instead of Termux for faster inference
2. **Use 5GHz WiFi** for lower latency
3. **Reduce observation frequency** if experiencing lag
4. **Batch multiple game ticks** per network request if needed

## Next Steps

1. Replace the heuristic `RLPolicy.select_action()` in `server.py` with your trained model
2. Integrate your physics simulator for validation
3. Add reward tracking and experience logging for online learning
4. Implement connection pooling and automatic reconnection
