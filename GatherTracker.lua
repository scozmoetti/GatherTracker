-- ============================================================================
-- GATHERTRACKER - Unified Edition (Core & Gather Module)
-- ============================================================================
GatherTracker = {}
local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("CHAT_MSG_LOOT")

-- Windows
local displayWindow, menuWindow = nil, nil
local rowLines = {}
local lastGPHUpdate = 0
local cachedGPHText = "Gold per hour:  0.00g"

-- Persistent Stopwatch State
local lastTickTime = GetTime()

-- Saved positions
GatherTrackerPos = GatherTrackerPos or {}

-- ============================================================================
-- UTILITIES
-- ============================================================================
local function FormatDuration(secs)
    if secs <= 0 then return "0 mins" end
    local hrs = math.floor(secs / 3600)
    local mins = (secs % 3600) / 60
    if hrs > 0 then return string.format("%d hr %.1f min", hrs, mins)
    else return string.format("%.1f min", mins) end
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
    if not GatherTrackerDB or GatherTrackerDB.GatherTime <= 0 or count <= 0 then return 0 end
    local hoursPassed = GatherTrackerDB.GatherTime / 3600
    if hoursPassed <= 0 then return 0 end
    return math.floor(count / hoursPassed + 0.5)
end

local function CalculateTotalGoldPerHour(totalCopper)
    if not GatherTrackerDB or GatherTrackerDB.GatherTime <= 0 or totalCopper <= 0 then return 0 end
    local hoursPassed = GatherTrackerDB.GatherTime / 3600
    if hoursPassed <= 0 then return 0 end
    return math.floor(totalCopper / hoursPassed + 0.5)
end

local function SaveFramePos(f, store)
    if not f or not store then return end
    local point, _, relativePoint, xOfs, yOfs = f:GetPoint()
    store.point, store.relativePoint, store.x, store.y = point, relativePoint, xOfs, yOfs
end

local function RestoreFramePos(f, store, defaultPoint, dx, dy)
    if store and store.x then
        f:ClearAllPoints()
        f:SetPoint(store.point, UIParent, store.relativePoint, store.x, store.y)
    else
        f:ClearAllPoints()
        f:SetPoint(defaultPoint, UIParent, defaultPoint, dx or 0, dy or 0)
    end
end

GatherTracker.CleanItemName = CleanItemName
GatherTracker.FormatMoneyString = FormatMoneyString
GatherTracker.GetQualityColor = GetQualityColor
GatherTracker.SaveFramePos = SaveFramePos
GatherTracker.RestoreFramePos = RestoreFramePos

-- ============================================================================
-- MAIN MENU UI (High Strata, Esc-Closable, Unified Export)
-- ============================================================================
local currentActiveList = "Gather"

