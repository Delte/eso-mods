local function InitializeSettings()
    local sv = _G["GamePadHelper_SavedVars"]
    if not sv then
        d("[GamePadHelper] SavedVars not found")
        return
    end

    local LAM = LibAddonMenu2
    if not LAM then
        d("[GamePadHelper] LibAddonMenu-2.0 not found")
        return
    end

    local panelData = {
        type = "panel",
        name = "GamePadHelper",
        displayName = "|c3399FFGamePadHelper|r",
        author = "olegbl, quelron",
        version = "1.05",
        registerForRefresh = true,
        registerForDefaults = true,
    }

    local optionsData = {
        {
            type = "button",
            name = "Reload UI",
            tooltip = "Reload the game UI to apply changes.",
            func = function() ReloadUI() end,
            width = "half",
        },
        -- Fishing
        {
            type = "header",
            name = "Fishing",
        },
        {
            type = "checkbox",
            name = "Fishing Module",
            tooltip = "Enable controller vibration feedback, 'Reel in!' alerts, and automatic bait selection by water type.",
            getFunc = function() return sv.fishingEnabled end,
            setFunc = function(v) sv.fishingEnabled = v end,
            default = true,
        },
        {
            type = "checkbox",
            name = "Alternative Baits",
            tooltip = "Fall back to alternative baits (Minnow/Guts, Chub/Worms) when the primary bait is unavailable.",
            getFunc = function() return sv.fishingAlternativeBaits end,
            setFunc = function(v) sv.fishingAlternativeBaits = v end,
            default = true,
            disabled = function() return not sv.fishingEnabled end,
        },
        -- Automation
        {
            type = "header",
            name = "Automation",
        },
        {
            type = "checkbox",
            name = "Auto Repair",
            tooltip = "Automatically repair all equipped items when you open a merchant store.",
            getFunc = function() return sv.autoRepairEnabled end,
            setFunc = function(v) sv.autoRepairEnabled = v end,
            default = true,
        },
        {
            type = "checkbox",
            name = "Auto Weapon Charge",
            tooltip = "Automatically recharge equipped weapons that drop below 25% charge after leaving combat.",
            getFunc = function() return sv.autoChargeEnabled end,
            setFunc = function(v) sv.autoChargeEnabled = v end,
            default = true,
        },
        {
            type = "checkbox",
            name = "Antiquarian's Eye",
            tooltip = "Automatically slot and activate the Antiquarian's Eye collectible when not in combat or moving.",
            getFunc = function() return sv.antiquariansEyeEnabled end,
            setFunc = function(v) sv.antiquariansEyeEnabled = v end,
            default = true,
        },
        {
            type = "checkbox",
            name = "Teleporter",
            tooltip = "Enable teleport functionality in inventory and chat.",
            getFunc = function() return sv.teleporterEnabled end,
            setFunc = function(v) sv.teleporterEnabled = v end,
            default = true,
        },
        -- UI Enhancements
        {
            type = "header",
            name = "UI Enhancements",
        },
        {
            type = "checkbox",
            name = "Dungeon Finder Enhancement",
            tooltip = "Show pledge quest names inside the dungeon finder.",
            getFunc = function() return sv.dungeonFinderEnabled end,
            setFunc = function(v) sv.dungeonFinderEnabled = v end,
            default = true,
        },
        {
            type = "checkbox",
            name = "Hide Low Level Recipes",
            tooltip = "Hide recipes under CP160 in the provisioning panel.",
            getFunc = function() return sv.showLowLevelRecipes end,
            setFunc = function(v) sv.showLowLevelRecipes = v end,
            default = true,
        },
        -- Tooltips & UI
        {
            type = "header",
            name = "Tooltips & UI",
        },
        {
            type = "checkbox",
            name = "Tooltip Traits",
            tooltip = "Show enhanced trait information with research icons in item tooltips.",
            getFunc = function() return sv.tooltipTraitEnabled end,
            setFunc = function(v) sv.tooltipTraitEnabled = v end,
            default = true,
        },
        {
            type = "checkbox",
            name = "Tooltip Price",
            tooltip = "Show item price information (including TTC data) in item tooltips.",
            getFunc = function() return sv.tooltipPriceEnabled end,
            setFunc = function(v) sv.tooltipPriceEnabled = v end,
            default = true,
        },
        {
            type = "checkbox",
            name = "Gear Comparison",
            tooltip = "Enable gear comparison features in inventory.",
            getFunc = function() return sv.gearComparisonEnabled end,
            setFunc = function(v) sv.gearComparisonEnabled = v end,
            default = true,
        },
        {
            type = "checkbox",
            name = "Inventory Traits",
            tooltip = "Show trait information in inventory tooltips.",
            getFunc = function() return sv.inventoryTraitEnabled end,
            setFunc = function(v) sv.inventoryTraitEnabled = v end,
            default = true,
        },
        {
            type = "checkbox",
            name = "Inventory Covetous Countess",
            tooltip = "Highlight Covetous Countess items in inventory.",
            getFunc = function() return sv.inventoryCovetousCountessEnabled end,
            setFunc = function(v) sv.inventoryCovetousCountessEnabled = v end,
            default = true,
        },
        {
            type = "checkbox",
            name = "Overview Panel",
            tooltip = "Enable the character overview panel enhancements.",
            getFunc = function() return sv.overviewEnabled end,
            setFunc = function(v) sv.overviewEnabled = v end,
            default = true,
        },
        {
            type = "checkbox",
            name = "Tooltip Poison Info",
            tooltip = "Show poison information in tooltips.",
            getFunc = function() return sv.tooltipPoisonEnabled end,
            setFunc = function(v) sv.tooltipPoisonEnabled = v end,
            default = true,
        },
        {
            type = "checkbox",
            name = "Tooltip Font Changes",
            tooltip = "Apply font size changes to tooltips.",
            getFunc = function() return sv.tooltipFontEnabled end,
            setFunc = function(v)
                sv.tooltipFontEnabled = v
                if v then
                    if _G["TooltipFont_Apply"] then _G["TooltipFont_Apply"]() end
                else
                    if _G["TooltipFont_Revert"] then _G["TooltipFont_Revert"]() end
                end
            end,
            default = true,
        },
        {
            type = "checkbox",
            name = "Tooltip Enchantments",
            tooltip = "Show enchantment information in tooltips.",
            getFunc = function() return sv.tooltipEnchantmentEnabled end,
            setFunc = function(v) sv.tooltipEnchantmentEnabled = v end,
            default = true,
        },
        -- Loot
        {
            type = "header",
            name = "Loot",
        },
        {
            type = "checkbox",
            name = "Enable Loot Offset",
            tooltip = "Shift the loot history panel upward so it does not overlap the chat box.",
            getFunc = function() return sv.lootOffsetEnabled end,
            setFunc = function(v)
                sv.lootOffsetEnabled = v
                if IsInGamepadPreferredMode() and ESO_Dialogs["LIBGAMEPAD_RELOADUI_CONFIRM"] then
                    ZO_Dialogs_ShowGamepadDialog("LIBGAMEPAD_RELOADUI_CONFIRM")
                end
            end,
            default = true,
            disabled = function() return IsConsoleUI() end,
            requiresReload = true,
        },
        {
            type = "slider",
            name = "Loot Offset Amount",
            tooltip = "How many pixels to shift the loot history panel. Default: 350.",
            min = 0,
            max = 700,
            step = 10,
            getFunc = function() return sv.lootOffset end,
            setFunc = function(v)
                sv.lootOffset = v
                if IsInGamepadPreferredMode() and ESO_Dialogs["LIBGAMEPAD_RELOADUI_CONFIRM"] then
                    ZO_Dialogs_ShowGamepadDialog("LIBGAMEPAD_RELOADUI_CONFIRM")
                end
            end,
            default = 350,
            disabled = function() return IsConsoleUI() or not sv.lootOffsetEnabled end,
            requiresReload = true,
        },
    }

    LAM:RegisterAddonPanel("GamePadHelperPanel", panelData)
    LAM:RegisterOptionControls("GamePadHelperPanel", optionsData)
end

EVENT_MANAGER:RegisterForEvent("GamePadHelper_SettingsInit", EVENT_ADD_ON_LOADED, function(event, addonName)
    if addonName ~= "GamePadHelper" then return end
    EVENT_MANAGER:UnregisterForEvent("GamePadHelper_SettingsInit", EVENT_ADD_ON_LOADED)
    InitializeSettings()
end)
