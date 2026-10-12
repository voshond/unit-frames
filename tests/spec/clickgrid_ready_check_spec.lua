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
		assert.equals(member.uf, member.UF_ReadyCheck)
		assert.is_false(target:IsElementEnabled("UF_ReadyCheck"))
		assert.is_nil(member.uf:GetReadyCheckIcon(), "members keep their own status icon")
		member.__unit = "party1"
		GetReadyCheckStatus = function(unit) return unit == "party1" and "notready" or nil end
		UF.oUF.elements.UF_ReadyCheck.update(member, "READY_CHECK")
		local r, g, b = member.uf:GetRow("health"):GetBar():GetTint()
		assert.same({ 0.85, 0.12, 0.12 }, { r, g, b })
		CG.Config:SetStyle("member", "readyCheck.enabled", false)
		assert.is_nil(member.uf:GetRow("health"):GetBar():GetTint())
		assert.is_false(member:IsElementEnabled("UF_ReadyCheck"))
	end)

	it("holds and fades the status icon like the member's tints", function()
		local icon = member.ReadyCheckIndicator
		rawset(icon, "__strict", true)
		assert.equals(2, icon.finishedTime)
		assert.equals(1.5, icon.fadeTime)
		-- The embedded oUF element reads them when enabled.
		UF.oUF.Private = { unitExists = UnitExists }
		-- Real animation groups return nil for unset fields such as .Alpha.
		rawset(icon, "CreateAnimationGroup", function(self)
			local group = Mock.NewObject("AnimationGroup", self)
			rawset(group, "__strict", true)
			return group
		end)
		assert(loadfile("UnitFrames/Libs/oUF/elements/readycheckindicator.lua"))("oUF", UF)
		member.RegisterEvent, member.UnregisterEvent = function() end, function() end
		assert.is_true(UF.oUF.elements.ReadyCheckIndicator.enable(member, "party1"))
		local alpha = icon.Animation.Alpha
		local function Last(name)
			for i = #alpha.__calls, 1, -1 do
				if alpha.__calls[i][1] == name then return alpha.__calls[i][2] end
			end
		end
		assert.equals(2, Last("SetStartDelay"))
		assert.equals(1.5, Last("SetDuration"))
		CG.Config:SetStyle("member", "readyCheck.hold", 4)
		CG.Config:SetStyle("member", "readyCheck.fade", 0)
		assert.equals(4, Last("SetStartDelay"), "restyles update the running element")
		assert.equals(0.01, Last("SetDuration"))
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
		local status = cell.member:GetReadyCheckState()
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
