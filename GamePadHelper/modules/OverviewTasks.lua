GPH_Overview = GPH_Overview or {}
GPH_Overview.Tasks = GPH_Overview.Tasks or {}

local Tasks = GPH_Overview.Tasks

local CRAFTING = {
  -- researchable (alphabetical)
  CRAFTING_TYPE_BLACKSMITHING,
  CRAFTING_TYPE_CLOTHIER,
  CRAFTING_TYPE_JEWELRYCRAFTING,
  CRAFTING_TYPE_WOODWORKING,
  -- no research (alphabetical)
  CRAFTING_TYPE_ALCHEMY,
  CRAFTING_TYPE_ENCHANTING,
  CRAFTING_TYPE_PROVISIONING,
}

local CRAFTING_TYPE_TO_WRIT_KEY = {
  [CRAFTING_TYPE_BLACKSMITHING]  = "blacksmith",
  [CRAFTING_TYPE_CLOTHIER]       = "clothier",
  [CRAFTING_TYPE_WOODWORKING]    = "woodworker",
  [CRAFTING_TYPE_ENCHANTING]     = "enchanter",
  [CRAFTING_TYPE_PROVISIONING]   = "provisioner",
  [CRAFTING_TYPE_ALCHEMY]        = "alchemist",
  [CRAFTING_TYPE_JEWELRYCRAFTING] = "jewelry",
}

local GPH_COMPANION_TRACKER_KEY = "overviewCompanionTracker"
local GPH_DAILY_WRIT_TRACKER_KEY = "overviewDailyWritTracker"

local DAILY_WRIT_GROUPS = {
  { id = "blacksmith", displayQuestId = 5377, questIds = { 5368, 5377, 5392 } },
  { id = "clothier", displayQuestId = 5374, questIds = { 5374, 5388, 5389 } },
  { id = "woodworker", displayQuestId = 5395, questIds = { 5394, 5395, 5396 } },
  { id = "enchanter", displayQuestId = 5407, questIds = { 5400, 5406, 5407 } },
  { id = "provisioner", displayQuestId = 5414, questIds = { 5409, 5412, 5413, 5414 } },
  { id = "alchemist", displayQuestId = 6105, questIds = { 5415, 5416, 5417, 5418, 6098, 6099, 6100, 6101, 6102, 6103, 6104, 6105 } },
  { id = "jewelry", displayQuestId = 6228, questIds = { 6218, 6227, 6228 } },
}

local function GetBoolSetting(key, default)
  local sv = _G["GamePadHelper_SavedVars"]
  if not sv then return default end
  local v = sv[key]
  if v == nil then return default end
  return v
end

local function GPH_NormalizeLowerText(text)
  return zo_strlower(zo_strformat("<<1>>", text or ""))
end

local COMPANION_RAPPORT_RECOMMENDATIONS = {
  ["bastian"] = {
    { id = "mages_daily", rapport = 125, questIds = { 5814, 5816, 5818, 5819, 5820, 5822, 5823, 5824, 5825, 5826, 5827, 5828, 5829, 5830, 5831 } },
  },
  ["mirri"] = {
    { id = "fighters_daily", rapport = 125, questIds = { 5786, 5793, 5787, 5789, 5791, 5833, 5794, 5796, 5795, 5797, 5785, 5790, 5788, 5784, 5792 } },
    { id = "ashlander_hunt_sorim_nakar", rapport = 125, displayQuestId = 5910, questIds = { 5907, 5908, 5909, 5910, 5911, 5912, 5913 } },
    { id = "ashlander_relic_numani_rasi", rapport = 125, displayQuestId = 5926, questIds = { 5924, 5925, 5926, 5927, 5928, 5929, 5930 } },
  },
  ["ember"] = {
    { id = "mages_daily", rapport = 125, questIds = { 5814, 5816, 5818, 5819, 5820, 5822, 5823, 5824, 5825, 5826, 5827, 5828, 5829, 5830, 5831 } },
    { id = "heist_daily", rapport = 125, questIds = { 5536, 5575, 5572, 5577, 5573 } },
    { id = "highisle_delve", rapport = 125, questIds = { 6809, 6826, 6805, 6825, 6818, 6815 } },
  },
  ["isobel"] = {
    { id = "undaunted_daily", rapport = 125, questIds = { 5735, 5733, 5738, 5853, 5800, 5808, 5737, 5778, 5779, 5802, 5744, 5745, 5739, 5734, 5798 } },
    { id = "highisle_worldboss", rapport = 125, questIds = { 6821, 6803, 6807, 6816, 6822, 6808 } },
  },
  ["azandar"] = {
    { id = "necrom_delve", rapport = 125, questIds = { 7035, 7037, 7036, 7034 } },
    { id = "enchanter_writ", rapport = 125, questIds = { 5407 } },
  },
  ["sharp-as-night"] = {
    { id = "necrom_worldboss", rapport = 125, questIds = { 7042, 7041, 7043, 7039, 7040 } },
    { id = "ashlander_hunt_sorim_nakar", rapport = 125, displayQuestId = 5910, questIds = { 5907, 5908, 5909, 5910, 5911, 5912, 5913 } },
    { id = "ashlander_relic_numani_rasi", rapport = 125, displayQuestId = 5926, questIds = { 5924, 5925, 5926, 5927, 5928, 5929, 5930 } },
  },
  ["tanlorin"] = {
    { id = "fighters_daily", rapport = 125, questIds = { 5786, 5793, 5787, 5789, 5791, 5833, 5794, 5796, 5795, 5797, 5785, 5790, 5788, 5784, 5792 } },
    { id = "alchemy_writ", rapport = 125, questIds = { 6105 } },
  },
  ["zerith-var"] = {
    { id = "northern_grahtwood_defence_force", rapport = 125, questIds = { 6318, 6341, 6342, 6345, 6347 } },
    { id = "tales_of_tribute_daily", rapport = 125, questIds = { 6831, 6832 } },
  },
}

