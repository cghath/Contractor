extends Node
## Headless checks for the company's income beyond contracts (claude/income, docs/income.md):
## the high command squads' side jobs, captures and bounties, FOB businesses and the black market.
## Pure campaign logic on the autoloads (no level), so it runs in seconds.
##   <voxel godot exe> --headless --path . res://tests/income_test.tscn
## Exits with the number of failures.

var failures := 0


func _ready() -> void:
	var tag := OS.get_environment("CONTRACTOR_TEST_TAG")
	GameState.zone_id = "test_income" + tag  # never touch a real save
	Campaign.campaign_id = "test_income_campaign" + tag
	GameState.delete_save()
	Campaign.reset_campaign()
	get_tree().create_timer(120.0).timeout.connect(func() -> void:
		print("INCOME TEST FAILED (timed out)")
		get_tree().quit(99))
	await get_tree().process_frame
	_new_campaign()
	_test_side_jobs()
	Campaign.reset_campaign()
	print("INCOME TEST %s (%d failures)" % ["PASSED" if failures == 0 else "FAILED", failures])
	get_tree().quit(failures)


func check(condition: bool, what: String) -> void:
	print("  [%s] %s" % ["ok" if condition else "FAIL", what])
	if not condition:
		failures += 1


func _new_campaign() -> void:
	Campaign.reset_campaign()
	Contracts.new_full_campaign(4242, 200000)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	Heroes.seed_standing(Campaign.section(&"roster"), Economy.day(), rng)


func _roster() -> Dictionary:
	return Campaign.section(&"roster")


func _test_side_jobs() -> void:
	print("High command side jobs (SideJobs)")
	SideJobs.refresh_offers(Economy.day())
	var s := Income.state()
	check((s.offers as Array).size() == int(SideJobs.c("board_size", 3)), "the board carries %d side job offers" % int(SideJobs.c("board_size", 3)))
	var o: Dictionary = s.offers[0]
	check(int(o.pay) > 0 and float(o.danger) > 0.0 and String(o.from) != "", "an offer has pay, danger and who offers it (%s, %s, $%d)" % [o.kind, o.from, o.pay])
	var k := SideJobs.kind(String(o.kind))
	check(SideJobs.pay_for(k, String(o.client), 1.0, 0.9) > SideJobs.pay_for(k, String(o.client), 1.0, 0.2), "pay scales with the zone's danger")
	var q_good := SideJobs.odds(k, 0.5, 0.85)
	var q_poor := SideJobs.odds(k, 0.5, 0.35)
	check(float(q_good.trouble) < float(q_poor.trouble), "a better squad gets into trouble less often (%.2f vs %.2f)" % [q_good.trouble, q_poor.trouble])
	check(float(SideJobs.odds(k, 0.9, 0.6).trouble) > float(SideJobs.odds(k, 0.2, 0.6).trouble), "a more dangerous zone means more trouble")
	var q := SideJobs.quality(_roster(), "d02")
	check(float(q.quality) > 0.2 and float(q.quality) < 0.95 and int(q.ready) == 4, "Hawk 2's quality comes from skill, kit, morale and men ready (%.2f)" % q.quality)
	# The danger follows the living war: a front in a zone makes it worse.
	var zone := String(o.zone)
	var before := Income.zone_danger(zone)
	WorldSites.site(zone)["front"] = {"by": "ashen_banner", "since": Economy.day(), "progress": 0.4}
	check(Income.zone_danger(zone) > before, "a front in the zone raises its danger (%.2f -> %.2f)" % [before, Income.zone_danger(zone)])
	WorldSites.site(zone).erase("front")
	# Sending a squad: the advance now, the squad away, it can't deploy.
	var cash0 := Economy.cash()
	var why := Income.server_request("job_send", [String(o.id), "d02"], 1)
	check(why == "", "Hawk 2 goes out on the job (%s)" % why)
	check(Economy.cash() == cash0 + roundi(int(o.pay) * SideJobs.c("advance_share", 0.25)), "the advance is paid up front")
	check(SideJobs.is_away("d02") and not "d02" in Heroes.deploying(_roster(), 3), "a squad that's out can't deploy with the company")
	check(Income.server_request("job_send", [String((Income.state().offers as Array)[0].id), "d02"], 1) != "", "a squad already out can't take a second job")
	check(Income.server_request("job_send", [String((Income.state().offers as Array)[0].id), "d03"], 2) != "", "only the host sends squads")
	check(Economy.ledger_kind("Side job: Hawk 2, Escort") == "Side jobs", "side job pay has its own line in the books")
	# Coming back: after its days, the job resolves and reports.
	var job := SideJobs.job_of("d02")
	var reports := (Income.state().reports as Array).size()
	Economy.advance_days(int(job.days), "test")
	check(not SideJobs.is_away("d02"), "Hawk 2 is back after %d days" % int(job.days))
	check((Income.state().reports as Array).size() == reports + 1, "the squad reports on the company net and leaves a debrief card")
	check("d02" in Heroes.deploying(_roster(), 3) or int(Heroes.strength(_roster(), "d02").ready) == 0, "back from the job, it deploys again")
	# The roll's outcomes over many jobs: good squads in calm zones mostly come back clean; poor ones
	# in hot zones get hurt and fail; pay follows the result.
	var tally := {"clean": 0, "trouble": 0, "failed": 0, "kia": 0}
	for i in 60:
		var fake := {"id": "t%d" % i, "kind": "escort", "client": "meridian", "from": "Meridian", "zone": zone, "days": 2, "pay": 30000,
			"advance": 7500, "did": "d03", "callsign": "Viper 3", "start": 100 + i, "end": 102 + i, "trouble": 0.6}
		(Income.state().jobs as Array).append(fake)
		var out := SideJobs.server_resolve(fake)
		tally[String(out.result)] = int(tally[String(out.result)]) + 1
		tally.kia = int(tally.kia) + (out.kia as Array).size()
		for mid: Variant in Heroes.get_detachment(_roster(), "d03").members:  # keep the squad whole for the next roll
			var m := Roster.get_member(_roster(), String(mid))
			m["status"] = Roster.READY
			m["sit_out_days"] = 0
	check(int(tally.clean) > 10 and int(tally.trouble) + int(tally.failed) > 20, "at 60%% trouble, some jobs come back clean and many don't (%s)" % str(tally))
	check(int(tally.kia) > 0 and int(tally.failed) > 0, "a squad can lose men or fail the job")
	check((Fallen.memorial(_roster()) as Array).size() > 0, "a man lost on a side job goes on the memorial wall")
	# The page builds on every peer's copy without errors.
	var rows := VBoxContainer.new()
	add_child(rows)
	SideWorkPage.build(rows, self)
	check(rows.get_child_count() >= 3, "the side work page builds (%d rows)" % rows.get_child_count())
	check(SideWorkPage.board_summary() != "", "the board has a side work line: %s" % SideWorkPage.board_summary())
	rows.queue_free()
