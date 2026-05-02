-- File browser metadata tabs title bar
-- Version: 1.0.0
-- Adds Books / Series / Authors tabs to the file manager title bar.

local Blitbuffer = require("ffi/blitbuffer")
local Button = require("ui/widget/button")
local Device = require("device")
local FileManager = require("apps/filemanager/filemanager")
local Font = require("ui/font")
local Geom = require("ui/geometry")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local IconButton = require("ui/widget/iconbutton")
local LeftContainer = require("ui/widget/container/leftcontainer")
local LineWidget = require("ui/widget/linewidget")
local OverlapGroup = require("ui/widget/overlapgroup")
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

local function getVirtualBaseDir(file_manager)
    local path = file_manager.file_chooser and file_manager.file_chooser.path
    local root_start = path and path:find("/" .. VIRTUAL_ROOT_SYMBOL, 1, true)
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
    local root_start, root_end
    if path then
        root_start, root_end = path:find("/" .. VIRTUAL_ROOT_SYMBOL, 1, true)
    end
    if not root_start then
        return "books"
    end

    for fragment in path:sub(root_end + 1):gmatch("[^/]+") do
        if fragment == AUTHOR_SYMBOL then
            return "authors"
        elseif fragment == SERIES_SYMBOL then
            return "series"
        elseif fragment ~= "" then
            break
        end
    end

    return "books"
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
    self.tab_underline_height = Size.line.thick
    self.titlebar_height = self.icon_size + self.button_padding * 2

    self.file_manager = self.file_manager or FileManager.instance
    local file_manager = self.file_manager
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
    self.tabs_container = LeftContainer:new{
        allow_mirroring = false,
        dimen = Geom:new{
            x = 0,
            y = 0,
            w = self.width,
            h = titlebar_body_height,
        },
        self.tabs_stack,
    }
    table.insert(self, self.tabs_container)
    self:updateSelectedTab(false)

    self.right_button = IconButton:new{
        icon = self.right_icon,
        width = self.icon_size,
        height = self.icon_size,
        padding = self.button_padding,
        padding_left = 2 * self.icon_size,
        padding_bottom = self.icon_size,
        overlap_align = "right",
        callback = self.right_icon_tap_callback,
        hold_callback = self.right_icon_hold_callback,
        show_parent = self.show_parent,
    }
    table.insert(self, self.right_button)

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
    self:updateSelectedTab(false)
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
    self:updateSelectedTab()
end

function MetadataTabsTitleBar:setLeftIcon()
end

function MetadataTabsTitleBar:setRightIcon(icon)
    if self.right_button then
        self.right_button:setIcon(icon, self.icon_size)
        UIManager:setDirty(self.show_parent, "ui", self.dimen)
    end
end

function MetadataTabsTitleBar:generateHorizontalLayout()
    return {
        {
            self.books_button,
            self.series_button,
            self.authors_button,
            self.right_button,
        },
    }
end

function MetadataTabsTitleBar:generateVerticalLayout()
    return {
        { self.books_button },
        { self.series_button },
        { self.authors_button },
        { self.right_button },
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
