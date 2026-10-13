local Helpers = require("helpers")
local Mock = Helpers.Mock

local function Values(list)
	local out = {}
	for _, entry in ipairs(list) do out[entry[1]] = true end
	return out
end

describe("Text source options", function()
	local ns, Compile
	before_each(function()
		ns = Helpers.LoadAddon(true)
		Mock.InstallUI()
		UnitHealth = function() return 1234567 end
		UnitHealthMax = function() return 2000000 end
		Compile = ns.TextTemplate.Compile
	end)

	local function Text(piece, unit)
		return Compile({ pieces = { piece } }).live(unit or "target")
	end

	it("formats numbers short, full or plain, also for secret values", function()
		assert.equals("1234567", Text({ source = "health.current" }), "the mock abbreviates nothing")
		assert.equals("1,234,567", Text({ source = "health.current", number = "full" }))
		assert.equals("2,000,000", Text({ source = "health.max", number = "full" }))
		assert.equals("1234567", Text({ source = "health.current", number = "plain" }))
		local values = ns.Units:GetSample("player")
		values.health = 15600
		assert.equals("15,600", Compile({ pieces = { { source = "health.current", number = "full" } } }).sample(values))
		UnitHealth = function() return Mock.Secret(5) end
		for _, style in ipairs({ "short", "full", "plain" }) do
			assert.is_true(Mock.IsSecret(Text({ source = "health.current", number = style })), style)
		end
	end)

	it("shows percentages with or without a decimal", function()
		UnitHealthPercent = function() return 65.43 end
		assert.equals("65%", Text({ source = "health.percent" }))
		assert.equals("65.4%", Text({ source = "health.percent", decimals = 1 }))
		local values = ns.Units:GetSample("player")
		values.health, values.healthMax = 1, 3
		assert.equals("33%", Compile({ pieces = { { source = "health.percent" } } }).sample(values))
		assert.equals("33.3%", Compile({ pieces = { { source = "health.percent", decimals = 1 } } }).sample(values))
		UnitHealthPercent = function() return Mock.Secret(65) end
		assert.is_true(Mock.IsSecret(Text({ source = "health.percent", decimals = 1 })))
	end)

	it("shows the missing percent natively and nothing at full", function()
		local curve
		UnitHealthPercent = function(_, _, c) curve = c; return 35 end
		assert.equals("35%", Text({ source = "health.missingPercent" }))
		assert.equals(100, curve:Evaluate(0))
		assert.equals(0, curve:Evaluate(1))
		UnitHealthPercent = function() return 0 end
		assert.equals("", Text({ source = "health.missingPercent", before = " -" }))
		UnitHealthPercent = function() return Mock.Secret(0) end
		assert.is_true(Mock.IsSecret(Text({ source = "health.missingPercent", before = " -" })))
		local values = ns.Units:GetSample("player")
		local template = Compile({ pieces = { { source = "health.missingPercent", before = "-" } } })
		values.health, values.healthMax = 24000, 24000
		assert.equals("", template.sample(values))
		values.health = 15600
		assert.equals("-35%", template.sample(values))
		assert.equals("76%", Compile({ pieces = { { source = "xp.missingPercent" } } }).live("player"),
			"plain player XP: 1200 of 5000")
	end)

	it("keeps templates apart only where an option applies", function()
		local Signature = ns.TextTemplate.Signature
		local function Of(piece) return Signature({ pieces = { piece } }) end
		assert.is_true(Of({ source = "health.max" }) == Of({ source = "health.max", number = "short" }))
		assert.is_false(Of({ source = "health.max" }) == Of({ source = "health.max", number = "full" }))
		assert.is_true(Of({ source = "name" }) == Of({ source = "name", number = "full", decimals = 1 }),
			"options a source doesn't use are ignored")
		assert.is_false(Of({ source = "health.percent" }) == Of({ source = "health.percent", decimals = 1 }))
	end)
end)

describe("Status and identity sources", function()
	local ns
	before_each(function()
		ns = Helpers.LoadAddon(true)
		Mock.InstallUI()
	end)

	it("show offline before dead, dead also for ghosts, and nothing for opaque states", function()
		local template = ns.TextTemplate.Compile({ pieces = { { source = "name" }, { source = "status", before = " - " } } })
		UnitName = function() return "Jaina" end
		assert.equals("Jaina", template.live("party1"))
		Mock.dead.party1 = true
		assert.equals("Jaina - Dead", template.live("party1"))
		Mock.dead.party1, Mock.ghosts.party1 = false, true
		assert.equals("Jaina - Dead", template.live("party1"))
		UnitIsConnected = function() return false end
		assert.equals("Jaina - Offline", template.live("party1"))
		UnitIsConnected = function() return Mock.Secret(false) end
		UnitIsGhost = function() return Mock.Secret(true) end
		assert.equals("Jaina", template.live("party1"))
		local values = ns.Units:GetSample("player")
		values.status = "offline"
		assert.equals("Uther - Offline", template.sample(values))
		assert.is_true(template.sharedEvents.PLAYER_UNGHOST)
		assert.is_nil(template.sharedEvents.UNIT_CONNECTION)
	end)

	it("shows the creature type on its own", function()
		UnitCreatureType = function() return Mock.Secret("Beast") end
		assert.is_true(Mock.IsSecret(ns.TextTemplate.Compile({ pieces = { { source = "creatureType" } } }).live("target")))
	end)
end)

