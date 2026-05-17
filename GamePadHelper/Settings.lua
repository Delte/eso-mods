local GPH_PANEL_ID = 9106
local GPH_CATEGORY_NAME = "|c3399FFGPH|r Settings"
local GPH_RELOAD_DIALOG = "GPH_RELOADUI_CONFIRM"
local gphLootReloadPending = false
local gphExitHookRegistered = false
local gphBackOverrideActive = false
local TRAIT_COLOR_LEGEND = "\n\nTrait color meaning:\n|c2DC50EGreen|r: Only copy with this trait you have access\n|cFFFF00Yellow|r: Another copy with the same trait exists in your inventory\n|cFF4444Red|r: Another copy with the same trait exists in your bank\n|cFFFFFFWhite|r: Equipped item uses ESO's default magnifying glass icon; details are shown in the tooltip"

local function GetSavedVars()
    return _G["GamePadHelper_SavedVars"]
end

local function GetBoolSetting(key, defaultValue)
    local sv = GetSavedVars()
    if not sv then
        return defaultValue or false
    end
    local value = sv[key]
    if value == nil then
        return defaultValue or false
    end
    return value
end

local function SetSetting(key, value)
    local sv = GetSavedVars()
    if sv then
        sv[key] = value
    end
end

local function BuildCheckbox(text, tooltip, key)
    return {
        panel = GPH_PANEL_ID,
        system = GPH_PANEL_ID,
        controlType = OPTIONS_CHECKBOX,
        text = text,
        gamepadTextOverride = text,
        tooltipText = tooltip,
        gamepadCustomTooltipFunction = function(tooltipControl)
            GAMEPAD_TOOLTIPS:LayoutTextBlockTooltip(tooltipControl, tooltip)
        end,
        GetSettingOverride = function()
            return GetBoolSetting(key, false)
        end,
        SetSettingOverride = function(_, value)
            SetSetting(key, value)
        end,
    }
end

local function BuildCheckboxCustom(text, tooltip, getFunc, setFunc, header, disabledFunc)
    return {
        panel = GPH_PANEL_ID,
        system = GPH_PANEL_ID,
        controlType = OPTIONS_CHECKBOX,
        text = text,
        gamepadTextOverride = text,
        header = header,
        disabled = disabledFunc,
        gamepadIsEnabledCallback = disabledFunc and function() return not disabledFunc() end or nil,
        tooltipText = tooltip,
        gamepadCustomTooltipFunction = function(tooltipControl)
            GAMEPAD_TOOLTIPS:LayoutTextBlockTooltip(tooltipControl, tooltip)
        end,
        GetSettingOverride = function()
            return getFunc()
        end,
        SetSettingOverride = function(_, value)
            setFunc(value)
        end,
    }
end

local function BuildSlider(text, tooltip, minValue, maxValue, stepValue, defaultValue, getFunc, setFunc, header, disabledFunc)
    return {
        panel = GPH_PANEL_ID,
        system = GPH_PANEL_ID,
        controlType = OPTIONS_SLIDER,
        text = text,
        gamepadTextOverride = text,
        header = header,
        disabled = disabledFunc,
        tooltipText = tooltip,
        minValue = minValue,
        maxValue = maxValue,
        showValue = true,
        showValueMin = minValue,
        showValueMax = maxValue,
        default = defaultValue,
        valueFormat = "%d",
        gamepadValueStepPercent = ((stepValue and stepValue > 0) and ((stepValue / (maxValue - minValue)) * 100)) or nil,
        gamepadCustomTooltipFunction = function(tooltipControl)
            GAMEPAD_TOOLTIPS:LayoutTextBlockTooltip(tooltipControl, tooltip)
        end,
        GetSettingOverride = function()
            return getFunc()
        end,
        SetSettingOverride = function(_, value)
            setFunc(tonumber(value) or minValue)
        end,
    }
end

local function BuildInvoke(text, tooltip, callback)
    return {
        panel = GPH_PANEL_ID,
        system = GPH_PANEL_ID,
        controlType = OPTIONS_INVOKE_CALLBACK,
        text = text,
        gamepadTextOverride = text,
        tooltipText = tooltip,
        gamepadCustomTooltipFunction = function(tooltipControl)
            GAMEPAD_TOOLTIPS:LayoutTextBlockTooltip(tooltipControl, tooltip)
        end,
        callback = callback,
    }
end

