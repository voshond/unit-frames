local Helpers = require("helpers")

describe("Workbench presentation pages", function()
	it("summarises text slots from effective content and refreshes after writes and resets", function()
		local UF, wb = Helpers.LoadWorkbench()
		wb:Open("unit.player")
		wb:SelectFeaturePage("@health", "style:text.right")
		local function Label()
			for _, choice in ipairs(wb.localSections:GetValues()) do
				if choice[1] == "style:text.right" then return choice[2] end
			end
		end
		local initial = Label()
		assert.is_not_nil(initial:find(" — ", 1, true))
		UF.Config:SetUnitValue("player", "health.right.format", "custom")
		assert.equals("Right Text — Custom", Label())
		UF.Config:SetUnitValue("player", "health.right.format", "none")
		assert.equals("Right Text — None", Label())
		UF.Config:SetUnitValue("player", "health.right.format", nil)
		assert.equals(initial, Label())
	end)

	it("routes member portrait and panel state links to their canonical ClickGrid stores", function()
		local _, _, wb = Helpers.LoadClickGrid(true)
		wb:Open("clickgrid.member")
		wb:SelectSection("@portrait")
		local aura
		for _, link in ipairs(wb.contextDestinations) do
			if link.record.path:match("^categoryAuras%.") then aura = link.record; break end
		end
		assert.is_not_nil(aura)
		assert.equals("clickgrid.panel", aura.entryId)
		assert.equals("member", aura.targetId)
		wb:OpenDestination(aura)
		wb:SelectSection("@states")
		assert.is_true(#wb.contextDestinations > 0)
		assert.equals("clickgrid.member", wb.contextDestinations[1].record.entryId)
		wb.contextLinks:Select(1)
		assert.equals("clickgrid.member", wb.entry.id)
		assert.is_not_nil(wb.inspector.revealedPath:match("%.format$"))
	end)

	it("offers a distinct aura overview linking to canonical sections and retains old aliases", function()
		local _, _, wb = Helpers.LoadClickGrid(true)
		for _, entryId in ipairs({ "unit.player", "clickgrid.panel", "clickgrid.target" }) do
			wb:Open(entryId)
			wb:SelectFeaturePage("@auras", "@overview")
			assert.equals("@overview", wb.activeFeatureSection.id)
			assert.equals(0, #wb.activeFeatureSection.paths)
			assert.is_false(wb.inspector:GetFrame():IsShown())
			assert.is_true(#wb.contextDestinations > 0)
			local destination = wb.contextDestinations[1].record
			wb.contextLinks:Select(1)
			assert.equals(destination.sectionId, wb.activeFeatureSection.id)
			assert.is_true(wb.inspector:GetFrame():IsShown())
		end
		wb:Open("unit.player")
		wb:SelectSection("auras")
		assert.equals("style:auras", wb.activeFeatureSection.id)
		assert.is_true(wb:ValidateCatalogue())
	end)

	it("links independent cast bars, portrait overlays and supported state text without editing settings", function()
		local UF, wb = Helpers.LoadWorkbench()
		wb:Open("unit.player")
		local before = UF.Util.Copy(UF.Config:GetUnitConfig("player"))
		wb:SelectSection("@castbar")
		assert.equals("timers", wb.contextDestinations[1].record.entryId)
		wb.contextLinks:Select(1)
		assert.equals("timers", wb.entry.id)
		assert.equals("castbar.enabled", wb.inspector.revealedPath)
		wb:Select("unit.player")
		wb:SelectSection("@portrait")
		assert.is_true(#wb.contextDestinations > 1)
		local links = wb.contextDestinations
		for _, link in ipairs(links) do
			assert.is_true(wb:OpenDestination(link.record))
			assert.equals("unit.player", wb.entry.id)
		end
		wb:SelectSection("resting")
		assert.is_true(#wb.contextDestinations > 0)
		wb.contextLinks:Select(1)
		assert.is_not_nil(wb.inspector.revealedPath:match("%.format$"))
		assert.same(before, UF.Config:GetUnitConfig("player"))
		wb:Select("unit.target")
		wb:SelectSection("@states")
		assert.is_true(#wb.contextDestinations > 0)
	end)
	it("keeps global pages directly accessible and orders navigation independently of registration", function()
		local _, _, wb = Helpers.LoadClickGrid(true)
		wb:Open("unit.player")
		local headers, globals, inGlobals = {}, {}, false
		for _, item in ipairs(wb.list.items) do
			if item.header then
				headers[#headers + 1] = item.text
				inGlobals = item.text == "Global Settings"
			elseif inGlobals then
				globals[#globals + 1] = item.text
				assert.equals("theme", item.entryId)
				assert.is_nil(item.depth)
			end
		end
		assert.same({ "Unit Frames", "Cast Bar & Swing Timers", "Global Settings", "Party & Raid", "Profiles", "Developer Tools" }, headers)
		assert.same({ "Fonts", "Bars, Borders & Backgrounds", "Colours" }, globals)
		local playerSession = wb.session
		wb.list:Select("theme|@artwork", true)
		assert.equals("theme", wb.entry.id)
		assert.is_true(playerSession.released)
		assert.equals("@artwork", wb.state.section)
		assert.equals("Global Settings > Bars, Borders & Backgrounds", wb.sectionTitle:GetText())
		local themeSession = wb.session
		wb.list:Select("theme|@colours", true)
		assert.equals(themeSession, wb.session)
		assert.equals("@colours", wb.state.section)
		assert.equals("theme|@colours", wb.list.selected)
		wb:Select("unit.target")
		wb.list:Select("theme|@fonts", true)
		assert.equals("@fonts", wb.state.section)
	end)

	it("only offers detailed adjustments on sections with available offset controls", function()
		local _, wb = Helpers.LoadWorkbench()
		wb:Open("unit.player")
		wb:SelectSection("@layout")
		assert.is_false(wb.detailsCheck:GetFrame():IsShown())
		wb:SelectFeaturePage("@health", "style:shields")
		assert.is_false(wb.detailsCheck:GetFrame():IsShown())
		wb:SelectSection("raidTarget")
		local offset
		for _, row in ipairs(wb.inspector.page.rows) do
			if row.path == "raidTarget.offsetX" then offset = row end
		end
		assert.is_not_nil(offset)
		assert.is_true(wb.detailsCheck:GetFrame():IsShown())
		assert.is_false(offset.region:IsShown())
		wb.detailsCheck:GetFrame():RunScript("OnClick")
		assert.is_true(offset.region:IsShown())
		assert.is_true(wb.detailsCheck:GetValue())
		wb:SelectSection("@layout")
		assert.is_false(wb.detailsCheck:GetFrame():IsShown())
		wb:SelectSection("raidTarget")
		assert.is_true(wb.detailsCheck:GetValue())
		assert.is_true(offset.region:IsShown())
		wb.detailsCheck:GetFrame():RunScript("OnClick")
		assert.is_false(offset.region:IsShown())
	end)

	it("updates detail availability when real prerequisites change without revealing hidden controls", function()
		local UF, wb = Helpers.LoadWorkbench()
		wb:Open("unit.player")
		local schema = {
			{ key = "enabled", type = "toggle", default = false },
			{ key = "offsetX", type = "range", min = -10, max = 10, default = 0,
				hidden = function(values) return not values.enabled end },
		}
		local target = UF.Widgets.Inspector.TableTarget(schema, {})
		wb.inspector:SetTarget(target, "conditional-details", { paths = { "enabled", "offsetX" }, details = { offsetX = true } })
		assert.is_false(wb.detailsCheck:GetFrame():IsShown())
		target.set("enabled", true)
		wb.inspector:Refresh()
		assert.is_true(wb.detailsCheck:GetFrame():IsShown())
		wb.detailsCheck:GetFrame():RunScript("OnClick")
		assert.is_true(wb.inspector.page.rows[2].region:IsShown())
		target.set("enabled", false)
		wb.inspector:Refresh()
		assert.is_false(wb.detailsCheck:GetFrame():IsShown())
		assert.is_false(wb.inspector.page.rows[2].region:IsShown())
		target.set("enabled", true)
		wb.inspector:Refresh()
		assert.is_true(wb.detailsCheck:GetFrame():IsShown())
		assert.is_true(wb.detailsCheck:GetValue())
	end)

	it("disconnects cached pages from retired preview targets before another entry is created", function()
		local _, wb = Helpers.LoadWorkbench()
		wb:Open("bar.health")
		wb:SelectSection("row")
		local page, control = wb.inspector.page, wb.inspector.page.rows[1].control
		local callback = control.opts.onChange
		wb:Select("unit.player")
		assert.is_nil(page.target)
		assert.has_no_error(function() callback(false) end)
		wb:Select("bar.health")
		wb:SelectSection("row")
		assert.equals(page, wb.inspector.page)
		control.opts.onChange(false)
		assert.is_false(wb.handle.parts.row:IsEnabled())
	end)

	it("groups existing icon and effect paths without duplicating navigation or changing stores", function()
		local UF, wb = Helpers.LoadWorkbench()
		wb:Open("unit.player")
		local ids = {}
		for _, item in ipairs(wb.sections) do if item.id then ids[item.id] = true end end
		assert.is_true(ids["@states"])
		assert.is_true(ids["@health"])
		assert.is_nil(ids.raidTarget)
		assert.is_nil(ids.range)
		wb:SelectSection("@effects")
		assert.equals("Player > Indicators & States", wb.sectionTitle:GetText())
		local spell
		for _, row in ipairs(wb.inspector.page.rows) do if row.path == "range.spell" then spell = row end end
		assert.is_not_nil(spell)
		assert.is_false(spell.region:IsShown())
		wb.styleTarget.set("range.mode", "spell")
		assert.is_true(spell.region:IsShown())
		spell.control.opts.onChange("133")
		assert.equals("133", UF.Config:GetUnitConfig("player").range.spell)
		assert.is_true(spell.reset:IsShown())
		spell.reset:RunScript("OnClick")
		assert.is_nil(UF.Config:GetUnitConfig("player").range.spell)
		assert.is_false(spell.reset:IsShown())
	end)

	it("retains scroll per cached page and maps remembered schema sections to their new page", function()
		local _, wb = Helpers.LoadWorkbench()
		wb:Open("unit.player")
		wb:SelectSection("@effects")
		local effects = wb.inspector.page
		wb.inspector.scroll:SetScrollPercentage(0.6)
		wb:SelectSection("raidTarget")
		assert.equals(0, wb.inspector.scroll:GetScrollPercentage())
		wb.inspector.scroll:SetScrollPercentage(0.25)
		wb:SelectSection("range")
		assert.equals(effects, wb.inspector.page)
		assert.equals(0.6, wb.inspector.scroll:GetScrollPercentage())
		wb.state.section = "readyCheck"
		wb:Select("unit.player")
		assert.equals("@states", wb.state.section)
		wb:Select("unit.target")
		wb:SelectSection("@effects")
		for _, row in ipairs(wb.inspector.page.rows) do assert.is_false(row.path == "resting") end
	end)

	it("uses original ancestor visibility for mixed root and nested option references", function()
		local UF, wb = Helpers.LoadWorkbench()
		wb:Open("unit.player")
		local schema = {
			{ key = "hide", type = "toggle", default = false },
			{ key = "group", type = "group", hidden = function(root) return root.hide end, schema = {
				{ key = "enabled", type = "toggle", default = true },
				{ key = "value", type = "text", default = "", hidden = function(group) return not group.enabled end },
			} },
		}
		local config = {}
		local target = UF.Widgets.Inspector.TableTarget(schema, config)
		local selection = { paths = { "hide", "group.value" } }
		local inspector = wb.inspector
		inspector:SetTarget(target, "mixed", selection)
		local value = inspector.page.rows[2]
		assert.is_true(value.region:IsShown())
		target.set("group.enabled", false)
		inspector:Refresh()
		assert.is_false(value.region:IsShown())
		target.set("group.enabled", true)
		target.set("hide", true)
		inspector:Refresh()
		assert.is_false(value.region:IsShown(), "hidden ancestor is respected even without its header")
		assert.has_error(function() inspector:SetTarget(target, "invalid", { paths = { "missing" } }) end)
	end)

	it("retargets cached callbacks and releases discarded page controls on schema or page revisions", function()
		local UF, wb = Helpers.LoadWorkbench()
		wb:Open("unit.player")
		local schema = { { key = "value", type = "text", default = "" } }
		local old, current = {}, {}
		local first = UF.Widgets.Inspector.TableTarget(schema, old)
		local second = UF.Widgets.Inspector.TableTarget(schema, current)
		local inspector, selection = wb.inspector, { paths = { "value" } }
		inspector:SetTarget(first, "retarget", selection)
		local page, input = inspector.page, inspector.page.rows[1].control
		inspector:SetTarget(second, "retarget", selection)
		assert.equals(page, inspector.page)
		input.opts.onChange("new")
		assert.equals("new", current.value)
		assert.is_nil(old.value)
		second.revision = 2
		inspector:SetTarget(second, "retarget", selection)
		assert.is_true(input.released)
		assert.is_nil(input.input:GetScript("OnEditFocusLost"))
		assert.is_nil(page.target)
		assert.is_false(page.frame:IsShown())
		local replacement = inspector.page
		selection.revision = 1
		inspector:SetTarget(second, "retarget", selection)
		assert.is_nil(replacement.target)
		assert.is_false(replacement == inspector.page)
	end)
end)
