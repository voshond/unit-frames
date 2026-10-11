local _, CG = ...
local UF, Copy = CG.UF, CG.UF.Util.Copy

-- Independent defaults; never change the shared player/pet definitions.
local member = Copy(UF.Units.definitions.pet)
member.label, member.width = "Group member", 150
member.rows[1].defaults.height = 28
member.rows[1].spec.textDefaults.belowLeft.format = "level:class"
member.rows[2].defaults.height = 6
member.rows[2].defaults.enabled = false
member.portrait.defaults.enabled = false
member.castbar.defaults.placement = "off"
member.auras.clickThrough = true
member.auras.defaults = {
	durationPosition = "CENTER", durationSize = 8, countSize = 8,
	buffs = { filter = "HELPFUL|PLAYER", maxDuration = 120, max = 4, size = 14, position = "top", gap = 1, alignment = "end" },
	debuffs = { sort = "unitDebuff", max = 3, size = 16, position = "bottom", gap = 1 },
}
member.raidTarget = { defaults = { size = 12 } }
CG.definitions = { member = member, target = Copy(UF.Units.definitions.targettarget) }
CG.definitions.target.width = 85
CG.definitions.target.rows[1].defaults.height = 28
CG.definitions.target.rows[2].defaults.enabled = false
CG.definitions.target.auras.clickThrough = true

CG.LayoutSchema = {
	{ key = "enabled", type = "toggle", label = "Show healing panel", default = true },
	{ key = "showSolo", type = "toggle", label = "Show when solo", default = false },
	{ key = "mode", type = "select", label = "Raid layout", default = "subgroups",
		values = { { "subgroups", "Keep raid subgroups" }, { "flat", "Flat grid" } } },
	{ key = "columns", type = "range", label = "Columns / subgroup columns", min = 1, max = 10, step = 1, default = 4 },
	{ key = "rows", type = "range", label = "Rows (flat raid)", min = 4, max = 40, step = 1, default = 10,
		hidden = function(c) return c.mode ~= "flat" end,
		tooltip = "Columns × rows must fit all 40 members. Changing either expands the other if necessary." },
	{ key = "flow", type = "select", label = "Fill grid", default = "down",
		values = { { "down", "Down, then across" }, { "across", "Across, then down" } } },
	{ key = "spacingX", type = "range", label = "Horizontal gap", min = 0, max = 50, step = 1, default = 8 },
	{ key = "spacingY", type = "range", label = "Vertical gap", min = 0, max = 80, step = 1, default = 36,
		tooltip = "Leave room for buff and debuff icons outside each bar." },
	{ key = "sectionGap", type = "range", label = "Section gap", min = 0, max = 80, step = 1, default = 24 },
	{ key = "padding", type = "range", label = "Panel padding", min = 0, max = 40, step = 1, default = 12 },
	{ key = "scale", type = "range", label = "Panel scale", min = 0.5, max = 1.5, step = 0.05, default = 1 },
	{ key = "targets", type = "toggle", label = "Show member targets", default = false },
	{ key = "targetGap", type = "range", label = "Gap to target", min = 0, max = 30, step = 1, default = 4 },
	{ key = "tanks", type = "toggle", label = "Extra tank section (duplicates)", default = false },
	{ key = "tankSlots", type = "range", label = "Maximum tank slots", min = 1, max = 40, step = 1, default = 5 },
}

CG.IndicatorSchema = {
	{ key = "role", type = "toggle", label = "Group role", default = true },
	{ key = "leader", type = "toggle", label = "Leader / assistant", default = true },
	{ key = "ready", type = "toggle", label = "Ready check", default = true },
	{ key = "resurrection", type = "toggle", label = "Incoming resurrection", default = true },
	{ key = "summon", type = "toggle", label = "Summon", default = true },
	{ key = "threat", type = "toggle", label = "Threat", default = false },
	{ key = "phase", type = "toggle", label = "Different phase", default = true },
	{ key = "size", type = "range", label = "Status icon size", min = 8, max = 32, step = 1, default = 14 },
	{ key = "private", type = "toggle", label = "Private encounter auras", default = true },
	{ key = "privateSize", type = "range", label = "Private aura size", min = 10, max = 40, step = 1, default = 18 },
}

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