local function GetLocalizedActivityLabel(activityId)
  if activityId == "fighters_daily" then
    local fighters = GetSkillLineName and GetSkillLineName(5, 2)
    if fighters and fighters ~= "" then
      return zo_strformat("<<C:1>>", fighters)
    end
  elseif activityId == "mages_daily" then
    local mages = GetSkillLineName and GetSkillLineName(5, 3)
    if mages and mages ~= "" then
      return zo_strformat("<<C:1>>", mages)
    end
  elseif activityId == "undaunted_daily" then
    local undaunted = GetString(SI_QUESTTYPE15)
    if undaunted and undaunted ~= "" then
      return zo_strformat("<<C:1>>", undaunted)
    end
  elseif activityId == "heist_daily" then
    return GetString(SI_GPH_OVERVIEW_COMPANION_ACTIVITY_HEIST_DAILY)
  elseif activityId == "highisle_worldboss" then
    return GetString(SI_GPH_OVERVIEW_COMPANION_ACTIVITY_HIGHISLE_WB)
  elseif activityId == "highisle_delve" then
    return GetString(SI_GPH_OVERVIEW_COMPANION_ACTIVITY_HIGHISLE_DELVE)
  elseif activityId == "necrom_worldboss" then
    return GetString(SI_GPH_OVERVIEW_COMPANION_ACTIVITY_NECROM_WB)
  elseif activityId == "necrom_delve" then
    return GetString(SI_GPH_OVERVIEW_COMPANION_ACTIVITY_NECROM_DELVE)
  elseif activityId == "ashlander_hunt" then
    return GetString(SI_GPH_OVERVIEW_COMPANION_ACTIVITY_ASHLANDER_HUNT)
  elseif activityId == "ashlander_hunt_sorim_nakar" then
    return GetString(SI_GPH_OVERVIEW_COMPANION_ACTIVITY_ASHLANDER_HUNT)
  elseif activityId == "ashlander_relic_numani_rasi" then
    return GetString(SI_GPH_OVERVIEW_COMPANION_ACTIVITY_ASHLANDER_RELIC)
  elseif activityId == "alchemy_writ" then
    return GetString(SI_GPH_OVERVIEW_COMPANION_ACTIVITY_ALCHEMY_WRIT)
  elseif activityId == "enchanter_writ" then
    return GetString(SI_GPH_OVERVIEW_COMPANION_ACTIVITY_ENCHANTER_WRIT)
  elseif activityId == "northern_grahtwood_defence_force" then
    return GetString(SI_GPH_OVERVIEW_COMPANION_ACTIVITY_NORTHERN_GRAHTWOOD_DEFENCE)
  elseif activityId == "tales_of_tribute_daily" then
    return GetString(SI_GPH_OVERVIEW_COMPANION_ACTIVITY_TALES_TRIBUTE)
  end
  return GetString(SI_GPH_OVERVIEW_TASKS)
end

