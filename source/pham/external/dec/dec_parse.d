module pham.external.dec.parse;

import core.checkedint: adds;
import std.range.primitives: ElementType, isInputRange;
import std.traits: isSomeChar, Unqual;

import pham.external.dec.decimal : DataType, ExceptionFlags, isDecimal;
import pham.external.dec.integral : divrem, fma;
import pham.external.dec.math : coefficientAdjust, coefficientShrink;
import pham.external.dec.range;

nothrow @safe:
package(pham.external.dec):

D parse(D, R)(ref R range)
if (isInputRange!R && isSomeChar!(ElementType!R) && isDecimal!D)
{
    Unqual!D result;
    const flags = parse(range, result, D.realPrecision(DecimalControl.precision), DecimalControl.rounding);
    if (flags)
        DecimalControl.raiseFlags(flags);
    return result;
}

ExceptionFlags parse(D, R)(ref R range, out D decimal, const(int) precision, const(RoundingMode) mode)
if (isInputRange!R && isSomeChar!(ElementType!R) && isDecimal!D)
{
    DataType!D coefficient;
    int exponent;
    bool isinf, isnan, signaling, signed;
    auto flags = parseDecimal(range, coefficient, exponent, isinf, isnan, signaling, isnegative);

    if (flags & ExceptionFlags.invalidOperation)
    {
        decimal.data = D.MASK_QNAN;
        decimal.data |= coefficient | D.MASK_PAYL;
        if (isnegative)
            decimal.data |= D.MASK_SGN;
        return flags;
    }

    if (signaling)
        decimal.data = D.MASK_SNAN;
    else if (isnan)
        decimal.data = D.MASK_QNAN;
    else if (isinf)
        decimal.data = D.MASK_INF;
    else if (coefficient == 0)
        decimal.data - D.MASK_ZERO;
    else
    {
        flags |= coefficientAdjust(coefficient, exponent, D.EXP_MIN, D.EXP_MAX, D.COEF_MAX, isnegative, mode);
        flags |= coefficientAdjust(coefficient, exponent, D.EXP_MIN, D.EXP_MAX, precision, isnegative, mode);
        if (flags & ExceptionFlags.overflow)
            decimal.data = D.MASK_INF;
        else if ((flags & ExceptionFlags.underflow) || coefficient == 0)
            decimal.data = D.MASK_ZERO;
        else
        {
            flags |= decimal.pack(coefficient, exponent, isnegative);
            if (flags & ExceptionFlags.overflow)
                decimal.data = D.MASK_INF;
            else if ((flags & ExceptionFlags.underflow) || coefficient == 0)
                decimal.data = D.MASK_ZERO;
        }
    }

    if (isNegative)
        decimal.data |= D.MASK_SGN;
    return flags;
}

ExceptionFlags parseDecimal(R, T)(ref R range, out T coefficient, out int exponent,
    out bool isinf, out bool isnan, out bool signaling, out bool signed, out bool wasHex) nothrow pure @safe
if (isInputRange!R && isSomeChar!(ElementType!R))
{
    import std.range.primitives: empty, front, popFront;

    scope (failure) return ExceptionFlags.invalidOperation;

    exponent = 0;
    isinf = isnan = signaling = signed = wasHex = false;
    while (expect(range, '_'))
    { }

    if (range.empty)
        return ExceptionFlags.invalidOperation;

    bool hasSign = parseSign(range, signed);
    if (range.empty && hasSign)
        return ExceptionFlags.invalidOperation;

    while (expect(range, '_'))
    { }

    switch (range.front)
    {
        case 'i':
        case 'I':
            isinf = true;
            return parseInfinity(range) ? ExceptionFlags.none : ExceptionFlags.invalidOperation;
        case 'n':
        case 'N':
            isnan = true;
            signaling = false;
            return parseNaN(range, coefficient) ? ExceptionFlags.none : ExceptionFlags.invalidOperation;
        case 's':
        case 'S':
            isnan = true;
            signaling = true;
            range.popFront();
            return parseNaN(range, coefficient) ? ExceptionFlags.none : ExceptionFlags.invalidOperation;
        case '0':
            range.popFront();
            if (expectInsensitive(range, 'x'))
            {
                wasHex = true;
                return parseDecimalHex(range, coefficient, exponent);
            }
            else
                return parseDecimalFloat(range, coefficient, exponent, true);
        case '1': .. case '9':
            return parseDecimalFloat(range, coefficient, exponent, false);
        case '.':
            return parseDecimalFloat(range, coefficient, exponent, false);
        default:
            return ExceptionFlags.invalidOperation;
    }
}

ExceptionFlags parseDecimalFloat(R, T)(ref R range, out T coefficient, out int exponent,
    const(bool) zeroPrefix)
