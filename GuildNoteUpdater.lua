-- Create the addon table
local GuildNoteUpdater = CreateFrame("Frame")
GuildNoteUpdater.hasUpdated = false  -- Flag to prevent double updates
GuildNoteUpdater.previousItemLevel = nil  -- Store the previous item level
GuildNoteUpdater.previousNote = ""  -- Store the previous note to avoid redundant updates

-- Initialize the addon
function GuildNoteUpdater:OnEvent(event, arg1)
    if event == "ADDON_LOADED" and arg1 == "GuildNoteUpdater" then
        self:InitializeSettings()
        -- Register only the PLAYER_EQUIPMENT_CHANGED event for handling gear changes
        self:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
        self:RegisterEvent("ACTIVE_TALENT_GROUP_CHANGED")  -- Event for spec change
    elseif event == "PLAYER_ENTERING_WORLD" then
        if IsInGuild() and not self.hasUpdated then
            self:RegisterEvent("GUILD_ROSTER_UPDATE")
            C_GuildInfo.GuildRoster()  -- Request a guild roster update
        end
    elseif event == "GUILD_ROSTER_UPDATE" then
        if not self.hasUpdated then
            -- Set the flag to prevent further updates and introduce a brief delay
            self.hasUpdated = true
            self:UnregisterEvent("GUILD_ROSTER_UPDATE")  -- Unregister the event to prevent further triggering
            C_Timer.After(1, function()
                if IsInGuild() and GetNumGuildMembers() > 0 then
                    self:UpdateGuildNote()
                end
            end)
        end
    elseif event == "PLAYER_EQUIPMENT_CHANGED" or event == "ACTIVE_TALENT_GROUP_CHANGED" then
        -- Delay the guild note update by 1 second to ensure the item level is refreshed
        C_Timer.After(1, function()
            if IsInGuild() then
                self:UpdateGuildNote(true)  -- true indicates that we want to check for item level or spec changes
            end
        end)
    end
end

-- Initialize settings and create the UI
function GuildNoteUpdater:InitializeSettings()
    if not GuildNoteUpdaterSettings then
        -- Set default settings for first-time use
        GuildNoteUpdaterSettings = {
            enabledCharacters = {},
            specUpdateMode = {},  -- Store whether to update automatically or manually
            selectedSpec = {},
            itemLevelType = {}  -- Store the item level type selection (Overall/Equipped)
        }

        -- Default settings for the first-time use
        GuildNoteUpdaterSettings.enabledCharacters[UnitName("player")] = true
        GuildNoteUpdaterSettings.specUpdateMode[UnitName("player")] = "Automatically"  -- Default to "Automatically"
        GuildNoteUpdaterSettings.selectedSpec[UnitName("player")] = nil  -- No spec selected by default
        GuildNoteUpdaterSettings.itemLevelType[UnitName("player")] = "Overall"  -- Default to Overall Item Level
    end

    self.enabledCharacters = GuildNoteUpdaterSettings.enabledCharacters or {}
    self.specUpdateMode = GuildNoteUpdaterSettings.specUpdateMode or {}
    self.selectedSpec = GuildNoteUpdaterSettings.selectedSpec or {}
    self.itemLevelType = GuildNoteUpdaterSettings.itemLevelType or {}

    self:CreateUI()  -- Now create the UI after loading saved settings
end

-- Update the guild note with item level and spec
-- Pass `true` to `checkForChanges` to only update when the item level or spec has changed
function GuildNoteUpdater:UpdateGuildNote(checkForChanges)
    local characterName = UnitName("player")

    if not self.enabledCharacters[characterName] then
        print("GuildNoteUpdater: Guild Note auto update disabled for this character. Use /guildupdate for settings.")
        return
    end

    -- Get both overall and equipped item levels
    local overallItemLevel, equippedItemLevel = GetAverageItemLevel()

    -- Determine whether to use overall or equipped item level
    local itemLevelType = self.itemLevelType[characterName] or "Overall"
    local itemLevel = (itemLevelType == "Equipped") and equippedItemLevel or overallItemLevel

    -- Get the current spec
    local spec = self:GetSpec(characterName)

    -- Prevent updates if "Select Spec" is still chosen
    if spec == "Select Spec" then
        print("GuildNoteUpdater: Please select a valid specialization.")
        return
    end

    -- Create the new guild note text
    local newNote = "ILvL: " .. math.floor(itemLevel) .. " - Spec: " .. spec

    -- Truncate the spec name if the combined note exceeds 31 characters
    if #newNote > 31 then
        local maxSpecLength = 31 - #("ILvL: " .. math.floor(itemLevel) .. " - Spec: ")
        spec = string.sub(spec, 1, maxSpecLength)
        newNote = "ILvL: " .. math.floor(itemLevel) .. " - Spec: " .. spec
    end

    -- Get the player's guild index
    local guildIndex = self:GetGuildIndexForPlayer()

    if guildIndex then
        local currentNote = select(8, GetGuildRosterInfo(guildIndex))  -- Get the current guild note

        -- If checking for changes, skip if both item level and spec are unchanged
        if checkForChanges and currentNote == newNote then
            return
        end

        -- Only update the note if the note is different
        if self.previousNote ~= newNote then
            print("GuildNoteUpdater: Updating guild note to:", newNote)
            print("GuildNoteUpdater: Run /guildupdate for settings")
            GuildRosterSetPublicNote(guildIndex, newNote)
            -- Store the current item level and note to track future changes
            self.previousItemLevel = math.floor(itemLevel)
            self.previousNote = newNote
        end
    else
        print("GuildNoteUpdater: Unable to find guild index for player.")
    end
