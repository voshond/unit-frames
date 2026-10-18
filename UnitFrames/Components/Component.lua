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
local schemas = setmetatable({}, { __mode = "k" })

function Component:Extend(className)
	local class = ns.Object.Extend(self, className)
	ns.Components[className] = class
	return class
end

function Component:New(parent, config, spec)
	local instance = setmetatable({}, self)
	instance.spec = spec or {}
	instance.config = config or {}
	instance.children = {}
	instance.enabled = true
	local Perf = ns.Perf
	Perf:Count("componentCreate")
	Perf:Begin("create")
	instance:OnCreate(parent, instance.spec)
	Perf:End("create")
	live[instance] = true
	instance:Apply()
	return instance
end

function Component:GetSchema()
	if not self.schemaCache then
		-- Definitions explicitly own immutable structural metadata. Arbitrary
		-- caller specs retain private schemas; mutable resolved/config never share.
		local owner, class = self.spec.schemaOwner, getmetatable(self)
		if not self.BuildSchema then
			self.schemaCache = self.schema
		elseif owner then
			local cache = schemas[class]
			if not cache then cache = setmetatable({}, { __mode = "k" }); schemas[class] = cache end
			if not cache[owner] then cache[owner] = Schema.Build(self.BuildSchema, self.spec) end
			self.schemaCache = cache[owner]
		else
			self.schemaCache = Schema.Build(self.BuildSchema, self.spec)
		end
	end
	return self.schemaCache
end

local function Apply(self, resolved)
	local Perf = ns.Perf
	Perf:Count(self.componentOwner and "childApply" or "rootApply")
	Perf:Begin(self.className)
	self.resolved = resolved or Schema.Resolve(self:GetSchema(), self.config, ns.Config:GetTheme())
	Perf:Count("presentationApply")
	self:OnApply(self.resolved)
	if self.resolved.enabled ~= nil then
		self:SetEnabled(self.resolved.enabled)
	end
	Perf:End(self.className)
end

function Component:Apply(config, resolved)
	assert(not self.released, "Cannot apply a released component")
	if config then
		self.config = config
	end
	-- Group styles opt their entire composition into deferred presentation.
	if self.deferInCombat and InCombatLockdown() then
		ns.AfterCombat:Queue("apply", self, Component.Apply)
		return
	end
	ns.AfterCombat:Cancel(self, "apply")
	Schema.Shared(Apply, self, resolved)
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

-- The config of this component's `key` group for a child: the group's
-- default overrides plus the user's values (never resolved values, which
-- would turn inherited theme values into overrides). Shared inside a
-- Schema.Shared scope, so callers must not modify the result.
local function BuildChildConfig(schema, config, key)
	ns.Perf:Count("childConfigBuild")
	local opt = Schema.Find(schema, key)
	local out = ns.Util.Copy(opt and opt.defaults or {})
	return ns.Util.Merge(out, (config and config[key]) or {})
end

function Component:ChildConfig(key)
	local schema = self:GetSchema()
	ns.Perf:Count("childConfigCall")
	ns.Perf:Begin("child config")
	local config = Schema.Memo(BuildChildConfig, schema, self.config, key)
	ns.Perf:End("child config")
	return config
end

-- Applies the `key` group of this component's config to a child component.
function Component:ApplyChild(child, key, resolved)
	local config = self:ChildConfig(key)
	local effective = Schema.ReuseGroup(self:GetSchema(), key, child:GetSchema(), resolved)
	child:Apply(config, effective)
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
	ns.AfterCombat:Cancel(self)
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
