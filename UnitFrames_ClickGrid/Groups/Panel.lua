local _, CG = ...

function CG:LayoutPanel()
	CG.UF.Perf:Count("clickgridPanelLayout")
	self:Measure()
	local cfg = self.Config:Resolved()
	self:EnsureHeaders(cfg.panel)
	local layout = self.Layout.Compute(cfg.panel, self.metrics.member, self.metrics.target, cfg.titles, cfg.border)
	self.layout, self.activeHeaders, self.panelConfig = layout, {}, cfg.panel
	self.panel:SetScale(cfg.panel.scale)
	for _, state in ipairs({ "party", "raid", "solo" }) do
		self.panel:SetAttribute(state .. "-width", layout[state].width)
		self.panel:SetAttribute(state .. "-height", layout[state].height)
	end
	for count = 2, 5 do
		self.panel:SetAttribute("party" .. count .. "-width", layout.partySizes[count].width)
		self.panel:SetAttribute("party" .. count .. "-height", layout.partySizes[count].height)
	end
	local size = IsInRaid() and layout.raid or IsInGroup()
		and layout.partySizes[math.max(2, math.min(5, GetNumGroupMembers()))] or layout.solo
	self.panel:SetSize(size.width, size.height)
	RegisterStateDriver(self.panel, "roster", "[group:raid] raid; [@party4,exists] party5; [@party3,exists] party4; [@party2,exists] party3; [group:party] party2; solo")
	RegisterAttributeDriver(self.panel, "state-visibility", not cfg.panel.enabled and "hide"
		or cfg.panel.showSolo and "show" or "[group] show; hide")
	self.Layout.Backdrop(self.background, self.panel, cfg.titles, cfg.border)
	for key, header in pairs(self.headers) do
		local section = layout.sections[key]
		local visible = section ~= nil
		self.activeHeaders[header] = visible
		if key ~= "party" and not visible then header:SetAttribute("showRaid", false) end
		local titles = self:GetHeaderTitles(header)
		for _, label in ipairs(titles.columns) do label:Hide() end
		if section then
			if key == "raid" then
				titles.label:Hide()
				for column = 1, section.grid.columns do
					local label = titles.columns[column]
					if not label then
						label = header:CreateFontString(nil, "OVERLAY")
						titles.columns[column] = label
					end
					self.Layout.TitleOnHeader(label, header, "group" .. column,
						{ grid = { width = layout.cellWidth } }, cfg.titles, layout.titlePadding,
						(column - 1) * (layout.cellWidth + cfg.panel.spacingX))
				end
			else self.Layout.TitleOnHeader(titles.label, header, key, section, cfg.titles, layout.titlePadding) end
			header:ClearAllPoints()
			header:SetPoint("TOPLEFT", self.panel, "TOPLEFT", section.x, -section.y)
			header:SetAttribute("_ignore", true)
			for attribute, value in pairs(self.Layout.Attributes(section.grid, cfg.panel)) do header:SetAttribute(attribute, value) end
			header:SetAttribute("_ignore", nil)
		else titles.label:Hide() end
		if key == "party" then
			header:SetAttribute("showSolo", cfg.panel.showSolo)
			header:SetVisibility("custom [group:raid] hide; " .. (cfg.panel.showSolo and "show" or "[group:party] show; hide"))
		else header:SetVisibility(visible and "custom [group:raid] show; hide" or "custom hide") end
	end
end
