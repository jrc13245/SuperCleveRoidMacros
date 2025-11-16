# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

SuperCleveRoidMacros is a World of Warcraft 1.12.1 (Vanilla) addon that provides enhanced macro functionality with dynamic tooltips, conditional execution, and extended syntax. It requires three DLL mods: **SuperWoW**, **Nampower**, and **UnitXP_SP3** - all are mandatory dependencies.

This addon is built for Turtle WoW (TWoW) private server and combines features from CleverMacro and Roid-Macros with significant extensions.

## Critical Requirements

### Required DLL Mods
The addon **WILL NOT FUNCTION** without all three DLL mods installed:
1. **SuperWoW** (balakethelock) - Provides extended API functions like `SetAutoloot`, `SpellInfo()`, `UnitBuff/UnitDebuff` with spell IDs
2. **Nampower** - Provides `QueueSpellByName`, `IsSpellInRange`, `GetCurrentCastingInfo`, and spell queueing
3. **UnitXP_SP3** (konaka) - Provides `UnitXP()` for distance/positioning checks

The addon checks for these on load in `Core.lua:18-48` and will disable itself with error messages if any are missing.

## Code Architecture

### File Loading Order (SuperCleveRoidMacros.toc)
Files are loaded in this exact order, which is critical for initialization:
1. `Localization.lua` - Sets up `CleveRoids.Localized` for multi-language support
2. `Init.lua` - Initializes the `CleveRoids` global table and environment flags
3. `Utility.lua` - Utility functions, string parsing, comparators, and the debuff tracking library (`CleveRoids.libdebuff`)
4. `Core.lua` - Main addon logic, macro parsing, action evaluation, UI hooks
5. `Conditionals.lua` - Conditional keyword validation functions (`CleveRoids.Keywords`)
6. `Console.lua` - Slash command handlers
7. `ExtensionsManager.lua` - Extension/plugin system for modular features
8. Compatibility layers for other addons (SuperMacro, pfUI, Bongos)
9. Extension modules (MacroLengthWarn, Mouseover integrations, Tooltips)

### Key Global Objects

**`CleveRoids`** - Main global namespace containing:
- `.playerClass` - Player's class (set in `Console.lua`)
- `.Spells`, `.Items`, `.Talents` - Indexed lookups for spells/items/talents
- `.Actions` - Parsed macro data per action button
- `.Sequences` - Cast sequence state tracking
- `.Keywords` - Conditional validation function table (from `Conditionals.lua`)
- `.libdebuff` - Debuff duration tracking system (SuperWoW-based)
- `.hasSuperwow`, `.hasNampower`, `.hasUnitXP` - Feature detection flags
- `.mouseoverUnit` - Current mouseover unit (managed by Extensions)

**`CleveRoidMacros`** - SavedVariables configuration:
- `.realtime` - 0 = event-based updates, 1 = continuous updates (default: 0)
- `.refresh` - Update rate in Hz when realtime=1 (1-10, default: 5)

**`CleveRoids_LearnedDurations`** - SavedVariables for learned debuff durations (per-caster GUID)

**`CleveRoids_ImmunityData`** - SavedVariables for NPC immunity tracking (organized by damage school)

### Core Systems

#### 1. Conditional System (`Conditionals.lua`)
The `CleveRoids.Keywords` table maps conditional keywords to validation functions. Each function receives a `conditionals` table containing:
- `.target` - The UnitID being evaluated (default: "target")
- `.help` / `.harm` - Friendly/enemy flag
- `.action` - The spell/item name being cast
- Additional conditional-specific values (e.g., `.mod`, `.stance`, `.buff`)

**Multi-value conditionals** (marked as "Multi" in README):
- Use `Or()` helper - returns true if ANY value matches
- Example: `[zone:Stormwind/Ironforge]` → true if in either zone

**Negatable conditionals** (marked as "Noable"):
- Use `And()` helper - ALL must be false
- Example: `[nozone:Stormwind/Ironforge]` → true only if in neither zone

