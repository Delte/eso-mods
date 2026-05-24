-- ============================================================
-- GPH Map Search
-- Navigation model: list owns d-pad, edit box for text only.
-- Full feature set: POI/House/Lift types, fuzzy search, teleport,
-- bookmarks with confirmation, narration, post-teleport restore.
-- ============================================================

local function CleanName(s)
    return (s and s ~= "") and zo_strformat("<<C:1>>", s) or (s or "")
end

local TYPE_WAYSHRINE     = 1
local TYPE_ZONE          = 2
local TYPE_POI           = 3
local TYPE_HOUSE_OWNED   = 4
local TYPE_HOUSE_UNOWNED = 5
local TYPE_LIFT          = 6

-- Use ESO's named constants - never hardcode poiType numbers.
-- POI_TYPE_WAYSHRINE / POI_TYPE_HOUSE / POI_TYPE_GROUP_DUNGEON etc. are defined by the game client.

local ICON_WAYSHRINE_KNOWN   = "/esoui/art/icons/poi/poi_wayshrine_complete.dds"
local ICON_WAYSHRINE_UNKNOWN = "/esoui/art/icons/poi/poi_wayshrine_incomplete.dds"
local ICON_POI_GENERIC       = "/esoui/art/icons/poi/poi_landmark_complete.dds"

local GPH_SEARCH_FRAGMENT     = nil
local GPH_SEARCH_TAB_INSERTED = false
local gphSearchTabIndex       = nil
local wasOnGPHSearch          = nil

local scannedData = nil
local candidates  = nil
local results     = {}
local currentTerm = ""
local lastSearchTerm = nil

local listObject        = nil
local editControl       = nil
local searchBarBG       = nil
local recallCostLabel   = nil
local keybindDescriptor = nil
local RebuildList

local lastSelectedIndex = 1
local pendingNarration  = nil
local postTeleportMsg   = nil
local listCostLoopId = 0

local function IsFragmentShowing()
    return GPH_SEARCH_FRAGMENT ~= nil and GPH_SEARCH_FRAGMENT:IsShowing()
end

_G["GamePadHelper_MapSearch_IsShowing"] = IsFragmentShowing

local function GetSavedVars()
    return _G["GamePadHelper_SavedVars"]
end

local function UpdateKeybinds()
    if keybindDescriptor then
        KEYBIND_STRIP:UpdateKeybindButtonGroup(keybindDescriptor)
    end
end


-- bookmarks

local function MakeBookmarkKey(c)
    return c.type .. ":" .. tostring(c.nodeIndex or c.zoneId or "") .. ":" .. c.name
end

local function GetBookmarkKey(c)
    if not c then return "" end
    if c.key and c.key ~= "" then return c.key end
    if c.bookmarkKey and c.bookmarkKey ~= "" then return c.bookmarkKey end
    local k = MakeBookmarkKey(c)
    c.bookmarkKey = k
    return k
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
    local key = GetBookmarkKey(c)
    for _, bm in ipairs(GetBookmarksArray()) do
        if GetBookmarkKey(bm) == key then return true end
    end
    return false
end

local function RemoveBookmark(c)
    local key = GetBookmarkKey(c)
    local arr = GetBookmarksArray()
    for i, bm in ipairs(arr) do
        if GetBookmarkKey(bm) == key then
            table.remove(arr, i)
            return
        end
    end
end

