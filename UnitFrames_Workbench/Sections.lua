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
-- Groups with only sub-groups are headers (not selectable).
local function SectionItems(items, schema, prefix, depth)
	for _, opt in ipairs(schema) do
		if opt.type == "group" then
			local path = prefix .. opt.key
			if HasOptions(opt.schema) then
				items[#items + 1] = { id = path, text = opt.label or opt.key, depth = depth }
			else
				items[#items + 1] = { text = opt.label or opt.key, depth = depth, header = true }
			end
			SectionItems(items, opt.schema, path .. ".", depth + 1)
		end
	end
	return items
end

function Workbench:FillSections()
	local items = {}
	if self.dataTarget then
		items[#items + 1] = { id = DATA_SECTION, text = "Preview data" }
	end
	if HasOptions(self.styleTarget.schema) then
		items[#items + 1] = { id = "", text = "General" }
	end
	SectionItems(items, self.styleTarget.schema, "", 0)
	self.sections = items

	local wanted = self.state.section
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
	if first then
		self:SelectSection(first)
	else
		self.sectionTitle:SetText("")
	end
end

-- Shows the settings of one section ("" = top level, DATA_SECTION = data).
function Workbench:SelectSection(id)
	self.state.section = id
	local title
	for _, item in ipairs(self.sections) do
		if item.id == id then
			title = item.text
		end
	end
	if id == DATA_SECTION then
		self.inspector:SetTarget(self.dataTarget, self.entry.id .. "|" .. DATA_SECTION, "")
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
