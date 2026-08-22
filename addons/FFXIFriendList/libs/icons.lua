--[[
* FFXIFriendList Icon Manager
* Texture loading and caching for UI icons
]]--

require('common');
local imgui = require('imgui');
local ffi = require('ffi');
local d3d = require('d3d8');
local C = ffi.C;

local M = {};

-- Icon cache (texture objects)
local iconCache = {};

-- D3D device (deferred access for Linux/Wine compatibility)
local d3d8dev = nil;

-- Addon path (set during initialization)
local addonPath = nil;

-- ========================================
-- D3D Device Access
-- ========================================

local function GetD3D8Device()
    if d3d8dev == nil then
        d3d8dev = d3d.get_device();
    end
    return d3d8dev;
end

-- ========================================
-- Icon Definitions
-- ========================================

-- Map icon names to filenames (without extension)
local iconFiles = {
    -- Status icons
    online = "online",
    offline = "offline",
    pending = "friend_request",
    away = "away",
    
    -- Lock icons
    lock = "lock_icon",
    unlock = "unlock_icon",
    
    -- Social icons
    discord = "discord",
    github = "github",
    heart = "heart",
    friend_request = "friend_request",
    
    -- Nation icons
    nation_sandoria = "sandy_icon",
    nation_bastok = "bastok_icon",
    nation_windurst = "windy_icon",
    
    -- Tab icons
    tab_friends = "friends",
    tab_requests = "requests",
    tab_notifications = "notifications",
    tab_privacy = "privacy",
    tab_view = "view",
    tab_tags = "tags",
    tab_help = "help",
    tab_themes = "theme",
    add_friend = "add-friend",
    
    -- UI action icons
    refresh = "refresh",
    collapse = "collapse",
    expand = "expand",
};

-- ========================================
-- Texture Loading
-- ========================================

-- Initialize the icon manager with addon path
function M.Initialize(path)
    addonPath = path;
    if addonPath then
        -- Normalize path - remove trailing slashes
        addonPath = addonPath:gsub('/$', ''):gsub('\\$', '');
    end
end

-- Load a texture from the assets/icons folder
local function LoadTexture(textureName)
    local device = GetD3D8Device();
    if device == nil then 
        return nil; 
    end
    
    if addonPath == nil then
        return nil;
    end
    
    local fullPath = nil;
    
    -- Check for custom image override first
    local settings = require('libs.settings');
    local customPath = settings.getCustomImagePath(textureName .. '.png');
    if customPath then
        fullPath = customPath;
    else
        -- Fall back to bundled assets
        fullPath = string.format('%s/assets/icons/%s.png', addonPath, textureName);
    end
    
    -- Load using D3DX
    local textures = T{};
    local texture_ptr = ffi.new('IDirect3DTexture8*[1]');
    local res = C.D3DXCreateTextureFromFileA(device, fullPath, texture_ptr);
    
    if res ~= C.S_OK then
        return nil;
    end
    
    textures.image = ffi.new('IDirect3DTexture8*', texture_ptr[0]);
    d3d.gc_safe_release(textures.image);
    
    return textures;
end

-- ImGui API compatibility -----------------------------------------------------
-- Ashita 4.3 moved to Dear ImGui 1.92, which changed the image API:
--   Image(tex, size, uv0, uv1)                          (tint/border args removed)
--   ImageButton(str_id, tex, size, uv0, uv1, bg, tint)  (str_id first, no frame_padding)
-- Older Ashita (ImGui 1.8x) keeps the legacy signatures. ImageWithBg only exists in
-- the new API, so its presence is used as the version probe.
local NEW_IMAGE_API = (imgui.ImageWithBg ~= nil);

local function DrawImage(textureId, size, uv0, uv1, tint, border)
    if NEW_IMAGE_API then
        imgui.Image(textureId, size, uv0, uv1);
    else
        DrawImage(textureId, size, uv0, uv1, tint, border);
    end
end

local function DrawImageButton(id, textureId, size, uv0, uv1, bg, tint)
    if NEW_IMAGE_API then
        return imgui.ImageButton(id, textureId, size, uv0, uv1, bg, tint);
    end
    -- legacy: textureId, size, uv0, uv1, frame_padding, bg_color, tint_color
    return imgui.ImageButton(textureId, size, uv0, uv1, -1, bg, tint);