end

-- Determine the spec to use for the guild note
function GuildNoteUpdater:GetSpec(characterName)
    local specIndex = GetSpecialization()
    if self.specUpdateMode[characterName] == "Manually" then
        -- Automatically select the current spec if none has been selected yet
        if not self.selectedSpec[characterName] then
            self.selectedSpec[characterName] = select(2, GetSpecializationInfo(specIndex)) or "Select Spec"
        end
        return self.selectedSpec[characterName]
    else
        return select(2, GetSpecializationInfo(specIndex)) or "Unknown"
    end
end

-- Get the player's guild index
function GuildNoteUpdater:GetGuildIndexForPlayer()
    local playerName = UnitName("player")
    for i = 1, GetNumGuildMembers() do
        local name = GetGuildRosterInfo(i)
        if name and name:find(playerName) then
            return i
        end
    end
    return nil
end

-- Create the UI for enabling/disabling the addon and managing spec options
function GuildNoteUpdater:CreateUI()
    local frame = CreateFrame("Frame", "GuildNoteUpdaterUI", UIParent, "BasicFrameTemplateWithInset")
    frame:SetSize(500, 240)  -- Adjust height to accommodate new elements
    frame:SetPoint("CENTER")
    frame:Hide()

    -- Title text
    frame.title = frame:CreateFontString(nil, "OVERLAY")
    frame.title:SetFontObject("GameFontHighlight")
    frame.title:SetPoint("CENTER", frame.TitleBg, "CENTER", 0, 0)
    frame.title:SetText("Guild Note Updater")

    -- Create the enable/disable checkbox
    local enableButton = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
    enableButton:SetPoint("TOPLEFT", 20, -30)
    enableButton.text:SetFontObject("GameFontNormal")
    enableButton.text:SetText("Enable for this character")

    enableButton:SetChecked(self.enabledCharacters[UnitName("player")] or false)
    enableButton:SetScript("OnClick", function(self)
        GuildNoteUpdater.enabledCharacters[UnitName("player")] = self:GetChecked()
        GuildNoteUpdaterSettings.enabledCharacters = GuildNoteUpdater.enabledCharacters  -- Save settings
    end)

    -- Add a label for "Update spec"
    local specUpdateLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    specUpdateLabel:SetPoint("TOPLEFT", 27, -70)
    specUpdateLabel:SetText("Update spec")

    -- Create the dropdown for selecting "Automatically" or "Manually"
    local specUpdateDropdown = CreateFrame("Frame", "GuildNoteUpdaterSpecUpdateDropdown", frame, "UIDropDownMenuTemplate")
    specUpdateDropdown:SetPoint("LEFT", specUpdateLabel, "RIGHT", 30, 0)

    -- Create the dropdown menu for manual spec selection (aligned directly under the "Update spec" dropdown)
    local specDropdown = CreateFrame("Frame", "GuildNoteUpdaterSpecDropdown", frame, "UIDropDownMenuTemplate")
    specDropdown:SetPoint("TOPLEFT", specUpdateDropdown, "BOTTOMLEFT", 0, -5)  -- Adjusted positioning to match alignment

    -- Add extra space between spec dropdown and item level type
    local itemLevelSpacer = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    itemLevelSpacer:SetPoint("TOPLEFT", specDropdown, "BOTTOMLEFT", 0, -10)  -- Add space here

    -- Add a label for Item Level Type
    local itemLevelTypeLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    itemLevelTypeLabel:SetPoint("TOPLEFT", 27, -143)
    itemLevelTypeLabel:SetText("Item Level Type")

    -- Create the dropdown menu for selecting item level type (Overall or Equipped)
    local itemLevelDropdown = CreateFrame("Frame", "GuildNoteUpdaterItemLevelDropdown", frame, "UIDropDownMenuTemplate")
    itemLevelDropdown:SetPoint("LEFT", itemLevelTypeLabel, "RIGHT", 10, 0)

    -- Function for selecting spec update mode (Automatically or Manually)
    local function OnSpecUpdateSelect(self)
        GuildNoteUpdater.specUpdateMode[UnitName("player")] = self.value
        UIDropDownMenu_SetText(specUpdateDropdown, self.value)
        GuildNoteUpdaterSettings.specUpdateMode = GuildNoteUpdater.specUpdateMode

        -- Enable or disable the spec dropdown based on the selection
        if self.value == "Manually" then
            UIDropDownMenu_EnableDropDown(GuildNoteUpdaterSpecDropdown)
            -- Immediately update with the selected spec
            GuildNoteUpdater:UpdateGuildNote()
        else
            UIDropDownMenu_DisableDropDown(GuildNoteUpdaterSpecDropdown)
            GuildNoteUpdater:UpdateGuildNote()  -- Automatically update spec
        end
    end

    local function InitializeSpecUpdateDropdown(self, level)
        local info = UIDropDownMenu_CreateInfo()
        info.text = "Automatically"
        info.value = "Automatically"
        info.func = OnSpecUpdateSelect
        info.checked = (GuildNoteUpdater.specUpdateMode[UnitName("player")] == "Automatically")
        UIDropDownMenu_AddButton(info, level)

        info.text = "Manually"
        info.value = "Manually"
        info.func = OnSpecUpdateSelect
        info.checked = (GuildNoteUpdater.specUpdateMode[UnitName("player")] == "Manually")
        UIDropDownMenu_AddButton(info, level)
    end

    UIDropDownMenu_Initialize(specUpdateDropdown, InitializeSpecUpdateDropdown)
    UIDropDownMenu_SetWidth(specUpdateDropdown, 120)
    UIDropDownMenu_SetText(specUpdateDropdown, self.specUpdateMode[UnitName("player")] or "Automatically")

    -- Function for selecting a spec manually
    local function OnSpecSelect(self)
        GuildNoteUpdater.selectedSpec[UnitName("player")] = self.value
        UIDropDownMenu_SetText(specDropdown, self.value)
        GuildNoteUpdaterSettings.selectedSpec = GuildNoteUpdater.selectedSpec
        -- Immediately update the guild note with the selected spec
        GuildNoteUpdater:UpdateGuildNote()
    end

    local function InitializeSpecDropdown(self, level)
        local info = UIDropDownMenu_CreateInfo()
        local numSpecs = GetNumSpecializations()
        info.text = "Select Spec"
        info.value = "Select Spec"
        info.func = OnSpecSelect
        info.checked = (GuildNoteUpdater.selectedSpec[UnitName("player")] == "Select Spec")
        UIDropDownMenu_AddButton(info, level)
        for i = 1, numSpecs do
            local specID, specName = GetSpecializationInfo(i)
            info.text = specName
            info.value = specName
            info.func = OnSpecSelect
            info.checked = (specName == GuildNoteUpdater.selectedSpec[UnitName("player")])
            UIDropDownMenu_AddButton(info, level)
        end
    end

    UIDropDownMenu_Initialize(specDropdown, InitializeSpecDropdown)
    UIDropDownMenu_SetWidth(specDropdown, 120)
    UIDropDownMenu_SetText(specDropdown, self.selectedSpec[UnitName("player")] or "Select Spec")

    -- Disable the spec dropdown if "Automatically" is selected
    if self.specUpdateMode[UnitName("player")] == "Automatically" then
        UIDropDownMenu_DisableDropDown(specDropdown)
    end

    -- Function for selecting item level type (Overall or Equipped)
    local function OnItemLevelSelect(self)
        GuildNoteUpdater.itemLevelType[UnitName("player")] = self.value
        UIDropDownMenu_SetText(itemLevelDropdown, self.value)
        GuildNoteUpdaterSettings.itemLevelType = GuildNoteUpdater.itemLevelType
        -- Immediately update the guild note when item level type is changed
        GuildNoteUpdater:UpdateGuildNote(true)
    end

    local function InitializeItemLevelDropdown(self, level)
        local info = UIDropDownMenu_CreateInfo()
        info.text = "Overall"
        info.value = "Overall"
        info.func = OnItemLevelSelect
        info.checked = (GuildNoteUpdater.itemLevelType[UnitName("player")] == "Overall")
        UIDropDownMenu_AddButton(info, level)

        info.text = "Equipped"
        info.value = "Equipped"
        info.func = OnItemLevelSelect
        info.checked = (GuildNoteUpdater.itemLevelType[UnitName("player")] == "Equipped")
        UIDropDownMenu_AddButton(info, level)
    end

    UIDropDownMenu_Initialize(itemLevelDropdown, InitializeItemLevelDropdown)
    UIDropDownMenu_SetWidth(itemLevelDropdown, 120)
    UIDropDownMenu_SetText(itemLevelDropdown, self.itemLevelType[UnitName("player")] or "Overall")

    -- Create a slash command to toggle the UI
    SLASH_GUILDNOTEUPDATER1 = "/guildupdate"
    SlashCmdList["GUILDNOTEUPDATER"] = function()
        if frame:IsShown() then
            frame:Hide()
        else
            frame:Show()
        end
    end
end

GuildNoteUpdater:RegisterEvent("ADDON_LOADED")
GuildNoteUpdater:RegisterEvent("PLAYER_ENTERING_WORLD")
GuildNoteUpdater:RegisterEvent("GUILD_ROSTER_UPDATE")  -- Register the event to handle guild roster updates
GuildNoteUpdater:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")  -- Register event to detect equipment changes
GuildNoteUpdater:RegisterEvent("ACTIVE_TALENT_GROUP_CHANGED")  -- Register event to detect spec changes
GuildNoteUpdater:SetScript("OnEvent", GuildNoteUpdater.OnEvent)