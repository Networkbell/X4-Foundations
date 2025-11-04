-- ffi setup
local ffi = require("ffi")
local C = ffi.C
ffi.cdef[[
	typedef uint64_t UniverseID;
	typedef struct {
		float angle;
		bool inside;
		bool valid;
	} ArrowDetails;
	typedef struct {
		uint32_t red;
		uint32_t green;
		uint32_t blue;
		uint32_t alpha;
	} Color;
	typedef struct {
		const char* id;
		Color color;
		float glowfactor;
	} ColorMapEntry;
	typedef struct {
		const char* name;
		float hull;
		float shield;
		int speed;
		bool hasShield;
	} ComponentDetails;
	typedef struct {
		bool armed;
		bool blocked;
		const char* modeIcon;
		bool pending;
		bool possible;
		uint32_t total;
		uint32_t undocked;
	} DroneState;
	typedef struct {
		uint64_t poiID;
		UniverseID componentID;
		const char* messageType;
		const char* connectionName;
		bool isAssociative;
		bool isMissionTarget;
		bool isPriorityMissionTarget;
		bool showIndicator;
		bool hasAdditionalOffset;
	} MessageDetails3;
	typedef struct {
		int relationStatus;
		int relationValue;
		int relationLEDValue;
		bool isBoostedValue;
	} RelationDetails;
	typedef struct {
		const char* icon;
		const char* mode;
		uint32_t damageState;
		bool active;
		bool usesAmmo;
		uint32_t ammo;
	} TurretDetails;
	typedef struct {
		const char* icon;
		uint32_t damageState;
		bool active;
		bool usesAmmo;
		uint32_t ammo;
		int32_t currentclip;
		int32_t maxclip;
		uint32_t mode;
		float reloadPercent;
		bool isAutoReloading;
		uint32_t heatState;
		float heatPercent;
		float nextShotHeatPercent;
		float lockPercent;
		uint64_t counterMeasureTarget;
	} WeaponDetails3;
	bool CanActivateSeta(bool checkcontext);
	bool CanHaveCountermeasures();
	void CycleNextDroneMode(uint32_t dronetype);
	void CycleTurretMissile(size_t turretnum);
	void CycleTurretMode(size_t turretnum);
	uint32_t GetActivePrimaryWeaponGroup();
	uint32_t GetActiveSecondaryWeaponGroup();
	int32_t GetAimAssistState(void);
	uint32_t GetAllColorMapEntries(ColorMapEntry* result, uint32_t resultlen);
	int32_t GetAutoRollState(void);
	float GetBoostEnergyPercentage(void);
	int32_t GetCollisionAvoidanceState(void);
	ArrowDetails GetCrosshairArrowDetails(int posid, float radius);
	double GetCurrentGameTime();
	DroneState GetDroneDetails(const uint32_t dronetype);
	float GetHUDUIScale(const bool scalewithresolution);
	const char* GetLocalizedText(uint32_t pageid, uint32_t textid, const char* defaultvalue);
	int GetPriorityMissiontargetPOSID();
	MessageDetails3 GetMessageDetails3(uint32_t messageid);
	float GetModeLightIntensity(void);
	uint32_t GetNumAllColorMapEntries(void);
	uint32_t GetNumCountermeasures();
	size_t GetNumPrimaryWeapons();
	size_t GetNumSecondaryWeapons();
	size_t GetNumTurrets();
	size_t GetNumTurretSlots();
	size_t GetNumWeaponSlots();
	const char* GetObjectEngineStatus(const UniverseID objectid);
	UniverseID GetPlayerOccupiedShipID(void);
	const char* GetPlayerShipSize();
	float GetRemainingOxygen();
	float GetScanProgress();
	TurretDetails GetTurret(size_t turretnum);
	float GetUIScale(const bool scalewithresolution);
	WeaponDetails3 GetWeaponDetails2(size_t weaponnum, bool issecondary);
	bool HasLimitedOxygenSupply();
	bool HasSeta();
	bool IsAutoPilotActive(void);
	bool IsCurrentlyScanning();
	bool IsExternalTargetMode();
	bool IsExternalViewActive();
	bool IsFlightAssistActive(void);
	bool IsGamePaused(void);
	bool IsLowOnOxygen();
	bool IsMissileIncoming();
	bool IsMissileLockingOn();
	bool IsMouseSteeringActive(void);
	bool IsObjectShootingDisabledByStanceOnly(UniverseID objectid);
	bool IsPlayerOccupiedShipDocked(void);
	bool IsReducedSpeedModeActive(void);
	bool IsSetaActive();
	bool IsVRMode();
	bool IsWidgetsystemRequestingCrosshairVisible(void);
	bool ShouldShowMouseSteeringHelperLine(void);
	void ToggleDrones(uint32_t dronetype);
]]

--- Wrapper ---
local origffistring = ffi.string
ffi.string = function(data) 
	if data ~= nil then
		return origffistring(data)
	else
		DebugError("Invalid parameter for ffi.string() in crosshair. Check caller!")
		DebugError(TraceBack())
		return ""
	end
end

-- global color lookup
Color = {}

local colorMetatable = {
	__index = function(table, key)
		DebugError(string.format("Color setup error: Tried to access non-existing color '%s'\n\n%s", tostring(key), TraceBack()))
		return { r = 255, g = 0, b = 255, a = 60, glow = 0 }
	end
}
setmetatable(Color, colorMetatable)

local function getColors()
	local n = C.GetNumAllColorMapEntries()
	if n > 0 then
		local buf = ffi.new("ColorMapEntry[?]", n)
		n = C.GetAllColorMapEntries(buf, n)
		for i = 0, n - 1 do
			local id = ffi.string(buf[i].id)
			Color[id] = { r = buf[i].color.red, g = buf[i].color.green, b = buf[i].color.blue, a = buf[i].color.alpha, glow = buf[i].glowfactor }
		end
	end
end

getColors()

-- settings
local config = {
	scalingFactor            = 0.003, -- factor the presentation is scaled in-game (used to scale the ui_anchor value)
	missionArrowRadius       = 0.063, -- radius of the mission arrow
	normalMissionGroupingAngle = 60,  -- max angular spread that displays mission arrow for normal mission targets
	targetArrowRadius        = 0.071, -- radius of the target arrow
	enableTimeMemoizing      = false, -- indicates whether we memoize the goToTime()-values we set slides to to save us setting goToTime()-values to the current time
									  -- #coreUIMed - reenable - this requires proper handling of skipping the goToTime()-memoization in cases the slide changed between active <-> inactive
									  -- since this resets the time value to 0
	dronePanelDisappearDelay = 5,     -- delay (in s) before the drone type column starts to disappear, if the last drone is destroyed

	-- color settings
	crosshairColor = {
		["normal"] = Color["crosshair_crosshair"],
		["shadow"] = Color["crosshair_crosshair_shadow"],
	},
	oxygenBarColor = { -- colors for the oxygen bar
		["normal"] = Color["crosshair_oxygen"], -- color when having normal oxygen levels
		["low"] = Color["crosshair_oxygen_low"], -- color when being low on oxygen
	},
	speedBarColor = { -- color for the speedbar
		["normal"] = Color["crosshair_speedbar"], -- color used for normal speed
		["boost"] = Color["crosshair_speedbar_boost"], -- color used for boosted speed
		["zeropoint"] = Color["crosshair_speedbar_zeropoint"],
		["maxpoint"] = Color["crosshair_speedbar_maxpoint"],
		["base"] = Color["crosshair_speedbar_base"],
	},
	boostBarColor = {
		["normal"] = Color["crosshair_boostbar"],
		["full"] = Color["crosshair_boostbar_full"],
		["inactive"] = Color["crosshair_boostbar_inactive"],
		["error"] = Color["crosshair_boostbar_error"],
	},
	hullBarColor = Color["crosshair_hull"],
	hullBarDamageAnimationColor = Color["crosshair_hull_damage_animation"],
	hullBarDamageColor = Color["crosshair_hull_damage"],
	shieldBarColor = Color["crosshair_shield"],
	shieldBarDamageAnimationColor = Color["crosshair_shield_damage_animation"],
	shieldBarDamageColor = Color["crosshair_shield_damage"],
	shieldBarBoostColor = Color["crosshair_shield_boost"],
	targetArrowColor = Color["crosshair_target_arrow"],
	missionArrowColor = Color["crosshair_mission_arrow"],
	weaponColor = { -- color for weapon/turret states
		[0] = { -- undamaged (fully functional)
			["active"] = Color["crosshair_weapon"], -- weapon is active in the group
			["active_highlight"] = Color["crosshair_weapon_highlight"],
			["active_disabled"] = Color["crosshair_weapon_disabled"],
			["inactive"] = Color["crosshair_weapon_inactive"], -- weapon is inactive in the group
			["inactive_highlight"] = Color["crosshair_weapon_inactive_highlight"],
			["inactive_disabled"] = Color["crosshair_weapon_inactive"],
		},
		[1] = { -- damaged
			["active"] = Color["crosshair_weapon_damaged"], -- weapon is active in the group
			["active_highlight"] = Color["crosshair_weapon_damaged_highlight"],
			["active_disabled"] = Color["crosshair_weapon_disabled"],
			["inactive"] = Color["crosshair_weapon_damaged_inactive"], -- weapon is inactive in the group
			["inactive_highlight"] = Color["crosshair_weapon_damaged_inactive_highlight"],
			["inactive_disabled"] = Color["crosshair_weapon_inactive"],
		},
		[2] = { -- broken
			["active"] = Color["crosshair_weapon_broken"], -- weapon is active in the group
			["active_highlight"] = Color["crosshair_weapon_broken_highlight"],
			["active_disabled"] = Color["crosshair_weapon_disabled"],
			["inactive"] = Color["crosshair_weapon_broken_inactive"], -- weapon is inactive in the group
			["inactive_highlight"] = Color["crosshair_weapon_broken_inactive_highlight"],
			["inactive_disabled"] = Color["crosshair_weapon_inactive"],
		},
		["error"] = Color["crosshair_weapon_error"],
	},
	weaponDecoColor = Color["crosshair_weapon_deco"],
	weaponAmmoColor = Color["crosshair_weapon_ammo"],
	weaponGroupColor = {
		["active"] = Color["crosshair_weapon_group_active"],
		["inactive"] = Color["crosshair_weapon_group_inactive"],
	},
	turretModeColor = Color["crosshair_turret_mode"],
	turretModeHighlightColor = Color["crosshair_turret_mode_highlight"],
	reloadBarColor = { -- color for reload bar
		["ready"] = { -- when reloading is done and player can fire the weapon
			["active"] = Color["crosshair_reload_ready"], -- if the weapon is active atm
			["inactive"] = Color["crosshair_reload_ready_inactive"], -- if the weapon is inactive atm
		},
		["reloading"] = { -- when weapon is reloading
			["active"] = Color["crosshair_reload_reloading"], -- if the weapon is active atm
			["inactive"] = Color["crosshair_reload_reloading_inactive"], -- if the weapon is inactive atm
		},
		["autoreloading"] = { -- when weapon is auto-reloading
			["active"] = Color["crosshair_reload_autoreloading"], -- if the weapon is active atm
			["inactive"] = Color["crosshair_reload_autoreloading_inactive"], -- if the weapon is inactive atm
		}
	},
	overheatBarColor = { -- color of the overheat bar
		["empty"] = { -- empty bar (no heat atm)
			["active"] = Color["crosshair_heat"], -- if the weapon is active atm
			["inactive"] = Color["crosshair_heat_inactive"], -- if the weapon is inactive atm
			["nextshot_active"] = Color["crosshair_heat_next_shot"],
			["nextshot_inactive"] = Color["crosshair_heat_next_shot_inactive"],
		},
		["normal"] = { -- normal operations (slightly built up heat)
			["active"] = Color["crosshair_heat_normal"], -- if the weapon is active atm
			["inactive"] = Color["crosshair_heat_normal_inactive"], -- if the weapon is inactive atm
			["nextshot_active"] = Color["crosshair_heat_next_shot_normal"],
			["nextshot_inactive"] = Color["crosshair_heat_next_shot_normal_inactive"],
		},
		["overheating"] = { -- when getting close to overheating
			["active"] = Color["crosshair_heat_overheating"], -- if the weapon is active atm
			["inactive"] = Color["crosshair_heat_overheating_inactive"], -- if the weapon is inactive atm
			["nextshot_active"] = Color["crosshair_heat_next_shot_overheating"],
			["nextshot_inactive"] = Color["crosshair_heat_next_shot_overheating_inactive"],
		},
		["cooling"] = { -- cooling down after being overheated
			["active"] = Color["crosshair_heat_cooling"], -- if the weapon is active atm
			["inactive"] = Color["crosshair_heat_cooling_inactive"], -- if the weapon is inactive atm
			["nextshot_active"] = Color["crosshair_heat_next_shot_cooling"],
			["nextshot_inactive"] = Color["crosshair_heat_next_shot_cooling_inactive"],
		}
	},
	dronePanelColor = {
		["active"] = Color["crosshair_drone_mode_active"], -- if the mode is active atm (blue)
		["active_highlight"] = Color["crosshair_drone_mode_active_highlight"], -- if the mode is active atm (blue)
		["pending"] = Color["crosshair_drone_mode_pending"], -- if the mode is pending activation (gray)
		["pending_highlight"] = Color["crosshair_drone_mode_pending_highlight"], -- if the mode is pending activation (gray)
		["armed"] = Color["crosshair_drone_armed"], -- if drones are armed/arming (blue)
		["armed_highlight"] = Color["crosshair_drone_armed_highlight"], -- if drones are armed/arming (blue)
		["disarmed"] = Color["crosshair_drone_disarmed"], -- if drones are disarmed/disarming (gray)
		["disarmed_highlight"] = Color["crosshair_drone_disarmed_highlight"], -- if drones are disarmed/disarming (gray)
		["blocked"] = Color["crosshair_drone_blocked"], -- color value for the drone panel, if the drone type interaction is blocked (i.e. auto trading) (orange)
		["blocked_highlight"] = Color["crosshair_drone_blocked_highlight"], -- color value for the drone panel, if the drone type interaction is blocked (i.e. auto trading) (orange)
		["destroyed"] = Color["crosshair_drone_destroyed"], -- color value for the drone panel, if the drones were destroyed (drone panel/column pending removal) (red)
		["destroyed_highlight"] = Color["crosshair_drone_destroyed_highlight"], -- color value for the drone panel, if the drones were destroyed (drone panel/column pending removal) (red)
		["number"] = Color["crosshair_drone_number"], -- color value for the number (white)
		["deco"] = Color["crosshair_drone_deco"],
	},
	indicatorColor = {
		["deactivated"]		= Color["crosshair_indicator_inactive"],
		["activated"]		= Color["crosshair_indicator_activated"],
		["active"]			= Color["crosshair_indicator_active"],
	},
	checkEngineColor = {
		["normal"]			= Color["crosshair_checkengine_normal"],
		["notravel"]		= Color["crosshair_checkengine_notravel"],
		["restricted"]		= Color["crosshair_checkengine_restricted"],
		["noboost"]			= Color["crosshair_checkengine_noboost"],
		["noboost_stance"]	= Color["crosshair_checkengine_noboost"],
		["disabled"]		= Color["crosshair_checkengine_disabled"],
		["disabled2"]		= Color["crosshair_checkengine_disabled2"],
	},
	checkEngineAnimationSpeed = 3,
	progressBarColor = {
		["grid"] = Color["crosshair_progressbar_grid"],
		["ring"] = Color["crosshair_progressbar_ring"],
		["icon"] = Color["crosshair_progressbar_icon"],
	},
	setaColor = {
		["ring"]			= Color["crosshair_seta_ring"],
		["inactive"]		= Color["crosshair_seta_unavailable"],
		["unavailable"]		= Color["crosshair_seta_unavailable"],
		["available"]		= Color["crosshair_seta_available"],
		["active"]			= Color["crosshair_seta_active"],
		["active_slow"]		= Color["crosshair_seta_active"],
	},

	-- icon settings
	droneIcons = { -- the drone icons used in the drone panel (left to right)
		[1] = "hud_drone_minedrone",
		[2] = "hud_drone_fightdrone",
		[3] = "hud_drone_tradedrone"
	},

	-- settings
	speedoflight = 299792458,
	indicatorIconSize = 15,
	indicatorOffsetX = 0,
	indicatorOffsetY = -175,

	-- boostbar animation
	boostBarFilledAnimationDuration = 0.5,

	-- boostbar animation
	stanceErrorAnimationDuration = 0.5,

	-- player hull/shield animation
	damageAnimationMinAlpha = 20,
	damageAnimationSpeedFactor = 20,
	damageAnimationDuration = 1,
	damageBarAnimationDelay = 1,
	damageBarAnimationDuration = 1,

	-- attack jiggle
	jiggleEnabled = true,
	maxJiggle = 2.5,
	jiggleDuration = 0.5,

	-- mouse steering line
	mouseSteeringLineWidth = 2,
	mouseSteeringLineColor = Color["crosshair_mousesteering_line"],

	-- glow
	glowfactors = {
		text = 0.5,
	},

	-- external view
	centralElementsOffset = 50,

	defaultFontSize = 10,
	ammoFontSize = 14,
	weaponAmmoFontSize = 14,
}

-- text array containing localized text
local L = {
	["FLR"] = ffi.string(C.GetLocalizedText(1001, 5106, "FLR")),
	["m/s"] = ffi.string(C.GetLocalizedText(1001, 113, "m/s")),
	["km"] = ffi.string(C.GetLocalizedText(1001, 108, "km")),
	["s"] = ffi.string(C.GetLocalizedText(1001, 100, "s")),
	["c"] = ffi.string(C.GetLocalizedText(1001, 124, "c")),
}

