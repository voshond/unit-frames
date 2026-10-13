local _, ns = ...
local Units = ns.Units

-- Fills a UnitFrame component without oUF, through the same data drivers
-- (Units/Drivers.lua) as its live bindings.

-- Plain sample values (Workbench, previews); see Units.SAMPLE.
function Units:ShowSample(uf, values)
	local Drivers = ns.UnitDrivers
	for _, driver in ipairs(Drivers.frame) do
		if driver.sample then driver.sample(uf, values) end
	end
	for key, row, cfg in uf:Rows() do
		local sample = Drivers.Row(key).sample
		if cfg.enabled and sample then
			sample(row, values, cfg)
			row:ShowSample(values)
		end
	end
	for key, part, cfg in uf:Parts() do
		local sample = Drivers.Part(key).sample
		if sample then sample(part, values, cfg) end
	end
end

-- An explicit unit polled by the owner (ClickGrid's live preview). `ctx` is
-- the caller's scratch table for this preview (e.g. its native heal
-- prediction calculator). Event-driven state (casts, ready checks) is not
-- polled.
function Units:ShowLive(uf, unit, ctx)
	local Drivers = ns.UnitDrivers
	for _, driver in ipairs(Drivers.frame) do
		if driver.live then driver.live(uf, unit, ctx) end
	end
	for key, row, cfg in uf:Rows() do
		local live = Drivers.Row(key).live
		if cfg.enabled and live then live(row, unit, ctx, cfg) end
	end
	for key, part, cfg in uf:Parts() do
		local live = Drivers.Part(key).live
		if live then live(part, unit, ctx, cfg) end
	end
end
