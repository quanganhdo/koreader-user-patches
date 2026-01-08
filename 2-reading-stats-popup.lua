--[[
Reading Stats Popup - Kobo-style reading statistics overlay
Shows: This Chapter (time left), Next Chapter (time), This Book (progress, pages read, time spent/left),
       Pace (avg time/day, pages/minute), Days (reading/to go)
Version: 1.0.2
Updates: https://github.com/quanganhdo/koreader-user-patches
]]--

local Blitbuffer = require("ffi/blitbuffer")
local CenterContainer = require("ui/widget/container/centercontainer")
local DataStorage = require("datastorage")
local Device = require("device")
local Dispatcher = require("dispatcher")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local InputContainer = require("ui/widget/container/inputcontainer")
local LeftContainer = require("ui/widget/container/leftcontainer")
local LineWidget = require("ui/widget/linewidget")
local Math = require("optmath")
local MovableContainer = require("ui/widget/container/movablecontainer")
local SQ3 = require("lua-ljsqlite3/init")
local Size = require("ui/size")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local util = require("util")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local Screen = Device.screen
local gettext = require("gettext")
local ReaderUI = require("apps/reader/readerui")

-- User patch localization: add your language overrides here.
local PATCH_L10N = {
    en = {
        ["THIS CHAPTER"] = "THIS CHAPTER",
        ["NEXT CHAPTER"] = "NEXT CHAPTER",
        ["THIS BOOK"] = "THIS BOOK",
        ["PACE"] = "PACE",
        ["Reading statistics: book overview"] = "Reading statistics: book overview",
        ["to go"] = "to go",
        ["to read"] = "to read",
        ["read"] = "read",
        ["per day"] = "per day",
        ["minute"] = "minute",
        ["minutes"] = "minutes",
        ["hour"] = "hour",
        ["hours"] = "hours",
        ["week reading"] = "week reading",
        ["weeks reading"] = "weeks reading",
        ["month reading"] = "month reading",
        ["months reading"] = "months reading",
        ["day reading"] = "day reading",
        ["days reading"] = "days reading",
        ["week to go"] = "week to go",
        ["weeks to go"] = "weeks to go",
        ["month to go"] = "month to go",
        ["months to go"] = "months to go",
        ["day to go"] = "day to go",
        ["days to go"] = "days to go",
        ["page read"] = "page read",
        ["pages read"] = "pages read",
        ["page per minute"] = "page per minute",
        ["pages per minute"] = "pages per minute",
    },
    vi = {
        ["THIS CHAPTER"] = "CHƯƠNG NÀY",
        ["NEXT CHAPTER"] = "CHƯƠNG TIẾP",
        ["THIS BOOK"] = "SÁCH NÀY",
        ["PACE"] = "NHỊP ĐỌC",
        ["Reading statistics: book overview"] = "Thống kê đọc: tổng quan sách",
        ["to go"] = "sẽ xong",
        ["to read"] = "để đọc",
        ["read"] = "đã đọc",
        ["per day"] = "mỗi ngày",
        ["minute"] = "phút",
        ["minutes"] = "phút",
        ["hour"] = "giờ",
        ["hours"] = "giờ",
        ["week reading"] = "tuần đã đọc",
        ["weeks reading"] = "tuần đã đọc",
        ["month reading"] = "tháng đã đọc",
        ["months reading"] = "tháng đã đọc",
        ["day reading"] = "ngày đã đọc",
        ["days reading"] = "ngày đã đọc",
        ["week to go"] = "tuần sẽ xong",
        ["weeks to go"] = "tuần sẽ xong",
        ["month to go"] = "tháng sẽ xong",
        ["months to go"] = "tháng sẽ xong",
        ["day to go"] = "ngày sẽ xong",
        ["days to go"] = "ngày sẽ xong",
        ["page read"] = "trang đã đọc",
        ["pages read"] = "trang đã đọc",
        ["page per minute"] = "trang mỗi phút",
        ["pages per minute"] = "trang mỗi phút",
    },
}

local function l10nLookup(msg)
    local lang = "en"
    if G_reader_settings and G_reader_settings.readSetting then
        lang = G_reader_settings:readSetting("language") or "en"
    end
    local lang_base = lang:match("^([a-z]+)") or lang
    local map = PATCH_L10N[lang] or PATCH_L10N[lang_base] or PATCH_L10N.en or {}
    return map[msg]
end

local function _(msg)
    return l10nLookup(msg) or gettext(msg)
