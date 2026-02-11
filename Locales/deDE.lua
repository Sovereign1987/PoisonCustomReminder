local ADDON_NAME, ns = ...

-- Wir holen uns die Tabelle L aus dem Namespace oder erstellen sie
if not ns.L then ns.L = {} end
local L = ns.L

if GetLocale() == "deDE" then
    -- UI & System
    L["MISSING"] = "FEHLT"
    L["EMPTY / REMOVE"] = "LEER / ENTFERNEN"
    L["Clear Slot"] = "Slot leeren"
    L["DRAG HERE"] = "HIER ZIEHEN"
    L["Add"] = "Hinzufügen"
    L["Unlock Position"] = "Position entsperren"
    L["Lock Position"] = "Position sperren"
    L["Open Settings"] = "Einstellungen öffnen"
    L["Poison & Custom Config"] = "Gift & Custom Konfiguration"
    L["Poisons"] = "Gifte"
    L["Custom Items"] = "Custom Items"
    L["Poison"] = "Gift" 
    
    -- Zonen
    L["Raid"] = "Schlachtzug"
    L["Dungeon"] = "Dungeon"
    L["BG"] = "Schlachtfeld"
    L["Arena"] = "Arena"
    L["Open World"] = "Open World"
    L["Delves"] = "Tiefen"
    
    -- Gifte
    L["Deadly"] = "Tödlich"
    L["Instant"] = "Sofort"
    L["Wound"] = "Wund"
    L["Amplifying"] = "Verstärkend"
    L["Crippling"] = "Verkrüppelnd"
    L["Numbing"] = "Narkotisch"
    L["Atrophic"] = "Atrophisch"
    
    -- Warnungen & Infos
    L["Class Warning"] = "Klassen-Warnung"
    L["Rogues only. Use 'Custom Items'!"] = "Nur für Schurken.\nNutze den 'Custom Items' Reiter!"
    L["Invalid ID"] = "Ungültige ID"
    L["Enable in:"] = "Aktivieren in:"
    
    -- Kategorien (NEU UMBENANNT)
    L["Buffs/Food"] = "Buffs/Essen"
    L["Flask/Runes"] = "Phiolen/Runen"
    L["Weapon Enchants"] = "Waffenverzauberungen"

    -- Dropdown Menü (NEU UMBENANNT)
    L["Buff (Spell ID)"] = "Buff (Zauber ID)"
    L["Buff (Item ID)"] = "Buff (Item ID)" -- War vorher Item (ItemID)
    L["Weapon (MH)"] = "Waffe (MH)"
    L["Weapon (OH)"] = "Waffe (OH)"
    L["(Main Hand)"] = "(Waffenhand)"
    L["(Off Hand)"] = "(Schildhand)"

    -- Tooltips
    L["Reminder for Buffs like Food, Raidbuffs etc."] = "Erinnerung für Buffs wie Essen, Schlachtzugsbuffs usw."
    L["Reminder for Flask and Runes"] = "Erinnerung für Items wie Phiolen und Runen"
    L["Reminder for Mainhand Oil, Sharpening Stone"] = "Erinnerung für Waffenöl oder Wetzstein auf der Haupthand"
    L["Reminder for Offhand Oil, Sharpening Stone"] = "Erinnerung für Waffenöl oder Wetzstein auf der Schildhand"

	-- PROFIL SYSTEM
    L["Profiles"] = "Profile"
    L["Active Profile:"] = "Aktives Profil:"
    L["Create New Profile"] = "Neues Profil erstellen"
    L["Create"] = "Erstellen"
    L["Copy from:"] = "Kopieren von:"
    L["Copy"] = "Kopieren"
    L["Delete Profile"] = "Profil löschen"
    L["Auto-Switch for Specs:"] = "Automatisch laden bei Spezialisierung:"
    L["Current Spec:"] = "Aktueller Spec:"
    L["(Active)"] = "(Aktiv)"
    L["Profile created."] = "Profil erstellt."
    L["Profile deleted."] = "Profil gelöscht."
    L["Profile copied."] = "Profil kopiert."
    L["Cannot delete default profile."] = "Standard-Profil kann nicht gelöscht werden."
    L["Enter profile name"] = "Profilname eingeben"
end