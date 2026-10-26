extends SceneTree
## Smoke test, run through tools/check.sh. Builds the level with each tuning
## profile, runs two seconds of physics with the player standing at the spawn,
## and prints one summary line per profile. Also prints a "z-fight:" line for
## each pair of blocks with overlapping faces on the same plane, facing the
## same way: they flicker in game.

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
		for line in _coplanar_faces(level.get_node("Built")):
			print("z-fight: %s: %s" % [profile, line])
		level.free()
	quit()


func _coplanar_faces(built: Node) -> Array[String]:
	var boxes: Array[AABB] = []
	for mesh: MeshInstance3D in built.find_children("*", "MeshInstance3D", true, false):
		if mesh.mesh is BoxMesh:
			var size := (mesh.mesh as BoxMesh).size
			boxes.append(AABB(mesh.global_position - size / 2.0, size))
	var found: Array[String] = []
	for i in boxes.size():
		for j in range(i + 1, boxes.size()):
			var a := boxes[i]
			var b := boxes[j]
			for axis in 3:
				var u := (axis + 1) % 3
				var v := (axis + 2) % 3
				var overlap_u := minf(a.end[u], b.end[u]) - maxf(a.position[u], b.position[u])
				var overlap_v := minf(a.end[v], b.end[v]) - maxf(a.position[v], b.position[v])
				if overlap_u < 0.01 or overlap_v < 0.01:
					continue
				for face in [a.position[axis], a.end[axis]]:
					var same_low := is_equal_approx(face, a.position[axis]) and is_equal_approx(face, b.position[axis])
					var same_high := is_equal_approx(face, a.end[axis]) and is_equal_approx(face, b.end[axis])
					if same_low or same_high:
						found.append("%s and %s share the %s%s face at %s" % [
								_corners(a), _corners(b), "-" if same_low else "+", "xyz"[axis], face])
	return found


func _corners(box: AABB) -> String:
	return "(%s)-(%s)" % [box.position.snappedf(0.01), box.end.snappedf(0.01)]
