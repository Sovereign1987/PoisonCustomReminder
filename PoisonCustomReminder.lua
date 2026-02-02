-- INITIALISIERUNG DES NAMESPACES & LOCALES --------------------------------
local ADDON_NAME, ns = ...
local L = setmetatable(ns.L or {}, { __index = function(t, k) return k end })

-- KONFIGURATION & DATEN ---------------------------------------------------
local MAX_POISON_SLOTS = 4 

local DEFAULT_SETUP = {
    raid     = { 0, 0, 0, 0 },
    party    = { 0, 0, 0, 0 },
    pvp      = { 0, 0, 0, 0 },
    arena    = { 0, 0, 0, 0 },
    none     = { 0, 0, 0, 0 },
    scenario = { 0, 0, 0, 0 },
}
local EMPTY_FALLBACK = { 0, 0, 0, 0 }

local _, PLAYER_CLASS = UnitClass("player")
local IS_ROGUE = (PLAYER_CLASS == "ROGUE")

local ALL_POISONS = {
    { id = 0,      name = L["EMPTY / REMOVE"] }, 
    { id = 2823,   name = L["Deadly"] },      { id = 315584, name = L["Instant"] },
    { id = 8679,   name = L["Wound"] },       { id = 381664, name = L["Amplifying"] },
    { id = 3408,   name = L["Crippling"] },   { id = 5761,   name = L["Numbing"] },
    { id = 381637, name = L["Atrophic"] },
}

local ZONES = {
    { key = "raid",     label = L["Raid"] },       { key = "party",    label = L["Dungeon"] },
    { key = "pvp",      label = L["BG"] },         { key = "arena",    label = L["Arena"] },
    { key = "none",     label = L["Open World"] }, { key = "scenario", label = L["Delves"] },
}

local gameplayButtons = {} 
local holderFrame, configFrame
local activeCustomItems = {} 

-- LAYOUT CONSTANTS
local COL_NAME_WIDTH = 220  
local COL_CHECK_START = 270 
local COL_CHECK_DIST = 35   

-- HILFSFUNKTIONEN ---------------------------------------------------------
local function GetIconForType(id, trackType)
    if id == 0 then return "Interface\\Buttons\\UI-GroupLoot-Pass-Up" end
    if trackType == "buff_spell" then
        local info = C_Spell.GetSpellInfo(id)
        return info and info.iconID or 134400
    else
        local _, _, _, _, _, _, _, _, _, icon = GetItemInfo(id)
        if not icon then 
            C_Item.RequestLoadItemDataByID(id) 
            return 134400 
        end
        return icon
    end
end

local function GetCurrentZoneType()
    local _, instanceType = GetInstanceInfo()
    if DEFAULT_SETUP[instanceType] then return instanceType end
    return "none"
end

-- BUTTON MANAGEMENT -------------------------------------------------------
local function CreateGameplayButton(index)
    local btn = CreateFrame("Button", "PCR_Btn"..index, holderFrame, "SecureActionButtonTemplate")
    btn:SetSize(45, 45)
    btn:EnableMouse(true)
    btn:RegisterForClicks("AnyUp", "AnyDown")
    
    btn.icon = btn:CreateTexture(nil, "BACKGROUND")
    btn.icon:SetAllPoints()
    
    btn.text = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    btn.text:SetPoint("TOP", btn, "BOTTOM", 0, -5)
    btn.text:SetText(L["MISSING"])
    
    btn:Hide()
    return btn
end

