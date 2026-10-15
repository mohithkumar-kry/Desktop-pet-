extends Node2D


var speed = 100.0
var change_every = 3.0          
var art_faces_left = true      
var ignore_time = 30.0          
var double_click_time = 0.3     
var gravity = 1500.0            
var drop_delay = 1.0           
var eat_loops_min = 8           
var eat_loops_max = 10

var follow_speed = 250.0        
var follow_stop = 80.0          
var throw_speed = 600.0         
var impact_speed = 700.0      
var bounce = 0.6               
var right_double_time = 0.4     
var bye_loops = 2              

var window_size = Vector2(200, 200)
var pos = Vector2.ZERO
var direction = Vector2(1, 0)
var change_timer = 0.0

var is_resting = false
var rest_timer = 0.0

var busy = false
var busy_timer = 0.0

var is_dragging = false
var drag_offset = Vector2.ZERO
var press_mouse = Vector2.ZERO
var click_pending = false
var click_timer = 0.0
var is_double = false
var drop_timer = 0.0
var last_raw = Vector2.ZERO
var drag_velocity = Vector2.ZERO

var is_thrown = false
var velocity = Vector2.ZERO
var impact_timer = 0.0
var impact_cooldown = 0.0

var following = false

var saying_bye = false
var bye_timer = 0.0
var last_right_click = -10.0

var air_anim = "drag"       
var ignored_timer = 0.0

@onready var sprite = $AnimatedSprite2D
@onready var area = $Area2D

func _ready():
	window_size = Vector2(DisplayServer.window_get_size())
	pos = Vector2(DisplayServer.window_get_position())

	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP, true)

	area.input_event.connect(_on_area_input)
	area.mouse_entered.connect(_on_attention) 

	pick_new_direction()


func _on_attention():
	ignored_timer = 0.0


func _physics_process(delta):
	var b = get_bounds()


	impact_cooldown -= delta
	if impact_timer > 0:
		impact_timer -= delta
		if impact_timer <= 0 and (is_dragging or is_thrown):
			sprite.play(air_anim) 

	if saying_bye:
		bye_timer -= delta
		if bye_timer <= 0:
			get_tree().quit()
		return

	if is_dragging:
		var raw = Vector2(DisplayServer.mouse_get_position()) - drag_offset
		drag_velocity = drag_velocity.lerp((raw - last_raw) / delta, 0.5)
		last_raw = raw


		if (raw.x < b.position.x and drag_velocity.x < -impact_speed) \
		or (raw.x > b.end.x and drag_velocity.x > impact_speed) \
		or (raw.y < b.position.y and drag_velocity.y < -impact_speed) \
		or (raw.y > b.end.y and drag_velocity.y > impact_speed):
			do_impact()

		pos.x = clamp(raw.x, b.position.x, b.end.x)
		pos.y = clamp(raw.y, b.position.y, b.end.y)
		apply_pos()
		return

	if is_thrown:
		velocity.y += gravity * delta
		pos += velocity * delta
		var impact = 0.0
		if pos.x <= b.position.x and velocity.x < 0:
			pos.x = b.position.x
			impact = max(impact, -velocity.x)
			velocity.x *= -bounce
		elif pos.x >= b.end.x and velocity.x > 0:
			pos.x = b.end.x
			impact = max(impact, velocity.x)
			velocity.x *= -bounce
		if pos.y <= b.position.y and velocity.y < 0:
			pos.y = b.position.y
			impact = max(impact, -velocity.y)
			velocity.y *= -bounce
		elif pos.y >= b.end.y and velocity.y > 0:
			pos.y = b.end.y
			impact = max(impact, velocity.y)
			velocity.y *= -bounce
			velocity.x *= 0.85       
		if impact >= impact_speed:
			do_impact()


		if pos.y >= b.end.y - 1 and abs(velocity.y) < 60 and abs(velocity.x) < 40:
			is_thrown = false
			velocity = Vector2.ZERO
			drop_timer = drop_delay
		apply_pos()
		return

	if drop_timer > 0:
		drop_timer -= delta
		if drop_timer <= 0:
			pick_new_direction()
		return

	if following:
		ignored_timer = 0.0
		var target = Vector2(DisplayServer.mouse_get_position()) - window_size / 2.0
		var to_target = target - pos
		if to_target.length() > follow_stop:
			direction = to_target.normalized()
			pos += direction * follow_speed * delta
			pos.x = clamp(pos.x, b.position.x, b.end.x)
			pos.y = clamp(pos.y, b.position.y, b.end.y)
			apply_pos()
			update_animation()
		else:
			sprite.pause()         
		return

	if click_pending:
		click_timer -= delta
		if click_timer <= 0:
			click_pending = false
			play_timed("eat", eat_loops_min, eat_loops_max)  
		return

	if busy:
		busy_timer -= delta
		if busy_timer <= 0:
			busy = false
			pick_new_direction()     
		return


	if is_resting:
		rest_timer -= delta
		if rest_timer <= 0:
			is_resting = false
			pick_new_direction()
		return


	ignored_timer += delta
	if ignored_timer >= ignore_time:
		ignored_timer = 0.0
		play_timed("hump", 6, 7)
		if busy:
			return

	
	change_timer += delta
	if change_timer >= change_every:
		pick_new_direction()
		maybe_idle(0.2)
		if busy or is_resting:
			return

	pos += direction * speed * delta


	pos.x = clamp(pos.x, b.position.x, b.end.x)
	pos.y = clamp(pos.y, b.position.y, b.end.y)

	
	var bounced = false
	if (pos.x <= b.position.x and direction.x < 0) or (pos.x >= b.end.x and direction.x > 0):
		direction.x *= -1
		bounced = true
	if (pos.y <= b.position.y and direction.y < 0) or (pos.y >= b.end.y and direction.y > 0):
		direction.y *= -1
		bounced = true
	if bounced:
		maybe_idle(0.3)
		if busy or is_resting:
			return

	apply_pos()
	update_animation()


