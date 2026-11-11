local _, CG = ...
local UF = CG.UF
local Auras, BuffSpells, Util = UF.Components.Auras, UF.BuffSpells, UF.Util
local Presets = {}
CG.BuffPresets = Presets

-- Named buff sets for ClickGrid members, built from catalogue family kinds
-- (BuffSpells.SETS): users pick a set and a placement, never spell IDs.
Presets.LIST = {
	{ id = "heals", label = "My heals & shields", filter = Auras.MY_HEALS },
	{ id = "externals", label = "Externals & defensives", filter = Auras.EXTERNALS },
	{ id = "raid", label = "Raid buffs", filter = Auras.RAID_BUFFS },
}
Presets.PLACEMENTS = {
	{ "outside", "Outside: icons along the cell" },
	{ "inside", "Inside: one spell per corner" },
	{ "bar", "Aura bar under health" },
}
Presets.SIDES = { { "top", "Top" }, { "bottom", "Bottom" } }
Presets.OFF = "off"
Presets.DEFAULT = { preset = "heals", placement = "outside", side = "top" }
-- Bottom left keeps clear of the member's level and class text.
Presets.CORNERS = { "TOPLEFT", "TOPRIGHT", "BOTTOMRIGHT" }

local byId, byFilter = {}, {}
for _, preset in ipairs(Presets.LIST) do byId[preset.id], byFilter[preset.filter] = preset, preset end

function Presets.Get(id)
	return byId[id]
end

function Presets.Values()
	local values = {}
	for i, preset in ipairs(Presets.LIST) do values[i] = { preset.id, preset.label } end
	return values
end

local function Set(id)
	return BuffSpells.SETS[byId[id].filter]
end

