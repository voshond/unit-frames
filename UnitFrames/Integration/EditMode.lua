local _, ns = ...

--[[
Edit Mode integration through LibEditMode: our frames can be selected and
dragged in Blizzard's Edit Mode. Positions are stored per Edit Mode layout,
so switching layouts (e.g. "Healer" / "DPS") moves our frames too.

The Edit Mode dialog of a frame has quick settings (width, rows on/off) and a
button that opens the full settings (the Workbench for now).
]]
local LEM = LibStub("LibEditMode", true)

local EditMode = { frames = {} }
ns.EditMode = EditMode

local pending = {}
local regenFrame = CreateFrame("Frame")
regenFrame:SetScript("OnEvent", function(self)
	self:UnregisterEvent("PLAYER_REGEN_ENABLED")
	for key in pairs(pending) do
		pending[key] = nil
		EditMode:ApplyPosition(key)
	end
end)

-- Moves a registered frame to its stored position for the current layout.
-- Unit buttons are protected, so this waits for combat to end.
function EditMode:ApplyPosition(key)
	local entry = self.frames[key]
	if InCombatLockdown() then
		pending[key] = true
		regenFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
		return
	end
	local pos = ns.Config:GetPosition(self.layout, key) or entry.default
	entry.frame:ClearAllPoints()
	entry.frame:SetPoint(pos.point, UIParent, pos.point, pos.x, pos.y)
end

-- A setting whose value lives at `path` in the unit config. Setting it back
-- to the default removes the change.
local function UnitSetting(unit, path, setting)
	setting.get = function()
		return ns.Util.GetPath(ns.Units.frames[unit].uf.resolved, path)
	end
	setting.set = function(_, value)
		if value == setting.default then
			value = nil
		end
		ns.Config:SetUnitValue(unit, path, value)
	end
	return setting
end

local function UnitSettings(unit)
	local def = ns.Units.definitions[unit]
	local settings = {
		UnitSetting(unit, "width", {
			kind = LEM.SettingType.Slider, name = "Width", default = def.width,
			minValue = 60, maxValue = 600, valueStep = 1,
		}),
	}
	for _, row in ipairs(def.rows) do
		settings[#settings + 1] = UnitSetting(unit, row.key .. ".enabled", {
			kind = LEM.SettingType.Checkbox, name = "Show " .. row.label:lower(), default = true,
		})
	end
	return settings
end

-- key: config key for the position ("player"), name: label in Edit Mode.
function EditMode:Register(frame, key, name, default)
	self.frames[key] = { frame = frame, default = default }
	self:ApplyPosition(key)
	if not LEM then
		return
	end
	LEM:AddFrame(frame, function(_, layout, point, x, y)
		ns.Config:SetPosition(layout, key, point, x, y)
	end, default, name)
	if ns.Units.definitions[key] then
		LEM:AddFrameSettings(frame, UnitSettings(key))
	end
	LEM:AddFrameSettingsButtons(frame, {
		{ text = "More settings", click = function()
			ns:OpenWorkbench("unit." .. key)
		end },
	})
end

if LEM then
	LEM:RegisterCallback("layout", function(layout)
		EditMode.layout = layout
		for key in pairs(EditMode.frames) do
			EditMode:ApplyPosition(key)
		end
	end)
end
