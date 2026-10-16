local Helpers = require("helpers")
local Mock = Helpers.Mock

describe("Category auras", function()
	local ns, frame, uf, icons
	local KEYS = { "crowdControl", "bigDefensive", "externalDefensive", "important" }
	before_each(function()
		ns = Helpers.LoadAddon(true, true)
		Mock.InstallUI()
		frame = ns.Units.frames.target
		uf = frame.uf
		icons = uf:GetPart("categoryAuras")
	end)

	local function Slot(key)
		return icons.container.__state.slots[key]
	end

	local function Level(key)
		return icons.buttons[key]:GetFrameLevel()
	end

	it("offers and binds the part on every unit", function()
		for _, unit in ipairs(ns.Units.order) do
			local live = ns.Units.frames[unit]
			assert.is_not_nil(ns.Schema.Find(live.uf:GetSchema(), "categoryAuras.anchor"))
			assert.equals(live.uf:GetPart("categoryAuras"), live.UF_CategoryAuras)
			assert.is_true(live:IsElementEnabled("UF_CategoryAuras"))
		end
		ns.Config:SetUnitValue("target", "categoryAuras.enabled", false)
		assert.is_false(frame:IsElementEnabled("UF_CategoryAuras"))
		assert.is_false(icons.container:IsEnabled())
	end)

	it("registers one native slot per category with its filter", function()
		assert.equals("HARMFUL|CROWD_CONTROL", Slot("crowdControl").filter)
		assert.equals("HELPFUL|BIG_DEFENSIVE", Slot("bigDefensive").filter)
		assert.equals("HELPFUL|EXTERNAL_DEFENSIVE", Slot("externalDefensive").filter)
		assert.equals("HELPFUL|IMPORTANT", Slot("important").filter)
		assert.is_true(Slot("crowdControl").enabled)
		assert.is_false(Slot("important").enabled, "important buffs are opt-in")
		ns.Config:SetUnitValue("target", "categoryAuras.important", true)
		ns.Config:SetUnitValue("target", "categoryAuras.crowdControl", false)
		assert.is_true(Slot("important").enabled)
		assert.is_false(Slot("crowdControl").enabled)
	end)

	it("skips unchanged artwork and slot writes while observing mutated config and inherited media", function()
		ns.Perf.counters = {}
		icons:Apply(ns.Util.Copy(icons.config))
		icons:Layout(uf:GetLayoutContext())
		assert.is_nil(ns.Perf.counters.categoryArtBuild)
		assert.is_nil(ns.Perf.counters.categorySlotWrite)
		assert.is_nil(ns.Perf.counters.categoryButtonStyle)
		local config = ns.Util.Copy(icons.config)
		config.important = true
		icons:Apply(config)
		assert.equals(1, ns.Perf.counters.categorySlotWrite)
		config.important = false
		icons:Apply(config)
		assert.equals(2, ns.Perf.counters.categorySlotWrite)
		ns.Config:SetThemeValue("font", "Arial Narrow")
		assert.equals(ns.Media:Fetch("font", icons.resolved.font), icons.buttons.crowdControl.ufTime:GetFont())
		ns.Perf.counters = nil
	end)

	it("restyles when missing media becomes available without changing the config", function()
		ns.Config:SetUnitValue("target", "categoryAuras.font", "Late category font")
		local font = ns.Media:Fetch("font", "Arial Narrow")
		ns.Media.LSM:Register("font", "Late category font", font)
		ns.Units:Refresh("target")
		assert.equals(font, icons.buttons.crowdControl.ufTime:GetFont())
		ns.Config:SetUnitValue("target", "categoryAuras.border.background", "Late category background")
		ns.Perf.counters = {}
		ns.Media.LSM:Register("background", "Late category background", [[Interface\Buttons\WHITE8X8]])
		ns.Units:Refresh("target")
		assert.equals(4, ns.Perf.counters.categoryButtonStyle)
		ns.Perf.counters = nil
	end)

	it("keeps artwork private and restyles both sides of a sample to live transition", function()
		local config = ns.Util.Copy(icons.config)
		local before = ns.Util.Copy(config)
		local resolved = ns.Util.Copy(icons.resolved)
		icons:Apply(config)
		assert.same(before, config)
		assert.same(resolved, icons.resolved)
		assert.is_true(icons.art.crowdControl.border ~= icons.art.bigDefensive.border)
		icons:ShowSample({ categoryAuras = { crowdControl = ns.Units.CATEGORY_SAMPLES.crowdControl } })
		assert.is_true(icons.previewFrame:IsShown())
		ns.Perf.counters = {}
		icons:SetUnit("target")
		assert.equals(4, ns.Perf.counters.categoryButtonStyle)
		assert.is_false(icons.previewFrame:IsShown())
		assert.is_true(icons.container:IsShown())
		ns.Perf.counters = nil
	end)

	it("stacks higher categories above lower ones without reading slot visibility", function()
		for i = 1, #KEYS - 1 do
			assert.is_true(Level(KEYS[i]) > Level(KEYS[i + 1]) + 4, KEYS[i] .. " covers " .. KEYS[i + 1])
		end
		local before = {}
		for _, key in ipairs(KEYS) do before[key] = Level(key) end
		uf:Apply(uf.config)
		uf:Apply(uf.config)
		for _, key in ipairs(KEYS) do assert.equals(before[key], Level(key), "repeated applies are stable") end
	end)

	it("covers the portrait above its model and below a castbar covering it", function()
		ns.Config:SetUnitValue("target", "castbar.enabled", true)
		ns.Config:SetUnitValue("target", "castbar.placement", "portrait")
		local portrait = uf:GetPart("portrait")
		local bounds = uf:GetLayoutContext().portrait
		local size = math.min(bounds.width, bounds.height)
		for _, key in ipairs(KEYS) do
			local button = icons.buttons[key]
			assert.same({ "CENTER", portrait:GetFrame(), "CENTER", 0, 0 }, button:GetAnchor("CENTER"))
			assert.equals(size, button:GetWidth())
			assert.is_true(button:GetFrameLevel() > portrait.model:GetFrameLevel())
			assert.is_true(button:GetFrameLevel() + 5 < uf:GetPart("castbar"):GetFrame():GetFrameLevel())
		end
		assert.is_true(icons.container:IsShown())
	end)

	it("hides and disables the container while there is no portrait to cover", function()
		ns.Config:SetUnitValue("target", "portrait.enabled", false)
		assert.is_false(icons.container:IsShown())
		assert.is_false(icons.container:IsEnabled())
		ns.Config:SetUnitValue("target", "portrait.enabled", true)
		assert.is_true(icons.container:IsShown())
		assert.is_true(icons.container:IsEnabled())
	end)

	it("sits alone on edge anchors without moving the icons there", function()
		ns.Config:SetUnitValue("target", "categoryAuras.anchor", "TOP")
		ns.Config:SetUnitValue("target", "categoryAuras.size", 24)
		local host = icons:GetFrame()
		assert.same({ "CENTER", frame, "TOP", 0, 0 }, host:GetAnchor("CENTER"))
		assert.equals(24, host:GetWidth())
		for _, key in ipairs(KEYS) do
			assert.same({ "CENTER", host, "CENTER", 0, 0 }, icons.buttons[key]:GetAnchor("CENTER"))
			assert.equals(24, icons.buttons[key]:GetWidth())
			assert.is_true(icons.buttons[key]:GetFrameLevel() > uf:GetPart("castbar"):GetFrame():GetFrameLevel())
		end
		ns.Config:SetUnitValue("target", "raidTarget.anchor", "TOP")
		assert.same({ "CENTER", frame, "TOP", 0, 0 }, uf:GetPart("raidTarget"):GetFrame():GetAnchor("CENTER"))
		assert.same({ "CENTER", frame, "TOP", 0, 0 }, host:GetAnchor("CENTER"))
		ns.Config:SetUnitValue("target", "categoryAuras.anchor", "PORTRAIT")
		assert.same({ "CENTER", uf:GetPart("portrait"):GetFrame(), "CENTER", 0, 0 }, icons.buttons.crowdControl:GetAnchor("CENTER"))
	end)

	it("tints the icon frame with the category colour", function()
		local function BorderColor(key)
			return ns.Components.Backdrop.BorderTextures(icons.buttons[key].ufIconFrame)[1].__state.vertexColor
		end
		ns.Config:SetUnitValue("target", "categoryAuras.crowdControlColor", { 0.1, 0.2, 0.3, 1 })
		assert.same({ 0.1, 0.2, 0.3, 1 }, BorderColor("crowdControl"))
		ns.Config:SetUnitValue("target", "categoryAuras.categoryBorder", false)
		assert.same(ns.Util.Copy(icons.resolved.border.color), BorderColor("crowdControl"))
	end)

	it("follows the oUF unit and releases without a nil unit", function()
		frame.__unit = "focus"
		ns.oUF.elements.UF_CategoryAuras.update(frame, "UnitFramesRefresh")
		assert.equals("focus", icons.container:GetUnit())
		local container = icons.container
		uf:Release()
		assert.is_false(container:IsEnabled())
		assert.equals("focus", container:GetUnit())
	end)

	it("defers restyling native slots until combat ends", function()
		Mock.inCombat = true
		ns.Config:SetUnitValue("target", "categoryAuras.anchor", "TOP")
		assert.same({ "CENTER", uf:GetPart("portrait"):GetFrame(), "CENTER", 0, 0 }, icons.buttons.bigDefensive:GetAnchor("CENTER"))
		Mock.inCombat = false
		Mock.FireEvent("PLAYER_REGEN_ENABLED")
		assert.same({ "CENTER", icons:GetFrame(), "CENTER", 0, 0 }, icons.buttons.bigDefensive:GetAnchor("CENTER"))
	end)

	it("previews the requested category samples with live artwork", function()
		local preview = ns.Units:CreateFrame("target", CreateFrame("Frame"))
		local part = preview:GetPart("categoryAuras")
		local values = ns.Units:GetSample("target")
		ns.Units:ShowSample(preview, values)
		for _, key in ipairs(KEYS) do assert.is_false(part.samples[key]:IsShown(), "none unless requested") end
		values.categoryAuras = { crowdControl = ns.Units.CATEGORY_SAMPLES.crowdControl,
			important = ns.Units.CATEGORY_SAMPLES.important }
		ns.Units:ShowSample(preview, values)
		assert.is_true(part.samples.crowdControl:IsShown())
		assert.equals([[Interface\Icons\Ability_Gouge]], part.samples.crowdControl.ufIcon:GetTexture())
		assert.is_false(part.samples.important:IsShown(), "disabled categories stay hidden")
		assert.is_true(part.samples.crowdControl:GetFrameLevel() > part.samples.bigDefensive:GetFrameLevel())
		assert.is_false(part.container:IsShown(), "live slots stay hidden in previews")
		preview:Release()
		assert.is_false(part.container:IsEnabled())
	end)
end)

