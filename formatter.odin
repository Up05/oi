package main

import "core:strings"
import "core:unicode/utf8"
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
    
    result_allocator := context.temp_allocator when CONFIG_SET_CHILDREN_STRAIGHT else window.boxes.content.allocator

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
        
        when CONFIG_SET_CHILDREN_STRAIGHT {
            result2, err2 := strings.builder_make_len_cap(0, len(result.buf) * 2, window.boxes.content.allocator)
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

find_color :: proc(token: odin.Token) -> Palette {
    when MEASURE_PERFORMANCE {
        __start := tick_now() 
        defer fperf[#location().procedure] += tick_diff(__start, tick_now())
    }    
    @static prev_color: Palette
    @static same_color_tokens: i32

    if same_color_tokens > 0 {
        same_color_tokens -= 1
        return prev_color
    }

    if token.text == "#" {
        prev_color = .RED2
        same_color_tokens = 1
        return prev_color
    }

    switch {
    case odin.is_digit(utf8.rune_at(token.text, 0)): return .AQUA1
    case odin.is_operator(token.kind) : return .AQUA2
    case odin.is_assignment_operator(token.kind) : return .RED1
    case odin.is_literal(token.kind) : return .FG1
    case odin.is_keyword(token.kind) : return .RED2 
    }

    return .FG1
}
render_code_block :: proc(box: ^Box) {
    the_text, the_text_size := render_text(box.text, box.font, .DBG)
    if box.min_size == box.tex_size { box.min_size = the_text_size }
    box.tex_size = the_text_size

    box.tex = sdl.CreateTexture(window.renderer, .ARGB8888, .TARGET, the_text_size.x, the_text_size.y)
    handle_premultiplied_alpha_compositing(box.tex)
    sdl.SetRenderTarget(window.renderer, box.tex)
    defer sdl.SetRenderTarget(window.renderer, nil)

    full_rect := sdl.Rect { 0, 0, the_text_size.x, the_text_size.y }
    sdl.RenderCopy(window.renderer, the_text, &full_rect, &full_rect)

    pos: Vector

    toker: odin.Tokenizer
    odin.init(&toker, box.text, "")

    link_list := make([dynamic] HyperLink, box.allocator)
    
    prev_token: odin.Token
    for {
        token := odin.scan(&toker)
        defer prev_token = token
        if token.kind == .EOF do break
        if token.text == "" do continue

        text_between := box.text[ prev_token.pos.offset + len(prev_token.text) : token.pos.offset ]// {{{
        if len(text_between) > 0 {
            if text_between[0] == '\n' {
                pos.x = 0
                pos.y += CONFIG_FONT_SIZE + 3
                text_between = text_between[1:]
            }
            if len(text_between) > 0 {
                pos.x += measure_text(text_between, box.font).x
            }
        }// }}}
        
        if odin.is_newline(token) {
            pos.x = 0
            pos.y += CONFIG_FONT_SIZE + CONFIG_CODE_LINE_SPACING
            continue
        }
    
        // sub_size := render_text_onto(main, pos, token.text, box.font, find_color(token))
        sub_size := measure_text(token.text, box.font)

        hl := COLORS[find_color(token)]
        sdl.SetRenderDrawBlendMode(window.renderer, .MOD)
        draw_rectangle(pos + { 0, 1 }, sub_size -  { 0, 2 }, find_color(token))
        sdl.SetRenderDrawBlendMode(window.renderer, .BLEND)

        if target, ok := current_tab().everything.initial_package.entities[token.text]; ok {
            hyperlink := HyperLink { pos = pos, size = sub_size, target = target }
            if len(link_list) > 0 {
                draw_line_rgba(
                    { pos.x, pos.y + sub_size.y }, 
                    { pos.x + sub_size.x, pos.y + sub_size.y }, 
                    brighten(COLORS[.BLUE1], 0.8)
                )
                draw_line_rgba(
                    { pos.x, pos.y + sub_size.y - 1 }, 
                    { pos.x + sub_size.x, pos.y + sub_size.y - 1 }, 
                    brighten(COLORS[.BLUE1], 0.8)
                )
            }
            append(&link_list, hyperlink)
        }

        pos += { sub_size.x, 0 }

    }

    box.links    = link_list[:]
}
