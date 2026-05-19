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

local function FormatBulletText(text, colorPrefix)
  local safeText = tostring(text or ""):gsub("|", "||")
  local bulletText = zo_strformat(SI_FORMAT_BULLET_TEXT, safeText)
  if colorPrefix and colorPrefix ~= "" then
    return colorPrefix .. bulletText .. "|r"
  end
  return bulletText
end

local function SanitizeTooltipText(text)
  local s = tostring(text or "")
  s = s:gsub("|", "||")
  s = s:gsub("\194\160", " ") -- UTF-8 NBSP
  s = s:gsub("Â", "")         -- common mojibake artifact before NBSP
  s = s:gsub("%s+$", "")
  return s
end

local function SplitAndNormalizeTaskLines(text)
  local lines = {}
  local raw = tostring(text or "")
  raw = raw:gsub("\r\n", "\n")
  for line in raw:gmatch("([^\n]+)") do
    local s = SanitizeTooltipText(line)
    s = s:gsub("^%s+", ""):gsub("%s+$", "")
    s = s:gsub("^â€¢%s*", "")
    s = s:gsub("^•%s*", "")
    s = s:gsub("^Â+", "")
    s = s:gsub("^%s+", "")
    if s ~= "" then
      table.insert(lines, s)
    end
  end
  if #lines == 0 and raw ~= "" then
    table.insert(lines, raw)
  end
  return lines
end

local function TryAppendBulletLine(target, text, colorPrefix, fallbackPrefix)
  local safe = SanitizeTooltipText(text)
  local line = (fallbackPrefix or "- ") .. safe
  if colorPrefix and colorPrefix ~= "" then
    line = colorPrefix .. line .. "|r"
  end
  return target .. "\n" .. line
end

local function BuildBulletBlock(lines, colorPrefix)
  local out = ""
  for _, line in ipairs(lines or {}) do
    out = TryAppendBulletLine(out, line, colorPrefix, "- ")
  end
  return out:gsub("^\n", "")
end

local function EnsureTooltipBulletList(tooltip, key, labelTemplate, bulletTemplate, secondaryBulletTemplate)
  tooltip.gphBulletLists = tooltip.gphBulletLists or {}
  local entry = tooltip.gphBulletLists[key]
  if not entry then
    local controlName = "GPHOverviewBulletList_" .. tostring(key or "default")
    local control = _G[controlName]
    if not control then
      control = WINDOW_MANAGER:CreateControl(controlName, tooltip, CT_CONTROL)
    else
      control:SetParent(tooltip)
    end
    control:SetHidden(true)
    local list = ZO_BulletList:New(control, labelTemplate or "ZO_BulletLabel", bulletTemplate, secondaryBulletTemplate)
    list:SetLinePaddingY(7)
    list:SetBulletPaddingX(14)
    entry = { control = control, list = list }
    tooltip.gphBulletLists[key] = entry
  end
  return entry.control, entry.list
end

local function AddBulletListSection(tooltip, lines, headerText, lineColor, listKey)
  if not lines or #lines == 0 then return end
  local headerSection = tooltip:AcquireSection(tooltip:GetStyle("bodySection"))
  headerSection:AddLine(headerText, tooltip:GetStyle("bodyDescription"))
  tooltip:AddSection(headerSection)

  local control, bulletList = EnsureTooltipBulletList(tooltip, listKey or "gphTasks", "ZO_QuestJournal_HintBulletLabel_Gamepad")
  bulletList:Clear()

  local normalized = {}
  local bodyStyle = tooltip:GetStyle("bodyDescription")
  local bodySectionStyle = tooltip:GetStyle("bodySection")
  local bodyFont = tooltip:GetFontString(bodyStyle)
  local function ResolveStyleColor(styleA, styleB)
    local style = styleA or styleB or {}
    if style.fontColor then
      return style.fontColor:UnpackRGBA()
    end
    local colorType = style.fontColorType
    local colorField = style.fontColorField
    if colorType and colorField then
      return GetInterfaceColor(colorType, colorField)
    end
    return 1, 1, 1, 1
  end
  local r, g, b, a = ResolveStyleColor(bodyStyle, bodySectionStyle)
  for _, line in ipairs(lines) do
    local text = SanitizeTooltipText(line)
    if lineColor and lineColor ~= "" then
      text = lineColor .. text .. "|r"
    end
    table.insert(normalized, text)
    bulletList:AddLine(text)
    if bulletList.lastLabel and bodyFont then
      bulletList.lastLabel:SetFont(bodyFont)
      if not (lineColor and lineColor ~= "") then
        bulletList.lastLabel:SetColor(r, g, b, a)
      end
    end
  end

  local width = tooltip:GetWidth()
  if not width or width <= 0 then
    width = 420
  end
  control:SetWidth(width - 40)
  control:SetHeight(math.max(1, control:GetHeight()))
  control:SetHidden(false)

  local section = tooltip:AcquireSection(tooltip:GetStyle("bodySection"))
  section:AddControl(control, control:GetHeight(), control:GetWidth())
  tooltip:AddSection(section)
