if not _ or not CopDamage then return end -- external dependancy and ingame check
if not (managers.hud and managers.hud._hud_mission_briefing) then return end
	managers.hud._hud_mission_briefing._backdrop._panel:child( "base_layer" ):set_alpha(0.5)
	managers.hud._hud_mission_briefing._backdrop._black_bg_ws:panel():hide()--:set_alpha(0)
--	managers.hud._hud_mission_briefing._backdrop._blackborder_workspace:hide() --hide()

-- Common simplefunctions
local me
local EMPTY_ARRAY = {}
local PERSON_TWEAKDATA = { intimidate = 1, hostage_convert = 1, hostage_move = 1, hostage_stay = 1, hostage_trade = 1, corpse_alarm_pager = 1 , corpse_dispose = 1 }
local ModPath = rawget(_G,'ModPath') or string.gsub(string.gsub(debug.getinfo(1).short_src,'\\','/'), "^(.+/)[^/]+$", "%1")
local theta = function(p,a,o)
	return Vector3( math.cos(a) * (p.x - o.x) - math.sin(a) * (p.y - o.y) + o.x, math.sin(a) * (p.x - o.x) + math.cos(a) * (p.y - o.y) + o.y , 0 )
end
local request = function(name)
	name = ModPath..'../Custom/map/'..name
	local f=io.open(name,"r")
	if f~=nil then
		io.close(f)
		return dofile(name)
	end
end

local ammoKey = '6d64ddbabb39af79'
--	Player 2, 3, 4, 5, AI Crew 16, 24
--	Normal Enemy 12, CIV 21, 22(tied - host only)
--	Sentry 25, 26
--	Projectile 14
--	Ammo 20, 23
local criminal_slotmask = World:make_slot_mask(2, 3, 4, 5, 16, 24)
local enemy_civ_slotmask = World:make_slot_mask(12, 21, 22)
local sentry_slotmask = World:make_slot_mask(25, 26)
local projectile_slotmask = World:make_slot_mask(14)
local itm_pnl_size = 100

request('legacy_map_Options.lua')
local Config = TPocoMapOption.Config
local colorMap = TPocoMapOption.colorMap

-- PocoMap Class --
local TPocoMap = class(TPocoBase)
TPocoMap.className = 'Map'
TPocoMap.classVersion = 3

local extOpt = io.open(ModPath.."../Custom/map/mapconfig.lua",'r')
if extOpt then
	extOpt = loadstring(extOpt:read('*all'))()
	for k,v in pairs(extOpt) do
		Config[k] = v
	end
else
	_.c('* PocoMap: No config provided. Please put \\poco\\mapconfig.lua')
end
local optScan = 1/(Config.optScan>0 and Config.optScan or math.huge)
local optDraw = 1/(Config.optDraw>0 and Config.optDraw or math.huge)
local optMap = Config.optMap and 1/(Config.optMap>0 and Config.optMap or math.huge) or 0

local map_oobb
TPocoMapOOBB = nil
if Config.dev_mode then request('legacy_map_devmode.lua') end
if TPocoMapOOBB then map_oobb = TPocoMapOOBB else Config.dev_mode = false end
if Config.dev_mode then
	colorMap = TPocoMapOption.colorMap
end

