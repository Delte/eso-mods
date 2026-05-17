-- ============================================================
-- GPH Map Search
-- Adds a "GPH Search" tab to the Gamepad World Map info panel.
-- POI data is pre-scanned on player activation and cached in memory.
-- ============================================================

local TYPE_WAYSHRINE     = 1
local TYPE_ZONE          = 2
local TYPE_POI           = 3
local TYPE_HOUSE_OWNED   = 4
local TYPE_HOUSE_UNOWNED = 5
local TYPE_LIFT          = 6

local FAST_TRAVEL_TYPE_HOUSE = 3

local ICON_WAYSHRINE_KNOWN   = "/esoui/art/icons/poi/poi_wayshrine_complete.dds"
local ICON_WAYSHRINE_UNKNOWN = "/esoui/art/icons/poi/poi_wayshrine_incomplete.dds"
local ICON_LIFT              = "/esoui/art/icons/poi/poi_transit_complete.dds"
local ICON_POI_GENERIC       = "/esoui/art/icons/poi/poi_landmark_complete.dds"

local FAST_TRAVEL_TYPE_LIFT  = 2

local GPH_SEARCH_FRAGMENT     = nil
local GPH_SEARCH_TAB_INSERTED = false

local candidates       = nil
local results          = {}
local currentTerm      = ""
local pendingNarration = nil
local postTeleportMsg  = nil

local listObject        = nil
local editControl       = nil
local focusManager      = nil
local currentFocusIndex = 0   -- 1=search bar, 2=list

local searchBarBG        = nil
local searchBarHighlight = nil
local searchBarIcon      = nil
local isTextMode         = false

local keybindDescriptor = nil
local UpdateKeybinds
local lastFocusIndex = 1
local lastSelectedIndex = 1
local pendingRestoreSelectedIndex = nil
local consumeNextListMove = false
local listNavLockUntilMs = 0
local firstRowLockUntilMs = 0

local function IsSearchFragmentShowing()
    return GPH_SEARCH_FRAGMENT ~= nil and GPH_SEARCH_FRAGMENT:IsShowing()
end

local function SyncDirectionalInputForFocus()
    if not focusManager or not listObject then return end
    if not IsSearchFragmentShowing() then
        listObject:Deactivate()
        return
    end
    local listFocused = currentFocusIndex == 2
    if listFocused then
        listObject:Activate()
    else
        listObject:Deactivate()
    end
    listObject:RefreshVisible()
end

local function ResetMapSearchInputState()
    if IsSearchFragmentShowing() and currentFocusIndex > 0 then
        lastFocusIndex = currentFocusIndex
        if listObject and currentFocusIndex == 2 and listObject.GetSelectedIndex then
            local idx = listObject:GetSelectedIndex()
            if idx and idx > 0 then
                lastSelectedIndex = idx
            end
        end
    end
    currentFocusIndex = 0
    if editControl and editControl:HasFocus() then
        editControl:LoseFocus()
    end
    if listObject then
        listObject:Deactivate()
    end
    if focusManager then
        focusManager:Deactivate()
    end
end

local function TransitionToSearch(activateTextInput)
    if not IsSearchFragmentShowing() or not focusManager then return end
    pendingRestoreSelectedIndex = nil
    consumeNextListMove = false
    listNavLockUntilMs = 0
    focusManager:SetFocusByIndex(1)
    if activateTextInput and editControl then
        editControl:TakeFocus()
    elseif editControl and editControl:HasFocus() then
        editControl:LoseFocus()
    end
    SyncDirectionalInputForFocus()
    UpdateKeybinds()
end

local function TransitionToList(fromSearchOrText)
    if not IsSearchFragmentShowing() or not focusManager then return end
    if fromSearchOrText then
        pendingRestoreSelectedIndex = 1
        consumeNextListMove = true
        listNavLockUntilMs = GetGameTimeMilliseconds() + 350
        firstRowLockUntilMs = GetGameTimeMilliseconds() + 300
    end
    if editControl and editControl:HasFocus() then
        editControl:LoseFocus()
    end
    focusManager:SetFocusByIndex(2)
    SyncDirectionalInputForFocus()
    UpdateKeybinds()
end

local function SaveCurrentNavState()
    if currentFocusIndex > 0 then
        lastFocusIndex = currentFocusIndex
    end
    if listObject and currentFocusIndex == 2 and listObject.GetSelectedIndex then
        local idx = listObject:GetSelectedIndex()
        if idx and idx > 0 then
            lastSelectedIndex = idx
        end
    end
end

local function EnsureListInteractive()
    if not IsSearchFragmentShowing() or currentFocusIndex ~= 2 then return end
    if listObject then
        listObject:Activate()
        listObject:RefreshVisible()
    end
    UpdateKeybinds()
end

-- ── helpers ───────────────────────────────────────────────────

function GPH_MapSearch_OnSearchFocused(focused)
    isTextMode = focused
    if searchBarBG then searchBarBG:SetHidden(not focused) end
end

UpdateKeybinds = function()
    if keybindDescriptor then
        KEYBIND_STRIP:UpdateKeybindButtonGroup(keybindDescriptor)
    end
end

local function MakeBookmarkKey(c)
    return c.type .. ":" .. tostring(c.nodeIndex or c.zoneId or "") .. ":" .. c.name
end

local function GetBookmarksArray()
    if not GamePadHelperSavedVars then GamePadHelperSavedVars = {} end
    local charName = GetUnitName("player")
    if not GamePadHelperSavedVars.mapSearchBookmarks then
        GamePadHelperSavedVars.mapSearchBookmarks = {}
    end
    if not GamePadHelperSavedVars.mapSearchBookmarks[charName] then
        GamePadHelperSavedVars.mapSearchBookmarks[charName] = {}
    end
    return GamePadHelperSavedVars.mapSearchBookmarks[charName]
