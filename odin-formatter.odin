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

format_statement :: proc(code: string) -> string {
    tokenizer: odin.Tokenizer
    odin.init(&tokenizer, code, "") // TODO CHECK WHAT IS THE DEFAULT_ERORR_HANDLER!!!
    
    result, err1 := strings.builder_make_len_cap(0, int(f64(len(code)) * 1.5), context.temp_allocator)
    assert(err1 == .None)

    type: DeclType
    prev: odin.Token

    for {
        token := odin.scan(&tokenizer)
        if token.kind == .EOF do break
        if token.text == "" do continue
        defer prev = token

        tokenizer_copy := tokenizer
        next := odin.scan(&tokenizer_copy)
        
        #partial switch token.kind {
        case .Proc:         
            if next.kind == .String { next = odin.scan(&tokenizer_copy) } 
            if next.kind == .Hash   { odin.scan(&tokenizer_copy); next = odin.scan(&tokenizer_copy) }
            type = .PROC_GROUP if next.text == "{" else .PROC
        case .Enum, .Union: type = .ENUM_OR_UNION
        case .Struct:       type = .STRUCT
        case:
        }
        
        // ======== PRE TOKEN =======
        if prev.text != "" {
            for symbol in SPACE_AROUND {
                if token.text[0] == symbol && prev.text[0] != symbol {
                    strings.write_byte(&result, ' ')
                }
            }
            if is_identifier_char(token.text[0]) && is_identifier_char(prev.text[0]) {
                strings.write_byte(&result, ' ')
            }
        }
        // ==========================

        // ============ TOKEN =======
        strings.write_string(&result, token.text)
        // ==========================

        // ======= POST TOKEN =======
        for symbol in SPACE_AROUND {
            if prev.text == "" do break
            if token.text[0] == symbol && next.text[0] != symbol {
                strings.write_byte(&result, ' ')
            }
        }

        if type == .PROC_GROUP || type == .STRUCT || type == .ENUM_OR_UNION {
            
            if next.text == "}" {
                strings.write_string(&result, "\n")
            } else 
            if token.text == "{" || token.text == "," { 
                strings.write_string(&result, "\n    ")
            }
        }

        if token.text == "}" {
            strings.write_byte(&result, '\n')
        }
        // ==========================
        
    
    }
    
    return strings.to_string(result)
}

odin_lookahead :: proc(tokenizer: odin.Tokenizer) -> odin.Token {
    tokenizer := tokenizer
    return odin.scan(&tokenizer)
}

format_curly_body :: proc(writer: ^strings.Builder, body: string) -> (to_skip: int) {
    
    return
} 

format_code_block :: proc(header: ^Header, entity: Declaration) -> string {

    name := doc.from_string(&header.base, entity.name) 
    body := doc.from_string(&header.base, entity.init_string) 

    tokenizer: odin.Tokenizer
    odin.init(&tokenizer, body, "") // TODO CHECK WHAT IS THE DEFAULT_ERROR_HANDLER!!!
    
    result, err1 := strings.builder_make_len_cap(0, int(f64(len(body)) * 1.5), context.temp_allocator)
    assert(err1 == .None)
    
    // switch over the .kind shit and yeah

    switch entity.kind {
    case .Import_Name, .Library_Name, .Builtin, .Invalid:
        panic("I don't know what the fuck any of these are...")
    
    case .Type_Name, .Proc_Group,  .Constant, .Variable, .Procedure:
        strings.write_string(&result, name)
        strings.write_string(&result, " :: ")

        level: int
        for r, i in body {
            next := body[i + utf8.rune_size(r)] if i + utf8.rune_size(r) < len(body) else 0
            if r == '{' do level += 1
            if r == '}' do level -= 1

            if level > 0 {
                strings.write_rune(&result, r)
                if r == '{' || r == ',' {
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
            
            lengths : [16] int
            column  : int
            level   = 0

            for r in strings.to_string(result) {
                switch r {
                case ':' : lengths[level] = max(lengths[level], column + 1)
                case '\n': column = 0
                case '{' : level += 1
                case '}' : level -= 1
                }
                column += 1
            }
            
            column = 0
            level  = 0

            for r, i in strings.to_string(result) {
                switch r {
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




        // this when statement's branch is much more convoluted...
        // } else {
        // 
        // level  : int        // curly bracket level 0 { 1 { 2 { 3
        // lengths: [16] int   // max length from the left in each level ...16
        // column : int        // current char column

        // for r, i in body {
        //     size := utf8.rune_size(r)
        //     next := body[i + size] if i + size < len(body) else 0
        //     if r == '{' { 
        //         level += 1
        //         chars_to_the_left: int = 0
        //         for r2, j in body[i:] {
        //             if r2 == ',' do chars_to_the_left = 0
        //             if r2 == ':' {
        //                 lengths[level] = max(lengths[level], chars_to_the_left + 1)
        //                 fmt.println(lengths[level])
        //             }
        //             chars_to_the_left += 1
        //         }
        //     }
        //     if r == '}' do level -= 1

        //     if level > 0 {
        //         strings.write_rune(&result, r)
        //         column += 1
        //         if strings.starts_with(body[i + size:], ": struct") {
        //             strings.write_byte(&result, ' ')
        //         } else if next == ':' {
        //             for j in 0..<(lengths[level] - column) {
        //                 strings.write_byte(&result, ' ')
        //             }
        //         }
        //         if r == '{' || r == ',' {
        //             strings.write_byte(&result, '\n')
        //             column = level * 4
        //             for i in 0..<level {
        //                 strings.write_string(&result, "   ")
        //             }
        //             if next == ' ' do strings.pop_byte(&result)
        //         }
        //         if next == '}' {
        //             strings.write_byte(&result, '\n')
        //             column = level * 4 - 4
        //             for i in 0..<(level - 1) {
        //                 strings.write_string(&result, "   ")
        //             }
        //         }
        //     } else {
        //         strings.write_rune(&result, r)
        //     
        //     }
        // }
        // }

    
    }

    
    return strings.to_string(result)
}


/*
 
This is stupid.

Simply draw the entire texture in pure white.
Then go through the same text, measure a bunch of stuff
  and generate a color mask
  afterwards just simply blend the shit with .MULTIPLY

To measure text, there is just a MeasureUTF8 in SDL_ttf

*/


// draw_code_block :: proc(header: ^Header, entity: Declaration) -> Texture {
//     width  := window.size.x - window.sidebar_w
//     height : i32 = 400
//     masks : [4] u32 = {
//         0xff000000,
//         0x00ff0000,
//         0x0000ff00,
//         0x000000ff,
//     }
//     main_surface := sdl.CreateRGBSurface(0, width, height, 32, masks.r, masks.g, masks.b, masks.a)
//     name := doc.from_string(&header.base, entity.name)
//     text_surface := ttf.RenderUTF8_Blended(fonts.mono, strings.clone_to_cstring(name), { 255, 0, 255, 255 })
//     sdl.BlitSurface(text_surface, &text_surface.clip_rect, main_surface, &text_surface.clip_rect)
//     code := doc.from_string(&header.base, entity.init_string)
//     return sdl.CreateTextureFromSurface(window.renderer, main_surface)
// }


