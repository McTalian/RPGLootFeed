---@type string, table
local addonName, ns = ...

---@class G_RLF
local G_RLF = ns

---@class RLF_RowScriptedEffectsMixin
RLF_RowScriptedEffectsMixin = {}

function RLF_RowScriptedEffectsMixin:CreateScriptedEffects()
	if not G_RLF:IsRetail() then
		return
	end

	if not self.leftSideTexture then
		self.leftSideTexture = self:CreateTexture(nil, "ARTWORK")
	end

	if not self.rightSideTexture then
		self.rightSideTexture = self:CreateTexture(nil, "ARTWORK")
	end

	if not self.leftModelScene then
		self.leftModelScene = CreateFrame("ModelScene", nil, self, "ScriptAnimatedModelSceneTemplate")
	end

	if not self.rightModelScene then
		self.rightModelScene = CreateFrame("ModelScene", nil, self, "ScriptAnimatedModelSceneTemplate")
	end

	-- Initialize scripted animation effect timers
	if not self.scriptedEffectTimers then
		self.scriptedEffectTimers = {}
	end

	local changed = false

	local sizingDb = G_RLF.DbAccessor:Sizing(self.frameType)
	local feedWidth = sizingDb.feedWidth
	local rowHeight = sizingDb.rowHeight
	if self.cachedModelSceneFeedWidthRef ~= feedWidth or self.cachedModelSceneRowHeightRef ~= rowHeight then
		self.cachedModelSceneFeedWidthRef = feedWidth
		self.cachedModelSceneRowHeightRef = rowHeight
		changed = true
	end

	if changed then
		local scaledHeight = G_RLF.PerfPixel.PScale(7 / 6 * rowHeight)
		local scaledWidth = G_RLF.PerfPixel.PScale(0.03 * feedWidth)
		self.leftSideTexture:ClearAllPoints()
		self.leftSideTexture:SetTexture("Interface\\LootFrame\\CosmeticToast")
		self.leftSideTexture:SetTexCoord(0.03, 0.06, 0.05, 0.95)
		self.leftSideTexture:SetPoint("TOPLEFT", self, "TOPLEFT")
		self.leftSideTexture:SetSize(scaledWidth, scaledHeight)

		self.rightSideTexture:ClearAllPoints()
		self.rightSideTexture:SetTexture("Interface\\LootFrame\\CosmeticToast")
		self.rightSideTexture:SetTexCoord(0.535, 0.565, 0.05, 0.95)
		self.rightSideTexture:SetPoint("TOPRIGHT", self, "TOPRIGHT")
		self.rightSideTexture:SetSize(scaledWidth, scaledHeight)

		local modelSceneHeight = G_RLF.PerfPixel.PScale(0.7 * scaledHeight)
		local modelSceneWidth = G_RLF.PerfPixel.PScale(0.8 * scaledWidth)
		self.leftModelScene:SetPoint("TOPLEFT", self.leftSideTexture, "TOPLEFT")
		self.leftModelScene:SetSize(modelSceneWidth, modelSceneHeight)

		self.rightModelScene:SetPoint("TOPRIGHT", self.rightSideTexture, "TOPRIGHT")
		self.rightModelScene:SetSize(modelSceneWidth, modelSceneHeight)

		self.leftSideTexture:Hide()
		self.rightSideTexture:Hide()
	end
end

function RLF_RowScriptedEffectsMixin:PlayTransmogEffect()
	if not G_RLF:IsRetail() then
		return
	end

	if not self.leftModelScene or not self.rightModelScene or not self.scriptedEffectTimers then
		self:CreateScriptedEffects()
	end

	-- Clear any existing effects
	self:StopScriptedEffects()

	if G_RLF.db.global.transmog.enableBlizzardTransmogSound then
		PlaySound(SOUNDKIT.UI_COSMETIC_ITEM_TOAST_SHOW)
	end

	if not G_RLF.db.global.transmog.enableTransmogEffect then
		self.leftSideTexture:Hide()
		self.rightSideTexture:Hide()
		return
	end

	self.leftSideTexture:Show()
	self.rightSideTexture:Show()

	-- Effect IDs from the transmog system (these are the same ones used in the WoW source)
	local effectID1 = 135 -- Lightning effect
	local effectID2 = 136 -- Secondary lightning effect

	-- Create and play the effects with staggered timing
	self.leftModelScene:AddEffect(effectID1, self.leftModelScene)
	table.insert(
		self.scriptedEffectTimers,
		C_Timer.NewTimer(0.25, function()
			self.leftModelScene:AddEffect(effectID2, self.leftModelScene)
		end)
	)
	table.insert(
		self.scriptedEffectTimers,
		C_Timer.NewTimer(0.5, function()
			self.leftModelScene:AddEffect(effectID1, self.leftModelScene)
		end)
	)

	table.insert(
		self.scriptedEffectTimers,
		C_Timer.NewTimer(0.3, function()
			self.rightModelScene:AddEffect(effectID1, self.rightModelScene)
		end)
	)
	table.insert(
		self.scriptedEffectTimers,
		C_Timer.NewTimer(0.55, function()
			self.rightModelScene:AddEffect(effectID2, self.rightModelScene)
		end)
	)
	table.insert(
		self.scriptedEffectTimers,
		C_Timer.NewTimer(0.8, function()
			self.rightModelScene:AddEffect(effectID1, self.rightModelScene)
		end)
	)
end

function RLF_RowScriptedEffectsMixin:StopScriptedEffects()
	if not G_RLF:IsRetail() then
		return
	end

	if self.leftModelScene then
		self.leftModelScene:ClearEffects()
	end

	if self.rightModelScene then
		self.rightModelScene:ClearEffects()
	end

	if self.scriptedEffectTimers then
		for i, timer in ipairs(self.scriptedEffectTimers) do
			timer:Cancel()
		end
	end

	self.scriptedEffectTimers = {}
end

G_RLF.RLF_RowScriptedEffectsMixin = RLF_RowScriptedEffectsMixin
