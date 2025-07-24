package main

import "core:fmt"
import "core:mem"
import sdl "vendor:sdl2"

// This is a programmer tool, might as well just make it suckless!
// ========== CONFIGURATION ==========

CONFIG_MAX_FPS               :: 60   
CONFIG_FONT_SIZE             :: 14
CONFIG_LARGE_FONT_SIZE       :: 22
CONFIG_SCROLLBAR_WIDTH       :: 16
CONFIG_SEARCH_PANEL_CLOSED   :: 15  // in pixels
CONFIG_SEARCH_PANEL_OPEN     :: 400 
CONFIG_TAB_WIDTH             :: 32 
CONFIG_SEARCH_METHOD_WIDTH   :: 96
CONFIG_INITIAL_SEARCH_METHOD :: SearchMethod.CONTAINS
CONFIG_EMPTY_TAB_NAME        :: "Empty tab"

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

// keybinds
// enum Category { ... }
// enum Modifier { CTRL, SHIFT, ALT, SUPER/WINDOWS }
// keys = {
//    category = {
//        { { CTRL, SHIFT }, { R }, recache_everything }
//        ...


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

should_exit: bool
main :: proc() {
    when ODIN_DEBUG {
		track: mem.Tracking_Allocator
		mem.tracking_allocator_init(&track, context.allocator)
		context.allocator = mem.tracking_allocator(&track)

		defer {
			if len(track.allocation_map) > 0 {
				fmt.eprintf("=== %v allocations not freed: ===\n", len(track.allocation_map))
				for _, entry in track.allocation_map {
					fmt.eprintf("- %v bytes @ %v\n", entry.size, entry.location)
				}
			}
			mem.tracking_allocator_destroy(&track)
		}
	}

    defer { // performance bodge
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
    for !should_exit {

        event: sdl.Event
        for sdl.PollEvent(&event) {
            #partial switch event.type {
            case .QUIT:         should_exit = true
            case .WINDOWEVENT:  if event.window.event == .RESIZED  { handle_resize() }
            case .MOUSEWHEEL:   window.events.scroll = { event.wheel.x, event.wheel.y }
            case .MOUSEBUTTONDOWN: 
                window.events.click = auto_cast event.button.button
                window.pressed      = auto_cast event.button.button
            case .MOUSEBUTTONUP:
                window.pressed = .NONE
            case .KEYDOWN, .TEXTINPUT: 
                handle_keypress(event)
            case: 
            }
        }

        sdl.SetRenderDrawColor(window.renderer, 0, 0, 0, 255)
        sdl.RenderClear(window.renderer)

        render_frame()

        eat_uncached_code_block()

        sdl.RenderPresent(window.renderer)
        take_break()
        next_frame_target += (1000 / CONFIG_MAX_FPS)

        window.events = {}
        free_all(context.temp_allocator)
    }

    free_all(alloc.body) // for tracking allocator

    sdl.DestroyWindow(window.handle)
    sdl.Quit()
}   


/*
TODO:

    search:
        shift does work
        ctrl shouldn't work

    maybe make icons for packages?

    horizontal scrolling?
    weird fullscreen bug
    copy codeblock
    open codeblock in editor
    fzf for sidebar
    search methods

    hot packages (sidebar pkg background redness would be controlled by visits/month)
      maybe an integrator? since, otherwise, I'd need to every visit

  search:
    maybe all_search_inputs: [dynamic] ^Search
      for mouse input...
    up/down arrows could be used for the selection of items in the list?

  1. global indexer
    load every file 
    simd look from strings that match the user querry*
      from entities[0].offset to entities[entities.length - 1].offset + ... .size
    load/highlight? files that have anything useful

  2. links 
    for links to other packages
      make my own map of files to package aliasses to packages
        (parse the odin files when recaching everything)
      and then just curr_file + pkg_alias.name -> package.name
    this is just in the "Everything/Global search" package

  3. custom content
    I would like to render the overview
    odin index's documentation
    ...

  4. (very easy) user libs

  5. accessibility


*/

