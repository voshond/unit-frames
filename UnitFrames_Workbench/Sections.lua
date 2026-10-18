local _, wb = ...
local UF = UnitFrames
local Workbench, W, Schema = wb.Workbench, UF.Widgets, UF.Schema

-- Schema navigation and inspector targets; pages outlive preview sessions.
local DATA_SECTION = "@data"

local function HasOptions(schema)
	for _, opt in ipairs(schema) do
		if opt.type ~= "group" then
			return true
		end
	end
	return false
end

-- The settings tree as list items: one item per group, indented by depth.
-- Groups with only sub-groups are headers (not selectable). Inline groups
-- belong to their parent's section.
local function SectionItems(items, schema, prefix, depth, excluded)
	for _, opt in ipairs(schema) do
		if opt.type == "group" and not opt.inline then
			local path = prefix .. opt.key
			if not excluded[path] then
				if HasOptions(opt.schema) then
					items[#items + 1] = { id = path, text = opt.label or opt.key, depth = depth }
				else
					items[#items + 1] = { text = opt.label or opt.key, depth = depth, header = true }
				end
				SectionItems(items, opt.schema, path .. ".", depth + 1, excluded)
			end
		end
	end
	return items
end

function Workbench:FillSections()
	self.pageModel = nil
	if self.entry.settingsTargets then self:FillFeaturePages(); return end
	if self.localSections then self.localSections:Hide() end
	self.frameReset:Hide()
	self.detailsCheck:Hide()
	self.contextLinks:Hide()
	self.inspector:SetPoint("TOPLEFT", 0, -156)
	self.scopeLabel:SetText("Developer tools — preview only")
	local items = {}
	local excluded, pages = {}, {}
	local wanted = self.state.section
	for _, page in ipairs(self.entry.settingsPages or {}) do
		assert(page.id:sub(1, 1) == "@" and page.id ~= DATA_SECTION, "Settings page needs a unique @ id")
		assert(not pages[page.id], "Duplicate settings page " .. page.id)
		pages[page.id] = page
		for _, path in ipairs(page.paths) do
			assert(Schema.Find(self.styleTarget.schema, path), "Unknown settings page path " .. path)
			excluded[path] = true
			if wanted == path or (wanted and wanted:sub(1, #path + 1) == path .. ".") then wanted = page.id end
		end
	end
	if self.dataTarget then
		items[#items + 1] = { id = DATA_SECTION, text = "Preview data" }
	end
	if HasOptions(self.styleTarget.schema) then
		items[#items + 1] = { id = "", text = "General" }
	end
	SectionItems(items, self.styleTarget.schema, "", 0, excluded)
	for _, page in ipairs(self.entry.settingsPages or {}) do
		items[#items + 1] = { id = page.id, text = page.label }
	end
	self.sections = items
	self.settingsPages = pages

	local first
	for _, item in ipairs(items) do
		if not item.header then
			first = first or item.id
			if item.id == wanted then
				first = wanted
				break
			end
		end
	end
	self.sectionList:SetItems(items)
	self.sectionList:Select(first)
	self.inspector:SetShown(first ~= nil)
	self:FillList()
	if first then
		self:SelectSection(first)
	else
		self.sectionTitle:SetText("")
	end
end

-- Shows the settings of one section ("" = top level, DATA_SECTION = data).
function Workbench:SelectSection(id)
	if self.pageModel then self:SelectFeaturePage(id); return end
	self.state.section = id
	local title
	for _, item in ipairs(self.sections) do
		if item.id == id then
			title = item.text
		end
	end
	if id == DATA_SECTION then
		self.inspector:SetTarget(self.dataTarget, self.entry.id .. "|" .. DATA_SECTION, "")
	elseif self.settingsPages[id] then
		self.inspector:SetTarget(self.styleTarget, self.entry.id .. "|" .. id, self.settingsPages[id])
	else
		self.inspector:SetTarget(self.styleTarget, self.entry.id .. "|" .. id, id)
		-- Breadcrumb for nested sections: "Health > Bar > Background".
		local labels, schema = {}, self.styleTarget.schema
		for key in string.gmatch(id, "[^%.]+") do
			local opt = Schema.Find(schema, key)
			labels[#labels + 1] = opt.label or key
			schema = opt.schema
		end
		if #labels > 1 then
			title = table.concat(labels, " > ")
		end
	end
	self.sectionTitle:SetText(title or "")
end

function Workbench:StyleTarget(handle, state)
	return W.Inspector.TableTarget(handle.schema, function() return state.config end, function()
		handle:Apply(state.config)
		self:UpdateData()
	end, function() return handle:Resolved() end)
end
