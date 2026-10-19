describe("Generated stripes artwork #dots", function()
	local function Read(path)
		local file = assert(io.open(path, "rb"))
		local bytes = file:read("*a")
		file:close()
		return bytes
	end

	it("matches the generator: a seamless 16x16 32-bit top-left TGA of diagonal stripes", function()
		local output = os.tmpname()
		local chunk = assert(loadfile("scripts/generate-stripes.lua"))
		setfenv(chunk, setmetatable({ arg = { output }, print = function() end }, { __index = _G }))
		chunk()
		local generated, committed = Read(output), Read("UnitFrames/Media/Stripes.tga")
		os.remove(output)
		assert.equals(generated, committed, "regenerate with luajit scripts/generate-stripes.lua")
		assert.equals(2, committed:byte(3))
		assert.equals(16, committed:byte(13) + committed:byte(14) * 256)
		assert.equals(16, committed:byte(15) + committed:byte(16) * 256)
		assert.equals(32, committed:byte(17))
		assert.equals(0x28, committed:byte(18))
		local function Alpha(x, y) return committed:byte(18 + (y * 16 + x) * 4 + 4) end
		assert.equals(255, Alpha(0, 0))
		assert.equals(0, Alpha(4, 0))
		assert.equals(Alpha(0, 0), Alpha(1, 15), "the diagonal continues across the tile's edge")
		for y = 0, 15 do
			for x = 0, 15 do assert.equals(Alpha(x, y), Alpha((x + 8) % 16, y), "8 px period") end
		end
	end)
end)
