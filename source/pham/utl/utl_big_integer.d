/*
 *
 * License: $(HTTP www.boost.org/LICENSE_1_0.txt, Boost License 1.0).
 * Authors: An Pham
 *
 * Copyright An Pham 2019 - xxxx.
 * Distributed under the Boost Software License, Version 1.0.
 * (See accompanying file LICENSE.txt or copy at http://www.boost.org/LICENSE_1_0.txt)
 *
 * A clone from https://github.com/dotnet/runtime/blob/main/src/libraries/System.Runtime.Numerics/src/System/Numerics
 */

module pham.utl.utl_big_integer;

public import std.ascii : LetterCase;
import std.ascii : lowerHexDigits, upperHexDigits=hexDigits, decimalDigits=digits;
import std.conv : ConvException;
import std.format : FormatException, FormatSpec, formatValue;
import std.range.primitives : ElementType, isInputRange, isOutputRange, put;
import std.string : indexOf;
import std.traits : isFloatingPoint, isIntegral, isSigned, isSomeChar, isUnsigned, Unqual;
import std.typecons : Flag;
public import std.typecons : No, Yes;

version(profile) import pham.utl.utl_test : PerfFunction;
import pham.utl.utl_array : ShortStringBuffer;
import pham.utl.utl_bit : bitLength, trailingZeroBits;
import pham.utl.utl_disposable : DisposingReason;
public import pham.utl.utl_numeric_parser : NumericLexerFlag, NumericLexerOptions;
import pham.utl.utl_numeric_parser : cvtDigit, cvtHexDigit2, isHexDigit, isNumericLexerRange, NumericLexer, NumericStringRange;
import pham.utl.utl_object : bytesToHexs, simpleIntegerFmt;
import pham.utl.utl_big_integer_calculator;
public import pham.utl.utl_big_integer_calculator : UByteTempArray, UIntTempArray;
import pham.utl.utl_big_integer_helper;

@safe:

pragma(inline, true)
Flag!"bigEndian" toBigEndianFlag(bool value) @nogc nothrow pure
{
    return value ? Yes.bigEndian : No.bigEndian;
}

pragma(inline, true)
Flag!"negative" toNegativeFlag(bool value) @nogc nothrow pure
{
    return value ? Yes.negative : No.negative;
}

pragma(inline, true)
Flag!"unsigned" toUnsignedFlag(bool value) @nogc nothrow pure
{
    return value ? Yes.unsigned : No.unsigned;
}

NumericLexerOptions!(const(Char)) defaultParseBigIntegerOptions(Char)() nothrow pure @safe
{
    NumericLexerOptions!(const(Char)) result;
    result.flags |= NumericLexerFlag.allowHexDigit;
    return result;
}

struct BigInteger
{
@safe:

public:
    version(none)
    this(this) nothrow pure
    {
        _bits = _bits.dup;
    }

    this(T)(auto ref T value) nothrow pure
    if (is(Unqual!T == BigInteger))
    {
        setSignInts(value._bits, value._sign);
    }

    /*
     * Creates a BigInteger from an integer type value
     */
    this(T)(T value) nothrow pure
    if (isIntegral!T)
    {
        static if (T.sizeof < int.sizeof)
        {
            static if (isSigned!T)
                setInt(cast(int)value);
            else
                setInt(cast(uint)value);
        }
        else
            setInt(value);
    }

    /*
     * Creates a BigInteger from a float type value
     */
    this(T)(T value) nothrow pure
    if (isFloatingPoint!T)
    {
        setFloat(value);
    }

    /**
     * Creates a BigInteger from a little-endian twos-complement ubyte array
     * Params:
     *  value = Contains BigInteger bits
     *  unsigned = The bool flag indicating the value bits is an unsigned value regardless of sign bit
     *  bigEndian = The bool flag indicating the value bits is in big endian format
     */
    this(scope const(ubyte)[] value,
        const(Flag!"unsigned") unsigned = No.unsigned,
        const(Flag!"bigEndian") bigEndian = No.bigEndian) nothrow pure
    {
        setBytes(value, unsigned, bigEndian);
    }

    this(scope const(uint)[] bits, int sign) nothrow pure
    in
    {
        assert(isValid(bits, sign) == 0);
    }
    do
    {
        setSignInts(bits, sign);
    }

    /*
     * Constructor used during bit manipulation and arithmetic.
     * When possible the uint[] will be packed into  _sign to conserve space.
     * Params:
     *  value = The absolute value of the number
     *  negative = The bool flag indicating the sign of the value
     */
    this(scope const(uint)[] value, const(Flag!"negative") negative) nothrow pure
    {
        setNegInts(value, negative);
    }

    /**
     * Create a BigInteger from a little-endian twos-complement UInt32 array.
     * When possible, value is assigned directly to this._bits without an array copy
     * so use this ctor with care.
     */
    private this(scope const(uint)[] value) nothrow pure
    {
        setInts(value);
    }

    this(scope const(char)[] hexOrDecimals, NumericLexerOptions!(const(char)) parseOptions = defaultParseBigIntegerOptions!char()) pure
    {
        auto range = NumericStringRange!(const(char)[])(hexOrDecimals);
        this(range, parseOptions);
    }

    this(Range, Char)(scope ref Range hexOrDecimals, NumericLexerOptions!Char parseOptions) pure
    if (isNumericLexerRange!Range && isSomeChar!Char && Char.sizeof == ElementType!Range.sizeof)
    {
        auto lexer = NumericLexer!Range(hexOrDecimals, parseOptions);

        void throwError()
        {
            import std.conv;

            throw new ConvException("Not a valid numerical string at " ~ lexer.count.to!string());
        }

        if (!lexer.hasNumericChar)
            throwError();

        if (lexer.isHex)
        {
            CharTempArray hexDigits;
            while (!lexer.empty)
            {
                auto f = lexer.front;
                if (isHexDigit(f))
                {
                    hexDigits.put(f);

                    lexer.popFront();
                }
                else if (lexer.conditionSkipSpaces())
                {
                    if (lexer.isInvalidAfterContinueSkippingSpaces())
                        throwError();
                }
                else
                    throwError();
            }

            const resultLength = (hexDigits.length / 2) + (hexDigits.length % 2);
            auto resultBits = UByteTempArray(resultLength);
            size_t bitIndex = 0;
            bool shift = false;

            // Parse the string into a little-endian two's complement byte array
            // string value     : O F E B 7 \0
            // string index (i) : 0 1 2 3 4 5 <--
            // byte[] (bitIndex): 2 1 1 0 0 <--
            for (auto i = hexDigits.length - 1; i > 0; i--)
            {
                if (shift)
                {
                    resultBits[bitIndex] = cast(ubyte)(resultBits[bitIndex] | (cvtHexDigit2(hexDigits[i]) << 4));
                    bitIndex++;
                }
                else
                {
                    resultBits[bitIndex] = cvtHexDigit2(hexDigits[i]);
                }
                shift = !shift;
            }

            const b = cvtHexDigit2(hexDigits[0]);
            const isNegative = (parseOptions.flags & NumericLexerFlag.unsigned) == 0 && (b & 0x08) == 0x08;
            if (shift)
                resultBits[bitIndex] = cast(ubyte)(resultBits[bitIndex] | (b << 4));
            else
                resultBits[bitIndex] = isNegative ? cast(ubyte)(b | 0xF0) : b;

            setBytes(resultBits[], isNegative ? No.unsigned : Yes.unsigned);
        }
        else
        {
            setZero();
            const ten = BigInteger(10);
            ubyte b;
            while (!lexer.empty)
            {
                const f = lexer.front;
                if (cvtDigit(f, b))
                {
                    this.opOpAssign!"*"(ten);
                    this.opOpAssign!"+"(BigInteger(b));

                    lexer.popFront();
                }
                else if (lexer.conditionSkipSpaces())
                {
                    if (lexer.isInvalidAfterContinueSkippingSpaces())
                        throwError();
                }
                else
                    throwError();
            }
        }

        if (lexer.neg)
            this.opUnary!"-"();
    }

    ref BigInteger opAssign(T)(auto scope ref T x) nothrow pure scope return
    if (is(Unqual!T == BigInteger))
    {
        setSignInts(x._bits, x._sign);
        return this;
    }

    ref BigInteger opAssign(T)(T x) nothrow pure return
    if (isIntegral!T)
    {
        setInt(x);
        return this;
    }

    ref BigInteger opAssign(T)(T x) nothrow pure return
    if (isFloatingPoint!T)
    {
        setFloat(x);
        return this;
    }

    ref BigInteger opOpAssign(string op, T)(const(T) rhs) nothrow pure return
    if ((op == "+" || op == "-" || op == "*" || op == "/" || op == "%") && is(T: BigInteger))
    in
    {
        assert(rhs.isValid() == 0);
    }
    do
    {
        static if (op == "+")
        {
            assert(isValid() == 0);

            if ((_sign < 0) != (rhs._sign < 0))
                return subtractOpAssign(rhs._bits, -1 * rhs._sign);
            else
                return addOpAssign(rhs._bits, rhs._sign);
        }
        else static if (op == "-")
        {
            assert(isValid() == 0);

            if ((_sign < 0) != (rhs._sign < 0))
                return addOpAssign(rhs._bits, -1 * rhs._sign);
            else
                return subtractOpAssign(rhs._bits, rhs._sign);
        }
        else static if (op == "*")
        {
            assert(isValid() == 0);

            const trivialLeft = _bits.length == 0;
            const trivialRight = rhs._bits.length == 0;

            if (trivialLeft && trivialRight)
                setInt(cast(long)_sign * rhs._sign);
            else if (trivialLeft)
            {
                auto resultBits = BigIntegerCalculator.multiply(rhs._bits, BigIntegerHelper.abs(_sign));
                setNegInts(resultBits[], toNegativeFlag((_sign < 0) ^ (rhs._sign < 0)));
            }
            else if (trivialRight)
            {
                auto resultBits = BigIntegerCalculator.multiply(_bits, BigIntegerHelper.abs(rhs._sign));
                setNegInts(resultBits[], toNegativeFlag((_sign < 0) ^ (rhs._sign < 0)));
            }
            else if (_bits == rhs._bits)
            {
                auto resultBits = BigIntegerCalculator.square(_bits);
                setNegInts(resultBits[], toNegativeFlag((_sign < 0) ^ (rhs._sign < 0)));
            }
            else if (_bits.length < rhs._bits.length)
            {
                auto resultBits = BigIntegerCalculator.multiply(rhs._bits, _bits);
                setNegInts(resultBits[], toNegativeFlag((_sign < 0) ^ (rhs._sign < 0)));
            }
            else
            {
                auto resultBits = BigIntegerCalculator.multiply(_bits, rhs._bits);
                setNegInts(resultBits[], toNegativeFlag((_sign < 0) ^ (rhs._sign < 0)));
            }

            return this;
        }
        else static if (op == "/")
        {
            assert(isValid() == 0);

            const trivialDividend = _bits.length == 0;
            const trivialDivisor = rhs._bits.length == 0;

            if (trivialDividend && trivialDivisor)
                setInt(_sign / rhs._sign);
            // The divisor is non-trivial and therefore the bigger one
            else if (trivialDividend)
                setZero();
            else if (trivialDivisor)
            {
                auto resultBits = BigIntegerCalculator.divide(_bits, BigIntegerHelper.abs(rhs._sign));
                setNegInts(resultBits[], toNegativeFlag((_sign < 0) ^ (rhs._sign < 0)));
            }
            else if (_bits.length < rhs._bits.length)
                setZero();
            else
            {
                auto resultBits = BigIntegerCalculator.divide(_bits, rhs._bits);
                setNegInts(resultBits[], toNegativeFlag((_sign < 0) ^ (rhs._sign < 0)));
            }

            return this;
        }
        else static if (op == "%")
        {
            assert(isValid() == 0);

            const trivialDividend = _bits.length == 0;
            const trivialDivisor = rhs._bits.length == 0;

            if (trivialDividend && trivialDivisor)
                setInt(_sign % rhs._sign);
            // The divisor is non-trivial and therefore the bigger one
            else if (trivialDividend)
                setSignInts(_bits, _sign);
            else if (trivialDivisor)
            {
                uint remainder = BigIntegerCalculator.remainder(_bits, BigIntegerHelper.abs(rhs._sign));
                if (_sign < 0)
                    setInt(-1 * remainder);
                else
                    setInt(remainder);
            }
            else if (_bits.length < rhs._bits.length)
            {
                //setSignInts(_bits, _sign);
            }
            else
            {
                auto resultBits = BigIntegerCalculator.remainder(_bits, rhs._bits);
                setNegInts(resultBits[], toNegativeFlag(_sign < 0));
            }

            return this;
        }
        else
            static assert(0, typeof(this).stringof ~ " " ~ op ~ "= " ~ T.stringof ~ " is not supported");
    }

    ref BigInteger opOpAssign(string op, T)(const(T) rhs) nothrow pure return
    if ((op == "+" || op == "-" || op == "*" || op == "/" || op == "%") && isIntegral!T)
    {
        return this.opOpAssign!op(BigInteger(rhs));
    }

    ref BigInteger opOpAssign(string op, T)(const(T) rhs) nothrow pure return
    if ((op == "&" || op == "|" || op == "^") && is(T: BigInteger))
    {
        static if (op == "&")
        {
            if (isZero || rhs.isZero)
            {
                setZero();
                return this;
            }
            else if (_bits.length == 0 && rhs._bits.length == 0)
            {
                setInt(_sign & rhs._sign);
                return this;
            }
        }
        else static if (op == "|")
        {
            if (isZero)
            {
                setSignInts(rhs._bits, rhs._sign);
                return this;
            }
            else if (rhs.isZero)
                return this;
            else if (_bits.length == 0 && rhs._bits.length == 0)
            {
                setInt(_sign | rhs._sign);
                return this;
            }
        }
        else static if (op == "^")
        {
            if (_bits.length == 0 && rhs._bits.length == 0)
            {
                setInt(_sign ^ rhs._sign);
                return this;
            }
        }
        else
            static assert(0, typeof(this).stringof ~ " " ~ op ~ "= " ~ T.stringof ~ " is not supported");

        auto x = toUIntArray();
        auto y = rhs.toUIntArray();
        auto z = UIntTempArray(0);
        z.length = Math.Max(x.Length, y.Length);
        const uint xExtend = _sign < 0 ? uint.MaxValue : 0;
        const uint yExtend = rhs._sign < 0 ? uint.MaxValue : 0;

        for (size_t i = 0; i < z.Length; i++)
        {
            const uint xu = i < x.Length ? x[i] : xExtend;
            const uint yu = i < y.Length ? y[i] : yExtend;
            mixin("z[i] = xu " ~ op ~ " yu");
        }

        setBits(z[]);

        return this;
    }

