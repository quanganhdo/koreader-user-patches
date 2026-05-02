-- File browser metadata tabs title bar
-- Version: 1.0.0
-- Adds Books / Series / Authors tabs to the file manager title bar.

local Blitbuffer = require("ffi/blitbuffer")
local Button = require("ui/widget/button")
local Device = require("device")
local Event = require("ui/event")
local FileManager = require("apps/filemanager/filemanager")
local FileChooser = require("ui/widget/filechooser")
local Font = require("ui/font")
local Geom = require("ui/geometry")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local InfoMessage = require("ui/widget/infomessage")
local LeftContainer = require("ui/widget/container/leftcontainer")
local LineWidget = require("ui/widget/linewidget")
local NetworkMgr = require("ui/network/manager")
local OverlapGroup = require("ui/widget/overlapgroup")
local PluginLoader = require("pluginloader")
local RightContainer = require("ui/widget/container/rightcontainer")
local Size = require("ui/size")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local _ = require("gettext")
local Screen = Device.screen

local DGENERIC_ICON_SIZE = G_defaults:readSetting("DGENERIC_ICON_SIZE")
local VIRTUAL_ROOT_SYMBOL = "\u{e257}"
local AUTHOR_SYMBOL = "\u{f2c0}"
local SERIES_SYMBOL = "\u{ecd7}"
local EMPTY_VALUE_SYMBOL = "\u{2205}"
local NIGHT_MODE_SYMBOL = "◐"
local FRONTLIGHT_SYMBOL = "☼"
local FRONTLIGHT_OFF_SYMBOL = "☀"
local WIFI_ON_SYMBOL = ""
local WIFI_OFF_SYMBOL = ""

local function findVirtualRoot(path)
    if path then
        return path:find("/" .. VIRTUAL_ROOT_SYMBOL, 1, true)
    end
end

local function getVirtualFragments(path)
    local _root_start, root_end = findVirtualRoot(path)
    if not root_end then
        return
    end

    local fragments = {}
    for fragment in path:sub(root_end + 1):gmatch("[^/]+") do
        table.insert(fragments, fragment)
    end
    return fragments
end

local function getMetadataLeafInfo(path)
    local fragments = getVirtualFragments(path)
    if not fragments or #fragments < 2 then
        return
    end
    if fragments[1] ~= AUTHOR_SYMBOL and fragments[1] ~= SERIES_SYMBOL then
        return
    end

    local title = fragments[2]
    if title == EMPTY_VALUE_SYMBOL then
        title = EMPTY_VALUE_SYMBOL
    end

    return {
        title = title,
        parent_path = path:gsub("(/[^/]+)$", ""),
    }
end

local function getVirtualBaseDir(file_manager)
    local path = file_manager.file_chooser and file_manager.file_chooser.path
    local root_start = findVirtualRoot(path)
    if root_start then
        return path:sub(1, root_start - 1)
    end
end

local function openBooks(file_manager)
    local base_dir = getVirtualBaseDir(file_manager)
    if base_dir and file_manager.file_chooser then
        file_manager.file_chooser:changeToPath(base_dir)
    else
        file_manager:onHome()
    end
end

local function browseByMetadata(file_manager, kind)
    if file_manager.onBrowseByMetadata then
        file_manager:onBrowseByMetadata(kind)
    end
end

local function getSelectedTabKey(file_manager)
    local path = file_manager and file_manager.file_chooser and file_manager.file_chooser.path
    local fragments = getVirtualFragments(path)
    if not fragments then
        return "books"
    end

    for _, fragment in ipairs(fragments) do
        if fragment == AUTHOR_SYMBOL then
            return "authors"
        elseif fragment == SERIES_SYMBOL then
            return "series"
        end
    end

    return "books"
end

local function getBackTitleBarInfo(file_manager)
    local path = file_manager and file_manager.file_chooser and file_manager.file_chooser.path
    local leaf_info = getMetadataLeafInfo(path)
    if not leaf_info then
        return
    end

    return {
        title = leaf_info.title,
        parent_path = leaf_info.parent_path,
        current_path = path,
    }
end

