# ComputerCraft Communication System

A communication system for ComputerCraft that allows computers and turtles to communicate via wireless modems.

## System Components

This system consists of two main components:

1. **CommCentral (`comm_central.lua`)** - The central hub that runs on a computer with a wireless modem. It provides a GUI for monitoring and communicating with connected devices.

2. **CommTurtle (`comm_turtle.lua`)** - The client that runs on turtles with wireless modems. It allows them to connect to the central hub and receive commands.

## Requirements

- Minecraft with ComputerCraft mod installed
- Advanced Computer (for the hub) with a wireless modem attached
- Turtles with wireless modems attached

## Installation

1. On your central computer:
   - Download the `comm_central.lua` file: `wget https://raw.githubusercontent.com/yourusername/minecraft_cc/main/comm_central.lua`
   - Run the program with: `comm_central`

2. On each turtle:
   - Download the `comm_turtle.lua` file: `wget https://raw.githubusercontent.com/yourusername/minecraft_cc/main/comm_turtle.lua`
   - Run the program with: `comm_turtle`

## Using CommCentral (The Hub)

### Main Interface
The CommCentral interface is divided into two main sections:
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

## Using CommTurtle

### Connecting to a Hub
The turtle will automatically connect to any CommCentral hub that discovers it. It will display the connection status on its screen.

### Sending Commands to Turtles
From the CommCentral hub, you can send commands to a turtle by prefixing them with an exclamation mark (`!`). For example:
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

## Tips for Use

1. **Range**: Wireless modems have a limited range (by default 64 blocks). Make sure your turtles stay within range of the hub.

2. **Fuel**: Always ensure your turtles have sufficient fuel before sending them on long journeys.

3. **Multiple Hubs**: A turtle can connect to multiple hubs, but will prioritize the most recent connection.

4. **Automatic Reconnection**: If a turtle loses connection, it will automatically try to reconnect when it comes back into range.

5. **Batch Commands**: To execute multiple commands in sequence, send them one after another; they will be queued on the turtle.

## Troubleshooting

- **No devices found**: Make sure wireless modems are attached to both the computer and turtles.

- **Connection lost**: Check if the turtle is within range of the computer.

- **Command failed**: The turtle will report back errors if commands cannot be executed.

- **Program crashes**: Ensure you're running the latest version of ComputerCraft and that your wireless network is properly configured.

## Advanced Usage

You can expand this system by:

1. Adding more commands to the turtle
2. Creating specialized turtles for different tasks
3. Implementing a security system with passwords
4. Building a turtle management dashboard for multiple turtles

Happy automating! 