    ref BigInteger opOpAssign(string op, T)(const(T) rhs) nothrow pure return
    if ((op == "&" || op == "|" || op == "^") && isIntegral!T)
    {
        static if (op == "&")
        {
            if (isZero || rhs == 0)
            {
                setZero();
                return this;
            }
            else if (_bits.length == 0)
            {
                setInt(_sign & rhs);
                return this;
            }
        }
        else static if (op == "|")
        {
            if (isZero)
            {
                setInt(rhs);
                return this;
            }
            else if (rhs == 0)
                return this;
            else if (_bits.length == 0)
            {
                setInt(_sign | rhs);
                return this;
            }
        }
        else static if (op == "^")
        {
            if (_bits.length == 0)
            {
                setInt(_sign ^ rhs);
                return this;
            }
        }
        else
            static assert(0, typeof(this).stringof ~ " " ~ op ~ "= " ~ T.stringof ~ " is not supported");

        return this.opOpAssign!op(BigInteger(rigth));
    }

    ref BigInteger opOpAssign(string op)(const(int) rhs) nothrow pure return
    if (op == "<<" || op == ">>" || op == "^^")
    {
        static if (op == "<<")
        {
            const shift = rhs;

            if (shift == 0)
                return this;
            else if (shift == int.min)
            {
                opOpAssign!">>"(int.max);
                opOpAssign!">>"(1);
                return this;
            }
            else if (shift < 0)
                return opOpAssign!">>"(-shift);
            else
            {
                const int digitShift = shift / kcbitUint;
                const int smallShift = shift - (digitShift * kcbitUint);

                UIntTempArray xd;
                int xl;
                const bool negx = getPartsForBitManipulation(this, xd, xl);

                const int zl = xl + digitShift + 1;
                auto zd = UIntTempArray(0);
                zd.length = zl;

                if (smallShift == 0)
                {
                    for (int i = 0; i < xl; i++)
                        zd[i + digitShift] = xd[i];
                }
                else
                {
                    const int carryShift = kcbitUint - smallShift;
                    uint carry = 0;
                    int i;
                    for (i = 0; i < xl; i++)
                    {
                        uint rot = xd[i];
                        zd[i + digitShift] = rot << smallShift | carry;
                        carry = rot >> carryShift;
                    }
                    zd[i + digitShift] = carry;
                }
                setNegInts(zd[], toNegativeFlag(negx));

                return this;
            }
        }
        else static if (op == ">>")
        {
            const shift = rhs;

            if (shift == 0)
                return this;
            else if (shift == int.min)
            {
                opOpAssign!"<<"(int.max);
                opOpAssign!"<<"(1);
                return this;
            }
            else if (shift < 0)
                return opOpAssign!"<<"(-shift);
            else
            {
                const int digitShift = shift / kcbitUint;
                const int smallShift = shift - (digitShift * kcbitUint);

                UIntTempArray xd;
                int xl;
                const bool negx = getPartsForBitManipulation(this, xd, xl);

                if (negx)
                {
                    if (shift >= (kcbitUint * xl))
                    {
                        setNegOne();
                        return this;
                    }

                    BigIntegerCalculator.makeTwosComplement(xd); // Mutates xd
                }

                int zl = xl - digitShift;
                if (zl < 0)
                    zl = 0;
                auto zd = UIntTempArray(0);
                zd.length = zl;

                if (smallShift == 0)
                {
                    for (int i = xl - 1; i >= digitShift; i--)
                        zd[i - digitShift] = xd[i];
                }
                else
                {
                    const int carryShift = kcbitUint - smallShift;
                    uint carry = 0;
                    for (int i = xl - 1; i >= digitShift; i--)
                    {
                        uint rot = xd[i];
                        if (negx && i == xl - 1)
                            // sign-extend the first shift for negative ints then let the carry propagate
                            zd[i - digitShift] = (rot >> smallShift) | (0xFFFFFFFF << carryShift);
                        else
                            zd[i - digitShift] = (rot >> smallShift) | carry;
                        carry = rot << carryShift;
                    }
                }
                if (negx)
                    BigIntegerCalculator.makeTwosComplement(zd);
                setNegInts(zd[], toNegativeFlag(negx));

                return this;
            }
        }
        else static if (op == "^^")
        {
            assert(isValid() == 0);

            const exponent = rhs;

            // x^(-p) == 1/(x^(p))
            if (exponent < 0)
            {
                const tempValue = this ^^ BigIntegerHelper.abs(exponent);
                if (tempValue.isOne)
                    setOne();
                else
                    setZero();
            }
            else if (exponent == 0)
                setOne();
            else if (exponent != 1)
            {
                const bool trivialValue = _bits.length == 0;

                if (trivialValue)
                {
                    if (_sign == 1 || _sign == 0)
                        return this;
                    else if (_sign == -1)
                    {
                        if ((exponent & 1) == 0)
                            setOne();
                        return this;
                    }
                }

                auto resultBits = trivialValue
                    ? BigIntegerCalculator.pow(BigIntegerHelper.abs(_sign), BigIntegerHelper.abs(exponent))
                    : BigIntegerCalculator.pow(_bits, BigIntegerHelper.abs(exponent));

                setNegInts(resultBits[], toNegativeFlag(_sign < 0 && (exponent & 1) != 0));
            }

            return this;
        }
        else
            static assert(0, typeof(this).stringof ~ " " ~ op ~ "= " ~ int.stringof ~ " is not supported");
    }

    BigInteger opBinary(string op, T)(const(T) rhs) const nothrow pure
    if (((op == "+" || op == "-" || op == "*" || op == "/" || op == "%") && is(T: BigInteger)) ||
        ((op == "&" || op == "|" || op == "^") && is(T: BigInteger)))
    {
        auto result = BigInteger(_bits, _sign);
        return result.opOpAssign!op(rhs);
    }

    BigInteger opBinary(string op, T)(const(T) rhs) const nothrow pure
    if (((op == "+" || op == "-" || op == "*" || op == "/" || op == "%") && isIntegral!T) ||
        ((op == "&" || op == "|" || op == "^") && isIntegral!T))
    {
        auto result = BigInteger(_bits, _sign);
        return result.opOpAssign!op(BigInteger(rhs));
    }

    BigInteger opBinary(string op)(const(int) rhs) const nothrow pure
    if (op == "<<" || op == ">>" || op == "^^")
    {
        auto result = BigInteger(_bits, _sign);
        return result.opOpAssign!op(rhs);
    }

    BigInteger opBinaryRight(string op, T)(const(T) lhs) const nothrow pure
    if (((op == "+" || op == "-" || op == "*" || op == "/" || op == "%") && isIntegral!T) ||
        ((op == "&" || op == "|" || op == "^") && isIntegral!T))
    {
        auto result = BigInteger(lhs);
        return result.opOpAssign!op(this);
    }

    /**
     * A bool cast which return True if this BigInteger instance is not zero
     */
    T opCast(T: bool)() const @nogc nothrow pure
    {
        return !isZero();
    }

    T opCast(T)() @nogc nothrow pure
    if (is(Unqual!T == BigInteger))
    {
        return this;
    }

    T opCast(T)() pure
    if (isIntegral!T)
    {
        static if (isSigned!T)
        {
            long l = toLong();

            static if (!is(Unqual!T == long))
            if (l < T.min || l > T.max)
                convertError(T.stringof);

            return cast(T)l;
        }
        else
        {
            ulong u = toULong();

            static if (!is(Unqual!T == ulong))
            if (u > T.max)
                convertError(T.stringof);

            return cast(T)u;
        }
    }

    T opCast(T)() pure @nogc
    if (isFloatingPoint!T)
    {
        return cast(T)toFloat();
    }

    int opCmp(const(int) rhs) const @nogc nothrow pure
    {
        return opCmp(cast(long)rhs);
    }

    int opCmp(const(uint) rhs) const @nogc nothrow pure
    {
        return opCmp(cast(ulong)rhs);
    }

    int opCmp(const(long) rhs) const @nogc nothrow pure
    {
        assert(isValid() == 0);

        if (_bits.length == 0)
            return BigIntegerHelper.compare(cast(long)_sign, rhs);

        ptrdiff_t cu;
        if ((_sign ^ rhs) < 0 || (cu = _bits.length) > 2)
            return _sign;

        ulong uu = rhs < 0 ? cast(ulong)(-rhs) : cast(ulong)rhs;
        ulong uuTmp = cu == 2 ? BigIntegerHelper.makeUlong(_bits[1], _bits[0]) : _bits[0];
        return _sign * BigIntegerHelper.compare(uuTmp, uu);
    }

    int opCmp(const(ulong) rhs) const @nogc nothrow pure
    {
        assert(isValid() == 0);

        if (_sign < 0)
            return -1;

        if (_bits.length == 0)
            return BigIntegerHelper.compare(cast(ulong)_sign, rhs);

        const cu = _bits.length;
        if (cu > 2)
            return +1;

        ulong uuTmp = cu == 2 ? BigIntegerHelper.makeUlong(_bits[1], _bits[0]) : _bits[0];
        return BigIntegerHelper.compare(uuTmp, rhs);
    }

    int opCmp(scope const(BigInteger) rhs) const @nogc nothrow pure
    in
    {
        assert(rhs.isValid() == 0);
    }
    do
    {
        assert(isValid() == 0);

        if ((_sign ^ rhs._sign) < 0)
        {
            // Different signs, so the comparison is easy.
            return _sign < 0 ? -1 : +1;
        }

        // Same signs
        if (_bits.length == 0)
        {
            if (rhs._bits.length == 0)
                return _sign < rhs._sign ? -1 : (_sign > rhs._sign ? +1 : 0);
            else
                return -rhs._sign;
        }

        ptrdiff_t cuThis, cuOther;
        if (rhs._bits.length == 0 || (cuThis = _bits.length) > (cuOther = rhs._bits.length))
            return _sign;

        if (cuThis < cuOther)
            return -_sign;

        auto cuDiff = getDiffLength(_bits, rhs._bits, cuThis);
        if (cuDiff == 0)
            return 0;

        return _bits[cuDiff - 1] < rhs._bits[cuDiff - 1] ? -_sign : _sign;
    }

    bool opEquals(const(int) rhs) const @nogc nothrow pure
    {
        return opEquals(cast(long)rhs);
    }

    bool opEquals(const(uint) rhs) const @nogc nothrow pure
    {
        return opEquals(cast(ulong)rhs);
    }

    bool opEquals(const(long) rhs) const @nogc nothrow pure
    {
        assert(isValid() == 0);

        if (_bits.length == 0)
            return _sign == rhs;

        long cu;
        if ((_sign ^ rhs) < 0 || (cu = _bits.length) > 2)
            return false;

        const ulong uu = rhs < 0 ? cast(ulong)(-rhs) : cast(ulong)rhs;
        if (cu == 1)
            return _bits[0] == uu;

        return BigIntegerHelper.makeUlong(_bits[1], _bits[0]) == uu;
    }

    bool opEquals(const(ulong) rhs) const @nogc nothrow pure
    {
        assert(isValid() == 0);

        if (_sign < 0)
            return false;

        if (_bits.length == 0)
            return cast(ulong)_sign == rhs;

        const size_t cu = _bits.length;
        if (cu > 2)
            return false;

        if (cu == 1)
            return _bits[0] == rhs;

        return BigIntegerHelper.makeUlong(_bits[1], _bits[0]) == rhs;
    }

    bool opEquals(scope const(BigInteger) rhs) const @nogc nothrow pure
    in
    {
        assert(rhs.isValid() == 0);
    }
    do
    {
        assert(isValid() == 0);

        if (_sign != rhs._sign)
            return false;

        if (_bits == rhs._bits)
            // _sign == rhs._sign && _bits.length == 0 && rhs._bits.length == 0
            return true;

        if (_bits.length == 0 || rhs._bits.length == 0)
            return false;

        const ptrdiff_t cu = _bits.length;
        if (cu != rhs._bits.length)
            return false;

        return getDiffLength(_bits, rhs._bits, cu) == 0;
    }

    ref BigInteger opUnary(string op)() nothrow return
    if (op == "+" || op == "-" || op == "~" || op == "++" || op == "--")
    {
        static if (op == "+")
        {
            assert(isValid() == 0);
        }
        else static if (op == "-")
        {
            assert(isValid() == 0);

            setSignInts(_bits, -_sign);
        }
        else static if (op == "~")
        {
            // -(this + one);
            this.opOpAssign!"+"(one);
            setSignInts(_bits, -_sign);
        }
        else static if (op == "++")
        {
            this.opOpAssign!"+"(one);
        }
        else static if (op == "--")
        {
            this.opOpAssign!"-"(one);
        }
        else
            static assert(0, op ~ "= " ~ typeof(this).stringof  ~ " is not supported");

        return this;
    }

    /**
     * For security reason, need a way clear the internal data
     */
    void dispose(const(DisposingReason) disposingReason = DisposingReason.dispose) @nogc nothrow pure @safe
    {
        _sign = 0;
        _bits[] = 0;
    }

    BigInteger dup() const nothrow pure
    {
        BigInteger result;
        result.setSignInts(this._bits, this._sign);
        return result;
    }

    /**
     * Gets the number of bytes that will be output by <see cref="toBytes()"/>
     * Returns:
     *  The number of bytes
     */
    size_t getByteCount(const(Flag!"includeSign") includeSign = Yes.includeSign) const nothrow
    {
        // Big or Little Endian doesn't matter for the byte count.
        UByteTempArray bytes;
        return getUBytesLittleEndian(bytes, includeSign);
    }

    /**
     * Set this BigInteger as odd value
     */
    ref BigInteger setOdd() nothrow pure return
    {
        if (_bits.length == 0)
            setOne();
        else
            _bits[0] |= 1;
        return this;
    }

    /**
     * Set this BigInteger as zero value
     */
    ref BigInteger setZero() nothrow pure return
    {
        _sign = 0;
        _bits = null;
        return this;
    }

    /**
     * Return a BigInteger as -1 value
     */
    static BigInteger negOne() nothrow pure
    {
        return BigInteger(-1);
    }

    /**
     * Return a BigInteger as 1 value
     */
    static BigInteger one() nothrow pure
    {
        return BigInteger(1);
    }

    /**
     * Return a BigInteger as 0 value
     */
    static BigInteger zero() nothrow pure
    {
        return BigInteger(0);
    }

    /**
     * Return this BigInteger as a double value
     */
    double toFloat() const @nogc nothrow pure scope
    {
        assert(isValid() == 0);

        const len = cast(int)_bits.length;

        if (len == 0)
            return _sign;

        // The maximum exponent for doubles is 1023, which corresponds to a uint bit length of 32.
        // All BigIntegers with bits[] longer than 32 evaluate to Double.Infinity (or NegativeInfinity).
        // Cases where the exponent is between 1024 and 1035 are handled in BigIntegerHelper.GetDoubleFromParts.
        enum infinityLength = 1_024 / kcbitUint;

        if (len > infinityLength)
        {
            if (sign >= 0)
                return double.infinity;
            else
                return -double.infinity;
        }

        const ulong h = _bits[len - 1];
        const ulong m = len > 1 ? _bits[len - 2] : 0;
        const ulong l = len > 2 ? _bits[len - 3] : 0;
        const int z = BigIntegerHelper.cbitHighZero(cast(uint)h);

        const int exp = (len - 2) * 32 - z;
        const ulong man = (h << 32 + z) | (m << z) | (l >> 32 - z);

        return BigIntegerHelper.getDoubleFromParts(_sign, exp, man);
    }

