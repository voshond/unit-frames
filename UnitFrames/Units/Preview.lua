local _, ns = ...
local Units, Colors = ns.Units, ns.Colors

-- Fills a UnitFrame component with plain sample values (Workbench preview,
-- later Edit Mode test frames). Values: see Units.SAMPLE.
local fillers = {}

function fillers.health(row, cfg, v)
	row:SetRange(0, v.healthMax)
	row:SetValue(v.health)
	row:SetSegmentValue("heal", v.heal)
	row:SetSegmentValue("absorb", v.absorb)
	row:SetSegmentValue("healAbsorb", v.healAbsorb)
	if cfg.colorMode == "class" then
		row:SetColor(Colors.Class(v.class))
	elseif cfg.colorMode == "gradient" then
		row:SetColor(Colors.HealthCurve():Evaluate(v.health / v.healthMax):GetRGB())
	else
		row:ClearColor()
	end
end

function fillers.power(row, _, v)
	row:SetRange(0, v.powerMax)
	row:SetValue(v.power)
	row:SetSegmentValue("cost", v.cost)
	row:SetColor(Colors.Power(v.powerType))
end

function fillers.experience(row, _, v)
	row:SetRange(0, v.xpMax)
	row:SetValue(v.xp)
	row:SetSegmentValue("rested", v.rested)
end

function Units:ShowSample(uf, values)
	for key, row, cfg in uf:Rows() do
		if cfg.enabled and fillers[key] then
			fillers[key](row, cfg, values)
			row:ShowSample(values)
		end
	end
end
