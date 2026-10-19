local Helpers = require("helpers")
local Mock = Helpers.Mock

local GOLDEN = dofile("tests/fixtures/formats_golden.lua")

-- Plain live values the golden fixture was generated with.
local function Plain()
	UnitExists = function() return true end
	UnitName = function() return "Jaina", "Realm" end
	UnitClass = function() return "Mage", "MAGE" end
	UnitLevel = function() return 44 end
	UnitClassification = function() return "rareelite" end
	UnitIsPlayer = function() return true end
	UnitCreatureType = function() return "Beast" end
	UnitHealth = function() return 15600 end
	UnitHealthMax = function() return 24000 end
	UnitHealthMissing = function() return 8400 end
	UnitHealthPercent = function() return 65 end
	UnitPower = function() return 0 end
	UnitPowerMax = function() return 12000 end
	UnitPowerMissing = function() return 12000 end
	UnitPowerPercent = function() return 0 end
	UnitXP = function() return 41000 end
	UnitXPMax = function() return 98000 end
	GetXPExhaustion = function() return 30000 end
	UnitCastingInfo = function() return nil end
	UnitChannelInfo = function() return nil end
	Mock.pvpInfo = {}
	Mock.resting = false
end

local SCENARIOS = {
	plain = Plain,
	["npc pvp resting"] = function()
		Plain()
		UnitIsPlayer = function() return false end
		UnitLevel = function() return -1 end
		UnitClassification = function() return "worldboss" end
		Mock.pvpInfo.player = { pvpIconAtlas = "UI-HUD-UnitFrame-SmallCircle-Horde" }
		Mock.resting = true
		UnitHealthMissing = function() return 0 end
		GetXPExhaustion = function() return nil end
		UnitXP = function() return 98000 end
	end,
	["missing identity"] = function()
		Plain()
		UnitName = function() return nil end
		UnitClass = function() return nil end
		UnitCreatureType = function() return nil end
		UnitClassification = function() return "normal" end
	end,
	casting = function()
		Plain()
		UnitCastingInfo = function() return "Fireball" end
	end,
	channel = function()
		Plain()
		UnitChannelInfo = function() return "Drain Life" end
	end,
	absent = function()
		Plain()
		UnitExists = function() return false end
	end,
}

local SAMPLES = {
	player = {},
	["no cast"] = { showCast = false },
	npc = { isPlayer = false, creatureType = "Undead", classification = "rare", pvp = "FFA", resting = true, rested = 0 },
	full = { health = 24000, power = 0, xp = 98000, pvp = "Alliance", level = 0, classification = "elite" },
}

local function Set(text)
	local set = {}
	for word in (text or ""):gmatch("%S+") do set[word] = true end
	return set
end

local function SharedSet(format)
	local set = {}
	for event in (format.events or ""):gmatch("%S+") do
		if format.sharedEvents and format.sharedEvents[event] then set[event] = true end
	end
	return set
end

describe("Text presets", function()
	local ns
	before_each(function()
		ns = Helpers.LoadAddon(true, true)
		Mock.InstallUI()
	end)

	it("keep every historical format id alongside this bar's values and full name", function()
		local ids = {}
		for _, format in ipairs(ns.Formats.list) do
			ids[format.id] = true
			assert.is_true(GOLDEN.events[format.id] ~= nil or format.id:find("^bar:") ~= nil
				or format.id == "fullname" or format.id == "threat", "new format id " .. format.id)
		end
		for id in pairs(GOLDEN.events) do assert.is_true(ids[id], "lost format id " .. id) end
	end)

	it("keep every historical live text", function()
		for name, setup in pairs(SCENARIOS) do
			setup()
			for id, expected in pairs(GOLDEN.live[name]) do
				assert.equals(expected, ns.Formats.Get(id).text("player"), name .. ": " .. id)
				assert.equals(expected, ns.oUF.Tags.Methods["uf:" .. id]("player"), name .. " tag: " .. id)
			end
		end
	end)

	it("keep every historical sample text", function()
		for name, patch in pairs(SAMPLES) do
			local values = ns.Units:GetSample("player")
			for key, value in pairs(patch) do values[key] = value end
			for id, expected in pairs(GOLDEN.sample[name]) do
				assert.equals(expected, ns.Formats.Get(id).sample(values), name .. ": " .. id)
			end
		end
	end)

	it("keep their update and shared events", function()
		for id, expected in pairs(GOLDEN.events) do
			local format = ns.Formats.Get(id)
			assert.same(Set(expected.events), Set(format.events), id)
			assert.same(Set(expected.shared), SharedSet(format), id)
			if expected.events ~= "" then
				assert.same(Set(expected.events), Set(ns.oUF.Tags.Events["uf:" .. id]), id)
			end
			for event in pairs(Set(expected.shared)) do
				assert.is_true(ns.oUF.Tags.SharedEvents[event], id .. ": " .. event)
			end
		end
	end)

	it("pass secret values through without inspecting them", function()
		-- The default mock client returns secret health, power, names and casts.
		UnitCastingInfo = function() return nil end
		UnitChannelInfo = function() return nil end
		for _, id in ipairs({ "name", "class", "level:name", "level:class", "level:info", "health:current",
			"health:value", "health:percent", "health:current:percent", "health:value:percent", "health:missing",
			"power:value:percent", "power:missing" }) do
			assert.is_true(Mock.IsSecret(ns.Formats.Get(id).text("target")), id)
		end
		local name = Mock.Secret("Jaina")
		UnitName = function() return name, Mock.Secret("realm") end
		assert.is_true(rawequal(name, ns.Formats.Get("name").text("target")))
		local spell = Mock.Secret("Frostbolt")
		UnitChannelInfo = function() return spell end
		for _, id in ipairs({ "cast:name", "level:class:cast", "level:info:cast" }) do
			assert.is_true(rawequal(spell, ns.Formats.Get(id).text("target")), id)
		end
	end)

	it("show player-only values only for the player", function()
		Plain()
		for _, id in ipairs({ "xp:current", "xp:value:percent", "xp:missing", "xp:rested", "resting" }) do
			assert.equals("", ns.Formats.Get(id).text("target"), id)
		end
		assert.equals("41000 / 98000 | 42%", ns.Formats.Get("xp:value:percent").text("player"))
	end)
end)

