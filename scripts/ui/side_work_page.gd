class_name SideWorkPage
extends RefCounted
## The base screen's "Side work" page (BaseUI, claude/income; docs/income.md): the company's
## income beyond contracts, every offer with what it pays and what it risks before anything is
## committed. Built from Income.view() (the host's section, synced to every peer); every button
## sends a BaseHub "income" request. Sections: the high command squads and their side jobs, the
## jobs on offer, and the latest reports (debrief cards). The contract board shows a summary
## (board_summary) with a button here.

const ABOUT := "Money beyond contracts: the high command squads' own jobs, captures sold by standing, bounties on the war's leaders. Every offer shows its pay and its risks before you commit."


## Builds the page into `rows`. `hotkey_root`: the node the send buttons' number keys belong to.
static func build(rows: VBoxContainer, hotkey_root: Node) -> void:
	var s := Income.view()
	var roster: Dictionary = BaseHub.view.get("roster", Campaign.section(&"roster"))
	var keys := [0]  # the next number key for a send button (1..9)
	_squads(rows, roster, s)
	_offers(rows, roster, s, hotkey_root, keys)
	_captures(rows, roster, s)
	_bounties(rows)
	_reports(rows, s)


## A send button's number key, 1..9 in page order (none after nine).
static func _key(b: Button, root: Node, keys: Array) -> Button:
	if int(keys[0]) < 9 and root != null:
		keys[0] = int(keys[0]) + 1
		UiKit.hotkey(b, KEY_0 + int(keys[0]), root)
	return b


static func _indent(c: Control) -> MarginContainer:
	var m := MarginContainer.new()
	m.add_theme_constant_override(&"margin_left", UiKit.SPACE_L)
	m.add_child(c)
	return m


static func money(v: Variant) -> String:
	return "$" + DebriefCalc.money(v)


static func pct(v: float) -> String:
	return "%d%%" % roundi(v * 100.0)


# --- High command squads ------------------------------------------------------------------

static func _squads(rows: VBoxContainer, roster: Dictionary, s: Dictionary) -> void:
	rows.add_child(UiKit.heading("High command squads"))
	var dets := Heroes.detachments(roster.duplicate(true))
	if dets.is_empty():
		rows.add_child(_indent(UiKit.text("No high command squads.")))
		return
	var ids: Array = dets.keys()
	ids.sort()
	for did: String in ids:
		var d: Dictionary = dets[did]
		var job := SideJobs.job_of(did, s)
		var q := SideJobs.quality(roster, did, s)
		var line := ""
		if not job.is_empty():
			line = "%s: away %s in %s for %s, back on day %d" % [String(d.callsign), String(SideJobs.kind(String(job.kind)).get("verb", "on a job")),
				RegionMap.zone_name(String(job.zone)), String(job.from), int(job.end)]
		else:
			line = "%s: %d of %d fit, morale %s, rated %s for side work" % [String(d.callsign), int(q.ready), int(q.total), pct(float(q.morale)), pct(float(q.quality))]
		var l := UiKit.text(line)
		l.tooltip_text = "Skill %s, kit %s, morale %s. Better squads get into trouble less often. A squad on a job can't deploy with the company." \
			% [pct(float(q.skill)), pct(float(q.kit)), pct(float(q.morale))]
		l.mouse_filter = Control.MOUSE_FILTER_PASS
		rows.add_child(_indent(l))


# --- Side jobs on offer -------------------------------------------------------------------

