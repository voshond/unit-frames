local _, ns = ...

-- Minimal single-inheritance class helper. A class is a table used as the
-- metatable of its instances; subclasses look up missing keys in the parent.
local Object = {}
Object.__index = Object
Object.className = "Object"

function Object:Extend(className)
	local class = setmetatable({}, { __index = self })
	class.__index = class
	class.className = className
	class.super = self
	return class
end

function Object:IsA(class)
	local current = getmetatable(self)
	while current do
		if current == class then
			return true
		end
		current = current.super
	end
	return false
end

ns.Object = Object
