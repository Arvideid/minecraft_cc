-- Import the LLM module
local llm = require("llm")

-- Coordinate tracking
local position = {x = 0, y = 0, z = 0}
local direction = 0  -- 0: north, 1: east, 2: south, 3: west

-- Store the input barrel's position and orientation
local inputBarrelPosition = {x = 0, y = 0, z = 0}
local inputBarrelDirection = 0

-- Function to update position based on direction
local function updatePosition()
    if direction == 0 then
        position.z = position.z - 1
    elseif direction == 1 then
        position.x = position.x + 1
    elseif direction == 2 then
        position.z = position.z + 1
    elseif direction == 3 then
        position.x = position.x - 1
    end
end

-- Function to move the turtle forward with position update
local function moveForward()
    if turtle.forward() then
        updatePosition()
        print("Moved forward to (" .. position.x .. ", " .. position.y .. ", " .. position.z .. ")")
    else
        print("Cannot move forward.")
    end
end

-- Function to turn the turtle left with direction update
local function turnLeft()
    turtle.turnLeft()
    direction = (direction - 1) % 4
    print("Turned left. Now facing direction " .. direction)
end

-- Function to turn the turtle right with direction update
local function turnRight()
    turtle.turnRight()
    direction = (direction + 1) % 4
    print("Turned right. Now facing direction " .. direction)
end

-- Function to check for a barrel in front
local function checkForBarrel()
    local success, data = turtle.inspect()
    if success and data.name == "minecraft:barrel" then
        print("Barrel detected.")
        return true
    else
        print("No barrel detected.")
        return false
    end
end

-- Function to refuel the turtle using items in its inventory
local function refuelTurtle()
    local slot = 16  -- Use only the last slot for refueling
    turtle.select(slot)
    if turtle.refuel(0) then  -- Check if the item in the slot can be used as fuel
        print("Refueling from slot " .. slot)
        turtle.refuel()  -- Refuel using the item
        return true
    end
    print("No fuel source found in the last inventory slot.")
    return false
end

-- Function to check fuel level and refuel if needed
local function checkFuel()
    if turtle.getFuelLevel() == 0 then
        print("Out of fuel!")
        if not refuelTurtle() then
            print("Please add fuel to the turtle's inventory.")
            return false
        end
    end
    return true
end

-- Function to get items from a barrel
local function getBarrelItems()
    local items = {}
    for slot = 1, 16 do
        turtle.select(slot)
        if turtle.suck() then
            local itemDetail = turtle.getItemDetail()
            if itemDetail then
                table.insert(items, itemDetail.name)
                print("Retrieved " .. itemDetail.count .. " of " .. itemDetail.name)
            end
        end
    end
    return items
end

-- Function to place items in a barrel
local function placeItemsInBarrel(items)
    for _, item in ipairs(items) do
        for slot = 1, 16 do
            turtle.select(slot)
            local itemDetail = turtle.getItemDetail()
            if itemDetail and itemDetail.name == item then
                turtle.drop()
                print("Placed " .. itemDetail.count .. " of " .. itemDetail.name)
                break
            end
        end
    end
end

-- Function to perform a 360-degree check for barrels
local function checkForBarrels360()
    local barrelsDetected = {}
    for i = 1, 4 do
        if checkForBarrel() then
            table.insert(barrelsDetected, {x = position.x, y = position.y, z = position.z, direction = direction})
        end
        turnRight()
    end
    return barrelsDetected
end

-- Function to check and sort items
local function checkAndSortItems(inputItems)
    local barrelItems = {}

    -- Iterate over barrels
    for i = 1, 4 do  -- Example: check 4 barrels
        local detectedBarrels = checkForBarrels360()
        for _, barrel in ipairs(detectedBarrels) do
            moveForward()
            if checkForBarrel() then
                local items = getBarrelItems()
                table.insert(barrelItems, items)
            end
        end
    end

    -- Use LLM to decide what to do with the items
    local prompt = "Input items: " .. table.concat(inputItems, ", ") .. ". "
    for index, items in ipairs(barrelItems) do
        prompt = prompt .. "Barrel " .. index .. " items: " .. table.concat(items, ", ") .. ". "
    end
    prompt = prompt .. "Decide which items should be moved to each barrel based on their contents."

    local response = llm.getGeminiResponse(prompt)
    if response then
        print("LLM response: " .. response)
        -- Parse the LLM response to determine item placement
        for index, items in ipairs(barrelItems) do
            local moveToBarrel = {}
            for item in response:gmatch("move (.-) to barrel " .. index) do
                table.insert(moveToBarrel, item)
            end
            -- Place items in the barrel
            placeItemsInBarrel(moveToBarrel)
            moveForward()
        end
    else
        print("No response from LLM.")
    end
end

-- Function to sense the environment and store input barrel position
local function senseEnvironmentAndStoreInputBarrel()
    local frontSuccess, frontData = turtle.inspect()
    if frontSuccess and frontData.name == "minecraft:barrel" then
        print("Input barrel detected at front.")
        inputBarrelPosition = {x = position.x, y = position.y, z = position.z}
        inputBarrelDirection = direction
    end
    local belowSuccess, belowData = turtle.inspectDown()
    local aboveSuccess, aboveData = turtle.inspectUp()
    print("Below: " .. (belowSuccess and belowData.name or "none"))
    print("Above: " .. (aboveSuccess and aboveData.name or "none"))
end

-- Function to navigate around the input barrel
local function navigateAroundInputBarrel()
    -- Turn around to explore other barrels
    turnRight()
    turnRight()
    print("Navigating around the input barrel.")
end

-- Main function to control the turtle
local function controlTurtle()
    while true do
        -- Check fuel level
        if not checkFuel() then
            print("Please refuel the turtle.")
            os.sleep(2)
        else
            -- Sense the environment and store input barrel position
            senseEnvironmentAndStoreInputBarrel()
            -- Scan the input barrel
            local inputItems = getBarrelItems()
            if #inputItems > 0 then
                navigateAroundInputBarrel()
                checkAndSortItems(inputItems)
            else
                print("No items in input barrel.")
            end
        end

        -- Add a delay to prevent spamming
        os.sleep(2)
    end
end

-- Start the turtle control
controlTurtle()
