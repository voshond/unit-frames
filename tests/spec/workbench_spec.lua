--[[
Smoke test of the Workbench against the mock client: builds the window, opens
every entry, drives every data source (live sources return fake secrets) and
operates every inspector control. Catches runtime errors in UI code that
otherwise only shows up in game.
]]
local Helpers = require("helpers")
local Mock = Helpers.Mock

-- Simulates a user changing an inspector row.
local function Operate(inspector)
	for _, row in ipairs(inspector.page.rows) do
		local opt, control = row.opt, row.control
		if control then
			local onChange = control.opts.onChange
			if opt.type == "toggle" then
				onChange(not control:GetValue())
			elseif opt.type == "range" then
				onChange(opt.min or 0)
			elseif opt.type == "select" then
				local values = control:GetValues()
				onChange(values[#values][1])
			elseif opt.type == "color" then
				onChange({ 0.1, 0.2, 0.3, 0.4 })
			elseif opt.type == "text" then
				onChange("changed")
			elseif opt.type == "action" then
				control.opts.onClick(control)
			else -- media
				local values = control:GetValues()
				onChange(values[1][1])
			end
			if row.reset and row.reset:IsShown() then
				row.reset:RunScript("OnClick")
			end
		end
	end
end

local function Tick(workbench, seconds)
	local step = 0.1
	for _ = 1, math.floor(seconds / step) do
		Mock.time = Mock.time + step
		workbench:OnUpdate(step)
	end
end

describe("Workbench", function()
	local ns, workbench
	before_each(function()
		ns, workbench = Helpers.LoadWorkbench()
		workbench:Toggle()
	end)

	it("builds and selects the first entry", function()
		assert.is_not_nil(workbench.window)
		assert.equals("unit.player", workbench.entry.id)
	end)

	it("opens every entry and drives every data source", function()
		for _, entry in ipairs(workbench.order) do
			assert.has_no_error(function()
				workbench:Select(entry.id)
				Tick(workbench, 0.5)
				if entry.data then
					local sourceOpt = ns.Schema.Find(entry.data.schema, "source")
					for _, choice in ipairs(ns.Schema.GetValues(sourceOpt)) do
						workbench.dataTarget.set("source", choice[1])
						Tick(workbench, 6)
					end
				end
			end, entry.id)
		end
	end)

	it("handles every control in every section of every entry", function()
		local sections = 0
		for _, entry in ipairs(workbench.order) do
			workbench:Select(entry.id)
			for _, item in ipairs(workbench.sections) do
				if not item.header then
					assert.has_no_error(function()
						workbench:SelectSection(item.id)
						Operate(workbench.inspector)
						Tick(workbench, 0.2)
					end, entry.id .. " / " .. item.id)
					sections = sections + 1
				end
			end
		end
		assert.is_true(sections > 40, "expected many sections, got " .. sections)
	end)

	it("lists the settings tree as sections, with data first", function()
		workbench:Select("unit.player")
		local ids = {}
		for _, item in ipairs(workbench.sections) do
			ids[#ids + 1] = item.id or ("[" .. item.text .. "]")
		end
		assert.equals("@data", ids[1])
		assert.equals("", ids[2], "top-level options (width, spacing)")
		local text = table.concat(ids, ",")
		assert.is_not_nil(text:find("health.bar.background", 1, true))
		assert.is_not_nil(text:find("[Segments]", 1, true), "groups with only sub-groups are headers")
		workbench:SelectSection("health.belowLeft")
		assert.equals("Health > Small text below left", workbench.sectionTitle:GetText())
	end)

	it("previews fonts in menus without SetFont (forbidden there)", function()
		local dropdown = ns.Widgets.Dropdown:New(CreateFrame("Frame"), {
			values = ns.Widgets.Dropdown.MediaValues("font"), preview = "font",
		})
		local radio = dropdown.dropdown.__state.menu.__state.elements[1]
		-- Like the menu compositor: SetFont on its font strings raises an error.
		local fontString = CreateFrame("Frame"):CreateFontString()
		fontString.SetFont = function() error("Use of function 'SetFont' is disallowed") end
		assert.has_no_error(function()
			for _, init in ipairs(radio.__state.initializers) do
				init({ fontString = fontString })
			end
		end)
	end)

	it("remembers the section per entry", function()
		workbench:Select("bar.power")
		workbench:SelectSection("row.right")
		workbench:Select("castbar")
		workbench:Select("bar.power")
		assert.equals("row.right", workbench.state.section)
	end)

	it("applies presets", function()
		for _, entry in ipairs(workbench.order) do
			workbench:Select(entry.id)
			for _, preset in ipairs(entry.presets or {}) do
				assert.has_no_error(function()
					workbench:ApplyPreset(preset)
				end, entry.id .. " / " .. preset.name)
			end
		end
	end)

	it("shows live casts with secret cast info", function()
		workbench:Select("castbar")
		workbench.dataTarget.set("source", "player")
		local castbar = workbench.handle.parts.castbar
		assert.has_no_error(function()
			Mock.FireEvent("UNIT_SPELLCAST_START", "player")
			Mock.FireEvent("UNIT_SPELLCAST_NOT_INTERRUPTIBLE", "player")
			Mock.FireEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
			Mock.FireEvent("UNIT_SPELLCAST_CHANNEL_START", "player")
			Mock.FireEvent("UNIT_SPELLCAST_CHANNEL_STOP", "player")
		end)
		assert.is_true(Mock.IsSecret(castbar.nameText.frame:GetText()) or castbar.nameText.frame:GetText() ~= nil)
	end)

	it("edits the global theme and restyles components", function()
		workbench:Select("bar.health")
		local bar = workbench.handle.parts.row:GetBar()
		workbench:Select("theme")
		workbench.styleTarget.set("barTexture", "Solid")
		assert.equals("Solid", ns.Config:GetTheme().barTexture)
		assert.equals([[Interface\Buttons\WHITE8X8]], workbench.handle.parts.bar.bar.__state.texture)
		workbench.styleTarget.set("barTexture", nil)
		assert.equals("Blizzard", ns.Config:GetTheme().barTexture)
		assert.is_not_nil(bar)
	end)

	it("toggles forced restrictions and resets them on close", function()
		local cvars = {}
		C_CVar.SetCVar = function(name, value) cvars[name] = value end
		workbench.secretCheck.opts.onChange(true)
		assert.equals("1", cvars.addonCombatRestrictionsForced)
		workbench.window:GetFrame():RunScript("OnHide")
		assert.equals("0", cvars.addonCombatRestrictionsForced)
	end)
end)