local function getBatteryText()
    if not Device:hasBattery() then
        return ""
    end

    local powerd = Device:getPowerDevice()
    local batt_lvl = powerd:getCapacity()
    local batt_symbol
    if Device:hasAuxBattery() and powerd:isAuxBatteryConnected() then
        batt_lvl = batt_lvl + powerd:getAuxCapacity()
        batt_symbol = powerd:getBatterySymbol(powerd:isAuxCharged(), powerd:isAuxCharging(), batt_lvl / 2)
    else
        batt_symbol = powerd:getBatterySymbol(powerd:isCharged(), powerd:isCharging(), batt_lvl)
    end
    return batt_symbol .. batt_lvl .. "%"
end

local function getWifiText()
    if not Device:hasWifiToggle() then
        return ""
    end
    if NetworkMgr.is_wifi_on == nil then
        NetworkMgr:queryNetworkState()
    end
    if NetworkMgr.is_wifi_on then
        return WIFI_ON_SYMBOL
    end
    return WIFI_OFF_SYMBOL
end

local function getFrontlightText()
    if Device:hasFrontlight() then
        local powerd = Device:getPowerDevice()
        return powerd:isFrontlightOn() and FRONTLIGHT_SYMBOL or FRONTLIGHT_OFF_SYMBOL
    end
    return ""
end

local function showBatteryInfo()
    if not Device:hasBattery() then
        return
    end
    if PluginLoader.loaded_plugins and PluginLoader:isPluginLoaded("batterystat") then
        UIManager:broadcastEvent(Event:new("ShowBatteryStatistics"))
        return
    end

    UIManager:show(InfoMessage:new{
        text = getBatteryText(),
    })
end

local function toggleWifi(refresh_callback)
    if not Device:hasWifiToggle() then
        return
    end

    NetworkMgr:queryNetworkState()
    local complete_callback = function()
        NetworkMgr:queryNetworkState()
        if refresh_callback then
            refresh_callback()
        end
    end
    if NetworkMgr.is_wifi_on and NetworkMgr.is_connected then
        NetworkMgr:toggleWifiOff(complete_callback, true)
    elseif NetworkMgr.is_wifi_on then
        NetworkMgr:promptWifi(complete_callback, nil, true)
    else
        NetworkMgr:toggleWifiOn(complete_callback, nil, true)
    end
end

local function showWifiNetworks(refresh_callback)
    if not Device:hasWifiToggle() then
        return
    end

    NetworkMgr:queryNetworkState()
    local complete_callback = function()
        NetworkMgr:queryNetworkState()
        if refresh_callback then
            refresh_callback()
        end
    end
    if NetworkMgr.is_wifi_on then
        NetworkMgr.wifi_toggle_long_press = true
        NetworkMgr:reconnectOrShowNetworkMenu(complete_callback, true)
    else
        NetworkMgr:toggleWifiOn(complete_callback, true, true)
    end
end

local ModeLeftContainer = LeftContainer:extend{
    visible_func = nil,
}

function ModeLeftContainer:isVisible()
    return self.visible_func == nil or self.visible_func()
end

function ModeLeftContainer:paintTo(bb, x, y)
    if self:isVisible() then
        return LeftContainer.paintTo(self, bb, x, y)
    end
end

function ModeLeftContainer:handleEvent(event)
    if self:isVisible() then
        return LeftContainer.handleEvent(self, event)
    end
    return false
end

local MetadataTabsTitleBar = OverlapGroup:extend{
    show_parent = nil,
    right_icon = nil,
    right_icon_tap_callback = function() end,
    right_icon_hold_callback = function() end,
}

