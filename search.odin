package main

import "core:fmt"
import "core:strings"
import "core:unicode"
import "core:unicode/utf8"

import sdl "vendor:sdl2"
import "vendor:sdl2/ttf"


Search :: struct {
    pos  : Vector,
    size : Vector,

    text    : strings.Builder,
    cursor  : int,              // cursor / selection start                 [bytes]
    select  : int,              // selection end (cursor is the null state) [bytes]
    texture : Texture,

    offsets : [] int,    // rune x offsets in pixels, by byte (NOT RUNE)
}

make_toolbar_search :: proc() {
    search: Search

    search.pos =  { window.sidebar_w + 4, 4 }
    search.texture, search.size = text_to_texture("[s]earch for items...", true)
    search.offsets = make([] int, 1)

    defer window.toolbar_search = search
}

render_search :: proc(search: ^Search) {
    if search.texture != nil {
        sdl.DestroyTexture(search.texture)
    }
    delete_slice(search.offsets)
    search.offsets = make([] int, len(search.text.buf) + 1  +4)

    x := 0
    for r, i in strings.to_string(search.text) {
        minx, maxx, miny, maxy, advance: i32
        glyph := ttf.GlyphMetrics32(fonts.regular, r, &minx, &maxx, &miny, &maxy, &advance)
        width := int(advance)

        x += width

        rune_size := utf8.rune_size(r)
        for j in 0..<rune_size {
            search.offsets[i+1 + j] = x
        }
    }

    search.texture, search.size = text_to_texture(strings.to_string(search.text), false)
}

