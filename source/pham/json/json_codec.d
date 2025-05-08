/*
 * License: $(HTTP www.boost.org/LICENSE_1_0.txt, Boost License 1.0).
 * Authors: An Pham
 *
 * Copyright An Pham 2025 - xxxx.
 * Distributed under the Boost Software License, Version 1.0.
 * (See accompanying file LICENSE.txt or copy at http://www.boost.org/LICENSE_1_0.txt)
 *
 */
module pham.json.json_codec;

import std.range : isOutputRange;
import std.traits : isFloatingPoint, isIntegral;

import pham.utl.utl_array_append : Appender;
import pham.json.json_exception;
import pham.json.json_type;

struct JSONTextDecoder
{
@safe:

public:
    static char escapeChar(Char)(const(Char) c) nothrow pure
    if (is(Char == char) || is(Char == dchar))
    {
        switch (c)
        {
            case '"':
                return '"';

            case '\\':
                return'\\';

            case '/':
                return '/';

            case 'b':
                return '\b';

            case 'f':
                return '\f';

            case 'n':
                return '\n';

            case 'r':
                return '\r';

            case 't':
                return '\t';

            default:
                return '\0';
        }
    }
}

struct JSONTextEncoder
{
    import std.algorithm.searching : canFind;
    import std.ascii : isControl;
    import std.format : sformat;
    import std.math.traits : isNaN, isInfinity, signbit;
    import std.typecons : Yes;
    import std.utf : decode, encode;
    
@safe:

public:
    this(JSONOptions options) nothrow pure
    {
        this.options = options;
        this.escapeNonAsciiChars = (options & JSONOptions.escapeNonAsciiChars) != 0;
        this.escapeSlash = (options & JSONOptions.doNotEscapeSlash) == 0;
        this.json5 = (options & JSONOptions.json5) != 0;
        this.specialFloatLiterals = (options & JSONOptions.specialFloatLiterals) != 0;
    }

    char[] encodeChar(Char)(const(Char) c, return ref char[12] s) nothrow pure
    if (is(Char == char) || is(Char == dchar))
    {
        switch (c)
        {
            case '"':
                s[0..2] = "\\\"";
                return s[0..2];

            case '\\':
                s[0..2] = "\\\\";
                return s[0..2];

            case '/':
                if (escapeSlash)
                {
                    s[0..2] = "\\/";
                    return s[0..2];
                }
                else
                    return [];

            case '\b':
                s[0..2] = "\\b";
                return s[0..2];

            case '\f':
                s[0..2] = "\\f";
                return s[0..2];

            case '\n':
                s[0..2] = "\\n";
                return s[0..2];

            case '\r':
                s[0..2] = "\\r";
                return s[0..2];

            case '\t':
                s[0..2] = "\\t";
                return s[0..2];

            default:
                if (isControl(c) || (escapeNonAsciiChars && c >= 0x80))
                    return encodeCharImpl(c, s);
                else
                    return [];
        }
    }

    static char[] encodeCharImpl(dchar c, return ref char[12] s) nothrow pure
    {
        // Ensure non-BMP characters are encoded as a pair
        // of UTF-16 surrogate characters, as per RFC 4627.
        wchar[2] wchars; // 1 or 2 UTF-16 code units
        const len = encode!(Yes.useReplacementDchar)(wchars, c); // number of UTF-16 code units
        ubyte count;
        foreach (w; wchars[0..len])
        {
            s[count++] = '\\';
            s[count++] = 'u';
            foreach_reverse (i; 0..4)
            {
                char ch = (w >>> (4 * i)) & 0x0f;
                ch += ch < 10 ? '0' : 'A' - 10;
                s[count++] = ch;
            }
        }
        return s[0..count];
    }

    static string encodeUtf8(dchar c) nothrow pure
    {
        if (c >= 0x80)
        {
            char[4] s;
            const len = encode!(Yes.useReplacementDchar)(s, c);
            return s.idup;
        }
        else
            return [cast(char)c].idup;
    }
    
    string toString(typeof(null)) nothrow pure
    {
        return JSONLiteral.null_;
    }

    auto ref Sink toString(Sink)(return auto ref Sink json, typeof(null)) nothrow pure
    if (isOutputRange!(Sink, char))
    {
        json.put(cast(string)JSONLiteral.null_);
        return json;
    }

    string toString(bool value) nothrow pure
    {
        return value ? JSONLiteral.true_ : JSONLiteral.false_;
    }

