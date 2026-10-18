local _, wb = ...
local UF = UnitFrames
local Workbench, W, Skin = wb.Workbench, UF.Widgets, UF.Skin
local Profiles = UF.Profiles

--[[
Profiles: the settings column manages AceDB profiles (switch, new, copy,
delete, reset); the stage shares them as strings (Core/Profiles.lua).
Profile operations change style only: the active profile keeps its Edit
Mode positions, and strings never carry them.
]]

-- Unsaved form state of the settings column; deleting and resetting stay
-- hidden until "Allow delete and reset" is ticked for one operation.
local editor = {}

local function ResetEditor()
	editor.newName, editor.copyFrom, editor.deleteName, editor.unlocked = "", nil, nil, false
end
ResetEditor()

local function Others()
	local values, current = {}, Profiles:GetCurrent()
	for _, name in ipairs(Profiles:List()) do
		if name ~= current then values[#values + 1] = { name, name } end
	end
	return values
end

-- A remembered choice among the other profiles, or the first of them.
local function Choice(name)
	local others = Others()
	for _, entry in ipairs(others) do
		if entry[1] == name then return name end
	end
	return others[1] and others[1][1]
end

local function NoOthers() return #Others() == 0 end
local function Locked(values) return NoOthers() or not values.unlocked end

local SCHEMA = {
	{ key = "current", type = "select", label = "Active profile",
		values = function()
			local values = {}
			for _, name in ipairs(Profiles:List()) do values[#values + 1] = { name, name } end
			return values
		end,
		tooltip = "Switch this character to another profile. Frames move to that profile's own Edit Mode positions." },
	{ key = "newName", type = "text", label = "New profile name" },
	{ key = "create", type = "action", label = "Create and switch",
		tooltip = "A new profile with the default style, made active. It starts with the current frame positions." },
	{ key = "copyFrom", type = "select", label = "Copy style from", values = Others, hidden = NoOthers,
		tooltip = "Another profile whose style (theme, unit frames, ClickGrid panel and bars) to copy." },
	{ key = "copy", type = "action", label = "Copy into active profile", hidden = NoOthers,
		tooltip = "Replace the active profile's style with a copy of the chosen profile. Frame positions stay where they are." },
	{ key = "unlocked", type = "toggle", label = "Allow delete and reset",
		tooltip = "Shows the buttons that delete a profile or reset the active one. Neither can be undone." },
	{ key = "deleteName", type = "select", label = "Profile to delete", values = Others, hidden = Locked },
	{ key = "delete", type = "action", label = "Delete profile", hidden = Locked,
		tooltip = "Delete the chosen profile. Characters using it switch to their default profile." },
	{ key = "reset", type = "action", label = "Reset active profile", hidden = function(values) return not values.unlocked end,
		tooltip = "Return the active profile to the default style. Frame positions stay where they are." },
}

local function Resolved()
	return {
		current = Profiles:GetCurrent(),
		newName = editor.newName,
		copyFrom = Choice(editor.copyFrom),
		unlocked = editor.unlocked,
		deleteName = Choice(editor.deleteName),
	}
end

local ACTIONS = {
	create = function()
		local ok, result = Profiles:Create(editor.newName)
		if ok then editor.newName = "" end
		return ok, result, ok and "Created and switched to " .. result .. "."
	end,
	copy = function()
		local from = Choice(editor.copyFrom)
		local ok, reason = Profiles:Copy(from)
		return ok, reason, ok and "Copied the style of " .. from .. "."
	end,
	delete = function()
		local name = Choice(editor.deleteName)
		local ok, reason = Profiles:Delete(name)
		editor.unlocked, editor.deleteName = false, nil
		return ok, reason, ok and "Deleted " .. name .. "."
	end,
	reset = function()
		Profiles:Reset()
		editor.unlocked = false
		return true, nil, "Reset " .. Profiles:GetCurrent() .. " to the default style."
	end,
}

local function StyleTarget(handle)
	return {
		schema = SCHEMA,
		-- Form fields are never "overridden": no reset buttons.
		get = function() return nil end,
		set = function(path, value)
			if path == "current" then
				local ok, reason = Profiles:Switch(value)
				handle:SetMessage(ok and "Switched to " .. value .. "." or reason, not ok)
				return ok, reason
			end
			editor[path] = value
			return true
		end,
		resolved = Resolved,
		invoke = function(path)
			local ok, reason, message = ACTIONS[path]()
			handle:SetMessage(ok and message or reason, not ok)
			handle:Apply()
		end,
	}
end

-- Stage: export and import strings -------------------------------------------------

local NOTE = "Share profiles as text. A style string holds the global theme, every unit frame's style and, with"
	.. " ClickGrid loaded, its panel and bar styles. Click bindings import into your current specialization."
	.. " All settings combines both. Frame positions are never included."
local MAX_LISTED = 6

local function Summary(dropped)
	if #dropped == 0 then return "" end
	local listed = {}
	for i = 1, math.min(#dropped, MAX_LISTED) do listed[i] = dropped[i] end
	return " Skipped " .. #dropped .. " unknown, invalid or unavailable item" .. (#dropped == 1 and "" or "s") .. ": "
		.. table.concat(listed, ", ") .. (#dropped > MAX_LISTED and ", …" or "") .. "."
end

local function CreateStage(stage)
	local handle = { schema = {}, buttons = {} }
	local frame = CreateFrame("Frame", nil, stage)
	handle.frame = frame

	local note = Skin.FontString(frame)
	note:SetPoint("TOPLEFT")
	note:SetPoint("TOPRIGHT")
	note:SetHeight(44)
	note:SetJustifyH("LEFT")
	note:SetJustifyV("TOP")
	note:SetWordWrap(true)
	handle.note = note

	local row = CreateFrame("Frame", nil, frame)
	row:SetPoint("TOPLEFT", note, "BOTTOMLEFT", 0, -6)
	row:SetPoint("TOPRIGHT", note, "BOTTOMRIGHT", 0, -6)
	row:SetHeight(22)
	local previous
	local function AddButton(parent, text, tooltip, onClick)
		local button = W.Button:New(parent, { text = text, tooltip = tooltip, onClick = onClick })
		if previous and previous:GetParent() == parent then
			button:SetPoint("TOPLEFT", previous, "TOPRIGHT", 6, 0)
		else
			button:SetPoint("TOPLEFT", parent, "TOPLEFT")
		end
		previous = button:GetFrame()
		handle.buttons[#handle.buttons + 1] = button
		return button
	end
	-- Each kind, then all of them together when there is more than one.
	local keys = {}
	for _, key in ipairs(Profiles.kindOrder) do
		if key ~= "all" then keys[#keys + 1] = key end
	end
	if #keys > 1 then keys[#keys + 1] = "all" end
	for _, key in ipairs(keys) do
		local label = Profiles.kinds[key].label
		local button = AddButton(row, "Export " .. label, "Put a string with the " .. label
			.. " of the active profile in the box below, ready to copy.", function() handle:Export(key) end)
		button:SetEnabled(Profiles:IsSupported())
	end

	-- The string box: Blizzard's multi-line scrolling edit box.
	local panel = CreateFrame("Frame", nil, frame, "BackdropTemplate")
	Skin.ApplyPanel(panel, "button")
	panel:SetPoint("TOPLEFT", row, "BOTTOMLEFT", 0, -6)
	-- Room below for the name box, the buttons and a two-line message.
	panel:SetPoint("BOTTOMRIGHT", 0, 108)
	local box = CreateFrame("Frame", nil, panel, "ScrollingEditBoxTemplate")
	box:SetPoint("TOPLEFT", 6, -6)
	box:SetPoint("BOTTOMRIGHT", -20, 6)
	local bar = CreateFrame("EventFrame", nil, panel, "MinimalScrollBar")
	bar:SetPoint("TOPLEFT", box, "TOPRIGHT", 4, 0)
	bar:SetPoint("BOTTOMLEFT", box, "BOTTOMRIGHT", 4, 0)
	ScrollUtil.RegisterScrollBoxWithScrollBar(box:GetScrollBox(), bar)
	handle.box = box

	local nameBox = W.EditBox:New(frame, { label = "Import as a new profile (empty: replace the active profile)",
		tooltip = "Name for a new profile to import a style string into. It starts with the current frame positions." })
	nameBox:SetPoint("TOPLEFT", panel, "BOTTOMLEFT", 0, -6)
	nameBox:SetPoint("TOPRIGHT", panel, "BOTTOMRIGHT", 0, -6)
	nameBox:SetValue("")
	handle.nameBox = nameBox
	handle.buttons[#handle.buttons + 1] = nameBox

	local actions = CreateFrame("Frame", nil, frame)
	actions:SetPoint("TOPLEFT", nameBox:GetFrame(), "BOTTOMLEFT", 0, -6)
	actions:SetPoint("TOPRIGHT", nameBox:GetFrame(), "BOTTOMRIGHT", 0, -6)
	actions:SetHeight(22)
	AddButton(actions, "Import", "Import the string in the box. Nothing changes when it is damaged or not a"
		.. " UnitFrames string; unknown settings are skipped.", function() handle:Import() end)
		:SetEnabled(Profiles:IsSupported())
	AddButton(actions, "Select all", "Select the whole string to copy it (Ctrl+C).", function()
		box:SetFocus()
		box:GetEditBox():HighlightText()
	end)
	AddButton(actions, "Clear", nil, function()
		box:ClearText()
		handle:SetMessage("")
	end)

	local message = Skin.FontString(frame)
	message:SetPoint("TOPLEFT", actions, "BOTTOMLEFT", 0, -6)
	message:SetPoint("TOPRIGHT", actions, "BOTTOMRIGHT", 0, -6)
	message:SetHeight(28)
	message:SetJustifyH("LEFT")
	message:SetJustifyV("TOP")
	message:SetWordWrap(true)
	handle.message = message

	function handle:SetMessage(text, failed)
		local color = failed and Skin.colors.warning or Skin.colors.text
		message:SetTextColor(color[1], color[2], color[3])
		message:SetText(text or "")
	end

	function handle:Export(kind)
		local text, reason = Profiles:Export(kind)
		if not text then return self:SetMessage(reason, true) end
		box:SetText(text)
		box:SetFocus()
		box:GetEditBox():HighlightText()
		self:SetMessage("Press Ctrl+C to copy the " .. Profiles.kinds[kind].label .. " string.")
	end

	function handle:Import()
		local ok, result, label = Profiles:Import(box:GetInputText(), self.nameBox:GetValue())
		if not ok then return self:SetMessage(result, true) end
		self.nameBox:SetValue("")
		self:SetMessage("Imported " .. label .. " into " .. Profiles:GetCurrent() .. "." .. Summary(result))
		self:Apply()
	end

	function handle:Apply()
		if not Profiles:IsSupported() then
			note:SetText(NOTE .. "\n|cffff5a4dThis client has no C_EncodingUtil: strings are unavailable.|r")
		else
			note:SetText(NOTE)
		end
	end

	function handle:Resolved() return Resolved() end

	function handle:Release()
		for _, button in ipairs(self.buttons) do button:Release() end
		box:ClearFocus()
		frame:Hide()
	end

	handle:Apply()
	return handle
end

Workbench:Register({
	id = "profiles",
	category = "Profiles",
	name = "Profiles & sharing",
	scope = "Active profile; click bindings use the current specialization",
	settingsTargets = function() return { { id = "style", schema = SCHEMA } } end,
	destinations = {
		{ label = "Import profile", aliases = "paste share string", reveal = function(handle) handle.box:SetFocus() end },
		{ label = "Export profile", aliases = "copy share string", reveal = function(handle) handle.box:SetFocus() end },
	},
	fillStage = true,
	size = { 600, 400 },
	-- Switching, copying and resetting restyle everything; the form follows.
	refreshOn = { "ProfileChanged" },
	create = CreateStage,
	styleTarget = StyleTarget,
	reset = ResetEditor,
})
