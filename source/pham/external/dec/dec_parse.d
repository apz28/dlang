module pham.external.dec.dec_parse;

import core.checkedint: adds;
import std.range.primitives: ElementType, isInputRange;
import std.traits: isSomeChar, Unqual;

import pham.external.dec.dec_decimal : isDecimal;
import pham.external.dec.dec_integral : divrem, fma;
import pham.external.dec.dec_math : coefficientAdjust, coefficientShrink;
import pham.external.dec.dec_range;
import pham.external.dec.dec_type;

nothrow @safe:
package(pham.external.dec):

D parse(D, R)(ref R range)
if (isDecimal!D && isInputRange!R && isSomeChar!(ElementType!R))
{
    Unqual!D result = void;
    ExceptionFlags flags;
    if (parse(range, result, flags, D.realPrecision(DecimalControl.precision), DecimalControl.rounding))
    {
        if (flags)
            DecimalControl.raiseFlags(flags);
        return result;
    }
    else
    {
        DecimalControl.throwFlags(ExceptionFlags.invalidOperation);
        return result;
    }
}

bool parse(D, R)(ref R range, out D decimal, out ExceptionFlags flags, const(int) precision, const(RoundingMode) mode)
if (isDecimal!D && isInputRange!R && isSomeChar!(ElementType!R))
{
    DataType!(D.sizeof) coefficient;
    int exponent;
    bool isinf, isnan, signaling, signed;
    
    if (!parseDecimal(range, coefficient, exponent, flags, isinf, isnan, signaling, isnegative))
    {
        decimal.invalidPack(isnegative);
        return false;
    }

    if (flags & ExceptionFlags.invalidOperation)
    {
        decimal.invalidPack(isnegative, coefficient);
        return true;
    }

    if (signaling)
        decimal.data = D.MASK_SNAN;
    else if (isnan)
        decimal.data = D.MASK_QNAN;
    else if (isinf)
        decimal.data = D.MASK_INF;
    else if (coefficient == 0)
        decimal.data = D.MASK_ZERO;
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
        
    return true;
}

bool parseDecimal(R, T)(ref R range, out T coefficient, out int exponent, ExceptionFlags flags,
    out bool isinf, out bool isnan, out bool signaling, out bool signed, out bool wasHex) nothrow pure @safe
if (isInputRange!R && isSomeChar!(ElementType!R))
{
    import std.range.primitives: empty, front, popFront;

    exponent = 0;
    flags = ExceptionFlags.none;
    isinf = isnan = signaling = signed = wasHex = false;

    // Special try construct for grep
    try {
        while (expect(range, '_'))
        { }
        if (range.empty)
            return false;

        bool hasSign = parseSign(range, signed);
        if (hasSign && range.empty)
        {
            flags |= ExceptionFlags.invalidOperation;
            return false;
        }

        switch (range.front)
        {
            // For most likely mached case should be first
            case '1': .. case '9':
                return parseDecimalFloat(range, false, coefficient, exponent, flags);
            case '0':
                range.popFront();
                if (expectInsensitive(range, 'x'))
                {
                    wasHex = true;
                    return parseDecimalHex(range, coefficient, exponent, flags);
                }
                else
                    return parseDecimalFloat(range, true, coefficient, exponent, flags);
            case 'n':
            case 'N':
                isnan = true;
                signaling = false;
                if (!parseNaN(range, coefficient))
                {
                    flags |= ExceptionFlags.invalidOperation;
                    return false;
                }
                return range.empty;
            case 'i':
            case 'I':
                isinf = true;
                if (!parseInfinity(range))
                {
                    flags |= ExceptionFlags.invalidOperation;
                    return false;
                }
                return range.empty;
            case 's':
            case 'S':
                isnan = true;
                signaling = true;
                range.popFront();
                if (!parseNaN(range, coefficient))
                {
                    flags |= ExceptionFlags.invalidOperation;
                    return false;
                }
                return range.empty;
            case '.':
                return parseDecimalFloat(range, false, coefficient, exponent, flags);
            default:
                flags |= ExceptionFlags.invalidOperation;
                return false;
        }
    } catch (Exception) return false;
}

