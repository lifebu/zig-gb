
// Order:
// Constants and Definitions.
// Types
// Functions (init/deinit). Core functions -> Helper. (Alphabetically)

const namespace_name = @import("dir_name/file_name.zig"); // NameSpace = set of function and structs.
const TypeName = @import("dir_name/TypeName.zig"); // TypeName = top-level fields (@This, struct).
// snake_case_variable_name
var global_var: i32 = undefined;
const const_name = 42;
const primitive_type_alias = f32;
const string_alias = []u8;

const StructName = struct {
    field: i32,
};
const StructAlias = StructName;
const EnumName = enum {
    ok,
    not_ok,
};

// Callable: camelCase
fn functionName(param_name: TypeName) void {
    var functionPointer = functionName;
    functionPointer();
    functionPointer = otherFunction;
    functionPointer();
}
const functionAlias = functionName;

// Returns type: TitleCase.
fn ListTemplateFunction(comptime ChildType: type, comptime fixed_size: usize) type {
    return List(ChildType, fixed_size);
}

fn ShortList(comptime T: type, comptime n: usize) type {
    return struct {
        field_name: [n]T,
        fn methodName() void {}
    };
}

// The word XML loses its casing when used in Zig identifiers.
const xml_document = 
    \\<?xml version="1.0" encoding="UTF-8"?>
    \\<document>
    \\</document>
;
const XmlParser = struct {
    field: i32,
};

// The initials BE (Big Endian) are just another word in Zig identifiers names.
fn readU32Be() u32 {}
