
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

module pham.utl.utl_file_size;

import std.conv : ConvException;
import std.format : format;
import std.traits : Unqual, isFloatingPoint, isIntegral;
import std.uni : sicmp;

debug(debug_pham_utl_utl_file_size) import std.stdio : writeln;

import pham.utl.utl_numeric_parser : ComputingSizeUnit, computingSizeUnitNames, computingSizeUnit1K, 
    computingSizeUnitValues, computingSizeUnitMaxs, isNumericLexerRange, parseDecimalSuffix;
public import pham.utl.utl_numeric_parser : NumericParsedKind;
import pham.utl.utl_result : cmp, sameSign;

@safe:

alias FileSizeUnit = ComputingSizeUnit;
alias fileSizeUnitNames = computingSizeUnitNames;
alias fileSizeUnit1K = computingSizeUnit1K;
alias fileSizeUnitValues = computingSizeUnitValues;
alias fileSizeUnitMaxs = computingSizeUnitMaxs;

struct FileSize
{
@safe:

public:
    this(string units, T)(T value) @nogc nothrow pure
    if (suffixIndex(units) >= 0 && (isIntegral!T || isFloatingPoint!T))
    {
        enum unitIndex = suffixIndex(units);
        this._bytes = opSafe!"*"(value, fileSizeUnitValues[unitIndex]);
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
        return FileSize(opSafe!"*"(value, fileSizeUnitValues[unitIndex]));
    }

    version(none) // not able to set alias Bytes = ... if implemented
    static FileSize from(string units)(double value) @nogc nothrow pure
    if (suffixIndex(units) >= 0)
    {
        enum unitIndex = suffixIndex(units);
        return FileSize(opSafe!"*"(value, fileSizeUnitValues[unitIndex]));
    }

    static FileSize parse(Range)(Range range) pure
    if (isNumericLexerRange!Range)
    {
        FileSize result;
        final switch (tryParse(range, result)) with (NumericParsedKind)
        {
            case ok: return result;
            case invalid: throw new ConvException("Invalid FileSize string");
            case overflow: throw new ConvException("Overflow FileSize string");
            case underflow: throw new ConvException("Underflow FileSize string");
        }
    }

    static NumericParsedKind tryParse(Range)(Range range, out FileSize fileSize) nothrow pure
    if (isNumericLexerRange!Range)
    {
        double n;
        int unitIndex;
        const result = parseDecimalSuffix(range, fileSizeUnitNames[], n, unitIndex);
        if (result == NumericParsedKind.ok)
        {
            if (n < 0)
            {
                fileSize = FileSize.min;
                return NumericParsedKind.underflow;
            }

            if (unitIndex < 0)
            {
                if (n > fileSizeUnitMaxs[FileSizeUnit.bytes])
                {
                    fileSize = FileSize.max;
                    return NumericParsedKind.overflow;
                }

                fileSize = FileSize(cast(long)n);
            }
            else
            {
                if (n > fileSizeUnitMaxs[unitIndex])
                {
                    fileSize = FileSize.max;
                    return NumericParsedKind.overflow;
                }
                fileSize = FileSize(opSafe!"*"(fileSizeUnitValues[unitIndex], n));
            }
        }
        else
            fileSize = FileSize.zero;
        return result;
    }

    static int suffixIndex(string units) @nogc nothrow pure
    {
        foreach (i, s; fileSizeUnitNames)
        {
            if (sicmp(s, units) == 0)
                return cast(int)i;
        }
        return -1;
    }

    long to(string units)() const @nogc nothrow pure
    if (suffixIndex(units) >= 0)
    {
        if (_bytes == 0)
            return 0L;

        enum unitIndex = suffixIndex(units);
        enum unitValue = fileSizeUnitValues[unitIndex];
        const long result = _bytes / unitValue;

        debug(debug_pham_utl_utl_file_size) debug writeln("_bytes=", _bytes, ", result=", result, ", dif=", _bytes - result*unitValue, ", u=", fileSizeUnitValues[unitIndex]);

        return unitIndex > 0 && (_bytes - result*unitValue) > fileSizeUnitValues[unitIndex - 1] ? result + 1 : result;
    }

