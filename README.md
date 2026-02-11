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

## Known Issues

- Unique macro names required (no blanks, duplicates, or spell names)
- Reactive abilities must be on action bars for detection
- Debuff time-left conditionals only work on own debuffs unless pfUI libdebuff or Cursive has data
- HealComm requires MarcelineVQ's [LunaUnitFrames](https://github.com/MarcelineVQ/LunaUnitFrames) for SuperWoW compatibility
- Macro line length: 261 characters max (MacroLengthWarn extension prevents crashes)

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

| Syntax | Logic | Example | Meaning |
|--------|-------|---------|---------|
| `[buff:X/Y]` | OR | `[buff:Renew/Rejuvenation]` | Has Renew **or** Rejuvenation |
| `[buff:X&Y]` | AND | `[buff:Fortitude&Mark_of_the_Wild]` | Has Fort **and** MotW |
| `[nobuff:X/Y]` | NOR | `[nobuff:Renew/Rejuvenation]` | Missing **both** Renew **and** Rejuvenation |
| `[nobuff:X&Y]` | NAND | `[nobuff:Fortitude&Mark_of_the_Wild]` | Missing **at least one** of Fort or MotW |

> **De Morgan's Law:** Negation flips the operator. `no` + `/`(OR) → AND (must lack all). `no` + `&`(AND) → OR (must lack at least one).

**Multiple instances = AND between groups:**
```lua
[mybuff:X/Y mybuff:Z]  -- (has X OR Y) AND (has Z)
```

### Comparisons
```lua
[hp:>50]            -- Health above 50%
[hp:>20&<50]        -- Health between 20% and 50%
[buff:"Name"<5]     -- Less than 5 seconds remaining
[debuff:"Name">#3]  -- 3+ stacks (use # for stacks)
```

### Special Prefixes
| Prefix | Example | Description |
|:------:|---------|-------------|
| `!` | `!Attack` | Only use if not active |
| `?` | `?[equipped:Swords] Ability` | Hide from tooltip |
| `~` | `~Slow Fall` | Toggle buff on/off |

---

## Slash Commands

| Command | Cond | Example | Description |
|---------|:----:|---------|-------------|
| `/cast` | ✅ | `/cast [mod:alt] Frostbolt` | Cast spell |
| `/use` | ✅ | `/use [hp:<30] Healing Potion` | Use item by name/ID/slot |
| `/equip` | ✅ | `/equip [nocombat] Fishing Pole` | Equip item |
| `/target` | ✅ | `/target [harm,nodead]` | Target with UnitXP 3D scanning |
| `/castsequence` | ✅ | `/castsequence reset=3/target Spell1, Spell2` | Cast spells in sequence |
| `/castpet` | ✅ | `/castpet [combat] Claw` | Cast pet spell |
| `/startattack` | ✅ | `/startattack [harm]` | Start auto-attack |
| `/stopattack` | ✅ | `/stopattack [noothertag]` | Stop auto-attack |
| `/stopcasting` | ✅ | `/stopcasting [mycc:silence]` | Stop casting |
| `/unqueue` | ✅ | `/unqueue [mod:shift]` | Cancel queued spell (Nampower) |
| `/cleartarget` | ✅ | `/cleartarget [dead]` | Clear target |
| `/cancelaura` | ✅ | `/cancelaura [combat] Ice Block` | Cancel buff (alias: `/unbuff`) |
| `/unshift` | ✅ | `/unshift [myhp:<30]` | Cancel shapeshift form |
| `/stopmacro` | ✅ | `/stopmacro [nocombat]` | Stop ALL macro execution |
| `/skipmacro` | ✅ | `/skipmacro [nogroup]` | Stop current submacro only |
| `/firstaction` | ✅ | `/firstaction [group]` | Priority: stop on first successful `/cast` |
| `/nofirstaction` | ✅ | `/nofirstaction` | Re-enable multi-queue after `/firstaction` |
| `/quickheal` | ✅ | `/quickheal [combat]` | Smart heal (alias: `/qh`, requires QuickHeal) |
| `/petattack` | ✅ | `/petattack [harm]` | Pet attack |
| `/petfollow` | ✅ | `/petfollow [nocombat]` | Pet follow |
| `/petwait` | ✅ | `/petwait [mod:ctrl]` | Pet stay |
| `/petpassive` | ✅ | `/petpassive` | Pet passive mode |
| `/petdefensive` | ✅ | `/petdefensive` | Pet defensive mode |
| `/petaggressive` | ✅ | `/petaggressive [group]` | Pet aggressive mode |
| `/equipmh` | ✅ | `/equipmh [nocombat] Dagger` | Equip to main hand |
| `/equipoh` | ✅ | `/equipoh [nocombat] Dagger` | Equip to off hand |
| `/equip11`-`14` | ✅ | `/equip13 [combat] Trinket` | Equip to ring/trinket slot |
| `/applymain` | ✅ | `/applymain [nomhimbue] Instant Poison` | Apply poison/oil to main hand |
| `/applyoff` | ✅ | `/applyoff [noohimbue] Crippling Poison` | Apply poison/oil to off hand |
| `/retarget` | — | `/retarget` | Clear invalid target, target nearest enemy |
| `/runmacro` | — | `/runmacro MyMacro` | Execute macro by name |
| `/rl` | — | `/rl` | Reload UI |
| `/clearequipqueue` | — | `/clearequipqueue` | Clear equipment swap queue |
| `/equipqueuestatus` | — | `/equipqueuestatus` | Show equipment queue status |

