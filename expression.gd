class_name scenescript_expression
extends RefCounted
#
#enum ExpressionType
#{
#	NUMERIC,
#	STRING,
#	BOOLEAN,
#}

var expression_tokens : Array[scenescript_token] :
	set(value):
		expression_tokens = value
		has_evaluated = false
	get:
		return expression_tokens


var print_debug_info := false
var always_evaluate := true #since variables can change
var has_evaluation_error := false
var evaluation_error_message := ""

var has_evaluated := false
var evaluated_value = null

func evaluate(process : scenescript_process = null):
	if has_evaluated and not always_evaluate:
		return evaluated_value
	
	const operator_precedence := {
		#numeric
		scenescript_token.TokenType.PLUS : 1, #also string
		scenescript_token.TokenType.MINUS : 1,
		scenescript_token.TokenType.STAR : 2,
		scenescript_token.TokenType.SLASH : 2,
		
		#boolean
		scenescript_token.TokenType.GREATER : 0,
		scenescript_token.TokenType.GREATER_EQUAL : 0,
		scenescript_token.TokenType.LESS : 0,
		scenescript_token.TokenType.LESS_EQUAL : 0,
		scenescript_token.TokenType.DOUBLE_EQUAL : 0,
		scenescript_token.TokenType.NOT_EQUAL : 0,
		scenescript_token.TokenType.AND : 0,
		scenescript_token.TokenType.OR : 0,
		scenescript_token.TokenType.NOT : 3,
	}
	
	#convert via shunting yard
	#todo? split shunting yard and rpn evaluation into seperate functions
	
	var tokens := expression_tokens.duplicate()
	
	var output := []
	var stack := []
	
	while tokens:
		var token : scenescript_token = tokens.pop_front()
		
		if token.type in [
			scenescript_token.TokenType.NUMBER, 
			scenescript_token.TokenType.LITERAL, 
			scenescript_token.TokenType.BOOL, 
			scenescript_token.TokenType.IDENTIFIER, 
			scenescript_token.TokenType.DEREGISTER,
			scenescript_token.TokenType.UNDERSCORE,
			
			scenescript_token.TokenType.SCENE,
			scenescript_token.TokenType.GLOBAL,
			scenescript_token.TokenType.AT,
			scenescript_token.TokenType.DOT,
			scenescript_token.TokenType.LANGREF,
			]:
			
			output.push_back(token)
		elif token.type in operator_precedence:
			while stack and stack.back().type in operator_precedence and operator_precedence[stack.back().type] >= operator_precedence[token.type]:
				output.push_back(stack.pop_back())
			stack.push_back(token)
		elif token.type == scenescript_token.TokenType.PAREN_OPEN:
			stack.push_back(token)
		elif token.type == scenescript_token.TokenType.PAREN_CLOSE:
			while stack.back().type != scenescript_token.TokenType.PAREN_OPEN:
				output.push_back(stack.pop_back())
				if stack.size() == 0:
					make_error("Mismatched parenthesis in expression")
					return null
			stack.pop_back()
		else:
			make_error("Unsupported token in expression: " + scenescript_token.token_names[(token as scenescript_token).type])
			return null
	while stack:
		output.push_back(stack.pop_back())
	
	if print_debug_info:
		print("\n--- Expression input: ---\n")
		print_token_array(expression_tokens)
		print("\n--- RPN'd expression tokens: ---\n")
		print_token_array(output)
	
	#evaluate
	
	#if this is set to true, then there is a variable in the function, otherwise we set always_evaluate to false
	var has_variable := false
	
	const operators :=[
		#numeric
		scenescript_token.TokenType.PLUS, #string
		scenescript_token.TokenType.MINUS,
		scenescript_token.TokenType.STAR,
		scenescript_token.TokenType.SLASH,
		
		#boolean
		scenescript_token.TokenType.GREATER,
		scenescript_token.TokenType.GREATER_EQUAL,
		scenescript_token.TokenType.LESS,
		scenescript_token.TokenType.LESS_EQUAL,
		scenescript_token.TokenType.DOUBLE_EQUAL,
		scenescript_token.TokenType.NOT_EQUAL,
		scenescript_token.TokenType.AND,
		scenescript_token.TokenType.OR,
		]
	
	while output:
		var token : scenescript_token = output.pop_front()
		if token.type == scenescript_token.TokenType.NUMBER:
			stack.push_back(token.value as float)
		elif token.type == scenescript_token.TokenType.LITERAL:
			stack.push_back(token.value as String)
		elif token.type == scenescript_token.TokenType.BOOL:
			stack.push_back(token.value as bool)
		elif token.type == scenescript_token.TokenType.UNDERSCORE:
			stack.push_back(null)
		elif token.type == scenescript_token.TokenType.IDENTIFIER:
			has_variable = true
			if process == null:
				make_error("Encountered an identifier, but a scenescript process wasn't supplied.")
				return null
			elif token.value not in process.constants and token.value not in process.variables:
				make_error("Identifier " + token.value + " was not in supplied process's variable dictionary.")
				return null
			
			stack.push_back(process.get_value(token.value))
		elif token.type == scenescript_token.TokenType.SCENE: #scene variable reference
			has_variable = true
			if process == null:
				make_error("Encountered a scene identifier, but a scenescript process wasn't supplied.")
				return null
			token = output.pop_front()
			if token.value not in Scenescript.scene_vars:
				make_error("Identifier " + token.value + " was not in scene variables.")
				return null
			
			stack.push_back(Scenescript.scene_vars[token.value])
			
		elif token.type == scenescript_token.TokenType.GLOBAL: #Global variable reference
			has_variable = true
			if process == null:
				make_error("Encountered a global identifier, but a scenescript process wasn't supplied.")
				return null
			token = output.pop_front()
			if token.value not in Scenescript.global_vars:
				make_error("Identifier " + token.value + " was not in global variables.")
				return null
			
			stack.push_back(Scenescript.global_vars[token.value])
			
		elif token.type == scenescript_token.TokenType.AT: #actor variable
			has_variable = true
			
			token = output.pop_front() #move to name / identifier
			if token.type != scenescript_token.TokenType.IDENTIFIER and token.type != scenescript_token.TokenType.LITERAL:
				make_error("Expected actor name (identifier or string literal) after @ in expression.")
				return null
			
			var actor_name := str(token.value)
			
			var actor : Variant
			
			if token.value in Scenescript.scene_actors:
				actor = Scenescript.scene_actors[actor_name]
				
			elif token.value in Scenescript.global_actors:
				actor = Scenescript.global_actors[actor_name]
				
			else:
				make_error("Actor name \"" + actor_name + "\" was not in global or scene actors.")
			
			token = output.pop_front() #move to dot
			if token.type != scenescript_token.TokenType.DOT:
				make_error("Expected dot after actor name in expression.")
				return null
			
			token = output.pop_front() #move to dot
			if token.type != scenescript_token.TokenType.IDENTIFIER:
				make_error("Expected dot after actor name in expression.")
				return null
			
			var member_name = token.value
			
			if not token.value in actor:
				make_error("Member name \"" + member_name + " was not in actor \"" + actor_name + "\".")
				return null
			
			stack.push_back(actor.get(member_name))
			
		elif token.type == scenescript_token.TokenType.DEREGISTER:
			has_variable = true
			if process == null:
				make_error("Encountered a deregister, but a scenescript process wasn't supplied.")
				return null
			
			if Scenescript.register_stack.size() == 0:
				stack.push_back(null)
			else:
				stack.push_back(process.pop_register())
			
		elif token.type == scenescript_token.TokenType.LANGREF:
			if process == null:
				make_error("Encountered a langref, but a scenescript process wasn't supplied.")
				return null
			
			token = output.pop_front() #move to literal
			if token.type != scenescript_token.TokenType.LITERAL:
				make_error("Expected literal after langref in expression.")
				return null
			
			stack.push_back(process.language_reference_dictionary[token.value])
			
		elif token.type == scenescript_token.TokenType.NOT: #special case for not operator
			var value = stack.pop_back()
			if typeof(value) != TYPE_BOOL:
				make_error(str(value) + " is non-boolean.")
				return null
			stack.push_back(not value)
		elif token.type in operators:
			#check if the stack has less than 2 entries, and error if so
			var r = stack.pop_back()
			var l = stack.pop_back()
			
			if typeof(l) == TYPE_INT:
				l = float(l)
			if typeof(r) == TYPE_INT:
				r = float(r)
			
			match token.type:
				#numeric
				scenescript_token.TokenType.PLUS: #string
					if l is String or r is String:
						stack.push_back(str(l) + str(r))
					else:
						if not check_type(l, r, TYPE_FLOAT):
							make_error("Can't add " + str(l) + " and " + str(r))
							return null
						stack.push_back(l + r)
				scenescript_token.TokenType.MINUS:
					if not check_type(l, r, TYPE_FLOAT):
						make_error("Can't subtract " + str(l) + " and " + str(r))
						return null
					stack.push_back(l - r)
				scenescript_token.TokenType.STAR:
					if not check_type(l, r, TYPE_FLOAT):
						make_error("Can't multiply " + str(l) + " and " + str(r))
						return null
					stack.push_back(l * r)
				scenescript_token.TokenType.SLASH:
					if not check_type(l, r, TYPE_FLOAT):
						make_error("Can't divide " + str(l) + " and " + str(r))
						return null
					stack.push_back(l / r)
				
				#logical
				scenescript_token.TokenType.AND:
					if not check_type(l, r, TYPE_BOOL):
						make_error("Either " + str(l) + " or " + str(r) + " is non-boolean.")
						return null
					stack.push_back(l and r)
				scenescript_token.TokenType.OR:
					if not check_type(l, r, TYPE_BOOL):
						make_error("Either " + str(l) + " or " + str(r) + " is non-boolean.")
						return null
					stack.push_back(l or r)
				scenescript_token.TokenType.GREATER:
					if not check_type(l, r, TYPE_FLOAT):
						make_error("Either " + str(l) + " or " + str(r) + " is not a number.")
						return null
					stack.push_back(l > r)
				scenescript_token.TokenType.GREATER_EQUAL:
					if not check_type(l, r, TYPE_FLOAT):
						make_error("Either " + str(l) + " or " + str(r) + " is not a number.")
						return null
					stack.push_back(l >= r)
				scenescript_token.TokenType.LESS:
					if not check_type(l, r, TYPE_FLOAT):
						make_error("Either " + str(l) + " or " + str(r) + " is not a number.")
						return null
					stack.push_back(l < r)
				scenescript_token.TokenType.LESS_EQUAL:
					if not check_type(l, r, TYPE_FLOAT):
						make_error("Either " + str(l) + " or " + str(r) + " is not a number.")
						return null
					stack.push_back(l <= r)
				scenescript_token.TokenType.DOUBLE_EQUAL:
					stack.push_back(l == r)
				scenescript_token.TokenType.NOT_EQUAL:
					stack.push_back(l != r)
		else:
			make_error("Unsupported token during expression evaluation: " + scenescript_token.token_names[token.type] + ": " + str(token.value))
	
	if stack.size() > 1:
		make_error("Final output stack size was greater than 1 (unknown error in expression).")
	var result = stack.pop_back()
	
	if print_debug_info:
		print("Final output: " + str(result))
		while stack.size() > 0:
			print("Unhandled stack entry: " + str(stack.pop_back()))
	
	has_evaluated = true
	evaluated_value = result
	
	if not has_variable:
		always_evaluate = false
	
	return result

func check_type(l, r, type) -> bool:
	if typeof(l) != type or typeof(r) != type:
		return false
	return true

func make_error(message : String):
	has_evaluation_error = true
	evaluation_error_message = message
	push_error("Scenescript evaluation error: " + message)

func print_token_array(array):
	for item in array:
		print(scenescript_token.token_names[(item as scenescript_token).type] + ": " + str((item as scenescript_token).value))
