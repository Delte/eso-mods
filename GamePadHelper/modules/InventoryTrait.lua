-- GetPlatformTraitInformationIcon is a PC-only alias; ZO_GetPlatformTraitInformationIcon is the base function
local _GetTraitIcon = ZO_GetPlatformTraitInformationIcon or GetPlatformTraitInformationIcon
local MultiIcon = _G["GamePadHelper_MultiIcon"]
local EQUIPPED_RESEARCH_COLOR = ZO_ColorDef:New("3399FF")

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
        return GetItemLink(bagId, slotIndex), bagId, slotIndex
    end

    if data.lootId ~= nil then
        return GetLootItemLink(data.lootId), nil, nil
    end

    return nil
end

local function IsEquippedDisplayItem(data, bagId)
    if bagId == BAG_WORN then
        return true
    end

    return type(data) == "table" and data.isEquipped == true
end

local function EnsureResearchLabel(control, icon)
    local label = control:GetNamedChild("StatusIndicatorLabel")
    if label ~= nil then
        return label
    end

    label = CreateControl("$(parent)StatusIndicatorLabel", control, CT_LABEL)
    label:SetFont("ZoFontGamepad18")
    label:SetInheritScale(false)
    label:SetMaxLineCount(1)
    label:SetWrapMode(TEXT_WRAP_MODE_ELLIPSIS)
    label:SetHorizontalAlignment(TEXT_ALIGN_CENTER)
    label:SetVerticalAlignment(TEXT_ALIGN_TOP)
    label:SetDrawLayer(DL_OVERLAY)
    label:SetDrawTier(DT_HIGH)
    label:ClearAnchors()
    label:SetAnchor(TOPLEFT, icon, BOTTOMLEFT, 0, 2)
    label:SetAnchor(TOPRIGHT, icon, BOTTOMRIGHT, 0, 2)
    return label
end

local function NormalizeTexture(texture)
    if type(texture) == "string" then
        return texture
    end

    return ""
end

local function SafeSetTexture(icon, texture)
    texture = NormalizeTexture(texture)
    if icon.SetTextureWithoutColor then
        icon.SetTextureWithoutColor(icon, texture)
    else
        icon:SetTexture(texture)
    end
    icon.activeTexture = texture ~= "" and texture or nil
end

local function SafeRemoveIcon(icon, iconTexture)
    if not icon or not iconTexture or not icon.iconData then
        return
    end

    local removedActiveTexture = icon.activeTexture == iconTexture
    local previousIconData = icon.iconData
    icon.iconData = {}

    for _, iconData in ipairs(previousIconData) do
        if iconData.iconTexture ~= iconTexture then
            table.insert(icon.iconData, iconData)
        end
    end

    if removedActiveTexture then
        local nextIconData = icon.iconData[1]
        local nextTexture = NormalizeTexture(nextIconData and nextIconData.iconTexture or nil)

        if nextTexture ~= "" then
            if icon.SetTexture then
                icon:SetTexture(nextTexture)
            else
                SafeSetTexture(icon, nextTexture)
            end

            if nextIconData and nextIconData.iconTint and icon.SetColor then
                icon:SetColor(nextIconData.iconTint:UnpackRGBA())
            elseif icon.SetColor then
                icon:SetColor(1, 1, 1, 1)
            end
        else
            SafeSetTexture(icon, "")
        end
    end
end

local function SafeRemoveIconColor(icon, iconTexture)
    if not icon or not icon.iconColors or not iconTexture then
        return
    end

    icon.iconColors[iconTexture] = nil
end

local function ClearTraitDecoration(icon, label, researchIcon)
    if researchIcon and icon:HasIcon(researchIcon) then
        SafeRemoveIcon(icon, researchIcon)
    end
    if researchIcon then
        SafeRemoveIconColor(icon, researchIcon)
    end
    if label then
        label:SetHidden(true)
    end
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

