---@type string, table
local addonName, ns = ...

---@class G_RLF
local G_RLF = ns

---@class RLF_Notifications: RLF_Module, AceEvent-3.0
local Notifications = G_RLF.RLF:NewModule(G_RLF.SupportModule.Notifications, "AceEvent-3.0")

--- Build a uniform payload for a notification row.
---@param key string Unique row identity
---@param text string Primary line text
---@param secondaryText string Secondary line text
---@param index number Notification index (for ack)
---@return RLF_ElementPayload
function Notifications:BuildPayload(key, text, secondaryText, index)
	---@type RLF_ElementPayload
	local payload = {
		type = "Notifications",
		key = key,
		quantity = 0,
		textFn = function()
			return text
		end,
		secondaryTextFn = function()
			return secondaryText
		end,
		icon = "Interface/Addons/RPGLootFeed/Icons/logo.blp",
		quality = G_RLF.ItemQualEnum.Legendary,
		highlight = true,
		IsEnabled = function()
			return Notifications:IsEnabled()
		end,
	}
	return payload
end

function Notifications:OnInitialize()
	G_RLF.Notifications:CheckForNotifications()
	self:Enable()
end

function Notifications:OnEnable()
	-- Nothing yet
end

function Notifications:OnDisable()
	-- Nothing yet
end

function Notifications:ViewNotification(index)
	G_RLF:LogDebug("ViewNotification " .. index)
	if G_RLF.db.global.notifications and G_RLF.db.global.notifications[index] then
		local n = G_RLF.db.global.notifications[index]
		G_RLF.LootElementBase:fromPayload(self:BuildPayload(n.key, n.text, n.secondaryText, index)):Show()
		G_RLF.Notifications:AckNotification(index)
	end
end

function Notifications:ViewAllNotifications()
	G_RLF:LogDebug("ViewAllNotifications")
	if G_RLF.db.global.notifications then
		for i = #G_RLF.db.global.notifications, 1, -1 do
			if not G_RLF.db.global.notifications[i].seen then
				self:ViewNotification(i)
			end
		end
	end
	-- PlaySoundFile(569200)
end
