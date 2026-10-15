local _, wb = ...
local UF = UnitFrames
local Workbench, W, Skin = wb.Workbench, UF.Widgets, UF.Skin

-- Window, stage and toolbar presentation. Session lifetime stays in the controller.
local STAGE_BACKGROUNDS = {
	{ "dark", "Dark" },
	{ "grey", "Grey" },
	{ "light", "Light" },
}
local STAGE_COLORS = {
	dark = { 0.02, 0.02, 0.03, 1 },
	grey = { 0.25, 0.25, 0.27, 1 },
	light = { 0.8, 0.8, 0.8, 1 },
}

function Workbench:Build()
	local db = self:GetDB()
	self.window = W.Window:New(UIParent, {
		name = "UnitFramesWorkbench",
		title = "UnitFrames Workbench - " .. UF.version,
		width = 1240, height = 700, minWidth = 1060, minHeight = 500,
		db = db.window,
		onHide = function()
			self:SetForcedRestrictions(false)
		end,
	})
	local content = self.window:GetContent()

	-- 1: entries.
	self.list = W.ScrollList:New(content, {
		rowHeight = 20,
		onSelect = function(item)
			self:Select(item.id)
		end,
	})
	self.list:SetPoint("TOPLEFT")
	self.list:SetPoint("BOTTOMLEFT")
	self.list:SetWidth(150)

	-- 2: sections of the selected entry.
	self.sectionList = W.ScrollList:New(content, {
		rowHeight = 20,
		onSelect = function(item)
			self:SelectSection(item.id)
		end,
	})
	self.sectionList:SetPoint("TOPLEFT", self.list:GetFrame(), "TOPRIGHT", 8, 0)
	self.sectionList:SetPoint("BOTTOMLEFT", self.list:GetFrame(), "BOTTOMRIGHT", 8, 0)
	self.sectionList:SetWidth(170)

	-- 3: settings of the selected section.
	local settings = CreateFrame("Frame", nil, content)
	settings:SetPoint("TOPLEFT", self.sectionList:GetFrame(), "TOPRIGHT", 8, 0)
	settings:SetPoint("BOTTOMLEFT", self.sectionList:GetFrame(), "BOTTOMRIGHT", 8, 0)
	settings:SetWidth(290)
	self.sectionTitle = Skin.FontString(settings, "title")
	self.sectionTitle:SetPoint("TOPLEFT", 0, -2)
	self.sectionTitle:SetPoint("TOPRIGHT", 0, -2)
	self.sectionTitle:SetJustifyH("LEFT")
	self.inspector = W.Inspector:New(settings)
	self.inspector:SetPoint("TOPLEFT", 0, -24)
	self.inspector:SetPoint("BOTTOMRIGHT")

	-- 4: preview: toolbar, stage, status line.
	local center = CreateFrame("Frame", nil, content)
	center:SetPoint("TOPLEFT", settings, "TOPRIGHT", 12, 0)
	center:SetPoint("BOTTOMRIGHT")
	self:BuildToolbar(center)

	local stage = CreateFrame("Frame", nil, center, "BackdropTemplate")
	stage:SetPoint("TOPLEFT", self.toolbar, "BOTTOMLEFT", 0, -6)
	stage:SetPoint("BOTTOMRIGHT", 0, 22)
	stage:SetClipsChildren(true)
	Skin.ApplyPanel(stage, "panel")
	self.stage = stage
	stage:SetScript("OnSizeChanged", function() self:FitStage() end)

	self.holder = CreateFrame("Frame", nil, stage)
	self.holder:SetSize(1, 1)
	self.holder:SetPoint("CENTER")

	self.bounds = CreateFrame("Frame", nil, self.holder, "BackdropTemplate")
	self.bounds:SetBackdrop({ edgeFile = Skin.WHITE, edgeSize = 1 })
	self.bounds:SetBackdropBorderColor(1, 0.2, 0.2, 0.9)
	self.bounds:SetFrameLevel(self.holder:GetFrameLevel() + 50) -- above the entry's frames

	self.banner = Skin.FontString(stage, "title")
	self.banner:SetPoint("TOP", 0, -8)
	self.banner:SetTextColor(unpack(Skin.colors.warning))
	self.banner:SetText("FORCED COMBAT RESTRICTIONS: live values are secret")

	self.status = Skin.FontString(center)
	self.status:SetPoint("BOTTOMLEFT", 2, 4)
	self.status:SetPoint("BOTTOMRIGHT", -2, 4)
	self.status:SetJustifyH("LEFT")

	self.eventFrame = CreateFrame("Frame")
	self.eventFrame:SetScript("OnEvent", function(_, event, ...)
		self:OnUnitEvent(event, ...)
	end)

	self.window:GetFrame():SetScript("OnUpdate", function(_, elapsed)
		self:OnUpdate(elapsed)
	end)
	self.window:GetFrame():HookScript("OnHide", function()
		self.eventFrame:UnregisterAllEvents()
	end)
	self.window:GetFrame():HookScript("OnShow", function()
		self:RegisterEntryEvents()
	end)

	self:ApplyStageOptions()
	self:FillList()
	local first = db.selected and self.entries[db.selected] and db.selected or (self.order[1] and self.order[1].id)
	if first then
		self.list:Select(first)
		self:Select(first)
	end
