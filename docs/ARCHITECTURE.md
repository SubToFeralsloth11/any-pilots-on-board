# Architecture

Godot 4.7, GDScript, Jolt physics. Everything is built from code (no art assets); the only scene is `scenes/main.tscn`.

## Frames of reference

- The **plane** (`Airliner`, `scripts/plane/airliner.gd`) is an `AnimatableBody3D` fixed at the world origin. It only pitches and rolls. Its local axes are: `-Z` = nose, `+X` = right wing, floor top at `y = 0`. The cockpit runs from `z -14` to `-10`, the cabin from `-10` to `6`, the lounge from `6` to `12` (`LOUNGE_MIN`/`LOUNGE_MAX`) and the cargo hold from `12` to `22` (`CARGO_MIN`/`CARGO_MAX`, rear ramp at `TAIL_Z`). Collision uses invisible boxes. The visible hull is a CSG tube with real window and door cut-outs.
- **Fixtures**: modules attach furniture to the moving plane with `plane.add_fixture(size, center, color, collide)`, `plane.add_mesh(mesh, xform)` and `plane.add_area(interactable)`.
- The **outside world** (`scripts/outside/outside.gd`) is built in world coordinates (ground at `y = 0`, north = `-Z`). Each frame, `World` sets the `Outside` transform to the inverse of the plane's flight pose, so the scenery moves past the plane.
- **Gravity is real.** `FlightModel` is force-based (lift from angle of attack, drag, thrust, flaps, stall). It produces `felt_accel`: real gravity minus 60% of the plane's own acceleration, in the scene frame. `World` writes that vector into the physics space's gravity every frame. Banks, dives and pull-ups therefore make loose bodies and players slide, float or get pinned. `felt_gravity()` returns the scalar g along the cabin floor.
- **Outside the hull**, the wind pushes toward the tail. `Airliner.is_outside(pos)` reports whether a position is outside. Anything farther than `World.LOSE_DISTANCE` from the origin is lost.

## Networking

The host (peer 1) is authoritative. It simulates `FlightModel`, every networked object (rigid bodies, NPCs) and the story. Each peer simulates only its own `Player` and streams it to the host, which relays it to everyone else. On clients, networked `RigidBody3D` objects are frozen (kinematic) and follow 30 Hz snapshots.

| Call (host only unless noted) | Effect |
|---|---|
| `world.spawn_object(kind, xform, extra)` | Creates the object on every peer through the factory registered for `kind`. |
| `world.despawn_object(id)` | Removes the object on every peer. |
| `world.object_event(id, event, args)` | Calls `obj.on_net_event(event, args)` on every peer (cosmetics). |
| `world.set_plane(key, bool)` | Plane state on every peer. Keys: `window:i`, `door:left/right/cockpit`, `ramp`, `fire:0/1`, `gear`. |
| `world.break_window(i)` | Breaks window `i` and counts it in the stats. |
| `world.say(speaker, text, dur)` | Subtitle on every screen (`subtitle` signal). |
| `world.notify(peer, text)` | Toast for one player (`toast` signal on that peer). |
| `world.push_player(peer, vel)` / `world.shake_all(amount)` | Knockback / camera shake. |
| `world.damage_plane(part, amount)` | Plane damage. Parts: `engine0/1`, `wing0/1` (left/right), `tail`, `hull`. Health is kept in `plane.damage[part]` on every peer (1 = intact). A negative amount repairs. |
| `world.damage_plane_at(pos, amount)` | Damages the part at a world point, breaks a window right there, leaves a scorch mark, and returns the part name. |
| `world.add_stat(key, n)` | Round statistics. |
| `world.add_player_stat(peer, key, n)` | Per-player round statistics for the crew awards (keys in `Scoring.AWARDS`). |
| `world.request(action, args)` (any peer) | Sends an action to the host, which runs `handler(peer_id, args)`. |

`world.locked_doors` is a host-side `{door_name: true}` map (empty at round start: the players are the crew, so the cockpit is open). `world.seatbelt_sign` is synced to every peer; the pilot toggles it with [B] (`seatbelt` action, `world.set_seatbelt(on)` on the host, `plane_changed("seatbelt", on)` on every peer).

**Damage changes the flight.** Engine thrust follows engine health and drops while the engine burns, and the thrust asymmetry yaws and rolls the plane. A weak wing drops. A damaged tail wobbles and loses elevator authority. Hull damage adds drag. Fires burn down engine and wing health, and a wrecked engine (health < 0.3) can catch fire by itself.

