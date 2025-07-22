package main

import "base:runtime"
import "core:fmt"
import "core:strings"
import "core:slice"
import os "core:os/os2"
import sdl "vendor:sdl2"
import "vendor:sdl2/ttf"
import doc "core:odin/doc-format"
import docl "doc-loader"

// 1 level of indirection from SDL, 
// just in case I want to change it back to Raylib or smth
// ====================================
Image   :: ^sdl.Surface
Texture :: ^sdl.Texture
Font    :: ^ttf.Font
RGBA    :: sdl.Color
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

TextBox  :: struct {
    pos   : Vector,
    size  : Vector,
    tex   : Texture,
    text  : string,
    type  : TextType,
    links : [] HyperLink,
}
Button   :: struct {
    pos   : Vector,
    size  : Vector,
    tex   : Texture,
    click : ClickEvent,
    userdata : rawptr,
    padding  : Vector,
    border  : bool,
}


TextType :: enum { HEADING, PARAGRAPH, CODE_BLOCK }
ClickEvent :: proc(target: ^Box)

HyperLink :: struct {
    pos    : Vector,
    size   : Vector,
    target : ^docl.Entity,
}

Box :: struct {
    relative : bool, // whether pos is relative to the parent
    parent   : ^Box,

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

Scroll :: struct {
    pos : i32, 
    vel : f32,
    max : i32,
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

    toolbar_h : i32, // maybe more "navbar" buf "nav" is 3 symbols.
    sidebar_w : i32, // yup... just toolbar_height... in pixels...

    content_scroll    : Scroll, // scroll is negative!!! 
    sidebar_scroll    : Scroll, // .pos can never be positive
    search_scroll     : Scroll,
    dragged_scrollbar : ^Scroll,

    toolbar_search : Search,
    active_search  : ^Search,
    search_panel   : Box
}

fonts : struct {
    regular : ^ttf.Font,
    mono    : ^ttf.Font,
    large   : ^ttf.Font
}

cache : struct {
    body    : [dynamic] Box,
    sidebar : [dynamic] Box,
    toolbar : [dynamic] Box,
    search  : [dynamic] Box, // search panel results
    
    //              ent.name pos.y
    positions : map [string] i32
}

current_everything: docl.Everything

initialize_window :: proc() {// {{{

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

    window.toolbar_h = 24
    window.sidebar_w = 256

    sdl.GetWindowSize(window.handle, &window.size.x, &window.size.y)

    everything, ok := docl.load("cache/core@os.odin-doc"); assert(ok)
    current_everything = everything
    cache_body(everything)

    cache_sidebar()
    cache_toolbar()

    // TODO temp
    window.active_search = &window.toolbar_search
    make_search_panel()

}// }}}

handle_resize :: proc() {
    prev_size := window.size
    sdl.GetWindowSize(window.handle, &window.size.x, &window.size.y)

    // rebuild the cache...
}


render_scrollbar :: proc(pos: Vector, scroll: ^Scroll) {
    bg := colorscheme[Color.BG3]
    fg := colorscheme[Color.FG2]

    w := i32(CONFIG_SCROLLBAR_WIDTH)
    h := window.size.y - pos.y

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

render_boxes :: proc(boxes: [] Box, scroll: ^Scroll) {
    offset_y := scroll.pos
    for &box in boxes {
        pos  := box.pos + box.offset + { 0, offset_y }
        size := box.size

        screen_pos := box.pos

        if box.relative && box.parent != nil {
            pos += box.parent.pos + box.parent.offset 
            screen_pos += box.parent.pos + box.parent.offset 
        }
        
        render_texture(box.tex, pos, size)
        
        if box.click != nil && clicked_in(screen_pos, size) { 
            box.click(&box) 
        }

        for link in box.links {
            y := link.pos.y + offset_y
            sdl.RenderDrawLine(window.renderer, 
                link.pos.x, y + link.size.y, link.pos.x + link.size.x, y + link.size.y)

            if window.events.click == .LEFT &&
               intersects(window.mouse, { link.pos.x, y }, link.size) {
                scroll.pos, _ = cache.positions[link.target.name]
                scroll.pos -= 50
                scroll.pos *= -1
            }
        }


    }
}

render_frame :: proc() {// {{{
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

    if intersects(window.mouse, Vector { window.sidebar_w, window.toolbar_h }, window.size) {
        apply_scroll(&window.content_scroll)
    }
    if intersects(window.mouse, Vector {0, 0}, Vector { window.sidebar_w, window.size.y }) {
        apply_scroll(&window.sidebar_scroll)
    }
    // if intersects(window.mouse, Vector {0, 0}, Vector { window.sidebar_w, window.size.y }) {
    //     apply_scroll(&window.search_scroll)
    // }

    // ============================= CONTENT ============================= 

    underline := colorscheme[Color.BLUE]


    sdl.SetRenderDrawColor(window.renderer, underline.r, underline.g, underline.b, 255)
    render_boxes(cache.body[:], &window.content_scroll)

    render_scrollbar(
        { window.search_panel.pos.x + window.search_panel.offset.x - CONFIG_SCROLLBAR_WIDTH, window.toolbar_h },
        &window.content_scroll)

    // ============================= SEARCH  ============================= 

    {
        panel := &window.search_panel
        pos   := panel.pos + panel.offset 
        size  := panel.size 

        bar := colorscheme[.BG2]
        sdl.SetRenderDrawColor(window.renderer, bar.r, bar.g, bar.b, bar.a)
        sdl.RenderFillRect(window.renderer, &{ pos.x, pos.y, panel.size.x, panel.size.y })

        render_boxes(cache.search[:], &window.search_scroll)

        if panel.click != nil && clicked_in(pos, size) {
            panel.click(panel)
        }
    }

    // ============================= SIDEBAR ============================= 

    bar := colorscheme[.BG3]
    sdl.SetRenderDrawColor(window.renderer, bar.r, bar.g, bar.b, bar.a)
    sdl.RenderFillRect(window.renderer, &{ 0, 0, window.sidebar_w, window.size.y })

    render_boxes(cache.sidebar[:], &window.sidebar_scroll)

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
    
}// }}}

// the font and code_block arguments are, basically, mutually exclusive
place_box :: proc(out: ^[dynamic] Box, text: string, pos: ^Vector, template: Box) {
    assert(out != nil && pos != nil)
    assert(template.font != nil || template.fmt_code)
    if len(text) == 0 do return

    box: Box = template
    box.text = text
    if template.fmt_code {
        surface: ^sdl.Surface
        surface, box.links = cache_code_block(current_everything, text)
        box.tex  = sdl.CreateTextureFromSurface(window.renderer, surface)
        box.size = { surface.w, surface.h }
        sdl.FreeSurface(surface)

    } else {
        box.tex, box.size = text_to_texture(text, true, template.font)
    }

    box.pos = pos^
    pos.y += box.size.y + box.margin.y

    for &link in box.links { link.pos += box.pos }
    append(out, box)
    
}


cache_body :: proc(everything: docl.Everything) {// {{{
    when MEASURE_PERFORMANCE {
        __start := tick_now() 
        defer fperf[#location().procedure] += tick_diff(__start, tick_now())
    }    
    
    register_for_scroll :: proc(name: string, pos: Vector) {
        cache.positions[name] = pos.y
        window.content_scroll.max = pos.y
    }

    clear(&cache.body)

    template      : Box = { font = fonts.regular, margin = { 0, 4 } } 
    template_code : Box = { fmt_code = true,      margin = { 0, 4 } } 
    pos : Vector = { window.sidebar_w + 10, window.toolbar_h + 10 }

    the_package := everything.initial_package

    place_box(&cache.body, the_package.name, &pos, { font = fonts.large, margin = { 0, 12 } })
    if len(the_package.docs) > 0 {
        place_box(&cache.body, the_package.docs, &pos, template)
    }

    for _, entity in the_package.entities {
        if entity.kind == .Type_Name { // <--
            register_for_scroll(entity.name, pos)
            place_box(&cache.body, format_code_block(entity), &pos, template_code)
            place_box(&cache.body, entity.docs, &pos, template)
        }
    }

    for _, entity in the_package.entities {
        if entity.kind == .Procedure {
            register_for_scroll(entity.name, pos)
            place_box(&cache.body, format_code_block(entity), &pos, template_code)
            place_box(&cache.body, entity.docs, &pos, template)
        }
    }

    for _, entity in the_package.entities {
        if entity.kind == .Proc_Group {
            register_for_scroll(entity.name, pos)
            place_box(&cache.body, format_code_block(entity), &pos, template_code)
            place_box(&cache.body, entity.docs, &pos, template)
        }
    }

    for _, entity in the_package.entities {
        if entity.kind == .Constant || entity.kind == .Variable {
            register_for_scroll(entity.name, pos)
            place_box(&cache.body, format_code_block(entity), &pos, template_code)
            place_box(&cache.body, entity.docs, &pos, template)
        }
    }

}// }}}

cache_sidebar :: proc() {// {{{

    sidebar_click_event_handler :: proc(target: ^Box) {
        if target.userdata == nil do return 
        path := (transmute(^string) target.userdata)^
        everything, ok := docl.load(strings.concatenate({ "cache/", path }, context.temp_allocator))
        if ok { cache_body(everything) }
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
        click = sidebar_click_event_handler           
    }
    pos := Vector { 4, window.toolbar_h }
    last_category: string

    // ======= THE MEAT =======
    for file in file_names {
        template.userdata = rawptr(new_clone(strings.clone(file) or_else ""))

        file := file
        if strings.ends_with(file, ".odin-doc") { 
            file = file[:len(file) - len(".odin-doc")] 
        }
        
        if category := strings.index(file, "@"); category != -1 {
            if last_category != file[:category] {
                place_box(&cache.sidebar, file[:category], &pos, 
                    { font = fonts.large })
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
