---@type string, table
local addonName, ns = ...

---@class G_RLF
local G_RLF = ns

---@class RLF_Notifications: RLF_Module, AceEvent-3.0
local Notifications = G_RLF.RLF:NewModule(G_RLF.SupportModule.Notifications, "AceEvent-3.0")

Notifications.Element = {}

function Notifications.Element:new(...)
	---@class Notifications.Element: RLF_BaseLootElement
	local element = G_RLF.LootElementBase:new()

	element.type = "Notifications"
	element.IsEnabled = function()
		return Notifications:IsEnabled()
	end

	local key, text, secondaryText, index = ...

	element.key = key
	element.quantity = 0
	element.textFn = function()
		return text
	end
	element.secondaryTextFn = function()
		return secondaryText
	end
	element.icon = "Interface/Addons/RPGLootFeed/Icons/logo.blp"
	element.quality = G_RLF.ItemQualEnum.Legendary
	element.highlight = true

	return element
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
		local e = self.Element:new(
			G_RLF.db.global.notifications[index].key,
			G_RLF.db.global.notifications[index].text,
			G_RLF.db.global.notifications[index].secondaryText,
			index
		)
		e:Show()
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
