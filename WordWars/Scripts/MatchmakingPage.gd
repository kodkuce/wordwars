extends Control

signal request_play
signal confirm_play

var welcome_finished = false
var req_in_progress = false
var accepted = false

onready var ppm = $PopupMsg
onready var ppmtxt = $PopupMsg/Panel/MarginContainer/Label

func _on_GameplayPage_finished_game():
	if not is_visible():
		show()
	$Control/play.grab_focus()
#open when auth succesfull
func _on_LoginPage_auth_sucessful(t):
	if not is_visible():
		show()
	$Control/play.grab_focus()
#atm player counter
func _on_MySingleton_mmws_welcom_player(nick):
	if $matchmaking_labele.is_visible():
		$matchmaking_labele.text = "WELCOME "+nick
	yield(get_tree().create_timer(1.0), "timeout")
	welcome_finished = true
func _on_MySingleton_mmws_update_player_count(count):
	if $matchmaking_labele.is_visible() and welcome_finished:
		$matchmaking_labele.text = "PLAYERS ONLINE: "+count

#request game part
func _on_MySingleton_mmws_confirm_new_game( gi, p1, enick ):
	accepted = false
	ppmtxt.text = "Evil enemy, "+ enick +"\nheard you looking for \na fight, defend your glory!"
	$PopupMsg/Panel/accept_button.grab_focus()
	#"Game found for you \nyou need to confirm you ready!"
	accept_button_countdown()
	pass
func _on_MySingleton_mmws_succesfull_new_game():
	$PopupMsg/Panel/accept_button.hide()
	ppmtxt.text = "Have fun :)"
	req_in_progress = false
	ppm.hide()
	hide()
	
func _on_MySingleton_mmws_failed_new_game():
	$PopupMsg/Panel/accept_button.hide()
	
	if accepted:
		ppmtxt.text = "Other player did \nnot confirm game in \ntimely meaner! \nDon't wory you are \nstill in matchmaking queue!"
	else:
		ppmtxt.text = "You did not \nconfirm game \nand got droped from \nmatchmaking queue!"
		ppm.popup_exclusive = false
		ppm.popup()
		req_in_progress = false
	pass



func accept_button_countdown():
	$PopupMsg/Panel/accept_button.disabled = false
	$PopupMsg/Panel/accept_button.show()
	var n : int = 10
	while req_in_progress and n>=0:
	#for n in range(10,0,-1):
		$PopupMsg/Panel/accept_button.text = "ACCEPT: " + ("%02d" % n)
		if n == 0:
			$PopupMsg/Panel/accept_button.text = "FAILED"
			$PopupMsg/Panel/accept_button.disabled = true
		yield(get_tree().create_timer(1.0), "timeout")
		n = n - 1
	 
func _on_play_button_up():
	$Control/play.disabled = true
	var vswho = $Control/vswho.text.strip_edges()
	if vswho == "":
		print("pressed req game button")
		request_game()
	else:
		print("not implement yet, direct challange player")
		return
func request_game():
	if not req_in_progress:
		req_in_progress = true
		$PopupMsg/Panel/accept_button.hide()
		ppmtxt.text = "Looking for game..."
		ppm.popup_exclusive = true
		ppm.popup()
		emit_signal("request_play")


func _on_PopupMsg_popup_hide():
	$Control/play.disabled = false
	print("pop hiden")


func _on_accept_button_button_up():
	accepted = true
	ppmtxt.text = "Waiting for other \nplayer to accept..."
	$PopupMsg/Panel/accept_button.hide()
	emit_signal("confirm_play")
