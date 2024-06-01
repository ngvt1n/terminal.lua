#!/usr/bin/env lua

--- CLI application.
-- Description goes here.
-- @script terminal
-- @usage
-- # start the application from a shell
-- terminal --some --options=here

print("Welcome to the terminal CLI, echoing arguments:")
for i, val in ipairs(arg) do
  print(i .. ":", val)
end
