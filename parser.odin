package main

import "core:fmt"
import "core:os"
import "core:os/os2"
import "core:simd"
import fp "core:path/filepath"
import doc "core:odin/doc-format"

import doc_loader "doc-loader"

Package     :: doc.Pkg
Declaration :: doc.Entity
Header      :: doc.Header

join_paths :: proc(paths: [] string) -> string { return fp.join(paths, context.temp_allocator) }
cache_everything :: proc() {
    using os2

    cache_directory :: proc(source: string, odin_root: string) {
        assert(os2.is_directory(source))

        destination, err1 := fp.rel(odin_root, source, context.temp_allocator)
        assert(err1 == nil)

        process_info: os2.Process_Desc
        process_info.command = { 
            "odin", "doc", source, 
            "-doc-format", "-all-packages", // temp
            fmt.aprintf("-out=./cache/%s", clone_and_replace_chars(destination, '/', '@'), allocator = context.temp_allocator) 
        }
        process, err2 := os2.process_start(process_info)
        state, err3 := os2.process_wait(process, 1000)
        // TODO handle err1 and err2...
        // TODO probably specify an actual timeout...


        files, err4 := os2.read_all_directory_by_path(source, context.temp_allocator)
        for file in files {
            if file.type != .Directory do continue
            cache_directory(file.fullpath, odin_root)
        }
    }


    exe_path, err1  := get_executable_directory(context.allocator)
    err2 := set_working_directory(exe_path)
    assert(err1 == nil && err2 == nil)

    odin_root := get_env("ODIN_ROOT", context.temp_allocator)

    os2.remove_all("cache")
    os2.make_directory("cache")
    
    cache_directory(join_paths({ odin_root, "base" }), odin_root)
    cache_directory(join_paths({ odin_root, "core" }), odin_root)
    cache_directory(join_paths({ odin_root, "vendor" }), odin_root)
}

read_documentation_file :: proc(file: string) -> (data: [] byte, header: ^doc.Header) {
    d, err1 := os2.read_entire_file_from_path(file, context.allocator)
    fmt.assertf(err1 == nil, "Failed to read file: '%s' with error: %v", file, err1)
    h, err2 := doc.read_from_bytes(d)
    assert(err2 == nil)
    return d, h
}



