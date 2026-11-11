local _, wb = ...
local UF = UnitFrames
local Workbench = wb.Workbench
local C = UF.Components

-- Edits the global theme (saved in the UnitFrames profile). Every component
-- that inherits from it updates live, including whatever else is on screen.
local function ThemeTarget()
	local Config = UF.Config
	return {
		schema = UF.Theme.schema,
		get = function(path)
			return Config:GetThemeOverride(path)
		end,
		set = function(path, value)
			Config:SetThemeValue(path, value)
		end,
		resolved = function()
			return UF.Schema.Resolve(UF.Theme.schema, Config:GetTheme(), nil)
		end,
		source = function(path, reset)
			return UF.Schema.Source(UF.Theme.schema, Config:GetThemeOverrides(), nil, path, reset)
		end,
	}
end

local LAUNCHER_SCHEMA = {
	{ key = "minimapIcon", type = "toggle", label = "Show minimap icon", default = true,
		tooltip = "Show the UnitFrames button on the minimap for every character. Right-click the button to hide it again; /uf minimap toggles it too." },
}

local function LauncherTarget()
	local Launcher = UF.Launcher
	return {
		schema = LAUNCHER_SCHEMA,
		get = function()
			if Launcher:IsMinimapShown() then return nil end
			return false
		end,
		set = function(_, value)
			Launcher:SetMinimapShown(value ~= false)
			return true
		end,
		resolved = function()
			return { minimapIcon = Launcher:IsMinimapShown() }
		end,
	}
end

Workbench:Register({
	id = "theme",
	category = "Shared appearance",
	name = "Shared appearance",
	scope = "Shared appearance defaults",
	settingsTargets = function() return {
		{ id = "style", schema = UF.Theme.schema, scope = "Shared appearance defaults" },
		{ id = "launcher", schema = LAUNCHER_SCHEMA, scope = "All characters on this account", target = LauncherTarget },
	} end,
	refreshOn = { { "MinimapIconChanged", notifyOnly = true } },
	size = { 240, 28 },
	create = function(stage)
		local bar = C.Bar:New(stage, {}, {
			segments = { { key = "absorb", label = "Absorb shields", mode = "append", colorInherit = "colors.absorb" } },
		})
		bar:SetRange(0, 100)
		bar:SetValue(70)
		bar:SetSegmentValue("absorb", 15)
		local text = C.Text:New(bar:GetTextParent(), {})
		text:SetPoint("CENTER", bar:GetTextParent(), "CENTER")
		text:SetText("Theme preview")
		local auras = C.Auras:New(bar:GetFrame(), {})
		auras:ShowSample({ buffs = UF.Units.SAMPLE.buffs, debuffs = UF.Units.SAMPLE.debuffs })
		return Workbench.Composite({
			{ key = "bar", label = "Bar", component = bar },
			{ key = "text", label = "Text", component = text },
			{ key = "auras", label = "Aura icons", component = auras },
		}, bar:GetFrame())
	end,
	defaultConfig = { bar = { border = { enabled = true } },
		auras = { buffs = { max = 7, size = 22 }, debuffs = { max = 5, size = 22 } } },
	styleTarget = ThemeTarget,
})