function TPocoMap:onInit()
	_('PocoMap INIT')
	local Run = function(key,...)
		if self.hooks[key] then
			return self.hooks[key][2](...)
		else
		end
	end
	local hook = function(Obj,key,newFunc)
		local realKey = key:gsub('*','')
		if not self.hooks[key] then
			self.hooks[key] = {Obj,Obj[realKey]}
			Obj[realKey] = function(...)
				if self.dead then
					return Run(key,...)
				else
					return newFunc(...)
				end
			end
		else
			_('!!Hook Name Collision:'..key)
		end
	end
	self.res = _.g('RenderSettings.resolution',{x=800,y=600})
	if Config.world_3d then
		self._mapSize = Config.mapSize
		self.render_template = "OverlayVertexColorTextured"
		self._cx = 175*120/(Config.world_3d_angle+30)
		self._cy = self._cx
		--self._ws = _.g('Overlay:newgui():create_screen_workspace()')
		--self._ws = World:newgui():create_world_workspace( self._cx*2, self._cy*2, Vector3(0,0,0), Vector3(500,0,0), Vector3(0,-500,0) )
		self._ws = World:newgui():create_screen_workspace()
	else
		self._mapSize = Config.mapSize*self.res.y/720
		self.render_template = "VertexColorTextured"
		self._cx = self.res.x / 2 + Config.halign * Config.hweight * self.res.x - Config.halign * self._mapSize / 2
		self._cy = self.res.y / 2 + Config.valign * Config.vweight * self.res.y * 0.65 - Config.valign * self._mapSize / 2
		self._ws = _.g('Overlay:newgui():create_screen_workspace()')
	end
	if not self._ws then return false end
	itm_pnl_size = self._mapSize
	self.pnl = 	self._ws:panel({ name = "pocomap_sheet" ,x = 0, y = 0, w= self.res.x, h=self.res.y })
	self.localPlayerId = managers.network:session():local_peer():id()
	self.items = {}
	self.hooks = {}
	self.bodies = {}
	self.memberCache = {}
	self.iconAssign = self.iconAssign or {}
	self.polyLimit = Config.polyLimit or 0
	self._throttle = false
	self.scanBreak = false
		
	hook( HUDManager, 'show_endscreen_hud', function( self )
		Run('show_endscreen_hud', self )
		me:onDestroy()
		me.Toggle()
	end)
	
	hook( NPCRaycastWeaponBase, 'singleshot', function( self, ... )
		self._poco_singleshot = true
		return Run('singleshot', self, ... )
	end)
	
	hook( NewNPCRaycastWeaponBase, '_sound_singleshot', function( self, ... )
		self._poco_singleshot = true
		Run('_sound_singleshot', self, ... )
	end)
	
	local width = self._mapSize/20
	if Config.mapBackground then
		--self.grid = self.pnl:rect({ name= "pre_bg", layer= 3, color= Color.white:with_alpha(0)})
		if Config.classic_mode then
			self.bg = self.pnl:bitmap( {
				name= "map_bg",
				texture= 'guis/textures/hud_icons',
				texture_rect=  { 243, 194, 26, 27 },
				layer= -1,
				color= Color.black:with_alpha(0.5),
				blend_mode= "normal",
				x= self._cx-self._mapSize/2 - width*2/3 ,
				y= self._cy-self._mapSize/2 - width*2/3 ,
				w= self._mapSize + width*4/3,
				h= self._mapSize + width*4/3,
				render_template = self.render_template
			} )
			self.bg_border = self.pnl:bitmap( {
				name= "map_bg_border",
				texture= 'guis/textures/pd2/hud_progress_active',
				layer= 0,
				color= Color.black,
				blend_mode= "normal",
				render_template = self.render_template
			} )
			self.bg_border:configure({ x= self._cx - self._mapSize /2  - width , y= self._cy - self._mapSize / 2 - width , w= self._mapSize + 2*width , h= self._mapSize + 2*width })
		else
			self.bg = self.pnl:rect( {
				name= "map_bg",
				layer= -1,
				color= Color.black:with_alpha(0.45),
				blend_mode= "normal",
				render_template = self.render_template
			} )
			self.bg_border = self.pnl:polyline({
				name= "map_bg_border",
				color= Color.black:with_alpha(0.6),
				layer= 0,
				line_width = width,
				closed= true,
				render_template = self.render_template
			})
			local rect = {
				Vector3( self._cx - ( self._mapSize + width ) /2 , self._cy - ( self._mapSize + width ) /2 , 0 ),
				Vector3( self._cx - ( self._mapSize + width ) /2 , self._cy + ( self._mapSize + width ) /2 , 0 ),
				Vector3( self._cx + ( self._mapSize + width ) /2 , self._cy + ( self._mapSize + width ) /2 , 0 ),
				Vector3( self._cx + ( self._mapSize + width ) /2 , self._cy - ( self._mapSize + width ) /2 , 0 )
			}
			self.bg_border:set_points(rect)
		end
	end
	
	self.intimidateCircle = self.pnl:bitmap( {
		name= "area",
		texture= 'guis/textures/crimenet_map_circle',
		layer= 1,
		color= Color.white,
		blend_mode= "add",
		alpha = 0.3,
		render_template = self.render_template
	} )
	
	local size_setting = {x= self._cx-self._mapSize/2, y= self._cy-self._mapSize/2, w= self._mapSize, h= self._mapSize}
	if Config.mapBackground and not Config.classic_mode then self.bg:configure(size_setting) end
	--self.intimidateCircle:configure(size_setting)
	
	--- Cache ---
	self.pnl:bitmap({layer=8, texture = 'guis/textures/pd2/scrollbar_arrows', texture_rect = {0,0,12,12}, render_template = self.render_template, alpha=0})
	self.pnl:bitmap({layer=7, texture = 'guis/textures/pd2/scrollbar_arrows', texture_rect = {0,0,12,12}, render_template = self.render_template, alpha=0})
	local texture, rect = tweak_data.hud_icons:get_icon_data( 'icon_addon' )
	self.pnl:bitmap({layer=7, texture = texture, texture_rect = rect, render_template = self.render_template, alpha = 0 })
	self.fireFlashList = {}
	if true then
		local width = self._mapSize
		if not Config.classic_mode then width = width *1.1 end
		local tex, tex_r
		for r=1,7 do
			tex, tex_r = tweak_data.hud_icons:get_icon_data( 'icon_circlefill'..r )
			self.fireFlashList[r] = self.pnl:bitmap ({ 
				name = "flash",
				layer = 10,
				texture = tex or "guis/textures/circlefill",
				texture_rect = tex_r or { 32, 0, 16, 16 },
				color = Color.red,
				x= self._cx-width/2,
				y= self._cy-width/2,
				w= width,
				h= width,
				visible = false,
				render_template = self.render_template
			})
		end
		tex, tex_r = tweak_data.hud_icons:get_icon_data( 'scroll_dn' )
		self.fireHeightDN = self.pnl:bitmap ({ 
			name = "flash_DN",
			layer = 10,
			texture = tex or "guis/textures/circlefill",
			texture_rect = tex_r or { 32, 0, 16, 16 },
			color = Color.green:with_alpha(1),
			blend_mode= "add",
			x= 0,
			y= 0,
			w= self._mapSize/5,
			h= self._mapSize/5,
			visible = false,
			render_template = self.render_template
		})
		tex, tex_r = tweak_data.hud_icons:get_icon_data( 'scroll_up' )
		self.fireHeightUP = self.pnl:bitmap ({ 
			name = "flash_UP",
			layer = 10,
			texture = tex or "guis/textures/circlefill",
			texture_rect = tex_r or { 32, 0, 16, 16 },
			color = Color.green:with_alpha(1),
			blend_mode= "add",
			x= 0,
			y= 0,
			w= self._mapSize/5,
			h= self._mapSize/5,
			visible = false,
			render_template = self.render_template
		})
	end
	if Config.dev_mode then
		self.icons = TPocoMapOption.iconLoad() or {}
	else
		self.icons = TPocoMapOption.iconCache
	end
	self.ammo = {{clip_max=1, total_left=1, total_max=1}, {clip_max=1, total_left=1, total_max=1}}
	self.grid_lines = {}
	self.pnl:hide()
	return true
end

function TPocoMap:import(data)
	self.iconAssign = data.iconAssign
end

function TPocoMap:export()
	Poco.save[self.className] = {
		iconAssign = self.iconAssign
	}
end

function TPocoMap:onResolutionChanged()
	if not Config.world_3d then
		self.res = _.g('RenderSettings.resolution',{x=800,y=600})
		self._mapSize = Config.mapSize*self.res.y/720
		self._cx = self.res.x / 2 + Config.halign * Config.hweight * self.res.x - Config.halign * self._mapSize / 2
		self._cy = self.res.y / 2 + Config.valign * Config.vweight * self.res.y * 0.65 - Config.valign * self._mapSize / 2
		self.pnl:configure( {
			w= self.res.x,
			h= self.res.y
		} )
		local size_setting = {x= self._cx-self._mapSize/2, y= self._cy-self._mapSize/2, w= self._mapSize, h= self._mapSize}
		if Config.mapBackground then
			local width = self._mapSize/20
			if not Config.classic_mode then
				local rect = {
					Vector3( self._cx - ( self._mapSize + width ) /2 , self._cy - ( self._mapSize + width ) /2 , 0 ),
					Vector3( self._cx - ( self._mapSize + width ) /2 , self._cy + ( self._mapSize + width ) /2 , 0 ),
					Vector3( self._cx + ( self._mapSize + width ) /2 , self._cy + ( self._mapSize + width ) /2 , 0 ),
					Vector3( self._cx + ( self._mapSize + width ) /2 , self._cy - ( self._mapSize + width ) /2 , 0 )
				}
				self.bg_border:set_points(rect)
				self.bg_border:configure({line_width = width})
				self.bg:configure(size_setting)
			else
				self.bg:configure( {
					x= self._cx-self._mapSize/2-48*self._mapSize/250,
					y= self._cy-self._mapSize/2-48*self._mapSize/250,
					w= self._mapSize+96*self._mapSize/250,
					h= self._mapSize+96*self._mapSize/250
				} )
				self.bg_border:configure({ x= self._cx - ( self._mapSize + width ) / 2 , y= self._cy - ( self._mapSize + width ) / 2 , w= self._mapSize + width , h= self._mapSize + width })
			end		
		end
		self.intimidateCircle:configure(size_setting)
	end
