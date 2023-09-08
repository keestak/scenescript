class_name scenescript_process
extends RefCounted

signal node_signal
signal finished
signal error_signal

var present_dialog_callback : Callable
var present_choice_callback : Callable
var get_timer_callback : Callable
var handle_say_params_callback : Callable
var finished_callback : Callable
var deselect_actor_callback : Callable

var language_reference_dictionary = {}

var nodes : Array[scenescript_node]
var current_node_index := -1
var current_node : scenescript_node

var variables := {}
var constants := {}
var selected_actor : scenescript_actor = null

var is_running := false
var end_step := false

var print_debug_info := false
var has_process_error := false
var process_error_message : String

#note: sub-process won't / can't use a langref file currently (could easily make it use this (the parent process)'s dictionary though)
var sub_process : scenescript_process
var parent_process_names = []

var process_name = ""

func load_file(path : String, should_print_debug_info := false):
	print_debug_info = should_print_debug_info
	if print_debug_info:
		print("Scenescript: " + path)
	
	var tokenizer := scenescript_tokenizer.new()
	tokenizer.print_debug_info = print_debug_info
	tokenizer.source_code = FileAccess.open(path, FileAccess.READ).get_as_text()
	
	if print_debug_info:
		print("--- tokenize ---\n")
	var tokens = tokenizer.tokenize()
	
	var parser := scenescript_parser.new()
	parser.print_debug_info = print_debug_info
	parser.tokens = tokens
	
	if print_debug_info:
		print("\n\n--- parse ---\n\n")
	nodes = parser.parse()
	
	for jump_name in parser.jump_positions.keys():
		constants[jump_name] = parser.jump_positions[jump_name].jump_position_index
		
	for action_name in parser.actions.keys():
		constants[action_name] = parser.actions[action_name].index
	
	process_name = path

func load_langref_file(path : String):
	print("Scenescript langref: " + path)
	language_reference_dictionary = scenescript_save_load.new().load_langref_text(path)
	pass

func save_to_file(path : String, split_language_and_logic := false):
	var save = scenescript_save_load.new()
	save.save_as_text(nodes, path, split_language_and_logic)

func step():
	if sub_process != null:
		sub_process.step()
		return #currently we're only running processes linearly; so no asynchronous stuff
		
	if is_running:
		#make_error("Step() was called while process is running")
		return
	
	is_running = true
	
	while (not is_at_end()) and (not has_process_error):
		
		advance()
		if is_at_end():
			finished.emit()
			finished_callback.call()
			is_running = false
			current_node_index = 0
			return
		
		match current_node.type:
			scenescript_node.NodeType.EXIT: #terminate process
				finished.emit()
				finished_callback.call()
				is_running = false
				current_node_index = 0
				return
			_:
				current_node.run(self)
				if current_node is scenescript_node.run_file:
					break
		
		if print_debug_info:
			print("Current node: " + current_node.name)
			print("vars:")
			for k in variables.keys():
				print("\t" + str(k)+ " : " + str(variables[k]) + "\n")
			
		if end_step:
			end_step = false
			break
	
	is_running = false

func advance():
	current_node_index += 1
	if is_at_end():
		current_node = null
		return
	current_node = nodes[current_node_index]

func is_at_end() -> bool:
	return current_node_index >= nodes.size()

func get_value(value_name : String):
	if value_name in constants.keys():
		return constants[value_name]
	elif value_name in variables.keys():
		return variables[value_name]
	else:
		make_error("Tried to get nonexistant value index: " + value_name)
		return null

func push_register(value):
	Scenescript.register_stack.push_back(value)
	
func pop_register():
	return Scenescript.register_stack.pop_back()

func go_to_id(id_name : String):
	if id_name in constants:
		current_node_index = constants[id_name] - 1
	else:
		make_error("Can't jump to id \"" + id_name + "\" because it doesn't exist.")

func go_to_index(index : int):
	if index < 0 or index > nodes.size():
		make_error("Can't jump to index because it's out of bounds.")
	current_node_index = index - 1

func do_action(action_name : String, run_if_not_running := false):
	if action_name in constants and nodes[constants[action_name]] is scenescript_node.action:
		var action_node := nodes[constants[action_name]] as scenescript_node.action
		action_node.return_index = current_node_index
		current_node_index = constants[action_name]
		if run_if_not_running and not is_running:
			step()
	else:
		make_error("Can't do action \"" + action_name + "\" because it doesn't exist or is not an action.")

func present_dialog(message : String):
	present_dialog_callback.call(message)
	end_step = true

func present_choice(choices : Array):
	#present_choice_callback.call(choices)
	
	var choice_names = []
	for choice in choices:
		if choice[2]:
			choice_names.push_back(language_reference_dictionary[choice[0]])
		else:choice_names.push_back(choice[0])
	
	present_choice_callback.call(choice_names)
	
	end_step = true

func select_choice(choice_index : int):
	if sub_process != null:
		sub_process.select_choice(choice_index)
		return
	current_node_index = (current_node as scenescript_node.choice).options[choice_index][1]

func deselect_actor():
	selected_actor = null
	deselect_actor_callback.call()

func make_error(message : String):
	has_process_error = true
	process_error_message = message
	error_signal.emit(message)
	push_error("Scenescript: " + message)

func get_timer(time : float) -> SceneTreeTimer:
	var timer : SceneTreeTimer = get_timer_callback.call(time)
#	if timer == null:
#		make_error("Proper get timer callback function was not provided.")
#		return null
	return timer
