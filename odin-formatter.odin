package main

import "core:fmt"
import "core:strings"
import "core:unicode/utf8"
import "core:thread"
import odin "core:odin/tokenizer"
import doc "core:odin/doc-format"
import docl "doc-loader"

import sdl "vendor:sdl2"
import ttf "vendor:sdl2/ttf"

SPACE_AROUND : [] byte : { ':', '=', '{' }

odin_look_for :: proc(code: string, needle: rune, unescaped := false) -> int {
    escaped: bool
    for r, i in code {
        if escaped {
            escaped = false
        } else {
            if r == '\\' && unescaped do escaped = true
            else if r == needle do return i
        }
    }
    return len(code)
}
odin_look_for_string :: proc(code: string, needle: string, unescaped := false) -> int {
    when MEASURE_PERFORMANCE {
        __start := tick_now() 
        defer fperf[#location().procedure] += tick_diff(__start, tick_now())
    }    
    escaped: bool
    for r, i in code {
        if escaped {
            escaped = false
        } else {
            if r == '\\' && unescaped do escaped = true
            else if strings.starts_with(code[i:], needle) do return i
        }
    }
    return len(code)
}

format_code_block :: proc(entity: ^docl.Entity) -> string {
    when MEASURE_PERFORMANCE {
        __start := tick_now() 
        defer fperf[#location().procedure] += tick_diff(__start, tick_now())
    }    
    
    // where this implementation before the library
    name := entity.name
    body := entity.body 

    tokenizer: odin.Tokenizer
    odin.init(&tokenizer, body, "") // TODO CHECK WHAT IS THE DEFAULT_ERROR_HANDLER!!!
    
    result_allocator := context.temp_allocator when CONFIG_SET_THE_CHILDREN_STRAIGHT else alloc.body

    result, err1 := strings.builder_make_len_cap(0, int(f64(len(body)) * 1.5), result_allocator)
    assert(err1 == .None)
    
    switch entity.kind {
    case .Import_Name, .Library_Name, .Builtin, .Invalid:
        panic("I don't know what the fuck any of these are...")
        // I still don't really, except .Library_Name is literally a library name, like: libc... (in ent.foreign_entity)
    
    case .Type_Name, .Proc_Group,  .Constant, .Variable, .Procedure:
        strings.write_string(&result, name)
        strings.write_string(&result, " :: ")

        split_procedure_at     : int
        should_split_procedure : bool
        procedure_closed       : bool
        if entity.kind == .Procedure { 
            should_split_procedure = (len(name) + len(body) + 4) > CONFIG_WHAT_IS_LONG_PROC 
        }

        level: int
        skip : int 
        for r, i in body {
            if skip > 0 { skip -= 1; continue }

            if strings.starts_with(body[i:], "//") do skip = odin_look_for(body[i:], '\n', false)
            if strings.starts_with(body[i:], "/*") do skip = odin_look_for_string(body[i:], "*/")
            if r == '"'  do skip = odin_look_for(body[i:], '"', true)
            if r == '`'  do skip = odin_look_for(body[i:], '"', true)
            if r == '\'' do skip = odin_look_for(body[i:], '"', true)

            next := body[i + utf8.rune_size(r)] if i + utf8.rune_size(r) < len(body) else 0
            if r == '{' do level += 1
            if r == '}' do level -= 1

            if r == '{' && next == '}' {
                strings.write_string(&result, " { }")
                skip = 1
                continue
            }

            if should_split_procedure {
                if r == '(' && split_procedure_at == 0 do split_procedure_at = i
                if r == '(' do level += 1
                if r == ')' do level -= 1
                if r == ')' && level == 0 && split_procedure_at != 0 do procedure_closed = true
            }

            if level > 0 {
                strings.write_rune(&result, r)
                if r == '{' || (r == ',' && !procedure_closed) || ( split_procedure_at == i && r == '(' ) {
                    strings.write_byte(&result, '\n')
                    for i in 0..<level {
                        strings.write_string(&result, "   ")
                    }
                    if next == ' ' do strings.pop_byte(&result)
                }
                if next == '}' {
                    strings.write_byte(&result, '\n')
                    for i in 0..<(level - 1) {
                        strings.write_string(&result, "   ")
                    }
                }
            } else {
                strings.write_rune(&result, r)
            }

        }
        
        when CONFIG_SET_THE_CHILDREN_STRAIGHT {
            result2, err2 := strings.builder_make_len_cap(0, len(result.buf) * 2, alloc.body)
            assert(err2 == .None)
            
            current_code := strings.to_string(result)

            lengths : [16] int
            column  : int
            level   = 0

            skip = 0
            for r, i in current_code {
                if skip > 0 {
                    skip -= 1
                    continue
                }

                if strings.starts_with(current_code[i:], "//") do skip = odin_look_for(current_code[i:], '\n', false)
                if strings.starts_with(current_code[i:], "/*") do skip = odin_look_for_string(current_code[i:], "*/")

                switch r {
                case '"' : skip = odin_look_for(current_code[i:], '"', true)
                case '`' : skip = odin_look_for(current_code[i:], '"', true)
                case '\'' : skip = odin_look_for(current_code[i:], '"', true)

                case ':' : lengths[level] = max(lengths[level], column + 1)
                case '\n': column = 0
                case '{' : level += 1
                case '}' : level -= 1
                }
                column += 1
            }
            
            column = 0
            level  = 0
            
            skip = 0
            for r, i in current_code {
                if skip > 0 {
                    skip -= 1
                    strings.write_rune(&result2, r)
                    continue
                }

                if strings.starts_with(current_code[i:], "//") do skip = odin_look_for(current_code[i:], '\n', false)
                if strings.starts_with(current_code[i:], "/*") do skip = odin_look_for_string(current_code[i:], "*/")

                switch r {
                case '"' : skip = odin_look_for(current_code[i:], '"', true)
                case '`' : skip = odin_look_for(current_code[i:], '"', true)
                case '\'' : skip = odin_look_for(current_code[i:], '"', true)

                case ':': 
                    if level == 0 do break
                    if strings.starts_with(strings.to_string(result)[i:], ": struct") {
                        strings.write_byte(&result2, ' ')
                        break
                    }
                    for _ in 0..<(lengths[level] - column) do strings.write_byte(&result2, ' ')
                case '\n': column = 0
                case '{' : level += 1
                case '}' : level -= 1
                }
                strings.write_rune(&result2, r)
                column += 1
            }

            return strings.to_string(result2)
        
        }

    }
    
    return strings.to_string(result)
}

find_color :: proc(token: odin.Token) -> RGBA {
    when MEASURE_PERFORMANCE {
        __start := tick_now() 
        defer fperf[#location().procedure] += tick_diff(__start, tick_now())
    }    
    @static prev_color: RGBA
    @static same_color_tokens: i32

    if same_color_tokens > 0 {
        same_color_tokens -= 1
        return prev_color
    }

    if token.text == "#" {
        prev_color = proper_to_rgba(CONFIG_CODE_DIRECTIVE)
        same_color_tokens = 1
        return prev_color
    }

    switch {
    case odin.is_digit(utf8.rune_at(token.text, 0)): return proper_to_rgba(CONFIG_CODE_NUMBER)
    case odin.is_operator(token.kind) : return proper_to_rgba(CONFIG_CODE_SYMBOL)
    case odin.is_assignment_operator(token.kind) : return proper_to_rgba(CONFIG_CODE_NUMBER)
    case odin.is_literal(token.kind) : return proper_to_rgba(CONFIG_CODE_NAME)
    case odin.is_keyword(token.kind) : return proper_to_rgba(CONFIG_CODE_KEYWORD) 
    }

    return { 255, 255, 255, 255 }
}


// TODO ideally, make a version with a font atlast
// that users with slower PCs may choose to enable
// or just never render everything?
cache_code_block :: proc(everything: docl.Everything, code_block: string) -> (main: ^sdl.Surface, links: [] HyperLink) {
    when MEASURE_PERFORMANCE {
        __start := tick_now() 
        defer fperf[#location().procedure] += tick_diff(__start, tick_now())
    }    
    text :: ttf.RenderUTF8_Blended
    // text :: proc(font: Font, text: cstring, fg: sdl.Color) -> ^sdl.Surface { return sdl.CreateRGBSurfaceWithFormat(0, 1, 1, 32, auto_cast sdl.PixelFormatEnum.ARGB8888) }
    
    lines: i32
    longest_line: string
    {
        line_start: int
        for r, i in code_block {
            if r == '\n' {
                lines += 1
                line_start = i
            }
            if len(longest_line) < i - line_start {
                longest_line = code_block[line_start:i]
            }
        }
    }

    entire_width, font_height: i32
    longest_line_cstr, ll_r, ll_i := corrupt_to_cstr(longest_line)
    ttf.SizeText(fonts.mono, longest_line_cstr, &entire_width, &font_height)
    uncorrupt_cstr(longest_line_cstr, ll_r, ll_i)

    width  := window.size.x - window.sidebar_w
    height := (font_height + CONFIG_CODE_LINE_SPACING) * (lines + 2)
    main    = sdl.CreateRGBSurfaceWithFormat(0, width, height, 32, auto_cast sdl.PixelFormatEnum.ARGB8888)
    sdl.SetSurfaceBlendMode(main, .NONE) // so I don't blend the textures twice

    pos: Vector

    toker: odin.Tokenizer
    odin.init(&toker, code_block, "")

    link_list := make([dynamic] HyperLink, alloc.body)
    
    prev_token: odin.Token
    for {
        token := odin.scan(&toker)
        defer prev_token = token
        if token.kind == .EOF do break
        if token.text == "" do continue

        text_between := code_block[ prev_token.pos.offset + len(prev_token.text) : token.pos.offset ]// {{{
        if len(text_between) > 0 {
            if text_between[0] == '\n' {
                pos.x = 0
                pos.y += font_height + CONFIG_CODE_LINE_SPACING
                text_between = text_between[1:]
            }
            if len(text_between) > 0 {
                space_w, scrap: i32

                text_between_cstr, tb_r, tb_i := corrupt_to_cstr(text_between)
                ttf.SizeText(fonts.mono, text_between_cstr, &space_w, &scrap)
                uncorrupt_cstr(text_between_cstr, tb_r, tb_i)
                pos.x += space_w
            }
        }// }}}
        
        if odin.is_newline(token) {
            pos.x = 0
            pos.y += font_height + CONFIG_CODE_LINE_SPACING
            continue
        }
    
        token_cstr, t_r, t_i := corrupt_to_cstr(token.text)
        surface := text(fonts.mono, token_cstr, find_color(token)) 
        uncorrupt_cstr(token_cstr, t_r, t_i)
        sdl.BlitSurface(surface, &surface.clip_rect, main, &{ pos.x, pos.y, surface.w, surface.h })

        if target, ok := everything.initial_package.entities[token.text]; ok {
            hyperlink := HyperLink { pos = pos, size = { surface.w, surface.h }, target = target }
            append(&link_list, hyperlink)
        }

        pos += { surface.w, 0 }
        sdl.FreeSurface(surface)

    }

    return main, link_list[:]
}

CodeBlockCacheData :: struct {
    out             : ^[dynamic] Box,
    out_index       : int,
    everything      : docl.Everything,
    code_block      : string,
    width           : i32,
    height          : i32,
}

eat_uncached_code_block :: proc() {
    text :: ttf.RenderUTF8_Blended
    
    if len(window.current_tab.cache_queue) <= 0 do return
    data := pop_front(&window.current_tab.cache_queue)

    main := sdl.CreateRGBSurfaceWithFormat(0, data.width, data.height, 32, auto_cast sdl.PixelFormatEnum.ARGB8888)
    sdl.SetSurfaceBlendMode(main, .NONE) // so I don't blend the textures twice

    pos: Vector

    toker: odin.Tokenizer
    odin.init(&toker, data.code_block, "")

    link_list := make([dynamic] HyperLink, alloc.body)
    
    prev_token: odin.Token
    for {
        token := odin.scan(&toker)
        defer prev_token = token
        if token.kind == .EOF do break
        if token.text == "" do continue

        text_between := data.code_block[ prev_token.pos.offset + len(prev_token.text) : token.pos.offset ]// {{{
        if len(text_between) > 0 {
            if text_between[0] == '\n' {
                pos.x = 0
                pos.y += CONFIG_FONT_SIZE + CONFIG_CODE_LINE_SPACING
                text_between = text_between[1:]
            }
            if len(text_between) > 0 {
                space_w, scrap: i32

                text_between_cstr, tb_r, tb_i := corrupt_to_cstr(text_between)
                ttf.SizeText(fonts.mono, text_between_cstr, &space_w, &scrap)
                uncorrupt_cstr(text_between_cstr, tb_r, tb_i)
                pos.x += space_w
            }
        }// }}}
        
        if odin.is_newline(token) {
            pos.x = 0
            pos.y += CONFIG_FONT_SIZE + CONFIG_CODE_LINE_SPACING
            continue
        }
    
        // I so can't be arsed to corrupt the thing here...
        token_cstr := strings.clone_to_cstring(token.text, context.temp_allocator)
        surface := text(fonts.mono, token_cstr, find_color(token)) 
        sdl.BlitSurface(surface, &surface.clip_rect, main, &{ pos.x, pos.y, surface.w, surface.h })

        if target, ok := data.everything.initial_package.entities[token.text]; ok {
            hyperlink := HyperLink { pos = pos, size = { surface.w, surface.h }, target = target }
            append(&link_list, hyperlink)
        }

        pos += { surface.w, 0 }
        sdl.FreeSurface(surface)

    }

    box := data.out[data.out_index]
    for &link in link_list { link.pos += box.pos }
    data.out[data.out_index].links = link_list[:]
    data.out[data.out_index].size  = { main.w, main.h }
    data.out[data.out_index].tex   = sdl.CreateTextureFromSurface(window.renderer, main)
    sdl.FreeSurface(main)
}

cache_code_block_deferred :: proc(out: ^[dynamic] Box, out_index: int, everything: docl.Everything, code_block: string) -> (size: Vector) {
    when MEASURE_PERFORMANCE {
        __start := tick_now() 
        defer fperf[#location().procedure] += tick_diff(__start, tick_now())
    }    
    text :: ttf.RenderUTF8_Blended
    // text :: proc(font: Font, text: cstring, fg: sdl.Color) -> ^sdl.Surface { return sdl.CreateRGBSurfaceWithFormat(0, 1, 1, 32, auto_cast sdl.PixelFormatEnum.ARGB8888) }
    
    lines: i32
    longest_line: string
    {
        line_start: int
        for r, i in code_block {
            if r == '\n' {
                lines += 1
                line_start = i
            }
            if len(longest_line) < i - line_start {
                longest_line = code_block[line_start:i]
            }
        }
    }

    entire_width, font_height: i32
    longest_line_cstr, ll_r, ll_i := corrupt_to_cstr(longest_line)
    ttf.SizeText(fonts.mono, longest_line_cstr, &entire_width, &font_height)
    uncorrupt_cstr(longest_line_cstr, ll_r, ll_i)

    // width  := window.size.x - window.sidebar_w
    width  := entire_width + 32
    height := (font_height + CONFIG_CODE_LINE_SPACING) * (lines + 1)

    data := CodeBlockCacheData {
        out        = out,
        out_index  = out_index,
        everything = everything,
        code_block = code_block,
        width      = width,
        height     = height
    }

    append(&window.current_tab.cache_queue, data)

    return { width, height }
}

