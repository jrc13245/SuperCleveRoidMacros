--[[
	Author  : Dennis Werner Garske (DWG) / brian / Mewtiny
	License : MIT License
]]
local _G = _G or getfenv(0)
local CleveRoids = _G.CleveRoids or {}
CleveRoids.Locale = GetLocale()
CleveRoids.Localized = {}

if CleveRoids.Locale == "enUS" or CleveRoids.Locale == "enGB" then
    -- place item in backpack slot 1 and run:
    -- /script local l=GetContainerItemLink(0,1);local _,_,id=string.find(l,"item:(%d+)");local n,_,_,_,t,st=GetItemInfo(id);DEFAULT_CHAT_FRAME:AddMessage("\n\nID: ["..id.."]\nName: ["..n.."]\nType: ["..t.."]\nSub Type: ["..st.."]\n\n");
    CleveRoids.Localized.Shield     = "Shields"
    CleveRoids.Localized.Bow        = "Bows"
    CleveRoids.Localized.Crossbow   = "Crossbows"
    CleveRoids.Localized.Gun        = "Guns"
    CleveRoids.Localized.Thrown     = "Thrown"
    CleveRoids.Localized.Wand       = "Wands"
    CleveRoids.Localized.Sword      = "Swords"
    CleveRoids.Localized.Staff      = "Staves"
    CleveRoids.Localized.Polearm    = "Polearms"
    CleveRoids.Localized.Mace       = "Maces"
    CleveRoids.Localized.FistWeapon = "Fist Weapons"
    CleveRoids.Localized.Dagger     = "Daggers"
    CleveRoids.Localized.Axe        = "Axes"

    CleveRoids.Localized.Attack    = "Attack"
    CleveRoids.Localized.AutoShot  = "Auto Shot"
    CleveRoids.Localized.Shoot     = "Shoot"
    CleveRoids.Localized.SpellRank = "%(Rank %d+%)"

    -- target creature and run:
    -- /script local ct, uc = UnitCreatureType("target"),UnitClassification("target"); DEFAULT_CHAT_FRAME:AddMessage("\n\nUnitCreatureType: ["..ct.."]\nUnitClassificationType: ["..uc.."]\n\n");
    CleveRoids.Localized.CreatureTypes = {
        ["Beast"]         = "Beast",
        ["Critter"]       = "Critter",
        ["Demon"]         = "Demon",
        ["Dragonkin"]     = "Dragonkin",
        ["Elemental"]     = "Elemental",
        ["Giant"]         = "Giant",
        ["Humanoid"]      = "Humanoid",
        ["Mechanical"]    = "Mechanical",
        ["Not specified"] = "Not Specified",
        ["Totem"]         = "Totem",
        ["Undead"]        = "Undead",
    }

    CleveRoids.Localized.Spells = {
        ["Shadowform"]    = "Shadowform",
        ["Stealth"]       = "Stealth",
        ["Prowl"]         = "Prowl",
        ["Revenge"]       = "Revenge",
        ["Overpower"]     = "Overpower",
        ["Riposte"]       = "Riposte",
        ["Surprise Attack"]  = "Surprise Attack",
        ["Mongoose Bite"] = "Mongoose Bite",
        ["Counterattack"] = "Counterattack",
        ["Arcane Surge"]  = "Arcane Surge",
    }

    -- place item in backpack slot 1 and run:
    -- /script local l=GetContainerItemLink(0,1);local _,_,id=string.find(l,"item:(%d+)");local n,_,_,_,t,st=GetItemInfo(id);DEFAULT_CHAT_FRAME:AddMessage("\n\nID: ["..id.."]\nName: ["..n.."]\nType: ["..t.."]\nSub Type: ["..st.."]\n\n");
    CleveRoids.Localized.ItemTypes = {
        ["Consumable"]  = "Consumable",
        ["Reagent"]     = "Reagent",
        ["Projectile"]  = "Projectile",
        ["Trade Goods"] = "Trade Goods",
    }
