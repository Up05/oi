package main

import "core:fmt"
import "core:strings"
import "core:unicode/utf8"
import odin "core:odin/tokenizer"
import doc "core:odin/doc-format"

import sdl "vendor:sdl2"
import ttf "vendor:sdl2/ttf"

DeclType :: enum {
    WHATEVER,
    PROC,
    PROC_GROUP,
    STRUCT,
    ENUM_OR_UNION,
}

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

format_code_block :: proc(header: ^Header, entity: Declaration) -> string {

    name := doc.from_string(&header.base, entity.name) 
    body := doc.from_string(&header.base, entity.init_string) 

    tokenizer: odin.Tokenizer
    odin.init(&tokenizer, body, "") // TODO CHECK WHAT IS THE DEFAULT_ERROR_HANDLER!!!
    
    result, err1 := strings.builder_make_len_cap(0, int(f64(len(body)) * 1.5), context.temp_allocator)
    assert(err1 == .None)
    
    switch entity.kind {
    case .Import_Name, .Library_Name, .Builtin, .Invalid:
        panic("I don't know what the fuck any of these are...")
    
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
            result2, err2 := strings.builder_make_len_cap(0, len(result.buf) * 2, context.temp_allocator)
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

cache_code_block :: proc(code_block: string) -> Image {
    text :: ttf.RenderUTF8_Blended
    cstr :: strings.clone_to_cstring
    
    new_image :: proc(height: i32) -> Image {
        masks : [4] u32 = { 0xff000000, 0x00ff0000, 0x0000ff00, 0x000000ff, }
        return sdl.CreateRGBSurface(0, window.size.x - window.sidebar_w, height, 32, masks.r, masks.g, masks.b, masks.a)
    }
    
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
    ttf.SizeText(fonts.mono, cstr(longest_line), &entire_width, &font_height)

    main := new_image((font_height + CONFIG_CODE_LINE_SPACING) * (lines + 2))
    sdl.SetSurfaceBlendMode(main, .NONE) // so I don't blend the textures twice

    pos: Vector

    toker: odin.Tokenizer
    odin.init(&toker, code_block, "")
    
    prev_token: odin.Token
    for {
        token := odin.scan(&toker)
        defer prev_token = token
        if token.kind == .EOF do break
        if token.text == "" do continue

        text_between := code_block[ prev_token.pos.offset + len(prev_token.text) : token.pos.offset ]
        if len(text_between) > 0 {
            if text_between[0] == '\n' {
                pos.x = 0
                pos.y += font_height + CONFIG_CODE_LINE_SPACING
                text_between = text_between[1:]
            }
            if len(text_between) > 0 {
                space_w, scrap: i32
                ttf.SizeText(fonts.mono, cstr(text_between), &space_w, &scrap)
                pos.x += space_w
            }
        }
        
        if odin.is_newline(token) {
            pos.x = 0
            pos.y += font_height + CONFIG_CODE_LINE_SPACING
            continue
        }

        surface := text(fonts.mono, cstr(token.text), find_color(token)) 
        sdl.BlitSurface(surface, &surface.clip_rect, main, &{ pos.x, pos.y, surface.w, surface.h })
        pos += { surface.w, 0 }
        sdl.FreeSurface(surface)

    }

    return main
}
