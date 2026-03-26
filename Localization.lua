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
        ["Shadowform"]      = "Shadowform",
        ["Stealth"]         = "Stealth",
        ["Prowl"]           = "Prowl",
        ["Shadowmeld"]      = "Shadowmeld",
        ["Revenge"]         = "Revenge",
        ["Overpower"]       = "Overpower",
        ["Riposte"]         = "Riposte",
        ["Surprise Attack"] = "Surprise Attack",
        ["Lacerate"]        = "Lacerate",
        ["Baited Shot"]     = "Baited Shot",
        ["Counterattack"]   = "Counterattack",
        ["Arcane Surge"]    = "Arcane Surge",
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
        ["Beast"]         = "Wildtier",
        ["Critter"]       = "Kleintier",
        ["Demon"]         = "Dämon",
        ["Dragonkin"]     = "Drachkin",
        ["Elemental"]     = "Elementar",
        ["Giant"]         = "Riese",
        ["Humanoid"]      = "Humanoid",
        ["Mechanical"]    = "Mechanisch",
        ["Not Specified"] = "Nicht spezifiziert",
        ["Totem"]         = "Totem",
        ["Undead"]        = "Untoter",
    }


    CleveRoids.Localized.Spells = {
        ["Shadowform"]      = "Schattengestalt",
        ["Stealth"]         = "Verstohlenheit",
        ["Prowl"]           = "Schleichen",
        ["Shadowmeld"]      = "Schattenmimik",
        ["Revenge"]         = "Rache",
        ["Overpower"]       = "Überwältigen",
        ["Riposte"]         = "Riposte",
        ["Surprise Attack"] = "Überraschungsangriff",
        ["Lacerate"]        = "Zerfleischen",
        ["Baited Shot"]     = "Köderschuss",
        ["Counterattack"]   = "Gegenangriff",
        ["Arcane Surge"]    = "Arkane Woge",
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
        ["Beast"]         = "Bête",
        ["Critter"]       = "Bestiole",
        ["Demon"]         = "Démon",
        ["Dragonkin"]     = "Draconien",
        ["Elemental"]     = "Elémentaire",
        ["Giant"]         = "Géant",
        ["Humanoid"]      = "Humanoïde",
        ["Mechanical"]    = "Machine",
        ["Not Specified"] = "Non spécifié",
        ["Totem"]         = "Totem",
        ["Undead"]        = "Mort-vivant",
    }

    CleveRoids.Localized.Spells = {
        ["Shadowform"]      = "Forme d'Ombre",
        ["Stealth"]         = "Camouflage",
        ["Prowl"]           = "Rôder",
        ["Shadowmeld"]      = "Camouflage dans l'ombre",
        ["Revenge"]         = "Vengeance",
        ["Overpower"]       = "Fulgurance",
        ["Riposte"]         = "Riposte",
        ["Surprise Attack"] = "Attaque surprise",
        ["Lacerate"]        = "Lacérer",
        ["Baited Shot"]     = "Tir appâté",
        ["Counterattack"]   = "Contre-attaque",
        ["Arcane Surge"]    = "Éruption d’arcanes",
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
        ["Beast"]         = "야수",
        ["Critter"]       = "동물",
        ["Demon"]         = "악마",
        ["Dragonkin"]     = "용족",
        ["Elemental"]     = "정령",
        ["Giant"]         = "거인",
        ["Humanoid"]      = "인간형",
        ["Mechanical"]    = "기계",
        ["Not Specified"] = "기타",
        ["Totem"]         = "토템",
        ["Undead"]        = "언데드",
    }

    CleveRoids.Localized.Spells = {
        ["Shadowform"]      = "어둠의 형상",
        ["Stealth"]         = "은신",
        ["Prowl"]           = "숨기",
        ["Shadowmeld"]      = "그림자 숨기",
        ["Revenge"]         = "복수",
        ["Overpower"]       = "제압",
        ["Riposte"]         = "반격",
        ["Surprise Attack"] = "기습",
        ["Lacerate"]        = "괴롭히다",
        ["Baited Shot"]     = "베이티드 샷",
        ["Counterattack"]   = "역습",
        ["Arcane Surge"]    = "비전 쇄도",
    }

    CleveRoids.Localized.ItemTypes = {
        ["Consumable"]  = "소모품",
        ["Reagent"]     = "재료",
        ["Projectile"]  = "발사체",
        ["Trade Goods"] = "거래 용품",
    }
