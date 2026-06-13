-- ============================================================================
-- GATHERTRACKER - Lightweight Gather-Only Edition
-- ============================================================================

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("CHAT_MSG_LOOT")

-- Windows
local displayWindow, priceWindow, menuWindow = nil, nil, nil

-- Row caches
local rowLines = {}
local sessionStartTime = nil
local isSessionFrozen = false
local frozenSessionDuration = 0
local lastGPHUpdate = 0
local cachedGPHText = "Gold per hour:  0.00g"

-- Session tables
local GatherTrackerSession = GatherTrackerSession or {}

-- Saved positions
GatherTrackerPos = GatherTrackerPos or {}
GatherTrackerPricePos = GatherTrackerPricePos or {}

-- ============================================================================
-- UTILITIES
-- ============================================================================
local function GetSessionDuration()
    if not sessionStartTime then return 0 end
    local secs = isSessionFrozen and frozenSessionDuration or (GetTime() - sessionStartTime)
    return secs
end

local function FormatDuration(secs)
    if secs <= 0 then return "0 mins" end
    local hrs = math.floor(secs / 3600)
    local mins = (secs % 3600) / 60
    if hrs > 0 then
        return string.format("%d hr %.1f min", hrs, mins)
    else
        return string.format("%.1f min", mins)
    end
end


local function CleanItemName(link)
    if not link then return nil end
    return string.match(link, "%[(.-)%]")
end

local function FormatMoneyString(copper)
    if not copper or copper <= 0 then return "0.00g" end
    return string.format("%.2fg", copper / 10000)
end

local function GetCustomPrice(itemName)
    if not itemName then return 0 end
    if GatherTrackerDB and GatherTrackerDB.ManualPrices and GatherTrackerDB.ManualPrices[itemName] then
        return math.floor((tonumber(GatherTrackerDB.ManualPrices[itemName]) or 0) * 10000 + 0.5)
    end
    return 0
end

local function GetQualityColor(name)
    if name == "Frost Lotus" or string.find(name or "", "Crystallized") then return "|cff1eff00" end
    local _, _, quality = GetItemInfo(name or "")
    if quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality] then
        return ITEM_QUALITY_COLORS[quality].hex
    end
    return "|cffffffff"
end

local function CalculatePerHourRate(count)
    if not sessionStartTime or count <= 0 then return 0 end
    local hoursPassed = isSessionFrozen and (frozenSessionDuration / 3600) or ((GetTime() - sessionStartTime) / 3600)
    if hoursPassed <= 0 then return 0 end
    return math.floor(count / hoursPassed + 0.5)
end

local function CalculateTotalGoldPerHour(totalCopper)
    if not sessionStartTime or totalCopper <= 0 then return 0 end
    local hoursPassed = isSessionFrozen and (frozenSessionDuration / 3600) or ((GetTime() - sessionStartTime) / 3600)
    if hoursPassed <= 0 then return 0 end
    return math.floor(totalCopper / hoursPassed + 0.5)
end

local function SaveFramePos(frame, store)
    local point, _, relativePoint, xOfs, yOfs = frame:GetPoint()
    store.point, store.relativePoint, store.x, store.y = point, relativePoint, xOfs, yOfs
end

local function RestoreFramePos(frame, store, defaultPoint, dx, dy)
    if store and store.x then
        frame:ClearAllPoints()
        frame:SetPoint(store.point, UIParent, store.relativePoint, store.x, store.y)
    else
        frame:ClearAllPoints()
        frame:SetPoint(defaultPoint, UIParent, defaultPoint, dx or 0, dy or 0)
    end
end

