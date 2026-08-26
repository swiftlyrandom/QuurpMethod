# rl_bridge/server.py - HTTP Version for Delta
"""
HTTP Bridge for RL bot communication.
Runs on Termux (Android) or any Python environment.
Receives observations from Roblox via HTTP POST, runs inference, sends back actions via HTTP GET.
"""

from http.server import HTTPServer, BaseHTTPRequestHandler
import json
import threading
from queue import Queue, Empty
import time
import numpy as np
from typing import Dict, Any, Optional

# Import your existing physics simulation if needed
try:
    from plane.step import step as physics_step
    from plane.state import PlaneState
    PHYSICS_AVAILABLE = True
except ImportError:
    PHYSICS_AVAILABLE = False
    print("Warning: Physics module not found. Running in passthrough mode.")

# --- Your RL Policy ---
class RLPolicy:
    def __init__(self):
        self.model = None  # Load your PyTorch/TensorFlow model here
        
    def select_action(self, observation: Dict[str, Any]) -> Dict[str, float]:
        """
        Select action based on observation.
        Returns dict with: pitch, yaw, throttle, fire_guns, drop_bomb
        """
        # TODO: Replace with actual model inference
        
        # Simple heuristic for demonstration
        self_pos = np.array(observation.get('position', [0, 200, 0]))
        self_vel = np.array(observation.get('velocity', [0, 0, 0]))
        
        # Try to get enemy position from observation
        enemy_pos = observation.get('enemy_position')
        if enemy_pos is None:
            # Try alternative field names
            enemy_pos = observation.get('enemyRelativePos')
            if enemy_pos is not None:
                # enemyRelativePos is relative, convert to absolute
                enemy_pos = self_pos + np.array(enemy_pos)
        
        if enemy_pos is not None:
            to_enemy = np.array(enemy_pos) - self_pos
            horizontal_dist = np.linalg.norm(to_enemy[[0, 2]])
            
            if horizontal_dist > 0.1:
                # Yaw: turn toward enemy horizontally
                yaw_error = np.arctan2(to_enemy[0], to_enemy[2])
                # Pitch: aim up/down
                pitch_error = np.arctan2(to_enemy[1], horizontal_dist)
                
                # Clamp to [-1, 1]
                pitch = float(np.clip(pitch_error * 0.5, -1.0, 1.0))
                yaw = float(np.clip(yaw_error * 0.3, -1.0, 1.0))
            else:
                pitch, yaw = 0.0, 0.0
        else:
            pitch, yaw = 0.0, 0.0
        
        # Throttle: full if enemy exists
        enemy_locked = observation.get('enemyLocked', False)
        throttle = 1.0 if enemy_locked else 0.0
        
        # Fire guns if aligned and enemy locked
        fire_guns = 1.0 if (enemy_locked and abs(pitch) < 0.3 and abs(yaw) < 0.3) else 0.0
        drop_bomb = 0.0
        
        return {
            'pitch': pitch,
            'yaw': yaw,
            'throttle': throttle,
            'fire_guns': fire_guns,
            'drop_bomb': drop_bomb
        }