bool parseDecimalFloat(R, T)(ref R range, const(bool) zeroPrefix, out T coefficient, out int exponent, out ExceptionFlags flags)
if (isInputRange!R && isSomeChar!(ElementType!R))
{
    if (!parseNumberAndExponent(range, zeroPrefix, coefficient, exponent, flags))
        return false;
    
    if (!expectInsensitive(range, 'e'))
    {
        if (range.empty)
            return true;
        flags |= ExceptionFlags.invalidOperation;
        return false;
    }
    
    uint e;
    bool signedExponent;
    parseSign(range, signedExponent);
    if (parseNumber(range, e) == 0)
    {
        flags |= ExceptionFlags.invalidOperation;
        return false;
    }
    
    bool overflow;
    if (!signedExponent)
    {
        if (e > int.max)
        {
            exponent = int.max;
            flags |= ExceptionFlags.overflow;
        }
        else
            exponent = adds(exponent, cast(int)e, overflow);
    }
    else
    {
        if (e > -int.min || overflow)
        {
            exponent = int.min;
            flags |= ExceptionFlags.underflow;
        }
        else
            exponent = adds(exponent, cast(int)(-e), overflow);
    }
    if (overflow)
        flags |= exponent > 0 ? ExceptionFlags.underflow : ExceptionFlags.overflow;
    
    return range.empty;
}

bool parseDecimalHex(R, T)(ref R range, out T coefficient, out int exponent, out ExceptionFlags flags)
if (isInputRange!R && isSomeChar!(ElementType!R))
{
    exponent = 0;
    flags = ExceptionFlags.none;
    
    if (parseHexNumber(range, coefficient) == 0)
        return false;
    
    if (!expectInsensitive(range, 'p'))
    {
        if (range.empty)
            return true;
        flags |= ExceptionFlags.invalidOperation;
        return false; 
    }
    
    uint e;
    bool signedExponent;
    parseSign(range, signedExponent);
    if (parseNumber(range, e) == 0)
    {
        flags |= ExceptionFlags.invalidOperation;
        return false;
    }
    
    if (signedExponent && e > -int.min)
    {
        exponent = int.min;
        flags |= ExceptionFlags.underflow;
    }
    else if (!signedExponent && e > int.max)
    {
        exponent = int.max;
        flags |= ExceptionFlags.overflow;
    }
    
    exponent = signedExponent ? -e : e;
    
    return range.empty;
}

//returns corresponding bracket and advances range if any of "([{<" is encountered, 0 otherwise
ElementType!R parseBracket(R)(ref R range) @nogc nothrow pure @safe
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
        return '\0';
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
int parseDigit(R)(ref R range) @nogc nothrow pure @safe
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
int parseHexDigit(R)(ref R range) @nogc nothrow pure @safe
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
uint parseHexNumber(R, T)(ref R range, out T value) @nogc nothrow pure @safe
if (isInputRange!R && isSomeChar!(ElementType!R))
{
    auto result = parseZeroes(range);
    enum maxWidth = T.sizeof * 2;
    int width = 0;
    while (width < maxWidth && !range.empty)
    {
        const digit = parseHexDigit(range);
        if (digit >= 0)
        {
            value = (value << 4) | cast(uint)digit;
            ++width;
            ++result;
        }
        else
            break;
    }
    return result;
}

unittest
{
    import pham.external.dec.dec_integral : uint128;

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
    assert(parseHexNumber(s, result3) && result3.hi == 0x1234_5678_9ABC_DEF1 && result3.lo == 0x2345_6789_ABCD_EF12, "a");
    assert(parseHexNumber(s, result3) && result3 == 0x0U);
    assert(!parseHexNumber(s, result3));
}

//parses hexadecimals if starts with 0x, otherwise decimals, false on failure
uint parseHexNumberOrNumber(R, T)(ref R range, ref T value, out bool wasHex)
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
            return parseNumber(range, value) +1;
    }
    else
        return parseNumber(range, value);
}

