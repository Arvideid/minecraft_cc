-- comm_hub.lua
-- ComputerCraft Communication Hub with GUI

-- Load the modem control module
local modem = require("modem_control")

-- Color settings
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
    BUTTON = colors.gray,
    BUTTON_TEXT = colors.white,
}

-- App state
local app = {
    running = true,
    mode = "main", -- main, help
    devices = {},
    selected = nil,
    messageInput = "",
    width = 0,
    height = 0,
    -- UI components
    ui = {
        deviceList = {
            x = 1, y = 3,
            width = 24,
            height = 0,
            scroll = 0
        },
        messagePanel = {
            x = 27, y = 3,
            width = 0,
            height = 0,
            scroll = 0
        },
        statusBar = {
            x = 1, y = 0
        },
        inputBar = {
            x = 27, y = 0
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

-- Text wrapping utility
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

-- Draw window borders and layout
local function drawBorder()
    term.setBackgroundColor(COLORS.BACKGROUND)
    term.setTextColor(COLORS.BORDER)
    term.clear()
    
    -- Draw title bar
    term.setCursorPos(1, 1)
    term.setBackgroundColor(COLORS.BORDER)
    term.setTextColor(COLORS.TITLE)
    term.write(string.rep(" ", app.width))
    term.setCursorPos(math.floor((app.width - 18) / 2), 1)
    term.write("ComNet Hub v1.0")
    
    -- Draw divider between device list and messages
    for y = 3, app.height - 3 do
        term.setCursorPos(app.ui.deviceList.width + 1, y)
        term.setBackgroundColor(COLORS.BORDER)
        term.write(" ")
    end
    
    -- Draw status bar
    term.setCursorPos(1, app.ui.statusBar.y)
    term.setBackgroundColor(COLORS.BORDER)
    term.setTextColor(COLORS.TEXT)
    term.write(string.rep(" ", app.width))
    
    -- Draw input bar divider
    term.setCursorPos(1, app.ui.inputBar.y)
    term.setBackgroundColor(COLORS.BORDER)
    term.write(string.rep(" ", app.width))
    
    -- Draw headers
    term.setTextColor(COLORS.TEXT)
    term.setBackgroundColor(COLORS.BORDER)
    term.setCursorPos(2, 2)
    term.write("Connected Devices")
    term.setCursorPos(app.ui.messagePanel.x, 2)
    term.write("Messages")
    
    -- Reset colors
    term.setBackgroundColor(COLORS.BACKGROUND)
    term.setTextColor(COLORS.TEXT)
end

-- Draw the list of devices
local function drawDeviceList()
    local y = app.ui.deviceList.y
    local count = 0
    local sorted = {}
    
    -- Sort devices by connection status and name
    for _, device in pairs(app.devices) do
        table.insert(sorted, device)
    end
    
    table.sort(sorted, function(a, b)
        if a.connected ~= b.connected then
            return a.connected
        end
        return a.name < b.name
    end)
    
    -- Draw each device
    for i, device in ipairs(sorted) do
        count = count + 1
        if count > app.ui.deviceList.scroll and y <= app.ui.deviceList.y + app.ui.deviceList.height then
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
    
    -- Fill remaining space
    term.setBackgroundColor(COLORS.BACKGROUND)
    while y <= app.ui.deviceList.y + app.ui.deviceList.height do
        term.setCursorPos(app.ui.deviceList.x, y)
        term.write(string.rep(" ", app.ui.deviceList.width))
        y = y + 1
    end
end

-- Draw message history
local function drawMessagePanel()
    if not app.selected or not app.devices[app.selected] then
        -- No device selected, show instructions
        term.setBackgroundColor(COLORS.BACKGROUND)
        term.setTextColor(COLORS.TEXT)
        term.setCursorPos(app.ui.messagePanel.x, app.ui.messagePanel.y + 2)
        term.write("Select a device to")
        term.setCursorPos(app.ui.messagePanel.x, app.ui.messagePanel.y + 3)
        term.write("view and send messages.")
        return
    end
    
    local device = app.devices[app.selected]
    local messages = device.messages or {}
    local y = app.ui.messagePanel.y + app.ui.messagePanel.height
    
    -- Clear message panel
    for cy = app.ui.messagePanel.y, app.ui.messagePanel.y + app.ui.messagePanel.height do
        term.setCursorPos(app.ui.messagePanel.x, cy)
        term.setBackgroundColor(COLORS.BACKGROUND)
        term.write(string.rep(" ", app.ui.messagePanel.width))
    end
    
    -- Draw messages from bottom to top
    local count = 0
    for i = #messages, 1, -1 do
        local msg = messages[i]
        local lines = {}
        local prefix = ""
        
        -- Set message format based on sender
        if msg.sender == "me" then
            term.setTextColor(COLORS.MESSAGE_OUT)
            prefix = "> "
        else
            term.setTextColor(COLORS.MESSAGE_IN)
            prefix = "< "
        end
        
        -- Word wrap the message
        local wrapped = wrapText(msg.content, app.ui.messagePanel.width - #prefix - 1)
        
        -- Add each line
        for j = #wrapped, 1, -1 do
            local text = wrapped[j]
            if j == #wrapped then
                text = prefix .. text
            else
                text = "  " .. text
            end
            
            count = count + 1
            if count > app.ui.messagePanel.scroll then
                y = y - 1
                if y >= app.ui.messagePanel.y then
                    term.setCursorPos(app.ui.messagePanel.x, y)
                    term.setBackgroundColor(COLORS.BACKGROUND)
                    term.write(text)
                end
            end
        end
        
        -- Add timestamp if we have space
        if y > app.ui.messagePanel.y then
            local timestamp = textutils.formatTime(msg.timestamp, true)
            y = y - 1
            term.setCursorPos(app.ui.messagePanel.x, y)
            term.setTextColor(colors.gray)
            term.write(timestamp)
        end
        
        -- Stop if we've filled the panel
        if y <= app.ui.messagePanel.y then
            break
        end
    end
end

-- Draw input field
local function drawInputBar()
    term.setCursorPos(app.ui.messagePanel.x, app.ui.inputBar.y + 1)
    term.setBackgroundColor(COLORS.BACKGROUND)
    term.setTextColor(COLORS.TEXT)
    
    -- Clear input area
    term.write(string.rep(" ", app.ui.messagePanel.width))
    
    -- Show input prompt if a device is selected
    if app.selected and app.devices[app.selected] then
        term.setCursorPos(app.ui.messagePanel.x, app.ui.inputBar.y + 1)
        term.write("> " .. app.messageInput)
    end
end

-- Draw status bar
local function drawStatusBar()
    term.setCursorPos(app.ui.statusBar.x, app.ui.statusBar.y)
    term.setBackgroundColor(COLORS.BORDER)
    term.setTextColor(COLORS.TEXT)
    
    local deviceCount = 0
    local connectedCount = 0
    for _, device in pairs(app.devices) do
        deviceCount = deviceCount + 1
        if device.connected then
            connectedCount = connectedCount + 1
        end
    end
    
    local status = string.format("Devices: %d connected, %d total | Hub ID: %d", 
        connectedCount, deviceCount, modem.deviceID)
    
    -- Add help text
    local help = "ENTER: Send | F1: Help | F5: Refresh | ESC: Exit"
    local padding = app.width - #status - #help
    
    if padding > 0 then
        term.write(status .. string.rep(" ", padding) .. help)
    else
        term.write(status)
    end
end

-- Draw help screen
local function drawHelpScreen()
    term.setBackgroundColor(COLORS.BACKGROUND)
    term.clear()
    
    term.setTextColor(COLORS.TITLE)
    term.setCursorPos(1, 1)
    term.write(string.rep("=", app.width))
    term.setCursorPos(math.floor((app.width - 12) / 2), 1)
    term.write(" HELP SCREEN ")
    term.setCursorPos(1, 2)
    term.write(string.rep("=", app.width))
    
    term.setTextColor(COLORS.TEXT)
    local help = {
        "",
        "KEYBOARD SHORTCUTS:",
        "  Arrow Up/Down - Navigate device list",
        "  Enter - Send message to selected device",
        "  F1 - Show/hide this help screen",
        "  F5 - Refresh device list (send discovery ping)",
        "  ESC - Exit application",
        "",
        "DEVICE STATUSES:",
        "  " .. string.char(7) .. " Green - Device is currently connected",
        "  " .. string.char(7) .. " Red - Device has timed out or disconnected",
        "",
        "COMMANDS:",
        "  /name [new name] - Rename the selected device locally",
        "  /clear - Clear message history with selected device",
        "  /ping - Send ping to selected device",
        "  !command - Send command to turtle (e.g. !forward, !turnLeft)",
        "",
        "Press any key to return..."
    }
    
    for i, line in ipairs(help) do
        term.setCursorPos(3, i + 3)
        term.write(line)
    end
end

-- Update the UI
local function updateUI()
    if app.mode == "help" then
        drawHelpScreen()
        return
    end
    
    drawBorder()
    drawDeviceList()
    drawMessagePanel()
    drawInputBar()
    drawStatusBar()
end

-- Handle input events
local function handleKeyEvent(key, held)
    if app.mode == "help" then
        app.mode = "main"
        return true
    end
    
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
    elseif key == keys.f1 then
        -- Show help screen
        app.mode = "help"
    elseif key == keys.f5 then
        -- Refresh devices
        modem.broadcastDiscovery()
    elseif key == keys.enter then
        -- Send message
        if app.messageInput ~= "" and app.selected then
            -- Check for commands
            if app.messageInput:sub(1,1) == "/" then
                local cmd = app.messageInput:match("^/(%w+)")
                local arg = app.messageInput:match("^/%w+ (.+)$")
                
                if cmd == "name" and arg then
                    -- Rename device
                    if app.devices[app.selected] then
                        app.devices[app.selected].name = arg
                    end
                elseif cmd == "clear" then
                    -- Clear messages
                    if app.devices[app.selected] then
                        app.devices[app.selected].messages = {}
                    end
                elseif cmd == "ping" then
                    -- Ping device
                    sendMessageToDevice(app.selected, "/ping")
                else
                    -- Unknown command
                    if app.devices[app.selected] then
                        table.insert(app.devices[app.selected].messages, {
                            content = "Unknown command: " .. cmd,
                            sender = "system",
                            timestamp = os.time()
                        })
                    end
                end
            else
                -- Send regular message
                sendMessageToDevice(app.selected, app.messageInput)
            end
            
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
    elseif key == keys.escape then
        -- Exit application
        app.running = false
    end
    
    return true
end

local function handleCharEvent(char)
    if app.mode == "main" then
        app.messageInput = app.messageInput .. char
    end
    return true
end

local function handleMouseEvent(button, x, y)
    if app.mode == "help" then
        app.mode = "main"
        return true
    end
    
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
    
    return true
end

-- Initialize app
local function initialize()
    -- Initialize modem first
    if not modem.init() then
        error("Failed to initialize modem")
    end
    
    -- Set up UI dimensions
    app.width, app.height = term.getSize()
    app.ui.deviceList.height = app.height - 6
    app.ui.messagePanel.width = app.width - app.ui.deviceList.width - 3
    app.ui.messagePanel.height = app.height - 8
    app.ui.statusBar.y = app.height - 2
    app.ui.inputBar.y = app.height - 3
    
    -- Send initial discovery ping
    modem.broadcastDiscovery()
    
    return true
end

-- Main event loop
local function mainLoop()
    while app.running do
        updateUI()
        
        -- Check for device timeouts
        checkDeviceTimeouts()
        
        -- Send periodic discovery pings
        if os.time() - modem.lastPingTime > 30 then
            modem.broadcastDiscovery()
        end
        
        -- Poll for events with a short timeout
        local event = {os.pullEvent()}
        
        if event[1] == "key" then
            handleKeyEvent(event[2], event[3])
        elseif event[1] == "char" then
            handleCharEvent(event[2])
        elseif event[1] == "mouse_click" then
            handleMouseEvent(event[2], event[3], event[4])
        elseif event[1] == "rednet_message" then
            local senderId, message, protocol = event[2], event[3], event[4]
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
    
    print("Initialization complete. Starting main loop...")
    
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