function MetadataTabsTitleBar:init()
    self.show_parent = self.show_parent or self
    self.width = Screen:getWidth()
    self.icon_size = Screen:scaleBySize(DGENERIC_ICON_SIZE)
    self.button_padding = Screen:scaleBySize(5)
    self.tab_padding_h = Screen:scaleBySize(10)
    self.tab_padding_v = Screen:scaleBySize(5)
    self.tab_font_face = "smallinfofont"
    self.tab_font_size = 18
    self.tab_underline_height = Size.line.thick * 2
    self.status_padding_h = Screen:scaleBySize(7)
    self.status_gap = Screen:scaleBySize(3)
    self.titlebar_height = self.icon_size + self.button_padding * 2

    self.file_manager = self.file_manager or FileManager.instance
    local file_manager = self.file_manager
    local function measureTextWidth(candidates, padding_h)
        local face = Font:getFace(self.tab_font_face, self.tab_font_size)
        local width = 0
        for _, text in ipairs(candidates) do
            local widget = TextWidget:new{
                text = text,
                face = face,
            }
            width = math.max(width, widget:getSize().w)
            widget:free()
        end
        return width + 2 * padding_h
    end
    local function getTabWidth(text)
        local face = Font:getFace(self.tab_font_face, self.tab_font_size)
        local normal_widget = TextWidget:new{
            text = text,
            face = face,
            bold = false,
        }
        local bold_widget = TextWidget:new{
            text = text,
            face = face,
            bold = true,
        }
        local width = math.max(normal_widget:getSize().w, bold_widget:getSize().w) + 2 * self.tab_padding_h
        normal_widget:free()
        bold_widget:free()
        return width
    end
    local function makeTab(key, text, callback, hold_callback)
        local tab_width = getTabWidth(text)
        local button = Button:new{
            text = text,
            text_font_face = self.tab_font_face,
            text_font_size = self.tab_font_size,
            text_font_bold = false,
            width = tab_width,
            bordersize = 0,
            padding_h = self.tab_padding_h,
            padding_v = self.tab_padding_v,
            callback = callback,
            hold_callback = hold_callback,
            show_parent = self.show_parent,
        }
        local line = LineWidget:new{
            style = "none",
            dimen = Geom:new{ w = tab_width, h = self.tab_underline_height },
            background = Blitbuffer.COLOR_BLACK,
        }
        local tab = VerticalGroup:new{
            align = "center",
            button,
            line,
        }
        tab.key = key
        tab.button = button
        tab.line = line
        return tab
    end

    self.books_tab = makeTab("books", _("Books"), function()
        openBooks(file_manager)
    end, function()
        file_manager:onShowFolderMenu()
    end)
    self.series_tab = makeTab("series", _("Series"), function()
        browseByMetadata(file_manager, "series")
    end)
    self.authors_tab = makeTab("authors", _("Authors"), function()
        browseByMetadata(file_manager, "author")
    end)
    self.books_button = self.books_tab.button
    self.series_button = self.series_tab.button
    self.authors_button = self.authors_tab.button
    self.tab_label_height = self.books_button.label_container.dimen.h
    local function getStatusWidths()
        local powerd = Device:getPowerDevice()
        local max_level = Device:hasAuxBattery() and 200 or 100
        local battery_candidates = {
            max_level .. "%",
        }
        if Device:hasBattery() then
            table.insert(battery_candidates, powerd:getBatterySymbol(true, false, 100) .. max_level .. "%")
            table.insert(battery_candidates, powerd:getBatterySymbol(false, true, 100) .. max_level .. "%")
            table.insert(battery_candidates, powerd:getBatterySymbol(false, false, 100) .. max_level .. "%")
        end

        local icon_width = measureTextWidth({
            NIGHT_MODE_SYMBOL,
            FRONTLIGHT_SYMBOL,
            FRONTLIGHT_OFF_SYMBOL,
            WIFI_ON_SYMBOL,
            WIFI_OFF_SYMBOL,
        }, self.status_padding_h)
        return {
            night_mode = icon_width,
            frontlight = icon_width,
            wifi = icon_width,
            battery = measureTextWidth(battery_candidates, self.status_padding_h),
        }
    end

    self.tabs_group = HorizontalGroup:new{
        align = "bottom",
        allow_mirroring = false,
        self.books_tab,
        self.series_tab,
        self.authors_tab,
    }
    local tabs_size = self.tabs_group:getSize()
    self.titlebar_height = math.max(self.titlebar_height, tabs_size.h)
    local titlebar_body_height = self.titlebar_height
    self.dimen = Geom:new{
        x = 0,
        y = 0,
        w = self.width,
        h = titlebar_body_height,
    }

    self.tabs_stack = VerticalGroup:new{
        align = "left",
        VerticalSpan:new{ width = titlebar_body_height - tabs_size.h },
        self.tabs_group,
    }
    self.tabs_container = ModeLeftContainer:new{
        allow_mirroring = false,
        dimen = Geom:new{
            x = 0,
            y = 0,
            w = self.width,
            h = titlebar_body_height,
        },
        visible_func = function()
            return self.back_title_info == nil
        end,
        self.tabs_stack,
    }
    table.insert(self, self.tabs_container)
    self:updateSelectedTab(false)

    local status_widths = getStatusWidths()
    self.night_mode_width = status_widths.night_mode
    self.frontlight_width = status_widths.frontlight
    self.wifi_width = status_widths.wifi
    self.battery_width = status_widths.battery
    self.status_width = self.night_mode_width + self.frontlight_width + self.wifi_width + self.battery_width + 3 * self.status_gap
    self.night_mode_button = Button:new{
        text = NIGHT_MODE_SYMBOL,
        text_font_face = self.tab_font_face,
        text_font_size = self.tab_font_size,
        text_font_bold = false,
        width = self.night_mode_width,
        height = self.tab_label_height,
        bordersize = 0,
        padding_h = self.status_padding_h,
        padding_v = self.tab_padding_v,
        callback = function()
            UIManager:broadcastEvent(Event:new("ToggleNightMode"))
        end,
        show_parent = self.show_parent,
    }
    self.frontlight_button = Button:new{
        text = getFrontlightText(),
        text_font_face = self.tab_font_face,
        text_font_size = self.tab_font_size,
        text_font_bold = false,
        width = self.frontlight_width,
        height = self.tab_label_height,
        bordersize = 0,
        padding_h = self.status_padding_h,
        padding_v = self.tab_padding_v,
        callback = function()
            if Device:hasFrontlight() then
                UIManager:broadcastEvent(Event:new("ShowFlDialog"))
            end
        end,
        hold_callback = function()
            if Device:hasFrontlight() then
                UIManager:broadcastEvent(Event:new("ToggleFrontlight"))
                self:refreshStatusIndicators()
            end
        end,
        show_parent = self.show_parent,
    }
    self.wifi_button = Button:new{
        text = getWifiText(),
        text_font_face = self.tab_font_face,
        text_font_size = self.tab_font_size,
        text_font_bold = false,
        width = self.wifi_width,
        height = self.tab_label_height,
        bordersize = 0,
        padding_h = self.status_padding_h,
        padding_v = self.tab_padding_v,
        callback = function()
            toggleWifi(function()
                self:updateStatusIndicators()
            end)
        end,
        hold_callback = function()
            showWifiNetworks(function()
                self:updateStatusIndicators()
            end)
        end,
        show_parent = self.show_parent,
    }
    self.battery_button = Button:new{
        text = getBatteryText(),
        text_font_face = self.tab_font_face,
        text_font_size = self.tab_font_size,
        text_font_bold = false,
        width = self.battery_width,
        height = self.tab_label_height,
        bordersize = 0,
        padding_h = self.status_padding_h,
        padding_v = self.tab_padding_v,
        hold_callback = function()
            showBatteryInfo()
            self:updateStatusIndicators()
        end,
        show_parent = self.show_parent,
    }
    self.status_row = HorizontalGroup:new{
        align = "bottom",
        allow_mirroring = false,
        self.night_mode_button,
        HorizontalSpan:new{ width = self.status_gap },
        self.frontlight_button,
        HorizontalSpan:new{ width = self.status_gap },
        self.wifi_button,
        HorizontalSpan:new{ width = self.status_gap },
        self.battery_button,
    }
    self.status_line = LineWidget:new{
        style = "none",
        dimen = Geom:new{ w = self.status_width, h = self.tab_underline_height },
        background = Blitbuffer.COLOR_BLACK,
    }
    self.status_group = VerticalGroup:new{
        align = "right",
        self.status_row,
        self.status_line,
    }
    self.status_stack = VerticalGroup:new{
        align = "right",
        VerticalSpan:new{ width = titlebar_body_height - tabs_size.h },
        self.status_group,
    }
    self.status_container = RightContainer:new{
        allow_mirroring = false,
        dimen = Geom:new{
            x = 0,
            y = 0,
            w = self.width,
            h = titlebar_body_height,
        },
        self.status_stack,
    }
    table.insert(self, self.status_container)

    self.back_title_width = self.width - self.status_width - self.tab_padding_h
    self.back_button = Button:new{
        text = "",
        align = "left",
        text_font_face = self.tab_font_face,
        text_font_size = self.tab_font_size,
        text_font_bold = true,
        width = self.back_title_width,
        height = self.tab_label_height,
        bordersize = 0,
        padding_h = self.tab_padding_h,
        padding_v = self.tab_padding_v,
        callback = function()
            self:onBackTitleTap()
        end,
        show_parent = self.show_parent,
    }
    self.back_chevron_button = Button:new{
        icon = "chevron.left",
        icon_width = self.tab_label_height,
        icon_height = self.tab_label_height,
        height = self.tab_label_height,
        bordersize = 0,
        padding_h = 0,
        padding_v = self.tab_padding_v,
        callback = function()
            self:onBackTitleTap()
        end,
        show_parent = self.show_parent,
    }
    self.back_button.width = self.back_title_width - self.back_chevron_button:getSize().w
    self.back_button:init()
    self.back_row = HorizontalGroup:new{
        align = "bottom",
        allow_mirroring = false,
        self.back_chevron_button,
        self.back_button,
    }
    self.back_title_line = LineWidget:new{
        style = "none",
        dimen = Geom:new{ w = self.back_title_width, h = self.tab_underline_height },
        background = Blitbuffer.COLOR_BLACK,
    }
    self.back_title_group = VerticalGroup:new{
        align = "left",
        self.back_row,
        self.back_title_line,
    }
    self.back_stack = VerticalGroup:new{
        align = "left",
        VerticalSpan:new{ width = titlebar_body_height - tabs_size.h },
        self.back_title_group,
    }
    self.back_container = ModeLeftContainer:new{
        allow_mirroring = false,
        dimen = Geom:new{
            x = 0,
            y = 0,
            w = self.width,
            h = titlebar_body_height,
        },
        visible_func = function()
            return self.back_title_info ~= nil
        end,
        self.back_stack,
    }
    table.insert(self, self.back_container)
    self:updateBackTitle(false)

    self.bottom_line = VerticalGroup:new{
        VerticalSpan:new{ width = titlebar_body_height },
        LineWidget:new{
            dimen = Geom:new{ w = self.width, h = Size.line.thin },
            background = Blitbuffer.COLOR_BLACK,
        },
    }
    table.insert(self, self.bottom_line)
    self.titlebar_height = self.titlebar_height + Size.line.thin
    self.dimen.h = self.titlebar_height

    -- Compatibility for callers that anchor popups on title_bar.left_button.image.dimen.
    self.left_button = {
        image = {
            dimen = self.books_button[1].dimen or self.books_button.dimen,
        },
    }

    OverlapGroup.init(self)