    size_t toHash() const nothrow @nogc @safe scope
    {
        assert(isValid() == 0);

        if (_bits.length == 0)
            return cast(size_t)_sign;

        size_t hash = cast(size_t)_sign;
        for (ptrdiff_t iv = _bits.length; --iv >= 0;)
            hash = BigIntegerHelper.combineHash(hash, cast(size_t)_bits[iv]);

        return hash;
    }

    /**
     * Return this BigInteger as a long value (64 bits)
     */
    long toLong() const pure scope
    {
        assert(isValid() == 0);

        const len = _bits.length;

        if (len == 0)
            return _sign;

        if (len > 2)
            convertError("long");

        const ulong uu = len > 1
            ? BigIntegerHelper.makeUlong(_bits[1], _bits[0])
            : _bits[0];

        const long ll = _sign > 0 ? cast(long)uu : -(cast(long)uu);

        // Signs match, no overflow
        if ((ll > 0 && _sign > 0) || (ll < 0 && _sign < 0))
            return ll;

        convertError("long");
        return 0; // Fix warning
    }

    /**
     * Return this BigInteger as a ulong value (64 bits)
     */
    ulong toULong() const pure scope
    {
        assert(isValid() == 0);

        const len = _bits.length;

        if (len > 2 || _sign < 0)
            convertError("ulong");

        if (len == 0)
            return cast(ulong)_sign;
        else if (len > 1)
            return BigIntegerHelper.makeUlong(_bits[1], _bits[0]);
        else
            return _bits[0];
    }

    /**
     * Returns the value of this BigInteger as a ubyte array in little endian format using the fewest number of bytes possible.
     * If the value is zero, returns an array of one ubyte whose element is 0x00.
     * Params:
     *  includeSign = Whether or not an unsigned encoding is to be used
     * Returns:
     *  This BigInteger value as ubyte[]
     */
    ubyte[] toBytes(const(Flag!"includeSign") includeSign = Yes.includeSign) const nothrow pure @safe scope
    {
        UByteTempArray tempResult;
        getUBytesLittleEndian(tempResult, includeSign);
        return tempResult.dup;
    }

    ref Writer toBytes(Writer)(return ref Writer sink, const(Flag!"includeSign") includeSign = Yes.includeSign) const nothrow pure @safe scope
    if (isOutputRange!(Writer, ubyte))
    {
        UByteTempArray tempResult;
        getUBytesLittleEndian(tempResult, includeSign);
        put(sink, tempResult[]);
        return sink;
    }

    /**
     * Return the value of this BigInteger as a little-endian twos-complement
     * uint array, using the fewest number of uints possible. If the value is zero,
     * return an array of one uint whose element is 0.
     * Params:
     *  includeSign = Whether or not an unsigned encoding is to be used
     * Returns:
     *  This BigInteger value as uint[]
     */
    uint[] toInts(const(Flag!"includeSign") includeSign = Yes.includeSign) const nothrow @safe scope
    {
        UIntTempArray result;
        toInts(result, includeSign);
        return result.dup;
    }

    /**
     * Returns the number of uints of this BigInteger
     * Params:
     *  result = UByteTempArray contains as a uint array in little endian format
     *           using the fewest number of uints possible.
     *           If the value is zero, returns an UByteTempArray of one uint whose element is 0x00.
     *  includeSign = Whether or not an unsigned encoding is to be used
     * Returns:
     *  This BigInteger value as UIntTempArray
     */
    size_t toInts(ref UIntTempArray result, const(Flag!"includeSign") includeSign = Yes.includeSign) const nothrow @safe scope
    {
        uint highDWord;
        cloneForConvert!uint(result, highDWord);

        // Find highest significant byte
        auto msb = result.length - 1;
        for (; msb > 0; msb--)
        {
            if (result[msb] != highDWord)
                break;
        }

        // Ensure high bit is 0 if positive, 1 if negative
        const needExtraByte = includeSign && (result[msb] & 0x80000000) != (highDWord & 0x80000000) ? 1 : 0;

        const resultLength = msb + 1 + needExtraByte;
        result.length = resultLength;
        if (needExtraByte)
            result[resultLength - 1] = highDWord;
        return resultLength;
    }

    ref Writer toDigitString(Writer, Char)(return ref Writer sink, scope const ref FormatSpec!Char f) const nothrow pure @safe
    if (isOutputRange!(Writer, Char) && isSomeChar!Char)
    in
    {
        assert(f.spec == 'd' || f.spec == 's');
    }
    do
    {
        scope (failure) assert(0, "Assume nothrow failed");

        const ptrdiff_t cuSrc = _bits.length;

        if (cuSrc == 0)
        {
            formatValue(sink, _sign, f);
            return sink;
        }

        // First convert to base 10^9.
        const uint kuBase = 1_000_000_000; // 10^9
        const int kcchBase = 9;

        const size_t cuMax = cuSrc * 10 / 9 + 2;
        auto rguDst = UIntTempArray(cuMax);
        ptrdiff_t cuDst = 0;

        for (ptrdiff_t iuSrc = cuSrc; --iuSrc >= 0;)
        {
            uint uCarry = _bits[iuSrc];
            for (size_t iuDst = 0; iuDst < cuDst; iuDst++)
            {
                assert(rguDst[iuDst] < kuBase);
                const ulong uuRes = BigIntegerHelper.makeUlong(rguDst[iuDst], uCarry);
                rguDst[iuDst] = cast(uint)(uuRes % kuBase);
                uCarry = cast(uint)(uuRes / kuBase);
            }
            if (uCarry != 0)
            {
                rguDst[cuDst++] = uCarry % kuBase;
                uCarry /= kuBase;
                if (uCarry != 0)
                    rguDst[cuDst++] = uCarry;
            }
        }

        // Each uint contributes at most 9 digits to the decimal representation.
        // Leave an extra slot for a minus sign.
        const char signChar = _sign < 0 ? '-' : (f.flPlus ? '+' : 0);
        const size_t cchMax = cuDst * kcchBase + (signChar != 0 ? 1 : 0);
        ptrdiff_t ichDst = cchMax;
        auto rgch = CharTempArray(cchMax);
        for (ptrdiff_t iuDst = 0; iuDst < cuDst - 1; iuDst++)
        {
            uint uDig = rguDst[iuDst];
            assert(uDig < kuBase);
            for (int cch = kcchBase; --cch >= 0;)
            {
                rgch[--ichDst] = cast(char)('0' + uDig % 10);
                uDig /= 10;
            }
        }
        for (uint uDig = rguDst[cuDst - 1]; uDig != 0;)
        {
            rgch[--ichDst] = cast(char)('0' + uDig % 10);
            uDig /= 10;
        }

        ptrdiff_t resultLength = cchMax - ichDst - (signChar != 0 ? 1 : 0);
        while (resultLength < f.width)
        {
            put(sink, '0');
            ++resultLength;
        }

        if (signChar != 0)
            put(sink, signChar);

        auto digits = rgch[ichDst..rgch.length];
        if (f.flSeparator)
        {
            for (size_t j = 0; j < digits.length; ++j)
            {
                if (j != 0 && (digits.length - j) % f.separators == 0)
                    put(sink, f.separatorChar);
                put(sink, digits[j]);
            }
        }
        else
            put(sink, digits);

        return sink;
    }

    string toHexString(const(Flag!"includeSign") includeSign = Yes.includeSign,
        const(LetterCase) letterCase = LetterCase.upper) const nothrow pure @safe scope
    {
        FormatSpec!char f;
        f.spec = letterCase == LetterCase.upper ? 'X' : 'x';
        ShortStringBuffer!char buffer;
        return toHexString!(ShortStringBuffer!char, char)(buffer, f, includeSign).toString();
    }

    ref Writer toHexString(Writer, Char)(return ref Writer sink, const(Flag!"includeSign") includeSign = Yes.includeSign,
        const(LetterCase) letterCase = LetterCase.upper) const nothrow pure @safe scope
    if (isOutputRange!(Writer, Char) && isSomeChar!Char)
    {
        FormatSpec!Char f;
        f.spec = letterCase == LetterCase.upper ? 'X' : 'x';
        return toHexString(sink, f, includeSign);
    }

    ref Writer toHexString(Writer, Char)(return ref Writer sink, scope const ref FormatSpec!Char f,
        const(Flag!"includeSign") includeSign) const nothrow pure @safe
    if (isOutputRange!(Writer, Char) && isSomeChar!Char)
    in
    {
        assert(f.spec == 'x' || f.spec == 'X');
    }
    do
    {
        scope (failure) assert(0, "Assume nothrow failed");

        const isUpper = f.spec == 'X';
        const hexDigitSources = isUpper ? upperHexDigits : lowerHexDigits;

        UByteTempArray bytesHolder;
        getUBytesLittleEndian(bytesHolder, includeSign);
        auto bytes = bytesHolder[];

        auto hexDigits = CharTempArray(bytes.length * 2);

        size_t charsPos = 0;
        ptrdiff_t cur = cast(ptrdiff_t)(bytes.length) - 1;
        if (cur >= 0)
        {
            // [FF..F8] drop the high F as the two's complement negative number remains clear
            // [F7..08] retain the high bits as the two's complement number is wrong without it
            // [07..00] drop the high 0 as the two's complement positive number remains clear
            bool clearHighF = false;
            ubyte head = bytes[cur];

            if (head > 0xF7)
            {
                head -= 0xF0;
                clearHighF = true;
            }

            if (head < 0x08 || clearHighF)
            {
                // {0xF8-0xFF} print as {8-F}
                // {0x00-0x07} print as {0-7}
                hexDigits[charsPos++] = head < 10
                    ? cast(char)(head + '0')
                    : (isUpper
                        ? cast(char)((head & 0xF) - 10 + 'A')
                        : cast(char)((head & 0xF) - 10 + 'a'));
                cur--;
            }
        }

        while (cur >= 0)
        {
            const b = bytes[cur--];
            hexDigits[charsPos++] = hexDigitSources[b >> 4];
            hexDigits[charsPos++] = hexDigitSources[b & 0xF];
        }

        ptrdiff_t resultLength = charsPos;
        while (resultLength < f.width)
        {
            put(sink, '0');
            ++resultLength;
        }

        if (f.flSeparator)
        {
            const len = hexDigits.length;
            for (size_t j = 0; j < len; ++j)
            {
                if (j != 0 && (len - j) % f.separators == 0)
                    put(sink, f.separatorChar);
                put(sink, hexDigits[j]);
            }
        }
        else
            put(sink, hexDigits[]);

        return sink;
    }

    string toString() const nothrow pure @safe scope
    {
        ShortStringBuffer!char buffer;
        auto fmtSpec = simpleIntegerFmt();
        return toString(buffer, fmtSpec).toString();
    }

    string toString(scope const(char)[] fmt) const pure @safe scope
    {
        ShortStringBuffer!char buffer;
        return toString!(ShortStringBuffer!char, char)(buffer, fmt).toString();
    }

    string toString(scope const(char)[] fmt, char separatorChar) const pure @safe scope
    {
        ShortStringBuffer!char buffer;

        auto f = FormatSpec!char(fmt);
        f.separatorChar = separatorChar;
        f.flSeparator = separatorChar != '\0';
        f.writeUpToNextSpec(buffer);

        return toString(buffer, f).toString();
    }

    ref Writer toString(Writer, Char)(return ref Writer sink, scope const(Char)[] fmt) const pure @safe
    if (isOutputRange!(Writer, Char) && isSomeChar!Char)
    {
        auto f = FormatSpec!Char(fmt);
        f.writeUpToNextSpec(sink);
        return toString(sink, f);
    }

    ref Writer toString(Writer, Char)(return ref Writer sink, scope const ref FormatSpec!Char f) const nothrow pure @safe
    if (isOutputRange!(Writer, Char) && isSomeChar!Char)
    in
    {
        assert(f.spec == 'd' || f.spec == 's' || f.spec == 'x' || f.spec == 'X');
    }
    do
    {
        if (f.spec == 'd' || f.spec == 's')
            return toDigitString(sink, f);
        else if (f.spec == 'x' || f.spec == 'X')
            return toHexString(sink, f, Yes.includeSign);
       else
            assert(0, "Invalid format specifier: %" ~ f.spec);
    }

    // Length in bits
    @property uint bitLength() const @nogc nothrow pure scope
    {
        import std.math : abs;

        return _bits.length == 0
            ? .bitLength(cast(uint)abs(_sign))
            : cast(uint)(_bits.length - 1) * kcbitUint + .bitLength(_bits[$ - 1]);
    }

    /// Returns the value of the i'th bit, with lsb == bit 0.
    @property bool bitSet(size_t index) const @nogc nothrow pure scope
    {
        const uint bp = 1u << (index % kcbitUint);
        const size_t bs = index / kcbitUint;
        const size_t count = _bits.length != 0 ? _bits.length : 1;
        if (bs >= count)
            return false;

        const uint bits = _bits.length != 0 ? _bits[bs] : cast(uint)_sign;
        return (bits & bp) != 0;
    }

    @property ref BigInteger bitSet(size_t index, bool value) nothrow pure return
    {
        const uint bp = 1u << (index % kcbitUint);
        const size_t bs = index / kcbitUint;
        const size_t count = _bits.length != 0 ? _bits.length : 1;
        if (bs >= count)
            return this;

        uint* bits = _bits.length != 0 ? &_bits[bs] : cast(uint*)&_sign;
        if (value)
            *bits |= bp;
        else
            *bits ^= bp;
        // Normalize special value
        if (_bits.length == 0 && _sign == -1)
            setMinInt();

        return this;
    }

    @property uint bitSets(size_t index) const @nogc nothrow pure scope
    {
        return _bits.length != 0
            ? (index < _bits.length ? _bits[index] : 0)
            : (index == 0 ? cast(uint)_sign : 0);
    }

    @property bool isEven() const @nogc nothrow pure scope
    {
        assert(isValid() == 0);

        return _bits.length == 0 ? ((_sign & 1) == 0) : ((_bits[0] & 1) == 0);
    }

    @property bool isOne() const @nogc nothrow pure scope
    {
        assert(isValid() == 0);

        return _sign == 1 && _bits.length == 0;
    }

    @property bool isPowerOfTwo() const @nogc nothrow pure scope
    {
        assert(isValid() == 0);

        if (_bits.length == 0)
            return (_sign & (_sign - 1)) == 0 && _sign != 0;

        if (_sign != 1)
            return false;

        ptrdiff_t iu = cast(ptrdiff_t)(_bits.length) - 1;
        if ((_bits[iu] & (_bits[iu] - 1)) != 0)
            return false;

        while (--iu >= 0)
        {
            if (_bits[iu] != 0)
                return false;
        }

        return true;
    }

    @property bool isZero() const @nogc nothrow pure scope
    {
        assert(isValid() == 0);

        return _sign == 0 && _bits.length == 0;
    }

