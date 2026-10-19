local _, ns = ...

--[[
Reads damage over time from enUS spell descriptions (ported from DoesItDie,
MIT, Licenses/DoesItDie-MIT.txt). Spell tables are keyed by name: Forever's
spellbook data has no stable spell IDs per rank.
]]
local DotParser = {}
ns.DotParser = DotParser

DotParser.DEFAULT_TICK_INTERVAL = 3

DotParser.SCHOOLS = {
	Physical = 1, Holy = 2, Fire = 4, Nature = 8, Frost = 16, Shadow = 32, Arcane = 64,
	Frostfire = 4 + 16,
}

DotParser.TICK_INTERVALS = {
	["Insect Swarm"] = 2,
	["Curse of Agony"] = 2,
	["Bane of Agony"] = 2,
	["Fireball"] = 2,
	["Holy Fire"] = 2,
	["Rip"] = 2,
	["Rupture"] = 2,
}

local AGONY_SHAPE = { 0.5, 0.5, 0.5, 0.5, 1, 1, 1, 1, 1.5, 1.5, 1.5, 1.5 }
DotParser.TICK_SHAPES = {
	["Bane of Agony"] = AGONY_SHAPE,
	["Curse of Agony"] = AGONY_SHAPE,
}

DotParser.SCHOOL_BY_NAME = {
	["Siphon Life"] = 32,
}

-- Projectiles start ticking when they land, up to this long after the cast.
DotParser.PROJECTILE_TRAVEL = 1.5
DotParser.PROJECTILES = {
	["Serpent Sting"] = true, ["Fireball"] = true, ["Pyroblast"] = true, ["Frostfire Bolt"] = true,
}

-- Read like DoTs on the target but are not: areas, channels, traps, delayed damage.
DotParser.IGNORED = {
	["Rain of Fire"] = true, ["Hellfire"] = true, ["Blizzard"] = true, ["Flamestrike"] = true,
	["Consecration"] = true, ["Hurricane"] = true, ["Volley"] = true,
	["Drain Life"] = true, ["Drain Soul"] = true, ["Drain Mana"] = true, ["Health Funnel"] = true,
	["Mind Flay"] = true, ["Arcane Missiles"] = true, ["Starshards"] = true,
	["Immolation Trap"] = true, ["Explosive Trap"] = true, ["Wyvern Sting"] = true,
}

local function SchoolFromWords(words)
	local school = DotParser.SCHOOLS.Physical
	for word in words:gmatch("%a+") do
		if DotParser.SCHOOLS[word] then school = DotParser.SCHOOLS[word] end
	end
	return school
end

function DotParser.IsFinisher(desc)
	return type(desc) == "string" and not issecretvalue(desc) and desc:find("Finishing move") ~= nil
end

function DotParser.AwardedComboPoints(desc)
	if type(desc) ~= "string" or issecretvalue(desc) then return nil end
	return tonumber(desc:match("Awards (%d+) combo point"))
end

-- "1 point : 243 damage over 12 sec. 2 points: 396 damage over 12 sec." (Rip)
-- "1 point: 25 damage over 8 secs\n ... 5 points: 87 damage over 16 secs" (Rupture)
local function ParseFinisher(desc, comboPoints)
	local byPoints, highest = {}, 0
	for points, amount, secs in desc:gmatch("(%d+) points?%s*:%s*(%d+) damage over (%d+%.?%d*) sec") do
		points = tonumber(points)
		byPoints[points] = { total = tonumber(amount), duration = tonumber(secs) }
		highest = math.max(highest, points)
	end
	if highest == 0 then return nil end
	local entry = byPoints[math.max(1, math.min(comboPoints, highest))] or byPoints[highest]
	return entry.total, DotParser.SCHOOLS.Physical, entry.duration
end

-- total, school mask, duration and, when the description states it, the tick
-- interval. The last "N <school> damage over T sec" clause wins, so a direct
-- hit followed by a periodic part yields the periodic part.
function DotParser.Parse(desc, comboPoints)
	if type(desc) ~= "string" or issecretvalue(desc) then return nil end
	if desc:find("Finishing move") then return ParseFinisher(desc, comboPoints or 5) end
	if desc:find("[Cc]oats a weapon") then return nil end
	if desc:find("^Heals") then return nil end

	local total, school, duration
	for amount, words, secs in desc:gmatch("(%d+)%s*([%a ]-)%s*damage over (%d+%.?%d*) sec") do
		total, school, duration = tonumber(amount), SchoolFromWords(words), tonumber(secs)
	end
	if total and duration > 0 then return total, school, duration end

	local amount, words, every = desc:match("(%d+)%s*([%a ]-)%s*damage every (%d+%.?%d*) sec")
	if not amount then
		amount, every = desc:match("(%d+) health.-every (%d+%.?%d*) sec")
		words = ""
	end
	local lasts = desc:match("[Ll]asts (%d+%.?%d*) sec")
	if amount and every and lasts then
		every, lasts = tonumber(every), tonumber(lasts)
		if every > 0 and lasts > 0 then
			return tonumber(amount) * math.floor(lasts / every + 0.5), SchoolFromWords(words), lasts, every
		end
	end
end

-- Everything the tracker needs for a cast of `name`, or nil when it is not a
-- tracked DoT.
function DotParser.Describe(name, desc, comboPoints)
	if DotParser.IGNORED[name] then return nil end
	local total, school, duration, statedInterval = DotParser.Parse(desc, comboPoints)
	if not total then return nil end
	local interval = statedInterval or DotParser.TICK_INTERVALS[name] or DotParser.DEFAULT_TICK_INTERVAL
	return {
		total = total,
		school = DotParser.SCHOOL_BY_NAME[name] or school,
		duration = duration,
		interval = interval,
		totalTicks = math.max(1, math.floor(duration / interval + 0.5)),
		shape = DotParser.TICK_SHAPES[name],
		travel = DotParser.PROJECTILES[name] and DotParser.PROJECTILE_TRAVEL or nil,
	}
end