end

function MetadataTabsTitleBar:updateBackTitle(refresh)
    local file_manager = self.file_manager or FileManager.instance
    local back_title_info = getBackTitleBarInfo(file_manager)
    local title = back_title_info and back_title_info.title or nil
    if self.back_title == title then
        return
    end

    self.back_title_info = back_title_info
    self.back_title = title
    self.back_button:setText(title or "", self.back_button.width)

    if refresh ~= false then
        UIManager:setDirty(self.show_parent, "ui", self.dimen)
    end
end

function MetadataTabsTitleBar:onBackTitleTap()
    local file_manager = self.file_manager or FileManager.instance
    local file_chooser = file_manager and file_manager.file_chooser
    local back_title_info = getBackTitleBarInfo(file_manager)
    if file_chooser and back_title_info then
        file_chooser:changeToPath(back_title_info.parent_path, back_title_info.current_path)
    end
end

function MetadataTabsTitleBar:updateStatusIndicators(refresh)
    if not self.battery_button then
        return
    end

    local battery_text = getBatteryText()
    local wifi_text = getWifiText()
    local frontlight_text = getFrontlightText()
    if self.battery_text == battery_text
            and self.wifi_text == wifi_text
            and self.frontlight_text == frontlight_text then
        return
    end

    self.battery_text = battery_text
    self.wifi_text = wifi_text
    self.frontlight_text = frontlight_text
    self.battery_button:setText(battery_text, self.battery_width)
    self.wifi_button:setText(wifi_text, self.wifi_width)
    self.frontlight_button:setText(frontlight_text, self.frontlight_width)
    if refresh ~= false then
        UIManager:setDirty(self.show_parent, "ui", self.dimen)
    end
