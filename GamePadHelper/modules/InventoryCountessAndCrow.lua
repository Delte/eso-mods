local Utils = _G["GamePadHelper_Utils"]
local MultiIcon = _G["GamePadHelper_IconExtensions"]
local QUEST_ICON = "/esoui/art/inventory/gamepad/gp_inventory_icon_quest.dds"

local COLOR_COUNTESS_ACTIVE = ZO_ColorDef:New(0.18, 0.77, 0.05)
local COLOR_CROW_ACTIVE = ZO_ColorDef:New(0.2, 0.6, 1.0)
local COLOR_USEFUL_INACTIVE = ZO_ColorDef:New(1, 1, 1)

local function EnsureStatusIndicatorInitialized(statusIndicator)
    if MultiIcon then
        MultiIcon.Initialize(statusIndicator)
    elseif not statusIndicator.HasIcon or not statusIndicator.AddIcon or not statusIndicator.SetIconColor then
        ZO_MultiIcon_Initialize(statusIndicator)
    end
end

local function ClearCovetousDecoration(statusIndicator)
    if not statusIndicator then
        return
    end

    EnsureStatusIndicatorInitialized(statusIndicator)

    if statusIndicator.RemoveIcon and QUEST_ICON then
        statusIndicator:RemoveIcon(QUEST_ICON)
    end
    if statusIndicator.RemoveIconColor and QUEST_ICON then
        statusIndicator:RemoveIconColor(QUEST_ICON)
    end
end

local function GetItemLinkFromData(data)
    if type(data) ~= "table" then
        return nil
    end

    if type(data.itemLink) == "string" and data.itemLink ~= "" then
        return data.itemLink
    elseif type(data.link) == "string" and data.link ~= "" then
        return data.link
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
    local sv = _G["GamePadHelper_CharSavedVars"]
    local statusIndicator = control:GetNamedChild("StatusIndicator")
    if not statusIndicator then return end

    ClearCovetousDecoration(statusIndicator)

    if not sv or (not sv.inventoryCovetousCountessEnabled and not sv.inventoryCrowEnabled) then return end

    local itemLink = GetItemLinkFromData(data)
    if not itemLink then return end

    local itemType = GetItemLinkItemType(itemLink)
    if itemType ~= ITEMTYPE_TREASURE then return end

    local isUsefulForActiveQuest, isUsefulForQuest = Utils.GetCountessState(itemLink)
    local isUsefulForActiveCrowGroup, isUsefulForCrow = Utils.GetCrowState(itemLink)

    EnsureStatusIndicatorInitialized(statusIndicator)

    local showCountess = sv.inventoryCovetousCountessEnabled and isUsefulForQuest
    local showCrow = sv.inventoryCrowEnabled and isUsefulForCrow

    if (showCountess or showCrow) and QUEST_ICON then
        if not statusIndicator:HasIcon(QUEST_ICON) then
            statusIndicator:AddIcon(QUEST_ICON)
        end
        if statusIndicator.SetIconColor then
            local color
            if showCountess and isUsefulForActiveQuest then
                color = COLOR_COUNTESS_ACTIVE
            elseif showCrow and isUsefulForActiveCrowGroup then
                color = COLOR_CROW_ACTIVE
            else
                color = COLOR_USEFUL_INACTIVE
            end
            statusIndicator:SetIconColor(QUEST_ICON, color:UnpackRGBA())
        end
    end

    if (sv.inventoryCovetousCountessEnabled and isUsefulForQuest) or (sv.inventoryCrowEnabled and isUsefulForCrow) then
        statusIndicator:Show()
    else
        ClearCovetousDecoration(statusIndicator)
    end

    RefreshMultiIcon(statusIndicator)
end

ZO_PostHook("ZO_SharedGamepadEntry_OnSetup", SharedGamepadEntry_OnSetup_After)