**Numeric comparisons** (hp, power, cooldown, etc.):
- Use `CleveRoids.operators` and `CleveRoids.comparators` tables
- Operators: `<`, `>`, `=`, `<=`, `>=`, `~=` (and string aliases: `lt`, `gt`, `eq`, etc.)
- Format in args table: `{operator = ">", amount = 50}`

#### 2. Debuff Timer System (`Utility.lua:328-998`)
The `CleveRoids.libdebuff` system provides accurate debuff tracking:
- Pre-configured durations for 329+ vanilla spells (see `lib.durations`)
- Auto-learning via `UNIT_CASTEVENT` (cast start) and `RAW_COMBATLOG` (fade detection)
- Per-caster GUID storage in `CleveRoids_LearnedDurations` (handles talent variations)
- GUID-based tracking (supports multiple mobs with same name)
- Fallback to static database for unknown spells

**Key functions:**
- `lib:GetDuration(spellID, casterGUID)` - Returns learned or static duration
- `lib:AddEffect(guid, unitName, spellID, duration, stacks, caster)` - Track new debuff
- `lib:UnitDebuff(unit, id)` - Returns: name, _, texture, stacks, dtype, duration, timeleft, caster

#### 3. Immunity Tracking System (`Utility.lua:1000-1380`)
The immunity tracking system automatically learns and tracks NPC immunities from combat log messages:
- **Auto-learning** from combat log: "X's Spell fails. Y is immune."
- Stores immunities by **damage school** (fire, frost, nature, shadow, arcane, holy, physical) in `CleveRoids_ImmunityData`
- Supports both **permanent immunities** and **buff-based immunities** (e.g., boss immune during a shield phase)
- Automatic spell school detection via tooltip scanning and name pattern matching

**Data Structure:**
```lua
CleveRoids_ImmunityData = {
    fire = {
        ["Ragnaros"] = true,  -- Permanent immunity
        ["Vaelastrasz the Corrupt"] = { buff = "Burning Adrenaline" }  -- Conditional immunity
    },
    frost = {
        ["Frozen Core"] = true
    }
}
```

**Key Functions:**
- `CleveRoids.CheckImmunity(unitId, spellOrSchool)` - Check immunity to spell name OR damage school
  - Example: `CheckImmunity("target", "Flame Shock")` or `CheckImmunity("target", "fire")`
  - Automatically detects buff-based immunity by checking target's current buffs
- `CleveRoids.ListImmunities(school)` - List immunity data (all or specific school)
- `CleveRoids.AddImmunity(npcName, school, buffName)` - Manually add immunity
- `CleveRoids.RemoveImmunity(npcName, school)` - Remove immunity entry
- `CleveRoids.ClearImmunities(school)` - Clear immunity data

**Combat Log Parsing:**
- Listens to `RAW_COMBATLOG` event for immunity messages
- Extracts spell name and target name from messages
- If target has exactly one buff when immunity occurs, assumes buff causes immunity
- Otherwise records as permanent immunity

**Console Commands:**
```bash
/cleveroid listimmune [school]           # List all or specific school immunities
/cleveroid addimmune "<NPC>" <school> [buff]  # Add manual immunity
/cleveroid removeimmune "<NPC>" <school> # Remove immunity
/cleveroid clearimmune [school]          # Clear data
```

**Conditional Usage:**
- `[immune:fire]` or `[immune:Flame Shock]` - Check if target is immune
- `[noimmune:nature]` or `[noimmune:"Serpent Sting"]` - Check if NOT immune
- Can omit spell/school to check the action being cast: `[noimmune] Fireball`

#### 4. Macro Parsing and Execution
Macros are parsed in `Core.lua` into action lists. Each action has:
- `.cmd` - Command (e.g., "/cast", "/use", "/castsequence")
- `.args` - Arguments string
- `.conditionals` - Parsed conditional table
- `.sequence` - Cast sequence data (if `/castsequence`)

**Evaluation flow:**
1. `CleveRoids.TestForActiveAction(actions)` iterates action list
2. For each action, `CleveRoids.TestAction(cmd, args)` evaluates conditionals
3. First passing action becomes `.active` and determines icon/tooltip
4. `#showtooltip` at macro start enables dynamic icon/tooltip updates