### Priority-Based Macro Evaluation

By default, all `/cast` lines evaluate and may queue spells with Nampower. `/firstaction` enables "first successful cast wins" mode.

```lua
/firstaction
/cast [myrawpower:>48] Shred      -- Priority: only one of these
/cast [myrawpower:>40] Claw
/nofirstaction
/cast Tiger's Fury                -- Always evaluates alongside
/startattack
```

`/firstaction [cond]` accepts conditionals. Child macros (via `{MacroName}`) inherit priority state.

### UnitXP 3D Enemy Scanning

`/target` with any conditionals automatically uses UnitXP 3D scanning to find enemies in line of sight. Exception: `[help]` without `[harm]` (friendly-only). If no match is found, your original target is preserved.

```lua
/target [name:Onyxia]       -- Scan for exact name
/target [nodead,harm]       -- Scan for living enemies
/target [cc:stun]           -- Scan for stunned enemies
```

---

## Conditionals Reference

All conditionals support negation with `no` prefix unless noted. Some have semantic opposites: `help`/`harm`, `alive`/`dead`, `isplayer`/`isnpc`, `inrange`/`outrange`.

**Table columns:**
- **Description** — what the conditional checks
- **No** — supports `no` prefix negation
- **Multi** — supports multi-value OR (`/`), AND (`&`), or comparison operators (`>`, `<`, `>=`, `<=`, `=`, `~=`)
- **NP** — minimum Nampower version required
- **Addon** — addon required or recommended

### Player Conditionals (@player)

These always evaluate against the player. Cannot be redirected with `@unit`.