describe("This bar's values", function()
	local ns
	before_each(function()
		ns = Helpers.LoadAddon(true, true)
		Mock.InstallUI()
		UnitHealth = function() return 15600 end
		UnitHealthMax = function() return 24000 end
		UnitPower = function() return 300 end
		UnitPowerMax = function() return 600 end
	end)

	local function Slot(unit, row, key)
		return ns.Units.frames[unit].uf:GetRow(row):GetText(key)
	end

	it("resolve to the slot's own bar and share its templates", function()
		ns.Config:SetUnitValue("target", "health.right.format", "bar:value")
		ns.Config:SetUnitValue("target", "power.right.format", "bar:value")
		assert.equals("15600 / 24000", Slot("target", "health", "right"):GetTemplate().live("target"))
		assert.equals("300 / 600", Slot("target", "power", "right"):GetTemplate().live("target"))
		ns.Config:SetUnitValue("player", "experience.center.format", "bar:value")
		assert.equals("1200 / 5000", Slot("player", "experience", "center"):GetTemplate().live("player"))
		-- Resolved before sharing: the same template as the explicit custom pieces.
		ns.Config:SetUnitValue("focus", "power.left.format", "custom")
		ns.Config:SetUnitValue("focus", "power.left.piece1.source", "power.current")
		ns.Config:SetUnitValue("focus", "power.left.piece2.source", "power.max")
		ns.Config:SetUnitValue("focus", "power.left.piece2.before", " / ")
		assert.equals(Slot("target", "power", "right"):GetTemplate(), Slot("focus", "power", "left"):GetTemplate())
		-- Bound through handles (their shared tags have no bar).
		local frame = ns.Units.frames.target
		local fs = Slot("target", "health", "right"):GetFrame()
		local handle = ns.TextTags.GetHandle(fs)
		assert.equals("[" .. handle .. "]", frame.tags[fs])
		assert.equals("UNIT_HEALTH UNIT_MAXHEALTH UNIT_CONNECTION", ns.oUF.Tags.Events[handle])
		assert.equals("", ns.Formats.Get("bar:value").text("target"))
	end)

	it("convert to custom pieces as this bar's values", function()
		ns.Config:SetUnitValue("target", "power.right.format", "bar:current:percent")
		ns.Config:SetUnitValue("target", "power.right.format", "custom")
		local saved = ns.Config:GetUnitConfig("target").power.right
		assert.equals("bar.current", saved.piece1.source)
		assert.same({ source = "bar.percent", before = " | ", after = "" }, saved.piece2)
		local values = ns.Units:GetSample("target")
		assert.equals("70 | 70%", Slot("target", "power", "right"):GetTemplate().sample(values))
	end)

	it("are offered only on bars, with their options", function()
		local schema = ns.Units:GetSchema("target")
		local sources = Values(ns.Schema.GetValues(ns.Schema.Find(schema, "health.left.piece1.source")))
		assert.is_true(sources["bar.current"] and sources["bar.missingPercent"] and sources.status)
		assert.is_true(Values(ns.Schema.GetValues(ns.Schema.Find(schema, "power.left.format")))["bar:value"])
		local castName = ns.Components.Text.BuildSchema({ formats = ns.Formats.HEALTH })
		local free = Values(ns.Schema.GetValues(ns.Schema.Find(castName, "piece1.source")))
		assert.is_nil(free["bar.current"], "no bar, no bar values")
		assert.is_nil(Values(ns.Schema.GetValues(ns.Schema.Find(castName, "format")))["bar:value"])
		local number = ns.Schema.Find(schema, "health.left.piece1.number")
		assert.is_false(number.hidden({ source = "bar.max" }))
		assert.is_true(number.hidden({ source = "bar.percent" }))
		assert.is_false(ns.Schema.Find(schema, "health.left.piece1.decimals").hidden({ source = "bar.percent" }))
	end)

	it("work on ClickGrid group bars", function()
		local UF, CG = Helpers.LoadClickGrid()
		local uf = UF.Units:CreateFromDefinition(CG.definitions.member, UIParent, {
			health = { right = { enabled = true, format = "bar:percent" } } })
		local values = UF.Units:GetSample("player")
		UF.Units:ShowSample(uf, values)
		assert.equals("65%", uf:GetRow("health"):GetText("right"):GetFrame():GetText())
		uf:Release()
	end)
end)
