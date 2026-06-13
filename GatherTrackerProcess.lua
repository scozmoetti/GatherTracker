-- ============================================================================
-- GATHERTRACKER - Process Module 
-- ============================================================================
local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("UNIT_SPELLCAST_SENT")
frame:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
frame:RegisterEvent("CHAT_MSG_LOOT")

local displayWindow = nil
local rowLines = {}
local lastProcessedItem = nil
local lastProcessType = nil
local processSuccessTime = 0
local countAddedThisProcess = false

local COLOR_HERB  = "|cFFA6FFCB"  
local COLOR_ORE   = "|cFFA6FFCB"  
local COLOR_COUNT = "|cFFFFFFFF"  
local COLOR_CYAN  = "|cFFC0B3FF"  
local COLOR_TOTAL = "|cFFFF8C00"  

ProcessTrackerPos = ProcessTrackerPos or {}

local function CleanItemName(link)
    if not link then return nil end
    return string.match(link, "%[(.-)%]")
end

local function GetQualityColor(name)
    local _, _, quality = GetItemInfo(name or "")
    if quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality] then
        return ITEM_QUALITY_COLORS[quality].hex
    end
    return "|cffffffff"
end

local function CreateTrackingWindow()
    if displayWindow then return displayWindow end

    local f = CreateFrame("Frame", "ProcessTrackerUIFrame", UIParent)
    f:SetSize(220, 100)
    GatherTracker.RestoreFramePos(f, ProcessTrackerPos, "CENTER", 0, -100)
    f:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16, insets = { left = 4, right = 4, top = 4, bottom = 4 }
    })
    f:SetMovable(true) f:EnableMouse(true) f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() GatherTracker.SaveFramePos(self, ProcessTrackerPos) end)

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", 10, -12) title:SetText("Process Tracker") title:SetTextColor(0.75, 0.18, 0.58, 1.0) 
    
    local closeBtn = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", 2, 2) closeBtn:SetSize(22, 22) closeBtn:SetScript("OnClick", function() f:Hide() end)

    local clearBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    clearBtn:SetSize(55, 20) clearBtn:SetPoint("BOTTOM", 0, 8) clearBtn:SetText("Clear")
    clearBtn:SetScript("OnClick", function()
        GatherTrackerDB.Process.Session = {}
        if displayWindow then UpdateUIWindow() end
        print("|cFF00FF00[ProcessTracker]|r Session cleared.")
    end)

    f:Hide() displayWindow = f return displayWindow
end

local function GetOrCreateRowLine(index)
    if not rowLines[index] then
        local lf = CreateFrame("Frame", nil, displayWindow) lf:SetSize(200, 16)
        local fs = lf:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall") fs:SetPoint("LEFT", 0, 0)
        lf.text = fs rowLines[index] = lf
    end return rowLines[index]
end

