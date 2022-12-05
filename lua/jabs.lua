local M = {}
local api = vim.api

local config = {}

M.conf = {}
config.preview = {}

config = {}

local function setup(c)
    -- create empty default tables for missing config tables
    c = c or {}
    c.offset = c.offset or {}
    c.symbols = c.symbols or {}
    c.keymap = c.keymap or {}
    c.preview = c.preview or {}
    c.highlight = c.highlight or {}
    c.offset = c.offset or {}

    -- position backwards compatibility
    if c.position == 'center' then
        c.position = {'center', 'center'}
    elseif c.position == 'corner' then
        c.position = {'right', 'bottom'}
    end

    -- main popup window stuff
    config.popup = {
        position = c.position or {'right', 'bottom'},
        width = c.width or 50,
        height = c.height or 10,
        relative = c.relative or 'win',
        style = c.style or 'minimal',
        border = c.border or 'single',
        clip_size = not (c.clip_popup_size == false),

        top_offset = c.offset.top or 0,
        bottom_offset = c.offset.bottom or 0,
        left_offset = c.offset.left or 0,
        right_offset = c.offset.right or 0,
    }

    config.preview = {
        width = c.preview.width or 70,
        height = c.preview.height or 30,
        style = c.preview.style or "minimal",
        border = c.preview.border or "double",
        position = c.preview_position or "top",
        relative = "win",
        anchor = "NW",
    }

    config.keymap = {
        delete = c.keymap.close or "D",
        jump = c.keymap.jump or "<cr>",
        h_split = c.keymap.h_split or "s",
        v_split = c.keymap.v_split or "v",
        preview = c.keymap.preview or "P",
    }

    -- sort_mru and split_filename
    config.sort_mru = c.sort_mru or false
    config.split_filename = c.split_filename or false
    config.split_filename_path_width = c.split_filename_path_width or 0

    -- icon / symbol stuff
    config.default_file_symbol = c.symbols.default_file or ""
    config.use_devicons = not (c.use_devicons == false)

    -- Highlight names
    config.highlight_map = {
        ["%a"] = c.highlight.current or "StatusLine",
        ["#a"] = c.highlight.split or "StatusLine",
        ["a"] = c.highlight.split or "StatusLine",
        ["#h"] = c.highlight.alternate or "WarningMsg",
        ["#"] = c.highlight.alternate or "WarningMsg",
        ["h"] = c.highlight.hidden or "ModeMsg",
    }

    -- Buffer info symbols
    config.symbols_map = {
        ["%a"] = c.symbols.current or "",
        ["#a"] = c.symbols.split or "",
        ["a"] = c.symbols.split or "",
        ["#h"] = c.symbols.alternate or "",
        ["h"] = c.symbols.hidden or "﬘",
        ["-"] = c.symbols.locked or "",
        ["="] = c.symbols.ro or "",
        ["+"] = c.symbols.edited or "",
        ["R"] = c.symbols.terminal or "",
        ["F"] = c.symbols.terminal or "",
    }
end