end

function Workbench:BuildToolbar(parent)
	local db = self:GetDB()
	local toolbar = CreateFrame("Frame", nil, parent)
	toolbar:SetPoint("TOPLEFT")
	toolbar:SetPoint("TOPRIGHT")
	toolbar:SetHeight(72)
	self.toolbar = toolbar

	-- Stage options on top.
	local row = CreateFrame("Frame", nil, toolbar)
	row:SetPoint("TOPLEFT")
	row:SetPoint("TOPRIGHT")
	row:SetHeight(44)

	-- Presets of the current entry below, wrapping onto more lines.
	self.presetRow = CreateFrame("Frame", nil, toolbar)
	self.presetRow:SetPoint("TOPLEFT", 0, -50)
	self.presetRow:SetPoint("TOPRIGHT", 0, -50)
	self.presetRow:SetHeight(22)
	self.presetRow:SetScript("OnSizeChanged", function()
		self:LayoutPresets()
	end)
	self.presetButtons = {}

	local function Place(widget, width, previous)
		widget:SetWidth(width)
		if previous then
			widget:SetPoint("TOPLEFT", previous:GetFrame(), "TOPRIGHT", 10, 0)
		else
			widget:SetPoint("TOPLEFT", row, "TOPLEFT")
		end
		return widget
	end

	self.widthSlider = Place(W.Slider:New(row, { label = "Width", min = 10, max = 600, step = 1,
		onChange = function(value) self:SetEntrySize(value, nil) end }), 80)
	self.heightSlider = Place(W.Slider:New(row, { label = "Height", min = 4, max = 300, step = 1,
		onChange = function(value) self:SetEntrySize(nil, value) end }), 80, self.widthSlider)
	self.scaleSlider = Place(W.Slider:New(row, { label = "Scale", min = 0.5, max = 3, step = 0.1,
		onChange = function(value)
			db.stage.scale = value
			self:ApplyStageOptions()
		end }), 80, self.heightSlider)
	self.backgroundDropdown = Place(W.Dropdown:New(row, { label = "Background", values = STAGE_BACKGROUNDS,
		onChange = function(value)
			db.stage.background = value
			self:ApplyStageOptions()
		end }), 100, self.scaleSlider)

	self.boundsCheck = W.Checkbox:New(row, { label = "Bounds", onChange = function(value)
		db.stage.bounds = value
		self:ApplyStageOptions()
	end })
	self.boundsCheck:SetWidth(70)
	self.boundsCheck:SetPoint("TOPLEFT", self.backgroundDropdown:GetFrame(), "TOPRIGHT", 10, -2)

	self.secretCheck = W.Checkbox:New(row, {
		label = "Force secrets",
		tooltip = "Turns on the addonCombatRestrictionsForced and addonEncounterRestrictionsForced CVars so the live sources return real secret values outside combat. Turned off again when the Workbench closes.",
		onChange = function(value)
			self:SetForcedRestrictions(value)
		end,
	})
	self.secretCheck:SetWidth(110)
	self.secretCheck:SetPoint("TOPLEFT", self.boundsCheck:GetFrame(), "BOTTOMLEFT", 0, -2)
