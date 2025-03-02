-- Define the sorting turtle module
local sortingTurtle = {}

-- Import the LLM module
local llm = require("llm")

-- Configuration
sortingTurtle.config = {
    SCAN_INTERVAL = 300,  -- Rescan every 5 minutes
    MIN_FUEL_LEVEL = 100,  -- Minimum fuel level before refueling
    MAX_STEPS = 16,  -- Maximum steps to search for barrels
    FUEL_ITEMS = {  -- Items that can be used as fuel
        ["minecraft:coal"] = true,
        ["minecraft:charcoal"] = true,
        ["minecraft:coal_block"] = true,
        ["minecraft:lava_bucket"] = true
    }
}

-- Store information about discovered barrels
sortingTurtle.barrels = {}
sortingTurtle.numBarrels = 0
sortingTurtle.lastScanTime = 0
sortingTurtle.position = { x = 0, y = 0, z = 0, facing = 0 }  -- 0=north, 1=east, 2=south, 3=west

-- After the configuration section, add new environment tracking
sortingTurtle.environment = {
    blocks = {},  -- Will store block information in a 3D grid
    lastScan = {},  -- Last scan results
    SCAN_RADIUS = 4  -- How far to scan in each direction
}

-- Function to check if a block is a barrel
function sortingTurtle.isBarrel()
    local success, data = turtle.inspect()
    if success and data then
        -- Print detected block for debugging
        print("Detected block:", data.name)
        -- Check for various barrel types
        return data.name == "minecraft:barrel" or 
               data.name:find("barrel") or 
               data.name:find("storage")
    end
    return false
end

-- Function to read barrel contents
function sortingTurtle.readBarrel()
    local contents = {
        name = "empty",
        displayName = "empty",
        category = "none"
    }
    
    -- Save current selected slot
    local currentSlot = turtle.getSelectedSlot()
    
    -- Try to suck one item to get its details
    if turtle.suck(1) then
        local item = turtle.getItemDetail()
        if item then
            contents = {
                name = item.name or "unknown",
                displayName = item.displayName or item.name or "unknown",
                category = sortingTurtle.getItemCategory(item.name or "unknown")
            }
            -- Put the item back
            turtle.drop(1)
        end
    end
    
    -- Restore selected slot
    turtle.select(currentSlot)
    return contents
end

-- Function to categorize items (helps with grouping similar items)
function sortingTurtle.getItemCategory(itemName)
    if not itemName then return "unknown" end
    
    local categories = {
        wood = {"log", "plank", "wood"},
        stone = {"stone", "cobble", "granite", "diorite", "andesite"},
        ore = {"ore", "ingot", "raw_"},
        crop = {"seed", "sapling", "flower", "wheat", "carrot", "potato"},
        tool = {"pickaxe", "axe", "shovel", "hoe", "sword"},
        redstone = {"redstone", "repeater", "comparator", "piston"},
    }
    
    for category, keywords in pairs(categories) do
        for _, keyword in ipairs(keywords) do
            if itemName:find(keyword) then
                return category
            end
        end
    end
    return "misc"
end

-- Function to check and maintain fuel levels
function sortingTurtle.checkFuel()
    local fuelLevel = turtle.getFuelLevel()
    if fuelLevel == "unlimited" then return true end
    
    print(string.format("Current fuel level: %d", fuelLevel))
    if fuelLevel < sortingTurtle.config.MIN_FUEL_LEVEL then
        print("Fuel level low, attempting to refuel...")
        -- Check inventory for fuel items
        for slot = 1, 16 do
            turtle.select(slot)
            local item = turtle.getItemDetail()
            if item and sortingTurtle.config.FUEL_ITEMS[item.name] then
                if turtle.refuel(1) then
                    print(string.format("Refueled with %s. New level: %d", item.name, turtle.getFuelLevel()))
                    return true
                end
            end
        end
        print("WARNING: No fuel items found!")
        return false
    end
    return true
end

-- Function to detect surroundings
function sortingTurtle.detectSurroundings()
    local surroundings = {
        front = { exists = turtle.detect(), block = nil },
        up = { exists = turtle.detectUp(), block = nil },
        down = { exists = turtle.detectDown(), block = nil }
    }
    
    -- Get block information
    if surroundings.front.exists then
        local success, data = turtle.inspect()
        if success then surroundings.front.block = data end
    end
    if surroundings.up.exists then
        local success, data = turtle.inspectUp()
        if success then surroundings.up.block = data end
    end
    if surroundings.down.exists then
        local success, data = turtle.inspectDown()
        if success then surroundings.down.block = data end
    end
    
    return surroundings
