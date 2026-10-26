class_name InfectedAnimals
extends RefCounted
## Turned dogs and wolves (docs/survival_nature.md; call 102): a Wildlife record with "infected" on.
## Fast (run: quicker than a man's sprint, MAN_SPRINT_MPS), low (height_m: harder to see and to
## hit: its hit box is that low), and hard to hear (heard_m: its feet carry a few metres where a
## walking man's carry Survival.STEP_M's 6). It runs down the nearest living within SEE_M (night
## NIGHT_SEE_M), any hour, bites every BITE_S in reach (the species' infected "bite" as trauma and an
## "animal_bite" mark with infected on: the body lane's infection reads it), and never flees. It
## doesn't care for the dead and they don't care for it. What turns them stays ARCHE's mystery.
## A bitten dog of yours (dogs as companions are call 94, later): bite_companion_dog's flag on its
## record is the hard choice that lane will read. Numbers in data/survival_fauna.json "infected".

const MAN_SPRINT_MPS := 6.0
const SEE_M := 35.0
const NIGHT_SEE_M := 25.0
const BITE_M := 1.4
const BITE_S := 1.2


static func row(sp: String) -> Dictionary:
	return (Nature.fauna().get("infected", {}) as Dictionary).get(sp, {})


static func can_turn(sp: String) -> bool:
	return not row(sp).is_empty()


static func speed(sp: String) -> float:
	return float(row(sp).get("run", 9.0))


static func height_m(sp: String) -> float:
	return float(row(sp).get("height_m", 0.5))


static func heard_m(sp: String) -> float:
	return float(row(sp).get("heard_m", 3.0))


static func bite(sp: String) -> float:
	return float(row(sp).get("bite", 10.0))


static func chance(sp: String) -> float:
	return float(row(sp).get("chance", 0.0))


## `a` turns (a dog or a wolf; anything else stays as it is). Returns whether.
static func turn(a: Dictionary) -> bool:
	if not can_turn(String(a.sp)):
		return false
	a["infected"] = true
	a.state = "idle"
	a.erase("prey")
	return true


static func step(level: Node, a: Dictionary, dt: float, ctx: Dictionary) -> void:
	var now := Soldier._now()
	var reach := lerpf(SEE_M, NIGHT_SEE_M, clampf(float(ctx.get("dark", 0.0)), 0.0, 1.0))
	var row_l := Wildlife.nearest_living(ctx, a.pos, reach, false)
	if row_l.is_empty():
		if String(a.state) == "hunt":
			a.state = "idle"
			a.home = a.pos
			a.wait = 1.0
		Wildlife._wander(a, dt)
		return
	a.state = "hunt"
	a["prey"] = row_l.s
	a.target = row_l.p
	if (row_l.p as Vector2).distance_to(a.pos) <= BITE_M and now >= float(a.get("bite_at", 0.0)):
		a["bite_at"] = now + BITE_S
		Predators.bite(level, a, row_l.s)


## The companion dog's bite (call 94's stub): its record carries when it was bitten.
static func bite_companion_dog(rec: Dictionary) -> void:
	rec["infected_bite_h"] = Moods.now_h()