end

local function N_(singular, plural, n)
    local singular_override = l10nLookup(singular)
    local plural_override = l10nLookup(plural)
    if singular_override or plural_override then
        if n == 1 then
            return singular_override or plural_override
        end
        return plural_override or singular_override
    end
    return gettext.ngettext(singular, plural, n)
end

local TIME_FORMAT_SETTING = "userpatch.anh.reading_stats_time_format"
local TIME_FORMAT_NICKEL = "nickel"
local TIME_FORMAT_XHYM = "xhym"

local function getTimeFormatSetting()
    if G_reader_settings and G_reader_settings.readSetting then
        return G_reader_settings:readSetting(TIME_FORMAT_SETTING) or TIME_FORMAT_NICKEL
    end
    return TIME_FORMAT_NICKEL
end

local function setTimeFormatSetting(value)
    if G_reader_settings and G_reader_settings.saveSetting then
        G_reader_settings:saveSetting(TIME_FORMAT_SETTING, value)
        if G_reader_settings.flush then
            G_reader_settings:flush()
        end
    end
end

local stats_db_path = DataStorage:getSettingsDir() .. "/statistics.sqlite3"

local function emptyValue()
    return { value = "", unit = "" }
end

local function formatCount(value)
    if value == nil then return "" end
    return util.getFormattedSize(value)
end

local function formatFraction(numerator, denominator)
    return string.format("%s/%s", formatCount(numerator), formatCount(denominator))
end

-- Returns { value = "...", unit = "..." } for display.
-- Uses the same minute-rounding behavior as the stock footer.
local function formatTimeHuman(seconds)
    if not seconds or seconds ~= seconds then
        return emptyValue()
    end

    if seconds <= 0 then
        return { value = formatCount(0), unit = N_("minute", "minutes", 0) }
    end

    local rounded_minutes = Math.round(seconds / 60)
    if rounded_minutes <= 0 then
        return { value = formatCount(0), unit = N_("minute", "minutes", 0) }
    elseif rounded_minutes < 60 then
        return { value = formatCount(rounded_minutes), unit = N_("minute", "minutes", rounded_minutes) }
    end

    local h = rounded_minutes / 60
    if h < 10 then
        return { value = string.format("%.1f", h), unit = N_("hour", "hours", h) }
    else
        return { value = string.format("%.0f", h), unit = N_("hour", "hours", h) }
    end
end

local function formatTimeXhym(seconds)
    if not seconds or seconds ~= seconds then
        return emptyValue()
    end

    local total_minutes = Math.round(seconds / 60)
    if total_minutes <= 0 then
        return { value = "0m", unit = "" }
    end

    local hours = math.floor(total_minutes / 60)
    local minutes = total_minutes % 60
    if hours > 0 then
        return { value = string.format("%dh%02dm", hours, minutes), unit = "" }
    end
    return { value = string.format("%dm", minutes), unit = "" }
end

local function selectTimeFormatter()
    if getTimeFormatSetting() == TIME_FORMAT_XHYM then
        return formatTimeXhym
    end
    return formatTimeHuman
end

local function dayCountLabel(kind, unit, count)
    if kind == "reading" then
        if unit == "week" then return N_("week reading", "weeks reading", count) end
        if unit == "month" then return N_("month reading", "months reading", count) end
        return N_("day reading", "days reading", count)
    elseif kind == "to_go" then
        if unit == "week" then return N_("week to go", "weeks to go", count) end
        if unit == "month" then return N_("month to go", "months to go", count) end
        return N_("day to go", "days to go", count)
    end
    return ""
end

local function humanizeDayCount(days, kind)
    local count = tonumber(days) or 0
    local unit = "day"
    if count >= 60 then
        unit = "month"
        count = math.floor((count + 15) / 30)
    elseif count >= 14 then
        unit = "week"
        count = math.floor((count + 3) / 7)
    end
    if count < 0 then count = 0 end
    return { value = formatCount(count), unit = dayCountLabel(kind, unit, count) }
end

local function getTotalDaysForBook(book_id)
    if not book_id then return end
    local conn = SQ3.open(stats_db_path)
    if not conn then return end
    -- Count distinct local dates for this book.
    local sql = [[
        SELECT count(*)
        FROM   (
                    SELECT strftime('%%Y-%%m-%%d', start_time, 'unixepoch', 'localtime') AS dates
                    FROM   page_stat
                    WHERE  id_book = %d
                    GROUP  BY dates
               );
    ]]
    local total_days = conn:rowexec(string.format(sql, book_id))
    conn:close()
    return total_days and tonumber(total_days) or nil
