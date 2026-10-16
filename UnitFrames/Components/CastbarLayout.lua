local _, ns = ...
local Layout = {}
ns.CastbarLayout = Layout

-- Only ordinary host dimensions and resolved configuration enter this module.
-- Relative anchor descriptions retain native sizing; no fill geometry is read.
-- maxHeight: the tallest a native-following host can grow; the square icon
-- covers it, so the icon frame only ever clips.
function Layout.Compute(width, height, cfg, portrait, maxHeight)
	local left, rightPad, top, bottom = ns.Components.Backdrop.Padding(cfg.border)
	local w, h = math.max(width - left - rightPad, 1), math.max(height - top - bottom, 1)
	local icon, points
	if cfg.icon.enabled and (not portrait or cfg.portraitLayout ~= "bar") then
		local split = portrait and cfg.portraitLayout == "split"
		local stack = portrait and cfg.portraitLayout == "stack"
		local iw = stack and w or split and math.max((w - cfg.icon.gap) / 2, 1) or h
		local ih = stack and math.max((h - cfg.icon.gap) / 2, 1) or h
		local right = not stack and cfg.icon.position == "RIGHT"
		local point = right and "TOPRIGHT" or "TOPLEFT"
		icon = { width = iw, height = ih, side = math.max(iw, ih, (maxHeight or 0) - top - bottom), point = point, x = right and -rightPad or left, y = -top,
			bottom = bottom }
		if stack then
			points = { { "TOPLEFT", "icon", "BOTTOMLEFT", 0, -cfg.icon.gap },
				{ "BOTTOMRIGHT", "frame", "BOTTOMRIGHT", -rightPad, bottom } }
		elseif right then
			points = { { "TOPLEFT", "frame", "TOPLEFT", left, -top },
				{ "BOTTOMRIGHT", "icon", "BOTTOMLEFT", -cfg.icon.gap, 0 } }
		else
			points = { { "TOPLEFT", "icon", "TOPRIGHT", cfg.icon.gap, 0 },
				{ "BOTTOMRIGHT", "frame", "BOTTOMRIGHT", -rightPad, bottom } }
		end
	else
		points = { { "TOPLEFT", "frame", "TOPLEFT", left, -top },
			{ "BOTTOMRIGHT", "frame", "BOTTOMRIGHT", -rightPad, bottom } }
	end
	return { icon = icon, bar = points }
end
