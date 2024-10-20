return {
	'mfussenegger/nvim-dap',
	dependencies = {
		'rcarriga/nvim-dap-ui',
		"mfussenegger/nvim-dap",
		"nvim-neotest/nvim-nio"
	},
	config = function()
		local dap = require('dap')
		local ui = require 'dapui'
		-- Setup UI
		ui.setup() -- Initialize DAP-UI

		dap.listeners.after.event_initialized["dapui_config"] = function()
			ui.open()
		end
		dap.listeners.before.event_terminated["dapui_config"] = function()
			ui.close()
		end
		dap.listeners.before.event_exited["dapui_config"] = function()
			ui.close()
		end

		require('dap').set_log_level('DEBUG')
		dap.adapters.coreclr = {
			type = 'executable',
			command = vim.fn.stdpath('data') .. '/mason/bin/netcoredbg',
			args = { '--interpreter=vscode' }
		}

		dap.configurations.cs = {
			{
				type = 'coreclr',
				name = 'Launch .NET Core App',
				request = 'launch',
				program = function()
					os.execute('dotnet build --configuration Debug')
					local cwd = vim.fn.getcwd()
					local program = vim.fn.input('Path to dll:',
						cwd .. '/bin/Debug/net8.0/Summeet.Api.dll',
						'file')
					print(program)
					return program
				end,
				--cwd = '${workspaceFolder}',
				env = {
					ASPNETCORE_ENVIRONMENT = 'Development',
				}
			}
		}

		vim.keymap.set('n', '<F5>', dap.continue, { noremap = true, silent = true })
		vim.keymap.set('n', '<F10>', dap.step_over, { noremap = true, silent = true })
		vim.keymap.set('n', '<F11>', dap.step_into, { noremap = true, silent = true })
		vim.keymap.set('n', '<F12>', dap.step_out, { noremap = true, silent = true })
		vim.keymap.set('n', '<leader>b', dap.toggle_breakpoint, { noremap = true, silent = true })
		vim.keymap.set('n', '<leader>B',
			function()
				dap.set_breakpoint(vim.fn.input('Breakpoint condition: '))
			end, { noremap = true, silent = true })
		vim.keymap.set('n', '<leader>lp',
			function()
				dap.set_breakpoint(nil, nil, vim.fn.input('Log point message: '))
			end, { noremap = true, silent = true })
		vim.keymap.set('n', '<leader>dr', dap.repl.open, { noremap = true, silent = true })
		vim.keymap.set('n', '<leader>dl', dap.run_last, { noremap = true, silent = true })
	end
}