end

local function getChapterPagesLeft(ui, pageno)
    if not ui or not ui.toc then return end
    local pages_left = ui.toc:getChapterPagesLeft(pageno, true)
    if pages_left == nil and ui.document then
        pages_left = ui.document:getTotalPagesLeft(pageno)
    end
    return pages_left
end

local function getBookProgressData(ui)
    if not ui or not ui.document then return end
    local current_page = ui:getCurrentPage()
    local total_pages = ui.document:getPageCount()
    if not current_page or not total_pages or total_pages == 0 then return end

    local pagemap = ui.pagemap and ui.pagemap:wantsPageLabels()
    local current_page_idx
    local total_pages_idx
    if pagemap then
        local _, page_idx, pages_idx = ui.pagemap:getCurrentPageLabel()
        current_page_idx = page_idx
        total_pages_idx = pages_idx
    elseif ui.document:hasHiddenFlows() then
        local flow = ui.document:getPageFlow(current_page)
        current_page = ui.document:getPageNumberInFlow(current_page)
        total_pages = ui.document:getTotalPagesInFlow(flow)
    end

    return {
        current_page = current_page,
        total_pages = total_pages,
        current_page_idx = current_page_idx,
        total_pages_idx = total_pages_idx,
        pagemap = pagemap,
    }
end

local function getBookPagesLeft(ui)
    local progress = getBookProgressData(ui)
    if not progress then return end
    return progress.total_pages - progress.current_page
end

local function getBookProgressPercent(ui)
    local progress = getBookProgressData(ui)
    if not progress then return end
    if progress.pagemap and progress.current_page_idx and progress.total_pages_idx and progress.total_pages_idx > 0 then
        return Math.round(100 * progress.current_page_idx / progress.total_pages_idx)
    end
    return Math.round(100 * progress.current_page / progress.total_pages)
end

local function getBookProgressCounts(ui)
    local progress = getBookProgressData(ui)
    if not progress then return end
    if progress.pagemap and progress.current_page_idx and progress.total_pages_idx and progress.total_pages_idx > 0 then
        return progress.current_page_idx, progress.total_pages_idx
    end
    return progress.current_page, progress.total_pages
end

local function withBookStats(stats_plugin, fn)
    if not stats_plugin or not stats_plugin.id_curr_book then return end
    return fn(stats_plugin)
end

local function getSerifFace(font_name, fallback_name, size)
    return Font:getFace(font_name, size) or Font:getFace(fallback_name, size)
end

local function buildSerifFonts()
    local label_size = Font.sizemap.x_smallinfofont
    return {
        section = Font:getFace("x_smallinfofont"),
        value = getSerifFace("NotoSerif-Bold.ttf", "tfont", 32),
        label = getSerifFace("NotoSerif-Regular.ttf", "x_smallinfofont", label_size),
    }
end

local function buildLayout(screen_w, padding_h, column_gap)
    local separator_width = 2 * column_gap + Size.line.medium
    local col_width = math.floor((screen_w - 2 * padding_h - separator_width) / 2)
    return {
        full_width = screen_w,
        padding_h = padding_h,
        column_gap = column_gap,
        separator_width = separator_width,
        col_width = col_width,
    }
end

local function buildColumnSeparator(column_gap, height)
    local v_padding = Size.padding.default
    return HorizontalGroup:new{
        HorizontalSpan:new{ width = column_gap },
        VerticalGroup:new{
            align = "center",
            VerticalSpan:new{ height = v_padding },
            LineWidget:new{
                dimen = Geom:new{ w = Size.line.medium, h = height - 2 * v_padding },
                background = Blitbuffer.COLOR_GRAY,
            },
            VerticalSpan:new{ height = v_padding },
        },
        HorizontalSpan:new{ width = column_gap },
    }
end

local function buildSectionHeader(font_section, text, width, left_padding)
    left_padding = left_padding or Size.padding.large
    local text_widget = TextWidget:new{ text = text, face = font_section }
    return FrameContainer:new{
        background = Blitbuffer.COLOR_GRAY_E,
        bordersize = 0,
        padding_top = Size.padding.small,
        padding_bottom = Size.padding.small,
        padding_left = left_padding,
        padding_right = 0,
        LeftContainer:new{
            dimen = Geom:new{ w = width - left_padding, h = text_widget:getSize().h },
            text_widget,
        },
    }
