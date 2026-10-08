-- Entry point. Order matters: options and keymaps first, then the plugin
-- manager, then the external tools that are downloaded on first start.
require("core.options")
require("core.keymaps")
require("core.autocmds")
require("tools").setup_path()
require("core.lazy")
require("tools").ensure_all()
require("tools.doctor")