end

-- Function to update position after movement
function sortingTurtle.updatePosition(movement)
    if movement == "forward" then
        if sortingTurtle.position.facing == 0 then
            sortingTurtle.position.z = sortingTurtle.position.z - 1
        elseif sortingTurtle.position.facing == 1 then
            sortingTurtle.position.x = sortingTurtle.position.x + 1
        elseif sortingTurtle.position.facing == 2 then
            sortingTurtle.position.z = sortingTurtle.position.z + 1
        else
            sortingTurtle.position.x = sortingTurtle.position.x - 1
        end
    elseif movement == "back" then
        if sortingTurtle.position.facing == 0 then
            sortingTurtle.position.z = sortingTurtle.position.z + 1
        elseif sortingTurtle.position.facing == 1 then
            sortingTurtle.position.x = sortingTurtle.position.x - 1
        elseif sortingTurtle.position.facing == 2 then
            sortingTurtle.position.z = sortingTurtle.position.z - 1
        else
            sortingTurtle.position.x = sortingTurtle.position.x + 1
        end
    elseif movement == "up" then
        sortingTurtle.position.y = sortingTurtle.position.y + 1
    elseif movement == "down" then
        sortingTurtle.position.y = sortingTurtle.position.y - 1
    elseif movement == "turnRight" then
        sortingTurtle.position.facing = (sortingTurtle.position.facing + 1) % 4
    elseif movement == "turnLeft" then
        sortingTurtle.position.facing = (sortingTurtle.position.facing - 1) % 4
    end
end

-- Enhanced movement functions with position tracking and obstacle detection
function sortingTurtle.safeMove(movement)
    if not sortingTurtle.checkFuel() then
        print("Cannot move: Insufficient fuel!")
        return false
    end
    
    local success = false
    if movement == "forward" then
        success = turtle.forward()
    elseif movement == "back" then
        success = turtle.back()
    elseif movement == "up" then
        success = turtle.up()
    elseif movement == "down" then
        success = turtle.down()
    elseif movement == "turnRight" then
        turtle.turnRight()
        success = true
    elseif movement == "turnLeft" then
        turtle.turnLeft()
        success = true
    end
    
    if success then
        sortingTurtle.updatePosition(movement)
        return true
    else
        print(string.format("Movement failed: %s", movement))
        return false
    end
end

-- Function to return to home position
function sortingTurtle.returnHome()
    print("Returning to home position...")
    
    -- First, handle Y position
    while sortingTurtle.position.y > 0 do
        if not sortingTurtle.safeMove("down") then break end
    end
    while sortingTurtle.position.y < 0 do
        if not sortingTurtle.safeMove("up") then break end
    end
    
    -- Turn to face the right direction for X movement
    if sortingTurtle.position.x > 0 then
        while sortingTurtle.position.facing ~= 3 do  -- Face west
            sortingTurtle.safeMove("turnLeft")
        end
    elseif sortingTurtle.position.x < 0 then
        while sortingTurtle.position.facing ~= 1 do  -- Face east
            sortingTurtle.safeMove("turnLeft")
        end
    end
    
    -- Move in X direction
    while sortingTurtle.position.x ~= 0 do
        if sortingTurtle.position.x > 0 then
            if not sortingTurtle.safeMove("forward") then break end
        else
            if not sortingTurtle.safeMove("forward") then break end
        end
    end
    
    -- Turn to face the right direction for Z movement
    if sortingTurtle.position.z > 0 then
        while sortingTurtle.position.facing ~= 0 do  -- Face north
            sortingTurtle.safeMove("turnLeft")
        end
    elseif sortingTurtle.position.z < 0 then
        while sortingTurtle.position.facing ~= 2 do  -- Face south
            sortingTurtle.safeMove("turnLeft")
        end
    end
    
    -- Move in Z direction
    while sortingTurtle.position.z ~= 0 do
        if sortingTurtle.position.z > 0 then
            if not sortingTurtle.safeMove("forward") then break end
        else
            if not sortingTurtle.safeMove("forward") then break end
        end
    end
    
    -- Face north (default position)
    while sortingTurtle.position.facing ~= 0 do
        sortingTurtle.safeMove("turnLeft")
    end
    
    if sortingTurtle.position.x == 0 and sortingTurtle.position.y == 0 and 
       sortingTurtle.position.z == 0 and sortingTurtle.position.facing == 0 then
        print("Successfully returned home!")
        return true
    else
        print("Warning: Could not return to exact home position!")
        print(string.format("Current position: x=%d, y=%d, z=%d, facing=%d",
            sortingTurtle.position.x, sortingTurtle.position.y,
            sortingTurtle.position.z, sortingTurtle.position.facing))
        return false
    end
