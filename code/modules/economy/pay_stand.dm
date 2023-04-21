/obj/machinery/paystand
	name = "unregistered pay stand"
	desc = "an unregistered pay stand"
	icon = 'icons/obj/economy.dmi'
	icon_state = "card_scanner"
	anchored = TRUE
	layer = FLY_LAYER
	/// ID linked to the holopay
	var/obj/item/card/id/linked_card = null
	var/shop_logo = "donate"
	/// Replaces the "pay whatever" functionality with a set amount when non-zero.
	var/force_fee = 0

/obj/machinery/paystand/examine(mob/user)
	. = ..()
	if(force_fee)
		. += span_boldnotice("This paystand forces a payment of <b>[force_fee]</b> credit\s per swipe instead of a variable amount.")

/obj/machinery/paystand/attack_hand(mob/living/user, list/modifiers)
	. = ..()
	if(.)
		return
	if(!user.a_intent == INTENT_HARM && user.stat == CONSCIOUS)
		ui_interact(user)
		return .
	return

/obj/machinery/paystand/play_attack_sound(damage_amount, damage_type = BRUTE, damage_flag = 0)
	switch(damage_type)
		if(BRUTE)
			playsound(loc, 'sound/weapons/egloves.ogg', 80, TRUE)
		if(BURN)
			playsound(loc, 'sound/weapons/egloves.ogg', 80, TRUE)

/obj/machinery/paystand/Destroy()
	linked_card?.my_store = null
	linked_card = null
	return ..()

/obj/machinery/paystand/attackby(obj/item/held_item, mob/item_holder, params)
	var/mob/living/user = item_holder
	if(!isliving(user))
		return ..()
	/// Users can pay with an ID to skip the UI
	if(isidcard(held_item))
		if(!linked_card)
			if(istype(held_item, /obj/item/card/id))
				var/obj/item/card/id/card = held_item
				desc = "Pays directly into [card.registered_account.account_holder]'s bank account."
				force_fee = card.holopay_fee
		if(force_fee && tgui_alert(item_holder, "This holopay has a [force_fee] cr fee. Confirm?", "Holopay Fee", list("Pay", "Cancel")) != "Pay")
			return TRUE
		process_payment(user)
		return TRUE
	/// Users can also pay by holochip
	if(istype(held_item, /obj/item/holochip))
		/// Account checks
		var/obj/item/holochip/chip = held_item
		if(!chip.credits)
			balloon_alert(user, "holochip is empty")
			to_chat(user, span_warning("There doesn't seem to be any credits here."))
			return FALSE
		/// Charges force fee or uses pay what you want
		var/cash_deposit = force_fee || tgui_input_number(user, "How much? (Max: [chip.credits])", "Patronage", max_value = chip.credits)
		/// Exit sanity checks
		if(!cash_deposit)
			return TRUE
		if(QDELETED(held_item) || QDELETED(user) || QDELETED(src))
			return FALSE
		if(!chip.spend(cash_deposit, FALSE))
			balloon_alert(user, "insufficient credits")
			to_chat(user, span_warning("You don't have enough credits to pay with this chip."))
			return FALSE
		/// Success: Alert buyer
		alert_buyer(user, cash_deposit)
		return TRUE
	/// Throws errors if they try to use space cash
	if(istype(held_item, /obj/item/stack/spacecash))
		to_chat(user, "What is this, the 2000s? We only take card here.")
		return TRUE
	if(istype(held_item, /obj/item/coin))
		to_chat(user, "What is this, the 1800s? We only take card here.")
		return TRUE
	return ..()

/obj/machinery/paystand/ui_interact(mob/user, datum/tgui/ui)
	. = ..()
	if(.)
		return FALSE
	var/mob/living/interactor = user
	if(isliving(interactor) && !interactor.a_intent == INTENT_HELP)
		return FALSE
	ui = SStgui.try_update_ui(user, src, ui)
	if(!ui)
		ui = new(user, src, "HoloPay")
		ui.open()

