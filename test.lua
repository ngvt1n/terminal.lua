-- ensure we use the local dev files
package.path = "./src/?.lua;./src/?/init.lua;" .. package.path
local sys = require("system")
local t = require("terminal")

local function testscreen()
  -- build test setup
  t.clear()
  local c, r = sys.termsize()

  local row = {}
  for i = 1, c do
    row[i] = tostring(i % 10)
  end
  row = table.concat(row)

  t.write("\27[90m")  -- FG dark-grey
  -- t.write("\27[38;5;233m")  -- FG dark-grey
  for i = 1, r do
    t.cursor_set(i, 1)
    t.write(row)
  end
  t.cursor_set(1, 1)
  t.write("\27[39m")  -- FG reset
end




local function main()
  testscreen()
  t.shape("block_blink")


  t.cursor_set(33, 144)
  t.box(10, 20, t.box_fmt.double, true, "hello world", true)
  t.cursor_set(10, 10)

  t.flush()
  sys.sleep(5)
end



t.initialize(true, io.stdout)
local ok, err = xpcall(main, debug.traceback)
t.shutdown()

if not ok then
  print(err)
end
-- print("press any key to exit...")
-- sys.readansi(math.huge)
print("done!")
os.exit(ok and 0 or 1)
