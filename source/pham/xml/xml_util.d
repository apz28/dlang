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

module pham.xml.xml_util;

import std.traits : isFloatingPoint, isIntegral;
import std.typecons : Flag;

import pham.xml.xml_exception;
import pham.xml.xml_message;
import pham.xml.xml_type;

@safe:


/** Determine XmlEncodedMarker of an array of bytes
    Params:
        s = array of bytes
    Returns:
        XmlEncodedMarker.none if s.length is less or equal to 1
        XmlEncodedMarker.utf8 if s starts with 0xEF 0xBB 0xBF
        XmlEncodedMarker.utf16be if s starts with 0xFE 0xFF
        XmlEncodedMarker.utf16le if s starts with 0xFF 0xFE
        XmlEncodedMarker.utf32be if s starts with 0x00 0x00 0xFE 0xFF
        XmlEncodedMarker.utf32le if s starts with 0xFF 0xFE 0x00 0x00
*/
XmlEncodedMarker getEncodedMarker(scope const(ubyte)[] s) nothrow pure
{
    if (s.length >= 2)
    {
        // utf8
        if (s.length >= 3 && s[0] == 0xEF && s[1] == 0xBB && s[2] == 0xBF)
            return XmlEncodedMarker.utf8;

        if (s.length >= 4)
        {
            // utf32be
            if (s[0] == 0x00 && s[1] == 0x00 && s[2] == 0xFE && s[3] == 0xFF)
                return XmlEncodedMarker.utf32be;

            // utf32le
            if (s[0] == 0xFF && s[1] == 0xFE && s[2] == 0x00 && s[3] == 0x00)
                return XmlEncodedMarker.utf32le;
        }

        // utf16be
        if (s[0] == 0xFE && s[1] == 0xFF)
            return XmlEncodedMarker.utf16be;

        // utf16le
        if (s[0] == 0xFF && s[1] == 0xFE)
            return XmlEncodedMarker.utf16le;
    }

    return XmlEncodedMarker.unknown;
}

/** Throws a XmlException if the string is not pass isName function according to the
    XML standard
    Template Params:
        AllowEmpty = consider valid if AllowEmpty is true and name.length is 0
    Params:
        name = the string to be tested
*/
void checkName(S, Flag!"AllowEmpty" AllowEmpty)(scope const(XmlChar!S)[] name)
if (isXmlStringEx!S)
{
    if (!isName!(S, AllowEmpty)(name))
    {
        if (name.length == 0)
            throw new XmlException(XmlMessage.eBlankName);
        else
            throw new XmlException(XmlMessage.eInvalidName, name.idup);
    }
}

/** Combine two string into a XML qualified name
    Params:
        prefix = one of the D string type
        localName = one of the D string type
    Returns:
        localName if prefix.length is zero
        otherwise prefix ":" localName
*/
pragma (inline, true)
S combineName(S)(S prefix, S localName) nothrow pure
if (isXmlString!S)
{
    if (prefix.length == 0)
        return localName;
    else
        return prefix ~ ":" ~ localName;
}

/** Returns true if the characters can be converted to a base character according to the XML standard
    Standards:
        $(LINK2 http://www.w3.org/TR/1998/REC-xml-19980210, XML 1.0)
        rule [66]
    Params:
        s = encoded char sequences (digit or hex form) to be converted
        c = the character to be returned
*/
bool convertToChar(S)(scope const(XmlChar!S)[] s, out dchar c) nothrow pure
if (isXmlStringEx!S)
{
    c = 0;
    if (s.length == 0)
        return false;

    if (s[0] == 'x' || s[0] == 'X')
    {
        s = s[1..$];
        if (s.length == 0)
            return false;

        foreach (d; s)
        {
            if (d >= 'a' && d <= 'f')
                c = (c * 16) + (d - 'a' + 10);
            else if (d >= 'A' && d <= 'F')
                c = (c * 16) + (d - 'A' + 10);
            else if (d >= '0' && d <= '9')
                c = (c * 16) + (d - '0');
            else if (d == ';')
                break;
            else
                return false;
        }
    }
    else
    {
        foreach (d; s)
        {
            if (d >= '0' && d <= '9')
                c = (c * 10) + (d - '0');
            else if (d == ';')
                break;
            else
                return false;
        }
    }

    return isChar(c);
}

/** Returns true if both strings are the same (case-sensitive)
    Params:
        s1 = one of D string type
        s2 = one of D string type
*/
bool equalCase(S)(scope const(XmlChar!S)[] s1, scope const(XmlChar!S)[] s2) nothrow pure
if (isXmlStringEx!S)
{
    return s1 == s2;
}

/** Returns true if both strings are the same (case-insensitive.)
    Using phobo std.uni.sicmp function
    Params:
        s1 = one of D string type
        s2 = one of D string type
*/
bool equalCaseInsensitive(S)(scope const(XmlChar!S)[] s1, scope const(XmlChar!S)[] s2) nothrow pure
if (isXmlStringEx!S)
{
    import std.uni : sicmp;
    scope (failure) assert(0, "Assume nothrow failed");

    return sicmp(s1, s2) == 0;
}

/** Returns true if subString is same from the end of s (case-sensitive)
    Params:
        s = one of D string type
        subString = one of D string type
*/
bool equalRight(S)(scope const(XmlChar!S)[] s, scope const(XmlChar!S)[] subString) nothrow pure
if (isXmlStringEx!S)
{
    auto i = s.length;
    auto j = subString.length;
    if (i < j)
        return false;

    for (; j > 0; --i, --j)
    {
        if (s[i - 1] != subString[j - 1])
            return false;
    }

    return true;
}

struct FormatGroupSpec
{
    char groupChar = '_';
    char negChar = '-';
}

struct FormatFloatSpec
{
    string fmt = "%f";
    FormatGroupSpec fmtg;
    char decimalChar = '.';

    alias fmtg this;
}

