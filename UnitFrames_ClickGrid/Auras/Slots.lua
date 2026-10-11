local _, CG = ...
local UF = CG.UF
local Slots = UF.Components.Auras:Extend("FriendlyAuraSlots")
CG.Slots = Slots
Slots.schema = UF.Util.Copy(UF.Components.Auras.schema)
for _, descriptor in ipairs(CG.SlotSchema) do Slots.schema[#Slots.schema + 1] = descriptor end

function Slots.ParseIDs(text)
	local ids, count = {}, 0
	for token in text:gmatch("[^,%s]+") do
		local id = tonumber(token)
		if not id or id < 1 or id == math.huge or id ~= math.floor(id) then return nil, "Use positive numeric aura spell IDs" end
		ids[id], count = true, count + 1
	end
	return ids, count
end

function Slots:OnCreate(parent)
	self.frame = CreateFrame("Frame", nil, parent)
	self.frame:SetAllPoints(parent)
	self.container = CreateFrame("AuraContainer", nil, self.frame, "CustomAuraContainerTemplate")
	self.buttons = {}
	for i = 1, 3 do
		local key = "slot" .. i
		self.buttons[i] = self.container:AddAuraSlot(key, "HELPFUL|PLAYER", {
			candidateFilters = { includeSpellIDs = {} },
			sortMethod = AuraContainerSortMethod.ExpirationOnly,
			sortDirection = AuraContainerSortDirection.Normal,
			initializeFrame = function(button) self:InitButton(button, key) end,
		})
	end
end

function Slots:InitButton(button, key, preview)
	UF.Components.Auras.InitButton(self, button, key, preview)
	button:SetMouseClickEnabled(false)
	button:SetMouseMotionEnabled(false)
end

function Slots:OnApply(cfg)
	self.errors = {}
	for i = 1, 3 do
		local key, button = "slot" .. i, self.buttons[i]
		local slot = cfg[key]
		local ids, reason = Slots.ParseIDs(slot.spell)
		if not ids then self.errors[#self.errors + 1] = key .. ": " .. reason end
		self.container:SetAuraSlotFilterString(key, slot.own and "HELPFUL|PLAYER" or "HELPFUL")
		self.container:SetAuraSlotCandidateFilters(key, { includeSpellIDs = slot.enabled and ids or {} })
		self:StyleButton(button)
		button:ClearAllPoints()
		button:SetPoint(slot.anchor, self.frame, slot.anchor, slot.offsetX, slot.offsetY)
	end
	if self.previewData then self:RenderSamples() end
end

function Slots:SetEnabled(enabled)
	self.enabled = enabled and true or false
	self.frame:SetShown(self.enabled)
	self.container:SetEnabled(self.enabled and not self.previewData)
	self.container:SetShown(self.enabled and not self.previewData)
end

function Slots:SetUnit(unit)
	if self.container:GetUnit() ~= unit then self.container:SetUnit(unit) end
end

function Slots:ShowSample(values)
	self.previewData = values
	self:SetEnabled(self.enabled)
	self:RenderSamples()
end

function Slots:RenderSamples()
	self.samples = self.samples or {}
	for i = 1, 3 do
		local key, button = "slot" .. i, self.samples[i]
		local cfg = self.resolved[key]
		if not button then
			button = CreateFrame("Button", nil, self.frame)
			self:InitButton(button, key, true)
			self.samples[i] = button
		end
		self:StyleButton(button)
		button:ClearAllPoints()
		button:SetPoint(cfg.anchor, self.frame, cfg.anchor, cfg.offsetX, cfg.offsetY)
		local ids = Slots.ParseIDs(cfg.spell)
		local found
		for _, aura in ipairs(self.previewData.buffs or {}) do
			if cfg.enabled and ids and ids[aura.spellId] and (not cfg.own or aura.sourceUnit == "player") then
				local remaining = aura.duration == 0 and math.huge or aura.remaining or aura.duration
				local previous = found and (found.duration == 0 and math.huge or found.remaining or found.duration)
				if not found or remaining < previous then found = aura end
			end
		end
		if found then UF.Components.Auras.DrawSample(self, button, found) end
		button:SetShown(found ~= nil)
	end
end

function Slots:OnRelease()
	self.previewData = nil
	self:SetEnabled(false)
end

local function Update(frame)
	if frame.__unit then frame.UFCG_Slots:SetUnit(frame.__unit) end
end
UF.oUF:AddElement("UFCG_Slots", Update, function(frame) return frame.UFCG_Slots ~= nil end, function() end)