local function GetCompanionProfileKey(companionId, companionName)
  local defId = tonumber(companionId)
  if defId then
    local byDefId = {}
    local function AddDef(defConstant, key)
      if type(defConstant) == "number" then
        byDefId[defConstant] = key
      end
    end
    AddDef(_G["COMPANION_DEF_ID_BASTIAN"], "bastian")
    AddDef(_G["COMPANION_DEF_ID_MIRRI"], "mirri")
    AddDef(_G["COMPANION_DEF_ID_EMBER"], "ember")
    AddDef(_G["COMPANION_DEF_ID_ISOBEL"], "isobel")
    AddDef(_G["COMPANION_DEF_ID_AZANDAR"], "azandar")
    AddDef(_G["COMPANION_DEF_ID_SHARP_AS_NIGHT"], "sharp-as-night")
    AddDef(_G["COMPANION_DEF_ID_TANLORIN"], "tanlorin")
    AddDef(_G["COMPANION_DEF_ID_ZERITH_VAR"], "zerith-var")
    if byDefId[defId] then
      return byDefId[defId]
    end
  end

  local name = GPH_NormalizeLowerText(companionName)
  if name == "" then return nil end
  if name:find("bastian", 1, true) then return "bastian" end
  if name:find("mirri", 1, true) then return "mirri" end
  if name:find("ember", 1, true) then return "ember" end
  if name:find("isobel", 1, true) then return "isobel" end
  if name:find("azandar", 1, true) then return "azandar" end
  if name:find("sharp", 1, true) then return "sharp-as-night" end
  if name:find("tanlorin", 1, true) then return "tanlorin" end
  if name:find("zerith", 1, true) then return "zerith-var" end
  return nil
end

local function EnsureCompanionTrackerState()
  local sv = _G["GamePadHelper_SavedVars"]
  if not sv then return nil end

  sv[GPH_COMPANION_TRACKER_KEY] = sv[GPH_COMPANION_TRACKER_KEY] or {}
  local tracker = sv[GPH_COMPANION_TRACKER_KEY]
  tracker.doneByActivity = tracker.doneByActivity or {}
  tracker.nextResetAt = tracker.nextResetAt or 0

  local now = GetTimeStamp and GetTimeStamp() or 0
  if now >= tracker.nextResetAt then
    tracker.doneByActivity = {}
    local untilReset = GetSecondsUntilDailyReset and GetSecondsUntilDailyReset() or 86400
    tracker.nextResetAt = now + zo_max(untilReset, 60)
  end

  return tracker
end

local function EnsureDailyWritTrackerState()
  local sv = _G["GamePadHelper_SavedVars"]
  if not sv then return nil end

  sv[GPH_DAILY_WRIT_TRACKER_KEY] = sv[GPH_DAILY_WRIT_TRACKER_KEY] or {}
  local tracker = sv[GPH_DAILY_WRIT_TRACKER_KEY]
  tracker.doneByQuestId = tracker.doneByQuestId or {}
  tracker.doneByWritKey = tracker.doneByWritKey or {}
  tracker.activeByQuestId = tracker.activeByQuestId or {}
  tracker.activeByWritKey = tracker.activeByWritKey or {}
  tracker.nextResetAt = tracker.nextResetAt or 0

  local now = GetTimeStamp and GetTimeStamp() or 0
  if now >= tracker.nextResetAt then
    tracker.doneByQuestId = {}
    tracker.doneByWritKey = {}
    tracker.activeByQuestId = {}
    tracker.activeByWritKey = {}
    local untilReset = GetSecondsUntilDailyReset and GetSecondsUntilDailyReset() or 86400
    tracker.nextResetAt = now + zo_max(untilReset, 60)
  end

  return tracker
end

local function IsQuestIdInActivity(questId, activity)
  if not questId or not activity or not activity.questIds then
    return false
  end
  for _, id in ipairs(activity.questIds) do
    if id == questId then
      return true
    end
  end
  return false
end