elseif CleveRoids.Locale == "zhCN" then
    CleveRoids.Localized.Shield     = "盾牌"
    CleveRoids.Localized.Bow        = "弓"
    CleveRoids.Localized.Crossbow   = "弩"
    CleveRoids.Localized.Gun        = "枪械"
    CleveRoids.Localized.Thrown     = "投掷武器"
    CleveRoids.Localized.Wand       = "魔杖"
    CleveRoids.Localized.Sword      = "剑"
    CleveRoids.Localized.Staff      = "法杖"
    CleveRoids.Localized.Polearm    = "长柄武器"
    CleveRoids.Localized.Mace       = "锤"
    CleveRoids.Localized.FistWeapon = "拳套"
    CleveRoids.Localized.Dagger     = "匕首"
    CleveRoids.Localized.Axe        = "斧"

    CleveRoids.Localized.Attack    = "攻击"
    CleveRoids.Localized.AutoShot  = "自动射击"
    CleveRoids.Localized.Shoot     = "射击"
    CleveRoids.Localized.SpellRank = "%(等级 %d+%)"

    CleveRoids.Localized.CreatureTypes = {
        ["Beast"]         = "野兽",
        ["Critter"]       = "小动物",
        ["Demon"]         = "恶魔",
        ["Dragonkin"]     = "龙类",
        ["Elemental"]     = "元素生物",
        ["Giant"]         = "巨人",
        ["Humanoid"]      = "人型生物",
        ["Mechanical"]    = "机械",
        ["Not Specified"] = "未指定",
        ["Totem"]         = "图腾",
        ["Undead"]        = "亡灵",
    }

    CleveRoids.Localized.Spells = {
        ["Shadowform"]      = "暗影形态",
        ["Stealth"]         = "潜行",
        ["Prowl"]           = "潜行",
        ["Shadowmeld"]      = "影遁",
        ["Revenge"]         = "复仇",
        ["Overpower"]       = "压制",
        ["Riposte"]         = "还击",
        ["Surprise Attack"] = "偷袭",
        ["Lacerate"]        = "划破",
        ["Baited Shot"]     = "诱饵射击",
        ["Counterattack"]   = "反击",
        ["Arcane Surge"]    = "奥术涌动",
    }

    CleveRoids.Localized.ItemTypes = {
        ["Consumable"]  = "消耗品",
        ["Reagent"]    = "材料",
        ["Projectile"] = "弹药",
        ["Trade Goods"] = "商品",
    }
