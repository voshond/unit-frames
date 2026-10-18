local _, wb = ...
local Workbench = wb.Workbench

function Workbench:FillFeaturePages()
	self.inspector:Show()
	self.pageModel = self:GetCatalogue().models[self.entry.id]
	self.pageTargets = { style = self.styleTarget }
	for _, descriptor in ipairs(self.entry.settingsTargets()) do
		if descriptor.target then self.pageTargets[descriptor.id] = descriptor.target() end
	end
	self.sections, self.settingsPages = {}, {}
	for _, page in ipairs(self.pageModel.pages) do
		self.sections[#self.sections + 1] = { id = page.id, text = page.label }
		self.settingsPages[page.id] = page
	end
	for _, link in ipairs(self.entry.links or {}) do
		self.sections[#self.sections + 1] = { id = link.id, text = link.label, destinationEntry = link.entryId }
	end
	if self.dataTarget then self.sections[#self.sections + 1] = { id = "@data", text = "Preview only" } end
	self.sectionList:SetItems(self.sections)
	self:SelectFeaturePage(self.state.section or self.sections[1].id)
	self:FillList()
end

function Workbench:SelectFeaturePage(id, sectionId)
	for _, link in ipairs(self.entry.links or {}) do
		if link.id == id then self:Select(link.entryId); self:SelectFeaturePage(id, sectionId); return end
	end
	self.prerequisiteButton:Hide()
	self.prerequisiteDestination = nil
	self.navigationMessage:SetText("")
	self.frameReset:Hide()
	self.detailsCheck:Hide()
	self.contextLinks:Hide()
	self.inspector:SetPoint("TOPLEFT", 0, -156)
	if id == "@data" and self.dataTarget then
		self.inspector:Show()
		self.state.section = id
		self.activeFeatureSection = nil
		self.localSections:Hide()
		self.inspector:SetTarget(self.dataTarget, self.entry.id .. "|@data", "")
		self.sectionTitle:SetText("Preview only")
		self.scopeLabel:SetText("Preview only — changes the simulation")
		self:FillList()
		return
	end
	local model = self.pageModel
	local page = model.byId[id]
	if not page then
		if id == "@icons" or id == "@effects" then page = model.byId["@states"] end
		local prefix = id == "" and "width" or id
		for _, record in ipairs(model.records) do
			if record.path == prefix or record.path:sub(1, #prefix + 1) == prefix .. "." then
				page, sectionId = model.byId[record.pageId], record.sectionId
				break
			end
		end
	end
	page = page or model.pages[1]
	self.state.section = page.id
	self.state.localSections = self.state.localSections or {}
	sectionId = sectionId or self.state.localSections[page.id]
	local section = page.byId[sectionId] or page.sections[1]
	self.state.localSections[page.id] = section.id
	self.localSections:Show()
	local labels, details = {}, {}
	for _, path in ipairs(section.paths) do
		local record = model.owners[section.targetId .. "|" .. path]
		labels[path] = record.label
		details[path] = path:match("%.offset[XY]$") ~= nil
	end
	self.inspector:SetTarget(self.pageTargets[section.targetId], self.entry.id .. "|" .. page.id .. "|" .. section.id,
		{ paths = section.paths, labels = labels, sources = not self.entry.fillStage, details = details })
	self.sectionTitle:SetText(wb.Presentation.NavLabel((self.entry.id == "theme" and "Global Settings" or self.entry.name) .. " > " .. page.label))
	self.scopeLabel:SetText("Applies to: " .. (section.scope or self.entry.scope or self.entry.name))
	self.activeFeatureSection = section
	self:UpdateFeatureHeader()
	self.frameReset:SetText(self.entry.id == "clickgrid.panel" and "Reset panel settings" or "Reset frame style")
	self.frameReset:SetShown(page.id == "@layout" and self.entry.reset ~= nil)
	self.navigationMessage:SetText(wb.Presentation.Hint(page.id, section) or "")
	self:UpdateContextLinks(page, section)
	self.inspector:SetShown(#section.paths > 0)
	self.sectionList:Select(page.id)
	self:FillList()
end

function Workbench:UpdateFeatureHeader()
	if not self.pageModel or not self.activeFeatureSection then return end
	local section = self.activeFeatureSection
	local page = self.pageModel.byId[self.state.section]
	local values = {}
	for _, item in ipairs(page.sections) do
		local label = wb.Presentation.NavLabel(item.label)
		if self.entry.id == "clickgrid.panel" and page.id == "@states" then
			label = label .. (item.targetId == "member" and " — Member style" or " — Panel indicators")
		end
		for _, path in ipairs(item.paths) do
			local slot = path:match("^(.-)%.format$")
			local target = self.pageTargets[item.targetId]
			local descriptor = slot and UnitFrames.Schema.Find(target.schema, slot)
			if descriptor and descriptor.textSlot then
				local format = UnitFrames.Util.GetPath(target.resolved(), path)
				for _, choice in ipairs(UnitFrames.Schema.GetValues(UnitFrames.Schema.Find(target.schema, path))) do
					if choice[1] == format then label = label .. " — " .. choice[2]; break end
				end
				break
			end
		end
		values[#values + 1] = { item.id, label }
	end
	self.localSections.opts.values = values
	self.localSections:SetValue(section.id)
	local path = section.paths[1]
	local root = path and path:match("^[^%.]+")
	local target = self.pageTargets and self.pageTargets[section.targetId]
	if not target then return end
	local resolved = target.resolved()
	local feature = root and resolved[root]
	local suffix = type(feature) == "table" and feature.enabled == false and " · Feature switched off" or ""
	self.scopeLabel:SetText("Applies to: " .. (section.scope or self.entry.scope or self.entry.name) .. suffix)
end

function Workbench:UpdateContextLinks(page, section)
	self.contextDestinations = wb.Presentation.Links(self:GetCatalogue(), self.entry.id, page, section)
	local values = {}
	for index, link in ipairs(self.contextDestinations) do values[#values + 1] = { index, link.label } end
	self.contextLinks.opts.values = values
	self.contextLinks:SetValue("Open related settings…")
	self.contextLinks:SetShown(#values > 0)
	self.inspector:SetPoint("TOPLEFT", 0, #values > 0 and -204 or -156)
end

function Workbench:OpenDestination(record)
	local entry = self.entries[record.entryId]
	if not entry then return false end
	if self.entry ~= entry then self:Select(entry.id) end
	if record.pageId then
		if self.pageModel then self:SelectFeaturePage(record.pageId, record.sectionId)
		else self:SelectSection(record.pageId) end
	end
	if record.reveal then record.reveal(self.handle) end
	local message = record.hint
	if record.path then
		local revealed, label = self.inspector:Reveal(record.path)
		if revealed then message = "Selected: " .. label
		else
			local prerequisite = record.prerequisite or record.opt.prerequisite
			if prerequisite then
				message = prerequisite.message
				local controlling = self.pageModel and self.pageModel.owners[record.targetId .. "|" .. prerequisite.path]
				self.prerequisiteDestination = controlling
				self.prerequisiteButton:SetShown(controlling ~= nil)
				self.frameReset:Hide()
				self.detailsCheck:Hide()
			else message = "This setting is unavailable in the current mode or class context. Check the feature's controlling options." end
		end
	end
	self.navigationMessage:SetText(message or ("Selected: " .. record.label))
	return true
end
