/*
 * License: $(HTTP www.boost.org/LICENSE_1_0.txt, Boost License 1.0).
 * Authors: An Pham
 *
 * Copyright An Pham 2025 - xxxx.
 * Distributed under the Boost Software License, Version 1.0.
 * (See accompanying file LICENSE.txt or copy at http://www.boost.org/LICENSE_1_0.txt)
 *
 */
module pham.json.json_type;

import pham.utl.utl_array_dictionary;

nothrow @safe:

enum JSONFloatLiteralType : ubyte
{
    none,  /// Not a special float string literal
    nnan,  /// Floating point negative NaN literal
    pnan,  /// Floating point NaN literal
    ninf,  /// Floating point negative Infinity literal
    pinf,  /// Floating point Infinity literal
}

/**
 * String literals used to represent special values within JSON strings.
 */
enum JSONLiteral : string
{
    null_ = "null",     /// String representation of null
    false_ = "false",   /// String representation of boolean false
    true_ = "true",     /// String representation of boolean true
    nnan = "-NaN",      /// String representation of floating point negative NaN
    pnan = "NaN",       /// String representation of floating point positive NaN
    ninf = "-Infinity", /// String representation of floating point negative Infinity
    pinf = "Infinity",  /// String representation of floating point Infinity
}

/**
 * Flags that control how JSON is encoded and parsed.
 */
enum JSONOptions : ubyte
{
    none,                     /// Standard parsing and encoding
    specialFloatLiterals = 1, /// Encode NaN and Inf float values as strings
    escapeNonAsciiChars = 2,  /// Encode non-ASCII characters with a unicode escape sequence
    doNotEscapeSlash = 4,     /// Do not escape slashes '/' when encoding
    strictParsing = 8,        /// Strictly follow RFC-8259 grammar when parsing
    prettyString = 16,        /// Serialized string is formatted to be human-readable
    json5 = 32,               /// Support json version 5
    objectName = 64,          /// Serialized object property string as name (without quote)
}

JSONOptions optionsOf(scope const(JSONOptions)[] options, uint initial = 0) @nogc pure
{
    foreach (opt; options)
        initial |= opt;
    assert(initial <= ubyte.max);
    return cast(JSONOptions)initial;
}

enum JSONTokenKind : ubyte
{
    none,
    null_,       /// A null token
    false_,      /// A boolean false token
    true_,       /// A boolean true token
    integer,     /// An integer
    integerHex,
    float_,      /// A float
    string,      /// A string
    beginArray,  /// An array start token
    endArray,    /// An array end token
    beginObject, /// An object start token
    endObject,   /// An object end token
    name,        /// An object property name
    colon,       /// Colon character
    comma,       /// Comma character
    commentLine, /// A single line comment
    commentLines,/// A multi-lines comment
    error,       /// Encounter error
    eof,         /// End of file/stream
}

/**
 * JSON types - Indicates the type of a `JSONValue`.
 */
enum JSONType : ubyte
{
    null_,
    false_,
    true_,
    integer,
    float_,
    string,
    array,
    object,
}

enum JSONOptions defaultOptions = optionsOf([JSONOptions.specialFloatLiterals, JSONOptions.json5]);
enum JSONOptions defaultPrettyOptions = optionsOf([JSONOptions.specialFloatLiterals, JSONOptions.json5, JSONOptions.prettyString]);

static immutable string defaultTab = "    ";

static immutable Dictionary!(string, JSONFloatLiteralType) floatLiteralTypes;

JSONFloatLiteralType floatLiteralType(scope const(char)[] text) @nogc pure
{
    if (auto f = text in floatLiteralTypes)
        return *f;
    else
        return JSONFloatLiteralType.none;
}

pragma(inline, true)
bool isCommentTokenKind(JSONTokenKind kind) @nogc pure
{
    return kind == JSONTokenKind.commentLine || kind == JSONTokenKind.commentLines;
}

bool tryGetSpecialFloat(scope const(char)[] str, ref double val) @nogc pure
{
    static immutable double[JSONFloatLiteralType.max + 1] floats = [double.nan, -double.nan, double.nan, -double.infinity, double.infinity];
    
    const ft = floatLiteralType(str);
    
    bool trueFloat() @nogc nothrow pure @safe
    {
        pragma(inline, true)
        
        val = floats[ft];
        return true;
    }
    
    return ft == JSONFloatLiteralType.none
        ? false
        : trueFloat();
}

struct StackBuffer(ushort Size, Char)
{
nothrow @safe:

    void opOpAssign(string op : "~")(Char c)
    {
        put(c);
    }

    void opOpAssign(string op : "~")(scope const(Char)[] s)
    {
        put(s);
    }

    Char[] opSlice() @nogc return
    {
        return buffer[0..length];
    }

    pragma(inline, true)
    bool canAdd(size_t len) const @nogc
    {
        return length + len <= Size;
    }

    pragma(inline, true)
    void put(Char c) @nogc
    {
        assert(canAdd(1));

        buffer[length++] = c;
    }

    pragma(inline, true)
    void put(scope const(Char)[] s) @nogc
    {
        assert(canAdd(s.length));

        buffer[length..length + s.length] = s;
        length += s.length;
    }

    void reset() @nogc
    {
        length = 0;
    }

    string toString()
    {
        return buffer[0..length].idup;
    }

    size_t length;
    Char[Size] buffer = void;
}


private:

shared static this() nothrow @trusted
{
    debug(debug_pham_utl_utl_json) import std.stdio : writeln;

    floatLiteralTypes = () nothrow
    {
        auto result = Dictionary!(string, JSONFloatLiteralType)(16);

        // Standard texts
        result["NaN"] = JSONFloatLiteralType.pnan;
        result["-NaN"] = JSONFloatLiteralType.nnan;
        result["Infinity"] = JSONFloatLiteralType.pinf;
        result["-Infinity"] = JSONFloatLiteralType.ninf;

        // Other support texts
        result["nan"] = JSONFloatLiteralType.pnan;
        result["-nan"] = JSONFloatLiteralType.nnan;
        result["NAN"] = JSONFloatLiteralType.pnan;
        result["-NAN"] = JSONFloatLiteralType.nnan;
        result["inf"] = JSONFloatLiteralType.pinf;
        result["+inf"] = JSONFloatLiteralType.pinf;
        result["-inf"] = JSONFloatLiteralType.ninf;
        result["infinity"] = JSONFloatLiteralType.pinf;
        result["+infinity"] = JSONFloatLiteralType.pinf;
        result["-infinity"] = JSONFloatLiteralType.ninf;
        result["Infinite"] = JSONFloatLiteralType.pinf; // dlang.std.json
        result["-Infinite"] = JSONFloatLiteralType.ninf; // dlang.std.json

        debug(debug_pham_utl_utl_json) if (result.maxCollision) debug writeln(__FUNCTION__, "(result.maxCollision=", result.maxCollision,
            ", result.collisionCount=", result.collisionCount, ", result.capacity=", result.capacity, ", result.length=", result.length, ")");

        return result;
    }();
}
