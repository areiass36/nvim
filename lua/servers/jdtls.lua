-- Java through the Eclipse JDT language server (Mason).
--
-- The server runs on the JDK of the machine, found in JAVA_HOME first and on
-- PATH after it -- a version manager (mise, asdf) is enough. The JDK this
-- config downloads is not used here: that one belongs to the database client
-- (tools/jdk.lua) and stays an implementation detail of it.
--
-- Mason's own `jdtls` launcher is skipped because it is a Python script, so
-- Java support would need a Python too. What follows is the command line that
-- script builds, started directly.
local platform = require("core.platform")
local tools = require("tools")

-- jdtls asks for JavaSE 25 in its OSGi bundles and refuses to resolve on an
-- older JDK: the process exits 13 with nothing useful on stderr, so the
-- version is checked here and the reason is said out loud instead.
local MINIMUM = 25

local share = tools.mason_root .. "/share/jdtls"
local launcher = share .. "/plugins/org.eclipse.equinox.launcher.jar"

--- @return string|nil
local function find_java()
	local home = vim.env.JAVA_HOME
	if home and home ~= "" then
		local candidate = home .. "/bin/java" .. platform.exe_suffix
		if vim.fn.executable(candidate) == 1 then
			return candidate
		end
	end
	local path = vim.fn.exepath("java")
	return path ~= "" and path or nil
end

--- `java -version` writes to stderr, first line: openjdk version "25.0.5" ...
--- @return integer|nil
local function major_version(java)
	local result = vim.system({ java, "-version" }, { text = true }):wait()
	return tonumber(((result.stderr or "") .. (result.stdout or "")):match('version "(%d+)'))
end

--- The server writes a project index and two projects must not share one. The
--- directory name alone would collide between two checkouts of the same
--- project, so the full path decides the suffix.
--- @param root string|nil
local function workspace(root)
	local cache = vim.fn.stdpath("cache") .. "/jdtls"
	if not root then
		return cache .. "/default"
	end
	return ("%s/%s-%s"):format(cache, vim.fs.basename(root), vim.fn.sha256(root):sub(1, 8))
end

-- Resolved before the server is enabled, which is the only thing that starts it.
local java

vim.lsp.config("jdtls", {
	cmd = function(dispatchers, config)
		local command = {
			java,
			"-Declipse.application=org.eclipse.jdt.ls.core.id1",
			"-Declipse.product=org.eclipse.jdt.ls.core.product",
			"-Dosgi.bundles.defaultStartLevel=4",
			-- The server logs into its workspace directory; only real failures.
			"-Dlog.level=ERROR",
			"-Xms1g",
			"--add-modules=ALL-SYSTEM",
			"--add-opens",
			"java.base/java.util=ALL-UNNAMED",
			"--add-opens",
			"java.base/java.lang=ALL-UNNAMED",
			-- Mason downloads lombok next to the server. Without the agent every
			-- getter it generates reads as a missing method.
			"-javaagent:" .. share .. "/lombok.jar",
			"-jar",
			launcher,
			"-configuration",
			share .. "/config",
			"-data",
			workspace(config.root_dir),
		}

		-- Corporate TLS inspection signs with a root that the JDK's own cacerts
		-- does not carry, and the Maven embedded in the server then cannot read
		-- a repository: the project fails to import with "PKIX path building
		-- failed" and the file gets no diagnostics at all. Windows already
		-- trusts that root, so the JVM is pointed at its store. (tools/download
		-- works around the same inspection for curl.)
		if platform.is_windows then
			table.insert(command, 2, "-Djavax.net.ssl.trustStoreType=Windows-ROOT")
		end

		return vim.lsp.rpc.start(command, dispatchers)
	end,
})

--- Buffers opened before the server was enabled do not get a client by
--- themselves; re-running FileType attaches them.
local function attach_open_buffers()
	for _, buf in ipairs(vim.api.nvim_list_bufs()) do
		if vim.api.nvim_buf_is_loaded(buf) and vim.bo[buf].filetype == "java" then
			vim.api.nvim_exec_autocmds("FileType", { buffer = buf, modeline = false })
		end
	end
end

-- Looked up on the first Java buffer instead of at startup: `java -version` is
-- a process, and a session that never opens Java should not pay for it.
local checked = false
local function enable()
	if checked or vim.fn.filereadable(launcher) == 0 then
		return -- Mason is still installing the server; ToolsReady comes back here
	end
	-- One look per session. A JDK installed from now on is picked up on the
	-- next start, which is also when Neovim would see the new PATH anyway.
	checked = true

	java = find_java()
	if not java then
		return tools.notify(
			("no java found for the Java server: it needs a JDK %d+ in JAVA_HOME or on PATH"):format(
				MINIMUM
			),
			vim.log.levels.WARN
		)
	end

	local version = major_version(java)
	if not version or version < MINIMUM then
		return tools.notify(
			("the Java server needs a JDK %d+; %s is %s"):format(MINIMUM, java, version or "unreadable"),
			vim.log.levels.WARN
		)
	end

	vim.lsp.enable("jdtls")
	attach_open_buffers()
end

local group = vim.api.nvim_create_augroup("jdtls_enable", { clear = true })
vim.api.nvim_create_autocmd("FileType", { group = group, pattern = "java", callback = enable })
vim.api.nvim_create_autocmd("User", {
	group = group,
	pattern = "ToolsReady",
	callback = attach_open_buffers,
	desc = "Start jdtls on Java buffers opened while Mason was still installing it",
})
