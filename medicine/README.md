# Medicine Cabinet
### A Windower Addon for FFXI
**Version:** 2.10 | **Author:** Phayde | **Commands:** `//med` or `//medicine`

---

## Overview

Medicine Cabinet is a debuff management addon that detects status ailments on your character and uses the appropriate curative items to remove them - quickly, intelligently, and in the right order. It handles everything from a simple silence mid-fight to a full Impact + Doom scenario, and gives you a small always-visible HUD so you always know when it's working and when it's safe to act.

---

## Known Issues

- **Ghoyu's Reverie / Moblin Maze Mongers (MMM):** A small number of hard crashes have been observed while running Medicine Cabinet inside Ghoyu's Reverie during MMM content (specifically the Revitalization Team maze). The cause has not been confirmed and may be unrelated to this addon, but it has been noted for investigation. If you experience crashes in MMM content, try unloading Medicine Cabinet before entering with `//lua unload medicine`.

---

## Anticipated updates

- **DEF, Acc, MDEF, Macc, MAB down:** Add language to target these specifics debuffs with a panacea.
- **Aura detection:** Right now there's a max attempt number to prevent item spam, but I'm working on detecting auras and skipping item use altogether.

---

## The HUD

A small overlay appears in the top-left corner of your screen (draggable to anywhere you like - position is saved). It has the following states:

| State | Color | Meaning |
|---|---|---|
| `[MedCab] OFF` | Grey | Addon loaded, no automatic monitoring active |
| `[MedCab] Autoscanning \| ignoring: poison` | White | Autoscan active, showing ignored ailments (or count if > 3) |
| `[MedCab] Monitoring: Bind, Slow` | White | Monitor mode active, showing watched ailments (or count if > 3) |
| `[MedCab] >> Remedy -> Panacea` | Red | Actively curing -- hold movement and actions |
| `[MedCab] Clear!` | Green | Debuffs removed, briefly shown before returning to idle |
| `[AutoPoison] Active \| 12 fruits` | White (2nd line) | Autopoison is on and monitoring |
| `[AutoPoison] Applying poison...` | Orange (2nd line) | Autopoison is currently using a fruit |
| `[AutoPoison] Out of fruit!` | Red (2nd line) | Autopoison has no El. Pachira Fruit remaining |
| `[AutoFood] Active: Sublime Sushi +1 \| 8 left` | White (3rd line) | Autofood is on and monitoring |
| `[AutoFood] Applying Sublime Sushi +1...` | Orange (3rd line) | Autofood is currently using food |
| `[AutoFood] Out of Sublime Sushi +1!` | Red (3rd line) | Autofood has no food remaining |

When the HUD turns red, the addon is in the middle of using items. **Do not move or perform actions** until it returns to white -- movement or casting can interrupt the item use and force a retry.

---

## The Three Modes

### 1. Manual Scan -- `//med`

The simplest mode. Type `//med` and the addon instantly scans your current debuffs, builds a prioritized cure plan, and executes it. One cycle, one scan. Nothing happens automatically - you're in full control of when it fires.

**Best for:** Situations where you want to stay in control, trivial fights where automation would waste items, or when you just want to pop a quick cure without thinking about which item to use.

```
//med
```

---

### 2. Autoscan -- `//med autoscan`

Toggles a passive monitor that watches for any tracked debuff to land on you and automatically triggers a full cure cycle the moment it's detected. It respects your ignore list (e.g. poison ignored by default), handles multi-debuff scenarios intelligently, and announces in chat when it fires so you know to hold your inputs.

**Best for:** Busy endgame fights where you can't afford to take your hands off your abilities to manually type a command. Set it and forget it.

```
//med autoscan           toggle on/off
//med autoscan on        explicitly enable
//med autoscan off       explicitly disable
```

Autoscan status is **saved** and persists across addon reloads.

---

### 3. Monitor Mode -- `//med monitor <debuff> [debuff] ...`

A targeted middle ground between Manual and Autoscan. You specify exactly which debuffs to watch for, and the addon only reacts to those - everything else is ignored, including your ignore list. Fires automatically like Autoscan but is scoped to the debuffs you care about for this specific fight.

