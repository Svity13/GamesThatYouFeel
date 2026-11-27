extends Node2D
# Interrogation game that reacts to the player's webcam-estimated emotion (calm / anxious / scared).
# tracker.py (Python + MediaPipe) sends the scores here over localhost. No video reaches Godot.
# Condition A: no sensing. B: hidden sensing. C: open sensing (see it, correct it, switch it off).

const SCREEN = Vector2(1152, 648)
const TIME_LIMIT = 10.0
const NEUTRAL_LIMIT = 0.15   # placeholder: below this, a scene average counts as calm
const STARTLE_LIMIT = 0.25   # placeholder: peak score after the scare that counts as a reaction
const STATES = ["calm", "anxious", "scared"]
const TRACKER_PORT = 5005
const COMMAND_PORT = 5006

# Each scene has: text (by emotion), answers (by emotion, "t" = text, "s" = suspicion points),
# "next" (which scene comes next, by the emotion sensed while answering) and optionally "scare".
const SCENES = {
	"intro": {
		"text": {"neutral": "Where were you last night at nine?"},
		"answers": {"neutral": [
			{"t": "I was at home.", "s": 0},
			{"t": "I was at the library.", "s": 0},
			{"t": "Say nothing", "s": 1}]},
		"next": {"calm": "cold", "anxious": "door", "scared": "kind", "default": "door"},
	},
	"cold": {
		"text": {"neutral": "You are calm. Suspiciously calm. Innocent people sweat. Who paid you?"},
		"answers": {"neutral": [
			{"t": "Nobody paid me.", "s": 0},
			{"t": "You have the wrong person.", "s": 0},
			{"t": "Say nothing", "s": 1}]},
		"next": {"default": "door"},
	},
	"kind": {
		"text": {"neutral": "Easy. Breathe. You look frightened. Nobody here wants to hurt you. What did you see?"},
		"answers": {"neutral": [
			{"t": "I saw nothing.", "s": 1},
			{"t": "A man at the museum door.", "s": 0},
			{"t": "Say nothing", "s": 1}]},
		"next": {"default": "door"},
	},
	"door": {
		"text": {
			"neutral": "You keep looking at the door. Why?",
			"calm": "You are very calm now. You keep looking at the door anyway. Why?",
			"anxious": "You look tense, and you keep looking at the door. Why?",
			"scared": "You are terrified of that door. What is out there?"},
		"answers": {
			"neutral": [
				{"t": "I want to leave.", "s": 1},
				{"t": "Nothing. I'm fine.", "s": 0},
				{"t": "Say nothing", "s": 1}],
			"anxious": [
				{"t": "I'm nervous. I admit it.", "s": 0},
				{"t": "Nothing. I'm fine.", "s": 1},
				{"t": "Say nothing", "s": 1}],
			"scared": [
				{"t": "Please, I want to go home.", "s": 0},
				{"t": "I heard something outside.", "s": 0},
				{"t": "Say nothing", "s": 1}]},
		"scare": true,
		"next": {"default": "after"},
	},
	"after": {
		"text": {
			"neutral": "That clock has been loose for years. Now, back to you. What are you hiding?",
			"calm": "You did not even flinch. Either you are very brave, or you knew it would fall.",
			"anxious": "You flinched. That clock has hung there for twenty years. Why so jumpy?",
			"scared": "You are shaking. What are you so afraid of?"},
		"answers": {
			"neutral": [
				{"t": "Nothing.", "s": 1},
				{"t": "I'm not hiding anything.", "s": 0},
				{"t": "Say nothing", "s": 1}],
			"calm": [
				{"t": "It's only a clock.", "s": 0},
				{"t": "I've seen worse.", "s": 1},
				{"t": "Say nothing", "s": 1}],
			"anxious": [
				{"t": "It startled me, that's all.", "s": 0},
				{"t": "I hate loud noises.", "s": 0},
				{"t": "Say nothing", "s": 1}],
			"scared": [
				{"t": "I thought someone was here.", "s": 0},
				{"t": "I want this to be over.", "s": 0},
				{"t": "Say nothing", "s": 1}]},
		"next": {"scared": "offer", "default": "final"},
	},
	"offer": {
		"text": {"neutral": "I can help you. A deal. But I need the truth. Where is the painting?"},
		"answers": {"neutral": [
			{"t": "It's in the cellar.", "s": 0, "confess": true},
			{"t": "I don't know anything.", "s": 1},
			{"t": "Say nothing", "s": 1}]},
		"next": {"default": "end"},
	},
	"final": {
		"text": {
			"neutral": "Last question. Who are you protecting?",
			"calm": "Last question. You never flinch. Who are you protecting?",
			"anxious": "Last question. Your voice is unsteady. Who are you protecting?",
			"scared": "Last question. You are afraid of someone. Who?"},
		"answers": {
			"neutral": [
				{"t": "My brother.", "s": 0},
				{"t": "Nobody.", "s": 1},
				{"t": "Say nothing", "s": 1}],
			"calm": [
				{"t": "Nobody.", "s": 1},
				{"t": "My brother.", "s": 0},
				{"t": "Say nothing", "s": 1}],
			"scared": [
				{"t": "He will hurt my family.", "s": 0, "confess": true},
				{"t": "Nobody.", "s": 1},
				{"t": "Say nothing", "s": 1}]},
		"next": {"default": "end"},
	},
}