    auto ref Sink toString(Sink)(return auto ref Sink json, bool value) nothrow pure
    if (isOutputRange!(Sink, char))
    {
        json.put(value ? cast(string)JSONLiteral.true_ : cast(string)JSONLiteral.false_);
        return json;
    }

    string toString(T)(T value) nothrow pure
    if (isIntegral!T)
    {
        StackBuffer!(50, char) buf;
        return toString(buf, value).toString();
    }

    auto ref Sink toString(Sink, T)(return auto ref Sink json, T value) nothrow pure
    if (isOutputRange!(Sink, char) && isIntegral!T)
    {
        scope (failure) assert(0, "Assume nothrow failed");

        char[50] buf;
        const cvtValue = buf[].sformat!"%d"(value);
        json.put(cvtValue);
        return json;
    }

    string toString(T)(T value) pure
    if (isFloatingPoint!T)
    {
        StackBuffer!(50, char) buf;
        return toString(buf, value).toString();
    }

    auto ref Sink toString(Sink, T)(return auto ref Sink json, const(T) value) pure
    if (isOutputRange!(Sink, char) && isFloatingPoint!T)
    {
        if (value.isNaN)
        {
            if (json5)
                json.put(signbit(value) ? cast(string)JSONLiteral.nnan : cast(string)JSONLiteral.pnan);
            else if (specialFloatLiterals)
            {
                json.put('"');
                json.put(signbit(value) ? cast(string)JSONLiteral.nnan : cast(string)JSONLiteral.pnan);
                json.put('"');
            }
            else
                throw new JSONException("Cannot encode NaN. Consider passing the JSONOptions.specialFloatLiterals flag.");
        }
        else if (value.isInfinity)
        {
            if (json5)
                json.put(signbit(value) ? cast(string)JSONLiteral.ninf : cast(string)JSONLiteral.pinf);
            else if (specialFloatLiterals)
            {
                json.put('"');
                json.put(signbit(value) ? cast(string)JSONLiteral.ninf : cast(string)JSONLiteral.pinf);
                json.put('"');
            }
            else
                throw new JSONException("Cannot encode Infinity. Consider passing the JSONOptions.specialFloatLiterals flag.");
        }
        else
        {
            // The correct formula for the number of decimal digits needed for lossless round
            // trips is actually:
            //     ceil(log(pow(2.0, double.mant_dig - 1)) / log(10.0) + 1) == (double.dig + 2)
            // Anything less will round off (1 + double.epsilon)
            char[50] buf;
            const cvtValue = buf[].sformat!"%.18g"(value);
            json.put(cvtValue);

            if (!cvtValue.canFind('e') && !cvtValue.canFind('.'))
                json.put(".0");
        }
        return json;
    }

    string toString(scope const(char)[] value) nothrow pure
    {
        auto result = Appender!string(value.length);
        return toString(result, value).data;
    }

    auto ref Sink toString(Sink)(return auto ref Sink json, scope const(char)[] value) nothrow pure
    if (isOutputRange!(Sink, char))
    {
        json.put('"');
        if (escapeNonAsciiChars)
            toStringEncode!(Sink, dchar)(json, value);
        else
            toStringEncode!(Sink, char)(json, value);
        json.put('"');
        return json;
    }

    auto ref Sink toStringEncode(Sink, Char)(return auto ref Sink json, scope const(char)[] value) nothrow pure
    if (isOutputRange!(Sink, char) && (is(Char == char) || is(Char == dchar)))
    {
        char[12] buffer;

        static if (is(Char == char))
        {
            foreach (const(char) c; value)
            {
                auto e = encodeChar(c, buffer);
                if (e.length == 0)
                    json.put(c);
                else
                    json.put(e);
            }
        }
        else
        {
            size_t p;
            while (p < value.length)
            {
                const c = decode!(Yes.useReplacementDchar)(value, p);
                const e = encodeChar(c, buffer);
                if (e.length == 0)
                    json.put(c);
                else
                    json.put(e);
            }
        }

        return json;
    }

    string toStringName(scope const(char)[] value) nothrow pure
    {
        auto result = Appender!string(value.length);
        return toStringName(result, value).data;
    }

    auto ref Sink toStringName(Sink)(return auto ref Sink json, scope const(char)[] value) nothrow pure
    if (isOutputRange!(Sink, char))
    {
        return escapeNonAsciiChars
            ? toStringEncode!(Sink, dchar)(json, value)
            : toStringEncode!(Sink, char)(json, value);
    }

    JSONOptions options;
    bool escapeNonAsciiChars;
    bool escapeSlash;
    bool json5;
    bool specialFloatLiterals;
}
