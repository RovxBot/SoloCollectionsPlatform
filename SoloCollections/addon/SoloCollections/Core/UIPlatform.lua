local SC = SoloCollections

local Platform = SC.UIPlatform or {}
SC.UIPlatform = Platform

Platform.API_VERSION = 1
Platform.WINDOW_POSITION_KEY = "solocollections-journal"
Platform.TRANSMOG_WINDOW_POSITION_KEY = "solocollections-transmog"
Platform.requiredCapabilities = {
    "chrome.panel",
    "chrome.persist",
    "chrome.position-migration",
    "modules.feature-registry",
    "components.collection-header",
    "components.journal-filter",
    "components.random-collection",
    "components.random-mount",
    "components.red-action",
    "components.journal-tabs",
}

local function copyPosition(source)
    if type(source) ~= "table" then return nil end
    return {
        point = source.point,
        relativePoint = source.relativePoint or source.relPoint,
        x = tonumber(source.x) or 0,
        y = tonumber(source.y) or 0,
    }
end

-- DragonUI_NewEra 0.1.x exposes its supported runtime surface directly on
-- DragonUI_NewEra (chrome, FrameUtil, RegisterPanel, tabs), rather than via
-- the short-lived Public table used by the integration-suite snapshot.  Keep
-- that difference contained here: the rest of SoloCollections continues to
-- consume one small, capability-checked platform object.
local function buildCurrentNewEraAdapter(newEra)
    if type(newEra) ~= "table" then return nil, "namespace" end
    if not (newEra.chrome and type(newEra.chrome.Apply) == "function") then return nil, "chrome" end
    if not (newEra.FrameUtil and type(newEra.FrameUtil.PersistWindowPosition) == "function"
        and type(newEra.FrameUtil.RestoreWindowPosition) == "function") then
        return nil, "window-position"
    end
    if type(newEra.RegisterPanel) ~= "function" then return nil, "register-panel" end

    local public = { API_VERSION = Platform.API_VERSION, adapter = "newera-0.1" }
    local capabilities = {}
    function public.HasCapability(name) return capabilities[name] == true end
    function public.Require(version, requested)
        if tonumber(version) and public.API_VERSION < tonumber(version) then return false, "API_VERSION" end
        for _, name in ipairs(requested or {}) do
            if not public.HasCapability(name) then return false, name end
        end
        return true
    end

    local chrome = {}
    public.Chrome = chrome
    function chrome:Apply(frame, options)
        newEra.chrome.Apply(frame, options or {})
        return true
    end
    function chrome:SetTitle(frame, title)
        if newEra.chrome.SetTitle then return newEra.chrome.SetTitle(frame, title) end
    end
    function chrome:PersistWindowPosition(frame, key, defaultPoint, dragHandle)
        newEra.FrameUtil.PersistWindowPosition(frame, key, defaultPoint, dragHandle)
        return true
    end
    function chrome:MigrateWindowPosition(key, legacy)
        if not (key and type(legacy) == "table" and legacy.point and newEra.db) then return false end
        newEra.db.windowPos = newEra.db.windowPos or {}
        if newEra.db.windowPos[key] then return false end
        newEra.db.windowPos[key] = {
            point = legacy.point,
            relPoint = legacy.relPoint or legacy.relativePoint or legacy.point,
            x = tonumber(legacy.x) or 0,
            y = tonumber(legacy.y) or 0,
        }
        return true
    end
    function chrome:RestoreWindowPosition(frame, key, defaultPoint)
        return newEra.FrameUtil.RestoreWindowPosition(frame, key, defaultPoint)
    end
    function chrome:ResetWindowPosition(key)
        if not (key and newEra.db and newEra.db.windowPos) then return false end
        newEra.db.windowPos[key] = nil
        return true
    end
    function chrome:KeepOnScreen(frame)
        if newEra.FrameUtil.KeepOnScreen then return newEra.FrameUtil.KeepOnScreen(frame) end
    end

    local components = {}
    public.Components = components
    local function setButtonText(button, text)
        local label = button:GetFontString()
        if not label then
            label = button:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            label:SetPoint("CENTER")
            button:SetFontString(label)
        end
        button:SetText(text or "")
    end

    function components:SkinRedActionButton(button, options)
        if not button then return false end
        local dragon = newEra.dragon
        if dragon and type(dragon.SkinRedButton) == "function" then
            local ok = pcall(dragon.SkinRedButton, button, options)
            if ok then return true end
        end
        if newEra.buttonskin and type(newEra.buttonskin.Skin) == "function" then
            return newEra.buttonskin.Skin(button, options or {})
        end
        return false
    end

    function components:CreateCollectionInfoHeader(parent, spec)
        spec = spec or {}
        local host = CreateFrame("Frame", spec.name, parent)
        host:SetPoint("TOPLEFT", parent, "TOPLEFT", spec.x or 0, -(spec.y or 0))
        if spec.width then host:SetWidth(spec.width) end
        if spec.height then host:SetHeight(spec.height) end
        if spec.point then
            host:ClearAllPoints()
            host:SetPoint(spec.point, parent, spec.relativePoint or spec.point, spec.x or 0, spec.y or 0)
        end

        local iconSize = spec.iconSize or 40
        local frameSize = iconSize / 0.4922
        local frameX = (0.5 - 0.4727) * frameSize
        local frameY = (0.4336 - 0.5) * frameSize
        local ornament = host:CreateTexture(nil, "OVERLAY")
        ornament:SetTexture(spec.frameTexture or "Interface\\AddOns\\DragonUI\\Textures\\Collections\\IconFrameGold.tga")
        ornament:SetWidth(frameSize)
        ornament:SetHeight(frameSize)
        ornament:SetPoint("TOPLEFT", host, "TOPLEFT", 2, -2)
        local icon = host:CreateTexture(nil, "ARTWORK")
        icon:SetWidth(iconSize)
        icon:SetHeight(iconSize)
        icon:SetPoint("CENTER", ornament, "CENTER", -frameX, -frameY)
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        local button = CreateFrame("Button", nil, host)
        button:SetAllPoints(icon)
        if spec.onClick then button:SetScript("OnClick", spec.onClick) end
        if spec.onDragStart then
            button:RegisterForDrag("LeftButton")
            button:SetScript("OnDragStart", spec.onDragStart)
        end
        if spec.onEnter then button:SetScript("OnEnter", spec.onEnter) end
        if spec.onLeave then button:SetScript("OnLeave", spec.onLeave) end
        local name = host:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        name:SetPoint("LEFT", icon, "RIGHT", 14, 0)
        name:SetWidth(spec.nameWidth or 260)
        name:SetHeight(spec.nameHeight or 40)
        name:SetJustifyH("LEFT")
        name:SetJustifyV("CENTER")
        name:SetWordWrap(true)
        local source = host:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        source:SetPoint("TOPLEFT", ornament, "BOTTOMLEFT", 12, -4)
        source:SetWidth(spec.textWidth or 320)
        source:SetJustifyH("LEFT")
        local description = host:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        description:SetPoint("TOPLEFT", source, "BOTTOMLEFT", 0, -6)
        description:SetWidth(spec.textWidth or 320)
        description:SetJustifyH("LEFT")
        description:SetJustifyV("TOP")
        description:SetTextColor(0.82, 0.82, 0.82)
        return {
            frame = host, ornament = ornament, icon = icon, button = button,
            name = name, source = source, description = description,
        }
    end

    function components:CreateJournalFilterButton(parent, spec)
        spec = spec or {}
        local button = CreateFrame("Button", spec.name, parent, "UIPanelButtonTemplate")
        button:SetWidth(spec.width or 76)
        button:SetHeight(spec.height or 20)
        setButtonText(button, spec.label or FILTER or "Filter")
        local arrow = button:CreateTexture(nil, "ARTWORK")
        arrow:SetWidth(8)
        arrow:SetHeight(8)
        arrow:SetPoint("RIGHT", button, "RIGHT", -6, 0)
        arrow:SetTexture(spec.arrowTexture or "Interface\\ChatFrame\\ChatFrameExpandArrow")
        local label = button:GetFontString()
        if label then
            label:ClearAllPoints()
            label:SetPoint("LEFT", button, "LEFT", 8, 0)
        end
        self:SkinRedActionButton(button)
        if spec.onClick then button:SetScript("OnClick", spec.onClick) end
        return button
    end

    function components:CreateRandomCollectionButton(parent, spec)
        spec = spec or {}
        local button = CreateFrame("Button", spec.name, parent)
        button:SetWidth(spec.width or 30)
        button:SetHeight(spec.height or 30)
        local icon = button:CreateTexture(nil, "ARTWORK")
        icon:SetAllPoints(button)
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        icon:SetTexture(spec.icon or spec.fallbackIcon or "Interface\\Icons\\INV_Misc_QuestionMark")
        local border = button:CreateTexture(nil, "OVERLAY")
        border:SetTexture(spec.frameTexture or "Interface\\AddOns\\DragonUI\\Textures\\ActionBars\\uiactionbariconframe_white.tga")
        local scale = (spec.width or 30) / 37
        local edge = 2.2 * scale
        border:SetVertexColor(0.08, 0.08, 0.08)
        border:SetPoint("TOPRIGHT", button, "TOPRIGHT", edge, 2.3 * scale)
        border:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", -edge, -edge)
        button._neIcon, button._neBorder = icon, border
        button:SetPushedTexture("Interface\\Buttons\\UI-Quickslot-Depress")
        button:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
        if spec.onClick then button:SetScript("OnClick", spec.onClick) end
        if spec.onEnter then button:SetScript("OnEnter", spec.onEnter) end
        if spec.onLeave then button:SetScript("OnLeave", spec.onLeave) end
        return button
    end

    function components:CreateRandomMountButton(parent, spec)
        spec = spec or {}
        if not spec.icon and not spec.fallbackIcon then
            spec.fallbackIcon = "Interface\\AddOns\\DragonUI_NewEra\\Textures\\Collections\\MountUpFavourites.blp"
        end
        return self:CreateRandomCollectionButton(parent, spec)
    end

    function components:CreateJournalTab(parent, spec)
        spec = spec or {}
        local index = spec.index or 1
        local name = spec.name or ("SoloCollectionsNewEraJournalTab" .. tostring(index))
        local button = CreateFrame("Button", name, parent, "CharacterFrameTabButtonTemplate")
        button:SetID(index)
        button:SetText(spec.label or "")
        if newEra.tabs and newEra.tabs.ReskinClassicTab then
            newEra.tabs.ReskinClassicTab(name, { selectedTextY = -3, deselectedTextY = -3 })
        end
        local label = _G[name .. "Text"] or button:GetFontString()
        button:SetWidth(math.max(70, math.floor((label and label:GetStringWidth() or 40) + 30)))
        local normalHeight = spec.height or 36
        local selectedHeight = spec.selectedHeight or 42
        button:SetHeight(normalHeight)
        local normalLevel = button:GetFrameLevel()
        if spec.onClick then button:SetScript("OnClick", spec.onClick) end
        function button:SetSelected(value)
            components:SetJournalTabSelected(self, value)
            self:SetHeight(value and selectedHeight or normalHeight)
            self:SetFrameLevel(normalLevel + (value and 8 or 0))
        end
        button.scCutoff = spec.cutoff and true or false
        button.scNewEraJournalTab = true
        return button
    end

    function components:SetJournalTabSelected(button, selected)
        if not button then return false end
        if selected then
            if PanelTemplates_SelectTab then PanelTemplates_SelectTab(button) else button:Disable() end
        else
            if PanelTemplates_DeselectTab then PanelTemplates_DeselectTab(button) else button:Enable() end
        end
        button.scSelected = selected and true or false
        return true
    end

    function components:LayoutJournalTabs(parent, tabs, spec)
        if not parent then return false end
        spec = spec or {}
        local names = {}
        for _, tab in ipairs(tabs or {}) do
            if tab and tab:GetName() then names[#names + 1] = tab:GetName() end
        end
        if newEra.tabs and type(newEra.tabs.SizeAndAnchorTabs) == "function" then
            newEra.tabs.SizeAndAnchorTabs(parent, names, {
                parentPoint = "BOTTOMLEFT", startX = spec.startX or 14, startY = spec.startY or 2,
                gap = spec.gap or 1, minWidth = spec.minWidth or 70, textPadding = spec.textPadding or 30,
            })
            return true
        end
        local x = spec.startX or 14
        for _, tab in ipairs(tabs or {}) do
            if tab then
                tab:ClearAllPoints()
                tab:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", x, spec.startY or 2)
                x = x + tab:GetWidth() + (spec.gap or 1)
            end
        end
        return true
    end

    local modules = {}
    public.Modules = modules
    function modules:RegisterFeature(spec)
        if type(spec) ~= "table" or not spec.id then return nil, "feature-id" end
        return newEra.RegisterPanel({
            id = spec.id, title = spec.title, desc = spec.description or spec.desc,
            frame = spec.frame, openFn = spec.open, closeFn = spec.close,
            refreshFn = spec.refresh, defaultPoint = spec.defaultPoint, order = spec.order,
        })
    end
    function modules:IsEnabled(id)
        return newEra.modules and newEra.modules.IsEnabled and newEra.modules.IsEnabled(id) or false
    end

    capabilities["chrome.panel"] = true
    capabilities["chrome.persist"] = true
    capabilities["chrome.position-migration"] = true
    capabilities["modules.feature-registry"] = true
    capabilities["components.collection-header"] = true
    capabilities["components.journal-filter"] = true
    capabilities["components.random-collection"] = true
    capabilities["components.random-mount"] = true
    capabilities["components.red-action"] = true
    capabilities["components.journal-tabs"] = true
    return public
end

function Platform:ShowError(reason)
    if self.errorShown then return end
    self.errorShown = true
    local message = "|cffff5555SoloCollections UI disabled:|r DragonUI_NewEra integration unavailable"
    if reason then message = message .. " (" .. tostring(reason) .. ")" end
    if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
        DEFAULT_CHAT_FRAME:AddMessage(message)
    end
end

function Platform:Initialize()
    local public = DragonUI_NewEra and DragonUI_NewEra.Public
    if not public or type(public.Require) ~= "function" then
        public, self.reason = buildCurrentNewEraAdapter(DragonUI_NewEra)
        if not public then
            self.ready = false
            return false, self.reason
        end
        self.adapter = "newera-0.1"
    else
        self.adapter = "public"
    end
    local ok, missing = public.Require(self.API_VERSION, self.requiredCapabilities)
    if not ok then
        self.ready = false
        self.reason = missing or "capability"
        return false, self.reason
    end
    self.public = public
    self.ready = true
    self.reason = nil
    return true
end

function Platform:IsReady()
    if self.ready == nil then self:Initialize() end
    return self.ready == true
end

function Platform:CanCreateUI()
    if self:IsReady() then return true end
    self:ShowError(self.reason)
    return false
end

function Platform:GetPublic()
    if not self:IsReady() then return nil end
    return self.public
end

function Platform:GetShellMode()
    local settings = SC.db and SC.db.uiPlatform
    local mode = settings and settings.uiShell or SC.DEFAULT_UI_SHELL
    if mode ~= "LEGACY" then return "DRAGONUI" end
    return "LEGACY"
end

function Platform:IsDragonUIShell()
    return self:IsReady() and self:GetShellMode() == "DRAGONUI"
end

function Platform:SetShellMode(mode)
    if not SC.db then return false end
    mode = string.upper(tostring(mode or ""))
    if mode ~= "LEGACY" and mode ~= "DRAGONUI" then return false end
    SC.db.uiPlatform = SC.db.uiPlatform or {}
    SC.db.uiPlatform.uiShell = mode
    return true
end

function Platform:GetLegacyFramePosition()
    local settings = SC.db and SC.db.uiPlatform
    return copyPosition((settings and settings.legacyFrameBackup) or (SC.db and SC.db.frame))
end

function Platform:PersistWindow(frame, dragHandle)
    if not (frame and self:IsDragonUIShell()) then return false end
    local public = self.public
    local settings = SC.db.uiPlatform
    if not settings.positionMigrated then
        local legacy = copyPosition(SC.db.frame)
        if legacy then
            settings.legacyFrameBackup = settings.legacyFrameBackup or legacy
            public.Chrome:MigrateWindowPosition(self.WINDOW_POSITION_KEY, legacy)
        end
        settings.positionMigrated = true
        SC.db.frame = nil
    end
    local fallback = settings.legacyFrameBackup or { point = "CENTER", relativePoint = "CENTER", x = 0, y = 0 }
    return public.Chrome:PersistWindowPosition(frame, self.WINDOW_POSITION_KEY, {
        point = fallback.point,
        relPoint = fallback.relativePoint,
        x = fallback.x,
        y = fallback.y,
    }, dragHandle)
end

function Platform:RestoreWindow(frame)
    if not (frame and self:IsDragonUIShell()) then return false end
    local fallback = self:GetLegacyFramePosition() or { point = "CENTER", relativePoint = "CENTER", x = 0, y = 0 }
    return self.public.Chrome:RestoreWindowPosition(frame, self.WINDOW_POSITION_KEY, {
        point = fallback.point,
        relPoint = fallback.relativePoint,
        x = fallback.x,
        y = fallback.y,
    })
end

function Platform:PersistTransmogWindow(frame, dragHandle)
    if not (frame and self:IsDragonUIShell()) then return false end
    local saved = SC.db and SC.db.transmogFrame
    local fallback = {
        point = (saved and saved.point) or "CENTER",
        relativePoint = (saved and saved.relativePoint) or "CENTER",
        x = (saved and saved.x) or 0,
        y = (saved and saved.y) or 0,
    }
    return self.public.Chrome:PersistWindowPosition(frame, self.TRANSMOG_WINDOW_POSITION_KEY, {
        point = fallback.point,
        relPoint = fallback.relativePoint,
        x = fallback.x,
        y = fallback.y,
    }, dragHandle)
end

function Platform:RestoreTransmogWindow(frame)
    if not (frame and self:IsDragonUIShell()) then return false end
    local saved = SC.db and SC.db.transmogFrame
    local fallback = {
        point = (saved and saved.point) or "CENTER",
        relativePoint = (saved and saved.relativePoint) or "CENTER",
        x = (saved and saved.x) or 0,
        y = (saved and saved.y) or 0,
    }
    return self.public.Chrome:RestoreWindowPosition(frame, self.TRANSMOG_WINDOW_POSITION_KEY, {
        point = fallback.point,
        relPoint = fallback.relativePoint,
        x = fallback.x,
        y = fallback.y,
    })
end

function Platform:ResetWindowPosition()
    if self:IsReady() then
        self.public.Chrome:ResetWindowPosition(self.WINDOW_POSITION_KEY)
        self.public.Chrome:ResetWindowPosition(self.TRANSMOG_WINDOW_POSITION_KEY)
    end
    if SC.db and SC.db.uiPlatform then
        SC.db.uiPlatform.positionMigrated = false
        SC.db.uiPlatform.legacyFrameBackup = nil
    end
end

function Platform:RegisterFeature()
    if self.featureRegistered or not self:IsReady() then return self.featureRegistered == true end
    local UI = SC.UI
    local module, reason = self.public.Modules:RegisterFeature({
        id = "solocollections",
        title = "Solo Collections",
        description = "Server-authoritative collection journal.",
        open = UI.ToggleJournal,
        close = UI.HideJournal,
        refresh = UI.RefreshActivePage,
    })
    if not module then
        self.reason = reason or "feature-registration"
        self:ShowError(self.reason)
        return false
    end
    self.featureRegistered = true
    return true
end

Platform:Initialize()