-- ============================================================================
-- PRICE BOOK WINDOW (Gather Whitelist)
-- ============================================================================
local function CreatePriceBookWindow()
    local f = CreateFrame("Frame", "GatherTrackerPriceFrame", UIParent)
    f:SetSize(400, 300)
    RestoreFramePos(f, GatherTrackerPricePos, "CENTER", -200, 0)
    f:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background", edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32, insets = { left = 11, right = 12, top = 12, bottom = 11 }
    })
    f:SetMovable(true) f:EnableMouse(true) f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        SaveFramePos(self, GatherTrackerPricePos)
    end)

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 20, -16) title:SetText("Gather Whitelist & Price Book")

    local scrollFrame = CreateFrame("ScrollFrame", "GatherTrackerPriceFrameScroll", f, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 20, -45) scrollFrame:SetPoint("BOTTOMRIGHT", -40, 45)

    local editBox = CreateFrame("EditBox", nil, scrollFrame)
    editBox:SetMultiLine(true) editBox:SetMaxLetters(99999) editBox:SetFontObject("GameFontHighlight")
    editBox:SetWidth(330) scrollFrame:SetScrollChild(editBox)

    local clickBg = CreateFrame("Button", nil, scrollFrame)
    clickBg:SetAllPoints(scrollFrame) clickBg:SetScript("OnClick", function() editBox:SetFocus() end)

    f:SetScript("OnShow", function()
        local str = ""
        if GatherTrackerDB and GatherTrackerDB.ManualPrices then
            for item, price in pairs(GatherTrackerDB.ManualPrices) do
                if price > 0 then str = str .. item .. " " .. price .. " " end
            end
        end
        editBox:SetText(str) editBox:SetFocus() editBox:HighlightText()
    end)

    local saveBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    saveBtn:SetSize(130, 22) saveBtn:SetPoint("BOTTOMLEFT", 20, 15) saveBtn:SetText("Import & Save")
    saveBtn:SetScript("OnClick", function()
        local rawText = editBox:GetText()
        GatherTrackerDB.ManualPrices = {}
        local foundCount = 0
        for name, price in string.gmatch(rawText, "([%a%s'%-%(%):]+)(%d+%.?%d*)") do
            local cleanName = string.match(name, "^%s*(.-)%s*$")
            local numPrice = tonumber(price)
            if cleanName and cleanName ~= "" and numPrice then
                GatherTrackerDB.ManualPrices[cleanName] = numPrice
                foundCount = foundCount + 1
            end
        end
        print("|cFF00FF00[GatherTracker] Synced! Imported " .. foundCount .. " items into your whitelist.|r")
        if displayWindow and displayWindow:IsShown() then UpdateUIWindow() end
        f:Hide()
    end)

    local closeBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    closeBtn:SetSize(130, 22) closeBtn:SetPoint("BOTTOMRIGHT", -35, 15) closeBtn:SetText("Close")
    closeBtn:SetScript("OnClick", function() f:Hide() end)

    f:Hide()
    priceWindow = f
end

