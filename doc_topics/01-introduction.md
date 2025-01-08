# 1. Introduction

Yet another terminal library, why? Becasue it adds a couple of things not found with other libraries:

- Also works on Windows (since it builds on top of `luasystem`)
- Has `stacks` to track settings so it becomes possible to revert to previous settings, even if a piece of code has no knowledge about those settings.
- Remains Lua only, to not fall back to a full curses type implementation

## 1.1 Basic design

There are 2 major concepts implemented in this library:

- [functions vs strings](#12-functions-vs-strings)
- [stacks](#13-stacks)

And then there is the design of the [text attributes](#14-text-attributes)

## 1.2 functions vs strings

Almost every function in this library also has a string-counterpart. That would be the same function, but with an extra "s" appended to its name. For example;

- `clear_end()` and `clear_ends()`
- `shape(<cursor-shape>)` and `shapes(<cursor-shape>)`

The difference being that the former will immediately print the sequence. Where the latter only returns the sequence as a string, and leaves writing to the user.

Hence these 2 examples are identical in functionality:

    local t = require "terminal"

    -- directly write
    t.shape("block_blink")

    -- manually write
    t.write(t.shapes("block_blink"))
    t.flush()

In simple cases the regular function will do. However when drawing more complex items on a terminal screen, combining multiple write actions into a single one, can reduce flicker and improve performance.

Here's an example that draws a vertical bar (3 rows high), and clears the lines:

    t.write(
      t.cursor_tocolumns(1),
      "|",
      t.clear_ends(),
      t.cursor_row_downs(),
      "|",
      t.clear_ends(),
      t.cursor_row_downs(),
      "|",
      t.clear_ends(),
      t.cursor_ups(2)
    )
    t.flush()

And as such it also allows for creating reusable sequences by storing it into a local variable:

    local three_line_box = table.concat {
      t.cursor_tocolumns(1),
      "|",
      t.clear_ends(),
      t.cursor_row_downs(),
      "|",
      t.clear_ends(),
      t.cursor_row_downs(),
      "|",
      t.clear_ends(),
      t.cursor_ups(2)
    }

    t.write(three_line_box)
    t.flush()

**Important**: the stack based functions are not suited for including in reusable strings, because of their dynamic nature. They would restore the state to the state from before the string was *created*, not to the state from before the stored value is actually *used*.

## 1.3 stacks

Terminal state cannot be queried (the exception being the cursor position). This means that if something is changed in the state of the terminal (eg. forground or background color) one cannot easily revert it to the previous state. This is what the stacks attempt to resolve.

For each piece of state there is a separate stack to control it. Leading to the following stacks:

- **cursor shape**: controls the shape of the cursor and whether it blinks or not.
- **cursor visibility**: controls the visibility of the cursor, which has a separate state in the terminal, and hence has its own stack.
- **cursor position**: controls the position of the cursor. This one is slightly different from the other ones, since this is the only queryable state in the terminal.
- **scroll region**: controls the rows for the scrollable region.
- **text attributes and color**: this controls colors and attributes like `reverse`, `blink`, etc.

Each stack has the following operations:

- **`push(values...)`**: takes value(s) for the specific stack, pushes it onto the stack, and applies it.
- **`pop(n)`**: pops `n` items of the stack, and applies the top of the stack again.
- **`apply()`**: applies the item at the top of the stack (eg. undoes any intermediate changes).

The cursor position stack operates as follows:

- **`push(new_row, new_col)`**: pushes the current cursor position onto the stack, and moves the cursor to the new position.
- **`pop(n)`**: pops `n` items of the stack, and applies the last item popped.

## 1.4 Text attributes

Text attributes are managed as a set of multiple values. These include:

- **foreground color**: in base-color, extended colors (255), or RGB colors (3x 255).
- **background color**: in base-color, extended colors (255), or RGB colors (3x 255).
- **brightness**: A combination of "invisible", "dim", none and "bright/bold" attributes.
- **underline**: boolean to control underlining.
- **blink**: boolean to control blinking.
- **reverse**: boolean to control reversing.
