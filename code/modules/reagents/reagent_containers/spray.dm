/obj/item/reagent_containers/spray
	name = "spray bottle"
	desc = "A spray bottle, with an unscrewable top."
	icon = 'icons/obj/janitor.dmi'
	icon_state = "cleaner"
	item_state = "cleaner"
	worn_icon_state = "spraybottle"
	lefthand_file = 'icons/mob/inhands/equipment/custodial_lefthand.dmi'
	righthand_file = 'icons/mob/inhands/equipment/custodial_righthand.dmi'
	item_flags = NOBLUDGEON | ISWEAPON
	reagent_flags = OPENCONTAINER
	slot_flags = ITEM_SLOT_BELT
	throwforce = 0
	w_class = WEIGHT_CLASS_SMALL
	throw_speed = 3
	throw_range = 7
	var/stream_mode = FALSE //whether we use the more focused mode
	var/current_range = 3 //the range of tiles the sprayer will reach.
	var/spray_range = 3 //the range of tiles the sprayer will reach when in spray mode.
	var/stream_range = 1 //the range of tiles the sprayer will reach when in stream mode.
	var/can_fill_from_container = TRUE
	/// Are we able to toggle between stream and spray modes, which change the distance and amount sprayed?
	var/can_toggle_range = TRUE
	amount_per_transfer_from_this = 5
	volume = 250
	possible_transfer_amounts = list(5,10)

/obj/item/reagent_containers/spray/afterattack(atom/A, mob/user)
	. = ..()
	if(istype(A, /obj/structure/sink) || istype(A, /obj/structure/janitorialcart) || istype(A, /obj/machinery/hydroponics))
		return

	if((A.is_drainable() && !A.is_refillable()) && get_dist(src,A) <= 1 && can_fill_from_container)
		if(!A.reagents.total_volume)
			to_chat(user, span_warning("[A] is empty."))
			return

		if(reagents.holder_full())
			to_chat(user, span_warning("[src] is full."))
			return

		var/trans = A.reagents.trans_to(src, 50, transfered_by = user) //transfer 50u , using the spray's transfer amount would take too long to refill
		to_chat(user, span_notice("You fill \the [src] with [trans] units of the contents of \the [A]."))
		return

	if(reagents.total_volume < amount_per_transfer_from_this)
		to_chat(user, span_warning("Not enough left!"))
		return

	spray(A, user)

	playsound(src.loc, 'sound/effects/spray2.ogg', 50, 1, -6)
	user.changeNext_move(CLICK_CD_RANGE*2)
	user.newtonian_move(get_dir(A, user))

	var/turf/T = get_turf(src)
	var/contained = reagents.log_list()

	log_combat(user, T, "sprayed", src, addition="which had [contained]")
	log_game("[key_name(user)] fired [contained] from \a [src] at [AREACOORD(T)].") //copypasta falling out of my pockets
	return TRUE


/obj/item/reagent_containers/spray/proc/spray(atom/A, mob/user)
	var/range = max(min(current_range, get_dist(src, A)), 1)

	var/obj/effect/decal/chempuff/D = new /obj/effect/decal/chempuff(get_turf(src))

	D.create_reagents(amount_per_transfer_from_this)
	var/puff_reagent_left = range //how many turf, mob or dense objet we can react with before we consider the chem puff consumed
	if(stream_mode)
		reagents.trans_to(D, amount_per_transfer_from_this)
		puff_reagent_left = 1
	else
		reagents.trans_to(D, amount_per_transfer_from_this, 1/range)
	D.color = mix_color_from_reagents(D.reagents.reagent_list)
	var/wait_step = max(round(2+3/range), 2)

	do_spray(A, wait_step, D, range, puff_reagent_left, user)

/obj/item/reagent_containers/spray/proc/do_spray(atom/A, wait_step, obj/effect/decal/chempuff/D, range, puff_reagent_left, mob/user)
	var/datum/move_loop/our_loop = SSmove_manager.move_towards_legacy(D, A, wait_step, timeout = range * wait_step, flags = MOVEMENT_LOOP_START_FAST, priority = MOVEMENT_ABOVE_SPACE_PRIORITY)
	D.user = user
	D.sprayer = src
	D.lifetime = puff_reagent_left
	D.stream = stream_mode
	D.RegisterSignal(our_loop, COMSIG_PARENT_QDELETING, TYPE_PROC_REF(/obj/effect/decal/chempuff, loop_ended))
	D.RegisterSignal(our_loop, COMSIG_MOVELOOP_POSTPROCESS, TYPE_PROC_REF(/obj/effect/decal/chempuff, check_move))