-- ============================================================================
-- MAIN GATHER TRACKER UI
-- ============================================================================
local function CreateTrackingWindow()
    if displayWindow then return displayWindow end

    local f = CreateFrame("Frame", "GatherTrackerUIFrame", UIParent)
    f:SetSize(240, 120)
    RestoreFramePos(f, GatherTrackerPos, "CENTER", 0, 100)
    f:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16, insets = { left = 4, right = 4, top = 4, bottom = 4 }
    })
    f:SetMovable(true) f:EnableMouse(true) f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        SaveFramePos(self, GatherTrackerPos)
    end)

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", 10, -12) title:SetText("Gather Tracker") title:SetTextColor(0.267, 0.600, 0.745, 1.0)
    f.title = title
    
    local timerText = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    timerText:SetPoint("LEFT", title, "RIGHT", 8, 0)
    timerText:SetText("No active session.") f.timerText = timerText
    
    local goldSummaryText = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    goldSummaryText:SetText("Gather Value: 0.00g") f.goldSummaryText = goldSummaryText
    
    local velocityText = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    velocityText:SetText("Gold per hour: 0.00g") velocityText:SetTextColor(1.0, 0.82, 0.0, 1.0)
    f.velocityText = velocityText

    local closeBtn = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", 2, 2) closeBtn:SetSize(22, 22) closeBtn:SetScript("OnClick", function() f:Hide() end)

    -- Play (triangle) button
    local playBtn = CreateFrame("Button", nil, f)
    playBtn:SetSize(18, 18) playBtn:SetPoint("TOPRIGHT", -28, -8)
    playBtn.texture = playBtn:CreateTexture(nil, "ARTWORK")
    playBtn.texture:SetAllPoints(playBtn)
    playBtn.texture:SetTexture("Interface\\Buttons\\UI-SpellbookIcon-NextPage-Up")
    playBtn:SetScript("OnClick", function()
        if sessionStartTime and isSessionFrozen then
            sessionStartTime = GetTime() - frozenSessionDuration
            isSessionFrozen = false frozenSessionDuration = 0
            lastGPHUpdate = 0
            print("|cFF00FF00[GatherTracker] Session resumed!|r")
        elseif not sessionStartTime then
            sessionStartTime = GetTime()
            isSessionFrozen = false frozenSessionDuration = 0
            lastGPHUpdate = 0
            print("|cFF00FF00[GatherTracker] Session started!|r")
        end
        if displayWindow then UpdateUIWindow() displayWindow:Show() end
    end)
    playBtn:SetScript("OnEnter", function() GameTooltip:SetOwner(playBtn, "ANCHOR_RIGHT"); GameTooltip:SetText("Start/Resume"); GameTooltip:Show() end)
    playBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Pause button using native 3.3.5a TimeManager icon
    local pauseBtn = CreateFrame("Button", nil, f)
    pauseBtn:SetSize(18, 18) 
    pauseBtn:SetPoint("TOPRIGHT", -10, -8)
    pauseBtn.texture = pauseBtn:CreateTexture(nil, "ARTWORK")
    pauseBtn.texture:SetAllPoints(pauseBtn)
    pauseBtn.texture:SetTexture("Interface\\TimeManager\\PauseButton")
    pauseBtn:SetScript("OnClick", function()
        if sessionStartTime and not isSessionFrozen then
            isSessionFrozen = true frozenSessionDuration = GetTime() - sessionStartTime
            if displayWindow then UpdateUIWindow() end print("|cFF00FF00[GatherTracker] Session paused!|r")
        end
    end)
    pauseBtn:SetScript("OnEnter", function() GameTooltip:SetOwner(pauseBtn, "ANCHOR_RIGHT"); GameTooltip:SetText("Pause"); GameTooltip:Show() end)
    pauseBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    
    f:Hide() displayWindow = f return displayWindow
end

