local _, ns = ...
local Skin, Schema, Util = ns.Skin, ns.Schema, ns.Util
local W = ns.Widgets
local Inspector = W.Inspector

local INDENT, ROW_GAP = 10, 6

-- Referred options retain their original ancestors and resolved-group context
-- even when a presentation page moves them elsewhere in navigation.
local function Hidden(schema, resolved, path)
	local group = resolved
	for key in path:gmatch("[^%.]+") do
		local opt = assert(Schema.Find(schema, key), "Inspector: unknown option " .. path)
		if opt.hidden and opt.hidden(group) then return true end
		schema, group = opt.schema, group and group[key]
	end
	return false
end

-- Re-reads all values, re-evaluates `hidden` and lays the rows out again.
function Inspector:Refresh()
	local page = self.page
	if not page then
		return
	end
	local target = page.target
	if not target then return end
	local resolved = target.resolved()
	local width = self.scroll:GetContent():GetWidth()
	local y, hasDetails = 0, false
	for _, row in ipairs(page.rows) do
		local visible = not Hidden(target.schema, resolved, row.path)
		local detail = page.selection and page.selection.details and page.selection.details[row.path]
		if visible and detail and row.control then hasDetails = true end
		if detail and not page.detailsExpanded then visible = false end
		row.visible = visible

		row.region:SetShown(visible)
		if row.reset then
			row.reset:Hide()
		end
		if visible then
			row.y = y
			local x = row.depth * INDENT
			if row.isHeader then
				y = y + 4
			end
			row.region:ClearAllPoints()
			row.region:SetPoint("TOPLEFT", page.frame, "TOPLEFT", x, -y)
			row.region:SetWidth(math.max(width - x - 22, 40))
			if row.control then
				self:UpdateControl(row, target, resolved)
			end
			if row.source then
				local source = target.source and target.source(row.path) or (target.get(row.path) ~= nil and "Custom value" or "Built-in default")
				row.source:SetText(source)
			end
			y = y + row.height + ROW_GAP
		end
	end
	self.empty:SetShown(#page.rows == 0)
	self.scroll:SetContentHeight(y)
	page.contentHeight = y
	if self.onDetailsChanged then self.onDetailsChanged(hasDetails, page.detailsExpanded == true) end
end

function Inspector:ClearReveal()
	if self.highlight then self.highlight:Hide(); self.highlight:SetScript("OnUpdate", nil) end
	self.revealedPath = nil
end

function Inspector:Reveal(path)
	self:ClearReveal()
	local page = self.page
	if not page then return false end
	if page.selection and page.selection.details and page.selection.details[path] then
		page.detailsExpanded = true
		self:Refresh()
	end
	for _, row in ipairs(page.rows) do
		if row.path == path and row.control then
			if not row.visible then return false end
			local extent = math.max(0, page.contentHeight - self.scroll.box:GetHeight())
			self.scroll:SetScrollPercentage(extent > 0 and math.min(1, row.y / extent) or 0)
			local highlight = self.highlight
			if not highlight then
				highlight = CreateFrame("Frame", nil, page.frame, "BackdropTemplate")
				highlight:SetBackdrop({ edgeFile = Skin.WHITE, edgeSize = 1 })
				highlight:SetBackdropBorderColor(unpack(Skin.colors.accent))
				self.highlight = highlight
			end
			highlight:SetParent(page.frame)
			highlight:ClearAllPoints()
			highlight:SetPoint("TOPLEFT", row.region, "TOPLEFT", -2, 2)
			highlight:SetPoint("BOTTOMRIGHT", row.region, "BOTTOMRIGHT", 2, -2)
			highlight:Show()
			local remaining = 3
			highlight:SetScript("OnUpdate", function(_, elapsed)
				remaining = remaining - elapsed
				if remaining <= 0 then self:ClearReveal() end
			end)
			self.revealedPath = path
			return true, row.opt.label or row.opt.key
		end
	end
	return false
end

function Inspector:SetDetails(expanded)
	if not self.page then return end
	self.page.detailsExpanded = expanded
	self:Refresh()
end
