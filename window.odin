package main

import "base:runtime"
import "core:fmt"
import "core:strings"
import "core:slice"
import "core:mem"
import "core:math/rand"
import "core:thread"
import os "core:os/os2"
import sdl "vendor:sdl2"
import "vendor:sdl2/ttf"
import doc "core:odin/doc-format"
import docl "doc-loader"

// 1 level of indirection from SDL, 
// TODO expand
// ====================================
Surface :: ^sdl.Surface
Texture :: ^sdl.Texture
Font    :: ^ttf.Font
RGBA    ::  sdl.Color
// ====================================

// ===== TYPES ======

// I am using a custom predefined colorscheme here.
Color :: enum { 
    BG1,        // content
    BG2,        // toolbar
    BG3,        // sidebar
    FG1,        // headings
    FG2,        // paragraphs
    CODE,       // code blocks & (maybe later) inline code 
    BLUE        // hyperlinks
}

MouseButton :: enum { 
    NONE, 
    LEFT, 
    MIDDLE, 
    RIGHT 
}

Vector :: [2] i32

TextType :: enum { HEADING, PARAGRAPH, CODE_BLOCK }
ClickEvent :: proc(target: ^Box)

HyperLink :: struct {
    pos    : Vector,
    size   : Vector,
    target : ^docl.Entity,
}

Scroll :: struct {
    pos : i32, 
    vel : f32,
    max : i32,
}

Tab :: struct {
    is_empty      : bool,
    everything    : docl.Everything,
    alloc         : mem.Allocator,
    box_table     : map [string] ^Box,  // entity name to y offset
    cache_queue   : [dynamic] CodeBlockCacheData,
    children      : [dynamic] Box,
    search        : [dynamic] Box,      // search results for the tab
    scroll        : Scroll,
    search_scroll : Scroll,
}

Box :: struct {
    relative : bool,    // whether pos is relative to the parent
    parent   : ^Box,    // currently only used in search panel
    scroll   : ^Scroll, // parent's scroll

    pos      : Vector,
    size     : Vector,
    offset   : Vector, 
    tex      : Texture,

    font     : Font, 
    fmt_code : bool, 
    entity   : ^docl.Entity,

    type     : TextType,
    text     : string,
    links    : [] HyperLink,

    click    : ClickEvent,
    userdata : rawptr,

    margin   : Vector,
    padding  : Vector,
    // border   : bool,

}

// ===== GLOBAL STATE ======

colorscheme : [Color] RGBA

window : struct {
    handle  : ^sdl.Window,
    renderer: ^sdl.Renderer,
    size    : Vector,
    mouse   : Vector,
    pressed : MouseButton, 

    events  : struct {
        scroll : Vector,
        click  : MouseButton,
        cancel_click : bool,
    },

    toolbar_h : i32,  // yup... just toolbar_height... in pixels...
    sidebar_w : i32,  // maybe more "navbar" but "nav" is 3 symbols.

    sidebar_scroll    :  Scroll, // .pos can never be positive
    dragged_scrollbar : ^Scroll,

    active_search  : ^Search,
    toolbar_search :  Search,
    search_panel   :  Box,

    tabbar_tabs  : [dynamic] Box,
    tabs         : [dynamic] Tab,
    current_tab  : int,
}


fonts : struct {
    regular : ^ttf.Font,
    mono    : ^ttf.Font,
    large   : ^ttf.Font
}

cache : struct {
    // body    : [dynamic] Box,
    sidebar : [dynamic] Box,
    toolbar : [dynamic] Box,
    // search  : [dynamic] Box, // search panel results
    
    //              ent.name pos.y
    // positions : map [string] i32
}

alloc : struct {
    body    : mem.Allocator,
    sidebar : mem.Allocator,
    sdl     : mem.Allocator,
}

pools : struct {
    body : thread.Pool,
}

