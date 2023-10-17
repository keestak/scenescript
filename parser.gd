#todo: clean up some duplicated code (like making expression object using parsed expression tokens from parse_expression())
#and also can remove a lot of parse_x functions and consolidate them into a single multi purpose function

class_name scenescript_parser
extends RefCounted

var nodes : Array[scenescript_node]
var pending_nodes : Array[scenescript_node]

var tokens : Array[scenescript_token]
var current_token : scenescript_token
var current_token_index := -1

#NOTE: these two dictionaries can't have name conflicts but that's not dealt with right now, so TODO fix that
var jump_positions := {} #goto nodes will map to jump positions in here if they exist {name; index}
var actions := {} #to go to process constants like above

var pending_gotos := {} #gotos without a matching jump position sit in here for the jump position to be added {jump name; goto node array}
var pending_block_begins := [] #waiting to be closed by a block_end

var indent_level := 0
var expect_indent := false
var pending_choice_stack = [] #array of choice nodes that are awaiting the choice options
var pending_choice_indent_levels = [] #array of ints that correspond to the indent levels in the choice stack

var dedent_handler_stack = [] #stack of callable functions that handles dedents for various nodes. number of elements is number of indents.

var has_parse_error := false
var parse_error_string := ""
var print_debug_info := false

var once_enabled := false #if this is on, the 'once' property of the next added node is set to false, meaning it will only run once

func parse() -> Array[scenescript_node]:
	if tokens.size() == 0:
		make_error("Tokens array is empty.")
		return []
	
	current_token_index = -1
	while not is_at_end():
		while pending_nodes.size() > 0:
			add_node(pending_nodes.pop_front())
		
		advance()
		
		var node : scenescript_node
		
		match current_token.type:
			
			#IGNORED FOR NOW.
			#Not sure how easy these will be to implement and how much they will complicate things
			#So for the sake of keeping things simple I will avoid implementing these functions until necessary
			#------------------------------------------------------
			scenescript_token.TokenType.AWAIT: #suspension (wait for coroutine / child process to finish)
				make_error("Unimplemented")
			scenescript_token.TokenType.ALIAS: #
				make_error("Unimplemented")
			scenescript_token.TokenType.COROUTINE: #define a coroutine (don't forget about named coroutines!)
				make_error("Unimplemented")
			scenescript_token.TokenType.START_COROUTINE: #start a coroutine
				make_error("Unimplemented")
			#------------------------------------------------------
			
			scenescript_token.TokenType.IDENTIFIER: #variable assignment
				node = parse_assignment()
			scenescript_token.TokenType.AT: #actor reference (may be actor selection, may be getting value from actor, or may be calling function on actor)
				node = parse_actor_reference()
			scenescript_token.TokenType.DOT: #calling function on selected actor
				node = parse_actor_reference()
			scenescript_token.TokenType.SELECT: #actor selection
				node = parse_select_actor()
			scenescript_token.TokenType.ID: #script section id
				node = parse_jump_position()
			scenescript_token.TokenType.ID: #jump position
				node = parse_jump_position()
			scenescript_token.TokenType.GOTO: #jump goto
				node = parse_goto()
			scenescript_token.TokenType.IF: #conditional
				node = parse_if()
			scenescript_token.TokenType.EXIT: #termination
				node = parse_exit()
			scenescript_token.TokenType.VAR: #variable
				node = parse_var()
			scenescript_token.TokenType.LOOP: #looping; if not provided with anything then it's an infinite loop, if it's provided with a number then it will loop that many (int) times, and loop while a boolean expression is true
				node = parse_loop()
			scenescript_token.TokenType.WAIT: #suspension
				node = parse_wait()
			scenescript_token.TokenType.PAUSE: #suspension
				node = parse_pause()
			scenescript_token.TokenType.SAY: #say statement / block
				node = parse_say()
			scenescript_token.TokenType.SIGNAL: #emit signal
				node = parse_signal()
			scenescript_token.TokenType.REGISTER: #register a value
				node = parse_register()
			scenescript_token.TokenType.DEREGISTER: #deregister signal
				node = parse_deregister()
			scenescript_token.TokenType.ACTION: #repeatable actions
				node = parse_action()
			scenescript_token.TokenType.DO: #call an action
				node = parse_do()
			scenescript_token.TokenType.SCENE: #declare a scene variable
				node = parse_scene_or_global_var()
			scenescript_token.TokenType.GLOBAL: #declare a global variable
				node = parse_scene_or_global_var()
			scenescript_token.TokenType.RUN: #execute other script by file name
				node = parse_run()
			scenescript_token.TokenType.CHOICE: #multi-choice
				node = parse_choice()
			scenescript_token.TokenType.INDENT: #begin block
				if not expect_indent and not is_in_choice_block():
					make_error("Encounted indent when not expecting one.")
					return []
				elif  expect_indent: expect_indent = false
				node = parse_indent()
			scenescript_token.TokenType.DEDENT: #end block
				node = parse_dedent()
			scenescript_token.TokenType.NEWLINE: #whitespace, do nothing
				pass
			scenescript_token.TokenType.ONCE: #set the once flag on the next node
				once_enabled = true
			scenescript_token.TokenType.LITERAL: #only time we should encounter this is in a choice block, where it is an option
				if is_in_choice_block():
					if peek_next().type != scenescript_token.TokenType.COLON:
						make_error("Expected a colon after literal option in choice block, but found " + scenescript_token.token_names[peek_next().type] + ".")
					else:
						(pending_choice_stack.back() as scenescript_node.choice).options.append([current_token.value, nodes.size(), false])
						advance() #consume literal
						advance() #consume colon
				else:
					make_unexpected_token_error()
			scenescript_token.TokenType.LANGREF: #same as above, only time we should encounter this is in a choice block, where it is an option
				if is_in_choice_block():
					if peek_next().type != scenescript_token.TokenType.LITERAL:
						make_error("Expected a literal after langref option in choice block, but found " + scenescript_token.token_names[peek_next().type] + ".")
					else:
						advance() #consume langref
						(pending_choice_stack.back() as scenescript_node.choice).options.append([current_token.value, nodes.size(), true])
						advance() #consume literal
						advance() #consume colon
				else:
					make_unexpected_token_error()
			scenescript_token.TokenType.END_OF_FILE: #termination
				node = parse_eof()
			_:
				make_unexpected_token_error()
		
		if node == null:
			pass
			#make_error("Unimplemented token: " + scenescript_token.token_names[current_token.type])
			#return
		else:
			add_node(node)
		if has_parse_error:
			return []
	return nodes

