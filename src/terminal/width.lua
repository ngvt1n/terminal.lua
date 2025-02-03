--- Module to check and validate character display widths.

local M = {}
local char_widths = {} -- registry to keep track of already tested widths
local t = require "terminal"
local sys = require "system"


-- Test the width of a character by writing it to the terminal and measure cursor displacement.
-- No colors or cursor positioning/moving back is involved.
local function test_width_by_writing(char)
  local _, start_column = t.cursor_get()
  t.write(char)
  local _, end_column = t.cursor_get()
  if end_column < start_column then
    -- cursor wrapped to next line
    local _, cols = t.termsize()
    end_column = end_column + cols
  end
  local w = end_column - start_column
  char_widths[char] = w
  return w
end

--- Write a character and report its width in columns.
-- Writes a character to the terminal and returns its width in columns.
-- The width measured is recorded in the cache, so subsequent calls with the
-- same character will be faster.
-- @tparam string char the character to write, a single utf8 character
-- @treturn number the width of the character in columns
function M.write_cwidth(char)
  local w = char_widths[char]
  if w then
    -- we have a cached width
    t.write(char)
    return w
  end

  return test_width_by_writing(char)
end

--- Write a string and report its width in columns.
-- Writes a string to the terminal and returns its width in columns.
-- The width measured for each character is recorded in the cache.
-- @tparam string str the string to write
-- @treturn number the width of the string in columns
function M.write_swidth(str)
  local w = 0
  for pos, char in utf8.codes(str) do
    w = w + M.write_cwidth(utf8.char(char))
  end
  return w
end

--- Reports the width of a character in columns.
-- Same as `write_cwidth`, but writes it "invisible" (brightness = 0), so it
-- does not show. The cursor is returned to its original position.
-- It will however overwrite existing content, and might locally
-- change the background color. So set that accordingly to avoid unwanted effects.
-- The width measured is recorded in the cache, so subsequent calls with the
-- same character will be faster.
-- @tparam string char the character to write, a single utf8 character
-- @treturn number the width of the character in columns
function M.get_cwidth(char)
  local w = char_widths[char]
  if w then
    return w
  end

  t.textpush({ brightness = 0 })
  local w = test_width_by_writing(char)
  t.textpop()
  t.cursor_left(w)
  return w
end

--- Reports the width of a string in columns. Each character will be tested and
-- the width recorded in the cache. This can be used to pre-load the cache with
-- the widths of a string, without actually showing it on the terminal.
-- Same as `write_swidth`, but uses `get_cwidth` so it will not really show on
-- the terminal. The cursor is returned to its original position.
function M.get_swidth(str)
  local w = 0
  for pos, codepoint in utf8.codes(str) do
    w = w + M.get_cwidth(utf8.char(codepoint))
  end
  return w
end

--- Returns the width of a character in columns, matches `sys.utf8cwidth`.
-- This will check the cache of recorded widths first, and if not found,
-- use `sys.utf8cwidth` to determine the width.
-- @tparam string char the character to check
-- @treturn number the width of the first character in columns
function M.utf8cwidth(char)
  char = utf8.char(utf8.codepoint(char))
  return char_widths[char] or sys.utf8cwidth(char)
end

--- Returns the width of a string in columns, matches `sys.utf8swidth`.
-- It will use `utf8cwidth` to determine the width of each character, and as such
-- will use the cached widths created with `written_width` and `get_width`.
-- @tparam string str the string to check
-- @treturn number the width of the string in columns
function M.utf8swidth(str)
  local w = 0
  for pos, char in utf8.codes(str) do
    w = w + M.utf8cwidth(char)
  end
  return w
end

return M
