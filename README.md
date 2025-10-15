# SuperCleveRoid Macros
This was originally an effort to bring the dynamic tooltip and cast sequence functionality of [CleverMacro](https://github.com/DanielAdolfsson/CleverMacro) into [Roid-Macros](https://github.com/MarcelineVQ/Roid-Macros).  It has since expanded after some additional changes I wanted along with feedback from others.  The majority of credit goes to the [original addon authors](#original-addons--authors).  Still a work in progress.

Both [SuperWoW](https://github.com/balakethelock/SuperWoW) and [Nampower](https://github.com/pepopo978/nampower) are REQUIRED.
Check slash command and all conditional lists for new usages! 

---

## Installation
### Manual
1. Download a zip from the green Code button or by clicking [here](https://github.com/jrc13245/SuperCleveRoidMacros/archive/refs/heads/main.zip)
2. Unzip the file and place the folder into your `Interface/Addons` folder.
3. Rename the `SuperCleveRoidMacros-main` folder to `SuperCleveRoidMacros`
4. Check that it is enabled in your addon list in-game.  
5. Make sure you don't have other macro addons that may interfere.  SuperMacro should be compatible.
6. SUPERWOW and NAMPOWER are REQUIRED!


* [SuperWoW](https://github.com/balakethelock/SuperWoW) dll mod is required
* [Nampower](https://github.com/pepopo978/nampower) dll mod is required 


### Turtle WoW Launcher / GitAddonsManager
1. Open either application
2. Click the Add button
3. Paste the url `https://github.com/jrc13245/SuperCleveRoidMacros`
4. Download and keep up to date
### SuperCleveRoidMacros Settings
* /cleveroid - view settings
* /cleveroid realtime 0 or 1 - Force realtime updates rather than event based updates (Default: 0. 1 = on, increases CPU load.)
* /cleveroid refresh X - Set refresh rate. (1 to 10 updates per second. Default: 5)
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

## Commands and Conditionals
### ***Important! Spells, Items, conditionals, etc are case sensitive.  Barring a bug, if there is an issue, it's almost always because something is typed incorrectly.***  
* New Alias for stopcasting 'unqueue'
* New update settings to swap between realtime or event based. Event based is the default and saves cpu and memory usage.
* New Conditional class/noclass.
* Conditional exists is now noable.
* Added alive/dead alias' nodead/noalive.
* Conditional combat can now take unitids.
* Renamed `attacking`/`noattacking` contitionals to `targeting`/`notargeting` for better clarity of what they do.
* All conditionals that should have an implied target of @target now do
* Conditionals can be separated by comma or space
* Conditional arguments with spaces that would need to be replaced with underscores (`_`) can instead be enclosed in quotes.
* Updated syntax for conditionals with stack/time checking  
  * You can use `>, <, =, ~=, >=, <=` as valid operators.  Include a `#` sign to designate you're checking the stack's, not time
    * Operators should be placed after the colon, either by itself (if applicable) or after the argument
      `[power:>20]`, `[debuff:"Sunder Armor<#5"]`, `[buff:Thorns<30]`
  * Omitting an operator or amount will just check that the buff/debuff exists  
  * When stack checking, omitting an operator assumes equals (=)  
  `[debuff:"Sunder Armor#3]` is the same as `[debuff:"Sunder Armor=#3]`  
  * Omitting the argument entirely will assume you want to use the action in the condition check  
  `[nobuff] Power Word: Fortitude` is the same as `[nobuff:"Power Word: Fortitude"] Power Word: Fortitude`
* Updated most conditionals (that make sense) to allow for multiple arguments.  Use a / to separate them.
* Added `plain` [mod] and [nomod] to conditionals
* Added `alive` conditional
* Added `member` conditional
* Added `form` conditional (an alias of stance)
* Added Priest Shadowform to `stance`/`form` conditionals.  Use `[stance:1]` or `[form:1]`
* Added Rogue Stealth to `stance`/`form` conditionals.  Use `[stance:1]` or `[form:1]`
* Added `combo` conditional
* Added `known` conditional
* Added `resting` conditional
* Changed `cooldown` conditional to ignore the GCD (will show usable if the cooldown is exactly 1.5 seconds) -- It felt better but not 100% on keeping this, send feedback.
* Added `cdgcd` conditional that works the same as `cooldown` that will trigger for any length of cooldown
* Added `inrange` conditional ([Nampower](https://github.com/pepopo978/nampower) required)
* Added changes to make usable/mana/range updating show properly in pfUI.
* Added Bongos action bars compatibility support
* Added /runmacro command. Same as /cast {macroname} but always ignores icon/tooltip
* Added /retarget command. Clears your target if it doesn't exist, has 0 hp or if you can't attack it and then targets the nearest enemy
* Added /equipmh command. Equips the weapon into your mainhand slot. 
* Added ? flag to prevent an action from affecting the icon/tooltips.  It must be the first character. 
    ```lua
    #showtooltip
    /use ?Some Item
    /cast [reactive] Overpower; Heroic Strike
    ```
* Updated ! flag as a shortcut easily make spammable spells.
* Added ~ flag to either cast or cancel the buff/aura if possible.  (Toggles the spell on/off)
* Added /stopmacro command. 
* Added conditional use to /startattack /stopattack /stopcasting.
* Added stat conditional. ex: '/cast [hp:<=20 stat:AP>=2000]Bloodthirst'
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

# Usage
## Slash Commands
| Command               | Conditionals Supported | Purpose |
|-----------------------|          :-:           |---------|
| /cleveroid |  | show update settings. /cleveroid realtime 0/1 : /cleveroid refresh 1-10 |
| /target               | * | takes limited conditionals. will target by name first and then if conditionals are not valid will target your last target or clear target. help/harm check in a 40 yd cone in front of you. this is due to client limitations. available conditionals: (help,harm,alive,dead,exists,isplayer,isnpc,type,(no)inrange,(no(de))buff,(raw)hp,(raw)power,(no)casting) |
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
* [SuperWoW](https://github.com/balakethelock/SuperWoW) dll mod is required for some conditionals
* [Nampower](https://github.com/pepopo978/nampower) dll mod required for some conditionals

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
