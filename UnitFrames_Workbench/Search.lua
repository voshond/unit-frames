local _, wb = ...
local Workbench, W, Skin = wb.Workbench, UnitFrames.Widgets, UnitFrames.Skin

function Workbench:BuildSearch(content)
	self.search = W.EditBox:New(content, { label = "Search all settings…",
		onTextChanged = function(query) self.searchQuery = query; self:UpdateSearch() end,
		onArrowPressed = function(key)
			if key ~= "UP" and key ~= "DOWN" then return end
			local count = #(self.searchResults or {})
			if count == 0 then return end
			self.searchSelection = math.max(1, math.min(count, (self.searchSelection or 1) + (key == "UP" and -1 or 1)))
			self.resultList:Select(self.searchSelection)
		end,
		onEnter = function()
			local result = (self.searchResults or {})[self.searchSelection or 1]
			if result then self:OpenSearchResult(result.record) end
		end,
		onEscape = function()
			self.resultPanel:Hide()
			self.search.input:ClearFocus()
		end,
	})
	self.search:SetPoint("TOPLEFT")
	self.search:SetWidth(400)
	self.search.input:HookScript("OnEditFocusGained", function() self:UpdateSearch() end)
	self.clearSearch = W.Button:New(content, { text = "Clear", onClick = function()
		self.searchQuery = ""
		self.search:SetValue("")
		self:UpdateSearch()
	end })
	self.clearSearch:SetPoint("TOPLEFT", self.search:GetFrame(), "TOPRIGHT", 8, -16)
	self.clearSearch:SetWidth(55)
	self.searchFilter = W.Dropdown:New(content, { label = "Search scope", values = {
		{ "all", "All settings" }, { "frame", "Current frame" }, { "page", "Current page" },
		{ "preview", "Include preview only" }, { "developer", "Include developer tools" },
	}, onChange = function(value) self.searchScope = value; self:UpdateSearch() end })
	self.searchFilter:SetPoint("TOPLEFT", self.clearSearch:GetFrame(), "TOPRIGHT", 8, 16)
	self.searchFilter:SetWidth(170)
	self.searchFilter:SetValue("all")
	self.previewToggle = W.Button:New(content, { text = "Hide preview", onClick = function()
		local db = self:GetDB()
		db.stage.preview = not self.previewPane:IsShown()
		self:LayoutWorkbench()
	end })
	self.previewToggle:SetPoint("TOPRIGHT", 0, -16)
	self.previewToggle:SetWidth(110)
	self.profileLabel = Skin.FontString(content)
	self.profileLabel:SetPoint("TOPLEFT", 0, -44)
	self.profileLabel:SetJustifyH("LEFT")
	local panel = CreateFrame("Frame", nil, content, "BackdropTemplate")
	panel:SetPoint("TOPLEFT", 0, -66)
	panel:SetPoint("RIGHT", content, "RIGHT", -8, 0)
	panel:SetHeight(360)
	panel:SetFrameStrata("DIALOG")
	Skin.ApplyPanel(panel, "panel")
	self.resultPanel = panel
	self.resultCount = Skin.FontString(panel)
	self.resultCount:SetPoint("TOPLEFT", 8, -6)
	self.resultList = W.ScrollList:New(panel, { rowHeight = 58, onSelect = function(item)
		self.searchSelection = item.id
		self:OpenSearchResult(item.record)
	end })
	self.resultList:SetPoint("TOPLEFT", 6, -28)
	self.resultList:SetPoint("BOTTOMRIGHT", -6, 6)
	panel:Hide()
end

function Workbench:UpdateSearch()
	if not self.resultPanel then return end
	if wb.Catalogue.Normalise(self.searchQuery) == "" then
		self.searchResults = {}
		self.searchContext = nil
		self.searchSelection = nil
		self.resultPanel:Hide()
		return
	end
	local scope = self.searchScope
	local options = { currentEntry = self.entry and self.entry.id, preview = scope == "preview", developer = scope == "developer" }
	if scope == "frame" or scope == "page" then options.entryId = options.currentEntry end
	if scope == "page" and self.state then options.pageId = self.state.section end
	local catalogue = self:GetCatalogue()
	local context = table.concat({ self.searchQuery, scope or "all", options.entryId or "", options.pageId or "" }, "|")
	if context == self.searchContext and catalogue == self.searchCatalogue then
		self.resultPanel:Show()
		return
	end
	local previous = self.searchResults and self.searchResults[self.searchSelection or 1]
	self.searchResults = wb.Catalogue.Query(catalogue, self.searchQuery, options)
	local selection = 1
	if context == self.searchContext and previous then
		for index, result in ipairs(self.searchResults) do
			local record, old = result.record, previous.record
			if record.entryId == old.entryId and record.targetId == old.targetId and record.path == old.path
				and record.label == old.label then selection = index; break end
		end
	end
	self.searchContext, self.searchCatalogue = context, catalogue
	local items = {}
	local group
	for index, result in ipairs(self.searchResults) do
		local record = result.record
		if record.group ~= group then
			group = record.group
			local labels = { settings = "Settings", preview = "Preview Only — Simulation", developer = "Developer Tools" }
			items[#items + 1] = { header = true, text = labels[group] }
		end
		items[#items + 1] = { id = index, record = record,
			text = record.label .. (not record.path and " (page/editor)" or record.opt.type == "action" and " (action)" or "")
				.. "\n" .. record.breadcrumb .. "\n" .. record.scope }
	end
	self.resultList:SetItems(items)
	self.searchSelection = selection
	self.resultList:Select(selection)
	local count = #self.searchResults
	self.resultCount:SetText(count > 0 and (count .. " results") or "No results — try fewer words or All settings.")
	self.resultPanel:SetShown(wb.Catalogue.Normalise(self.searchQuery) ~= "")
end

function Workbench:OpenSearchResult(record)
	self.search.input:ClearFocus()
	self.resultPanel:Hide()
	self:OpenDestination(record)
end
