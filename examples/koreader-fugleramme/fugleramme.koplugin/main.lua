local DataStorage = require("datastorage")
local Device = require("device")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local ImageWidget = require("ui/widget/imagewidget")
local InfoMessage = require("ui/widget/infomessage")
local InputContainer = require("ui/widget/container/inputcontainer")
local InputDialog = require("ui/widget/inputdialog")
local LuaSettings = require("luasettings")
local NetworkMgr = require("ui/network/manager")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local http = require("socket.http")
local logger = require("logger")
local socket = require("socket")
local socketutil = require("socketutil")
local _ = require("gettext")

local Screen = Device.screen
local settings_file = DataStorage:getSettingsDir() .. "/fugleramme.lua"
local frame_file = DataStorage:getSettingsDir() .. "/fugleramme-frame.png"
local frame_tmp = frame_file .. ".tmp"

local FuglerammeView = InputContainer:extend{
    name = "fugleramme_frame",
    image = nil,
    owner = nil,
}

function FuglerammeView:init()
    local width, height = Screen:getWidth(), Screen:getHeight()
    self.dimen = Geom:new{ x = 0, y = 0, w = width, h = height }
    if Device:hasKeys() then
        self.key_events.Close = { { Device.input.group.Back } }
    end
    if Device:isTouchDevice() then
        local screen = GestureRange:new{ ges = "tap", range = self.dimen }
        self.ges_events.Tap = { screen }
        self.ges_events.Hold = { GestureRange:new{ ges = "hold", range = self.dimen } }
    end
    self.image = ImageWidget:new{
        file = frame_file,
        file_do_cache = false,
        width = width,
        height = height,
        alpha = false,
        original_in_nightmode = true,
    }
    self[1] = self.image
end

function FuglerammeView:onShow()
    UIManager:setDirty(self, "full")
    return true
end

function FuglerammeView:onTap()
    self.owner:refresh(true)
    return true
end

function FuglerammeView:onHold()
    self:onClose()
    return true
end

function FuglerammeView:onClose()
    UIManager:close(self)
    return true
end

FuglerammeView.onCloseWidget = function(self)
    self.owner:stop()
    UIManager:setDirty(nil, "full")
end

local Fugleramme = WidgetContainer:extend{
    name = "fugleramme",
    is_doc_only = false,
    settings = nil,
    view = nil,
    task = nil,
    running = false,
    version = nil,
}

function Fugleramme:init()
    self.settings = LuaSettings:open(settings_file)
    self.settings:readSetting("server_url", "")
    self.settings:readSetting("interval_seconds", 300)
    self.ui.menu:registerToMainMenu(self)
    self.task = function() self:refresh(false) end
end

function Fugleramme:profile()
    return Device:hasColorScreen() and "kaleido3" or "grayscale"
end

function Fugleramme:url(path)
    local base = self.settings:readSetting("server_url", ""):gsub("/+$", "")
    local query = string.format(
        "width=%d&height=%d&profile=%s",
        Screen:getWidth(), Screen:getHeight(), self:profile()
    )
    return base .. path .. "?" .. query
end

function Fugleramme:http_text(url)
    local chunks = {}
    socketutil:set_timeout(10, 30)
    local code, _headers, status = socket.skip(1, http.request{
        url = url,
        sink = socketutil.table_sink(chunks),
    })
    socketutil:reset_timeout()
    if code ~= 200 then return nil, status or tostring(code) end
    local body = table.concat(chunks):gsub("%s+$", "")
    return body
end

function Fugleramme:download(url)
    local output, err = io.open(frame_tmp, "wb")
    if not output then return nil, err end
    socketutil:set_timeout(15, 60)
    local code, _headers, status = socket.skip(1, http.request{
        url = url,
        sink = socketutil.file_sink(output),
    })
    socketutil:reset_timeout()
    if code ~= 200 then
        os.remove(frame_tmp)
        return nil, status or tostring(code)
    end
    if not os.rename(frame_tmp, frame_file) then
        os.remove(frame_tmp)
        return nil, "could not replace cached frame"
    end
    return true
