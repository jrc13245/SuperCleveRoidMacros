# SuperCleveRoid Macros

Enhanced macro addon for World of Warcraft 1.12.1 (Vanilla/Turtle WoW) with dynamic tooltips, conditional execution, and extended syntax.

## Requirements

| Mod | Required | Purpose |
|-----|:--------:|---------|
| [SuperWoW](https://github.com/balakethelock/SuperWoW/releases) | ✅ | Extended API (addon won't load without it) |
| [Nampower](https://gitea.com/avitasia/nampower/releases) (v2.23+) | ✅ | Spell queueing, DBC data access |
| [UnitXP_SP3](https://codeberg.org/konaka/UnitXP_SP3/releases) | ✅ | Distance checks, `[multiscan]` enemy scanning |

## Installation

1. Download and extract to `Interface/AddOns/SuperCleveRoidMacros`
2. **Disable conflicts:** pfUI MacroTweak, ShaguTweaks MacroTweak, pfUI "Scan Macros for spells"

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
| `mybuffcount` | `[mybuffcount:>15]` | Player buff slot count |
| `buff` | `[buff:"Name">#3]` | Target has buff (with stacks) |
| `debuff` | `[debuff:"Sunder">20]` | Target has debuff (with time) |
| `cursive` | `[cursive:Rake<3]` | Cursive addon tracking (GUID-based) |

### Cooldowns & Casting
| Conditional | Example | Description |
|-------------|---------|-------------|
| `cooldown` | `[cooldown:"Spell"<5]` | CD remaining (ignores GCD) |
| `cdgcd` | `[cdgcd:"Spell">0]` | CD remaining (includes GCD) |
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
| `mhimbue` | `[mhimbue:Flametongue]` | Main-hand weapon imbue |
| `ohimbue` | `[ohimbue:Frostbrand]` | Off-hand weapon imbue |

### CC & Immunity
| Conditional | Example | Description |
|-------------|---------|-------------|
| `cc` | `[cc]` `[cc:stun/fear]` | Target has CC effect |
| `mycc` | `[mycc]` `[mycc:silence]` | Player has CC effect |
| `immune` | `[immune:fire]` `[immune:stun]` | School/CC immunity |
| `resisted` | `[resisted]` `[resisted:full/partial]` | Last spell was resisted |

**CC Types:** stun, fear, root, snare/slow, sleep, charm, polymorph, banish, horror, disorient, silence, disarm, daze, freeze, shackle

**Loss-of-control** (checked by bare `[cc]`): stun, fear, sleep, charm, polymorph, banish, horror, freeze, disorient, shackle

### Addon Integrations
| Conditional | Addon | Example | Description |
|-------------|-------|---------|-------------|
| `swingtimer` | SP_SwingTimer | `[swingtimer:<15]` | Swing % elapsed |
| `stimer` | SP_SwingTimer | `[stimer:>80]` | Alias for swingtimer |
| `threat` | TWThreat | `[threat:>80]` | Threat % (100=pull) |
| `ttk` | TimeToKill | `[ttk:<10]` | Time to kill (seconds) |
| `tte` | TimeToKill | `[tte:<5]` | Time to execute (20% HP) |
| `cursive` | Cursive | `[cursive:Rake>3]` | GUID debuff tracking |

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
| `/stopmacro [cond]` | ✅ | — | Stop macro execution if conditions met |
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
/cast [name:Red_Affinity]Fireball
/target [name:Blue_Affinity]
/cast [name:Blue_Affinity]Frostbolt
/target [name:Mana_Affinity]
/cast [name:Mana_Affinity]Arcane Missiles
```

If no matching target is found, your original target is preserved.

---

## Features

### Debuff Timer System
Auto-learns debuff durations from your casts. 335+ spells pre-configured.
```lua
/cast [nodebuff:Moonfire] Moonfire
/cast [debuff:Moonfire<4] Moonfire
/cast Wrath
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

**Unit Frames:** pfUI, LunaUnitFrames, XPerl, Grid, CT_UnitFrames, agUnitFrames, and more

**Action Bars:** Blizzard, pfUI, Bongos, Discord Action Bars

**Integrations:** SP_SwingTimer, TWThreat, TimeToKill, QuickHeal, Cursive, ClassicFocus, SuperMacro

---

## Known Issues

- Unique macro names required (no blanks, duplicates, or spell names)
- Reactive abilities must be on action bars for detection
- HealComm requires MarcelineVQ's [LunaUnitFrames](https://github.com/MarcelineVQ/LunaUnitFrames) for SuperWoW compatibility

---

## Credits

Based on [CleverMacro](https://github.com/DanielAdolfsson/CleverMacro) and [Roid-Macros](https://github.com/DennisWG/Roid-Macros). Cursive integration by Avitasia.

MIT License