-- private member data
local private = {
	contract = nil,                           -- the Anark contract element
	crosshairElement = nil,                   -- crosshair element
	interactElement = nil,                    -- interact element
	missileLockElement = nil,                 -- the missile lock element
	missileIncomingElement = nil,             -- the missile incoming element
	playerActualSpeedbarElement = nil,        -- player actual speedbar element
	playerBoostBarElement = nil,              -- player boostbar element
	playerHullElement = nil,                  -- player hullbar element
	playerHullBarElement = nil,               -- player hullbar bar element
	playerHullDamageElement = nil,            -- player hullbar damage element
	playerHullBackgroundElement = nil,        -- player hullbar background element
	playerShieldElement = nil,                -- player shieldbar element
	playerShieldBarElement = nil,             -- player shieldbar bar element
	playerShieldDamageElement = nil,          -- player shieldbar damage element
	playerShieldDamageElementMaterial = nil,  -- player shieldbar damage element
	playerSpeedValueElement = nil,            -- player actual speed text element
	playerTargetedSpeedbarElement = nil,      -- player targeted speedbar element
	playerTargetedSpeedbarArrowElement = nil, -- player targeted speedbar arrow element
	targetSpeedbarElement = nil,              -- the target's speedbar element (for matching speed handling)
	targetSpeedbarArrowElement = nil,         -- the target's speedbar arrow element (for matching speed handling)
	targetSpeedbarArrowMaterialElement = nil, -- the target's speedbar arrow element material
	setaElement = nil,                        -- the SETA element
	checkEngineElement = nil,                 -- the checkengine element
	countermeasureElement = nil,              -- the countermeasure text element
	oxygenElement = nil,                      -- the oxygen element
	textElement = nil,                        -- the interact text element
	targetArrowElement = nil,                 -- the target arrow element group (inside the target ring element)
	targetRingElement = nil,                  -- the target ring element
	missionArrowHidden = false,               -- indicates whether the mission arrow is hidden atm
	targetArrowHidden = false,                -- indicates whether the target arrow is hidden atm
	progressbarElement = nil,                 -- the (scan-)progress bar element
	progressbarRangeElement = nil,            -- the range component in the progress bar element
	missionArrowElement = nil,                -- the mission arrow element group (inside the mission ring element)
	missionRingElement = nil,                 -- the mission ring element (aka: mission target arrow)
	interactElementShown = false,             -- indicates whether the interaction element is shown or hidden
	mouseSteeringElement = nil,               -- the mouse steering element
	indicatorElements = {
		["flightassist"] = {
			elementName = "assist_flight",
			element = nil,
			materialElement = nil,
			position = 2,
			type = "bool",
			getState = C.IsFlightAssistActive,
			mode = "off",
		},
		["autopilot"] = {
			elementName = "assist_autopilot",
			element = nil,
			materialElement = nil,
			position = 4,
			type = "bool",
			getState = C.IsAutoPilotActive,
			mode = "off",
		},
		["autoroll"] = {
			elementName = "assist_autoroll",
			element = nil,
			materialElement = nil,
			position = 0,
			type = "int",
			getState = C.GetAutoRollState,
			mode = "off",
		},
		["collisionavoidance"] = {
			elementName = "assist_collisionavoidance",
			element = nil,
			materialElement = nil,
			position = 1,
			type = "int",
			getState = C.GetCollisionAvoidanceState,
			mode = "off",
		},
		["aimassist"] = {
			elementName = "assist_aim",
			element = nil,
			materialElement = nil,
			position = 3,
			type = "int",
			getState = C.GetAimAssistState,
			mode = "off",
		},
		["mousesteering"] = {
			elementName = "assist_mousesteering",
			element = nil,
			materialElement = nil,
			position = 5,
			type = "bool",
			getState = C.IsMouseSteeringActive,
			mode = "off",
			inputmode = "mouse",
		},
	},
	curOxygenLevel = 100,                     -- the current displayed oxygen level (if the bar is shown)
	oxygenBarActive = false,                  -- indicates whehter the oxygen bar is active
	progressbarActive = false,                -- indicates whether the progressbar is active
	targetArrowActive = false,                -- indicates whether a target arrow is active
	targetSpeedbarActive = false,             -- indicates whether the target speedbar element is active
	softtargetPosID = nil,                    -- ID of the pos element representing the softtarget
	missionPosID = nil,                       -- current mission pos ID
	normalMissionPosIDs = {},                 -- all current mission PosIDs
	missionArrowActive = false,               -- indicates whether the mission arrow is active
	softtargetMessageID = nil,                -- the message ID of the current selected target (only, if it has an associated instant action)
	previousMissiontargetAngle = 0,           -- the angle the mission target ring currently represents
	previousTargetAngle = 0,                  -- the angle the target ring currently represents
	crosshairActive = false,                  -- indicates whether the crosshair is active
	rescanSlideChanges = false,               -- indicates whether all crosshair elements should be rechecked for required slide-changes
	currentInteraction = nil,                 -- the current target monitor interaction being displayed (if any)
	interactText = nil,                       -- the interaction text (if any) which is displayed atm
	targetText = "",                          -- target text which is displayed atm
	playerShieldbarActive = false,            -- indicates whether the player shield bar is active atm
	missileLockActive = false,                -- indicates whether the missile lock warning is active atm
	missileIncomingActive = false,            -- indicates whether the missile incoming warning is active atm
	prevTargetedSpeedTime = nil,              -- time value displayed currently on the targeted speed speedbar
	prevTargetSpeedTime = nil,                -- time value displayed currently on the target speed speedbar
	curPlayerHull = nil,                      -- value the player hull bar represents atm
	prevPlayerHull = nil,                     -- value the player hull damage bar is based on
	prevPlayerHullTime = nil,                 -- time value the player hull damage bar animation is based on
	lastHullDamageTime = nil,                 -- time value the player hull bar damage animation is based on
	curPlayerShield = nil,                    -- value the player shield bar represents atm
	prevPlayerShield = nil,                   -- value the player shield damage bar is based on
	prevPlayerShieldTime = nil,               -- time value the player shield damage bar animation is based on
	lastShieldDamageTime = nil,               -- time value the player shield bar damage animation is based on
	hasSeta = false,                          -- indicates whether we have SETA installed
	setaActive = false,                       -- indicates whether SETA is active atm
	setaMode = "inactive",                    -- the current mode for the SETA element (inactive, activate, unavailable, available)
	checkEngineMode = "normal",               -- indicates the status of the check engine light
	numCountermeasures = -1,                  -- the number of counter measures (-1 => not initialized yet)
	numWeaponSlots = 0,                       -- number of available slots for primary/secondary weapons
	numTurretSlots = 0,                       -- number of available slots for turrets
	numPrimaryWeapons = 0,                    -- number of installed primary weapons
	numSecondaryWeapons = 0,                  -- number of installed secondary weapons
	numTurrets = 0,                           -- number of installed turrets
	prevActualSpeedTime = nil,                -- time value displayed currently on the actual speed speedbar
	prevBoostState = false,                   -- the previous boost state of the speedbar
	prevTargetBoostState = false,             -- the previous boost state of the target displayed on the speedbar
	boostBarFull = true,                      -- whether the boost bar is currently full
	prevBoostBarTime = nil,                   -- previous boostbar time value
	dronePanel = {                            -- elements and data related to the drone panel
		["mainElement"] = nil,                    -- the drone main element
		["active"] = false,                       -- indicates whether the drone panel is active atm (or being activated)
		["type"] = {
			-- [x] = {                            -- (x = 1-3)
				-- [element]                  = nil,       -- the drone type column element
				-- [active]                   = false,     -- indicates whether the drone type column is active atm (or being activated)
				-- [deactivationDelay]        = nil | time -- time at which the drone panel's disappear animation will start (nil, if no disappearing is scheduled atm)
				-- [mouseInteractionsEnabled] = boolean    -- indicates whether mouse interactions are enabled atm
				-- [drone] = {
					-- [colorMode]       = ""|mode    -- the current color mode, the drone icon is set to ("", if not initialized)
					-- [iconElement]     = nil        -- the icon (texture) element
					-- [materialElement] = nil        -- the icon (material) element
					-- [pickElement]     = nil        -- the icon element used for mouse picking (aka: the model element)
				-- },
				-- [mode] = {
					-- [colorMode]       = ""|mode    -- the current color mode, the mode icon is set to ("", if not initialized)
					-- [currentIcon]     = ""|mode    -- the icon currently displayed ("", if not initialized)
					-- [iconElement]     = nil        -- the icon (texture) element
					-- [materialElement] = nil        -- the icon (material) element
					-- [pickElement]     = nil        -- the icon element used for mouse picking (aka: the model element)
				-- },
				-- [number] = {
					-- [colorMode]          = ""|mode -- the current color mode, the number is set to ("", if not initialized)
					-- [currentMode]        = mode    -- the current number mode ("inactive", "single", "double")
					-- [dashElement]        = nil     -- the dash element
					-- [element]            = nil     -- the number element
					-- [partialTextElement] = nil     -- the partial number text element
					-- [totalTextElement]   = nil     -- the total number text element
				-- }
			-- }
		}
	},
	weaponPanel = {
		["primary"] = {
			["panel"] = nil,                         -- the panel element
			["groups"] = {
				-- [x] = nil,                        -- primary weapon group element (x = 1-4)
			},
			["weapons"] = {
				-- [x] = {                           -- (x = 1-8)
					-- [element] = nil,              -- weapon element
					-- [icon] = {
						-- [iconElement] = nil,         -- the weapon icon (component) element
						-- [textureElement] = nil,      -- the weapon icon (texture) element
						-- [color] = nil|{rgba}         -- the current icon color value (nil, if no color set yet)
					-- },
					-- [ammo] = {
						-- [ammoElement] = nil,         -- the ammo (component) element
						-- [textElement] = nil,         -- the ammo text element
						-- [usesAmmo] = true|false,     -- indicates whether the weapon uses ammo
					-- },
					-- [bar] = {
						-- [barElement] = nil,          -- the bar element
						-- [fillElement] = nil,         -- the fill element
						-- [fill2Element] = nil,        -- the fill2 element
						-- [color] = nil|{rgba},        -- the current bar color value (nil, if no color set yet)
						-- [time] = nil|number          -- the current fill bar time value (nil, if not set yet)
					-- }
				-- }
			}
		},
		["secondary"] = {
			["panel"] = nil,                         -- the panel element
			["groups"] = {
				-- [x] = nil,                        -- secondary weapon group element (x = 1-4)
			},
			["weapons"] = {
				-- [x] = {                           -- (x = 1-8)
					-- [element] = nil,              -- weapon element
					-- [icon] = {
						-- [iconElement] = nil,         -- the weapon icon (component) element
						-- [textureElement] = nil,      -- the weapon icon (texture) element
						-- [color] = nil|{rgba}         -- the current icon color value (nil, if no color set yet)
						-- [curIcon] = string|nil,      -- the current set weapon(icon) (nil, if not set yet)
					-- },
					-- [ammo] = {
						-- [ammoElement] = nil,         -- the ammo (component) element
						-- [textElement] = nil,         -- the ammo text element
						-- [usesAmmo] = true|false,     -- indicates whether the weapon uses ammo
					-- },
					-- [bar] = {
						-- [barElement] = nil,          -- the bar element
						-- [fillElement] = nil,         -- the fill element
						-- [fill2Element] = nil,        -- the fill2 element
						-- [color] = nil|{rgba},        -- the current bar color value (nil, if no color set yet)
						-- [time] = nil|number          -- the current fill bar time value (nil, if not set yet)
					-- }
				-- }
			}
		},
		["turrets"] = {
			["panel"] = nil,                  -- the panel element
			["turrets"] = {
				-- [x] = {                    -- (x = 1-8)
					-- [element] = nil,       -- turret element
					-- [mode] = {
						-- [iconElement] = nil,         -- the turret mode (component) element
						-- [textureElement] = nil,      -- the turret mode (texture) element
						-- [curMode] = string|nil,      -- the current set mode(icon) (nil, if not set yet)
					-- }
					-- [icon] = {
						-- [iconElement] = nil,         -- the weapon icon (component) element
						-- [textureElement] = nil,      -- the weapon icon (texture) element
						-- [color] = nil|{rgba}         -- the current icon color value (nil, if no color set yet)
						-- [curIcon] = string|nil,      -- the current set turret(icon) (nil, if not set yet)
					-- },
					-- [ammo] = {
						-- [ammoElement] = nil,          -- the ammo (component) element
						-- [textElement] = nil,          -- the ammo text element
						-- [usesAmmo] = true|false,      -- indicates whether the weapon uses ammo
					-- }
				-- }
			}
		}
	}
}

-- local functions forward declarations
local onActiveWeaponGroupChanged
local onBoostInput
local onExternalTargetView
local onDroneClick
local onDroneOver
local onDroneOut
local onDroneModeClick
local onDroneModeOver
local onDroneModeOut
local onFlightControlStarted
local onFlightControlStopped
local onGamePlanChange
local onInteractionHidden
local onInteractionShown
local onInventoryWaresAdded
local onMissileIncoming
local onMissileLockInitiated
local onMissileLockLost
local onPlayerActivityChanged
local onPrimaryMissiontargetChanged
local onResetHUDColors
local onSofttargetChanged
local onScanStarted
local onScanAborted
local onScanFinished
local onSetaActivated
local onSetaDeactivated
local onShootInput
local onTeleportSucceeded
local onTurretModeClick
local onTurretModeOver
local onTurretModeOut
local onTurretClick
local onTurretOver
local onTurretOut
local onUnlock
local onUpdateHUDColors
local onWeaponGroupChanged
local abortScan
local activateCrosshair
local activateDronePanel
local activateDroneType
local activateInteractElement
local activateMissileIncoming
local activateMissileLock
local activateMissionArrow
local activateOxygenBar
local activatePlayerShieldbar
local activateProgressbar
local activateSeta
local activateTargetArrow
local activateWeaponPanel
local activationScan
local colorDroneType
local deactivateCrosshair
local deactivateDronePanel
local deactivateDroneType
local deactivateInteractElement
local deactivateMissileIncoming
local deactivateMissileLock
local deactivateMissionArrow
local deactivateOxygenBar
local deactivatePlayerShieldbar
local deactivateSeta
local deactivateTargetRing
local deactivateProgressbar
local deactivateWeaponPanel
local disableDroneTypeInteractions
local enableDroneTypeInteractions
local finishScan
local initDronePanel
local initPlayerHullShield
local initScale
local initWeaponPanel
local setBarState
local setCentralElementsPosition
local setColorHelper
local setDecoColors
local setDecoColorsWithIntensity
local setTextColor
local setTurretColor
local setTurretMode
local setWeaponColor
local startScan
local updateActivityColor
local updateArrowState
local updateBoostBar
local updateCheckEngineLight
local updateCountermeasures
local updateDronePanel
local updateDroneType
local updateHullShield
local updateIndicators
local updateMatchSpeedElement
local updateMissionArrow
local updateOxygenBar
local updateProgressbar
local updateSeta
local updateSpeedbar
local updateTargetArrow
local updateTargetText
local updateText
local updateWeaponGroup
local updateWeaponPanel

