local _, ns = ...
local Schema = ns.Schema

--[[
Base class of every unit frame building block.

Lifecycle:
  Class:New(parent, config, spec)  build once via OnCreate(parent, spec), then Apply(config)
  :Apply(config)                   resolve config against schema + theme, then OnApply(resolved).
                                   Must be idempotent: applying twice gives the same result.
  :SetEnabled(enabled)             the on/off toggle
  :Release()                       hide and detach; the instance must not be used afterwards

`config` holds only the user's/preset's values (it is never mutated here);
`self.resolved` is the effective configuration after the cascade.
`spec` is structural and fixed for the instance's lifetime (e.g. which bar
segments exist), unlike config which can change at any time.

Components never do arithmetic or comparisons on unit data: values are
passed straight to widgets, so secret values work (docs/01 §3).
]]
local Component = ns.Object:Extend("Component")
ns.Component = Component

Component.schema = {}

-- Live instances, re-applied when the theme changes.
local live = setmetatable({}, { __mode = "k" })

function Component:Extend(className)
	local class = ns.Object.Extend(self, className)
	ns.Components[className] = class
	return class
end

function Component:New(parent, config, spec)
	local instance = setmetatable({}, self)
	instance.spec = spec or {}
	instance.enabled = true
	instance:OnCreate(parent, instance.spec)
	live[instance] = true
	instance:Apply(config or {})
	return instance
end

function Component:GetSchema()
	return self.schema
end

function Component:Apply(config)
	if config then
		self.config = config
	end
	self.resolved = Schema.Resolve(self:GetSchema(), self.config, ns.Config:GetTheme())
	self:OnApply(self.resolved)
	if self.resolved.enabled ~= nil then
		self:SetEnabled(self.resolved.enabled)
	end
end

-- Applies the `key` group of this component's config to a child component,
-- carrying over the group's default overrides (composite components).
function Component:ApplyChild(child, key)
	local opt = Schema.Find(self:GetSchema(), key)
	local config = ns.Util.Copy(opt and opt.defaults or {})
	ns.Util.Merge(config, (self.config and self.config[key]) or {})
	child:Apply(config)
end

function Component:SetEnabled(enabled)
	self.enabled = enabled and true or false
	self.frame:SetShown(self.enabled)
end

function Component:IsEnabled()
	return self.enabled
end

function Component:GetFrame()
	return self.frame
end

function Component:SetPoint(...)
	self.frame:SetPoint(...)
end

function Component:SetAllPoints(...)
	self.frame:SetAllPoints(...)
end

function Component:ClearAllPoints()
	self.frame:ClearAllPoints()
end

function Component:SetSize(width, height)
	self.frame:SetSize(width, height)
end

function Component:Release()
	live[self] = nil
	self:OnRelease()
	self.frame:Hide()
	self.frame:ClearAllPoints()
end

-- Hooks for subclasses.
function Component:OnCreate(parent, spec) end
function Component:OnApply(resolved) end
function Component:OnRelease() end

local themeWatcher = {}
ns.Events.RegisterCallback(themeWatcher, "ThemeChanged", function()
	for instance in pairs(live) do
		instance:Apply()
	end
end)
