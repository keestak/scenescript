class_name scenescript_tokenizer
extends Object

var print_debug_info = false
var source_code := ""
var current_position := 0
var current_line := 0

var indent_level := 0
var pending_tokens : Array[scenescript_token] = []
var last_token : scenescript_token = null
var is_say_block := false

var has_token_error := false
var token_error_string := ""

func tokenize() -> Array[scenescript_token]:
	if source_code == "": return []
	
	#just make things a bit nicer to work with
	if not source_code.ends_with('\n'):
		source_code += '\n'
	
	var tokens : Array[scenescript_token] = []
	
	while true:
		var token = scan()
		if print_debug_info:
			print(str(tokens.size()).rpad(5) + " " + scenescript_token.token_names[token.type] + ("" if (token.value is String and token.value == scenescript_token.token_names[token.type]) else " (" + str(token.value) + ")"))
		tokens.append(token)
		last_token = token
		if token.type == scenescript_token.TokenType.END_OF_FILE: break
		if has_token_error: break
	
	return tokens

func scan() -> scenescript_token:
	if pending_tokens.size() > 0:
		return pending_tokens.pop_front()
	
	var c := advance()
	skip_white_space()
	
	if pending_tokens.size() > 0:
		retreat()
		return pending_tokens.pop_front()
	
	if is_say_block:
		if last_token.type == scenescript_token.TokenType.DEDENT:
			is_say_block = false
	
	c = peek()
	
	if is_at_end():
		return make_token(scenescript_token.TokenType.END_OF_FILE)
	
	if is_digit():
		return number()
	
	if c.is_valid_identifier():
		if not (c == '_' and peek(0) not in [' ', '\t', '\n']): #special case for single underscore
			return identifier_or_keyword()
	
	match c:
		'"':
			return string()
		"\n":
			return make_token(scenescript_token.TokenType.NEWLINE)
		'<':
			if peek(0) == "=":
				advance()
				return make_token(scenescript_token.TokenType.LESS_EQUAL)
			return make_token(scenescript_token.TokenType.LESS)
		'>':
			if peek(0) == "=":
				advance()
				return make_token(scenescript_token.TokenType.GREATER_EQUAL)
			return make_token(scenescript_token.TokenType.GREATER)
		'+':
			return make_token(scenescript_token.TokenType.PLUS)
		'-':
			return make_token(scenescript_token.TokenType.MINUS)
		'*':
			return make_token(scenescript_token.TokenType.STAR)
		'/':
			return make_token(scenescript_token.TokenType.SLASH)
		'%':
			return make_token(scenescript_token.TokenType.PERCENT)
		'!':
			if peek(0) == "=":
				advance()
				return make_token(scenescript_token.TokenType.NOT_EQUAL)
			return make_token(scenescript_token.TokenType.BANG)
		'=':
			if peek(0) == "=":
				advance()
				return make_token(scenescript_token.TokenType.DOUBLE_EQUAL)
			return make_token(scenescript_token.TokenType.EQUAL)
		'@':
			return make_token(scenescript_token.TokenType.AT)
		',':
			return make_token(scenescript_token.TokenType.COMMA)
		'.':
			return make_token(scenescript_token.TokenType.DOT)
		'(':
			return make_token(scenescript_token.TokenType.PAREN_OPEN)
		')':
			return make_token(scenescript_token.TokenType.PAREN_CLOSE)
		'[':
			return make_token(scenescript_token.TokenType.BRACKET_OPEN)
		']':
			return make_token(scenescript_token.TokenType.BRACKET_CLOSE)
		'{':
			return make_token(scenescript_token.TokenType.BRACE_OPEN)
		'}':
			return make_token(scenescript_token.TokenType.BRACE_CLOSE)
		':':
			if last_token.type == scenescript_token.TokenType.SAY:
				if peek(0) in [' ', '\t', '\r']:
					advance()
					skip_white_space()
					retreat() #we want to process the newline
				is_say_block = true
			return make_token(scenescript_token.TokenType.COLON)
		'_':
			return make_token(scenescript_token.TokenType.UNDERSCORE)
		'\\':
			return make_token(scenescript_token.TokenType.BACKSLASH)
		_:
			make_error("Tried to tokenize unknown character: " + c + " at line " + str(current_line) + ".")
			return null
	
	#unreachable
#	make_error("Reached end of tokenizer.scan() without finding a valid token at line " + str(current_line) + ".")
#	return null

func advance() -> String:
	if peek() == "\n":
		current_line += 1
	current_position += 1
	return peek()

func retreat() -> String:
	current_position -= 1
	if peek() == "\n":
		current_line -= 1
	return peek()