string formatFloat(N)(N n, in FormatFloatSpec spec = FormatFloatSpec.init)
if (isFloatingPoint!N)
{
    import std.format : format;
    import std.string : indexOf;

    const v = format(spec.fmt, n);
    const decimalIndex = v.indexOf(spec.decimalChar);

    if (decimalIndex >= 0)
    {
        if (decimalIndex + 1 < v.length)
            return formatGroup(v[0..decimalIndex], spec.fmtg) ~ spec.decimalChar ~ formatGroup(v[decimalIndex + 1..$], spec.fmtg);
        else
            return formatGroup(v[0..decimalIndex], spec.fmtg) ~ spec.decimalChar;
    }
    else
        return formatGroup(v, spec.fmtg);
}

struct FormatNumberSpec
{
    string fmt = "%d";
    FormatGroupSpec fmtg;

    alias fmtg this;
}

string formatNumber(N)(N n, in FormatNumberSpec spec = FormatNumberSpec.init) pure
if (isIntegral!N)
{
    import std.format : format;

    return formatGroup(format(spec.fmt, n), spec.fmtg);
}

/** Returns true if the character is a base character according to the XML standard
    Standards:
        $(LINK2 http://www.w3.org/TR/1998/REC-xml-19980210, XML 1.0)
        rule [85]
    Params:
        c = the character to be tested
*/
pragma (inline, true)
bool isBaseChar(const(dchar) c) nothrow pure
{
    return lookup(baseCharTable, c);
}

/** Returns true if the character is a character according to the XML standard
    Standards:
        $(LINK2 http://www.w3.org/TR/1998/REC-xml-19980210, XML 1.0)
        rule [2]
    Params:
        c = the character to be tested
*/
pragma (inline, true)
bool isChar(const(dchar) c) nothrow pure
{
    return (c >= 0x20 && c <= 0xD7FF)
        || (c >= 0xE000 && c <= 0x10FFFF && (c & 0x1FFFFE) != 0xFFFE) // U+FFFE and U+FFFF
        || isSpace(c);
}

/** Returns true if the character is a combining character according to the XML standard
    Standards:
        $(LINK2 http://www.w3.org/TR/1998/REC-xml-19980210, XML 1.0)
        rule [87]
    Params:
        c = the character to be tested
*/
pragma (inline, true)
bool isCombiningChar(const(dchar) c) nothrow pure
{
    return lookup(combiningCharTable, c);
}

/** Returns true if the character is a digit according to the XML standard
    Standards:
        $(LINK2 http://www.w3.org/TR/1998/REC-xml-19980210, XML 1.0)
        rule [88]
    Params:
        c = the character to be tested
*/
pragma (inline, true)
bool isDigit(const(dchar) c) nothrow pure
{
    return (c >= 0x30 && c <= 0x39) || lookup(digitTable, c);
}

/** A overloaded isDigit
*/
pragma (inline, true)
bool isDigit(const(char) c) nothrow pure
{
    return c >= 0x30 && c <= 0x39;
}

/** Returns true if the character is an extender according to the XML standard
    Standards:
        $(LINK2 http://www.w3.org/TR/1998/REC-xml-19980210, XML 1.0)
        rule [89]
    Params:
        c = the character to be tested
*/
pragma (inline, true)
bool isExtender(const(dchar) c) nothrow pure
{
    return lookup(extenderTable, c);
}

/** Returns true if the character is an ideographic character according to the XML standard
    Standards:
        $(LINK2 http://www.w3.org/TR/1998/REC-xml-19980210, XML 1.0)
        rule [86]
    Params:
        c = the character to be tested
*/
pragma (inline, true)
bool isIdeographic(const(dchar) c) nothrow pure
{
    return (c == 0x3007) || (c >= 0x3021 && c <= 0x3029) || (c >= 0x4E00 && c <= 0x9FA5);
}

/** Returns true if the character is a combining character according to the XML standard
    Standards:
        $(LINK2 http://www.w3.org/TR/1998/REC-xml-19980210, XML 1.0)
        rule [84]
    Params:
        c = the character to be tested
*/
pragma (inline, true)
bool isLetter(const(dchar) c) nothrow pure
{
    return isIdeographic(c) || isBaseChar(c);
}

/** Returns true if the character is a first character of a XML name according to the XML standard
    Standards:
        $(LINK2 http://www.w3.org/TR/1998/REC-xml-19980210, XML 1.0)
        rule [5]
    Params:
        c = the character to be tested
*/
pragma (inline, true)
bool isNameStartC(const(dchar) c) nothrow pure
{
    return c == '_' || c == ':' || isLetter(c);
}

/** Returns true if the character is a subsequecence character of a XML name according to the XML standard
    Standards:
        $(LINK2 http://www.w3.org/TR/1998/REC-xml-19980210, XML 1.0)
        rule [5]
    Params:
        c = the character to be tested
*/
pragma (inline, true)
bool isNameInC(const(dchar) c) nothrow pure
{
    return c == '_' || c == ':' || c == '-' || c == '.' ||
        isLetter(c) || isDigit(c) || isCombiningChar(c) || isExtender(c);
}

/** Returns true if the string is a combining characters according to the XML standard
    Standards:
        $(LINK2 http://www.w3.org/TR/1998/REC-xml-19980210, XML 1.0)
        rule [5]
    Template Params:
        AllowEmpty = return true if AllowEmpty is true and name.lenght is 0
    Params:
        name = the string to be tested
*/
bool isName(S, Flag!"AllowEmpty" AllowEmpty)(scope const(XmlChar!S)[] name) nothrow pure
if (isXmlStringEx!S)
{
    if (name.length == 0)
        return AllowEmpty;

    if (!isNameStartC(name[0]))
        return false;

    foreach (c; name[1..$])
    {
        if (isNameInC(c))
            continue;

        return false;
    }

    return true;
}