end

-- Function to check inventory space
function sortingTurtle.hasInventorySpace()
    for slot = 1, 16 do
        if turtle.getItemCount(slot) == 0 then
            return true
        end
    end
    return false
end

-- Function to count empty slots
function sortingTurtle.countEmptySlots()
    local count = 0
    for slot = 1, 16 do
        if turtle.getItemCount(slot) == 0 then
            count = count + 1
        end
    end
    return count
end

-- Function to get total items in inventory
function sortingTurtle.getTotalItems()
    local total = 0
    for slot = 1, 16 do
        total = total + turtle.getItemCount(slot)
    end
    return total
end

-- Function to perform a 360-degree scan
function sortingTurtle.scan360()
    local scan = {
        north = {},
        east = {},
        south = {},
        west = {},
        up = turtle.detectUp(),
        down = turtle.detectDown(),
        upBlock = nil,
        downBlock = nil
    }
    
    -- Get up/down block data
    if scan.up then
        local success, data = turtle.inspectUp()
        if success then scan.upBlock = data end
    end
    if scan.down then
        local success, data = turtle.inspectDown()
        if success then scan.downBlock = data end
    end
    
    -- Store original facing direction
    local originalFacing = sortingTurtle.position.facing
    
    -- Scan in all four directions
    for i = 0, 3 do
        local direction = ({"north", "east", "south", "west"})[i + 1]
        local success, data = turtle.inspect()
        scan[direction] = {
            exists = success,
            block = data
        }
        sortingTurtle.safeMove("turnRight")
    end
    
    -- Return to original facing direction
    while sortingTurtle.position.facing ~= originalFacing do
        sortingTurtle.safeMove("turnRight")
    end
    
    sortingTurtle.lastScan = scan
    return scan
end

-- Function to analyze surroundings and find interesting blocks
function sortingTurtle.analyzeSurroundings()
    local scan = sortingTurtle.scan360()
    local findings = {
        barrels = {},
        chests = {},
        obstacles = {},
        interesting = {}
    }
    
    -- Helper function to categorize a block
    local function categorizeBlock(block, direction, distance)
        if not block then return end
        
        local info = {
            name = block.name,
            direction = direction,
            distance = distance or 1
        }
        
        if block.name:find("barrel") or block.name:find("storage") then
            table.insert(findings.barrels, info)
        elseif block.name:find("chest") then
            table.insert(findings.chests, info)
        elseif block.name ~= "minecraft:air" then
            table.insert(findings.obstacles, info)
        end
        
        -- Add any special blocks you want to track
        if block.name:find("diamond") or block.name:find("chest") or
           block.name:find("furnace") or block.name:find("crafting") then
            table.insert(findings.interesting, info)
        end
    end
    
    -- Analyze each direction
    for direction, data in pairs(scan) do
        if direction ~= "up" and direction ~= "down" and data.block then
            categorizeBlock(data.block, direction)
        end
    end
    
    -- Analyze up/down
    if scan.upBlock then categorizeBlock(scan.upBlock, "up") end
    if scan.downBlock then categorizeBlock(scan.downBlock, "down") end
    
    return findings
end

-- Function to map current position
function sortingTurtle.mapPosition()
    local surroundings = sortingTurtle.analyzeSurroundings()
    local pos = sortingTurtle.position
    local key = string.format("%d,%d,%d", pos.x, pos.y, pos.z)
    
    sortingTurtle.environment.blocks[key] = {
        position = {x = pos.x, y = pos.y, z = pos.z},
        surroundings = surroundings,
        timestamp = os.epoch("local")
    }
    
    return surroundings
end

