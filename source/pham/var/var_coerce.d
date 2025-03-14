/*
 *
 * License: $(HTTP www.boost.org/LICENSE_1_0.txt, Boost License 1.0).
 * Authors: An Pham
 *
 * Copyright An Pham 2022 - xxxx.
 * Distributed under the Boost Software License, Version 1.0.
 * (See accompanying file LICENSE.txt or copy at http://www.boost.org/LICENSE_1_0.txt)
 *
 */

module pham.var.var_coerce;

import std.math.traits : isNaN;
import std.traits : fullyQualifiedName,
    isFloatingPoint, isIntegral, isSigned, isSomeChar, isSomeString, isUnsigned,
    Unqual;

debug(debug_pham_var_var_coerce) import std.stdio : writeln;
import pham.utl.utl_array_dictionary;

enum ConvertHandlerFlag : uint
{
    none = 0,
    implicit = 1,
}

alias ConvertFunction = bool function(scope void* srcPtr, scope void* dstPtr) nothrow;

struct ConvertHandlerKey
{
nothrow @safe:

public:
    bool opEqual(scope const(ConvertHandlerKey) rhs) const @nogc pure
    {
        return this.srcQualifiedName == rhs.srcQualifiedName && this.dstQualifiedName == rhs.dstQualifiedName;
    }

    bool opEqual(scope const(char)[] srcQualifiedName, scope const(char)[] dstQualifiedName) const @nogc pure
    {
        return this.srcQualifiedName == srcQualifiedName && this.dstQualifiedName == dstQualifiedName;
    }

    size_t opHash() const @nogc pure
    {
        return hashOf(dstQualifiedName, hashOf(srcQualifiedName));
    }

public:
    string srcQualifiedName;
    string dstQualifiedName;
}

struct ConvertHandler
{
nothrow @safe:

public:
    deprecated("please use register")
    alias add = register;

    /**
     * Registers a conversion function from one type to other type
     * It should be called only on startup function (shared static this()) because no-lock -> it is not thread safe
     * Params:
     *  key = a struct to hold the from fully qualified name types from & to
     *  handler = function pointer, ConvertFunction, to do the conversion
     */
    static void register(ConvertHandlerKey key, ConvertHandler handler) @trusted
    {
        convertHandlers[key] = handler;
    }

    /**
     * Registers a conversion function from one type to other type
     * It should be called only on startup function (shared static this()) because no-lock -> it is not thread safe
     * Params:
     *  srcQualifiedName = a fully qualified type source name
     *  dstQualifiedName = a fully qualified type destination name
     *  handler = function pointer, ConvertFunction, to do the conversion
     */
    static void register(string srcQualifiedName, string dstQualifiedName, ConvertHandler handler)
    {
        debug(debug_pham_var_var_coerce) debug writeln(__FUNCTION__, "(from=", srcQualifiedName, ", to=", dstQualifiedName, ")");

        register(ConvertHandlerKey(srcQualifiedName, dstQualifiedName), handler);
    }

    /**
     * Registers a conversion function from one type to other type
     * It should be called only on startup function (shared static this()) because no-lock -> it is not thread safe
     * Params:
     *  S = a template source type
     *  D = a template destination type
     *  handler = function pointer, ConvertFunction, to do the conversion
     */
    static void register(S, D)(ConvertHandler handler)
    {
        debug(debug_pham_var_var_coerce) debug writeln(__FUNCTION__, "(from=", fullyQualifiedName!S, ", to=", fullyQualifiedName!D, ")");

        register(ConvertHandlerKey(fullyQualifiedName!S, fullyQualifiedName!D), handler);
    }

    /**
     * Finds a registered conversion function from one type to other type
     * It is thread safe if add/remove ConvertHandler is called only in startup (shared static this())
     * Params:
     *  key = a struct to hold the from fully qualified name types from & to
     *  handler = variable to hold a function pointer, ConvertFunction, to do the conversion
     */
    static bool find(ConvertHandlerKey key, ref ConvertHandler handler) @trusted
    {
        if (auto e = key in convertHandlers)
        {
            handler = *e;
            return true;
        }
        else
            return false;
    }

