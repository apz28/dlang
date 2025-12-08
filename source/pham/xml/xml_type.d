/*
 *
 * License: $(HTTP www.boost.org/LICENSE_1_0.txt, Boost License 1.0).
 * Authors: An Pham
 *
 * Copyright An Pham 2017 - xxxx.
 * Distributed under the Boost Software License, Version 1.0.
 * (See accompanying file LICENSE.txt or copy at http://www.boost.org/LICENSE_1_0.txt)
 *
 */

module pham.xml.xml_type;

nothrow @safe:

/** 
 * Code to identify what kind of encoding of an array of bytes or stream of bytes.
 * $(XmlEncodedMarker unknown) there is no encoded marker
 * $(XmlEncodedMarker utf8) utf8 encoded marker
 * $(XmlEncodedMarker utf16be) utf16be encoded marker
 * $(XmlEncodedMarker utf16le) utf16le encoded marker
 * $(XmlEncodedMarker utf32be) utf32be encoded marker
 * $(XmlEncodedMarker utf32le) utf32le encoded marker
 */
enum XmlEncodedMarker : ubyte
{
    unknown,
    utf8,
    utf16be,
    utf16le,
    utf32be,
    utf32le,
}

enum XmlNamespaceNode : ubyte
{
    none = 0, // Must start as zero
    onlyUri,
    nameUri,
}

/** 
 * Template trait to determine if S is an build in D string (string, wstring, dstring.)
 * Params:
 *   S = A type name.
 * Returns:
 *   true if S is of a type string, wstring or dstring.
 */
enum bool isXmlString(S) = is(S == string) || is(S == wstring) || is(S == dstring);

enum bool isXmlStringEx(S) = is(S == string) || is(S == wstring) || is(S == dstring)
    || is(S == const(char)[]) || is(S == const(wchar)[]) || is(S == const(dchar)[])
    || is(S == char[]) || is(S == wchar[]) || is(S == dchar[]);

/** 
 * Get element type template from one of D string type S
 */
template XmlChar(S)
if (isXmlStringEx!S)
{
    static if (is(S == string) || is(S == const(char)[]) || is(S == char[]))
        alias XmlChar = char;
    else static if (is(S == wstring) || is(S == const(wchar)[]) || is(S == wchar[]))
        alias XmlChar = wchar;
    else static if (is(S == dstring) || is(S == const(dchar)[]) || is(S == dchar[]))
        alias XmlChar = dchar;
    else
        static assert(0);
}


private:

unittest // isXmlString
{
    assert(isXmlString!string);
    assert(isXmlString!wstring);
    assert(isXmlString!dstring);

    assert(!isXmlString!(const(char)[]));
    assert(!isXmlString!(const(wchar)[]));
    assert(!isXmlString!(const(dchar)[]));

    assert(!isXmlString!(char[]));
    assert(!isXmlString!(wchar[]));
    assert(!isXmlString!(dchar[]));
}

unittest // isXmlStringEx
{
    assert(isXmlStringEx!string);
    assert(isXmlStringEx!wstring);
    assert(isXmlStringEx!dstring);

    assert(isXmlStringEx!(const(char)[]));
    assert(isXmlStringEx!(const(wchar)[]));
    assert(isXmlStringEx!(const(dchar)[]));

    assert(isXmlStringEx!(char[]));
    assert(isXmlStringEx!(wchar[]));
    assert(isXmlStringEx!(dchar[]));
}

unittest // XmlChar
{
    static assert(is(XmlChar!string == char));
    static assert(is(XmlChar!wstring == wchar));
    static assert(is(XmlChar!dstring == dchar));

    static assert(is(XmlChar!(const(char)[]) == char));
    static assert(is(XmlChar!(const(wchar)[]) == wchar));
    static assert(is(XmlChar!(const(dchar)[]) == dchar));

    static assert(is(XmlChar!(char[]) == char));
    static assert(is(XmlChar!(wchar[]) == wchar));
    static assert(is(XmlChar!(dchar[]) == dchar));
}
