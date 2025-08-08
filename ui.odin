package main

import "core:fmt"
import "core:math"
import "core:strings"

import "core:unicode/utf8"
rune_size :: utf8.rune_size

// ==================================================================================
// ==============================   BOX UTILITY PROCS   =============================
// ==================================================================================

box_list :: proc(allocator: Allocator) -> [dynamic] ^Box {// {{{
    return make([dynamic] ^Box, allocator = allocator)
}// }}}

is_child :: proc(box, parent: ^Box) -> bool {// {{{
    if box == parent do return true
    if box.parent == nil do return false
    return is_child(box.parent, parent)
}// }}}

get_child_box :: proc(parent: ^Box, text: string) -> ^Box {// {{{
    for child in parent.children {
        if child.text == text do return child
    }
    return nil
}// }}}

get_child_box_recursive :: proc(parent: ^Box, text: string) -> ^Box {// {{{
    for child in parent.children {
        if child.text == text do return child
        if box := get_child_box_recursive(child, text); box != nil do return box 
    }
    return nil
}// }}}

get_parent_of_type :: proc(box: ^Box, type: BoxType) -> ^Box {// {{{
    if box == nil do return nil
    if box.type == type do return box
    return get_parent_of_type(box.parent, type)
}// }}}

get_first_child_of_type :: proc(box: ^Box, type: BoxType) -> ^Box {// {{{
    for child in box.children {
        if box.type == type do return child
    }
    return nil
}   // }}}

scroll_to :: proc(parent: ^Box, box: ^Box) {// {{{
    parent.scroll.pos = box.cached_pos - { 0, parent.cached_pos.y }
}// }}}

print_box_hierarchy :: proc(tree: ^Box, level := 0) {// {{{
    space := "                                                                                                "
    fmt.printfln("%s[%q]", space[:level*4], tree.text)
    for child, i in tree.children {
        print_box_hierarchy(child, level + 1)
        if i > 24 {
            fmt.println(space[:level*4+4], "...", sep = "")
            return
        }

    }
}// }}}

template_default_popup :: proc() -> Box {// {{{
    return {
        parent = &window.root,
        min_size = { 1, 1 },
        hidden = true,
    }
}// }}}

// ==================================================================================
// ==============================   BOX REGISTRATION   ==============================
// ==================================================================================

init_box :: proc(box: ^Box, parent: ^Box) {// {{{
    box.parent = parent

    if box.type == .UNKNOWN {
        // if len(box.text) == 0 do box.type = .CONTAINER
        if box.folded || box.cached_indent != {} do box.type = .LIST
    }

    box.allocator = make_arena() if box.type == .CONTAINER else parent.allocator

    // calculating (to-be-rendered) text size
    if len(box.text) > 0 {

        allocation: bool
        box.text, allocation = strings.replace_all(box.text, "\t", "    ", box.allocator)
        if !allocation { box.text = strings.clone(box.text, box.allocator) }

        // this is ignores new lines and is later replaced,
        // but I guess, it is good to not have 0 tex_size... or smth... 
        // + later can make my own
        box.tex_size = measure_text(box.text, box.font)
        if box.min_size == {} do box.min_size = box.tex_size
        if box.padding.y != 0 && box.min_size.y != 0 {
            box.min_size.y += box.padding.y * 2
        }
    }

    if box.type == .CODE do box.min_size.x = 0
    if box.advance == {} do box.advance.y = 1
    if box.foreground    == {} do box.foreground = .FG1
    if box.active_color  == {} do box.active_color = box.background
    if box.hovered_color == {} do box.hovered_color = box.background
    if box.loading_color == {} do box.loading_color = .BG4

    if box.type == .TEXT_INPUT {
        box.offsets = make([] int, 1)
    }
}// }}}

