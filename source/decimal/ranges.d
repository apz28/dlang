module decimal.ranges;

import std.range.primitives: ElementType, isInputRange;
import std.traits: isSomeChar, Unqual;
import decimal.integrals: fma, uint128;

package:

//rewrite some range primitives because phobos is performing utf decoding and we are not interested
//in throwing UTFException and consequentely bring the garbage collector into equation
//Also, we don't need any decoding, we are working with the ASCII character set

@safe pure nothrow @nogc
void popFront(T)(ref T[] s)
{
    assert(s.length);
    s = s[1 .. $];
}

@safe pure nothrow @nogc
@property T front(T)(const T[] s)
{
    assert(s.length);
    return s[0];
}

@safe pure nothrow @nogc
@property bool empty(T)(const T[] s)
{
    return !s.length;
}

//returns true and advance range if element is found
bool expect(R, T)(ref R range, T element)
if (isInputRange!R && isSomeChar!T)
{
    if (!range.empty && range.front == element)
    {
        range.popFront();
        return true;
    }
    return false;
}

unittest
{
    auto s = "abc";
    assert(expect(s, 'a'));
    assert(!expect(s, 'B'));
    assert(expect(s, 'b'));
    assert(expect(s, 'c'));
    assert(!expect(s, 'd'));
}

//returns true and advance range if element is found case insensitive
bool expectInsensitive(R, T)(ref R range, T element)
if (isInputRange!R && isSomeChar!T)
{
    if (!range.empty && ((range.front | 32) == (element | 32)))
    {
        range.popFront();
        return true;
    }
    return false;
}

unittest
{
    auto s = "abcABC";
    assert(expectInsensitive(s, 'a'));
    assert(!expectInsensitive(s, 'z'));
    assert(expectInsensitive(s, 'B'));
    assert(expectInsensitive(s, 'c'));
    assert(expectInsensitive(s, 'A'));
    assert(expectInsensitive(s, 'b'));
    assert(expectInsensitive(s, 'C'));
    assert(!expectInsensitive(s, 'd'));
    assert(!expectInsensitive(s, 'D'));
}

//returns parsed characters count and advance range
int expect(R, C)(ref R range, const(C)[] s)
if (isInputRange!R && isSomeChar!C)
{
    int cnt;
    foreach (ch; s)
    {
        if (expect(range, ch))
            ++cnt;
        else
            break;
    }
    return cnt;
}

unittest
{
    auto s = "somestring";
    assert(expect(s, "some") == 4);
    assert(expect(s, "spring") == 1);
    assert(expect(s, "bring") == 0);
    assert(expect(s, "tring") == 5);
}

//returns parsed characters count and advance range insensitive
int expectInsensitive(R, C)(ref R range, const(C)[] s)
if (isInputRange!R && isSomeChar!C)
{
    int cnt;
    foreach(ch; s)
    {
        if (expectInsensitive(range, ch))
            ++cnt;
        else
            break;
    }
    return cnt;
}

unittest
{
    auto s = "sOmEsTrInG";
    assert(expectInsensitive(s, "SoME") == 4);
    assert(expectInsensitive(s, "SPRing") == 1);
    assert(expectInsensitive(s, "bRING") == 0);
    assert(expectInsensitive(s, "TRinG") == 5);
}

bool parseSign(R)(ref R range, out bool isNegative)
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
        return false;
}

unittest
{
    bool isNegative;
    auto s = "+-s";
    assert (parseSign(s, isNegative) && !isNegative);
    assert (parseSign(s, isNegative) && isNegative);
    assert (!parseSign(s, isNegative));
}

//returns true and advances range if "inf" or "infinity" is encountered
bool parseInfinity(R)(ref R range)
if (isInputRange!R && isSomeChar!(ElementType!R))
{
    if (expectInsensitive(range, "inf") == 3)
    {
        auto parsed = expectInsensitive(range, "inity");
        return parsed == 0 || parsed == 5;
    }
    return false;
}

unittest
{
    auto s = "inf/infinity/InF/iNfInITY/in/infinit/infig";
    assert (parseInfinity(s)); s.popFront;
    assert (parseInfinity(s)); s.popFront;
    assert (parseInfinity(s)); s.popFront;
    assert (parseInfinity(s)); s.popFront;
    assert (!parseInfinity(s)); s.popFront;
    assert (!parseInfinity(s)); s.popFront;
    assert (!parseInfinity(s));
}

