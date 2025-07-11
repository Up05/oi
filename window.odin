package main

import "base:runtime"
import "core:fmt"
import "core:strings"
import "core:slice"
import os "core:os/os2"
import sdl "vendor:sdl2"
import "vendor:sdl2/ttf"
import doc "core:odin/doc-format"

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

TextType :: enum { HEADING, PARAGRAPH, CODE_BLOCK, HYPERLINK }
TextBox  :: struct {
    pos   : Vector,
    size  : Vector,
    tex   : Texture,
    text  : string,
    type  : TextType,
    links : [] Button
}

ClickEvent :: proc(target: ^Button) -> bool

Button   :: struct {
    pos   : Vector,
    size  : Vector,
    tex   : Texture,
    click : ClickEvent,

    userdata : rawptr,
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

    content_scroll : struct { pos: i32, vel: f32 }, 
    sidebar_scroll : struct { pos: i32, vel: f32 }, 
}

fonts : struct {
    regular : ^ttf.Font,
    mono    : ^ttf.Font,
    large   : ^ttf.Font
}

cache : struct {
    body    : [dynamic] TextBox,
    sidebar : [dynamic] Button,
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

    window.toolbar_h = 32
    window.sidebar_w = 256

    sdl.GetWindowSize(window.handle, &window.size.x, &window.size.y)
    cache_body(read_documentation_file("cache/core@os.odin-doc"))
    cache_sidebar()


}// }}}

handle_resize :: proc() {
    prev_size := window.size
    sdl.GetWindowSize(window.handle, &window.size.x, &window.size.y)

    // rebuild the cache...
}


