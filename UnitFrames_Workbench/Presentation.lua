local _, wb = ...
local Presentation = {}
wb.Presentation = Presentation

function Presentation.NavLabel(label)
	return (label:gsub("%a[%w']*", function(word) return word:sub(1, 1):upper() .. word:sub(2) end))
end

function Presentation.CategoryLabel(category)
	local labels = { ["Shared appearance"] = "Global Settings", ["Party & raid (ClickGrid)"] = "Party & Raid" }
	return labels[category] or Presentation.NavLabel(category)
end

function Presentation.Prerequisite(path, entryId)
	if entryId == "profiles" and (path == "reset" or path == "delete" or path == "deleteName") then
		return { path = "unlocked", message = "Enable Allow delete and reset to reveal this action. Deleting also requires another profile." }
	end
	local reaction, field = path:match("^(%w+)%.(%w+)$")
	if (reaction == "friendly" or reaction == "hostile") and (field == "spell" or field == "macro") then
		return { path = reaction .. ".action", message = "Choose the matching spell or macro action before editing its value. This edits the selected mouse button and modifier in the current specialization." }
	end
	local slot = path:match("^(.-)%.piece%d+%.")
	if slot then return { path = slot .. ".format", message = "Choose Custom in the text content selector to edit individual pieces. Some piece options also depend on their selected source." } end
	if path:match("%.whileCasting$") then
		return { path = path:gsub("whileCasting$", "format"), message = "Choose Custom in the text content selector to edit casting behaviour." }
	end
	if path:match("%.whileStatus$") then
		return { path = path:gsub("whileStatus$", "format"), message = "Choose Custom in the text content selector to edit dead and offline behaviour." }
	end
	if path:match("%.levelColor$") then
		return { path = path:gsub("levelColor$", "format"), message = "Choose a text that shows the level to colour it by difficulty." }
	end
	if path:match("%.threatColor$") then
		return { path = path:gsub("threatColor$", "format"), message = "Choose a text that shows Threat % to colour it by stage." }
	end
	local background = path:match("^(.-%.background)%.")
	if background and path:match("%.color$") then
		return { path = background .. ".useBarColor", message = "Turn off Tint with bar colour to choose a separate background colour." }
	end
	if background and path:match("%.alpha$") then
		return { path = background .. ".useBarColor", message = "Turn on Tint with bar colour to adjust its opacity." }
	end
	if path == "castbar.portraitLayout" then
		return { path = "castbar.placement", message = "Place the cast bar over the portrait to choose its portrait layout." }
	end
	if path:match("^indicators%.private") then
		return { path = "indicators.private", message = "Enable Private encounter auras. This display also requires client support for private auras." }
	end
end

function Presentation.Hint(pageId, section)
	if pageId == "@layout" then return "Move frames through the game's Edit Mode. Style changes apply immediately." end
	if pageId == "@health" and section.id:match(":shields$") then
		return "Overlay health draws inward from the end. After health reserves space after the fill, even at full health. Text uses actual maximum health."
	end
	if pageId == "@power" then return "The resource shown depends on the unit." end
	if pageId == "@castbar" then return "This frame's cast bar is independent of Cast bar & swing timers." end
	if pageId == "@comboPoints" then return "Combo points are available for rogues and druids. Target frames show points on your current target." end
	if pageId == "@states" then return "Resting text uses a text-slot preset. For Offline / dead text, choose Custom and select that piece source." end
	if pageId == "@auras" then
		if section.id:find(":slots", 1, true) then return "Pin friendly buff spell IDs to fixed positions. Slots share member external aura artwork, including its on/off state." end
		if section.id:match(":auraBar$") then return "Cropped icons inside a frame row. Can be used alongside external and priority icons." end
		if section.id:match(":categoryAuras$") then return "Crowd control, defensive abilities and important buffs. The highest enabled priority covers overlapping icons." end
		return "External icons, an embedded row and priority icons are independent displays and can be used together."
	end
	if pageId == "@fonts" or pageId == "@artwork" or pageId == "@colours" then
		return "Defaults for settings that inherit them. Frame defaults and custom overrides can take precedence."
	end
end

function Presentation.Links(catalogue, entryId, page, section)
	local links, model = {}, catalogue.models[entryId]
	local function Add(label, path, destinationEntry)
		local destination = catalogue.models[destinationEntry or entryId]
		local record = destination and destination.owners[(section.targetId or "style") .. "|" .. path]
		if record then links[#links + 1] = { label = label, record = record } end
	end
	if page.id == "@castbar" and entryId:match("^unit%.") then
		Add("Standalone Player Cast Bar", "castbar.enabled", "timers")
	elseif page.id == "@portrait" then
		Add("Cast Bar Covering the Portrait", "castbar.placement")
		local auraModel = entryId == "clickgrid.member" and catalogue.models["clickgrid.panel"] or model
		for _, record in ipairs(auraModel.records) do
			if record.storeId == entryId and record.path:match("^categoryAuras%..*anchor$") then
				links[#links + 1] = { label = "Priority Icons — " .. record.label, record = record }
			end
		end
	elseif page.id == "@states" then
		local textModel = entryId == "clickgrid.panel" and catalogue.models["clickgrid.member"] or model
		for _, record in ipairs(textModel.records) do
			if record.path:match("%.format$") then
				local source = textModel.owners[record.targetId .. "|" .. record.path:gsub("%.format$", ".piece1.source")]
				for _, choice in ipairs(source and UnitFrames.Schema.GetValues(source.opt) or {}) do
					if choice[1] == "resting" or (not section.id:match(":resting$") and choice[1] == "status") then
						links[#links + 1] = { label = record.label, record = record }
						break
					end
				end
			end
		end
	elseif page.id == "@auras" and section.id == "@overview" then
		for _, item in ipairs(page.sections) do
			local record = model.owners[item.targetId .. "|" .. (item.paths[1] or "")]
			if record then links[#links + 1] = { label = Presentation.NavLabel(item.label), record = record } end
		end
	end
	return links
end
