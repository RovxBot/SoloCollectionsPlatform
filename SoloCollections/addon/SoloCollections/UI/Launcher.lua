local SC = SoloCollections
local UI = SC.UI

local TRANSMOG_MINIMAP_DEFAULT_ANGLE = 225

-- The verified local ezCollections 2.2 Transmogrify artwork is a 32x64
-- micro-button with the usable glyph in its upper half.  Cropping the lower
-- half selects transparent padding and leaves a malformed minimap button.
local MICRO_BUTTON_ICON_COORD = { 0.08, 0.92, 0.02, 0.48 }

local function normalizeMinimapAngle(value)
    value = tonumber(value) or TRANSMOG_MINIMAP_DEFAULT_ANGLE
    value = value % 360
    if value < 0 then value = value + 360 end
    return math.floor(value + 0.5) % 360
end

local function savedTransmogMinimapAngle()
    local saved = SC.db and SC.db.transmogMinimap
    return normalizeMinimapAngle(saved and saved.angle)
end

local function saveTransmogMinimapAngle(button, angle)
    if not SC.db then return end
    SC.db.transmogMinimap = {
        angle = normalizeMinimapAngle(angle or button.scMinimapAngle),
    }
end

local function positionTransmogMinimapButton(button, angle)
    local minimap = _G.Minimap
    -- DragonUI and other minimap-button collectors re-parent their managed
    -- children. Leave their placement alone once that happens.
    if not (button and minimap and button:GetParent() == minimap) then return false end

    local width, height = minimap:GetWidth(), minimap:GetHeight()
    if not width or not height or width <= 0 or height <= 0 then return false end

    angle = normalizeMinimapAngle(angle)
    local buttonSize = math.max(button:GetWidth() or 0, button:GetHeight() or 0)
    local radius = math.max(12, math.min(width, height) * 0.5 - buttonSize * 0.5 + 6)
    local radians = math.rad(angle)
    button:ClearAllPoints()
    button:SetPoint("CENTER", minimap, "CENTER", math.cos(radians) * radius, math.sin(radians) * radius)
    button.scMinimapAngle = angle
    return true
end

local function updateTransmogMinimapDrag(button)
    local minimap = _G.Minimap
    if not (minimap and button:GetParent() == minimap) then return end

    local centerX, centerY = minimap:GetCenter()
    if not centerX or not centerY then return end

    local cursorX, cursorY = GetCursorPosition()
    local scale = minimap:GetEffectiveScale() or 1
    if scale <= 0 then scale = 1 end
    local angle = math.deg(math.atan2(cursorY / scale - centerY, cursorX / scale - centerX))
    if angle < 0 then angle = angle + 360 end
    positionTransmogMinimapButton(button, angle)
end

local function transmogIconPath()
    if UI.EzCollections and UI.EzCollections.AssetPath then
        local path = UI.EzCollections:AssetPath(
            "Textures\\UI-MicroButton-Transmogrify-Up.tga",
            "Interface\\Icons\\INV_Chest_Cloth_17"
        )
        if path then return path end
    end
    if SC.RetailUI and type(SC.RetailUI.GetWardrobePortraitPath) == "function" then
        local path = SC.RetailUI.GetWardrobePortraitPath()
        if path then return path end
    end
    return "Interface\\Icons\\INV_Chest_Cloth_17"
end

