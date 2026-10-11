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
		tickStatic = true, -- test casts finish and restore the frozen preview
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
			{ key = "start", type = "action", label = "Start cast", hidden = NotFake },
			{ key = "interrupt", type = "action", label = "Interrupt", hidden = NotFake },
			{ key = "fail", type = "action", label = "Fail", hidden = NotFake },
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
		update = function(handle, d, es)
			if d.source == "static" then
				Preview(handle.parts.castbar, d)
			elseif Data.IsLive(d) then
				es.live = es.live or {}
				UF.Cast.Refresh(handle.parts.castbar, es.live, d.source) -- a cast in progress, else hidden
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
		-- Live casts use the same state machine as the unit frames, so names,
		-- icons, timings and the interruptible flag may all be secret.
		events = UF.Cast.EVENTS,
		onEvent = function(handle, _, es, event, unit, ...)
			es.live = es.live or {}
			UF.Cast.Handle(handle.parts.castbar, es.live, event, unit, ...)
		end,
	},
})