func peek(offset : int = -1) -> String:
	if is_at_end(offset + 1) or current_position + offset < 0: return ""
	return source_code[current_position + offset]

func peek_next_not_in(matchpoints : Array) -> String:
	for i in range(current_position, source_code.length()):
		if source_code[current_position] not in matchpoints:
			return source_code[current_position]
	return ''

func is_at_end(offset : int = 0) -> bool:
	if current_position + offset > source_code.length(): return true
	return false

func is_white_space():
	const whitespace = [' ', '\t', '\r']
	return peek() in whitespace

func skip_white_space():
	var num_indents = 0
	
	#if we're starting at a newline, then we want to track indent/dedent levels
	#otherwise the indents are purely whitespace and shouldn't be considered
	var is_block_indent := peek(-2) == '\n' 
	
	while is_white_space():
		if peek() == '\t' and is_block_indent:
			num_indents += 1
			if num_indents > indent_level:
				indent_level = num_indents
				pending_tokens.append(make_token(scenescript_token.TokenType.INDENT))
		elif is_say_block:
			var space_literal = make_token(scenescript_token.TokenType.LITERAL)
			space_literal.value = peek()
			pending_tokens.append(space_literal)
		advance()

	if last_token != null and last_token.type == scenescript_token.TokenType.NEWLINE:
		if num_indents < indent_level:
			for i in indent_level - num_indents:
				indent_level -= 1
				pending_tokens.append(make_token(scenescript_token.TokenType.DEDENT))

	if peek() == '#': skip_to_next_line() #comment

func skip_to_next_line():
	while peek() != '\n':
		if is_at_end(): return
		advance()

func make_token(type : scenescript_token.TokenType) -> scenescript_token:
	var token = scenescript_token.new()
	token.type = type
	token.value = scenescript_token.token_names[type]
	return token

func is_digit() -> bool:
	if peek().is_valid_int() or ((peek() == '+' or peek() == '-') and peek(0).is_valid_int() and not peek(-2).is_valid_int()):
		return true
	return false

func number():
	var num_string = ""
	while is_digit() or peek() == '.':
		if is_at_end(): break
		num_string += peek()
		advance()
	retreat() #go back so we don't advance past the next character
	
	var num := num_string.to_float()
	var token = scenescript_token.new()
	token.type = scenescript_token.TokenType.NUMBER
	token.value = num
	
	return token

func string(enclosed_in_quotes := true) -> scenescript_token:
	var starting_line := current_line
	var string_value := ""
	
	if enclosed_in_quotes:
		advance() #consme opening quotes
	
	while(true):
		if peek() == "\\":
			advance() #consume backslash
			
			if is_at_end():
				make_error("Reached end of file after backslash escape in string at line " + str(starting_line)+ ".")
				return null
				
			match peek():
				"\\": 
					string_value += "\\"
				"\"":
					string_value += "\""
				"t":
					string_value += "\t"
				"n":
					string_value += "\n"
				_:
					make_error("Unknown escape sequence \\" + peek() + " in string at line " + str(starting_line)+ ".")
					return null
			advance() #consume escaped character
			continue
		
		if (enclosed_in_quotes and peek() == '"') or (not enclosed_in_quotes and peek() == '\n'):
			break
		if is_at_end():
			make_error("Reached end of file when reading string that begins at line " + str(starting_line)+ ".")
			return null
		
		string_value += peek()
		advance()
	
	if not enclosed_in_quotes and peek() == '\n':
		retreat() #go back so the newline is encountered in the next scan
	
	var token := scenescript_token.new()
	token.type = scenescript_token.TokenType.LITERAL
	token.value = string_value
	return token

func identifier_or_keyword() -> scenescript_token:
	var word := ""
	while(true):
		if is_at_end() or not peek().is_valid_identifier():
			break
		word += peek()
		if peek(0).is_valid_identifier():
			advance()
		else: break
	
	#see if its a keyword
	#the dot check exists assuming that anything after the dot is an identifier (for a variable/function on on actor)
	if (last_token == null or last_token.type != scenescript_token.TokenType.DOT) and word in scenescript_token.token_keywords:
		return make_token(scenescript_token.token_keywords[word])
	
	#or a special word
	if word == "true":
		var token := scenescript_token.new()
		token.type = scenescript_token.TokenType.BOOL
		token.value = true
		return token
	
	if word == "false":
		var token := scenescript_token.new()
		token.type = scenescript_token.TokenType.BOOL
		token.value = false
		return token
	
	#else its an identifier
	var token := scenescript_token.new()
	token.type = scenescript_token.TokenType.IDENTIFIER
	token.value = word
	return token

func make_error(err_string):
	has_token_error = true
	token_error_string = err_string
	push_error("Scenescript: " + token_error_string)
