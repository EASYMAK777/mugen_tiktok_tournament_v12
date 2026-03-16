"""
Offline TikTok Gift Tester for IKEMEN GO
Simulates gift commands without needing a live TikTok stream.
Run this while IkemenGO is open with a fight in progress.

Usage:
    python tiktok_test.py
"""

import json
import os
import time

COMMANDS_FILE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "tiktok_commands.json")

# Quick-pick gifts for testing
GIFTS = {
    "1": {"cmd": "heal",    "value": 1,   "duration": 1,   "target": 0, "label": "Like - Heal Both +1"},
    "2": {"cmd": "heal",    "value": 100, "duration": 1,   "target": 1, "label": "Rose - Heal P1 (1pt)"},
    "3": {"cmd": "heal",    "value": 100, "duration": 1,   "target": 2, "label": "GG - Heal P2 (1pt)"},
    "4": {"cmd": "all",     "value": 30,  "duration": 600, "target": 1, "label": "Finger Heart - Buff P1 (5pt)"},
    "5": {"cmd": "all",     "value": 30,  "duration": 600, "target": 2, "label": "Overreact - Buff P2 (5pt)"},
    "6": {"cmd": "godmode", "value": 50,  "duration": 900, "target": 1, "label": "Rosa - God Mode P1 (10pt)"},
    "7": {"cmd": "godmode", "value": 50,  "duration": 900, "target": 2, "label": "Friendship Necklace - God Mode P2 (10pt)"},
    "8": {"cmd": "hammer", "value": 200, "duration": 1,   "target": 0, "label": "REPOST - Hammer Drop!"},
}


def write_command(gift):
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
        "cmd": gift["cmd"],
        "value": gift["value"],
        "duration": gift["duration"],
        "target": gift["target"],
        "from": "TestUser",
        "gift": gift["label"],
        "coins": 1,
        "count": 1,
        "timestamp": time.time(),
    }
    commands.append(command)
    commands = commands[-50:]

    with open(COMMANDS_FILE, "w") as f:
        json.dump(commands, f, indent=2)


def main():
    # Clear old commands
    with open(COMMANDS_FILE, "w") as f:
        json.dump([], f)

    print("=" * 50)
    print("  TIKTOK GIFT TESTER (OFFLINE)")
    print("=" * 50)
    print()
    print("  Start a fight in IkemenGO, then press a key:")
    print()
    for key, gift in GIFTS.items():
        print(f"  [{key}] {gift['label']}")
    print()
    print("  [Q] Quit")
    print()

    while True:
        choice = input("  > ").strip().lower()
        if choice == "q":
            print("  Done.")
            break
        if choice in GIFTS:
            gift = GIFTS[choice]
            write_command(gift)
            target_label = "P1" if gift["target"] == 1 else "P2"
            print(f"  -> Sent: {gift['label']}")
        else:
            print("  Invalid choice, try again.")


if __name__ == "__main__":
    main()
