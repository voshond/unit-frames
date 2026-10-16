local _, ns = ...
local AuraIcon, Backdrop = ns.AuraIcon, ns.Components.Backdrop

--[[
The unit's crowd control and big/external defensive auras: one native aura
slot per category, all at the same place. Whether a slot shows an aura is
secret, so priority comes from frame levels alone: a higher category's
opaque icon covers the ones below it. The icons cover the portrait or join
the frame's DecorationStack without taking a place in its groups: they sit
alone on their anchor and overlap neighbouring icons while shown.
]]
local CategoryAuras = ns.Component:Extend("CategoryAuras")
CategoryAuras.stackKey = "categoryAuras"

-- Highest priority first.
CategoryAuras.CATEGORIES = {
	{ key = "crowdControl", label = "Crowd control", filter = "HARMFUL|CROWD_CONTROL", color = { 1, 0.25, 0.25, 1 } },
	{ key = "bigDefensive", label = "Big defensives", filter = "HELPFUL|BIG_DEFENSIVE", color = { 1, 0.82, 0, 1 } },
	{ key = "externalDefensive", label = "External defensives", filter = "HELPFUL|EXTERNAL_DEFENSIVE", color = { 0.3, 0.75, 1, 1 } },
	{ key = "important", label = "Important buffs", filter = "HELPFUL|IMPORTANT", color = { 0.75, 0.45, 1, 1 }, enabled = false },
}

-- Frame levels per slot: an aura button and its artwork frames fit in one band.
local LEVEL_BAND = 6
CategoryAuras.LEVELS = #CategoryAuras.CATEGORIES * LEVEL_BAND + 1

local PRIORITY = {}
for index, category in ipairs(CategoryAuras.CATEGORIES) do PRIORITY[category.key] = index end