function UpdateUIWindow()
    if not displayWindow then return end
    if sessionStartTime then
        local secs = isSessionFrozen and frozenSessionDuration or (GetTime() - sessionStartTime)
        local hrs = math.floor(secs / 3600) local mins = (secs - hrs * 3600) / 60
        local prefix = isSessionFrozen and "Done: " or "Time: " local color = isSessionFrozen and "|cff00ff00" or ""
        if hrs > 0 then displayWindow.timerText:SetText(string.format("%s%s%d hr %.1f m|r", color, prefix, hrs, mins))
        else displayWindow.timerText:SetText(string.format("%s%s%.1f mins|r", color, prefix, mins)) end
    else displayWindow.timerText:SetText("New Session.") end

    for _, line in ipairs(rowLines) do if line.text then line.text:SetText("") end line:Hide() end
    local lineIndex, verticalOffset, totalSessionValue = 1, -44, 0

    for item, total in pairs(GatherTrackerSession or {}) do
        if total > 0 then
            if not rowLines[lineIndex] then
                local lf = CreateFrame("Frame", nil, displayWindow) lf:SetSize(220, 16)
                local fs = lf:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall") fs:SetPoint("LEFT", 0, 0)
                lf.text = fs rowLines[lineIndex] = lf
            end
            local colorHex = GetQualityColor(item)
            local itemRate = CalculatePerHourRate(total)
            local singleUnitPrice = GetCustomPrice(item)
            local totalItemValue = singleUnitPrice * total totalSessionValue = totalSessionValue + totalItemValue
            
            local currentLine = rowLines[lineIndex] currentLine:SetPoint("TOPLEFT", 10, verticalOffset)
            currentLine.text:SetText(string.format("%s%s|r x%d (%d/h) - |cffffd700%.2fg|r", colorHex, item, total, itemRate, totalItemValue / 10000))
            currentLine:Show() lineIndex = lineIndex + 1 verticalOffset = verticalOffset - 14
        end
    end

    displayWindow.goldSummaryText:SetPoint("TOPLEFT", 10, verticalOffset - 6)
    displayWindow.goldSummaryText:SetText("Total:  " .. FormatMoneyString(totalSessionValue))
    
    local now = GetTime()
    if (now - lastGPHUpdate) >= 5 then
        local masterVelocityRate = CalculateTotalGoldPerHour(totalSessionValue)
        cachedGPHText = "Gold per hour:  " .. FormatMoneyString(masterVelocityRate)
        lastGPHUpdate = now
    end

    displayWindow.velocityText:SetPoint("TOPLEFT", 10, verticalOffset - 20)
    displayWindow.velocityText:SetText(cachedGPHText)

    if lineIndex > 1 then displayWindow:SetSize(240, math.abs(verticalOffset) + 45) else displayWindow:SetSize(240, 90) end
end

local updateTicker = CreateFrame("Frame")
updateTicker:SetScript("OnUpdate", function(self, elapsed)
    if displayWindow and displayWindow:IsShown() then UpdateUIWindow() end
end)

-- ============================================================================
-- GLOBAL EVENTS
-- ============================================================================
frame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == "GatherTracker" then
        if not GatherTrackerDB then GatherTrackerDB = {} end
        if not GatherTrackerDB.Lifetime then GatherTrackerDB.Lifetime = {} end
        if not GatherTrackerDB.HistoryTable then GatherTrackerDB.HistoryTable = {} end
        if not GatherTrackerDB.ManualPrices then GatherTrackerDB.ManualPrices = {} end
        
        if not GatherTrackerSession then GatherTrackerSession = {} end

        CreateTrackingWindow()
        CreatePriceBookWindow() 
        print("|cFF00FF00[GatherTracker] Loaded! Type /gather for options|r")

    elseif event == "CHAT_MSG_LOOT" then
        if isSessionFrozen then return end
        local message = arg1
        local itemLink = string.match(message, "(|c%x+|Hitem.-|h%[.-%]|h|r)")
        if not itemLink then return end

        local itemName = CleanItemName(itemLink)
        if not itemName then return end

        local count = tonumber(string.match(message, "x(%d+)")) or 1

        if GatherTrackerDB.ManualPrices[itemName] then
            GatherTrackerSession[itemName] = (GatherTrackerSession[itemName] or 0) + count
            GatherTrackerDB.Lifetime[itemName] = (GatherTrackerDB.Lifetime[itemName] or 0) + count
        end
    end
end)

