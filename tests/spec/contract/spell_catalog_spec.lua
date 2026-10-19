describe("Generated Forever spell catalogue #dots", function()
	it("matches the pinned build without requiring the raw spell database", function()
		assert.equals(0, os.execute("python3 -B scripts/spell_catalog.py --check-pin"))
	end)

	it("passes effect classification and source provenance regressions", function()
		assert.equals(0, os.execute("python3 -B tests/scripts/spell_catalog_test.py"))
	end)
end)
