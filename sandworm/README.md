# Sandworm Tracker
**Windower 4 Addon** | Author: Phayde | Version: 1.0.1

Have you ever tried camping Sandworm for the title? It sucks... but now it can suck less! (unless you want Doomvoid, in which case it can suck more... I guess?)

This addon automatically scans for the roaming Sandworm NM across its 7 possible zones. Detects position movement between scans to confirm the worm is present, then alerts you with coordinates, a map grid reference, a live navigation compass, and an audio cue. Tracks Time of Death and spawn window type (Doomvoid or normal kill) to display the correct respawn window. Integrates with SuperWarp to automatically cycle through all 7 zones until the worm is found.

---

## Installation

1. Drop the `sandworm` folder into `<Windower4>\addons\`
2. *(Optional)* Place a short WAV file named `alert.wav` in the addon folder - any chime or alarm works. Silently skipped if missing.
3. *(Recommended)* Install and load the SuperWarp addon to enable automatic zone cycling.
4. Load the addon: `//lua load sandworm`
   - Or add it to your Windower autoload list.

### Dependencies
Standard Windower 4 Lua libraries (all included with Windower): `texts`, `config`, `strings`, `bit`, `pack`

---

## Commands
Use `//worm` or `//sandworm`.

| Command | Description |
|---|---|
| `//worm help` | Show command list in chat |
| `//worm scan` | Manually trigger a scan cycle in current zone |
| `//worm stop` | Stop scanning and cancel any pending autowarp |
| `//worm status` | Show current window status based on saved ToD |
| `//worm tod now [kill\|doomvoid]` | Set Time of Death to right now |
| `//worm tod MM-DD HH:MM [kill\|doomvoid]` | Set Time of Death manually |
| `//worm autowarp [on/off]` | Toggle automatic zone cycling via SuperWarp |
| `//worm nav` | Toggle the on-screen navigation compass |
| `//worm reset` | Clear all saved data (ToD, positions) |
| `//worm zones` | List zones in rotation order, with current zone marked |

---

## How It Works

On zone-in to any of the 7 Sandworm zones, a scan cycle starts automatically:

```
Scan 1  ->  compare vs known position  ->  differs?
    +- YES -> run confirmation scans (see below)
    +- NO  -> wait 30s -> Scan 2 -> compare vs Scan 1
                  +- moved?  YES -> ALERT!
                             NO  -> ... -> Scan 5 -> NO -> autowarp to next zone
```

Each cycle runs 5 scans with 30 seconds between them - roughly 2 minutes of observation per zone. "Moved" means the worm's position changed by more than 1.0 units between consecutive scans. If confirmed, you get:

- A chat alert with exact coordinates and map grid reference (e.g. `Map: H-7`)
- A live navigation compass showing direction and distance, displayed at the top center of the screen
- An audio alert (if `alert.wav` is present)
- A log entry written to `sandworm_log.csv`

---

## Cross-Session Position Tracking

The addon saves the worm's last known position per zone to `sandworm_positions.csv` after every scan. When you return to a zone in a new session, Scan 1 compares against the saved position. If it differs, the addon enters an investigation phase before alerting - running confirmation scans to determine whether the worm is actively roaming (spawned) or was killed by another player since your last session.

**If the worm is actively roaming:** alert fires immediately on confirmation.

**If position changed but worm is now stationary:** the addon concludes another player killed it, clears the saved ToD, and reports the estimated time window in which the kill occurred (between your last recorded scan and now), along with a suggested midpoint ToD for you to confirm manually.

Position records are automatically cleared for the affected zone when Doomvoid or death is detected, preventing false alerts on the next visit.

---

## Autowarp Zone Cycling

With autowarp enabled (on by default), the addon automatically cycles through all 7 zones using SuperWarp's Survival Guide command. After a full scan cycle with no detection, it waits 5 seconds then issues `//sw sg <next zone>`. The cycle wraps back to zone 1 after zone 7 and continues indefinitely until the worm is detected or you issue `//worm stop`.

**Recommended workflow:**
1. Load SuperWarp and sandworm
2. Set ToD if known: `//worm tod MM-DD HH:MM kill` or `//worm tod MM-DD HH:MM doomvoid`
3. Manually warp to any of the 7 zones to start
4. Focus elsewhere - the addon will scan and cycle on its own
5. When `alert.wav` fires, return to FFXI and follow the navigation compass

To disable autowarp: `//worm autowarp off`

Zone rotation order (default):
1. East Ronfaure [S]
2. North Gustaberg [S]
3. West Sarutabaruta [S]
4. Meriphataud Mountains [S]
5. Batallia Downs [S]
6. Rolanberry Fields [S]
7. Sauromugue Champaign [S]

The rotation index automatically syncs to whichever zone you zone into, so you can start from any zone and the cycle continues from there.

---

## Navigation Compass

When the worm is detected, a HUD box appears at the top center of the screen and updates live as you move:

```
[Sandworm Navigator]
> NNE  |  143y away  Map: H-7
Target: (312.5, -88.2)
```

Disappears automatically when you are within 10 units of the target. Toggle manually at any time with `//worm nav` after a scan has recorded a position.

---

## Map Grid Coordinates

Detection alerts and the navigation compass include a map grid reference in standard FFXI column-row format (e.g. `F-9`, `L-10`). This corresponds directly to the grid shown on the in-game map so you can locate the spawn without interpreting raw coordinates.

Grid calibration is based on two in-game reference points per zone. Accuracy is within one grid square. The universal cell size is 161.0 world units per grid square on both axes.

---

## Time of Death & Spawn Windows

| Condition | Window Opens | Window Closes |
|---|---|---|
| Sandworm uses Doomvoid | 20 hours after | 25 hours after |
| Player kills Sandworm | 48 hours after | 72 hours after |
| Unclaimed despawn | Repops in 1-3h in a random zone | - |

The addon distinguishes between the two main conditions and shows only the relevant window:

- **Doomvoid detected automatically** via the mob action packet when the Sandworm readies Doomvoid. ToD and window type are recorded instantly, before the zone teleport occurs.
- **Normal kill detected automatically** via the entity status packet when the Sandworm's death status is observed.
- **Manual entry** accepts an optional type flag: `//worm tod MM-DD HH:MM kill` or `//worm tod MM-DD HH:MM doomvoid`. If no type is provided, both windows are shown.

ToD input is validated against the current time - timestamps more than 5 minutes in the future are rejected.

ToD and window type are saved to `sandworm_tod.txt` and persist across restarts.

---

## Data Files

| File | Contents |
|---|---|
| `sandworm_log.csv` | Full event log - detections, kills, Doomvoid events, ToD sets |
| `sandworm_tod.txt` | Last saved Time of Death and window type |
| `sandworm_positions.csv` | Last known position per zone with timestamp |

All files are created in the addon folder on first run.

---

## Notes

- The addon auto-scans once per zone visit. Use `//worm scan` to trigger additional cycles manually.
- `//worm stop` halts the scan cycle and cancels any pending autowarp without unloading the addon.
- You do not need to be targeting the worm - the scan packet requests an entity update by index directly from the server.
- If SuperWarp is not loaded, autowarp will produce a console error but otherwise cause no harm. Use `//worm autowarp off` to suppress this.
- If the worm is not in the zone, the scan may return stale or null position data - handled gracefully.
