/*
A wrapper around the core:odin/doc-format

The only option for you:
everything := parse(filename, allocator)    
        
(I recommend passing in a custom allocator / context.temp_allocator
because cleaning up the produced mess would be annoying)

More info may be found in './insights.md'

┏━━━━━━━━━━━━━━━━━━━━┓  parse()   
┃   .odin-doc file   ┃ --------> Everything           
┣━━━━━━━━━━━━━━━━━━━━┫             [path] All files   
┃ base │ HEADER      ┃               name             
┃──────┘             ┃               package          
┠────────────────────┨             [path] All packages
┃                    ┃               [name] Entity    
┃      DATA BLOB     ┃             [index] Entities   
┃                    ┃               pos.file         
┗━━━━━━━━━━━━━━━━━━━━┛           
&header == &header.base == raw_data(data)

*/
package doc_loader

// import "core:fmt"
import "core:strings"
import doc "core:odin/doc-format"
import os "core:os/os2"
import "core:mem/virtual"

Entity_Kind :: doc.Entity_Kind

LOAD_TYPES   :: false
FREE_RAW_DATA :: true

// Not recommended
Type :: struct {// {{{
    kind  : doc.Type_Kind,
    flags : u32le, // kind of an enum? see e.g. custom_align 
    name  : string,

    custom_align        : string,
    elem_count_len      : u32le,
    elem_counts         : [doc.Type_Elems_Cap] i64le,
    calling_convention  : string,
    
    types    : [] ^Type,
    entities : [] ^Entity,

    polymorphic_params : ^Type,
    // decorative property
    where_clauses      : [] string,
    tags               : [] string,
}// }}}

File :: struct {
    // The package that the file is in
    the_package : ^Package,
    path : string
}

Position :: struct {
    file   : ^File,
    line   : int,
    column : int,
    offset : int,
}

// All sorts of declarations.
// Everything in global scope that has the " :: "
Entity :: struct {
    kind    : doc.Entity_Kind,
    flags   : doc.Entity_Flags,
    pos     : Position,
    name    : string,
    _types   : [] ^Type, // just don't fucking use this shit... look up the package by name in file before . or whatever and then just by var name...
    body    : string,
    comment : string,
    docs    : string,

    field_group_index : int,
    // { .kind = .Library_Name, .name = "e.g.: libc", ... }
    foreign_library   : ^Entity,
    // sometimes there
    link_name         : string,
    // @(attribute=value), many boolean attrs have value = ""
    attributes        : map [string] string,
    // procedures in procedure groups
    grouped_entities  : [] ^Entity,
    where_clauses     : [] string,
}

Package :: struct {
	fullpath : string,
	name     : string,
	flags    : doc.Pkg_Flags,
	docs     : string,
	files    : [] ^File,
    // key is name (no "package." due to import aliasses). entities are from Everything.entities
	entities : map [string] ^Entity,
}

Everything :: struct {
    // nil by the time parse() is finished (unless FREE_RAW_DATA == false)
    _header  : Header, 

    // takes in the full path
    files    : map [string] ^File,
    // takes in the full path
    packages : map [string] ^Package,
    // [Entity_Index] ^Entity, entities stored by name are in package.entities
    entities : [] ^Entity,
    // [Type_Index] ^Type (empty array, unless LOAD_TYPES == true)
    types    : [] ^Type,

    // yes, all imported packages are also stored in all files :)  (as a compiler workaround)
    initial_package : ^Package,
}

@private
Header :: ^doc.Header

@private // extra private
str :: proc(raw: doc.String) -> string {
    assert(context.user_ptr != nil, "doc-loader.str() called without context.user_ptr = &header.base!")
    base := cast(^doc.Header_Base) context.user_ptr
    return strings.clone(doc.from_string(base, raw))
}

