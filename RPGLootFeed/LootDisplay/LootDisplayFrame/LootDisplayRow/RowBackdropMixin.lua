---@type string, table
local addonName, ns = ...

---@class G_RLF
local G_RLF = ns

---@class RLF_RowBackdropMixin
RLF_RowBackdropMixin = {}

local FALLBACK_BACKGROUND_TEXTURE = "Interface/Buttons/WHITE8X8"

function RLF_RowBackdropMixin:StyleBackground()
	local stylingDb = G_RLF.DbAccessor:Styling(self.frameType)

	if stylingDb.rowBackgroundType ~= G_RLF.RowBackground.GRADIENT then
		self.Background:Hide()
		return
	else
		self.Background:Show()
	end

	local changed = false

	local insets = stylingDb.backdropInsets
	local topInset = insets.top or 0
	local rightInset = insets.right or 0
	local bottomInset = insets.bottom or 0
	local leftInset = insets.left or 0
	local gradientStart = stylingDb.rowBackgroundGradientStart
	local gradientEnd = stylingDb.rowBackgroundGradientEnd
	local leftAlign = stylingDb.leftAlign

	if
		self.cachedGradientStart ~= gradientStart
		or self.cachedGradientEnd ~= gradientEnd
		or self.cachedBackgoundLeftAlign ~= leftAlign
		or self.cachedTopInset ~= topInset
		or self.cachedRightInset ~= rightInset
		or self.cachedBottomInset ~= bottomInset
		or self.cachedLeftInset ~= leftInset
	then
		self.cachedGradientStart = gradientStart
		self.cachedGradientEnd = gradientEnd
		self.cachedBackgoundLeftAlign = leftAlign
		self.cachedTopInset = topInset
		self.cachedRightInset = rightInset
		self.cachedBottomInset = bottomInset
		self.cachedLeftInset = leftInset
		changed = true
	end

	if changed then
		local leftColor = CreateColor(unpack(gradientStart))
		local rightColor = CreateColor(unpack(gradientEnd))
		if not leftAlign then
			leftColor, rightColor = rightColor, leftColor
		end
		self.Background:SetGradient("HORIZONTAL", leftColor, rightColor)

		if topInset ~= 0 or rightInset ~= 0 or bottomInset ~= 0 or leftInset ~= 0 then
			self.Background:ClearAllPoints()
			self.Background:SetPoint("TOPLEFT", self, "TOPLEFT", leftInset, -topInset)
			self.Background:SetPoint("BOTTOMRIGHT", self, "BOTTOMRIGHT", -rightInset, bottomInset)
		end
	end
end

