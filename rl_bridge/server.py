"""
WebSocket server for RL bot communication.
Runs on Termux (Android) or any Python environment.
Receives observations from Roblox, runs inference, sends back actions.
"""

import asyncio
import json
import numpy as np
from websockets.server import serve
from typing import Optional, Dict, Any

# Import your existing physics simulation
try:
    from plane.step import step as physics_step
    from plane.state import PlaneState
    PHYSICS_AVAILABLE = True
except ImportError:
    PHYSICS_AVAILABLE = False
    print("Warning: Physics module not found. Running in passthrough mode.")

# Replace this with your actual trained model
class RLPolicy:
    def __init__(self):
        self.model = None  # Load your PyTorch/TensorFlow model here
        
    def select_action(self, observation: Dict[str, Any]) -> Dict[str, float]:
        """
        Select action based on observation.
        Returns dict with: pitch, yaw, throttle, fire_guns, drop_bomb
        """
        # TODO: Replace with actual model inference
        # For now, return a simple heuristic action
        
        # Example: extract features from observation
        self_pos = np.array(observation.get('position', [0, 200, 0]))
        self_vel = np.array(observation.get('velocity', [0, 0, 0]))
        enemy_pos = np.array(observation.get('enemy_position', [0, 200, 100]))
        
        # Simple proportional controller for demonstration
        if enemy_pos is not None:
            to_enemy = enemy_pos - self_pos
            to_enemy[1] = 0  # Ignore vertical component for yaw
            norm = np.linalg.norm(to_enemy)
            if norm > 0.1:
                desired_heading = to_enemy / norm
                # Calculate pitch/yaw errors (simplified)
                pitch_error = np.arctan2(to_enemy[1], norm) * 0.5
                yaw_error = np.arctan2(to_enemy[0], to_enemy[2]) * 0.3
            else:
                pitch_error = 0.0
                yaw_error = 0.0
        else:
            pitch_error = 0.0
            yaw_error = 0.0
            
        # Clip to valid range [-1, 1]
        pitch = float(np.clip(pitch_error, -1.0, 1.0))
        yaw = float(np.clip(yaw_error, -1.0, 1.0))
        
        # Throttle: full speed if enemy exists and alive
        throttle = 1.0 if observation.get('enemy_alive', False) else 0.0
        
        # Weapons: fire if aligned (simplified logic)
        fire_guns = 1.0 if abs(pitch) < 0.3 and abs(yaw) < 0.3 and observation.get('enemy_alive', False) else 0.0
        drop_bomb = 0.0  # Only drop bombs in specific situations
        
        return {
            'pitch': pitch,
            'yaw': yaw,
            'throttle': throttle,
            'fire_guns': fire_guns,
            'drop_bomb': drop_bomb
        }


class RLBridge:
    def __init__(self):
        self.policy = RLPolicy()
        self.sim_state: Optional[PlaneState] = None
        self.last_observation: Optional[Dict[str, Any]] = None
        
    async def handle_client(self, websocket):
        """Handle a single WebSocket connection from Roblox."""
        print(f"Client connected: {websocket.remote_address}")
        
        try:
            async for message in websocket:
                try:
                    # Parse incoming observation
                    observation = json.loads(message)
                    self.last_observation = observation
                    
                    # Run policy inference
                    action = self.policy.select_action(observation)
                    
                    # Optionally run physics simulation for validation
                    if PHYSICS_AVAILABLE and self.sim_state is not None:
                        # Update sim state with observation (for validation)
                        self._sync_sim_state(observation)
                        
                        # Step simulation with action
                        desired_heading = self._action_to_heading(action['pitch'], action['yaw'])
                        physics_step(
                            self.sim_state,
                            dt=observation.get('dt', 0.016),
                            desired_heading=desired_heading
                        )
                    
                    # Send action back to Roblox
                    response = json.dumps(action)
                    await websocket.send(response)
                    
                except json.JSONDecodeError as e:
                    print(f"Invalid JSON: {e}")
                    await websocket.send(json.dumps({'error': 'Invalid JSON'}))
                except Exception as e:
                    print(f"Error processing message: {e}")
                    await websocket.send(json.dumps({'error': str(e)}))
                    
        except Exception as e:
            print(f"Connection error: {e}")
        finally:
            print(f"Client disconnected: {websocket.remote_address}")
    
    def _sync_sim_state(self, observation: Dict[str, Any]):
        """Sync simulation state with latest observation (for validation)."""
        if self.sim_state is None:
            self.sim_state = PlaneState()
            
        self.sim_state.position = np.array(observation.get('position', [0, 200, 0]))
        self.sim_state.velocity = np.array(observation.get('velocity', [0, 0, 0]))
        # heading would need to be reconstructed from orientation
        self.sim_state.alive = observation.get('alive', True)
        
    def _action_to_heading(self, pitch: float, yaw: float) -> np.ndarray:
        """Convert pitch/yaw controls to desired heading vector."""
        x = np.cos(pitch) * np.cos(yaw)
        z = np.cos(pitch) * np.sin(yaw)
        y = np.sin(pitch)
        return np.array([x, y, z])


async def main(host: str = "0.0.0.0", port: int = 8765):
    """Start the WebSocket server."""
    bridge = RLBridge()
    
    print(f"Starting RL Bridge WebSocket server on {host}:{port}")
    print("Waiting for Roblox client connection...")
    
    async with serve(bridge.handle_client, host, port):
        await asyncio.Future()  # Run forever


if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser(description="RL Bridge WebSocket Server")
    parser.add_argument("--host", default="0.0.0.0", help="Host to bind to")
    parser.add_argument("--port", type=int, default=8765, help="Port to listen on")
    args = parser.parse_args()
    
    try:
        asyncio.run(main(args.host, args.port))
    except KeyboardInterrupt:
        print("\nServer stopped.")
