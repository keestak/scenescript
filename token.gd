class_name scenescript_token
extends Object

var type : TokenType
var value : Variant

enum TokenType
{
	NOTHING,
	IDENTIFIER,
	LITERAL,
	#types
	NUMBER,
	BOOL,
	#comparison
	LESS,
	LESS_EQUAL,
	GREATER,
	GREATER_EQUAL,
	DOUBLE_EQUAL,
	NOT_EQUAL,
	#logical
	AND,
	NOT,
	OR,
	#math
	PLUS,
	MINUS,
	STAR,
	SLASH,
	PERCENT,
	#assignment
	EQUAL,
	#selector
	AT,
	#keywords
	SELECT,
	ID,
	POS,
	GOTO,
	IF,
	EXIT,
	VAR,
	WAIT,
	SIGNAL,
	PAUSE,
	AWAIT,
	ALIAS,
	SAY,
	ACTION,
	CHOICE,
	LANGREF,
	RUN,
	DO,
	LOOP,
	REGISTER,
	DEREGISTER,
	SCENE,
	GLOBAL,
	#BREAK,
	COROUTINE,
	START_COROUTINE,
	ONCE,
	#punctuation
	COLON,
	PAREN_OPEN,
	PAREN_CLOSE,
	BRACKET_OPEN,
	BRACKET_CLOSE,
	BRACE_OPEN,
	BRACE_CLOSE,
	COMMA,
	DOT,
	UNDERSCORE,
	BACKSLASH,
	BANG,
	#whitespace
	INDENT,
	DEDENT,
	NEWLINE,
	#eof
	END_OF_FILE
}

const token_names :=\
[
	"nothing",
	"identifier",
	"literal",
	#types
	"number",
	"bool",
	#comparison
	"<",
	"<=",
	">",
	">=",
	"==",
	"!=",
	#logic
	"and",
	"not",
	"or",
	#math
	"+",
	"-",
	"*",
	"/",
	"%",
	#assignment
	"=",
	#selector
	"@",
	#keywords
	"select",
	"id",
	"pos",
	"goto",
	"if",
	"exit",
	"var",
	"wait",
	"signal",
	"pause",
	"await",
	"alias",
	"say",
	"action",
	"choice",
	"langref",
	"run",
	"do",
	"loop",
	"register",
	"deregister",
	"scene",
	"global",
	#"break",
	"coroutine",
	"start coroutine",
	"once",
	#punctuation
	":",
	"(",
	")",
	"[",
	"]",
	"{",
	"}",
	",",
	".",
	"_",
	'\\',
	"!",
	#whitespace
	"indent",
	"dedent",
	"newline",
	#eof
	"end of file"
]

const token_keywords :=\
{
	"select" : TokenType.SELECT,
	"id" : TokenType.ID,
	"pos" : TokenType.POS,
	"goto" : TokenType.GOTO,
	"if" : TokenType.IF,
	"exit" : TokenType.EXIT,
	"var" : TokenType.VAR,
	"wait" : TokenType.WAIT,
	"signal" : TokenType.SIGNAL,
	"pause" : TokenType.PAUSE,
	"await" : TokenType.AWAIT,
	"alias" : TokenType.ALIAS,
	"say" : TokenType.SAY,
	"action" : TokenType.ACTION,
	"choice" : TokenType.CHOICE,
	"langref" : TokenType.LANGREF,
	"run" : TokenType.RUN,
	"do" : TokenType.DO,
	"loop" : TokenType.LOOP,
	"register" : TokenType.REGISTER,
	"deregister" : TokenType.DEREGISTER,
	"scene" : TokenType.SCENE,
	"global" : TokenType.GLOBAL,
	#"break" : TokenType.BREAK,
	"coroutine" : TokenType.COROUTINE,
	"start_coroutine" : TokenType.START_COROUTINE,
	"once" : TokenType.ONCE,
	
	#these get included too because its easier, even though they're not keywords
	"and" : TokenType.AND,
	"not" : TokenType.NOT,
	"or" : TokenType.OR,
}