@private
load_type :: proc(everything: ^Everything, type_index: doc.Type_Index) -> ^Type {// {{{
    header := everything._header
    
    if everything.types[type_index] != nil { 
        return everything.types[type_index] 
    }

    raw_type := doc.from_array(&header.base, header.types)[type_index]

    type := new(Type)
    everything.types[type_index] = type

    type.kind  = raw_type.kind
    type.flags = raw_type.flags
    type.name  = str(raw_type.name)
    type.custom_align   = str(raw_type.custom_align)
    type.elem_count_len = raw_type.elem_count_len
    type.elem_counts    = raw_type.elem_counts
    type.calling_convention = str(raw_type.calling_convention)
    
    type.types = make([] ^Type, raw_type.types.length)
    for child_type, i in doc.from_array(&header.base, raw_type.types) {
        type.types[i] = load_type(everything, child_type)
    }

    type.entities = make([] ^Entity, raw_type.entities.length)
    for entity, i in doc.from_array(&header.base, raw_type.entities) {
        type.entities[i] = load_entity(everything, entity)
    }
    type.polymorphic_params = load_type(everything, raw_type.polymorphic_params)

    type.tags = make([] string, raw_type.tags.length)
    for tag, i in doc.from_array(&header.base, raw_type.tags) {
        type.tags[i] = str(tag)
    }

    return type
}// }}}

@private
load_entity :: proc(everything: ^Everything, entity_index: doc.Entity_Index) -> ^Entity {
    header := everything._header

    if everything.entities[entity_index] != nil { 
        return everything.entities[entity_index] 
    }

    raw_entity := doc.from_array(&header.base, header.entities)[entity_index]
    
    entity := new(Entity)
    everything.entities[entity_index] = entity

    entity.kind  = raw_entity.kind
    entity.flags = raw_entity.flags
    entity.pos   = {
        file   = load_file(everything, raw_entity.pos.file),
        line   = auto_cast raw_entity.pos.line,
        column = auto_cast raw_entity.pos.column,
        offset = auto_cast raw_entity.pos.offset,
    }

    if entity.pos.file == nil do return nil
    
    entity.name    = str(raw_entity.name)
    entity.body    = str(raw_entity.init_string)
    entity.comment = str(raw_entity.comment)
    entity.docs    = str(raw_entity.docs)

    when LOAD_TYPES {
        all_types := doc.from_array(&header.base, header.types)
        ent_types := doc.from_array(&header.base, all_types[raw_entity.type].types)

        entity._types = make([] ^Type, len(ent_types))
        for type_index, i in ent_types {
            entity._types[i] = load_type(everything, type_index)
        }
    }

    entity.field_group_index = auto_cast raw_entity.field_group_index
    entity.foreign_library   = load_entity(everything, raw_entity.foreign_library)
    entity.link_name         = str(raw_entity.link_name)

    for attribute in doc.from_array(&header.base, raw_entity.attributes) {
        // I FEEL like I don't need to clone the map key's string...
        entity.attributes[str(attribute.name)] = str(attribute.value)
    }

    ihatethis: int
    entity.grouped_entities = make([] ^Entity, raw_entity.grouped_entities.length)
    for group_entity, i in doc.from_array(&header.base, raw_entity.grouped_entities) {
        entity.grouped_entities[i - ihatethis] = load_entity(everything, group_entity)
        if entity.grouped_entities[i - ihatethis] == nil {
            ihatethis += 1
        }
    }
    entity.grouped_entities = entity.grouped_entities[:len(entity.grouped_entities) - ihatethis]

    entity.where_clauses = make([] string, raw_entity.where_clauses.length)
    for where_clause, i in doc.from_array(&header.base, raw_entity.where_clauses) {
        entity.where_clauses[i] = str(where_clause)
    }

    return entity
}

@private
load_package :: proc(everything: ^Everything, pkg: doc.Pkg_Index) -> ^Package {
    header := everything._header

    raw_package := doc.from_array(&header.base, header.pkgs)[pkg]

    fullpath := str(raw_package.fullpath)
    if fullpath in everything.packages {
        return everything.packages[fullpath]
    }

    the_package := new(Package)
    everything.packages[fullpath] = the_package

    the_package.fullpath = fullpath 
    the_package.name     = str(raw_package.name)
    the_package.flags    = raw_package.flags
    the_package.docs     = str(raw_package.docs)

    if len(the_package.name) == 0 { 
        // for the "base:builtin" package
        return nil
    }

    the_package.files = make([] ^File, raw_package.files.length)
    ihatethis: int 
    for index, i in doc.from_array(&header.base, raw_package.files) {
        the_package.files[i - ihatethis] = load_file(everything, index)
        if the_package.files[i] == nil {
            ihatethis += 1
        }
    }
    the_package.files = the_package.files[:len(the_package.files) - ihatethis]
    
    for entry, i in doc.from_array(&header.base, raw_package.entries) {
        entity := load_entity(everything, entry.entity)
        if entity == nil { continue }
        the_package.entities[entity.name] = entity
    }

    return the_package
}

