# 🗑️ Trash It
### A Windower 4 addon for Final Fantasy XI

> **Activate. Farm. Deactivate. Done.**  
> Automatically discards newly acquired items so your inventory stays clean. Built for Mog Gardening, useful anywhere (?).

---

## Overview

I was tried of the Mog Gardening grind clogging my inventory with worthless items. **Trash It** solves this: flip it on before you collect, and every new item that lands in your inventory gets automatically discarded. A bold on-screen indicator stays visible the entire time so you never forget it's running.

---

## Installation

1. Copy `trashit.lua` into `Windower/addons/trashit/trashit.lua`
2. Load it in-game:
   ```
   //lua load trashit
   ```

---

## Usage

```
//trash on       → Activate. Takes an inventory snapshot, begins discarding new items.
//trash off      → Deactivate. Returns to normal behavior.
//trash          → Toggle on/off.
```

That's the whole workflow. Turn it on, do your gardening, turn it off.

---

## Whitelist

Items you want to **keep** even when the addon is active:

```
//trash keep <item name>     → Add to whitelist
//trash remove <item name>   → Remove from whitelist
//trash list                 → View current whitelist
```

Item names are matched exactly (case-insensitive). The whitelist persists between sessions via `settings.xml`.

---

## Safety

Trash It is designed with a conservative safety model:

- **Inventory snapshot on activation** - the moment you run `//trash on`, your current inventory is recorded. Any item you already own is permanently off-limits for that session, even if you pick up another one.
- **Drops quantity 1 only** - if you have a stack of 10 Ice Crystals and pick up an 11th, only the new one is discarded. The original stack is never touched.
- **No pre-existing item is ever dropped** - if an item appears in your snapshot at any count above zero, it is skipped entirely.
- **On-screen HUD** - a persistent red warning banner is displayed at the top of your screen whenever the addon is active, so you can't accidentally leave it running.
- **Note** - All dropped items appear in your recycle bin, so if something is trashed and you change your mind, you can get it back until yuor bin runs out of space

---

## Other Commands

```
//trash status   → Show active state, snapshot size, and whitelist count
//trash debug    → Toggle verbose debug output (useful for troubleshooting)
//trash help     → Show command reference in-game
```

---

## Notes

- Designed and tested for **Mog Gardening**, but should work with any item acquisition method: fishing, digging, mob drops, etc.
- HUD is positioned for **1920×1080**. For other resolutions, adjust `HUD_X` at the top of the file using: `HUD_X = math.floor(screen_width / 2) - 140`
- Compatible with auto-sorter addons — a short delay is applied before each drop to give sorters time to move items to their final slot first.

---

*Built for [Windower 4](https://www.windower.net/) · FFXI*