end

function ZO_Tooltip:LayoutGPHQuestOverviewTooltip(title, questName, backgroundText, activeStepText, taskLines, completedLines, optionalLines, hintLines)
  local titleSection = self:AcquireSection(self:GetStyle("bodyHeader"))
  titleSection:AddLine(title, self:GetStyle("title"))
  self:AddSection(titleSection)

  local body1 = self:AcquireSection(self:GetStyle("bodySection"))
  body1:AddLine("|cDAA520" .. SanitizeTooltipText(questName) .. "|r", self:GetStyle("bodyDescription"))
  self:AddSection(body1)

  local body2 = self:AcquireSection(self:GetStyle("bodySection"))
  body2:AddLine(SanitizeTooltipText(backgroundText), self:GetStyle("bodyDescription"))
  self:AddSection(body2)

  local body3 = self:AcquireSection(self:GetStyle("bodySection"))
  body3:AddLine(SanitizeTooltipText(activeStepText), self:GetStyle("bodyDescription"))
  self:AddSection(body3)

  AddBulletListSection(self, taskLines, "|cDAA520" .. GetString(SI_GPH_OVERVIEW_TASKS_LABEL) .. "|r", nil, "gphTasks")
  AddBulletListSection(self, completedLines, "|cDAA520" .. GetString(SI_GPH_OVERVIEW_COMPLETED_LABEL) .. "|r", "|c9D9D9D", "gphCompleted")
  AddBulletListSection(self, optionalLines, "|cDAA520" .. GetString(SI_GPH_OVERVIEW_OPTIONAL_LABEL) .. "|r", "|cAAAAAA", "gphOptional")
  AddBulletListSection(self, hintLines, "|cDAA520" .. GetString(SI_GPH_OVERVIEW_HINTS_LABEL) .. "|r", "|cAAAAAA", "gphHints")
end

local function TryBuildSection(builderFn)
  local ok, result = pcall(builderFn)
  if ok and type(result) == "string" and result ~= "" then
    return result
  end
  return ""
end

