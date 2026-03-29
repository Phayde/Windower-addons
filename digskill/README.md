# DigSkill

**Automated chocobo digging**

DigSkill handles the full digging loop of sending dig commands, moving between spots, tracking your daily fatigue, managing your inventory, and warping you home when you're done. Bring plenty of greens, set it up once and let it run.

---

## Requirements

- A chocobo (rented or personal)
- Gysahl Greens in your inventory
- The [ChocoCard](https://github.com/Windower/Addons) addon (optional, for reading your chocobo's END stat)

---

## Installation

1. Extract the `digskill` folder into your `Windower/addons/` directory
2. In Windower, run: `lua load digskill`
3. To load automatically on startup, add `lua load digskill` to your `Windower/scripts/init.txt`

---

## Getting Started

1. Mount your chocobo
2. Make sure you have Gysahl Greens in your inventory
3. Run `//cc log` (ChocoBud addon) to find your chocobo's END stat, then set it:
   ```
   //ds end <value>
   ```
4. Set your current digging rank:
   ```
   //ds rank Recruit
   ```
5. Start digging:
   ```
   //ds start
   ```

---

## How It Works

DigSkill runs a continuous dig loop using a state machine with three phases:

- **Idle** - sends `/dig` when the rank cooldown has elapsed
- **Digging** - waits for the game's response (item found, miss, conquest points, etc.)
- **Moving** - moves the chocobo forward and left between digs to change the dig spot

Dig timing is governed by your rank. Higher ranks have shorter cooldowns between digs, so keeping your rank setting accurate helps with efficiency

### Fatigue Tracking

Every successful dig (item or conquest points) consumes one point of daily fatigue. Your fatigue cap is determined by your chocobo's END stat and whether you're wearing Blue Racing Silks:

```
Fatigue Cap = min(100 + floor(END / 2), 200)
Blue Racing Silks add a flat +50 to this cap
```

DigSkill tracks how much fatigue you've used today across all sessions and shows your remaining estimate at session end. Fatigue resets at JP midnight (00:00 JST).

### Miss Detection

Ten consecutive misses triggers a warning suggesting you've either hit your fatigue cap or the zone has run out of items. DigSkill never hard-stops on misses; it's a warning only, leaving the decision to you.

### Wing Skill

DigSkill detects and tracks your wing skill level. When you level up, it announces the old and new level in chat and can automatically update your dig rank setting to match. Wing skill data is saved permanently and never resets.

---

## Multi-Character Support

All stats and logs are stored under `data/<CharacterName>/` inside the addon folder. Each character on the same computer gets their own separate history, fatigue tracking, and wing skill data.

---

## Commands

### Session Control

| Command | Description |
|---|---|
| `//ds start` | Begin a digging session |
| `//ds stop` | End the current session and save the log |
| `//ds pause` | Pause an active session |
| `//ds resume` | Resume a paused session |

### Configuration

| Command | Description |
|---|---|
| `//ds rank [name]` | Show or set your dig rank (Amateur through Expert) |
| `//ds body [type]` | Set body piece: `none`, `blue`, or `sky` |
| `//ds end <value>` | Set your chocobo's END stat (from `//cc log`) |
| `//ds maxtime [min]` | Set max session duration in minutes (`0` = no limit) |
| `//ds tossitems` | Toggle dropping of unwanted dug items |
| `//ds warp` | Toggle auto-warp home on dismount after a session |
| `//ds campaign` | Toggle Hyper Campaign mode (minimises all delays) |
| `//ds dst` | Toggle Daylight Saving Time for JP midnight calculation |

### Wing Skill

| Command | Description |
|---|---|
| `//ds wingskill` | Show current wing skill level, career ups, and mapped rank |
| `//ds wingskill set <n>` | Manually set your wing skill level |
| `//ds wingskill autorank` | Toggle auto-updating dig rank on skill-up |

### Information

| Command | Description |
|---|---|
| `//ds status` | Show session stats or current environment info if idle |
| `//ds settings` | Show all current settings |
| `//ds zonelist` | List all diggable zones with skill and profit grades |
| `//ds report` | Print today's session log to chat |
| `//ds fullreport` | Compile an all-time report from all daily logs |
| `//ds cumulative` | Show all-time career stats |
| `//ds debug [on/off]` | Toggle verbose state machine logging |
| `//ds help` | Show the full command list in chat |

---

## Body Piece Options

| Setting | Effect |
|---|---|
| `none` | No bonus |
| `blue` | Blue Racing Silks - ~50% chance each successful dig costs no fatigue |
| `sky` | Sky Blue Racing Silks - ~50% chance of a bonus chocobo knowledge proc per dig |

---

## Auto-Warp

When enabled, DigSkill automatically uses your Warp Ring after you dismount at the end of a session. If your session ends due to a time limit, DigSkill will dismount your chocobo automatically so the warp sequence can proceed without you having to do anything.

The Warp Ring can be in your inventory or any wardrobe. If the first use attempt fails the sequence retries automatically.

Enable with `//ds warp`. Requires a Warp Ring somewhere in your inventory or wardrobes.

---

## Digging Ranks and Delays

| Rank | Dig Delay |
|---|---|
| Amateur | 15s |
| Recruit | 10s |
| Initiate | 5s |
| Novice | 3s |
| Apprentice | 3s |
| Journeyman | 3s |
| Craftsman | 3s |
| Artisan | 3s |
| Adept | 3s |
| Veteran | 3s |
| Expert | 3s |

During **Hyper Campaign** events all delays are reduced to 3s regardless of rank (`//ds campaign`).

---

## Session Logs

Each session is appended to a daily log file at:
```
addons/digskill/data/<CharacterName>/dig logs/log_YYYY-MM-DD.txt
```

Logs use the JP calendar date, so a session that starts before and ends after JP midnight is logged to the correct day. Use `//ds report` to print today's log to chat, or `//ds fullreport` to compile an all-time breakdown by day to a text file.

---

## Settings

Settings are saved to `data/settings.xml` and are per-character (Windower handles this automatically). Most settings can be changed via commands, but you can also edit the XML directly. Key settings:

| Setting | Default | Description |
|---|---|---|
| `dig_rank` | `Amateur` | Current dig rank - controls dig delay |
| `chocobo_end_value` | `0` | Raw END stat from `//cc log`. 0 = rental or Poor endurance |
| `body_piece` | `None` | Body piece worn while digging |
| `max_session_minutes` | `60` | Session time limit in minutes. 0 = no limit |
| `keep_items` | `Gysahl Greens` | Comma-separated items to keep when toss mode is on |
| `drop_dug_items` | `true` | Automatically discard unwanted dug items |
| `warp` | `false` | Auto-warp on dismount |
| `auto_rank` | `true` | Auto-update dig rank when wing skill levels up |
| `dst` | `true` | Daylight Saving Time toggle for JP midnight calculation |

---

## Tips

- Run `//ds status` before starting to confirm your zone grade, fatigue remaining, and settings look right
- Use `//ds zonelist` to find zones with good skill grades if you're levelling wing skill
- If you're farming specific items, add them to `keep_items` and enable toss mode with `//ds tossitems`
- Wing skill thresholds in the auto-rank table are placeholders (Note: update `WING_SKILL_RANKS` in the lua once SE publishes official values)
- If you don't use GearSwap, the `gs disable`/`gs enable` commands in the warp sequence are harmless, Windower will just ignore them

---