    /**
     * Returns a number that indicates the sign (negative, positive, or zero)
     * Returns
     *  -1  The value is negative.
     *  0   The value is 0 (zero).
     *  1 	The value is positive.
     */
    @property int sign() const @nogc nothrow pure scope
    {
        assert(isValid() == 0);

        return (_sign >> (kcbitUint - 1)) - (-_sign >> (kcbitUint - 1));
    }

    /// Returns the number of consecutive least significant zero
    @property uint trailingZeroBits() const @nogc nothrow pure scope
    {
        import std.math : abs;

        if (_bits.length == 0)
            return isZero ? 0 : .trailingZeroBits(cast(uint)abs(_sign));

        uint i;
        foreach (b; _bits)
        {
            if (b == 0)
                i++;
            else
                break;
        }
    	// x[i] != 0
	    return i*kcbitUint + .trailingZeroBits(_bits[i]);
    }

private:
    ref BigInteger addOpAssign(scope const(uint)[] rightBits, int rightSign) nothrow pure return
    {
        const trivialLeft = _bits.length == 0;
        const trivialRight = rightBits.length == 0;

        if (trivialLeft && trivialRight)
            setInt(cast(long)_sign + rightSign);
        else if (trivialLeft)
        {
            auto resultBits = BigIntegerCalculator.add(rightBits, BigIntegerHelper.abs(_sign));
            setNegInts(resultBits[], toNegativeFlag(_sign < 0));
        }
        else if (trivialRight)
        {
            auto resultBits = BigIntegerCalculator.add(_bits, BigIntegerHelper.abs(rightSign));
            setNegInts(resultBits[], toNegativeFlag(_sign < 0));
        }
        else if (_bits.length < rightBits.length)
        {
            auto resultBits = BigIntegerCalculator.add(rightBits, _bits);
            setNegInts(resultBits[], toNegativeFlag(_sign < 0));
        }
        else
        {
            auto resultBits = BigIntegerCalculator.add(_bits, rightBits);
            setNegInts(resultBits[], toNegativeFlag(_sign < 0));
        }

        return this;
    }

    void convertError(string toT) const pure scope
    {
        import std.conv : ConvException;

        auto msg = "Error converting BigInteger(" ~ toString() ~ ") to " ~ toT;
        throw new ConvException(msg);
    }

    void cloneForConvert(I)(ref UIntTempArray result, out I highMark) const
    if (isUnsigned!I)
    {
        if (_bits.length == 0)
        {
            highMark = _sign < 0 ? I.max : 0;
            result.clear(1);
            result[0] = cast(uint)_sign;
        }
        else if (_sign < 0)
        {
            highMark = I.max;
            result = _bits;
            BigIntegerCalculator.makeTwosComplement(result);
        }
        else
        {
            highMark = 0;
            result = _bits;
        }
    }

    int isValid() const @nogc nothrow pure scope
    {
        return isValid(_bits, _sign);
    }

    static int isValid(scope const(uint)[] bits, const(int) sign) @nogc nothrow pure
    {
        // int.min should not be stored in the sign field
        if (bits.length == 0)
            return sign > int.min ? 0 : 1;

        // sign must be +1 or -1 when bits is non-empty
        if (!(sign == 1 || sign == -1))
            return 2;

        // Wasted space: bits[0] could have been packed into sign
        if (!(bits.length > 1 || bits[0] >= kuMaskHighBit))
            return 3;

        // Wasted space: leading zeros could have been truncated
        if (!(bits[$ - 1] != 0))
            return 4;

        return 0;
    }

    static ptrdiff_t getDiffLength(scope const(uint)[] rgu1, scope const(uint)[] rgu2, ptrdiff_t cu) @nogc nothrow pure
    {
        for (ptrdiff_t iv = cu; --iv >= 0;)
        {
            if (rgu1[iv] != rgu2[iv])
                return iv + 1;
        }
        return 0;
    }

    /**
     * Encapsulate the logic of normalizing the "small" and "large" forms of BigInteger
     * into the "large" form so that Bit Manipulation algorithms can be simplified
     * Params:
     *  x = BigInteger instance
     *  xd = The UInt32 array containing the entire big integer in "large" (denormalized) form.
     *       E.g., the number one (1) and negative one (-1) are both stored as 0x00000001
     *       BigInteger values Int32.MinValue< x >= Int32.MaxValue are converted to this
     *       format for convenience
     *  xl = The length of xd
     * Returns:
     *  True for negative numbers
     */
    static bool getPartsForBitManipulation(const(BigInteger) x, out UIntTempArray xd, out int xl) nothrow pure
    {
        const len = x._bits.length;

        if (len == 0)
        {
            xd.length = 1;
            if (x._sign < 0)
                xd[0] = cast(uint)(-x._sign);
            else
                xd[0] = cast(uint)x._sign;
        }
        else
        {
            xd = UIntTempArray(x._bits);
        }

        xl = len == 0 ? 1 : cast(int)len;

        return x._sign < 0;
    }

    size_t getUBytesLittleEndian(ref UByteTempArray bytes, const(Flag!"includeSign") includeSign) const nothrow pure scope
    {
        // We could probably make this more efficient by eliminating one of the passes.
        // The current code does one pass for uint array -> byte array conversion,
        // and then another pass to remove unneeded bytes at the top of the array.
        ubyte highByte;
        UIntTempArray dwords;
        cloneForConvert!ubyte(dwords, highByte);
        bytes.clear(4 * dwords.length);
        size_t curByte = 0;
        foreach (dword; dwords)
        {
            for (int j = 0; j < 4; j++)
            {
                bytes[curByte++] = cast(ubyte)(dword & 0xff);
                dword >>= 8;
            }
        }

        // find highest significant byte
        auto msb = bytes.length - 1;
        for (; msb > 0; msb--)
        {
            if (bytes[msb] != highByte)
                break;
        }

        // ensure high bit is 0 if positive, 1 if negative
        const needExtraByte = includeSign && (bytes[msb] & 0x80) != (highByte & 0x80) ? 1 : 0;

        const resultLength = msb + 1 + needExtraByte;
        bytes.length = resultLength;
        if (needExtraByte)
            bytes[resultLength - 1] = highByte;
        return resultLength;
    }

    void setBytes(scope const(ubyte)[] value,
        const(Flag!"unsigned") unsigned = No.unsigned,
        const(Flag!"bigEndian") bigEndian = No.bigEndian) nothrow pure
    {
        bool isNegative = false;
        ptrdiff_t byteCount = cast(ptrdiff_t)(value.length);
        if (byteCount > 0)
        {
            const ubyte mostSignificantByte = bigEndian ? value[0] : value[byteCount - 1];
            isNegative = (mostSignificantByte & 0x80) != 0 && !unsigned;

            if (mostSignificantByte == 0)
            {
                // Try to conserve space as much as possible by checking for wasted leading ubyte[] entries
                if (bigEndian)
                {
                    size_t offset = 1;
                    while (offset < byteCount && value[offset] == 0)
                        offset++;

                    value = value[offset..$];
                    byteCount = cast(ptrdiff_t)(value.length);
                }
                else
                {
                    byteCount -= 2;
                    while (byteCount >= 0 && value[byteCount] == 0)
                        byteCount--;
                    byteCount++;
                }
            }
        }

        if (byteCount == 0)
        {
            // BigInteger.zero
            _sign = 0;
            _bits = null;

            return;
        }

        if (byteCount <= 4)
        {
            _sign = isNegative ? cast(int)0xffffffff : 0;

            if (bigEndian)
            {
                for (size_t i = 0; i < byteCount; i++)
                {
                    _sign = (_sign << 8) | value[i];
                }
            }
            else
            {
                for (ptrdiff_t i = byteCount - 1; i >= 0; i--)
                {
                    _sign = (_sign << 8) | value[i];
                }
            }

            _bits = null;
            if (_sign < 0 && !isNegative)
            {
                // Int32 overflow
                // Example: Int64 value 2362232011 (0xCB, 0xCC, 0xCC, 0x8C, 0x0)
                // can be naively packed into 4 bytes (due to the leading 0x0)
                // it overflows into the int32 sign bit

                _bits = [cast(uint)_sign];
                _sign = +1;
            }
            if (_sign == int.min)
                setMinInt();
        }
        else
        {
            const ptrdiff_t unalignedBytes = byteCount % 4;
            const ptrdiff_t dwordCount = byteCount / 4 + (unalignedBytes == 0 ? 0 : 1);
            const ptrdiff_t byteCountMinus1 = byteCount - 1;
            auto val = UIntTempArray(0);
            val.length = dwordCount;

            // Copy all dwords, except don't do the last one if it's not a full four bytes
            ptrdiff_t curDword, curByte;

            if (bigEndian)
            {
                curByte = byteCount - int.sizeof;
                for (curDword = 0; curDword < dwordCount - (unalignedBytes == 0 ? 0 : 1); curDword++)
                {
                    for (size_t byteInDword = 0; byteInDword < 4; byteInDword++)
                    {
                        const ubyte curByteValue = value[curByte];
                        val[curDword] = (val[curDword] << 8) | curByteValue;
                        curByte++;
                    }

                    curByte -= 8;
                }
            }
            else
            {
                curByte = int.sizeof - 1;
                for (curDword = 0; curDword < dwordCount - (unalignedBytes == 0 ? 0 : 1); curDword++)
                {
                    for (size_t byteInDword = 0; byteInDword < 4; byteInDword++)
                    {
                        const ubyte curByteValue = value[curByte];
                        val[curDword] = (val[curDword] << 8) | curByteValue;
                        curByte--;
                    }

                    curByte += 8;
                }
            }

            // Copy the last dword specially if it's not aligned
            if (unalignedBytes != 0)
            {
                if (isNegative)
                    val[dwordCount - 1] = 0xffffffff;

                if (bigEndian)
                {
                    for (curByte = 0; curByte < unalignedBytes; curByte++)
                    {
                        const ubyte curByteValue = value[curByte];
                        val[curDword] = (val[curDword] << 8) | curByteValue;
                    }
                }
                else
                {
                    for (curByte = byteCountMinus1; curByte >= byteCount - unalignedBytes; curByte--)
                    {
                        const ubyte curByteValue = value[curByte];
                        val[curDword] = (val[curDword] << 8) | curByteValue;
                    }
                }
            }

            if (isNegative)
            {
                BigIntegerCalculator.makeTwosComplement(val);

                // Pack _bits to remove any wasted space after the twos complement
                size_t len = val.length;
                while (len > 1 && val[len - 1] == 0)
                    len--;

                if (len == 1)
                {
                    switch (val[0])
                    {
                        case 1: // abs(-1)
                            setNegOne();
                            return;

                        case kuMaskHighBit: // abs(int.min)
                            setMinInt();
                            return;

                        default:
                            if (cast(int)val[0] > 0)
                            {
                                _sign = (-1) * (cast(int)val[0]);
                                _bits = null;
                                assert(isValid() == 0);

                                return;
                            }
                            break;
                    }
                }

                _sign = -1;
                _bits = val[0..len].dup;
            }
            else
            {
                _sign = +1;
                _bits = val.dup();
            }
        }

        assert(isValid() == 0);
    }

    void setInts(scope const(uint)[] value) nothrow pure
    {
        size_t dwordCount = value.length;
        const bool isNegative = dwordCount > 0 && ((value[dwordCount - 1] & 0x80000000) == 0x80000000);

        // Try to conserve space as much as possible by checking for wasted leading uint[] entries
        while (dwordCount > 0 && value[dwordCount - 1] == 0)
            dwordCount--;

        if (dwordCount == 0)
        {
            setZero();
            return;
        }

        if (dwordCount == 1)
        {
            if (cast(int)value[0] < 0 && !isNegative)
            {
                _sign = +1;
                _bits = [value[0]];
            }
            // Handle the special cases where the BigInteger likely fits into _sign
            else if (int.min == cast(int)value[0])
            {
                setMinInt();
            }
            else
            {
                _sign = cast(int)value[0];
                _bits = null;
            }

            assert(isValid() == 0);

            return;
        }

        if (!isNegative)
        {
            // Handle the simple positive value cases where the input is already in sign magnitude
            _sign = +1;
            _bits = value[0..dwordCount].dup;

            assert(isValid() == 0);

            return;
        }

        // Finally handle the more complex cases where we must transform the input into sign magnitude
        auto clonedValue = UIntTempArray(value);
        BigIntegerCalculator.makeTwosComplement(clonedValue);

        // Pack _bits to remove any wasted space after the twos complement
        size_t len = clonedValue.length;
        while (len > 0 && clonedValue[len - 1] == 0)
            len--;

        // The number is represented by a single dword
        const valueAtZero = len != 0 ? clonedValue[0] : 0;
        if (len == 1 && cast(int)valueAtZero > 0)
        {
            if (valueAtZero == 1) // == abs(-1)
                setNegOne();
            else if (valueAtZero == kuMaskHighBit) // == abs(int.min)
                setMinInt();
            else
            {
                _sign = (-1) * cast(int)valueAtZero;
                _bits = null;
            }
        }
        // The number is represented by multiple dwords.
        // Trim off any wasted uint values when possible.
        else
        {
            _sign = -1;
            _bits = clonedValue[0..len].dup;
        }

        assert(isValid() == 0);
    }

    void setFloat(float value) nothrow pure
    {
        setFloat(cast(double)value);
    }

    void setFloat(double value) nothrow pure
    {
        import std.math : isFinite;

        assert(isFinite(value));

        setZero();

        int sign = void, exp = void;
        ulong man = void;
        bool fFinite = void;
        BigIntegerHelper.getDoubleParts(value, sign, exp, man, fFinite);
        assert(sign == +1 || sign == -1);

        if (man == 0)
        {
            //setZero();
            return;
        }

        assert(man < (1UL << 53));
        assert(exp <= 0 || man >= (1UL << 52));

        if (exp <= 0)
        {
            if (exp <= -kcbitUlong)
            {
                //setZero();
                return;
            }
            setInt(man >> -exp);
            if (_sign < 0)
                _sign = -_sign;
        }
        else if (exp <= 11)
        {
            setInt(man << exp);
            if (_sign < 0)
                _sign = -_sign;
        }
        else
        {
            // Overflow into at least 3 uints.
            // Move the leading 1 to the high bit.
            man <<= 11;
            exp -= 11;

            // Compute cu and cbit so that exp == 32 * cu - cbit and 0 <= cbit < 32.
            const int cu = (exp - 1) / kcbitUint + 1;
            const int cbit = cu * kcbitUint - exp;
            assert(0 <= cbit && cbit < kcbitUint);
            assert(cu >= 1);

            // Populate the uints.
            _bits = new uint[](cu + 2);
            _bits[cu + 1] = cast(uint)(man >> (cbit + kcbitUint));
            _bits[cu] = cast(uint)(man >> cbit);
            if (cbit > 0)
                _bits[cu - 1] = (cast(uint)man) << (kcbitUint - cbit);
            _sign = sign;
        }

        assert(isValid() == 0);
    }