/obj/machinery/paystand/ui_status(mob/user)
	. = ..()
	if(!in_range(user, src) && !isobserver(user))
		return UI_CLOSE

/obj/machinery/paystand/ui_static_data(mob/user)
	. = list()
	.["available_logos"] = linked_card.available_logos
	.["description"] = desc
	.["max_fee"] = linked_card.holopay_max_fee
	.["owner"] = linked_card.registered_account?.account_holder || null
	.["shop_logo"] = shop_logo

/obj/machinery/paystand/ui_data(mob/user)
	. = list()
	.["force_fee"] = force_fee
	.["name"] = name
	if(!isliving(user))
		return .
	var/mob/living/card_holder = user
	var/obj/item/card/id/id_card = card_holder.get_idcard(TRUE)
	var/datum/bank_account/account = id_card?.registered_account || null
	if(account)
		.["user"] = list()
		.["user"]["name"] = account.account_holder
		.["user"]["balance"] = account.account_balance

/obj/machinery/paystand/ui_act(action, list/params, datum/tgui/ui)
	. = ..()
	if(.)
		return FALSE
	switch(action)
		if("done")
			ui.send_full_update()
			return TRUE
		if("fee")
			linked_card.set_holopay_fee(params["amount"])
			force_fee = linked_card.holopay_fee
		if("logo")
			linked_card.set_holopay_logo(params["logo"])
			shop_logo = linked_card.holopay_logo
		if("pay")
			ui.close()
			process_payment(usr)
			return TRUE
		if("rename")
			linked_card.set_holopay_name(params["name"])
			name = linked_card.holopay_name
	return FALSE

/**
 * Initiates a transaction between accounts.
 *
 * Parameters:
 * * mob/living/user - The user who initiated the transaction.
 * Returns:
 * * TRUE - transaction was successful
 */
/obj/machinery/paystand/proc/process_payment(mob/living/user)
	/// Account checks
	var/obj/item/card/id/id_card
	id_card = user.get_idcard(TRUE)
	if(!id_card || !id_card.registered_account || !id_card.registered_account.account_job)
		balloon_alert(user, "invalid account")
		to_chat(user, span_warning("You don't have a valid account."))
		return FALSE
	var/datum/bank_account/payee = id_card.registered_account
	if(payee == linked_card?.registered_account)
		balloon_alert(user, "invalid transaction")
		to_chat(user, span_warning("You can't pay yourself."))
		return FALSE
	/// If the user has enough money, ask them the amount or charge the force fee
	var/amount = force_fee || tgui_input_number(user, "How much? (Max: [payee.account_balance])", "Patronage", max_value = payee.account_balance)
	/// Exit checks in case the user cancelled or entered an invalid amount
	if(!amount || QDELETED(user) || QDELETED(src))
		return FALSE
	if(!payee.adjust_money(-amount, "Holopay: [capitalize(name)]"))
		balloon_alert(user, "insufficient credits")
		to_chat(user, span_warning("You don't have the money to pay for this."))
		return FALSE
	/// Success: Alert the buyer
	alert_buyer(user, amount)
	return TRUE

/**
 * Alerts the owner of the transaction.
 *
 * Parameters:
 * * payee - The user who initiated the transaction.
 * * amount - The amount of money that was paid.
 * Returns:
 * * TRUE - alert was successful.
 */
/obj/machinery/paystand/proc/alert_buyer(payee, amount)
	/// Pay the owner
	linked_card.registered_account.adjust_money(amount, "Holopay: [name]")
	/// Make alerts
	linked_card.registered_account.bank_card_talk("[payee] has deposited [amount] cr at your holographic pay stand.")
	say("Thank you for your patronage, [payee]!")
	playsound(src, 'sound/effects/cashregister.ogg', 20, TRUE)
	SSblackbox.record_feedback("amount", "credits_transferred", amount)
	return TRUE
