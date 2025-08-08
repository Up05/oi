package main

Bind :: struct {
    key  : Key,
    mods : bit_set [KeyMod],
    func : proc(),
    name : string,
}

kb_exit_textbox :: proc() {// {{{
    if window.active_input != nil {
        window.active_input.select = window.active_input.cursor
        window.active_input = nil
    }
}// }}}

kb_close_tab :: proc() {// {{{
    close_tab(window.current_tab)
}// }}}

kb_focus_search :: proc() {// {{{
    window.active_input = window.boxes.search
}// }}}

kb_focus_address :: proc() {// {{{
    window.boxes.sidebar.scroll.pos = {}
    window.active_input = window.boxes.address
}// }}}

kb_goto_next_result :: proc() {// {{{
    tab := current_tab()
    if tab == nil do return
    if len(tab.search) == 0 do return

    if tab.search[tab.search_cursor].font == .LARGE do tab.search_cursor += 1
    tab.search_cursor = max(tab.search_cursor, 0) % len(tab.search)

    target := tab.search[tab.search_cursor]
    anchor, ok := tab.box_table[target.text]
    if ok { scroll_to(window.boxes.content, anchor) }

    tab.search_cursor += 1
    tab.search_cursor = max(tab.search_cursor, 0) % len(tab.search)

    target.background = .TRANSPARENT
    tab.search[tab.search_cursor].background = tab.search[tab.search_cursor].active_color   
}// }}}

kb_goto_prev_result :: proc() {// {{{
    tab := current_tab()
    if tab == nil do return
    if len(tab.search) == 0 do return

    if tab.search[tab.search_cursor].font == .LARGE do tab.search_cursor -= 1
    if tab.search_cursor < 0 do tab.search_cursor = len(tab.search) - 1

    target := tab.search[tab.search_cursor]
    anchor, ok := tab.box_table[target.text]
    if ok { scroll_to(window.boxes.content, anchor) }

    tab.search_cursor -= 1
    if tab.search_cursor < 0 do tab.search_cursor = len(tab.search) - 1

    target.background = .TRANSPARENT
    tab.search[tab.search_cursor].background = tab.search[tab.search_cursor].active_color   
}// }}}

kb_open_code_in_editor :: proc() {// {{{
    box := window.hot_boxes.hovered
    if box == nil do return
    if box.type != .CODE do return

    view_in_editor(box.entity)
}// }}}

kb_toggle_debug_menu :: proc() {// {{{
    debug.show = !debug.show
}// }}}

kb_recache_everything :: proc() {
    recache()
}

kb_open_nexus   :: proc() { open_module_by_name("nexus") }
kb_open_raylib  :: proc() { open_module_by_name("raylib") }
kb_open_vulkan  :: proc() { open_module_by_name("vulkan") }
kb_open_os2     :: proc() { open_module_by_name("os2") }
kb_open_strings :: proc() { open_module_by_name("strings") }
kb_open_math    :: proc() { open_module_by_name("math") }
kb_open_linalg  :: proc() { open_module_by_name("linalg") }
kb_open_utf8    :: proc() { open_module_by_name("utf8") }

kb_switch_tab_1 :: proc() { switch_tabs(0) }
kb_switch_tab_2 :: proc() { switch_tabs(1) }
kb_switch_tab_3 :: proc() { switch_tabs(2) }
kb_switch_tab_4 :: proc() { switch_tabs(3) }
kb_switch_tab_5 :: proc() { switch_tabs(4) }