-- Gameface lifetime functions
function self:onInitialize()
	local scene           = getElement("Scene")
	local uiAnchorElement = getElement("Layer.ui_anchor", scene)

	private.crosshairElement = getElement("crosshair", uiAnchorElement)
	private.centralElements = getElement("central_elements", private.crosshairElement)
	private.interactElement  = getElement("interact", uiAnchorElement)
	private.textElement      = getElement("Text", private.interactElement)

	-- crosshair
	setColorHelper(getElement("crosshair_03.Cylinder13.ui_gradient_05", private.crosshairElement), nil, config.crosshairColor.normal)
	setColorHelper(getElement("crosshair_03.crosshair_03_shadow.Cylinder01.ui_gradient_05", private.crosshairElement), nil, config.crosshairColor.shadow)

	-- player speedbar
	local speedbar = getElement("speedbar", private.centralElements)
	private.playerActualSpeedbarElement					= getElement("currentspeed", speedbar)
	private.playerTargetedSpeedbarElement				= getElement("targetedspeed", speedbar)
	private.playerSpeedValueElement						= getElement("playerspeed", private.centralElements)
	private.playerTargetedSpeedbarArrowElement			= getElement("speedbar_arrow.speedbar_arrow", private.playerTargetedSpeedbarElement)
	private.playerTargetedSpeedbarArrowMaterialElement	= getElement("4", private.playerTargetedSpeedbarArrowElement)
	private.targetSpeedbarElement						= getElement("targetspeed", speedbar)
	private.targetSpeedbarArrowElement					= getElement("speedbar_arrow.target_speed_indicator", private.targetSpeedbarElement)
	private.targetSpeedbarArrowMaterialElement			= getElement("ui_gradient_outline", private.targetSpeedbarArrowElement)
	private.playerBoostBarElement						= getElement("boostbar.currentboost", private.centralElements)
	private.playerBoostBarMaterialElement				= getElement("playerboostbar_01.boostbar_0.boostbar", private.playerBoostBarElement)

	setColorHelper(private.playerTargetedSpeedbarArrowMaterialElement, private.playerTargetedSpeedbarArrowElement, config.speedBarColor.normal)
	setColorHelper(private.targetSpeedbarArrowMaterialElement, private.targetSpeedbarArrowElement, config.speedBarColor.normal)
	setColorHelper(getElement("playerspeedbar_03.Object036.2", private.playerActualSpeedbarElement), nil, config.speedBarColor.base)
	setColorHelper(getElement("playerspeedbar_0point.Object18.2", private.playerActualSpeedbarElement), nil, config.speedBarColor.zeropoint)
	setColorHelper(getElement("playerspeedbar_max_point.Object38.2", private.playerActualSpeedbarElement), nil, config.speedBarColor.maxpoint)
	setColorHelper(getElement("playerspeedbar_boost_01.Object39.2", private.playerActualSpeedbarElement), nil, config.speedBarColor.boost)
	setColorHelper(private.playerBoostBarMaterialElement, nil, config.boostBarColor.full)

	-- player shield/hull
	private.playerHullElement                 = getElement("playerhull", private.centralElements)
	private.playerHullBarElement              = getElement("playerhullbar_2", private.playerHullElement)
	private.playerHullBarElementMaterial      = getElement("playerhullbar_02.Object19.2", private.playerHullBarElement)
	private.playerHullDamageElement           = getElement("playerhullbar_damage", private.playerHullElement)
	private.playerHullBackgroundElement       = getElement("playerhullbar_background", private.playerHullElement)
	private.playerShieldElement               = getElement("playershield", private.centralElements)
	private.playerShieldBarElement            = getElement("playershieldbar", private.playerShieldElement)
	private.playerShieldBarElementMaterial    = getElement("Object14.2", private.playerShieldBarElement)
	private.playerShieldDamageElement         = getElement("playershield_damage", private.playerShieldElement)
	private.playerShieldDamageElementMaterial = getElement("playershieldbar.Object14.2", private.playerShieldDamageElement)

	setColorHelper(private.playerHullBarElementMaterial, nil, config.hullBarColor)
	setColorHelper(getElement("playerhullbar_damage.Object19.2", private.playerHullDamageElement), nil, config.hullBarDamageColor)
	setColorHelper(getElement("PlayerStatsRing_FX.postglow4.Material4407", private.playerHullElement), nil, Color["crosshair_hull_gradient_glow"])
	setColorHelper(private.playerShieldBarElementMaterial, nil, config.shieldBarColor)
	setColorHelper(getElement("PlayerStatsRing_FX.postglow4.Material4407", private.playerShieldElement), nil, Color["crosshair_shield_gradient_glow"])

	-- (mission) target ring
	private.missionRingElement  = getElement("missiontarget", private.crosshairElement)
	private.missionArrowElement = getElement("Group", private.missionRingElement)
	private.targetRingElement   = getElement("softtarget", private.crosshairElement)
	private.targetArrowElement  = getElement("Group", private.targetRingElement)

	setColorHelper(getElement("arrow sele.ui_gradient_05", private.missionArrowElement), nil, config.missionArrowColor)
	setColorHelper(getElement("arrow sele.ui_gradient_05", private.targetArrowElement), nil, config.targetArrowColor)

	-- progress bar
	private.progressbarElement      = getElement("progressbar", private.crosshairElement)
	private.progressbarRangeElement = getElement("ring", private.progressbarElement)

	setColorHelper(getElement("scan_icon.Material364", private.progressbarElement), nil, config.progressBarColor.icon)
	setColorHelper(getElement("scangrid.Material366", private.progressbarElement), nil, config.progressBarColor.grid)

	-- missile warning
	private.missileLockElement     = getElement("missilelock", private.centralElements)
	private.missileIncomingElement = getElement("missileincoming", private.centralElements)

	-- counter measures
	private.countermeasureElement = getElement("countermeasures", private.centralElements)

	-- oxygen display
	private.oxygenElement = getElement("o2", private.centralElements)

	-- SETA
	private.setaElement = getElement("seta", private.centralElements)

	setColorHelper(getElement("ring_gradient.ring.03 - Default", private.setaElement), nil, config.setaColor.ring)

	-- indicators
	for _, entry in pairs(private.indicatorElements) do
		entry.element = getElement(entry.elementName, private.centralElements)
		entry.materialElement = getElement("assist_quad.Material1802", entry.element)
	end

	-- check engine
	private.checkEngineElement = getElement("checkengine", private.centralElements)

	-- mouse steering
	private.mouseSteeringElement =  getElement("mousesteering", private.crosshairElement)
	setColorHelper(getElement("mousesteering.mousesteering", private.mouseSteeringElement), nil, config.mouseSteeringLineColor)

	-- drone panel
	local dronePanel = private.dronePanel
	dronePanel.mainElement = getElement("drones", private.crosshairElement)

	for i = 1, 3 do
		local droneTypeElement     = getElement("drone"..i, dronePanel.mainElement)
		local numberElement        = getElement("number", droneTypeElement)
		local droneModelElement    = getElement("drone_icon", droneTypeElement)
		local droneMaterialElement = getElement("drone_icon", droneModelElement)
		local modeModelElement     = getElement("mode_icon", droneTypeElement)
		local modeMaterialElement  = getElement("mode_icon", modeModelElement)
		dronePanel.type[i] = {
			["element"] = droneTypeElement,
			["active"] = false,
			["drone"] = {
				["colorMode"]       = "",
				["iconElement"]     = getElement("drone_icon", droneMaterialElement),
				["materialElement"] = droneMaterialElement,
				["pickElement"]     = droneModelElement
			},
			["mode"] = {
				["colorMode"]       = "",
				["currentIcon"]     = "",
				["iconElement"]     = getElement("mode_icon", modeMaterialElement),
				["materialElement"] = modeMaterialElement,
				["pickElement"]     = modeModelElement
			},
			["number"] = {
				["colorMode"]          = "",
				["currentMode"]        = "inactive",
				["dashElement"]        = getElement("dash.dash", numberElement),
				["element"]            = numberElement,
				["partialTextElement"] = getElement("partial", numberElement),
				["totalTextElement"]   = getElement("total", numberElement)
			}
		}
	end

	-- weapon panel
	local weaponPanel = private.weaponPanel
	weaponPanel.primary.panel   = getElement("weapon_group1", private.crosshairElement)
	weaponPanel.secondary.panel = getElement("weapon_group2", private.crosshairElement)
	weaponPanel.turrets.panel   = getElement("turrets", private.crosshairElement)
	for i = 1, 4 do
		weaponPanel.primary.groups[i]   = getElement("group"..i, weaponPanel.primary.panel)
		setColorHelper(getElement("Rectangle.ui_gradient_05", weaponPanel.primary.groups[i]), nil, config.weaponGroupColor.inactive)

		weaponPanel.secondary.groups[i] = getElement("group"..i, weaponPanel.secondary.panel)
		setColorHelper(getElement("Rectangle.ui_gradient_05", weaponPanel.secondary.groups[i]), nil, config.weaponGroupColor.inactive)
	end
	for i = 1, 8 do
		weaponPanel.primary.weapons[i] = {
			["element"] = getElement("weapon"..i, weaponPanel.primary.panel),
			["icon"] = {
				["iconElement"]    = getElement("weapon"..i..".icon", weaponPanel.primary.panel),
				["materialElement"] = getElement("weapon"..i..".icon.Material2086", weaponPanel.primary.panel),
				["textureElement"] = getElement("weapon"..i..".icon.Material2086.icon", weaponPanel.primary.panel),
			},
			["ammo"] = {
				["ammoElement"] = getElement("weapon"..i..".ammo", weaponPanel.primary.panel),
				["textElement"] = getElement("weapon"..i..".ammo.Text", weaponPanel.primary.panel),
				["text2Element"] = getElement("weapon"..i..".ammo.Text2", weaponPanel.primary.panel),
			},
			["bar"] = {
				["barElement"]  = getElement("weapon"..i..".bar", weaponPanel.primary.panel),
				["materialElement1"]  = getElement("weapon"..i..".bar.Rectangle1.Material381", weaponPanel.primary.panel),
				["materialElement2"]  = getElement("weapon"..i..".bar.Rectangle2.Material381", weaponPanel.primary.panel),
				["fillElement"] = getElement("weapon"..i..".bar.fill", weaponPanel.primary.panel),
				["materialElement3"]  = getElement("weapon"..i..".bar.fill.Rectangle.Material381", weaponPanel.primary.panel),
				["fill2Element"] = getElement("weapon"..i..".bar.fill2", weaponPanel.primary.panel),
				["materialElement4"]  = getElement("weapon"..i..".bar.fill2.Rectangle.Material381", weaponPanel.primary.panel),
			}
		}

		setTextColor(weaponPanel.primary.weapons[i].ammo.textElement, config.weaponAmmoColor)

		weaponPanel.secondary.weapons[i] = {
			["element"] = getElement("weapon"..i, weaponPanel.secondary.panel),
			["icon"] = {
				["iconElement"]    = getElement("weapon"..i..".icon", weaponPanel.secondary.panel),
				["materialElement"] = getElement("weapon"..i..".icon.Material2086", weaponPanel.secondary.panel),
				["textureElement"] = getElement("weapon"..i..".icon.Material2086.icon", weaponPanel.secondary.panel),
			},
			["ammo"] = {
				["ammoElement"] = getElement("weapon"..i..".ammo", weaponPanel.secondary.panel),
				["textElement"] = getElement("weapon"..i..".ammo.Text", weaponPanel.secondary.panel),
				["text2Element"] = getElement("weapon"..i..".ammo.Text2", weaponPanel.secondary.panel),
			},
			["bar"] = {
				["barElement"]  = getElement("weapon"..i..".bar", weaponPanel.secondary.panel),
				["materialElement1"]  = getElement("weapon"..i..".bar.Rectangle1.Material381", weaponPanel.secondary.panel),
				["materialElement2"]  = getElement("weapon"..i..".bar.Rectangle2.Material381", weaponPanel.secondary.panel),
				["fillElement"] = getElement("weapon"..i..".bar.fill", weaponPanel.secondary.panel),
				["materialElement3"]  = getElement("weapon"..i..".bar.fill.Rectangle.Material381", weaponPanel.secondary.panel),
				["fill2Element"] = getElement("weapon"..i..".bar.fill2", weaponPanel.secondary.panel),
				["materialElement4"]  = getElement("weapon"..i..".bar.fill2.Rectangle.Material381", weaponPanel.secondary.panel),
			}
		}

		setTextColor(weaponPanel.secondary.weapons[i].ammo.textElement, config.weaponAmmoColor)

		weaponPanel.turrets.turrets[i] = {
			["element"] = getElement("turret"..i, weaponPanel.turrets.panel),
			["icon"] = {
				["iconElement"]    = getElement("turret"..i..".icon", weaponPanel.turrets.panel),
				["materialElement"] = getElement("turret"..i..".icon.Material2086", weaponPanel.turrets.panel),
				["textureElement"] = getElement("turret"..i..".icon.Material2086.icon", weaponPanel.turrets.panel)
			},
			["ammo"] = {
				["ammoElement"] = getElement("turret"..i..".ammo", weaponPanel.turrets.panel),
				["textElement"] = getElement("turret"..i..".ammo.Text", weaponPanel.turrets.panel),
			},
			["mode"] = {
				["iconElement"] = getElement("turret"..i..".mode", weaponPanel.turrets.panel),
				["materialElement"] = getElement("turret"..i..".mode.Material2086", weaponPanel.turrets.panel),
				["textureElement"] = getElement("turret"..i..".mode.Material2086.icon", weaponPanel.turrets.panel)
			}
		}

		setColorHelper(weaponPanel.turrets.turrets[i].mode.materialElement, nil, config.turretModeColor)
		setTextColor(weaponPanel.turrets.turrets[i].ammo.textElement, config.weaponAmmoColor)
	end

	local activity, activitycolor, _ = GetPlayerActivity()
	if activity == "none" then
		activitycolor = nil
	else
		activitycolor = Color[activitycolor]
	end
	setDecoColors(activitycolor)

	initScale(uiAnchorElement)

	-- register for events
	private.contract = getElement("UIContract", scene)
	registerForEvent("activeWeaponGroupChanged",     private.contract, onActiveWeaponGroupChanged)
	registerForEvent("boostinput",                   private.contract, onBoostInput)
	registerForEvent("externalTargetViewActive",     private.contract, function () return onExternalTargetView(true) end)
	registerForEvent("externalTargetViewInactive",   private.contract, function () return onExternalTargetView(false) end)
	registerForEvent("flightControlStarted",         private.contract, onFlightControlStarted)
	registerForEvent("flightControlStopped",         private.contract, onFlightControlStopped)
	registerForEvent("gameplanchange",               private.contract, onGamePlanChange)
	registerForEvent("inputModeChanged",             private.contract, onInputModeChanged)
	registerForEvent("interactionHidden",            private.contract, onInteractionHidden)
	registerForEvent("interactionShown",             private.contract, onInteractionShown)
	registerForEvent("missileIncoming",              private.contract, onMissileIncoming)
	registerForEvent("missileLockInitiated",         private.contract, onMissileLockInitiated)
	registerForEvent("missileLockLost",              private.contract, onMissileLockLost)
	registerForEvent("missionPosIDConnected",        private.contract, onMissionPosIDConnected)
	registerForEvent("missionPosIDDisconnected",     private.contract, onMissionPosIDDisconnected)
	registerForEvent("onUnlock",                     private.contract, onUnlock)
	registerForEvent("playerActivityChanged",        private.contract, onPlayerActivityChanged)
	registerForEvent("priorityMissiontargetChanged", private.contract, onPriorityMissiontargetChanged)
	registerForEvent("reducedSpeedModeActivated",    private.contract, onReducedSpeedModeActivated)
	registerForEvent("reducedSpeedModeDeactivated",  private.contract, onReducedSpeedModeDeactivated)
	registerForEvent("scanAborted",                  private.contract, onScanAborted)
	registerForEvent("scanFinished",                 private.contract, onScanFinished)
	registerForEvent("scanStarted",                  private.contract, onScanStarted)
	registerForEvent("setaActivated",                private.contract, onSetaActivated)
	registerForEvent("setaDeactivated",              private.contract, onSetaDeactivated)
	registerForEvent("shootinput",                   private.contract, onShootInput)
	registerForEvent("softtargetChanged",            private.contract, onSofttargetChanged)
	registerForEvent("teleportSucceeded",            private.contract, onTeleportSucceeded)
	registerForEvent("weaponGroupChanged",           private.contract, onWeaponGroupChanged)
	registerForEvent("updateHUDColors",              private.contract, onUpdateHUDColors)
	registerForEvent("resetHUDColors",               private.contract, onResetHUDColors)

	-- register for SETA relevant events (to detect installation)
	-- #coreUIMed - most likely we'd also add removal detection (mods can do that presumably -> backport to XR then?)
	local hasSeta = C.HasSeta()
	if not hasSeta then
		-- listening to this event is only required, if we don't have SETA yet
		registerForEvent("inventoryWaresAdded", private.contract, onInventoryWaresAdded)
		NotifyOnInventoryWaresAdded(private.contract)
	end
	initSeta(hasSeta)

	-- notify on game events
	NotifyOnActiveWeaponGroupChanged(private.contract)
	NotifyOnIncomingMissile(private.contract)
	NotifyOnMissileLockInitiated(private.contract)
	NotifyOnMissileLockLost(private.contract)
	NotifyOnPlayerActivityChanged(private.contract)
	NotifyOnPlayerFlightControlStarted(private.contract)
	NotifyOnPlayerFlightControlStopped(private.contract)
	NotifyOnScanAborted(private.contract)
	NotifyOnScanFinished(private.contract)
	NotifyOnScanStarted(private.contract)
	NotifyOnTeleportSucceeded(private.contract)
	NotifyOnWeaponGroupChanged(private.contract)

	-- clear text elements
	setAttribute(private.playerSpeedValueElement, "textstring", "")
	setAttribute(private.countermeasureElement, "textstring", "")

	-- glow
	setTextColor(private.textElement, Color["crosshair_interaction_text"])
	setTextColor(private.playerSpeedValueElement, config.speedBarColor.normal)

	setTextColor(private.countermeasureElement, Color["crosshair_countermeasures"])

	if HasFlightControl() and (not C.IsExternalTargetMode()) then
		activateCrosshair()
	else
		deactivateCrosshair()
	end
	
	setCentralElementsPosition(C.IsExternalViewActive())

	-- must be done after crosshairActive was initialized
	initWeaponPanel()

	initDronePanel()

	-- initialize the priority missiontarget ring correctly (note: at the time of coding this, C.GetPriorityMissiontargetPOSID() will always return nil here - this is due to the fact
	-- that the crosshair is initialized alongside the target system --- if that ever changes, this code ensures that the priority mission target is correctly initialized)
	local posID = C.GetPriorityMissiontargetPOSID()
	if posID == -1 then
		posID = nil
	end
	onPriorityMissiontargetChanged(nil, posID)

	-- initialize the scan progress
	if C.IsCurrentlyScanning() then
		startScan()
	end

	-- initialize missile warning
	if C.IsMissileIncoming() then
		activateMissileIncoming()
	end
	if C.IsMissileLockingOn() then
		activateMissileLock()
	end
end

function setDecoColorsWithIntensity(intensity)
	-- limit intensity to at least 0.5 in the UI for text readibility
	local limitedintensity = math.max(intensity, 0.5)
	local activitycolor = {
		r = private.activityColor.r * limitedintensity,
		g = private.activityColor.g * limitedintensity,
		b = private.activityColor.b * limitedintensity,
		a = private.activityColor.a,
		glow = private.activityColor.glow,
	}
	setDecoColors(activitycolor)
end