    void setInt(int value) nothrow pure
    {
        if (value == int.min)
            setMinInt();
        else
        {
            _sign = value;
            _bits = null;
        }

        assert(isValid() == 0);
    }

    void setInt(uint value) nothrow pure
    {
        if (value <= int.max)
        {
            _sign = cast(int)value;
            _bits = null;
        }
        else
        {
            _sign = +1;
            _bits = [value];
        }

        assert(isValid() == 0);
    }

    void setInt(long value) nothrow pure
    {
        if (int.min < value && value <= int.max)
        {
            _sign = cast(int)value;
            _bits = null;
        }
        else if (value == int.min)
        {
            setMinInt();
        }
        else
        {
            ulong x = 0;
            if (value < 0)
            {
                _sign = -1;
                x = cast(ulong)(-value);
            }
            else
            {
                _sign = +1;
                x = cast(ulong)value;
            }

            if (x <= uint.max)
                _bits = [cast(uint)x];
            else
                _bits = [cast(uint)x, cast(uint)(x >> kcbitUint)];
        }

        assert(isValid() == 0);
    }

    void setInt(ulong value) nothrow pure
    {
        if (value <= int.max)
        {
            _sign = cast(int)value;
            _bits = null;
        }
        else if (value <= uint.max)
        {
            _sign = +1;
            _bits = [cast(uint)value];
        }
        else
        {
            _sign = +1;
            _bits = [cast(uint)value, cast(uint)(value >> kcbitUint)];
        }

        assert(isValid() == 0);
    }

    // We have to make a choice of how to represent int.MinValue. This is the one
    // value that fits in an int, but whose negation does not fit in an int.
    // We choose to use a large representation, so we're symmetric with respect to negation.
    void setMinInt() nothrow pure
    {
        _bits = [kuMaskHighBit];
        _sign = -1;
    }

    void setNegOne() nothrow pure
    {
        _bits = null;
        _sign = -1;
    }

    void setNegInts(scope const(uint)[] value, const(Flag!"negative") negative) nothrow pure
    {
        size_t len = value.length;

        // Try to conserve space as much as possible by checking for wasted leading uint[] entries
        // sometimes the uint[] has leading zeros from bit manipulation operations & and ^
        while (len > 0 && value[len - 1] == 0)
            len--;

        if (len == 0)
            setZero();
        // Values like (Int32.MaxValue+1) are stored as "0x80000000" and as such cannot be packed into _sign
        else if (len == 1 && value[0] < kuMaskHighBit)
        {
            this._bits = null;
            this._sign = negative ? -cast(int)value[0] : cast(int)value[0];
            // Although Int32.MinValue fits in _sign, we represent this case differently for negate
            if (this._sign == int.min)
                setMinInt();
        }
        else
        {
            this._sign = negative ? -1 : +1;
            this._bits = value[0..len].dup;
        }

        assert(isValid() == 0);
    }

    void setOne() nothrow pure
    {
        _bits = null;
        _sign = 1;
    }

    void setSignInts(scope const(uint)[] bits, int sign) nothrow pure scope
    {
        this._sign = sign;
        this._bits = bits.dup;

        assert(isValid() == 0);
    }

    ref BigInteger subtractOpAssign(scope const(uint)[] rightBits, int rightSign) nothrow pure return
    {
        const trivialLeft = _bits.length == 0;
        const trivialRight = rightBits.length == 0;

        if (trivialLeft && trivialRight)
            setInt(cast(long)_sign - rightSign);
        else if (trivialLeft)
        {
            auto resultBits = BigIntegerCalculator.subtract(rightBits, BigIntegerHelper.abs(_sign));
            setNegInts(resultBits[], toNegativeFlag(_sign >= 0));
        }
        else if (trivialRight)
        {
            auto resultBits = BigIntegerCalculator.subtract(_bits, BigIntegerHelper.abs(rightSign));
            setNegInts(resultBits[], toNegativeFlag(_sign < 0));
        }
        else if (BigIntegerCalculator.compare(_bits, rightBits) < 0)
        {
            auto resultBits = BigIntegerCalculator.subtract(rightBits, _bits);
            setNegInts(resultBits[], toNegativeFlag(_sign >= 0));
        }
        else
        {
            auto resultBits = BigIntegerCalculator.subtract(_bits, rightBits);
            setNegInts(resultBits[], toNegativeFlag(_sign < 0));
        }

        return this;
    }

private:
    // For values int.MinValue < n <= int.MaxValue, the value is stored in sign
    // and _bits is null. For all other values, sign is +1 or -1 and the bits are in _bits
    uint[] _bits;
    int _sign;
}

int compare(const(BigInteger) lhs, const(BigInteger) rhs) @nogc nothrow pure
{
    return lhs.opCmp(rhs);
}

BigInteger abs(const(BigInteger) value) nothrow pure
{
    auto result = BigInteger(value._bits, value._sign);
    if (result < BigInteger.zero)
        return -result;
    else
        return result;
}

BigInteger add(const(BigInteger) lhs, const(BigInteger) rhs) nothrow pure
{
    return lhs + rhs;
}

BigInteger subtract(const(BigInteger) lhs, const(BigInteger) rhs) nothrow pure
in
{
    assert(lhs.isValid() == 0);
    assert(rhs.isValid() == 0);
}
do
{
    auto result = BigInteger(lhs._bits, lhs._sign);
    if ((lhs._sign < 0) != (rhs._sign < 0))
        return result.addOpAssign(rhs._bits, -1 * rhs._sign);
    else
        return result.subtractOpAssign(rhs._bits, rhs._sign);
}

BigInteger multiply(const(BigInteger) lhs, const(BigInteger) rhs) nothrow pure
{
    return lhs * rhs;
}

BigInteger divide(const(BigInteger) dividend, const(BigInteger) divisor) nothrow pure
{
    return dividend / divisor;
}

BigInteger divRem(const(BigInteger) dividend, const(BigInteger) divisor, out BigInteger remainder) nothrow pure
in
{
    assert(dividend.isValid() == 0);
    assert(divisor.isValid() == 0);
}
do
{
    // remainder can be an alias to divident or divisor, so care to be taken
    // when setting remainder value

    const trivialDividend = dividend._bits.length == 0;
    const trivialDivisor = divisor._bits.length == 0;

    if (trivialDividend && trivialDivisor)
    {
        auto quotient = BigInteger(dividend._sign / divisor._sign);
        remainder = BigInteger(dividend._sign % divisor._sign);
        return quotient;
    }

    if (trivialDividend)
    {
        // The divisor is non-trivial and therefore the bigger one
        remainder = BigInteger(dividend._bits, dividend._sign);
        return BigInteger.zero();
    }

    if (trivialDivisor)
    {
        uint rest;
        auto resultBits = BigIntegerCalculator.divide(dividend._bits, BigIntegerHelper.abs(divisor._sign), rest);
        auto quotient = BigInteger(resultBits[], toNegativeFlag((dividend._sign < 0) ^ (divisor._sign < 0)));
        remainder = BigInteger(dividend._sign < 0 ? -1 * rest : rest);
        return quotient;
    }

    if (dividend._bits.length < divisor._bits.length)
    {
        remainder = BigInteger(dividend._bits, dividend._sign);
        return BigInteger.zero();
    }
    else
    {
        UIntTempArray rest;
        auto resultBits = BigIntegerCalculator.divide(dividend._bits, divisor._bits, rest);
        auto quotient = BigInteger(resultBits[], toNegativeFlag((dividend._sign < 0) ^ (divisor._sign < 0)));
        remainder = BigInteger(rest[], toNegativeFlag(dividend._sign < 0));
        return quotient;
    }
}

BigInteger remainder(const(BigInteger) dividend, const(BigInteger) divisor) nothrow pure
{
    return dividend % divisor;
}

double log(const(BigInteger) value, double baseValue) nothrow pure
{
    import std.math : isInfinity, log;

    if (value._sign < 0 || baseValue == cast(double)1.0)
        return double.nan;

    const isOne = value.isOne();

    //if (baseValue == double.PositiveInfinity)
    if (isInfinity(baseValue))
        return isOne ? cast(double)0.0 : double.nan;

    if (baseValue == cast(double)0.0 && !isOne)
        return double.nan;

    if (value._bits.length == 0)
        return BigIntegerCalculator.logBase(value._sign, baseValue);

    const ulong h = value._bits[$ - 1];
    const ulong m = value._bits.length > 1 ? value._bits[$ - 2] : 0;
    const ulong l = value._bits.length > 2 ? value._bits[$ - 3] : 0;

    // Measure the exact bit count
    const int c = BigIntegerHelper.cbitHighZero(cast(uint)h);
    const long b = (cast(long)value._bits.length) * 32 - c;

    // Extract most significant bits
    const ulong x = (h << 32 + c) | (m << c) | (l >> 32 - c);

    // Let v = value, b = bit count, x = v/2^b-64
    // log ( v/2^b-64 * 2^b-64 ) = log ( x ) + log ( 2^b-64 )
    return BigIntegerCalculator.logBase(x, baseValue) + (b - 64) / BigIntegerCalculator.logBase(baseValue, 2);
}

double log(const(BigInteger) value) nothrow pure
{
    import std.math : E;

    return log(value, E);
}

double log10(const(BigInteger) value) nothrow pure
{
    return log(value, 10);
}

bool modInverse(const(BigInteger) a, const(BigInteger) m, ref BigInteger d) nothrow pure @safe
{
    BigInteger x, y, gcd;
    extendedEuclid(a, m, x, y, gcd);
    if (gcd.isOne)
    {
        d = x.sign == -1 ? (m + x) % m : x % m;
        return true;
    }
    else
        return false;
}

BigInteger modPow(const(BigInteger) value, const(BigInteger) exponent, const(BigInteger) modulus) nothrow pure
in
{
    assert(exponent.sign >= 0);
    assert(value.isValid() == 0);
    assert(exponent.isValid() == 0);
    assert(modulus.isValid() == 0);
}
do
{
    const trivialValue = value._bits.length == 0;
    const trivialExponent = exponent._bits.length == 0;
    const trivialModulus = modulus._bits.length == 0;

    if (trivialModulus)
    {
        auto resultBits = trivialValue && trivialExponent
            ? BigIntegerCalculator.pow(BigIntegerHelper.abs(value._sign), BigIntegerHelper.abs(exponent._sign), BigIntegerHelper.abs(modulus._sign))
            : (trivialValue
               ? BigIntegerCalculator.pow(BigIntegerHelper.abs(value._sign), exponent._bits, BigIntegerHelper.abs(modulus._sign))
               : (trivialExponent
                  ? BigIntegerCalculator.pow(value._bits, BigIntegerHelper.abs(exponent._sign), BigIntegerHelper.abs(modulus._sign))
                  : BigIntegerCalculator.pow(value._bits, exponent._bits, BigIntegerHelper.abs(modulus._sign))));

        return value._sign < 0 && !exponent.isEven
            ? BigInteger.negOne() * BigInteger(resultBits)
            : BigInteger(resultBits);
    }
    else
    {
        auto resultBits = trivialValue && trivialExponent
            ? BigIntegerCalculator.pow(BigIntegerHelper.abs(value._sign), BigIntegerHelper.abs(exponent._sign), modulus._bits)
            : (trivialValue
               ? BigIntegerCalculator.pow(BigIntegerHelper.abs(value._sign), exponent._bits, modulus._bits)
               : (trivialExponent
                  ? BigIntegerCalculator.pow(value._bits, BigIntegerHelper.abs(exponent._sign), modulus._bits)
                  : BigIntegerCalculator.pow(value._bits, exponent._bits, modulus._bits)));

        return BigInteger(resultBits[], toNegativeFlag(value._sign < 0 && !exponent.isEven));
    }
}

BigInteger negate(const(BigInteger) value) nothrow pure
{
    auto result = BigInteger(value._bits, value._sign);
    return -result;
}

BigInteger pow(const(BigInteger) value, int exponent) nothrow pure
{
    auto result = BigInteger(value._bits, value._sign);
    return result ^^ exponent;
}

BigInteger sqrt(const(BigInteger) value) nothrow pure
{
    if (value <= 1)
        return value.dup;

	// Start with value known to be too large and repeat "z = ⌊(z + ⌊x/z⌋)/2⌋" until it stops getting smaller.
	// See Brent and Zimmermann, Modern Computer Arithmetic, Algorithm 1.13 (SqrtInt).
	// https://members.loria.fr/PZimmermann/mca/pub226.html
	// If x is one less than a perfect square, the sequence oscillates between the correct z and z+1;
	// otherwise it converges to the correct z and stays there.
	BigInteger z1 = 1, z2;
	z1 <<= (value.bitLength + 1) / 2; // must be ≥ √x
	while (true)
    {
		z2 = divide(value, z1);
		z2 += z1;
		z2 >>= 1;
		if (z2 >= z1)
			return z1; // z1 is answer.
        swap(z1, z2);
	}
}

inout(BigInteger) max(inout(BigInteger) lhs, inout(BigInteger) rhs) nothrow pure
{
    if (lhs < rhs)
        return rhs;
    else
        return lhs;
}

inout(BigInteger) min(inout(BigInteger) lhs, inout(BigInteger) rhs) nothrow pure
{
    if (lhs <= rhs)
        return lhs;
    else
        return rhs;
}

void swap(ref BigInteger a, ref BigInteger b) nothrow pure
{
    BigInteger t = a;
    a = b;
    b = t;
}

BigInteger greatestCommonDivisor(const(BigInteger) lhs, const(BigInteger) rhs) nothrow pure
in
{
    assert(lhs.isValid() == 0);
    assert(rhs.isValid() == 0);
}
do
{
    const trivialLeft = lhs._bits.length == 0;
    const trivialRight = rhs._bits.length == 0;

    if (trivialLeft && trivialRight)
    {
        return BigInteger(BigIntegerCalculator.gcd(BigIntegerHelper.abs(lhs._sign), BigIntegerHelper.abs(rhs._sign)));
    }

    if (trivialLeft)
    {
        return lhs._sign != 0
            ? BigInteger(BigIntegerCalculator.gcd(rhs._bits, BigIntegerHelper.abs(lhs._sign)))
            : BigInteger(rhs._bits, No.negative);
    }

    if (trivialRight)
    {
        return rhs._sign != 0
            ? BigInteger(BigIntegerCalculator.gcd(lhs._bits, BigIntegerHelper.abs(rhs._sign)))
            : BigInteger(lhs._bits, No.negative);
    }

    if (BigIntegerCalculator.compare(lhs._bits, rhs._bits) < 0)
        return greatestCommonDivisor(rhs._bits, lhs._bits);
    else
        return greatestCommonDivisor(lhs._bits, rhs._bits);
}

alias ProbablyPrimeTestRandomGen = BigInteger delegate(BigInteger /*limit*/) nothrow @safe;
enum ushort probablyPrimeTestIterations = 20;