    /**
     * Finds a registered conversion function from one type to other type
     * It is thread safe if add/remove ConvertHandler is called only in startup (shared static this())
     * Params:
     *  srcQualifiedName = a fully qualified type source name
     *  dstQualifiedName = a fully qualified type destination name
     *  handler = variable to hold a function pointer, ConvertFunction, to do the conversion
     */
    static bool find(string srcQualifiedName, string dstQualifiedName, ref ConvertHandler handler)
    {
        return find(ConvertHandlerKey(srcQualifiedName, dstQualifiedName), handler);
    }

    /**
     * Finds a registered conversion function from one type to other type
     * It is thread safe if add/remove ConvertHandler is called only in startup (shared static this())
     * Params:
     *  S = a template source type
     *  D = a template destination type
     *  handler = variable to hold a function pointer, ConvertFunction, to do the conversion
     */
    static bool find(S, D)(ref ConvertHandler handler)
    {
        return find(ConvertHandlerKey(fullyQualifiedName!S, fullyQualifiedName!D), handler);
    }

    /**
     * Finds a registered cast function from one type to other type
     * It is thread safe if add/remove ConvertHandler is called only in startup (shared static this())
     * Params:
     *  srcQualifiedName = a fully qualified type source name
     *  dstQualifiedName = a fully qualified type destination name
     *  doCast = variable to hold a function pointer, ConvertFunction, to do the cast
     */
    static bool findCast(string srcQualifiedName, string dstQualifiedName, ref ConvertFunction doCast)
    {
        ConvertHandler handler;
        if (find(srcQualifiedName, dstQualifiedName, handler))
        {
            if (handler.canCast)
            {
                doCast = handler.doCast;
                return true;
            }
        }
        return false;
    }

    /**
     * Finds a registered cast function from one type to other type
     * It is thread safe if add/remove ConvertHandler is called only in startup (shared static this())
     * Params:
     *  S = a template source type
     *  D = a template destination type
     *  doCast = variable to hold a function pointer, ConvertFunction, to do the cast
     */
    static bool findCast(S, D)(ref ConvertFunction doCast)
    {
        return findCast(fullyQualifiedName!S, fullyQualifiedName!D, doCast);
    }

    /**
     * Finds a registered coerce function from one type to other type
     * It is thread safe if add/remove ConvertHandler is called only in startup (shared static this())
     * Params:
     *  srcQualifiedName = a fully qualified type source name
     *  dstQualifiedName = a fully qualified type destination name
     *  doCoerce = variable to hold a function pointer, ConvertFunction, to do the coerce
     */
    static bool findCoerce(string srcQualifiedName, string dstQualifiedName, ref ConvertFunction doCoerce)
    {
        ConvertHandler handler;
        if (find(srcQualifiedName, dstQualifiedName, handler))
        {
            if (handler.canCoerce)
            {
                doCoerce = handler.doCoerce;
                return true;
            }
        }
        return false;
    }

    /**
     * Finds a registered coerce function from one type to other type
     * It is thread safe if add/remove ConvertHandler is called only in startup (shared static this())
     * Params:
     *  S = a template source type
     *  D = a template destination type
     *  doCoerce = variable to hold a function pointer, ConvertFunction, to do the coerce
     */
    static bool findCoerce(S, D)(ref ConvertFunction doCoerce)
    {
        return findCoerce(fullyQualifiedName!S, fullyQualifiedName!D, doCoerce);
    }

    pragma(inline, true)
    @property bool canCast() const @nogc pure
    {
        return doCast !is null;
    }

    pragma(inline, true)
    @property bool canCoerce() const @nogc pure
    {
        return doCoerce !is null;
    }

    pragma(inline, true)
    @property bool canImplicit() const @nogc pure
    {
        return (flags & ConvertHandlerFlag.implicit) != 0 && canCoerce;
    }

public:
    ConvertFunction doCast;
    ConvertFunction doCoerce;
    uint flags;
}


// All implement after this point must be private
private:

