import asyncio
import json
from websockets import connect

# SERVER_URL = "ws://192.168.0.218:8080"
SERVER_URL = "ws://167.96.250.233:8080"
commands = [
    {
        "type": "launch",
        "package": "eu.deeper.fishdeeper/eu.deeper.app.splash.SplashActivity",
        "delay": 13,
    },
    {"type": "tap", "x": 70, "y": 140, "delay": 1},
    {"type": "tap", "x": 300, "y": 250, "delay": 2},
]


async def send_command_queue():
    async with connect(SERVER_URL) as websocket:
        for command in commands:
            await websocket.send(json.dumps(command))
            print("Sent:", command)
            await asyncio.sleep(
                command["delay"]
            )  # Delay to allow execution before sending next


if __name__ == "__main__":
    asyncio.run(send_command_queue())
