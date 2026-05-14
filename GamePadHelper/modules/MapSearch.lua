-- ============================================================
-- GPH Map Search
-- Adds a "GPH Search" tab to the Gamepad World Map info panel.
-- Data: entirely from ESO in-game APIs (no hardcoded tables).
-- ============================================================

local TYPE_WAYSHRINE = 1
local TYPE_ZONE      = 2
local TYPE_POI       = 3

local ICON_WAYSHRINE = "/esoui/art/icons/poi/poi_wayshrine_complete.dds"
local ICON_ZONE      = "/esoui/art/icons/poi/poi_zonestory_complete.dds"
local ICON_POI       = "/esoui/art/icons/poi/poi_city_complete.dds"

local TYPE_NAMES = {
    [TYPE_WAYSHRINE] = "Wayshrine",
    [TYPE_ZONE]      = "Zone",
    [TYPE_POI]       = "Location",
}

-- ── state ────────────────────────────────────────────────────
local GPH_SEARCH_FRAGMENT     = nil
local GPH_SEARCH_TAB_INSERTED = false

local candidates  = nil
local results     = {}
local currentTerm = ""

local listObject       = nil
local editControl      = nil
local focusManager     = nil   -- ZO_GamepadFocus: navigates between search bar and list
local currentFocusIndex = 0   -- 1=search bar, 2=list; tracked here because GetFocus() returns nil inside callbacks

local sideTypeLabel        = nil
local sideLocationIcon     = nil
local sideNameLabel        = nil   -- shows candidate.name (large text, mislabelled ZoneName in XML)
local sideDescriptionLabel = nil

local searchBarBG        = nil
local searchBarHighlight = nil
local searchBarIcon      = nil

local keybindDescriptor = nil

-- ── search bar visual state ───────────────────────────────────
-- Called by OnFocusGained / OnFocusLost on the EditBox.
-- Only manages the semi-transparent BG; the white outline highlight
-- is handled by ZO_GamepadFocus via its FocusAlphaFadeAnimation.

function GPH_MapSearch_OnSearchFocused(focused)
    if searchBarBG then searchBarBG:SetHidden(not focused) end
end

-- ── keybind strip helper ──────────────────────────────────────
-- Call this after any focus change, once focusManager.index is settled.

local function UpdateKeybinds()
    if keybindDescriptor then
        KEYBIND_STRIP:UpdateKeybindButtonGroup(keybindDescriptor)
    end
end

-- ── side panel ────────────────────────────────────────────────

local function FindWayshrineInZone(zoneId)
    if not zoneId then return nil end
    for nodeIndex = 1, GetNumFastTravelNodes() do
        local known, _, _, _, _, _, typePOI, _, isLocked =
            GetFastTravelNodeInfo(nodeIndex)
        if known and not isLocked and typePOI == 1 then
            local zi      = select(1, GetFastTravelNodePOIIndicies(nodeIndex))
            local nZoneId = GetZoneId(zi)
            if nZoneId == zoneId or GetParentZoneId(nZoneId) == zoneId then
                return nodeIndex
            end
        end
    end
    return nil
end

