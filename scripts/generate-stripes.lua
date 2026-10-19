local usage = "luajit scripts/generate-stripes.lua [output.tga]"
local output = arg[1] or "UnitFrames/Media/Stripes.tga"
if output == "--help" then print(usage); return end

-- A diagonal hatch, repeated over fills: SIZE is a whole number of periods so tiles meet seamlessly.
local SIZE, PERIOD, WIDTH = 16, 8, 3

local function UInt16(value)
	return string.char(value % 256, math.floor(value / 256) % 256)
end

local bytes = {
	string.char(0, 0, 2), string.rep("\0", 5), UInt16(0), UInt16(0), UInt16(SIZE), UInt16(SIZE),
	string.char(32, 0x28),
}
for y = 0, SIZE - 1 do
	for x = 0, SIZE - 1 do
		bytes[#bytes + 1] = string.char(255, 255, 255, (x + y) % PERIOD < WIDTH and 255 or 0)
	end
end
local file = assert(io.open(output, "wb"))
file:write(table.concat(bytes))
file:close()
print(string.format("%s: %dx%d, stripes every %d px", output, SIZE, SIZE, PERIOD))
