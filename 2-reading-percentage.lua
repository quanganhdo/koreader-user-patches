-- File browser reading percentage badge
-- Version: 1.0.3
-- Updates: https://github.com/quanganhdo/koreader-user-patches
local userpatch = require("userpatch")

userpatch.registerPatchPluginFunc("coverbrowser", function(CoverBrowser)
    local BD = require("ui/bidi")
    local Blitbuffer = require("ffi/blitbuffer")
    local Device = require("device")
    local Font = require("ui/font")
    local Geom = require("ui/geometry")
    local MosaicMenu = require("mosaicmenu")
    local MosaicMenuItem = userpatch.getUpValue(MosaicMenu._updateItemsBuildUI, "MosaicMenuItem")
    local FileChooser = require("ui/widget/filechooser")
    local TextWidget = require("ui/widget/textwidget")
    local Screen = Device.screen

    local percentage_badge_cache = {}
    local percentage_face = Font:getFace("infont", 13)

    local function getReadingPercentageText(percent_finished)
        local percent = math.floor((percent_finished or 0) * 100 + 0.5)
        if percent <= 0 then
            percent = 1
        elseif percent >= 100 then
            percent = 99
        end
        return string.format("%d%%", percent)
    end

    local function getReadingPercentageBadge(percent_finished)
        local text = getReadingPercentageText(percent_finished)
        if percentage_badge_cache[text] then
            return percentage_badge_cache[text]
        end

        local text_widget = TextWidget:new{
            text = text,
            face = percentage_face,
            fgcolor = Blitbuffer.COLOR_WHITE,
        }
        local text_size = text_widget:getSize()
        local padding_h = Screen:scaleBySize(3)
        local padding_top = Screen:scaleBySize(2)
        local padding_bottom = Screen:scaleBySize(3)
        local badge_w = text_size.w + 2 * padding_h
        local badge_h = text_size.h + padding_top + padding_bottom
        local badge = {
            text_widget = text_widget,
            text_size = text_size,
            width = badge_w,
            height = badge_h,
            padding_top = padding_top,
        }
        function badge:getSize()
            return Geom:new{ w = self.width, h = self.height }
        end
        percentage_badge_cache[text] = badge
        return badge
    end

    local function paintReadingPercentageBadge(bb, x, y, badge)
        bb:paintRect(x, y, badge.width, badge.height, Blitbuffer.COLOR_BLACK)
        local text_x = x + math.floor((badge.width - badge.text_size.w) / 2)
        local text_y = y + badge.padding_top
        badge.text_widget:paintTo(bb, text_x, text_y)
    end

    local original_setupFileManagerDisplayMode = CoverBrowser.setupFileManagerDisplayMode
    function CoverBrowser.setupFileManagerDisplayMode(...)
        original_setupFileManagerDisplayMode(...)
        FileChooser._do_hint_opened = false
    end

    FileChooser._do_hint_opened = false

    local original_MosaicMenuItem_paintTo = MosaicMenuItem.paintTo
    function MosaicMenuItem:paintTo(bb, x, y)
        original_MosaicMenuItem_paintTo(self, bb, x, y)

        if not self.menu or self.menu.name ~= "filemanager" then
            return
        end
        if not self.been_opened or not self.percent_finished then
            return
        end
        if self.status == "complete" or self.status == "abandoned" then
            return
        end

        local target = self[1] and self[1][1] and self[1][1][1]
        if not target or not target.dimen then
            return
        end

        local badge = getReadingPercentageBadge(self.percent_finished)
        local badge_size = badge:getSize()
        local badge_x
        if BD.mirroredUILayout() then
            badge_x = target.dimen.x + Screen:scaleBySize(5)
        else
            badge_x = target.dimen.x + target.dimen.w - badge_size.w - Screen:scaleBySize(5)
        end
        local badge_y = target.dimen.y
        paintReadingPercentageBadge(bb, badge_x, badge_y, badge)
    end
end)