-- The set's families, the class's own first, then by rank count (core
-- spells have the most ranks) and name. Own sets keep to the class; an
-- unknown class keeps every class, like BuffSpells.SetIDs.
function Presets.Families(id, class)
	local set, families, roots = Set(id), UF.BuffCatalog.families, {}
	for root, family in pairs(families) do
		if set.kinds[family.kind] and (not set.own or class == nil or family.class == class) then roots[#roots + 1] = root end
	end
	table.sort(roots, function(a, b)
		local left, right = families[a], families[b]
		local leftOwn, rightOwn = left.class == class, right.class == class
		if leftOwn ~= rightOwn then return leftOwn end
		if #left.ids ~= #right.ids then return #left.ids > #right.ids end
		if left.name ~= right.name then return left.name < right.name end
		return a < b
	end)
	return roots
end

-- What a preset means for the player: the native filter string, every rank
-- ID it matches and its families in slot order.
function Presets.Resolve(id)
	local preset = byId[id]
	return {
		filter = Auras.GroupFilter("buffs", preset.filter),
		ids = Auras.IncludeSpellIDs(preset.filter),
		own = Set(id).own == true,
		families = Presets.Families(id, BuffSpells.PlayerClass()),
	}
end

local function SlotPreset(slot)
	local id = slot and slot.spell and tonumber(slot.spell:match("%d+") or "")
	local family = id and BuffSpells.Family(id)
	if not family then return nil end
	for _, preset in ipairs(Presets.LIST) do
		if Set(preset.id).kinds[family.kind] then return preset end
	end
end

-- Writes a placement into member style overrides. The set shows in one
-- placement: the aura block and the aura bar drop their buffs otherwise.
-- OFF only drops them where they show this same set.
function Presets.EditStyle(style, resolved, id, placement, side)
	local filter = byId[id].filter
	local function Leaves(group) return placement ~= Presets.OFF or group.filter == filter end
	if placement == "outside" then
		Util.SetPath(style, "auras.buffs.enabled", true)
		Util.SetPath(style, "auras.buffs.filter", filter)
		Util.SetPath(style, "auras.buffs.position", side or Presets.DEFAULT.side)
	elseif Leaves(resolved.auras.buffs) then
		Util.SetPath(style, "auras.buffs.enabled", false)
	end
	-- Corner slots share the aura block's on/off state.
	if placement == "outside" or placement == "inside" then Util.SetPath(style, "auras.enabled", true) end
	if placement == "bar" then
		if not resolved.auraBar.enabled then Util.SetPath(style, "auraBar.debuffs.enabled", false) end
		Util.SetPath(style, "auraBar.enabled", true)
		Util.SetPath(style, "auraBar.buffs.enabled", true)
		Util.SetPath(style, "auraBar.buffs.filter", filter)
	elseif Leaves(resolved.auraBar.buffs) then
		Util.SetPath(style, "auraBar.buffs.enabled", false)
		if resolved.auraBar.enabled and not resolved.auraBar.debuffs.enabled then Util.SetPath(style, "auraBar.enabled", false) end
	end
end

-- Writes the corner slots: inside fills one family per corner by its first
-- rank; elsewhere only slots showing this same set are switched off.
function Presets.EditSlots(slots, resolved, id, placement, class)
	local roots = Presets.Families(id, class)
	for i, anchor in ipairs(Presets.CORNERS) do
		local key = "slot" .. i
		local root = placement == "inside" and roots[i]
		if root then
			slots[key] = { enabled = true, spell = tostring(root), own = Set(id).own == true, anchor = anchor, offsetX = 0, offsetY = 0 }
		elseif placement == "inside" or SlotPreset(resolved and resolved[key]) == byId[id] then
			slots[key] = slots[key] or {}
			slots[key].enabled = false
		end
	end
end

function Presets.Apply(id, placement, side)
	local class = BuffSpells.PlayerClass()
	local ok, reason = CG.Config.styles.member:Edit("", function(style, resolved)
		Presets.EditStyle(style, resolved, id, placement, side)
	end)
	if not ok then return false, reason end
	return CG.Config.settings:Edit("slots", function(slots, resolved)
		Presets.EditSlots(slots, resolved, id, placement, class)
	end)
end

-- A style string's ClickGrid section (Integration/Profiles.lua) with the set
-- placed: it replaces every store, so it carries all of them as saved.
function Presets.StyleSection(id, placement, side)
	local data = UF.Profiles.sections.clickgrid.export()
	Presets.EditStyle(data.member, CG.Config.styles.member:Resolved(), id, placement, side)
	data.settings.slots = data.settings.slots or {}
	Presets.EditSlots(data.settings.slots, CG.Config:Resolved().slots, id, placement, BuffSpells.PlayerClass())
	return data
end

-- The set and placement the saved settings show, or nil for a custom setup.
function Presets.Detect(member, slots)
	local bar, auras = member.auraBar, member.auras
	if bar.enabled and bar.buffs.enabled and byFilter[bar.buffs.filter] then
		return { preset = byFilter[bar.buffs.filter].id, placement = "bar" }
	end
	if auras.enabled and auras.buffs.enabled and byFilter[auras.buffs.filter] then
		local side = auras.buffs.position == "bottom" and "bottom" or "top"
		return { preset = byFilter[auras.buffs.filter].id, placement = "outside", side = side }
	end
	local preset = auras.enabled and slots.slot1.enabled and SlotPreset(slots.slot1)
	if preset then return { preset = preset.id, placement = "inside" } end
end

function Presets.Current()
	local found = Presets.Detect(CG.Config.styles.member:Resolved(), CG.Config:Resolved().slots) or {}
	return Util.Merge(Util.Copy(Presets.DEFAULT), found)
end

-- Plain sample art for showcases when the client has no spell texture.
local SAMPLE_ICONS = {
	["Rejuvenation"] = [[Interface\Icons\Spell_Nature_Rejuvenation]],
	["Regrowth"] = [[Interface\Icons\Spell_Nature_ResistNature]],
	["Lifebloom"] = [[Interface\Icons\INV_Misc_Herb_Felblossom]],
	["Wild Growth"] = [[Interface\Icons\Ability_Druid_Flourish]],
	["Renew"] = [[Interface\Icons\Spell_Holy_Renew]],
	["Power Word: Shield"] = [[Interface\Icons\Spell_Holy_PowerWordShield]],
	["Prayer of Mending"] = [[Interface\Icons\Spell_Holy_PrayerOfMendingtga]],
	["Riptide"] = [[Interface\Icons\Spell_Nature_Riptide]],
	["Earth Shield"] = [[Interface\Icons\Spell_Nature_SkinofEarth]],
	["Innervate"] = [[Interface\Icons\Spell_Nature_Lightning]],
	["Barkskin"] = [[Interface\Icons\Spell_Nature_StoneClawTotem]],
	["Blessing of Protection"] = [[Interface\Icons\Spell_Holy_SealOfProtection]],
	["Divine Shield"] = [[Interface\Icons\Spell_Holy_DivineIntervention]],
	["Power Infusion"] = [[Interface\Icons\Spell_Holy_PowerInfusion]],
	["Pain Suppression"] = [[Interface\Icons\Spell_Holy_PainSupression]],
	["Mark of the Wild"] = [[Interface\Icons\Spell_Nature_Regeneration]],
	["Gift of the Wild"] = [[Interface\Icons\Spell_Nature_Regeneration]],
	["Thorns"] = [[Interface\Icons\Spell_Nature_Thorns]],
	["Power Word: Fortitude"] = [[Interface\Icons\Spell_Holy_WordFortitude]],
	["Arcane Intellect"] = [[Interface\Icons\Spell_Holy_MagicalSentry]],
	["Battle Shout"] = [[Interface\Icons\Ability_Warrior_BattleShout]],
}
local UNKNOWN_ICON = [[Interface\Icons\INV_Misc_QuestionMark]]
local SAMPLE_TIMES = { { 15, 9 }, { 21, 14 }, { 7, 3 }, { 30, 22 } }

local function Icon(root, family)
	local texture = C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(root)
	return texture or SAMPLE_ICONS[family.name] or UNKNOWN_ICON
end

-- One plain sample aura per family, keyed by its first rank, as cast by the
-- player for own sets and by a party member otherwise.
function Presets.Samples(id, class)
	local own, auras = Set(id).own, {}
	for i, root in ipairs(Presets.Families(id, class)) do
		local timing = SAMPLE_TIMES[i]
		if not timing then break end
		local family = UF.BuffCatalog.families[root]
		auras[i] = { spellId = root, name = family.name, icon = Icon(root, family), duration = timing[1], remaining = timing[2],
			sourceUnit = own and "player" or "party1" }
	end
	return auras
end