T min(T)() @nogc nothrow pure @safe
if (isFloatingPoint!T)
{
    return -T.max;
}

enum bool isString(T) = is(T == string) || is(T == wstring) || is(T == dstring);

enum bool isConstString(T) = is(T == const(char)[]) || is(T == const(wchar)[]) || is(T == const(dchar)[]);

template CharOfString(T)
if (isSomeString!T)
{
    static if (is(immutable T == immutable C[], C) && (is(C == char) || is(C == wchar) || is(C == dchar)))
        alias CharOfString = C;
    else
        static assert(0);
}

template StringOfChar(T)
if (isSomeChar!T)
{
    static if (is(Unqual!T == char))
        alias StringOfChar = string;
    else static if (is(Unqual!T == wchar))
        alias StringOfChar = wstring;
    else static if (is(Unqual!T == dchar))
        alias StringOfChar = dstring;
    else
        static assert(0);
}

template ConstStringOfChar(T)
if (isSomeChar!T)
{
    static if (is(Unqual!T == char))
        alias ConstStringOfChar = const(char)[];
    else static if (is(Unqual!T == wchar))
        alias ConstStringOfChar = const(wchar)[];
    else static if (is(Unqual!T == dchar))
        alias ConstStringOfChar = const(dchar)[];
    else
        static assert(0);
}

bool doCastBool(S, D)(scope void* srcPtr, scope void* dstPtr) nothrow
if ((is(D == bool) || isFloatingPoint!S || isIntegral!S || isSomeChar!S) && is(D == bool))
{
    const s = *cast(S*)srcPtr;
    static if (is(D == S))
        *cast(D*)dstPtr = s;
    else static if (isIntegral!S)
        *cast(D*)dstPtr = s != 0;
    else static if (isFloatingPoint!S)
        *cast(D*)dstPtr = s != 0.0 && !isNaN(s);
    else static if (isSomeChar!S)
        *cast(D*)dstPtr = s != 0;
    else
        static assert(0);

    return true;
}

bool doCoerceBool(S, D)(scope void* srcPtr, scope void* dstPtr) nothrow
if (is(S == bool) && (is(D == bool) || isFloatingPoint!D || isIntegral!D))
{
    const s = *cast(S*)srcPtr;
    static if (is(D == S))
        *cast(D*)dstPtr = s;
    else
        *cast(D*)dstPtr = s ? cast(D)1 : cast(D)0;
    return true;
}

bool doCastFloat(S, D)(scope void* srcPtr, scope void* dstPtr) nothrow
if ((isFloatingPoint!S || isIntegral!S || isSomeChar!S) && isFloatingPoint!D)
{
    const s = *cast(S*)srcPtr;

    static if (isFloatingPoint!S)
    if (isNaN(s))
    {
        *cast(D*)dstPtr = D.nan;
        return true;
    }

    *cast(D*)dstPtr = cast(D)s;
    return true;
}

bool doCoerceFloat(S, D)(scope void* srcPtr, scope void* dstPtr) nothrow
if ((isFloatingPoint!S || isIntegral!S || isSomeChar!S) && isFloatingPoint!D)
{
    const s = *cast(S*)srcPtr;

    static if (isFloatingPoint!S)
    if (isNaN(s))
    {
        *cast(D*)dstPtr = D.nan;
        return true;
    }

    static if (D.sizeof >= S.sizeof)
    {
        *cast(D*)dstPtr = cast(D)s;
        return true;
    }
    else
    {
        if (min!D() <= s && s <= D.max)
        {
            *cast(D*)dstPtr = cast(D)s;
            return true;
        }

        return false;
    }
}

bool doCastIntegral(S, D)(scope void* srcPtr, scope void* dstPtr) nothrow
if ((isFloatingPoint!S || isIntegral!S || isSomeChar!S) && (isIntegral!D || isSomeChar!D))
{
    import std.math : lround;

    const s = *cast(S*)srcPtr;

    static if (isFloatingPoint!S)
    if (isNaN(s))
        return false;

    *cast(D*)dstPtr = cast(D)s;
    return true;
}

