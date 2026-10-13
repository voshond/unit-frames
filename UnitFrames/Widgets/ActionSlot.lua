local _, ns = ...
local Skin, Util = ns.Skin, ns.Util

--[[
Drop target for an action (spell, macro...) with its icon, name and state.
The owner decodes the cursor and describes values; this control only shows
them and hands accepted values to onChange. It never writes secure state.

opts: label, tooltip,
  accept()          -> value, or nil plus a reason (nil, nil: nothing on the cursor)
  describe(value)   -> { icon, name, status, inactive }
  onChange(value)   -> true, or false plus a reason; the cursor is cleared only on true
  empty             value that Clear commits
  extras            { { text, tooltip, onClick, combatLocked }, ... } buttons beside the slot

A drop or a click while carrying an action takes the same path. Rejected or
unsaved drops leave both the previous value and the cursor untouched.
]]
local ActionSlot = ns.Widget:Extend("ActionSlot")

local SLOT, LABEL, BUTTON, GAP = 34, 18, 20, 4

function ActionSlot:OnCreate(parent, opts)
	local frame = CreateFrame("Frame", nil, parent)
	self.frame = frame
	-- Label, then the slot with its name and status, then the buttons on their
	-- own row so a narrow settings panel never squeezes the action's name.
	frame:SetHeight(LABEL + SLOT + GAP + BUTTON)
	self:CreateLabel(frame, opts.label):SetPoint("TOPLEFT")

	local slot = CreateFrame("Button", nil, frame, "BackdropTemplate")
	slot:SetSize(SLOT, SLOT)
	slot:SetPoint("TOPLEFT", 0, -LABEL)
	Skin.ApplyPanel(slot, "button")
	slot:RegisterForClicks("LeftButtonUp")
	self.icon = slot:CreateTexture(nil, "ARTWORK")
	self.icon:SetPoint("TOPLEFT", 2, -2)
	self.icon:SetPoint("BOTTOMRIGHT", -2, 2)
	self.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	local function Receive() self:Receive() end
	slot:SetScript("OnReceiveDrag", Receive)
	slot:SetScript("OnClick", Receive)
	slot:SetScript("OnEnter", function() slot:SetBackdropBorderColor(unpack(Skin.colors.accent)) end)
	slot:SetScript("OnLeave", function() slot:SetBackdropBorderColor(unpack(Skin.colors.border)) end)
	ns.Widget.AttachTooltip(slot, opts.label, opts.tooltip)
	self.slot = slot

	-- Buttons right to left: Clear, then the owner's extras.
	self.buttons = {}
	local anchor
	local function AddButton(text, tooltip, onClick)
		local button = ns.Widgets.Button:New(frame, { text = text, tooltip = tooltip, height = BUTTON, onClick = onClick })
		if anchor then
			button:SetPoint("RIGHT", anchor:GetFrame(), "LEFT", -GAP, 0)
		else
			button:SetPoint("BOTTOMRIGHT")
		end
		anchor = button
		self.buttons[#self.buttons + 1] = button
		return button
	end
	self.clear = AddButton("Clear", "Remove this action. The spell or macro itself is not changed.", function()
		self:Commit(Util.Copy(self.opts.empty))
	end)
	self.locked = {}
	for _, extra in ipairs(opts.extras or {}) do
		local onClick = extra.onClick
		local button = AddButton(extra.text, extra.tooltip, function()
			if extra.combatLocked and InCombatLockdown() then return end
			onClick()
		end)
		if extra.combatLocked then self.locked[#self.locked + 1] = button end
	end

	self.name = Skin.FontString(frame)
	self.name:SetJustifyH("LEFT")
	self.name:SetPoint("TOPLEFT", slot, "TOPRIGHT", 6, -4)
	self.name:SetPoint("RIGHT", frame, "RIGHT")
	self.status = Skin.FontString(frame)
	self.status:SetJustifyH("LEFT")
	self.status:SetPoint("BOTTOMLEFT", slot, "BOTTOMRIGHT", 6, 4)
	self.status:SetPoint("RIGHT", frame, "RIGHT")

	-- PLAYER_REGEN_DISABLED fires before lockdown begins, so the events
	-- themselves decide; the click guard above covers the rest.
	if #self.locked > 0 then
		frame:RegisterEvent("PLAYER_REGEN_DISABLED")
		frame:RegisterEvent("PLAYER_REGEN_ENABLED")
		frame:SetScript("OnEvent", function(_, event) self:SetCombatLocked(event == "PLAYER_REGEN_DISABLED") end)
	end
	self:SetCombatLocked(InCombatLockdown())
end

function ActionSlot:SetCombatLocked(locked)
	for _, button in ipairs(self.locked) do button:SetEnabled(not locked) end
end

function ActionSlot:Receive()
	if self.released then return end
	local value, reason = self.opts.accept()
	if value == nil then
		if reason then self:ShowMessage(reason) end
		return
	end
	if self:Commit(value) then ClearCursor() end
end

function ActionSlot:Commit(value)
	local ok, reason = self.opts.onChange(value)
	if ok then
		self.message = nil
		self:Render()
		return true
	end
	self:ShowMessage(reason or "The action could not be saved.")
	return false
end

function ActionSlot:ShowMessage(text)
	self.message = text
	self:Render()
end

function ActionSlot:SetValue(value)
	if not Util.Equals(value, self.value) then self.message = nil end
	self.value = Util.Copy(value)
	self:Render()
end

function ActionSlot:GetValue()
	return self.value
end

function ActionSlot:Render()
	if self.value == nil then return end
	local info = self.opts.describe(self.value)
	self.icon:SetTexture(info.icon)
	self.icon:SetDesaturated(info.inactive == true)
	self.name:SetText(info.name or "")
	local color = (self.message or info.inactive) and Skin.colors.warning or Skin.colors.textDim
	self.status:SetTextColor(color[1], color[2], color[3])
	self.status:SetText(self.message or info.status or "")
	self.clear:SetEnabled(not Util.Equals(self.value, self.opts.empty))
end

function ActionSlot:OnRelease()
	self.frame:UnregisterAllEvents()
	self.frame:SetScript("OnEvent", nil)
	for _, name in ipairs({ "OnReceiveDrag", "OnClick", "OnEnter", "OnLeave" }) do self.slot:SetScript(name, nil) end
	for _, button in ipairs(self.buttons) do button:Release() end
	self.buttons, self.locked = {}, {}
end
