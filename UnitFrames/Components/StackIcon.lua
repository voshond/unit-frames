local _, ns = ...

--[[
An icon in its unit frame's DecorationStack: the raid marker, PvP flag,
elite marker. Layout only: oUF drives the texture on live frames; previews
set sample art. Subclasses set `stackKey` (the member key in the stack) and
build their schema with StackIcon.BuildIconSchema.

  icon:Layout(context)   join the frame's stack (UnitFrame:Layout calls this)
  icon:Reflow()          after the art was shown or hidden
  icon:GetWidget()       the texture for oUF

spec.nativeLayout: the frame's texts follow native geometry, so the icon is
created with the forbidden layout aspect to be able to sit before the name.
]]
local StackIcon = ns.Component:Extend("StackIcon")

StackIcon.ANCHORS = ns.DecorationStack.ANCHORS

-- Shared placement options; `defaults` replaces the descriptor defaults
-- (enabled, anchor, order, gap, size).
function StackIcon.BuildIconSchema(defaults)
	return ns.IconPlacement.BuildSchema({ defaults = defaults })
end

function StackIcon:OnCreate(parent, spec)
	self.frame = CreateFrame("Frame", nil, parent, spec.nativeLayout and "DisableUntrustedLayoutScriptsTemplate" or nil)
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
	local cfg = ns.IconPlacement.Read(self.resolved)
	cfg.enabled = self.enabled
	stack:Set(self.stackKey, ns.IconPlacement.Member(cfg, self.frame, self:GetStackWidgets()))
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
