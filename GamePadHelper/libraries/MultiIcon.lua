local MultiIcon = {}

local function SetColor(self, r, g, b, a)
    if self.iconColors ~= nil and self.activeTexture ~= nil then
        local color = self.iconColors[self.activeTexture]
        if color ~= nil then
            self.SetColorWithoutIconColor(self, color.r, color.g, color.b, color.a)
            return
        end
    end

    self.SetColorWithoutIconColor(self, r, g, b, a)
end

local function SetTexture(self, texture)
    self.activeTexture = texture
    self.SetTextureWithoutColor(self, texture)

    if self.iconColors ~= nil then
        local color = self.iconColors[texture]
        if color ~= nil then
            self:SetColor(color.r, color.g, color.b, color.a)
        else
            self:SetColor(1, 1, 1, 1)
        end
    end
end

local function ClearIcons(self)
    self:Hide()
    self.activeTexture = nil

    if self.iconData ~= nil then
        ZO_ClearNumericallyIndexedTable(self.iconData)
    end

    self.SetTextureWithoutColor(self, "")
end

local function RemoveIcon(self, iconTexture)
    local removedActiveTexture = self.activeTexture == iconTexture

    if self.iconData then
        local previousIconData = self.iconData
        self.iconData = {}

        for _, iconData in ipairs(previousIconData) do
            if iconData.iconTexture ~= iconTexture then
                table.insert(self.iconData, iconData)
            end
        end
    end

    if removedActiveTexture then
        local nextIconData = self.iconData and self.iconData[1] or nil
        local nextTexture = nextIconData and nextIconData.iconTexture or nil
        self.activeTexture = nextTexture

        if nextTexture ~= nil then
            self:SetTexture(nextTexture)
            if nextIconData.iconTint ~= nil then
                self:SetColor(nextIconData.iconTint:UnpackRGBA())
            else
                self:SetColor(1, 1, 1, 1)
            end
        else
            self:SetTextureWithoutColor(self, "")
        end
    end
end

local function SetIconColor(self, iconTexture, r, g, b, a)
    if not self.iconColors then
        self.iconColors = {}
    end

    self.iconColors[iconTexture] = { r = r, g = g, b = b, a = a }

    if iconTexture == self.activeTexture then
        self:SetColor(r, g, b, a)
    end
end

local function RemoveIconColor(self, iconTexture)
    if not self.iconColors then
        self.iconColors = {}
    end

    self.iconColors[iconTexture] = nil
end

function MultiIcon.Initialize(self)
    if not self then
        return nil
    end

    if self.gphMultiIconInitialized then
        return self
    end

    if not self.HasIcon or not self.AddIcon then
        ZO_MultiIcon_Initialize(self)
    end

    -- If another addon/library already wrapped this control's multi-icon methods,
    -- do not wrap them again. Double-wrapping SetColor/SetTexture causes recursion.
    if self.SetTextureWithoutColor ~= nil or self.SetColorWithoutIconColor ~= nil then
        self.gphMultiIconInitialized = true
        return self
    end

    if self.SetTexture ~= SetTexture then
        self.SetTextureWithoutColor = self.SetTexture
        self.SetTexture = SetTexture
    end

    if self.SetColor ~= SetColor then
        self.SetColorWithoutIconColor = self.SetColor
        self.SetColor = SetColor
    end

    self.ClearIcons = ClearIcons
    self.RemoveIcon = RemoveIcon
    self.SetIconColor = SetIconColor
    self.RemoveIconColor = RemoveIconColor
    self.gphMultiIconInitialized = true

    return self
end

_G["GamePadHelper_MultiIcon"] = MultiIcon