func add_node(node : scenescript_node):
	if node is scenescript_node.block_start:
		indent_level += 1
		if dedent_handler_stack.size() < indent_level:
			dedent_handler_stack.push_back(null)
	elif node is scenescript_node.block_end:
		indent_level -= 1
		var handler = dedent_handler_stack[indent_level]
		if handler != null:
			(handler as Callable).call(node)
		else:
			dedent_handler_stack.pop_back()
	
	
	if once_enabled:
		node.once = true
		once_enabled = false

	node.index = nodes.size()
	nodes.push_back(node)
	
	if print_debug_info:
		print(str(nodes.size() - 1).rpad(5) + " " + str(node.name) + (" (once)" if node.once else ""))

func advance():
	current_token_index += 1
	if is_at_end():
		current_token = null
	else: current_token = tokens[current_token_index]

func peek_next() -> scenescript_token:
	if current_token_index + 1 == tokens.size(): return null
	return tokens[current_token_index + 1]

func is_at_end() -> bool:
	if current_token_index < 0: return false
	return current_token_index >= tokens.size()

func is_in_choice_block() -> bool: return pending_choice_indent_levels.back() == indent_level

func expect(type : scenescript_token.TokenType) -> bool:
	if current_token.type == type:
		return true
	make_unexpected_token_error(type)
	return false

#func skip_trailing_indents():
#	while current_token.type == scenescript_token.TokenType.INDENT:
#		advance()

# ========== parsing ========== 

