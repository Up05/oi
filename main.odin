package main

import "core:fmt"
import sdl "vendor:sdl2"

// This is a programmer tool, might as well just make it suckless!
// ========== CONFIGURATION ==========

CONFIG_MAX_FPS      :: 60   
CONFIG_FONT_SIZE    :: 14

CONFIG_SCROLLBAR_WIDTH :: 16

// original colorscheme totally stolen from morhetz/gruvbox
CONFIG_UI_BG1       :: "282828FF"
CONFIG_UI_BG2       :: "3C3836FF"
CONFIG_UI_BG3       :: "504945FF"
CONFIG_UI_FG1       :: "FBF1C7FF"
CONFIG_UI_FG2       :: "EBDBB2FF"
CONFIG_UI_CODE      :: "B8BB26FF"
CONFIG_UI_BLUE      :: "458588FF"

CONFIG_CODE_SYMBOL    : u32 : 0xFFFF00FF
CONFIG_CODE_KEYWORD   : u32 : 0xFF0000FF
CONFIG_CODE_NAME      : u32 : 0x77FFBBFF
CONFIG_CODE_DIRECTIVE : u32 : 0x7700FFFF
CONFIG_CODE_STRING    : u32 : 0x770000FF
CONFIG_CODE_NUMBER    : u32 : 0xCC00CCFF

// formatter
CONFIG_SET_THE_CHILDREN_STRAIGHT :: true

CONFIG_CODE_LINE_SPACING :: 2

// How many characters before procedure arguments   example :: proc(arg1: int, arg2: string) ...
// get broken up into different lines
CONFIG_WHAT_IS_LONG_PROC :: 50


// ===================================

#assert(CONFIG_MAX_FPS < 1000)

#assert(len(CONFIG_UI_BG1)  == 8)
#assert(len(CONFIG_UI_BG2)  == 8)
#assert(len(CONFIG_UI_BG3)  == 8)
#assert(len(CONFIG_UI_FG1)  == 8)
#assert(len(CONFIG_UI_FG2)  == 8)
#assert(len(CONFIG_UI_CODE) == 8)
#assert(len(CONFIG_UI_BLUE) == 8)



// ===================================

MEASURE_PERFORMANCE :: true 

// partially taken from: https://stackoverflow.com/questions/2548541/achieving-a-constant-frame-rate-in-sdl
next_frame_target: u32
take_break :: proc() {
    now := sdl.GetTicks()
    breaktime := max(next_frame_target - now, 0)
    if breaktime < 1000 do sdl.Delay(breaktime)
}

main :: proc() {
    defer {
        longest: int
        for func, _ in fperf {
            longest = max(longest, len(func))
        }

        for func, durr in fperf {
            space :=  "                                                    "
            fmt.printfln("%s%s%v", func, space[:longest - len(func) + 4], durr)
        }
    }

    assert( sdl.Init(sdl.INIT_VIDEO) >= 0, "Failed to initialize SDL!" )
    assert( sdl.CreateWindowAndRenderer(1280, 720, { sdl.WindowFlag.RESIZABLE }, &window.handle, &window.renderer) >= 0, "Failed to start program!" )

    initialize_window()

    next_frame_target = sdl.GetTicks() + (1000 / CONFIG_MAX_FPS)
    gameloop: for {
        event: sdl.Event
        for sdl.PollEvent(&event) {
            #partial switch event.type {
            case .QUIT:         break gameloop
            case .KEYDOWN:      if event.key.keysym.sym == .ESCAPE { break gameloop }
            case .WINDOWEVENT:  if event.window.event == .RESIZED  { handle_resize() }
            case .MOUSEWHEEL:   window.events.scroll = { event.wheel.x, event.wheel.y }
            case .MOUSEBUTTONDOWN: window.events.click = auto_cast event.button.button
            case: 
            }
        }
        sdl.SetRenderDrawColor(window.renderer, 0, 0, 0, 255)
        sdl.RenderClear(window.renderer)

        render_frame()

        sdl.RenderPresent(window.renderer)
        take_break()
        next_frame_target += (1000 / CONFIG_MAX_FPS)

        window.events = {}
        free_all(context.temp_allocator)
    }


    sdl.DestroyWindow(window.handle)
    sdl.Quit()
}   


/*
TODO:
  1. global indexer
    load every file 
    simd look from strings that match the user querry*
      from entities[0].offset to entities[entities.length - 1].offset + ... .size
    load/highlight? files that have anything useful

  2. links
    links for the same package I can do right now
    for links to other packages
      make my own map of files to package aliasses to packages
        (parse the odin files when recaching everything)
      and then just curr_file + pkg_alias.name -> package.name

  3. custom content
    I would like to render the overview
    odin index's documentation
    ...

  4. (very easy) user libs
 
*/