local function GetTraitLegendDescription()
    local lines = {}
    local researchIcon = _GetTraitIcon and _GetTraitIcon(ITEM_TRAIT_INFORMATION_CAN_BE_RESEARCHED)
    local ornateIcon = _GetTraitIcon and _GetTraitIcon(ITEM_TRAIT_INFORMATION_ORNATE)
    local intricateIcon = _GetTraitIcon and _GetTraitIcon(ITEM_TRAIT_INFORMATION_INTRICATE)

    local function AddResearchLine(hexColor, text)
        if researchIcon then
            table.insert(lines, string.format("|c%s%s|r %s", hexColor, zo_iconFormatInheritColor(researchIcon, 48, 48), text))
        else
            table.insert(lines, string.format("|c%s%s|r", hexColor, text))
        end
    end

    local function AddIconLine(iconTexture, text)
        if iconTexture then
            table.insert(lines, string.format("%s %s", zo_iconFormat(iconTexture, 48, 48), text))
        else
            table.insert(lines, text)
        end
    end

    AddResearchLine("3399FF", GetString(SI_GPH_TRAIT_LEGEND_EQUIPPED))
    AddResearchLine("2DC50E", GetString(SI_GPH_TRAIT_LEGEND_ONLY_COPY))
    AddResearchLine("FFFF00", GetString(SI_GPH_TRAIT_LEGEND_DUPLICATE_INVENTORY))
    AddResearchLine("FF4444", GetString(SI_GPH_TRAIT_LEGEND_DUPLICATE_BANK))

    if researchIcon then
        table.insert(lines, string.format("|cA0A0A0%s|r  +  |cFFFFFF2|r  = %s", zo_iconFormatInheritColor(researchIcon, 48, 48), GetString(SI_GPH_TRAIT_LEGEND_DUPLICATE_COUNT)))
    else
        table.insert(lines, string.format("+  |cFFFFFF2|r  = %s", GetString(SI_GPH_TRAIT_LEGEND_DUPLICATE_COUNT)))
    end
    AddIconLine(intricateIcon, GetString("SI_ITEMTRAITINFORMATION", ITEM_TRAIT_INFORMATION_INTRICATE))
    AddIconLine(ornateIcon, GetString("SI_ITEMTRAITINFORMATION", ITEM_TRAIT_INFORMATION_ORNATE))

    return table.concat(lines, "\n")
end

local function RefreshDeconstructionTraitLegend()
    local sv = _G["GamePadHelper_CharSavedVars"]
    if not sv or not sv.inventoryTraitEnabled then
        GAMEPAD_TOOLTIPS:ClearTooltip(GAMEPAD_RIGHT_TOOLTIP)
        return
    end

    GAMEPAD_TOOLTIPS:LayoutTitleAndDescriptionTooltip(
        GAMEPAD_RIGHT_TOOLTIP,
        GetString(SI_GPH_SETTING_INVENTORY_TRAITS_NAME),
        GetTraitLegendDescription()
    )
end

local function ClearDeconstructionTraitLegend()
    GAMEPAD_TOOLTIPS:ClearTooltip(GAMEPAD_RIGHT_TOOLTIP)
end

local function GetTraitResearchState(itemLink, bagId, slotIndex)
    if not itemLink or not LibTraitResearch then
        return nil
    end

    if LibTraitResearch.GetItemLinkTraitResearchStateForSlot and bagId ~= nil and slotIndex ~= nil then
        return LibTraitResearch:GetItemLinkTraitResearchStateForSlot(itemLink, bagId, slotIndex)
    end

    return LibTraitResearch:GetItemLinkTraitResearchState(itemLink)
end

local function BuildDuplicateLabelText(duplicateRemoteItems, colorRemote, duplicateLocalItems, colorLocal)
    if duplicateRemoteItems > 0 and duplicateLocalItems > 0 then
        return colorRemote:Colorize(duplicateRemoteItems) .. " " .. colorLocal:Colorize(duplicateLocalItems)
    elseif duplicateRemoteItems > 0 then
        return colorRemote:Colorize(duplicateRemoteItems)
    elseif duplicateLocalItems > 0 then
        return colorLocal:Colorize(duplicateLocalItems)
    end

    return nil
end

local function ApplyTraitOverrideData(data)
    local sv = _G["GamePadHelper_CharSavedVars"]
    if not sv or not sv.inventoryTraitEnabled or type(data) ~= "table" then
        return
    end

    local itemLink, bagId, slotIndex = GetItemLinkFromData(data)
    if not itemLink then
        data.gphTraitEquipped = nil
        return
    end

    local canBeResearched, colorOverall, duplicateRemoteItems, colorRemote, duplicateLocalItems, colorLocal =
        GetTraitResearchState(itemLink, bagId, slotIndex)

    if not canBeResearched then
        data.gphTraitLabelText = nil
        data.gphTraitEquipped = nil
        return
    end

    if IsEquippedDisplayItem(data, bagId) then
        data.gphTraitEquipped = true
        data.gphTraitLabelText = nil
    else
        data.gphTraitEquipped = nil
        data.gphTraitLabelText = BuildDuplicateLabelText(duplicateRemoteItems, colorRemote, duplicateLocalItems, colorLocal)
    end

    if not data.overrideStatusIndicatorIcons then
        return
    end

    local researchIcon = _GetTraitIcon and _GetTraitIcon(ITEM_TRAIT_INFORMATION_CAN_BE_RESEARCHED)
    if not researchIcon then
        return
    end

    local traitNarration = GetString("SI_ITEMTRAITINFORMATION", ITEM_TRAIT_INFORMATION_CAN_BE_RESEARCHED)
    local traitIconFound = false
    for _, iconData in ipairs(data.overrideStatusIndicatorIcons) do
        if iconData.iconTexture == researchIcon then
            iconData.iconTint = colorOverall
            iconData.iconNarration = traitNarration
            traitIconFound = true
        end
    end

    if not traitIconFound then
        table.insert(data.overrideStatusIndicatorIcons,
        {
            iconTexture = researchIcon,
            iconTint = colorOverall,
            iconNarration = traitNarration,
        })
    end
