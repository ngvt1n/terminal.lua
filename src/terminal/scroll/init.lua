--- Terminal scroll module.
-- Provides utilities to handle scroll-regions and scrolling in terminals.
-- @module terminal.scroll
local M = {}
package.loaded["terminal.scroll"] = M -- Register the module early to avoid circular dependencies

local sys = require "system"
local output = require("terminal.output")
local utils = require("terminal.utils")



--- Function to return the default scroll reset sequence
-- @treturn string The ANSI sequence for resetting the scroll region.
-- @within Sequences
function M.reset_seq()
  return "\27[r"
end



--- Applies the default scroll reset sequence by writing it to the terminal.
-- @treturn true Always returns true after applying.
function M.reset()
  output.write(M.reset_seq())
  return true
end



--- Creates an ANSI sequence to set the scroll region without writing to the terminal.
-- Negative indices are supported, counting from the bottom of the screen.
-- For example, `-1` refers to the last row, `-2` refers to the second-to-last row, etc.
-- @tparam number start_row The first row of the scroll region. Negative values are resolved
-- from the bottom of the screen, such that `-1` is the last row.
-- @tparam number end_row The last row of the scroll region. Negative values are resolved
-- from the bottom of the screen, such that `-1` is the last row.
-- @treturn string The ANSI sequence for setting the scroll region.
-- @within Sequences
function M.set_seq(start_row, end_row)
  -- Resolve negative indices
  local rows, _ = sys.termsize()
  start_row = utils.resolve_index(start_row, rows, 1)
  end_row = utils.resolve_index(end_row, rows, start_row)
  return "\27[" .. tostring(start_row) .. ";" .. tostring(end_row) .. "r"
end



--- Sets the scroll region and writes the ANSI sequence to the terminal.
-- Negative indices are supported, counting from the bottom of the screen.
-- For example, `-1` refers to the last row, `-2` refers to the second-to-last row, etc.
-- @tparam number start_row The first row of the scroll region (can be negative).
-- @tparam number end_row The last row of the scroll region (can be negative).
-- @treturn true Always returns true after setting the scroll region.
function M.set(start_row, end_row)
  output.write(M.set_seq(start_row, end_row))
  return true
end



--- Creates an ANSI sequence to scroll up by a specified number of lines.
-- @tparam[opt=1] number n The number of lines to scroll up.
-- @treturn string The ANSI sequence for scrolling up.
-- @within Sequences
function M.up_seq(n)
  n = n or 1
  return "\27[" .. tostring(n) .. "S"
end



--- Scrolls up by a specified number of lines and writes the sequence to the terminal.
-- @tparam[opt=1] number n The number of lines to scroll up.
-- @treturn true Always returns true after scrolling.
function M.up(n)
  output.write(M.up_seq(n))
  return true
end



--- Creates an ANSI sequence to scroll down by a specified number of lines.
-- @tparam[opt=1] number n The number of lines to scroll down.
-- @treturn string The ANSI sequence for scrolling down.
-- @within Sequences
function M.down_seq(n)
  n = n or 1
  return "\27[" .. tostring(n) .. "T"
end



--- Scrolls down by a specified number of lines and writes the sequence to the terminal.
-- @tparam[opt=1] number n The number of lines to scroll down.
-- @treturn true Always returns true after scrolling.
function M.down(n)
  output.write(M.down_seq(n))
  return true
end



--- Creates an ANSI sequence to scroll vertically by a specified number of lines.
-- Positive values scroll down, negative values scroll up.
-- @tparam number n The number of lines to scroll (positive for down, negative for up).
-- @treturn string The ANSI sequence for vertical scrolling.
-- @within Sequences
function M.vertical_seq(n)
  if n == 0 or n == nil then
    return ""
  end
  return "\27[" .. (n < 0 and (tostring(-n) .. "S") or (tostring(n) .. "T"))
end



--- Scrolls vertically by a specified number of lines and writes the sequence to the terminal.
-- @tparam number n The number of lines to scroll (positive for down, negative for up).
-- @treturn true Always returns true after scrolling.
function M.vertical(n)
  output.write(M.vertical_seq(n))
  return true
end



-- Load stack module **after registering everything** since it will call into
-- this module.
M.stack = require("terminal.scroll.stack")



return M
