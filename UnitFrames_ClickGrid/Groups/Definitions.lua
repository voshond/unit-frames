local _, CG = ...
local UF, Copy = CG.UF, CG.UF.Util.Copy

-- Independent copies; never change the shared pet/target-of-target definitions.
local member = UF.Units:Derive("pet", {
	label = "Group member", width = 150,
	rows = {
		health = { defaults = { height = 28 }, spec = { textDefaults = { belowLeft = { format = "level:class" } } } },
		power = { defaults = { height = 6, enabled = false } },
	},
	portrait = { defaults = { enabled = false } },
	castbar = { defaults = { enabled = false } },
	auras = { clickThrough = true },
	raidTarget = { defaults = { size = 12 } },
	-- Mouse-transparent so hover and mouseover casts still reach the member.
	categoryAuras = { noMouse = true, defaults = { anchor = "CENTER", size = 18 } },
})
-- Replaces the pet's aura defaults as a whole.
member.auras.defaults = {
	durationPosition = "CENTER", durationSize = 8, countSize = 8,
	buffs = { filter = "HELPFUL|PLAYER|RAID_IN_COMBAT", maxDuration = 120, max = 4, size = 14, position = "top", gap = 1, alignment = "end" },
	debuffs = { sort = "unitDebuff", max = 3, size = 16, position = "bottom", gap = 1 },
}
CG.definitions = {
	member = member,
	target = UF.Units:Derive("targettarget", {
		width = 85,
		rows = { health = { defaults = { height = 28 } }, power = { defaults = { enabled = false } } },
		auras = { clickThrough = true },
		categoryAuras = { noMouse = true, defaults = { enabled = false } },
	}),
}
-- Group bars show status icons instead of the unit frames' PvP flag and elite
-- icon. Status places its own ready check icon among the other indicators and
-- attaches it to the member's ReadyCheck. Targets are not part of the check.
for _, def in pairs(CG.definitions) do
	def.portrait.lazyBackends = true
	def.pvp, def.classification, def.readyCheckIcon = nil, nil, nil
end
CG.definitions.target.readyCheck = nil

CG.LayoutSchema = {
	{ key = "enabled", type = "toggle", label = "Show healing panel", default = true },
	{ key = "showSolo", type = "toggle", label = "Show when solo", default = false },
	{ key = "mode", type = "select", label = "Raid layout", default = "subgroups",
		values = { { "subgroups", "Keep raid subgroups" }, { "flat", "Flat grid" } } },
	{ key = "columns", type = "range", label = "Columns / subgroup columns", min = 1, max = 10, step = 1, default = 4,
		tooltip = "Preferred flat-grid columns, or raid subgroup columns. Across-then-down keeps this wrap width; extra rows accommodate larger raids." },
	{ key = "rows", type = "range", label = "Rows (flat raid)", min = 1, max = 40, step = 1, default = 10,
		hidden = function(c) return c.mode ~= "flat" end,
		tooltip = "Preferred flat-grid rows. Down-then-across keeps this wrap height; extra columns accommodate larger raids. Saved rows and columns never change each other." },
	{ key = "flow", type = "select", label = "Fill grid", default = "down",
		values = { { "down", "Down, then across" }, { "across", "Across, then down" } } },
	{ key = "spacingX", type = "range", label = "Horizontal gap", min = 0, max = 50, step = 1, default = 8 },
	{ key = "spacingY", type = "range", label = "Vertical gap", min = 0, max = 80, step = 1, default = 36,
		tooltip = "Leave room for buff and debuff icons outside each bar." },
	{ key = "sectionGap", type = "range", label = "Section gap", min = 0, max = 80, step = 1, default = 24 },
	{ key = "scale", type = "range", label = "Panel scale", min = 0.5, max = 1.5, step = 0.05, default = 1 },
	{ key = "targetGap", type = "range", label = "Gap to target", min = 0, max = 30, step = 1, default = 4 },
	{ key = "tanks", type = "toggle", label = "Extra tank section (duplicates)", default = false },
	{ key = "tankSlots", type = "range", label = "Maximum tank slots", min = 1, max = 40, step = 1, default = 5 },
}