// Automatically initializes a box made out of templates
// templates are box structs that override only non-zero properties
// of previous structs. See: util.merge()
// And appends the box to parent boxes children.
append_box :: proc(parent: ^Box, templates: ..Box) -> ^Box {// {{{
    new_box := new(Box, parent.allocator)
    for a_box in templates { new_box^ = merge(new_box^, a_box) }
    append(&parent.children, new_box)
    box := parent.children[len(parent.children) - 1]

    init_box(box, parent)

    if len(window.tabs) > 0 && box.entity != nil {
        tab := current_tab()
        tab.box_table[box.entity.name] = box
    }
    
    debug.box_count += 1
    return box
}// }}}

pop_queued_box :: proc(queue: ^[dynamic] ^Box) -> bool {// {{{
    if queue == nil do return false
    if len(queue) <= 0 do return false

    box := pop_front(queue)

    assert(!box.rendered)
    assert(box.render_scheduled)

    if box.type == .CODE { 
        render_code_block(box)
    } else {

        color := box.design.foreground if box.type != .TEXT_INPUT else box.design.ghost_color

        text := box.text if input_empty(box) else strings.to_string(box.input.buffer)
        if len(text) > 0 {
            box.tex, box.tex_size = render_text(box.text, box.font, color)
            if box.min_size == {} do box.min_size = box.tex_size
            window.should_relayout_later = true
        }
    }

    box.rendered = true
    box.render_scheduled = false
    debug.box_placed += 1
    return true
}// }}}

pop_box_from_any_queue :: proc() {// {{{
    tab := current_tab()

    a := len(tab.cache_queue) if tab != nil else 0
    b := len(window.box_queue)

    if a < b && a != 0 {
        if pop_queued_box(&tab.cache_queue) do return
    }

    pop_queued_box(&window.box_queue)

}// }}}

clear_box :: proc(box: ^Box, the_chosen := true) {// {{{
    for child in box.children {
        clear_box(child, false)
    }

    for &hotbox in (transmute([^] ^Box) &window.hot_boxes)[:size_of(window.hot_boxes)/size_of(^Box)] {
        if box == hotbox do hotbox = nil
    }

    if box.tex != nil { 
        destroy_texture(box.tex) 
        box.tex = nil
        box.tex_size = {}
    }

    if box.type == .CONTAINER { free_all(box.allocator) }
    if the_chosen { clear(&box.children) }
    else do box^ = {}

    if the_chosen {
        box.children = make([dynamic] ^Box, allocator = box.allocator)
    }

    window.should_relayout = true
}// }}}

setup_base_ui :: proc() {// {{{
    using window.boxes
    
    window.box_queue.allocator = permanent
    window.root.allocator = permanent

    content = append_box(&window.root, {
        type     = .CONTAINER,
        border   = true,
        design   = { background = .BG3 },
    })
    toolbar = append_box(&window.root, { 
        type     = .CONTAINER,
        min_size = { 0, 52 },
        design   = { background = .BG2 }, 
        border   = true,
    })
    sidebar = append_box(&window.root, { 
        type     = .CONTAINER,
        min_size = { CONFIG_SIDEBAR_OPEN, 0 }, 
        design   = { background = .BG2 },
        border   = true,
        click    = box_collapse_handler,
    })
    navbar  = append_box(&window.root, { 
        type     = .CONTAINER,
        min_size = { CONFIG_NAVBAR_CLOSED, 0 },  
        old_size = { CONFIG_NAVBAR_OPEN, 0 },  
        mirror   = { true, false }, 
        design   = { background = .BG2 }, 
        border   = true,
        click    = box_collapse_handler,
    })
    
    window.boxes.popup = new(Box, permanent)
    window.boxes.popup^ = template_default_popup()
    append(&window.root.children, window.boxes.popup)

    toolbar.offset.x = &sidebar.min_size.x
    // sidebar.offset.y = &toolbar.min_size.y
    navbar.offset.y = &toolbar.min_size.y

    content.offset.x = &sidebar.min_size.x
    content.offset.y = &toolbar.min_size.y
    
    toolbar_search := append_box(toolbar, {
        type      = .TEXT_INPUT,
        min_size  = { -navbar.min_size.x, CONFIG_FONT_SIZE + 4 }, //  - sidebar.min_size.x
        position  = { 2, 2 },
        padding   = { 4, 1 },
        design    = { 
            foreground    = .FG2, 
            background    = .BG3, 
            active_color  = .BG4, 
            hovered_color = .BG4,
            ghost_color   = .FG4,
        }, 
        border    = true,
        border_in = true,
        font      = .MONO,
        text      = "search package",
        click     = search_click_handler,
        submit    = search_submit_handler,
    })
    window.boxes.search = toolbar_search

    // toolbar_search.offset.x = &sidebar.min_size.x
    setup_sidebar(sidebar)

    window.should_relayout = true

}// }}}

