utils = require('utils')


-- default config
local config = {
    -- main popup window stuff
    popup = {
        position = {'center', 'top'},
        width = 50,
        height = 10,
        relative = 'win',
        border = 'single',
        clip_size = false,

        top_offset = 0,
        bottom_offset = 0,
        left_offset = 0,
        right_offset = 0,
    },
    preview = {
        width = 70,
        height = 30,
        style = nil,
        border = "double",
        position = "top",
    },
    keymap = {
        delete = "D",
        jump = "<CR>",
        h_split = "s",
        v_split = "v",
        preview = "P",
        toggle_unlisted = "u",
        switch_to = "<S-CR>",
    },
    -- sort_mru and split_filename
    sort_mru = false,
    split_filename = false,
    split_filename_path_width = 0,

    -- icon / symbol stuff
    use_devicons = false,

    highlight = {
        current = "Number",
        split = "Statement",
        alternate = "Function",
        hidden = "String",
        unlisted = "ErrorMsg",
        filename = nil
    },
    symbols = {
        default = "",
        current = "",
        split = "",
        alternate = "",
        hidden = "﬘",
        locked = "",
        ro = "",
        edited = "",
        terminal = "",
    },
}

local function setup(c)
    -- position backwards compatibility
    if c.position == 'center' then
        c.position = {'center', 'center'}
    elseif c.position == 'corner' then
        c.position = {'right', 'bottom'}
    end

    utils.mergeTables(config, c)
end

config.setup = setup

return config