-- Add a new function for step-by-step movement with 360 scanning
function sortingTurtle.moveWithScan(movement)
    -- First do a 360 scan before moving
    print("Scanning surroundings before movement...")
    local preMoveState = sortingTurtle.mapPosition()
    
    -- Perform the movement
    local success = sortingTurtle.safeMove(movement)
    
    if success then
        -- Do another 360 scan after moving
        print("Scanning surroundings after movement...")
        local postMoveState = sortingTurtle.mapPosition()
        
        -- Compare states and report any changes
        local changes = {
            newBarrels = 0,
            newObstacles = 0,
            newInteresting = 0
        }
        
        if postMoveState.barrels and #postMoveState.barrels > 0 then
            changes.newBarrels = #postMoveState.barrels
        end
        if postMoveState.obstacles and #postMoveState.obstacles > 0 then
            changes.newObstacles = #postMoveState.obstacles
        end
        if postMoveState.interesting and #postMoveState.interesting > 0 then
            changes.newInteresting = #postMoveState.interesting
        end
        
        if changes.newBarrels > 0 or changes.newObstacles > 0 or changes.newInteresting > 0 then
            print("Environment changes detected:")
            if changes.newBarrels > 0 then print("  - Found " .. changes.newBarrels .. " barrels") end
            if changes.newObstacles > 0 then print("  - Found " .. changes.newObstacles .. " obstacles") end
            if changes.newInteresting > 0 then print("  - Found " .. changes.newInteresting .. " interesting blocks") end
        end
    end
    
    return success
end