end

local function SharedGamepadEntry_OnSetup_After(control, data)
    local sv = _G["GamePadHelper_CharSavedVars"]
    if not sv or not sv.inventoryTraitEnabled then
        return
    end

    local icon = control:GetNamedChild("StatusIndicator")
    if not icon then
        return
    end

    if MultiIcon then
        MultiIcon.Initialize(icon)
    elseif not icon.HasIcon or not icon.AddIcon or not icon.SetIconColor then
        ZO_MultiIcon_Initialize(icon)
    end

    local researchIcon = _GetTraitIcon and _GetTraitIcon(ITEM_TRAIT_INFORMATION_CAN_BE_RESEARCHED)
    local label = EnsureResearchLabel(control, icon)
    label:SetHidden(true)

    local itemLink, bagId, slotIndex = GetItemLinkFromData(data)
    if not itemLink then
        ClearTraitDecoration(icon, label, researchIcon)
        RefreshMultiIcon(icon)
        return
    end

    if not LibTraitResearch then
        ClearTraitDecoration(icon, label, researchIcon)
        RefreshMultiIcon(icon)
        return
    end

    local canBeResearched, colorOverall, duplicateRemoteItems, colorRemote, duplicateLocalItems, colorLocal =
        GetTraitResearchState(itemLink, bagId, slotIndex)

    if not canBeResearched then
        ClearTraitDecoration(icon, label, researchIcon)
        RefreshMultiIcon(icon)
        return
    end

    if data.gphTraitEquipped or IsEquippedDisplayItem(data, bagId) then
        colorOverall = EQUIPPED_RESEARCH_COLOR
    end

    if researchIcon and not icon:HasIcon(researchIcon) then
        icon:AddIcon(researchIcon)
    end

    if icon.SetIconColor and researchIcon then
        icon:SetIconColor(researchIcon, colorOverall:UnpackRGBA())
    end
    icon:Show()

    local duplicateLabelText
    if not (data.gphTraitEquipped or IsEquippedDisplayItem(data, bagId)) then
        duplicateLabelText = data.gphTraitLabelText or BuildDuplicateLabelText(duplicateRemoteItems, colorRemote, duplicateLocalItems, colorLocal)
    end
    if duplicateLabelText then
        label:SetText(duplicateLabelText)
        label:SetHidden(false)
    end

    RefreshMultiIcon(icon)
end

ZO_PostHook("ZO_SharedGamepadEntry_OnSetup", SharedGamepadEntry_OnSetup_After)

local function WrapCustomExtraDataFunction(inventory)
    if not inventory or inventory.gphTraitExtraDataWrapped or type(inventory.customExtraDataFunction) ~= "function" then
        return
    end

    local originalCustomExtraDataFunction = inventory.customExtraDataFunction
    inventory.customExtraDataFunction = function(bagId, slotIndex, data)
        originalCustomExtraDataFunction(bagId, slotIndex, data)
        ApplyTraitOverrideData(data)
    end
    inventory.gphTraitExtraDataWrapped = true
end