end

function MetadataTabsTitleBar:refreshStatusIndicators()
    self:updateStatusIndicators(false)
    UIManager:setDirty(self.show_parent, "ui", self.dimen)
end

function MetadataTabsTitleBar:setTabSelected(tab, selected)
    tab.line.style = selected and "solid" or "none"
    if tab.button.label_widget and tab.button.label_widget.bold ~= selected then
        tab.button.label_widget.bold = selected
        tab.button.label_widget:free()
    end
end

function MetadataTabsTitleBar:updateSelectedTab(refresh)
    local file_manager = self.file_manager or FileManager.instance
    local selected_tab_key = getSelectedTabKey(file_manager)
    if selected_tab_key == self.selected_tab_key then
        return
    end

    self.selected_tab_key = selected_tab_key
    for _, tab in ipairs({ self.books_tab, self.series_tab, self.authors_tab }) do
        self:setTabSelected(tab, tab.key == selected_tab_key)
    end

    if refresh ~= false then
        UIManager:setDirty(self.show_parent, "ui", self.dimen)
    end
end

function MetadataTabsTitleBar:paintTo(bb, x, y)
    self.dimen.x = x
    self.dimen.y = y
    self:updateBackTitle(false)
    self:updateSelectedTab(false)
    self:updateStatusIndicators(false)
    OverlapGroup.paintTo(self, bb, x, y)
    if self.books_button and self.books_button[1] and self.books_button[1].dimen then
        self.left_button.image.dimen = self.books_button[1].dimen
    end