-- Modify the scanBarrels function to use enhanced movement and scanning
function sortingTurtle.scanBarrels()
    print("\n=== Starting Enhanced Barrel Scan ===")
    sortingTurtle.barrels = {}
    sortingTurtle.numBarrels = 0
    local steps = 0
    
    -- Check fuel before starting
    if not sortingTurtle.checkFuel() then
        print("Cannot scan: Insufficient fuel!")
        return
    end
    
    -- Initial 360 scan at starting position
    print("Performing initial environment scan...")
    local initialScan = sortingTurtle.mapPosition()
    print(string.format("Found %d interesting blocks nearby", 
        #initialScan.interesting))
    
    -- Turn right to start scanning
    print("Turning right to scan...")
    sortingTurtle.moveWithScan("turnRight")
    
    -- First pass: Move forward and count barrels with enhanced scanning
    print("First pass: Scanning environment and counting barrels...")
    while steps < sortingTurtle.config.MAX_STEPS do
        -- Perform 360 scan at current position
        local scan = sortingTurtle.mapPosition()
        
        -- Check for barrels in the scan
        if #scan.barrels > 0 then
            for _, barrel in ipairs(scan.barrels) do
                if barrel.direction == "front" then
                    steps = steps + 1
                    print(string.format("Found barrel at position %d (%s)", 
                        steps, barrel.name))
                    
                    table.insert(sortingTurtle.barrels, {
                        position = steps,
                        contents = {
                            name = "unknown",
                            displayName = "unknown",
                            category = "unknown"
                        },
                        blockData = barrel
                    })
                    sortingTurtle.numBarrels = sortingTurtle.numBarrels + 1
                end
            end
        end
        
        -- Move forward with 360 scan
        if not sortingTurtle.moveWithScan("forward") then
            print("Path blocked at step " .. steps)
            break
        end
    end
    
    -- Return to start using position tracking with scanning
    print("\nReturning to home position with environment scanning...")
    sortingTurtle.returnHomeWithScanning()
    
    -- If we found barrels, do a second pass to read contents
    if sortingTurtle.numBarrels > 0 then
        print("\nSecond pass: Reading barrel contents...")
        sortingTurtle.moveWithScan("turnRight")
        
        for i = 1, sortingTurtle.numBarrels do
            print(string.format("\nMoving to barrel %d with continuous scanning...", i))
            -- Move to barrel
            for j = 1, sortingTurtle.barrels[i].position do
                if not sortingTurtle.moveWithScan("forward") then
                    print("Error reaching barrel " .. i)
                    break
                end
            end
            
            -- Read contents
            print("Reading barrel contents...")
            local contents = sortingTurtle.readBarrel()
            sortingTurtle.barrels[i].contents = contents
            print(string.format("Barrel %d contains: %s (%s)", 
                i, 
                contents.displayName or "empty", 
                contents.category or "none"))
            
            -- Return to start with scanning
            sortingTurtle.returnHomeWithScanning()
            if i < sortingTurtle.numBarrels then
                sortingTurtle.moveWithScan("turnRight")
            end
        end
    end
    
    sortingTurtle.lastScanTime = os.epoch("local")
    
    -- Print enhanced barrel summary with environment data
    print("\n=== Enhanced Environment Summary ===")
    print(string.format("Found %d barrels", sortingTurtle.numBarrels))
    print("\nBarrel Details:")
    for i, barrel in ipairs(sortingTurtle.barrels) do
        print(string.format("\nBarrel %d:", i))
        print(string.format("  Position: %d blocks east", barrel.position))
        print(string.format("  Block Type: %s", barrel.blockData.name))
        print(string.format("  Contents: %s", barrel.contents.displayName))
        print(string.format("  Category: %s", barrel.contents.category))
    end
    
    -- Print environment map
    print("\nEnvironment Map:")
    local blockCount = 0
    local positionsSeen = {}
    for pos, data in pairs(sortingTurtle.environment.blocks) do
        blockCount = blockCount + 1
        table.insert(positionsSeen, pos)
    end
    print(string.format("Mapped %d unique positions", blockCount))
    print("Positions mapped:")
    for _, pos in ipairs(positionsSeen) do
        print("  - " .. pos)
    end
end

-- Add new function for returning home with continuous scanning
function sortingTurtle.returnHomeWithScanning()
    print("Returning to home position with continuous environment scanning...")
    
    -- First, handle Y position
    while sortingTurtle.position.y > 0 do
        if not sortingTurtle.moveWithScan("down") then break end
    end
    while sortingTurtle.position.y < 0 do
        if not sortingTurtle.moveWithScan("up") then break end
    end
    
    -- Turn to face the right direction for X movement
    if sortingTurtle.position.x > 0 then
        while sortingTurtle.position.facing ~= 3 do  -- Face west
            sortingTurtle.moveWithScan("turnLeft")
        end
    elseif sortingTurtle.position.x < 0 then
        while sortingTurtle.position.facing ~= 1 do  -- Face east
            sortingTurtle.moveWithScan("turnLeft")
        end
    end
    
    -- Move in X direction
    while sortingTurtle.position.x ~= 0 do
        if sortingTurtle.position.x > 0 then
            if not sortingTurtle.moveWithScan("forward") then break end
        else
            if not sortingTurtle.moveWithScan("forward") then break end
        end
    end
    
    -- Turn to face the right direction for Z movement
    if sortingTurtle.position.z > 0 then
        while sortingTurtle.position.facing ~= 0 do  -- Face north
            sortingTurtle.moveWithScan("turnLeft")
        end
    elseif sortingTurtle.position.z < 0 then
        while sortingTurtle.position.facing ~= 2 do  -- Face south
            sortingTurtle.moveWithScan("turnLeft")
        end
    end
    
    -- Move in Z direction
    while sortingTurtle.position.z ~= 0 do
        if sortingTurtle.position.z > 0 then
            if not sortingTurtle.moveWithScan("forward") then break end
        else
            if not sortingTurtle.moveWithScan("forward") then break end
        end
    end
    
    -- Face north (default position)
    while sortingTurtle.position.facing ~= 0 do
        sortingTurtle.moveWithScan("turnLeft")
    end
    
    if sortingTurtle.position.x == 0 and sortingTurtle.position.y == 0 and 
       sortingTurtle.position.z == 0 and sortingTurtle.position.facing == 0 then
        print("Successfully returned home!")
        return true
    else
        print("Warning: Could not return to exact home position!")
        print(string.format("Current position: x=%d, y=%d, z=%d, facing=%d",
            sortingTurtle.position.x, sortingTurtle.position.y,
            sortingTurtle.position.z, sortingTurtle.position.facing))
        return false
    end
end

-- Modify moveToBarrel to use scanning
function sortingTurtle.moveToBarrel(slot)
    if not sortingTurtle.barrels[slot] then
        print("Invalid barrel slot: " .. slot)
        return false
    end
    
    print(string.format("Moving to barrel %d at position %d with continuous scanning", 
        slot, sortingTurtle.barrels[slot].position))
    
    sortingTurtle.moveWithScan("turnRight")
    for i = 1, sortingTurtle.barrels[slot].position do
        if not sortingTurtle.moveWithScan("forward") then
            print("Failed to reach barrel!")
            return false
        end
    end
    sortingTurtle.moveWithScan("turnLeft")
    return true
end

-- Modify returnToChest to use scanning
function sortingTurtle.returnToChest()
    print("Returning to input chest with continuous scanning...")
    sortingTurtle.moveWithScan("turnLeft")
    for i = 1, sortingTurtle.numBarrels do
        if not sortingTurtle.moveWithScan("back") then
            print("Warning: Failed to return completely!")
            break
        end
    end
    sortingTurtle.moveWithScan("turnRight")
end

-- Function to determine which barrel slot to use based on item name using LLM
function sortingTurtle.getBarrelSlot(itemName, itemCategory)
    if sortingTurtle.numBarrels == 0 then
        return nil
    end

    -- Create a detailed context for the LLM
    local barrelContext = "Current barrel contents:\n"
    for i, barrel in ipairs(sortingTurtle.barrels) do
        barrelContext = barrelContext .. string.format("Barrel %d: %s (category: %s)\n", 
            i, 
            barrel.contents.displayName or "empty", 
            barrel.contents.category or "none")
    end
    
    -- Construct a more specific prompt
    local prompt = string.format([[
Return ONLY a number between 1 and %d.
Item to sort: "%s" (category: %s)
%s
Rules:
- If exact item match exists, use that barrel number
- If empty barrel exists, use first empty barrel
- If similar category exists, use that barrel
- ONLY return the number, no other text

Number:]], 
        sortingTurtle.numBarrels,
        itemName, 
        itemCategory,
        barrelContext)

    local response = llm.getGeminiResponse(prompt)
    
    if response then
        -- Clean up response to ensure we only get a number
        response = response:match("^%s*(%d+)%s*$")
        local barrelSlot = tonumber(response)
        if barrelSlot and barrelSlot >= 1 and barrelSlot <= sortingTurtle.numBarrels then
            return barrelSlot
        else
            print("Invalid barrel number from LLM: " .. (response or "nil"))
        end
    else
        print("No response received from LLM.")
    end
    return nil
end

-- Function to move items from input chest to barrels
function sortingTurtle.sortItems()
    -- Check if we need to rescan barrels
    local currentTime = os.epoch("local")
    if sortingTurtle.numBarrels == 0 or 
       (currentTime - sortingTurtle.lastScanTime) > sortingTurtle.config.SCAN_INTERVAL then
        sortingTurtle.scanBarrels()
        if sortingTurtle.numBarrels == 0 then
            print("No barrels found! Please set up barrels and restart.")
            return
        end
    end
    
    print("\nChecking input chest...")
    -- Move to the input chest
    if not turtle.forward() then
        print("Cannot reach input chest!")
        return
    end

    -- Check each slot in the turtle's inventory
    for slot = 1, 16 do
        turtle.select(slot)
        if turtle.suck() then  -- Attempt to take items from the chest
            local itemDetail = turtle.getItemDetail()
            if itemDetail then
                local itemCategory = sortingTurtle.getItemCategory(itemDetail.name)
                print(string.format("\nProcessing: %s (Category: %s)", 
                    itemDetail.displayName or "unknown", 
                    itemCategory))
                
                -- Determine which barrel to place the item in
                local barrelSlot = sortingTurtle.getBarrelSlot(itemDetail.name, itemCategory)
                if barrelSlot then
                    print("Moving to barrel " .. barrelSlot)
                    -- Move to the correct barrel
                    sortingTurtle.moveToBarrel(barrelSlot)
                    -- Place the item in the barrel
                    if turtle.drop() then
                        print("Successfully placed item in barrel " .. barrelSlot)
                        -- Update barrel contents in memory
                        sortingTurtle.barrels[barrelSlot].contents = {
                            name = itemDetail.name,
                            displayName = itemDetail.displayName,
                            category = itemCategory
                        }
                    else
                        print("Failed to place item in barrel " .. barrelSlot)
                    end
                    -- Return to the input chest
                    sortingTurtle.returnToChest()
                else
                    print("No suitable barrel found, returning item to chest")
                    -- Drop item back in chest
                    turtle.drop()
                end
            end
        end
    end
    
    -- Return to starting position
    if not turtle.back() then
        print("Warning: Could not return to starting position!")
    end
end

-- Main loop
print("=== Smart Sorting Turtle v2.1 ===")
print("Setup Instructions:")
print("1. Place turtle in front of input chest")
print("2. Place barrels in a line to the right")
print("3. Ensure all barrels are accessible")
print("\nStarting initial barrel scan...")

-- Do initial barrel scan
sortingTurtle.scanBarrels()

if sortingTurtle.numBarrels == 0 then
    print("\nNo barrels found! Please set up barrels and restart the program.")
    return sortingTurtle
end

print("\nReady to sort items!")
print("Monitoring input chest...")

while true do
    sortingTurtle.sortItems()
    os.sleep(5)  -- Wait for a few seconds before checking again
end

return sortingTurtle

