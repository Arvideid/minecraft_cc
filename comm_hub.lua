-- comm_hub.lua
-- ComputerCraft Communication Hub with simplified GUI

-- Load the modem control module
local modem = require("modem_control")

-- Color settings (simplified)
local COLORS = {
    BACKGROUND = colors.black,
    TEXT = colors.white,
    TITLE = colors.yellow,
    BORDER = colors.blue,
    SELECTED = colors.lightBlue,
    CONNECTED = colors.lime,
    DISCONNECTED = colors.red,
    MESSAGE_IN = colors.lightGray,
    MESSAGE_OUT = colors.cyan,
}

-- App state
local app = {
    running = true,
    devices = {},
    selected = nil,
    messageInput = "",
    width = 0,
    height = 0,
    lastScan = 0,
    scanInterval = 5, -- Scan every 5 seconds
    -- UI components
    ui = {
        deviceList = {
            x = 1, y = 3,
            width = 20, -- Slightly narrower
            height = 0,
            scroll = 0
        },
        messagePanel = {
            x = 23, y = 3, -- Adjusted
            width = 0,
            height = 0,
            scroll = 0
        },
        statusBar = {
            x = 1, y = 0
        },
        inputBar = {
            x = 23, y = 0 -- Adjusted
        }
    }
}

-- Device management
local function addDevice(id, name, deviceType)
    if not app.devices[id] then
        app.devices[id] = {
            id = id,
            name = name or "Device-" .. id,
            type = deviceType or "unknown",
            lastSeen = os.time(),
            connected = true,
            messages = {}
        }
    else
        -- Update existing device
        app.devices[id].lastSeen = os.time()
        app.devices[id].connected = true
        if name then app.devices[id].name = name end
        if deviceType then app.devices[id].type = deviceType end
    end
end

local function checkDeviceTimeouts()
    for id, device in pairs(app.devices) do
        if os.time() - device.lastSeen > modem.config.TIMEOUT then
            device.connected = false
        end
    end
end

-- Send a message and update history
local function sendMessageToDevice(deviceId, messageText)
    if not deviceId or not app.devices[deviceId] then return false end
    
    local success = modem.sendMessage(deviceId, messageText)
    
    if success then
        -- Add to message history
        if not app.devices[deviceId].messages then
            app.devices[deviceId].messages = {}
        end
        
        table.insert(app.devices[deviceId].messages, {
            content = messageText,
            sender = "me",
            timestamp = os.time()
        })
        
        return true
    end
    
    return false
end

-- Process messages from other devices
local function processMessage(senderId, message)
    if not message or not message.type then return end
    
    if message.type == "discovery_ping" then
        -- Respond to discovery
        modem.respondToDiscovery(senderId)
        -- Add device to list
        addDevice(senderId, message.name, message.device_type)
    elseif message.type == "discovery_response" then
        -- Add responding device
        addDevice(senderId, message.name, message.device_type)
    elseif message.type == "message" then
        -- Add to conversation
        addDevice(senderId)
        
        if not app.devices[senderId].messages then
            app.devices[senderId].messages = {}
        end
        
        table.insert(app.devices[senderId].messages, {
            content = message.content,
            sender = "them",
            timestamp = os.time()
        })
        
        -- Auto-respond to pings
        if message.content == "/ping" then
            sendMessageToDevice(senderId, "/ping_response")
        end
    end
end

-- UI Drawing functions --

-- Text wrapping utility (simplified)
local function wrapText(text, width)
    local result = {}
    local line = ""
    
    for word in text:gmatch("%S+") do
        if #line + #word + 1 > width then
            table.insert(result, line)
            line = word
        else
            if #line > 0 then
                line = line .. " " .. word
            else
                line = word
            end
        end
    end
    
    if #line > 0 then
        table.insert(result, line)
    end
    
    return result
end