/** Returns true if the character is whitespace according to the XML standard
    Only the following characters are considered whitespace in XML - tab,
    carriage return, linefeed and space
    Standards:
        $(LINK2 http://www.w3.org/TR/1998/REC-xml-19980210, XML 1.0)
        rule [3]
    Params:
        c = the character to be tested
*/
pragma (inline, true)
bool isSpace(const(dchar) c) nothrow pure
{
    return c == 0x09 || c == 0x0A || c == 0x0D || c == 0x20;
}

/** Returns true if the string is all whitespace characters (using isSpace function for testing)
    Returns false if the s.lenght is 0
    Params:
        s = the string to be tested
*/
bool isSpaces(S)(scope const(XmlChar!S)[] s) nothrow pure
if (isXmlStringEx!S)
{
    foreach (c; s)
    {
        if (!isSpace(c))
            return false;
    }
    return s.length != 0;
}

/** Returns true if object parameter is class type of T
    Params:
        aObj = A class object.
*/
bool isClassType(T)(Object object) nothrow pure
{
    return (cast(T)object) !is null;
}

/** Returns true if the string is in form "D.D"
    D is any digit characters 0 to 9
    Standards:
        $(LINK2 http://www.w3.org/TR/1998/REC-xml-19980210, XML 1.0)
        relax of rule [26]
    Template Params:
        AllowEmpty = return true if AllowEmpty is true and s.length is 0
    Params:
        s = the string to be tested
*/
bool isVersionStr(S, Flag!"AllowEmpty" AllowEmpty)(const(XmlChar!S)[] s) nothrow pure
if (isXmlStringEx!S)
{
    import std.string : isNumeric;

    if (s.length == 0)
        return AllowEmpty;

    enum const(XmlChar!S) separator = '.';
    const(XmlChar!S)[] v1, v2;
    if (const r = splitNameValueD!(const(XmlChar!S)[])(s, separator, v1, v2))
    {
        if (!isNumeric(v1))
            return false;

        // There is dot separator but no value
        if (r == 2 && v2.length == 0)
            return AllowEmpty;

        return v2.length == 0 || isNumeric(v2);
    }
    else
        return false;
}

/** Returns number of code-points from left of a string
    Params:
        s = the string to be sliced
        count = how many characters that the function returns
*/
pragma (inline, true)
S leftString(S)(S s, const(size_t) count) nothrow pure
if (isXmlStringEx!S)
{
    return count >= s.length ? s : s[0..count];
}

/** Returns number of code-points from left of a string
    If s length is greater than the count, it will append "..." to the end of result
    Params:
        s = the string to be sliced
        count = how many characters that the function returns
*/
S leftStringIndicator(S)(S s, const(size_t) count) nothrow pure
if (isXmlStringEx!S)
{
    return count >= s.length ? s : s[0..count] ~ "...";
}

/** Convert from one string type to another. If both types are the same,
    returns the original value
    Params:
        s = the string that needed to be converted
    Returns:
        new string type value of s
*/
toS toUTF(fromS, toS)(fromS s)
if (isXmlString!fromS && isXmlString!toS)
{
    static if (is(fromS == toS))
        return s;
    else static if (is(toS == dstring))
    {
        import std.utf : toUTF32;

        return toUTF32(s);
    }
    else static if (is(toS == wstring))
    {
        import std.utf : toUTF16;

        return toUTF16(s);
    }
    else
    {
        import std.utf : toUTF8;

        return toUTF8(s);
    }
}

/** Returns number of code-points from right of a string
    Params:
        s = the string to be sliced
        count = how many characters that the function returns
*/
pragma (inline, true)
S rightString(S)(S s, size_t count) nothrow pure
if (isXmlStringEx!S)
{
    return count >= s.length ? s : s[$ - count..$];
}

void splitName(S)(S name, out S prefix, out S localName) nothrow pure
if (isXmlStringEx!S)
in
{
    assert(name.length != 0);
}
do
{
    import std.string : indexOf;

    const colonIndex = name.indexOf(':');
    if (colonIndex >= 0)
    {
        prefix = name[0..colonIndex];
        const nameLength = name.length;
        localName = colonIndex + 1 < nameLength ? localName = name[colonIndex + 1..nameLength] : "";
    }
    else
    {
        localName = name;
        prefix = "";
    }
}

/** Split the string into name and value separated by a character.
    If a separator character, delimiter, is not found, the name will be the pass in string
    and value will be null
    if the pass in string is empty, name and value will be null
    Params:
        s = the string to be splitted
        delimiter = a separator character
        name = string part before the aDelimiter
        value = string part after the aDelimiter
*/
int splitNameValueD(S)(S s, const(XmlChar!S) delimiter, out S name, out S value) nothrow pure
if (isXmlStringEx!S)
{
    import std.string : indexOf;

    if (s.length == 0)
    {
        name = null;
        value = null;
        return 0;
    }
    
    return splitNameValueI!S(s, s.indexOf(delimiter), name, value);
}

/** Split the string into name and value at the index, index.
    If index is equal or greater then the pass in string length, name will be the pass in string
    and value will be null
    Params:
        s = the string to be splitted
        index = a index where the string to be splitted
        name = string part before the aIndex
        value = string part after the aIndex
*/
int splitNameValueI(S)(S s, const(ptrdiff_t) index, out S name, out S value) nothrow pure
if (isXmlStringEx!S)
in
{
    assert(index < 0 || index < s.length);
}
do
{
    if (s.length == 0)
    {
        name = null;
        value = null;
        return 0;
    }

    if (index >= 0)
    {
        name = s[0..index];
        const sLength = s.length;
        value = index + 1 < sLength ? s[index + 1..sLength] : null;
        return 2;
    }
    else
    {
        name = s;
        value = null;
        return 1;
    }
}

/** Return a string of repetitive c for count times
    Params:
        c = the character that be repeated
        count = number of times c to be repeated
*/
S stringOfChar(S)(const(XmlChar!S) c, size_t count)
if (isXmlString!S)
in
{
    assert(count < (size_t.max / 2));
}
do
{
    import std.array : Appender;

    if (count != 0)
    {
        Appender!(XmlChar!S[]) buffer;
        buffer.reserve(count);
        for (; count != 0; --count)
            buffer.put(c);
        return buffer.data.idup;
    }
    else
        return "";
}

