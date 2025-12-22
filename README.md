# SuperCleveRoid Macros

An enhanced macro addon for World of Warcraft 1.12.1 (Vanilla) that provides dynamic tooltips, conditional execution, and extended syntax. Originally based on [CleverMacro](https://github.com/DanielAdolfsson/CleverMacro) and [Roid-Macros](https://github.com/MarcelineVQ/Roid-Macros) with significant expansions.

## Required DLL Mods

**ALL THREE ARE MANDATORY:**
- [SuperWoW](https://github.com/balakethelock/SuperWoW/releases/tag/Release) - Extended API functions
- [Nampower](https://gitea.com/avitasia/nampower/releases) - Spell queueing and range checking
- [UnitXP_SP3](https://codeberg.org/konaka/UnitXP_SP3/releases) - Distance/positioning checks

The addon will not function without all three DLL mods installed.

---

## Installation

1. Download from the green Code button or [click here](https://github.com/jrc13245/SuperCleveRoidMacros/archive/refs/heads/main.zip)
2. Unzip and place folder into `Interface/Addons`
3. Rename `SuperCleveRoidMacros-main` to `SuperCleveRoidMacros`
4. Verify it's enabled in your addon list in-game
5. **Disable conflicts:**
   - Disable MacroTweak module in pfUI
   - Disable MacroTweak in ShaguTweaks
   - Disable "Scan Macros for spells" in pfUI actionbar settings

---

## Settings & Commands

### Basic Settings
```lua
/cleveroid                    -- View current settings
/cleveroid realtime 0|1       -- Toggle realtime updates (Default: 0, increases CPU load)
/cleveroid refresh 1-10       -- Set refresh rate in Hz (Default: 5)
```

### Debuff Duration Learning
```lua
/cleveroid learn <spellID> <duration>  -- Manually set spell duration
/cleveroid forget <spellID|all>        -- Forget learned duration(s)
/cleveroid debug 0|1                   -- Toggle learning debug messages
```

### Immunity Tracking
```lua
/cleveroid listimmune [school]              -- List immunities
/cleveroid addimmune "<NPC>" <school> [buff] -- Add immunity
/cleveroid removeimmune "<NPC>" <school>    -- Remove immunity
/cleveroid clearimmune [school]             -- Clear immunity data
```

### Talent & Equipment Testing
```lua
/cleveroid talenttabs                  -- Show talent tab IDs
/cleveroid listtab <tab>               -- List talents in a tab
/cleveroid talents                     -- Show current talent ranks
```

### Combo Point Tracking
```lua
/combotrack show    -- Display tracking data
/combotrack clear   -- Clear all tracking data
/combotrack debug   -- Toggle debug output
```

---

## Known Issues

- **Event-based updates:** By default (realtime=0), conditionals like `@unitid` and `mod` update on events. Enable realtime for instant updates (increases CPU usage).
- **Unique macro names:** All macros must have unique names - no blanks, duplicates, or spell names or special characters.
- **Parenthesis in spell names:** Must include rank - `Faerie Fire (Feral)(Rank 4)` NOT `Faerie Fire (Feral)`.
- **Reactive abilities:** Revenge, Overpower, etc. must be on action bars for detection.
- **HealComm support:** See [HealComm Support](#healcomm-support) section.

---

# Macro Syntax Guide

## Basic Rules

### **Spells/items are case sensitive!**

### Spell and Item Names
- **Spaces:** Use underscores OR quotes
  - `Mark_of_the_Wild` OR `"Mark of the Wild"`
- **Ranks:** Must include full rank syntax
  - ✅ `Faerie Fire (Feral)(Rank 4)`
  - ❌ `Faerie Fire (Feral)`

### Conditional Structure
- **Format:** `[conditional1 conditional2] Action`
- **Evaluation:** Left to right, top to bottom
- **First match wins:** First action where ALL conditionals pass
- **Separators:** Space or comma
  - `[mod:alt harm alive]` = `[mod:alt,harm,alive]`

### Conditional Arguments
- **Colon required:** Use `:` to pass arguments to conditionals
  - ✅ `[mod:alt]` - Correct (argument provided)
  - ✅ `[hp:>50]` - Correct (argument provided)
  - ✅ `[harm]` - Correct (no argument needed)
  - ❌ `[mod alt]` - Wrong (missing colon)
  - ❌ `[hp>50]` - Wrong (missing colon)

### Line Formats
Both formats work identically:

**Multi-line:**
```lua
#showtooltip
/cast [mod:alt] Frostbolt
/cast [mod:ctrl] Fire Blast
/cast Blink
```

**Single-line:**
```lua
#showtooltip
/cast [mod:alt] Frostbolt; [mod:ctrl] Fire Blast; Blink
```

### Target Specification
```lua
/cast [@party1 combat] Intervene  -- Targets party1, checks if player in combat
```
- **Syntax:** `[@unitid]` at start of conditionals
- **Default:** Most conditionals default to `@target`

### Multi-Value Conditionals

#### Separators: `/` for OR, `&` for AND
```lua
[zone:Stormwind_City/Ironforge]              -- In Stormwind OR Ironforge (either)
[zone:Stormwind_City&Ironforge]              -- In Stormwind AND Ironforge (both - impossible, but illustrative)
```

#### Negated conditionals: Operators are FLIPPED for intuitive behavior
For `no*` conditionals, `/` and `&` work opposite to positive conditionals (De Morgan's law):
```lua
[nozone:Stormwind_City/Ironforge]            -- NOT in Stormwind AND NOT in Ironforge (not in either)
[nozone:Stormwind_City&Ironforge]            -- NOT in Stormwind OR NOT in Ironforge (not in at least one)
```

This matches natural language: `[nobuff:X/Y]` reads as "no X or Y" meaning "neither X nor Y".

#### Comma-separated same conditionals = AND (missing all)
```lua
[nomybuff:X, nomybuff:Y]                     -- Same as [nomybuff:X/Y] - missing both X AND Y
[mybuff:X, mybuff:Y]                         -- Same as [mybuff:X&Y] - has both X AND Y
```

#### More Examples
```lua
[nomybuff:Mark_of_the_Wild/Thorns]           -- Missing BOTH buffs (neither present)
[nomybuff:"Seal of Wisdom"&"Seal of Light"]  -- Missing at least one buff (not both present)
[nomybuff:"Mind Quickening", nomybuff:"Arcane Power"]  -- Missing both (comma = AND)
```


### Negation
Prefix with `no` to negate (marked as "Noable" in tables):
```lua
[nobuff]           -- Does NOT have buff
[nomod:alt]        -- Alt is NOT pressed
```

### Numerical Comparisons
```lua
[hp:>50]                                -- HP above 50%
[cooldown:"Spell Name"<5]               -- Less than 5 seconds remaining
[buff:"Mark of the Wild">#5]            -- 5+ stacks (use ># for stacks)
[mybuff:"Renew"<4]                      -- Less than 4 seconds remaining
```
- **Operators:** `<`, `>`, `=`, `<=`, `>=`, `~=`

### Omitting Values
If conditional value matches the action:
```lua
[debuff:<#5] Sunder Armor               -- Same as [debuff:"Sunder Armor"<#5]
[nobuff] Mark of the Wild               -- Same as [nobuff:"Mark of the Wild"]
```

### Item IDs
Use IDs to avoid cache issues:
```lua
#showtooltip
/use [nomod] 5350              -- Conjured Water
/cast [mod] Conjure Water
```

### Equipment Slots
Use slot numbers (1-19):
```lua
#showtooltip
/use [combat hp:<=20] 13       -- Use trinket in slot 13
/use 16                        -- Use main hand weapon
```

## Special Prefixes

| Prefix | Example | Description |
|:------:|---------|-------------|
| `!` | `!Attack`<br/>`!Cat Form` | Only use if not active<br/>Shorthand for `[nomybuff]` connected with an AND |
| `?` | `?[equipped:Swords] Ability` | Hides icon/tooltip<br/>Must be first character |
| `~` | `~Slow Fall` | Toggle buff on/off |

## Common Pitfalls

❌ **Cascading conditionals (NOT SUPPORTED):**
```lua
/use [@mouseover alive help hp:<70][@target alive help hp:<70][@player] Bandage
```

✅ **Correct format:**
```lua
/use [@mouseover alive help hp:<70] Bandage
/use [@target alive help hp:<70] Bandage
/use [@player] Bandage
```

---

# Features

## Dynamic Icons and Tooltips

Icons and tooltips automatically update to the first action with passing conditionals.

### #showtooltip Support
```lua
#showtooltip
/cast [mod:alt] Frostbolt
/cast [mod:ctrl] Fire Blast
/cast Blink
```

### With Explicit Icon
```lua
#showtooltip Fireball
/cast [mod] Conjure Food
/use 2288
```

### Channel Time Conditional
Recast channeled spells when time remaining is below threshold:
```lua
#showtooltip Arcane Missiles
/cast [channeltime:<0.5] Arcane Missiles
```
This will recast Arcane Missiles only when less than 0.5 seconds remain on the current channel, preventing early cancellation and maximizing damage.

### Macro References
Macro 1 shows Macro 2's icon when out of combat:
```lua
-- Macro 1
#showtooltip
/cast [nocombat] {Macro2}
/cast Fireball

-- Macro 2
#showtooltip Arcane Missiles
/cast [mod] Conjure Food
/use 2288
```

### Item Counts
- Consumables show stack count
- Spells with reagents show use count
- Item IDs work even when uncached (no ? icons)

---

## Debuff Timer System

Built-in debuff tracking using SuperWoW's advanced features.

### Features
- ✅ Auto-learning from successful casts
- ✅ 335+ debuffs pre-configured
- ✅ Per-caster storage (handles talent variations)
- ✅ GUID-based tracking
- ✅ Works independently of pfUI

### How It Works
1. Cast debuff → timestamp recorded
2. Debuff fades → duration calculated
3. Duration saved for future casts
4. Use in conditionals: `[debuff:Sunder_Armor>25]`

### Examples
```lua
-- Maintain Sunder with 25s buffer
/cast [debuff:Sunder_Armor>25] Heroic Strike; Sunder Armor

-- Refresh Corruption when <4s
/cast [debuff:Corruption<4] Corruption; Shadow Bolt

-- Multi-DoT priority
/cast [nodebuff:Moonfire] Moonfire
/cast [debuff:Moonfire<4] Moonfire
/cast [nodebuff:Insect_Swarm] Insect Swarm
/cast Wrath
```

### Supported Classes
- **Warrior:** Sunder, Rend, Hamstring, Thunder Clap, Demo Shout
- **Rogue:** Rupture, Garrote, Expose Armor, Poisons
- **Hunter:** Serpent Sting, Hunter's Mark, Wing Clip, Wyvern Sting
- **Druid:** Rip, Rake, Moonfire, Insect Swarm, Faerie Fire, Roots
- **Warlock:** Corruption, Curses, Immolate, Siphon Life
- **Mage:** Polymorph (all variants), Slow effects
- **Priest:** Shadow Word: Pain, Devouring Plague, Mind Flay
- **Paladin:** Judgement of the Crusader (all ranks), Hammer of Justice
- **Shaman:** Flame Shock, Frost Shock

---

## Combo Point Tracking

Automatically tracks combo finisher durations regardless of casting method.

### Supported Spells
- **Rogue Rupture:** 8s + 2s per CP (8-16s)
- **Rogue Kidney Shot:** Rank 1: 1s + 1s per CP, Rank 2: 2s + 1s per CP
- **Druid Rip:** 10s + 2s per CP (10-18s)

### Universal Tracking
Works with ALL casting methods:
- ✅ Spellbook clicks
- ✅ Action bar clicks
- ✅ Macros (`/cast Rip`)
- ✅ Direct Lua calls

### Examples
```lua
-- Refresh Rip when low
/cast [nodebuff:Rip] Rip
/cast [debuff:Rip<4] Rip

-- Rupture tracking
/cast [nodebuff:Rupture] Rupture
/cast [debuff:Rupture<2] Rupture
```

---

## Talent Modifiers

Automatically applies talent-based duration modifications.

**Calculation:** `final = (base + combo_points) + talent_modifier`

### Supported Talents
- **Warrior:**
  - Booming Voice (5 ranks): +12% per rank to Demo Shout
- **Rogue:**
  - Taste for Blood (3 ranks): +2s per rank to Rupture
  - Improved Gouge (3 ranks): +0.5s per rank to Gouge
- **Priest:**
  - Improved Shadow Word: Pain (2 ranks): +3s per rank
- **Druid:**
  - Brutal Impact (2 ranks): +0.5s per rank to Bash/Pounce stun

### Example
Rupture with 5 CP and Taste for Blood 3/3:
1. Base: 8s
2. Combo points: 8s + (5-1)×2 = 16s
3. Talent: 16s + (3×2) = **22s final**

### Carnage (Druid - TWoW Custom)
Ferocious Bite at 5 CP refreshes Rip/Rake to original duration.

**Requirements:**
- Carnage talent rank 2+
- Ferocious Bite with exactly 5 CP
- Rip/Rake active on target

---

## Equipment Modifiers

Item-based duration modifications.

**Calculation:** `final = (base + combo + talent) × equipment`

### Supported Items
- **Idol of Savagery (61699):** -10% to Rip/Rake duration (×0.9)

### Example
Rip with 5 CP and Idol of Savagery:
1. Base: 10s
2. Combo: 10s + (5-1)×2 = 18s
3. Talent: 18s + 0 = 18s
4. Equipment: 18s × 0.9 = **16.2s final**

---

## Set Bonus Modifiers

Set piece bonuses affect durations.

### Supported Sets
- **Dreamwalker Regalia (4/9):** +3s Moonfire, +2s Insect Swarm
- **Haruspex's Garb (3/5):** +5s Faerie Fire (non-feral)

---

## Immunity Tracking

Auto-learns NPC immunities from combat log.

### Features
- ✅ Auto-learning: "X's Spell fails. Y is immune."
- ✅ Damage schools: fire, frost, nature, shadow, arcane, holy, physical, bleed
- ✅ Buff-based immunities (temporary)
- ✅ Split damage spell support (Rake, Pounce, Garrote)

### Examples
```lua
-- Check by damage school
/cast [noimmune:fire] Fireball; Frostbolt
/cast [noimmune:bleed] Rip; Shred

-- Check by spell name
/cast [noimmune:"Flame Shock"] Flame Shock; Lightning Bolt

-- Split damage spells
/cast [noimmune] Rake                        -- Checks bleed (DoT)
/cast [noimmune:physical] Rake               -- Checks physical (initial)
/cast [noimmune noimmune:physical] Rake      -- Checks BOTH
```

### Split Damage Spells
- **Rake:** Physical initial + Bleed DoT
- **Pounce:** Physical initial + Bleed DoT
- **Garrote:** Physical initial + Bleed DoT

Default `[noimmune]` checks the debuff school (bleed).

---

# Slash Commands

| Command | Conditionals | Purpose |
|---------|:------------:|---------|
| /target | * | Target unit matching conditionals |
| /retarget |  | Clear invalid target, target nearest enemy |
| /startattack | * | Start auto-attacking |
| /stopattack | * | Stop auto-attacking |
| /stopcasting | * | Stop casting |
| /unqueue | * | Clear spell queue |
| /petattack | * | Pet attack |
| /petfollow | * | Pet follow |
| /petwait | * | Pet stay |
| /petaggressive | * | Set pet aggressive |
| /petdefensive | * | Set pet defensive |
| /petpassive | * | Set pet passive |
| /castpet |  | Cast pet ability by name |
| /castsequence | * | Cast sequence (see below) |
| /equip | * | Equip item by name/ID |
| /equipmh | * | Equip main hand |
| /equipoh | * | Equip off-hand |
| /unshift | * | Cancel shapeshift form |
| /cancelaura |  | Cancel buff/aura |
| /unbuff |  | Alias for cancelaura |
| /runmacro |  | Run macro by name |
| /use | * | Use item by name/ID |
| /cast | * | Cast spell by name |
| /stopmacro | * | Stop macro execution |
| /quickheal | * | Smart heal (QuickHeal) |
| /qh | * | Alias for /quickheal |

---

## Cast Sequence

```lua
#showtooltip
/castsequence reset=3 Fireball, Frostbolt, Arcane Explosion, Fire Blast
```

- Dynamic icons/tooltips with range/mana/usable checks
- **Reset options:** `reset=#/mod/target/combat`
- Conditionals apply to entire sequence

```lua
#showtooltip
/castsequence [group:party/raid] reset=3/target Spell1, Spell2, Spell3
/castsequence reset=target/combat CasualSpell1, CasualSpell2
```

---

# Conditionals Reference

## Key Modifiers

| Conditional | Syntax | Multi | Noable | Tests For |
|-------------|--------|:-----:|:------:|-----------|
| mod | [mod]<br/>[mod:ctrl/alt/shift] | * | * | Any mod key pressed<br/>Specific mod key(s) pressed |

## Player Only

| Conditional | Syntax | Multi | Noable | Tests For |
|-------------|--------|:-----:|:------:|-----------|
| cdgcd | [cdgcd:"Name">X] | * | * | Cooldown **INCLUDING** GCD |
| channeled | [channeled] |  | * | Player channeling |
| channeltime | [channeltime:<0.5] | * |  | Remaining channel time |
| checkchanneled | [checkchanneled] |  |  | Prevent recasting channel |
| combo | [combo:>#3] | * | * | Combo points |
| cooldown | [cooldown:"Name"<X] | * | * | Cooldown **IGNORING** GCD |
| druidmana | [druidmana:>=X] | * |  | Druid mana in form |
| equipped | [equipped:Daggers2] | * | * | Item/type equipped |
| form | [form:0/1/2] | * | * | Shapeshift form |
| group | [group:party/raid] | * | * | Player in group type |
| known | [known:"Name">#2] | * | * | Spell/talent known |
| mybuff | [mybuff:"Name"<X] | * | * | Player buff |
| mybuffcount | [mybuffcount:>=X] | * |  | Total buff count |
| mydebuff | [mydebuff:"Name"<X] | * | * | Player debuff |
| myhp | [myhp:<=50] | * |  | Player HP % |
| myhplost | [myhplost:>=X] | * |  | Player HP lost |
| mylevel | [mylevel:>=60] | * |  | Player level |
| mypower | [mypower:>=50] | * |  | Player power % |
| mypowerlost | [mypowerlost:>=X] | * |  | Player power lost |
| myrawhp | [myrawhp:>=1000] | * |  | Player HP raw |
| myrawpower | [myrawpower:>=500] | * |  | Player power raw |
| mhimbue | [mhimbue:Flametongue] |  | * | Main hand imbue |
| ohimbue | [ohimbue] |  | * | Off-hand imbue |
| onswingpending | [onswingpending] |  | * | On-swing spell queued |
| pet | [pet:Voidwalker] | * | * | Pet summoned |
| queuedspell | [queuedspell:X] | * | * | Spell queued |
| reactive | [reactive:Overpower] | * | * | Reactive ability available |
| resting | [resting] |  | * | In rest area |
| selfcasting | [selfcasting] |  | * | Player casting/channeling |
| stance | [stance:1/2/3] | * | * | In stance # |
| stat | [stat:str>=100] | * |  | Player stat check |
| stealth | [stealth] |  | * | Stealth/Prowl |
| swingtimer | [swingtimer:<15] | * | * | Swing % elapsed (SP_SwingTimer) |
| stimer | [stimer:>80] | * | * | Alias for swingtimer (SP_SwingTimer) |
| threat | [threat:>80] | * | * | Player threat % (TWThreat) |
| ttk | [ttk:<10] | * | * | Time to kill seconds (TimeToKill) |
| tte | [tte:<5] | * | * | Time to execute 20% HP (TimeToKill) |
| swimming | [swimming] |  | * | Aquatic form available |
| usable | [usable:"Name"] | * | * | Spell/item usable |
| zone | [zone:"Ironforge"] | * | * | In zone |

## Unit Based

Default `@unitid` is usually `@target` if not specified.

| Conditional | Syntax | Multi | Noable | Tests For |
|-------------|--------|:-----:|:------:|-----------|
| alive | [alive] |  | * | NOT dead/ghost |
| behind | [behind] |  | * | Player behind target |
| buff | [buff:"Name"<X] | * | * | Unit buff |
| casting | [casting:"Spell"] | * | * | Unit casting spell |
| class | [class:Warrior/Priest] | * | * | Player class |
| combat | [combat:target] | * | * | Unit in combat |
| dead | [dead] |  | * | Dead or ghost |
| debuff | [debuff:"Name"<X] | * | * | Unit debuff |
| distance | [distance:<40] | * | * | Distance in yards |
| exists | [exists] |  | * | Unit exists |
| hastarget | [hastarget] |  |  | Player has a target |
| harm | [harm] |  | * | Unit is enemy |
| help | [help] |  | * | Unit is friendly |
| hp | [hp:>=50] | * |  | Unit HP % |
| hplost | [hplost:>=X] | * |  | Unit HP lost |
| immune | [immune:fire] | * | * | Immune to school/spell |
| inrange | [inrange:"Name"] | * | * | In spell range |
| insight | [insight] |  | * | In line of sight |
| isnpc | [isnpc] |  |  | Is NPC |
| isplayer | [isplayer] |  |  | Is player |
| level | [level:>=60] | * |  | Unit level |
| meleerange | [meleerange] |  | * | In melee range |
| member | [member] | * |  | In party OR raid |
| notarget | [notarget] |  |  | Player has no target |
| outrange | [outrange:"Name"] |  |  | Out of spell range |
| party | [party]/[party:unitid] |  | * | Unit in party |
| power | [power:>=50] | * |  | Unit power % |
| powerlost | [powerlost:>=X] | * |  | Unit power lost |
| powertype | [powertype:mana/rage] | * | * | Power type |
| raid | [raid]/[raid:unitid] |  | * | Unit in raid |
| rawhp | [rawhp:>=1000] | * |  | Unit HP raw |
| rawpower | [rawpower:>=500] | * |  | Unit power raw |
| targeting | [targeting:player] | * | * | Unit targeting X |
| type | [type:Undead] | * | * | Creature type |
| @unitid | [@mouseover] |  |  | Valid unitid |

## UnitIDs

| UnitID |
|--------|
| player |
| target |
| pet |
| mouseover |
| partyN (N=1-4) |
| partypetN |
| raidN (N=1-40) |
| raidpetN |
| targettarget |
| playertarget |
| pettarget |
| partyNtarget |
| raidNtarget |
| targettargettarget |
| focus (requires pfUI) |

## Classes

Warrior, Paladin, Hunter, Shaman, Druid, Rogue, Mage, Warlock, Priest

## Weapon Types

| Type | Slot |
|------|------|
| Axes, Axes2 | Main/Off Hand |
| Bows | Ranged |
| Crossbows | Ranged |
| Daggers, Daggers2 | Main/Off Hand |
| Fists, Fists2 | Main/Off Hand |
| Guns | Ranged |
| Maces, Maces2 | Main/Off Hand |
| Polearms | Main Hand |
| Shields | Off Hand |
| Staves | Main Hand |
| Swords, Swords2 | Main/Off Hand |
| Thrown | Ranged |
| Wands | Ranged |

## Creature Types

Boss, Worldboss, Beast, Dragonkin, Demon, Elemental, Giant, Undead, Humanoid, Critter, Mechanical, Not specified, Totem, Non-combat Pet, Gas Cloud

## Reactive Spells (TWoW)

Revenge, Overpower, Riposte, Lacerate, Baited Shot, Counterattack, Arcane Surge

## Available Stats (stat conditional)

str/strength, agi/agility, stam/stamina, int/intellect, spi/spirit, ap/attackpower, rap/rangedattackpower, healing/healingpower, arcane_power, fire_power, frost_power, nature_power, shadow_power, armor, defense, arcane_res, fire_res, frost_res, nature_res, shadow_res

---

# Supported Addons

### Unit Frames
agUnitFrames, Blizzard, CT_RaidAssist, CT_UnitFrames, DiscordUnitFrames, FocusFrame, Grid, LunaUnitFrames, NotGrid, PerfectRaid, pfUI, sRaidFrames, UnitFramesImproved_Vanilla, XPerl

### Action Bars
Blizzard, Bongos, Discord Action Bars, pfUI

### Other
ClassicFocus/FocusFrame, SuperMacro, ShaguTweaks

### Optional Integrations
- [SP_SwingTimer](https://github.com/jrc13245/SP_SwingTimer) - `[swingtimer]` conditional
- [TWThreat](https://github.com/MarcelineVQ/TWThreat) - `[threat]` conditional
- [TimeToKill](https://github.com/jrc13245/TimeToKill) - `[ttk]` and `[tte]` conditionals
- [QuickHeal](https://github.com/jrc13245/QuickHeal) - `/quickheal` command

---

# Swing Timer Integration

Requires [SP_SwingTimer](https://github.com/jrc13245/SP_SwingTimer).

**How It Works:**
Checks what percentage of swing time has **elapsed** (not remaining).

**Syntax:**
```lua
[swingtimer:<15]   -- Less than 15% elapsed (early)
[swingtimer:>80]   -- More than 80% elapsed (late)
[stimer:<X]        -- Alias
```

**Examples:**
```lua
-- Cast Slam early in swing
#showtooltip Slam
/cast [swingtimer:<15] Slam

-- Heroic Strike late in swing
#showtooltip Heroic Strike
/cast [stimer:>70] Heroic Strike

-- Complex rotation
#showtooltip
/cast [swingtimer:<15] Slam
/cast [swingtimer:>80] Heroic Strike
/cast Bloodthirst
```

**Understanding Percentage:**
- 0% = Swing just started
- 15% = Early (optimal for Slam)
- 50% = Half elapsed
- 80% = Late (close to next swing)
- 100% = About to swing

For 3.5s weapon:
- `<15` = less than 0.525s elapsed
- `>80` = more than 2.8s elapsed

---

# Target State Conditionals

Check if player has or doesn't have a target selected.

| Conditional | True when |
|-------------|-----------|
| `[notarget]` | Player has NO current target (frame empty) |
| `[hastarget]` | Player HAS a current target selected |

**Key Difference from `[exists]`/`[noexists]`:**
- `[exists]` checks if the `@unit` specifier exists (e.g., `[@mouseover,exists]`)
- `[notarget]` checks if player's actual target frame is empty

**Example - Smart Targeting Macro:**
```lua
/target [@target,harm,alive]             -- Validate current target
/target [notarget,@mouseover,harm,alive] -- Target mouseover if no target
/retarget                                -- Fallback to nearest enemy
/startattack
```

---

# Slam Clip Conditionals (Warrior Only)

Specialized conditionals for Warrior Slam rotation to prevent auto-attack clipping.

**Note:** These conditionals are designed specifically for Warrior Slam rotation optimization. They are not intended for general-purpose use with other classes or abilities.

**Requirements:**
- [SP_SwingTimer](https://github.com/jrc13245/SP_SwingTimer) addon
- Warrior class (reads Slam cast time from spellbook tooltip)

**How It Works:**
Slam pauses the swing timer if it would complete during the cast, causing auto-attack clipping. These conditionals calculate optimal windows based on your current swing timer and Slam cast time (accounting for haste and talents).

**The Math:**
- **Slam Window**: `(SwingTimer - SlamCastTime) / SwingTimer × 100`
- **Instant Window**: `(2 × SwingTimer - SlamCastTime - GCD) / SwingTimer × 100`

**Conditionals:**
```lua
[noslamclip]        -- True if Slam NOW won't clip auto-attack
[slamclip]          -- True if Slam NOW WILL clip (negated)
[nonextslamclip]    -- True if instant NOW won't cause NEXT Slam to clip
[nextslamclip]      -- True if instant NOW WILL cause NEXT Slam to clip (negated)
```

**Debug Command:**
```lua
/cleveroid slamdebug    -- Show cast time, windows, and current status
```

**Example Values** (2.7s swing timer, 1.6s Slam cast):
- Slam window: ~40% (can cast Slam up to 40% into swing)
- Instant window: ~85% (can cast BT/WW up to 85% into swing)

**Examples:**
```lua
-- Cast Slam only when safe
#showtooltip Slam
/cast [noslamclip] Slam

-- Use Heroic Strike when past Slam window
#showtooltip Heroic Strike
/cast [slamclip] Heroic Strike

-- Cast Bloodthirst only when next Slam won't clip
#showtooltip Bloodthirst
/cast [nonextslamclip] Bloodthirst

-- Full Slam rotation macro
#showtooltip
/cast [noslamclip] Slam
/cast [nonextslamclip] Bloodthirst
/cast [slamclip] Heroic Strike
```

---

# Threat Integration

Requires [TWThreat](https://github.com/MarcelineVQ/TWThreat).

**How It Works:**
Checks your threat percentage on the current target.

**Note:** TWThreat only provides threat data for **elite targets** when you are in a **party or raid**.

**Threat Values:**
- 0-99% = Not tanking
- 100% = Tank/aggro holder
- 110% = Melee pull threshold
- 130% = Ranged pull threshold

**Syntax:**
```lua
[threat:>80]   -- Threat above 80%
[threat:<50]   -- Threat below 50%
[nothreat:>X]  -- NOT above X%
```

**Examples:**
```lua
-- Stop DPS when threat is high
#showtooltip Fireball
/cast [threat:<90] Fireball

-- Fade when about to pull aggro
#showtooltip Fade
/cast [threat:>100] Fade

-- Use threat reduction before pulling
#showtooltip Feign Death
/cast [threat:>105] Feign Death

-- Tank: taunt when losing aggro
#showtooltip Taunt
/cast [threat:<100] Taunt
```

---

# Time-To-Kill Integration

Requires [TimeToKill](https://github.com/jrc13245/TimeToKill).

**How It Works:**
Uses RLS algorithm to predict when target will die or reach execute phase (20% HP).

**Conditionals:**
- `[ttk:<X]` - Time to kill in seconds
- `[tte:<X]` - Time to execute (20% HP) in seconds

**Syntax:**
```lua
[ttk:<10]   -- Target dies in less than 10 seconds
[ttk:>30]   -- Target dies in more than 30 seconds
[tte:<5]    -- Target reaches 20% HP in less than 5 seconds
[nottk:<X]  -- NOT dying in less than X seconds
```

**Examples:**
```lua
-- Use execute when target about to enter execute range
#showtooltip Execute
/cast [tte:<3] Execute

-- Pop cooldowns only on long fights
#showtooltip Recklessness
/cast [ttk:>30] Recklessness

-- Finish mob quickly if almost dead
#showtooltip
/cast [ttk:<5] Heroic Strike
/cast Bloodthirst

-- Don't waste DoTs on dying targets
#showtooltip
/cast [ttk:>15] Corruption
/cast Shadow Bolt
```

---

# QuickHeal Integration

Requires [QuickHeal](https://github.com/jrc13245/QuickHeal).

**How It Works:**
Adds `/quickheal` (or `/qh`) command with full conditional support for smart healing.

**Syntax:**
```lua
/quickheal                     -- Smart heal (auto-select target)
/quickheal target              -- Heal current target
/quickheal [conditionals] X    -- Heal X if conditionals pass
/qh                            -- Alias
```

**Target Options:**
- `player` - Self
- `target` - Current target
- `targettarget` - Target's target
- `party` / `subgroup` - Lowest health party member
- `mt` / `nonmt` - Main tanks or non-tanks (raid only)

**Type Options:**
- `heal` - Regular heal (default)
- `hot` - Heal over time
- `hs` - Holy Shock (Paladin)
- `chainheal` - Chain Heal (Shaman)

**Examples:**
```lua
-- Only heal if not in danger
#showtooltip
/quickheal [threat:<80] mt

-- Emergency self-heal
#showtooltip
/quickheal [myhp:<30] player

-- Smart group healing with mana check
#showtooltip
/quickheal [combat,mypower:>25] party

-- HoT when low on mana
#showtooltip
/quickheal [mypower:<40] hot
/quickheal heal

-- Heal tank if they're hurt
#showtooltip
/quickheal [combat] mt
```

---

# HealComm Support

This addon uses SuperWoW's CastSpellByName which is incompatible with standard HealComm-1.0.

**Solution:**
Use MarcelineVQ's updated [LunaUnitFrames](https://github.com/MarcelineVQ/LunaUnitFrames) which includes SuperWoW support in HealComm-1.0.

**Manual Update:**
1. Exit WoW
2. Download MarcelineVQ's [LunaUnitFrames](https://github.com/MarcelineVQ/LunaUnitFrames)
3. Delete `/Interface/AddOns/HealComm/libs/HealComm-1.0`
4. Copy `/libs/HealComm-1.0` from LunaUnitFrames into `/Interface/AddOns/HealComm/libs/`

---

## Original Addons & Authors
- [Roid-Macros](https://github.com/DennisWG/Roid-Macros) by DennisWG (DWG)
- [CleverMacro](https://github.com/DanielAdolfsson/CleverMacro) by DanielAdolfsson (_brain)

## License

MIT
