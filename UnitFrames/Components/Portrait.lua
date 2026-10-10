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
	elseif mode == "2D" then
		SetPortraitTexture(self.texture, unit)
	else
		local _, class = UnitClass(unit)
		self.texture:SetAtlas("classicon-" .. class)
	end
end