function UpdateUIWindow()
    if not displayWindow or not GatherTrackerDB then return end
    for _, line in ipairs(rowLines) do if line.text then line.text:SetText("") end line:Hide() end

    local lineIndex, verticalOffset = 1, -30
    local totalHerbs, totalOre, milledTypes, prospectedTypes = 0, 0, 0, 0
    local grandPigments, grandGems = {}, {}

    for item, data in pairs(GatherTrackerDB.Process.Session) do
        if data.consumed > 0 and item ~= "" and item ~= "Unknown Herb" and item ~= "Unknown Ore" then
            local isProspect = (data.processType == "Prospecting")
            if isProspect then totalOre = totalOre + data.consumed prospectedTypes = prospectedTypes + 1
            else totalHerbs = totalHerbs + data.consumed milledTypes = milledTypes + 1 end

            local casts = data.consumed / 5
            local headerColor = isProspect and COLOR_ORE or COLOR_HERB
            
            local itemLine = GetOrCreateRowLine(lineIndex)
            itemLine:SetPoint("TOPLEFT", 10, verticalOffset)
            itemLine.text:SetText(string.format("%s%s|r (%d)", headerColor, item, data.consumed))
            itemLine:Show()
            
            lineIndex = lineIndex + 1 verticalOffset = verticalOffset - 14

            local yieldData = data.yields or data.pigments or {}
            for yieldItem, count in pairs(yieldData) do
                if count > 0 then
                    if isProspect then grandGems[yieldItem] = (grandGems[yieldItem] or 0) + count
                    else grandPigments[yieldItem] = (grandPigments[yieldItem] or 0) + count end

                    local yieldColor = GetQualityColor(yieldItem)
                    local yieldPercent = (count / casts) * 100

                    local yieldLine = GetOrCreateRowLine(lineIndex)
                    yieldLine:SetPoint("TOPLEFT", 10, verticalOffset)
                    yieldLine.text:SetText(string.format("  %s%s|r %sx%d|r %s(%.0f%%)|r", yieldColor, yieldItem, COLOR_COUNT, count, COLOR_CYAN, yieldPercent))
                    yieldLine:Show()
                    
                    lineIndex = lineIndex + 1 verticalOffset = verticalOffset - 14
                end
            end verticalOffset = verticalOffset - 6
        end
    end

    if milledTypes > 1 then
        verticalOffset = verticalOffset - 4
        local dividerLine = GetOrCreateRowLine(lineIndex)
        dividerLine:SetPoint("TOPLEFT", 10, verticalOffset)
        dividerLine.text:SetText(string.format("%s--- Combined Pigments ---|r", COLOR_TOTAL))
        dividerLine:Show() lineIndex = lineIndex + 1 verticalOffset = verticalOffset - 14

        for pigment, count in pairs(grandPigments) do
            local grandYieldPercent = (count / (totalHerbs / 5)) * 100
            local grandLine = GetOrCreateRowLine(lineIndex)
            grandLine:SetPoint("TOPLEFT", 10, verticalOffset)
            grandLine.text:SetText(string.format("  %s%s|r %sx%d|r %s(%.0f%%)|r", GetQualityColor(pigment), pigment, COLOR_COUNT, count, COLOR_CYAN, grandYieldPercent))
            grandLine:Show() lineIndex = lineIndex + 1 verticalOffset = verticalOffset - 14
        end verticalOffset = verticalOffset - 6
    end

    if prospectedTypes > 1 then
        verticalOffset = verticalOffset - 4
        local dividerLine = GetOrCreateRowLine(lineIndex)
        dividerLine:SetPoint("TOPLEFT", 10, verticalOffset)
        dividerLine.text:SetText(string.format("%s--- Combined Gems ---|r", COLOR_TOTAL))
        dividerLine:Show() lineIndex = lineIndex + 1 verticalOffset = verticalOffset - 14

        for gem, count in pairs(grandGems) do
            local grandYieldPercent = (count / (totalOre / 5)) * 100
            local grandLine = GetOrCreateRowLine(lineIndex)
            grandLine:SetPoint("TOPLEFT", 10, verticalOffset)
            grandLine.text:SetText(string.format("  %s%s|r %sx%d|r %s(%.0f%%)|r", GetQualityColor(gem), gem, COLOR_COUNT, count, COLOR_CYAN, grandYieldPercent))
            grandLine:Show() lineIndex = lineIndex + 1 verticalOffset = verticalOffset - 14
        end verticalOffset = verticalOffset - 6
    end

    if totalHerbs > 0 or totalOre > 0 then
        verticalOffset = verticalOffset - 4
        if totalHerbs > 0 then
            local totalLine = GetOrCreateRowLine(lineIndex) totalLine:SetPoint("TOPLEFT", 10, verticalOffset)
            totalLine.text:SetText(string.format("%sTotal Herbs Milled: %d|r", COLOR_TOTAL, totalHerbs)) totalLine:Show()
            lineIndex = lineIndex + 1 verticalOffset = verticalOffset - 14
        end
        if totalOre > 0 then
            local totalLine = GetOrCreateRowLine(lineIndex) totalLine:SetPoint("TOPLEFT", 10, verticalOffset)
            totalLine.text:SetText(string.format("%sTotal Ore Prospected: %d|r", COLOR_TOTAL, totalOre)) totalLine:Show()
            lineIndex = lineIndex + 1 verticalOffset = verticalOffset - 14
        end
    end

    if lineIndex > 1 then displayWindow:SetSize(230, math.abs(verticalOffset) + 35) else displayWindow:SetSize(230, 60) end
