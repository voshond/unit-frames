local _, ns = ...

--[[
Minimal single-inheritance class helper. A class is a table used as the
metatable of its instances; subclasses look up missing keys in the parent.

Three kinds of building blocks use it, or deliberately don't:
  Component   configurable visuals: schema, config cascade and lifecycle
              (Components/Component.lua)
  Widget      settings controls with plain opts (Widgets/Widget.lua)
  Object      any other stateful helper: Class:New(...) calls Init(...)
Stateless logic (layout calculations, schema builders) stays a plain module
table of functions.
]]
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

function Object:New(...)
	local instance = setmetatable({}, self)
	instance:Init(...)
	return instance
end

function Object:Init() end

ns.Object = Object