elseif CleveRoids.Locale == "deDE" then
    CleveRoids.Localized.Shield     = "Schilde"
    CleveRoids.Localized.Bow        = "Bögen"
    CleveRoids.Localized.Crossbow   = "Armbrüste"
    CleveRoids.Localized.Gun        = "Waffen"
    CleveRoids.Localized.Thrown     = "Geworfen"
    CleveRoids.Localized.Wand       = "Zauberstäbe"
    CleveRoids.Localized.Sword      = "Schwerter"
    CleveRoids.Localized.Staff      = "Dauben"
    CleveRoids.Localized.Polearm    = "Stangenwaffen"
    CleveRoids.Localized.Mace       = "Streitkolben"
    CleveRoids.Localized.FistWeapon = "Faustwaffen"
    CleveRoids.Localized.Dagger     = "Dolche"

    CleveRoids.Localized.Axe       = "Äxte"
    CleveRoids.Localized.Attack    = "Angriff"
    CleveRoids.Localized.AutoShot  = "Automatischer Schuss"
    CleveRoids.Localized.Shoot     = "Schießen"
    CleveRoids.Localized.SpellRank = "%(Rank %d+%)"

    CleveRoids.Localized.CreatureTypes = {
        ["Wildtier"]           = "Beast",
        ["Kleintier"]          = "Critter",
        ["Dämon"]              = "Demon",
        ["Drachkin"]           = "Dragonkin",
        ["Elementar"]          = "Elemental",
        ["Riese"]              = "Giant",
        ["Humanoid"]           = "Humanoid",
        ["Mechanisch"]         = "Mechanical",
        ["Nicht spezifiziert"] = "Not Specified",
        ["Totem"]              = "Totem",
        ["Untoter"]            = "Undead",
    }


    CleveRoids.Localized.Spells = {
        ["Shadowform"]    = "Schattengestalt",
        ["Stealth"]       = "Verstohlenheit",
        ["Prowl"]         = "Schleichen",
        ["Revenge"]       = "Rache",
        ["Overpower"]     = "Überwältigen",
        ["Riposte"]       = "Riposte",
        ["Surprise Attack"]  = "Überraschungsangriff",
        ["Mongoose Bite"] = "Mungobiss",
        ["Counterattack"] = "Gegenangriff",
        ["Arcane Surge"]  = "Arkane Woge",
    }


    CleveRoids.Localized.ItemTypes = {
        ["Consumable"]  = "Verbrauchsmaterial",
        ["Reagent"]     = "Reagens",
        ["Projectile"]  = "Projektil",
        ["Trade Goods"] = "Handwerkswaren",
    }
elseif CleveRoids.Locale == "frFR" then
    CleveRoids.Localized.Shield     = "Boucliers"
    CleveRoids.Localized.Bow        = "Arcs"
    CleveRoids.Localized.Crossbow   = "Arbalètes"
    CleveRoids.Localized.Gun        = "Armes à feu"
    CleveRoids.Localized.Thrown     = "Thrown"
    CleveRoids.Localized.Wand       = "Wands"
    CleveRoids.Localized.Sword      = "Swords"
    CleveRoids.Localized.Staff      = "Staves"
    CleveRoids.Localized.Polearm    = "Polearms"
    CleveRoids.Localized.Mace       = "Maces"
    CleveRoids.Localized.FistWeapon = "Fist Weapons"
    CleveRoids.Localized.Dagger     = "Daggers"
    CleveRoids.Localized.Axe        = "Axes"

    CleveRoids.Localized.Attack    = "Attack"
    CleveRoids.Localized.AutoShot  = "Auto Shot"
    CleveRoids.Localized.Shoot     = "Shoot"
    CleveRoids.Localized.SpellRank = "%(Rank %d+%)"

    CleveRoids.Localized.CreatureTypes = {
        ["Bête"]         = "Beast",
        ["Bestiole"]     = "Critter",
        ["Démon"]        = "Demon",
        ["Draconien"]    = "Dragonkin",
        ["Elémentaire"]  = "Elemental",
        ["Géant"]        = "Giant",
        ["Humanoïde"]    = "Humanoid",
        ["Machine"]      = "Mechanical",
        ["Non spécifié"] = "Not Specified",
        ["Totem"]        = "Totem",
        ["Mort-vivant"]  = "Undead",
    }

    CleveRoids.Localized.Spells = {
        ["Shadowform"]    = "Forme d'Ombre",
        ["Stealth"]       = "Camouflage",
        ["Prowl"]         = "Rôder",
        ["Revenge"]       = "Vengeance",
        ["Overpower"]     = "Fulgurance",
        ["Riposte"]       = "Riposte",
        ["Surprise Attack"]  = "Attaque surprise",
        ["Mongoose Bite"] = "Morsure de la mangouste",
        ["Counterattack"] = "Contre-attaque",
        ["Arcane Surge"]  = "Éruption d’arcanes",
    }

    CleveRoids.Localized.ItemTypes = {
        ["Consumable"]  = "Consommable",
        ["Reagent"]     = "Reagent",
        ["Projectile"]  = "Projectile",
        ["Trade Goods"] = "Artisanat",
    }