make_context_menu :: proc(target: ^Box, items: [] Box) {// {{{
    context_menu: Box = {
        parent        = &window.root,
        type          = .CONTAINER,
        padding       = { 4, 4 },
        border        = true,
        background    = .BG3,
        position      = ({ window.mouse.x, target.cached_pos.y + target.cached_size.y } - target.cached_scroll),
        target        = target
    }

    init_box(&context_menu, &window.root)

    item_template: Box = {
        type    = .BASIC,
        margin  = { 4, 0 },
        padding = { 2, 1 },
        // border  = true,
        foreground = .FG2,
        // background = .BG2,
        hovered_color = .BG4,
        active_color  = .GRAY1,
        target        = target,
    }

    for item in items { 
        if len(item.text) == 0 { continue }

        size  := measure_text(item.text, item.font)
        width := max(context_menu.min_size.x, size.x + 8)
        context_menu.min_size.x = width + item.padding.x 
        context_menu.min_size.y += size.y + 2 + item_template.padding.y*2 + item_template.margin.y

        append_box(&context_menu, item_template, item) 
        context_menu.scroll.max = context_menu.min_size
    }
    context_menu.min_size.y += 4
    

    window.boxes.popup^ = context_menu
    window.active_context_menu = window.boxes.popup

    for child in context_menu.children {
        two: i32 = 1
        child.offset.xy = new_clone(two)
        child.min_size.x = context_menu.min_size.x - 4 // border takes up 2 pixels on each side...
        child.parent = window.boxes.popup
    }

    window.should_relayout = true
}// }}}

update_text_input :: proc(box: ^Box) {// {{{
    if box.tex != nil { destroy_texture(box.tex); box.tex = nil }
    if box.ghost_tex != nil { destroy_texture(box.ghost_tex); box.ghost_tex = nil }

    if len(box.buffer.buf) == 0 {
        if box.tex != nil { destroy_texture(box.tex) }
        box.tex, box.tex_size = render_text(box.text, box.font, box.ghost_color)
        box.old_size = box.tex_size
        return
    }

    delete_slice(box.offsets)
    box.offsets = make([] int, len(box.buffer.buf) + 1  +4)

    x := 0
    for r, i in strings.to_string(box.buffer) {
        x += measure_rune_advance(r, box.font)

        rune_size := utf8.rune_size(r)
        for j in 0..<rune_size {
            box.offsets[i+1 + j] = x
        }
    }

    box.tex, box.tex_size = render_text(strings.to_string(box.buffer), box.font, box.foreground)
    box.old_size = box.tex_size

    window.text_cursor_visible = true
    window.text_cursor_change_state_in = CONFIG_CURSOR_REFRESH_RATE

    if len(box.buffer.buf) > 1 && box.suggestions != nil {

        for suggestion in box.suggestions {
            if len(suggestion) < len(box.buffer.buf) do continue

            if strings.starts_with(suggestion, string(box.buffer.buf[:])) {
                box.ghost_text = suggestion[len(box.buffer.buf):]
                box.ghost_tex, box.ghost_size = render_text(box.ghost_text, box.font, box.ghost_color)
                return
            }
        }
        
        min_distance := max(int)
        min_result: string
        for suggestion in box.suggestions {
            if len(suggestion) < len(box.buffer.buf) do continue

            distance := strings.levenshtein_distance(suggestion, string(box.buffer.buf[:]))
            if distance < min_distance {
                min_distance = distance
                min_result = suggestion
            }
        }

        if min_distance < 3 {
            box.ghost_text = min_result[len(box.buffer.buf):]
            box.ghost_tex, box.ghost_size = render_text(box.ghost_text, box.font, box.ghost_color)
        }

    }

}// }}}