function RLF_RowBackdropMixin:StyleRowBackdrop()
	---@type RLF_ConfigStyling
	local stylingDb = G_RLF.DbAccessor:Styling(self.frameType)
	local enableRowBorder = stylingDb.enableRowBorder
	local enableTexturedBackground = stylingDb.rowBackgroundType == G_RLF.RowBackground.TEXTURED
	if
		(not enableRowBorder or stylingDb.rowBorderTexture == "None")
		and (not enableTexturedBackground or stylingDb.rowBackgroundTexture == "None")
	then
		self:ClearBackdrop()
		return
	end

	local borderSize = stylingDb.rowBorderSize
	local classColors = stylingDb.rowBorderClassColors
	local borderColor = stylingDb.rowBorderColor
	local borderTexture = enableRowBorder and stylingDb.rowBorderTexture or "None"
	local backdropTexture = enableTexturedBackground and stylingDb.rowBackgroundTexture or "None"
	local backdropColorR = stylingDb.rowBackgroundTextureColor[1]
	local backdropColorG = stylingDb.rowBackgroundTextureColor[2]
	local backdropColorB = stylingDb.rowBackgroundTextureColor[3]
	local backdropColorA = stylingDb.rowBackgroundTextureColor[4] or 1
	local topInset = stylingDb.backdropInsets.top or 0
	local rightInset = stylingDb.backdropInsets.right or 0
	local bottomInset = stylingDb.backdropInsets.bottom or 0
	local leftInset = stylingDb.backdropInsets.left or 0
	local needsUpdate = false

	if
		self.cachedBorderSize ~= borderSize
		or self.cacheBorderColor ~= borderColor
		or self.cacheClassColors ~= classColors
		or self.cachedBorderTexture ~= borderTexture
		or self.cachedBackdropTexture ~= backdropTexture
		or self.cachedBackdropColorR ~= backdropColorR
		or self.cachedBackdropColorG ~= backdropColorG
		or self.cachedBackdropColorB ~= backdropColorB
		or self.cachedBackdropColorA ~= backdropColorA
		or self.cachedBackdropTopInset ~= topInset
		or self.cachedBackdropRightInset ~= rightInset
		or self.cachedBackdropBottomInset ~= bottomInset
		or self.cachedBackdropLeftInset ~= leftInset
	then
		self.cachedBorderSize = borderSize
		self.cacheBorderColor = borderColor
		self.cacheClassColors = classColors
		self.cachedBorderTexture = borderTexture
		self.cachedBackdropTexture = backdropTexture
		self.cachedBackdropColorR = backdropColorR
		self.cachedBackdropColorG = backdropColorG
		self.cachedBackdropColorB = backdropColorB
		self.cachedBackdropColorA = backdropColorA
		self.cachedBackdropTopInset = topInset
		self.cachedBackdropRightInset = rightInset
		self.cachedBackdropBottomInset = bottomInset
		self.cachedBackdropLeftInset = leftInset
		borderSize = G_RLF.PerfPixel.PScale(borderSize)
		topInset = G_RLF.PerfPixel.PScale(topInset)
		rightInset = G_RLF.PerfPixel.PScale(rightInset)
		bottomInset = G_RLF.PerfPixel.PScale(bottomInset)
		leftInset = G_RLF.PerfPixel.PScale(leftInset)
		needsUpdate = true
	end

	if not needsUpdate then
		return
	end

	-- Use textured borders via backdrop
	local lsm = G_RLF.lsm

	---@type backdropInfo
	local backdrop = {}

	if borderTexture ~= "None" then
		local texturePath = lsm:Fetch(lsm.MediaType.BORDER, borderTexture)

		if texturePath == nil or texturePath == "" then
			G_RLF:LogWarn("Could not find a texture path in LSM for border texture: %s", borderTexture)
		else
			backdrop.edgeFile = texturePath
			backdrop.edgeSize = borderSize
		end
	end

	if backdropTexture ~= "None" then
		local texturePath = lsm:Fetch(lsm.MediaType.BACKGROUND, backdropTexture)

		if texturePath == nil or texturePath == "" then
			G_RLF:LogWarn("Could not find a texture path in LSM for backdrop texture: %s", backdropTexture)
		else
			backdrop.bgFile = texturePath
			backdrop.insets = {
				left = leftInset,
				right = rightInset,
				top = topInset,
				bottom = bottomInset,
			}
		end
	else
		backdrop.bgFile = FALLBACK_BACKGROUND_TEXTURE
	end

	self:SetBackdrop(backdrop)

	if backdropTexture ~= "None" then
		self:SetBackdropColor(backdropColorR or 0, backdropColorG or 0, backdropColorB or 0, backdropColorA or 1)
	else
		self:SetBackdropColor(0, 0, 0, 0) -- Transparent background
	end

	-- Apply coloring to textured border
	if classColors then
		local classColor
		local a = 1
		if GetExpansionLevel() >= G_RLF.Expansion.BFA then
			classColor = C_ClassColor.GetClassColor(select(2, UnitClass(self.unit or "player")))
		else
			classColor = RAID_CLASS_COLORS[select(2, UnitClass(self.unit or "player"))]
		end
		if classColor == nil then
			G_RLF:LogWarn("Could not find a class color for unit: %s", self.unit or "player")
			-- Fallback to transparent black
			classColor = { r = 0, g = 0, b = 0 }
			a = 0
		end
		self:SetBackdropBorderColor(classColor.r, classColor.g, classColor.b, a)
	else
		local r, g, b, a = unpack(borderColor)
		self:SetBackdropBorderColor(r, g, b, a or 1)
	end
end

G_RLF.RLF_RowBackdropMixin = RLF_RowBackdropMixin
