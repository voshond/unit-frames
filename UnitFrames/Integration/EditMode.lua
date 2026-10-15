local _, ns = ...

--[[
Edit Mode integration through LibEditMode: our frames can be selected and
dragged in Blizzard's Edit Mode. Positions are stored per Edit Mode layout,
so switching layouts (e.g. "Healer" / "DPS") moves our frames too.

The Edit Mode dialog of a frame has quick settings (width, rows on/off) and a
button that opens the full settings (the Workbench for now).
]]
local LEM = LibStub("LibEditMode", true)

local EditMode = { frames = {} }
ns.EditMode = EditMode

-- Moves a registered frame to its stored position for the current layout.
-- Unit buttons are protected, so this waits for combat to end.
function EditMode:ApplyPosition(key)
	local entry = self.frames[key]
	if InCombatLockdown() then
		ns.AfterCombat:Queue("position", key, function() EditMode:ApplyPosition(key) end)
		return
	end
	local pos = ns.Config:GetPosition(self.layout, key) or entry.default
	entry.frame:ClearAllPoints()
	entry.frame:SetPoint(pos.point, UIParent, pos.point, pos.x, pos.y)
end

-- Read-only geometry adapters let Blizzard choose the same grid, edge and
-- corner snaps as its own frames. Never register addon objects in Blizzard's
-- shared magneticFrames table or change a Blizzard frame's scripts/anchors.
local Geometry = {}
Geometry.__index = Geometry

local function PlainNumber(value)
	return not ns.Util.IsSecret(value) and type(value) == "number"
end

local function Rect(frame)
	if not frame:IsVisible() then return end
	local left, bottom, width, height = frame:GetRect()
	local scale, parentScale = frame:GetEffectiveScale(), UIParent:GetEffectiveScale()
	if not PlainNumber(left) or not PlainNumber(bottom) or not PlainNumber(width) or not PlainNumber(height)
		or not PlainNumber(scale) or not PlainNumber(parentScale)
		or width <= 0 or height <= 0 or scale <= 0 or parentScale <= 0 then return end
	local ratio = scale / parentScale
	return setmetatable({ left = left * ratio, right = (left + width) * ratio,
		bottom = bottom * ratio, top = (bottom + height) * ratio, scale = ratio }, Geometry)
end

function Geometry:GetScaledSelectionSides() return self.left, self.right, self.bottom, self.top end
function Geometry:GetScaledSelectionCenter() return (self.left + self.right) / 2, (self.bottom + self.top) / 2 end
function Geometry:HasValidSelectionRect() return true end
function Geometry:IsToTheLeftOfFrame(frame) return self.right < frame.left end
function Geometry:IsToTheRightOfFrame(frame) return self.left > frame.right end
function Geometry:IsAboveFrame(frame) return self.bottom > frame.top end
function Geometry:IsBelowFrame(frame) return self.top < frame.bottom end
function Geometry:IsVerticallyAlignedWithFrame(frame) return self.top >= frame.bottom and self.bottom <= frame.top end
function Geometry:IsHorizontallyAlignedWithFrame(frame) return self.right >= frame.left and self.left <= frame.right end
function Geometry:GetFrameMagneticEligibility(frame)
	if frame == self then return end
	return self:IsVerticallyAlignedWithFrame(frame) and (self:IsToTheLeftOfFrame(frame) or self:IsToTheRightOfFrame(frame)),
		self:IsHorizontallyAlignedWithFrame(frame) and (self:IsAboveFrame(frame) or self:IsBelowFrame(frame))
end

function Geometry:Point(point)
	local x, y = self:GetScaledSelectionCenter()
	if point:find("LEFT", 1, true) then x = self.left
	elseif point:find("RIGHT", 1, true) then x = self.right end
	if point:find("BOTTOM", 1, true) then y = self.bottom
	elseif point:find("TOP", 1, true) then y = self.top end
	return x, y
end

local function CanSnap()
	return not InCombatLockdown() and LEM and LEM:IsInEditMode()
		and EditModeManagerFrame and EditModeManagerFrame:IsSnapEnabled()
		and EditModeMagnetismManager and EditModeMagnetismManager.GetMagneticFrameInfos
end

