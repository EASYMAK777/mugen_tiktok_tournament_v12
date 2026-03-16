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
from TikTokLive.events import GiftEvent, ConnectEvent, DisconnectEvent

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
    # --- Small gifts (1-10 coins) ---
    # target: 1 = Player 1, 2 = Player 2
    "rose":             {"cmd": "heal",      "value": 50,   "duration": 1,   "target": 1, "desc": "Heal P1"},
    "ice cream cone":   {"cmd": "power",     "value": 500,  "duration": 1,   "target": 1, "desc": "Power boost P1"},
    "gg":               {"cmd": "attack",    "value": 15,   "duration": 300, "target": 1, "desc": "Attack buff P1 5s"},
    "like":             {"cmd": "heal",      "value": 50,   "duration": 1,   "target": 2, "desc": "Heal P2"},
    "finger heart":     {"cmd": "defense",   "value": 15,   "duration": 300, "target": 2, "desc": "Defense buff P2 5s"},
    "tiktok":           {"cmd": "speed",     "value": 10,   "duration": 300, "target": 1, "desc": "Speed buff P1 5s"},
    "heart me":         {"cmd": "heal",      "value": 75,   "duration": 1,   "target": 1, "desc": "Small heal P1"},
    "doughnut":         {"cmd": "power",     "value": 800,  "duration": 1,   "target": 2, "desc": "Power boost P2"},
    "cap":              {"cmd": "attack",    "value": 10,   "duration": 180, "target": 2, "desc": "Attack buff P2 3s"},

    # --- Medium gifts (10-100 coins) ---
    "perfume":          {"cmd": "heal",      "value": 150,  "duration": 1,   "target": 1, "desc": "Medium heal P1"},
    "hand heart":       {"cmd": "defense",   "value": 25,   "duration": 600, "target": 1, "desc": "Defense buff P1 10s"},
    "love you":         {"cmd": "heal",      "value": 200,  "duration": 1,   "target": 2, "desc": "Medium heal P2"},
    "sunglasses":       {"cmd": "attack",    "value": 25,   "duration": 600, "target": 1, "desc": "Attack buff P1 10s"},
    "cheer you on":     {"cmd": "power",     "value": 1500, "duration": 1,   "target": 1, "desc": "Big power boost P1"},
    "disco ball":       {"cmd": "speed",     "value": 20,   "duration": 600, "target": 2, "desc": "Speed buff P2 10s"},
    "birthday cake":    {"cmd": "heal",      "value": 250,  "duration": 1,   "target": 2, "desc": "Large heal P2"},
    "gamepad":          {"cmd": "attack",    "value": 30,   "duration": 600, "target": 2, "desc": "Strong attack buff P2"},

    # --- Large gifts (100-1000 coins) ---
    "drama queen":      {"cmd": "heal",      "value": 400,  "duration": 1,   "target": 1, "desc": "Big heal P1"},
    "money gun":        {"cmd": "power",     "value": 3000, "duration": 1,   "target": 1, "desc": "Max power P1"},
    "garland":          {"cmd": "defense",   "value": 40,   "duration": 900, "target": 2, "desc": "Defense buff P2 15s"},
    "hat and mustache": {"cmd": "attack",    "value": 40,   "duration": 900, "target": 1, "desc": "Attack buff P1 15s"},
    "train":            {"cmd": "all",       "value": 25,   "duration": 600, "target": 1, "desc": "All buffs P1 10s"},
    "family":           {"cmd": "heal",      "value": 500,  "duration": 1,   "target": 2, "desc": "Huge heal P2"},

    # --- Premium gifts (1000+ coins) ---
    "lion":             {"cmd": "godmode",   "value": 50,   "duration": 900, "target": 1, "desc": "GOD MODE P1 15s"},
    "universe":         {"cmd": "godmode",   "value": 60,   "duration": 1200,"target": 1, "desc": "GOD MODE P1 20s"},
    "rocket":           {"cmd": "all",       "value": 50,   "duration": 900, "target": 2, "desc": "All max buffs P2 15s"},
    "interstellar":     {"cmd": "godmode",   "value": 75,   "duration": 1800,"target": 2, "desc": "GOD MODE P2 30s"},
    "planet":           {"cmd": "heal_full", "value": 999,  "duration": 1,   "target": 1, "desc": "FULL HEAL P1"},
}

# Fallback: map by coin value if gift name not recognized (defaults to P1)
COIN_THRESHOLDS = [
    (1,    {"cmd": "heal",      "value": 30,   "duration": 1,   "target": 1, "desc": "Tiny heal P1"}),
    (5,    {"cmd": "heal",      "value": 75,   "duration": 1,   "target": 1, "desc": "Small heal P1"}),
    (10,   {"cmd": "attack",    "value": 15,   "duration": 300, "target": 1, "desc": "Attack buff P1"}),
    (50,   {"cmd": "heal",      "value": 200,  "duration": 1,   "target": 1, "desc": "Medium heal P1"}),
    (100,  {"cmd": "defense",   "value": 30,   "duration": 600, "target": 1, "desc": "Defense buff P1"}),
    (500,  {"cmd": "all",       "value": 25,   "duration": 600, "target": 1, "desc": "All buffs P1"}),
    (1000, {"cmd": "heal",      "value": 500,  "duration": 1,   "target": 1, "desc": "Big heal P1"}),
    (5000, {"cmd": "godmode",   "value": 50,   "duration": 900, "target": 1, "desc": "GOD MODE P1"}),
]


def get_command_for_gift(gift_name, coin_value):
    """Look up the command for a gift by name, falling back to coin value."""
    key = gift_name.strip().lower()
    if key in GIFT_MAP:
        return GIFT_MAP[key]

    # Fallback by coin value
    result = COIN_THRESHOLDS[0][1]
    for threshold, cmd in COIN_THRESHOLDS:
        if coin_value >= threshold:
            result = cmd
    return result


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
        write_command(cmd_data, username, gift_name, coin_value, repeat_count or 1)

        log(f"  GIFT: {username} sent {gift_name} x{repeat_count or 1} ({coin_value} coins)")
        log(f"  -> {cmd_data['desc']} (cmd={cmd_data['cmd']}, val={cmd_data['value']})")
        log("")

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
