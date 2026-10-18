local _, ns = ...
local Skin, Schema, Util = ns.Skin, ns.Schema, ns.Util
local W = ns.Widgets
local Inspector = W.Inspector

local MEDIA_PREVIEW = { font = "font", statusbar = "statusbar", background = "background" }

function Inspector:CreateControl(page, opt, path)
	local label = opt.label or opt.key
	local function Set(value)
		if not page.target then return false end
		local ok, reason = page.target.set(path, value)
		self:Refresh()
		return ok, reason
	end
	local t = opt.type
	if t == "toggle" then
		return W.Checkbox:New(page.frame, { label = label, tooltip = opt.tooltip, onChange = Set })
	elseif t == "range" then
		return W.Slider:New(page.frame, { label = label, tooltip = opt.tooltip, min = opt.min, max = opt.max, step = opt.step,
			onChange = Set })
	elseif t == "select" then
		return W.Dropdown:New(page.frame, { label = label, tooltip = opt.tooltip, onChange = Set,
			values = function() return Schema.GetValues(opt) end })
	elseif ns.Media.TYPES[t] then
		return W.Dropdown:New(page.frame, { label = label, tooltip = opt.tooltip, onChange = Set,
			values = W.Dropdown.MediaValues(t), preview = MEDIA_PREVIEW[t] })
	elseif t == "color" then
		return W.ColorSwatch:New(page.frame, { label = label, tooltip = opt.tooltip, hasAlpha = opt.hasAlpha, onChange = Set })
	elseif t == "text" then
		return W.EditBox:New(page.frame, { label = label, tooltip = opt.tooltip, onChange = Set })
	elseif t == "actionslot" then
		return W.ActionSlot:New(page.frame, { label = label, tooltip = opt.tooltip, accept = opt.accept,
			describe = opt.describe, empty = opt.empty, extras = opt.extras, onChange = Set })
	elseif t == "action" then
		return W.Button:New(page.frame, { text = label, tooltip = opt.tooltip, onClick = function()
			if not page.target then return end
			page.target.invoke(path)
			self:Refresh()
		end })
	end
	error("Inspector: unsupported option type " .. tostring(t))
end

function Inspector:UpdateControl(row, target, resolved)
	local opt, control = row.opt, row.control
	if opt.type == "action" then
		return
	end
	local value = Util.GetPath(resolved, row.path)
	if value ~= nil then
		control:SetValue(value)
	end
	local overridden = target.get(row.path) ~= nil
	local color = overridden and Skin.colors.accent or Skin.colors.text
	control:SetLabelColor(color[1], color[2], color[3])
	if row.reset then
		row.reset:ClearAllPoints()
		row.reset:SetPoint("TOPLEFT", row.region, "TOPRIGHT", 4, 0)
		row.reset:SetShown(overridden)
	end
end

-- Convenience target for a plain config table (no theme, e.g. Workbench data).
function Inspector.TableTarget(schema, config, onChange, resolve)
	return ns.Store:New({
		schema = schema,
		read = function() return type(config) == "function" and config() or config end,
		changed = onChange,
	}):Target(nil, resolve)
end