end

function TPocoMap:Update(t, dt)
	local r,e = pcall(self._update,self,t,dt)
	if not r then
		_('PocoMap UpdErr:'..e)
	end
end

function TPocoMap:onDestroy()
	for key,hook in pairs(self.hooks or {}) do
		local realKey = key:gsub('*','')
		local Obj,func = hook[1],hook[2]
		Obj[realKey] = func
		self.hooks[key] = nil
	end
	
	if alive(self._ws) then
		if Config.world_3d then
			World:gui():destroy_workspace(self._ws)
		else
			Overlay:gui():destroy_workspace(self._ws)
		end
	end
end

function TPocoMap:_checkAngle(vec,item)
	local ang = math.atan2(vec.x,vec.y)
	local angle = math.ceil(ang/360*Config.iconGroupFar)
	local a = self.angles[angle]
	if not a then
		self.angles[angle] = {}
		self.angles[angle][item.typeDetail] = {}
	else
		if a[item.typeDetail] and a[item.typeDetail].ang then
			if a[item.typeDetail].ang < ang then
				return true
			else
				self.angles[angle][item.typeDetail].pnl:set_visible(false)
			end
		else
			self.angles[angle][item.typeDetail] = {}
		end
	end
	self.angles[angle][item.typeDetail].ang = ang
	self.angles[angle][item.typeDetail].pnl = item.pnl
	return false
end
function TPocoMap:_isSpecial(unit)
	local utweak = alive(unit) and ( unit:base() or EMPTY_ARRAY )._tweak_table or '-'
	return 	(tweak_data.character[ utweak ] or EMPTY_ARRAY).priority_shout
end
function TPocoMap:_isInteractivePerson(tweak_data) -- Intimidate-able Mob or Tie-able person
	return PERSON_TWEAKDATA[tweak_data]
end
function TPocoMap:_isBelowAmmo()
	local showAmmo = false
	for k,v in pairs(self.ammo) do
		if math.min(math.sqrt(v.total_max*v.clip_max),v.total_max/3) > v.total_left then showAmmo = true end
	end
	-- There are two cases. If a weapon has too many clips comparing max_ammo(like piglet), first sqaure root thing is applied.
	-- Otherwise, max_ammo / 3 is applied. (like cross bow)
	if showAmmo then return true else return false end
end

function TPocoMap:_getSkillIcon(skill_id)
	local skill = tweak_data.skilltree.skills[ skill_id ]
	if skill then
		local texture_rect_x = (skill.icon_xy and skill.icon_xy[1]) or 0
		local texture_rect_y = (skill.icon_xy and skill.icon_xy[2]) or 0
		return "guis/textures/pd2/skilltree/icons_atlas", { texture_rect_x*64, texture_rect_y*64, 64, 64 }
	else return false
	end
end
function TPocoMap:getIcon(itm)
	local icon, iconrect = 'guis/textures/pd2/scrollbar_arrows', {0,0,12,12}
	if itm.type < 3 and itm.unit then
		if itm.type == 1 then
			itm.isInvisible = false
			local uKey = itm.unit:key()
			local member = uKey and self.memberCache[uKey]
			if member then
				if member == self.localPlayerId then itm.isLocalPlayer = true end
				return (member and tweak_data.chat_colors[member] or Color.blue), Color.white, icon,iconrect
			elseif (itm.unit:in_slot(24) or itm.unit:in_slot(16)) then -- AI crew
				return colorMap.clAICrew, Color.white,icon,iconrect
			else
				if itm.special then
					if itm.special == 'f45' then -- captain
						icon , iconrect = 'guis/textures/pd2/hud_buff_shield', {4, 4, 24, 24}
						itm.notRotate = true
					end
					itm.isInvisible = true
					return colorMap.clSpecial[itm.special] or Color.red, Color.red, icon,iconrect				
				else	-- CIV, COP
					local unit_anim_data = itm.unit:anim_data() or EMPTY_ARRAY
					if managers.enemy:is_enemy( itm.unit ) then
						local tied_anim = unit_anim_data.hands_tied
						if tied_anim then
							return  Color.yellow, Color.black, icon, iconrect
						end
						itm.isInvisible = true
						return colorMap.clEquip, Color.black, icon, iconrect	-- Normal Mob. Probably.
					else
						local tied_anim = unit_anim_data.tied
						if tied_anim or ( itm.unit:interaction() or EMPTY_ARRAY ).tweak_data == 'hostage_stay' then
							return Color.yellow, Color.white, icon, iconrect
						end
						itm.isInvisible = true
						return colorMap.clFreeCiv, Color.white, icon, iconrect
					end					
				end
			end
		elseif itm.type == 1.5 then
			itm.notRotate = true
			local prj = ( itm.unit:base() or EMPTY_ARRAY )._tweak_projectile_entry
			if prj then -- ArrowTypeAmmo
				if string.find(prj, 'wpn_prj') then -- Projectile Style (Grenade)
					icon, iconrect = tweak_data.hud_icons:get_icon_data( prj:gsub('wpn_prj_','')..'_projectile' )
					return colorMap.clJam, Color.black, icon, iconrect
				else -- Crossbow Style
					icon, iconrect = tweak_data.hud_icons:get_icon_data( 'jav_projectile' )
					return colorMap.clBag, Color.black, icon, iconrect
				end
			elseif itm.unit:name() and itm.unit:name():key() == ammoKey then -- Normal pickupAmmo
				icon = 'guis/textures/pd2/skilltree/icons_atlas'
				iconrect = {162, 10, 25, 25}
				return colorMap.clJam, Color.black, icon, iconrect
			elseif itm.unit:in_slot(25) or itm.unit:in_slot(26) then -- Sentry or Turret
				icon, iconrect = tweak_data.hud_icons:get_icon_data( 'equipment_sentry' )
				local clr = Color.red
				itm.isInvisible = true
				if ( itm.unit:base() or EMPTY_ARRAY )._tweak_table_id  == 'sentry_gun' then
					clr = colorMap.clBag
					itm.isInvisible = false
				end
				return clr, Color.black, icon,iconrect
			end
		elseif itm.type == 2 then
			itm.notRotate = true
			local clr
			local ict = self.icons[itm.tweak_data]
			if ict then
				if self:_getSkillIcon(ict) then
					icon, iconrect = self:_getSkillIcon(ict)
				else
					icon, iconrect = tweak_data.hud_icons:get_icon_data( ict )
				end
				if Config.dev_mode then TPocoMapOption.iconAssign(itm.tweak_data, ict) end
				if itm.tweak_data == 'gage_assignment' then ict = itm.unit:base()._assignment end
			else
				icon, iconrect = nil, nil
				if Config.dev_mode then icon, iconrect = TPocoMapOption.iconUnAssigned(itm.tweak_data) end
			end
			clr = colorMap[ict] or colorMap.clEquip
			return  clr, Color.black, icon, iconrect
		end
	elseif itm.type == 3 then
		itm.notRotate = true
		return colorMap.clWaypoint, Color.black, tweak_data.hud_icons:get_icon_data( itm.iconText, {0, 0, 32, 32} )
	elseif itm.type == 4 then
		return Color.white, Color.black, icon, iconrect
	elseif itm.type == 5 then
		local clr
		if itm.area == 'smoke' then
			clr = Color('777777'):with_alpha(0.8)
			icon, iconrect = 'guis/textures/pd2/blackmarket/icons/masks/jw_shades', {0, 0, 128, 128}
			return Color.white, clr, icon, iconrect
		elseif itm.area == 'fire' then
			clr = Color('772222'):with_alpha(0.5)
			icon, iconrect = tweak_data.hud_icons:get_icon_data( 'pd2_fire' )
		else
			clr = Color('777777'):with_alpha(0.5)
			icon, iconrect = 'guis/dlcs/big_bank/textures/pd2/pre_planning/preplan_icon_types', {240, 192, 48, 48}
		end
		return Color.red, clr, icon, iconrect
	else
		return Color.green, Color.red, icon, iconrect
	end