bool doCoerceIntegral(S, D)(scope void* srcPtr, scope void* dstPtr) nothrow
if ((isFloatingPoint!S || isIntegral!S || isSomeChar!S) && (isIntegral!D || isSomeChar!D))
{
    import std.math : lround;

    const s = *cast(S*)srcPtr;

    static if (is(D == S))
    {
        *cast(D*)dstPtr = s;
        return true;
    }
    else
    {
        static if (isFloatingPoint!S)
        {
            if (isNaN(s))
                return false;

            static if (isUnsigned!D)
            if (s < cast(S)0.0)
                return false;

            if (s > D.max)
                return false;

            static if (isSigned!D)
            if (s < D.min)
                return false;
        }

        static if (isSigned!S && (isUnsigned!D || isSomeChar!D))
        if (s < 0)
            return false;

        static if ((isIntegral!S || isSomeChar!S) && D.sizeof < S.sizeof)
        {
            if (s > cast(S)D.max)
                return false;

            static if (isSigned!S && isSigned!D)
            if (s < cast(S)D.min)
                return false;
        }

        static if (isFloatingPoint!S)
            *cast(D*)dstPtr = cast(D)lround(s);
        else
            *cast(D*)dstPtr = cast(D)s;
        return true;
    }
}

bool doCoerceCharToString(S, D)(scope void* srcPtr, scope void* dstPtr) nothrow
if (isSomeChar!S && isString!D && is(Unqual!S == CharOfString!D))
{
    *cast(D*)dstPtr = [*cast(S*)srcPtr].idup;
    return true;
}

bool doCoerceString(S, D)(scope void* srcPtr, scope void* dstPtr) nothrow
if (isSomeString!S && isString!D && is(CharOfString!S == CharOfString!D))
{
    static if (is(D == S))
        *cast(D*)dstPtr = *cast(S*)srcPtr;
    else
        *cast(D*)dstPtr = (*cast(S*)srcPtr).idup;
    return true;
}

bool doCoerceStringEx(S, D)(scope void* srcPtr, scope void* dstPtr) nothrow
if (isSomeString!S && isString!D && !is(CharOfString!S == CharOfString!D))
{
    import std.conv : to;

    // Special try construct for grep
    try {
        *cast(D*)dstPtr = (*cast(S*)srcPtr).to!D();
        return true;
    } catch (Exception) return false;
}

bool doCoerceConstString(S, D)(scope void* srcPtr, scope void* dstPtr) nothrow
if (isSomeString!S && isConstString!D && is(CharOfString!S == CharOfString!D))
{
    *cast(D*)dstPtr = *cast(S*)srcPtr;
    return true;
}

__gshared Dictionary!(ConvertHandlerKey, ConvertHandler) convertHandlers;

import core.attribute : standalone;

