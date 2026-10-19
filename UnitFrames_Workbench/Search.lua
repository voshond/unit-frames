local _, wb = ...
local Workbench, W, Skin = wb.Workbench, UnitFrames.Widgets, UnitFrames.Skin
local GROUP_LABELS = { settings = "Settings", preview = "Preview Only — Simulation", developer = "Developer Tools" }
local HIGHLIGHT = string.format("|cff%02x%02x%02x", math.floor(Skin.colors.accent[1] * 255),
	math.floor(Skin.colors.accent[2] * 255), math.floor(Skin.colors.accent[3] * 255))

local function Location(record)
	if record.breadcrumb:lower():find(record.scope:lower(), 1, true) then return record.breadcrumb end
	return record.breadcrumb .. "  ·  " .. record.scope
end

local function GroupByLocation(results)
	local sections, ordered = {}, {}
	for _, result in ipairs(results) do
		local key = result.record.group .. "|" .. Location(result.record)
		if not sections[key] then
			sections[key] = {}
			sections[#sections + 1] = sections[key]
		end
		table.insert(sections[key], result)
	end
	for _, section in ipairs(sections) do
		for _, result in ipairs(section) do ordered[#ordered + 1] = result end
	end
	return ordered
end

local function Highlight(text, query)
	local lower, marks = text:lower(), {}
	for token in wb.Catalogue.Normalise(query):gmatch("%S+") do
		for _, word in ipairs(wb.Catalogue.Alternatives(token)) do
			local start, stop = lower:find(word, 1, true)
			while start do
				for index = start, stop do marks[index] = true end
				start, stop = lower:find(word, stop + 1, true)
			end
		end
	end
	local parts, index = {}, 1
	while index <= #text do
		local stop = index
		while stop < #text and marks[stop + 1] == marks[index] do stop = stop + 1 end
		local chunk = text:sub(index, stop)
		parts[#parts + 1] = marks[index] and HIGHLIGHT .. chunk .. "|r" or chunk
		index = stop + 1
	end
	return table.concat(parts)
end

function Workbench:BuildSearch(content)
	self.search = W.EditBox:New(content, { label = "Search all settings…", height = 26,
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
	self.clearSearch = W.Button:New(content, { text = "Clear", width = 55, height = 26, onClick = function()
		self.searchQuery = ""
		self.search:SetValue("")
		self:UpdateSearch()
	end })
	self.clearSearch:SetPoint("BOTTOMLEFT", self.search:GetFrame(), "BOTTOMRIGHT", 8, 0)
	self.searchFilter = W.Dropdown:New(content, { label = "Search scope", values = {
		{ "all", "All settings" }, { "frame", "Current frame" }, { "page", "Current page" },
		{ "preview", "Include preview only" }, { "developer", "Include developer tools" },
	}, onChange = function(value) self.searchScope = value; self:UpdateSearch() end })
	self.searchFilter:SetPoint("BOTTOMLEFT", self.clearSearch:GetFrame(), "BOTTOMRIGHT", 16, 0)
	self.searchFilter:SetWidth(170)
	self.searchFilter:SetValue("all")
	self.previewToggle = W.Button:New(content, { text = "Hide preview", width = 110, height = 26, onClick = function()
		local db = self:GetDB()
		db.stage.preview = not self.previewPane:IsShown()
		self:LayoutWorkbench()
	end })
	self.previewToggle:SetPoint("TOPRIGHT", 0, -18)
	self.profileLabel = Skin.FontString(content)
	self.profileLabel:SetPoint("TOPLEFT", 0, -50)
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
	self.resultList = W.ScrollList:New(panel, { rowHeight = 22, stickyHeaders = true, onSelect = function(item)
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
	self.searchResults = GroupByLocation(wb.Catalogue.Query(catalogue, self.searchQuery, options))
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
	local count = #self.searchResults
	local mixed = count > 0 and self.searchResults[1].record.group ~= self.searchResults[count].record.group
	local group, location
	for index, result in ipairs(self.searchResults) do
		local record = result.record
		if record.group ~= group then
			group, location = record.group, nil
			if mixed then items[#items + 1] = { header = true, text = GROUP_LABELS[group] } end
		end
		if Location(record) ~= location then
			location = Location(record)
			items[#items + 1] = { header = true, sticky = true, text = Highlight(location, self.searchQuery) }
		end
		items[#items + 1] = { id = index, record = record, text = Highlight(record.label, self.searchQuery)
			.. (not record.path and " (page/editor)" or record.opt.type == "action" and " (action)" or "") }
	end
	self.resultList:SetItems(items)
	self.searchSelection = selection
	self.resultList:Select(selection)
	self.resultCount:SetText(count > 0 and (count .. " results") or "No results — try fewer words or All settings.")
	self.resultPanel:SetShown(wb.Catalogue.Normalise(self.searchQuery) ~= "")
end

function Workbench:OpenSearchResult(record)
	self.search.input:ClearFocus()
	self.resultPanel:Hide()
	self:OpenDestination(record)
end
