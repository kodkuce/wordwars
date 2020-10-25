extends Control


signal finished_game

var isp1:bool
var finished:bool = false
var my_nick = ""
var enemy_nick = ""
var gameserwer_address
var gameserwer_port
var authtoken = ""
var giws

onready var ppm = $PopupMsg
onready var ppmtxt = $PopupMsg/CenterContainer/Panel/MarginContainer/Label

onready var scrtxt = $score_ui/MarginContainer/scoretxt
onready var inptxt = $player_input_ui/MarginContainer/inputtxt
onready var p1pwr = $player_ui/powerbar
onready var p2pwr = $enemy_ui/powerbar

#gamplay
onready var rocket_root = $rockets_root
onready var rocket_prefab = load("res://Sceens/Rocket.tscn")
onready var rocket_shader = load("res://Shaders/pixleize.shader")
var rockets = []

var p1score = 0
var p2score = 0
var inputing_string = ""
var p1powerbar = 0
var p2powerbar = 0
var scrambled_timeout = 0.0

var gameserwer_domain = "nooooo.duckdns.org/grammergame/"

func ready_up():
	#GAME WIZE
	for r in range(30):
		var rk = Rocket.new()
		rk.state = -1
		var rpref = rocket_prefab.instance()
		rpref.get_node("Label").material = ShaderMaterial.new()
		rpref.get_node("Label").material.shader = rocket_shader
		rocket_root.add_child(rpref)
		rk.n = rpref
		rpref.get_node("DriveAnim").seek(randf(),true)
		rockets.append(rk)

func _ready():
	#yield(get_tree().create_timer(0.1), "timeout")
	ready_up()


func _process(delta):
	giws_loop()
	rocket_loop(delta)
	powerup_loop(delta)
	display_scrabled(delta)

func _unhandled_input(event):
	if not is_visible():
		return
	
	if event is InputEventKey:	
		if not event.pressed:
			var key = OS.get_scancode_string(event.scancode)
			
			if not event.pressed and event.scancode == KEY_1:
				print("pressed 1")
				if p1powerbar > 500:
					var asjson = JSON.print({
					"t": "powerup",
					"v": 0
					});
					giws.get_peer(1).put_packet(asjson.to_utf8())
					return
			
			if not event.pressed and event.scancode == KEY_2:
				if p1powerbar >= 1000:
					var asjson = JSON.print({
					"t": "powerup",
					"v": 1
					});
					giws.get_peer(1).put_packet(asjson.to_utf8())
					return
			
			#clear old if any
			if(event.scancode in range(64,91))  or event.scancode == KEY_BACKSPACE:
				if inptxt.text == "TYPE NEXT ROCKET CODE ...":
					inputing_string = ""
					inptxt.text = ""
					
			if(event.scancode in range(64,91)):
				inputing_string += key
			elif(event.scancode == KEY_BACKSPACE) and inputing_string.length() > 0:
				if inputing_string.length() == 1:
					inputing_string = ""
				else:
					inputing_string = inputing_string.left( inputing_string.length() -1 )
			elif(event.scancode == KEY_SPACE) and inputing_string.length() > 1:
				inputing_string += " "
			

			#update ui labele
			if inputing_string != "":
				inptxt.text = inputing_string
			else:
				inptxt.text = "TYPE NEXT ROCKET CODE ..."
				
		if not event.pressed and event.scancode == KEY_ENTER:
			if inputing_string == "" or inputing_string == "TYPE NEXT ROCKET CODE ...":
				return
			
			var asjson = JSON.print({
				"t": "kr",
				"w": inputing_string
			});
			
			giws.get_peer(1).put_packet(asjson.to_utf8())
			inputing_string = ""
			inptxt.text = "TYPE NEXT ROCKET CODE ..."

func _on_LoginPage_auth_sucessful(t):
	authtoken = t
	print("passed token")
	print(authtoken)

func _on_MySingleton_mmws_welcom_player(nick):
	my_nick = nick

func _on_MySingleton_mmws_confirm_new_game(gi, p1, enick):
	gameserwer_address = gi[0]
	gameserwer_port = gi[1]
	print(gameserwer_address)
	print(gameserwer_port)
	
	isp1 = p1
	enemy_nick = enick
	
func _on_MySingleton_succesfull_new_game():
	#yield(get_tree().create_timer(1), "timeout")
	setup_game()
	show()

func _on_PopupMsg_popup_hide():
	if finished:
		print("goint MM page")
		hide()
		emit_signal("finished_game")

