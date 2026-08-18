#!/usr/bin/env python3
"""
Deploy FFXIFriendList Lua addon to HorizonXI addons directory.

This script deploys the Lua addon to the target path:
C:\\HorizonXI\\HorizonXI\\Game\\addons\\FFXIFriendList
"""

import shutil
import sys
from pathlib import Path

# Configuration
TARGET_DIR = Path(r"C:\HorizonXI\HorizonXI\Game\addons\FFXIFriendList")

# Files/folders to exclude from deployment
EXCLUDE = {
    "scripts",
    "tests", 
    "release",
    ".git",
    ".gitignore",
    "__pycache__",
    "*.pyc",
    ".DS_Store",
}

def should_exclude(path: Path) -> bool:
    """Check if a path should be excluded from deployment."""
    name = path.name
    if name in EXCLUDE:
        return True
    for pattern in EXCLUDE:
        if pattern.startswith("*") and name.endswith(pattern[1:]):
            return True
    return False

def main():
    # Find the addon source directory
    script_dir = Path(__file__).parent
    addon_src = script_dir.parent  # FFXIFriendList folder
    
    if not (addon_src / "FFXIFriendList.lua").exists():
        print(f"ERROR: Could not find FFXIFriendList.lua in {addon_src}")
        sys.exit(1)
    
    print(f"Source: {addon_src}")
    print(f"Target: {TARGET_DIR}")
    
    # Create target directory if it doesn't exist
    TARGET_DIR.mkdir(parents=True, exist_ok=True)
    
    # Clean existing files in target (except user config)
    if TARGET_DIR.exists():
        for item in TARGET_DIR.iterdir():
            if item.name in ("config", "settings.lua"):
                print(f"  Preserving: {item.name}")
                continue
            if item.is_dir():
                shutil.rmtree(item)
            else:
                item.unlink()
    
    # Copy files
    copied_count = 0
    for item in addon_src.iterdir():
        if should_exclude(item):
            print(f"  Skipping: {item.name}")
            continue
        
        dest = TARGET_DIR / item.name
        if item.is_dir():
            shutil.copytree(item, dest, dirs_exist_ok=True)
            print(f"  Copied dir: {item.name}/")
        else:
            shutil.copy2(item, dest)
            print(f"  Copied: {item.name}")
        copied_count += 1
    
    print(f"\nDeployed {copied_count} items to {TARGET_DIR}")
    print("Done!")

if __name__ == "__main__":
    main()

