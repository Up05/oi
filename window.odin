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

Vector :: [2] i32

HyperLink :: struct {
    pos    : Vector,
    size   : Vector,
    target : ^docl.Entity,
}

TextType :: enum { HEADING, PARAGRAPH, CODE_BLOCK }
TextBox  :: struct {
    pos   : Vector,
    size  : Vector,
    tex   : Texture,
    text  : string,
    type  : TextType,
    links : [] HyperLink,
}

ClickEvent :: proc(target: ^Button) -> bool

Button   :: struct {
    pos   : Vector,
    size  : Vector,
    tex   : Texture,
    click : ClickEvent,
    userdata : rawptr,
    padding  : Vector,
    border  : bool,

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

    events  : struct {
        scroll : Vector,
        click  : enum { NONE, LEFT, MIDDLE, RIGHT }, // none of us give a shit
    },

    toolbar_h : i32, // maybe more "navbar" buf "nav" is 3 symbols.
    sidebar_w : i32, // yup... just toolbar_height... in pixels...

    content_scroll : Scroll, // scroll is negative!!! 
    sidebar_scroll : Scroll, // .pos can never be positive

    toolbar_search : Search,
    active_search : ^Search,
}

fonts : struct {
    regular : ^ttf.Font,
    mono    : ^ttf.Font,
    large   : ^ttf.Font
}

cache : struct {
    body    : [dynamic] TextBox,
    sidebar : [dynamic] Button,
    toolbar : [dynamic] Button,
    
    //              ent.name pos.y
    positions : map [string] i32
}


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

    fonts.regular = ttf.OpenFont("font-regular.ttf",   CONFIG_FONT_SIZE    )
    fonts.mono    = ttf.OpenFont("font-monospace.ttf", CONFIG_FONT_SIZE    )
    fonts.large   = ttf.OpenFont("font-regular.ttf",   CONFIG_FONT_SIZE * 2)

    window.toolbar_h = 24
    window.sidebar_w = 256

    sdl.GetWindowSize(window.handle, &window.size.x, &window.size.y)

    everything, ok := docl.load("cache/core@os.odin-doc")
    assert(ok)
    cache_body(everything)

    cache_sidebar()
    cache_toolbar()

    // TODO temp
    window.active_search = &window.toolbar_search


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
        scroll.pos = -i32( f32(window.mouse.y - pos.y - h2/2)/f32(h) / (1/f32(scroll.max)) )
    }

}

render_frame :: proc() {// {{{
    sdl.GetMouseState(&window.mouse.x, &window.mouse.y)

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

    // ============================= CONTENT ============================= 


    underline    := colorscheme[Color.BLUE]

    sdl.SetRenderDrawColor(window.renderer, underline.r, underline.g, underline.b, 255)
    for element in cache.body {
        offset_y := window.content_scroll.pos

        using element
        sdl.RenderCopy(window.renderer, tex, 
            &{ 0, 0, size.x, size.y }, &{ pos.x, pos.y + offset_y, size.x, size.y })

        for link in element.links {
            y := link.pos.y + offset_y
            sdl.RenderDrawLine(window.renderer, 
                link.pos.x, y + link.size.y, link.pos.x + link.size.x, y + link.size.y)

            if window.events.click == .LEFT &&
               intersects(window.mouse, { link.pos.x, y }, link.size) {
                window.content_scroll.pos, _ = cache.positions[link.target.name]
                window.content_scroll.pos -= 50
                window.content_scroll.pos *= -1
            }
        }
    }

    render_scrollbar({ window.size.x - CONFIG_SCROLLBAR_WIDTH, window.toolbar_h }, &window.content_scroll)

    // ============================= SIDEBAR ============================= 

    bar := colorscheme[.BG3]
    sdl.SetRenderDrawColor(window.renderer, bar.r, bar.g, bar.b, bar.a)
    sdl.RenderFillRect(window.renderer, &{ 0, 0, window.sidebar_w, window.size.y })

    for &element in cache.sidebar {
        offset_y := window.sidebar_scroll.pos

        using element
        sdl.RenderCopy(window.renderer, tex, 
            &{ 0, 0, size.x, size.y }, &{ pos.x, pos.y + offset_y, size.x, size.y })

        if intersects(window.mouse - { 0, offset_y }, element.pos, element.size) &&
           window.events.click == .LEFT &&
           element.click != nil { element.click(&element) }
    }


    render_scrollbar({ window.sidebar_w - CONFIG_SCROLLBAR_WIDTH, window.toolbar_h }, &window.sidebar_scroll)

    // ============================= TOOLBAR ============================= 

    bar  = colorscheme[.BG2]
    sdl.SetRenderDrawColor(window.renderer, bar.r, bar.g, bar.b, bar.a)
    sdl.RenderFillRect(window.renderer, &{ 0, 0, window.size.x, window.toolbar_h })

    for &element in cache.toolbar {
        using element
    
        sdl.RenderCopy(window.renderer, tex, 
            &{ 0, 0, size.x, size.y }, &{ pos.x, pos.y, size.x, size.y })

        if element.border {
            border := colorscheme[.FG2]
            sdl.SetRenderDrawColor(window.renderer, border.r, border.g, border.b, border.a)
            border_pos  := element.pos  - element.padding/2        // + offset_y for other buttons
            border_size := element.size + element.padding
            sdl.RenderDrawRect(window.renderer, &{ border_pos.x, border_pos.y, border_size.x, border_size.y })
        }

        if intersects(window.mouse - { 0, 0 }, element.pos, element.size) &&
           window.events.click == .LEFT &&
           element.click != nil { element.click(&element) }
    }
    
    draw_search(window.toolbar_search)

    if window.active_search != nil {
        draw_cursor(window.active_search^)

    }
    

    // ========================== INTERSECTION? ========================== 
    
    bar  = colorscheme[.CODE]
    sdl.SetRenderDrawColor(window.renderer, bar.r, bar.g, bar.b, bar.a)
    sdl.RenderFillRect(window.renderer, &{ 0, 0, window.sidebar_w, window.toolbar_h })
    
}// }}}



