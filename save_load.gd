class_name scenescript_save_load
extends Object

const truncated_hash_length := 8

var file : FileAccess = null
var lang_file : FileAccess = null
var lang_hash_map := {}

func save_as_text(nodes : Array[scenescript_node], file_name : String, split_language_and_logic := false):
	
	if file_name.ends_with(".langref"):
		push_error("Scenescript file extension can't be .langref, otherwise it conflicts with the generated .langref file.")
		return
	
	if FileAccess.file_exists(file_name):
		push_warning("Overwriting scenescript file: " + file_name)
		var dir = DirAccess.open("res://")
		dir.remove(file_name)
	
	file = FileAccess.open(file_name, FileAccess.WRITE)
	if split_language_and_logic:
		lang_file = FileAccess.open(file_name + ".langref", FileAccess.WRITE)
	
	var indent_level := 0
	
	var skip_next := false
	var skip_after_dedent_stack := []
	var block_type_stack := []
	var choice_block_options_queue := []
	
#	if split_language_and_logic:
#		file.store_string("langref \"" + file_name + ".langref" + "\"\n")
	
	for i in nodes.size():
		if skip_next:
			skip_next = false
			continue
		
		var node := nodes[i]
		
		var line := ""
		
		for j in indent_level:
			line += "\t"
		
		if node.once:
			line += "once "
		
		match node.type:
			node.NodeType.VARIABLE:
				line += "var " + node.variable_name
				
			node.NodeType.VARIABLE_ASSIGNMENT:
				if node.destination_name == "global" or node.destination_name == "scene":
					line += node.destination_name
				if node.is_actor_variable:
					if node.use_selected_actor:
						line += "." + node.variable_identifier + "="
					else: line += "@" + node.destination_name + "." + node.variable_identifier + "="
				else: line += node.variable_identifier + "="
				line += get_tokens_string((node.expression as scenescript_expression).expression_tokens)
			
			node.NodeType.SELECT_ACTOR:
				line += "@\"" + node.actor_name + "\""
			
			node.NodeType.ACTOR_FUNCTION:
				if not node.use_selected_actor:
					line += "@\"" + node.actor_name + "\""
				line += "." + node.function_name + "("
				for j in node.function_expressions.size():
					line += get_tokens_string((node.function_expressions[j] as scenescript_expression).expression_tokens)
					if not j == node.function_expressions.size() - 1:
						line += ", "
				line += ")"
			
			node.NodeType.ID:
				line += "id " + node.id_string
			
			node.NodeType.JUMP_POSITION:
				line += "pos " + node.jump_position_name
			
			node.NodeType.GOTO:
				if node.expression == null:
					line += "goto " + node.jump_position_name
				else:
					line += "goto " + get_tokens_string((node.expression as scenescript_expression).expression_tokens)
			
			node.NodeType.IF_CONDITION:
				line += "if " + get_tokens_string((node.expression as scenescript_expression).expression_tokens) + ":"
			
			node.NodeType.EXIT:
				line += "exit"
			
			node.NodeType.SAY:
				
				if not split_language_and_logic or node.param_expressions.size() > 0:
				
					line += "say "
					if node.param_expressions.size() > 0:
						line += "{"
						for j in node.param_expressions.size():
							line += get_tokens_string((node.param_expressions[j] as scenescript_expression).expression_tokens)
							if not j == node.param_expressions.size() - 1:
								line += ", "
						line += "}"
					if not node.params_only:
						line += "\n"
				
				if not node.params_only:
				
					var expression_string = get_tokens_string((node.expression as scenescript_expression).expression_tokens)
#					var expression_hash = (str(lang_file_index) + expression_string).sha1_text()
#
					if split_language_and_logic:
