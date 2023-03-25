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

module pham.external.dec.variant_coerce;


// All implement after this point must be private
private:

import std.traits : isFloatingPoint, isIntegral, isSomeChar;
import std.meta : AliasSeq;

import pham.external.dec.decimal : Decimal32, Decimal64, Decimal128, DecimalControl, ExceptionFlags, isDecimal, RoundingMode;
import pham.utl.variant_coerce;

// Support Variant.coerce
bool doCoerceDecimal(S, D)(scope void* srcPtr, scope void* dstPtr) nothrow
if ((isFloatingPoint!S || isIntegral!S || isSomeChar!S || isDecimal!S) && isDecimal!D)
{
    const savedState = DecimalControl.clearState();
    scope (exit)
        DecimalControl.restoreState(savedState);
    
    try
    {
        auto r = D(*cast(S*)srcPtr);
        
        static if (isFloatingPoint!S)
        {
            // Ignore the ExceptionFlags.inexact for float
            if (DecimalControl.severe)
                return false;
        }
        else
        {
            if (DecimalControl.flags)
                return false;
        }

        *cast(D*)dstPtr = r;
        return true;
    }
    catch (Exception ex)
    {
        return false;
    }
}

// Support Variant.coerce
bool doCoerceDecimalToNumeric(S, D)(scope void* srcPtr, scope void* dstPtr) nothrow
if (isDecimal!S && (isFloatingPoint!D || isIntegral!D || isSomeChar!D))
{
    const savedState = DecimalControl.clearState();
    scope (exit)
        DecimalControl.restoreState(savedState);
    
    try
    {
        auto r = (*cast(S*)srcPtr).opCast!D();
        
        static if (isFloatingPoint!D)
        {
            // Ignore the ExceptionFlags.inexact for float
            if (DecimalControl.severe)
                return false;
        }
        else
        {
            if (DecimalControl.flags)
                return false;
        }

        *cast(D*)dstPtr = r;
        return true;
    }
    catch (Exception ex)
    {
        return false;
    }
}

shared static this()
{
    // Support Variant.coerce
    ConvertHandler handler, invHandler;
    handler.doCast = invHandler.doCast = null;

    static foreach (S; AliasSeq!(byte, ubyte, short, ushort, int, uint, long, ulong, float, double, real))
    {
        static foreach (D; AliasSeq!(Decimal32, Decimal64, Decimal128))
        {
            handler.doCoerce = &doCoerceDecimal!(S, D);
            ConvertHandler.add!(S, D)(handler);

            // Inverse
            invHandler.doCoerce = &doCoerceDecimalToNumeric!(D, S);
            ConvertHandler.add!(D, S)(invHandler);
        }
    }

    static foreach (S; AliasSeq!(char, wchar, dchar))
    {
        static foreach (D; AliasSeq!(Decimal32, Decimal64, Decimal128))
        {
            handler.doCoerce = &doCoerceDecimal!(S, D);
            ConvertHandler.add!(S, D)(handler);
        }
    }

    static foreach (S; AliasSeq!(Decimal32, Decimal64, Decimal128))
    {
        static foreach (D; AliasSeq!(Decimal32, Decimal64, Decimal128))
        {
            static if (S.sizeof != D.sizeof)
            {
                handler.doCoerce = &doCoerceDecimal!(S, D);
                ConvertHandler.add!(S, D)(handler);

                // Inverse
                invHandler.doCoerce = &doCoerceDecimal!(D, S);
                ConvertHandler.add!(D, S)(invHandler);
            }
        }
    }
}

version (unittest)
T round(T)(T x, ubyte places)
if (isFloatingPoint!T)
{
    static import std.math;
    const p = std.math.pow(10.0, places);
    return cast(T)(std.math.round(x * p) / p);
}

