## =====================================================================================
## CHANGES REQUIRED IN Main_Match_Core_Gameplay_Script.gd
## =====================================================================================
## These changes are needed to integrate the base3 (Fossil) effects.
## Add these in the appropriate locations in your main script.
## =====================================================================================

## ---- 1. PLAYER ATTACK ROUTING ----
## Add these BEFORE the generic damage path in player_use_attack(),
## after the existing LEECH LIFE check and before the CALL FOR FAMILY check:

#region BASE3_PLAYER_ATTACK_ROUTING

	# SONICBOOM: Fixed damage ignoring W/R
	if "don't apply weakness and resistance for this attack" in text_lower:
		hide_attack_buttons()
		var base_dmg = attack_effects.parse_attack_base_damage(attack)
		await attack_effects.execute_sonicboom(player_active_pokemon, opponent_active_pokemon, false, base_dmg)
		last_attack_on_opponent = {"damage": base_dmg, "attack": attack, "attacker_types": player_active_pokemon.metadata.get("types", ["Colorless"])}
		player_attacked_this_turn = true
		await check_all_knockouts()
		await get_tree().create_timer(0.5).timeout
		player_end_turn_checks()
		return
	
	# WILDFIRE: Discard Fire Energy to mill opponent deck
	if "discard any number of fire energy" in text_lower and "discard that many cards" in text_lower:
		hide_attack_buttons()
		await attack_effects.execute_wildfire(player_active_pokemon, false)
		await get_tree().create_timer(0.5).timeout
		player_end_turn_checks()
		return
	
	# GIGASHOCK: 30 damage + 10 to up to 3 bench
	if "choose 3 of your opponent's benched" in text_lower and "10 damage to each of them" in text_lower:
		hide_attack_buttons()
		await attack_effects.execute_gigashock(player_active_pokemon, opponent_active_pokemon, false)
		last_attack_on_opponent = {"damage": 30, "attack": attack, "attacker_types": player_active_pokemon.metadata.get("types", ["Colorless"])}
		player_attacked_this_turn = true
		await check_all_knockouts()
		await get_tree().create_timer(0.5).timeout
		player_end_turn_checks()
		return
	
	# THUNDERSTORM: 40 + per-bench flip + self recoil
	if "for each of your opponent's benched" in text_lower and "flip a coin" in text_lower and "damage times the number of tails" in text_lower:
		hide_attack_buttons()
		await attack_effects.execute_thunderstorm(player_active_pokemon, opponent_active_pokemon, false)
		last_attack_on_opponent = {"damage": 40, "attack": attack, "attacker_types": player_active_pokemon.metadata.get("types", ["Colorless"])}
		player_attacked_this_turn = true
		await check_all_knockouts()
		await get_tree().create_timer(0.5).timeout
		player_end_turn_checks()
		return
	
	# PROPHECY: Look at top 3 cards, rearrange
	if "look at up to 3 cards" in text_lower and "rearrange" in text_lower:
		hide_attack_buttons()
		await attack_effects.execute_prophecy(player_active_pokemon, false)
		await get_tree().create_timer(0.5).timeout
		player_end_turn_checks()
		return
	
	# ENERGY CONVERSION: Get energy from discard + self damage
	if "energy cards from your discard pile into your hand" in text_lower and "damage to itself" in text_lower:
		hide_attack_buttons()
		await attack_effects.execute_energy_conversion(player_active_pokemon, false)
		await check_all_knockouts()
		await get_tree().create_timer(0.5).timeout
		player_end_turn_checks()
		return
	
	# SPACING OUT: Flip to heal self, can't use if no damage
	if "remove a damage counter from" in text_lower and "can't be used if" in text_lower and "no damage counters" in text_lower:
		hide_attack_buttons()
		await attack_effects.execute_spacing_out(player_active_pokemon, false)
		await get_tree().create_timer(0.5).timeout
		player_end_turn_checks()
		return
	
	# SCAVENGE: Discard Psychic Energy, get Trainer from discard
	if "discard 1 psychic energy" in text_lower and "trainer card from your discard pile" in text_lower:
		hide_attack_buttons()
		await attack_effects.execute_scavenge(player_active_pokemon, false)
		await get_tree().create_timer(0.5).timeout
		player_end_turn_checks()
		return

#endregion

## ---- 2. TURN START: RESET TRAINER LOCK ----
## In your player_start_turn / opponent_start_turn functions, add:

	trainer_effects.reset_trainer_lock(false)   # At player turn start
	trainer_effects.reset_trainer_lock(true)    # At opponent turn start

## ---- 3. EVOLUTION BLOCK (Prehistoric Power) ----
## Before allowing any evolution (both player and CPU), add:

	if powers_and_bodies.is_prehistoric_power_active():
		await show_message("PREHISTORIC POWER: EVOLUTION IS BLOCKED!")
		return

## ---- 4. TRANSPARENCY CHECK ----
## Before applying damage to a defending pokemon, add:
## (In your damage application flow, after selecting the attack but before dealing damage)

	var transparency_blocked = await powers_and_bodies.check_transparency(defender)
	if transparency_blocked:
		# Skip damage and all attack effects
		return

## ---- 5. KABUTO ARMOR CHECK ----
## In calculate_final_damage(), after W/R but before returning, add:

	damage = powers_and_bodies.apply_kabuto_armor(defending_pokemon, damage)

## ---- 6. CLAIRVOYANCE (Optional UI) ----
## If you want to show the opponent's hand face-up when Omanyte's Clairvoyance is active:

	if powers_and_bodies.is_clairvoyance_active():
		# Show opponent hand cards face-up in UI
		pass

## ---- 7. TOXIC GAS INTEGRATION ----
## Powers_And_Bodies_Effects.gd already has is_toxic_gas_active().
## This is checked internally by the new power functions.
## BUT you should also add a check in open_power_menu() to block the
## power menu entirely when Toxic Gas is active:
## (Already partially handled - the individual powers check it)
## For full correctness, add at the top of open_power_menu():

	if is_toxic_gas_active():
		# Still allow bench token discards (they aren't Pokemon Powers)
		# But block everything else
		pass
