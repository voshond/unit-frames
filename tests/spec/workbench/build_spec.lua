local Helpers = require("helpers")

describe("Workbench build visibility", function()
	it("keeps the component gallery in development builds and displays the version", function()
		local ns, workbench = Helpers.LoadWorkbench({
			Version = "dev-123456789abc-dirty", ["X-Build-Channel"] = "development",
			["X-Build-Commit"] = "123456789abcdef0123456789abcdef0123456789",
		})
		assert.is_true(ns.isDevelopment)
		assert.equals("123456789abcdef0123456789abcdef0123456789", ns.commit)
		for _, id in ipairs({ "bar.health", "bar.power", "bar.experience", "castbar", "backdrop", "text" }) do
			assert.is_not_nil(workbench.entries[id])
		end
		workbench:Open("bar.health")
		assert.equals("UnitFrames Workbench - dev-123456789abc-dirty", workbench.window.title:GetText())
	end)

	it("omits gallery entries in releases while keeping real settings and previews", function()
		local ns, workbench = Helpers.LoadWorkbench({ Version = "1.2.3-beta.1", ["X-Build-Channel"] = "release" })
		assert.is_false(ns.isDevelopment)
		for _, id in ipairs({ "bar.health", "bar.power", "bar.experience", "castbar", "backdrop", "text" }) do
			assert.is_nil(workbench.entries[id])
		end
		-- A previously selected gallery entry must fall back to the player settings.
		workbench:GetDB().selected = "bar.health"
		workbench:Toggle()
		assert.equals("unit.player", workbench.entry.id)
		assert.equals("UnitFrames Workbench - 1.2.3-beta.1", workbench.window.title:GetText())
		for _, unit in ipairs(ns.Units.order) do
			workbench:Open("unit." .. unit)
			assert.equals("unit." .. unit, workbench.entry.id)
			assert.is_not_nil(workbench.handle)
		end
		for _, id in ipairs({ "theme", "profiles" }) do
			workbench:Open(id)
			assert.equals(id, workbench.entry.id)
		end
	end)
end)