elseif CleveRoids.Locale == "koKR" then
    CleveRoids.Localized.Shield     = "Shields"
    CleveRoids.Localized.Bow        = "Bows"
    CleveRoids.Localized.Crossbow   = "Crossbows"
    CleveRoids.Localized.Gun        = "Guns"
    CleveRoids.Localized.Thrown     = "Thrown"
    CleveRoids.Localized.Wand       = "Wands"
    CleveRoids.Localized.Sword      = "Swords"
    CleveRoids.Localized.Staff      = "Staves"
    CleveRoids.Localized.Polearm    = "Polearms"
    CleveRoids.Localized.Mace       = "Maces"
    CleveRoids.Localized.FistWeapon = "Fist Weapons"
    CleveRoids.Localized.Dagger     = "Daggers"
    CleveRoids.Localized.Axe        = "Axes"

    CleveRoids.Localized.Attack    = "Attack"
    CleveRoids.Localized.AutoShot  = "Auto Shot"
    CleveRoids.Localized.Shoot     = "Shoot"
    CleveRoids.Localized.SpellRank = "%(Rank %d+%)"

    CleveRoids.Localized.CreatureTypes = {
        ["야수"]   = "Beast",
        ["동물"]   = "Critter",
        ["악마"]   = "Demon",
        ["용족"]   = "Dragonkin",
        ["정령"]   = "Elemental",
        ["거인"]   = "Giant",
        ["인간형"] = "Humanoid",
        ["기계"]   = "Mechanical",
        ["기타"]   = "Not Specified",
        ["토템"]   = "Totem",
        ["언데드"] = "Undead",
    }

    CleveRoids.Localized.Spells = {
        ["Shadowform"]    = "어둠의 형상",
        ["Stealth"]       = "은신",
        ["Prowl"]         = "숨기",
        ["Revenge"]       = "복수",
        ["Overpower"]     = "제압",
        ["Riposte"]       = "반격",
        ["Surprise Attack"]  = "기습",
        ["Mongoose Bite"] = "살쾡이의 이빨",
        ["Counterattack"] = "역습",
        ["Arcane Surge"]  = "비전 쇄도",
    }

    CleveRoids.Localized.ItemTypes = {
        ["Consumable"]  = "소모품",
        ["Reagent"]     = "Reagent",
        ["Projectile"]  = "Projectile",
        ["Trade Goods"] = "거래 용품",
    }
elseif CleveRoids.Locale == "zhCN" then
    CleveRoids.Localized.Shield     = "Shields"
    CleveRoids.Localized.Bow        = "Bows"
    CleveRoids.Localized.Crossbow   = "Crossbows"
    CleveRoids.Localized.Gun        = "Guns"
    CleveRoids.Localized.Thrown     = "Thrown"
    CleveRoids.Localized.Wand       = "Wands"
    CleveRoids.Localized.Sword      = "Swords"
    CleveRoids.Localized.Staff      = "Staves"
    CleveRoids.Localized.Polearm    = "Polearms"
    CleveRoids.Localized.Mace       = "Maces"
    CleveRoids.Localized.FistWeapon = "Fist Weapons"
    CleveRoids.Localized.Dagger     = "Daggers"
    CleveRoids.Localized.Axe        = "Axes"

    CleveRoids.Localized.Attack    = "Attack"
    CleveRoids.Localized.AutoShot  = "Auto Shot"
    CleveRoids.Localized.Shoot     = "Shoot"
    CleveRoids.Localized.SpellRank = "%(Rank %d+%)"

    CleveRoids.Localized.CreatureTypes = {
        ["野兽"]    = "Beast",
        ["小动物"]  = "Critter",
        ["恶魔"]    = "Demon",
        ["龙类"]    = "Dragonkin",
        ["元素生物"] = "Elemental",
        ["巨人"]     = "Giant",
        ["人型生物"] = "Humanoid",
        ["机械"]     = "Mechanical",
        ["未指定"]   = "Not Specified",
        ["图腾"]     = "Totem",
        ["亡灵"]     = "Undead",
    }

    CleveRoids.Localized.Spells = {
        ["Shadowform"]    = "暗影形态",
        ["Stealth"]       = "潜行",
        ["Prowl"]         = "潜行",
        ["Revenge"]       = "复仇",
        ["Overpower"]     = "压制",
        ["Riposte"]       = "还击",
        ["Surprise Attack"]  = "偷袭",
        ["Mongoose Bite"] = "猫鼬撕咬",
        ["Counterattack"] = "反击",
        ["Arcane Surge"]  = "奥术涌动",
    }

    CleveRoids.Localized.ItemTypes = {
        ["Consumable"]  = "消耗品",
        ["Reagent"]     = "Reagent",
        ["Projectile"]  = "Projectile",
        ["Trade Goods"] = "贸易品",
    }