end

function Workbench:ApplyStageOptions()
	local stageDB = self:GetDB().stage
	self.stage:SetBackdropColor(unpack(STAGE_COLORS[stageDB.background] or STAGE_COLORS.dark))
	self:FitStage()
	self.scaleSlider:SetValue(stageDB.scale)
	self.backgroundDropdown:SetValue(stageDB.background)
	self.boundsCheck:SetValue(stageDB.bounds)
	self.bounds:SetShown(stageDB.bounds and self.handle ~= nil)
	self.secretCheck:SetValue(self.forcedRestrictions)
	self.banner:SetShown(self.forcedRestrictions == true)
end

-- Only opt-in previews have ordinary, addon-owned dimensions. Never inspect
-- native aura/container bounds here: those can be secret even outside combat.
function Workbench:FitStage()
	if not self.holder then return end
	if self.entry and self.entry.fitToStage and InCombatLockdown() then
		self.pendingStageFit = true
		return
	end
	self.pendingStageFit = nil
	local scale = self:GetDB().stage.scale
	if self.entry and self.entry.fitToStage and self.handle then
		local width, height = self.handle.frame:GetSize()
		local availableWidth, availableHeight = self.stage:GetWidth() - 32, self.stage:GetHeight() - 32
		if width > 0 and height > 0 and availableWidth > 0 and availableHeight > 0 then
			scale = math.min(scale, availableWidth / width, availableHeight / height)
		end
	end
	if self.holder:GetScale() ~= scale then self.holder:SetScale(scale) end
end

function Workbench:BuildPresets(entry)
	for _, button in ipairs(self.presetButtons) do
		button:Hide()
	end
	local presets = {}
	for _, preset in ipairs(entry.presets or {}) do
		presets[#presets + 1] = preset
	end
	presets[#presets + 1] = { name = "Reset", reset = true }

	for i, preset in ipairs(presets) do
		local button = self.presetButtons[i]
		if not button then
			button = W.Button:New(self.presetRow, {})
			self.presetButtons[i] = button
		end
		button:SetText(preset.name)
		button:SetWidth(math.max(60, button.text:GetStringWidth() + 20))
		button.opts.onClick = function()
			self:ApplyPreset(preset)
		end
		button:Show()
	end
	self.presetCount = #presets
	self:LayoutPresets()
end

-- Flows the preset buttons into lines that fit the preview column.
function Workbench:LayoutPresets()
	local maxWidth = self.presetRow:GetWidth()
	local x, line = 0, 0
	for i = 1, self.presetCount or 0 do
		local button = self.presetButtons[i]
		local width = button:GetFrame():GetWidth()
		if x > 0 and maxWidth > 0 and x + width > maxWidth then
			x, line = 0, line + 1
		end
		button:ClearAllPoints()
		button:SetPoint("TOPLEFT", self.presetRow, "TOPLEFT", x, -line * 26)
		x = x + width + 4
	end
	local height = (line + 1) * 26
	self.presetRow:SetHeight(height)
	self.toolbar:SetHeight(50 + height)
end

function Workbench:SetEntrySize(width, height)
	local state = self.state
	if not state then
		return
	end
	state.width = width or state.width
	state.height = height or state.height
	self:ApplySize()
end

function Workbench:ApplySize()
	local state, autoSize = self.state, self.entry.autoSize or self.entry.fillStage
	self.widthSlider:SetShown(not autoSize)
	self.heightSlider:SetShown(not autoSize)
	if autoSize then
		return
	end
	self.handle.frame:SetSize(state.width, state.height)
	self.widthSlider:SetValue(state.width)
	self.heightSlider:SetValue(state.height)
end
