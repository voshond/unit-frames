local _, CG = ...
local Layout = CG.Layout

function CG.PetLayout(layout, cfg, pet, count, raid, partyCount, titles, border)
	if pet.mode ~= "group" then return layout end
	local left, right, top, bottom = CG.UF.Components.Backdrop.Padding(border)
	local titleHeight = Layout.TitleHeight(titles)
	local columns = math.min(cfg.columns, 40)
	local rows = math.ceil(40 / columns)
	local capacity = Layout.Grid(columns, rows, pet.width, pet.height, cfg.spacingX, cfg.spacingY)
	local filledColumns, filledRows
	if cfg.flow == "down" then
		filledColumns, filledRows = math.ceil(math.max(1, count) / rows), math.min(rows, math.max(1, count))
	else
		filledColumns, filledRows = math.min(columns, math.max(1, count)), math.ceil(math.max(1, count) / columns)
	end
	local grid = Layout.Grid(filledColumns, filledRows, pet.width, pet.height, cfg.spacingX, cfg.spacingY)
	local size = raid and layout.raid or layout.partySizes[math.max(1, math.min(5, partyCount))]
	local section = { x = left, y = size.height - bottom + cfg.sectionGap + (titles.position == "below" and 0 or titleHeight),
		grid = grid, capacity = capacity, parked = count == 0 }
	local function Offset(bounds)
		return bounds.height - bottom + cfg.sectionGap + (titles.position == "below" and 0 or titleHeight)
	end
	layout.petOffsets = { raid = Offset(layout.raid), solo = Offset(layout.solo) }
	for members = 2, 5 do layout.petOffsets["party" .. members] = Offset(layout.partySizes[members]) end
	layout.sections.pets = section
	local parked = 0
	local parkedY = section.y + capacity.height + cfg.sectionGap + titleHeight
	for group = 1, 8 do
		local block = layout.sections["group" .. group]
		if block and block.parked then
			local column, row = parked % cfg.columns, math.floor(parked / cfg.columns)
			block.x = left + column * (block.grid.width + cfg.spacingX)
			block.y = parkedY + row * (block.grid.height + cfg.sectionGap + titleHeight)
			parked = parked + 1
		end
	end
	if count == 0 then return layout end
	local function Grow(bounds)
		bounds.width = math.max(bounds.width, grid.width + left + right)
		bounds.height = bounds.height + cfg.sectionGap + titleHeight + grid.height
	end
	Grow(layout.raid)
	for _, bounds in ipairs(layout.partySizes) do Grow(bounds) end
	return layout
end
