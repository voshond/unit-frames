local Helpers = require("helpers")
local Mock = Helpers.Mock

describe("Cropped aura icon row", function()
	local ns, uf, bar
	before_each(function()
		ns = Helpers.LoadAddon(true, true)
		uf = ns.Units:CreateFromDefinition(ns.Units:GetDefinition("target"), UIParent, {
			portrait = { enabled = false }, castbar = { placement = "off" },
			auraBar = { enabled = true, height = 12, buffs = { size = 32 }, debuffs = { size = 32 } },
		})
		bar = uf:GetPart("auraBar")
		ns.Units:ShowSample(uf, ns.Units.SAMPLE)
	end)

	local function Samples(kind) return bar.previewContainers[kind].ufElements end
	local function Native(kind) return bar:GetContainer(kind).__state.groups[kind] end
	local function LastCall(object, method)
		local value
		for _, call in ipairs(object.__calls) do if call[1] == method then value = call[2] end end
		return value
	end

	it("is optional and can coexist with blocks or replace them", function()
		for _, unit in ipairs(ns.Units.order) do
			local frame = ns.Units.frames[unit]
			assert.is_false(frame.uf:GetPart("auraBar"):IsEnabled())
			assert.is_false(frame:IsElementEnabled("UF_AuraBar"))
		end
		assert.is_true(uf:GetPart("auras"):IsEnabled())
		local before = uf.layout.height
		uf:Apply({ portrait = { enabled = false }, castbar = { placement = "off" },
			auras = { enabled = false }, auraBar = { enabled = true, height = 12 } })
		assert.is_false(uf:GetPart("auras"):IsEnabled())
		assert.is_true(bar:IsEnabled())
		assert.equals(before, uf.layout.height)
		uf:Apply({ portrait = { enabled = false }, castbar = { placement = "off" }, auraBar = { enabled = false } })
		assert.equals(before - 12 - uf.resolved.spacing, uf.layout.height)
	end)

	it("binds independently through oUF and follows unit changes and saved toggles", function()
		local frame = ns.Units.frames.target
		ns.Config:SetUnitValue("target", "auraBar.enabled", true)
		assert.is_true(frame:IsElementEnabled("UF_AuraBar"))
		assert.is_true(frame:IsElementEnabled("UF_Auras"))
		frame.__unit = "focus"
		ns.oUF.elements.UF_AuraBar.update(frame, "UnitFramesRefresh")
		assert.equals("focus", frame.uf:GetPart("auraBar"):GetContainer("buffs"):GetUnit())
		ns.Config:SetUnitValue("target", "auras.enabled", false)
		assert.is_false(frame:IsElementEnabled("UF_Auras"))
		assert.is_true(frame:IsElementEnabled("UF_AuraBar"))
		ns.Config:SetUnitValue("target", "auraBar.enabled", false)
		assert.is_false(frame:IsElementEnabled("UF_AuraBar"))
		assert.is_false(frame.uf:GetPart("auraBar"):GetContainer("buffs"):IsEnabled())
	end)

	it("keeps square artwork centred behind fixed clipping sections", function()
		local button = Samples("buffs")[1]
		assert.equals(12, button:GetHeight())
		assert.equals(32, button:GetWidth())
		assert.equals(32, button.ufIconFrame:GetHeight())
		assert.same({ "TOPLEFT", button, "TOPLEFT", 0, 10 }, button.ufIconFrame:GetAnchor("TOPLEFT"))
		assert.same({ "BOTTOM", button, "BOTTOM", 0, 2 }, button.ufTime:GetAnchor("BOTTOM"))
		assert.equals(12, bar.sections.buffs:GetHeight())
		assert.equals(true, LastCall(bar.sections.buffs, "SetClipsChildren"))
		assert.equals(bar.sections.buffs, bar:GetContainer("buffs"):GetParent())
		assert.equals(bar.sections.buffs, bar.previewContainers.buffs:GetParent())
		assert.equals(false, LastCall(Native("buffs").frames[1], "EnableMouse"))
	end)

	it("limits horizontal capacity and fills inward from opposite ends", function()
		bar:Layout(138)
		assert.equals(2, bar.geometry.buffs.capacity)
		assert.equals(2, Native("buffs").max)
		assert.equals(2, #Samples("buffs"))
		assert.equals(2, #Samples("debuffs"))
		assert.same({ "TOPLEFT", bar.sections.buffs, "TOPLEFT", 0, 0 }, bar.previewContainers.buffs:GetAnchor("TOPLEFT"))
		assert.same({ "TOPRIGHT", bar.sections.debuffs, "TOPRIGHT", 0, 0 }, bar.previewContainers.debuffs:GetAnchor("TOPRIGHT"))
		assert.same({ "TOPRIGHT", bar.previewContainers.debuffs, "TOPRIGHT", -34, 0 }, Samples("debuffs")[2]:GetAnchor("TOPRIGHT"))
		bar:Apply({ enabled = true, height = 12, buffs = { size = 32, entrySide = "right" }, debuffs = { size = 32 } })
		assert.equals(false, bar.geometry.buffs.left)
		assert.equals(true, bar.geometry.debuffs.left)
		assert.equals(0, bar.geometry.debuffs.x)
	end)

	it("lets debuffs fill independently without moving their reserved section", function()
		assert.is_not_nil(ns.Schema.Find(bar:GetSchema(), "debuffs.entrySide"))
		bar:Layout(138)
		local x = bar.geometry.debuffs.x
		bar:Apply({ enabled = true, debuffs = { entrySide = "left" } })
		assert.equals(x, bar.geometry.debuffs.x)
		assert.is_true(bar.geometry.debuffs.left)
		assert.same({ "TOPLEFT", bar.sections.debuffs, "TOPLEFT", 0, 0 }, bar.previewContainers.debuffs:GetAnchor("TOPLEFT"))
		bar:SetUnit("target")
		assert.equals("TOPLEFT", bar:GetContainer("debuffs").__state.flowAnchor)
		bar:Apply({ enabled = true, debuffs = { entrySide = "right" } })
		assert.equals(x, bar.geometry.debuffs.x)
		assert.equals("TOPRIGHT", bar:GetContainer("debuffs").__state.flowAnchor)
		bar:Apply({ enabled = true, buffs = { entrySide = "right" } })
		assert.equals("TOPLEFT", bar:GetContainer("debuffs").__state.flowAnchor)
	end)

	it("styles a row background independently of icon borders and sample contents", function()
		assert.is_nil(bar.background:GetBackdrop())
		local config = { enabled = true, height = 12, rowBackdrop = {
			enabled = true, background = "Solid", backgroundColor = { 0.1, 0.2, 0.3, 0.6 },
		} }
		bar:Apply(config)
		bar:Layout(138)
		assert.equals(ns.Media:Fetch("background", "Solid"), bar.background:GetBackdrop().bgFile)
		assert.is_nil(bar.background:GetBackdrop().edgeFile)
		local iconBorder = Samples("buffs")[1].ufIconFrame:GetBackdrop().edgeFile
		bar:ShowSample({ buffs = {}, debuffs = {} })
		assert.is_not_nil(bar.background:GetBackdrop())
		bar:Apply({ enabled = true, rowBackdrop = { enabled = false } })
		assert.is_nil(bar.background:GetBackdrop())
		bar:ShowSample(ns.Units.SAMPLE)
		assert.equals(iconBorder, Samples("buffs")[1].ufIconFrame:GetBackdrop().edgeFile)
		assert.is_true(config.rowBackdrop.enabled)
	end)

	it("keeps an empty category's share, supports asymmetric widths and zero cells", function()
		bar:Apply({ enabled = true, height = 12, buffWidthPercent = 75 })
		bar:Layout(138)
		assert.equals(3, bar.geometry.buffs.capacity)
		assert.equals(1, bar.geometry.debuffs.capacity)
		bar:ShowSample({ buffs = {}, debuffs = ns.Units.SAMPLE.debuffs })
		assert.equals(3, bar.geometry.buffs.capacity)
		assert.equals(1, #Samples("debuffs"))
		bar:Apply({ enabled = true, height = 12, buffs = { enabled = false } })
		assert.equals(138, bar.geometry.debuffs.width)
		assert.equals(4, #Samples("debuffs"))
		bar:Layout(31)
		assert.equals(0, #Samples("debuffs"))
		assert.equals(0, Native("debuffs").max)
		assert.is_false(Native("debuffs").enabled)
		bar:Layout(32)
		assert.equals(1, #Samples("debuffs"))
		bar:Apply({ enabled = true, height = 2, padding = 2 })
		assert.equals(0, #Samples("buffs"))
		assert.equals(0, #Samples("debuffs"))
	end)

	it("sorts samples before selection, replaces removed auras and leaves fixtures untouched", function()
		local fixture = { buffs = {
			{ icon = "permanent", duration = 0, sampleNativePriority = 1, sampleRaidPriority = 3 },
			{ icon = "long", duration = 60, remaining = 30, sampleNativePriority = 3, sampleRaidPriority = 1 },
			{ icon = "short", duration = 10, remaining = 5, sampleNativePriority = 2, sampleRaidPriority = 2 },
		} }
		bar:Apply({ enabled = true, height = 12, buffs = { max = 1 }, debuffs = { enabled = false } })
		bar:ShowSample(fixture)
		assert.equals("short", Samples("buffs")[1].ufIcon:GetTexture())
		assert.equals("permanent", fixture.buffs[1].icon)
		bar:ShowSample({ buffs = { fixture.buffs[1], fixture.buffs[2] } })
		assert.equals("long", Samples("buffs")[1].ufIcon:GetTexture())
		for _, sort in ipairs({ "default", "unitDebuff" }) do
			bar:Apply({ enabled = true, height = 12, buffs = { max = 1, sort = sort }, debuffs = { enabled = false } })
			assert.equals(sort == "default" and AuraContainerSortMethod.Default or AuraContainerSortMethod.UnitFrameDebuff,
				Native("buffs").sort[1])
			bar:ShowSample(fixture)
			assert.equals(sort == "default" and "permanent" or "long", Samples("buffs")[1].ufIcon:GetTexture())
		end
	end)

	it("keeps filters and timers independent of the external icons", function()
		local config = { enabled = true, height = 12, durationPosition = "below",
			buffs = { filter = "HELPFUL|PLAYER", maxDuration = 120 } }
		bar:Apply(config)
		assert.equals("below", config.durationPosition)
		assert.equals("below", bar.resolved.durationPosition)
		assert.equals("BOTTOM", bar.artConfig.durationPosition)
		assert.equals(3, #Samples("buffs"))
		assert.equals(8, #uf:GetPart("auras").previewContainers.buffs.ufElements)
		bar:Apply({ enabled = true, height = 12, showDuration = false, dispelBorder = false })
		assert.is_false(Samples("buffs")[1].ufTime:IsShown())
		assert.is_false(Samples("debuffs")[1].ufBorder:IsShown())
		bar:Apply({ enabled = true, height = 12 })
		assert.is_true(Samples("debuffs")[1].ufBorder:IsShown())
	end)

	it("never uses native secret bounds for layout or reparents native containers", function()
		local parents = {}
		for _, kind in ipairs({ "buffs", "debuffs" }) do
			local native = bar:GetContainer(kind)
			parents[kind] = native:GetParent()
			Mock.SetEngineSize(native, Mock.Secret(999), Mock.Secret(999))
			native.GetWidth = function() error("native width read") end
			native.GetHeight = function() error("native height read") end
			assert.is_nil(native:GetScript("OnSizeChanged"))
		end
		for _, unit in ipairs({ "target", "focus", "player" }) do
			bar:SetUnit(unit)
			bar:Layout(138)
			assert.equals(unit, bar:GetContainer("buffs"):GetUnit())
			bar:ShowSample(ns.Units.SAMPLE)
			assert.is_false(bar:GetContainer("buffs"):IsEnabled())
			assert.equals(parents.buffs, bar:GetContainer("buffs"):GetParent())
		end
	end)

	it("adds a top or bottom structural row and participates in portrait spans", function()
		uf:Apply({ portrait = { enabled = true, rowSpan = 1 }, castbar = { placement = "off" },
			auraBar = { enabled = true, position = "top", height = 12 } })
		assert.equals("auraBar", uf.layout.rows[1].key)
		assert.equals(12, uf.layout.portrait.height)
		local first = uf.layout.rows[1]
		assert.equals(uf.layout.width - first.left - first.right, bar.hostWidth)
		uf:Apply({ portrait = { enabled = true, rowSpan = 0 }, castbar = { placement = "off" },
			auraBar = { enabled = true, position = "bottom", height = 12, collapse = false } })
		assert.equals("auraBar", uf.layout.rows[#uf.layout.rows].key)
		-- Collapsing keeps it beside health instead.
		uf:Apply({ portrait = { enabled = true, rowSpan = 0 }, castbar = { placement = "off" },
			auraBar = { enabled = true, position = "bottom", height = 12 } })
		assert.equals("auraBar", uf.layout.rows[2].key)
	end)

	it("uses a native assignment animation rather than an OnShow script", function()
		local button = Native("buffs").frames[1]
		assert.is_true(button.__state.auraAssignedAnimations[button.ufEntryAnimation])
		assert.equals(button.ufIconFrame, button.ufEntryAnimation:GetParent())
		assert.is_nil(button:GetScript("OnShow"))
		-- Exercise Blizzard's actual assignment implementation with mocked widgets.
		local env = setmetatable({ CustomAuraButtonSharedMixin = nil, AuraButtonPrivateMixin = {},
			CreateFromMixins = function(...) local out = {}; for i = 1, select("#", ...) do
				for k, v in pairs(select(i, ...)) do out[k] = v end end; return out end }, { __index = _G })
		local source = loadfile("examples/wow-ui-source-forever/Interface/AddOns/Blizzard_AuraContainer/Blizzard_CustomAuraButton.lua")
		-- Assignment enum comes from the generated client snapshot.
		local mode = Mock.API.Snapshot().enums.CustomAuraButtonUpdateMode
		assert.is_not_nil(mode)
		env.Enum = { CustomAuraButtonUpdateMode = mode }
		if source then
			setfenv(source, env)
			source("Blizzard_AuraContainer", {})
			local apply = env.CustomAuraButtonPrivateMixin.ApplyAuraAssignmentAnimations
			local owner = { auraAssignedAnimations = { { element = button.ufEntryAnimation } } }
			Mock.RunUntainted(function()
				apply(owner, "target", {}, mode.Assignment)
				assert.is_true(button.ufEntryAnimation:IsPlaying())
				local calls = #button.ufEntryAnimation.__calls
				apply(owner, "target", {}, mode.Update)
				assert.equals(calls, #button.ufEntryAnimation.__calls)
				apply(owner, "target", {}, mode.Assignment)
				assert.equals(calls + 2, #button.ufEntryAnimation.__calls, "pooled replacement stops and replays")
				apply(owner, "target", nil, mode.Assignment)
				assert.is_false(button.ufEntryAnimation:IsPlaying())
			end)
		end
		bar:SetUnit("target")
		bar:Apply({ enabled = true, fadeIn = false })
		assert.is_nil(button.__state.auraAssignedAnimations[button.ufEntryAnimation])
		bar:Apply({ enabled = true, fadeIn = true })
		assert.is_true(button.__state.auraAssignedAnimations[button.ufEntryAnimation])
	end)

	it("defers denied restyles in combat and clears animations/pending work on release", function()
		bar:SetUnit("target")
		Mock.inCombat = true
		bar:Apply({ enabled = true, height = 16, durationPosition = "TOP" })
		Mock.inCombat = false
		Mock.FireEvent("PLAYER_REGEN_ENABLED")
		assert.equals(16, Native("buffs").frames[1]:GetHeight())
		assert.same({ "TOP", Native("buffs").frames[1], "TOP", 0, -2 }, Native("buffs").frames[1].ufTime:GetAnchor("TOP"))
		bar:ShowSample({ buffs = ns.Units.SAMPLE.buffs, debuffs = ns.Units.SAMPLE.debuffs, animateAuras = true })
		local sample = Samples("buffs")[1]
		assert.is_true(sample.ufEntryAnimation:IsPlaying())
		bar:ShowSample({ buffs = {}, debuffs = {} })
		assert.is_false(sample.ufEntryAnimation:IsPlaying())
		bar:SetUnit("target")
		Mock.aurasSecret = true
		bar:Apply({ enabled = true, height = 10 })
		assert.is_true(ns.AfterCombat:IsQueued(bar, "restyle"))
		bar:Release()
		assert.is_false(ns.AfterCombat:IsQueued(bar, "restyle"))
		assert.is_false(bar:GetContainer("buffs"):IsEnabled())
		Mock.aurasSecret = false
		Mock.FireEvent("PLAYER_REGEN_ENABLED")
		assert.is_true(bar.released)
	end)
end)