describe("Category aura Workbench previews", function()
	it("shows the chosen sample category and cycles its timer when animated", function()
		local ns, wb = Helpers.LoadWorkbench()
		wb:Toggle()
		wb:Select("unit.target")
		local part = wb.handle.parts.uf:GetPart("categoryAuras")
		assert.is_false(part.samples.crowdControl:IsShown(), "portraits stay visible by default")
		wb.dataTarget.set("categoryAuras", "bigDefensive")
		assert.is_true(part.samples.bigDefensive:IsShown())
		assert.is_false(part.samples.crowdControl:IsShown())
		wb.dataTarget.set("categoryAuras", "all")
		for _, key in ipairs({ "crowdControl", "bigDefensive", "externalDefensive" }) do
			assert.is_true(part.samples[key]:IsShown(), key)
		end
		assert.is_false(part.samples.important:IsShown(), "disabled by default")
		local static = part.samples.crowdControl.ufTime:GetText()
		wb.dataTarget.set("source", "animated")
		wb:OnUpdate(1.5)
		assert.is_true(static ~= part.samples.crowdControl.ufTime:GetText(), "animated timers cycle")
		wb.dataTarget.set("categoryAuras", "cycle")
		local function Shown()
			local shown = {}
			for key, button in pairs(part.samples) do if button:IsShown() then shown[#shown + 1] = key end end
			return table.concat(shown, ",")
		end
		local seen = {}
		for _ = 1, 10 do
			seen[Shown()] = true
			wb:OnUpdate(2)
		end
		for _, key in ipairs({ "crowdControl", "bigDefensive", "externalDefensive", "" }) do
			assert.is_true(seen[key], "cycles through " .. (key == "" and "none" or key))
		end
		wb.dataTarget.set("source", "static")
		assert.equals(3, select(2, Shown():gsub("[^,]+", "")), "static cycle shows them all")
		wb.styleTarget.set("categoryAuras.crowdControl", false)
		assert.is_false(part.samples.crowdControl:IsShown())
		assert.is_false(ns.Units.frames.target.uf:GetPart("categoryAuras").container.__state.slots.crowdControl.enabled,
			"the Style tab edits the live frame too")
	end)
end)
