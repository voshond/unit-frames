local _, ns = ...

--[[
An icon in its unit frame's DecorationStack: the raid marker, PvP flag,
elite marker. Layout only: oUF drives the texture on live frames; previews
set sample art. Subclasses set `stackKey` (the member key in the stack) and
build their schema with StackIcon.BuildIconSchema.

  icon:Layout(context)   join the frame's stack (UnitFrame:Layout calls this)
  icon:Reflow()          after the art was shown or hidden
  icon:GetWidget()       the texture for oUF
]]
local StackIcon = ns.Component:Extend("StackIcon")

StackIcon.ANCHORS = ns.DecorationStack.ANCHORS

-- Shared placement options; `defaults` replaces the descriptor defaults
-- (enabled, anchor, order, gap, size).
function StackIcon.BuildIconSchema(defaults)
	local d = defaults or {}
	local function Default(key, fallback)
		if d[key] == nil then return fallback end
		return d[key]
	end
	return {
		{ key = "enabled", type = "toggle", label = "Enabled", default = Default("enabled", true) },
		{ key = "anchor", type = "select", label = "Anchor", values = StackIcon.ANCHORS, default = Default("anchor", "TOP"),
			tooltip = "Icons sharing a position line up as one group: edges and the centre keep the group centred, border corners grow inward from the corner. Portrait anchors keep it inside a bottom corner and require an enabled portrait." },
		{ key = "order", type = "range", label = "Order", min = 1, max = 10, step = 1, default = Default("order", 1),
			tooltip = "Icons sharing a position run left to right (top to bottom on the sides) by order. Absent icons leave no gap." },
		{ key = "gap", type = "range", label = "Gap to next icon", min = 0, max = 20, step = 1, default = Default("gap", 2) },
		{ key = "size", type = "range", label = "Size", min = 8, max = 64, step = 1, default = Default("size", 20),
			tooltip = "Portrait icons shrink to fit if the portrait is smaller than this size." },
		{ key = "offsetX", type = "range", label = "Horizontal offset", min = -100, max = 100, step = 1, default = 0,
			tooltip = "Positive moves right; negative moves left. Moves only this icon, not the rest of its group." },
		{ key = "offsetY", type = "range", label = "Vertical offset", min = -100, max = 100, step = 1, default = 0,
			tooltip = "Positive moves up; negative moves down. Moves only this icon, not the rest of its group." },
	}
end

function StackIcon:OnCreate(parent)
	self.frame = CreateFrame("Frame", nil, parent)
	self.texture = self.frame:CreateTexture(nil, "OVERLAY")
	self.texture:SetAllPoints(self.frame)
	self.texture:Hide()
	-- oUF calls this after showing or hiding the art, also in combat.
	self.texture.PostUpdate = function() self:Reflow() end
end

function StackIcon:OnApply(cfg)
	if self.layoutContext then
		self:Layout(self.layoutContext)
	else
		self:SetSize(cfg.size, cfg.size)
	end
end

-- Widgets whose visibility decides presence in the stack.
function StackIcon:GetStackWidgets()
	return { self.texture }
end

function StackIcon:SetEnabled(enabled)
	self.enabled = enabled and true or false
	local stack = self.layoutContext and self.layoutContext.decorations
	if not stack then
		self.frame:SetShown(self.enabled)
		return
	end
	local cfg = self.resolved
	stack:Set(self.stackKey, { host = self.frame, widgets = self:GetStackWidgets(), enabled = self.enabled,
		anchor = cfg.anchor, size = cfg.size, order = cfg.order, gap = cfg.gap, x = cfg.offsetX, y = cfg.offsetY })
	stack:Reflow()
end

-- Joins the frame's decoration stack. Keep this above portraits, bars and
-- the overlay castbar.
function StackIcon:Layout(context)
	self.layoutContext = context
	self.frame:SetFrameLevel(context.root:GetFrameLevel() + 20)
	self:SetEnabled(self.resolved.enabled)
end

function StackIcon:Reflow()
	local stack = self.layoutContext and self.layoutContext.decorations
	if stack and not self.released then stack:Reflow() end
end

function StackIcon:OnRelease()
	local stack = self.layoutContext and self.layoutContext.decorations
	if stack then stack:Remove(self.stackKey) end
end

function StackIcon:GetWidget()
	return self.texture
end
