# SuperCleveRoid Macros

Enhanced macro addon for World of Warcraft 1.12.1 (Vanilla/Turtle WoW) with dynamic tooltips, conditional execution, and extended syntax.

## Requirements

| Mod | Required | Purpose |
|-----|:--------:|---------|
| [SuperWoW](https://github.com/balakethelock/SuperWoW/releases) | ✅ | Extended API (addon won't load without it) |
| [Nampower](https://gitea.com/avitasia/nampower/releases) (v2.24+) | ✅ | Spell queueing, DBC data, auto-attack events |
| [UnitXP_SP3](https://codeberg.org/konaka/UnitXP_SP3/releases) | ✅ | Distance checks, `[multiscan]` enemy scanning |

## Installation

1. Download and extract to `Interface/AddOns/SuperCleveRoidMacros`
2. **Recommended pfUI:** Use [jrc13245/pfUI](https://github.com/jrc13245/pfUI) for full compatibility with macro spell scanning and action bar features

---

## Quick Start

### Basic Syntax
```lua
#showtooltip
/cast [mod:alt] Frostbolt; [mod:ctrl] Fire Blast; Blink
```

- **Conditionals** in `[]` brackets, space or comma separated
- **Arguments** use colon: `[mod:alt]`, `[hp:>50]`
- **Negation** with `no` prefix: `[nobuff]`, `[nomod:alt]`
- **Target** with `@`: `[@mouseover,help]`, `[@party1,hp:<50]`
- **Spell names** with spaces: `"Mark of the Wild"` or `Mark_of_the_Wild`

### Multi-Value Logic
```lua
[buff:X/Y]        -- X OR Y (has either)
[buff:X&Y]        -- X AND Y (has both)
[nobuff:X/Y]      -- NOT X AND NOT Y (missing both) - operators flip for negation
```

### Comparisons
```lua
[hp:>50]          -- Health above 50%
[buff:"Name"<5]   -- Less than 5 seconds remaining
[debuff:"Name">#3] -- 3+ stacks (use ># for stacks)
```

### Special Prefixes
| Prefix | Example | Description |
|:------:|---------|-------------|
| `!` | `!Attack` | Only use if not active |
| `?` | `?[equipped:Swords] Ability` | Hide from tooltip |
| `~` | `~Slow Fall` | Toggle buff on/off |

---

## Conditionals Reference

All conditionals support negation with `no` prefix (e.g., `[nocombat]`, `[nobuff]`, `[nohelp]`). Some also have semantic opposites: `help`/`harm`, `isplayer`/`isnpc`, `alive`/`dead`, `inrange`/`outrange`.

### Modifiers & Player State
| Conditional | Example | Description |
|-------------|---------|-------------|
| `mod` | `[mod:alt/ctrl/shift]` | Modifier key pressed |
| `combat` | `[combat]` `[combat:target]` | In combat (player or unit) |
| `form/stance` | `[form:1]` `[stance:2]` | Shapeshift/stance index |
| `stealth` | `[stealth]` | In stealth (Rogue/Druid) |
| `group` | `[group]` `[group:party/raid]` | Player in group type |
| `resting` | `[resting]` | In rest area |
| `swimming` | `[swimming]` | Can use aquatic form |
| `moving` | `[moving]` `[moving:>100]` | Moving / speed % (MonkeySpeed) |
| `zone` | `[zone:"Ironforge"]` | Current zone name |

### Resources
| Conditional | Example | Description |
|-------------|---------|-------------|
| `myhp` | `[myhp:<30]` | Player HP % |
| `myrawhp` | `[myrawhp:>1000]` | Player raw HP value |
| `myhplost` | `[myhplost:>500]` | Player HP lost (max - current) |
| `mypower` | `[mypower:>50]` | Player mana/rage/energy % |
| `myrawpower` | `[myrawpower:>500]` | Player raw power value |
| `mypowerlost` | `[mypowerlost:>200]` | Player power lost |
| `druidmana` | `[druidmana:>=500]` | Druid mana while shapeshifted |
| `combo` | `[combo:>=4]` | Combo points |
| `stat` | `[stat:agi>100]` `[stat:ap>1000]` | Player stats (see below) |

**Stat types:** `str`, `agi`, `stam`, `int`, `spi`, `ap`, `rap`, `healing`, `armor`, `defense`, `arcane_power`, `fire_power`, `frost_power`, `nature_power`, `shadow_power`, `arcane_res`, `fire_res`, `frost_res`, `nature_res`, `shadow_res`

### Buffs & Debuffs
| Conditional | Example | Description |
|-------------|---------|-------------|
| `mybuff` | `[mybuff:"Name"<5]` | Player has buff (with time check) |
| `mydebuff` | `[mydebuff:"Name"]` | Player has debuff |
| `mybuffcount` | `[mybuffcount:>15]` `[nomybuffcount:>28]` | Player buff slot count (32 max) |
| `buff` | `[buff:"Name">#3]` | Target has buff (with stacks) |
| `debuff` | `[debuff:"Sunder">20]` | Target has debuff (with time) |
| `cursive` | `[cursive:Rake<3]` | Cursive addon tracking (GUID-based) |

### Cooldowns & Casting
| Conditional | Example | Description |
|-------------|---------|-------------|
| `cooldown` | `[cooldown:"Spell"<5]` | CD remaining (ignores GCD) |
| `cdgcd` | `[cdgcd:"Spell">0]` | CD remaining (includes GCD) |
| `gcd` | `[gcd]` `[gcd:<1]` | GCD is active / remaining time |
| `usable` | `[usable:"Spell"]` | Spell/item is usable |
| `reactive` | `[reactive:Overpower]` | Reactive ability available |
| `known` | `[known:"Spell">#2]` | Spell/talent known (with rank) |
| `channeled` | `[channeled]` | Currently channeling |
| `channeltime` | `[channeltime:<0.5]` | Channel time remaining (seconds) |
| `selfcasting` | `[selfcasting]` | Player is casting/channeling |
| `casttime` | `[casttime:<0.5]` | Player cast time remaining |
| `checkcasting` | `[checkcasting]` `[checkcasting:Frostbolt]` | NOT casting (specific spell) |
| `checkchanneled` | `[checkchanneled]` | NOT channeling (specific spell) |
| `queuedspell` | `[queuedspell]` `[queuedspell:Fireball]` | Spell queued (Nampower) |
| `onswingpending` | `[onswingpending]` | On-swing spell pending |

### Target Checks
| Conditional | Example | Description |
|-------------|---------|-------------|
| `exists` | `[@mouseover,exists]` | Unit exists |
| `alive/dead` | `[alive]` `[dead]` | Alive or dead |
| `help/harm` | `[help]` `[harm]` | Friendly or hostile |
| `hp` | `[hp:<20]` `[hp:>30&<70]` | Target HP % |
| `rawhp` | `[rawhp:>5000]` | Target raw HP value |
| `hplost` | `[hplost:>1000]` | Target HP lost |
| `power` | `[power:<30]` | Target power % |
| `rawpower` | `[rawpower:>500]` | Target raw power value |
| `powerlost` | `[powerlost:>100]` | Target power lost |
| `powertype` | `[powertype:mana/rage/energy]` | Target's power type |
| `level` | `[level:>60]` `[mylevel:=60]` | Unit level (skull = 63) |
| `class` | `[class:Warrior/Priest]` | Target class (players only) |
| `type` | `[type:Undead/Beast]` | Creature type |
| `isplayer` | `[isplayer]` | Target is a player |
| `isnpc` | `[isnpc]` | Target is an NPC |
| `targeting` | `[targeting:player]` | Unit targeting you |
| `casting` | `[casting:"Spell"]` | Unit casting spell |
| `party` | `[party]` `[party:focus]` | Unit in your party |
| `raid` | `[raid]` `[raid:mouseover]` | Unit in your raid |
| `member` | `[member]` | Target in party OR raid |
| `hastarget` | `[hastarget]` | Player has a target |
| `notarget` | `[notarget]` | Player has no target |
| `pet` | `[pet]` `[pet:Cat/Wolf]` | Has pet (with family) |
| `name` | `[name:Onyxia]` | Exact name match (case-insensitive) |
| `tag` | `[tag]` | Target is tapped (by anyone) |
| `notag` | `[notag]` | Target is not tapped |
| `mytag` | `[mytag]` | Target is tapped by you |
| `nomytag` | `[nomytag]` | Target is not tapped by you |
| `othertag` | `[othertag]` | Target is tapped by someone else |
| `noothertag` | `[noothertag]` | Not tapped by others (yours or unclaimed) |

### Range & Position
| Conditional | Example | Description |
|-------------|---------|-------------|
| `distance` | `[distance:<40]` | Distance in yards (UnitXP) |
| `inrange` | `[inrange:"Spell"]` | In spell range |
| `outrange` | `[outrange:"Spell"]` | Out of spell range |
| `meleerange` | `[meleerange]` | In melee range (~5 yards) |
| `behind` | `[behind]` | Behind target (UnitXP) |
| `insight` | `[insight]` | In line of sight (UnitXP) |

### Equipment
| Conditional | Example | Description |
|-------------|---------|-------------|
| `equipped` | `[equipped:Daggers]` | Item/type equipped |
| `mhimbue` | `[mhimbue]` `[mhimbue:Instant_Poison]` | Main-hand has temporary imbue |
| `ohimbue` | `[ohimbue]` `[ohimbue:Crippling_Poison]` | Off-hand has temporary imbue |

**Imbue Conditionals (Poisons, Oils, Sharpening Stones):**
```lua
[mhimbue]                      -- Has any temporary imbue
[mhimbue:Instant_Poison]       -- Has specific imbue (tooltip match)
[mhimbue:<300]                 -- Imbue expires in < 300 seconds (5 min)
[mhimbue:Instant_Poison<300]   -- Specific imbue with time check
[mhimbue:>#5]                  -- Has > 5 charges remaining
[nomhimbue]                    -- No temporary imbue (apply needed)
```

**Note:** Temporary imbues are detected via tooltip time/charge markers, filtering out permanent enchants like Crusader.

### CC & Immunity
| Conditional | Example | Description |
|-------------|---------|-------------|
| `cc` | `[cc]` `[cc:stun/fear]` | Target has CC effect |
| `mycc` | `[mycc]` `[mycc:silence]` | Player has CC effect |
| `immune` | `[immune:fire]` `[immune:stun]` | Target IS immune (skip cast) |
| `noimmune` | `[noimmune]` `[noimmune:bleed]` | Target NOT immune (allow cast) |
| `resisted` | `[resisted]` `[resisted:full/partial]` | Last spell was resisted |

**CC Types:** stun, fear, root, snare/slow, sleep, charm, polymorph, banish, horror, disorient, silence, disarm, daze, freeze, shackle

**Loss-of-control** (checked by bare `[cc]`): stun, fear, sleep, charm, polymorph, banish, horror, freeze, disorient, shackle

**Damage Schools:** physical, fire, frost, nature, shadow, arcane, holy, bleed

### Addon Integrations
| Conditional | Addon | Example | Description |
|-------------|-------|---------|-------------|
| `swingtimer` | SP_SwingTimer | `[swingtimer:<15]` | Swing % elapsed |
| `stimer` | SP_SwingTimer | `[stimer:>80]` | Alias for swingtimer |
| `threat` | TWThreat | `[threat:>80]` | Threat % (100=pull) |
| `ttk` | TimeToKill | `[ttk:<10]` | Time to kill (seconds) |
| `tte` | TimeToKill | `[tte:<5]` | Time to execute (20% HP) |
| `cursive` | Cursive | `[cursive:Rake>3]` | GUID debuff tracking |
| `moving` | MonkeySpeed | `[moving:>100]` | Speed % (100=normal run) |

### Warrior Slam Conditionals
For optimizing Slam rotations without clipping auto-attacks:

| Conditional | Description |
|-------------|-------------|
| `noslamclip` | True if Slam NOW won't clip auto-attack |
| `slamclip` | True if Slam NOW WILL clip auto-attack |
| `nonextslamclip` | True if instant NOW won't cause NEXT Slam to clip |
| `nextslamclip` | True if instant NOW WILL cause NEXT Slam to clip |

```lua
/cast [noslamclip] Slam
/cast [slamclip] Heroic Strike   -- Use HS when past slam window
/cast [nonextslamclip] Bloodthirst
```

### Auto-Attack Conditionals (Nampower v2.24+)

Track player melee swings and incoming attacks. Requires `NP_EnableAutoAttackEvents=1` CVar.

| Conditional | Example | Description |
|-------------|---------|-------------|
| `lastswing` | `[lastswing]` | Any melee swing in last 5 seconds |
| `lastswing:type` | `[lastswing:crit]` | Last swing was specific type |
| `lastswing:<N` | `[lastswing:<2]` | Last swing was < N seconds ago |
| `nolastswing:type` | `[nolastswing:miss/dodge]` | Last swing was NOT type (AND logic) |
| `incominghit` | `[incominghit]` | Any incoming hit in last 5 seconds |
| `incominghit:type` | `[incominghit:crushing]` | Last incoming hit was type |
| `noincominghit:type` | `[noincominghit:crushing]` | Last hit was NOT type |

**Swing/Hit Types:**
| Type | Description |
|------|-------------|
| `crit` | Critical hit |
| `glancing` | Glancing blow |
| `crushing` | Crushing blow (incoming only) |
| `miss` | Attack missed |
| `dodge` / `dodged` | Target dodged |
| `parry` / `parried` | Target parried |
| `blocked` / `block` | Attack was blocked |
| `offhand` / `oh` | Off-hand swing (lastswing only) |
| `mainhand` / `mh` | Main-hand swing (lastswing only) |
| `hit` | Successful hit (not miss/dodge/parry) |

```lua
/cast [lastswing:dodge] Overpower        -- Overpower after enemy dodged
/use [incominghit:crushing] Last Stand   -- Emergency CD after crushing blow
/cast [lastswing:crit] Execute           -- Execute after crit proc
```

### Aura Cap Conditionals (Nampower v2.20+)

Track buff/debuff bar capacity. Requires `NP_EnableAuraCastEvents=1` CVar for accurate tracking.

| Conditional | Example | Description |
|-------------|---------|-------------|
| `mybuffcapped` | `[mybuffcapped]` | Player has 32 buffs (full) |
| `nomybuffcapped` | `[nomybuffcapped]` | Player has buff room |
| `mydebuffcapped` | `[mydebuffcapped]` | Player has 16 debuffs (full) |
| `nomydebuffcapped` | `[nomydebuffcapped]` | Player has debuff room |
| `buffcapped` | `[buffcapped]` | Target buff bar is full (32) |
| `nobuffcapped` | `[nobuffcapped]` | Target has buff room |
| `debuffcapped` | `[debuffcapped]` | Target debuff bar is full |
| `nodebuffcapped` | `[nodebuffcapped]` | Target has debuff room |

**Aura Capacity:**
- **Player:** 32 buff slots, 16 debuff slots
- **NPCs:** 16 debuff slots + 32 overflow = 48 total visual debuff capacity

```lua
/cast [nodebuffcapped,nocursive:Rake] Rake   -- Only DoT if room on target
/cast [nomybuffcapped] Mark of the Wild      -- Only buff self if room
/cast [@focus,nodebuffcapped] Corruption     -- Only DoT focus if room
```

### Multiscan (Target Scanning)
Scans enemies and soft-casts without changing your target. Requires UnitXP_SP3.
```lua
/cast [multiscan:nearest,nodebuff:Rake] Rake
/cast [multiscan:skull,harm] Eviscerate
/cast [multiscan:markorder] Sinister Strike
/cast [multiscan:highesthp,noimmune:stun] Cheap Shot
```

**Priorities:**
| Priority | Description |
|----------|-------------|
| `nearest` | Closest enemy |
| `farthest` | Farthest enemy |
| `highesthp` | Highest HP % |
| `lowesthp` | Lowest HP % |
| `highestrawhp` | Highest raw HP |
| `lowestrawhp` | Lowest raw HP |
| `markorder` | First mark in kill order (skull→cross→square→moon→triangle→diamond→circle→star) |
| `skull`, `cross`, `square`, `moon`, `triangle`, `diamond`, `circle`, `star` | Specific raid mark |

**Note:** Scanned targets must be in combat with player, except current target and `@unit` specified in macro.

---

## Slash Commands

### Commands with Conditional Support

These commands accept `[conditionals]` and use UnitXP 3D enemy scanning when applicable.

| Command | Conditionals | UnitXP Scan | Description |
|---------|:------------:|:-----------:|-------------|
| `/cast [cond] Spell` | ✅ | — | Cast spell with conditionals |
| `/castpet [cond] Spell` | ✅ | — | Cast pet spell |
| `/use [cond] Item` | ✅ | — | Use item by name/ID/slot |
| `/equip [cond] Item` | ✅ | — | Equip item (same as /use) |
| `/target [cond]` | ✅ | ✅ | Target with conditionals + enemy scan |
| `/startattack [cond]` | ✅ | — | Start auto-attack if conditions met |
| `/stopattack [cond]` | ✅ | — | Stop auto-attack if conditions met |
| `/stopcasting [cond]` | ✅ | — | Stop casting if conditions met |
| `/unqueue [cond]` | ✅ | — | Clear spell queue if conditions met |
| `/cleartarget [cond]` | ✅ | — | Clear target if conditions met |
| `/cancelaura [cond] Name` | ✅ | — | Cancel buff if conditions met |
| `/quickheal [cond]` | ✅ | — | Smart heal (requires QuickHeal) |
| `/stopmacro [cond]` | ✅ | — | Stop ALL macro execution (including parent macros) |
| `/skipmacro [cond]` | ✅ | — | Stop current submacro only, parent continues |
| `/firstaction [cond]` | ✅ | — | Stop on first successful `/cast` or `/use` (priority mode) |
| `/nofirstaction [cond]` | ✅ | — | Re-enable multi-queue after `/firstaction` |
| `/petattack [cond]` | ✅ | — | Pet attack with conditionals |
| `/petfollow [cond]` | ✅ | — | Pet follow with conditionals |
| `/petwait [cond]` | ✅ | — | Pet stay with conditionals |
| `/petpassive [cond]` | ✅ | — | Pet passive with conditionals |
| `/petdefensive [cond]` | ✅ | — | Pet defensive with conditionals |
| `/petaggressive [cond]` | ✅ | — | Pet aggressive with conditionals |
| `/castsequence` | ✅ | — | Sequence with reset conditionals |
| `/equipmh [cond] Item` | ✅ | — | Equip to main hand |
| `/equipoh [cond] Item` | ✅ | — | Equip to off hand |
| `/equip11` - `/equip14 [cond]` | ✅ | — | Equip to slot (rings/trinkets) |
| `/unshift [cond]` | ✅ | — | Cancel shapeshift if conditions met |
| `/applymain [cond] Item` | ✅ | — | Apply poison/oil to main hand |
| `/applyoff [cond] Item` | ✅ | — | Apply poison/oil to off hand |

#### Priority-Based Macro Evaluation (`/firstaction` & `/nofirstaction`)

By default, all `/cast` lines in a macro are evaluated and may queue spells with Nampower. Use `/firstaction` to enable "first successful cast wins" behavior - once a `/cast` or `/use` succeeds, the macro stops evaluating subsequent lines. Use `/nofirstaction` to re-enable normal multi-queue behavior.

```lua
-- WITHOUT /firstaction: Both Shred AND Claw may queue if conditions are met
/cast [myrawpower:>48] Shred
/cast [myrawpower:>40] Claw

-- WITH /firstaction: Only Shred casts if energy >= 48, Claw is skipped
/firstaction
/cast [myrawpower:>48] Shred
/cast [myrawpower:>40] Claw

-- Mixed mode: priority section + always-queue section
/firstaction
/cast [myrawpower:>48] Shred      -- Priority: only one of these
/cast [myrawpower:>40] Claw
/nofirstaction
/cast Tiger's Fury                -- Always evaluates (can queue alongside)
/startattack

-- With conditionals
/firstaction [group]              -- Priority mode only in groups
/cast [myrawpower:>48] Shred
/cast [myrawpower:>40] Claw
```

**Child Macro Behavior:** `/firstaction` and `/nofirstaction` in child macros (called via `{MacroName}`) affect subsequent lines in the parent macro. Think of the child's lines as being "inlined" at the call site.

**Comparison:**
- `/stopmacro [cond]` - Stop if condition is true (regardless of cast success)
- `/skipmacro [cond]` - Stop current submacro only
- `/firstaction [cond]` - Stop on first **successful** cast/use (priority mode)
- `/nofirstaction [cond]` - Re-enable multi-queue behavior after `/firstaction`

### Commands without Conditional Support

| Command | Description |
|---------|-------------|
| `/retarget` | Clear invalid target, target nearest enemy |
| `/runmacro Name` | Execute macro by name (use `{MacroName}` in `/cast` for conditionals) |
| `/rl` | Reload UI |

### UnitXP 3D Enemy Scanning

`/target` with any conditionals automatically uses UnitXP 3D scanning to find enemies in line of sight, even without nameplates visible. The only exception is `[help]` without `[harm]` (friendly-only targeting).

```lua
/target [name:Onyxia]           -- Scans for exact name match
/target [nodead,harm]           -- Scans for living enemies
/target [hp:<30]                -- Scans for low HP enemies
/target [cc:stun]               -- Scans for stunned enemies

-- Kara 40 Mage Incantagos example --
/target [name:Red_Affinity]
/cast [name:Red_Affinity] Fireball
/target [name:Blue_Affinity]
/cast [name:Blue_Affinity] Frostbolt
/target [name:Mana_Affinity]
/cast [name:Mana_Affinity] Arcane Missiles
```

If no matching target is found, your original target is preserved.

---

## Features

### Debuff Timer System
Auto-learns debuff durations from your casts. 335+ spells pre-configured.
```lua
/cast [nodebuff:Moonfire] Moonfire   -- Apply if missing
/cast [debuff:Moonfire<4] Moonfire   -- Refresh if < 4 sec left
/cast Wrath                          -- Filler
```

### Combo Point Tracking
Tracks finisher durations (Rip, Rupture, Kidney Shot) accounting for combo points spent.

### Talent & Equipment Modifiers
Automatically adjusts tracked durations for talents (Imp. Gouge, Taste for Blood, etc.) and equipment (Idol of Savagery).

### Special Mechanics (TWoW)
- **Carnage** (Druid): Detects Rip/Rake refresh from Ferocious Bite proc
- **Molten Blast** (Shaman): Flame Shock refresh detection
- **Conflagrate** (Warlock): Immolate reduction tracking
- **Dark Harvest** (Warlock): DoT acceleration compensation

---

## Immunity Tracking Guide

The addon auto-learns NPC immunities from combat. When a spell fails with "immune", the addon remembers it for that NPC.

### Using `[noimmune]`

| Usage | What it checks |
|-------|----------------|
| `[noimmune]` | Auto-detects spell's school from action |
| `[noimmune:fire]` | Fire immunity specifically |
| `[noimmune:bleed]` | Bleed immunity specifically |
| `[noimmune:stun]` | Stun CC immunity |

### Common Examples

```lua
-- Fire Mage: Skip immune targets
/cast [noimmune] Fireball

-- Warlock: Check shadow immunity
/cast [noimmune:shadow] Corruption

-- Rogue: Skip stun-immune targets
/cast [noimmune:stun] Cheap Shot
/cast Sinister Strike

-- Druid: Check fear immunity for Hibernate
/cast [noimmune:sleep,type:Beast/Dragonkin] Hibernate
```

### Split Damage Spells (Rake, Pounce, Garrote)

These spells have an initial physical hit + a bleed DoT. The addon **automatically checks BOTH immunities**:

```lua
-- Checks both physical AND bleed immunity
/cast [noimmune] Rake

-- With time check using Cursive
/cast [noimmune, cursive:Rake<1.5] Rake

-- Multi-DoT rotation
/cast [noimmune, nocursive:Rake] Rake
/cast [noimmune, nocursive:Rip, combo:>=4] Rip
```

`[noimmune]` for these spells returns false (skip cast) if target is immune to **either** component. You can also check specific schools:
- `[noimmune:physical]` - only checks physical immunity
- `[noimmune:bleed]` - only checks bleed immunity

### Pure Bleed Spells (Rip, Rupture, Rend)

These are pure bleeds with no initial hit:

```lua
-- Rip (pure bleed)
/cast [noimmune, combo:>=4] Rip

-- Rupture (pure bleed)
/cast [noimmune, combo:>=4] Rupture
```

### Manually Adding Immunities

If you know an NPC is immune before fighting:
```lua
/cleveroid addimmune "Boss Name" bleed        -- Permanent bleed immunity
/cleveroid addimmune "Boss Name" fire "Shield" -- Fire immune only when buffed
/cleveroid addccimmune "Boss Name" stun       -- Permanent stun immunity
```

### Viewing Learned Immunities

```lua
/cleveroid listimmune           -- All school immunities
/cleveroid listimmune bleed     -- Only bleed immunities
/cleveroid listccimmune         -- All CC immunities
/cleveroid listccimmune stun    -- Only stun immunities
```

---

## Debuff Tracking Guide

### Built-in Tracking (`[debuff]`)

The addon checks debuffs on the target:

```lua
-- Basic: Only cast if target doesn't have Moonfire
/cast [nodebuff:Moonfire] Moonfire

-- Time check: Refresh when < 4 seconds left
/cast [debuff:Moonfire<4] Moonfire
```

**Notes:**
- Existence checks (`[nodebuff]`, `[debuff]`) detect ANY debuff on target
- Time-remaining checks (`[debuff:X<5]`) use internal tracking from your casts
- Shared debuffs (Sunder, Faerie Fire) are detected from any source

### Cursive Integration (`[cursive]`)

[Cursive](https://github.com/avitasia/Cursive) provides more accurate GUID-based tracking:

```lua
-- Check if target has Rake (any time remaining)
/cast [nocursive:Rake] Rake

-- Refresh when < 3 seconds remaining
/cast [cursive:Rake<3] Rake

-- Complex: Only if missing OR about to expire
/cast [nocursive:Rake>1.5] Rake
```

**Advantages of Cursive:**
- GUID-based (survives target switching)
- Tracks pending casts
- Works at debuff cap
- More accurate timing

### MonkeySpeed Integration (`[moving]`)

[MonkeySpeed](https://github.com/jrc13245/MonkeySpeed) provides accurate movement speed detection via SuperWoW's `UnitPosition` API:

```lua
-- Only cast if standing still
/cast [nomoving] Aimed Shot

-- Cast instant ability while moving
/cast [moving] Arcane Shot

-- Check speed percentage (100 = normal run speed)
/cast [moving:>100] Sprint    -- Already faster than normal
/cast [moving:<50] Escape Artist  -- Currently slowed

-- Combined with other conditionals
/cast [nomoving, harm] Aimed Shot
/cast [moving, harm] Arcane Shot
```

**Speed Reference:**
| Speed | Description |
|-------|-------------|
| `0` | Standing still |
| `100` | Normal run speed |
| `160` | Level 40 mount |
| `200` | Epic mount |

**Notes:**
- Basic `[moving]`/`[nomoving]` works without MonkeySpeed (position fallback)
- Speed comparisons (`[moving:>100]`) require MonkeySpeed addon
- Speed values vary with buffs/debuffs affecting movement

### Recommended DoT Macro Patterns

**Druid Feral (with Cursive):**
```lua
#showtooltip
/cast [noimmune, nocursive:Rake] Rake
```

**Druid Feral (without Cursive):**
```lua
#showtooltip
/cast [noimmune, nodebuff] Rake
```

**Warlock Multi-DoT:**
```lua
#showtooltip
/cast [noimmune:shadow, nodebuff] Corruption
```

**Rogue Rupture:**
```lua
#showtooltip
/cast [noimmune, nodebuff, combo:>=4] Rupture
```

---

## Settings

```lua
/cleveroid                      -- View settings
/cleveroid realtime 0|1         -- Instant updates (more CPU)
/cleveroid refresh 1-10         -- Update rate in Hz
/cleveroid debug 0|1            -- Debug messages
/cleveroid learn <id> <dur>     -- Manually set spell duration
/cleveroid forget <id|all>      -- Forget duration(s)
```

### Immunity Commands
```lua
/cleveroid listimmune [school]
/cleveroid addimmune "NPC" school [buff]
/cleveroid listccimmune [type]
/cleveroid addccimmune "NPC" type [buff]
```

### Combo Tracking
```lua
/combotrack show|clear|debug
```

---

## Supported Addons

**Unit Frames:** [pfUI](https://github.com/jrc13245/pfUI), LunaUnitFrames, XPerl, Grid, CT_UnitFrames, agUnitFrames, and more

**Action Bars:** Blizzard, [pfUI](https://github.com/jrc13245/pfUI), Bongos, Discord Action Bars

**Integrations:** SP_SwingTimer, TWThreat, TimeToKill, QuickHeal, Cursive (with mouseover support for DoT timer bars), ClassicFocus, SuperMacro, MonkeySpeed

> **Note:** For pfUI users, the [jrc13245/pfUI fork](https://github.com/jrc13245/pfUI) includes native SuperCleveRoidMacros integration for proper cooldown, icon, and tooltip display on conditional macros.

---

## Known Issues

- Unique macro names required (no blanks, duplicates, or spell names)
- Reactive abilities must be on action bars for detection
- HealComm requires MarcelineVQ's [LunaUnitFrames](https://github.com/MarcelineVQ/LunaUnitFrames) for SuperWoW compatibility

---

## Credits

Based on [CleverMacro](https://github.com/DanielAdolfsson/CleverMacro) and [Roid-Macros](https://github.com/DennisWG/Roid-Macros). Cursive integration by Avitasia.

MIT License
