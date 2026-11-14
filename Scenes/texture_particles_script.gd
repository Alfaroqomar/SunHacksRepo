extends GPUParticles2D

const COLUMNS = 4
const ROWS = 3  # 3rd row empty, but sheet is still 4x3

func _ready() -> void:
	# Tell the renderer about the spritesheet grid
	var canvas_mat = CanvasItemMaterial.new()
	canvas_mat.particles_animation = true
	canvas_mat.particles_anim_h_frames = COLUMNS
	canvas_mat.particles_anim_v_frames = ROWS
	canvas_mat.particles_anim_loop = false
	material = canvas_mat

	set_particle_frame(0)  # pick whichever frame you want

func set_particle_frame(frame_index: int) -> void:
	# frame_index 0-7 are valid (rows 1 and 2 only, row 3 is empty)
	var total_frames = COLUMNS * ROWS  # 12 total slots
	var normalized = float(frame_index) / float(total_frames)

	var proc_mat = process_material as ParticleProcessMaterial
	proc_mat.anim_speed_min = 0.0  # freeze, don't animate
	proc_mat.anim_speed_max = 0.0
	proc_mat.anim_offset_min = normalized
	proc_mat.anim_offset_max = normalized
