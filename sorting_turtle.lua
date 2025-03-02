-- Import the LLM module
local llm = require("llm")

-- Function to move the turtle forward
local function moveForward()
    if turtle.forward() then
        print("Moved forward.")
    else
        print("Cannot move forward.")
    end
end

-- Function to turn the turtle left
local function turnLeft()
    turtle.turnLeft()
    print("Turned left.")
end

-- Function to turn the turtle right
local function turnRight()
    turtle.turnRight()
    print("Turned right.")
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

-- Main function to control the turtle
local function controlTurtle()
    while true do
        -- Check fuel level
        if not checkFuel() then
            print("Please refuel the turtle.")
            os.sleep(2)
        else
            -- Use LLM to decide what to do
            local prompt = "The turtle is ready to move. Provide a command in the format 'action: steps', where action is forward, left, right, or stop."
            local response = llm.getGeminiResponse(prompt)
            if response then
                response = response:match("^%s*(.-)%s*$")  -- Trim whitespace
                print("LLM response: " .. response)
                -- Parse the response
                local action, steps = response:match("^(%a+)%s*:%s*(%d+)$")
                steps = tonumber(steps)
                if action and steps then
                    -- Implement actions based on LLM response
                    for i = 1, steps do
                        if action == "forward" then
                            moveForward()
                        elseif action == "left" then
                            turnLeft()
                        elseif action == "right" then
                            turnRight()
                        elseif action == "stop" then
                            print("Stopping turtle.")
                            return
                        else
                            print("Unknown command from LLM.")
                            break
                        end
                    end
                else
                    print("Invalid response format from LLM.")
                end
            else
                print("No response from LLM.")
            end
        end

        -- Add a delay to prevent spamming
        os.sleep(2)
    end
end

-- Start the turtle control
controlTurtle()
