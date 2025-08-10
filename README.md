oi (odin index) is a native, keyboard-driven documentation viewer for the Odin programming language.

https://github.com/user-attachments/assets/8f393445-5f31-46b0-8dfc-c47625bbd544

 
It is an alternative to the [pkg.odin-lang.org](https://pkg.odin-lang.org) website, that I started, because:

1. The site was too slow on my laptop :(. 
2. I dislike the fuzzy, scattered matching
3. I eventually found myself just typing out the entire:  
   `pkg.odin-lang.org/core/strings` to go to `strings`... 
4. also there still is no os/os2 there and I can never find where laytan's HTTP library docs are...

And now:

1. Well, I went outside and my kernel borked, but I do use SDL with heavy culling of UI elements (and lazy text rendering)
2. There are a bunch of search methods, (default: "dotstar" -- `strings.contains` + only `.*` from regex)
3. `Ctrl + T` to open packages (almost all packages have unique names after 3-4 letters, so why bother typing "core/")
4. base:intrinsics and base:builtin were (for now) traded in for os2 and user libraries (just enter their path)
5. Source can be viewed directly in the user's editor (instead of Github) by pressing `Ctrl + G` (or in right click menu)

# Installation

Works on Linux and Windows, although, unfortunately, not really tested on MacOS (time estimate has only ever increased...)

On Windows: 
Please keep SDL2\*.dll files next to the executable

The Odin compiler has to be in your `PATH` to generate the `oi.exe directory/cache`

```
git clone https://github.com/Up05/oi
cd oi && odin run .
```
Could use for "release": `odin build . -o:speed`

# Configuration

The program is configured through source code. 

Entire configuration may be found in the `main.odin`. Simply edit it and rebuild.

<img width="1920" height="1040" alt="image" src="https://github.com/user-attachments/assets/a582123c-aa15-45e6-a444-221556fb4a7b" />

This is only somewhat inspired by suckless software, since
there is no patching, and I haven't figured out how to properly do source code config
without the user having to merge their sh\*t or copy-paste onto updated sources main.odin.  
Sorry...

# Contributing

## UI

The UI is made up of "boxes" (only). Content and navbar box contents + some other stuff is cached is tabs, but there can only be 1 tab at once.

All boxes are children of `window.root`, but (generally) you will want to append to one of `window.boxes.(sidebar|content|toolbar)`.
Boxes are layed out automatically, although, after editing them, be sure to set `window.should_relayout` to `true`!

The function to append new boxes is:
```odin
append_box( parent, ..templates )

// example:

more_generic_text_input: Box = {
    type = .TEXT_INPUT,
    font = .MONO,
    background = .BG1, // 1 is darkest, 4 is brightest
    border    = true,  // BASIC elements can't have a border (currently)
    border_in = true,  // border_in[set]
    ...
}

append_box(toolbar, more_generic_text_input, {
    // 0 in min_size means "fill parent" 
    // (negative numbers are also allowed, just 'parent.x|y - abs(min_size.x|y)')
    min_size = { 0, CONFIG_FONT_SIZE }, 
    text = "search in package"    
})
```
The templates are "merged" i.e.: properties of the previous structs get overwritten by (non-zero) properties of following structs

I just add all of the random-ass global state to `window`.

## Files

```
# base building blocks
main    - configuration and the main function
header  - type and many global variable declarations
sdl     - layer of indirection on top of SDL2 and TTF + stuff related
os      - the gateway to core:os/os2
ui      - most of ui implementation + setup_base_ui
util    - utility functions and type aliasses

# specific features
toolbar   - toolbar + tab
modules   - sidebar + content modules
formatter - odin source code formatter + syntax highlighter

# function pointer implementations
keybinds  - keyboard shortcut procedures
event     - event handling procedures
```

## Please don't:

1. use the os[2] package outside of os.odin
2. unalign my code intentionally or remove leading whitespace via tool
3. add unnecessary things to main.odin
4. (to younger me) split up the `Box` mega struct to save <200kb

# Thanks to

[Smilex for MacOS fixes](https://github.com/Smilex/oi)


