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

function Layout.Compute(cfg, member, target)
	local cellWidth = member.width + (cfg.targets and target.width + cfg.targetGap or 0)
	local cellHeight = math.max(member.height, cfg.targets and target.height or 0)
	local cols = cfg.mode == "subgroups" and math.min(8, cfg.columns) or cfg.columns
	local result = { cellWidth = cellWidth, cellHeight = cellHeight, sections = {} }
	local party = Layout.Grid(1, 5, cellWidth, cellHeight, cfg.spacingX, cfg.spacingY)
	result.party = { width = party.width + 2 * cfg.padding, height = party.height + Layout.LABEL + 2 * cfg.padding }
	result.solo = { width = cellWidth + 2 * cfg.padding, height = cellHeight + Layout.LABEL + 2 * cfg.padding }
	local y, width = cfg.padding + Layout.LABEL, 0
	if cfg.tanks then
		local tankCols = math.min(cols, cfg.tankSlots)
		local tankRows = math.ceil(cfg.tankSlots / tankCols)
		local grid = Layout.Grid(tankCols, tankRows, cellWidth, cellHeight, cfg.spacingX, cfg.spacingY)
		result.sections.tanks = { x = cfg.padding, y = y, grid = grid }
		y, width = y + grid.height + cfg.sectionGap + Layout.LABEL, grid.width
	end
	if cfg.mode == "flat" then
		assert(cfg.columns * cfg.rows >= 40, "Raid capacity must cover all 40 members")
		local grid = Layout.Grid(cols, cfg.rows, cellWidth, cellHeight, cfg.spacingX, cfg.spacingY)
		result.sections.raid = { x = cfg.padding, y = y, grid = grid }
		y, width = y + grid.height, math.max(width, grid.width)
	else
		local block = Layout.Grid(1, 5, cellWidth, cellHeight, cfg.spacingX, cfg.spacingY)
		local blockRows = math.ceil(8 / cols)
		for group = 1, 8 do
			local column, row = (group - 1) % cols, math.floor((group - 1) / cols)
			result.sections["group" .. group] = { x = cfg.padding + column * (block.width + cfg.spacingX),
				y = y + row * (block.height + cfg.sectionGap + Layout.LABEL), grid = block }
		end
		y = y + blockRows * block.height + (blockRows - 1) * (cfg.sectionGap + Layout.LABEL)
		width = math.max(width, cols * block.width + (cols - 1) * cfg.spacingX)
	end
	result.raid = { width = width + 2 * cfg.padding, height = y + cfg.padding }
	result.sections.party = { x = cfg.padding, y = cfg.padding + Layout.LABEL, grid = party }
	return result
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
