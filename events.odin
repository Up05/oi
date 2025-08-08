package main

import "core:fmt"
import "core:slice"
import "core:reflect"
import "core:strings"
import "core:unicode/utf8"
import docl "doc-loader"
import sdl "vendor:sdl2"

MouseEvent :: proc(target: ^Box)
InputEvent :: proc(target: ^Box)

emit_events :: proc() {// {{{
    handle_keypress(window.events.base)

    box := window.hovered
    defer window.hovered = nil
    if box == nil do return

    if window.events.click != .NONE { on_click(box) }
    handle_scrollbar(box)

}// }}}

on_click :: proc(box: ^Box) {// {{{

    // ================ COOLING HOT BOXES ================
    if window.active_context_menu != nil {
        if !is_child(box, window.active_context_menu) {
            free_all(window.active_context_menu.allocator)
            window.active_context_menu = nil
            window.boxes.popup^ = template_default_popup()
        }
    }

    if window.active_input != nil {
        if box != window.active_input {
            window.active_input = nil
        }
    }

    // ================ CANCELLING CLICKS ================
    if box == window.dragged_scrollbar { return } 

    // ================ CLICKING ON LINKS ================
    for link in box.links {
        if intersects(window.mouse, box.cached_pos - box.cached_scroll + link.pos, link.size) {
            anchor, ok := current_tab().box_table[link.target.name]
            scroll_to(get_parent_of_type(box, .CONTAINER), anchor)
            return
        }
    }

    // ================ DEFAULT  CLICKING ================
    if box.click != nil { 
        box.click(box) 
    }
}// }}}

handle_scrollbar :: proc(box: ^Box) {// {{{
    if box.scroll.pos.y < -15 { fmt.printfln("Scrolled %d pixels, don't make scroll negative!", box.scroll.pos.y) }

    s := window.events.scroll
    if s.x != 0 || s.y != 0 {
        // s.x  = 1 * shift
        // s.y *= !shift
        get_parent_of_type(box, .CONTAINER).scroll.vel += [2]f32 { f32(s.x), f32(s.y) } * 15
    }

    if window.dragged_scrollbar != nil { apply_scroll_dragging(window.dragged_scrollbar) }
} // }}}

apply_scroll_velocity :: proc(box: ^Box) {// {{{
    box.scroll.pos += { i32(box.scroll.vel.x), -i32(box.scroll.vel.y) }
    box.scroll.pos.x = min(box.scroll.pos.x, 0)
    box.scroll.pos.y = max(box.scroll.pos.y, 0)
    box.scroll.vel *= 0.8
}// }}}

apply_scroll_dragging :: proc(box: ^Box) {// {{{
    track_offset := box.cached_pos.y
    track_height := box.cached_size.y
    thumb_height := scale(track_height*track_height, 1/f32(box.scroll.max.y))

    box.scroll.pos.y = i32( 
        f32(window.mouse.y - track_offset - thumb_height/2) / 
        f32(track_height) / (1/f32(box.scroll.max.y)) )
}// }}}

box_toggle_fold_handler :: proc(target: ^Box) {// {{{
    target.folded = !target.folded
    window.should_relayout = true
}// }}}

box_collapse_handler :: proc(target: ^Box) {// {{{
    if target.old_size.x == 0 do target.old_size.x = target.min_size.x

    {
        test1 := target.min_size.x
        test2 := test1 ~ (target.old_size.x ~ 15)
        test3 := test2 ~ (target.old_size.x ~ 15)
        old   := target.old_size.x
        fmt.assertf(old == test2 || old == test3, " curr: %d, old: %d, xor1: %d xor2: %d\n(go to the code for more info)", test1, old, test2, test3)
        // min_size was changed
        // and old_size was not updated!
    }

    target.min_size.x = target.min_size.x ~ (target.old_size.x ~ 15)
    window.should_relayout = true
}// }}}

search_click_handler :: proc(target: ^Box) {// {{{
    fmt.println("SEARCH CLICKED")

    if window.events.click == .LEFT {
        window.active_input = target
    }

    if window.events.click == .RIGHT {
        boxes: [SearchMethod] Box
        for method in SearchMethod {
            boxes[method] = { 
                text     = eat(reflect.enum_name_from_value(method)), 
                userdata = transmute(rawptr) u64(method), 
                click    = proc(item: ^Box) {
                    item.target.method = auto_cast (transmute(u64) item.userdata)
                    fmt.println("SEARCH METHOD:", item.target.method)
                }
        }
        }
        make_context_menu(target, (cast([^] Box) &boxes)[:len(boxes)])
    }
}// }}}

codeblock_click_handler :: proc(target: ^Box) {// {{{
    if window.events.click == .RIGHT {
        boxes: [2] Box = {
            {
                text = "copy",
                click = proc(item: ^Box) { copy(item.target.text) },
            },
            {
                text = "open in editor", 
                click = proc(item: ^Box) {
                    view_in_editor(item.target.entity)
                }
            },
        }
        make_context_menu(target, (cast([^] Box) &boxes)[:len(boxes)])
    
    }
}// }}}

