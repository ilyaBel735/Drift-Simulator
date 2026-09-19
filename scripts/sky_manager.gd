class_name SkyManager
extends Node3D

@export_group("Sky")
@export var sky_top_color := Color(0.25, 0.45, 0.85)
@export var sky_horizon_color := Color(0.65, 0.78, 0.92)

@export_group("Clouds")
@export var cloud_color := Color(1.0, 1.0, 1.0)
@export var cloud_shadow_color := Color(0.72, 0.75, 0.80)
@export_range(0.0, 0.05) var cloud_speed := 0.05
@export_range(0.5, 5.0) var cloud_scale := 1.5
@export_range(0.2, 0.8) var cloud_coverage := 0.45
@export_range(0.05, 0.5) var cloud_softness := 0.2

@export_group("Performance")
# Меньше = быстрее, но отражения/освещение чуть грубее.
@export var radiance_size: int = Sky.RADIANCE_SIZE_128

var _sky_material: ShaderMaterial

func _ready() -> void:
	var env_node := _find_world_environment(self)
	if env_node == null or env_node.environment == null:
		push_warning("SkyManager: WorldEnvironment не найден.")
		return
	_setup_sky(env_node.environment)

func _find_world_environment(node: Node) -> WorldEnvironment:
	if node is WorldEnvironment:
		return node
	for child in node.get_children():
		var result := _find_world_environment(child)
		if result != null:
			return result
	return null

func _setup_sky(env: Environment) -> void:
	var shader := Shader.new()
	shader.code = SKY_SHADER

	_sky_material = ShaderMaterial.new()
	_sky_material.shader = shader
	_apply_params()

	var sky := Sky.new()
	sky.sky_material = _sky_material
	# REALTIME нужен, чтобы облака двигались.
	sky.process_mode = Sky.PROCESS_MODE_REALTIME
	# Понижаем разрешение карты отражений — заметно дешевле.
	sky.radiance_size = radiance_size

	env.background_mode = Environment.BG_SKY
	env.sky = sky

func _apply_params() -> void:
	if _sky_material == null:
		return
	_sky_material.set_shader_parameter("sky_top_color", sky_top_color)
	_sky_material.set_shader_parameter("sky_horizon_color", sky_horizon_color)
	_sky_material.set_shader_parameter("cloud_color", cloud_color)
	_sky_material.set_shader_parameter("cloud_shadow_color", cloud_shadow_color)
	_sky_material.set_shader_parameter("cloud_speed", cloud_speed)
	_sky_material.set_shader_parameter("cloud_scale", cloud_scale)
	_sky_material.set_shader_parameter("cloud_coverage", cloud_coverage)
	_sky_material.set_shader_parameter("cloud_softness", cloud_softness)

const SKY_SHADER = """
shader_type sky;

uniform vec3 sky_top_color : source_color = vec3(0.25, 0.45, 0.85);
uniform vec3 sky_horizon_color : source_color = vec3(0.65, 0.78, 0.92);
uniform vec3 cloud_color : source_color = vec3(1.0, 1.0, 1.0);
uniform vec3 cloud_shadow_color : source_color = vec3(0.72, 0.75, 0.80);
uniform float cloud_speed : hint_range(0.0, 0.05) = 0.008;
uniform float cloud_scale : hint_range(0.5, 5.0) = 1.5;
uniform float cloud_coverage : hint_range(0.2, 0.8) = 0.45;
uniform float cloud_softness : hint_range(0.05, 0.5) = 0.2;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
		mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x),
		u.y
	);
}

// 3 октавы вместо 5 — облака чуть проще, но сильно дешевле.
float fbm(vec2 p) {
	float value = 0.0;
	float amplitude = 0.5;
	float frequency = 1.0;
	for (int i = 0; i < 3; i++) {
		value += amplitude * noise(p * frequency);
		frequency *= 2.0;
		amplitude *= 0.5;
	}
	return value;
}

void sky() {
	vec3 dir = normalize(EYEDIR);

	float t = clamp(dir.y, 0.0, 1.0);
	vec3 sky = mix(sky_horizon_color, sky_top_color, pow(t, 0.6));

	if (dir.y > 0.01) {
		vec2 uv = dir.xz / (dir.y + 0.15);
		uv *= cloud_scale;
		uv += vec2(TIME * cloud_speed, TIME * cloud_speed * 0.3);

		float n = fbm(uv);
		float cloud = smoothstep(cloud_coverage, cloud_coverage + cloud_softness, n);

		float fade = smoothstep(0.01, 0.25, dir.y);
		cloud *= fade;

		vec3 cloud_col = mix(cloud_shadow_color, cloud_color, smoothstep(0.3, 0.7, n));

		sky = mix(sky, cloud_col, cloud * 0.85);
	}

	COLOR = sky;
}
"""
