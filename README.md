# Scenescript
 A simple scripting language for creating cutscenes and branching dialog sequences for the Godot game engine, focusing on being efficient and non-verbose. Made public temporarily, part of a larger game project.
 Features:
 - Choices and branching dialog trees
 - Multiple variable lifetime scopes (global, scene, and local)
 - Support for complex expressions
 - Complete localization support
 - Python-like syntax and comments

 Planned:
 - Binary format (.ssb) for quick and easy serialization

Example script:
```
id bnuy_store_2
@player_hud.show_money()
say:
	Hai Hai![pause]\nU want 2 buy a CoconutDrinks?\nOnly 50 coin(s)!!!
choice:
	"buy":
		if @global_actor.is_player_inventory_full:
			say:
				Ummm excuse me but, user inventory overflow error.
			@player_hud.hide_money()
			exit
		if @global_actor.player_money < 25:
			say:
				Sorry, but you don't have enough coin(s)!
				Come back when you're a little, uhhhh, richer!
			@player_hud.hide_money()
			exit
		@global_actor.call_on_node("SprBsodShop2/cyber_denizen/item_spawner", "spawn")
		@global_actor.player_money = @global_actor.player_money - 50
		say "Thankies!! Come again!!!"
		@player_hud.hide_money()
		exit
	"bye":
		say "ok...."
		@player_hud.hide_money()
		exit

id long_hallway_start
wait 0.5
@melody
.flip_sprite(false)
.set_behavior("control")
.set_sprite("look_side")
.move_to(1200, 1100)
wait 1.5
say:
	...
	{"worried"}Looks like we're getting close to the end.
	...
.flip_sprite(true)
.set_sprite("idle")
wait 0.5
say:
	Uh... I- I just wanted to say, that...
	{"worried_lookleft"}W- Well, this isn't how I expected to meet you, but, I'm glad that you're here, and...

.flip_sprite(false)
say:
	{"neutral_raise_eyebrows"}Well, once we get out of this place, there's a whole world out there waiting for us to explore.
	{"neutral_talk"}I... hope that we'll be able to get to know each other better and...
	{"neutral_raise_eyebrows"}Maybe... become friends...
	{"neutral"}...
	{"neutral_raise_eyebrows"}Um... Anyways... Let's keep going.
	I'm sure we'll be out of here soon.

@melody.set_behavior("follow")
exit

id long_hallway_end
wait 0.5
@melody
.set_behavior("control")
.set_sprite("surprise")

say:
	{"shock_1"}H-huh? What the heck!?

.set_sprite("look_down")

say:
	What's wrong with the ground?\nWhat's with all this weird black stuff!?
	{"worried"}They're blocking the way forward, but... well, it seems like there's another path...
	{"worried_lookleft"}I... I don't think this is what's supposed to happen...

@melody.set_behavior("follow")
exit
```