end

function GatherTracker.ExportProcessCSV()
    local csv = "Action\tItem \tAmount \tYield \tCount \t% \n"
    local hasData = false local totalHerbs, totalOre = 0, 0

    for item, data in pairs(GatherTrackerDB.Process.Session) do
        if data.consumed > 0 and item ~= "" and item ~= "Unknown Herb" and item ~= "Unknown Ore" then
            local pType = data.processType or "Milling"
            if pType == "Prospecting" then totalOre = totalOre + data.consumed else totalHerbs = totalHerbs + data.consumed end

            local isFirstYield = true
            for yieldItem, count in pairs(data.yields or data.pigments or {}) do
                local yieldPercent = (count / (data.consumed / 5)) * 100
                if isFirstYield then
                    csv = csv .. string.format("%s\t%s\t%d\t%s\t%d\t%.0f%%\n", pType, item, data.consumed, yieldItem, count, yieldPercent)
                    isFirstYield = false
                else
                    csv = csv .. string.format("\t\t\t%s\t%d\t%.0f%%\n", yieldItem, count, yieldPercent)
                end
                hasData = true
            end
        end
    end

    if not hasData then csv = "No items processed in this session.\n" else
        csv = csv .. "\n"
        if totalOre > 0 then csv = csv .. string.format("Total Ore:\t%d\n", totalOre) end
        if totalHerbs > 0 then csv = csv .. string.format("Total Herbs:\t%d\n", totalHerbs) end
    end
    GatherTracker.DisplayMenuText(csv, "Process Export")
end

GatherTracker.ToggleProcessWindow = function()
    if displayWindow then if displayWindow:IsShown() then displayWindow:Hide() else displayWindow:Show() UpdateUIWindow() end end
end

frame:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        local addonName = ...
        if addonName == "GatherTracker" then
            CreateTrackingWindow()
        end

    elseif event == "UNIT_SPELLCAST_SENT" then
        local unit, spellName, spellRank, targetName = ...
        if unit == "player" and (spellName == "Milling" or spellName == "Prospecting") then
            lastProcessType = spellName
            if targetName and targetName ~= "" then lastProcessedItem = targetName else
                local tooltipName = GameTooltip:GetItem()
                if tooltipName then lastProcessedItem = tooltipName else lastProcessedItem = (spellName == "Prospecting") and "Unknown Ore" or "Unknown Herb" end
            end
        end

    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        local unit, spellName = ...
        if unit == "player" and (spellName == "Milling" or spellName == "Prospecting") then
            processSuccessTime = GetTime() countAddedThisProcess = false
            if not lastProcessType then lastProcessType = spellName end
        end

    elseif event == "CHAT_MSG_LOOT" then
        local msg = ...
        if (GetTime() - processSuccessTime) <= 2.0 and lastProcessedItem then
            local itemLink = string.match(msg, "(|c%x+|Hitem.-|h%[.-%]|h|r)")
            if not itemLink then return end
            
            local itemName = CleanItemName(itemLink)
            local count = tonumber(string.match(msg, "x(%d+)")) or 1

            if not GatherTrackerDB.Process.Session[lastProcessedItem] then
                GatherTrackerDB.Process.Session[lastProcessedItem] = { consumed = 0, yields = {}, processType = lastProcessType or "Milling" }
            end

            if not countAddedThisProcess then
                GatherTrackerDB.Process.Session[lastProcessedItem].consumed = GatherTrackerDB.Process.Session[lastProcessedItem].consumed + 5
                countAddedThisProcess = true
            end

            GatherTrackerDB.Process.Session[lastProcessedItem].yields[itemName] = (GatherTrackerDB.Process.Session[lastProcessedItem].yields[itemName] or 0) + count
            if displayWindow and displayWindow:IsShown() then UpdateUIWindow() end
        end
    end
end)