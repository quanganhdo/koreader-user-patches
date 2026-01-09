-- Custom time remaining format: "X hr Y mins left in chapter/book" when hours are present.
-- Version: 1.0.1
-- Updates: https://github.com/quanganhdo/koreader-user-patches
local ReaderFooter = require("apps/reader/modules/readerfooter")
local Math = require("optmath")

-- User patch localization: add your language overrides here.
local PATCH_L10N = {
    en = {
        ["hr"] = "hr",
        ["hrs"] = "hrs",
        ["min"] = "min",
        ["mins"] = "mins",
        ["left in chapter"] = "left in chapter",
        ["left in book"] = "left in book",
    },
    vi = {
        ["hr"] = "giờ",
        ["hrs"] = "giờ",
        ["min"] = "phút",
        ["mins"] = "phút",
        ["left in chapter"] = "còn lại trong chương",
        ["left in book"] = "còn lại trong sách",
    },
    ru = {
        ["hr"] = "ч.",
        ["hrs"] = "ч.",
        ["min"] = "мин.",
        ["mins"] = "мин.",
        ["left in chapter"] = "осталось в главе",
        ["left in book"] = "осталось в книге",
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

local function tr(msg)
    return l10nLookup(msg) or msg
end

local function formatTimeLeft(seconds, suffix)
    if not seconds or seconds ~= seconds then
        return ""
    end

    local total_minutes = Math.round(seconds / 60)
    if total_minutes < 0 then
        total_minutes = 0
    end
    local hrs = math.floor(total_minutes / 60)
    local mins = total_minutes % 60

    if hrs > 0 then
        local hr_text = hrs == 1 and tr("hr") or tr("hrs")
        local min_text = mins == 1 and tr("min") or tr("mins")
        return string.format("%d %s %d %s %s", hrs, hr_text, mins, min_text, suffix)
    else
        local min_text = mins == 1 and tr("min") or tr("mins")
        return string.format("%d %s %s", mins, min_text, suffix)
    end
end

ReaderFooter.textGeneratorMap.chapter_time_to_read = function(footer)
    local left = footer.ui.toc:getChapterPagesLeft(footer.pageno, true)
        or footer.ui.document:getTotalPagesLeft(footer.pageno)

    if not footer.ui.statistics or not footer.ui.statistics.avg_time then
        return ""
    end

    return formatTimeLeft(left * footer.ui.statistics.avg_time, tr("left in chapter"))
end

ReaderFooter.textGeneratorMap.book_time_to_read = function(footer)
    local left = footer.ui.document:getTotalPagesLeft(footer.pageno)

    if not footer.ui.statistics or not footer.ui.statistics.avg_time then
        return ""
    end

    return formatTimeLeft(left * footer.ui.statistics.avg_time, tr("left in book"))
end
