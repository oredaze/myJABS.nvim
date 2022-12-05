local jabs = require('jabs')

vim.api.nvim_create_user_command("JABS", jabs.open, {nargs = 0})
-- to stay backwards compatible
vim.api.nvim_create_user_command("JABSOpen", jabs.open, {nargs = 0})