@standalone
shared static this() nothrow @trusted
{
    import std.meta : AliasSeq;

    convertHandlers = Dictionary!(ConvertHandlerKey, ConvertHandler)(1_500, 1_000);
    ConvertHandler handler;

    // To integral type
    static foreach (S; AliasSeq!(byte, ubyte, short, ushort, int, uint, long, ulong, float, double, real, char, wchar, dchar))
    {
        static foreach (D; AliasSeq!(byte, ubyte, short, ushort, int, uint, long, ulong, char, wchar, dchar))
        {
            handler.doCast = &doCastIntegral!(S, D);
            handler.doCoerce = &doCoerceIntegral!(S, D);
            handler.flags = ConvertHandlerFlag.implicit;
            ConvertHandler.register!(S, D)(handler);
        }
    }

    // To float type
    static foreach (S; AliasSeq!(byte, ubyte, short, ushort, int, uint, long, ulong, float, double, real, char, wchar, dchar))
    {
        static foreach (D; AliasSeq!(float, double, real))
        {
            handler.doCast = &doCastFloat!(S, D);
            handler.doCoerce = &doCoerceFloat!(S, D);
            handler.flags = ConvertHandlerFlag.implicit;
            ConvertHandler.register!(S, D)(handler);
        }
    }

    // To bool type
    static foreach (S; AliasSeq!(byte, ubyte, short, ushort, int, uint, long, ulong, float, double, real, char, wchar, dchar, bool))
    {
        handler.doCast = &doCastBool!(S, bool);
        handler.doCoerce = null;
        handler.flags = ConvertHandlerFlag.implicit;
        ConvertHandler.register!(S, bool)(handler);
    }

    static foreach (S; AliasSeq!(byte, ubyte, short, ushort, int, uint, long, ulong, float, double, real, bool))
    {
        handler.doCast = null;
        handler.doCoerce = &doCoerceBool!(bool, S);
        handler.flags = ConvertHandlerFlag.implicit;
        ConvertHandler.register!(bool, S)(handler);
    }

    // To same string type
    static foreach (S; AliasSeq!(char, wchar, dchar))
    {
        handler.doCast = null;
        handler.flags = ConvertHandlerFlag.implicit;

        // to immutable(S)[]
        handler.doCoerce = &doCoerceString!(StringOfChar!S, StringOfChar!S);
        ConvertHandler.register!(StringOfChar!S, StringOfChar!S)(handler);

        handler.doCoerce = &doCoerceString!(S[], StringOfChar!S);
        ConvertHandler.register!(S[], StringOfChar!S)(handler);

        handler.doCoerce = &doCoerceString!(const(S)[], StringOfChar!S);
        ConvertHandler.register!(const(S)[], StringOfChar!S)(handler);

        // to const(S)[]
        handler.doCoerce = &doCoerceConstString!(StringOfChar!S, ConstStringOfChar!S);
        ConvertHandler.register!(StringOfChar!S, ConstStringOfChar!S)(handler);

        handler.doCoerce = &doCoerceConstString!(S[], ConstStringOfChar!S);
        ConvertHandler.register!(S[], ConstStringOfChar!S)(handler);

        handler.doCoerce = &doCoerceConstString!(const(S)[], ConstStringOfChar!S);
        ConvertHandler.register!(const(S)[], ConstStringOfChar!S)(handler);

        // S to immutable(S)[]
        handler.doCoerce = &doCoerceCharToString!(S, StringOfChar!S);
        ConvertHandler.register!(S, StringOfChar!S)(handler);
    }

    // To different string type
    static foreach (S; AliasSeq!(char, wchar, dchar))
    {
        static foreach (D; AliasSeq!(char, wchar, dchar))
        {
            static if (!is(S == D))
            {
                handler.doCast = null;
                handler.flags = ConvertHandlerFlag.none;

                handler.doCoerce = &doCoerceStringEx!(StringOfChar!S, StringOfChar!D);
                ConvertHandler.register!(StringOfChar!S, StringOfChar!D)(handler);

                handler.doCoerce = &doCoerceStringEx!(S[], StringOfChar!D);
                ConvertHandler.register!(S[], StringOfChar!D)(handler);

                handler.doCoerce = &doCoerceStringEx!(const(S)[], StringOfChar!D);
                ConvertHandler.register!(const(S)[], StringOfChar!D)(handler);
            }
        }
    }

    debug(debug_pham_var_var_coerce) if (convertHandlers.maxCollision) debug writeln(__FUNCTION__, "(convertHandlers.maxCollision=", convertHandlers.maxCollision,
        ", convertHandlers.collisionCount=", convertHandlers.collisionCount, ", convertHandlers.capacity=", convertHandlers.capacity, ", convertHandlers.length=", convertHandlers.length, ")");
}

version(unittest)
template isGreaterEqual(L, R)
if ((isIntegral!L || isFloatingPoint!L || isSomeChar!L)
    && (isIntegral!R || isFloatingPoint!R || isSomeChar!R))
{
    static if (is(L == R))
        enum isGreaterEqual = 1;
    else static if (L.sizeof < R.sizeof)
        enum isGreaterEqual = 0;
    else static if (L.sizeof == R.sizeof)
    {
        static if (isFloatingPoint!R)
            enum isGreaterEqual = 0;
        else static if (isSigned!L && (isUnsigned!R || isSomeChar!R))
            enum isGreaterEqual = 0;
        else
            enum isGreaterEqual = 1;
    }
    else
        enum isGreaterEqual = 2;
}