cache_body :: proc(everything: docl.Everything) {// {{{
    when MEASURE_PERFORMANCE {
        __start := tick_now() 
        defer fperf[#location().procedure] += tick_diff(__start, tick_now())
    }    
    
    is_any_kind :: proc(a: doc.Entity_Kind, b: ..doc.Entity_Kind) -> bool { return is_any(a, ..b) }

    cache_text :: proc(everything: docl.Everything, str: string, type: TextType) -> (texture: Texture, size: Vector, links: [] HyperLink) {// {{{
        when MEASURE_PERFORMANCE {
            __start := tick_now() 
            defer fperf[#location().procedure] += tick_diff(__start, tick_now())
        }

        text :: ttf.RenderUTF8_Blended_Wrapped
        cstr :: strings.clone_to_cstring        // TODO I can now replace with fast_str_to_cstr
                                                // OR later replace with custom RenderText
        font  := fonts.regular
        color : RGBA = { 127, 0, 0, 255 }
        switch type {
        case .HEADING   : font = fonts.large;   color = colorscheme[.FG1]
        case .PARAGRAPH :                       color = colorscheme[.FG1]
        case .CODE_BLOCK: font = fonts.mono;    color = { 255, 255, 255, 255 } // colorscheme[.CODE]
        }
        
        if type == .CODE_BLOCK {
            s, links := cache_code_block(everything, str)
            defer  sdl.FreeSurface(s)
            return sdl.CreateTextureFromSurface(window.renderer, s), { s.w, s.h }, links
        }

        surface := text(font, cstr(str, context.temp_allocator), color, u32(window.size.x - window.sidebar_w))
        defer  sdl.FreeSurface(surface)
        return sdl.CreateTextureFromSurface(window.renderer, surface), { surface.w, surface.h }, {}
    }

    place_text :: proc(
        everything: docl.Everything,
        pos: ^Vector, str: string, type: TextType, 
        entity: ^docl.Entity = nil, 
        caller := #caller_location) {

        when MEASURE_PERFORMANCE {
            __start := tick_now() 
            defer fperf[#location().procedure] += tick_diff(__start, tick_now())
        }
        fmt.assertf(str != "", "called from: %v\n", caller)
        texture : Texture
        size    : Vector
        element : TextBox
        links   : [] HyperLink
        
        texture, size, links = cache_text(everything, str, type)
        defer  pos.y += size.y + 4

        element.pos   = pos^
        element.size  = size
        element.tex   = texture
        element.text  = str
        element.type  = type
        element.links = links

        for &link in links {
            link.pos += element.pos
        }

        if entity != nil {
            cache.positions[entity.name] = pos.y
        }

        window.content_scroll.max = pos.y + size.y
        
        append(&cache.body, element)

    }// }}}
    
    clear(&cache.body)

    // === STATE TO BE MODIFIED ===
    pos : Vector = { window.sidebar_w + 10, window.toolbar_h + 10 }

    the_package := everything.initial_package

    place_text(everything, &pos, the_package.name, .HEADING)
    if len(the_package.docs) > 0 {
        place_text(everything, &pos, the_package.name, .PARAGRAPH)
    }

    for _, entity in the_package.entities {
        if entity.kind == .Type_Name {
            place_text(everything, &pos, format_code_block(entity), .CODE_BLOCK, entity = entity)

            if len(entity.docs) != 0 {
                place_text(everything, &pos, entity.docs, .PARAGRAPH)
            }
        }
    }


    for _, entity in the_package.entities {
        if entity.kind == .Procedure {
            place_text(everything, &pos, format_code_block(entity), .CODE_BLOCK, entity = entity)

            if len(entity.docs) != 0 {
                place_text(everything, &pos, entity.docs, .PARAGRAPH)
            }
        }
    }


    for _, entity in the_package.entities {
        if entity.kind == .Proc_Group {
            place_text(everything, &pos, format_code_block(entity), .CODE_BLOCK, entity = entity)

            if len(entity.docs) != 0 {
                place_text(everything, &pos, entity.docs, .PARAGRAPH)
            }
        }
    }

    for _, entity in the_package.entities {
        if entity.kind == .Constant || entity.kind == .Variable {
            place_text(everything, &pos, format_code_block(entity), .CODE_BLOCK, entity = entity)

            if len(entity.docs) != 0 {
                place_text(everything, &pos, entity.docs, .PARAGRAPH)
            }
        }
    }

}// }}}

cache_sidebar :: proc() {// {{{
    cache_text :: proc(str: string, large: bool) -> (texture: Texture, size: Vector) {
        text :: ttf.RenderText_Blended
        cstr :: strings.clone_to_cstring        // TODO I can now replace with fast_str_to_cstr
                                                // OR later replace with custom RenderText
        font  := fonts.large if large else fonts.regular
        color : RGBA = colorscheme[.FG2]
        
        surface := text(font, cstr(str, context.temp_allocator), color)
        defer  sdl.FreeSurface(surface)
        return sdl.CreateTextureFromSurface(window.renderer, surface), { surface.w, surface.h }
    }

    files := make([dynamic] string, 0, 128, context.temp_allocator)
    get_files :: proc(out: ^[dynamic] string, dir: [] os.File_Info, level := 0) {
        for item in dir {
            append(out, item.name)

            if item.type == .Directory {
                file_list, err1 := os.read_all_directory_by_path(item.fullpath, context.temp_allocator)
                if err1 == nil {
                    get_files(out, file_list, level + 1)
                }
            }
        }
    }

    sidebar_click_event_handler :: proc(target: ^Button) -> bool {
        everything, ok := docl.load((transmute(^string) target.userdata)^)
        if ok {
            cache_body(everything)
        }
        return false
    }
    
    file_list, err1 := os.read_all_directory_by_path("cache", context.temp_allocator)
    if err1 != nil { /*rebuild cache*/ panic("need to rebuild cache") }
    get_files(&files, file_list)

    slice.sort(files[:])
    
    pos := Vector { 0, window.toolbar_h }
    path: [8] string

    for file in files {
        filepath := file
        file := file
        if strings.ends_with(file, ".odin-doc") { 
            file = file[:len(file) - len(".odin-doc")] 
        }

        parts := strings.split(file, "@")
        level := i32(len(parts)) - 1
        for part, i in parts {
            if part == path[i] do continue
            path[i] = part

            if i == len(parts) - 1 do break

            button: Button
            button.pos = pos + { i32(i) * 16, 0 }
            button.tex, button.size = cache_text(part, i == 0)
            button.click = sidebar_click_event_handler
            button.userdata = rawptr(new_clone(fmt.aprint("./cache/", filepath, sep = "")))

            append(&cache.sidebar, button)
            
            pos.y += button.size.y + 2
               
        }

        for i in (len(parts)+1)..<8 { path[i] = "" }

        button: Button
        button.pos = pos + { level * 16, 0 }
        button.tex, button.size = cache_text(parts[len(parts) - 1], false)
        button.click = sidebar_click_event_handler
        button.userdata = rawptr(new_clone(fmt.aprint("./cache/", filepath, sep = "")))

        append(&cache.sidebar, button)
        
        pos.y += button.size.y + 2
        window.sidebar_scroll.max = pos.y
    }


}// }}}

cache_toolbar :: proc() {
    // and as for buttons:
    // ? ? ? ? ? ~ .* /search  \/  /\   ? ? ? ?

    clear(&cache.toolbar)

    button: Button

    make_toolbar_search()
}

display_error :: proc(format: string, values: ..any) {
    fmt.printf(format, ..values)
}
