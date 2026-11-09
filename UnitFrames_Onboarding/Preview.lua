local _, ob = ...
local UF = UnitFrames

--[[
Sample unit frames in a style that isn't saved. They are built, applied and
filled inside Config:WithTheme with that style's own theme, so neither the
live frames nor the saved style are read or changed.

  layout: array of { unit, point = { SetPoint arguments }, buffs, debuffs, cast, dots }
  opts:   animated
]]
local Preview = UF.Object:Extend("OnboardingPreview")
ob.Preview = Preview

local FRAME_INTERVAL = 1 / 30

local DOT = { name = "Corruption", school = 32 }

local function Slice(list, count)
	local out = {}
	for index = 1, math.min(count or 0, #list) do out[index] = list[index] end
	return out
end

-- Plain sample values; animated, health and power drift and casts loop.
local function Values(slot, time)
	local v = UF.Units:GetSample(slot.unit)
	local phase = slot.unit == "player" and 0 or 2.1
	local wave = time and 0.5 + 0.5 * math.sin(time * 0.8 + phase) or 0.55
	v.health = v.healthMax * (0.38 + 0.52 * wave)
	v.absorb = v.healthMax * 0.12
	v.power = v.powerMax * (0.85 - 0.45 * wave)
	v.pendingDamage = {}
	if slot.dots then
		v.pendingDamage[1] = { name = DOT.name, school = DOT.school, damage = v.healthMax * 0.14 }
	end
	v.showCast = slot.cast == true
	v.castProgress = time and (time + phase) % 2.4 / 2.4 or 0.6
	if time then v.gcdProgress = time % 1.5 / 1.5 end
	v.categoryAuras = {}
	v.buffs = Slice(v.buffs, slot.buffs)
	v.debuffs = Slice(v.debuffs, slot.debuffs)
	v.animateAuras = time ~= nil
	return v
end

function Preview:Init(parent, layout, opts)
	self.parent, self.layout, self.opts = parent, layout, opts or {}
	self.frames, self.time, self.elapsed = {}, 0, 0
end

local function Build(self, style)
	for index, slot in ipairs(self.layout) do
		local config = style.units[slot.unit]
		local frame = self.frames[index]
		if not frame then
			frame = UF.Units:CreateFromDefinition(UF.Units:GetDefinition(slot.unit), self.parent, config)
			frame:SetPoint(unpack(slot.point))
			self.frames[index] = frame
		end
		frame:Apply(config)
	end
end

local function Fill(self, time)
	for index, slot in ipairs(self.layout) do
		UF.Units:ShowSample(self.frames[index], Values(slot, time))
	end
end

-- Shows `style` (Pending:Style()) with its resolved theme.
function Preview:Show(style, theme)
	self.style, self.theme = style, theme
	UF.Config:WithTheme(theme, Build, self, style)
	self:Update()
end

function Preview:Update()
	if not self.theme then return end
	UF.Config:WithTheme(self.theme, Fill, self, self.opts.animated and self.time or nil)
end

function Preview:Tick(elapsed)
	if not self.opts.animated or not self.theme then return end
	self.time, self.elapsed = self.time + elapsed, self.elapsed + elapsed
	if self.elapsed < FRAME_INTERVAL then return end
	self.elapsed = 0
	self:Update()
end

function Preview:Release()
	for _, frame in ipairs(self.frames) do frame:Release() end
	self.frames, self.style, self.theme = {}, nil, nil
end