nothrow unittest // ConvertHandler.Integral
{
    import std.math : lround;
    import std.meta : AliasSeq;

    ConvertHandler handler;
    bool f;

    static S coerceMaxOf(S, D)()
    {
        static if (isSomeChar!S || isSomeChar!D)
        {
            static if (S.sizeof < D.sizeof || S.max < D.max)
                return S.max - 1;
            else
                return cast(S)(D.max - 1);
        }
        else static if (isFloatingPoint!S)
        {
            static if (D.sizeof < 4)
                return cast(S)(D.max - 2);
            else
                return cast(S)(int.max - 2);
        }
        else static if (S.sizeof > D.sizeof || (isUnsigned!S && isSigned!D))
            return cast(S)(D.max - 1);
        else
            return S.max - 1;
    }

    static foreach (S; AliasSeq!(byte, ubyte, short, ushort, int, uint, long, ulong, float, double, real, char, wchar, dchar))
    {
        static foreach (D; AliasSeq!(byte, ubyte, short, ushort, int, uint, long, ulong, char, wchar, dchar))
        {
            {
                S s;
                D d;

                f = ConvertHandler.find!(S, D)(handler);
                assert(f);
                assert(handler.doCast !is null);
                assert(handler.doCoerce !is null);

                s = 0;
                d = 1;
                f = handler.doCoerce(&s, &d);
                assert(f, S.stringof ~ " to " ~ D.stringof);
                assert(d == 0, S.stringof ~ " to " ~ D.stringof);

                s = 0;
                d = 1;
                f = handler.doCast(&s, &d);
                assert(f, S.stringof ~ " to " ~ D.stringof);
                assert(d == 0, S.stringof ~ " to " ~ D.stringof);

                s = 127;
                d = 1;
                f = handler.doCoerce(&s, &d);
                assert(f, S.stringof ~ " to " ~ D.stringof);
                assert(d == 127, S.stringof ~ " to " ~ D.stringof);

                s = 127;
                d = 1;
                f = handler.doCast(&s, &d);
                assert(f, S.stringof ~ " to " ~ D.stringof);
                assert(d == 127, S.stringof ~ " to " ~ D.stringof);

                static if (isGreaterEqual!(D, S))
                {
                    s = coerceMaxOf!(S, D);
                    d = 1;
                    f = handler.doCoerce(&s, &d);
                    //dgWriteln("coerce D.sizeof >= S.sizeof: ", "f=", f, ", cast(ulong)d=", cast(ulong)d, ", cast(ulong)s=", cast(ulong)s, " ", S.stringof ~ " to " ~ D.stringof, ", s=", s);
                    assert(f, S.stringof ~ " to " ~ D.stringof);
                    assert(cast(ulong)d == cast(ulong)s, S.stringof ~ " to " ~ D.stringof);
                }

                // Cast case
                {
                    s = coerceMaxOf!(S, D);
                    d = 1;
                    f = handler.doCast(&s, &d);
                    assert(f, S.stringof ~ " to " ~ D.stringof);
                    static if (!isFloatingPoint!S)
                    assert(cast(ulong)d == cast(ulong)s, S.stringof ~ " to " ~ D.stringof);
                }

                static if (S.sizeof < D.sizeof && isSigned!S && isSigned!D && !isFloatingPoint!S)
                {
                    s = S.min;
                    d = 0;
                    f = handler.doCoerce(&s, &d);
                    assert(f, S.stringof ~ " to " ~ D.stringof);
                    assert(d == s, S.stringof ~ " to " ~ D.stringof);
                }

                // Not coerce for out of range
                static if (S.sizeof > D.sizeof)
                {
                    s = S.max;
                    d = 0;
                    f = handler.doCoerce(&s, &d);
                    assert(!f, S.stringof ~ " to " ~ D.stringof);
                    assert(d == 0, S.stringof ~ " to " ~ D.stringof);

                    static if (isSigned!S && !isFloatingPoint!S)
                    {
                        s = S.min;
                        d = 0;
                        f = handler.doCoerce(&s, &d);
                        assert(!f, S.stringof ~ " to " ~ D.stringof);
                        assert(d == 0, S.stringof ~ " to " ~ D.stringof);
                    }

                    static if (isFloatingPoint!S)
                    {
                        s = min!S();
                        d = 0;
                        f = handler.doCoerce(&s, &d);
                        assert(!f, S.stringof ~ " to " ~ D.stringof);
                        assert(d == 0, S.stringof ~ " to " ~ D.stringof);
                    }
                }

                // Not coerce/cast for nan
                static if (isFloatingPoint!S)
                {
                    s = S.nan;
                    d = 1;
                    f = handler.doCoerce(&s, &d);
                    assert(!f, S.stringof ~ " to " ~ D.stringof);
                    assert(d == 1, S.stringof ~ " to " ~ D.stringof);

                    s = S.nan;
                    d = 1;
                    f = handler.doCast(&s, &d);
                    assert(!f, S.stringof ~ " to " ~ D.stringof);
                    assert(d == 1, S.stringof ~ " to " ~ D.stringof);
                }
            }
        }
    }
}

