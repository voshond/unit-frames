local _, wb = ...
local UF = UnitFrames
local Workbench, Data = wb.Workbench, wb.Data
local C = UF.Components

local function Spell(d)
	return Data.SPELLS[d.spell] or Data.SPELLS[1]
end

local function FakeDuration(seconds)
	local duration = C_DurationUtil.CreateDuration()
	duration:SetTimeFromStart(GetTime(), seconds)
	return duration
end

local function StartFake(castbar, d, es, spell)
	castbar:Start({
		name = spell.name,
		icon = spell.icon,
		channel = spell.channel,
		notInterruptible = d.notInterruptible,
		duration = FakeDuration(spell.time),
	})
	es.casting = true
	es.castEnds = GetTime() + spell.time
end

-- Frozen cast for styling: shows `progress` of the selected spell.
local function Preview(castbar, d)
	local spell = Spell(d)
	local fraction = d.progress / 100
	castbar:Preview({ name = spell.name, icon = spell.icon, channel = spell.channel, notInterruptible = d.notInterruptible },
		spell.channel and 1 - fraction or fraction, string.format("%.1f", spell.time * (1 - fraction)))
end

local function NotStatic(d)
	return d.source ~= "static"
end

local function NotFake(d)
	return Data.IsLive(d)
end

Workbench:Register({
	id = "castbar",
	category = "Bars",
	name = "Castbar",
	size = { 240, 22 },
	create = function(stage)
		return Workbench.Composite({
			{ key = "castbar", label = "Castbar", component = C.Castbar:New(stage, {}) },
		})
	end,
	presets = {
		{ name = "Icon right", config = { castbar = { icon = { position = "RIGHT" } } } },
		{ name = "No icon", config = { castbar = { icon = { enabled = false } } } },
		{ name = "Flat", config = { castbar = { bar = { texture = "Solid" }, border = { border = "UnitFrames Pixel",
			size = 1, inset = 0, padding = 1, color = { 0, 0, 0, 1 } } } } },
		{ name = "No border", config = { castbar = { border = { enabled = false } } } },
		{ name = "Large", size = { 300, 30 }, config = { castbar = { name = { size = 13 }, time = { size = 13 } } } },
	},
	data = {
		schema = {
			{ key = "source", type = "select", label = "Source", default = "static", values = {
				{ "static", "Static preview" },
				{ "loop", "Animated (loop)" },
				{ "player", "Live: player" },
				{ "target", "Live: target" },
				{ "focus", "Live: focus" },
			} },
			{ key = "spell", type = "select", label = "Spell", values = Data.SpellValues, default = 1, hidden = NotFake },
			{ key = "notInterruptible", type = "toggle", label = "Not interruptible", default = false, hidden = NotFake },
			{ key = "progress", type = "range", label = "Progress %", min = 0, max = 100, step = 1, default = 60,
				hidden = NotStatic },
			{ key = "start", type = "action", label = "Start cast", hidden = NotFake,
				run = function() Workbench:RunAction("start") end },
			{ key = "interrupt", type = "action", label = "Interrupt", hidden = NotFake,
				run = function() Workbench:RunAction("interrupt") end },
			{ key = "fail", type = "action", label = "Fail", hidden = NotFake,
				run = function() Workbench:RunAction("fail") end },
		},
		actions = {
			start = function(handle, d, es)
				StartFake(handle.parts.castbar, d, es, Spell(d))
			end,
			interrupt = function(handle, _, es)
				handle.parts.castbar:Stop("interrupted")
				es.casting = false
				es.nextStart = GetTime() + 1.2
			end,
			fail = function(handle, _, es)
				handle.parts.castbar:Stop("failed")
				es.casting = false
				es.nextStart = GetTime() + 1.2
			end,
		},
		update = function(handle, d)
			if d.source == "static" then
				Preview(handle.parts.castbar, d)
			elseif Data.IsLive(d) then
				handle.parts.castbar:GetFrame():Hide() -- until the unit casts
			end
		end,
		tick = function(handle, d, es)
			if Data.IsLive(d) then
				return
			end
			local castbar = handle.parts.castbar
			local now = GetTime()
			if es.casting and now >= es.castEnds then
				es.casting = false
				castbar:Stop("success")
				es.nextStart = now + 1.2
			end
			-- Static mode: bring the preview back once a test cast has faded out.
			if d.source == "static" and not es.casting and es.nextStart and now >= es.nextStart then
				es.nextStart = nil
				Preview(castbar, d)
			end
			-- Loop: cast every spell in turn; every third one gets interrupted half way.
			if d.source == "loop" and not es.casting and now >= (es.nextStart or 0) then
				es.loopIndex = (es.loopIndex or 0) % #Data.SPELLS + 1
				StartFake(castbar, d, es, Data.SPELLS[es.loopIndex])
				es.interruptAt = es.loopIndex % 3 == 0 and now + Data.SPELLS[es.loopIndex].time / 2 or nil
			end
			if es.casting and es.interruptAt and now >= es.interruptAt then
				es.interruptAt = nil
				es.casting = false
				castbar:Stop("interrupted")
				es.nextStart = now + 1.2
			end
		end,
		events = {
			"UNIT_SPELLCAST_START", "UNIT_SPELLCAST_DELAYED", "UNIT_SPELLCAST_STOP",
			"UNIT_SPELLCAST_SUCCEEDED", "UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_INTERRUPTED",
			"UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_CHANNEL_UPDATE", "UNIT_SPELLCAST_CHANNEL_STOP",
			"UNIT_SPELLCAST_INTERRUPTIBLE", "UNIT_SPELLCAST_NOT_INTERRUPTIBLE",
		},
		-- Live casts: names, icons, timings and the interruptible flag may all be
		-- secret. Only type() is used to check for "no cast".
		onEvent = function(handle, _, es, event, unit)
			local castbar = handle.parts.castbar
			if event == "UNIT_SPELLCAST_START" or event == "UNIT_SPELLCAST_DELAYED" then
				local name, _, texture, _, _, _, _, notInterruptible = UnitCastingInfo(unit)
				if type(name) == "nil" then
					return
				end
				castbar:Start({ name = name, icon = texture, notInterruptible = notInterruptible,
					duration = UnitCastingDuration(unit) })
				es.casting, es.channel = true, false
			elseif event == "UNIT_SPELLCAST_CHANNEL_START" or event == "UNIT_SPELLCAST_CHANNEL_UPDATE" then
				local name, _, texture, _, _, _, notInterruptible = UnitChannelInfo(unit)
				if type(name) == "nil" then
					return
				end
				castbar:Start({ name = name, icon = texture, channel = true, notInterruptible = notInterruptible,
					duration = UnitChannelDuration(unit) })
				es.casting, es.channel = true, true
			elseif event == "UNIT_SPELLCAST_INTERRUPTED" and es.casting then
				castbar:Stop("interrupted")
				es.casting = false
			elseif event == "UNIT_SPELLCAST_FAILED" and es.casting and not es.channel then
				castbar:Stop("failed")
				es.casting = false
			elseif (event == "UNIT_SPELLCAST_SUCCEEDED" and not es.channel or event == "UNIT_SPELLCAST_STOP"
				or event == "UNIT_SPELLCAST_CHANNEL_STOP") and es.casting then
				castbar:Stop("success")
				es.casting = false
			elseif event == "UNIT_SPELLCAST_INTERRUPTIBLE" or event == "UNIT_SPELLCAST_NOT_INTERRUPTIBLE" then
				castbar:ApplyCastColor({ channel = es.channel, notInterruptible = event == "UNIT_SPELLCAST_NOT_INTERRUPTIBLE" })
			end
		end,
	},
})