const MENU_TEXT = "You are being questioned about a stolen painting. Answer before the red bar runs out. Your answers, and in B and C your expression, change the story.\n\nIn B and C your webcam is used to estimate whether you look calm, anxious or scared. The video is processed live on this computer and is never shown, saved or sent anywhere. Only numbers are saved. The estimate is a rough guess and is often wrong.\n\nMid-game there is a sudden noise and a flash of light (a clock falls). In C you can see the estimate, correct it and switch sensing off. You can stop at any time (Esc)."

var condition = "C"
var sensing_on = true
var participant_id = "P01"
var phase = "menu"
var scene_id = "intro"
var next_scene_id = ""
var current_answers = []
var last_state = "neutral"
var override_state = ""
var timer_left = TIME_LIMIT
var suspicion = 0
var confessed = false
var mood_counts = {"calm": 0, "anxious": 0, "scared": 0}
var startle_state = "unknown"
var rows = PackedStringArray()

# Data from the tracker
var udp
var command_peer
var last_packet_ms = -100000
var tracker_sensing = false
var tracker_face = false
var tracker_calibrating = false
var tracker_calibrated = false
var raw_calm = 1.0
var raw_anxious = 0.0
var raw_scared = 0.0
var shown_calm = 1.0
var shown_anxious = 0.0
var shown_scared = 0.0

# Averages over the current scene
var frames_total = 0
var face_frames = 0
var sum_calm = 0.0
var sum_anxious = 0.0
var sum_scared = 0.0

# The scare (falling clock)
var clock_state = "wall"
var scare_t = 0.0
var scare_impact_done = false
var buildup = 0.0
var blackout = 0.0
var impact_flash = 0.0
var shake_strength = 0.0
var startle_total = 0
var startle_frames = 0
var startle_peak_scared = 0.0
var startle_peak_anxious = 0.0

# Look of the room
var time_total = 0.0
var fear_level = 0.0
var anx_level = 0.0
var calm_level = 0.0
var light_level = 1.0

var dialogue_label
var choice_row
var timer_bar
var footer_label
var sense_box
var estimate_label
var calm_bar
var anxious_bar
var scared_bar
var sense_switch
var menu_overlay
var menu_status
var menu_notice
var id_input
var consent_box
var fullscreen_button
var crash_player
var ending_overlay
var ending_title
var ending_text
var ending_summary


func _ready():
	RenderingServer.set_default_clear_color(Color.BLACK)
	var window = get_window()
	window.content_scale_size = Vector2i(1152, 648)
	window.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	window.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP

	udp = PacketPeerUDP.new()
	var error = udp.bind(TRACKER_PORT, "127.0.0.1")
	if error != OK:
		print("Could not listen on port %d (is another copy of the game running?)" % TRACKER_PORT)
	command_peer = PacketPeerUDP.new()
	command_peer.set_dest_address("127.0.0.1", COMMAND_PORT)

	crash_player = AudioStreamPlayer.new()
	crash_player.stream = make_noise(0.7, 0.45)
	add_child(crash_player)

	build_ui()
	show_menu()


# ---------- Interface ----------

func make_style(background, border, border_width):
	var style = StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(6)
	style.content_margin_left = 12
	style.content_margin_right = 12
	return style


func style_button(button, size = 22):
	var normal = make_style(Color(0.04, 0.03, 0.03, 0.9), Color(0.8, 0.8, 0.85, 0.7), 1)
	var hover = make_style(Color(0.15, 0.05, 0.05, 0.95), Color(0.91, 0.31, 0.23), 2)
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", hover)
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	button.add_theme_font_size_override("font_size", size)


func add_label(parent, text, size, colour, width = 952):
	var label = Label.new()
	label.text = text
	label.custom_minimum_size = Vector2(width, 0)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", size)
	label.modulate = colour
	parent.add_child(label)
	return label


func make_bar(parent, title, colour):
	add_label(parent, title, 14, Color(0.8, 0.8, 0.8), 350)
	var bar = ProgressBar.new()
	bar.custom_minimum_size = Vector2(350, 10)
	bar.min_value = 0.0
	bar.max_value = 100.0
	bar.show_percentage = false
	bar.add_theme_stylebox_override("background", make_style(Color(0.15, 0.1, 0.1), Color(0, 0, 0, 0), 0))
	bar.add_theme_stylebox_override("fill", make_style(colour, Color(0, 0, 0, 0), 0))
	parent.add_child(bar)
	return bar