@private
load_file :: proc(everything: ^Everything, file_index: doc.File_Index) -> ^File {
    header := everything._header

    raw_file := doc.from_array(&header.base, header.files)[file_index]

    filename := str(raw_file.name)
    if filename in everything.files {
        return everything.files[filename]
    }

    file := new(File)
    everything.files[filename] = file

    file.path        = filename
    file.the_package = load_package(everything, raw_file.pkg)
    if file.the_package == nil do return nil

    return file
}

read_documentation_file :: proc(file: string, allocator := context.allocator) -> (header: Header, ok: bool) {
    d, err1 := os.read_entire_file_from_path(file, allocator)
    if err1 != nil do return {}, false
    h, err2 := doc.read_from_bytes(d) // rawptr(h) == rawptr(d)   (pseudo-code)
    if err2 != nil do return {}, false
    return h, true
}

load :: proc(file: string, allocator := context.allocator) -> (result: Everything, ok: bool) {
    general_allocator := context.allocator

    everything: Everything
    everything._header, ok = read_documentation_file(file, general_allocator)
    if !ok do return {}, false
    defer {
        free(everything._header, general_allocator)
        everything._header = nil
    }
    header := everything._header

    context.user_ptr = &header.base
    context.allocator = allocator

    everything.entities = make([] ^Entity, header.entities.length)
    when LOAD_TYPES {
        everything._types = make([] ^Type,   header.types.length)
    }
    for _, i in doc.from_array(&header.base, header.pkgs) {
        pkg := load_package(&everything, auto_cast i)
        if pkg == nil do continue
        everything.packages[pkg.fullpath] = pkg
        if doc.Pkg_Flag.Init in pkg.flags {
            everything.initial_package = pkg
        }
    }

    return everything, true
}


FileEntities :: struct { file: string, entities: [] string, types: [] Entity_Kind }
fetch_all_entity_names :: proc(path: string, progress: ^[2] int = nil, allocator := context.allocator) -> (entities: [] FileEntities, ok: bool) {
    files, err1 := os.read_all_directory_by_path(path, allocator) 
    if err1 != nil do return {}, false

    arena: virtual.Arena
    _ = virtual.arena_init_growing(&arena)
    file_allocator := virtual.arena_allocator(&arena)

    if progress != nil do progress[1] = len(files)
    entities = make([] FileEntities, len(files))
    for file, i in files {
        if !strings.ends_with(file.name, ".odin-doc") do continue

        everything: Everything
        everything._header, ok = read_documentation_file(file.fullpath, file_allocator)
        if !ok do return {}, false

        header := everything._header
        context.user_ptr = &header.base
        context.allocator = allocator

        initial_package: doc.Pkg = doc.from_array(&header.base, header.pkgs)[0] if header.pkgs.length != 0 else {}
        for pkg in doc.from_array(&header.base, header.pkgs) {
            if doc.Pkg_Flag.Init in pkg.flags { initial_package = pkg }
        }

        ent_list  := make([] string, header.entities.length)
        type_list := make([] doc.Entity_Kind, header.entities.length)
        for entry, i in doc.from_array(&header.base, initial_package.entries) {
            entity := doc.from_array(&header.base, header.entities)[entry.entity]
            ent_list[i]  = strings.clone(doc.from_string(&header.base, entity.name), allocator)
            type_list[i] = entity.kind
        }
        entities[i] = { file = file.name, entities = ent_list, types = type_list }

        free_all(file_allocator)
        if progress != nil do progress[0] = i + 1
    }
    virtual.arena_destroy(&arena)

    return entities, true
}




when false {
main :: proc() {
    base := parse("test.odin-doc")

    // for _, pkg in base.packages {
    //     fmt.println(pkg.entities)
    //     // fmt.println(pkg.fullpath, pkg.name)
    // }

    // for _, entity in base.initial_package.entities {
    //     fmt.printfln("%#v\n", entity.grouped_entities)
    // }

    // for pkg in doc.from_array(&header.base, header.pkgs) {
    //     
    //     for entry in doc.from_array(&header.base, pkg.entries) {
    //         entity := doc.from_array(&header.base, header.entities)[entry.entity]

    //         a := doc.from_string(&header.base, entry.name)
    //         b := doc.from_string(&header.base, entity.name)
    //         if a != b { fmt.println(a, "\n", b) }
    //         fmt.println()
    //     }


    //     fmt.println("\n\n")
    // }

}
}
