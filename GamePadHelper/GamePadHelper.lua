local ADDON_NAME = "GamePadHelper"
local ADDON_VERSION = 1.04

-- Settings window variables
local settingsWindow = nil
local settingsCreated = false

-- Ensure ESO API compatibility
if GetAPIVersion() < 101047 then
    d("[" .. ADDON_NAME .. "] ESO API version too old. Requires API 101047 or higher.")
    return
end

-- Default saved variables
local defaults = {
    fishingEnabled = true,
    fishingAlternativeBaits = true,
    autoRepairEnabled = true,
    autoChargeEnabled = true,
    antiquariansEyeEnabled = true,
    dungeonFinderEnabled = true,
    provisioningEnabled = true,
    lootOffsetEnabled = true,
    lootOffset = 350,
    showLowLevelRecipes = false,
}

-- Saved variables
local savedVars


-- Create settings window
local function CreateSettingsWindow()
    -- Check if window already exists
    if settingsWindow and not settingsWindow:IsControlHidden() then
        return -- Window already exists and is visible
    end

    settingsCreated = true

    -- Create main window if it doesn't exist
    if not settingsWindow then
        settingsWindow = WINDOW_MANAGER:CreateTopLevelWindow("GamePadHelperSettingsWindow")
        settingsWindow:SetDimensions(400, 500)
        settingsWindow:SetAnchor(CENTER, GuiRoot, CENTER, 0, 0)
        settingsWindow:SetMouseEnabled(true)
        settingsWindow:SetMovable(true)
        settingsWindow:SetHidden(true)
        settingsWindow:SetClampedToScreen(true)
        settingsWindow:SetDrawTier(DT_HIGH)
        settingsWindow:SetDrawLayer(DL_CONTROLS)
        settingsWindow:SetKeyboardEnabled(true)

        -- Add ESC key handler to close window
        settingsWindow:SetHandler("OnKeyUp", function(self, key, ctrl, alt, shift)
            if key == KEY_ESCAPE then
                self:SetHidden(true)
                -- Switch back to game mode when window is closed
                SetGameCameraUIMode(false)
                -- Unregister as top-level window when closed
                if SCENE_MANAGER and SCENE_MANAGER.HideTopLevel then
                    SCENE_MANAGER:HideTopLevel(self)
                end
                return true
            end
            return false
        end)

        -- Create background using ESO's standard backdrop template
        local bg = WINDOW_MANAGER:CreateControlFromVirtual("GamePadHelperSettingsWindowBG", settingsWindow, "ZO_DefaultBackdrop")
        bg:SetAnchorFill(settingsWindow)

        -- Create title
        local title = WINDOW_MANAGER:CreateControl("GamePadHelperSettingsWindowTitle", settingsWindow, CT_LABEL)
        title:SetAnchor(TOP, settingsWindow, TOP, 0, 20)
        title:SetFont("ZoFontWinH2")
        title:SetText("GamePadHelper Settings")
        title:SetColor(0.5, 0.8, 1, 1)

        -- Create scroll container using ESO's standard scroll template
        local scrollContainer = WINDOW_MANAGER:CreateControlFromVirtual("GamePadHelperSettingsWindowScrollContainer", settingsWindow, "ZO_ScrollContainer")
        scrollContainer:SetAnchor(TOPLEFT, settingsWindow, TOPLEFT, 20, 60)
        scrollContainer:SetAnchor(BOTTOMRIGHT, settingsWindow, BOTTOMRIGHT, -20, -60)

        local scrollChild = scrollContainer:GetNamedChild("ScrollChild")
        if not scrollChild then
            scrollChild = WINDOW_MANAGER:CreateControl("GamePadHelperSettingsWindowScrollChild", scrollContainer, CT_CONTROL)
            scrollChild:SetAnchor(TOPLEFT, scrollContainer, TOPLEFT, 0, 0)
            scrollChild:SetResizeToFitPadding(0, 0)
        end

        -- Set the scroll child properly
        local scroll = scrollContainer.scroll or scrollContainer:GetNamedChild("Scroll")
        if scroll and scroll.SetScrollChild then
            scroll:SetScrollChild(scrollChild)
        end
        scrollChild:SetResizeToFitPadding(0, 0)

        local scroll = scrollContainer.scroll or scrollContainer:GetNamedChild("Scroll") or scrollContainer
        if scroll and scroll.SetScrollChild then
            scroll:SetScrollChild(scrollChild)
        end

        -- Create settings controls
        local yOffset = 0

        local function AddCheckbox(parent, label, settingKey, tooltip)
            -- Create checkbox container
            local checkboxContainer = WINDOW_MANAGER:CreateControl("GamePadHelperSettingsCheckboxContainer_" .. settingKey, parent, CT_CONTROL)
            checkboxContainer:SetAnchor(TOPLEFT, parent, TOPLEFT, 0, yOffset)
            checkboxContainer:SetDimensions(300, 30)

            -- Use ESO's standard checkbox template
            local checkbox = WINDOW_MANAGER:CreateControlFromVirtual("GamePadHelperSettingsCheckbox_" .. settingKey, checkboxContainer, "ZO_CheckButton")
            checkbox:SetAnchor(TOPLEFT, checkboxContainer, TOPLEFT, 0, 0)
            checkbox:SetDimensions(24, 24)

            -- Create label next to checkbox
            local labelControl = WINDOW_MANAGER:CreateControl("GamePadHelperSettingsCheckboxLabel_" .. settingKey, checkboxContainer, CT_LABEL)
            labelControl:SetAnchor(LEFT, checkbox, RIGHT, 10, 0)
            labelControl:SetFont("ZoFontWinT1")
            labelControl:SetText(label)
            labelControl:SetColor(1, 1, 1, 1)

            -- Set the checkbox state
            ZO_CheckButton_SetCheckState(checkbox, savedVars[settingKey])

            -- Set up the click handler
            checkbox:SetHandler("OnClicked", function(self)
                local newState = not savedVars[settingKey]
                savedVars[settingKey] = newState
                ZO_CheckButton_SetCheckState(self, newState)
            end)

            -- Add tooltip if provided
            if tooltip and tooltip ~= "" then
                checkbox:SetHandler("OnMouseEnter", function(self)
                    InitializeTooltip(InformationTooltip, self, TOP, 0, 5)
                    SetTooltipText(InformationTooltip, tooltip)
                end)
                checkbox:SetHandler("OnMouseExit", function(self)
                    ClearTooltip(InformationTooltip)
                end)
            end

            yOffset = yOffset + 35
            return checkbox
        end

        -- Add checkboxes for each setting
        AddCheckbox(scrollChild, "Fishing Module", "fishingEnabled", "Enable/disable fishing features")
        AddCheckbox(scrollChild, "Alternative Baits", "fishingAlternativeBaits", "Use alternative bait selection")
        AddCheckbox(scrollChild, "Auto Repair", "autoRepairEnabled", "Automatically repair equipment")
        AddCheckbox(scrollChild, "Auto Charge", "autoChargeEnabled", "Automatically charge weapons")
        AddCheckbox(scrollChild, "Auto Antiquarian's Eye", "antiquariansEyeEnabled", "Automatically use Antiquarian's Eye")
        AddCheckbox(scrollChild, "Dungeon Finder", "dungeonFinderEnabled", "Enhanced dungeon finder features")
        AddCheckbox(scrollChild, "Provisioning Filter", "provisioningEnabled", "Filter provisioning recipes")
        AddCheckbox(scrollChild, "Loot Offset", "lootOffsetEnabled", "Offset loot window for gamepad")

        -- Add loot offset slider
        local sliderLabel = WINDOW_MANAGER:CreateControl("GamePadHelperSettingsWindowLootOffsetLabel", scrollChild, CT_LABEL)
        sliderLabel:SetAnchor(TOPLEFT, scrollChild, TOPLEFT, 0, yOffset)
        sliderLabel:SetFont("ZoFontWinT1")
        sliderLabel:SetText("Loot Offset Value: " .. savedVars.lootOffset)

        local slider = WINDOW_MANAGER:CreateControlFromVirtual("GamePadHelperSettingsWindowLootOffsetSlider", scrollChild, "ZO_Slider")
        slider:SetAnchor(TOPLEFT, scrollChild, TOPLEFT, 0, yOffset + 25)
        slider:SetDimensions(300, 20)
        slider:SetMinMax(100, 600)
        slider:SetValue(savedVars.lootOffset)
        slider:SetValueStep(10)

        slider:SetHandler("OnValueChanged", function(self, value)
            savedVars.lootOffset = value
            sliderLabel:SetText("Loot Offset Value: " .. math.floor(value))
        end)

        yOffset = yOffset + 60

        -- Create button container
        local buttonContainer = WINDOW_MANAGER:CreateControl("GamePadHelperSettingsWindowButtonContainer", settingsWindow, CT_CONTROL)
        buttonContainer:SetAnchor(BOTTOM, settingsWindow, BOTTOM, 0, -20)
        buttonContainer:SetDimensions(220, 30)

        -- Create close button
        local closeButton = WINDOW_MANAGER:CreateControlFromVirtual("GamePadHelperSettingsWindowCloseButton", buttonContainer, "ZO_DefaultButton")
        closeButton:SetAnchor(RIGHT, buttonContainer, RIGHT, 0, 0)
        closeButton:SetDimensions(100, 30)
        closeButton:SetText("Close")
        closeButton:SetClickSound(SOUNDS.DEFAULT_CLICK)
        closeButton:SetHandler("OnClicked", function()
            settingsWindow:SetHidden(true)
        end)

        -- Create reset button
        local resetButton = WINDOW_MANAGER:CreateControlFromVirtual("GamePadHelperSettingsWindowResetButton", buttonContainer, "ZO_DefaultButton")
        resetButton:SetAnchor(LEFT, buttonContainer, LEFT, 0, 0)
        resetButton:SetDimensions(100, 30)
        resetButton:SetText("Reset to Default")
        resetButton:SetClickSound(SOUNDS.DEFAULT_CLICK)
        resetButton:SetHandler("OnClicked", function()
            -- Reset all settings to defaults
            for key, value in pairs(defaults) do
                savedVars[key] = value
            end

            -- Update existing controls if window exists, otherwise recreate
            if settingsWindow then
                -- Update all checkboxes with new values
                local checkboxNames = {
                    "GamePadHelperSettingsCheckbox_fishingEnabled",
                    "GamePadHelperSettingsCheckbox_fishingAlternativeBaits",
                    "GamePadHelperSettingsCheckbox_autoRepairEnabled",
                    "GamePadHelperSettingsCheckbox_autoChargeEnabled",
                    "GamePadHelperSettingsCheckbox_antiquariansEyeEnabled",
                    "GamePadHelperSettingsCheckbox_dungeonFinderEnabled",
                    "GamePadHelperSettingsCheckbox_provisioningEnabled",
                    "GamePadHelperSettingsCheckbox_lootOffsetEnabled"
                }

                for _, checkboxName in ipairs(checkboxNames) do
                    local checkbox = WINDOW_MANAGER:GetControlByName(checkboxName)
                    if checkbox then
                        -- Extract setting key from checkbox name
                        local settingKey = checkboxName:match("GamePadHelperSettingsCheckbox_(.+)")
                        if settingKey and savedVars[settingKey] ~= nil then
                            ZO_CheckButton_SetCheckState(checkbox, savedVars[settingKey])
                        end
                    end
                end

                -- Update the slider
                local slider = WINDOW_MANAGER:GetControlByName("GamePadHelperSettingsWindowLootOffsetSlider")
                if slider then
                    slider:SetValue(savedVars.lootOffset)
                    local sliderLabel = WINDOW_MANAGER:GetControlByName("GamePadHelperSettingsWindowLootOffsetLabel")
                    if sliderLabel then
                        sliderLabel:SetText("Loot Offset Value: " .. savedVars.lootOffset)
                    end
                end

                d("|c3399FF[GamePadHelper]|r Settings reset to defaults")
            else
                -- Recreate window if it doesn't exist
                ShowSettingsWindow()
                d("|c3399FF[GamePadHelper]|r Settings reset to defaults")
            end
        end)


        -- Set scroll child height
        scrollChild:SetHeight(yOffset)
    end