unittest
{
    import std.conv : to;
    import std.format : format;
    import std.math.operations : isClose;
    import std.traits : isSigned, isUnsigned;
    import pham.utl.test;
    traceUnitTest("unittest pham.external.dec.variant_coerce");

    ConvertHandler handler, invHandler;
    bool f;

    static foreach (S; AliasSeq!(byte, ubyte, short, ushort, int, uint, long, ulong))
    {
        static foreach (D; AliasSeq!(Decimal32, Decimal64, Decimal128))
        {
            static if (D.sizeof >= S.sizeof)
            {{
                f = ConvertHandler.find!(S, D)(handler);
                assert(f);
                assert(handler.doCoerce !is null);
                f = ConvertHandler.find!(D, S)(invHandler);
                assert(f);
                assert(invHandler.doCoerce !is null);

                static if (D.sizeof > S.sizeof)
                {
                    enum S checkMin = S.min;
                    enum S checkMax = S.max;
                }
                else static if (D.sizeof == 8)
                {
                    enum S checkMax = 9999_9999_9999_9999L;
                    static if (isUnsigned!S)
                        enum S checkMin = 0L;
                    else
                        enum S checkMin = -9999_9999_9999_9999L;
                }
                else //static if (D.sizeof == 4)
                {
                    enum S checkMax = 999_9999;
                    static if (isUnsigned!S)
                        enum S checkMin = 0;
                    else
                        enum S checkMin = -999_9999;
                }
                
                D d = 1;
                S s = checkMin;
                f = handler.doCoerce(&s, &d);
                assert(f, S.stringof ~ " to " ~ D.stringof);
                assert(d == checkMin, S.stringof ~ " to " ~ D.stringof ~ " : " ~ d.toString() ~ " vs " ~ to!string(checkMin)); // S.stringof ~ " to " ~ D.stringof);

                // Inverse
                s = 1;
                d = checkMin;
                f = invHandler.doCoerce(&d, &s);
                assert(f, D.stringof ~ " to " ~ S.stringof);
                assert(s == checkMin, S.stringof ~ " to " ~ D.stringof ~ " : " ~ D.stringof ~ " to " ~ S.stringof);

                d = 1;
                s = 0;
                f = handler.doCoerce(&s, &d);
                assert(f, S.stringof ~ " to " ~ D.stringof);
                assert(d == 0, S.stringof ~ " to " ~ D.stringof);

                d = 1;
                s = checkMax;
                f = handler.doCoerce(&s, &d);
                assert(f, S.stringof ~ " to " ~ D.stringof);
                assert(d == checkMax, S.stringof ~ " to " ~ D.stringof ~ " : " ~ d.toString() ~ " vs " ~ to!string(checkMax)); // S.stringof ~ " to " ~ D.stringof);

                // Inverse
                s = 1;
                d = checkMax;
                f = invHandler.doCoerce(&d, &s);
                assert(f, D.stringof ~ " to " ~ S.stringof);
                assert(s == checkMax, D.stringof ~ " to " ~ S.stringof);
            }}
            
            // Not convertable
            static if (S.sizeof >= D.sizeof)
            {{
                f = ConvertHandler.find!(S, D)(handler);
                assert(f);
                assert(handler.doCoerce !is null);

                D d;
                S s = S.max;
                assert(!handler.doCoerce(&s, &d));
                
                static if (isSigned!S)
                {
                    s = S.min;
                    assert(!handler.doCoerce(&s, &d));
                }
            }}
        }
    }

    static foreach (S; AliasSeq!(float, double, real))
    {
        static foreach (D; AliasSeq!(Decimal32, Decimal64, Decimal128))
        {
            static if (D.sizeof >= S.sizeof)
            {{
                f = ConvertHandler.find!(S, D)(handler);
                assert(f);
                assert(handler.doCoerce !is null);
                f = ConvertHandler.find!(D, S)(invHandler);
                assert(f);
                assert(invHandler.doCoerce !is null);

                enum S checkMin = cast(S)-281638.80;
                enum S checkMax = cast(S)735376.60;
                
                D d = 1;
                S s = checkMin;
                f = handler.doCoerce(&s, &d);
                assert(f, S.stringof ~ " to " ~ D.stringof ~ " for " ~ format("%f", checkMin));
                assert(d == D(checkMin), S.stringof ~ " to " ~ D.stringof ~ " for " ~ d.toString() ~ " vs " ~ format("%f", checkMin));

                // Inverse
                s = 1;
                d = checkMin;
                f = invHandler.doCoerce(&d, &s);
                assert(f, D.stringof ~ " to " ~ S.stringof);
                assert(isClose(s, checkMin), D.stringof ~ " to " ~ S.stringof ~ " for " ~ format("%f", s) ~ " vs " ~ format("%f", checkMin));

                d = 1;
                s = 0.0;
                f = handler.doCoerce(&s, &d);
                assert(f, S.stringof ~ " to " ~ D.stringof);
                assert(d == 0.0, S.stringof ~ " to " ~ D.stringof);

                d = 1;
                s = checkMax;
                f = handler.doCoerce(&s, &d);
                assert(f, S.stringof ~ " to " ~ D.stringof ~ " for " ~ format("%f", checkMax));
                assert(d == D(checkMax), S.stringof ~ " to " ~ D.stringof ~ " for " ~ d.toString() ~ " vs " ~ format("%f", checkMax));

                // Inverse
                s = 1;
                d = checkMax;
                f = invHandler.doCoerce(&d, &s);
                assert(f, D.stringof ~ " to " ~ S.stringof);
                assert(isClose(s, checkMax), D.stringof ~ " to " ~ S.stringof ~ " for " ~ format("%f", s) ~ " vs " ~ format("%f", checkMax));
            }}
            
            // Not convertable
            static if (S.sizeof > D.sizeof)
            {{
                f = ConvertHandler.find!(S, D)(handler);
                assert(f);
                assert(handler.doCoerce !is null);

                D d;
                S s = S.max;
                assert(!handler.doCoerce(&s, &d));
                
                s = -S.max;
                assert(!handler.doCoerce(&s, &d));
            }}
        }
    }

    static foreach (S; AliasSeq!(char, wchar, dchar))
    {
        static foreach (D; AliasSeq!(Decimal32, Decimal64, Decimal128))
        {
            {
                f = ConvertHandler.find!(S, D)(handler);
                assert(f);
                assert(handler.doCoerce !is null);

                D d = 1;
                S s = S.min;
                f = handler.doCoerce(&s, &d);
                assert(f, S.stringof ~ " to " ~ D.stringof);
                assert(d == S.min, S.stringof ~ " to " ~ D.stringof);

                d = 1;
                s = 0;
                f = handler.doCoerce(&s, &d);
                assert(f, S.stringof ~ " to " ~ D.stringof);
                assert(d == 0, S.stringof ~ " to " ~ D.stringof);

                d = 1;
                s = S.max;
                f = handler.doCoerce(&s, &d);
                assert(f, S.stringof ~ " to " ~ D.stringof);
                assert(d == S.max, S.stringof ~ " to " ~ D.stringof);
            }
        }
    }

    static foreach (S; AliasSeq!(Decimal32, Decimal64, Decimal128))
    {
        static foreach (D; AliasSeq!(Decimal32, Decimal64, Decimal128))
        {
            static if (D.sizeof > S.sizeof)
            {{
                f = ConvertHandler.find!(S, D)(handler);
                assert(f);
                assert(handler.doCoerce !is null);
                f = ConvertHandler.find!(D, S)(invHandler);
                assert(f);
                assert(invHandler.doCoerce !is null);

                D d = 1;
                S s = S.min;
                f = handler.doCoerce(&s, &d);
                assert(f, S.stringof ~ " to " ~ D.stringof);
                assert(d == S.min, S.stringof ~ " to " ~ D.stringof);

                // Inverse
                s = 1;
                d = S.min;
                f = invHandler.doCoerce(&d, &s);
                assert(f, D.stringof ~ " to " ~ S.stringof);
                assert(s == S.min, D.stringof ~ " to " ~ S.stringof);

                d = 1;
                s = 0;
                f = handler.doCoerce(&s, &d);
                assert(f, S.stringof ~ " to " ~ D.stringof);
                assert(d == 0, S.stringof ~ " to " ~ D.stringof);

                d = 1;
                s = S.max;
                f = handler.doCoerce(&s, &d);
                assert(f, S.stringof ~ " to " ~ D.stringof);
                assert(d == S.max, S.stringof ~ " to " ~ D.stringof);

                // Inverse
                s = 1;
                d = S.max;
                f = invHandler.doCoerce(&d, &s);
                assert(f, D.stringof ~ " to " ~ S.stringof);
                assert(s == S.max, D.stringof ~ " to " ~ S.stringof);
            }}

            static if (D.sizeof < S.sizeof)
            {{
                f = ConvertHandler.find!(S, D)(handler);
                assert(f);
                assert(handler.doCoerce !is null);
                f = ConvertHandler.find!(D, S)(invHandler);
                assert(f);
                assert(invHandler.doCoerce !is null);

                D d = 1;
                S s = D.min;
                f = handler.doCoerce(&s, &d);
                assert(f, S.stringof ~ " to " ~ D.stringof);
                assert(d == D.min, S.stringof ~ " to " ~ D.stringof);

                // Inverse
                s = 1;
                d = D.min;
                f = invHandler.doCoerce(&d, &s);
                assert(f, D.stringof ~ " to " ~ S.stringof);
                assert(s == D.min, D.stringof ~ " to " ~ S.stringof);

                d = 1;
                s = 0;
                f = handler.doCoerce(&s, &d);
                assert(f, S.stringof ~ " to " ~ D.stringof);
                assert(d == 0, S.stringof ~ " to " ~ D.stringof);

                d = 1;
                s = D.max;
                f = handler.doCoerce(&s, &d);
                assert(f, S.stringof ~ " to " ~ D.stringof);
                assert(d == D.max, S.stringof ~ " to " ~ D.stringof);

                // Inverse
                s = 1;
                d = D.max;
                f = invHandler.doCoerce(&d, &s);
                assert(f, D.stringof ~ " to " ~ S.stringof);
                assert(s == D.max, D.stringof ~ " to " ~ S.stringof);
            }}
        }
    }
}

