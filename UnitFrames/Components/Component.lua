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
local pending = {}
local regen = CreateFrame("Frame")
regen:SetScript("OnEvent", function(self)
	self:UnregisterEvent("PLAYER_REGEN_ENABLED")
	for instance in pairs(pending) do
		pending[instance] = nil
		instance:Apply()
	end
end)

function Component:Extend(className)
	local class = ns.Object.Extend(self, className)
	ns.Components[className] = class
	return class
end

function Component:New(parent, config, spec)
	local instance = setmetatable({}, self)
	instance.spec = spec or {}
	instance.children = {}
	instance.enabled = true
	instance:OnCreate(parent, instance.spec)
	live[instance] = true
	instance:Apply(config or {})
	return instance
end

function Component:GetSchema()
	if not self.schemaCache then
		self.schemaCache = self.BuildSchema and self.BuildSchema(self.spec) or ns.Util.Copy(self.schema)
	end
	return self.schemaCache
end

function Component:Apply(config)
	assert(not self.released, "Cannot apply a released component")
	if config then
		self.config = config
	end
	-- Group styles opt their entire composition into deferred presentation.
	if self.deferInCombat and InCombatLockdown() then
		pending[self] = true
		regen:RegisterEvent("PLAYER_REGEN_ENABLED")
		return
	end
	pending[self] = nil
	self.resolved = Schema.Resolve(self:GetSchema(), self.config, ns.Config:GetTheme())
	self:OnApply(self.resolved)
	if self.resolved.enabled ~= nil then
		self:SetEnabled(self.resolved.enabled)
	end
end

function Component:SetCombatDeferred(deferred)
	self.deferInCombat = deferred and true or false
	for _, child in ipairs(self.children) do
		child:SetCombatDeferred(deferred)
	end
end

-- Component ownership is independent of native frame parenting. Collections
-- and shared-root compositions participate in the same lifecycle.
function Component:Own(child)
	assert(not child.componentOwner and not child.released, "Component already owned or released")
	child.componentOwner = self
	self.children[#self.children + 1] = child
	child:SetCombatDeferred(self.deferInCombat)
	return child
end

-- Runtime owners also rebind oUF/data on theme changes, so they perform the
-- entire refresh through their own theme callback.
function Component:SetThemeManaged(managed)
	self.themeManaged = managed and true or false
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
	if self.released then return end
	self.released = true
	live[self] = nil
	pending[self] = nil
	self:OnRelease()
	for i = #self.children, 1, -1 do self.children[i]:Release() end
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
		if not instance.componentOwner and not instance.themeManaged then instance:Apply() end
	end
end)
