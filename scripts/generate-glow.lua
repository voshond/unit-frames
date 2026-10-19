local usage = "luajit scripts/generate-glow.lua [output.tga] [corner radius] [inset]"
local output = arg[1] or "UnitFrames/Media/Glow.tga"
if output == "--help" then print(usage); return end

--[[
Without an inset: a halo that stays outside the frame, clear inside it.
With an inset: a halo drawn under the frame's background. It starts at a
rectangle `inset` texels inside the frame's edge, rounded by the corner
radius, at full strength up to the inset's distance (the frame's edge along
its sides) and fades out within INNER texels further in; the frame covers
the part inside it. Rounded corners lie further from that rectangle, so the
glow dims around them. Slice margins reach past that into the frame, so corner
slices meet the uniform, stretched edge slices.
]]
local RADIUS = tonumber(arg[2]) or 0
local INSET = tonumber(arg[3]) or 0
local REACH, INNER = 31, 4
local MASKED = INSET == 0
local MARGIN = REACH + INSET + (MASKED and RADIUS or math.max(RADIUS, INNER))
-- A power of two; the edge slices between the margins are uniform.
local SIZE = 64
while SIZE < 2 * MARGIN + 2 do SIZE = SIZE * 2 end
local PEAK, FALLOFF = 0.8, 3

-- Signed distance to the rounded rectangle the glow starts at.
local function Distance(x, y)
	local low, high = REACH + INSET + RADIUS, SIZE - REACH - INSET - RADIUS
	local qx, qy = math.max(low - x, x - high), math.max(low - y, y - high)
	local outside = math.sqrt(math.max(qx, 0) ^ 2 + math.max(qy, 0) ^ 2)
	return outside + math.min(math.max(qx, qy), 0) - RADIUS
end

-- Brightest where the glow starts, fading out to its reach outside the frame.
local function Alpha(x, y)
	if MASKED and x > REACH and x < SIZE - REACH and y > REACH and y < SIZE - REACH then return 0 end
	local distance = Distance(x, y)
	if distance <= 0 then
		if MASKED or distance <= -INNER then return 0 end
		return math.floor(PEAK * (1 + distance / INNER) * 255 + 0.5)
	end
	local t = math.max(0, distance - INSET) / REACH
	if t >= 1 then return 0 end
	return math.floor(PEAK * (1 - t) ^ FALLOFF * 255 + 0.5)
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
