local _, CG = ...
local Layout = {}
CG.Layout = Layout
Layout.LABEL = 18

function Layout.Grid(columns, rows, width, height, gapX, gapY)
	return { columns = columns, rows = rows,
		width = columns * width + (columns - 1) * gapX,
		height = rows * height + (rows - 1) * gapY }
end

function Layout.Cell(index, columns, rows, flow, width, height, gapX, gapY)
	local column, row
	if flow == "down" then column, row = math.floor((index - 1) / rows), (index - 1) % rows
	else column, row = (index - 1) % columns, math.floor((index - 1) / columns) end
	return column * (width + gapX), row * (height + gapY)
end

function Layout.TitleHeight(titles)
	if not titles then return Layout.LABEL end
	return titles.enabled and (titles.size + titles.gap + 2) or 0
end

function Layout.Compute(cfg, member, target, titles, border, raidCount, partyCount)
	local left, right, top, bottom = CG.UF.Components.Backdrop.Padding(border)
	local titleHeight = Layout.TitleHeight(titles)
	local below = titles and titles.position == "below"
	local leading, trailing = below and 0 or titleHeight, below and titleHeight or 0
	local cellWidth = member.width + (cfg.targets and target.width + cfg.targetGap or 0)
	local cellHeight = math.max(member.height, cfg.targets and target.height or 0)
	local cols = cfg.mode == "subgroups" and math.min(8, cfg.columns) or cfg.columns
	local result = { cellWidth = cellWidth, cellHeight = cellHeight, sections = {}, partySizes = {},
		titlePadding = below and bottom or top }
	for count = 1, 5 do
		local grid = Layout.Grid(1, count, cellWidth, cellHeight, cfg.spacingX, cfg.spacingY)
		result.partySizes[count] = { width = grid.width + left + right,
			height = grid.height + titleHeight + top + bottom }
	end
	partyCount = math.max(1, math.min(5, partyCount or 5))
	local party = Layout.Grid(1, partyCount, cellWidth, cellHeight, cfg.spacingX, cfg.spacingY)
	result.party = result.partySizes[partyCount]
	result.solo = result.partySizes[1]
	local y, width = top + leading, 0
	if cfg.tanks then
		local tankCols = math.min(cols, cfg.tankSlots)
		local tankRows = math.ceil(cfg.tankSlots / tankCols)
		local grid = Layout.Grid(tankCols, tankRows, cellWidth, cellHeight, cfg.spacingX, cfg.spacingY)
		result.sections.tanks = { x = left, y = y, grid = grid }
		y, width = y + grid.height + cfg.sectionGap + titleHeight, grid.width
	end
	if cfg.mode == "flat" then
		-- Preserve the user's wrap axis and saved preferences. Runtime reserves
		-- all 40 slots before combat; previews need only their plain roster count.
		local columns, rows = cols, cfg.rows
		if cfg.flow == "down" then columns = math.max(columns, math.ceil((raidCount or 40) / rows))
		else rows = math.max(rows, math.ceil((raidCount or 40) / columns)) end
		local grid = Layout.Grid(columns, rows, cellWidth, cellHeight, cfg.spacingX, cfg.spacingY)
		result.sections.raid = { x = left, y = y, grid = grid }
		y, width = y + grid.height, math.max(width, grid.width)
	else
		local block = Layout.Grid(1, 5, cellWidth, cellHeight, cfg.spacingX, cfg.spacingY)
		local blockRows = math.ceil(8 / cols)
		for group = 1, 8 do
			local column, row = (group - 1) % cols, math.floor((group - 1) / cols)
			result.sections["group" .. group] = { x = left + column * (block.width + cfg.spacingX),
				y = y + row * (block.height + cfg.sectionGap + titleHeight), grid = block }
		end
		y = y + blockRows * block.height + (blockRows - 1) * (cfg.sectionGap + titleHeight)
		width = math.max(width, cols * block.width + (cols - 1) * cfg.spacingX)
	end
	result.raid = { width = width + left + right, height = y + bottom + trailing }
	result.sections.party = { x = left, y = top + leading, grid = party }
	return result
end

-- Shared rendering for real secure headers and ordinary sample previews.
-- Native header anchors follow roster bounds without reading their geometry.
function Layout.StyleTitle(label, key, cfg)
	local UF = CG.UF
	UF.Media:ApplyFont(label, cfg.font, cfg.size, cfg.outline)
	label:SetTextColor(UF.Util.UnpackColor(cfg.color))
	label:SetJustifyH(cfg.alignment)
	label:SetWordWrap(false)
	label:SetShadowColor(0, 0, 0, cfg.shadow and 1 or 0)
	label:SetShadowOffset(cfg.shadow and 1 or 0, cfg.shadow and -1 or 0)
	label:SetHeight(cfg.size + 2)
	label:SetText(cfg[key] or ("Group " .. (key:match("%d+") or "")))
	label:SetShown(cfg.enabled)
end

function Layout.TitleOnHeader(label, header, key, section, cfg, padding, x)
	Layout.StyleTitle(label, key, cfg)
	label:SetWidth(section.grid.width)
	label:ClearAllPoints()
	if cfg.position == "below" then label:SetPoint("TOPLEFT", header, "BOTTOMLEFT", (x or 0) + cfg.offsetX, -cfg.gap - (padding or 0) + cfg.offsetY)
	else label:SetPoint("BOTTOMLEFT", header, "TOPLEFT", (x or 0) + cfg.offsetX, cfg.gap + (padding or 0) + cfg.offsetY) end
end

function Layout.TitleInPreview(label, parent, key, section, cfg, contentHeight, padding)
	Layout.StyleTitle(label, key, cfg)
	label:SetWidth(section.grid.width)
	label:ClearAllPoints()
	if cfg.position == "below" then
		label:SetPoint("TOPLEFT", parent, "TOPLEFT", section.x + cfg.offsetX, -section.y - contentHeight - cfg.gap - (padding or 0) + cfg.offsetY)
	else label:SetPoint("BOTTOMLEFT", parent, "TOPLEFT", section.x + cfg.offsetX, -section.y + cfg.gap + (padding or 0) + cfg.offsetY) end
end

-- Keep one enclosing backdrop, but exclude the title band from its artwork.
-- Use configured geometry only, never native aura/header size arithmetic.
function Layout.Backdrop(frame, parent, titles, border)
	local height = Layout.TitleHeight(titles)
	frame:ClearAllPoints()
	frame:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, titles.position == "below" and 0 or -height)
	frame:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, titles.position == "below" and height or 0)
	CG.UF.Components.Backdrop.ApplyTo(frame, border)
	local Backdrop = CG.UF.Components.Backdrop
	Backdrop.SetBorderLevel(frame, parent:GetFrameLevel() + Backdrop.LEVELS.panel)
end

function Layout.Attributes(grid, cfg)
	local down = cfg.flow == "down"
	return {
		point = down and "TOP" or "LEFT", xOffset = down and 0 or cfg.spacingX,
		yOffset = down and -cfg.spacingY or 0,
		unitsPerColumn = down and grid.rows or grid.columns,
		maxColumns = down and grid.columns or grid.rows,
		columnAnchorPoint = down and "LEFT" or "TOP",
		columnSpacing = down and cfg.spacingX or cfg.spacingY,
	}
end