end

-- Get or load an icon by name
function M.GetIcon(iconName)
    -- Return from cache if already loaded
    if iconCache[iconName] then
        return iconCache[iconName];
    end
    
    -- Get filename for this icon
    local filename = iconFiles[iconName];
    if not filename then
        return nil;
    end
    
    -- Load the texture
    local texture = LoadTexture(filename);
    if texture then
        iconCache[iconName] = texture;
    end
    
    return texture;
end

-- Preload all icons (call during initialization)
function M.PreloadAll()
    for iconName, _ in pairs(iconFiles) do
        M.GetIcon(iconName);
    end
end

-- Clear the icon cache (call on unload)
function M.ClearCache()
    iconCache = {};
end

-- ========================================
-- ImGui Rendering Helpers
-- ========================================

-- Render an icon with imgui.Image
-- Returns true if icon was rendered, false if fallback needed
function M.RenderIcon(iconName, width, height, tintColor)
    local texture = M.GetIcon(iconName);
    if texture == nil or texture.image == nil then
        return false;
    end
    
    local textureId = tonumber(ffi.cast("uint32_t", texture.image));
    local size = { width or 14, height or 14 };
    local uv0 = { 0, 0 };
    local uv1 = { 1, 1 };
    local tint = tintColor or { 1, 1, 1, 1 };
    local border = { 0, 0, 0, 0 };
    
    DrawImage(textureId, size, uv0, uv1, tint, border);
    return true;
end

-- Render an icon button using imgui.ImageButton with theme styling
-- Returns true if clicked, false if not clicked, nil if icon not available
function M.RenderIconButton(iconName, width, height, tooltip, tintColor)
    local texture = M.GetIcon(iconName);
    if texture == nil or texture.image == nil then
        return nil;
    end
    
    local w = width or 24;
    local h = height or 24;
    local textureId = tonumber(ffi.cast("uint32_t", texture.image));
    
    -- Get button colors from theme (or use fallback)
    local btnColor = {0.26, 0.26, 0.26, 1.0};
    local btnHoverColor = {0.35, 0.35, 0.35, 1.0};
    local btnActiveColor = {0.45, 0.45, 0.45, 1.0};
    
    local app = _G.FFXIFriendListApp;
    if app and app.features and app.features.themes then
        local themeColors = app.features.themes:getCurrentThemeColors();
        if themeColors then
            if themeColors.buttonColor then
                local c = themeColors.buttonColor;
                btnColor = {c.r or 0.26, c.g or 0.26, c.b or 0.26, c.a or 1.0};
            end
            if themeColors.buttonHoverColor then
                local c = themeColors.buttonHoverColor;
                btnHoverColor = {c.r or 0.35, c.g or 0.35, c.b or 0.35, c.a or 1.0};
            end
            if themeColors.buttonActiveColor then
                local c = themeColors.buttonActiveColor;
                btnActiveColor = {c.r or 0.45, c.g or 0.45, c.b or 0.45, c.a or 1.0};
            end
        end
    end
    
    -- Use provided tint color or default to white
    local tint = tintColor or {1, 1, 1, 1};
    
    -- Push button colors and unique ID
    imgui.PushID("icon_btn_" .. iconName);
    imgui.PushStyleColor(ImGuiCol_Button, btnColor);
    imgui.PushStyleColor(ImGuiCol_ButtonHovered, btnHoverColor);
    imgui.PushStyleColor(ImGuiCol_ButtonActive, btnActiveColor);
    -- Frame padding set to -1 to use image size directly
    imgui.PushStyleVar(ImGuiStyleVar_FrameRounding, 4);
    
    -- ImageButton: textureId, size, uv0, uv1, frame_padding, bg_color, tint_color
    -- frame_padding = -1 means use FramePadding style var (default padding)
    local clicked = DrawImageButton("##icon_btn_" .. iconName, textureId, {w, h}, {0, 0}, {1, 1}, {0, 0, 0, 0}, tint);
    
    -- Pop styles and ID
    imgui.PopStyleVar(1);
    imgui.PopStyleColor(3);
    imgui.PopID();
    
    if imgui.IsItemHovered() and tooltip then
        imgui.SetTooltip(tooltip);
    end
    
    return clicked;
end

