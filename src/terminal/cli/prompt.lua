--- Prompt input for CLI tools.
--
-- This module provides a simple way to read line input from the terminal.
-- Features: Prompt, UTF8 support, async input, (to be added: secrets, scrolling and wrapping)
-- The user can confirm their choices by pressing <Enter>
-- Cancel their choices by pressing <Esc>
-- @classmod cli.Prompt
-- @usage
-- local prompt = Prompt {
--     prompt = "Enter something: ",
--     value = "Hello, 你-好 World 🚀!",
--     max_length = 62,
--     overflow = "wrap" -- or "scroll"
--     position = 2,
--     fsleep = sys.sleep,
-- }
-- local result, exitkey = pr:run()

-- todo: use the new keymap -- check cli.select

local t = require("terminal")
local sys = require("system")
local utils = require("terminal.utils")
local width = require("terminal.text.width")
local output = require("terminal.output")
local UTF8EditLine = require("terminal.text.utf8edit").UTF8EditLine

-- Key bindings
local keys = t.input.keymap.get_keys()
local keymap = t.input.keymap.get_keymap({
  ctrl_c = keys.escape, -- Ctrl+C
  esc = keys.escape,    -- Esc
})

local Prompt = utils.class()

function Prompt:init(opts)
  self.value = UTF8EditLine(opts.value or "")
  self.prompt = opts.prompt or ""        -- the prompt to display
  self.max_length = opts.max_length      -- the maximum length of the input
  self.drawn_before = false              -- if the prompt has been drawn
  self.fsleep = opts.fsleep or sys.sleep -- the sleep function to use
end

function Prompt:draw(redraw)
  if redraw or not self.prompt_ready then
    -- we are at start of prompt
    self.prompt_ready = true
    t.cursor.position.column(1)
    output.write(tostring(self.prompt))
  else
    -- we are at current cursor position, move to start of prompt
    t.cursor.position.column(width.utf8swidth(self.prompt) + 1)
  end
  -- write prompt & value
  local value = tostring(self.value)
  output.write(value)
  -- clear remainder of input size
  output.write(string.rep(" ", self.max_length - self.value.olen))
  -- move to cursor position
  t.cursor.position.column(width.utf8swidth(self.prompt) + self.value.ocursor)
  output.flush()
end

-- Read and normalize key input
function Prompt:readKey()
  local key = t.input.readansi(math.huge, self.fsleep)
  return key, keymap[key] or key
end

--- Processes key input async
-- This function listens for key events and processes them.
-- If an exit key is pressed, it yields the input value and the exit key.
-- @event key Triggered when a key is pressed.
-- @tparam string key The key that was pressed.
-- @tparam string keytype The type of the key (e.g., "ansi", "control").
function Prompt:handleInput()
  while true do
    local _, keyname = self:readKey()
    if keyname then
      local editing_handler = self.value[keyname]
      if editing_handler then
        editing_handler(self.value)
        self:draw()
      elseif keyname == keys.escape and self.cancellable then
        return "cancelled"
      elseif keyname == keys.enter then
        return "returned"
      elseif pcall(function() return keys[keyname] end) then -- hacky way to check non-printing characters
        t.bell()
      elseif self.value.ilen >= self.max_length then
        -- if control character
        -- or if printing character but the length limit is reached :P
        t.bell()
      else -- add the character at the current cursor
        self.value:add(keyname)
        self:draw()
      end
    end
  end
end

--- Starts the prompt input loop.
-- This function initializes the input loop for the readline instance.
-- It uses a coroutine to process key input until an exit key is pressed.
-- @tparam boolean redraw Whether to redraw the prompt initially.
-- @treturn string The final input value entered by the user.
-- @treturn string The exit key that terminated the input loop.
function Prompt:run()
  local revert
  if not t.ready() then
    t.initialize()
    revert = true
  end

  self:draw()

  local status = self:handleInput()

  output.print() -- move to new line (we're still on the 'press any key' line)

  if revert then t.shutdown() end

  if status == "returned" then
    return tostring(self.value), status
  else
    return nil, status
  end
end

return Prompt
