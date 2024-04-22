require 'lspconfig'.omnisharp.setup({
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