initialize_window :: proc() {// {{{
    alloc.body = make_arena_alloc()
    alloc.sidebar = make_arena_alloc()

    colorscheme = {
        .BG1  = to_rgba(CONFIG_UI_BG1 ),
        .BG2  = to_rgba(CONFIG_UI_BG2 ),
        .BG3  = to_rgba(CONFIG_UI_BG3 ),
        .FG1  = to_rgba(CONFIG_UI_FG1 ),
        .FG2  = to_rgba(CONFIG_UI_FG2 ),
        .CODE = to_rgba(CONFIG_UI_CODE),
        .BLUE = to_rgba(CONFIG_UI_BLUE),
    }

    assert( ttf.Init() >= 0, "Failed to get True Type Font support" )

    fonts.regular = ttf.OpenFont("font-regular.ttf",   CONFIG_FONT_SIZE)
    fonts.mono    = ttf.OpenFont("font-monospace.ttf", CONFIG_FONT_SIZE)
    fonts.large   = ttf.OpenFont("font-regular.ttf",   CONFIG_LARGE_FONT_SIZE)

    window.toolbar_h = 48
    window.sidebar_w = 256

    sdl.GetWindowSize(window.handle, &window.size.x, &window.size.y)

    cache.sidebar = make([dynamic] Box, alloc.sidebar) 
    cache_sidebar()
    cache_toolbar()

    // temp, later don't make the search active by default
    window.active_search = &window.toolbar_search
    make_search_panel()

    new_tab(CONFIG_EMPTY_TAB_NAME)
    // default_module := Module {
    //     name     = strings.clone("default"),
    //     userdata = raw_data(strings.clone("cache/core@os.odin-doc")),
    //     function = open_odin_package,
    // }
    // open_sidebar_module(default_module)


}// }}}

// I use the getter here because 
// I changed the way I fetch the current tab ~3 times now
// I MAY end up with a { tabs: ..., cursor: int } struct
// and the current way is relatively long (text-wise)
current_tab :: proc() -> ^Tab {
    return &window.tabs[window.current_tab]
}

refresh_tabbar :: proc() {
    x: i32
    if len(window.tabbar_tabs) > 0 do x = window.sidebar_w + 4
    for &tab in window.tabbar_tabs {
        tab.pos.x = x
        x += tab.size.x + tab.margin.x
    }
}

new_tab :: proc(name: string) {

    tab: Tab

    if len(window.tabs) <= 0 || !window.tabs[0].is_empty {

        tab.alloc = make_arena_alloc()
        tab.is_empty = name == CONFIG_EMPTY_TAB_NAME
        append(&window.tabs, tab)
        window.current_tab = len(window.tabs) - 1

        tab_click_handler :: proc(target: ^Box) {
            tab := cast(^Tab) target.userdata
            for &bar_tab, i in window.tabs {
                if &bar_tab == tab {
                    window.current_tab = i
                    fmt.println("TEST", i)
                }
            }
            fmt.println("Did not find tab. Failed to set current tab in tab_click_handler") // VERY TODO
        }


        template: Box = {
            font     = fonts.regular,
            click    = tab_click_handler,
            userdata = rawptr(current_tab()),
            margin   = { 2, 0 },
        }
        
        x: i32 = 4
        for tab in window.tabbar_tabs {
            x += tab.size.x + template.margin.x
        }

        pos := Vector { window.sidebar_w + x, window.toolbar_h / 2 + 8 }
        place_box(&window.tabbar_tabs, name, &pos, template) 

    } else {
        window.tabs[0].is_empty = false
        tab := &window.tabbar_tabs[0]
        tab.text = name
        tab.tex, tab.size = text_to_texture(tab.text, true, tab.font)
        refresh_tabbar()

    }
}

close_tab :: proc(tab_index: int, caller := #caller_location) {
    fmt.println(caller)
    old_tab := &window.tabs[tab_index]

    clear(&old_tab.box_table)
    clear(&old_tab.cache_queue)
    destroy_boxes(&old_tab.children)
    destroy_boxes(&old_tab.search)

    free_all(old_tab.alloc) // <-- !!!

    old_tab.scroll = {}

    ordered_remove(&window.tabs,        tab_index)
    ordered_remove(&window.tabbar_tabs, tab_index)

    if len(window.tabs) > 0 {
        refresh_tabbar()
    } else {
        new_tab(CONFIG_EMPTY_TAB_NAME)
    }

    window.current_tab = len(window.tabs) - 1
}

