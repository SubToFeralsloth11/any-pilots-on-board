# Any Pilots On Board?

> The pilot passed out. You said you could fly. You can't.

A chaotic co-op multiplayer 3D game for up to 8 players, made with Godot 4.7. You and your crew pick the passenger and cargo contracts, board the flight, take off, fly through storms to the destination runway and land the airliner (or crash it). Then you get paid. Along the way, chickens get loose, a crocodile breaks out of its crate, windows blow out and engines catch fire.

## Download

Get the latest build from the [Releases page](https://github.com/SubToFeralsloth11/any-pilots-on-board/releases/latest):

| Platform | File |
|---|---|
| Windows 10/11 (64-bit) | `AnyPilotsOnBoard-windows.zip` |
| macOS (Apple Silicon and Intel) | `AnyPilotsOnBoard-macos.zip` |
| Linux (x86_64) | `AnyPilotsOnBoard-linux.zip` |

Every player needs the same version of the game.

## Install

The builds are not code-signed, so each operating system warns you the first time you run the game.

### Windows

1. Download `AnyPilotsOnBoard-windows.zip`, right-click it and choose **Extract All…**.
2. Double-click `AnyPilotsOnBoard.exe` in the extracted folder.
3. If Windows shows **"Windows protected your PC"**, click **More info**, then **Run anyway**.
4. When Windows Defender Firewall asks, allow access on **Private networks**. Friends can't join your flight otherwise.

To uninstall, delete the folder.

### macOS

1. Download `AnyPilotsOnBoard-macos.zip` and double-click it to unzip it (Safari may do this for you).
2. Drag `AnyPilotsOnBoard.app` into your **Applications** folder.
3. Double-click it. macOS says it can't verify the app: click **Done** (or **Cancel**).
4. Open **System Settings → Privacy & Security**, scroll down to the message about *AnyPilotsOnBoard* and click **Open Anyway**. Confirm with your password. On macOS 14 and earlier, you can also right-click the app and choose **Open**.
5. Allow microphone access if you want voice chat, and allow incoming connections if macOS asks (needed to host).

If macOS says the app **"is damaged and can't be opened"**, remove the download quarantine flag in Terminal, then open the app again:

```sh
xattr -dr com.apple.quarantine /Applications/AnyPilotsOnBoard.app
```

To uninstall, drag the app to the Trash.

### Linux

```sh
unzip AnyPilotsOnBoard-linux.zip -d AnyPilotsOnBoard
cd AnyPilotsOnBoard
chmod +x AnyPilotsOnBoard.x86_64
./AnyPilotsOnBoard.x86_64
```

You need a GPU driver with Vulkan support (Mesa is fine for AMD and Intel; use the proprietary driver for NVIDIA). If you use a firewall and want to host, open UDP port 7777, for example `sudo ufw allow 7777/udp`.

To uninstall, delete the folder.

## Playing with friends

The game uses direct IP connections: one player hosts, and the others join the host's IP address on **UDP port 7777**.

1. **Host:** enter your name and click **Host a flight**. The title screen shows your local IP address under *"Friends on your Wi-Fi join you at"*. You can also host alone.
2. **Friends:** enter your name, type the host's IP address in **Host IP** and click **Join a friend's flight**.

**Same network (home Wi-Fi, LAN party):** use the local IP shown on the host's title screen (usually `192.168.x.x` or `10.x.x.x`).

**Over the internet,** pick one:

- **Virtual LAN (easiest):** everyone installs [Tailscale](https://tailscale.com/) or [ZeroTier](https://www.zerotier.com/) and joins the same network. Friends then join the host's Tailscale/ZeroTier IP. No router setup needed.
- **Port forwarding:** the host forwards **UDP port 7777** on their router to their computer, and friends join the host's public IP (search "what is my IP"). This doesn't work on some mobile and carrier-grade NAT connections.

Players can join a flight that has already started.

## Controls

| Key | Action |
|---|---|
| WASD | Move. In the pilot seat: W/S nose down/up, A/D bank |
| Mouse | Look |
| Space | Jump |
| Shift | Sprint (raises throttle while piloting) |
| Ctrl / C | Crouch / brace (lowers throttle while piloting) |
| E | Interact, pick up or drop, strap cargo |
| Left mouse button | Throw or punch |
| Right mouse button | Use the held item |
| Middle mouse button | Ping a spot for your crew |
| G | Landing gear |
| F | Flaps |
| B | Seatbelt sign |
| V | Toggle first/third-person camera |
| Y | Shout |
| T | Push-to-talk voice chat (Settings → Voice chat: Off / Hold T / Open mic) |
| R | Fly again (host, after the round ends) |
| Esc | Pause menu (Resume, Settings, Leave) |

## Running from source

1. Install [Godot 4.7](https://godotengine.org/download/) (standard build, not .NET).
2. Clone this repository and open `project.godot` in Godot, or run it directly:

```sh
godot --path . -- --host                       # host a flight
godot --path . -- --join=127.0.0.1 --name=Bob  # join it from a second instance
godot --headless -s res://tests/run_tests.gd   # unit tests
```

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for how the game is structured and for more dev commands.

## Builds and releases

GitHub Actions (`.github/workflows/build.yml`) runs the unit tests and exports Windows, macOS and Linux builds on every push; the zips are downloadable from the run's artifacts for 14 days. Publishing a GitHub release attaches the three zips to it.

To export locally, install the Godot 4.7 export templates (**Editor → Manage Export Templates**) and run:

```sh
godot --headless --export-release "Windows"   # export/windows/AnyPilotsOnBoard.exe
godot --headless --export-release "macOS"     # export/macos/AnyPilotsOnBoard.zip
godot --headless --export-release "Linux"     # export/linux/AnyPilotsOnBoard.x86_64
```

Create the `export/windows`, `export/macos` and `export/linux` folders first.
