local _, ns = ...
local Samples = {}
ns.TimerSamples = Samples

local SPEEDS = { 2.6, 1.8, 2.8 }
local PROGRESS = { 0.25, 0.7, 0.45 }

function Samples.Show(feed, time, progress, spell, combat)
	feed:Clear()
	local sample = ns.Units.SAMPLE
	spell = spell or { name = sample.spell, icon = sample.spellIcon, time = sample.castTime }
	local fraction = time and time % spell.time / spell.time or progress or 0.6
	local castbar = feed.component:GetCastbar()
	if castbar:IsEnabled() then
		castbar:Preview({ name = spell.name, icon = spell.icon, channel = spell.channel,
			castTime = spell.time, latency = sample.castLatency },
			spell.channel and 1 - fraction or fraction, string.format("%.1f", spell.time * (1 - fraction)))
		castbar:PreviewGCD(time and time % 1.5 / 1.5 or sample.gcdProgress)
	end
	for index, row in ipairs(feed.component.SWING_ROWS) do
		if feed.component:GetRow(row.key):IsEnabled() then
			feed.swings[row.key]:Preview(time and time % SPEEDS[index] / SPEEDS[index] or PROGRESS[index], SPEEDS[index])
		end
	end
	feed:RefreshVisibility(combat)
end
