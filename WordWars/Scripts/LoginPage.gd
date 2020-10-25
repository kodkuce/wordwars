extends Control

onready var ppm = $PopupMsg
onready var ppmtxt = $PopupMsg/Panel/MarginContainer/Label

var gamserwer_domain = "nooooo.duckdns.org/grammergame/"
var authurl = "https://" + gamserwer_domain + "auth/"
#var authurl = "http://127.0.0.1:8888/auth"
signal auth_sucessful( got_token )
signal go_register_page

func _ready():
	$VBoxContainer/login.grab_focus()

func try_login():
	#VALIDATE USERNAME AS USERNAME OR EMAIL
	var username = $VBoxContainer/username.text.strip_edges()
	var emaillogin = false
	if "@" in username: #treat like login in with email
		var regexe = RegEx.new()
		regexe.compile("^[a-zA-Z0-9_.+-]+@[a-zA-Z0-9-]+\\.[a-zA-Z0-9-.]+$")
		var legite = regexe.search(username)
		if not legite:
			ppmtxt.text = "Invalid email:\nit seams you typed\nan non valid email adreess"
			ppm.popup()
			return
		emaillogin = true	
	if not emaillogin:
		var regex = RegEx.new()
		regex.compile("^[A-Za-z]{5,}$")
		var legit = regex.search(username)
		if not legit:
			ppmtxt.text = "Invalid username: \nminimum 5 characters and \nonly letters allowed!"
			ppm.popup()
			return

	#VALIDATE PASSWORD
	var password = $VBoxContainer/password.text.strip_edges()
	if password.length() < 9:
		ppmtxt.text = "Invalid password: \npassword should have\nminimum 9 characters"
		ppm.popup()
		return
		
	#IF ALL GOOD TRY LOGIN
	var data
	if emaillogin:
		data = JSON.print( { "email":username, "password":password } )
	else:
		data = JSON.print( { "username":username, "password":password } )
	var headers = ["Content-Type: application/json"]
	$auth.request(authurl, headers, false, HTTPClient.METHOD_POST, data)

func _on_auth_request_completed(result, response_code, headers, body):
	if result == HTTPRequest.RESULT_SUCCESS:
		if response_code == 200:
			var jdata = JSON.parse( body.get_string_from_utf8() )
			#print(jdata.get_result()["ok"])
			#ppmtxt.text = "Success:\nWelcome "
			#ppm.popup()
			#succesfull login go to MM page
			#MySingleton.authtoken = jdata.get_result()["token"]
			$VBoxContainer/login.disabled = false
			$go_register_page.disabled = false	
			emit_signal("auth_sucessful", jdata.get_result()["token"])
			hide()
		else:
			print("Failed to login, sewer responed 400")
#			print( body.get_string_from_utf8() )
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

func _on_login_button_up():
	$VBoxContainer/login.disabled = true
	$go_register_page.disabled = true
	try_login()

func _on_PopupMsg_popup_hide():
	$VBoxContainer/login.disabled = false
	$go_register_page.disabled = false
	
func _on_go_register_page_button_up():
	hide()
	emit_signal("go_register_page")
	print("close self go open reg page TODO")

func _on_RegisterPage_reg_sucessful():
	if not is_visible():
		show()