describe("Text composer", function()
	local ns, Compile
	before_each(function()
		ns = Helpers.LoadAddon(true)
		Mock.InstallUI()
		Plain()
		Compile = ns.TextTemplate.Compile
	end)

	local function Probe(ns, id, live, sample, extra)
		local source = { label = id, events = "UNIT_NAME_UPDATE", live = live, sample = sample or live }
		for k, v in pairs(extra or {}) do source[k] = v end
		ns.TextSources.Register(id, source)
	end

	it("shows a piece's affixes only with its text", function()
		local template = Compile({ pieces = {
			{ source = "name" },
			{ source = "health.missing", before = " (-", after = ")" },
			{ source = "pvp", before = " " },
		} })
		assert.equals("Jaina (-8400)", template.live("target"))
		UnitHealthMissing = function() return 0 end
		assert.equals("Jaina", template.live("target"))
		local values = ns.Units:GetSample("player")
		values.health, values.pvp = values.healthMax, "Horde"
		assert.equals("Uther |A:UI-HUD-UnitFrame-SmallCircle-Horde:0:0:0:0|a", template.sample(values))
	end)

	it("lets the engine decide affixes of secret, possibly empty text", function()
		UnitHealthMissing = function() return Mock.Secret(0) end
		local template = Compile({ pieces = { { source = "name" }, { source = "health.missing", before = " / " } } })
		assert.is_true(Mock.IsSecret(template.live("target")))
	end)

	it("keeps affix and literal text out of the format string", function()
		local template = Compile({ pieces = {
			{ literal = "%d%%" }, { source = "name", before = "%s [", after = "] $>" }, { literal = "%" },
		} })
		assert.equals("%d%%%s [Jaina] $>%", template.live("target"))
		local values = ns.Units:GetSample("player")
		assert.equals("%d%%%s [Uther] $>%", template.sample(values))
	end)

	it("compiles unknown, absent and empty pieces to empty text without events", function()
		local template = Compile({ pieces = { { source = "none" }, { source = "nope", before = "x" }, {} } })
		assert.equals("", template.live("target"))
		assert.equals("", template.sample(ns.Units:GetSample("player")))
		assert.is_nil(template.events)
		assert.is_nil(template.sharedEvents)
		assert.equals("", Compile({}).live("target"))
	end)

	it("reads no source for an absent unit", function()
		Probe(ns, "probe", function() error("read an absent unit") end)
		local template = Compile({ pieces = { { source = "probe" } }, whileCasting = "spell" })
		UnitCastingInfo = function() error("read an absent unit's cast") end
		UnitExists = function() return false end
		assert.equals("", template.live("target"))
		assert.equals("", template.live(nil))
	end)

	it("normalises missing values without truth tests", function()
		Probe(ns, "probe.nil", function() return nil end)
		Probe(ns, "probe.false", function() return false end)
		local template = Compile({ pieces = { { source = "probe.nil", before = "a" }, { literal = "|" },
			{ source = "probe.nil" } } })
		assert.equals("|", template.live("target"))
		-- Only nil counts as missing; other values reach the renderer as text.
		assert.equals("false", Compile({ pieces = { { source = "probe.false", before = "" }, { literal = "" } } })
			.live("target"))
	end)

	it("replaces the whole slot with the spell name while casting", function()
		local template = Compile({ pieces = { { source = "level" }, { literal = " " }, { source = "name" } },
			whileCasting = "spell" })
		assert.equals("44 Jaina", template.live("target"))
		UnitCastingInfo = function() return "Fireball" end
		assert.equals("Fireball", template.live("target"))
		UnitCastingInfo = function() return nil end
		UnitChannelInfo = function() return "Drain Life" end
		assert.equals("Drain Life", template.live("target"))
		local values = ns.Units:GetSample("player")
		assert.equals(values.spell, template.sample(values))
		values.showCast = false
		assert.equals("42 Uther", template.sample(values))
		local events = Set(template.events)
		assert.is_true(events.UNIT_SPELLCAST_CHANNEL_STOP and events.UNIT_NAME_UPDATE and events.UNIT_LEVEL)
	end)

	it("unions events and keeps unitless ones shared next to unit events", function()
		local template = Compile({ pieces = { { source = "name" }, { source = "xp.current", before = " " },
			{ source = "pvp", before = " " }, { source = "level", before = " " } } })
		assert.same(Set("UNIT_NAME_UPDATE PLAYER_XP_UPDATE UPDATE_EXHAUSTION PLAYER_LEVEL_UP UNIT_FACTION "
			.. "PLAYER_PVP_FLAG_CHANGED PLAYER_REGEN_ENABLED UNIT_LEVEL"), Set(template.events))
		local events = {}
		for event in template.events:gmatch("%S+") do
			assert.is_nil(events[event], "duplicate " .. event)
			events[event] = true
		end
		assert.same({ PLAYER_XP_UPDATE = true, UPDATE_EXHAUSTION = true, PLAYER_LEVEL_UP = true,
			PLAYER_PVP_FLAG_CHANGED = true, PLAYER_REGEN_ENABLED = true }, template.sharedEvents)
	end)
end)