function setDecoColors(activitycolor)
	local dronecolor = activitycolor or config.dronePanelColor.deco
	local weapongroupactivecolor = activitycolor or config.weaponGroupColor.active
	local weaponcolor = activitycolor or config.weaponDecoColor

	for i = 1, 6 do
		local materialElement = getElement("lines.Rectangle" .. ((i == 1) and "" or i) .. ".Material698", private.dronePanel.mainElement)
		setColorHelper(materialElement, nil, dronecolor)
	end

	for i = 1, 4 do
		setColorHelper(getElement("wp_group_active.ui_gradient_05", private.weaponPanel.primary.groups[i]), nil, weapongroupactivecolor)
		setColorHelper(getElement("wp_group_active.ui_gradient_05", private.weaponPanel.secondary.groups[i]), nil, weapongroupactivecolor)
	end

	for i = 1, 8 do
		setColorHelper(getElement("ring_r.WeaponGroupRing_0"..i..".G0"..i..".line_0"..i..".ui_gradient_06", private.weaponPanel.primary.panel), nil, weaponcolor)
		setColorHelper(getElement("ring_r.WeaponGroupRing_0"..i..".G0"..i..".scanline_0.scanline", private.weaponPanel.primary.panel), nil, weaponcolor)
		setColorHelper(getElement("ring_r.WeaponGroupRing_0"..i..".G0"..i..".gradient_0.scanline", private.weaponPanel.primary.panel), nil, weaponcolor)
		setColorHelper(getElement("weapon"..i..".WeaponBracket.WeaponBracket_scanlineFX_01.Plane006.7", private.weaponPanel.primary.panel), nil, weaponcolor)

		setColorHelper(getElement("ring_r.WeaponGroupRing_0"..i..".G0"..i..".line_0"..i..".ui_gradient_06", private.weaponPanel.secondary.panel), nil, weaponcolor)
		setColorHelper(getElement("ring_r.WeaponGroupRing_0"..i..".G0"..i..".scanline_0.scanline", private.weaponPanel.secondary.panel), nil, weaponcolor)
		setColorHelper(getElement("ring_r.WeaponGroupRing_0"..i..".G0"..i..".gradient_0.scanline", private.weaponPanel.secondary.panel), nil, weaponcolor)
		setColorHelper(getElement("weapon"..i..".WeaponBracket.WeaponBracket_scanlineFX_01.Plane006.7", private.weaponPanel.secondary.panel), nil, weaponcolor)
	end
end

function self:onUpdate()
	if not private.crosshairActive then
		return -- for an inactive crosshair we've got nothing to do atm (no relevant state changes here)
	end

	local rescanSlideChanges = private.rescanSlideChanges
	if private.rescanSlideChanges then
		activationScan()
	else
		-- update the weapon panel in the next frame, since elements just got activated (relevant for the fill-bar atm)
		-- #coreUI - refactor -> change fill-component to get inactive/active slides and explicitly set it --- then change this call to be done in the initial frame too again
		updateWeaponPanel()
	end

	if private.progressbarActive then
		updateProgressbar()
	end

	-- note: if we have the active missile lock warning, check each cycle whether the state changed (i.e. whether the missile is no longer homing onto us - i.e. no event for this state)
	if private.missileIncomingActive then
		if not C.IsMissileIncoming() then
			deactivateMissileIncoming()
		end
	end

	-- update the (mission)target arrows
	-- #StefanLow --- this could be an unnecessary performance impact here --- we should not be required to update the rotation every frame
	-- but on the other hand we expect that the player always does have a softtarget/missiontarget --- hence, it'd be updated every frame anyway
	-- hence the performance loss should be neglactable (=> low prio)
	updateTargetArrow()
	updateMissionArrow()

	updateCountermeasures()
	updateTargetText()
	updateCheckEngineLight()
	updateSpeedbar()
	-- #coreUILow - minor optimization - this call is not required in principle the first time after the player and target bar were both initialized in the frame
	-- and if only one bar was initialized, updating that bar is redundant this frame inside updateHullShield()
	updateHullShield()
	updateSeta()
	updateDronePanel(rescanSlideChanges)
	updateOxygenBar()
	updateIndicators()
	updateMouseSteeringLine()
	updateActivityColor()
end

-------------------------------------
-- Presentation specific callbacks --
-------------------------------------
function onActiveWeaponGroupChanged(_, primaryGroup, group)
	if private.numWeaponSlots > 0 then
		local element
		if primaryGroup then
			element = private.weaponPanel.primary
		else
			element = private.weaponPanel.secondary
		end
		updateWeaponGroup(element, group, true)
	end
end

function onBoostInput(_, success)
	if not success then
		private.boostErrorTime = getElapsedTime()
		private.updateCheckEngineLight = true
	end
end

function onExternalTargetView(active)
	if active then
		deactivateCrosshair()
	else
		activateCrosshair()
	end
end

function onDroneClick(i)
	C.ToggleDrones(i)
end

function onDroneOver(i)
	local dronetype = private.dronePanel.type[i]
	dronetype.ishighlighted = true
	colorDroneType(dronetype, C.GetDroneDetails(i))
end

function onDroneOut(i)
	local dronetype = private.dronePanel.type[i]
	dronetype.ishighlighted = false
	colorDroneType(dronetype, C.GetDroneDetails(i))
end

function onDroneModeClick(i)
	C.CycleNextDroneMode(i)
end

function onDroneModeOver(i)
	local dronetype = private.dronePanel.type[i]
	dronetype.ismodehighlighted = true
	colorDroneType(dronetype, C.GetDroneDetails(i))
end

function onDroneModeOut(i)
	local dronetype = private.dronePanel.type[i]
	dronetype.ismodehighlighted = false
	colorDroneType(dronetype, C.GetDroneDetails(i))
end

function onFlightControlStarted()
	if not C.IsExternalTargetMode() then
		activateCrosshair()
	end
end

function onFlightControlStopped()
	if (not C.IsWidgetsystemRequestingCrosshairVisible()) or C.IsPlayerOccupiedShipDocked() then
		deactivateCrosshair()
	end
end

function onGamePlanChange(_, gameplan)
	setCentralElementsPosition(gameplan == "external")
end

function onInputModeChanged(_, mode)
	updateIndicatorScalePositionAndActivation(mode)
end

function onInteractionHidden(_, interactionID)
	if interactionID ~= private.currentInteraction then
		return -- different interaction ID - might occur, when we retrieve successive shown/hidden interaction events
	end

	private.interactText = nil
	private.currentInteraction = nil
	updateText()
end

function onInteractionShown(_, interactionID, interactionText)
	private.currentInteraction = interactionID
	-- do not display the text (and background element), if we have either no interaction (nil) or the interaction doesn't specify a to displayed text ("")
	if interactionText ~= nil and interactionText ~= "" then
		private.interactText = interactionText
		updateText()
	end
end

function onInventoryWaresAdded()
	-- check whether we got the Seta inventory item
	if C.HasSeta() then
		initSeta(true)
		-- once we got the event we are no longer interested in it
		unregisterForEvent("inventoryWaresAdded", private.contract, onInventoryWaresAdded)
	end
end

function onPriorityMissiontargetChanged(_, posID)
	private.missionPosID = posID

	if posID ~= nil then
		activateMissionArrow()
	else
		deactivateMissionArrow()
	end
end

function onMissileIncoming()
	activateMissileIncoming()
end

function onMissileLockInitiated()
	activateMissileLock()
end

function onMissileLockLost()
	if private.missileLockActive and not C.IsMissileLockingOn() then
		-- note: we must check via IsMissileLockingOn() wether in fact the last missile lock was lost (rather than some other missile lock still being in progress)
		deactivateMissileLock()
	end
end

function onMissionPosIDConnected(_, posID)
	if posID >= 0 then
		private.normalMissionPosIDs[posID] = true
	else
		private.normalMissionPosIDs = {}
	end

	if private.missionPosID == nil then
		if next(private.normalMissionPosIDs) then
			activateMissionArrow()
		else
			deactivateMissionArrow()
		end
	end
end

function onMissionPosIDDisconnected(_, posID)
	private.normalMissionPosIDs[posID] = nil

	if private.missionPosID == nil then
		if next(private.normalMissionPosIDs) then
			activateMissionArrow()
		else
			deactivateMissionArrow()
		end
	end
end

function onPlayerActivityChanged()
	local activity, activitycolor, _ = GetPlayerActivity()
	if activity == "none" then
		activitycolor = nil
	else
		activitycolor = Color[activitycolor]
	end
	private.activityColor = activitycolor
	if activityolor then
		setDecoColorsWithIntensity(C.GetModeLightIntensity())
	else
		setDecoColors(private.activityColor)
	end
end

function onUpdateHUDColors(_, colorstring)
	local colors = {}
	for color in string.gmatch(colorstring, "([^;]+)") do
		table.insert(colors, tonumber(color))
	end

	private.activityColor = { r = colors[1], g = colors[2], b = colors[3], a = 90, glow = 0.5 }
	setDecoColors(private.activityColor, private.activityBGColor)
end

function onResetHUDColors()
	private.activityColor = nil
	private.activityBGColor = nil
	setDecoColors(private.activityColor, private.activityBGColor)
end

function onReducedSpeedModeActivated()
	activateSeta("active_slow")
end

function onReducedSpeedModeDeactivated()
	deactivateSeta(false)
end

function onScanAborted()
	abortScan()
end

function onScanFinished()
	finishScan()
end

function onScanStarted()
	startScan()
end

function onSetaActivated()
	activateSeta("active")
end

function onSetaDeactivated()
	deactivateSeta(false)
end

function onShootInput()
	local ship = C.GetPlayerOccupiedShipID()
	if ship ~= 0 then
		if C.IsObjectShootingDisabledByStanceOnly(ship) then
			private.shootErrorTime = getElapsedTime()
		end
	end
end

function onSofttargetChanged(_, newsofttargetmessageid, posID)
	-- #coreUIMed - cleanup --- move deactivation of target-relevant elements to separate function
	-- just flag the softtarget change, don't do it right away here, since a goToSlide() call might be pending which
	-- might not have been processed just yet
	if newsofttargetmessageid then
		local details = C.GetMessageDetails3(newsofttargetmessageid)
		-- newsofttargetmessageid could point to an invalid (aka already destroyed) message -- this can happen, if the message was being destroyed in-between the
		-- softtarget changed event dispatch process --- so we have to handle and recheck this here
		if details.componentID == 0 then
			posID = nil
			deactivateTargetArrow()
			private.targetText = ""
			private.softtargetMessageID = nil
			updateText()
		else
			-- get action info to display instant actions for current target (note that non-instant actions are handled in onShowInteractMenu)
			local _, _, _, instantAction = GetActionInfo(newsofttargetmessageid)
			if instantAction then
				private.softtargetMessageID = newsofttargetmessageid
			else
				private.targetText = ""
				updateText()
			end

			-- valid id, so activate the target arrow
			activateTargetArrow()
		end
	else
		deactivateTargetArrow()
		private.targetText = ""
		private.softtargetMessageID = nil
		updateText()
	end

	private.softtargetPosID = posID
end

function onTeleportSucceeded()
	-- reset the relevant (ship-dependent) states

	-- first, reset the entire crosshair
	deactivateCrosshair()
	if HasFlightControl() and (not C.IsExternalTargetMode()) then
		activateCrosshair()
	end

	-- reinitialize the weapon panel (must be done after potential crosshair activation)
	initWeaponPanel()

	-- update missile warning (we changed the ship and therefore wouldn't have gotten the event of a new incoming missile, if one is already active)...
	if C.IsMissileIncoming() then
		activateMissileIncoming()
	end
	-- ...same goes for the locking-on-event
	if C.IsMissileLockingOn() then
		activateMissileLock()
	end

	deactivateSeta()
end

function onTurretClick(i)
	C.CycleTurretMissile(i)
end

function onTurretOver(i)
	local turretDetails = C.GetTurret(i)
	local turreticon = private.weaponPanel.turrets.turrets[i].icon
	turreticon.ishighlighted = true
	setTurretColor(turreticon, turretDetails.active, turretDetails.damageState)
end

function onTurretOut(i)
	local turretDetails = C.GetTurret(i)
	local turreticon = private.weaponPanel.turrets.turrets[i].icon
	turreticon.ishighlighted = false
	setTurretColor(turreticon, turretDetails.active, turretDetails.damageState)
end

function onTurretModeClick(i)
	C.CycleTurretMode(i)
end

function onTurretModeOver(i)
	setColorHelper(private.weaponPanel.turrets.turrets[i].mode.materialElement, nil, config.turretModeHighlightColor)
end

function onTurretModeOut(i)
	setColorHelper(private.weaponPanel.turrets.turrets[i].mode.materialElement, nil, config.turretModeColor)
end

function onUnlock()
	-- reset crosshair state (could have changed when player entered/left stations/drones or started a new game)

	-- see XT-3826 for a list of outstanding tasks

	-- we just reset the interaction --- proper handling would not be that easy, since it requires inter-LuaState-handling (state is stored in the target monitor)
	-- #StefanMed - with the change to use target monitor interactions in the dock case now, we might actually want to higher prioritze this one
	onInteractionHidden(nil, private.currentInteraction)

	-- update the priority missiontarget
	local posID = C.GetPriorityMissiontargetPOSID()
	if posID == -1 then
		posID = nil
	end
	onPriorityMissiontargetChanged(nil, posID)

	-- just reset the softtarget state --- practically this is not an issue, since we always get a softtarget-update-event
	-- #StefanLow - handle that by updating the softtarget (in case we ever change the behavior of the unlocking/locking behavior or the initialization order
	-- and hence can no longer rely on the current fact that we always do get an onSofttargetChanged-event after unlocking)
	onSofttargetChanged(nil, nil, nil)

	-- explicitly deactivate the crosshair, so that a following (potential) (re-)activation correctly initializes the crosshair (f.e. #weapon could have changed)
	-- notes:
	--   - this is also necessary, since we might have not retrieved a previous deactivation-call prior to locking the presentation
	--   - must be done prior to initWeaponPanel() to ensure that we are deactivating the correct number of turrets/weapons
	deactivateCrosshair()

	setCentralElementsPosition(C.IsExternalViewActive())

	-- update controling based states
	if HasFlightControl() and (not C.IsExternalTargetMode()) then
		activateCrosshair()
	end

	setCentralElementsPosition(C.IsExternalViewActive())

	-- must be done after crosshairActive was initialized
	initWeaponPanel()

	-- update scan progress
	if C.IsCurrentlyScanning() then
		startScan()
	else
		deactivateProgressbar("inactive")
	end

	-- update text element
	updateText()

	local activity, activitycolor, _ = GetPlayerActivity()
	if activity == "none" then
		activitycolor = nil
	else
		activitycolor = Color[activitycolor]
	end
	setDecoColors(activitycolor)

	-- update missile warning (must be done after crosshairActive was initialized)
	if C.IsMissileIncoming() then
		activateMissileIncoming()
	end
	if C.IsMissileLockingOn() then
		activateMissileLock()
	end
end

function onWeaponGroupChanged()
	-- weapon group setup changed -> we need to reinitialize the weapon panel, since the primary/secondary group setup (could have) changed
	-- #coreUIMed improve this here
	-- 1) we don't need to fully reinitialize the weapon panel, but just have to recheck if and what relevant things changed
	-- 2) we don't have to reinitialize the weapon panel every time the event is triggerred but rather only once after the event was triggered and then only if the weapon panel (aka the crosshair) was reactivated
	initWeaponPanel()
end

------------------------------------
-- Presentation specific function --
------------------------------------
function abortScan()
	deactivateProgressbar("inactive")
	--PlaySound("ui_hud_soft_scan_neg_core")
end

function activateCrosshair()
	if private.crosshairActive then
		return -- crosshair already active, nothing to do
	end

	-- activate all elements which are permanently active, if the crosshair is active
	goToSlide(private.crosshairElement, "active")
	goToSlide(private.playerActualSpeedbarElement, "active")
	goToSlide(private.playerTargetedSpeedbarElement, "active")
	goToSlide(private.playerBoostBarElement, "active")
	private.crosshairActive = true
	-- #StefanMed - review the rescanSlideChanges-behavior --- maybe deprecated? or at least should be cleaned-up
	private.rescanSlideChanges = true
	updateText()
	updateIndicators()
	updateCheckEngineLight()

	-- ensure the player hull/shield bar is initialized correctly
	-- note: this call here is also important for properly handling the case of upgrading a ship while sitting in the pilot chair
	--       aka: (un-)installing a shield generator -> properly activates/deactivates the shieldbar
	initPlayerHullShield()
end

function activateDronePanel()
	if private.dronePanel.active then
		return -- already active, nothing to do
	end

	goToSlide(private.dronePanel.mainElement, "activate")
	private.dronePanel.active = true
end

function activateDroneType(dronePanelEntry)
	-- note: we reset the deactivationDelay upon each call so that a potentially scheduled disappear-animation is reset
	dronePanelEntry.deactivationDelay = nil

	if dronePanelEntry.active then
		return -- already active, nothing to do
	end

	goToSlide(dronePanelEntry.element, "activate")
	enableDroneTypeInteractions(dronePanelEntry)
	dronePanelEntry.active = true
end

function activateInteractElement()
	if private.interactElementShown then
		return -- nothing to do, element already displayed
	end

	goToSlide(private.interactElement, "appear")
	private.interactElementShown = true
end

function activateMissileIncoming()
	if private.missileIncomingActive then
		return -- nothing to do
	end

	if private.crosshairActive then
		goToSlide(private.missileIncomingElement, "active")
	end
	private.missileIncomingActive = true
