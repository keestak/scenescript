#this is an autoload class. The autoload must be called "Scenescript"
class_name scenescript_global_autolaod
extends Node

var global_vars := {} #variables that are presistent as long as the game is running
var scene_vars := {}  #variables that belong to the current scene; should be cleared when the scene changes
var register_stack := [] #register stack is global, so can share values across files
var scene_actors := {} #contains all the actors in the scene by name

var use_say_params := true
