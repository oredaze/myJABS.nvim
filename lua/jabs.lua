local api = vim.api

local config = {}

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
        toggle_unlisted = c.keymap.toggle_unlisted or "u"
    }

    -- sort_mru and split_filename
    config.sort_mru = c.sort_mru or false
    config.split_filename = c.split_filename or false
    config.split_filename_path_width = c.split_filename_path_width or 0

    config.show_unlisted = c.show_unlisted or false

    -- icon / symbol stuff
    config.default_file_symbol = c.symbols.default_file or ""
    config.use_devicons = not (c.use_devicons == false)

    -- Highlight names
    config.highlight = {
        current = c.highlight.current or "StatusLine",
        split = c.highlight.split or "StatusLine",
        alternate = c.highlight.alternate or "WarningMsg",
        hidden = c.highlight.hidden or "ModeMsg",
        unlisted = c.highlight.unlisted or "ErrorMsg",
    }

    -- Buffer symbols
    config.symbols = {
        current = c.symbols.current or "",
        split = c.symbols.split or "",
        alternate = c.symbols.alternate or "",
        hidden = c.symbols.hidden or "﬘",
        locked = c.symbols.locked or "",
        ro = c.symbols.ro or "",
        edited = c.symbols.edited or "",
        terminal = c.symbols.terminal or "",
    }
end