func build_ui():
	var layer = CanvasLayer.new()
	add_child(layer)

	dialogue_label = RichTextLabel.new()
	dialogue_label.bbcode_enabled = true
	dialogue_label.scroll_active = false
	dialogue_label.position = Vector2(48, 404)
	dialogue_label.size = Vector2(1056, 72)
	dialogue_label.add_theme_font_size_override("normal_font_size", 26)
	dialogue_label.add_theme_font_size_override("bold_font_size", 26)
	layer.add_child(dialogue_label)

	choice_row = HBoxContainer.new()
	choice_row.position = Vector2(24, 504)
	choice_row.size = Vector2(1104, 64)
	choice_row.add_theme_constant_override("separation", 14)
	layer.add_child(choice_row)

	timer_bar = ProgressBar.new()
	timer_bar.position = Vector2(24, 588)
	timer_bar.size = Vector2(1104, 10)
	timer_bar.min_value = 0.0
	timer_bar.max_value = TIME_LIMIT
	timer_bar.value = TIME_LIMIT
	timer_bar.show_percentage = false
	timer_bar.add_theme_stylebox_override("background", make_style(Color(0.15, 0.1, 0.1), Color(0, 0, 0, 0), 0))
	timer_bar.add_theme_stylebox_override("fill", make_style(Color(0.91, 0.31, 0.23), Color(0, 0, 0, 0), 0))
	layer.add_child(timer_bar)

	footer_label = Label.new()
	footer_label.position = Vector2(24, 608)
	footer_label.size = Vector2(1104, 30)
	footer_label.add_theme_font_size_override("font_size", 16)
	footer_label.modulate = Color(1, 1, 1, 0.55)
	layer.add_child(footer_label)

	# Open-sensing panel (condition C only): shows what the game senses and lets the player correct it
	sense_box = VBoxContainer.new()
	sense_box.position = Vector2(780, 16)
	sense_box.custom_minimum_size = Vector2(350, 0)
	sense_box.add_theme_constant_override("separation", 6)
	layer.add_child(sense_box)
	add_label(sense_box, "THE GAME IS SENSING YOU", 16, Color(0.91, 0.31, 0.23), 350)
	estimate_label = add_label(sense_box, "", 18, Color(0.9, 0.9, 0.9), 350)
	calm_bar = make_bar(sense_box, "Calm", Color(0.4, 0.7, 1.0))
	anxious_bar = make_bar(sense_box, "Anxious", Color(1.0, 0.7, 0.2))
	scared_bar = make_bar(sense_box, "Scared", Color(1.0, 0.25, 0.2))
	add_label(sense_box, "Wrong? Tell the game how you feel:", 14, Color(0.8, 0.8, 0.8), 350)
	var correction_row = HBoxContainer.new()
	correction_row.add_theme_constant_override("separation", 6)
	sense_box.add_child(correction_row)
	for state in STATES:
		var button = Button.new()
		button.text = "I feel " + state
		style_button(button, 14)
		button.pressed.connect(set_override.bind(state))
		correction_row.add_child(button)
	sense_switch = CheckButton.new()
	sense_switch.text = "Sensing ON (untick to switch off)"
	sense_switch.button_pressed = true
	sense_switch.add_theme_font_size_override("font_size", 16)
	sense_switch.toggled.connect(on_sense_toggled)
	sense_box.add_child(sense_switch)
	sense_box.visible = false

	# Start menu
	menu_overlay = ColorRect.new()
	menu_overlay.color = Color(0, 0, 0, 0.93)
	menu_overlay.size = SCREEN
	layer.add_child(menu_overlay)
	var menu_box = VBoxContainer.new()
	menu_box.position = Vector2(100, 56)
	menu_box.custom_minimum_size = Vector2(952, 0)
	menu_box.add_theme_constant_override("separation", 8)
	menu_overlay.add_child(menu_box)
	add_label(menu_box, "INTERROGATION", 40, Color(0.91, 0.31, 0.23))
	add_label(menu_box, MENU_TEXT, 16, Color(0.9, 0.9, 0.9))
	consent_box = CheckBox.new()
	consent_box.text = "I have read this and agree to take part."
	consent_box.add_theme_font_size_override("font_size", 18)
	menu_box.add_child(consent_box)
	var id_row = HBoxContainer.new()
	menu_box.add_child(id_row)
	add_label(id_row, "Participant ID (no names):", 18, Color(0.9, 0.9, 0.9), 280)
	id_input = LineEdit.new()
	id_input.text = "P01"
	id_input.custom_minimum_size = Vector2(200, 0)
	id_row.add_child(id_input)
	menu_status = add_label(menu_box, "", 18, Color(1.0, 0.8, 0.4))
	menu_notice = add_label(menu_box, "", 20, Color(1.0, 0.3, 0.25))
	var calibrate_button = Button.new()
	calibrate_button.text = "Calibrate (look at the screen with a relaxed face for 3 seconds)"
	style_button(calibrate_button, 18)
	calibrate_button.pressed.connect(send_command.bind("calibrate"))
	menu_box.add_child(calibrate_button)
	var option_row = HBoxContainer.new()
	option_row.add_theme_constant_override("separation", 12)
	menu_box.add_child(option_row)
	var options = [["A", "A: buttons only"], ["B", "B: hidden sensing"], ["C", "C: open sensing"]]
	for option in options:
		var button = Button.new()
		button.text = option[1]
		button.custom_minimum_size = Vector2(300, 48)
		style_button(button, 20)
		button.pressed.connect(try_start.bind(option[0]))
		option_row.add_child(button)

	# Ending screen
	ending_overlay = ColorRect.new()
	ending_overlay.color = Color(0, 0, 0, 0.84)
	ending_overlay.size = SCREEN
	ending_overlay.visible = false
	layer.add_child(ending_overlay)
	var ending_box = VBoxContainer.new()
	ending_box.position = Vector2(120, 50)
	ending_box.custom_minimum_size = Vector2(912, 0)
	ending_box.add_theme_constant_override("separation", 14)
	ending_overlay.add_child(ending_box)
	add_label(ending_box, "ENDING", 16, Color(0.7, 0.7, 0.7), 912)
	ending_title = add_label(ending_box, "", 44, Color(0.91, 0.31, 0.23), 912)
	ending_text = add_label(ending_box, "", 26, Color(0.95, 0.95, 0.95), 912)
	ending_summary = add_label(ending_box, "", 17, Color(0.75, 0.85, 1.0), 912)
	var end_buttons = HBoxContainer.new()
	end_buttons.add_theme_constant_override("separation", 12)
	ending_box.add_child(end_buttons)
	var again_button = Button.new()
	again_button.text = "Play again"
	again_button.custom_minimum_size = Vector2(220, 52)
	style_button(again_button, 20)
	again_button.pressed.connect(play_again)
	end_buttons.add_child(again_button)
	var quit_button = Button.new()
	quit_button.text = "Quit"
	quit_button.custom_minimum_size = Vector2(160, 52)
	style_button(quit_button, 20)
	quit_button.pressed.connect(quit_game)
	end_buttons.add_child(quit_button)

	# Fullscreen button (on top of everything)
	fullscreen_button = Button.new()
	fullscreen_button.text = "Fullscreen (F)"
	fullscreen_button.focus_mode = Control.FOCUS_NONE
	fullscreen_button.position = Vector2(24, 12)
	style_button(fullscreen_button, 14)
	fullscreen_button.pressed.connect(toggle_fullscreen)
	layer.add_child(fullscreen_button)


