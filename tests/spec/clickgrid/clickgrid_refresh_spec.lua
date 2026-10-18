local Helpers = require("helpers")
local Mock = Helpers.Mock

describe("ClickGrid targeted refresh", function()
	local UF, CG
	before_each(function() UF, CG = Helpers.LoadClickGrid() end)

	local function Observe(edit)
		UF.Perf.counters = {}
		edit()
		local counters = UF.Perf.counters
		UF.Perf.counters = nil
		return counters
	end

	local function Cell()
		return CG.headers.party:GetAttribute("child1")
	end

	local function Anchor(frame)
		local point = frame:GetAnchor("TOPLEFT")
		return point and { point[1], point[3], point[4], point[5] }
	end

	local function FrameState(frame)
		local uf = frame.uf
		local state = { resolved = UF.Util.Copy(uf.resolved), layout = UF.Util.Copy(uf.layout),
			anchor = Anchor(frame), elements = UF.Util.Copy(frame.enabledElements),
			paused = UF.Util.Copy(frame.pausedElements), rows = {}, parts = {} }
		for key, row in uf:Rows() do
			local texts = {}
			for name, text in pairs(row.texts) do texts[name] = UF.Util.Copy(text.resolved) end
			state.rows[key] = { resolved = UF.Util.Copy(row.resolved), bar = UF.Util.Copy(row.bar.resolved), texts = texts }
		end
		for key, part in uf:Parts() do
			state.parts[key] = { resolved = UF.Util.Copy(part.resolved), enabled = part:IsEnabled() }
		end
		local button = CG:GetGridButton(frame)
		if button.status then state.status = UF.Util.Copy(button.status.resolved) end
		if button.slots then state.slots = UF.Util.Copy(button.slots.resolved) end
		return state
	end

	local function State()
		local cell = Cell()
		local headers = {}
		for key, header in pairs(CG.headers) do headers[key] = Anchor(header) end
		return { member = FrameState(cell.Member), target = FrameState(cell.Target),
			layout = UF.Util.Copy(CG.layout), metrics = UF.Util.Copy(CG.metrics), headers = headers }
	end

	it("updates indicators without root styles, unit binds, header layout or click-binding compilation", function()
		local cell = Cell()
		local signature, events = {}, {}
		UF.Events.RegisterCallback(signature, "ClickGridConfigChanged", function(_, path, kind, nested)
			events[#events + 1] = { path = path, kind = kind, nested = nested }
		end)
		local counters = Observe(function() CG.Config:Set("indicators.role", false) end)
		assert.is_nil(counters.rootApply)
		assert.is_nil(counters.unitBind)
		assert.is_nil(counters.unitLayout)
		assert.is_nil(counters.clickgridPanelLayout)
		assert.is_nil(counters.clickgridBindingsCompile)
		assert.equals(1, counters.clickgridTargetedRefresh)
		assert.is_false(CG:GetGridButton(cell.Member).status.resolved.role)
		assert.is_false(cell.Member:IsElementEnabled("GroupRoleIndicator"))
		assert.same({ { path = "indicators.role", kind = "settings", nested = "indicators.role" } }, events)
	end)

	it("routes slots independently and retains the shared member aura switch", function()
		local counters = Observe(function() CG.Config:Set("slots.slot1.spell", "139,774") end)
		assert.is_nil(counters.rootApply)
		assert.is_nil(counters.unitBind)
		assert.is_nil(counters.clickgridPanelLayout)
		assert.is_nil(counters.clickgridBindingsCompile)
		local slots = CG:GetGridButton(Cell().Member).slots
		CG.Config:Set("slots.slot1.enabled", true)
		assert.same({ [139] = true, [774] = true }, slots.candidates.slot1)
		CG.Config:SetStyle("member", "auras.enabled", false)
		assert.is_false(slots:IsEnabled())
		CG.Config:SetStyle("member", "auras.enabled", true)
		assert.is_true(slots:IsEnabled())
	end)

	it("relayouts titles, borders and panel spacing without restyling units or compiling bindings", function()
		for _, edit in ipairs({
			function() CG.Config:Set("titles.size", 18) end,
			function() CG.Config:Set("border.padding", 8) end,
			function() CG.Config:Set("panel.spacingX", 7) end,
		}) do
			local counters = Observe(edit)
			assert.equals(1, counters.clickgridPanelLayout)
			assert.is_nil(counters.rootApply)
			assert.is_nil(counters.unitBind)
			assert.is_nil(counters.unitLayout)
			assert.is_nil(counters.clickgridBindingsCompile)
		end
	end)

	it("restyles only the selected kind and propagates member height to target fill geometry", function()
		local event
		UF.Events.RegisterCallback({}, "ClickGridConfigChanged", function(_, path, kind, nested)
			event = { path, kind, nested }
		end)
		local member = Observe(function() CG.Config:SetStyle("member", "width", 191) end)
		assert.equals(45, member.rootApply)
		assert.equals(45, member.unitBind)
		assert.is_nil(member.clickgridBindingsCompile)
		assert.same({ "member", "member", "width" }, event)
		local target = Observe(function() CG.Config:SetStyle("target", "width", 65) end)
		assert.equals(45, target.rootApply)
		assert.equals(45, target.unitBind)
		CG.Config:SetStyle("member", "health.height", 52)
		assert.equals(CG.layout.cellHeight, Cell().Target.uf.fillHeight)
		assert.equals(CG.layout.cellHeight, Cell().Target.uf.layout.height)
		CG.Config:SetStyle("target", "shown", true)
		assert.is_nil(Cell().Target:GetAttribute("statehidden"))
		assert.is_false(Cell().Target:IsElementPaused("Health"))
		CG.Config:SetStyle("target", "shown", false)
		assert.is_true(Cell().Target:IsElementPaused("Health"))
	end)

	it("matches a full refresh after each representative edit", function()
		for _, edit in ipairs({
			function() CG.Config:Set("indicators.readySize", 24) end,
			function() CG.Config:Set("slots.slot1.spell", "139") end,
			function() CG.Config:Set("titles.position", "below") end,
			function() CG.Config:Set("panel.targetGap", 8) end,
			function() CG.Config:SetStyle("member", "health.height", 42) end,
			function() CG.Config:SetStyle("member", "auras.durationSize", 10) end,
			function() CG.Config:SetStyle("target", "shown", true) end,
		}) do
			edit()
			local targeted = State()
			CG:Refresh()
			assert.same(targeted, State())
		end
	end)

	it("coalesces mixed combat domains and bindings without promoting them to a full refresh", function()
		Mock.inCombat = true
		CG.Config:Set("indicators.role", false)
		CG.Config:Set("slots.slot1.spell", "139")
		CG.Config:SetStyle("member", "width", 191)
		CG.Config:SetAction(2, "shift", "friendly", { action = "spell", spell = "2061" })
		assert.is_true(CG.pendingChanges.indicators)
		assert.is_true(CG.pendingChanges.slots)
		assert.is_true(CG.pendingChanges.member)
		assert.is_nil(CG.pendingChanges.full)
		assert.is_true(CG:GetGridButton(Cell().Member).status.resolved.role)
		assert.is_nil(Cell().Member:GetAttribute("shift-spell-heal2"))
		Mock.inCombat = false
		local counters = Observe(function() Mock.FireEvent("PLAYER_REGEN_ENABLED") end)
		assert.equals(1, counters.clickgridTargetedRefresh)
		assert.is_nil(counters.clickgridFullRefresh)
		assert.equals(45, counters.rootApply)
		assert.equals(1, counters.clickgridBindingsCompile)
		assert.equals(2061, Cell().Member:GetAttribute("shift-spell-heal2"))
		assert.is_false(CG:GetGridButton(Cell().Member).status.resolved.role)
		assert.equals(191, Cell().Member.uf.resolved.width)
		assert.is_nil(CG.pending)
		assert.is_nil(CG.pendingChanges)
		assert.is_nil(CG.pendingBindings)
	end)

	it("lets full invalidation supersede queued edits and falls back for unclassified paths", function()
		Mock.inCombat = true
		CG.Config:Set("indicators.role", false)
		CG:RequestRefresh()
		CG.Config:Set("titles.size", 18)
		assert.same({ full = true }, CG.pendingChanges)
		Mock.inCombat = false
		local counters = Observe(function() Mock.FireEvent("PLAYER_REGEN_ENABLED") end)
		assert.equals(1, counters.clickgridFullRefresh)
		assert.equals(90, counters.rootApply)
		local fallback = Observe(function() CG:RequestRefresh("settings", "future.option") end)
		assert.equals(1, fallback.clickgridFullRefresh)
	end)

	it("reactivates retained headers with current style, indicators and bindings before raid eligibility", function()
		CG.Config:Set("panel.mode", "flat")
		local inactive = CG.headers.group1:GetAttribute("child1").Member
		assert.is_true(CG:GetGridButton(inactive).inactive)
		CG.Config:SetStyle("member", "width", 191)
		CG.Config:Set("indicators.role", false)
		CG.Config:SetAction(2, "shift", "friendly", { action = "spell", spell = "2061" })
		assert.is_true(CG:GetGridButton(inactive).status.resolved.role)
		CG.Config:Set("panel.mode", "subgroups")
		assert.is_nil(CG:GetGridButton(inactive).inactive)
		assert.equals(191, inactive.uf.resolved.width)
		assert.is_false(CG:GetGridButton(inactive).status.resolved.role)
		assert.equals(2061, inactive:GetAttribute("shift-spell-heal2"))
		assert.is_true(CG.headers.group1:GetAttribute("showRaid"))
	end)
end)

describe("ClickGrid targeted preview refresh", function()
	local UF, CG, wb
	before_each(function()
		UF, CG, wb = Helpers.LoadClickGrid(true)
		wb:Open("clickgrid.panel")
	end)

	it("updates live and static preview indicators without applying either root composition", function()
		local preview = wb.handle
		local member, target, applies, feeds = preview.cells[1].member, preview.cells[1].target, 0, 0
		local applyMember, applyTarget, feed = member.Apply, target.Apply, preview.ShowData
		member.Apply = function(self, ...) applies = applies + 1; return applyMember(self, ...) end
		target.Apply = function(self, ...) applies = applies + 1; return applyTarget(self, ...) end
		preview.ShowData = function(self, ...) feeds = feeds + 1; return feed(self, ...) end
		CG.Config:Set("indicators.role", false)
		assert.equals(0, applies)
		assert.equals(1, feeds)
		assert.is_false(preview.cells[1].status.GroupRoleIndicator:IsShown())
		assert.is_false(CG:GetGridButton(CG.headers.party:GetAttribute("child1").Member).status.resolved.role)
		Mock.groupSize = 2
		_G.UnitExists = function(unit) return unit == "player" end
		wb.dataTarget.set("source", "live")
		CG.Config:Set("indicators.privatePosition", "TOP")
		assert.is_false(preview.cells[1].status.GroupRoleIndicator:IsShown())
		assert.is_false(preview.cells[2].slots.container:IsEnabled())
		assert.is_false(preview.cells[2].member:GetFrame():IsShown())
	end)

	it("retains edits for hidden cells and applies them when the preview expands again", function()
		wb.dataTarget.set("count", 8)
		local retained = wb.handle.cells[8]
		wb.dataTarget.set("count", 5)
		CG.Config:Set("indicators.role", false)
		CG.Config:SetStyle("member", "width", 191)
		assert.is_not_nil(retained.changes)
		wb.dataTarget.set("count", 8)
		assert.is_nil(retained.changes)
		assert.equals(191, retained.member.resolved.width)
		assert.is_false(retained.status.GroupRoleIndicator:IsShown())
	end)

	it("drains retired previews and queued source changes after combat without losing narrow edits", function()
		local retired = wb.handle
		Mock.inCombat = true
		CG.Config:Set("indicators.role", false)
		retired:Release()
		local current = CG.Preview:New(UIParent)
		current:ShowData({ source = "animated", count = 8 })
		Mock.inCombat = false
		Mock.FireEvent("PLAYER_REGEN_ENABLED")
		assert.is_nil(next(CG.retiredPreviews))
		assert.is_true(retired.cells[1].member.released)
		assert.equals("animated", current.source)
		assert.equals(8, #current.cells)
		assert.is_false(current.cells[1].status.GroupRoleIndicator:IsShown())
		assert.is_nil(CG.pending)
		current:Release()
	end)
end)