-- Render icon button with explicit button size (image is automatically scaled by UI.ICON_SCALE)
function M.RenderIconButtonWithSize(iconName, buttonWidth, buttonHeight, tooltip, tintColor)
    local texture = M.GetIcon(iconName);
    if texture == nil or texture.image == nil then
        return nil;
    end
    
    local btnW = buttonWidth or 24;
    local btnH = buttonHeight or 24;
    -- Image is scaled by ICON_SCALE constant
    local UI = require('constants.ui');
    local imgW = math.floor(btnW * UI.ICON_SCALE);
    local imgH = math.floor(btnH * UI.ICON_SCALE);
    local textureId = tonumber(ffi.cast("uint32_t", texture.image));
    
    -- Calculate padding needed to center smaller image in larger button
    local padX = math.max(0, (btnW - imgW) / 2);
    local padY = math.max(0, (btnH - imgH) / 2);
    
    -- Get button colors from theme (or use fallback)
    local btnColor = {0.26, 0.26, 0.26, 1.0};
    local btnHoverColor = {0.35, 0.35, 0.35, 1.0};
    local btnActiveColor = {0.45, 0.45, 0.45, 1.0};
    
    local app = _G.FFXIFriendListApp;
    if app and app.features and app.features.themes then
        local themeColors = app.features.themes:getCurrentThemeColors();
        if themeColors then
            if themeColors.buttonColor then
                local c = themeColors.buttonColor;
                btnColor = {c.r or 0.26, c.g or 0.26, c.b or 0.26, c.a or 1.0};
            end
            if themeColors.buttonHoverColor then
                local c = themeColors.buttonHoverColor;
                btnHoverColor = {c.r or 0.35, c.g or 0.35, c.b or 0.35, c.a or 1.0};
            end
            if themeColors.buttonActiveColor then
                local c = themeColors.buttonActiveColor;
                btnActiveColor = {c.r or 0.45, c.g or 0.45, c.b or 0.45, c.a or 1.0};
            end
        end
    end
    
    -- Use provided tint color or default to white
    local tint = tintColor or {1, 1, 1, 1};
    
    -- Push button colors and unique ID
    imgui.PushID("icon_btn_sized_" .. iconName);
    imgui.PushStyleColor(ImGuiCol_Button, btnColor);
    imgui.PushStyleColor(ImGuiCol_ButtonHovered, btnHoverColor);
    imgui.PushStyleColor(ImGuiCol_ButtonActive, btnActiveColor);
    imgui.PushStyleVar(ImGuiStyleVar_FramePadding, {padX, padY});
    imgui.PushStyleVar(ImGuiStyleVar_FrameRounding, 4);
    
    -- ImageButton: textureId, size, uv0, uv1, frame_padding, bg_color, tint_color
    local clicked = DrawImageButton("##icon_btn_" .. iconName, textureId, {imgW, imgH}, {0, 0}, {1, 1}, {0, 0, 0, 0}, tint);
    
    -- Pop styles and ID
    imgui.PopStyleVar(2);
    imgui.PopStyleColor(3);
    imgui.PopID();
    
    if imgui.IsItemHovered() and tooltip then
        imgui.SetTooltip(tooltip);
    end
    
    return clicked;
end

-- ========================================
-- Status Icon Helpers
-- ========================================

-- Get the appropriate status icon for a friend
function M.GetStatusIconName(isOnline, isPending, isAway)
    if isPending then
        return "pending";
    elseif isAway then
        return "away";
    elseif isOnline then
        return "online";
    else
        return "offline";
    end
end

-- Get tint color for status
function M.GetStatusTint(isOnline, isPending, isAway)
    if isPending then
        return { 1.0, 0.8, 0.0, 1.0 };
    elseif isAway then
        return { 1.0, 1.0, 1.0, 1.0 };
    elseif isOnline then
        return { 1.0, 1.0, 1.0, 1.0 };
    else
        return { 0.70, 0.70, 0.70, 1.0 };
    end
end

-- Render status indicator icon
function M.RenderStatusIcon(isOnline, isPending, size, isAway)
    local iconName = M.GetStatusIconName(isOnline, isPending, isAway);
    local tint = M.GetStatusTint(isOnline, isPending, isAway);
    local iconSize = size or 12;
    
    return M.RenderIcon(iconName, iconSize, iconSize, tint);
end

return M;