end

function TPocoMap:itemRegister(key,data,t)
	local itm = self._items[key] or self.items[key] or data
	if not itm then return end
	if self.scanBreak then
		self.items[key] = itm
	else
		self._items[key] = itm
		self.items[key] = nil
	end
	itm.t = t
	itm.unitAlive = alive(itm.unit)
	local clFg,clBg,icon,iconrect = self:getIcon(itm)
	if itm.fg and itm.fg ~= clFg then
		if itm.bmp then
			itm.bmp:configure ({
				texture= icon or 'guis/textures/pd2/infamous_symbol',
				texture_rect= iconrect,
				color = clFg
			})
		end
		if itm.bg then
			itm.bg:configure ({
				texture= icon or 'guis/textures/pd2/infamous_symbol',
				texture_rect= iconrect,
				color = clBg:with_alpha(0.8)
			})
		end
		itm.fg = clFg
		itm.typeDetail = itm.type..tostring(clFg)..tostring(icon or '')..(iconrect and iconrect[1] or '')
	end
	if not itm.pnl then
		itm.fg = clFg
		itm.typeDetail = itm.type..tostring(clFg)..tostring(icon or '')..(iconrect and iconrect[1] or '')
		itm.pnl = self.pnl:panel({ x=0,y=0,w=itm_pnl_size*2,h=itm_pnl_size*2})
		if itm.type == 1 then -- Person
			itm.ratio = itm.ratio or Config.arrowRatio
			itm.special = self:_isSpecial(itm.unit)
			itm.bmp = itm.pnl:bitmap( {
				name= "icon",
				texture= icon or 'guis/textures/pd2/infamous_symbol',
				texture_rect= iconrect,
				layer= 8,
				blend_mode= "normal",
				render_template = self.render_template
			} )
			if clBg then
				clBg = clBg:with_alpha(0.8)
				itm.bg = itm.pnl:bitmap( {
					name= "iconbg",
					texture= icon or 'guis/textures/pd2/infamous_symbol',
					texture_rect= iconrect,
					layer= 7,
					blend_mode= "normal",
					render_template = self.render_template
				} )
			end
			itm.weapon_unit_base = itm.unit:inventory() and itm.unit:inventory():equipped_unit() and itm.unit:inventory():equipped_unit():base() or nil
		elseif itm.type <= 2 then -- Interactive or ammo
			itm.bmp = itm.pnl:bitmap( {
				name= "icon",
				texture= icon or 'guis/textures/pd2/infamous_symbol',
				texture_rect= iconrect,
				layer= 6,
				blend_mode= "add",
				render_template = self.render_template
			} )
			itm.sentry = itm.unit:in_slot(25) and ( itm.unit:base() or EMPTY_ARRAY ).sentry_gun and itm.unit:weapon() or nil
		elseif itm.type == 3 then -- wp
			itm.bmp = itm.pnl:bitmap( {
				name= "icon",
				texture= icon or 'guis/textures/pd2/infamous_symbol',
				texture_rect= iconrect,
				layer= 5,
				blend_mode= "normal",
				render_template = self.render_template			
			} )
		elseif itm.type == 4 then -- obstacle Rect
			if map_oobb then map_oobb.register(itm) end
		elseif itm.type == 5 then -- Smoke Grenade
			if itm.unit then
				itm.bmp = itm.pnl:bitmap( {
					name= "special_bmp",
					texture= icon or 'guis/textures/pd2/infamous_symbol',
					texture_rect= iconrect,
					layer= 10,
					blend_mode= "normal",
					render_template = self.render_template
				} )
				if ( itm.unit:base() or EMPTY_ARRAY )._smoke_effect then itm.bmp:set_blend_mode("sub") end
			end
			if itm.area then
				itm.bg = itm.pnl:bitmap( {
					name= "special_bg",
					texture= 'guis/textures/pd2/hud_progress_32px',
					texture_rect= {0,0,32,32},
					layer= 9,
					blend_mode= "normal",
					render_template = self.render_template
				} )
			end
		end
		-- Panel Common Settings
		itm.ratio = itm.ratio or 1
		if itm.bmp then itm.bmp:configure({	x= 0, y= 0, w= 1, h= 1, color = clFg}) end
		if itm.bg then itm.bg:configure({	x= 0, y= 0, w= 1, h= 1, color = clBg}) end
	end
	if not self.scanBreak then self:_drawPanel(itm, t) end
end
function TPocoMap:itemUnregister(key,item)
	self.pnl:remove(item.pnl)
	self.items[key] = nil
end