bool isProbablyPrime(const(BigInteger) x, scope ProbablyPrimeTestRandomGen testRandomGen, const(ushort) testIterations = probablyPrimeTestIterations) nothrow
{
    version(profile) debug auto p = PerfFunction.create();

    if (x.sign == -1 || x.isZero || x.isOne)
        return false;

    if (x.isEven)
        return x == 2;

    // Check small prime number list
    static immutable ubyte[] ubytePrimes = [
        2, 3, 5, 7, 11, 13, 17, 19, 23, 29,
        31, 37, 41, 43, 47, 53, 59, 61, 67, 71,
        73, 79, 83, 89, 97, 101, 103, 107, 109, 113,
        127, 131, 137, 139, 149, 151, 157, 163, 167, 173,
        179, 181, 191, 193, 197, 199, 211, 223, 227, 229,
        233, 239, 241, 251,
        ];

    if (x < 255)
    {
        foreach (sp; ubytePrimes)
        {
            if (x == cast(uint)sp)
                return true;
        }
    }

	enum uint primesA = 3 * 5 * 7 * 11 * 13 * 17 * 19 * 23 * 37;
	enum uint primesB = 29 * 31 * 41 * 43 * 47 * 53;
	const rA = x % primesA;
	const rB = x % primesB;
	if (rA%3 == 0 || rA%5 == 0 || rA%7 == 0 || rA%11 == 0 || rA%13 == 0 || rA%17 == 0 || rA%19 == 0 || rA%23 == 0 || rA%37 == 0
		|| rB%29 == 0 || rB%31 == 0 || rB%41 == 0 || rB%43 == 0 || rB%47 == 0 || rB%53 == 0)
		return false;

	return isProbablyPrimeMillerRabin(x, testRandomGen, testIterations, false) && isProbablyPrimeLucas(x);
}


// Any below codes are private
private:

void extendedEuclid(const(BigInteger) a, const(BigInteger) b,
    out BigInteger x, out BigInteger y, out BigInteger gcd) nothrow pure
{
    version(profile) debug auto p = PerfFunction.create();

    BigInteger s = BigInteger.zero, oldS = BigInteger.one;
    BigInteger t = BigInteger.one, oldT = BigInteger.zero;
    BigInteger r = b.dup, oldR = a.dup;
    while (!r.isZero)
    {
        const quotient = oldR / r;

        auto old = oldR;
        oldR = r;
        r = old - quotient * r;

        old = oldS;
        oldS = s;
        s = old - quotient * s;

        old = oldT;
        oldT = t;
        t = old - quotient * t;
    }
    gcd = oldR;
    x = oldS;
    y = oldT;
}

BigInteger greatestCommonDivisor(const(uint)[] leftBits, const(uint)[] rightBits) nothrow pure
{
    assert(BigIntegerCalculator.compare(leftBits, rightBits) >= 0);

    // Short circuits to spare some allocations...
    if (rightBits.length == 1)
    {
        uint temp = BigIntegerCalculator.remainder(leftBits, rightBits[0]);
        return BigInteger(BigIntegerCalculator.gcd(rightBits[0], temp));
    }

    if (rightBits.length == 2)
    {
        auto tempBits = BigIntegerCalculator.remainder(leftBits, rightBits);

        ulong lhs = (cast(ulong)rightBits[1] << 32) | rightBits[0];
        ulong rhs = (cast(ulong)tempBits[1] << 32) | tempBits[0];

        return BigInteger(BigIntegerCalculator.gcd(lhs, rhs));
    }

    auto resultBits = BigIntegerCalculator.gcd(leftBits, rightBits);
    return BigInteger(resultBits[], No.negative);
}

// probablyPrimeMillerRabin reports whether n passes testIterations rounds of the
// Miller-Rabin primality test, using pseudo-randomly chosen bases.
// If isForced is true, one of the rounds is forced to use base 2.
// See Handbook of Applied Cryptography, p. 139, Algorithm 4.24.
// The number n is known to be non-zero.
bool isProbablyPrimeMillerRabin(const(BigInteger) n, scope ProbablyPrimeTestRandomGen testRandomGen, const(ushort) testIterations,
    const(bool) isForced) nothrow
{
    version(profile) debug auto p = PerfFunction.create();

	auto nm1 = n - 1;

	// determine q, k such that nm1 = q << k
	const k = nm1.trailingZeroBits();
	const q = nm1 >> k;

	auto nm3 = nm1 - 2;

	BigInteger x, y, quotient;

	foreach (i; 0..testIterations)
    {
        bool nextRandom = false;
		if (i == testIterations-1 && isForced)
			x = 2;
        else
			x = testRandomGen(nm3) + 2;

		y = modPow(x, q, n);
		if (y.isOne || y == nm1)
			continue;

		foreach (_; 1..k)
        {
            y *= y;
            quotient = divRem(y, n, y);
			if (y == nm1)
            {
                nextRandom = true;
                break;
            }
			if (y.isOne)
				return false;
		}

        if (!nextRandom)
		    return false;
	}

	return true;
}

bool isProbablyPrimeLucas(const(BigInteger) n) nothrow pure
{
    version(profile) debug auto pf = PerfFunction.create();

/* Already checked by caller -> no need
	// Discard 0 & 1
	if (n.isZero || n.isOne)
		return false;

	// Two is the only even prime.
	if (n.isEven)
        return n == 2;
*/

	// Baillie-OEIS "method C" for choosing D, P, Q,
	// as in https://oeis.org/A217719/a217719.txt:
	// try increasing P ≥ 3 such that D = P² - 4 (so Q = 1)
	// until Jacobi(D, n) = -1.
	// The search is expected to succeed for non-square n after just a few trials.
	// After more than expected failures, check whether n is square
	// (which would cause Jacobi(D, n) = 1 for all D not dividing n).
	uint p = 3;
	BigInteger d = BigInteger.one;
	BigInteger t1; // temp
	for (; ; p++)
    {
		if (p > 10_000)
        {
			// This is widely believed to be impossible.
			// If we get a report, we'll want the exact number n.
			// panic("math/big: internal error: cannot find (D/n) = -1 for " + intN.String())
            return false;
		}

		d = p*p - 4;
		const j = jacobi(d, n);
		if (j == -1)
			break;

		if (j == 0)
        {
			// d = p²-4 = (p-2)(p+2).
			// If (d/n) == 0 then d shares a prime factor with n.
			// Since the loop proceeds in increasing p and starts with p-2==1,
			// the shared prime factor must be p+2.
			// If p+2 == n, then n is prime; otherwise p+2 is a proper factor of n.
			return n == p+2;
		}

		if (p == 40)
        {
			// We'll never find (d/n) = -1 if n is a square.
			// If n is a non-square we expect to find a d in just a few attempts on average.
			// After 40 attempts, take a moment to check if n is indeed a square.
			t1 = sqrt(n);
			t1 = t1 * t1;
			if (t1 == n)
				return false;
		}
	}

	// Grantham definition of "extra strong Lucas pseudoprime", after Thm 2.3 on p. 876
	// (D, P, Q above have become Δ, b, 1):
	//
	// Let U_n = U_n(b, 1), V_n = V_n(b, 1), and Δ = b²-4.
	// An extra strong Lucas pseudoprime to base b is a composite n = 2^r s + Jacobi(Δ, n),
	// where s is odd and gcd(n, 2*Δ) = 1, such that either (i) U_s ≡ 0 mod n and V_s ≡ ±2 mod n,
	// or (ii) V_{2^t s} ≡ 0 mod n for some 0 ≤ t < r-1.
	//
	// We know gcd(n, Δ) = 1 or else we'd have found Jacobi(d, n) == 0 above.
	// We know gcd(n, 2) = 1 because n is odd.
	//
	// Arrange s = (n - Jacobi(Δ, n)) / 2^r = (n+1) / 2^r.
	BigInteger s = n + 1;
	const r = s.trailingZeroBits;
	s >>= r;
	BigInteger nm2 = n - 2; // n-2

	// We apply the "almost extra strong" test, which checks the above conditions
	// except for U_s ≡ 0 mod n, which allows us to avoid computing any U_k values.
	// Jacobsen points out that maybe we should just do the full extra strong test:
	// "It is also possible to recover U_n using Crandall and Pomerance equation 3.13:
	// U_n = D^-1 (2V_{n+1} - PV_n) allowing us to run the full extra-strong test
	// at the cost of a single modular inversion. This computation is easy and fast in GMP,
	// so we can get the full extra-strong test at essentially the same performance as the
	// almost extra strong test."

	// Compute Lucas sequence V_s(b, 1), where:
	//
	//	V(0) = 2
	//	V(1) = P
	//	V(k) = P V(k-1) - Q V(k-2).
	//
	// (Remember that due to method C above, P = b, Q = 1.)
	//
	// In general V(k) = α^k + β^k, where α and β are roots of x² - Px + Q.
	// Crandall and Pomerance (p.147) observe that for 0 ≤ j ≤ k,
	//
	//	V(j+k) = V(j)V(k) - V(k-j).
	//
	// So in particular, to quickly double the subscript:
	//
	//	V(2k) = V(k)² - 2
	//	V(2k+1) = V(k) V(k+1) - P
	//
	// We can therefore start with k=0 and build up to k=s in log₂(s) steps.
	BigInteger natP = p;
	BigInteger vk1 = p;
	BigInteger vk = 2;
	BigInteger t2; // temp
	for (ptrdiff_t i = s.bitLength; i >= 0; i--)
    {
		if (s.bitSet(i))
        {
			// k' = 2k+1
			// V(k') = V(2k+1) = V(k) V(k+1) - P.
			t1 = vk * vk1;
			t1 += n;
			t1 -= natP;
			t2 = divRem(t1, n, vk);
			// V(k'+1) = V(2k+2) = V(k+1)² - 2.
			t1 = vk1 * vk1;
			t1 += nm2;
            t2 = divRem(t1, n, vk1);
		}
        else
        {
			// k' = 2k
			// V(k'+1) = V(2k+1) = V(k) V(k+1) - P.
			t1 = vk * vk1;
			t1 += n;
			t1 -= natP;
            t2 = divRem(t1, n, vk1);
			// V(k') = V(2k) = V(k)² - 2
			t1 = vk * vk;
			t1 += nm2;
            t2 = divRem(t1, n, vk);
		}
	}

	// Now k=s, so vk = V(s). Check V(s) ≡ ±2 (mod n).
	if (vk == 2 || vk == nm2)
    {
		// Check U(s) ≡ 0.
		// As suggested by Jacobsen, apply Crandall and Pomerance equation 3.13:
		//
		//	U(k) = D⁻¹ (2 V(k+1) - P V(k))
		//
		// Since we are checking for U(k) == 0 it suffices to check 2 V(k+1) == P V(k) mod n,
		// or P V(k) - 2 V(k+1) == 0 mod n.
		t1 = vk * natP;
		t2 = vk1 << 1;
		if (t1 < t2)
            swap(t1, t2);
		t1 -= t2;
		BigInteger t3 = vk1; // steal vk1, no longer needed below
		vk1 = 0;
		//_ = vk1
        t2 = divRem(t1, n, t3);
		if (t3 == 0)
			return true;
	}

	// Check V(2^t s) ≡ 0 mod n for some 0 ≤ t < r-1.
	for (int t = 0; t < r-1; t++)
    {
		if (vk == 0) // vk == 0
			return true;
		// Optimization: V(k) = 2 is a fixed point for V(k') = V(k)² - 2,
		// so if V(k) = 2, we can stop: we will never find a future V(k) == 0.
		if (vk == 2) // vk == 2
			return false;
		// k' = 2k
		// V(k') = V(2k) = V(k)² - 2
		t1 = vk * vk;
		t1 -= 2;
        t2 = divRem(t1, n, vk);
	}

	return false;
}

// Jacobi returns the Jacobi symbol (x/y), either +1, -1, or 0.
int jacobi(const(BigInteger) x, const(BigInteger) y) nothrow pure
in
{
    assert(x != 0);
    assert(!y.isEven);
}
do
{
    version(profile) debug auto p = PerfFunction.create();

	// We use the formulation described in chapter 2, section 2.4,
	// "The Yacas Book of Algorithms":
	// http://yacas.sourceforge.net/Algo.book.pdf

	BigInteger a = x.dup, b = y.dup;
	int j = 1;
	if (b.sign == -1)
    {
		if (a.sign == -1)
			j = -1;
		b = abs(b);
	}

	while (true)
    {
		if (b == 1)
			return j;

		if (a == 0)
			return 0;

        a %= b;
		if (a == 0)
			return 0;

		// a > 0
		// handle factors of 2 in 'a'
		const s = a.trailingZeroBits;
		if ((s&1) != 0)
        {
			const bmod8 = b.bitSets(0) & 7;
			if (bmod8 == 3 || bmod8 == 5)
				j = -j;
		}
		const c = a >> s; // a = 2^s*c

		// swap numerator and denominator
		if ((b.bitSets(0)&3) == 3 && (c.bitSets(0)&3) == 3)
			j = -j;
        a = b;
        b = c;
	}
}

version(unittest)
string toStringSafe(const(BigInteger) n,
    string format = null,
    char separator = '_') nothrow @safe
{
    scope (failure) assert(0, "Assume nothrow failed");

    return format.length ? n.toString(format, separator) : n.toString();
}

nothrow unittest // BigInteger.toString('%d')
{
    import std.conv : to;

    static void check(T)(T value, string checkedValue,
        string format = null,
        char separator = '_',
        uint line = __LINE__) nothrow @safe
    {
        auto v = BigInteger(value);
        auto s = toStringSafe(v, format, separator);
        assert(s == checkedValue, "from line: " ~ line.to!string() ~ ": " ~ s ~ " ? " ~ checkedValue);
    }

    check(0, to!string(0));
    check(1, to!string(1));
    check(-1, to!string(-1));
    check(int.min, to!string(int.min));
    check(int.max, to!string(int.max));
    check(uint.min, to!string(uint.min));
    check(uint.max, to!string(uint.max));
    check(long.min, to!string(long.min));
    check(long.max, to!string(long.max));
    check(ulong.min, to!string(ulong.min));
    check(ulong.max, to!string(ulong.max));

    check(cast(long)(uint.max + 1), to!string(cast(long)(uint.max + 1)));
    check(-(cast(long)uint.max), to!string(-(cast(long)uint.max)));

    check(-12345678, "-12_345_678", "%,3d");
    check(uint.max, "42_9496_7295", "%,4d");
}