// ==================================================================================
// ================================    BOX LAYOUT    ================================
// ==================================================================================

calculate_size :: proc(box: ^Box, base_pos: Vector) -> Vector {// {{{
    size := box.min_size
    parent_size := (window.size - base_pos) if box.parent == &window.root else box.parent.cached_size
    if size.x < 1 do size.x = max(parent_size.x - math.abs(size.x), 0)
    if size.y < 1 do size.y = max(parent_size.y - math.abs(size.y), 0)
    return size + box.padding
}// }}}

layout_box :: proc(box: ^Box, the_pos: ^Vector) {// {{{
    if box.hidden do return

    box.cached_pos += box.position

    box.cached_pos.x += box.offset.x^ if box.offset.x != nil else 0
    box.cached_pos.y += box.offset.y^ if box.offset.y != nil else 0

    box.cached_pos += the_pos^

    if box.parent.type == .LIST {
        indent := box.parent.indent + box.parent.cached_indent
        box.cached_pos    += indent
        box.cached_indent += indent
    }

    box.cached_size = calculate_size(box, box.cached_pos)

    if box.mirror.x do box.cached_pos.x = window.size.x - box.cached_size.x  
    if box.mirror.y do box.cached_pos.y = window.size.y - box.cached_size.y

    if box.type == .CONTAINER {
        the_pos^  = box.cached_pos + { 1, 0 }
    } else {
        the_pos^ += scale_vec(box.cached_size + box.margin + box.position + box.padding, box.advance)
    }

    if !box.folded {
        prev_pos: Vector
        for child, i in box.children {
            layout_box(child, the_pos)
            if prev_pos.y > the_pos.y do box.out_of_order = true
            prev_pos = the_pos^
        }
    }

    box.scroll.max = the_pos^
    if box.type == .CONTAINER { box.scroll.max.y -= box.cached_pos.y }
}// }}}

layout_reset :: proc(box: ^Box) {// {{{
    box.cached_pos = {}
    box.cached_size = {}
    box.cached_indent = {}
    for child in box.children {
        layout_reset(child)
    }
}// }}}

update_layout :: proc() {// {{{

    if window.should_relayout {
        window.should_relayout = false
    } else if window.should_relayout_later && (window.frames + 15) % 30 == 0 {
        window.should_relayout_later = false
    } else {
        return
    }

    layout_reset(&window.root)
    for box in window.root.children {
        the_pos: Vector
        layout_box(box, &the_pos)
    }

    fmt.println("=== layout updated ===")
}// }}}

// ==================================================================================
// ================================   BOX DRAWING    ================================
// ==================================================================================

draw_text_select :: proc(box: ^Box) {// {{{
    selecting_range := box.cursor != box.select
    just_in_case    := max(box.cursor, box.select) < len(box.offsets)
    if !just_in_case do return
    
    if selecting_range {
        x := i32(box.offsets[min(box.cursor, box.select)])
        w := i32(box.offsets[max(box.cursor, box.select)]) - x 
        
        draw_rectangle(box.cached_pos + { x + box.padding.x/2, 0 }, { w, box.tex_size.y }, .AQUA1)
    }
}// }}}

draw_text_cursor :: proc(box: ^Box) {// {{{
    window.text_cursor_change_state_in -= 1
    if window.text_cursor_change_state_in < 0 {
        window.text_cursor_change_state_in = CONFIG_CURSOR_REFRESH_RATE
        window.text_cursor_visible = !window.text_cursor_visible
    }
    if !window.text_cursor_visible do return

    selecting_range := box.cursor != box.select
    just_in_case    := max(box.cursor, box.select) < len(box.offsets)
    if !just_in_case do return

    if !selecting_range {
        x := i32(int(box.cached_pos.x) + box.offsets[min(box.cursor, box.select)]) + box.padding.x/2
        draw_line_rgba({ x, box.cached_pos.y }, { x, box.cached_pos.y + box.tex_size.y }, COLORS[.FG1])
    }
}// }}}

