class_name scenescript_node
extends Object

enum NodeType
{
	VARIABLE,
	VARIABLE_ASSIGNMENT,
	ACTOR_FUNCTION,
	SELECT_ACTOR,
	JUMP_POSITION,
	GOTO,
	IF_CONDITION,
	SAY,
	CHOICE,
	EXIT,
	BLOCK_START,
	BLOCK_END,
	LOOP,
	WAIT,
	PAUSE,
	SIGNAL_EMISSION,
	REGISTER,
	DEREGISTER,
	ACTION,
	RETURN,
	DO,
	RUN,
}

#const name : String = "node" #we're gonna use duck typing here
var index := -1
var disabled := false
var once := false
var has_run := false:
	set (value):
		if once: disabled = true
		has_run = value
	get:
		return has_run

func run(_process : scenescript_process):
	pass

#======================================

class variable_assignment:
	extends scenescript_node
	const name : String = "variable_assignment"
	var type := NodeType.VARIABLE_ASSIGNMENT
	
	var variable_identifier : String
	var is_actor_variable : bool
	var use_selected_actor : bool
	
	#empty for normal variables; 'global' or 'scene' puts them into respective special dictionaries
	#may also be an actor name
	var destination_name : String
	
	var expression : scenescript_expression
	
	func run(process : scenescript_process):
		if disabled: return
		has_run = true
		
		var value = expression.evaluate(process)
		if expression.has_evaluation_error:
			return
		
		if destination_name == "global":
			if variable_identifier not in Scenescript.global_vars:
				process.make_error("Tried to assign a nonexistant global variable: " + variable_identifier)
				return
				
			Scenescript.global_vars[variable_identifier] = value
		elif destination_name == "scene":
			if variable_identifier not in Scenescript.scene_vars:
				process.make_error("Tried to assign a nonexistant scene variable: " + variable_identifier)
				return
				
			Scenescript.scene_vars[variable_identifier] = value
		elif is_actor_variable:
			var actor : scenescript_actor
			
			if use_selected_actor:
				if process.selected_actor == null:
					process.make_error("Tried to assign a value onto the selected actor, which was null.")
					return
				actor = process.selected_actor
				
			elif destination_name not in Scenescript.scene_actors:
				process.make_error("Tried to assign a value onto a nonexistant actor: " + destination_name)
				return
				
			else:
				actor = Scenescript.scene_actors[destination_name]
			
			if variable_identifier not in actor:
				process.make_error("Variable name \"" + variable_identifier + "\" does not exist in actor: " + destination_name)
				return
			
			actor.set(variable_identifier, value)
			
		else:
			if variable_identifier not in process.variables:
				process.make_error("Tried to assign a nonexistant variable: " + variable_identifier)
				return
				
			process.variables[variable_identifier] = value
		
		#print("Set " + variable_identifier + " to " + str(value))

class select_actor:
	extends scenescript_node
	const name : String = "select_actor"
	var type := NodeType.SELECT_ACTOR
	
	var actor_name : String
	
	func run(process : scenescript_process):
		if disabled: return
		has_run = true
		
		if not actor_name in Scenescript.scene_actors:
			process.make_error("Actor named \"" + actor_name + "\" was not in scene actors.")
			return
		
		var actor : scenescript_actor = Scenescript.scene_actors[actor_name]
		process.selected_actor = actor
		actor.select(process)

class actor_function:
	extends scenescript_node
	const name : String = "actor_function"
	var type := NodeType.ACTOR_FUNCTION
	
	var actor_name : String
	var use_selected_actor : bool
	var function_name : String
	var function_expressions := []
	
	func run(process : scenescript_process):
		if disabled: return
		has_run = true
		
		if use_selected_actor:
			if process.selected_actor == null:
				process.make_error("Tried to call function on selected actor, which was null.")
				return
			
			actor_name = process.selected_actor.actor_name
		
		if not actor_name in Scenescript.scene_actors:
			process.make_error("Actor named \"" + actor_name + "\" was not in scene actors.")
			return
		
		var actor : scenescript_actor = Scenescript.scene_actors[actor_name]
		
		if not function_name in actor:
			process.make_error("Actor named \"" + actor_name + "\" does not have function \"" + function_name + "\".")
			return
		
		var function_values := []
		
		for expression in function_expressions:
			var value = expression.evaluate(process)
			if (expression as scenescript_expression).has_evaluation_error:
				return
			function_values.push_back(value)
		
		actor.callv(function_name, function_values)