local function CreateMainMenuWindow()
    if menuWindow then return menuWindow end

    local f = CreateFrame("Frame", "GatherTrackerMenuFrame", UIParent)
    f:SetSize(480, 320)
    f:SetPoint("CENTER", 0, 0)
    f:SetFrameStrata("HIGH") -- Ensures it floats above all other tracker windows
    f:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background", edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32, insets = { left = 11, right = 12, top = 12, bottom = 11 }
    })
    f:SetMovable(true) f:EnableMouse(true) f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving) f:SetScript("OnDragStop", f.StopMovingOrSizing)
    
    -- Enables the Escape key to close the menu
    tinsert(UISpecialFrames, "GatherTrackerMenuFrame")

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 20, -20) title:SetText("Gather Tracker")
    GatherTracker.MenuTitle = title

    local closeBtn = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", -2, -2)

    -- Shared Text Box Area
    local scrollFrame = CreateFrame("ScrollFrame", "GatherTrackerMenuScroll", f, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPRIGHT", -35, -45)
    scrollFrame:SetSize(210, 210)

    -- Text Box Border Wrapper
    local scrollBorder = CreateFrame("Frame", nil, f)
    scrollBorder:SetPoint("TOPLEFT", scrollFrame, "TOPLEFT", -6, 6)
    scrollBorder:SetPoint("BOTTOMRIGHT", scrollFrame, "BOTTOMRIGHT", 27, -5)
    scrollBorder:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 }
    })
    scrollBorder:SetBackdropColor(0.05, 0.05, 0.05, 0.8)

    local editBox = CreateFrame("EditBox", nil, scrollFrame)
    editBox:SetMultiLine(true) editBox:SetMaxLetters(99999) editBox:SetFontObject("GameFontHighlight")
    editBox:SetWidth(205) scrollFrame:SetScrollChild(editBox)
    GatherTracker.MenuEditBox = editBox

    local function LoadActiveList()
        local str = ""
        local db = (currentActiveList == "Gather") and GatherTrackerDB.ManualPrices or GatherTrackerDB.CraftPrices
        for item, price in pairs(db or {}) do
            if price > 0 then str = str .. item .. " " .. price .. "\n" end
        end
        editBox:SetText(str)
        -- Intentionally not setting focus or highlighting text to prevent auto-typing
    end

    f:SetScript("OnShow", function()
        if not f.preventLoad then
            if currentActiveList == "Export" then currentActiveList = "Gather" end
            GatherTracker.MenuTitle:SetText(currentActiveList .. " Pricelist")
            LoadActiveList()
        end
    end)

    -- User provided Import Button size and position
    local importBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    importBtn:SetSize(65, 22) importBtn:SetPoint("BOTTOMLEFT", 380, 20) importBtn:SetText("Import")
    importBtn:SetScript("OnClick", function()
        if currentActiveList == "Export" then 
            print("|cFFFF0000[GatherTracker]|r Cannot import data while viewing an Export. Please click 'Gather Pricelist' or 'Craft Pricelist' first.")
            return 
        end
        
        local rawText = editBox:GetText()
        local targetDB = {}
        local foundCount = 0
        for name, price in string.gmatch(rawText, "([%a%s'%-%(%):]+)(%d+%.?%d*)") do
            local cleanName = string.match(name, "^%s*(.-)%s*$")
            local numPrice = tonumber(price)
            if cleanName and cleanName ~= "" and numPrice then
                targetDB[cleanName] = numPrice
                foundCount = foundCount + 1
            end
        end
        
        if currentActiveList == "Gather" then
            GatherTrackerDB.ManualPrices = targetDB
            if displayWindow and displayWindow:IsShown() then GatherTracker.UpdateUIWindow() end
        else
            GatherTrackerDB.CraftPrices = targetDB
            if GatherTracker.UpdateCraftingUI then GatherTracker.UpdateCraftingUI() end
        end
        print("|cFF00FF00[GatherTracker]|r " .. currentActiveList .. " whitelist synced! (" .. foundCount .. " items)")
    end)

    -- Pricelist Swapping Buttons
    local btnGatherPrice = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    btnGatherPrice:SetPoint("TOPLEFT", 20, -50) btnGatherPrice:SetSize(160, 26) btnGatherPrice:SetText("Gather Pricelist")
    
    local btnCraftPrice = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    btnCraftPrice:SetPoint("TOPLEFT", 20, -85) btnCraftPrice:SetSize(160, 26) btnCraftPrice:SetText("Craft Pricelist")

    btnGatherPrice:SetScript("OnClick", function() currentActiveList = "Gather"; GatherTracker.MenuTitle:SetText("Gather Pricelist"); LoadActiveList() end)
    btnCraftPrice:SetScript("OnClick", function() currentActiveList = "Craft"; GatherTracker.MenuTitle:SetText("Craft Pricelist"); LoadActiveList() end)

    -- Tracker Open Buttons
    local btnGather = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    btnGather:SetPoint("TOPLEFT", 20, -140) btnGather:SetSize(75, 26) btnGather:SetText("Gather")
    btnGather:SetScript("OnClick", function() if displayWindow then displayWindow:Show() GatherTracker.UpdateUIWindow() end end)

    local btnCraft = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    btnCraft:SetPoint("TOPLEFT", 105, -140) btnCraft:SetSize(75, 26) btnCraft:SetText("Craft")
    btnCraft:SetScript("OnClick", function() if GatherTracker.CraftDisplayWindow then GatherTracker.CraftDisplayWindow:Show() end end)

    local btnProcess = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    btnProcess:SetPoint("TOPLEFT", 62, -175) btnProcess:SetSize(75, 26) btnProcess:SetText("Process")
    btnProcess:SetScript("OnClick", function() if GatherTracker.ToggleProcessWindow then GatherTracker.ToggleProcessWindow() end end)

    -- Export Bottom Section
    local exportLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    exportLabel:SetPoint("BOTTOMLEFT", 20, 25) exportLabel:SetText("Export data:")

    local expGather = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    expGather:SetPoint("LEFT", exportLabel, "RIGHT", 10, 0) expGather:SetSize(65, 22) expGather:SetText("Gather")
    expGather:SetScript("OnClick", function() GatherTracker.ExportGatherCSV() end)

    local expCraft = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    expCraft:SetPoint("LEFT", expGather, "RIGHT", 5, 0) expCraft:SetSize(65, 22) expCraft:SetText("Craft")
    expCraft:SetScript("OnClick", function() if GatherTracker.ExportCraftCSV then GatherTracker.ExportCraftCSV() end end)

    local expProcess = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    expProcess:SetPoint("LEFT", expCraft, "RIGHT", 5, 0) expProcess:SetSize(65, 22) expProcess:SetText("Process")
    expProcess:SetScript("OnClick", function() if GatherTracker.ExportProcessCSV then GatherTracker.ExportProcessCSV() end end)

    f:Hide() menuWindow = f return menuWindow
