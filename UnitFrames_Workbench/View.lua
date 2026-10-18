local _, wb = ...
local UF = UnitFrames
local Workbench, W, Skin = wb.Workbench, UF.Widgets, UF.Skin

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
	self.content = content
	self:BuildSearch(content)

	-- 1: entries.
	self.list = W.ScrollList:New(content, {
		rowHeight = 20,
		onSelect = function(item)
			if item.entryId and (not self.entry or self.entry.id ~= item.entryId) then self:Select(item.entryId) end
			if item.pageId then self:SelectSection(item.pageId)
			else self:Select(item.id) end
		end,
	})
	self.list:SetPoint("TOPLEFT", 0, -74)
	self.list:SetPoint("BOTTOMLEFT")
	self.list:SetWidth(210)

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
	self.sectionList:Hide()

	-- 3: settings of the selected section.
	local settings = CreateFrame("Frame", nil, content)
	settings:SetPoint("TOPLEFT", self.list:GetFrame(), "TOPRIGHT", 12, 0)
	settings:SetPoint("BOTTOMLEFT", self.list:GetFrame(), "BOTTOMRIGHT", 12, 0)
	settings:SetWidth(380)
	self.settingsPane = settings
	self.sectionTitle = Skin.FontString(settings, "title")
	self.sectionTitle:SetPoint("TOPLEFT", 0, -2)
	self.sectionTitle:SetPoint("TOPRIGHT", 0, -2)
	self.sectionTitle:SetJustifyH("LEFT")
	self.scopeLabel = Skin.FontString(settings)
	self.scopeLabel:SetPoint("TOPLEFT", 0, -24)
	self.scopeLabel:SetPoint("TOPRIGHT", 0, -24)
	self.scopeLabel:SetJustifyH("LEFT")
	self.localSections = W.Dropdown:New(settings, { label = "Section", onChange = function(value)
		self:SelectFeaturePage(self.state.section, value)
	end })
	self.localSections:SetPoint("TOPLEFT", 0, -46)
	self.localSections:SetPoint("TOPRIGHT", 0, -46)
	self.navigationMessage = Skin.FontString(settings)
	self.navigationMessage:SetPoint("TOPLEFT", 0, -92)
	self.navigationMessage:SetPoint("TOPRIGHT", 0, -92)
	self.navigationMessage:SetHeight(36)
	self.navigationMessage:SetWordWrap(true)
	self.navigationMessage:SetJustifyH("LEFT")
	self.prerequisiteButton = W.Button:New(settings, { text = "Open controlling setting", onClick = function()
		if self.prerequisiteDestination then self:OpenDestination(self.prerequisiteDestination) end
	end })
	self.prerequisiteButton:SetPoint("TOPLEFT", 0, -128)
	self.prerequisiteButton:Hide()
	self.frameReset = W.Button:New(settings, { text = "Reset frame style", onClick = function()
		if self.entry.reset then self.entry.reset() end
	end })
	self.frameReset:SetPoint("TOPLEFT", 0, -128)
	self.frameReset:SetWidth(170)
	self.frameReset:Hide()
	self.detailsCheck = W.Checkbox:New(settings, { label = "Detailed adjustments",
		tooltip = "Show horizontal and vertical offsets available in this section.", onChange = function(value)
		self.inspector:SetDetails(value)
	end })
	self.detailsCheck:SetPoint("TOPRIGHT", 0, -128)
	self.detailsCheck:SetWidth(170)
	self.inspector = W.Inspector:New(settings)
	self.inspector.onDetailsChanged = function(available, expanded)
		self.detailsCheck:SetValue(expanded)
		self.detailsCheck:SetShown(available and not self.prerequisiteDestination)
	end
	self.inspector.onInherited = function(path)
		local model = self:GetCatalogue().models.theme
		local destination = model and model.owners["style|" .. path]
		if destination then self:OpenDestination(destination) end
	end
	self.inspector:SetPoint("TOPLEFT", 0, -156)
	self.inspector:SetPoint("BOTTOMRIGHT")
	self.contextLinks = W.Dropdown:New(settings, { label = "Related Settings", onChange = function(value)
		local link = self.contextDestinations[value]
		if link then self:OpenDestination(link.record) end
	end })
	self.contextLinks:SetPoint("TOPLEFT", 0, -156)
	self.contextLinks:SetPoint("TOPRIGHT", 0, -156)
	self.contextLinks:Hide()

	-- 4: preview: toolbar, stage, status line.
	local center = CreateFrame("Frame", nil, content)
	self.previewPane = center
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
		self.resultPanel:Hide()
		self.search.input:ClearFocus()
		self.inspector:ClearReveal()
		self.inspector:FinishEditing()
		if self.session then self.session:ActivateEvents(self.eventFrame, false) end
	end)
	self.window:GetFrame():HookScript("OnShow", function()
		self:RegisterEntryEvents()
		self:UpdateData()
	end)

	self:ApplyStageOptions()
	content:HookScript("OnSizeChanged", function() self:LayoutWorkbench() end)
	self:FillList()
	local first = db.selected and self.entries[db.selected] and db.selected or (self.order[1] and self.order[1].id)
	if first then
		self.list:Select(first)
		self:Select(first)
	end
	self:LayoutWorkbench()
end

function Workbench:LayoutWorkbench()
	local available = self.content:GetWidth()
	if available <= 0 then available = self.window:GetFrame():GetWidth() - 24 end
	local preference = self:GetDB().stage.preview
	local shown = preference == true or (preference ~= false and available >= 1160)
	if self.entry and self.entry.fillStage then shown = true end
	self.previewPane:SetShown(shown)
	self.previewToggle:SetText(shown and "Hide preview" or "Show preview")
	self.settingsPane:SetWidth(shown and 380 or math.max(380, available - 222))
	self:FitStage()
end