version (xmlTraceParser)
{
    import std.traits : isSomeChar;
    import pham.utl.utl_test;

    void outputXmlTraceParser(A...)(A args) nothrow
    {
        dgWriteln(args);
    }

    void outputXmlTraceParserF(Char, A...)(in Char[] fmt, A args) nothrow
    if (isSomeChar!Char)
    {
        dgWritefln(fmt, args);
    }

    void outputXmlTraceParserF0(Char, A...)(in Char[] fmt, A args) nothrow
    if (isSomeChar!Char)
    {
        dgWritef(fmt, args);
    }
}

version (xmlTraceXPathParser)
{
    import std.traits : isSomeChar;
    import pham.utl.utl_test;

    void outputXmlTraceXPathParser(A...)(A args) nothrow
    {
        dgWriteln(args);
    }

    void outputXmlTraceXPathParserF(Char, A...)(in Char[] fmt, A args) nothrow
    if (isSomeChar!Char)
    {
        dgWritefln(fmt, args);
    }
}

version (isXmlTraceProgress)
{
    import pham.utl.utl_test;

    void outputXmlTraceProgress(A...)(A args) nothrow
    {
        dgWriteln(args);
    }
}


// Any below codes are private
private:

static immutable baseCharTable = [
    [0x0041, 0x005A], [0x0061, 0x007A], [0x00C0, 0x00D6], [0x00D8, 0x00F6],
    [0x00F8, 0x00FF], [0x0100, 0x0131], [0x0134, 0x013E], [0x0141, 0x0148],
    [0x014A, 0x017E], [0x0180, 0x01C3], [0x01CD, 0x01F0], [0x01F4, 0x01F5],
    [0x01FA, 0x0217], [0x0250, 0x02A8], [0x02BB, 0x02C1], [0x0386, 0x0386],
    [0x0388, 0x038A], [0x038C, 0x038C], [0x038E, 0x03A1], [0x03A3, 0x03CE],
    [0x03D0, 0x03D6], [0x03DA, 0x03DA], [0x03DC, 0x03DC], [0x03DE, 0x03DE],
    [0x03E0, 0x03E0], [0x03E2, 0x03F3], [0x0401, 0x040C], [0x040E, 0x044F],
    [0x0451, 0x045C], [0x045E, 0x0481], [0x0490, 0x04C4], [0x04C7, 0x04C8],
    [0x04CB, 0x04CC], [0x04D0, 0x04EB], [0x04EE, 0x04F5], [0x04F8, 0x04F9],
    [0x0531, 0x0556], [0x0559, 0x0559], [0x0561, 0x0586], [0x05D0, 0x05EA],
    [0x05F0, 0x05F2], [0x0621, 0x063A], [0x0641, 0x064A], [0x0671, 0x06B7],
    [0x06BA, 0x06BE], [0x06C0, 0x06CE], [0x06D0, 0x06D3], [0x06D5, 0x06D5],
    [0x06E5, 0x06E6], [0x0905, 0x0939], [0x093D, 0x093D], [0x0958, 0x0961],
    [0x0985, 0x098C], [0x098F, 0x0990], [0x0993, 0x09A8], [0x09AA, 0x09B0],
    [0x09B2, 0x09B2], [0x09B6, 0x09B9], [0x09DC, 0x09DD], [0x09DF, 0x09E1],
    [0x09F0, 0x09F1], [0x0A05, 0x0A0A], [0x0A0F, 0x0A10], [0x0A13, 0x0A28],
    [0x0A2A, 0x0A30], [0x0A32, 0x0A33], [0x0A35, 0x0A36], [0x0A38, 0x0A39],
    [0x0A59, 0x0A5C], [0x0A5E, 0x0A5E], [0x0A72, 0x0A74], [0x0A85, 0x0A8B],
    [0x0A8D, 0x0A8D], [0x0A8F, 0x0A91], [0x0A93, 0x0AA8], [0x0AAA, 0x0AB0],
    [0x0AB2, 0x0AB3], [0x0AB5, 0x0AB9], [0x0ABD, 0x0ABD], [0x0AE0, 0x0AE0],
    [0x0B05, 0x0B0C], [0x0B0F, 0x0B10], [0x0B13, 0x0B28], [0x0B2A, 0x0B30],
    [0x0B32, 0x0B33], [0x0B36, 0x0B39], [0x0B3D, 0x0B3D], [0x0B5C, 0x0B5D],
    [0x0B5F, 0x0B61], [0x0B85, 0x0B8A], [0x0B8E, 0x0B90], [0x0B92, 0x0B95],
    [0x0B99, 0x0B9A], [0x0B9C, 0x0B9C], [0x0B9E, 0x0B9F], [0x0BA3, 0x0BA4],
    [0x0BA8, 0x0BAA], [0x0BAE, 0x0BB5], [0x0BB7, 0x0BB9], [0x0C05, 0x0C0C],
    [0x0C0E, 0x0C10], [0x0C12, 0x0C28], [0x0C2A, 0x0C33], [0x0C35, 0x0C39],
    [0x0C60, 0x0C61], [0x0C85, 0x0C8C], [0x0C8E, 0x0C90], [0x0C92, 0x0CA8],
    [0x0CAA, 0x0CB3], [0x0CB5, 0x0CB9], [0x0CDE, 0x0CDE], [0x0CE0, 0x0CE1],
    [0x0D05, 0x0D0C], [0x0D0E, 0x0D10], [0x0D12, 0x0D28], [0x0D2A, 0x0D39],
    [0x0D60, 0x0D61], [0x0E01, 0x0E2E], [0x0E30, 0x0E30], [0x0E32, 0x0E33],
    [0x0E40, 0x0E45], [0x0E81, 0x0E82], [0x0E84, 0x0E84], [0x0E87, 0x0E88],
    [0x0E8A, 0x0E8A], [0x0E8D, 0x0E8D], [0x0E94, 0x0E97], [0x0E99, 0x0E9F],
    [0x0EA1, 0x0EA3], [0x0EA5, 0x0EA5], [0x0EA7, 0x0EA7], [0x0EAA, 0x0EAB],
    [0x0EAD, 0x0EAE], [0x0EB0, 0x0EB0], [0x0EB2, 0x0EB3], [0x0EBD, 0x0EBD],
    [0x0EC0, 0x0EC4], [0x0F40, 0x0F47], [0x0F49, 0x0F69], [0x10A0, 0x10C5],
    [0x10D0, 0x10F6], [0x1100, 0x1100], [0x1102, 0x1103], [0x1105, 0x1107],
    [0x1109, 0x1109], [0x110B, 0x110C], [0x110E, 0x1112], [0x113C, 0x113C],
    [0x113E, 0x113E], [0x1140, 0x1140], [0x114C, 0x114C], [0x114E, 0x114E],
    [0x1150, 0x1150], [0x1154, 0x1155], [0x1159, 0x1159], [0x115F, 0x1161],
    [0x1163, 0x1163], [0x1165, 0x1165], [0x1167, 0x1167], [0x1169, 0x1169],
    [0x116D, 0x116E], [0x1172, 0x1173], [0x1175, 0x1175], [0x119E, 0x119E],
    [0x11A8, 0x11A8], [0x11AB, 0x11AB], [0x11AE, 0x11AF], [0x11B7, 0x11B8],
    [0x11BA, 0x11BA], [0x11BC, 0x11C2], [0x11EB, 0x11EB], [0x11F0, 0x11F0],
    [0x11F9, 0x11F9], [0x1E00, 0x1E9B], [0x1EA0, 0x1EF9], [0x1F00, 0x1F15],
    [0x1F18, 0x1F1D], [0x1F20, 0x1F45], [0x1F48, 0x1F4D], [0x1F50, 0x1F57],
    [0x1F59, 0x1F59], [0x1F5B, 0x1F5B], [0x1F5D, 0x1F5D], [0x1F5F, 0x1F7D],
    [0x1F80, 0x1FB4], [0x1FB6, 0x1FBC], [0x1FBE, 0x1FBE], [0x1FC2, 0x1FC4],
    [0x1FC6, 0x1FCC], [0x1FD0, 0x1FD3], [0x1FD6, 0x1FDB], [0x1FE0, 0x1FEC],
    [0x1FF2, 0x1FF4], [0x1FF6, 0x1FFC], [0x2126, 0x2126], [0x212A, 0x212B],
    [0x212E, 0x212E], [0x2180, 0x2182], [0x3041, 0x3094], [0x30A1, 0x30FA],
    [0x3105, 0x312C], [0xAC00, 0xD7A3]
    ];

