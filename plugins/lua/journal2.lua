local gui = require 'gui'
local widgets = require('gui.widgets')

-- debug line, remove
-- view = nil
-- if view then
--     view:delete()
--     view = nul
-- end

local CLIPBOARD_MODE = {LOCAL = 1, LINE = 2}

TextEditor = defclass(TextEditor, widgets.Widget)

TextEditor.ATTRS{
    text = '',
    text_pen = COLOR_LIGHTCYAN,
    ignore_keys = {'STRING_A096'},
    select_pen = COLOR_CYAN,
    on_change = DEFAULT_NIL,
    debug = false
}

function TextEditor:init()
    self.render_start_line = 1
    self.scrollbar = widgets.Scrollbar{
        frame={r=0},
        on_scroll=self:callback('onScrollbar')
    }
    self.editor = TextEditorView{
        text = self.text,
        text_pen = self.text_pen,
        ignore_keys = self.ignore_keys,
        select_pen = self.select_pen,
        debug = self.debug,

        on_change = function (val)
            if (self.editor.cursor.y >= self.render_start_line + self.editor.frame_body.height) then
                self.render_start_line = self.editor.cursor.y - self.editor.frame_body.height + 1
            end

            self:updateLayout()
            if self.on_change then
                self.on_change(val)
            end
        end
    }

    self:addviews{
        self.scrollbar,
        self.editor
    }
    self:setFocus(true)
end

function TextEditor:getPreferredFocusState()
    return true
end

function TextEditor:postUpdateLayout()
    self:updateScrollbar()
end

