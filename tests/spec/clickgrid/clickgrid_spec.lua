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

	it("resolves each style once per refresh and keeps member aura config apart from slots", function()
		CG:Refresh()
		local a = CG.headers.party:GetAttribute("child1")
		local b = CG.headers.group3:GetAttribute("child2")
		assert.equals(a.Member.uf.resolved, b.Member.uf.resolved)
		assert.equals(a.Member.uf:GetPart("auras").resolved, b.Member.uf:GetPart("auras").resolved)
		assert.is_true(a.Member.uf.resolved ~= a.Target.uf.resolved)
		local auras = a.Member.uf:GetPart("auras").config
		assert.is_nil(auras.slot1, "slot settings are not merged into the shared aura config")
		assert.is_not_nil(CG:GetGridButton(a.Member).slots.resolved.slot1)
		local before = a.Member.uf.resolved
		CG.Config:SetStyle("member", "width", 151)
		assert.is_true(before ~= a.Member.uf.resolved, "a later refresh resolves afresh")
		assert.equals(a.Member.uf.resolved, b.Member.uf.resolved)
		assert.equals(151, b.Member.uf.resolved.width)
	end)

	it("offers independent aura rows and stops their native feeds on hidden targets", function()
		CG.Config:SetStyle("member", "auraBar.enabled", true)
		CG.Config:SetStyle("target", "auraBar.enabled", true)
		CG.Config:Set("panel.targets", true)
		local cell = CG.headers.party:GetAttribute("child1")
		assert.is_true(cell.Member.uf:GetPart("auraBar"):IsEnabled())
		assert.is_true(cell.Target.uf:GetPart("auraBar"):GetContainer("buffs"):IsEnabled())
		CG.Config:Set("panel.targets", false)
		assert.is_false(cell.Target.uf:GetPart("auraBar"):GetContainer("buffs"):IsEnabled())
		local preview = CG.Preview:New(UIParent)
		preview:ShowData({ source = "static", count = 1 })
		local sample = preview.cells[1]
		assert.is_true(sample.member:GetPart("auraBar"):IsEnabled())
		preview:HideCell(sample)
		assert.is_false(sample.member:GetPart("auraBar"):IsEnabled())
		preview:Release()
	end)

	it("keeps addon state off the secure unit buttons and headers", function()
		local function NoAddonFields(frame, name)
			for key in pairs(frame) do
				local addonKey = type(key) == "string" and (key:match("^ufcg") or key == "ufReady")
				assert.is_true(not addonKey, name .. " carries " .. tostring(key))
			end
		end
		for _, frame in ipairs(CG.frames) do NoAddonFields(frame, frame:GetName()) end
		for key, header in pairs(CG.headers) do NoAddonFields(header, key) end
		for unit, frame in pairs(UF.Units.frames) do NoAddonFields(frame, unit) end
		local cell = CG.headers.party:GetAttribute("child1")
		assert.equals("member", CG:GetGridButton(cell.Member).kind)
		assert.is_not_nil(CG:GetGridButton(cell.Member).status)
		assert.equals("target", CG:GetGridButton(cell.Target).kind)
		assert.is_nil(CG:GetGridButton(cell.Target).slots, "targets have no member extras")
		assert.is_nil(CG:GetGridButton(cell), "the structural cell is not a unit button")
		assert.is_not_nil(CG:GetHeaderTitles(CG.headers.party).label)
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

	it("shrinks party bounds and selects precomputed roster sizes during combat", function()
		Mock.inParty, Mock.groupSize = true, 2
		CG:Refresh()
		local cfg, layout = CG.Config:Resolved(), CG.layout
		local function Height(count)
			return count * layout.cellHeight + (count - 1) * cfg.panel.spacingY
				+ CG.Layout.TitleHeight(cfg.titles) + 2 * cfg.panel.padding
		end
		assert.equals(Height(2), CG.panel:GetHeight())
		assert.equals("[group:raid] raid; [@party4,exists] party5; [@party3,exists] party4; [@party2,exists] party3; [group:party] party2; solo",
			CG.panel.__state.drivers.roster)
		assert.equals(5, CG.headers.party:GetAttribute("unitsPerColumn"))
		assert.is_not_nil(CG.headers.party:GetAttribute("child5"))
		local resize = assert(loadstring(CG.panel:GetAttribute("_onstate-roster")))
		local env = setmetatable({ self = CG.panel }, { __index = _G })
		setfenv(resize, env)
		local frames = #CG.frames
		Mock.inCombat = true
		for _, count in ipairs({ 3, 5, 4, 2 }) do
			env.newstate = "party" .. count
			-- Secure state snippets run untainted: they may resize protected frames in combat.
			assert.has_no_error(function() Mock.RunUntainted(resize) end)
			assert.equals(Height(count), CG.panel:GetHeight())
			assert.equals(layout.party.width, CG.panel:GetWidth())
		end
		env.newstate = "raid"
		Mock.RunUntainted(resize)
		assert.equals(layout.raid.height, CG.panel:GetHeight())
		env.newstate = "solo"
		Mock.RunUntainted(resize)
		assert.equals(Height(1), CG.panel:GetHeight())
		assert.equals(frames, #CG.frames)
		Mock.inCombat = false
		Mock.groupSize = 4
		CG:Refresh()
		assert.equals(Height(4), CG.panel:GetHeight())
	end)

	it("creates alternate layouts outside combat and preserves all 40 primary slots", function()
		assert.is_true(CG.Config:Set("panel.mode", "flat"))
		local header = CG.headers.raid
		assert.is_not_nil(header:GetAttribute("child40"))
		assert.equals("custom hide", CG.headers.group1.visibility)
		assert.equals("custom [group:raid] show; hide", header.visibility)
		assert.is_true(CG.Config:Set("panel.columns", 1))
		assert.equals(10, CG.Config:Resolved().panel.rows)
		assert.equals(10, header:GetAttribute("unitsPerColumn"))
		assert.equals(4, header:GetAttribute("maxColumns"))
		assert.is_true(CG.Config:Set("panel.rows", 4))
		assert.equals(1, CG.Config:Resolved().panel.columns)
		assert.equals(10, header:GetAttribute("maxColumns"))
		assert.is_true(CG.Config:Set("panel.rows", 1))
		assert.equals(40, header:GetAttribute("maxColumns"))
		assert.is_false(CG.Config:Set("panel.rows", 0))
	end)

	it("preserves independent five-by-five preferences and forty-member secure capacity in both flows", function()
		CG.Config:Set("panel.mode", "flat")
		CG.Config:Set("panel.columns", 5)
		CG.Config:Set("panel.rows", 5)
		local header = CG.headers.raid
		assert.equals(5, CG.Config:Resolved().panel.columns)
		assert.equals(5, CG.Config:Resolved().panel.rows)
		assert.equals(5, header:GetAttribute("unitsPerColumn"))
		assert.equals(8, header:GetAttribute("maxColumns"))
		assert.is_not_nil(header:GetAttribute("child40"))
		CG.Config:Set("panel.flow", "across")
		assert.equals(5, CG.Config:Resolved().panel.columns)
		assert.equals(5, CG.Config:Resolved().panel.rows)
		assert.equals(5, header:GetAttribute("unitsPerColumn"))
		assert.equals(8, header:GetAttribute("maxColumns"))
		assert.equals(8, CG.layout.sections.raid.grid.rows)
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

	it("reserves title size and gap without changing grid spacing", function()
		local cfg = CG.Config:Resolved()
		local original = CG.Layout.Compute(cfg.panel, CG.metrics.member, CG.metrics.target, cfg.titles)
		assert.equals("Group 1", CG:GetHeaderTitles(CG.headers.group1).label:GetText())
		CG.Config:Set("titles.size", 20)
		CG.Config:Set("titles.gap", 9)
		cfg = CG.Config:Resolved()
		local larger = CG.Layout.Compute(cfg.panel, CG.metrics.member, CG.metrics.target, cfg.titles)
		assert.equals(original.party.height + 13, larger.party.height)
		assert.same(original.sections.party.grid, larger.sections.party.grid)
		CG.Config:Set("titles.position", "below")
		cfg = CG.Config:Resolved()
		local below = CG.Layout.Compute(cfg.panel, CG.metrics.member, CG.metrics.target, cfg.titles)
		assert.equals(larger.raid.height, below.raid.height)
		assert.equals(cfg.panel.padding, below.sections.group1.y)
		CG.Config:Set("titles.enabled", false)
		cfg = CG.Config:Resolved()
		local hidden = CG.Layout.Compute(cfg.panel, CG.metrics.member, CG.metrics.target, cfg.titles)
		assert.equals(below.party.height - 31, hidden.party.height)
		assert.is_false(CG:GetHeaderTitles(CG.headers.party).label:IsShown())
		CG.Config:Set("titles.enabled", true)
		assert.is_true(CG:GetHeaderTitles(CG.headers.party).label:IsShown())
	end)

	it("anchors titles to native headers and defers changes during combat", function()
		local header = CG.headers.party
		local label = CG:GetHeaderTitles(header).label
		CG.Config:Set("titles.offsetX", 7)
		CG.Config:Set("titles.offsetY", -3)
		assert.same({ "BOTTOMLEFT", header, "TOPLEFT", 7, 14 }, { label:GetPoint() })
		CG.Config:Set("titles.position", "below")
		assert.same({ "TOPLEFT", header, "BOTTOMLEFT", 7, -20 }, { label:GetPoint() })
		Mock.inCombat = true
		CG.Config:Set("titles.party", "My party")
		CG.Config:Set("titles.size", 18)
		assert.equals("Party", label:GetText())
		assert.equals(11, label.__state.font[2])
		Mock.inCombat = false
		Mock.FireEvent("PLAYER_REGEN_ENABLED")
		assert.equals("My party", label:GetText())
		assert.equals(18, label.__state.font[2])
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

	it("applies binding edits as changed attributes only, without a panel refresh #bindings", function()
		local frame = CG.headers.party:GetAttribute("child1").Member
		local refreshes, writes = 0, {}
		local refresh, set = CG.Refresh, frame.SetAttribute
		CG.Refresh = function(...) refreshes = refreshes + 1; return refresh(...) end
		rawset(frame, "SetAttribute", function(self, key, value)
			writes[#writes + 1] = key
			return set(self, key, value)
		end)
		CG.Config:SetAction(2, "shift", "friendly", { action = "spell", spell = "2061" })
		assert.equals(0, refreshes)
		table.sort(writes)
		assert.same({ "shift-spell-heal2", "shift-type-heal2" }, writes)
		assert.equals("spell", frame:GetAttribute("shift-type-heal2"))
		assert.equals(2061, frame:GetAttribute("shift-spell-heal2"))
		-- Spell and macro updates take the same path; unchanged plans write nothing.
		writes = {}
		Mock.FireEvent("SPELLS_CHANGED")
		Mock.FireEvent("UPDATE_MACROS")
		assert.equals(0, refreshes)
		assert.same({}, writes)
		Mock.spellOverrides[2061] = 2062
		Mock.FireEvent("SPELLS_CHANGED")
		assert.same({ "shift-spell-heal2" }, writes)
		-- A full refresh rewrites nothing either; a reset clears what was set.
		writes = {}
		CG.Config:Set("panel.columns", 3)
		assert.equals(1, refreshes)
		assert.same({}, writes)
		CG.Config:SetAction(2, "shift", "friendly", nil)
		assert.is_nil(frame:GetAttribute("shift-type-heal2"))
		assert.is_nil(frame:GetAttribute("shift-spell-heal2"))
		CG.Refresh = refresh
	end)

	it("defers binding edits in combat to binding application after it, without a restyle #bindings", function()
		local frame = CG.headers.party:GetAttribute("child1").Member
		local refreshes, refresh = 0, CG.Refresh
		CG.Refresh = function(...) refreshes = refreshes + 1; return refresh(...) end
		Mock.inCombat = true
		CG.Config:SetAction(3, "none", "hostile", { action = "spell", spell = "139" })
		Mock.FireEvent("SPELLS_CHANGED")
		assert.is_nil(frame:GetAttribute("spell-harm3"))
		assert.is_true(CG.pendingBindings)
		assert.is_nil(CG.pending)
		Mock.inCombat = false
		Mock.FireEvent("PLAYER_REGEN_ENABLED")
		assert.equals(139, frame:GetAttribute("spell-harm3"))
		assert.is_nil(CG.pendingBindings)
		assert.equals(0, refreshes)
		-- A style change in the same combat still restyles once, bindings included.
		Mock.inCombat = true
		CG.Config:SetAction(3, "none", "hostile", { action = "spell", spell = "2061" })
		CG.Config:Set("panel.columns", 3)
		Mock.inCombat = false
		Mock.FireEvent("PLAYER_REGEN_ENABLED")
		assert.equals(1, refreshes)
		assert.equals(2061, frame:GetAttribute("spell-harm3"))
		assert.is_nil(CG.pending)
		assert.is_nil(CG.pendingBindings)
		CG.Refresh = refresh
	end)

	it("recompiles bindings for talent and specialization changes without restyling #bindings", function()
		local refreshes, refresh = 0, CG.Refresh
		CG.Refresh = function(...) refreshes = refreshes + 1; return refresh(...) end
		local owner, compiled = {}, 0
		UF.Events.RegisterCallback(owner, "ClickGridBindingsCompiled", function() compiled = compiled + 1 end)
		Mock.FireEvent("PLAYER_TALENT_UPDATE")
		Mock.FireEvent("PLAYER_SPECIALIZATION_CHANGED", "player")
		Mock.FireEvent("PLAYER_SPECIALIZATION_CHANGED", "party1")
		assert.equals(0, refreshes)
		assert.equals(2, compiled)
		UF.Events.UnregisterCallback(owner, "ClickGridBindingsCompiled")
		CG.Refresh = refresh
	end)

	it("respects Clique ownership and does not rewrite its attributes", function()
		local frame = CG.headers.party:GetAttribute("child1").Member
		Clique = {}
		frame:SetAttribute("type-heal1", "external")
		CG:RequestRefresh()
		assert.equals("external", frame:GetAttribute("type-heal1"))
		Clique = nil
	end)

	it("keeps shield scale options correct across placement and repeated toggles #shields", function()
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
		local slots = CG:GetGridButton(CG.headers.party:GetAttribute("child1").Member).slots
		local native = slots.container.__state.slots.slot1
		assert.equals("HELPFUL|PLAYER", native.filter)
		assert.same({ [139] = true, [774] = true }, native.candidateFilters.includeSpellIDs)
		CG.Config:Set("slots.slot1.enabled", false)
		assert.same({}, native.candidateFilters.includeSpellIDs)
		assert.is_nil(UF.Schema.Find(CG.SlotSchema, "slot1.debuff"))
	end)
end)