#### 5. Equipment Swapping System (`Core.lua:57-227`)
Implements queued equipment changes with cooldowns:
- Per-slot cooldown: 1.5s (`EQUIP_COOLDOWN`)
- Global cooldown: 0.5s (`EQUIP_GLOBAL_COOLDOWN`)
- Combat weapon swap protection (checks casting state, on-swing spells)
- `CleveRoids.QueueEquipItem(item, slotName)` - Queue swap
- `CleveRoids.ProcessEquipmentQueue()` - Process queue (called from OnUpdate)

#### 6. Extension System (`ExtensionsManager.lua`)
Modular plugin architecture for addon integrations:
- `CleveRoids.RegisterExtension(name)` creates extension object
- Extensions can register events, hook functions/methods
- Mouseover extensions set `CleveRoids.SetMouseoverFrom(source, unit)` with priority system (pfUI > blizz > tooltip)
- Compatibility extensions handle SuperMacro, pfUI MacroTweak, Bongos action bars

## Common Development Tasks

### Adding a New Conditional Keyword

1. **Add validation function to `Conditionals.lua`:**
```lua
CleveRoids.Keywords = {
    -- Existing conditionals...

    mynewconditional = function(conditionals)
        -- Access parsed values from conditionals table
        local checkValue = conditionals.mynewconditional

        -- For multi-value support, use Or() helper:
        return Or(checkValue, function(val)
            return YourCheckFunction(val)
        end)
    end,

    nomynewconditional = function(conditionals)
        -- Negated version uses And() helper:
        return And(conditionals.nomynewconditional, function(val)
            return not YourCheckFunction(val)
        end)
    end,
}
```

2. **Update README.md** with syntax, examples, and whether it's Multi/Noable

### Adding Support for a New Spell Duration

1. **Add to static database in `Utility.lua`:**
```lua
lib.durations = lib.durations or {
    -- Existing durations...
    [12345] = 30,  -- Spell Name (Rank X) - duration in seconds
}
```

2. **Or let players learn it manually:**
```
/cleveroid learn 12345 30
```

The system will auto-learn durations as players cast spells if not in database.

### Modifying Mouseover Behavior

Mouseover unit determination uses a priority system in `Utility.lua:94-145`:
- Priority levels: pfUI (3), blizzard (3), tooltip (1)
- Extensions call `CleveRoids.SetMouseoverFrom(source, unit)` to set mouseover
- Highest priority source wins
- `CleveRoids.ClearMouseoverFrom(source, unitIfMatch)` to remove

To add new source:
1. Create extension in `Extensions/Mouseover/YourAddon.lua`
2. Hook the addon's frame OnEnter/OnLeave scripts
3. Call `SetMouseoverFrom("youraddon", unitID)` with appropriate priority

### Testing Conditionals

Use `/dump` command to inspect values:
```lua
/script DEFAULT_CHAT_FRAME:AddMessage(tostring(CleveRoids.ValidateHp("target", "<=", 50)))
```

Check `CleveRoids.Keywords` table for function existence:
```lua
/script DEFAULT_CHAT_FRAME:AddMessage(tostring(CleveRoids.Keywords.myconditional ~= nil))
```

## Important Implementation Details

### String Parsing and Quotation Handling
- Spell/item names with spaces can use underscores OR quotes: `[buff:Mark_of_the_Wild]` or `[buff:"Mark of the Wild"]`
- The parser in `Core.lua` uses `CleveRoids.splitStringIgnoringQuotes()` to handle quoted strings
- Rank syntax MUST include parentheses: `Faerie Fire (Feral)(Rank 4)` (not just `Faerie Fire (Feral)`)

### Macro Icon/Tooltip Updates
- Icons update via `CleveRoids.QueueActionUpdate()` which sets `isActionUpdateQueued = true`
- OnUpdate handler processes queue and calls `ActionButton_Update()` on affected buttons
- If `realtime=0` (default), updates only on events (ACTIONBAR_UPDATE, UNIT_AURA, etc.)
- If `realtime=1`, updates continuously at `refresh` rate (CPU intensive)