// I would honestly prefer this to be a map of string* <-> function pointer
// and in sidebar.click
open_sidebar_module :: proc(module: Module) {
    
    fmt.println(module)
    new_tab(module.name)

    tab := current_tab()
    tab.box_table    = make(map [string] ^Box, tab.alloc)
    tab.children     = make([dynamic] Box,     tab.alloc)
    tab.search       = make([dynamic] Box,     tab.alloc)
    tab.cache_queue  = make([dynamic] CodeBlockCacheData, 0, 32, tab.alloc)

    // old core:os has processor_core_count
    // but I would rather not use it here
    // and I can quite safely assume that all
    // target computers will have >= 4 cores
    thread.pool_init(&pools.body, alloc.body, 3) 
    thread.pool_start(&pools.body)

    module.function(module.userdata)
}

handle_resize :: proc() {
    fmt.println("window resized")
    prev_size := window.size
    sdl.GetWindowSize(window.handle, &window.size.x, &window.size.y)

    make_search_panel()
    // cache_body(current_everything)
    // rebuild the cache...
}


render_scrollbar :: proc(pos: Vector, scroll: ^Scroll) {
    bg := colorscheme[Color.BG3]
    fg := colorscheme[Color.FG2]

    w := i32(CONFIG_SCROLLBAR_WIDTH)
    h := window.size.y - pos.y

    if scroll.max < window.size.y {
        return
    }

    sdl.SetRenderDrawColor(window.renderer, bg.r, bg.g, bg.b, 255)
    sdl.RenderFillRect(window.renderer, &{ pos.x, pos.y, w, h })
    
    fraction := f32(-scroll.pos) / f32(scroll.max)
    y2 := i32(f32(h) * fraction) + pos.y
    h2 := i32(f32(h) * f32(h)/f32(scroll.max))
    
    sdl.SetRenderDrawColor(window.renderer, fg.r, fg.g, fg.b, 255)
    sdl.RenderFillRect(window.renderer, &{ pos.x, y2, w, h2 })

    if window.events.click == .LEFT && intersects(window.mouse, pos, { w, h }) {
        window.dragged_scrollbar = scroll
    } else if window.pressed == .NONE {
        window.dragged_scrollbar = nil
    }

    if window.dragged_scrollbar == scroll {
        scroll.pos = -i32( f32(window.mouse.y - pos.y - h2/2)/f32(h) / (1/f32(scroll.max)) )
    }

}

render_texture :: proc(texture: Texture, pos: Vector, size: Vector) {
    sdl.RenderCopy(window.renderer, texture, 
        &{ 0, 0, size.x, size.y }, &{ pos.x, pos.y, size.x, size.y })
} 

calculate_pos :: proc(box: Box, scroll: ^Scroll) -> (world: Vector, screen: Vector) {
    world  = box.pos + box.offset + { 0, scroll.pos }
    screen = box.pos
    if box.relative && box.parent != nil {
        world  += box.parent.pos + box.parent.offset 
        screen += box.parent.pos + box.parent.offset
    }
    return 
}

render_boxes :: proc(boxes: [] Box) {
    for &box in boxes {
        scroll := box.scroll if box.scroll != nil else &{}
        size   := box.size

        offset_y := scroll.pos
        pos, screen_pos := calculate_pos(box, scroll)
        
        render_texture(box.tex, pos, size)
        
        if box.click != nil && clicked_in(pos, size) { 
            box.click(&box) 
        }

        for link in box.links {
            y := link.pos.y + offset_y
            sdl.RenderDrawLine(window.renderer, 
                link.pos.x, y + link.size.y, link.pos.x + link.size.x, y + link.size.y)

            if window.events.click == .LEFT &&
               intersects(window.mouse, { link.pos.x, y }, link.size) {
                target := current_tab().box_table[link.target.name]
                if target != nil {
                    scroll.pos  = eat(calculate_pos(target^, scroll)).y
                    // scroll.pos += 50
                    scroll.pos *= -1
                }
            }
        }


    }
}