end

function MetadataTabsTitleBar:getHeight()
    return self.titlebar_height
end

function MetadataTabsTitleBar:setTitle()
end

function MetadataTabsTitleBar:setSubTitle()
    self:updateBackTitle()
    self:updateSelectedTab()
    self:updateStatusIndicators()
end

function MetadataTabsTitleBar:setLeftIcon()
end

function MetadataTabsTitleBar:setRightIcon()
    self:updateStatusIndicators()
end

function MetadataTabsTitleBar:onNetworkConnected()
    NetworkMgr:queryNetworkState()
    self:updateStatusIndicators()
end

function MetadataTabsTitleBar:onNetworkDisconnected()
    NetworkMgr:queryNetworkState()
    self:updateStatusIndicators()
end

function MetadataTabsTitleBar:onNetworkDisconnecting()
    NetworkMgr.is_wifi_on = false
    self:updateStatusIndicators()
end

function MetadataTabsTitleBar:onFrontlightStateChanged()
    self:refreshStatusIndicators()
    UIManager:scheduleIn(0.2, self.refreshStatusIndicators, self)
    UIManager:scheduleIn(1, self.refreshStatusIndicators, self)
end

function MetadataTabsTitleBar:generateHorizontalLayout()
    return {
        {
            self.back_button,
            self.books_button,
            self.series_button,
            self.authors_button,
            self.night_mode_button,
            self.frontlight_button,
            self.wifi_button,
            self.battery_button,
        },
    }
end

function MetadataTabsTitleBar:generateVerticalLayout()
    return {
        { self.back_button },
        { self.books_button },
        { self.series_button },
        { self.authors_button },
        { self.night_mode_button },
        { self.frontlight_button },
        { self.wifi_button },
        { self.battery_button },
    }
end

local function findTitleBarUpvalue(func, seen)
    if type(func) ~= "function" then
        return
    end
    seen = seen or {}
    if seen[func] then
        return
    end
    seen[func] = true

    local nested = {}
    local idx = 1
    while true do
        local name, value = debug.getupvalue(func, idx)
        if not name then
            break
        end
        if name == "TitleBar" then
            return func, idx, value
        elseif type(value) == "function" then
            table.insert(nested, value)
        end
        idx = idx + 1
    end

    for _, nested_func in ipairs(nested) do
        local target_func, target_idx, original = findTitleBarUpvalue(nested_func, seen)
        if target_func then
            return target_func, target_idx, original
        end
    end
end

local FileChooser_genItemTable = FileChooser.genItemTable
FileChooser.genItemTable = function(self, dirs, files, path)
    local item_table = FileChooser_genItemTable(self, dirs, files, path)
    local leaf_info = getMetadataLeafInfo(path)
    if leaf_info then
        local first_item = item_table[1]
        if first_item and first_item.is_go_up and first_item.path == leaf_info.parent_path then
            table.remove(item_table, 1)
            self.path_items[path] = nil
        end
    end
    return item_table
end

local FileManager_setupLayout = FileManager.setupLayout
FileManager.setupLayout = function(self, ...)
    local target_func, titlebar_idx, original_titlebar = findTitleBarUpvalue(FileManager_setupLayout)
    if target_func and titlebar_idx then
        MetadataTabsTitleBar.file_manager = self
        debug.setupvalue(target_func, titlebar_idx, MetadataTabsTitleBar)
        local ok, ret = pcall(FileManager_setupLayout, self, ...)
        debug.setupvalue(target_func, titlebar_idx, original_titlebar)
        MetadataTabsTitleBar.file_manager = nil
        if not ok then
            error(ret)
        end
        return ret
    end
    return FileManager_setupLayout(self, ...)
end
