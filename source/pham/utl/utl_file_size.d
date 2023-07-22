
/*
 *
 * License: $(HTTP www.boost.org/LICENSE_1_0.txt, Boost License 1.0).
 * Authors: An Pham
 *
 * Copyright An Pham 2021 - xxxx.
 * Distributed under the Boost Software License, Version 1.0.
 * (See accompanying file LICENSE.txt or copy at http://www.boost.org/LICENSE_1_0.txt)
 *
 */

module pham.utl.file_size;

import std.algorithm.searching : countUntil;
import std.conv : ConvException, convTo = to;
import std.exception : enforce;
import std.format : format;
import std.range.primitives : ElementType;
import std.traits : isFloatingPoint, isIntegral, Unqual;

version (unittest) import pham.utl.test;
import pham.utl.numeric_parser : defaultParseDecimalOptions, isDigit, isNumericLexerRange, NumericLexer,
    NumericLexerFlag;
import pham.utl.result : cmp, sameSign;

@safe:

struct UnitSize
{
@safe nothrow:

    string symbol;
    long value;
}

struct FileSize
{
@safe:

public:
    static immutable string[] suffixes = ["Bytes", "KB", "MB", "GB", "TB", "PB"];

    static immutable UnitSize[] unitSizes = [
        {"Bytes", 1L},
        {"KB", 1L << 10},
        {"MB", 1L << 20},
        {"GB", 1L << 30},
        {"TB", 1L << 40},
        {"PB", 1L << 50},
        //{"EB", 1L << 60},
        //{"ZB", 1L << 70},
        //{"YB", 1L << 80},
        ];

    static ptrdiff_t suffixIndex(scope const(char)[] suffix) @nogc nothrow pure
    {
        auto result = suffixes.countUntil(suffix);
        if (result < 0 && (suffix == "BYTES" || suffix == "bytes"))
            return 0;
        return result;
    }

public:
    this(string units, T)(T value) @nogc nothrow pure
    if (suffixIndex(units) >= 0 && (isIntegral!T || isFloatingPoint!T))
    {
        enum unitIndex = suffixIndex(units);
        this._bytes = opSafe!"*"(value, unitSizes[unitIndex].value);
    }

    ref typeof(this) opOpAssign(string op, T)(T value) @nogc nothrow pure return
    if (op == "*" && (isIntegral!T || isFloatingPoint!T))
    {
        _bytes = opSafe!"*"(_bytes, value);
        return this;
    }

    ref typeof(this) opOpAssign(string op, T)(T value) @nogc pure return
    if (op == "/" && (isIntegral!T || isFloatingPoint!T))
    in
    {
        assert(value != 0);
    }
    do
    {
        _bytes = cast(long)(_bytes / value);
        return this;
    }

    FileSize opBinary(string op)(scope const(FileSize) rhs) const @nogc nothrow pure
    if (op == "+" || op == "-")
    {
        return FileSize(opSafe!op(_bytes, rhs._bytes));
    }

    FileSize opBinary(string op, T)(T value) const @nogc nothrow pure
    if (op == "*" && (isIntegral!T || isFloatingPoint!T))
    {
        return FileSize(opSafe!op(_bytes, value));
    }

    FileSize opBinary(string op, T)(T value) const pure
    if (op == "/" && (isIntegral!T || isFloatingPoint!T))
    in
    {
        assert(value != 0);
    }
    do
    {
        return FileSize(cast(long)(_bytes / value));
    }

    bool opCast(C: bool)() const @nogc nothrow pure
    {
        return _bytes != 0;
    }

    // Temporary hack until bug http://d.puremagic.com/issues/show_bug.cgi?id=5747 is fixed.
    FileSize opCast(T)() const @nogc nothrow pure
    if (is(Unqual!T == FileSize))
    {
        return this;
    }

    int opCmp(scope const(FileSize) rhs) const @nogc nothrow pure
    {
        return cmp(_bytes, rhs._bytes);
    }

    bool opEquals(scope const(FileSize) rhs) const @nogc nothrow pure
    {
        return opCmp(rhs) == 0;
    }

    FileSize opUnary(string op)() const @nogc nothrow pure
    if (op == "-")
    {
        return FileSize(-_bytes);
    }