//returns true and advances range if "inf" or "infinity" is encountered
bool parseInfinity(R)(ref R range) @nogc nothrow pure @safe
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
uint parseNumber(R, T)(ref R range, ref T value) @nogc nothrow pure @safe
if (isInputRange!R && isSomeChar!(ElementType!R))
{
    auto result = parseZeroes(range);
    while (!range.empty)
    {
        const f = range.front;
        if (f >= '0' && f <= '9')
        {
            const uint digit = f - '0';
            bool overflow;
            Unqual!T v = fma(value, 10U, digit, overflow);
            if (overflow)
                break;
            range.popFront();
            value = v;
            ++result;
        }
        else if (f == '_')
            range.popFront();
        else
            break;
    }
    return result;
}

//returns true if a decimal number can be read in value, stops if doesn't fit in value
bool parseNumberAndExponent(R, T)(ref R range, const(bool) zeroPrefix, out T value, out int exponent, out ExceptionFlags flags)
if (isInputRange!R && isSomeChar!(ElementType!R))
{
    import std.range.primitives : empty, front, popFront;

    exponent = 0;
    flags = ExceptionFlags.none;
    
    // Special try construct for grep
    try {
        bool afterDecimalPoint = false;
        auto atLeastOneDigits = parseZeroes(range) + cast(ubyte)zeroPrefix;
        uint atLeastOneFractionalDigits;
        
        while (!range.empty)
        {
            const f = range.front;
            if (f >= '0' && f <= '9')
            {
                const uint digit = f - '0';
                bool overflow;
                Unqual!T v = fma(value, 10U, digit, overflow);
                if (overflow)
                {
                    //try to shrink the coefficient, this will loose some zeros
                    coefficientShrink(value, exponent);
                    overflow = false;
                    v = fma(value, 10U, digit, overflow);
                    if (overflow)
                    {
                        if (afterDecimalPoint)
                            flags |= ExceptionFlags.inexact;
                        else
                            flags |= ExceptionFlags.overflow;
                        break;
                    }
                }
                range.popFront();
                value = v;
                if (afterDecimalPoint)
                {
                    --exponent;
                    ++atLeastOneFractionalDigits;
                }
                else
                    ++atLeastOneDigits;
            }
            else if (f == '.' && !afterDecimalPoint)
            {
                afterDecimalPoint = true;
                range.popFront();
            }
            else if (f == '_')
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
            const f = range.front;
            if (f >= '0' && f <= '9')
            {
                const uint digit = f - '0';
                if (digit != 0)
                    flags |= ExceptionFlags.inexact;
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
                range.popFront();
                if (afterDecimalPoint)
                    ++atLeastOneFractionalDigits;
                else
                {
                    ++exponent;
                    ++atLeastOneDigits;
                }
            }
            else if (f == '.' && !afterDecimalPoint)
            {
                afterDecimalPoint = true;
                range.popFront();
            }
            else if (f == '_')
                range.popFront();
            else
                break;
        }

        //just increase exponent before decimal point
        while (!range.empty)
        {
            const f = range.front;
            if (f >= '0' && f <= '9')
            {
                if (f != '0')
                    flags |= ExceptionFlags.inexact;
                range.popFront();
                if (afterDecimalPoint)
                    ++atLeastOneFractionalDigits;
                else
                {
                   ++exponent;
                   ++atLeastOneDigits;
                }
            }
            else if (f == '.' && !afterDecimalPoint)
            {
                afterDecimalPoint = true;
                range.popFront();
            }
            else if (f == '_')
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

        return (atLeastOneDigits + atLeastOneFractionalDigits) != 0;    
    } catch (Exception) return false;
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

bool parseSign(R)(ref R range, out bool isNegative) @nogc nothrow pure @safe
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
uint parseZeroes(R)(ref R range) @nogc nothrow pure @safe
if (isInputRange!R && isSomeChar!(ElementType!R))
{
    uint result = 0;
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