CG.TitleSchema = {
	{ key = "enabled", type = "toggle", label = "Show titles", default = true },
	{ key = "position", type = "select", label = "Position", default = "above",
		values = { { "above", "Above the group" }, { "below", "Below the group" } } },
	{ key = "alignment", type = "select", label = "Alignment", default = "LEFT", values = UF.Components.Text.JUSTIFY },
	{ key = "gap", type = "range", label = "Gap to frame", min = 0, max = 30, step = 1, default = 5 },
	{ key = "offsetX", type = "range", label = "Horizontal offset", min = -100, max = 100, step = 1, default = 0 },
	{ key = "offsetY", type = "range", label = "Vertical offset", min = -100, max = 100, step = 1, default = 0 },
	{ key = "font", type = "font", label = "Font", inherit = "font" },
	{ key = "size", type = "range", label = "Font size", min = 6, max = 40, step = 1, default = 11 },
	{ key = "outline", type = "select", label = "Font outline", values = UF.Theme.OUTLINES, inherit = "fontOutline" },
	{ key = "shadow", type = "toggle", label = "Shadow", default = true },
	{ key = "color", type = "color", label = "Colour", default = { 1, 1, 1, 1 } },
	{ key = "party", type = "text", label = "Party title", default = "Party" },
	{ key = "tanks", type = "text", label = "Tank section title", default = "Tanks" },
}
for group = 1, 8 do
	CG.TitleSchema[#CG.TitleSchema + 1] = { key = "group" .. group, type = "text", label = "Group / column " .. group .. " title", default = "Group " .. group }
end

local positions = { { "NAME", "Before name" } }
for _, anchor in ipairs(UF.DecorationStack.ANCHORS) do positions[#positions + 1] = Copy(anchor) end

-- Options of an icon in the member's decoration stack, sharing a prefix.
local function Placed(key, label, name, position, order, tooltip, size)
	local function Off(c) return not c[key] end
	local function NoOffset(c) return not c[key] or c[key .. "Position"] == "NAME" end
	return UF.IconPlacement.BuildSchema({
		keys = UF.IconPlacement.PrefixedKeys(key),
		order = { "enabled", "anchor", "size", "order", "gap", "offsetX", "offsetY" },
		defaults = { anchor = position, order = order, size = size or 14 },
		fields = {
			enabled = { label = label },
			anchor = { label = name .. " position", values = positions, hidden = Off,
				tooltip = tooltip .. " Icons sharing a position line up as one group and leave no gap for absent icons: edges and the centre keep the group centred, border and portrait corners grow inward. Before name uses an enabled left-aligned Name text on the health bar." },
			size = { label = name .. " size", hidden = Off, tooltip = false },
			order = { label = name .. " order", hidden = Off,
				tooltip = "Icons sharing a position run left to right (top to bottom on the sides) by order. The raid marker's order is in the member style." },
			gap = { label = name .. " gap", hidden = Off, tooltip = "Space after this icon, to the next icon or the name." },
			offsetX = { label = name .. " horizontal offset", hidden = NoOffset, tooltip = "Moves only this icon, not the rest of its group." },
			offsetY = { label = name .. " vertical offset", hidden = NoOffset, tooltip = "Moves only this icon, not the rest of its group." },
		},
	})
end

local readySchema = UF.Components.ReadyCheckIcon.schema
CG.IndicatorSchema = UF.Schema.Concat(
	Placed("role", "Group role", "Role icon", "NAME", 2,
		"An ordinary unassigned role (including solo) takes no space. Opaque roles keep their slot."),
	Placed("leader", "Leader / assistant", "Leader icon", "TOP", 3, "Leader and assistant share one slot."),
	Placed("ready", "Ready check", "Ready check icon", UF.Schema.Find(readySchema, "anchor").default, 4,
		"Shown during a ready check and briefly after it.", UF.Schema.Find(readySchema, "size").default),
	Placed("death", "Dead / ghost", "Dead / ghost icon", "TOP", 5, "A spirit icon while dead or after releasing as a ghost."),
	Placed("resurrection", "Incoming resurrection", "Resurrection icon", "TOP", 6, "Shown while a resurrection is incoming."),
	{
		{ key = "resurrectionText", type = "toggle", label = "Green health text for incoming resurrection", default = true,
			hidden = function(c) return not c.resurrection end },
	},
	Placed("summon", "Summon", "Summon icon", "TOP", 7, "Shows pending, accepted or declined summons."),
	{
		{ key = "threat", type = "toggle", label = "Threat", default = false },
		{ key = "phase", type = "toggle", label = "Different phase", default = true },
		{ key = "size", type = "range", label = "Other status icon size", min = 8, max = 32, step = 1, default = 14 },
		{ key = "private", type = "toggle", label = "Private encounter auras", default = true },
		{ key = "privatePosition", type = "select", label = "Private aura position", default = "RIGHT",
			values = { { "RIGHT", "Inside right" }, { "LEFT", "Inside left" }, { "TOP", "Inside top" },
				{ "BOTTOM", "Inside bottom" }, { "CENTER", "Centre" } },
			hidden = function(c) return not c.private end,
			tooltip = "The centre belongs to Crowd control & defensives by default." },
		{ key = "privateSize", type = "range", label = "Private aura size", min = 10, max = 40, step = 1, default = 18 },
	})

local slotSchema = {
	{ key = "enabled", type = "toggle", label = "Enabled", default = false },
	{ key = "spell", type = "text", label = "Friendly buff spell IDs", default = "",
		tooltip = "Comma-separated numeric aura spell IDs. Exact slots are only for friendly buffs." },
	{ key = "own", type = "toggle", label = "Only buffs cast by me", default = true },
	{ key = "size", type = "range", label = "Size", min = 10, max = 32, step = 1, default = 14 },
	{ key = "anchor", type = "select", label = "Position", default = "TOPLEFT", values = {
		{ "TOPLEFT", "Top left" }, { "TOPRIGHT", "Top right" },
		{ "BOTTOMLEFT", "Bottom left" }, { "BOTTOMRIGHT", "Bottom right" }, { "CENTER", "Center" },
	} },
	{ key = "offsetX", type = "range", label = "Offset X", min = -100, max = 100, step = 1, default = 0 },
	{ key = "offsetY", type = "range", label = "Offset Y", min = -100, max = 100, step = 1, default = 0 },
}
CG.SlotSchema = {}
for i = 1, 3 do
	CG.SlotSchema[i] = { key = "slot" .. i, type = "group", label = "Friendly buff slot " .. i,
		schema = slotSchema, defaults = { offsetX = (i - 1) * 16 } }
end
