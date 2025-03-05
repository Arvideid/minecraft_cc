# ComputerCraft Communication System

A modular communication system for ComputerCraft computers and turtles. This system allows for robust wireless communication between computers and turtles with a simple, reliable architecture.

## System Components

This system consists of three main components:

1. **Modem Control Module (`modem_control.lua`)** - The core communication library that handles all wireless interactions.

2. **Communication Hub (`comm_hub.lua`)** - The central hub that runs on a computer with a wireless modem. It provides a GUI for monitoring and communicating with connected devices.

3. **Turtle Client (`comm_turtle.lua`)** - The client that runs on turtles with wireless modems. It allows them to connect to the central hub and receive commands.

## Requirements

- Minecraft with ComputerCraft mod installed
- Advanced Computer (for the hub) with a wireless modem attached
- Turtles with wireless modems attached

## Installation

1. On your central computer:
   - Download the three required files:
     - `wget https://raw.githubusercontent.com/Arvideid/minecraft_cc/main/modem_control.lua`
     - `wget https://raw.githubusercontent.com/Arvideid/minecraft_cc/main/comm_hub.lua`
   - Run the hub program: `comm_hub`

2. On each turtle:
   - Download the required files:
     - `wget https://raw.githubusercontent.com/Arvideid/minecraft_cc/main/modem_control.lua`
     - `wget https://raw.githubusercontent.com/Arvideid/minecraft_cc/main/comm_turtle.lua`
   - Run the turtle program: `comm_turtle`

## Using the Communication Hub

### Main Interface
The hub interface is divided into two main sections:
- Left panel: List of connected devices (turtles and computers)
- Right panel: Message history with the selected device

### Keyboard Shortcuts
- **Arrow Up/Down**: Navigate the device list
- **Tab**: Cycle through connected devices
- **Enter**: Send message to selected device
- **F1**: Show help screen
- **F5**: Refresh device list (send discovery ping)
- **ESC**: Exit application

### Commands
You can send these special commands to devices:
- `/name [new name]`: Rename the selected device locally
- `/clear`: Clear message history with selected device
- `/ping`: Send ping to selected device

## Using ComNet Turtle

### Connecting to a Hub
The turtle will automatically connect to any hub that discovers it. It will display the connection status on its screen.

### Sending Commands to Turtles
From the hub, you can send commands to a turtle by prefixing them with an exclamation mark (`!`). For example:
- `!forward`: Move the turtle forward
- `!turnLeft`: Turn the turtle left
- `!dig`: Dig the block in front
- `!getFuelLevel`: Get the current fuel level

### Available Turtle Commands
- **Movement**: `forward`, `back`, `up`, `down`, `turnLeft`, `turnRight`
- **Tool**: `dig`, `digUp`, `digDown`, `place`, `placeUp`, `placeDown`
- **Inventory**: `select [slot]`, `getItemCount`, `getItemDetail [slot]`, `transferTo [slot] [count]`
- **Information**: `detect`, `detectUp`, `detectDown`, `inspect`, `inspectUp`, `inspectDown`
- **Other**: `getFuelLevel`, `refuel [count]`, `status`, `help`

### Position Tracking
The turtle can track its position relative to its starting point:
- `!setPosition x y z [facing]`: Set the turtle's current position
- `!enableTracking`: Enable position tracking
- `!disableTracking`: Disable position tracking

## Why This System Works
This communication system has been designed with several key principles:

1. **Modular Design**: By separating the modem control logic into its own module, we avoid function definition order issues.

2. **Error Handling**: The system includes robust error handling throughout.

3. **Consistent Protocol**: All messages follow a standard format for improved reliability.

4. **Automatic Discovery**: Devices automatically find each other without manual configuration.

5. **Graceful Reconnection**: If connections are lost, they are automatically restored when possible.

## Tips for Use

1. **Range**: Wireless modems have a limited range (by default 64 blocks). Make sure your turtles stay within range of the hub.

2. **Fuel**: Always ensure your turtles have sufficient fuel before sending them on long journeys.

3. **Multiple Hubs**: A turtle can connect to multiple hubs, but will prioritize the most recent connection.

4. **Command Queuing**: Commands sent to a turtle are queued and executed in sequence, even if they arrive rapidly.

5. **Press Ctrl+Q**: To exit the turtle program, press Ctrl+Q. For the hub, use ESC.

## Troubleshooting

- **No devices found**: Make sure wireless modems are attached to both the computer and turtles.

- **Connection lost**: Check if the turtle is within range of the computer.

- **Command failed**: The turtle will report back errors if commands cannot be executed.

- **Program crashes**: Ensure you're running the latest version of ComputerCraft and that your wireless network is properly configured.

## Advanced Usage

You can expand this system by:

1. Adding more commands to the turtle client
2. Creating specialized turtles for different tasks
3. Implementing a security system with passwords
4. Building a turtle management dashboard for multiple turtles

Happy automating! 
