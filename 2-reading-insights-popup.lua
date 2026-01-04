--[[
Reading Insights Popup - Reading stats and streaks overlay
Shows: Today (time/pages), Current/Best streaks, Year totals, Monthly chart, books list on tap
]]--

local Blitbuffer = require("ffi/blitbuffer")
local BottomContainer = require("ui/widget/container/bottomcontainer")
local Button = require("ui/widget/button")
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
local Size = require("ui/size")
local SQ3 = require("lua-ljsqlite3/init")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local Widget = require("ui/widget/widget")
local Screen = Device.screen
local _ = require("gettext")
local N_ = _.ngettext
local T = require("ffi/util").template
local util = require("util")

local function formatCount(value)
    if value == nil then return "" end
    return util.getFormattedSize(value)
end

local MONTH_NAMES_SHORT = {
    _("Jan"), _("Feb"), _("Mar"), _("Apr"), _("May"), _("Jun"),
    _("Jul"), _("Aug"), _("Sep"), _("Oct"), _("Nov"), _("Dec"),
}
local MONTH_NAMES_FULL = {
    _("January"), _("February"), _("March"), _("April"), _("May"), _("June"),
    _("July"), _("August"), _("September"), _("October"), _("November"), _("December"),
}

local db_path = DataStorage:getSettingsDir() .. "/statistics.sqlite3"
local ReadingInsightsPopup

local function withStatsDb(fallback, fn)
    local lfs = require("libs/libkoreader-lfs")
    if lfs.attributes(db_path, "mode") ~= "file" then
        return fallback
    end

    local conn = SQ3.open(db_path)
    if not conn then return fallback end

    local ok, result = pcall(fn, conn)
    conn:close()
    if ok then
        return result
    end
    return fallback
end

local function withStatement(conn, sql, fn)
    local stmt = conn:prepare(sql)
    if not stmt then return end
    local ok, result = pcall(fn, stmt)
    stmt:close()
    if ok then
        return result
    end
end

local function computeStreaks(entries_desc, is_consecutive, is_current_start)
    if #entries_desc == 0 then
        return 0, 0
    end

    local current = 0
    if is_current_start(entries_desc[1]) then
        current = 1
        for i = 2, #entries_desc do
            if is_consecutive(entries_desc[i - 1], entries_desc[i]) then
                current = current + 1
            else
                break
            end
        end
    end

    local best = 1
    local run = 1
    for i = 2, #entries_desc do
        if is_consecutive(entries_desc[i - 1], entries_desc[i]) then
            run = run + 1
            if run > best then
                best = run
            end
        else
            run = 1
        end
    end

    return current, best
end

local function parseDateYMD(date_str)
    if not date_str then return end
    local year = tonumber(date_str:sub(1,4))
    local month = tonumber(date_str:sub(6,7))
    local day = tonumber(date_str:sub(9,10))
    if not year or not month or not day then return end
    return year, month, day
end

local function parseWeekYear(week_str)
    if not week_str then return end
    local year_str, week_str_num = week_str:match("(%d+)-(%d+)")
    local year = tonumber(year_str)
    local week = tonumber(week_str_num)
    if not year or week == nil then return end
    return year, week
end

local function formatTimeRead(seconds)
    if not seconds or seconds <= 0 then
        return "", ""
    end

    if seconds < 60 then
        local s = math.floor(seconds)
        return formatCount(s), N_("second read", "seconds read", s)
    elseif seconds < 3600 then
        local m = math.floor(seconds / 60)
        return formatCount(m), N_("minute read", "minutes read", m)
    else
        local h = seconds / 3600
        if h < 10 then
            return string.format("%.1f", h), N_("hour read", "hours read", h)
        else
            return string.format("%.0f", h), N_("hour read", "hours read", h)
        end
    end
end

local function getSerifFace(font_name, fallback_name, size)
    return Font:getFace(font_name, size) or Font:getFace(fallback_name, size)
end

local function buildSerifFonts()
    local label_size = Font.sizemap.x_smallinfofont
    local small_size = Font.sizemap.xx_smallinfofont
    return {
        section = Font:getFace("x_smallinfofont"),
        value = getSerifFace("NotoSerif-Bold.ttf", "tfont", 32),
        label = getSerifFace("NotoSerif-Regular.ttf", "x_smallinfofont", label_size),
        small = getSerifFace("NotoSerif-Regular.ttf", "xx_smallinfofont", small_size),
    }