local function GetActiveCompanionRapportOverviewLines()
  if not HasActiveCompanion or not HasActiveCompanion() then return nil end
  local companionId = GetActiveCompanionDefId and GetActiveCompanionDefId() or nil
  if not companionId then return nil end

  local companionName = GetCompanionName and GetCompanionName(companionId) or ""
  local profileKey = GetCompanionProfileKey(companionId, companionName)
  local activities = profileKey and COMPANION_RAPPORT_RECOMMENDATIONS[profileKey] or nil
  local lines = {}

  table.insert(lines, "|cDAA520" .. GetString(SI_GPH_OVERVIEW_COMPANION_LABEL) .. "|r " .. zo_strformat("<<C:1>>", companionName ~= "" and companionName or GetString(SI_GENERIC_ACTIVE_COMPANION_NAME)))

  local rapportValue = GetActiveCompanionRapport and GetActiveCompanionRapport() or nil
  local rapportLevel = GetActiveCompanionRapportLevel and GetActiveCompanionRapportLevel() or nil
  if rapportLevel then
    local rapportLevelText = GetString("SI_COMPANIONRAPPORTLEVEL", rapportLevel)
    if rapportValue then
      table.insert(lines, "|cDAA520" .. GetString(SI_GPH_OVERVIEW_COMPANION_RAPPORT_LABEL) .. "|r |cFFFFFF" .. tostring(rapportValue) .. "|r (" .. zo_strformat("<<C:1>>", rapportLevelText) .. ")")
    else
      table.insert(lines, "|cDAA520" .. GetString(SI_GPH_OVERVIEW_COMPANION_RAPPORT_LABEL) .. "|r " .. zo_strformat("<<C:1>>", rapportLevelText))
    end
  end

  if not activities or #activities == 0 then
    table.insert(lines, "|cAAAAAA" .. GetString(SI_GPH_OVERVIEW_COMPANION_NO_CONFIG) .. "|r")
    return lines
  end

  table.insert(lines, "")
  table.insert(lines, "|cDAA520" .. GetString(SI_GPH_OVERVIEW_COMPANION_BEST_DAILIES) .. "|r")

  local tracker = EnsureCompanionTrackerState()
  local doneByActivity = (tracker and tracker.doneByActivity) or {}
  for _, activity in ipairs(activities) do
    local isDoneToday = doneByActivity[activity.id] == true
    local isInProgress = false
    local activeQuestName = nil
    for i = 1, MAX_JOURNAL_QUESTS do
      if IsValidQuestIndex(i) then
        local journalQuestId = GetJournalQuestId and GetJournalQuestId(i) or nil
        if IsQuestIdInActivity(journalQuestId, activity) then
          isInProgress = true
          activeQuestName = GetJournalQuestName and GetJournalQuestName(i) or GetJournalQuestInfo(i)
          break
        end
      end
    end

    local status = isDoneToday and ("|c66FF66" .. GetString(SI_GPH_OVERVIEW_COMPANION_STATUS_DONE) .. "|r") or (isInProgress and ("|cFFFF66" .. GetString(SI_GPH_OVERVIEW_COMPANION_STATUS_IN_PROGRESS) .. "|r") or ("|cAAAAAA" .. GetString(SI_GPH_OVERVIEW_COMPANION_STATUS_NOT_DONE) .. "|r"))
    local activityLabel = activeQuestName and activeQuestName ~= "" and zo_strformat("<<C:1>>", activeQuestName) or GetLocalizedActivityLabel(activity.id)
    table.insert(lines, string.format("  %s - %s", activityLabel, status))
  end

  table.insert(lines, "|c888888" .. GetString(SI_GPH_OVERVIEW_COMPANION_TRACKING_NOTE) .. "|r")
  return lines
end

function Tasks.OnQuestRemovedForCompanionTracker(_, completed, questIndex, questName, zoneIndex, poiIndex, questId)
  if not completed then return end
  if not questId or questId == 0 then return end
  if not HasActiveCompanion or not HasActiveCompanion() then return end

  local companionId = GetActiveCompanionDefId and GetActiveCompanionDefId() or nil
  if not companionId then return end
  local companionName = GetCompanionName and GetCompanionName(companionId) or ""
  local profileKey = GetCompanionProfileKey(companionId, companionName)
  local activities = profileKey and COMPANION_RAPPORT_RECOMMENDATIONS[profileKey] or nil
  if not activities then return end

  local tracker = EnsureCompanionTrackerState()
  if not tracker then return end

  for _, activity in ipairs(activities) do
    if IsQuestIdInActivity(questId, activity) then
      tracker.doneByActivity[activity.id] = true
    end
  end
end

local function IsDailyCraftingWritQuest(questIndex)
  if not IsValidQuestIndex(questIndex) then return false end
  if GetJournalQuestType(questIndex) ~= QUEST_TYPE_CRAFTING then return false end
  return GetJournalQuestRepeatType(questIndex) == QUEST_REPEAT_DAILY
end

local function GetDailyWritKeyForQuestId(questId)
  if not questId or questId == 0 then return nil end
  for _, group in ipairs(DAILY_WRIT_GROUPS) do
    for _, id in ipairs(group.questIds) do
      if id == questId then
        return group.id
      end
    end
  end
  return nil