elseif CleveRoids.Locale == "zhTW" then
    CleveRoids.Localized.Shield     = "Shields"
    CleveRoids.Localized.Bow        = "Bows"
    CleveRoids.Localized.Crossbow   = "Crossbows"
    CleveRoids.Localized.Gun        = "Guns"
    CleveRoids.Localized.Thrown     = "Thrown"
    CleveRoids.Localized.Wand       = "Wands"
    CleveRoids.Localized.Sword      = "Swords"
    CleveRoids.Localized.Staff      = "Staves"
    CleveRoids.Localized.Polearm    = "Polearms"
    CleveRoids.Localized.Mace       = "Maces"
    CleveRoids.Localized.FistWeapon = "Fist Weapons"
    CleveRoids.Localized.Dagger     = "Daggers"
    CleveRoids.Localized.Axe        = "Axes"

    CleveRoids.Localized.Attack    = "Attack"
    CleveRoids.Localized.AutoShot  = "Auto Shot"
    CleveRoids.Localized.Shoot     = "Shoot"
    CleveRoids.Localized.SpellRank = "%(Rank %d+%)"

    CleveRoids.Localized.CreatureTypes = {
        ["野獸"]     = "Beast",
        ["小動物"]   = "Critter",
        ["惡魔"]     = "Demon",
        ["龍類"]     = "Dragonkin",
        ["元素生物"] = "Elemental",
        ["巨人"]     = "Giant",
        ["人型生物"] = "Humanoid",
        ["機械"]     = "Mechanical",
        ["不明"]     = "Not Specified",
        ["圖騰"]     = "Totem",
        ["不死族"]   = "Undead",
    }

    CleveRoids.Localized.Spells = {
        ["Shadowform"]    = "暗影形態",
        ["Stealth"]       = "隱形",
        ["Prowl"]         = "徘徊",
        ["Revenge"]       = "復仇",
        ["Overpower"]     = "壓倒",
        ["Riposte"]       = "還擊",
        ["Surprise Attack"]  = "偷襲",
        ["Mongoose Bite"] = "貓鼬咬傷",
        ["Counterattack"] = "反擊",
        ["Arcane Surge"]  = "奧術湧動",
    }

    CleveRoids.Localized.ItemTypes = {
        ["Consumable"]  = "消耗品",
        ["Reagent"]     = "Reagent",
        ["Projectile"]  = "Projectile",
        ["Trade Goods"] = "貿易貨物",
    }
