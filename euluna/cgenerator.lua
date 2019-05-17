local CEmitter = require 'euluna.cemitter'
local iters = require 'euluna.utils.iterators'
local traits = require 'euluna.utils.traits'
local pegger = require 'euluna.utils.pegger'
local fs = require 'euluna.utils.fs'
local config = require 'euluna.configer'.get()
local cdefs = require 'euluna.cdefs'
local cbuiltins = require 'euluna.cbuiltins'
local typedefs = require 'euluna.typedefs'
local CContext = require 'euluna.ccontext'
local primtypes = typedefs.primtypes
local visitors = {}

function visitors.Number(_, node, emitter)
  local base, int, frac, exp, literal = node:args()
  local value, integral, type = node.attr.value, node.attr.integral, node.attr.type
  if not type:is_float() and literal then
    emitter:add_nodectypecast(node)
  end
  emitter:add_composed_number(base, int, frac, exp, value:abs())
  if type:is_unsigned() then
    emitter:add('U')
  elseif type:is_float32() and base == 'dec' then
    emitter:add(integral and '.0f' or 'f')
  elseif type:is_float64() and base == 'dec' then
    emitter:add(integral and '.0' or '')
  end
end

function visitors.String(context, node, emitter)
  local decemitter = CEmitter(context)
  local value = node.attr.value
  local len = #value
  local varname = context:genuniquename('strlit')
  local quoted_value = pegger.double_quote_c_string(value)
  decemitter:add_indent_ln('static const struct { uintptr_t len, res; char data[', len + 1, ']; }')
  decemitter:add_indent_ln('  ', varname, ' = {', len, ', ', len, ', ', quoted_value, '};')
  emitter:add('(const ', primtypes.string, ')&', varname)
  context:add_declaration(decemitter:generate(), varname)
end

function visitors.Boolean(_, node, emitter)
  emitter:add_booleanlit(node.attr.value)
end

-- TODO: Nil
-- TODO: Varargs

function visitors.Table(context, node, emitter)
  local childnodes, type = node:arg(1), node.attr.type
  local len = #childnodes
  if len == 0 and (type:is_record() or type:is_array() or type:is_arraytable()) then
    emitter:add_nodezerotype(node)
  elseif type:is_record() then
    emitter:add_nodectypecast(node)
    emitter:add('{', childnodes, '}')
  elseif type:is_array() then
    emitter:add_nodectypecast(node)
    emitter:add('{{', childnodes, '}}')
  elseif type:is_arraytable() then
    emitter:add(context:typename(type), '_create((', type.subtype, '[', len, ']){', childnodes, '},', len, ')')
  else --luacov:disable
    error('not implemented yet')
  end --luacov:enable
end

function visitors.Pair(_, node, emitter)
  local namenode, valuenode = node:args()
  local parenttype = node.attr.parenttype
  if parenttype and parenttype:is_record() then
    assert(traits.is_string(namenode))
    emitter:add('.', cdefs.quotename(namenode), ' = ', valuenode)
  else --luacov:disable
    error('not implemented yet')
  end --luacov:enable
end

-- TODO: Function

function visitors.Pragma(context, node, emitter)
  local attr = node.attr
  if attr.cinclude then
    context:add_include(attr.cinclude)
  end
  if attr.cemit then
    emitter:add_ln(attr.cemit)
  end
  if attr.cdefine then
    context:add_declaration(string.format('#define %s\n', attr.cdefine))
  end
  if attr.cflags then
    table.insert(context.compileopts.cflags, attr.cflags)
  end
  if attr.ldflags then
    table.insert(context.compileopts.ldflags, attr.ldflags)
  end
  if attr.linklib then
    table.insert(context.compileopts.linklibs, attr.linklib)
  end
end

function visitors.Id(context, node, emitter)
  if node.attr.type:is_nilptr() then
    emitter:add_null()
  else
    emitter:add(context:declname(node))
  end
end

function visitors.Paren(_, node, emitter)
  local innernode = node:args()
  emitter:add('(', innernode, ')')
end

visitors.FuncType = visitors.Type
visitors.ArrayTableType = visitors.Type
visitors.ArrayType = visitors.Type
visitors.PointerType = visitors.Type

