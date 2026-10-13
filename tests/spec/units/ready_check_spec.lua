local Helpers = require("helpers")
local Mock = Helpers.Mock

local GREY, GREEN, RED = { 0.5, 0.5, 0.5 }, { 0.15, 0.8, 0.15 }, { 0.85, 0.12, 0.12 }

-- The tint of every row: { r, g, b, amount } or false.
local function Tints(uf)
	local out = {}
	for key, row in uf:Rows() do
		local r, g, b, amount = row:GetBar():GetTint()
		out[key] = r and { r, g, b, amount } or false
	end
	return out
end

local function AssertTint(uf, color, amount, message)
	for key, tint in pairs(Tints(uf)) do
		if color then
			assert.is_true(tint ~= false, (message or "") .. ": " .. key .. " tinted")
			for i = 1, 3 do assert.equals(color[i], tint[i], (message or "") .. ": " .. key) end
			assert.is_true(math.abs(amount - tint[4]) < 1e-6,
				(message or "") .. ": " .. key .. " amount " .. amount .. ", got " .. tint[4])
		else
			assert.is_false(tint, (message or "") .. ": " .. key .. " untinted")
		end
	end
end

describe("Ready check tints", function()
	local ns, frame, uf, handlers, statuses
	before_each(function()
		ns = Helpers.LoadAddon(true, true)
		Mock.InstallUI()
		frame = ns.Units.frames.player
		uf = frame.uf
		statuses = {}
		GetReadyCheckStatus = function(unit) return statuses[unit] end
		handlers = {}
		frame.RegisterEvent = function(_, event, handler, shared)
			handlers[event] = handler
			assert.is_true(shared, event .. " carries no unit of this frame")
		end
		frame.UnregisterEvent = function(_, event) handlers[event] = nil end
		assert.is_true(ns.oUF.elements.UF_ReadyCheck.enable(frame, "player"))
	end)

	local function Fire(event)
		handlers[event](frame, event)
	end

	local function Step(seconds)
		local driver = uf:GetReadyCheck().driver
		for _ = 1, math.floor(seconds / 0.25 + 0.5) do
			local script = driver:GetScript("OnUpdate")
			if script then script(driver, 0.25) end
		end
	end

	it("does no hold-period painting or alpha-only geometry work", function()
		local ready, stack = uf:GetReadyCheck(), uf:GetDecorations()
		ready:Set("ready")
		ready:Finish()
		local paints, reflows, tint, reflow = 0, 0, ready.tint, stack.Reflow
		ready.tint = function(...) paints = paints + 1; return tint(...) end
		stack.Reflow = function(self) reflows = reflows + 1; return reflow(self) end
		local driver = ready.driver
		for _ = 1, 60 do driver:GetScript("OnUpdate")(driver, 1 / 60) end
		assert.equals(0, paints)
		assert.equals(0, reflows)
		Step(1.75)
		assert.is_true(paints > 0)
		assert.equals(0, reflows)
		Step(1)
		assert.equals(1, reflows, "the icon leaves its slot at zero opacity")
		assert.is_nil(driver:GetScript("OnUpdate"))
	end)

	it("is offered and bound on every unit frame and ClickGrid member bars", function()
		for _, unit in ipairs(ns.Units.order) do
			local live = ns.Units.frames[unit]
			assert.is_not_nil(ns.Schema.Find(live.uf:GetSchema(), "readyCheck.fade"), unit)
			assert.equals(live.uf:GetReadyCheck(), live.UF_ReadyCheck)
			assert.is_true(live:IsElementEnabled("UF_ReadyCheck"))
		end
		ns.Config:SetUnitValue("target", "readyCheck.enabled", false)
		assert.is_true(ns.Units.frames.target:IsElementEnabled("UF_ReadyCheck"), "the icon still needs the state")
		ns.Config:SetUnitValue("target", "readyCheckIcon.enabled", false)
		assert.is_false(ns.Units.frames.target:IsElementEnabled("UF_ReadyCheck"))
		ns.Config:SetUnitValue("target", "readyCheck.enabled", true)
		assert.is_true(ns.Units.frames.target:IsElementEnabled("UF_ReadyCheck"))
		local _, CG = Helpers.LoadClickGrid()
		assert.is_not_nil(UnitFrames.Schema.Find(CG:StyleSchema("member"), "readyCheck"))
		assert.is_nil(UnitFrames.Schema.Find(CG:StyleSchema("target"), "readyCheck"), "targets are not in the check")
		for _, kind in ipairs({ "member", "target" }) do
			assert.is_nil(UnitFrames.Schema.Find(CG:StyleSchema(kind), "readyCheckIcon"), kind .. " has its own icon")
		end
	end)

	it("greys every bar while waiting and turns green or red on the unit's answer", function()
		assert.is_false(Tints(uf).experience, "the player's XP row takes part")
		AssertTint(uf, nil, nil, "no check")
		statuses.player = "waiting"
		Fire("READY_CHECK")
		AssertTint(uf, GREY, 1, "waiting")
		-- Confirmations name party/raid tokens; each frame re-reads its unit.
		Fire("READY_CHECK_CONFIRM")
		AssertTint(uf, GREY, 1, "someone else answered")
		statuses.player = "ready"
		Fire("READY_CHECK_CONFIRM")
		AssertTint(uf, GREEN, 1, "ready")
		statuses.player = "notready"
		Fire("READY_CHECK_CONFIRM")
		AssertTint(uf, RED, 1, "not ready")
		statuses.player = nil
		Fire("READY_CHECK_CONFIRM")
		AssertTint(uf, nil, nil, "units outside the check stay untinted")
		statuses.player = Secret("ready")
		Fire("READY_CHECK_CONFIRM")
		AssertTint(uf, nil, nil, "an opaque status is not inspected")
	end)

	it("keeps live bar colours, including secret ones, under the tint", function()
		local health = uf:GetRow("health"):GetBar()
		local r, g, b = Secret(0.78), Secret(0.61), Secret(0.43)
		health:SetColor(r, g, b)
		statuses.player = "ready"
		Fire("READY_CHECK")
		assert.same({ r, g, b, 1 }, health.bar.__state.color)
		ns.Config:SetUnitValue("player", "health.height", 30)
		AssertTint(uf, GREEN, 1, "re-styling keeps the tint")
		assert.same({ r, g, b, 1 }, health.bar.__state.color)
	end)

	it("counts a missing answer as not ready, holds, then fades back", function()
		statuses.player = "waiting"
		Fire("READY_CHECK")
		Fire("READY_CHECK_FINISHED")
		AssertTint(uf, RED, 1, "no answer")
		Step(2)
		AssertTint(uf, RED, 1, "held for two seconds")
		Step(0.75)
		AssertTint(uf, RED, 0.5, "half faded")
		frame.UF_ReadyCheck = uf:GetReadyCheck()
		ns.oUF.elements.UF_ReadyCheck.update(frame, "UnitFramesRefresh")
		AssertTint(uf, RED, 0.5, "other updates do not cut the fade short")
		Step(0.75)
		AssertTint(uf, nil, nil, "faded out")
		assert.is_nil(uf:GetReadyCheck().driver:GetScript("OnUpdate"), "no work after the fade")
	end)

	it("lets a new check interrupt the fade and honours changed settings", function()
		statuses.player = "ready"
		Fire("READY_CHECK")
		Fire("READY_CHECK_FINISHED")
		AssertTint(uf, GREEN, 1)
		Step(2.5)
		statuses.player = "waiting"
		Fire("READY_CHECK")
		AssertTint(uf, GREY, 1, "new check")
		assert.is_nil(uf:GetReadyCheck().driver:GetScript("OnUpdate"))
		ns.Config:SetUnitValue("player", "readyCheck.waitingColor", { 0.3, 0.3, 0.3, 1 })
		AssertTint(uf, { 0.3, 0.3, 0.3 }, 1, "colour changes apply during a check")
		ns.Config:SetUnitValue("player", "readyCheck.hold", 0)
		ns.Config:SetUnitValue("player", "readyCheck.fade", 0)
		statuses.player = "ready"
		Fire("READY_CHECK_CONFIRM")
		Fire("READY_CHECK_FINISHED")
		Step(0.25)
		AssertTint(uf, nil, nil, "no hold and no fade")
		Fire("READY_CHECK_FINISHED")
		AssertTint(uf, nil, nil, "finishing without a status does nothing")
	end)

	it("removes tints when switched off, disabled or released", function()
		statuses.player = "notready"
		Fire("READY_CHECK")
		ns.Config:SetUnitValue("player", "readyCheck.enabled", false)
		AssertTint(uf, nil, nil, "switched off")
		ns.Config:SetUnitValue("player", "readyCheck.enabled", true)
		Fire("READY_CHECK")
		Fire("READY_CHECK_FINISHED")
		ns.oUF.elements.UF_ReadyCheck.disable(frame)
		AssertTint(uf, nil, nil, "element disabled")
		assert.is_nil(handlers.READY_CHECK)
		assert.is_nil(uf:GetReadyCheck().driver:GetScript("OnUpdate"))
		local preview = ns.Units:CreateFrame("target", UIParent)
		preview:GetReadyCheck():Set("ready")
		preview:GetReadyCheck():Finish()
		assert.is_not_nil(preview:GetReadyCheck().driver:GetScript("OnUpdate"))
		preview:Release()
		assert.is_nil(preview:GetReadyCheck().driver:GetScript("OnUpdate"))
	end)

	it("shows the matching check mark in the decoration stack and fades it with the tints", function()
		local icon = uf:GetReadyCheck():GetIcon()
		local texture = icon:GetWidget()
		assert.is_false(texture:IsShown(), "no check")
		statuses.player = "waiting"
		Fire("READY_CHECK")
		assert.is_true(texture:IsShown())
		assert.equals("UI-LFG-PendingMark-Raid", texture.__state.atlas)
		assert.same({ "CENTER", frame, "CENTER", 0, 0 }, { icon:GetFrame():GetPoint() })
		statuses.player = "ready"
		Fire("READY_CHECK_CONFIRM")
		assert.equals("UI-LFG-ReadyMark-Raid", texture.__state.atlas)
		statuses.player = "waiting"
		Fire("READY_CHECK_CONFIRM")
		Fire("READY_CHECK_FINISHED")
		assert.equals("UI-LFG-DeclineMark-Raid", texture.__state.atlas, "no answer: not ready")
		Step(2)
		assert.equals(1, texture:GetAlpha())
		Step(0.75)
		assert.equals(0.5, texture:GetAlpha(), "fades with the tints")
		Step(0.75)
		assert.is_false(texture:IsShown())
	end)

	it("lets the icon and the tints work without each other", function()
		local texture = uf:GetReadyCheck():GetIcon():GetWidget()
		ns.Config:SetUnitValue("player", "readyCheck.enabled", false)
		statuses.player = "notready"
		Fire("READY_CHECK")
		AssertTint(uf, nil, nil, "tints off")
		assert.is_true(texture:IsShown(), "icon only")
		Fire("READY_CHECK_FINISHED")
		assert.is_not_nil(uf:GetReadyCheck().driver:GetScript("OnUpdate"), "the icon still fades")
		Step(4)
		assert.is_false(texture:IsShown())
		ns.Config:SetUnitValue("player", "readyCheck.enabled", true)
		ns.Config:SetUnitValue("player", "readyCheckIcon.enabled", false)
		statuses.player = "ready"
		Fire("READY_CHECK")
		AssertTint(uf, GREEN, 1, "tints only")
		assert.is_false(uf:GetReadyCheck():GetIcon():GetFrame():IsShown(), "a disabled icon leaves the stack")
		ns.Config:SetUnitValue("player", "readyCheckIcon.enabled", true)
		assert.is_true(uf:GetReadyCheck():GetIcon():GetFrame():IsShown())
		assert.is_true(texture:IsShown(), "enabled during a check: shows the current answer")
	end)

	it("copies player settings", function()
		ns.Config:SetUnitValue("player", "readyCheck.readyColor", { 0, 0, 1, 1 })
		ns.Units:CopyPlayerSettings("focus")
		assert.same({ 0, 0, 1, 1 }, ns.Units.frames.focus.uf.resolved.readyCheck.readyColor)
	end)
end)