function TPocoMap:scan(t)	
	self.angles = {}
	self._fireFlashDist = math.huge
	self._items = {}
	local objs = {}
	
	if not self.scanBreak then 
		-- 1. Scan Persons
		objs = World:find_units_quick( "all", criminal_slotmask )
		for k,unit in pairs(objs) do
			if not (unit:character_damage() and unit:character_damage():dead() ) then
				local key = unit:id()
				self:itemRegister(key, { type = 1, unit = unit } ,t)
			end
		end
		
		objs = World:find_units_quick( "all", enemy_civ_slotmask )
		self.scanCount = 0
		for k,unit in pairs(objs) do
			if not ( unit:character_damage() and unit:character_damage():dead() ) then
				local key = unit:id()
				if self._items[key] or self.items[key] then
					self:itemRegister(key,nil,t)
					self.scanCount = self.scanCount + 1
				elseif self.lastScanEnemyCiv or 0 < 50 then -- very low: 20, low: 30, standard : 50, many : 80, -- 1:20, 3.5:~65
					self:itemRegister(key, { type = 1,  unit = unit } ,t)
					self.scanCount = self.scanCount + 1
				end
			end
		end
		self.lastScanEnemyCiv = self.scanCount
	
		-- 1.1. Turret or Sentry gun
		objs = World:find_units_quick( "all", sentry_slotmask )
		for k,unit in pairs(objs) do
			if not ( unit:character_damage() and unit:character_damage():dead() ) then
				local key = unit:id()
				self:itemRegister(key, { type = 1.5, unit = unit } ,t)
			end
		end
	
		-- 2. Scan Interaction things
		objs = managers.interaction._interactive_units or {}
		self.scanCount = 0
		for k,unit in pairs( objs ) do
			local tweak = ( unit:interaction() or EMPTY_ARRAY ).tweak_data
			if tweak and not self:_isInteractivePerson(tweak) then
				if ( unit:base() or EMPTY_ARRAY )._is_attachable == false then
				else
					local key = 'interaction'..unit:id()
					local ict = self.icons[tweak]			
					if ict == '' then
						if Config.dev_mode then TPocoMapOption.iconAssign(tweak, ict) end
					elseif ict then
						if self._items[key] or self.items[key] then
							self:itemRegister(key,nil,t)
							self.scanCount = self.scanCount + 1
						elseif self.lastScanInteraction or 0 < 200 then
							self:itemRegister(key, { type = 2, unit = unit, tweak_data = tweak } ,t)
							self.scanCount = self.scanCount + 1
						end
					elseif Config.dev_mode then
						self:itemRegister(key, { type = 2, unit = unit, tweak_data = tweak } ,t)
					end
				end
			end
		end
		self.lastScanInteraction = self.scanCount
		
		-- 3. Scan Pickups (ammo)
		objs = World:find_units_quick( "all", managers.slot:get_mask('pickups') )
		for k,unit in pairs(objs) do
			local key = unit:id()
			if unit:name() and unit:name():key() == ammoKey then
				local s = unit:position() - self.pos
				if self:_isBelowAmmo() and math.sqrt(s.x*s.x+s.y*s.y+s.z*s.z) < Config.mapRange then
					self:itemRegister(key, { type = 1.5, unit = unit } ,t)
				end
			else
				self:itemRegister(key, { type = 1.5, unit = unit } ,t)
			end
		end
	end
	
	-- 1.2 Projectile type (grenade, launcher)
	objs = World:find_units_quick( "all", projectile_slotmask )
	for k,unit in pairs(objs) do
		local unit_base = unit:base()
		if unit_base then
			local key = unit:id()
			local unit_size, area_type
			if key ~= -1 and unit_base._effect_name then
				if unit_base._effect_name:find('molotov') then
					unit_size = 250
					area_type = 'fire'
				else
					area_type = 'grenade'
					unit_size = unit_base._range or 300
				end
				local itm = {
					type = 5,
					unit = unit,
					area = area_type,
					size = {x=unit_size,y=unit_size},
				}
				self:itemRegister('grenade'..key,itm,t)
			elseif unit_base._smoke_effect then
				key = unit_base._smoke_effect
				unit_size = 300
				local itm = {
					type = 5,
					unit = unit,
					area = 'smoke',
					size = {x=unit_size,y=unit_size},
				}
				self:itemRegister('smoke'..key,itm,t)
			end
		end
	end
	
	-- 4. Add waypoints
	objs = managers.hud._hud.waypoints or {}
	for id, wp in pairs( objs ) do
		if not (wp.init_data.icon == 'wp_suspicious' or wp.init_data.icon == 'wp_detected' or wp.init_data.icon == 'wp_calling_in_hazard' ) then
			local itm = {
				type = 3,
				unit = wp.unit,
				pos = wp.position,
				iconText = wp.init_data.icon or 'wp_standard'
			}
			self:itemRegister('wp'..id,itm,t)
		end
	end
	
	-- 5. scanOOBBs
	if map_oobb then map_oobb.scan(Config, t) end
end

