local _, ns = ...
local Media, Util = ns.Media, ns.Util

--[[
A single line of text. Accepts secret strings and numbers: they render
normally, they just can't be read back (GetText returns a secret).

spec (optional):
  host     frame the text spans (left edge to right edge, minus `inset`), so
           the alignment option actually moves the text. Without a host the
           owner anchors the text itself.
  formats  list of format ids (Core/Formats.lua): makes the text a slot that
           shows a preset or custom pieces of text sources. The owner decides
           when to fill it (ShowSample/ShowLive, or an oUF tag).
  context  what the slot's host provides ({ player = true } on the player
           frame); decides which sources and presets it offers and shows.

A slot's `format` is a preset id or "custom". Custom slots show up to
Text.PIECES pieces (piece1, ...: source, before, after) and choose what
happens while casting. The first switch to Custom copies the selected
preset into the pieces; later switches keep the custom edits, and "Edit as
custom text" replaces them with a fresh copy of the selected preset.
]]
local Text = ns.Component:Extend("Text")

Text.JUSTIFY = {
	{ "LEFT", "Left" },
	{ "CENTER", "Centre" },
	{ "RIGHT", "Right" },
}

Text.schema = {
	{ key = "enabled", type = "toggle", label = "Enabled", default = true },
	{ key = "font", type = "font", label = "Font", inherit = "font" },
	{ key = "size", type = "range", label = "Size", min = 6, max = 40, step = 1, inherit = "fontSize" },
	{ key = "outline", type = "select", label = "Outline", values = ns.Theme.OUTLINES, inherit = "fontOutline" },
	{ key = "shadow", type = "toggle", label = "Shadow", default = true },
	{ key = "color", type = "color", label = "Colour", default = { 1, 1, 1, 1 } },
	{ key = "justifyH", type = "select", label = "Alignment", values = Text.JUSTIFY, default = "CENTER" },
}

Text.VERTICAL = {
	{ "auto", "Automatic" },
	{ "middle", "Middle" },
	{ "top", "Top" },
	{ "bottom", "Bottom" },
}

local HOST_OPTIONS = {
	{ key = "vertical", type = "select", label = "Vertical position", values = Text.VERTICAL, default = "auto",
		tooltip = "Automatic: middle, or decided by the owner (e.g. moves up to make room for a text below)." },
	{ key = "inset", type = "range", label = "Edge inset", min = 0, max = 30, step = 1, default = 4,
		tooltip = "Distance from the left and right edge." },
	{ key = "offsetX", type = "range", label = "Offset X", min = -100, max = 100, step = 1, default = 0 },
	{ key = "offsetY", type = "range", label = "Offset Y", min = -50, max = 50, step = 1, default = 0 },
}

-- Slots ---------------------------------------------------------------------

Text.PIECES = 4
Text.CUSTOM = "custom"

Text.WHILE_CASTING = {
	{ "keep", "Keep this text" },
	{ "spell", "Show the spell name" },
}

local function PieceKey(i)
	return "piece" .. i
end