//returns corresponding bracket and advances range if any of "([{<" is encountered, 0 otherwise
ElementType!R parseBracket(R)(ref R range)
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
    assert (parseBracket(s) == ')');
    assert (parseBracket(s) == ']');
    assert (parseBracket(s) == '}');
    assert (parseBracket(s) == '>');
    assert (parseBracket(s) == 0);
}

//returns a digit value and advances range if a digit is encountered, -1 otherwise, skips _
int parseDigit(R)(ref R range)
if (isInputRange!R && isSomeChar!(ElementType!R))
{
    while (expect(range, '_')) { }
    if (!range.empty && range.front >= '0' && range.front <= '9')
    {
        int result = range.front - '0';
        range.popFront();
        return result;
    }
    return -1;
}

unittest
{
    auto s = "0123a";
    assert (parseDigit(s) == 0);
    assert (parseDigit(s) == 1);
    assert (parseDigit(s) == 2);
    assert (parseDigit(s) == 3);
    assert (parseDigit(s) == -1);
}

//returns a digit value and advances range if a hex digit is encountered, -1 otherwise, skips _
int parseHexDigit(R)(ref R range)
if (isInputRange!R && isSomeChar!(ElementType!R))
{
    while (expect(range, '_')) { }
    if (!range.empty)
    {
        if (range.front >= '0' && range.front <= '9')
        {
            int result = range.front - '0';
            range.popFront();
            return result;
        }
        if (range.front >= 'A' && range.front <= 'F')
        {
            int result = range.front - 'A' + 10;
            range.popFront();
            return result;
        }
        if (range.front >= 'a' && range.front <= 'f')
        {
            int result = range.front - 'a' + 10;
            range.popFront();
            return result;
        }
    }
    return -1;
}

unittest
{
    auto s = "0123aBcg";
    assert (parseHexDigit(s) == 0);
    assert (parseHexDigit(s) == 1);
    assert (parseHexDigit(s) == 2);
    assert (parseHexDigit(s) == 3);
    assert (parseHexDigit(s) == 10);
    assert (parseHexDigit(s) == 11);
    assert (parseHexDigit(s) == 12);
    assert (parseHexDigit(s) == -1);

}

//returns how many zeros encountered and advances range, skips _
int parseZeroes(R)(ref R range)
if (isInputRange!R && isSomeChar!(ElementType!R))
{
    int count = 0;
    do
    {
        if (expect(range, '0'))
            ++count;
        else if (!expect(range, '_'))
            break;
    } while (true);
    return count;
}

unittest
{
    auto s = "0__00_000_";
    assert(parseZeroes(s) == 6);
}

//returns true if a hex number can be read in value, stops if doesn't fit in value
bool parseHexNumber(R, T)(ref R range, out T value)
if (isInputRange!R && isSomeChar!(ElementType!R))
{
    bool atLeastOneDigit = parseZeroes(range) != 0;
    enum maxWidth = T.sizeof * 2;
    int width = 0;
    while (width < maxWidth && !range.empty)
    {
        auto digit = parseHexDigit(range);
        if (!atLeastOneDigit)
            atLeastOneDigit = digit >= 0;
        if (digit >= 0)
        {
            value <<= 4;
            value |= cast(uint)digit;
            ++width;
        }
        else if (range.front == '_')
            range.popFront();
        else
            break;
    }
    return atLeastOneDigit;
}

unittest
{
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

//returns true if a decimal number can be read in value, stops if doesn't fit in value
@safe
bool parseNumber(R, T)(ref R range, ref T value)
if (isInputRange!R && isSomeChar!(ElementType!R))
{
    bool atLeastOneDigit = parseZeroes(range) != 0;
    bool overflow;
    while (!range.empty)
    {
        if (range.front >= '0' && range.front <= '9')
        {
            uint digit = range.front - '0';
            overflow = false;
            Unqual!T v = fma(value, 10U, digit, overflow);
            if (overflow)
                break;
            range.popFront();
            value = v;
            atLeastOneDigit = true;
        }
        else if (range.front == '_')
            range.popFront();
        else
            break;
    }
    return atLeastOneDigit;
}