/** Definitions from the XML specification
*/
static immutable charTable = [
    [0x0009, 0x0009], [0x000A, 0x000A], [0x000D, 0x000D], [0x0020, 0xD7FF],
    [0xE000, 0xFFFD], [0x10000, 0x10FFFF]
    ];

static immutable combiningCharTable = [
    [0x0300, 0x0345], [0x0360, 0x0361], [0x0483, 0x0486], [0x0591, 0x05A1],
    [0x05A3, 0x05B9], [0x05BB, 0x05BD], [0x05BF, 0x05BF], [0x05C1, 0x05C2],
    [0x05C4, 0x05C4], [0x064B, 0x0652], [0x0670, 0x0670], [0x06D6, 0x06DC],
    [0x06DD, 0x06DF], [0x06E0, 0x06E4], [0x06E7, 0x06E8], [0x06EA, 0x06ED],
    [0x0901, 0x0903], [0x093C, 0x093C], [0x093E, 0x094C], [0x094D, 0x094D],
    [0x0951, 0x0954], [0x0962, 0x0963], [0x0981, 0x0983], [0x09BC, 0x09BC],
    [0x09BE, 0x09BE], [0x09BF, 0x09BF], [0x09C0, 0x09C4], [0x09C7, 0x09C8],
    [0x09CB, 0x09CD], [0x09D7, 0x09D7], [0x09E2, 0x09E3], [0x0A02, 0x0A02],
    [0x0A3C, 0x0A3C], [0x0A3E, 0x0A3E], [0x0A3F, 0x0A3F], [0x0A40, 0x0A42],
    [0x0A47, 0x0A48], [0x0A4B, 0x0A4D], [0x0A70, 0x0A71], [0x0A81, 0x0A83],
    [0x0ABC, 0x0ABC], [0x0ABE, 0x0AC5], [0x0AC7, 0x0AC9], [0x0ACB, 0x0ACD],
    [0x0B01, 0x0B03], [0x0B3C, 0x0B3C], [0x0B3E, 0x0B43], [0x0B47, 0x0B48],
    [0x0B4B, 0x0B4D], [0x0B56, 0x0B57], [0x0B82, 0x0B83], [0x0BBE, 0x0BC2],
    [0x0BC6, 0x0BC8], [0x0BCA, 0x0BCD], [0x0BD7, 0x0BD7], [0x0C01, 0x0C03],
    [0x0C3E, 0x0C44], [0x0C46, 0x0C48], [0x0C4A, 0x0C4D], [0x0C55, 0x0C56],
    [0x0C82, 0x0C83], [0x0CBE, 0x0CC4], [0x0CC6, 0x0CC8], [0x0CCA, 0x0CCD],
    [0x0CD5, 0x0CD6], [0x0D02, 0x0D03], [0x0D3E, 0x0D43], [0x0D46, 0x0D48],
    [0x0D4A, 0x0D4D], [0x0D57, 0x0D57], [0x0E31, 0x0E31], [0x0E34, 0x0E3A],
    [0x0E47, 0x0E4E], [0x0EB1, 0x0EB1], [0x0EB4, 0x0EB9], [0x0EBB, 0x0EBC],
    [0x0EC8, 0x0ECD], [0x0F18, 0x0F19], [0x0F35, 0x0F35], [0x0F37, 0x0F37],
    [0x0F39, 0x0F39], [0x0F3E, 0x0F3E], [0x0F3F, 0x0F3F], [0x0F71, 0x0F84],
    [0x0F86, 0x0F8B], [0x0F90, 0x0F95], [0x0F97, 0x0F97], [0x0F99, 0x0FAD],
    [0x0FB1, 0x0FB7], [0x0FB9, 0x0FB9], [0x20D0, 0x20DC], [0x20E1, 0x20E1],
    [0x302A, 0x302F], [0x3099, 0x3099], [0x309A, 0x309A]
    ];