end

function activateMissileLock()
	if private.missileLockActive then
		return -- nothing to do
	end

	if private.crosshairActive then
		goToSlide(private.missileLockElement, "active")
	end
	private.missileLockActive = true
end

function activateMissionArrow()
	if private.missionArrowActive then
		return -- nothing to do
	end

	if private.crosshairActive and not private.missionArrowHidden then
		goToSlide(private.missionRingElement, "active")
	end
	private.missionArrowActive = true
end

function activateOxygenBar()
	if private.oxygenBarActive then
		return -- nothing to do
	end

	if private.crosshairActive then
		goToSlide(private.oxygenElement, "active")
	end
	private.oxygenBarActive = true
end

function activatePlayerShieldbar()
	if private.playerShieldbarActive then
		return -- nothing to do
	end

	if private.crosshairActive then
		goToSlide(private.playerShieldElement, "active")
	end

	private.playerShieldbarActive = true
end

function activateSeta(mode)
	if private.setaActive and (private.setaMode == mode) then
		return -- nothing to do, if already inactive
	end

	if mode ~= private.setaMode then
		goToSlide(private.setaElement, mode)
	end
	private.setaMode = mode
	setColorHelper(getElement("background.ui_gradient_05", private.setaElement), nil, config.setaColor[mode])
	private.setaActive = true
end

function activateTargetArrow()
	if private.targetArrowActive then
		return -- nothing to do
	end

	if private.crosshairActive and not private.targetArrowHidden then
		goToSlide(private.targetRingElement, "active")
	end
	private.targetArrowActive = true
end

function activateProgressbar()
	private.progressbarActive = true

	if private.crosshairActive then
		goToSlide(private.progressbarElement, "active")
		setColorHelper(getElement("scanring.Material453", private.progressbarRangeElement), nil, config.progressBarColor.ring)
	end
end

function activateWeaponPanel()
	-- note: only called, if crosshair is active (hence no check required)

	if private.numWeaponSlots > 0 then
		goToSlide(private.weaponPanel.primary.panel, "weapon"..private.numWeaponSlots)
		goToSlide(private.weaponPanel.secondary.panel, "weapon"..private.numWeaponSlots)

		-- activate the weapon group indicators
		updateWeaponGroup(private.weaponPanel.primary, C.GetActivePrimaryWeaponGroup(), false)
		updateWeaponGroup(private.weaponPanel.secondary, C.GetActiveSecondaryWeaponGroup(), false)
	end
	if private.numTurretSlots > 0 then
		goToSlide(private.weaponPanel.turrets.panel, "turret"..private.numTurretSlots)
	end

	-- activate the weapons
	for i = 1, private.numPrimaryWeapons do
		goToSlide(private.weaponPanel.primary.weapons[i].element, "active")
		goToSlide(private.weaponPanel.primary.weapons[i].bar.barElement, "active")
		if private.weaponPanel.primary.weapons[i].ammo.usesAmmo then
			goToSlide(private.weaponPanel.primary.weapons[i].ammo.ammoElement, "active")
		end
	end
	for i = 1, private.numSecondaryWeapons do
		goToSlide(private.weaponPanel.secondary.weapons[i].element, "active")
		goToSlide(private.weaponPanel.secondary.weapons[i].bar.barElement, "active")
		if private.weaponPanel.secondary.weapons[i].ammo.usesAmmo then
			goToSlide(private.weaponPanel.secondary.weapons[i].ammo.ammoElement, "active")
		end
	end
	for i = 1, private.numTurrets do
		goToSlide(private.weaponPanel.turrets.turrets[i].element, "active")
		if private.weaponPanel.turrets.turrets[i].ammo.usesAmmo then
			goToSlide(private.weaponPanel.turrets.turrets[i].ammo.ammoElement, "active")
		end
	end
end

function activationScan()
	if private.missionArrowActive and not private.missionArrowHidden then
		goToSlide(private.missionRingElement, "active")
	end
	if private.targetArrowActive and not private.targetArrowHidden then
		goToSlide(private.targetRingElement, "active")
	end
	-- #coreUI - seta handling was simply copied over from XR - should be cleaned up
	if private.hasSeta then
		initSeta(true)
	end
	if private.interactElementShown then
		goToSlide(private.interactElement, "appear")
	end
	if private.missileLockActive then
		goToSlide(private.missileLockElement, "active")
	end
	if private.missileIncomingActive then
		goToSlide(private.missileIncomingElement, "active")
	end
	if private.oxygenBarActive then
		goToSlide(private.oxygenElement, "active")
		private.curOxygenLevel = 100
	end
	if private.playerShieldbarActive then
		goToSlide(private.playerShieldElement, "active")
		private.curPlayerShield = 0
	end
	if private.progressbarActive then
		goToSlide(private.progressbarElement, "active")
		setColorHelper(getElement("scanring.Material453", private.progressbarRangeElement), nil, config.progressBarColor.ring)
	end

	activateWeaponPanel()

	private.rescanSlideChanges = false
end

function colorDroneType(dronePanelEntry, droneTypeDetails)
	local changedPendingToActiveModeColor = false
	local modehighlightcolor = dronePanelEntry.ismodehighlighted and "_highlight" or ""
	local dronehighlightcolor = dronePanelEntry.ishighlighted and "_highlight" or ""

	-- initialize with default color values
	local modeIconColorMode  = "active" .. modehighlightcolor
	local droneIconColorMode = "armed" .. dronehighlightcolor
	local numberColorMode    = "number"

	if droneTypeDetails.total == 0 then
		-- pending removal -> coloring red
		modeIconColorMode  = "destroyed" .. modehighlightcolor
		droneIconColorMode = "destroyed" .. dronehighlightcolor
		numberColorMode    = "destroyed"
	elseif droneTypeDetails.blocked then
		-- blocked interactions (i.e. auto trading) -> orange
		modeIconColorMode  = "blocked" .. modehighlightcolor
		droneIconColorMode = "blocked" .. dronehighlightcolor
		numberColorMode    = "blocked"
	else
		-- normal coloring
		if droneTypeDetails.pending then
			-- mode being activated -> gray
			modeIconColorMode = "pending" .. modehighlightcolor
		-- else -- otherwise use the default color (mode is active -> blue)
		end

		if not droneTypeDetails.armed then
			-- drones are disarming / disarmed -> gray
			droneIconColorMode = "disarmed" .. dronehighlightcolor
		-- else -- otherwise use the armed color -> blue
		end

		-- textcolor is always white (default value)
	end

	local modeColor   = config.dronePanelColor[modeIconColorMode]
	local droneColor  = config.dronePanelColor[droneIconColorMode]
	local numberColor = config.dronePanelColor[numberColorMode]

	-- finally apply the color values
	if modeIconColorMode ~= dronePanelEntry.mode.colorMode then
		setColorHelper(dronePanelEntry.mode.materialElement, nil, modeColor)
		dronePanelEntry.mode.colorMode = modeIconColorMode
		changedPendingToActiveModeColor = not droneTypeDetails.pending
	end
	if droneIconColorMode ~= dronePanelEntry.drone.colorMode then
		setColorHelper(dronePanelEntry.drone.materialElement, nil, droneColor)
		dronePanelEntry.drone.colorMode = droneIconColorMode
	end
	if numberColorMode ~= dronePanelEntry.drone.colorMode then
		setTextColor(dronePanelEntry.number.partialTextElement, numberColor)
		setTextColor(dronePanelEntry.number.totalTextElement, numberColor)
		setColorHelper(dronePanelEntry.number.dashElement, nil, numberColor)
		dronePanelEntry.number.colorMode = numberColorMode
	end

	return changedPendingToActiveModeColor
end

function deactivateCrosshair()
	if not private.crosshairActive then
		return -- already inactive, nothing to do
	end

	goToSlide(private.crosshairElement, "inactive")
	goToSlide(private.interactElement, "inactive")

	-- hide the speedbar elements
	goToSlide(private.playerActualSpeedbarElement, "inactive")
	goToSlide(private.playerTargetedSpeedbarElement, "inactive")
	goToSlide(private.playerBoostBarElement, "inactive")
	if private.targetSpeedbarActive then
		goToSlide(private.targetSpeedbarElement, "inactive")
		private.targetSpeedbarActive = false
	end

	goToSlide(private.playerHullElement, "inactive")
	goToSlide(private.playerHullBarElement, "inactive")
	goToSlide(private.playerHullDamageElement, "inactive")
	private.curPlayerHull = 0
	private.prevPlayerHull = 0
	private.prevPlayerHullTime = nil
	private.lastHullDamageTime = nil

	-- also hide all separate elements
	if private.targetArrowActive and not private.targetArrowHidden then
		goToSlide(private.targetRingElement, "inactive")
	end
	if private.oxygenBarActive then
		goToSlide(private.oxygenElement, "inactive")
	end
	if private.progressbarActive then
		-- #coreUILow - shouldn't this reset the progressbarActive state?
		goToSlide(private.progressbarElement, "inactive")
	end
	if private.hasSeta then
		goToSlide(private.setaElement, "inactive")
		private.setaMode = "inactive"
	end
	if private.missionArrowActive and not private.missionArrowHidden then
		goToSlide(private.missionRingElement, "inactive")
	end
	if private.interactElementShown then
		goToSlide(private.interactElement, "disappear")
	end
	if private.missileLockActive then
		goToSlide(private.missileLockElement, "inactive")
	end
	if private.missileIncomingActive then
		goToSlide(private.missileIncomingElement, "inactive")
	end
	if private.playerShieldbarActive then
		goToSlide(private.playerShieldElement, "inactive")
		goToSlide(private.playerShieldDamageElement, "inactive")
		private.curShieldHull = 0
		private.prevPlayerShield = 0
		private.prevPlayerShieldTime = nil
		private.lastShieldDamageTime = nil
	end

	deactivateWeaponPanel()
	deactivateDroneType(private.dronePanel.type[1])
	deactivateDroneType(private.dronePanel.type[2])
	deactivateDroneType(private.dronePanel.type[3])
	deactivateDronePanel()

	private.crosshairActive = false
	updateText()
	updateIndicators()
	updateCheckEngineLight()
	updateMouseSteeringLine()
end

function deactivateDronePanel()
	if not private.dronePanel.active then
		return -- already inactive, nothing to do
	end

	goToSlide(private.dronePanel.mainElement, "deactivate")
	private.dronePanel.active = false
end

function deactivateDroneType(dronePanelEntry)
	if not dronePanelEntry.active then
		return -- already inactive, nothing to do
	end

	goToSlide(dronePanelEntry.element, "deactivate")
	if dronePanelEntry.number.currentMode ~= "inactive" then
		goToSlide(dronePanelEntry.number.element, "deact_"..dronePanelEntry.number.currentMode)
		dronePanelEntry.number.currentMode = "inactive"
	end
	disableDroneTypeInteractions(dronePanelEntry)
	dronePanelEntry.active = false
end

function deactivateInteractElement()
	if not private.interactElementShown then
		return -- already hidden
	end

	goToSlide(private.interactElement, "disappear")
	private.interactElementShown = false
end

function deactivateMissileIncoming()
	if not private.missileIncomingActive then
		return -- nothing to do
	end

	if private.crosshairActive then
		goToSlide(private.missileIncomingElement, "inactive")
	end
	private.missileIncomingActive = false
end

function deactivateMissileLock()
	if not private.missileLockActive then
		return -- nothing to do
	end

	if private.crosshairActive then
		goToSlide(private.missileLockElement, "inactive")
	end
	private.missileLockActive = false
end

function deactivateMissionArrow()
	if not private.missionArrowActive then
		return -- nothing to do
	end

	if private.crosshairActive and not private.missionArrowHidden then
		goToSlide(private.missionRingElement, "inactive")
	end
	private.missionArrowActive = false
end

function deactivateOxygenBar()
	if not private.oxygenBarActive then
		return -- nothing to do
	end

	if private.crosshairActive then
		goToSlide(private.oxygenElement, "inactive")
	end
	private.oxygenBarActive = false
end

function deactivateProgressbar(type)
	private.progressbarActive = false

	if private.crosshairActive then
		goToSlide(private.progressbarElement, "inactive")
	end
end

function deactivatePlayerShieldbar()
	if not private.playerShieldbarActive then
		return -- nothing to do
	end

	if private.crosshairActive then
		goToSlide(private.playerShieldElement, "inactive")
	end

	private.curPlayerShield = 0
	private.playerShieldbarActive = false
end

function deactivateSeta(force)
	if not private.setaActive and not force then
		return -- nothing to do, if already inactive
	end

	-- if not force, the proper slide is set during the update-cycle (aka distinguishing between blocked and deactivate state)
	if force then
		private.setaMode = "available"
		goToSlide(private.setaElement, "available")
		setColorHelper(getElement("background.ui_gradient_05", private.setaElement), nil, config.setaColor["available"])
	end

	private.setaActive = false
end

function deactivateTargetArrow()
	if not private.targetArrowActive then
		return -- nothing to do
	end

	if private.crosshairActive and not private.targetArrowHidden then
		goToSlide(private.targetRingElement, "inactive")
	end
	private.targetArrowActive = false
end

function deactivateWeaponPanel()
	-- deactivate weapons
	for i = 1, private.numPrimaryWeapons do
		if private.weaponPanel.primary.weapons[i].ammo.usesAmmo then
			goToSlide(private.weaponPanel.primary.weapons[i].ammo.ammoElement, "inactive")
		end
		goToSlide(private.weaponPanel.primary.weapons[i].bar.barElement, "inactive")
		goToSlide(private.weaponPanel.primary.weapons[i].element, "inactive")
	end
	for i = 1, private.numSecondaryWeapons do
		if private.weaponPanel.secondary.weapons[i].ammo.usesAmmo then
			goToSlide(private.weaponPanel.secondary.weapons[i].ammo.ammoElement, "inactive")
		end
		goToSlide(private.weaponPanel.secondary.weapons[i].bar.barElement, "inactive")
		goToSlide(private.weaponPanel.secondary.weapons[i].element, "inactive")
	end
	for i = 1, private.numTurrets do
		if private.weaponPanel.turrets.turrets[i].ammo.usesAmmo then
			goToSlide(private.weaponPanel.turrets.turrets[i].ammo.ammoElement, "inactive")
		end
		goToSlide(private.weaponPanel.turrets.turrets[i].element, "inactive")
	end

	-- deactivate weapon slot elements
	if private.numWeaponSlots > 0 then
		-- no need to change to inactive slide, if we never activated the panel
		goToSlide(private.weaponPanel.primary.panel, "inactive")
		goToSlide(private.weaponPanel.secondary.panel, "inactive")
	end
	if private.numTurretSlots > 0 then
		-- no need to change to inactive slide, if we never activated the panel
		goToSlide(private.weaponPanel.turrets.panel, "inactive")
	end

	-- deactivate the weapon group indicators
	for i = 1, 4 do
		goToSlide(private.weaponPanel.primary.groups[i], "inactive")
	end
	for i = 1, 4 do
		goToSlide(private.weaponPanel.secondary.groups[i], "inactive")
	end
end

function enableDroneTypeInteractions(dronePanelEntry)
	if dronePanelEntry.mouseInteractionsEnabled then
		return -- already enabled, nothing to do
	end

	RegisterMouseInteractions(dronePanelEntry.mode.pickElement)
	RegisterMouseInteractions(dronePanelEntry.drone.pickElement)
	dronePanelEntry.mouseInteractionsEnabled = true
end

function disableDroneTypeInteractions(dronePanelEntry)
	if not dronePanelEntry.mouseInteractionsEnabled then
		return -- already disabled, nothing to do
	end

	UnregisterMouseInteractions(dronePanelEntry.mode.pickElement)
	UnregisterMouseInteractions(dronePanelEntry.drone.pickElement)
	dronePanelEntry.mouseInteractionsEnabled = false
end

function finishScan()
	deactivateProgressbar("inactive")
	--PlaySound("ui_hud_soft_scan_pos_core")	
end

function initDronePanel()
	for i = 1, 3 do
		local dronePanelEntry = private.dronePanel.type[i]
		registerForEvent("onMouseClick", dronePanelEntry.mode.pickElement, function () return onDroneModeClick(i) end)
		registerForEvent("onGroupedMouseOver", dronePanelEntry.mode.pickElement, function () return onDroneModeOver(i) end)
		registerForEvent("onGroupedMouseOut", dronePanelEntry.mode.pickElement, function () return onDroneModeOut(i) end)
		registerForEvent("onMouseClick", dronePanelEntry.drone.pickElement, function () return onDroneClick(i) end)
		registerForEvent("onGroupedMouseOver", dronePanelEntry.drone.pickElement, function () return onDroneOver(i) end)
		registerForEvent("onGroupedMouseOut", dronePanelEntry.drone.pickElement, function () return onDroneOut(i) end)

		-- initialize the drone icon
		SetIcon(dronePanelEntry.drone.iconElement, config.droneIcons[i], nil, nil, nil, false)
	end
end

function initPlayerHullShield()
	local _, shield = GetPlayerShipHullShield()

	-- #coreUILow --- also add activate/deactivate calls for playerHullElement for consistency
	goToSlide(private.playerHullElement, "active")
	goToSlide(private.playerHullBarElement, "active")
	-- initialize to initial value (needs to be updated the next update-cycle since it just got activated)
	private.curPlayerHull = 0
	private.prevPlayerHull = 0
	private.prevPlayerHullTime = nil
	private.lastHullDamageTime = nil

	-- shield == nil indicates no shield installed
	if shield then
		activatePlayerShieldbar()
		-- initialize to initial value (needs to be updated the next update-cycle since it just got activated)
		private.curPlayerShield = 0
		private.prevPlayerShield = 0
		private.prevPlayerShieldTime = nil
		private.lastShieldDamageTime = nil
	else
		deactivatePlayerShieldbar()
	end
