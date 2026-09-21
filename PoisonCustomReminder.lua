-- INITIALISIERUNG DES NAMESPACES & LOCALES --------------------------------
local ADDON_NAME, ns = ...
local L = setmetatable(ns.L or {}, { __index = function(t, k) return k end })

-- KONFIGURATION & DATEN ---------------------------------------------------
local MAX_POISON_SLOTS = 4 

local DEFAULT_SETUP = {
    raid        = { 0, 0, 0, 0 },
    party       = { 0, 0, 0, 0 },
    pvp         = { 0, 0, 0, 0 },
    arena       = { 0, 0, 0, 0 },
    none        = { 0, 0, 0, 0 },
    scenario    = { 0, 0, 0, 0 },
    warnEnabled = true,
    warnRaid    = 15,   
    warnDungeon = 30,   
    glowEnabled = true,
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

-- HELPER: PROFIL MANAGEMENT -----------------------------------------------
local function GetCurrentProfile()
    local key = PoisonCustomDB.activeProfile or "Default"
    if not PoisonCustomDB.profiles[key] then 
        local newData = {}
        for k, v in pairs(DEFAULT_SETUP) do
            if type(v) == "table" then newData[k] = CopyTable(v) else newData[k] = v end
        end
        PoisonCustomDB.profiles[key] = newData
    end
    
    if PoisonCustomDB.profiles[key].glowEnabled == nil then
        PoisonCustomDB.profiles[key].glowEnabled = true
    end
    
    return PoisonCustomDB.profiles[key]
end

-- VORWÄRTSDEKLARATIONEN
local UpdateVisuals

local function SwitchProfile(profileName)
    if not PoisonCustomDB.profiles[profileName] then return end
    PoisonCustomDB.activeProfile = profileName
    if configFrame and configFrame:IsShown() then
        if configFrame.RefreshProfiles then configFrame.RefreshProfiles() end
        if configFrame.RefreshPoisons then configFrame.RefreshPoisons() end
    end
    UpdateButtonsToZone() 
    print("|cff00ff00[PCR]|r " .. L["Active Profile:"] .. " " .. profileName)
end

local function CheckSpecAutoSwitch()
    local specIndex = GetSpecialization()
    if not specIndex then return end
    local specID = GetSpecializationInfo(specIndex)
    
    if specID and PoisonCustomDB.specLinks and PoisonCustomDB.specLinks[specID] then
        local targetProfile = PoisonCustomDB.specLinks[specID]
        if PoisonCustomDB.activeProfile ~= targetProfile and PoisonCustomDB.profiles[targetProfile] then
            SwitchProfile(targetProfile)
        end
    end
end

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

local function FormatTime(seconds)
    if seconds < 60 then return math.floor(seconds) .. "s" end
    return math.floor(seconds / 60) .. "m"
end

-- BUTTON MANAGEMENT -------------------------------------------------------
function CreateGameplayButton(index) 
    local btn = CreateFrame("Button", "PCR_Btn"..index, holderFrame, "SecureActionButtonTemplate")
    btn:SetSize(45, 45)
    btn:EnableMouse(true)
    btn:RegisterForClicks("AnyUp", "AnyDown")
    
    btn.icon = btn:CreateTexture(nil, "BACKGROUND")
    btn.icon:SetAllPoints()
    
    -- NEU in v26.0: Auffälligerer Rahmen (Dicker & weiter außen)
    btn.border = CreateFrame("Frame", nil, btn, "BackdropTemplate")
    btn.border:SetPoint("TOPLEFT", btn, "TOPLEFT", -4, 4)
    btn.border:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 4, -4)
    btn.border:SetBackdrop({edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 18})
    btn.border:SetBackdropBorderColor(1, 0.85, 0, 1) -- Intensives Gelb-Gold
    btn.border:Hide()
    
    -- NEU in v26.0: Herzschlag-Pulsieren (Alpha + Skalierung)
    btn.glowAnim = btn.border:CreateAnimationGroup()
    btn.glowAnim:SetLooping("BOUNCE")
    
    local alpha = btn.glowAnim:CreateAnimation("Alpha")
    alpha:SetFromAlpha(0.2)
    alpha:SetToAlpha(1.0)
    alpha:SetDuration(0.35) -- Deutlich schneller
    
    -- Die Scale-Animation lässt den Rahmen "pumpen" (wird 15% größer)
    local scale = btn.glowAnim:CreateAnimation("Scale")
    scale:SetScale(1.15, 1.15) 
    scale:SetDuration(0.35)
    scale:SetOrigin("CENTER", 0, 0)
    
    btn.text = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    btn.text:SetPoint("TOP", btn, "BOTTOM", 0, -5)
    btn.text:SetText(L["MISSING"])
    
    btn:Hide()
    return btn
