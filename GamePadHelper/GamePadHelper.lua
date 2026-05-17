local ADDON_NAME = "GamePadHelper"
local ADDON_VERSION = 1.066
local ANNOUNCE_VERSION = 10607

-- Make ADDON_NAME globally accessible for submodules
_G["ADDON_NAME"] = ADDON_NAME

-- Ensure ESO API compatibility
if GetAPIVersion() < 101047 then
    d(zo_strformat(GetString(SI_GPH_API_TOO_OLD), ADDON_NAME, "101047"))
    return
end

local function IsConsole()
    return IsConsoleUI and IsConsoleUI() or false
end
_G["GamePadHelper_IsConsole"] = IsConsole

-- Default saved variables
local defaults = {
    fishingEnabled = true,
    fishingAlternativeBaits = true,
    autoRepairEnabled = true,
    autoChargeEnabled = true,
    autoChargeThreshold = 25,
    antiquariansEyeEnabled = true,
    dungeonFinderEnabled = true,
    teleporterEnabled = true,
    lootOffsetEnabled = true,
    lootOffset = 350,
    showLowLevelRecipes = false,
    tooltipTraitEnabled = true,
    tooltipPriceEnabled = true,
    gearComparisonEnabled = true,
    inventoryTraitEnabled = true,
    inventoryCovetousCountessEnabled = true,
    overviewEnabled = true,
    tooltipPoisonEnabled = true,
    tooltipFontEnabled = true,
    tooltipEnchantmentEnabled = true,
    lastAnnouncedVersion = 0,
}

local savedVars

local function ShowWhatsNewIfNeeded()
    if savedVars.lastAnnouncedVersion >= ANNOUNCE_VERSION then return end
    savedVars.lastAnnouncedVersion = ANNOUNCE_VERSION

    zo_callLater(function()
        if IsInGamepadPreferredMode() then
            local chat = KEYBOARD_CHAT_SYSTEM or CHAT_SYSTEM
            if chat then
                chat:AddMessage("|c3399FF[GamePadHelper]|r " .. GetString(SI_GPH_WHATS_NEW_TITLE))
                chat:AddMessage("|cFFFF00• " .. GetString(SI_GPH_WHATS_NEW_MULTILANG_LABEL) .. "|r " .. GetString(SI_GPH_WHATS_NEW_MULTILANG_BODY))
                chat:AddMessage("|cFFFF00• " .. GetString(SI_GPH_WHATS_NEW_MAPSEARCH_LABEL) .. "|r " .. GetString(SI_GPH_WHATS_NEW_MAPSEARCH_BODY))
            end
        else
            ZO_Dialogs_RegisterCustomDialog("GPH_WHATS_NEW", {
                title    = { text = GetString(SI_GPH_WHATS_NEW_TITLE) },
                mainText = { text = GetString(SI_GPH_WHATS_NEW_BODY) },
                buttons = {
                    {
                        text     = GetString(SI_GPH_WHATS_NEW_CONFIRM),
                        callback = function() end,
                    },
                },
            })
            ZO_Dialogs_ShowDialog("GPH_WHATS_NEW")
        end
    end, 3000)
end

local function OnAddonLoaded(event, addonName)
    if addonName ~= ADDON_NAME then return end
    EVENT_MANAGER:UnregisterForEvent(ADDON_NAME, EVENT_ADD_ON_LOADED)

    savedVars = ZO_SavedVars:NewAccountWide("GamePadHelperSavedVars", 1, nil, defaults)
    _G["GamePadHelper_SavedVars"] = savedVars

    EVENT_MANAGER:RegisterForEvent(ADDON_NAME, EVENT_PLAYER_ACTIVATED, function()
        EVENT_MANAGER:UnregisterForEvent(ADDON_NAME, EVENT_PLAYER_ACTIVATED)
        ShowWhatsNewIfNeeded()
    end)
end

EVENT_MANAGER:RegisterForEvent(ADDON_NAME, EVENT_ADD_ON_LOADED, OnAddonLoaded)