local function UpdateButtonsToZone()
    if InCombatLockdown() then return end 
    local zone = GetCurrentZoneType()
    
    local settings = EMPTY_FALLBACK
    if IS_ROGUE then 
        settings = PoisonCustomDB[zone] or DEFAULT_SETUP[zone] or EMPTY_FALLBACK
    end
    
    activeCustomItems = {}
    if PoisonCustomDB.customItems then
        for _, item in ipairs(PoisonCustomDB.customItems) do
            if item.zones[zone] then table.insert(activeCustomItems, item) end
        end
    end

    local totalSlots = MAX_POISON_SLOTS + #activeCustomItems
    local visibleCount = #activeCustomItems
    if IS_ROGUE then visibleCount = visibleCount + MAX_POISON_SLOTS end
    
    if visibleCount == 0 then holderFrame:SetWidth(100) else holderFrame:SetWidth(60 + (visibleCount * 50)) end

    local currentVisibleIndex = 0
    for i = 1, totalSlots do
        if not gameplayButtons[i] then gameplayButtons[i] = CreateGameplayButton(i) end
        local btn = gameplayButtons[i]
        
        if i <= MAX_POISON_SLOTS then
            if IS_ROGUE then
                currentVisibleIndex = currentVisibleIndex + 1
                local spellID = settings[i] or 0
                btn.checkType = "spell"
                btn.checkID = spellID
                
                local xOffset = -((visibleCount-1)*50)/2 + ((currentVisibleIndex-1)*50)
                btn:SetPoint("CENTER", holderFrame, "CENTER", xOffset, 0)

                if spellID > 0 then
                    btn:SetAttribute("type", "spell")
                    btn:SetAttribute("spell", spellID)
                    btn.icon:SetTexture(C_Spell.GetSpellInfo(spellID).iconID)
                    btn:Show() 
                else
                    btn:SetAttribute("type", nil)
                    btn:Hide(); btn.checkID = 0
                end
            else
                btn:SetAttribute("type", nil)
                btn:Hide(); btn.checkID = 0
            end
        else
            currentVisibleIndex = currentVisibleIndex + 1
            local itemData = activeCustomItems[i - MAX_POISON_SLOTS]
            btn.checkType = itemData.trackType 
            btn.checkID = itemData.id
            
            local xOffset = -((visibleCount-1)*50)/2 + ((currentVisibleIndex-1)*50)
            btn:SetPoint("CENTER", holderFrame, "CENTER", xOffset, 0)
            
            if itemData.trackType == "buff_spell" then
                btn:SetAttribute("type", "spell")
                btn:SetAttribute("spell", itemData.id)
            else
                btn:SetAttribute("type", "item")
                btn:SetAttribute("item", "item:"..itemData.id)
            end
            
            btn.icon:SetTexture(GetIconForType(itemData.id, itemData.trackType))
            btn:Show()
        end
    end
    
    for i = totalSlots + 1, #gameplayButtons do
        gameplayButtons[i]:Hide(); gameplayButtons[i].checkID = 0
    end
end

-- INITIALISIERUNG ---------------------------------------------------------
local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("ADDON_LOADED")
initFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
initFrame:RegisterEvent("GET_ITEM_INFO_RECEIVED") 

initFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        local addonName = ...
        if addonName == ADDON_NAME then
            if not PoisonCustomDB then PoisonCustomDB = {} end
            for _, z in ipairs(ZONES) do
                if not PoisonCustomDB[z.key] then 
                    PoisonCustomDB[z.key] = CopyTable(DEFAULT_SETUP[z.key] or EMPTY_FALLBACK)
                end
            end
            if not PoisonCustomDB.customItems then PoisonCustomDB.customItems = {} end
            
            if PoisonCustomDB.position and holderFrame then
                holderFrame:ClearAllPoints()
                local point, relTo, relPoint, x, y = unpack(PoisonCustomDB.position)
                holderFrame:SetPoint(point, UIParent, relPoint, x, y)
            end
        end
        
    elseif event == "PLAYER_ENTERING_WORLD" then
        if not InCombatLockdown() then UpdateButtonsToZone() end
        
    elseif event == "GET_ITEM_INFO_RECEIVED" then
        local itemID, success = ...
        if success then
            for _, btn in pairs(gameplayButtons) do
                if btn:IsShown() and btn.checkID == itemID and btn.checkType ~= "spell" and btn.checkType ~= "buff_spell" then
                    local _, _, _, _, _, _, _, _, _, icon = GetItemInfo(itemID)
                    if icon then btn.icon:SetTexture(icon) end
                end
            end
        end
    end
end)

-- WATCHER -----------------------------------------------------------------
local function HasBuffByName(targetName)
    if not targetName then return false end
    for i = 1, 40 do
        local aura = C_UnitAuras.GetAuraDataByIndex("player", i, "HELPFUL")
        if not aura then return false end 
        local status, result = pcall(function() return aura.name == targetName end)
        if status and result then return true end
    end
    return false
end