function visitors.IdDecl(context, node, emitter)
  local attr = node.attr
  local type = node.attr.type
  if type:is_type() then return end
  if attr.const    then emitter:add('const ') end
  if attr.volatile then emitter:add('volatile ') end
  if attr.restrict then emitter:add('restrict ') end
  if attr.register then emitter:add('register ') end
  emitter:add(type, ' ', context:declname(node))
end

-- indexing
function visitors.DotIndex(_, node, emitter)
  local name, objnode = node:args()
  local type = objnode.attr.type
  if type:is_type() then
    local objtype = node.attr.holdedtype
    if objtype:is_enum() then
      emitter:add(objtype:get_field(name).value)
    else --luacov:disable
      error('not implemented yet')
    end --luacov:enable
  elseif type:is_pointer() then
    emitter:add(objnode, '->', cdefs.quotename(name))
  else
    emitter:add(objnode, '.', cdefs.quotename(name))
  end
end

-- TODO: ColonIndex

function visitors.ArrayIndex(context, node, emitter)
  local index, objnode = node:args()
  local objtype = objnode.attr.type
  local pointer = false
  if objtype:is_pointer() and not objtype:is_generic_pointer() then
    objtype = objtype.subtype
    pointer = true
  end
  if objtype:is_arraytable() then
    emitter:add('*', context:typename(objtype))
    emitter:add(node.assign and '_at(&' or '_get(&')
  end
  if pointer then
    emitter:add('(*', objnode, ')')
  else
    emitter:add(objnode)
  end
  if objtype:is_arraytable() then
    emitter:add(', ', index, ')')
  elseif objtype:is_array() then
    emitter:add('.data[', index, ']')
  else
    emitter:add('[', index, ']')
  end
end

