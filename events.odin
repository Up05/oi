package main

import "core:fmt"
import "core:reflect"
import "core:strings"
import docl "doc-loader"
import sdl "vendor:sdl2"

MouseEvent :: proc(target: ^Box)

emit_events :: proc() {
    box := window.hovered
    defer window.hovered = nil
    if box == nil do return

    if window.active_context_menu != nil {
        if window.events.click != .NONE && !is_child(box, window.active_context_menu) {
            free_all(window.active_context_menu.allocator)
            window.active_context_menu = nil
            window.boxes.popup^ = template_default_popup()
        }
    }

    if window.active_input != nil {
        if window.events.click != .NONE && box != window.active_input {
            window.active_input = nil
        }
    }

    if window.events.click != .NONE && box != window.dragged_scrollbar {
        clicked_on_link: bool
        for link in box.links {
            if intersects(window.mouse, box.cached_pos - box.cached_scroll + link.pos, link.size) {
                anchor, ok := current_tab().box_table[link.target.name]
                scroll_to(get_parent_of_type(box, .CONTAINER), anchor)
                clicked_on_link = true
            }
        }
        if !clicked_on_link && box.click != nil { box.click(box) }
    }

    if box.scroll.pos.y < -15 {
        fmt.printfln("Scrolled %d pixels, scroll.pos.y should ALWAYS be positive!", box.scroll.pos.y)
    }
    s := window.events.scroll
    if s.x != 0 || s.y != 0 {
        // s.x *= shift
        // s.y *= !shift
        get_parent_of_type(box, .CONTAINER).scroll.vel += [2]f32 { f32(s.x), f32(s.y) } * 15
    }

    if window.dragged_scrollbar != nil {
        apply_scroll_dragging(window.dragged_scrollbar)
    }
}

apply_scroll_velocity :: proc(box: ^Box) {
    box.scroll.pos += { i32(box.scroll.vel.x), -i32(box.scroll.vel.y) }
    box.scroll.pos.x = min(box.scroll.pos.x, 0)
    box.scroll.pos.y = max(box.scroll.pos.y, 0)
    box.scroll.vel *= 0.8
}

apply_scroll_dragging :: proc(box: ^Box) {
    track_offset := box.cached_pos.y
    track_height := box.cached_size.y
    thumb_height := scale(track_height*track_height, 1/f32(box.scroll.max.y))

    box.scroll.pos.y = i32( f32(window.mouse.y - track_offset - thumb_height/2)/f32(track_height) / (1/f32(box.scroll.max.y)) )


}

box_toggle_fold_handler :: proc(target: ^Box) {
    target.folded = !target.folded
    window.should_relayout = true
}

box_collapse_handler :: proc(target: ^Box) {
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
}

search_click_handler :: proc(target: ^Box) {
    fmt.println("SEARCH CLICKED")

    if window.events.click == .LEFT {
        window.active_input = target
    }

    if window.events.click == .RIGHT {
        boxes: [SearchMethod] Box
        for method in SearchMethod {
            boxes[method] = { 
                text = eat(reflect.enum_name_from_value(method)), 
                userdata = transmute(rawptr) u64(method) 
            }
        }
        make_context_menu(target, (cast ([^]Box) &boxes)[:len(SearchMethod)])
    }
}

handle_keypress :: proc(base_event: sdl.Event) {
    event: sdl.Keysym = base_event.key.keysym
    
    is_lowercase := event.mod & { .RSHIFT, .LSHIFT, .CAPS } == { }

    ctrl  := .LCTRL  in event.mod
    shift := .LSHIFT in event.mod

    // be sure to `return` in the switch to stop 
    // a key event from going the active search
    #partial switch event.sym {
        case .ESCAPE:
            if window.active_input != nil {
                window.active_input.select = window.active_input.cursor
            }
            window.active_input = nil
            return
        case .s:
            if ctrl && is_lowercase {
                window.active_input = get_first_child_of_type(window.boxes.toolbar, .TEXT_INPUT)
                return
            }
        case .w:
            if ctrl {
                close_tab(window.current_tab)
                return
            }
        

        case:
    }

    if window.active_input != nil {
        handle_event_search(window.active_input, base_event)          
    }
}

nexus_submit_handler :: proc(target: ^Box) {
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
}


sidebar_click_event_handler :: proc(target: ^Box) {
    module := Module { 
        name     = target.text, 
        userdata = target.userdata, 
        function = get_module_function_by_name(target.text) 
    }
    open_sidebar_module(module)
}

nexus_result_click_event_handler :: proc(target: ^Box) {
    module := Module { 
        name     = target.parent.text, 
        userdata = target.userdata, 
        function = get_module_function_by_name(target.parent.text) 
    }
    open_sidebar_module(module)
}






