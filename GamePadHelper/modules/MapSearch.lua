-- ============================================================
-- GPH Map Search
-- Adds a "GPH Search" tab to the Gamepad World Map info panel.
-- POI data is pre-scanned on player activation and cached in memory.
-- ============================================================

local TYPE_WAYSHRINE = 1
local TYPE_ZONE      = 2
local TYPE_POI       = 3

local ICON_WAYSHRINE_KNOWN   = "/esoui/art/icons/poi/poi_wayshrine_complete.dds"
local ICON_WAYSHRINE_UNKNOWN = "/esoui/art/icons/poi/poi_wayshrine_incomplete.dds"
local ICON_ZONE              = "/esoui/art/icons/poi/poi_zonestory_complete.dds"
local ICON_POI               = "/esoui/art/icons/poi/poi_city_complete.dds"

local TYPE_NAMES = {
    [TYPE_WAYSHRINE] = "Wayshrine",
    [TYPE_ZONE]      = "Zone",
    [TYPE_POI]       = "Location",
}

-- ── state ────────────────────────────────────────────────────
local GPH_SEARCH_FRAGMENT     = nil
local GPH_SEARCH_TAB_INSERTED = false

local candidates  = nil   -- built from SavedVars; nil = needs rebuild
local results     = {}
local currentTerm = ""

local listObject        = nil
local editControl       = nil
local focusManager      = nil
local currentFocusIndex = 0   -- 1=search bar, 2=list

local searchBarBG        = nil
local searchBarHighlight = nil
local searchBarIcon      = nil

local keybindDescriptor = nil

-- ── search bar visual state ───────────────────────────────────

function GPH_MapSearch_OnSearchFocused(focused)
    if searchBarBG then searchBarBG:SetHidden(not focused) end
end

-- ── keybind strip helper ──────────────────────────────────────

local function UpdateKeybinds()
    if keybindDescriptor then
        KEYBIND_STRIP:UpdateKeybindButtonGroup(keybindDescriptor)
    end
end

-- ── wayshrine teleport helper ─────────────────────────────────

-- refNx, refNy: optional normalized POI position to find the nearest wayshrine.
-- GetFastTravelNodeInfo positions 3,4 are normalizedX, normalizedY in the current map space.
local function FindWayshrineInZone(zoneId, refNx, refNy)
    if not zoneId then return nil end
    local bestNode, bestDist = nil, math.huge
    local parentZoneId = GetParentZoneId(zoneId)
    for nodeIndex = 1, GetNumFastTravelNodes() do
        local known, _, wsNx, wsNy, _, _, typePOI, _, isLocked =
            GetFastTravelNodeInfo(nodeIndex)
        if known and not isLocked and typePOI == 1 then
            local zi       = select(1, GetFastTravelNodePOIIndicies(nodeIndex))
            local wsZoneId = GetZoneId(zi)
            local inZone   = wsZoneId == zoneId
                          or GetParentZoneId(wsZoneId) == zoneId
                          or (parentZoneId and wsZoneId == parentZoneId)
            if inZone then
                local dist
                if refNx and refNy and refNx > 0 and wsNx and wsNy then
                    local dx, dy = wsNx - refNx, wsNy - refNy
                    dist = dx * dx + dy * dy
                else
                    dist = 0
                end
                if dist < bestDist then
                    bestDist = dist
                    bestNode = nodeIndex
                end
            end
        end
    end
    return bestNode
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

-- ── pre-scan: collect all POI data with correct icons ─────────
-- Runs on EVENT_PLAYER_ACTIVATED. Stored in memory only — no SavedVars.
-- GetPOIMapInfo returns the actual map-pin icon (state-aware), which is
-- what BeamMeUp also uses and the only reliable source for locked wayshrines.

local scannedData = nil   -- populated by PreScan; nil = not yet scanned