-- ============================================================================
-- EXPORT WINDOW
-- ============================================================================
local function ShowExportWindow(csvText, titleText)
    local exportFrame = CreateFrame("Frame", "GatherTrackerExportFrame", UIParent)
    exportFrame:SetSize(400, 300) exportFrame:SetPoint("CENTER", 0, 0)
    exportFrame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background", edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border", 
        tile = true, tileSize = 32, edgeSize = 32, insets = { left = 11, right = 12, top = 12, bottom = 11 }
    })
    exportFrame:SetMovable(true) exportFrame:EnableMouse(true) exportFrame:RegisterForDrag("LeftButton")
    exportFrame:SetScript("OnDragStart", exportFrame.StartMoving) exportFrame:SetScript("OnDragStop", exportFrame.StopMovingOrSizing)
    
    local title = exportFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal") 
    title:SetPoint("TOP", 0, -15) title:SetText(titleText .. " (Ctrl+C to Copy)")
    
    local closeButton = CreateFrame("Button", nil, exportFrame, "UIPanelButtonTemplate") 
    closeButton:SetSize(80, 22) closeButton:SetPoint("BOTTOM", 0, 15) closeButton:SetText("Close") 
    closeButton:SetScript("OnClick", function() exportFrame:Hide() end)
    
    local scrollArea = CreateFrame("ScrollFrame", "GatherTrackerScrollFrame", exportFrame, "UIPanelScrollFrameTemplate") 
    scrollArea:SetPoint("TOPLEFT", 15, -40) scrollArea:SetPoint("BOTTOMRIGHT", -35, 45)
    
    local editBox = CreateFrame("EditBox", nil, scrollArea) 
    editBox:SetMultiLine(true) editBox:SetMaxLetters(99999) editBox:SetFontObject("GameFontHighlight") 
    editBox:SetWidth(350) editBox:SetText(csvText) editBox:HighlightText() 
    editBox:SetScript("OnEscapePressed", function() exportFrame:Hide() end)
    
    scrollArea:SetScrollChild(editBox) exportFrame:Show()
end

local function ExportGatherCSV()
    -- Calculate duration
    local totalSeconds = 0
    if sessionStartTime then
        totalSeconds = isSessionFrozen and frozenSessionDuration or (GetTime() - sessionStartTime)
    end
    local durationMins = math.floor(totalSeconds / 60)

    local csv = "Duration: " .. durationMins .. " minutes\n\n"
    csv = csv .. "Item Name\tCount\tPer Hour Rate\tGold Value\n"
    
    local hasData = false
    local totalSessionValue = 0

    for item, count in pairs(GatherTrackerSession or {}) do
        if count > 0 then
            local price = GetCustomPrice(item) or 0
            local itemTotalValue = price * count
            local perHour = CalculatePerHourRate(count)
            
            csv = csv .. string.format("%s\t%d\t%d/hr\t%.2fg\n", item, count, perHour, itemTotalValue / 10000)
            
            totalSessionValue = totalSessionValue + itemTotalValue
            hasData = true
        end
    end

    if not hasData then 
        csv = csv .. "No items gathered in this session.\n" 
    else
        local totalGPH = CalculateTotalGoldPerHour(totalSessionValue)
        csv = csv .. "\n"
        csv = csv .. string.format("Total Gold:\t\t\t%.2fg\n", totalSessionValue / 10000)
        csv = csv .. string.format("Gold Per Hour:\t\t\t%.2fg\n", totalGPH / 10000)
    end

    ShowExportWindow(csv, "Gather Export")
end


local function ExportLifetimeCSV()
    local csv = "Item Name\tLifetime Count\n"
    for item, count in pairs(GatherTrackerDB and GatherTrackerDB.Lifetime or {}) do
        csv = csv .. string.format("%s\t%d\n", item, count)
    end
    ShowExportWindow(csv, "Lifetime Export")
end

-- ============================================================================
-- MAIN MENU
-- ============================================================================
local function CreateMainMenuWindow()
    if menuWindow then return menuWindow end
    local f = CreateFrame("Frame", "GatherTrackerMenuFrame", UIParent)
    f:SetSize(280, 192)
    f:SetPoint("CENTER", 0, 0)
    f:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 }
    })
    f:SetMovable(true) f:EnableMouse(true) f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving) f:SetScript("OnDragStop", f.StopMovingOrSizing)

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -12) title:SetText("Gather Tracker")

    local function makeBtn(text, y, onClick)
        local b = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        b:SetSize(220, 26) b:SetPoint("TOP", 0, y) b:SetText(text)
        b:SetScript("OnClick", function()
            if menuWindow then menuWindow:Hide() end
            onClick()
        end)
        return b
    end

    makeBtn("Gather Whitelist", -40, function()
        if priceWindow then priceWindow:Show() end
    end)

    makeBtn("Open Gather Tracker", -72, function()
        if displayWindow then displayWindow:Show() UpdateUIWindow() end
    end)

    makeBtn("Export Session Data", -104, function()
        ExportGatherCSV()
    end)

    local closeBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    closeBtn:SetSize(100, 22) closeBtn:SetPoint("BOTTOM", 0, 12) closeBtn:SetText("Close")
    closeBtn:SetScript("OnClick", function() f:Hide() end)

    f:Hide()
    menuWindow = f
    return menuWindow
