local _, ns = ...
local Perf = ns.Perf

function Perf:MeasureEdit(operation)
	self:Divider("edit " .. operation)
	if not self:CanMeasure() then return end
	local cg = ns.ClickGrid
	if not cg or not cg.started then ns:Print("ClickGrid must already be loaded and prepared"); return end
	local config = cg.Config
	local edits = {
		indicators = { config.settings, "indicators.phase" },
		titles = { config.settings, "titles.enabled" },
		spacing = { config.settings, "panel.spacingX" },
		member = { config.styles.member, "width" },
		target = { config.styles.target, "width" },
		slots = { config.settings, "slots.slot1.size" },
		bindings = { config.bindings, "button1.none.friendly.action" },
	}
	local edit = edits[operation]
	if not edit then ns:Print("edit operations: indicators, titles, spacing, member, target, slots, bindings"); return end
	local store, path = edit[1], edit[2]
	local before = ns.Util.Copy(store:Read())
	local valid, reason = store:Check(before)
	if not valid then ns:Print("cannot restore current overrides:", reason); return end
	local opt = ns.Schema.Find(store:GetSchema(), path)
	local previous = ns.Util.GetPath(store:Resolved(), path)
	local value
	if opt.type == "toggle" then
		value = not previous
	elseif opt.type == "range" then
		local step = opt.step or 1
		value = previous + step <= opt.max and previous + step or previous - step
	else
		value = previous == "target" and "assist" or "target"
	end
	local title = "edit " .. operation
	local reported, result = pcall(self.Run, self, title, function()
		local ok, err = store:Set(path, value)
		if not ok then error(err, 0) end
	end)
	local restored, success, restoreError = pcall(store.Replace, store, before)
	local report = ns.Config.db.global.perfMeasurements and ns.Config.db.global.perfMeasurements[title]
	if reported and result and report then
		report.edit = { path = path, before = previous, value = value, overrides = before,
			restored = restored and success == true }
	end
	if not restored or not success then
		local err = restored and restoreError or success
		ns.Logs:Error(title .. " restore", err)
		ns:Print("settings restoration failed:", err)
		return
	end
	ns:Print("settings overrides restored outside the measured operation")
	if not reported then
		ns.Logs:Error(title, result)
		ns:Print("measurement reporting failed:", result)
	end
end