class jump_position:
	extends scenescript_node
	const name : String = "jump_position"
	var type := NodeType.JUMP_POSITION
	
	var jump_position_name : String
	var jump_position_index : int

class goto:
	extends scenescript_node
	const name : String = "goto"
	var type := NodeType.GOTO
	
	var expression : scenescript_expression
	
	var jump_position_name : String #optional if the goto is not jumping to a pos node but rahter some arbitrary position
	var jump_position_index : int
	var skip_to_end_of_block : bool = false #if this is true, then the node at jump_position_index is a block_start node or choice node and we skip the entire block
	
	func run(process : scenescript_process):
		if disabled: return
		has_run = true
		
		if skip_to_end_of_block:
			var pointed_node : scenescript_node = process.nodes[jump_position_index]
			if pointed_node is block_start:
				process.current_node_index = pointed_node.closing_block_index
			elif pointed_node is choice:
				process.current_node_index = pointed_node.end_index
			return
		if expression == null:
			process.current_node_index = jump_position_index - 1 #process will advance to this position at next loop
		else:
			var result = expression.evaluate(process)
			if not (result is float):
				process.make_error("Goto has found a non-number expression.")
				return
			else:
				process.current_node_index = max(int(result) - 1, -1)

class if_condition:
	extends scenescript_node
	const name : String = "if_condition"
	var type := NodeType.IF_CONDITION
	
	var expression : scenescript_expression
	
	func run(process : scenescript_process):
		if not disabled:
			has_run = true
			
			var condition = expression.evaluate(process)
			if not (condition is bool):
				process.make_error("If condition's expression is non-boolean.")
				return
			
			if condition:
				return #move on to the next node
		
		var block_start_node : block_start = process.nodes[process.current_node_index + 1]
		process.current_node_index = block_start_node.closing_block_index

class exit:
	extends scenescript_node
	const name : String = "exit"
	var type := NodeType.EXIT

class variable:
	extends scenescript_node
	const name : String = "variable"
	var type := NodeType.VARIABLE
	var ignore_existing_variable_conflict = false
	
	var variable_name : String
	var destination_name : String #empty for normal variables; 'global' or 'scene' puts them into respective special dictionaries
	
	func run(process : scenescript_process):
		if disabled: return
		has_run = true
		
		if destination_name == "global":
			if (variable_name in Scenescript.global_vars and not ignore_existing_variable_conflict):
				process.make_error("Tried to re-initialize an already existing global variable: " + variable_name)
				return
			Scenescript.global_vars[variable_name] = null
		elif  destination_name == "scene":
			if (variable_name in Scenescript.scene_vars and not ignore_existing_variable_conflict):
				process.make_error("Tried to re-initialize an already existing scene variable: " + variable_name)
				return
			Scenescript.scene_vars[variable_name] = null
		else:
			if (variable_name in process.variables and not ignore_existing_variable_conflict) or variable_name in process.constants:
				process.make_error("Tried to re-initialize an already existing variable: " + variable_name)
				return
			process.variables[variable_name] = null

class say:
	extends scenescript_node
	const name : String = "say"
	var type := NodeType.SAY
	
	var expression : scenescript_expression
	var param_expressions := []
	var params_only := false #if this is true, the node just calls the say params callback and returns; this is used when source files are split into logic and langref files
	
	func run(process : scenescript_process):
		if disabled: return
		has_run = true
		
		if Scenescript.use_say_params and param_expressions.size() > 0:
			
			var param_values := []
			
			for param_expression in param_expressions:
				var value = param_expression.evaluate(process)
				if param_expression.has_evaluation_error:
					return
				param_values.push_back(value)
			
			process.handle_say_params_callback.call(param_values)
			
			if params_only:
				return
		
		
		if expression.expression_tokens.size() == 0: #will be read as param only, but just in case
			return
		
		var result = expression.evaluate(process)
		if expression.has_evaluation_error:
			return
			
		process.present_dialog(str(result))
	
