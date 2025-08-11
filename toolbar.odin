package main

current_tab :: proc() -> ^Tab {
    if len(window.tabs) <= window.current_tab do return nil
    return &window.tabs[window.current_tab]
}

switch_tabs :: proc(index: int) {
    if index < 0 || index >= len(window.tabs) do return
    old_tab := current_tab()
    window.current_tab = index
    window.root.children[0] = &current_tab().box
    window.boxes.content = window.root.children[0]
    window.should_relayout = true
    window.boxes.content.scroll = current_tab().scroll
    window.hot_boxes.active_toolbar_tab = current_tab().toolbar_box
    window.boxes.navbar.children = current_tab().search
}

new_tab :: proc(name: string) {

    tab: Tab
    tab_index: int

    tab.box = {
        type   = .CONTAINER,
        border = true,
        design = { background = .BG3 },
        offset = { &window.boxes.sidebar.min_size.x, &window.boxes.toolbar.min_size.y },
    }

    if len(window.tabs) <= 0 || !window.tabs[0].is_empty {

        tab.allocator = make_arena()
        tab.is_empty = name == CONFIG_EMPTY_TAB_NAME
        window.current_tab = len(window.tabs)
        tab_index = len(window.tabs)

        template: Box = {
            type      = .BASIC,
            click     = tab_click_handler,
            position  = { 2, 2 },
            padding   = { 4, 2 },
            margin    = { 2, 0 },
            advance   = { 1, 0 },
            border    = true,

            foreground    = .FG2,
            background    = .BG1,
            active_color  = .BG3,
            hovered_color = .BG4,
        }

        tab.toolbar_box = append_box(window.boxes.toolbar, template, { text = name }) 
        append(&window.tabs, tab)
        tab.toolbar_box.userdata = current_tab()

        switch_tabs(tab_index)
        init_box(window.boxes.content, &window.root)
        
    } else {
        window.tabs[0].is_empty = false
        tab := &window.tabs[0]
        tab_index = 0

        box := tab.toolbar_box
        box.text = name
        box.tex, box.tex_size = render_text(box.text, box.font, box.foreground)
        box.min_size = box.tex_size + { 0, box.padding.y } // total hack, cba to fix root cause
    }
    

}

close_tab :: proc(tab_index: int, caller := #caller_location) {
    {
        old_tab := current_tab()
        if old_tab.is_empty do return

        clear(&old_tab.box_table)
        clear(&old_tab.cache_queue)
        clear_box(old_tab)
        for box in old_tab.search { clear_box(box) }

        for box, i in window.boxes.toolbar.children {
            if box == old_tab.toolbar_box {
                ordered_remove(&window.boxes.toolbar.children, i)
            }
        }

        free_all(old_tab.allocator) // <-- !!!
        old_tab = {}
    }

    ordered_remove(&window.tabs, tab_index)

    if len(window.tabs) <= 0 {
        new_tab(CONFIG_EMPTY_TAB_NAME)
    }

    if window.current_tab >= len(window.tabs) {
        window.current_tab -= 1
    }
    switch_tabs(window.current_tab)
    window.should_relayout = true
}

