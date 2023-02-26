local gui = require 'gui'
local widgets = require('gui.widgets')

-- debug line, remove
view = nil
if view then
    view:delete()
    view = nul
end

local CLIPBOARD_MODE = {LOCAL = 1, LINE = 2}

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
TextEditor = defclass(TextEditor, widgets.Widget)

TextEditor.ATTRS{
    text = '',
    text_pen = COLOR_LIGHTCYAN,
    ignore_keys = {'STRING_A096'},
    select_pen = COLOR_CYAN,
    on_change = DEFAULT_NIL,
}

function TextEditor:init()
    self.cursor = nil
    -- lines are derivate of text, stored as variable
    -- for performance
    self.lines = {}
    self.text_offset = 0
    self.clipboard = nil
    self.clipboard_mode = CLIPBOARD_MODE.LOCAL
end

function TextEditor:postComputeFrame()
    self:ensureTrailingSpace()
    self:recomputeLines()
end

function TextEditor:recomputeLines()
    local orig_index = self.cursor and self:cursorToIndex(
        self.cursor.x - 1,
        self.cursor.y
    )
    local orig_sel_end = self.sel_end and self:cursorToIndex(
        self.sel_end.x - 1,
        self.sel_end.y
    )

    self.lines = self.text:strict_wrap(self.frame_body.width)

    local cursor = orig_index and self:indexToCursor(orig_index)
        or {
            x = math.max(1, #self.lines[#self.lines]),
            y = math.max(1, #self.lines)
        }
    self:setCursor(cursor.x, cursor.y)
    self.sel_end = orig_sel_end and self:indexToCursor(orig_sel_end) or nil
end

function TextEditor:getPreferredFocusState()
    return true
end

function TextEditor:setCursor(x, y)
    local lines_count = #self.lines
    local normalized_y = math.max(1, math.min(y, lines_count))

    while (x < 1 and normalized_y > 1) do
        normalized_y = normalized_y - 1
        x = x + #self.lines[normalized_y]
    end

    while (x > #self.lines[normalized_y] and normalized_y < lines_count) do
        x = x - #self.lines[normalized_y]
        normalized_y = normalized_y + 1
    end

    x = math.min(x, #self.lines[normalized_y])

    self.cursor = {
        y = normalized_y,
        x = math.max(1, x)
    }
    self.sel_end = nil
    self.last_cursor_x = nil
end

function TextEditor:setSelection(from_x, from_y, to_x, to_y)
    -- text selection is always start on self.cursor and on self.sel_end
    local from = {x=from_x, y=from_y}
    local to = {x=to_x, y=to_y}

    self.cursor = from
    self.sel_end = (from.x ~= to.x or from.y ~= to.y)
        and to or nil
end

function TextEditor:hasSelection()
    return not not self.sel_end
end

function TextEditor:eraseSelection()
    if (self:hasSelection()) then
        local from, to = self.cursor, self.sel_end
        if (from.y > to.y or (from.y == to.y and from.x > to.x)) then
            from, to = to, from
        end

        local from_ind = self:cursorToIndex(from.x, from.y)
        local to_ind = self:cursorToIndex(to.x, to.y)
        self:setText(self.text:sub(1, from_ind - 1) .. self.text:sub(to_ind + 1))
        self:setCursor(from.x, from.y)
        self.sel_end = nil
    end
end

function TextEditor:setClipboard(text)
    self.clipboard = text
end

function TextEditor:copy()
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

function TextEditor:cut()
    self:copy()
    self:eraseSelection()
end

function TextEditor:paste()
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

function TextEditor:setText(text)
    local changed = self.text ~= text
    self.text = text
    self:recomputeLines()

    if changed and self.on_change then
        self.on_change(text)
    end
end


function TextEditor:ensureTrailingSpace()
    if (self.text:sub(#self.text, #self.text) ~= ' ') then
        self:setText(self.text .. ' ')
    end
end

function TextEditor:insert(text)
    self:eraseSelection()
    local index = self:cursorToIndex(
        self.cursor.x - 1,
        self.cursor.y
    )

    self:setText(
        self.text:sub(1, index) ..
        text ..
        self.text:sub(index + 1)
    )
    self:setCursor(self.cursor.x + #text, self.cursor.y)
end

function TextEditor:cursorToIndex(x, y)
    local cursor = x
    local lines = {table.unpack(self.lines, 1, y - 1)}
    for _, line in ipairs(lines) do
      cursor = cursor + #line
    end

    return cursor
end

function TextEditor:indexToCursor(index)
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

function TextEditor:onRenderBody(dc)
    dc:pen({fg=self.text_pen, bg=COLOR_RESET, bold=true})

    local max_width = dc.width - self.text_offset

    dc:advance(self.text_offset)

    for ind, line in ipairs(self.lines) do
        -- do not render new lines symbol
        line = line:gsub('\n', '')
        dc:string(line)
        dc:newline(self.text_offset)
    end

    local show_focus = self.focus and gui.blink_visible(530)
    if (show_focus) then
        dc:seek(self.text_offset + self.cursor.x - 1, self.cursor.y - 1)
            :char('_')
    end

    if (self:hasSelection()) then
        local from, to = self.cursor, self.sel_end
        if (from.y > to.y or (from.y == to.y and from.x > to.x)) then
            from, to = to, from
        end

        local line = self.lines[from.y]
            :sub(from.x, to.y == from.y and to.x or nil)
            :gsub('\n', '')
        dc:pen({ fg=self.text_pen, bg=self.select_pen })
            :seek(self.text_offset + from.x - 1, from.y - 1)
            :string(line)

        for y = from.y + 1, to.y - 1 do
            line = self.lines[y]:gsub('\n', '')
            dc:seek(self.text_offset, y - 1)
                :string(line)
        end

        if (to.y > from.y) then
            local line = self.lines[to.y]
                :sub(1, to.x)
                :gsub('\n', '')
            dc:seek(self.text_offset, to.y - 1)
                :string(line)
        end

        dc:pen({fg=self.text_pen, bg=COLOR_RESET})
    end
end

function TextEditor:onInput(keys)
    if (keys.LEAVESCREEN or keys._MOUSE_R_DOWN) then
        self:setFocus(false)
        return false
    end

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
            y = math.min(#self.lines, mouse_y + 1 - self.text_offset)
            x = math.min(#self.lines[y], mouse_x + 1 - self.text_offset)
            self:setCursor(x, y)
            return true
        end

    elseif keys._MOUSE_L then
        local mouse_x, mouse_y = self:getMousePos()
        if mouse_x and mouse_y then
            y = math.min(#self.lines, mouse_y + 1 - self.text_offset )
            x = math.min(
                #self.lines[y],
                mouse_x + 1 - self.text_offset
            )
            self:setSelection(self.cursor.x, self.cursor.y, x, y)

            return true
        end

    elseif keys._STRING then
        if keys._STRING == 0 then
            -- handle backspace
            if (self:hasSelection()) then
                self:eraseSelection()
            else
                local del_pos = self:cursorToIndex(
                    self.cursor.x - 1,
                    self.cursor.y
                )
                if del_pos > 0 then
                    local x, y = self.cursor.x - 1, self.cursor.y
                    self:setText(self.text:sub(1, del_pos-1) .. self.text:sub(del_pos+1))
                    self:setCursor(x, y)
                end
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
        self:ensureTrailingSpace()
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
        self:ensureTrailingSpace()
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
        self:ensureTrailingSpace()
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
            local line_start = self:cursorToIndex(1, self.cursor.y)
            local line_end = self:cursorToIndex(#self.lines[self.cursor.y], self.cursor.y)
            self:setText(self.text:sub(1, line_start - 1) .. self.text:sub(line_end + 1))
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
        self:setText(self.text:sub(1, word_start - 1) .. self.text:sub(ind))
        local cursor = self:indexToCursor(word_start - 1)
        self:setCursor(cursor.x, cursor.y)
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
                value=text
            })
        end
    end

    self:addviews{
      widgets.Window{
        frame_title='DF Journal',
        frame={w=35, h=45},
        resizable=true,
        resize_min={w=40, h=10},
        autoarrange_subviews=true,
        subviews={
            TextEditor{
                text=content,
                on_change=on_text_change
            }
        }
      }
    }
end

function JournalScreen:onDismiss()
    view = nil
end

-- if not dfhack.isMapLoaded() then
--     qerror('journal requires a fortress map to be loaded')
-- end

view = view and view:raise() or JournalScreen{}:show()
