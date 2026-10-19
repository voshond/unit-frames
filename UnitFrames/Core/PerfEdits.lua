local _, ns = ...
local Perf = ns.Perf
local EDITS = { "indicators", "titles", "spacing", "member", "target", "slots", "bindings" }
Perf.EDITS = EDITS

function Perf:RunEdit(operation)
	local config = ns.ClickGrid.Config
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
	if not edit then
		local reason = "edit operations: " .. table.concat(EDITS, ", ")
		ns:Print(reason)
		return false, reason
	end
	local store, path = edit[1], edit[2]
	local before = ns.Util.Copy(store:Read())
	local valid, reason = store:Check(before)
	if not valid then ns:Print("cannot restore current overrides:", reason); return false, reason end
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
	local reported, measured, failure = pcall(self.Run, self, title, function()
		local ok, err = store:Set(path, value)
		if not ok then error(err, 0) end
	end)
	local restored, success, restoreError = pcall(store.Replace, store, before)
	local report = ns.Config.db.global.perfMeasurements and ns.Config.db.global.perfMeasurements[title]
	if reported and measured and report then
		report.edit = { path = path, before = previous, value = value, overrides = before,
			restored = restored and success == true }
	end
	if not restored or not success then
		local err = restored and restoreError or success
		ns.Logs:Error(title .. " restore", err)
		ns:Print("settings restoration failed:", err)
		return false, "settings restoration failed: " .. tostring(err)
	end
	ns:Print("settings overrides restored outside the measured operation")
	if not reported then
		ns.Logs:Error(title, measured)
		ns:Print("measurement reporting failed:", measured)
		return false, "measurement reporting failed: " .. tostring(measured)
	end
	if not measured then return false, tostring(failure) end
	return true
end

function Perf:MeasureEdit(operation)
	self:Divider("edit " .. operation)
	if not self:CanMeasure() then return end
	local cg = ns.ClickGrid
	if not cg or not cg.started then ns:Print("ClickGrid must already be loaded and prepared"); return end
	self:RunEdit(operation)
end

function Perf:TickSuiteEdit(suite)
	local name = EDITS[suite.edit]
	self:Divider("edit " .. name)
	suite.editing = true
	local ran, ok, reason = pcall(self.RunEdit, self, name)
	suite.editing = nil
	if self.suite ~= suite then return end
	if not ran or not ok then
		self:FinishSuite("failed", "edit " .. name .. ": " .. tostring(ran and reason or ok))
		return
	end
	suite.report.edits[#suite.report.edits + 1] = name
	suite.edit = suite.edit + 1
	if suite.edit > #EDITS then self:FinishSuite("completed") end
end
