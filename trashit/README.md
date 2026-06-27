# Trash It
### A Windower 4 addon for Final Fantasy XI

> **Activate. Farm. Deactivate. Done.**  
> Automatically discards newly acquired items so your inventory stays clean. Built for Mog Gardening, useful anywhere.

---

## Overview

I was tired of the Mog Gardening grind clogging my inventory with worthless items. **Trash It** solves this: flip it on before you collect, and every new item that lands in your inventory gets automatically discarded. A bold on-screen indicator stays visible the entire time so you never forget it's running.

Works with gardening, mob farming, fishing, and any other acquisition method.

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
//trash on       -> Activate. Takes an inventory snapshot, begins discarding new items.
//trash off      -> Deactivate. Returns to normal behavior.
//trash          -> Toggle on/off.
```

That's the whole workflow. Turn it on, do your thing, turn it off.

---

## Whitelist

Items you want to **keep** even when the addon is active:

```
//trash keep <term>          -> Add term to whitelist
//trash remove <term>        -> Remove term from whitelist
//trash list                 -> View current whitelist
```

Whitelist matching is **case-insensitive substring** based - you don't need to know the exact item name. Adding `mythril ore` will protect "Chunk of mythril ore", "Lump of mythril ore", or any item whose name contains that phrase. Adding `bayld` protects "Pinch of high-purity bayld", and so on. The whitelist persists between sessions via `settings.xml`.

---

## Safety

Trash It is designed with a conservative safety model:

- **Inventory snapshot on activation** - the moment you run `//trash on`, your current inventory is recorded. Any item you already own is permanently off-limits for that session, even if you pick up another one.
- **Only newly acquired units are dropped** - if you have a stack of 10 Ice Crystals and pick up an 11th, only the new one is discarded. Pre-existing stacks are never touched.
- **No pre-existing item is ever dropped** - if an item appears in your snapshot at any count above zero, it is skipped entirely.
- **On-screen HUD** - a persistent red warning banner is displayed at the top of your screen whenever the addon is active, so you can't accidentally leave it running.
- **Note** - All dropped items appear in your recycle bin, so if something is trashed and you change your mind, you can get it back until your bin runs out of space.

---

## Other Commands

```
//trash status   -> Show active state, snapshot size, and whitelist count
//trash help     -> Show command reference in-game
```

---

## Notes

- Designed and tested for **Mog Gardening**, but works with any item acquisition method: mob farming, fishing, digging, chest drops, etc.
- HUD is positioned for **1920x1080**. For other resolutions, adjust `HUD_X` at the top of the file using: `HUD_X = math.floor(screen_width / 2) - 140`
- Compatible with auto-sorter addons - a short delay is applied before each drop to give sorters time to move items to their final slot first.

---

*Built for [Windower 4](https://www.windower.net/) · FFXI*