end

-- Show settings window
local function ShowSettingsWindow()
    if not settingsWindow then
        CreateSettingsWindow()
    end

    if settingsWindow:IsControlHidden() then
        settingsWindow:SetHidden(false)
    end

    -- Switch to UI mode to allow mouse interaction with the window
    SetGameCameraUIMode(true)

    -- Register as top-level window for proper focus (do this before showing)
    if SCENE_MANAGER and SCENE_MANAGER.RegisterTopLevel then
        SCENE_MANAGER:RegisterTopLevel(settingsWindow, LOCKS_UI_MODE)
        SCENE_MANAGER:ShowTopLevel(settingsWindow)
    end

    -- Ensure mouse input is enabled for pointer interaction
    settingsWindow:SetMouseEnabled(true)
    
    -- Bring window to top for mouse focus
    settingsWindow:BringWindowToTop()
    
    -- Ensure the window is properly layered for mouse interaction
    settingsWindow:SetDrawTier(DT_HIGH)
    
    -- Ensure all child controls are also mouse enabled
    local function EnableMouseForChildren(control)
        if control.SetMouseEnabled then
            control:SetMouseEnabled(true)
        end
        for i = 1, control:GetNumChildren() do
            local child = control:GetChild(i)
            if child then
                EnableMouseForChildren(child)
            end
        end
    end
    EnableMouseForChildren(settingsWindow)
end

-- Create the keybinding function that bindings.xml expects
function GAMEPADHELPER_SETTINGS()
    ShowSettingsWindow()
end

-- Load saved variables
local function OnAddonLoaded(event, addonName)
    if addonName ~= ADDON_NAME then return end
    EVENT_MANAGER:UnregisterForEvent(ADDON_NAME, EVENT_ADD_ON_LOADED)

    savedVars = ZO_SavedVars:NewAccountWide("GamePadHelperSavedVars", 1, nil, defaults)

    SLASH_COMMANDS["/gph"] = function()
        ShowSettingsWindow()
    end

    _G["GamePadHelper_SavedVars"] = savedVars

    ZO_CreateStringId("SI_BINDING_NAME_GAMEPADHELPER_SETTINGS", "Open GamePadHelper Settings")

    GAMEPADHELPER_SETTINGS = ShowSettingsWindow

    d("|c3399FF[GamePadHelper]|r v" .. ADDON_VERSION .. " loaded. Use |cDAA520/gph|r to open settings.")
end

EVENT_MANAGER:RegisterForEvent(ADDON_NAME, EVENT_ADD_ON_LOADED, OnAddonLoaded)