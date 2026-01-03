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

### Modifiers & Player State
| Conditional | Example | Description |
|-------------|---------|-------------|
| `mod` | `[mod:alt/ctrl/shift]` | Modifier key pressed |
| `combat` | `[combat]` `[nocombat]` | In combat |
| `form/stance` | `[form:1]` `[stance:2]` | Shapeshift/stance |
| `stealth` | `[stealth]` | In stealth |
| `group` | `[group]` `[group:party/raid]` | In group type |
| `swimming` | `[swimming]` | Can use aquatic form |
| `resting` | `[resting]` | In rest area |
| `zone` | `[zone:"Ironforge"]` | Current zone |

### Resources
| Conditional | Example | Description |
|-------------|---------|-------------|
| `myhp` | `[myhp:<30]` | Player HP % |
| `mypower` | `[mypower:>50]` | Player mana/rage/energy % |
| `druidmana` | `[druidmana:>=500]` | Druid mana while shapeshifted |
| `combo` | `[combo:>=4]` | Combo points |

### Buffs & Debuffs
| Conditional | Example | Description |
|-------------|---------|-------------|
| `mybuff` | `[mybuff:"Name"<5]` | Player has buff (with time check) |
| `mydebuff` | `[mydebuff:"Name"]` | Player has debuff |
| `buff` | `[buff:"Name">#3]` | Target has buff (with stacks) |
| `debuff` | `[debuff:"Sunder">20]` | Target has debuff (with time) |
| `cursive` | `[cursive:Rake<3]` | Cursive addon tracking (more accurate) |

### Cooldowns & Casting
| Conditional | Example | Description |
|-------------|---------|-------------|
| `cooldown` | `[cooldown:"Spell"<5]` | CD remaining (ignores GCD) |
| `cdgcd` | `[cdgcd:"Spell">0]` | CD remaining (includes GCD) |
| `usable` | `[usable:"Spell"]` | Spell/item is usable |
| `reactive` | `[reactive:Overpower]` | Reactive ability available |
| `channeled` | `[channeled]` | Currently channeling |
| `channeltime` | `[channeltime:<0.5]` | Channel time remaining |
| `known` | `[known:"Spell">#2]` | Spell/talent known (with rank) |

### Target Checks
| Conditional | Example | Description |
|-------------|---------|-------------|
| `exists` | `[@mouseover,exists]` | Unit exists |
| `alive/dead` | `[alive]` `[dead]` | Alive or dead |
| `help/harm` | `[help]` `[harm]` | Friendly or hostile |
| `hp` | `[hp:<20]` | Target HP % |
| `class` | `[class:Warrior/Priest]` | Target class |
| `type` | `[type:Undead]` | Creature type |
| `targeting` | `[targeting:player]` | Unit targeting you |
| `casting` | `[casting:"Spell"]` | Unit casting spell |
| `party/raid` | `[party]` `[raid]` | Target in party/raid |
| `member` | `[member]` | Target in party OR raid |
| `hastarget/notarget` | `[notarget]` | Player has/doesn't have target |

### Range & Position
| Conditional | Example | Description |
|-------------|---------|-------------|
| `distance` | `[distance:<40]` | Distance in yards |
| `inrange` | `[inrange:"Spell"]` | In spell range |
| `meleerange` | `[meleerange]` | In melee range |
| `behind` | `[behind]` | Behind target |
| `insight` | `[insight]` | In line of sight |

### Equipment
| Conditional | Example | Description |
|-------------|---------|-------------|
| `equipped` | `[equipped:Daggers]` | Item/type equipped |
| `mhimbue/ohimbue` | `[mhimbue:Flametongue]` | Weapon imbue |

### CC & Immunity
| Conditional | Example | Description |
|-------------|---------|-------------|
| `cc` | `[cc:stun/fear]` | Target has CC effect |
| `mycc` | `[mycc:silence]` | Player has CC effect |
| `immune` | `[noimmune:fire]` `[noimmune:stun]` | School/CC immunity |

**CC Types:** stun, fear, root, snare, sleep, charm, polymorph, banish, horror, disorient, silence, disarm, daze, freeze, shackle

### Addon Integrations
| Conditional | Addon | Example |
|-------------|-------|---------|
| `swingtimer` | SP_SwingTimer | `[swingtimer:<15]` (% elapsed) |
| `threat` | TWThreat | `[threat:>80]` |
| `ttk/tte` | TimeToKill | `[ttk:<10]` `[tte:<5]` |
| `cursive` | Cursive | `[cursive:Rake>3]` |
| `noslamclip` | SP_SwingTimer | Warrior Slam optimization |

### Multiscan (Target Scanning)
Scans enemies and soft-casts without changing your target.
```lua
/cast [multiscan:nearest,nodebuff:Rake] Rake
/cast [multiscan:skull] Eviscerate
/cast [multiscan:markorder] Sinister Strike
```
**Priorities:** `nearest`, `farthest`, `highesthp`, `lowesthp`, `markorder`, `skull`, `cross`, `square`, `moon`, `triangle`, `diamond`, `circle`, `star`

---

## Slash Commands

| Command | Description |
|---------|-------------|
| `/cast [cond] Spell` | Cast with conditionals |
| `/use [cond] Item` | Use item by name/ID/slot |
| `/castsequence reset=X Spell1, Spell2` | Cast sequence |
| `/startattack` `/stopattack` | Auto-attack control |
| `/stopcasting` `/unqueue` | Stop cast / clear queue |
| `/equip` `/equipmh` `/equipoh` | Equip items |
| `/unshift` | Cancel shapeshift |
| `/cancelaura Name` | Cancel buff |
| `/target [@unit,cond]` | Target with conditionals |
| `/retarget` | Clear invalid, target nearest |
| `/quickheal` `/qh` | Smart heal (QuickHeal addon) |
| `/pet*` | Pet commands (attack, follow, wait, aggressive, defensive, passive) |

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
- Spells with parentheses must include rank: `Faerie Fire (Feral)(Rank 4)`
- Reactive abilities must be on action bars for detection
- HealComm requires MarcelineVQ's [LunaUnitFrames](https://github.com/MarcelineVQ/LunaUnitFrames) for SuperWoW compatibility

---

## Credits

Based on [CleverMacro](https://github.com/DanielAdolfsson/CleverMacro) and [Roid-Macros](https://github.com/DennisWG/Roid-Macros). Cursive integration by Avitasia.

MIT License