end

local function buildValueLine(font_value, font_label, col_width, time_data, label)
    if time_data.value == "" then
        return TextBoxWidget:new{
            text = time_data.unit,
            face = font_label,
            width = col_width,
            alignment = "left",
        }
    end

    local desc = time_data.unit
    if label and label ~= "" then
        if desc ~= "" then
            desc = desc .. " " .. label
        else
            desc = label
        end
    end
    local value_widget = TextWidget:new{ text = time_data.value, face = font_value }
    local value_width = value_widget:getSize().w
    local text_desc_width = col_width - value_width - Size.padding.large
    return HorizontalGroup:new{
        align = "center",
        value_widget,
        HorizontalSpan:new{ width = Size.padding.large },
        TextBoxWidget:new{
            text = desc,
            face = font_label,
            width = text_desc_width,
            alignment = "left",
        },
    }
end

local function fixedCol(widget, width, height)
    height = height or widget:getSize().h
    return LeftContainer:new{
        dimen = Geom:new{ w = width, h = height },
        widget,
    }
end

local function padded(padding_h, widget)
    return HorizontalGroup:new{
        HorizontalSpan:new{ width = padding_h },
        widget,
    }
end

local function shouldTrackTarget(target_mask, key)
    if not target_mask then
        return true
    end
    return target_mask[key] == true
end

local function buildTwoColRow(left_widget, right_widget, layout, tap_targets, target_mask)
    local left_h = left_widget:getSize().h
    local right_h = right_widget:getSize().h
    local row_height = math.max(left_h, right_h)
    local left_col = fixedCol(left_widget, layout.col_width, row_height)
    local right_col = fixedCol(right_widget, layout.col_width, row_height)
    if tap_targets then
        if shouldTrackTarget(target_mask, "left") then
            table.insert(tap_targets, left_col)
        end
        if shouldTrackTarget(target_mask, "right") then
            table.insert(tap_targets, right_col)
        end
    end
    return HorizontalGroup:new{
        align = "center",
        left_col,
        buildColumnSeparator(layout.column_gap, row_height),
        right_col,
    }
end

local function buildChapterHeaders(font_section, layout)
    -- Match header widths to the two columns below.
    local left_width = layout.padding_h + layout.col_width + math.floor(layout.separator_width / 2)
    local right_width = layout.full_width - left_width
    local next_chapter_padding = math.ceil(layout.separator_width / 2)
    return HorizontalGroup:new{
        align = "center",
        buildSectionHeader(font_section, _("THIS CHAPTER"), left_width),
        buildSectionHeader(font_section, _("NEXT CHAPTER"), right_width, next_chapter_padding),
    }
end

local function addSectionWithRow(sections, header_widget, row, layout)
    table.insert(sections, header_widget)
    table.insert(sections, VerticalSpan:new{ height = Size.padding.default })
    table.insert(sections, padded(layout.padding_h, row))
    table.insert(sections, VerticalSpan:new{ height = Size.padding.large })
    table.insert(sections, LineWidget:new{
        dimen = Geom:new{ w = layout.full_width, h = Size.line.medium },
        background = Blitbuffer.COLOR_BLACK,
    })
end