local watcher = CreateFrame("Frame")
local timer = 0
watcher:SetScript("OnUpdate", function(self, elapsed)
    timer = timer + elapsed
    if timer < 0.5 then return end
    timer = 0
    
    if InCombatLockdown() or UnitIsDeadOrGhost("player") then return end
    if EditModeManagerFrame and EditModeManagerFrame:IsShown() then return end
    if holderFrame:IsMouseEnabled() then return end 

    for i, btn in ipairs(gameplayButtons) do
        if btn.checkID and btn.checkID > 0 then
            local isMissing = true
            
            if btn.checkType == "spell" or btn.checkType == "buff_spell" then
                isMissing = (C_UnitAuras.GetPlayerAuraBySpellID(btn.checkID) == nil)
            elseif btn.checkType == "buff_item" then
                local itemName = GetItemInfo(btn.checkID)
                if itemName then isMissing = not HasBuffByName(itemName) end
            elseif btn.checkType == "weapon_mh" then
                local hasMH = GetWeaponEnchantInfo()
                isMissing = not hasMH
            elseif btn.checkType == "weapon_oh" then
                local _, _, _, _, hasOH = GetWeaponEnchantInfo()
                isMissing = not hasOH
            end
            
            if isMissing then btn:Show() else btn:Hide() end
            btn:SetAlpha(1)
        else
            btn:Hide()
        end
    end
end)

-- HOLDER UI ---------------------------------------------------------------
holderFrame = CreateFrame("Frame", "PCR_Holder", UIParent, "BackdropTemplate")
holderFrame:SetSize(220, 60); holderFrame:SetPoint("CENTER", UIParent, "CENTER", 0, -100)
holderFrame:SetMovable(true); holderFrame:EnableMouse(false); holderFrame:SetClampedToScreen(true); holderFrame:SetAlpha(1) 
holderFrame:SetBackdrop({bgFile="Interface/Tooltips/UI-Tooltip-Background", edgeFile="Interface/Tooltips/UI-Tooltip-Border", tile=true, tileSize=16, edgeSize=16, insets={left=4,right=4,top=4,bottom=4}})
holderFrame:SetBackdropColor(0,1,0,0); holderFrame:SetBackdropBorderColor(0,1,0,0)
holderFrame:RegisterForDrag("LeftButton"); holderFrame:SetScript("OnDragStart", function(s) s:StartMoving() end); holderFrame:SetScript("OnDragStop", function(s) s:StopMovingOrSizing(); local p,_,rp,x,y=s:GetPoint(); PoisonCustomDB.position={p,"UIParent",rp,x,y} end)
holderFrame.label = holderFrame:CreateFontString(nil,"OVERLAY","GameFontNormalHuge"); holderFrame.label:SetPoint("CENTER"); holderFrame.label:SetText(L["DRAG HERE"]); holderFrame.label:Hide()

-- CONFIG MENÜ -------------------------------------------------------------
configFrame = CreateFrame("Frame", "PCR_Config", UIParent, "BackdropTemplate")
configFrame:SetSize(600, 450); configFrame:SetPoint("CENTER"); configFrame:SetFrameStrata("DIALOG")
configFrame:EnableMouse(true); configFrame:SetMovable(true); configFrame:SetClampedToScreen(true)
configFrame:SetBackdrop({bgFile="Interface/DialogFrame/UI-DialogBox-Background", edgeFile="Interface/DialogFrame/UI-DialogBox-Border", tile=true, tileSize=32, edgeSize=32, insets={left=8,right=8,top=8,bottom=8}})
local titleArea = CreateFrame("Frame", nil, configFrame, "BackdropTemplate"); titleArea:SetSize(300, 40); titleArea:SetPoint("TOP", 0, 12); titleArea:SetBackdrop({ bgFile = "Interface/DialogFrame/UI-DialogBox-Header" }); configFrame.title = titleArea:CreateFontString(nil, "OVERLAY", "GameFontNormal"); configFrame.title:SetPoint("CENTER", 0, 10); configFrame.title:SetText(L["Poison & Custom Config"])
configFrame:RegisterForDrag("LeftButton"); configFrame:SetScript("OnMouseDown", function(s, b) if b == "LeftButton" then s:StartMoving() end end); configFrame:SetScript("OnMouseUp", function(s) s:StopMovingOrSizing() end)
CreateFrame("Button", nil, configFrame, "UIPanelCloseButton"):SetPoint("TOPRIGHT", -5, -5); configFrame:Hide()