static func _offers(rows: VBoxContainer, roster: Dictionary, s: Dictionary, root: Node, keys: Array) -> void:
	var offers: Array = s.get("offers", [])
	rows.add_child(UiKit.heading("Side jobs offered (%d)" % offers.size()))
	if offers.is_empty():
		rows.add_child(_indent(UiKit.text("Nobody is offering side work today. Employers and fixers who'll deal with the company post new jobs every day.")))
		return
	rows.add_child(_indent(UiKit.hint("Pay scales with the zone's danger. A quarter comes up front and is kept whatever happens; the rest when the squad comes back with the job done.")))
	var dets := Heroes.detachments(roster.duplicate(true))
	var ids: Array = dets.keys()
	ids.sort()
	for o: Dictionary in offers:
		var k := SideJobs.kind(String(o.kind))
		var box := VBoxContainer.new()
		box.add_theme_constant_override(&"separation", UiKit.SPACE_XS)
		var head := UiKit.text("%s for %s in %s: %s over %d day%s (advance %s). Danger %s. Offer ends day %d." % [String(k.get("name", "")), String(o.from),
			RegionMap.zone_name(String(o.zone)), money(o.pay), int(o.days), "" if int(o.days) == 1 else "s",
			money(roundi(int(o.pay) * SideJobs.c("advance_share", 0.25))), Income.danger_word(float(o.danger)), int(o.expires)])
		UiKit.fit_label_text(head)
		head.tooltip_text = String(k.get("brief", "")) + ("\nTraining locals raises rebel support in the region." if int(k.get("rebel_support", 0)) > 0 else "")
		head.mouse_filter = Control.MOUSE_FILTER_PASS
		box.add_child(head)
		var buttons: Array = []
		for did: String in ids:
			var d: Dictionary = dets[did]
			var why := SideJobs.cant_send(roster, did) if SideJobs.job_of(did, s).is_empty() else "%s is already out on a job" % String(d.callsign)
			var od := SideJobs.odds(k, float(o.danger), float(SideJobs.quality(roster, did, s).quality))
			var tip := "Send %s: trouble %s (wounded men), a man lost %s, the job failing %s. Away %d days; can't deploy with you meanwhile." \
				% [String(d.callsign), pct(float(od.trouble)), pct(float(od.loss)), pct(float(od.fail)), int(o.days)]
			var b := UiKit.button("Send %s (risk %s)" % [String(d.callsign), pct(float(od.trouble))],
				func() -> void: BaseHub.request("income", ["job_send", String(o.id), did]), tip if why == "" else why)
			b.disabled = why != ""
			buttons.append(_key(b, root, keys) if why == "" else b)
		box.add_child(UiKit.button_row(buttons))
		rows.add_child(_indent(box))


# --- Captures and bounties ---------------------------------------------------------------

static func _captures(rows: VBoxContainer, roster: Dictionary, s: Dictionary) -> void:
	var caps := Bounties.stored_captures()
	rows.add_child(UiKit.heading("Captured vehicles and guns in storage (%d)" % caps.size()))
	if caps.is_empty():
		rows.add_child(_indent(UiKit.text("None. Tag an enemy vehicle or heavy gun \"to sell\" in the field and store it from the debrief: buyers here pay by standing.")))
		return
	var dets := Heroes.detachments(roster.duplicate(true))
	var ids: Array = dets.keys()
	ids.sort()
	for e: Dictionary in caps:
		var lot: Dictionary = e.lot
		var box := VBoxContainer.new()
		box.add_child(UiKit.text("%s (worth $%s; storage sale $%s)" % [String(lot.get("label", "?")), DebriefCalc.money(lot.get("value", 0)),
			DebriefCalc.money(Pallets.sell_price(lot, true))]))
		var buttons: Array = []
		for b: Dictionary in Bounties.capture_buyers(lot):
			var tip := "Sell to %s now: %s standing with them%s" % [String(b.from), "%+d" % int(b.rep),
				(", %+d with every lawful faction (arming a militia)" % int(b.lawful_hit)) if int(b.lawful_hit) != 0 else ""]
			var sell := UiKit.button("%s %s" % [String(b.from), money(b.price)],
				func() -> void: BaseHub.request("income", ["capture_sell", int(e.index), String(b.faction)]), tip if String(b.why) == "" else String(b.why))
			sell.disabled = String(b.why) != ""
			buttons.append(sell)
			if String(b.why) != "":
				continue
			for did: String in ids:
				var why := SideJobs.cant_send(roster, did) if SideJobs.job_of(did, s).is_empty() else "out on a job"
				if why != "":
					continue
				var o := Bounties.delivery_offer(int(e.index), String(b.faction))
				if o.is_empty():
					continue
				var od := SideJobs.odds(SideJobs.kind("recover"), float(o.danger), float(SideJobs.quality(roster, did, s).quality))
				var dv := UiKit.button("%s delivers: %s" % [String(dets[did].callsign), money(o.pay)],
					func() -> void: BaseHub.request("income", ["capture_deliver", int(e.index), String(b.faction), did]),
					"%s drives it to %s in %s (%d days, danger %s): trouble %s, a man lost %s, the vehicle lost %s. Paid on delivery." % [String(dets[did].callsign),
						String(b.from), RegionMap.zone_name(String(o.zone)), int(o.days), Income.danger_word(float(o.danger)), pct(float(od.trouble)), pct(float(od.loss)), pct(float(od.fail))])
				buttons.append(dv)
		box.add_child(UiKit.button_row(buttons))
		rows.add_child(_indent(box))