render_frame :: proc() {// {{{
    tab := current_tab()

    sdl.GetMouseState(&window.mouse.x, &window.mouse.y)
    sdl.SetRenderDrawColor(window.renderer, 255, 200, 200, 255)
    sdl.RenderFillRect(window.renderer, 
        &{ window.sidebar_w, window.toolbar_h, window.size.x, window.size.y })
    apply_scroll :: proc(scroll: ^Scroll) {
        scroll.vel += f32(window.events.scroll.y * 15)
        scroll.pos += i32(scroll.vel)
        scroll.pos  = min(scroll.pos, 0)
        scroll.vel *= 0.8
    }

    if intersects(window.mouse, window.search_panel.pos + window.search_panel.offset, window.search_panel.size) {
        apply_scroll(&tab.search_scroll)
    } else if intersects(window.mouse, Vector { window.sidebar_w, window.toolbar_h }, window.size) {
        apply_scroll(&tab.scroll)
    }
    if intersects(window.mouse, Vector {0, 0}, Vector { window.sidebar_w, window.size.y }) {
        apply_scroll(&window.sidebar_scroll)
    }

    // ============================= CONTENT ============================= 

    underline := colorscheme[Color.BLUE]

    sdl.SetRenderDrawColor(window.renderer, underline.r, underline.g, underline.b, 255)
    render_boxes(tab.children[:])

    render_scrollbar({ window.search_panel.pos.x + window.search_panel.offset.x - CONFIG_SCROLLBAR_WIDTH, window.toolbar_h }, &tab.scroll)

    // ============================= SEARCH  ============================= 

    {
        panel := &window.search_panel
        pos   := panel.pos + panel.offset 
        size  := panel.size 

        bar := colorscheme[.BG2]
        sdl.SetRenderDrawColor(window.renderer, bar.r, bar.g, bar.b, bar.a)
        sdl.RenderFillRect(window.renderer, &{ pos.x, pos.y, panel.size.x, panel.size.y })

        render_boxes(tab.search[:])

        if panel.click != nil && clicked_in(pos, size) {
            panel.click(panel)
        }

        if window.search_panel.offset.x == -CONFIG_SEARCH_PANEL_OPEN {
            render_scrollbar({ window.size.x - CONFIG_SCROLLBAR_WIDTH, window.toolbar_h }, &tab.search_scroll)
        }
    }

    // ============================= SIDEBAR ============================= 

    bar := colorscheme[.BG3]
    sdl.SetRenderDrawColor(window.renderer, bar.r, bar.g, bar.b, bar.a)
    sdl.RenderFillRect(window.renderer, &{ 0, 0, window.sidebar_w, window.size.y })

    render_boxes(cache.sidebar[:])

    render_scrollbar({ window.sidebar_w - CONFIG_SCROLLBAR_WIDTH, window.toolbar_h }, &window.sidebar_scroll)

    // ============================= TOOLBAR ============================= 

    bar  = colorscheme[.BG2]
    sdl.SetRenderDrawColor(window.renderer, bar.r, bar.g, bar.b, bar.a)
    sdl.RenderFillRect(window.renderer, &{ 0, 0, window.size.x, window.toolbar_h })

    for &element in cache.toolbar {
        using element
    
        sdl.RenderCopy(window.renderer, tex, 
            &{ 0, 0, size.x, size.y }, &{ pos.x, pos.y, size.x, size.y })

        // if element.border {
        //     border := colorscheme[.FG2]
        //     sdl.SetRenderDrawColor(window.renderer, border.r, border.g, border.b, border.a)
        //     border_pos  := element.pos  - element.padding/2        // + offset_y for other buttons
        //     border_size := element.size + element.padding
        //     sdl.RenderDrawRect(window.renderer, &{ border_pos.x, border_pos.y, border_size.x, border_size.y })
        // }

        if intersects(window.mouse - { 0, 0 }, element.pos, element.size) &&
           window.events.click == .LEFT &&
           element.click != nil { element.click(&element) }
    }
    
    draw_search(window.toolbar_search, window.active_search == &window.toolbar_search)

    // ========================== INTERSECTION? ========================== 
    
    bar  = colorscheme[.CODE]
    sdl.SetRenderDrawColor(window.renderer, bar.r, bar.g, bar.b, bar.a)
    sdl.RenderFillRect(window.renderer, &{ 0, 0, window.sidebar_w, window.toolbar_h })
    
    // ============================= TABBAR ============================= 

    render_boxes(window.tabbar_tabs[:])
    


}// }}}