static immutable digitTable = [
    [0x0030, 0x0039], [0x0660, 0x0669], [0x06F0, 0x06F9], [0x0966, 0x096F],
    [0x09E6, 0x09EF], [0x0A66, 0x0A6F], [0x0AE6, 0x0AEF], [0x0B66, 0x0B6F],
    [0x0BE7, 0x0BEF], [0x0C66, 0x0C6F], [0x0CE6, 0x0CEF], [0x0D66, 0x0D6F],
    [0x0E50, 0x0E59], [0x0ED0, 0x0ED9], [0x0F20, 0x0F29]
    ];

static immutable extenderTable = [
    [0x00B7, 0x00B7], [0x02D0, 0x02D0], [0x02D1, 0x02D1], [0x0387, 0x0387],
    [0x0640, 0x0640], [0x0E46, 0x0E46], [0x0EC6, 0x0EC6], [0x3005, 0x3005],
    [0x3031, 0x3035], [0x309D, 0x309E], [0x30FC, 0x30FE]
    ];

static immutable ideographicTable = [
    [0x3007, 0x3007], [0x3021, 0x3029], [0x4E00, 0x9FA5]
    ];

string formatGroup(const(char)[] v, in FormatGroupSpec spec = FormatGroupSpec.init) nothrow pure
{
    import std.uni : byGrapheme;
    import std.range : Appender, appender, walkLength;

    char[250] buffer;
    ptrdiff_t bLen;
    ptrdiff_t cLen = v.length;
    ptrdiff_t c = 2 - (cLen % 3);
    for (ptrdiff_t i = 0; cLen > 0; ++i)
    {
        char e = v[i];
        buffer[bLen++] = e;
        if (--cLen > 0)
        {
            if (c == 1 && e != spec.negChar)
                buffer[bLen++] = spec.groupChar;
            c = (c + 1) % 3;
        }
    }
    string result = buffer[0..bLen].idup;

    version (none)
    {
        import std.stdio : writeln;

        writeln(" negChar: ", cast(int)(spec.negChar),
                " groupChar: ", cast(int)(spec.groupChar),
                " v: ", v, " vlen: ", v.length,
                " r: ", result,
                " rlen: ", result.length);
    }

    return result;
}

bool lookup(scope const(int[][]) pairTable, int c) nothrow pure
in
{
    assert(pairTable.length != 0);
}
do
{
    ptrdiff_t l;
    ptrdiff_t r = pairTable.length - 1;
    while (l <= r)
    {
        const m = (l + r) >> 1;
        if (c < pairTable[m][0])
            r = m - 1;
        else if (c > pairTable[m][1])
            l = m + 1;
        else
            return true;
    }
    return false;
}

unittest  // combineName
{
    import pham.utl.utl_test;
    traceUnitTest("unittest xml.util.combineName");

    assert(combineName!string("", "") == "");
    assert(combineName!string("", "name") == "name");
    assert(combineName!string("prefix", "") == "prefix:");
    assert(combineName!string("prefix", "name") == "prefix:name");
}

unittest  // equalCase
{
    import pham.utl.utl_test;
    traceUnitTest("unittest xml.util.equalCase");

    assert(equalCase!string("", ""));
    assert(equalCase!string(" ", " "));
    assert(equalCase!string("a", "a"));
    assert(equalCase!string("za", "za"));
    assert(equalCase!string("1", "1"));

    assert(!equalCase!string("a", "A"));
    assert(!equalCase!string("za", "ZA"));
    assert(!equalCase!string("1", "9"));
}

unittest  // equalCaseInsensitive
{
    import pham.utl.utl_test;
    traceUnitTest("unittest xml.util.equalCaseInsensitive");

    assert(equalCaseInsensitive!string("", ""));
    assert(equalCaseInsensitive!string(" ", " "));
    assert(equalCaseInsensitive!string("a", "a"));
    assert(equalCaseInsensitive!string("za", "za"));
    assert(equalCaseInsensitive!string("a", "A"));
    assert(equalCaseInsensitive!string("za", "ZA"));
    assert(equalCaseInsensitive!string("1", "1"));

    assert(!equalCaseInsensitive!string("1", "9"));
}

unittest  // formatNumber
{
    import pham.utl.utl_test;
    traceUnitTest("unittest xml.util.formatNumber");

    assert(formatNumber!int(0) == "0");
    assert(formatNumber!int(100) == "100");
    assert(formatNumber!int(1000) == "1_000");
    assert(formatNumber!int(10000) == "10_000");
    assert(formatNumber!int(200000) == "200_000");
    assert(formatNumber!int(9000000) == "9_000_000");
    assert(formatNumber!int(int.max) == "2_147_483_647");

    assert(formatNumber!int(-1) == "-1");
    assert(formatNumber!int(-100) == "-100");
    assert(formatNumber!int(-1000) == "-1_000");
    assert(formatNumber!int(-10000) == "-10_000");
    assert(formatNumber!int(-200000) == "-200_000");
    assert(formatNumber!int(-9000000) == "-9_000_000");
    assert(formatNumber!int(int.min) == "-2_147_483_648");

    assert(formatNumber!uint(0) == "0");
    assert(formatNumber!uint(100) == "100");
    assert(formatNumber!uint(1000) == "1_000");
    assert(formatNumber!uint(10000) == "10_000");
    assert(formatNumber!uint(200000) == "200_000");
    assert(formatNumber!uint(9000000) == "9_000_000");
    assert(formatNumber!uint(uint.max) == "4_294_967_295");

    assert(formatNumber!long(long.max) == "9_223_372_036_854_775_807");
    assert(formatNumber!long(long.min) == "-9_223_372_036_854_775_808");
    assert(formatNumber!ulong(ulong.max) == "18_446_744_073_709_551_615");
}

