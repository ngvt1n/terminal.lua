--- A module for progress updating.

local sys = require("system")
local t = require("terminal")

local M = {}


--- table with predefined sprites for progress spinners.
M.sprites = setmetatable({
  bar_vertical = { [0] = " ", "▁", "▂", "▃", "▄", "▅", "▆", "▇", "█", "▇", "▆", "▅", "▄", "▃", "▂", "▁", " " },
  bar_horizontal = { [0] = " ", "▏", "▎", "▍", "▌", "▋", "▊", "▉", "█", "▉", "▊", "▋", "▌", "▍", "▎", "▏", " " },
  square_rotate = { [0] = " ", "▖", "▘", "▝", "▗" },
  moon = { [0] = " ", "🌑", "🌒", "🌓", "🌔", "🌕", "🌖", "🌗", "🌘" },
  dot_expanding = { [0] = " ", ".", "o", "O", "o" },
  dot_vertical = { [0] = " ", "⢀", "⠠", "⠐", "⠈", "⠐", "⠠" },
  dot1_snake = { [0] = " ", "⠁", "⠈", "⠐", "⠠", "⢀", "⡀", "⠄", "⠂" },
  dot2_snake = { [0] = " ", "⠃", "⠉", "⠘", "⠰", "⢠", "⣀", "⡄", "⠆" },
  dot3_snake = { [0] = " ", "⡆", "⠇", "⠋", "⠙", "⠸", "⢰", "⣠", "⣄" },
  dot4_snake = { [0] = " ", "⡇", "⠏", "⠛", "⠹", "⢸", "⣰", "⣤", "⣆"},
  block_pulsing = { [0] = " ", " ", "░", "▒", "▓", "█", "▓", "▒", "░" },
  bar_rotating = { [0] = " ", "┤", "┘", "┴", "└", "├", "┌", "┬", "┐" },
  spinner = { [0] = " ", "|", "/", "-", "\\" },
  dot_horizontal = { [0] = "   ", "   ", ".  ", ".. ", "..." },
}, {
  __index = function(self, key)
    local lst = {}
    for name in pairs(self) do
      lst[#lst+1] = name
    end
    error("Unknown spinner sprite: '" .. key .. "'. Available sprites: " .. table.concat(lst, ", "), 2)
  end
})



--- Create a progress spinner.
-- The returned spinner function can be called as often as needed to update the spinner. It will only update after
-- the `stepsize` has passed since the last update. So try to call it at least every `stepsize` seconds, or more often.
-- If `row` and `col` are given then terminal memory is used to (re)store the cursor position. If they are not given
-- then the spinner will be printed at the current cursor position, and the cursor will return to the same position
-- after each update.
-- @tparam table opts a table of options;
-- @tparam table opts.sprites a table of strings to display, one at a time, overwriting the previous one. Index 0 is the "done" message.
-- See `sprites` for a table of predefined sprites.
-- @tparam[opt=0.2] number opts.stepsize the time in seconds between each step (before printing the next string from the sequence)
-- @tparam textattr textattr a table of text attributes to apply to the text (using the stack), or nil to not change the attributes.
-- @tparam[opt] textattr done_textattr a table of text attributes to apply to the "done" message, or nil to not change the attributes.
-- @tparam[opt] string done_sprite the sprite to display when the spinner is done. This overrides `sprites[0]` if provided.
-- @tparam[opt] number row the row to print the spinner (required if `col` is provided)
-- @tparam[opt] number col the column to print the spinner (required if `row` is provided)
-- @treturn function a stepper function that should be called in a loop to update the spinner. Signature: `nil = stepper(done)` where
-- `done` is a boolean indicating that the spinner should print the "done" message.
function M.spinner(opts)
  opts = opts or {}
  assert(opts.sprites and #opts.sprites > 0, "sprites must be provided")
  local stepsize = opts.stepsize or 0.2
  local textattr = opts.textattr
  local row = opts.row
  local col = opts.col
  if col or row then
    assert(col and row, "both row and col must be provided, or neither")
  end

  -- copy sequence to include cursor movement to return to start position.
  -- include character display width check using LuaSystem
  local steps do
    local pos_set, pos_restore
    if row then
      pos_set = t.cursor_saves() .. t.cursor_sets(row, col)
      pos_restore = t.cursor_restores()
    end

    local attr_push, attr_pop -- both will remain nil, if no text attr set
    if textattr then
      attr_push = function() return t.textpushs(textattr) end
      attr_pop = t.textpops
    end
    local attr_push_done = attr_push
    if opts.done_textattr then
      attr_push_done = function() return t.textpushs(opts.done_textattr) end
    end

    steps = {}
    for i=0, #opts.sprites do
      local s = opts.sprites[i] or ""
      if i == 0 then
        s = opts.done_sprite or s
      end
      local sequence = t.sequence()
      sequence[#sequence+1] = pos_set
      sequence[#sequence+1] = (i == 0 and attr_push_done) or attr_push or nil
      sequence[#sequence+1] = s .. t.cursor_lefts(sys.utf8swidth(s))
      sequence[#sequence+1] = attr_pop
      sequence[#sequence+1] = pos_restore
      steps[i] = sequence
    end
  end
  local step = 0
  local next_step = sys.gettime()


  return function(done)
    if sys.gettime() >= next_step or done then
      if done then
        step = 0 -- will force to print element 0, the done message
      else
        next_step = sys.gettime() + stepsize
        step = step + 1
        if step > #steps then
          step = 1
        end
      end

      t.write(steps[step])
    end
  end
end

return M