/obj/item/reagent_containers/spray/attack_self(mob/user)
	. = ..()
	toggle_stream_mode(user)

/obj/item/reagent_containers/spray/attack_self_secondary(mob/user)
	. = ..()
	toggle_stream_mode(user)

/obj/item/reagent_containers/spray/proc/toggle_stream_mode(mob/user)
	if(stream_range == spray_range || !stream_range || !spray_range || possible_transfer_amounts.len > 2 || !can_toggle_range)
		return
	stream_mode = !stream_mode
	if(stream_mode)
		current_range = stream_range
	else
		current_range = spray_range
	to_chat(user, span_notice("You switch the nozzle setting to [stream_mode ? "\"stream\"":"\"spray\""]. You'll now use [amount_per_transfer_from_this] units per use."))

/obj/item/reagent_containers/spray/attackby(obj/item/I, mob/user, params)
	var/hotness = I.is_hot()
	if(hotness && reagents)
		reagents.expose_temperature(hotness)
		to_chat(user, span_notice("You heat [name] with [I]!"))
	return ..()

/obj/item/reagent_containers/spray/verb/empty()
	set name = "Empty Spray Bottle"
	set category = "Object"
	set src in usr
	if(usr.incapacitated())
		return
	if (alert(usr, "Are you sure you want to empty that?", "Empty Bottle:", "Yes", "No") != "Yes")
		return
	if(isturf(usr.loc) && src.loc == usr)
		to_chat(usr, span_notice("You empty \the [src] onto the floor."))
		reagents.expose(usr.loc)
		src.reagents.clear_reagents()

/obj/item/reagent_containers/spray/on_reagent_change(changetype)
	var/total_reagent_weight
	var/amount_of_reagents
	for (var/datum/reagent/R in reagents.reagent_list)
		total_reagent_weight = total_reagent_weight + R.reagent_weight
		amount_of_reagents++

	if(total_reagent_weight && amount_of_reagents) //don't bother if the container is empty - DIV/0
		var/average_reagent_weight = total_reagent_weight / amount_of_reagents
		spray_range = clamp(round((initial(spray_range) / average_reagent_weight) - ((amount_of_reagents - 1) * 1)), 3, 5) //spray distance between 3 and 5 tiles rounded down; extra reagents lose a tile
	else
		spray_range = initial(spray_range)
	if(stream_mode == 0)
		current_range = spray_range

//space cleaner
/obj/item/reagent_containers/spray/cleaner
	name = "space cleaner"
	desc = "BLAM!-brand non-foaming space cleaner! A warning label reads 'CAUTION! NOT SAFE FOR INGESTION'"
	volume = 100
	list_reagents = list(/datum/reagent/space_cleaner = 100)
	amount_per_transfer_from_this = 2
	possible_transfer_amounts = list(2,5)

/obj/item/reagent_containers/spray/cleaner/suicide_act(mob/living/user)
	user.visible_message(span_suicide("[user] is putting the nozzle of \the [src] in [user.p_their()] mouth.  It looks like [user.p_theyre()] trying to commit suicide!"))
	if(do_after(user, 3 SECONDS))
		if(reagents.total_volume >= amount_per_transfer_from_this)//if not empty
			user.visible_message(span_suicide("[user] pulls the trigger!"))
			src.spray(user)
			return BRUTELOSS
		else
			user.visible_message(span_suicide("[user] pulls the trigger...but \the [src] is empty!"))
			return SHAME
	else
		user.visible_message(span_suicide("[user] decided life was worth living."))
		return

//spray tan
/obj/item/reagent_containers/spray/spraytan
	name = "spray tan"
	volume = 50
	desc = "Gyaro brand spray tan. Do not spray near eyes or other orifices."
	list_reagents = list(/datum/reagent/spraytan = 50)

//water flower
/obj/item/reagent_containers/spray/waterflower
	name = "water flower"
	desc = "A seemingly innocent sunflower...with a twist."
	icon = 'icons/obj/hydroponics/harvest.dmi'
	icon_state = "sunflower"
	item_state = "sunflower"
	amount_per_transfer_from_this = 1
	has_variable_transfer_amount = FALSE
	can_toggle_range = FALSE
	current_range = 1
	volume = 10
	list_reagents = list(/datum/reagent/water = 10)

/obj/item/reagent_containers/spray/waterflower/superlube
	name = "clown flower"
	desc = "A delightly devilish flower... you got a feeling where this is going."
	icon = 'icons/obj/chemical.dmi'
	icon_state = "clownflower"
	volume = 30
	list_reagents = list(/datum/reagent/lube/superlube = 30)

/obj/item/reagent_containers/spray/waterflower/cyborg
	reagent_flags = NONE
	volume = 100
	list_reagents = list(/datum/reagent/water = 100)
	var/generate_amount = 5
	var/generate_type = /datum/reagent/water
	var/last_generate = 0
	var/generate_delay = 10	//deciseconds
	can_fill_from_container = FALSE

/obj/item/reagent_containers/spray/waterflower/cyborg/hacked
	name = "nova flower"
	desc = "This doesn't look safe at all..."
	list_reagents = list(/datum/reagent/clf3 = 3)
	volume = 3
	generate_type = /datum/reagent/clf3
	generate_amount = 1
	generate_delay = 40		//deciseconds

/obj/item/reagent_containers/spray/waterflower/cyborg/Initialize(mapload)
	. = ..()
	START_PROCESSING(SSfastprocess, src)

/obj/item/reagent_containers/spray/waterflower/cyborg/Destroy()
	STOP_PROCESSING(SSfastprocess, src)
	return ..()

/obj/item/reagent_containers/spray/waterflower/cyborg/process()
	if(world.time < last_generate + generate_delay)
		return
	last_generate = world.time
	generate_reagents()

/obj/item/reagent_containers/spray/waterflower/cyborg/empty()
	to_chat(usr, span_warning("You can not empty this!"))
	return

/obj/item/reagent_containers/spray/waterflower/cyborg/proc/generate_reagents()
	reagents.add_reagent(generate_type, generate_amount)

//chemsprayer
/obj/item/reagent_containers/spray/chemsprayer
	name = "chem sprayer"
	desc = "A utility used to spray large amounts of reagents in a given area."
	icon = 'icons/obj/guns/projectile.dmi'
	icon_state = "chemsprayer"
	item_state = "chemsprayer"
	lefthand_file = 'icons/mob/inhands/weapons/guns_lefthand.dmi'
	righthand_file = 'icons/mob/inhands/weapons/guns_righthand.dmi'
	throwforce = 0
	w_class = WEIGHT_CLASS_LARGE
	stream_mode = 1
	current_range = 7
	spray_range = 4
	stream_range = 7
	amount_per_transfer_from_this = 10
	volume = 600

/obj/item/reagent_containers/spray/chemsprayer/afterattack(atom/A as mob|obj, mob/user)
	// Make it so the bioterror spray doesn't spray yourself when you click your inventory items
	if (A.loc == user)
		return
	. = ..()

/obj/item/reagent_containers/spray/chemsprayer/spray(atom/A, mob/user)
	var/direction = get_dir(src, A)
	var/turf/T = get_turf(A)
	var/turf/T1 = get_step(T,turn(direction, 90))
	var/turf/T2 = get_step(T,turn(direction, -90))
	var/list/the_targets = list(T,T1,T2)

	for(var/i in 1 to 3) // intialize sprays
		if(reagents.total_volume < 1)
			return
		..(the_targets[i], user)

/obj/item/reagent_containers/spray/chemsprayer/bioterror
	list_reagents = list(/datum/reagent/toxin/sodium_thiopental = 100, /datum/reagent/toxin/coniine = 100, /datum/reagent/toxin/venom = 100, /datum/reagent/consumable/condensedcapsaicin = 100, /datum/reagent/toxin/initropidril = 100, /datum/reagent/toxin/polonium = 100)


/obj/item/reagent_containers/spray/chemsprayer/janitor
	name = "janitor chem sprayer"
	desc = "A utility used to spray large amounts of cleaning reagents in a given area. It regenerates space cleaner by itself but it's unable to be fueled by normal means."
	icon_state = "chemsprayer_janitor"
	item_state = "chemsprayer_janitor"
	lefthand_file = 'icons/mob/inhands/weapons/guns_lefthand.dmi'
	righthand_file = 'icons/mob/inhands/weapons/guns_righthand.dmi'
	reagent_flags = NONE
	list_reagents = list(/datum/reagent/space_cleaner = 1000)
	volume = 1000
	amount_per_transfer_from_this = 5
	var/generate_amount = 50
	var/generate_type = /datum/reagent/space_cleaner
	var/last_generate = 0
	var/generate_delay = 10	//deciseconds

/obj/item/reagent_containers/spray/chemsprayer/janitor/Initialize(mapload)
	. = ..()
	START_PROCESSING(SSfastprocess, src)

/obj/item/reagent_containers/spray/chemsprayer/janitor/Destroy()
	STOP_PROCESSING(SSfastprocess, src)
	return ..()

/obj/item/reagent_containers/spray/chemsprayer/janitor/process()
	if(world.time < last_generate + generate_delay)
		return
	last_generate = world.time
	reagents.add_reagent(generate_type, generate_amount)

/obj/item/reagent_containers/spray/chemsprayer/janitor/clown
	name = "lubinator 8000"
	desc = "A modified industrial cleaning sprayer, capable of coating entire hallways in high performance lubricant, honk!"
	icon_state = "chemsprayer"
	item_state = "chemsprayer"
	list_reagents = list(/datum/reagent/lube = 1000)
	generate_type = /datum/reagent/lube

// Plant-B-Gone
/obj/item/reagent_containers/spray/plantbgone // -- Skie
	name = "Plant-B-Gone"
	desc = "Kills those pesky weeds!"
	icon = 'icons/obj/hydroponics/equipment.dmi'
	icon_state = "plantbgone"
	item_state = "plantbgone"
	lefthand_file = 'icons/mob/inhands/equipment/hydroponics_lefthand.dmi'
	righthand_file = 'icons/mob/inhands/equipment/hydroponics_righthand.dmi'
	volume = 100
	list_reagents = list(/datum/reagent/toxin/plantbgone = 100)

/obj/item/reagent_containers/spray/cyborg
	var/charge_cost = 50
	var/charge_tick = 0
	var/recharge_time = 2 //Time it takes for 5u to recharge (in seconds)
	var/datum/reagent/set_reagent

CREATION_TEST_IGNORE_SELF(/obj/item/reagent_containers/spray/cyborg)

/obj/item/reagent_containers/spray/cyborg/Initialize(mapload)
	. = ..()
	reagents.add_reagent(set_reagent, volume)
	START_PROCESSING(SSobj, src)

/obj/item/reagent_containers/spray/cyborg/process()
	charge_tick++
	if(charge_tick >= recharge_time)
		regenerate_reagents()
		charge_tick = 0

/obj/item/reagent_containers/spray/cyborg/proc/regenerate_reagents()
	var/mob/living/silicon/robot/R = loc
	if(istype(R))
		if(R.cell)
			if(reagents.total_volume <= volume)
				R.cell.use(charge_cost)
				reagents.add_reagent(set_reagent, 5)

/obj/item/reagent_containers/spray/cyborg/drying_agent
	name = "drying agent spray"
	desc = "A spray for cleaning up wet floors."
	color = "#A000A0"
	set_reagent = /datum/reagent/drying_agent

/obj/item/reagent_containers/spray/cyborg/plantbgone
	name = "Plant-B-Gone"
	desc = "A bottle of weed killer spray for stopping kudzu-based harm."
	icon = 'icons/obj/hydroponics/equipment.dmi'
	icon_state = "plantbgone"
	item_state = "plantbgone"
	set_reagent = /datum/reagent/toxin/plantbgone

/obj/item/reagent_containers/spray/cyborg/lube
	name = "lube spray"
	desc = "A spray filled with space lube, for sabotaging the crew."
	color = "#009CA8"
	set_reagent = /datum/reagent/lube

/obj/item/reagent_containers/spray/cyborg/acid
	name = "acid spray"
	desc = "A spray filled with sulfuric acid for offensive use."
	color = "#00FF32"
	set_reagent = /datum/reagent/toxin/acid