end

local function IsBookmarked(c)
    local key = MakeBookmarkKey(c)
    for _, bm in ipairs(GetBookmarksArray()) do
        if bm.key == key then return true end
    end
    return false
end

-- Maps stripped icon filenames to display names.
-- Mirrors LibPOI's POI_CATEGORIES + ICON_CATEGORY_OVERRIDES without the runtime dependency.
local POI_TYPE_NAMES = {
    areaofinterest  = "Area of Interest",
    adventurezone   = "Adventure Zone",
    ayleidruin      = "Ayleid Ruin",
    ayliedruin      = "Ayleid Ruin",   -- in-game icon typo
    battlefield     = "Battlefield",
    battleground    = "Battlefield",   -- group variant
    boss            = "World Boss",
    camp            = "Camp",
    cave            = "Cave",
    cemetery        = "Cemetery",
    cemetary        = "Cemetery",      -- in-game icon typo
    city            = "City",
    crafting        = "Crafting Station",
    crypt           = "Crypt",
    daedricruin     = "Daedric Ruin",
    darkbrotherhood = "Dark Brotherhood",
    delve           = "Delve",
    dock            = "Dock",
    dungeon         = "Group Dungeon",
    dwemerruin      = "Dwemer Ruin",
    endlessdungeon  = "Endless Dungeon",
    estate          = "Estate",
    explorable      = "Explorable",
    farm            = "Farm",
    gate            = "Gate",
    grove           = "Grove",
    harborage       = "Harborage",
    house           = "House",
    instance        = "Group Dungeon",
    groupboss       = "World Boss",
    groupdelve      = "Delve",
    groupinstance   = "Group Dungeon",
    keep            = "Keep",
    lighthouse      = "Lighthouse",
    mine            = "Mine",
    mine_compete    = "Mine",          -- in-game icon typo
    mine_incompete  = "Mine",          -- in-game icon typo
    mundus          = "Mundus Stone",
    mushromtower    = "Mushroom Tower",
    portal          = "Dolmen",
    raiddungeon     = "Group Trial",
    ruin            = "Ruin",
    sewer           = "Sewer",
    shrine          = "Shrine",
    shrine_vampire  = "Shrine",
    shrine_werewolf = "Shrine",
    solotrial       = "Solo Trial",
    tower           = "Tower",
    town            = "Town",
    transit         = "Lift",
    lift            = "Lift",
    nord_boat       = "Nord Boat",
    dwemergear      = "Lift",
    -- Imperial City district icons all share one category
    ic_boneshard         = "Imperial City",
    ic_darkether         = "Imperial City",
    ic_tinyclaw          = "Imperial City",
    ic_marklegion        = "Imperial City",
    ic_monstrousteeth    = "Imperial City",
    ic_planararmorscraps = "Imperial City",
    ic_daedricshackles   = "Imperial City",
    ic_daedricembers     = "Imperial City",
    -- Adventure zone naming variants
    adventurezone_entrance             = "Adventure Zone",
    adventurezone_jumppad              = "Adventure Zone",
    adventurezone_faction_ruckus       = "Adventure Zone",
    adventurezone_faction_thousandeyes = "Adventure Zone",
    adventurezone_faction_glittering   = "Adventure Zone",
    adventurezone_skirmish             = "Adventure Zone",
    adventurezone_contentgrouptimed    = "Adventure Zone",
    -- Fast travel / internal sentinels
    wayshrine    = "Wayshrine",
    icon_missing = "Unknown",
    unknown      = "Unknown",
}

local function GetPOITypeLabel(icon)
    if not icon or icon == "" then return nil end
    local name = (icon:match("([^/]+)%.dds$") or icon)
        :gsub("_complete$",   "")
        :gsub("_incomplete$", "")
        :gsub("_owned$",      "")
        :gsub("_unowned$",    "")
        :gsub("^poi_group_",  "")
        :gsub("^poi_",        "")
        :gsub("^u%d+_poi_",   "")
        :gsub("^u%d+_",       "")
    return POI_TYPE_NAMES[name]
end