    FileSize abs() const @nogc nothrow pure
    {
        return _bytes >= 0 ? FileSize(_bytes) : FileSize(-_bytes);
    }

    static FileSize from(string units)(long value) @nogc nothrow pure
    if (suffixIndex(units) >= 0)
    {
        enum unitIndex = suffixIndex(units);
        return FileSize(opSafe!"*"(value, unitSizes[unitIndex].value));
    }

    version (none) // not able to set alias Bytes = ... if implemented
    static FileSize from(string units)(double value) @nogc nothrow pure
    if (suffixIndex(units) >= 0)
    {
        enum unitIndex = suffixIndex(units);
        return FileSize(opSafe!"*"(value, unitSizes[unitIndex].value));
    }

    static FileSize parse(Range)(Range range) pure
    if (isNumericLexerRange!Range)
    {
        static immutable errorMessage = "Not a valid FileSize string";
        alias RangeElement = Unqual!(ElementType!Range);

        auto lexer = NumericLexer!(Range)(range, defaultParseDecimalOptions!RangeElement());
        enforce!ConvException(lexer.hasNumericChar, errorMessage);

        size_t nNumber = 0;
        RangeElement[30] number;
        while (!lexer.empty && nNumber < number.length)
        {
            const c = lexer.front;

            if (isDigit(c))
            {
                number[nNumber++] = c;
                lexer.popFront();
            }
            else if (lexer.allowDecimalChar && lexer.options.isDecimalChar(c))
            {
                number[nNumber++] = c;
                lexer.popDecimalChar();
            }
            else
                break;
        }

        lexer.skipSpaces();
        size_t nSuffix = 0;
        RangeElement[20] suffix;
        while (!lexer.empty && nSuffix < suffix.length)
        {
            const c = lexer.front;
            if (lexer.options.isSpaceChar(c))
                break;
            suffix[nSuffix++] = lexer.toUpper(c);
            lexer.popFront();
        }

        lexer.skipSpaces();
        enforce!ConvException(lexer.empty && nNumber > 0, errorMessage);

        long v;
        const n = convTo!double(number[0..nNumber]);
        if (nSuffix != 0)
        {
            const unitIndex = suffixIndex(convTo!string(suffix[0..nSuffix]));
            enforce!ConvException(unitIndex >= 0, errorMessage);
            v = cast(long)(n * unitSizes[unitIndex].value);
        }
        else
            v = cast(long)n;

        return FileSize(lexer.neg ? -v : v);
    }

    long to(string units)() const @nogc nothrow pure
    if (suffixIndex(units) >= 0)
    {
        enum unitIndex = suffixIndex(units);
        long result = _bytes;
        int numberCounter = unitIndex;
        while (numberCounter > 0)
        {
            result /= 1024;
            numberCounter--;
        }
        if (unitIndex > 0 && (_bytes % unitSizes[unitIndex].value) >= unitSizes[unitIndex - 1].value)
            result++;
        return result;
    }

    size_t toHash() const nothrow pure
    {
        return .hashOf(_bytes);
    }

    string toString(string units)() const nothrow pure
    if (suffixIndex(units) >= 0)
    {
        scope (failure) assert(0, "Assume nothrow failed");

        enum unitIndex = suffixIndex(units);
        const number = to!units();
        return format!"%d %s"(number, suffixes[unitIndex]);
    }

    @property long bytes() const @nogc nothrow pure
    {
        return _bytes;
    }

    alias length = bytes;

    static @property FileSize max() @nogc nothrow pure
    {
        return FileSize(long.max);
    }

    static @property FileSize min() @nogc nothrow pure
    {
        return FileSize(0);
    }

    static @property FileSize zero() @nogc nothrow pure
    {
        return FileSize(0);
    }

private:
    this(long bytes) @nogc nothrow pure
    {
        this._bytes = bytes;
    }

    static long opSafe(string op, RHS)(const(long) lhs, const(RHS) rhs) @nogc nothrow pure
    {
        import core.checkedint : adds, subs, muls;

        static if (isFloatingPoint!RHS)
            return cast(long)(mixin("lhs" ~ op ~ "rhs"));
        else
        {
            long result;
            bool overflow;

            static if (op == "+")
                result = adds(lhs, long(rhs), overflow);
            else static if (op == "-")
                result = subs(lhs, long(rhs), overflow);
            else static if (op == "*")
                result = muls(lhs, long(rhs), overflow);
            else
                static assert(0, op);

            if (!overflow)
                return result;

            static if (op == "*")
                return sameSign(lhs, rhs) ? long.max : long.min;
            else
                return sameSign(lhs, rhs) == 1 ? long.max : long.min;
        }
    }

private:
    long _bytes;
}