**Best for:** Situations where you know exactly what a mob does. Fighting something that spams Bind and STR Down? Just monitor those two. You get the automation of Autoscan without burning expensive items on debuffs you don't care about.

```
//med monitor bind strdown        watch for Bind and STR Down only
//med monitor paralyze slow bio   watch for Paralyze, Slow, and Bio
//med monitor off                 stop monitor mode
```

Monitor mode is **session only** -- it resets when the addon is reloaded. Enabling Monitor mode automatically disables Autoscan, and vice versa.

---

## Passive Features

### Autopoison -- `//med autopoison`

Runs independently alongside any of the three modes above. When active, it watches for your poison buff to fall off (for any reason) and immediately reapplies it using El. Pachira Fruit. Useful for players who intentionally keep poison up to prevent sleep effects.

If you want to reapply a different food immediately while autopoison is active, use `/antacid` to clear it and autopoison will reapply the fruit automatically.

```
//med autopoison         toggle on/off
//med autopoison on      explicitly enable
//med autopoison off     explicitly disable
//med ap                 shorthand for all of the above
```

Autopoison is **session only** -- resets when the addon is reloaded. Fires immediately on activation if poison is not currently active.

---

### Autofood -- `//med autofood <item name>`

Runs independently alongside any mode. When active, it watches for your food buff (buff ID 251) to wear off and automatically reapplies your specified food item. Works with any food in the game -- just type the name as it appears in your inventory.

If you want to swap to a different food while autofood is active, use `/antacid` to clear your current food and autofood will apply the new one automatically once you set it.

```
//med autofood sublime sushi +1   set food and enable (fires immediately if no food active)
//med autofood                    toggle off if active, show usage if not
//med autofood off                explicitly disable
//med af                          shorthand for all of the above
```

Autofood is **session only** -- resets when the addon is reloaded. If your food supply runs out, autofood disables itself and alerts you.

---

### Movement Detection -- `//med movement`

When enabled, Medicine Cabinet checks whether you are moving before firing any item use attempt. If you are moving, it holds the item and displays a yellow warning in chat -- once -- letting you know it's ready and waiting. The moment you stop moving it fires immediately and resumes the normal retry loop.

**Best for:** Situations where you need to keep moving but know a debuff needs to be cleared as soon as you stop -- such as a BRD pulling a full floor of mobs while getting silenced by casters along the way. Rather than burning through retry attempts mid-pull (when the item would fail anyway), Medicine Cabinet waits patiently and fires the instant you arrive at your destination.

The movement check applies to every item attempt, including retries, so no attempts are wasted while you are in motion.

```
//med movement           toggle on/off
//med movement on        explicitly enable
//med movement off       explicitly disable
//med move               shorthand for all of the above
```

Movement detection is **saved** and persists across addon reloads.

---

## Cure Priority & Item Logic

When a scan runs (in any mode), debuffs are handled in this order:

| Priority | Debuff | Item Used | Notes |
|---|---|---|---|
| 1 | **Paralysis** | Remedy | Always first -- paralysis can interrupt every other cure attempt. Overrides poison ignore if needed. |
| 2 | **Doom** | Holy Water (spam) | Jumps to front if not also paralyzed. Holy Water can fail and be consumed without removing Doom -- retries up to 10 times. |
| 3 | **Silence** | Echo Drops / Remedy | Falls back to Remedy if out of Echo Drops, even if poison ignore is on -- silence takes priority. |
| 4 | **Panacea debuffs** | Panacea | All Panacea-curable debuffs collapsed into a single item use (see full list below). |
| 5 | **Blindness** | Eye Drops / Remedy | Remedy used if also Silenced and no poison concern. Falls back to Remedy if out of Eye Drops. |
| 6 | **Curse** | Holy Water | Single use, no spam -- Curse always clears on a successful item use. |
| 7 | **Poison** | Antidote / Remedy | Only acted on if poison is removed from the ignore list. |

### Multi-Debuff Efficiency

The addon pre-collapses debuffs into the fewest possible item uses:

