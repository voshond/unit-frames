local _, ns = ...

--[[
Cast state machine shared by the oUF castbar element and live previews:
turns spellcast events for one unit into Castbar Start/Stop/colour calls.
No oUF dependency; the owner keeps one `state` table per castbar.

Cast info may be secret: it goes straight into the component, and only
type() is used to check whether there is a cast. Cast IDs aren't secret.
Cast times only reach the latency zone when they are plain.

Latency is measured with GetTime() from the player's UNIT_SPELLCAST_SENT to
the cast's start; delayed casts and channel updates keep the cast's value.
]]
local Cast = {}
ns.Cast = Cast

Cast.EVENTS = {
	"UNIT_SPELLCAST_SENT",
	"UNIT_SPELLCAST_START", "UNIT_SPELLCAST_DELAYED", "UNIT_SPELLCAST_STOP",
	"UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_INTERRUPTED",
	"UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_CHANNEL_UPDATE", "UNIT_SPELLCAST_CHANNEL_STOP",
	"UNIT_SPELLCAST_INTERRUPTIBLE", "UNIT_SPELLCAST_NOT_INTERRUPTIBLE",
}

-- Unitless: the player's global cooldown (Cast.UpdateGCD).
Cast.GCD_EVENTS = { "SPELL_UPDATE_COOLDOWN" }

local CastTime = ns.CastExtras.CastTime

local function StartCast(castbar, state, unit)
	local name, _, texture, startMs, endMs, _, _, notInterruptible, _, castID = UnitCastingInfo(unit)
	if type(name) == "nil" then
		return false
	end
	castbar:Start({ name = name, icon = texture, notInterruptible = notInterruptible, duration = UnitCastingDuration(unit),
		castTime = CastTime(startMs, endMs), latency = state.latency })
	state.casting, state.channel, state.castID = true, false, castID
	return true
end

local function StartChannel(castbar, state, unit)
	local name, _, texture, startMs, endMs, _, notInterruptible, _, _, _, castID = UnitChannelInfo(unit)
	if type(name) == "nil" then
		return false
	end
	castbar:Start({ name = name, icon = texture, channel = true, notInterruptible = notInterruptible,
		duration = UnitChannelDuration(unit), castTime = CastTime(startMs, endMs), latency = state.latency })
	state.casting, state.channel, state.castID = true, true, castID
	return true
end

-- Only the cast we show may stop it: a failed second attempt (spamming a key
-- while casting) fires FAILED for the new cast ID.
local function Stop(castbar, state, result, castID)
	if state.casting and castID and castID == state.castID then
		castbar:Stop(result)
		state.casting = false
	end
end

-- A new cast's latency: since its UNIT_SPELLCAST_SENT, if there was one.
local function TakeLatency(state)
	state.latency = state.sentAt and GetTime() - state.sentAt or nil
	state.sentAt = nil
end

-- The player's global cooldown on castbars that show it. Forever has no
-- global cooldown spell (61304 is unknown): like Blizzard's cooldown code, ask
-- whether the last sent spell is on the global cooldown. isOnGCD is never
-- secret and holds while handling SPELL_UPDATE_COOLDOWN; the spell ID may be
-- secret, which these functions accept. A spell with its own, longer cooldown
-- doesn't report the global one.
function Cast.UpdateGCD(castbar, state)
	if not castbar:WantsGCD() then
		return
	end
	local spell = state.gcdSpell
	local cooldown = spell and C_Spell.GetSpellCooldown(spell)
	if cooldown and cooldown.isOnGCD then
		castbar:StartGCD(C_Spell.GetSpellCooldownDuration(spell))
	else
		castbar:StopGCD()
	end
end

-- Shows the unit's current cast or channel, else hides the castbar
-- (refreshes and unit changes).
function Cast.Refresh(castbar, state, unit)
	if not (StartCast(castbar, state, unit) or StartChannel(castbar, state, unit)) then
		state.casting = false
		castbar:Hide()
	end
end

-- Event payloads after the unit: SENT: target, castGUID, spellID; others castGUID, spellID, then
--   STOP: castID | CHANNEL_STOP: interruptedBy, castID
--   FAILED: castID | INTERRUPTED: interruptedBy, castID      (same as oUF's Castbar)
-- Events outside Cast.EVENTS and Cast.GCD_EVENTS refresh.
function Cast.Handle(castbar, state, event, unit, _, _, arg3, arg4)
	if event == "UNIT_SPELLCAST_SENT" then
		state.sentAt, state.gcdSpell = GetTime(), arg3
	elseif event == "SPELL_UPDATE_COOLDOWN" then
		Cast.UpdateGCD(castbar, state)
	elseif event == "UNIT_SPELLCAST_START" then
		TakeLatency(state)
		StartCast(castbar, state, unit)
	elseif event == "UNIT_SPELLCAST_CHANNEL_START" then
		TakeLatency(state)
		StartChannel(castbar, state, unit)
	elseif event == "UNIT_SPELLCAST_DELAYED" then
		StartCast(castbar, state, unit)
	elseif event == "UNIT_SPELLCAST_CHANNEL_UPDATE" then
		StartChannel(castbar, state, unit)
	elseif event == "UNIT_SPELLCAST_INTERRUPTED" then
		Stop(castbar, state, "interrupted", arg4)
	elseif event == "UNIT_SPELLCAST_FAILED" then
		Stop(castbar, state, "failed", arg3)
	elseif event == "UNIT_SPELLCAST_STOP" then
		Stop(castbar, state, "success", arg3)
	elseif event == "UNIT_SPELLCAST_CHANNEL_STOP" then
		Stop(castbar, state, arg3 and "interrupted" or "success", arg4)
	elseif event == "UNIT_SPELLCAST_INTERRUPTIBLE" or event == "UNIT_SPELLCAST_NOT_INTERRUPTIBLE" then
		if state.casting then
			castbar:ApplyCastColor({ channel = state.channel, notInterruptible = event == "UNIT_SPELLCAST_NOT_INTERRUPTIBLE" })
		end
	else
		Cast.Refresh(castbar, state, unit)
	end
end