**Ragdolls.** An object can return limb bodies from `get_net_parts()`, in the same order on every peer. The host snapshots each part, and clients freeze the parts and follow them. While `net_parts_active()` returns false, only the root body is synced.

## Module contract

`World` creates four modules as children: `Props`, `Npcs`, `Story` and `Fun` (board games, weapons, lounge activities). Each is a `Node` with:

- `setup(world: World)`: runs on **every** peer. Register object factories with `world.register_kind(kind, func(extra) -> Node3D)` and host actions with `world.register_action(action, func(peer_id, args))`.
- `populate()`: runs on the **host** only, once per round. Spawn the starting objects here.

The `Story` module can also implement:

- `can_pilot(peer) -> bool`
- `get_sync() -> Dictionary` and `apply_sync(d)`, for players who join late.

### Networked objects

A networked object is any `Node3D` created by a registered factory. `World` sets the metadata `net_id`, `kind` and `extra`. Loose objects should be `RigidBody3D` on the `Layers.PROP` layer (NPCs use `Layers.NPC`), with the collision mask `WORLD | PLAYER | PROP | NPC`.

Optional members on an object, called by `World`:

| Member | Where it runs | Purpose |
|---|---|---|
| group `"grabbable"` | — | The object can be picked up with [E], carried and thrown. |
| meta `"action"` | — | [E] sends `request(meta_action, [net_id])` instead of picking up (for example, `"search"` on crates). |
| `get_prompt() -> String` | All peers | The HUD prompt shown while aiming at the object. |
| `can_grab(peer) -> bool` | Host | Allows or refuses a pickup. |
| `on_grabbed(peer)`, `on_released()`, `on_thrown(peer)`, `on_punched(peer, dir)`, `on_lost()` | Host | Reactions to being handled or lost. |
| `get_spawn_extra() -> Dictionary` | Host | Current state sent to players who join late. |
| `on_net_event(event, args)` | All peers | Visual or audio reaction to `world.object_event`. |
| `use(peer, origin, dir)` | Host | Right-click while holding the object (World checks that `peer` is the holder). |

Group `"npc"` marks passengers: losing one counts as `passengers_lost`.