unittest // BigInteger.toString('%X')
{
    import std.conv : to;

    static void check(T)(T value, string checkedValue,
        string format = "%X",
        char separator = '_',
        uint line = __LINE__)
    {
        auto v = BigInteger(value);
        auto s = toStringSafe(v, format, separator);
        assert(s == checkedValue, "from line: " ~ line.to!string() ~ ": " ~ s ~ " ? " ~ checkedValue);
    }

    check(0, to!string(0, 16));
    check(1, to!string(1, 16));
    check(-1, "F"); //check(-1, to!string(-1, 16));
    check(int.min, to!string(int.min, 16));
    check(int.max, to!string(int.max, 16));
    check(uint.min, to!string(uint.min, 16));
    check(uint.max, "0FFFFFFFF"); //check(uint.max, to!string(uint.max, 16));
    check(long.min, to!string(long.min, 16));
    check(long.max, to!string(long.max, 16));
    check(ulong.min, to!string(ulong.min, 16));
    check(ulong.max, "0FFFFFFFFFFFFFFFF"); //check(ulong.max, to!string(ulong.max, 16));

    check(cast(long)(uint.max + 1), to!string(cast(long)(uint.max + 1), 16));
    check(-(cast(long)uint.max), "F00000001"); //check(-(cast(long)uint.max), to!string(-(cast(long)uint.max), 16));

    check(-12345678, "f_439_eb2", "%,3x");
    check(uint.max, "0_FFFF_FFFF", "%,4X");
}

unittest // parse integer
{
    import std.conv : to;

    static void check(string value,
        uint line = __LINE__) @safe
    {
        auto v = BigInteger(value);
        auto s = toStringSafe(v);
        assert(s == value, "from line: " ~ line.to!string() ~ ": " ~ s ~ " ? " ~ value);
    }

    check(to!string(0));
    check(to!string(1));
    check(to!string(-1));
    check(to!string(int.min));
    check(to!string(int.max));
    check(to!string(uint.min));
    check(to!string(uint.max));
    check(to!string(long.min));
    check(to!string(long.max));
    check(to!string(ulong.min));
    check(to!string(ulong.max));

    check("9223372036854775807");
    check("90123123981293054321");
    check("1234567890098765432112345678900987654321123456789009876543211234567890");
    check("-9223372036854775808");
    check("-1234567890098765432112345678900987654321123456789009876543211234567890");
}

unittest // parse hex
{
    import std.conv : to;

    static void check(string value,
        uint line = __LINE__)
    {
        auto v = BigInteger("0x" ~ value);
        auto s = toStringSafe(v, "%X");
        assert(s == value, "from line: " ~ line.to!string() ~ ": " ~ s ~ " ? " ~ value);
    }

    check(to!string(0, 16));
    check(to!string(1, 16));
    check("F"); //check(-1, to!string(-1, 16));
    check(to!string(int.min, 16));
    check(to!string(int.max, 16));
    check(to!string(uint.min, 16));
    check("0FFFFFFFF"); //check(uint.max, to!string(uint.max, 16));
    check(to!string(long.min, 16));
    check(to!string(long.max, 16));
    check(to!string(ulong.min, 16));
    check("0FFFFFFFFFFFFFFFF"); //check(ulong.max, to!string(ulong.max, 16));

    check(to!string(cast(long)(uint.max + 1), 16));
    check("F00000001"); //check(-(cast(long)uint.max), to!string(-(cast(long)uint.max), 16));

    check("F439EB2");
}

unittest // Parse failed
{
    import std.exception : assertThrown;

    assertThrown!ConvException(BigInteger(""));
    assertThrown!ConvException(BigInteger("123 456"));
    assertThrown!ConvException(BigInteger("0x"));
    assertThrown!ConvException(BigInteger("0x0  abc"));
}

unittest // compare
{
    auto x = BigInteger("12345");
    auto x2 = BigInteger("12345");
    assert(x == x);
    assert(x2 == x);
    assert(x2 >= x);

    int z = 12345;
    assert(x == z);

    int w = 54321;
    assert(w != x);

    auto y = BigInteger("12399");
    assert(y != x);
    assert(y > x);
    assert(x < y);
    assert(x <= y);
}

unittest // cast
{
    import std.conv : to, ConvException;
    import std.exception : assertThrown;

    // Non-zero values are regarded as true
    auto x = BigInteger("1");
    assert(x);

    auto y = BigInteger("10");
    assert(y);

    auto n = BigInteger("-1");
    assert(n);

    // Zero value is regarded as false
    auto z = BigInteger("0");
    assert(!z);

    assert(to!int(z) == 0);
    assert(to!int(BigInteger("0")) == 0);

    assert(to!ubyte(BigInteger("0")) == 0);
    assert(to!ubyte(BigInteger("255")) == 255);
    assertThrown!ConvException(to!ubyte(BigInteger("256")));
    assertThrown!ConvException(to!ubyte(BigInteger("-1")));

    assert(to!byte(BigInteger("-1")) == -1);
    assert(to!byte(BigInteger("-128")) == -128);
    assert(to!byte(BigInteger("127")) == 127);
    assertThrown!ConvException(to!byte(BigInteger("-129")));
    assertThrown!ConvException(to!byte(BigInteger("128")));

    assert(BigInteger("0").to!uint == 0);
    assert(BigInteger("4294967295").to!uint == uint.max);
    assertThrown!ConvException(BigInteger("4294967296").to!uint);
    assertThrown!ConvException(BigInteger("-1").to!uint);

    assert(BigInteger("-1").to!int == -1);
    assert(BigInteger("-2147483648").to!int == int.min);
    assert(BigInteger("2147483647").to!int == int.max);
    assertThrown!ConvException(BigInteger("-2147483649").to!int);
    assertThrown!ConvException(BigInteger("2147483648").to!int);

    assert(BigInteger("0").to!ulong == 0);
    assert(BigInteger("18446744073709551615").to!ulong == ulong.max);
    assertThrown!ConvException(BigInteger("18446744073709551616").to!ulong);
    assertThrown!ConvException(BigInteger("-1").to!ulong);

    assert(BigInteger("-1").to!long == -1);
    assert(BigInteger("-9223372036854775808").to!long == long.min);
    assert(BigInteger("9223372036854775807").to!long == long.max);
    assertThrown!ConvException(BigInteger("-9223372036854775809").to!long);
    assertThrown!ConvException(BigInteger("9223372036854775808").to!long);
}

unittest // operator + - ~
{
    import std.conv : to;

    static void check(const(BigInteger) value, string checkedValue,
        uint line = __LINE__)
    {
        auto s = toStringSafe(value, "%,3d", '_');
        assert(s == checkedValue, "from line: " ~ line.to!string() ~ ": " ~ s ~ " ? " ~ checkedValue);
        assert(value == BigInteger(checkedValue), "from line: " ~ line.to!string() ~ ": " ~ s ~ " ? " ~ checkedValue);
    }

    BigInteger v, x;

    v = BigInteger.zero;
    v += 1;
    check(v, "1");

    v = BigInteger.zero;
    v -= BigInteger.one;
    check(v, "-1");

    v = BigInteger.one;
    v += BigInteger.one;
    check(v, "2");

    v = BigInteger.one;
    v -= 1;
    check(v, "0");

    v = BigInteger("1_000_000_000");
    v += 12345;
    check(v, "1_000_012_345");

    v = BigInteger("1_000_000_000");
    v -= 12345;
    check(v, "999_987_655");

    v = BigInteger("0");
    v += BigInteger("1_000_000_000");
    check(v, "1_000_000_000");

    v = BigInteger("0");
    v -= BigInteger("1_000_000_000");
    check(v, "-1_000_000_000");

    v = BigInteger.zero;
    v += int.max;
    check(v, "2_147_483_647");

    v = BigInteger.zero;
    v -= int.max;
    check(v, "-2_147_483_647");

    v = BigInteger.zero;
    v += uint.max;
    check(v, "4_294_967_295");

    v = BigInteger.zero;
    v -= uint.max;
    check(v, "-4_294_967_295");

    v = BigInteger.zero;
    v += long.max;
    check(v, "9_223_372_036_854_775_807");

    v = BigInteger.zero;
    v -= long.max;
    check(v, "-9_223_372_036_854_775_807");

    v = BigInteger.zero;
    v += ulong.max;
    check(v, "18_446_744_073_709_551_615");

    v = BigInteger.zero;
    v -= ulong.max;
    check(v, "-18_446_744_073_709_551_615");

    v = BigInteger.one;
    v += int.max;
    check(v, "2_147_483_648");

    v = BigInteger.one;
    v -= int.max;
    check(v, "-2_147_483_646");

    v = BigInteger.one;
    v += uint.max;
    check(v, "4_294_967_296");

    v = BigInteger.one;
    v -= uint.max;
    check(v, "-4_294_967_294");

    v = BigInteger.one;
    v += long.max;
    check(v, "9_223_372_036_854_775_808");

    v = BigInteger.one;
    v -= long.max;
    check(v, "-9_223_372_036_854_775_806");

    v = BigInteger.one;
    v += ulong.max;
    check(v, "18_446_744_073_709_551_616");

    v = BigInteger.one;
    v -= ulong.max;
    check(v, "-18_446_744_073_709_551_614");

    v = BigInteger.one;
    x = --v;
    check(v, "0");
    check(x, "0");

    v = BigInteger.one;
    x = v--;
    check(v, "0");
    check(x, "1");

    v = BigInteger.one;
    x = -v;
    check(v, "-1");
    check(x, "-1");

    v = BigInteger.one;
    x = ++v;
    check(v, "2");
    check(x, "2");

    v = BigInteger.one;
    x = v++;
    check(v, "2");
    check(x, "1");

    v = BigInteger("937_123_857_476_363");
    x = ~v;
    check(x, "-937_123_857_476_364");

    v = BigInteger("9");
    x = ~v;
    check(x, "-10");

    v = BigInteger("-127");
    x = ~v;
    check(x, "126");
}

unittest // operator * / %
{
    import std.conv : to;

    static void check(const(BigInteger) value, string checkedValue,
        uint line = __LINE__)
    {
        auto s = toStringSafe(value, "%,3d", '_');
        assert(s == checkedValue, "from line: " ~ line.to!string() ~ ": " ~ s ~ " ? " ~ checkedValue);
        assert(value == BigInteger(checkedValue), "from line: " ~ line.to!string() ~ ": " ~ s ~ " ? " ~ checkedValue);
    }

    BigInteger v, x;

    v = BigInteger("123") * BigInteger("456");
    check(v, "56_088");

    v = BigInteger("123") * BigInteger("-456");
    check(v, "-56_088");

    v = BigInteger("9_588_669_891_916_142") * BigInteger("7_452_469_135_154_800");
    check(v, "71_459_266_416_693_160_362_545_788_781_600");

    x = BigInteger("7_452_469_135_154_800") * BigInteger("9_588_669_891_916_142");
    check(x, v.toString("%,3d", '_'));

    v = BigInteger("-9_588_669_891_916_142") * BigInteger("7_452_469_135_154_800");
    check(v, "-71_459_266_416_693_160_362_545_788_781_600");

    v = BigInteger.zero * BigInteger("456");
    check(v, "0");

    v = BigInteger.one;
    v *= BigInteger("456");
    check(v, "456");

    v = BigInteger("456") / BigInteger("123");
    check(v, "3");

    v = BigInteger("-456") / BigInteger("123");
    check(v, "-3");

    v = BigInteger("456") % BigInteger("123");
    check(v, "87");

    v = BigInteger("-456") % BigInteger("123");
    check(v, "-87");

    v = BigInteger("456") % BigInteger("-123");
    check(v, "87");

    v = BigInteger("9_588_669_891_916_142") / BigInteger("7_452_469_135");
    check(v, "1_286_643");

    v = BigInteger("-9_588_669_891_916_142") / BigInteger("-7_452_469_135");
    check(v, "1_286_643");

    v = BigInteger("9_588_669_891_916_142") / BigInteger("-7_452_469_135");
    check(v, "-1_286_643");

    v = BigInteger("9_588_669_891_916_142") % BigInteger("7_452_469_135");
    check(v, "2_646_652_337");

    v = BigInteger("-9_588_669_891_916_142") % BigInteger("-7_452_469_135");
    check(v, "-2_646_652_337");

    v = BigInteger("9_588_669_891_916_142") % BigInteger("-7_452_469_135");
    check(v, "2_646_652_337");
}

unittest // operator << >> ^^
{
    import std.conv : to;

    static void check(const(BigInteger) value, string checkedValue,
        uint line = __LINE__)
    {
        auto s = toStringSafe(value, "%,3d", '_');
        assert(s == checkedValue, "from line: " ~ line.to!string() ~ ": " ~ s ~ " ? " ~ checkedValue);
        assert(value == BigInteger(checkedValue), "from line: " ~ line.to!string() ~ ": " ~ s ~ " ? " ~ checkedValue);
    }

    BigInteger v, x;

    v = BigInteger("37_123_857_476_363");
    v ^^= 11;
    check(v, "184_579_754_300_582_061_788_234_378_664_824_134_403_613_841_989_382_007_432_894_888_475_104_193_069_685_183_864_658_233_409_338_396_700_941_735_582_626_978_202_603_350_759_794_560_967_874_473_839_187");

    v = BigInteger("937_123_857_476_363");
    v >>= 33;
    check(v, "109_095");

    v = BigInteger("937_123_857_476_363");
    v <<= 33;
    check(v, "8_049_832_640_324_688_356_048_896");
    x = v >> 33;
    check(x, "937_123_857_476_363");
}

unittest // multiply
{
    import std.conv : to;

    static void check(const(BigInteger) value, string checkedValue,
        uint line = __LINE__)
    {
        auto s = toStringSafe(value);
        assert(s == checkedValue, "from line: " ~ line.to!string() ~ ": " ~ s ~ " ? " ~ checkedValue);
        assert(value == BigInteger(checkedValue), "from line: " ~ line.to!string() ~ ": " ~ s ~ " ? " ~ checkedValue);
    }

    BigInteger v, x;

    v = multiply(BigInteger("241127122100380210001001124020210001001100000200003101000062221012075223052000021042250111300200000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"),
            BigInteger("70020000000050041832100040114001011000002200722143200000014102001132330110410406020210020045721000160014200000101224530010000111021520000000012000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"));
    check(v, "16883721089480688747229011802283756823349870758229387365814728471518346136944894862961035756393632618073413910091006778604956808730652275328822700182498926542563654351871390166691461743896850906716336187966456064270200717632811001335602400000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000");
}

unittest // Compile time construct
{
    enum b = BigInteger("0x123");
    enum b2 = BigInteger("291");
    assert(b == b2);
}

unittest
{
    auto b = BigInteger("148607213746748888433115898774488125434956021884951532398437063594981690133657747515764650183781235940657054608881977858196568765979755791042029635107364589767082851027596594595936524517171068826751265581664247659551324634745120309986368437908665195084578221129443657946400665125676458397984792168049771254957");

    assert(bytesToHexs(b.toBytes()) == "AD9487795C33B20BE5A7D7011A954790747A3E248DBA651EBDBEFBC61872A6C9ACB9B8F6DB3381DF0433652892049293D5D28124ED3B9A5FB410A2A071FACEC5C7E980DC18EF281A53421C83B56B7A97DDD098D3F0436FD08F0D727272827BB78BA005F3F16902A3200B6CF7009F8A69DD895E87F4673D8AEB96E68B9AAA9FD300");
}

