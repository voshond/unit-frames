local _, ns = ...
local Layout = {}
ns.UnitFrameLayout = Layout

-- Only structural specs and resolved, plain configuration enter this module.
-- Native aura bounds and live fill/roster geometry must never be inputs.
function Layout.CastbarPlacement(spec, cfg)
	if not spec.castbar or not cfg.castbar.enabled then return "off" end
	local placement = cfg.castbar.placement
	if placement == "health" and not (cfg.health and cfg.health.enabled) then return "top" end
	return placement
end

-- Whether the icon row lends its space (and the gap) to the health bar
-- while no icon is shown. The unit must offer it and show both rows.
function Layout.AuraBarCollapses(spec, cfg)
	return spec.auraBar ~= nil and spec.auraBar.collapsible == true and cfg.auraBar.enabled
		and cfg.auraBar.collapse == true and cfg.health ~= nil and cfg.health.enabled
end

-- Whether the combo point row takes space: the unit must offer it to a
-- class that has combo points (spec, fixed for the frame) and enable it.
function Layout.PointBarShown(spec, cfg)
	return spec.comboPoints ~= nil and spec.comboPoints.available ~= false and cfg.comboPoints.enabled
end

function Layout.Compute(spec, cfg)
	local padLeft, padRight, padTop, padBottom = ns.Components.Backdrop.Padding(cfg.border)
	local placement = Layout.CastbarPlacement(spec, cfg)
	local items = {}
	local auraBar = spec.auraBar and cfg.auraBar.enabled and cfg.auraBar
	local collapse = Layout.AuraBarCollapses(spec, cfg)
	local auraItem = auraBar and { key = "auraBar", height = auraBar.height }
	-- A collapsing row sits beside health, so no other row has to move.
	local function AuraBarAt(position, beside)
		if auraBar and auraBar.position == position and (beside == "health") == collapse then items[#items + 1] = auraItem end
	end
	local points = Layout.PointBarShown(spec, cfg) and cfg.comboPoints
	-- "power" follows the power row, enabled or not; without one, the rows.
	local pointsPending = points and points.position
	local function PointsAt(position)
		if pointsPending == position then
			items[#items + 1] = { key = "comboPoints", height = points.height }
			pointsPending = nil
		end
	end
	AuraBarAt("top")
	if placement == "top" then items[#items + 1] = { key = "castbar", height = cfg.castbar.height } end
	PointsAt("top")
	for _, row in ipairs(spec.rows) do
		if cfg[row.key].enabled then
			if row.key == "health" then AuraBarAt("top", "health") end
			items[#items + 1] = { key = row.key, height = cfg[row.key].height }
			if row.key == "health" then AuraBarAt("bottom", "health") end
		end
		if row.key == "power" then PointsAt("power") end
	end
	PointsAt("power")
	PointsAt("bottom")
	if placement == "bottom" then items[#items + 1] = { key = "castbar", height = cfg.castbar.height } end
	AuraBarAt("bottom")
	local stackHeight = 0
	for i, item in ipairs(items) do stackHeight = stackHeight + item.height + (i > 1 and cfg.spacing or 0) end

	local left, right, portraitWidth = padLeft, padRight, 0
	local portrait, portraitRows = nil, 0
	if spec.portrait and cfg.portrait.enabled and stackHeight > 0 then
		portraitRows = cfg.portrait.rowSpan == 0 and #items or math.min(cfg.portrait.rowSpan, #items)
		local height = 0
		for i = 1, portraitRows do height = height + items[i].height + (i > 1 and cfg.spacing or 0) end
		local width = cfg.portrait.size > 0 and cfg.portrait.size or height
		local side = cfg.portrait.position
		portrait = { width = width, height = height, side = side, x = side == "LEFT" and padLeft or -padRight, y = -padTop }
		portraitWidth = width + cfg.portrait.gap
		if side == "LEFT" then left = left + portraitWidth else right = right + portraitWidth end
	end

	local y = padTop
	for i, item in ipairs(items) do
		if i > 1 then y = y + cfg.spacing end
		item.left, item.right, item.y = i <= portraitRows and left or padLeft, i <= portraitRows and right or padRight, -y
		y = y + item.height
	end
	return { width = cfg.width + portraitWidth, height = math.max(stackHeight + padTop + padBottom, 1),
		rows = items, portrait = portrait, castbarPlacement = placement, auraBarCollapses = collapse }
end