end

function initSeta(hasSeta)
	private.hasSeta = hasSeta
	if hasSeta then
		if C.IsSetaActive() then
			activateSeta("active")
		else
			deactivateSeta(true)
		end
	end

	if C.IsReducedSpeedModeActive() then
		activateSeta("active_slow")
	end
end

function initScale(anchorElement)
	-- Note: For the VR version, we explicitly do not want that a change in resolution changes the relative size of UI elements (i.e. they should not become smaller on higher resolutions) but rather leave it completely up to the user to adjust the actual UI
	--       scale via the ui scale config setting.
	local uiScale = math.min(1.6, C.GetUIScale(not C.IsVRMode()))
	local presentationUIScale = C.GetHUDUIScale(not C.IsVRMode())

	-- apply the overall (normalizing) scale factor - compensates for world-space positioning and presentation setup scaling factor
	-- note: We interpret the scaling factor here the way that the overall presentation setup needs to be scaled so to fit into the worldspace correctly.
	--       Hence, because of that logic/definition we also scale the z-axis.
	setAttribute(anchorElement, "scale.x", config.scalingFactor * presentationUIScale)
	setAttribute(anchorElement, "scale.y", config.scalingFactor * presentationUIScale)
	setAttribute(anchorElement, "scale.z", config.scalingFactor * presentationUIScale)

	local _, height = getScreenInfo()
	local screenfactor = 1080 / height * 0.907

	local weaponpanelcorrection = getAttribute(private.weaponPanel.primary.panel, "pivot.x") / presentationUIScale / ((2 - 2 * screenfactor) * presentationUIScale + 2 * screenfactor - 1)
	setAttribute(private.weaponPanel.primary.panel, "pivot.x", weaponpanelcorrection)
	setAttribute(private.weaponPanel.secondary.panel, "pivot.x", weaponpanelcorrection)

	local turretcorrection = getAttribute(private.weaponPanel.turrets.panel, "position.y") / presentationUIScale
	setAttribute(private.weaponPanel.turrets.panel, "position.y", turretcorrection)

	local dronecorrection = getAttribute(private.dronePanel.mainElement, "position.y") / presentationUIScale
	setAttribute(private.dronePanel.mainElement, "position.y", dronecorrection)

	private.textUIScale = uiScale / presentationUIScale

	local countermeasurecorrection = getAttribute(private.countermeasureElement, "position.y") - math.max(0, 6 * (private.textUIScale - 1))
	setAttribute(private.countermeasureElement, "position.y", countermeasurecorrection)

	local textsToScale = {
		{ getElement("crosshair.central_elements.playerspeed", anchorElement), config.defaultFontSize },
		{ getElement("interact.Text", anchorElement), config.defaultFontSize },
		{ private.countermeasureElement, config.defaultFontSize },
	}
	for i = 1, 2 do
		for j = 1, 8 do
			table.insert(textsToScale, { getElement("crosshair.weapon_group" .. i .. ".weapon" .. j .. ".ammo.Text", anchorElement), config.defaultFontSize })
			table.insert(textsToScale, { getElement("crosshair.weapon_group" .. i .. ".weapon" .. j .. ".ammo.Text2", anchorElement), config.weaponAmmoFontSize })
		end
	end
	for i = 1, 8 do
		table.insert(textsToScale, { getElement("crosshair.turrets.turret" .. i .. ".ammo.Text", anchorElement), config.ammoFontSize })
	end
	for i = 1, 3 do
		table.insert(textsToScale, { getElement("crosshair.drones.drone" .. i .. ".number.partial", anchorElement), config.ammoFontSize })
		table.insert(textsToScale, { getElement("crosshair.drones.drone" .. i .. ".number.total", anchorElement), config.ammoFontSize })
	end

	for _, element in ipairs(textsToScale) do
		setAttribute(element[1], "size", math.ceil(element[2] * private.textUIScale))
	end

	updateIndicatorScalePositionAndActivation(GetControllerInfo())
end

function setCentralElementsPosition(external)
	if external then
		setAttribute(private.centralElements, "position.y", config.centralElementsOffset)
	else
		setAttribute(private.centralElements, "position.y", 0)
	end
end

function initWeaponPanel()
	if C.GetPlayerOccupiedShipID() == 0 then
		return
	end

	private.numWeaponSlots      = tonumber(C.GetNumWeaponSlots())
	private.numTurretSlots      = 0
	private.numPrimaryWeapons   = tonumber(C.GetNumPrimaryWeapons())
	private.numSecondaryWeapons = tonumber(C.GetNumSecondaryWeapons())
	private.numTurrets          = 0

	-- no turret display in weapon panel for L and XL sized ships (see P1DEV-389)
	local shipSize = ffi.string(C.GetPlayerShipSize())
	if shipSize ~= "ship_l" and shipSize ~= "ship_xl" then
		private.numTurretSlots = tonumber(C.GetNumTurretSlots())
		private.numTurrets     = tonumber(C.GetNumTurrets())
	end

	-- error checks and sanitize retrieved data
	if private.numWeaponSlots > 8 then
		DebugError("Crosshair error. Too many weapon slots. Retrieved "..tostring(private.numWeaponSlots).." even though only 8 are supported. Only 8 slots will be displayed.")
		private.numWeaponSlots = 8
	end
	if private.numTurretSlots > 8 then
		DebugError("Crosshair error. Too many turret slots. Retrieved "..tostring(private.numTurretSlots).." even though only 8 are supported. Only 8 slots will be displayed.")
		private.numTurretSlots = 8
	end
	if private.numPrimaryWeapons > private.numWeaponSlots then
		DebugError("Crosshair error. Number of retrieved primary weapons ("..tostring(private.numPrimaryWeapons)..") exceeds number of weapon slots ("..tostring(private.numWeaponSlots).."). Only the first "..tostring(private.numWeaponSlots).." weapons will be displayed.")
		private.numPrimaryWeapons = private.numWeaponSlots
	end
	if private.numSecondaryWeapons > private.numWeaponSlots then
		DebugError("Crosshair error. Number of retrieved secondary weapons ("..tostring(private.numSecondaryWeapons)..") exceeds number of weapon slots ("..tostring(private.numWeaponSlots).."). Only the first "..tostring(private.numWeaponSlots).." weapons will be displayed.")
		private.numSecondaryWeapons = private.numWeaponSlots
	end
	if private.numTurrets > private.numTurretSlots then
		DebugError("Crosshair error. Number of retrieved turrets ("..tostring(private.numTurrets)..") exceeds number of turret slots ("..tostring(private.numTurretSlots).."). Only the first "..tostring(private.numTurretSlots).." turrets will be displayed.")
		private.numTurrets = private.numWeaponSlots
	end

	-- #coreUIMed - review this --- shouldn't we better process this in the onUpdate() call and even though it's fixed atm already right now add support for that value to change eventually?
	-- initialize the weapon/turret types
	for i = 1, private.numPrimaryWeapons do
		local weaponDetails = C.GetWeaponDetails2(i, false)
		private.weaponPanel.primary.weapons[i].ammo.usesAmmo = weaponDetails.usesAmmo
	end
	for i = 1, private.numSecondaryWeapons do
		local weaponDetails = C.GetWeaponDetails2(i, true)
		private.weaponPanel.secondary.weapons[i].ammo.usesAmmo = weaponDetails.usesAmmo
	end
	for i = 1, private.numTurrets do
		local turretDetails = C.GetTurret(i)
		private.weaponPanel.turrets.turrets[i].ammo.usesAmmo = turretDetails.usesAmmo
	end

	-- register for mouse click handling (note: just register all elements even those which are not active, so that if we change the behavior at some point to update the active elements things
	-- will simply work)
	for i = 1, 8 do
		registerForEvent("onMouseClick",		private.weaponPanel.turrets.turrets[i].mode.iconElement, function () return onTurretModeClick(i) end)
		registerForEvent("onGroupedMouseOver",	private.weaponPanel.turrets.turrets[i].mode.iconElement, function () return onTurretModeOver(i) end)
		registerForEvent("onGroupedMouseOut",	private.weaponPanel.turrets.turrets[i].mode.iconElement, function () return onTurretModeOut(i) end)
		RegisterMouseInteractions(private.weaponPanel.turrets.turrets[i].mode.iconElement)

		registerForEvent("onMouseClick",		private.weaponPanel.turrets.turrets[i].icon.iconElement, function () return onTurretClick(i) end)
		registerForEvent("onGroupedMouseOver",	private.weaponPanel.turrets.turrets[i].icon.iconElement, function () return onTurretOver(i) end)
		registerForEvent("onGroupedMouseOut",	private.weaponPanel.turrets.turrets[i].icon.iconElement, function () return onTurretOut(i) end)
		RegisterMouseInteractions(private.weaponPanel.turrets.turrets[i].icon.iconElement)
	end

	if not private.crosshairActive then
		return -- nothing to do, just stay in the inactive slides
	end

	-- activate the panels where we have at least 1 slot (otherwise stay at the inactive slide)
	activateWeaponPanel()
end

function setBarState(barEntry, mode, isActive, reloadPercent, heatState, heatPercent, nextShotHeatPercent, isAutoReloading)
	-- convert to active state
	local activeState = "inactive"
	if isActive then
		activeState = "active"
	end

	-- bar animation notes
	-- time 0 -> bar at 100%
	-- time 1 -> bar at   0%

	-- set the time and color values based on the weapon mode
	local time, time2 = 1, 1
	local color, color2
	if mode == 0 then
		-- reload bar

		-- reloadPercent 0% -> bar at 0% (aka: time = 1)
		-- reloadPercent 100% -> bar at 100% (aka: time = 0)
		time = 1 - (reloadPercent / 100)

		-- reloading -> red bar
		-- ready to fire -> grey elements (bar)
		-- inactive weapon -> transparent bar
		local reloadState = "ready"
		if isActive and (reloadPercent > 0) then
			reloadState = isAutoReloading and "autoreloading" or "reloading"
		end
		color = config.reloadBarColor[reloadState][activeState]
	else
		-- mode == 1 -> overheat bar

		-- heatPercent 0% -> bar at 0% (aka: time = 1)
		-- heatPercent 100% -> bar at 100% (aka: time = 0)
		time = 1 - (heatPercent / 100)

		-- 0% heat -> grey bar
		-- >0% heat but heatState 0 -> blue bar
		-- >0% heat and heatState 1 -> yellow bar (overheating)
		-- >0% heat and heatState 2 -> red bar (overheated -> cooling down)
		-- 0% heat and heatState ~= 0 is considered invalid/unsuspported (just ignore the invalid state)
		local heatMode = "empty"
		if isActive and (heatPercent > 0) then
			if heatState == 0 then
				heatMode = "normal"
			elseif heatState == 1 then
				heatMode = "overheating"
			else -- heatState == 2
				heatMode = "cooling"
			end
		end
		color = config.overheatBarColor[heatMode][activeState]

		time2 = math.max(0, 1 - ((heatPercent + nextShotHeatPercent) / 100))
		local nextShotHeatMode = "empty"
		if isActive then
			if heatMode == "cooling" then
				nextShotHeatMode = "cooling"
			elseif heatPercent + nextShotHeatPercent >= 100 then
				nextShotHeatMode = "cooling"
			elseif heatPercent + nextShotHeatPercent >= 75 then
				nextShotHeatMode = "overheating"
			else
				nextShotHeatMode = "normal"
			end
		end
		color2 = config.overheatBarColor[nextShotHeatMode]["nextshot_" .. activeState]
	end

	-- set the bar accordingly
	if barEntry.color ~= color then
		setColorHelper(barEntry.materialElement1, nil, color)
		setColorHelper(barEntry.materialElement2, nil, color)
		setColorHelper(barEntry.materialElement3, nil, color)
		--barEntry.color = color
	end
	if barEntry.color2 ~= color2 then
		setColorHelper(barEntry.materialElement4, nil, color2)
		--barEntry.color2 = color2
	end
	if not config.enableTimeMemoizing or barEntry.time ~= time then
		goToTime(barEntry.fillElement, time)
		barEntry.time = time
	end
	if not config.enableTimeMemoizing or barEntry.time2 ~= time2 then
		goToTime(barEntry.fill2Element, time2)
		barEntry.time2 = time2
	end
end

function setColorHelper(element, parent, color)
	SetDiffuseColor(parent or element, color.r, color.g, color.b)
	setAttribute(parent or element, "opacity", color.a)
	setAttribute(element, "glowfactor", color.glow)
end

function setTextColor(textelement, color)
	setAttribute(textelement, "textcolor.r", color.r)
	setAttribute(textelement, "textcolor.g", color.g)
	setAttribute(textelement, "textcolor.b", color.b)
	setAttribute(textelement, "glowfactor", color.glow)
end

function setTurretColor(turretIconEntry, isActive, damageState)
	local activeEntry = "inactive"
	if isActive then
		activeEntry = "active"
	end

	if turretIconEntry.ishighlighted then
		activeEntry = activeEntry .. "_highlight"
	end

	local color = config.weaponColor[damageState][activeEntry]
	if turretIconEntry.color ~= color then
		setColorHelper(turretIconEntry.materialElement, turretIconEntry.iconElement, color)
		turretIconEntry.color = color
	end
end

function setTurretMode(turretModeEntry, mode)
	if turretModeEntry.curMode ~= mode then
		SetIcon(turretModeEntry.textureElement, mode, nil, nil, nil, false)
		turretModeEntry.curMode = mode
	end
end

function setWeaponColor(weaponIconEntry, isActive, damageState, isdisabledbystance)
	local activeEntry = "inactive"
	if isActive then
		activeEntry = "active"
	end

	if isdisabledbystance then
		activeEntry = activeEntry .. "_disabled"
	end

	local color = config.weaponColor[damageState][activeEntry]

	if private.shootErrorTime then
		local curtime = getElapsedTime()
		if private.shootErrorTime + config.stanceErrorAnimationDuration < curtime then
			private.shootErrorTime = nil
		else
			local normalcolor = color
			local errorcolor = config.weaponColor["error"]

			local t = (curtime - private.shootErrorTime) / config.stanceErrorAnimationDuration
			color = {
				r = t * normalcolor.r + (1 - t) * errorcolor.r,
				g = t * normalcolor.g + (1 - t) * errorcolor.g,
				b = t * normalcolor.b + (1 - t) * errorcolor.b,
				a = t * normalcolor.a + (1 - t) * errorcolor.a,
				glow = t * normalcolor.glow + (1 - t) * errorcolor.glow,
			}
		end
	end

	if weaponIconEntry.color ~= color then
		setColorHelper(weaponIconEntry.materialElement, weaponIconEntry.iconElement, color)
		weaponIconEntry.color = color
	end
end

function startScan()
	activateProgressbar()
end

function updateActivityColor()
	if private.activityColor then
		local intensity = C.GetModeLightIntensity()

		if intensity ~= private.modeLightIntensity then
			private.modeLightIntensity = intensity
			setDecoColorsWithIntensity(intensity)
		end
	end
end

function updateBoostBar()
	local curtime = getElapsedTime()
	local boostEnergy = C.GetBoostEnergyPercentage()

	-- color
	local updatecolor = private.updateBoostColor
	local isboostbarfull = boostEnergy > 99.99
	if isboostbarfull ~= private.boostBarFull then
		private.boostBarFull = isboostbarfull
		if private.boostBarFull then
			private.boostBarFilledTime = curtime
		else
			private.boostBarFilledTime = nil
		end
		updatecolor = true
	end

	if updatecolor or private.boostBarFilledTime or private.boostErrorTime then
		local color = config.boostBarColor["normal"]
		if (private.checkEngineMode == "noboost") or (private.checkEngineMode == "noboost_stance") then
			color = config.boostBarColor["inactive"]
		elseif private.boostBarFull then
			color = config.boostBarColor["full"]
		end

		if private.boostErrorTime then
			if private.boostErrorTime + config.stanceErrorAnimationDuration < curtime then
				private.boostErrorTime = nil
				private.updateCheckEngineLight = true
			else
				local normalcolor = color
				local errorcolor = config.boostBarColor["error"]

				local t = (curtime - private.boostErrorTime) / config.stanceErrorAnimationDuration
				color = {
					r = t * normalcolor.r + (1 - t) * errorcolor.r,
					g = t * normalcolor.g + (1 - t) * errorcolor.g,
					b = t * normalcolor.b + (1 - t) * errorcolor.b,
					a = t * normalcolor.a + (1 - t) * errorcolor.a,
					glow = t * normalcolor.glow + (1 - t) * errorcolor.glow,
				}
			end
		elseif private.boostBarFilledTime then
			if private.boostBarFilledTime + config.boostBarFilledAnimationDuration < curtime then
				private.boostBarFilledTime = nil
			else
				local normalcolor = config.boostBarColor["normal"]
				local fullcolor = config.boostBarColor["full"]

				local t = (curtime - private.boostBarFilledTime) / config.boostBarFilledAnimationDuration
				color = {
					r = t * fullcolor.r + (1 - t) * normalcolor.r,
					g = t * fullcolor.g + (1 - t) * normalcolor.g,
					b = t * fullcolor.b + (1 - t) * normalcolor.b,
					a = t * fullcolor.a + (1 - t) * normalcolor.a,
					glow = t * fullcolor.glow + (1 - t) * normalcolor.glow,
				}
			end
		end

		setColorHelper(private.playerBoostBarMaterialElement, nil, color)

		private.updateBoostColor = nil
	end

	-- value
	local boostBarTime = (1 - boostEnergy / 100) * 4
	if not config.enableTimeMemoizing or private.prevBoostBarTime ~= boostBarTime then
		goToTime(private.playerBoostBarElement, boostBarTime)
		private.prevBoostBarTime = boostBarTime
	end