alias Bytes = FileSize.from!"Bytes";
alias KBytes = FileSize.from!"KB";
alias MBytes = FileSize.from!"MB";
alias GBytes = FileSize.from!"GB";
alias TBytes = FileSize.from!"TB";
alias PBytes = FileSize.from!"PB";


private:

@safe nothrow unittest // FileSize.opCmp
{
    import pham.utl.test;
    traceUnitTest("unittest pham.utl.filesize.FileSize.opCmp");

    assert(FileSize(12).opCmp(FileSize(12)) == 0);
    assert(FileSize(10).opCmp(FileSize(12)) < 0);
    assert(FileSize(12).opCmp(FileSize(10)) > 0);
    assert(FileSize.max.opCmp(FileSize.min) > 0);
}

@safe nothrow unittest // FileSize.opCast
{
    import pham.utl.test;
    traceUnitTest("unittest pham.utl.filesize.FileSize.opCast");

    auto bytes = 10.Bytes;
    assert(bytes);
    assert(!(bytes - bytes));
    assert(bytes + bytes);
}

@safe nothrow unittest // FileSize.opEquals
{
    import pham.utl.test;
    traceUnitTest("unittest pham.utl.filesize.FileSize.opEquals");

    assert(FileSize(0).opEquals(FileSize.zero));
    assert(FileSize(12).opEquals(FileSize(12)));
    assert(!FileSize(10).opEquals(FileSize(12)));
    assert(!FileSize(12).opEquals(FileSize(10)));
}

@safe nothrow unittest // FileSize.opOpAssign
{
    import pham.utl.test;
    traceUnitTest("unittest pham.utl.filesize.FileSize.opOpAssign");

    assert((FileSize(5) *= 7) == FileSize(35));
    assert((FileSize(7) *= 5) == FileSize(35));

    const c = FileSize(12);
    static assert(!__traits(compiles, c *= 12));

    immutable i = FileSize(12);
    static assert(!__traits(compiles, i *= 12));
}

@safe nothrow unittest // FileSize.opOpAssign
{
    import pham.utl.test;
    traceUnitTest("unittest pham.utl.filesize.FileSize.opOpAssign");

    assert((FileSize(5) /= 7) == FileSize(0));
    assert((FileSize(7) /= 5) == FileSize(1));

    const c = FileSize(12);
    static assert(!__traits(compiles, c /= 12));

    immutable i = FileSize(12);
    static assert(!__traits(compiles, i /= 12));
}

@safe nothrow unittest // FileSize.opBinary
{
    import pham.utl.test;
    traceUnitTest("unittest pham.utl.filesize.FileSize.opBinary");

    assert(FileSize(5) + FileSize(7) == FileSize(12));
    assert(FileSize(7) + FileSize(5) == FileSize(12));
}

@safe nothrow unittest // FileSize.opBinary
{
    import pham.utl.test;
    traceUnitTest("unittest pham.utl.filesize.FileSize.opBinary");

    assert(FileSize(5) - FileSize(7) == FileSize(-2));
    assert(FileSize(7) - FileSize(5) == FileSize(2));
}

@safe nothrow unittest // FileSize.opBinary
{
    import pham.utl.test;
    traceUnitTest("unittest pham.utl.filesize.FileSize.opBinary");

    assert(FileSize(5) * 7 == FileSize(35));
    assert(FileSize(7) * 5 == FileSize(35));
}

@safe nothrow unittest // FileSize.opBinary
{
    import pham.utl.test;
    traceUnitTest("unittest pham.utl.filesize.FileSize.opBinary");

    assert(FileSize(5) / 7 == FileSize(0));
    assert(FileSize(7) / 5 == FileSize(1));
    assert(FileSize(8) / 4 == FileSize(2));
}