draw_border_raw :: proc(pos, size: Vector, color: Palette, inset := false) {// {{{
    luma1 : f32 = 1.33 if !inset else 0.75 
    luma2 : f32 = 1.33 if  inset else 0.75 

    c1 := brighten(COLORS[color], luma1)
    c2 := brighten(COLORS[color], luma2)
    draw_two_lines_rgba(pos+1, size-2, c1)
    draw_two_lines_rgba(pos-1 + size, -size+2, c2)

    c1  = brighten(c1, luma1)
    c2  = brighten(c2, luma2)
    draw_two_lines_rgba(pos, size, c1)
    draw_two_lines_rgba(pos + size, -size, c2)
}// }}}

// horizontal scrollbar is not drawn
draw_scrollbar :: proc(box: ^Box) {// {{{
    if box.type != .CONTAINER do return

    if box.scroll.max.y == 0 { return }
    if box.scroll.max.y < box.cached_size.y { return }

    track_pos  : Vector = box.cached_pos + { box.cached_size.x - CONFIG_SCROLLBAR_WIDTH, 0 }
    track_size : Vector = { CONFIG_SCROLLBAR_WIDTH, box.cached_size.y }

    if box == window.boxes.content {
        track_pos.x = window.boxes.navbar.cached_pos.x - CONFIG_SCROLLBAR_WIDTH
    }

    if window.events.click == .LEFT && intersects(window.mouse, track_pos, track_size) {
        window.dragged_scrollbar = box
    } else if window.pressed == .NONE {
        window.dragged_scrollbar = nil
    }

    scroll       := box.scroll
    fraction     := f32(scroll.pos.y) / f32(scroll.max.y)
    thumb_offset := scale(track_size.y, fraction) + track_pos.y
    thumb_height := scale(track_size.y*track_size.y, 1/f32(scroll.max.y))

    draw_rectangle(track_pos, track_size, .BG1)
    draw_rectangle({ track_pos.x, thumb_offset }, { track_size.x, thumb_height }, .GRAY2)
    draw_border_raw({ track_pos.x, thumb_offset }, { track_size.x-1, thumb_height }, .GRAY2)

}// }}}

draw_box :: proc(box: ^Box, scroll_amount: Vector) {// {{{
    fmt.assertf(box.cached_size.x >= 0, "Box width is negative... %#v", box) 

    scroll_amount := scroll_amount
    box.cached_scroll = scroll_amount // I don't like this much, but whatever...
    pos := box.cached_pos - scroll_amount

    if box.type == .CONTAINER {
        scroll_amount = box.scroll.pos
    }

    box_visible := !box.hidden
    box_visible &= AABB(pos, { min( box.cached_size.x, pos.x + get_clip_area_size().x ), box.cached_size.y }, {}, window.size)

    if box_visible { 
        if !box.render_scheduled && !box.rendered {
            box.render_scheduled = true
            if box.box_queue != nil {
                append(box.box_queue, box)
            } else {
                append(&window.box_queue, box)
            }
        }
    
        background := box.design.background
        if intersects(window.mouse, pos, box.cached_size) {
            window.hovered = box

            background = box.design.hovered_color
            if window.pressed != .NONE { background = box.design.active_color } 
        }

        if box == window.hot_boxes.active_toolbar_tab {
            background = box.design.active_color
        }

        draw_rectangle(pos, box.cached_size, background)

        if box.progress != nil {
            p := box.progress^
            fraction := min(1, f32(p[0]) / f32(p[1]))
            draw_rectangle(pos + { scale(box.cached_size.x, fraction), 0 }, box.cached_size, box.design.loading_color)
        }

        if box == window.active_input { draw_text_select(box) }

        draw_texture(pos + box.padding/2 + { 0, 2 }, min_vector(box.tex_size, box.cached_size), box.tex)

        ghost_texture_position := pos + box.padding/2 + { box.tex_size.x, 2 }
        draw_texture(ghost_texture_position, min_vector(box.ghost_size, box.cached_size - ghost_texture_position), box.ghost_tex)

        if box == window.active_input { draw_text_cursor(box) }

        if box.border {
            if box == window.hot_boxes.active_input {
                draw_border_raw(pos, box.cached_size, .GRAY1, box.border_in) 
            } else {
                draw_border_raw(pos, box.cached_size, box.background, box.border_in) 
            }
        }
        
        debug.box_drawn += 1
    }

    if box.type == .CONTAINER do set_clip_area(pos, box.cached_size - 2)
    for child, i in box.children { 
        draw_box(child, scroll_amount) 
        if !box.out_of_order && child.cached_pos.y > scroll_amount.y + window.size.y {
            break
        }
    }
    if box.type == .CONTAINER do unset_clip_area()

    if box_visible {
        if box.cached_size.x > CONFIG_SCROLLBAR_WIDTH * 2 { // incredible solution
            draw_scrollbar(box)
            apply_scroll_velocity(box)
        }
    }

}// }}}