end

local function GetDailyWritGroupLabel(group)
  local questName = GetQuestName and GetQuestName(group.displayQuestId) or nil
  if questName and questName ~= "" then
    return zo_strformat("<<C:1>>", questName)
  end
  return group.id
end

local function GetDailyWritStatusByKey()
  local tracker = EnsureDailyWritTrackerState()
  if not tracker then return nil end

  local activeByQuestId = {}
  local activeByWritKey = {}

  for questIndex = 1, MAX_JOURNAL_QUESTS do
    if IsDailyCraftingWritQuest(questIndex) then
      local questId = GetJournalQuestId and GetJournalQuestId(questIndex) or nil
      local questName = GetJournalQuestName and GetJournalQuestName(questIndex) or GetJournalQuestInfo(questIndex)
      questName = zo_strformat("<<C:1>>", questName or "")
      local writKey = GetDailyWritKeyForQuestId(questId)

      if questId and questId ~= 0 then
        activeByQuestId[questId] = { name = questName, writKey = writKey }
      end
      if writKey then
        activeByWritKey[writKey] = questName
      end
    end
  end

  tracker.activeByQuestId = activeByQuestId
  tracker.activeByWritKey = activeByWritKey

  local dailyWritLabel = GetString(SI_GPH_OVERVIEW_DAILY_WRIT)
  local statusByKey = {}
  for _, group in ipairs(DAILY_WRIT_GROUPS) do
    local status
    local isDone = false
    if activeByWritKey[group.id] then
      status = "|cFFFF66" .. GetString(SI_GPH_OVERVIEW_COMPANION_STATUS_IN_PROGRESS) .. "|r"
    elseif tracker.doneByWritKey[group.id] then
      status = "|c66FF66" .. GetString(SI_GPH_OVERVIEW_COMPANION_STATUS_DONE) .. "|r"
      isDone = true
    else
      status = "|cAAAAAA" .. GetString(SI_GPH_OVERVIEW_COMPANION_STATUS_NOT_DONE) .. "|r"
    end
    statusByKey[group.id] = { label = dailyWritLabel, status = status, isDone = isDone }
  end

  return statusByKey
end

local function OnQuestRemovedForDailyWritTracker(_, completed, questIndex, questName, zoneIndex, poiIndex, questId)
  if not completed then return end
  if not questId or questId == 0 then return end

  local tracker = EnsureDailyWritTrackerState()
  if not tracker then return end

  local writKey = GetDailyWritKeyForQuestId(questId)
  local activeQuest = tracker.activeByQuestId and tracker.activeByQuestId[questId]
  if activeQuest then
    tracker.doneByQuestId[questId] = activeQuest.name
    tracker.activeByQuestId[questId] = nil
  end
  writKey = writKey or (activeQuest and activeQuest.writKey)
  if writKey then
    tracker.doneByWritKey[writKey] = true
    if tracker.activeByWritKey then
      tracker.activeByWritKey[writKey] = nil
    end
  end
end

function Tasks.OnQuestRemoved(...)
  Tasks.OnQuestRemovedForCompanionTracker(...)
  OnQuestRemovedForDailyWritTracker(...)
end

local function FormatTimeRemaining(seconds)
  if not seconds or seconds <= 0 then return "" end
  local days = math.floor(seconds / 86400)
  local hours = math.floor((seconds % 86400) / 3600)
  local minutes = math.floor((seconds % 3600) / 60)
  local timeString = ""

  if days > 0 then
    timeString = timeString .. zo_strformat(GetString(SI_GPH_TIME_DAY_SHORT), days) .. " "
    if hours > 0 then timeString = timeString .. zo_strformat(GetString(SI_GPH_TIME_HOUR_SHORT), hours) .. " " end
  else
    if hours > 0 then timeString = timeString .. zo_strformat(GetString(SI_GPH_TIME_HOUR_SHORT), hours) .. " " end
    if minutes > 0 then timeString = timeString .. zo_strformat(GetString(SI_GPH_TIME_MINUTE_SHORT), minutes) end
  end

  timeString = timeString:gsub("%s+$", "")

  local totalDays = seconds / 86400
  if totalDays <= 3 then
    return "|cCC4C4C" .. timeString .. "|r"
  elseif totalDays <= 7 then
    return "|cFFFF00" .. timeString .. "|r"
  else
    return "|cFFFFFF" .. timeString .. "|r"
  end
end