function TPocoMap:draw(t)
	if not self.cam_rot then return end
	if self.scanBreak then
		for key,item in pairs(self.items) do
			item.unitAlive = alive(item.unit)
			if item.type == 3 and managers.hud._hud.waypoints[item.id] then
				item.t = t
			elseif item.unitAlive then
				if item.unit:character_damage() and item.unit:character_damage():dead() then
				elseif item.type == 2 and not (item.unit:interaction() or EMPTY_ARRAY)._active then -- drill
				else
					item.t = t
				end
			elseif item.type == 4 then
				item.t = t
			end
			if item.t < t then -- Decay Items
				if item.unitAlive and item.type == 1 then
					if not item.decaying then
						self:_drawDecayPanel(item)
					end
					self:_drawDecay(key, item, t)
				else
					self:itemUnregister(key,item)
				end
			else
				self:_drawPanel(item, t)
			end
		end
	else -- Unregister every objects except decaying panel
		for key,item in pairs(self.items) do
			item.unitAlive = alive(item.unit)
			if item.unitAlive and item.type == 1 and item.unit:character_damage() and item.unit:character_damage():dead() then
				if not item.decaying then
					self:_drawDecayPanel(item)
				end
				self:_drawDecay(key, item, t)
				self._items[key] = self.items[key]
			else
				self:itemUnregister(key,item)
			end
		end
		self.items = self._items
	end
	
	--- fireFlash ---
	local fireFlashTime = 1/3
	if not self.fireFlash and self._fireFlashWorking then
		self._fireFlashStart = t
		local r = math.floor( 3*self._fireFlashDist/Config.mapRange + 1)
		if r > 7 then r = 7 end
		self.fireFlash = self.fireFlashList[r]
		local rot = -math.lerp(9.25,13.25,math.random())*r + self._fireFlashAng
		if Config.mapRotate then rot = rot + self.cam_rot:yaw() + 180 end
		self.fireFlash:set_rotation(rot)
		if math.abs(self._fireFlashHeight) > 230 then
			if self._fireFlashHeight < 0 then
				self.fireHeight = self.fireHeightDN
			else
				self.fireHeight = self.fireHeightUP
			end
			if r < 4 then self.fireHeight:configure ({ w= self._mapSize/(9-r), 	h= self._mapSize/(9-r)}) end
			local p = { x= self._cx, y= self._cy-self._mapSize/3}
			p = theta(p,rot+11.25*r,{x= self._cx, y= self._cy})
			self.fireHeight:set_center(p.x,p.y)
		end
	elseif self.fireFlash then
		if t-self._fireFlashStart > fireFlashTime then
			self.fireFlash:set_visible(false)
			if self.fireHeight then
				self.fireHeight:set_visible(false)
				self.fireHeight = nil
			end
			self.fireFlash = nil
			self._fireFlashStart = 0
			self._fireFlashWorking = false
		else
			self.fireFlash:set_visible(true)
			self.fireFlash:set_alpha(0.7*(1-(t-self._fireFlashStart)/fireFlashTime))
			if self.fireHeight then
				self.fireHeight:set_visible(true)
				self.fireHeight:set_alpha(0.7*(1-(t-self._fireFlashStart)/fireFlashTime))
			end
		end
	end
	
	--- Grid Line ---
	local grid_size = Config.mapRange * Config.grid_size / 1000
	local nSG = math.ceil( self.range * 2 / grid_size * math.sqrt(2) ) + 1
	local grid_coord = {x= self.pos.x % grid_size , y= self.pos.y % grid_size }
	local rect, p_1, p_2 = {}
	local p_x, p_y, ang, radius = 0,0,0, self._mapSize/2
	
	if #self.grid_lines > nSG*2 then
		for i = nSG*2 + 1, #self.grid_lines do
			self.pnl:remove(self.grid_lines[i])
			self.grid_lines[i] = nil
		end
	end
	for i= 1, nSG*2 do
		if not self.grid_lines[i] then
			self.grid_lines[i] = self.pnl:polyline( {
				name= "grid_line",
				color= Color.white,
				alpha= 0.1,
				layer= 3,
				line_width= 3,
				closed= false
			} )
		end
		if Config.classic_mode then
			local check = 0
			if i > nSG then
				p_y= ( grid_size * ( ( i - nSG  ) - math.floor( nSG / 2 )) - grid_coord.y ) * radius / self.range
				ang = Config.mapRotate and self.cam_rot:yaw()+180 or 0
			else
				p_y= ( grid_size * ( i - math.floor(nSG/2)) - grid_coord.x ) * radius / self.range
				ang = Config.mapRotate and self.cam_rot:yaw()-90 or 90
			end
			p_x= radius * radius - p_y * p_y
			if p_x > 0 then
				p_x= math.sqrt(p_x)
				p_1 = theta({x= - p_x,y= p_y},ang,{x=0,y=0})
				p_2 = theta({x= p_x,y= p_y},ang,{x=0,y=0})
				rect[1] = Vector3( self._cx + p_1.x , self._cy + p_1.y )
				rect[2] = Vector3( self._cx + p_2.x , self._cy + p_2.y )
				self.grid_lines[i]:set_points(rect)
				if not self.grid_lines[i]:visible() then self.grid_lines[i]:set_visible(true) end
			elseif self.grid_lines[i]:visible() then
				self.grid_lines[i]:set_visible(false)
			end
		else
			if i > nSG then
				p_y= ( grid_size * ( ( i - nSG  ) - math.floor( nSG / 2 )) - grid_coord.y ) * radius / self.range 
				ang = Config.mapRotate and self.cam_rot:yaw()+180 or 0
			else
				p_y= ( grid_size * (i - math.floor(nSG/2)) - grid_coord.x ) * radius / self.range
				ang = Config.mapRotate and self.cam_rot:yaw()-90 or 90
			end
			p_x= radius * math.sqrt(2) 
			p_1 = theta({x= - p_x,y= p_y},ang,{x=0,y=0})
			p_2 = theta({x= p_x,y= p_y},ang,{x=0,y=0})
			local ratio_1 = math.abs ( p_1.x ) > radius and (math.abs( p_1.x ) - radius ) /  math.abs ( p_1.x - p_2.x ) or 0
			ratio_1 = math.abs ( p_1.y ) > radius and math.max ( (math.abs( p_1.y ) - radius ) /  math.abs ( p_1.y - p_2.y ) , ratio_1 ) or ratio_1
			local ratio_2 = math.abs ( p_2.x ) > radius and (math.abs( p_2.x ) - radius ) /  math.abs ( p_1.x - p_2.x ) or 0
			ratio_2 = math.abs ( p_2.y ) > radius and math.max ( (math.abs( p_2.y ) - radius ) /  math.abs ( p_1.y - p_2.y ) , ratio_2 ) or ratio_2
			if ratio_1 + ratio_2 < 1 then
				rect[1] = Vector3( self._cx +p_1.x + (p_2.x-p_1.x)*ratio_1, self._cy + p_1.y + (p_2.y-p_1.y)*ratio_1 )
				rect[2] = Vector3( self._cx +p_2.x + (p_1.x-p_2.x)*ratio_2, self._cy + p_2.y + (p_1.y-p_2.y)*ratio_2 )
				self.grid_lines[i]:set_points(rect)
				if not self.grid_lines[i]:visible() then self.grid_lines[i]:set_visible(true) end
			elseif self.grid_lines[i]:visible() then
				self.grid_lines[i]:set_visible(false)
			end
		end
	end	