-- Offsets are in UIParent coordinates, independent of the dragged frame's
-- scale. Use a private view of the native manager to add our candidates.
function EditMode:GetSnap(key)
	if not CanSnap() then return end
	local entry = self.frames[key]
	local source, parent = entry and Rect(entry.frame), Rect(UIParent)
	if not source or not parent then return end
	local manager = EditModeMagnetismManager
	local view = setmetatable({ magneticFrames = {},
		topLevelParentLeft = parent.left, topLevelParentRight = parent.right,
		topLevelParentBottom = parent.bottom, topLevelParentTop = parent.top,
		topLevelParentWidth = parent.right - parent.left, topLevelParentHeight = parent.top - parent.bottom,
	}, { __index = manager })
	view.topLevelParentCenterX, view.topLevelParentCenterY = parent:GetScaledSelectionCenter()
	for frame in pairs(manager.magneticFrames or {}) do
		-- Blizzard uses its highlighted selection bounds for magnetism.
		local geometry = Rect(frame.Selection or frame)
		if geometry then view.magneticFrames[geometry] = true end
	end
	for otherKey, other in pairs(self.frames) do
		if otherKey ~= key then
			local geometry = Rect(other.frame)
			if geometry then view.magneticFrames[geometry] = true end
		end
	end
	local infos = view:GetMagneticFrameInfos(source)
	if not infos then return end
	local dx, dy, guides = 0, 0, {}
	for _, info in ipairs(infos) do
		local target = info.frame == UIParent and parent or info.frame
		local x, y = target:Point(info.relativePoint)
		local sourceX, sourceY = source:Point(info.point)
		if info.isHorizontal or info.isCornerSnap then
			x = x + info.offset
			dx = x - sourceX
			guides[#guides + 1] = { vertical = true, position = x }
		end
		if not info.isHorizontal or info.isCornerSnap then
			y = y + info.offset
			dy = y - sourceY
			guides[#guides + 1] = { vertical = false, position = y }
		end
	end
	return { source = source, parent = parent, dx = dx, dy = dy, guides = guides }
end

function EditMode:SnapFrame(key)
	local snap = self:GetSnap(key)
	if not snap then return false end
	local x, y = snap.source:GetScaledSelectionCenter()
	local parentX, parentY = snap.parent:GetScaledSelectionCenter()
	x, y = (x + snap.dx - parentX) / snap.source.scale, (y + snap.dy - parentY) / snap.source.scale
	local frame = self.frames[key].frame
	frame:ClearAllPoints()
	frame:SetPoint("CENTER", UIParent, "CENTER", x, y)
	ns.Config:SetPosition(LEM:GetActiveLayoutName(), key, "CENTER", x, y)
	if LEM.RefreshFrameSettings then LEM:RefreshFrameSettings(frame) end
	return true
end

function EditMode:HideSnapGuides()
	if self.snapGuides then self.snapGuides:Hide() end
end

function EditMode:ShowSnapGuides(key)
	local snap = self:GetSnap(key)
	if not snap then self:HideSnapGuides(); return end
	if not self.snapGuides then
		self.snapGuides = CreateFrame("Frame", nil, UIParent)
		self.snapGuides:SetAllPoints(UIParent)
		self.snapGuides:SetFrameStrata("TOOLTIP")
		self.snapGuides:EnableMouse(false)
		self.snapGuideLines = {}
	end
	for _, line in ipairs(self.snapGuideLines) do line:Hide() end
	for i, guide in ipairs(snap.guides) do
		local line = self.snapGuideLines[i]
		if not line then
			line = self.snapGuides:CreateLine(nil, "OVERLAY")
			line:SetColorTexture(1, 0, 0, 0.8)
			line:SetThickness(1.5)
			self.snapGuideLines[i] = line
		end
		local x = guide.vertical and guide.position - snap.parent.left or 0
		local y = guide.vertical and 0 or guide.position - snap.parent.bottom
		line:SetStartPoint("BOTTOMLEFT", UIParent, x, y)
		line:SetEndPoint(guide.vertical and "TOPLEFT" or "BOTTOMRIGHT", UIParent, x, y)
		line:Show()
	end
	self.snapGuides:Show()
end

function EditMode:HookSnapping(frame, key)
	local selection = LEM.frameSelections and LEM.frameSelections[frame]
	if not selection then return end
	local dragging, elapsed = false, 0
	selection:HookScript("OnDragStart", function()
		if InCombatLockdown() then return end
		dragging, elapsed = true, 0
		self:ShowSnapGuides(key)
	end)
	selection:HookScript("OnUpdate", function(_, delta)
		if not dragging then return end
		elapsed = elapsed + delta
		if elapsed >= 0.05 then elapsed = 0; self:ShowSnapGuides(key) end
	end)
	selection:HookScript("OnDragStop", function()
		local wasDragging = dragging
		dragging = false
		self:HideSnapGuides()
		-- The library has stopped moving and saved the unsnapped location.
		-- Save again after snapping, with no live anchor to another frame.
		if wasDragging then self:SnapFrame(key) end
	end)
	selection:HookScript("OnHide", function()
		if dragging then dragging = false; self:HideSnapGuides() end
	end)
	selection:HookScript("OnEvent", function(_, event)
		if event == "PLAYER_REGEN_DISABLED" then dragging = false; self:HideSnapGuides() end
	end)
end

-- Optional parts offered in the quick settings: { part key, option path, name }.
local PART_SETTINGS = {
	{ "portrait", "portrait.enabled", "Show portrait" },
	{ "auras", "auras.enabled", "Show buffs & debuffs" },
	{ "castbar", "castbar.placement", "Castbar" },
}

-- A quick setting built from the unit's schema descriptor at `path`. Its value
-- lives in the unit config; setting it back to the default removes the change.
local function UnitSetting(unit, path, name)
	local schema = ns.Units:GetSchema(unit)
	local opt = ns.Schema.Find(schema, path)
	local setting = { name = name, default = ns.Util.GetPath(ns.Schema.Defaults(schema), path) }
	if opt.type == "range" then
		setting.kind, setting.minValue, setting.maxValue, setting.valueStep = LEM.SettingType.Slider, opt.min, opt.max, opt.step
	elseif opt.type == "toggle" then
		setting.kind = LEM.SettingType.Checkbox
	else
		setting.kind, setting.values = LEM.SettingType.Dropdown, {}
		for _, entry in ipairs(ns.Schema.GetValues(opt)) do
			setting.values[#setting.values + 1] = { value = entry[1], text = entry[2] }
		end
	end
	setting.get = function()
		return ns.Util.GetPath(ns.Units.frames[unit].uf.resolved, path)
	end
	setting.set = function(_, value)
		if value == setting.default then
			value = nil
		end
		ns.Config:SetUnitValue(unit, path, value)
	end
	return setting
end

local function UnitSettings(unit)
	local def = ns.Units.definitions[unit]
	local settings = { UnitSetting(unit, "width", "Width") }
	for _, row in ipairs(def.rows) do
		settings[#settings + 1] = UnitSetting(unit, row.key .. ".enabled", "Show " .. row.label:lower())
	end
	for _, entry in ipairs(PART_SETTINGS) do
		if def[entry[1]] then settings[#settings + 1] = UnitSetting(unit, entry[2], entry[3]) end
	end
	return settings
end

-- key: config key for the position ("player"), name: label in Edit Mode.
function EditMode:Register(frame, key, name, default, entryId)
	self.frames[key] = { frame = frame, default = default }
	self:ApplyPosition(key)
	if not LEM then
		return
	end
	LEM:AddFrame(frame, function(_, layout, point, x, y)
		ns.Config:SetPosition(layout, key, point, x, y)
	end, default, name)
	self:HookSnapping(frame, key)
	if ns.Units.definitions[key] then
		LEM:AddFrameSettings(frame, UnitSettings(key))
	end
	LEM:AddFrameSettingsButtons(frame, {
		{ text = "More settings", click = function()
			ns:OpenWorkbench(entryId or "unit." .. key)
		end },
	})
end

function EditMode:ApplyPositions()
	for key in pairs(self.frames) do
		self:ApplyPosition(key)
	end
end

-- Positions are stored in the profile.
ns.Events.RegisterCallback(EditMode, "ProfileChanged", function() EditMode:ApplyPositions() end)

if LEM then
	LEM:RegisterCallback("exit", function() EditMode:HideSnapGuides() end)
	LEM:RegisterCallback("layout", function(layout)
		EditMode.layout = layout
		EditMode:ApplyPositions()
	end)
end