local function PatchDeconstructionSetupFunctionForInventory(inventory)
    if not inventory or not inventory.list then
        return false
    end

    local list = inventory.list
    if not list.SetDataTemplateSetupFunction or not list.dataTypes then
        return false
    end

    local function WrapTemplate(templateName)
        local dataType = list.dataTypes[templateName]
        if not dataType or type(dataType.setupFunction) ~= "function" then
            return false
        end
        if dataType.gphTraitWrapped then
            return false
        end

        local originalSetup = dataType.setupFunction
        local wrappedSetup = function(control, data, selected, ...)
            originalSetup(control, data, selected, ...)
            SharedGamepadEntry_OnSetup_After(control, data)
        end

        list:SetDataTemplateSetupFunction(templateName, wrappedSetup)
        dataType.gphTraitWrapped = true
        return true
    end

    local patched = false
    patched = WrapTemplate("ZO_GamepadItemSubEntryTemplate") or patched
    patched = WrapTemplate("ZO_GamepadItemSubEntryTemplateWithHeader") or patched
    patched = WrapTemplate("ZO_GamepadItemSubEntry") or patched
    return patched
end

local deconstructionHooksInstalled = false
local bagHooksInstalled = false

local function HookBagInventoryList(inventoryList)
    if not inventoryList or inventoryList.gphTraitWrapped then
        return
    end

    if inventoryList.list and inventoryList.list.SetDataTemplateSetupFunction and inventoryList.list.dataTypes then
        local function WrapTemplate(templateName)
            local dataType = inventoryList.list.dataTypes[templateName]
            if not dataType or type(dataType.setupFunction) ~= "function" or dataType.gphTraitWrapped then
                return
            end

            local originalSetup = dataType.setupFunction
            inventoryList.list:SetDataTemplateSetupFunction(templateName, function(control, data, selected, ...)
                originalSetup(control, data, selected, ...)
                SharedGamepadEntry_OnSetup_After(control, data)
            end)
            dataType.gphTraitWrapped = true
        end

        WrapTemplate("ZO_GamepadItemSubEntryTemplate")
        WrapTemplate("ZO_GamepadItemSubEntryTemplateWithHeader")
        WrapTemplate("ZO_GamepadItemSubEntry")
    end

    local originalSetupItemEntry = inventoryList.SetupItemEntry
    inventoryList.SetupItemEntry = function(self, entry, itemData, ...)
        local result = originalSetupItemEntry(self, entry, itemData, ...)
        if entry then
            ApplyTraitOverrideData(entry)
            if type(entry.itemData) == "table" then
                entry.itemData.gphTraitLabelText = entry.gphTraitLabelText
            end
        end
        return result
    end

    inventoryList.gphTraitWrapped = true
end

local function DecorateDeconstructionVisibleControls(inventory)
    if not inventory or not inventory.list or not inventory.list.GetAllVisibleControls then
        return
    end

    local visibleControls = inventory.list:GetAllVisibleControls()
    if not visibleControls then
        return
    end

    for control in pairs(visibleControls) do
        local data = control.dataEntry and control.dataEntry.data
        if not data then
            local dataIndex = control.dataIndex
            if dataIndex and inventory.list.dataList then
                data = inventory.list.dataList[dataIndex]
            end
        end

        if data then
            ApplyTraitOverrideData(data)
            SharedGamepadEntry_OnSetup_After(control, data)
        end
    end
end

local function QueueDeconstructionVisibleRefresh(inventory)
    if not inventory then
        return
    end

    if inventory.gphTraitRefreshQueued then
        return
    end

    inventory.gphTraitRefreshQueued = true

    local function RunPass(delay)
        zo_callLater(function()
            if inventory.list then
                DecorateDeconstructionVisibleControls(inventory)
            end
            if delay == 200 then
                inventory.gphTraitRefreshQueued = false
            end
        end, delay)
    end

    RunPass(0)
    RunPass(50)
    RunPass(200)
end

local function HookDeconstructionInventory(inventory)
    if not inventory then
        return
    end

    WrapCustomExtraDataFunction(inventory)

    if not inventory.gphTraitRefreshWrapped then
        local originalPerformFullRefresh = inventory.PerformFullRefresh
        inventory.PerformFullRefresh = function(self, ...)
            WrapCustomExtraDataFunction(self)
            PatchDeconstructionSetupFunctionForInventory(self)
            local result = originalPerformFullRefresh(self, ...)
            DecorateDeconstructionVisibleControls(self)
            QueueDeconstructionVisibleRefresh(self)
            return result
        end
        inventory.gphTraitRefreshWrapped = true
    end

    if inventory.list and not inventory.list.gphTraitRefreshWrapped then
        local originalRefreshVisible = inventory.list.RefreshVisible
        inventory.list.RefreshVisible = function(listSelf, ...)
            local result = originalRefreshVisible(listSelf, ...)
            DecorateDeconstructionVisibleControls(inventory)
            QueueDeconstructionVisibleRefresh(inventory)
            return result
        end
        inventory.list.gphTraitRefreshWrapped = true
    end

    PatchDeconstructionSetupFunctionForInventory(inventory)
    DecorateDeconstructionVisibleControls(inventory)
    QueueDeconstructionVisibleRefresh(inventory)