- **Paralysis + Silence + Blind** -- single Remedy removes all three
- **7x Stat Down + Frost + Slow** -- single Panacea removes all at once
- **Paralysis + Doom** -- Remedy first (clears paralysis so Holy Water attempts are not eaten), then Holy Water spam for Doom

### Poison & the Ignore List

Poison is on the ignore list by default because many players intentionally keep poison active -- a ticking HP DoT prevents sleep effects, which is a common defensive strategy against sleep-heavy mobs.

**Exception:** If you are paralyzed AND poisoned, a Remedy is used regardless of the ignore list since paralysis is the most crippling debuff in the game. The addon will notify you when this happens.

---

## Panacea Debuff List

A single Panacea removes all of these simultaneously:

**Stat downs (individual):** STR Down, DEX Down, VIT Down, AGI Down, INT Down, MND Down, CHR Down

**Combat downs:** ATK Down, DEF Down, ACC Down, EVA Down

**Magic downs:** Magic ATK Down, Magic DEF Down, Magic ACC Down, Max HP Down, Max MP Down

**Spells & Effects:** Slow, Bio, Dia, Addle, Flash, Helix, Gravity, Bind

**Elemental DoTs:** Burn, Frost, Choke, Rasp, Shock, Drown

---

## Retry Logic

The addon uses your buff table -- not chat text -- as its primary source of truth. After using an item it waits **3.0 seconds** then checks whether the debuff is actually gone. This approach is immune to chat lag and flooding, which is common in busy endgame zones.

| Debuff | Max Retries | Reason |
|---|---|---|
| Paralysis | 10 | Item use can be eaten by a paralysis proc |
| Doom | 10 | Holy Water can be consumed and still fail to remove Doom |
| Everything else | 3 | Items work 100% when they fire cleanly |

The `lose buff` game event is also monitored as a fast-path -- if your debuff drops before the 3.0 second check fires, the addon advances to the next item immediately without waiting.

---

## All Commands

### Modes
```
//med                            Scan current debuffs and cure by priority (single cycle)
//med autoscan [on|off]          Toggle automatic full debuff monitoring
//med monitor <buff> [...]       Watch specific debuffs only and auto-cure if they land
//med monitor off                Stop monitor mode
//med autopoison/ap [on|off]     Toggle automatic poison reapplication
//med autofood/af <item name>    Auto-reapply food when it wears off
//med autofood/af off            Disable autofood
//med movement/move [on|off]     Toggle movement-aware item delay
//med doom                       Manually trigger Doom removal Holy Water loop
```

### Ignore List
```
//med ignore <buff>              Toggle a debuff on/off the ignore list
//med <buff> on                  Remove debuff from ignore list (will now be cured)
//med <buff> off                 Add debuff to ignore list (will be skipped)
```

### Direct Item Use -- `//med` commands
```
//med r / rem / remedy           Use a Remedy
//med p / pan / panacea          Use a Panacea
//med e / echo                   Use Echo Drops
//med eye                        Use Eye Drops
//med a / anti / antidote        Use an Antidote
//med h / hw / holy              Use a Holy Water
//med vile / ve                  Use a Vile Elixir
//med vile+1 / ve1               Use a Vile Elixir +1
//med antacid                    Use an Antacid
//med wing / iw                  Use an Icarus Wing
//med fruit                      Use an El. Pachira Fruit
//med prism / powder / prismpowder  Use a Prism Powder
//med oil / silentoil            Use a Silent Oil
//med rr                         Use best available Reraise item*
```
*Reraise priority: Super Reraiser -> Hi-Reraiser -> Reraiser -> Scroll of Instant Reraise

### Slash Shortcuts -- single `/` panic buttons
No `//med` prefix needed. Type these directly in chat like any other slash command. Single-use only -- no retry logic. Designed for muscle memory in high-pressure moments.