static func _bounties(rows: VBoxContainer) -> void:
	var open := Bounties.open_bounties()
	rows.add_child(UiKit.heading("Bounties on the war's leaders (%d)" % open.size()))
	if open.is_empty():
		rows.add_child(_indent(UiKit.text("No bounties posted.")))
		return
	rows.add_child(_indent(UiKit.hint("Paid at the debrief of the job that takes him: an HVT capture or manhunt brings him in alive; an HVT kill pays the dead bounty only with his ID papers carried out.")))
	for b: Dictionary in open:
		var l := UiKit.text("%s, %s: %s alive, %s dead (posted by %s)" % [String(b.leader).capitalize() if String(b.leader).begins_with("the ") else String(b.leader),
			MissionRegistry.faction_name(String(b.faction)), money(b.alive), money(b.dead), String(b.poster_name)])
		l.tooltip_text = "The bounty rises while %s is strong in the war. Look for an HVT job against them on the contract board." % MissionRegistry.faction_name(String(b.faction))
		l.mouse_filter = Control.MOUSE_FILTER_PASS
		UiKit.fit_label_text(l)
		rows.add_child(_indent(l))


# --- Reports ------------------------------------------------------------------------------

static func _reports(rows: VBoxContainer, s: Dictionary) -> void:
	var reports: Array = (s.get("reports", []) as Array).duplicate()
	if reports.is_empty():
		return
	reports.reverse()
	rows.add_child(UiKit.heading("Reports"))
	for r: Dictionary in reports.slice(0, 6):
		var card := UiKit.panel()
		var box := VBoxContainer.new()
		card.add_child(box)
		var title := UiKit.text("Day %d  %s" % [int(r.get("day", 0)), String(r.get("title", ""))])
		box.add_child(title)
		var body := UiKit.warn(String(r.get("text", ""))) if String(r.get("kind", "")) == "bad" else UiKit.hint(String(r.get("text", "")))
		body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(body)
		var parts := PackedStringArray()
		for l: Array in r.get("lines", []):
			parts.append("%s %s" % [String(l[0]), money(l[1])] if int(l[1]) != 0 else String(l[0]))
		if not parts.is_empty():
			var detail := UiKit.hint("  ".join(parts))
			detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			box.add_child(detail)
		rows.add_child(_indent(card))


## The contract board's line about side work: what's on offer and who's away.
static func board_summary() -> String:
	var s := Income.view()
	var parts := PackedStringArray()
	var offers: Array = s.get("offers", [])
	if not offers.is_empty():
		var best := 0
		for o: Dictionary in offers:
			best = maxi(best, int(o.get("pay", 0)))
		parts.append("%d side job%s for the high command squads (up to %s)" % [offers.size(), "" if offers.size() == 1 else "s", money(best)])
	for j: Dictionary in s.get("jobs", []):
		parts.append("%s away until day %d" % [String(j.callsign), int(j.end)])
	var open := Bounties.open_bounties()
	if not open.is_empty():
		var top := 0
		for b: Dictionary in open:
			top = maxi(top, int(b.alive))
		parts.append("%d bount%s on the war's leaders (up to %s)" % [open.size(), "y" if open.size() == 1 else "ies", money(top)])
	if not Bounties.stored_captures().is_empty():
		parts.append("%d capture%s in storage to sell" % [Bounties.stored_captures().size(), "" if Bounties.stored_captures().size() == 1 else "s"])
	return "; ".join(parts) + "." if not parts.is_empty() else "No side work today."