#	func extract_say_params(message : String, process : scenescript_process):
#		if message[0] != '{':
#			if message.length() > 1 and message[0] == '\\' and message[1] == '{':
#				return message.substr(1)
#			return message
#
#		var raw_params := []
#
#		var current_character_index := 0
#		while message[current_character_index] != '}':
#			var raw_expression := ""
#			while  message[current_character_index] != ',' and message[current_character_index] != '}':
#				current_character_index += 1
#
#				if current_character_index >= message.length():
#					process.make_error("Opening brace for say parameters did not have a closing brace.")
#					return null
#
#				raw_expression += message[current_character_index]
#
#			if message[current_character_index] == ',':
#				current_character_index += 1
#
#			raw_params.push_back(raw_expression)
#
#
#		var expressions := []
#		var tokenizer := scenescript_tokenizer.new()
#
#		for param_code in raw_params:
#			tokenizer.source_code = param_code
#			var tokens := tokenizer.tokenize()
#			if tokenizer.has_token_error:
#				return null
#
#			var param_expression := scenescript_expression.new()
#			param_expression.expression_tokens = tokens
#			expressions.push_back(param_expression)
#
#		expressions.push_back(message.substr(current_character_index))
#		return expressions

class block_start:
	extends scenescript_node
	const name : String = "block_start"
	var type := NodeType.BLOCK_START
	
	var closing_block_index : int

class block_end:
	extends scenescript_node
	const name : String = "block_end"
	var type := NodeType.BLOCK_END
	
	var starting_block_index : int

class choice:
	extends scenescript_node
	const name : String = "choice"
	var type := NodeType.CHOICE
	
	var options := [] #array of arrays; sub arrays are [String (choice text / md5), int, bool (if we use langref or not)]
	var end_index : int
	
	func run(process : scenescript_process):
		if disabled:
			process.current_node_index = end_index #skip say block
		has_run = true
		
		process.present_choice(options)

class loop:
	extends scenescript_node
	const name : String = "loop"
	var type := NodeType.LOOP
	
	var expression : scenescript_expression
	var num_loops := 0
	
	func run(process : scenescript_process):
		var block_start_node : block_start = process.nodes[process.current_node_index + 1]
		if disabled or num_loops < 0: #skip to end
			process.current_node_index = block_start_node.closing_block_index + 1 #we add the 1 to skip over the goto node after the block end
		
		if num_loops > 0:
			num_loops -= 1
			if num_loops == 0:
				process.current_node_index = block_start_node.closing_block_index + 1
		elif expression != null:
			var result = expression.evaluate(process)
			if result is float:
				num_loops = int(result)
			elif result is bool and result == false:
				process.current_node_index = block_start_node.closing_block_index + 1

class pause:
	extends scenescript_node
	const name : String = "pause"
	var type := NodeType.PAUSE
	
	func run(process : scenescript_process):
		if disabled:
			return
		process.end_step = true

class wait:
	extends scenescript_node
	const name : String = "wait"
	var type := NodeType.WAIT
	
	var expression : scenescript_expression
	
	func run(process : scenescript_process):
		if disabled:
			return
		
		var result = expression.evaluate(process)
		if expression.has_evaluation_error:
			return
		
		if not (result is float):
			process.make_error("Wait node expression is not numeric.")
		
		var timer : SceneTreeTimer = process.get_timer(result)
		#right now we're just calling the step() function again in process
		#but it might be better to make sure the process can't be continued by something else?
		
		process.end_step = true
		await timer.timeout
		
		if not process.is_running:
			process.step()
		else:
			process.make_error("Process was waiting for wait node, but was resumed by something else.")

