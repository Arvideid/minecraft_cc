-- Ensure HTTP is enabled in the ComputerCraft configuration

-- Your Gemini API key
local apiKey = "AIzaSyBovnTYV5SFtsB-Gk5RAQjjPFFKpsZ5SCw"  -- Replace with your actual API key

-- Function to send a prompt to the Gemini API and get a response
function getGeminiResponse(prompt)
    local url = "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key=" .. apiKey
    local headers = {
        ["Content-Type"] = "application/json"
    }
    local body = textutils.serializeJSON({
        contents = {
            {
                parts = {
                    { text = "Please respond in plain text only. " .. prompt }
                }
            }
        }
    })

    print("Sending request to Gemini API...")

    local response, err = http.post(url, body, headers)
    if response then
        local content = response.readAll()
        response.close()
        print("Response received.")

        local data = textutils.unserializeJSON(content)
        
        -- Adjust based on the actual response structure
        if data and data.candidates and #data.candidates > 0 then
            local candidate = data.candidates[1]
            if candidate.content and candidate.content.parts and #candidate.content.parts > 0 then
                return candidate.content.parts[1].text
            else
                print("Unexpected response structure.")
                return nil
            end
        else
            print("Unexpected response structure.")
            return nil
        end
    else
        print("Failed to fetch data from Gemini API")
        if err then
            print("Error: " .. err)
        end
        return nil
    end
end

-- Main interactive loop
while true do
    -- Ask the user for a prompt
    print("Enter your prompt (or type 'exit' to quit):")
    local userPrompt = read()

    -- Exit the loop if the user types 'exit'
    if userPrompt == "exit" then
        break
    end

    -- Get the response from the Gemini API
    local response = getGeminiResponse(userPrompt)
    if response then
        print("Gemini API response: " .. response)
    else
        print("No response received.")
    end
end