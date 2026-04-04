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
    local FrameContainer = require("ui/widget/container/framecontainer")
    local CenterContainer = require("ui/widget/container/centercontainer")
    local Size = require("ui/size")
    local TextWidget = require("ui/widget/textwidget")
    local Screen = Device.screen

    local percentage_badge_cache = {}
    local percentage_face = Font:getFace("infont", 13)
    local complete_badge

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

    local function getCompleteBadge()
        if complete_badge then
            return complete_badge
        end

        local text_widget = TextWidget:new{
            text = "\u{2713}",
            face = percentage_face,
            fgcolor = Blitbuffer.COLOR_WHITE,
        }
        local text_size = text_widget:getSize()
        local padding = Screen:scaleBySize(3)
        local inner_side = math.max(text_size.w, text_size.h)
        complete_badge = FrameContainer:new{
            margin = 0,
            padding = padding,
            bordersize = math.max(1, Size.line.thin),
            color = Blitbuffer.COLOR_WHITE,
            radius = math.floor((inner_side + padding * 2) / 2) + 1,
            background = Blitbuffer.COLOR_BLACK,
            CenterContainer:new{
                dimen = Geom:new{ w = inner_side, h = inner_side },
                text_widget,
            },
        }
        return complete_badge
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
        if not self.been_opened then
            return
        end
        if self.status == "abandoned" then
            return
        end
        if self.status ~= "complete" and not self.percent_finished then
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
        if self.status == "complete" then
            badge = getCompleteBadge()
            badge_size = badge:getSize()
            if BD.mirroredUILayout() then
                badge_x = target.dimen.x + Screen:scaleBySize(5)
            else
                badge_x = target.dimen.x + target.dimen.w - badge_size.w - Screen:scaleBySize(5)
            end
            badge_y = target.dimen.y + target.dimen.h - badge_size.h - Screen:scaleBySize(5)
            badge:paintTo(bb, badge_x, badge_y)
        else
            paintReadingPercentageBadge(bb, badge_x, badge_y, badge)
        end
    end
end)