| Conditional | Description | No | Multi | Example | NP | Addon |
|-------------|-------------|:--:|:-----:|---------|:--:|-------|
| ***State & Modifiers*** | | | | | | |
| `mod` | Modifier key pressed | ✅ | ✅ | `[mod:alt/ctrl]` | | |
| `combat` | In combat (player default, or unit) | ✅ | ✅ | `[combat]` `[combat:target]` | | |
| `form` / `stance` | Shapeshift form or stance index | ✅ | ✅ | `[form:1/3]` `[stance:2]` | | |
| `stealth` | In stealth (Rogue/Druid) | ✅ | — | `[stealth]` | | |
| `group` | Player is in group type | ✅ | ✅ | `[group:party/raid]` | | |
| `resting` | In rest area | ✅ | — | `[resting]` | | |
| `swimming` | Swimming | ✅ | — | `[swimming]` | | |
| `moving` | Moving / speed % | ✅ | ✅ | `[moving]` `[moving:>100&<200]` | | MonkeySpeed (speed %) |
| `zone` | Current zone name | ✅ | ✅ | `[zone:Ironforge/Stormwind]` | | |
| ***Resources*** | | | | | | |
| `myhp` | Player HP % | — | ✅ | `[myhp:<30]` `[myhp:>20&<50]` | | |
| `myrawhp` | Player raw HP value | — | ✅ | `[myrawhp:>1000]` | | |
| `myhplost` | Player HP deficit (max - current) | — | ✅ | `[myhplost:>500]` | | |
| `mypower` | Player mana/rage/energy % | — | ✅ | `[mypower:>50]` | | |
| `myrawpower` | Player raw power value | — | ✅ | `[myrawpower:>=40]` | | |
| `mypowerlost` | Player power deficit | — | ✅ | `[mypowerlost:>200]` | | |
| `druidmana` | Druid mana while shapeshifted | — | ✅ | `[druidmana:>=500]` | | |
| `combo` | Combo points | ✅ | ✅ | `[combo:>=4]` | | |
| `stat` | Player stat value | ✅ | ✅ | `[stat:agi>100]` `[stat:ap>1000]` | | |
| `mylevel` | Player level | — | ✅ | `[mylevel:=60]` | | |
| ***Player Auras*** | | | | | | |
| `mybuff` | Player has buff (with time/stacks) | ✅ | ✅ | `[mybuff:Thorns<5]` `[nomybuff:MotW/GotW]` | | |
| `mydebuff` | Player has debuff (with time/stacks) | ✅ | ✅ | `[mydebuff:Curse_of_Agony]` | | |
| `mybuffcount` | Player buff slot count (32 max) | ✅ | ✅ | `[mybuffcount:>15]` `[nomybuffcount:>28]` | | |
| `mybuffcapped` | Player buff bar full (32) | ✅ | — | `[nomybuffcapped]` | v2.20 | |
| `mydebuffcapped` | Player debuff bar full (16) | ✅ | — | `[nomydebuffcapped]` | v2.20 | |
| `mycc` | Player has CC effect | ✅ | ✅ | `[mycc:stun/silence]` `[nomycc]` | | |
| ***Spells & Cooldowns*** | | | | | | |
| `cooldown` | Spell/item CD remaining (ignores GCD) | ✅ | ✅ | `[cooldown:Sprint<5]` | | |
| `cdgcd` | Spell/item CD remaining (includes GCD) | ✅ | ✅ | `[cdgcd:Sprint>0]` | | |
| `gcd` | GCD is active / time remaining | ✅ | ✅ | `[gcd]` `[gcd:<1]` | | |
| `usable` | Spell/item is usable now | ✅ | ✅ | `[usable:Overpower]` | | |
| `reactive` | Reactive ability available (on bar) | ✅ | ✅ | `[reactive:Overpower]` | | |
| `known` | Spell/talent known (with rank) | ✅ | ✅ | `[known:Berserk]` `[known:Frostbolt>#2]` | | |
| `selfcasting` | Player is casting or channeling | ✅ | ✅ | `[selfcasting]` `[noselfcasting:Hearthstone]` | | |
| `checkcasting` | True if NOT casting (specific spell) | — | ✅ | `[checkcasting]` `[checkcasting:Frostbolt]` | | |
| `channeled` | Player is channeling | ✅ | ✅ | `[channeled]` `[channeled:Arcane_Missiles]` | | |
| `checkchanneled` | True if NOT channeling (specific spell) | — | ✅ | `[checkchanneled]` `[checkchanneled:Evocation]` | | |
| `spellcasttime` | Spell cast time from tooltip (real-time) | ✅ | ✅ | `[spellcasttime:>1.5]` `[spellcasttime:Frostbolt<2]` | | |
| `queuedspell` | Spell is queued | ✅ | ✅ | `[queuedspell]` `[queuedspell:Fireball]` | v2.12 | |
| `onswingpending` | On-swing spell pending | ✅ | — | `[onswingpending]` | v2.12 | |
| ***Equipment*** | | | | | | |
| `equipped` | Item or weapon type equipped | ✅ | ✅ | `[equipped:Daggers/Swords]` | | |
| `mhimbue` | Main hand has temporary imbue | ✅ | ✅ | `[mhimbue:Instant_Poison<300]` `[mhimbue:>#5]` | | |
| `ohimbue` | Off hand has temporary imbue | ✅ | ✅ | `[noohimbue]` `[ohimbue:Crippling_Poison]` | | |
| `pet` | Has active pet (with family) | ✅ | ✅ | `[pet]` `[pet:Cat/Wolf]` | | |
| ***Melee Tracking*** | | | | | | |
| `lastswing` | Player melee swing type/timing | ✅ | ✅ | `[lastswing:dodge]` `[lastswing:<2]` | v2.24 | |
| `incominghit` | Incoming attack type/timing | ✅ | ✅ | `[incominghit:crushing]` `[noincominghit:crit]` | v2.24 | |
| `swingtimer` | Swing timer % elapsed | ✅ | ✅ | `[swingtimer:>80]` | | SP_SwingTimer |
| `stimer` | Alias for swingtimer | ✅ | ✅ | `[stimer:<15]` | | SP_SwingTimer |
| `slamclip` / `noslamclip` | Slam now will/won't clip auto-attack | ✅ | — | `[noslamclip]` | | SP_SwingTimer |
| `nextslamclip` / `nonextslamclip` | Instant now will/won't cause next Slam to clip | ✅ | — | `[nonextslamclip]` | | SP_SwingTimer |
| ***Target Existence*** | | | | | | |
| `hastarget` | Player has a target | — | — | `[hastarget]` | | |
| `notarget` | Player has no target | — | — | `[notarget]` | | |