func apply_pos():
	DisplayServer.window_set_position(Vector2i(pos))


func get_bounds() -> Rect2:
	# usable rect = screen minus the taskbar
	var r = DisplayServer.screen_get_usable_rect()
	return Rect2(Vector2(r.position), Vector2(r.size) - window_size)

func pick_new_direction():
	var options = [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]
	direction = options.pick_random()
	change_timer = 0.0

func update_animation():
	if abs(direction.x) >= abs(direction.y):
		sprite.play("walk_side")
		sprite.flip_h = (direction.x > 0) if art_faces_left else (direction.x < 0)
	elif direction.y < 0:
		sprite.flip_h = false
		sprite.play("walk_up")
	else:
		sprite.flip_h = false
		sprite.play("walk_down")

func has_anim(anim) -> bool:
	if sprite.sprite_frames.has_animation(anim):
		return true
	push_warning("No '" + anim + "' animation found. Check the name in SpriteFrames.")
	return false

func anim_length(anim) -> float:
	var total = 0.0
	for i in sprite.sprite_frames.get_frame_count(anim):
		total += sprite.sprite_frames.get_frame_duration(anim, i)
	return total / max(sprite.sprite_frames.get_animation_speed(anim), 0.01)


func maybe_idle(chance = 0.3):
	if randf() >= chance:
		return
	if randf() < 0.6:
		start_sleep()
	else:
		play_timed("eat", eat_loops_min, eat_loops_max)


func start_sleep():
	var anim = "sleep"
	if not has_anim(anim):
		return
	sprite.sprite_frames.set_animation_loop(anim, true)
	is_resting = true
	rest_timer = randi_range(6, 7) * anim_length(anim)
	sprite.flip_h = false
	sprite.play(anim)

func play_timed(anim, min_loops = 6, max_loops = 7):
	if not has_anim(anim):
		return
	sprite.sprite_frames.set_animation_loop(anim, true)   # the timer ends it, not Loop
	busy = true
	is_resting = false
	busy_timer = randi_range(min_loops, max_loops) * anim_length(anim)
	sprite.flip_h = false
	sprite.play(anim)


func do_impact():
	if impact_cooldown > 0:
		return
	impact_cooldown = 0.6
	if not has_anim("boom"):
		return
	sprite.sprite_frames.set_animation_loop("boom", false)
	impact_timer = anim_length("boom")
	sprite.flip_h = false
	sprite.play("boom")


func start_bye():
	saying_bye = true
	is_dragging = false
	is_thrown = false
	following = false
	busy = false
	is_resting = false
	click_pending = false
	sprite.flip_h = false
	if has_anim("bye"):
		sprite.sprite_frames.set_animation_loop("bye", true)
		bye_timer = bye_loops * anim_length("bye")
		sprite.play("bye")
	else:
		bye_timer = 0.0          # no bye animation, just close


func start_fall():
	is_thrown = true
	is_resting = false
	busy = false
	velocity = Vector2(randf_range(-150.0, 150.0), 0.0)
	sprite.flip_h = false
	if sprite.sprite_frames.has_animation("fall"):
		air_anim = "fall"
	else:
		air_anim = "walk_down"
	sprite.play(air_anim)


func _on_area_input(_viewport, event, _shape_idx):
	if not (event is InputEventMouseButton and event.pressed):
		return

	if saying_bye:
		return

	if event.button_index == MOUSE_BUTTON_RIGHT:
		var now = Time.get_ticks_msec() / 1000.0
		if now - last_right_click <= right_double_time:
			start_bye()
			return
		last_right_click = now
		following = not following
		is_resting = false
		busy = false
		click_pending = false
		drop_timer = 0.0
		ignored_timer = 0.0
		if not following:
			pick_new_direction()
		return


	if event.button_index == MOUSE_BUTTON_LEFT:
		is_double = click_pending      # second click arrived in time
		click_pending = false
		following = false
		is_dragging = true
		is_thrown = false
		velocity = Vector2.ZERO
		is_resting = false
		busy = false
		drop_timer = 0.0
		ignored_timer = 0.0
		press_mouse = Vector2(DisplayServer.mouse_get_position())
		drag_offset = press_mouse - Vector2(DisplayServer.window_get_position())
		last_raw = press_mouse - drag_offset
		drag_velocity = Vector2.ZERO
		sprite.flip_h = false
		sprite.play("drag")


func _input(event):

	if is_dragging and event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		is_dragging = false
		var moved = Vector2(DisplayServer.mouse_get_position()).distance_to(press_mouse)
		if moved >= 5:
			if drag_velocity.length() >= throw_speed:
				is_thrown = true                           # swung it: fly and bounce
				air_anim = "drag"
				velocity = drag_velocity.limit_length(3000.0)
			else:
				drop_timer = drop_delay                    # slow drag: pause, then walk
		elif is_double:
			start_fall()                                   # double click
		else:
			click_pending = true                           # wait to see if a 2nd click follows
			click_timer = double_click_time
		is_double = false

	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		get_tree().quit()
