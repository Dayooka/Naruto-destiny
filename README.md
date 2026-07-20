Core Features
Turn‑aware combat – reacts to Your Turn events, executes attacks/abilities.

Resource management – HP & chakra thresholds trigger automatic healing teleport.

Multi‑target farming – pick specific NPCs from a dynamically scanned list.

Movement modes – teleport or walk, auto‑switch for distant targets.

Ability priority – uses cooldown tracking and slot‑based scoring.

Anti‑AFK – keeps session alive during long farms.

Draggable GUI – real‑time status, toggles, and target selection menu.

⚙️ Quick Config
Setting	Default	Description
HealthEnabled	false	Enable auto‑heal teleport
AutoHealthThreshold	0.3	HP % to trigger heal
AutoChakraThreshold	0.2	Chakra % to trigger heal
MoveMode	"Teleport"	"Walk" or "Teleport"
ReturnDelay	2s	Time to wait before returning after combat
HealDuringCombat	false	(Experimental) heal mid‑fight
AutoAbility	true	Automatically use abilities
All settings can be tweaked via the in‑game UI buttons.

🎮 How to Use
Paste script into your executor.

GUI appears – select targets (mandatory) via the “Select Targets” button.

Adjust thresholds/movement as needed.

Press START AUTOFARM – script handles the rest.

🧠 Technical Highlights
Modular structure – configuration, UI, combat logic, and utilities are separated.

Safe state machine – prevents overlapping actions (health busy, combat lock).

Position memory – saves and restores your location after healing/combat.

Clean shutdown – disconnects all events and stops movement on exit.

Lightweight – no external dependencies, uses native Roblox services.

📝 Notes
Works best in games with RemoteEvents (TurnEvent, CombatRemoteEvent) and NPCs tagged with IsNPC attribute.

Health teleport requires a predefined CFrame – adjust CONFIG.HealthTeleportCFrame if needed.

All actions are triggered by in‑game events – no direct memory manipulation.

Disclaimer – Use responsibly and only in environments where automation is allowed.