-- Set the world map to the zone that owns zoneIndex, using the stable map ID.
-- Returns true if the map was changed/is now correct.
local function SetMapToZone(zoneIndex)
    local zoneId = zoneIndex and GetZoneId(zoneIndex)
    local mapId  = zoneId and GetMapIdByZoneId(zoneId)
    if mapId and mapId > 0 then
        WORLD_MAP_MANAGER:SetMapById(mapId)
        return true
    end
    -- Fallback: iterate map list (rare case where zone has no dedicated map ID)
    for mi = 1, GetNumMaps() do
        local _, mapType, _, zi = GetMapInfoByIndex(mi)
        if zi == zoneIndex and mapType == MAPTYPE_ZONE then
            WORLD_MAP_MANAGER:SetMapByIndex(mi)
            return true
        end
    end
    return false
end

local function PreScan()
    local zoneToMap = {}
    for mi = 1, GetNumMaps() do
        local _, mapType, _, zi = GetMapInfoByIndex(mi)
        if zi and zi > 0 then
            -- Prefer MAPTYPE_ZONE so POI coordinates from GetPOIMapInfo match.
            if not zoneToMap[zi] or mapType == MAPTYPE_ZONE then
                zoneToMap[zi] = mi
            end
        end
    end

    local data = { wayshrines = {}, zones = {}, pois = {} }

    -- Wayshrines ---------------------------------------------------------
    for nodeIndex = 1, GetNumFastTravelNodes() do
        local known, name, _, _, _, _, typePOI, _, isLocked =
            GetFastTravelNodeInfo(nodeIndex)
        if name ~= "" and typePOI == 1 then
            local zoneIndex, poiIndex = GetFastTravelNodePOIIndicies(nodeIndex)
            local zoneId = GetZoneId(zoneIndex)
            -- GetPOIMapInfo returns the correct state-aware icon for this specific wayshrine.
            local _, _, _, poiIcon = GetPOIMapInfo(zoneIndex, poiIndex)
            local icon = (poiIcon and poiIcon ~= "") and poiIcon
                      or (known and ICON_WAYSHRINE_KNOWN or ICON_WAYSHRINE_UNKNOWN)
            data.wayshrines[#data.wayshrines + 1] = {
                name      = name,
                icon      = icon,
                nodeIndex = nodeIndex,
                zoneIndex = zoneIndex,
                zoneId    = zoneId,
                poiIndex  = poiIndex,
                mapIndex  = zoneToMap[zoneIndex],
                zoneName  = GetZoneNameById(zoneId),
                known     = known,
                isLocked  = isLocked,
            }
        end
    end

    -- Zones --------------------------------------------------------------
    local seenZone = {}
    for mapIndex = 1, GetNumMaps() do
        local mapName, mapType, _, zoneIndex = GetMapInfoByIndex(mapIndex)
        if mapName ~= "" and zoneIndex and zoneIndex > 0 then
            local zoneId = GetZoneId(zoneIndex)
            if not seenZone[zoneId]
               and (mapType == MAPTYPE_ZONE or mapType == MAPTYPE_WORLD) then
                seenZone[zoneId] = true
                data.zones[#data.zones + 1] = {
                    name      = mapName,
                    zoneId    = zoneId,
                    zoneIndex = zoneIndex,
                    mapIndex  = mapIndex,
                }
            end
        end
    end

    -- POIs ---------------------------------------------------------------
    local seenPOI = {}
    for mapIndex = 1, GetNumMaps() do
        local _, _, _, zoneIndex = GetMapInfoByIndex(mapIndex)
        if zoneIndex and zoneIndex > 0 then
            local zoneId   = GetZoneId(zoneIndex)
            local zoneName = GetZoneNameById(zoneId)
            for poiIndex = 1, GetNumPOIs(zoneIndex) do
                local uid = zoneIndex .. ":" .. poiIndex
                if not seenPOI[uid] then
                    seenPOI[uid] = true
                    local name = GetPOIInfo(zoneIndex, poiIndex)
                    if name and name ~= "" then
                        local _, _, _, icon = GetPOIMapInfo(zoneIndex, poiIndex)
                        -- Skip wayshrine POIs — handled separately via fast travel nodes.
                        if not icon or not icon:find("wayshrine") then
                            local poiIcon = (icon and icon ~= "") and icon or nil
                            if LibPOI and poiIcon then
                                local cat = LibPOI:GetPOICategory(zoneIndex, poiIndex)
                                if cat and cat.id == "unknown" then poiIcon = nil end
                            end
                            data.pois[#data.pois + 1] = {
                                name      = name,
                                icon      = poiIcon or ICON_POI,
                                zoneIndex = zoneIndex,
                                zoneId    = zoneId,
                                poiIndex  = poiIndex,
                                mapIndex  = zoneToMap[zoneIndex],
                                zoneName  = zoneName,
                            }
                        end
                    end
                end
            end
        end
    end

    scannedData = data
    candidates  = nil   -- force BuildCandidates to rebuild from fresh data