local tab1 = CreateFrame("Button", nil, configFrame, "PanelTabButtonTemplate"); tab1:SetPoint("TOPLEFT", configFrame, "BOTTOMLEFT", 10, 0); tab1:SetText(L["Poisons"]); tab1:SetID(1)
local tab2 = CreateFrame("Button", nil, configFrame, "PanelTabButtonTemplate"); tab2:SetPoint("LEFT", tab1, "RIGHT", 5, 0); tab2:SetText(L["Custom Items"]); tab2:SetID(2)
local panelPoisons = CreateFrame("Frame", nil, configFrame); panelPoisons:SetAllPoints()
local panelCustom = CreateFrame("Frame", nil, configFrame); panelCustom:SetAllPoints(); panelCustom:Hide()
local function SwitchTab(self) PanelTemplates_SetTab(configFrame, self:GetID()); if self:GetID()==1 then panelPoisons:Show(); panelCustom:Hide() else panelPoisons:Hide(); panelCustom:Show() end end
tab1:SetScript("OnClick", SwitchTab); tab2:SetScript("OnClick", SwitchTab); configFrame.numTabs = 2; configFrame.Tabs = {tab1, tab2}; PanelTemplates_SetTab(configFrame, 1)

-- TAB 1: GIFT MATRIX
if IS_ROGUE then
    local selectionFrame = CreateFrame("Frame", "PCR_Selector", UIParent, "BackdropTemplate"); selectionFrame:SetSize(220, 100); selectionFrame:SetFrameStrata("TOOLTIP"); selectionFrame:SetBackdrop({bgFile="Interface/Tooltips/UI-Tooltip-Background", edgeFile="Interface/Tooltips/UI-Tooltip-Border", tile=true, tileSize=16, edgeSize=16, insets={left=4,right=4,top=4,bottom=4}}); selectionFrame:SetBackdropColor(0,0,0,0.95); selectionFrame:Hide()
    local function OpenSelection(anchorFrame, zoneKey, slotIndex)
        selectionFrame:Hide(); selectionFrame:SetPoint("TOPLEFT", anchorFrame, "BOTTOMLEFT", 0, 2)
        if not selectionFrame.buttons then selectionFrame.buttons = {} end
        for _, btn in pairs(selectionFrame.buttons) do btn:Hide() end
        local cols = 4
        for i, poison in ipairs(ALL_POISONS) do
            local btn = selectionFrame.buttons[i]
            if not btn then
                btn = CreateFrame("Button", nil, selectionFrame); btn:SetSize(30, 30); btn:CreateTexture(nil, "BACKGROUND"):SetAllPoints()
                btn:SetScript("OnEnter", function(s) GameTooltip:SetOwner(s, "ANCHOR_RIGHT"); if s.sid > 0 then GameTooltip:SetSpellByID(s.sid) else GameTooltip:SetText(L["Clear Slot"]) end GameTooltip:Show() end); btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
                selectionFrame.buttons[i] = btn
            end
            local row = math.floor((i-1)/cols); local col = (i-1)%cols
            btn:ClearAllPoints(); btn:SetPoint("TOPLEFT", 10+(col*35), -10-(row*35))
            btn.sid = poison.id; btn:GetRegions():SetTexture(GetIconForType(poison.id, "buff_spell")) 
            btn:SetScript("OnClick", function() PoisonCustomDB[zoneKey][slotIndex]=poison.id; selectionFrame:Hide(); anchorFrame.icon:SetTexture(GetIconForType(poison.id, "buff_spell")); UpdateButtonsToZone() end)
            btn:Show()
        end
        local rows = math.ceil(#ALL_POISONS/cols); selectionFrame:SetWidth(10+(cols*35)); selectionFrame:SetHeight(10+(rows*35)+10); selectionFrame:Show()
    end
    local startX = 140; local colWidth = 90
    for i=1, MAX_POISON_SLOTS do local h = panelPoisons:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); h:SetPoint("TOPLEFT", startX+((i-1)*colWidth), -20); h:SetText(L["Poison"].." "..i) end
    local startY = -50
    for i, zoneData in ipairs(ZONES) do
        local y = startY - ((i-1) * 45); local lbl = panelPoisons:CreateFontString(nil, "OVERLAY", "GameFontNormal"); lbl:SetPoint("TOPLEFT", 20, y - 10); lbl:SetText(zoneData.label)
        for slot=1, MAX_POISON_SLOTS do
            local b = CreateFrame("Button", nil, panelPoisons); b:SetSize(36, 36); b:SetPoint("TOPLEFT", startX+((slot-1)*colWidth), y); b.icon = b:CreateTexture(nil, "BACKGROUND"); b.icon:SetAllPoints()
            b:SetScript("OnClick", function(s) OpenSelection(s, zoneData.key, slot) end)
            b:SetScript("OnShow", function(s) if PoisonCustomDB[zoneData.key] then s.icon:SetTexture(GetIconForType(PoisonCustomDB[zoneData.key][slot] or 0, "buff_spell")) end end)
        end
    end
