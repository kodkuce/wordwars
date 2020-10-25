extends Node



#signals
signal mmws_connection_closed
signal mmws_welcome_player
signal mmws_update_player_count
signal mmws_got_in_queen
signal mmws_confirm_new_game
signal mmws_succesfull_new_game
signal mmws_failed_new_game

var gamserwer_domain = "nooooo.duckdns.org/grammergame/"

#matchmaking connection should be constanst so its here 
var authtoken =""#  "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzY29yZSI6IjAiLCJpZCI6IjEiLCJleHAiOjE1OTc0OTc2NzYsIm5pY2siOiJwb3NhbyJ9.hx6xYamt1L2OYDfBeV2946hpG6p2TBx_9zBmxNpbnEw"
#var mmurl = "ws://127.0.0.1:9001/play"

var mmurl = "wss://" + gamserwer_domain + "play/"
var mmws


func _ready():
	connect_all_signals()
func _process(delta):
	mmws_loop()


func connect_all_signals():
	$LoginPage.connect("auth_sucessful", self, "_on_LoginPage_auth_sucessful")
	$LoginPage.connect("auth_sucessful", $MatchmakingPage, "_on_LoginPage_auth_sucessful")
	$LoginPage.connect("go_register_page", $RegisterPage, "_on_LoginPage_go_register_page")
	$RegisterPage.connect("reg_sucessful", $LoginPage, "_on_RegisterPage_reg_sucessful")
	self.connect("mmws_update_player_count", $MatchmakingPage, "_on_MySingleton_mmws_update_player_count")
	self.connect("mmws_welcome_player", $MatchmakingPage, "_on_MySingleton_mmws_welcom_player")
	self.connect("mmws_confirm_new_game", $MatchmakingPage, "_on_MySingleton_mmws_confirm_new_game")
	self.connect("mmws_succesfull_new_game", $MatchmakingPage, "_on_MySingleton_mmws_succesfull_new_game")
	self.connect("mmws_failed_new_game", $MatchmakingPage, "_on_MySingleton_mmws_failed_new_game")
	$MatchmakingPage.connect("request_play", self, "_on_MatchmakingPage_request_game")
	$MatchmakingPage.connect("confirm_play", self, "_on_MatchmakingPage_confirm_game")
	self.connect("mmws_confirm_new_game", $GameplayPage, "_on_MySingleton_mmws_confirm_new_game")
	self.connect("mmws_succesfull_new_game", $GameplayPage, "_on_MySingleton_succesfull_new_game")
	self.connect("mmws_welcome_player", $GameplayPage, "_on_MySingleton_mmws_welcom_player")
	$LoginPage.connect("auth_sucessful", $GameplayPage, "_on_LoginPage_auth_sucessful")
	$GameplayPage.connect("finished_game", $MatchmakingPage, "_on_GameplayPage_finished_game")

func mmws_loop():
	if mmws != null and mmws.CONNECTION_CONNECTED:
		mmws.poll()
func setup_mmws():
	
	if mmws != null and not mmws.CONNECTION_DISCONNECTED:
		mmws.disconnect_from_host()
	print("creating ws client")
	mmws = WebSocketClient.new()
	mmws.connect("connection_closed", self, "mmws_closed")
	mmws.connect("connection_error", self, "mmws_closed")
	mmws.connect("connection_established", self, "mmws_connected")
	mmws.connect("data_received", self, "mmws_on_data")
	
	var err = mmws.connect_to_url(mmurl, ["xxx", authtoken], false )
	if err != OK:
		print("errored ws")
func mmws_closed(was_clean = false):
	print("closed aaa")
func mmws_connected(proto=""):
	print("connected")
func mmws_on_data():
	var rec_data = mmws.get_peer(1).get_packet().get_string_from_utf8()
	#print(rec_data)
	var parsed_data = JSON.parse(rec_data)
	
	if parsed_data.error == OK:	
		if parsed_data.result is Dictionary:
			if parsed_data.result.has("t"):
				
				#connection establisehd welcome
				if parsed_data.result["t"] == "welcome" and parsed_data.result.has("nick"):
					emit_signal("mmws_welcome_player", parsed_data.result["nick"]) 
					
				#update atm playercounter 
				elif parsed_data.result["t"] == "atm_con" and parsed_data.result.has("value"):
					emit_signal( "mmws_update_player_count", String(parsed_data.result["value"]) )

				#error on requesting game from serwer
				elif parsed_data.result["t"] == "ewtp" and parsed_data.result.has("msg"): 
					print(parsed_data.result["msg"])
					#$MasterUI/MatchMakingUI/InitPanel/InitPlayLBL.text = parsed_data.result["msg"]
					yield(get_tree().create_timer(1.0), "timeout")
					#$MasterUI/MatchMakingUI/InitPanel.hide()
				
				#good game request
				elif parsed_data.result["t"] == "cwtp":
					print ("aa")
					
				elif parsed_data.result["t"] == "confirm_new_game":
					var p1:bool = parsed_data.result["p1"]
					var gi = parsed_data.result["game_instance"]
					var enick = parsed_data.result["enick"]
					
					emit_signal( "mmws_confirm_new_game", gi, p1, enick )

				elif parsed_data.result["t"] == "new_game_confirmed":
					var good:bool = parsed_data.result["value"]
					if good:
						emit_signal("mmws_succesfull_new_game")
					else:
						emit_signal("mmws_failed_new_game")
					
func _on_MatchmakingPage_request_game():
	print( "req" )
	var msg = JSON.print({
	"t": "wtp",
	"value": true
	})
	mmws.get_peer(1).put_packet( msg.to_utf8() )
	
func _on_MatchmakingPage_confirm_game():
	var msg = JSON.print({
	"t": "cmf",
	"value": true
	})
	mmws.get_peer(1).put_packet( msg.to_utf8() )
	
func _on_LoginPage_auth_sucessful(t):
	authtoken = t
	setup_mmws()