end

function updateCountermeasures()
	-- #coreUIMed - it would be better to disable the entire text elmenet, when the countermeasure-display is inactive (instead of just clearing the text)
	local numCountermeasures = -1
	-- #coreUIMed - it'd be better to work with events here, so to not recheck the state every frame (especially if we are not in a spacesuit)
	if C.CanHaveCountermeasures() then
		numCountermeasures = C.GetNumCountermeasures()
	end

	if private.numCountermeasures ~= numCountermeasures then
		local text = ""
		if numCountermeasures ~= -1 then
			text = L["FLR"].." "..numCountermeasures
		end
		setAttribute(private.countermeasureElement, "textstring", text)
		private.numCountermeasures = numCountermeasures
	end
end

function updateDronePanel(force)
	local miningDrones  = C.GetDroneDetails(1)
	local defenceDrones = C.GetDroneDetails(2)
	local tradeDrones   = C.GetDroneDetails(3)

	updateDroneType(private.dronePanel.type[1], miningDrones, force)
	updateDroneType(private.dronePanel.type[2], defenceDrones, force)
	updateDroneType(private.dronePanel.type[3], tradeDrones, force)

	if private.dronePanel.type[1].active or private.dronePanel.type[2].active or private.dronePanel.type[3].active then
		activateDronePanel()
	else
		deactivateDronePanel()
	end
end

