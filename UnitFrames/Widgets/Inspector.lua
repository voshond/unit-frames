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

Extra option types understood only here:
  action     { key, type = "action", label } -> target.invoke(path)
  actionslot { key, type = "actionslot", label, accept, describe, empty, extras }
             -> an ActionSlot drop target (see Widgets/ActionSlot.lua). It
             needs target.set to return true, or false plus a reason.
]]
local Inspector = ns.Widget:Extend("Inspector")

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
		self:ClearReveal()
		self:FinishEditing()
		self.page.scrollPercentage = self.scroll:GetScrollPercentage()
		self.page.frame:Hide()
		self.page.target = nil
		self.page = nil
	end
	self.empty:Hide()
end

function Inspector:FinishEditing()
	if not self.page then return end
	for _, row in ipairs(self.page.rows) do
		if row.control then
			if row.control.ClosePicker then row.control:ClosePicker() end
			if row.control.dropdown then row.control.dropdown:CloseMenu() end
			if row.control.input then row.control.input:ClearFocus() end
		end
	end
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
		if row.sourceLink then row.sourceLink:Release() end
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
