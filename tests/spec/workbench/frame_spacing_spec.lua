local Helpers = require("helpers")

describe("Shared frame and panel spacing previews", function()
	it("defaults frame and panel content padding to three in live and preview sources", function()
		local UF, CG, wb = Helpers.LoadClickGrid(true)
		local B = UF.Components.Backdrop
		local defaults = UF.Schema.Resolve(B.schema, {}, UF.Config:GetTheme())
		assert.same({ 3, 3, 3, 3 }, { B.Padding(defaults) })
		defaults.separatePadding = true
		assert.same({ 3, 3, 3, 3 }, { B.Padding(defaults) })
		wb:Open("unit.player")
		assert.equals(3, UF.Units.frames.player.uf.resolved.border.padding)
		assert.equals(3, wb.handle.parts.uf.resolved.border.padding)
		wb:Open("clickgrid.panel")
		assert.equals(3, CG.Config:Resolved().border.padding)
		assert.equals(3, CG.layout.sections.party.x)
		assert.equals(3, wb.handle.layout.sections.party.x)
		assert.equals(3, wb.handle.cells[1].member.resolved.border.padding)
	end)

	it("edits per-side background insets in frame and panel inspectors without moving content", function()
		local UF, CG, wb = Helpers.LoadClickGrid(true)
		for _, entry in ipairs({ "unit.player", "clickgrid.member", "clickgrid.panel" }) do
			wb:Open(entry)
			wb:SelectSection("border")
			wb.styleTarget.set("border.inset", 6)
			local before = UF.Util.Copy(CG.layout)
			local rows = {}
			for _, row in ipairs(wb.inspector.page.rows) do rows[row.path] = row end
			assert.is_true(rows["border.separateInset"].region:IsShown())
			assert.is_false(rows["border.insetLeft"].region:IsShown())
			rows["border.separateInset"].control.opts.onChange(true)
			assert.is_false(rows["border.inset"].region:IsShown())
			for i, side in ipairs({ "Left", "Right", "Top", "Bottom" }) do
				local row = rows["border.inset" .. side]
				assert.is_true(row.region:IsShown())
				assert.equals(6, row.control:GetValue())
				row.control.opts.onChange(i)
			end
			local live, preview
			if entry == "unit.player" then
				live, preview = UF.Units.frames.player.uf.border, wb.handle.parts.uf.border
			elseif entry == "clickgrid.member" then
				live, preview = CG.headers.party:GetAttribute("child1").Member.uf.border, wb.handle.cells[1].member.border
			else live, preview = CG.background, wb.handle.background end
			assert.same({ left = 1, right = 2, top = 3, bottom = 4 }, live:GetBackdrop().insets)
			assert.same(live:GetBackdrop().insets, preview:GetBackdrop().insets)
			assert.same(before, CG.layout, "background insets do not change content layout")
			rows["border.separateInset"].control.opts.onChange(false)
			assert.same({ left = 6, right = 6, top = 6, bottom = 6 }, live:GetBackdrop().insets)
			rows["border.separateInset"].control.opts.onChange(true)
			assert.same({ left = 1, right = 2, top = 3, bottom = 4 }, live:GetBackdrop().insets)
		end
	end)

	it("caches all four insets without changing previous artwork or aura controls", function()
		local UF = Helpers.LoadAddon(true)
		local B = UF.Components.Backdrop
		local cfg = UF.Schema.Resolve(B.schema, { separateInset = true, insetLeft = 1, insetRight = 2,
			insetTop = 3, insetBottom = 4 }, UF.Config:GetTheme())
		local original = B.Info(cfg)
		assert.equals(original, B.Info(UF.Util.Copy(cfg)))
		for _, side in ipairs({ "Left", "Right", "Top", "Bottom" }) do
			local changed = UF.Util.Copy(cfg)
			changed["inset" .. side] = 9
			assert.is_true(original ~= B.Info(changed))
		end
		assert.same({ left = 1, right = 2, top = 3, bottom = 4 }, original.insets)
		assert.is_nil(UF.Schema.Find(UF.AuraIcon.schema, "border.separateInset"))
		assert.is_nil(UF.Schema.Find(UF.Components.AuraBar.schema, "rowBackdrop.separateInset"))
	end)

	it("shows the per-side padding switch at the top of frame and panel inspector sections", function()
		local UF, CG, wb = Helpers.LoadClickGrid(true)
		for _, entry in ipairs({ "unit.player", "clickgrid.member", "clickgrid.panel" }) do
			wb:Open(entry)
			wb:SelectSection("border")
			local rows = wb.inspector.page.rows
			local controls = {}
			for _, row in ipairs(rows) do if row.control then controls[#controls + 1] = row end end
			assert.equals("border.separatePadding", controls[2].path)
			assert.is_true(controls[2].region:IsShown())
			assert.equals("Content padding per side", rows[2].opt.label)
			local byPath = {}
			for _, row in ipairs(rows) do byPath[row.path] = row end
			assert.is_false(byPath["border.paddingLeft"].region:IsShown())
			rows[2].control.opts.onChange(true)
			assert.is_false(byPath["border.padding"].region:IsShown())
			for _, side in ipairs({ "Left", "Right", "Top", "Bottom" }) do
				local row = byPath["border.padding" .. side]
				assert.is_true(row.region:IsShown())
				row.control.opts.onChange(11)
				assert.equals(11, row.control:GetValue())
			end
		end
		assert.equals(11, UF.Config:GetUnitConfig("player").border.paddingLeft)
		assert.equals(11, CG.Config:GetStyle("member").border.paddingLeft)
		assert.equals(11, CG.Config:Resolved().border.paddingLeft)
	end)

	it("keeps every live and preview decoration host above member and panel borders", function()
		local UF, CG, wb = Helpers.LoadClickGrid(true)
		wb:Open("clickgrid.panel")
		local live = CG.headers.party:GetAttribute("child1").Member.uf
		local preview = wb.handle.cells[1].member
		for _, kind in ipairs({ "Blizzard Tooltip", "Blizzard Raid" }) do
			CG.Config:Set("border.border", kind)
			CG.Config:SetStyle("member", "border.border", kind)
			for _, pair in ipairs({ { live, CG.background }, { preview, wb.handle.background } }) do
				local uf, panel = pair[1], pair[2]
				local B = UF.Components.Backdrop
				local frameLevel = B.BorderTextures(uf.border)[1]:GetParent():GetFrameLevel()
				local panelLevel = B.BorderTextures(panel)[1]:GetParent():GetFrameLevel()
				for _, member in pairs(uf:GetDecorations().members) do
					if member.host:IsShown() then
						assert.is_true(member.host:GetFrameLevel() > frameLevel)
						assert.is_true(member.host:GetFrameLevel() > panelLevel)
					end
				end
			end
		end
	end)

	it("preserves uniform padding when enabling per-side controls and updates player geometry", function()
		local UF, wb = Helpers.LoadWorkbench()
		wb:Open("unit.player")
		UF.Config:SetUnitValue("player", "portrait.enabled", false)
		UF.Config:SetUnitValue("player", "border.padding", 7)
		UF.Config:SetUnitValue("player", "border.separatePadding", true)
		local live, preview = UF.Units.frames.player.uf, wb.handle.parts.uf
		assert.same({ 7, 7, 7, 7 }, { UF.Components.Backdrop.Padding(live.resolved.border) })
		local oldHeight = live.layout.height
		for side, value in pairs({ Left = 2, Right = 9, Top = 3, Bottom = 12 }) do
			UF.Config:SetUnitValue("player", "border.padding" .. side, value)
		end
		assert.equals(oldHeight + 1, live.layout.height)
		assert.equals(2, live.layout.rows[1].left)
		assert.equals(9, live.layout.rows[1].right)
		assert.equals(-3, live.layout.rows[1].y)
		assert.same(live.layout, preview.layout)
		UF.Config:SetUnitValue("player", "border.separatePadding", false)
		assert.equals(oldHeight, live.layout.height)
		assert.equals(7, live.layout.rows[1].left)
		UF.Config:SetUnitValue("player", "border.separatePadding", true)
		assert.equals(2, live.layout.rows[1].left, "previous side values survive toggling")
	end)

	it("uses the same side padding for bars, portraits and castbar geometry", function()
		local UF = Helpers.LoadAddon(true)
		local border = { enabled = true, separatePadding = true,
			paddingLeft = 2, paddingRight = 9, paddingTop = 3, paddingBottom = 12 }
		local bar = UF.Components.Bar:New(UIParent, { border = border }, { nativeLayout = true })
		bar:SetKnownSize(100, 40)
		assert.same({ 89, 25 }, { bar:GetKnownInnerSize() })
		assert.same({ "TOPLEFT", bar.frame, "TOPLEFT", 2, -3 }, { bar.bar:GetPoint(1) })
		assert.same({ "BOTTOMRIGHT", bar.frame, "BOTTOMRIGHT", -9, 12 }, { bar.bar:GetPoint(2) })
		local portrait = UF.Components.Portrait:New(UIParent, { mode = "2D", border = border })
		portrait:SetSize(100, 40)
		assert.same({ "TOPLEFT", portrait.frame, "TOPLEFT", 2, -3 }, { portrait.viewport:GetPoint(1) })
		assert.same({ "BOTTOMRIGHT", portrait.frame, "BOTTOMRIGHT", -9, 12 }, { portrait.viewport:GetPoint(2) })
		local cfg = UF.Schema.Resolve(UF.Components.Castbar.BuildSchema(), { border = border, icon = { enabled = false } }, UF.Config:GetTheme())
		local cast = UF.CastbarLayout.Compute(100, 40, cfg)
		assert.same({ { "TOPLEFT", "frame", "TOPLEFT", 2, -3 },
			{ "BOTTOMRIGHT", "frame", "BOTTOMRIGHT", -9, 12 } }, cast.bar)
	end)

	it("uses asymmetric panel padding for bounds, member placement and titles in both sources", function()
		local _, CG, wb = Helpers.LoadClickGrid(true)
		wb:Open("clickgrid.panel")
		CG.Config:Set("border.separatePadding", true)
		assert.equals(3, CG.Config:Resolved().border.paddingLeft)
		for side, value in pairs({ Left = 3, Right = 17, Top = 5, Bottom = 21 }) do
			CG.Config:Set("border.padding" .. side, value)
		end
		local preview, cfg = wb.handle, CG.Config:Resolved()
		assert.equals(3, preview.layout.sections.party.x)
		assert.equals(5 + CG.Layout.TitleHeight(cfg.titles), preview.layout.sections.party.y)
		assert.equals(CG.metrics.member.width + 20, preview.layout.party.width)
		assert.same(CG.layout.party, preview.layout.party)
		assert.equals(5, preview.layout.titlePadding)
		CG.Config:Set("titles.position", "below")
		assert.equals(21, preview.layout.titlePadding)
		assert.equals(5, preview.layout.sections.party.y)
		assert.same(CG.layout.party, preview.layout.party)
		CG.Config:Set("border.inset", 9)
		assert.equals(9, CG.background:GetBackdrop().insets.left)
		assert.equals(3, preview.layout.sections.party.x, "background inset does not move members")
	end)

	it("keeps frame and panel edges above their contents without raising backgrounds", function()
		local UF, CG, wb = Helpers.LoadClickGrid(true)
		wb:Open("clickgrid.panel")
		local B = UF.Components.Backdrop
		for _, kind in ipairs({ "Blizzard Tooltip", "Blizzard Raid", "Blizzard Tooltip" }) do
			CG.Config:Set("border.border", kind)
			CG.Config:SetStyle("member", "border.border", kind)
			local preview = wb.handle
			local member = preview.cells[1].member
			local outer = B.BorderTextures(preview.background)[1]:GetParent()
			local inner = B.BorderTextures(member.border)[1]:GetParent()
			assert.is_true(outer:GetFrameLevel() > inner:GetFrameLevel())
			assert.is_true(inner:GetFrameLevel() > member:GetRow("health"):GetBar():GetTextParent():GetFrameLevel())
			assert.is_true(preview.background:GetFrameLevel() < inner:GetFrameLevel())
			assert.equals(preview.frame:GetFrameLevel() + 100, outer:GetFrameLevel())
		end
	end)

	it("migrates saved panel padding without modifying its source or discarding a new override", function()
		local UF, CG = Helpers.LoadClickGrid()
		local old = { panel = { padding = 23 } }
		local migrated = CG.Config:MigrateSettings(old)
		assert.same({ panel = { padding = 23 } }, old)
		assert.equals(23, migrated.border.padding)
		assert.is_nil(migrated.panel.padding)
		assert.equals(6, CG.Config:MigrateSettings({ panel = { padding = 23 }, border = { padding = 6 } }).border.padding)
		CG.Config.db.profile.settings = old -- simulate a saved profile from the old schema
		CG:RequestRefresh()
		assert.equals(23, CG.Config:Resolved().border.padding)
		assert.equals(CG.metrics.member.width + 46, CG.layout.party.width)
		local text = UF.Profiles:Export("style")
		UF.Profiles:Reset()
		assert.is_true(UF.Profiles:Import(text))
		assert.equals(23, CG.Config:Resolved().border.padding)
		assert.is_nil(UF.Util.GetPath(CG.Config:Get(), "panel.padding"))
	end)

	it("keeps aura padding controls and texture layering as before", function()
		local UF = Helpers.LoadAddon(true, true)
		assert.is_nil(UF.Schema.Find(UF.AuraIcon.schema, "border.separatePadding"))
		assert.equals(16, UF.Schema.Find(UF.AuraIcon.schema, "border.padding").max)
		assert.is_nil(UF.Schema.Find(UF.Components.AuraBar.schema, "rowBackdrop.separatePadding"))
		local auras = UF.Units.frames.player.uf:GetPart("auras")
		local button = auras:GetContainer("debuffs"):GetAuraGroupFrame("debuffs", 1)
		assert.equals(button.ufBorder, button.ufDispelTextures[1]:GetParent())
	end)
end)
