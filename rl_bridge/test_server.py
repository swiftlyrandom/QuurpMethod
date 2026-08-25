#!/usr/bin/env python3
"""
Simple test server to verify WebSocket connectivity.
Echoes back received messages with a timestamp.
"""

import asyncio
import json
from datetime import datetime
from websockets.server import serve

async def echo_handler(websocket):
    print(f"Test client connected: {websocket.remote_address}")
    
    try:
        async for message in websocket:
            # Parse incoming
            data = json.loads(message)
            print(f"Received: {json.dumps(data, indent=2)}")
            
            # Echo back with timestamp
            response = {
                "received": True,
                "timestamp": datetime.now().isoformat(),
                "original_data": data,
                "test_action": {
                    "pitch": 0.1,
                    "yaw": -0.1,
                    "throttle": 1.0,
                    "fire_guns": 0.0,
                    "drop_bomb": 0.0
                }
            }
            
            await websocket.send(json.dumps(response))
            print(f"Sent response")
            
    except Exception as e:
        print(f"Connection error: {e}")
    finally:
        print(f"Client disconnected")

async def main():
    print("Starting test WebSocket server on port 8765...")
    print("This server echoes back received messages.")
    print("Press Ctrl+C to stop.")
    
    async with serve(echo_handler, "0.0.0.0", 8765):
        await asyncio.Future()

if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        print("\nTest server stopped.")
