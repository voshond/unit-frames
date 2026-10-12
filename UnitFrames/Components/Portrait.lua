local _, ns = ...
local Util = ns.Util
local Backdrop = ns.Components.Backdrop

--[[
Unit portrait: 3D model, 2D portrait or class icon, on an optional
background/border. Live frames hand GetWidget() to oUF's Portrait element;
previews call SetUnit().
]]
local Portrait = ns.Component:Extend("Portrait")

Portrait.MODES = {
	{ "3D", "3D model" },
	{ "2D", "2D portrait" },
	{ "class", "Class icon" },
}

Portrait.schema = {
	{ key = "enabled", type = "toggle", label = "Enabled", default = true },
	{ key = "mode", type = "select", label = "Style", values = Portrait.MODES, default = "3D" },
	{ key = "background", type = "color", label = "Background", default = { 0, 0, 0, 0.6 } },
	{ key = "border", type = "group", label = "Border", schema = Backdrop.schema, defaults = { enabled = false } },
}

function Portrait:OnCreate(parent)
	self.frame = CreateFrame("Frame", nil, parent, "BackdropTemplate")
	self.background = self.frame:CreateTexture(nil, "BACKGROUND")
	self.model = CreateFrame("PlayerModel", nil, self.frame)
	-- oUF can replace the model on unit/visibility changes; restore its material
	-- opacity after that update as well as when our host opacity changes.
	self.model.PostUpdate = function() self:SyncAlpha() end
	self.texture = self.frame:CreateTexture(nil, "ARTWORK")
end

function Portrait:OnApply(cfg)
	Backdrop.ApplyTo(self.frame, cfg.border)
	Backdrop.Inset(self.background, self.frame, cfg.border)
	Backdrop.Inset(self.model, self.frame, cfg.border)
	Backdrop.Inset(self.texture, self.frame, cfg.border)
	self.background:SetColorTexture(Util.UnpackColor(cfg.background))

	local is3D = cfg.mode == "3D"
	self.model:SetShown(is3D)
	self.texture:SetShown(not is3D)
	if cfg.mode == "2D" then
		self.texture:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	else
		self.texture:SetTexCoord(0, 1, 0, 1)
	end
	-- oUF's Portrait element shows the class icon on textures with showClass.
	self.texture.showClass = cfg.mode == "class"
	self:SyncAlpha()
end

-- A covering castbar's plain alpha for this portrait (1 = uncovered).
function Portrait:SetCoverAlpha(alpha)
	self.coverAlpha = alpha
	self:SyncAlpha()
end

-- The owner's range fade: the native range results (possibly secret) and the
-- out-of-range alpha, or nil without a fade.
function Portrait:SetRangeFade(inRange, checkedRange, outsideAlpha)
	self.rangeFade = inRange ~= nil and { inRange, checkedRange, outsideAlpha } or nil
	self:SyncAlpha()
end

--[[
PlayerModel artwork ignores the alpha it inherits, so it is faded directly,
without reading any alpha back (below a secret range fade the client returns
no effective alpha and secret alphas, which SetModelAlpha refuses):
  material alpha  castbar coverage, a plain number (SetModelAlpha)
  frame alpha     the range fade, selected natively from the range results
                  exactly like the unit frame's own fade (SetAlphaFromBoolean)
]]
function Portrait:SyncAlpha()
	if self.released or not self.resolved or self.resolved.mode ~= "3D" then
		return
	end
	local model, fade = self.model, self.rangeFade
	model:SetModelAlpha(self.coverAlpha or 1)
	if fade then
		model:SetAlphaFromBoolean(fade[1], 1, fade[3])
		model:SetAlphaFromBoolean(fade[2], model:GetAlpha(), 1)
	else
		model:SetAlpha(1)
	end
end

function Portrait:OnRelease()
	self.model.PostUpdate = nil
end

-- The region oUF's Portrait element should drive for the current mode.
function Portrait:GetWidget()
	return self.resolved.mode == "3D" and self.model or self.texture
end

-- Preview: show `unit` without oUF. Repeated calls with the same unit and
-- style do nothing (re-setting a model restarts its animation).
function Portrait:SetUnit(unit)
	local mode = self.resolved.mode
	if self.shownUnit == unit and self.shownMode == mode then
		return
	end
	self.shownUnit, self.shownMode = unit, mode
	if mode == "3D" then
		self.model:ClearModel()
		self.model:SetUnit(unit)
		self.model:SetPortraitZoom(1)
		self:SyncAlpha()
	elseif mode == "2D" then
		SetPortraitTexture(self.texture, unit)
	else
		local _, class = UnitClass(unit)
		self.texture:SetAtlas("classicon-" .. class)
	end
end
