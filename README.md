# SuperCleveRoid Macros
This was originally an effort to bring the dynamic tooltip and cast sequence functionality of [CleverMacro](https://github.com/DanielAdolfsson/CleverMacro) into [Roid-Macros](https://github.com/MarcelineVQ/Roid-Macros).  It has since expanded after some additional changes I wanted along with feedback from others.  The majority of credit goes to the [original addon authors](#original-addons--authors).  Still a work in progress.

# REQUIRED DLLS
[SuperWoW](https://github.com/balakethelock/SuperWoW)
[Nampower](https://github.com/pepopo978/nampower) 
[UnitXP_SP3](https://codeberg.org/konaka/UnitXP_SP3) 
# ALL 3 ARE REQUIRED!!!
Check slash command and all conditional lists for new usages! 

---

## Installation
### Manual
1. Download a zip from the green Code button or by clicking [here](https://github.com/jrc13245/SuperCleveRoidMacros/archive/refs/heads/main.zip)
2. Unzip the file and place the folder into your `Interface/Addons` folder.
3. Rename the `SuperCleveRoidMacros-main` folder to `SuperCleveRoidMacros`
4. Check that it is enabled in your addon list in-game.  
5. Make sure you don't have other macro addons that may interfere.
6. SUPERWOW ,NAMPOWER, and UNITXP_SP3 are REQUIRED!
7. Disable Macrotweak module in pfui, and disable macrotweak in shagutweaks!
8. Disable Scan Macros for spells in the actionbar section of pfui!

* [SuperWoW](https://github.com/balakethelock/SuperWoW) dll mod is required
* [Nampower](https://github.com/pepopo978/nampower) dll mod is required 
* [UnitXP_SP3](https://codeberg.org/konaka/UnitXP_SP3) dll mod is required

### SuperCleveRoidMacros Settings
* `/cleveroid` - View current settings
* `/cleveroid realtime 0 or 1` - Force realtime updates rather than event based updates (Default: 0. 1 = on, increases CPU load)
* `/cleveroid refresh X` - Set refresh rate (1 to 10 updates per second. Default: 5)
* `/cleveroid learn <spellID> <duration>` - Manually set spell duration in seconds
* `/cleveroid forget <spellID|all>` - Forget learned spell duration(s)
* `/cleveroid debug [0|1]` - Toggle learning debug messages
* `/cleveroid listimmune [school]` - List all or specific school immunities
* `/cleveroid addimmune "<NPC>" <school> [buff]` - Add manual immunity
* `/cleveroid removeimmune "<NPC>" <school>` - Remove immunity
* `/cleveroid clearimmune [school]` - Clear immunity data

--- 

## Known Issues
* By default, conditional checks to update icons are event based with realtime set to 0. This means icons using some conditionals that arent triggered by events are slow to change. example: @unitid mod etc. Enable realtime setting, but beware increase in cpu usage and lag.
* ALL macros must be given unique names, no blank names or muliple of the same name or using spell names. 
* If any of your macros have syntax errors, it will affect all macros when it comes to errors.
* Spells with parenthesis ie: Faerie Fire (Feral) or Barkskin (Feral) MUST be written using ranks, becomming `Faerie Fire (Feral)(Rank X)`
* Minor: If you improperly create a macro, in some certain cases it can cause strange UI issues including not displaying any icons, other macros not working or lua errors.  Fix the macro or remove it from your actionbar and it should go back to normal automatically.  Depending on the cause, you may need to reload your UI (/rl).  If you find one of these and can reproduce the issue, let me know.
* Minor: HealComm support.  See [below](#healcomm-support)
* I have not tested all possible combinations of conditionals or ways to break things.  Find me on Discord or open an issue if you find any bugs or have feedback.

---

# Macro Syntax Guide

## Basic Syntax Rules

### ***Important! Spells, Items, conditionals, etc are case sensitive.  Barring a bug, if there is an issue, it's almost always because something is typed incorrectly.***

### Spell and Item Names
* **Spaces**: Use underscores (`_`) OR enclose in quotes (`"`)
  * `Mark_of_the_Wild` OR `"Mark of the Wild"`
* **Ranks**: Must include full rank syntax with parentheses
  * `Faerie Fire (Feral)(Rank 4)` NOT `Faerie Fire (Feral)`

### Conditional Structure
* **Format**: `[conditional1 conditional2] Action`
* **Evaluation**: Left to right, top to bottom
* **First match wins**: First action where ALL conditionals are true executes
* **Separators**: Space or comma between conditionals
  * `[mod:alt harm alive]` OR `[mod:alt,harm,alive]`

### Line Formats
Both single-line and multi-line formats work identically:

**Multi-line** (easier to read):
```
#showtooltip
/cast [mod:alt] Frostbolt
/cast [mod:ctrl] Fire Blast
/cast Blink
```

**Single-line** (semicolon separated):
```
#showtooltip
/cast [mod:alt] Frostbolt; [mod:ctrl] Fire Blast; Blink
```

### Target Specification
* **Syntax**: `[@unitid]` at the start of conditionals
* **Example**: `/cast [@party1 combat] Intervene`
  * Targets party1, checks if player is in combat
* **Default**: Most conditionals default to `@target` if not specified

### Multi-Value Conditionals
Some conditionals accept multiple values with operators:

#### OR Operator (`/`)
* **Any match wins**: `[zone:Stormwind/Ironforge]` = in Stormwind OR Ironforge
* **Works with negation**: `[nozone:Stormwind_City/Ironforge]` = NOT in Stormwind OR NOT in Ironforge
  * True if you're outside either zone (or both)
  * Example: `[nomypower:>10/<20]` = power is not >10 OR not <20 (true if power is 5-10 or ≥20)

#### AND Operator (`&`)
* **All must match**: `[zone:Stormwind_City&Elwynn_Forest]` = in both zones (subzone & zone check)
* **Works with negation**: `[nozone:Stormwind_City&Ironforge]` = NOT in Stormwind AND NOT in Ironforge
  * True only if you're in neither zone
  * Example: `[nomybuff:Mark_of_the_Wild&Thorns]` = missing both Mark AND Thorns

**Important**: The `/` operator ALWAYS means OR, even for negated conditionals. Use `&` for AND logic.

* **Marked as "Multi"** in the conditionals table below

### Negation (No-able Conditionals)
Prefix with `no` to negate:
* **Marked as "Noable"** in the conditionals table below
* **Operators apply**: Use `/` for OR logic, `&` for AND logic (see above)

### Numerical Comparisons
For hp, power, cooldown, etc:
* **Operators**: `<`, `>`, `=`, `<=`, `>=`, `~=`
* **Format**: `[condition:>50]` or `[condition:"Name">50]`
* **Stacks vs Time**: Use `>#` for stacks/rank, no `#` for time
  * `[buff:"Mark_of_the_Wild">#5]` = 5+ stacks
  * `[mybuff:"Renew"<4]` = less than 4 seconds remaining

### Omitting Values
If the conditional value matches the action, you can omit it:
* `[debuff:"Sunder_Armor"<#5] Sunder Armor` = `[debuff:<#5] Sunder Armor`
* `[nobuff:"Mark_of_the_Wild"] Mark of the Wild` = `[nobuff] Mark of the Wild`

### Item IDs
Use item IDs instead of names to avoid cache issues:
```
#showtooltip
/use [nomod] 5350
/cast [mod] Conjure Water
```

### Equipment Slots
Use slot numbers (1-19) with `/use`:
```
#showtooltip
/use [combat hp:<=20] 13
```

## Special Prefixes

| Prefix | Example | Description |
|:------:|---------|-------------|
| `!` | `!Attack`<br/>`!Cat Form` | Only use if not already active<br/>Shorthand for `[nomybuff]` |
| `?` | `?[equipped:Swords]`<br/>`?Presence of Mind` | Hides icon/tooltip<br/>Must be first character |
| `~` | `~Slow Fall` | Toggle buff on/off<br/>Casts or cancels if possible |

## Common Pitfalls

❌ **Cascading conditionals** (Retail/Classic style) - NOT SUPPORTED:
```
/use [@mouseover alive help hp:<70][@target alive help hp:<70][@player] Bandage
```

✅ **Correct format** - Separate lines or semicolons:
```
/use [@mouseover alive help hp:<70] Bandage
/use [@target alive help hp:<70] Bandage
/use [@player] Bandage
```

❌ **Missing rank on spells with parentheses**:
```
/cast Faerie Fire (Feral)  -- WRONG
```

✅ **Include full rank**:
```
/cast Faerie Fire (Feral)(Rank 4)  -- CORRECT
```

### Multi-Value Operator Examples

**OR Operator (`/`)** - Any value matches:
```
# Cast if in Stormwind OR Ironforge
/cast [zone:Stormwind_City/Ironforge] Hearthstone

# Cast if NOT in Stormwind OR NOT in Ironforge (true if outside either/both)
/cast [nozone:Stormwind_City/Ironforge] Mount

# Cast if power is NOT >10 OR NOT <20 (true if power is 5-10 or ≥20)
/cast [nomypower:>10/<20] Spell
```

**AND Operator (`&`)** - All values must match:
```
# Cast if missing both Mark of the Wild AND Thorns
/cast [nobuff:Mark_of_the_Wild&Thorns] Mark of the Wild

# Cast if NOT alt AND NOT ctrl (only true if pressing neither)
/cast [nomod:alt&ctrl] Fireball

# Cast if target has neither Corruption AND Curse of Agony
/cast [nodebuff:Corruption&Curse_of_Agony] Corruption
```

**Practical Comparison**:
```
# OR: Reapply if missing EITHER buff
/cast [nomybuff:Mark_of_the_Wild/Thorns] Mark of the Wild

# AND: Only apply if missing BOTH buffs
/cast [nomybuff:Mark_of_the_Wild&Thorns] Mark of the Wild
```

---

# What's Different

## Dynamic Icons and Tooltips
* The icon and tooltip for a macro will automatically update to the first true condition's action.  Left to right, top to bottom.
* Consumables and certain other item types will now show a count on the action bar.
* Spells with reagent costs will now show a count of how many uses you have.
* Full `#showtooltip` support with dynamic icons and tooltips
  * A macro must start with `#showtooltip` or `#showtooltip spell/item/itemid`. The icons and tooltips will update on your bars as the conditions are met.

    ```lua
    #showtooltip
    /cast [mod:alt] Frostbolt; [mod:ctrl] Fire Blast; [mod:shift] {MyMacro}; Blink
    ```
    ```lua
    #showtooltip
    /cast [stance:1/3, nocooldown, notargeting:player] Mocking Blow
    /cast [stance:2/3, nocooldown, notargeting:player] Taunt
    /cast Shield Slam
    ```
    
    One line or separate lines are valid, sometimes one is better than the other

    ```
    #showtooltip
    /cast [zone:Ahn'Qiraj] Yellow Qiraji Battle Tank;[nozone:Orgrimmar/Undercity/"Thunder Bluff" nomybuff:"Water Walking"] Red Goblin Shredder;Plainsrunning
    ```
    Is the same as
    ```
    #showtooltip
    /cast [zone:Ahn'Qiraj] Yellow Qiraji Battle Tank
    /cast [nozone:Orgrimmar/Undercity/"Thunder Bluff" nomybuff:"Water Walking"] Red Goblin Shredder
    /cast Plainsrunning
    ```

  
* Updated `/castsequence` support.  See [below](#cast-sequence)
* Added support for updating to the icon/tooltip of the {macro} named in a another macro
  * Macro 1 calls Macro 2 and will update the icon when out of combat with Arcane Missiles from Macro2's `#showtooltip`  
    
    ***Note: This will only use the icon/tooltip of either the referenced `#showtooltip <spell/item/itemid>` or the icon you set for the macro.***  
      
      Macro 1:
    ```lua
    #showtooltip
    /cast [nocombat] {Macro2}; Fireball
    ```  
    Macro 2
    ```lua
    #showtooltip Arcane Missiles
    /cast [mod] Conjure Food
    /use 2288
    ```
* Added support for itemid lookup instead of the item's name.  Using this will show the icon/tooltip even if you don't have the item cached or in your inventory so you don't see ? icons.  e.g. No Mage food/water on login

    ```lua
    #showtooltip
    /use [nomod] 5350
    /cast [mod] Conjure Water
    ```
*Added support of using equipped items by slot number

    ```lua
    #showtooltip
    /use 16
    ```
---

## Debuff Timer System (SuperWoW) BY: yani9o
SuperCleveRoidMacros includes a built-in **debuff timer tracking system** that accurately tracks your debuff durations using SuperWoW's advanced features:

### Features
* ✅ **Auto-Learning** - Automatically learns debuff durations as you cast them
* ✅ **Accurate Tracking** - Only tracks debuffs that successfully land (no false timers on misses)
* ✅ **335+ Debuffs Pre-configured** - Extensive database of vanilla 1.12.1 spell IDs
* ✅ **Per-Caster Storage** - Handles talent variations by tracking per player GUID
* ✅ **GUID-Based** - Correctly handles multiple mobs with the same name
* ✅ **No pfUI Required** - Fully independent debuff tracking system

### How It Works
1. When you cast a debuff, the system records the timestamp
2. When the debuff fades, it calculates the actual duration
3. Duration is saved and used for all future casts of that spell
4. You can check debuff timers in macros using conditionals like `[debuff:Sunder Armor>25]`

### Manual Control
```lua
/cleveroid learn 11597 30        -- Set Sunder Armor (ID 11597) to 30 seconds
/cleveroid forget 11597           -- Forget Sunder Armor duration
/cleveroid forget all             -- Clear all learned durations
/cleveroid debug 1                -- Enable learning messages in chat
```

### Macro Examples
```lua
-- Maintain Sunder Armor with 25s buffer
/cast [debuff:Sunder_Armor>25] Heroic Strike; Sunder Armor

-- Refresh Corruption when <4s remain
/cast [debuff:Corruption<4] Corruption; Shadow Bolt

-- Apply Serpent Sting if missing or <5s
/cast [nodebuff:Serpent_Sting] Serpent Sting; [debuff:Serpent_Sting<5] Serpent Sting; Steady Shot

-- Multi-DoT priority system
/cast [nodebuff:Moonfire] Moonfire
/cast [debuff:Moonfire<4] Moonfire
/cast [nodebuff:Insect_Swarm] Insect Swarm
/cast Wrath
```

### Supported Debuffs
The system includes pre-configured durations for 335+ debuffs across all classes:
- **Warrior:** Sunder Armor, Rend, Hamstring, Thunder Clap, Demoralizing Shout, etc.
- **Rogue:** Rupture, Garrote, Expose Armor, Poisons, etc.
- **Hunter:** Serpent Sting, Hunter's Mark, Wing Clip, Wyvern Sting, etc.
- **Druid:** Rip, Rake, Moonfire, Insect Swarm, Faerie Fire, Entangling Roots, etc.
- **Warlock:** Corruption, Curses, Immolate, Siphon Life, etc.
- **Mage:** Polymorph (all variants), Slow effects, etc.
- **Priest:** Shadow Word: Pain, Devouring Plague, Mind Flay, etc.
- **Paladin:** Judgement of the Crusader (all 6 ranks), Hammer of Justice, etc.
- **Shaman:** Flame Shock, Frost Shock, etc.

### Combo Point Scaling
The addon automatically tracks combo point finishers that scale duration with combo points:
- **Rogue Rupture** (all ranks): 8s base + 2s per combo point (8s @ 1 CP, 16s @ 5 CP)
- **Rogue Kidney Shot**: Rank 1: 1s + 1s per CP, Rank 2: 2s + 1s per CP
- **Druid Rip** (all ranks): 10s base + 2s per combo point (10s @ 1 CP, 18s @ 5 CP)

The system automatically detects combo points at cast time and calculates the correct duration **regardless of how you cast the spell**:
- ✅ Clicking spell in spellbook
- ✅ Clicking ability on action bars
- ✅ Using macros (`/cast Rip`)
- ✅ Direct Lua calls (`CastSpellByName("Rip")`)

```lua
-- Will show accurate duration based on combo points used
/cast [nodebuff:Rip] Rip
/cast [debuff:Rip<4] Rip

-- Rupture duration tracking with combo point awareness
/cast [nodebuff:Rupture] Rupture
/cast [debuff:Rupture<2] Rupture
```

Use `/combotrack show` to see recent combo finisher casts and their calculated durations.

### Talent Modifiers
The addon automatically applies talent-based duration modifications to debuffs. Talent modifiers layer on top of combo point calculations for finisher abilities.
**IF YOUR TALENT DEBUFF DURATION MODIFIER IS MISSING, PLEASE MAKE A BUG REPORT!!!**

**Calculation Order:** `final_duration = (base + combo_points) + talent_modifier`

**Supported Talent Modifiers:**
- **Warrior:**
  - **Booming Voice** (5 ranks): +12% per rank to Demoralizing Shout duration (60% at rank 5)
- **Rogue:**
  - **Taste for Blood** (3 ranks): +2s per rank to Rupture duration
  - **Improved Gouge** (3 ranks): +0.5s per rank to Gouge duration
- **Priest:**
  - **Improved Shadow Word: Pain** (2 ranks): +3s per rank to SW:P duration
- **Druid:**
  - **Brutal Impact** (2 ranks): +0.5s per rank to Bash and Pounce stun duration

**Example:** Rupture with 5 CP and Taste for Blood 3/3:
1. Base duration: 8s
2. Combo point modifier: 8s + (5-1)×2 = 16s
3. Talent modifier: 16s + (3×2) = **22s final**

### Special Talent Mechanics

#### Carnage (Druid - TWoW Custom Talent)
The **Carnage** talent (Feral Combat tree, 2/2 required) causes **Ferocious Bite at 5 combo points** to refresh Rip and Rake back to their original duration.

**How it works:**
1. Cast Rip at 5 CP → 18 second duration (with Idol of Savagery: 16.2s)
2. Cast Ferocious Bite at 5 CP → Rip refreshes back to 18 seconds (or 16.2s with idol)

**Features:**
- ✅ **Duration preservation** - Remembers the original cast duration (including combo points, talents, and equipment modifiers)
- ✅ **pfUI integration** - Refreshed duration displays correctly on pfUI's target debuff timers
- ✅ **Multiple DoT support** - Both Rip and Rake refresh simultaneously and display correctly

**Requirements:**
- Carnage talent at rank 2 or higher
- Ferocious Bite must be cast with exactly 5 combo points
- Rip/Rake must already be active on the target

### Equipment Modifiers
The addon supports item-based duration modifications.
**IF YOUR EQUIPMENT DEBUFF DURATION MODIFIER IS MISSING, PLEASE MAKE A BUG REPORT!!!**

**Calculation Order:** `final_duration = (((base + combo_points) + talent_modifier) × equipment_modifier) + set_bonus`

**Supported Equipment Modifiers:**
- **Idol of Savagery** (Item ID: 61699, Druid Idol): Reduces the time between periodic ticks and the duration of Rake and Rip by 10% (×0.9 multiplier)

**Example:** Rip with 5 CP and Idol of Savagery equipped:
1. Base duration: 10s
2. Combo point modifier: 10s + (5-1)×2 = 18s
3. Talent modifier: 18s + 0 = 18s (if no talent)
4. Equipment modifier: 18s × 0.9 = **16.2s final**

### Set Bonus Modifiers
The addon supports set bonus duration modifications by counting equipped set pieces.
**IF YOUR SET BONUS DEBUFF DURATION MODIFIER IS MISSING, PLEASE MAKE A BUG REPORT!!!**

**How It Works:**
The system counts how many pieces from a set are equipped and applies the modifier when the threshold is met.

**Supported Set Bonus Modifiers:**
- **Druid:**
  - **Dreamwalker Regalia (4/9)**: +3s to Moonfire duration, +2s to Insect Swarm duration
    - Item IDs: 47372, 47373, 47374, 47375, 47376, 47377, 47378, 47379, 47380
  - **Haruspex's Garb (3/5)**: +5s to Faerie Fire duration (non-feral only)
    - Item IDs: 19613, 19955, 19840, 19839, 19838

**Example:** Moonfire with Dreamwalker Regalia 4-set:
1. Base duration: 18s
2. Set bonus modifier: 18s + 3s = **21s final**

**Example:** Insect Swarm with Dreamwalker Regalia 4-set:
1. Base duration: 18s
2. Set bonus modifier: 18s + 2s = **20s final**

### Immunity Tracking System
The addon automatically learns and tracks NPC immunities from combat log messages:

**Features:**
- ✅ **Auto-learning** from combat log: "X's Spell fails. Y is immune."
- ✅ **Damage school tracking**: fire, frost, nature, shadow, arcane, holy, physical
- ✅ **Buff-based immunity detection**: Tracks temporary immunities (e.g., boss immune during shield phase)
- ✅ **Automatic spell school detection** via tooltip scanning

**Usage in Macros:**
```lua
-- Check immunity before casting
/cast [noimmune:fire] Fireball; Frostbolt
/cast [noimmune:"Flame Shock"] Flame Shock; Lightning Bolt

-- Check if target is immune (any school)
/cast [immune] Shoot; Arcane Shot
```

**Manual Control:**
```lua
/cleveroid listimmune [school]           -- List all or specific immunities
/cleveroid addimmune "NPC Name" fire     -- Add manual immunity
/cleveroid removeimmune "NPC Name" fire  -- Remove immunity
/cleveroid clearimmune [school]          -- Clear immunity data
```

### Technical Details
- **Combo point tracking:**
  - Hooks `CastSpell`, `UseAction`, and `CastSpellByName` at addon load time
  - Pre-captures combo points before spell execution
  - Works universally across all casting methods (spellbook, action bars, macros, Lua calls)
  - Integrates with pfUI's debuff timer display
- **Debuff duration tracking:**
  - Uses **UNIT_CASTEVENT** for precise cast detection (only tracks successful hits)
  - Uses **RAW_COMBATLOG** to detect when debuffs fade
  - Stores durations in **SavedVariables** (persists between sessions)
  - Falls back to static database for unknown spells
- **No dependency on pfUI or other addons** (but integrates with pfUI if present)

---
# Usage
## Slash Commands
| Command               | Conditionals Supported | Purpose |
|-----------------------|          :-:           |---------|
| /cleveroid |  | show update settings. /cleveroid realtime 0/1 : /cleveroid refresh 1-10 |
| /target               | * | Targets a unit that matchets the conditionals. Requires friendly nameplates for friendly non-party/raid units or their pets. Requires enemy nameplates for non-friendly units. |
| /retarget             |   | Clears your target if it doesn't exist, has 0 hp or if you can't attack it and then targets the nearest enemy. |
| /startattack          | * | Starts auto-attacking. |
| /stopattack           | * | Stops auto-attacking. |
| /stopcasting          | * | Stops casting. |
| /unqueue          | * | Stops casting. |
| /petattack            | * | Command pet to Attack. |
| /petfollow            | * | Command pet to Follow. |
| /petwait              | * | Command pet to Wait (Stay). |
| /petaggressive        | * | Set pet mode to Aggressive. |
| /petdefensive         | * | Set pet mode to Defensive. |
| /petpassive           | * | Set pet mode to Passive. |
| /castpet              |   | Casts a pet ability by name. |
| /castsequence         | * | Performs a cast sequence.  See [below](#cast-sequence) for more infomation. |
| /equip                | * | Equips an item by name or itemid. |
| /equipmh              | * | Equips an item by name or itemid into your mainhand slot. |
| /equipoh              | * | Equips an item by name or itemid into your offhand slot. |
| /unshift              | * | Cancels your current shapeshift form. |
| /cancelaura, /unbuff  |   | Cancels a valid buff/aura. |
| /runmacro             |   | Runs a macro.  Use /runmacro {macroname} |
| /use                  | * | Uses an item by name or id |
| /cast                 | * | Casts a spell by name      |
| /stopmacro            | * | prevent any lines under /stopmacro from being run unless conditionals are met |

---

## Cast Sequence
  ```lua
  #showtooltip
  /castsequence reset=3 Fireball, Frostbolt, Arcane Explosion, Fire Blast
  ```
* Dynamic icons and tooltips on each sequence with range/mana/usable checks
* Supports reset=#/mod/target/combat
* Supports conditionals for the entire sequence, not individual actions within the sequence.  
  ```lua
  #showtooltip
  /castsequence [group:party/raid] reset=3/target Sweaty Spell 1, Sweaty Spell 2, Sweaty Spell 3
  /castsequence reset=target/combat Casual Spell 1, Casual Spell 2, Casual Spell 3
  ```

## Conditionals Reference

See the **[Macro Syntax Guide](#macro-syntax-guide)** above for detailed syntax rules.

### Example Macros

**startattack, stopattack, stopcasting:**
```
#showtooltip
/startattack [harm alive]

#showtooltip
/stopattack [form:0/1/2/3]

#showtooltip
/stopcasting [hp:<=20]
```

**Item Slots (1-19) with /use:**
```
#showtooltip
/use [combat hp:<=20] 13
```

**Bandage priority example:**
```
#showtooltip
/use [@mouseover alive help hp:<70 nodebuff:"Recently Bandaged"] Runecloth Bandage
/use [@target alive help hp:<70 nodebuff:Recently_Bandaged] Runecloth Bandage
/use [@player] Runecloth Bandage
```

**Using selfcasting conditional:**
```
#showtooltip
/stopcasting [selfcasting mod:shift]
/cast [mod:shift] Polymorph

-- Stop casting and cast Frostbolt if you're currently casting/channeling
#showtooltip
/stopcasting [selfcasting]
/cast Frostbolt

-- Only cast if not already casting
#showtooltip
/cast [noselfcasting] Fireball
```

### Additional Notes

* **Focus targeting**: @focus can be used as a unitid, but requires a compatible addon (pfUI or similar) since Vanilla doesn't support focus natively
* **Time-based buff/debuff checks**: Only the player's buffs/debuffs can be checked for remaining time
* **DLL requirements**: [SuperWoW](https://github.com/balakethelock/SuperWoW), [Nampower](https://github.com/pepopo978/nampower), and [UnitXP_SP3](https://codeberg.org/konaka/UnitXP_SP3) are all required

---

## Conditional Keywords

### Key Modifiers
| Conditional    | Syntax Examples       | Multi | Noable | Tests For |
|----------------|---------------|  :-:  | :-:    |-----------|
| mod            | [mod]<br/>[mod:ctrl/alt/shift] | * | * | If any mod key is pressed.</br>If one of the listed modifier keys are pressed.  |


### Player Only
| Conditional    | Syntax Examples       | Multi | Noable | Tests For |
|----------------|---------------|  :-:  | :-:    |-----------|
| cdgcd          | [cdgcd]<br/>[cdgcd:"Name"]<br/>[cdgcd:"Name">X] | * | * | If the Spell or Item is on cooldown and optionally if the amount of time left is >= or <= than X seconds.  **GCD NOT IGNORED** |
| channeled      | [channeled] |  | * | If the player is currently channeling a spell. |
| checkchanneled | [checkchanneled] |  |  | Prevents a spell from being cast if you are already channeling it. |
| combo          | [combo:>#3]<br/>[combo:#2]</br>[combo:<#5] | * |  * |  If the player has the specified number of combo points. |
| cooldown       | [cooldown]<br/>[cooldown:"Name"]<br/>[cooldown:"Name"<X] | * | * | If the Spell or Item name is on cooldown and optionally if the amount of time left is >= or <= than X seconds. **GCD (if exatly 1.5 sec) IGNORED** |
| druidmana      | [druidmana:>=X]<br/>[druidmana:>=X/<=Y] | * | | The druid's mana compared to X. **ONLY FOR DRUIDS** **Works in Cat or Bear form.** |
| equipped       | [equipped:"Name"]<br/>[equipped:Shields]<br/>[equipped:Daggers2] | * | * | If the player has an item name/id or item type equipped.  See [below](#weapon-types) for a list of valid Weapon Types. |
| form           | [form:0/1/2/3/4/5] | * | * | Alias of `stance` |
| group          | [group]<br/>[group:party/raid] | * |  | If the player is in any group or specific group type. |
| known          | [known]<br/>[known:"Name"]</br>[known:"Name">#2] | * | * | If the player knows a spell or talent.  Can optionally check the rank. |
| mybuff         | [mybuff]<br/>[mybuff:"Name"]<br/>[mybuff:"Name">#X]<br/>[mybuff:<X] | * | * | If the player has a buff of the given name.</br>Optionally compared to X number of stacks.<br/>Optionally compared to X time remaining. |
| mybuffcount    | [mybuffcount:>=X]<br/>[mybuffcount:<=X] | * |  | If the player has more or less auras present than X.|
| mydebuff       | [mydebuff]<br/>[mydebuff:"Name"]<br/>[mydebuff:"Name">#X]<br/>[mydebuff:<X] | * | * | If the player has a debuff of the given name.<br/>Optionally compared to X number of stacks.<br/>Optionally compared to X time remaining. |
| myhp           | [myhp:<=X]<br/>[myhp:>=X/<=Y] | * |  | The player's health **PERCENT** compared to X. |
| myhplost       | [myhplost:>=X]<br/>[myhplost:>=X/<=Y] | * |  | The player's lost health compared to X. |
| mylevel        | [mylevel:>=X]<br/>[mylevel:<=Y] | * |  | The player's level compared to X. |
| mypower        | [mypower:>=X]<br/>[mypower:>=X/<=Y] | * |  | The player's power (mana/rage/energy) **PERCENT** compared to X. |
| mypowerlost    | [mypowerlost:>=X]<br/>[mypowerlost:>=X/<=Y] | * |  | The player's lost power (mana/rage/energy) compared to X. |
| myrawhp        | [myrawhp:>=X]<br/>[myrawhp:>=X/<=Y] | * |  | The player's health compared to X. |
| myrawpower     | [myrawpower:>=X]<br/>[myrawpower:>=X/<=Y] | * |  | The player's power (mana/rage/energy) compared to X. |
| mhimbue        | [mhimbue:Flametongue] |  | * | If the player has weapon imbue on main hand. |
| ohimbue        | [ohimbue] |  | * | If the player has weapon imbue on off-hand. |
| onswingpending | [onswingpending] |  | * | If the player has a on swing spell pending.|
| pet            | [pet]<br/>[pet:Voidwalker]<br/>[pet:Imp/Felhunter] | * | * | If the player has a pet summoned and optionally if it matches the specified pet type(s). Works for Warlock demons and Hunter pets. |
| queuedspell    | [queuedspell]<br/>[queuedspell:X] | * | * | If the player has any or a specific spell queued with nampower. |
| reactive       | [reactive]<br/>[reactive:Overpower] | * | * | If the player has the reactive ability (Revenge, Overpower, Riposte, etc.) available to use.<br/><br/>**NOTE: Currently requires the reactive ability to be somewhere on your actionbars in addition to any macros you're using it in.  A planned future update will remove this requirement if using [Nampower](https://github.com/pepopo978/nampower).** |
| resting        | [resting] |  | * | If the player is resting (in an inn/capital city/etc.) |
| selfcasting    | [selfcasting] |  | * | If the player is currently casting or channeling any spell. More reliable than `[casting @player]` |
| stance         | [stance:0/1/2/3/4/5] | * | * | If the player is in stance #.<br/>Supports Shadowform and Stealth as stance 1.|
| stat           | [stat:stat>=x/<=y] | * |  | Check if one of the players statistics is greater or less than a specific number. Available Stats: str/strength, agi/agility, stam/stamina, int/intellect, spi/spirit, ap/attackpower, rap/rangedattackpower, healing/healingpower, arcane_power, fire_power, frost_power, nature_power, shadow_power, armor, defense, arcane_res, fire_res, frost_res, nature_res, shadow_res. |
| stealth        | [stealth] |  | * | If the player is in Stealth or Prowl. |
| swingtimer     | [swingtimer:<15] | * | * | If a percentage of swing time has elapsed. `<15` = early in swing, `>80` = late in swing. Requires [SP_SwingTimer](https://github.com/jrc13245/SP_SwingTimer) addon. See [below](#swing-timer-integration) for details.|
| stimer         | [stimer:<15] | * | * | Alias for `swingtimer` |
| swimming       | [swimming] |  | * | Druid only, works like reactive but for aquatic form, must have aquatic form on one of your non-stance actionbars. |
| usable         | [usable]<br/>[usable:"Spell Name"] | * | * | If the spell or item is usable (not on cooldown, have reagents, etc.). |
| zone           | [zone:"Zone"]<br/>[zone:"Zone"/"Another Zone"] | * | * | If the player is in one or more zones of the given name. |

### Unit Based
### The default @unitid is usually @target if you don't specify one
### The only conditionals that take conditional:unitid are combat/nocombat and targeting/notargeting
| Conditional    | Syntax        | Multi | Noable | Tests For |
|----------------|---------------|  :-:  | :-:    |-----------|
| alive          | [alive]       |       |    *    | If the @unitid is NOT dead or a ghost. |
| behind         | [behind] |  | * | If the player is behind the target.|
| buff           | [buff]<br/>[buff:"Name"]<br/>[buff:"Name">#X]<br/>[buff:"Name"<X] | * | * | If the @unitid has a buff of the given name and optionally if it has >= or <= than X number of stacks or X time remaining. |
| casting        | [casting]<br/>[casting:"Spell Name"] | * |  * |  If the @unitid is casting any or one or more specific spells. |
| class          | [class:classname1/classname2]<br/>[class:Warrior/Priest] | * | * | The target is a player of the specified class/classes. |
| combat         | [combat]<br/>[combat:target] | * | * | If the unitid (default is player) is in combat. |
| dead           | [dead]        |       |    *    | If the @unitid is dead or a ghost. |
| debuff         | [debuff]<br/>[debuff:"Name"]<br/>[debuff:"Name">#X]<br/>[debuff:<X] | * | * | If the @unitid has a debuff of the given name and optionally if it has >= or <= than X number of stacks or X time remaining. |
| distance       | [distance:>X]<br/>[distance:<X] | * | * | If the player is closer or farther than X yards from the target.|
| exists         | [exists] |  | * | If the @unitid exists. |
| harm           | [harm]        |       |    *    | If the @unitid is an enemy. |
| help           | [help]        |       |    *    | If the @unitid is friendly. |
| hp             | [hp:>=X]<br/>[hp:>=X/<=Y] | * |  | The @unitid health **PERCENT** compared to X. |
| hplost         | [hplost:>=X]<br/>[hplost:>=X/<=Y] | * |  | The @unitid health lost compared to X. |
| immune         | [immune:fire]<br/>[immune:Flame_Shock] | * | * | If the npc has immunities to a damage type or spell. Check slash commands section for more information. |
| inrange        | [inrange]<br/>[inrange:"Name"] | * | * | If the specified @unitid is in range of the spell. |
| insight        | [insight] |  | * | If the player is in line of sight of the target. |
| isnpc          | [isnpc] |  |  | If the @unitid is an npc.<br/>See this [article](https://wowpedia.fandom.com/wiki/UnitId) for a list of unitids.<br/>Not all units are valid in vanilla. |
| isplayer       | [isplayer] |  |  | If the @unitid is a player.<br/>See this [article](https://wowpedia.fandom.com/wiki/UnitId) for a list of unitids.<br/>Not all units are valid in vanilla. |
| level          | [level:>=X]<br/>[level:<=Y] | * |  | The @unitid level compared to X. |
| meleerange     | [meleerange] |  | * | If the player is melee range of the target.|
| member         | [member]      |    *   |       | If the @unitid is in your party OR raid. |
| outrange       | [outrange]<br/>[outrange:"Name"] |  |  | If the specified @unitid is out of range of the spell. |
| party          | [party]       |       |    *   | If the @unitid is in your party. |
| power          | [power:>=X]<br/>[power:>=X/<=Y] | * |  | The @unitid power (mana/rage/energy) **PERCENT** compared to X. |
| powerlost      | [powerlost:>=X]<br/>[powerlost:>=X/<=Y] | * |  | The @unitid power (mana/rage/energy) lost compared to X. |
| powertype      | [powertype:mana]<br/>[powertype:rage]<br/>[powertype:energy]<br/>[powertype:mana/rage] | * | * | If the @unitid uses the specified power type(s). Valid types: mana, rage, energy, focus. Useful for checking if NPCs use mana or for player class detection. |
| raid           | [raid]        |       |    *   | If the @unitid is in your raid.  |
| rawhp          | [rawhp:>=X]<br/>[rawhp:>=X/<=Y] | * |  | The @unitid health compared to X. |
| rawpower       | [rawpower:>=X]<br/>[rawpower:>=X/<=Y] | * |  | The @unitid power (mana/rage/energy) compared to X. |
| targeting      | [targeting:unitid] | * | * | If the @unitid is targeting the specified unitid.<br/>See this [article](https://wowpedia.fandom.com/wiki/UnitId) for a list of unitids.<br/>Not all units are valid in vanilla. |
| type           | [type:"Creature Type"] | * | * | If the @unitid is the specified creature type.  See [below](#creature-types) for a list of valid Creature Types. |
| @unitid        | [@mouseover] |  |  | The @unitid is a valid target. |

### Unitids
| Name (N=party/raid slot number) |
|------|
| player |
| target |
| pet |
| mouseover |
| partyN |
| partypetN |
| raidN |
| raidpetN |
| targettarget |
| playertarget |
| pettarget |
| partyNtarget |
| raidNtarget |
| targettargettarget |
| focus (requires pfui or another addon) |

### Classes
| Class |
|------|
| Warrior |
| Paladin |
| Hunter |
| Shaman |
| Druid |
| Rogue |
| Mage |
| Warlock |
| Priest |

### Weapon Types
| Name | Slot |
|------|------|
| Axes, Axes2 | Main Hand, Off Hand |
| Bows | Ranged |
| Daggers, Daggers2 | Main Hand, Off Hand |
| Crossbows | Ranged |
| Fists, Fists2  | Main Hand, Off Hand |
| Guns | Ranged |
| Maces, Maces2 | Main Hand, Off Hand |
| Polearms | Main Hand |
| Shields | Off Hand |
| Staves | Main Hand |
| Swords, Swords2 | Main Hand, Off Hand |
| Thrown | Ranged |
| Wands | Ranged |


### Creature Types
| Name |
|------|
| Boss |
| Worldboss |
| Beast |
| Dragonkin |
| Demon |
| Elemental |
| Giant |
| Undead |
| Humanoid |
| Critter |
| Mechanical |
| Not specified |
| Totem |
| Non-combat Pet |
| Gas Cloud |

### Reactive Spells (twow)
| Name          |
|---------------|
| Revenge       |
| Overpower     |
| Riposte       |
| Lacerate      |
| Baited Shot   |
| Counterattack |
| Arcane Surge  |

### UnitFrames
* agUnitFrames
* Blizzard's UnitFrames
* CT_RaidAssist
* CT_UnitFrames
* DiscordUnitFrames
* FocusFrame
* Grid
* LunaUnitFrames
* NotGrid
* PerfectRaid
* pfUI
* sRaidFrames
* UnitFramesImproved_Vanilla
* XPerl

### Action Bars
* Blizzard's Action Bars
* Bongos
* Discord Action Bars
* pfUI


### Supported Addons
* ClassicFocus / FocusFrame
* SuperMacro
* ShaguTweaks


### Swing Timer Integration
The addon integrates with [SP_SwingTimer](https://github.com/jrc13245/SP_SwingTimer) to provide swing timer conditionals for abilities like Slam that benefit from being cast at specific points in your swing cycle.

**Requirements:**
- [SP_SwingTimer](https://github.com/jrc13245/SP_SwingTimer) addon must be installed
- If SP_SwingTimer is not loaded, the conditional will return false and display an error message once

**How It Works:**
The conditional checks what percentage of your swing time has **elapsed** (not remaining).

`[swingtimer:<15]` checks if less than 15% of your swing has elapsed (early in swing).

This allows you to cast abilities like Slam at the optimal time in your swing cycle.

**Syntax:**
- `[swingtimer:<X]` - True if less than X% of swing has elapsed (early in swing)
- `[swingtimer:>X]` - True if more than X% of swing has elapsed (late in swing)
- `[swingtimer:>=X]` - True if X% or more of swing has elapsed
- `[swingtimer:<=X]` - True if X% or less of swing has elapsed
- `[stimer:<X]` - Alias for swingtimer

**Negation:**
- `[noswingtimer:<15]` - True if NOT (less than 15% elapsed) = 15% or more has elapsed
- `[nostimer:>80]` - Alias for noswingtimer

**Example Macros:**

```lua
-- Cast Slam early in the swing (first 15% of swing time)
-- This is optimal for Slam to avoid delaying your next auto-attack
#showtooltip Slam
/cast [swingtimer:<15] Slam
```

```lua
-- Heroic Strike queue management - only queue late in swing
#showtooltip Heroic Strike
/cast [stimer:>70] Heroic Strike
```

```lua
-- Complex rotation with swing timer awareness
#showtooltip
/cast [swingtimer:<15] Slam
/cast [swingtimer:>80] Heroic Strike
/cast Bloodthirst
```

**Understanding the Percentage:**
- 0% = Just attacked (swing just started)
- 15% = Early in swing (optimal for Slam)
- 50% = Half of swing time has elapsed
- 80% = Late in swing (close to next auto-attack)
- 100% = About to swing

For a warrior with a 3.5 second weapon:
- `[swingtimer:<15]` = True when less than 0.525 seconds have elapsed (early)
- `[swingtimer:>80]` = True when more than 2.8 seconds have elapsed (late)

---

### HealComm Support
This addon uses [SuperWoW](https://github.com/balakethelock/SuperWoW)'s CastSpellByName which is not compatible with the standard HealComm-1.0 library.  MarcelineVQ has an updated version of [LunaUnitFrames](https://github.com/MarcelineVQ/LunaUnitFrames) where they added [SuperWoW](https://github.com/balakethelock/SuperWoW) support to the HealComm-1.0 library.  If you use [SuperWoW](https://github.com/balakethelock/SuperWoW) and want proper HealComm support with your macros, you need to do one or both of the following:  

* Contact the author of whichever addon and ask that they update their HealComm to support [SuperWoW](https://github.com/balakethelock/SuperWoW) and link them to MarcelineVQ's updated [LunaUnitFrames](https://github.com/MarcelineVQ/LunaUnitFrames).

* Manually update any addon that is using the `HealComm-1.0` library by deleting the `HealComm-1.0` folder and replacing it with the `libs/HealComm-1.0` folder from MarcelineVQ's version of LunaUnitFrames.  

Example for the standalone HealComm addon:  
1. Exit WoW completely.
2. Download a copy of the updated [LunaUnitFrames](https://github.com/MarcelineVQ/LunaUnitFrames).
3. Delete the `/Interface/AddOns/HealComm/libs/HealComm-1.0` folder.
4. From the [LunaUnitFrames](https://github.com/MarcelineVQ/LunaUnitFrames) download, copy the `/libs/HealComm-1.0` folder into your `/Interface/AddOns/HealComm/libs/` folder.


----
### Original Addons & Authors  
* [Roid-Macros by DennisWG (DWG)](https://github.com/DennisWG/Roid-Macros)  
* [CleverMacro by DanielAdolfsson (_brain)](https://github.com/DanielAdolfsson/CleverMacro)
----
License
----

MIT
