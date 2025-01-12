-- This example demonstrates the use of the text-attribute stack, and how to
-- use it to manage text attributes in a more structured way.

local sys = require("system")
local t = require("terminal")


local SPINNER = { [0] = " ", "|", "/", "-", "\\" }
local PLEASE_WAIT = { [0] = "Done!         ", "Please wait   ", "Please wait.  ", "Please wait.. ", "Please wait..." }

--- create a progress spinner
-- @tparam table sequence a table of strings to display, one at a time, overwriting the previous one. Index 0 is the "done" message.
-- @tparam number stepsize the time in seconds between each step (before printing the next string from the sequence)
-- @tparam table textattr a table of text attributes to apply to the text (using the stack), or nil to not change the attributes.
-- @treturn function a stepper function that should be called in a loop to update the spinner.
local function spinner(sequence, stepsize, textattr)
  -- copy sequence to include cursor movement to return to start position.
  -- include character display width check using LuaSystem
  do
    local seq = {}
    for i=0, #sequence do
      local s = sequence[i] or ""
      seq[i] = s .. t.cursor_lefts(sys.utf8swidth(s))
    end
    sequence = seq
  end
  local step = 0
  local next_step = sys.gettime()

  local write_one = function(done)
    if done then
      step = -1 -- will force to print element 0, the done message
    end
    step = step + 1
    if step > #sequence then
      step = 1
    end
    if textattr then
      t.textpush(textattr)
      t.write(sequence[step])
      t.textpop()
    else
      t.write(sequence[step])
    end
  end

  local stepper = function(done)
    if sys.gettime() >= next_step or done then
      write_one(done)
      next_step = sys.gettime() + stepsize
    end
  end

  return stepper
end

-- initialize terminal
t.initialize()

-- create spinner functions
local spinner1 = spinner(SPINNER, 0.2, {fg = "black", bg = "red", brightness = "normal"})
local spinner2 = spinner(PLEASE_WAIT, 0.2)

-- print 2 empty lines to create room for the spinners
t.print()
t.print()
t.write("Press any key to stop the spinners...")
t.visible(false)
t.cursor_tocolumn(1)
t.cursor_up(2)

while true do
  spinner1()
  t.cursor_down(1)
  spinner2()
  t.cursor_up(1)
  t.flush()
  if sys.readansi(0.1) then
    break
  end
end

spinner1(true)
t.cursor_down(1)
spinner2(true)
t.cursor_down(1)  -- on the 'press any key...' line now
t.visible(true)
t.print() -- move to new line

-- restore all settings
t.shutdown()