local function buildSections(stats, fonts, layout, tap_targets)
    local function valueLine(time_data, label)
        return buildValueLine(fonts.value, fonts.label, layout.col_width, time_data, label)
    end

    local chapter_val1 = valueLine(stats.chapter_time_left, _("to go"))
    local chapter_val2 = valueLine(stats.next_chapter_time, _("to read"))
    local progress_label = stats.book_progress.value ~= "" and _("read") or ""
    local book_progress = valueLine(stats.book_progress, progress_label)
    local book_pages_read = valueLine(stats.book_pages_read, "")
    local book_col1 = valueLine(stats.book_time_spent, _("read"))
    local book_col2 = valueLine(stats.book_time_left, _("to go"))
    local pace_col1 = valueLine(stats.avg_time_per_day, _("per day"))
    local pace_col2 = valueLine(stats.pages_per_minute, "")
    local days_col1 = valueLine(stats.days_reading, "")
    local days_col2 = valueLine(stats.days_to_go, "")

    local book_progress_row = buildTwoColRow(book_progress, book_pages_read, layout)
    local book_row = buildTwoColRow(book_col1, book_col2, layout, tap_targets)
    local pace_row = buildTwoColRow(pace_col1, pace_col2, layout, tap_targets, { left = true })
    local days_row = buildTwoColRow(days_col1, days_col2, layout)
    local chapter_values = buildTwoColRow(chapter_val1, chapter_val2, layout, tap_targets)
    local chapter_headers = buildChapterHeaders(fonts.section, layout)

    local sections = VerticalGroup:new{
        align = "left",
    }

    addSectionWithRow(sections, chapter_headers, chapter_values, layout)
    addSectionWithRow(
        sections,
        buildSectionHeader(fonts.section, _("THIS BOOK"), layout.full_width),
        VerticalGroup:new{
            align = "center",
            book_progress_row,
            VerticalSpan:new{ height = Size.padding.default },
            book_row,
        },
        layout
    )

    table.insert(sections, buildSectionHeader(fonts.section, _("PACE"), layout.full_width))
    table.insert(sections, VerticalSpan:new{ height = Size.padding.default })
    table.insert(sections, padded(layout.padding_h, days_row))
    table.insert(sections, VerticalSpan:new{ height = Size.padding.default })
    table.insert(sections, padded(layout.padding_h, pace_row))
    table.insert(sections, VerticalSpan:new{ height = Size.padding.default })
    table.insert(sections, LineWidget:new{
        dimen = Geom:new{ w = layout.full_width, h = Size.line.medium },
        background = Blitbuffer.COLOR_BLACK,
    })

    return sections
end

Dispatcher:registerAction("reading_stats_popup", {
    category = "none",
    event = "ShowReadingStatsPopup",
    title = _("Reading statistics: book overview"),
    reader = true,
})

local ReadingStatsPopup = InputContainer:extend{
    modal = true,
    ui = nil,
    width = nil,
    height = nil,
}

function ReadingStatsPopup:init()
    local screen_w = Screen:getWidth()
    local screen_h = Screen:getHeight()
    local stats = self:gatherStats()
    local fonts = buildSerifFonts()
    local layout = buildLayout(screen_w, Size.padding.large, Screen:scaleBySize(20))
    local tap_targets = {}
    local sections = buildSections(stats, fonts, layout, tap_targets)

    self.popup_frame = FrameContainer:new{
        background = Blitbuffer.COLOR_WHITE,
        bordersize = 0,
        radius = 0,
        padding = 0,
        width = screen_w,
        sections,
    }

    self[1] = VerticalGroup:new{
        self.popup_frame,
    }

    self.time_cell_targets = tap_targets
    self.dimen = Geom:new{ w = screen_w, h = screen_h }

    if Device:isTouchDevice() then
        self.ges_events.TapClose = {
            GestureRange:new{
                ges = "tap",
                range = self.dimen,
            }
        }
    end
    if Device:hasKeys() then
        self.key_events.AnyKeyPressed = { { Device.input.group.Any } }
    end
end

-- Use callback-based setDirty so the dirty region matches popup_frame's final size.
function ReadingStatsPopup:onShow()
    UIManager:setDirty(self, function()
        return "ui", self.popup_frame.dimen
    end)
    return true
end