else
    local warning = panelPoisons:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge"); warning:SetPoint("CENTER", 0, 20); warning:SetText("|cffff0000"..L["Class Warning"].."|r"); local subText = panelPoisons:CreateFontString(nil, "OVERLAY", "GameFontHighlightMedium"); subText:SetPoint("TOP", warning, "BOTTOM", 0, -10); subText:SetText(L["Rogues only. Use 'Custom Items'!"])
end

-- TAB 2: CUSTOM ITEMS UI
local customScroll = CreateFrame("ScrollFrame", nil, panelCustom, "UIPanelScrollFrameTemplate"); customScroll:SetPoint("TOPLEFT", 10, -100); customScroll:SetPoint("BOTTOMRIGHT", -30, 40)
local customContent = CreateFrame("Frame"); customContent:SetSize(500, 500); customScroll:SetScrollChild(customContent)
local inputID = CreateFrame("EditBox", nil, panelCustom, "InputBoxTemplate"); inputID:SetSize(80, 30); inputID:SetPoint("TOPLEFT", 20, -40); inputID:SetAutoFocus(false); inputID:SetNumeric(true); inputID:SetText("ID")

local dropdownType = CreateFrame("Frame", "PCR_TypeDrop", panelCustom, "UIDropDownMenuTemplate")
dropdownType:SetPoint("LEFT", inputID, "RIGHT", -10, -2); UIDropDownMenu_SetWidth(dropdownType, 130); UIDropDownMenu_SetText(dropdownType, L["Buff (Spell ID)"]); dropdownType.selectedValue = "buff_spell"

-- (REMOVED enableHeader HERE)

UIDropDownMenu_Initialize(dropdownType, function(self, level, menuList)
    local info = UIDropDownMenu_CreateInfo()
    info.text = L["Buff (Spell ID)"]; info.tooltipTitle = L["Buff (Spell ID)"]; info.tooltipText = L["Reminder for Buffs like Food, Raidbuffs etc."]; info.tooltipOnButton = 1; info.func = function() UIDropDownMenu_SetText(dropdownType, L["Buff (Spell ID)"]); dropdownType.selectedValue="buff_spell" end; UIDropDownMenu_AddButton(info)
    info.text = L["Buff (Item ID)"]; info.tooltipTitle = L["Buff (Item ID)"]; info.tooltipText = L["Reminder for Flask and Runes"]; info.tooltipOnButton = 1; info.func = function() UIDropDownMenu_SetText(dropdownType, L["Buff (Item ID)"]); dropdownType.selectedValue="buff_item" end; UIDropDownMenu_AddButton(info)
    info.text = L["Weapon (MH)"]; info.tooltipTitle = L["Weapon (MH)"]; info.tooltipText = L["Reminder for Mainhand Oil, Sharpening Stone"]; info.tooltipOnButton = 1; info.func = function() UIDropDownMenu_SetText(dropdownType, L["Weapon (MH)"]); dropdownType.selectedValue="weapon_mh" end; UIDropDownMenu_AddButton(info)
    info.text = L["Weapon (OH)"]; info.tooltipTitle = L["Weapon (OH)"]; info.tooltipText = L["Reminder for Offhand Oil, Sharpening Stone"]; info.tooltipOnButton = 1; info.func = function() UIDropDownMenu_SetText(dropdownType, L["Weapon (OH)"]); dropdownType.selectedValue="weapon_oh" end; UIDropDownMenu_AddButton(info)
end)
local addBtn = CreateFrame("Button", nil, panelCustom, "GameMenuButtonTemplate"); addBtn:SetSize(80, 25); addBtn:SetPoint("LEFT", dropdownType, "RIGHT", 10, 3); addBtn:SetText(L["Add"])

