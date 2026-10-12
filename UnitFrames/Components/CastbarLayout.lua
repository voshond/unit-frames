local _, ns = ...
local Layout = {}
ns.CastbarLayout = Layout

-- Only ordinary host dimensions and resolved configuration enter this module.
-- Relative anchor descriptions retain native sizing; no fill geometry is read.
function Layout.Compute(width, height, cfg, portrait)
	local pad = cfg.border.enabled and cfg.border.padding or 0
	local w, h = math.max(width - 2 * pad, 1), math.max(height - 2 * pad, 1)
	local icon, points
	if cfg.icon.enabled and (not portrait or cfg.portraitLayout ~= "bar") then
		local split = portrait and cfg.portraitLayout == "split"
		local stack = portrait and cfg.portraitLayout == "stack"
		local iw = stack and w or split and math.max((w - cfg.icon.gap) / 2, 1) or h
		local ih = stack and math.max((h - cfg.icon.gap) / 2, 1) or h
		local right = not stack and cfg.icon.position == "RIGHT"
		local point = right and "TOPRIGHT" or "TOPLEFT"
		local x, y = 0.42, 0.42
		if portrait then x, y = x * math.min(iw / ih, 1), y * math.min(ih / iw, 1) end
		icon = { width = iw, height = ih, point = point, x = right and -pad or pad, y = -pad,
			crop = { 0.5 - x, 0.5 + x, 0.5 - y, 0.5 + y } }
		if stack then
			points = { { "TOPLEFT", "icon", "BOTTOMLEFT", 0, -cfg.icon.gap },
				{ "BOTTOMRIGHT", "frame", "BOTTOMRIGHT", -pad, pad } }
		elseif right then
			points = { { "TOPLEFT", "frame", "TOPLEFT", pad, -pad },
				{ "BOTTOMRIGHT", "icon", "BOTTOMLEFT", -cfg.icon.gap, 0 } }
		else
			points = { { "TOPLEFT", "icon", "TOPRIGHT", cfg.icon.gap, 0 },
				{ "BOTTOMRIGHT", "frame", "BOTTOMRIGHT", -pad, pad } }
		end
	else
		points = { { "TOPLEFT", "frame", "TOPLEFT", pad, -pad },
			{ "BOTTOMRIGHT", "frame", "BOTTOMRIGHT", -pad, pad } }
	end
	return { icon = icon, bar = points }
end
