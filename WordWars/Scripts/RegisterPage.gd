extends Control

onready var ppm = $PopupMsg
onready var ppmtxt = $PopupMsg/Panel/MarginContainer/Label

signal reg_sucessful

var gamserwer_domain = "nooooo.duckdns.org/grammergame/"
var regurl = "https://" + gamserwer_domain + "reg/"
#var regurl = "http://127.0.0.1:8888/reg"
var sucessful = false
var try_reg_ended = true


func _unhandled_input(event):
	if event is InputEventKey:
		if event.pressed and event.scancode == KEY_ESCAPE and try_reg_ended and visible:
			print("esc on reg page")
			emit_signal("reg_sucessful")
			hide()


func try_req():
	try_reg_ended = false
	
	#VALIDATE EMAIL
	var emailtxt = $CenterContainer/VBoxContainer/email.text.strip_edges()
	# (^[a-zA-Z0-9_.+-]+@[a-zA-Z0-9-]+\.[a-zA-Z0-9-.]+$)
	var regexe = RegEx.new()
	regexe.compile("^[a-zA-Z0-9_.+-]+@[a-zA-Z0-9-]+\\.[a-zA-Z0-9-.]+$")
	var legite = regexe.search(emailtxt)
	if not legite:
		ppmtxt.text = "Invalid email:\nhmm meybe type something legit?"
		ppm.popup()
		return
	
	#VALIDATE USERNAME
	var usernametxt = $CenterContainer/VBoxContainer/username.text.strip_edges()
	var regex = RegEx.new()
	regex.compile("^[A-Za-z]{5,}$")
	var legit = regex.search(usernametxt)
	if not legit:
		ppmtxt.text = "Invalid username: \nminimum 5 characters and \nonly letters allowed!"
		ppm.popup()
		return
	
	#VALIDATE PASSWORD
	var password = $CenterContainer/VBoxContainer/password.text.strip_edges()
	var passwordv = $CenterContainer/VBoxContainer/password_validator.text.strip_edges()
	if passwordv == "" or password == "" or password.length() < 9:
		ppmtxt.text = "Invalid password: \npassword should have\nminimum 9 characters\nand you need to fill both\npassword fields"
		ppm.popup()
		return
	if password != passwordv:
		ppmtxt.text = "Passwords did not match \nplease check again\nwhat you have typed"
		ppm.popup()
		return
		
	#OK SO IF ALL IS VALID WE NOW SEND REGISTER REQUEST TO SERWER
	var data = JSON.print( { "email":emailtxt, "password":password, "username":usernametxt } )
	var headers = ["Content-Type: application/json"]
	$reg.request(regurl, headers, false, HTTPClient.METHOD_POST, data)

func _on_register_button_up():
	$CenterContainer/VBoxContainer/register.disabled = true
	try_req()
	pass # Replace with function body.

func _on_reg_request_completed(result, response_code, headers, body):
	if result == HTTPRequest.RESULT_SUCCESS:
		if response_code == 200:
			#print("Register request succesful")
			var jdata = JSON.parse( body.get_string_from_utf8() )
			#print(jdata.get_result()["ok"])
			sucessful = true
			ppmtxt.text = "Success:\nyour account has bean\ncreated please check\nyour email for\n activation link"
			ppm.popup()
		else:
			#print("Failed to register,sewer responed 400")
			var jdata = JSON.parse( body.get_string_from_utf8() )
			#print( jdata.get_result()["error"] )
			var errors = jdata.get_result()["error"]
			var towrite = ""
			for e in errors:
				towrite = e + "\n"
			ppmtxt.text = "Error:\n"+ towrite
			ppm.popup()
	else:
		#print("Failed to send register request to serwer")
		ppmtxt.text = "Error:\nNo response from\nregistration serwer\nmaybe try leater..."
		ppm.popup()

func _on_PopupMsg_popup_hide():
	if sucessful:
		emit_signal("reg_sucessful")
		hide()
		
	yield(get_tree().create_timer(0.5), "timeout")
	try_reg_ended = true
	$CenterContainer/VBoxContainer/register.disabled = false

func _on_LoginPage_go_register_page():
	if not is_visible():
		show()