function ReadingStatsPopup:gatherStats()
    local formatTime = selectTimeFormatter()
    local zero_time = formatTime(0)
    local zero_pages_per_minute = { value = formatCount(0), unit = N_("page per minute", "pages per minute", 0) }
    local zero_days_reading = humanizeDayCount(0, "reading")
    local zero_days_to_go = humanizeDayCount(0, "to_go")
    local zero_progress = { value = formatCount(0) .. "%", unit = "" }
    local zero_pages_read = { value = formatCount(0), unit = N_("page read", "pages read", 0) }
    local stats = {
        chapter_time_left = zero_time,
        next_chapter_time = zero_time,
        book_time_left = zero_time,
        book_time_spent = zero_time,
        book_progress = zero_progress,
        book_pages_read = zero_pages_read,
        avg_time_per_day = zero_time,
        pages_per_minute = zero_pages_per_minute,
        days_reading = zero_days_reading,
        days_to_go = zero_days_to_go,
    }

    local ui = self.ui
    if not ui then return stats end

    local stats_plugin = ui.statistics
    local toc = ui.toc
    local doc = ui.document
    local footer = ui.view and ui.view.footer

    if stats_plugin then
        stats_plugin:insertDB()
    end

    local pageno = footer and footer.pageno or 1
    local pages = footer and footer.pages or 1

    local progress_percent = getBookProgressPercent(ui)
    if progress_percent then
        stats.book_progress = { value = formatCount(progress_percent) .. "%", unit = "" }
    end
    local current_page_count, total_page_count = getBookProgressCounts(ui)
    if current_page_count and total_page_count and total_page_count > 0 then
        stats.book_pages_read = {
            value = formatFraction(current_page_count, total_page_count),
            unit = N_("page read", "pages read", current_page_count),
        }
    end

    local avg_time = stats_plugin and stats_plugin.avg_time
    local has_stats = avg_time and avg_time == avg_time  -- check not NaN

    local pages_left = nil
    if has_stats and toc then
        local chapter_pages_left = getChapterPagesLeft(ui, pageno)
        if chapter_pages_left and chapter_pages_left > 0 then
            local seconds = chapter_pages_left * avg_time
            stats.chapter_time_left = formatTime(seconds)
        end

        local next_chapter_start = toc:getNextChapter(pageno)
        if next_chapter_start then
            local chapter_after_next = toc:getNextChapter(next_chapter_start)
            local next_chapter_pages
            if chapter_after_next then
                next_chapter_pages = chapter_after_next - next_chapter_start
            else
                next_chapter_pages = pages - next_chapter_start + 1
            end
            -- Mirror footer semantics by excluding the chapter start page.
            next_chapter_pages = next_chapter_pages - 1
            if next_chapter_pages < 0 then
                next_chapter_pages = 0
            end
            if next_chapter_pages and next_chapter_pages > 0 then
                local seconds = next_chapter_pages * avg_time
                stats.next_chapter_time = formatTime(seconds)
            end
        else
            stats.next_chapter_time = emptyValue()
        end
    end

    if has_stats and doc then
        pages_left = getBookPagesLeft(ui)
        if pages_left and pages_left > 0 then
            local seconds = pages_left * avg_time
            stats.book_time_left = formatTime(seconds)
        end
    end

    if has_stats and avg_time > 0 then
        local ppm = 60 / avg_time
        local ppm_str
        if ppm >= 1 then
            ppm_str = string.format("%.1f", ppm)
        else
            ppm_str = string.format("%.2f", ppm)
        end
        stats.pages_per_minute = { value = ppm_str, unit = N_("page per minute", "pages per minute", ppm) }
    end

    withBookStats(stats_plugin, function(plugin)
        local total_time = 0
        if plugin.getPageTimeTotalStats then
            local read_pages, time_val = plugin:getPageTimeTotalStats(plugin.id_curr_book)
            total_time = tonumber(time_val) or 0
        end
        if total_time and total_time > 0 then
            stats.book_time_spent = formatTime(total_time)
        end
        local total_days = getTotalDaysForBook(plugin.id_curr_book)
        if total_days ~= nil then
            if total_time and total_time > 0 then
                local avg_per_day = total_time / total_days
                stats.avg_time_per_day = formatTime(avg_per_day)
            end

            stats.days_reading = humanizeDayCount(total_days, "reading")

            if has_stats and pages_left and pages_left > 0 and total_time > 0 then
                local time_to_read = pages_left * avg_time
                local avg_reading_per_day = total_time / total_days
                local days_to_finish = math.ceil(time_to_read / avg_reading_per_day)
                if time_to_read > 0 then
                    stats.days_to_go = humanizeDayCount(days_to_finish, "to_go")
                end
            end
        end
    end)

    return stats
end

function ReadingStatsPopup:toggleTimeFormat()
    local current = getTimeFormatSetting()
    local next_format = current == TIME_FORMAT_XHYM and TIME_FORMAT_NICKEL or TIME_FORMAT_XHYM
    setTimeFormatSetting(next_format)
    UIManager:close(self)
    UIManager:show(ReadingStatsPopup:new{ ui = self.ui })
    return true
end

function ReadingStatsPopup:onTapClose(arg, ges_ev)
    if ges_ev and ges_ev.pos and self.time_cell_targets then
        for _, target in ipairs(self.time_cell_targets) do
            if target.dimen and ges_ev.pos:intersectWith(target.dimen) then
                return self:toggleTimeFormat()
            end
        end
    end
    UIManager:close(self)
    return true
end

function ReadingStatsPopup:onAnyKeyPressed()
    UIManager:close(self)
    return true
end

function ReadingStatsPopup:onCloseWidget()
    UIManager:setDirty(nil, "ui")
end

function ReaderUI.onShowReadingStatsPopup(this)
    local popup = ReadingStatsPopup:new{
        ui = this,
    }
    UIManager:show(popup)
    return true
end
