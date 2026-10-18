local Helpers = require("helpers")
local Mock = Helpers.Mock

describe("ClickGrid preview lifecycle", function()
	it("reuses independent sample feeds and clears optional fields on source changes", function()
		local UF, CG, wb = Helpers.LoadClickGrid(true)
		CG.Config:SetStyle("target", "shown", true)
		wb:Open("clickgrid.panel")
		wb.dataTarget.set("readyCheck", "check")
		wb.dataTarget.set("source", "animated")
		local preview, fixture = wb.handle, UF.Util.Copy(UF.Units.SAMPLE)
		local first, second = preview.cells[1], preview.cells[2]
		local member, target, aura = first.memberValues, first.targetValues, first.memberValues.buffs[1]
		for _ = 1, 10 do preview:Tick(0.1) end
		assert.equals(member, first.memberValues)
		assert.equals(target, first.targetValues)
		assert.equals(aura, member.buffs[1])
		assert.is_true(member.buffs ~= target.buffs)
		assert.is_true(member.buffs ~= second.memberValues.buffs)
		assert.equals("Enemy 1", target.name)
		assert.is_nil(target.class)
		assert.is_not_nil(member.class)
		wb.dataTarget.set("source", "static")
		assert.is_nil(member.readyCheckTime)
		assert.is_nil(member.readyCheckAnswerAt)
		assert.equals(fixture.buffs[1].remaining, member.buffs[1].remaining)
		wb.dataTarget.set("readyCheck", "off")
		assert.is_nil(member.readyCheck)
		assert.same(fixture, UF.Units.SAMPLE)
		preview:Release()
		assert.is_nil(first.memberValues)
		assert.is_nil(first.targetValues)
	end)
	it("shows varied debuffs whose glows light typed dispels and leave others unlit #glow", function()
		local UF, CG, wb = Helpers.LoadClickGrid(true)
		CG.Config:SetStyle("member", "auras.debuffs.enabled", true)
		CG.Config:SetStyle("member", "auras.dispelGlow.enabled", true)
		wb:Open("clickgrid.panel")
		local cells = wb.handle.cells
		local function Types(index)
			local types = {}
			for i, aura in ipairs(cells[index].memberValues.debuffs) do types[i] = aura.dispelName or "none" end
			return table.concat(types, ",")
		end
		assert.equals("Magic", Types(1))
		assert.equals("Curse,none", Types(2))
		assert.equals("Poison,Disease", Types(3))
		assert.equals("", Types(4))
		assert.is_true(cells[1].memberValues.debuffs ~= UF.Units.SAMPLE.debuffs)
		local samples = cells[2].member:GetPart("auras").previewContainers.debuffs.ufElements
		local lit = {}
		for i = 1, 2 do lit[i] = UF.AuraIcon.GetGlow(samples[i]).textures[1]:IsShown() end
		assert.same({ true, false }, lit)
		wb.handle:Release()
	end)

	it("lights sample cells with a dispellable debuff in its native type colour #glow", function()
		local UF, CG, wb = Helpers.LoadClickGrid(true)
		wb:Open("clickgrid.panel")
		CG.Config:Set("indicators.dispel", true)
		local cells = wb.handle.cells
		local function Glow(index) return cells[index].status.dispelSample end
		assert.is_nil(cells[1].status.dispelContainer, "previews own no native slot")
		assert.is_true(Glow(1):IsShown())
		assert.same({ AuraUtil.GetAuraBorderColor("Magic"):GetRGBA() }, Glow(1).textures[1].__state.vertexColor)
		assert.same({ AuraUtil.GetAuraBorderColor("Curse"):GetRGBA() }, Glow(2).textures[1].__state.vertexColor)
		assert.equals(cells[1].member:GetFrame(), select(2, Glow(1):GetPoint(1)))
		assert.is_true(Glow(4) == nil or not Glow(4):IsShown())
		CG.Config:Set("indicators.dispelGlow.opacity", 0.5)
		assert.equals(0.5, Glow(1):GetAlpha())
		CG.Config:Set("indicators.dispel", false)
		assert.is_false(Glow(1):IsShown())
		wb.handle:Release()
	end)

	it("shows the overheal edge on member samples that are healed past full health #overheal", function()
		local UF, CG, wb = Helpers.LoadClickGrid(true)
		CG.Config:SetStyle("member", "health.bar.overheal.enabled", true)
		wb:Open("clickgrid.panel")
		local cells = wb.handle.cells
		local function Edge(index) return cells[index].member:GetRow("health"):GetBar():GetOverheal() end
		assert.equals(1, Edge(1).levels[1].gate.__state.alpha, "a full-health member with incoming heals")
		assert.equals(0, Edge(2).levels[1].gate.__state.alpha, "a hurt member the heal does not overfill")
		local function Lit(index)
			local lit = {}
			for level = 1, 3 do lit[level] = Edge(index).levels[level].gate.__state.alpha end
			return lit
		end
		assert.same({ 1, 0, 0 }, Lit(1))
		assert.same({ 1, 1, 0 }, Lit(4))
		assert.same({ 1, 1, 1 }, Lit(5))
		local live = CG.headers.party:GetAttribute("child1").Member
		assert.equals(live.uf:GetRow("health"):GetBar():GetOverheal(), live.Health.ufOverheal)
		CG.Config:SetStyle("member", "health.bar.overheal.enabled", false)
		assert.is_nil(Edge(1))
		wb.handle:Release()
	end)

	it("restyles and feeds an active preview once per saved edit, theme and profile change", function()
		local UF, CG, wb = Helpers.LoadClickGrid(true)
		wb:Open("clickgrid.panel")
		local preview, applies, feeds = wb.handle, 0, 0
		local inspectorRefreshes, refresh = 0, wb.inspector.Refresh
		wb.inspector.Refresh = function(self, ...)
			inspectorRefreshes = inspectorRefreshes + 1
			return refresh(self, ...)
		end
		local apply, feed = preview.Apply, preview.ShowData
		preview.Apply = function(self, ...)
			applies = applies + 1
			return apply(self, ...)
		end
		preview.ShowData = function(self, ...)
			feeds = feeds + 1
			return feed(self, ...)
		end
		local function Once(edit)
			applies, feeds, inspectorRefreshes = 0, 0, 0
			edit()
			assert.equals(1, applies)
			assert.equals(1, feeds)
			assert.is_true(inspectorRefreshes > 0)
		end
		Once(function() CG.Config:Set("indicators.readySize", 24) end)
		Once(function() UF.Config:SetThemeValue("fontSize", 13) end)
		Once(function() UF.Config.db:SetProfile("other") end)
		assert.equals(preview, wb.handle)
	end)

	it("updates samples without a full style application and disables absent live subscriptions", function()
		local _, CG, wb = Helpers.LoadClickGrid(true)
		CG.Config:SetStyle("member", "auras.buffs.enabled", true)
		wb:Open("clickgrid.panel")
		local cell = wb.handle.cells[2]
		local applies, apply = 0, cell.member.Apply
		cell.member.Apply = function(self, ...)
			applies = applies + 1
			return apply(self, ...)
		end
		wb.dataTarget.set("readyCheck", "check")
		wb.dataTarget.set("source", "animated")
		wb:OnUpdate(0.2)
		assert.equals(0, applies)
		Mock.groupSize = 2
		CG.headers.party:Assign(2, "party1")
		wb.dataTarget.set("source", "live")
		assert.is_true(cell.member:GetPart("auras").containers.buffs:IsEnabled())
		CG.headers.party:Assign(2, nil)
		wb:OnUpdate(0.2)
		assert.is_false(cell.member:GetPart("auras").containers.buffs:IsEnabled())
		assert.is_false(cell.slots.container:IsEnabled())
		CG.headers.party:Assign(2, "party1")
		wb:OnUpdate(0.2)
		assert.is_true(cell.member:GetPart("auras").containers.buffs:IsEnabled())
	end)

	it("switches ready check samples to live and back without retaining sample state", function()
		local _, _, wb = Helpers.LoadClickGrid(true)
		wb:Open("clickgrid.panel")
		wb.dataTarget.set("readyCheck", "check")
		local cell = wb.handle.cells[1]
		assert.is_not_nil(cell.member:GetRow("health"):GetBar():GetTint())
		for _, source in ipairs({ "live", "animated", "live", "static" }) do
			wb.dataTarget.set("source", source)
			if source == "live" then
				assert.is_nil(cell.member:GetRow("health"):GetBar():GetTint())
				assert.is_false(cell.status.ReadyCheckIndicator:IsShown())
			else
				assert.is_not_nil(cell.member:GetRow("health"):GetBar():GetTint())
			end
		end
	end)

	it("retains combat source changes and never resumes a retired preview", function()
		local _, CG, wb = Helpers.LoadClickGrid(true)
		wb:Open("clickgrid.panel")
		local old = wb.handle
		Mock.inCombat = true
		wb.dataTarget.set("source", "live")
		wb:Select("clickgrid.target")
		assert.is_true(old.released)
		Mock.inCombat = false
		Mock.FireEvent("PLAYER_REGEN_ENABLED")
		assert.is_true(old.cells[1].member.released)
		assert.is_nil(CG.previews[old])
		assert.is_nil(next(CG.retiredPreviews))
	end)
	it("releases action drop slots without leaving listeners or callbacks", function()
		local UF = Helpers.LoadClickGrid(true)
		local saved = 0
		local slot = UF.Widgets.ActionSlot:New(UIParent, {
			accept = function() return { action = "spell", spell = "2061" } end,
			describe = function(value) return { name = value.action } end,
			onChange = function() saved = saved + 1; return true end,
			empty = { action = "none" },
			extras = { { text = "Open", combatLocked = true, onClick = function() end } },
		})
		slot:SetValue({ action = "none" })
		assert.is_true(slot.frame.__state.events.PLAYER_REGEN_DISABLED)
		slot:Release()
		assert.is_nil(next(slot.frame.__state.events))
		assert.is_nil(slot.slot:GetScript("OnReceiveDrag"))
		assert.is_nil(slot.slot:GetScript("OnClick"))
		Mock.cursorInfo = { "spell", 12, "spell", 2061 }
		slot:Receive()
		assert.equals(0, saved)
		assert.is_not_nil(Mock.cursorInfo)
	end)
end)