unittest  // formatFloat
{
    import pham.utl.utl_test;
    traceUnitTest("unittest xml.util.formatFloat");

    assert(formatFloat!double(0.0) == "0.000_000");
    assert(formatFloat!double(100.0) == "100.000_000");
    assert(formatFloat!double(1000.0) == "1_000.000_000");
    assert(formatFloat!double(1000.01) == "1_000.010_000");
    assert(formatFloat!double(1000.001) == "1_000.001_000");
    assert(formatFloat!double(1000.0001) == "1_000.000_100");

    assert(formatFloat!double(-100.0) == "-100.000_000");
    assert(formatFloat!double(-1000.0) == "-1_000.000_000");
    assert(formatFloat!double(-1000.01) == "-1_000.010_000");
    assert(formatFloat!double(-1000.001) == "-1_000.001_000");
    assert(formatFloat!double(-1000.0001) == "-1_000.000_100");
}

unittest  // stringOfChar
{
    import pham.utl.utl_test;
    traceUnitTest("unittest xml.util.stringOfChar");

    assert(stringOfChar!string(' ', 0) == "");
    assert(stringOfChar!string(' ', 1) == " ");
    assert(stringOfChar!string(' ', 2) == "  ");
}

unittest  // isChar
{
    import pham.utl.utl_test;
    traceUnitTest("unittest xml.util.isChar");

    assert(isChar(cast(dchar)0x9));
    assert(isChar(cast(dchar)0xA));
    assert(isChar(cast(dchar)0xD));

    foreach (c; 0x20..0xD7FF + 1)
        assert(isChar(cast(dchar)c));

    foreach (c; 0xE000..0xFFFD + 1)
        assert(isChar(cast(dchar)c));

    foreach (c; 0x10000..0x10FFFF + 1)
        assert(isChar(cast(dchar)c));

    assert(isChar('a'));
    assert(isChar('A'));
    assert(isChar('j'));
    assert(isChar('J'));
    assert(isChar('z'));
    assert(isChar('Z'));
    assert(isChar(cast(dchar)0xD7FF));
    assert(isChar(cast(dchar)0xE000));
    assert(isChar(cast(dchar)0xFFFD));
    assert(isChar(cast(dchar)0x10000));
    assert(isChar(cast(dchar)0x10FFFF));

    assert(!isChar(cast(dchar)0x0));
    assert(!isChar(cast(dchar)0x8));
    assert(!isChar(cast(dchar)0xB));
    assert(!isChar(cast(dchar)0xC));
    assert(!isChar(cast(dchar)0xE));
    assert(!isChar(cast(dchar)0x1F));
    assert(!isChar(cast(dchar)0xD800));
    assert(!isChar(cast(dchar)0xDFFF));
    assert(!isChar(cast(dchar)0xFFFE));
    assert(!isChar(cast(dchar)0xFFFF));
    assert(!isChar(cast(dchar)0x110000));
}

unittest  // isDigit
{
    import pham.utl.utl_test;
    traceUnitTest("unittest xml.util.isDigit");

    assert(isDigit('0'));
    assert(isDigit('1'));
    assert(isDigit('2'));
    assert(isDigit('3'));
    assert(isDigit('4'));
    assert(isDigit('5'));
    assert(isDigit('6'));
    assert(isDigit('7'));
    assert(isDigit('8'));
    assert(isDigit('9'));

    foreach (c; 0x0030..0x0039 + 1)
        assert(isDigit(cast(dchar)c));

    foreach (c; 0x0660..0x0669 + 1)
        assert(isDigit(cast(dchar)c));

    foreach (c; 0x06F0..0x06F9 + 1)
        assert(isDigit(cast(dchar)c));

    foreach (c; 0x0966..0x096F + 1)
        assert(isDigit(cast(dchar)c));

    foreach (c; 0x09E6..0x09EF + 1)
        assert(isDigit(cast(dchar)c));

    foreach (c; 0x0A66..0x0A6F + 1)
        assert(isDigit(cast(dchar)c));

    foreach (c; 0x0AE6..0x0AEF + 1)
        assert(isDigit(cast(dchar)c));

    foreach (c; 0x0B66..0x0B6F + 1)
        assert(isDigit(cast(dchar)c));

    foreach (c; 0x0BE7..0x0BEF + 1)
        assert(isDigit(cast(dchar)c));

    foreach (c; 0x0C66..0x0C6F + 1)
        assert(isDigit(cast(dchar)c));

    foreach (c; 0x0CE6..0x0CEF + 1)
        assert(isDigit(cast(dchar)c));

    foreach (c; 0x0D66..0x0D6F + 1)
        assert(isDigit(cast(dchar)c));

    foreach (c; 0x0E50..0x0E59 + 1)
        assert(isDigit(cast(dchar)c));

    foreach (c; 0x0ED0..0x0ED9 + 1)
        assert(isDigit(cast(dchar) c));

    foreach (c; 0x0F20..0x0F29 + 1)
        assert(isDigit(cast(dchar)c));

    assert(!isDigit(cast(dchar)0x0));
    assert(!isDigit(' '));
    assert(!isDigit('a'));
    assert(!isDigit('A'));
    assert(!isDigit('j'));
    assert(!isDigit('J'));
    assert(!isDigit('z'));
    assert(!isDigit('Z'));
}

