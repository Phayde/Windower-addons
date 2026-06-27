# Smart Target
### Smarter auto-targeting for Final Fantasy XI | by Phayde | v1.0.3

> **NOTICE:** A sample `settings.xml` is included with settings optimized for Limbus and segment farming.
> If you use it, **replace the character name inside the file with your own** before loading.
> Delete it entirely to start fresh and a new one will be generated on first load.

---

## Installation

Drop the `smarttarget` folder into your `Windower/addons/` directory and load it with:

```
//lua load smarttarget
```

Settings save automatically on any change and reload on next load.

---

## Commands

Use `//smarttarget`, `//smart`, or `//smrt`. Do not type `[ ]`, `< >`, or `|` -- they indicate optional arguments.

```
//smrt                           Engage immediately
//smrt on | off                  Enable or disable smart targeting
//smrt status                    Show all current settings
//smrt debug                     Toggle debug messages
```

```
//smrt aggro                     Toggle aggro-only vs all-monsters targeting
//smrt stat   [on|off|toggle]    Prioritize statues before or after regular mobs
//smrt hp     <0-100 | off>      Prefer mobs at or above an HP% threshold
//smrt first  [on|off|toggle]    Respect your manually chosen first target
//smrt limbus [on|off|toggle]    Auto-disengage when the Limbus floor objective completes
//smrt assist <name> | off       Mirror a party/alliance member's target continuously
//smrt as     <name> | off       Alias for //smrt assist
//smrt finish                    Snap to the lowest HP mob within 10 yalms (one-shot)
```

```
//smrt bias  <0-25>              Bonus/penalty strength for whitelist and greylist (default: 8)
//smrt wlist add|del|list <n>    Whitelist - preferred targets
//smrt glist add|del|list <n>    Greylist  - deprioritized targets
//smrt blist add|del|list <n>    Blacklist - ignored targets
```

---

## Targeting Lists

Three lists let you bias mob priority without editing the lua.

- **Whitelist** -- grants a virtual distance bonus, making these mobs more likely to be chosen
- **Greylist** -- applies a virtual distance penalty, making these mobs less likely to be chosen
- **Blacklist** -- ignores these mobs entirely (if blacklisted mobs are your only option, you may disengage)

Matching is case-insensitive and whole-phrase. Adding "Bat" matches "Nostos Bat", "Temenos Bat", etc. Adding "Black Pudding" only matches that exact family. A name can only exist on one list at a time -- adding it to a new list removes it from the old one automatically.

```
//smrt wlist add Bat        //smrt glist add Slime        //smrt blist add Wyvern
//smrt wlist del Bat        //smrt wlist list
```

The `bias` value (default 8) controls how strongly whitelist/greylist entries are preferred, measured in virtual yalms. Increase it if whitelisted mobs aren't being chosen aggressively enough.

---

## Special Commands

**`//smrt assist <name>`** enters assist mode, continuously mirroring a party or alliance member's target. While active, the normal weighting system is suspended -- the addon simply follows whoever you're assisting. If they disengage, you disengage. Turn it off with `//smrt assist off` or `//smrt off`.

There is a short settle delay (default 1.5s) before committing to a new target, to avoid chasing transitional hops if the person you're assisting is also running smarttarget. This can be adjusted by editing `assist_settle_delay` near the top of the lua.

**`//smrt finish`** is a one-shot command that immediately targets the lowest HP mob within 10 yalms, useful for closing out the last kill of a Limbus floor. The selection is locked so auto-targeting won't override it. Bind it to a macro:

```
/console smrt finish
```

The scan radius can be adjusted by editing `finish_radius` near the top of the lua.

---

## Anti-Thrash

Smart Target won't endlessly swap between equally-rated targets. Tune these values in the lua if needed:

```lua
switch_hysteresis = 2    -- new target must score this much better before switching
retarget_window   = 2.0  -- rolling window in seconds for counting switches
retarget_max      = 2    -- max switches allowed per window
```

- Still swapping too much? Raise `switch_hysteresis` to 3 or 4.
- Too slow to react? Lower `switch_hysteresis` to 1.
- Thrashing in large pulls? Set `retarget_max = 1` or raise `retarget_window`.

---

## Version History

| Version | Summary |
|---|---|
| v0.0.4 | Anti-thrash system; improved front-of-player targeting bonus |
| v0.0.5 | HP threshold targeting with graceful fallback |
| v0.0.6 | Manual first target lock; `//smrt status` command |
| v0.0.7 | Limbus auto-disengage on floor completion |
| v0.0.8 | Auto-save and auto-load for all settings |
| v0.0.9 | Whitelist, greylist, blacklist with whole-phrase matching |
| v1.0.0 | Reliable list persistence; color-coded status/help output; code cleanup |
| v1.0.1 | `//smrt finish` one-shot lowest-HP targeting with auto-lock |
| v1.0.2 | `//smrt assist` / `//smrt as` continuous target mirroring mode |
| v1.0.3 | Fixed dead mob targeting in high-density camp clears |