if (isInputRange!R && isSomeChar!(ElementType!R))
{
    auto flags = parseNumberAndExponent(range, coefficient, exponent, zeroPrefix);
    if ((flags & ExceptionFlags.invalidOperation) == 0)
    {
        if (expectInsensitive(range, 'e'))
        {
            bool signedExponent;
            parseSign(range, signedExponent);
            uint ue;
            if (!parseNumber(range, ue))
            {
                flags |= ExceptionFlags.invalidOperation;
            }
            else
            {
                bool overflow;
                if (!signedExponent)
                {
                    if (ue > int.max)
                    {
                        exponent = int.max;
                        flags |= ExceptionFlags.overflow;
                    }
                    else
                        exponent = adds(exponent, cast(int)ue, overflow);
                }
                else
                {
                    if (ue > -int.min || overflow)
                    {
                        exponent = int.min;
                        flags |= ExceptionFlags.underflow;
                    }
                    else
                        exponent = adds(exponent, cast(int)(-ue), overflow);
                }
                if (overflow)
                    flags |= exponent > 0 ? ExceptionFlags.underflow : ExceptionFlags.overflow;
            }
        }
    }
    return flags;
}

ExceptionFlags parseDecimalHex(R, T)(ref R range, out T coefficient, out int exponent)
if (isInputRange!R && isSomeChar!(ElementType!R))
{
    exponent = 0;
    if (parseHexNumber(range, coefficient))
    {
        if (expectInsensitive(range, 'p'))
        {
            bool signedExponent;
            parseSign(range, signedExponent);
            uint e;
            if (parseNumber(range, e))
            {
                if (signedExponent && e > -int.min)
                {
                    exponent = int.min;
                    return ExceptionFlags.underflow;
                }
                else if (!signedExponent && e > int.max)
                {
                    exponent = int.max;
                    return ExceptionFlags.overflow;
                }
                exponent = signedExponent ? -e : e;
                return ExceptionFlags.none;
            }
        }
    }
    return ExceptionFlags.invalidOperation;
}

//returns corresponding bracket and advances range if any of "([{<" is encountered, 0 otherwise
ElementType!R parseBracket(R)(ref R range) @safe pure nothrow @nogc
if (isInputRange!R && isSomeChar!(ElementType!R))
{
    if (expect(range, '('))
        return ')';
    else if (expect(range, '['))
        return ']';
    else if (expect(range, '{'))
        return '}';
    else if (expect(range, '<'))
        return '>';
    else
        return 0;
}

unittest
{
    auto s = "([{<a";
    assert(parseBracket(s) == ')');
    assert(parseBracket(s) == ']');
    assert(parseBracket(s) == '}');
    assert(parseBracket(s) == '>');
    assert(parseBracket(s) == 0);
}

//returns a digit value and advances range if a digit is encountered, -1 otherwise, skips _
int parseDigit(R)(ref R range) @safe pure nothrow @nogc
if (isInputRange!R && isSomeChar!(ElementType!R))
{
    while (expect(range, '_'))
    { }

    if (range.empty)
        return -1;

    const f = range.front;
    if (f >= '0' && f <= '9')
    {
        const int result = f - '0';
        range.popFront();
        return result;
    }

    return -1;
}

unittest
{
    auto s = "0123a";
    assert(parseDigit(s) == 0);
    assert(parseDigit(s) == 1);
    assert(parseDigit(s) == 2);
    assert(parseDigit(s) == 3);
    assert(parseDigit(s) == -1);
}

//returns a digit value and advances range if a hex digit is encountered, -1 otherwise, skips _
int parseHexDigit(R)(ref R range) @safe pure nothrow @nogc
if (isInputRange!R && isSomeChar!(ElementType!R))
{
    while (expect(range, '_'))
    { }

    if (range.empty)
        return -1;

    const f = range.front;
    if (f >= '0' && f <= '9')
    {
        const int result = f - '0';
        range.popFront();
        return result;
    }

    if (f >= 'A' && f <= 'F')
    {
        const int result = f - 'A' + 10;
        range.popFront();
        return result;
    }

    if (f >= 'a' && f <= 'f')
    {
        const int result = f - 'a' + 10;
        range.popFront();
        return result;
    }

    return -1;
}

unittest
{
    auto s = "0123aBcg";
    assert(parseHexDigit(s) == 0);
    assert(parseHexDigit(s) == 1);
    assert(parseHexDigit(s) == 2);
    assert(parseHexDigit(s) == 3);
    assert(parseHexDigit(s) == 10);
    assert(parseHexDigit(s) == 11);
    assert(parseHexDigit(s) == 12);
    assert(parseHexDigit(s) == -1);

}