func parse_assignment(destination_name : String = "") -> scenescript_node.variable_assignment:
	if not expect(scenescript_token.TokenType.IDENTIFIER): return null
	var identifier_string = current_token.value
	advance()
	if not expect(scenescript_token.TokenType.EQUAL): return null
	advance()
	
	var expression_tokens = parse_expression()
	var expression := scenescript_expression.new()
	expression.expression_tokens = expression_tokens
	
	if not expect(scenescript_token.TokenType.NEWLINE): return null
	
	var node := scenescript_node.variable_assignment.new()
	node.variable_identifier = identifier_string
	node.expression = expression
	node.destination_name = destination_name
	return node

func parse_expression() -> Array[scenescript_token]:
	var expression_tokens : Array[scenescript_token] = []
	var nest_level := 0
	var finished := false
	
	while current_token.type != scenescript_token.TokenType.NEWLINE and current_token.type != scenescript_token.TokenType.COLON and current_token.type != scenescript_token.TokenType.COMMA:
		
		match current_token.type:
			#math
			scenescript_token.TokenType.PLUS:
				expression_tokens.push_back(current_token)
			scenescript_token.TokenType.MINUS:
				expression_tokens.push_back(current_token)
			scenescript_token.TokenType.SLASH:
				expression_tokens.push_back(current_token)
			scenescript_token.TokenType.STAR:
				expression_tokens.push_back(current_token)
			scenescript_token.TokenType.PERCENT:
				expression_tokens.push_back(current_token)
			#logical
			scenescript_token.TokenType.AND:
				expression_tokens.push_back(current_token)
			scenescript_token.TokenType.OR:
				expression_tokens.push_back(current_token)
			#comparison
			scenescript_token.TokenType.LESS:
				expression_tokens.push_back(current_token)
			scenescript_token.TokenType.LESS_EQUAL:
				expression_tokens.push_back(current_token)
			scenescript_token.TokenType.GREATER:
				expression_tokens.push_back(current_token)
			scenescript_token.TokenType.GREATER_EQUAL:
				expression_tokens.push_back(current_token)
			scenescript_token.TokenType.DOUBLE_EQUAL:
				expression_tokens.push_back(current_token)
			scenescript_token.TokenType.NOT_EQUAL:
				expression_tokens.push_back(current_token)
			#values
			scenescript_token.TokenType.UNDERSCORE:
				expression_tokens.push_back(current_token)
			scenescript_token.TokenType.IDENTIFIER:
				expression_tokens.push_back(current_token)
			scenescript_token.TokenType.DEREGISTER:
				expression_tokens.push_back(current_token)
			scenescript_token.TokenType.LITERAL:
				expression_tokens.push_back(current_token)
			scenescript_token.TokenType.NUMBER:
				expression_tokens.push_back(current_token)
			scenescript_token.TokenType.BOOL:
				expression_tokens.push_back(current_token)
			#special
			scenescript_token.TokenType.SCENE:
				expression_tokens.push_back(current_token)
			scenescript_token.TokenType.GLOBAL:
				expression_tokens.push_back(current_token)
			scenescript_token.TokenType.AT:
				expression_tokens.push_back(current_token)
			scenescript_token.TokenType.DOT:
				expression_tokens.push_back(current_token)
			scenescript_token.TokenType.LANGREF:
				expression_tokens.push_back(current_token)
			#parenthesis
			scenescript_token.TokenType.PAREN_OPEN:
				expression_tokens.push_back(current_token)
				nest_level += 1
			scenescript_token.TokenType.PAREN_CLOSE:
				if nest_level == 0: #if everything's correct, we've reached the end of the expression and the next parenthesis is enclosing the expression
					finished = true
					break
				expression_tokens.push_back(current_token)
				nest_level -= 1
			#negation
			scenescript_token.TokenType.NOT:
				expression_tokens.push_back(current_token)
			#error
			_:
				make_unexpected_token_error()
				return expression_tokens
		
		if finished: break
		
		advance()
	
	if nest_level != 0:
		make_error("Invalid expression found during parsing; unbalanced parenthesis.")
	
	return expression_tokens

