local Overview = {}

-- On console GAMEPAD_CHAT_SYSTEM is absent; treat as faded so the full
-- GAMEPAD_RIGHT_TOOLTIP slot is used for the tasks panel.
local isChatFaded = (GAMEPAD_CHAT_SYSTEM == nil)

local CRAFTING = {
  CRAFTING_TYPE_BLACKSMITHING,
  CRAFTING_TYPE_CLOTHIER,
  CRAFTING_TYPE_ENCHANTING,
  CRAFTING_TYPE_ALCHEMY,
  CRAFTING_TYPE_JEWELRYCRAFTING,
  CRAFTING_TYPE_PROVISIONING,
  CRAFTING_TYPE_WOODWORKING
}


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
        local traitType, _, known = GetSmithingResearchLineTraitInfo(craftingType, researchLineIndex, traitIndex)

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

-- Returns: researchableTraits, researchableItems, currentResearching, availableSlots
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
                table.insert(researchableTraitList, {researchLineIndex = researchLineIndex, traitIndex = traitIndex})
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

-- Returns: treasureCount, totalSurveyCount, totalWritCount
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

-- Count scryable antiquities and find minimum lead expiration time
local function GetScryableAntiquitiesInfo()
  local totalLeads = 0
  local totalMinTimeRemaining = nil
  local urgentZoneName = nil

  local antiquityId = GetNextAntiquityId()
  while antiquityId do
    local antiquityData = ANTIQUITY_DATA_MANAGER:GetAntiquityData(antiquityId)

    -- Check if this antiquity has a lead and meets skill requirements (global count)
    if antiquityData:HasLead() and antiquityData:MeetsScryingSkillRequirements() and not antiquityData:HasAchievedAllGoals() then
      totalLeads = totalLeads + 1
    end

    -- Check lead expiration time for all antiquities with expiring leads
    local timeRemaining = antiquityData:GetLeadTimeRemainingS()
    if timeRemaining and timeRemaining > 0 then
      -- Track global minimum time and zone
      if totalMinTimeRemaining == nil or timeRemaining < totalMinTimeRemaining then
        totalMinTimeRemaining = timeRemaining
        urgentZoneName = zo_strformat("<<C:1>>", GetZoneNameById(antiquityData:GetZoneId()))
      end
    end

    antiquityId = GetNextAntiquityId(antiquityId)
  end
  return totalLeads, totalMinTimeRemaining, urgentZoneName
end