### Target Conditionals (default @target)

These default to checking the current target. Most can be redirected with `@unit` (e.g., `[@focus,hp:<30]`, `[@mouseover,exists]`).

| Conditional | Description | No | Multi | Example | NP | Addon |
|-------------|-------------|:--:|:-----:|---------|:--:|-------|
| ***Existence & Disposition*** | | | | | | |
| `exists` | Unit exists | ✅ | — | `[@mouseover,exists]` | | |
| `alive` | Unit is alive | ✅ | — | `[alive]` | | |
| `dead` | Unit is dead | ✅ | — | `[dead]` | | |
| `help` | Unit is friendly | ✅ | — | `[help]` | | |
| `harm` | Unit is hostile | ✅ | — | `[harm]` | | |
| `isplayer` | Unit is a player | ✅ | — | `[isplayer]` | | |
| `isnpc` | Unit is an NPC | ✅ | — | `[isnpc]` | | |
| ***Resources*** | | | | | | |
| `hp` | Target HP % | — | ✅ | `[hp:<20]` `[hp:>30&<70]` | | |
| `rawhp` | Target raw HP value | — | ✅ | `[rawhp:>5000]` | | |
| `hplost` | Target HP deficit (max - current) | — | ✅ | `[hplost:>1000]` | | |
| `power` | Target mana/rage/energy % | — | ✅ | `[power:<30]` | | |
| `rawpower` | Target raw power value | — | ✅ | `[rawpower:>500]` | | |
| `powerlost` | Target power deficit | — | ✅ | `[powerlost:>100]` | | |
| `powertype` | Target power type | ✅ | ✅ | `[powertype:mana/rage]` | | |
| `level` | Target level (skull = 63) | — | ✅ | `[level:>60]` | | |
| ***Classification*** | | | | | | |
| `class` | Target class (players only) | ✅ | ✅ | `[class:Warrior/Priest]` | | |
| `type` | Creature type | ✅ | ✅ | `[type:Undead/Beast]` | | |
| `name` | Exact name match (case-insensitive) | ✅ | ✅ | `[name:Onyxia]` `[noname:Critter/Dummy]` | | |
| ***Target Auras*** | | | | | | |
| `buff` | Target has buff (with time/stacks) | ✅ | ✅ | `[buff:Shield>#3]` `[nobuff:Renew/Rejuv]` | | |
| `debuff` | Target has debuff (with time/stacks) | ✅ | ✅ | `[debuff:Moonfire<4]` `[nodebuff:Rake]` | | |
| `buffcapped` | Target buff bar full (32) | ✅ | — | `[nobuffcapped]` | v2.20 | |
| `debuffcapped` | Target debuff bar full | ✅ | — | `[nodebuffcapped]` | v2.20 | |
| `cc` | Target has CC effect | ✅ | ✅ | `[cc:stun/fear]` `[nocc:polymorph]` | | |
| `cursive` | GUID-based debuff tracking (time remaining) | ✅ | ✅ | `[cursive:Rake<3]` `[nocursive:Rip]` | | Cursive |
| ***Casting*** | | | | | | |
| `casting` | Target is casting (specific spell) | ✅ | ✅ | `[casting]` `[casting:Heal]` | | |
| `casttime` | Target cast time remaining (seconds) | ✅ | ✅ | `[casttime:<0.5]` | | |
| `channeltime` | Target channel time remaining (seconds) | ✅ | ✅ | `[channeltime:<0.5]` | | |
| ***Relationship*** | | | | | | |
| `party` | Unit is in your party | ✅ | ✅ | `[party]` `[party:focus]` | | |
| `raid` | Unit is in your raid | ✅ | ✅ | `[raid]` `[raid:mouseover]` | | |
| `member` | Target is in party or raid | ✅ | — | `[member]` | | |
| `targeting` | Unit is targeting you or a tank | ✅ | ✅ | `[targeting:player]` `[notargeting:tank]` | | pfUI (for tank) |
| `istank` | Unit is marked as tank | ✅ | — | `[istank]` `[@focus,istank]` | | pfUI |
| `tag` | Target is tapped by anyone | ✅ | — | `[tag]` `[notag]` | | |
| `mytag` | Target is tapped by you | ✅ | — | `[mytag]` `[nomytag]` | | |
| `othertag` | Target is tapped by someone else | ✅ | — | `[othertag]` `[noothertag]` | | |
| ***Range & Position*** | | | | | | |
| `distance` | Distance in yards | ✅ | ✅ | `[distance:<40]` | | UnitXP_SP3 |
| `meleerange` | In melee range / count in melee | ✅ | ✅ | `[meleerange]` `[meleerange:>1]` | | UnitXP_SP3 |
| `inrange` | In spell range / count in range | ✅ | ✅ | `[inrange:Charge]` `[inrange:Multi-Shot>1]` | | UnitXP_SP3 (count) |
| `outrange` | Out of spell range / count out | ✅ | ✅ | `[outrange:Charge]` `[outrange:Charge>0]` | | UnitXP_SP3 (count) |
| `insight` | In line of sight / count in LoS | ✅ | ✅ | `[insight]` `[insight:>0]` | | UnitXP_SP3 |
| `behind` | Behind target / count behind | ✅ | ✅ | `[behind]` `[behind:>=2]` | | UnitXP_SP3 |
| `multiscan` | Scan enemies by priority, soft-cast | — | ✅ | `[multiscan:nearest]` `[multiscan:skull]` | | UnitXP_SP3 |
| ***Immunity*** | | | | | | |
| `immune` | Target is immune (school or CC type) | ✅ | ✅ | `[noimmune:fire]` `[noimmune:stun]` | | |
| `resisted` | Last spell was resisted | ✅ | ✅ | `[resisted]` `[resisted:full/partial]` | | |
| ***Addon Integrations*** | | | | | | |
| `threat` | Threat % on target (100 = pull) | ✅ | ✅ | `[threat:>80]` | | TWThreat |
| `ttk` | Time to kill target (seconds) | ✅ | ✅ | `[ttk:<10]` | | TimeToKill |
| `tte` | Time to execute threshold (seconds) | ✅ | ✅ | `[tte:<5]` | | TimeToKill |