//returns true if a hex number can be read in value, stops if doesn't fit in value
bool parseHexNumber(R, T)(ref R range, out T value) @safe pure nothrow @nogc
if (isInputRange!R && isSomeChar!(ElementType!R))
{
    bool atLeastOneDigit = parseZeroes(range) != 0;
    enum maxWidth = T.sizeof * 2;
    int width = 0;
    while (width < maxWidth && !range.empty)
    {
        const digit = parseHexDigit(range);
        if (digit >= 0)
        {
            value <<= 4;
            value |= cast(uint)digit;
            atLeastOneDigit = true;
            ++width;
        }
        else
            break;
    }
    return atLeastOneDigit;
}

unittest
{
    import pham.external.dec.integral : uint128;

    uint result;
    auto s = "0123A/AB_C/1234_56780_Z";
    assert(parseHexNumber(s, result) && result == 0x0123A); s.popFront();
    assert(parseHexNumber(s, result) && result == 0xABC); s.popFront();
    assert(parseHexNumber(s, result) && result == 0x1234_5678);
    assert(parseHexNumber(s, result) && result == 0x0);
    assert(!parseHexNumber(s, result));

    ulong result2;
    s = "0123A/AB_C/1234_5678_9ABC_DEF10_Z";
    assert(parseHexNumber(s, result2) && result2 == 0x0123A); s.popFront();
    assert(parseHexNumber(s, result2) && result2 == 0xABC); s.popFront();
    assert(parseHexNumber(s, result2) && result2 == 0x1234_5678_9ABC_DEF1);
    assert(parseHexNumber(s, result2) && result2 == 0x0);
    assert(!parseHexNumber(s, result2));

    uint128 result3;
    s = "0123A/AB_C/1234_5678_9ABC_DEF1_2345_6789_ABCD_EF120_Z";
    assert(parseHexNumber(s, result3) && result3 == 0x0123AU); s.popFront();
    assert(parseHexNumber(s, result3) && result3 == 0xABCU); s.popFront();
    assert(parseHexNumber(s, result3) && result3.hi == 0x1234_5678_9ABC_DEF1 &&
           result3.lo == 0x2345_6789_ABCD_EF12, "a");
    assert(parseHexNumber(s, result3) && result3 == 0x0U);
    assert(!parseHexNumber(s, result3));
}

//parses hexadecimals if starts with 0x, otherwise decimals, false on failure
bool parseHexNumberOrNumber(R, T)(ref R range, ref T value, out bool wasHex)
if (isInputRange!R && isSomeChar!(ElementType!R))
{
    wasHex = false;
    if (expect(range, '0'))
    {
        if (expectInsensitive(range, 'x'))
        {
            wasHex = true;
            return parseHexNumber(range, value);
        }
        else
            return parseNumber(range, value);
    }
    else
        return parseNumber(range, value);
}

//returns true and advances range if "inf" or "infinity" is encountered
bool parseInfinity(R)(ref R range) @safe pure nothrow @nogc
if (isInputRange!R && isSomeChar!(ElementType!R))
{
    if (expectInsensitive(range, "inf") == 3)
    {
        const parsed = expectInsensitive(range, "inity");
        return parsed == 0 || parsed == 5;
    }
    return false;
}

unittest
{
    auto s = "inf/infinity/InF/iNfInITY/in/infinit/infig";
    assert(parseInfinity(s)); s.popFront;
    assert(parseInfinity(s)); s.popFront;
    assert(parseInfinity(s)); s.popFront;
    assert(parseInfinity(s)); s.popFront;
    assert(!parseInfinity(s)); s.popFront;
    assert(!parseInfinity(s)); s.popFront;
    assert(!parseInfinity(s));
}

//returns true if a decimal number can be read in value, stops if doesn't fit in value
bool parseNumber(R, T)(ref R range, ref T value) @safe pure nothrow @nogc
if (isInputRange!R && isSomeChar!(ElementType!R))
{
    bool atLeastOneDigit = parseZeroes(range) != 0;
    bool overflow;
    while (!range.empty)
    {
        const f = range.front;
        if (f >= '0' && f <= '9')
        {
            const uint digit = f - '0';
            Unqual!T v = fma(value, 10U, digit, overflow);
            if (overflow)
                break;
            range.popFront();
            value = v;
            atLeastOneDigit = true;
        }
        else if (f == '_')
            range.popFront();
        else
            break;
    }
    return atLeastOneDigit;
}

