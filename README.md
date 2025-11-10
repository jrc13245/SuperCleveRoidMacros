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
* `/cleveroid debug [0|1]` - Toggle debug messages for spell duration learning

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

# What's Different
### ***Important! Spells, Items, conditionals, etc are case sensitive.  Barring a bug, if there is an issue, it's almost always because something is typed incorrectly.***  
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
* ✅ **329+ Debuffs Pre-configured** - Extensive database of vanilla 1.12.1 spell IDs
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
/cast [debuff:Sunder Armor>25] Heroic Strike; Sunder Armor

-- Refresh Corruption when <4s remain
/cast [debuff:Corruption<4] Corruption; Shadow Bolt

-- Apply Serpent Sting if missing or <5s
/cast [nodebuff:Serpent Sting] Serpent Sting; [debuff:Serpent Sting<5] Serpent Sting; Steady Shot

-- Multi-DoT priority system
/cast [nodebuff:Moonfire] Moonfire
/cast [debuff:Moonfire<4] Moonfire
/cast [nodebuff:Insect Swarm] Insect Swarm
/cast Wrath
```

### Supported Debuffs
The system includes pre-configured durations for 329+ debuffs across all classes:
- **Warrior:** Sunder Armor, Rend, Hamstring, Thunder Clap, Demoralizing Shout, etc.
- **Rogue:** Rupture, Garrote, Expose Armor, Poisons, etc.
- **Hunter:** Serpent Sting, Hunter's Mark, Wing Clip, Wyvern Sting, etc.
- **Druid:** Rip, Rake, Moonfire, Insect Swarm, Faerie Fire, Entangling Roots, etc.
- **Warlock:** Corruption, Curses, Immolate, Siphon Life, etc.
- **Mage:** Polymorph (all variants), Slow effects, etc.
- **Priest:** Shadow Word: Pain, Devouring Plague, Mind Flay, etc.
- **Paladin:** Judgements, Hammer of Justice, etc.
- **Shaman:** Flame Shock, Frost Shock, etc.

### Technical Details
- Uses **UNIT_CASTEVENT** for precise cast detection (only tracks successful hits)
- Uses **RAW_COMBATLOG** to detect when debuffs fade
- Stores durations in **SavedVariables** (persists between sessions)
- Falls back to static database for unknown spells
- No dependency on pfUI or other addons

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

## Conditionals
* Conditionals are basically if/then/else statements which are evaluated left to right, top to bottom.  
* The first set of conditions that are all true will be the action that happens so the order you put things in is very important.
* Multiple conditionals can be used, separated with a space or comma.  
* Spells and items with spaces in the name need to use underscores (`_`) instead of spaces or be enclosed in quotations.
* Each action can be written on one line or on separate.  Both are effectively the same however WoW executes every line of a macro so it is technically better to use one line where possible.  I usually prefer separate lines because it's easier to read and troubleshoot at a quick glance.  You do you.
  
  
  **startattack, stopattack, stopacasting:**
  ```
  #showtooltip
  /startattack [harm alive]
  
  #showtooltip
  /stopattack [form:0/1/2/3]

  #showtooltip
  /stopcasting [hp:<=20]
  ```
    **Item Slots 1-19 supports /use only right now:**
  ```
  #showtooltip
  /use [combat,hp:<=20]13
  ```
  **Separate Lines:**
  ```
  #showtooltip
  /use [@mouseover alive help hp:<70 nodebuff:"Recently Bandaged"] Runecloth Bandage
  /use [@target, alive, help, hp:<70, nodebuff:Recently_Bandaged] Runecloth Bandage
  /use [@player] Runecloth Bandage
  ```
  **One Line:**
  ```
  #showtooltip
  /use [@mouseover alive help hp:<70 nodebuff:"Recently Bandaged"] Runecloth Bandage; [@target, alive, help, hp:<70, nodebuff:Recently_Bandaged] Runecloth Bandage; [@player] Runecloth Bandage
  ```
  **Note: Classic/Retail macros allow for cascading conditional blocks like below.  This is NOT supported.**  
  ```
  #showtooltip
  /use [@mouseover alive help hp:<70][@target alive help hp:<70][@player][] Runecloth Bandage
  ```

* If a conditional on the table is marked as **Multi** you can provide multiple values in the same condition.  *Only one needs to be true.*  
  `[targeting:party1/party2/party3/party4]` -- targeting one of your party members  
  `[zone:Stormwind/Ironforge]` -- in Stormwind OR Ironforge  
* If a conditional is marked as **Noable** you can prefix the condition with "no" to test the opposite condition.  *All need to be true*  
   `[notargeting:player]` -- not targeting the player  
   `[nozone:Stormwind/Ironforge]` -- not in Stormwind AND not in Ironforge  
* You can specifiy a target unit for the macro by adding in a valid @unitid  
   `/cast [@party1 combat] Intervene`  -- casts Intervene on party member 1 if you (player) are in combat  
* @focus / focus can be used as an @unitid / conditional unitid however Vanilla does not support focus targets, a compatible addon is required to make this function.
* If the conditional allows for a numerical comparison, the format is `condition:>X` or `condition:"Some Value">X`. If you want to compare stacks/rank (where applicable) and not remaining time, use `>#X`.  
  * **Only the player's buffs/debufs can be checked for remaining time**  
  * Valid operators are =, ~=, >, >=, <, <=
