-- Custom time remaining format: "X hr Y mins left in chapter/book" when hours are present.
local ReaderFooter = require("apps/reader/modules/readerfooter")

local function formatTimeLeft(seconds, suffix)
    local mins = math.floor(seconds / 60)
    local hrs = math.floor(mins / 60)
    mins = mins % 60

    if hrs > 0 then
        local hr_text = hrs == 1 and "hr" or "hrs"
        local min_text = mins == 1 and "min" or "mins"
        return string.format("%d %s %d %s %s", hrs, hr_text, mins, min_text, suffix)
    else
        local min_text = mins == 1 and "min" or "mins"
        return string.format("%d %s %s", mins, min_text, suffix)
    end
end

ReaderFooter.textGeneratorMap.chapter_time_to_read = function(footer)
    local left = footer.ui.toc:getChapterPagesLeft(footer.pageno, true)
        or footer.ui.document:getTotalPagesLeft(footer.pageno)

    if not footer.ui.statistics or not footer.ui.statistics.avg_time then
        return ""
    end

    return formatTimeLeft(left * footer.ui.statistics.avg_time, "left in chapter")
end

ReaderFooter.textGeneratorMap.book_time_to_read = function(footer)
    local left = footer.ui.document:getTotalPagesLeft(footer.pageno)

    if not footer.ui.statistics or not footer.ui.statistics.avg_time then
        return ""
    end

    return formatTimeLeft(left * footer.ui.statistics.avg_time, "left in book")
end
