local _, ns = ...
local Skin, Schema, Util = ns.Skin, ns.Schema, ns.Util
local W = ns.Widgets
local Inspector = W.Inspector

function Inspector:BuildPage(target, groupPath)
	local page = {
		frame = CreateFrame("Frame", nil, self.scroll:GetContent()),
		rows = {},
		revision = target.revision,
		groupPath = type(groupPath) ~= "table" and groupPath or nil,
		selection = type(groupPath) == "table" and Util.Copy(groupPath) or nil,
	}
	page.frame:SetAllPoints()
	if type(groupPath) == "table" then
		local previousParent
		for _, path in ipairs(groupPath.paths) do
			local parentPath = path:match("^(.*)%.[^%.]+$")
			local parentOpt = parentPath and Schema.Find(target.schema, parentPath)
			if parentOpt and parentOpt.inline and previousParent ~= parentPath then
				self:AddHeader(page, parentOpt, parentPath, 0)
			end
			previousParent = parentPath
			local opt = assert(Schema.Find(target.schema, path), "Inspector: unknown settings path " .. path)
			if groupPath.labels and groupPath.labels[path] then
				opt = Util.Copy(opt)
				opt.label = groupPath.labels[path]
			end
			if opt.type == "group" then
				self:AddHeader(page, opt, path, 0)
				self:BuildRows(page, opt.schema, path .. ".", 1)
			else
				self:AddControl(page, opt, path, 0)
			end
		end
	elseif groupPath then
		local schema, prefix = target.schema, ""
		if groupPath ~= "" then
			schema, prefix = Schema.Find(target.schema, groupPath).schema, groupPath .. "."
		end
		self:BuildRows(page, schema, prefix, 0, true)
	else
		self:BuildRows(page, target.schema, "", 0)
	end
	return page
end

function Inspector:AddHeader(page, opt, path, depth)
	local header = Skin.FontString(page.frame, "header")
	header:SetJustifyH("LEFT")
	header:SetText(opt.label or opt.key)
	self:AddRow(page, { opt = opt, path = path, depth = depth, region = header, height = 18, isHeader = true })
end

function Inspector:AddControl(page, opt, path, depth)
	local control = self:CreateControl(page, opt, path)
	self:AddRow(page, { opt = opt, path = path, depth = depth, control = control, region = control:GetFrame(),
		height = control:GetHeight() })
	if page.selection and page.selection.sources and opt.type ~= "action" then
		local row = page.rows[#page.rows]
		local source = Skin.FontString(row.region)
		source:SetPoint("TOPLEFT", row.region, "BOTTOMLEFT", 0, -2)
		source:SetPoint("TOPRIGHT", row.region, "BOTTOMRIGHT", 0, -2)
		source:SetJustifyH("LEFT")
		source:SetTextColor(unpack(Skin.colors.textDim))
		row.source, row.height = source, row.height + 18
		if opt.inherit then
			local link = W.Button:New(row.region, { text = "Edit shared default", onClick = function()
				if page.target and self.onInherited then self.onInherited(opt.inherit) end
			end })
			link:SetPoint("TOPRIGHT", row.region, "BOTTOMRIGHT", 0, -2)
			link:SetWidth(120)
			link:GetFrame():SetHeight(16)
			row.sourceLink = link
			source:SetPoint("TOPRIGHT", row.region, "BOTTOMRIGHT", -124, -2)
		end
	end
	if opt.hint then
		local hint = Skin.FontString(page.frame)
		hint:SetJustifyH("LEFT")
		hint:SetWordWrap(true)
		hint:SetTextColor(unpack(Skin.colors.textDim))
		hint:SetText(opt.hint)
		hint:SetHeight(36)
		self:AddRow(page, { opt = opt, path = path, depth = depth, region = hint, height = 36, isHint = true })
	end
end

-- flat: skip sub-groups (they are separate sections) unless they are inline.
function Inspector:BuildRows(page, schema, prefix, depth, flat)
	for _, opt in ipairs(schema) do
		local path = prefix .. opt.key
		if opt.type == "group" then
			if flat and opt.inline then
				self:AddHeader(page, opt, path, depth)
				self:BuildRows(page, opt.schema, path .. ".", depth + 1, true)
			elseif not flat then
				self:AddHeader(page, opt, path, depth)
				self:BuildRows(page, opt.schema, path .. ".", depth + 1)
			end
		else
			self:AddControl(page, opt, path, depth)
		end
	end
end

function Inspector:AddRow(page, row)
	if row.control and row.opt.type ~= "action" then
		local reset = CreateFrame("Button", nil, page.frame)
		reset:SetSize(14, 14)
		reset:SetNormalTexture([[Interface\Buttons\UI-RefreshButton]])
		reset:SetScript("OnClick", function()
			if not page.target then return end
			page.target.set(row.path, nil)
			self:Refresh()
		end)
		ns.Widget.AttachTooltip(reset, "Use inherited/default value", "Restore the effective inherited or default value.")
		reset:SetScript("OnEnter", function()
			if not page.target then return end
			local source, value
			if page.target.source then source, value = page.target.source(row.path, true) end
			local label = type(value) == "table" and "configured colour" or tostring(value)
			GameTooltip:SetOwner(reset, "ANCHOR_RIGHT")
			GameTooltip:SetText("Use inherited/default value", 1, 1, 1)
			GameTooltip:AddLine((source or "Built-in default") .. ": " .. label, nil, nil, nil, true)
			GameTooltip:Show()
		end)
		row.reset = reset
	end
	page.rows[#page.rows + 1] = row
end
