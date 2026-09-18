extends Node
## مدير الصوت: مؤثرات + محرك + موسيقى. Autoload: AudioFX
## كل الأصوات مولّدة برمجياً (tools/gen_audio.py) وخفيفة على الموبايل.

const SFX := {
	"air_brake": "res://audio/air_brake.wav",
	"door_open": "res://audio/door_open.wav",
	"door_close": "res://audio/door_close.wav",
	"horn": "res://audio/horn.wav",
	"bell": "res://audio/bell.wav",
	"coin": "res://audio/coin.wav",
	"crash": "res://audio/crash.wav",
	"skid": "res://audio/skid.wav",
	"ui_click": "res://audio/ui_click.wav",
	"success": "res://audio/success.wav",
	"fail": "res://audio/fail.wav",
	"perfect": "res://audio/perfect.wav",
}

var _streams: Dictionary = {}
var _pool: Array[AudioStreamPlayer] = []
var _engine: AudioStreamPlayer
var _music: AudioStreamPlayer
var _ambience: AudioStreamPlayer
var _engine_target_pitch := 1.0
var _engine_target_vol := -80.0
var _last_play: Dictionary = {}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for k in SFX.keys():
		var s = load(SFX[k])
		if s:
			_streams[k] = s
	for i in range(8):
		var p := AudioStreamPlayer.new()
		p.bus = "Master"
		add_child(p)
		_pool.append(p)
	_engine = AudioStreamPlayer.new()
	_engine.stream = _make_loop("res://audio/engine_loop.wav")
	_engine.volume_db = -80
	add_child(_engine)
	_music = AudioStreamPlayer.new()
	_music.stream = _make_loop("res://audio/music_loop.wav")
	add_child(_music)
	_ambience = AudioStreamPlayer.new()
	_ambience.stream = _make_loop("res://audio/ambience_loop.wav")
	add_child(_ambience)
	GameState.settings_changed.connect(_apply_settings)
	_apply_settings()

func _make_loop(path: String) -> AudioStream:
	var s = load(path)
	if s is AudioStreamWAV:
		s.loop_mode = AudioStreamWAV.LOOP_FORWARD
		s.loop_begin = 0
		s.loop_end = s.data.size() / 2
	return s

func _apply_settings() -> void:
	var mv: float = float(GameState.settings.get("music", 0.5))
	_music.volume_db = linear_to_db(clampf(mv, 0.0001, 1.0)) - 6.0
	if mv <= 0.001:
		_music.volume_db = -80

func _process(delta: float) -> void:
	if _engine.playing:
		_engine.pitch_scale = lerpf(_engine.pitch_scale, _engine_target_pitch, delta * 6.0)
		_engine.volume_db = lerpf(_engine.volume_db, _engine_target_vol, delta * 8.0)

## تشغيل مؤثر صوتي مع حماية من التكرار السريع
func play(name: String, volume_db: float = 0.0, pitch: float = 1.0, min_interval: float = 0.05) -> void:
	if not _streams.has(name):
		return
	var now := Time.get_ticks_msec() / 1000.0
	if _last_play.has(name) and now - float(_last_play[name]) < min_interval:
		return
	_last_play[name] = now
	var sfx_vol: float = float(GameState.settings.get("sfx", 0.9))
	if sfx_vol <= 0.001:
		return
	for p in _pool:
		if not p.playing:
			p.stream = _streams[name]
			p.volume_db = volume_db + linear_to_db(sfx_vol)
			p.pitch_scale = pitch
			p.play()
			return
	# كل المشغلات مشغولة: استبدل الأقدم
	var p := _pool[0]
	p.stream = _streams[name]
	p.volume_db = volume_db + linear_to_db(sfx_vol)
	p.pitch_scale = pitch
	p.play()

## ---------------- المحرك
func engine_start() -> void:
	if not _engine.playing:
		_engine.play()
	_engine_target_vol = -14.0

func engine_stop() -> void:
	_engine_target_vol = -80.0

## rpm_ratio: 0 (خمول) .. 1 (أقصى سرعة) | throttle: 0..1
func engine_update(rpm_ratio: float, throttle: float) -> void:
	var sfx_vol: float = float(GameState.settings.get("sfx", 0.9))
	_engine_target_pitch = 0.75 + rpm_ratio * 1.35
	_engine_target_vol = linear_to_db(clampf(sfx_vol, 0.0001, 1.0)) - 16.0 + throttle * 6.0 + rpm_ratio * 3.0
	if sfx_vol <= 0.001:
		_engine_target_vol = -80

## ---------------- الموسيقى والجو
func music_start() -> void:
	if not _music.playing:
		_music.play()

func music_stop() -> void:
	_music.stop()

func ambience_start() -> void:
	_ambience.volume_db = -20
	if not _ambience.playing:
		_ambience.play()

func ambience_stop() -> void:
	_ambience.stop()
