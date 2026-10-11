local _, CG = ...
local UF = CG.UF
local Config = {}
CG.Config = Config
Config.schema = {
	{ key = "panel", type = "group", label = "Panel layout", schema = CG.LayoutSchema },
	{ key = "titles", type = "group", label = "Group / column titles", schema = CG.TitleSchema },
	{ key = "indicators", type = "group", label = "Status indicators", schema = CG.IndicatorSchema },
	{ key = "slots", type = "group", label = "Fixed friendly buff slots", schema = CG.SlotSchema },
}

function Config:Initialize()
	self.db = UF.Config.db:RegisterNamespace("ClickGrid", {
		profile = { version = 1, settings = {}, member = {}, target = {} },
		char = { loadouts = {} },
	})
end

function Config:Get()
	return self.db.profile.settings
end

function Config:Resolved()
	return UF.Schema.Resolve(self.schema, self:Get(), UF.Config:GetTheme())
end

function Config:Set(path, value)
	local candidate = UF.Util.Copy(self:Get())
	if value == nil then UF.Util.ClearPath(candidate, path) else UF.Util.SetPath(candidate, path, value) end
	local errors = UF.Schema.Validate(self.schema, candidate)
	if #errors > 0 then return false, table.concat(errors, "; ") end
	local slots = UF.Schema.Resolve(CG.SlotSchema, candidate.slots)
	for _, slot in pairs(slots) do
		local ids, reason = CG.Slots.ParseIDs(slot.spell)
		if not ids then return false, reason end
	end
	self.db.profile.settings = candidate
	CG:RequestRefresh()
	UF.Events:Fire("ClickGridConfigChanged", path)
	return true
end

function Config:GetStyle(kind)
	return self.db.profile[kind]
end

function Config:SetStyle(kind, path, value)
	local candidate = UF.Util.Copy(self:GetStyle(kind))
	if value == nil then UF.Util.ClearPath(candidate, path) else UF.Util.SetPath(candidate, path, value) end
	local errors = UF.Schema.Validate(CG.styleSchemas[kind], candidate)
	if #errors > 0 then return false, table.concat(errors, "; ") end
	self.db.profile[kind] = candidate
	CG:RequestRefresh()
	UF.Events:Fire("ClickGridConfigChanged", kind)
	return true
end

function Config:SpecKey()
	if CG.Caps.specialization then
		local index = C_SpecializationInfo.GetSpecialization()
		if not issecretvalue(index) and index then return tostring(index) end
	end
	return "default"
end

function Config:GetBindings()
	local key = self:SpecKey()
	local loadouts = self.db.char.loadouts
	loadouts[key] = loadouts[key] or {}
	return loadouts[key]
end

function Config:SetBinding(button, modifier, reaction, field, value)
	local path = "button" .. button .. "." .. modifier .. "." .. reaction .. "." .. field
	local candidate = UF.Util.Copy(self:GetBindings())
	if value == nil then UF.Util.ClearPath(candidate, path) else UF.Util.SetPath(candidate, path, value) end
	local errors = UF.Schema.Validate(CG.Bindings.schema, candidate)
	if #errors > 0 then return false, table.concat(errors, "; ") end
	self.db.char.loadouts[self:SpecKey()] = candidate
	CG:RequestRefresh()
	UF.Events:Fire("ClickGridConfigChanged", "bindings")
	return true
end