func toggle_fullscreen():
	if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)


func quit_game():
	send_command("off")
	get_tree().quit()


func _unhandled_key_input(event):
	# F or F11 toggles fullscreen; Esc leaves fullscreen first, then quits.
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F or event.keycode == KEY_F11:
			toggle_fullscreen()
		elif event.keycode == KEY_ESCAPE:
			if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN:
				toggle_fullscreen()
			else:
				quit_game()


# ---------- Tracker ----------

func send_command(text):
	command_peer.put_packet(text.to_utf8_buffer())


func tracker_alive():
	return Time.get_ticks_msec() - last_packet_ms < 1500


func read_tracker():
	while udp.get_available_packet_count() > 0:
		var text = udp.get_packet().get_string_from_utf8()
		var data = JSON.parse_string(text)
		if typeof(data) == TYPE_DICTIONARY:
			last_packet_ms = Time.get_ticks_msec()
			tracker_sensing = data.get("sensing", false)
			tracker_face = data.get("face", false)
			tracker_calibrating = data.get("calibrating", false)
			tracker_calibrated = data.get("calibrated", false)
			raw_calm = float(data.get("calm", 1.0))
			raw_anxious = float(data.get("anxious", 0.0))
			raw_scared = float(data.get("scared", 0.0))


func classify(calm_score, anxious_score, scared_score, face_fraction):
	if face_fraction < 0.3:
		return "unknown"
	if maxf(anxious_score, scared_score) < NEUTRAL_LIMIT:
		return "calm"
	if scared_score > anxious_score:
		return "scared"
	return "anxious"


func sensing_active():
	return sensing_on and tracker_alive() and tracker_sensing and tracker_face


# ---------- Game flow ----------

func make_noise(duration, volume):
	# A short fading burst of noise used as the crash sound.
	var rate = 22050
	var count = int(duration * rate)
	var data = PackedByteArray()
	data.resize(count * 2)
	for i in count:
		var envelope = pow(1.0 - float(i) / count, 2.0)
		var sample = int(randf_range(-1.0, 1.0) * envelope * volume * 32767)
		data.encode_s16(i * 2, sample)
	var wav = AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = rate
	wav.stereo = false
	wav.data = data
	return wav


func pick(options, variant):
	# Use the version for this emotion if the scene has one, otherwise the neutral version.
	if options.has(variant):
		return options[variant]
	return options["neutral"]


func choose_next(scene, final_state):
	var options = scene["next"]
	if options.has(final_state):
		return options[final_state]
	return options["default"]


func show_menu():
	phase = "menu"
	menu_overlay.visible = true


func try_start(chosen):
	if not consent_box.button_pressed:
		menu_notice.text = "Tick the consent box first."
		return
	if chosen != "A" and not tracker_alive():
		menu_notice.text = "The tracker is not running. Start tracker.py first (B and C need it)."
		return
	if chosen != "A" and not tracker_calibrated:
		menu_notice.text = "Press Calibrate first and hold a relaxed face for 3 seconds."
		return
	menu_notice.text = ""
	start_game(chosen)