local function UpdateSidePanel(candidate)
    if sideTypeLabel then
        sideTypeLabel:SetText(candidate and (TYPE_NAMES[candidate.type] or "") or "")
    end

    if sideLocationIcon then
        if candidate and candidate.icon then
            sideLocationIcon:SetTexture(candidate.icon)
            sideLocationIcon:SetHidden(false)
        else
            sideLocationIcon:SetHidden(true)
        end
    end

    -- Main name label (XML control is named ZoneName but we use it for the location name)
    if sideNameLabel then
        sideNameLabel:SetText(candidate and (candidate.name or "") or "")
    end

    if sideDescriptionLabel then
        local parts = {}
        if candidate then
            if candidate.type == TYPE_POI
               and candidate.zoneIndex and candidate.poiIndex then
                local _, poiDesc = GetPOIInfo(candidate.zoneIndex, candidate.poiIndex)
                if poiDesc and poiDesc ~= "" then
                    parts[#parts + 1] = poiDesc
                end
            end
            if candidate.zoneName and candidate.zoneName ~= "" then
                parts[#parts + 1] = candidate.zoneName
            end
        end
        local desc = table.concat(parts, "\n")
        if desc ~= "" then
            sideDescriptionLabel:SetText(desc)
            sideDescriptionLabel:SetHidden(false)
        else
            sideDescriptionLabel:SetText("")
            sideDescriptionLabel:SetHidden(true)
        end
    end
end

-- ── bookmarks ────────────────────────────────────────────────

local function MakeBookmarkKey(c)
    return c.type .. ":" .. tostring(c.nodeIndex or c.zoneId or "") .. ":" .. c.name
end

local function GetBookmarksArray()
    local sv = _G["GamePadHelper_SavedVars"]
    if not sv then return {} end
    local charName = GetUnitName("player")
    if not sv.mapSearchBookmarks then sv.mapSearchBookmarks = {} end
    if not sv.mapSearchBookmarks[charName] then sv.mapSearchBookmarks[charName] = {} end
    return sv.mapSearchBookmarks[charName]
end

local function IsBookmarked(c)
    local key = MakeBookmarkKey(c)
    for _, bm in ipairs(GetBookmarksArray()) do
        if bm.key == key then return true end
    end
    return false
end

-- ── data builder ─────────────────────────────────────────────

local function BuildCandidates()
    local list = {}

    -- zoneIndex → lowest mapIndex mapping, used so every candidate knows which
    -- map to switch to when centering the world map on it.
    local zoneToMap = {}
    for mi = 1, GetNumMaps() do
        local _, _, _, zi = GetMapInfoByIndex(mi)
        if zi and zi > 0 and not zoneToMap[zi] then
            zoneToMap[zi] = mi
        end
    end

    for nodeIndex = 1, GetNumFastTravelNodes() do
        local known, name, _, _, icon, _, typePOI, _, isLocked =
            GetFastTravelNodeInfo(nodeIndex)
        if name ~= "" and typePOI == 1 then
            local zoneIndex, poiIndex = GetFastTravelNodePOIIndicies(nodeIndex)
            local zoneId    = GetZoneId(zoneIndex)
            list[#list + 1] = {
                name       = name,
                searchName = name:lower(),
                type       = TYPE_WAYSHRINE,
                icon       = (icon and icon ~= "") and icon or ICON_WAYSHRINE,
                nodeIndex  = nodeIndex,
                zoneId     = zoneId,
                zoneIndex  = zoneIndex,
                poiIndex   = poiIndex,
                mapIndex   = zoneToMap[zoneIndex],
                zoneName   = GetZoneNameById(zoneId),
                known      = known,
                isLocked   = isLocked,
            }
        end
    end

    local seenZone = {}
    for mapIndex = 1, GetNumMaps() do
        local mapName, mapType, _, zoneIndex = GetMapInfoByIndex(mapIndex)
        if mapName ~= "" and zoneIndex and zoneIndex > 0 then
            local zoneId = GetZoneId(zoneIndex)
            if not seenZone[zoneId]
               and (mapType == MAPTYPE_ZONE or mapType == MAPTYPE_WORLD) then
                seenZone[zoneId] = true
                list[#list + 1] = {
                    name       = mapName,
                    searchName = mapName:lower(),
                    type       = TYPE_ZONE,
                    icon       = ICON_ZONE,
                    zoneId     = zoneId,
                    zoneIndex  = zoneIndex,
                    mapIndex   = mapIndex,
                    zoneName   = mapName,
                    known      = true,
                }
            end
        end
    end

    local seenPOI = {}
    for mapIndex = 1, GetNumMaps() do
        local _, _, _, zoneIndex = GetMapInfoByIndex(mapIndex)
        if zoneIndex and zoneIndex > 0 then
            local zoneId   = GetZoneId(zoneIndex)
            local zoneName = GetZoneNameById(zoneId)
            for poiIndex = 1, GetNumPOIs(zoneIndex) do
                local poiName = GetPOIInfo(zoneIndex, poiIndex)
                if poiName and poiName ~= "" then
                    local _, _, _, icon, _, _, isDiscovered =
                        GetPOIMapInfo(zoneIndex, poiIndex)
                    local uid = zoneIndex .. ":" .. poiIndex
                    if isDiscovered and not seenPOI[uid]
                       and icon and not icon:find("wayshrine") then
                        seenPOI[uid] = true
                        list[#list + 1] = {
                            name       = poiName,
                            searchName = poiName:lower(),
                            type       = TYPE_POI,
                            icon       = (icon ~= "") and icon or ICON_POI,
                            zoneId     = zoneId,
                            zoneIndex  = zoneIndex,
                            mapIndex   = zoneToMap[zoneIndex],
                            poiIndex   = poiIndex,
                            zoneName   = zoneName,
                            known      = true,
                        }
                    end
                end
            end
        end
    end

    return list
end

-- ── fuzzy search ──────────────────────────────────────────────

local function ScoreMatch(nameLower, termLower)
    if termLower == "" then return 1.0 end
    local ni, ti   = 1, 1
    local consec   = 0
    local score    = 0
    local nLen, tLen = #nameLower, #termLower

    while ni <= nLen and ti <= tLen do
        if nameLower:sub(ni, ni) == termLower:sub(ti, ti) then
            ti     = ti + 1
            consec = consec + 1
            score  = score + consec * consec
        else
            consec = 0
        end
        ni = ni + 1
    end

    if ti <= tLen then return 0 end
    if nameLower:sub(1, tLen) == termLower then score = score + 200 end
    if nameLower == termLower               then score = score + 500 end
    return score
end

local function RunSearch(term)
    if not candidates then candidates = BuildCandidates() end

    local termLower = term:lower()
    local scored = {}

    for i = 1, #candidates do
        local c = candidates[i]
        local s = ScoreMatch(c.searchName, termLower)
        if s > 0 then scored[#scored + 1] = { score = s, c = c } end
    end

    table.sort(scored, function(a, b)
        if a.score ~= b.score then return a.score > b.score end
        if a.c.type  ~= b.c.type  then return a.c.type < b.c.type end
        return a.c.searchName < b.c.searchName
    end)

    results = {}
    for i = 1, math.min(#scored, 60) do
        results[#results + 1] = scored[i].c
    end
end

-- ── teleport ──────────────────────────────────────────────────

local function TeleportToCandidate(c)
    SCENE_MANAGER:HideCurrentScene()

    local nodeIndex = c.nodeIndex
    if (not nodeIndex or c.type ~= TYPE_WAYSHRINE) and c.zoneId then
        nodeIndex = FindWayshrineInZone(c.zoneId)
    end

    if nodeIndex then
        FastTravelToNode(nodeIndex)
        return
    end

    if c.zoneId and BMU and BMU.createTable then
        local ok, tbl = pcall(BMU.createTable,
            { index = 6, fZoneId = c.zoneId, dontDisplay = true })
        if ok and tbl and tbl[1] then
            local entry = tbl[1]
            if entry.displayName and entry.displayName ~= "" then
                if IsFriend(entry.displayName) then
                    JumpToFriend(entry.displayName)
                else
                    JumpToGuildMember(entry.displayName)
                end
                return
            end
        end
    end

    ZO_Alert(UI_ALERT_CATEGORY_ERROR, SOUNDS.NEGATIVE_CLICK,
             "No wayshrine or portal found for " .. (c.name or "that location"))
end

-- ── gamepad list ──────────────────────────────────────────────

local CAT_NAMES = {
    [TYPE_WAYSHRINE] = "Wayshrines",
    [TYPE_ZONE]      = "Zones",
    [TYPE_POI]       = "Locations",
}

local function RebuildList()
    if not listObject then return end
    listObject:Clear()

    local bookmarks = GetBookmarksArray()

    if currentTerm == "" then
        -- No search term: show bookmarks only.
        for i, bm in ipairs(bookmarks) do
            local entryData = ZO_GamepadEntryData:New(bm.name, bm.icon)
            entryData.candidate = bm
            entryData:SetIconTintOnSelection(true)
            if i == 1 then
                entryData:SetHeader("Bookmarks")
                listObject:AddEntryWithHeader(
                    "ZO_GamepadMenuEntryTemplateLowercase34", entryData)
            else
                listObject:AddEntry(
                    "ZO_GamepadMenuEntryTemplateLowercase34", entryData)
            end
        end
    elseif #results > 0 then
        -- Search active: show results grouped by type.
        local lastType = nil
        for i = 1, #results do
            local c = results[i]
            local displayName = IsBookmarked(c)
                and zo_iconTextFormat("EsoUI/Art/Collections/Favorite_StarOnly.dds", 24, 24, c.name)
                or c.name
            local entryData = ZO_GamepadEntryData:New(displayName, c.icon)
            entryData.candidate = c
            entryData:SetIconTintOnSelection(true)
            if c.type ~= lastType then
                lastType = c.type
                entryData:SetHeader(CAT_NAMES[c.type] or "Other")
                listObject:AddEntryWithHeader(
                    "ZO_GamepadMenuEntryTemplateLowercase34", entryData)
            else
                listObject:AddEntry(
                    "ZO_GamepadMenuEntryTemplateLowercase34", entryData)
            end
        end
    end

    listObject:Commit()

    -- Fall back to search bar if the list is now empty.
    local listEmpty = (currentTerm == "" and #bookmarks == 0)
                   or (currentTerm ~= "" and #results == 0)
    if focusManager and focusManager:IsActive() and currentFocusIndex == 2 and listEmpty then
        focusManager:SetFocusByIndex(1)
    end

    -- Always refresh keybinds after list content changes; TargetDataChanged may
    -- not fire when transitioning from an empty list to a single-entry list.
    UpdateKeybinds()
end

local function RemoveBookmark(c)
    local key = MakeBookmarkKey(c)
    local arr = GetBookmarksArray()
    for i, bm in ipairs(arr) do
        if bm.key == key then
            table.remove(arr, i)
            RebuildList()
            UpdateKeybinds()
            return
        end
    end
end

local function ToggleBookmark(c)
    if IsBookmarked(c) then
        ZO_Dialogs_ShowGamepadDialog("GPH_UNBOOKMARK_CONFIRM", c)
    else
        local arr = GetBookmarksArray()
        arr[#arr + 1] = {
            key        = MakeBookmarkKey(c),
            name       = c.name,
            searchName = c.name:lower(),
            type       = c.type,
            icon       = c.icon,
            nodeIndex  = c.nodeIndex,
            zoneId     = c.zoneId,
            zoneIndex  = c.zoneIndex,
            mapIndex   = c.mapIndex,
            poiIndex   = c.poiIndex,
            zoneName   = c.zoneName,
            isLocked   = c.isLocked,
            known      = c.known,
        }
        RebuildList()
        UpdateKeybinds()
    end
end

-- ── map centering ────────────────────────────────────────────

local function CenterMapOnCandidate(c)
    if not c then return end

    -- Use the official manager so the internal g_playerChoseCurrentMap flag is set
    -- and OnWorldMapChanged fires properly (same as the native Locations tab does).
    if c.mapIndex then
        WORLD_MAP_MANAGER:SetMapByIndex(c.mapIndex)
    end

    -- GetPOIMapInfo returns coordinates relative to the zone map (not the world map),
    -- which is what ZO_WorldMap_PanToNormalizedPosition expects after a zone switch.
    -- 100 ms matches BeamMeUp's delay and gives the map time to finish rendering.
    zo_callLater(function()
        if c.zoneIndex and c.poiIndex then
            local nx, ny = GetPOIMapInfo(c.zoneIndex, c.poiIndex)
            if nx and ny then
                ZO_WorldMap_PanToNormalizedPosition(nx, ny)
            end
        end
    end, 100)
end

-- ── keybind strip ─────────────────────────────────────────────

local function BuildKeybindDescriptor()
    keybindDescriptor = {
        alignment = KEYBIND_STRIP_ALIGN_LEFT,
        {
            -- A: enter text mode on search bar; show on map and close panel on list entry.
            name = function()
                if currentFocusIndex == 1 then return "Search" end
                return "Show on Map"
            end,
            keybind  = "UI_SHORTCUT_PRIMARY",
            callback = function()
                if currentFocusIndex == 1 then
                    if editControl then editControl:TakeFocus() end
                else
                    local d = listObject and listObject:GetTargetData()
                    if d and d.candidate then
                        CenterMapOnCandidate(d.candidate)
                    end
                end
            end,
            visible = function()
                if currentFocusIndex == 1 then return true end
                local d = listObject and listObject:GetTargetData()
                return d ~= nil and d.candidate ~= nil
            end,
        },
        {
            -- SECONDARY (X tap): "Search" from list → search bar; "Clear" from search bar
            name = function()
                return currentFocusIndex == 1 and "Clear" or "Search"
            end,
            keybind = "UI_SHORTCUT_SECONDARY",
            callback = function()
                if currentFocusIndex == 1 then
                    GPH_MapSearch_ClearSearch()
                elseif focusManager then
                    focusManager:SetFocusByIndex(1)
                    UpdateKeybinds()
                end
            end,
            visible = function()
                return currentFocusIndex == 1 or currentFocusIndex == 2
            end,
        },
        {
            -- QUATERNARY (Hold X): toggle bookmark on focused list entry
            name = function()
                local d = listObject and listObject:GetTargetData()
                if d and d.candidate then
                    return IsBookmarked(d.candidate) and "Unbookmark" or "Bookmark"
                end
                return "Bookmark"
            end,
            keybind  = "UI_SHORTCUT_QUATERNARY",
            callback = function()
                local d = listObject and listObject:GetTargetData()
                if d and d.candidate then
                    ToggleBookmark(d.candidate)
                end
            end,
            visible = function()
                if currentFocusIndex ~= 2 then return false end
                local d = listObject and listObject:GetTargetData()
                return d ~= nil and d.candidate ~= nil
            end,
        },
    }
    -- LT / RT: jump between category headers (Wayshrines / Zones / Locations)
    ZO_Gamepad_AddListTriggerKeybindDescriptors(keybindDescriptor, listObject)
    -- Custom back (B button): exit text mode first if edit box is active, otherwise leave the panel.
    keybindDescriptor[#keybindDescriptor + 1] = {
        alignment = KEYBIND_STRIP_ALIGN_LEFT,
        order     = -1500,
        name      = GetString(SI_GAMEPAD_BACK_OPTION),
        keybind   = "UI_SHORTCUT_NEGATIVE",
        visible   = IsInGamepadPreferredMode,
        sound     = SOUNDS.GAMEPAD_MENU_BACK,
        callback  = function()
            if editControl and editControl:HasFocus() then
                editControl:LoseFocus()
            else
                if GAMEPAD_WORLD_MAP_INFO then
                    GAMEPAD_WORLD_MAP_INFO:Hide()
                end
            end
        end,
    }
end

-- ── global callbacks (called from XML) ────────────────────────

function GPH_MapSearch_OnShown(edit)
    editControl = edit
    ZO_EditDefaultText_Initialize(edit, "Search locations… (bookmarks shown below)")
    RebuildList()
end

function GPH_MapSearch_OnTextChanged(text)
    currentTerm = text
    if text == "" then results = {} end
    if text ~= "" then RunSearch(text) end
    RebuildList()
end

function GPH_MapSearch_ClearSearch()
    results     = {}
    currentTerm = ""
    UpdateSidePanel(nil)
    if editControl then
        editControl:SetText("")   -- triggers OnTextChanged → RebuildList (may switch focus)
        editControl:LoseFocus()
    end
    -- Only switch if not already on search bar (RebuildList may have already done it).
    if focusManager and currentFocusIndex ~= 1 then
        focusManager:SetFocusByIndex(1)
    end
    RebuildList()
    UpdateKeybinds()
end

-- Tab / down-arrow in the edit box: move D-pad focus to the list
function GPH_MapSearch_FocusList()
    if editControl then editControl:LoseFocus() end
    if focusManager then
        focusManager:MoveNext()
        UpdateKeybinds()
    end
end

function GPH_MapSearch_SelectCurrent()
    if listObject then
        local d = listObject:GetTargetData()
        if d and d.candidate then
            TeleportToCandidate(d.candidate)
            return
        end
    end
    if results[1] then TeleportToCandidate(results[1]) end
end

-- ── tab insertion ─────────────────────────────────────────────

local function InitList(control)
    local listCtrl = control:GetNamedChild("Main"):GetNamedChild("List")
    listObject = ZO_GamepadVerticalParametricScrollList:New(listCtrl)
    listObject:SetAlignToScreenCenter(true)

    local setupFn      = ZO_SharedGamepadEntry_OnSetup
    local parametricFn = ZO_GamepadMenuEntryTemplateParametricListFunction

    listObject:AddDataTemplate(
        "ZO_GamepadMenuEntryTemplateLowercase34", setupFn, parametricFn)
    listObject:AddDataTemplateWithHeader(
        "ZO_GamepadMenuEntryTemplateLowercase34", setupFn, parametricFn,
        nil, "ZO_GamepadMenuEntryHeaderTemplate")

    listObject:SetOnTargetDataChangedCallback(function(_, targetData)
        local c = targetData and targetData.candidate
        UpdateSidePanel(c)
        UpdateKeybinds()
    end)

    -- D-pad UP at the first list item: return focus to the search bar.
    local function ReturnToSearchBar()
        if focusManager then
            focusManager:SetFocusByIndex(1)
            UpdateKeybinds()
        end
    end

    listObject:SetOnHitBeginningOfListCallback(ReturnToSearchBar)

    -- ZO_ParametricScrollList:MovePrevious only fires HitBeginningOfList when
    -- #dataList > 1.  With a single entry (e.g. one bookmark) the callback is
    -- never reached, trapping the user in the list.  Patch the instance to cover
    -- the single-entry case without double-firing for multi-entry lists.
    local origMovePrevious = listObject.MovePrevious
    listObject.MovePrevious = function(self, ...)
        if #self.dataList <= 1 then
            ReturnToSearchBar()
            return false
        end
        return origMovePrevious(self, ...)
    end
end

local function InitFocusManager(control)
    -- ZO_GamepadFocus handles D-pad navigation between the search bar (entry 1)
    -- and the result list (entry 2). The list is skipped when it is empty.
    focusManager = ZO_GamepadFocus:New(control)

    -- Entry 1: search bar
    -- NOTE: UpdateKeybinds() is NOT called here because ZO_GamepadFocus sets self.index
    -- AFTER the activate/deactivate callbacks return, so GetFocus() would return nil.
    -- Instead, callers call UpdateKeybinds() after SetFocusByIndex/MoveNext returns.
    focusManager:AddEntry({
        highlight = searchBarHighlight,
        activate = function()
            currentFocusIndex = 1
            if searchBarIcon then
                searchBarIcon:SetColor(ZO_SELECTED_TEXT:UnpackRGBA())
            end
            UpdateKeybinds()
        end,
        deactivate = function()
            currentFocusIndex = 0
            if editControl and editControl:HasFocus() then
                editControl:LoseFocus()
            end
            if searchBarIcon then
                searchBarIcon:SetColor(ZO_DISABLED_TEXT:UnpackRGBA())
            end
        end,
    })

    -- Entry 2: result list (skipped when empty and no bookmarks)
    focusManager:AddEntry({
        canFocus = function()
            if currentTerm == "" then return #GetBookmarksArray() > 0 end
            return #results > 0
        end,
        activate = function()
            currentFocusIndex = 2
            if listObject then listObject:Activate() end
            focusManager:SetDirectionalInputEnabled(false)
            UpdateKeybinds()
        end,
        deactivate = function()
            currentFocusIndex = 0
            if listObject then listObject:Deactivate() end
            focusManager:SetDirectionalInputEnabled(true)
        end,
    })
end

local function InsertMapSearchTab()
    if GPH_SEARCH_TAB_INSERTED then return end

    local mapInfo = GAMEPAD_WORLD_MAP_INFO
    if not mapInfo or not mapInfo.tabBarEntries or not mapInfo.header then return end

    local control = GPH_MapSearch_Gamepad
    if not control then return end

    InitList(control)

    -- Grab search bar controls for visual state
    local searchBar  = control:GetNamedChild("Main"):GetNamedChild("SearchBar")
    searchBarBG        = searchBar:GetNamedChild("BG")
    searchBarHighlight = searchBar:GetNamedChild("Highlight")
    searchBarIcon      = searchBar:GetNamedChild("Icon")

    -- Grab side panel label references
    local sideContainer  = control:GetNamedChild("SideContent"):GetNamedChild("Container")
    sideTypeLabel        = sideContainer:GetNamedChild("TypeLabel")
    sideLocationIcon     = sideContainer:GetNamedChild("LocationIcon")
    sideNameLabel        = sideContainer:GetNamedChild("ZoneName")   -- XML name is ZoneName; we use it for candidate.name
    sideDescriptionLabel = sideContainer:GetNamedChild("DescriptionLabel")

    BuildKeybindDescriptor()
    InitFocusManager(control)

    GPH_SEARCH_FRAGMENT = ZO_SimpleSceneFragment:New(control)

    GPH_SEARCH_FRAGMENT:RegisterCallback("StateChange", function(_, newState)
        if newState == SCENE_SHOWING then
            if focusManager then
                focusManager:Activate()
                -- Start on the bookmark list if bookmarks exist, otherwise search bar.
                if #GetBookmarksArray() > 0 then
                    focusManager:SetFocusByIndex(2)
                end
            end
            KEYBIND_STRIP:AddKeybindButtonGroup(keybindDescriptor)
            UpdateKeybinds()
        elseif newState == SCENE_HIDDEN then
            KEYBIND_STRIP:RemoveKeybindButtonGroup(keybindDescriptor)
            if focusManager then focusManager:Deactivate() end
            if editControl  then editControl:LoseFocus() end
            UpdateSidePanel(nil)
        end
    end)

    -- If BeamMeUp is present and its "show on map open" is enabled it inserts
    -- its own tab at position 1; sit behind it so we are second.  Otherwise go first.
    local bmuActive = BMU ~= nil
                   and BMU_savedVarsAcc ~= nil
                   and BMU_savedVarsAcc.ShowOnMapOpen == true
    table.insert(mapInfo.tabBarEntries, bmuActive and 2 or 1, {
        text     = "|c3399FFGPH|r Search",
        callback = function()
            mapInfo:SwitchToFragment(GPH_SEARCH_FRAGMENT, true)
        end,
    })

    ZO_GamepadGenericHeader_Refresh(mapInfo.header, mapInfo.baseHeaderData)
    GPH_SEARCH_TAB_INSERTED = true
end

local function OnAddonLoaded(event, name)
    if name ~= "GamePadHelper" then return end
    EVENT_MANAGER:UnregisterForEvent("MapSearch", EVENT_ADD_ON_LOADED)

    ZO_Dialogs_RegisterCustomDialog("GPH_UNBOOKMARK_CONFIRM", {
        gamepadInfo = {
            dialogType = GAMEPAD_DIALOGS.BASIC,
        },
        title = { text = "Remove Bookmark" },
        mainText = {
            text = function(dialog)
                local name = dialog.data and dialog.data.name or "this location"
                return "Remove bookmark for " .. name .. "?"
            end,
        },
        buttons = {
            {
                keybind  = "DIALOG_PRIMARY",
                text     = SI_YES,
                callback = function(dialog) RemoveBookmark(dialog.data) end,
            },
            {
                keybind = "DIALOG_NEGATIVE",
                text    = SI_NO,
            },
        },
    })

    GAMEPAD_WORLD_MAP_SCENE:RegisterCallback("StateChange", function(_, newState)
        if newState == SCENE_SHOWING then
            -- Defer one frame so addons like BeamMeUp can insert their tabs
            -- synchronously first; we then insert at position 1 to be first.
            zo_callLater(InsertMapSearchTab, 0)
        end
    end)
end

EVENT_MANAGER:RegisterForEvent("MapSearch", EVENT_ADD_ON_LOADED, OnAddonLoaded)