* You can omit the value of a conditional if you want to check the same spell/item that you are using in the action.  
  `[debuff:"Sunder Armor"<#5] Sunder Armor`  ==  `[debuff:<#5] Sunder Armor`  
  `[nobuff:"Mark of the Wild"] Mark of the Wild` == `[nobuff] Mark of the Wild`
* [SuperWoW](https://github.com/balakethelock/SuperWoW) dll mod is required
* [Nampower](https://github.com/pepopo978/nampower) dll mod required
* [UnitXP_SP3](https://codeberg.org/konaka/UnitXP_SP3) dll mod required

### Special Characters
| Character    | Syntax Examples      | Description |
|     :-:      |---------------|-------------|
| !            | !Attack<br/>!Cat Form<br/>!Spell Name | Prefix on spell name.<br/>Will only use the spell if it's not already active.<br/>Can also be used with other spells as shorthand for `nomybuff`   |
| ?            | /use ?[equipped:Swords]</br>/cast ?Presence of Mind | Prevents the icon and tooltip from showing.<br/>Must be the first character. |
| ~            | ~Slow Fall    | Prefix on spell name.  Acts as a toggle ability.<br/>Will cast or cancel the buff/aura if possible. |

### Key Modifiers
| Conditional    | Syntax Examples       | Multi | Noable | Tests For |
|----------------|---------------|  :-:  | :-:    |-----------|
| mod            | [mod]<br/>[mod:ctrl/alt/shift] | * | * | If any mod key is pressed.</br>If one of the listed modifier keys are pressed.  |


### Player Only
| Conditional    | Syntax Examples       | Multi | Noable | Tests For |
|----------------|---------------|  :-:  | :-:    |-----------|
| cdgcd          | [cdgcd]<br/>[cdgcd:"Name"]<br/>[cdgcd:"Name">X] | * | * | If the Spell or Item is on cooldown and optionally if the amount of time left is >= or <= than X seconds.  **GCD NOT IGNORED** |
| channeled      | [channeled] |  | * | If the player is currently channeling a spell. |
| combo          | [combo:>#3]<br/>[combo:#2]</br>[combo:<#5] | * |  * |  If the player has the specified number of combo points. |
| cooldown       | [cooldown]<br/>[cooldown:"Name"]<br/>[cooldown:"Name"<X] | * | * | If the Spell or Item name is on cooldown and optionally if the amount of time left is >= or <= than X seconds. **GCD (if exatly 1.5 sec) IGNORED** |
| equipped       | [equipped:"Name"]<br/>[equipped:Shields]<br/>[equipped:Daggers2] | * | * | If the player has an item name/id or item type equipped.  See [below](#weapon-types) for a list of valid Weapon Types. |
| form           | [form:0/1/2/3/4/5] | * | * | Alias of `stance` |
| group          | [group]<br/>[group:party/raid] | * | * | If the player is in any group or specific group type. |
| known          | [known]<br/>[known:"Name"]</br>[known:"Name">#2] | * | * | If the player knows a spell or talent.  Can optionally check the rank. |
| mybuff         | [mybuff]<br/>[mybuff:"Name"]<br/>[mybuff:"Name">#X]<br/>[mybuff:<X] | * | * | If the player has a buff of the given name.</br>Optionally compared to X number of stacks.<br/>Optionally compared to X time remaining. |
| mydebuff       | [mydebuff]<br/>[mydebuff:"Name"]<br/>[mydebuff:"Name">#X]<br/>[mydebuff:<X] | * | * | If the player has a debuff of the given name.<br/>Optionally compared to X number of stacks.<br/>Optionally compared to X time remaining. |
| myhp           | [myhp:<=X]<br/>[myhp:>=X/<=Y] | * | * | The player's health **PERCENT** compared to X. |
| myhplost       | [myhplost:>=X]<br/>[myhplost:>=X/<=Y] | * |  | The player's lost health compared to X. |
| mypower        | [mypower:>=X]<br/>[mypower:>=X/<=Y] | * | * | The player's power (mana/rage/energy) **PERCENT** compared to X. |
| mypowerlost    | [mypowerlost:>=X]<br/>[mypowerlost:>=X/<=Y] | * |  | The player's lost power (mana/rage/energy) compared to X. |
| myrawhp        | [myrawhp:>=X]<br/>[myrawhp:>=X/<=Y] | * | * | The player's health compared to X. |
| myrawpower     | [myrawpower:>=X]<br/>[myrawpower:>=X/<=Y] | * | * | The player's power (mana/rage/energy) compared to X. |
| druidmana | [druidmana:>=X]<br/>[druidmana:>=X/<=Y] | * | | The druid's mana compared to X. **ONLY FOR DRUIDS** **Works in Cat or Bear form.** |
| reactive       | [reactive]<br/>[reactive:Overpower] | * | * | If the player has the reactive ability (Revenge, Overpower, Riposte, etc.) available to use.<br/><br/>**NOTE: Currently requires the reactive ability to be somewhere on your actionbars in addition to any macros you're using it in.  A planned future update will remove this requirement if using [Nampower](https://github.com/pepopo978/nampower).** |
| resting        | [resting] |  | * | If the player is resting (in an inn/capital city/etc.) |
| stance         | [stance:0/1/2/3/4/5] | * | * | If the player is in stance #.<br/>Supports Shadowform and Stealth as stance 1.|
| stealth        | [stealth] |  | * | If the player is in Stealth or Prowl. |
| zone           | [zone:"Zone"]<br/>[zone:"Zone"/"Another Zone"] | * | * | If the player is in one or more zones of the given name. |
| checkchanneled | [checkchanneled] | * |  | Prevents a spell from being cast if you are already channeling it. |
| stat | [stat:stat>=x/<=y] | * |  | Check if one of the players statistics is greater or less than a specific number. Available Stats: str/strength, agi/agility, stam/stamina, int/intellect, spi/spirit, ap/attackpower, rap/rangedattackpower, healing/healingpower, arcane_power, fire_power, frost_power, nature_power, shadow_power, armor, defense, arcane_res, fire_res, frost_res, nature_res, shadow_res. |
| pet            | [pet]<br/>[pet:Voidwalker]<br/>[pet:Imp/Felhunter] | * | * | If the player has a pet summoned and optionally if it matches the specified pet type(s). Works for Warlock demons and Hunter pets. |
| swimming            | [swimming] |  | * | Druid only, works like reactive but for aquatic form, must have aquatic form on one of your non-stance actionbars.*** |
| mybuffcount            | [mybuffcount:>=X]<br/>[mybuffcount:<=X] |  |  | If the player has more or less auras present than X.|
| queuedspell         | [queuedspell]<br/>[queuedspell:X] |  | * | if the player has any or a specific spell queued with nampower. |
| onswingpending         | [onswingpending] |  | * | If the player has a on swing spell pending.|
| mhimbue/ohimbue         | [mhimbue:Flametongue]<br/>[ohimbue] |  | * | If the player has weapon imbue on their mh/oh.|

### Unit Based
### The default @unitid is usually @target if you don't specify one
### The only conditionals that take conditional:unitid are combat/nocombat and targeting/notargeting
| Conditional    | Syntax        | Multi | Noable | Tests For |
|----------------|---------------|  :-:  | :-:    |-----------|
| alive          | [alive]       |       |    *    | If the @unitid is NOT dead or a ghost. |
| buff           | [buff]<br/>[buff:"Name"]<br/>[buff:"Name">#X]<br/>[buff:"Name"<X] | * | * | If the @unitid has a buff of the given name and optionally if it has >= or <= than X number of stacks. |
| casting        | [casting]<br/>[casting:"Spell Name"] | * |  * |  If the @unitid is casting any or one or more specific spells. |
| combat         | [combat]<br/>[combat:target] | * | * | If the unitid (default is player) is in combat. |
| dead           | [dead]        |       |    *    | If the @unitid is dead or a ghost. |
| debuff         | [debuff]<br/>[debuff:"Name"]<br/>[debuff:"Name">#X]<br/>[debuff:<X] | * | * | If the @unitid has a debuff of the given name and optionally if it has >= or <= than X number of stacks. |
| harm           | [harm]        |       |    *    | If the @unitid is an enemy. |
| help           | [help]        |       |    *    | If the @unitid is friendly. |
| hp             | [hp:>=X]<br/>[hp:>=X/<=Y] | * |  | The @unitid health **PERCENT** compared to X. |
| hplost         | [hplost:>=X]<br/>[hplost:>=X/<=Y] | * |  | The @unitid health lost compared to X. |
| inrange        | [inrange]<br/>[inrange:"Name"] | * | * | If the specified @unitid is in range of the spell. |
| outrange        | [outrange]<br/>[outrange:"Name"] | * |  | If the specified @unitid is out of range of the spell. |
| isnpc          | [isnpc] |  |  | If the @unitid is an npc.<br/>See this [article](https://wowpedia.fandom.com/wiki/UnitId) for a list of unitids.<br/>Not all units are valid in vanilla. |
| isplayer       | [isplayer] |  |  | If the @unitid is a player.<br/>See this [article](https://wowpedia.fandom.com/wiki/UnitId) for a list of unitids.<br/>Not all units are valid in vanilla. |
| member         | [member]      |    *   |       | If the @unitid is in your party OR raid. |
| party          | [party]       |       |    *   | If the @unitid is in your party. |
| power          | [power:>=X]<br/>[power:>=X/<=Y] | * |  | The @unitid power (mana/rage/energy) **PERCENT** compared to X. |
| powerlost      | [powerlost:>=X]<br/>[powerlost:>=X/<=Y] | * |  | The @unitid power (mana/rage/energy) lost compared to X. |
| raid           | [raid]        |       |    *   | If the @unitid is in your raid.  |
| rawphp         | [rawhp:>=X]<br/>[rawhp:>=X/<=Y] | * |  | The @unitid health compared to X. |
| rawpower       | [rawpower:>=X]<br/>[rawpower:>=X/<=Y] | * |  | The @unitid power (mana/rage/energy) compared to X. |
| type           | [type:"Creature Type"] | * | * | If the @unitid is the specified creature type.  See [below](#creature-types) for a list of valid Creature Types. |
| targeting      | [targeting:unitid] | * | * | If the @unitid is targeting the specified unitid.<br/>See this [article](https://wowpedia.fandom.com/wiki/UnitId) for a list of unitids.<br/>Not all units are valid in vanilla. |
| exists         | [exists] |  | * | If the @unitid exists. |
| @unitid        | [@mouseover] |  |  | The @unitid is a valid target. |
| class          | [class:classname1/classname2]<br/>[class:Warrior/Priest] | * | * | The target is a player of the specified class/classes. |
| distance         | [distance:>X]<br/>[distance:<X] |  | * | If the player is closer or farther than X yards from the target.|
| behind         | [behind] |  | * | If the player is behind the target.|
| insight         | [insight] |  | * | If the player is in line of sight of the target. |
| meleerange         | [meleerange] |  | * | If the player is melee range of the target.|

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