local function GetBestQuestIndex()
  local questIndex = QUEST_JOURNAL_MANAGER and QUEST_JOURNAL_MANAGER:GetFocusedQuestIndex() or nil
  if questIndex and IsValidQuestIndex and IsValidQuestIndex(questIndex) then
    return questIndex
  end

  for i = 1, MAX_JOURNAL_QUESTS do
    if IsValidQuestIndex(i) then
      local _, _, _, _, _, _, tracked = GetJournalQuestInfo(i)
      if tracked then
        return i
      end
    end
  end

  for i = 1, MAX_JOURNAL_QUESTS do
    if IsValidQuestIndex(i) then
      return i
    end
  end

  return nil
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
    sv.overviewDebug = sv.overviewDebug or {}
    local dbg = sv.overviewDebug
    dbg.timestamp = GetTimeStamp and GetTimeStamp() or 0
    dbg.clientLang = GetCVar and GetCVar("Language.2") or "unknown"

    GAMEPAD_TOOLTIPS:ClearTooltip(GAMEPAD_LEFT_TOOLTIP)
    GAMEPAD_TOOLTIPS:ClearTooltip(GAMEPAD_RIGHT_TOOLTIP)
    GAMEPAD_TOOLTIPS:ClearTooltip(GAMEPAD_QUAD3_TOOLTIP)

    local questIndex = GetBestQuestIndex()
    dbg.questIndex = questIndex
    if not questIndex then
        dbg.noQuest = true
        GAMEPAD_TOOLTIPS:LayoutTitleAndDescriptionTooltip(
            GAMEPAD_LEFT_TOOLTIP,
            "|c57A64E" .. GetString(SI_GPH_OVERVIEW_QUEST) .. "|r",
            GetString(SI_GPH_OVERVIEW_TASKS_AVAILABLE)
        )
        return
    end

    local questName, backgroundText, activeStepText, activeStepType, activeStepOverrideText = GetJournalQuestInfo(questIndex)
    dbg.noQuest = false
    dbg.questName = tostring(questName or "")
    dbg.backgroundText = tostring(backgroundText or "")
    dbg.activeStepText = tostring(activeStepText or "")
    dbg.activeStepType = tostring(activeStepType or "")
    dbg.activeStepOverrideText = tostring(activeStepOverrideText or "")
    local questSections = {}
    local function AddSection(text)
        if text and text ~= "" then
            table.insert(questSections, text)
        end
    end

    AddSection(TryBuildSection(function()
        return "|cDAA520" .. SanitizeTooltipText(zo_strformat("<<C:1>>", questName or "")) .. "|r"
    end))
    AddSection(TryBuildSection(function()
        return SanitizeTooltipText(backgroundText)
    end))
    AddSection(TryBuildSection(function()
        return SanitizeTooltipText(activeStepText)
    end))

    local questStrings = {}
    local fakeQuestJournal = {questStrings = questStrings}
    ZO_ClearNumericallyIndexedTable(questStrings)
    QUEST_JOURNAL_MANAGER:BuildTextForTasks(activeStepOverrideText, questIndex, questStrings)
    dbg.taskRawCount = #questStrings
    local taskLines = {}
    local completedLines = {}
    local debugTaskNames = {}
    local debugCompletedNames = {}
    for key, value in ipairs(questStrings) do
        local separatedLines = SplitAndNormalizeTaskLines(value.name)
        if not value.isComplete then
            for _, taskLine in ipairs(separatedLines) do
                table.insert(taskLines, taskLine)
                table.insert(debugTaskNames, tostring(taskLine or ""))
            end
        else
            for _, taskLine in ipairs(separatedLines) do
                table.insert(completedLines, taskLine)
                table.insert(debugCompletedNames, tostring(taskLine or ""))
            end
        end
    end
    dbg.taskNames = debugTaskNames
    dbg.completedTaskNames = debugCompletedNames

    ZO_ClearNumericallyIndexedTable(questStrings)
    ZO_QuestJournal_Shared.BuildTextForStepVisibility(fakeQuestJournal, questIndex, QUEST_STEP_VISIBILITY_OPTIONAL)
    dbg.optionalRawCount = #questStrings
    local optionalLines = {}
    if #questStrings > 0 then
        local debugOptionalNames = {}
        for index = 1, #questStrings do
            local separatedLines = SplitAndNormalizeTaskLines(questStrings[index])
            for _, taskLine in ipairs(separatedLines) do
                table.insert(optionalLines, taskLine)
                table.insert(debugOptionalNames, tostring(taskLine or ""))
            end
        end
        dbg.optionalNames = debugOptionalNames
    else
        dbg.optionalNames = {}
    end

    ZO_ClearNumericallyIndexedTable(questStrings)
    ZO_QuestJournal_Shared.BuildTextForStepVisibility(fakeQuestJournal, questIndex, QUEST_STEP_VISIBILITY_HINT)
    dbg.hintsRawCount = #questStrings
    local hintLines = {}
    if #questStrings > 0 then
        local debugHintNames = {}
        for index = 1, #questStrings do
            local separatedLines = SplitAndNormalizeTaskLines(questStrings[index])
            for _, taskLine in ipairs(separatedLines) do
                table.insert(hintLines, taskLine)
                table.insert(debugHintNames, tostring(taskLine or ""))
            end
        end
        dbg.hintNames = debugHintNames
    else
        dbg.hintNames = {}
    end

    if #questSections == 0 then
        table.insert(questSections, SanitizeTooltipText(zo_strformat("<<C:1>>", questName or "")))
    end
    local previewText = table.concat(questSections, "\n\n")
    if #taskLines > 0 then
        previewText = previewText .. "\n\n" .. GetString(SI_GPH_OVERVIEW_TASKS_LABEL) .. "\n" .. table.concat(taskLines, "\n")
    end
    dbg.sectionCount = #questSections
    dbg.questDescriptionLength = string.len(previewText)
    dbg.questDescriptionPreview = string.sub(previewText, 1, 600)

    GAMEPAD_TOOLTIPS:LayoutGPHQuestOverviewTooltip(
        GAMEPAD_LEFT_TOOLTIP,
        "|c57A64E" .. GetString(SI_GPH_OVERVIEW_QUEST) .. "|r",
        SanitizeTooltipText(zo_strformat("<<C:1>>", questName or "")),
        SanitizeTooltipText(backgroundText),
        SanitizeTooltipText(activeStepText),
        taskLines,
        completedLines,
        optionalLines,
        hintLines
    )

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