local function createTransmogMinimapButton()
    local minimap = _G.Minimap
    if not minimap then return nil end

    local button = CreateFrame("Button", "SoloCollectionsTransmogMinimapButton", minimap)
    button:SetWidth(31)
    button:SetHeight(31)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(8)
    button:SetMovable(true)
    button:EnableMouse(true)
    button:SetClampedToScreen(true)
    button:RegisterForClicks("LeftButtonUp")
    button:RegisterForDrag("LeftButton")

    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetTexture(transmogIconPath())
    icon:SetPoint("TOPLEFT", button, "TOPLEFT", 3, -3)
    icon:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -3, 3)
    icon:SetTexCoord(unpack(MICRO_BUTTON_ICON_COORD))
    button.icon = icon

    local border = button:CreateTexture(nil, "OVERLAY")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetPoint("TOPLEFT", button, "TOPLEFT", -4, 4)
    border:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 4, -4)

    button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight", "ADD")
    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText(SC.Localize("Transmogrify", "幻化"))
        GameTooltip:AddLine(SC.Localize(
            "Click to open the Transmog window. Drag to move this button.",
            "点击打开幻化室。拖动可改变小地图位置。"
        ), 0.82, 0.72, 0.52, true)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    button:SetScript("OnDragStart", function(self)
        if self:GetParent() ~= minimap then return end
        self.scMinimapDragging = true
        self.scMinimapWasDragged = true
        self:SetScript("OnUpdate", updateTransmogMinimapDrag)
        GameTooltip:Hide()
    end)
    button:SetScript("OnDragStop", function(self)
        self:SetScript("OnUpdate", nil)
        if not self.scMinimapDragging then return end
        self.scMinimapDragging = nil
        updateTransmogMinimapDrag(self)
        saveTransmogMinimapAngle(self)
    end)
    button:SetScript("OnClick", function(self)
        if self.scMinimapWasDragged then
            self.scMinimapWasDragged = nil
            return
        end
        if SC.ToggleTransmog then
            SC:ToggleTransmog()
        elseif UI.ToggleTransmog then
            UI.ToggleTransmog()
        end
    end)
    button:SetScript("OnShow", function(self)
        positionTransmogMinimapButton(self, savedTransmogMinimapAngle())
    end)
    button:SetScript("OnHide", function(self)
        self:SetScript("OnUpdate", nil)
    end)

    if not minimap.scTransmogMinimapSizeHooked then
        minimap.scTransmogMinimapSizeHooked = true
        minimap:HookScript("OnSizeChanged", function()
            if UI.TransmogMinimapButton then
                positionTransmogMinimapButton(UI.TransmogMinimapButton, savedTransmogMinimapAngle())
            end
        end)
    end

    positionTransmogMinimapButton(button, savedTransmogMinimapAngle())
    return button
end

function UI.CreateLauncher()
    if SC.UIPlatform and not SC.UIPlatform:CanCreateUI() then return nil end

    -- DragonUI owns the mounts/pets entry. The old free-floating launchers are
    -- intentionally retired; hide them too when a development tool reloads
    -- this file without a full UI reload.
    if UI.Launcher then
        UI.Launcher:Hide()
        UI.Launcher = nil
    end
    if UI.TransmogLauncher then
        UI.TransmogLauncher:Hide()
        UI.TransmogLauncher = nil
    end

    if not UI.TransmogMinimapButton then
        UI.TransmogMinimapButton = createTransmogMinimapButton()
    end

    return UI.TransmogMinimapButton
end

function UI.ResetPositions()
    if UI.TransmogMinimapButton then
        positionTransmogMinimapButton(UI.TransmogMinimapButton, savedTransmogMinimapAngle())
    end
    if UI.CollectionsFrame then
        if SC.UIPlatform and SC.UIPlatform:IsDragonUIShell() then
            SC.UIPlatform:RestoreWindow(UI.CollectionsFrame)
        elseif SC.db and SC.db.frame then
            local saved = SC.db.frame
            UI.CollectionsFrame:ClearAllPoints()
            UI.CollectionsFrame:SetPoint(saved.point, UIParent, saved.relativePoint, saved.x, saved.y)
            UI.CollectionsFrame:SetClampedToScreen(true)
        end
    end
    if UI.TransmogFrame then
        if SC.UIPlatform and SC.UIPlatform:IsDragonUIShell() and SC.UIPlatform.RestoreTransmogWindow then
            SC.UIPlatform:RestoreTransmogWindow(UI.TransmogFrame)
        elseif SC.db and SC.db.transmogFrame then
            local saved = SC.db.transmogFrame
            UI.TransmogFrame:ClearAllPoints()
            UI.TransmogFrame:SetPoint(saved.point, UIParent, saved.relativePoint, saved.x, saved.y)
            UI.TransmogFrame:SetClampedToScreen(true)
        end
    end
    if UI.SyncJournalFromDatabase then
        UI.SyncJournalFromDatabase()
    end
end