@safe nothrow unittest // FileSize.opUnary
{
    import pham.utl.test;
    traceUnitTest("unittest pham.utl.filesize.FileSize.opUnary");

    assert(-FileSize(7) == FileSize(-7));
    assert(-FileSize(-7) == FileSize(7));
    assert(-FileSize(0) == FileSize(0));
}

@safe nothrow unittest // FileSize.abs
{
    import pham.utl.test;
    traceUnitTest("unittest pham.utl.filesize.FileSize.abs");

    assert(FileSize(17).abs() == FileSize(17));
    assert(FileSize(-17).abs() == FileSize(17));
}

@safe nothrow unittest // FileSize.from
{
    import pham.utl.test;
    traceUnitTest("unittest pham.utl.filesize.FileSize.from");

    assert(FileSize.from!"Bytes"(1).bytes == 1);
    assert(1.Bytes == FileSize(1));

    assert(FileSize.from!"KB"(1).bytes == 1024);
    assert(1.KBytes.bytes == 1024);
    assert(FileSize.from!"KB"(1).to!"KB"() == 1);

    assert(FileSize.from!"MB"(1).bytes == 1024L * 1024);
    assert(1.MBytes.bytes == 1024L * 1024);
    assert(FileSize.from!"MB"(1).to!"MB"() == 1);

    assert(FileSize.from!"GB"(1).bytes == 1024L * 1024 * 1024);
    assert(1.GBytes.bytes == 1024L * 1024 * 1024);
    assert(FileSize.from!"GB"(1).to!"GB"() == 1);

    assert(FileSize.from!"TB"(1).bytes == 1024L * 1024 * 1024 * 1024);
    assert(1.TBytes.bytes == 1024L * 1024 * 1024 * 1024);
    assert(FileSize.from!"TB"(1).to!"TB"() == 1);

    assert(FileSize.from!"PB"(1).bytes == 1024L * 1024 * 1024 * 1024 * 1024);
    assert(1.PBytes.bytes == 1024L * 1024 * 1024 * 1024 * 1024);
    assert(FileSize.from!"PB"(1).to!"PB"() == 1);
}

@safe unittest // FileSize.parse
{
    import std.exception : assertThrown;
    import pham.utl.test;
    traceUnitTest("unittest pham.utl.filesize.FileSize.parse");

    auto f0 = FileSize.parse("0"d);
    assert(f0 == FileSize(0));

    auto f1 = FileSize.parse("101"d);
    assert(f1 == FileSize(101), f1.toString!"Bytes"());

    auto f2 = FileSize.parse("1_000"c);
    assert(f2 == FileSize(1_000), f1.toString!"Bytes"());

    auto f3 = FileSize.parse("  1_000  Bytes "c);
    assert(f3 == FileSize(1_000));

    auto f4 = FileSize.parse("  2 KB");
    assert(f4 == FileSize(1024L * 2));

    auto f5 = FileSize.parse("2 MB ");
    assert(f5 == FileSize(1024L * 1024 * 2));

    auto f6 = FileSize.parse("2 gb");
    assert(f6 == FileSize(1024L * 1024 * 1024 * 2));

    auto f7 = FileSize.parse("2 Tb");
    assert(f7 == FileSize(1024L * 1024 * 1024 * 1024 * 2));

    auto f8 = FileSize.parse("2 PB");
    assert(f8 == FileSize(1024L * 1024 * 1024 * 1024 * 1024 * 2));

    auto f9 = FileSize.parse("1 PB");
    assert(f9 == FileSize(1024L * 1024 * 1024 * 1024 * 1024));

    auto f10 = FileSize.parse("234.7645 PB");
    assert(f10 == FileSize(264_321_328_679_955_200L));

    // Not acceptable cases
    assertThrown!ConvException(FileSize.parse("0x"d));
    assertThrown!ConvException(FileSize.parse("1 unknown"));
    assertThrown!ConvException(FileSize.parse("Bytes"));
    assertThrown!ConvException(FileSize.parse("-PB"));
}

