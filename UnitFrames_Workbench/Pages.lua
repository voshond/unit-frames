local _, wb = ...
local UF = UnitFrames
local Pages = {}
wb.Pages = Pages

local FEATURES = {
	{ "layout", "Layout & border" }, { "health", "Health & shields" }, { "power", "Power" },
	{ "castbar", "Cast bar" }, { "portrait", "Portrait" }, { "auras", "Buffs & debuffs" },
	{ "states", "Indicators & states" }, { "comboPoints", "Combo points" }, { "experience", "Experience" },
}
local AURAS = { auras = "External icons", auraBar = "Embedded row", categoryAuras = "Priority icons", slots = "Tracked friendly buffs", privateAuras = "Private auras" }
local STATES = { range = true, dead = true, resting = true, restingIcon = true, readyCheck = true, readyCheckIcon = true,
	raidTarget = true, pvp = true, classification = true, indicators = true }
local LABELS = { spark = "Fill-edge highlight", range = "Fade out-of-range frames", segments = "Shields and healing overlays",
	castbar = "Cast bar", copyPlayerSettings = "Copy player style" }

function Pages.Walk(schema, visit, prefix, ancestors)
	for _, opt in ipairs(schema) do
		local path = (prefix or "") .. opt.key
		local labels = UF.Util.Copy(ancestors or {})
		labels[#labels + 1] = opt.label or opt.key
		if opt.type == "group" then Pages.Walk(opt.schema, visit, path .. ".", labels)
		else visit(opt, path, labels) end
	end
end

local function Location(entry, path)
	local root = path:match("^[^%.]+")
	if path:match("^indicators%.private") then return "auras", "Buffs & debuffs", "private", "Private auras" end
	if entry.id == "profiles" then return "profiles", "Profiles & sharing", "profiles", "Profile management" end
	if entry.id == "clickgrid.bindings" then
		return "bindings", "Click spells", root == "friendly" and "friendly" or root == "hostile" and "hostile" or "selection",
			root == "friendly" and "Friendly unit" or root == "hostile" and "Hostile unit" or "Binding selection"
	end
	if entry.id == "timers" then
		local timers = { castbar = "Player cast bar", mainHand = "Main hand", offHand = "Off hand", ranged = "Ranged" }
		if timers[root] then return root, timers[root], "bar", "Bar & text" end
	end
	if entry.id == "theme" then
		if root == "colors" then return "colours", "Colours", "colours", "Colours" end
		if root:find("font") then return "fonts", "Fonts", "fonts", "Fonts" end
		return "artwork", "Bars, borders & backgrounds", "artwork", "Bars, borders & backgrounds"
	end
	if entry.id == "clickgrid.panel" then
		if root == "panel" then return "layout", "Panel layout", "layout", "Panel behaviour & layout" end
		if root == "titles" then return "layout", "Panel layout", "titles", "Group titles" end
		if root == "border" then return "layout", "Panel layout", "border", "Panel border" end
	end
	if root == "slots" then
		local slot = path:match("^slots%.([^%.]+)")
		return "auras", "Buffs & debuffs", "slots." .. slot, "Tracked friendly buffs — " .. slot:gsub("slot", "Slot ")
	end
	if AURAS[root] then return "auras", "Buffs & debuffs", root, AURAS[root] end
	if root == "indicators" then
		local key = path:match("^indicators%.([^%.]+)")
		local events = { { "ready", "readyCheck", "Ready check icon" }, { "role", "role", "Group role" },
			{ "leader", "leader", "Leader & assistant" }, { "death", "death", "Dead & ghost" },
			{ "resurrection", "resurrection", "Incoming resurrection" }, { "summon", "summon", "Summon" },
			{ "threat", "threat", "Threat" }, { "dispel", "dispel", "Dispellable debuffs" }, { "hover", "hover", "Mouseover" } }
		for _, event in ipairs(events) do
			if key:sub(1, #event[1]) == event[1] then return "states", "Indicators & states", event[2], event[3] end
		end
		return "states", "Indicators & states", "other", "Other status icons"
	end
	if STATES[root] then
		local section = root == "readyCheckIcon" and "readyCheck" or root == "restingIcon" and "resting" or root
		local names = { dead = "Dead & ghost", readyCheck = "Ready check tints & icon", resting = "Resting border & icon", raidTarget = "Raid marker", pvp = "PvP flag", classification = "Elite & rare" }
		return "states", "Indicators & states", section, names[section] or LABELS[section] or section
	end
	for _, feature in ipairs(FEATURES) do
		if root == feature[1] and root ~= "layout" then
			local slot = path:match("^[^%.]+%.([^%.]+)")
			if path:find("%.bar%.segments%.") then return root, feature[2], "shields", "Shields" end
			local opt = slot and UF.Schema.Find(entry.primarySchema, root .. "." .. slot)
			if opt and opt.textSlot then return root, feature[2], "text." .. slot, opt.label end
			if slot == "textLayout" or slot == "lineGap" then return root, feature[2], "text", "Text layout" end
			return root, feature[2], "bar", root == "portrait" and "portrait" or "Bar"
		end
	end
	return "layout", entry.id == "clickgrid.panel" and "Panel layout" or "Layout & border", root == "border" and "border" or "layout",
		root == "border" and "Outer border" or "Layout & frame actions"
end

function Pages.Build(entry, targets)
	local model = { pages = {}, byId = {}, records = {}, owners = {}, exclusions = {} }
	local context = { id = entry.id, primarySchema = targets[1].schema }
	for _, target in ipairs(targets) do
		Pages.Walk(target.schema, function(opt, path, labels)
			if target.include and not target.include(path) then return end
			local exclusion = opt.internal or (entry.id == "timers" and path == "castbar.portraitLayout" and "Standalone timers do not cover a portrait")
			if exclusion then model.exclusions[target.id .. "|" .. path] = exclusion; return end
			local pageKey, pageLabel, sectionKey, sectionLabel = Location(context, path)
			local pageId = "@" .. pageKey
			local page = model.byId[pageId]
			if not page then
				page = { id = pageId, label = pageLabel, sections = {}, byId = {} }
				model.pages[#model.pages + 1], model.byId[pageId] = page, page
			end
			local sectionId = target.id .. ":" .. sectionKey
			local section = page.byId[sectionId]
			if not section then
				section = { id = sectionId, label = sectionLabel, targetId = target.id, paths = {}, scope = target.scope }
				page.sections[#page.sections + 1], page.byId[sectionId] = section, section
			end
			section.paths[#section.paths + 1] = path
			local label = LABELS[opt.key] or opt.label or opt.key
			if opt.key == "enabled" and (not opt.label or opt.label == "Enabled") then label = "Show " .. (labels[#labels - 1] or entry.name) end
			if opt.key == "format" then label = labels[1] .. " text content — " .. (labels[#labels - 1] or "Text") end
			if path == "castbar.enabled" then label = "Show cast bar" end
			if path == "range.enabled" then label = "Fade out-of-range frames" end
			if path == "auras.enabled" then label = "Show external aura icons" end
			if path == "auraBar.enabled" then label = "Show embedded icon row" end
			if path == "categoryAuras.enabled" then label = "Show priority icons" end
			if opt.key == "spark" then label = "Fill-edge highlight" end
			if path:find("%.segments%.absorb%.") then
				if opt.key == "placement" then label = "Shield placement" end
				if opt.key == "color" then label = "Shield colour" end
			end
			local record = { entryId = entry.id, targetId = target.id, path = path, pageId = pageId, sectionId = sectionId,
				label = label, scope = target.scope or entry.scope or entry.name, opt = opt,
				breadcrumb = table.concat({ entry.category, entry.name, pageLabel, sectionLabel }, " > "),
				ancestry = table.concat(labels, " ") }
			record.storeId = target.storeId or entry.id
			if entry.id == "theme" then
				record.breadcrumb = "Global Settings > " .. wb.Presentation.NavLabel(pageLabel)
				record.aliases = "shared appearance theme defaults"
			else
				record.breadcrumb = wb.Presentation.CategoryLabel(entry.category) .. " > "
					.. wb.Presentation.NavLabel(table.concat({ entry.name, pageLabel, sectionLabel }, " > "))
			end
			record.prerequisite = opt.prerequisite or wb.Presentation.Prerequisite(path, entry.id)
			if path:match("^slots%.") then
				record.hint = "Tracked friendly buffs use aura spell IDs and share the member external aura artwork and its on/off state."
				record.aliases = "my hots heal over time tracked friendly buffs"
			end
			local key = target.id .. "|" .. path
			assert(not model.owners[key], "Duplicate settings destination " .. key)
			model.owners[key] = record
			model.records[#model.records + 1] = record
		end)
	end
	local order = {}
	for index, feature in ipairs(FEATURES) do order["@" .. feature[1]] = index end
	table.sort(model.pages, function(a, b)
		if entry.id == "theme" then
			local themeOrder = { ["@fonts"] = 1, ["@artwork"] = 2, ["@colours"] = 3 }
			return themeOrder[a.id] < themeOrder[b.id]
		end
		local left, right = order[a.id] or 50, order[b.id] or 50
		if left ~= right then return left < right end
		return a.id < b.id
	end)
	for _, page in ipairs(model.pages) do
		if page.id == "@auras" then
			local first = page.sections[1]
			local overview = { id = "@overview", label = "Overview", targetId = first.targetId, scope = first.scope, paths = {} }
			table.insert(page.sections, 1, overview)
			page.byId[overview.id] = overview
		end
		if entry.id == "clickgrid.panel" and page.id == "@states" then
			table.sort(page.sections, function(a, b)
				local left = a.id:match(":(.+)$")
				local right = b.id:match(":(.+)$")
				if left ~= right then return left < right end
				return a.targetId < b.targetId
			end)
		end
	end
	return model
end

function Pages.Validate(entries, index)
	local owners, expected = {}, {}
	for _, entry in ipairs(entries) do
		if entry.settingsTargets then
			local model = assert(index.models[entry.id], "Missing settings model " .. entry.id)
			for _, target in ipairs(entry.settingsTargets()) do
				local storeId = target.storeId or entry.id
				Pages.Walk(target.schema, function(opt, path)
					local key = storeId .. "|" .. path
					expected[key] = true
					if model.exclusions[target.id .. "|" .. path] then owners[key] = owners[key] or "excluded" end
				end)
			end
			for _, record in ipairs(model.records) do
				local key = record.storeId .. "|" .. record.path
				assert(not owners[key], "Duplicate canonical setting " .. key)
				assert(model.byId[record.pageId].byId[record.sectionId], "Missing local section " .. key)
				owners[key] = record
			end
		end
	end
	for key in pairs(expected) do assert(owners[key], "Orphaned setting " .. key) end
	return true
end