local function ShowReloadPrompt(onConfirm, onCancel)
    if ESO_Dialogs[GPH_RELOAD_DIALOG] then
        ZO_Dialogs_ShowGamepadDialog(GPH_RELOAD_DIALOG, {
            onConfirm = onConfirm,
            onCancel = onCancel,
        })
    elseif ESO_Dialogs["LIBGAMEPAD_RELOADUI_CONFIRM"] then
        ZO_Dialogs_ShowGamepadDialog("LIBGAMEPAD_RELOADUI_CONFIRM")
    else
        ZO_Alert(UI_ALERT_CATEGORY_ALERT, nil, "Reload UI required.")
        if onCancel then
            onCancel()
        end
    end
end

local function MarkLootReloadPending()
    gphLootReloadPending = true
end

local function EnsureReloadDialog()
    if ESO_Dialogs[GPH_RELOAD_DIALOG] then
        return
    end

    -- Dedicated confirmation used by both "Reload UI" button and deferred loot changes.
    ESO_Dialogs[GPH_RELOAD_DIALOG] = {
        gamepadInfo = { dialogType = GAMEPAD_DIALOGS.BASIC },
        title = { text = "Reload UI Required" },
        mainText = { text = "Changes require a UI reload. Reload now?" },
        buttons = {
            {
                text = SI_DIALOG_CONFIRM,
                callback = function(dialog)
                    local onConfirm = dialog.data and dialog.data.onConfirm
                    if onConfirm then
                        onConfirm()
                    else
                        ReloadUI()
                    end
                end,
            },
            {
                text = SI_DIALOG_CANCEL,
                callback = function(dialog)
                    local onCancel = dialog.data and dialog.data.onCancel
                    if onCancel then
                        onCancel()
                    end
                end,
            },
        },
    }
end

