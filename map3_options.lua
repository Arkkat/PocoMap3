TPocoMapOption = {}
TPocoMapOption.Config = {
	itemSize = 180,		-- default ItemSize as centimeter, default value is 180
	iconScale = 1.5,	-- Equipment or interactive icon scale, default value is 1.5
	iconScaleFar = 0.7,	-- Far icon scale, default value is 0.7
	iconGroupFar = 50,	-- maximum number of 'far' icons grouped as, default value is 50
	itemDecayTime = 5,	-- decaying time of dead units. default value is 5 seconds
	itemBorder = 3,		-- items' border as pixels, default value is 3
	npcScale = 0.65,	-- Non special enemy and civilian scale, default value is 0.65
	arrowRatio = 1.4,	-- person unit arrows' height ratio, default 1.4
	mapBackground = true,	-- On/Off map background
	mapSize = 250,		-- map's width as pixels, default is 250.
	mapRotate = true,	-- true: rotate map as camera moves
	mapSmartRange = true,	-- true: ADS to far areas will zoom out
	mapRange = 2000,		-- Scanning radius in centimeter, default 2000
	grid_size = 500,		-- Grid size of background
	
	optScan = 3,		-- FPS cap for fetching far objects. 0 = disable optimization
	optDraw = 15,		-- FPS cap for drawing far objects.  0 = disable optimization
	Tht = 55,			-- Throttling FPS to minimize lagging
	classic_mode = false,	-- Classic : Circle type, false value means rectangular type
	halign = 1,			-- -1 : left side, 0 : center, 1 : right side
	valign = 1,			-- -1 : top side, 0 : center, 1 : bottom side
	hweight = 0.475,	-- weight of left or right position, 0~0.5, if value is 0, it is same as center position
	vweight = 0.475,	-- weight of top or bottom position, 0~0.5, if value is 0, it is same as center position
	
	world_3d = true,
	world_3d_angle = 60
}
TPocoMapOption.iconCache = {
	carry_drop = 'wp_bag',
	hold_pickup_lance = 'wp_bag',
	money_bag = 'wp_bag',
	painting_carry_drop = 'wp_bag',
	safe_carry_drop = 'wp_bag',
	apartment_saw_jammed = 'pd2_drill',
	drill_jammed = 'pd2_drill',
	huge_lance_jammed = 'pd2_drill',
	lance_jammed = 'pd2_drill',
	hack_suburbia_jammed = 'pd2_computer',
	hack_suburbia_jammed_y = 'pd2_computer',
	uload_database_jammed = 'pd2_computer',
	votingmachine2_jammed = 'pd2_computer',
	ammo_bag = 'equipment_ammo_bag',
	doctor_bag = 'equipment_doctor_bag',
	first_aid_kit = 'equipment_first_aid_kit',
	bodybags_bag = 'equipment_bodybags_bag',
	trip_mine = 'equipment_trip_mine',
	ecm_jammer = 'equipment_ecm_jammer',
	grenade_crate = 'frag_grenade',
	gage_assignment = 'wp_target'
}	

local clWaypoint = Color('ff00ff')
local clJam = Color('ff3f00')
local clBag = Color('009090')
local clAICrew = Color('ee8800')
local clFreeCiv = Color('9900ff')
local clEquip = Color.white:with_alpha(0.7)
TPocoMapOption.colorMap = {
	wp_bag = clBag,
	redAmmo = clJam,
	blueAmmo = clBag,
	pd2_drill = clJam,
	pd2_computer = clJam,
	equipment_ammo_bag = clJam,
	equipment_doctor_bag = clJam,
	equipment_first_aid_kit = clJam,
	equipment_bodybags_bag = clJam,
	frag_grenade = clJam,
	green_mantis = Color('bbff00'),
	yellow_bull = Color('ffff00'),
	red_spider = Color('ff5d5d'),
	blue_eagle = Color('00d6ff'),
	purple_snake = Color('8100ff'),
	clSpecial = {
		f30 = Color('000000'), -- Dozer
		f31 = Color('cccccc'), -- Shield
		f32 = Color('00ffff'), -- Taser
		f33 = Color('66ff00'), -- Cloaker
		f34 = Color('cccc33'), -- Sniper
		f45 = Color('ff9900')  -- Captain
	},
	clWaypoint = clWaypoint,
	clJam = clJam,
	clBag = clBag,
	clAICrew = clAICrew,
	clFreeCiv = clFreeCiv,
	clEquip = clEquip
}