    size_t toHash() const nothrow pure
    {
        return .hashOf(_bytes);
    }

    string toString(string units = "KB")() const nothrow pure
    if (suffixIndex(units) >= 0)
    {
        scope (failure) assert(0, "Assume nothrow failed");

        enum unitIndex = suffixIndex(units);
        const unitNumber = to!units();
        return format!"%d %s"(unitNumber, fileSizeUnitNames[unitIndex]);
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
    this(const(long) bytes) @nogc nothrow pure
    {
        this._bytes = bytes;
    }

    static long opSafe(string op, RHS)(const(long) lhs, const(RHS) rhs) @nogc nothrow pure
    {
        import core.checkedint : adds, subs, muls;

        static if (isFloatingPoint!RHS)
        {
            const d = mixin("cast(double)lhs" ~ op ~ "cast(double)rhs");
            return d >= long.max ? long.max : cast(long)d;
        }
        else
        {
            long result;
            bool overflow;

            static if (op == "+")
                result = adds(lhs, cast(long)rhs, overflow);
            else static if (op == "-")
                result = subs(lhs, cast(long)rhs, overflow);
            else static if (op == "*")
                result = muls(lhs, cast(long)rhs, overflow);
            else
                static assert(0, op);

            if (!overflow)
                return result;

            static if (op == "*")
                return sameSign(lhs, rhs) ? long.max : 0L;
            else
                return sameSign(lhs, rhs) == 1 ? long.max : 0L;
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
    assert(FileSize(12).opCmp(FileSize(12)) == 0);
    assert(FileSize(10).opCmp(FileSize(12)) < 0);
    assert(FileSize(12).opCmp(FileSize(10)) > 0);
    assert(FileSize.max.opCmp(FileSize.min) > 0);
}

@safe nothrow unittest // FileSize.opCast
{
    auto bytes = 10.Bytes;
    assert(bytes);
    assert(!(bytes - bytes));
    assert(bytes + bytes);
}

@safe nothrow unittest // FileSize.opEquals
{
    assert(FileSize(0).opEquals(FileSize.zero));
    assert(FileSize(12).opEquals(FileSize(12)));
    assert(!FileSize(10).opEquals(FileSize(12)));
    assert(!FileSize(12).opEquals(FileSize(10)));
}

@safe nothrow unittest // FileSize.opOpAssign
{
    assert((FileSize(5) *= 7) == FileSize(35));
    assert((FileSize(7) *= 5) == FileSize(35));

    const c = FileSize(12);
    static assert(!__traits(compiles, c *= 12));

    immutable i = FileSize(12);
    static assert(!__traits(compiles, i *= 12));
}

@safe nothrow unittest // FileSize.opOpAssign
{
    assert((FileSize(5) /= 7) == FileSize(0));
    assert((FileSize(7) /= 5) == FileSize(1));

    const c = FileSize(12);
    static assert(!__traits(compiles, c /= 12));

    immutable i = FileSize(12);
    static assert(!__traits(compiles, i /= 12));
}

@safe nothrow unittest // FileSize.opBinary
{
    assert(FileSize(5) + FileSize(7) == FileSize(12));
    assert(FileSize(7) + FileSize(5) == FileSize(12));
}

@safe nothrow unittest // FileSize.opBinary
{
    assert(FileSize(5) - FileSize(7) == FileSize(-2));
    assert(FileSize(7) - FileSize(5) == FileSize(2));
}

@safe nothrow unittest // FileSize.opBinary
{
    assert(FileSize(5) * 7 == FileSize(35));
    assert(FileSize(7) * 5 == FileSize(35));
}

@safe nothrow unittest // FileSize.opBinary
{
    assert(FileSize(5) / 7 == FileSize(0));
    assert(FileSize(7) / 5 == FileSize(1));
    assert(FileSize(8) / 4 == FileSize(2));
}

@safe nothrow unittest // FileSize.opUnary
{
    assert(-FileSize(7) == FileSize(-7));
    assert(-FileSize(-7) == FileSize(7));
    assert(-FileSize(0) == FileSize(0));
}

@safe nothrow unittest // FileSize.abs
{
    assert(FileSize(17).abs() == FileSize(17));
    assert(FileSize(-17).abs() == FileSize(17));
}

@safe nothrow unittest // FileSize.from
{
    import std.conv : to;

    assert(FileSize.from!"Bytes"(1).bytes == 1);
    assert(1.Bytes == FileSize(1));

    assert(FileSize.from!"KB"(1).bytes == fileSizeUnitValues[FileSizeUnit.kbytes]);
    assert(1.KBytes.bytes == fileSizeUnitValues[FileSizeUnit.kbytes]);
    assert(FileSize.from!"KB"(1).to!"KB"() == 1, FileSize.from!"KB"(1).to!"KB"().to!string);

    assert(FileSize.from!"MB"(1).bytes == fileSizeUnitValues[FileSizeUnit.mbytes]);
    assert(1.MBytes.bytes == fileSizeUnitValues[FileSizeUnit.mbytes]);
    assert(FileSize.from!"MB"(1).to!"MB"() == 1, FileSize.from!"MB"(1).to!"MB"().to!string);

    assert(FileSize.from!"GB"(1).bytes == fileSizeUnitValues[FileSizeUnit.gbytes]);
    assert(1.GBytes.bytes == fileSizeUnitValues[FileSizeUnit.gbytes]);
    assert(FileSize.from!"GB"(1).to!"GB"() == 1);

    assert(FileSize.from!"TB"(1).bytes == fileSizeUnitValues[FileSizeUnit.tbytes]);
    assert(1.TBytes.bytes == fileSizeUnitValues[FileSizeUnit.tbytes]);
    assert(FileSize.from!"TB"(1).to!"TB"() == 1);

    assert(FileSize.from!"PB"(1).bytes == fileSizeUnitValues[FileSizeUnit.pbytes]);
    assert(1.PBytes.bytes == fileSizeUnitValues[FileSizeUnit.pbytes]);
    assert(FileSize.from!"PB"(1).to!"PB"() == 1);
}

@safe unittest // FileSize.parse
{
    import std.exception : assertThrown;

    auto f0 = FileSize.parse("0"d);
    assert(f0 == FileSize(0));

    auto f1 = FileSize.parse("101"d);
    assert(f1 == FileSize(101), f1.toString!"Bytes"());

    auto f2 = FileSize.parse("1_000"c);
    assert(f2 == FileSize(1_000), f1.toString!"Bytes"());

    auto f3 = FileSize.parse("  1_000  Bytes "c);
    assert(f3 == FileSize(1_000));

    auto f4 = FileSize.parse("  2 KB");
    assert(f4 == FileSize(fileSizeUnitValues[FileSizeUnit.kbytes] * 2));

    auto f5 = FileSize.parse("2 MB ");
    assert(f5 == FileSize(fileSizeUnitValues[FileSizeUnit.mbytes] * 2));

    auto f6 = FileSize.parse("2 gb");
    assert(f6 == FileSize(fileSizeUnitValues[FileSizeUnit.gbytes] * 2));

    auto f7 = FileSize.parse("2 Tb");
    assert(f7 == FileSize(fileSizeUnitValues[FileSizeUnit.tbytes] * 2));

    auto f8 = FileSize.parse("2 PB");
    assert(f8 == FileSize(fileSizeUnitValues[FileSizeUnit.pbytes] * 2));

    auto f10 = FileSize.parse("234.762 PB");
    assert(f10 == FileSize(264_318_513_930_188_096L), f10.toString!"Bytes"());

    // Not acceptable cases
    assertThrown!ConvException(FileSize.parse("0x"d));
    assertThrown!ConvException(FileSize.parse("1 unknown"));
    assertThrown!ConvException(FileSize.parse("Bytes"));
    assertThrown!ConvException(FileSize.parse("-PB"));
}

@safe nothrow unittest // FileSize.to
{
    assert(FileSize(0).to!"Bytes"() == 0);
    assert(FileSize(0).to!"KB"() == 0);
    assert(FileSize(0).to!"MB"() == 0);
    assert(FileSize(0).to!"GB"() == 0);
    assert(FileSize(0).to!"TB"() == 0);
    assert(FileSize(0).to!"PB"() == 0);

    assert(FileSize(1).to!"Bytes"() == 1);
    assert(FileSize(1).to!"KB"() == 0);
    assert(FileSize(1).to!"MB"() == 0);
    assert(FileSize(1).to!"GB"() == 0);
    assert(FileSize(1).to!"TB"() == 0);
    assert(FileSize(1).to!"PB"() == 0);

    assert(FileSize(1000).to!"KB"() == 1);
    assert(FileSize(1025).to!"MB"() == 1);
    assert(FileSize(1001).to!"GB"() == 0);
    assert(FileSize(1001).to!"TB"() == 0);
    assert(FileSize(1001).to!"PB"() == 0);
}

@safe nothrow unittest // FileSize.toString
{
    assert(FileSize(0).toString!"Bytes"() == "0 Bytes");
    assert(FileSize(0).toString!"KB"() == "0 KB");
    assert(FileSize(0).toString!"MB"() == "0 MB");
    assert(FileSize(0).toString!"GB"() == "0 GB");
    assert(FileSize(0).toString!"TB"() == "0 TB");
    assert(FileSize(0).toString!"PB"() == "0 PB");

    assert(FileSize(1).toString!"Bytes"() == "1 Bytes");
    assert(FileSize(1).toString!"KB"() == "0 KB");
    assert(FileSize(1).toString!"MB"() == "0 MB");
    assert(FileSize(1).toString!"GB"() == "0 GB");
    assert(FileSize(1).toString!"TB"() == "0 TB");
    assert(FileSize(1).toString!"PB"() == "0 PB");

    assert(FileSize(1000).toString!"KB"() == "1 KB");
    assert(FileSize(1000).toString!"MB"() == "0 MB");
    assert(FileSize(1000).toString!"GB"() == "0 GB");
    assert(FileSize(1000).toString!"TB"() == "0 TB");
    assert(FileSize(1000).toString!"PB"() == "0 PB");

    assert(FileSize(1000).toString!"KB"() == "1 KB");
    assert(FileSize(1_000_000).toString!"MB"() == "1 MB");
    assert(FileSize(1_000_000).toString!"GB"() == "0 GB");
    assert(FileSize(1_000_000).toString!"TB"() == "0 TB");
    assert(FileSize(1_000_000).toString!"PB"() == "0 PB");

    assert(FileSize(fileSizeUnit1K + 2).toString!"KB"() == "2 KB");
    assert(FileSize(1_001_500).toString!"MB"() == "1 MB");
    assert(FileSize(1_001_500).toString!"GB"() == "0 GB");
    assert(FileSize(1_001_500).toString!"TB"() == "0 TB");
    assert(FileSize(1_001_500).toString!"PB"() == "0 PB");
}

@safe nothrow unittest // FileSize overflow
{
    const lh = (long.max / 2) + 1;

    assert(FileSize.from!"KB"(lh).bytes == long.max);
    assert(FileSize.from!"MB"(lh).bytes == long.max);
    assert(FileSize.from!"GB"(lh).bytes == long.max);
    assert(FileSize.from!"TB"(lh).bytes == long.max);
    assert(FileSize.from!"PB"(lh).bytes == long.max);

    assert((FileSize.from!"Bytes"(lh) * lh).bytes == long.max);
    assert((FileSize.from!"Bytes"(lh) + FileSize.from!"Bytes"(lh)).bytes == long.max);
}