func parse_actor_reference():
	
	var use_selected_actor := false
	var actor_name := ""
	
	if current_token.type == scenescript_token.TokenType.DOT:
		use_selected_actor = true
	else:
		if not expect(scenescript_token.TokenType.AT): return null
		advance()
		
		if current_token.type == scenescript_token.TokenType.UNDERSCORE:
			var node := scenescript_node.select_actor.new()
			node.actor_name = ""
			return node
		
		if current_token.type != scenescript_token.TokenType.IDENTIFIER and current_token.type != scenescript_token.TokenType.LITERAL:
			make_error("Unexpected token: " + scenescript_token.token_names[current_token.type] + "\n(expected either identifier or literal)")
			return null
		actor_name = str(current_token.value)
		advance()
		
		if current_token.type == scenescript_token.TokenType.NEWLINE: #actor selection
			var node := scenescript_node.select_actor.new()
			node.actor_name = actor_name
			return node
	
	#otherwise calling a function on the actor or setting a value
	if not expect(scenescript_token.TokenType.DOT): return null
	advance()
	if not expect(scenescript_token.TokenType.IDENTIFIER): return null
	var function_or_member_name = current_token.value
	advance()
	
	#calling a function
	if current_token.type == scenescript_token.TokenType.PAREN_OPEN:
		advance()
		
		var expressions = []
		
		while current_token.type != scenescript_token.TokenType.PAREN_CLOSE:
			while current_token.type != scenescript_token.TokenType.COMMA:
				
				var expression_tokens := parse_expression()
				if has_parse_error:
					return null
				var expression := scenescript_expression.new()
				expression.expression_tokens = expression_tokens
				expressions.push_back(expression)
				
				if current_token.type == scenescript_token.TokenType.PAREN_CLOSE:
					break
				advance()
		
		if not expect(scenescript_token.TokenType.PAREN_CLOSE): return null
		advance()
		if not expect(scenescript_token.TokenType.NEWLINE): return null
		
		var node := scenescript_node.actor_function.new()
		node.actor_name = actor_name
		node.function_name = function_or_member_name
		node.function_expressions = expressions
		node.use_selected_actor = use_selected_actor
		
		return node
	
	else: #setting a value
		if not expect(scenescript_token.TokenType.EQUAL): return null
		advance()
		
		var expression_tokens := parse_expression()
		if has_parse_error:
			return null
		var expression := scenescript_expression.new()
		expression.expression_tokens = expression_tokens
		
		var node := scenescript_node.variable_assignment.new()
		node.is_actor_variable = true
		node.expression = expression
		node.variable_identifier = function_or_member_name
		node.destination_name = actor_name
		node.use_selected_actor = use_selected_actor
		
		return node

func parse_select_actor() -> scenescript_node.select_actor:
	if not expect(scenescript_token.TokenType.SELECT): return null
	advance()
	if current_token.type != scenescript_token.TokenType.IDENTIFIER and current_token.type != scenescript_token.TokenType.LITERAL:
		make_error("Unexpected token: " + scenescript_token.token_names[current_token.type] + "\n(expected either identifier or literal)")
		return null
	var actor_name = str(current_token.value)
	
	var node := scenescript_node.select_actor.new()
	node.actor_name = actor_name
	
	advance()
	if not expect(scenescript_token.TokenType.NEWLINE): return null
	
	return node

func parse_jump_position() -> scenescript_node.jump_position:
	if not expect(scenescript_token.TokenType.ID): return null
	advance()
	if not expect(scenescript_token.TokenType.IDENTIFIER): return null
	
	var node := scenescript_node.jump_position.new()
	node.jump_position_name = current_token.value
	node.jump_position_index = nodes.size()
	
	if node.jump_position_name in jump_positions:
		make_error("Redeclaration of jump position '" + node.jump_position_name + "'.")
		return node
	else:
		jump_positions[node.jump_position_name] = node
		
		if node.jump_position_name in pending_gotos:
			for pending in pending_gotos[node.jump_position_name]:
				(pending as scenescript_node.goto).jump_position_index = node.jump_position_index
			pending_gotos.erase(node.jump_position_name)
	
	advance()
	if not expect(scenescript_token.TokenType.NEWLINE): return null
	
	return node