end

local function HookDeconstructionTraitLegend(panel, scene)
    if not panel or panel.gphTraitLegendWrapped then
        return
    end

    local originalRefreshTooltip = panel.RefreshTooltip
    panel.RefreshTooltip = function(self, ...)
        local result = originalRefreshTooltip(self, ...)
        RefreshDeconstructionTraitLegend()
        return result
    end

    if scene and not panel.gphTraitLegendSceneHooked then
        scene:RegisterCallback("StateChange", function(oldState, newState)
            if newState == SCENE_SHOWING or newState == SCENE_SHOWN then
                zo_callLater(RefreshDeconstructionTraitLegend, 0)
            elseif newState == SCENE_HIDING or newState == SCENE_HIDDEN then
                ClearDeconstructionTraitLegend()
            end
        end)
        panel.gphTraitLegendSceneHooked = true
    end

    panel.gphTraitLegendWrapped = true
end

local function TryInstallDeconstructionHooks()
    if deconstructionHooksInstalled then
        return true
    end

    if not ZO_UniversalDeconstructionPanel_Gamepad or not ZO_GamepadSmithingExtraction then
        return false
    end

    ZO_PostHook(ZO_UniversalDeconstructionPanel_Gamepad, "InitializeInventory", function(self)
        HookDeconstructionInventory(self.inventory)
    end)

    ZO_PostHook(ZO_UniversalDeconstructionPanel_Gamepad, "Initialize", function(self, panelControl, floatingControl, universalDeconstructionParent, isRefinementOnly, scene)
        HookDeconstructionTraitLegend(self, scene)
    end)

    ZO_PostHook(ZO_GamepadSmithingExtraction, "InitializeInventory", function(self)
        HookDeconstructionInventory(self.inventory)
    end)

    ZO_PostHook(ZO_GamepadSmithingExtraction, "Initialize", function(self, panelControl, floatingControl, owner, isRefinementOnly, scene)
        HookDeconstructionTraitLegend(self, scene)
    end)

    if UNIVERSAL_DECONSTRUCTION_GAMEPAD
        and UNIVERSAL_DECONSTRUCTION_GAMEPAD.deconstructionPanel
        and UNIVERSAL_DECONSTRUCTION_GAMEPAD.deconstructionPanel.inventory
    then
        HookDeconstructionInventory(UNIVERSAL_DECONSTRUCTION_GAMEPAD.deconstructionPanel.inventory)
        HookDeconstructionTraitLegend(UNIVERSAL_DECONSTRUCTION_GAMEPAD.deconstructionPanel, UNIVERSAL_DECONSTRUCTION_GAMEPAD.scene)
    end

    if SMITHING_GAMEPAD and SMITHING_GAMEPAD.deconstructionPanel and SMITHING_GAMEPAD.deconstructionPanel.inventory then
        HookDeconstructionInventory(SMITHING_GAMEPAD.deconstructionPanel.inventory)
        HookDeconstructionTraitLegend(SMITHING_GAMEPAD.deconstructionPanel, GAMEPAD_SMITHING_DECONSTRUCT_SCENE)
    end

    deconstructionHooksInstalled = true
    return true
end

local function TryInstallBagHooks()
    if bagHooksInstalled then
        return true
    end

    if not GAMEPAD_INVENTORY then
        return false
    end

    if GAMEPAD_INVENTORY.itemList then
        HookBagInventoryList(GAMEPAD_INVENTORY.itemList)
    end

    if GAMEPAD_INVENTORY.vengeanceItemList then
        HookBagInventoryList(GAMEPAD_INVENTORY.vengeanceItemList)
    end

    bagHooksInstalled = GAMEPAD_INVENTORY.itemList ~= nil or GAMEPAD_INVENTORY.vengeanceItemList ~= nil
    return bagHooksInstalled
end

EVENT_MANAGER:RegisterForEvent("GPH_InventoryTrait_Initialize", EVENT_PLAYER_ACTIVATED, function()
    EVENT_MANAGER:UnregisterForEvent("GPH_InventoryTrait_Initialize", EVENT_PLAYER_ACTIVATED)

    local function TryLater()
        local installedDeconstruction = TryInstallDeconstructionHooks()
        local installedBag = TryInstallBagHooks()
        if not installedDeconstruction or not installedBag then
            zo_callLater(TryLater, 1000)
        end
    end

    TryLater()
end)
