-- Parse the "[from metadata]" files Roslyn generates for symbols that live in
-- reference assemblies. They contain only signatures; the header tells which
-- assembly they came from.
--
--   #region Assembly System.Runtime, Version=8.0.0.0, ...
--   // /usr/share/dotnet/packs/Microsoft.NETCore.App.Ref/8.0.11/ref/net8.0/System.Runtime.dll
local M = {}

local TYPE_ALIASES = {
	string = "string",
	int32 = "int",
	int64 = "long",
	int16 = "short",
	boolean = "bool",
	char = "char",
	object = "object",
	double = "double",
	single = "float",
	decimal = "decimal",
	byte = "byte",
	sbyte = "sbyte",
	uint32 = "uint",
	uint64 = "ulong",
	uint16 = "ushort",
	void = "void",
}

--- @class csharp.MetadataInfo
--- @field pack string      e.g. Microsoft.NETCore.App
--- @field version string   e.g. 8.0.11
--- @field shared_dir string runtime folder with the implementation assemblies
--- @field dll string       reference assembly file name
--- @field namespace string
--- @field type_name string
--- @field full_type string

--- @param lines string[] file content
--- @param filename string
--- @return csharp.MetadataInfo|nil
function M.parse(lines, filename)
	local ref_path = (lines[2] or ""):match("^//%s*(.-)%s*$")
	ref_path = ref_path and vim.fs.normalize(ref_path) -- Windows paths use backslashes
	if not ref_path or not ref_path:find("/packs/", 1, true) then
		return nil
	end
	-- .../packs/<Pack>.Ref/<version>/ref/<tfm>/<Dll>  ->  .../shared/<Pack>/<version>/
	local root, pack, version, dll = ref_path:match("^(.*)/packs/([^/]+)%.Ref/([^/]+)/ref/[^/]+/([^/]+)$")
	if not root then
		return nil
	end

	local namespace = ""
	for _, line in ipairs(lines) do
		local found = line:match("^namespace%s+([%w%._]+)")
		if found then
			namespace = found
			break
		end
	end
	local type_name = vim.fn.fnamemodify(filename, ":t:r")
	return {
		pack = pack,
		version = version,
		shared_dir = ("%s/shared/%s/%s"):format(root, pack, version),
		dll = dll,
		namespace = namespace,
		type_name = type_name,
		full_type = (namespace ~= "" and (namespace .. ".") or "") .. type_name,
	}
end

--- Remove generic argument lists: IEnumerable<TResult> Select<TSource, TResult>(...) -> IEnumerable Select(...)
function M.strip_generics(line)
	local previous
	repeat
		previous = line
		line = line:gsub("<[^<>]*>", "")
	until line == previous
	return line
end

--- Normalized parameter types of a member: "String? a, Int32 b" -> {"string", "int"}
--- @param flat_line string line without generics
--- @param member string
--- @return string[]|nil
function M.parameter_types(flat_line, member)
	local params = flat_line:match(member .. "%s*%((.-)%)")
	if not params then
		return nil
	end
	local types = {}
	for part in params:gmatch("[^,]+") do
		part = part:gsub("^%s*this%s+", ""):gsub("^%s*(params|ref|out|in)%s+", "")
		local type_name = part:match("^%s*([%w_%.%[%]]+)")
		if type_name then
			type_name = type_name:lower():gsub("^system%.", "")
			types[#types + 1] = TYPE_ALIASES[type_name] or type_name
		end
	end
	return types
end

--- @class csharp.Signature
--- @field name string
--- @field generic string|nil   e.g. "<TSource, TResult>"
--- @field static boolean
--- @field types string[]|nil  normalized parameter types

--- What identifies the member on a metadata line, used to pick the right overload.
--- @return csharp.Signature|nil
function M.signature(line)
	line = line or ""
	local flat = M.strip_generics(line)
	local name = flat:match("([%w_]+)%s*%(") or flat:match("([%w_]+)%s*[{;=]")
	if not name then
		return nil
	end
	return {
		name = name,
		generic = line:match(name .. "%s*(<[^(]->)"),
		static = line:find("%f[%w]static%f[%W]") ~= nil,
		types = M.parameter_types(flat, name),
	}
end

return M
