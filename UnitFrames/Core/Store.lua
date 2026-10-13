local _, ns = ...
local Schema, Util = ns.Schema, ns.Util

--[[
A settings store: the one write path for a table of user overrides.

  Store:New({
    schema   = schema or function() return schema end,
    read     = function() return overrides end,   -- current override table
    write    = function(overrides) end,           -- optional; installs a validated replacement.
                                                   -- Without it, the read table is updated in place.
    theme    = true,                              -- resolve against the global theme
    validate = true,                              -- Schema.Validate a candidate before committing
    check    = function(candidate) return ok, reason end,  -- optional extra validation
    changed  = function(path) end,                -- after every commit; path nil = whole table
  })

Set/Edit/Reset/Replace return true, or false plus a reason when validation
fails (nothing is written then). Target() is an Inspector target for the store.

Descriptors may take part in writes (Core/Schema.lua):
  onSet(group, value, resolvedGroup)   after Set writes the option: further
                                       changes to its group in the same commit.
                                       resolvedGroup is the effective group
                                       before the change.
  invoke(store, path)                  an "action" option's handler
]]
local Store = ns.Object:Extend("Store")
ns.Store = Store

function Store:Init(opts)
	self.opts = opts
end

function Store:GetSchema()
	local schema = self.opts.schema
	return type(schema) == "function" and schema() or schema
end

function Store:Read()
	return self.opts.read()
end

function Store:Get(path)
	return Util.GetPath(self:Read(), path)
end

function Store:Resolved()
	return Schema.Resolve(self:GetSchema(), self:Read(), self.opts.theme and ns.Config:GetTheme() or nil)
end

local function Check(store, candidate)
	if store.opts.validate then
		local errors = Schema.Validate(store:GetSchema(), candidate)
		if #errors > 0 then return false, table.concat(errors, "; ") end
	end
	if store.opts.check then return store.opts.check(candidate) end
	return true
end

-- Validated stores commit a candidate copy; others edit the live table.
local function Commit(store, candidate, path)
	local ok, reason = Check(store, candidate)
	if not ok then return false, reason end
	if store.opts.write then
		store.opts.write(candidate)
	else
		local current = store:Read()
		if current ~= candidate then
			wipe(current)
			Util.Merge(current, candidate)
		end
	end
	if store.opts.changed then store.opts.changed(path) end
	return true
end

local function Candidate(store)
	return (store.opts.validate or store.opts.check or store.opts.write) and Util.Copy(store:Read()) or store:Read()
end

local function Parent(path)
	return path:match("^(.*)%.[^%.]+$")
end

-- The override group at `path` ("" or nil: the top level), created if needed.
local function Group(candidate, path)
	if not path or path == "" then return candidate end
	local group = Util.GetPath(candidate, path)
	if type(group) ~= "table" then
		group = {}
		Util.SetPath(candidate, path, group)
	end
	return group
end

local function ResolvedGroup(store, path)
	local resolved = store:Resolved()
	if not path or path == "" then return resolved end
	return Util.GetPath(resolved, path) or {}
end

-- value nil removes the override (back to the inherited/default value).
function Store:Set(path, value)
	local opt = Schema.Find(self:GetSchema(), path)
	local before = opt and opt.onSet and ResolvedGroup(self, Parent(path))
	local candidate = Candidate(self)
	if value == nil then
		Util.ClearPath(candidate, path)
	else
		Util.SetPath(candidate, path, value)
	end
	if before then opt.onSet(Group(candidate, Parent(path)), value, before) end
	return Commit(self, candidate, path)
end

-- Several changes to the group at `path` as one commit:
-- edit(group, resolvedGroup) changes the override table `group`.
function Store:Edit(path, edit)
	local resolved = ResolvedGroup(self, path)
	local candidate = Candidate(self)
	edit(Group(candidate, path), resolved)
	return Commit(self, candidate, path ~= "" and path or nil)
end

-- Replaces every override at once (copying settings, presets).
function Store:Replace(overrides)
	return Commit(self, Util.Copy(overrides or {}), nil)
end

function Store:Reset()
	return self:Replace({})
end

-- Inspector target. `report` receives validation failures; `resolved`
-- optionally replaces the store's own resolution (e.g. a live component's).
function Store:Target(report, resolved)
	return {
		schema = self:GetSchema(),
		get = function(path) return self:Get(path) end,
		set = function(path, value)
			local ok, reason = self:Set(path, value)
			if not ok and report then report(reason) end
			return ok, reason
		end,
		resolved = resolved or function() return self:Resolved() end,
		invoke = function(path) self:Invoke(path) end,
	}
end

-- Runs an action option's own handler, if it has one.
function Store:Invoke(path)
	local opt = Schema.Find(self:GetSchema(), path)
	if opt and opt.invoke then opt.invoke(self, path) end
end