#						lang_file_index += 1
#						lang_file.store_string(expression_hash + " " + expression_string + "\n")
#
#						if node.param_expressions.size() > 0:
#							line += "\n"
#						line += "sayref " + expression_hash
						line += "say " + expression_string
					else:
						line += expression_string
			
			node.NodeType.BLOCK_START:
				indent_level += 1
				if block_type_stack.size() < indent_level:
					
					if indent_level > 1:
						if block_type_stack.back() == "choice":
							if split_language_and_logic:
								var choice_string : String = choice_block_options_queue.pop_front()
								file.store_string(line + "langref \"" + store_lang_string(choice_string) + "\":\n")
							else:
								file.store_string(line + "\"" + choice_block_options_queue.pop_front() + "\":\n")
							skip_after_dedent_stack.push_back(true)
					
					block_type_stack.push_back("default")
				
					
				if skip_after_dedent_stack.size() < indent_level:
					skip_after_dedent_stack.push_back(false)
					
				continue
			
			node.NodeType.BLOCK_END:
				indent_level -= 1
				skip_next = skip_after_dedent_stack.pop_back()
				block_type_stack.pop_back()
				continue
			
			node.NodeType.LOOP:
				line += "loop"
				if node.expression != null:
					line += " " + get_tokens_string((node.expression as scenescript_expression).expression_tokens)
				line += ":"
				skip_after_dedent_stack.push_back(true)
			
			node.NodeType.SIGNAL_EMISSION:
				line += "signal " + get_tokens_string((node.expression as scenescript_expression).expression_tokens)
			
			node.NodeType.REGISTER:
				line += "register " + get_tokens_string((node.expression as scenescript_expression).expression_tokens)
			
			node.NodeType.DEREGISTER:
				line += "deregister"
			
			node.NodeType.PAUSE:
				line += "pause"
			
			node.NodeType.WAIT:
				line += "wait " + get_tokens_string((node.expression as scenescript_expression).expression_tokens)
			
			node.NodeType.ACTION:
				line += "action " + node.action_name + ":"
			
			node.NodeType.DO:
				line += "do " + node.action_name
			
			node.NodeType.RUN:
				line += "run \"" + node.file_path + "\""
			
			node.NodeType.CHOICE:
				line += "choice:"
				
				block_type_stack.push_back("choice")
				for option in node.options:
					choice_block_options_queue.push_back(option[0])
			
			_:
				print ("Unsaved node: " + node.name)
		
		line += "\n"
		
		file.store_string(line)
	
	file.close()
	if lang_file != null: lang_file.close()

func get_tokens_string(tokens : Array[scenescript_token]) -> String: #for parsing expressions
	var string := ""
	
	for token in tokens:
		match token.type:
			token.TokenType.LITERAL:
				#literals have to be replaced with langref references
				if lang_file != null:
					var literal_string = str(token.value)
					string += "langref \"" + store_lang_string(literal_string) + "\" "
				else:
					string += "\"" + token.value + "\""
					
			token.TokenType.INDENT: string += "\t"
			token.TokenType.DEDENT: pass
			token.TokenType.NEWLINE: string += "\n"
			_: string += str(token.value) + " "
	
	return string

func store_lang_string(literal_string : String) -> String:
	var literal_hash = literal_string.md5_text().substr(0, truncated_hash_length)
	
	var collisions := 0
	while literal_hash in lang_hash_map:
		literal_hash = (str(collisions) + literal_string).md5_text().substr(0, truncated_hash_length)
		collisions += 1
	
	lang_hash_map[literal_hash] = literal_string
	
	lang_file.store_string(literal_hash + " " + literal_string + "\n")
	return literal_hash

func load_langref_text(path : String):
	var file := FileAccess.open(path, FileAccess.READ)
	
	var hash_dictionary := {}
	
	while not file.eof_reached():
		var line := file.get_line()
		
		if line == "": continue
		
		var index := 0
		var hash := ""
		
		while line[index] != ' ':
			hash += line[index]
			index += 1
		
		index += 1
		
		var value := ""
		
		while index < line.length():
			value += line[index]
			index += 1
		
		hash_dictionary[hash] = value
	
	return hash_dictionary