elseif CleveRoids.Locale == "zhTW" then
    CleveRoids.Localized.Shield     = "盾牌"
    CleveRoids.Localized.Bow        = "長弓"
    CleveRoids.Localized.Crossbow   = "弩"
    CleveRoids.Localized.Gun        = "槍械"
    CleveRoids.Localized.Thrown     = "投擲武器"
    CleveRoids.Localized.Wand       = "魔杖"
    CleveRoids.Localized.Sword      = "劍"
    CleveRoids.Localized.Staff      = "法杖"
    CleveRoids.Localized.Polearm    = "長柄武器"
    CleveRoids.Localized.Mace       = "錘"
    CleveRoids.Localized.FistWeapon = "拳套"
    CleveRoids.Localized.Dagger     = "匕首"
    CleveRoids.Localized.Axe        = "斧"

    CleveRoids.Localized.Attack    = "攻擊"
    CleveRoids.Localized.AutoShot  = "自動射擊"
    CleveRoids.Localized.Shoot     = "射擊"
    CleveRoids.Localized.SpellRank = "%(等級 %d+%)"

    CleveRoids.Localized.CreatureTypes = {
        ["Beast"]         = "野獸",
        ["Critter"]       = "小動物",
        ["Demon"]         = "惡魔",
        ["Dragonkin"]     = "龍類",
        ["Elemental"]     = "元素生物",
        ["Giant"]         = "巨人",
        ["Humanoid"]      = "人型生物",
        ["Mechanical"]    = "機械",
        ["Not Specified"] = "不明",
        ["Totem"]         = "圖騰",
        ["Undead"]        = "不死族",
    }

    CleveRoids.Localized.Spells = {
        ["Shadowform"]      = "暗影形態",
        ["Stealth"]         = "隱形",
        ["Prowl"]           = "徘徊",
        ["Shadowmeld"]      = "影遁",
        ["Revenge"]         = "復仇",
        ["Overpower"]       = "壓倒",
        ["Riposte"]         = "還擊",
        ["Surprise Attack"] = "偷襲",
        ["Lacerate"]        = "劃破",
        ["Baited Shot"]     = "誘餌射擊",
        ["Counterattack"]   = "反擊",
        ["Arcane Surge"]    = "奧術湧動",
    }

    CleveRoids.Localized.ItemTypes = {
        ["Consumable"]  = "消耗品",
        ["Reagent"]     = "材料",
        ["Projectile"]  = "彈藥",
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
        ["Beast"]         = "Животное",
        ["Critter"]       = "Существо",
        ["Demon"]         = "Демон",
        ["Dragonkin"]     = "Дракон",
        ["Elemental"]     = "Элементаль",
        ["Giant"]         = "Великан",
        ["Humanoid"]      = "Гуманоид",
        ["Mechanical"]    = "Механизм",
        ["Not Specified"] = "Не указано",
        ["Totem"]         = "Тотем",
        ["Undead"]        = "Нежить",
    }

    CleveRoids.Localized.Spells = {
        ["Shadowform"]      = "Облик Тени",
        ["Stealth"]         = "Незаметность",
        ["Prowl"]           = "Крадущийся зверь",
        ["Shadowmeld"]      = "Слияние с тенью",
        ["Revenge"]         = "Реванш",
        ["Overpower"]       = "Превосходство",
        ["Riposte"]         = "Ответный удар",
        ["Surprise Attack"] = "Внезапная атака",
        ["Lacerate"]        = "Разрыв",
        ["Baited Shot"]     = "Выстрел с наживкой",
        ["Counterattack"]   = "Контратака",
        ["Arcane Surge"]    = "Чародейский выброс",
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
        ["Beast"]         = "Bestia",
        ["Critter"]       = "Alma",
        ["Demon"]         = "Demonio",
        ["Dragonkin"]     = "Dragon",
        ["Elemental"]     = "Elemental",
        ["Giant"]         = "Gigante",
        ["Humanoid"]      = "Humanoide",
        ["Mechanical"]    = "Mecánico",
        ["Not Specified"] = "No especificado",
        ["Totem"]         = "Tótem",
        ["Undead"]        = "No-muerto",
    }

    CleveRoids.Localized.Spells = {
        ["Shadowform"]      = "Forma de las Sombras",
        ["Stealth"]         = "Sigilo",
        ["Prowl"]           = "Acechar",
        ["Shadowmeld"]      = "Fusión con las sombras",
        ["Revenge"]         = "Revancha",
        ["Overpower"]       = "Abrumar",
        ["Riposte"]         = "Estocada",
        ["Surprise Attack"] = "Ataque sorpresa",
        ["Lacerate"]        = "Lacerar",
        ["Baited Shot"]     = "Disparo con cebo",
        ["Counterattack"]   = "Contraataque",
        ["Arcane Surge"]    = "Oleada Arcana",
    }

    CleveRoids.Localized.ItemTypes = {
        ["Consumable"]  = "Consumible",
        ["Reagent"]     = "Reagent",
        ["Projectile"]  = "Projectile",
        ["Trade Goods"] = "Objetos comerciables",
    }
end

_G["CleveRoids"] = CleveRoids