end
function TPocoMap:_drawPanel(item, t)
	item.pos = item.unitAlive and item.unit:position() or item.pos
	local vec = self.cam_pos - item.pos
	local alpha = 1
	if item.type < 3 and item.unitAlive then
		if item.weapon_unit_base then 
			if (item.weapon_unit_base._poco_singleshot or item.weapon_unit_base._shooting) and not item.isLocalPlayer then
				if not self.fireFlash and self._fireFlashDist > vec:length() then
					self._fireFlashAng = math.atan2(vec.x,vec.y)
					self._fireFlashDist = vec:length()
					self._fireFlashHeight = -vec.z
					self._fireFlashWorking = true
				end
				if item.weapon_unit_base._poco_singleshot then item.weapon_unit_base._poco_singleshot = false end
			end
		elseif item.sentry then
			if item.sentry._shooting then
				if not self.fireFlash and self._fireFlashDist > vec:length() then
					self._fireFlashAng = math.atan2(vec.x,vec.y)
					self._fireFlashDist = vec:length()
					self._fireFlashHeight = -vec.z
					self._fireFlashWorking = true
				end
			end
			--log(_.s(item.unit:character_damage()._health)..'__'.._.s(item.unit:character_damage()._shield_health))
		end
		-- This return things must be after fire shot catch. otherwise, flash won't be work.
		if not Config.dev_mode and item.isInvisible and not ( item.unit:contour() or EMPTY_ARRAY )._contour_list then
			local float = ( PocoHud3 or EMPTY_ARRAY ).floats and PocoHud3.floats[item.unit:key()]
			if float then
				if not item.pnl:visible() then item.pnl:set_visible(true) end
				alpha = float.pnl:alpha()
			else
				if item.pnl:visible() then item.pnl:set_visible(false) end
				return
			end
		end
	end
	local yaw = self.cam_rot:yaw()
	local zoom = self.range / self._mapSize * 2	
	local tvec = vec / zoom
	if Config.mapRotate then tvec = theta(tvec, -(yaw+180),{x=0,y=0}) end
	local dist = math.max ( math.abs( tvec.x ) , math.abs ( tvec.y ) )
	if Config.classic_mode then
		dist = math.sqrt(tvec.x*tvec.x+tvec.y*tvec.y)
	end
	if dist < self._mapSize/2 or self.updateFar then
		local hdiff = (item.pos - self.pos - math.UP*20).z
		local izoom = math.min(zoom,15)
		local checkAngle
		--if dist > self._mapSize/2 then checkAngle = self:_checkAngle(vec, item) end
		if checkAngle then
			item.pnl:set_visible(false)
		else
			if math.abs(hdiff) > Config.mapRange then -- ridiculously far
				item.pnl:set_alpha(0)
			elseif math.abs(hdiff) > 230 then
				item.pnl:set_alpha(alpha*0.3)
			else
				item.pnl:set_alpha(alpha)
			end
			if item.type == 1 and (item.unit:in_slot(12) or item.unit:in_slot(21) or item.unit:in_slot(22)) and not self:_isSpecial(item.unit) then
				izoom = izoom/Config.npcScale
			end
			if dist > self._mapSize/2 then
				if Config.classic_mode then
					tvec = tvec * self._mapSize / dist / 2
				else
					local ratio = self._mapSize / math.max( math.abs( tvec.x ) , math.abs( tvec.y ) ) / 2
					tvec = tvec * ratio
				end
				izoom = izoom/Config.iconScaleFar
				if item.type > 3 then -- oobb or smoke panel
					if item.pnl:visible() then item.pnl:set_visible(false) end
					return
				end
			end
			local dotSize = Config.itemSize * ( item.type > 1 and item.type <= 3 and Config.iconScale or 1)
			local rot = item.unitAlive and item.unit:rotation() and item.unit:rotation():yaw() or item.rot
			local pxPos = {x=self._cx+tvec.x,y=self._cy-tvec.y}
			if item.type < 4 then
				if item.bmp then
					item.bmp:set_size(dotSize/izoom,dotSize/izoom*item.ratio)
					item.bmp:set_center(itm_pnl_size,itm_pnl_size)
					if rot and not item.notRotate then
						item.bmp:set_rotation(-rot+(Config.mapRotate and yaw or 180))
					elseif item.type == 1 and not item.notRotate then
						item.bmp:set_rotation((Config.mapRotate and 0 or 180-yaw))
					end
				end
				if item.decaying then
					item.decaying:set_size(dotSize/izoom,dotSize/izoom)
					item.decaying:set_center(itm_pnl_size,itm_pnl_size)
					item.decaying:set_alpha(1-(t-item.t)/Config.itemDecayTime)
				end
				if item.bg then
					item.bg:set_size(dotSize/izoom+2*Config.itemBorder,dotSize/izoom*item.ratio+2*Config.itemBorder)
					item.bg:set_center(itm_pnl_size,itm_pnl_size)
					if rot and not item.notRotate then
						item.bg:set_rotation(-rot+(Config.mapRotate and yaw or 180))
					elseif item.type == 1 and not item.notRotate then
						item.bg:set_rotation((Config.mapRotate and 0 or 180-yaw))
					end
				end
				if item.isLocalPlayer then
					local ms = self._mapSize*self.rangeRate
					self.intimidateCircle:set_size(ms,ms)
					self.intimidateCircle:set_center(pxPos.x,pxPos.y)
					if item.bmp then item.bmp:set_rotation(Config.mapRotate and 0 or 180-yaw) end
					if item.bg then item.bg:set_rotation(Config.mapRotate and 0 or 180-yaw) end
				end
			elseif map_oobb and item.type == 4 then
				map_oobb.draw(Config, item, rot, yaw, itm_pnl_size)
			elseif item.type == 5 then
				local p_x=item.size.x*self._mapSize/self.range
				local p_y=item.size.y*self._mapSize/self.range
				if item.bmp then
					item.bmp:set_size(p_x,p_y)
					item.bmp:set_center(itm_pnl_size,itm_pnl_size)
				end
				if item.bg then
					item.bg:set_size(p_x,p_y)
					item.bg:set_center(itm_pnl_size,itm_pnl_size)
				end
			end
			item.pnl:set_center(pxPos.x,pxPos.y)
			if not item.pnl:visible() then item.pnl:set_visible(true) end
		end
	end
end
function TPocoMap:_drawDecayPanel(item)
	item.isInvisible = nil
	local texture, rect = tweak_data.hud_icons:get_icon_data( 'icon_addon' )--'guis/textures/pd2/hitconfirm'
	local clr = item.special and Color.red or item.fg
	item.decaying = item.pnl:bitmap({ name = 'decay', texture = texture, texture_rect = rect, rotation = 45, color = clr, layer=7, render_template = self.render_template, alpha=0 })
	if item.bmp then
		item.pnl:remove(item.bmp)
		item.bmp = nil
	end
	if item.bg then
		item.pnl:remove(item.bg)
		item.bg = nil
	end
end
function TPocoMap:_drawDecay(key, item, t)
	if t-item.t >= Config.itemDecayTime then
		item.pnl:remove(item.decaying)
		item.decaying = nil
		self:itemUnregister(key, item)
	else
		self:_drawPanel(item, t)
	end
end

local _lastThrottle, _lastUpdate, _lastScan, _lastArea, _lastFarDraw, _everyCheck = 0,0,0,0,0,0
function TPocoMap:setPerformance(t, dt)
	if dt > 1/Config.Tht and t-_lastUpdate < 1 then
		_lastThrottle = t
		if self.polyLimit ~=0 then self.polyLimit = self.polyLimit - 1 end
		self._throttle = true
	else
		_lastUpdate = t
		self._throttle = false
	end
	if t - _lastThrottle > 1 and self.polyLimit < ( Config.polyLimit or 0 ) then self.polyLimit = self.polyLimit + 1 end
	
	self.scanBreak = true
	if t-_lastScan > optScan then
		_lastScan = t
		self.scanBreak = false
	end
	self.scanBreak_oobb = true
	if t-_lastArea > optMap then
		_lastArea = t
		self.scanBreak_oobb = false
	end
	self.updateFar = false
	if t-_lastFarDraw > optDraw then
		_lastFarDraw = t
		self.updateFar = true
	end
	
	if t - _everyCheck > 1 then
		_everyCheck = t
		if managers.network:session() then -- Peer Data
			self.memberCache = {}
			for k,m in pairs(managers.network:session()._peers_all) do
				if m:unit() then
					self.memberCache[m:unit():key()] = m:id()
				end
			end
		end
		if managers.player:local_player() then -- Local Player Ammo
			local weapon_selections = managers.player:local_player():inventory():available_selections()
			local __, total_left, total_max, clip_max
			for k,v in pairs(weapon_selections) do
				local weapon_data = v.unit:base()
				clip_max, __, total_left, total_max = weapon_data:ammo_info()
				if weapon_data:weapon_tweak_data().AMMO_PICKUP and weapon_data:weapon_tweak_data().AMMO_PICKUP[1] * weapon_data:weapon_tweak_data().AMMO_PICKUP[2] ~= 0 then
					self.ammo[k] = {clip_max=clip_max, total_left=total_left, total_max=total_max}
				else
					self.ammo[k] = {clip_max=1, total_left=1, total_max=1}
				end
			end
		end
	end