end

-- Used by all 3 modules to display their text in the main menu box
function GatherTracker.DisplayMenuText(csvText, titleText)
    if not menuWindow then CreateMainMenuWindow() end
    menuWindow.preventLoad = true
    menuWindow:Show()
    currentActiveList = "Export"
    GatherTracker.MenuTitle:SetText(titleText .. " (Ctrl+C to Copy)")
    GatherTracker.MenuEditBox:SetText(csvText)
    GatherTracker.MenuEditBox:HighlightText()
    menuWindow.preventLoad = false
end

-- ============================================================================
-- MAIN GATHER TRACKER UI
-- ============================================================================
local function CreateTrackingWindow()
    if displayWindow then return displayWindow end

    local f = CreateFrame("Frame", "GatherTrackerUIFrame", UIParent)
    f:SetSize(240, 120)
    RestoreFramePos(f, GatherTrackerPos, "CENTER", -150, 100)
    f:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16, insets = { left = 4, right = 4, top = 4, bottom = 4 }
    })
    f:SetMovable(true) f:EnableMouse(true) f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() SaveFramePos(self, GatherTrackerPos) end)

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", 10, -12) title:SetText("Gather Tracker") title:SetTextColor(0.267, 0.600, 0.745, 1.0)
    
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

    local playBtn = CreateFrame("Button", nil, f)
    playBtn:SetSize(18, 18) playBtn:SetPoint("TOPRIGHT", -28, -8)
    playBtn.texture = playBtn:CreateTexture(nil, "ARTWORK") playBtn.texture:SetAllPoints(playBtn)
    playBtn.texture:SetTexture("Interface\\Buttons\\UI-SpellbookIcon-NextPage-Up")
    playBtn:SetScript("OnClick", function()
        GatherTrackerDB.IsSessionFrozen = false
        print("|cFF00FF00[GatherTracker] Session playing!|r")
        if displayWindow then GatherTracker.UpdateUIWindow() displayWindow:Show() end
    end)

    local pauseBtn = CreateFrame("Button", nil, f)
    pauseBtn:SetSize(18, 18) pauseBtn:SetPoint("TOPRIGHT", -10, -8)
    pauseBtn.texture = pauseBtn:CreateTexture(nil, "ARTWORK") pauseBtn.texture:SetAllPoints(pauseBtn)
    pauseBtn.texture:SetTexture("Interface\\TimeManager\\PauseButton")
    pauseBtn:SetScript("OnClick", function()
        GatherTrackerDB.IsSessionFrozen = true
        print("|cFF00FF00[GatherTracker] Session paused!|r")
        if displayWindow then GatherTracker.UpdateUIWindow() end
    end)

    local clearBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    clearBtn:SetSize(55, 20) clearBtn:SetPoint("BOTTOM", 0, 8) clearBtn:SetText("Clear")
    clearBtn:SetScript("OnClick", function()
        GatherTrackerDB.Session = {}
        GatherTrackerDB.GatherTime = 0
        GatherTrackerDB.IsSessionFrozen = true
        if displayWindow then GatherTracker.UpdateUIWindow() end
        print("|cFF00FF00[GatherTracker]|r Session cleared.")
    end)

    f:Hide() displayWindow = f return displayWindow
end

function GatherTracker.UpdateUIWindow()
    if not displayWindow or not GatherTrackerDB then return end
    
    local secs = GatherTrackerDB.GatherTime or 0
    local hrs = math.floor(secs / 3600) local mins = (secs - hrs * 3600) / 60
    local prefix = GatherTrackerDB.IsSessionFrozen and "Paused: " or "Time: " 
    local color = GatherTrackerDB.IsSessionFrozen and "|cff00ff00" or ""
    
    if secs > 0 then
        if hrs > 0 then displayWindow.timerText:SetText(string.format("%s%s%d hr %.1f m|r", color, prefix, hrs, mins))
        else displayWindow.timerText:SetText(string.format("%s%s%.1f mins|r", color, prefix, mins)) end
    else
        displayWindow.timerText:SetText("No active session.")
    end

    for _, line in ipairs(rowLines) do if line.text then line.text:SetText("") end line:Hide() end
    local lineIndex, verticalOffset, totalSessionValue = 1, -44, 0

    for item, total in pairs(GatherTrackerDB.Session or {}) do
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

    if lineIndex > 1 then displayWindow:SetSize(240, math.abs(verticalOffset) + 65) else displayWindow:SetSize(240, 110) end
