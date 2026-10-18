local usage = "luajit scripts/generate-glow.lua [output.tga]"
local output = arg[1] or "UnitFrames/Media/Glow.tga"
if output == "--help" then print(usage); return end

local SIZE, MARGIN = 64, 31

local function Falloff(distance)
	if distance <= 0 or distance >= MARGIN then return 0 end
	local t = distance / MARGIN
	return math.sin(math.pi * t) ^ 2
end

local function Alpha(x, y)
	local cx = math.max(0, MARGIN - x, x - (SIZE - MARGIN))
	local cy = math.max(0, MARGIN - y, y - (SIZE - MARGIN))
	local outside = math.sqrt(cx * cx + cy * cy)
	return math.floor(Falloff(MARGIN - outside) * 255 + 0.5)
end

local function UInt16(value)
	return string.char(value % 256, math.floor(value / 256) % 256)
end

local bytes = {
	string.char(0, 0, 2), string.rep("\0", 5), UInt16(0), UInt16(0), UInt16(SIZE), UInt16(SIZE),
	string.char(32, 0x28),
}
for y = 0, SIZE - 1 do
	for x = 0, SIZE - 1 do
		bytes[#bytes + 1] = string.char(255, 255, 255, Alpha(x + 0.5, y + 0.5))
	end
end
local file = assert(io.open(output, "wb"))
file:write(table.concat(bytes))
file:close()
print(string.format("%s: %dx%d, slice margins %d", output, SIZE, SIZE, MARGIN))