local function AddBookmark(c)
    local arr = GetBookmarksArray()
    arr[#arr + 1] = {
        key        = GetBookmarkKey(c),
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
end

-- POI type labels

local POI_TYPE_NAMES = {
    areaofinterest  = GetString(SI_GPH_MAPSEARCH_LABEL_AREA_OF_INTEREST),
    adventurezone   = GetString(SI_GPH_MAPSEARCH_LABEL_ADVENTURE_ZONE),
    ayleidruin      = GetString(SI_GPH_MAPSEARCH_LABEL_AYLEID_RUIN),
    ayliedruin      = GetString(SI_GPH_MAPSEARCH_LABEL_AYLEID_RUIN),
    battlefield     = GetString(SI_GPH_MAPSEARCH_LABEL_BATTLEFIELD),
    battleground    = GetString(SI_GPH_MAPSEARCH_LABEL_BATTLEFIELD),
    boss            = GetString(SI_GPH_MAPSEARCH_LABEL_WORLD_BOSS),
    camp            = GetString(SI_GPH_MAPSEARCH_LABEL_CAMP),
    cave            = GetString(SI_GPH_MAPSEARCH_LABEL_CAVE),
    cemetery        = GetString(SI_GPH_MAPSEARCH_LABEL_CEMETERY),
    cemetary        = GetString(SI_GPH_MAPSEARCH_LABEL_CEMETERY),
    city            = GetString(SI_GPH_MAPSEARCH_LABEL_CITY),
    crafting        = GetString(SI_GPH_MAPSEARCH_LABEL_CRAFTING_STATION),
    crypt           = GetString(SI_GPH_MAPSEARCH_LABEL_CRYPT),
    daedricruin     = GetString(SI_GPH_MAPSEARCH_LABEL_DAEDRIC_RUIN),
    darkbrotherhood = GetString(SI_GPH_MAPSEARCH_LABEL_DARK_BROTHERHOOD),
    delve           = GetString(SI_GPH_MAPSEARCH_LABEL_DELVE),
    dock            = GetString(SI_GPH_MAPSEARCH_LABEL_DOCK),
    dungeon         = GetString(SI_GPH_MAPSEARCH_LABEL_GROUP_DUNGEON),
    dwemerruin      = GetString(SI_GPH_MAPSEARCH_LABEL_DWEMER_RUIN),
    endlessdungeon  = GetString(SI_GPH_MAPSEARCH_LABEL_ENDLESS_DUNGEON),
    estate          = GetString(SI_GPH_MAPSEARCH_LABEL_ESTATE),
    explorable      = GetString(SI_GPH_MAPSEARCH_LABEL_EXPLORABLE),
    farm            = GetString(SI_GPH_MAPSEARCH_LABEL_FARM),
    gate            = GetString(SI_GPH_MAPSEARCH_LABEL_GATE),
    grove           = GetString(SI_GPH_MAPSEARCH_LABEL_GROVE),
    harborage       = GetString(SI_GPH_MAPSEARCH_LABEL_HARBORAGE),
    house           = GetString(SI_GPH_MAPSEARCH_LABEL_HOUSE),
    instance        = GetString(SI_GPH_MAPSEARCH_LABEL_GROUP_DUNGEON),
    groupboss       = GetString(SI_GPH_MAPSEARCH_LABEL_WORLD_BOSS),
    groupdelve      = GetString(SI_GPH_MAPSEARCH_LABEL_DELVE),
    groupinstance   = GetString(SI_GPH_MAPSEARCH_LABEL_GROUP_DUNGEON),
    -- explicit group_ keys so poi_group_* icons resolve correctly
    group_boss            = GetString(SI_GPH_MAPSEARCH_LABEL_WORLD_BOSS),
    group_delve           = GetString(SI_GPH_MAPSEARCH_LABEL_DELVE),
    group_instance        = GetString(SI_GPH_MAPSEARCH_LABEL_GROUP_DUNGEON),
    group_dungeon         = GetString(SI_GPH_MAPSEARCH_LABEL_GROUP_DUNGEON),
    group_house           = GetString(SI_GPH_MAPSEARCH_LABEL_GROUP_INSTANCE),
    group_keep            = GetString(SI_GPH_MAPSEARCH_LABEL_KEEP),
    group_cave            = GetString(SI_GPH_MAPSEARCH_LABEL_DELVE),
    group_areaofinterest  = GetString(SI_GPH_MAPSEARCH_LABEL_AREA_OF_INTEREST),
    group_cemetery        = GetString(SI_GPH_MAPSEARCH_LABEL_CEMETERY),
    group_lighthouse      = GetString(SI_GPH_MAPSEARCH_LABEL_LIGHTHOUSE),
    group_ruin            = GetString(SI_GPH_MAPSEARCH_LABEL_RUIN),
    group_portal          = GetString(SI_GPH_MAPSEARCH_LABEL_DOLMEN),
    group_estate          = GetString(SI_GPH_MAPSEARCH_LABEL_GROUP_TRIAL),
    keep            = GetString(SI_GPH_MAPSEARCH_LABEL_KEEP),
    lighthouse      = GetString(SI_GPH_MAPSEARCH_LABEL_LIGHTHOUSE),
    mine            = GetString(SI_GPH_MAPSEARCH_LABEL_MINE),
    mine_compete    = GetString(SI_GPH_MAPSEARCH_LABEL_MINE),
    mine_incompete  = GetString(SI_GPH_MAPSEARCH_LABEL_MINE),
    mundus          = GetString(SI_GPH_MAPSEARCH_LABEL_MUNDUS_STONE),
    mushromtower    = GetString(SI_GPH_MAPSEARCH_LABEL_MUSHROOM_TOWER),
    portal          = GetString(SI_GPH_MAPSEARCH_LABEL_DOLMEN),
    raiddungeon     = GetString(SI_GPH_MAPSEARCH_LABEL_GROUP_TRIAL),
    ruin            = GetString(SI_GPH_MAPSEARCH_LABEL_RUIN),
    sewer           = GetString(SI_GPH_MAPSEARCH_LABEL_SEWER),
    shrine          = GetString(SI_GPH_MAPSEARCH_LABEL_SHRINE),
    shrine_vampire  = GetString(SI_GPH_MAPSEARCH_LABEL_VAMPIRE_SHRINE),
    shrine_werewolf = GetString(SI_GPH_MAPSEARCH_LABEL_WEREWOLF_SHRINE),
    solotrial       = GetString(SI_GPH_MAPSEARCH_LABEL_SOLO_TRIAL),
    tower           = GetString(SI_GPH_MAPSEARCH_LABEL_TOWER),
    town            = GetString(SI_GPH_MAPSEARCH_LABEL_TOWN),
    transit         = GetString(SI_GPH_MAPSEARCH_LABEL_LIFT),
    lift            = GetString(SI_GPH_MAPSEARCH_LABEL_LIFT),
    nord_boat       = GetString(SI_GPH_MAPSEARCH_LABEL_NORD_BOAT),
    dwemergear      = GetString(SI_GPH_MAPSEARCH_LABEL_LIFT),
    ic_boneshard         = GetString(SI_GPH_MAPSEARCH_LABEL_IMPERIAL_CITY),
    ic_darkether         = GetString(SI_GPH_MAPSEARCH_LABEL_IMPERIAL_CITY),
    ic_tinyclaw          = GetString(SI_GPH_MAPSEARCH_LABEL_IMPERIAL_CITY),
    ic_marklegion        = GetString(SI_GPH_MAPSEARCH_LABEL_IMPERIAL_CITY),
    ic_monstrousteeth    = GetString(SI_GPH_MAPSEARCH_LABEL_IMPERIAL_CITY),
    ic_planararmorscraps = GetString(SI_GPH_MAPSEARCH_LABEL_IMPERIAL_CITY),
    ic_daedricshackles   = GetString(SI_GPH_MAPSEARCH_LABEL_IMPERIAL_CITY),
    ic_daedricembers     = GetString(SI_GPH_MAPSEARCH_LABEL_IMPERIAL_CITY),
    adventurezone_entrance             = GetString(SI_GPH_MAPSEARCH_LABEL_ADVENTURE_ZONE),
    adventurezone_jumppad              = GetString(SI_GPH_MAPSEARCH_LABEL_ADVENTURE_ZONE),
    adventurezone_faction_ruckus       = GetString(SI_GPH_MAPSEARCH_LABEL_ADVENTURE_ZONE),
    adventurezone_faction_thousandeyes = GetString(SI_GPH_MAPSEARCH_LABEL_ADVENTURE_ZONE),
    adventurezone_faction_glittering   = GetString(SI_GPH_MAPSEARCH_LABEL_ADVENTURE_ZONE),
    adventurezone_skirmish             = GetString(SI_GPH_MAPSEARCH_LABEL_ADVENTURE_ZONE),
    adventurezone_contentgrouptimed    = GetString(SI_GPH_MAPSEARCH_LABEL_ADVENTURE_ZONE),
    wayshrine    = GetString(SI_GPH_MAPSEARCH_LABEL_WAYSHRINE),
    icon_missing = GetString(SI_GPH_MAPSEARCH_LABEL_UNKNOWN),
    unknown      = GetString(SI_GPH_MAPSEARCH_LABEL_UNKNOWN),
}

-- Direct label lookup by ESO's poiType enum (avoids icon parsing for unambiguous types).
-- Type 2 is intentionally absent: it covers both Mundus Stones and Great Lifts,
-- so icon parsing is required to tell them apart.
local POI_TYPE_DIRECT = {
    [3] = GetString(SI_GPH_MAPSEARCH_LABEL_DELVE),
    [4] = GetString(SI_GPH_MAPSEARCH_LABEL_DOLMEN),
    [5] = GetString(SI_GPH_MAPSEARCH_LABEL_PUBLIC_DUNGEON),
    [6] = GetString(SI_GPH_MAPSEARCH_LABEL_GROUP_DUNGEON),
    [7] = GetString(SI_GPH_MAPSEARCH_LABEL_HOUSE),
}

local function GetPOITypeLabel(icon, poiType)
    if poiType and POI_TYPE_DIRECT[poiType] then
        return POI_TYPE_DIRECT[poiType]
    end
    -- type 0 and type 2 (Standard / ambiguous) need icon parsing.
    if not icon or icon == "" then return nil end
    local name = (icon:match("([^/]+)%.dds$") or icon)
        :gsub("_complete$",   "")
        :gsub("_incomplete$", "")
        :gsub("_owned$",      "")
        :gsub("_unowned$",    "")
        :gsub("^u%d+_poi_",   "")
        :gsub("^u%d+_",       "")
        :gsub("^poi_",        "")
        :gsub("^u%d+_",       "")
    return POI_TYPE_NAMES[name]
end

-- narration

local function BuildCandidateNarrationText(c, isBookmark)
    local parts = { c.name }
    if isBookmark then parts[#parts + 1] = GetString(SI_GPH_MAPSEARCH_NARRATION_BOOKMARKED) end
    if c.type == TYPE_HOUSE_OWNED or c.type == TYPE_HOUSE_UNOWNED then
        parts[#parts + 1] = c.type == TYPE_HOUSE_UNOWNED and GetString(SI_GPH_MAPSEARCH_NARRATION_UNOWNED) or GetString(SI_GPH_MAPSEARCH_NARRATION_OWNED)
        parts[#parts + 1] = GetString(SI_GPH_MAPSEARCH_LABEL_HOUSE)
    elseif c.type == TYPE_POI then
        if c.isLocked      then parts[#parts + 1] = GetString(SI_GPH_MAPSEARCH_NARRATION_LOCKED)
        elseif not c.known then parts[#parts + 1] = GetString(SI_GPH_MAPSEARCH_NARRATION_UNDISCOVERED) end
        parts[#parts + 1] = c.poiTypeLabel or GetString(SI_GPH_MAPSEARCH_NARRATION_POI)
    elseif c.type == TYPE_ZONE then
        if c.isLocked then parts[#parts + 1] = GetString(SI_GPH_MAPSEARCH_NARRATION_LOCKED) end
        parts[#parts + 1] = GetString(SI_GPH_MAPSEARCH_NARRATION_ZONE)
    elseif c.type == TYPE_LIFT then
        if not c.known     then parts[#parts + 1] = GetString(SI_GPH_MAPSEARCH_NARRATION_UNDISCOVERED)
        elseif c.isLocked  then parts[#parts + 1] = GetString(SI_GPH_MAPSEARCH_NARRATION_LOCKED) end
        parts[#parts + 1] = GetString(SI_GPH_MAPSEARCH_LABEL_LIFT)
    else
        if c.isLocked      then parts[#parts + 1] = GetString(SI_GPH_MAPSEARCH_NARRATION_LOCKED)
        elseif not c.known then parts[#parts + 1] = GetString(SI_GPH_MAPSEARCH_NARRATION_UNDISCOVERED) end
    end
    return table.concat(parts, ", ")
end

-- pre-scan 

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

    local lockedZoneIndex = {}
    for nodeIndex = 1, GetNumFastTravelNodes() do
        local _, _, _, _, _, _, typePOI, _, isLocked = GetFastTravelNodeInfo(nodeIndex)
        if isLocked and typePOI == POI_TYPE_WAYSHRINE then
            local zi = GetFastTravelNodePOIIndicies(nodeIndex)
            if zi then lockedZoneIndex[zi] = true end
        end
    end

    for nodeIndex = 1, GetNumFastTravelNodes() do
        local drawLevelOffset = GetFastTravelNodeDrawLevelOffset(nodeIndex)
        if drawLevelOffset ~= 0 then
            local known, name, _, _, _, _, typePOI, _, isLocked = GetFastTravelNodeInfo(nodeIndex)
            local isWayshrine = typePOI == POI_TYPE_WAYSHRINE
            local isHouse     = typePOI == POI_TYPE_HOUSE
            if isWayshrine or isHouse then
                local zoneIndex, poiIndex = GetFastTravelNodePOIIndicies(nodeIndex)
                local zoneId = GetZoneId(zoneIndex)
                local _, _, _, poiIcon = GetPOIMapInfo(zoneIndex, poiIndex)
                local defaultIcon = known and ICON_WAYSHRINE_KNOWN or ICON_WAYSHRINE_UNKNOWN
                local icon = (poiIcon and poiIcon ~= "") and poiIcon or defaultIcon
                -- HasCompletedFastTravelNodePOI is how ESO itself determines house ownership.
                local isOwnedHouse = isHouse and HasCompletedFastTravelNodePOI(nodeIndex)
                local houseId      = isHouse and GetFastTravelNodeHouseId(nodeIndex) or nil
                local mapPriority  = GetFastTravelNodeMapPriority(nodeIndex) or 0
                data.wayshrines[#data.wayshrines + 1] = {
                    name         = CleanName(name),
                    icon         = icon,
                    nodeIndex    = nodeIndex,
                    zoneIndex    = zoneIndex,
                    zoneId       = zoneId,
                    poiIndex     = poiIndex,
                    mapIndex     = zoneToMap[zoneIndex],
                    zoneName     = CleanName(GetZoneNameById(zoneId)),
                    known        = known,
                    isLocked     = isLocked,
                    isHouse      = isHouse,
                    isOwnedHouse = isOwnedHouse,
                    houseId      = houseId,
                    mapPriority  = mapPriority,
                }
            end
        end
    end

    local seenZone = {}
    for mapIndex = 1, GetNumMaps() do
        local mapName, mapType, _, zoneIndex = GetMapInfoByIndex(mapIndex)
        if mapName ~= "" and zoneIndex and zoneIndex > 0 then
            local zoneId = GetZoneId(zoneIndex)
            if not seenZone[zoneId] and (mapType == MAPTYPE_ZONE or mapType == MAPTYPE_WORLD) then
                seenZone[zoneId] = true
                local cleanZoneName = CleanName(mapName)
                data.zones[#data.zones + 1] = {
                    name      = cleanZoneName,
                    zoneId    = zoneId,
                    zoneIndex = zoneIndex,
                    mapIndex  = mapIndex,
                    isLocked  = lockedZoneIndex[zoneIndex] or false,
                }
                nameToZoneId[cleanZoneName] = zoneId
            end
        end
    end

    local seenPOI = {}
    for mapIndex = 1, GetNumMaps() do
        local _, _, _, zoneIndex = GetMapInfoByIndex(mapIndex)
        if zoneIndex and zoneIndex > 0 then
            local zoneId   = GetZoneId(zoneIndex)
            local zoneName = CleanName(GetZoneNameById(zoneId))
            for poiIndex = 1, GetNumPOIs(zoneIndex) do
                local uid = zoneIndex .. ":" .. poiIndex
                if not seenPOI[uid] then
                    seenPOI[uid] = true
                    local name = GetPOIInfo(zoneIndex, poiIndex)
                    if name and name ~= "" then
                        local _, _, _, icon, _, collectibleLocked, isDiscovered = GetPOIMapInfo(zoneIndex, poiIndex)
                        local poiType = GetPOIType(zoneIndex, poiIndex)
                        if not icon or not icon:find("wayshrine") then
                            local poiIcon  = (icon and icon ~= "") and icon or nil
                            local isLocked = collectibleLocked or lockedZoneIndex[zoneIndex] or false
                            data.pois[#data.pois + 1] = {
                                name      = CleanName(name),
                                icon      = poiIcon or ICON_POI_GENERIC,
                                -- Only _owned suffix means you own it; _complete/_incomplete do not.
                                isOwned   = poiIcon ~= nil and poiIcon:find("_owned") ~= nil and poiIcon:find("_unowned") == nil,
                                poiType   = poiType,
                                zoneIndex = zoneIndex,
                                zoneId    = zoneId,
                                poiIndex  = poiIndex,
                                mapIndex  = zoneToMap[zoneIndex],
                                zoneName  = zoneName,
                                known     = isDiscovered,
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
    lastSearchTerm = nil
end

-- candidates

local function FindNearestWayshrineToPos(px, py, minDist, filterZoneIndex)
    if not px or not py or px == 0 then return nil end
    local bestNode, bestDist = nil, math.huge
    for nodeIndex = 1, GetNumFastTravelNodes() do
        local known, _, wsNx, wsNy, _, _, typePOI, _, isLocked = GetFastTravelNodeInfo(nodeIndex)
        if known and not isLocked and typePOI == POI_TYPE_WAYSHRINE and wsNx and wsNy then
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

local function FindBestDiscoveredWayshrineFromScan(candidate)
    -- scannedData is freed after BuildCandidates; search the candidates list instead.
    local list = candidates
    if not list then return nil end

    local filterZoneId    = candidate and candidate.zoneId
    local filterZoneIndex = candidate and candidate.zoneIndex
    local filterZoneName  = candidate and candidate.name and candidate.name:lower() or nil

    local function pickBest(matchFn)
        local bestNode     = nil
        local bestPriority = -math.huge
        for _, c in ipairs(list) do
            if c.type == TYPE_WAYSHRINE and c.nodeIndex and c.known and not c.isLocked and matchFn(c) then
                local prio = c.mapPriority or 0
                if prio > bestPriority then
                    bestPriority = prio
                    bestNode = c.nodeIndex
                end
            end
        end
        return bestNode
    end

    if filterZoneId then
        local byZoneId = pickBest(function(c) return c.zoneId == filterZoneId end)
        if byZoneId then return byZoneId end
    end

    if filterZoneIndex then
        local byZoneIndex = pickBest(function(c) return c.zoneIndex == filterZoneIndex end)
        if byZoneIndex then return byZoneIndex end
    end

    if filterZoneName and filterZoneName ~= "" then
        local byZoneName = pickBest(function(c)
            return c.zoneName and c.zoneName:lower() == filterZoneName
        end)
        if byZoneName then return byZoneName end
    end

    return nil
end

local function BuildCandidates()
    if not scannedData then PreScan() end

    local nameToZoneId = scannedData.nameToZoneId
    local list = {}
    local ownedHouseByKey = {}
    local ownedHouseByName = {}

    for _, ws in ipairs(scannedData.wayshrines) do
        if ws.isHouse and ws.isOwnedHouse and ws.houseId and ws.name then
            local key = (ws.name:lower()) .. "|" .. tostring(ws.zoneId or 0)
            ownedHouseByKey[key] = ws
            ownedHouseByName[ws.name:lower()] = ownedHouseByName[ws.name:lower()] or ws
        end
        list[#list + 1] = {
            name        = ws.name,
            searchName  = ws.name:lower(),
            type        = ws.isHouse and (ws.isOwnedHouse and TYPE_HOUSE_OWNED or TYPE_HOUSE_UNOWNED)
                       or TYPE_WAYSHRINE,
            icon        = ws.icon,
            nodeIndex   = ws.nodeIndex,
            zoneId      = ws.zoneId,
            zoneIndex   = ws.zoneIndex,
            poiIndex    = ws.poiIndex,
            mapIndex    = ws.mapIndex,
            zoneName    = ws.zoneName,
            known       = ws.known,
            isLocked    = ws.isLocked,
            houseId     = ws.houseId,
            mapPriority = ws.mapPriority,
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
        local poiTypeLabel = GetPOITypeLabel(poi.icon, poi.poiType)
        local isHousePOI   = poiTypeLabel == GetString(SI_GPH_MAPSEARCH_LABEL_HOUSE)
        local matchedOwnedHouse = nil
        if isHousePOI and poi.isOwned and poi.name then
            local key = (poi.name:lower()) .. "|" .. tostring(poi.zoneId or 0)
            matchedOwnedHouse = ownedHouseByKey[key] or ownedHouseByName[poi.name:lower()]
        end
        local entryType = isHousePOI
            and (poi.isOwned and TYPE_HOUSE_OWNED or TYPE_HOUSE_UNOWNED)
            or TYPE_POI

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
                nodeIndex    = matchedOwnedHouse and matchedOwnedHouse.nodeIndex or nil,
                houseId      = matchedOwnedHouse and matchedOwnedHouse.houseId or nil,
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
                nodeIndex    = matchedOwnedHouse and matchedOwnedHouse.nodeIndex or nil,
                houseId      = matchedOwnedHouse and matchedOwnedHouse.houseId or nil,
                known        = poi.known,
                isLocked     = poi.isLocked,
            }
        end
    end

    scannedData = nil  -- free raw scan data; candidates table has everything needed
    return list
end

-- search

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

    term = term or ""
    if term == lastSearchTerm then return end
    lastSearchTerm = term

    local termLower = term:lower()
    local scored    = {}

    for i = 1, #candidates do
        local c = candidates[i]
        local s = ScoreMatch(c.searchName, termLower)
        if s > 0 then scored[#scored + 1] = { score = s, c = c } end
    end

    table.sort(scored, function(a, b)
        if a.score ~= b.score   then return a.score > b.score end
        if a.c.type ~= b.c.type then return a.c.type < b.c.type end
        return a.c.searchName < b.c.searchName
    end)

    results = {}
    for i = 1, math.min(#scored, 60) do
        results[#results + 1] = scored[i].c
    end
end

-- list

local function GetCandidateSubText(c)
    local parts = {}
    if c.zoneName and c.zoneName ~= "" then
        parts[#parts + 1] = c.zoneName
    end
    if c.type == TYPE_POI and c.poiTypeLabel then
        parts[#parts + 1] = c.poiTypeLabel
    elseif c.type == TYPE_WAYSHRINE then
        local mp = c.mapPriority or 0
        if mp >= 2 then
            parts[#parts + 1] = GetString(SI_GPH_MAPSEARCH_LABEL_WAYSHRINE_CAPITAL)
        elseif mp == 1 then
            parts[#parts + 1] = GetString(SI_GPH_MAPSEARCH_LABEL_WAYSHRINE_MAJOR)
        else
            parts[#parts + 1] = GetString(SI_GPH_MAPSEARCH_LABEL_WAYSHRINE)
        end
    elseif c.type == TYPE_HOUSE_OWNED or c.type == TYPE_HOUSE_UNOWNED then
        parts[#parts + 1] = GetString(SI_GPH_MAPSEARCH_LABEL_HOUSE)
    elseif c.type == TYPE_LIFT then
        parts[#parts + 1] = GetString(SI_GPH_MAPSEARCH_LABEL_LIFT)
    elseif c.type == TYPE_ZONE then
        parts[#parts + 1] = GetString(SI_GPH_MAPSEARCH_NARRATION_ZONE)
    end
    return #parts > 0 and table.concat(parts, " - ") or nil
end

local function ResolveOwnedHouseId(candidate)
    if not candidate then return nil end
    if candidate.houseId and candidate.houseId ~= 0 then
        return candidate.houseId
    end
    if candidate.nodeIndex then
        local hid = GetFastTravelNodeHouseId(candidate.nodeIndex)
        if hid and hid ~= 0 then return hid end
    end
    local targetName = candidate.name and candidate.name:lower()
    if not targetName then return nil end
    for nodeIndex = 1, GetNumFastTravelNodes() do
        local known, name, _, _, _, _, typePOI, _, _ = GetFastTravelNodeInfo(nodeIndex)
        if known and typePOI == POI_TYPE_HOUSE and name and name:lower() == targetName then
            local hid = GetFastTravelNodeHouseId(nodeIndex)
            if hid and hid ~= 0 and HasCompletedFastTravelNodePOI(nodeIndex) then
                return hid
            end
        end
    end
    return nil
end

local function GetCandidateCostSubText(c)
    -- Cost display moved to a dedicated top label below search box.
    return nil
end

local cachedRecallNode = nil

local function FindRecallNode()
    if not GetRecallCost then return nil end
    for nodeIndex = 1, GetNumFastTravelNodes() do
        local known, _, _, _, _, _, typePOI, _, isLocked = GetFastTravelNodeInfo(nodeIndex)
        if known and not isLocked and typePOI == POI_TYPE_WAYSHRINE then
            return nodeIndex
        end
    end
    return nil
end

local function GetStableRecallCost()
    if GetInteractionType and GetInteractionType() == INTERACTION_FAST_TRAVEL then
        return 0
    end
    if not GetRecallCost then return 0 end
    if not cachedRecallNode then
        cachedRecallNode = FindRecallNode()
    end
    return cachedRecallNode and (GetRecallCost(cachedRecallNode) or 0) or 0
end

local function FormatRecallCostAmount(cost)
    local canAfford = cost == 0 or cost <= GetCurrencyAmount(CURT_MONEY, CURRENCY_LOCATION_CHARACTER)
    local coloredNum = (canAfford and "|cFFFFFF" or "|cff4444") .. ZO_CommaDelimitNumber(cost) .. "|r"
    return zo_strformat(SI_GPH_MAPSEARCH_RECALL_COST_AMOUNT, coloredNum)
end

local function UpdateRecallCostLabel()
    if not recallCostLabel then return end
    recallCostLabel:SetText(FormatRecallCostAmount(GetStableRecallCost()))
end

local function StopListCostLoop()
    listCostLoopId = listCostLoopId + 1
end

local function StartListCostLoop()
    StopListCostLoop()
    local myId = listCostLoopId
    local function loop()
        if listCostLoopId ~= myId or not IsFragmentShowing() then return end
        UpdateRecallCostLabel()
        zo_callLater(loop, 1000)
    end
    zo_callLater(loop, 1000)
end


local CAT_NAMES = {
    [TYPE_WAYSHRINE]     = GetString(SI_GPH_MAPSEARCH_GROUP_WAYSHRINES),
    [TYPE_LIFT]          = GetString(SI_GPH_MAPSEARCH_GROUP_LIFTS),
    [TYPE_ZONE]          = GetString(SI_GPH_MAPSEARCH_GROUP_ZONES),
    [TYPE_POI]           = GetString(SI_GPH_MAPSEARCH_GROUP_LOCATIONS),
    [TYPE_HOUSE_OWNED]   = GetString(SI_GPH_MAPSEARCH_GROUP_OWNED_HOUSES),
    [TYPE_HOUSE_UNOWNED] = GetString(SI_GPH_MAPSEARCH_GROUP_UNOWNED_HOUSES),
}

local function BuildListEntryData(c, displayName, isBookmarked, narrationBookmark)
    local entryData = ZO_GamepadEntryData:New(displayName or c.name, c.icon)
    entryData.candidate     = c
    entryData.narrationText = BuildCandidateNarrationText(c, narrationBookmark == true)
    entryData:SetIconTintOnSelection(true)
    entryData:SetShowUnselectedSublabels(true)
    if isBookmarked then
        entryData.isBookmark = true
    end
    if c.isLocked then
        entryData:AddIcon("EsoUI/Art/Miscellaneous/status_locked.dds")
    end
    local sub = GetCandidateSubText(c)
    if sub then entryData:AddSubLabel(sub) end
    local costSub = GetCandidateCostSubText(c)
    if costSub then entryData:AddSubLabel(costSub) end
    return entryData
end

RebuildList = function()
    if not listObject then return end
    local rowIndex = 0
    listObject:Clear()

    local bookmarks = GetBookmarksArray()
    local bookmarkedByKey = {}
    for _, bm in ipairs(bookmarks) do
        bookmarkedByKey[GetBookmarkKey(bm)] = true
    end

    if currentTerm == "" then
        for i, bm in ipairs(bookmarks) do
            local entryData = BuildListEntryData(bm, bm.name, true, true)
            rowIndex = rowIndex + 1
            if i == 1 then
                entryData:SetHeader(GetString(SI_GPH_MAPSEARCH_GROUP_BOOKMARKS))
                listObject:AddEntryWithHeader("ZO_GamepadMenuEntryTemplateLowercase34", entryData)
            else
                listObject:AddEntry("ZO_GamepadMenuEntryTemplateLowercase34", entryData)
            end
        end

        -- Owned houses below bookmarks when no search term
        if candidates then
            local bookmarkKeys = {}
            for _, bm in ipairs(bookmarks) do bookmarkKeys[GetBookmarkKey(bm)] = true end
            local firstHouse = true
            for _, c in ipairs(candidates) do
                if c.type == TYPE_HOUSE_OWNED and not bookmarkKeys[GetBookmarkKey(c)] then
                    local entryData = BuildListEntryData(c, c.name, false, false)
                    rowIndex = rowIndex + 1
                    if firstHouse then
                        firstHouse = false
                        entryData:SetHeader(GetString(SI_GPH_MAPSEARCH_GROUP_OWNED_HOUSES))
                        listObject:AddEntryWithHeader("ZO_GamepadMenuEntryTemplateLowercase34", entryData)
                    else
                        listObject:AddEntry("ZO_GamepadMenuEntryTemplateLowercase34", entryData)
                    end
                end
            end
        end
    elseif #results > 0 then
        local sv = GetSavedVars()
        local groupByLocation = sv and sv.mapSearchGroupByLocation == true

        if groupByLocation then
            local groupedByLocation = {}
            local locationOrder = {}
            for _, c in ipairs(results) do
                local key = (c.zoneName and c.zoneName ~= "") and c.zoneName or GetString(SI_GPH_MAPSEARCH_GROUP_OTHER)
                if not groupedByLocation[key] then
                    groupedByLocation[key] = {}
                    locationOrder[#locationOrder + 1] = key
                end
                groupedByLocation[key][#groupedByLocation[key] + 1] = c
            end

            for _, location in ipairs(locationOrder) do
                local bucket = groupedByLocation[location]
                local firstInLocation = true
                for _, c in ipairs(bucket) do
                    local isBookmarked = bookmarkedByKey[GetBookmarkKey(c)] == true
                    local displayName = isBookmarked
                        and zo_iconTextFormat("EsoUI/Art/Collections/Favorite_StarOnly.dds", 24, 24, c.name)
                        or c.name
                    local entryData = BuildListEntryData(c, displayName, false, isBookmarked)
                    rowIndex = rowIndex + 1
                    if firstInLocation then
                        firstInLocation = false
                        entryData:SetHeader(location)
                        listObject:AddEntryWithHeader("ZO_GamepadMenuEntryTemplateLowercase34", entryData)
                    else
                        listObject:AddEntry("ZO_GamepadMenuEntryTemplateLowercase34", entryData)
                    end
                end
            end
        else
            local grouped = {}
            for _, c in ipairs(results) do
                if not grouped[c.type] then grouped[c.type] = {} end
                grouped[c.type][#grouped[c.type] + 1] = c
            end
            local typeOrder = {
                TYPE_WAYSHRINE,
                TYPE_LIFT,
                TYPE_ZONE,
                TYPE_POI,
                TYPE_HOUSE_OWNED,
                TYPE_HOUSE_UNOWNED,
            }
            for _, t in ipairs(typeOrder) do
                local bucket = grouped[t]
                if bucket and #bucket > 0 then
                    local firstInType = true
                    for _, c in ipairs(bucket) do
                        local isBookmarked = bookmarkedByKey[GetBookmarkKey(c)] == true
                        local displayName = isBookmarked
                            and zo_iconTextFormat("EsoUI/Art/Collections/Favorite_StarOnly.dds", 24, 24, c.name)
                            or c.name
                        local entryData = BuildListEntryData(c, displayName, false, isBookmarked)
                        rowIndex = rowIndex + 1
                        if firstInType then
                            firstInType = false
                            entryData:SetHeader(CAT_NAMES[c.type] or GetString(SI_GPH_MAPSEARCH_GROUP_OTHER))
                            listObject:AddEntryWithHeader("ZO_GamepadMenuEntryTemplateLowercase34", entryData)
                        else
                            listObject:AddEntry("ZO_GamepadMenuEntryTemplateLowercase34", entryData)
                        end
                    end
                end
            end
        end
    end

    listObject:Commit()

    local numItems = listObject:GetNumItems()
    if numItems > 0 then
        lastSelectedIndex = zo_clamp(lastSelectedIndex, 1, numItems)
        listObject:SetSelectedIndex(lastSelectedIndex)
    end

    UpdateKeybinds()
end

-- map interaction

local postTeleportDestination = nil

local function AddMapPin(x, y)
    local sv = GetSavedVars()
    if sv ~= nil and sv.mapSearchMapPin == false then return end
    local pinMgr = ZO_WorldMap_GetPinManager and ZO_WorldMap_GetPinManager()
    if not pinMgr then return end
    pinMgr:RemovePins("pings")
    pinMgr:CreatePin(MAP_PIN_TYPE_AUTO_MAP_NAVIGATION_PING, "pings", x, y)
end


local function StorePostTeleportDestination(c)
    local sv = GetSavedVars()
    if sv ~= nil and sv.mapSearchSetDestination == false then return end
    if c.zoneIndex and c.poiIndex then
        local nx, ny = GetPOIMapInfo(c.zoneIndex, c.poiIndex)
        if nx and nx > 0 then
            postTeleportDestination = { x = nx, y = ny }
            return
        end
    end
    if c.nodeIndex then
        local _, _, nx, ny = GetFastTravelNodeInfo(c.nodeIndex)
        if nx and nx > 0 then
            postTeleportDestination = { x = nx, y = ny }
        end
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
                AddMapPin(nx, ny)
                return
            end
        end
        if c.type == TYPE_WAYSHRINE and c.nodeIndex then
            local _, _, nx, ny = GetFastTravelNodeInfo(c.nodeIndex)
            if nx and nx > 0 then
                AddMapPin(nx, ny)
            end
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

-- keybinds

local function BuildKeybindDescriptor()
    keybindDescriptor = {
        alignment = KEYBIND_STRIP_ALIGN_LEFT,
        {
            keybind  = "UI_SHORTCUT_PRIMARY",
            name     = function()
                if editControl and editControl:HasFocus() then return GetString(SI_GPH_MAPSEARCH_KEYBIND_DONE) end
                local td = listObject and listObject:GetTargetData()
                return (td and td.candidate) and GetString(SI_GPH_MAPSEARCH_KEYBIND_SHOW_ON_MAP) or GetString(SI_GPH_MAPSEARCH_KEYBIND_DONE)
            end,
            callback = function()
                if editControl and editControl:HasFocus() then
                    editControl:LoseFocus()
                    if listObject and IsFragmentShowing() then
                        listObject:SetSelectedIndex(1)
                        listObject:Activate()
                    end
                    return
                end
                local td = listObject and listObject:GetTargetData()
                if td and td.candidate then
                    if not GamePadHelperSavedVars then GamePadHelperSavedVars = {} end
                    GamePadHelperSavedVars.lastSelectedPOI = td.candidate
                    CenterMapOnCandidate(td.candidate)
                    local keybindName = ZO_Keybindings_GetBindingStringFromAction("UI_SHORTCUT_QUINARY") or GetString(SI_GPH_TELEPORT)
                    pendingNarration = BuildCandidateNarrationText(td.candidate, td.isBookmark) .. ". " .. zo_strformat(SI_GPH_MAPSEARCH_SHOWN_ON_MAP, keybindName)
                    SCREEN_NARRATION_MANAGER:QueueCustomEntry("GPH_MapSearch_Narration")
                end
            end,
            visible  = function()
                if editControl and editControl:HasFocus() then return true end
                local td = listObject and listObject:GetTargetData()
                return td ~= nil and td.candidate ~= nil
            end,
        },
        {
            -- In text mode: X = Clear (clears text, stays in search box)
            -- In list mode: X = Search (opens text mode)
            keybind  = "UI_SHORTCUT_SECONDARY",
            name     = function()
                return (editControl and editControl:HasFocus()) and GetString(SI_GPH_MAPSEARCH_CLEAR) or GetString(SI_SCREEN_NARRATION_EDIT_BOX_SEARCH_NAME)
            end,
            callback = function()
                if editControl and editControl:HasFocus() then
                    currentTerm = ""
                    editControl:SetText("")
                    results = {}
                    RebuildList()
                    pendingNarration = GetString(SI_GPH_MAPSEARCH_SEARCH_CLEARED)
                    SCREEN_NARRATION_MANAGER:QueueCustomEntry("GPH_MapSearch_Narration")
                else
                    if editControl then editControl:TakeFocus() end
                end
            end,
            visible  = function() return IsFragmentShowing() end,
        },
        {
            keybind  = "UI_SHORTCUT_QUATERNARY",
            name     = function()
                local td = listObject and listObject:GetTargetData()
                if td and td.candidate then
                    return IsBookmarked(td.candidate) and GetString(SI_GPH_MAPSEARCH_UNBOOKMARK) or GetString(SI_GPH_MAPSEARCH_BOOKMARK)
                end
                return GetString(SI_GPH_MAPSEARCH_BOOKMARK)
            end,
            callback = function()
                local td = listObject and listObject:GetTargetData()
                if not td or not td.candidate then return end
                local c = td.candidate
                local idx = listObject:GetSelectedIndex()
                if IsBookmarked(c) then
                    ZO_Dialogs_ShowGamepadDialog("GPH_UNBOOKMARK_CONFIRM", c)
                else
                    AddBookmark(c)
                    pendingNarration = zo_strformat(SI_GPH_MAPSEARCH_BOOKMARKED, c.name)
                    SCREEN_NARRATION_MANAGER:QueueCustomEntry("GPH_MapSearch_Narration")
                    RunSearch(currentTerm)
                    RebuildList()
                    if idx and idx > 0 and listObject:GetNumItems() > 0 then
                        listObject:SetSelectedIndex(zo_clamp(idx, 1, listObject:GetNumItems()))
                    end
                end
            end,
            visible  = function()
                if editControl and editControl:HasFocus() then return false end
                local td = listObject and listObject:GetTargetData()
                return td ~= nil and td.candidate ~= nil
            end,
        },
        {
            keybind  = "UI_SHORTCUT_QUINARY",
            name     = function()
                local td = listObject and listObject:GetTargetData()
                if td and td.candidate then
                    local c = td.candidate
                    if (c.type == TYPE_WAYSHRINE and c.known and not c.isLocked)
                    or c.type == TYPE_HOUSE_OWNED then
                        return GetString(SI_GPH_TELEPORT)
                    end
                end
                return GetString(SI_GPH_MAPSEARCH_TELEPORT_NEAREST)
            end,
            enabled  = function()
                local td = listObject and listObject:GetTargetData()
                if td and td.candidate then
                    local c = td.candidate
                    -- Keep enabled for wayshrines locked by DLC/chapter so pressing opens the shop
                    if c.isLocked and not c.nodeIndex then return false end
                end
                return true
            end,
            visible  = function()
                if editControl and editControl:HasFocus() then return false end
                local td = listObject and listObject:GetTargetData()
                return td ~= nil and td.candidate ~= nil
            end,
            callback = function()
                local td = listObject and listObject:GetTargetData()
                if not td or not td.candidate then return end
                local c = td.candidate

                if not GamePadHelperSavedVars then GamePadHelperSavedVars = {} end
                GamePadHelperSavedVars.lastSelectedPOI = c

                if c.isLocked then
                    local collectibleData
                    if c.nodeIndex then
                        local collectibleId = GetFastTravelNodeLinkedCollectibleId(c.nodeIndex)
                        collectibleData     = ZO_COLLECTIBLE_DATA_MANAGER:GetCollectibleDataById(collectibleId)
                    end
                    if collectibleData then
                        ZO_Dialogs_ShowCollectibleRequirementFailedPlatformDialog(collectibleData, c.name, MARKET_OPEN_OPERATION_DLC_FAILURE_TELEPORT_TO_ZONE)
                    else
                        ZO_Alert(UI_ALERT_CATEGORY_ERROR, SOUNDS.NEGATIVE_CLICK, GetString(SI_GPH_MAPSEARCH_ZONE_LOCKED))
                    end
                    return
                end

                if c.type == TYPE_HOUSE_OWNED then
                    local houseId = ResolveOwnedHouseId(c)
                    if houseId then c.houseId = houseId end
                    if not CanJumpToHouseFromCurrentLocation() then
                        ZO_Alert(UI_ALERT_CATEGORY_ERROR, SOUNDS.NEGATIVE_CLICK, GetString(SI_GPH_MAPSEARCH_NO_HOUSE_TRAVEL))
                        return
                    end
                    if not c.houseId then
                        ZO_Alert(UI_ALERT_CATEGORY_ERROR, SOUNDS.NEGATIVE_CLICK, GetString(SI_GPH_MAPSEARCH_NO_HOUSE_TRAVEL))
                        return
                    end
                    ZO_Dialogs_ShowGamepadDialog("GAMEPAD_TRAVEL_TO_HOUSE_OPTIONS_DIALOG", { GetReferenceId = function() return c.houseId end })
                    return
                end

                local nodeIndex, failReason = nil, nil
                if c.type == TYPE_WAYSHRINE and c.known then
                    nodeIndex = c.nodeIndex
                elseif c.type == TYPE_ZONE and c.zoneId then
                    nodeIndex = FindBestDiscoveredWayshrineFromScan(c)
                    if not nodeIndex then failReason = GetString(SI_GPH_MAPSEARCH_NARRATION_UNDISCOVERED) end
                elseif c.zoneIndex and c.poiIndex then
                    local nx, ny = GetPOIMapInfo(c.zoneIndex, c.poiIndex)
                    if nx and ny then
                        nodeIndex = FindNearestWayshrineToPos(nx, ny, 0, c.zoneIndex)
                    end
                    if not nodeIndex then failReason = GetString(SI_GPH_MAPSEARCH_NARRATION_UNDISCOVERED) end
                elseif c.nodeIndex then
                    nodeIndex = c.nodeIndex
                end

                if not nodeIndex then
                    local msg = failReason == GetString(SI_GPH_MAPSEARCH_NARRATION_LOCKED)
                        and GetString(SI_GPH_MAPSEARCH_ZONE_LOCKED)
                        or  GetString(SI_GPH_MAPSEARCH_NO_DISCOVERED_WAYSHRINE)
                    ZO_Alert(UI_ALERT_CATEGORY_ERROR, SOUNDS.NEGATIVE_CLICK, msg)
                    return
                end

                local atWayshrine = GetInteractionType() == INTERACTION_FAST_TRAVEL
                local cost = (not atWayshrine) and GetRecallCost(nodeIndex) or 0
                StorePostTeleportDestination(c)
                if cost > 0 then
                    ZO_Dialogs_ShowGamepadDialog("GPH_TELEPORT_CONFIRM", {
                        nodeIndex = nodeIndex,
                        candidate = c,
                        name      = c.name,
                        cost      = cost,
                    })
                else
                    local sv = GetSavedVars()
                    if sv == nil or sv.mapSearchNarratePostTeleport ~= false then
                        postTeleportMsg = zo_strformat(SI_GPH_MAPSEARCH_TELEPORTED_TO, c.name)
                    end
                    FastTravelToNode(nodeIndex)
                    ZO_WorldMap_HideWorldMap()
                end
            end,
        },
    }

    ZO_Gamepad_AddBackNavigationKeybindDescriptors(keybindDescriptor, GAME_NAVIGATION_TYPE_BUTTON, function()
        if editControl and editControl:HasFocus() then
            editControl:LoseFocus()
        elseif GAMEPAD_WORLD_MAP_INFO then
            GAMEPAD_WORLD_MAP_INFO:Hide()
        end
    end)

    ZO_Gamepad_AddListTriggerKeybindDescriptors(keybindDescriptor, listObject)
end

-- XML callbacks

function GPH_MapSearch_OnShown(edit)
    editControl = edit
    edit:SetDefaultText(GetString(SI_GPH_MAPSEARCH_SEARCH_HINT))
    edit:SetHandler("OnKeyDown", function(_, key)
        if key == KEY_GAMEPAD_DPAD_LEFT then
            edit:LoseFocus()
        end
    end)
    RunSearch(currentTerm)
    RebuildList()
    UpdateRecallCostLabel()
end

function GPH_MapSearch_OnTextChanged(text)
    if not IsFragmentShowing() then return end
    currentTerm = text or ""
    if currentTerm ~= "" then RunSearch(currentTerm) else results = {} end
    RebuildList()
end

function GPH_MapSearch_OnSearchFocused(focused)
    if searchBarBG then searchBarBG:SetHidden(not focused) end
    if listObject then
        if focused then
            listObject:Deactivate()
        elseif IsFragmentShowing() then
            listObject:Activate()
        end
    end
    UpdateKeybinds()
    if focused then
        local label = currentTerm ~= "" and (zo_strformat(SI_GPH_MAPSEARCH_SEARCHING_FOR, currentTerm)) or GetString(SI_GPH_MAPSEARCH_SEARCH_READY)
        pendingNarration = label .. ". " .. GetString(SI_GPH_MAPSEARCH_FILTER_HINT)
        SCREEN_NARRATION_MANAGER:QueueCustomEntry("GPH_MapSearch_Narration")
    end
end

function GPH_MapSearch_SelectCurrent()
    if not IsFragmentShowing() then return end
    if editControl and editControl:HasFocus() then editControl:LoseFocus() end
    local td = listObject and listObject:GetTargetData()
    if td and td.candidate then
        if not GamePadHelperSavedVars then GamePadHelperSavedVars = {} end
        GamePadHelperSavedVars.lastSelectedPOI = td.candidate
        CenterMapOnCandidate(td.candidate)
    end
end

-- UI init

local function InitList(control)
    local listCtrl = control:GetNamedChild("Main"):GetNamedChild("List")
    listObject = ZO_GamepadVerticalParametricScrollList:New(listCtrl)
    listObject:SetAlignToScreenCenter(true)

    listObject:AddDataTemplate(
        "ZO_GamepadMenuEntryTemplateLowercase34",
        ZO_SharedGamepadEntry_OnSetup,
        ZO_GamepadMenuEntryTemplateParametricListFunction)
    listObject:AddDataTemplateWithHeader(
        "ZO_GamepadMenuEntryTemplateLowercase34",
        ZO_SharedGamepadEntry_OnSetup,
        ZO_GamepadMenuEntryTemplateParametricListFunction,
        nil, "ZO_GamepadMenuEntryHeaderTemplate")

    listObject:SetOnTargetDataChangedCallback(function()
        local idx = listObject:GetSelectedIndex()
        if idx and idx > 0 then lastSelectedIndex = idx end
        UpdateKeybinds()
        if not (editControl and editControl:HasFocus()) then
            SCREEN_NARRATION_MANAGER:QueueCustomEntry("GPH_MapSearch_Narration")
        end
        local td = listObject:GetTargetData()
        local c = td and td.candidate
        if c then
        else
            ZO_WorldMap_HideAllTooltips()
        end
    end)
end

local function InsertMapSearchTab()
    if GPH_SEARCH_TAB_INSERTED then return end
    local sv = GetSavedVars()
    if sv ~= nil and sv.mapSearchEnabled == false then return end

    local mapInfo = GAMEPAD_WORLD_MAP_INFO
    if not mapInfo or not mapInfo.tabBarEntries or not mapInfo.header then return end

    local control = GPH_MapSearch_Gamepad
    if not control then return end

    InitList(control)

    local searchBar = control:GetNamedChild("Main"):GetNamedChild("SearchBar")
    searchBarBG     = searchBar:GetNamedChild("BG")
    local recallRow   = control:GetNamedChild("Main"):GetNamedChild("RecallRow")
    local recallTitle = recallRow and recallRow:GetNamedChild("RecallCostTitle") or nil
    if recallTitle then recallTitle:SetText(GetString(SI_GPH_MAPSEARCH_RECALL_COST)) end
    recallCostLabel = recallRow and recallRow:GetNamedChild("RecallCostValue") or nil
    UpdateRecallCostLabel()

    BuildKeybindDescriptor()

    GPH_SEARCH_FRAGMENT = ZO_SimpleSceneFragment:New(control)

    SCREEN_NARRATION_MANAGER:RegisterCustomObject("GPH_MapSearch_Narration", {
        narrationType = NARRATION_TYPE_UI_INTERACTIONS,
        canNarrate    = function() return IsFragmentShowing() end,
        selectedNarrationFunction = function()
            local narrations = {}
            if pendingNarration then
                ZO_AppendNarration(narrations, SCREEN_NARRATION_MANAGER:CreateNarratableObject(pendingNarration))
                pendingNarration = nil
                return narrations
            end
            local td = listObject and listObject:GetTargetData()
            local text = td and (td.narrationText or (td.candidate and BuildCandidateNarrationText(td.candidate, td.isBookmark)))
            if not text then
                text = currentTerm ~= "" and (zo_strformat(SI_GPH_MAPSEARCH_SEARCHING_FOR, currentTerm)) or GetString(SI_GPH_MAPSEARCH_SEARCH_LOCATIONS)
            end
            ZO_AppendNarration(narrations, SCREEN_NARRATION_MANAGER:CreateNarratableObject(text))
            return narrations
        end,
    })

    GPH_SEARCH_FRAGMENT:RegisterCallback("StateChange", function(_, newState)
        if newState == SCENE_SHOWING then
            if _G["GamePadHelper_MapTeleporter_SetSuppressed"] then
                _G["GamePadHelper_MapTeleporter_SetSuppressed"](true)
            end
            RunSearch(currentTerm)
            RebuildList()
            UpdateRecallCostLabel()
            StartListCostLoop()
            if listObject then
                listObject:Activate()
                local numItems = listObject:GetNumItems()
                if numItems > 0 then
                    listObject:SetSelectedIndex(zo_clamp(lastSelectedIndex, 1, numItems))
                end
                listObject:RefreshVisible()
            end
            KEYBIND_STRIP:AddKeybindButtonGroup(keybindDescriptor)
            UpdateKeybinds()
            SCREEN_NARRATION_MANAGER:QueueCustomEntry("GPH_MapSearch_Narration")
        elseif newState == SCENE_HIDING or newState == SCENE_HIDDEN then
            if listObject then
                local idx = listObject:GetSelectedIndex()
                if idx and idx > 0 then lastSelectedIndex = idx end
                listObject:Deactivate()
            end
            KEYBIND_STRIP:RemoveKeybindButtonGroup(keybindDescriptor)
            if editControl then editControl:LoseFocus() end
            pendingNarration = nil
            StopListCostLoop()
            if _G["GamePadHelper_MapTeleporter_SetSuppressed"] then
                _G["GamePadHelper_MapTeleporter_SetSuppressed"](false)
            end
        end
    end)

    local bmuActive = BMU ~= nil
                   and BMU_savedVarsAcc ~= nil
                   and BMU_savedVarsAcc.ShowOnMapOpen == true
    local tabIndex = bmuActive and 2 or 1
    table.insert(mapInfo.tabBarEntries, tabIndex, {
        text     = GetString(SI_GPH_MAPSEARCH_TAB),
        callback = function()
            mapInfo:SwitchToFragment(GPH_SEARCH_FRAGMENT, false)
        end,
    })

    gphSearchTabIndex = tabIndex
    ZO_GamepadGenericHeader_Refresh(mapInfo.header, mapInfo.baseHeaderData)
    GPH_SEARCH_TAB_INSERTED = true
end

-- addon loaded

local function OnAddonLoaded(_, name)
    if name ~= "GamePadHelper" then return end
    EVENT_MANAGER:UnregisterForEvent("MapSearch", EVENT_ADD_ON_LOADED)

    EVENT_MANAGER:RegisterForEvent("MapSearch_PreScan", EVENT_PLAYER_ACTIVATED, function()
        EVENT_MANAGER:UnregisterForEvent("MapSearch_PreScan", EVENT_PLAYER_ACTIVATED)
        if not scannedData then PreScan() end
    end)

    EVENT_MANAGER:RegisterForEvent("MapSearch_RecallNodeReset", EVENT_PLAYER_ACTIVATED, function()
        cachedRecallNode = nil
    end)
    EVENT_MANAGER:RegisterForEvent("MapSearch_POIUpdated", EVENT_POI_UPDATED, function()
        cachedRecallNode = nil
    end)

    EVENT_MANAGER:RegisterForEvent("MapSearch_Teleport", EVENT_PLAYER_ACTIVATED, function()
        if postTeleportMsg then
            local msg = postTeleportMsg
            postTeleportMsg = nil
            zo_callLater(function()
                local params = CENTER_SCREEN_ANNOUNCE:CreateMessageParams(CSA_CATEGORY_SMALL_TEXT)
                params:SetText(msg)
                CENTER_SCREEN_ANNOUNCE:AddMessageWithParams(params)
            end, 500)
        end
        if postTeleportDestination then
            local dest = postTeleportDestination
            postTeleportDestination = nil
            zo_callLater(function()
                PingMap(MAP_PIN_TYPE_PLAYER_WAYPOINT, MAP_TYPE_LOCATION_CENTERED, dest.x, dest.y)
            end, 500)
        end
    end)

    ZO_Dialogs_RegisterCustomDialog("GPH_UNBOOKMARK_CONFIRM", {
        gamepadInfo = { dialogType = GAMEPAD_DIALOGS.BASIC },
        title       = { text = SI_GPH_MAPSEARCH_REMOVE_BOOKMARK },
        mainText    = {
            text = function(dialog)
                local n = dialog.data and dialog.data.name or GetString(SI_GPH_MAPSEARCH_SEARCH_LOCATIONS)
                return zo_strformat(GetString(SI_GPH_MAPSEARCH_REMOVE_BOOKMARK_PROMPT), n)
            end,
        },
        buttons = {
            {
                keybind  = "DIALOG_PRIMARY",
                text     = SI_YES,
                callback = function(dialog)
                    if dialog.data then
                        local idx = listObject and listObject:GetSelectedIndex()
                        RemoveBookmark(dialog.data)
                        pendingNarration = zo_strformat(SI_GPH_MAPSEARCH_BOOKMARK_REMOVED, (dialog.data.name or ""))
                        SCREEN_NARRATION_MANAGER:QueueCustomEntry("GPH_MapSearch_Narration")
                        RunSearch(currentTerm)
                        RebuildList()
                        if idx and idx > 0 and listObject:GetNumItems() > 0 then
                            listObject:SetSelectedIndex(zo_clamp(idx, 1, listObject:GetNumItems()))
                        end
                    end
                end,
            },
            { keybind = "DIALOG_NEGATIVE", text = SI_NO },
        },
    })

    ZO_Dialogs_RegisterCustomDialog("GPH_TELEPORT_CONFIRM", {
        gamepadInfo = { dialogType = GAMEPAD_DIALOGS.BASIC },
        canQueue    = true,
        title = {
            text = SI_PROMPT_TITLE_FAST_TRAVEL_CONFIRM,
        },
        mainText = {
            text = function(dialog)
                if not dialog.data then return "" end
                local destination   = dialog.data.nodeIndex
                local wayshrineName = dialog.data.name
                local cost          = GetRecallCost(destination)
                local currency      = GetRecallCurrency(destination)
                local canAfford     = cost <= GetCurrencyAmount(currency, CURRENCY_LOCATION_CHARACTER)
                local cooldown      = GetRecallCooldown()
                local cooldownStr   = ZO_FormatTimeMilliseconds(cooldown, TIME_FORMAT_STYLE_SHOW_LARGEST_TWO_UNITS, TIME_FORMAT_PRECISION_SECONDS)

                local baseId
                if cost == 0 then
                    baseId = SI_GAMEPAD_FAST_TRAVEL_DIALOG_MAIN_TEXT
                elseif cooldown == 0 then
                    baseId = canAfford and SI_GAMEPAD_FAST_TRAVEL_DIALOG_RECALL_MAIN_TEXT
                                       or SI_GAMEPAD_FAST_TRAVEL_DIALOG_CANT_AFFORD
                else
                    baseId = canAfford and SI_GAMEPAD_FAST_TRAVEL_DIALOG_PREMIUM
                                       or SI_GAMEPAD_FAST_TRAVEL_DIALOG_CANT_AFFORD_PREMIUM
                end

                local text = zo_strformat(baseId, wayshrineName, cooldownStr)

                if cost > 0 then
                    text = text
                        .. "\n\n" .. GetString(SI_GPH_MAPSEARCH_RECALL_COST)
                        .. "\n"   .. FormatRecallCostAmount(cost)
                end
                return text
            end,
        },
        buttons = {
            {
                text     = SI_DIALOG_CONFIRM,
                callback = function(dialog)
                    if not dialog.data then return end
                    local d  = dialog.data
                    local sv = GetSavedVars()
                    if sv == nil or sv.mapSearchNarratePostTeleport ~= false then
                        postTeleportMsg = zo_strformat(SI_GPH_MAPSEARCH_TELEPORTED_TO, d.name)
                    end
                    FastTravelToNode(d.nodeIndex)
                    SCENE_MANAGER:ShowBaseScene()
                end,
                visible = function(dialog)
                    if not dialog.data then return false end
                    local destination = dialog.data.nodeIndex
                    local currency    = GetRecallCurrency(destination)
                    return GetRecallCost(destination) <= GetCurrencyAmount(currency, CURRENCY_LOCATION_CHARACTER)
                end,
            },
            {
                text = SI_DIALOG_CANCEL,
            },
        },
        updateFn = function(dialog)
            if not dialog.data then return end
            local remainingTime = GetRecallCooldown()
            local onCooldown    = remainingTime > 0
            if onCooldown or dialog.onCooldown ~= onCooldown then
                ZO_Dialogs_UpdateDialogMainText(dialog)
                dialog.onCooldown = onCooldown
            end
            KEYBIND_STRIP:UpdateCurrentKeybindButtonGroups()
        end,
    })

    GAMEPAD_WORLD_MAP_SCENE:RegisterCallback("StateChange", function(_, newState)
        if newState == SCENE_HIDING then
            wasOnGPHSearch = IsFragmentShowing()
        elseif newState == SCENE_SHOWING then
            zo_callLater(InsertMapSearchTab, 0)
            zo_callLater(function()
                if wasOnGPHSearch and gphSearchTabIndex and GAMEPAD_WORLD_MAP_INFO and GAMEPAD_WORLD_MAP_INFO.header then
                    ZO_GamepadGenericHeader_SetActiveTabIndex(GAMEPAD_WORLD_MAP_INFO.header, gphSearchTabIndex)
                end
            end, 0)
            if GamePadHelperSavedVars and GamePadHelperSavedVars.lastSelectedPOI then
                zo_callLater(function()
                    local poi = GamePadHelperSavedVars.lastSelectedPOI
                    CenterMapOnCandidate(poi)
                    GamePadHelperSavedVars.lastSelectedPOI = nil
                end, 100)
            end
        end
    end)
end

EVENT_MANAGER:RegisterForEvent("MapSearch", EVENT_ADD_ON_LOADED, OnAddonLoaded)