### Multi-Unit Count Mode

Range and position conditionals (`meleerange`, `behind`, `insight`, `inrange`, `outrange`) support counting enemies when given an operator + number. Requires UnitXP_SP3. Operators: `>`, `<`, `>=`, `<=`, `=`, `~=`

```lua
/cast [meleerange:>1] Whirlwind           -- AoE if 2+ enemies in melee
/cast [behind:>=2] Blade Flurry           -- Cleave if behind 2+ enemies
/cast [inrange:Multi-Shot>1] Multi-Shot   -- AoE if 2+ in spell range
/cast [insight:>0] Arcane Explosion       -- AoE if any enemy in LoS
```

### Multiscan (Target Scanning)

Scans enemies and soft-casts without changing your target. Requires UnitXP_SP3. Scanned targets must be in combat with player (exceptions: current target and `@unit` specified in macro).

| Priority | Description |
|----------|-------------|
| `nearest` | Closest enemy |
| `farthest` | Farthest enemy |
| `highesthp` / `lowesthp` | Highest/lowest HP % |
| `highestrawhp` / `lowestrawhp` | Highest/lowest raw HP |
| `markorder` | First mark in kill order (skull→cross→square→moon→triangle→diamond→circle→star) |
| `skull` `cross` `square` `moon` `triangle` `diamond` `circle` `star` | Specific raid mark |