func parse_goto() -> scenescript_node.goto:
	if not expect(scenescript_token.TokenType.GOTO): return null
	advance()
	
	var node = scenescript_node.goto.new()
	
	if current_token.type != scenescript_token.TokenType.IDENTIFIER:
		
		var expression := scenescript_expression.new()
		expression.expression_tokens = parse_expression()
		
		if has_parse_error:
			return null
		
		node.expression = expression
		
	else:
	
		node.jump_position_name = current_token.value
		
		if node.jump_position_name in jump_positions.keys():
			node.jump_position_index = (jump_positions[node.jump_position_name] as scenescript_node.jump_position).jump_position_index
		else:
			if node.jump_position_name in pending_gotos.keys():
				(pending_gotos[node.jump_position_name] as Array).append(node)
			else:
				pending_gotos[node.jump_position_name] = [node]
	
		advance()
		
	if not expect(scenescript_token.TokenType.NEWLINE): return null
	
	return node

func parse_if() -> scenescript_node.if_condition:
	if not expect(scenescript_token.TokenType.IF): return null
	advance()
	
	var expression_tokens := parse_expression()
	var expression := scenescript_expression.new()
	expression.expression_tokens = expression_tokens
	
	if has_parse_error:
		return null
	if not expect(scenescript_token.TokenType.COLON): return null
	advance()
	
	if not expect(scenescript_token.TokenType.NEWLINE): return null
	
	if peek_next().type != scenescript_token.TokenType.INDENT:
		make_error("Expected an indent after colon succeeding an if token, but instead got " + scenescript_token.token_names[peek_next().type] + ".")
		return null
	expect_indent = true
	
	var node := scenescript_node.if_condition.new()
	node.expression = expression
	return node

func parse_exit() -> scenescript_node.exit:
	if not expect(scenescript_token.TokenType.EXIT): return null
	advance()
	if not expect(scenescript_token.TokenType.NEWLINE): return null
	
	return scenescript_node.exit.new()

func parse_pause() -> scenescript_node.pause:
	if not expect(scenescript_token.TokenType.PAUSE): return null
	advance()
	if not expect(scenescript_token.TokenType.NEWLINE): return null
	
	return scenescript_node.pause.new()

func parse_wait() -> scenescript_node.wait:
	if not expect(scenescript_token.TokenType.WAIT): return null
	advance()
	
	var expression_tokens := parse_expression()
	var expression := scenescript_expression.new()
	expression.expression_tokens = expression_tokens
	
	if has_parse_error:
		return null
	
	if not expect(scenescript_token.TokenType.NEWLINE): return null
	
	var node := scenescript_node.wait.new()
	node.expression = expression
	return node

func parse_eof() -> scenescript_node.exit:
	if peek_next() != null:
		make_error("End of file isn't the last token.")
		return null
	if not expect(scenescript_token.TokenType.END_OF_FILE): return null
	advance()
	
	return scenescript_node.exit.new()

func parse_var(destination := "") -> scenescript_node.variable:
	if not expect(scenescript_token.TokenType.VAR): return null
	advance()
	if not expect(scenescript_token.TokenType.IDENTIFIER): return null
	
	var node = scenescript_node.variable.new()
	node.variable_name = current_token.value
	node.destination_name = destination
	advance() #consume identifier
	
	if current_token.type == scenescript_token.TokenType.EQUAL: #assignment
		advance() #consume equal
		var expression_tokens := parse_expression()
		var expression := scenescript_expression.new()
		expression.expression_tokens = expression_tokens
		
		var assignment_node = scenescript_node.variable_assignment.new()
		assignment_node.variable_identifier = node.variable_name
		assignment_node.expression = expression
		assignment_node.once = once_enabled
		assignment_node.destination_name = destination
		pending_nodes.push_back(assignment_node)
	
	if not expect(scenescript_token.TokenType.NEWLINE): return null
	
	return node

