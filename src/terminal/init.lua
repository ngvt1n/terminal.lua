--- Terminal library for Lua.
--
-- Explain some basics, or the design.
--
-- @copyright Copyright (c) 2024-2024 Thijs Schreijer
-- @author Thijs Schreijer
-- @license MIT, see `LICENSE.md`.
local M = {
  _VERSION = "0.0.1",
  _COPYRIGHT = "Copyright (c) 2024-2024 Thijs Schreijer",
  _DESCRIPTION = "Cross platform terminal library for Lua (Windows/Unix/Mac)",
  cursor = {},
}


local pack, unpack do
  -- nil-safe versions of pack/unpack
  local oldunpack = unpack or table.unpack -- luacheck: ignore
  pack = function(...) return { n = select("#", ...), ... } end
  unpack = function(t, i, j) return oldunpack(t, i or 1, j or t.n or #t) end
end


local sys = require "system"
local t -- the terminal/stream to operate on, default io.stdout


--=============================================================================
-- Stream support
--=============================================================================

--- Stream support.
-- Shortcuts to the stream used.
-- @section stream

--- Writes to the stream.
-- @param ... the values to write
-- @return the return value of the stream's `write` function
-- @within stream
function M.write(...)
  return t:write(...)
end

--- Flushes the stream.
-- @return the return value of the stream's `flush` function
-- @within stream
function M.flush()
  return t:flush()
end


--=============================================================================
-- cursor shapes
--=============================================================================

--- Cursor shapes.
-- Managing the shape and visibility of the cursor. These functions just generate
-- required ansi sequences, without any stack operations.
-- @section cursor_shapes


local shape_reset = "\27[0 q"

local shapes = setmetatable({
  block_blink     = "\27[1 q",
  block           = "\27[2 q",
  underline_blink = "\27[3 q",
  underline       = "\27[4 q",
  bar_blink       = "\27[5 q",
  bar             = "\27[6 q",
  hide            = "\27[8 q",
}, {
  __index = function(t, k)
    error("invalid shape: "..tostring(k), 2)
  end
})

local _shapestack = {
  shape_reset
}


--- Returns the ansi sequence for a cursor shape without writing it to the terminal.
-- @tparam string shape the shape to get, one of the keys `"block"`,
-- `"block_blink"`, `"underline"`, `"underline_blink"`, `"bar"`, `"bar_blink"`, `"hide"`
-- @treturn string ansi sequence to write to the terminal
-- @within cursor_shapes
function M.shapes(shape)
  return shapes[shape]
end

--- Sets the cursor shape and writes it to the terminal (+flush).
-- @tparam string shape the shape to set, one of the keys `"block"`,
-- `"block_blink"`, `"underline"`, `"underline_blink"`, `"bar"`, `"bar_blink"`, `"hide"`
-- @return true
-- @within cursor_shapes
function M.shape(shape)
  t:write(shapes[shape])
  t:flush()
  return true
end

--=============================================================================
--- Cursor shape stack.
-- Managing the shape and visibility of the cursor based on a stack. Since the
-- current shape cannot be requested, using a stack allows the user to revert to
-- a previous state since the stack keeps track of that.
-- It does however require the user to use balanced operations; `push`/`pop`.
-- @section cursor_shape_stack


--- Re-applies the shape at the top of the stack (returns it, does not write it to the terminal).
-- @treturn string ansi sequence to write to the terminal
-- @within cursor_shape_stack
function M.shape_applys()
  return _shapestack[#_shapestack]
end

--- Re-applies the shape at the top of the stack, and writes it to the terminal (+flush).
-- @return true
-- @within cursor_shape_stack
function M.shape_apply()
  t:write(_shapestack[#_shapestack])
  t:flush()
  return true
end

--- Pushes a cursor shape onto the stack (and returns it), without writing it to the terminal.
-- @tparam string shape the shape to push, one of the keys `"block"`,
-- `"block_blink"`, `"underline"`, `"underline_blink"`, `"bar"`, `"bar_blink"`, `"hide"`
-- @treturn string ansi sequence to write to the terminal
-- @within cursor_shape_stack
function M.shape_pushs(shape)
  _shapestack[#_shapestack + 1] = shapes[shape]
  return M.shape_applys()
end

--- Pushes a cursor shape onto the stack, and writes it to the terminal (+flush).
-- @tparam string shape the shape to push, one of the keys `"block"`,
-- `"block_blink"`, `"underline"`, `"underline_blink"`, `"bar"`, `"bar_blink"`, `"hide"`
-- @return true
-- @within cursor_shape_stack
function M.shape_push(shape)
  t:write(M.shape_pushs(shape))
  t:flush()
  return true
end

--- Pops `n` cursor shape(s) off the stack (and returns the last one), without writing it to the terminal.
-- @tparam[opt=1] number n number of shapes to pop
-- @treturn string ansi sequence to write to the terminal
-- @within cursor_shape_stack
function M.shape_pops(n)
  local new_last = math.max(#_shapestack - (n or 1), 1)
  for i = new_last + 1, #_shapestack do
    _shapestack[i] = nil
  end
  return M.shape_applys()
end

--- Pops `n` cursor shape(s) off the stack, and writes the last one to the terminal (+flush).
-- @tparam[opt=1] number n number of shapes to pop
-- @return true
-- @within cursor_shape_stack
function M.shape_pop(n)
  t:write(M.shape_pops(n))
  t:flush()
  return true
end


--=============================================================================
-- cursor position
--=============================================================================
--- Cursor positioning.
-- Managing the cursor in absolute positions, without stack operations.
-- @section cursor_position

local _positionstack = {}


local new_readansi, old_readansi do
  local kbbuffer = {}
  local kbstart = 0
  local kbend = 0

  old_readansi = sys.readansi

  function new_readansi(timeout)
    if kbend ~= 0 then
      -- we have buffered input
      kbstart = kbstart + 1
      local res = kbbuffer[kbstart]
      kbbuffer[kbstart] = nil
      if kbstart == kbend then
        kbstart = 0
        kbend = 0
      end
      return unpack(res)
    end
    return old_readansi(timeout)
  end


  --- Requests the current cursor position from the terminal.
  -- Will read entire keyboard buffer to empty it, then request the cursor position.
  -- The output buffer will be flushed.
  -- In case of a keyboard error, the error will be returned here, but also by
  -- `readansi` on a later call, because readansi retains the proper order of keyboard
  -- input, whilst this function buffers input.
  -- @treturn[1] number row
  -- @treturn[1] number column
  -- @treturn[2] nil
  -- @treturn[2] string error message in case of a keyboard read error
  -- @within cursor_position
  function M.cursor_get()
    -- first empty keyboard buffer
    while true do
      local seq, typ, part = old_readansi(0)
      if seq == nil and typ == "timeout" then
        break
      end
      kbend = kbend + 1
      kbbuffer[kbend] = pack(seq, typ, part)
      if seq == nil then
        -- error reading keyboard
        return nil, "error reading keyboard: "..typ
      end
    end

    -- request cursor position, and flush
    t:write("\27[6n")
    t:flush()

    -- read response
    while true do
      local seq, typ, part = old_readansi(0)
      if seq == nil and typ == "timeout" then
        error("no response from terminal, this is unexpected")
      end
      if typ == "ansi" then
        local row, col = seq:match("^\27%[(%d+);(%d+)R$")
        if row and col then
          return tonumber(row), tonumber(col)
        end
      end
      kbend = kbend + 1
      kbbuffer[kbend] = pack(seq, typ, part)
      if seq == nil then
        -- error reading keyboard
        return nil, "error reading keyboard: "..typ
      end
    end
    -- unreachable
  end
end

--- Returns the ansi sequence to store to backup the current sursor position (in terminal storage, not stacked).
-- @treturn string ansi sequence to write to the terminal
-- @within cursor_position
function M.cursor_saves()
  return "\27[s"
end

--- Writes the ansi sequence to store the current cursor position (in terminal storage, not stacked) to the terminal (+flush).
-- @return true
-- @within cursor_position
function M.cursor_save()
  t:write(M.cursor_saves())
  t:flush()
  return true
end

--- Returns the ansi sequence to restore the cursor position (from the terminal storage, not stacked).
-- @treturn string ansi sequence to write to the terminal
-- @within cursor_position
function M.cursor_restores()
  return "\27[u"
end

--- Writes the ansi sequence to restore the cursor position (from the terminal storage, not stacked) to the terminal (+flush).
-- @return true
-- @within cursor_position
function M.cursor_restore()
  t:write(M.cursor_restores())
  t:flush()
  return true
end

--- Creates ansi sequence to set the cursor position without writing to the terminal or pushing onto the stack.
-- @tparam number row
-- @tparam number column
-- @treturn string ansi sequence to write to the terminal
-- @within cursor_position
function M.cursor_sets(row, column)
  return "\27[" .. tostring(row) .. ";" .. tostring(column) .. "H"
end

--- Sets the cursor position and writes it to the terminal (+flush), without pushing onto the stack.
-- @tparam number row
-- @tparam number column
-- @return true
-- @within cursor_position
function M.cursor_set(row, column)
  t:write(M.cursor_sets(row, column))
  t:flush()
  return true
end


--=============================================================================
--- Cursor positioning stack based.
-- Managing the cursor in absolute positions, stack based.
-- @section cursor_position_stack


--- Pushes the current cursor position onto the stack, and returns an ansi sequence to move to the new position without writing it to the terminal.
-- Calls cursor.get() under the hood.
-- @tparam number row
-- @tparam number column
-- @treturn string ansi sequence to write to the terminal
-- @within cursor_position_stack
function M.cursor_pushs(row, column)
  local r, c = M.cursor.get()
  -- ignore the error, since we need to keep the stack in sync for pop/push operations
  _positionstack[#_positionstack + 1] = { r, c }
  return M.cursor_sets(row, column)
end

--- Pushes the current cursor position onto the stack, and writes an ansi sequence to move to the new position to the terminal (+flush).
-- Calls cursor.get() under the hood.
-- @tparam number row
-- @tparam number column
-- @return true
-- @within cursor_position_stack
function M.cursor_push(row, column)
  t:write(M.cursor_pushs(row, column))
  t:flush()
  return true
end

--- Pops the last n cursor positions off the stack, and returns an ansi sequence to move to the last one without writing it to the terminal.
-- @tparam[opt=1] number n number of positions to pop
-- @treturn string ansi sequence to write to the terminal
-- @within cursor_position_stack
function M.cursor_pops(n)
  n = n or 1
  local entry
  while n > 1 do
    entry = table.remove(_positionstack)
    n = n - 1
  end
  if not entry then
    return ""
  end
  return M.cursor_sets(entry[1], entry[2])
end

--- Pops the last n cursor position off the stack, and writes an ansi sequence to move to the last one to the terminal (+flush).
-- @tparam[opt=1] number n number of positions to pop
-- @return true
-- @within cursor_position_stack
function M.cursor_pop(n)
  t:write(M.cursor_pops(n))
  t:flush()
  return true
end

--=============================================================================
-- cursor movements
--=============================================================================
--- Cursor movements.
-- Moving the cursor around, without stack interactions.
-- @section cursor_moving

--- Creates an ansi sequence to move the cursor up without writing it to the terminal.
-- @tparam[opt=1] number n number of lines to move up
-- @treturn string ansi sequence to write to the terminal
-- @within cursor_moving
function M.cursor_ups(n)
  n = n or 1
  return "\27["..tostring(n).."A"
end

--- Moves the cursor up and writes it to the terminal (+flush).
-- @tparam[opt=1] number n number of lines to move up
-- @return true
-- @within cursor_moving
function M.cursor_up(n)
  t:write(M.cursor_ups(n))
  t:flush()
  return true
end

--- Creates an ansi sequence to move the cursor down without writing it to the terminal.
-- @tparam[opt=1] number n number of lines to move down
-- @treturn string ansi sequence to write to the terminal
-- @within cursor_moving
function M.cursor_downs(n)
  n = n or 1
  return "\27["..tostring(n).."B"
end

--- Moves the cursor down and writes it to the terminal (+flush).
-- @tparam[opt=1] number n number of lines to move down
-- @return true
-- @within cursor_moving
function M.cursor_down(n)
  t:write(M.cursor_downs(n))
  t:flush()
  return true
end

--- Creates an ansi sequence to move the cursor vertically without writing it to the terminal.
-- @tparam[opt=1] number n number of lines to move (negative for up, positive for down)
-- @treturn string ansi sequence to write to the terminal
-- @within cursor_moving
function M.cursor_verticals(n)
  n = n or 1
  if n == 0 then
    return ""
  end
  return "\27[" .. (n < 0 and (tostring(-n) .. "A") or (tostring(n) .. "B"))
end

--- Moves the cursor vertically and writes it to the terminal (+flush).
-- @tparam[opt=1] number n number of lines to move (negative for up, positive for down)
-- @return true
-- @within cursor_moving
function M.cursor_vertical(n)
  t:write(M.cursor_verticals(n))
  t:flush()
  return true
end

--- Creates an ansi sequence to move the cursor left without writing it to the terminal.
-- @tparam[opt=1] number n number of columns to move left
-- @treturn string ansi sequence to write to the terminal
-- @within cursor_moving
function M.cursor_lefts(n)
  n = n or 1
  return "\27["..tostring(n).."D"
end

--- Moves the cursor left and writes it to the terminal (+flush).
-- @tparam[opt=1] number n number of columns to move left
-- @return true
-- @within cursor_moving
function M.cursor_left(n)
  t:write(M.cursor_lefts(n))
  t:flush()
  return true
end

--- Creates an ansi sequence to move the cursor right without writing it to the terminal.
-- @tparam[opt=1] number n number of columns to move right
-- @treturn string ansi sequence to write to the terminal
-- @within cursor_moving
function M.cursor_rights(n)
  n = n or 1
  return "\27["..tostring(n).."C"
end

--- Moves the cursor right and writes it to the terminal (+flush).
-- @tparam[opt=1] number n number of columns to move right
-- @return true
-- @within cursor_moving
function M.cursor_right(n)
  t:write(M.cursor_rights(n))
  t:flush()
  return true
end

--- Creates an ansi sequence to move the cursor horizontally without writing it to the terminal.
-- @tparam[opt=1] number n number of columns to move (negative for left, positive for right)
-- @treturn string ansi sequence to write to the terminal
-- @within cursor_moving
function M.cursor_horizontals(n)
  n = n or 1
  if n == 0 then
    return ""
  end
  return "\27[" .. (n < 0 and (tostring(-n) .. "D") or (tostring(n) .. "C"))
end

--- Moves the cursor horizontally and writes it to the terminal (+flush).
-- @tparam[opt=1] number n number of columns to move (negative for left, positive for right)
-- @return true
-- @within cursor_moving
function M.cursor_horizontal(n)
  t:write(M.cursor_horizontals(n))
  t:flush()
  return true
end

--- Creates an ansi sequence to move the cursor horizontal and vertical without writing it to the terminal.
-- @tparam[opt=0] number rows number of rows to move (negative for up, positive for down)
-- @tparam[opt=0] number columns number of columns to move (negative for left, positive for right)
-- @treturn string ansi sequence to write to the terminal
-- @within cursor_moving
function M.cursor_moves(rows, columns)
  return M.cursor_verticals(rows or 0) .. M.cursor_horizontals(columns or 0)
end

--- Moves the cursor horizontal and vertical and writes it to the terminal (+flush).
-- @tparam[opt=0] number rows number of rows to move (negative for up, positive for down)
-- @tparam[opt=0] number columns number of columns to move (negative for left, positive for right)
-- @return true
-- @within cursor_moving
function M.cursor_move(rows, columns)
  t:write(M.cursor_moves(rows, columns))
  t:flush()
  return true
end

--=============================================================================
-- clearing
--=============================================================================
--- Clearing.
-- Clearing (parts of) the screen.
-- @section clearing

--- Creates an ansi sequence to clear the screen without writing it to the terminal.
-- @treturn string ansi sequence to write to the terminal
-- @within clearing
function M.clears()
  return "\27[2J"
end

--- Clears the screen and writes it to the terminal (+flush).
-- @return true
-- @within clearing
function M.clear()
  t:write(M.clears())
  t:flush()
  return true
end

--- Creates an ansi sequence to clear the screen from the cursor position to the left and top without writing it to the terminal.
-- @treturn string ansi sequence to write to the terminal
-- @within clearing
function M.clear_tops()
  return "\27[1J"
end

--- Clears the screen from the cursor position to the left and top and writes it to the terminal (+flush).
-- @return true
-- @within clearing
function M.clear_top()
  t:write(M.clear_tops())
  t:flush()
  return true
end

--- Creates an ansi sequence to clear the screen from the cursor position to the right and bottom without writing it to the terminal.
-- @treturn string ansi sequence to write to the terminal
-- @within clearing
function M.clear_bottoms()
  return "\27[0J"
end

--- Clears the screen from the cursor position to the right and bottom and writes it to the terminal (+flush).
-- @return true
-- @within clearing
function M.clear_bottom()
  t:write(M.clear_bottoms())
  t:flush()
  return true
end

--- Creates an ansi sequence to clear the line without writing it to the terminal.
-- @treturn string ansi sequence to write to the terminal
-- @within clearing
function M.clear_lines()
  return "\27[2K"
end

--- Clears the line and writes it to the terminal (+flush).
-- @return true
-- @within clearing
function M.clear_line()
  t:write(M.clear_lines())
  t:flush()
  return true
end

--- Creates an ansi sequence to clear the line from the cursor position to the left without writing it to the terminal.
-- @treturn string ansi sequence to write to the terminal
-- @within clearing
function M.clear_starts()
  return "\27[1K"
end

--- Clears the line from the cursor position to the left and writes it to the terminal (+flush).
-- @return true
-- @within clearing
function M.clear_start()
  t:write(M.clear_starts())
  t:flush()
  return true
end

--- Creates an ansi sequence to clear the line from the cursor position to the right without writing it to the terminal.
-- @treturn string ansi sequence to write to the terminal
-- @within clearing
function M.clear_ends()
  return "\27[0K"
end

--- Clears the line from the cursor position to the right and writes it to the terminal (+flush).
-- @return true
-- @within clearing
function M.clear_end()
  t:write(M.clear_ends())
  t:flush()
  return true
end

--- Creates an ansi sequence to clear a box from the cursor position (top-left) without writing it to the terminal.
-- Cursor will return to the original position.
-- @tparam number height the height of the box in rows
-- @tparam number width the width of the box in columns
-- @treturn string ansi sequence to write to the terminal
-- @within clearing
function M.clear_boxs(height, width)
  local line = (" "):rep(width) .. M.cursor_lefts(width)
  local line_next = line .. M.cursor_downs()
  return line_next:rep(height - 1) .. line .. M.cursor_ups(height - 1)
end

--- Clears a box from the cursor position (top-left) and writes it to the terminal (+flush).
-- Cursor will return to the original position.
-- @tparam number height the height of the box in rows
-- @tparam number width the width of the box in columns
-- @treturn string ansi sequence to write to the terminal
-- @within clearing
function M.clear_box(height, width)
  t:write(M.clear_boxs(height, width))
  t:flush()
  return true
end

--=============================================================================
-- scrolling
--=============================================================================
--- Scrolling.
-- Managing the scroll-region, without stack operations.
-- @section scrolling

local _scroll_reset = "\27[r"
local _scrollstack = {
  _scroll_reset,
}

--- Creates an ansi sequence to set the scroll region without writing it to the terminal.
-- If no arguments are given, it resets the scroll region to the whole screen.
-- @tparam number top top row of the scroll region
-- @tparam number bottom bottom row of the scroll region
-- @treturn string ansi sequence to write to the terminal
-- @within scrolling
function M.scroll_regions(top, bottom)
  if not top and not bottom then
    return _scroll_reset
  end
  return "\27["..tostring(top)..";"..tostring(bottom).."r"
end

--- Sets the scroll region and writes it to the terminal (+flush).
-- If no arguments are given, it resets the scroll region to the whole screen.
-- @tparam number top top row of the scroll region
-- @tparam number bottom bottom row of the scroll region
-- @return true
-- @within scrolling
function M.scroll_region(top, bottom)
  t:write(M.scroll_regions(top, bottom))
  t:flush()
  return true
end

--- Creates an ansi sequence to scroll the screen up without writing it to the terminal.
-- @tparam[opt=1] number n number of lines to scroll up
-- @treturn string ansi sequence to write to the terminal
-- @within scrolling
function M.scroll_ups(n)
  n = n or 1
  return "\27["..tostring(n).."S"
end

--- Scrolls the screen up and writes it to the terminal (+flush).
-- @tparam[opt=1] number n number of lines to scroll up
-- @return true
-- @within scrolling
function M.scroll_up(n)
  t:write(M.scroll_ups(n))
  t:flush()
  return true
end

--- Creates an ansi sequence to scroll the screen down without writing it to the terminal.
-- @tparam[opt=1] number n number of lines to scroll down
-- @treturn string ansi sequence to write to the terminal
-- @within scrolling
function M.scroll_downs(n)
  n = n or 1
  return "\27["..tostring(n).."T"
end

--- Scrolls the screen down and writes it to the terminal (+flush).
-- @tparam[opt=1] number n number of lines to scroll down
-- @return true
-- @within scrolling
function M.scroll_down(n)
  t:write(M.scroll_downs(n))
  t:flush()
  return true
end

--- Creates an ansi sequence to scroll the screen vertically without writing it to the terminal.
-- @tparam[opt=0] number n number of lines to scroll (negative for up, positive for down)
-- @treturn string ansi sequence to write to the terminal
-- @within scrolling
function M.scroll_s(n)
  if n == 0 or n == nil then
    return ""
  end
  return "\27[" .. (n < 0 and (tostring(-n) .. "S") or (tostring(n) .. "T"))
end

--- Scrolls the screen vertically and writes it to the terminal (+flush).
-- @tparam[opt=0] number n number of lines to scroll (negative for up, positive for down)
-- @return true
-- @within scrolling
function M.scroll_(n)
  t:write(M.scroll_s(n))
  t:flush()
  return true
end



--=============================================================================
--- Scrolling region.
-- Managing the scroll-region, stack based
-- @section scrolling_region

--- Applies the scroll region at the top of the stack (returns it, does not write it to the terminal).
-- @treturn string ansi sequence to write to the terminal
-- @within scrolling_region
function M.scroll_applys()
  return _scrollstack[#_scrollstack]
end

--- Applies the scroll region at the top of the stack, and writes it to the terminal (+flush).
-- @return true
-- @within scrolling_region
function M.scroll_apply()
  t:write(_scrollstack[#_scrollstack])
  t:flush()
  return true
end

--- Pushes a new scroll region onto the stack (and returns it), without writing it to the terminal.
-- If no arguments are given, it resets the scroll region to the whole screen.
-- @tparam number top top row of the scroll region
-- @tparam number bottom bottom row of the scroll region
-- @treturn string ansi sequence to write to the terminal
-- @within scrolling_region
function M.scroll_pushs(top, bottom)
  _scrollstack[#_scrollstack + 1] = M.scroll_regions(top, bottom)
  return M.scroll_applys()
end

--- Pushes a new scroll region onto the stack, and writes it to the terminal (+flush).
-- If no arguments are given, it resets the scroll region to the whole screen.
-- @tparam number top top row of the scroll region
-- @tparam number bottom bottom row of the scroll region
-- @return true
-- @within scrolling_region
function M.scroll_push(top, bottom)
  t:write(M.scroll_pushs(top, bottom))
  t:flush()
  return true
end

--- Pops `n` scroll region(s) off the stack (and returns the last), without writing it to the terminal.
-- @tparam[opt=1] number n number of scroll regions to pop
-- @treturn string ansi sequence to write to the terminal
-- @within scrolling_region
function M.scroll_pops(n)
  local new_top = math.max(#_scrollstack - (n or 1), 1)
  for i = new_top, #_scrollstack do
    _scrollstack[i] = nil
  end
  return M.scroll_applys()
end

--- Pops `n` scroll region(s) off the stack, and writes the last to the terminal (+flush).
-- @tparam[opt=1] number n number of scroll regions to pop
-- @return true
-- @within scrolling_region
function M.scroll_pop(n)
  t:write(M.scroll_pops(n))
  t:flush()
  return true
end


--=============================================================================
-- text: colors & attributes
--=============================================================================
-- Text colors and attributes.
-- Managing the text color and attributes.
-- @section textcolor

local fg_color_reset = "\27[39m"
local bg_color_reset = "\27[49m"
local attribute_reset = "\27[0m"
local bold_on = "\27[1m"
local bold_off = "\27[22m"
local underline_on = "\27[4m"
local underline_off = "\27[24m"
local blink_on = "\27[5m"
local blink_off = "\27[25m"
local reverse_on = "\27[7m"
local reverse_off = "\27[27m"
local invisible_on = "\27[8m"
local invisible_off = "\27[28m"

local default_colors = {
  fg = fg_color_reset, -- reset fg
  bg = bg_color_reset, -- reset bg
  bold = false,
  underline = false,
  blink = false,
  reverse = false,
  invisible = false,
}

local _colorstack = {
  default_colors,
}

-- Takes a color name/scheme by user and returns the ansi sequence for it.
local function colorcode(color)
  error("not implemented")
end

--- Creates an ansi sequence to set the foreground color without writing it to the terminal.
-- @tparam string color the color to set
-- @treturn string ansi sequence to write to the terminal
-- @within textcolor
function M.color_fgs(color)
  return colorcode(color)
end

--- Sets the foreground color and writes it to the terminal (+flush).
-- @tparam string color the color to set
-- @return true
-- @within textcolor
function M.color_fg(color)
  t:write(M.color_fgs(color))
  t:flush()
  return true
end

--- Creates an ansi sequence to set the background color without writing it to the terminal.
-- @tparam string color the color to set
-- @treturn string ansi sequence to write to the terminal
-- @within textcolor
function M.color_bgs(color)
  return colorcode(color)
end

--- Sets the background color and writes it to the terminal (+flush).
-- @tparam string color the color to set
-- @return true
-- @within textcolor
function M.color_bg(color)
  t:write(M.color_bgs(color))
  t:flush()
  return true
end

--- Creates an ansi sequence to set the bold attribute without writing it to the terminal.
-- @treturn string ansi sequence to write to the terminal
-- @within textcolor
function M.bold_ons()
  return bold_on
end

--- Sets the bold attribute and writes it to the terminal (+flush).
-- @return true
-- @within textcolor
function M.bold_on()
  t:write(M.bold_ons())
  t:flush()
  return true
end

--- Creates an ansi sequence to unset the bold attribute without writing it to the terminal.
-- @treturn string ansi sequence to write to the terminal
-- @within textcolor
function M.bold_offs()
  return bold_off
end

--- Unsets the bold attribute and writes it to the terminal (+flush).
-- @return true
-- @within textcolor
function M.bold_off()
  t:write(M.bold_offs())
  t:flush()
  return true
end

--- Creates an ansi sequence to set the underline attribute without writing it to the terminal.
-- @treturn string ansi sequence to write to the terminal
-- @within textcolor
function M.underline_ons()
  return underline_on
end

--- Sets the underline attribute and writes it to the terminal (+flush).
-- @return true
-- @within textcolor
function M.underline_on()
  t:write(M.underline_ons())
  t:flush()
  return true
end

--- Creates an ansi sequence to unset the underline attribute without writing it to the terminal.
-- @treturn string ansi sequence to write to the terminal
-- @within textcolor
function M.underline_offs()
  return underline_off
end

--- Unsets the underline attribute and writes it to the terminal (+flush).
-- @return true
-- @within textcolor
function M.underline_off()
  t:write(M.underline_offs())
  t:flush()
  return true
end

--- Creates an ansi sequence to set the blink attribute without writing it to the terminal.
-- @treturn string ansi sequence to write to the terminal
-- @within textcolor
function M.blink_ons()
  return blink_on
end

--- Sets the blink attribute and writes it to the terminal (+flush).
-- @return true
-- @within textcolor
function M.blink_on()
  t:write(M.blink_ons())
  t:flush()
  return true
end

--- Creates an ansi sequence to unset the blink attribute without writing it to the terminal.
-- @treturn string ansi sequence to write to the terminal
-- @within textcolor
function M.blink_offs()
  return blink_off
end

--- Unsets the blink attribute and writes it to the terminal (+flush).
-- @return true
-- @within textcolor
function M.blink_off()
  t:write(M.blink_offs())
  t:flush()
  return true
end

--- Creates an ansi sequence to set the reverse attribute without writing it to the terminal.
-- @treturn string ansi sequence to write to the terminal
-- @within textcolor
function M.reverse_ons()
  return reverse_on
end

--- Sets the reverse attribute and writes it to the terminal (+flush).
-- @return true
-- @within textcolor
function M.reverse_on()
  t:write(M.reverse_ons())
  t:flush()
  return true
end

--- Creates an ansi sequence to unset the reverse attribute without writing it to the terminal.
-- @treturn string ansi sequence to write to the terminal
-- @within textcolor
function M.reverse_offs()
  return reverse_off
end

--- Unsets the reverse attribute and writes it to the terminal (+flush).
-- @return true
-- @within textcolor
function M.reverse_off()
  t:write(M.reverse_offs())
  t:flush()
  return true
end

--- Creates an ansi sequence to set the invisible attribute without writing it to the terminal.
-- @treturn string ansi sequence to write to the terminal
-- @within textcolor
function M.invisible_ons()
  return invisible_on
end

--- Sets the invisible attribute and writes it to the terminal (+flush).
-- @return true
-- @within textcolor
function M.invisible_on()
  t:write(M.invisible_ons())
  t:flush()
  return true
end

--- Creates an ansi sequence to unset the invisible attribute without writing it to the terminal.
-- @treturn string ansi sequence to write to the terminal
-- @within textcolor
function M.invisible_offs()
  return invisible_off
end

--- Unsets the invisible attribute and writes it to the terminal (+flush).
-- @return true
-- @within textcolor
function M.invisible_off()
  t:write(M.invisible_offs())
  t:flush()
  return true
end


local function newtext(attr)
  local last = _colorstack[#_colorstack]
  local new = {
    fg        = attr.fg         == nil and last.fg        or colorcode(attr.fg),
    bg        = attr.bg         == nil and last.bg        or colorcode(attr.bg),
    bold      = attr.bold       == nil and last.bold      or (not not attr.bold),
    underline = attr.underline  == nil and last.underline or (not not attr.underline),
    blink     = attr.blink      == nil and last.blink     or (not not attr.blink),
    reverse   = attr.reverse    == nil and last.reverse   or (not not attr.reverse),
    invisible = attr.invisible  == nil and last.invisible or (not not attr.invisible),
  }
  new.ansi = new.fg .. new.bg ..
    attribute_reset ..
    (new.bold and bold_on or "") ..
    (new.underline and underline_on or "") ..
    (new.blink and blink_on or "") ..
    (new.reverse and reverse_on or "") ..
    (new.invisible and invisible_on or "")

  return new
end

--- Creates an ansi sequence to set the text attributes without writing it to the terminal.
-- Every element omitted in the `attr` table will be taken from the current top of the stack.
-- @tparam table attr the attributes to set, with keys:
-- @tparam[opt] string attr.fg the foreground color to set
-- @tparam[opt] string attr.bg the background color to set
-- @tparam[opt] boolean attr.bold whether to set bold
-- @tparam[opt] boolean attr.underline whether to set underline
-- @tparam[opt] boolean attr.blink whether to set blink
-- @tparam[opt] boolean attr.reverse whether to set reverse
-- @tparam[opt] boolean attr.invisible whether to set invisible
-- @treturn string ansi sequence to write to the terminal
-- @within textcolor
function M.textsets(attr)
  local new = newtext(attr)
  return new.ansi
end

--- Sets the text attributes and writes it to the terminal (+flush).
-- Every element omitted in the `attr` table will be taken from the current top of the stack.
-- @tparam table attr the attributes to set, see `textsets` for details.
-- @return true
-- @within textcolor
function M.textset(attr)
  t:write(newtext(attr).ansi)
  t:flush()
  return true
end

--- Pushes the current attributes onto the stack, and returns an ansi sequence to set the new attributes without writing it to the terminal.
-- Every element omitted in the `attr` table will be taken from the current top of the stack.
-- @tparam table attr the attributes to set, see `textsets` for details.
-- @treturn string ansi sequence to write to the terminal
-- @within textcolor
function M.textpushs(attr)
  local new = newtext(attr)
  _colorstack[#_colorstack + 1] = new
  return new.ansi
end

--- Pushes the current attributes onto the stack, and writes an ansi sequence to set the new attributes to the terminal (+flush).
-- Every element omitted in the `attr` table will be taken from the current top of the stack.
-- @tparam table attr the attributes to set, see `textsets` for details.
-- @return true
-- @within textcolor
function M.textpush(attr)
  t:write(M.textpushs(attr))
  t:flush()
  return true
end

--- Pops n attributes off the stack (and returns the last one), without writing it to the terminal.
-- @tparam[opt=1] number n number of attributes to pop
-- @treturn string ansi sequence to write to the terminal
-- @within textcolor
function M.textpops(n)
  n = n or 1
  local l = #_colorstack
  while n > 1 and l > 1 do
    table.remove(_colorstack)
    l = l - 1
    n = n - 1
  end
  if l == 1 then
    return _colorstack[1]  -- cannot pop last one
  end
  return table.remove(_colorstack)
end

--- Pops n attributes off the stack, and writes the last one to the terminal (+flush).
-- @tparam[opt=1] number n number of attributes to pop
-- @return true
-- @within textcolor
function M.textpop(n)
  t:write(M.textpops(n))
  t:flush()
  return true
end

--- Re-applies the current attributes (returns it, does not write it to the terminal).
-- @treturn string ansi sequence to write to the terminal
-- @within textcolor
function M.textapplys()
  return _colorstack[#_colorstack].ansi
end

--- Re-applies the current attributes, and writes it to the terminal (+flush).
-- @return true
-- @within textcolor
function M.textapply()
  t:write(_colorstack[#_colorstack].ansi)
  t:flush()
  return true
end



--=============================================================================
-- line drawing
--=============================================================================
--- Drawing lines.
-- Drawing horizontal and vertical lines.
-- @section lines

--- Creates a sequence to draw a horizontal line without writing it to the terminal.
-- Line is drawn left to right.
-- Returned sequence might be shorter than requested if the character is a multi-byte character
-- and the number of columns is not a multiple of the character width.
-- @tparam number n number of columns to draw
-- @tparam[opt="─"] string char the character to draw
-- @treturn string ansi sequence to write to the terminal
-- @within lines
function M.line_horizontals(n, char)
  char = char or "─"
  local w = sys.utf8cwidth(char)
  return char:rep(math.floor(n / w))
end

--- Draws a horizontal line and writes it to the terminal (+flush).
-- Line is drawn left to right.
-- Returned sequence might be shorter than requested if the character is a multi-byte character
-- and the number of columns is not a multiple of the character width.
-- @tparam number n number of columns to draw
-- @tparam[opt="─"] string char the character to draw
-- @return true
-- @within lines
function M.line_horizontal(n, char)
  t:write(M.line_horizontals(n, char))
  t:flush()
  return true
end

--- Creates a sequence to draw a vertical line without writing it to the terminal.
-- Line is drawn top to bottom. Cursor is left to the right of the last character (so not below it).
-- @tparam number n number of rows/lines to draw
-- @tparam[opt="│"] string char the character to draw
-- @tparam[opt] boolean lastcolumn whether to draw the last column of the terminal
-- @treturn string ansi sequence to write to the terminal
-- @within lines
function M.line_verticals(n, char, lastcolumn)
  char = char or "│"
  lastcolumn = lastcolumn and 1 or 0
  local w = sys.utf8cwidth(char)
  -- TODO: why do we need 'lastcolumn*2' here???
  return (char .. M.cursor_lefts(w-lastcolumn*2) .. M.cursor_downs(1)):rep(n-1) .. char
end

--- Draws a vertical line and writes it to the terminal (+flush).
-- Line is drawn top to bottom. Cursor is left to the right of the last character (so not below it).
-- @tparam number n number of rows/lines to draw
-- @tparam[opt="│"] string char the character to draw
-- @return true
-- @within lines
function M.line_vertical(n, char)
  t:write(M.line_verticals(n, char))
  t:flush()
  return true
end

--- Creates a sequence to draw a horizontal line with a title centered in it without writing it to the terminal.
-- Line is drawn left to right. If the width is too small for the title, the title is truncated with "trailing `"..."`.
-- If less than 4 characters are available for the title, the title is omitted alltogether.
-- @tparam number width the total width of the line in columns
-- @tparam[opt=""] string title the title to draw (if empty or nil, only the line is drawn)
-- @tparam[opt="─"] string char the line-character to use
-- @tparam[opt=""] string pre the prefix for the title, eg. "┤ "
-- @tparam[opt=""] string post the postfix for the title, eg. " ├"
-- @treturn string ansi sequence to write to the terminal
-- @within lines
function M.line_titles(width, title, char, pre, post)

  -- TODO: strip any ansi sequences from the title before determining length
  -- such that titles can have multiple colors etc. what if we truncate????

  if title == nil or title == "" then
    return M.line_horizontals(width, char)
  end
  pre = pre or ""
  post = post or ""
  local pre_w = sys.utf8swidth(pre)
  local post_w = sys.utf8swidth(post)
  local title_w = sys.utf8swidth(title)
  local w_for_title = width - pre_w - post_w
  if w_for_title > title_w then
    -- enough space for title
    local p1 = M.line_horizontals(math.floor((w_for_title - title_w) / 2), char) .. pre .. title .. post
    return  p1 .. M.line_horizontals(width - sys.utf8swidth(p1), char)
  elseif w_for_title < 4 then
    -- too little space for title, omit it alltogether
    return M.line_horizontals(width, char)
  elseif w_for_title == title_w then
    -- exact space for title
    return pre .. title .. post
  else -- truncate the title
    w_for_title = w_for_title - 3 -- for "..."
    while title_w == nil or title_w > w_for_title do
      title = title:sub(1, -2) -- drop last byte
      title_w = sys.utf8swidth(title)
    end
    return pre .. title .. "..." .. post
  end
end

--- Draws a horizontal line with a title centered in it and writes it to the terminal (+flush).
-- Line is drawn left to right. If the width is too small for the title, the title is truncated with "trailing `"..."`.
-- If less than 4 characters are available for the title, the title is omitted alltogether.
-- @tparam string title the title to draw
-- @tparam number width the total width of the line in columns
-- @tparam[opt="─"] string char the line-character to use
-- @tparam[opt=""] string pre the prefix for the title, eg. "┤ "
-- @tparam[opt=""] string post the postfix for the title, eg. " ├"
-- @return true
-- @within lines
function M.line_title(title, width, char, pre, post)
  t:write(M.line_titles(title, width, char, pre, post))
  t:flush()
  return true
end

--- Table with pre-defined box formats.
-- @table box_fmt
-- @field single Single line box format
-- @field double Double line box format
-- @field copy Function to copy a box format, see `box_fmt.copy` for details
-- @within lines
M.box_fmt = setmetatable({
  single = {
    h = "─",
    v = "│",
    tl = "┌",
    tr = "┐",
    bl = "└",
    br = "┘",
    pre = "┤",
    post = "├",
  },
  double = {
    h = "═",
    v = "║",
    tl = "╔",
    tr = "╗",
    bl = "╚",
    br = "╝",
    pre = "╡",
    post = "╞",
  },
  --- Copy a box format.
  -- @function box_fmt.copy
  -- @tparam table default the default format to copy
  -- @treturn table a copy of the default format provided
  -- @within lines
  -- @usage -- create new format with spaces around the title
  -- local fmt = t.box_fmt.copy(t.box_fmt.single)
  -- fmt.pre = fmt.pre .. " "
  -- fmt.post = " " .. fmt.post
  copy = function(default)
    return {
      h = default.h,
      v = default.v,
      tl = default.tl,
      tr = default.tr,
      bl = default.bl,
      br = default.br,
      pre = default.pre,
      post = default.post,
    }
  end,
}, {
  __index = function(_, k)
    error("invalid box format: " .. tostring(k))
  end,
})

--- Creates a sequence to draw a box, without writing it to the terminal.
-- The box is drawn starting from the top-left corner at the current cursor position,
-- after drawing the cursor will be in the same position.
-- @tparam number height the height of the box in rows
-- @tparam number width the width of the box in columns
-- @tparam[opt="single"] table format the format for the box, with keys:
-- @tparam[opt=" "] string format.h the horizontal line character
-- @tparam[opt=""] string format.v the vertical line character
-- @tparam[opt=""] string format.tl the top left corner character
-- @tparam[opt=""] string format.tr the top right corner character
-- @tparam[opt=""] string format.bl the bottom left corner character
-- @tparam[opt=""] string format.br the bottom right corner character
-- @tparam[opt=""] string format.pre the title-prefix character(s)
-- @tparam[opt=""] string format.post the left-postfix character(s)
-- @tparam bool clear whether to clear the box contents
-- @tparam[opt=""] string title the title to draw
-- @tparam[opt] boolean lastcolumn whether to draw the last column of the terminal
-- @treturn string ansi sequence to write to the terminal
-- @within lines
function M.boxs(height, width, format, clear, title, lastcolumn)
  format = format or M.box_fmt.single
  local v_w = sys.utf8swidth(format.v or "")
  local tl_w = sys.utf8swidth(format.tl or "")
  local tr_w = sys.utf8swidth(format.tr or "")
  local bl_w = sys.utf8swidth(format.bl or "")
  local br_w = sys.utf8swidth(format.br or "")
  local v_line_l = M.line_verticals(height - 2, format.v)
  local v_line_r = v_line_l
  if lastcolumn then
    v_line_r = M.line_verticals(height - 2, format.v, lastcolumn)
  end
  lastcolumn = lastcolumn and 1 or 0

  local r = {
    -- draw top
    format.tl or "",
    M.line_titles(width - tl_w - tr_w, title, format.h or " ", format.pre or "", format.post or ""),
    format.tr or "",
    -- position to draw right, and draw it
    M.cursor_moves(1, -v_w + lastcolumn),
    v_line_r,
    -- position back to top left, and draw left
    M.cursor_moves(-height + 3, -width + lastcolumn),
    v_line_l,
    -- draw bottom
    M.cursor_moves(1, -1),
    format.bl or "",
    M.line_horizontals(width - bl_w - br_w, format.h or " "),
    format.br or "",
    -- return to top left
    M.cursor_moves(-height + 1, -width + lastcolumn),
  }
  if clear then
    local l = #r
    r[l+1] = M.cursor_moves(1, v_w)
    r[l+2] = M.clear_boxs(height - 2, width - 2 * v_w)
    r[l+3] = M.cursor_moves(-1, -v_w)
  end
  return table.concat(r)
end

--- Draws a box and writes it to the terminal (+flush).
-- @tparam number height the height of the box in rows
-- @tparam number width the width of the box in columns
-- @tparam table format the format for the box, see `boxs` for details.
-- @tparam bool clear whether to clear the box contents
-- @tparam[opt=""] string title the title to draw
-- @tparam[opt] boolean lastcolumn whether to draw the last column of the terminal
-- @return true
-- @within lines
function M.box(height, width, format, clear, title, lastcolumn)
  t:write(M.boxs(height, width, format, clear, title, lastcolumn))
  t:flush()
  return true
end


--=============================================================================
-- terminal initialization and exit
--=============================================================================
--- Initialization.
-- Initialization and termination.
-- @section initialization

do
  local termbackup
  local reset = "\27[0m"
  local savescreen = "\27[?47h"
  local restorescreen = "\27[?47l"


  --- Initializes the terminal for use.
  -- Makes a backup of the current terminal settings.
  -- Sets input to non-blocking, disables canonical mode and echo, and enables ANSI processing.
  -- @tparam[opt=false] boolean displaybackup if true, the current terminal display is also
  -- backed up (by switching to the alternate screen buffer).
  -- @tparam[opt=io.stdout] filehandle filehandle the stream to use for output
  -- @return true
  -- @within initialization
  function M.initialize(displaybackup, filehandle)
    assert(not termbackup, "terminal already initialized")

    filehandle = filehandle or io.stdout
    assert(io.type(filehandle) == 'file', "invalid file handle")
    t = filehandle

    termbackup = sys.termbackup()
    if displaybackup then
      t:write(savescreen)
      termbackup.displaybackup = true
    end

    -- set Windows output to UTF-8
    sys.setconsoleoutputcp(65001)

    -- setup Windows console to handle ANSI processing, disable echo and line input (canonical mode)
    sys.setconsoleflags(io.stdout, sys.getconsoleflags(io.stdout) + sys.COF_VIRTUAL_TERMINAL_PROCESSING)
    sys.setconsoleflags(io.stdin, sys.getconsoleflags(io.stdin) + sys.CIF_VIRTUAL_TERMINAL_INPUT - sys.CIF_ECHO_INPUT - sys.CIF_LINE_INPUT)

    -- setup Posix terminal to disable canonical mode and echo
    sys.tcsetattr(io.stdin, sys.TCSANOW, {
      lflag = sys.tcgetattr(io.stdin).lflag - sys.L_ICANON - sys.L_ECHO,
    })
    -- setup stdin to non-blocking mode
    sys.setnonblock(io.stdin, true)

    -- set up keyboard buffering for cursor pos reading
    sys.readansi = new_readansi

    return true
  end

  --- Shuts down the terminal, restoring the terminal settings.
  -- @return true
  -- @within initialization
function M.shutdown()
    assert(termbackup, "terminal not initialized")
    if termbackup.displaybackup then
      t:write(restorescreen)
      t:flush()
    end
    t:write(reset)
    t:flush()

    sys.termrestore(termbackup)

    t = nil
    termbackup = nil
    sys.readansi = old_readansi

    return true
  end
end



return M
