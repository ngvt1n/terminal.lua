# 2. TODO items

Terminals are hard to interact with. Sending commands is easy, but querying status
is all but impossible. This means that the state set (e.g. what is currently displayed at pos x,y, or the foreground color currently set) is
global, and non-queryable. In an async application, the global state becomes even
harder to manage.

# 2.1 Global state

Most state is non-queryable. Cursor position being an exception.
This means an application needs to keep track. Some options:

* do nothing, let the user keep track of it as necessary. Since is easy for sync behavior
  but with async behaviour it gets more complicated.

* always reset state. This is what the ansicolors module does; everything you
  write to the screen sets its own colors etc, and is followed by a reset sequence.
  In async enviornments this is tedious, since there might be race conditions.

* This terminal.lua implements stacks. Where state is pushed on a stack, text written
  and then popped, restoring the last state. Espcially async this works nicely.
  This works best if the entire application uses the stacks, but at the same time
  calling out to foreign code is easily handled by reapplying what is on the stack

are ther alternative solutions? what are they, and how do they compare??

# 2.2 querying the terminal

querying the terminal is done by writing a command code, and then reading the response
from the input buffer. However the data is appended to the STDIN buffer if it wasn't empty
to begin with. This means that when reading, any data that is not the response needs
to be buffered Lua side to be consumed later.

This means that input handling must be done in the library, since the default
io.read functions etc wouldn't be able to read from the buffered data, they can only read
from STDIN.

terminal.lua currently patches `system.readansi` to inject this buffer. This works but
is ugly and doesn't adhere to 'mechanisms over policies'. So the lib should probably
just provide its own `readansi` and leave patching to the user.

# 2.2.1 thread safety

a related problem to the reading+buffering from stdin issue is async safety.

luasystem implements `readansi` by sleeping whilst there is no data. And it mentions
that the `system.sleep` function should be patched by a yielding, coroutine aware version
if async behvior is needed.

This works nicely, except when querying the terminal. Because between sending the command
and reading its response, we do not want an implicit yield to occur (and other threads running).
So in those cases there must be a 'blocking' sleep, otherwise if multiple threads
query the terminal at the same time, responses my be mixed.

This might require a change to luasystem. for example by passing in the sleep method to use.

# 2.3 terminal output buffers

The output written to the terminal is also buffered. And especially on MacOS this is known to
cause issues. If too much data is written at once, then the data is truncated and will
not be written to the terminal.

terminal.lua handles this by providing its own `write` and `print` functions that write
a limited number of bytes before doing a very short sleep and continuing.

2 things to take:

1. is there a better way to prevent data loss?
2. the sleep used in the output functions MUST be a blocking sleep, since a yielding
   sleep might cause race-conditions again

# 2.4 character width

luasystem provides an implementation of wcwidth to check character width. However that
doesn't cover all scenarios. Some characters are ambiguous and have 1 column width in
western displays, but 2 columns on east asian displays, such that they are better aligned
on the display.

So far the only way to detect those widths is by writing them to the terminal, and record
cursor displacement.
