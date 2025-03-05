-- modem_control.lua
-- Handles all modem communication for ComputerCraft devices

local modemControl = {}

-- Default configuration
modemControl.config = {
    PROTOCOL = "COMMNET",
    CHANNELS = {
        BROADCAST = 65535,
        DISCOVERY = 64000,
    },
    TIMEOUT = 60, -- seconds before a device is considered disconnected
}

-- Initialize modem
function modemControl.init()
    -- Find wireless modem
    local modem = peripheral.find("modem", function(_, m) return m.isWireless() end)
    if not modem then
        error("No wireless modem found. Please attach a wireless modem.")
    end
    
    modemControl.modem = modem
    modemControl.deviceID = os.getComputerID()
    modemControl.deviceName = os.getComputerLabel() or (turtle and "Turtle-" or "Computer-") .. modemControl.deviceID
    modemControl.deviceType = turtle and "turtle" or "computer"
    modemControl.lastPingTime = 0
    
    -- Open channels
    modem.open(modemControl.config.CHANNELS.BROADCAST)
    modem.open(modemControl.config.CHANNELS.DISCOVERY)
    
    -- Open rednet on this modem
    local side = peripheral.getName(modem)
    rednet.open(side)
    
    return true
end

-- Broadcast discovery ping to find other devices
function modemControl.broadcastDiscovery()
    print("Broadcasting discovery ping...")
    rednet.broadcast({
        type = "discovery_ping",
        sender = modemControl.deviceID,
        name = modemControl.deviceName,
        device_type = modemControl.deviceType,
        protocol = modemControl.config.PROTOCOL,
        timestamp = os.time()
    }, modemControl.config.PROTOCOL)
    
    modemControl.lastPingTime = os.time()
    return true
end

-- Send direct response to a discovery ping
function modemControl.respondToDiscovery(targetID)
    print("Responding to discovery from ID " .. targetID)
    rednet.send(targetID, {
        type = "discovery_response",
        sender = modemControl.deviceID,
        name = modemControl.deviceName,
        device_type = modemControl.deviceType,
        protocol = modemControl.config.PROTOCOL,
        timestamp = os.time()
    }, modemControl.config.PROTOCOL)
    
    return true
end

-- Send message to a specific device
function modemControl.sendMessage(targetID, messageContent, messageType)
    if not targetID then 
        print("Error: No target ID provided for message")
        return false 
    end
    
    print("Sending " .. (messageType or "message") .. " to ID " .. targetID)
    
    return rednet.send(targetID, {
        type = messageType or "message",
        sender = modemControl.deviceID,
        content = messageContent,
        protocol = modemControl.config.PROTOCOL,
        timestamp = os.time()
    }, modemControl.config.PROTOCOL)
end

-- Wait for and receive a message, with optional timeout
function modemControl.receiveMessage(timeout)
    print("Waiting for message with timeout " .. (timeout or "infinite"))
    local senderID, message, protocol = rednet.receive(modemControl.config.PROTOCOL, timeout)
    if senderID and message and protocol == modemControl.config.PROTOCOL and type(message) == "table" then
        print("Received valid message from ID " .. senderID)
        return senderID, message
    end
    if senderID then
        print("Received message with invalid format from ID " .. senderID)
    else
        print("No message received within timeout")
    end
    return nil, nil
end

-- Set device name
function modemControl.setDeviceName(name)
    modemControl.deviceName = name
    return true
end

-- Check if modem is connected
function modemControl.isConnected()
    return modemControl.modem ~= nil
end

-- Close connection
function modemControl.close()
    if modemControl.modem then
        local side = peripheral.getName(modemControl.modem)
        rednet.close(side)
    end
end

return modemControl 