local function izipargnodes(vars, argnodes)
  local iter = iters.izip(vars, argnodes)
  local lastargindex = #argnodes
  local lastargnode = argnodes[#argnodes]
  local calleetype = lastargnode and lastargnode.attr.calleetype
  if lastargnode and lastargnode.tag == 'Call' and (not calleetype or not calleetype:is_type()) then
    -- last arg is a runtime call
    assert(calleetype)
    -- we know the callee type
    return function()
      local i, var, argnode = iter()
      if not i then return nil end
      if i >= lastargindex and lastargnode.attr.multirets then
        -- argnode does not exists, fill with multiple returns type
        -- in case it doest not exists, the argtype will be false
        local callretindex = i - lastargindex + 1
        local argtype = calleetype:get_return_type(callretindex)
        return i, var, argnode, argtype, callretindex, calleetype
      else
        return i, var, argnode, argnode.attr.type, nil
      end
    end
  else
    -- no calls from last argument
    return function()
      local i, var, argnode = iter()
      if not i then return end
      -- we are sure this argument have no type, set argtype to false
      local argtype = argnode and argnode.attr.type
      return i, var, argnode, argtype
    end
  end
end

function visitors.Call(context, node, emitter)
  local argnodes, callee, block_call = node:args()
  local type = node.attr.type
  if block_call then
    emitter:add_indent()
  end
  local builtin
  if callee.tag == 'Id' then
    --TODO: move builtin detection to type checker
    local fname = callee[1]
    builtin = cbuiltins.functions[fname]
  end
  if builtin then
    callee = builtin(context, node, emitter)
  end
  local calleetype = node.attr.calleetype
  if calleetype:is_function() then
    -- function call
    local tmpargs = {}
    local tmpcount = 0
    local lastcalltmp
    local sequential = false
    for i,_,argnode,_,lastcallindex in izipargnodes(calleetype.argtypes, argnodes) do
      if (argnode and argnode.attr.sideeffect) or lastcallindex == 1 then
        -- expressions with side effects need to be evaluated in sequence
        -- and expressions with multiple returns needs to be stored in a temporary
        tmpcount = tmpcount + 1
        local tmpname = '__tmp' .. tmpcount
        tmpargs[i] = tmpname
        if lastcallindex == 1 then
          lastcalltmp = tmpname
        end
        if tmpcount >= 2 or lastcallindex then
          -- only need to evaluate in sequence mode if we have two or more temporaries
          -- or the last argument is a multiple return call
          sequential = true
        end
      end
    end

    if sequential then
      -- begin sequential expression
      if not block_call then
        emitter:add('(')
      end
      emitter:add_ln('{')
      emitter:inc_indent()

      for _,tmparg,argnode,argtype,_,lastcalletype in izipargnodes(tmpargs, argnodes) do
        -- set temporary values in sequence
        if tmparg then
          if lastcalletype then
            -- type for result of multiple return call
            argtype = context:funcretctype(lastcalletype)
          end
          emitter:add_indent_ln(argtype, ' ', tmparg, ' = ', argnode, ';')
        end
      end

      emitter:add_indent()
    end

    emitter:add(callee, '(')
    for i,funcargtype,argnode,argtype,lastcallindex in izipargnodes(calleetype.argtypes, argnodes) do
      if i > 1 then emitter:add(', ') end
      local arg = argnode
      if sequential then
        if lastcallindex then
          arg = string.format('%s.r%d', lastcalltmp, lastcallindex)
        elseif tmpargs[i] then
          arg = tmpargs[i]
        end
      end
      emitter:add_val2type(funcargtype, arg, argtype)
    end
    emitter:add(')')

    if calleetype:has_multiple_returns() and not node.attr.multirets then
      -- get just the first result in multiple return functions
      emitter:add('.r1')
    end

    if sequential then
      -- end sequential expression
      emitter:add_ln(';')
      emitter:dec_indent()
      emitter:add_indent('}')
      if not block_call then
        emitter:add(')')
      end
    end
  elseif calleetype:is_type() then
    -- type assertion
    assert(#argnodes == 1)
    local argnode = argnodes[1]
    if argnode.attr.type ~= type then
      -- type really differs, cast it
      emitter:add_ctypecast(type)
      emitter:add('(', argnode, ')')
    else
      -- same type, no need to cast
      emitter:add(argnode)
    end
  else
    --TODO: handle better calls on any types
    emitter:add(callee, '(', argnodes, ')')
  end
  if block_call then
    emitter:add_ln(";")
  end
end

function visitors.CallMethod(_, node, emitter)
  local name, args, callee, block_call = node:args()
  if block_call then
    emitter:add_indent()
  end
  local sep = #args > 0 and ', ' or ''
  emitter:add(callee, '.', cdefs.quotename(name), '(', callee, sep, args, ')')
  if block_call then
    emitter:add_ln()
  end
end

function visitors.Block(context, node, emitter)
  local statnodes = node:args()
  emitter:inc_indent()
  context:push_scope('block')
  do
    emitter:add_traversal_list(statnodes, '')
  end
  context:pop_scope()
  emitter:dec_indent()
end

function visitors.Return(context, node, emitter)
  local retnodes = node:args()
  local funcscope = context.scope:get_parent_of_kind('function')
  local numretnodes = #retnodes
  funcscope.has_return = true
  if funcscope.main then
    -- in main body
    node:assertraisef(numretnodes <= 1, "multiple returns in main is not supported yet")
    if numretnodes == 0 then
      -- main must always return an integer
      emitter:add_indent_ln('return 0;')
    else
      -- return one value (an integer expected)
      local retnode = retnodes[1]
      emitter:add_indent_ln('return ', retnode, ';')
    end
  else
    local functype = funcscope.functype
    local numfuncrets = functype:get_return_count()
    if numfuncrets == 0 then
      -- no returns
      assert(numretnodes == 0)
      emitter:add_indent_ln('return;')
    elseif numfuncrets == 1 then
      -- one return
      local retnode, rettype = retnodes[1], functype:get_return_type(1)
      emitter:add_indent('return ')
      if retnode then
        -- return value is present
        emitter:add_ln(retnode, ';')
      else
        -- no return value present, generate a zeroed one
        emitter:add_castedzerotype(rettype)
        emitter:add_ln(';')
      end
    else
      -- multiple returns
      local retctype = context:funcretctype(functype)
      emitter:add_indent('return (', retctype, '){')
      for i,retnode in iters.inpairs(retnodes, numfuncrets) do
        local rettype = functype:get_return_type(i)
        if i>1 then emitter:add(', ') end
        emitter:add_val2type(rettype, retnode)
      end
      emitter:add_ln('};')
    end
  end
end

function visitors.If(_, node, emitter)
  local ifparts, elseblock = node:args()
  for i,ifpart in ipairs(ifparts) do
    local condnode, blocknode = ifpart[1], ifpart[2]
    if i == 1 then
      emitter:add_indent("if(")
      emitter:add_val2type(primtypes.boolean, condnode)
      emitter:add_ln(") {")
    else
      emitter:add_indent("} else if(")
      emitter:add_val2type(primtypes.boolean, condnode)
      emitter:add_ln(") {")
    end
    emitter:add(blocknode)
  end
  if elseblock then
    emitter:add_indent_ln("} else {")
    emitter:add(elseblock)
  end
  emitter:add_indent_ln("}")
end

function visitors.Switch(_, node, emitter)
  local valnode, caseparts, elsenode = node:args()
  emitter:add_indent_ln("switch(", valnode, ") {")
  emitter:inc_indent()
  node:assertraisef(#caseparts > 0, "switch must have case parts")
  for casepart in iters.ivalues(caseparts) do
    local casenode, blocknode = casepart[1], casepart[2]
    emitter:add_indent_ln("case ", casenode, ': {')
    emitter:add(blocknode)
    emitter:inc_indent() emitter:add_indent_ln('break;') emitter:dec_indent()
    emitter:add_indent_ln("}")
  end
  if elsenode then
    emitter:add_indent_ln('default: {')
    emitter:add(elsenode)
    emitter:inc_indent() emitter:add_indent_ln('break;') emitter:dec_indent()
    emitter:add_indent_ln("}")
  end
  emitter:dec_indent()
  emitter:add_indent_ln("}")
end

function visitors.Do(_, node, emitter)
  local blocknode = node:args()
  if #blocknode[1] == 0 then return end
  emitter:add_indent_ln("{")
  emitter:add(blocknode)
  emitter:add_indent_ln("}")
end

function visitors.While(_, node, emitter)
  local condnode, blocknode = node:args()
  emitter:add_indent("while(")
  emitter:add_val2type(primtypes.boolean, condnode)
  emitter:add_ln(') {')
  emitter:add(blocknode)
  emitter:add_indent_ln("}")
end

function visitors.Repeat(_, node, emitter)
  local blocknode, condnode = node:args()
  emitter:add_indent_ln("do {")
  emitter:add(blocknode)
  emitter:add_indent('} while(!(')
  emitter:add_val2type(primtypes.boolean, condnode)
  emitter:add_ln('));')
end

function visitors.ForNum(context, node, emitter)
  local itvarnode, begvalnode, compop, endvalnode, stepvalnode, blocknode  = node:args()
  compop = node.attr.compop
  local fixedstep = node.attr.fixedstep
  context:push_scope('for')
  do
    local ccompop = cdefs.binary_ops[compop]
    local ittype = itvarnode.attr.type
    local itname = context:declname(itvarnode)
    emitter:add_indent('for(', ittype, ' __it = ')
    emitter:add_val2type(ittype, begvalnode)
    emitter:add(', __end = ')
    emitter:add_val2type(ittype, endvalnode)
    if not fixedstep then
      emitter:add(', __step = ')
      emitter:add_val2type(ittype, stepvalnode)
    end
    emitter:add('; ')
    if compop then
      emitter:add('__it ', ccompop, ' __end')
    else
      -- step is an expression, must detect the compare operation at runtime
      assert(not fixedstep)
      emitter:add('(__step >= 0 && __it <= __end) || (__step < 0 && __it >= __end)')
    end
    emitter:add('; __it = __it + ')
    if not fixedstep then
      emitter:add('__step')
    elseif stepvalnode then
      emitter:add_val2type(ittype, stepvalnode)
    else
      emitter:add('1')
    end
    emitter:add_ln(') {')
    emitter:inc_indent()
    emitter:add_indent_ln(itvarnode, ' = __it; EULUNA_UNUSED(', itname, ');')
    emitter:dec_indent()
    emitter:add(blocknode)
    emitter:add_indent_ln('}')
  end
  context:pop_scope()
end

-- TODO: ForIn

function visitors.Break(_, _, emitter)
  emitter:add_indent_ln('break;')
end

function visitors.Continue(_, _, emitter)
  emitter:add_indent_ln('continue;')
end

function visitors.Label(_, node, emitter)
  local name = node:args()
  emitter:add_indent_ln(cdefs.quotename(name), ':')
end

function visitors.Goto(_, node, emitter)
  local labelname = node:args()
  emitter:add_indent_ln('goto ', cdefs.quotename(labelname), ';')
end

local function visit_assignments(context, emitter, varnodes, valnodes, decl)
  local multiretvalname
  for _,varnode,valnode,valtype,lastcallindex in izipargnodes(varnodes, valnodes or {}) do
    local vartype = varnode.attr.type
    if not vartype:is_type() and not varnode.attr.nodecl then
      local declared, defined = false, false
      -- declare main variables in the top scope
      if decl and context.scope:is_main() then
        local decemitter = CEmitter(context)
        decemitter:add_indent('static ', varnode, ' = ')
        if valnode and valnode.attr.const then
          -- initialize to const values
          assert(not lastcallindex)
          decemitter:add_val2type(vartype, valnode)
          defined = true
        else
          -- pre initialize to zeros
          decemitter:add_zeroinit(vartype)
        end
        decemitter:add_ln(';')
        context:add_declaration(decemitter:generate())
        declared = true
      end

      if lastcallindex == 1 then
        --TODO: use another identifier other than pos
        multiretvalname = context:genuniquename('ret')
        local retctype = context:funcretctype(valnode.attr.calleetype)
        emitter:add_indent_ln(retctype, ' ', multiretvalname, ' = ', valnode, ';')
      end

      if not declared or (not defined and (valnode or lastcallindex)) then
        -- declare or define if needed
        if not declared then
          emitter:add_indent(varnode)
        else
          emitter:add_indent(context:declname(varnode))
        end
        emitter:add(' = ')
        if lastcallindex then
          local valname = string.format('%s.r%d', multiretvalname, lastcallindex)
          emitter:add_val2type(vartype, valname, valtype)
        else
          emitter:add_val2type(vartype, valnode)
        end
        emitter:add_ln(';')
      end
    elseif varnode.attr.cinclude then
      -- not declared, might be an imported variable from C
      context:add_include(varnode.attr.cinclude)
    end
  end
end

function visitors.VarDecl(context, node, emitter)
  local varscope, mutability, varnodes, valnodes = node:args()
  node:assertraisef(varscope == 'local', 'global variables not supported yet')
  visit_assignments(context, emitter, varnodes, valnodes, true)
end

function visitors.Assign(context, node, emitter)
  local vars, vals = node:args()
  visit_assignments(context, emitter, vars, vals)
end

function visitors.FuncDef(context, node)
  local varscope, varnode, argnodes, retnodes, pragmanodes, blocknode = node:args()
  node:assertraisef(varscope == 'local', 'non local scope for functions not supported yet')

  local attr = node.attr
  local type = attr.type
  local numrets = type:get_return_count()
  local decoration = 'static '
  local declare, define = not attr.nodecl, true

  if attr.cinclude then
    context:add_include(attr.cinclude)
  end
  if attr.cimport then
    decoration = ''
    define = false
  end

  if attr.volatile then decoration = decoration .. 'volatile ' end
  if attr.inline then decoration = decoration .. 'inline ' end
  if attr.noinline then decoration = decoration .. 'EULUNA_NOINLINE ' end
  if attr.noreturn then decoration = decoration .. 'EULUNA_NORETURN ' end

  local decemitter, defemitter = CEmitter(context), CEmitter(context)
  local retctype = context:funcretctype(type)
  if numrets > 1 then
    node:assertraisef(declare, 'functions with multiple returns must be declared')

    local retemitter = CEmitter(context)
    retemitter:add_indent_ln('typedef struct ', retctype, ' {')
    retemitter:inc_indent()
    for i=1,numrets do
      local rettype = type:get_return_type(i)
      assert(rettype)
      retemitter:add_indent_ln(rettype, ' ', 'r', i, ';')
    end
    retemitter:dec_indent()
    retemitter:add_indent_ln('} ', retctype, ';')
    context:add_declaration(retemitter:generate())
  end

  decemitter:add_indent(decoration, retctype, ' ')
  defemitter:add_indent(retctype, ' ')

  decemitter:add(varnode)
  defemitter:add(varnode)
  local funcscope = context:push_scope('function')
  funcscope.functype = type
  do
    decemitter:add_ln('(', argnodes, ');')
    defemitter:add_ln('(', argnodes, ') {')
    defemitter:add(blocknode)
  end
  context:pop_scope()
  defemitter:add_indent_ln('}')
  if declare then
    context:add_declaration(decemitter:generate())
  end
  if define then
    context:add_definition(defemitter:generate())
  end
end

function visitors.UnaryOp(_, node, emitter)
  local opname, argnode = node:args()
  local op = cdefs.unary_ops[opname]
  assert(op)
  local surround = node.attr.inoperator
  if surround then emitter:add('(') end
  if traits.is_string(op) then
    emitter:add(op, argnode)
  else
    local builtin = cbuiltins.operators[opname]
    builtin(node, emitter, argnode)
  end
  if surround then emitter:add(')') end
end

function visitors.BinaryOp(_, node, emitter)
  local opname, lnode, rnode = node:args()
  local type = node.attr.type
  local op = cdefs.binary_ops[opname]
  assert(op)
  local surround = node.attr.inoperator
  if surround then emitter:add('(') end
  if node.attr.dynamic_conditional then
    emitter:add_ln('({')
    emitter:inc_indent()
    emitter:add_indent(type, ' t1_ = ')
    emitter:add_val2type(type, lnode)
    emitter:add_ln('; EULUNA_UNUSED(t1_);')
    emitter:add_indent_ln(type, ' t2_ = {0}; EULUNA_UNUSED(t2_);')
    if opname == 'and' then
      emitter:add_indent('bool cond_ = ')
      emitter:add_val2type(primtypes.boolean, 't1_', type)
      emitter:add_ln(';')
      emitter:add_indent_ln('if(cond_) {')
      emitter:add_indent('  t2_ = ')
      emitter:add_val2type(type, rnode)
      emitter:add_ln(';')
      emitter:add_indent('  cond_ = ')
      emitter:add_val2type(primtypes.boolean, 't2_', type)
      emitter:add_ln(';')
      emitter:add_indent_ln('}')
      emitter:add_indent_ln('cond_ ? t2_ : (', type, '){0};')
    elseif opname == 'or' then
      emitter:add_indent('bool cond_ = ')
      emitter:add_val2type(primtypes.boolean, 't1_', type)
      emitter:add_ln(';')
      emitter:add_indent_ln('if(cond_)')
      emitter:add_indent('  t2_ = ')
      emitter:add_val2type(type, rnode)
      emitter:add_ln(';')
      emitter:add_indent_ln('cond_ ? t1_ : t2_;')
    end
    emitter:dec_indent()
    emitter:add_indent('})')
  else
    local sequential = lnode.attr.sideeffect and rnode.attr.sideeffect
    local lname = lnode
    local rname = rnode
    if sequential then
      -- need to evaluate args in sequence when one expression has side effects
      emitter:add_ln('({')
      emitter:inc_indent()
      emitter:add_indent_ln(lnode.attr.type, ' t1_ = ', lnode, ';')
      emitter:add_indent_ln(rnode.attr.type, ' t2_ = ', rnode, ';')
      emitter:add_indent()
      lname = 't1_'
      rname = 't2_'
    end
    if traits.is_string(op) then
      emitter:add(lname, ' ', op, ' ', rname)
    else
      local builtin = cbuiltins.operators[opname]
      builtin(node, emitter, lnode, rnode, lname, rname)
    end
    if sequential then
      emitter:add_ln(';')
      emitter:dec_indent()
      emitter:add_indent('})')
    end
  end
  if surround then emitter:add(')') end
end

local generator = {}

function generator.generate(ast)
  local context = CContext(visitors)
  context.runtime_path = fs.join(config.runtime_path, 'c')

  context:ensure_runtime('euluna_core')

  local mainemitter = CEmitter(context, -1)

  local main_scope = context:push_scope('function')
  main_scope.main = true
  do
    mainemitter:inc_indent()
    mainemitter:add_ln("int euluna_main() {")
    mainemitter:add_traversal(ast)
    if not main_scope.has_return then
      -- main() must always return an integer
      mainemitter:inc_indent()
      mainemitter:add_indent_ln("return 0;")
      mainemitter:dec_indent()
    end
    mainemitter:add_ln("}")
    mainemitter:dec_indent()
  end
  context:pop_scope()

  context:add_definition(mainemitter:generate())

  context:ensure_runtime('euluna_main')
  context:evaluate_templates()

  local code = table.concat({
    table.concat(context.declarations),
    table.concat(context.definitions)
  })

  return code, context.compileopts
end

generator.compiler = require('euluna.ccompiler')

return generator