```
/med                             Full priority scan and cure (same as //med)

/remedy  /rem  /remed            Use a Remedy
/panacea  /pan  /panac           Use a Panacea
/echodrops  /ech  /echod         Use Echo Drops
/eyedrops  /eye                  Use Eye Drops
/antidote  /anti  /antid         Use an Antidote
/holywater  /hol  /holyw         Use a Holy Water
/vileelixir  /vile  /ve          Use a Vile Elixir
/vileelixir+1  /ve1              Use a Vile Elixir +1
/antacid                         Use an Antacid
/icaruswing  /wing  /iw          Use an Icarus Wing
/fruit  /pachira                 Use an El. Pachira Fruit
/prism  /powder  /prismpowder    Use a Prism Powder
/invis  /inv                     Use a Prism Powder
/oil  /silentoil                 Use a Silent Oil
/snk                             Use a Silent Oil
/rr                              Use best available Reraise item
```

> **Note:** `/echo`, `/holy`, `/invisible`, and `/sneak` are vanilla FFXI commands or conflict with the shortcuts addon and are intentionally excluded. Use the alternatives listed above instead. `/hw` conflicts with Healing Waltz in the shortcuts addon and is also excluded. `/inv` is safe to use for Prism Powder as it has no vanilla conflict.

### Info
```
//med status                     Show active debuffs, mode, ignore list, and inventory counts
//med list ignore                List all ailments on the ignore list
//med list monitor               List all ailments currently being monitored
//med help                       Show command list in chat
```

### Monitor Mode Debuff Keywords
```
Debuff keywords are space-separated with no commas:

Paralysis / paralyze    Doom              Curse
Silence                 Blind / blindness Poison
Slow                    Bio               Dia
Bind                    Gravity           Addle
Flash                   Helix             Burn
Frost                   Choke             Rasp
Shock                   Drown

Stat Downs (individual):
strdown  dexdown  vitdown  agidown  intdown  mnddown  chrdown

Stat Downs (groups):
statdown     all 7 attribute downs
combatdown   ATK / DEF / ACC / EVA Down
magicdown    Magic ATK / Magic DEF / Magic ACC Down
maxhpdown    maxmpdown
```

---

## Default Settings

| Setting | Default | Notes |
|---|---|---|
| Autoscan | OFF | Toggle with `//med autoscan`; persists across reloads |
| Autopoison | OFF | Session only, resets on reload |
| Autofood | OFF | Session only, resets on reload |
| Movement detection | OFF | Toggle with `//med movement`; persists across reloads |
| Monitor mode | OFF | Session only, resets on reload |
| Ignore list | Poison | Add/remove with `//med ignore <buff>`; persists across reloads |
| HUD position | Top-left | Draggable; position saved on unload |

---

## Installation

1. Place `medicine.lua` in your Windower addons folder: `Windower/addons/medicine/medicine.lua`
2. Load with `//lua load medicine` or add to your Windower startup
3. Type `//med help` to confirm it's running

---

## Changelog

**v2.10**
- Added Autopoison feature (auto-reapply El. Pachira Fruit when poison wears off)
- Added Autofood feature (auto-reapply any food item when food buff wears off)
- Added Monitor mode (watch specific debuffs only, session only)
- Added slash command panic buttons (/pan, /rem, /ech, /prism, /snk, /invis, /rr, etc.)
- Added //med doom command for manual Doom removal loop
- Switched from chat-based retry logic to buff table polling for lag immunity
- Added HUD with live status display (draggable, position saved)
- Retry delay tuned to 3.0 seconds
- Generation counter pattern prevents duplicate item use on interrupted retries
- Added movement detection -- holds item use while player is moving, fires on stop
- Added cleanup scan at end of each cure cycle to catch debuffs that landed mid-queue
- Added /inv as additional shortcut for Prism Powder
- Known issue: occasional crash observed in Ghoyu's Reverie (MMM) -- under investigation

**v2.00**
- Complete rewrite with buff-table driven retry engine
- Pre-collapsed queue builder (one Remedy/Panacea per debuff group)
- Autoscan mode added
- Ignore list for any debuff (poison ignored by default)
- Priority order: Paralysis > Doom > Silence > Panacea > Blindness > Curse > Poison

**v1.00**
- Initial release with manual scan and cure
