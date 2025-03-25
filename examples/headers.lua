local sys = require("system")
local t = require("terminal")

-- Keys
local key_names = {
  ["\27[A"] = "up",
  ["\27[B"] = "down",
  ["\27[C"] = "right",
  ["\27[D"] = "left",
  ["\127"] = "backspace",
  ["\8"] = "backspace",
  ["\27[3~"] = "delete",
  ["\27[H"] = "home",
  ["\27[F"] = "end",
  ["\27"] = "escape",
  ["\9"] = "tab",
  ["\27[Z"] = "shift-tab",
  ["\r"] = "enter",
  ["\n"] = "enter",
  ["f10"] = "f10",
  ["\6"] = "ctrl-f",
  ["\2"] = "ctrl-b",
}
-- Utility function to read a key from terminal input
local function readKey()
  local key = t.input.readansi(1) -- Read a single key
  return key, key_names[key] or key -- Return raw key and mapped name
end

-- Utility function to draw components using the stack style
local function withStyle(style, callback)
  t.text.stack.push(style)
  callback()
  t.text.stack.pop()
end

-- Colors
local colors = {
  "black", "red", "green", "yellow", "blue", "magenta", "cyan", "white"
}
local rcolors = {}
for index, color in ipairs(colors) do
  rcolors[color] = index
end

-- TUI classes
local TerminalUIApp = {}
local Bar = {}
local TextArea = {}

-- Constructor: TerminalUIApp: Full-screen TUI App
function TerminalUIApp:new(options)
  options = options or {}
  local instance = {
    appName = options.appName or "Terminal Application",
    header = options.header or Bar:new(),
    footer = options.footer or Bar:new(),
    content = options.content or TextArea:new(),
    linesWritten = 0,
  }
  setmetatable(instance, { __index = self })
  -- circular reference between components and parent tui app
  instance.content.parent_app = instance.content.parent_app or instance
  instance.header.parent_app = instance.header.parent_app or instance
  instance.footer.parent_app = instance.footer.parent_app or instance
  return instance
end

function TerminalUIApp:run()
  t.initialize {
    displaybackup = true,
    filehandle = io.stdout,
  }
  t.clear.screen()

  self.content:initializeContent()
  self.content:handleInput()

  t.shutdown()
  print("Thank you for using MyTerminal! You wrote " .. self.linesWritten .. " lines.")
end

function TerminalUIApp:refreshDisplay()
  local savedY, savedX = self.content.cursorY, self.content.cursorX
  local rows, _ = sys.termsize()

  self.header:draw(1)
  self.footer:draw(rows)

  self.content:updateCursor(savedY, savedX)
end

-- Constructor: TextArea: main content area
function TextArea:new(options)
  options = options or {}
  local instance = {
    parent_app = options.parent_app,
    cursorY = 2,
    cursorX = 2,
    style = options.style or { fg = "green", bg = "black", brightness = "normal" },
  }
  instance.currentFgColorIndex = instance.style.fg and rcolors[instance.style.fg] or 3
  instance.currentBgColorIndex = instance.style.bg and rcolors[instance.style.bg] or 1
  setmetatable(instance, { __index = self })
  return instance
end