func start_game(chosen):
	condition = chosen
	sensing_on = condition != "A"
	participant_id = id_input.text.strip_edges()
	if participant_id == "":
		participant_id = "P00"
	send_command("on" if sensing_on else "off")   # in A the camera is not used at all
	scene_id = "intro"
	last_state = "neutral"
	suspicion = 0
	confessed = false
	mood_counts = {"calm": 0, "anxious": 0, "scared": 0}
	startle_state = "unknown"
	clock_state = "wall"
	rows = PackedStringArray()
	sense_switch.button_pressed = true
	sense_box.visible = condition == "C"
	menu_overlay.visible = false
	show_scene()


func clear_choices():
	for child in choice_row.get_children():
		child.queue_free()


func show_scene():
	var scene = SCENES[scene_id]
	var variant = "neutral"
	if sensing_on and STATES.has(last_state):
		variant = last_state
	dialogue_label.text = "[color=#e8503a][b]DETECTIVE:[/b][/color] " + pick(scene["text"], variant)
	dialogue_label.visible_ratio = 0.0
	current_answers = pick(scene["answers"], variant)
	clear_choices()
	override_state = ""
	frames_total = 0
	face_frames = 0
	sum_calm = 0.0
	sum_anxious = 0.0
	sum_scared = 0.0
	timer_left = TIME_LIMIT
	timer_bar.value = TIME_LIMIT
	footer_label.text = ""
	phase = "typing"


func begin_answering():
	for i in current_answers.size():
		var button = Button.new()
		button.text = current_answers[i]["t"]
		button.custom_minimum_size = Vector2(0, 64)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		style_button(button)
		button.pressed.connect(answer.bind(i, false))
		choice_row.add_child(button)
	timer_left = TIME_LIMIT
	phase = "answering"


func set_override(state):
	override_state = state


func on_sense_toggled(is_on):
	sensing_on = is_on
	send_command("on" if is_on else "off")
	if not is_on:
		last_state = "neutral"


func answer(index, timed_out):
	if phase != "answering":
		return
	phase = "answered"
	var scene = SCENES[scene_id]
	var chosen = current_answers[index]
	var seconds_taken = clampf(TIME_LIMIT - timer_left, 0.0, TIME_LIMIT)
	var avg_calm = 0.0
	var avg_anxious = 0.0
	var avg_scared = 0.0
	var face_fraction = 0.0
	if frames_total > 0:
		face_fraction = float(face_frames) / frames_total
	if face_frames > 0:
		avg_calm = sum_calm / face_frames
		avg_anxious = sum_anxious / face_frames
		avg_scared = sum_scared / face_frames
	var guess = ""
	if sensing_on:
		guess = classify(avg_calm, avg_anxious, avg_scared, face_fraction)
	var final_state = guess
	if override_state != "":
		final_state = override_state

	suspicion += chosen["s"]
	if chosen.get("confess", false):
		confessed = true
	if sensing_on:
		if STATES.has(final_state):
			last_state = final_state
			mood_counts[final_state] += 1
		else:
			last_state = "neutral"

	var answer_text = chosen["t"]
	if timed_out:
		answer_text = "(no answer: time ran out)"
	rows.append(",".join([condition, participant_id, scene_id, answer_text.replace(",", ";"),
		"%.2f" % seconds_taken, "%.3f" % avg_calm, "%.3f" % avg_anxious, "%.3f" % avg_scared,
		"%.2f" % face_fraction, guess, override_state, str(sensing_on)]))

	# The story branches on the emotion sensed while the player answered.
	next_scene_id = choose_next(scene, final_state if sensing_on else "")
	clear_choices()
	await get_tree().create_timer(0.6).timeout
	if scene.get("scare", false):
		start_scare()
	else:
		go_to_next()


func go_to_next():
	if next_scene_id == "end":
		show_end()
	else:
		scene_id = next_scene_id
		show_scene()


# ---------- The scare: a clock falls off the wall ----------

func start_scare():
	phase = "scare"
	scare_t = 0.0
	scare_impact_done = false
	startle_total = 0
	startle_frames = 0
	startle_peak_scared = 0.0
	startle_peak_anxious = 0.0
	override_state = ""
	dialogue_label.text = "..."
	dialogue_label.visible_ratio = 1.0
	timer_bar.value = 0.0
	clear_choices()


func scare_impact():
	scare_impact_done = true
	clock_state = "fallen"
	crash_player.play()
	impact_flash = 0.9
	shake_strength = 14.0


func update_scare(delta):
	scare_t += delta
	buildup = 0.0
	if scare_t < 1.55:
		buildup = clampf(scare_t / 1.2, 0.0, 1.0)
	if scare_t >= 1.2 and clock_state == "wall":
		clock_state = "falling"
	if scare_t >= 1.2 and scare_t < 1.55 and randf() < 0.5:
		light_level *= 0.3
	if scare_t >= 1.55 and not scare_impact_done:
		scare_impact()
	if scare_t >= 1.55 and scare_t < 2.15:
		blackout = 0.94
	elif scare_t >= 2.15 and scare_t < 2.5 and randf() < 0.4:
		blackout = 0.5
	else:
		blackout = 0.0
	# For two seconds after the crash, record the strongest reaction on the player's face.
	if scare_t >= 1.55 and scare_t <= 3.55:
		startle_total += 1
		if sensing_active():
			startle_frames += 1
			startle_peak_scared = maxf(startle_peak_scared, shown_scared)
			startle_peak_anxious = maxf(startle_peak_anxious, shown_anxious)
	if scare_t >= 4.0:
		finish_scare()


