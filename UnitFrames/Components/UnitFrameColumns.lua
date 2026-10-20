local _, ns = ...
local Columns = {}
ns.UnitFrameColumns = Columns

function Columns.Compute(spec, cfg, fillHeight)
	local Layout = ns.UnitFrameLayout
	local left, right, top, bottom = ns.Components.Backdrop.Padding(cfg.border)
	local placement = Layout.CastbarPlacement(spec, cfg)
	local before, after, columns = {}, {}, {}
	local function Extra(list, key, height)
		list[#list + 1] = { key = key, height = height }
	end
	local aura = spec.auraBar and cfg.auraBar.enabled and cfg.auraBar
	if aura then Extra(aura.position == "top" and before or after, "auraBar", aura.height) end
	if placement == "top" or placement == "bottom" then
		Extra(placement == "top" and before or after, "castbar", cfg.castbar.height)
	end
	if Layout.PointBarShown(spec, cfg) then
		Extra(cfg.comboPoints.position == "top" and before or after, "comboPoints", cfg.comboPoints.height)
	end
	local width = 0
	for _, row in ipairs(spec.rows) do
		local config = cfg[row.key]
		if config.enabled then
			if #columns > 0 then width = width + cfg.spacing end
			columns[#columns + 1] = { key = row.key, x = width, width = config.columnWidth }
			width = width + config.columnWidth
		end
	end
	width = math.max(width, 1)
	local extraHeight = 0
	for _, list in ipairs({ before, after }) do
		for _, item in ipairs(list) do extraHeight = extraHeight + item.height + cfg.spacing end
	end
	local height = math.max(cfg.columnHeight, (fillHeight or 0) - top - bottom - extraHeight)
	local portrait
	local portraitWidth = 0
	if spec.portrait and cfg.portrait.enabled and #columns > 0 then
		portraitWidth = cfg.portrait.size > 0 and cfg.portrait.size or height
		portrait = { width = portraitWidth, height = height, side = cfg.portrait.position,
			x = cfg.portrait.position == "LEFT" and left or -right }
		portraitWidth = portraitWidth + cfg.portrait.gap
	end
	local totalWidth = width + left + right + portraitWidth
	local rows, y = {}, top
	local function Append(list)
		for _, item in ipairs(list) do
			item.left, item.right, item.y = left, right, -y
			rows[#rows + 1] = item
			y = y + item.height + cfg.spacing
		end
	end
	Append(before)
	if portrait then portrait.y = -y end
	for _, item in ipairs(columns) do
		item.left = left + item.x + (portrait and portrait.side == "LEFT" and portraitWidth or 0)
		item.right = totalWidth - item.left - item.width
		item.y, item.height = -y, height
		item.x, item.width = nil, nil
		rows[#rows + 1] = item
	end
	y = y + height
	if #after > 0 then y = y + cfg.spacing end
	Append(after)
	if #after > 0 then y = y - cfg.spacing end
	return { width = totalWidth, height = math.max(1, y + bottom), rows = rows, portrait = portrait,
		castbarPlacement = placement, auraBarCollapses = false }
end