func parse_say() -> scenescript_node.say:
	if not expect(scenescript_token.TokenType.SAY): return null
	advance()
	
	var node := scenescript_node.say.new()
	
	if current_token.type == scenescript_token.TokenType.COLON: #say block
		advance() #consume colon
		if not expect(scenescript_token.TokenType.NEWLINE): return null
		advance() #consume newline
		if not expect(scenescript_token.TokenType.INDENT): return null
		#pending_nodes.append(parse_indent())
		indent_level += 1
		advance()
		while(true):
			if current_token.type == scenescript_token.TokenType.DEDENT: #say block dedent
				#pending_nodes.append(parse_dedent(true))
				indent_level -= 1
				break
			else:
				var param_expressions = null
				if current_token.type == scenescript_token.TokenType.BRACE_OPEN: #say params
					if has_parse_error:
						return null
					param_expressions = parse_say_param_expressions()
				
				#======= OLD CODE FOR WHEN SAY BLOCK TEXT WAS ALL TOKENS INSTEAD OF SINGLE LITERAL (GROSS)
				#we need to put all the next tokens up to the newline into a string literal token, and use that as our expression tokens
#				if current_token.type == scenescript_token.TokenType.LITERAL and current_token.value in [' ', '\t', '\r']:
#					advance()
#
#				var literal_token := scenescript_token.new()
#				literal_token.type = scenescript_token.TokenType.LITERAL
#				literal_token.value = ""
#
#				var say_block_node := scenescript_node.say.new()
#				if once_enabled: say_block_node.once = true
#
#				var is_escaping := false
#				while current_token.type != scenescript_token.TokenType.NEWLINE:
#					var token_string = str(current_token.value)
#
#					if is_escaping:
#						match token_string[0]:
#							"n":
#								literal_token.value += "\n"
#							"t":
#								literal_token.value += "\t"
#							"r":
#								literal_token.value += "\r"
#							"\\":
#								literal_token.value += "\\"
#							_:
#								make_error("Escaping unknown token value \"" + token_string[0] + "\" when parsing say block line.")
#						token_string = token_string.substr(1)
#						is_escaping = false
#					elif token_string == '\\':
#						is_escaping = true
#						token_string = ""
#
#					#we need to add the quotes back in
#					#TODO: doing it this way means that the literals a and "a" will be indistinguishable, and "a" will be shown without quotes.
#					#so we need to fix that... somehow. my best guess is to use a new "CHARACTER_LITERAL" token for single characters to fix this issue?
#					if current_token.type == scenescript_token.TokenType.LITERAL and token_string.length() > 1:
#						token_string = '"' + token_string + '"'
#
#					literal_token.value += token_string
#					advance()
				#=======
				
				if not expect(scenescript_token.TokenType.LITERAL): return null
				
				var literal_token := current_token

				var say_block_node := scenescript_node.say.new()
				if once_enabled: say_block_node.once = true
				
				say_block_node.expression = scenescript_expression.new()
				say_block_node.expression.expression_tokens = [literal_token]
				if param_expressions != null:
					say_block_node.param_expressions = param_expressions
				
				pending_nodes.append(say_block_node)
				advance()
				if not expect(scenescript_token.TokenType.NEWLINE): return null
				advance()
				
				#make_unexpected_token_error()
		return null #all say nodes are appended to pending nodes 
	else: #single say expression
		if current_token.type == scenescript_token.TokenType.BRACE_OPEN: #say params
			if has_parse_error:
				return null
			node.param_expressions = parse_say_param_expressions()
		#expression
		var expression_tokens = parse_expression()
		if has_parse_error:
			return null
		
		node.expression = scenescript_expression.new()
		if expression_tokens.size() == 0:
			node.params_only = true
		else:
			node.expression.expression_tokens = expression_tokens
	
	if not expect(scenescript_token.TokenType.NEWLINE):
		return null
	
	return node

