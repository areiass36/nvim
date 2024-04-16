require 'lspconfig'.omnisharp.setup({
	cmd = { "dotnet", "/Users/areiass36/.local/share/nvim/mason/packages/omnisharp/libexec/OmniSharp.dll" },
	settings = {
		FormattingOptions = {
			VarForBuiltInType = true,
			OrganizaImports = true
		},
		RoslynExtensionsOptions = {
			EnableAnalyzerSupport = nil
		}
	},
	handlers = {
		["textDocument/definition"] = require('omnisharp_extended').definition_handler,
		["textDocument/typeDefinition"] = require('omnisharp_extended')
		    .type_definition_handler,
		["textDocument/references"] = require('omnisharp_extended').references_handler,
		["textDocument/implementation"] = require('omnisharp_extended')
		    .implementation_handler,
	}
})