-- GROUPING LOGIC & LAYOUT
local function RefreshCustomList()
    if customContent.rows then for _, r in pairs(customContent.rows) do r:Hide() end end
    if customContent.headers then for _, h in pairs(customContent.headers) do h:Hide() end end
    customContent.rows = customContent.rows or {}
    customContent.headers = customContent.headers or {}
    
    local y = 0
    local groups = {
        { label = L["Buffs/Food"], types = { ["buff_spell"] = true } },
        { label = L["Flask/Runes"], types = { ["buff_item"] = true } },
        { label = L["Weapon Enchants"], types = { ["weapon_mh"] = true, ["weapon_oh"] = true } },
    }
    local headerCount = 0
    
    for _, group in ipairs(groups) do
        local hasItems = false
        for _, item in ipairs(PoisonCustomDB.customItems) do
            if group.types[item.trackType] then hasItems = true break end
        end
        
        if hasItems then
            headerCount = headerCount + 1
            local header = customContent.headers[headerCount]
            if not header then
                header = CreateFrame("Frame", nil, customContent)
                header:SetSize(520, 20)
                header.title = header:CreateFontString(nil, "OVERLAY", "GameFontHighlightMedium")
                header.title:SetPoint("LEFT", 10, 0)
                
                header.cols = {}
                for i, z in ipairs(ZONES) do
                    local colFrame = CreateFrame("Frame", nil, header)
                    colFrame:SetSize(24, 20)
                    colFrame:SetPoint("LEFT", COL_CHECK_START + ((i-1)*COL_CHECK_DIST) - 4, 0) 
                    
                    local txt = colFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                    txt:SetPoint("CENTER")
                    txt:SetText(string.sub(z.label, 1, 1))
                    
                    colFrame:SetScript("OnEnter", function(self) GameTooltip:SetOwner(self, "ANCHOR_TOP"); GameTooltip:SetText(z.label); GameTooltip:Show() end)
                    colFrame:SetScript("OnLeave", function() GameTooltip:Hide() end)
                    header.cols[i] = colFrame
                end
                
                customContent.headers[headerCount] = header
            end
            
            header:SetPoint("TOPLEFT", 0, y)
            header.title:SetText(group.label)
            header:Show()
            y = y - 25
            
            for idx, item in ipairs(PoisonCustomDB.customItems) do
                if group.types[item.trackType] then
                    local row = customContent.rows[idx]
                    if not row then
                        row = CreateFrame("Frame", nil, customContent); row:SetSize(520, 40)
                        row.icon = row:CreateTexture(nil, "ARTWORK"); row.icon:SetSize(32,32); row.icon:SetPoint("LEFT", 5, 0)
                        row.name = row:CreateFontString(nil, "OVERLAY", "GameFontNormal"); row.name:SetPoint("LEFT", 45, 0); row.name:SetWidth(COL_NAME_WIDTH); row.name:SetJustifyH("LEFT")
                        row.del = CreateFrame("Button", nil, row, "UIPanelCloseButton"); row.del:SetSize(25,25); row.del:SetPoint("RIGHT", -5, 0)
                        row.checks = {}
                        for i, z in ipairs(ZONES) do
                            local cb = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate"); cb:SetSize(24, 24); cb:SetPoint("LEFT", COL_CHECK_START + ((i-1)*COL_CHECK_DIST), 0)
                            cb.tooltipText = z.label; cb:SetScript("OnEnter", function(s) GameTooltip:SetOwner(s, "ANCHOR_RIGHT"); GameTooltip:SetText(z.label); GameTooltip:Show() end); cb:SetScript("OnLeave", function() GameTooltip:Hide() end)
                            row.checks[z.key] = cb
                        end
                        customContent.rows[idx] = row
                    end
                    
                    row:SetPoint("TOPLEFT", 0, y)
                    row.icon:SetTexture(GetIconForType(item.id, item.trackType))
                    
                    local display = "ID: "..item.id
                    if item.trackType == "buff_spell" then
                        local info = C_Spell.GetSpellInfo(item.id); if info then display = info.name end
                    else
                        local name = GetItemInfo(item.id); if name then display = name end
                    end
                    if item.trackType == "weapon_mh" then display = display .. " |cff00ccff" .. L["(Main Hand)"] .. "|r" end
                    if item.trackType == "weapon_oh" then display = display .. " |cff00ccff" .. L["(Off Hand)"] .. "|r" end

                    row.name:SetText(display)
                    row.del:SetScript("OnClick", function() table.remove(PoisonCustomDB.customItems, idx); RefreshCustomList(); UpdateButtonsToZone() end)
                    for key, cb in pairs(row.checks) do cb:SetChecked(item.zones[key]); cb:SetScript("OnClick", function() item.zones[key] = cb:GetChecked(); UpdateButtonsToZone() end) end
                    row:Show()
                    y = y - 45
                end
            end
            y = y - 10 
        end
    end
