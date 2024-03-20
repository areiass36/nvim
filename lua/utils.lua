function nodePath()
		local output = assert(io.popen("npm root -g", "r"))
		local path = assert(output:read("*a"))
		return path:gsub("node_modules","")
end
