-- ============================================================================
-- GATHERTRACKER - Crafting Module
-- ============================================================================
local craftFrame = CreateFrame("Frame")
craftFrame:RegisterEvent("ADDON_LOADED")
craftFrame:RegisterEvent("CHAT_MSG_LOOT")

local craftRowLines = {}
GatherTrackerCraftPos = GatherTrackerCraftPos or {}

local function GetCraftPrice(itemName)
    if not itemName then return 0 end
    if GatherTrackerDB and GatherTrackerDB.CraftPrices and GatherTrackerDB.CraftPrices[itemName] then
        return math.floor((tonumber(GatherTrackerDB.CraftPrices[itemName]) or 0) * 10000 + 0.5)
    end
    return 0
end

local function CreateCraftingTrackingWindow()
    local f = CreateFrame("Frame", "GatherTrackerCraftUIFrame", UIParent)
    f:SetSize(240, 90)
    GatherTracker.RestoreFramePos(f, GatherTrackerCraftPos, "CENTER", 150, 100)
    f:SetBackdrop({bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", tile = true, tileSize = 16, edgeSize = 16, insets = { left = 4, right = 4, top = 4, bottom = 4 }})
    f:SetMovable(true) f:EnableMouse(true) f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() GatherTracker.SaveFramePos(self, GatherTrackerCraftPos) end)

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", 10, -12) title:SetText("Craft Tracker") title:SetTextColor(0.0, 1.0, 1.0, 1.0)
    
    local goldSummaryText = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    goldSummaryText:SetText("Crafting Value: 0.00g")
    f.goldSummaryText = goldSummaryText

    local closeBtn = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", 2, 2) closeBtn:SetSize(22, 22) closeBtn:SetScript("OnClick", function() f:Hide() end)

    local clearBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    clearBtn:SetSize(55, 20) clearBtn:SetPoint("BOTTOM", 0, 8) clearBtn:SetText("Clear")
    clearBtn:SetScript("OnClick", function()
        GatherTrackerDB.SessionCrafts = {}
        if GatherTracker.UpdateCraftingUI then GatherTracker.UpdateCraftingUI() end
        print("|cff00ffff[GatherTracker]|r Craft Session cleared.")
    end)

    f:Hide()
    GatherTracker.CraftDisplayWindow = f
end

function GatherTracker.UpdateCraftingUI()
    if not GatherTracker.CraftDisplayWindow or not GatherTrackerDB then return end

    for _, line in ipairs(craftRowLines) do if line.text then line.text:SetText("") end line:Hide() end
    local lineIndex, verticalOffset, totalCraftValue = 1, -30, 0

    for item, data in pairs(GatherTrackerDB.SessionCrafts or {}) do
        if data.count > 0 then
            if not craftRowLines[lineIndex] then
                local lf = CreateFrame("Frame", nil, GatherTracker.CraftDisplayWindow) lf:SetSize(220, 16)
                local fs = lf:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall") fs:SetPoint("LEFT", 0, 0)
                lf.text = fs craftRowLines[lineIndex] = lf
            end
            
            local colorHex = GatherTracker.GetQualityColor(item)
            local singleUnitPrice = GetCraftPrice(item)
            local itemTotalValue = singleUnitPrice * data.count
            totalCraftValue = totalCraftValue + itemTotalValue
            
            local ratePerCast = data.count / data.casts
            
            local currentLine = craftRowLines[lineIndex] currentLine:SetPoint("TOPLEFT", 10, verticalOffset)
            currentLine.text:SetText(string.format("%s%s|r x%d (%.2f/c) - |cffffd700%.2fg|r", colorHex, item, data.count, ratePerCast, itemTotalValue / 10000))
            currentLine:Show() lineIndex = lineIndex + 1 verticalOffset = verticalOffset - 14
        end
    end

    GatherTracker.CraftDisplayWindow.goldSummaryText:SetPoint("TOPLEFT", 10, verticalOffset - 6)
    GatherTracker.CraftDisplayWindow.goldSummaryText:SetText("Total Session Value:  " .. GatherTracker.FormatMoneyString(totalCraftValue))

    if lineIndex > 1 then GatherTracker.CraftDisplayWindow:SetSize(240, math.abs(verticalOffset) + 50) else GatherTracker.CraftDisplayWindow:SetSize(240, 90) end
end

function GatherTracker.ExportCraftCSV()
    local csv = "Item Name\tCasts\tYield\tYield/Cast\tGold Value\n"
    local totalValue = 0
    for item, data in pairs(GatherTrackerDB.SessionCrafts or {}) do
        if data.count > 0 then
            local singlePrice = GetCraftPrice(item)
            local val = singlePrice * data.count
            totalValue = totalValue + val
            csv = csv .. string.format("%s\t%d\t%d\t%.2f\t%.2fg\n", item, data.casts, data.count, data.count/data.casts, val/10000)
        end
    end
    if totalValue == 0 then csv = csv .. "No items crafted in this session.\n" end
    csv = csv .. string.format("\nTotal Session Value:\t\t\t\t%.2fg\n", totalValue/10000)
    GatherTracker.DisplayMenuText(csv, "Craft Export")
end

craftFrame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == "GatherTracker" then
        CreateCraftingTrackingWindow()

    elseif event == "CHAT_MSG_LOOT" then
        if string.find(arg1, "Create") or string.find(arg1, "create") then
            local itemLink = string.match(arg1, "(|c%x+|Hitem.-|h%[.-%]|h|r)")
            if not itemLink then return end
            
            local itemName = GatherTracker.CleanItemName(itemLink)
            local count = tonumber(string.match(arg1, "x(%d+)")) or 1

            if GatherTrackerDB.CraftPrices and GatherTrackerDB.CraftPrices[itemName] then
                if not GatherTrackerDB.SessionCrafts[itemName] then
                    GatherTrackerDB.SessionCrafts[itemName] = { casts = 0, count = 0 }
                end
                
                GatherTrackerDB.SessionCrafts[itemName].casts = GatherTrackerDB.SessionCrafts[itemName].casts + 1
                GatherTrackerDB.SessionCrafts[itemName].count = GatherTrackerDB.SessionCrafts[itemName].count + count
                
                if GatherTracker.CraftDisplayWindow and GatherTracker.CraftDisplayWindow:IsShown() then
                    GatherTracker.UpdateCraftingUI()
                end
            end
        end
    end
end)