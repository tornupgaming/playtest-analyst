extends SceneTree
## Smoke test, run through tools/check.sh. Builds the level with each tuning
## profile, runs two seconds of physics with the player standing at the spawn,
## and prints one summary line per profile.

const LEVEL := "res://level/level.tscn"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	for profile in ["clean", "planted"]:
		var level := (load(LEVEL) as PackedScene).instantiate() as Node3D
		level.set(&"tuning", load("res://eval/tuning_%s.tres" % profile))
		root.add_child(level)
		for i in 240:
			await physics_frame
		var player := level.get_node("Player") as Player
		var zones: Array[String] = []
		for node in level.get_node("Built").get_children():
			if node.name.begins_with("Zone_"):
				zones.append(node.name.trim_prefix("Zone_"))
		print("%s: %d built nodes, zones %s, player %s on floor: %s" % [
				profile, level.get_node("Built").get_child_count(), ",".join(zones),
				player.global_position.snappedf(0.01), player.is_on_floor()])
		level.free()
	quit()