local function GetResearchLineInfo(craftingType, researchLineIndex, numTraits)
  local areAllTraitsKnown = true
  for traitIndex = 1, numTraits do
    local _, _, known = GetSmithingResearchLineTraitInfo(craftingType, researchLineIndex, traitIndex)

    if not known then
      areAllTraitsKnown = false

      local durationSecs = GetSmithingResearchLineTraitTimes(craftingType, researchLineIndex, traitIndex)
      if durationSecs and durationSecs > 0 then
        return traitIndex, areAllTraitsKnown
      end
    end
  end
  return nil, areAllTraitsKnown
end

local function GetResearchInfo(craftingType)
  local maximum = GetMaxSimultaneousSmithingResearch(craftingType)
  local current = 0
  local researchableTraits = 0
  local researchableItems = 0

  local researchableTraitList = {}
  for researchLineIndex = 1, GetNumSmithingResearchLines(craftingType) do
    local _, _, numTraits = GetSmithingResearchLineInfo(craftingType, researchLineIndex)
    if numTraits > 0 then
      local researchingTraitIndex, areAllTraitsKnown = GetResearchLineInfo(craftingType, researchLineIndex, numTraits)
      if researchingTraitIndex then
        current = current + 1
      end
      if not areAllTraitsKnown then
        for traitIndex = 1, numTraits do
          local _, _, known = GetSmithingResearchLineTraitInfo(craftingType, researchLineIndex, traitIndex)
          if not known then
            local durationSecs = GetSmithingResearchLineTraitTimes(craftingType, researchLineIndex, traitIndex)
            if not durationSecs or durationSecs == 0 then
              researchableTraits = researchableTraits + 1
              table.insert(researchableTraitList, { researchLineIndex = researchLineIndex, traitIndex = traitIndex })
            end
          end
        end
      end
    end
  end

  if #researchableTraitList > 0 then
    for _, traitInfo in ipairs(researchableTraitList) do
      local hasItem = false

      for slotIndex = 0, GetBagSize(BAG_BACKPACK) - 1 do
        if GetItemId(BAG_BACKPACK, slotIndex) > 0 then
          if CanItemBeSmithingTraitResearched(BAG_BACKPACK, slotIndex, craftingType, traitInfo.researchLineIndex, traitInfo.traitIndex) then
            hasItem = true
            break
          end
        end
      end

      if not hasItem then
        for slotIndex = 0, GetBagSize(BAG_BANK) - 1 do
          if GetItemId(BAG_BANK, slotIndex) > 0 then
            if CanItemBeSmithingTraitResearched(BAG_BANK, slotIndex, craftingType, traitInfo.researchLineIndex, traitInfo.traitIndex) then
              hasItem = true
              break
            end
          end
        end
      end

      if not hasItem then
        for slotIndex = 0, GetBagSize(BAG_SUBSCRIBER_BANK) - 1 do
          if GetItemId(BAG_SUBSCRIBER_BANK, slotIndex) > 0 then
            if CanItemBeSmithingTraitResearched(BAG_SUBSCRIBER_BANK, slotIndex, craftingType, traitInfo.researchLineIndex, traitInfo.traitIndex) then
              hasItem = true
              break
            end
          end
        end
      end

      if hasItem then
        researchableItems = researchableItems + 1
      end
    end
  end

  local availableSlots = maximum - current
  return researchableTraits, researchableItems, current, availableSlots
end

local function CountAllInventoryItems()
  local treasureCount = 0
  local totalSurveyCount = 0
  local totalWritCount = 0
  local treasureKeyword = zo_strlower(GetString(SI_GPH_OVERVIEW_KEYWORD_TREASURE) or "")
  local mapKeyword = zo_strlower(GetString(SI_GPH_OVERVIEW_KEYWORD_MAP) or "")
  local surveyKeyword = zo_strlower(GetString(SI_GPH_OVERVIEW_KEYWORD_SURVEY) or "")
  local writKeyword = zo_strlower(GetString(SI_GPH_OVERVIEW_KEYWORD_WRIT) or "")

  local function NameContains(name, keyword)
    return keyword ~= "" and name:find(keyword, 1, true) ~= nil
  end

  for bagId = BAG_BACKPACK, BAG_SUBSCRIBER_BANK do
    for slotIndex = 0, GetBagSize(bagId) - 1 do
      if GetItemId(bagId, slotIndex) > 0 then
        local itemName = GetItemName(bagId, slotIndex)
        if itemName then
          local itemNameLower = zo_strlower(itemName)

          if NameContains(itemNameLower, treasureKeyword) and NameContains(itemNameLower, mapKeyword) then
            treasureCount = treasureCount + GetSlotStackSize(bagId, slotIndex)
          elseif NameContains(itemNameLower, surveyKeyword) then
            totalSurveyCount = totalSurveyCount + GetSlotStackSize(bagId, slotIndex)
          elseif NameContains(itemNameLower, writKeyword) then
            totalWritCount = totalWritCount + GetSlotStackSize(bagId, slotIndex)
          end
        end
      end
    end
  end

  return treasureCount, totalSurveyCount, totalWritCount