function updateDroneType(dronePanelEntry, droneTypeDetails, force)
	if droneTypeDetails.total == 0 then
		-- we don't have any drones of the specified type, make sure to trigger the deactivation handling, if it didn't start yet
		if dronePanelEntry.active then
			if (not force) and (dronePanelEntry.deactivationDelay == nil) then
				dronePanelEntry.deactivationDelay = C.GetCurrentGameTime() + config.dronePanelDisappearDelay
			elseif force or (dronePanelEntry.deactivationDelay >= C.GetCurrentGameTime()) then
				deactivateDroneType(dronePanelEntry)
				return -- we are done (i.e. don't update the drone type states when we are deactivating the current type column)
			end
		else
			return -- already inactive (or deactivation animation in progress) -> nothing to do
		end
	else
		activateDroneType(dronePanelEntry)
	end

	-- update the current mode icon
	local droneModeIcon = ffi.string(droneTypeDetails.modeIcon)
	local modeIconChanged = false
	if droneModeIcon ~= dronePanelEntry.mode.currentIcon then
		dronePanelEntry.mode.currentIcon = droneModeIcon
		SetIcon(dronePanelEntry.mode.iconElement, droneModeIcon, nil, nil, nil, false)
		modeIconChanged = true
	end

	-- update number display
	if droneTypeDetails.armed or droneTypeDetails.undocked > 0 then
		-- if drones are armed (or in progress of disarming), we display the double number mode
		if dronePanelEntry.number.currentMode ~= "double" then
			goToSlide(dronePanelEntry.number.element, "double")
			dronePanelEntry.number.currentMode = "double"
		end
		setAttribute(dronePanelEntry.number.partialTextElement, "textstring", droneTypeDetails.undocked)
	else
		-- otherwise we display the single number mode
		if dronePanelEntry.number.currentMode ~= "single" then
			goToSlide(dronePanelEntry.number.element, "single")
			dronePanelEntry.number.currentMode = "single"
		end
	end
	setAttribute(dronePanelEntry.number.totalTextElement, "textstring", droneTypeDetails.total)

	-- color the drone type
	-- #coreUILow - a bit hackish to determine whether to play the sound or not through the colorDroneType's return value...
	if colorDroneType(dronePanelEntry, droneTypeDetails) and not modeIconChanged then
		-- play the mode activation sound only if the mode changed the state from pending -> active and not if we cycled the mode to the current active one
		PlaySound("ui_drone_event")
	end
end

function updateHullShield()
	-- player hull is always active (if the crosshair is active) - hence update the state always
	local playerhull, playershield, timesincelastattack, shieldchargingsound, shieldchargedsound = GetPlayerShipHullShield()
	local curtime = getElapsedTime()

	if not config.enableTimeMemoizing or playerhull ~= private.curPlayerHull then
		if playerhull < private.curPlayerHull then
			if not private.prevPlayerHullTime then
				-- init damagebar with old hull value
				private.prevPlayerHull = private.curPlayerHull
				private.prevPlayerHullTime = curtime
				goToSlide(private.playerHullDamageElement, "active")
			else
				-- reset timer and update damage bar value to its current value
				local delta_t = math.max(0, (curtime - private.prevPlayerHullTime - config.damageBarAnimationDelay) / config.damageBarAnimationDuration)
				private.prevPlayerHull = private.curPlayerHull + (private.prevPlayerHull - private.curPlayerHull) * (1 - delta_t)
				private.prevPlayerHullTime = curtime
			end
			private.lastHullDamageTime = curtime
		end
		if private.prevPlayerHullTime and (playerhull >= private.prevPlayerHull) then
			-- hull has been repaired, reset damage bar
			private.prevPlayerHullTime = nil
			goToSlide(private.playerHullDamageElement, "inactive")
			private.lastHullDamageTime = nil
			setColorHelper(private.playerHullBarElementMaterial, nil, config.hullBarColor)
		end
		
		-- set actual hull value
		goToTime(private.playerHullBarElement, playerhull / 100)
		private.curPlayerHull = playerhull
	end

	if private.prevPlayerHullTime then
		local delta_t = math.max(0, (curtime - private.prevPlayerHullTime - config.damageBarAnimationDelay) / config.damageBarAnimationDuration)
		if delta_t > 1 then
			private.prevPlayerHullTime = nil
			goToSlide(private.playerHullDamageElement, "inactive")
		else
			local prevhull = private.curPlayerHull + (private.prevPlayerHull - private.curPlayerHull) * (1 - delta_t)
			goToTime(private.playerHullDamageElement, prevhull / 100)
		end
	end

	if private.lastHullDamageTime then
		local color = config.hullBarColor
		if private.lastHullDamageTime + config.damageAnimationDuration < curtime then
			private.lastHullDamageTime = nil
		else
			-- animate independent from lastHullDamageTime, so that the animation does not jump when lastHullDamageTime updates
			local t = (math.sin(curtime * config.damageAnimationSpeedFactor) + 1) / 2
			color = {
				r = t * config.hullBarDamageAnimationColor.r + (1 - t) * config.hullBarColor.r,
				g = t * config.hullBarDamageAnimationColor.g + (1 - t) * config.hullBarColor.g,
				b = t * config.hullBarDamageAnimationColor.b + (1 - t) * config.hullBarColor.b,
				a = t * config.hullBarDamageAnimationColor.a + (1 - t) * config.hullBarColor.a,
				glow = t * config.hullBarDamageAnimationColor.glow + (1 - t) * config.hullBarColor.glow,
			}
		end
		setColorHelper(private.playerHullBarElementMaterial, nil, color)
	end

	if config.jiggleEnabled then
		local jiggle_x, jiggle_y = 0, 0
		if (not C.IsGamePaused()) and (playershield == 0) and timesincelastattack and (timesincelastattack < config.jiggleDuration) then 
			local tau = 10 * timesincelastattack + 1
			jiggle_x = 0
			jiggle_y = 1.25 * math.sin(12 * tau) * config.maxJiggle / tau
		end
		setAttribute(private.playerHullBarElement, "position.x", jiggle_x)
		setAttribute(private.playerHullBarElement, "position.y", jiggle_y)
		setAttribute(private.playerHullDamageElement, "position.x", jiggle_x)
		setAttribute(private.playerHullDamageElement, "position.y", jiggle_y)
		setAttribute(private.playerHullBackgroundElement, "position.x", jiggle_x)
		setAttribute(private.playerHullBackgroundElement, "position.y", jiggle_y)
	end

	if private.playerShieldbarActive then
		local _, _, _, boosting, _, _, _, _ = GetPlayerSpeed()
		if boosting then
			private.lastBoostTime = curtime
		end

		if not config.enableTimeMemoizing or playershield ~= private.curPlayerShield then
			if playershield < private.curPlayerShield then
				if not private.prevPlayerShieldTime then
					-- init damagebar with old shield value
					private.prevPlayerShield = private.curPlayerShield
					private.prevPlayerShieldTime = curtime
					goToSlide(private.playerShieldDamageElement, "active")
				else
					-- reset timer and update damage bar value to its current value
					local delta_t = math.max(0, (curtime - private.prevPlayerShieldTime - config.damageBarAnimationDelay) / config.damageBarAnimationDuration)
					private.prevPlayerShield = private.curPlayerShield + (private.prevPlayerShield - private.curPlayerShield) * (1 - delta_t)
					private.prevPlayerShieldTime = curtime
				end
				private.lastShieldDamageTime = curtime
			end
			if private.prevPlayerShieldTime and (playershield >= private.prevPlayerShield) then
				-- shield has been regenerated, reset damage bar
				private.prevPlayerShieldTime = nil
				goToSlide(private.playerShieldDamageElement, "inactive")
				private.lastShieldDamageTime = nil
				setColorHelper(private.playerShieldBarElementMaterial, nil, config.shieldBarColor)
			end

			if private.curPlayerShield > 0 then
				if (private.curPlayerShield < 100) and (playershield == 100) then
					if shieldchargedsound ~= "" then
						PlaySound(shieldchargedsound)
					end
				elseif private.shieldIsDraining and (playershield > private.curPlayerShield) then
					private.shieldIsDraining = nil
					if shieldchargingsound ~= "" then
						PlaySound(shieldchargingsound)
					end
				elseif playershield < private.curPlayerShield then
					private.shieldIsDraining = true
				end
			end
		
			-- set actual shield value
			goToTime(private.playerShieldElement, playershield / 100)
			private.curPlayerShield = playershield
		end

		if private.prevPlayerShieldTime then
			local delta_t = math.max(0, (curtime - private.prevPlayerShieldTime - config.damageBarAnimationDelay) / config.damageBarAnimationDuration)
			if delta_t > 1 then
				private.prevPlayerShieldTime = nil
				goToSlide(private.playerShieldDamageElement, "inactive")
			else
				local prevshield = private.curPlayerShield + (private.prevPlayerShield - private.curPlayerShield) * (1 - delta_t)
				goToTime(private.playerShieldDamageElement, prevshield / 100)
			end
		end

		local attackcolor = false
		if timesincelastattack then
			if (timesincelastattack < config.jiggleDuration) or (private.lastBoostTime == nil) or (timesincelastattack < (curtime - private.lastBoostTime)) then
				attackcolor = true
			end
		end
		setColorHelper(private.playerShieldDamageElementMaterial, nil, attackcolor and config.shieldBarDamageColor or config.shieldBarBoostColor)

		if private.lastShieldDamageTime then
			local color = config.shieldBarColor
			if private.lastShieldDamageTime + config.damageAnimationDuration < curtime then
				private.lastShieldDamageTime = nil
			elseif attackcolor then
				-- animate independent from lastHullDamageTime, so that the animation does not jump when lastHullDamageTime updates
				local t = (math.sin(curtime * config.damageAnimationSpeedFactor) + 1) / 2
				color = {
					r = t * config.shieldBarDamageAnimationColor.r + (1 - t) * config.shieldBarColor.r,
					g = t * config.shieldBarDamageAnimationColor.g + (1 - t) * config.shieldBarColor.g,
					b = t * config.shieldBarDamageAnimationColor.b + (1 - t) * config.shieldBarColor.b,
					a = t * config.shieldBarDamageAnimationColor.a + (1 - t) * config.shieldBarColor.a,
					glow = t * config.shieldBarDamageAnimationColor.glow + (1 - t) * config.shieldBarColor.glow,
				}
			end
			setColorHelper(private.playerShieldBarElementMaterial, nil, color)
		end

		if config.jiggleEnabled then
			local jiggle_x, jiggle_y = 0, 0
			if (not C.IsGamePaused()) and (playershield > 0) and timesincelastattack and (timesincelastattack < config.jiggleDuration) then 
				local tau = 10 * timesincelastattack + 1
				jiggle_x = 0
				jiggle_y = 1.25 * math.sin(12 * tau) * config.maxJiggle / tau
			end
			setAttribute(private.playerShieldElement, "position.x", jiggle_x)
			setAttribute(private.playerShieldElement, "position.y", jiggle_y)
		end
	end
end

function updateMouseSteeringLine()
	local shouldshow = false
	if private.crosshairActive then
		shouldshow = C.ShouldShowMouseSteeringHelperLine()
	end
	if shouldshow ~= private.mouseSteeringActive then
		if shouldshow then
			goToSlide(private.mouseSteeringElement, "active")
			private.mouseSteeringActive = true
		else
			private.mouseSteeringActive = false
			goToSlide(private.mouseSteeringElement, "inactive")
		end
	end

	if private.mouseSteeringActive then
		local threshold = 30

		local posX, posY = GetLocalMousePosition()
		if posX ~= nil then
			-- due to 0.1 scale factor on crosshair component
			posX = posX * 10
			posY = posY * 10

			local distance = math.sqrt(posX * posX + posY * posY)
			local angle = math.atan2(posX, -posY)

			if distance > threshold then
				setAttribute(private.mouseSteeringElement, "position.x", (posX + threshold * math.sin(angle)) / 2)
				setAttribute(private.mouseSteeringElement, "position.y", (posY - threshold * math.cos(angle)) / 2)

				setAttribute(private.mouseSteeringElement, "scale.x", (distance - threshold) / 15)
				setAttribute(private.mouseSteeringElement, "scale.y", config.mouseSteeringLineWidth / 15)

				setAttribute(private.mouseSteeringElement, "rotation.z", angle + math.pi / 2)
			else
				setAttribute(private.mouseSteeringElement, "scale.x", 0)
				setAttribute(private.mouseSteeringElement, "scale.y", 0)
			end
		end
	end
end

function updateIndicatorScalePositionAndActivation(mode)
	-- determine current inputmode
	local inputmode
	if (mode == "mouseSteering") or (mode == "mouseCursor") then
		inputmode = "mouse"
	else
		inputmode = "other"
	end

	-- set and count active indicators
	local indicatorCount = 0
	for _, entry in pairs(private.indicatorElements) do
		if (entry.inputmode == nil) or (entry.inputmode == inputmode) then
			entry.active = true
			indicatorCount = indicatorCount + 1
		else
			entry.active = false
		end
	end

	-- scale and position indicators correctly
	local indicatorSize = math.floor(config.indicatorIconSize * private.textUIScale + 0.5)
	local startx = config.indicatorOffsetX - (indicatorCount / 2 - 0.5) * indicatorSize
	for _, entry in pairs(private.indicatorElements) do
		if entry.active then
			local x = startx + entry.position * indicatorSize
			setAttribute(entry.element, "position.x", x)
			setAttribute(entry.element, "position.y", config.indicatorOffsetY - math.max(0, 15 * (private.textUIScale - 1)))
			setAttribute(entry.element, "scale.x", indicatorSize / config.indicatorIconSize)
			setAttribute(entry.element, "scale.y", indicatorSize / config.indicatorIconSize)
		end
	end
end

function updateIndicators()
	for _, entry in pairs(private.indicatorElements) do
		local mode = "off"
		if private.crosshairActive and entry.active then
			local state = entry.getState()
			if entry.type == "bool" then
				mode = state and "active" or "deactivated"
			elseif entry.type == "int" then
				if state == 0 then
					mode = "deactivated"
				elseif state == 1 then
					mode = "activated"
				elseif state == 2 then
					mode = "active"
				end
			end
		end

		if mode ~= entry.mode then
			entry.mode = mode
			if mode == "off" then
				goToSlide(entry.element, "inactive")
			else
				goToSlide(entry.element, "active")
				setColorHelper(entry.materialElement, entry.element, config.indicatorColor[mode])
			end
		end
	end
end

function updateMatchSpeedElement(matchSpeed, targetSpeed, normalTargetSpeed)
	if not matchSpeed then
		if private.targetSpeedbarActive then
			goToSlide(private.targetSpeedbarElement, "inactive")
			private.targetSpeedbarActive = false
		end
		return -- done, no update required if element is inactive completely
	end

	if not private.targetSpeedbarActive then
		goToSlide(private.targetSpeedbarElement, "active")
		private.targetSpeedbarActive = true
	end

	-- map the speed [-1, 3] onto the corresponding time range [0, 4]
	local targetSpeedTime = targetSpeed + 1

	-- set the target speed
	if not config.enableTimeMemoizing or private.prevTargetSpeedTime ~= targetSpeedTime then
		goToTime(private.targetSpeedbarArrowElement, targetSpeedTime)
		-- we compare the set time rather than the given speed, so that we only issue goToTime()-update calls when the visuals would actually differ
		-- aka: some very small speed changes like -1 -> -0.9991 which wouldn't result in a different speedbar position are ignored
		private.prevTargetSpeedTime = targetSpeedTime
	end

	-- switch color elements based on target's boosting/travelMode state
	local boostState = not normalTargetSpeed
	if private.prevTargetBoostState ~= boostState then
		local color = config.speedBarColor.normal
		if boostState then
			color = config.speedBarColor.boost
		end

		-- set the arrow and text color
		setColorHelper(private.targetSpeedbarArrowMaterialElement, private.targetSpeedbarArrowElement, color)

		private.prevTargetBoostState = boostState
	end
end

function updateMissionArrow()
	if not private.missionArrowActive then
		return -- nothing to do
	end

	if private.missionPosID then
		local arrowDetails = C.GetCrosshairArrowDetails(private.missionPosID, config.missionArrowRadius)
		if arrowDetails.valid then
			private.previousMissiontargetAngle = arrowDetails.angle
			updateArrowState(private.missionRingElement, private.missionArrowHidden, arrowDetails.inside)
			private.missionArrowHidden = arrowDetails.inside
		end
	else
		-- get details for all tracked mission posids
		-- check if all angles are within config.normalMissionGroupingAngle
		-- maybe a distance check? But the angle takes care of that basicially
		-- if so -> set angle, make arrow visible

		local minangle, maxangle, minphaseshiftedangle, maxphaseshiftedangle
		local hidden, average, phaseshiftedaverage, count = false, 0, 0, 0
		for posID in pairs(private.normalMissionPosIDs) do
			local arrowDetails = C.GetCrosshairArrowDetails(posID, config.missionArrowRadius)
			if arrowDetails.valid then
				count = count + 1
				local angle = arrowDetails.angle
				local phaseshiftedangle = (angle + 180) % 360
				average = average + angle
				phaseshiftedaverage = phaseshiftedaverage + phaseshiftedangle

				minangle = minangle and math.min(minangle, angle) or angle
				maxangle = maxangle and math.max(maxangle, angle) or angle
				minphaseshiftedangle = minphaseshiftedangle and math.min(minphaseshiftedangle, phaseshiftedangle) or phaseshiftedangle
				maxphaseshiftedangle = maxphaseshiftedangle and math.max(maxphaseshiftedangle, phaseshiftedangle) or phaseshiftedangle
				hidden = hidden or arrowDetails.inside
			else
				private.normalMissionPosIDs[posID] = nil
			end
		end
		if count > 0 then
			average = average / count
			phaseshiftedaverage = phaseshiftedaverage / count
		end

		if maxangle then
			if maxangle - minangle > 180 then
				-- we may have crossed the 0°/360° discontinuity -> check phase shifted angles, too
				if maxphaseshiftedangle - minphaseshiftedangle > config.normalMissionGroupingAngle then
					hidden = true
				else
					average = (phaseshiftedaverage - 180) % 360
				end
			elseif maxangle - minangle > config.normalMissionGroupingAngle then
				hidden = true
			end
		else
			hidden = true
		end

		private.previousMissiontargetAngle = average
		updateArrowState(private.missionRingElement, private.missionArrowHidden, hidden)
		private.missionArrowHidden = hidden
	end

	if not private.missionArrowHidden then
		setAttribute(private.missionArrowElement, "rotation.z", (-private.previousMissiontargetAngle)/180 * math.pi)
	end
end

function updateOxygenBar()
	-- #coreUIMed - it'd be better to work with events here, so to not recheck the state every frame (especially if we are not in a spacesuit)
	local panelActive = C.HasLimitedOxygenSupply()
	-- activate the bar, based on whether the player is in a spacesuit or not
	if panelActive ~= private.oxygenBarActive then
		if panelActive then
			activateOxygenBar()
		else
			deactivateOxygenBar()
		end
	end

	if not private.oxygenBarActive then
		return -- nothing else to do, if the oxygen bar is inactive
	end

	local oxygenPercent = C.GetRemainingOxygen()
	if private.curOxygenLevel == oxygenPercent then
		return -- nothing to do
	end

	-- bar is animated inverted (0 = 100%, 1 = 0%)
	local timeValue = (100 - oxygenPercent)/100
	goToTime(private.oxygenElement, timeValue)
	private.curOxygenLevel = oxygenPercent

	-- color bar and icon red, if GetRemainingOxygenPercent() is below the threashold (see Low warning)
	-- #coreUIMed - improve the handling - no need to reset the color every frame (just do so, if the color actually changes)
	local state = "normal"
	if C.IsLowOnOxygen() then
		state = "low"
	end
	SetDiffuseColor(private.oxygenElement, config.oxygenBarColor[state].r, config.oxygenBarColor[state].g, config.oxygenBarColor[state].b)
end

function updateProgressbar()
	local percent = C.GetScanProgress()
	goToTime(private.progressbarRangeElement, percent)
end

function updateArrowState(arrowElement, wasHidden, isHidden)
	if isHidden and not wasHidden then
		goToSlide(arrowElement, "inactive")
	elseif not isHidden and wasHidden then
		goToSlide(arrowElement, "active")
	end
end

function updateSeta()
	if ((not private.hasSeta) and (private.setaMode ~= "active_slow") and (private.setaMode ~= "active")) or private.setaActive then
		-- no need to update anything if SETA is running atm or we don't have SETA at all
		return
	end

	local mode = private.hasSeta and "available" or "inactive"
	if private.hasSeta and (not C.CanActivateSeta(true)) then
		mode = "unavailable"
	end

	if private.setaMode ~= mode then
		goToSlide(private.setaElement, mode)
		setColorHelper(getElement("background.ui_gradient_05", private.setaElement), nil, config.setaColor[mode])
		private.setaMode = mode
	end
end

function updateCheckEngineLight()
	local mode = "normal"
	if private.crosshairActive then
		local ship = C.GetPlayerOccupiedShipID()
		if ship ~= 0 then
			mode = ffi.string(C.GetObjectEngineStatus(ship))
		end
	end
	if private.updateCheckEngineLight or (mode ~= private.checkEngineMode) then
		private.checkEngineMode = mode
		private.updateBoostColor = true

		if (mode ~= "normal") and ((mode ~= "noboost_stance") or private.boostErrorTime) then
			goToSlide(private.checkEngineElement, "active")
			-- color
			local color = config.checkEngineColor[mode]
			SetDiffuseColor(private.checkEngineElement, color.r, color.g, color.b)
			setAttribute(private.checkEngineElement, "opacity", color.a)
			setAttribute(getElement("checkengine_poly.checkengine_mat", private.checkEngineElement), "glowfactor", color.glow)

			if mode == "disabled" then
				private.checkEngineStartTime = getElapsedTime()
			else
				private.checkEngineStartTime = nil
			end
		else
			private.checkEngineStartTime = nil
			goToSlide(private.checkEngineElement, "inactive")
		end

		private.updateCheckEngineLight = nil
	end

	if private.checkEngineStartTime then
		local factor = ((getElapsedTime() - private.checkEngineStartTime) * config.checkEngineAnimationSpeed) % 2
		local color = (factor > 1) and config.checkEngineColor["disabled"] or config.checkEngineColor["disabled2"]
		SetDiffuseColor(private.checkEngineElement, color.r, color.g, color.b)
		setAttribute(private.checkEngineElement, "opacity", color.a)
		setAttribute(getElement("checkengine_poly.checkengine_mat", private.checkEngineElement), "glowfactor", color.glow)
	elseif private.boostErrorTime then
		local t = (getElapsedTime() - private.boostErrorTime) / config.stanceErrorAnimationDuration
		setAttribute(private.checkEngineElement, "opacity", (1 - t) * 100)
	end
end

function updateSpeedbar()
	-- speed is always returned between -1 and 1 (1 meaning full forward speed, -1 meaning full reverse speed)
	local actualSpeed, targetedSpeed, actualSpeedPerSecond, boosting, travelMode, matchSpeed, targetSpeed, normalTargetSpeed = GetPlayerSpeed()

	-- map the speed [-1, 3] onto the corresponding time range [0, 4]
	local targetedSpeedTime = targetedSpeed + 1
	local actualSpeedTime   = actualSpeed + 1

	-- set the targeted speed
	if not config.enableTimeMemoizing or private.prevTargetedSpeedTime ~= targetedSpeedTime then
		goToTime(private.playerTargetedSpeedbarElement, targetedSpeedTime)
		-- we compare the set time rather than the given speed, so that we only issue goToTime()-update calls when the visuals would actually differ
		-- aka: some very small speed changes like -1 -> -0.9991 which wouldn't result in a different speedbar position are ignored
		private.prevTargetedSpeedTime = targetedSpeedTime
	end

	-- set the actual speed
	if not config.enableTimeMemoizing or private.prevActualSpeedTime ~= actualSpeedTime then
		goToTime(private.playerActualSpeedbarElement, actualSpeedTime)
		private.prevActualSpeedTime = actualSpeedTime
	end

	-- set the actual speed value
	if math.abs(actualSpeedPerSecond) >= 0.01 * config.speedoflight then
		actualSpeedPerSecond = math.floor(actualSpeedPerSecond * 100 / config.speedoflight + 0.5) / 100
		setAttribute(private.playerSpeedValueElement, "textstring", actualSpeedPerSecond .. L["c"])
	elseif math.abs(actualSpeedPerSecond) >= 10000 then
		if math.abs(actualSpeedPerSecond) >= 100000 then
			actualSpeedPerSecond = math.floor(actualSpeedPerSecond / 1000 + 0.5)
		else
			actualSpeedPerSecond = math.floor(actualSpeedPerSecond / 100 + 0.5) / 10
		end
		setAttribute(private.playerSpeedValueElement, "textstring", actualSpeedPerSecond .. " " .. L["km"] .. "/" .. L["s"])
	else
		setAttribute(private.playerSpeedValueElement, "textstring", actualSpeedPerSecond .. " " .. L["m/s"])
	end

	-- switch color elements based on boosting/travelMode state
	local boostState = (boosting or travelMode)
	if private.prevBoostState ~= boostState then
		local color = config.speedBarColor.normal
		if boostState then
			color = config.speedBarColor.boost
		end

		-- set the arrow and text color
		setTextColor(private.playerSpeedValueElement, color)
		setColorHelper(private.playerTargetedSpeedbarArrowMaterialElement, private.playerTargetedSpeedbarArrowElement, color)

		private.prevBoostState = boostState
	end

	updateMatchSpeedElement(matchSpeed, targetSpeed, normalTargetSpeed)

	updateBoostBar()
end

function updateTargetArrow()
	if not private.targetArrowActive then
		return -- nothing to do
	end

	local arrowDetails = C.GetCrosshairArrowDetails(private.softtargetPosID, config.targetArrowRadius)
	if arrowDetails.valid then
		private.previousTargetAngle = arrowDetails.angle
		updateArrowState(private.targetRingElement, private.targetArrowHidden, arrowDetails.inside)
		private.targetArrowHidden = arrowDetails.inside
	end

	if not private.targetArrowHidden then
		setAttribute(private.targetArrowElement, "rotation.z", (-private.previousTargetAngle)/180 * math.pi)
	end
end

function updateTargetText()
	if private.softtargetMessageID == nil then
		return -- nothing to do
	end

	local actionname, isPossible = GetActionInfo(private.softtargetMessageID)
	if not isPossible then
		actionname = ""
	end
	if private.targetText ~= actionname then
		private.targetText = actionname
		updateText()
	end
end

function updateText()
	local text = ""
	if private.crosshairActive then
		-- text is only set, if the crosshair is active
		if private.interactText ~= nil then
			text = private.interactText
		else
			text = private.targetText
		end
	end
	
	if text ~= "" then
		activateInteractElement()
		setAttribute(private.textElement, "textstring", text)
	else
		deactivateInteractElement()
	end
end

function updateWeaponGroup(element, group, playSound)
	if not private.crosshairActive then
		return -- nothing to do for inactive crosshair
	end

	if group > 4 then
		DebugError("Crosshair error. Invalid active weapon group retrieved. Retrieved "..tostring(group).." even though only 1-4 are supported. Defaulting to display group 1.")
		group = 1
	end

	for i = 1, 4 do
		if i == group then
			goToSlide(element.groups[i], "active")
		else
			goToSlide(element.groups[i], "unselected")
		end
	end

	if playSound then
		PlaySound("ui_weapon_group_change_beep")
	end
end

function updateWeaponPanel()
	local isdisabledbystance = false
	local ship = C.GetPlayerOccupiedShipID()
	if ship ~= 0 then
		isdisabledbystance = C.IsObjectShootingDisabledByStanceOnly(ship)
	end
	for i = 1, private.numPrimaryWeapons do
		local weaponDetails = C.GetWeaponDetails2(i, false)
		local weaponEntry = private.weaponPanel.primary.weapons[i]
		if weaponEntry.ammo.usesAmmo ~= weaponDetails.usesAmmo then
			DebugError("Crosshair error. Mismatch between retrieved ("..tostring(weaponDetails.usesAmmo)..") and recorded ("..tostring(weaponEntry.ammo.usesAmmo)..") uses-ammo state for primary weapon "..tostring(i).." - ammo might not be displayed or not updated correctly")
		end
		if weaponDetails.usesAmmo then
			local showclip = false
			if weaponDetails.maxclip > 1 then
				setAttribute(weaponEntry.ammo.text2Element, "textstring", math.min(weaponDetails.currentclip, weaponDetails.ammo))
				showclip = true
			else
				setAttribute(weaponEntry.ammo.text2Element, "textstring", "")
			end
			if showclip then
				setAttribute(weaponEntry.ammo.textElement, "textstring", "/" .. math.max(0, weaponDetails.ammo - weaponDetails.currentclip))
			else
				setAttribute(weaponEntry.ammo.textElement, "textstring", weaponDetails.ammo)
			end
		end
		local weaponIcon = ffi.string(weaponDetails.icon)
		-- #coreUIMed - optimize - we can directly set the proper color, if we also change the current icon
		if weaponIcon ~= weaponEntry.icon.curIcon then
			SetIcon(weaponEntry.icon.textureElement, weaponIcon, nil, nil, nil, false)
			weaponEntry.icon.curIcon = weaponIcon
		end
		setWeaponColor(weaponEntry.icon, weaponDetails.active, weaponDetails.damageState, isdisabledbystance)
		-- #coreUIMed - clean structure up - better have a single element to process for setBarState() rather than passing the complete weapon-element-entry
		setBarState(weaponEntry.bar, weaponDetails.mode, weaponDetails.active, weaponDetails.reloadPercent, weaponDetails.heatState, weaponDetails.heatPercent, weaponDetails.nextShotHeatPercent, weaponDetails.isAutoReloading)
	end

	for i = 1, private.numSecondaryWeapons do
		local weaponDetails = C.GetWeaponDetails2(i, true)
		local weaponEntry = private.weaponPanel.secondary.weapons[i]
		if weaponEntry.ammo.usesAmmo ~= weaponDetails.usesAmmo then
			DebugError("Crosshair error. Mismatch between retrieved ("..tostring(weaponDetails.usesAmmo)..") and recorded ("..tostring(weaponEntry.ammo.usesAmmo)..") uses-ammo state for secondary weapon "..tostring(i).." - ammo might not be displayed or not updated correctly")
		end
		if weaponDetails.usesAmmo then
			local showclip = false
			if weaponDetails.maxclip > 1 then
				setAttribute(weaponEntry.ammo.text2Element, "textstring", math.min(weaponDetails.currentclip, weaponDetails.ammo))
				showclip = true
			else
				setAttribute(weaponEntry.ammo.text2Element, "textstring", "")
			end
			if showclip then
				setAttribute(weaponEntry.ammo.textElement, "textstring", "/" .. math.max(0, weaponDetails.ammo - weaponDetails.currentclip))
			else
				setAttribute(weaponEntry.ammo.textElement, "textstring", weaponDetails.ammo)
			end
		end
		local weaponIcon = ffi.string(weaponDetails.icon)
		-- #coreUIMed - optimize - we can directly set the proper color, if we also change the current icon
		if weaponIcon ~= weaponEntry.icon.curIcon then
			SetIcon(weaponEntry.icon.textureElement, weaponIcon, nil, nil, nil, false)
			weaponEntry.icon.curIcon = weaponIcon
		end
		setWeaponColor(weaponEntry.icon, weaponDetails.active, weaponDetails.damageState, isdisabledbystance)
		-- #coreUIMed - clean structure up - better have a single element to process for setBarState() rather than passing the complete weapon-element-entry
		setBarState(weaponEntry.bar, weaponDetails.mode, weaponDetails.active, weaponDetails.reloadPercent, weaponDetails.heatState, weaponDetails.heatPercent, weaponDetails.nextShotHeatPercent, weaponDetails.isAutoReloading)
	end

	for i = 1, private.numTurrets do
		local turretDetails = C.GetTurret(i)
		local turretEntry = private.weaponPanel.turrets.turrets[i]
		if turretEntry.ammo.usesAmmo ~= turretDetails.usesAmmo then
			DebugError("Crosshair error. Mismatch between retrieved ("..tostring(turretDetails.usesAmmo)..") and recorded ("..tostring(turretEntry.ammo.usesAmmo)..") uses-ammo state for turret "..tostring(i).." - ammo might not be displayed or not updated correctly")
		end
		if turretDetails.usesAmmo then
			setAttribute(turretEntry.ammo.textElement, "textstring", turretDetails.ammo)
		end
		setTurretMode(turretEntry.mode, ffi.string(turretDetails.mode))
		local turretIcon = ffi.string(turretDetails.icon)
		-- #coreUIMed - optimize - we can directly set the proper color, if we also change the current icon
		if turretIcon ~= turretEntry.icon.curIcon then
			SetIcon(turretEntry.icon.textureElement, turretIcon, nil, nil, nil, false)
			turretEntry.icon.curIcon = turretIcon
		end
		setTurretColor(turretEntry.icon, turretDetails.active, turretDetails.damageState)
	end
end