local function ShowTooltips()
    local sv = _G["GamePadHelper_SavedVars"]
    if not sv or not sv.overviewEnabled then return end
    GAMEPAD_TOOLTIPS:ClearTooltip(GAMEPAD_RIGHT_TOOLTIP)
    GAMEPAD_TOOLTIPS:ClearTooltip(GAMEPAD_QUAD3_TOOLTIP)

    local questIndex = QUEST_JOURNAL_MANAGER:GetFocusedQuestIndex()
    local questName, backgroundText, activeStepText, activeStepType, activeStepOverrideText = GetJournalQuestInfo(questIndex)
    local questDescription = string.format("|cDAA520%s|r\n\n%s\n\n%s", zo_strformat("<<C:1>>", questName), backgroundText, activeStepText)

    local questStrings = {}
    local fakeQuestJournal = {questStrings = questStrings}
    ZO_ClearNumericallyIndexedTable(questStrings)
    QUEST_JOURNAL_MANAGER:BuildTextForTasks(activeStepOverrideText, questIndex, questStrings)
    local taskText = ""
    local completedTasks = ""
    for key, value in ipairs(questStrings) do
        if not value.isComplete then
            taskText = taskText .. "\n• " .. value.name
        else
            completedTasks = completedTasks .. "\n|c9D9D9D• " .. value.name .. "|r"
        end
    end
    if taskText ~= "" then
        questDescription = questDescription .. "\n\n|cDAA520" .. GetString(SI_GPH_OVERVIEW_TASKS_LABEL) .. "|r" .. taskText
    end
    if completedTasks ~= "" then
        questDescription = questDescription .. "\n\n|cDAA520" .. GetString(SI_GPH_OVERVIEW_COMPLETED_LABEL) .. "|r" .. completedTasks
    end

    ZO_ClearNumericallyIndexedTable(questStrings)
    ZO_QuestJournal_Shared.BuildTextForStepVisibility(fakeQuestJournal, questIndex, QUEST_STEP_VISIBILITY_OPTIONAL)
    if #questStrings > 0 then
        questDescription = questDescription .. "\n\n|cDAA520" .. GetString(SI_GPH_OVERVIEW_OPTIONAL_LABEL) .. "|r"
        for index = 1, #questStrings do
            questDescription = questDescription .. "\n|cAAAAAA• " .. questStrings[index] .. "|r"
        end
    end

    ZO_ClearNumericallyIndexedTable(questStrings)
    ZO_QuestJournal_Shared.BuildTextForStepVisibility(fakeQuestJournal, questIndex, QUEST_STEP_VISIBILITY_HINT)
    if #questStrings > 0 then
        questDescription = questDescription .. "\n\n|cDAA520" .. GetString(SI_GPH_OVERVIEW_HINTS_LABEL) .. "|r"
        for index = 1, #questStrings do
            questDescription = questDescription .. "\n|cAAAAAA• " .. questStrings[index] .. "|r"
        end
    end

    GAMEPAD_TOOLTIPS:LayoutTitleAndDescriptionTooltip(GAMEPAD_LEFT_TOOLTIP, "|c57A64E" .. GetString(SI_GPH_OVERVIEW_QUEST) .. "|r", questDescription)

    local rightTooltip = isChatFaded and GAMEPAD_RIGHT_TOOLTIP or GAMEPAD_QUAD3_TOOLTIP

    local tasksDescription = ""

    -- urgent antiquity timers shown first
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
        tasksDescription = tasksDescription .. "|cDAA520" .. GetString(SI_GPH_OVERVIEW_CRAFTING) .. "|r" .. craftingCountersText .. "\n"
        hasCrafting = true
    end

    for _, craftingType in ipairs(CRAFTING) do
        local researchableTraits, researchableItems, current, availableSlots = GetResearchInfo(craftingType)
        local craftText = zo_strformat("<<C:1>>", GetCraftingSkillName(craftingType))

        if GetNumSmithingResearchLines(craftingType) == 0 then
            local hasSkill = false
            if craftingType == CRAFTING_TYPE_PROVISIONING or craftingType == CRAFTING_TYPE_ENCHANTING or craftingType == CRAFTING_TYPE_ALCHEMY then
                local targetSkillName = zo_strlower(zo_strformat("<<1>>", GetCraftingSkillName(craftingType) or ""))
                -- GetSkillLineName is a PC-only alias; use GetSkillLineNameById on console
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
                 if not hasCrafting then
                     hasCrafting = true
                 end
                 tasksDescription = tasksDescription .. "|cDAA520" .. craftText .. ":|r\n  " .. GetString(SI_GPH_OVERVIEW_VISIT_STATION) .. "\n"
             end
         elseif researchableTraits > 0 and availableSlots > 0 then
             if not hasCrafting then
                 hasCrafting = true
             end
             local slotText = availableSlots > 0 and string.format(" |c00FF00%d|r %s", availableSlots, zo_strformat(GetString(SI_GPH_OVERVIEW_AVAILABLE_SLOTS), zo_strformat("<<1[slot/slots/slots]>>", availableSlots), "")) or ""
             local text = string.format("  |cFFFFFF%d|r/|cFFFFFF%d|r %s%s", researchableTraits, researchableItems, GetString(SI_GPH_OVERVIEW_RESEARCHABLE), slotText)
             tasksDescription = tasksDescription .. "|cDAA520" .. craftText .. ":|r\n" .. text .. "\n"
         end
     end
    if hasCrafting then
        tasksDescription = tasksDescription .. "\n"
    end

    if totalCount > 0 then
        -- Main leads line with total count and timer
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

    if tasksDescription == "" then
        tasksDescription = GetString(SI_GPH_OVERVIEW_TASKS_AVAILABLE)
    end

    GAMEPAD_TOOLTIPS:LayoutTitleAndDescriptionTooltip(rightTooltip, "|cDAA520" .. GetString(SI_GPH_OVERVIEW_TASKS) .. "|r", tasksDescription)
end

local function HideTooltips()
    GAMEPAD_TOOLTIPS:ClearTooltip(GAMEPAD_LEFT_TOOLTIP)
    GAMEPAD_TOOLTIPS:ClearTooltip(GAMEPAD_RIGHT_TOOLTIP)
end


function Overview:Initialize()
    -- re-evaluate: on PC check actual minimized state; on console always faded (no GAMEPAD_CHAT_SYSTEM)
    isChatFaded = not GAMEPAD_CHAT_SYSTEM or GAMEPAD_CHAT_SYSTEM:IsMinimized()

    SCENE_MANAGER:RegisterCallback("SceneStateChanged", function(scene, oldState, newState)
        if scene:GetName() == "mainMenuGamepad" then
            if newState == SCENE_SHOWING then
                ShowTooltips()
            elseif newState == SCENE_HIDING then
                HideTooltips()
            end
        end
    end)

    if GAMEPAD_CHAT_SYSTEM then
        ZO_PostHook(GAMEPAD_CHAT_SYSTEM, "Minimize", function()
            isChatFaded = true
            local sv = _G["GamePadHelper_SavedVars"]
            if sv and sv.overviewEnabled and SCENE_MANAGER:IsShowing("mainMenuGamepad") then
                ShowTooltips()
            end
        end)

        ZO_PostHook(GAMEPAD_CHAT_SYSTEM, "Maximize", function()
            isChatFaded = false
            local sv = _G["GamePadHelper_SavedVars"]
            if sv and sv.overviewEnabled and SCENE_MANAGER:IsShowing("mainMenuGamepad") then
                ShowTooltips()
            end
        end)
    end
end

EVENT_MANAGER:RegisterForEvent("Overview", EVENT_ADD_ON_LOADED, function(_, name)
    if name ~= "GamePadHelper" then return end
    EVENT_MANAGER:UnregisterForEvent("Overview", EVENT_ADD_ON_LOADED)
    Overview:Initialize()
end)
