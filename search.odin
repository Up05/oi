package main

import docl "doc-loader"

import "core:fmt"
import "core:slice"
import "core:reflect"
import "core:strings"
import "core:text/match"
import "core:unicode"
import "core:unicode/utf8"

import sdl "vendor:sdl2"

string_dist :: strings.levenshtein_distance

SearchMethod :: enum {
    CONTAINS,               // default
    STRICT, PREFIX, SUFFIX,
    // TODO later replace with substring fuzzy matching, like: 
    // https://en.wikipedia.org/wiki/Damerau%E2%80%93Levenshtein_distance#Optimal_string_alignment_distance
    FUZZY1, FUZZY2, FUZZY4, // 1, 2 and 4 are the string "distances" in levelshtein algorithm
    REGEX, DOTSTAR,         // dotstar is strings.contains + regex's '.*' 
    // TODO SYNONYMS,       // synonyms WOULD probably use some synonyms graph for stuff
}

search_method_procs: [SearchMethod] proc(a, b: string) -> bool = {
    .CONTAINS = proc(a, b: string) -> bool { return strings.contains(a, b) },
    .STRICT   = proc(a, b: string) -> bool { return a == b },
    .PREFIX   = proc(a, b: string) -> bool { return strings.starts_with(a, b) },
    .SUFFIX   = proc(a, b: string) -> bool { return strings.ends_with(a, b) },
    .FUZZY1   = proc(a, b: string) -> bool { return string_dist(a, b, context.temp_allocator) <= 1 },
    .FUZZY2   = proc(a, b: string) -> bool { return string_dist(a, b, context.temp_allocator) <= 2 },
    .FUZZY4   = proc(a, b: string) -> bool { return string_dist(a, b, context.temp_allocator) <= 4 },
    .REGEX    = proc(a, b: string) -> bool {
        a := a
        captures: [32] match.Match        
        res, ok := match.gfind(&a, b, &captures)
        return len(res) > 0
    },
    .DOTSTAR = dotstar,
    // .SYNONYMS = proc(a, b: string) -> bool { panic("NOT YET IMPLEMENTED") },
}

search_submit_handler :: proc(search: ^Box) {
    tab := current_tab()
    if tab.is_empty do return
    clear_box(window.boxes.navbar)

    query := strings.to_string(search.buffer)
    result: [dynamic] ^docl.Entity 
    defer delete(result)
    
    start_item_count := len(tab.everything.initial_package.entities)
    for name, entity in tab.everything.initial_package.entities {
        if search_method_procs[search.method](name, query) {
            append(&result, entity)
        }
    }
    
    if len(result) == 0 do return
    
    slice.sort_by(result[:], proc(a, b: ^docl.Entity) -> bool {
        return a.kind < b.kind if a.kind != b.kind else a.name < b.name
    })

    template := Box { 
        font  = .MONO,
        click = search_result_click_handler,
    }

    result_box := window.boxes.navbar 

    // cba to import doc-format
    prev_kind := result[len(result) - 1].kind
    prev_kind = auto_cast 0
    for entity in result {
        
        if prev_kind != entity.kind {
            #partial switch entity.kind {
            case .Procedure: append_box(result_box, template, { font = .LARGE, text = "Procedures", })
            case .Type_Name: append_box(result_box, template, { font = .LARGE, text = "Types",      })
            case .Constant:  append_box(result_box, template, { font = .LARGE, text = "Constants",  })
            case .Variable:  append_box(result_box, template, { font = .LARGE, text = "Variables",  })
            }
            prev_kind = entity.kind
        }

        template.font = .MONO 
        box := append_box(result_box, template, { text = entity.name })
    }

    if window.boxes.navbar.cached_size == CONFIG_SEARCH_PANEL_CLOSED {
        box_toggle_fold_handler(window.boxes.navbar)
    }
}

search_result_click_handler :: proc(target: ^Box) {
    tab := current_tab()
    if tab == nil do return
    anchor, ok := tab.box_table[target.text]
    if !ok do return

    scroll_to(window.boxes.content, anchor)
}