func finish_scare():
	var guess = "unknown"
	var face_fraction = 0.0
	if startle_total > 0:
		face_fraction = float(startle_frames) / startle_total
	if sensing_on and startle_frames > 0:
		if startle_peak_scared > STARTLE_LIMIT:
			guess = "scared"
		elif startle_peak_anxious > STARTLE_LIMIT:
			guess = "anxious"
		else:
			guess = "calm"
	var final_state = guess
	if override_state != "":
		final_state = override_state
	startle_state = final_state
	# The reaction to the scare decides how the detective speaks in the next scene.
	if sensing_on and STATES.has(final_state):
		last_state = final_state
	else:
		last_state = "neutral"
	rows.append(",".join([condition, participant_id, "scare", "clock_falls", "0", "",
		"%.3f" % startle_peak_anxious, "%.3f" % startle_peak_scared, "%.2f" % face_fraction,
		guess, override_state, str(sensing_on)]))
	go_to_next()


# ---------- Endings ----------

func choose_ending():
	var stressed = mood_counts["anxious"] + mood_counts["scared"]
	if confessed:
		return ["THE CONFESSION", "You told the truth. The detective switches off the lamp and sits down across from you. \"Thank you,\" he says quietly. \"That took courage.\" The red glow in his eyes fades. For the first time tonight, you can breathe."]
	if condition != "A" and mood_counts["calm"] >= 3 and suspicion >= 2:
		return ["IRON NERVES", "You never flinched. Not once. The detective stares at you for a long time. \"Nobody is that calm,\" he says, and locks the door. \"Nobody innocent.\""]
	if suspicion <= 1:
		return ["FREE TO GO", "The detective closes his notebook. \"You can go,\" he says. \"For now.\" The door opens. Behind you, the broken clock lies where it fell."]
	if condition != "A" and stressed >= 3:
		return ["THE LONG NIGHT", "Your hands will not stop shaking. \"Get some rest,\" the detective says, not unkindly. \"We will talk again in the morning.\" The lamp keeps swinging long after you leave."]
	return ["WE WILL CHECK YOUR STORY", "The detective writes something down and does not show you. \"We will check your story,\" he says. \"Wait here.\" The door clicks shut."]


func show_end():
	phase = "ended"
	send_command("off")   # camera released when the game is over
	sense_box.visible = false
	clear_choices()
	timer_bar.value = 0.0
	var ending = choose_ending()
	ending_title.text = ending[0]
	ending_text.text = ending[1]

	var rated = 0
	var agreed = 0
	for row in rows:
		var fields = row.split(",")
		if STATES.has(fields[9]):
			rated += 1
			if fields[10] == "" or fields[10] == fields[9]:
				agreed += 1
	var path = save_log()

	var summary = ""
	if condition == "A":
		summary = "This version did not use the camera. Only your answers changed the story."
	elif condition == "B":
		summary = "In this version the game read your face in secret and used it to change the story, the answers you were offered and the room."
	else:
		summary = "In this version the game showed you what it sensed and let you correct it."
	if condition != "A":
		summary += "\nYour expression was read as calm %d, anxious %d and scared %d times. Reaction to the falling clock: %s." % [mood_counts["calm"], mood_counts["anxious"], mood_counts["scared"], startle_state]
		if rated > 0:
			summary += "\nThe game's guess matched you %d of %d times (no correction counts as a match)." % [agreed, rated]
	summary += "\nLog saved to: " + path
	ending_summary.text = summary
	ending_overlay.visible = true


func play_again():
	get_tree().reload_current_scene()


func save_log():
	var path = "user://interrogation_log_%d.csv" % int(Time.get_unix_time_from_system())
	var file = FileAccess.open(path, FileAccess.WRITE)
	file.store_line("condition,participant,scene,answer,answer_time_s,calm,anxious,scared,face_fraction,game_guess,player_correction,sensing_on")
	for row in rows:
		file.store_line(row)
	file.close()
	return ProjectSettings.globalize_path(path)


# ---------- Per-frame updates ----------

func update_menu_status():
	if not tracker_alive():
		menu_status.text = "Tracker: NOT running. Start tracker.py (only needed for B and C)."
	elif tracker_calibrating:
		menu_status.text = "Calibrating... keep a relaxed face."
	elif tracker_calibrated:
		menu_status.text = "Tracker ready and calibrated." + ("" if tracker_face else " (No face seen right now.)")
	else:
		menu_status.text = "Tracker running. Press Calibrate."


func update_panel():
	if condition != "C":
		return
	if not sensing_on:
		estimate_label.text = "Sensing is OFF. The room and the detective no longer react to you."
	elif not tracker_alive():
		estimate_label.text = "Tracker not connected."
	elif not tracker_face:
		estimate_label.text = "I can't see your face."
	else:
		var state = classify(shown_calm, shown_anxious, shown_scared, 1.0)
		estimate_label.text = "The game thinks you feel: " + state.to_upper()
		if override_state != "":
			estimate_label.text += "\nYou said: " + override_state
	calm_bar.value = clampf(shown_calm * 100.0, 0.0, 100.0)
	anxious_bar.value = clampf(shown_anxious * 300.0, 0.0, 100.0)
	scared_bar.value = clampf(shown_scared * 300.0, 0.0, 100.0)


