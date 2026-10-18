local _, ns = ...
local Backdrop, TextBar = ns.Components.Backdrop, ns.Components.TextBar
local Castbar, Portrait, Auras = ns.Components.Castbar, ns.Components.Portrait, ns.Components.Auras
local RaidTarget, PvPFlag, Classification = ns.Components.RaidTarget, ns.Components.PvPFlag, ns.Components.Classification
local ReadyCheckIcon, PointBar = ns.Components.ReadyCheckIcon, ns.Components.PointBar
local RestingIcon = ns.Components.RestingIcon
local CategoryAuras = ns.Components.CategoryAuras

--[[
A unit frame made of rows stacked top to bottom inside one bordered frame.
Each row is a TextBar (bar + left/centre/right text) with its own height and
on/off toggle; switched-off rows collapse and the frame shrinks.

Optional extras:
  portrait  a column left or right, spanning all or the first few visible rows
  castbar   placed as an extra row at the top or bottom, or over the health
            row (it covers the health bar only while casting)
  comboPoints  a row of points at the top, below the power bar or at the bottom
  auras     independently positioned buffs and debuffs on any side
  raidTarget  raid marker on a border, the centre or inside the portrait
  pvp       the unit's PvP flag, placed like the raid marker
  classification  elite, rare or boss marker, placed like the raid marker
  restingIcon  the player's resting zZz, placed like the raid marker
  readyCheckIcon  ready check mark, driven with the ready check tints
  categoryAuras  crowd control and defensive auras over the portrait or
            on an edge anchor

Edge icons (the raid marker, PvP flag, elite marker, resting zZz and
companions' status icons) share one
DecorationStack per frame, so icons on the same anchor stay grouped.

The component only builds and lays out the visuals. Feeding unit data is
done by the owner: oUF for live frames (Units/), fake values in the Workbench.

spec:
  frame     use this frame as the root (the oUF unit button); else one is created
  width     default width (of the rows area, including the border padding)
  resting   offer the resting border (player)
  playerFrame  the frame always shows the player: its texts offer player-only
            sources (XP, resting)
  readyCheck  offer ready check bar tints
  rows      array of {
              key, label,
              spec      TextBar spec (segments, colorInherit, formats, textDefaults)
              defaults  row option defaults, e.g. { height = 24, right = { size = 9 } }
              options   extra row options (schema entries), e.g. health colour mode
            }
  portrait, castbar, comboPoints, auras, auraBar, raidTarget, pvp, classification,
  restingIcon, readyCheckIcon, categoryAuras
            { defaults, ... } to offer that part (see UnitFrame.PARTS;
            auras also take cancelBuffs and clickThrough; auraBar takes
            collapsible: the row can lend its space to the health bar;
            comboPoints takes available = false: the player's class has none,
            so the row takes no space)

Access: GetRow(key) and GetPart(key) return a row's TextBar or a present
part's component; Rows() and Parts() iterate them with their resolved config.
GetReadyCheck() returns the ReadyCheck presenter when the spec offers one.
]]
local UnitFrame = ns.Component:Extend("UnitFrame")

UnitFrame.CASTBAR_PLACEMENTS = {
	{ "top", "Extra row at the top" },
	{ "bottom", "Extra row at the bottom" },
	{ "health", "Over the health bar" },
	{ "portrait", "Replace portrait while casting" },
}

UnitFrame.POINT_BAR_POSITIONS = {
	{ "top", "Extra row at the top" },
	{ "power", "Below the power bar" },
	{ "bottom", "Extra row at the bottom" },
}

UnitFrame.SIDES = {
	{ "LEFT", "Left" },
	{ "RIGHT", "Right" },
}

UnitFrame.RANGE_MODES = {
	{ "group", "Group range" },
	{ "spell", "Spell range" },
}

-- Shared choices keep copied settings valid on units with fewer rows.
UnitFrame.PORTRAIT_ROW_SPANS = {
	{ 0, "All rows" },
	{ 1, "1 row" },
	{ 2, "2 rows" },
	{ 3, "3 rows" },
	{ 4, "4 rows" },
}

-- A component's schema with `extra` options after "enabled" (or at the
-- top), leaving out keys listed in `skip`.
local function GroupSchema(options, extra, skip)
	return ns.Schema.Without(ns.Schema.Insert(options, "enabled", extra), skip)
