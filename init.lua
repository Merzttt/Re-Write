local RunBytecode = coroutine.wrap(function()
	-- // Environment changes in the VM are not supposed to alter the behaviour of the VM so we localise globals beforehand
	local type = type
	local pcall = pcall
	local error = error
	local tonumber = tonumber
	local assert = assert
	local setmetatable = setmetatable

	local string_format = string.format

	local table_move = table.move
	local table_pack = table.pack
	local table_unpack = table.unpack
	local table_create = table.create
	local table_insert = table.insert
	local table_remove = table.remove

	local coroutine_create = coroutine.create
	local coroutine_yield = coroutine.yield
	local coroutine_yield = coroutine.yield
	local coroutine_resume = coroutine.resume
	local coroutine_close = coroutine.close

	local buffer_fromstring = buffer.fromstring
	local buffer_len = buffer.len
	local buffer_readu8 = buffer.readu8
	local buffer_readu32 = buffer.readu32
	local buffer_readstring = buffer.readstring
	local buffer_readf32 = buffer.readf32
	local buffer_readf64 = buffer.readf64

	local bit32_bor = bit32.bor
	local bit32_band = bit32.band
	local bit32_btest = bit32.btest
	local bit32_rshift = bit32.rshift
	local bit32_lshift = bit32.lshift
	local bit32_extract = bit32.extract

	local ttisnumber = function(v) return type(v) == "number" end
	local ttisstring = function(v) return type(v) == "string" end
	local ttisboolean = function(v) return type(v) == "boolean" end
	local ttisfunction = function(v) return type(v) == "function" end

	-- // opList contains information about the instruction, each instruction is defined in this format:
	-- // {OP_NAME, OP_MODE, K_MODE, HAS_AUX}
	-- // OP_MODE specifies what type of registers the instruction uses if any
	--		0 = NONE
	--		1 = A
	--		2 = AB
	--		3 = ABC
	--		4 = AD
	--		5 = AE
	-- // K_MODE specifies if the instruction has a register that holds a constant table index, which will be directly converted to the constant in the 2nd pass
	--		0 = NONE
	--		1 = AUX
	--		2 = C
	--		3 = D
	--		4 = AUX import
	--		5 = AUX boolean low 1 bit
	--		6 = AUX number low 24 bits
	-- // HAS_AUX boolean specifies whether the instruction is followed up with an AUX word, which may be used to execute the instruction.

	local opList = {
		{ "NOP", 0, 0, false },
		{ "BREAK", 0, 0, false },
		{ "LOADNIL", 1, 0, false },
		{ "LOADB", 3, 0, false },
		{ "LOADN", 4, 0, false },
		{ "LOADK", 4, 3, false },
		{ "MOVE", 2, 0, false },
		{ "GETGLOBAL", 1, 1, true },
		{ "SETGLOBAL", 1, 1, true },
		{ "GETUPVAL", 2, 0, false },
		{ "SETUPVAL", 2, 0, false },
		{ "CLOSEUPVALS", 1, 0, false },
		{ "GETIMPORT", 4, 4, true },
		{ "GETTABLE", 3, 0, false },
		{ "SETTABLE", 3, 0, false },
		{ "GETTABLEKS", 3, 1, true },
		{ "SETTABLEKS", 3, 1, true },
		{ "GETTABLEN", 3, 0, false },
		{ "SETTABLEN", 3, 0, false },
		{ "NEWCLOSURE", 4, 0, false },
		{ "NAMECALL", 3, 1, true },
		{ "CALL", 3, 0, false },
		{ "RETURN", 2, 0, false },
		{ "JUMP", 4, 0, false },
		{ "JUMPBACK", 4, 0, false },
		{ "JUMPIF", 4, 0, false },
		{ "JUMPIFNOT", 4, 0, false },
		{ "JUMPIFEQ", 4, 0, true },
		{ "JUMPIFLE", 4, 0, true },
		{ "JUMPIFLT", 4, 0, true },
		{ "JUMPIFNOTEQ", 4, 0, true },
		{ "JUMPIFNOTLE", 4, 0, true },
		{ "JUMPIFNOTLT", 4, 0, true },
		{ "ADD", 3, 0, false },
		{ "SUB", 3, 0, false },
		{ "MUL", 3, 0, false },
		{ "DIV", 3, 0, false },
		{ "MOD", 3, 0, false },
		{ "POW", 3, 0, false },
		{ "ADDK", 3, 2, false },
		{ "SUBK", 3, 2, false },
		{ "MULK", 3, 2, false },
		{ "DIVK", 3, 2, false },
		{ "MODK", 3, 2, false },
		{ "POWK", 3, 2, false },
		{ "AND", 3, 0, false },
		{ "OR", 3, 0, false },
		{ "ANDK", 3, 2, false },
		{ "ORK", 3, 2, false },
		{ "CONCAT", 3, 0, false },
		{ "NOT", 2, 0, false },
		{ "MINUS", 2, 0, false },
		{ "LENGTH", 2, 0, false },
		{ "NEWTABLE", 2, 0, true },
		{ "DUPTABLE", 4, 3, false },
		{ "SETLIST", 3, 0, true },
		{ "FORNPREP", 4, 0, false },
		{ "FORNLOOP", 4, 0, false },
		{ "FORGLOOP", 4, 8, true },
		{ "FORGPREP_INEXT", 4, 0, false },
		{ "FASTCALL3", 3, 1, true },
		{ "FORGPREP_NEXT", 4, 0, false },
		{ "DEP_FORGLOOP_NEXT", 0, 0, false },
		{ "GETVARARGS", 2, 0, false },
		{ "DUPCLOSURE", 4, 3, false },
		{ "PREPVARARGS", 1, 0, false },
		{ "LOADKX", 1, 1, true },
		{ "JUMPX", 5, 0, false },
		{ "FASTCALL", 3, 0, false },
		{ "COVERAGE", 5, 0, false },
		{ "CAPTURE", 2, 0, false },
		{ "SUBRK", 3, 7, false },
		{ "DIVRK", 3, 7, false },
		{ "FASTCALL1", 3, 0, false },
		{ "FASTCALL2", 3, 0, true },
		{ "FASTCALL2K", 3, 1, true },
		{ "FORGPREP", 4, 0, false },
		{ "JUMPXEQKNIL", 4, 5, true },
		{ "JUMPXEQKB", 4, 5, true },
		{ "JUMPXEQKN", 4, 6, true },
		{ "JUMPXEQKS", 4, 6, true },
		{ "IDIV", 3, 0, false },
		{ "IDIVK", 3, 2, false },
	}

	local LUA_MULTRET = -1
	local LUA_GENERALIZED_TERMINATOR = -2

	local function luau_newsettings()
		return {
			vectorCtor = function() warn("vectorCtor was not provided") end,
			vectorSize = 4,
			useNativeNamecall = false,
			namecallHandler = function() warn("Native __namecall handler was not provided") end,
			extensions = {},
			callHooks = {},
			errorHandling = true,
			generalizedIteration = true,
			allowProxyErrors = false,
			useImportConstants = false,
			staticEnvironment = {},
		}
	end

	local function luau_validatesettings(luau_settings)
		assert(type(luau_settings) == "table", "luau_settings should be a table")
		assert(type(luau_settings.vectorCtor) == "function", "luau_settings.vectorCtor should be a function")
		assert(type(luau_settings.vectorSize) == "number", "luau_settings.vectorSize should be a number")
		assert(type(luau_settings.useNativeNamecall) == "boolean", "luau_settings.useNativeNamecall should be a boolean")
		assert(type(luau_settings.namecallHandler) == "function", "luau_settings.namecallHandler should be a function")
		assert(type(luau_settings.extensions) == "table", "luau_settings.extensions should be a table of functions")
		assert(type(luau_settings.callHooks) == "table", "luau_settings.callHooks should be a table of functions")
		assert(type(luau_settings.errorHandling) == "boolean", "luau_settings.errorHandling should be a boolean")
		assert(type(luau_settings.generalizedIteration) == "boolean", "luau_settings.generalizedIteration should be a boolean")
		assert(type(luau_settings.allowProxyErrors) == "boolean", "luau_settings.allowProxyErrors should be a boolean")
		assert(type(luau_settings.staticEnvironment) == "table", "luau_settings.staticEnvironment should be a table")
		assert(type(luau_settings.useImportConstants) == "boolean", "luau_settings.useImportConstants should be a boolean")
	end

	local function resolveImportConstant(static, count, k0, k1, k2)
		local res = static[k0]
		if count < 2 or res == nil then
			return res
		end
		res = res[k1]
		if count < 3 or res == nil then
			return res
		end
		res = res[k2]
		return res
	end

	local function luau_deserialize(bytecode, luau_settings)
		if luau_settings == nil then
			luau_settings = luau_newsettings()
		else 
			luau_validatesettings(luau_settings)
		end

		-- local stream = if type(bytecode) == "string" then buffer_fromstring(bytecode) else bytecode
		local stream = bytecode
        local cursor = 0

		local function readByte()
			local byte = buffer_readu8(stream, cursor)
			cursor = cursor + 1
			return byte
		end

		local function readWord()
			local word = buffer_readu32(stream, cursor)
			cursor = cursor + 4
			return word
		end

		local function readFloat()
			local float = buffer_readf32(stream, cursor)
			cursor = cursor + 4
			return float
		end

		local function readDouble()
			local double = buffer_readf64(stream, cursor)
			cursor = cursor + 8
			return double
		end

		local function readVarInt()
			local result = 0

			for i = 0, 4 do
				local value = readByte()
				result = bit32_bor(result, bit32_lshift(bit32_band(value, 0x7F), i * 7))
				if not bit32_btest(value, 0x80) then
					break
				end
			end

			return result
		end

		local function readString()
			local size = readVarInt()

			if size == 0 then
				return ""
			else
				local str = buffer_readstring(stream, cursor, size)
				cursor = cursor + size

				return str
			end
		end

		local luauVersion = readByte()
		local typesVersion = 0
		if luauVersion == 0 then
			warn("Failed to run script [syntax error or bad script] -> ", 0)
		elseif luauVersion < 3 or luauVersion > 6 then
			warn("Script unsupported", 0)
		elseif luauVersion >= 4 then
			typesVersion = readByte()
		end

		local stringCount = readVarInt()
		local stringList = table_create(stringCount)

		for i = 1, stringCount do
			stringList[i] = readString()
        end
        
		local function readInstruction(codeList)
			local value = readWord()
            
			local opcode = bit32_band(value, 0xFF)
			local opinfo = opList[opcode + 1]
			local opname = opinfo[1]
			local opmode = opinfo[2]
			local kmode = opinfo[3]
			local usesAux = opinfo[4]

			local inst = {
				opcode = opcode;
				opname = opname;
				opmode = opmode;
				kmode = kmode;
				usesAux = usesAux;
			}

			table_insert(codeList, inst)

			if opmode == 1 then --[[ A ]]
				inst.A = bit32_band(bit32_rshift(value, 8), 0xFF)
			elseif opmode == 2 then --[[ AB ]]
				inst.A = bit32_band(bit32_rshift(value, 8), 0xFF)
				inst.B = bit32_band(bit32_rshift(value, 16), 0xFF)
			elseif opmode == 3 then --[[ ABC ]]
				inst.A = bit32_band(bit32_rshift(value, 8), 0xFF)
				inst.B = bit32_band(bit32_rshift(value, 16), 0xFF)
				inst.C = bit32_band(bit32_rshift(value, 24), 0xFF)
			elseif opmode == 4 then --[[ AD ]]
				inst.A = bit32_band(bit32_rshift(value, 8), 0xFF)
				local temp = bit32_band(bit32_rshift(value, 16), 0xFFFF)
				inst.D = if temp < 0x8000 then temp else temp - 0x10000
			elseif opmode == 5 then --[[ AE ]]
				local temp = bit32_band(bit32_rshift(value, 8), 0xFFFFFF)
				inst.E = if temp < 0x800000 then temp else temp - 0x1000000
			end

			if usesAux then 
				local aux = readWord()
				inst.aux = aux

				table_insert(codeList, {value = aux, opname = "auxvalue" })
			end

			return usesAux
		end

		local function checkkmode(inst, k)
			local kmode = inst.kmode

			if kmode == 1 then --// AUX
				inst.K = k[inst.aux +  1]
			elseif kmode == 2 then --// C
				inst.K = k[inst.C + 1]
			elseif kmode == 3 then--// D
				inst.K = k[inst.D + 1]
			elseif kmode == 4 then --// AUX import
				local extend = inst.aux
				local count = bit32_rshift(extend, 30)
				local id0 = bit32_band(bit32_rshift(extend, 20), 0x3FF)

				inst.K0 = k[id0 + 1]
				inst.KC = count
				if count == 2 then
					local id1 = bit32_band(bit32_rshift(extend, 10), 0x3FF)

					inst.K1 = k[id1 + 1]
				elseif count == 3 then
					local id1 = bit32_band(bit32_rshift(extend, 10), 0x3FF)
					local id2 = bit32_band(bit32_rshift(extend, 0), 0x3FF)

					inst.K1 = k[id1 + 1]
					inst.K2 = k[id2 + 1]
				end
				if luau_settings.useImportConstants then
					inst.K = resolveImportConstant(
						luau_settings.staticEnvironment,
						count, inst.K0, inst.K1, inst.K2
					)
				end
			elseif kmode == 5 then --// AUX boolean low 1 bit
				inst.K = bit32_extract(inst.aux, 0, 1) == 1
				inst.KN = bit32_extract(inst.aux, 31, 1) == 1
			elseif kmode == 6 then --// AUX number low 24 bits
				inst.K = k[bit32_extract(inst.aux, 0, 24) + 1]
				inst.KN = bit32_extract(inst.aux, 31, 1) == 1
			elseif kmode == 7 then --// B
				inst.K = k[inst.B + 1]
			elseif kmode == 8 then --// AUX number low 16 bits
				inst.K = bit32_band(inst.aux, 0xf)
			end
		end

		local function readProto(bytecodeid)
			local maxstacksize = readByte()
			local numparams = readByte()
			local nups = readByte()
			local isvararg = readByte() ~= 0

			if luauVersion >= 4 then
				readByte() --// flags 
				local typesize = readVarInt();
				cursor = cursor + typesize;
			end

			local sizecode = readVarInt()
			local codelist = table_create(sizecode)

			local skipnext = false 
			for i = 1, sizecode do
				if skipnext then 
					skipnext = false
					continue 
				end

				skipnext = readInstruction(codelist)
			end

			local sizek = readVarInt()
			local klist = table_create(sizek)

			for i = 1, sizek do
				local kt = readByte()
				local k

				if kt == 0 then --// Nil
					k = nil
				elseif kt == 1 then --// Bool
					k = readByte() ~= 0
				elseif kt == 2 then --// Number
					k = readDouble()
				elseif kt == 3 then --// String
					k = stringList[readVarInt()]
				elseif kt == 4 then --// Import
					k = readWord()
				elseif kt == 5 then --// Table
					local dataLength = readVarInt()
					k = table_create(dataLength)

					for i = 1, dataLength do
						k[i] = readVarInt()
					end
				elseif kt == 6 then --// Closure
					k = readVarInt()
				elseif kt == 7 then --// Vector
					local x,y,z,w = readFloat(), readFloat(), readFloat(), readFloat()

					if luau_settings.vectorSize == 4 then
						k = luau_settings.vectorCtor(x, y, z, w)
					else 
						k = luau_settings.vectorCtor(x, y, z)
					end
				end

				klist[i] = k
			end

			-- // 2nd pass to replace constant references in the instruction
			for i = 1, sizecode do
				checkkmode(codelist[i], klist)
			end

			local sizep = readVarInt()
			local protolist = table_create(sizep)

			for i = 1, sizep do
				protolist[i] = readVarInt() + 1
			end

			local linedefined = readVarInt()

			local debugnameindex = readVarInt()
			local debugname 

			if debugnameindex ~= 0 then
				debugname = stringList[debugnameindex]
			else 
				debugname = "(??)"
			end

			-- // lineinfo
			local lineinfoenabled = readByte() ~= 0
			local instructionlineinfo = nil 

			if lineinfoenabled then
				local linegaplog2 = readByte()

				local intervals = bit32_rshift((sizecode - 1), linegaplog2) + 1

				local lineinfo = table_create(sizecode)
				local abslineinfo = table_create(intervals)

				local lastoffset = 0
				for j = 1, sizecode do
					lastoffset += readByte()
					lineinfo[j] = lastoffset
				end

				local lastline = 0
				for j = 1, intervals do
					lastline += readWord()
					abslineinfo[j] = lastline % (2 ^ 32)
				end

				instructionlineinfo = table_create(sizecode)

				for i = 1, sizecode do 
					--// p->abslineinfo[pc >> p->linegaplog2] + p->lineinfo[pc];
					table_insert(instructionlineinfo, abslineinfo[bit32_rshift(i - 1, linegaplog2) + 1] + lineinfo[i])
				end
			end

			-- // debuginfo
			if readByte() ~= 0 then
				local sizel = readVarInt()
				for i = 1, sizel do
					readVarInt()
					readVarInt()
					readVarInt()
					readByte()
				end
				local sizeupvalues = readVarInt()
				for i = 1, sizeupvalues do
					readVarInt()
				end
			end

			return {
				maxstacksize = maxstacksize;
				numparams = numparams;
				nups = nups;
				isvararg = isvararg;
				linedefined = linedefined;
				debugname = debugname;

				sizecode = sizecode;
				code = codelist;

				sizek = sizek;
				k = klist;

				sizep = sizep;
				protos = protolist;

				lineinfoenabled = lineinfoenabled;
				instructionlineinfo = instructionlineinfo;

				bytecodeid = bytecodeid;
			}
		end

		-- userdataRemapping (not used in VM, left unused)
		if typesVersion == 3 then
			local index = readByte()

			while index ~= 0 do
				readVarInt()

				index = readByte()
			end
		end

		local protoCount = readVarInt()
		local protoList = table_create(protoCount)

		for i = 1, protoCount do
			protoList[i] = readProto(i - 1)
		end

		local mainProto = protoList[readVarInt() + 1]

		-- assert(cursor == buffer_len(stream), "deserializer cursor position mismatch")

		mainProto.debugname = "(main)"

		return {
			stringList = stringList;
			protoList = protoList;

			mainProto = mainProto;

			typesVersion = typesVersion;
		}
	end

	local function luau_load(module, env, luau_settings)
		if luau_settings == nil then
			luau_settings = luau_newsettings()
		else 
			luau_validatesettings(luau_settings)
		end

		if type(module) ~= "table" then
			module = luau_deserialize(module, luau_settings)
		end

		local protolist = module.protoList
		local mainProto = module.mainProto

		local breakHook = luau_settings.callHooks.breakHook
		local stepHook = luau_settings.callHooks.stepHook
		local interruptHook = luau_settings.callHooks.interruptHook
		local panicHook = luau_settings.callHooks.panicHook

		local alive = true 

		local function luau_close()
			alive = false
		end

		local function luau_wrapclosure(module, proto, upvals)
			local function luau_execute(...)
				local debugging, stack, protos, code, varargs

				if luau_settings.errorHandling then
					debugging, stack, protos, code, varargs = ... 
				else 
					--// Copied from error handling wrapper
					local passed = table_pack(...)
					stack = table_create(proto.maxstacksize)
					varargs = {
						len = 0,
						list = {},
					}

					table_move(passed, 1, proto.numparams, 0, stack)

					if proto.numparams < passed.n then
						local start = proto.numparams + 1
						local len = passed.n - proto.numparams
						varargs.len = len
						table_move(passed, start, start + len - 1, 1, varargs.list)
					end

					passed = nil

					debugging = {pc = 0, name = "NONE"}

					protos = proto.protos 
					code = proto.code
				end 

				local top, pc, open_upvalues, generalized_iterators = -1, 1, setmetatable({}, {__mode = "vs"}), setmetatable({}, {__mode = "ks"})
				local constants = proto.k
				local extensions = luau_settings.extensions

				while alive do
					local inst = code[pc]
					local op = inst.opcode

					debugging.pc = pc
					debugging.top = top
					debugging.name = inst.opname

					pc += 1

					if stepHook then
						stepHook(stack, debugging, proto, module, upvals)
					end

					if op == 0 then --[[ NOP ]]
						--// Do nothing
					elseif op == 1 then --[[ BREAK ]]
						if breakHook then
							breakHook(stack, debugging, proto, module, upvals)
						else
							warn("Breakpoint encountered without a break hook")
						end
					elseif op == 2 then --[[ LOADNIL ]]
						stack[inst.A] = nil
					elseif op == 3 then --[[ LOADB ]]
						stack[inst.A] = inst.B == 1
						pc += inst.C
					elseif op == 4 then --[[ LOADN ]]
						stack[inst.A] = inst.D
					elseif op == 5 then --[[ LOADK ]]
						stack[inst.A] = inst.K
					elseif op == 6 then --[[ MOVE ]]
						stack[inst.A] = stack[inst.B]
					elseif op == 7 then --[[ GETGLOBAL ]]
						local kv = inst.K

						stack[inst.A] = extensions[kv] or env[kv]

						pc += 1 --// adjust for aux
					elseif op == 8 then --[[ SETGLOBAL ]]
						local kv = inst.K
						env[kv] = stack[inst.A]

						pc += 1 --// adjust for aux
					elseif op == 9 then --[[ GETUPVAL ]]
						local uv = upvals[inst.B + 1]
						stack[inst.A] = uv.store[uv.index]
					elseif op == 10 then --[[ SETUPVAL ]]
						local uv = upvals[inst.B + 1]
						uv.store[uv.index] = stack[inst.A]
					elseif op == 11 then --[[ CLOSEUPVALS ]]
						for i, uv in open_upvalues do
							if uv.index >= inst.A then
								uv.value = uv.store[uv.index]
								uv.store = uv
								uv.index = "value" --// self reference
								open_upvalues[i] = nil
							end
						end
					elseif op == 12 then --[[ GETIMPORT ]]
						if luau_settings.useImportConstants then
							stack[inst.A] = inst.K
						else
							local count = inst.KC
							local k0 = inst.K0
							local import = extensions[k0] or env[k0]
							if count == 1 then
								stack[inst.A] = import
							elseif count == 2 then
								stack[inst.A] = import[inst.K1]
							elseif count == 3 then
								stack[inst.A] = import[inst.K1][inst.K2]
							end
						end

						pc += 1 --// adjust for aux 
					elseif op == 13 then --[[ GETTABLE ]]
						stack[inst.A] = stack[inst.B][stack[inst.C]]
					elseif op == 14 then --[[ SETTABLE ]]
						stack[inst.B][stack[inst.C]] = stack[inst.A]
					elseif op == 15 then --[[ GETTABLEKS ]]
						local index = inst.K
						stack[inst.A] = stack[inst.B][index]

						pc += 1 --// adjust for aux 
					elseif op == 16 then --[[ SETTABLEKS ]]
						local index = inst.K
						stack[inst.B][index] = stack[inst.A]

						pc += 1 --// adjust for aux
					elseif op == 17 then --[[ GETTABLEN ]]
						stack[inst.A] = stack[inst.B][inst.C + 1]
					elseif op == 18 then --[[ SETTABLEN ]]
						stack[inst.B][inst.C + 1] = stack[inst.A]
					elseif op == 19 then --[[ NEWCLOSURE ]]
						local newPrototype = protolist[protos[inst.D + 1]]

						local nups = newPrototype.nups
						local upvalues = table_create(nups)
						stack[inst.A] = luau_wrapclosure(module, newPrototype, upvalues)

						for i = 1, nups do
							local pseudo = code[pc]

							pc += 1

							local type = pseudo.A

							if type == 0 then --// value
								local upvalue = {
									value = stack[pseudo.B],
									index = "value",--// self reference
								}
								upvalue.store = upvalue

								upvalues[i] = upvalue
							elseif type == 1 then --// reference
								local index = pseudo.B
								local prev = open_upvalues[index]

								if prev == nil then
									prev = {
										index = index,
										store = stack,
									}
									open_upvalues[index] = prev
								end

								upvalues[i] = prev
							elseif type == 2 then --// upvalue
								upvalues[i] = upvals[pseudo.B + 1]
							end
						end
					elseif op == 20 then --[[ NAMECALL ]]
						local A = inst.A
						local B = inst.B

						local kv = inst.K

						local sb = stack[B]

						stack[A + 1] = sb

						pc += 1 --// adjust for aux 

						local useFallback = true

						--// Special handling for native namecall behaviour
						local useNativeHandler = luau_settings.useNativeNamecall

						if useNativeHandler then
							local nativeNamecall = luau_settings.namecallHandler

							local callInst = code[pc]
							local callOp = callInst.opcode

							--// Copied from the CALL handler under
							local callA, callB, callC = callInst.A, callInst.B, callInst.C

							if stepHook then
								stepHook(stack, debugging, proto, module, upvals)
							end

							if interruptHook then
								interruptHook(stack, debugging, proto, module, upvals)	
							end

							local params = if callB == 0 then top - callA else callB - 1
							local ret_list = table_pack(
								nativeNamecall(kv, table_unpack(stack, callA + 1, callA + params))
							)

							if ret_list[1] == true then
								useFallback = false

								pc += 1 --// Skip next CALL instruction

								inst = callInst
								op = callOp
								debugging.pc = pc
								debugging.name = inst.opname

								table_remove(ret_list, 1)

								local ret_num = ret_list.n - 1

								if callC == 0 then
									top = callA + ret_num - 1
								else
									ret_num = callC - 1
								end

								table_move(ret_list, 1, ret_num, callA, stack)
							end
						end

						if useFallback then
							stack[A] = sb[kv]
						end
					elseif op == 21 then --[[ CALL ]]
						if interruptHook then
							interruptHook(stack, debugging, proto, module, upvals)	
						end

						local A, B, C = inst.A, inst.B, inst.C

						local params = if B == 0 then top - A else B - 1
						local func = stack[A]
						local ret_list = table_pack(
							func(table_unpack(stack, A + 1, A + params))
						)

						local ret_num = ret_list.n

						if C == 0 then
							top = A + ret_num - 1
						else
							ret_num = C - 1
						end

						table_move(ret_list, 1, ret_num, A, stack)
					elseif op == 22 then --[[ RETURN ]]
						if interruptHook then
							interruptHook(stack, debugging, proto, module, upvals)	
						end

						local A = inst.A
						local B = inst.B 
						local b = B - 1
						local nresults

						if b == LUA_MULTRET then
							nresults = top - A + 1
						else
							nresults = B - 1
						end

						return table_unpack(stack, A, A + nresults - 1)
					elseif op == 23 then --[[ JUMP ]]
						pc += inst.D
					elseif op == 24 then --[[ JUMPBACK ]]
						if interruptHook then
							interruptHook(stack, debugging, proto, module, upvals)	
						end

						pc += inst.D
					elseif op == 25 then --[[ JUMPIF ]]
						if stack[inst.A] then
							pc += inst.D
						end
					elseif op == 26 then --[[ JUMPIFNOT ]]
						if not stack[inst.A] then
							pc += inst.D
						end
					elseif op == 27 then --[[ JUMPIFEQ ]]
						if stack[inst.A] == stack[inst.aux] then
							pc += inst.D
						else
							pc += 1
						end
					elseif op == 28 then --[[ JUMPIFLE ]]
						if stack[inst.A] <= stack[inst.aux] then
							pc += inst.D
						else
							pc += 1
						end
					elseif op == 29 then --[[ JUMPIFLT ]]
						if stack[inst.A] < stack[inst.aux] then
							pc += inst.D
						else
							pc += 1
						end
					elseif op == 30 then --[[ JUMPIFNOTEQ ]]
						if stack[inst.A] == stack[inst.aux] then
							pc += 1
						else
							pc += inst.D
						end
					elseif op == 31 then --[[ JUMPIFNOTLE ]]
						if stack[inst.A] <= stack[inst.aux] then
							pc += 1
						else
							pc += inst.D
						end
					elseif op == 32 then --[[ JUMPIFNOTLT ]]
						if stack[inst.A] < stack[inst.aux] then
							pc += 1
						else
							pc += inst.D
						end
					elseif op == 33 then --[[ ADD ]]
						stack[inst.A] = stack[inst.B] + stack[inst.C]
					elseif op == 34 then --[[ SUB ]]
						stack[inst.A] = stack[inst.B] - stack[inst.C]
					elseif op == 35 then --[[ MUL ]]
						stack[inst.A] = stack[inst.B] * stack[inst.C]
					elseif op == 36 then --[[ DIV ]]
						stack[inst.A] = stack[inst.B] / stack[inst.C]
					elseif op == 37 then --[[ MOD ]]
						stack[inst.A] = stack[inst.B] % stack[inst.C]
					elseif op == 38 then --[[ POW ]]
						stack[inst.A] = stack[inst.B] ^ stack[inst.C]
					elseif op == 39 then --[[ ADDK ]]
						stack[inst.A] = stack[inst.B] + inst.K
					elseif op == 40 then --[[ SUBK ]]
						stack[inst.A] = stack[inst.B] - inst.K
					elseif op == 41 then --[[ MULK ]]
						stack[inst.A] = stack[inst.B] * inst.K
					elseif op == 42 then --[[ DIVK ]]
						stack[inst.A] = stack[inst.B] / inst.K
					elseif op == 43 then --[[ MODK ]]
						stack[inst.A] = stack[inst.B] % inst.K
					elseif op == 44 then --[[ POWK ]]
						stack[inst.A] = stack[inst.B] ^ inst.K
					elseif op == 45 then --[[ AND ]]
						local value = stack[inst.B]
						stack[inst.A] = if value then stack[inst.C] or false else value
					elseif op == 46 then --[[ OR ]]
						local value = stack[inst.B]
						stack[inst.A] = if value then value else stack[inst.C] or false
					elseif op == 47 then --[[ ANDK ]]
						local value = stack[inst.B]
						stack[inst.A] = if value then inst.K or false else value
					elseif op == 48 then --[[ ORK ]]
						local value = stack[inst.B]
						stack[inst.A] = if value then value else inst.K or false
					elseif op == 49 then --[[ CONCAT ]]
						local s = ""
						for i = inst.B, inst.C do
							s ..= stack[i]
						end
						stack[inst.A] = s
					elseif op == 50 then --[[ NOT ]]
						stack[inst.A] = not stack[inst.B]
					elseif op == 51 then --[[ MINUS ]]
						stack[inst.A] = -stack[inst.B]
					elseif op == 52 then --[[ LENGTH ]]
						stack[inst.A] = #stack[inst.B]
					elseif op == 53 then --[[ NEWTABLE ]]
						stack[inst.A] = table_create(inst.aux)

						pc += 1 --// adjust for aux 
					elseif op == 54 then --[[ DUPTABLE ]]
						local template = inst.K
						local serialized = {}
						for _, id in template do
							serialized[constants[id + 1]] = nil
						end
						stack[inst.A] = serialized
					elseif op == 55 then --[[ SETLIST ]]
						local A = inst.A
						local B = inst.B
						local c = inst.C - 1

						if c == LUA_MULTRET then
							c = top - B + 1
						end

						table_move(stack, B, B + c - 1, inst.aux, stack[A])

						pc += 1 --// adjust for aux 
					elseif op == 56 then --[[ FORNPREP ]]
						local A = inst.A

						local limit = stack[A]
						if not ttisnumber(limit) then
							local number = tonumber(limit)

							if number == nil then
								warn("invalid 'for' limit (number expected)")
							end

							stack[A] = number
							limit = number
						end

						local step = stack[A + 1]
						if not ttisnumber(step) then
							local number = tonumber(step)

							if number == nil then
								warn("invalid 'for' step (number expected)")
							end

							stack[A + 1] = number
							step = number
						end

						local index = stack[A + 2]
						if not ttisnumber(index) then
							local number = tonumber(index)

							if number == nil then
								warn("invalid 'for' index (number expected)")
							end

							stack[A + 2] = number
							index = number
						end

						if step > 0 then
							if not (index <= limit) then
								pc += inst.D
							end
						else
							if not (limit <= index) then
								pc += inst.D
							end
						end
					elseif op == 57 then --[[ FORNLOOP ]]
						if interruptHook then
							interruptHook(stack, debugging, proto, module, upvals)	
						end

						local A = inst.A
						local limit = stack[A]
						local step = stack[A + 1]
						local index = stack[A + 2] + step

						stack[A + 2] = index

						if step > 0 then
							if index <= limit then
								pc += inst.D
							end
						else
							if limit <= index then
								pc += inst.D
							end
						end
					elseif op == 58 then --[[ FORGLOOP ]]
						if interruptHook then
							interruptHook(stack, debugging, proto, module, upvals)	
						end

						local A = inst.A
						local res = inst.K

						top = A + 6

						local it = stack[A]

						if (luau_settings.generalizedIteration == false) or ttisfunction(it) then 
							local vals = { it(stack[A + 1], stack[A + 2]) }
							table_move(vals, 1, res, A + 3, stack)

							if stack[A + 3] ~= nil then
								stack[A + 2] = stack[A + 3]
								pc += inst.D
							else
								pc += 1
							end
						else
							local ok, vals = coroutine_resume(generalized_iterators[inst], it, stack[A + 1], stack[A + 2])
							if not ok then
								warn(vals)
							end
							if vals == LUA_GENERALIZED_TERMINATOR then 
								generalized_iterators[inst] = nil
								pc += 1
							else
								table_move(vals, 1, res, A + 3, stack)

								stack[A + 2] = stack[A + 3]
								pc += inst.D
							end
						end
					elseif op == 59 then --[[ FORGPREP_INEXT ]]
						if not ttisfunction(stack[inst.A]) then
							warn(string_format("attempt to iterate over a %s value", type(stack[inst.A]))) -- FORGPREP_INEXT encountered non-function value
						end

						pc += inst.D
					elseif op == 60 then --[[ FASTCALL3 ]]
						--[[ Skipped ]]
						pc += 1 --// adjust for aux
					elseif op == 61 then --[[ FORGPREP_NEXT ]]
						if not ttisfunction(stack[inst.A]) then
							warn(string_format("attempt to iterate over a %s value", type(stack[inst.A]))) -- FORGPREP_NEXT encountered non-function value
						end

						pc += inst.D
					elseif op == 63 then --[[ GETVARARGS ]]
						local A = inst.A
						local b = inst.B - 1

						if b == LUA_MULTRET then
							b = varargs.len
							top = A + b - 1
						end

						table_move(varargs.list, 1, b, A, stack)
					elseif op == 64 then --[[ DUPCLOSURE ]]
						local newPrototype = protolist[inst.K + 1] --// correct behavior would be to reuse the prototype if possible but it would not be useful here

						local nups = newPrototype.nups
						local upvalues = table_create(nups)
						stack[inst.A] = luau_wrapclosure(module, newPrototype, upvalues)

						for i = 1, nups do
							local pseudo = code[pc]
							pc += 1

							local type = pseudo.A
							if type == 0 then --// value
								local upvalue = {
									value = stack[pseudo.B],
									index = "value",--// self reference
								}
								upvalue.store = upvalue

								upvalues[i] = upvalue

								--// references dont get handled by DUPCLOSURE
							elseif type == 2 then --// upvalue
								upvalues[i] = upvals[pseudo.B + 1]
							end
						end
					elseif op == 65 then --[[ PREPVARARGS ]]
						--[[ Handled by wrapper ]]
					elseif op == 66 then --[[ LOADKX ]]
						local kv = inst.K
						stack[inst.A] = kv

						pc += 1 --// adjust for aux 
					elseif op == 67 then --[[ JUMPX ]]
						if interruptHook then
							interruptHook(stack, debugging, proto, module, upvals)	
						end

						pc += inst.E
					elseif op == 68 then --[[ FASTCALL ]]
						--[[ Skipped ]]
					elseif op == 69 then --[[ COVERAGE ]]
						inst.E += 1
					elseif op == 70 then --[[ CAPTURE ]]
						--[[ Handled by CLOSURE ]]
						warn("encountered unhandled CAPTURE")
					elseif op == 71 then --[[ SUBRK ]]
						stack[inst.A] = inst.K - stack[inst.C]
					elseif op == 72 then --[[ DIVRK ]]
						stack[inst.A] = inst.K / stack[inst.C]
					elseif op == 73 then --[[ FASTCALL1 ]]
						--[[ Skipped ]]
					elseif op == 74 then --[[ FASTCALL2 ]]
						--[[ Skipped ]]
						pc += 1 --// adjust for aux
					elseif op == 75 then --[[ FASTCALL2K ]]
						--[[ Skipped ]]
						pc += 1 --// adjust for aux
					elseif op == 76 then --[[ FORGPREP ]]
						local iterator = stack[inst.A]

						if luau_settings.generalizedIteration and not ttisfunction(iterator) then
							local loopInstruction = code[pc + inst.D]
							if generalized_iterators[loopInstruction] == nil then 
								local function gen_iterator(...)
									for r1, r2, r3, r4, r5, r6, r7, r8, r9, r10, r11, r12, r13, r14, r15, r16, r17, r18, r19, r20, r21, r22, r23, r24, r25, r26, r27, r28, r29, r30, r31, r32, r33, r34, r35, r36, r37, r38, r39, r40, r41, r42, r43, r44, r45, r46, r47, r48, r49, r50, r51, r52, r53, r54, r55, r56, r57, r58, r59, r60, r61, r62, r63, r64, r65, r66, r67, r68, r69, r70, r71, r72, r73, r74, r75, r76, r77, r78, r79, r80, r81, r82, r83, r84, r85, r86, r87, r88, r89, r90, r91, r92, r93, r94, r95, r96, r97, r98, r99, r100, r101, r102, r103, r104, r105, r106, r107, r108, r109, r110, r111, r112, r113, r114, r115, r116, r117, r118, r119, r120, r121, r122, r123, r124, r125, r126, r127, r128, r129, r130, r131, r132, r133, r134, r135, r136, r137, r138, r139, r140, r141, r142, r143, r144, r145, r146, r147, r148, r149, r150, r151, r152, r153, r154, r155, r156, r157, r158, r159, r160, r161, r162, r163, r164, r165, r166, r167, r168, r169, r170, r171, r172, r173, r174, r175, r176, r177, r178, r179, r180, r181, r182, r183, r184, r185, r186, r187, r188, r189, r190, r191, r192, r193, r194, r195, r196, r197, r198, r199, r200 in ... do 
										coroutine_yield({r1, r2, r3, r4, r5, r6, r7, r8, r9, r10, r11, r12, r13, r14, r15, r16, r17, r18, r19, r20, r21, r22, r23, r24, r25, r26, r27, r28, r29, r30, r31, r32, r33, r34, r35, r36, r37, r38, r39, r40, r41, r42, r43, r44, r45, r46, r47, r48, r49, r50, r51, r52, r53, r54, r55, r56, r57, r58, r59, r60, r61, r62, r63, r64, r65, r66, r67, r68, r69, r70, r71, r72, r73, r74, r75, r76, r77, r78, r79, r80, r81, r82, r83, r84, r85, r86, r87, r88, r89, r90, r91, r92, r93, r94, r95, r96, r97, r98, r99, r100, r101, r102, r103, r104, r105, r106, r107, r108, r109, r110, r111, r112, r113, r114, r115, r116, r117, r118, r119, r120, r121, r122, r123, r124, r125, r126, r127, r128, r129, r130, r131, r132, r133, r134, r135, r136, r137, r138, r139, r140, r141, r142, r143, r144, r145, r146, r147, r148, r149, r150, r151, r152, r153, r154, r155, r156, r157, r158, r159, r160, r161, r162, r163, r164, r165, r166, r167, r168, r169, r170, r171, r172, r173, r174, r175, r176, r177, r178, r179, r180, r181, r182, r183, r184, r185, r186, r187, r188, r189, r190, r191, r192, r193, r194, r195, r196, r197, r198, r199, r200})
									end

									coroutine_yield(LUA_GENERALIZED_TERMINATOR)
								end

								generalized_iterators[loopInstruction] = coroutine_create(gen_iterator)
							end
						end

						pc += inst.D
					elseif op == 77 then --[[ JUMPXEQKNIL ]]
						local kn = inst.KN

						if (stack[inst.A] == nil) ~= kn then
							pc += inst.D
						else
							pc += 1
						end
					elseif op == 78 then --[[ JUMPXEQKB ]]
						local kv = inst.K
						local kn = inst.KN
						local ra = stack[inst.A]

						if (ttisboolean(ra) and (ra == kv)) ~= kn then
							pc += inst.D
						else
							pc += 1
						end
					elseif op == 79 then --[[ JUMPXEQKN ]]
						local kv = inst.K
						local kn = inst.KN
						local ra = stack[inst.A]

						if (ra == kv) ~= kn then
							pc += inst.D
						else
							pc += 1
						end
					elseif op == 80 then --[[ JUMPXEQKS ]]
						local kv = inst.K
						local kn = inst.KN
						local ra = stack[inst.A]

						if (ra == kv) ~= kn then
							pc += inst.D
						else
							pc += 1
						end
					elseif op == 81 then --[[ IDIV ]]
						stack[inst.A] = stack[inst.B] // stack[inst.C]
					elseif op == 82 then --[[ IDIVK ]]
						stack[inst.A] = stack[inst.B] // inst.K
					else
						warn("Unsupported Opcode: " .. inst.opname .. " op: " .. op)
					end
				end

				for i, uv in open_upvalues do
					uv.value = uv.store[uv.index]
					uv.store = uv
					uv.index = "value" --// self reference
					open_upvalues[i] = nil
				end

				for i, iter in generalized_iterators do 
					coroutine_close(iter)
					generalized_iterators[i] = nil
				end
			end

			local function wrapped(...)
				local passed = table_pack(...)
				local stack = table_create(proto.maxstacksize)
				local varargs = {
					len = 0,
					list = {},
				}

				table_move(passed, 1, proto.numparams, 0, stack)

				if proto.numparams < passed.n then
					local start = proto.numparams + 1
					local len = passed.n - proto.numparams
					varargs.len = len
					table_move(passed, start, start + len - 1, 1, varargs.list)
				end

				passed = nil

				local debugging = {pc = 0, name = "NONE"}
				local result
				if luau_settings.errorHandling then 
					result = table_pack(pcall(luau_execute, debugging, stack, proto.protos, proto.code, varargs))
				else
					result = table_pack(true, luau_execute(debugging, stack, proto.protos, proto.code, varargs))
				end

				if result[1] then
					return table_unpack(result, 2, result.n)
				else
					local message = result[2]

					if panicHook then
						panicHook(message, stack, debugging, proto, module, upvals)
					end

					if ttisstring(message) == false then
						if luau_settings.allowProxyErrors then
							warn(message)
						else 
							message = type(message)
						end
					end

					if proto.lineinfoenabled then
					else 
						return warn(string_format("nexar>lvm error [name>%s>opcode %s]>%s", proto.debugname, debugging.pc, debugging.name, message), 0)
					end
				end
			end

			if luau_settings.errorHandling then 
				return wrapped
			else 
				return luau_execute
			end 
		end

		return luau_wrapclosure(module, mainProto),  luau_close
	end

	return function(bytecode, env)
		local executable = luau_load(bytecode, env)
		return setfenv(executable, env)
	end
end)()