unittest
{
    import pham.utl.variant;
    import pham.utl.test;
    traceUnitTest("unittest pham.external.dec.variant_coerce");

    Variant v;

    v = Decimal32(100);
    assert(v.coerce!Decimal32() == 100.0);
    assert(v.coerce!Decimal64() == 100.0);
    assert(v.coerce!Decimal128() == 100.0);
    assert(v.coerce!float() == 100.0);
    assert(v.coerce!double() == 100.0);

    v = Decimal64(1000);
    assert(v.coerce!Decimal32() == 1000.0);
    assert(v.coerce!Decimal64() == 1000.0);
    assert(v.coerce!Decimal128() == 1000.0);
    assert(v.coerce!float() == 1000.0);
    assert(v.coerce!double() == 1000.0);

    v = Decimal128(11000);
    assert(v.coerce!Decimal32() == 11000.0);
    assert(v.coerce!Decimal64() == 11000.0);
    assert(v.coerce!Decimal128() == 11000.0);
    assert(v.coerce!float() == 11000.0);
    assert(v.coerce!double() == 11000.0);

    v = float(100);
    assert(v.coerce!Decimal32() == 100.0);
    assert(v.coerce!Decimal64() == 100.0);
    assert(v.coerce!Decimal128() == 100.0);
    assert(v.coerce!float() == 100.0);
    assert(v.coerce!double() == 100.0);
}