nothrow unittest // ConvertHandler.Float
{
    import std.meta : AliasSeq;

    ConvertHandler handler;
    bool f;

    static foreach (S; AliasSeq!(byte, ubyte, short, ushort, int, uint, long, ulong, float, double, real, char, wchar, dchar))
    {
        static foreach (D; AliasSeq!(float, double, real))
        {
            {
                S s;
                D d;

                f = ConvertHandler.find!(S, D)(handler);
                assert(f);
                assert(handler.doCast !is null);
                assert(handler.doCoerce !is null);

                s = 0;
                d = 1;
                f = handler.doCoerce(&s, &d);
                assert(f, S.stringof ~ " to " ~ D.stringof);
                assert(d == 0, S.stringof ~ " to " ~ D.stringof);

                s = 0;
                d = 1;
                f = handler.doCast(&s, &d);
                assert(f, S.stringof ~ " to " ~ D.stringof);
                assert(d == 0, S.stringof ~ " to " ~ D.stringof);

                s = 127;
                d = 1;
                f = handler.doCoerce(&s, &d);
                assert(f, S.stringof ~ " to " ~ D.stringof);
                assert(d == 127, S.stringof ~ " to " ~ D.stringof);

                static if (isFloatingPoint!S)
                {
                    s = S.nan;
                    d = 1;
                    f = handler.doCoerce(&s, &d);
                    assert(f, S.stringof ~ " to " ~ D.stringof);
                    assert(isNaN(d), S.stringof ~ " to " ~ D.stringof);

                    s = S.nan;
                    d = 1;
                    f = handler.doCast(&s, &d);
                    assert(f, S.stringof ~ " to " ~ D.stringof);
                    assert(isNaN(d), S.stringof ~ " to " ~ D.stringof);
                }

                // Not coerce for out of range
                static if (S.sizeof > D.sizeof && isFloatingPoint!S)
                {
                    s = S.max;
                    d = 0;
                    f = handler.doCoerce(&s, &d);
                    assert(!f, S.stringof ~ " to " ~ D.stringof);
                    assert(d == 0, S.stringof ~ " to " ~ D.stringof);

                    s = min!S();
                    d = 0;
                    f = handler.doCoerce(&s, &d);
                    assert(!f, S.stringof ~ " to " ~ D.stringof);
                    assert(d == 0, S.stringof ~ " to " ~ D.stringof);
                }
            }
        }
    }
}

