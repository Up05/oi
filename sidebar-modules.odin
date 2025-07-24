package main

import docl "doc-loader"

Module :: struct {
    // type     : int,
    name     : string,
    userdata : rawptr,
    function : proc(data: rawptr)
}

open_odin_package :: proc(userdata: rawptr) {// {{{
    when MEASURE_PERFORMANCE {
        __start := tick_now() 
        defer fperf[#location().procedure] += tick_diff(__start, tick_now())
    }    
    
    ok: bool
    current_tab().everything, ok = docl.load(string(transmute(cstring) userdata), current_tab().alloc)
    assert(ok)

    everything := current_tab().everything
    tab := current_tab()

    template      : Box = { font = fonts.regular, margin = { 0, 4 }, scroll = &tab.scroll } 
    template_code : Box = { fmt_code = true,      margin = { 0, 4 }, scroll = &tab.scroll } 
    pos : Vector = { window.sidebar_w + 10, window.toolbar_h + 10 }

    the_package := everything.initial_package

    place_box(&tab.children, the_package.name, &pos, { font = fonts.large, margin = { 0, 12 }, scroll = &tab.scroll })
    if len(the_package.docs) > 0 {
        place_box(&tab.children, the_package.docs, &pos, template)
    }

    for _, entity in the_package.entities {
        if entity.kind == .Type_Name { // <--
            box := place_box(&tab.children, format_code_block(entity), &pos, template_code)
            if box != nil { tab.box_table[entity.name] = box }
            place_box(&tab.children, entity.docs, &pos, template)
        }
    }

    for _, entity in the_package.entities {
        if entity.kind == .Procedure {
            box := place_box(&tab.children, format_code_block(entity), &pos, template_code)
            if box != nil { tab.box_table[entity.name] = box }
            place_box(&tab.children, entity.docs, &pos, template)
        }
    }

    for _, entity in the_package.entities {
        if entity.kind == .Proc_Group {
            box := place_box(&tab.children, format_code_block(entity), &pos, template_code)
            if box != nil { tab.box_table[entity.name] = box }
            place_box(&tab.children, entity.docs, &pos, template)
        }
    }

    for _, entity in the_package.entities {
        if entity.kind == .Constant || entity.kind == .Variable {
            box := place_box(&tab.children, format_code_block(entity), &pos, template_code)
            if box != nil { tab.box_table[entity.name] = box }
            place_box(&tab.children, entity.docs, &pos, template)
        }
    }

}// }}}