unittest
{
    import std.conv : to;

    static void check(string caseNumber, const(BigInteger) value, string checkedValue,
        uint line = __LINE__)
    {
        auto s = toStringSafe(value);
        assert(s == checkedValue, caseNumber ~ " from line s: " ~ line.to!string() ~ ": " ~ s ~ " ? " ~ checkedValue);
        assert(value == BigInteger(checkedValue), caseNumber ~ " from line b: " ~ line.to!string() ~ ": " ~ s ~ " ? " ~ checkedValue);
    }

    auto N = BigInteger("161854874649776085868045952190159031555772097014435707776279513538616175047026058065927714606879676219064271341818754038806823814541886861147177045257236811627035155212310813305487929926508522581710604504792711726648563877865328333166885998671854094528177699206377434633696300213499023964016345755132798642663");
    auto g = BigInteger("2");
    auto k = BigInteger("1277432915985975349439481660349303019122249719989");

    // Calculate of public key
    check("Case 1", modPow(g, BigInteger("166877457487623127448749043969556209859"), N), "81888951733654370650300744105990642651311279993652657578339178478664726661342444540489461007187483129056870525865748047152232526957313096191487005597426852739926780802853155564902296695527785924860736461542137894705369444941892309212244889473155929501415954448777042653808745933663108253612593345044477819653");
    check("Case 2", modPow(g, BigInteger("18033386923759210106954361155040376679"), N), "373827886597641888664350759247757788432290172556909096299291898433813565406963636754236737874236053504540992786593986500223152409020327904309450266904698735698428769898122519283675167818158909039196829582386987604681517299882989262228398952941211107855769819963774047652979435027400791845211693289870461111");
    check("Case 3", modPow(g, BigInteger("311072220313260656089193972478315100026"), N), "8415608665477072513378877367298986919740598906750861435498569390984098574780748451985159837056253716735071751719993664503752744018532933556862387781909156957206504437165096086270912904968696796514418362832160816585806192584301180472217873452760694808258323516174851040038593288145665601563143735699394542529");

    // Calculate session key
    void calculateSessionKey(string caseNumber,
        BigInteger u, BigInteger x, BigInteger serverPublicKey, BigInteger privateKey,
        string expectedGX, string expectedKGX, string expectedBKGX, string expectedDIFF,
        string expectedUX, string expectedAUX, string expectedSessionKey) @safe
    {
        auto gx = modPow(g, x, N);
        check(caseNumber, gx, expectedGX);

        BigInteger kgx;
        divRem(k * gx, N, kgx);
        check(caseNumber, kgx, expectedKGX);

        auto bkgx = serverPublicKey - kgx;
        if (bkgx < 0)
            bkgx = bkgx + N;
        check(caseNumber, bkgx, expectedBKGX);

        BigInteger diff;
        divRem(bkgx, N, diff);
        check(caseNumber, diff, expectedDIFF);

        BigInteger ux;
        divRem(u * x, N, ux);
        check(caseNumber, ux, expectedUX);

        BigInteger aux;
        divRem(privateKey + ux, N, aux);
        check(caseNumber, aux, expectedAUX);

        check(caseNumber, modPow(diff, aux, N), expectedSessionKey);
    }
    calculateSessionKey("Case 1",
        BigInteger("1086026541129304727389343222464000291394179491805"),
        BigInteger("1118094570933656353507431961291973646064838772098"),
        BigInteger("70873969751381248603539753132354522841659480325927929017846443390924759619015467102001617317896400723998166075310608877954113108888608672811991220339757680187570509114581759602805463386075600146845035828894210146506697505773839421288909468537491942261654135926323092388946788622062954854815299705945731149953"),
        BigInteger("331000129387001149249428891683996999459"),
        "113271415817112435858321448314858771877637356308146576713688281565270963987653348260863879518473295634935229062825019058759212775134634358580966248580783344381965663984818721847402147327302452073611377816114839885815113874023501471638461328602568861268406286641672558520716094680121021057095413101043799821159",
        "104395973268591681080532285488846125611402389393247008569986395114027813104211104082519857580693964519028976637398372094706733545397241014277722519243887381447686665467242264691106440936642805948588408554178868784213152649135261529746895908851597190577648166185061141282781386125777959217328263037206368478258",
        "128332871132565653391053419833667428786029187947116628224139561815513121561830421085409474344082112424033460779730990822054203378033254519681445746353107110366918998859650308217186952375941316779967231779508053088942108734503906224708899558357748846212183668947639385739861702709784019601503382423872161314358",
        "128332871132565653391053419833667428786029187947116628224139561815513121561830421085409474344082112424033460779730990822054203378033254519681445746353107110366918998859650308217186952375941316779967231779508053088942108734503906224708899558357748846212183668947639385739861702709784019601503382423872161314358",
        "1214280379526532863772430663883675531759709533217088643339364523216259817908845765782849853656890",
        "1214280379526532863772430663883675531759709533217088643339695523345646819058095194674533850656349",
        "34808899877002258396130672881087821930299709196141357872453912158826187403066821514234540881340776732057470124699792709388824013382760003684918087604384060917336182348467151292491240855203670824695958684332890106101915025067375113895070065469764163999096986688956418068229340924325333080432384744839845041097"
       );
    calculateSessionKey("Case 2",
        BigInteger("1447007608869390416300419587573061593931690851325"),
        BigInteger("1118094570933656353507431961291973646064838772098"),
        BigInteger("34879121201903518996454336628469081767565914760423430616387329608596458426975896194154426868171505280610912668129263343854371055957136910630089343891609326157808316380473720452274706215536129353537429831381287202882184858173013520376413734886994896593457050375170031740635578041862858862496190839715601710105"),
        BigInteger("81406933379696834572834690266813219248"),
        "113271415817112435858321448314858771877637356308146576713688281565270963987653348260863879518473295634935229062825019058759212775134634358580966248580783344381965663984818721847402147327302452073611377816114839885815113874023501471638461328602568861268406286641672558520716094680121021057095413101043799821159",
        "104395973268591681080532285488846125611402389393247008569986395114027813104211104082519857580693964519028976637398372094706733545397241014277722519243887381447686665467242264691106440936642805948588408554178868784213152649135261529746895908851597190577648166185061141282781386125777959217328263037206368478258",
        "92338022583087923783968003329781987711935622381612129822680448033184820369790850177562283894357216980646207372549645287954461325101782757499543869904958756337156806125542269066656195205401845986659625781995130145317596086903080323796403824707251800543986583396486325091550492129583923609184273557642031874510",
        "92338022583087923783968003329781987711935622381612129822680448033184820369790850177562283894357216980646207372549645287954461325101782757499543869904958756337156806125542269066656195205401845986659625781995130145317596086903080323796403824707251800543986583396486325091550492129583923609184273557642031874510",
        "1617891351576557111270042047976285010216885631285044758968319641361836344744257703838853276329850",
        "1617891351576557111270042047976285010216885631285044758968401048295216041578830538529120089549098",
        "49414943413164726926570107903536527598327170216944765407782963085841075455402607092375427385298581964120982545794601107676381850568158700818424451607480994693763516345062519218281138727880103791054298687847707398055830933746701402329739384917721470440280266075919964919707717454459052173298461750909962503931"
       );
    calculateSessionKey("Case 3",
        BigInteger("496560186623772534645023109040214532923962576006"),
        BigInteger("1118094570933656353507431961291973646064838772098"),
        BigInteger("101430969384713884480369322209374893179789588604166057636330615647994942778436289301880648582455718629047298886939262339117806321025429254063710947844434000864351610451093551225055733847674918393831555963544026061504626414016833655225250118822142801844756776379474766520442506924096221783830329091194542649196"),
        BigInteger("104491947522532296711270077998991262627"),
        "113271415817112435858321448314858771877637356308146576713688281565270963987653348260863879518473295634935229062825019058759212775134634358580966248580783344381965663984818721847402147327302452073611377816114839885815113874023501471638461328602568861268406286641672558520716094680121021057095413101043799821159",
        "104395973268591681080532285488846125611402389393247008569986395114027813104211104082519857580693964519028976637398372094706733545397241014277722519243887381447686665467242264691106440936642805948588408554178868784213152649135261529746895908851597190577648166185061141282781386125777959217328263037206368478258",
        "158889870765898289267882988910687799124159296225354756842623734072583304721251243285288505608641430329082593591359644283217896590170075100933165473857783431043700100196162099839437222837540635026953751914157869003940037642746900458645240208642399705795286309400791059871357421011817286530518411809120972813601",
        "158889870765898289267882988910687799124159296225354756842623734072583304721251243285288505608641430329082593591359644283217896590170075100933165473857783431043700100196162099839437222837540635026953751914157869003940037642746900458645240208642399705795286309400791059871357421011817286530518411809120972813601",
        "555201248805843277041858572938629561136620975361906949088120120448334395467308264904734037080588",
        "555201248805843277041858572938629561136620975361906949088224612395856927764019534982733028343215",
        "60200670310998898545503783314801977811021352353243349406037365576304366931392344178261453913145139672906516808635493851722658566136188757905752432773862614766677724694879760037219343621851028306075876131499437013356802062182895781455681614269981911929900326407523213579183069256957487352485956427189499088426"
       );
}

unittest // std.conv.to template
{
    import std.conv : to;

    const a = to!BigInteger("1234");
    assert(a == 1234);
}

unittest // constructors
{
    auto a = BigInteger("-903145792771643190182");
    auto b = BigInteger("0xCF0A55968BB1A7545A");
    assert(a == b);

    a = BigInteger("3145792771643190182");
    b = BigInteger("0x2BA819DBD2C8ABA6");
    assert(a == b);
}

unittest // modInverse
{
    BigInteger d;

    assert(modInverse(BigInteger(65537), BigInteger("57896044618658097711785492504343953926634992332820282019728792003956564819949"), d));
    assert(d == BigInteger("34424722930556307912062759539027956675055501185976482746308063640541669864409"));

    assert(modInverse(BigInteger(53), BigInteger(120), d));
    assert(d == BigInteger(77));

    assert(modInverse(BigInteger(65537), BigInteger("1034776851837418226012406113933120080"), d));
    assert(d == BigInteger("568411228254986589811047501435713"));

    //assert(modInverse(BigInteger(), BigInteger(), d));
    //assert(d == BigInteger());
}

unittest // BigInteger.bitLength
{
    assert(BigInteger(0).bitLength == 0);
    assert(BigInteger(1).bitLength == 1);
    assert(BigInteger(-1).bitLength == 1);
    assert(BigInteger(2).bitLength == 2);
    assert(BigInteger(4).bitLength == 3);

    auto options = defaultParseBigIntegerOptions!char();
    options.flags |= NumericLexerFlag.unsigned;

    assert(BigInteger("0xabc", options).bitLength == 12);
    assert(BigInteger("0x8000", options).bitLength == 16);
    assert(BigInteger("0x8000_0000", options).bitLength == 32);
    assert(BigInteger("0x8000_0000_0000", options).bitLength == 48);
    assert(BigInteger("0x8000_0000_0000_0000", options).bitLength == 64);
    assert(BigInteger("0x8000_0000_0000_0000_0000", options).bitLength == 80);
    assert(BigInteger("-0x40_0000_0000_0000_0000_0000", options).bitLength == 87);
}

unittest // BigInteger.trailingZeroBits
{
    assert(BigInteger(0).trailingZeroBits == 0);
    assert(BigInteger(1).trailingZeroBits == 0);
    assert(BigInteger(-1).trailingZeroBits == 0);
    assert(BigInteger(2).trailingZeroBits == 1);
    assert(BigInteger(4).trailingZeroBits == 2);

    auto options = defaultParseBigIntegerOptions!char();
    options.flags |= NumericLexerFlag.unsigned;

    assert(BigInteger("0xabc", options).trailingZeroBits == 2);
    assert(BigInteger("0x8000", options).trailingZeroBits == 15);
    assert(BigInteger("0x8000_0000", options).trailingZeroBits == 31);
    assert(BigInteger("0x8000_0000_0000", options).trailingZeroBits == 47);
    assert(BigInteger("0x8000_0000_0000_0000", options).trailingZeroBits == 63);
    assert(BigInteger("0x8000_0000_0000_0000_0000", options).trailingZeroBits == 79);
    assert(BigInteger("-0x40_0000_0000_0000_0000_0000", options).trailingZeroBits == 86);
}

unittest // BigInteger.sqrt
{
    auto options = defaultParseBigIntegerOptions!char();
    options.flags |= NumericLexerFlag.unsigned;

    const x1 = BigInteger("0x92fcad4b5c0d52f451aec609b15da8e5e5626c4eaa88723bdeac9d25ca9b961269400410ca208a16af9c2fb07d799c32fe2f3cc5422f9711078d51a3797eb18e691295293284d8f5e69caf6decddfe1df6", options);
    const r1 = BigInteger("25896323039101168858705535065253312412509632832011338487216516809677871643438699011042899929132115", options);
    assert(x1.sqrt == r1);

    const x2 = BigInteger("0x5c0d52f451aec609b15da8e5e5626c4eaa88723bdeac9d25ca9b961269400410ca208a16af9c2fb07d7a11c7772cba02c22f9711078d51a3797eb18e691295293284d988e349fa6deba46b25a4ecd9f715", options);
    const r2 = BigInteger("20493462331187228687772903530600462842384761584767303313899474124009959815839275652338762739419510", options);
    assert(x2.sqrt == r2);

    assert(BigInteger("653987632134").sqrt == BigInteger("808695"));
}

unittest // BigInteger.divRem
{
    BigInteger divident = BigInteger(-50);
    BigInteger divisor = BigInteger(1);
    BigInteger remainder = BigInteger(1);
    auto quotient = divRem(divident, divisor, remainder);
    assert(remainder == 0);

    divident = BigInteger(50);
    divisor = BigInteger(-1);
    remainder = BigInteger(1);
    quotient = divRem(divident, divisor, remainder);
    assert(remainder == 0);
}

unittest // BigInteger.divRem vs / & %
{
    // a = (a div m)*m + (a mod m)

    assert(BigInteger(8) / BigInteger(5) == BigInteger(1));
    assert(BigInteger(-8) / BigInteger(5) == BigInteger(-1));
    assert(BigInteger(8) / BigInteger(-5) == BigInteger(-1));
    assert(BigInteger(-8) / BigInteger(-5) == BigInteger(1));

    assert(BigInteger(8) % BigInteger(5) == BigInteger(3));
    assert(BigInteger(-8) % BigInteger(5) == BigInteger(-3));
    assert(BigInteger(8) % BigInteger(-5) == BigInteger(3));
    assert(BigInteger(-8) % BigInteger(-5) == BigInteger(-3));

	BigInteger d, r;
	d = divRem(BigInteger(8), BigInteger(5), r);
    assert(d == BigInteger(1));
    assert(r == BigInteger(3));
	d = divRem(BigInteger(-8), BigInteger(5), r);
    assert(d == BigInteger(-1));
    assert(r == BigInteger(-3));
	d = divRem(BigInteger(8), BigInteger(-5), r);
    assert(d == BigInteger(-1));
    assert(r == BigInteger(3));
	d = divRem(BigInteger(-8), BigInteger(-5), r);
    assert(d == BigInteger(1));
    assert(r == BigInteger(-3));
}