local function BuildSettingsData()
    local data = {}
    local nextSettingId = 1

    -- Each row must have a stable settingId for ZO_SharedOptions lookups.
    local function add(row)
        row.settingId = nextSettingId
        nextSettingId = nextSettingId + 1
        data[#data + 1] = row
    end

    add(BuildInvoke("Reload UI", "Reloads the user interface. Required after changing loot offset settings.", function()
        ShowReloadPrompt()
    end))

    add(BuildCheckboxCustom("Fishing Module", "Vibrates the controller when a fish bites, shows a 'Reel in!' center-screen alert, and automatically equips the correct bait for the water type (lake, river, saltwater, foul).", function()
        return GetBoolSetting("fishingEnabled", false)
    end, function(v)
        SetSetting("fishingEnabled", v)
    end, "Fishing"))

    add(BuildCheckbox("Alternative Baits", "When in stock, prefer the higher-quality bait for each water type (e.g. Lake Minnow over Lake Guts). Falls back to the standard bait if the alternative runs out.", "fishingAlternativeBaits"))

    add(BuildCheckboxCustom("Auto Repair", "Repairs all damaged equipped gear automatically when you open a merchant. Gold is deducted at the standard repair cost.", function()
        return GetBoolSetting("autoRepairEnabled", false)
    end, function(v)
        SetSetting("autoRepairEnabled", v)
    end, "Automation"))

    add(BuildCheckbox("Auto Weapon Charge", "Recharges weapons using the highest-level filled soul gem in your backpack when enchantment charge drops below the threshold, triggered after leaving combat.", "autoChargeEnabled"))
    add(BuildSlider("Charge Threshold %", "Recharge weapons when enchantment charge drops below this percentage. Default is 25%.", 5, 95, 5, 25, function()
        local sv = GetSavedVars()
        return (sv and sv.autoChargeThreshold) or 25
    end, function(v)
        SetSetting("autoChargeThreshold", tonumber(v) or 25)
    end, nil, function()
        return not GetBoolSetting("autoChargeEnabled", false)
    end))
    add(BuildCheckbox("Antiquarian's Eye", "Automatically equips the Antiquarian's Eye quickslot and activates it while scrying. Returns to your previous quickslot when done. Disabled in PvP zones and dungeons.", "antiquariansEyeEnabled"))
    add(BuildCheckbox("Teleporter", "Adds fast-travel options to the world map for wayshrines and owned homes. Player houses offer a choice between entering inside or travelling to the exterior.", "teleporterEnabled"))

    add(BuildCheckboxCustom("Set Destination on Show Map", "Places a waypoint marker at the selected location when you use 'Show on Map' from the search results.", function()
        return GetBoolSetting("mapSearchSetDestination", true)
    end, function(v)
        SetSetting("mapSearchSetDestination", v)
    end, "Map Search"))

    add(BuildCheckboxCustom("Announce Teleport Destination", "Shows a small on-screen announcement after arriving at the destination, confirming the location name and reminding you to check the map for the destination pin.", function()
        return GetBoolSetting("mapSearchNarratePostTeleport", true)
    end, function(v)
        SetSetting("mapSearchNarratePostTeleport", v)
    end))

    add(BuildCheckboxCustom("Dungeon Finder Enhancement", "Shows the active Undaunted pledge quest name next to matching dungeons in the dungeon finder, making it easy to identify which dungeons count for today's pledges.", function()
        return GetBoolSetting("dungeonFinderEnabled", false)
    end, function(v)
        SetSetting("dungeonFinderEnabled", v)
    end, "UI Enhancements"))

    add(BuildCheckbox("Hide Low Level Recipes", "Hides provisioning recipes whose food or drink buff only applies below CP160, keeping the recipe list focused on end-game content.", "showLowLevelRecipes"))

    add(BuildCheckboxCustom("Tooltip Traits", "Shows a research status icon in item tooltips to indicate whether the item's trait can still be researched." .. TRAIT_COLOR_LEGEND, function()
        return GetBoolSetting("tooltipTraitEnabled", false)
    end, function(v)
        SetSetting("tooltipTraitEnabled", v)
    end, "Tooltips & UI"))

    add(BuildCheckbox("Tooltip Price", "Shows vendor sell value and market price (from TTC, TSC, or LibPriceCache if installed) in item tooltips. Also displays material costs in crafting panels.", "tooltipPriceEnabled"))
    add(BuildCheckbox("Gear Comparison", "Displays a stat comparison between the hovered item and your currently equipped gear in the tooltip, showing the difference for each attribute.", "gearComparisonEnabled"))
    add(BuildCheckbox("Inventory Traits", "Shows a research status icon on items in your inventory." .. TRAIT_COLOR_LEGEND, "inventoryTraitEnabled"))
    add(BuildCheckbox("Inventory Covetous Countess", "Marks items requested by the Covetous Countess daily writ with a highlight icon in your inventory for quick identification.", "inventoryCovetousCountessEnabled"))
    add(BuildCheckbox("Overview Panel", "Shows a summary of active research timers, pending survey maps, available antiquities, and treasure maps in the gamepad main menu sidebar.", "overviewEnabled"))
    add(BuildCheckbox("Tooltip Poison Info", "Shows the active poison's name, application chance, and effect duration in the weapon tooltip.", "tooltipPoisonEnabled"))
    add(BuildCheckboxCustom("Tooltip Font Changes", "Increases the font size for item descriptions, flavor text, and other tooltip fields. Useful when playing on a TV or large display.", function()
        return GetBoolSetting("tooltipFontEnabled", false)
    end, function(v)
        SetSetting("tooltipFontEnabled", v)
        if v then
            if _G["TooltipFont_Apply"] then
                _G["TooltipFont_Apply"]()
            end
        else
            if _G["TooltipFont_Revert"] then
                _G["TooltipFont_Revert"]()
            end
        end
    end))
    add(BuildCheckbox("Tooltip Enchantments", "Shows the enchantment name and remaining charge percentage in tooltips for weapons and armor.", "tooltipEnchantmentEnabled"))

    add(BuildCheckboxCustom("Enable Loot Offset", "Moves the loot history panel upward so it does not overlap the chat box. Adjust the amount with the slider below.\n\n|cFFAA00Reload UI required after changing this setting.|r", function()
        return GetBoolSetting("lootOffsetEnabled", false)
    end, function(v)
        SetSetting("lootOffsetEnabled", v)
        MarkLootReloadPending()
    end, "Loot", function()
        return IsConsoleUI and IsConsoleUI()
    end))

    -- UI shows -350..350, but saved value stays compatible with loot module (0..700 where 350 is midpoint).
    add(BuildSlider("Loot Offset Amount", "Controls how far the loot panel is shifted. Negative values move it down, positive values move it up. 0 is the default position.\n\n|cFFAA00Reload UI required after changing this setting.|r", -350, 350, 10, 0, function()
        local sv = GetSavedVars()
        local internalValue = (sv and sv.lootOffset) or 350
        return internalValue - 350
    end, function(v)
        local sv = GetSavedVars()
        if not sv then return end
        sv.lootOffset = zo_clamp((tonumber(v) or 0) + 350, 0, 700)
        MarkLootReloadPending()
    end, nil, function()
        local sv = GetSavedVars()
        local isConsole = IsConsoleUI and IsConsoleUI()
        return isConsole or not (sv and sv.lootOffsetEnabled)
    end))

    return data
end

local function RegisterSharedOptions(settingsData)
    if not ZO_SharedOptions or not ZO_SharedOptions.AddTableToPanel then
        return
    end

    local shared = {
        [GPH_PANEL_ID] = {},
    }

    for _, optionData in ipairs(settingsData) do
        local copy = ZO_ShallowTableCopy(optionData)
        shared[GPH_PANEL_ID][optionData.settingId] = copy
    end

    ZO_SharedOptions.AddTableToPanel(GPH_PANEL_ID, shared)
end

local function RegisterCategory()
    if not GAMEPAD_OPTIONS then
        return false
    end

    if not GAMEPAD_SETTINGS_DATA then
        return false
    end

    if GAMEPAD_SETTINGS_DATA[GPH_PANEL_ID] == nil then
        GAMEPAD_SETTINGS_DATA[GPH_PANEL_ID] = BuildSettingsData()
    end

    RegisterSharedOptions(GAMEPAD_SETTINGS_DATA[GPH_PANEL_ID])

    local categoryData = ZO_GamepadEntryData:New(GPH_CATEGORY_NAME, "/esoui/art/options/gamepad/gp_options_addons.dds")
    categoryData.sortOrder = 106
    categoryData.panelId = GPH_PANEL_ID
    categoryData:SetIconTintOnSelection(true)
    categoryData.callback = function()
        GAMEPAD_OPTIONS.currentCategory = GPH_PANEL_ID
        SCENE_MANAGER:Push("gamepad_options_panel")
    end

    GAMEPAD_OPTIONS:RegisterCustomCategory(categoryData)

    return true
end

local function OpenSettings()
    if not GAMEPAD_OPTIONS then
        return
    end

    GAMEPAD_OPTIONS.currentCategory = GPH_PANEL_ID
    SCENE_MANAGER:Push("gamepad_options_panel")
end

local function HookInvokeCallback()
    -- OPTIONS_INVOKE_CALLBACK rows in custom systems need explicit routing in gamepad options.
    ZO_PreHook("ZO_Options_InvokeCallback", function(control)
        local data = control and control.data
        if data and data.system == GPH_PANEL_ID and data.panel == GPH_PANEL_ID and data.callback then
            data.callback(control)
            return true
        end
        return false
    end)
end

local function InstallBackOverride()
    if gphBackOverrideActive or not GAMEPAD_OPTIONS then
        return
    end

    gphBackOverrideActive = true
    GAMEPAD_OPTIONS.overrideBackName = GetString(SI_GAMEPAD_BACK_OPTION)
    GAMEPAD_OPTIONS.overrideBackCallback = function()
        if GAMEPAD_OPTIONS.currentCategory == GPH_PANEL_ID and gphLootReloadPending then
            ShowReloadPrompt(function()
                ReloadUI()
            end, function()
                gphLootReloadPending = false
                SCENE_MANAGER:HideCurrentScene()
            end)
            return
        end

        gphLootReloadPending = false
        SCENE_MANAGER:HideCurrentScene()
    end
end

local function ClearBackOverride()
    if not gphBackOverrideActive or not GAMEPAD_OPTIONS then
        return
    end

    GAMEPAD_OPTIONS.overrideBackCallback = nil
    GAMEPAD_OPTIONS.overrideBackName = nil
    gphBackOverrideActive = false
end

local function InitializeGamepadSettings()
    EnsureReloadDialog()
    HookInvokeCallback()

    local tryRegisterAttempts = 0
    local function TryRegister()
        if RegisterCategory() then
            return
        end
        tryRegisterAttempts = tryRegisterAttempts + 1
        if tryRegisterAttempts < 10 then
            zo_callLater(TryRegister, 1000)
        end
    end

    TryRegister()

    if not gphExitHookRegistered then
        local panelScene = SCENE_MANAGER and SCENE_MANAGER:GetScene("gamepad_options_panel")
        if panelScene then
            panelScene:RegisterCallback("StateChange", function(...)
                local newState = select(2, ...) or select(1, ...)
                if newState == SCENE_SHOWING or newState == "showing" then
                    if GAMEPAD_OPTIONS and GAMEPAD_OPTIONS.currentCategory == GPH_PANEL_ID then
                        InstallBackOverride()
                    end
                elseif newState == SCENE_HIDING or newState == SCENE_HIDDEN or newState == "hiding" or newState == "hidden" then
                    ClearBackOverride()
                end
            end)
            gphExitHookRegistered = true
        end
    end

    SLASH_COMMANDS["/gph"] = function()
        OpenSettings()
    end
end

EVENT_MANAGER:RegisterForEvent("Settings_Init", EVENT_PLAYER_ACTIVATED, function()
    EVENT_MANAGER:UnregisterForEvent("Settings_Init", EVENT_PLAYER_ACTIVATED)
    InitializeGamepadSettings()
end)
