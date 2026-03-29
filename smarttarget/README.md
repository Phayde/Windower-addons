# Smart Target

## Employs smarter auto-targeting logic to improve DPS uptime

> This addon was inherited at v0.0.3 from an anonymous author. Updates after v0.0.3 by Phayde.

> **NOTICE:** A sample `settings.xml` is included with settings optimized for limbus and segment farming.
> If you use it, **replace the character name inside the file with your own** before loading.
> If you'd prefer to start fresh, delete the file and a new one will be generated on first load.
> Recommended Limbus settings: `//smrt limbus on` and `//smrt hp 90` and make a `/console smrt finish` macro to use when you only need 1 more kill
> Recommended segfarm settings: `//smrt limbus off` and `//smrt hp 99`
> Pro Tip:	To manually change to a specific target, disengage the current target and re-engage with the `//smrt first` setting on (I keep it on all the time)
> 			If you switch targets without disengaging, the addon will jump in and choose its preferred target instead

---

## Installation

Drop the `smarttarget` folder into your Windower `addons` directory and load it with:

```
//lua load smarttarget
```

Settings are saved automatically any time you make a change and reloaded on next load.

---

## Commands

All commands use `//smarttarget`, `//smart`, or `//smrt`.
Do not type the `[ ]`, `< >`, or `|` characters (they indicate optional arguments and choices)

```
//smrt                           Engage immediately
//smrt on | off                  Enable or disable smart targeting
//smrt status                    Show all current settings
//smrt debug                     Toggle verbose debug messages in the console
```

```
//smrt aggro                     Toggle between aggro-only and all-monsters targeting
//smrt stat   [on|off|toggle]    Prioritize statues before or after regular mobs
//smrt hp     <0-100 | off>      Prefer mobs at or above an HP% threshold (falls back if none qualify)
//smrt first  [on|off|toggle]    Respect your manually chosen first target before handing off to the addon
//smrt limbus [on|off|toggle]    Auto-disengage when the Limbus floor objective is completed
//smrt finish                    Immediately target the lowest HP% mob within 10 yalms (one-shot)
```

```
//smrt bias  <0-25>              Yalm-equivalent bonus/penalty applied to whitelist and greylist mobs (default: 8)
//smrt wlist add|del|list <n>    Whitelist  - preferred targets
//smrt glist add|del|list <n>    Greylist   - deprioritized targets
//smrt blist add|del|list <n>    Blacklist  - ignored targets entirely
```

---

## Targeting Lists

Three lists let you customize how mobs are prioritized without editing the lua.

**Whitelist** — grants a virtual distance bonus so the addon favors these mobs even if they are a bit farther away.

**Greylist** — applies a virtual distance penalty, making these mobs less likely to be chosen unless nothing better is available.

**Blacklist** — completely ignores these mobs. Note: if a blacklisted mob is your only option, it will still be ignored and you may disengage.

Matching is case-insensitive and supports whole phrases. For a mob named "Nostos Bat" or "Temenos Bat" you can just add "Bat" and it will match both.
Multi-word phrases work, too. Adding "Black Pudding" will only match that exact family, not any mob that happens to contain "Black" or "Pudding" individually.

```
//smrt wlist add Bat             Add "bat" to the whitelist
//smrt glist add Slime           Add "slime" to the greylist
//smrt blist add Wyvern          Add "wyvern" to the blacklist
//smrt wlist del Bat             Remove "bat" from the whitelist
//smrt wlist list                Show everything on the whitelist
```

Adding a name that already exists on a different list will automatically move it and notify you. Each name can only exist on one list at a time.

The `bias` value controls how strong the whitelist and greylist effect is, measured in virtual yalms. A higher value means the addon will reach farther (or less far for the greylist) to prefer that mob. The default of 8 is a good balance — increase it if whitelisted mobs aren't being chosen aggressively enough.

---

## Finish Command

`//smrt finish` is a one-shot manual command designed for the end of a Limbus floor or any situation where you want to pile onto the lowest HP mob nearby to finish it off quickly.

When triggered it scans all eligible mobs within 10 yalms, picks the one with the lowest HP%, and immediately switches to it, even if you are already engaged on something else. The selection is locked so the auto-targeting loop won't override it, and the lock releases naturally when that mob dies. The blacklist is respected; the addon's on/off state is not (this command always fires).

The scan radius is hardcoded to 10 yalms but can be changed by editing the `finish_radius` value near the top of the lua.

Bind it to a macro button and hit it when you see the progress bar is one kill away from full:

```
/console smrt finish
```

---

## Anti-Thrash System

Smart Target will not endlessly swap between two equally-rated targets. Three values in the lua control this behavior and can be tuned if needed:

```lua
switch_hysteresis = 2     -- a new target must score this much better before switching
retarget_window   = 2.0   -- seconds over which target-switch attempts are counted
retarget_max      = 2     -- maximum target switches allowed within that window
```

- If the addon still swaps too much, increase `switch_hysteresis` to 3 or 4.
- If it feels too slow to react, lower `switch_hysteresis` to 1.
- If it thrashes in very large pulls, set `retarget_max = 1` or increase `retarget_window`.

---

## Development History

This addon was originally written by an anonymous author and inherited at v0.0.3. The following is a summary of improvements made from v0.0.4 through v1.0.1.

**Targeting logic**
- Widened the "directly in front of player" distance bonus zone
- Added HP threshold targeting: prefer mobs above a set HP% and fall back gracefully when none qualify
- Added aggro-only toggle to optionally include non-aggro mobs
- Added statue priority toggle (first or later)

**Anti-thrash system**
- Hysteresis: a new target must score meaningfully better before the addon switches
- Rate limiting: caps the number of target switches within a rolling time window
- Stable tie-breaking: consistent ordering by distance then mob ID prevents flip-flopping

**Manual control**
- `//smrt first`: locks the player's manually chosen initial target; addon takes over when it dies
- `//smrt finish`: one-shot command to immediately switch to the lowest HP mob within 10 yalms, with lock to prevent auto-targeting from overriding it

**Limbus support**
- `//smrt limbus`: auto-disengages when the floor objective complete message appears in chat, giving the BRD a clean window to sleep remaining mobs

**Targeting lists**
- Whitelist, greylist, and blacklist for per-mob priority tuning without editing the lua
- Whole-phrase, case-insensitive matching ("Bat" matches "Nostos Bat", "Temenos Bat", etc.)
- Adding a name to one list automatically removes it from any other
- `//smrt bias` controls the strength of the whitelist/greylist effect in virtual yalms

**Settings and polish**
- All settings auto-save on change and auto-load on next load, including on/off state
- Settings persist reliably across reloads for list data
- `//smrt status` and help output use color-coded formatting in the Windower console
- Dead code removed, comments cleaned up
