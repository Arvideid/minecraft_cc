-- CommCentral - Communication Hub with GUI Interface
-- Allows central control of connected computers and turtles

-- Constants and configuration
local CONFIG = {
    TITLE = "CommCentral v1.0",
    REFRESH_RATE = 0.1,  -- seconds between screen refreshes
    PROTOCOL = "COMMCENTRAL",  -- protocol name for communications
    CHANNELS = {
        BROADCAST = 65535,  -- channel for broadcast messages
        DISCOVERY = 64000,  -- channel for device discovery
    },
    COLORS = {
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
}

-- Application state
local state = {
    devices = {},       -- connected devices
    messages = {},      -- message history
    selected = nil,     -- currently selected device
    modem = nil,        -- modem peripheral
    running = true,     -- application running flag
    mode = "main",      -- current UI mode (main, message, help)
    messageInput = "",  -- current message being composed
    lastPing = 0,       -- last time a ping was sent
}

-- UI elements and dimensions
local ui = {
    width = 0,
    height = 0,
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

-- Device management functions
local function addDevice(id, name, deviceType, distance)
    if not state.devices[id] then
        state.devices[id] = {
            id = id,
            name = name or "Device-" .. id,
            type = deviceType or "unknown",
            lastSeen = os.time(),
            connected = true,
            messages = {},
            distance = distance or "unknown",
        }
    else
        -- Update existing device
        state.devices[id].lastSeen = os.time()
        state.devices[id].connected = true
        if name then state.devices[id].name = name end
        if deviceType then state.devices[id].type = deviceType end
        if distance then state.devices[id].distance = distance end
    end
end

local function checkDeviceTimeouts()
    for id, device in pairs(state.devices) do
        if os.time() - device.lastSeen > 60 then -- 60 second timeout
            device.connected = false
        end
    end
end

-- Communication functions
local function sendMessage(deviceId, message)
    if not deviceId then return false end
    
    local success = rednet.send(deviceId, {
        type = "message",
        sender = os.getComputerID(),
        content = message,
        protocol = CONFIG.PROTOCOL,
        timestamp = os.time()
    }, CONFIG.PROTOCOL)
    
    if success then
        -- Add to message history
        if not state.devices[deviceId].messages then
            state.devices[deviceId].messages = {}
        end
        
        table.insert(state.devices[deviceId].messages, {
            content = message,
            sender = "me",
            timestamp = os.time()
        })
        
        return true
    end
    
    return false
end

-- Move this function BEFORE initialize
local function sendDiscoveryPing()
    rednet.broadcast({
        type = "discovery_ping",
        sender = os.getComputerID(),
        name = os.getComputerLabel() or "Computer-" .. os.getComputerID(),
        computer_type = "computer",
        protocol = CONFIG.PROTOCOL,
    }, CONFIG.PROTOCOL)
    
    state.lastPing = os.time()
end

local function respondToDiscovery(senderId)
    rednet.send(senderId, {
        type = "discovery_response",
        sender = os.getComputerID(),
        name = os.getComputerLabel() or "Computer-" .. os.getComputerID(),
        computer_type = "computer",
        protocol = CONFIG.PROTOCOL,
    }, CONFIG.PROTOCOL)
end

-- Initialize the application
local function initialize()
    -- Get terminal dimensions
    ui.width, ui.height = term.getSize()
    
    -- Calculate panel heights
    ui.deviceList.height = ui.height - 6
    ui.messagePanel.width = ui.width - ui.deviceList.width - 3
    ui.messagePanel.height = ui.height - 8
    ui.statusBar.y = ui.height - 2
    ui.inputBar.y = ui.height - 3
    
    -- Find modem
    local modems = {peripheral.find("modem", function(name, modem) return modem.isWireless() end)}
    if #modems == 0 then
        error("No wireless modem found. Please attach a wireless modem.")
    end
    state.modem = modems[1]
    
    -- Open channels
    state.modem.open(CONFIG.CHANNELS.BROADCAST)
    state.modem.open(CONFIG.CHANNELS.DISCOVERY)
    
    -- Start rednet
    local modemSide = peripheral.getName(state.modem)
    rednet.open(modemSide)
    
    -- Send initial discovery ping
    sendDiscoveryPing()
end

-- UI Drawing functions
local function drawBorder()
    term.setBackgroundColor(CONFIG.COLORS.BACKGROUND)
    term.setTextColor(CONFIG.COLORS.BORDER)
    term.clear()
    
    -- Draw title bar
    term.setCursorPos(1, 1)
    term.setBackgroundColor(CONFIG.COLORS.BORDER)
    term.setTextColor(CONFIG.COLORS.TITLE)
    term.write(string.rep(" ", ui.width))
    term.setCursorPos(math.floor((ui.width - #CONFIG.TITLE) / 2), 1)
    term.write(CONFIG.TITLE)
    
    -- Draw divider between device list and messages
    for y = 3, ui.height - 3 do
        term.setCursorPos(ui.deviceList.width + 1, y)
        term.setBackgroundColor(CONFIG.COLORS.BORDER)
        term.write(" ")
    end
    
    -- Draw status bar
    term.setCursorPos(1, ui.statusBar.y)
    term.setBackgroundColor(CONFIG.COLORS.BORDER)
    term.setTextColor(CONFIG.COLORS.TEXT)
    term.write(string.rep(" ", ui.width))
    
    -- Draw input bar divider
    term.setCursorPos(1, ui.inputBar.y)
    term.setBackgroundColor(CONFIG.COLORS.BORDER)
    term.write(string.rep(" ", ui.width))
    
    -- Draw headers
    term.setTextColor(CONFIG.COLORS.TEXT)
    term.setBackgroundColor(CONFIG.COLORS.BORDER)
    term.setCursorPos(2, 2)
    term.write("Connected Devices")
    term.setCursorPos(ui.messagePanel.x, 2)
    term.write("Messages")
    
    -- Reset colors
    term.setBackgroundColor(CONFIG.COLORS.BACKGROUND)
    term.setTextColor(CONFIG.COLORS.TEXT)
end

local function drawDeviceList()
    local y = ui.deviceList.y
    local count = 0
    local sorted = {}
    
    -- Sort devices by connection status and name
    for _, device in pairs(state.devices) do
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
        if count > ui.deviceList.scroll and y <= ui.deviceList.y + ui.deviceList.height then
            term.setCursorPos(ui.deviceList.x, y)
            
            -- Highlight selected device
            if state.selected == device.id then
                term.setBackgroundColor(CONFIG.COLORS.SELECTED)
            else
                term.setBackgroundColor(CONFIG.COLORS.BACKGROUND)
            end
            
            -- Set color based on connection status
            if device.connected then
                term.setTextColor(CONFIG.COLORS.CONNECTED)
            else
                term.setTextColor(CONFIG.COLORS.DISCONNECTED)
            end
            
            -- Draw device name with padding
            local displayName = device.name
            if #displayName > ui.deviceList.width - 4 then
                displayName = displayName:sub(1, ui.deviceList.width - 7) .. "..."
            end
            term.write(string.format(" %-" .. (ui.deviceList.width - 2) .. "s", displayName))
            
            y = y + 1
        end
    end
    
    -- Fill remaining space
    term.setBackgroundColor(CONFIG.COLORS.BACKGROUND)
    while y <= ui.deviceList.y + ui.deviceList.height do
        term.setCursorPos(ui.deviceList.x, y)
        term.write(string.rep(" ", ui.deviceList.width))
        y = y + 1
    end
end

local function drawMessagePanel()
    if not state.selected or not state.devices[state.selected] then
        -- No device selected, show instructions
        term.setBackgroundColor(CONFIG.COLORS.BACKGROUND)
        term.setTextColor(CONFIG.COLORS.TEXT)
        term.setCursorPos(ui.messagePanel.x, ui.messagePanel.y + 2)
        term.write("Select a device to")
        term.setCursorPos(ui.messagePanel.x, ui.messagePanel.y + 3)
        term.write("view and send messages.")
        return
    end
    
    local device = state.devices[state.selected]
    local messages = device.messages or {}
    local y = ui.messagePanel.y + ui.messagePanel.height
    
    -- Clear message panel
    for cy = ui.messagePanel.y, ui.messagePanel.y + ui.messagePanel.height do
        term.setCursorPos(ui.messagePanel.x, cy)
        term.setBackgroundColor(CONFIG.COLORS.BACKGROUND)
        term.write(string.rep(" ", ui.messagePanel.width))
    end
    
    -- Draw messages from bottom to top
    local count = 0
    for i = #messages, 1, -1 do
        local msg = messages[i]
        local lines = {}
        local prefix = ""
        
        -- Set message format based on sender
        if msg.sender == "me" then
            term.setTextColor(CONFIG.COLORS.MESSAGE_OUT)
            prefix = "> "
        else
            term.setTextColor(CONFIG.COLORS.MESSAGE_IN)
            prefix = "< "
        end
        
        -- Word wrap the message
        local wrapped = wrapText(msg.content, ui.messagePanel.width - #prefix - 1)
        
        -- Add each line
        for j = #wrapped, 1, -1 do
            local text = wrapped[j]
            if j == #wrapped then
                text = prefix .. text
            else
                text = "  " .. text
            end
            
            count = count + 1
            if count > ui.messagePanel.scroll then
                y = y - 1
                if y >= ui.messagePanel.y then
                    term.setCursorPos(ui.messagePanel.x, y)
                    term.setBackgroundColor(CONFIG.COLORS.BACKGROUND)
                    term.write(text)
                end
            end
        end
        
        -- Add timestamp if we have space
        if y > ui.messagePanel.y then
            local timestamp = textutils.formatTime(msg.timestamp, true)
            y = y - 1
            term.setCursorPos(ui.messagePanel.x, y)
            term.setTextColor(colors.gray)
            term.write(timestamp)
        end
        
        -- Stop if we've filled the panel
        if y <= ui.messagePanel.y then
            break
        end
    end
end

-- Utility function to wrap text
function wrapText(text, width)
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

local function drawInputBar()
    term.setCursorPos(ui.messagePanel.x, ui.inputBar.y + 1)
    term.setBackgroundColor(CONFIG.COLORS.BACKGROUND)
    term.setTextColor(CONFIG.COLORS.TEXT)
    
    -- Clear input area
    term.write(string.rep(" ", ui.messagePanel.width))
    
    -- Show input prompt if a device is selected
    if state.selected and state.devices[state.selected] then
        term.setCursorPos(ui.messagePanel.x, ui.inputBar.y + 1)
        term.write("> " .. state.messageInput)
    end
end

local function drawStatusBar()
    term.setCursorPos(ui.statusBar.x, ui.statusBar.y)
    term.setBackgroundColor(CONFIG.COLORS.BORDER)
    term.setTextColor(CONFIG.COLORS.TEXT)
    
    local deviceCount = 0
    local connectedCount = 0
    for _, device in pairs(state.devices) do
        deviceCount = deviceCount + 1
        if device.connected then
            connectedCount = connectedCount + 1
        end
    end
    
    local status = string.format("Devices: %d connected, %d total | Computer ID: %d", 
        connectedCount, deviceCount, os.getComputerID())
    
    -- Add help text
    local help = "ENTER: Send | F1: Help | F5: Refresh | ESC: Exit"
    local padding = ui.width - #status - #help
    
    if padding > 0 then
        term.write(status .. string.rep(" ", padding) .. help)
    else
        term.write(status)
    end
end

local function drawHelpScreen()
    term.setBackgroundColor(CONFIG.COLORS.BACKGROUND)
    term.clear()
    
    term.setTextColor(CONFIG.COLORS.TITLE)
    term.setCursorPos(1, 1)
    term.write(string.rep("=", ui.width))
    term.setCursorPos(math.floor((ui.width - 12) / 2), 1)
    term.write(" HELP SCREEN ")
    term.setCursorPos(1, 2)
    term.write(string.rep("=", ui.width))
    
    term.setTextColor(CONFIG.COLORS.TEXT)
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
        "",
        "Press any key to return..."
    }
    
    for i, line in ipairs(help) do
        term.setCursorPos(3, i + 3)
        term.write(line)
    end
end

-- Main UI update function
local function updateUI()
    if state.mode == "help" then
        drawHelpScreen()
        return
    end
    
    drawBorder()
    drawDeviceList()
    drawMessagePanel()
    drawInputBar()
    drawStatusBar()
end

-- Handle user input
local function handleKeyEvent(key, held)
    if state.mode == "help" then
        state.mode = "main"
        return true
    end
    
    if key == keys.up then
        -- Navigate device list up
        if ui.deviceList.scroll > 0 then
            ui.deviceList.scroll = ui.deviceList.scroll - 1
        end
    elseif key == keys.down then
        -- Navigate device list down
        local deviceCount = 0
        for _ in pairs(state.devices) do deviceCount = deviceCount + 1 end
        if deviceCount > ui.deviceList.height and ui.deviceList.scroll < deviceCount - ui.deviceList.height then
            ui.deviceList.scroll = ui.deviceList.scroll + 1
        end
    elseif key == keys.f1 then
        -- Show help screen
        state.mode = "help"
    elseif key == keys.f5 then
        -- Refresh devices
        sendDiscoveryPing()
    elseif key == keys.enter then
        -- Send message
        if state.messageInput ~= "" and state.selected then
            -- Check for commands
            if state.messageInput:sub(1,1) == "/" then
                local cmd = state.messageInput:match("^/(%w+)")
                local arg = state.messageInput:match("^/%w+ (.+)$")
                
                if cmd == "name" and arg then
                    -- Rename device
                    if state.devices[state.selected] then
                        state.devices[state.selected].name = arg
                    end
                elseif cmd == "clear" then
                    -- Clear messages
                    if state.devices[state.selected] then
                        state.devices[state.selected].messages = {}
                    end
                elseif cmd == "ping" then
                    -- Ping device
                    sendMessage(state.selected, "/ping")
                else
                    -- Unknown command
                    if state.devices[state.selected] then
                        table.insert(state.devices[state.selected].messages, {
                            content = "Unknown command: " .. cmd,
                            sender = "system",
                            timestamp = os.time()
                        })
                    end
                end
            else
                -- Send regular message
                sendMessage(state.selected, state.messageInput)
            end
            
            state.messageInput = ""
        end
    elseif key == keys.backspace then
        -- Delete character from message
        if #state.messageInput > 0 then
            state.messageInput = state.messageInput:sub(1, -2)
        end
    elseif key == keys.tab then
        -- Cycle through connected devices
        local connectedDevices = {}
        for id, device in pairs(state.devices) do
            if device.connected then
                table.insert(connectedDevices, id)
            end
        end
        
        table.sort(connectedDevices)
        
        if #connectedDevices > 0 then
            if not state.selected then
                state.selected = connectedDevices[1]
            else
                local index = nil
                for i, id in ipairs(connectedDevices) do
                    if id == state.selected then
                        index = i
                        break
                    end
                end
                
                if index then
                    state.selected = connectedDevices[(index % #connectedDevices) + 1]
                else
                    state.selected = connectedDevices[1]
                end
            end
        end
    elseif key == keys.escape then
        -- Exit application
        state.running = false
    end
    
    return true
end

local function handleCharEvent(char)
    if state.mode == "main" then
        state.messageInput = state.messageInput .. char
    end
    return true
end

local function handleMouseEvent(button, x, y)
    if state.mode == "help" then
        state.mode = "main"
        return true
    end
    
    -- Check if click was in the device list
    if x >= ui.deviceList.x and x < ui.deviceList.x + ui.deviceList.width and
       y >= ui.deviceList.y and y < ui.deviceList.y + ui.deviceList.height then
        -- Find which device was clicked
        local deviceIndex = y - ui.deviceList.y + ui.deviceList.scroll
        
        -- Get sorted list of devices
        local sorted = {}
        for _, device in pairs(state.devices) do
            table.insert(sorted, device)
        end
        
        table.sort(sorted, function(a, b)
            if a.connected ~= b.connected then
                return a.connected
            end
            return a.name < b.name
        end)
        
        if sorted[deviceIndex] then
            state.selected = sorted[deviceIndex].id
        end
    end
    
    return true
end

-- Message handling
local function handleMessage(senderId, message, protocol)
    if type(message) ~= "table" or message.protocol ~= CONFIG.PROTOCOL then
        return
    end
    
    if message.type == "discovery_ping" then
        -- Respond to discovery pings
        respondToDiscovery(senderId)
        -- Also add the sender to our device list
        addDevice(senderId, message.name, message.computer_type)
    elseif message.type == "discovery_response" then
        -- Add responding device to our list
        addDevice(senderId, message.name, message.computer_type)
    elseif message.type == "message" then
        -- Add message to conversation
        addDevice(senderId) -- Ensure device exists
        
        if not state.devices[senderId].messages then
            state.devices[senderId].messages = {}
        end
        
        table.insert(state.devices[senderId].messages, {
            content = message.content,
            sender = "them",
            timestamp = os.time()
        })
        
        -- If it's a ping response, update ping time
        if message.content == "/ping_response" then
            state.devices[senderId].pingTime = os.time() - (state.devices[senderId].pingStart or os.time())
        end
        
        -- Auto-respond to pings
        if message.content == "/ping" then
            sendMessage(senderId, "/ping_response")
        end
    end
end

-- Main event loop
local function eventLoop()
    while state.running do
        updateUI()
        
        -- Check for device timeouts
        checkDeviceTimeouts()
        
        -- Send discovery ping every 30 seconds
        if os.time() - state.lastPing > 30 then
            sendDiscoveryPing()
        end
        
        -- Listen for events
        local event = {os.pullEvent(nil)}
        
        if event[1] == "key" then
            handleKeyEvent(event[2], event[3])
        elseif event[1] == "char" then
            handleCharEvent(event[2])
        elseif event[1] == "mouse_click" then
            handleMouseEvent(event[2], event[3], event[4])
        elseif event[1] == "rednet_message" then
            local senderId, message, protocol = event[2], event[3], event[4]
            handleMessage(senderId, message, protocol)
        end
    end
end

-- Application startup
local function main()
    term.clear()
    term.setCursorPos(1,1)
    
    -- Initialize application
    initialize()
    
    -- Run event loop
    parallel.waitForAny(
        eventLoop,
        function()
            -- Background tasks
            while state.running do
                sleep(1)
            end
        end
    )
    
    -- Cleanup
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
    term.clear()
    term.setCursorPos(1,1)
    print("CommCentral terminated.")
end

-- Start the application
main() 