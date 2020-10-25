extends Node


var authurl = "http://127.0.0.1:8888/auth"


var mmurl = "ws://127.0.0.1:9001/play"
var mmws


var giws

var ppp = ""
var eee = ""
var uuu = ""
var tkn = ""

#UIs
onready var uiLoginGRP = $MasterUI/LoginUI
onready var uiMatchmakingGRP = $MasterUI/MatchMakingUI
onready var uiReqPlayerGRP = $MasterUI/MatchMakingUI/ReqPlayGRP
onready var uiInfoPanelGRP = $MasterUI/MatchMakingUI/InfoPanel

# Called when the node enters the scene tree for the first time.
func _ready():
	uiLoginGRP.get_node("Panel/MarginContainer/VBoxContainer/LoginBTN").grab_focus()
	pass # Replace with function body.


func _process(delta):
	mmloop()

		
	if giws != null and giws.CONNECTION_CONNECTED:
		giws.poll()




#AUTH
func _on_LoginBTN_button_up():
	doAuthHTTP()
func doAuthHTTP():
	var le = uiLoginGRP.get_node("Panel/MarginContainer/VBoxContainer/EmailTXT")
	var lp = uiLoginGRP.get_node("Panel/MarginContainer/VBoxContainer/PassTXT")
	var lb = uiLoginGRP.get_node("Panel/MarginContainer/VBoxContainer/LoginBTN")
	var lhttp = uiLoginGRP.get_node("HTTPRequest")
	
	le.editable = false
	lp.editable = false
	lb.disabled = true
	lb.release_focus()

	var data = JSON.print( { "email":le.text, "password": lp.text } )
	var headers = ["Content-Type: application/json"]
	lhttp.request(authurl, headers, false, HTTPClient.METHOD_POST, data)
func _on_AuthHTTPend(result, response_code, headers, body):
	if result == HTTPRequest.RESULT_SUCCESS:
		if response_code == 200:
			print("OK")
			print( body )			
			var jdata = JSON.parse( body.get_string_from_utf8() )
			#print( jdata.get_result()["ok"] )
			#print( jdata.get_result()["token"] )
			tkn = jdata.get_result()["token"]
			
			uiLoginGRP.hide()
			uiMatchmakingGRP.show()
			setupMM()
			
		else:
			print("ERROR")
			var jdata = JSON.parse( body.get_string_from_utf8() )
			#print( jdata.get_result()["error"] )
			var errors = jdata.get_result()["error"]
			var nl = ""
			for er in errors:
				nl = nl + er + "\n"
			$MasterUI/ErrorPopup/Panel/ErrorTextLBL.text = nl
			$MasterUI/ErrorPopup.popup()
	else:
		$MasterUI/ErrorPopup/Panel/ErrorTextLBL.text = "Failed to connect to auth server,\n possible down?"
		$MasterUI/ErrorPopup.popup()
		
			
	var le = uiLoginGRP.get_node("Panel/MarginContainer/VBoxContainer/EmailTXT")
	var lp = uiLoginGRP.get_node("Panel/MarginContainer/VBoxContainer/PassTXT")
	var lb = uiLoginGRP.get_node("Panel/MarginContainer/VBoxContainer/LoginBTN")
	var lhttp = uiLoginGRP.get_node("HTTPRequest")
	
	le.editable = true
	lp.editable = true
	lb.disabled = false
	
	pass # Replace with function body.

#MATCHMAKING
func setupMM():
	$MasterUI/MatchMakingUI/AtmPlayersLBL.text = "CONNECTING TO SERWER..."
	yield(get_tree().create_timer(1.0), "timeout")
	print("Starting a mm connection")
	if mmws != null and not mmws.CONNECTION_DISCONNECTED:
		mmws.disconnect_from_host()
	print("creating ws client")
	mmws = WebSocketClient.new()
	mmws.connect("connection_closed", self, "mmws_closed")
	mmws.connect("connection_error", self, "mmws_closed")
	mmws.connect("connection_established", self, "mmws_connected")
	mmws.connect("data_received", self, "mmws_on_data")
	
	var err = mmws.connect_to_url(mmurl, ["xxx", tkn], false )
	if err != OK:
		print(err)
		print("ERROR WS TO MM")
		$MasterUI/MatchMakingUI/AtmPlayersLBL.text = "CONNECTION ERROR"
		yield(get_tree().create_timer(1.0), "timeout")
