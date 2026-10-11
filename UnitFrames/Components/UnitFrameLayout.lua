local _, ns = ...
local Layout = {}
ns.UnitFrameLayout = Layout

-- Only structural specs and resolved, plain configuration enter this module.
-- Native aura bounds and live fill/roster geometry must never be inputs.
function Layout.CastbarPlacement(spec, cfg)
	if not spec.castbar then return "off" end
	local placement = cfg.castbar.placement
	if placement == "health" and not (cfg.health and cfg.health.enabled) then return "top" end
	return placement
end

function Layout.Compute(spec, cfg)
	local pad = cfg.border.enabled and cfg.border.padding or 0
	local placement = Layout.CastbarPlacement(spec, cfg)
	local items = {}
	if placement == "top" then items[#items + 1] = { key = "castbar", height = cfg.castbar.height } end
	for _, row in ipairs(spec.rows) do
		if cfg[row.key].enabled then items[#items + 1] = { key = row.key, height = cfg[row.key].height } end
	end
	if placement == "bottom" then items[#items + 1] = { key = "castbar", height = cfg.castbar.height } end
	local stackHeight = 0
	for i, item in ipairs(items) do stackHeight = stackHeight + item.height + (i > 1 and cfg.spacing or 0) end

	local left, right, portraitWidth = pad, pad, 0
	local portrait, portraitRows = nil, 0
	if spec.portrait and cfg.portrait.enabled and stackHeight > 0 then
		portraitRows = cfg.portrait.rowSpan == 0 and #items or math.min(cfg.portrait.rowSpan, #items)
		local height = 0
		for i = 1, portraitRows do height = height + items[i].height + (i > 1 and cfg.spacing or 0) end
		local width = cfg.portrait.size > 0 and cfg.portrait.size or height
		local side = cfg.portrait.position
		portrait = { width = width, height = height, side = side, x = side == "LEFT" and pad or -pad, y = -pad }
		portraitWidth = width + cfg.portrait.gap
		if side == "LEFT" then left = left + portraitWidth else right = right + portraitWidth end
	end

	local y = pad
	for i, item in ipairs(items) do
		if i > 1 then y = y + cfg.spacing end
		item.left, item.right, item.y = i <= portraitRows and left or pad, i <= portraitRows and right or pad, -y
		y = y + item.height
	end
	return { width = cfg.width + portraitWidth, height = math.max(stackHeight + 2 * pad, 1),
		rows = items, portrait = portrait, castbarPlacement = placement }
end
