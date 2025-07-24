package main

import "core:fmt"
import sdl "vendor:sdl2"
import "vendor:sdl2/ttf"

// typedef struct {
//   Uint8  scancode; // just UTF-8 (from my understanding)
//   SDLKey sym;      // https://www.libsdl.org/release/SDL-1.2.15/docs/html/sdlkey.html
//   SDLMod mod;      // https://www.libsdl.org/release/SDL-1.2.15/docs/html/sdlkey.html#SDLMOD
//   Uint16 unicode;  // do not use (since wchar_t)
// } SDL_keysym;

handle_keypress :: proc(base_event: sdl.Event) {
    event: sdl.Keysym = base_event.key.keysym
    
    is_lowercase := event.mod & { .RSHIFT, .LSHIFT, .CAPS } == { }

    ctrl  := .LCTRL  in event.mod
    shift := .LSHIFT in event.mod

    // be sure to `return` in the switch to stop 
    // a key event from going the active search
    #partial switch event.sym {
        case .ESCAPE:
            if window.active_search != nil {
                window.active_search.select = window.active_search.cursor
            }
            window.active_search = nil
            return
        case .s:
            if ctrl && is_lowercase {
                window.active_search = &window.toolbar_search
                return
            }
        case .w:
            if ctrl {
                close_tab(window.current_tab)
                return
            }
        

        case:
    }

    if window.active_search != nil {
        handle_event_search(window.active_search, base_event)          
    }
}
