local Helpers = require("helpers")
local Mock = Helpers.Mock

local function Near(expected, actual, message)
	assert.is_true(math.abs(expected - actual) < 1e-9, (message or "") .. " expected " .. expected .. ", got " .. actual)
end

-- Player castbar extras: latency zone at the end of the cast and the global
-- cooldown strip (Components/CastExtras.lua).
describe("Player castbar extras #castbar", function()
	local ns, element, player, castbar
	before_each(function()
		ns = Helpers.LoadAddon(true, true)
		ns.Config:SetUnitValue("player", "castbar.enabled", true)
		Mock.InstallUI()
		element = ns.oUF.elements.UF_Castbar
		player = ns.Units.frames.player
		castbar = player.uf:GetPart("castbar")
		element.enable(player, "player")
	end)

	local function PlainCast(startMs, endMs)
		_G.UnitCastingInfo = function()
			return "Fireball", nil, 135812, startMs, endMs, false, nil, false, 133, 77
		end
		_G.UnitChannelInfo = function()
			return "Drain Life", nil, 136169, startMs, endMs, false, false, 689, false, 0, 78
		end
	end

	local function Fire(event, ...)
		element.update(player, event, "player", ...)
	end

	local function Zone()
		return castbar.latency.bar
	end

	it("offers the extras on the player castbar only", function()
		local function Has(unit, key)
			return ns.Schema.Find(ns.Units:GetSchema(unit), "castbar." .. key) ~= nil
		end
		assert.is_true(Has("player", "latency"))
		assert.is_true(Has("player", "gcd"))
		for _, unit in ipairs({ "pet", "target", "targettarget", "focus" }) do
			assert.is_false(Has(unit, "latency"), unit)
			assert.is_false(Has(unit, "gcd"), unit)
			assert.is_nil(ns.Units.frames[unit].uf:GetPart("castbar").latency, unit)
		end
	end)

	it("leaves the extras out when copying player settings", function()
		ns.Config:SetUnitValue("player", "castbar.latency.mode", "latency")
		ns.Config:SetUnitValue("player", "castbar.gcd.enabled", true)
		ns.Units:CopyPlayerSettings("target")
		local copy = ns.Config:GetUnitConfig("target").castbar or {}
		assert.is_nil(copy.latency)
		assert.is_nil(copy.gcd)
	end)

	it("fills the measured latency from the end of a cast", function()
		ns.Config:SetUnitValue("player", "castbar.latency.mode", "latency")
		PlainCast(1000, 3000)
		Fire("UNIT_SPELLCAST_SENT")
		Mock.time = Mock.time + 0.125
		Fire("UNIT_SPELLCAST_START", "guid", 133)
		local state = Zone().__state
		assert.is_true(Zone():IsShown())
		assert.same({ 0, 2 }, { state.min, state.max })
		Near(0.125, state.value)
		assert.is_true(state.reverseFill, "a cast ends at the far end")
		PlainCast(1000, 3500)
		Mock.time = Mock.time + 1
		Fire("UNIT_SPELLCAST_DELAYED", "guid", 133)
		assert.equals(2.5, state.max, "pushback lengthens the cast")
		Near(0.125, state.value, "and keeps the cast's latency")
		Fire("UNIT_SPELLCAST_STOP", "guid", 133, 77)
		assert.is_false(Zone():IsShown())
	end)

	it("puts the zone on the draining start of a channel and follows reverse fill", function()
		PlainCast(0, 5000)
		Fire("UNIT_SPELLCAST_CHANNEL_START", "guid", 689)
		assert.is_false(Zone().__state.reverseFill)
		ns.Config:SetUnitValue("player", "castbar.bar.reverseFill", true)
		Fire("UNIT_SPELLCAST_CHANNEL_UPDATE", "guid", 689)
		assert.is_true(Zone().__state.reverseFill)
		PlainCast(0, 2000)
		Fire("UNIT_SPELLCAST_START", "guid", 133)
		assert.is_false(Zone().__state.reverseFill)
	end)

	it("defaults to the spell queue window, with latency as the alternative", function()
		PlainCast(0, 2000)
		Fire("UNIT_SPELLCAST_START", "guid", 133)
		assert.equals(0.4, Zone().__state.value)
		ns.Config:SetUnitValue("player", "castbar.latency.mode", "latency")
		Fire("UNIT_SPELLCAST_START", "guid", 133)
		assert.equals(0.08, Zone().__state.value, "world latency without a sent cast")
	end)

	it("stays hidden with secret cast times or when turned off", function()
		Fire("UNIT_SPELLCAST_START", "guid", 133)
		assert.is_true(castbar:GetFrame():IsShown())
		assert.is_false(Zone():IsShown())
		PlainCast(0, 2000)
		ns.Config:SetUnitValue("player", "castbar.latency.enabled", false)
		Fire("UNIT_SPELLCAST_START", "guid", 133)
		assert.is_false(Zone():IsShown())
	end)

	it("registers the unitless cooldown event on the player castbar only", function()
		assert.is_true(player.__state.events.SPELL_UPDATE_COOLDOWN)
		element.disable(player)
		assert.is_nil(player.__state.events.SPELL_UPDATE_COOLDOWN)
		local target = ns.Units.frames.target
		ns.Config:SetUnitValue("target", "castbar.enabled", true)
		element.enable(target, "target")
		assert.is_nil(target.__state.events.SPELL_UPDATE_COOLDOWN)
	end)

	local FROSTBOLT, EXECUTE = 116, 5308

	local function SendSpell(spellID)
		Fire("UNIT_SPELLCAST_SENT", "target", "guid", spellID)
	end

	local function GlobalCooldown(spellID, onGCD)
		Mock.cooldowns[spellID] = onGCD ~= nil and { duration = 1.5, onGCD = onGCD } or nil
		Fire("SPELL_UPDATE_COOLDOWN")
	end

	it("runs the strip from the sent spell's global cooldown while the castbar is idle", function()
		local strip = castbar.gcd.bar
		SendSpell(FROSTBOLT)
		GlobalCooldown(FROSTBOLT, true)
		assert.is_false(strip:IsShown(), "off by default")
		ns.Config:SetUnitValue("player", "castbar.gcd.enabled", true)
		GlobalCooldown(FROSTBOLT, true)
		assert.is_false(castbar:GetFrame():IsShown(), "no cast shown")
		assert.is_true(strip:IsShown())
		local timer = strip.__state.timer
		assert.equals(1.5, timer.duration.__state.length)
		assert.equals(Enum.StatusBarTimerDirection.ElapsedTime, timer.direction)
		GlobalCooldown(FROSTBOLT, nil)
		assert.is_false(strip:IsShown(), "ended")
	end)

	-- Forever has no global cooldown spell (61304): only the sent spell tells.
	it("shows nothing before a spell is sent or for a spell on its own cooldown", function()
		ns.Config:SetUnitValue("player", "castbar.gcd.enabled", true)
		Fire("SPELL_UPDATE_COOLDOWN")
		assert.is_false(castbar.gcd.bar:IsShown())
		SendSpell(EXECUTE)
		GlobalCooldown(EXECUTE, false)
		assert.is_false(castbar.gcd.bar:IsShown())
	end)

	it("accepts a secret spell ID", function()
		ns.Config:SetUnitValue("player", "castbar.gcd.enabled", true)
		local secret = Secret(FROSTBOLT)
		local query = C_Spell.GetSpellCooldown
		C_Spell.GetSpellCooldown = function(id)
			assert.is_true(Mock.IsSecret(id))
			return query(id.secretValue)
		end
		SendSpell(secret)
		Mock.cooldowns[FROSTBOLT] = { duration = 1.5, onGCD = true }
		Fire("SPELL_UPDATE_COOLDOWN")
		assert.is_true(castbar.gcd.bar:IsShown())
	end)

	it("hides the strip when it, or the castbar, is turned off", function()
		ns.Config:SetUnitValue("player", "castbar.gcd.enabled", true)
		SendSpell(FROSTBOLT)
		GlobalCooldown(FROSTBOLT, true)
		ns.Config:SetUnitValue("player", "castbar.gcd.enabled", false)
		assert.is_false(castbar.gcd.bar:IsShown())
		ns.Config:SetUnitValue("player", "castbar.gcd.enabled", true)
		GlobalCooldown(FROSTBOLT, true)
		ns.Config:SetUnitValue("player", "castbar.enabled", false)
		assert.is_false(castbar.gcd.bar:IsShown())
	end)

	it("places the strip along an edge or over the whole bar", function()
		ns.Config:SetUnitValue("player", "castbar.gcd.enabled", true)
		local strip, anchor = castbar.gcd.bar, castbar:GetBar():GetStatusBar()
		local function Points()
			local points = {}
			for _, p in ipairs(strip.__state.points) do points[#points + 1] = p[1] end
			return table.concat(points, ",")
		end
		assert.equals("BOTTOMLEFT,BOTTOMRIGHT", Points())
		assert.equals(2, strip:GetHeight())
		ns.Config:SetUnitValue("player", "castbar.gcd.position", "top")
		assert.equals("TOPLEFT,TOPRIGHT", Points())
		ns.Config:SetUnitValue("player", "castbar.gcd.position", "full")
		assert.equals(anchor, strip.__state.points[1][2])
		SendSpell(FROSTBOLT)
		GlobalCooldown(FROSTBOLT, true)
		assert.is_true(strip:GetFrameLevel() > anchor:GetFrameLevel(), "above the fill")
	end)

	it("shows both in sample previews", function()
		ns.Config:SetUnitValue("player", "castbar.gcd.enabled", true)
		ns.Units:ShowSample(player.uf, ns.Units:GetSample("player"))
		assert.is_true(Zone():IsShown())
		assert.equals(0.4, Zone().__state.value, "the queue window, by default")
		ns.Config:SetUnitValue("player", "castbar.latency.mode", "latency")
		ns.Units:ShowSample(player.uf, ns.Units:GetSample("player"))
		assert.equals(0.15, Zone().__state.value, "the sample latency")
		assert.equals(1.5, Zone().__state.max)
		assert.is_true(castbar.gcd.bar:IsShown())
		assert.equals(0.4, castbar.gcd.bar:GetValue())
	end)
end)

describe("Workbench castbar extras #castbar", function()
	local wb, castbar
	before_each(function()
		local _
		_, wb = Helpers.LoadWorkbench()
		wb:Open("castbar")
		castbar = wb.handle.parts.castbar
		castbar:Apply({ gcd = { enabled = true } })
	end)

	it("previews a frozen zone and global cooldown", function()
		wb.dataTarget.set("progress", 20)
		assert.is_true(castbar.latency.bar:IsShown())
		assert.is_true(castbar.gcd.bar:IsShown())
		Near(0.4, castbar.gcd.bar:GetValue())
		wb.dataTarget.set("progress", 90)
		assert.is_false(castbar.gcd.bar:IsShown(), "the global cooldown is over")
	end)

	it("ends a test cast's global cooldown", function()
		wb:RunAction("start")
		assert.is_true(castbar.gcd.bar:IsShown())
		Mock.time = Mock.time + 2
		wb:OnUpdate(2)
		assert.is_false(castbar.gcd.bar:IsShown())
	end)

	it("follows the live global cooldown", function()
		wb.dataTarget.set("source", "player")
		Mock.FireEvent("UNIT_SPELLCAST_SENT", "player", "target", "guid", 116)
		Mock.cooldowns[116] = { duration = 1.5, onGCD = true }
		Mock.FireEvent("SPELL_UPDATE_COOLDOWN")
		assert.is_true(castbar.gcd.bar:IsShown())
		Mock.cooldowns[116] = nil
		Mock.FireEvent("SPELL_UPDATE_COOLDOWN")
		assert.is_false(castbar.gcd.bar:IsShown())
	end)
end)