-- Draw the entire UI (simplified)
local function drawUI()
    term.setBackgroundColor(COLORS.BACKGROUND)
    term.clear()
    
    -- Draw title bar
    term.setCursorPos(1, 1)
    term.setBackgroundColor(COLORS.BORDER)
    term.setTextColor(COLORS.TITLE)
    term.write(string.rep(" ", app.width))
    term.setCursorPos(math.floor((app.width - 18) / 2), 1)
    term.write("ComNet Hub v1.0")
    
    -- Draw divider
    for y = 3, app.height - 3 do
        term.setCursorPos(app.ui.deviceList.width + 1, y)
        term.setBackgroundColor(COLORS.BORDER)
        term.write(" ")
    end
    
    -- Draw headers
    term.setTextColor(COLORS.TEXT)
    term.setBackgroundColor(COLORS.BORDER)
    term.setCursorPos(2, 2)
    term.write("Devices")
    term.setCursorPos(app.ui.messagePanel.x, 2)
    term.write("Messages")
    
    -- Reset colors
    term.setBackgroundColor(COLORS.BACKGROUND)
    term.setTextColor(COLORS.TEXT)
    
    -- Draw device list
    local y = app.ui.deviceList.y
    local sorted = {}
    
    for _, device in pairs(app.devices) do
        table.insert(sorted, device)
    end
    
    table.sort(sorted, function(a, b)
        if a.connected ~= b.connected then
            return a.connected
        end
        return a.name < b.name
    end)
    
    for i, device in ipairs(sorted) do
        if i > app.ui.deviceList.scroll and y <= app.ui.deviceList.y + app.ui.deviceList.height then
            term.setCursorPos(app.ui.deviceList.x, y)
            
            -- Highlight selected device
            if app.selected == device.id then
                term.setBackgroundColor(COLORS.SELECTED)
            else
                term.setBackgroundColor(COLORS.BACKGROUND)
            end
            
            -- Set color based on connection status
            if device.connected then
                term.setTextColor(COLORS.CONNECTED)
            else
                term.setTextColor(COLORS.DISCONNECTED)
            end
            
            -- Draw device name with padding
            local displayName = device.name
            if #displayName > app.ui.deviceList.width - 4 then
                displayName = displayName:sub(1, app.ui.deviceList.width - 7) .. "..."
            end
            term.write(string.format(" %-" .. (app.ui.deviceList.width - 2) .. "s", displayName))
            
            y = y + 1
        end
    end
    
    -- Draw messages
    if app.selected and app.devices[app.selected] then
        local device = app.devices[app.selected]
        local messages = device.messages or {}
        local y = app.ui.messagePanel.y + app.ui.messagePanel.height
        
        -- Clear message panel
        for cy = app.ui.messagePanel.y, app.ui.messagePanel.y + app.ui.messagePanel.height do
            term.setCursorPos(app.ui.messagePanel.x, cy)
            term.setBackgroundColor(COLORS.BACKGROUND)
            term.write(string.rep(" ", app.ui.messagePanel.width))
        end
        
        -- Draw last few messages
        local count = 0
        for i = #messages, math.max(1, #messages - 10), -1 do
            local msg = messages[i]
            
            -- Set message format based on sender
            if msg.sender == "me" then
                term.setTextColor(COLORS.MESSAGE_OUT)
                prefix = "> "
            else
                term.setTextColor(COLORS.MESSAGE_IN)
                prefix = "< "
            end
            
            local wrapped = wrapText(msg.content, app.ui.messagePanel.width - 3)
            
            for j = #wrapped, 1, -1 do
                local text = wrapped[j]
                if j == #wrapped then
                    text = prefix .. text
                else
                    text = "  " .. text
                end
                
                y = y - 1
                if y >= app.ui.messagePanel.y then
                    term.setCursorPos(app.ui.messagePanel.x, y)
                    term.write(text)
                end
            end
            
            -- Stop if we've filled the panel
            if y <= app.ui.messagePanel.y then
                break
            end
        end
    else
        -- No device selected
        term.setTextColor(COLORS.TEXT)
        term.setCursorPos(app.ui.messagePanel.x, app.ui.messagePanel.y + 2)
        term.write("Select a device")
    end
    
    -- Draw input bar
    term.setCursorPos(1, app.height)
    term.setBackgroundColor(COLORS.BORDER)
    term.setTextColor(COLORS.TEXT)
    term.write(string.rep(" ", app.width))
    
    -- Draw status info
    local deviceCount = 0
    local connectedCount = 0
    for _, device in pairs(app.devices) do
        deviceCount = deviceCount + 1
        if device.connected then
            connectedCount = connectedCount + 1
        end
    end
    
    term.setCursorPos(2, app.height)
    term.write(string.format("Connected: %d/%d | ID: %d | ESC: Exit", 
        connectedCount, deviceCount, modem.deviceID))
    
    -- Draw input field
    term.setCursorPos(app.ui.messagePanel.x, app.height - 1)
    term.setBackgroundColor(COLORS.BACKGROUND)
    term.setTextColor(COLORS.TEXT)
    term.write(string.rep(" ", app.ui.messagePanel.width))
    
    -- Show input prompt if a device is selected
    if app.selected and app.devices[app.selected] then
        term.setCursorPos(app.ui.messagePanel.x, app.height - 1)
        term.write("> " .. app.messageInput)
        
        -- Position cursor at end of input
        term.setCursorPos(app.ui.messagePanel.x + 2 + #app.messageInput, app.height - 1)
        term.setCursorBlink(true)
    else
        term.setCursorBlink(false)
    end
end

-- Handle input events
local function handleKey(key)
    if key == keys.up then
        -- Navigate device list up
        if app.ui.deviceList.scroll > 0 then
            app.ui.deviceList.scroll = app.ui.deviceList.scroll - 1
        end
    elseif key == keys.down then
        -- Navigate device list down
        local deviceCount = 0
        for _ in pairs(app.devices) do deviceCount = deviceCount + 1 end
        if deviceCount > app.ui.deviceList.height and app.ui.deviceList.scroll < deviceCount - app.ui.deviceList.height then
            app.ui.deviceList.scroll = app.ui.deviceList.scroll + 1
        end
    elseif key == keys.enter then
        -- Send message
        if app.messageInput ~= "" and app.selected then
            -- Send message
            sendMessageToDevice(app.selected, app.messageInput)
            app.messageInput = ""
        end
    elseif key == keys.backspace then
        -- Delete character from message
        if #app.messageInput > 0 then
            app.messageInput = app.messageInput:sub(1, -2)
        end
    elseif key == keys.tab then
        -- Cycle through connected devices
        local connectedDevices = {}
        for id, device in pairs(app.devices) do
            if device.connected then
                table.insert(connectedDevices, id)
            end
        end
        
        table.sort(connectedDevices)
        
        if #connectedDevices > 0 then
            if not app.selected then
                app.selected = connectedDevices[1]
            else
                local index = nil
                for i, id in ipairs(connectedDevices) do
                    if id == app.selected then
                        index = i
                        break
                    end
                end
                
                if index then
                    app.selected = connectedDevices[(index % #connectedDevices) + 1]
                else
                    app.selected = connectedDevices[1]
                end
            end
        end
    elseif key == keys.f5 then
        -- Refresh devices
        modem.broadcastDiscovery()
    elseif key == keys.escape then
        -- Exit application
        app.running = false
    end
end

local function handleChar(char)
    app.messageInput = app.messageInput .. char
end

local function handleClick(button, x, y)
    -- Check if click was in the device list
    if x >= app.ui.deviceList.x and x < app.ui.deviceList.x + app.ui.deviceList.width and
       y >= app.ui.deviceList.y and y < app.ui.deviceList.y + app.ui.deviceList.height then
        -- Find which device was clicked
        local deviceIndex = y - app.ui.deviceList.y + app.ui.deviceList.scroll
        
        -- Get sorted list of devices
        local sorted = {}
        for _, device in pairs(app.devices) do
            table.insert(sorted, device)
        end
        
        table.sort(sorted, function(a, b)
            if a.connected ~= b.connected then
                return a.connected
            end
            return a.name < b.name
        end)
        
        if sorted[deviceIndex] then
            app.selected = sorted[deviceIndex].id
        end
    end
end

-- Initialize app
local function initialize()
    -- Initialize modem first
    if not modem.init() then
        error("Failed to initialize modem")
    end
    
    -- Set up UI dimensions
    app.width, app.height = term.getSize()
    app.ui.deviceList.height = app.height - 5
    app.ui.messagePanel.width = app.width - app.ui.deviceList.width - 3
    app.ui.messagePanel.height = app.height - 6
    
    -- Send initial discovery ping
    modem.broadcastDiscovery()
    app.lastScan = os.time()
    
    return true
end

-- Main event loop
local function mainLoop()
    while app.running do
        drawUI()
        
        -- Check for device timeouts
        checkDeviceTimeouts()
        
        -- Send periodic discovery pings (every 5 seconds)
        if os.time() - app.lastScan > app.scanInterval then
            modem.broadcastDiscovery()
            app.lastScan = os.time()
        end
        
        -- Poll for events with a short timeout
        local event, param1, param2, param3 = os.pullEvent(0.5) -- Short timeout for responsive UI
        
        if event == "key" then
            handleKey(param1)
        elseif event == "char" then
            handleChar(param1)
        elseif event == "mouse_click" then
            handleClick(param1, param2, param3)
        elseif event == "rednet_message" then
            local senderId, message, protocol = param1, param2, param3
            if protocol == modem.config.PROTOCOL then
                processMessage(senderId, message)
            end
        end
    end
end

-- Main application entry point
local function main()
    term.clear()
    term.setCursorPos(1,1)
    
    print("Starting ComNet Hub...")
    
    if not initialize() then
        print("Failed to initialize the application. Exiting.")
        return
    end
    
    print("Ready! Starting main loop...")
    
    -- Small delay to show startup message
    sleep(1)
    
    -- Run the main event loop
    mainLoop()
    
    -- Cleanup
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
    term.clear()
    term.setCursorPos(1,1)
    print("ComNet Hub terminated.")
    
    -- Close modem connections
    modem.close()
end

-- Start the application
main() 