end

function UpdateButtonsToZone() 
    if InCombatLockdown() then return end 
    local zone = GetCurrentZoneType()
    local profile = GetCurrentProfile()
    
    local settings = EMPTY_FALLBACK
    if IS_ROGUE then settings = profile[zone] or EMPTY_FALLBACK end
    
    activeCustomItems = {}
    if profile.customItems then
        for _, item in ipairs(profile.customItems) do
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
                btn.isClassPoison = true
                
                local xOffset = -((visibleCount-1)*50)/2 + ((currentVisibleIndex-1)*50)
                btn:SetPoint("CENTER", holderFrame, "CENTER", xOffset, 0)

                if spellID > 0 then
                    btn:SetAttribute("type", "spell"); btn:SetAttribute("spell", spellID)
                    btn.icon:SetTexture(C_Spell.GetSpellInfo(spellID).iconID)
                else
                    btn:SetAttribute("type", nil); btn:Hide(); btn.checkID = 0
                end
            else
                btn.isClassPoison = false
                btn:SetAttribute("type", nil); btn:Hide(); btn.checkID = 0
            end
        else
            currentVisibleIndex = currentVisibleIndex + 1
            local itemData = activeCustomItems[i - MAX_POISON_SLOTS]
            btn.checkType = itemData.trackType; btn.checkID = itemData.id
            btn.isClassPoison = false
            
            local xOffset = -((visibleCount-1)*50)/2 + ((currentVisibleIndex-1)*50)
            btn:SetPoint("CENTER", holderFrame, "CENTER", xOffset, 0)
            
            if itemData.trackType == "buff_spell" then
                btn:SetAttribute("type", "spell"); btn:SetAttribute("spell", itemData.id)
            else
                btn:SetAttribute("type", "item"); btn:SetAttribute("item", "item:"..itemData.id)
            end
            btn.icon:SetTexture(GetIconForType(itemData.id, itemData.trackType))
        end
    end
    for i = totalSlots + 1, #gameplayButtons do gameplayButtons[i]:Hide(); gameplayButtons[i].checkID = 0 end
    
    UpdateVisuals()
end

-- LOGIK UPDATE (Mit kreisendem Glow)
UpdateVisuals = function()
    if InCombatLockdown() or UnitIsDeadOrGhost("player") then return end
    if EditModeManagerFrame and EditModeManagerFrame:IsShown() then return end
    if holderFrame:IsMouseEnabled() then return end 

    local profile = GetCurrentProfile()
    local zone = GetCurrentZoneType()

    for i, btn in ipairs(gameplayButtons) do
        if btn.checkID and btn.checkID > 0 then
            local isMissing = true
            local isExpiring = false
            local timeLeft = 0
            
            if btn.checkType == "spell" or btn.checkType == "buff_spell" then
                local aura = C_UnitAuras.GetPlayerAuraBySpellID(btn.checkID)
                if aura then
                    isMissing = false
                    if btn.isClassPoison and profile.warnEnabled then
                        local thresholdMin = 15
                        if zone == "raid" then thresholdMin = profile.warnRaid or 15
                        elseif zone == "party" then thresholdMin = profile.warnDungeon or 30 end
                        
                        local thresholdSec = thresholdMin * 60
                        if aura.expirationTime and aura.expirationTime > 0 then
                            timeLeft = aura.expirationTime - GetTime()
                            if timeLeft > 0 and timeLeft <= thresholdSec then
                                isExpiring = true
                            end
                        end
                    end
                end
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
            
            -- UI & GLOW UPDATE
            if isMissing then
                btn:Show()
                btn:SetAlpha(1)
                btn.text:SetText(L["MISSING"])
                btn.text:SetTextColor(1, 0, 0)
                
                if profile.glowEnabled then
                    btn.border:Show()
                    btn.glowAnim:Play()
                else
                    btn.border:Hide()
                    btn.glowAnim:Stop()
                end
                
            elseif isExpiring then
                btn:Show()
                btn:SetAlpha(1)
                btn.text:SetText(L["Expires: "] .. FormatTime(timeLeft))
                btn.text:SetTextColor(1, 1, 0)
                
                btn.border:Show()
                
                if profile.glowEnabled then 
                    btn.glowAnim:Play() 
                else 
                    btn.glowAnim:Stop() 
                end
            else
                btn:Hide()
                btn.border:Hide()
                btn.glowAnim:Stop()
            end
        else
            btn:Hide()
            if btn.glowAnim then btn.glowAnim:Stop() end
        end
    end