// may want to refactor this into some more generic text input
// if I will ever need a text input box again in this project...
handle_event_search :: proc(search: ^Search, base_event: sdl.Event) {
    using search

    // if base_event.type == .MOUSE_OR_WHATEVER {
    //     return
    // }

    event: sdl.Keysym = base_event.key.keysym
    is_lowercase := event.mod & { .RSHIFT, .LSHIFT, .CAPS } == { }
    ctrl  := .LCTRL  in event.mod
    shift := .LSHIFT in event.mod
    
    // TODO
    // (maybe not...) ctrl + z
    // (maybe not...) ctrl + shift + z
    // up/down arrows for history

    // ported from another one of my tools
    #partial switch event.sym {
    case .BACKSPACE, .KP_BACKSPACE:
        if cursor == 0 do break

        if select != cursor {
            hi := max(select, cursor) // as in hi-fi, a.k.a.: "to" (I use it elsewhere too)
            remove_range(&text.buf, min(select, cursor), hi)
            cursor = min(cursor, select)
            select = cursor
        } else if ctrl {
            start := strings.last_index_byte(string(text.buf[:cursor-1]), ' ') + 1
            remove_range(&text.buf, start, cursor)
            cursor = start
            select = start
        } else {
            _, size := utf8.decode_last_rune(text.buf[:cursor])
            remove_range(&text.buf, cursor - size, cursor)
            cursor -= size
            select -= size
        }

        render_search(search)
        return

    case .DELETE:
        if cursor > len(text.buf) do return

        if select != cursor {
            hi := max(select, cursor) // as in hi-fi, a.k.a.: "to" (I use it elsewhere too)
            remove_range(&text.buf, min(select, cursor), hi)
            cursor = min(cursor, select)
            select = cursor
        } else if ctrl {
            start := strings.index_byte(string(text.buf[cursor:]), ' ') 
            if start == -1 {
                start  = len(text.buf)
            } else {
                start += cursor + 1
            }
            remove_range(&text.buf, cursor, start)
        } else {
            _, size := utf8.decode_rune(text.buf[cursor:])
            remove_range(&text.buf, cursor, cursor + size)
        }

        render_search(search)
        return

    // arrows keys genuinely are just that convoluted...
    // and they don't feel right at all otherwise...
    case .LEFT:
        cursor = min(max(cursor, 0), len(text.buf))
        select = min(max(select, 0), len(text.buf))

        if cursor != select && !shift {
            cursor = min(cursor, select)
            select = cursor
            return
        }

        if ctrl {
            space_skip := (1 * int(select > 0))
            space := strings.last_index_byte(string(text.buf[:select - space_skip]), ' ')
            select = (space + space_skip) if space != -1 else 0
            
            if !shift do cursor = select
            return
        }


        select -= last_rune_size(text.buf[:min(cursor, select)])
        select = max(select, 0)
        if !shift do cursor = select
        return
    
    case .RIGHT:
        _, end_size := utf8.decode_last_rune(text.buf[:])
        cursor = min(max(cursor, 0), len(text.buf))
        select = min(max(select, 0), len(text.buf))

        if cursor != select && !shift {
            cursor = max(cursor, select)
            select = cursor
            return
        }

        if ctrl {
            space_skip := (1 * int(select + 1 < len(text.buf)))
            space := strings.index_byte(string(text.buf[select + space_skip:]), ' ')
            select = space + select + space_skip if space != -1 else len(text.buf)

            if !shift do cursor = select
            return
        }
        
        select += utf8.rune_size(utf8.rune_at(string(text.buf[:]), select))
        select = min(select, len(text.buf))
        if !shift do cursor = select
        return
    
    case .UP, .DOWN: // TODO: traverse history
        return

    case .A:
        if !ctrl do break

        select = 0
        cursor = len(text.buf)

        return
        
    // case .ESCAPE: (ESC unfocusses the search box)
    //     select = cursor

    case .C:
        if !ctrl do break

        lo := min(select, cursor)
        hi := max(select, cursor) + utf8.rune_size(utf8.rune_at(string(text.buf[:]), max(select, cursor)))

        cstr, original, original_at := corrupt_to_cstr(string(text.buf[lo:hi]))
        sdl.SetClipboardText(cstr)
        uncorrupt_cstr(cstr, original, original_at)

        return

    case .V:
        if !ctrl do break

        if select != cursor {
            remove_range(&text.buf, min(select, cursor), max(select, cursor))
            cursor = min(cursor, select)
            select = cursor
        }
        
        contents := sdl.GetClipboardText()
        inject_at_elem_string(&text.buf, cursor, string(contents))
        cursor += len(contents)
        select = cursor
        sdl.free(rawptr(contents))

        render_search(search)
        return

    case: 
    }

    // ============================== ACTUAL TYPING ===============================

    // I have zero clue how someone would actually implement this at all whatsoever...
    if cast(bool) ttf.GlyphIsProvided32(fonts.regular, transmute(rune) event.sym) {
        r := transmute(rune) event.sym
        if !is_lowercase do r = unicode.to_upper(r)

        if select != cursor {
            remove_range(&text.buf, min(select, cursor), max(select, cursor))
            cursor = min(cursor, select)
            select = cursor
        }

        buf, n := utf8.encode_rune(r)
        inject_at_elem_string(&search.text.buf, search.cursor, string(buf[:n]))
        search.cursor += n
        search.select += n
        render_search(search)
    }
}



draw_search :: proc(search: Search, is_active: bool) {
    FG := colorscheme[.FG2]
    BG := colorscheme[.BLUE]

    if is_active {
        if search.cursor != search.select && max(search.cursor, search.select) < len(search.offsets) {
            x := i32(search.offsets[min(search.cursor, search.select)])
            w := i32(search.offsets[max(search.cursor, search.select)]) - x 
                
            sdl.SetRenderDrawColor(window.renderer, BG.r, BG.g, BG.b, BG.a)
            sdl.RenderFillRect(window.renderer, &{ search.pos.x + x, search.pos.y, w, search.pos.y + search.size.y })
        }
    }

    sdl.RenderCopy(
        window.renderer, search.texture, 
        &{ 0, 0, search.size.x, search.size.y }, 
        &{ search.pos.x, search.pos.y, search.size.x, search.size.y }    
    )

    if is_active {
        if search.cursor == search.select && max(search.cursor, search.select) < len(search.offsets) {
            x := i32(int(search.pos.x) + search.offsets[min(search.cursor, search.select)])
            sdl.SetRenderDrawColor(window.renderer, FG.r, FG.g, FG.b, FG.a)
            sdl.RenderDrawLine(window.renderer, x, i32(search.pos.y), x, i32(search.pos.y + search.size.y))
        }
    }
}


