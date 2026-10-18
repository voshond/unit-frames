local _, wb = ...
local Workbench, Pages = wb.Workbench, wb.Pages
local Catalogue = {}
wb.Catalogue = Catalogue

local SYNONYMS = {
	{ "shield", "shields", "absorb", "barrier" }, { "buff", "buffs", "aura", "auras", "hots", "hot" },
	{ "colour", "color" }, { "opacity", "transparency" }, { "castbar", "cast bar" },
	{ "cc", "crowd control" }, { "gcd", "global cooldown" }, { "percent", "percentage", "%" },
	{ "clickgrid", "party", "raid" }, { "spark", "fill edge highlight" },
}

local function Normalise(value)
	return tostring(value or ""):lower():gsub("%%", " percent "):gsub("[%p%s]+", " "):match("^%s*(.-)%s*$")
end
Catalogue.Normalise = Normalise

local function Fields(record)
	local opt, choices = record.opt or {}, {}
	local values = opt.searchValues or opt.values
	if type(values) == "table" then
		for _, choice in ipairs(values) do choices[#choices + 1] = tostring(choice[2]) end
	end
	return { Normalise(record.label), Normalise(record.breadcrumb),
		Normalise((record.aliases or "") .. " " .. (record.ancestry or "") .. " " .. table.concat(choices, " ")),
		Normalise((opt.tooltip or "") .. " " .. (opt.hint or "") .. " " .. (record.hint or "")) }
end

function Catalogue.Build(entries)
	local index = { records = {}, models = {} }
	for _, entry in ipairs(entries) do
		if entry.settingsTargets then
			local model = Pages.Build(entry, entry.settingsTargets())
			index.models[entry.id] = model
			for _, record in ipairs(model.records) do
				record.group = "settings"
				index.records[#index.records + 1] = record
			end
		end
		if not entry.settingsTargets then
			index.records[#index.records + 1] = { entryId = entry.id, label = entry.name, group = "developer",
				breadcrumb = "Developer tools > " .. entry.category .. " > " .. entry.name, scope = "Developer tools" }
		end
		for _, destination in ipairs(entry.destinations or {}) do
			local record = UnitFrames.Util.Copy(destination)
			record.entryId, record.group = entry.id, record.group or "settings"
			record.scope = record.scope or entry.scope or entry.name
			record.breadcrumb = entry.category .. " > " .. entry.name .. " > " .. record.label
			index.records[#index.records + 1] = record
		end
		if entry.data then
			Pages.Walk(entry.data.schema, function(opt, path, labels)
				index.records[#index.records + 1] = { entryId = entry.id, targetId = "preview", path = path,
					pageId = "@data", opt = opt, label = opt.label or opt.key, ancestry = table.concat(labels, " "),
					breadcrumb = entry.name .. " > Preview only", scope = "Preview only", group = entry.settingsTargets and "preview" or "developer" }
			end)
		end
	end
	for ordinal, record in ipairs(index.records) do
		record.ordinal, record.fields = ordinal, Fields(record)
	end
	Pages.Validate(entries, index)
	return index
end

local function Alternatives(token)
	for _, group in ipairs(SYNONYMS) do
		for _, word in ipairs(group) do
			if token == word then return group end
		end
	end
	return { token }
end

function Catalogue.Query(index, query, options)
	options = options or {}
	query = Normalise(query)
	if query == "" then return {} end
	local results = {}
	for _, record in ipairs(index.records) do
		local allowed = (record.group ~= "preview" or options.preview) and (record.group ~= "developer" or options.developer)
		allowed = allowed and (not options.entryId or record.entryId == options.entryId)
		allowed = allowed and (not options.pageId or record.pageId == options.pageId)
		local score, matched = 0, allowed
		if allowed then
			for token in query:gmatch("%S+") do
				local best
				for _, alternative in ipairs(Alternatives(token)) do
					for field, value in ipairs(record.fields) do
						if value:find(alternative, 1, true) then best = math.min(best or 10, field) end
					end
				end
				if not best then matched = false; break end
				score = score + best
			end
		end
		if matched then
			if record.fields[1] == query then score = score - 20
			elseif record.fields[1]:sub(1, #query) == query then score = score - 10 end
			if query:find(" ", 1, true) and record.aliases and Normalise(record.aliases):find(query, 1, true) then score = score - 12 end
			results[#results + 1] = { record = record, score = score }
		end
	end
	table.sort(results, function(a, b)
		if a.record.group ~= b.record.group then
			if a.record.group == "settings" then return true end
			if b.record.group == "settings" then return false end
		end
		if a.score ~= b.score then return a.score < b.score end
		local left, right = a.record.entryId == options.currentEntry, b.record.entryId == options.currentEntry
		if left ~= right then return left end
		return a.record.ordinal < b.record.ordinal
	end)
	return results
end

function Workbench:GetCatalogue()
	if not self.catalogue then self.catalogue = Catalogue.Build(self.order) end
	return self.catalogue
end

function Workbench:FindSettings(query, options)
	return Catalogue.Query(self:GetCatalogue(), query, options)
end

function Workbench:ValidateCatalogue()
	return Pages.Validate(self.order, self:GetCatalogue())
end