end

local updateTicker = CreateFrame("Frame")
updateTicker:SetScript("OnUpdate", function(self, elapsed)
    local now = GetTime()
    if GatherTrackerDB and not GatherTrackerDB.IsSessionFrozen then
        GatherTrackerDB.GatherTime = (GatherTrackerDB.GatherTime or 0) + (now - lastTickTime)
    end
    lastTickTime = now

    if displayWindow and displayWindow:IsShown() then GatherTracker.UpdateUIWindow() end
end)

-- ============================================================================
-- GLOBAL EVENTS
-- ============================================================================
frame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == "GatherTracker" then
        if not GatherTrackerDB then GatherTrackerDB = {} end
        if not GatherTrackerDB.Session then GatherTrackerDB.Session = {} end
        if not GatherTrackerDB.SessionCrafts then GatherTrackerDB.SessionCrafts = {} end
        if not GatherTrackerDB.Process then GatherTrackerDB.Process = { Session = {} } end
        if not GatherTrackerDB.ManualPrices then GatherTrackerDB.ManualPrices = {} end
        if not GatherTrackerDB.CraftPrices then GatherTrackerDB.CraftPrices = {} end
        if GatherTrackerDB.GatherTime == nil then GatherTrackerDB.GatherTime = 0 end
        if GatherTrackerDB.IsSessionFrozen == nil then GatherTrackerDB.IsSessionFrozen = true end
        
        lastTickTime = GetTime()

        CreateTrackingWindow()
        CreateMainMenuWindow() 
        print("|cFF00FF00[GatherTracker] Unified Modules Loaded! Type /gather|r")

    elseif event == "CHAT_MSG_LOOT" then
        if not GatherTrackerDB or GatherTrackerDB.IsSessionFrozen then return end
        local message = arg1
        local itemLink = string.match(message, "(|c%x+|Hitem.-|h%[.-%]|h|r)")
        if not itemLink then return end

        local itemName = CleanItemName(itemLink)
        if not itemName then return end

        local count = tonumber(string.match(message, "x(%d+)")) or 1

        if GatherTrackerDB.ManualPrices[itemName] and not string.find(message, "Create") and not string.find(message, "create") then
            GatherTrackerDB.Session[itemName] = (GatherTrackerDB.Session[itemName] or 0) + count
        end
    end
end)

function GatherTracker.ExportGatherCSV()
    local totalSeconds = GatherTrackerDB.GatherTime or 0
    local durationMins = math.floor(totalSeconds / 60)

    local csv = "Duration: " .. durationMins .. " minutes\n\nItem Name\tCount\tPer Hour Rate\tGold Value\n"
    local hasData = false local totalSessionValue = 0

    for item, count in pairs(GatherTrackerDB.Session or {}) do
        if count > 0 then
            local price = GetCustomPrice(item) or 0
            local itemTotalValue = price * count
            local perHour = CalculatePerHourRate(count)
            csv = csv .. string.format("%s\t%d\t%d/hr\t%.2fg\n", item, count, perHour, itemTotalValue / 10000)
            totalSessionValue = totalSessionValue + itemTotalValue
            hasData = true
        end
    end

    if not hasData then csv = csv .. "No items gathered in this session.\n" 
    else
        local totalGPH = CalculateTotalGoldPerHour(totalSessionValue)
        csv = csv .. "\nTotal Gold:\t\t\t%.2fg\nGold Per Hour:\t\t\t%.2fg\n"
        csv = string.format(csv, totalSessionValue / 10000, totalGPH / 10000)
    end
    GatherTracker.DisplayMenuText(csv, "Gather Export")
end

-- ============================================================================
-- SLASH COMMANDS
-- ============================================================================
SLASH_GATHERTRACKER1 = "/gather"
SlashCmdList["GATHERTRACKER"] = function(msg)
    msg = msg and msg:lower() or ""
    if msg == "menu" or msg == "" then 
        if menuWindow then if menuWindow:IsShown() then menuWindow:Hide() else menuWindow:Show() end end 
    end
end