func setup_game():
	$start_animation.play("uiAnim")
	$players_root/come.play("top_flyin")
	
	#cleanup from old game
	print("run cleanup")
	$ExplosionParticle.hide()
	$ExplosionParticle.emitting = false
	p1pwr.value = 0
	p1pwr.value = 0
	p1powerbar = 0
	p2powerbar = 0
	p1score = 0
	p2score = 0
	scrtxt.text ="ENEMY SCORE : " + ("%08d" % p2score) + \
	 "\nYOUR SCORE : " + ("%08d" % p1score) + "\nLANGUAGE : ENGLISH"
	
	var v99 = Vector2(99999,99999)
	for r in rockets:
		r.n.position = v99
		r.pos = v99
	
	inptxt.text = "TYPE NEXT ROCKET CODE ..."
	
	$player_ui/name.text = my_nick
	$enemy_ui/name.text = enemy_nick
	finished = false
	setup_giws()
func giws_loop():
	if not is_visible():
		return
	if giws != null and giws.CONNECTION_CONNECTED:
		giws.poll()
	
func setup_giws():
	if giws != null and not giws.CONNECTION_DISCONNECTED:
		giws.disconnect_from_host()
	print("creating ws client")
	giws = WebSocketClient.new()
	giws.connect("connection_closed", self, "giws_closed")
	giws.connect("connection_error", self, "giws_closed")
	giws.connect("connection_established", self, "giws_connected")
	giws.connect("data_received", self, "giws_on_data")
	#"ws://127.0.0.1:9001/play"
	#owerwrite gamserwer adrres cuz using domain nmae
	#var faddress = "wss://" + gameserwer_address + ":" + String(gameserwer_port)+ "/ws"	
	var faddress = "wss://" +  gameserwer_domain + "gs" + String(gameserwer_port) + "/"
	print(faddress)
	var err = giws.connect_to_url(faddress, ["xxx", authtoken], false )
	if err != OK:
		print("errored wss")
	giws.poll()
func giws_closed(was_clean = false):
	print("closed ", was_clean)
func giws_connected(proto=""):
	print("connected")
func giws_on_data():
	var rec_data = giws.get_peer(1).get_packet().get_string_from_utf8()
	#print(rec_data)
	var data = JSON.parse(rec_data)
	
	if data.error == OK:	
		if data.result is Dictionary:
			if data.result.has("t"):			
				
				if data.result["t"] == "spawn": #spawn rocket
					#print( "spawning rocket" )
					#print (data)
					#print (data.result)
					var i = data.result["i"]
					rockets[i].n.show()
					rockets[i].word = data.result["w"]
					rockets[i].owner = data.result["o"]			
					rockets[i].speed = data.result["s"]
					rockets[i].scrabled = data.result["c"]
					rockets[i].n.get_node("Label").material.set_shader_param("pixelSize",1)
					
#					if rockets[i].scrabled:
#						rockets[i].scrabled_pos = rand_range(0,rockets[i].word.length())
					rockets[i].scrabled_pos = 1
					
					rockets[i].pos = Vector2( data.result["p"].x, data.result["p"].y )
					rockets[i].state = data.result["a"]

					rockets[i].n.get_node("Label").text = rockets[i].word
					rockets[i].n.get_node("sfx").play()

					#owner rocket is gray to him
					if (rockets[i].owner == 0 and isp1) or (rockets[i].owner == 1 and not isp1):
						rockets[i].n.modulate = Color(0.3,0.3,0.3,1)
					else:
						rockets[i].n.modulate = Color(1,1,1,1)
