local _, ns = ...
local Units, Colors = ns.Units, ns.Colors

-- Fills a UnitFrame component with plain sample values (Workbench preview,
-- later Edit Mode test frames). Values: see Units.SAMPLE.
local fillers = {}

function fillers.health(row, cfg, v)
	ns.UnitRows.SampleHealth(row, v)
	if cfg.colorMode == "class" then
		row:SetColor(Colors.Sample(v))
	elseif cfg.colorMode == "gradient" then
		row:SetColor(Colors.HealthCurve():Evaluate(v.health / v.healthMax):GetRGB())
	else
		row:ClearColor()
	end
end

function fillers.power(row, _, v)
	ns.UnitRows.SamplePower(row, v)
end

function fillers.experience(row, _, v)
	ns.UnitRows.Experience(row, v.xp, v.xpMax, v.rested)
end

-- Sample feeders per optional part (UnitFrame.PARTS).
local parts = {}

function parts.portrait(portrait)
	if portrait:IsEnabled() then
		portrait:SetUnit("player") -- the real character; there's no sample model
	end
end

-- values.showCast = false hides the sample cast (it can cover the health bar).
function parts.castbar(castbar, v)
	if not castbar:IsEnabled() then return end
	if v.showCast == false then
		castbar:Hide()
	else
		local progress = v.castProgress
		castbar:Preview({ name = v.spell, icon = v.spellIcon }, progress, string.format("%.1f", v.castTime * (1 - progress)))
	end
end

function parts.auras(auras, v)
	auras:ShowSample(v)
end

function parts.raidTarget(marker, v)
	marker:SetIndex(v.raidTarget)
end

function parts.pvp(flag, v)
	flag:SetSample(v.pvp)
end

function parts.classification(icon, v)
	icon:SetClassification(v.isPlayer == false and v.classification or nil)
end

function Units:ShowSample(uf, values)
	uf:SetRangeState(values.outOfRange ~= true, true)
	uf:SetResting(uf.spec.resting and values.resting == true, values.restingAnimated == true)
	-- values.readyCheck: "waiting", "ready", "notready" or nil; with
	-- readyCheckTime the sample loops through a whole check (tints and icon).
	local readyCheck = uf:GetReadyCheck()
	if readyCheck then
		readyCheck:Sample(values.readyCheck, values.readyCheckTime, values.readyCheckAnswerAt)
	end
	for key, row, cfg in uf:Rows() do
		if cfg.enabled and fillers[key] then
			fillers[key](row, cfg, values)
			row:ShowSample(values)
		end
	end
	for key, part in uf:Parts() do
		if parts[key] then parts[key](part, values) end
	end
end