class signal_emission:
	extends scenescript_node
	const name : String = "signal_emission"
	var type := NodeType.SIGNAL_EMISSION
	
	var expression : scenescript_expression
	
	func run(process : scenescript_process):
		if disabled:
			return
		
		var result = expression.evaluate(process)
		if expression.has_evaluation_error:
			return
		
		process.emit_signal("node_signal", result)

class register:
	extends scenescript_node
	const name : String = "register"
	var type := NodeType.REGISTER
	
	var expression : scenescript_expression
	
	func run(process : scenescript_process):
		if disabled:
			return
			
		var result = expression.evaluate(process)
		if expression.has_evaluation_error:
			return
		process.push_register(result)

class deregister:
	extends scenescript_node
	const name : String = "deregister"
	var type := NodeType.DEREGISTER
	
	func run(process : scenescript_process):
		if disabled:
			return
		
		if Scenescript.register_stack.size() == 0:
			process.make_error("Tried to deregister when the register is empty.")
		
		process.pop_register()
		
class action:
	extends scenescript_node
	const name : String = "action"
	var type := NodeType.ACTION
	
	var action_name : String
	var return_index : int = -1
	
	func run(process : scenescript_process):
		#when we encounter an action node, it means we've advanced to it normally without jumping into it (from do)
		#in that case, we want to skip over the code and go to the end
		#so the action node should always prevent you from advancing to the action body
		
		var block_start_node : block_start = process.nodes[index + 1]
		process.current_node_index = block_start_node.closing_block_index + 1 #add one to skip return node after block end

class action_return:
	extends scenescript_node
	const name : String = "action return"
	var type := NodeType.RETURN
	
	var action_node_index : int
	
	func run(process : scenescript_process):
		if disabled:
			return
		
		var action_node : action = process.nodes[action_node_index]
		process.current_node_index = action_node.return_index
		
class do_action:
	extends scenescript_node
	const name : String = "do action"
	var type := NodeType.DO
	
	var action_name : String
	
	func run(process : scenescript_process):
		if disabled:
			return
		
		if process == null:
			process.make_error("Encountered a do action node without a provided process.")
			return
		
		if action_name in process.constants.keys():
			var action_node : action = process.nodes[process.constants[action_name]]
			action_node.return_index = index
			process.current_node_index = action_node.index
		else:
			process.make_error("Tried to do action '" + action_name + "' which doesn't exist.")
			return

#todo: memory leak risk here?
class run_file:
	extends scenescript_node
	const name : String = "run file"
	var type := NodeType.RUN
	
	var file_path = ""
	
	func run(process : scenescript_process):
		if disabled:
			return
		
		if not FileAccess.file_exists(file_path):
			process.make_error("Run node - file does not exist at: " + file_path)
			return
		
		#file runs in its own self-contained process
		
		for process_name in process.parent_process_names:
			if process_name == file_path:
				process.make_error("Run node - can't run file due to cyclic dependency: " + process_name)
				return
		
		var sub_process := scenescript_process.new()
		sub_process.load_file(file_path)
		
		sub_process.get_timer_callback = process.get_timer_callback
		sub_process.present_choice_callback = process.present_choice_callback
		sub_process.present_dialog_callback = process.present_dialog_callback
		
		sub_process.parent_process_names = process.parent_process_names.duplicate()
		sub_process.parent_process_names.append(process.process_name)
		
		for connection in process.node_signal.get_connections():
			sub_process.node_signal.connect(connection["callable"], connection["flags"])
		
		process.sub_process = sub_process
		sub_process.finished.connect(func():
			process.sub_process = null
			
			for c in sub_process.node_signal.get_connections():
				sub_process.node_signal.disconnect(c["callable"])
				
			for c in sub_process.finished.get_connections():
				sub_process.finished.disconnect(c["callable"])
			
			process.step()
			)
			
		
		sub_process.step()

#class node_template:
#	extends scenescript_node
#	const name : String = ""
#	var type := NodeType.
#	func run(process : scenescript_process):
#		if disabled:
#			return
