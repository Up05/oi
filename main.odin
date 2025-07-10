package main

import "core:fmt"
import sdl "vendor:sdl2"

// main.odin should only be changed when absolutely necessary
// and cannot even be bodged elsewhere.


// This is a programmer tool, let's be suckless!
// ========== CONFIGURATION ==========

CONFIG_MAX_FPS      :: 60   

CONFIG_FONT_SIZE    :: 14

// original colorscheme totally stolen from morhetz/gruvbox
CONFIG_UI_BG1       :: "282828FF"
CONFIG_UI_BG2       :: "3C3836FF"
CONFIG_UI_BG3       :: "504945FF"
CONFIG_UI_FG1       :: "FBF1C7FF"
CONFIG_UI_FG2       :: "EBDBB2FF"
CONFIG_UI_CODE      :: "B8BB26FF"
CONFIG_UI_BLUE      :: "458588FF"

// formatter
CONFIG_SET_THE_CHILDREN_STRAIGHT :: true


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


// partially taken from: https://stackoverflow.com/questions/2548541/achieving-a-constant-frame-rate-in-sdl
next_frame_target: u32
take_break :: proc() {
    now := sdl.GetTicks()
    breaktime := max(next_frame_target - now, 0)
    if breaktime < 1000 do sdl.Delay(breaktime)
}

main :: proc() {
    
    // cache_everything()
    // fmt.println("\n================================================================")
    // assert( sdl.GetTicks() != 999999 )

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
