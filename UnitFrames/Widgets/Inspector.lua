local _, ns = ...
local Skin, Schema, Util = ns.Skin, ns.Schema, ns.Util
local W = ns.Widgets

--[[
Builds a panel of controls from a schema (see Core/Schema.lua) and keeps it in
sync with a config. Used by the Workbench and later by the settings window.

  inspector:SetTarget(target, cacheKey, groupPath)

With groupPath (e.g. "health.bar", "" for the top level) only that group's own
options are shown, not its sub-groups: one settings section at a time.
Without it, the whole schema is shown with nested groups as headers.

  target = {
    schema   = schema,
    get      = function(path) end        -- raw value at path, nil = inherited/default
    set      = function(path, value) end  -- value nil = reset to inherited/default
    resolved = function() end              -- effective values (same shape as schema)
    invoke   = function(path) end          -- optional UI action on the current target
    revision = value                       -- optional; change when schema structure changes
  }

Controls are built once per cacheKey and reused when switching back.
Options whose value is set (not inherited) show their label in the accent
colour and get a reset button.

Extra option type understood only here:
  action   { key, type = "action", label } -> target.invoke(path)
]]
local Inspector = ns.Widget:Extend("Inspector")

local INDENT = 10
local ROW_GAP = 6
local MEDIA_PREVIEW = { font = "font", statusbar = "statusbar", background = "background" }

function Inspector:OnCreate(parent)
	self.scroll = W.ScrollPanel:New(parent)
	self.frame = self.scroll:GetFrame()
	self.pages = {}
	self.empty = Skin.FontString(self.frame)
	self.empty:SetPoint("TOPLEFT", 0, -4)
	self.empty:SetTextColor(unpack(Skin.colors.textDim))
	self.empty:SetText("Nothing to set here; pick a section below it.")
	-- Row widths depend on the panel width.
	self.scroll.box:HookScript("OnSizeChanged", function()
		self:Refresh()
	end)
end

function Inspector:SetTarget(target, cacheKey, groupPath)
	if self.page then
		self.page.frame:Hide()
	end
	cacheKey = cacheKey or target
	local page = self.pages[cacheKey]
	if not page or page.revision ~= target.revision or page.groupPath ~= groupPath then
		page = self:BuildPage(target, groupPath)
		self.pages[cacheKey] = page
	end
	page.target = target
	self.page = page
	page.frame:Show()
	self:Refresh()
end

function Inspector:BuildPage(target, groupPath)
	local page = {
		frame = CreateFrame("Frame", nil, self.scroll:GetContent()),
		rows = {},
		revision = target.revision,
		groupPath = groupPath,
	}
	page.frame:SetAllPoints()
	if groupPath then
		local schema, prefix = target.schema, ""
		if groupPath ~= "" then
			schema, prefix = Schema.Find(target.schema, groupPath).schema, groupPath .. "."
		end
		self:BuildRows(page, schema, prefix, 0, true)
	else
		self:BuildRows(page, target.schema, "", 0)
	end
	return page
end

-- flat: skip sub-groups (they are separate sections).
function Inspector:BuildRows(page, schema, prefix, depth, flat)
	for _, opt in ipairs(schema) do
		local path = prefix .. opt.key
		if opt.type == "group" then
			if not flat then
				local header = Skin.FontString(page.frame, "header")
				header:SetJustifyH("LEFT")
				header:SetText(opt.label or opt.key)
				self:AddRow(page, { opt = opt, path = path, depth = depth, region = header, height = 18, isHeader = true })
				self:BuildRows(page, opt.schema, path .. ".", depth + 1)
			end
		else
			local control = self:CreateControl(page, opt, path)
			self:AddRow(page, { opt = opt, path = path, depth = depth, control = control, region = control:GetFrame(),
				height = control:GetHeight() })
		end
	end
end

function Inspector:AddRow(page, row)
	if row.control and row.opt.type ~= "action" then
		local reset = CreateFrame("Button", nil, page.frame)
		reset:SetSize(14, 14)
		reset:SetNormalTexture([[Interface\Buttons\UI-RefreshButton]])
		reset:SetScript("OnClick", function()
			page.target.set(row.path, nil)
			self:Refresh()
		end)
		ns.Widget.AttachTooltip(reset, "Reset", "Use the inherited or default value again.")
		row.reset = reset
	end
	page.rows[#page.rows + 1] = row
end

function Inspector:CreateControl(page, opt, path)
	local label = opt.label or opt.key
	local function Set(value)
		page.target.set(path, value)
		self:Refresh()
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
	elseif t == "action" then
		return W.Button:New(page.frame, { text = label, tooltip = opt.tooltip, onClick = function()
			page.target.invoke(path)
			self:Refresh()
		end })
	end
	error("Inspector: unsupported option type " .. tostring(t))
end

-- Re-reads all values, re-evaluates `hidden` and lays the rows out again.
function Inspector:Refresh()
	local page = self.page
	if not page then
		return
	end
	local target = page.target
	local resolved = target.resolved()
	local width = self.scroll:GetContent():GetWidth()
	local y = 0
	local hiddenDepth -- rows deeper than a hidden group are hidden too
	for _, row in ipairs(page.rows) do
		if hiddenDepth and row.depth <= hiddenDepth then
			hiddenDepth = nil
		end
		local parentPath = row.path:match("^(.*)%.[^%.]+$")
		local group = parentPath and Util.GetPath(resolved, parentPath) or resolved
		local visible = not hiddenDepth and not (row.opt.hidden and row.opt.hidden(group))
		if not visible and row.isHeader and not hiddenDepth then
			hiddenDepth = row.depth
		end

		row.region:SetShown(visible)
		if row.reset then
			row.reset:Hide()
		end
		if visible then
			local x = row.depth * INDENT
			if row.isHeader then
				y = y + 4
			end
			row.region:ClearAllPoints()
			row.region:SetPoint("TOPLEFT", page.frame, "TOPLEFT", x, -y)
			row.region:SetWidth(math.max(width - x - 22, 40))
			if row.control then
				self:UpdateControl(row, target, resolved)
			end
			y = y + row.height + ROW_GAP
		end
	end
	self.empty:SetShown(#page.rows == 0)
	self.scroll:SetContentHeight(y)
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
	return ns.Store.New({
		schema = schema,
		read = function() return type(config) == "function" and config() or config end,
		changed = onChange,
	}):Target(nil, resolve)
end
