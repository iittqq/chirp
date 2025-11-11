# Requires: pip install uiautomator2 opencv-python numpy pillow
import uiautomator2 as u2
import time
import cv2
import numpy as np
from PIL import Image

DEVICE_IP = "192.168.1.42"  # or adb serial / "usb" to auto connect
APP_PACKAGE = "com.fishdeeper.app"  # example package; replace
APP_ACTIVITY = ".MainActivity"  # if needed

# Known popup buttons/texts to try automatically (ordered)
POPUP_ACCEPT_TEXTS = ["OK", "Allow", "Update", "Install", "Yes"]
POPUP_DISMISS_TEXTS = [
    "No thanks",
    "Not now",
    "Later",
    "Cancel",
    "Close",
    "Maybe later",
]

# Connect to device
d = u2.connect(DEVICE_IP)  # or u2.connect_usb() / u2.connect()
d.app_start(APP_PACKAGE)  # start app


def wait_for(selector_fn, timeout=15, poll=0.5):
    """Wait until selector_fn() returns truthy; returns its value or None."""
    end = time.time() + timeout
    while time.time() < end:
        val = selector_fn()
        if val:
            return val
        # also check for popups each poll
        handle_known_popups()
        time.sleep(poll)
    return None


def handle_known_popups():
    # 1) try text-based matches
    for t in POPUP_DISMISS_TEXTS + POPUP_ACCEPT_TEXTS:
        e = d(text=t)
        if e.exists:
            try:
                e.click()
                print(f"Clicked popup button with text: {t}")
                time.sleep(0.3)
                return True
            except Exception:
                pass
    # 2) try resource-id known popups (example ids)
    known_ids = [
        "com.android.packageinstaller:id/permission_deny_button",
        "com.android.packageinstaller:id/permission_allow_button",
    ]
    for rid in known_ids:
        e = d(resourceId=rid)
        if e.exists:
            try:
                e.click()
                print(f"Clicked popup resource: {rid}")
                return True
            except Exception:
                pass
    return False


# Example: navigate to sonar connect button
def click_connect():
    # primary: wait for UI element by text or resourceId
    btn = wait_for(
        lambda: d(text="Connect").until(1) if d(text="Connect").exists else None,
        timeout=20,
    )
    if btn:
        print("Found Connect by text - clicking")
        d(text="Connect").click()
        return True

    # fallback: try resource-id
    btn2 = wait_for(
        lambda: d(resourceId="com.fishdeeper:id/btn_connect").exists
        and d(resourceId="com.fishdeeper:id/btn_connect"),
        timeout=10,
    )
    if btn2:
        d(resourceId="com.fishdeeper:id/btn_connect").click()
        return True

    # image-based fallback (load template image)
    try:
        screen = d.screenshot(format="opencv")
        template = cv2.imread("templates/connect_button.png", cv2.IMREAD_COLOR)
        res = cv2.matchTemplate(screen, template, cv2.TM_CCOEFF_NORMED)
        minv, maxv, minloc, maxloc = cv2.minMaxLoc(res)
        if maxv > 0.8:
            th, tw = template.shape[:2]
            x = maxloc[0] + tw // 2
            y = maxloc[1] + th // 2
            d.tap(x, y)
            print("Tapped image-matched Connect button")
            return True
    except Exception as e:
        print("Image fallback failed:", e)

    print("Unable to find Connect button")
    return False


# Usage
if click_connect():
    print("Clicked connect - now wait for connection state")
    connected = wait_for(lambda: d(textContains="Connected").exists, timeout=30)
    if connected:
        print("Device shows connected!")
    else:
        print("Connection not detected.")
else:
    print("Could not press connect.")
