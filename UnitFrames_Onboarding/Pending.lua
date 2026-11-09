local _, ob = ...
local UF = UnitFrames
local Util, Schema = UF.Util, UF.Schema
local Presets = ob.Presets

--[[
The choices made so far: a preset, tweaks on top of it, a size and extras.
Nothing is saved until Apply; Style() composes a fresh style table from the
choices each time, and Resolved() its effective values for the steps.
]]
local Pending = {}
ob.Pending = Pending

local function Base(style)
	style = Util.Copy(style)
	style.theme, style.units, style.timers = style.theme or {}, style.units or {}, style.timers or {}
	for _, unit in ipairs(UF.Units.order) do style.units[unit] = style.units[unit] or {} end
	return style
end

-- Effective values of a style: { theme, units = { [unit] = resolved }, timers }.
function Pending.Resolve(style)
	local theme = Schema.Defaults(UF.Theme.schema, style.theme)
	local resolved = { theme = theme, units = {}, timers = Schema.Resolve(UF.Timers:GetSchema(), style.timers, theme) }
	for _, unit in ipairs(UF.Units.order) do
		resolved.units[unit] = Schema.Resolve(UF.Units:GetSchema(unit), style.units[unit], theme)
	end
	return resolved
end

-- A preset as shipped, for the cards in step 1.
function Pending.PresetStyle(preset)
	return Base(preset.style)
end

local function Round(value)
	return math.floor(value + 0.5)
end

-- Scales every frame's width and bar heights from their effective values.
local function Scale(style, factor)
	if factor == 1 then return end
	local resolved = Pending.Resolve(style)
	for _, unit in ipairs(UF.Units.order) do
		local values, config = resolved.units[unit], style.units[unit]
		config.width = Round(values.width * factor)
		Util.SetPath(config, "health.height", math.max(2, Round(values.health.height * factor)))
		Util.SetPath(config, "power.height", math.max(2, Round(values.power.height * factor)))
	end
end

function Pending:Reset()
	self.preset = Presets.byId.default
	self.tweaks, self.extras, self.size = {}, {}, "normal"
	self.newProfile = true
	self.result = nil
	self:Changed()
end

function Pending:Changed()
	self.style, self.resolved = nil, nil
	if self.onChange then self.onChange() end
end

-- Choosing another look starts its tweaks afresh; extras stay.
function Pending:SelectPreset(id)
	self.preset = Presets.byId[id]
	self.tweaks, self.size = {}, "normal"
	self:Changed()
end

function Pending:Style()
	if not self.style then
		local style = Base(self.preset.style)
		for _, tweak in ipairs(Presets.tweaks) do
			local value = self.tweaks[tweak.key]
			if value ~= nil and tweak.write then tweak.write(style, value) end
		end
		for _, extra in ipairs(Presets.extras) do
			local value = self.extras[extra.key]
			if value ~= nil then extra.write(style, value) end
		end
		Scale(style, Presets.SIZES[self.size])
		self.style = style
	end
	return self.style
end

function Pending:Resolved()
	if not self.resolved then self.resolved = Pending.Resolve(self:Style()) end
	return self.resolved
end

function Pending:GetTweak(key)
	return Presets.tweaksByKey[key].read(self:Resolved(), self)
end

function Pending:SetTweak(key, value)
	if key == "size" then self.size = value else self.tweaks[key] = value end
	self:Changed()
end

function Pending:GetExtra(key)
	return Presets.extrasByKey[key].read(self:Resolved())
end

function Pending:SetExtra(key, enabled)
	self.extras[key] = enabled
	self:Changed()
end

function Pending:SetNewProfile(enabled)
	self.newProfile = enabled and true or false
end

--[[
Saves the composed style through the same validation as an imported string:
into a new profile named after the look (made active, keeping positions), or
over the active profile. Returns true and the profile's name, or false and a
reason; nothing is written when it fails.
]]
function Pending:Apply()
	local apply, reason = UF.Profiles:Prepare("style", self:Style())
	if not apply then return false, reason end
	if self.newProfile then
		local ok, created = UF.Profiles:Create(UF.Profiles:UniqueName(self.preset.name .. " look"))
		if not ok then return false, created end
	end
	apply()
	UF.FirstRun:MarkDone()
	self.result = UF.Profiles:GetCurrent()
	return true, self.result
end