function TextEditor:onScrollbar(scroll_spec)
    local height = self.editor.frame_body.height
    if scroll_spec == 'down_large' then
        self.render_start_line = self.render_start_line + math.ceil(height / 2)
    elseif scroll_spec == 'up_large' then
        self.render_start_line = self.render_start_line - math.ceil(height / 2)
    elseif scroll_spec == 'down_small' then
        self.render_start_line = self.render_start_line + 1
    elseif scroll_spec == 'up_small' then
        self.render_start_line = self.render_start_line - 1
    else
        self.render_start_line = tonumber(scroll_spec)
    end

    self.render_start_line = math.min(
        #self.editor.lines - height + 1,
        math.max(1, self.render_start_line)
    )

    self:updateScrollbar()
    -- local max_page_top = math.max(1, #self.choices - self.page_size + 1)
    -- self.page_top = math.max(1, math.min(max_page_top, self.page_top + v))
    -- update_list_scrollbar(self)
end

function TextEditor:updateScrollbar()
    local lines_count = #self.editor.lines

    self.scrollbar:update(
        self.render_start_line,
        self.frame_body.height,
        lines_count
    )
    if (self.frame_body.height >= lines_count) then
        self.render_start_line = 1
    end
end

function TextEditor:onInput(keys)
    if self.scrollbar:onInput(keys) then
        return true
    end

    if not self.scrollbar:getMousePos() and not self.scrollbar.is_dragging then
        return self.editor:onInput(keys)
    end
end

function TextEditor:renderSubviews(dc)
    dc:clear()
    self.editor.frame_body.y1 = self.frame_body.y1-(self.render_start_line - 1)
    self.editor:render(dc)
    self.scrollbar:render(dc)
end

-- multiline text editor, features
--[[
Supported features:
 - cursor controlled by arrow keys (left, right, top, bottom)
 - fast rewind by shift+left/alt+b and shift+right/alt+f
 - remember longest x for up/bottom cursor movement
 - mouse control for cursor
 - support few new lines (submit key)
 - wrapable text
 - backspace
 - ctrl+d as delete
 - ctrl+a / ctrl+e go to beginning/end of line
 - ctrl+u delete current line
 - ctrl+w delete last word
 - mouse text selection and replace/remove features for it
 - local copy/paste selection text or current line (ctrl+x/ctrl+c/ctrl+v)
 - go to text begin/end by shift+up/shift+down
--]]
TextEditorView = defclass(TextEditorView, widgets.Widget)

TextEditorView.ATTRS{
    text = '',
    text_pen = COLOR_LIGHTCYAN,
    ignore_keys = {'STRING_A096'},
    select_pen = COLOR_CYAN,
    on_change = DEFAULT_NIL,
    debug = false
}

function TextEditorView:init()
    self.cursor = nil
    -- lines are derivate of text, stored as variable
    -- for performance
    self.lines = {}
    self.clipboard = nil
    self.clipboard_mode = CLIPBOARD_MODE.LOCAL
end


function TextEditorView:getPreferredFocusState()
    return true
end

function TextEditorView:postComputeFrame()
    self:recomputeLines()
end

function TextEditorView:recomputeLines()
    local orig_index = self.cursor and self:cursorToIndex(
        self.cursor.x - 1,
        self.cursor.y
    )
    local orig_sel_end = self.sel_end and self:cursorToIndex(
        self.sel_end.x - 1,
        self.sel_end.y
    )

    self.lines = self.text:strict_wrap(self.frame_body.width)
    -- as cursor always point to "next" char we need invisible last char
    -- that can not be pass by
    self.lines[#self.lines] = self.lines[#self.lines] .. NEWLINE

    local cursor = orig_index and self:indexToCursor(orig_index)
        or {
            x = math.max(1, #self.lines[#self.lines] - 1),
            y = math.max(1, #self.lines)
        }
    self:setCursor(cursor.x, cursor.y)
    self.sel_end = orig_sel_end and self:indexToCursor(orig_sel_end) or nil
end

function TextEditorView:setCursor(x, y)
    x, y = self:normalizeCursor(x, y)
    self.cursor = {x=x, y=y}

    self.sel_end = nil
    self.last_cursor_x = nil
end

function TextEditorView:normalizeCursor(x, y)
    local lines_count = #self.lines

    while (x < 1 and y > 1) do
        y = y - 1
        x = x + #self.lines[y]
    end

    while (x > #self.lines[y] and y < lines_count) do
        x = x - #self.lines[y]
        y = y + 1
    end

    x = math.min(x, #self.lines[y])
    y = math.min(y, lines_count)

    return math.max(1, x), math.max(1, y)
end

function TextEditorView:setSelection(from_x, from_y, to_x, to_y)
    from_x, from_y = self:normalizeCursor(from_x, from_y)
    to_x, to_y = self:normalizeCursor(to_x, to_y)

    -- text selection is always start on self.cursor and on self.sel_end
    local from = {x=from_x, y=from_y}
    local to = {x=to_x, y=to_y}

    self.cursor = from
    self.sel_end = to
end

function TextEditorView:hasSelection()
    return not not self.sel_end
end

function TextEditorView:eraseSelection()
    if (self:hasSelection()) then
        local from, to = self.cursor, self.sel_end
        if (from.y > to.y or (from.y == to.y and from.x > to.x)) then
            from, to = to, from
        end

        local from_ind = self:cursorToIndex(from.x, from.y)
        local to_ind = self:cursorToIndex(to.x, to.y)

        local new_text = self.text:sub(1, from_ind - 1) .. self.text:sub(to_ind + 1)
        self:setText(new_text, from.x, from.y)
        self.sel_end = nil
    end
end

function TextEditorView:setClipboard(text)
    self.clipboard = text
end

function TextEditorView:copy()
    if self.sel_end then
        self.clipboard_mode =  CLIPBOARD_MODE.LOCAL

        local from = self.cursor
        local to = self.sel_end

        local from_ind = self:cursorToIndex(from.x, from.y)
        local to_ind = self:cursorToIndex(to.x, to.y)
        if from_ind > to_ind then
            from_ind, to_ind = to_ind, from_ind
        end

        self:setClipboard(self.text:sub(from_ind, to_ind))
    else
        self.clipboard_mode = CLIPBOARD_MODE.LINE

        self:setClipboard(self.lines[self.cursor.y])
    end
end

function TextEditorView:cut()
    self:copy()
    self:eraseSelection()
end

function TextEditorView:paste()
    if self.clipboard then
        local clipboard = self.clipboard
        if self.clipboard_mode == CLIPBOARD_MODE.LINE and not self:hasSelection() then
            clipboard = self.clipboard
            local cursor_x = self.cursor.x
            self:setCursor(1, self.cursor.y)
            self:insert(clipboard)
            self:setCursor(cursor_x, self.cursor.y)
        else
            self:eraseSelection()
            self:insert(clipboard)
        end

    end
end

function TextEditorView:setText(text, cursor_x, cursor_y)
    local changed = self.text ~= text
    self.text = text
    self:recomputeLines()

    if cursor_x and cursor_y then
        self:setCursor(cursor_x, cursor_y)
    end

    if changed and self.on_change then
        self.on_change(text)
    end
end

function TextEditorView:insert(text)
    self:eraseSelection()
    local index = self:cursorToIndex(
        self.cursor.x - 1,
        self.cursor.y
    )

    local new_text =
        self.text:sub(1, index) ..
        text ..
        self.text:sub(index + 1)
    self:setText(new_text, self.cursor.x + #text, self.cursor.y)
end

function TextEditorView:cursorToIndex(x, y)
    local cursor = x
    local lines = {table.unpack(self.lines, 1, y - 1)}
    for _, line in ipairs(lines) do
      cursor = cursor + #line
    end

    return cursor
end

function TextEditorView:indexToCursor(index)
    for y, line in ipairs(self.lines) do
        if index < #line then
            return {x=index + 1, y=y}
        end
        index = index - #line
    end

    return {
        x=#self.lines[#self.lines],
        y=#self.lines
    }
end

function TextEditorView:onRenderBody(dc)
    dc:pen({fg=self.text_pen, bg=COLOR_RESET, bold=true})

    local max_width = dc.width
    local new_line = self.debug and NEWLINE or ''
    for ind, line in ipairs(self.lines) do
        -- do not render new lines symbol
        local line = line:gsub(NEWLINE, new_line)
        dc:string(line)
        dc:newline()
    end

    local show_focus = not self:hasSelection()
        and self.parent_view.focus
        and gui.blink_visible(530)
    if (show_focus) then
        dc:seek(self.cursor.x - 1, self.cursor.y - 1)
            :char('_')
    end

    if self:hasSelection() then
        local sel_new_line = self.debug and PERIOD or ''
        local from, to = self.cursor, self.sel_end
        if (from.y > to.y or (from.y == to.y and from.x > to.x)) then
            from, to = to, from
        end

        local line = self.lines[from.y]
            :sub(from.x, to.y == from.y and to.x or nil)
            :gsub(NEWLINE, sel_new_line)
        dc:pen({ fg=self.text_pen, bg=self.select_pen })
            :seek(from.x - 1, from.y - 1)
            :string(line)

        for y = from.y + 1, to.y - 1 do
            line = self.lines[y]:gsub(NEWLINE, sel_new_line)
            dc:seek(0, y - 1)
                :string(line)
        end

        if (to.y > from.y) then
            local line = self.lines[to.y]
                :sub(1, to.x)
                :gsub(NEWLINE, sel_new_line)
            dc:seek(0, to.y - 1)
                :string(line)
        end

        dc:pen({fg=self.text_pen, bg=COLOR_RESET})
    end

    if self.debug then
        local cursor_ind = self:cursorToIndex(self.cursor.x, self.cursor.y)
        local cursor_char = self.text:sub(cursor_ind, cursor_ind)
        local debug_msg = string.format(
            'x: %s y: %s ind: %s #line: %s char: %s',
            self.cursor.x,
            self.cursor.y,
            self:cursorToIndex(self.cursor.x, self.cursor.y),
            #self.lines[self.cursor.y],
            (cursor_char == NEWLINE and 'NEWLINE') or
            (cursor_char == ' ' and 'SPACE') or
            (cursor_char == '' and 'nil') or
            cursor_char
        )
        dc:pen({fg=COLOR_LIGHTRED, bg=COLOR_RESET})
            :seek(0, self.parent_view.frame_body.height - 1)
            :string(debug_msg)
    end
end

function TextEditorView:onInput(keys)
    for _,ignore_key in ipairs(self.ignore_keys) do
        if keys[ignore_key] then return false end
    end

    if keys.SELECT then
        -- handle enter
        self:insert(NEWLINE)
        return true
    elseif keys._MOUSE_L_DOWN then
        local mouse_x, mouse_y = self:getMousePos()
        if mouse_x and mouse_y then
            y = math.min(#self.lines, mouse_y + 1)
            x = math.min(#self.lines[y], mouse_x + 1)
            self:setCursor(x, y)
            return true
        end

    elseif keys._MOUSE_L then
        local mouse_x, mouse_y = self:getMousePos()
        if mouse_x and mouse_y then
            y = math.min(#self.lines, mouse_y + 1 )
            x = math.min(
                #self.lines[y],
                mouse_x + 1
            )
            if self.cursor.x ~= x or self.cursor.y ~= y then
                self:setSelection(self.cursor.x, self.cursor.y, x, y)
            else
                self.sel_end = nil
            end

            return true
        end

    elseif keys._STRING then
        if keys._STRING == 0 then
            -- handle backspace
            if (self:hasSelection()) then
                self:eraseSelection()
            else
                local x, y = self.cursor.x - 1, self.cursor.y
                self:setSelection(x, y, x, y)
                self:eraseSelection()
            end
        else
            if (self:hasSelection()) then
                self:eraseSelection()
            end
            local cv = string.char(keys._STRING)
            self:insert(cv)
        end

        return true
    elseif keys.KEYBOARD_CURSOR_LEFT or keys.CUSTOM_CTRL_B then
        self:setCursor(self.cursor.x - 1, self.cursor.y)
        return true
    elseif keys.KEYBOARD_CURSOR_RIGHT or keys.CUSTOM_CTRL_F then
        self:setCursor(self.cursor.x + 1, self.cursor.y)
        return true
    elseif keys.KEYBOARD_CURSOR_UP then
        local last_cursor_x = self.last_cursor_x or self.cursor.x
        local y = math.max(1, self.cursor.y - 1)
        local x = math.min(last_cursor_x, #self.lines[y])
        self:setCursor(x, y)
        self.last_cursor_x = last_cursor_x
        return true
    elseif keys.KEYBOARD_CURSOR_DOWN then
        local last_cursor_x = self.last_cursor_x or self.cursor.x
        local y = math.min(#self.lines, self.cursor.y + 1)
        local x = math.min(last_cursor_x, #self.lines[y])
        self:setCursor(x, y)
        self.last_cursor_x = last_cursor_x
        return true
    elseif keys.KEYBOARD_CURSOR_UP_FAST then
        self:setCursor(1, 1)
        return true
    elseif keys.KEYBOARD_CURSOR_DOWN_FAST then
        -- go to text end
        self:setCursor(
            #self.lines[#self.lines],
            #self.lines
        )
        return true
    elseif keys.CUSTOM_ALT_B or keys.KEYBOARD_CURSOR_LEFT_FAST then
        -- back one word
        local ind = self:cursorToIndex(self.cursor.x, self.cursor.y)
        local _, prev_word_end = self.text
            :sub(1, ind-1)
            :find('.*%s[^%s]')
        self:setCursor(
            self.cursor.x - (ind - (prev_word_end or 1)),
            self.cursor.y
        )
        return true
    elseif keys.CUSTOM_ALT_F or keys.KEYBOARD_CURSOR_RIGHT_FAST then
        -- forward one word
        local ind = self:cursorToIndex(self.cursor.x, self.cursor.y)
        local _, next_word_start = self.text:find('.-[^%s][%s]', ind)
        self:setCursor(
            self.cursor.x + ((next_word_start or #self.text) - ind),
            self.cursor.y
        )
        return true
    elseif keys.CUSTOM_CTRL_A then
        -- line start
        self:setCursor(1, self.cursor.y)
        return true
    elseif keys.CUSTOM_CTRL_E then
        -- line end
        self:setCursor(
            #self.lines[self.cursor.y],
            self.cursor.y
        )
        return true
    elseif keys.CUSTOM_CTRL_U then
        -- delete current line
        if (self:hasSelection()) then
            -- delete all lines that has selection
            self:setSelection(
                1,
                self.cursor.y,
                #self.lines[self.sel_end.y],
                self.sel_end.y
            )
            self:eraseSelection()
        else
            local y = self.cursor.y
            self:setSelection(1, y, #self.lines[y], y)
            self:eraseSelection()

            -- local line_start = self:cursorToIndex(1, self.cursor.y)
            -- local line_end = self:cursorToIndex(#self.lines[self.cursor.y], self.cursor.y)
            -- local new_text = self.text:sub(1, line_start - 1) .. self.text:sub(line_end + 1)
            -- self:setText(new_text)
        end
        return true
    elseif keys.CUSTOM_CTRL_D then
        -- delete char, there is no support for `Delete` key
        local old = self.text
        if (self:hasSelection()) then
            self:eraseSelection()
        else
            local del_pos = self:cursorToIndex(
                self.cursor.x,
                self.cursor.y
            )
            self:setText(old:sub(1, del_pos-1) .. old:sub(del_pos+1))
        end

        return true
    elseif keys.CUSTOM_CTRL_W then
        -- delete one word backward
        local ind = self:cursorToIndex(self.cursor.x, self.cursor.y)
        local _, prev_word_end = self.text
            :sub(1, ind-1)
            :find('.*%s[^%s]')
        local word_start = prev_word_end or 1
        local cursor = self:indexToCursor(word_start - 1)
        local new_text = self.text:sub(1, word_start - 1) .. self.text:sub(ind)
        self:setText(new_text, cursor.x, cursor.y)
        return true
    elseif keys.CUSTOM_CTRL_C then
        self:copy()
        return true
    elseif keys.CUSTOM_CTRL_X then
        self:cut()
        return true
    elseif keys.CUSTOM_CTRL_V then
        self:paste()
        return true
    end

end

JOURNAL_PERSIST_KEY = 'dfjournal-content'

JournalScreen = defclass(JournalScreen, gui.ZScreen)
JournalScreen.ATTRS {
    frame_title = 'journal',
    frame_width = 80,
    frame_height = 40,
    focus_path='journal',
}


function JournalScreen:init()
    local content_entry = dfhack.persistent.get(JOURNAL_PERSIST_KEY)
    local content = content_entry and content_entry.value or ''
    local function on_text_change(text)
        if dfhack.isWorldLoaded() then
            dfhack.persistent.save({
                key=JOURNAL_PERSIST_KEY,
                value=text,
            })
        end
    end

    self.window = widgets.Window{
        frame_title='DF Journal',
        frame={w=65, h=45},
        resizable=true,
        resize_min={w=32, h=10},
        autoarrange_subviews=true,
        subviews={
            TextEditor{
                text=content,
                on_change=on_text_change
            }
        }
      }
    self:addviews{self.window}
end

function JournalScreen:onDismiss()
    view = nil
end

if not dfhack.isMapLoaded() then
    qerror('journal requires a fortress map to be loaded')
end

view = view and view:raise() or JournalScreen{}:show()