end

function TPocoMap:_update(t, dt)
	if self.dead then return end
	if not self.shown and game_state_machine:current_state_name() ~= "ingame_waiting_for_players" then
		self.pnl:show()
	end
	local playerAlive = managers.player:player_unit()
	self.fov = playerAlive and playerAlive:camera()._camera_object:fov() or 75
	self.cam_pos = playerAlive and playerAlive:camera()._camera_object:position() or managers.viewport:get_current_camera_position()
	self.last_cam_pos = self.last_cam_pos or self.cam_pos
	self.pos = playerAlive and playerAlive:position() or self.cam_pos
	self.cam_rot = playerAlive and playerAlive:camera()._camera_object:rotation() or managers.viewport:get_current_camera_rotation()
	if not (self.pos and self.cam_rot) then return end
	local speed = math.min(math.max( _.g('managers.player:player_unit():movement():current_state()._last_velocity_xy:length()',0) /500 - 0.6 , 0 ) , 1 )
	self.range_t = math.lerp(  Config.mapRange, Config.mapRange*1.2, speed )
	local isADS = _.g('managers.player:player_unit():movement():current_state()._state_data.in_steelsight')
	local ray
	if Config.mapSmartRange and self.cam_rot then
		local from = self.cam_pos
		if not from then return end
		local to = from + self.cam_rot:y() * 300000
		ray = World:raycast( "ray", from, to, "slot_mask", managers.slot:get_mask( "explosion_targets" ))
	end
	if isADS and ray then
		self.range_t = math.max(math.ceil((ray.distance+200)/1000)*1000,self.range_t)
	else
		self.range_t = self.range_t
	end
	local r = self.range or self.range_t
	self.range = r + (self.range_t-r)/10
	----
	local range_mul = managers.player:upgrade_value( "player", "intimidate_range_mul", 1 ) * managers.player:upgrade_value( "player", "passive_intimidate_range_mul", 1 )
	local intimidate_range_civ = tweak_data.player.long_dis_interaction.intimidate_range_civilians * range_mul
	self.rangeRate = intimidate_range_civ / self.range
	
	if Global.FadeoutObjects and Global.FadeoutObjects[1] and Global.FadeoutObjects[1]._panel then
		self.pnl:set_alpha(1-Global.FadeoutObjects[1]._panel:alpha())
	elseif not Config.dev_mode then
		local fb = math.min(1,managers.environment_controller._current_flashbang)
		local hs = math.min(1,managers.environment_controller._hit_some)
		local fb1 = math.max(fb,hs)
		self.pnl:set_alpha(1-fb1)
	end
	
	self:setPerformance(t, dt)
	if not self._throttle then
		self:scan(t)
		self:draw(t)
		self.intimidateCircle:set_visible( not not managers.player:player_unit() )
	end
	if alive(self._ws) and Config.world_3d then
		local a, x, y, o, r
		local x_axis = math.tan(self.fov/2)/1.3
		local z_axis = self._cx*math.sin(Config.world_3d_angle)*x_axis
		--local k = -Config.halign * (math.cos(Config.world_3d_angle*4/5 + 90) +1)
		local k = -Config.halign * (math.cos(Config.world_3d_angle*4/5 + 90) +2)
		
		--a = Vector3( (self.cam_pos.x + self.last_cam_pos.x)/2 , (self.cam_pos.y + self.last_cam_pos.y)/2 , (self.cam_pos.z + self.last_cam_pos.z)/2 ) + Vector3(-self._cx*(0.5-Config.halign*1.2)*x_axis,self._cy,(k+0.5)*z_axis):rotate_with(self.cam_rot)
		--x = Vector3(self._cx*x_axis ,0,0):rotate_with(self.cam_rot)
		--y = Vector3(-self._cy*Config.halign*1.2*math.cos(Config.world_3d_angle)*x_axis,-self._cy*math.cos(Config.world_3d_angle),-z_axis*(k*math.cos(Config.world_3d_angle) + 1)):rotate_with(self.cam_rot)
		
		o = Vector3( (self.cam_pos.x*2 + self.last_cam_pos.x)/3 , (self.cam_pos.y*2 + self.last_cam_pos.y)/3 , (self.cam_pos.z*2 + self.last_cam_pos.z)/3 )
		a = o + Vector3(-(k+0.5)*z_axis,self._cy,self._cx*(0.5-Config.valign*0.2)*x_axis):rotate_with(self.cam_rot)
		x = Vector3(z_axis*(k*math.cos(Config.world_3d_angle) + 1),-self._cy*math.cos(Config.world_3d_angle),0*self._cy*Config.valign*0.2*math.cos(Config.world_3d_angle)*x_axis):rotate_with(self.cam_rot)
		y = Vector3(-5, -5, -self._cx*x_axis):rotate_with(self.cam_rot)
		
		self._ws:set_world( self._cx*2, self._cy*2, a, x , y )
		self.last_cam_pos = o
	end
end

-- +0.3 : sqrt(1.39)

PocoMap = PocoMap
TPocoMap.Toggle = function()
	me = Poco:AddOn(TPocoMap)
	if me and not me.dead then
		PocoMap = me
	else
		PocoMap = true
	end
end
if Poco and not Poco.dead then
	if Config.dev_mode and Poco.addOns[TPocoMap.className] then
		local menu = {}
		table.insert(menu, { text="legacy map menu",callback = TPocoMapOption.MapMenu } )
		table.insert(menu, { text="Turn off map",callback = TPocoMap.Toggle } )
		table.insert(menu, { text="Cancel", is_cancel_button = true } )
		TPocoMapOption.SimpleMenuV2:new('Map menu', '', menu):show()
	else
		TPocoMap.Toggle()
	end
else
	managers.menu_component:post_event( 'zoom_out')
end