end

local function HeightOption(default, hidden)
	return { key = "height", type = "range", label = "Height", min = 2, max = 100, step = 1, default = default or 20,
		hidden = hidden }
end

--[[
Optional parts, declared once. A unit offers a part when its spec has the
key ({ defaults, ... }); the order is creation, apply, binding and frame-level
order. Every part is an owned child component, found with GetPart(key).
Adding a part here is enough for schema, lifecycle and iteration; its data
(oUF binding, samples, polled previews) is declared in Units/Drivers.lua.
  schema(partSpec)     the part's option group (beforeRows: listed above the rows)
  create(frame, ps, native)  builds the component; native: the frame uses
                       native layout (see IsNativeLayout)
  apply(part, cfg)     optional, after the part's config is applied
  stack                a StackIcon: joins the frame's DecorationStack
]]
UnitFrame.PARTS = {
	{ key = "portrait", label = "Portrait", beforeRows = true,
		schema = function()
			return GroupSchema(Portrait.schema, {
				{ key = "position", type = "select", label = "Side", values = UnitFrame.SIDES, default = "LEFT" },
				{ key = "rowSpan", type = "select", label = "Rows to span", values = UnitFrame.PORTRAIT_ROW_SPANS, default = 0,
					tooltip = "Count visible rows from the top, including a castbar in its own row. Disabled rows are skipped. Rows below the portrait use the full width. All rows follows the whole frame." },
				{ key = "size", type = "range", label = "Width", min = 0, max = 200, step = 1, default = 0,
					tooltip = "0 = square, as wide as the rows the portrait spans are tall." },
				{ key = "gap", type = "range", label = "Gap to the bars", min = 0, max = 20, step = 1, default = 2 },
			})
		end,
		create = function(frame, partSpec, _, config)
			return Portrait:New(frame, config, { lazyBackends = partSpec.lazyBackends })
		end },
	{ key = "castbar", label = "Castbar",
		schema = function(partSpec)
			local function OverHealth(cfg)
				return cfg.placement == "health" or cfg.placement == "portrait"
			end
			local schema = ns.Schema.Override(Castbar.BuildSchema(partSpec), "portraitLayout", {
				hidden = function(cfg) return cfg.placement ~= "portrait" end,
			})
			return GroupSchema(schema, {
				{ key = "placement", type = "select", label = "Placement", values = UnitFrame.CASTBAR_PLACEMENTS,
					default = "bottom" },
				HeightOption(18, OverHealth),
			})
		end,
		create = function(frame, partSpec, native, config)
			local castbar = Castbar:New(frame, config, { nativeLayout = native, playerCast = partSpec.playerCast })
			castbar:Hide()
			return castbar
		end },
	{ key = "comboPoints", label = "Combo points",
		schema = function()
			local schema = ns.Schema.Override(PointBar.schema, "enabled", {
				tooltip = "Rogues and druids. Combo points are stored on your target: the target frame shows yours on it, and a player frame row shows those on your current target. For other classes the row takes no space.",
			})
			return GroupSchema(schema, {
				{ key = "position", type = "select", label = "Placement", values = UnitFrame.POINT_BAR_POSITIONS,
					default = "power" },
				HeightOption(8),
			})
		end,
		create = function(frame, partSpec) return PointBar:New(frame, {}, { available = partSpec.available }) end,
		-- A class without combo points neither shows nor binds the row.
		apply = function(points, cfg) points:SetEnabled(cfg.enabled and points.spec.available ~= false) end },
	{ key = "auras", label = "Buffs & debuffs",
		schema = function() return Auras.schema end,
		create = function(frame, partSpec, _, config)
			return Auras:New(frame, config, { cancelBuffs = partSpec.cancelBuffs, clickThrough = partSpec.clickThrough })
		end },
	{ key = "auraBar", label = "Buff & debuff icon row",
		schema = function(partSpec) return ns.Components.AuraBar.BuildSchema(partSpec) end,
		create = function(frame, partSpec, _, config)
			return ns.Components.AuraBar:New(frame, config, { clickThrough = true, collapsible = partSpec.collapsible })
		end },
	{ key = "raidTarget", label = "Raid target icon", stack = true,
		schema = function() return RaidTarget.schema end,
		create = function(frame, _, native, config) return RaidTarget:New(frame, config, { nativeLayout = native }) end },
	{ key = "pvp", label = "PvP flag icon", stack = true,
		schema = function() return PvPFlag.schema end,
		create = function(frame, _, native, config) return PvPFlag:New(frame, config, { nativeLayout = native }) end },
	{ key = "classification", label = "Elite / rare icon", stack = true,
		schema = function() return Classification.schema end,
		create = function(frame, _, native, config) return Classification:New(frame, config, { nativeLayout = native }) end },
	{ key = "restingIcon", label = "Resting icon", stack = true,
		schema = function() return RestingIcon.schema end,
		create = function(frame, _, native, config) return RestingIcon:New(frame, config, { nativeLayout = native }) end },
	{ key = "readyCheckIcon", label = "Ready check icon", stack = true,
		schema = function() return ReadyCheckIcon.schema end,
		create = function(frame, _, native, config) return ReadyCheckIcon:New(frame, config, { nativeLayout = native }) end },
	{ key = "categoryAuras", label = "Crowd control & defensives", stack = true,
		schema = function() return CategoryAuras.schema end,
		create = function(frame, partSpec, _, config)
			return CategoryAuras:New(frame, config, { noMouse = partSpec.noMouse })
		end },
}