`World` already handles the following for every networked `RigidBody3D`: wind and suction forces, loss when out of range, carrying (with the velocity steered toward the player's hold point), throwing and punching.

## Player input

| Key | Action |
|---|---|
| WASD | Move. In the pilot seat: W/S nose down/up, A/D bank. |
| Space | Jump |
| Shift | Sprint (raises throttle while piloting) |
| Ctrl / C | Crouch / brace (lowers throttle while piloting) |
| E | Interact, pick up or drop |
| Left mouse button | Throw, or punch |
| Right mouse button | Use the held item (World's `use_item` action calls the object's `use()`) |
| Y | Shout (`shout` action) |
| G | Landing gear |
| Esc | Pause (Resume, Settings, Leave). Settings also open from the title menu and are saved by the `Settings` autoload. |
| R | Restart (host, after the round ends) |
| T | Push-to-talk voice chat (Settings → Voice chat: Off / Hold T / Open mic) |

## Voice chat

`scripts/net/voice.gd` (World module `Voice`, every peer) captures the microphone through an `AudioStreamMicrophone` on the muted `VoiceMic` bus (`AudioEffectCapture`, `audio/driver/enable_input=true`). Audio is downmixed to mono, scaled by `Settings.mic_gain`, resampled to 16 kHz and sent as 20 ms G.711 μ-law frames (`scripts/net/voice_codec.gd`: 5-byte header + 320 bytes). Clients send frames to the host (`unreliable_ordered`, channel 2); the host relays them to every other peer within ~30 m, like player state. Each remote talker plays from an `AudioStreamGenerator` on an `AudioStreamPlayer3D` on their head (25 m range) after an 80 ms jitter buffer. A billboard speaker icon shows over a talking player's name label; your own HUD shows a TALKING badge. `voice.is_talking(peer)` reports who is speaking. Without a microphone (no device, permission denied, headless) voice logs once and stays receive-only. macOS exports need a microphone usage description.

## Weather

`scripts/weather/weather.gd` (World module `Weather`, `world.weather`, every peer). `weather_cells.gd` places 3–5 storm cells between `FlightModel.ORIGIN_RUNWAY_CENTER` and `FlightModel.runway_threshold()`, seeded from `world.airline.flight_no` (one always sits on the route), so every peer derives the same cells without sync. `intensity_at(pos)` (0..1, full in the core, smooth falloff to the rim, calm above the cloud tops) and `current` (at the plane; 0 unless FLYING) work on every peer, as does `ahead` (index of the cell the plane enters within ~20 s, or -1).

While FLYING the host adds turbulence jolts to `flight.bump` with pitch/roll kicks (loose props hop, standing players are pushed), air pockets (2–4 s near zero g, then a slam), gusts, and lightning: a bolt, screen flash and distance-delayed thunder on every peer; a hit damages the hull a little and may crack a window (a cracked window hit again breaks). TOWER warns once per cell ~20 s before entry. Host signals for other modules: `jolt(strength)`, `air_pocket(active)`; `strike(hit)` fires on every peer.

Visuals (`weather_fx.gd`): one merged storm-cloud mesh and one rain-shaft mesh under `world.outside`, rain streak particles around the plane, rain on the side windows and windshield (one MultiMesh, one shader), darker sky/fog/sun inside storms. The pilot sees a heading-up radar (`weather_radar.gd`) with cells coloured by threat to the current heading (red on the path, yellow close, green clear).

## Cargo

`scripts/cargo/cargo_module.gd` (World module `Cargo`, `world.cargo`). When `world.airline` enters `"boarding"`, the host spawns `count` pieces per accepted cargo contract into the hold: two columns at `x = ±1.65` (the `|x| < 1` walkway stays clear), the right column stopping short of `Airliner.RAMP_LEVER`; beyond 11 pieces they stack. Every piece, hen and crocodile has meta `contract`. `cargo_report()` (host) returns contract id → `{units, delivered, condition}`: a piece counts when it still exists, isn't destroyed and is inside the hull (a loose but on-board crocodile halves the condition; a coop scores hens inside fully and loose ones by half).

Pieces (`cargo_piece.gd`, kinds `luggage`, `mail`, `fragile`, `chickens`, `crocodile`, `explosive`, `mystery`; models in `cargo_looks.gd`, sounds in `cargo_sfx.gd`) lose condition on hard impacts. Fragile vases crack and shatter below 0. Impacts, throws, punches, fire and turbulence (`|flight.bump|` above 0.3 while flying) anger the coop (the door pops, 3–5 `chicken` bodies run around; drop one into its coop to return it) and the crocodile crate (the `croc` crawls to the nearest person and bites; carry it by the tail back into its crate or throw it out). Explosive barrels blow on hard hits or after a short fuse near fire (burning engine, flare, another blast): impulse, ragdolls, knockback, `world.damage_plane_at`, chain reactions. The mystery crate hums, floats, teleports or inverts gravity around itself while flying.

Meta `action` = `"strap"`: [E] on a piece resting in the hold straps it down (frozen and carried with the plane, so it never slides and turbulence can't open it), [E] again unstraps, and crouch + [E] (or [E] anywhere outside the hold) picks it up through the core `grab` action.

## Round flow

`FlightModel.phase` is `PARKED → ROLLING (takeoff roll, departure_roll = true) → FLYING → ROLLING → LANDED`, or `→ CRASHED`. The round starts PARKED on the origin runway (`ORIGIN_RUNWAY_CENTER`, `START_POS`) with gear down; Story holds `flight.parking_brake` until the airline phase is `"flight"`. Throttle past `TAKEOFF_THROTTLE` starts the takeoff roll, pulling up at `VR` or faster lifts off; chopping the throttle on the roll goes back to PARKED and running off the runway at speed crashes. The destination runway (`RUNWAY_CENTER`, `runway_threshold()`) is ~26 km north; a touchdown there sets `touchdown.at_destination`. When the round ends, the host emits `round_ended(result)` on every peer. The result is built by `Scoring.result`; it carries the per-player stats and the crew awards from `Scoring.awards` (pure; ties go to the lowest peer id), which the results screen shows as cards. `Main.restart_round()` (host only) rebuilds the World on every peer.

## Dev and test commands

```
godot --headless -s res://tests/run_tests.gd          # unit tests
godot -- --host --shot=/tmp/a.png --shot-at=3 --at=0,0.1,4 --look=0,-5 --quit-after=5
godot -- --join=127.0.0.1 --name=Bob                  # second instance
godot -- --host --voice-test-tone                     # voice: send a 440 Hz tone instead of the mic
godot -- --join=127.0.0.1 --voice-test-tone           # logs "[voice N] frames sent=… received=…" every 2 s
```

In the screenshot command, `--at` is a plane-local position and `--look` is yaw and pitch in degrees.