### Spell Cooldown Handling
- `CleveRoids.GetSpellCooldown(spellName, ignoreGCD)` returns absolute expiry time
- `ignoreGCD=true` treats 1.5s cooldowns as "not on cooldown" (GCD)
- Item cooldowns are separate: `CleveRoids.GetItemCooldown(item)` returns remaining seconds

### Cast Sequence Reset Logic
Cast sequences reset on:
- `reset=X` - X seconds of inactivity
- `reset=target` - Target change
- `reset=combat` - Leaving combat
- `reset=mod` - Modifier key press
- Can combine: `reset=3/target/combat`

State tracked in `CleveRoids.Sequences` by macro slot.

## File Structure Patterns

### Adding New Compatibility Layer
Create `Compatibility/YourAddon.lua`:
```lua
local _G = _G or getfenv(0)
local CleveRoids = _G.CleveRoids or {}

if not YourAddon then return end  -- Check if addon exists

-- Your compatibility code here
-- Usually hooks or event handlers to prevent conflicts

_G["CleveRoids"] = CleveRoids
```

Add to `.toc` file in Compatibility section.

### Adding New Extension
Create `Extensions/YourExtension.lua`:
```lua
local extension = CleveRoids.RegisterExtension("YourExtension")

extension.OnLoad = function()
    -- Initialization code
    extension.RegisterEvent("SOME_EVENT", "OnSomeEvent")
end

extension.OnSomeEvent = function()
    -- Event handler using 'event', 'arg1', etc. globals
end

return extension
```

Add to `.toc` file in Extensions section.

## Performance Considerations

- **Avoid `realtime=1` unless necessary** - Event-based updates (realtime=0) are significantly more efficient
- **Debuff table cleanup** - Runs on target change, throttled to 2s intervals (see `Utility.lua:948`)
- **Spell/item indexing** - Only rebuilt on SPELLS_CHANGED, LEARNED_SPELL_IN_TAB events
- **Reactive spell detection** - Requires abilities on action bars to detect usability (limitation may be removed with Nampower enhancements)

## Console Commands

Defined in `Console.lua`:

```bash
# View/modify settings
/cleveroid                          # Show current settings
/cleveroid realtime 0|1             # Toggle realtime updates
/cleveroid refresh 1-10             # Set update rate (Hz)

# Debuff duration learning
/cleveroid learn <spellID> <dur>    # Manually set duration (seconds)
/cleveroid forget <spellID|all>     # Forget learned duration(s)
/cleveroid debug 0|1                # Toggle learning debug messages
```

## Debugging Tips

1. **Enable debug mode for debuff learning:**
   ```
   /cleveroid debug 1
   ```
   Shows learned durations in chat as debuffs fade.

2. **Check for missing dependencies:**
   Look for error messages on login mentioning SuperWoW/Nampower/UnitXP.

3. **Macro syntax errors:**
   - Check for unmatched quotes or brackets
   - Verify spell/item names are spelled correctly (case-sensitive)
   - Use `#showtooltip` to see which action is evaluating as active

4. **Icon not updating:**
   - Ensure macro starts with `#showtooltip`
   - Check if `realtime=0` and conditional needs event trigger
   - Verify action bar addon compatibility (see Extensions)

## Localization

The `Localization.lua` file provides `CleveRoids.Localized` table with:
- `.Spells` - Localized spell names (keyed by English name)
- `.CreatureTypes` - Creature type translations
- `.Dagger`, `.Sword`, `.Shield`, etc. - Weapon type names

Always use `CleveRoids.Localized.Spells["EnglishName"]` for hardcoded spell references to support non-English clients.

## Known Limitations

1. **Reactive abilities** (Revenge, Overpower, etc.) must be on action bars for detection (workaround may be possible with Nampower)
2. **Aquatic Form** detection uses reactive system (must be on non-stance action bar)
3. **Debuff time-left conditionals** only work on player's own debuffs unless pfUI or internal libdebuff has data
4. **Macro names** must be unique - no blank names, duplicates, or using spell names
5. **Parenthesis in spell names** (e.g., "Faerie Fire (Feral)") MUST include rank: "Faerie Fire (Feral)(Rank X)"
