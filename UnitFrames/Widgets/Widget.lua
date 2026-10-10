local _, ns = ...

-- Base class of our UI controls (settings window, Workbench). Unlike
-- components, widgets take plain `opts` and have no schema or theme.
local Widget = ns.Object:Extend("Widget")
ns.Widget = Widget

function Widget:Extend(className)
	local class = ns.Object.Extend(self, className)
	ns.Widgets[className] = class
	return class
end

function Widget:New(parent, opts)
	local widget = setmetatable({}, self)
	widget.opts = opts or {}
	widget:OnCreate(parent, widget.opts)
	return widget
end

function Widget:OnCreate(parent, opts) end

function Widget:GetFrame()
	return self.frame
end

function Widget:SetPoint(...)
	self.frame:SetPoint(...)
end

function Widget:ClearAllPoints()
	self.frame:ClearAllPoints()
end

function Widget:SetSize(width, height)
	self.frame:SetSize(width, height)
end

function Widget:SetWidth(width)
	self.frame:SetWidth(width)
end

function Widget:GetHeight()
	return self.frame:GetHeight()
end

function Widget:Show()
	self.frame:Show()
end

function Widget:Hide()
	self.frame:Hide()
end

function Widget:SetShown(shown)
	self.frame:SetShown(shown)
end

function Widget:IsShown()
	return self.frame:IsShown()
end

-- Shared tooltip helper for controls with opts.tooltip.
function Widget.AttachTooltip(frame, title, text)
	if not text then
		return
	end
	frame:HookScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText(title or "", 1, 1, 1)
		GameTooltip:AddLine(text, nil, nil, nil, true)
		GameTooltip:Show()
	end)
	frame:HookScript("OnLeave", function()
		GameTooltip:Hide()
	end)
end