end

-- INITIALISIERUNG & MIGRATION ---------------------------------------------
local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("ADDON_LOADED")
initFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
initFrame:RegisterEvent("GET_ITEM_INFO_RECEIVED") 
initFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED") 

initFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        local addonName = ...
        if addonName == ADDON_NAME then
            if not PoisonCustomDB then PoisonCustomDB = {} end
            
            if not PoisonCustomDB.profiles then
                local oldData = {}
                for k, v in pairs(DEFAULT_SETUP) do
                    if PoisonCustomDB[k] ~= nil then 
                        if type(PoisonCustomDB[k]) == "table" then
                            oldData[k] = CopyTable(PoisonCustomDB[k]) 
                        else
                            oldData[k] = PoisonCustomDB[k]
                        end
                    end
                end
                if PoisonCustomDB.customItems then oldData.customItems = CopyTable(PoisonCustomDB.customItems) end
                
                PoisonCustomDB = {
                    profiles = { ["Default"] = oldData },
                    activeProfile = "Default",
                    specLinks = {}, 
                    position = PoisonCustomDB.position 
                }
                
                for k, v in pairs(DEFAULT_SETUP) do
                    if PoisonCustomDB.profiles["Default"][k] == nil then
                        if type(v) == "table" then
                            PoisonCustomDB.profiles["Default"][k] = CopyTable(v)
                        else
                            PoisonCustomDB.profiles["Default"][k] = v
                        end
                    end
                end
            end
            
            if not PoisonCustomDB.specLinks then PoisonCustomDB.specLinks = {} end
            
            if PoisonCustomDB.position and holderFrame then
                holderFrame:ClearAllPoints()
                local point, relTo, relPoint, x, y = unpack(PoisonCustomDB.position)
                holderFrame:SetPoint(point, UIParent, relPoint, x, y)
            end
        end
        
    elseif event == "PLAYER_ENTERING_WORLD" then
        CheckSpecAutoSwitch()
        if not InCombatLockdown() then UpdateButtonsToZone() end
        
    elseif event == "PLAYER_SPECIALIZATION_CHANGED" then
        local unit = ...
        if unit == "player" then CheckSpecAutoSwitch() end
        
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
local watcher = CreateFrame("Frame")
local timer = 0
watcher:SetScript("OnUpdate", function(self, elapsed)
    timer = timer + elapsed
    if timer < 0.5 then return end
    timer = 0
    UpdateVisuals() 
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
configFrame:SetSize(600, 480); configFrame:SetPoint("CENTER"); configFrame:SetFrameStrata("DIALOG")
configFrame:EnableMouse(true); configFrame:SetMovable(true); configFrame:SetClampedToScreen(true)
configFrame:SetBackdrop({bgFile="Interface/DialogFrame/UI-DialogBox-Background", edgeFile="Interface/DialogFrame/UI-DialogBox-Border", tile=true, tileSize=32, edgeSize=32, insets={left=8,right=8,top=8,bottom=8}})
local titleArea = CreateFrame("Frame", nil, configFrame, "BackdropTemplate"); titleArea:SetSize(300, 40); titleArea:SetPoint("TOP", 0, 12); titleArea:SetBackdrop({ bgFile = "Interface/DialogFrame/UI-DialogBox-Header" }); configFrame.title = titleArea:CreateFontString(nil, "OVERLAY", "GameFontNormal"); configFrame.title:SetPoint("CENTER", 0, 10); configFrame.title:SetText(L["Poison & Custom Config"])
configFrame:RegisterForDrag("LeftButton"); configFrame:SetScript("OnMouseDown", function(s, b) if b == "LeftButton" then s:StartMoving() end end); configFrame:SetScript("OnMouseUp", function(s) s:StopMovingOrSizing() end)
CreateFrame("Button", nil, configFrame, "UIPanelCloseButton"):SetPoint("TOPRIGHT", -5, -5); configFrame:Hide()

local tab1 = CreateFrame("Button", nil, configFrame, "PanelTabButtonTemplate"); tab1:SetPoint("TOPLEFT", configFrame, "BOTTOMLEFT", 10, 0); tab1:SetText(L["Poisons"]); tab1:SetID(1)
local tab2 = CreateFrame("Button", nil, configFrame, "PanelTabButtonTemplate"); tab2:SetPoint("LEFT", tab1, "RIGHT", 5, 0); tab2:SetText(L["Custom Items"]); tab2:SetID(2)
local tab3 = CreateFrame("Button", nil, configFrame, "PanelTabButtonTemplate"); tab3:SetPoint("LEFT", tab2, "RIGHT", 5, 0); tab3:SetText(L["Profiles"]); tab3:SetID(3)

local panelPoisons = CreateFrame("Frame", nil, configFrame); panelPoisons:SetAllPoints()
local panelCustom = CreateFrame("Frame", nil, configFrame); panelCustom:SetAllPoints(); panelCustom:Hide()
local panelProfiles = CreateFrame("Frame", nil, configFrame); panelProfiles:SetAllPoints(); panelProfiles:Hide()

local function SwitchTab(self) 
    PanelTemplates_SetTab(configFrame, self:GetID())
    panelPoisons:Hide(); panelCustom:Hide(); panelProfiles:Hide()
    if self:GetID() == 1 then 
        panelPoisons:Show()
        if configFrame.RefreshPoisons then configFrame.RefreshPoisons() end
    elseif self:GetID() == 2 then 
        panelCustom:Show()
    elseif self:GetID() == 3 then 
        panelProfiles:Show()
        if configFrame.RefreshProfiles then configFrame.RefreshProfiles() end
    end
end
tab1:SetScript("OnClick", SwitchTab); tab2:SetScript("OnClick", SwitchTab); tab3:SetScript("OnClick", SwitchTab)
configFrame.numTabs = 3; configFrame.Tabs = {tab1, tab2, tab3}; PanelTemplates_SetTab(configFrame, 1)

-- *** TAB 1: GIFT MATRIX & SETTINGS ***
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
            btn:SetScript("OnClick", function() 
                local p = GetCurrentProfile(); p[zoneKey][slotIndex]=poison.id
                selectionFrame:Hide(); anchorFrame.icon:SetTexture(GetIconForType(poison.id, "buff_spell")); UpdateButtonsToZone() 
            end)
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
            b:SetScript("OnShow", function(s) 
                local p = GetCurrentProfile()
                if p[zoneData.key] then s.icon:SetTexture(GetIconForType(p[zoneData.key][slot] or 0, "buff_spell")) end 
            end)
        end
    end
    
    local warnLabel = panelPoisons:CreateFontString(nil, "OVERLAY", "GameFontHighlightMedium")
    warnLabel:SetPoint("TOPLEFT", 20, -325)
    warnLabel:SetText(L["Poison Expiry Warning"])

    local cbWarn = CreateFrame("CheckButton", nil, panelPoisons, "UICheckButtonTemplate")
    cbWarn:SetPoint("TOPLEFT", 20, -345)
    cbWarn.text = cbWarn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    cbWarn.text:SetPoint("LEFT", cbWarn, "RIGHT", 5, 0)
    cbWarn.text:SetText(L["Enable Warning"])

    local cbGlow = CreateFrame("CheckButton", nil, panelPoisons, "UICheckButtonTemplate")
    cbGlow:SetPoint("LEFT", cbWarn.text, "RIGHT", 100, 0)
    cbGlow.text = cbGlow:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    cbGlow.text:SetPoint("LEFT", cbGlow, "RIGHT", 5, 0)
    cbGlow.text:SetText(L["Enable Glow"])

    local editRaid = CreateFrame("EditBox", nil, panelPoisons, "InputBoxTemplate")
    editRaid:SetSize(40, 20); editRaid:SetPoint("TOPLEFT", 40, -375); editRaid:SetNumeric(true); editRaid:SetAutoFocus(false)
    local lblRaid = editRaid:CreateFontString(nil, "OVERLAY", "GameFontNormal"); lblRaid:SetPoint("LEFT", editRaid, "RIGHT", 5, 0); lblRaid:SetText(L["Raid (Min)"])

    local editDungeon = CreateFrame("EditBox", nil, panelPoisons, "InputBoxTemplate")
    editDungeon:SetSize(40, 20); editDungeon:SetPoint("LEFT", lblRaid, "RIGHT", 30, 0); editDungeon:SetNumeric(true); editDungeon:SetAutoFocus(false)
    local lblDungeon = editDungeon:CreateFontString(nil, "OVERLAY", "GameFontNormal"); lblDungeon:SetPoint("LEFT", editDungeon, "RIGHT", 5, 0); lblDungeon:SetText(L["Dungeon (Min)"])

    cbWarn:SetScript("OnClick", function(self)
        GetCurrentProfile().warnEnabled = self:GetChecked()
        UpdateVisuals()
    end)
    cbGlow:SetScript("OnClick", function(self)
        GetCurrentProfile().glowEnabled = self:GetChecked()
        UpdateVisuals()
    end)
    editRaid:SetScript("OnTextChanged", function(self)
        local val = tonumber(self:GetText())
        if val then GetCurrentProfile().warnRaid = val end
    end)
    editDungeon:SetScript("OnTextChanged", function(self)
        local val = tonumber(self:GetText())
        if val then GetCurrentProfile().warnDungeon = val end
    end)

    configFrame.RefreshPoisons = function()
        local p = GetCurrentProfile()
        cbWarn:SetChecked(p.warnEnabled)
        cbGlow:SetChecked(p.glowEnabled ~= false) 
        editRaid:SetText(tostring(p.warnRaid or 15))
        editDungeon:SetText(tostring(p.warnDungeon or 30))
    end
    panelPoisons:SetScript("OnShow", configFrame.RefreshPoisons)

else
    local warning = panelPoisons:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge"); warning:SetPoint("CENTER", 0, 20); warning:SetText("|cffff0000"..L["Class Warning"].."|r"); local subText = panelPoisons:CreateFontString(nil, "OVERLAY", "GameFontHighlightMedium"); subText:SetPoint("TOP", warning, "BOTTOM", 0, -10); subText:SetText(L["Rogues only. Use 'Custom Items'!"])
end

-- TAB 2: CUSTOM ITEMS UI
local customScroll = CreateFrame("ScrollFrame", nil, panelCustom, "UIPanelScrollFrameTemplate"); customScroll:SetPoint("TOPLEFT", 10, -100); customScroll:SetPoint("BOTTOMRIGHT", -30, 40)
local customContent = CreateFrame("Frame"); customContent:SetSize(500, 500); customScroll:SetScrollChild(customContent)
local inputID = CreateFrame("EditBox", nil, panelCustom, "InputBoxTemplate"); inputID:SetSize(80, 30); inputID:SetPoint("TOPLEFT", 20, -40); inputID:SetAutoFocus(false); inputID:SetNumeric(true); inputID:SetText("ID")

local dropdownType = CreateFrame("Frame", "PCR_TypeDrop", panelCustom, "UIDropDownMenuTemplate")
dropdownType:SetPoint("LEFT", inputID, "RIGHT", -10, -2); UIDropDownMenu_SetWidth(dropdownType, 130); UIDropDownMenu_SetText(dropdownType, L["Buff (Spell ID)"]); dropdownType.selectedValue = "buff_spell"

UIDropDownMenu_Initialize(dropdownType, function(self, level, menuList)
    local info = UIDropDownMenu_CreateInfo()
    info.text = L["Buff (Spell ID)"]; info.tooltipTitle = L["Buff (Spell ID)"]; info.tooltipText = L["Reminder for Buffs like Food, Raidbuffs etc."]; info.tooltipOnButton = 1; info.func = function() UIDropDownMenu_SetText(dropdownType, L["Buff (Spell ID)"]); dropdownType.selectedValue="buff_spell" end; UIDropDownMenu_AddButton(info)
    info.text = L["Buff (Item ID)"]; info.tooltipTitle = L["Buff (Item ID)"]; info.tooltipText = L["Reminder for Flask and Runes"]; info.tooltipOnButton = 1; info.func = function() UIDropDownMenu_SetText(dropdownType, L["Buff (Item ID)"]); dropdownType.selectedValue="buff_item" end; UIDropDownMenu_AddButton(info)
    info.text = L["Weapon (MH)"]; info.tooltipTitle = L["Weapon (MH)"]; info.tooltipText = L["Reminder for Mainhand Oil, Sharpening Stone"]; info.tooltipOnButton = 1; info.func = function() UIDropDownMenu_SetText(dropdownType, L["Weapon (MH)"]); dropdownType.selectedValue="weapon_mh" end; UIDropDownMenu_AddButton(info)
    info.text = L["Weapon (OH)"]; info.tooltipTitle = L["Weapon (OH)"]; info.tooltipText = L["Reminder for Offhand Oil, Sharpening Stone"]; info.tooltipOnButton = 1; info.func = function() UIDropDownMenu_SetText(dropdownType, L["Weapon (OH)"]); dropdownType.selectedValue="weapon_oh" end; UIDropDownMenu_AddButton(info)
end)
local addBtn = CreateFrame("Button", nil, panelCustom, "GameMenuButtonTemplate"); addBtn:SetSize(80, 25); addBtn:SetPoint("LEFT", dropdownType, "RIGHT", 10, 3); addBtn:SetText(L["Add"])

local function RefreshCustomList()
    if customContent.rows then for _, r in pairs(customContent.rows) do r:Hide() end end
    if customContent.headers then for _, h in pairs(customContent.headers) do h:Hide() end end
    customContent.rows = customContent.rows or {}
    customContent.headers = customContent.headers or {}
    
    local profile = GetCurrentProfile() 
    local y = 0
    local groups = {
        { label = L["Buffs/Food"], types = { ["buff_spell"] = true } },
        { label = L["Flask/Runes"], types = { ["buff_item"] = true } },
        { label = L["Weapon Enchants"], types = { ["weapon_mh"] = true, ["weapon_oh"] = true } },
    }
    local headerCount = 0
    
    for _, group in ipairs(groups) do
        local hasItems = false
        if profile.customItems then
            for _, item in ipairs(profile.customItems) do
                if group.types[item.trackType] then hasItems = true break end
            end
        end
        
        if hasItems then
            headerCount = headerCount + 1
            local header = customContent.headers[headerCount]
            if not header then
                header = CreateFrame("Frame", nil, customContent); header:SetSize(520, 20)
                header.title = header:CreateFontString(nil, "OVERLAY", "GameFontHighlightMedium"); header.title:SetPoint("LEFT", 10, 0)
                header.cols = {}
                for i, z in ipairs(ZONES) do
                    local colFrame = CreateFrame("Frame", nil, header); colFrame:SetSize(24, 20)
                    colFrame:SetPoint("LEFT", COL_CHECK_START + ((i-1)*COL_CHECK_DIST) - 4, 0) 
                    local txt = colFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"); txt:SetPoint("CENTER"); txt:SetText(string.sub(z.label, 1, 1))
                    colFrame:SetScript("OnEnter", function(self) GameTooltip:SetOwner(self, "ANCHOR_TOP"); GameTooltip:SetText(z.label); GameTooltip:Show() end); colFrame:SetScript("OnLeave", function() GameTooltip:Hide() end)
                    header.cols[i] = colFrame
                end
                customContent.headers[headerCount] = header
            end
            header:SetPoint("TOPLEFT", 0, y); header.title:SetText(group.label); header:Show(); y = y - 25
            
            for idx, item in ipairs(profile.customItems) do
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
                    if item.trackType == "buff_spell" then local info = C_Spell.GetSpellInfo(item.id); if info then display = info.name end
                    else local name = GetItemInfo(item.id); if name then display = name end end
                    if item.trackType == "weapon_mh" then display = display .. " |cff00ccff" .. L["(Main Hand)"] .. "|r" end
                    if item.trackType == "weapon_oh" then display = display .. " |cff00ccff" .. L["(Off Hand)"] .. "|r" end
                    row.name:SetText(display)
                    
                    row.del:SetScript("OnClick", function() table.remove(profile.customItems, idx); RefreshCustomList(); UpdateButtonsToZone() end)
                    for key, cb in pairs(row.checks) do 
                        cb:SetChecked(item.zones[key])
                        cb:SetScript("OnClick", function() item.zones[key] = cb:GetChecked(); UpdateButtonsToZone() end) 
                    end
                    row:Show(); y = y - 45
                end
            end
            y = y - 10 
        end
    end
end
addBtn:SetScript("OnClick", function() 
    local id = tonumber(inputID:GetText())
    if id and id > 0 then 
        local p = GetCurrentProfile()
        if not p.customItems then p.customItems = {} end
        table.insert(p.customItems, {id = id, trackType = dropdownType.selectedValue, zones = { raid=true, party=true, pvp=true, arena=true, none=true, scenario=true }})
        inputID:SetText(""); RefreshCustomList(); UpdateButtonsToZone() 
    else print(L["Invalid ID"]) end 
end)
panelCustom:SetScript("OnShow", RefreshCustomList)

-- *** TAB 3: PROFILES UI ***
do
    local p = panelProfiles
    
    local lblActive = p:CreateFontString(nil, "OVERLAY", "GameFontNormal"); lblActive:SetPoint("TOPLEFT", 20, -50); lblActive:SetText(L["Active Profile:"])
    local dropActive = CreateFrame("Frame", "PCR_ProfileActiveDrop", p, "UIDropDownMenuTemplate"); dropActive:SetPoint("LEFT", lblActive, "RIGHT", 0, -2); UIDropDownMenu_SetWidth(dropActive, 180)
    
    local lblNew = p:CreateFontString(nil, "OVERLAY", "GameFontNormal"); lblNew:SetPoint("TOPLEFT", 20, -100); lblNew:SetText(L["Create New Profile"])
    local inputNew = CreateFrame("EditBox", nil, p, "InputBoxTemplate"); inputNew:SetSize(150, 30); inputNew:SetPoint("TOPLEFT", 20, -120); inputNew:SetAutoFocus(false); inputNew:SetText(L["Enter profile name"])
    local btnCreate = CreateFrame("Button", nil, p, "GameMenuButtonTemplate"); btnCreate:SetSize(100, 25); btnCreate:SetPoint("LEFT", inputNew, "RIGHT", 10, 0); btnCreate:SetText(L["Create"])
    
    local lblCopy = p:CreateFontString(nil, "OVERLAY", "GameFontNormal"); lblCopy:SetPoint("TOPLEFT", 20, -170); lblCopy:SetText(L["Copy from:"])
    local dropCopy = CreateFrame("Frame", "PCR_ProfileCopyDrop", p, "UIDropDownMenuTemplate"); dropCopy:SetPoint("TOPLEFT", 20, -190); UIDropDownMenu_SetWidth(dropCopy, 180)
    local btnCopy = CreateFrame("Button", nil, p, "GameMenuButtonTemplate"); btnCopy:SetSize(100, 25); btnCopy:SetPoint("LEFT", dropCopy, "RIGHT", 130, 2); btnCopy:SetText(L["Copy"])
    
    local btnDelete = CreateFrame("Button", nil, p, "GameMenuButtonTemplate"); btnDelete:SetSize(120, 25); btnDelete:SetPoint("TOPRIGHT", -30, -50); btnDelete:SetText(L["Delete Profile"])
    
    local lblSpecs = p:CreateFontString(nil, "OVERLAY", "GameFontHighlightMedium"); lblSpecs:SetPoint("TOPLEFT", 20, -260); lblSpecs:SetText(L["Auto-Switch for Specs:"])
    
    local checkboxes = {}
    
    local function RefreshProfileUI()
        UIDropDownMenu_SetText(dropActive, PoisonCustomDB.activeProfile)
        UIDropDownMenu_Initialize(dropActive, function(self, level)
            for k, v in pairs(PoisonCustomDB.profiles) do
                local info = UIDropDownMenu_CreateInfo(); info.text = k; info.func = function() SwitchProfile(k) end; UIDropDownMenu_AddButton(info)
            end
        end)
        
        UIDropDownMenu_SetText(dropCopy, "")
        UIDropDownMenu_Initialize(dropCopy, function(self, level)
            for k, v in pairs(PoisonCustomDB.profiles) do
                local info = UIDropDownMenu_CreateInfo(); info.text = k; info.func = function() UIDropDownMenu_SetText(dropCopy, k); dropCopy.selected = k end; UIDropDownMenu_AddButton(info)
            end
        end)
        
        local numSpecs = GetNumSpecializations()
        for i=1, numSpecs do
            if not checkboxes[i] then
                local cb = CreateFrame("CheckButton", nil, p, "UICheckButtonTemplate")
                cb:SetPoint("TOPLEFT", 30, -290 - ((i-1)*30))
                cb.text = cb:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                cb.text:SetPoint("LEFT", cb, "RIGHT", 5, 0)
                cb:SetScript("OnClick", function(self)
                    local specID = self.specID
                    if self:GetChecked() then
                        PoisonCustomDB.specLinks[specID] = PoisonCustomDB.activeProfile
                    else
                        PoisonCustomDB.specLinks[specID] = nil
                    end
                    RefreshProfileUI()
                end)
                checkboxes[i] = cb
            end
            
            local id, name = GetSpecializationInfo(i)
            checkboxes[i].specID = id
            local linkedProfile = PoisonCustomDB.specLinks[id]
            checkboxes[i]:SetChecked(linkedProfile == PoisonCustomDB.activeProfile)
            
            if linkedProfile and linkedProfile ~= PoisonCustomDB.activeProfile then
                checkboxes[i].text:SetText(name .. " (|cff888888" .. linkedProfile .. "|r)")
            else
                checkboxes[i].text:SetText(name)
            end
            checkboxes[i]:Show()
        end
    end
    configFrame.RefreshProfiles = RefreshProfileUI
    p:SetScript("OnShow", RefreshProfileUI)
    
    btnCreate:SetScript("OnClick", function()
        local name = inputNew:GetText()
        if name and name ~= "" and not PoisonCustomDB.profiles[name] then
            local newData = {}
            for k, v in pairs(DEFAULT_SETUP) do
                if type(v) == "table" then newData[k] = CopyTable(v) else newData[k] = v end
            end
            PoisonCustomDB.profiles[name] = newData
            SwitchProfile(name)
            inputNew:SetText("")
            print(L["Profile created."])
        end
    end)
    
    btnCopy:SetScript("OnClick", function()
        local source = dropCopy.selected
        if source and PoisonCustomDB.profiles[source] then
            PoisonCustomDB.profiles[PoisonCustomDB.activeProfile] = CopyTable(PoisonCustomDB.profiles[source])
            UpdateButtonsToZone()
            print(L["Profile copied."])
        end
    end)
    
    btnDelete:SetScript("OnClick", function()
        if PoisonCustomDB.activeProfile == "Default" then print(L["Cannot delete default profile."]); return end
        PoisonCustomDB.profiles[PoisonCustomDB.activeProfile] = nil
        SwitchProfile("Default")
        print(L["Profile deleted."])
    end)
end

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
print("|cff00ff00Poison & Custom Reminder v26.0 (Stronger Glow) geladen.|r /pcr")