local function convertToBytes(str)
    local cleaned_str = str:gsub('^|', ''):gsub('|$', '')
    local byte_strings = {}
    for byte in cleaned_str:gmatch('[^|]+') do
        table.insert(byte_strings, byte)
    end
    local byte_array = {}
    for _, byte_str in ipairs(byte_strings) do
        local byte = tonumber(byte_str)
        if byte then
            table.insert(byte_array, byte)
        end
    end
    return byte_array
end

local function parse(booleanstr)
	local a = false
	if tostring(booleanstr) == "true" then
		a = true
	end
	return a
end

local function randomstr(length)
    local characters = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"
    local result = ""
    for i = 1, length do
        local randomIndex = math.random(1, #characters)
        result = result .. string.sub(characters, randomIndex, randomIndex)
    end
    return result
end

local function create_environment()
	local genv = table.create(0)
	local renv = table.create(0)
	local defenv = {"DockWidgetPluginGuiInfo","warn","tostring","gcinfo","os","tick","task","getfenv","pairs","NumberSequence","assert","rawlen","tonumber","CatalogSearchParams","Enum","Delay","OverlapParams","Stats","_G","UserSettings","coroutine","NumberRange","buffer","shared","NumberSequenceKeypoint","PhysicalProperties","PluginManager","Vector2int16","UDim2","loadstring","printidentity","Version","Vector2","UDim","Game","delay","spawn","Ray","string","xpcall","SharedTable","RotationCurveKey","DateTime","print","ColorSequence","debug","RaycastParams","Workspace","unpack","TweenInfo","Random","require","Vector3","bit32","Vector3int16","setmetatable","next","Instance","Font","FloatCurveKey","ipairs","plugin","Faces","rawequal","Region3int16","collectgarbage","game","getmetatable","Spawn","ColorSequenceKeypoint","Region3","utf8","Color3","CFrame","rawset","PathWaypoint","typeof","workspace","ypcall","settings","Wait","math","version","pcall","stats","elapsedTime","type","wait","ElapsedTime","select","time","DebuggerManager","rawget","table","Rect","BrickColor","setfenv","_VERSION","Axes","error","newproxy",}
	
	for i, v in pairs(defenv) do
		renv[v] = getfenv()[v]
	end
	
	setmetatable(genv, {})
	local gmeta = getmetatable(genv)
	gmeta.__index = function(_, i)
		return renv[i]
	end
	gmeta.__len = function(_)
		return rawlen(genv)
	end
	rawset(genv, "getgenv", function()
		return genv
	end)
	rawset(genv, "getrenv", function()
		return renv
	end)

	renv.hui_created = false
	genv.hui_created = renv.hui_created
	return renv, genv
end

local function _request(args)
	local Body = nil
	local Timeout = 0
	local function callback(success, body)
		Body = body
		Body['Success'] = success
	end
	game:GetService("HttpService"):RequestInternal(args):Start(callback)
	while not Body and Timeout < 10 do
		task.wait(.00000001)
		Timeout = Timeout + .1
	end
	return Body
end

local function execute(bytecode, env)
	local toret = RunBytecode(bytecode, env)
	local cl = toret
	if type(toret) ~= "function" then
		toret = function(...)
			warn(cl,2)
		end
	end
	return function()
		local success, errorMessage = pcall(toret)
		if errorMessage ~= nil then
			-- would be mad sick to make this red, but it doesn't really matter
			print(errorMessage)
		end
	end
end

local function new_hui()
	local hui = Instance.new("ScreenGui")
	hui.Name = randomstr(20)
	hui.Parent = game:GetService("CoreGui")
	return hui
end

local function register_functions(environment, isrenv)
	if (environment.hui_created == false) then
		environment.hui = new_hui() -- # create a new hidden ui environment
		environment.hui_created = true
	end

	environment.new_hui = new_hui
	-- // HTTP // --
	environment.request = _request
	environment.HttpGet = function(url: string)
		--if (type(url))
		return environment.request({
			Method = "GET",
			Url = tostring(url),
		}).Body
	end
	environment.http = {}
	environment.http.request = environment.request
	environment.http_request = environment.request

	-- // FILE SYSTEM // --
	environment.split = function(input, delimiter)
		local result = {}
		for match in (input..delimiter):gmatch("(.-)"..delimiter) do
			table.insert(result, match)
		end
		return result
	end

	environment.readfile = function(fname)
		local HttpService = game:GetService("HttpService")
		local p = ""
		pcall(function() p = _request({ Url = "http://localhost:7331/file-read", Method = "POST", Body = HttpService:JSONEncode({filename = tostring(fname)})}).Body end)
		return p
	end

	environment.writefile = function(fname, fcontent)
		local HttpService = game:GetService("HttpService")
		local p = false
		pcall(function() p = parse(_request({ Url = "http://localhost:7331/file-write", Method = "POST", Body = HttpService:JSONEncode({filename = tostring(fname), content = tostring(fcontent)})}).Body) end)
		return p
	end

	environment.listfiles = function()
		local unparsed_list = ""
		pcall(function() unparsed_list = _request({ Url = "http://localhost:7331/file-list", Method = "POST", Body = ""}).Body end)

		local parsed_list = environment.split(unparsed_list, "\n")
		return parsed_list
	end

	environment.makefolder = function(foldern)
		local HttpService = game:GetService("HttpService")
		local status = false
		pcall(function() status = parse(_request({ Url = "http://localhost:7331/file-mfolder", Method = "POST", Body = HttpService:JSONEncode({foldername = tostring(foldern)})}).Body) end)
		return status
	end

	environment.appendfile = function(fname, fcontent)
		local HttpService = game:GetService("HttpService")
		local p = false
		pcall(function() p = parse(_request({ Url = "http://localhost:7331/file-append", Method = "POST", Body = HttpService:JSONEncode({filename = tostring(fname), content = tostring(fcontent)})}).Body) end)
		return p
	end

	environment.isfile = function(finame)
		local HttpService = game:GetService("HttpService")
		local p = false
		pcall(function() p = parse(_request({ Url = "http://localhost:7331/file-isfile", Method = "POST", Body = HttpService:JSONEncode({filename = tostring(finame)})}).Body) end)
		return p
	end

	environment.isfolder = function(foname)
		local HttpService = game:GetService("HttpService")
		local p = false
		pcall(function() p = parse(_request({ Url = "http://localhost:7331/file-isfolder", Method = "POST", Body = HttpService:JSONEncode({foldername = tostring(foname)})}).Body) end)
		return p
	end

	environment.delfolder = function(foname)
		local HttpService = game:GetService("HttpService")
		local p = false
		pcall(function() p = parse(_request({ Url = "http://localhost:7331/file-delfolder", Method = "POST", Body = HttpService:JSONEncode({foldername = tostring(foname)})}).Body) end)
		return p
	end

	environment.delfile = function(finame)
		local HttpService = game:GetService("HttpService")
		local p = false
		pcall(function() p = parse(_request({ Url = "http://localhost:7331/file-delfile", Method = "POST", Body = HttpService:JSONEncode({filename = tostring(finame)})}).Body) end)
		return p
	end

	environment.loadfile = function(finame)
		local content = environment.readfile(finame)
		return function(...)
			environment.loadstring(content)()
		end
	end

	-- // CLONE/CLOSURE // --
	environment.clonedrefs = {}
	environment.cloneref = function(ref)
		assert(ref, "Missing #1 argument")
		assert(typeof(ref) == "Instance", "Expected #1 argument to be Instance, got "..tostring(typeof(ref)).." instead")
		if game:FindFirstChild(ref.Name)  or ref.Parent == game then 
			return ref
		else
			local class = ref.ClassName
			local cloned = Instance.new(class)
			local mt = {
				__index = ref,
				__newindex = function(t, k, v)

					if k == "Name" then
						ref.Name = v
					end
					rawset(t, k, v)
				end
			}
			local proxy = setmetatable({}, mt)
			environment.clonedrefs.insert(proxy)
			return proxy
		end
	end
	environment.checkcaller = function()
		local info = debug.info(environment, 'slnaf')
		return debug.info(1, 'slnaf')==info
	end
	environment.clonefunction = function(_function)
		return function(...) return _function(...) end
	end
	environment.getscriptclosure = function(script)
		return function()
			return table.clone(require(script))
		end
	end

	environment.getscriptfunction = environment.getscriptclosure

	environment.iscclosure = function(func)
		return debug.info(func, "s") == "[C]"
	end

	environment.islclosure = function(func)
		return debug.info(func, "s") ~= "[C]"
	end

	-- // METATABLE // --
	environment.getrawmetatable = function(object)
		if type(object) ~= "table" and type(object) ~= "userdata" then
			warn("expected tbl or userdata", 2)
			return {}
		end
		local raw_mt = debug.getmetatable(object)
		if raw_mt and raw_mt.__metatable then
			raw_mt.__metatable = nil 
			local result_mt = debug.getmetatable(object)
			raw_mt.__metatable = "Locked!" 
			return result_mt
		end	
		return raw_mt
	end

	environment.setrawmetatable = function(object, newmetatbl)
		if type(object) ~= "table" and type(object) ~= "userdata" then
			warn("expected table or userdata", 2)
			return false
		end
		if type(newmetatbl) ~= "table" and newmetatbl ~= nil then
			warn("new metatable must be a table or nil", 2)
			return false
		end
		local raw_mt = debug.getmetatable(object)
			if raw_mt and raw_mt.__metatable then
			local old_metatable = raw_mt.__metatable
			raw_mt.__metatable = nil  
					local success, err = pcall(setmetatable, object, newmetatbl)
					raw_mt.__metatable = old_metatable
					if not success then
				warn("failed to set metatable : " .. tostring(err), 2)
				return false
			end
			return true  
		end
			setmetatable(object, newmetatbl)
		return true
	end

	-- // DEBUG // --
	environment.debug = {}
	environment.debug.getinfo = function(f, options)
		if type(options) == "string" then
			options = string.lower(options) 
		else
			options = "sflnu"
		end
		local result = {}
		for index = 1, #options do
			local option = string.sub(options, index, index)
			if "s" == option then
				local short_src = debug.info(f, "s")
				result.short_src = short_src
				result.source = "=" .. short_src
				result.what = if short_src == "[C]" then "C" else "Lua"
			elseif "f" == option then
				result.func = debug.info(f, "f")
			elseif "l" == option then
				result.currentline = debug.info(f, "l")
			elseif "n" == option then
				result.name = debug.info(f, "n")
			elseif "u" == option or option == "a" then
				local numparams, is_vararg = debug.info(f, "a")
				result.numparams = numparams
				result.is_vararg = if is_vararg then 1 else 0
				if "u" == option then
					result.nups = -1
				end
			end
		end
		return result
	end
	environment.debug.getconstant = function(f, i)
		local c = debug.getconstants(f)
		return c[i]
	end
	environment.debug.getconstants = function(f)
		local c = {}
		local i = 1
		while true do
			local k = environment.debug.getconstant(f, i)
			if not k then break end
			c[i] = k
			i = i + 1
		end
		return c
	end
	environment.debug.getstack = function(l, i)
		local s = {}
		local j = 1
		while true do
			local n, v = debug.getlocal(l + 1, j)
			if not n then break end
			s[j] = v
			j = j + 1
		end
		return i and s[i] or s
	end
	
	environment.debug.getupvalue = function(f, i)
		local _, v = debug.getupvalue(f, i)
		return v
	end
	
	environment.debug.getupvalues = function(f)
		local u = {}
		local i = 1
		while true do
			local _, v = environment.debug.getupvalue(f, i)
			if not _ then break end
			u[i] = v
			i = i + 1
		end
		return u
	end
	
	environment.debug.getproto = function(f, index)
		local function find_prototype(func, idx)
			local count = 1
			local i = 1
			while true do
				local name, upvalue = environment.debug.getupvalue(func, i)
				if not name then break end
				if type(upvalue) == "function" then
					if count == idx then
						return upvalue
					end
					count = count + 1
				end
				i = i + 1
			end
			return nil
		end
		
		return find_prototype(f, index)
	end
	
	environment.debug.getprotos = function(f)
		local protos = {}
		local i = 1
			local function get_prototypes(func)
			local index = 1
			while true do
				local name, func = environment.debug.getupvalue(func, index)
				if not name then break end
				if type(func) == "function" then
					table.insert(protos, func)
					get_prototypes(func)
				end
				index = index + 1
			end
		end
		get_prototypes(f)
		
		return protos
	end
	
	environment.debug.getmetatable = function(tableorud)
		local result = getmetatable(tableorud)
	
		if result == nil then -- No meta
			return
		end
	
		if type(result) == "table" and pcall(setmetatable, tableorud, result) then -- This checks if it's real without overwriting
			return result --* We dont cache this as it will be the same always anyways
		end
		-- Metamethod bruteforcing
		-- For Full (except __gc & __tostring) Metamethod list Refer to - https://github.com/luau-lang/luau/blob/master/VM/src/ltm.cpp#L34
	
		-- Todo: Look into more ways of making metamethods error (like https://github.com/luau-lang/luau/blob/master/VM%2Fsrc%2Flvmutils.cpp#L174)
	
		--TODO We can also rebuild many non-dynamic things like len or arithmetic  metamethods since we know what arguments to expect in those usually
	
		local real_metamethods = {}
	
		xpcall(function()
			return tableorud._
		end, function()
			real_metamethods.__index = debug.info(2, "f")
		end)
	
		xpcall(function()
			tableorud._ = tableorud
		end, function()
			real_metamethods.__newindex = debug.info(2, "f")
		end)
	
		-- xpcall(function()
		-- -- !MAKE __mode ERROR SOMEHOW..
		-- end, function()
		-- 	newTable.__mode = debug.info(2, "f")
		-- end)
	
		xpcall(function()
			return tableorud:___() -- Make sure this doesn't exist in the tableorud
		end, function()
			real_metamethods.__namecall = debug.info(2, "f")
		end)
	
		xpcall(function()
			tableorud() -- ! This might not error on tables with __call defined
		end, function()
			real_metamethods.__call = debug.info(2, "f")
		end)
	
		xpcall(function() -- * LUAU
			for _ in tableorud do -- ! This will never error on tables
			end
		end, function()
			real_metamethods.__iter = debug.info(2, "f")
		end)
	
		xpcall(function()
			return #tableorud -- ! This will never error on tables, with userdata the issue is same as __concat - is it even a defined metamethod in that case?
		end, function()
			real_metamethods.__len = debug.info(2, "f")
		end)
	
		-- * Make sure type_check_semibypass lacks any metamethods
		local type_check_semibypass = {} -- bypass typechecks (which will return error instead of actual metamethod)
	
		xpcall(function()
			return tableorud == type_check_semibypass -- ! This will never error (it calls __eq but we need it to error); ~= can also be used
		end, function()
			real_metamethods.__eq = debug.info(2, "f")
		end)
	
		xpcall(function()
			return tableorud + type_check_semibypass
		end, function()
			real_metamethods.__add = debug.info(2, "f")
		end)
	
		xpcall(function()
			return tableorud - type_check_semibypass
		end, function()
			real_metamethods.__sub = debug.info(2, "f")
		end)
	
		xpcall(function()
			return tableorud * type_check_semibypass
		end, function()
			real_metamethods.__mul = debug.info(2, "f")
		end)
	
		xpcall(function()
			return tableorud / type_check_semibypass
		end, function()
			real_metamethods.__div = debug.info(2, "f")
		end)
	
		xpcall(function() -- * LUAU
			return tableorud // type_check_semibypass
		end, function()
			real_metamethods.__idiv = debug.info(2, "f")
		end)
	
		xpcall(function()
			return tableorud % type_check_semibypass
		end, function()
			real_metamethods.__mod = debug.info(2, "f")
		end)
	
		xpcall(function()
			return tableorud ^ type_check_semibypass
		end, function()
			real_metamethods.__pow = debug.info(2, "f")
		end)
	
		xpcall(function()
			return -tableorud
		end, function()
			real_metamethods.__unm = debug.info(2, "f")
		end)
	
		xpcall(function()
			return tableorud < type_check_semibypass
		end, function()
			real_metamethods.__lt = debug.info(2, "f")
		end)
	
		xpcall(function()
			return tableorud <= type_check_semibypass
		end, function()
			real_metamethods.__le = debug.info(2, "f")
		end)
	
		xpcall(function()
			return tableorud .. type_check_semibypass -- TODO Not sure if this would work on userdata.. (do they even have __concat defined? would it be called?)
		end, function()
			real_metamethods.__concat = debug.info(2, "f")
		end)
	
		-- xpcall(function()
		-- -- !MAKE __type ERROR SOMEHOW..
		-- end, function()
		-- 	newTable.__type = debug.info(2, "f")
		-- end)
		-- FAKE __type INBOUND
		real_metamethods.__type = typeof(tableorud)
	
		real_metamethods.__metatable = getmetatable(game) -- "The metatable is locked"
	
		-- xpcall(function()
		-- -- !MAKE __tostring  ERROR SOMEHOW..
		-- end, function()
		-- 	newTable.__tostring = debug.info(2, "f")
		-- end)
	
		-- FAKE __tostring INBOUND (We wrap it because 1. No rawtostring & 2. In case tableorud Name changes)
		real_metamethods.__tostring = function()
			return tostring(tableorud)
		end
	
		-- xpcall(function()
		-- -- !MAKE __gc ERROR SOMEHOW..
		-- end, function()
		-- 	newTable.__gc = debug.info(2, "f")
		-- end)
	
		-- table.freeze(real_metamethods) -- Not using for compatibility -- We can't check readonly state of an actual metatable sadly (or can we?)
		return real_metamethods
	end
	
	environment.debug.setconstant = function(f, i, v)
		local c = debug.getconstants(f)
		local tmp = function() return v end
		local nf = string.dump(tmp)
		debug.setupvalue(nf, 1, v)
		for j = 1, #c do
			if j == i then
				debug.setupvalue(f, j, v)
			else
				debug.setupvalue(f, j, c[j])
			end
		end
	end
	
	environment.debug.setstack=function(l, i, v)
		local n = debug.getlocal(l + 1, i)
		if n then
			debug.setlocal(l + 1, i, v)
		end
	end
	
	environment.debug.setupvalue=function(f, i, v)
		local nf = string.dump(f)
		local j = 1
		while true do
			local n = debug.getupvalue(nf, j)
			if not n then break end
			if j == i then
				debug.setupvalue(nf, j, v)
			else
				debug.setupvalue(nf, j, debug.getupvalue(f, j))
			end
			j = j + 1
		end
		return nf
	end
	
	environment.debug.setmetatable = function(tableorud, newmt)
		assert(type(tableorud) == "table" or type(tableorud) == "userdata", "First argument must be a table or userdata")
		assert(type(newmt) == "table" or newmt == nil, "Second argument must be a table or nil")
		local current_metatable = debug.getmetatable(tableorud)
			if current_metatable and current_metatable.__metatable then
			warn("Metatable is locked and cannot be changed.")
			return {}
		end
		local success, result = pcall(setmetatable, tableorud, newmt)
			if not success then
			warn("Failed to set metatable: " .. tostring(result))
			return {}
		end
		return newmt
	end

	-- // INSTANCE // --
	environment.getinstances = function()
		return game:GetDescendants()
	end
	environment.compareinstances = function(a1,a2)
		if not environment.clonerefs[a1] then
			return a1 == a2
		else
			if table.find(environment.clonerefs[a1], a2) then return true end
		end
		return false
	end
	
	environment.getnilinstances = function()
		local datamodel={game}game.DescendantRemoving:Connect(function(a)environment.cache[a]='REMOVE'end)game.DescendantAdded:Connect(function(a)environment.cache[a]=true;table.insert(datamodel,a)end)for b,c in pairs(game:GetDescendants())do table.insert(datamodel,c)end
		local nilinstances = {}
		for _,v in pairs(datamodel) do
			if v.Parent ~= nil then continue end
			table.insert(nilinstances, v)
		end
		return nilinstances
	end

	-- // CACHE // --
	environment.cache = {}
	environment.cache.cached = {}
	environment.cache.iscached = function(t) return environment.cache.cached[t] ~= 'r' or (not t:IsDescendantOf(game)) end
	environment.cache.invalidate = function(t)
		environment.cache.cached[t] = 'r'
		t.Parent = nil
	end
	environment.cache.replace = function(x, y)
		if environment.cache.cached[x] then
			environment.cache.cached[x] = y
		end
		y.Parent = x.Parent
		y.Name = x.Name
		x.Parent = nil
	end

	-- // sUNC // --
	environment.getscriptbytecode = function(a) return nil end

	-- // MISC // --
	local connection = nil
	local TARGET_FRAME_RATE = 0
	local frameStart = os.clock()

	environment.getexecutorname = function() return "Nexar v1.0.0" end
	environment.identifyexecutor = environment.getexecutorname
	environment.getthreadcontext = function() return 3 end
	environment.getthreadidentity = environment.getthreadcontext
	environment.dumpstring = function(str) return str end
	environment.gethui = function() return environment.hui end
	environment.setfpscap = function(fps)
		local TARGET_FRAME_RATE = fps
		if connection then
			connection:Disconnect()
		end
	
		if TARGET_FRAME_RATE > 0 then
			connection = game:GetService("RunService").PreSimulation:Connect(function()
				while os.clock() - frameStart < 1 / TARGET_FRAME_RATE do
				end
				frameStart = os.clock()
			end)
		end
	end

	-- // DRAWING // --
	environment.Drawing = {}
	environment.drawingUI = environment.new_hui()
	environment.drawingUI.Name = "Drawing"

	environment.drawingUI.IgnoreGuiInset = true
	environment.drawingUI.DisplayOrder = 0x7fffffff
	local drawingIndex = 0
	local uiStrokes = table.create(0)
	local baseDrawingObj = setmetatable({
		Visible = true,
		ZIndex = 0,
		Transparency = 1,
		Color = Color3.new(),
		Remove = function(self)
			setmetatable(self, nil)
		end
	}, {
		__add = function(t1, t2)
			local result = table.clone(t1)

			for index, value in t2 do
				result[index] = value
			end
			return result
		end
	})
	local drawingFontsEnum = {
		[0] = Font.fromEnum(Enum.Font.Roboto),
		[1] = Font.fromEnum(Enum.Font.Legacy),
		[2] = Font.fromEnum(Enum.Font.SourceSans),
		[3] = Font.fromEnum(Enum.Font.RobotoMono),
	}
	-- function
	local function getFontFromIndex(fontIndex: number): Font
		return drawingFontsEnum[fontIndex]
	end

	local function convertTransparency(transparency: number): number
		return math.clamp(1 - transparency, 0, 1)
	end

	environment.Drawing.Fonts =  {
		["UI"] = 0,
		["System"] = 1,
		["Plex"] = 2,
		["Monospace"] = 3
	}

	local drawings = {}
	environment.Drawing.new = function(drawingType)
		drawingIndex += 1
		if drawingType == "Line" then
			local lineObj = ({
				From = Vector2.zero,
				To = Vector2.zero,
				Thickness = 1
			} + baseDrawingObj)

			local lineFrame = Instance.new("Frame")
			lineFrame.Name = drawingIndex
			lineFrame.AnchorPoint = (Vector2.one * .5)
			lineFrame.BorderSizePixel = 0

			lineFrame.BackgroundColor3 = lineObj.Color
			lineFrame.Visible = lineObj.Visible
			lineFrame.ZIndex = lineObj.ZIndex
			lineFrame.BackgroundTransparency = convertTransparency(lineObj.Transparency)

			lineFrame.Size = UDim2.new()

			lineFrame.Parent = environment.drawingUI
			local bs = table.create(0)
			table.insert(drawings,bs)
			return setmetatable(bs, {
				__newindex = function(_, index, value)
					if typeof(lineObj[index]) == "nil" then return end

					if index == "From" then
						local direction = (lineObj.To - value)
						local center = (lineObj.To + value) / 2
						local distance = direction.Magnitude
						local theta = math.deg(math.atan2(direction.Y, direction.X))

						lineFrame.Position = UDim2.fromOffset(center.X, center.Y)
						lineFrame.Rotation = theta
						lineFrame.Size = UDim2.fromOffset(distance, lineObj.Thickness)
					elseif index == "To" then
						local direction = (value - lineObj.From)
						local center = (value + lineObj.From) / 2
						local distance = direction.Magnitude
						local theta = math.deg(math.atan2(direction.Y, direction.X))

						lineFrame.Position = UDim2.fromOffset(center.X, center.Y)
						lineFrame.Rotation = theta
						lineFrame.Size = UDim2.fromOffset(distance, lineObj.Thickness)
					elseif index == "Thickness" then
						local distance = (lineObj.To - lineObj.From).Magnitude

						lineFrame.Size = UDim2.fromOffset(distance, value)
					elseif index == "Visible" then
						lineFrame.Visible = value
					elseif index == "ZIndex" then
						lineFrame.ZIndex = value
					elseif index == "Transparency" then
						lineFrame.BackgroundTransparency = convertTransparency(value)
					elseif index == "Color" then
						lineFrame.BackgroundColor3 = value
					end
					lineObj[index] = value
				end,
				__index = function(self, index)
					if index == "Remove" or index == "Destroy" then
						return function()
							lineFrame:Destroy()
							lineObj.Remove(self)
							return lineObj:Remove()
						end
					end
					return lineObj[index]
				end
			})
		elseif drawingType == "Text" then
			local textObj = ({
				Text = "",
				Font = environment.Drawing.Fonts.UI,
				Size = 0,
				Position = Vector2.zero,
				Center = false,
				Outline = false,
				OutlineColor = Color3.new()
			} + baseDrawingObj)

			local textLabel, uiStroke = Instance.new("TextLabel"), Instance.new("UIStroke")
			textLabel.Name = drawingIndex
			textLabel.AnchorPoint = (Vector2.one * .5)
			textLabel.BorderSizePixel = 0
			textLabel.BackgroundTransparency = 1

			textLabel.Visible = textObj.Visible
			textLabel.TextColor3 = textObj.Color
			textLabel.TextTransparency = convertTransparency(textObj.Transparency)
			textLabel.ZIndex = textObj.ZIndex

			textLabel.FontFace = getFontFromIndex(textObj.Font)
			textLabel.TextSize = textObj.Size

			textLabel:GetPropertyChangedSignal("TextBounds"):Connect(function()
				local textBounds = textLabel.TextBounds
				local offset = textBounds / 2

				textLabel.Size = UDim2.fromOffset(textBounds.X, textBounds.Y)
				textLabel.Position = UDim2.fromOffset(textObj.Position.X + (if not textObj.Center then offset.X else 0), textObj.Position.Y + offset.Y)
			end)

			uiStroke.Thickness = 1
			uiStroke.Enabled = textObj.Outline
			uiStroke.Color = textObj.Color

			textLabel.Parent, uiStroke.Parent = environment.drawingUI, textLabel
			local bs = table.create(0)
			table.insert(drawings,bs)
			return setmetatable(bs, {
				__newindex = function(_, index, value)
					if typeof(textObj[index]) == "nil" then return end

					if index == "Text" then
						textLabel.Text = value
					elseif index == "Font" then
						value = math.clamp(value, 0, 3)
						textLabel.FontFace = getFontFromIndex(value)
					elseif index == "Size" then
						textLabel.TextSize = value
					elseif index == "Position" then
						local offset = textLabel.TextBounds / 2

						textLabel.Position = UDim2.fromOffset(value.X + (if not textObj.Center then offset.X else 0), value.Y + offset.Y)
					elseif index == "Center" then
						local position = (
							if value then
								game.Workspace.CurrentCamera.ViewportSize / 2
								else
								textObj.Position
						)

						textLabel.Position = UDim2.fromOffset(position.X, position.Y)
					elseif index == "Outline" then
						uiStroke.Enabled = value
					elseif index == "OutlineColor" then
						uiStroke.Color = value
					elseif index == "Visible" then
						textLabel.Visible = value
					elseif index == "ZIndex" then
						textLabel.ZIndex = value
					elseif index == "Transparency" then
						local transparency = convertTransparency(value)

						textLabel.TextTransparency = transparency
						uiStroke.Transparency = transparency
					elseif index == "Color" then
						textLabel.TextColor3 = value
					end
					textObj[index] = value
				end,
				__index = function(self, index)
					if index == "Remove" or index == "Destroy" then
						return function()
							textLabel:Destroy()
							textObj.Remove(self)
							return textObj:Remove()
						end
					elseif index == "TextBounds" then
						return textLabel.TextBounds
					end
					return textObj[index]
				end
			})
		elseif drawingType == "Circle" then
			local circleObj = ({
				Radius = 150,
				Position = Vector2.zero,
				Thickness = .7,
				Filled = false
			} + baseDrawingObj)

			local circleFrame, uiCorner, uiStroke = Instance.new("Frame"), Instance.new("UICorner"), Instance.new("UIStroke")
			circleFrame.Name = drawingIndex
			circleFrame.AnchorPoint = (Vector2.one * .5)
			circleFrame.BorderSizePixel = 0

			circleFrame.BackgroundTransparency = (if circleObj.Filled then convertTransparency(circleObj.Transparency) else 1)
			circleFrame.BackgroundColor3 = circleObj.Color
			circleFrame.Visible = circleObj.Visible
			circleFrame.ZIndex = circleObj.ZIndex

			uiCorner.CornerRadius = UDim.new(1, 0)
			circleFrame.Size = UDim2.fromOffset(circleObj.Radius, circleObj.Radius)

			uiStroke.Thickness = circleObj.Thickness
			uiStroke.Enabled = not circleObj.Filled
			uiStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border

			circleFrame.Parent, uiCorner.Parent, uiStroke.Parent = environment.drawingUI, circleFrame, circleFrame
			local bs = table.create(0)
			table.insert(drawings,bs)
			return setmetatable(bs, {
				__newindex = function(_, index, value)
					if typeof(circleObj[index]) == "nil" then return end

					if index == "Radius" then
						local radius = value * 2
						circleFrame.Size = UDim2.fromOffset(radius, radius)
					elseif index == "Position" then
						circleFrame.Position = UDim2.fromOffset(value.X, value.Y)
					elseif index == "Thickness" then
						value = math.clamp(value, .6, 0x7fffffff)
						uiStroke.Thickness = value
					elseif index == "Filled" then
						circleFrame.BackgroundTransparency = (if value then convertTransparency(circleObj.Transparency) else 1)
						uiStroke.Enabled = not value
					elseif index == "Visible" then
						circleFrame.Visible = value
					elseif index == "ZIndex" then
						circleFrame.ZIndex = value
					elseif index == "Transparency" then
						local transparency = convertTransparency(value)

						circleFrame.BackgroundTransparency = (if circleObj.Filled then transparency else 1)
						uiStroke.Transparency = transparency
					elseif index == "Color" then
						circleFrame.BackgroundColor3 = value
						uiStroke.Color = value
					end
					circleObj[index] = value
				end,
				__index = function(self, index)
					if index == "Remove" or index == "Destroy" then
						return function()
							circleFrame:Destroy()
							circleObj.Remove(self)
							return circleObj:Remove()
						end
					end
					return circleObj[index]
				end
			})
		elseif drawingType == "Square" then
			local squareObj = ({
				Size = Vector2.zero,
				Position = Vector2.zero,
				Thickness = .7,
				Filled = false
			} + baseDrawingObj)

			local squareFrame, uiStroke = Instance.new("Frame"), Instance.new("UIStroke")
			squareFrame.Name = drawingIndex
			squareFrame.BorderSizePixel = 0

			squareFrame.BackgroundTransparency = (if squareObj.Filled then convertTransparency(squareObj.Transparency) else 1)
			squareFrame.ZIndex = squareObj.ZIndex
			squareFrame.BackgroundColor3 = squareObj.Color
			squareFrame.Visible = squareObj.Visible

			uiStroke.Thickness = squareObj.Thickness
			uiStroke.Enabled = not squareObj.Filled
			uiStroke.LineJoinMode = Enum.LineJoinMode.Miter

			squareFrame.Parent, uiStroke.Parent = environment.drawingUI, squareFrame
			local bs = table.create(0)
			table.insert(drawings,bs)
			return setmetatable(bs, {
				__newindex = function(_, index, value)
					if typeof(squareObj[index]) == "nil" then return end

					if index == "Size" then
						squareFrame.Size = UDim2.fromOffset(value.X, value.Y)
					elseif index == "Position" then
						squareFrame.Position = UDim2.fromOffset(value.X, value.Y)
					elseif index == "Thickness" then
						value = math.clamp(value, 0.6, 0x7fffffff)
						uiStroke.Thickness = value
					elseif index == "Filled" then
						squareFrame.BackgroundTransparency = (if value then convertTransparency(squareObj.Transparency) else 1)
						uiStroke.Enabled = not value
					elseif index == "Visible" then
						squareFrame.Visible = value
					elseif index == "ZIndex" then
						squareFrame.ZIndex = value
					elseif index == "Transparency" then
						local transparency = convertTransparency(value)

						squareFrame.BackgroundTransparency = (if squareObj.Filled then transparency else 1)
						uiStroke.Transparency = transparency
					elseif index == "Color" then
						uiStroke.Color = value
						squareFrame.BackgroundColor3 = value
					end
					squareObj[index] = value
				end,
				__index = function(self, index)
					if index == "Remove" or index == "Destroy" then
						return function()
							squareFrame:Destroy()
							squareObj.Remove(self)
							return squareObj:Remove()
						end
					end
					return squareObj[index]
				end
			})
		elseif drawingType == "Image" then
			local imageObj = ({
				Data = "",
				DataURL = "rbxassetid://0",
				Size = Vector2.zero,
				Position = Vector2.zero
			} + baseDrawingObj)

			local imageFrame = Instance.new("ImageLabel")
			imageFrame.Name = drawingIndex
			imageFrame.BorderSizePixel = 0
			imageFrame.ScaleType = Enum.ScaleType.Stretch
			imageFrame.BackgroundTransparency = 1

			imageFrame.Visible = imageObj.Visible
			imageFrame.ZIndex = imageObj.ZIndex
			imageFrame.ImageTransparency = convertTransparency(imageObj.Transparency)
			imageFrame.ImageColor3 = imageObj.Color

			imageFrame.Parent = environment.drawingUI
			local bs = table.create(0)
			table.insert(drawings,bs)
			return setmetatable(bs, {
				__newindex = function(_, index, value)
					if typeof(imageObj[index]) == "nil" then return end

					if index == "Data" then
						-- later
					elseif index == "DataURL" then -- temporary property
						imageFrame.Image = value
					elseif index == "Size" then
						imageFrame.Size = UDim2.fromOffset(value.X, value.Y)
					elseif index == "Position" then
						imageFrame.Position = UDim2.fromOffset(value.X, value.Y)
					elseif index == "Visible" then
						imageFrame.Visible = value
					elseif index == "ZIndex" then
						imageFrame.ZIndex = value
					elseif index == "Transparency" then
						imageFrame.ImageTransparency = convertTransparency(value)
					elseif index == "Color" then
						imageFrame.ImageColor3 = value
					end
					imageObj[index] = value
				end,
				__index = function(self, index)
					if index == "Remove" or index == "Destroy" then
						return function()
							imageFrame:Destroy()
							imageObj.Remove(self)
							return imageObj:Remove()
						end
					elseif index == "Data" then
						return nil -- TODO: add error here
					end
					return imageObj[index]
				end
			})
		elseif drawingType == "Quad" then
			local quadObj = ({
				PointA = Vector2.zero,
				PointB = Vector2.zero,
				PointC = Vector2.zero,
				PointD = Vector3.zero,
				Thickness = 1,
				Filled = false
			} + baseDrawingObj)

			local _linePoints = table.create(0)
			_linePoints.A = environment.Drawing.new("Line")
			_linePoints.B = environment.Drawing.new("Line")
			_linePoints.C = environment.Drawing.new("Line")
			_linePoints.D = environment.Drawing.new("Line")
			local bs = table.create(0)
			table.insert(drawings,bs)
			return setmetatable(bs, {
				__newindex = function(_, index, value)
					if typeof(quadObj[index]) == "nil" then return end

					if index == "PointA" then
						_linePoints.A.From = value
						_linePoints.B.To = value
					elseif index == "PointB" then
						_linePoints.B.From = value
						_linePoints.C.To = value
					elseif index == "PointC" then
						_linePoints.C.From = value
						_linePoints.D.To = value
					elseif index == "PointD" then
						_linePoints.D.From = value
						_linePoints.A.To = value
					elseif (index == "Thickness" or index == "Visible" or index == "Color" or index == "ZIndex") then
						for _, linePoint in _linePoints do
							linePoint[index] = value
						end
					elseif index == "Filled" then
						-- later
					end
					quadObj[index] = value
				end,
				__index = function(self, index)
					if index == "Remove" then
						return function()
							for _, linePoint in _linePoints do
								linePoint:Remove()
							end

							quadObj.Remove(self)
							return quadObj:Remove()
						end
					end
					if index == "Destroy" then
						return function()
							for _, linePoint in _linePoints do
								linePoint:Remove()
							end

							quadObj.Remove(self)
							return quadObj:Remove()
						end
					end
					return quadObj[index]
				end
			})
		elseif drawingType == "Triangle" then
			local triangleObj = ({
				PointA = Vector2.zero,
				PointB = Vector2.zero,
				PointC = Vector2.zero,
				Thickness = 1,
				Filled = false
			} + baseDrawingObj)

			local _linePoints = table.create(0)
			_linePoints.A = environment.Drawing.new("Line")
			_linePoints.B = environment.Drawing.new("Line")
			_linePoints.C = environment.Drawing.new("Line")
			local bs = table.create(0)
			table.insert(drawings,bs)
			return setmetatable(bs, {
				__newindex = function(_, index, value)
					if typeof(triangleObj[index]) == "nil" then return end

					if index == "PointA" then
						_linePoints.A.From = value
						_linePoints.B.To = value
					elseif index == "PointB" then
						_linePoints.B.From = value
						_linePoints.C.To = value
					elseif index == "PointC" then
						_linePoints.C.From = value
						_linePoints.A.To = value
					elseif (index == "Thickness" or index == "Visible" or index == "Color" or index == "ZIndex") then
						for _, linePoint in _linePoints do
							linePoint[index] = value
						end
					elseif index == "Filled" then
						-- later
					end
					triangleObj[index] = value
				end,
				__index = function(self, index)
					if index == "Remove" then
						return function()
							for _, linePoint in _linePoints do
								linePoint:Remove()
							end

							triangleObj.Remove(self)
							return triangleObj:Remove()
						end
					end
					if index == "Destroy" then
						return function()
							for _, linePoint in _linePoints do
								linePoint:Remove()
							end

							triangleObj.Remove(self)
							return triangleObj:Remove()
						end
					end
					return triangleObj[index]
				end
			})
		end
	end

	environment.isrenderobj = function(obj)
		return drawings[obj] ~= nil
	end

	environment.getrenderproperty = function(t, property)
		return t[property]
	end

	environment.setrenderproperty = function(t, property, val)
		local success, err = pcall(function()
			t[property] = val
		end)
		if not success and err then
			warn(err)
		end
	end
	environment.cleardrawcache = function()
		for _, v in pairs(drawings) do
			v:Remove()
		end
		table.clear(drawings)
	end

	environment.newcclosure = function(func)
		local wrappedFunc
		wrappedFunc = function(...)
			return func(...)
		end
		local coroutineFunc = coroutine.wrap(wrappedFunc)
		return coroutineFunc
	end

	environment.PeFc2NLXEOaehwb7iGNYwCRbvgWnim = false
	local UserInputService = game:GetService("UserInputService")
	UserInputService.WindowFocusReleased:Connect(function()
		environment.PeFc2NLXEOaehwb7iGNYwCRbvgWnim = false
	end)
	UserInputService.WindowFocused:Connect(function()
		environment.PeFc2NLXEOaehwb7iGNYwCRbvgWnim = true
	end)

	environment.isrbxactive = function()
		return environment.PeFc2NLXEOaehwb7iGNYwCRbvgWnim
	end
	environment.isgameactive = environment.isrbxactive

	environment.getcustomasset = function(assetID)
		if type(assetID) ~= "string" or assetID == "" then
			return ""  
		end    return "rbxasset://" .. assetID
	end

	environment.fireclickdetector = function(fcd, distance, event)
		local ClickDetector = fcd:FindFirstChild("ClickDetector") or fcd
		local upval1 = ClickDetector.Parent
		local part = Instance.new("Part")
		part.Transparency = 1
		part.Size = Vector3.new(30, 30, 30)
		part.Anchored = true
		part.CanCollide = false
		part.Parent = workspace
		ClickDetector.Parent = part
		ClickDetector.MaxActivationDistance = math.huge
		local connection = nil
		connection = game:GetService("RunService").Heartbeat:Connect(function()
			part.CFrame = workspace.Camera.CFrame * CFrame.new(0, 0, -20) * CFrame.new(workspace.Camera.CFrame.LookVector.X, workspace.Camera.CFrame.LookVector.Y, workspace.Camera.CFrame.LookVector.Z)
			game:GetService("VirtualUser"):ClickButton1(Vector2.new(20, 20), workspace:FindFirstChildOfClass("Camera").CFrame)
		end)
		ClickDetector.MouseClick:Once(function()
			connection:Disconnect()
			ClickDetector.Parent = upval1
			part:Destroy()
		end)
	end

	environment.getcallbackvalue = function(object, methodName, ...)
		if object and type(object[methodName]) == "function" then
			return object[methodName]
		end
		local args = {...}
		return args[1]  
	end

	environment.getconnections = function(event)
		if not event or not event.Connect then
			warn("invalidevent")
			return {}
		end
		local connections = {}
			for _, connection in ipairs(event:GetConnected()) do
			local connectinfo = {
				Enabled = connection.Enabled, 
				ForeignState = connection.ForeignState, 
				LuaConnection = connection.LuaConnection, 
				Function = connection.Function,
				Thread = connection.Thread,
				Fire = connection.Fire, 
				Defer = connection.Defer, 
				Disconnect = connection.Disconnect,
				Disable = connection.Disable, 
				Enable = connection.Enable,
			}
			
			table.insert(connections, connectinfo)
		end
		return connections
	end

	environment.isscriptable = function(object, property)
		if object and typeof(object) == 'Instance' then
			local success, result = pcall(function()
				return object[property] ~= nil
			end)
			return success and result
		end
		return false
	end
	
	environment.setscriptable = function(instance, property, scriptable)
		local className = instance.ClassName
			if not environment.scriptableProperties[className] then
				environment.scriptableProperties[className] = {}
		end
			local wasScriptable = environment.scriptableProperties[className][property] or false
			environment.scriptableProperties[className][property] = scriptable
			if scriptable then
			local mt = getmetatable(instance) or {}
			mt.__index = function(t, key)
				if key == property then
					return scriptable
				end
				return rawget(t, key)
			end
			mt.__newindex = function(t, key, value)
				if key == property then
					rawset(t, key, value)
				else
					rawset(t, key, value)
				end
			end
			setmetatable(instance, mt)
		end
		return wasScriptable
	end

	environment.nexar = {
		Saved_Metatable = {},
		ReadOnly = {},
		OriginalTables = {},
		Luau_setmetatable = setmetatable
	}
	environment.isreadonly = function(tbl)
		return environment.nexar.ReadOnly[tbl] or table.isfrozen(tbl) or false
	end
	environment.setreadonly = function(tbl, readOnly)
		if readOnly then
			environment.nexar.ReadOnly[tbl] = true
			local clone = table.clone(tbl)
			environment.nexar.OriginalTables[clone] = tbl
			return environment.nexar.Luau_setmetatable(clone, {
				__index = tbl,
				__newindex = function(_, key, value)
					print("attempt to modify a readonly table")
				end
			})
		else
			return tbl 
		end
	end

	environment.getsenv = function(script)
		local fakeEnvironment = getfenv()
	
		return setmetatable({
			script = script,
		}, {
			__index = function(self, index)
				return fakeEnvironment[index] or rawget(self, index)
			end,
			__newindex = function(self, index, value)
				xpcall(function()
					fakeEnvironment[index] = value
				end, function()
					rawset(self, index, value)
				end)
			end,
		})
	end

	environment.getloadedmodules = function()
		local moduleScripts = {}
		for _, obj in pairs(game:GetDescendants()) do
			if typeof(obj) == "Instance" and obj:IsA("ModuleScript") then 
				table.insert(moduleScripts, obj) 
			end
		end
		return moduleScripts
	end
	
	environment.getrunningscripts = function()
		local runningScripts = {}
		for _, obj in pairs(game:GetDescendants()) do
			if typeof(obj) == "Instance" and obj:IsA("ModuleScript") then
				table.insert(runningScripts, obj)
			elseif typeof(obj) == "Instance" and obj:IsA("LocalScript") then
				if obj.Enabled == true then
					table.insert(runningScripts, obj)
				end
			end
		end
		return runningScripts
	end
	
	environment.getscripts = function()
		local scripts = {}
		for _, scriptt in game:GetDescendants() do
			if scriptt:IsA("LocalScript") or scriptt:IsA("ModuleScript") then
				table.insert(scripts, scriptt)
			end
		end
		return scripts
	end
	
	environment.getscripthash = function(script)
		local isValidType = nil
		if typeof(script) == "Instance" then
			isValidType = script:IsA("Script") or script:IsA("LocalScript") or script:IsA("LuaSourceContainer")
		end
		assert(isValidType, "Expected a Script, LocalScript, or LuaSourceContainer")
		return script:GetHash()
	end	

	environment.getidentity = environment.getthreadcontext

	environment.getgc = function()
		local function lookatduhobjectcuhh(obj, visited, results)
			if visited[obj] then return end
			visited[obj] = true
	
			if type(obj) == "table" or type(obj) == "function" then
				table.insert(results, obj)
				if type(obj) == "table" then
					for _, v in pairs(obj) do
						lookatduhobjectcuhh(v, visited, results)
					end
				end
			end
		end
	
		local visited, results = {}, {}
		lookatduhobjectcuhh(environment, visited, results)
		
		return results
	end

	type Streamer = {
		Offset: number,
		Source: string,
		Length: number,
		IsFinished: boolean,
		LastUnreadBytes: number,
	
		read: (Streamer, len: number?, shiftOffset: boolean?) -> string,
		seek: (Streamer, len: number) -> (),
		append: (Streamer, newData: string) -> (),
		toEnd: (Streamer) -> ()
	}
	
	type BlockData = {
		[number]: {
			Literal: string,
			LiteralLength: number,
			MatchOffset: number?,
			MatchLength: number?
		}
	}
	
	local function plainFind(str, pat)
		return string.find(str, pat, 0, true)
	end
	
	local function streamer(str): Streamer
		local Stream = {}
		Stream.Offset = 0
		Stream.Source = str
		Stream.Length = string.len(str)
		Stream.IsFinished = false	
		Stream.LastUnreadBytes = 0
	
		function Stream.read(self: Streamer, len: number?, shift: boolean?): string
			local len = len or 1
			local shift = if shift ~= nil then shift else true
			local dat = string.sub(self.Source, self.Offset + 1, self.Offset + len)
	
			local dataLength = string.len(dat)
			local unreadBytes = len - dataLength
	
			if shift then
				self:seek(len)
			end
	
			self.LastUnreadBytes = unreadBytes
			return dat
		end
	
		function Stream.seek(self: Streamer, len: number)
			local len = len or 1
	
			self.Offset = math.clamp(self.Offset + len, 0, self.Length)
			self.IsFinished = self.Offset >= self.Length
		end
	
		function Stream.append(self: Streamer, newData: string)
			self.Source ..= newData
			self.Length = string.len(self.Source)
			self:seek(0) 
		end
	
		function Stream.toEnd(self: Streamer)
			self:seek(self.Length)
		end
	
		return Stream
	end

	environment.lz4compress = function(str: string): string
		local blocks: BlockData = {}
		local iostream = streamer(str)
		if iostream.Length > 12 then
			local firstFour = iostream:read(4)
			local processed = firstFour
			local lit = firstFour
			local match = ""
			local LiteralPushValue = ""
			local pushToLiteral = true
			repeat
				pushToLiteral = true
				local nextByte = iostream:read()
				if plainFind(processed, nextByte) then
					local next3 = iostream:read(3, false)
					if string.len(next3) < 3 then
						LiteralPushValue = nextByte .. next3
						iostream:seek(3)
					else
						match = nextByte .. next3
						local matchPos = plainFind(processed, match)
						if matchPos then
							iostream:seek(3)
							repeat
								local nextMatchByte = iostream:read(1, false)
								local newResult = match .. nextMatchByte
	
								local repos = plainFind(processed, newResult) 
								if repos then
									match = newResult
									matchPos = repos
									iostream:seek(1)
								end
							until not plainFind(processed, newResult) or iostream.IsFinished
							local matchLen = string.len(match)
							local pushMatch = true
							if iostream.Length - iostream.Offset <= 5 then
								LiteralPushValue = match
								pushMatch = false
							end
							if pushMatch then
								pushToLiteral = false
								local realPosition = string.len(processed) - matchPos
								processed = processed .. match
								table.insert(blocks, {
									Literal = lit,
									LiteralLength = string.len(lit),
									MatchOffset = realPosition + 1,
									MatchLength = matchLen,
								})
								lit = ""
							end
						else
							LiteralPushValue = nextByte
						end
					end
				else
					LiteralPushValue = nextByte
				end
				if pushToLiteral then
					lit = lit .. LiteralPushValue
					processed = processed .. nextByte
				end
			until iostream.IsFinished
			table.insert(blocks, {
				Literal = lit,
				LiteralLength = string.len(lit)
			})
		else
			local str = iostream.Source
			blocks[1] = {
				Literal = str,
				LiteralLength = string.len(str)
			}
		end
		local output = string.rep("\x00", 4)
		local function write(char)
			output = output .. char
		end
		for chunkNum, chunk in blocks do
			local litLen = chunk.LiteralLength
			local matLen = (chunk.MatchLength or 4) - 4
			local tokenLit = math.clamp(litLen, 0, 15)
			local tokenMat = math.clamp(matLen, 0, 15)
			local token = bit32.lshift(tokenLit, 4) + tokenMat
			write(string.pack("<I1", token))
			if litLen >= 15 then
				litLen = litLen - 15
				repeat
					local nextToken = math.clamp(litLen, 0, 0xFF)
					write(string.pack("<I1", nextToken))
					if nextToken == 0xFF then
						litLen = litLen - 255
					end
				until nextToken < 0xFF
			end
			write(chunk.Literal)
			if chunkNum ~= #blocks then
				write(string.pack("<I2", chunk.MatchOffset))
				if matLen >= 15 then
					matLen = matLen - 15
					repeat
						local nextToken = math.clamp(matLen, 0, 0xFF)
						write(string.pack("<I1", nextToken))
						if nextToken == 0xFF then
							matLen = matLen - 255
						end
					until nextToken < 0xFF
				end
			end
		end
		local compLen = string.len(output) - 4
		local decompLen = iostream.Length
		return string.pack("<I4", compLen) .. string.pack("<I4", decompLen) .. output
	end
	
	environment.lz4decompress = function(lz4data: string): string
		local inputStream = streamer(lz4data)
		local compressedLen = string.unpack("<I4", inputStream:read(4))
		local decompressedLen = string.unpack("<I4", inputStream:read(4))
		local reserved = string.unpack("<I4", inputStream:read(4))
		if compressedLen == 0 then
			return inputStream:read(decompressedLen)
		end
		local outputStream = streamer("")
		repeat
			local token = string.byte(inputStream:read())
			local litLen = bit32.rshift(token, 4)
			local matLen = bit32.band(token, 15) + 4
			if litLen >= 15 then
				repeat
					local nextByte = string.byte(inputStream:read())
					litLen += nextByte
				until nextByte ~= 0xFF
			end
			local literal = inputStream:read(litLen)
			outputStream:append(literal)
			outputStream:toEnd()
			if outputStream.Length < decompressedLen then
				local offset = string.unpack("<I2", inputStream:read(2))
				if matLen >= 19 then
					repeat
						local nextByte = string.byte(inputStream:read())
						matLen += nextByte
					until nextByte ~= 0xFF
				end
				outputStream:seek(-offset)
				local pos = outputStream.Offset
				local match = outputStream:read(matLen)
				local unreadBytes = outputStream.LastUnreadBytes
				local extra
				if unreadBytes then
					repeat
						outputStream.Offset = pos
						extra = outputStream:read(unreadBytes)
						unreadBytes = outputStream.LastUnreadBytes
						match ..= extra
					until unreadBytes <= 0
				end
				outputStream:append(match)
				outputStream:toEnd()
			end
		until outputStream.Length >= decompressedLen
		return outputStream.Source
	end	

	environment.crypt = {}

	environment.crypt.base64encode = function(data)
		local letters = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
		return ((data:gsub('.', function(x) 
			local r, b = '', x:byte()
			for i = 8, 1, -1 do r = r .. (b % 2^i - b % 2^(i-1) > 0 and '1' or '0') end
			return r
		end) .. '0000'):gsub('%d%d%d?%d?%d?%d?', function(x)
			if (#x < 6) then return '' end
			local c = 0
			for i = 1, 6 do c = c + (x:sub(i, i) == '1' and 2^(6-i) or 0) end
			return letters:sub(c + 1, c + 1)
		end) .. ({ '', '==', '=' })[#data % 3 + 1])
	end
	
	environment.crypt.base64decode = function(data)
		local b = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
		data = string.gsub(data, '[^'..b..'=]', '')
		return (data:gsub('.', function(x)
			if x == '=' then return '' end
			local r, f = '', (b:find(x) - 1)
			for i = 6, 1, -1 do
				r = r .. (f % 2^i - f % 2^(i - 1) > 0 and '1' or '0')
			end
			return r
		end):gsub('%d%d%d?%d?%d?%d?%d?%d?', function(x)
			if #x ~= 8 then return '' end
			local c = 0
			for i = 1, 8 do
				c = c + (x:sub(i, i) == '1' and 2^(8 - i) or 0)
			end
			return string.char(c)
		end))
	end

	environment.crypt.base64 = {}
	environment.crypt.base64.encode = environment.crypt.base64encode
	environment.crypt.base64.decode = environment.crypt.base64decode

	environment.crypt.base64_encode = environment.crypt.base64encode
	environment.crypt.base64_decode = environment.crypt.base64decode

	environment.base64 = {}
	environment.base64.encode = environment.crypt.base64encode
	environment.base64.decode = environment.crypt.base64decode

	environment.base64_encode = environment.crypt.base64encode
	environment.base64_decode = environment.crypt.base64decode

	environment.messagebox = function(text, caption, flags)
		local HttpService = game:GetService("HttpService")
		local resp = "Success."
		pcall(function() resp = _request({ Url = "http://localhost:7331/message_box", Method = "POST", Body = HttpService:JSONEncode({text = tostring(text), caption = tostring(caption), flags = tostring(flags)})}).Body end)
		return resp
	end

	environment.loadstringa = function(code, chunkname: string?)
		return function()
			pcall(function()
				local t = _request({ Url = "http://localhost:7331/loadstring_lua", Method = "POST", Body = tostring(code)}).Body
				local byteArray = convertToBytes(t)
				local buff = buffer.create(#byteArray+1)
				for i, byte in ipairs(byteArray) do
					buffer.writeu8(buff, i-1, byte)
				end
				if buffer.readu8(buff, 1) == 0 then
					table.remove(byteArray, 1)
					print("Catched Error:", string.char(table.unpack(byteArray)))
				end
				execute(buff, environment)()
			end)
		end
	end

	environment.raw_execute = function(source, chunkName: string?)
		return function(...)
			local t = _request({ Url = "http://localhost:7331/loadstring_lua", Method = "POST", Body = tostring(source)}).Body
			local byteArray = convertToBytes(t)
			local buff = buffer.create(#byteArray+1)
			for i, byte in ipairs(byteArray) do
				buffer.writeu8(buff, i-1, byte)
			end
			if buffer.readu8(buff, 1) == 0 then
				table.remove(byteArray, 1)
				print("Catched Error:", string.char(table.unpack(byteArray)))
			end
			execute(buff, environment)()
		end
	end

	environment.loadstring = function(source, chunkName: string?)
		if (source == "" or source == " ") then
			return function(...) end
		end

		return function(...) local tx = pcall(environment.raw_execute(source, chunkName)) setfenv(tx, getfenv(debug.info(2, 'f'))) return tx end
	end

	environment.crypt.generatebytes = function(size)
		local randomBytes = table.create(size)
		for i = 1, size do
			randomBytes[i] = string.char(math.random(0, 255))
		end
		return environment.crypt.base64encode(table.concat(randomBytes))
	end
	
	environment.crypt.generatekey = function()
		return environment.crypt.generatebytes(32)
	end
	
	environment.crypt.encrypt = function(plaintext, key)
		local result = {}
		plaintext = tostring(plaintext)
		key = tostring(key)
		for i = 1, #plaintext do
			local byte = string.byte(plaintext, i)
			local keyByte = string.byte(key, (i - 1) % #key + 1)
			table.insert(result, string.format("%02X", bit32.bxor(byte, keyByte)))
		end
		return table.concat(result), key
	end
	
	environment.crypt.decrypt = function(hex, key)
		local result = {}
		key = tostring(key)
		for i = 1, #hex, 2 do
			local byte_str = string.sub(hex, i, i+1)
			local byte = tonumber(byte_str, 16)
			local keyByte = string.byte(key, ((i - 1) // 2) % #key + 1)
			table.insert(result, string.char(bit32.bxor(byte, keyByte)))
		end
		return table.concat(result)
	end

	environment.crypt.hash = environment.getscripthash

	print("Registered functions.")
end

local function interpolate_cenvironments(env1, env2)
	for i,_ in env2 do
		env1[i] = env2[i]
	end
end

local function interpolate_environments(env1, env2)
	for i,_ in env2 do
		env1(0)[i] = env2[i]
	end
end

print("Creating environment...")
local renv, genv = create_environment()
register_functions(renv, true)
register_functions(genv, false)
print("Registering functions...")

interpolate_cenvironments(renv, genv) -- replicate functions from exec env to renv [for use from executor side only] -> don't need to worry about sandboxing
interpolate_environments(getfenv, genv)
print("Sandboxed environments.")

genv.isexecutorclosure = function() return true end
renv.isexecutorclosure = function() return false end
getfenv().isexecutorclosure = renv.isexecutorclosure

genv.isourclosure = genv.isexecutorclosure
renv.isourclosure = renv.isexecutorclosure
getfenv().isourclosure = renv.isourclosure

genv.checkclosure = genv.isourclosure
renv.checkclosure = renv.isourclosure
getfenv().checkclosure = renv.isourclosure

local function Thread()
    while true do
        task.wait()	
		local response = _request({
			Method = "GET",
			Url = "http://localhost:7331/loadstring",
		})

        pcall(function() if response ~= "" then
        local _script = response.Body
        _script = _script:gsub("game:HttpGet", "getgenv().HttpGet")
        local byteArray = convertToBytes(_script)
		local buff = buffer.create(#byteArray+1)
		for i, byte in ipairs(byteArray) do
			buffer.writeu8(buff, i-1, byte)
		end
		if buffer.readu8(buff, 1) == 0 then
			table.remove(byteArray, 1)
			print("Catched Error:", string.char(table.unpack(byteArray)))
		end
		execute(buff, genv)()
    end
        end)
    end
end

print("Spawned thread.")
task.spawn(Thread)

local initialized = false

local initializedEvent = Instance.new("BindableEvent")
local PolicyService = table.create(0)

function PolicyService:InitAsync()
if initialized then return end
local plrs = game:GetService('Players')
local localPlayer = plrs.LocalPlayer
while not localPlayer do
    plrs.PlayerAdded:Wait()
    localPlayer = plrs.LocalPlayer
end
initialized = true
initializedEvent:Fire()
end

function PolicyService:IsSubjectToChinaPolicies()
--self:InitAsync()

return false
end

return PolicyService