```lua
/cast [multiscan:nearest,nodebuff:Rake] Rake
/cast [multiscan:skull,harm] Eviscerate
/cast [multiscan:nearest,notargeting:tank,harm] Taunt
```

### Reference Tables

**CC Types** (for `[cc]`, `[mycc]`, `[immune]`):

| Type | Examples |
|------|----------|
| `stun` | Cheap Shot, Kidney Shot, HoJ, Bash, Gouge, Sap |
| `fear` | Fear, Psychic Scream, Howl of Terror |
| `root` | Entangling Roots, Frost Nova |
| `snare` / `slow` | Hamstring, Wing Clip, Crippling Poison |
| `sleep` | Hibernate, Wyvern Sting |
| `charm` | Mind Control, Seduction |
| `polymorph` | Polymorph (all variants) |
| `banish` | Banish |
| `horror` | Death Coil, Intimidating Shout |
| `disorient` | Scatter Shot, Blind |
| `silence` | Silence, Counterspell |
| `disarm` | Disarm |
| `daze` | Daze effects |
| `freeze` | Freeze effects |
| `shackle` | Shackle Undead |

**Loss-of-control** (checked by bare `[cc]`): stun, fear, sleep, charm, polymorph, banish, horror, freeze, disorient, shackle

**Damage Schools** (for `[immune]`): physical, fire, frost, nature, shadow, arcane, holy, bleed

**Swing/Hit Types** (for `[lastswing]`, `[incominghit]`):

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

**Stat Types** (for `[stat]`): `str`, `agi`, `stam`, `int`, `spi`, `ap`, `rap`, `healing`, `spell_power` (highest across all schools), `arcane_power`, `fire_power`, `frost_power`, `nature_power`, `shadow_power`, `armor`, `defense`, `arcane_res`, `fire_res`, `frost_res`, `nature_res`, `shadow_res`

**Aura Capacity:** Player: 32 buffs, 16 debuffs. NPCs: 16 debuff slots + 32 overflow = 48 total.

**Speed Reference** (for `[moving:>N]`): 0 = still, 100 = run, 160 = mount, 200 = epic mount.

---

## Features