end

local function GetScryableAntiquitiesInfo()
  local totalLeads = 0
  local totalMinTimeRemaining = nil
  local urgentZoneName = nil

  local antiquityId = GetNextAntiquityId()
  while antiquityId do
    local antiquityData = ANTIQUITY_DATA_MANAGER:GetAntiquityData(antiquityId)

    if antiquityData:HasLead() and antiquityData:MeetsScryingSkillRequirements() and not antiquityData:HasAchievedAllGoals() then
      totalLeads = totalLeads + 1
    end

    local timeRemaining = antiquityData:GetLeadTimeRemainingS()
    if timeRemaining and timeRemaining > 0 then
      if totalMinTimeRemaining == nil or timeRemaining < totalMinTimeRemaining then
        totalMinTimeRemaining = timeRemaining
        urgentZoneName = zo_strformat("<<C:1>>", GetZoneNameById(antiquityData:GetZoneId()))
      end
    end

    antiquityId = GetNextAntiquityId(antiquityId)
  end
  return totalLeads, totalMinTimeRemaining, urgentZoneName
end

function Tasks.ShowRightTooltip(rightTooltip)
  local tasksDescription = ""

  local totalCount, totalMinTime, urgentZoneName = GetScryableAntiquitiesInfo()
  local isUrgent = totalMinTime and (totalMinTime / 86400) <= 3
  if isUrgent then
    local zoneText = urgentZoneName and zo_strformat(GetString(SI_GPH_OVERVIEW_IN_ZONE), "|cFFFF00" .. urgentZoneName .. "|r") or ""
    tasksDescription = tasksDescription .. "|cCC4C4C" .. GetString(SI_GPH_OVERVIEW_URGENT) .. "|r\n   " .. zo_strformat(GetString(SI_GPH_OVERVIEW_LEAD_EXPIRES), zoneText, FormatTimeRemaining(totalMinTime)) .. "\n\n"
  end

  local horseTrainingTimeRemaining = GetTimeUntilCanBeTrained()
  local speedBonus, maxSpeedBonus, staminaBonus, maxStaminaBonus, inventoryBonus, maxInventoryBonus = STABLE_MANAGER:GetStats()
  if horseTrainingTimeRemaining == 0 and ((speedBonus < maxSpeedBonus) or (staminaBonus < maxStaminaBonus) or (inventoryBonus < maxInventoryBonus)) then
    tasksDescription = tasksDescription .. "|cDAA520" .. GetString(SI_GPH_OVERVIEW_HORSE_TRAINING) .. "|r " .. GetString(SI_GPH_OVERVIEW_AVAILABLE) .. "\n\n"
  end

  local hasCrafting = false
  local treasureCount, totalSurveyCount, totalWritCount = CountAllInventoryItems()

  if totalSurveyCount > 0 or totalWritCount > 0 then
    local craftingCountersText = ""
    if totalSurveyCount > 0 then
      craftingCountersText = craftingCountersText .. " |cFFFFFF" .. totalSurveyCount .. "|r " .. GetString(SI_GPH_OVERVIEW_SURVEY)
    end
    if totalSurveyCount > 0 and totalWritCount > 0 then
      craftingCountersText = craftingCountersText .. " -"
    end
    if totalWritCount > 0 then
      craftingCountersText = craftingCountersText .. " |cFFFFFF" .. totalWritCount .. "|r " .. GetString(SI_GPH_OVERVIEW_WRIT)
    end
    tasksDescription = tasksDescription .. "|cDAA520" .. GetString(SI_GPH_OVERVIEW_CRAFTING) .. "|r" .. craftingCountersText .. "\n\n"
    hasCrafting = true
  end

  local writStatusByKey = GetBoolSetting("overviewDailyWritEnabled", true) and GetDailyWritStatusByKey() or nil

  for _, craftingType in ipairs(CRAFTING) do
    local researchableTraits, researchableItems, _, availableSlots = GetResearchInfo(craftingType)
    local craftText = zo_strformat("<<C:1>>", GetCraftingSkillName(craftingType))
    local writKey = CRAFTING_TYPE_TO_WRIT_KEY[craftingType]
    local writEntry = writStatusByKey and writKey and writStatusByKey[writKey]
    local entryLines = {}

    if writEntry and not writEntry.isDone then
      table.insert(entryLines, "  " .. writEntry.label .. " - " .. writEntry.status)
    end

    if GetNumSmithingResearchLines(craftingType) == 0 then
      local hasSkill = false
      if craftingType == CRAFTING_TYPE_PROVISIONING or craftingType == CRAFTING_TYPE_ENCHANTING or craftingType == CRAFTING_TYPE_ALCHEMY then
        local targetSkillName = zo_strlower(zo_strformat("<<1>>", GetCraftingSkillName(craftingType) or ""))
        -- GetSkillLineName is a PC-only alias; use GetSkillLineNameById on console.
        local function SafeGetSkillLineName(skillType, skillLineIndex)
          if GetSkillLineName then return GetSkillLineName(skillType, skillLineIndex) end
          local id = GetSkillLineId and GetSkillLineId(skillType, skillLineIndex)
          return id and GetSkillLineNameById and GetSkillLineNameById(id)
        end
        for skillCategory = 1, GetNumSkillTypes() do
          for skillLine = 1, GetNumSkillLines(skillCategory) do
            local skillLineName = SafeGetSkillLineName(skillCategory, skillLine)
            if skillLineName then
              if targetSkillName ~= "" and zo_strlower(zo_strformat("<<1>>", skillLineName)):find(targetSkillName, 1, true) then
                hasSkill = true
                break
              end
            end
          end
          if hasSkill then break end
        end
      end

      if not hasSkill then
        table.insert(entryLines, "  " .. GetString(SI_GPH_OVERVIEW_VISIT_STATION))
      end
    elseif researchableTraits > 0 and availableSlots > 0 then
      local slotText = availableSlots > 0 and string.format(" |c00FF00%d|r %s", availableSlots, zo_strformat(GetString(SI_GPH_OVERVIEW_AVAILABLE_SLOTS), zo_strformat("<<1[slot/slots/slots]>>", availableSlots), "")) or ""
      table.insert(entryLines, string.format("  |cFFFFFF%d|r/|cFFFFFF%d|r %s%s", researchableTraits, researchableItems, GetString(SI_GPH_OVERVIEW_RESEARCHABLE), slotText))
    end

    if #entryLines > 0 then
      hasCrafting = true
      tasksDescription = tasksDescription .. "|cDAA520" .. craftText .. ":|r\n" .. table.concat(entryLines, "\n") .. "\n\n"
    end
  end

  if hasCrafting then
    tasksDescription = tasksDescription .. "\n"
  end

  if totalCount > 0 then
    local totalTimeString = ""
    if totalMinTime and not isUrgent then
      totalTimeString = " (" .. FormatTimeRemaining(totalMinTime) .. ")"
    end
    tasksDescription = tasksDescription .. "|cDAA520" .. GetString(SI_GPH_OVERVIEW_LEADS) .. "|r |cFFFFFF" .. totalCount .. "|r " .. GetString(SI_GPH_OVERVIEW_SCRYABLE) .. totalTimeString .. "\n"
  end

  if treasureCount > 0 then
    tasksDescription = tasksDescription .. "|cDAA520" .. GetString(SI_GPH_OVERVIEW_TREASURE) .. "|r |cFFFFFF" .. treasureCount .. "|r " .. GetString(SI_GPH_OVERVIEW_MAPS) .. "\n"
  end

  if totalCount > 0 or treasureCount > 0 then
    tasksDescription = tasksDescription .. "\n\n"
  end

  local companionLines = GetBoolSetting("overviewCompanionEnabled", true) and GetActiveCompanionRapportOverviewLines() or nil
  if companionLines and #companionLines > 0 then
    if tasksDescription ~= "" then
      tasksDescription = tasksDescription .. "\n"
    end
    tasksDescription = tasksDescription .. table.concat(companionLines, "\n")
  end

  if tasksDescription == "" then
    tasksDescription = GetString(SI_GPH_OVERVIEW_TASKS_AVAILABLE)
  end

  GAMEPAD_TOOLTIPS:LayoutTitleAndDescriptionTooltip(rightTooltip, "|cDAA520" .. GetString(SI_GPH_OVERVIEW_TASKS) .. "|r", tasksDescription)
end