@safe nothrow unittest // FileSize.to
{
    import pham.utl.test;
    traceUnitTest("unittest pham.utl.filesize.FileSize.to");

    assert(FileSize(0).to!"Bytes"() == 0);
    assert(FileSize(0).to!"KB"() == 0);
    assert(FileSize(0).to!"MB"() == 0);
    assert(FileSize(0).to!"GB"() == 0);
    assert(FileSize(0).to!"TB"() == 0);
    assert(FileSize(0).to!"PB"() == 0);

    assert(FileSize(1).to!"Bytes"() == 1);
    assert(FileSize(1).to!"KB"() == 1);
    assert(FileSize(1).to!"MB"() == 0);
    assert(FileSize(1).to!"GB"() == 0);
    assert(FileSize(1).to!"TB"() == 0);
    assert(FileSize(1).to!"PB"() == 0);

    assert(FileSize(1023).to!"KB"() == 1);
    assert(FileSize(1023).to!"MB"() == 0);
    assert(FileSize(1023).to!"GB"() == 0);
    assert(FileSize(1023).to!"TB"() == 0);
    assert(FileSize(1023).to!"PB"() == 0);

    assert(FileSize(1024).to!"KB"() == 1);
    assert(FileSize(1024).to!"MB"() == 1);
    assert(FileSize(1024).to!"GB"() == 0);
    assert(FileSize(1024).to!"TB"() == 0);
    assert(FileSize(1024).to!"PB"() == 0);

    assert(FileSize(1025).to!"KB"() == 2);
    assert(FileSize(1025).to!"MB"() == 1);
    assert(FileSize(1025).to!"GB"() == 0);
    assert(FileSize(1025).to!"TB"() == 0);
    assert(FileSize(1025).to!"PB"() == 0);
}

@safe nothrow unittest // FileSize.toString
{
    import pham.utl.test;
    traceUnitTest("unittest pham.utl.filesize.FileSize.toString");

    assert(FileSize(0).toString!"Bytes"() == "0 Bytes");
    assert(FileSize(0).toString!"KB"() == "0 KB");
    assert(FileSize(0).toString!"MB"() == "0 MB");
    assert(FileSize(0).toString!"GB"() == "0 GB");
    assert(FileSize(0).toString!"TB"() == "0 TB");
    assert(FileSize(0).toString!"PB"() == "0 PB");

    assert(FileSize(1).toString!"Bytes"() == "1 Bytes");
    assert(FileSize(1).toString!"KB"() == "1 KB");
    assert(FileSize(1).toString!"MB"() == "0 MB");
    assert(FileSize(1).toString!"GB"() == "0 GB");
    assert(FileSize(1).toString!"TB"() == "0 TB");
    assert(FileSize(1).toString!"PB"() == "0 PB");

    assert(FileSize(1023).toString!"KB"() == "1 KB");
    assert(FileSize(1023).toString!"MB"() == "0 MB");
    assert(FileSize(1023).toString!"GB"() == "0 GB");
    assert(FileSize(1023).toString!"TB"() == "0 TB");
    assert(FileSize(1023).toString!"PB"() == "0 PB");

    assert(FileSize(1024).toString!"KB"() == "1 KB");
    assert(FileSize(1024).toString!"MB"() == "1 MB");
    assert(FileSize(1024).toString!"GB"() == "0 GB");
    assert(FileSize(1024).toString!"TB"() == "0 TB");
    assert(FileSize(1024).toString!"PB"() == "0 PB");

    assert(FileSize(1025).toString!"KB"() == "2 KB");
    assert(FileSize(1025).toString!"MB"() == "1 MB");
    assert(FileSize(1025).toString!"GB"() == "0 GB");
    assert(FileSize(1025).toString!"TB"() == "0 TB");
    assert(FileSize(1025).toString!"PB"() == "0 PB");
}

@safe nothrow unittest // FileSize overflow
{
    import pham.utl.test;
    traceUnitTest("unittest pham.utl.filesize.FileSize.overflow");

    const lh = (long.max / 2) + 1;

    assert(FileSize.from!"KB"(lh).bytes == long.max);
    assert(FileSize.from!"MB"(lh).bytes == long.max);
    assert(FileSize.from!"GB"(lh).bytes == long.max);
    assert(FileSize.from!"TB"(lh).bytes == long.max);
    assert(FileSize.from!"PB"(lh).bytes == long.max);

    assert((FileSize.from!"Bytes"(lh) * lh).bytes == long.max);
    assert((FileSize.from!"Bytes"(lh) + FileSize.from!"Bytes"(lh)).bytes == long.max);
}
