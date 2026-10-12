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
groupPath may also be { paths = { "range", "readyCheck", ... }, revision? }:
a presentation page referring to existing groups or individual option paths.

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

function Inspector:ClearTarget()
	if self.page then
		self.page.scrollPercentage = self.scroll:GetScrollPercentage()
		self.page.frame:Hide()
		self.page.target = nil
		self.page = nil
	end
	self.empty:Hide()
end

function Inspector:SetTarget(target, cacheKey, groupPath)
	self:ClearTarget()
	cacheKey = cacheKey or target
	local page = self.pages[cacheKey]
	local selection = type(groupPath) == "table" and groupPath or nil
	local path = not selection and groupPath or nil
	if not page or page.revision ~= target.revision or page.groupPath ~= path
		or not Util.Equals(page.selection, selection) then
		if page then self:DiscardPage(page) end
		page = self:BuildPage(target, groupPath)
		self.pages[cacheKey] = page
	end
	page.target = target
	self.page = page
	page.frame:Show()
	self:Refresh()
	self.scroll:SetScrollPercentage(page.scrollPercentage or 0)
end

function Inspector:DiscardPage(page)
	page.target = nil
	for _, row in ipairs(page.rows) do
		if row.control then row.control:Release() end
		if row.reset then
			row.reset:SetScript("OnClick", nil)
			row.reset:SetScript("OnEnter", nil)
			row.reset:SetScript("OnLeave", nil)
		end
	end
	page.rows = {}
	page.frame:Hide()
	page.frame:ClearAllPoints()
end

function Inspector:BuildPage(target, groupPath)
	local page = {
		frame = CreateFrame("Frame", nil, self.scroll:GetContent()),
		rows = {},
		revision = target.revision,
		groupPath = type(groupPath) ~= "table" and groupPath or nil,
		selection = type(groupPath) == "table" and Util.Copy(groupPath) or nil,
	}
	page.frame:SetAllPoints()
	if type(groupPath) == "table" then
		for _, path in ipairs(groupPath.paths) do
			local opt = assert(Schema.Find(target.schema, path), "Inspector: unknown settings path " .. path)
			if opt.type == "group" then
				self:AddHeader(page, opt, path, 0)
				self:BuildRows(page, opt.schema, path .. ".", 1)
			else
				self:AddControl(page, opt, path, 0)
			end
		end
	elseif groupPath then
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

function Inspector:AddHeader(page, opt, path, depth)
	local header = Skin.FontString(page.frame, "header")
	header:SetJustifyH("LEFT")
	header:SetText(opt.label or opt.key)
	self:AddRow(page, { opt = opt, path = path, depth = depth, region = header, height = 18, isHeader = true })
end

function Inspector:AddControl(page, opt, path, depth)
	local control = self:CreateControl(page, opt, path)
	self:AddRow(page, { opt = opt, path = path, depth = depth, control = control, region = control:GetFrame(),
		height = control:GetHeight() })
end

-- flat: skip sub-groups (they are separate sections).
function Inspector:BuildRows(page, schema, prefix, depth, flat)
	for _, opt in ipairs(schema) do
		local path = prefix .. opt.key
		if opt.type == "group" then
			if not flat then
				self:AddHeader(page, opt, path, depth)
				self:BuildRows(page, opt.schema, path .. ".", depth + 1)
			end
		else
			self:AddControl(page, opt, path, depth)
		end
	end
end

function Inspector:AddRow(page, row)
	if row.control and row.opt.type ~= "action" then
		local reset = CreateFrame("Button", nil, page.frame)
		reset:SetSize(14, 14)
		reset:SetNormalTexture([[Interface\Buttons\UI-RefreshButton]])
		reset:SetScript("OnClick", function()
			if not page.target then return end
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
		if not page.target then return end
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
			if not page.target then return end
			page.target.invoke(path)
			self:Refresh()
		end })
	end
	error("Inspector: unsupported option type " .. tostring(t))
end

-- Referred options retain their original ancestors and resolved-group context
-- even when a presentation page moves them elsewhere in navigation.
local function Hidden(schema, resolved, path)
	local group = resolved
	for key in path:gmatch("[^%.]+") do
		local opt = assert(Schema.Find(schema, key), "Inspector: unknown option " .. path)
		if opt.hidden and opt.hidden(group) then return true end
		schema, group = opt.schema, group and group[key]
	end
	return false
end

-- Re-reads all values, re-evaluates `hidden` and lays the rows out again.
function Inspector:Refresh()
	local page = self.page
	if not page then
		return
	end
	local target = page.target
	if not target then return end
	local resolved = target.resolved()
	local width = self.scroll:GetContent():GetWidth()
	local y = 0
	for _, row in ipairs(page.rows) do
		local visible = not Hidden(target.schema, resolved, row.path)

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