func parse_say_param_expressions():
	if not expect(scenescript_token.TokenType.BRACE_OPEN): return null
	advance()
	
	var param_expressions := []
	
	while true:
		var expression = scenescript_expression.new()
		while current_token.type != scenescript_token.TokenType.COMMA and current_token.type != scenescript_token.TokenType.BRACE_CLOSE:
			if current_token.value not in [' ', '\t', '\r']:
				expression.expression_tokens.push_back(current_token)
			advance()
		
		param_expressions.push_back(expression)
		
		if current_token.type == scenescript_token.TokenType.COMMA:
			advance()
		elif current_token.type == scenescript_token.TokenType.BRACE_CLOSE:
			break
		elif current_token.type != scenescript_token.TokenType.NEWLINE:
			make_error("Missing closing brace while parsing say params.")
			return null
	
	advance() #consume closing brace
	
	return param_expressions

func parse_choice() -> scenescript_node.choice:
	if not expect(scenescript_token.TokenType.CHOICE): return null
	advance()
	if not expect(scenescript_token.TokenType.COLON): return null
	advance()
	
	while peek_next().type == scenescript_token.TokenType.NEWLINE:
		advance()
	
	if peek_next().type != scenescript_token.TokenType.INDENT:
		make_error("Expected an indent after colon succeeding a choice token, but instead got " + scenescript_token.token_names[peek_next().type] + ".")
		return null
	
	expect_indent = true
	
	var node = scenescript_node.choice.new()
	pending_choice_stack.push_back(node)
	pending_choice_indent_levels.push_back(indent_level + 1)
	
	var individual_choice_handler := func(_end_block_node : scenescript_node):
		var goto_node := scenescript_node.goto.new()
		goto_node.skip_to_end_of_block = true
		goto_node.jump_position_index = node.index
		pending_nodes.push_back(goto_node)
	
	var choice_block_handler := func(_end_block_node : scenescript_node):
		dedent_handler_stack.pop_back() #remove individual choice function
		dedent_handler_stack.pop_back() #remove this function
		node.end_index = _end_block_node.index
	
	dedent_handler_stack.push_back(choice_block_handler)
	dedent_handler_stack.push_back(individual_choice_handler)
	
	return node

func parse_indent() -> scenescript_node.block_start:
	if not expect(scenescript_token.TokenType.INDENT): return null
	var node := scenescript_node.block_start.new()
	pending_block_begins.append(node)
	return node

func parse_dedent(is_pending := false) -> scenescript_node.block_end:
	if not expect(scenescript_token.TokenType.DEDENT): return null
	if pending_block_begins.size() == 0:
		make_error("Encountered a dedent token without a corresponding indent.")
		return null
	
	var node := scenescript_node.block_end.new()
	node.index = nodes.size() + (pending_nodes.size() if is_pending else 0)
	var starting_block : scenescript_node.block_start = pending_block_begins.pop_back()
	starting_block.closing_block_index = node.index
	node.starting_block_index = starting_block.index
	
	return node

func parse_loop() -> scenescript_node.loop:
	if not expect(scenescript_token.TokenType.LOOP): return null
	advance()
	
	var node := scenescript_node.loop.new()
	
	if current_token.type != scenescript_token.TokenType.COLON:
		#expect expression
		var expression := scenescript_expression.new()
		expression.expression_tokens = parse_expression()
		if has_parse_error:
			return null
		node.expression = expression
	
	if not expect(scenescript_token.TokenType.COLON): return null
	advance()
	while peek_next().type == scenescript_token.TokenType.NEWLINE:
		advance()
	
	if peek_next().type != scenescript_token.TokenType.INDENT:
		make_error("Expected an indent after colon succeeding a loop token, but instead got " + scenescript_token.token_names[peek_next().type] + ".")
		return null
	
	expect_indent = true
	
	#create a goto node after dedent, set the goto index to the index of the block start, and push it onto pending nodes
	var indent_index = nodes.size()
	var dedent_handler := func(_block_end_node):
		var goto := scenescript_node.goto.new()
		goto.jump_position_index = indent_index
		pending_nodes.push_back(goto)
		dedent_handler_stack.pop_back() #remove this function
	
	dedent_handler_stack.push_back(dedent_handler)
	
	return node

