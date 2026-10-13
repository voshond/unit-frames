local _, ns = ...
local Placement = {}
ns.IconPlacement = Placement

-- Fresh descriptors; adapters preserve each owner's saved keys and UI policy.
function Placement.BuildSchema(opts)
	opts = opts or {}
	local d = opts.defaults or {}
	local function Default(key, fallback)
		if d[key] == nil then return fallback end
		return d[key]
	end
	local schema = {
		{ key = "enabled", type = "toggle", label = "Enabled", default = Default("enabled", true) },
		{ key = "anchor", type = "select", label = "Anchor", values = ns.DecorationStack.ANCHORS, default = Default("anchor", "TOP"),
			tooltip = "Icons sharing a position line up as one group: edges and the centre keep the group centred, border corners grow inward from the corner. Portrait anchors offer the same nine positions inside the portrait and require an enabled portrait." },
		{ key = "order", type = "range", label = "Order", min = 1, max = 10, step = 1, default = Default("order", 1),
			tooltip = "Icons sharing a position run left to right (top to bottom on the sides) by order. Absent icons leave no gap." },
		{ key = "gap", type = "range", label = "Gap to next icon", min = 0, max = 20, step = 1, default = Default("gap", 2) },
		{ key = "size", type = "range", label = "Size", min = 8, max = 64, step = 1, default = Default("size", 20),
			tooltip = "Portrait icons shrink to fit if the portrait is smaller than this size. A crowded portrait group can still extend past the portrait." },
		{ key = "offsetX", type = "range", label = "Horizontal offset", min = -100, max = 100, step = 1, default = 0,
			tooltip = "Positive moves right; negative moves left. Moves only this icon, not the rest of its group." },
		{ key = "offsetY", type = "range", label = "Vertical offset", min = -100, max = 100, step = 1, default = 0,
			tooltip = "Positive moves up; negative moves down. Moves only this icon, not the rest of its group." },
	}
	local byKey, out = {}, {}
	for _, opt in ipairs(schema) do byKey[opt.key] = opt end
	for _, key in ipairs(opts.order or { "enabled", "anchor", "order", "gap", "size", "offsetX", "offsetY" }) do
		local opt = byKey[key]
		for field, value in pairs((opts.fields or {})[key] or {}) do opt[field] = value end
		if opt.tooltip == false then opt.tooltip = nil end
		opt.key = opts.keys and opts.keys[key] or key
		out[#out + 1] = opt
	end
	return ns.Util.Copy(out)
end

function Placement.PrefixedKeys(prefix)
	return { enabled = prefix, anchor = prefix .. "Position", size = prefix .. "Size",
		order = prefix .. "Order", gap = prefix .. "Gap", offsetX = prefix .. "OffsetX", offsetY = prefix .. "OffsetY" }
end

function Placement.Read(cfg, keys)
	local out = {}
	for _, key in ipairs({ "enabled", "anchor", "order", "gap", "size", "offsetX", "offsetY" }) do
		out[key] = cfg[keys and keys[key] or key]
	end
	return out
end

function Placement.Member(cfg, host, widgets, present)
	return { host = host, widgets = widgets, present = present, enabled = cfg.enabled,
		anchor = cfg.anchor, size = cfg.size, order = cfg.order, gap = cfg.gap, x = cfg.offsetX, y = cfg.offsetY }
end