// OLD IMPLEMENTATION
//   // e.g.: a function and it's comment
//   Declaration :: struct {
//       name    : string,
//       comment : string,
//       c_lines : int,
//   }
//   
//   // odinfmt files are seperated by package
//   Package :: struct {
//       name        : string,
//       path        : string,
//       description : string,
//       files       : [] string,
//   
//       constants   : [dynamic] Declaration,
//       procedures  : [dynamic] Declaration,
//       proc_groups : [dynamic] Declaration,
//       types       : [dynamic] Declaration,
//   
//       longest_line: int,
//   }
//   
//   SIMD_LANES :: 64
//   SIMD_ARRAY :: #simd [SIMD_LANES] u8
//   
//   INDENT :: SIMD_ARRAY { 
//       '\t', '\t', '\t', '\t', '\t'
//   } 
//   
//   NEW_LINE :: SIMD_ARRAY { // fuck whoever wants to change the lanes, I guess...
//       '\n', '\n', '\n', '\n', '\n', '\n', '\n', '\n', 
//       '\n', '\n', '\n', '\n', '\n', '\n', '\n', '\n', 
//       '\n', '\n', '\n', '\n', '\n', '\n', '\n', '\n', 
//       '\n', '\n', '\n', '\n', '\n', '\n', '\n', '\n', 
//       '\n', '\n', '\n', '\n', '\n', '\n', '\n', '\n', 
//       '\n', '\n', '\n', '\n', '\n', '\n', '\n', '\n', 
//       '\n', '\n', '\n', '\n', '\n', '\n', '\n', '\n', 
//       '\n', '\n', '\n', '\n', '\n', '\n', '\n', '\n', 
//   }
//   
//   ORDERING :: SIMD_ARRAY {
//        0,  1,  2,  3,  4,  5,  6,  7, 
//        8,  9, 10, 11, 12, 13, 14, 15, 
//       16, 17, 18, 19, 20, 21, 22, 23, 
//       24, 25, 26, 27, 28, 29, 30, 31, 
//       32, 33, 34, 35, 36, 37, 38, 39, 
//       40, 41, 42, 43, 44, 45, 46, 47, 
//       48, 49, 50, 51, 52, 53, 54, 55, 
//       56, 57, 58, 59, 60, 61, 62, 63, 
//   }
//   
//   odindoc_buffer: [] byte
//   parse_file :: proc(file: string) -> Package {
//   
//       if odindoc_buffer == nil {
//           odindoc_buffer = make([] byte, 4 * 1024 * 1024)
//       }
//   
//       // ====== FILE READING ======    
//       handle, err_open := os.open(file)
//       if err_open != nil {
//           display_error("Failed to open odin documentation file at: '%s'!", file)
//       }
//   
//       n, err_read := os.read(handle, odindoc_buffer)
//       if err_read != nil {
//           display_error("Failed to open odin documentation file at: '%s'!", file)
//       }
//       
//       for i in n..<(n - n % SIMD_LANES + SIMD_LANES) { odindoc_buffer[i] = 0 }
//       buffer := odindoc_buffer[:n - n % SIMD_LANES + SIMD_LANES]
//   
//       // ====== FILE PARSING ======    
//       
//       the_package: Package
//       the_decl_list : ^[dynamic] Declaration
//   
//       path : [dynamic] Declaration // for consistency
//       files: [dynamic] Declaration // for consistency
//       description: [dynamic] byte
//   
//       // parse the  <package_name> in `package <package_name>[\r]\n`
//       if string(buffer[:len("package")]) == "package" {
//           new_line: int
//           for r, i in buffer { if r == '\n' { new_line = i; break } }
//           the_package.name = string(buffer[len("package "):new_line])
//       }
//   
//       last_line: int   
//       for i: int; i < len(buffer); i += SIMD_LANES {
//           vector := simd.from_slice(SIMD_ARRAY, buffer[i:])
//       
//           lines: [16] byte
//           simd.masked_compress_store(&lines, ORDERING, simd.lanes_eq(vector, NEW_LINE) )
//           
//           for j in 0..<len(lines) {
//               if lines[j] == 0 do break
//               defer last_line = i + int(lines[j]) + 1
//               if i + int(lines[j]) - last_line < 3 do continue
//               
//               line := string(buffer[ last_line : i + int(lines[j]) ])
//               the_package.longest_line = min(max(the_package.longest_line, len(line)), 120)
//   
//               fmt.println(line)
//               if line[2] == '\t' && len(the_decl_list^) != 0 { // comment
//                   back := &the_decl_list[len(the_decl_list) - 1]
//                   if back.comment == "" { back.comment = line; back.c_lines = 1 }
//                   else { expand_string(&back.comment, len(line) + 1); back.c_lines += 1  }
//   
//               } else if line[1] == '\t' { // declaration
//                   if len(the_decl_list^) != 0 {
//                       prev_back := &the_decl_list[len(the_decl_list) - 1]
//                       prev_back.name    = new_clone(prev_back.name[2:])^  // TODO set custom allocator
//                       prev_back.comment = new_clone(prev_back.comment)^   // TODO set custom allocator
//                   }
//                   append(the_decl_list, Declaration { line, "", 0 })
//   
//               } else if line[0] == '\t' { // category
//                   category := line[1:]
//                   switch {
//                   case starts_with(category, "constants"):    the_decl_list = &the_package.constants   
//                   case starts_with(category, "procedures"):   the_decl_list = &the_package.procedures         
//                   case starts_with(category, "proc_group"):   the_decl_list = &the_package.proc_groups
//                   case starts_with(category, "types"):        the_decl_list = &the_package.types
//                   case starts_with(category, "fullpath"):     the_decl_list = &path
//                   case starts_with(category, "files"):        the_decl_list = &files
//                   case: append_string(&description, line[1:]); append(&description, '\n')
//                   }
//               }
//           }
//       }
//   
//       the_package.description = string(description[:])
//       the_package.files = make([] string, len(files))
//       if len(path) > 0 do the_package.path  = new_clone(path[0].name)^ /* TODO set custom allocator */
//       for file, i in files { the_package.files[i] = new_clone(file.name)^ /* TODO set custom allocator */ }
//   
//       return the_package
//   } 
//   
//   starts_with :: proc(a, b: string) -> bool {
//       return len(a) >= len(b) && a[:len(b)] == b
//   }
//   
//   expand_string :: proc(str: ^string, by: int) {
//       RawString :: struct { cstr: cstring, len: int }
//       raw := cast(^RawString) str
//       raw.len += by
//   }
//   