end

local function buildLayout(screen_w, padding_h, column_gap)
    local separator_width = 2 * column_gap + Size.line.medium
    local content_width = screen_w - 2 * padding_h
    local col_width = math.floor((content_width - separator_width) / 2)
    return {
        full_width = screen_w,
        padding_h = padding_h,
        column_gap = column_gap,
        separator_width = separator_width,
        content_width = content_width,
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

local function buildValueLine(font_value, font_label, col_width, value, unit)
    if value == "" then
        return TextBoxWidget:new{
            text = unit,
            face = font_label,
            width = col_width,
            alignment = "left",
        }
    end

    local value_widget = TextWidget:new{ text = value, face = font_value }
    local value_width = value_widget:getSize().w
    local text_desc_width = col_width - value_width - Size.padding.large
    return HorizontalGroup:new{
        align = "center",
        value_widget,
        HorizontalSpan:new{ width = Size.padding.large },
        TextBoxWidget:new{
            text = unit,
            face = font_label,
            width = text_desc_width,
            alignment = "left",
        },
    }
end

local function fixedCol(widget, width)
    return LeftContainer:new{
        dimen = Geom:new{ w = width, h = widget:getSize().h },
        widget,
    }
end

local function padded(padding_h, widget)
    return HorizontalGroup:new{
        HorizontalSpan:new{ width = padding_h },
        widget,
    }
end

local function buildTwoColRow(left_widget, right_widget, layout)
    return HorizontalGroup:new{
        align = "center",
        fixedCol(left_widget, layout.col_width),
        buildColumnSeparator(layout.column_gap, left_widget:getSize().h),
        fixedCol(right_widget, layout.col_width),
    }
end

local function addSectionWithRow(sections, header_widget, row, layout, opts)
    local pad_row = true
    local add_divider = true
    if opts then
        if opts.pad_row == false then pad_row = false end
        if opts.add_divider == false then add_divider = false end
    end

    table.insert(sections, header_widget)
    table.insert(sections, VerticalSpan:new{ height = Size.padding.default })
    table.insert(sections, pad_row and padded(layout.padding_h, row) or row)
    table.insert(sections, VerticalSpan:new{ height = Size.padding.large })
    if add_divider then
        table.insert(sections, LineWidget:new{
            dimen = Geom:new{ w = layout.full_width, h = Size.line.medium },
            background = Blitbuffer.COLOR_BLACK,
        })
    end
end

local function buildYearHeader(popup_self, font_section, layout, year_range)
    local selected_year = popup_self.selected_year
    local prev_enabled = selected_year > year_range.min_year
    local next_enabled = selected_year < year_range.max_year

    local sample_nav = TextWidget:new{ text = "< 0000", face = font_section }
    local nav_width = sample_nav:getSize().w
    sample_nav:free()

    local year_label = TextWidget:new{
        text = tostring(selected_year),
        face = font_section,
    }

    local function navButton(text, target_year)
        return Button:new{
            text = text,
            bordersize = 0,
            padding = 0,
            margin = 0,
            background = Blitbuffer.COLOR_GRAY_E,
            text_font_face = font_section.orig_font,
            text_font_size = font_section.orig_size,
            text_font_bold = false,
            callback = function()
                UIManager:close(popup_self)
                local new_popup = ReadingInsightsPopup:new{
                    ui = popup_self.ui,
                    selected_year = target_year,
                }
                UIManager:show(new_popup)
            end,
        }
    end

    local prev_widget = prev_enabled
        and navButton("< " .. tostring(selected_year - 1), selected_year - 1)
        or HorizontalSpan:new{ width = nav_width }
    local next_widget = next_enabled
        and navButton(tostring(selected_year + 1) .. " >", selected_year + 1)
        or HorizontalSpan:new{ width = nav_width }

    local prev_w = prev_enabled and prev_widget:getSize().w or nav_width
    local next_w = next_enabled and next_widget:getSize().w or nav_width
    local year_w = year_label:getSize().w
    local remaining = layout.content_width - prev_w - year_w - next_w
    local side_space = math.floor(remaining / 2)

    local year_header_content = HorizontalGroup:new{
        align = "center",
        LeftContainer:new{
            dimen = Geom:new{ w = prev_w + side_space, h = year_label:getSize().h },
            prev_widget,
        },
        year_label,
        LeftContainer:new{
            dimen = Geom:new{ w = next_w + side_space, h = year_label:getSize().h },
            HorizontalGroup:new{
                HorizontalSpan:new{ width = side_space },
                next_widget,
            },
        },
    }

    return FrameContainer:new{
        background = Blitbuffer.COLOR_GRAY_E,
        bordersize = 0,
        padding_top = Size.padding.small,
        padding_bottom = Size.padding.small,
        padding_left = layout.padding_h,
        padding_right = layout.padding_h,
        year_header_content,
    }
end

local function buildYearlyRow(popup_self, yearly_stats, fonts, layout)
    local days_val = buildValueLine(
        fonts.value,
        fonts.label,
        layout.col_width,
        formatCount(yearly_stats.days),
        N_("day read", "days read", yearly_stats.days)
    )
    local pages_val = buildValueLine(
        fonts.value,
        fonts.label,
        layout.col_width,
        formatCount(yearly_stats.pages),
        N_("page read", "pages read", yearly_stats.pages)
    )

    local yearly_row = buildTwoColRow(days_val, pages_val, layout)

    local yearly_row_container = FrameContainer:new{
        bordersize = 0,
        padding = 0,
        padded(layout.padding_h, yearly_row),
    }
    local tappable_yearly_row = InputContainer:new{
        dimen = yearly_row_container:getSize(),
        yearly_row_container,
    }
    tappable_yearly_row.ges_events = {
        Tap = {
            GestureRange:new{
                ges = "tap",
                range = function() return tappable_yearly_row.dimen end,
            }
        },
    }
    local selected_year_for_tap = popup_self.selected_year
    function tappable_yearly_row:onTap()
        popup_self:showBooksForYear(selected_year_for_tap)
        return true
    end

    return tappable_yearly_row
end

local function buildMonthlyChart(popup_self, monthly_data, layout, fonts)
    if #monthly_data == 0 then
        return nil
    end

    local max_days = 1
    for _, m in ipairs(monthly_data) do
        local d = tonumber(m.days) or 0
        if d > max_days then max_days = d end
    end

    local chart_width = layout.content_width
    local bar_height = tonumber(Screen:scaleBySize(60))
    local bar_width = math.floor(chart_width / 6) - tonumber(Screen:scaleBySize(8))
    local bar_gap = math.floor((chart_width - bar_width * 6) / 5)
    local font_small = fonts.small

    local sample_label = TextWidget:new{ text = "0", face = font_small }
    local label_height = sample_label:getSize().h
    sample_label:free()

    local current_year = tonumber(os.date("%Y"))
    local current_month = os.date("%Y-%m")

    local function createBarRow(data_slice)
        local bars_row = HorizontalGroup:new{ align = "bottom" }
        local month_labels_row = HorizontalGroup:new{ align = "top" }
        local baseline_h = Size.line.medium
        local total_bar_height = bar_height + label_height

        for i, m in ipairs(data_slice) do
            local days = tonumber(m.days) or 0
            local ratio = max_days > 0 and (days / max_days) or 0
            local bar_h = math.floor(ratio * bar_height + 0.5)
            if bar_h == 0 and days > 0 then bar_h = 1 end

            local is_current = (popup_self.selected_year == current_year) and (m.month == current_month)
            local bar_color = is_current and Blitbuffer.COLOR_BLACK or Blitbuffer.COLOR_GRAY

            local day_label = TextWidget:new{
                text = formatCount(days),
                face = font_small,
            }
            local centered_label = CenterContainer:new{
                dimen = Geom:new{ w = bar_width, h = label_height },
                day_label,
            }

            local bar_column = VerticalGroup:new{
                align = "center",
            }
            table.insert(bar_column, centered_label)
            if bar_h > 0 then
                table.insert(bar_column, LineWidget:new{
                    dimen = Geom:new{ w = bar_width, h = bar_h },
                    background = bar_color,
                })
            end
            table.insert(bar_column, LineWidget:new{
                dimen = Geom:new{ w = bar_width, h = baseline_h },
                background = bar_color,
            })

            local bar_container = BottomContainer:new{
                dimen = Geom:new{ w = bar_width, h = total_bar_height },
                bar_column,
            }

            local tappable_bar = InputContainer:new{
                dimen = Geom:new{ w = bar_width, h = total_bar_height },
                bar_container,
            }
            local month_data = m
            local month_year_label = m.label_full .. " " .. popup_self.selected_year
            tappable_bar.ges_events = {
                Tap = {
                    GestureRange:new{
                        ges = "tap",
                        range = function() return tappable_bar.dimen end,
                    }
                },
            }
            function tappable_bar:onTap()
                popup_self:showBooksForMonth(month_data.month, month_year_label)
                return true
            end

            table.insert(bars_row, tappable_bar)

            local month_label_widget = TextWidget:new{
                text = m.label,
                face = font_small,
            }
            table.insert(month_labels_row, CenterContainer:new{
                dimen = Geom:new{ w = bar_width, h = month_label_widget:getSize().h },
                month_label_widget,
            })

            if i < #data_slice then
                table.insert(bars_row, HorizontalSpan:new{ width = bar_gap })
                table.insert(month_labels_row, HorizontalSpan:new{ width = bar_gap })
            end
        end

        return VerticalGroup:new{
            align = "center",
            bars_row,
            VerticalSpan:new{ height = Size.padding.small },
            month_labels_row,
        }
    end

    local chart = VerticalGroup:new{
        align = "center",
    }
    local row_index = 0
    for i = 1, #monthly_data, 6 do
        local row_data = {}
        for j = i, math.min(i + 5, #monthly_data) do
            table.insert(row_data, monthly_data[j])
        end
        if #row_data > 0 then
            if row_index > 0 then
                table.insert(chart, VerticalSpan:new{ height = Size.padding.default })
            end
            table.insert(chart, createBarRow(row_data))
            row_index = row_index + 1
        end
    end

    return chart
end

local function buildInsightsSections(popup_self, streaks, yearly_stats, year_range, monthly_data, today_stats, fonts, layout)
    local sections = VerticalGroup:new{
        align = "left",
    }

    if today_stats and (today_stats.seconds > 0 or today_stats.pages > 0) then
        local time_val, time_unit = formatTimeRead(today_stats.seconds)
        local pages_val = today_stats.pages > 0 and formatCount(today_stats.pages) or ""
        local pages_unit = today_stats.pages > 0 and N_("page read", "pages read", today_stats.pages) or ""
        local today_row = buildTwoColRow(
            buildValueLine(fonts.value, fonts.label, layout.col_width, time_val, time_unit),
            buildValueLine(fonts.value, fonts.label, layout.col_width, pages_val, pages_unit),
            layout
        )

        addSectionWithRow(
            sections,
            buildSectionHeader(fonts.section, _("TODAY"), layout.full_width),
            today_row,
            layout
        )
    end

    local function streakDisplay(n, unit_label, empty_label)
        if n < 2 then
            return "", empty_label
        end
        return formatCount(n), unit_label(n)
    end

    local cw_val, cw_unit = streakDisplay(
        streaks.current_weeks,
        function(n) return N_("week in a row", "weeks in a row", n) end,
        _("No weekly streak")
    )
    local cd_val, cd_unit = streakDisplay(
        streaks.current_days,
        function(n) return N_("day in a row", "days in a row", n) end,
        _("No daily streak")
    )
    local bw_val, bw_unit = streakDisplay(
        streaks.best_weeks,
        function(n) return N_("week in a row", "weeks in a row", n) end,
        _("No weekly streak")
    )
    local bd_val, bd_unit = streakDisplay(
        streaks.best_days,
        function(n) return N_("day in a row", "days in a row", n) end,
        _("No daily streak")
    )

    local current_row = buildTwoColRow(
        buildValueLine(fonts.value, fonts.label, layout.col_width, cw_val, cw_unit),
        buildValueLine(fonts.value, fonts.label, layout.col_width, cd_val, cd_unit),
        layout
    )
    local best_row = buildTwoColRow(
        buildValueLine(fonts.value, fonts.label, layout.col_width, bw_val, bw_unit),
        buildValueLine(fonts.value, fonts.label, layout.col_width, bd_val, bd_unit),
        layout
    )

    addSectionWithRow(
        sections,
        buildSectionHeader(fonts.section, _("CURRENT STREAK"), layout.full_width),
        current_row,
        layout
    )
    addSectionWithRow(
        sections,
        buildSectionHeader(fonts.section, _("BEST STREAK"), layout.full_width),
        best_row,
        layout
    )

    local year_header = buildYearHeader(popup_self, fonts.section, layout, year_range)
    local yearly_row = buildYearlyRow(popup_self, yearly_stats, fonts, layout)
    addSectionWithRow(
        sections,
        year_header,
        yearly_row,
        layout,
        { pad_row = false }
    )

    local chart = buildMonthlyChart(popup_self, monthly_data, layout, fonts)
    if chart then
        addSectionWithRow(
            sections,
            buildSectionHeader(fonts.section, _("DAYS READ PER MONTH"), layout.full_width),
            chart,
            layout,
            { add_divider = false }
        )
    end

    table.insert(sections, LineWidget:new{
        dimen = Geom:new{ w = layout.full_width, h = Size.line.medium },
        background = Blitbuffer.COLOR_BLACK,
    })

    return sections
end

Dispatcher:registerAction("reading_insights_popup", {
    category = "none",
    event = "ShowReadingInsightsPopup",
    title = _("Reading statistics: reading insights"),
    reader = true,
})

ReadingInsightsPopup = InputContainer:extend{
    modal = true,
    ui = nil,
    width = nil,
    height = nil,
    selected_year = nil, -- for yearly stats section
}

-- Streaks are computed from distinct local dates/weeks in page_stat.
function ReadingInsightsPopup:calculateStreaks()
    local streaks = {
        current_days = 0,
        best_days = 0,
        current_weeks = 0,
        best_weeks = 0,
    }

    return withStatsDb(streaks, function(conn)
        local dates = {}
        local sql = "SELECT DISTINCT date(start_time, 'unixepoch', 'localtime') as d FROM page_stat ORDER BY d DESC"
        withStatement(conn, sql, function(stmt)
            for row in stmt:rows() do
                table.insert(dates, row[1])
            end
        end)

        local today = os.date("%Y-%m-%d")
        local yesterday = os.date("%Y-%m-%d", os.time() - 86400)

        local function isCurrentDayStart(first_date)
            return first_date == today or first_date == yesterday
        end

        local function isConsecutiveDay(prev_date, curr_date)
            local year, month, day = parseDateYMD(prev_date)
            if not year then return false end
            local prev_time = os.time({
                year = year,
                month = month,
                day = day,
            })
            local expected_prev = os.date("%Y-%m-%d", prev_time - 86400)
            return curr_date == expected_prev
        end

        streaks.current_days, streaks.best_days = computeStreaks(dates, isConsecutiveDay, isCurrentDayStart)

        local weeks = {}
        local sql_weeks = "SELECT DISTINCT strftime('%Y-%W', start_time, 'unixepoch', 'localtime') as w FROM page_stat ORDER BY w DESC"
        withStatement(conn, sql_weeks, function(stmt_weeks)
            for row in stmt_weeks:rows() do
                table.insert(weeks, row[1])
            end
        end)

        local current_week = os.date("%Y-%W")
        local last_week = os.date("%Y-%W", os.time() - 7 * 86400)

        local function isCurrentWeekStart(first_week)
            return first_week == current_week or first_week == last_week
        end

        local function isConsecutiveWeek(prev_week, curr_week)
            local prev_year, prev_wk = parseWeekYear(prev_week)
            local curr_year, curr_wk = parseWeekYear(curr_week)
            if not prev_year or not curr_year then
                return false
            end

            if prev_year == curr_year and prev_wk == curr_wk + 1 then
                return true
            end
            if prev_year == curr_year + 1 and prev_wk == 0 and curr_wk >= 52 then
                -- Year boundary: week 0 of new year follows week 52/53 of previous year
                return true
            end
            return false
        end

        streaks.current_weeks, streaks.best_weeks = computeStreaks(weeks, isConsecutiveWeek, isCurrentWeekStart)

        return streaks
    end)
end

function ReadingInsightsPopup:getMonthlyReadingDays(year)
    local months = {}
    return withStatsDb(months, function(conn)
        local year_str = tostring(year)
        local sql = string.format([[
            SELECT strftime('%%Y-%%m', start_time, 'unixepoch', 'localtime') AS month,
                   COUNT(DISTINCT date(start_time, 'unixepoch', 'localtime')) AS days_read
            FROM page_stat
            WHERE strftime('%%Y', start_time, 'unixepoch', 'localtime') = '%s'
            GROUP BY month
            ORDER BY month ASC
        ]], year_str)

        local results = {}
        withStatement(conn, sql, function(stmt)
            for row in stmt:rows() do
                results[row[1]] = row[2]
            end
        end)

        for month_num = 1, 12 do
            local year_month = string.format("%04d-%02d", year, month_num)
            local days = tonumber(results[year_month]) or 0
            table.insert(months, {
                month = year_month,
                days = days,
                label = MONTH_NAMES_SHORT[month_num],
                label_full = MONTH_NAMES_FULL[month_num],
            })
        end

        return months
    end)
end

function ReadingInsightsPopup:getYearlyStats(year)
    local stats = { days = 0, pages = 0 }
    return withStatsDb(stats, function(conn)
        local year_str = tostring(year)

        local sql_days = string.format([[
            SELECT COUNT(DISTINCT date(start_time, 'unixepoch', 'localtime'))
            FROM page_stat
            WHERE strftime('%%Y', start_time, 'unixepoch', 'localtime') = '%s'
        ]], year_str)
        withStatement(conn, sql_days, function(stmt_days)
            for row in stmt_days:rows() do
                stats.days = tonumber(row[1]) or 0
            end
        end)

        -- Unique (id_book, page) pairs; rereads in the same year do not add to the count.
        local sql_pages = string.format([[
            SELECT count(*)
            FROM (
                SELECT 1
                FROM page_stat
                WHERE strftime('%%Y', start_time, 'unixepoch', 'localtime') = '%s'
                GROUP BY id_book, page
            )
        ]], year_str)
        withStatement(conn, sql_pages, function(stmt_pages)
            for row in stmt_pages:rows() do
                stats.pages = tonumber(row[1]) or 0
            end
        end)

        return stats
    end)
end

function ReadingInsightsPopup:getYearRange()
    local current_year = tonumber(os.date("%Y"))
    local range = { min_year = current_year, max_year = current_year }
    return withStatsDb(range, function(conn)
        local sql = [[
            SELECT MIN(strftime('%Y', start_time, 'unixepoch', 'localtime')) AS min_year,
                   MAX(strftime('%Y', start_time, 'unixepoch', 'localtime')) AS max_year
            FROM page_stat
        ]]
        withStatement(conn, sql, function(stmt)
            for row in stmt:rows() do
                if row[1] then range.min_year = tonumber(row[1]) or current_year end
                if row[2] then range.max_year = tonumber(row[2]) or current_year end
            end
        end)

        return range
    end)
end

function ReadingInsightsPopup:getTodayStats()
    local stats = { seconds = 0, pages = 0 }
    return withStatsDb(stats, function(conn)
        local now_ts = os.time()
        local now_t = os.date("*t")
        local start_today_time = now_ts - (now_t.hour * 3600 + now_t.min * 60 + now_t.sec)
        -- Count unique pages read today; sum reading time per (book,page).
        local sql = string.format([[
            SELECT count(*),
                   sum(sum_duration)
            FROM (
                SELECT sum(duration) AS sum_duration
                FROM page_stat
                WHERE start_time >= %d
                GROUP BY id_book, page
            );
        ]], start_today_time)

        withStatement(conn, sql, function(stmt)
            for row in stmt:rows() do
                stats.pages = tonumber(row[1]) or 0
                stats.seconds = tonumber(row[2]) or 0
            end
        end)

        return stats
    end)
end

local function getBooksForPeriod(period_format, period_value)
    local books = {}
    return withStatsDb(books, function(conn)
        -- Count distinct pages per book for the period (ignore rereads of the same page).
        local sql = string.format([[
            SELECT book.title, book.authors, COUNT(DISTINCT page_stat.page) as pages_read
            FROM page_stat
            JOIN book ON page_stat.id_book = book.id
            WHERE strftime('%s', start_time, 'unixepoch', 'localtime') = '%s'
            GROUP BY page_stat.id_book
            ORDER BY pages_read DESC
        ]], period_format, period_value)

        withStatement(conn, sql, function(stmt)
            for row in stmt:rows() do
                table.insert(books, {
                    title = row[1] or _("Unknown"),
                    authors = row[2] or "",
                    pages = tonumber(row[3]) or 0,
                })
            end
        end)

        return books
    end)
end

-- Get list of books read in a given month (year_month format: "2025-01")
function ReadingInsightsPopup:getBooksForMonth(year_month)
    return getBooksForPeriod("%Y-%m", year_month)
end

local function showBookList(title, books, on_close)
    local Menu = require("ui/widget/menu")

    if #books == 0 then
        local InfoMessage = require("ui/widget/infomessage")
        UIManager:show(InfoMessage:new{
            text = _("No books read"),
        })
        return
    end

    local item_table = {}
    for i, book in ipairs(books) do
        local pages_text = N_("page", "pages", book.pages)
        local display_text = book.title
        if book.authors and book.authors ~= "" then
            display_text = display_text .. " (" .. book.authors .. ")"
        end
        table.insert(item_table, {
            text = display_text,
            mandatory = util.getFormattedSize(book.pages) .. " " .. pages_text,
            bold = true,
        })
    end

    local menu
    menu = Menu:new{
        title = title,
        item_table = item_table,
        width = Screen:getWidth(),
        height = Screen:getHeight(),
        is_borderless = true,
        is_popout = false,
        close_callback = function()
            UIManager:close(menu)
            if on_close then on_close() end
        end,
    }
    UIManager:show(menu)
end

local function showBooksForPeriod(popup_self, books, empty_text, title)
    if #books == 0 then
        local InfoMessage = require("ui/widget/infomessage")
        UIManager:show(InfoMessage:new{
            text = empty_text,
        })
        return
    end

    local ui = popup_self.ui
    local selected_year = popup_self.selected_year
    UIManager:close(popup_self)

    showBookList(
        title,
        books,
        function()
            local new_popup = ReadingInsightsPopup:new{
                ui = ui,
                selected_year = selected_year,
            }
            UIManager:show(new_popup)
        end
    )
end

-- month_label_full should be "January 2025" format
function ReadingInsightsPopup:showBooksForMonth(year_month, month_label_full)
    local books = self:getBooksForMonth(year_month)
    showBooksForPeriod(
        self,
        books,
        T(_("No books read in %1"), month_label_full),
        T(N_("%1 - Book Read (%2)", "%1 - Books Read (%2)", #books), month_label_full, #books)
    )
end

function ReadingInsightsPopup:getBooksForYear(year)
    return getBooksForPeriod("%Y", tostring(year))
end

function ReadingInsightsPopup:showBooksForYear(year)
    local books = self:getBooksForYear(year)
    showBooksForPeriod(
        self,
        books,
        _("No books read in ") .. year,
        T(N_("%1 - Book Read (%2)", "%1 - Books Read (%2)", #books), year, #books)
    )
end

function ReadingInsightsPopup:init()
    local screen_w = Screen:getWidth()
    local screen_h = Screen:getHeight()
    local today_stats = self:getTodayStats()
    local streaks = self:calculateStreaks()
    local year_range = self:getYearRange()
    if not self.selected_year then
        self.selected_year = year_range.max_year
    end
    local yearly_stats = self:getYearlyStats(self.selected_year)
    local monthly_data = self:getMonthlyReadingDays(self.selected_year)

    local fonts = buildSerifFonts()
    local layout = buildLayout(screen_w, Size.padding.large, Screen:scaleBySize(20))
    local sections = buildInsightsSections(
        self,
        streaks,
        yearly_stats,
        year_range,
        monthly_data,
        today_stats,
        fonts,
        layout
    )

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

    self.dimen = Geom:new{ w = screen_w, h = screen_h }

    if Device:isTouchDevice() then
        self.ges_events.TapClose = {
            GestureRange:new{
                ges = "tap",
                range = self.dimen,
            }
        }
    end
end

function ReadingInsightsPopup:onShow()
    UIManager:setDirty(self, function()
        return "ui", self.popup_frame.dimen
    end)
    return true
end

function ReadingInsightsPopup:onTapClose()
    UIManager:close(self)
    return true
end

function ReadingInsightsPopup:onCloseWidget()
    UIManager:setDirty(nil, "ui")
end

-- Hook into ReaderUI to handle the event
local ReaderUI = require("apps/reader/readerui")
local orig_ReaderUI_registerKeyEvents = ReaderUI.registerKeyEvents

ReaderUI.registerKeyEvents = function(self)
    if orig_ReaderUI_registerKeyEvents then
        orig_ReaderUI_registerKeyEvents(self)
    end
    self.onShowReadingInsightsPopup = function(this)
        local popup = ReadingInsightsPopup:new{
            ui = this,
        }
        UIManager:show(popup)
        return true
    end
end