end
addBtn:SetScript("OnClick", function() local id = tonumber(inputID:GetText()); if id and id > 0 then table.insert(PoisonCustomDB.customItems, {id = id, trackType = dropdownType.selectedValue, zones = { raid=true, party=true, pvp=true, arena=true, none=true, scenario=true }}); inputID:SetText(""); RefreshCustomList(); UpdateButtonsToZone() else print(L["Invalid ID"]) end end)
panelCustom:SetScript("OnShow", RefreshCustomList)

-- COMMON UI
local unlockBtn = CreateFrame("Button", nil, configFrame, "GameMenuButtonTemplate"); unlockBtn:SetSize(200, 30); unlockBtn:SetPoint("BOTTOM", 0, 20); unlockBtn:SetText(L["Unlock Position"])
local isUnlocked = false
local function ToggleUnlock()
    if InCombatLockdown() then print("Kampf!") return end
    isUnlocked = not isUnlocked
    if isUnlocked then unlockBtn:SetText(L["Lock Position"]); holderFrame:SetBackdropColor(0, 1, 0, 0.5); holderFrame:SetBackdropBorderColor(0, 1, 0, 1); holderFrame:EnableMouse(true); holderFrame.label:Show(); for k, btn in pairs(gameplayButtons) do btn:Hide() end
    else unlockBtn:SetText(L["Unlock Position"]); holderFrame:SetBackdropColor(0, 0, 0, 0); holderFrame:SetBackdropBorderColor(0, 0, 0, 0); holderFrame:EnableMouse(false); holderFrame.label:Hide() end
end
unlockBtn:SetScript("OnClick", ToggleUnlock)

local blizzPanel = CreateFrame("Frame", "PCR_BlizzPanel")
local blizzTitle = blizzPanel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge"); blizzTitle:SetPoint("TOPLEFT", 16, -16); blizzTitle:SetText("Poison & Custom Reminder")
local openConfigBtn = CreateFrame("Button", nil, blizzPanel, "GameMenuButtonTemplate"); openConfigBtn:SetPoint("TOPLEFT", blizzTitle, "BOTTOMLEFT", 0, -30); openConfigBtn:SetSize(140, 30); openConfigBtn:SetText(L["Open Settings"])
openConfigBtn:SetScript("OnClick", function() if configFrame:IsShown() then configFrame:Hide() else configFrame:Show() end end)
if Settings and Settings.RegisterCanvasLayoutCategory then local category = Settings.RegisterCanvasLayoutCategory(blizzPanel, "Poison & Custom Reminder"); Settings.RegisterAddOnCategory(category) else blizzPanel.name = "Poison & Custom Reminder"; InterfaceOptions_AddCategory(blizzPanel) end

SLASH_POISONCUSTOM1 = "/pcr"
SlashCmdList["POISONCUSTOM"] = function() if configFrame:IsShown() then configFrame:Hide() else configFrame:Show() end end
print("|cff00ff00Poison & Custom Reminder v21.1 (Cleanup) geladen.|r /pcr")