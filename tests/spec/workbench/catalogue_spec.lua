local Helpers = require("helpers")
local Mock = Helpers.Mock

describe("Workbench settings catalogue", function()
	it("indexes unvisited production entries without frames, previews or dynamic dropdown evaluation", function()
		local UF, wb = Helpers.LoadWorkbench()
		local count = #Mock.objects
		local create = CreateFrame
		CreateFrame = function() error("index created a frame") end
		local index = wb:GetCatalogue()
		local results = wb:FindSettings("player shield placement")
		CreateFrame = create
		assert.equals(count, #Mock.objects)
		assert.is_nil(wb.session)
		assert.is_nil(wb.window)
		assert.equals("health.bar.segments.absorb.placement", results[1].record.path)
		assert.equals("unit.player", results[1].record.entryId)
		assert.is_true(wb:ValidateCatalogue())
		assert.is_not_nil(index.models["unit.focustarget"])
		local schema = { { key = "choice", label = "Choice", type = "select", values = function() error("dynamic choices evaluated") end } }
		wb:Register({ id = "test.static", name = "Static index", category = "Test", settingsTargets = function()
			return { { id = "style", schema = schema } }
		end })
		assert.equals(1, #wb:FindSettings("choice", { entryId = "test.static" }))
		assert.is_not_nil(UF.Units:GetSchema("target"))
	end)

	it("covers every real store exactly once with ClickGrid and rejects orphaned destinations", function()
		local _, _, wb = Helpers.LoadClickGrid(true)
		assert.is_true(wb:ValidateCatalogue())
		local model = wb:GetCatalogue().models["unit.player"]
		local record = table.remove(model.records)
		assert.has_error(function() wb:ValidateCatalogue() end)
		model.records[#model.records + 1] = record
		assert.is_true(wb:ValidateCatalogue())
		model.records[#model.records + 1] = record
		assert.has_error(function() wb:ValidateCatalogue() end)
	end)

	it("normalises queries, ranks content selectors and editor phrases, and keeps distinct targets", function()
		local _, _, wb = Helpers.LoadClickGrid(true)
		local first = wb:FindSettings(" TARGET   health-percent ")[1].record
		assert.equals("unit.target", first.entryId)
		assert.is_not_nil(first.path:match("^health%..-%.format$"))
		assert.equals("clickgrid.bindings", wb:FindSettings("left click heal")[1].record.entryId)
		assert.equals("profiles", wb:FindSettings("import profile")[1].record.entryId)
		local results = wb:FindSettings("shield placement")
		local seen = {}
		for _, result in ipairs(results) do seen[result.record.entryId] = true end
		assert.is_true(seen["unit.player"])
		assert.is_true(seen["unit.target"])
		local repeated = wb:FindSettings("shield placement")
		for index, result in ipairs(results) do assert.equals(result.record, repeated[index].record) end
		assert.equals(0, #wb:FindSettings("abracadabra"))
		assert.equals(0, #wb:FindSettings(""))
	end)

	it("separates preview and developer results and honours explicit scope", function()
		local _, wb = Helpers.LoadWorkbench()
		for _, result in ipairs(wb:FindSettings("health")) do assert.equals("settings", result.record.group) end
		local preview = false
		for _, result in ipairs(wb:FindSettings("health", { preview = true })) do
			if result.record.group == "preview" then preview = true end
			assert.is_false(result.record.group == "developer")
		end
		assert.is_true(preview)
		local developer = false
		for _, result in ipairs(wb:FindSettings("castbar", { developer = true })) do
			if result.record.group == "developer" then developer = true end
		end
		assert.is_true(developer)
		assert.equals(0, #wb:FindSettings("resting", { entryId = "unit.target" }))
		assert.is_true(#wb:FindSettings("resting") > 0)
		for _, result in ipairs(wb:FindSettings("health", { entryId = "unit.player", pageId = "@health" })) do
			assert.equals("unit.player", result.record.entryId)
			assert.equals("@health", result.record.pageId)
		end
	end)
end)