-- Source choices a host can show, labelled by group ("Health: Max").
local function SourceValues(context)
	return function()
		local values = { { "none", "None" } }
		for _, source in ipairs(ns.TextSources.list) do
			if ns.TextTemplate.Available(source, context) then
				values[#values + 1] = { source.id, source.group .. ": " .. source.label }
			end
		end
		return values
	end
end

-- Writes `presetId` (on a host with `context`) into a slot's override
-- group as its custom pieces and selects Custom: all pieces, casting
-- behaviour and the initialised flag at once, as independent tables.
function Text.WriteCustom(group, presetId, context)
	local pieces, whileCasting = ns.Formats.Pieces(presetId, context)
	for i = 1, Text.PIECES do
		group[PieceKey(i)] = pieces[i] or { source = "none", before = "", after = "" }
	end
	group.whileCasting = whileCasting
	group.customInitialized = true
	group.format = Text.CUSTOM
end

--[[
Makes a copied slot override group (`group`, a copy of `source`'s effective
values) valid on a host with `context`: pieces the host can't show become
"none" in place, also retained custom pieces behind a preset. A selected
preset the host can't show at all becomes "none"; one it can partly show
becomes custom pieces with the rest switched off.
]]
function Text.AdaptCopy(group, source, context)
	for i = 1, Text.PIECES do
		local key = PieceKey(i)
		local id = source[key] and source[key].source
		local available = ns.TextSources.Get(id or "none")
		if id and id ~= "none" and not (available and ns.TextTemplate.Available(available, context)) then
			group[key] = ns.Util.Merge(ns.Util.Copy(group[key] or {}), { source = "none" })
		end
	end
	local format = source.format
	if format ~= Text.CUSTOM then
		local availability = ns.Formats.Availability(format, context)
		if availability == "none" then
			group.format = "none"
		elseif availability == "some" then
			Text.WriteCustom(group, format, context)
		end
	end
	return group
end

-- A source option (TextSources.OPTIONS), shown for sources that use it.
local function PieceOption(key)
	for _, opt in ipairs(ns.TextSources.OPTIONS) do
		if opt.key == key then
			return { key = key, type = "select", label = opt.label, values = opt.values, default = opt.default,
				hidden = function(cfg)
					local source = ns.TextSources.Get(cfg.source)
					return not (source and source.options and source.options[key])
				end }
		end
	end
end

local function SlotSchema(spec)
	local context = spec.context
	local function NotCustom(cfg) return cfg.format ~= Text.CUSTOM end
	local schema = {
		{ key = "format", type = "select", label = "Shows", default = "none",
			values = ns.Formats.Values(spec.formats, context, { { Text.CUSTOM, "Custom" } }),
			onSet = function(group, value, before)
				if value == Text.CUSTOM and not before.customInitialized and before.format ~= Text.CUSTOM then
					Text.WriteCustom(group, before.format, context)
				end
			end },
		{ key = "customize", type = "action", label = "Edit as custom text",
			tooltip = "Copy this preset into custom pieces and show them. Replaces earlier custom edits. Custom pieces hide their own spaces and separators when they're empty, so missing data no longer leaves a gap.",
			hidden = function(cfg) return cfg.format == Text.CUSTOM or cfg.format == "none" end,
			invoke = function(store, path)
				store:Edit(path:match("^(.*)%.[^%.]+$"), function(group, resolved)
					Text.WriteCustom(group, resolved.format, context)
				end)
			end },
		{ key = "whileCasting", type = "select", label = "While casting", values = Text.WHILE_CASTING,
			default = "keep", hidden = NotCustom },
		-- Distinguishes retained custom edits (even an empty slot) from none yet.
		{ key = "customInitialized", type = "toggle", label = "Custom text set up", default = false,
			hidden = function() return true end },
	}
	for i = 1, Text.PIECES do
		schema[#schema + 1] = { key = PieceKey(i), type = "group", label = "Piece " .. i, inline = true,
			hidden = NotCustom, schema = {
				{ key = "source", type = "select", label = "Source", values = SourceValues(context), default = "none",
					tooltip = "Values that are often missing (Missing, PvP flag, Resting, Rested, spell name) should carry the separator next to them, so it disappears with them." },
				PieceOption("number"),
				PieceOption("decimals"),
				{ key = "before", type = "text", label = "Text before", default = "",
					hidden = function(cfg) return cfg.source == "none" end,
					tooltip = "Shown only when this piece has text, e.g. \" / \" before Health: Max." },
				{ key = "after", type = "text", label = "Text after", default = "",
					hidden = function(cfg) return cfg.source == "none" end,
					tooltip = "Shown only when this piece has text." },
			} }
	end
	return schema
end

function Text.BuildSchema(spec)
	spec = spec or {}
	local slot = spec.formats and SlotSchema(spec) or {}
	return ns.Util.Copy(ns.Schema.Concat(slot, Text.schema, spec.host and HOST_OPTIONS or {}))
end

function Text:OnCreate(parent)
	self.frame = parent:CreateFontString(nil, "OVERLAY")
end

function Text:OnApply(cfg)
	local fs = self.frame
	Media:ApplyFont(fs, cfg.font, cfg.size, cfg.outline)
	if cfg.shadow then
		fs:SetShadowColor(0, 0, 0, 1)
		fs:SetShadowOffset(1, -1)
	else
		fs:SetShadowOffset(0, 0)
	end
	self.baseColor = CreateColor(Util.UnpackColor(cfg.color))
	self:ApplyColor()
	fs:SetJustifyH(cfg.justifyH)
	fs:SetWordWrap(false)
	self:Layout()
	self.template = self:CompileTemplate(cfg)
end

-- The slot's template: a fully available preset shares the preset's own
-- (also behind its [uf:<id>] tag); the rest compile for this host.
function Text:CompileTemplate(cfg)
	local Formats = ns.Formats
	local format = self.spec.formats and cfg.format or "none"
	if format == Text.CUSTOM then
		local pieces = {}
		for i = 1, Text.PIECES do pieces[i] = cfg[PieceKey(i)] end
		return ns.TextTemplate.Get({ pieces = pieces, whileCasting = cfg.whileCasting }, self.spec.context)
	end
	local preset = Formats.Get(format)
	if not preset.relative and Formats.Availability(preset.id, self.spec.context) == "all" then
		return preset.template
	end
	return ns.TextTemplate.Get(preset, self.spec.context)
end

function Text:GetTemplate()
	return self.template
end

-- The preset id whose shared [uf:<id>] tag shows this slot, if any.
function Text:GetPresetTag()
	local format = self:GetFormat()
	if format ~= Text.CUSTOM and format ~= "none" and self.template == ns.Formats.Get(format).template then
		return format
	end
end

-- Whether the text starts with the unit's name (optionally after its level).
function Text:LeadsWithName()
	local sources = self.template.sources
	return sources[1] == "name" or (sources[1] == "level" and sources[2] == "name")
end

function Text:OnRelease()
	self.template = nil
end

-- Transient room for an adjacent indicator, not a saved text-style override.
function Text:SetLeadingSpace(space)
	self.leadingSpace = space
	self:Layout()
end

function Text:Layout()
	local cfg, fs = self.resolved, self.frame
	if not cfg then return end
	local host = self.spec.host
	if host then
		local vertical = cfg.vertical
		if vertical == "auto" then
			vertical = self.autoVertical or "middle"
		end
		-- top/bottom sit 1px inside the edge; middle is centred.
		local edge, y = "", cfg.offsetY
		if cfg.vertical == "auto" then
			y = y + (self.autoOffset or 0)
		end
		if vertical == "top" then
			edge, y = "TOP", y - 1
		elseif vertical == "bottom" then
			edge, y = "BOTTOM", y + 1
		end
		fs:ClearAllPoints()
		fs:SetPoint(edge .. "LEFT", host, edge .. "LEFT", cfg.inset + cfg.offsetX + (self.leadingSpace or 0), y)
		fs:SetPoint(edge .. "RIGHT", host, edge .. "RIGHT", -cfg.inset + cfg.offsetX, y)
	end
end

-- Where "auto" vertical position goes ("middle", "top", "bottom"), plus a
-- plain y offset (e.g. a line of a centred block); set by the owner before
-- applying. No offset clears it.
function Text:SetAutoVertical(vertical, offset)
	self.autoVertical, self.autoOffset = vertical, offset
end

function Text:GetFormat()
	return self.resolved.format or "none"
end

-- Data API ------------------------------------------------------------------

-- Transient status colour; the condition may be secret. Keep the configured
-- colour as the native false branch, including after a style reapplication.
function Text:SetColorCondition(condition, color)
	if color then
		self.conditionStorage = self.conditionStorage or {}
		self.conditionStorage.condition, self.conditionStorage.color = condition, color
		self.colorCondition = self.conditionStorage
	else
		self.colorCondition = nil
		if self.conditionStorage then
			self.conditionStorage.condition, self.conditionStorage.color = nil, nil
		end
	end
	self:ApplyColor()
end

function Text:ApplyColor()
	local base = self.resolved.color
	local override = self.colorCondition
	if override and ns.Caps.curves then
		local color = C_CurveUtil.EvaluateColorFromBoolean(override.condition,
			override.color, self.baseColor)
		self.frame:SetTextColor(color:GetRGBA())
	else
		self.frame:SetTextColor(Util.UnpackColor(base))
	end
end

function Text:SetText(text)
	self.frame:SetText(text)
end

function Text:SetFormattedText(fmt, ...)
	self.frame:SetFormattedText(fmt, ...)
end

function Text:SetTextColor(r, g, b, a)
	self.frame:SetTextColor(r, g, b, a or 1)
end

-- Fills the text from its template with plain sample values.
function Text:ShowSample(values)
	self.frame:SetText(self.template.sample(values))
end

-- Fills the text from its template with the live (possibly secret) unit data.
function Text:ShowLive(unit)
	self.frame:SetText(self.template.live(unit))
end