nothrow unittest // ConvertHandler.cast(bool)
{
    import std.meta : AliasSeq;

    ConvertHandler handler;
    bool f;

    static foreach (S; AliasSeq!(byte, ubyte, short, ushort, int, uint, long, ulong, float, double, real, char, wchar, dchar))
    {
        {
            S s;
            bool d;

            f = ConvertHandler.find!(S, bool)(handler);
            assert(f);
            assert(handler.doCast !is null);

            s = 1;
            d = false;
            f = handler.doCast(&s, &d);
            assert(f, S.stringof ~ " to " ~ bool.stringof);
            assert(d, S.stringof ~ " to " ~ bool.stringof);

            s = S.max;
            d = false;
            f = handler.doCast(&s, &d);
            assert(f, S.stringof ~ " to " ~ bool.stringof);
            assert(d, S.stringof ~ " to " ~ bool.stringof);

            s = 0;
            d = true;
            f = handler.doCast(&s, &d);
            assert(f, S.stringof ~ " to " ~ bool.stringof);
            assert(!d, S.stringof ~ " to " ~ bool.stringof);

            static if (isFloatingPoint!S)
            {
                s = S.nan;
                d = true;
                f = handler.doCast(&s, &d);
                assert(f, S.stringof ~ " to " ~ bool.stringof);
                assert(!d, S.stringof ~ " to " ~ bool.stringof);
            }
        }
    }
}

nothrow unittest // ConvertHandler.coerce(string)
{
    import std.conv : to;
    import std.meta : AliasSeq;

    ConvertHandler handler;
    bool f;

    static foreach (S; AliasSeq!(char, wchar, dchar))
    {
        static foreach (D; AliasSeq!(char, wchar, dchar))
        {
            {
                scope (failure) assert(0, "Assume nothrow failed");

                auto foo = "this is a foo?".to!(StringOfChar!S)();
                auto food = foo.to!(StringOfChar!D)();

                StringOfChar!D d;

                f = ConvertHandler.find!(S[], StringOfChar!D)(handler);
                assert(f);
                assert(handler.doCoerce !is null);
                S[] s = foo.dup;
                d = null;
                f = handler.doCoerce(&s, &d);
                assert(f, S[].stringof ~ " to " ~ StringOfChar!D.stringof);
                assert(d == food, S[].stringof ~ " to " ~ StringOfChar!D.stringof);

                f = ConvertHandler.find!(StringOfChar!S, StringOfChar!D)(handler);
                assert(f);
                assert(handler.doCoerce !is null);
                d = null;
                f = handler.doCoerce(&foo, &d);
                assert(f, StringOfChar!S.stringof ~ " to " ~ StringOfChar!D.stringof);
                assert(d == food, StringOfChar!S.stringof ~ " to " ~ StringOfChar!D.stringof);
            }
        }
    }

    static foreach (S; AliasSeq!(char, wchar, dchar))
    {
        {
            scope (failure) assert(0, "Assume nothrow failed");

            auto foo = "this is a foo?".to!(StringOfChar!S)();
            ConstStringOfChar!S d;

            f = ConvertHandler.find!(S[], ConstStringOfChar!S)(handler);
            assert(f);
            assert(handler.doCoerce !is null);
            S[] s = foo.dup;
            d = null;
            f = handler.doCoerce(&s, &d);
            assert(f, S[].stringof ~ " to " ~ ConstStringOfChar!S.stringof);
            assert(d.ptr is s.ptr, S[].stringof ~ " to " ~ ConstStringOfChar!S.stringof);

            f = ConvertHandler.find!(StringOfChar!S, ConstStringOfChar!S)(handler);
            assert(f);
            assert(handler.doCoerce !is null);
            d = null;
            f = handler.doCoerce(&foo, &d);
            assert(f, StringOfChar!S.stringof ~ " to " ~ ConstStringOfChar!S.stringof);
            assert(d.ptr is foo.ptr, StringOfChar!S.stringof ~ " to " ~ ConstStringOfChar!S.stringof);
        }
    }

    static foreach (S; AliasSeq!(char, wchar, dchar))
    {
        {
            S s;
            StringOfChar!S d;

            f = ConvertHandler.find!(S, StringOfChar!S)(handler);
            assert(f);
            assert(handler.doCoerce !is null);
            s = 'B';
            f = handler.doCoerce(&s, &d);
            assert(f, S.stringof ~ " to " ~ StringOfChar!S.stringof);
            assert(d == "B", S.stringof ~ " to " ~ StringOfChar!S.stringof);
        }
    }
}
