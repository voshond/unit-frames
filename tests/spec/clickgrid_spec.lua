local Helpers = require("helpers")
local Mock = Helpers.Mock

describe("ClickGrid companion", function()
	local UF, CG
	before_each(function() UF, CG = Helpers.LoadClickGrid() end)

	it("keeps standalone units separate and prepares party and all raid subgroup capacity", function()
		assert.equals(CG, UF.ClickGrid)
		for _, key in ipairs(UF.Units.order) do
			assert.is_not_nil(UF.Units.definitions[key])
			assert.is_false(key == "member" or key == "clickgrid")
		end
		assert.equals(9, #UF.oUF.headers)
		assert.equals(90, #CG.frames)
		for key, header in pairs(CG.headers) do
			assert.is_not_nil(header:GetAttribute("child5"), key)
			assert.equals(1, header:GetAttribute("startingIndex"))
		end
		assert.is_true(CG.headers.party:GetAttribute("showParty"))
		assert.is_false(CG.headers.party:GetAttribute("showRaid"))
		assert.equals("1", CG.headers.group1:GetAttribute("groupFilter"))
		assert.equals("8", CG.headers.group8:GetAttribute("groupFilter"))
		assert.equals(UF.Units.STYLE, UF.oUF:GetActiveStyle())
	end)

	it("runs the embedded oUF header initializer on the structural cell and both unit children", function()
		local file = assert(io.open("UnitFrames/Libs/oUF/ouf.lua"))
		local source = file:read("*a"); file:close()
		local body = assert(source:match("local initialConfigFunction = %[%[(.-)%]%]"))
		local header = CG.headers.party
		-- oUF must guess raid while precreating units, before this header is
		-- switched to party. This exercises the real snippet, not its stand-in.
		header:SetAttribute("showRaid", true)
		local cell = header:GetAttribute("child1")
		local styled
		function cell:GetChildList(frames) frames[#frames + 1] = self.Member; frames[#frames + 1] = self.Target end
		for _, frame in ipairs({ cell, cell.Member, cell.Target }) do
			-- Restricted snippets receive self as a global, not a vararg.
			function frame:Run(code)
				local chunk = assert(loadstring(code))
				setfenv(chunk, setmetatable({ self = self }, { __index = _G }))
				chunk()
			end
		end
		function header:CallMethod(_, name) styled = name end
		function header:GetFrameRef() return nil end
		local restrictedTable = { new = function() return {} end, insert = table.insert }
		local initialize = assert(loadstring(body))
		setfenv(initialize, setmetatable({ self = cell, table = restrictedTable }, { __index = _G }))
		assert.has_no_error(initialize)
		assert.equals(cell:GetName(), styled)
		assert.equals("raid", cell.Member:GetAttribute("oUF-guessUnit"))
		assert.equals("raidtarget", cell.Target:GetAttribute("oUF-guessUnit"))
		assert.is_true(cell.Member:GetAttribute("useparent-unit"))
		assert.is_true(cell.Member:GetAttribute("toggleForVehicle"))
		assert.is_false(cell.Target:GetAttribute("toggleForVehicle"))
		assert.equals(CG.metrics.member.height, cell:GetHeight())
	end)

	it("creates alternate layouts outside combat and preserves all 40 primary slots", function()
		assert.is_true(CG.Config:Set("panel.mode", "flat"))
		local header = CG.headers.raid
		assert.is_not_nil(header:GetAttribute("child40"))
		assert.equals("custom hide", CG.headers.group1.visibility)
		assert.equals("custom [group:raid] show; hide", header.visibility)
		assert.is_true(CG.Config:Set("panel.columns", 1))
		assert.equals(40, CG.Config:Resolved().panel.rows)
		assert.equals(40, header:GetAttribute("unitsPerColumn"))
		assert.is_true(CG.Config:Set("panel.rows", 4))
		assert.equals(10, CG.Config:Resolved().panel.columns)
		assert.is_false(CG.Config:Set("panel.rows", 1))
	end)

	it("compiles row-first layout spacing with positive native column spacing", function()
		local cfg = CG.Config:Resolved().panel
		cfg.mode, cfg.flow, cfg.columns, cfg.rows = "flat", "across", 5, 8
		local layout = CG.Layout.Compute(cfg, CG.metrics.member, CG.metrics.target)
		local attr = CG.Layout.Attributes(layout.sections.raid.grid, cfg)
		assert.equals("LEFT", attr.point)
		assert.equals("TOP", attr.columnAnchorPoint)
		assert.equals(cfg.spacingY, attr.columnSpacing)
		local x, y = CG.Layout.Cell(6, 5, 8, cfg.flow, layout.cellWidth, layout.cellHeight, cfg.spacingX, cfg.spacingY)
		assert.equals(0, x)
		assert.equals(layout.cellHeight + cfg.spacingY, y)
	end)

	it("uses independent member defaults and inherited styles", function()
		assert.equals(150, CG.definitions.member.width)
		assert.equals(170, UF.Units.definitions.pet.width)
		local member = CG.headers.party:GetAttribute("child1").Member
		assert.is_nil(member.UF_Experience)
		assert.equals(member.uf:GetRow("health"):GetBar():GetStatusBar(), member.Health)
		assert.equals(Enum.UnitDamageAbsorbClampMode.MaximumHealth, member.Health.damageAbsorbClampMode)
		assert.equals(120, member.uf:GetAuras().resolved.buffs.maxDuration)
		assert.equals("unitDebuff", member.uf:GetAuras().resolved.debuffs.sort)
		assert.is_true(member.uf:GetRow("health"):GetText("left").deferInCombat)
		local auraButton = member.uf:GetAuras().containers.buffs.__state.groups.buffs.frames[1]
		local clickThrough = false
		for _, call in ipairs(auraButton.__calls) do
			if call[1] == "SetMouseClickEnabled" and call[2] == false then clickThrough = true end
		end
		assert.is_true(clickThrough)
	end)

	it("queues geometry and bindings without touching secure frames during combat", function()
		local member = CG.headers.party:GetAttribute("child1").Member
		local originalWidth = member:GetWidth()
		local oldSet = member.SetAttribute
		member.SetAttribute = function(self, ...)
			assert.is_false(Mock.inCombat)
			return oldSet(self, ...)
		end
		Mock.inCombat = true
		assert.is_true(CG.Config:SetStyle("member", "width", 200))
		assert.is_true(CG.Config:Set("panel.targets", true))
		assert.is_true(CG.Config:SetBinding(1, "shift", "friendly", "action", "spell"))
		assert.is_true(CG.Config:SetBinding(1, "shift", "friendly", "spell", "2061"))
		assert.is_true(CG.pending)
		assert.equals(originalWidth, member:GetWidth())
		Mock.inCombat = false
		Mock.FireEvent("PLAYER_REGEN_ENABLED")
		assert.is_nil(CG.pending)
		assert.equals(200, member:GetWidth())
		assert.equals(2061, member:GetAttribute("shift-spell-heal1"))
		assert.is_true(CG.headers.party:GetAttribute("child1").Target.__state.unitWatched)
	end)

	it("lets a header assign a different member and its target in combat without building widgets", function()
		local header = CG.headers.group1
		local count = #CG.frames
		Mock.inCombat = true
		header:Assign(1, "raid22")
		local cell = header:GetAttribute("child1")
		assert.equals("raid22", cell.Member.__unit)
		assert.equals("raid22target", cell.Target.__unit)
		assert.has_no_error(function()
			UF.oUF.elements.UF_Auras.update(cell.Member)
			UF.oUF.elements.UFCG_Slots.update(cell.Member)
		end)
		assert.equals("raid22", cell.Member.ufcgSlots.container:GetUnit())
		assert.equals(count, #CG.frames)
		header:Assign(1, nil)
		assert.has_no_error(function() UF.oUF.elements.UF_Auras.update(cell.Member) end)
		Mock.inCombat = false
	end)

	it("registers status and private aura widgets with pre-created anchors", function()
		local member = CG.headers.party:GetAttribute("child1").Member
		assert.is_true(member:IsElementEnabled("GroupRoleIndicator"))
		assert.is_true(member:IsElementEnabled("ReadyCheckIndicator"))
		-- The base mock has no private aura API. Absence is a capability, not an error.
		assert.is_false(member:IsElementEnabled("PrivateAuras"))
		assert.equals(3, #member.ufcgStatus.PrivateAuras)
		assert.is_nil(member.ThreatIndicator)
		CG.Config:Set("indicators.threat", true)
		member.__unit = "raid1"
		local previous = UnitThreatSituation
		UnitThreatSituation = function() return Mock.Secret(3) end
		assert.has_no_error(function() member.ThreatIndicator.Override(member) end)
		UnitThreatSituation = previous
	end)

	it("keeps profile style separate from character/spec bindings", function()
		CG.Config:SetStyle("member", "width", 190)
		CG.Config:SetBinding(1, "none", "friendly", "spell", "2061")
		Mock.specIndex = 2
		assert.is_nil(next(CG.Config:GetBindings()))
		CG.Config:SetBinding(1, "none", "friendly", "spell", "139")
		Mock.specIndex = 1
		assert.equals("2061", CG.Config:GetBindings().button1.none.friendly.spell)
		UF.Config.db:SetProfile("Another")
		assert.is_nil(CG.Config:GetStyle("member").width)
		assert.equals("2061", CG.Config:GetBindings().button1.none.friendly.spell)
	end)

	it("resolves every modifier and clears previous spells and wildcard actions", function()
		local B, config = CG.Bindings, {}
		for i, modifier in ipairs(B.modifiers) do
			UF.Util.SetPath(config, "button1." .. modifier[1] .. ".friendly", { action = "spell", spell = tostring(2060 + i) })
		end
		local frame = CG.headers.party:GetAttribute("child1").Member
		local plan, errors = B:Compile(config)
		assert.equals(0, #errors)
		B:Apply(frame, plan)
		for i, modifier in ipairs(B.modifiers) do assert.equals(2060 + i, frame:GetAttribute(modifier[3] .. "spell-heal1")) end
		B:Apply(frame, B:Compile({}))
		assert.is_nil(frame:GetAttribute("shift-spell-heal1"))
		assert.is_nil(frame:GetAttribute("*type1"))
		assert.equals("target", frame:GetAttribute("type-heal1"))
		assert.equals("togglemenu", frame:GetAttribute("type-harm2"))
	end)

	it("keeps unknown spell intent and resolves overrides after spell updates", function()
		Mock.unknownSpells[2061] = true
		CG.Config:SetBinding(1, "none", "friendly", "action", "spell")
		CG.Config:SetBinding(1, "none", "friendly", "spell", "2061")
		local frame = CG.headers.party:GetAttribute("child1").Member
		assert.is_nil(frame:GetAttribute("type-heal1"))
		assert.equals("2061", CG.Config:GetBindings().button1.none.friendly.spell)
		assert.equals(1, #CG.bindingErrors)
		Mock.spellOverrides[2061], Mock.unknownSpells[2061] = 2062, nil
		Mock.FireEvent("SPELLS_CHANGED")
		assert.equals(2062, frame:GetAttribute("spell-heal1"))
		assert.equals(0, #CG.bindingErrors)
	end)

	it("respects Clique ownership and does not rewrite its attributes", function()
		local frame = CG.headers.party:GetAttribute("child1").Member
		Clique = {}
		frame:SetAttribute("type-heal1", "external")
		CG:RequestRefresh()
		assert.equals("external", frame:GetAttribute("type-heal1"))
		Clique = nil
	end)

	it("keeps shield scale options correct across placement and repeated toggles", function()
		local frame = CG.headers.party:GetAttribute("child1").Member
		CG.Config:SetStyle("member", "health.bar.segments.absorb.placement", "append")
		assert.equals(Enum.UnitMaximumHealthMode.WithAbsorbs, frame.Health.maximumHealthClampMode)
		CG.Config:SetStyle("member", "health.bar.segments.absorb.enabled", false)
		assert.equals(Enum.UnitMaximumHealthMode.Default, frame.Health.maximumHealthClampMode)
		CG.Config:SetStyle("member", "health.bar.segments.absorb.enabled", true)
		assert.equals(Enum.UnitMaximumHealthMode.WithAbsorbs, frame.Health.maximumHealthClampMode)
	end)

	it("validates fixed friendly-buff IDs and passes them to native slots", function()
		assert.is_false(CG.Config:Set("slots.slot1.spell", "139, invalid"))
		assert.is_false(CG.Config:Set("slots.slot1.spell", "1e999"))
		CG.Config:Set("slots.slot1.spell", "139,774")
		CG.Config:Set("slots.slot1.enabled", true)
		local slots = CG.headers.party:GetAttribute("child1").Member.ufcgSlots
		local native = slots.container.__state.slots.slot1
		assert.equals("HELPFUL|PLAYER", native.filter)
		assert.same({ [139] = true, [774] = true }, native.candidateFilters.includeSpellIDs)
		CG.Config:Set("slots.slot1.enabled", false)
		assert.same({}, native.candidateFilters.includeSpellIDs)
		assert.is_nil(UF.Schema.Find(CG.SlotSchema, "slot1.debuff"))
	end)
end)

describe("ClickGrid Workbench", function()
	local UF, CG, wb
	before_each(function() UF, CG, wb = Helpers.LoadClickGrid(true); wb:Open("clickgrid.panel") end)

	it("renders enemy targets with NPC reaction colors instead of an absent class token", function()
		assert.has_error(function() C_ClassColor.GetClassColor(nil) end)
		CG.Config:Set("panel.targets", true)
		local target = wb.handle.cells[1].target:GetRow("health"):GetBar()
		assert.same(UF.Config:GetTheme().colors.hostile, target.bar.__state.color)
		assert.has_no_error(function()
			wb:Select("clickgrid.target")
			wb.state.data.source = "animated"
			wb:OnUpdate(0.2)
		end)
		assert.same(UF.Config:GetTheme().colors.hostile, wb.handle.cells[1].target:GetRow("health"):GetBar().bar.__state.color)
		assert.same({ 0.5, 0.5, 0.5 }, { UF.Colors.Class(nil) })
		assert.same({ UF.Colors.Class("MAGE") }, { UF.Colors.Class(Mock.Secret("MAGE")) })
	end)

	it("does not tick or apply config to an absent preview handle", function()
		local preview = wb.handle
		preview:Release()
		wb.handle = nil
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

	it("previews 40 members, animated timers, configured slots and full-health shields", function()
		wb.state.data.count = 40
		wb:UpdateData()
		assert.equals(40, #wb.handle.cells)
		CG.Config:Set("slots.slot1.spell", "139")
		CG.Config:Set("slots.slot1.enabled", true)
		wb:UpdateData()
		local cell = wb.handle.cells[1]
		assert.is_true(cell.slots.samples[1]:IsShown())
		local remaining = cell.member:GetAuras().previewData.buffs[3].remaining
		wb:OnUpdate(0.2)
		assert.equals(remaining, cell.member:GetAuras().previewData.buffs[3].remaining)
		wb.state.data.source = "animated"
		wb:OnUpdate(0.2)
		assert.is_true(remaining ~= cell.member:GetAuras().previewData.buffs[3].remaining)
		CG.Config:SetStyle("member", "health.bar.segments.absorb.placement", "append")
		wb.state.data.source = "static"
		wb:UpdateData()
		assert.equals(28800, cell.member:GetRow("health"):GetBar():GetStatusBar().__state.max)
	end)

	it("shows live opaque data without secret arithmetic and defers source changes in combat", function()
		CG.headers.party:Assign(1, "player")
		wb.state.data.source = "live"
		assert.has_no_error(function() wb:UpdateData() end)
		assert.is_true(Mock.IsSecret(wb.handle.cells[1].member:GetRow("health"):GetBar():GetStatusBar().__state.value))
		Mock.inCombat = true
		wb.state.data.count, wb.state.data.source = 40, "static"
		assert.has_no_error(function() wb:UpdateData(); wb:Select("clickgrid.target") end)
		assert.equals(0, #wb.handle.cells)
		Mock.inCombat = false
		Mock.FireEvent("PLAYER_REGEN_ENABLED")
		assert.is_true(#wb.handle.cells > 0)
		assert.is_nil(next(CG.retiredPreviews))
	end)

	it("previews sparse live raids without assuming consecutive subgroup occupancy", function()
		Mock.inRaid, Mock.groupSize = true, 4
		CG.headers.group8:Assign(1, "raid1")
		wb.state.data.source = "live"
		wb:UpdateData()
		assert.equals(40, #wb.handle.cells)
		assert.is_true(wb.handle.cells[36].member:GetFrame():IsShown())
		assert.equals("raid1", wb.handle.cells[36].member:GetAuras().containers.buffs:GetUnit())
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

	it("registers entries when Workbench was loaded before the companion", function()
		local core, workbench = Helpers.LoadWorkbench()
		Helpers.LoadToc("UnitFrames_ClickGrid/UnitFrames_ClickGrid.toc", "UnitFrames_ClickGrid")
		Mock.FireEvent("ADDON_LOADED", "UnitFrames_ClickGrid")
		Mock.FireEvent("PLAYER_LOGIN")
		assert.is_not_nil(workbench.entries["clickgrid.panel"])
		assert.equals(core.ClickGrid, UnitFrames.ClickGrid)
	end)
end)