destroy_boxes :: proc(boxes: ^[dynamic] Box) {
    for &box in boxes { if box.tex != nil do sdl.DestroyTexture(box.tex) }
    clear(boxes)
}

// the font and code_block arguments are, basically, mutually exclusive
place_box :: proc(out: ^[dynamic] Box, text: string, pos: ^Vector, template: Box) -> ^Box {
    assert(out != nil && pos != nil)
    assert(template.font != nil || template.fmt_code)
    if len(text) == 0 do return nil

    box: Box = template
    box.text = text
    if template.fmt_code {
        box.size = cache_code_block_deferred(out, len(out), current_tab().everything, text)
    } else {
        box.tex, box.size = text_to_texture(text, true, template.font)
    }

    box.pos = pos^
    pos.y += box.size.y + box.margin.y

    for &link in box.links { link.pos += box.pos }
    append(out, box)

    if box.scroll != nil {
        box.scroll.max = box.pos.y
    }

    return &out[len(out) - 1]
    
}


cache_sidebar :: proc() {// {{{

    sidebar_click_event_handler :: proc(target: ^Box) {
        if target.userdata == nil do return 
        path := (transmute(^string) target.userdata)^
        path  = strings.concatenate({ "cache/", path }, context.allocator)
        module := Module { 
            name = package_name_from_path(path), 
            userdata = raw_data(path), 
            function = open_odin_package 
        }
        open_sidebar_module(module)
    }
    
    // ======= SETUP =======
    file_details, err1 := os.read_all_directory_by_path("cache", context.temp_allocator)
    if err1 != nil { /*rebuild cache*/ panic("need to rebuild cache") }
    file_names := make([] string, len(file_details), context.temp_allocator)
    for file, i in file_details {
        file_names[i] = file.name
    }

    slice.sort(file_names[:])
    
    template := Box {
        font = fonts.regular,
        click = sidebar_click_event_handler,
        scroll = &window.sidebar_scroll,
    }
    pos := Vector { 4, window.toolbar_h }
    last_category: string

    // ======= THE MEAT =======
    for file in file_names {
        template.userdata = rawptr(new_clone(strings.clone(file, alloc.sidebar) or_else "", alloc.sidebar))

        file := file
        if strings.ends_with(file, ".odin-doc") { 
            file = file[:len(file) - len(".odin-doc")] 
        }
        
        if category := strings.index(file, "@"); category != -1 {
            if last_category != file[:category] {
                place_box(&cache.sidebar, file[:category], &pos, 
                    { font = fonts.large, scroll = &window.sidebar_scroll })
            }
            last_category = file[:category]
        }

        levels := strings.count(file, "@") - 1
        if levels > -1 {
            file = file[strings.last_index(file, "@")+1:]
        }

        pos.x += i32(levels) * 16
        place_box(&cache.sidebar, file, &pos, template)
        pos.x -= i32(levels) * 16

        window.sidebar_scroll.max = pos.y
    }


}// }}}

cache_toolbar :: proc() {
    // and as for buttons:
    // ? ? ? ? ? ~ .* /search  \/  /\   ? ? ? ?

    clear(&cache.toolbar)

    make_toolbar_search()
}

display_error :: proc(format: string, values: ..any) {
    fmt.printf(format, ..values)
}