handle_event_search :: proc(search: ^Box, base_event: sdl.Event) {// {{{
    using search

    // if base_event.type == .MOUSE_OR_WHATEVER {
    //     return
    // }


    // ============================== ACTUAL TYPING ===============================

    if base_event.type == .TEXTINPUT {
        new_text_raw := base_event.text.text
        new_text := string(transmute(cstring) &new_text_raw)

        if select != cursor {
            remove_range(&buffer.buf, min(select, cursor), max(select, cursor))
            cursor = min(cursor, select)
            select = cursor
        }

        inject_at_elem_string(&buffer.buf, cursor, new_text)
        search.cursor += len(new_text)
        search.select += len(new_text)
        refresh_search(search)

        return 
        // pressing e.g.: 'a' fires 2 events
        // this return stops only the .TEXTINPUT
        // but .KEYDOWN with 'a' still passes: 
    }


    event: sdl.Keysym = base_event.key.keysym
    // is_lowercase := event.mod & { .RSHIFT, .LSHIFT, .CAPS } == { }
    ctrl  := .LCTRL  in event.mod
    shift := .LSHIFT in event.mod

    // TODO
    // (maybe not...) ctrl + z
    // (maybe not...) ctrl + shift + z
    // up/down arrows for history

    // ported from another one of my tools
    #partial switch event.sym {
    case .RETURN:
        search.submit(search)
        return

    case .BACKSPACE, .KP_BACKSPACE:
        if cursor == 0 do break

        if select != cursor {
            hi := max(select, cursor) // as in hi-fi, a.k.a.: "to" (I use it elsewhere too)
            remove_range(&buffer.buf, min(select, cursor), hi)
            cursor = min(cursor, select)
            select = cursor
        } else if ctrl {
            start := strings.last_index_byte(string(buffer.buf[:cursor-1]), ' ') + 1
            remove_range(&buffer.buf, start, cursor)
            cursor = start
            select = start
        } else {
            _, size := utf8.decode_last_rune(buffer.buf[:cursor])
            remove_range(&buffer.buf, cursor - size, cursor)
            cursor -= size
            select -= size
        }

        refresh_search(search)
        return

    case .DELETE:
        if cursor > len(buffer.buf) do return

        if select != cursor {
            hi := max(select, cursor) // as in hi-fi, a.k.a.: "to" (I use it elsewhere too)
            remove_range(&buffer.buf, min(select, cursor), hi)
            cursor = min(cursor, select)
            select = cursor
        } else if ctrl {
            start := strings.index_byte(string(buffer.buf[cursor:]), ' ') 
            if start == -1 {
                start  = len(buffer.buf)
            } else {
                start += cursor + 1
            }
            remove_range(&buffer.buf, cursor, start)
        } else {
            _, size := utf8.decode_rune(buffer.buf[cursor:])
            remove_range(&buffer.buf, cursor, cursor + size)
        }

        refresh_search(search)
        return

    // arrows keys genuinely are just that convoluted...
    // and they don't feel right at all otherwise...
    case .LEFT:
        window.text_cursor_visible = true
        window.text_cursor_change_state_in = CONFIG_CURSOR_REFRESH_RATE

        cursor = min(max(cursor, 0), len(buffer.buf))
        select = min(max(select, 0), len(buffer.buf))

        if cursor != select && !shift {
            cursor = min(cursor, select)
            select = cursor
            return
        }

        if ctrl {
            space_skip := (1 * int(select > 0))
            space := strings.last_index_byte(string(buffer.buf[:select - space_skip]), ' ')
            select = (space + space_skip) if space != -1 else 0
            
            if !shift do cursor = select
            return
        }


        select -= last_rune_size(buffer.buf[:min(cursor, select)])
        select = max(select, 0)
        if !shift do cursor = select
        return

    case .RIGHT:
        window.text_cursor_visible = true
        window.text_cursor_change_state_in = CONFIG_CURSOR_REFRESH_RATE

        _, end_size := utf8.decode_last_rune(buffer.buf[:])
        cursor = min(max(cursor, 0), len(buffer.buf))
        select = min(max(select, 0), len(buffer.buf))

        if cursor != select && !shift {
            cursor = max(cursor, select)
            select = cursor
            return
        }

        if ctrl {
            space_skip := (1 * int(select + 1 < len(buffer.buf)))
            space := strings.index_byte(string(buffer.buf[select + space_skip:]), ' ')
            select = space + select + space_skip if space != -1 else len(buffer.buf)

            if !shift do cursor = select
            return
        }
        
        select += utf8.rune_size(utf8.rune_at(string(buffer.buf[:]), select))
        select = min(select, len(buffer.buf))
        if !shift do cursor = select
        return

    case .UP, .DOWN: // TODO: traverse history
        window.text_cursor_visible = true
        window.text_cursor_change_state_in = CONFIG_CURSOR_REFRESH_RATE

        return

    case .A:
        if !ctrl do break

        select = 0
        cursor = len(buffer.buf)
        if shift do select = cursor

        return
        
    case .C:
        if !ctrl do break

        window.text_cursor_visible = true
        window.text_cursor_change_state_in = CONFIG_CURSOR_REFRESH_RATE

        lo := min(select, cursor)
        hi := max(select, cursor) + utf8.rune_size(utf8.rune_at(string(buffer.buf[:]), max(select, cursor)))

        lo = max(lo, 0); hi = min(hi, len(buffer.buf))
        sdl.SetClipboardText(cstr(string(buffer.buf[lo:hi])))

        return

    case .V:
        if !ctrl do break

        window.text_cursor_visible = true
        window.text_cursor_change_state_in = CONFIG_CURSOR_REFRESH_RATE

        if select != cursor {
            remove_range(&buffer.buf, min(select, cursor), max(select, cursor))
            cursor = min(cursor, select)
            select = cursor
        }
        
        contents := sdl.GetClipboardText()
        inject_at_elem_string(&buffer.buf, cursor, string(contents))
        cursor += len(contents)
        select = cursor
        sdl.free(rawptr(contents))

        refresh_search(search)
        return

    case: 
    }

}// }}}

// theres the same function in ui.odin
refresh_search :: proc(search: ^Box) {
    if len(search.buffer.buf) == 0 {
        if search.tex != nil { destroy_texture(search.tex) }
        search.tex, search.tex_size = render_text(search.text, search.font, search.ghost_color)
        search.old_size = search.tex_size
        return
    }

    if search.tex != nil { 
        destroy_texture(search.tex)
    }
    delete_slice(search.offsets)
    search.offsets = make([] int, len(search.buffer.buf) + 1  +4)

    x := 0
    for r, i in strings.to_string(search.buffer) {
        x += measure_rune_advance(r, search.font)

        rune_size := utf8.rune_size(r)
        for j in 0..<rune_size {
            search.offsets[i+1 + j] = x
        }
    }

    search.tex, search.tex_size = render_text(strings.to_string(search.buffer), search.font, search.foreground)
    search.old_size = search.tex_size
    // window.should_relayout = true

    window.text_cursor_visible = true
    window.text_cursor_change_state_in = CONFIG_CURSOR_REFRESH_RATE
}
    
