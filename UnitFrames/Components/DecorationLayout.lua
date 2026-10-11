local _, ns = ...

-- Configured geometry only: native artwork may have opaque dimensions.
local Layout = {}
ns.DecorationLayout = Layout

function Layout.Place(host, context, anchor, size, x, y)
	host:ClearAllPoints()
	host:SetSize(size, size)
	local corner = anchor:match("^PORTRAIT_(.+)$")
	if corner then
		local portrait = context.portrait
		if not portrait then return false end
		local fitted = math.min(size, portrait.width, portrait.height)
		host:SetSize(fitted, fitted)
		host:SetPoint(corner, portrait.frame, corner, x, y)
	else
		host:SetPoint("CENTER", context.root, anchor, x, y)
	end
	return true
end