elseif CleveRoids.Locale == "ruRU" then
    CleveRoids.Localized.Shield     = "Shields"
    CleveRoids.Localized.Bow        = "Bows"
    CleveRoids.Localized.Crossbow   = "Crossbows"
    CleveRoids.Localized.Gun        = "Guns"
    CleveRoids.Localized.Thrown     = "Thrown"
    CleveRoids.Localized.Wand       = "Wands"
    CleveRoids.Localized.Sword      = "Swords"
    CleveRoids.Localized.Staff      = "Staves"
    CleveRoids.Localized.Polearm    = "Polearms"
    CleveRoids.Localized.Mace       = "Maces"
    CleveRoids.Localized.FistWeapon = "Fist Weapons"
    CleveRoids.Localized.Dagger     = "Daggers"
    CleveRoids.Localized.Axe        = "Axes"

    CleveRoids.Localized.Attack    = "Attack"
    CleveRoids.Localized.AutoShot  = "Auto Shot"
    CleveRoids.Localized.Shoot     = "Shoot"
    CleveRoids.Localized.SpellRank = "%(Rank %d+%)"

    CleveRoids.Localized.CreatureTypes = {
        ["Животное"]   = "Beast",
        ["Существо"]   = "Critter",
        ["Демон"]      = "Demon",
        ["Дракон"]     = "Dragonkin",
        ["Элементаль"] = "Elemental",
        ["Великан"]    = "Giant",
        ["Гуманоид"]   = "Humanoid",
        ["Механизм"]   = "Mechanical",
        ["Не указано"] = "Not Specified",
        ["Тотем"]      = "Totem",
        ["Нежить"]     = "Undead",
    }

    CleveRoids.Localized.Spells = {
        ["Shadowform"]    = "Облик Тени",
        ["Stealth"]       = "Незаметность",
        ["Prowl"]         = "Крадущийся зверь",
        ["Revenge"]       = "Реванш",
        ["Overpower"]     = "Превосходство",
        ["Riposte"]       = "Ответный удар",
        ["Surprise Attack"]  = "Внезапная атака",
        ["Mongoose Bite"] = "Укус мангуста",
        ["Counterattack"] = "Контратака",
        ["Arcane Surge"]  = "Чародейский выброс",
    }

    CleveRoids.Localized.ItemTypes = {
        ["Consumable"]  = "Расходный материал",
        ["Reagent"]     = "Reagent",
        ["Projectile"]  = "Projectile",
        ["Trade Goods"] = "Хозяйственные товары",
    }
elseif CleveRoids.Locale == "esES" then
    CleveRoids.Localized.Shield     = "Shields"
    CleveRoids.Localized.Bow        = "Bows"
    CleveRoids.Localized.Crossbow   = "Crossbows"
    CleveRoids.Localized.Gun        = "Guns"
    CleveRoids.Localized.Thrown     = "Thrown"
    CleveRoids.Localized.Wand       = "Wands"
    CleveRoids.Localized.Sword      = "Swords"
    CleveRoids.Localized.Staff      = "Staves"
    CleveRoids.Localized.Polearm    = "Polearms"
    CleveRoids.Localized.Mace       = "Maces"
    CleveRoids.Localized.FistWeapon = "Fist Weapons"
    CleveRoids.Localized.Dagger     = "Daggers"
    CleveRoids.Localized.Axe        = "Axes"

    CleveRoids.Localized.Attack    = "Attack"
    CleveRoids.Localized.AutoShot  = "Auto Shot"
    CleveRoids.Localized.Shoot     = "Shoot"
    CleveRoids.Localized.SpellRank = "%(Rank %d+%)"

    CleveRoids.Localized.CreatureTypes = {
        ["Bestia"]          = "Beast",
        ["Alma"]            = "Critter",
        ["Demonio"]         = "Demon",
        ["Dragon"]          = "Dragonkin",
        ["Elemental"]       = "Elemental",
        ["Gigante"]         = "Giant",
        ["Humanoide"]       = "Humanoid",
        ["Mecánico"]        = "Mechanical",
        ["No especificado"] = "Not Specified",
        ["Tótem"]           = "Totem",
        ["No-muerto"]       = "Undead",
    }

    CleveRoids.Localized.Spells = {
        ["Shadowform"]    = "Forma de las Sombras",
        ["Stealth"]       = "Sigilo",
        ["Prowl"]         = "Acechar",
        ["Revenge"]       = "Revancha",
        ["Overpower"]     = "Abrumar",
        ["Riposte"]       = "Estocada",
        ["Surprise Attack"]  = "Ataque sorpresa",
        ["Mongoose Bite"] = "Mordedura de mangosta",
        ["Counterattack"] = "Contraataque",
        ["Arcane Surge"]  = "Oleada Arcana",
    }

    CleveRoids.Localized.ItemTypes = {
        ["Consumable"]  = "Consumible",
        ["Reagent"]     = "Reagent",
        ["Projectile"]  = "Projectile",
        ["Trade Goods"] = "Objetos comerciables",
    }
end

_G["CleveRoids"] = CleveRoids