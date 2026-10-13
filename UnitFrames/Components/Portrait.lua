local _, ns = ...
local Util = ns.Util
local Backdrop = ns.Components.Backdrop

--[[
Unit portrait: 3D model, 2D portrait or class icon, on an optional
background/border. Live frames hand GetWidget() to oUF's Portrait element;
previews call SetUnit().

2D and class artwork keep their proportions: the texture is scaled uniformly
to cover a clipping viewport inside the border and centred, so a wide or tall
portrait crops the artwork instead of stretching it. Geometry uses only the
owner's known size and static asset metadata, never native dimensions.
]]
local Portrait = ns.Component:Extend("Portrait")

-- SetPortraitTexture artwork is square; this symmetric crop keeps it square.
local PORTRAIT_CROP = { 0.08, 0.92, 0.08, 0.92 }
-- Class icons share one atlas layout; any class serves as static reference.
local CLASS_REFERENCE_ATLAS = "classicon-warrior"

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

-- Size drawing a sourceWidth x sourceHeight image at uniform scale so it
-- covers a viewWidth x viewHeight viewport (the excess is clipped). Plain
-- layout numbers only; nil when either side has no usable size.
function Portrait.CoverSize(viewWidth, viewHeight, sourceWidth, sourceHeight)
	if viewWidth <= 0 or viewHeight <= 0 or sourceWidth <= 0 or sourceHeight <= 0 then
		return nil
	end
	local scale = math.max(viewWidth / sourceWidth, viewHeight / sourceHeight)
	return sourceWidth * scale, sourceHeight * scale
end

-- Width/height of the class icon artwork, from static atlas metadata.
local classAspect
local function ClassIconAspect()
	if not classAspect then
		local info = C_Texture.GetAtlasInfo(CLASS_REFERENCE_ATLAS)
		if info and info.width > 0 and info.height > 0 then
			classAspect = info.width / info.height
		else
			classAspect = 1
		end
	end
	return classAspect
end

function Portrait:OnCreate(parent, spec)
	self.frame = CreateFrame("Frame", nil, parent, "BackdropTemplate")
	self.background = self.frame:CreateTexture(nil, "BACKGROUND")
	-- Deferred compositions can prepare selected artwork at style time.
	-- Other callers keep both backends available for combat style changes.
	if not spec.lazyBackends then self:Prepare("3D"); self:Prepare("2D") end
end

-- Called during style preparation, never from live data/getters. Backends
-- remain owned once created, so mode and enable toggles reuse native objects.
function Portrait:Prepare(mode)
	if mode == "3D" then
		if self.model then return end
		self.model = CreateFrame("PlayerModel", nil, self.frame)
		-- oUF can replace the model on unit/visibility changes; restore its material
		-- opacity after that update as well as when our host opacity changes.
		self.model.PostUpdate = function() self:SyncAlpha() end
	else
		if self.texture then return end
		-- 2D/class artwork clips to this viewport, not the root, so borders,
		-- indicators and cast overlays anchored to the root keep their geometry.
		self.viewport = CreateFrame("Frame", nil, self.frame)
		self.viewport:SetClipsChildren(true)
		self.texture = self.viewport:CreateTexture(nil, "ARTWORK")
		self.texture:SetPoint("CENTER", self.viewport, "CENTER")
		-- oUF replaces the artwork (SetPortraitTexture/SetAtlas) on unit updates.
		self.texture.PostUpdate = function() self:PresentArtwork() end
	end
end

function Portrait:OnApply(cfg)
	Backdrop.ApplyTo(self.frame, cfg.border)
	Backdrop.Inset(self.background, self.frame, cfg.border)
	self.background:SetColorTexture(Util.UnpackColor(cfg.background))
	if cfg.enabled then self:Prepare(cfg.mode) end
	if self.model then Backdrop.Inset(self.model, self.frame, cfg.border) end
	if self.viewport then Backdrop.Inset(self.viewport, self.frame, cfg.border) end

	local is3D = cfg.mode == "3D"
	if self.model then self.model:SetShown(is3D) end
	if self.texture then self.texture:SetShown(not is3D) end
	if not self.texture then self:SyncAlpha(); return end
	-- oUF's Portrait element shows the class icon on textures with showClass.
	self.texture.showClass = cfg.mode == "class"
	-- Leaving 2D drops its crop once; the next artwork (atlas) brings its own
	-- coordinates. Never touch the UVs of an atlas already shown.
	if self.artworkMode ~= cfg.mode then
		if cfg.mode ~= "2D" then self.texture:SetTexCoord(0, 1, 0, 1) end
		self.artworkMode = cfg.mode
	end
	self:PresentArtwork()
	self:SyncAlpha()
end

-- Known outer size from the owner's layout; artwork geometry follows it.
function Portrait:SetSize(width, height)
	ns.Component.SetSize(self, width, height)
	self.width, self.height = width, height
	self:LayoutArtwork()
end

-- Restores the mode's base UVs after the artwork changed, then sizes it. An
-- atlas carries its own coordinates; only the 2D portrait gets the crop.
function Portrait:PresentArtwork()
	if self.released or not self.resolved then
		return
	end
	if self.resolved.mode == "2D" then
		self.texture:SetTexCoord(unpack(PORTRAIT_CROP))
	end
	self:LayoutArtwork()
end

function Portrait:LayoutArtwork()
	local cfg = self.resolved
	if self.released or not cfg or cfg.mode == "3D" or not self.texture then
		if self.viewport then self.viewport:SetShown(false) end
		return
	end
	local border = cfg.border
	local pad = border.enabled and border.padding or 0
	local width, height
	if self.width then
		width, height = Portrait.CoverSize(self.width - 2 * pad, self.height - 2 * pad,
			cfg.mode == "class" and ClassIconAspect() or 1, 1)
	end
	-- No usable interior yet: hide the artwork rather than divide by zero.
	self.viewport:SetShown(width ~= nil)
	if width then
		self.texture:SetSize(width, height)
	end
end

-- A covering castbar's plain alpha for this portrait (1 = uncovered).
function Portrait:SetCoverAlpha(alpha)
	self.coverAlpha = alpha
	self:SyncAlpha()
end

-- The owner's range fade: the native range results (possibly secret) and the
-- out-of-range alpha, or nil without a fade.
function Portrait:SetRangeFade(inRange, checkedRange, outsideAlpha)
	self.hasRangeFade = inRange ~= nil
	self.rangeInRange, self.rangeChecked, self.rangeOutsideAlpha = inRange, checkedRange, outsideAlpha
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
	if self.released or not self.resolved or self.resolved.mode ~= "3D" or not self.model then
		return
	end
	local model = self.model
	model:SetModelAlpha(self.coverAlpha or 1)
	if self.hasRangeFade then
		model:SetAlphaFromBoolean(self.rangeInRange, 1, self.rangeOutsideAlpha)
		model:SetAlphaFromBoolean(self.rangeChecked, model:GetAlpha(), 1)
	else
		model:SetAlpha(1)
	end
end

function Portrait:OnRelease()
	if self.model then self.model.PostUpdate = nil end
	if self.texture then self.texture.PostUpdate = nil end
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
		self:PresentArtwork()
	else
		local _, class = UnitClass(unit)
		self.texture:SetAtlas("classicon-" .. class)
		self:PresentArtwork()
	end
end