#
					if (rockets[i].owner == 0 and isp1) or (rockets[i].owner == 1 and not isp1):
						rockets[i].n.get_node("RocketParticle").gravity = Vector2(0,98)
					else: #TODO FIGURE OUT WHY BUGGED NOT CHANGE COLOR OR PARTICLE FOR P2
						rockets[i].n.get_node("RocketParticle").gravity = Vector2(0,-98)

				if data.result["t"] == "r": #move rocket
					var i = data.result["i"]
					rockets[i].pos = Vector2( data.result["p"].x, data.result["p"].y )
		
				if data.result["t"] == "sd": #shoot down rocket
					print("kill rocket")
					var i = data.result["i"]
					rockets[i].state = 1 #going down state
					if (rockets[i].owner == 0 and isp1) or (rockets[i].owner == 1 and not isp1):
						p2score = p2score + rockets[i].word.length()*24 #TODO BACK TO 24
						p2powerbar = clamp(p2powerbar + rockets[i].word.length()*24, 0, 1000) 
					else:
						p1score = p1score + rockets[i].word.length()*24
						p1powerbar = clamp(p1powerbar + rockets[i].word.length()*24, 0, 1000)
					#update socre
					scrtxt.text ="ENEMY SCORE : " + ("%08d" % p2score) + \
					 "\nYOUR SCORE : " + ("%08d" % p1score) + "\nLANGUAGE : ENGLISH"
					
					
				if data.result["t"] == "gs":
					print("GameStarted")
					
				if data.result["t"] == "powerup_t":
					print("powerup_t heppend")
					#{"t":"powerup_t", "p":took_slot ,"v":475}
					var tooks = data.result["p"]
					if isp1:
						if tooks == 0:
							p1powerbar -= data.result["v"]
						elif tooks == 1:
							p2powerbar -= data.result["v"]
					else:
						if tooks == 0:
							p2powerbar -= data.result["v"]
						elif tooks == 1:
							p1powerbar -= data.result["v"]
					
				if data.result["t"] == "ge":
					var exp_place = rockets[ data.result["i"] ].n.position
					rockets[ data.result["i"] ].n.hide()
					$ExplosionParticle.position = exp_place 
					$ExplosionParticle.emitting = true
					$ExplosionParticle.show()
					finished = true
					
					#ADD SFX 
					
					
					var shp = Vector2(1/get_viewport().size.x * exp_place.x, 1-(1/get_viewport().size.y * exp_place.y))
					$CanvasLayer/ColorRect.material.set_shader_param("center", shp )
					$CanvasLayer/exp_shader_animation.play("exp_shader")
					print("GameEnded player ", (data.result["w"] + 1) ," won!" )
					yield(get_tree().create_timer(2.0), "timeout")
					
					if (isp1 and data.result["w"]==0) or ( not isp1 and data.result["w"]==1):
						print("you won")
						ppmtxt.text = "Oh glorius "+my_nick+" \nyou have scored victory in \none more intergalactic battle \nkeep the good work!"
						ppm.popup()
					else:
						print("you lost")
						ppmtxt.text = "Your command skills were week \nyou and your crew \nare now floating in space \nhopfull someone will find your sorry ass!"
						ppm.popup()

func rocket_loop(delta):
	for r in range(30):
		if rockets[r].state == 0 or rockets[r].state == 1: # rActive or rGoingDown
			
			if isp1:
				if abs( rockets[r].n.position.x ) > 800:#if out of screen teleport instant
					rockets[r].n.position = rockets[r].pos	#so we dont lerp on spawn
				#smooth move rocket form pos to pos
				rockets[r].n.position = lerp(rockets[r].n.position,rockets[r].pos, delta)
			
			if not isp1:
				var inv = Vector2( 1024 - rockets[r].pos.x, 600 - rockets[r].pos.y)
				#var inv = Vector2( get_viewport().size.x - rockets[r].pos.x, get_viewport().size.y  - rockets[r].pos.y)
				#print("rp:", rockets[r].n.position, "  >  ", inv)
				if abs( rockets[r].n.position.x ) > 800:#if out of screen teleport instant
					rockets[r].n.position = inv #rockets[r].pos	#so we dont lerp on spawn
				#smooth move rocket form pos to pos
				rockets[r].n.position = lerp(rockets[r].n.position, inv, delta) #rockets[r].pos
			
		if rockets[r].state == 1:
			rockets[r].n.modulate = Color( rockets[r].n.modulate.r, rockets[r].n.modulate.g, rockets[r].n.modulate.b, rockets[r].n.modulate.a - delta)		
func powerup_loop(delta):
	if not finished:
		p1pwr.value = lerp(p1pwr.value, p1powerbar, 1*delta )
		p2pwr.value = lerp(p2pwr.value, p2powerbar, 1*delta )

				
func display_scrabled(delta):
	for r in rockets:
		if r.scrabled:
			var mymat = r.n.get_node("Label").get_material()
			if mymat == null:
				print("aaaaaa")
				get_tree().quit()
			var p = mymat.get_shader_param("pixelSize")
			if p > 4:
				r.scrabled_pos = 0
			if p < 0.1:
				r.scrabled_pos = 1
			
			if r.scrabled_pos == 1:
				mymat.set_shader_param("pixelSize", p + delta*3)
			else:
				mymat.set_shader_param("pixelSize", p - delta*3)
				

class Rocket:
	var n:Node2D
	var i:int
	var word:String
	var scrabled:bool
	var scrabled_pos:int
	var speed:float
	var owner:int
	var pos:Vector2
	var state:int
	
class PlayerData:
	var id:int
	var score:int