# --- HTTP Handler ---
class RLHandler(BaseHTTPRequestHandler):
    """Handles HTTP requests from Roblox client."""
    
    # Shared state across all connections
    policy = RLPolicy()
    action_queue = Queue(maxsize=1)  # Only keep latest action
    last_action = {'pitch': 0, 'yaw': 0, 'throttle': 0, 'fire_guns': 0, 'drop_bomb': 0}
    last_observation = None
    sim_state = None
    
    def log_message(self, format, *args):
        """Suppress verbose logging."""
        pass
    
    def do_GET(self):
        """Handle GET requests."""
        if self.path == "/ping":
            self._send_json({'status': 'ok', 'timestamp': time.time()})
            return
        
        if self.path == "/action":
            # Return the latest action immediately (non-blocking)
            try:
                action = self.action_queue.get_nowait()
                self.last_action = action
            except Empty:
                pass  # Use last action
            
            self._send_json(self.last_action)
            return
        
        if self.path == "/health":
            self._send_json({
                'status': 'ok',
                'connected': True,
                'queue_size': self.action_queue.qsize(),
                'last_observation': self.last_observation is not None
            })
            return
        
        self._send_error(404, "Not found")
    
    def do_POST(self):
        """Handle POST requests."""
        if self.path == "/action":
            content_length = int(self.headers.get('Content-Length', 0))
            if content_length == 0:
                self._send_error(400, "Empty body")
                return
            
            post_data = self.rfile.read(content_length)
            
            try:
                # Parse observation
                data = json.loads(post_data.decode('utf-8'))
                observation = data.get('observation', data)  # Handle wrapped format
                
                self.last_observation = observation
                
                # Run policy inference
                action = self.policy.select_action(observation)
                
                # Optionally sync physics simulation
                if PHYSICS_AVAILABLE:
                    self._sync_sim_state(observation)
                
                # Store action for polling
                try:
                    self.action_queue.put_nowait(action)
                except:
                    # Queue full, replace
                    try:
                        self.action_queue.get_nowait()
                        self.action_queue.put_nowait(action)
                    except:
                        pass
                
                self.last_action = action
                self._send_json(action)
                
            except json.JSONDecodeError as e:
                self._send_error(400, f"Invalid JSON: {e}")
            except Exception as e:
                self._send_error(500, str(e))
            return
        
        self._send_error(404, "Not found")
    
    def _send_json(self, data):
        """Send JSON response with CORS headers."""
        self.send_response(200)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Access-Control-Allow-Methods', 'GET, POST, OPTIONS')
        self.send_header('Access-Control-Allow-Headers', 'Content-Type')
        self.end_headers()
        
        try:
            self.wfile.write(json.dumps(data).encode('utf-8'))
        except:
            pass
    
    def _send_error(self, code, message):
        """Send error response."""
        self.send_response(code)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Access-Control-Allow-Origin', '*')
        self.end_headers()
        self.wfile.write(json.dumps({'error': message}).encode('utf-8'))
    
    def _sync_sim_state(self, observation):
        """Sync simulation state with observation."""
        if self.sim_state is None:
            self.sim_state = PlaneState()
        
        try:
            pos = observation.get('position', [0, 200, 0])
            vel = observation.get('velocity', [0, 0, 0])
            self.sim_state.position = np.array(pos)
            self.sim_state.velocity = np.array(vel)
            self.sim_state.alive = observation.get('alive', True)
        except:
            pass


# --- Server ---
class RLBridgeServer:
    def __init__(self, host='0.0.0.0', port=8765):
        self.host = host
        self.port = port
        self.server = None
        
    def start(self):
        """Start the HTTP server."""
        print(f"🚀 Starting RL Bridge HTTP Server on {self.host}:{self.port}")
        print(f"📍 Use these URLs in Roblox:")
        print(f"   Ping: http://{self.host}:{self.port}/ping")
        print(f"   Action: http://{self.host}:{self.port}/action")
        print(f"   Send observation: POST to http://{self.host}:{self.port}/action")
        print()
        print("📡 Waiting for Roblox client...")
        
        self.server = HTTPServer((self.host, self.port), RLHandler)
        try:
            self.server.serve_forever()
        except KeyboardInterrupt:
            self.stop()
    
    def stop(self):
        """Stop the server."""
        if self.server:
            self.server.shutdown()
            print("🛑 Server stopped")


# --- Main Entry Point ---
if __name__ == "__main__":
    import argparse
    
    parser = argparse.ArgumentParser(description="RL Bridge HTTP Server")
    parser.add_argument("--host", default="0.0.0.0", help="Host to bind to")
    parser.add_argument("--port", type=int, default=8765, help="Port to listen on")
    args = parser.parse_args()
    
    # Try to import physics
    try:
        from plane.step import step as physics_step
        from plane.state import PlaneState
        PHYSICS_AVAILABLE = True
        print("✅ Physics module loaded")
    except ImportError:
        print("⚠️ Physics module not available - running in passthrough mode")
    
    server = RLBridgeServer(args.host, args.port)
    server.start()