func update_look(delta):
	# Smooth the scores, then turn them into the look of the room.
	var target_calm = 1.0
	var target_anxious = 0.0
	var target_scared = 0.0
	if sensing_active():
		target_calm = raw_calm
		target_anxious = raw_anxious
		target_scared = raw_scared
	shown_calm = lerpf(shown_calm, target_calm, delta * 4.0)
	shown_anxious = lerpf(shown_anxious, target_anxious, delta * 4.0)
	shown_scared = lerpf(shown_scared, target_scared, delta * 4.0)

	var fear = 0.0
	var anxiety = 0.0
	var calmness = 0.0
	if sensing_on and phase != "menu":
		fear = clampf(shown_scared * 3.0, 0.0, 1.0)
		anxiety = clampf(shown_anxious * 3.0, 0.0, 1.0)
		calmness = clampf(shown_calm, 0.0, 1.0) * (1.0 - maxf(fear, anxiety))
	fear_level = fear
	anx_level = anxiety
	calm_level = calmness

	light_level = 1.0 - 0.4 * maxf(fear_level, anx_level)
	var flicker_chance = (fear_level * 0.8 + anx_level * 0.3) * 0.15
	if randf() < flicker_chance:
		light_level *= 0.35

	shake_strength = move_toward(shake_strength, 0.0, 30.0 * delta)
	impact_flash = move_toward(impact_flash, 0.0, 3.0 * delta)
	position = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * (fear_level * 4.0 + shake_strength)


func collect_samples():
	if (phase == "typing" or phase == "answering") and sensing_on and tracker_alive():
		frames_total += 1
		if tracker_face:
			face_frames += 1
			sum_calm += raw_calm
			sum_anxious += raw_anxious
			sum_scared += raw_scared


func _process(delta):
	time_total += delta
	read_tracker()
	update_look(delta)
	collect_samples()
	if phase == "menu":
		update_menu_status()
	elif phase == "typing":
		dialogue_label.visible_ratio += delta * 0.9
		if dialogue_label.visible_ratio >= 1.0:
			dialogue_label.visible_ratio = 1.0
			begin_answering()
	elif phase == "answering":
		timer_left -= delta
		timer_bar.value = maxf(timer_left, 0.0)
		update_panel()
		if timer_left <= 0.0:
			answer(2, true)
	elif phase == "scare":
		update_panel()
		update_scare(delta)
	queue_redraw()


# ---------- Drawing the room ----------

func draw_oval(center, rx, ry, colour):
	var points = PackedVector2Array()
	for i in 32:
		var angle = TAU * i / 32.0
		points.append(center + Vector2(cos(angle) * rx, sin(angle) * ry))
	draw_colored_polygon(points, colour)


func draw_clock():
	var clock_center = Vector2(290, 140)
	var clock_colour = Color(0.55, 0.38, 0.32, 0.7)
	var mark_colour = Color(0.3, 0.12, 0.12, 0.5)
	if clock_state == "wall":
		draw_arc(clock_center, 30, 0, TAU, 40, clock_colour, 3.0)
		var minute_angle = time_total * (0.3 + anx_level * 1.5 + fear_level * 2.5)
		draw_line(clock_center, clock_center + Vector2(sin(minute_angle), -cos(minute_angle)) * 24, Color(0.6, 0.45, 0.4, 0.8), 2.0)
		draw_line(clock_center, clock_center + Vector2(sin(minute_angle * 0.1), -cos(minute_angle * 0.1)) * 16, Color(0.6, 0.45, 0.4, 0.8), 3.0)
	elif clock_state == "falling":
		draw_arc(clock_center, 32, 0, TAU, 40, mark_colour, 2.0)
		var f = clampf((scare_t - 1.2) / 0.35, 0.0, 1.0)
		var fall_position = clock_center.lerp(Vector2(300, 468), f * f)
		draw_set_transform(fall_position, f * 3.0, Vector2.ONE)
		draw_arc(Vector2.ZERO, 30, 0, TAU, 40, clock_colour, 3.0)
		draw_line(Vector2.ZERO, Vector2(0, -22), clock_colour, 2.0)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	else:
		draw_arc(clock_center, 32, 0, TAU, 40, mark_colour, 2.0)
		var landed = Vector2(300, 468)
		draw_arc(landed, 30, 0.3, 4.2, 24, clock_colour, 3.0)
		draw_line(landed, landed + Vector2(30, 22), clock_colour, 2.0)
		draw_line(landed + Vector2(-30, -8), landed + Vector2(-45, 12), clock_colour, 2.0)
		draw_line(landed, landed + Vector2(-15, -23), clock_colour, 2.0)


