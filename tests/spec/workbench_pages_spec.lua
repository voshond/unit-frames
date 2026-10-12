local Helpers = require("helpers")

describe("Workbench presentation pages", function()
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
		assert.is_true(ids["@icons"])
		assert.is_true(ids["@effects"])
		assert.is_nil(ids.raidTarget)
		assert.is_nil(ids.range)
		wb:SelectSection("@effects")
		assert.equals("State effects", wb.sectionTitle:GetText())
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
		wb:SelectSection("@icons")
		assert.equals(0, wb.inspector.scroll:GetScrollPercentage())
		wb.inspector.scroll:SetScrollPercentage(0.25)
		wb:SelectSection("@effects")
		assert.equals(effects, wb.inspector.page)
		assert.equals(0.6, wb.inspector.scroll:GetScrollPercentage())
		wb.state.section = "readyCheck"
		wb:Select("unit.player")
		assert.equals("@effects", wb.state.section)
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
