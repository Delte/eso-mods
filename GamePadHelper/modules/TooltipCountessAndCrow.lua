local QUEST_ICON = zo_iconFormatInheritColor("/esoui/art/inventory/gamepad/gp_inventory_icon_quest.dds", 32, 32)
local COLOR_COUNTESS_ACTIVE = ZO_ColorDef:New(0.18, 0.77, 0.05)
local COLOR_CROW_ACTIVE = ZO_ColorDef:New(0.2, 0.6, 1.0)
local COLOR_USEFUL_INACTIVE = ZO_ColorDef:New(1, 1, 1)

local function GetCountessState(itemLink)
    if not itemLink or itemLink == "" then
        return false, false
    end

    if not LibCovetousCountess or not LibCovetousCountess.IsItemUsefulForCountess then
        return false, false
    end

    local success, isUsefulForActiveQuest, isUsefulForQuest = pcall(LibCovetousCountess.IsItemUsefulForCountess, LibCovetousCountess, itemLink)
    if not success then
        return false, false
    end

    return isUsefulForActiveQuest, isUsefulForQuest
end

local function GetCrowState(itemLink)
    if not itemLink or itemLink == "" then
        return false, false
    end

    if not LibCovetousCountess or not LibCovetousCountess.IsItemUsefulForCrow then
        return false, false
    end

    local success, isUsefulForActiveGroup, isUsefulForCrow = pcall(LibCovetousCountess.IsItemUsefulForCrow, LibCovetousCountess, itemLink)
    if not success then
        return false, false
    end

    return isUsefulForActiveGroup, isUsefulForCrow
end

local function OnAddonLoaded(event, name)
    if name ~= "GamePadHelper" then
        return
    end

    EVENT_MANAGER:UnregisterForEvent("TooltipCountessAndCrow", EVENT_ADD_ON_LOADED)

    local function Tooltip_AddCovetousCountess_After(self, itemLink)
        local sv = _G["GamePadHelper_CharSavedVars"]
        if not sv or (not sv.tooltipCovetousCountessEnabled and not sv.tooltipCrowEnabled) then
            return
        end

        if GetItemLinkItemType(itemLink) ~= ITEMTYPE_TREASURE then
            return
        end

        local isUsefulForActiveQuest, isUsefulForQuest = GetCountessState(itemLink)
        local isUsefulForActiveCrowGroup, isUsefulForCrow = GetCrowState(itemLink)

        if not isUsefulForQuest and not isUsefulForCrow then
            return
        end

        if sv.tooltipCovetousCountessEnabled and isUsefulForQuest then
            local covetousSection = self:AcquireSection(self:GetStyle("bodySection"))
            local iconColor = isUsefulForActiveQuest and COLOR_COUNTESS_ACTIVE or COLOR_USEFUL_INACTIVE
            local title = string.format("%s (%s)", GetString(SI_GPH_TOOLTIP_COVETOUS_TITLE), iconColor:Colorize(QUEST_ICON))
            local descriptionStringId = isUsefulForActiveQuest and SI_GPH_TOOLTIP_COVETOUS_ACTIVE or SI_GPH_TOOLTIP_COVETOUS_INACTIVE

            covetousSection:AddLine(title, self:GetStyle("bodyHeader"))
            covetousSection:AddLine(GetString(descriptionStringId), self:GetStyle("bodyDescription"))
            self:AddSection(covetousSection)
        end

        if sv.tooltipCrowEnabled and isUsefulForCrow then
            local crowSection = self:AcquireSection(self:GetStyle("bodySection"))
            local iconColor = isUsefulForActiveCrowGroup and COLOR_CROW_ACTIVE or COLOR_USEFUL_INACTIVE
            local title = string.format("%s (%s)", GetString(SI_GPH_TOOLTIP_CROW_TITLE), iconColor:Colorize(QUEST_ICON))
            local descriptionStringId = isUsefulForActiveCrowGroup and SI_GPH_TOOLTIP_CROW_ACTIVE or SI_GPH_TOOLTIP_CROW_INACTIVE

            crowSection:AddLine(title, self:GetStyle("bodyHeader"))
            crowSection:AddLine(GetString(descriptionStringId), self:GetStyle("bodyDescription"))
            self:AddSection(crowSection)
        end
    end

    local tooltips = {
        GAMEPAD_LEFT_DIALOG_TOOLTIP,
        GAMEPAD_LEFT_TOOLTIP,
        GAMEPAD_MOVABLE_TOOLTIP,
        GAMEPAD_QUAD1_TOOLTIP,
        GAMEPAD_QUAD3_TOOLTIP,
        GAMEPAD_RIGHT_TOOLTIP,
    }

    for _, tooltip in ipairs(tooltips) do
        ZO_PostHook(GAMEPAD_TOOLTIPS:GetTooltip(tooltip), "AddItemCombinationText", Tooltip_AddCovetousCountess_After)
    end
end

EVENT_MANAGER:RegisterForEvent("TooltipCountessAndCrow", EVENT_ADD_ON_LOADED, OnAddonLoaded)