describe("Ready check previews", function()
	local function Tick(workbench, seconds)
		for _ = 1, math.floor(seconds / 0.1 + 0.5) do
			Mock.time = Mock.time + 0.1
			workbench:OnUpdate(0.1)
		end
	end

	it("holds the answer in static previews on every frame", function()
		local ns, wb = Helpers.LoadWorkbench()
		wb:Toggle()
		for _, unit in ipairs(ns.Units.order) do
			wb:Select("unit." .. unit)
			local uf = wb.handle.parts.uf
			AssertTint(uf, nil, nil, unit .. " default")
			for status, color in pairs({ waiting = GREY, ready = GREEN, notready = RED }) do
				wb.dataTarget.set("readyCheck", status)
				AssertTint(uf, color, 1, unit .. " " .. status)
			end
			wb.dataTarget.set("readyCheck", "notready")
			wb.styleTarget.set("readyCheck.notReadyColor", { 1, 0, 1, 1 })
			AssertTint(uf, { 1, 0, 1 }, 1, unit .. " restyled")
			for status, atlas in pairs({ waiting = "UI-LFG-PendingMark-Raid", ready = "UI-LFG-ReadyMark-Raid",
				notready = "UI-LFG-DeclineMark-Raid" }) do
				wb.dataTarget.set("readyCheck", status)
				assert.equals(atlas, uf:GetReadyCheck():GetIcon():GetWidget().__state.atlas, unit .. " icon " .. status)
				assert.is_true(uf:GetReadyCheck():GetIcon():GetWidget():IsShown())
			end
			wb.dataTarget.set("readyCheck", "off")
			AssertTint(uf, nil, nil, unit .. " off")
			assert.is_false(uf:GetReadyCheck():GetIcon():GetWidget():IsShown())
			Tick(wb, 1)
			AssertTint(uf, nil, nil, unit .. " static samples do not animate")
		end
	end)

	it("loops a whole check in animated previews", function()
		local _, wb = Helpers.LoadWorkbench()
		wb:Toggle()
		wb:Select("unit.player")
		local uf = wb.handle.parts.uf
		wb.dataTarget.set("readyCheck", "ready")
		wb.dataTarget.set("source", "animated")
		-- Loop: 1.5 s waiting, 1.5 s ready, 2 s hold, 1.5 s fade, 1 s plain.
		Tick(wb, 1)
		AssertTint(uf, GREY, 1, "waiting")
		Tick(wb, 1)
		AssertTint(uf, GREEN, 1, "answered")
		Tick(wb, 2)
		AssertTint(uf, GREEN, 1, "held")
		Tick(wb, 1.5)
		local _, _, _, amount = uf:GetRow("health"):GetBar():GetTint()
		assert.is_true(amount > 0 and amount < 1, "fading")
		Tick(wb, 1.2)
		AssertTint(uf, nil, nil, "plain")
		Tick(wb, 1)
		AssertTint(uf, GREY, 1, "the next loop")
		wb.dataTarget.set("readyCheck", "waiting")
		Tick(wb, 3.5)
		AssertTint(uf, RED, 1, "unanswered checks end not ready")
	end)
end)