#	else:
#		$MasterUI/MatchMakingUI/AtmPlayersLBL.text = "CONNECTION ESTABLISHED"
#		yield(get_tree().create_timer(1.0), "timeout")
		
func mmws_closed(was_clean = false):
	print("closed mm")
	uiMatchmakingGRP.get_node("AtmPlayersLBL").text = "CONNECTION FAILED"
	yield(get_tree().create_timer(1.0), "timeout")
	uiMatchmakingGRP.get_node("AtmPlayersLBL").text = "RECONNECTING IN 3"
	yield(get_tree().create_timer(1.0), "timeout")
	uiMatchmakingGRP.get_node("AtmPlayersLBL").text = "RECONNECTING IN 2"
	yield(get_tree().create_timer(1.0), "timeout")
	uiMatchmakingGRP.get_node("AtmPlayersLBL").text = "RECONNECTING IN 1"
	yield(get_tree().create_timer(1.0), "timeout")
	setupMM()
	
func mmws_connected(proto=""):
	print("connected")
func mmws_on_data():
	var rec_data = mmws.get_peer(1).get_packet().get_string_from_utf8()
	print(rec_data)
	var parsed_data = JSON.parse(rec_data)
	
	if parsed_data.error == OK:	
		if parsed_data.result is Dictionary:
			if parsed_data.result.has("t"):
				
				#connection establisehd welcome
				if parsed_data.result["t"] == "welcome" and parsed_data.result.has("nick"):
					uuu = parsed_data.result["nick"]
					
					uiMatchmakingGRP.get_node("AtmPlayersLBL").text = "WELCOME "+ uuu
				#update atm playercounter 
				elif parsed_data.result["t"] == "atm_con" and parsed_data.result.has("value"):
					uiMatchmakingGRP.get_node("AtmPlayersLBL").text = "ATM CONNECTED PLAYERS:" + String(parsed_data.result["value"])
				#error on requesting game from serwer
				elif parsed_data.result["t"] == "ewtp" and parsed_data.result.has("msg"): 
					$MasterUI/MatchMakingUI/InitPanel/InitPlayLBL.text = parsed_data.result["msg"]
					yield(get_tree().create_timer(1.0), "timeout")
					$MasterUI/MatchMakingUI/InitPanel.hide()
				#good game request
				elif parsed_data.result["t"] == "wtp":
					print ("aa")
				elif parsed_data.result["t"] == "confirm_new_game":
					$MasterUI/MatchMakingUI/InitPanel/InitPlayLBL.text = "Game found, accept ?"
					$MasterUI/MatchMakingUI/InitPanel/ConfirmBTN.show()
					$MasterUI/MatchMakingUI/InitPanel/ConfirmTimerLBL.start_count_down_timer()
				
func mmloop():
	if mmws != null and mmws.CONNECTION_CONNECTED:
		mmws.poll()

func _on_ErrorPopup_popup_hide():
	if $MasterUI/LoginUI.visible:
		$MasterUI/LoginUI/Panel/MarginContainer/VBoxContainer/EmailTXT.grab_focus()
	pass # Replace with function body.


func _on_PlayBTN_button_up():
	#block buttons first
	#$MasterUI/MatchMakingUI/PlayBTN.disabled = true
	#$MasterUI/MatchMakingUI/WithWhoTXT.editable = false
	
	var wwho = $MasterUI/MatchMakingUI/WithWhoTXT.text.strip_edges(true,true)
	print (wwho)
	if wwho == "":
		print("normal request")
		
		var msg = JSON.print({
		"t": "wtp",
		"value": "yes"
		})
		
		$MasterUI/MatchMakingUI/InitPanel.show()
		$MasterUI/MatchMakingUI/InitPanel/InitPlayLBL.text = "SEARCHING FOR A GAME..."
		mmws.get_peer(1).put_packet( msg.to_utf8() )
	else:
		print("exact request")
	pass # Replace with function body.


func _on_ConfirmBTN_button_up():
	pass # Replace with function body.
