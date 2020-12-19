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

module pham.utl.utf8;

nothrow @safe:

enum unicodeHalfShift = 10;
enum unicodeHalfBase = 0x00010000;
enum unicodeHalfMask = 0x03FF;
enum unicodeSurrogateHighBegin = 0xD800;
enum unicodeSurrogateHighEnd = 0xDBFF;
enum unicodeSurrogateLowBegin = 0xDC00;
enum unicodeSurrogateLowEnd = 0xDFFF;

immutable ubyte[] unicodeTrailingBytesForUTF8 = [
    0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
    0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
    0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
    0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
    0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
    0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
    1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1, 1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,
    2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2, 3,3,3,3,3,3,3,3,4,4,4,4,5,5,5,5
];

immutable uint[] unicodeOffsetsFromUTF8 = [
    0x00000000, 0x00003080, 0x000E2080, 0x03C82080, 0xFA082080, 0x82082080
];

void inplaceMoveToLeft(ref ubyte[] data, size_t fromIndex, size_t toIndex, size_t nBytes) pure
in
{
    assert(nBytes > 0);
    assert(toIndex < fromIndex);
    assert(toIndex + nBytes <= data.length);
    assert(fromIndex + nBytes <= data.length);
}
do
{
    import core.stdc.string : memmove;

    (() @trusted => memmove(data.ptr + toIndex, data.ptr + fromIndex, nBytes))();
}

dchar utf8NextChar(const(char)[] str, ref size_t pos, out size_t cnt)
{
    cnt = 0;
    if (pos >= str.length)
        return 0;

    ubyte c = str[pos++];

    /* The following encodings are valid utf8 combinations:
     *  0xxxxxxx
     *  110xxxxx 10xxxxxx
     *  1110xxxx 10xxxxxx 10xxxxxx
     *  11110xxx 10xxxxxx 10xxxxxx 10xxxxxx
     *  111110xx 10xxxxxx 10xxxxxx 10xxxxxx 10xxxxxx
     *  1111110x 10xxxxxx 10xxxxxx 10xxxxxx 10xxxxxx 10xxxxxx
     */
    if (c & 0x80)
    {
        const extraBytesToRead = unicodeTrailingBytesForUTF8[c];

        if (extraBytesToRead + pos > str.length)
            return dchar.max;

        dchar res = 0;

        switch (extraBytesToRead)
        {
            case 5:
                res += c;
                res <<= 6;
                c = str[pos++];
                goto case 4;
            case 4:
                if (extraBytesToRead != 4 && (c & 0xC0) != 0x80)
                    return dchar.max;

                res += c;
                res <<= 6;
                c = str[pos++];
                goto case 3;
            case 3:
                if (extraBytesToRead != 3 && (c & 0xC0) != 0x80)
                    return dchar.max;

                res += c;
                res <<= 6;
                c = str[pos++];
                goto case 2;
            case 2:
                if (extraBytesToRead != 2 && (c & 0xC0) != 0x80)
                    return dchar.max;

                res += c;
                res <<= 6;
                c = str[pos++];
                goto case 1;
            case 1:
                if (extraBytesToRead != 1 && (c & 0xC0) != 0x80)
                    return dchar.max;

                res += c;
                res <<= 6;
                c = str[pos++];
                goto case 0;
            case 0:
                if (extraBytesToRead != 0 && (c & 0xC0) != 0x80)
                    return dchar.max;

                res += c;
                break;
            default:
                assert(0);
        }

        cnt = extraBytesToRead + 1;
        return res - unicodeOffsetsFromUTF8[extraBytesToRead];
    }
    else
    {
        cnt = 1;
        return c;
    }
}


// Any below codes are private
private:


nothrow @safe unittest // inplaceMoveToLeft
{
    import pham.utl.utltest;
    dgWriteln("unittest utl.utf8.inplaceMoveToLeft");

    auto chars = cast(ubyte[])"1234567890".dup;

    inplaceMoveToLeft(chars, 5, 0, 5);
    assert(chars == "6789067890");
}