tab_click_handler :: proc(target: ^Box) {// {{{
    tab := cast(^Tab) target.userdata
    for &bar_tab, i in window.tabs {
        if &bar_tab == tab {
            switch_tabs(i)
            return
        }
    }
    fmt.println("Did not find tab. Failed to set current tab in tab_click_handler")
}// }}}

nexus_submit_handler :: proc(target: ^Box) {// {{{
    template: Box = {
        type   = .LIST,
        font   = .MONO,
        indent = { 16, 0 },
        click  = box_toggle_fold_handler,
    }

    colors: [docl.Entity_Kind] Palette = {
        .Invalid      = .BAD, 
        .Constant     = .YELLOW1, 
        .Variable     = .YELLOW2, 
        .Type_Name    = .PURPLE2, 
        .Procedure    = .AQUA2, 
        .Proc_Group   = .AQUA1, 
        .Import_Name  = .BAD, 
        .Library_Name = .BAD, 
        .Builtin      = .GRAY1,  
    }

    for box, i in window.boxes.content.children {
        if box == target {
            set_dynamic_array_length(&window.boxes.content.children, i + 1)
        }
    }

    root := append_box(window.boxes.content, { font = .LARGE, text = "results:", position = { 0, 8 } })
    node := root

    query := string(target.buffer.buf[:])
    filter_func := search_method_procs[target.method]

    for &column in entity_table { // technically, row, but no matter
        
        path := column.file[:len(column.file) - len(".odin-doc")]
        directories := strings.split(path, "@")

        n: int
        for &entity, i in column.entities {
            if n > 15 {
                append_box(node, template, { text = "..." })
                break
            }
            if !filter_func(entity, query) do continue 
            
            if n == 0 {
                for dir in directories {
                    box := get_child_box(node, dir)
                    if box != nil {
                        node = box
                        continue
                    }
                    node = append_box(node, template, { text = dir, foreground = .ORANGE2 })
                }
            }

            append_box(node, template, { 
                text        = entity, 
                foreground  = colors[column.types[i]],
                userdata    = new_clone(cat({ "cache/", column.file })),
                click       = nexus_result_click_event_handler, 
            })

            n += 1
        }
        node = root
    }

    window.should_relayout = true
}// }}}

sidebar_click_event_handler :: proc(target: ^Box) {// {{{
    module := Module { 
        name     = target.text, 
        userdata = target.userdata, 
        function = get_module_function_by_name(target.text) 
    }
    open_sidebar_module(module)
}// }}}

nexus_result_click_event_handler :: proc(target: ^Box) {// {{{
    module := Module { 
        name     = target.parent.text, 
        userdata = target.userdata, 
        function = get_module_function_by_name(target.parent.text) 
    }
    open_sidebar_module(module)
}// }}}

search_submit_handler :: proc(search: ^Box) {// {{{
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
        padding = { 0, 1 },
        margin  = { 0, -2 },
        active_color  = .BG3,
        hovered_color = .BG3,
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
        append(&tab.search, box)
    }

    if window.boxes.navbar.min_size.x == CONFIG_NAVBAR_CLOSED {
        box_collapse_handler(window.boxes.navbar)
    }
}// }}}

search_result_click_handler :: proc(target: ^Box) {// {{{
    tab := current_tab()
    if tab == nil do return
    anchor, ok := tab.box_table[target.text]
    if !ok do return

    scroll_to(window.boxes.content, anchor)

    tab.search[tab.search_cursor].background = .TRANSPARENT
    for child, i in tab.search {
        if child.text == target.text do tab.search_cursor = i
    }
    tab.search[tab.search_cursor].background = tab.search[tab.search_cursor].active_color   
}// }}}

handle_keypress :: proc(base_event: Event) {// {{{
    is_relevant_event: bool
    is_relevant_event ||= base_event.type == (.KEYDOWN if ODIN_OS != .Darwin else .KEYUP)
    is_relevant_event ||= base_event.type == .TEXTINPUT
    is_relevant_event ||= base_event.type == .TEXTEDITING
    if !is_relevant_event { return }

    event: sdl.Keysym = base_event.key.keysym
    
    mods: bit_set [KeyMod]
    if event.mod & { .LCTRL, .RCTRL }   != {} do mods += { .CTRL  }
    if event.mod & { .LSHIFT, .RSHIFT } != {} do mods += { .SHIFT } 
    if event.mod & { .LALT, .RALT }     != {} do mods += { .ALT   }
    if event.mod & { .LGUI, .RGUI }     != {} do mods += { .SUPER } 


    for keybind in KEYBINDS {
        if keybind.key  == event.sym && keybind.mods == mods {
            keybind.func()
            return
        } 
    }

    if window.active_input != nil {
        handle_keyboard_in_text_input(window.active_input, base_event) 
    }

}// }}}

handle_keyboard_in_text_input :: proc(search: ^Box, base_event: Event) {// {{{
    using search

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
        update_text_input(search)

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
        if search.submit != nil do search.submit(search)
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

        update_text_input(search)
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

        update_text_input(search)
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

        update_text_input(search)
        return

    case: 
    }

}// }}}