prev_frame_active_search: ^Box
draw_window :: proc() {// {{{
    defer prev_frame_active_search = window.active_input 
    if window.active_input != nil && prev_frame_active_search == nil { start_text_input() }
    if window.active_input == nil && prev_frame_active_search != nil { stop_text_input() }

    draw_rectangle({}, window.size, .BAD)

    for box in window.root.children {
        draw_box(box, {})
    }

    draw_debug_info()

}// }}}

draw_debug_info :: proc() { // {{{
    box_info :: proc(name: string, b: ^Box) -> string {// {{{
        return fmt.aprintf(
`%s:
   POS: % 4d % 4d
  SIZE: % 4d % 4d
 MSIZE: % 4d % 4d
 TSIZE: % 4d % 4d (%v)
  TYPE: %v
  TEXT: %q
SCROLL: %v/%v`, name,
                b.cached_pos.x,  b.cached_pos.y, 
                b.cached_size.x, b.cached_size.y,
                b.min_size.x,    b.min_size.y,
                b.tex_size.x,    b.tex_size.y, b.tex,
                b.type,          up_to(b.text, 25),
                b.scroll.pos,    b.scroll.max,
                allocator = context.temp_allocator
        )   
    }// }}}

    if !debug.show do return

    texts := make([dynamic] string, context.temp_allocator)

    append(&texts, fmt.aprintf(" ± FRAMETIME: %v", get_smoothed_frame_time(), allocator = context.temp_allocator))
    append(&texts, fmt.aprintf("BOX    COUNT: %d", debug.box_count, allocator = context.temp_allocator))
    append(&texts, fmt.aprintf("BOXES  DRAWN: %d", debug.box_drawn, allocator = context.temp_allocator))
    append(&texts, fmt.aprintf("BOXES LOADED: %d", debug.box_placed, allocator = context.temp_allocator))
    append(&texts, fmt.aprintf("MOUSE: %d %d", window.mouse.x, window.mouse.y, allocator = context.temp_allocator))
    append(&texts, fmt.aprintf("TAB NUMBER: %d", window.current_tab, allocator = context.temp_allocator))

    if window.hovered != nil { append(&texts, box_info("HOVERED BOX", window.hovered)) }
    if window.active_context_menu != nil { append(&texts, box_info("ACTIVE CONTEXT MENU", window.active_context_menu)) }

    if window.dragged_scrollbar != nil {
        s := window.dragged_scrollbar.scroll
        append(&texts, fmt.aprintf("SCROLL: %d %.2f %d", s.pos.y, s.vel.y, s.max.y, allocator = context.temp_allocator))
    }

    pos: Vector = { 4, 4 + window.boxes.toolbar.cached_size.y }
    for text, i in texts {
        color := Palette.DBG
        if i == 0 && get_smoothed_frame_time() > 15 * 1000 * 1000 do color = .BAD

        texture, size := render_text(text, .MONO, color)
        draw_rectangle_rgba(pos - 2, { min(size.x + 4, 300), size.y + 4 }, { 0, 0, 0, 100 })
        draw_texture(pos, { min(size.x, 300), size.y }, texture)
        pos.y += size.y + 1
        destroy_texture(texture)
    }

}// }}}

