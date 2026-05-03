-- File browser finished-book badge
-- Version: 1.0.0
-- Updates: https://github.com/quanganhdo/koreader-user-patches
-- Changelog:
-- * 1.0.0: replace coverbrowser's opened dogear with a finished-book checkmark badge
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

    local complete_badge
    local complete_face = Font:getFace("infont", 13)

    local function getCompleteBadge()
        if complete_badge then
            return complete_badge
        end

        local text_widget = TextWidget:new{
            text = "\u{2713}",
            face = complete_face,
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
        if not self.been_opened or self.status ~= "complete" then
            return
        end

        local target = self[1] and self[1][1] and self[1][1][1]
        if not target or not target.dimen then
            return
        end

        local badge = getCompleteBadge()
        local badge_size = badge:getSize()
        local badge_x
        if BD.mirroredUILayout() then
            badge_x = target.dimen.x + Screen:scaleBySize(5)
        else
            badge_x = target.dimen.x + target.dimen.w - badge_size.w - Screen:scaleBySize(5)
        end
        local badge_y = target.dimen.y + target.dimen.h - badge_size.h - Screen:scaleBySize(5)
        badge:paintTo(bb, badge_x, badge_y)
    end
end)
