class_name scenescript_actor
extends Node

@export var actor_name = ""

func _ready():
	if actor_name != "":
		if actor_name in Scenescript.scene_actors:
			push_error("An actor by the name of \"" + actor_name + "\" was already in the scene actors.")
			return
		Scenescript.scene_actors[actor_name] = self

func select(_process : scenescript_process):
	print("Scenescript actor " + actor_name + " was selected.")
