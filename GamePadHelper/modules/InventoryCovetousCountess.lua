-- GetPlatformTraitInformationIcon is a PC-only alias; ZO_GetPlatformTraitInformationIcon is the base function
local _GetTraitIcon = ZO_GetPlatformTraitInformationIcon or GetPlatformTraitInformationIcon
local MultiIcon = _G["GamePadHelper_MultiIcon"]

local COLOR_USEFUL_ACTIVE = ZO_ColorDef:New(1, 1, 0)
local COLOR_USEFUL_INACTIVE = ZO_ColorDef:New(1, 1, 1)

local function GetItemLinkFromData(data)
    if type(data) ~= "table" then
        return nil
    end

    local bagId = data.bagId or data.bag
    local slotIndex = data.slotIndex or data.index

    if (bagId == nil or slotIndex == nil) and type(data.dataSource) == "table" then
        bagId = data.dataSource.bagId or data.dataSource.bag or bagId
        slotIndex = data.dataSource.slotIndex or data.dataSource.index or slotIndex
    end

    if (bagId == nil or slotIndex == nil) and type(data.itemData) == "table" then
        bagId = data.itemData.bagId or data.itemData.bag or bagId
        slotIndex = data.itemData.slotIndex or data.itemData.index or slotIndex
    end

    if bagId ~= nil and slotIndex ~= nil then
        return GetItemLink(bagId, slotIndex)
    elseif data.lootId ~= nil then
        return GetLootItemLink(data.lootId)
    end

    return nil
end

local function RefreshMultiIcon(icon)
    if not icon or not icon.iconData or not icon.Hide or not icon.Show then
        return
    end

    local wasHidden = icon:IsHidden()
    if not wasHidden then
        icon:Hide()
    end
    icon:Show()
end

local function SharedGamepadEntry_OnSetup_After(control, data, ...)
    local sv = _G["GamePadHelper_SavedVars"]
    if not sv or not sv.inventoryCovetousCountessEnabled then return end
    local statusIndicator = control:GetNamedChild("StatusIndicator")
    if not statusIndicator then return end

    local itemLink = GetItemLinkFromData(data)
    if not itemLink then return end

    local itemType = GetItemLinkItemType(itemLink)
    if itemType ~= ITEMTYPE_TREASURE then return end

    local researchIcon = _GetTraitIcon and _GetTraitIcon(ITEM_TRAIT_INFORMATION_CAN_BE_RESEARCHED)
    local isUsefulForActiveQuest, isUsefulForQuest = false, false
    if LibCovetousCountess and LibCovetousCountess.IsItemUseful then
        local success, result1, result2 = pcall(LibCovetousCountess.IsItemUseful, LibCovetousCountess, itemLink)
        if success then
            isUsefulForActiveQuest, isUsefulForQuest = result1, result2
        end
    end

    if MultiIcon then
        MultiIcon.Initialize(statusIndicator)
    elseif not statusIndicator.HasIcon or not statusIndicator.AddIcon or not statusIndicator.SetIconColor then
        ZO_MultiIcon_Initialize(statusIndicator)
    end

    if isUsefulForQuest then
        if researchIcon and not statusIndicator:HasIcon(researchIcon) then
            statusIndicator:AddIcon(researchIcon)
        end
        if statusIndicator.SetIconColor and researchIcon then
            local color = isUsefulForActiveQuest and COLOR_USEFUL_ACTIVE or COLOR_USEFUL_INACTIVE
            statusIndicator:SetIconColor(researchIcon, color:UnpackRGBA())
        end
        statusIndicator:Show()
    else
        if statusIndicator.RemoveIcon and researchIcon then
            statusIndicator:RemoveIcon(researchIcon)
        end
        if statusIndicator.RemoveIconColor and researchIcon then
            statusIndicator:RemoveIconColor(researchIcon)
        end
    end

    RefreshMultiIcon(statusIndicator)
end

ZO_PostHook("ZO_SharedGamepadEntry_OnSetup", SharedGamepadEntry_OnSetup_After)