func parse_signal():
	if not expect(scenescript_token.TokenType.SIGNAL): return null
	advance()
	
	var expression_tokens := parse_expression()
	var expression := scenescript_expression.new()
	expression.expression_tokens = expression_tokens
	
	if has_parse_error:
		return null
	
	if not expect(scenescript_token.TokenType.NEWLINE): return null
	
	var node := scenescript_node.signal_emission.new()
	node.expression = expression
	return node

func parse_register():
	if not expect(scenescript_token.TokenType.REGISTER): return null
	advance()
	
	var expression_tokens := parse_expression()
	var expression := scenescript_expression.new()
	expression.expression_tokens = expression_tokens
	
	if has_parse_error:
		return null
	
	if not expect(scenescript_token.TokenType.NEWLINE): return null
	
	var node := scenescript_node.register.new()
	node.expression = expression
	return node

func parse_deregister():
	if not expect(scenescript_token.TokenType.DEREGISTER): return null
	advance()
	if not expect(scenescript_token.TokenType.NEWLINE): return null
	
	return scenescript_node.deregister.new()

func parse_action():
	if not expect(scenescript_token.TokenType.ACTION): return null
	advance()
	
	if not expect(scenescript_token.TokenType.IDENTIFIER): return null
	var action_name = current_token.value
	advance()
	
	if not expect(scenescript_token.TokenType.COLON): return null
	advance()
	
	if not expect(scenescript_token.TokenType.NEWLINE): return null
	
	if peek_next().type != scenescript_token.TokenType.INDENT:
		make_error("Expected an indent after colon succeeding an action token, but instead got " + scenescript_token.token_names[peek_next().type] + ".")
		return null
	expect_indent = true
	
	if action_name in actions.keys():
		make_error("Action '" + action_name + "' was already declared.")
		return null
	
	var action_node := scenescript_node.action.new()
	action_node.action_name = action_name
	actions[action_name] = action_node
	
	var action_body_dedent_handler = func(_block_end_node):
		dedent_handler_stack.pop_back()
		
		var return_node := scenescript_node.action_return.new()
		return_node.action_node_index = action_node.index
		pending_nodes.push_back(return_node)
	
	dedent_handler_stack.push_back(action_body_dedent_handler)
	
	
	return action_node

func parse_do():
	if not expect(scenescript_token.TokenType.DO): return null
	advance()
	
	if not expect(scenescript_token.TokenType.IDENTIFIER): return null
	var action_name = current_token.value
	advance()
	
	var do_node := scenescript_node.do_action.new()
	do_node.action_name = action_name
	return do_node

func parse_scene_or_global_var(): #variable declaration for scene or global
	var destination := "global" if current_token.type == scenescript_token.TokenType.GLOBAL else "scene"
	
	if current_token.type != scenescript_token.TokenType.SCENE and current_token.type != scenescript_token.TokenType.GLOBAL:
		make_error("Unexpected token: " +  scenescript_token.token_names[current_token.type] + "\n(Expected either SCENE or GLOBAL)")
		return null
	advance()
	
	if current_token.type == scenescript_token.TokenType.VAR:	#variable declaration
		return parse_var(destination)
	elif current_token.type == scenescript_token.TokenType.IDENTIFIER: #variable assignment
		return parse_assignment(destination)
	else:
		make_error("Unexpected token: " +  scenescript_token.token_names[current_token.type] + "\n(Expected either VAR or IDENTIFIER)")
		return null

func parse_run():
	if not expect(scenescript_token.TokenType.RUN): return null
	advance()
	
	if not expect(scenescript_token.TokenType.LITERAL): return null
	
	if not (current_token.value is String):
		make_error("Literal after run statement is not text")
		return null
	
	var file : String = current_token.value
	
	var run_node := scenescript_node.run_file.new()
	run_node.file_path = file
	return run_node

# ========== errors ==========

func make_unexpected_token_error(expected_type := -1):
	var message : String = "Unexpected token: " + scenescript_token.token_names[current_token.type] + " with value: " + str(current_token.value)
	if expected_type >= 0:
		message += "\n(Expected type was " + scenescript_token.token_names[expected_type] + ")"
	make_error(message)

func make_error(error_message):
	has_parse_error = true
	parse_error_string = error_message
	push_error("Scenescript: " + error_message)
	pass