end

function Fugleramme:redraw()
    if not self.view then return end
    self.view.image:free()
    UIManager:setDirty(self.view, "full")
end

function Fugleramme:schedule()
    if not self.running then return end
    UIManager:unschedule(self.task)
    local interval = tonumber(self.settings:readSetting("interval_seconds", 300)) or 300
    UIManager:scheduleIn(math.max(30, interval), self.task)
end

function Fugleramme:refresh(force)
    if not self.running then return end
    NetworkMgr:runWhenOnline(function()
        local version, err = self:http_text(self:url("/display/version"))
        if not version then
            logger.warn("Fugleramme version check failed:", err)
            self:schedule()
            return
        end
        if force or version ~= self.version then
            local ok
            ok, err = self:download(self:url("/display/frame.png"))
            if ok then
                self.version = version
                self:redraw()
                logger.info("Fugleramme displayed frame", version)
            else
                logger.warn("Fugleramme frame download failed:", err)
            end
        end
        self:schedule()
    end)
end

function Fugleramme:start()
    local server = self.settings:readSetting("server_url", "")
    if server == "" then
        UIManager:show(InfoMessage:new{ text = _("Set the Fugleramme server URL first.") })
        return
    end
    self.running = true
    local cached = io.open(frame_file, "rb")
    if cached then
        cached:close()
        self.view = FuglerammeView:new{ owner = self }
        UIManager:show(self.view)
    end
    NetworkMgr:runWhenOnline(function()
        if not self.view then
            local version, err = self:http_text(self:url("/display/version"))
            if version then
                local ok
                ok, err = self:download(self:url("/display/frame.png"))
                if ok then
                    self.version = version
                    self.view = FuglerammeView:new{ owner = self }
                    UIManager:show(self.view)
                    self:schedule()
                    return
                end
            end
            logger.warn("Fugleramme initial fetch failed:", err)
            self.running = false
            UIManager:show(InfoMessage:new{ text = _("Could not load the Fugleramme frame. Check Wi-Fi and the server URL.") })
        else
            self:refresh(false)
        end
    end)
end

function Fugleramme:stop()
    self.running = false
    UIManager:unschedule(self.task)
    self.view = nil
end

function Fugleramme:set_server_url()
    local dialog
    dialog = InputDialog:new{
        title = _("Fugleramme server URL"),
        input = self.settings:readSetting("server_url", ""),
        input_type = "url",
        buttons = {{
            {
                text = _("Cancel"),
                id = "close",
                callback = function() UIManager:close(dialog) end,
            },
            {
                text = _("Save"),
                is_enter_default = true,
                callback = function()
                    local value = dialog:getInputText():gsub("%s+$", ""):gsub("/+$", "")
                    self.settings:saveSetting("server_url", value):flush()
                    UIManager:close(dialog)
                end,
            },
        }},
    }
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

function Fugleramme:addToMainMenu(menu_items)
    menu_items.fugleramme = {
        text = _("Fugleramme frame"),
        sorting_hint = "more_tools",
        sub_item_table = {
            { text = _("Open frame"), callback = function() self:start() end },
            { text = _("Set server URL"), callback = function() self:set_server_url() end },
            {
                text = _("Refresh interval"),
                sub_item_table = {
                    { text = _("1 minute"), radio = true,
                      checked_func = function() return self.settings:readSetting("interval_seconds") == 60 end,
                      callback = function() self.settings:saveSetting("interval_seconds", 60):flush() end },
                    { text = _("5 minutes"), radio = true,
                      checked_func = function() return self.settings:readSetting("interval_seconds") == 300 end,
                      callback = function() self.settings:saveSetting("interval_seconds", 300):flush() end },
                    { text = _("15 minutes"), radio = true,
                      checked_func = function() return self.settings:readSetting("interval_seconds") == 900 end,
                      callback = function() self.settings:saveSetting("interval_seconds", 900):flush() end },
                },
            },
        },
    }
end

function Fugleramme:onCloseWidget()
    self:stop()
    if self.settings then self.settings:flush() end
end

return Fugleramme
