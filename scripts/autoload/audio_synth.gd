extends Node
## Procedural sound effects (autoload "AudioSynth").
## Every sound in the game is synthesized at startup into an AudioStreamWAV, so the
## project ships without any third-party audio files. Sounds are short and cheap to
## generate (about 100 ms of CPU on a phone).

const RATE := 22050
const POOL_SIZE := 8

var sounds: Dictionary = {}
var _pool: Array[AudioStreamPlayer] = []
var _engine: AudioStreamPlayer
var _engine_target_volume := -80.0


func _ready() -> void:
	sounds["click"] = _make_click()
	sounds["horn"] = _make_horn()
	sounds["door"] = _make_door_chime()
	sounds["hit"] = _make_hit()
	sounds["coin"] = _make_coin()
	sounds["success"] = _make_success()
	sounds["fail"] = _make_fail()
	sounds["ding"] = _make_ding()
	sounds["engine"] = _make_engine_loop()
	for i in POOL_SIZE:
		var p := AudioStreamPlayer.new()
		p.bus = "Master"
		add_child(p)
		_pool.append(p)
	_engine = AudioStreamPlayer.new()
	_engine.stream = sounds["engine"]
	_engine.volume_db = -80.0
	add_child(_engine)


## Plays a named one-shot sound.
func play(sound_name: String, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	if not GameState.settings.sound:
		return
	if not sounds.has(sound_name):
		return
	var player: AudioStreamPlayer = null
	for p in _pool:
		if not p.playing:
			player = p
			break
	if player == null:
		player = _pool[0]
	player.stream = sounds[sound_name]
	player.volume_db = volume_db
	player.pitch_scale = pitch
	player.play()


## Drives the looping engine sound. rpm in 0..1, load in 0..1.
func set_engine(rpm: float, load: float, running: bool) -> void:
	if not running or not GameState.settings.sound:
		if _engine.playing:
			_engine.stop()
		return
	if not _engine.playing:
		_engine.play()
	_engine.pitch_scale = lerpf(0.75, 1.9, clampf(rpm, 0.0, 1.0))
	_engine_target_volume = linear_to_db(lerpf(0.18, 0.55, clampf(load, 0.0, 1.0)))
	_engine.volume_db = lerpf(_engine.volume_db, _engine_target_volume, 0.15)


func stop_engine() -> void:
	if _engine.playing:
		_engine.stop()


# ---------------------------------------------------------------- synthesis helpers
func _wav_from_samples(samples: PackedFloat32Array, loop: bool = false) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in samples.size():
		var v := int(clampf(samples[i], -1.0, 1.0) * 32767.0)
		bytes.encode_s16(i * 2, v)
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.stereo = false
	wav.data = bytes
	if loop:
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = samples.size()
	return wav


func _env(t: float, attack: float, release: float, length: float) -> float:
	var a := clampf(t / maxf(attack, 0.0001), 0.0, 1.0)
	var r := clampf((length - t) / maxf(release, 0.0001), 0.0, 1.0)
	return a * r


func _make_click() -> AudioStreamWAV:
	var length := 0.05
	var n := int(RATE * length)
	var s := PackedFloat32Array()
	s.resize(n)
	for i in n:
		var t := float(i) / RATE
		s[i] = sin(TAU * 1400.0 * t) * exp(-t * 90.0) * 0.6
	return _wav_from_samples(s)


func _make_horn() -> AudioStreamWAV:
	var length := 0.8
	var n := int(RATE * length)
	var s := PackedFloat32Array()
	s.resize(n)
	for i in n:
		var t := float(i) / RATE
		var v := 0.0
		# Two slightly detuned tones with odd harmonics give the classic bus horn timbre.
		for f in [392.0, 494.0]:
			v += sin(TAU * f * t) * 0.5
			v += sin(TAU * f * 3.0 * t) * 0.12
			v += sin(TAU * f * 5.0 * t) * 0.05
		s[i] = v * 0.5 * _env(t, 0.03, 0.12, length)
	return _wav_from_samples(s)


func _make_door_chime() -> AudioStreamWAV:
	var length := 0.5
	var n := int(RATE * length)
	var s := PackedFloat32Array()
	s.resize(n)
	for i in n:
		var t := float(i) / RATE
		var v := 0.0
		if t < 0.25:
			v = sin(TAU * 1046.0 * t) * exp(-t * 9.0)
		else:
			var t2 := t - 0.25
			v = sin(TAU * 1318.0 * t2) * exp(-t2 * 8.0)
		s[i] = v * 0.5
	return _wav_from_samples(s)


func _make_hit() -> AudioStreamWAV:
	var length := 0.4
	var n := int(RATE * length)
	var s := PackedFloat32Array()
	s.resize(n)
	var filtered := 0.0
	for i in n:
		var t := float(i) / RATE
		var noise := randf_range(-1.0, 1.0)
		filtered += (noise - filtered) * 0.18
		var thump := sin(TAU * 70.0 * t) * exp(-t * 14.0)
		s[i] = (filtered * exp(-t * 9.0) * 0.9 + thump * 0.8) * 0.8
	return _wav_from_samples(s)


func _make_coin() -> AudioStreamWAV:
	var length := 0.3
	var n := int(RATE * length)
	var s := PackedFloat32Array()
	s.resize(n)
	for i in n:
		var t := float(i) / RATE
		var f := 988.0 if t < 0.08 else 1319.0
		var t2 := t if t < 0.08 else t - 0.08
		s[i] = sin(TAU * f * t2) * exp(-t2 * 7.0) * 0.5
	return _wav_from_samples(s)


func _make_success() -> AudioStreamWAV:
	var notes := [523.25, 659.25, 783.99, 1046.5]
	var step := 0.13
	var length := step * 3.0 + 0.6
	var n := int(RATE * length)
	var s := PackedFloat32Array()
	s.resize(n)
	for i in n:
		var t := float(i) / RATE
		var idx := mini(int(t / step), 3)
		var t2 := t - idx * step
		var decay := 4.0 if idx == 3 else 12.0
		var f: float = notes[idx]
		s[i] = (sin(TAU * f * t2) + 0.3 * sin(TAU * f * 2.0 * t2)) * exp(-t2 * decay) * 0.45
	return _wav_from_samples(s)


func _make_fail() -> AudioStreamWAV:
	var length := 0.7
	var n := int(RATE * length)
	var s := PackedFloat32Array()
	s.resize(n)
	var phase := 0.0
	for i in n:
		var t := float(i) / RATE
		var f := lerpf(380.0, 160.0, t / length)
		phase += TAU * f / RATE
		var saw := 2.0 * fposmod(phase / TAU, 1.0) - 1.0
		s[i] = saw * 0.35 * _env(t, 0.02, 0.2, length)
	return _wav_from_samples(s)


func _make_ding() -> AudioStreamWAV:
	var length := 0.45
	var n := int(RATE * length)
	var s := PackedFloat32Array()
	s.resize(n)
	for i in n:
		var t := float(i) / RATE
		s[i] = (sin(TAU * 1760.0 * t) + 0.4 * sin(TAU * 3520.0 * t)) * exp(-t * 8.0) * 0.4
	return _wav_from_samples(s)


func _make_engine_loop() -> AudioStreamWAV:
	# One second loop; every frequency is an integer so the loop is seamless.
	var length := 1.0
	var n := int(RATE * length)
	var s := PackedFloat32Array()
	s.resize(n)
	var filtered := 0.0
	for i in n:
		var t := float(i) / RATE
		var v := sin(TAU * 58.0 * t) * 0.5
		v += sin(TAU * 116.0 * t) * 0.25
		v += sin(TAU * 174.0 * t) * 0.12
		v += sin(TAU * 232.0 * t) * 0.06
		var noise := randf_range(-1.0, 1.0)
		filtered += (noise - filtered) * 0.05
		v += filtered * 0.35
		v *= 1.0 + 0.12 * sin(TAU * 14.0 * t)
		s[i] = v * 0.8
	return _wav_from_samples(s, true)