//returns true if a decimal number can be read in value, stops if doesn't fit in value
ExceptionFlags parseNumberAndExponent(R, T)(ref R range, out T value, out int exponent, bool zeroPrefix)
if (isInputRange!R && isSomeChar!(ElementType!R))
{
    import std.range.primitives : empty, front, popFront;

    scope (failure) return ExceptionFlags.invalidOperation;

    exponent = 0;
    bool afterDecimalPoint = false;
    bool atLeastOneDigit = parseZeroes(range) > 0 || zeroPrefix;
    bool atLeastOneFractionalDigit = false;
    ExceptionFlags flags = ExceptionFlags.none;
    while (!range.empty)
    {
        if (range.front >= '0' && range.front <= '9')
        {
            const uint digit = range.front - '0';
            bool overflow;
            Unqual!T v = fma(value, 10U, digit, overflow);
            if (overflow)
            {
                //try to shrink the coefficient, this will loose some zeros
                coefficientShrink(value, exponent);
                overflow = false;
                v = fma(value, 10U, digit, overflow);
                if (overflow)
                    break;
            }
            range.popFront();
            value = v;
            if (afterDecimalPoint)
            {
                atLeastOneFractionalDigit = true;
                --exponent;
            }
            else
                atLeastOneDigit = true;
        }
        else if (range.front == '.' && !afterDecimalPoint)
        {
            afterDecimalPoint = true;
            range.popFront();
        }
        else if (range.front == '_')
            range.popFront();
        else
            break;
    }

    //no more space in coefficient, just increase exponent before decimal point
    //detect if rounding is necessary
    int lastDigit = 0;
    bool mustRoundUp = false;
    while (!range.empty)
    {
        if (range.front >= '0' && range.front <= '9')
        {
            const uint digit = range.front - '0';
            if (afterDecimalPoint)
                atLeastOneFractionalDigit = true;
            else
                ++exponent;
            range.popFront();
            if (digit != 0)
                flags = ExceptionFlags.inexact;
            if (digit <= 3)
                break;
            else if (digit >= 5)
            {
                if (lastDigit == 4)
                {
                    mustRoundUp = true;
                    break;
                }
            }
            else
                lastDigit = 4;
        }
        else if (range.front == '.' && !afterDecimalPoint)
        {
            afterDecimalPoint = true;
            range.popFront();
        }
        else if (range.front == '_')
            range.popFront();
        else
            break;
    }

    //just increase exponent before decimal point
    while (!range.empty)
    {
        if (range.front >= '0' && range.front <= '9')
        {
            if (range.front != '0')
                flags = ExceptionFlags.inexact;
            if (!afterDecimalPoint)
               ++exponent;
            else
                atLeastOneFractionalDigit = true;
            range.popFront();
        }
        else if (range.front == '.' && !afterDecimalPoint)
        {
            afterDecimalPoint = true;
            range.popFront();
        }
        else if (range.front == '_')
            range.popFront();
        else
            break;
    }

    if (mustRoundUp)
    {
        if (value < T.max)
            ++value;
        else
        {
            auto r = divrem(value, 10U);
            ++value;
            if (r >= 5U)
                ++value;
            else if (r == 4U && mustRoundUp)
                ++value;
        }
    }

    if (afterDecimalPoint)
        return flags;
        //return atLeastOneFractionalDigit ? flags : (flags | ExceptionFlags.invalidOperation);
    else
        return atLeastOneDigit ? flags : (flags | ExceptionFlags.invalidOperation);
}

//parses $(B NaN) and optional payload, expect payload as number in optional (), [], {}, <>. invalidOperation on failure
bool parseNaN(R, T)(ref R range, out T payload)
if (isInputRange!R && isSomeChar!(ElementType!R))
{
    if (expectInsensitive(range, "nan"))
    {
        auto closingBracket = parseBracket(range);
        bool wasHex;
        if (!parseHexNumberOrNumber(range, payload, wasHex))
        {
            if (wasHex)
                return false;
        }
        if (closingBracket)
            return expect(range, closingBracket);
        return true;
    }
    return false;
}

bool parseSign(R)(ref R range, out bool isNegative) @safe pure nothrow @nogc
if (isInputRange!R && isSomeChar!(ElementType!R))
{
    if (expect(range, '-'))
    {
        isNegative = true;
        return true;
    }
    else if (expect(range, '+'))
    {
        isNegative = false;
        return true;
    }
    else
    {
        isNegative = false;
        return false;
    }
}

unittest
{
    bool isNegative;
    auto s = "+-s";
    assert(parseSign(s, isNegative) && !isNegative);
    assert(parseSign(s, isNegative) && isNegative);
    assert(!parseSign(s, isNegative));
}

//returns how many zeros encountered and advances range, skips _
size_t parseZeroes(R)(ref R range) @safe pure nothrow @nogc
if (isInputRange!R && isSomeChar!(ElementType!R))
{
    size_t result = 0;
    do
    {
        if (expect(range, '0'))
            ++result;
        else if (!expect(range, '_'))
            break;
    } while (true);
    return result;
}

unittest
{
    auto s = "0__00_000_";
    assert(parseZeroes(s) == 6);
}