end

-- ── data builder (reads in-memory scan) ──────────────────────

local function BuildCandidates()
    if not scannedData then PreScan() end

    local list = {}

    for _, ws in ipairs(scannedData.wayshrines) do
        list[#list + 1] = {
            name       = ws.name,
            searchName = ws.name:lower(),
            type       = TYPE_WAYSHRINE,
            icon       = ws.icon,
            nodeIndex  = ws.nodeIndex,
            zoneId     = ws.zoneId,
            zoneIndex  = ws.zoneIndex,
            poiIndex   = ws.poiIndex,
            mapIndex   = ws.mapIndex,
            zoneName   = ws.zoneName,
            known      = ws.known,
            isLocked   = ws.isLocked,
        }
    end

    for _, z in ipairs(scannedData.zones) do
        list[#list + 1] = {
            name       = z.name,
            searchName = z.name:lower(),
            type       = TYPE_ZONE,
            icon       = ICON_ZONE,
            zoneId     = z.zoneId,
            zoneIndex  = z.zoneIndex,
            mapIndex   = z.mapIndex,
            zoneName   = z.name,
            known      = true,
        }
    end

    for _, poi in ipairs(scannedData.pois) do
        list[#list + 1] = {
            name       = poi.name,
            searchName = poi.name:lower(),
            type       = TYPE_POI,
            icon       = poi.icon,
            zoneId     = poi.zoneId,
            zoneIndex  = poi.zoneIndex,
            poiIndex   = poi.poiIndex,
            mapIndex   = poi.mapIndex,
            zoneName   = poi.zoneName,
            known      = true,
        }
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

    local listEmpty = (currentTerm == "" and #bookmarks == 0)
                   or (currentTerm ~= "" and #results == 0)
    if focusManager and focusManager:IsActive() and currentFocusIndex == 2 and listEmpty then
        focusManager:SetFocusByIndex(1)
    end

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

local function AddPing(x, y)
    local pinMgr = ZO_WorldMap_GetPinManager and ZO_WorldMap_GetPinManager()
    if not pinMgr then return end
    pinMgr:RemovePins("pings")
    pinMgr:CreatePin(MAP_PIN_TYPE_AUTO_MAP_NAVIGATION_PING, "pings", x, y)
end

local function CenterMapOnCandidate(c)
    if not c then return end

    local zoneId      = c.zoneId
    local mapId       = zoneId and GetMapIdByZoneId(zoneId)
    local currentMapId = GetCurrentMapId and GetCurrentMapId()

    local function doPan()
        if c.zoneIndex and c.poiIndex then
            local nx, ny = GetPOIMapInfo(c.zoneIndex, c.poiIndex)
            if nx and nx > 0 then
                ZO_WorldMap_PanToNormalizedPosition(nx, ny)
                AddPing(nx, ny)
                return
            end
        end
        if c.type == TYPE_WAYSHRINE and c.nodeIndex then
            ZO_WorldMap_PanToWayshrine(c.nodeIndex)
        end
    end

    if mapId and mapId > 0 and mapId ~= currentMapId then
        WORLD_MAP_MANAGER:SetMapById(mapId)
        zo_callLater(doPan, 100)
    else
        doPan()
    end
end

-- ── keybind strip ─────────────────────────────────────────────

local function BuildKeybindDescriptor()
    keybindDescriptor = {
        alignment = KEYBIND_STRIP_ALIGN_LEFT,
        {
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
    ZO_Gamepad_AddListTriggerKeybindDescriptors(keybindDescriptor, listObject)
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
    if editControl then
        editControl:SetText("")
        editControl:LoseFocus()
    end
    if focusManager and currentFocusIndex ~= 1 then
        focusManager:SetFocusByIndex(1)
    end
    RebuildList()
    UpdateKeybinds()
end

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
            CenterMapOnCandidate(d.candidate)
            return
        end
    end
    if results[1] then CenterMapOnCandidate(results[1]) end
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
        UpdateKeybinds()
        if targetData and targetData.candidate then
            CenterMapOnCandidate(targetData.candidate)
        end
    end)

    local function ReturnToSearchBar()
        if focusManager then
            focusManager:SetFocusByIndex(1)
            UpdateKeybinds()
        end
    end

    listObject:SetOnHitBeginningOfListCallback(ReturnToSearchBar)

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
    focusManager = ZO_GamepadFocus:New(control)

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

    local searchBar    = control:GetNamedChild("Main"):GetNamedChild("SearchBar")
    searchBarBG        = searchBar:GetNamedChild("BG")
    searchBarHighlight = searchBar:GetNamedChild("Highlight")
    searchBarIcon      = searchBar:GetNamedChild("Icon")

    BuildKeybindDescriptor()
    InitFocusManager(control)

    -- false = we do not provide our own right-side content; the native map
    -- panel uses its own right quadrant (shows pin info as the map pans).
    GPH_SEARCH_FRAGMENT = ZO_SimpleSceneFragment:New(control)

    GPH_SEARCH_FRAGMENT:RegisterCallback("StateChange", function(_, newState)
        if newState == SCENE_SHOWING then
            if focusManager then
                focusManager:Activate()
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
        end
    end)

    local bmuActive = BMU ~= nil
                   and BMU_savedVarsAcc ~= nil
                   and BMU_savedVarsAcc.ShowOnMapOpen == true
    table.insert(mapInfo.tabBarEntries, bmuActive and 2 or 1, {
        text     = "|c3399FFGPH|r Search",
        callback = function()
            -- false = no custom right-side content; native map info panel handles right side
            mapInfo:SwitchToFragment(GPH_SEARCH_FRAGMENT, false)
        end,
    })

    ZO_GamepadGenericHeader_Refresh(mapInfo.header, mapInfo.baseHeaderData)
    GPH_SEARCH_TAB_INSERTED = true
end

local function OnAddonLoaded(event, name)
    if name ~= "GamePadHelper" then return end
    EVENT_MANAGER:UnregisterForEvent("MapSearch", EVENT_ADD_ON_LOADED)

    ZO_Dialogs_RegisterCustomDialog("GPH_UNBOOKMARK_CONFIRM", {
        gamepadInfo = { dialogType = GAMEPAD_DIALOGS.BASIC },
        title = { text = "Remove Bookmark" },
        mainText = {
            text = function(dialog)
                local n = dialog.data and dialog.data.name or "this location"
                return "Remove bookmark for " .. n .. "?"
            end,
        },
        buttons = {
            {
                keybind  = "DIALOG_PRIMARY",
                text     = SI_YES,
                callback = function(dialog) RemoveBookmark(dialog.data) end,
            },
            { keybind = "DIALOG_NEGATIVE", text = SI_NO },
        },
    })

    -- Scan is lazy: built the first time the user runs a search or opens the panel.

    GAMEPAD_WORLD_MAP_SCENE:RegisterCallback("StateChange", function(_, newState)
        if newState == SCENE_SHOWING then
            zo_callLater(InsertMapSearchTab, 0)
        end
    end)
end

EVENT_MANAGER:RegisterForEvent("MapSearch", EVENT_ADD_ON_LOADED, OnAddonLoaded)
