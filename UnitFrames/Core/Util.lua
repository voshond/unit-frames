local _, ns = ...

local Util = {}
ns.Util = Util

function Util.Copy(value)
	if type(value) ~= "table" then
		return value
	end
	local out = {}
	for k, v in pairs(value) do
		out[k] = Util.Copy(v)
	end
	return out
end

function Util.Equals(a, b)
	if type(a) ~= "table" or type(b) ~= "table" then
		return a == b
	end
	for k, v in pairs(a) do
		if not Util.Equals(v, b[k]) then
			return false
		end
	end
	for k in pairs(b) do
		if a[k] == nil then
			return false
		end
	end
	return true
end

-- Deep-merges `source` into `target` (source wins). Returns target.
function Util.Merge(target, source)
	for k, v in pairs(source) do
		if type(v) == "table" and type(target[k]) == "table" then
			Util.Merge(target[k], v)
		else
			target[k] = Util.Copy(v)
		end
	end
	return target
end

-- Paths are dot separated: "background.color".
function Util.GetPath(tbl, path)
	local node = tbl
	for key in string.gmatch(path, "[^%.]+") do
		if type(node) ~= "table" then
			return nil
		end
		node = node[key]
	end
	return node
end

function Util.SetPath(tbl, path, value)
	local node = tbl
	local keys = {}
	for key in string.gmatch(path, "[^%.]+") do
		keys[#keys + 1] = key
	end
	for i = 1, #keys - 1 do
		local key = keys[i]
		if type(node[key]) ~= "table" then
			node[key] = {}
		end
		node = node[key]
	end
	node[keys[#keys]] = value
end

-- Removes a path and prunes tables left empty by it.
function Util.ClearPath(tbl, path)
	local keys = {}
	for key in string.gmatch(path, "[^%.]+") do
		keys[#keys + 1] = key
	end
	local nodes = { tbl }
	for i = 1, #keys - 1 do
		local nextNode = nodes[i][keys[i]]
		if type(nextNode) ~= "table" then
			return
		end
		nodes[i + 1] = nextNode
	end
	nodes[#keys][keys[#keys]] = nil
	for i = #keys - 1, 1, -1 do
		if next(nodes[i + 1]) == nil then
			nodes[i][keys[i]] = nil
		else
			break
		end
	end
end

function Util.IsSecret(value)
	return issecretvalue ~= nil and issecretvalue(value) or false
end

-- Colours are stored as arrays { r, g, b, a }.
function Util.UnpackColor(color, alphaOverride)
	return color[1], color[2], color[3], alphaOverride or color[4] or 1
end

function Util.Clamp(value, min, max)
	if value < min then
		return min
	elseif value > max then
		return max
	end
	return value
end