func _draw():
	var darkness = maxf(fear_level * 0.5, anx_level * 0.3)
	var sway = sin(time_total * (1.5 + 4.0 * fear_level)) * (anx_level * 8.0 + fear_level * 22.0) + sin(time_total * 9.0) * buildup * 10.0
	var lamp_x = 560.0 + sway

	# Walls: warm red normally, cooler when calm, amber when anxious, deep red when scared
	var wall = Color(0.2, 0.07, 0.07)
	wall = wall.lerp(Color(0.1, 0.12, 0.2), calm_level * 0.5)
	wall = wall.lerp(Color(0.26, 0.15, 0.05), anx_level * 0.7)
	wall = wall.lerp(Color(0.38, 0.03, 0.03), fear_level * 0.8)
	wall = wall.lerp(Color(0.04, 0.01, 0.01), darkness)
	draw_rect(Rect2(Vector2.ZERO, SCREEN), wall)

	# Door
	draw_rect(Rect2(60, 190, 110, 230), Color(0.07, 0.04, 0.04))
	draw_rect(Rect2(60, 190, 110, 230), Color(0.35, 0.18, 0.15, 0.6), false, 3.0)
	draw_circle(Vector2(152, 310), 4, Color(0.5, 0.35, 0.25, 0.7))

	# Clock (falls during the scare)
	draw_clock()

	# Board
	draw_rect(Rect2(700, 110, 200, 150), Color(0.27, 0.13, 0.13))
	draw_rect(Rect2(700, 110, 200, 150), Color(0.4, 0.22, 0.2, 0.8), false, 3.0)
	for row_y in [160, 220]:
		for column_x in [745, 800, 855]:
			draw_circle(Vector2(column_x, row_y), 16, Color(0.08, 0.04, 0.04))

	# Desk
	draw_rect(Rect2(0, 410, 1152, 238), Color(0.1, 0.05, 0.05).lerp(Color(0.04, 0.02, 0.02), darkness))

	# Light cone (cooler and steadier when calm, harsher when scared)
	var lamp_colour = Color(1.0, 0.72, 0.45).lerp(Color(0.8, 0.88, 1.0), calm_level * 0.5)
	for k in 3:
		var spread = 190.0 + k * 45.0
		draw_colored_polygon(PackedVector2Array([Vector2(lamp_x, 152), Vector2(lamp_x - spread, 470), Vector2(lamp_x + spread, 470)]),
			Color(lamp_colour.r, lamp_colour.g, lamp_colour.b, 0.07 * light_level))

	# Detective silhouette
	var body = Color(0.05, 0.02, 0.02)
	draw_colored_polygon(PackedVector2Array([Vector2(430, 410), Vector2(465, 350), Vector2(525, 335), Vector2(595, 335), Vector2(655, 350), Vector2(690, 410)]), body)
	draw_oval(Vector2(560, 302), 36, 42, body)
	draw_colored_polygon(PackedVector2Array([Vector2(515, 262), Vector2(525, 220), Vector2(595, 220), Vector2(605, 262)]), body)
	draw_oval(Vector2(560, 262), 66, 10, body)

	# General dimming
	draw_rect(Rect2(Vector2.ZERO, SCREEN), Color(0, 0, 0, 0.22 + darkness * 0.35))

	# Lamp
	draw_line(Vector2(lamp_x, 0), Vector2(lamp_x, 118), Color(0.12, 0.06, 0.06), 3.0)
	draw_colored_polygon(PackedVector2Array([Vector2(lamp_x - 15, 118), Vector2(lamp_x + 15, 118), Vector2(lamp_x + 42, 150), Vector2(lamp_x - 42, 150)]), Color(0.14, 0.08, 0.08))
	draw_circle(Vector2(lamp_x, 154), 28, Color(lamp_colour.r, lamp_colour.g, lamp_colour.b, 0.12 * light_level))
	draw_circle(Vector2(lamp_x, 154), 10, Color(1.0, 0.88, 0.65, light_level))

	# Red eyes: glow with suspicion and with your fear
	var glow = clampf(0.4 + 0.12 * suspicion + 0.5 * fear_level, 0.0, 1.0) * (0.7 + 0.3 * sin(time_total * 3.0))
	draw_circle(Vector2(545, 303), 9, Color(1, 0.1, 0.1, glow * 0.25))
	draw_circle(Vector2(575, 303), 9, Color(1, 0.1, 0.1, glow * 0.25))
	draw_circle(Vector2(545, 303), 4.5, Color(1, 0.12, 0.1, glow))
	draw_circle(Vector2(575, 303), 4.5, Color(1, 0.12, 0.1, glow))

	# Red heartbeat pulse over the whole screen when scared
	if fear_level > 0.05:
		var pulse = 0.5 + 0.5 * sin(time_total * 6.0)
		draw_rect(Rect2(Vector2.ZERO, SCREEN), Color(0.6, 0.0, 0.0, fear_level * 0.18 * pulse))

	# Scare: blackout and the white flash at the moment of impact
	if blackout > 0.0:
		draw_rect(Rect2(Vector2.ZERO, SCREEN), Color(0, 0, 0, blackout))
	if impact_flash > 0.0:
		draw_rect(Rect2(Vector2.ZERO, SCREEN), Color(1, 1, 1, impact_flash * 0.6))