local function iter2array(...)
    local arr = {}
    for v in ... do
        arr[#arr + 1] = v
    end
    return arr
end

local function getUnicodeStringWidth(str)
    local extra_width = #str - #string.gsub(str, '[\128-\191]', '')
    return string.len(str) - extra_width
end

local function isJABSPopup(buf)
    return vim.b[buf].isJABSBuffer == true
end

local function getBufferHandleFromLine(line)
    local handle = string.match(line, "^[^%d]*(%d+)")
    return assert(tonumber(handle))
end

local function closePopup()
    local window_handle = api.nvim_get_current_win()
    assert(vim.w[window_handle].isJABSWindow)
    api.nvim_win_close(window_handle, false)
    -- all the cleanup will be done by cleanUp which gets
    -- call by the WinClosed event
end

local function cleanUp()
    api.nvim_clear_autocmds({group = "JABSAutoCmds"})
    for _, win in ipairs(api.nvim_list_wins()) do
        if vim.w[win].isJABSWindow == true then
            api.nvim_win_close(win, false)
        end
    end
    for _, buf in ipairs(api.nvim_list_bufs()) do
        if vim.b[buf].isJABSBuffer == true then
            api.nvim_buf_delete(buf, {force = false})
        end
    end
end

local function getFileSymbol(filename)
    if not config.use_devicons or not pcall(require, "nvim-web-devicons") then
        return '', nil
    end

    local ext =  string.match(filename, "%.(.*)$")
    local symbol, hl = require("nvim-web-devicons").get_icon(filename, ext)
    if not symbol then
        symbol = config.default_file_symbol
    end

    return symbol, hl
end

local function getBufferSymbol(flags, unlisted)
    --[[ TODO: known bug: we can't "mark" the alternate buffer because we call
               ls after the JABS window and buffer became the current buffer.
               Therefor the JABS buffer is always the current buffer, the
               previously current buffer became the alternate buffer and the
               previously alternate buffer has no marking anymore.......
               BUT: I don't want to call ls in open (before we create the
               window because that would cause a lot of other "issues"
               For now that's the way it is, maybe there's another solution
               someone can come up with......]]
    local function getSymbol()
        --if string.match(flags, '%%') then
        --    return config.symbols.current
        if string.match(flags, '#') then
            return config.symbols.current
        elseif string.match(flags, 'a') then
            return config.symbols.split
        elseif string.match(flags, '[RF]') then
            return config.symbols.terminal
        elseif string.match(flags, '-') then
            return config.symbols.locked
        elseif string.match(flags, '=') then
            return config.symbols.ro
        elseif string.match(flags, '+') then
            return config.symbols.edited
        else
            return config.symbols.hidden
        end
    end

    local function getHighlight()
        if unlisted then
            return config.highlight.unlisted
        --elseif string.match(flags, '%') then
        --    return config.highlight.current
        elseif string.match(flags, '#') then
            return config.highlight.current
        elseif string.match(flags, 'a') then
            return config.highlight.split
        else
            return config.highlight.hidden
        end
    end

    return getSymbol(), getHighlight()
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

    -- make termial filename nicer
    filename = string.gsub(filename, "^term://(.*)//.*$", "Terminal: %1", 1)

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

local function updateBufferFromLsLines(buf)
    -- build ls command
    local ls_cmd = ":ls"
    if config.show_unlisted then ls_cmd = ls_cmd .. "!" end
    if config.sort_mru then  ls_cmd = ls_cmd .. " t" end
    --execute ls command and split by '\n'
    local ls_result = api.nvim_exec(ls_cmd, true)
    local ls_lines = iter2array(string.gmatch(ls_result, "([^\n]+)"))


    local i = 1
    for _, ls_line in ipairs(ls_lines) do
        -- extract data from ls string
        local match_cmd = '(%d+)(u?)%s*([^%s]*)%s+"(.*)"'
        if not config.sort_mru then
            match_cmd = match_cmd .. '%s*line%s(%d+)'
        else
            -- dummy that should never match so we get '' as result for linenr
            match_cmd = match_cmd .. '(\n?)'
        end

        local buffer_handle, unlisted, flags, filename, linenr =
            string.match(ls_line, match_cmd)

        -- all "valid unlisted buffer" have no flags set!
        -- this seams to make the difference to "invalid buffers" (hidden
        -- buffers from plugins)
        if unlisted == 'u' and flags ~= '' then
            goto continue
        end

        -- get file and buffer symbol
        local fn_symbol, fn_symbol_hl = getFileSymbol(filename)
        local buf_symbol, buf_symbol_hl = getBufferSymbol(flags, unlisted == 'u')

        -- format preLine and postLine
        local preLine =
            string.format(" %s %3d %s ", buf_symbol, buffer_handle, fn_symbol)
        local postLine = linenr ~= '' and string.format("  %3d ", linenr) or ''

        -- determine filename field length and format filename
        local buffer_width = api.nvim_win_get_width(0)
        local filename_max_length =
            buffer_width - getUnicodeStringWidth(preLine .. postLine)
        local filename_str = formatFilename(filename, filename_max_length)

        -- concat final line for the buffer
        local line = preLine .. filename_str .. postLine

        -- set line and highligh
        api.nvim_buf_set_lines(buf, i, i, true, { line })
        api.nvim_buf_add_highlight(buf, -1, buf_symbol_hl, i, 0, -1)
        if fn_symbol_hl and fn_symbol ~= '' then
            local pos = string.find(line, fn_symbol, 1, true)
            api.nvim_buf_add_highlight(buf, -1, fn_symbol_hl, i, pos,
                                       pos + string.len(fn_symbol) - 1)
        end

        i = i + 1
        ::continue::
    end
end

local function refresh()
    --save cursor position
    local cursor_pos = vim.fn.getpos('.')

    local buf = api.nvim_get_current_buf()
    assert(isJABSPopup(buf))

    -- init buffer
    api.nvim_buf_set_option(buf, "modifiable", true)
    api.nvim_buf_set_lines(buf, 0, -1, false, {'Open Buffers:'})
    api.nvim_buf_add_highlight(buf, -1, "Folded", 0, 0, -1)

    updateBufferFromLsLines(buf)

    -- Disable modifiable when done
    api.nvim_buf_set_option(buf, "modifiable", false)
    -- restore cursor position
    vim.fn.setpos('.', cursor_pos)
end

local function getPreviewConfig()
    local pos_table = {
        top = {    pos_x = (config.popup.width - config.preview.width) / 2,
                   pos_y = -config.preview.height - 1 },
        bottom = { pos_x = (config.popup.width - config.preview.width) / 2,
                   pos_y = config.popup.height - 1},
        right = {  pos_x = config.popup.width - 1,
                   pos_y = (config.popup.height - config.preview.height) / 2},
        left = {   pos_x = -config.preview.width - 1,
                   pos_y = (config.popup.height - config.preview.height) / 2 }
    }

    if config.popup.border == 'none' then
        pos_table['top']['pos_y'] = pos_table['top']['pos_y'] - 1
        pos_table['bottom']['pos_y'] = pos_table['bottom']['pos_y'] + 1
        pos_table['right']['pos_x'] = pos_table['right']['pos_x'] + 1
        pos_table['left']['pos_x'] = pos_table['left']['pos_x'] - 1
    end

    return {
        width = config.preview.width,
        height = config.preview.height,
        row = pos_table[config.preview.position]['pos_y'],
        col = pos_table[config.preview.position]['pos_x'],
        style = config.preview.style,
        border = config.preview.border,
        anchor = "NW",
        relative = "win",
        win = api.nvim_get_current_win()
    }
end

local function openPreview()
    local buf = getBufferHandleFromLine(api.nvim_get_current_line())

    local prev_win = api.nvim_open_win(buf, false, getPreviewConfig())

    api.nvim_win_set_var(prev_win, "isJABSWindow", true)
    api.nvim_set_current_win(prev_win)

    -- close preview when cursor leaves window
    local fn_callback = function() api.nvim_win_close(prev_win, false) return true end
    local options = {group = "JABSAutoCmds", buffer = buf, callback = fn_callback}
    api.nvim_create_autocmd({ "WinLeave" }, options)
end

local function openSelectedBuffer(opt)
    local buf = vim.v.count
    if buf == 0 then
        buf = getBufferHandleFromLine(api.nvim_get_current_line())
    end

    if vim.fn.bufexists(buf) == 0 then
        print("Buffer number not found!")
        return
    end

    closePopup()

    local openOptions = {
        window = "e #%s",
        vsplit = "vs #%s",
        hsplit = "sp #%s",
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

    local function toggleUnlisted()
        config.show_unlisted = not config.show_unlisted
        refresh()
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
    buf_keymap(config.keymap.toggle_unlisted, toggleUnlisted)

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

    local win = api.nvim_get_current_win()
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

    local pos_table = {
        cursor = { pos_x = { center = -size_x / 2,
                             right  = 0 + config.popup.left_offset,
                             left   = -size_x - config.popup.right_offset, },
                   pos_y = { center = -size_y / 2,
                             bottom = 0 + config.popup.top_offset,
                             top    = -size_y - config.popup.bottom_offset, },
        },
        win = { pos_x = { center = max_width / 2 - size_x / 2,
                          right  = max_width - size_x - config.popup.right_offset,
                          left   = 0 + config.popup.left_offset, },
                pos_y = { center = max_height / 2 - size_y / 2,
                          bottom = max_height - size_y - config.popup.bottom_offset,
                          top    = 0 + config.popup.top_offset, },
        },
    }
    pos_table.editor = pos_table.win

    return {
        width = size_x,
        height = size_y,
        row = pos_table[relative]["pos_y"][position_y],
        col = pos_table[relative]["pos_x"][position_x],
        style = config.popup.style,
        border = config.popup.border,
        anchor = "NW",
        relative = config.popup.relative,
    }

end

local function open()
    local current_buf = api.nvim_get_current_buf()

    if isJABSPopup(current_buf) then
        closePopup()
        return
    end

    config.show_unlisted = false

    -- init jabs popup buffer
    local buf = api.nvim_create_buf(false, true)
    api.nvim_buf_set_name(buf, "expJABS")
    vim.b[buf].isJABSBuffer = true

    -- Prevent cursor from going to buffer title
    vim.cmd(string.format(
        "au CursorMoved <buffer=%s> if line(\".\") == 1 | call feedkeys('j', 'n') | endif",
        buf))

    win = api.nvim_open_win(buf, true, getPopupConfig())
    api.nvim_win_set_var(win, "isJABSWindow", true)

    refresh()
    setKeymaps(buf)
end

return { open = open, setup = setup }