unittest  // isExtender
{
    import pham.utl.utl_test;
    traceUnitTest("unittest xml.util.isExtender");

    assert(isExtender(cast(dchar)0x00B7));
    assert(isExtender(cast(dchar)0x02D0));
    assert(isExtender(cast(dchar)0x02D1));
    assert(isExtender(cast(dchar)0x0387));
    assert(isExtender(cast(dchar)0x0640));
    assert(isExtender(cast(dchar)0x0E46));
    assert(isExtender(cast(dchar)0x0EC6));
    assert(isExtender(cast(dchar)0x3005));

    foreach (c; 0x3031..0x3035 + 1)
        assert(isExtender(cast(dchar)c));

    foreach (c; 0x309D..0x309E + 1)
        assert(isExtender(cast(dchar)c));

    foreach (c; 0x30FC..0x30FE + 1)
        assert(isExtender(cast(dchar)c));
}

unittest  // isIdeographic
{
    import pham.utl.utl_test;
    traceUnitTest("unittest xml.util.isIdeographic");

    assert(isIdeographic('\u4E00'));
    assert(isIdeographic('\u9FA5'));
    assert(isIdeographic('\u3007'));
    assert(isIdeographic('\u3021'));
    assert(isIdeographic('\u3029'));

    assert(isIdeographic(cast(dchar)0x3007));

    foreach (c; 0x4E00..0x9FA5 + 1)
        assert(isIdeographic(cast(dchar)c));

    foreach (c; 0x3021..0x3029 + 1)
        assert(isIdeographic(cast(dchar)c));
}

unittest  // all code points for xml_util.isChar, xml_util.isDigit, xml_util.isIdeographic
{
    import pham.utl.utl_test;

    version (none)
    {
        import std.conv;
        traceUnitTest("unittest xml.util.isChar, isDigit, isIdeographic");

        foreach (c; 0..dchar.max + 1)
        {
            assert(isChar(c) == lookup(charTable, c), "isChar: " ~ c.to!string());
            assert(isDigit(c) == lookup(digitTable, c), "isDigit: " ~ c.to!string());
            assert(isIdeographic(c) == lookup(ideographicTable, c),
                    "isIdeographic: " ~ c.to!string());
        }
    }
}

unittest  // isSpaces
{
    import pham.utl.utl_test;
    traceUnitTest("unittest xml.util.isSpaces");

    assert(isSpaces!string(" "));
    assert(isSpaces!string("    \n\t"));

    assert(!isSpaces!string(""));
    assert(!isSpaces!string("0"));
    assert(!isSpaces!string("00"));
    assert(!isSpaces!string("9"));
    assert(!isSpaces!string("99"));
    assert(!isSpaces!string("a"));
    assert(!isSpaces!string("aa"));
    assert(!isSpaces!string("z"));
    assert(!isSpaces!string("zz"));
    assert(!isSpaces!string("    b"));
    assert(!isSpaces!string("b    "));
}

unittest  // isVersionStr
{
    import std.typecons : No, Yes;
    import pham.utl.utl_test;
    traceUnitTest("unittest xml.util.isVersionStr");

    assert(isVersionStr!(string, Yes.AllowEmpty)(""));
    assert(isVersionStr!(string, No.AllowEmpty)("1"));
    assert(isVersionStr!(string, No.AllowEmpty)("1.1"));
    assert(isVersionStr!(string, No.AllowEmpty)("1.2"));
    assert(isVersionStr!(string, No.AllowEmpty)("123.456"));

    assert(!isVersionStr!(string, No.AllowEmpty)(""));
    assert(!isVersionStr!(string, No.AllowEmpty)("1."));
    assert(!isVersionStr!(string, No.AllowEmpty)(".1"));
    assert(!isVersionStr!(string, No.AllowEmpty)("ab"));
    assert(!isVersionStr!(string, No.AllowEmpty)("a.b"));
}

unittest  // leftString
{
    import pham.utl.utl_test;
    traceUnitTest("unittest xml.util.leftString");

    assert(leftString!string("", 1) == "");
    assert(leftString!string("abc", 1) == "a");
    assert(leftString!string("abcd", 5) == "abcd");
    assert(leftString!string("xyz", 2) == "xy");
}

unittest  // leftStringIndicator
{
    import pham.utl.utl_test;
    traceUnitTest("unittest xml.util.leftStringIndicator");

    assert(leftStringIndicator!string("", 1) == "");
    assert(leftStringIndicator!string("abc", 1) == "a...");
    assert(leftStringIndicator!string("abcd", 5) == "abcd");
    assert(leftStringIndicator!string("xyz", 2) == "xy...");
}

unittest  // rightString
{
    import pham.utl.utl_test;
    traceUnitTest("unittest xml.util.rightString");

    assert(rightString!string("", 1) == "");
    assert(rightString!string("abc", 1) == "c");
    assert(rightString!string("abcd", 5) == "abcd");
    assert(rightString!string("xyz", 2) == "yz");
}

unittest  // splitName
{
    import pham.utl.utl_test;
    traceUnitTest("unittest xml.util.splitName");

    string p, n;

    splitName!string(":", p, n);
    assert(p == "");
    assert(n == "");

    splitName!string("name", p, n);
    assert(p == "");
    assert(n == "name");

    splitName!string("prefix:name", p, n);
    assert(p == "prefix");
    assert(n == "name");
}

unittest  // splitNameValue
{
    import pham.utl.utl_test;
    traceUnitTest("unittest xml.util.splitNameValue");

    string n, v;

    assert(splitNameValueD!string("name=value", '=', n, v) == 2);
    assert(n == "name");
    assert(v == "value");

    assert(splitNameValueD!string("name=", '=', n, v) == 2);
    assert(n == "name");
    assert(v == "");

    assert(splitNameValueD!string("name", '=', n, v) == 1);
    assert(n == "name");
    assert(v is null);

    assert(splitNameValueD!string("=value", '=', n, v) == 2);
    assert(n == "");
    assert(v == "value");

    assert(splitNameValueD!string("", '=', n, v) == 0);
    assert(n is null);
    assert(v is null);

    assert(splitNameValueD!string("  ", '=', n, v) == 1);
    assert(n == "  ");
    assert(v is null);
}
