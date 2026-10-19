describe("Generated glow artwork #glow", function()
	local function Read(path)
		local file = assert(io.open(path, "rb"))
		local bytes = file:read("*a")
		file:close()
		return bytes
	end

	it("matches the generator: a 64x64 32-bit top-left TGA, clear inside and brightest at the inner edge", function()
		local output = os.tmpname()
		local chunk = assert(loadfile("scripts/generate-glow.lua"))
		setfenv(chunk, setmetatable({ arg = { output }, print = function() end }, { __index = _G }))
		chunk()
		local generated, committed = Read(output), Read("UnitFrames/Media/Glow.tga")
		os.remove(output)
		assert.equals(generated, committed, "regenerate with luajit scripts/generate-glow.lua")
		assert.equals(2, committed:byte(3))
		assert.equals(64, committed:byte(13) + committed:byte(14) * 256)
		assert.equals(64, committed:byte(15) + committed:byte(16) * 256)
		assert.equals(32, committed:byte(17))
		assert.equals(0x28, committed:byte(18))
		local function Alpha(x, y) return committed:byte(18 + (y * 64 + x) * 4 + 4) end
		assert.equals(0, Alpha(32, 32))
		assert.equals(0, Alpha(0, 0))
		assert.is_true(Alpha(30, 32) > 150)
		assert.is_true(Alpha(30, 32) > Alpha(20, 32) and Alpha(20, 32) > Alpha(10, 32))
		assert.is_true(Alpha(1, 32) < 5)
	end)

	it("matches the generator for glows under a frame: lit under its edge, clear further in, dimmer at rounded corners", function()
		for file, radius in pairs({ GlowFrame = 0, GlowFrameSoft = 12, GlowFrameRound = 24 }) do
			local output = os.tmpname()
			local chunk = assert(loadfile("scripts/generate-glow.lua"))
			setfenv(chunk, setmetatable({ arg = { output, tostring(radius), "8" }, print = function() end }, { __index = _G }))
			chunk()
			local generated, committed = Read(output), Read("UnitFrames/Media/" .. file .. ".tga")
			os.remove(output)
			assert.equals(generated, committed, "regenerate with luajit scripts/generate-glow.lua UnitFrames/Media/"
				.. file .. ".tga " .. radius .. " 8")
			local size = committed:byte(13) + committed:byte(14) * 256
			assert.equals(128, size, file)
			local function Alpha(x, y) return committed:byte(18 + (y * size + x) * 4 + 4) end
			local mid = size / 2
			-- The frame's edge is texel 31: full strength there, running on
			-- under it to the inset and gone a little further in.
			assert.is_true(Alpha(30, mid) > 180, file)
			assert.is_true(Alpha(34, mid) >= Alpha(30, mid), file)
			assert.equals(0, Alpha(44, mid), file)
			assert.equals(0, Alpha(mid, mid), file)
			assert.is_true(Alpha(30, mid) > Alpha(20, mid) and Alpha(20, mid) > Alpha(10, mid), file)
			assert.is_true(Alpha(1, mid) < 5, file)
			if radius > 0 then assert.is_true(Alpha(30, 30) < Alpha(30, mid), file) end
		end
	end)
end)