end

local function EnsureAllWindows()
    CreateMainMenuWindow()
    CreateTrackingWindow()
    CreatePriceBookWindow()
end

-- ============================================================================
-- SLASH COMMANDS
-- ============================================================================
SLASH_GATHERTRACKER1 = "/gather"
SlashCmdList["GATHERTRACKER"] = function(msg)
    msg = msg and msg:lower() or ""

    if msg == "price" then
        if priceWindow then priceWindow:Show() end
        if menuWindow then menuWindow:Hide() end
        return
    end

    if msg == "export" then
        ExportGatherCSV()
        if menuWindow then menuWindow:Hide() end
        return
    end
    
    if msg == "export lifetime" then
        ExportLifetimeCSV()
        if menuWindow then menuWindow:Hide() end
        return
    end

    if msg == "new" then
        local dStr = date("%Y-%m-%d %H:%M:%S")
        local hasData = false

        for _, count in pairs(GatherTrackerSession or {}) do
            if count > 0 then hasData = true break end
        end
        if hasData then
            GatherTrackerDB.HistoryTable[dStr] = {}
            for item, total in pairs(GatherTrackerSession) do
                if total > 0 then GatherTrackerDB.HistoryTable[dStr][item] = total end
            end
            print("|cFF00FF00[GatherTracker] Run archived: " .. dStr .. "|r")
        end

        GatherTrackerSession = {}
        isSessionFrozen = false
        frozenSessionDuration = 0
        sessionStartTime = GetTime()
        lastGPHUpdate = 0

        if displayWindow then
            UpdateUIWindow()
            displayWindow:Show()
        end
        return
    end

    if msg == "stop" then
        if sessionStartTime and not isSessionFrozen then
            isSessionFrozen = true
            frozenSessionDuration = GetTime() - sessionStartTime
            if displayWindow then UpdateUIWindow() end
            print("|cFF00FF00[GatherTracker] Session paused!|r")
        end
        return
    end

    if msg == "go" then
        if sessionStartTime and isSessionFrozen then
            sessionStartTime = GetTime() - frozenSessionDuration
            isSessionFrozen = false
            frozenSessionDuration = 0
            lastGPHUpdate = 0
            if displayWindow then UpdateUIWindow() end
            print("|cFF00FF00[GatherTracker] Session resumed!|r")
        elseif not sessionStartTime then
            sessionStartTime = GetTime()
            isSessionFrozen = false
            frozenSessionDuration = 0
            lastGPHUpdate = 0
            if displayWindow then UpdateUIWindow() displayWindow:Show() end
            print("|cFF00FF00[GatherTracker] Session started!|r")
        end
        return
    end

    if msg == "track" then
        if displayWindow then
            UpdateUIWindow()
            displayWindow:Show()
        end
        if menuWindow then menuWindow:Hide() end
        return
    end

    if msg == "" or msg == "menu" then
        EnsureAllWindows()
        if menuWindow then
            if menuWindow:IsShown() then menuWindow:Hide()
            else menuWindow:Show() end
        end
        return
    end

    print("|cFF00FF00[GatherTracker] Commands: /gather | /gather price | /gather track | /gather export | /gather stop | /gather go | /gather new|r")
end