local function BuildCandidateNarrationText(c, isBookmark)
    local parts = { c.name }
    if isBookmark then parts[#parts + 1] = "bookmarked" end
    if c.type == TYPE_HOUSE_OWNED or c.type == TYPE_HOUSE_UNOWNED then
        parts[#parts + 1] = c.type == TYPE_HOUSE_UNOWNED and "unowned" or "owned"
        parts[#parts + 1] = "House"
    elseif c.type == TYPE_POI then
        if c.isLocked       then parts[#parts + 1] = "locked"
        elseif not c.known  then parts[#parts + 1] = "undiscovered" end
        parts[#parts + 1] = c.poiTypeLabel or "Point of Interest"
    elseif c.type == TYPE_ZONE then
        if c.isLocked then parts[#parts + 1] = "locked" end
        parts[#parts + 1] = "Zone"
    elseif c.type == TYPE_LIFT then
        if not c.known    then parts[#parts + 1] = "undiscovered"
        elseif c.isLocked then parts[#parts + 1] = "locked" end
        parts[#parts + 1] = "Lift"
    else -- TYPE_WAYSHRINE
        if c.isLocked     then parts[#parts + 1] = "locked"
        elseif not c.known then parts[#parts + 1] = "undiscovered" end
    end
    return table.concat(parts, ", ")
end

-- ── pre-scan ──────────────────────────────────────────────────

local scannedData = nil

local function PreScan()
    local zoneToMap    = {}
    local nameToZoneId = {}
    for mi = 1, GetNumMaps() do
        local mapName, mapType, _, zi = GetMapInfoByIndex(mi)
        if zi and zi > 0 then
            if not zoneToMap[zi] or mapType == MAPTYPE_ZONE then
                zoneToMap[zi] = mi
            end
            nameToZoneId[mapName] = GetZoneId(zi)
        end
    end

    local data = { wayshrines = {}, zones = {}, pois = {}, nameToZoneId = nameToZoneId }

    -- Build a set of locked zoneIndices from fast travel nodes so zones/POIs can inherit it.
    local lockedZoneIndex = {}
    for nodeIndex = 1, GetNumFastTravelNodes() do
        local _, _, _, _, _, _, typePOI, _, isLocked = GetFastTravelNodeInfo(nodeIndex)
        if isLocked and typePOI == 1 then
            local zi = GetFastTravelNodePOIIndicies(nodeIndex)
            if zi then lockedZoneIndex[zi] = true end
        end
    end

    for nodeIndex = 1, GetNumFastTravelNodes() do
        local known, name, _, _, _, _, typePOI, _, isLocked = GetFastTravelNodeInfo(nodeIndex)
        local isWayshrine = typePOI == 1
        local isHouse     = typePOI == FAST_TRAVEL_TYPE_HOUSE
        local isLift      = typePOI == FAST_TRAVEL_TYPE_LIFT
        if name ~= "" and (isWayshrine or isHouse or isLift) then
            local zoneIndex, poiIndex = GetFastTravelNodePOIIndicies(nodeIndex)
            local zoneId = GetZoneId(zoneIndex)
            local _, _, _, poiIcon = GetPOIMapInfo(zoneIndex, poiIndex)
            local defaultIcon = isLift and ICON_LIFT
                             or (known and ICON_WAYSHRINE_KNOWN or ICON_WAYSHRINE_UNKNOWN)
            local icon = (poiIcon and poiIcon ~= "") and poiIcon or defaultIcon
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
                isHouse   = isHouse,
                isLift    = isLift,
            }
        end
    end

    local seenZone = {}
    for mapIndex = 1, GetNumMaps() do
        local mapName, mapType, _, zoneIndex = GetMapInfoByIndex(mapIndex)
        if mapName ~= "" and zoneIndex and zoneIndex > 0 then
            local zoneId = GetZoneId(zoneIndex)
            if not seenZone[zoneId] and (mapType == MAPTYPE_ZONE or mapType == MAPTYPE_WORLD) then
                seenZone[zoneId] = true
                data.zones[#data.zones + 1] = {
                    name      = mapName,
                    zoneId    = zoneId,
                    zoneIndex = zoneIndex,
                    mapIndex  = mapIndex,
                    isLocked  = lockedZoneIndex[zoneIndex] or false,
                }
                nameToZoneId[mapName] = zoneId
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
                local uid = zoneIndex .. ":" .. poiIndex
                if not seenPOI[uid] then
                    seenPOI[uid] = true
                    local name = GetPOIInfo(zoneIndex, poiIndex)
                    if name and name ~= "" then
                        local _, _, _, icon, _, linkedCollectibleIsLocked, known = GetPOIMapInfo(zoneIndex, poiIndex)
                        if not icon or not icon:find("wayshrine") then
                            local poiIcon = (icon and icon ~= "") and icon or nil
                            local isLocked = linkedCollectibleIsLocked or lockedZoneIndex[zoneIndex] or false
                            data.pois[#data.pois + 1] = {
                                name      = name,
                                icon      = poiIcon or ICON_POI_GENERIC,
                                isUnowned = poiIcon ~= nil and poiIcon:find("_unowned") ~= nil,
                                zoneIndex = zoneIndex,
                                zoneId    = zoneId,
                                poiIndex  = poiIndex,
                                mapIndex  = zoneToMap[zoneIndex],
                                zoneName  = zoneName,
                                known     = known,
                                isLocked  = isLocked,
                            }
                        end
                    end
                end
            end
        end
    end

    scannedData = data
    candidates  = nil
end

-- ── candidate building ────────────────────────────────────────

local function FindNearestWayshrineToPos(px, py, minDist, filterZoneIndex)
    if not px or not py or px == 0 then return nil end
    local bestNode, bestDist = nil, math.huge
    for nodeIndex = 1, GetNumFastTravelNodes() do
        local known, _, wsNx, wsNy, _, _, typePOI, _, isLocked = GetFastTravelNodeInfo(nodeIndex)
        if known and not isLocked and typePOI == 1 and wsNx and wsNy then
            local wsZoneIndex = filterZoneIndex and GetFastTravelNodePOIIndicies(nodeIndex)
            if not filterZoneIndex or wsZoneIndex == filterZoneIndex then
                local dx, dy = wsNx - px, wsNy - py
                local dist = dx * dx + dy * dy
                if dist < bestDist and dist >= (minDist or 0) then
                    bestDist = dist
                    bestNode = nodeIndex
                end
            end
        end
    end
    return bestNode
end

local function BuildCandidates()
    if not scannedData then PreScan() end

    local nameToZoneId = scannedData.nameToZoneId
    local list = {}

    for _, ws in ipairs(scannedData.wayshrines) do
        list[#list + 1] = {
            name       = ws.name,
            searchName = ws.name:lower(),
            type       = ws.isHouse and (ws.isLocked and TYPE_HOUSE_UNOWNED or TYPE_HOUSE_OWNED)
                      or ws.isLift and TYPE_LIFT
                      or TYPE_WAYSHRINE,
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
            icon       = "/esoui/art/worldmap/map_indexicon_locations_up.dds",
            zoneId     = z.zoneId,
            zoneIndex  = z.zoneIndex,
            mapIndex   = z.mapIndex,
            zoneName   = z.name,
            known      = true,
            isLocked   = z.isLocked,
        }
    end

    for _, poi in ipairs(scannedData.pois) do
        local poiTypeLabel = GetPOITypeLabel(poi.icon)
        local isHousePOI   = poiTypeLabel == "House"
        local entryType    = isHousePOI
            and (poi.isUnowned and TYPE_HOUSE_UNOWNED or TYPE_HOUSE_OWNED)
            or TYPE_POI

        -- Cities that are also zones: link to the zone map rather than the POI pin
        local cityZoneId = (poi.icon:find("poi_city") and nameToZoneId[poi.name]) or nil
        if cityZoneId then
            list[#list + 1] = {
                name         = poi.name,
                searchName   = poi.name:lower(),
                type         = entryType,
                poiTypeLabel = poiTypeLabel,
                icon         = poi.icon,
                zoneId       = cityZoneId,
                zoneIndex    = GetZoneIndex(cityZoneId),
                mapIndex     = GetMapIndexByZoneId(cityZoneId),
                isLocked     = poi.isLocked,
            }
        else
            list[#list + 1] = {
                name         = poi.name,
                searchName   = poi.name:lower(),
                type         = entryType,
                poiTypeLabel = poiTypeLabel,
                icon         = poi.icon,
                zoneId       = poi.zoneId,
                zoneIndex    = poi.zoneIndex,
                poiIndex     = poi.poiIndex,
                mapIndex     = poi.mapIndex,
                zoneName     = poi.zoneName,
                known        = poi.known,
                isLocked     = poi.isLocked,
            }
        end
    end

    return list
end

-- ── search ────────────────────────────────────────────────────

local function ScoreMatch(nameLower, termLower)
    if termLower == "" then return 1.0 end
    local ni, ti     = 1, 1
    local consec     = 0
    local score      = 0
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
    local scored    = {}

    for i = 1, #candidates do
        local c = candidates[i]
        local s = ScoreMatch(c.searchName, termLower)
        if s > 0 then scored[#scored + 1] = { score = s, c = c } end
    end

    table.sort(scored, function(a, b)
        if a.score ~= b.score  then return a.score > b.score end
        if a.c.type ~= b.c.type then return a.c.type < b.c.type end
        return a.c.searchName < b.c.searchName
    end)

    results = {}
    for i = 1, math.min(#scored, 60) do
        results[#results + 1] = scored[i].c
    end
end

-- ── list ──────────────────────────────────────────────────────

local CAT_NAMES = {
    [TYPE_WAYSHRINE]     = "Wayshrines",
    [TYPE_LIFT]          = "Lifts",
    [TYPE_ZONE]          = "Zones",
    [TYPE_POI]           = "Locations",
    [TYPE_HOUSE_OWNED]   = "Owned Houses",
    [TYPE_HOUSE_UNOWNED] = "Unowned Houses",
}

local function RebuildList()
    if not listObject then return end
    listObject:Clear()

    local bookmarks = GetBookmarksArray()

    if currentTerm == "" then
        for i, bm in ipairs(bookmarks) do
            local entryData = ZO_GamepadEntryData:New(bm.name, bm.icon)
            entryData.candidate = bm
            entryData.isBookmark = true
            entryData:SetIconTintOnSelection(true)
            if bm.isLocked then entryData:AddIcon("EsoUI/Art/Miscellaneous/status_locked.dds") end
            if i == 1 then
                entryData:SetHeader("Bookmarks")
                listObject:AddEntryWithHeader("ZO_GamepadMenuEntryTemplateLowercase34", entryData)
            else
                listObject:AddEntry("ZO_GamepadMenuEntryTemplateLowercase34", entryData)
            end
        end
    elseif #results > 0 then
        local lastType = nil
        for _, c in ipairs(results) do
            local displayName = IsBookmarked(c)
                and zo_iconTextFormat("EsoUI/Art/Collections/Favorite_StarOnly.dds", 24, 24, c.name)
                or c.name
            local entryData = ZO_GamepadEntryData:New(displayName, c.icon)
            entryData.candidate = c
            entryData:SetIconTintOnSelection(true)
            if c.isLocked then entryData:AddIcon("EsoUI/Art/Miscellaneous/status_locked.dds") end
            if c.type ~= lastType then
                lastType = c.type
                entryData:SetHeader(CAT_NAMES[c.type] or "Other")
                listObject:AddEntryWithHeader("ZO_GamepadMenuEntryTemplateLowercase34", entryData)
            else
                listObject:AddEntry("ZO_GamepadMenuEntryTemplateLowercase34", entryData)
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

-- ── bookmarks ─────────────────────────────────────────────────

local function RemoveBookmark(c)
    local key = MakeBookmarkKey(c)
    local arr = GetBookmarksArray()
    for i, bm in ipairs(arr) do
        if bm.key == key then
            table.remove(arr, i)
            RebuildList()
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
    end
end

-- ── map interaction ───────────────────────────────────────────

local function AddPing(x, y)
    local pinMgr = ZO_WorldMap_GetPinManager and ZO_WorldMap_GetPinManager()
    if not pinMgr then return end
    pinMgr:RemovePins("pings")
    pinMgr:CreatePin(MAP_PIN_TYPE_AUTO_MAP_NAVIGATION_PING, "pings", x, y)
    local sv = _G["GamePadHelper_SavedVars"]
    if sv == nil or sv.mapSearchSetDestination ~= false then
        PingMap(MAP_PIN_TYPE_PLAYER_WAYPOINT, MAP_TYPE_LOCATION_CENTERED, x, y)
    end
end

local function CenterMapOnCandidate(c)
    if not c then return end

    local zoneId       = c.zoneId
    local mapId        = zoneId and GetMapIdByZoneId(zoneId)
    local currentMapId = GetCurrentMapId and GetCurrentMapId()

    local function doPan()
        if c.icon and c.icon:find("poi_city") then
            ZO_WorldMap_PanToNormalizedPosition(0.5, 0.5)
            return
        end
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

-- ── keybinds ──────────────────────────────────────────────────

local function BuildKeybindDescriptor()
    keybindDescriptor = {
        alignment = KEYBIND_STRIP_ALIGN_LEFT,
        {
            name = function()
                return currentFocusIndex == 1 and "Search" or "Show on Map"
            end,
            keybind  = "UI_SHORTCUT_PRIMARY",
            callback = function()
                if currentFocusIndex == 1 then
                    if isTextMode and focusManager then
                        TransitionToList(true)
                    elseif editControl then
                        TransitionToSearch(true)
                        pendingNarration = "Text input active"
                        SCREEN_NARRATION_MANAGER:QueueCustomEntry("GPH_MapSearch_Narration")
                    end
                else
                    local td = listObject and listObject:GetTargetData()
                    if td and td.candidate then
                        local selectedIndexBeforePrimary = nil
                        if listObject and listObject.GetSelectedIndex then
                            selectedIndexBeforePrimary = listObject:GetSelectedIndex()
                        end
                        if selectedIndexBeforePrimary and selectedIndexBeforePrimary > 0 then
                            lastFocusIndex = 2
                            lastSelectedIndex = selectedIndexBeforePrimary
                        end
                        CenterMapOnCandidate(td.candidate)
                        zo_callLater(function()
                            if not IsSearchFragmentShowing() then return end
                            if focusManager and currentFocusIndex ~= 2 then
                                focusManager:SetFocusByIndex(2)
                            end
                            if listObject and selectedIndexBeforePrimary and selectedIndexBeforePrimary > 0 then
                                local restoreIndex = selectedIndexBeforePrimary
                                if listObject.GetNumItems then
                                    local numItems = listObject:GetNumItems()
                                    if numItems and numItems > 0 then
                                        restoreIndex = zo_clamp(restoreIndex, 1, numItems)
                                    else
                                        restoreIndex = 1
                                    end
                                end
                                listObject:SetSelectedIndex(restoreIndex)
                            end
                            EnsureListInteractive()
                        end, 80)
                        local keybindName = ZO_Keybindings_GetBindingStringFromAction("UI_SHORTCUT_QUINARY") or "Teleport"
                        pendingNarration = td.candidate.name .. " selected on map. Ready to teleport. Hold " .. keybindName .. " to teleport."
                        SCREEN_NARRATION_MANAGER:QueueCustomEntry("GPH_MapSearch_Narration")
                    end
                end
            end,
            visible = function()
                if currentFocusIndex == 1 then return true end
                local td = listObject and listObject:GetTargetData()
                return td ~= nil and td.candidate ~= nil
            end,
        },
        {
            name = function()
                return currentFocusIndex == 1 and "Clear" or "Search"
            end,
            keybind  = "UI_SHORTCUT_SECONDARY",
            callback = function()
                if currentFocusIndex == 1 then
                    GPH_MapSearch_ClearSearch()
                elseif focusManager then
                    TransitionToSearch(false)
                    local label = currentTerm ~= "" and ("Searching for " .. currentTerm) or "Search locations"
                    pendingNarration = label .. ", text field"
                    SCREEN_NARRATION_MANAGER:QueueCustomEntry("GPH_MapSearch_Narration")
                end
            end,
            visible = function()
                return currentFocusIndex == 1 or currentFocusIndex == 2
            end,
        },
        {
            name = function()
                local td = listObject and listObject:GetTargetData()
                if td and td.candidate then
                    return IsBookmarked(td.candidate) and "Unbookmark" or "Bookmark"
                end
                return "Bookmark"
            end,
            keybind  = "UI_SHORTCUT_QUATERNARY",
            callback = function()
                local td = listObject and listObject:GetTargetData()
                if td and td.candidate then
                    local wasBookmarked = IsBookmarked(td.candidate)
                    local name = td.candidate.name
                    ToggleBookmark(td.candidate)
                    pendingNarration = (not wasBookmarked and "Bookmarked" or "Bookmark removed") .. ", " .. name
                    SCREEN_NARRATION_MANAGER:QueueCustomEntry("GPH_MapSearch_Narration")
                end
            end,
            visible = function()
                if currentFocusIndex ~= 2 then return false end
                local td = listObject and listObject:GetTargetData()
                return td ~= nil and td.candidate ~= nil
            end,
        },
        {
            name     = function()
                local td = listObject and listObject:GetTargetData()
                if td and td.candidate then
                    local c = td.candidate
                    if (c.type == TYPE_WAYSHRINE and c.known and not c.isLocked) or c.type == TYPE_HOUSE_OWNED then
                        return "Teleport"
                    end
                end
                return "Teleport to Nearest Wayshrine"
            end,
            enabled  = function()
                local td = listObject and listObject:GetTargetData()
                if td and td.candidate then
                    local c = td.candidate
                    if c.type == TYPE_WAYSHRINE and c.isLocked then
                        return false
                    end
                end
                return true
            end,
            keybind  = "UI_SHORTCUT_QUINARY",
            visible  = function() return currentFocusIndex == 2 end,
            callback = function()
                local nodeIndex = nil
                local failReason = nil
                local td = listObject and listObject:GetTargetData()
                if td and td.candidate then
                    local c = td.candidate
                    if not GamePadHelperSavedVars then GamePadHelperSavedVars = {} end
                    GamePadHelperSavedVars.lastSelectedPOI = c
                    if c.type == TYPE_WAYSHRINE and c.known and not c.isLocked then
                        nodeIndex = c.nodeIndex
                    elseif c.type == TYPE_WAYSHRINE and c.isLocked then
                        failReason = "locked"
                    elseif c.zoneIndex and c.poiIndex then
                        local nx, ny = GetPOIMapInfo(c.zoneIndex, c.poiIndex)
                        if nx and ny then
                            nodeIndex = FindNearestWayshrineToPos(nx, ny, 0, c.zoneIndex)
                        end
                        if not nodeIndex then failReason = "undiscovered" end
                    elseif c.nodeIndex then
                        nodeIndex = c.nodeIndex
                    end
                end
                if not nodeIndex then
                    local msg = failReason == "locked"
                        and "This zone is locked — you don't own the required content"
                        or  "No discovered wayshrine in this zone"
                    ZO_Alert(UI_ALERT_CATEGORY_ERROR, SOUNDS.NEGATIVE_CLICK, msg)
                    return
                end
                local atWayshrine = GetInteractionType() == INTERACTION_FAST_TRAVEL
                local cost = (not atWayshrine) and GetRecallCost(nodeIndex) or 0
                if cost > 0 then
                    ZO_Dialogs_ShowGamepadDialog("GPH_TELEPORT_CONFIRM", { nodeIndex = nodeIndex, cost = cost })
                else
                    FastTravelToNode(nodeIndex)
                    local sv = _G["GamePadHelper_SavedVars"]
                    if sv == nil or sv.mapSearchNarratePreTeleport ~= false then
                        postTeleportMsg = "Teleporting. Open the map to find the visual pin marking your destination."
                    end
                end
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
            if isTextMode then
                if editControl then editControl:LoseFocus() end
                focusManager:SetFocusByIndex(1)
                SyncDirectionalInputForFocus()
                local label = currentTerm ~= "" and ("Searching for " .. currentTerm) or "Search locations"
                pendingNarration = label .. ", text field"
                SCREEN_NARRATION_MANAGER:QueueCustomEntry("GPH_MapSearch_Narration")
            elseif GAMEPAD_WORLD_MAP_INFO then
                GAMEPAD_WORLD_MAP_INFO:Hide()
            end
        end,
    }
end

-- ── XML callbacks ─────────────────────────────────────────────

function GPH_MapSearch_OnShown(edit)
    editControl = edit
    ZO_EditDefaultText_Initialize(edit, "Search locations… (bookmarks shown below)")
    RebuildList()
end

function GPH_MapSearch_OnTextChanged(text)
    if not IsSearchFragmentShowing() then return end
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
    if focusManager then
        if currentFocusIndex ~= 1 then
            focusManager:SetFocusByIndex(1)
        end
        SyncDirectionalInputForFocus()
    end
    RebuildList()
    UpdateKeybinds()
end

function GPH_MapSearch_FocusList()
    if not IsSearchFragmentShowing() then return end
    if isTextMode then
        TransitionToList(true)
    elseif focusManager then
        TransitionToList(true)
    end
end

function GPH_MapSearch_SelectCurrent()
    if not IsSearchFragmentShowing() then return end
    if listObject then
        local td = listObject:GetTargetData()
        if td and td.candidate then
            CenterMapOnCandidate(td.candidate)
            return
        end
    end
    if results[1] then CenterMapOnCandidate(results[1]) end
end

-- ── UI init ───────────────────────────────────────────────────

local function InitList(control)
    local listCtrl = control:GetNamedChild("Main"):GetNamedChild("List")
    listObject = ZO_GamepadVerticalParametricScrollList:New(listCtrl)
    listObject:SetAlignToScreenCenter(true)

    local SELECTED_COLOR = ZO_ColorDef:New(0.95, 0.82, 0.45, 1)  -- soft golden

    local function EntrySetup(ctrl, data, selected, reselectingDuringRebuild, enabled, active)
        local isFocused = currentFocusIndex == 2
        ZO_SharedGamepadEntry_OnSetup(ctrl, data, selected and isFocused, reselectingDuringRebuild, enabled, active)
        if selected and isFocused and ctrl.label then
            ctrl.label:SetColor(SELECTED_COLOR:UnpackRGBA())
        end
    end

    local function EntryParametric(ctrl, distanceFromCenter, continousParametricOffset)
        if currentFocusIndex == 2 then
            ZO_GamepadMenuEntryTemplateParametricListFunction(ctrl, distanceFromCenter, continousParametricOffset)
        else
            if ctrl.icon then ctrl.icon:SetScale(1) end
        end
    end

    listObject:AddDataTemplate(
        "ZO_GamepadMenuEntryTemplateLowercase34",
        EntrySetup,
        EntryParametric)
    listObject:AddDataTemplateWithHeader(
        "ZO_GamepadMenuEntryTemplateLowercase34",
        EntrySetup,
        EntryParametric,
        nil, "ZO_GamepadMenuEntryHeaderTemplate")

    local narrationPending = false
    listObject:SetOnTargetDataChangedCallback(function()
        UpdateKeybinds()
        if currentFocusIndex == 2 and not narrationPending then
            narrationPending = true
            zo_callLater(function()
                narrationPending = false
                if currentFocusIndex == 2 then
                    SCREEN_NARRATION_MANAGER:QueueCustomEntry("GPH_MapSearch_Narration")
                end
            end, 600)
        end
    end)

    local function ReturnToSearchBar()
        if IsSearchFragmentShowing() and focusManager then
            focusManager:SetFocusByIndex(1)
            UpdateKeybinds()
        end
    end

    listObject:SetOnHitBeginningOfListCallback(ReturnToSearchBar)

    local origMovePrevious = listObject.MovePrevious
    listObject.MovePrevious = function(self, ...)
        if GetGameTimeMilliseconds() < listNavLockUntilMs then
            return false
        end
        if GetGameTimeMilliseconds() < firstRowLockUntilMs then
            return false
        end
        if #self.dataList <= 1 then
            ReturnToSearchBar()
            return false
        end
        return origMovePrevious(self, ...)
    end

    local origMoveNext = listObject.MoveNext
    listObject.MoveNext = function(self, ...)
        if GetGameTimeMilliseconds() < listNavLockUntilMs then
            return false
        end
        if GetGameTimeMilliseconds() < firstRowLockUntilMs then
            return false
        end
        if consumeNextListMove then
            consumeNextListMove = false
            return false
        end
        return origMoveNext(self, ...)
    end
end

local function InitFocusManager(control)
    focusManager = ZO_GamepadFocus:New(control)

    focusManager:AddEntry({
        highlight     = searchBarHighlight,
        narrationText = function()
            local label = currentTerm ~= "" and ("Searching for " .. currentTerm) or "Search locations"
            return SCREEN_NARRATION_MANAGER:CreateNarratableObject(label .. ", text field")
        end,
        activate = function()
            currentFocusIndex = 1
            if searchBarIcon then searchBarIcon:SetColor(ZO_SELECTED_TEXT:UnpackRGBA()) end
            SyncDirectionalInputForFocus()
            UpdateKeybinds()
            local label = currentTerm ~= "" and ("Searching for " .. currentTerm) or "Search locations"
            pendingNarration = label .. ", text field"
            SCREEN_NARRATION_MANAGER:QueueCustomEntry("GPH_MapSearch_Narration")
        end,
        deactivate = function()
            currentFocusIndex = 0
            if editControl and editControl:HasFocus() then editControl:LoseFocus() end
            if searchBarIcon then searchBarIcon:SetColor(ZO_DISABLED_TEXT:UnpackRGBA()) end
        end,
    })

    focusManager:AddEntry({
        canFocus = function()
            if currentTerm == "" then return #GetBookmarksArray() > 0 end
            return #results > 0
        end,
        narrationText = function()
            local td = listObject and listObject:GetTargetData()
            if not td or not td.candidate then
                return SCREEN_NARRATION_MANAGER:CreateNarratableObject("Empty list")
            end
            return SCREEN_NARRATION_MANAGER:CreateNarratableObject(
                BuildCandidateNarrationText(td.candidate, td.isBookmark))
        end,
        activate = function()
            currentFocusIndex = 2
            if listObject then
                local hasExplicitRestoreIndex = pendingRestoreSelectedIndex ~= nil
                local desiredIndex = pendingRestoreSelectedIndex or 1
                local enteringFromSearch = desiredIndex == 1 and (consumeNextListMove or not hasExplicitRestoreIndex)
                if listObject.GetNumItems then
                    local numItems = listObject:GetNumItems()
                    if numItems and numItems > 0 then
                        desiredIndex = zo_clamp(desiredIndex, 1, numItems)
                    else
                        desiredIndex = 1
                    end
                end
                listObject:SetSelectedIndex(desiredIndex)
                if desiredIndex ~= 1 then
                    consumeNextListMove = false
                end
                pendingRestoreSelectedIndex = nil
                if enteringFromSearch then
                    listNavLockUntilMs = GetGameTimeMilliseconds() + 350
                    firstRowLockUntilMs = GetGameTimeMilliseconds() + 300
                    zo_callLater(function()
                        if currentFocusIndex == 2 and IsSearchFragmentShowing() and listObject then
                            listObject:SetSelectedIndex(1)
                            listObject:RefreshVisible()
                        end
                    end, 0)
                    zo_callLater(function()
                        if currentFocusIndex == 2 and IsSearchFragmentShowing() and listObject then
                            listObject:SetSelectedIndex(1)
                            listObject:RefreshVisible()
                        end
                    end, 120)
                end
            end
            SyncDirectionalInputForFocus()
            UpdateKeybinds()
            SCREEN_NARRATION_MANAGER:QueueCustomEntry("GPH_MapSearch_Narration")
        end,
        deactivate = function()
            currentFocusIndex = 0
            if listObject then
                listObject:Deactivate()
                listObject:RefreshVisible()
            end
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

    GPH_SEARCH_FRAGMENT = ZO_SimpleSceneFragment:New(control)

    SCREEN_NARRATION_MANAGER:RegisterCustomObject("GPH_MapSearch_PostTeleport", {
        narrationType = NARRATION_TYPE_UI_INTERACTIONS,
        canNarrate    = function() return pendingNarration ~= nil end,
        selectedNarrationFunction = function()
            local narrations = {}
            if pendingNarration then
                ZO_AppendNarration(narrations, SCREEN_NARRATION_MANAGER:CreateNarratableObject(pendingNarration))
                pendingNarration = nil
            end
            return narrations
        end,
    })

    SCREEN_NARRATION_MANAGER:RegisterCustomObject("GPH_MapSearch_Narration", {
        narrationType = NARRATION_TYPE_UI_INTERACTIONS,
        canNarrate    = function()
            return GPH_SEARCH_FRAGMENT:IsShowing()
        end,
        selectedNarrationFunction = function()
            local narrations = {}
            if pendingNarration then
                ZO_AppendNarration(narrations, SCREEN_NARRATION_MANAGER:CreateNarratableObject(pendingNarration))
                pendingNarration = nil
                return narrations
            end
            if currentFocusIndex == 2 then
                local td = listObject and listObject:GetTargetData()
                if td and td.candidate then
                    ZO_AppendNarration(narrations, SCREEN_NARRATION_MANAGER:CreateNarratableObject(
                        BuildCandidateNarrationText(td.candidate, td.isBookmark)))
                else
                    ZO_AppendNarration(narrations, SCREEN_NARRATION_MANAGER:CreateNarratableObject("Empty list"))
                end
            else
                local label = currentTerm ~= "" and ("Searching for " .. currentTerm) or "Search locations"
                ZO_AppendNarration(narrations, SCREEN_NARRATION_MANAGER:CreateNarratableObject(label))
            end
            return narrations
        end,
    })

    GPH_SEARCH_FRAGMENT:RegisterCallback("StateChange", function(_, newState)
        if newState == SCENE_SHOWING then
            ResetMapSearchInputState()
            if focusManager then
                focusManager:Activate()
                if lastFocusIndex == 2 then
                    pendingRestoreSelectedIndex = lastSelectedIndex or 1
                    focusManager:SetFocusByIndex(2)
                else
                    focusManager:SetFocusByIndex(1)
                end
            end
            SyncDirectionalInputForFocus()
            KEYBIND_STRIP:AddKeybindButtonGroup(keybindDescriptor)
            UpdateKeybinds()
            SCREEN_NARRATION_MANAGER:QueueCustomEntry("GPH_MapSearch_Narration")
        elseif newState == SCENE_HIDING or newState == SCENE_HIDDEN then
            SaveCurrentNavState()
            KEYBIND_STRIP:RemoveKeybindButtonGroup(keybindDescriptor)
            ResetMapSearchInputState()
        end
    end)

    local bmuActive = BMU ~= nil
                   and BMU_savedVarsAcc ~= nil
                   and BMU_savedVarsAcc.ShowOnMapOpen == true
    local tabIndex = bmuActive and 2 or 1
    table.insert(mapInfo.tabBarEntries, tabIndex, {
        text     = "|c3399FFGPH|r Search",
        callback = function()
            ResetMapSearchInputState()
            mapInfo:SwitchToFragment(GPH_SEARCH_FRAGMENT, false)
        end,
    })

    ZO_GamepadGenericHeader_Refresh(mapInfo.header, mapInfo.baseHeaderData)
    local sv = _G["GamePadHelper_SavedVars"]
    local defaultTab = sv == nil or sv.mapSearchDefaultTab ~= false
    if defaultTab then
        ZO_GamepadGenericHeader_SetActiveTabIndex(mapInfo.header, tabIndex)
    end
    GPH_SEARCH_TAB_INSERTED = true
end

-- ── addon loaded ──────────────────────────────────────────────

local function OnAddonLoaded(event, name)
    if name ~= "GamePadHelper" then return end
    EVENT_MANAGER:UnregisterForEvent("MapSearch", EVENT_ADD_ON_LOADED)

    EVENT_MANAGER:RegisterForEvent("MapSearch_Teleport", EVENT_PLAYER_ACTIVATED, function()
        if postTeleportMsg then
            local msg = postTeleportMsg
            postTeleportMsg = nil
            zo_callLater(function()
                SCREEN_NARRATION_MANAGER:QueueCustomEntry("GPH_MapSearch_PostTeleport")
                pendingNarration = msg
            end, 500)
        end
    end)

    ZO_Dialogs_RegisterCustomDialog("GPH_TELEPORT_CONFIRM", {
        gamepadInfo = { dialogType = GAMEPAD_DIALOGS.BASIC },
        title       = { text = "Confirm Teleport" },
        mainText    = {
            text = function(dialog)
                local cost = dialog.data and dialog.data.cost or 0
                return zo_strformat("This teleport will cost <<1>> gold. Proceed?", cost)
            end,
        },
        buttons = {
            {
                keybind  = "DIALOG_PRIMARY",
                text     = SI_YES,
                callback = function(dialog)
                    if dialog.data and dialog.data.nodeIndex then
                        FastTravelToNode(dialog.data.nodeIndex)
                        local sv = _G["GamePadHelper_SavedVars"]
                    if sv == nil or sv.mapSearchNarratePreTeleport ~= false then
                        postTeleportMsg = "Teleporting. Open the map to find the visual pin marking your destination."
                    end
                    end
                end,
            },
            { keybind = "DIALOG_NEGATIVE", text = SI_NO },
        },
    })

    ZO_Dialogs_RegisterCustomDialog("GPH_UNBOOKMARK_CONFIRM", {
        gamepadInfo = { dialogType = GAMEPAD_DIALOGS.BASIC },
        title       = { text = "Remove Bookmark" },
        mainText    = {
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

    GAMEPAD_WORLD_MAP_SCENE:RegisterCallback("StateChange", function(_, newState)
        if newState == SCENE_SHOWING then
            zo_callLater(InsertMapSearchTab, 0)
            if GamePadHelperSavedVars and GamePadHelperSavedVars.lastSelectedPOI then
                zo_callLater(function()
                    local poi = GamePadHelperSavedVars.lastSelectedPOI
                    CenterMapOnCandidate(poi)
                    GamePadHelperSavedVars.lastSelectedPOI = nil
                    local sv2 = _G["GamePadHelper_SavedVars"]
                    if sv2 == nil or sv2.mapSearchNarratePostTeleport ~= false then
                        pendingNarration = "Teleported to nearest wayshrine. " .. poi.name .. " is visually marked on the map with a destination waypoint."
                        SCREEN_NARRATION_MANAGER:QueueCustomEntry("GPH_MapSearch_Narration")
                    end
                end, 100)
            end
        end
    end)
end

EVENT_MANAGER:RegisterForEvent("MapSearch", EVENT_ADD_ON_LOADED, OnAddonLoaded)
