"""
TikTok Live -> IKEMEN GO Gift Bridge
Listens for TikTok Live gift events and writes heal/buff commands
to a JSON file that the in-game Lua script reads each frame.

Usage:
    python tiktok_bridge.py
    python tiktok_bridge.py --username otheruser
"""

import json
import os
import sys
import time
import argparse
from datetime import datetime

from TikTokLive import TikTokLiveClient
from TikTokLive.events import GiftEvent, ConnectEvent, DisconnectEvent, ShareEvent

# ============================================================
# Config
# ============================================================
DEFAULT_USERNAME = "pattycake174"
COMMANDS_FILE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "tiktok_commands.json")
LOG_FILE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "tiktok_bridge.log")

# Gift -> Command mapping
# Each gift maps to: command type, value, duration (frames), description
# Common TikTok gift names (case-insensitive matching)
GIFT_MAP = {
    # --- Like: tiny heal both players ---
    "like":                 {"cmd": "heal",    "value": 1,    "duration": 1,    "target": 0, "points": 0,  "desc": "Heal both +1"},

    # --- 1 point: Heal ---
    "rose":                 {"cmd": "heal",    "value": 100,  "duration": 1,    "target": 1, "points": 1,  "desc": "Heal P1"},
    "gg":                   {"cmd": "heal",    "value": 100,  "duration": 1,    "target": 2, "points": 1,  "desc": "Heal P2"},

    # --- 5 points: Buff (all buffs for 10s) ---
    "finger heart":         {"cmd": "all",     "value": 30,   "duration": 600,  "target": 1, "points": 5,  "desc": "Buff P1 10s"},
    "overreact":            {"cmd": "all",     "value": 30,   "duration": 600,  "target": 2, "points": 5,  "desc": "Buff P2 10s"},

    # --- 10 points: God Mode (15s) ---
    "rosa":                 {"cmd": "godmode", "value": 50,   "duration": 900,  "target": 1, "points": 10, "desc": "GOD MODE P1 15s"},
    "friendship necklace":  {"cmd": "godmode", "value": 50,   "duration": 900,  "target": 2, "points": 10, "desc": "GOD MODE P2 15s"},
}

def get_command_for_gift(gift_name, coin_value):
    """Look up the command for a gift by name. Ignores unrecognized gifts."""
    key = gift_name.strip().lower()
    if key in GIFT_MAP:
        return GIFT_MAP[key]
    return None


def write_command(cmd_data, username, gift_name, coin_value, repeat_count):
    """Append a command to the JSON commands file."""
    # Read existing commands
    commands = []
    if os.path.exists(COMMANDS_FILE):
        try:
            with open(COMMANDS_FILE, "r") as f:
                data = json.load(f)
                if isinstance(data, list):
                    commands = data
        except (json.JSONDecodeError, IOError):
            commands = []

    # Scale value by repeat count (streak gifts)
    scaled_value = cmd_data["value"] * max(1, repeat_count)
    scaled_duration = cmd_data["duration"] * max(1, min(repeat_count, 3))

    command = {
        "cmd": cmd_data["cmd"],
        "value": scaled_value,
        "duration": scaled_duration,
        "target": cmd_data.get("target", 1),
        "from": username,
        "gift": gift_name,
        "coins": coin_value,
        "count": repeat_count,
        "timestamp": time.time(),
    }
    commands.append(command)

    # Keep only last 50 commands to prevent file bloat
    commands = commands[-50:]

    try:
        with open(COMMANDS_FILE, "w") as f:
            json.dump(commands, f, indent=2)
    except IOError as e:
        log(f"ERROR writing commands file: {e}")


def log(msg):
    """Log to console and file."""
    timestamp = datetime.now().strftime("%H:%M:%S")
    line = f"[{timestamp}] {msg}"
    print(line)
    try:
        with open(LOG_FILE, "a", encoding="utf-8") as f:
            f.write(line + "\n")
    except IOError:
        pass


def main():
    parser = argparse.ArgumentParser(description="TikTok Live -> IKEMEN GO Bridge")
    parser.add_argument("--username", default=DEFAULT_USERNAME, help="TikTok username")
    args = parser.parse_args()

    # Clear old commands
    try:
        with open(COMMANDS_FILE, "w") as f:
            json.dump([], f)
    except IOError:
        pass

    log("=" * 50)
    log("  TIKTOK LIVE -> IKEMEN GO BRIDGE")
    log("=" * 50)
    log(f"  Connecting to: @{args.username}")
    log(f"  Commands file: {COMMANDS_FILE}")
    log("")

    client = TikTokLiveClient(unique_id=args.username)

    @client.on(ConnectEvent)
    async def on_connect(event: ConnectEvent):
        log(f"Connected to @{args.username}'s live stream!")
        log("Listening for gifts...")
        log("")

    @client.on(DisconnectEvent)
    async def on_disconnect(event: DisconnectEvent):
        log("Disconnected from live stream.")

    @client.on(GiftEvent)
    async def on_gift(event: GiftEvent):
        gift_name = event.gift.name if event.gift else "Unknown"
        coin_value = event.gift.diamond_count if event.gift else 1
        username = event.user.nickname if event.user else "Anonymous"
        repeat_count = event.repeat_count if hasattr(event, "repeat_count") else 1

        # For streak gifts, only process when streak ends
        if hasattr(event, "repeat_end") and not event.repeat_end:
            return

        cmd_data = get_command_for_gift(gift_name, coin_value)
        if cmd_data is None:
            log(f"  GIFT: {username} sent {gift_name} x{repeat_count or 1} ({coin_value} coins) -- IGNORED (not mapped)")
            return

        write_command(cmd_data, username, gift_name, coin_value, repeat_count or 1)

        log(f"  GIFT: {username} sent {gift_name} x{repeat_count or 1} ({coin_value} coins)")
        log(f"  -> {cmd_data['desc']} [{cmd_data['points']}pt] (cmd={cmd_data['cmd']}, val={cmd_data['value']})")
        log("")

    @client.on(ShareEvent)
    async def on_share(event: ShareEvent):
        username = event.user.nickname if event.user else "Anonymous"
        log(f"  SHARE: {username} shared the stream!")
        log(f"  -> HAMMER DROP!")
        log("")

        # Write hammer command directly
        commands = []
        if os.path.exists(COMMANDS_FILE):
            try:
                with open(COMMANDS_FILE, "r") as f:
                    data = json.load(f)
                    if isinstance(data, list):
                        commands = data
            except (json.JSONDecodeError, IOError):
                commands = []

        command = {
            "cmd": "hammer",
            "value": 200,
            "duration": 1,
            "target": 0,
            "from": username,
            "gift": "share",
            "coins": 0,
            "count": 1,
            "timestamp": time.time(),
        }
        commands.append(command)
        commands = commands[-50:]

        try:
            with open(COMMANDS_FILE, "w") as f:
                json.dump(commands, f, indent=2)
        except IOError as e:
            log(f"ERROR writing commands file: {e}")

    try:
        log("Starting TikTok Live listener...")
        client.run()
    except KeyboardInterrupt:
        log("Bridge stopped by user.")
    except Exception as e:
        log(f"ERROR: {e}")
        log("Make sure you are currently LIVE on TikTok!")
        sys.exit(1)


if __name__ == "__main__":
    main()
