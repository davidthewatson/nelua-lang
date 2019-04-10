require 'busted.runner'()

local assert = require 'spec.assert'
local euluna_syntax = require 'euluna.syntaxdefs'()
local euluna_parser = euluna_syntax.parser
local euluna_grammar = euluna_syntax.grammar
local euluna_astbuilder = euluna_syntax.astbuilder
local n = euluna_astbuilder.aster
local pegs = euluna_parser.defs

describe("Euluna should parse", function()

--------------------------------------------------------------------------------
-- spaces
-----------------------------------------------------a---------------------------
it("spaces", function()
  assert.peg_match_all(pegs.SPACE, {
    ' ', '\t', '\n', '\r',
  })
  assert.peg_match_none(pegs.SPACE, {
    'a'
  })
end)

it("line breaks", function()
  assert.peg_match_all(pegs.LINEBREAK, {
    "\n\r", "\r\n", "\n", "\r",
  })
  assert.peg_match_none(pegs.LINEBREAK, {
    ' ',
    '\t'
  })
end)

--------------------------------------------------------------------------------
-- shebang
--------------------------------------------------------------------------------
it("shebang", function()
  assert.peg_match_all(pegs.SHEBANG, {
    "#!/usr/bin/euluna",
    "#!anything can go here"
  })
  assert.peg_match_none(pegs.SHEBANG, {
    "#/usr/bin/euluna",
    "/usr/bin/euluna",
    " #!/usr/bin/euluna"
  })
end)

--------------------------------------------------------------------------------
-- comments
--------------------------------------------------------------------------------
it("comments", function()
  assert.peg_match_all(pegs.SHORTCOMMENT, {
    "-- a comment"
  })
  assert.peg_match_all(pegs.LONGCOMMENT, {
    "--[[ a\nlong\ncomment ]]",
    "--[=[ [[a\nlong\ncomment]] ]=]",
    "--[==[ [[a\nlong\ncomment]] ]==]"
  })
  assert.peg_match_all(pegs.COMMENT, {
    "--[[ a\nlong\r\ncomment ]]",
    "-- a comment"
  })
end)

--------------------------------------------------------------------------------
-- keywords
--------------------------------------------------------------------------------
it("keywords", function()
  assert.peg_match_all(pegs.KEYWORD, {
    'if', 'for', 'while'
  })
  assert.peg_match_none(pegs.KEYWORD, {
    'IF', '_if', 'fi_',
  })
end)

--------------------------------------------------------------------------------
-- identifiers
--------------------------------------------------------------------------------
it("identifiers", function()
  assert.peg_capture_all(pegs.cNAME, {
    ['varname'] = 'varname',
    ['_if'] = '_if',
    ['if_'] = 'if_',
    ['var123'] = 'var123'
  })
  assert.peg_capture_all(pegs.cID, {
    ['_varname'] = n.Id{'_varname'}
  })
  assert.peg_match_none(pegs.cNAME, {
    '123a', 'if', '-varname', 'if', 'else'
  })
end)

--------------------------------------------------------------------------------
-- numbers
--------------------------------------------------------------------------------
describe("numbers", function()
  it("binary", function()
    assert.peg_capture_all(pegs.cNUMBER, {
      ["0b0"] = n.Number{"bin", "0"},
      ["0b1"] = n.Number{"bin", "1"},
      ["0b10101111"] = n.Number{"bin", "10101111"},
    })
  end)
  it("hexadecimal", function()
    assert.peg_capture_all(pegs.cNUMBER, {
      ["0x0"] = n.Number{"hex", "0"},
      ["0x0123456789abcdef"] = n.Number{"hex", "0123456789abcdef"},
      ["0xABCDEF"] = n.Number{"hex", "ABCDEF"},
    })
  end)
  it("integer", function()
    assert.peg_capture_all(pegs.cNUMBER, {
      ["1"] = n.Number{"dec", "1"},
      ["0123456789"] = n.Number{"dec", "0123456789"},
    })
  end)
  it("decimal", function()
    assert.peg_capture_all(pegs.cNUMBER, {
      [".0"] = n.Number{"dec", "0", "0"},
      ["0."] = n.Number{"dec", "0", "0"},
      ["0123.456789"] = n.Number{"dec", "0123", "456789"},
    })
  end)
  it("exponential", function()
    assert.peg_capture_all(pegs.cNUMBER, {
      ["1.2e-3"] = n.Number{"dec", "1", "2", "-3"},
      [".1e2"] = n.Number{"dec", "0", "1", "2"},
      [".0e+2"] = n.Number{"dec", "0", "0", "+2"},
      ["1e-2"] = n.Number{"dec", "1", nil, "-2"},
      ["1e+2"] = n.Number{"dec", "1", nil, "+2"},
      ["1.e3"] = n.Number{"dec", "1", "0", "3"},
      ["1e1"] = n.Number{"dec", "1", nil, "1"},
      ["1.2e+6"] = n.Number{"dec", "1", "2", "+6"},
      ["0x3.3p3"] = n.Number{"hex", "3", "3", "3"},
      ["0x5.5P-5"] = n.Number{"hex", "5", "5", "-5"},
      ["0b1.1p2"] = n.Number{"bin", "1", "1", "2"},
    })
  end)
  it("literal", function()
    assert.peg_capture_all(pegs.cNUMBER, {
      [".1f"] = n.Number{"dec", "0", "1", nil, "f"},
      ["123u"] = n.Number{"dec", "123", nil, nil, "u"},
    })
  end)
  it("malformed", function()
    assert.peg_error_all(pegs.cNUMBER, "MalformedHexadecimalNumber", {
      "0x",
      "0xG",
    })
    assert.peg_error_all(pegs.cNUMBER, "MalformedBinaryNumber", {
      "0b",
      "0b2",
      "0b012"
    })
    assert.peg_error_all(pegs.cNUMBER, "MalformedExponentialNumber", {
      "0e",
      "0ef",
      "1e*2"
    })
  end)
end)

--------------------------------------------------------------------------------
-- escape sequence
--------------------------------------------------------------------------------
it("escape sequence", function()
  assert.peg_error_all(pegs.cESCAPESEQUENCE, 'MalformedEscapeSequence', {
    "\\A",
    "\\u42",
    "\\xH",
    "\\x",
    "\\x1",
    "\\u{}",
    "\\300"
  })
  assert.peg_capture_all(pegs.cESCAPESEQUENCE, {
    ["\\a"] = "\a",
    ["\\b"] = "\b",
    ["\\f"] = "\f",
    ["\\n"] = "\n",
    ["\\r"] = "\r",
    ["\\t"] = "\t",
    ["\\v"] = "\v",
    ["\\\\"] = "\\",
    ["\\'"] = "'",
    ['\\"'] = '"',
    ['\\z \t\r\n'] = '',
    ['\\0'] = '\0',
    ['\\65'] = 'A',
    ['\\065'] = 'A',
    ['\\x41'] = 'A',
    ['\\u{41}'] = 'A',
    ['\\\n'] = '\n',
    ['\\\r'] = '\n',
    ['\\\r\n'] = '\n',
    ['\\\n\r'] = '\n',
  })
end)

--------------------------------------------------------------------------------
-- string
--------------------------------------------------------------------------------
describe("string", function()
  it("long", function()
    assert.peg_capture_all(pegs.cSTRING, {
      "[[]]", "[=[]=]", "[==[]==]",
      "[[[]]", "[=[]]=]", "[==[]]]]==]",
      "[[test]]", "[=[test]=]", "[==[test]==]",
      "[[\nasd\n]]", "[=[\nasd\n]=]", "[==[\nasd\n]==]",
      ["[[\nasd\n]]"] = n.String{"asd\n"},
      ["[==[\nasd\n]==]"] = n.String{"asd\n"}
    })
    assert.peg_error_all(pegs.cSTRING, 'UnclosedLongString', {
      '[[', '[=[]]', '[[]',
    })
  end)

  it("short", function()
    assert.peg_capture_all(pegs.cSTRING, {
      ['""'] = n.String{''},
      ["''"] = n.String{''},
      ['"test"'] = n.String{'test'},
      ["'test'"] = n.String{'test'},
      ['"a\\t\\nb"'] = n.String{'a\t\nb'}
    })
    assert.peg_error_all(pegs.cSTRING, 'UnclosedShortString', {
      '"', "'", '"\\"', "'\\\"", '"\n"',
    })
  end)

  it("literal", function()
    assert.peg_capture_all(pegs.cSTRING, {
      ['"asd"u8'] = n.String{"asd", "u8"},
      ["'asd'hex"] = n.String{"asd", "hex"},
      ["[[asd]]hex"] = n.String{"asd", "hex"},
    })
  end)
end)

--------------------------------------------------------------------------------
-- boolean
--------------------------------------------------------------------------------
it("boolean", function()
  assert.peg_capture_all(pegs.cBOOLEAN, {
    ["true"] = n.Boolean{true},
    ["false"] = n.Boolean{false},
  })
  assert.peg_match_none(pegs.cBOOLEAN, {
    'False', 'FALSE', 'True', 'TRUE',
  })
end)

--------------------------------------------------------------------------------
-- operators and symbols
--------------------------------------------------------------------------------
it("operators and symbols", function()
  assert.peg_match_all(pegs.ADD, {'+'})
  assert.peg_match_all(pegs.SUB, {'-'})
  assert.peg_match_all(pegs.MUL, {'*'})
  assert.peg_match_all(pegs.MOD, {'%'})
  assert.peg_match_all(pegs.DIV, {'/'})
  assert.peg_match_all(pegs.POW, {'^'})

  assert.peg_match_all(pegs.BAND, {'&'})
  assert.peg_match_all(pegs.BOR, {'|'})
  assert.peg_match_all(pegs.SHL, {'<<'})
  assert.peg_match_all(pegs.SHR, {'>>'})

  assert.peg_match_all(pegs.EQ, {'=='})
  assert.peg_match_all(pegs.NE, {'~='})
  assert.peg_match_all(pegs.LE, {'<='})
  assert.peg_match_all(pegs.GE, {'>='})
  assert.peg_match_all(pegs.LT, {'<'})
  assert.peg_match_all(pegs.GT, {'>'})

  assert.peg_match_all(pegs.NEG, {'-'})
  assert.peg_match_all(pegs.LEN, {'#'})
  assert.peg_match_all(pegs.BNOT, {'~'})
  assert.peg_match_all(pegs.TOSTR, {'$'})

  assert.peg_match_all(pegs.LPAREN, {'('})
  assert.peg_match_all(pegs.RPAREN, {')'})
  assert.peg_match_all(pegs.LBRACKET, {'['})
  assert.peg_match_all(pegs.RBRACKET, {']'})
  assert.peg_match_all(pegs.LCURLY, {'{'})
  assert.peg_match_all(pegs.RCURLY, {'}'})
  assert.peg_match_all(pegs.LANGLE, {'<'})
  assert.peg_match_all(pegs.RANGLE, {'>'})

  assert.peg_match_all(pegs.SEMICOLON, {';'})
  assert.peg_match_all(pegs.COMMA, {','})
  assert.peg_match_all(pegs.SEPARATOR, {';', ','})
  assert.peg_match_all(pegs.ELLIPSIS, {'...'})
  assert.peg_match_all(pegs.CONCAT, {'..'})
  assert.peg_match_all(pegs.DOT, {'.'})
  assert.peg_match_all(pegs.DBLCOLON, {'::'})
  assert.peg_match_all(pegs.COLON, {':'})
  assert.peg_match_all(pegs.AT, {'@'})
  assert.peg_match_all(pegs.DOLLAR, {'$'})
  assert.peg_match_all(pegs.QUESTION, {'?'})

  assert.peg_match_none(pegs.SUB, {'--'})
  assert.peg_match_none(pegs.LT, {'<<', '<='})
  assert.peg_match_none(pegs.BXOR, {'~='})
  assert.peg_match_none(pegs.ASSIGN, {'=='})

  assert.peg_match_none(pegs.NEG, {'--'})
  assert.peg_match_none(pegs.BNOT, {'~='})
  assert.peg_match_none(pegs.LBRACKET, {'[['})

  assert.peg_match_none(pegs.CONCAT, {'...'})
  assert.peg_match_none(pegs.DOT, {'...', '..'})
  assert.peg_match_none(pegs.COLON, {'::'})
end)

--------------------------------------------------------------------------------
-- empty file
--------------------------------------------------------------------------------
it("empty file", function()
  assert.parse_ast(euluna_parser, "", n.Block{{}})
  assert.parse_ast(euluna_parser, " \t\n", n.Block{{}})
  assert.parse_ast(euluna_parser, ";", n.Block{{}})
end)

--------------------------------------------------------------------------------
-- invalid syntax
--------------------------------------------------------------------------------
it("invalid syntax", function()
  assert.parse_ast_error(euluna_parser, [[something]], 'UnexpectedSyntaxAtEOF')
end)

--------------------------------------------------------------------------------
-- shebang
--------------------------------------------------------------------------------
it("shebang", function()
  assert.parse_ast(euluna_parser, [[#!/usr/bin/env lua]], n.Block{{}})
  assert.parse_ast(euluna_parser, [[#!/usr/bin/env lua\n]], n.Block{{}})
end)

--------------------------------------------------------------------------------
-- comments
--------------------------------------------------------------------------------
it("comments", function()
  assert.parse_ast(euluna_parser, [=[-- line comment
--[[
multiline comment
]]]=], n.Block{{}})

  assert.parse_ast(euluna_parser, [=[if a then --[[f()]] end]=],
    n.Block{{n.If{{{ n.Id{'a'}, n.Block{{}}}
  }}}})
end)

--------------------------------------------------------------------------------
-- return statement
--------------------------------------------------------------------------------
describe("return", function()
  it("simple", function()
    assert.parse_ast(euluna_parser, "return",
      n.Block{{
        n.Return{{}}
    }})
  end)
  it("with semicolon", function()
    assert.parse_ast(euluna_parser, "return;",
      n.Block{{
        n.Return{{}}
    }})
  end)
  it("with value", function()
    assert.parse_ast(euluna_parser, "return 0",
      n.Block{{
        n.Return{{
          n.Number{'dec', '0'}
    }}}})
  end)
  it("with multiple values", function()
    assert.parse_ast(euluna_parser, "return 1,2,3",
      n.Block{{
        n.Return{{
          n.Number{'dec', '1'},
          n.Number{'dec', '2'},
          n.Number{'dec', '3'},
    }}}})
  end)
end)

--------------------------------------------------------------------------------
-- expressions
--------------------------------------------------------------------------------
describe("expression", function()
  it("number", function()
    assert.parse_ast(euluna_parser, "return 3.34e-50, 0xff, 0.1",
      n.Block{{
        n.Return{{
          n.Number{'dec', '3', '34', '-50'},
          n.Number{'hex', 'ff'},
          n.Number{'dec', '0', '1'},
    }}}})
  end)
  it("string", function()
    assert.parse_ast(euluna_parser, [[return 'hi', "there"]],
      n.Block{{
        n.Return{{
          n.String{'hi'},
          n.String{'there'}
    }}}})
  end)
  it("boolean", function()
    assert.parse_ast(euluna_parser, "return true, false",
      n.Block{{
        n.Return{{
          n.Boolean{true},
          n.Boolean{false}
    }}}})
  end)
  it("nil", function()
    assert.parse_ast(euluna_parser, "return nil",
      n.Block{{
        n.Return{{
          n.Nil{},
    }}}})
  end)
  it("varargs", function()
    assert.parse_ast(euluna_parser, "return ...",
      n.Block{{
        n.Return{{
          n.Varargs{},
    }}}})
  end)
  it("identifier", function()
    assert.parse_ast(euluna_parser, "return a, _b",
      n.Block{{
        n.Return{{
          n.Id{'a'},
          n.Id{'_b'},
    }}}})
  end)
  it("table", function()
    assert.parse_ast(euluna_parser, "return {}, {a}, {a,b}, {a=b}, {[a] = b}",
      n.Block{{
        n.Return{{
          n.Table{{}},
          n.Table{{ n.Id{'a'} }},
          n.Table{{ n.Id{'a'}, n.Id{'b'} }},
          n.Table{{ n.Pair{'a', n.Id{'b'}} }},
          n.Table{{ n.Pair{n.Id{'a'}, n.Id{'b'}} }},
    }}}})
  end)
  it("surrounded expression", function()
    assert.parse_ast(euluna_parser, "return (a)",
      n.Block{{
        n.Return{{
          n.Paren{
            n.Id{'a'}
    }}}}})
  end)
  it("dot index", function()
    assert.parse_ast(euluna_parser, "return a.b, a.b.c",
      n.Block{{
        n.Return{{
          n.DotIndex{'b',
            n.Id{'a'}
          },
          n.DotIndex{'c',
            n.DotIndex{'b',
              n.Id{'a'}
          }}
    }}}})
  end)
  it("array index", function()
    assert.parse_ast(euluna_parser, "return a[b], a[b][c]",
      n.Block{{
        n.Return{{
          n.ArrayIndex{
            n.Id{'b'},
            n.Id{'a'}
          },
          n.ArrayIndex{
            n.Id{'c'},
            n.ArrayIndex{
              n.Id{'b'},
              n.Id{'a'}
          }}
    }}}})
  end)
  it("anonymous function", function()
    assert.parse_ast(euluna_parser, "return function() end, function(a, b: B): C,D end",
      n.Block{{
        n.Return{{
          n.Function{{}, {}, n.Block{{}}},
          n.Function{
            { n.IdDecl{'a', 'var'}, n.IdDecl{'b', 'var', n.Type{'B'}} },
            { n.Type{'C'}, n.Type{'D'} },
            n.Block{{}}
          }
    }}}})
  end)
  it("call global", function()
    assert.parse_ast(euluna_parser, "return a()",
      n.Block{{
        n.Return{{
          n.Call{{}, {}, n.Id{'a'}},
    }}}})
  end)
  it("call with arguments", function()
    assert.parse_ast(euluna_parser, "return a(a, 'b', 1, f(), ...)",
      n.Block{{
        n.Return{{
          n.Call{{}, {
            n.Id{'a'},
            n.String{'b'},
            n.Number{'dec', '1'},
            n.Call{{}, {}, n.Id{'f'}},
            n.Varargs{},
          }, n.Id{'a'}},
    }}}})
  end)
  it("call field", function()
    assert.parse_ast(euluna_parser, "return a.b()",
      n.Block{{
        n.Return{{
          n.Call{{}, {}, n.DotIndex{'b', n.Id{'a'}}},
    }}}})
  end)
  it("call method", function()
    assert.parse_ast(euluna_parser, "return a:b()",
      n.Block{{
        n.Return{{
          n.CallMethod{'b', {}, {}, n.Id{'a'}},
    }}}})
  end)
end)

--------------------------------------------------------------------------------
-- tables
--------------------------------------------------------------------------------
describe("table", function()
  it("complex fields", function()
    assert.parse_ast(euluna_parser, [[return {
      a=a, [a]=a, [nil]=nil, [true]=true,
      ['mystr']='mystr', [1.0]=1.0, [func()]=func(),
      [...]=...
    }]],
      n.Block{{
        n.Return{{
          n.Table{{
            n.Pair{'a', n.Id{'a'}},
            n.Pair{n.Id{'a'}, n.Id{'a'}},
            n.Pair{n.Nil{}, n.Nil{}},
            n.Pair{n.Boolean{true}, n.Boolean{true}},
            n.Pair{n.String{'mystr'}, n.String{'mystr'}},
            n.Pair{n.Number{'dec', '1', '0'}, n.Number{'dec', '1', '0'}},
            n.Pair{n.Call{{}, {}, n.Id{'func'}}, n.Call{{}, {}, n.Id{'func'}}},
            n.Pair{n.Varargs{}, n.Varargs{}},
    }}}}}})
  end)
  it("multiple values", function()
    assert.parse_ast(euluna_parser, "return {a,nil,true,'mystr',1.0,func(),...}",
      n.Block{{
        n.Return{{
          n.Table{{
            n.Id{'a'},
            n.Nil{},
            n.Boolean{true},
            n.String{'mystr'},
            n.Number{'dec', '1', '0'},
            n.Call{{}, {}, n.Id{'func'}},
            n.Varargs{},
    }}}}}})
  end)
  it("nested", function()
    assert.parse_ast(euluna_parser, "return {{{}}}",
      n.Block{{
        n.Return{{
          n.Table{{ n.Table{{ n.Table{{}}}},
    }}}}}})
  end)
end)


--------------------------------------------------------------------------------
-- call statement
--------------------------------------------------------------------------------
describe("call", function()
  it("simple", function()
    assert.parse_ast(euluna_parser, "a()",
      n.Block{{
        n.Call{{}, {}, n.Id{'a'}, true},
    }})
  end)
  it("dot index", function()
    assert.parse_ast(euluna_parser, "a.b()",
      n.Block{{
        n.Call{{}, {}, n.DotIndex{'b', n.Id{'a'}}, true}
    }})
  end)
  it("array index", function()
    assert.parse_ast(euluna_parser, "a['b']()",
      n.Block{{
        n.Call{{}, {}, n.ArrayIndex{n.String{'b'}, n.Id{'a'}}, true}
    }})
  end)
  it("method", function()
    assert.parse_ast(euluna_parser, "a:b()",
      n.Block{{
        n.CallMethod{'b', {}, {}, n.Id{'a'}, true}
    }})
  end)
  it("nested", function()
    assert.parse_ast(euluna_parser, "a(b())",
      n.Block{{
        n.Call{{}, {n.Call{{}, {}, n.Id{'b'}}}, n.Id{'a'}, true},
    }})
  end)
  it("typed", function()
    assert.parse_ast(euluna_parser, "print<string>('hi')",
      n.Block{{
        n.Call{
          { n.Type{'string'} },
          { n.String{'hi'} },
          n.Id{'print'}, true},
    }})
  end)
  it("typed method", function()
    assert.parse_ast(euluna_parser, "s:substr<number,number>(1,2)",
      n.Block{{
        n.CallMethod{
          'substr',
          { n.Type{'number'}, n.Type{'number'} },
          { n.Number{'dec', '1'}, n.Number{'dec', '2'} },
          n.Id{'s'},
          true
    }}})
  end)
end)

--------------------------------------------------------------------------------
-- if statement
--------------------------------------------------------------------------------
describe("statement if", function()
  it("simple", function()
    assert.parse_ast(euluna_parser, "if true then end",
      n.Block{{
        n.If{{
          {n.Boolean{true}, n.Block{{}}}
    }}}})
  end)
  it("with elseifs and else", function()
    assert.parse_ast(euluna_parser, "if a then return x elseif b then return y else return z end",
      n.Block{{
        n.If{{
          { n.Id{'a'}, n.Block{{n.Return{{ n.Id{'x'} }}}} },
          { n.Id{'b'}, n.Block{{n.Return{{ n.Id{'y'} }}}} },
        },
        n.Block{{n.Return{{ n.Id{'z'} }}}}
    }}})
  end)
end)

--------------------------------------------------------------------------------
-- switch statement
--------------------------------------------------------------------------------
describe("statement switch", function()
  it("simple", function()
    assert.parse_ast(euluna_parser, "switch a case b then end",
      n.Block{{
        n.Switch{
          n.Id{'a'},
          { {n.Id{'b'}, n.Block{{}}} }
    }}})
  end)
  it("with else part", function()
    assert.parse_ast(euluna_parser, "switch a case b then else end",
      n.Block{{
        n.Switch{
          n.Id{'a'},
          { {n.Id{'b'}, n.Block{{}}} },
          n.Block{{}}
    }}})
  end)
  it("multiple cases", function()
    assert.parse_ast(euluna_parser, "switch a case b then case c then else end",
      n.Block{{
        n.Switch{
          n.Id{'a'},
          { {n.Id{'b'}, n.Block{{}}},
            {n.Id{'c'}, n.Block{{}}}
          },
          n.Block{{}}
    }}})
  end)
end)

--------------------------------------------------------------------------------
-- do statement
--------------------------------------------------------------------------------
describe("statement do", function()
  it("simple", function()
    assert.parse_ast(euluna_parser, "do end",
      n.Block{{
        n.Do{n.Block{{}}}
    }})
  end)
  it("with statements", function()
    assert.parse_ast(euluna_parser, "do print() end",
      n.Block{{
        n.Do{n.Block{{ n.Call{{}, {}, n.Id{'print'}, true} }}}
    }})
  end)
end)

--------------------------------------------------------------------------------
-- simple loop statements
--------------------------------------------------------------------------------
describe("loop statement", function()
  it("while", function()
    assert.parse_ast(euluna_parser, "while a do end",
      n.Block{{
        n.While{n.Id{'a'}, n.Block{{}}}
    }})
  end)
  it("break and continue", function()
    assert.parse_ast(euluna_parser, "while a do break end",
      n.Block{{
        n.While{n.Id{'a'}, n.Block{{ n.Break{} }}}
    }})
    assert.parse_ast(euluna_parser, "while a do continue end",
      n.Block{{
        n.While{n.Id{'a'}, n.Block{{ n.Continue{} }}}
    }})
  end)
  it("repeat", function()
    assert.parse_ast(euluna_parser, "repeat until a",
      n.Block{{
        n.Repeat{n.Block{{}}, n.Id{'a'}}
    }})
    assert.parse_ast(euluna_parser, "repeat print() until a==b",
      n.Block{{
        n.Repeat{
          n.Block{{ n.Call{{}, {}, n.Id{'print'}, true} }},
          n.BinaryOp{'eq', n.Id{'a'}, n.Id{'b'}}
    }}})
  end)
end)

--------------------------------------------------------------------------------
-- for statement
--------------------------------------------------------------------------------
describe("statement for", function()
  it("simple", function()
    assert.parse_ast(euluna_parser, "for i=1,10 do end",
      n.Block{{
        n.ForNum{
          n.IdDecl{'i', 'var'},
          n.Number{'dec', '1'},
          'le',
          n.Number{'dec', '10'},
          nil,
          n.Block{{}}}
    }})
  end)
  it("reverse with comparations", function()
    assert.parse_ast(euluna_parser, "for i:number=10,>0,-1 do end",
      n.Block{{
        n.ForNum{
          n.IdDecl{'i', 'var', n.Type{'number'}},
          n.Number{'dec', '10'},
          'gt',
          n.Number{'dec', '0'},
          n.UnaryOp{'neg', n.Number{'dec', '1'}},
          n.Block{{}}}
    }})
  end)
  it("in", function()
    assert.parse_ast(euluna_parser, "for i in a,b,c do end",
      n.Block{{
        n.ForIn{
          { n.IdDecl{'i', 'var'} },
          { n.Id{'a'}, n.Id{'b'}, n.Id{'c'} },
          n.Block{{}}}
    }})
  end)
  it("in typed", function()
    assert.parse_ast(euluna_parser, "for i:int8,j:int16,k:int32 in iter() do end",
      n.Block{{
        n.ForIn{
          { n.IdDecl{'i', 'var', n.Type{'int8'}},
            n.IdDecl{'j', 'var', n.Type{'int16'}},
            n.IdDecl{'k', 'var', n.Type{'int32'}}
          },
          { n.Call{{}, {}, n.Id{'iter'}} },
          n.Block{{}}}
    }})
  end)
end)

--------------------------------------------------------------------------------
-- goto statement
--------------------------------------------------------------------------------
describe("statement goto", function()
  it("simple", function()
    assert.parse_ast(euluna_parser, "goto mylabel",
      n.Block{{
        n.Goto{'mylabel'}
    }})
  end)
  it("label", function()
    assert.parse_ast(euluna_parser, "::mylabel::",
      n.Block{{
        n.Label{'mylabel'}
    }})
  end)
  it("complex", function()
    assert.parse_ast(euluna_parser, "::mylabel:: f() if a then goto mylabel end",
      n.Block{{
        n.Label{'mylabel'},
        n.Call{{}, {}, n.Id{'f'}, true},
        n.If{{ {n.Id{'a'}, n.Block{{n.Goto{'mylabel'}}} } }}
    }})
  end)
end)

--------------------------------------------------------------------------------
-- variable declaration statement
--------------------------------------------------------------------------------
describe("statement variable declaration", function()
  it("local variable", function()
    assert.parse_ast(euluna_parser, [[
      local a
      local a: integer
    ]],
      n.Block{{
        n.VarDecl{'local', 'var', { n.IdDecl{'a', 'var'} }},
        n.VarDecl{'local', 'var', { n.IdDecl{'a', 'var', n.Type{'integer'}} }}
    }})
  end)
  it("local variable assignment", function()
    assert.parse_ast(euluna_parser, [[
      local a = b
      local a: integer = b
    ]],
      n.Block{{
        n.VarDecl{'local', 'var', { n.IdDecl{'a', 'var'} }, { n.Id{'b'} }},
        n.VarDecl{'local', 'var',
          { n.IdDecl{'a', 'var', n.Type{'integer'}} },
          { n.Id{'b'} }}
    }})
  end)
  it("non local variable", function()
    assert.parse_ast(euluna_parser, "var a",
      n.Block{{
        n.VarDecl{nil, 'var', { n.IdDecl{'a', 'var'} }}
    }})
  end)
  it("variable mutabilities", function()
    assert.parse_ast(euluna_parser, [[
      var a = b
      val a = b
      val& a = b
      local var& a = b
    ]],
      n.Block{{
        n.VarDecl{nil, 'var', { n.IdDecl{'a', 'var'} }, { n.Id{'b'} }},
        n.VarDecl{nil, 'val', { n.IdDecl{'a', 'var'} }, { n.Id{'b'} }},
        n.VarDecl{nil, 'val&', { n.IdDecl{'a', 'var'} }, { n.Id{'b'} }},
        n.VarDecl{'local', 'var&', { n.IdDecl{'a', 'var'} }, { n.Id{'b'} }},
    }})
  end)
  it("variable multiple assigments", function()
    assert.parse_ast(euluna_parser, "local a,b,c = x,y,z",
      n.Block{{
        n.VarDecl{'local', 'var',
          { n.IdDecl{'a', 'var'}, n.IdDecl{'b', 'var'}, n.IdDecl{'c', 'var'} },
          { n.Id{'x'}, n.Id{'y'}, n.Id{'z'} }},
    }})
  end)
end)

--------------------------------------------------------------------------------
-- assignment statement
--------------------------------------------------------------------------------
describe("statement assignment", function()
  it("simple", function()
    assert.parse_ast(euluna_parser, "a = b",
      n.Block{{
        n.Assign{
          { n.Id{'a'} },
          { n.Id{'b'} }},
    }})
  end)
  it("multiple", function()
    assert.parse_ast(euluna_parser, "a,b,c = x,y,z",
      n.Block{{
        n.Assign{
          { n.Id{'a'}, n.Id{'b'}, n.Id{'c'} },
          { n.Id{'x'}, n.Id{'y'}, n.Id{'z'} }},
    }})
  end)
  it("on indexes", function()
    assert.parse_ast(euluna_parser, "a.b, a[b], a[b][c], f(a).b = x,y,z,w",
      n.Block{{
        n.Assign{
          { n.DotIndex{'b', n.Id{'a'}},
            n.ArrayIndex{n.Id{'b'}, n.Id{'a'}},
            n.ArrayIndex{n.Id{'c'}, n.ArrayIndex{n.Id{'b'}, n.Id{'a'}}},
            n.DotIndex{'b', n.Call{{}, {n.Id{'a'}}, n.Id{'f'}}},
          },
          { n.Id{'x'}, n.Id{'y'}, n.Id{'z'}, n.Id{'w'} }}
    }})
  end)
  it("on calls", function()
    assert.parse_ast(euluna_parser, "f().a, a.b()[c].d = 1, 2",
      n.Block{{
        n.Assign{{
          n.DotIndex{"a", n.Call{{}, {}, n.Id{"f"}}},
          n.DotIndex{
              "d",
              n.ArrayIndex{
                n.Id{"c"},
                n.Call{{}, {}, n.DotIndex{"b", n.Id{"a"}}}
              }
            }
          },
          { n.Number{"dec", "1"},
            n.Number{"dec", "2"}
          }
    }}})
  end)
end)

--------------------------------------------------------------------------------
-- function statement
--------------------------------------------------------------------------------
describe("statement function", function()
  it("simple", function()
    assert.parse_ast(euluna_parser, "function f() end",
      n.Block{{
        n.FuncDef{nil, n.Id{'f'}, {}, {}, n.Block{{}} }
    }})
  end)
  it("local and typed", function()
    assert.parse_ast(euluna_parser, "local function f(a, b: int): string end",
      n.Block{{
        n.FuncDef{'local', n.Id{'f'},
          { n.IdDecl{'a', 'var'}, n.IdDecl{'b', 'var', n.Type{'int'}} },
          { n.Type{'string'} },
          n.Block{{}} }
    }})
  end)
  it("with colon index", function()
    assert.parse_ast(euluna_parser, "function a:f() end",
      n.Block{{
        n.FuncDef{nil, n.ColonIndex{'f', n.Id{'a'}}, {}, {}, n.Block{{}} }
    }})
  end)
  it("with dot index", function()
    assert.parse_ast(euluna_parser, "function a.f() end",
      n.Block{{
        n.FuncDef{nil, n.DotIndex{'f', n.Id{'a'}}, {}, {}, n.Block{{}} }
    }})
  end)
end)

--------------------------------------------------------------------------------
-- operators
--------------------------------------------------------------------------------
describe("operator", function()
  it("'or'", function()
    assert.parse_ast(euluna_parser, "return a or b",
      n.Block{{
        n.Return{{
          n.BinaryOp{'or', n.Id{'a'}, n.Id{'b'}
    }}}}})
  end)
  it("'and'", function()
    assert.parse_ast(euluna_parser, "return a and b",
      n.Block{{
        n.Return{{
          n.BinaryOp{'and', n.Id{'a'}, n.Id{'b'}
    }}}}})
  end)
  it("'<'", function()
    assert.parse_ast(euluna_parser, "return a < b",
      n.Block{{
        n.Return{{
          n.BinaryOp{'lt', n.Id{'a'}, n.Id{'b'}
    }}}}})
  end)
  it("'>'", function()
    assert.parse_ast(euluna_parser, "return a > b",
      n.Block{{
        n.Return{{
          n.BinaryOp{'gt', n.Id{'a'}, n.Id{'b'}
    }}}}})
  end)
  it("'<='", function()
    assert.parse_ast(euluna_parser, "return a <= b",
      n.Block{{
        n.Return{{
          n.BinaryOp{'le', n.Id{'a'}, n.Id{'b'}
    }}}}})
  end)
  it("'>='", function()
    assert.parse_ast(euluna_parser, "return a >= b",
      n.Block{{
        n.Return{{
          n.BinaryOp{'ge', n.Id{'a'}, n.Id{'b'}
    }}}}})
  end)
  it("'~='", function()
    assert.parse_ast(euluna_parser, "return a ~= b",
      n.Block{{
        n.Return{{
          n.BinaryOp{'ne', n.Id{'a'}, n.Id{'b'}
    }}}}})
  end)
  it("'=='", function()
    assert.parse_ast(euluna_parser, "return a == b",
      n.Block{{
        n.Return{{
          n.BinaryOp{'eq', n.Id{'a'}, n.Id{'b'}
    }}}}})
  end)
  it("'|'", function()
    assert.parse_ast(euluna_parser, "return a | b",
      n.Block{{
        n.Return{{
          n.BinaryOp{'bor', n.Id{'a'}, n.Id{'b'}
    }}}}})
  end)
  it("'~'", function()
    assert.parse_ast(euluna_parser, "return a ~ b",
      n.Block{{
        n.Return{{
          n.BinaryOp{'bxor', n.Id{'a'}, n.Id{'b'}
    }}}}})
  end)
  it("'&'", function()
    assert.parse_ast(euluna_parser, "return a & b",
      n.Block{{
        n.Return{{
          n.BinaryOp{'band', n.Id{'a'}, n.Id{'b'}
    }}}}})
  end)
  it("'<<'", function()
    assert.parse_ast(euluna_parser, "return a << b",
      n.Block{{
        n.Return{{
          n.BinaryOp{'shl', n.Id{'a'}, n.Id{'b'}
    }}}}})
  end)
  it("'>>'", function()
    assert.parse_ast(euluna_parser, "return a >> b",
      n.Block{{
        n.Return{{
          n.BinaryOp{'shr', n.Id{'a'}, n.Id{'b'}
    }}}}})
  end)
  it("'..'", function()
    assert.parse_ast(euluna_parser, "return a .. b",
      n.Block{{
        n.Return{{
          n.BinaryOp{'concat', n.Id{'a'}, n.Id{'b'}
    }}}}})
  end)
  it("'+'", function()
    assert.parse_ast(euluna_parser, "return a + b",
      n.Block{{
        n.Return{{
          n.BinaryOp{'add', n.Id{'a'}, n.Id{'b'}
    }}}}})
  end)
  it("'-'", function()
    assert.parse_ast(euluna_parser, "return a - b",
      n.Block{{
        n.Return{{
          n.BinaryOp{'sub', n.Id{'a'}, n.Id{'b'}
    }}}}})
  end)
  it("'*'", function()
    assert.parse_ast(euluna_parser, "return a * b",
      n.Block{{
        n.Return{{
          n.BinaryOp{'mul', n.Id{'a'}, n.Id{'b'}
    }}}}})
  end)
  it("'/'", function()
    assert.parse_ast(euluna_parser, "return a / b",
      n.Block{{
        n.Return{{
          n.BinaryOp{'div', n.Id{'a'}, n.Id{'b'}
    }}}}})
  end)
  it("'//'", function()
    assert.parse_ast(euluna_parser, "return a // b",
      n.Block{{
        n.Return{{
          n.BinaryOp{'idiv', n.Id{'a'}, n.Id{'b'}
    }}}}})
  end)
  it("'%'", function()
    assert.parse_ast(euluna_parser, "return a % b",
      n.Block{{
        n.Return{{
          n.BinaryOp{'mod', n.Id{'a'}, n.Id{'b'}
    }}}}})
  end)
  it("'not'", function()
    assert.parse_ast(euluna_parser, "return not a",
      n.Block{{
        n.Return{{
          n.UnaryOp{'not', n.Id{'a'}
    }}}}})
  end)
  it("'#'", function()
    assert.parse_ast(euluna_parser, "return #a",
      n.Block{{
        n.Return{{
          n.UnaryOp{'len', n.Id{'a'}
    }}}}})
  end)
  it("'-'", function()
    assert.parse_ast(euluna_parser, "return -a",
      n.Block{{
        n.Return{{
          n.UnaryOp{'neg', n.Id{'a'}
    }}}}})
  end)
  it("'~'", function()
    assert.parse_ast(euluna_parser, "return ~a",
      n.Block{{
        n.Return{{
          n.UnaryOp{'bnot', n.Id{'a'}
    }}}}})
  end)
  it("'$'", function()
    assert.parse_ast(euluna_parser, "return $a",
      n.Block{{
        n.Return{{
          n.UnaryOp{'tostring', n.Id{'a'}
    }}}}})
  end)
  it("'&'", function()
    assert.parse_ast(euluna_parser, "return &a",
      n.Block{{
        n.Return{{
          n.UnaryOp{'ref', n.Id{'a'}
    }}}}})
  end)
  it("'*'", function()
    assert.parse_ast(euluna_parser, "return *a",
      n.Block{{
        n.Return{{
          n.UnaryOp{'deref', n.Id{'a'}
    }}}}})
  end)
  it("'^'", function()
    assert.parse_ast(euluna_parser, "return a ^ b",
      n.Block{{
        n.Return{{
          n.BinaryOp{'pow', n.Id{'a'}, n.Id{'b'}
    }}}}})
  end)
end)

--------------------------------------------------------------------------------
-- operators precedence rules
--------------------------------------------------------------------------------
--[[
Operator precedence in Lua follows the table below, from lower
to higher priority:
  or
  and
  <     >     <=    >=    ~=    ==
  |
  ~
  &
  <<    >>
  ..
  +     -
  *     /     //    %
  unary operators (not   #     -     ~)
  ^
All binary operators are left associative, except for `^´ (exponentiation)
and `..´ (concatenation), which are right associative.
]]
describe("operators following precedence rules for", function()
  it("`and` and `or`", function()
    assert.parse_ast(euluna_parser, "return a and b or c",
      n.Block{{
        n.Return{
          {n.BinaryOp{"or", n.BinaryOp{"and", n.Id{"a"}, n.Id{"b"}}, n.Id{"c"}}}
        }
    }})
    assert.parse_ast(euluna_parser, "return a or b and c",
      n.Block{{
        n.Return{
          {n.BinaryOp{"or", n.Id{"a"}, n.BinaryOp{"and", n.Id{"b"}, n.Id{"c"}}}}
        }
    }})
    assert.parse_ast(euluna_parser, "return a and (b or c)",
      n.Block{{
        n.Return{
          {n.BinaryOp{"and", n.Id{"a"}, n.Paren{n.BinaryOp{"or", n.Id{"b"}, n.Id{"c"}}}}}
        }
    }})
  end)
  it("lua procedence rules", function()
    assert.parse_ast(euluna_parser, "return a or b and c < d | e ~ f & g << h .. i + j * k ^ #l",
      n.Block{{
        n.Return{{
          n.BinaryOp{"or", n.Id{"a"},
            n.BinaryOp{"and", n.Id{"b"},
              n.BinaryOp{"lt", n.Id{"c"},
                n.BinaryOp{"bor", n.Id{"d"},
                  n.BinaryOp{"bxor", n.Id{"e"},
                    n.BinaryOp{"band", n.Id{"f"},
                      n.BinaryOp{"shl", n.Id{"g"},
                        n.BinaryOp{"concat", n.Id{"h"},
                          n.BinaryOp{"add", n.Id{"i"},
                            n.BinaryOp{"mul", n.Id{"j"},
                              n.BinaryOp{"pow", n.Id{"k"},
                                n.UnaryOp{"len", n.Id{"l"}
    }}}}}}}}}}}}}}}})
  end)
  it("lua associative rules", function()
    assert.parse_ast(euluna_parser, "return a + b + c",
    n.Block{{
      n.Return{{
        n.BinaryOp{"add",
          n.BinaryOp{"add", n.Id{"a"}, n.Id{"b"}},
          n.Id{"c"}
    }}}}})
    assert.parse_ast(euluna_parser, "return a .. b .. c",
    n.Block{{
      n.Return{{
        n.BinaryOp{"concat", n.Id{"a"},
          n.BinaryOp{"concat", n.Id{"b"}, n.Id{"c"}}
    }}}}})
    assert.parse_ast(euluna_parser, "return a ^ b ^ c",
    n.Block{{
      n.Return{{
        n.BinaryOp{"pow", n.Id{"a"},
          n.BinaryOp{"pow", n.Id{"b"}, n.Id{"c"}}
    }}}}})
  end)
end)


--------------------------------------------------------------------------------
-- type expressions
--------------------------------------------------------------------------------
describe("type expression", function()
  it("function", function()
    assert.parse_ast(euluna_parser, "local f: function<()>",
      n.Block{{
        n.VarDecl{'local', 'var',
          { n.IdDecl{'f', 'var', n.FuncType{{}, {}}} }
    }}})
    assert.parse_ast(euluna_parser, "local f: function<(int): string>",
      n.Block{{
        n.VarDecl{'local', 'var',
          { n.IdDecl{'f', 'var', n.FuncType{{n.Type{'int'}}, {n.Type{'string'}}}} }
    }}})
    assert.parse_ast(euluna_parser, "local f: function<(int, uint): string, bool>",
      n.Block{{
        n.VarDecl{'local', 'var',
          { n.IdDecl{'f', 'var', n.FuncType{
            {n.Type{'int'}, n.Type{'uint'}},
            {n.Type{'string'}, n.Type{'bool'}}}} }
    }}})
  end)
  it("composed type", function()
    assert.parse_ast(euluna_parser, "local t: table<int>",
      n.Block{{
        n.VarDecl{'local', 'var',
          { n.IdDecl{'t', 'var', n.ComposedType{'table',
            { n.Type{'int'} }}} }
    }}})
    assert.parse_ast(euluna_parser, "local t: table<int, string>",
      n.Block{{
        n.VarDecl{'local', 'var',
          { n.IdDecl{'t', 'var', n.ComposedType{'table',
            { n.Type{'int'}, n.Type{'string'} }}} }
    }}})
  end)
  it("record type", function()
    assert.parse_ast(euluna_parser, "local r: record{a: int}",
      n.Block{{
        n.VarDecl{'local', 'var', {
          n.IdDecl{'r', 'var', n.RecordType{{
            n.RecordField{'a', n.Type{'int'}}
    }}}}}}})
    assert.parse_ast(euluna_parser, "local r: record{a: int, b: bool}",
      n.Block{{
        n.VarDecl{'local', 'var',
          { n.IdDecl{'r', 'var', n.RecordType{{
            n.RecordField{'a', n.Type{'int'}},
            n.RecordField{'b', n.Type{'bool'}}
    }}}}}}})
    assert.parse_ast(euluna_parser,
      "local r: record{f: function<(int, uint): string, bool>, t: table<int>}",
      n.Block{{
        n.VarDecl{'local', 'var',
          { n.IdDecl{'r', 'var', n.RecordType{{
            n.RecordField{'f', n.FuncType{
              {n.Type{'int'}, n.Type{'uint'}},
              {n.Type{'string'}, n.Type{'bool'}}}},
            n.RecordField{'t', n.ComposedType{'table', { n.Type{'int'} }}},
    }}}}}}})
    assert.parse_ast(euluna_parser, "local r: record{a: record{c: int}, b: bool}",
      n.Block{{
        n.VarDecl{'local', 'var',
          { n.IdDecl{'r', 'var', n.RecordType{{
            n.RecordField{'a', n.RecordType{{
              n.RecordField{'c', n.Type{'int'}}
            }}},
            n.RecordField{'b', n.Type{'bool'}}
    }}}}}}})
  end)
  it("enum type", function()
    assert.parse_ast(euluna_parser, "local e: enum{a}",
      n.Block{{
        n.VarDecl{'local', 'var', {
          n.IdDecl{'e', 'var', n.EnumType{nil, {
            n.EnumField{'a'},
    }}}}}}})
    assert.parse_ast(euluna_parser, "local e: enum<int>{a,b=2,}",
      n.Block{{
        n.VarDecl{'local', 'var', {
          n.IdDecl{'e', 'var', n.EnumType{n.Type{'int'}, {
            n.EnumField{'a'},
            n.EnumField{'b', n.Number{'dec','2'}},
    }}}}}}})
  end)
  it("inference", function()
    assert.parse_ast(euluna_parser, "local Integer = @integer",
      n.Block{{
        n.VarDecl{'local', 'var',
          {n.IdDecl{'Integer', 'var'} },
          {n.TypeInfer{n.Type{'integer'}}}
    }}})
    assert.parse_ast(euluna_parser, "local MyRecord = @record{a: int}",
      n.Block{{
        n.VarDecl{'local', 'var',
          {n.IdDecl{'MyRecord', 'var'} },
          {n.TypeInfer{n.RecordType{{n.RecordField{'a', n.Type{'int'}}}}}}
    }}})
    assert.parse_ast(euluna_parser, "local a = @integer(0)",
      n.Block{{
        n.VarDecl{'local', 'var',
          {n.IdDecl{'a', 'var'} },
          {n.Call {{},{n.Number{"dec","0"}},n.TypeInfer{n.Type{"integer"}}}
        }
    }}})
  end)
end)

--------------------------------------------------------------------------------
-- live grammar change
--------------------------------------------------------------------------------
describe("live grammar change for", function()
  it("return keyword", function()
    local grammar = euluna_grammar:clone()
    local astbuilder = euluna_astbuilder:clone()
    local parser = euluna_parser:clone()
    parser:set_astbuilder(astbuilder)
    parser:add_keyword("do_return")
    grammar:set_pegs([[
      stat_return <-
        ({} %DO_RETURN -> 'Return' {| (expr (%COMMA expr)*)? |} %SEMICOLON?) -> to_astnode
    ]], { to_nothing = function() end }, true)
    parser:set_peg('sourcecode', grammar:build())
    parser:remove_keyword("return")

    assert.parse_ast(parser, "do_return",
      n.Block{{
        n.Return{{}}}})
    assert.parse_ast_error(parser, "return", 'UnexpectedSyntaxAtEOF')
  end)

  it("return keyword (revert)", function()
    assert.parse_ast(euluna_parser, "return",
      n.Block{{
        n.Return{{}}}})
    assert.parse_ast_error(euluna_parser, "do_return", 'UnexpectedSyntaxAtEOF')
  end)
end)

end)
