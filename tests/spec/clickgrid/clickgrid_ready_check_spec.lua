local Helpers = require("helpers")
local Mock = Helpers.Mock

local ATLASES = { ready = "UI-LFG-ReadyMark-Raid", notready = "UI-LFG-DeclineMark-Raid", waiting = "UI-LFG-PendingMark-Raid" }

describe("ClickGrid ready checks", function()
	local UF, CG, member, target
	before_each(function()
		UF, CG = Helpers.LoadClickGrid()
		local cell = CG.headers.party:GetAttribute("child1")
		member, target = cell.Member, cell.Target
	end)

	it("tints member bars live but not their targets", function()
		assert.is_true(member:IsElementEnabled("UF_ReadyCheck"))
		assert.equals(member.uf:GetReadyCheck(), member.UF_ReadyCheck)
		assert.is_false(target:IsElementEnabled("UF_ReadyCheck"))
		assert.equals(CG:GetGridButton(member).status.ReadyCheckIndicator, member.uf:GetReadyCheck():GetIcon():GetWidget())
		assert.equals("CENTER", member.uf:GetReadyCheck():GetIcon().resolved.anchor)
		assert.equals(22, member.uf:GetReadyCheck():GetIcon().resolved.size)
		assert.is_false(member:IsElementEnabled("ReadyCheckIndicator"), "one shared state drives bars and icon")
		member.__unit = "party1"
		GetReadyCheckStatus = function(unit) return unit == "party1" and "notready" or nil end
		UF.oUF.elements.UF_ReadyCheck.update(member, "READY_CHECK")
		local r, g, b = member.uf:GetRow("health"):GetBar():GetTint()
		assert.same({ 0.85, 0.12, 0.12 }, { r, g, b })
		CG.Config:SetStyle("member", "readyCheck.enabled", false)
		assert.is_nil(member.uf:GetRow("health"):GetBar():GetTint())
		assert.is_true(member:IsElementEnabled("UF_ReadyCheck"), "the icon still needs ready check updates")
		assert.is_true(CG:GetGridButton(member).status.ReadyCheckIndicator:IsShown())
		CG.Config:Set("indicators.ready", false)
		assert.is_false(member:IsElementEnabled("UF_ReadyCheck"))
	end)

	it("holds and fades the status icon like the member's tints", function()
		CG.Config:Set("indicators.readyPosition", "TOP")
		CG.Config:Set("indicators.readySize", 14)
		local icon = CG:GetGridButton(member).status.ReadyCheckIndicator
		member.__unit = "party1"
		GetReadyCheckStatus = function() return "waiting" end
		local element = UF.oUF.elements.UF_ReadyCheck
		element.update(member, "READY_CHECK")
		assert.equals(ATLASES.waiting, icon.__state.atlas)
		member.uf:GetPart("raidTarget"):SetIndex(8)
		assert.same({ "CENTER", member, "TOP", -8, 0 }, { member.uf:GetPart("raidTarget"):GetFrame():GetPoint() })
		element.update(member, "READY_CHECK_FINISHED")
		assert.equals(ATLASES.notready, icon.__state.atlas, "an unanswered check ends as not ready")
		local driver = member.uf:GetReadyCheck().driver
		driver:RunScript("OnUpdate", 2.75)
		assert.equals(0.5, icon:GetAlpha())
		local _, _, _, amount = member.uf:GetRow("health"):GetBar():GetTint()
		assert.equals(amount, icon:GetAlpha(), "one fade drives both")
		driver:RunScript("OnUpdate", 0.75)
		assert.is_false(icon:IsShown())
		assert.is_nil(driver:GetScript("OnUpdate"))
		assert.same({ "CENTER", member, "TOP", 0, 0 }, { member.uf:GetPart("raidTarget"):GetFrame():GetPoint() })
		element.update(member, "READY_CHECK")
		element.update(member, "READY_CHECK_FINISHED")
		CG.Config:SetStyle("member", "readyCheck.hold", 0)
		CG.Config:SetStyle("member", "readyCheck.fade", 0)
		driver:RunScript("OnUpdate", 0.01)
		assert.is_false(icon:IsShown(), "zero fade removes the mark immediately")
	end)
end)

describe("ClickGrid ready check previews", function()
	local UF, CG, wb
	before_each(function() UF, CG, wb = Helpers.LoadClickGrid(true); wb:Open("clickgrid.panel") end)

	local function Tick(seconds)
		for _ = 1, math.floor(seconds / 0.1 + 0.5) do
			Mock.time = Mock.time + 0.1
			wb:OnUpdate(0.1)
		end
	end

	local function State(cell)
		local status = cell.member:GetReadyCheck():GetState()
		local icon = cell.status.ReadyCheckIndicator
		return status, icon:IsShown() and icon.__state.atlas or nil
	end

	it("shows a static check with mixed answers on bars and icons", function()
		local icon2 = wb.handle.cells[2].status.ReadyCheckIndicator
		assert.is_true(icon2:IsShown(), "without a check: the placement sample on member 2")
		assert.is_nil(wb.handle.cells[1].member:GetRow("health"):GetBar():GetTint())
		wb.dataTarget.set("readyCheck", "check")
		for index, status in ipairs({ "ready", "ready", "notready", "waiting", "ready" }) do
			local cell = wb.handle.cells[index]
			local shown, atlas = State(cell)
			assert.equals(status, shown, "member " .. index)
			assert.equals(ATLASES[status], atlas, "member " .. index)
			assert.is_not_nil(cell.member:GetRow("health"):GetBar():GetTint())
			assert.is_nil(cell.target:GetRow("health"):GetBar():GetTint(), "targets stay untinted")
		end
		CG.Config:Set("indicators.ready", false)
		assert.is_false(wb.handle.cells[1].status.ReadyCheckIndicator:IsShown(), "the icon toggle still applies")
		CG.Config:Set("indicators.ready", true)
		wb.dataTarget.set("readyCheck", "off")
		assert.is_nil(wb.handle.cells[1].member:GetRow("health"):GetBar():GetTint())
		assert.is_true(icon2:IsShown())
		assert.equals(1, icon2:GetAlpha())
	end)

	it("lets members answer in turn, then ends the check and fades out", function()
		wb.dataTarget.set("readyCheck", "check")
		wb.dataTarget.set("source", "animated")
		Tick(0.6)
		assert.equals("ready", (State(wb.handle.cells[1])), "the first member answered")
		assert.equals("waiting", (State(wb.handle.cells[3])), "later members still pending")
		Tick(2)
		assert.equals("notready", (State(wb.handle.cells[3])))
		assert.equals("waiting", (State(wb.handle.cells[4])), "member 4 never answers")
		Tick(1)
		local status, atlas = State(wb.handle.cells[4])
		assert.equals("notready", status, "unanswered at the end: not ready")
		assert.equals(ATLASES.notready, atlas)
		Tick(2.8)
		local icon = wb.handle.cells[1].status.ReadyCheckIndicator
		assert.is_true(icon:GetAlpha() > 0 and icon:GetAlpha() < 1, "icon fades with the tints")
		Tick(1)
		assert.is_nil((State(wb.handle.cells[1])), "faded out")
		assert.is_false(icon:IsShown())
	end)
end)
