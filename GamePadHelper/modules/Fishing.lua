local cnt0 = 0

-- Bait constants
local BAIT_LAKE_GUTS          = 2
local BAIT_LAKE_GUTS_ITEMID   = 42870
local BAIT_LAKE_MINNOW        = 8
local BAIT_LAKE_MINNOW_ITEMID = 42876

local BAIT_FOUL_CRAWLERS      = 3
local BAIT_FOUL_CRAWLERS_ITEMID = 42871
local BAIT_FOUL_ROE           = 9
local BAIT_FOUL_ROE_ITEMID    = 42873

local BAIT_RIVER_INSECT       = 4
local BAIT_RIVER_INSECT_ITEMID = 42872
local BAIT_RIVER_SHAD         = 6
local BAIT_RIVER_SHAD_ITEMID  = 42874

local BAIT_SALTWATER_WORMS    = 5
local BAIT_SALTWATER_WORMS_ITEMID = 42869
local BAIT_SALTWATER_CHUB     = 7
local BAIT_SALTWATER_CHUB_ITEMID  = 42875

local FISHING_HOLES = {
    ["Lake Fishing Hole"]      = { reg = BAIT_LAKE_GUTS,       regId = BAIT_LAKE_GUTS_ITEMID,       alt = BAIT_LAKE_MINNOW,    altId = BAIT_LAKE_MINNOW_ITEMID },
    ["Saltwater Fishing Hole"] = { reg = BAIT_SALTWATER_WORMS, regId = BAIT_SALTWATER_WORMS_ITEMID, alt = BAIT_SALTWATER_CHUB, altId = BAIT_SALTWATER_CHUB_ITEMID },
    ["Foul Fishing Hole"]      = { reg = BAIT_FOUL_CRAWLERS,   regId = BAIT_FOUL_CRAWLERS_ITEMID,   alt = BAIT_FOUL_ROE,       altId = BAIT_FOUL_ROE_ITEMID },
    ["River Fishing Hole"]     = { reg = BAIT_RIVER_INSECT,    regId = BAIT_RIVER_INSECT_ITEMID,    alt = BAIT_RIVER_SHAD,     altId = BAIT_RIVER_SHAD_ITEMID },
}

local setBait = true

local function GetItemQuantity(itemId)
    local _, qnt  = GetItemInfo(BAG_VIRTUAL, itemId)
    local _, qnt2 = GetItemInfo(BAG_BACKPACK, itemId)
    if HasCraftBagAccess() then return (qnt + qnt2) else return qnt2 end
end

local function SelectFishingBait(interactableName)
    local savedVars = _G["GamePadHelper_SavedVars"]
    if not savedVars or not savedVars.fishingEnabled then return end

    local hole = FISHING_HOLES[interactableName]
    if not hole then return end

    if savedVars.fishingAlternativeBaits and GetItemQuantity(hole.altId) > 0 then
        SetFishingLure(hole.alt)
    else
        SetFishingLure(hole.reg)
    end
    setBait = false
end

local function startVibration2()
    SetGamepadVibration(3000, 0.99, 0.50, 1.00, 1.00, "Fishing")
    EVENT_MANAGER:UnregisterForUpdate("startVibration2")
end

local function startVibration()
    SetGamepadVibration(180, 0.50, 0.90, 1.00, 1.00, "Fishing")
    EVENT_MANAGER:RegisterForUpdate("startVibration2", 250, startVibration2)
end

local function onSlotUpdate(event, bagId, slotIndex, isNew)
    local savedVars = _G["GamePadHelper_SavedVars"]
    if not savedVars or not savedVars.fishingEnabled then
        return
    end

    local lure = GetFishingLure()
    local cnt = 0
    if lure then
        cnt = select(3, GetFishingLureInfo(lure))
    else
        cnt = 0
    end
    if (not isNew and (GetItemType(bagId, slotIndex) == ITEMTYPE_LURE) and (cnt0 - cnt == 1)) then
        startVibration()
        local action = GetGameCameraInteractableActionInfo()
        if action == GetString(SI_GAMECAMERAACTIONTYPE17) then
            local messageParams = CENTER_SCREEN_ANNOUNCE:CreateMessageParams(CSA_CATEGORY_MAJOR_TEXT, SOUNDS.BOOK_ACQUIRED)
            messageParams:SetText("|t32:32:/esoui/art/tutorial/gamepad/achievement_categoryicon_fishing.dds|t Reel in!")
            CENTER_SCREEN_ANNOUNCE:AddMessageWithParams(messageParams)
        end
    else
        SetGamepadVibration(0, 0, 0, 0, 0, "Fishing")
    end
    cnt0 = cnt
end

local function onLureCleared(event)
    local lure = GetFishingLure()
    if lure then
        cnt0 = select(3, GetFishingLureInfo(lure))
    end
end

local function onLureSet(event, lure)
    if lure then
        cnt0 = select(3, GetFishingLureInfo(lure))
    end
end

local function OnAddonLoaded(event, name)
    if name ~= "GamePadHelper" then return end
    EVENT_MANAGER:UnregisterForEvent("Fishing", EVENT_ADD_ON_LOADED)

    EVENT_MANAGER:RegisterForEvent("Fishing", EVENT_INVENTORY_SINGLE_SLOT_UPDATE, onSlotUpdate)
    EVENT_MANAGER:RegisterForEvent("Fishing", EVENT_FISHING_LURE_CLEARED, onLureCleared)
    EVENT_MANAGER:RegisterForEvent("Fishing", EVENT_FISHING_LURE_SET, onLureSet)

    ZO_PreHook(ZO_Reticle, "TryHandlingInteraction", function(interactionPossible, currentFrameTimeSeconds)
        local savedVars = _G["GamePadHelper_SavedVars"]
        if not savedVars or not savedVars.fishingEnabled then
            return
        end

        if interactionPossible then
            local action, interactableName, interactionBlocked, isOwned, additionalInteractInfo, context, contextLink, isCriminalInteract = GetGameCameraInteractableActionInfo()
            if additionalInteractInfo == ADDITIONAL_INTERACT_INFO_FISHING_NODE and setBait then
                SelectFishingBait(interactableName)
            end
        else
            setBait = true
        end
    end)

    local lure = GetFishingLure()
    if lure then
        cnt0 = select(3, GetFishingLureInfo(lure))
    end
end

EVENT_MANAGER:RegisterForEvent("Fishing", EVENT_ADD_ON_LOADED, OnAddonLoaded)