### Debuff Timer System
Auto-learns debuff durations from your casts. 335+ spells pre-configured.
```lua
/cast [nodebuff:Moonfire] Moonfire   -- Apply if missing
/cast [debuff:Moonfire<4] Moonfire   -- Refresh if < 4 sec left
/cast Wrath                          -- Filler
```

**Notes:**
- Existence checks (`[nodebuff]`, `[debuff]`) detect ANY debuff on target
- Time-remaining checks (`[debuff:X<5]`) use internal tracking from your casts
- Shared debuffs (Sunder, Faerie Fire) are detected from any source
- [Cursive](https://github.com/pepopo978/Cursive) provides GUID-based tracking with better accuracy (handles target switching, pending casts, debuff cap)

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

## Immunity Tracking

Auto-learns NPC immunities from combat. When a spell fails with "immune", the addon remembers it for that NPC.

### Using `[noimmune]`

| Usage | What it checks |
|-------|----------------|
| `[noimmune]` | Auto-detects spell's school from action |
| `[noimmune:fire]` | Fire immunity specifically |
| `[noimmune:bleed]` | Bleed immunity specifically |
| `[noimmune:stun]` | Stun CC immunity |

**Split damage spells** (Rake, Pounce, Garrote) have initial physical hit + bleed DoT. `[noimmune]` automatically checks **both** components.

```lua
/cast [noimmune] Rake                    -- Checks physical AND bleed
/cast [noimmune:stun] Cheap Shot         -- Checks stun immunity
/cast [noimmune:shadow] Corruption       -- Checks shadow immunity
```

### Manual Immunity Commands
```lua
/cleveroid addimmune "Boss Name" bleed          -- Permanent immunity
/cleveroid addimmune "Boss Name" fire "Shield"  -- Conditional (while buffed)
/cleveroid addccimmune "Boss Name" stun         -- CC immunity
/cleveroid listimmune [school]                  -- View school immunities
/cleveroid listccimmune [type]                  -- View CC immunities
```

---

## Settings

```lua
/cleveroid                          -- View settings
/cleveroid realtime 0|1             -- Instant tooltip updates (more CPU)
/cleveroid refresh 1-10             -- Tooltip update rate in Hz
/cleveroid debug 0|1                -- Debug messages
/cleveroid learn <spellID> <dur>    -- Manually set spell duration
/cleveroid forget <spellID|all>     -- Forget learned duration(s)
/cleveroid debuffdebug [spell]      -- Debug debuff tracking on target
/cleveroid tankdebug                -- Debug pfUI tank conditionals
/combotrack show|clear|debug        -- Combo point tracking
```

---

## Supported Addons

**Unit Frames:** [pfUI](https://github.com/jrc13245/pfUI), LunaUnitFrames, XPerl, Grid, CT_UnitFrames, agUnitFrames, and more

**Action Bars:** Blizzard, [pfUI](https://github.com/jrc13245/pfUI), Bongos, Discord Action Bars

**Integrations:** [SP_SwingTimer](https://github.com/jrc13245/SP_SwingTimer), [TWThreat](https://github.com/MarcelineVQ/TWThreat), [TimeToKill](https://github.com/jrc13245/TimeToKill), [QuickHeal](https://github.com/jrc13245/QuickHeal), [Cursive](https://github.com/pepopo978/Cursive), [ClassicFocus](https://github.com/wtfcolt/Addons-for-Vanilla-1.12.1-CFM/tree/master/ClassicFocus), [SuperMacro](https://github.com/jrc13245/SuperMacro-turtle-SuperWoW), [MonkeySpeed](https://github.com/jrc13245/MonkeySpeed)

> **Note:** For pfUI users, the [jrc13245/pfUI fork](https://github.com/jrc13245/pfUI) includes native SuperCleveRoidMacros integration for proper cooldown, icon, and tooltip display on conditional macros.

---

## Credits

Based on [CleverMacro](https://github.com/DanielAdolfsson/CleverMacro) and [Roid-Macros](https://github.com/DennisWG/Roid-Macros).

MIT License