render_frame :: proc() {
    sdl.GetMouseState(&window.mouse.x, &window.mouse.y)

    apply_scroll :: proc(scroll: ^struct { pos: i32, vel: f32 }) {
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

    for element in cache.body {
        offset_y := window.content_scroll.pos

        using element
        sdl.RenderCopy(window.renderer, tex, 
            &{ 0, 0, size.x, size.y }, &{ pos.x, pos.y + offset_y, size.x, size.y })

    }

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

    // ============================= TOOLBAR ============================= 

    bar  = colorscheme[.BG2]
    sdl.SetRenderDrawColor(window.renderer, bar.r, bar.g, bar.b, bar.a)
    sdl.RenderFillRect(window.renderer, &{ 0, 0, window.size.x, window.toolbar_h })

    
}

cache_body :: proc(data: [] byte, header: ^Header) {
    is_any_kind :: proc(a: doc.Entity_Kind, b: ..doc.Entity_Kind) -> bool { return is_any(a, ..b) }

    // same as doc.from_string, oops
    to_string :: proc(data: [] byte, raw: doc.String) -> string {
        return transmute(string)( 
            runtime.Raw_String { 
                data = transmute([^] u8) (transmute(u64)(raw_data(data)) + u64(raw.offset)), 
                len  = int(raw.length) 
            })
    }

    cache_text :: proc(str: string, type: TextType) -> (texture: Texture, size: Vector) {// {{{
        text :: ttf.RenderUTF8_Blended_Wrapped
        cstr :: strings.clone_to_cstring        // TODO I can now replace with fast_str_to_cstr
                                                // OR later replace with custom RenderText
        font  := fonts.regular
        color : RGBA = { 127, 0, 0, 255 }
        switch type {
        case .HEADING   : font = fonts.large;   color = colorscheme[.FG1]
        case .PARAGRAPH :                       color = colorscheme[.FG1]
        case .CODE_BLOCK: font = fonts.mono;    color = { 255, 255, 255, 255 } // colorscheme[.CODE]
        case .HYPERLINK :                       color = colorscheme[.BLUE]
        }
        
        if type == .CODE_BLOCK {
            s := cache_code_block(str)
            defer  sdl.FreeSurface(s)
            return sdl.CreateTextureFromSurface(window.renderer, s), { s.w, s.h }
        }

        surface := text(font, cstr(str, context.temp_allocator), color, u32(window.size.x - window.sidebar_w))
        defer  sdl.FreeSurface(surface)
        return sdl.CreateTextureFromSurface(window.renderer, surface), { surface.w, surface.h }
    }

    place_text :: proc(pos: ^Vector, str: string, type: TextType, caller := #caller_location) {
        fmt.assertf(str != "", "called from: %v\n", caller)
        texture : Texture
        size    : Vector
        element : TextBox
        
        texture, size = cache_text(str, type)
        defer  pos.y += size.y + 4

        element.pos  = pos^
        element.size = size
        element.tex  = texture
        element.text = str
        element.type = type
        // links maybe later?
        append(&cache.body, element)

    }// }}}
    
    clear(&cache.body)

    // === STATE TO BE MODIFIED ===
    pos : Vector = { window.sidebar_w + 10, window.toolbar_h + 10 }

    the_package: Package
    for i in 0..<header.pkgs.length {
        p := doc.from_array(&header.base, header.pkgs)[i]
        if .Init in p.flags do the_package = p
    }


    fmt.println(to_string(data, the_package.name))

    place_text(&pos, to_string(data, the_package.name), .HEADING)
    if the_package.docs.length != 0 {
        place_text(&pos, to_string(data, the_package.docs), .PARAGRAPH)
    }

    entities := doc.from_array(&header.base, header.entities)
    entries := doc.from_array(&header.base, the_package.entries)

    for entry in entries {
        declaration := entities[entry.entity]
        if is_any_kind(declaration .kind, .Type_Name) {
            code := fmt.aprint(
                      to_string(data, declaration.name), 
                      "::", 
                      to_string(data, declaration.init_string), 
                      allocator = context.temp_allocator)

            place_text(&pos, format_code_block(header, declaration), .CODE_BLOCK)

            if declaration.docs.length != 0 {
                place_text(&pos, to_string(data, declaration.docs), .PARAGRAPH)
            }
        }
    }


    for entry in entries {
        declaration := entities[entry.entity]
        if is_any_kind(declaration .kind, .Procedure) {
            code := fmt.aprint(
                      to_string(data, declaration.name), 
                      "::", 
                      to_string(data, declaration.init_string), 
                      allocator = context.temp_allocator)

            place_text(&pos, format_code_block(header, declaration), .CODE_BLOCK)

            if declaration.docs.length != 0 {
                place_text(&pos, to_string(data, declaration.docs), .PARAGRAPH)
            }
        }
    }
    
    for entry in entries {
        declaration := entities[entry.entity]
        if is_any_kind(declaration .kind, .Proc_Group) {
            code := fmt.aprint(
                      to_string(data, declaration.name), 
                      "::", 
                      to_string(data, declaration.init_string), 
                      allocator = context.temp_allocator)

            place_text(&pos, format_code_block(header, declaration), .CODE_BLOCK)

            if declaration.docs.length != 0 {
                place_text(&pos, to_string(data, declaration.docs), .PARAGRAPH)
            }
        }
    }

    for entry in entries {
        declaration := entities[entry.entity]
        if is_any_kind(declaration .kind, .Constant) {
            code := fmt.aprint(
                      to_string(data, declaration.name), 
                      "::", 
                      to_string(data, declaration.init_string), 
                      allocator = context.temp_allocator)

            place_text(&pos, format_code_block(header, declaration), .CODE_BLOCK)

            if declaration.docs.length != 0 {
                place_text(&pos, to_string(data, declaration.docs), .PARAGRAPH)
            }
        }
    }

    for entry in entries {
        declaration := entities[entry.entity]
        if is_any_kind(declaration .kind, .Variable) {
            code := fmt.aprint(
                      to_string(data, declaration.name), 
                      "::", 
                      to_string(data, declaration.init_string), 
                      allocator = context.temp_allocator)

            place_text(&pos, format_code_block(header, declaration), .CODE_BLOCK)

            if declaration.docs.length != 0 {
                place_text(&pos, to_string(data, declaration.docs), .PARAGRAPH)
            }
        }
    }


}

//   // caches all of the text for the main documentation body.
//   //    | A | B | C | D |
//   // ---+----------------
//   // a  |  xxxxxxxxxxxx
//   // b  |  xxxxxxxxxxxx
//   //  c |  xxxxxxxxxxxx
//   //    |  xxxxxxxxxxxx
//   cache_body :: proc(the_package: Package) {// {{{
//       cache_text :: proc(str: string, type: TextType) -> (texture: Texture, size: Vector) {
//           text :: ttf.RenderText_Blended_Wrapped
//           cstr :: strings.clone_to_cstring        // TODO I can now replace with fast_str_to_cstr
//                                                   // OR later replace with custom RenderText
//           font  := fonts.regular
//           color : RGBA = { 127, 0, 0, 255 }
//           switch type {
//           case .HEADING   : font = fonts.large;   color = colorscheme[.FG1]
//           case .PARAGRAPH :                       color = colorscheme[.FG1]
//           case .CODE_BLOCK: font = fonts.mono;    color = colorscheme[.CODE]
//           case .HYPERLINK :                       color = colorscheme[.BLUE]
//           }
//           
//           surface := text(font, cstr(str, context.temp_allocator), color, u32(window.size.x - window.sidebar_w))
//           defer  sdl.FreeSurface(surface)
//           return sdl.CreateTextureFromSurface(window.renderer, surface), { surface.w, surface.h }
//       }
//   
//       place_text :: proc(pos: ^Vector, str: string, type: TextType) {
//           assert(str != "")
//           texture : Texture
//           size    : Vector
//           element : TextBox
//           
//           texture, size = cache_text(str, type)
//           defer  pos.y += size.y + 4
//   
//           element.pos  = pos^
//           element.size = size
//           element.tex  = texture
//           element.text = str
//           element.type = type
//           // links maybe later?
//           append(&cache.body, element)
//   
//       }
//       
//       clear(&cache.body)
//   
//       // === STATE TO BE MODIFIED ===
//       pos : Vector = { window.sidebar_w + 10, window.toolbar_h + 10 }
//   
//       place_text(&pos, the_package.name, .HEADING)
//       place_text(&pos, the_package.path, .HYPERLINK)
//   
//       place_text(&pos, the_package.description, .PARAGRAPH)
//       pos.y += CONFIG_FONT_SIZE
//   
//       place_text(&pos, the_package.description, .PARAGRAPH)
//   
//       pos.y += CONFIG_FONT_SIZE
//       place_text(&pos, "TYPES", .HEADING)
//       for item in the_package.types {
//           place_text(&pos, format_statement(item.name), .CODE_BLOCK)
//           if item.comment != "" do place_text(&pos, item.comment, .PARAGRAPH)
//       }
//   
//       pos.y += CONFIG_FONT_SIZE
//       place_text(&pos, "PROCEDURE GROUPS", .HEADING)
//       for item in the_package.proc_groups {
//           place_text(&pos, format_statement(item.name), .CODE_BLOCK)
//           if item.comment != "" do place_text(&pos, item.comment, .PARAGRAPH)
//       }
//   
//       pos.y += CONFIG_FONT_SIZE
//       place_text(&pos, "PROCEDURES", .HEADING)
//       for item in the_package.procedures {
//           place_text(&pos, item.name, .CODE_BLOCK)
//           if item.comment != "" do place_text(&pos, item.comment, .PARAGRAPH)
//       }
//   
//       pos.y += CONFIG_FONT_SIZE
//       place_text(&pos, "CONSTANTS", .HEADING)
//       for item in the_package.constants {
//           place_text(&pos, item.name, .CODE_BLOCK)
//           if item.comment != "" do place_text(&pos, item.comment, .PARAGRAPH)
//       }
//   
//   }// }}}

cache_sidebar :: proc() {
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
        cache_body(read_documentation_file(
                (transmute(^string) target.userdata)^
        ))
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
    }


}


display_error :: proc(format: string, values: ..any) {
    fmt.printf(format, ..values)
}
