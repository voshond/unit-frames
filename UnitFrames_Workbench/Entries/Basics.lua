local _, wb = ...
local UF = UnitFrames
if not UF.isDevelopment then return end
local Workbench = wb.Workbench
local C = UF.Components

-- Backdrop ------------------------------------------------------------------

Workbench:Register({
	id = "backdrop",
	category = "Basics",
	name = "Backdrop",
	size = { 220, 60 },
	create = function(stage)
		return Workbench.Composite({
			{ key = "backdrop", label = "Backdrop", component = C.Backdrop:New(stage, {}) },
		})
	end,
	presets = {
		{ name = "Chamfered", config = {} },
		{ name = "Dialog", config = { backdrop = { border = "Blizzard Dialog", size = 24, inset = 6 } } },
		{ name = "Pixel", config = { backdrop = { border = "UnitFrames Pixel", size = 1, inset = 0 } } },
	},
})

-- Native raid border --------------------------------------------------------
Workbench:Register({
	id = "raidBorder",
	category = "Basics",
	name = "Raid border",
	size = { 220, 100 },
	defaultConfig = { border = { border = "Blizzard Raid", size = 16, color = { 1, 1, 1, 1 } } },
	create = function(stage)
		return Workbench.Composite({
			{ key = "border", label = "Border", component = C.Backdrop:New(stage, {}) },
		})
	end,
	presets = {
		{ name = "Native size", config = { border = { border = "Blizzard Raid", size = 16, color = { 1, 1, 1, 1 } } }, size = { 220, 100 } },
		{ name = "Unit frame", config = { border = { border = "Blizzard Raid", size = 8, color = { 1, 1, 1, 1 } } }, size = { 220, 60 } },
		{ name = "Raid group", config = { border = { border = "Blizzard Raid", size = 16, color = { 1, 1, 1, 1 } } }, size = { 90, 200 } },
		{ name = "Tooltip", config = { border = { border = "Blizzard Tooltip", size = 12 } }, size = { 220, 100 } },
	},
})

-- Text ------------------------------------------------------------------------

Workbench:Register({
	id = "text",
	category = "Basics",
	name = "Text",
	size = { 220, 30 },
	create = function(stage)
		local backdrop = C.Backdrop:New(stage, {})
		local text = C.Text:New(backdrop:GetFrame(), {})
		text:SetPoint("LEFT", backdrop:GetFrame(), "LEFT", 6, 0)
		text:SetPoint("RIGHT", backdrop:GetFrame(), "RIGHT", -6, 0)
		return Workbench.Composite({
			{ key = "text", label = "Text", component = text },
			{ key = "backdrop", label = "Backdrop", component = backdrop },
		}, backdrop:GetFrame())
	end,
	presets = {
		{ name = "Outlined", config = { text = { outline = "OUTLINE", shadow = false } } },
		{ name = "Large", config = { text = { size = 18 } }, size = { 260, 40 } },
	},
	data = {
		schema = {
			{ key = "source", type = "select", label = "Source", default = "static", values = {
				{ "static", "Static text" },
				{ "playerName", "Live: UnitName(\"player\")" },
				{ "playerHealth", "Live: UnitHealth(\"player\")" },
			} },
			{ key = "text", type = "text", label = "Text", default = "Thrall the Warchief",
				hidden = function(d) return d.source ~= "static" end },
		},
		update = function(handle, d)
			local text = handle.parts.text
			if d.source == "static" then
				text:SetText(d.text)
			end
		end,
		-- Live values may be secret: they go straight into SetText
		-- (AbbreviateNumbers returns a secret string for a secret number).
		tick = function(handle, d)
			local text = handle.parts.text
			if d.source == "playerName" then
				text:SetText(UnitName("player"))
			elseif d.source == "playerHealth" then
				text:SetText(AbbreviateNumbers(UnitHealth("player")))
			end
		end,
	},
})