function UnitFrame:OnCreate(parent, spec)
	self.frame = spec.frame or CreateFrame("Frame", nil, parent)
	self.rangeInRange, self.rangeChecked = true, false
	-- The unit button may not be a BackdropTemplate frame; draw the border on a child.
	self.border = CreateFrame("Frame", nil, self.frame, "BackdropTemplate")
	self.border:SetAllPoints(self.frame)
	self.border:SetFrameLevel(self.frame:GetFrameLevel())

	self.rows = {}
	self.rowsByKey = {}
	local native = spec.auraBar and spec.auraBar.collapsible or nil
	self.nativeLayout = native
	for _, def in ipairs(spec.rows) do
		local rowSpec = UnitFrame.RowSpec(spec, def)
		-- Its bar follows a collapsing icon row's native extent.
		if native and def.key == "health" then
			rowSpec.nativeLayout = true
		end
		local row = self:Own(TextBar:New(self.frame, self:ChildConfig(def.key), rowSpec))
		self.rows[#self.rows + 1] = { def = def, component = row }
		self.rowsByKey[def.key] = row
	end
	self.decorations = ns.DecorationStack:New()
	self.parts = {}
	self.partsByKey = {}
	for _, part in ipairs(UnitFrame.PARTS) do
		if spec[part.key] then
			local component = self:Own(part.create(self.frame, spec[part.key], native, self:ChildConfig(part.key)))
			self.parts[#self.parts + 1] = { def = part, component = component }
			self.partsByKey[part.key] = component
		end
	end
	if spec.readyCheck then
		self.readyCheck = ns.ReadyCheck:New(self.frame, function(color, amount)
			for _, row in ipairs(self.rows) do
				if color then row.component:SetTint(color[1], color[2], color[3], amount)
				else row.component:SetTint(nil) end
			end
		end)
		self.readyCheck:Attach(self.partsByKey.readyCheckIcon)
	end
end

-- A row's spec on this frame: its texts learn what the frame provides.
local rowSchemaOwners = setmetatable({}, { __mode = "k" })
function UnitFrame.RowSpec(spec, def)
	local rowSpec = ns.Util.Merge(ns.Util.Copy(def.spec), { textContext = { player = spec.playerFrame == true } })
	if spec.schemaOwner then
		local owners = rowSchemaOwners[spec.schemaOwner]
		if not owners then owners = {}; rowSchemaOwners[spec.schemaOwner] = owners end
		owners[def.key] = owners[def.key] or {}
		rowSpec.schemaOwner = owners[def.key]
	end
	return rowSpec
end

function UnitFrame.BuildSchema(spec)
	local schema = {
		{ key = "width", type = "range", label = "Width", min = 60, max = 600, step = 1, default = spec.width or 230 },
		{ key = "spacing", type = "range", label = "Row spacing", min = 0, max = 20, step = 1, default = 1 },
		{ key = "border", type = "group", label = "Frame border", schema = Backdrop.schema,
			defaults = { enabled = true } },
		{ key = "range", type = "group", label = "Out-of-range opacity", schema = {
			{ key = "enabled", type = "toggle", label = "Enabled", default = false },
			{ key = "outsideAlpha", type = "range", label = "Out-of-range opacity", min = 0, max = 1, step = 0.05, default = 0.55,
				tooltip = "0 = transparent, 1 = fully opaque. In-range and unavailable checks stay fully opaque. Fades the whole frame, including its extras." },
			{ key = "mode", type = "select", label = "Range check", values = UnitFrame.RANGE_MODES, default = "group",
				tooltip = "Group range uses the game's group-member check (normally 40 yards), not enemy distance. Spell range checks the chosen spell against this frame's unit, including enemy targets." },
			{ key = "spell", type = "text", label = "Spell ID or name", default = "",
				prerequisite = { path = "range.mode", message = "Choose Spell range under Range check to set a spell." },
				hidden = function(cfg) return cfg.mode ~= "spell" end,
				tooltip = "Choose a spell you know that applies to this unit (a heal for allies, an attack for enemies). Unknown spells, invalid targets and spells without a range check do not fade the frame. Names must match your client language." },
		} },
	}
	if spec.resting then
		schema[#schema + 1] = { key = "resting", type = "group", label = "Resting border", schema = {
			{ key = "enabled", type = "toggle", label = "Enabled", default = true },
			{ key = "color", type = "color", label = "Resting colour", default = { 1, 0.753, 0.157, 1 } },
			{ key = "period", type = "range", label = "Pulse duration (seconds)", min = 2, max = 10, step = 0.5, default = 4,
				tooltip = "Time for one slow fade to the resting colour and back. Requires a visible frame border." },
		} }
	end
	if spec.readyCheck then
		schema[#schema + 1] = { key = "readyCheck", type = "group", label = "Ready check", schema = ns.ReadyCheck.schema }
	end
	local function AddParts(beforeRows)
		for _, part in ipairs(UnitFrame.PARTS) do
			local partSpec = spec[part.key]
			if partSpec and (part.beforeRows or false) == beforeRows then
				schema[#schema + 1] = { key = part.key, type = "group", label = part.label,
					schema = part.schema(partSpec), defaults = partSpec.defaults }
			end
		end
	end
	AddParts(true)
	for _, row in ipairs(spec.rows) do
		local extra = { HeightOption() }
		for _, opt in ipairs(row.options or {}) do
			extra[#extra + 1] = opt
		end
		schema[#schema + 1] = { key = row.key, type = "group", label = row.label,
			schema = GroupSchema(TextBar.BuildSchema(UnitFrame.RowSpec(spec, row)), extra), defaults = row.defaults }
	end
	AddParts(false)
	return ns.Util.Copy(schema)
end

function UnitFrame:OnApply(cfg)
	Backdrop.ApplyTo(self.border, cfg.border)
	for _, row in ipairs(self.rows) do
		self:ApplyChild(row.component, row.def.key)
	end
	for _, part in ipairs(self.parts) do
		self:ApplyChild(part.component, part.def.key)
		if part.def.apply then part.def.apply(part.component, cfg[part.def.key]) end
	end
	self:Layout()
	self:ApplyRangeOpacity()
	self:ApplyRestingBorder()
	if self.readyCheck then self.readyCheck:Apply(cfg.readyCheck) end
end

-- Resting is a plain player state (IsResting), never opaque unit data.
-- Only the unprotected border child gets an update script.
local function PulseRestingBorder(_, elapsed, component)
	component.restingElapsed = (component.restingElapsed + elapsed) % component.resolved.resting.period
	component:ColorRestingBorder(0.5 - 0.5 * math.cos(component.restingElapsed * 2 * math.pi / component.resolved.resting.period))
end

function UnitFrame:ColorRestingBorder(amount)
	local base, tint = self.resolved.border.color, self.resolved.resting.color
	Backdrop.SetBorderColor(self.border,
		base[1] * (1 - amount) + tint[1] * amount,
		base[2] * (1 - amount) + tint[2] * amount,
		base[3] * (1 - amount) + tint[3] * amount,
		(base[4] or 1) * (1 - amount) + (tint[4] or 1) * amount)
end

function UnitFrame:ApplyRestingBorder()
	local cfg = self.resolved
	self.border:SetScript("OnUpdate", nil)
	if cfg.resting and cfg.resting.enabled and self.resting and cfg.border.enabled and cfg.border.border ~= "None" then
		if self.restingAnimated ~= false then
			self.restingElapsed = self.restingElapsed or 0
			PulseRestingBorder(self.border, 0, self)
			self.border:SetScript("OnUpdate", function(border, elapsed) PulseRestingBorder(border, elapsed, self) end)
		else
			self:ColorRestingBorder(1)
		end
	else
		self.restingElapsed = 0
		Backdrop.SetBorderColor(self.border, ns.Util.UnpackColor(cfg.border.color))
	end
end

function UnitFrame:SetResting(resting, animated)
	self.resting, self.restingAnimated = resting, animated
	self:ApplyRestingBorder()
end

-- The ReadyCheck presenter (tints and icon), or nil when not offered.
function UnitFrame:GetReadyCheck()
	return self.readyCheck
end

-- Neither range result may be tested in Lua: both can be secret in combat.
-- Native selection also restores full opacity when no range check was made.
function UnitFrame:ApplyRangeOpacity()
	local cfg = self.resolved.range
	local fade = cfg.enabled and ns.Caps.booleanAlpha
	if fade then
		self.frame:SetAlphaFromBoolean(self.rangeInRange, 1, cfg.outsideAlpha)
		self.frame:SetAlphaFromBoolean(self.rangeChecked, self.frame:GetAlpha(), 1)
	else
		self.frame:SetAlpha(1)
	end
	-- A 3D model ignores this inherited fade and repeats it on its own frame.
	local portrait = self.partsByKey.portrait
	if portrait then
		if fade then portrait:SetRangeFade(self.rangeInRange, self.rangeChecked, cfg.outsideAlpha)
		else portrait:SetRangeFade(nil) end
	end
end

function UnitFrame:SetRangeState(inRange, checkedRange)
	self.rangeInRange, self.rangeChecked = inRange, checkedRange
	self:ApplyRangeOpacity()
end

-- A companion layout can ask for a taller frame; the health row absorbs
-- the difference at the next Apply/Layout. nil restores the natural height.
function UnitFrame:SetFillHeight(height)
	self.fillHeight = height
end

function UnitFrame:Layout()
	ns.Perf:Count("unitLayout")
	ns.Perf:Begin("unit layout")
	local layout = ns.UnitFrameLayout.Compute(self.spec, self.resolved, self.fillHeight)
	local previous = self.layout
	self.layout = layout
	local placements = self.rowPlacements or {}
	self.rowPlacements = placements
	for _, row in ipairs(self.rows) do
		local key = row.def.key
		if not self.resolved[key].enabled and placements[key] then
			row.component:ClearAllPoints()
			placements[key] = nil
		end
	end
	local portrait = self.partsByKey.portrait
	if portrait then
		local bounds = layout.portrait
		if not previous or not ns.Util.Equals(previous.portrait, bounds) then
			portrait:ClearAllPoints()
			if bounds then
				portrait:SetSize(bounds.width, bounds.height)
				portrait:SetPoint("TOP" .. bounds.side, self.frame, "TOP" .. bounds.side, bounds.x, bounds.y)
			end
		end
	end

	local auraBar = self.partsByKey.auraBar
	if auraBar then auraBar:SetCollapse(layout.auraBarCollapses and self.resolved.spacing or nil) end
	for _, item in ipairs(layout.rows) do
		local component = self.partsByKey[item.key] or self.rowsByKey[item.key]
		if not self.rowsByKey[item.key] or not ns.Util.Equals(placements[item.key], item) then
			component:ClearAllPoints()
			component:SetPoint("TOPLEFT", self.frame, "TOPLEFT", item.left, item.y)
			component:SetPoint("TOPRIGHT", self.frame, "TOPRIGHT", -item.right, item.y)
			component:GetFrame():SetHeight(item.height)
			placements[item.key] = item
			ns.Perf:Count("rowLayoutWrite")
		end
		if item.key == "auraBar" or item.key == "comboPoints" then
			component:Layout(layout.width - item.left - item.right)
		end
	end
	if auraBar and auraBar.spec.collapsible then self:LayoutCollapse(layout) end
	self:LayoutCastbar(layout)

	self:Resize(layout.width, layout.height)
	local bounds = layout.portrait
	self.layoutContext = { root = self.frame, portrait = bounds and {
		frame = portrait:GetFrame(), width = bounds.width, height = bounds.height,
	} or nil, name = self:GetLeadingName(), decorations = self.decorations }
	self.decorations:SetContext(self.layoutContext)

	if self.partsByKey.auras then
		self.partsByKey.auras:Layout(layout.width, layout.height)
	end
	for _, part in ipairs(self.parts) do
		if part.def.stack then part.component:Layout(self.layoutContext) end
	end
	self.decorations:Reflow()
	Backdrop.SetBorderLevel(self.border, self.frame:GetFrameLevel() + Backdrop.LEVELS.frame)
	ns.Perf:End("unit layout")
end

-- A collapsible icon row lends its space to the health bar: the bar's edge
-- next to the row follows the row's native viewport, its texts with it. The
-- row frame (a covering castbar's host) keeps the configured health height.
function UnitFrame:LayoutCollapse(layout)
	local health, rowItem, barItem = self.rowsByKey.health
	for _, item in ipairs(layout.rows) do
		if item.key == "health" then rowItem = item elseif item.key == "auraBar" then barItem = item end
	end
	if rowItem then health:SetKnownSize(layout.width - rowItem.left - rowItem.right, rowItem.height) end
	if not layout.auraBarCollapses then
		health:ExtendBar(nil)
	elseif self.resolved.auraBar.position == "top" then
		health:ExtendBar("TOP", self.partsByKey.auraBar:GetViewport(), rowItem.left - barItem.left)
	else
		health:ExtendBar("BOTTOM", self.partsByKey.auraBar:GetViewport(), barItem.right - rowItem.right)
	end
end

-- Row placements are positioned with the rows. A covering castbar ("health",
-- "portrait") instead sits over its host, opaque, and replaces it while a
-- cast is shown. Portrait placement needs a visible portrait. Over a health
-- bar that lends its edge to a collapsing aura bar, the castbar follows the
-- bar's native edge so it grows and shrinks with it.
function UnitFrame:LayoutCastbar(layout)
	local castbar = self.partsByKey.castbar
	if not castbar then return end
	local placement = layout.castbarPlacement
	local portrait = layout.portrait and self.partsByKey.portrait
	local host, hostLevel, onCoverChanged, coverArea
	local width, height, maxHeight
	local rowKey = placement == "health" and "health" or "castbar"
	for _, item in ipairs(layout.rows) do
		if item.key == rowKey then
			width, height = layout.width - item.left - item.right, item.height
			break
		end
	end
	if placement == "health" then
		host = self.rowsByKey.health:GetFrame()
		hostLevel = host:GetFrameLevel()
		coverArea = layout.auraBarCollapses and self.rowsByKey.health:GetBar():GetFrame() or host
	elseif placement == "portrait" and portrait then
		width, height = layout.portrait.width, layout.portrait.height
		host = portrait:GetFrame()
		hostLevel = (portrait.model or portrait.viewport or host):GetFrameLevel()
		onCoverChanged = function(alpha) portrait:SetCoverAlpha(alpha) end
	end

	castbar:SetPortraitPlacement(placement == "portrait")
	castbar:SetEnabled(placement ~= "off" and (placement ~= "portrait" or portrait ~= nil))
	if host then
		castbar:ClearAllPoints()
		castbar:SetAllPoints(coverArea or host)
		-- Above category auras covering the portrait.
		castbar:GetFrame():SetFrameLevel(hostLevel + CategoryAuras.LEVELS + 6)
	else
		castbar:GetFrame():SetFrameLevel(self.frame:GetFrameLevel() + 1)
	end
	if coverArea and coverArea ~= host then
		maxHeight = height
		for _, item in ipairs(layout.rows) do
			if item.key == "auraBar" then maxHeight = maxHeight + self.resolved.spacing + item.height end
		end
	end
	castbar:SetKnownSize(width, height, maxHeight)
	castbar:SetOpaque(host ~= nil)
	castbar:SetCovered(host, onCoverChanged)
end

-- An enabled, left-aligned name text on the health row. Icons placed
-- "before the name" make room in it.
function UnitFrame:GetLeadingName()
	local row = self.rowsByKey.health
	if row and row:IsEnabled() then
		for _, text in row:EnabledTexts() do
			if text.resolved.justifyH == "LEFT" and text:LeadsWithName() then
				return text
			end
		end
	end
end

-- Whether the health bar and its texts can follow native (secret) geometry.
-- Frames a companion may anchor to them, such as icons placed before the
-- name, must then be created with DisableUntrustedLayoutScriptsTemplate.
function UnitFrame:IsNativeLayout()
	return self.nativeLayout == true
end

-- The edge icon stack; members join through DecorationStack:Set.
function UnitFrame:GetDecorations()
	return self.decorations
end

function UnitFrame:GetLayoutContext()
	return self.layoutContext
end

-- Unit buttons are protected: resizing them waits until combat ends.
function UnitFrame:Resize(width, height)
	if self.frame:IsProtected() and InCombatLockdown() then
		ns.AfterCombat:Queue("layout", self, UnitFrame.Layout)
		return
	end
	self.frame:SetSize(width, height)
end

function UnitFrame:OnRelease()
	self.border:SetScript("OnUpdate", nil)
	self.onReadyCheckChanged = nil
	if self.readyCheck then self.readyCheck:Release() end
	self.decorations:Release()
end

-- A row's TextBar, by key ("health", "power", ...).
function UnitFrame:GetRow(key)
	return self.rowsByKey[key]
end

-- Resolved row config (enabled, height, extra options, ...).
function UnitFrame:GetRowConfig(key)
	return self.resolved[key]
end

-- Iterates rows: for key, row, rowConfig in frame:Rows() do ... end
function UnitFrame:Rows()
	local i = 0
	return function()
		i = i + 1
		local row = self.rows[i]
		if row then
			return row.def.key, row.component, self.resolved[row.def.key]
		end
	end
end

-- Iterates present optional parts in declaration order:
-- for key, part, partConfig in frame:Parts() do ... end
function UnitFrame:Parts()
	local i = 0
	return function()
		i = i + 1
		local part = self.parts[i]
		if part then
			return part.def.key, part.component, self.resolved[part.def.key]
		end
	end
end

-- A present optional part's component ("portrait", "castbar", ...), else nil.
function UnitFrame:GetPart(key)
	return self.partsByKey[key]
end
