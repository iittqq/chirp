import asyncio
import subprocess
import json
import random
from websockets import connect, ConnectionClosed

SERVER_URL = (
    "wss://ywh1uzhhk9.execute-api.us-east-2.amazonaws.com/test?deviceId=testAndroid"
)


def run_as_root(command: str):
    process = subprocess.Popen(
        ["su"],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    stdout, stderr = process.communicate(command + "\n")
    print("stdout:", stdout.strip())
    print("stderr:", stderr.strip())


async def handle_command(command):
    try:
        data = json.loads(command)

        if data.get("message") in ("Forbidden", "forbidden"):
            return

        if isinstance(data.get("body"), str):
            try:
                data = json.loads(data["body"])
            except json.JSONDecodeError:
                pass

        cmd_type = data.get("action") or data.get("type")

        if cmd_type == "tap":
            x, y = data.get("x"), data.get("y")
            if x is not None and y is not None:
                run_as_root(f"input tap {x} {y}")
                print(f"Executed: tap {x} {y}")

        elif cmd_type == "swipe":
            x1, y1, x2, y2 = (
                data.get("x1"),
                data.get("y1"),
                data.get("x2"),
                data.get("y2"),
            )
            duration = data.get("duration", 300)
            run_as_root(f"input swipe {x1} {y1} {x2} {y2} {duration}")
            print(f"Executed: swipe from ({x1},{y1}) to ({x2},{y2})")

        elif cmd_type == "launch":
            package = data.get("package")
            if package:
                run_as_root(f"am start -n {package}")
                print(f"Launched package: {package}")

        elif cmd_type == "restart":
            package = data.get("package") or "eu.deeper.fishdeeper"
            activity = data.get("activity") or "eu.deeper.app.splash.SplashActivity"
            run_as_root(f"am force-stop {package}")
            await asyncio.sleep(1.0)
            run_as_root(f"am start -n {package}/{activity}")
            print(f"Restarted: {package}/{activity}")

        elif cmd_type == "ping":
            # no-op
            pass
        else:
            print("Unknown command type:", cmd_type)

    except json.JSONDecodeError:
        print("Invalid JSON:", command)
    except Exception as e:
        print("Error:", e)


async def listen():
    async with connect(
        SERVER_URL,
        ping_interval=30,
        ping_timeout=30,
        close_timeout=5,
        max_size=2**20,
    ) as ws:
        print("Connected:", SERVER_URL)

        async def heartbeats(interval=90):
            try:
                while True:
                    await ws.send(json.dumps({"action": "ping"}))
                    await asyncio.sleep(interval)
            except asyncio.CancelledError:
                return

        async def receiver():
            while True:
                msg = await ws.recv()
                print("Raw message:", msg)
                await handle_command(msg)

        hb = asyncio.create_task(heartbeats())
        try:
            await receiver()
        finally:
            hb.cancel()
            with contextlib.suppress(Exception):
                await hb


async def persistent_listener():
    backoff = 1
    while True:
        try:
            await listen()
            backoff = 1
        except ConnectionClosed as cc:
            print(f"Closed: code={cc.code} reason={cc.reason}")
        except Exception as e:
            print(f"Disconnected: {e}")
        sleep_for = min(backoff * 2, 30) + random.uniform(0, 0.5)
        await asyncio.sleep(sleep_for)
        backoff = min(backoff * 2, 30)


if __name__ == "__main__":
    import contextlib

    asyncio.run(persistent_listener())
