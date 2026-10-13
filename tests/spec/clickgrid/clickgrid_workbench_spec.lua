local Helpers = require("helpers")
local Mock = Helpers.Mock

describe("ClickGrid Workbench", function()
	local UF, CG, wb
	before_each(function() UF, CG, wb = Helpers.LoadClickGrid(true); wb:Open("clickgrid.panel") end)

	it("renders matching flat-grid column headings outside the single backdrop", function()
		CG.Config:Set("panel.mode", "flat")
		CG.Config:Set("panel.columns", 5)
		CG.Config:Set("panel.rows", 5)
		wb.dataTarget.set("count", 25)
		local preview, header = wb.handle, CG.headers.raid
		assert.is_false(preview.labels.raid:IsShown())
		assert.is_false(CG:GetHeaderTitles(header).label:IsShown())
		for column = 1, 5 do
			assert.equals("Group " .. column, preview.labels["column" .. column]:GetText())
			assert.equals("Group " .. column, CG:GetHeaderTitles(header).columns[column]:GetText())
			assert.equals(preview.layout.cellWidth, preview.labels["column" .. column]:GetWidth())
		end
		local cfg = CG.Config:Resolved()
		local section = preview.layout.sections.raid
		local _, _, _, x, y = preview.labels.column2:GetPoint()
		assert.equals(section.x + preview.layout.cellWidth + cfg.panel.spacingX, x)
		assert.equals(-section.y + cfg.titles.gap + cfg.panel.padding, y)
		assert.equals(-CG.Layout.TitleHeight(cfg.titles), select(5, preview.background:GetPoint()))
		CG.Config:Set("titles.group2", "Healers")
		assert.equals("Healers", preview.labels.column2:GetText())
		assert.equals("Healers", CG:GetHeaderTitles(header).columns[2]:GetText())
		CG.Config:Set("titles.enabled", false)
		assert.is_false(preview.labels.column2:IsShown())
		assert.is_false(CG:GetHeaderTitles(header).columns[2]:IsShown())
		CG.Config:Set("panel.mode", "subgroups")
		assert.is_false(preview.labels.column2:IsShown())
		assert.is_false(CG:GetHeaderTitles(header).columns[2]:IsVisible())
	end)

	it("previews five-by-five preferences with safe overflow rather than rewriting either control", function()
		CG.Config:Set("panel.mode", "flat")
		wb.styleTarget.set("panel.columns", 5)
		wb.styleTarget.set("panel.rows", 5)
		wb.dataTarget.set("count", 25)
		local grid = wb.handle.layout.sections.raid.grid
		assert.equals(5, grid.columns)
		assert.equals(5, grid.rows)
		wb.dataTarget.set("count", 40)
		grid = wb.handle.layout.sections.raid.grid
		assert.equals(8, grid.columns)
		assert.equals(5, grid.rows)
		assert.equals(5, CG.Config:Resolved().panel.columns)
		assert.equals(5, CG.Config:Resolved().panel.rows)
		CG.Config:Set("panel.flow", "across")
		grid = wb.handle.layout.sections.raid.grid
		assert.equals(5, grid.columns)
		assert.equals(8, grid.rows)
		assert.equals(40, #wb.handle.cells)
		wb.dataTarget.set("count", 25)
		assert.equals(5, wb.handle.layout.sections.raid.grid.rows)
		assert.is_false(wb.handle.cells[26].frame:IsShown())
	end)

	it("fits the whole configured raid grid inside the stage instead of clipping its first columns", function()
		wb.stage:SetSize(700, 400)
		wb:GetDB().stage.scale = 2
		CG.Config:SetStyle("member", "width", 600)
		wb.dataTarget.set("count", 40)
		local preview = wb.handle
		local width, height = preview.frame:GetSize()
		local expected = math.min(2, 668 / width, 368 / height)
		assert.equals(expected, wb.holder:GetScale())
		assert.equals(2, wb:GetDB().stage.scale)
		assert.same({ "CENTER", wb.holder, "CENTER", 0, 0 }, { preview.frame:GetPoint() })
		assert.same({ "TOPLEFT", preview.frame, "TOPLEFT", preview.layout.sections.group2.x,
			-preview.layout.sections.group2.y }, { preview.cells[6].frame:GetPoint() })
		assert.equals(600, CG.headers.group1:GetAttribute("child1").Member:GetWidth())
		assert.equals(1, CG.panel:GetScale())
		wb.stage:SetSize(400, 300)
		assert.equals(math.min(2, 368 / width, 268 / height), wb.holder:GetScale())
		CG.Config:Set("panel.mode", "flat")
		width, height = preview.frame:GetSize()
		assert.equals(math.min(2, 368 / width, 268 / height), wb.holder:GetScale())
	end)

	it("refits on count changes and restores normal scale after leaving the group preview", function()
		wb.stage:SetSize(500, 400)
		wb.dataTarget.set("count", 40)
		assert.is_true(wb.holder:GetScale() < 1)
		wb.dataTarget.set("count", 1)
		assert.equals(1, wb.holder:GetScale())
		local old = wb.handle
		wb:Select("clickgrid.member")
		assert.is_nil(old.frame:GetScript("OnSizeChanged"))
		assert.is_true(wb.entry.fitToStage)
		wb:GetDB().stage.scale = 1.5
		wb:Select("unit.player")
		assert.equals(1.5, wb.holder:GetScale())
	end)

	it("defers stage fitting during combat and resumes without touching native aura dimensions", function()
		wb.stage:SetSize(700, 400)
		wb.dataTarget.set("count", 40)
		local before = wb.holder:GetScale()
		Mock.inCombat = true
		wb.stage:SetSize(400, 300)
		assert.equals(before, wb.holder:GetScale())
		assert.is_true(wb.pendingStageFit)
		Mock.inCombat = false
		wb:OnUpdate(0.01)
		assert.is_nil(wb.pendingStageFit)
		local width, height = wb.handle.frame:GetSize()
		assert.equals(math.min(1, 368 / width, 268 / height), wb.holder:GetScale())
	end)

	it("shares custom title text and styling with live headers", function()
		wb.dataTarget.set("count", 10)
		wb.styleTarget.set("titles.group1", "Healing team")
		CG.Config:Set("titles.size", 17)
		CG.Config:Set("titles.outline", "OUTLINE")
		CG.Config:Set("titles.color", { 0.2, 0.4, 0.6, 0.8 })
		CG.Config:Set("titles.alignment", "RIGHT")
		CG.Config:Set("titles.shadow", false)
		local live, preview = CG:GetHeaderTitles(CG.headers.group1).label, wb.handle.labels.group1
		assert.equals("Healing team", live:GetText())
		assert.equals(live:GetText(), preview:GetText())
		assert.equals("Group 2", wb.handle.labels.group2:GetText())
		assert.same(live.__state.font, preview.__state.font)
		assert.equals(17, preview.__state.font[2])
		assert.equals("OUTLINE", preview.__state.font[3])
		assert.same({ 0.2, 0.4, 0.6, 0.8 }, preview.__state.textColor)
		assert.equals(CG.layout.sections.group1.grid.width, preview:GetWidth())
		CG.Config:Set("titles.enabled", false)
		assert.is_false(preview:IsShown())
		assert.is_false(live:IsShown())
		CG.Config:Set("titles.enabled", true)
		assert.is_true(preview:IsShown())
		assert.is_true(CG.Config:Set("titles.outline", ""))
		assert.equals("", preview.__state.font[3])
	end)

	it("keeps below-title preview placement inside the solo panel", function()
		wb.dataTarget.set("count", 1)
		CG.Config:Set("titles.position", "below")
		CG.Config:Set("titles.offsetX", 4)
		CG.Config:Set("titles.offsetY", -2)
		local preview, cfg = wb.handle, CG.Config:Resolved()
		local section = preview.layout.sections.party
		assert.same({ "TOPLEFT", preview.frame, "TOPLEFT", section.x + 4,
			-section.y - preview.layout.cellHeight - cfg.titles.gap - cfg.panel.padding - 2 }, { preview.labels.party:GetPoint() })
		assert.equals(preview.layout.solo.height, preview.frame:GetHeight())
	end)

	it("fits party previews to occupied rows for sample and live sources", function()
		for _, flow in ipairs({ "down", "across" }) do
			CG.Config:Set("panel.flow", flow)
			CG.Config:Set("titles.position", "below")
			for _, source in ipairs({ "static", "animated", "live" }) do
				wb.dataTarget.set("source", source)
				for _, count in ipairs({ 2, 5, 3, 1 }) do
					Mock.inParty, Mock.groupSize = count > 1, count
					wb.dataTarget.set("count", count)
					local preview, cfg = wb.handle, CG.Config:Resolved()
					local section = preview.layout.sections.party
					assert.equals(count, section.grid.rows)
					assert.equals(section.grid.height + CG.Layout.TitleHeight(cfg.titles)
						+ 2 * cfg.panel.padding, preview.frame:GetHeight())
					assert.same({ "TOPLEFT", preview.frame, "TOPLEFT", section.x + cfg.titles.offsetX,
						-section.y - section.grid.height - cfg.titles.gap - cfg.panel.padding + cfg.titles.offsetY },
						{ preview.labels.party:GetPoint() })
					if preview.cells[count + 1] then assert.is_false(preview.cells[count + 1].frame:IsShown()) end
				end
			end
		end
	end)

	it("renders enemy targets with NPC reaction colors instead of an absent class token", function()
		assert.has_error(function() C_ClassColor.GetClassColor(nil) end)
		CG.Config:Set("panel.targets", true)
		local target = wb.handle.cells[1].target:GetRow("health"):GetBar()
		assert.same(UF.Config:GetTheme().colors.hostile, target.bar.__state.color)
		assert.has_no_error(function()
			wb:Select("clickgrid.target")
			wb.dataTarget.set("source", "animated")
			wb:OnUpdate(0.2)
		end)
		assert.same(UF.Config:GetTheme().colors.hostile, wb.handle.cells[1].target:GetRow("health"):GetBar().bar.__state.color)
		assert.same({ 0.5, 0.5, 0.5 }, { UF.Colors.Class(nil) })
		assert.same({ UF.Colors.Class("MAGE") }, { UF.Colors.Class(Mock.Secret("MAGE")) })
	end)

	it("does not populate hidden targets in static, animated or live previews", function()
		local target = wb.handle.cells[1].target
		local showSample, showLive = UF.Units.ShowSample, wb.handle.ShowLive
		local samples, liveUpdates = 0, 0
		UF.Units.ShowSample = function(self, uf, values)
			if uf == target then samples = samples + 1 end
			return showSample(self, uf, values)
		end
		wb.handle.ShowLive = function(self, uf, ...)
			if uf == target then liveUpdates = liveUpdates + 1 end
			return showLive(self, uf, ...)
		end
		wb.handle:Apply()
		wb.dataTarget.set("source", "animated")
		wb:OnUpdate(0.2)
		assert.equals(0, samples)
		assert.is_false(target:GetFrame():IsShown())
		CG.Config:Set("panel.targets", true)
		assert.is_true(samples > 0)
		CG.Config:Set("panel.targets", false)
		samples = 0
		wb:OnUpdate(0.2)
		assert.equals(0, samples)
		wb.dataTarget.set("source", "live")
		wb:OnUpdate(0.2)
		assert.equals(0, liveUpdates)
		CG.Config:Set("panel.targets", true)
		assert.is_true(liveUpdates > 0)
	end)

	it("does not tick or apply config after a preview failed to build", function()
		local entry = wb.entries["clickgrid.panel"]
		local create = entry.create
		entry.create = function() error("preview construction failed") end
		assert.has_error(function() wb:Select("clickgrid.panel") end)
		entry.create = create
		assert.is_nil(wb.session)
		assert.has_no_error(function()
			wb:OnUpdate(0.005)
			CG.Config:Set("panel.columns", 2)
		end)
		assert.equals(0, wb.entryState.time)
		assert.has_no_error(function() wb:Select("clickgrid.panel"); wb:OnUpdate(0.005) end)
		assert.is_not_nil(wb.handle)
	end)

	it("uses saved settings for panel and both bar styles", function()
		assert.is_not_nil(wb.entries["clickgrid.bindings"])
		wb.styleTarget.set("panel.columns", 2)
		assert.equals(2, CG.Config:Resolved().panel.columns)
		wb:Select("clickgrid.member")
		wb.styleTarget.set("width", 205)
		assert.equals(205, wb.handle.cells[1].member:GetFrame():GetWidth())
		assert.equals(205, CG.headers.party:GetAttribute("child1").Member:GetWidth())
	end)

	it("matches role placement in previews and removes name reservations when released", function()
		local cell = wb.handle.cells[1]
		local role = cell.status.GroupRoleIndicator
		local name = cell.member:GetRow("health"):GetText("left")
		assert.equals(16, name.leadingSpace)
		-- Sample member 1: marker 12, role 14 and leader 14 at the top, 44 wide.
		CG.Config:Set("indicators.rolePosition", "TOP")
		local frame = cell.member:GetFrame()
		assert.same({ "CENTER", frame, "TOP", -16, 0 }, { cell.member:GetPart("raidTarget"):GetFrame():GetPoint() })
		assert.same({ "CENTER", frame, "TOP", -1, 0 }, { role:GetParent():GetPoint() })
		assert.same({ "CENTER", frame, "TOP", 15, 0 }, { cell.status.LeaderIndicator:GetParent():GetPoint() })
		assert.equals(0, name.leadingSpace)
		CG.Config:Set("indicators.rolePosition", "NAME")
		assert.equals(16, name.leadingSpace)
		CG.Config:SetStyle("member", "health.left.enabled", false)
		assert.is_false(role:GetParent():IsShown())
		assert.equals(0, name.leadingSpace)
		CG.Config:SetStyle("member", "health.left.enabled", true)
		assert.equals(16, name.leadingSpace)
		local status = cell.status
		wb:Select("unit.player")
		assert.equals(0, name.leadingSpace)
		assert.is_true(status.released)
		assert.is_false(status:GetFrame():IsShown())
	end)

	it("matches leader placement in samples and cleans up combined name reservations", function()
		CG.Config:Set("indicators.leaderPosition", "NAME")
		local cell = wb.handle.cells[1]
		local name = cell.member:GetRow("health"):GetText("left")
		assert.equals(32, name.leadingSpace)
		assert.is_true(cell.status.LeaderIndicator:IsShown())
		assert.is_true(wb.handle.cells[2].status.AssistantIndicator:IsShown())
		assert.is_false(wb.handle.cells[2].status.LeaderIndicator:IsShown())
		CG.Config:Set("indicators.leaderPosition", "TOP")
		assert.same({ "CENTER", cell.member:GetFrame(), "TOP", 7, 0 }, { cell.status.LeaderIndicator:GetParent():GetPoint() })
		assert.equals(16, name.leadingSpace)
		CG.Config:Set("indicators.leaderPosition", "NAME")
		wb:Select("unit.player")
		assert.equals(0, name.leadingSpace)
		assert.is_false(cell.status.LeaderIndicator:GetParent():IsVisible())
	end)

	it("samples ready checks, the dead and ghosts in grouped edge icons", function()
		CG.Config:Set("indicators.readyPosition", "TOP")
		CG.Config:Set("indicators.readySize", 14)
		local function Atlas(icon)
			for i = #icon.__calls, 1, -1 do
				if icon.__calls[i][1] == "SetAtlas" then return icon.__calls[i][2] end
			end
		end
		local second, third, fifth = wb.handle.cells[2], wb.handle.cells[3], wb.handle.cells[5]
		-- Member 2 has no marker: assistant 14 + gap 2 + ready check 14.
		local ready = second.status.ReadyCheckIndicator
		assert.is_true(ready:IsShown())
		assert.same({ "CENTER", second.member:GetFrame(), "TOP", -8, 0 }, { second.status.AssistantIndicator:GetParent():GetPoint() })
		assert.same({ "CENTER", second.member:GetFrame(), "TOP", 8, 0 }, { ready:GetParent():GetPoint() })
		local dead, ghost = third.status.UFCG_DeathIndicator, fifth.status.UFCG_DeathIndicator
		assert.is_true(dead:IsShown())
		assert.is_true(ghost:IsShown())
		assert.equals("RaidFrame-Icon-Rez", Atlas(dead))
		assert.equals(Atlas(dead), Atlas(ghost))
		assert.is_false(wb.handle.cells[4].status.UFCG_DeathIndicator:IsShown())
		assert.same({ "CENTER", third.member:GetFrame(), "TOP", -8, 0 }, { dead:GetParent():GetPoint() })
		assert.same({ "CENTER", third.member:GetFrame(), "TOP", 8, 0 }, { third.status.ResurrectIndicator:GetParent():GetPoint() })
		CG.Config:Set("indicators.death", false)
		assert.is_false(dead:IsShown())
		assert.is_false(dead:GetParent():IsShown())
		CG.Config:Set("indicators.readyOrder", 1)
		assert.same({ "CENTER", second.member:GetFrame(), "TOP", -8, 0 }, { ready:GetParent():GetPoint() })
		wb.dataTarget.set("source", "animated")
		wb:OnUpdate(0.2)
		assert.same({ "CENTER", second.member:GetFrame(), "TOP", -8, 0 }, { ready:GetParent():GetPoint() })
	end)

	it("previews green resurrection text and clears it on toggles and release", function()
		local third, fourth = wb.handle.cells[3], wb.handle.cells[4]
		local text = third.member:GetRow("health"):GetText("left")
		assert.same({ 0, 1, 0, 1 }, text:GetFrame().__state.textColor)
		assert.same({ 1, 1, 1, 1 }, fourth.member:GetRow("health"):GetText("left"):GetFrame().__state.textColor)
		assert.is_true(fourth.status.SummonIndicator:IsShown())
		assert.same({ "CENTER", fourth.member:GetFrame(), "TOP", 0, 0 }, { fourth.status.SummonIndicator:GetParent():GetPoint() })
		CG.Config:Set("indicators.resurrectionText", false)
		assert.same({ 1, 1, 1, 1 }, text:GetFrame().__state.textColor)
		CG.Config:Set("indicators.resurrectionText", true)
		assert.same({ 0, 1, 0, 1 }, text:GetFrame().__state.textColor)
		CG.Config:Set("indicators.resurrection", false)
		assert.same({ 1, 1, 1, 1 }, text:GetFrame().__state.textColor)
		assert.same({ "CENTER", third.member:GetFrame(), "TOP", 0, 0 }, { third.status.UFCG_DeathIndicator:GetParent():GetPoint() })
		CG.Config:Set("indicators.resurrection", true)
		wb.dataTarget.set("source", "animated")
		wb:OnUpdate(0.2)
		assert.same({ 0, 1, 0, 1 }, text:GetFrame().__state.textColor)
		third.status:HideIndicators()
		assert.same({ 1, 1, 1, 1 }, text:GetFrame().__state.textColor)
		third.status:ShowSample(3)
		wb:Select("unit.player")
		assert.is_nil(text.colorCondition)
	end)

	it("previews 40 members, animated timers, configured slots and full-health shields #shields", function()
		wb.dataTarget.set("count", 40)
		assert.equals(40, #wb.handle.cells)
		CG.Config:Set("slots.slot1.spell", "139")
		CG.Config:Set("slots.slot1.enabled", true)
		wb:UpdateData()
		local cell = wb.handle.cells[1]
		assert.is_true(cell.slots.samples[1]:IsShown())
		local remaining = cell.member:GetPart("auras").previewData.buffs[3].remaining
		wb:OnUpdate(0.2)
		assert.equals(remaining, cell.member:GetPart("auras").previewData.buffs[3].remaining)
		wb.dataTarget.set("source", "animated")
		wb:OnUpdate(0.2)
		assert.is_true(remaining ~= cell.member:GetPart("auras").previewData.buffs[3].remaining)
		CG.Config:SetStyle("member", "health.bar.segments.absorb.placement", "append")
		wb.dataTarget.set("source", "static")
		assert.equals(28800, cell.member:GetRow("health"):GetBar():GetStatusBar().__state.max)
	end)

	it("shows live opaque data without secret arithmetic and defers source changes in combat", function()
		CG.headers.party:Assign(1, "player")
		assert.has_no_error(function() wb.dataTarget.set("source", "live") end)
		assert.is_true(Mock.IsSecret(wb.handle.cells[1].member:GetRow("health"):GetBar():GetStatusBar().__state.value))
		Mock.inCombat = true
		assert.has_no_error(function()
			wb.dataTarget.set("count", 40)
			wb.dataTarget.set("source", "static")
			wb:Select("clickgrid.target")
		end)
		assert.equals(0, #wb.handle.cells)
		Mock.inCombat = false
		Mock.FireEvent("PLAYER_REGEN_ENABLED")
		assert.is_true(#wb.handle.cells > 0)
		assert.is_nil(next(CG.retiredPreviews))
	end)

	it("previews sparse live raids without assuming consecutive subgroup occupancy", function()
		Mock.inRaid, Mock.groupSize = true, 4
		CG.headers.group8:Assign(1, "raid1")
		wb.dataTarget.set("source", "live")
		assert.equals(40, #wb.handle.cells)
		assert.is_true(wb.handle.cells[36].member:GetFrame():IsShown())
		assert.equals("raid1", wb.handle.cells[36].member:GetPart("auras").containers.buffs:GetUnit())
	end)

	it("releases old previews and their native aura subscriptions when switching entries", function()
		local old = wb.handle
		wb:Select("clickgrid.bindings")
		assert.is_true(old.released)
		assert.is_nil(CG.previews[old])
		assert.is_false(old.cells[1].slots.container:IsEnabled())
		wb.styleTarget.set("friendly.action", "spell")
		wb.styleTarget.set("friendly.spell", "2061")
		assert.equals(2061, CG.headers.party:GetAttribute("child1").Member:GetAttribute("spell-heal1"))
		assert.has_no_error(function() wb:Select("unit.player"); wb:Select("clickgrid.bindings") end)
	end)

	it("edits another binding cell and refreshes on saves without rebuilding the preview", function()
		wb:Select("clickgrid.bindings")
		local session, handle = wb.session, wb.handle
		handle.cells["2:3"].lines.friendly:RunScript("OnClick")
		assert.equals(3, wb.styleTarget.resolved().button)
		assert.equals("shift", wb.styleTarget.resolved().modifier)
		assert.equals("friendly", wb.state.section)
		wb.styleTarget.set("friendly.action", "focus")
		assert.equals(session, wb.session)
		assert.is_false(handle.released == true)
		assert.equals("focus", CG.Config:GetBindings().button3.shift.friendly.action)
		CG.Config:SetBinding(1, "none", "hostile", "action", "assist")
		assert.equals(session, wb.session)
		assert.equals("Target", handle.cells["1:1"].lines.friendly.name:GetText())
		assert.equals("Assist", handle.cells["1:1"].lines.hostile.name:GetText())
	end)

	local function DropSlot(reaction)
		wb:Select("clickgrid.bindings")
		wb:SelectSection(reaction)
		local row = wb.inspector.page.rows[1]
		assert.equals(reaction .. ".drop", row.path)
		return row.control
	end

	local function LastCall(object, name)
		for i = #object.__calls, 1, -1 do
			if object.__calls[i][1] == name then return object.__calls[i] end
		end
	end

	it("saves a dropped spell as one action group and clears the cursor only after saving", function()
		local slot = DropSlot("hostile")
		local frame = CG.headers.party:GetAttribute("child1").Member
		Mock.cursorInfo = { "spell", 12, "spell", 2061 }
		slot.slot:RunScript("OnReceiveDrag")
		assert.is_nil(Mock.cursorInfo)
		assert.same({ action = "spell", spell = "2061" }, CG.Config:GetBindings().button1.none.hostile)
		assert.equals(2061, frame:GetAttribute("spell-harm1"))
		assert.equals("target", frame:GetAttribute("type-heal1"))
		assert.is_nil(frame:GetAttribute("spell-heal1"))
		assert.equals("Flash Heal", slot.name:GetText())
		assert.equals("Active", slot.status:GetText())
		assert.equals(137061, slot.icon:GetTexture())
		-- A click while carrying a spell takes the same path, into the newly selected cell.
		wb.handle.cells["2:3"].lines.hostile:RunScript("OnClick")
		Mock.cursorInfo = { "spell", 3, "spell", 139 }
		slot.slot:RunScript("OnClick")
		assert.is_nil(Mock.cursorInfo)
		assert.same({ action = "spell", spell = "139" }, CG.Config:GetBindings().button3.shift.hostile)
		assert.same({ action = "spell", spell = "2061" }, CG.Config:GetBindings().button1.none.hostile)
		assert.equals(139, frame:GetAttribute("shift-spell-harm3"))
		-- Dropped IDs keep their intent and resolve overrides at compile time.
		Mock.spellOverrides[139] = 140
		Mock.FireEvent("SPELLS_CHANGED")
		assert.equals(140, frame:GetAttribute("shift-spell-harm3"))
	end)

	it("rejects unsupported or unsaved drops without touching the binding or the cursor", function()
		local slot = DropSlot("friendly")
		for _, cursor in ipairs({ { "item", 6948, "item:6948" }, { "macro", 3 }, { "petaction", 5 } }) do
			Mock.cursorInfo = cursor
			slot.slot:RunScript("OnReceiveDrag")
			assert.equals(cursor, Mock.cursorInfo)
			assert.equals("Only spells can be dropped here", slot.status:GetText())
		end
		assert.is_nil(CG.Config:GetBindings().button1)
		Mock.cursorInfo = nil
		slot.slot:RunScript("OnClick")
		assert.is_nil(CG.Config:GetBindings().button1)
		local setAction = CG.Config.SetAction
		CG.Config.SetAction = function() return false, "Store rejected the action" end
		Mock.cursorInfo = { "spell", 12, "spell", 2061 }
		slot.slot:RunScript("OnReceiveDrag")
		CG.Config.SetAction = setAction
		assert.same({ "spell", 12, "spell", 2061 }, Mock.cursorInfo)
		assert.equals("Store rejected the action", slot.status:GetText())
		assert.is_nil(CG.Config:GetBindings().button1)
		assert.equals("target", CG.headers.party:GetAttribute("child1").Member:GetAttribute("type-heal1"))
	end)

	it("clears a slot to unbound and summarises both reactions with inactive states", function()
		Mock.unknownSpells[139] = true
		local slot = DropSlot("friendly")
		Mock.cursorInfo = { "spell", 12, "spell", 139 }
		slot.slot:RunScript("OnReceiveDrag")
		assert.is_nil(Mock.cursorInfo)
		assert.equals("Not learned in this specialization", slot.status:GetText())
		assert.is_true(LastCall(slot.icon, "SetDesaturated")[2])
		local cell = wb.handle.cells["1:1"]
		assert.equals("Spell 139", cell.lines.friendly.name:GetText())
		assert.equals(135139, cell.lines.friendly.icon:GetTexture())
		assert.is_true(LastCall(cell.lines.friendly.icon, "SetDesaturated")[2])
		assert.equals(UF.Skin.colors.warning[1], cell.lines.friendly.name.__state.textColor[1])
		assert.equals("Target", cell.lines.hostile.name:GetText())
		slot.clear.opts.onClick()
		assert.same({ action = "none" }, CG.Config:GetBindings().button1.none.friendly)
		assert.is_nil(CG.headers.party:GetAttribute("child1").Member:GetAttribute("type-heal1"))
		assert.equals("Unbound", slot.name:GetText())
		assert.is_false(LastCall(slot.clear.frame, "SetEnabled")[2])
		assert.equals("Unbound", cell.lines.friendly.name:GetText())
		-- The manual alternative still edits the same group.
		wb.styleTarget.set("friendly.action", "spell")
		wb.styleTarget.set("friendly.spell", "Flash Heal")
		assert.equals(2061, CG.headers.party:GetAttribute("child1").Member:GetAttribute("spell-heal1"))
	end)

	it("binds spells dropped straight onto a grid line, like the drop slots", function()
		wb:Select("clickgrid.bindings")
		local handle, frame = wb.handle, CG.headers.party:GetAttribute("child1").Member
		local line = handle.cells["3:2"].lines.friendly
		Mock.cursorInfo = { "spell", 12, "spell", 2061 }
		line:RunScript("OnReceiveDrag")
		assert.is_nil(Mock.cursorInfo)
		assert.same({ action = "spell", spell = "2061" }, CG.Config:GetBindings().button2.ctrl.friendly)
		assert.equals(2061, frame:GetAttribute("ctrl-spell-heal2"))
		assert.equals("Flash Heal", line.name:GetText())
		assert.equals(137061, line.icon:GetTexture())
		-- The dropped cell becomes the edited one, on the dropped reaction's page.
		assert.equals(2, wb.styleTarget.resolved().button)
		assert.equals("ctrl", wb.styleTarget.resolved().modifier)
		assert.equals("friendly", wb.state.section)
		assert.equals("Flash Heal", wb.inspector.page.rows[1].control.name:GetText())
		assert.same(UF.Skin.colors.accent, handle.cells["3:2"].__state.backdropBorderColor)
		assert.same(UF.Skin.colors.border, handle.cells["1:1"].__state.backdropBorderColor)
		-- A click while carrying a spell binds instead of selecting.
		Mock.cursorInfo = { "spell", 3, "spell", 139 }
		handle.cells["3:2"].lines.hostile:RunScript("OnClick")
		assert.is_nil(Mock.cursorInfo)
		assert.equals(139, frame:GetAttribute("ctrl-spell-harm2"))
		assert.equals("hostile", wb.state.section)
	end)

	it("rejects grid drops without touching the binding or the cursor, and says why", function()
		wb:Select("clickgrid.bindings")
		local handle = wb.handle
		local line = handle.cells["1:1"].lines.friendly
		Mock.cursorInfo = { "item", 6948, "item:6948" }
		line:RunScript("OnReceiveDrag")
		assert.same({ "item", 6948, "item:6948" }, Mock.cursorInfo)
		assert.is_nil(CG.Config:GetBindings().button1)
		assert.equals("Target", line.name:GetText())
		assert.is_true(handle.note:GetText():find("Only spells can be dropped here", 1, true) ~= nil)
		local setAction = CG.Config.SetAction
		CG.Config.SetAction = function() return false, "Store rejected the action" end
		Mock.cursorInfo = { "spell", 12, "spell", 2061 }
		line:RunScript("OnClick")
		CG.Config.SetAction = setAction
		assert.same({ "spell", 12, "spell", 2061 }, Mock.cursorInfo)
		assert.is_true(handle.note:GetText():find("Store rejected the action", 1, true) ~= nil)
		assert.is_nil(CG.Config:GetBindings().button1)
		-- Selecting with an empty cursor clears the message.
		Mock.cursorInfo = nil
		line:RunScript("OnClick")
		assert.is_nil(handle.note:GetText():find("rejected", 1, true))
	end)

	it("fills the stage and fits the binding grid to its size", function()
		wb:Select("clickgrid.bindings")
		local handle = wb.handle
		local point, relativeTo = handle.frame:GetPoint(1)
		assert.equals("TOPLEFT", point)
		assert.equals(wb.stage, relativeTo)
		assert.equals(wb.stage, select(2, handle.frame:GetPoint(2)))
		assert.is_false(wb.widthSlider:GetFrame():IsShown())
		local function Cell(key) return handle.cells[key] end
		handle.frame:SetSize(1000, 600)
		local wide, tall = Cell("1:1"):GetWidth(), Cell("1:1"):GetHeight()
		assert.equals(180, wide)
		assert.equals(select(4, Cell("1:1"):GetPoint()) + wide + 3, select(4, Cell("1:2"):GetPoint()))
		assert.is_true(tall > 30 and tall <= 52)
		assert.equals("Left", handle.columns[1]:GetText())
		assert.equals("Alt+Ctrl+Shift", handle.rows[8]:GetText())
		handle.frame:SetSize(500, 300)
		assert.equals(80, Cell("1:1"):GetWidth())
		assert.equals(30, Cell("1:1"):GetHeight())
		assert.equals(14, Cell("1:1").lines.friendly:GetHeight())
		assert.equals(select(4, Cell("8:5"):GetPoint()), 84 + 3 + 4 * 83)
	end)

	it("releases the binding grid's drop targets when switching entries", function()
		wb:Select("clickgrid.bindings")
		local handle, line = wb.handle, wb.handle.cells["1:1"].lines.friendly
		wb:Select("clickgrid.panel")
		assert.is_true(handle.released)
		assert.is_nil(line:GetScript("OnReceiveDrag"))
		assert.is_nil(line:GetScript("OnClick"))
	end)

	it("opens the spellbook only outside combat", function()
		local opener = DropSlot("friendly").buttons[2]
		opener.opts.onClick()
		assert.equals(1, Mock.spellBookOpened)
		Mock.FireEvent("PLAYER_REGEN_DISABLED")
		Mock.inCombat = true
		assert.is_false(LastCall(opener.frame, "SetEnabled")[2])
		opener.opts.onClick()
		assert.equals(1, Mock.spellBookOpened)
		Mock.inCombat = false
		Mock.FireEvent("PLAYER_REGEN_ENABLED")
		assert.is_true(LastCall(opener.frame, "SetEnabled")[2])
	end)

	it("restyles only the ClickGrid entries when ClickGrid settings change", function()
		wb:Select("unit.player")
		local session = wb.session
		CG.Config:Set("panel.columns", 3)
		assert.equals(session, wb.session)
		assert.is_false(session.released == true)
	end)

	it("registers entries when Workbench was loaded before the companion", function()
		local core, workbench = Helpers.LoadWorkbench()
		Helpers.LoadToc("UnitFrames_ClickGrid/UnitFrames_ClickGrid.toc", "UnitFrames_ClickGrid")
		Mock.FireEvent("ADDON_LOADED", "UnitFrames_ClickGrid")
		Mock.FireEvent("PLAYER_LOGIN")
		assert.is_not_nil(workbench.entries["clickgrid.panel"])
		assert.equals(core.ClickGrid, UnitFrames.ClickGrid)
	end)
end)
