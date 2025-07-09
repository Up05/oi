package main

import "core:fmt"
import "core:strings"
import odin "core:odin/tokenizer"

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