local ANCHORS = { { "PORTRAIT", "Cover the portrait" } }
for _, anchor in ipairs(ns.DecorationStack.ANCHORS) do ANCHORS[#ANCHORS + 1] = ns.Util.Copy(anchor) end

local function Covering(cfg) return cfg.anchor == "PORTRAIT" end

local categories = {}
for _, category in ipairs(CategoryAuras.CATEGORIES) do
	categories[#categories + 1] = { key = category.key, type = "toggle", label = category.label,
		default = category.enabled ~= false }
end
categories[#categories + 1] = { key = "categoryBorder", type = "toggle", label = "Colour border by category", default = true,
	tooltip = "Tint the icon frame with the category's colour. Disable to use Icon frame > Border colour." }
for _, category in ipairs(CategoryAuras.CATEGORIES) do
	categories[#categories + 1] = { key = category.key .. "Color", type = "color", label = category.label .. " colour",
		default = category.color, hidden = function(cfg) return not cfg.categoryBorder or not cfg[category.key] end }
end

local art = ns.Schema.Without(ns.Util.Copy(AuraIcon.schema), { dispelBorder = true, dispelColors = true })
local insidePositions = {}
for _, position in ipairs(AuraIcon.DURATION_POSITIONS) do
	if position[1] ~= "below" then insidePositions[#insidePositions + 1] = ns.Util.Copy(position) end
end
art = ns.Schema.Override(art, "durationPosition", { values = insidePositions, default = "CENTER",
	tooltip = "Inside the icon: a lower category's text must not show past a covering icon." })

CategoryAuras.schema = ns.Schema.Concat(
	ns.IconPlacement.BuildSchema({
		defaults = { anchor = "PORTRAIT", size = 22 },
		fields = {
			anchor = { label = "Position", values = ANCHORS,
				tooltip = "Cover the portrait fills its shorter side, above the portrait and below a castbar covering it. Other positions sit on the anchor without moving other icons there, and cover them while shown." },
			size = { hidden = Covering }, order = { hidden = Covering }, gap = { hidden = Covering },
			offsetX = { hidden = Covering }, offsetY = { hidden = Covering },
		},
	}),
	categories,
	{
		{ key = "swipe", type = "select", label = "Cooldown swipe", default = "normal", values = {
			{ "normal", "Progressing" }, { "reverse", "Decreasing" }, { "none", "None" },
		} },
		{ key = "showSwipeEdge", type = "toggle", label = "Show swipe edge", default = true },
	},
	art)

function CategoryAuras:OnCreate(parent, spec)
	self.root = parent
	self.frame = CreateFrame("Frame", nil, parent)
	self.buttons = {}
end

-- The native container is built when the part is first enabled, outside
-- combat. It is parented to the root so stack reflows never re-level it.
function CategoryAuras:CreateContainer()
	if self.container then return end
	if InCombatLockdown() then
		ns.AfterCombat:Queue("create", self, function() self:SetEnabled(self.enabled) end)
		return
	end
	self.container = CreateFrame("AuraContainer", nil, self.root, "CustomAuraContainerTemplate")
	for _, category in ipairs(CategoryAuras.CATEGORIES) do
		self.buttons[category.key] = self.container:AddAuraSlot(category.key, category.filter, {
			sortMethod = AuraContainerSortMethod.Default,
			sortDirection = AuraContainerSortDirection.Normal,
			initializeFrame = function(button) self:InitButton(button, category.key) end,
		})
	end
	self:ApplySlots()
	if self.unit then self.container:SetUnit(self.unit) end
end

function CategoryAuras:InitButton(button, key, preview)
	AuraIcon.Create(button, key, preview, { clickThrough = true })
	if self.spec.noMouse then
		button:SetMouseClickEnabled(false)
		button:SetMouseMotionEnabled(false)
	end
end

function CategoryAuras:ApplySlots()
	for _, category in ipairs(CategoryAuras.CATEGORIES) do
		self.container:SetAuraSlotEnabled(category.key, self.resolved[category.key])
	end
end

function CategoryAuras:OnApply(cfg)
	self.art = {}
	for _, category in ipairs(CategoryAuras.CATEGORIES) do
		local copy = ns.Util.Copy(cfg)
		if cfg.categoryBorder then copy.border.color = cfg[category.key .. "Color"] end
		self.art[category.key] = copy
	end
	if self.container then self:ApplySlots() end
	self.styled = nil
end

-- Icon size and base frame level here, or nil where the icons cannot show.
function CategoryAuras:Geometry()
	local cfg, context = self.resolved, self.layoutContext
	local portrait = context and context.portrait
	if cfg.anchor == "PORTRAIT" or cfg.anchor:match("^PORTRAIT_") then
		if not portrait then return nil end
		if cfg.anchor == "PORTRAIT" then
			return math.min(portrait.width, portrait.height), portrait.frame:GetFrameLevel() + 2, portrait.frame
		end
		return math.min(cfg.size, portrait.width, portrait.height), self.root:GetFrameLevel() + Backdrop.LEVELS.decorations, self.frame
	end
	return cfg.size, self.root:GetFrameLevel() + Backdrop.LEVELS.decorations, self.frame
end

function CategoryAuras:JoinStack()
	local stack = self.layoutContext and self.layoutContext.decorations
	if not stack then return end
	local cfg = ns.IconPlacement.Read(self.resolved)
	cfg.enabled = self.enabled and not Covering(self.resolved)
	stack:Set(self.stackKey, ns.IconPlacement.Member(cfg, self.frame, nil, function() return false end))
	stack:Reflow()
end

function CategoryAuras:SetEnabled(enabled)
	self.enabled = enabled and true or false
	if self.enabled then self:CreateContainer() end
	self:JoinStack()
	local size, level, anchor = self:Geometry()
	local shown = self.enabled and size ~= nil
	self.size, self.level, self.anchor = size, level, anchor
	if self.container then
		self.container:SetShown(shown and not self.previewData)
		self.container:SetEnabled(shown and not self.previewData)
	end
	if self.previewFrame then self.previewFrame:SetShown(shown and self.previewData ~= nil) end
	if shown then self:RestyleButtons() end
end

function CategoryAuras:Layout(context)
	self.layoutContext = context
	self:SetEnabled(self.resolved.enabled)
end

function CategoryAuras:StyleButton(button)
	local cfg = self.resolved
	AuraIcon.Apply(button, self.art[button.ufKind], self.size, nil, cfg.swipe, cfg.showSwipeEdge)
	button:ClearAllPoints()
	button:SetPoint("CENTER", self.anchor, "CENTER", 0, 0)
	button:SetFrameLevel(self.level + 1 + (#CategoryAuras.CATEGORIES - PRIORITY[button.ufKind]) * LEVEL_BAND)
end

-- Access to native slot buttons may be denied while aura data is secret:
-- restyle them at the next combat end then, like Auras:RestyleButtons.
local function Restyle(icons)
	for _, button in pairs(icons.buttons) do icons:StyleButton(button) end
end

function CategoryAuras:RestyleButtons()
	local style, styled = { self.resolved, self.size, self.level, self.anchor, self.previewData ~= nil }, self.styled
	if styled and styled[1] == style[1] and styled[2] == style[2] and styled[3] == style[3]
		and styled[4] == style[4] and styled[5] == style[5] then return end
	if self.previewData then
		self.previewFrame:SetFrameLevel(self.level)
		for _, button in pairs(self.samples) do self:StyleButton(button) end
		self.styled = style
		return
	end
	if not self.container then return end
	if InCombatLockdown() then
		ns.AfterCombat:Queue("restyle", self, CategoryAuras.RestyleButtons)
		return
	end
	self.container:SetFrameLevel(self.level)
	local ok, reason = pcall(Restyle, self)
	if not ok then
		if not ns.AfterCombat:IsQueued(self, "restyle") then ns.Logs:Error("Category auras restyle deferred", reason) end
		ns.AfterCombat:Queue("restyle", self, CategoryAuras.RestyleButtons)
	else
		self.styled = style
		ns.AfterCombat:Cancel(self, "restyle")
	end
end

function CategoryAuras:SetUnit(unit)
	if self.previewData then
		self.previewData = nil
		self.styled = nil
		self:SetEnabled(self.enabled)
	end
	self.unit = unit
	if not self.container then return end
	if self.container:GetUnit() ~= unit then
		self.container:SetUnit(unit)
	else
		self.container:UpdateAllAuras()
	end
end

-- values.categoryAuras: { [category key] = sample aura } for the shown ones.
function CategoryAuras:ShowSample(values)
	if not self.previewFrame then
		self.previewFrame = CreateFrame("Frame", nil, self.root)
		self.previewFrame:SetAllPoints(self.root)
		self.samples = {}
		for _, category in ipairs(CategoryAuras.CATEGORIES) do
			local button = CreateFrame("Button", nil, self.previewFrame)
			self:InitButton(button, category.key, true)
			self.samples[category.key] = button
		end
	end
	self.previewData = values
	self.styled = nil
	ns.AfterCombat:Cancel(self, "restyle")
	local active = values.categoryAuras or {}
	for key, button in pairs(self.samples) do
		local aura = self.resolved[key] and active[key] or nil
		if aura then AuraIcon.DrawSample(button, aura) end
		button:SetShown(aura ~= nil)
	end
	self:SetEnabled(self.enabled)
end

function CategoryAuras:OnRelease()
	self.previewData = nil
	self:SetEnabled(false)
	local stack = self.layoutContext and self.layoutContext.decorations
	if stack then stack:Remove(self.stackKey) end
end