local function iter2array(...)
    local arr = {}
    for v in ... do
        arr[#arr + 1] = v
    end
    return arr
end

local function isJABSPopup(buf)
    return vim.b[buf].isJABSBuffer == true
end

local function getBufferHandleFromLine(line)
    local handle = iter2array(string.gmatch(line, "[^%s]+"))[2]
    return assert(tonumber(handle))
end

local function closePopup()
    local window_handle = vim.api.nvim_get_current_win()
    assert(vim.w[window_handle].isJABSWindow)
    vim.api.nvim_win_close(window_handle, false)
    -- all the cleanup will be done by cleanUp which gets
    -- call by the WinClosed event
end

local function cleanUp()
    vim.api.nvim_clear_autocmds({group = "JABSAutoCmds"})
    for _, win in ipairs(vim.api.nvim_list_wins()) do
        if vim.w[win].isJABSWindow == true then
            vim.api.nvim_win_close(win, false)
        end
    end
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
        if vim.b[buf].isJABSBuffer == true then
            vim.api.nvim_buf_delete(buf, {force = false})
        end
    end
end

local function getFileSymbol(filename)
    local devicons = pcall(require, "nvim-web-devicons")
    if not devicons then
        return '', nil
    end

    local ext =  string.match(filename, "%.(.*)$")

    local symbol, hl = require("nvim-web-devicons").get_icon(filename, ext)
    if not symbol then
        symbol = config.default_file_symbol
    end

    return symbol, hl
end

local function getBufferIcon(flags)
    flags = flags ~= '' and flags or 'h'

    -- if flags do not end with a or h extract trailing char (-> -, =, +, R, F)
    local iconFlag = string.match(flags, "([^ah])$")
    iconFlag = iconFlag or flags

    -- extract '#' or '.*[ah]'
    local hlFlag = string.match(flags, "(.[ah#])")
    hlFlag = hlFlag or flags

    return config.symbols_map[iconFlag], config.highlight_map[hlFlag]
end

local function formatFilename(filename, filename_max_length)
    local function trunc_filename(fn, fn_max)
        if string.len(fn) <= fn_max then
            return fn
        end

        local substr_length = fn_max - string.len("...")
        if substr_length <= 0 then
            return string.rep('.', fn_max)
        end

        return "..." .. string.sub(fn, -substr_length)
    end

    local function split_filename(fn)
        return string.match(fn, "(.-)([^\\/]-%.?[^%.\\/]*)$")
    end

    filename = string.gsub(filename, "term://", "Terminal: ", 1)

    if config.split_filename then
        local path, file = split_filename(filename)
        local path_width = config.split_filename_path_width
        local file_width = filename_max_length - config.split_filename_path_width
        filename = string.format('%-' .. file_width .. "s%-" .. path_width .. "s",
                    trunc_filename(file, file_width),
                    trunc_filename(path, path_width))
    else
        filename = trunc_filename(filename, filename_max_length)
    end

    return string.format("%-" .. filename_max_length .. "s", filename)
end

local function updateBufferFromLsLines(buf, ls_lines)

    for i, ls_line in ipairs(ls_lines) do
        -- extract data from ls string
        local match_cmd = '(%d+)%s+([^%s]*)%s+"(.*)"'
        if not config.sort_mru then
            match_cmd = match_cmd .. '%s*line%s(%d+)'
        else
            -- dummy that should never match so we get '' as result for linenr
            match_cmd = match_cmd .. '(\n?)'
        end

        local buffer_handle, flags, filename, linenr =
            string.match(ls_line, match_cmd)

        -- get symbol and icon
        local fn_symbol, fn_symbol_hl = '', nil
        if config.use_devicons then
            fn_symbol, fn_symbol_hl = getFileSymbol(filename)
        end
        local icon, icon_hl = getBufferIcon(flags)

        -- format preLine and postLine
        local preLine =
            string.format(" %s %3d %s ", icon, buffer_handle, fn_symbol)
        local postLine = linenr ~= '' and string.format("  %3d ", linenr) or ''

        -- some symbols magic, they increase the string.len by more
        -- than 1 and this is a magic trick to get the extra width
        local extra_width = #preLine + #postLine -
            #string.gsub(preLine .. postLine, '[\128-\191]', '')

        -- determine filename field length and format filename
        local buffer_width = vim.api.nvim_win_get_width(0)
        local filename_max_length =
            buffer_width - #preLine - #postLine + extra_width
        local filename_str = formatFilename(filename, filename_max_length)

        -- concat final line for the buffer
        local line = preLine .. filename_str .. postLine

        -- set line and highligh
        api.nvim_buf_set_lines(buf, i, i, true, { line })
        api.nvim_buf_add_highlight(buf, -1, icon_hl, i, 0, -1)
        if fn_symbol_hl and fn_symbol ~= '' then
            local pos = string.find(line, fn_symbol, 1, true)
            api.nvim_buf_add_highlight(buf, -1, fn_symbol_hl, i, pos,
                                       pos + string.len(fn_symbol))
        end
    end
end

local function refresh()
    local popup_width = vim.api.nvim_win_get_width(0)
    local buf = vim.api.nvim_get_current_buf()
    assert(isJABSPopup(buf))

    local ls_result = api.nvim_exec(config.sort_mru and ":ls t" or ":ls", true)
    local ls_lines = iter2array(string.gmatch(ls_result, "([^\n]+)"))

    -- init buffer
    api.nvim_buf_set_option(buf, "modifiable", true)
    api.nvim_buf_set_lines(buf, 0, -1, false, {'Open Buffers:'})
    api.nvim_buf_add_highlight(buf, -1, "Folded", 0, 0, -1)

    -- Prevent cursor from going to buffer title
    vim.cmd(string.format(
        "au CursorMoved <buffer=%s> if line(\".\") == 1 | call feedkeys('j', 'n') | endif",
        buf))

    updateBufferFromLsLines(buf, ls_lines)

    -- Disable modifiable when done
    api.nvim_buf_set_option(buf, "modifiable", false)
end

local function getPreviewConfig(win)
    local pos_x, pos_y
    if config.preview.position == "top" then
        pos_x = config.popup.width / 2 - config.preview.width / 2
        pos_y = -config.preview.height - 2

        if config.popup.border ~= "none" then
            pos_y = pos_y - 1
        end
    elseif config.preview.position == "bottom" then
        pos_x = config.popup.width / 2 - config.preview.width / 2
        pos_y = config.popup.height

        if config.popup.border ~= "none" then
            pos_y = pos_y + 1
        end
    elseif config.preview.position == "right" then
        pos_x = config.popup.width
        pos_y = config.popup.height / 2 - config.preview.height / 2

        if config.popup.border ~= "none" then
            pos_x = pos_x + 1
        end
    elseif config.preview.position == "left" then
        pos_x = -config.preview.width
        pos_y = config.popup.height / 2 - config.preview.height / 2

        if config.popup.border ~= "none" then
            pos_x = pos_x - 1
        end
    end

    return {
        width = config.preview.width,
        height = config.preview.height,
        row = pos_y,
        col = pos_x,
        style = config.preview.style,
        border = config.preview.border,
        anchor = "NW",
        relative = "win",
        win = win
    }
end

local function openPreview()
    local buf = getBufferHandleFromLine(vim.api.nvim_get_current_line())
    local win = vim.api.nvim_get_current_win()

    prev_win = vim.api.nvim_open_win(buf, false, getPreviewConfig(win))

    vim.api.nvim_win_set_var(prev_win, "isJABSWindow", true)
    vim.api.nvim_set_current_win(prev_win)

    -- close preview when cursor leaves window
    local fn_callback = function() api.nvim_win_close(prev_win, false) end
    local options = {group = "JABSAutoCmds", buffer = buf, callback = fn_callback}
    vim.api.nvim_create_autocmd({ "WinLeave" }, options)
end

local function openSelectedBuffer(opt)
    local selected_buf = getBufferHandleFromLine(api.nvim_get_current_line())

    local buf = vim.v.count ~= 0 and vim.v.count or selected_buf

    if vim.fn.bufexists(buf) == 0 then
        print "Buffer number not found!"
        return
    end

    closePopup()

    local openOptions = {
        window = "b%s",
        vsplit = "vert sb %s",
        hsplit = "sb %s",
    }

    vim.cmd(string.format(openOptions[opt], buf))
end

local function deleteSelectedBuffer()
    local buf = getBufferHandleFromLine(api.nvim_get_current_line())

    -- check if file is open in a window
    local buf_win_id = (table.unpack or unpack)(vim.fn.win_findbuf(buf))
    if buf_win_id ~= nil then return end

    vim.cmd("bd " .. buf)
    refresh()
end

local function setKeymaps(buf)

    local function buf_keymap(key, fn_callback)
        api.nvim_buf_set_keymap(buf, "n", key, '',
            {nowait = true, noremap = true, silent = true,
             callback = fn_callback})
    end

    local function winEnterEvent()
        if vim.w.isJABSWindow ~= true then
            cleanUp()
        end
    end

    -- Basic window buffer configuration
    buf_keymap(config.keymap.jump,
               function() openSelectedBuffer("window") end)
    buf_keymap(config.keymap.h_split,
               function() openSelectedBuffer("hsplit") end)
    buf_keymap(config.keymap.v_split,
               function() openSelectedBuffer("vsplit") end)
    buf_keymap(config.keymap.delete, deleteSelectedBuffer)
    buf_keymap(config.keymap.preview, openPreview)

    -- Navigation keymaps
    buf_keymap("q", closePopup)
    buf_keymap("<Esc>", closePopup)

    local options = { nowait = true, noremap = true, silent = true }
    api.nvim_buf_set_keymap(buf, "n", "<Tab>", "j",options)
    api.nvim_buf_set_keymap(buf, "n", "<S-Tab>", "k", options)

    -- some auto commands to handle closing JABS
    api.nvim_create_augroup("JABSAutoCmds", {})
    api.nvim_create_autocmd({'WinEnter'}, {group="JABSAutoCmds",
                                           callback = winEnterEvent})

    local win = vim.api.nvim_get_current_win()
    api.nvim_create_autocmd({'WinClosed'}, {pattern=tostring(win),
                                            group="JABSAutoCmds",
                                            callback = cleanUp})
end

local function getPopupConfig()
    local unpack = table.unpack or unpack
    assert(type(config.popup.position) == 'table')
    assert(#config.popup.position == 2)

    local position_x, position_y = unpack(config.popup.position)
    local relative = config.popup.relative

    -- determine max width and height
    local max_width, max_height
    if relative == 'win' then
        max_width = api.nvim_win_get_width(0)
        max_height = api.nvim_win_get_height(0)
    elseif relative == 'editor' or relative == 'cursor' then
        local ui = api.nvim_list_uis()[1]
        max_width = ui.width
        max_height = ui.height
    else assert(false)
    end

    -- clip size if neccessary
    local size_x, size_y = config.popup.width, config.popup.height
    if config.popup.clip_size then
        size_x = size_x > max_width and max_width or config.popup.width
        size_y = size_y > max_height and max_height or config.popup.height
    end

    local pos_x, pos_y
    if relative == 'cursor' then
        -- calculate position x
            if position_x == 'center' then pos_x = -size_x / 2
        elseif position_x == 'right'  then pos_x = 0 + config.popup.left_offset
        elseif position_x == 'left'   then pos_x = -size_x - config.popup.right_offset
        else assert(false)
        end
        -- calculate position y
            if position_y == 'center' then pos_y = -size_y / 2
        elseif position_y == 'bottom' then pos_y = 0 + config.popup.top_offset
        elseif position_y == 'top'    then pos_y = -size_y - config.popup.bottom_offset
        else assert(false)
        end
    else
        -- calculate position x
            if position_x == 'center' then pos_x = max_width / 2 - size_x / 2
        elseif position_x == 'right'  then pos_x = max_width - size_x - config.popup.right_offset
        elseif position_x == 'left'   then pos_x = 0 + config.popup.left_offset
        else assert(false)
        end

        -- calculate position y
            if position_y == 'center' then pos_y = max_height / 2 - size_y / 2
        elseif position_y == 'bottom' then pos_y = max_height - size_y - config.popup.bottom_offset
        elseif position_y == 'top'    then pos_y = 0 + config.popup.top_offset
        end
    end

    return {
        width = size_x,
        height = size_y,
        row = pos_y,
        col = pos_x,
        style = config.popup.style,
        border = config.popup.border,
        anchor = "NW",
        relative = config.popup.relative,
    }

end

local function open()
    local current_buf = vim.api.nvim_get_current_buf()

    if isJABSPopup(current_buf) then
        closePopup()
        return
    end

    -- init jabs popup buffer
    local buf = api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_name(buf, "expJABS")
    vim.b[buf].isJABSBuffer = true

    win = api.nvim_open_win(buf, true, getPopupConfig())
    vim.api.nvim_win_set_var(win, "isJABSWindow", true)
    refresh()
    setKeymaps(buf)
end

return { open = open, setup = setup }