-- cycle colors
function TextArea:cycleColor(isBackground)
  if isBackground then
    self.currentBgColorIndex = (self.currentBgColorIndex % #colors) + 1
    self.style.bg = colors[self.currentBgColorIndex]
  else
    self.currentFgColorIndex = (self.currentFgColorIndex % #colors) + 1
    self.style.fg = colors[self.currentFgColorIndex]
  end

  t.text.attrs(self.style)
  self.parent_app:refreshDisplay()
end

function TextArea:getCurrentColorInfo()
  return string.format("FG: %s, BG: %s", colors[self.currentFgColorIndex], colors[self.currentBgColorIndex])
end

function TextArea:updateCursor(y, x)
  self.cursorY = y
  self.cursorX = x
  t.cursor.position.set(y, x)
end

function TextArea:initializeContent()
  local rows, cols = sys.termsize()

  t.text.attrs(self.style)

  for i = 2, rows - 1 do
    t.cursor.position.set(i, 1)
    t.output.write(string.rep(" ", cols))
  end

  self:updateCursor(2, 2)
end

function TextArea:handleInput()
  local rows, cols = sys.termsize()

  self.parent_app:refreshDisplay()

  while true do
    t.cursor.position.set(self.cursorY, self.cursorX)

    local rawKey, keyName = readKey()

    if rawKey then
      if keyName == "escape" or keyName == "f10" then
        break
      elseif keyName == "ctrl-f" then
        self:cycleColor(false)
      elseif keyName == "ctrl-b" then
        self:cycleColor(true)
      elseif keyName == "enter" then
        self.parent_app.linesWritten = self.parent_app.linesWritten + 1

        if self.cursorY < rows - 1 then
          self:updateCursor(self.cursorY + 1, 2)
        else
          self:updateCursor(self.cursorY, 2)
          t.output.write(string.rep(" ", cols))
        end
        self.parent_app:refreshDisplay()
      elseif keyName == "backspace" then
        if self.cursorX > 2 then
          self:updateCursor(self.cursorY, self.cursorX - 1)
          t.output.write(" ")
          self:updateCursor(self.cursorY, self.cursorX)
        elseif self.cursorY > 2 then
          self:updateCursor(self.cursorY - 1, cols - 2)
        end
      elseif keyName == "up" and self.cursorY > 2 then
        self:updateCursor(self.cursorY - 1, self.cursorX)
      elseif keyName == "down" and self.cursorY < rows - 1 then
        self:updateCursor(self.cursorY + 1, self.cursorX)
      elseif keyName == "right" and self.cursorX < cols then
        self:updateCursor(self.cursorY, self.cursorX + 1)
      elseif keyName == "left" and self.cursorX > 2 then
        self:updateCursor(self.cursorY, self.cursorX - 1)
      elseif keyName == "home" then
        self:updateCursor(self.cursorY, 2)
      elseif keyName == "end" then
        self:updateCursor(self.cursorY, cols - 1)
      elseif #rawKey == 1 then
        t.output.write(rawKey)
        self:updateCursor(self.cursorY, self.cursorX + 1)
      end
    end

    t.output.flush()
  end
end

-- Constructor: Bar: horizontal bar in the screen
function Bar:new(options)
  options = options or {}
  local instance = {
    style = options.style or { fg = "white", bg = "blue", brightness = "bright" },
    content_fn = options.content_fn,
  }
  setmetatable(instance, { __index = self })
  return instance
end

function Bar:draw(row)
  local _, cols = sys.termsize()

  withStyle(self.style, function()
    t.cursor.position.set(row, 1)
    t.output.write(string.rep(" ", cols))

    if self.content_fn then
      self:content_fn(row, cols)
    end
  end)
end

-- Initiate two bars of Bar for header and footer
local myHeader = Bar:new {
  style = { fg = "white", bg = "blue", brightness = "bright" },
  content_fn = function(self, _, cols)
    local currentTime = os.date("%H:%M:%S")
    local cursorText = string.format("Pos: %d,%d", self.parent_app.content.cursorY, self.parent_app.content.cursorX)
    t.cursor.position.set(1, 2)
    t.output.write(self.parent_app.appName)

    local clockPos = math.floor(cols / 4)
    t.cursor.position.set(1, clockPos)
    t.output.write(currentTime)

    local cursorPos = math.floor(cols / 2) + 5
    t.cursor.position.set(1, cursorPos)
    t.output.write(cursorText)

    local colorText = "Color: " .. self.parent_app.content:getCurrentColorInfo()
    t.cursor.position.set(1, cols - #colorText - 1)
    t.output.write(colorText)
  end,
}
local myFooter = Bar:new {
  style = { fg = "white", bg = "blue", brightness = "bright" },
  content_fn = function(self, _, cols)
    local rows, _ = sys.termsize()
    local lineText = "Lines: " .. self.parent_app.linesWritten
    local helpText = "Ctrl+F: Change FG | Ctrl+B: Change BG | ESC: Exit"

    t.cursor.position.set(rows, 2)
    t.output.write(lineText)

    t.cursor.position.set(rows, cols - #helpText - 1)
    t.output.write(helpText)
  end,
}

local myTerminal = TerminalUIApp:new {
  appName = "The best terminal ever",
  header = myHeader,
  footer = myFooter,
}

myTerminal:run()
