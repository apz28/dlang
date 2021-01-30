/*
 *
 * License: $(HTTP www.boost.org/LICENSE_1_0.txt, Boost License 1.0).
 * Authors: An Pham
 *
 * Copyright An Pham 2019 - xxxx.
 * Distributed under the Boost Software License, Version 1.0.
 * (See accompanying file LICENSE.txt or copy at http://www.boost.org/LICENSE_1_0.txt)
 *
 * A clone from https://github.com/dotnet/corefx
 * tree/master/src/System.Runtime.Numerics/src/System/Numerics
 */

module pham.cp.biginteger;

import std.array : Appender;
import std.conv : ConvException;
import std.format : FormatSpec, formatValue, FormatException;
import std.string : indexOf, CaseSensitive;
import std.typecons : Flag, No, Yes;
import std.traits;

import pham.utl.array : IndexedArray;
import pham.utl.utlobject;
import pham.cp.biginteger_helper;
import pham.cp.biginteger_calculator;

@safe:

enum ParseStyle
{
    allowLeadingWhite = 1 << 0,
    trailingWhite = 1 << 1,
    allowThousand = 1 << 2,
    isHexs = 1 << 3,
    isUnsigned = 1 << 4
}

struct ParseFormat
{
nothrow @safe:

    // Any chars is less or equal to ' ' will be consider space and thousand chars
    string thousandChars = ",_";

    ParseStyle styles = ParseStyle.allowLeadingWhite
        | ParseStyle.trailingWhite
        | ParseStyle.allowThousand;

    bool isAllowThousandChar(char c) const pure
    {
        return (styles & ParseStyle.allowThousand) != 0 && isThousandChar(c);
    }

    static bool isHexPrefix(const(char)[] hexs) pure
    {
        return hexs.length >= 2 && hexs[0] == '0' && (hexs[1] == 'x' || hexs[1] == 'X');
    }

    pragma (inline, true)
    bool isSpaceChar(char c) const pure
    {
        return c <= ' ';
    }

    pragma (inline, true)
    bool isThousandChar(char c) const pure
    {
        return isSpaceChar(c) || thousandChars.indexOf(c, Yes.caseSensitive) >= 0;
    }
}

Flag!"negative" toNegativeFlag(bool value) @nogc nothrow pure
{
    return value ? Yes.negative : No.negative;
}

Flag!"unsigned" toUnsignedFlag(bool value) @nogc nothrow pure
{
    return value ? Yes.unsigned : No.unsigned;
}

struct BigInteger
{
@safe:

public:
    this(T)(T value) nothrow pure
    if (is(Unqual!T == BigInteger))
    {
        setSignInts(value._sign, value._bits);
    }

    this(T)(T value) nothrow pure
    if (isIntegral!T)
    {
        setInt(value);
    }

    this(T)(T value) nothrow pure
    if (isFloatingPoint!T)
    {
        setFloat(value);
    }

    /// <summary>
    /// Creates a BigInteger from a little-endian twos-complement ubyte array.
    /// </summary>
    /// <param name="value"></param>
    this(scope const(ubyte)[] value,
        const Flag!"unsigned" unsigned = No.unsigned,
        const Flag!"bigEndian" bigEndian = No.bigEndian) nothrow pure
    {
        setBytes(value, unsigned, bigEndian);
    }

    this(int sign, scope const(uint)[] bits) nothrow pure
    {
        setSignInts(sign, bits);
    }

    /// <summary>
    /// Constructor used during bit manipulation and arithmetic.
    /// When possible the uint[] will be packed into  _sign to conserve space.
    /// </summary>
    /// <param name="value">The absolute value of the number</param>
    /// <param name="negative">The bool indicating the sign of the value.</param>
    this(scope const(uint)[] value, const Flag!"negative" negative) nothrow pure
    {
        setNegativeInts(negative, value);
    }

    this(scope const(char)[] hexOrDecimals,
        const ParseFormat format = ParseFormat.init) pure
    {
        import std.conv : ConvException;
        import std.exception : enforce;

        setZero();

        bool anyDigits, negative;
        size_t errorIndex = size_t.max;
        size_t l = 0;
        size_t r = hexOrDecimals.length;

        // Trim trailings so that some check codes can be out of loop when calling
        // setHexs or setDecimals
        if (format.styles & ParseStyle.allowThousand)
        {
            while (r > 0 && format.isThousandChar(hexOrDecimals[r - 1]))
                --r;
        }
        else if (format.styles & ParseStyle.trailingWhite)
        {
            while (r > 0 && format.isSpaceChar(hexOrDecimals[r - 1]))
                --r;
        }

        // Trim leadings so that some check codes can be out of loop when calling
        // setHexs or setDecimals
        void trimLeadingChars()
        {
            if (format.styles & ParseStyle.allowThousand)
            {
                while (l < r && format.isThousandChar(hexOrDecimals[l]))
                    ++l;
            }
            else if (format.styles & ParseStyle.allowLeadingWhite)
            {
                while (l < r && format.isSpaceChar(hexOrDecimals[l]))
                    ++l;
            }
        }

        trimLeadingChars();

        // Check leading sign char
        if (l < r)
        {
            if (hexOrDecimals[l] == '+')
            {
                ++l;
                trimLeadingChars();
            }
            else if (hexOrDecimals[l] == '-')
            {
                ++l;
                negative = true;
                trimLeadingChars();
            }
        }

        bool isHexs = (format.styles & ParseStyle.isHexs) != 0;
        if (l < r && ParseFormat.isHexPrefix(hexOrDecimals[l..r]))
        {
            l += 2;
            isHexs = true;
            trimLeadingChars();
        }

        if (l < r)
        {
            anyDigits = true;
            if (isHexs)
                setHexs(hexOrDecimals[l..r], format, errorIndex);
            else
                setDecimals(hexOrDecimals[l..r], format, errorIndex);
        }

        enforce!ConvException(anyDigits && errorIndex == size_t.max, "Not a valid numerical string");

        if (negative)
            this.opUnary!"-"();
    }

    /// <summary>
    /// Create a BigInteger from a little-endian twos-complement UInt32 array.
    /// When possible, value is assigned directly to this._bits without an array copy
    /// so use this ctor with care.
    /// </summary>
    /// <param name="value"></param>
    private this(scope const(uint)[] value) nothrow pure
    {
        setInts(value);
    }

    BigInteger opAssign(T)(T x) nothrow pure
    if (is(Unqual!T == BigInteger))
    {
        setSignInts(x._sign, x._bits);
        return this;
    }

    BigInteger opAssign(T)(T x) nothrow pure
    if (isIntegral!T)
    {
        setInt(x);
        return this;
    }

    BigInteger opAssign(T)(T x) nothrow pure
    if (isFloatingPoint!T)
    {
        setFloat(x);
        return this;
    }

    BigInteger opOpAssign(string op, T)(const T right) nothrow pure
    if ((op == "+" || op == "-" || op == "*" || op == "/" || op == "%") && is(T: BigInteger))
    {
        static if (op == "+")
        {
            debug assertValid();
            debug right.assertValid();

            if ((_sign < 0) != (right._sign < 0))
                return subtractOpAssign(right._bits, -1 * right._sign);
            else
                return addOpAssign(right._bits, right._sign);
        }
        else static if (op == "-")
        {
            debug assertValid();
            debug right.assertValid();

            if ((_sign < 0) != (right._sign < 0))
                return addOpAssign(right._bits, -1 * right._sign);
            else
                return subtractOpAssign(right._bits, right._sign);
        }
        else static if (op == "*")
        {
            debug assertValid();
            debug right.assertValid();

            const trivialLeft = _bits.length == 0;
            const trivialRight = right._bits.length == 0;

            if (trivialLeft && trivialRight)
                setInt(cast(long)_sign * right._sign);
            else if (trivialLeft)
            {
                auto resultBits = BigIntegerCalculator.multiply(right._bits, BigIntegerHelper.abs(_sign));
                setNegativeInts(toNegativeFlag((_sign < 0) ^ (right._sign < 0)), resultBits[]);
            }
            else if (trivialRight)
            {
                auto resultBits = BigIntegerCalculator.multiply(_bits, BigIntegerHelper.abs(right._sign));
                setNegativeInts(toNegativeFlag((_sign < 0) ^ (right._sign < 0)), resultBits[]);
            }
            else if (_bits == right._bits)
            {
                auto resultBits = BigIntegerCalculator.square(_bits);
                setNegativeInts(toNegativeFlag((_sign < 0) ^ (right._sign < 0)), resultBits[]);
            }
            else if (_bits.length < right._bits.length)
            {
                auto resultBits = BigIntegerCalculator.multiply(right._bits, _bits);
                setNegativeInts(toNegativeFlag((_sign < 0) ^ (right._sign < 0)), resultBits[]);
            }
            else
            {
                auto resultBits = BigIntegerCalculator.multiply(_bits, right._bits);
                setNegativeInts(toNegativeFlag((_sign < 0) ^ (right._sign < 0)), resultBits[]);
            }

            return this;
        }
        else static if (op == "/")
        {
            debug assertValid();
            debug right.assertValid();

            const trivialDividend = _bits.length == 0;
            const trivialDivisor = right._bits.length == 0;

            if (trivialDividend && trivialDivisor)
                setInt(_sign / right._sign);
            // The divisor is non-trivial and therefore the bigger one
            else if (trivialDividend)
                setZero();
            else if (trivialDivisor)
            {
                auto resultBits = BigIntegerCalculator.divide(_bits, BigIntegerHelper.abs(right._sign));
                setNegativeInts(toNegativeFlag((_sign < 0) ^ (right._sign < 0)), resultBits[]);
            }
            else if (_bits.length < right._bits.length)
                setZero();
            else
            {
                auto resultBits = BigIntegerCalculator.divide(_bits, right._bits);
                setNegativeInts(toNegativeFlag((_sign < 0) ^ (right._sign < 0)), resultBits[]);
            }

            return this;
        }
        else static if (op == "%")
        {
            debug assertValid();
            debug right.assertValid();

            const trivialDividend = _bits.length == 0;
            const trivialDivisor = right._bits.length == 0;

            if (trivialDividend && trivialDivisor)
                setInt(_sign % right._sign);
            // The divisor is non-trivial and therefore the bigger one
            else if (trivialDividend)
                setSignInts(_sign, _bits);
            else if (trivialDivisor)
            {
                uint remainder = BigIntegerCalculator.remainder(_bits, BigIntegerHelper.abs(right._sign));
                if (_sign < 0)
                    setInt(-1 * remainder);
                else
                    setInt(remainder);
            }
            else if (_bits.length < right._bits.length)
            {
                //setSignInts(_sign, _bits);
            }
            else
            {
                auto resultBits = BigIntegerCalculator.remainder(_bits, right._bits);
                setNegativeInts(toNegativeFlag(_sign < 0), resultBits[]);
            }

            return this;
        }
        else
            static assert(0, typeof(this).stringof ~ " " ~ op ~ "= " ~ T.stringof ~ " is not supported");
    }

    BigInteger opOpAssign(string op, T)(const T right) nothrow pure
    if ((op == "+" || op == "-" || op == "*" || op == "/" || op == "%") && isIntegral!T)
    {
        return this.opOpAssign!op(BigInteger(right));
    }

    BigInteger opOpAssign(string op, T)(const T right) nothrow pure
    if ((op == "&" || op == "|" || op == "^") && is(T: BigInteger))
    {
        static if (op == "&")
        {
            if (isZero || right.isZero)
            {
                setZero();
                return this;
            }
            else if (_bits.length == 0 && right._bits.length == 0)
            {
                setInt(_sign & right._sign);
                return this;
            }
        }
        else static if (op == "|")
        {
            if (isZero)
            {
                setSignInts(right._sign, right._bits);
                return this;
            }
            else if (right.isZero)
                return this;
            else if (_bits.length == 0 && right._bits.length == 0)
            {
                setInt(_sign | right._sign);
                return this;
            }
        }
        else static if (op == "^")
        {
            if (_bits.length == 0 && right._bits.length == 0)
            {
                setInt(_sign ^ right._sign);
                return this;
            }
        }
        else
            static assert(0, typeof(this).stringof ~ " " ~ op ~ "= " ~ T.stringof ~ " is not supported");

        auto x = toUIntArray();
        auto y = right.toUIntArray();
        auto z = UIntTempArray(0);
        z.length = Math.Max(x.Length, y.Length);
        const uint xExtend = (_sign < 0) ? uint.MaxValue : 0;
        const uint yExtend = (right._sign < 0) ? uint.MaxValue : 0;

        for (size_t i = 0; i < z.Length; i++)
        {
            const uint xu = (i < x.Length) ? x[i] : xExtend;
            const uint yu = (i < y.Length) ? y[i] : yExtend;
            mixin("z[i] = xu " ~ op ~ " yu");
        }

        setBits(z[]);

        return this;
    }

    BigInteger opOpAssign(string op, T)(const T right) nothrow pure
    if ((op == "&" || op == "|" || op == "^") && isIntegral!T)
    {
        static if (op == "&")
        {
            if (isZero || right == 0)
            {
                setZero();
                return this;
            }
            else if (_bits.length == 0)
            {
                setInt(_sign & right);
                return this;
            }
        }
        else static if (op == "|")
        {
            if (isZero)
            {
                setInt(right);
                return this;
            }
            else if (right == 0)
                return this;
            else if (_bits.length == 0)
            {
                setInt(_sign | right);
                return this;
            }
        }
        else static if (op == "^")
        {
            if (_bits.length == 0)
            {
                setInt(_sign ^ right);
                return this;
            }
        }
        else
            static assert(0, typeof(this).stringof ~ " " ~ op ~ "= " ~ T.stringof ~ " is not supported");

        return this.opOpAssign!op(BigInteger(rigth));
    }

    BigInteger opOpAssign(string op)(const int right) nothrow pure
    if (op == "<<" || op == ">>" || op == "^^")
    {
        static if (op == "<<")
        {
            const shift = right;

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
                setNegativeInts(toNegativeFlag(negx), zd[]);

                return this;
            }
        }
        else static if (op == ">>")
        {
            const shift = right;

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
                        return minusOne();

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
                setNegativeInts(toNegativeFlag(negx), zd[]);

                return this;
            }
        }
        else static if (op == "^^")
        {
            debug assertValid();

            const exponent = right;

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

                setNegativeInts(toNegativeFlag(_sign < 0 && (exponent & 1) != 0), resultBits[]);
            }

            return this;
        }
        else
            static assert(0, typeof(this).stringof ~ " " ~ op ~ "= " ~ int.stringof ~ " is not supported");
    }

    BigInteger opBinary(string op, T)(const T right) const nothrow pure
    if (((op == "+" || op == "-" || op == "*" || op == "/" || op == "%") && is(T: BigInteger)) ||
        ((op == "&" || op == "|" || op == "^") && is(T: BigInteger)))
    {
        auto result = BigInteger(_sign, _bits);
        return result.opOpAssign!op(right);
    }

    BigInteger opBinary(string op, T)(const T right) const nothrow pure
    if (((op == "+" || op == "-" || op == "*" || op == "/" || op == "%") && isIntegral!T) ||
        ((op == "&" || op == "|" || op == "^") && isIntegral!T))
    {
        auto result = BigInteger(_sign, _bits);
        return result.opOpAssign!op(BigInteger(right));
    }

    BigInteger opBinary(string op)(const int right) const nothrow pure
    if (op == "<<" || op == ">>" || op == "^^")
    {
        auto result = BigInteger(_sign, _bits);
        return result.opOpAssign!op(right);
    }

    BigInteger opBinaryRight(string op, T)(const T left) const nothrow pure
    if (((op == "+" || op == "-" || op == "*" || op == "/" || op == "%") && isIntegral!T) ||
        ((op == "&" || op == "|" || op == "^") && isIntegral!T))
    {
        auto result = BigInteger(left);
        return result.opOpAssign!op(this);
    }

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

    int opCmp(int other) const @nogc nothrow pure
    {
        return opCmp(cast(long)other);
    }

    int opCmp(uint other) const @nogc nothrow pure
    {
        return opCmp(cast(ulong)other);
    }

    int opCmp(long other) const @nogc nothrow pure
    {
        debug assertValid();

        if (_bits.length == 0)
            return BigIntegerHelper.compare(cast(long)_sign, other);

        ptrdiff_t cu;
        if ((_sign ^ other) < 0 || (cu = _bits.length) > 2)
            return _sign;

        ulong uu = other < 0 ? cast(ulong)(-other) : cast(ulong)other;
        ulong uuTmp = cu == 2 ? BigIntegerHelper.makeUlong(_bits[1], _bits[0]) : _bits[0];
        return _sign * BigIntegerHelper.compare(uuTmp, uu);
    }

    int opCmp(ulong other) const @nogc nothrow pure
    {
        debug assertValid();

        if (_sign < 0)
            return -1;

        if (_bits.length == 0)
            return BigIntegerHelper.compare(cast(ulong)_sign, other);

        const cu = _bits.length;
        if (cu > 2)
            return +1;

        ulong uuTmp = cu == 2 ? BigIntegerHelper.makeUlong(_bits[1], _bits[0]) : _bits[0];
        return BigIntegerHelper.compare(uuTmp, other);
    }

    int opCmp(const BigInteger other) const @nogc nothrow pure
    {
        debug assertValid();
        debug other.assertValid();

        if ((_sign ^ other._sign) < 0)
        {
            // Different signs, so the comparison is easy.
            return _sign < 0 ? -1 : +1;
        }

        // Same signs
        if (_bits.length == 0)
        {
            if (other._bits.length == 0)
                return _sign < other._sign ? -1 : _sign > other._sign ? +1 : 0;
            else
                return -other._sign;
        }

        ptrdiff_t cuThis, cuOther;
        if (other._bits.length == 0 || (cuThis = _bits.length) > (cuOther = other._bits.length))
            return _sign;

        if (cuThis < cuOther)
            return -_sign;

        auto cuDiff = getDiffLength(_bits, other._bits, cuThis);
        if (cuDiff == 0)
            return 0;

        return _bits[cuDiff - 1] < other._bits[cuDiff - 1] ? -_sign : _sign;
    }

    bool opEquals(int other) const @nogc nothrow pure
    {
        return opEquals(cast(long)other);
    }

    bool opEquals(uint other) const @nogc nothrow pure
    {
        return opEquals(cast(ulong)other);
    }

    bool opEquals(long other) const @nogc nothrow pure
    {
        debug assertValid();

        if (_bits.length == 0)
            return _sign == other;

        long cu;
        if ((_sign ^ other) < 0 || (cu = _bits.length) > 2)
            return false;

        const ulong uu = other < 0 ? cast(ulong)(-other) : cast(ulong)other;
        if (cu == 1)
            return _bits[0] == uu;

        return BigIntegerHelper.makeUlong(_bits[1], _bits[0]) == uu;
    }

    bool opEquals(ulong other) const @nogc nothrow pure
    {
        debug assertValid();

        if (_sign < 0)
            return false;

        if (_bits.length == 0)
            return cast(ulong)_sign == other;

        const size_t cu = _bits.length;
        if (cu > 2)
            return false;

        if (cu == 1)
            return _bits[0] == other;

        return BigIntegerHelper.makeUlong(_bits[1], _bits[0]) == other;
    }

    bool opEquals(const BigInteger other) const @nogc nothrow pure
    {
        debug assertValid();
        debug other.assertValid();

        if (_sign != other._sign)
            return false;

        if (_bits == other._bits)
            // _sign == other._sign && _bits.length == 0 && other._bits.length == 0
            return true;

        if (_bits.length == 0 || other._bits.length == 0)
            return false;

        const ptrdiff_t cu = _bits.length;
        if (cu != other._bits.length)
            return false;

        return getDiffLength(_bits, other._bits, cu) == 0;
    }

    BigInteger opUnary(string op)() nothrow
    if (op == "+" || op == "-" || op == "~" || op == "++" || op == "--")
    {
        static if (op == "+")
        {
            debug assertValid();
        }
        else static if (op == "-")
        {
            debug assertValid();
            setSignInts(-_sign, _bits);
        }
        else static if (op == "~")
        {
            // -(this + one);
            this.opOpAssign!"+"(one);
            setSignInts(-_sign, _bits);
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

    // For security reason, need a way clear the secrete information
    void dispose(bool disposing) @nogc nothrow pure
    {
        _sign = 0;
        _bits[] = 0;
    }

    /// <summary>Gets the number of bytes that will be output by <see cref="toUByteArray(bool, bool)"/> and <see cref="TryWriteBytes(Span{ubyte}, out int, bool, bool)"/>.</summary>
    /// <returns>The number of bytes.</returns>
    size_t getByteCount(const Flag!"includeSign" includeSign = Yes.includeSign) const nothrow
    {
        // Big or Little Endian doesn't matter for the byte count.
        UByteTempArray bytes;
        return getUBytesLittleEndian(includeSign, GetBytesMode.count, bytes);
    }

    bool isEven() const @nogc nothrow pure
    {
        debug assertValid();

        return _bits.length == 0 ? (_sign & 1) == 0 : (_bits[0] & 1) == 0;
    }

    bool isOne() const @nogc nothrow pure
    {
        debug assertValid();

        return _sign == 1 && _bits.length == 0;
    }

    bool isPowerOfTwo() const @nogc nothrow pure
    {
        debug assertValid();

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

    bool isZero() const @nogc nothrow pure
    {
        debug assertValid();

        return _sign == 0;
    }

    void setZero() nothrow pure
    {
        _sign = 0;
        _bits = null;
    }

    int sign() const @nogc nothrow pure
    {
        debug assertValid();

        return (_sign >> (kcbitUint - 1)) - (-_sign >> (kcbitUint - 1));
    }

    static BigInteger minusOne() nothrow pure
    {
        return BigInteger(-1);
    }

    static BigInteger one() nothrow pure
    {
        return BigInteger(1);
    }

    static BigInteger zero() nothrow pure
    {
        return BigInteger(0);
    }

    double toFloat() const @nogc nothrow pure
    {
        debug assertValid();

        const len = cast(int)_bits.length;

        if (len == 0)
            return _sign;

        // The maximum exponent for doubles is 1023, which corresponds to a uint bit length of 32.
        // All BigIntegers with bits[] longer than 32 evaluate to Double.Infinity (or NegativeInfinity).
        // Cases where the exponent is between 1024 and 1035 are handled in BigIntegerHelper.GetDoubleFromParts.
        enum infinityLength = 1024 / kcbitUint;

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

    size_t toHash() const nothrow @nogc
    {
        debug assertValid();

        if (_bits.length == 0)
            return cast(size_t)_sign;

        size_t hash = cast(size_t)_sign;
        for (ptrdiff_t iv = _bits.length; --iv >= 0;)
            hash = BigIntegerHelper.combineHash(hash, cast(size_t)_bits[iv]);

        return hash;
    }

    long toLong() const pure
    {
        debug assertValid();

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

    ulong toULong() const pure
    {
        debug assertValid();

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

    /// <summary>
    /// Returns the value of this BigInteger as a ubyte array using the fewest number of bytes possible.
    /// If the value is zero, returns an array of one ubyte whose element is 0x00.
    /// </summary>
    /// <param name="isUnsigned">Whether or not an unsigned encoding is to be used</param>
    /// <param name="isBigEndian">Whether or not to write the bytes in a big-endian byte order</param>
    /// <returns></returns>
    /// <exception cref="OverflowException">
    ///   If <paramref name="isUnsigned"/> is <c>true</c> and <see cref="sign"/> is negative.
    /// </exception>
    /// <remarks>
    /// The integer value <c>33022</c> can be exported as four different arrays.
    ///
    /// <list type="bullet">
    ///   <item>
    ///     <description>
    ///       <c>(isUnsigned: false, isBigEndian: false)</c> => <c>new ubyte[] { 0xFE, 0x80, 0x00 }</c>
    ///     </description>
    ///   </item>
    ///   <item>
    ///     <description>
    ///       <c>(isUnsigned: false, isBigEndian: true)</c> => <c>new ubyte[] { 0x00, 0x80, 0xFE }</c>
    ///     </description>
    ///   </item>
    ///   <item>
    ///     <description>
    ///       <c>(isUnsigned: true, isBigEndian: false)</c> => <c>new ubyte[] { 0xFE, 0x80 }</c>
    ///     </description>
    ///   </item>
    ///   <item>
    ///     <description>
    ///       <c>(isUnsigned: true, isBigEndian: true)</c> => <c>new ubyte[] { 0x80, 0xFE }</c>
    ///     </description>
    ///   </item>
    /// </list>
    /// </remarks>
    ubyte[] toBytes(const Flag!"includeSign" includeSign = Yes.includeSign) const nothrow pure
    {
        UByteTempArray result;
        getUBytesLittleEndian(includeSign, GetBytesMode.allocateArray, result);
        return result.dup;
    }

    /// <summary>
    /// Return the value of this BigInteger as a little-endian twos-complement
    /// uint array, using the fewest number of uints possible. If the value is zero,
    /// return an array of one uint whose element is 0.
    /// </summary>
    /// <returns></returns>
    uint[] toInts(const Flag!"includeSign" includeSign = Yes.includeSign) const nothrow
    {
        if (isEmpty())
            return [0];

        uint highDWord;
        auto result = cloneForConvert!uint(highDWord);

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

        return result.dup;
    }

    string toString() const nothrow pure
    {
        Appender!string writer;
        writer.reserve(256);

        FormatSpec!char f;
        f.spec = 'd';
        toString(writer, f);

        return writer.data;
    }

    string toString(string formatString,
        char separatorChar = '\0') const pure
    {
        Appender!string writer;
        writer.reserve(256);

        auto f = FormatSpec!char(formatString);
        f.separatorChar = separatorChar;
        if (separatorChar == '\0')
            f.flSeparator = false;
        f.writeUpToNextSpec(writer);

        if (f.spec == 'd')
            toString(writer, f);
        else if (f.spec == 'x' || f.spec == 'X')
            toHexString(writer, f, Yes.includeSign);
       else
            assert(0, "Invalid format specifier: %" ~ f.spec);

        return writer.data;
    }

    string toHexString(const Flag!"includeSign" includeSign = Yes.includeSign,
        const Flag!"isUpper" isUpper = Yes.isUpper) const nothrow pure
    {
        Appender!string writer;
        writer.reserve(256);

        FormatSpec!char f;
        f.spec = isUpper ? 'X' : 'x';
        toHexString(writer, f, includeSign);

        return writer.data;
    }

private:
    BigInteger addOpAssign(const(uint)[] rightBits, int rightSign) nothrow pure
    {
        const trivialLeft = _bits.length == 0;
        const trivialRight = rightBits.length == 0;

        if (trivialLeft && trivialRight)
            setInt(cast(long)_sign + rightSign);
        else if (trivialLeft)
        {
            auto resultBits = BigIntegerCalculator.add(rightBits, BigIntegerHelper.abs(_sign));
            setNegativeInts(toNegativeFlag(_sign < 0), resultBits[]);
        }
        else if (trivialRight)
        {
            auto resultBits = BigIntegerCalculator.add(_bits, BigIntegerHelper.abs(rightSign));
            setNegativeInts(toNegativeFlag(_sign < 0), resultBits[]);
        }
        else if (_bits.length < rightBits.length)
        {
            auto resultBits = BigIntegerCalculator.add(rightBits, _bits);
            setNegativeInts(toNegativeFlag(_sign < 0), resultBits[]);
        }
        else
        {
            auto resultBits = BigIntegerCalculator.add(_bits, rightBits);
            setNegativeInts(toNegativeFlag(_sign < 0), resultBits[]);
        }

        return this;
    }

    debug void assertValid() const nothrow
    {
        if (_bits.ptr !is null)
        {
            // _sign must be +1 or -1 when _bits is non-null
            assert(_sign == 1 || _sign == -1);

            // _bits must contain at least 1 element or be null
            assert(_bits.length > 0);

            // Wasted space: _bits[0] could have been packed into _sign
            assert(_bits.length > 1 || _bits[0] >= kuMaskHighBit);

            // Wasted space: leading zeros could have been truncated
            assert(_bits[_bits.length - 1] != 0);
        }
        else
        {
            // Int32.MinValue should not be stored in the _sign field
            assert(_sign > int.min);
        }
    }

    void convertError(string toT) const pure
    {
        import std.conv : ConvException;

        auto msg = "Error converting BigInteger(" ~ toString() ~ ") to " ~ toT;
        throw new ConvException(msg);
    }

    UIntTempArray cloneForConvert(I)(out I highMark) const
    {
        if (_bits.length == 0)
        {
            highMark = _sign < 0 ? I.max : 0;
            auto result = UIntTempArray(1);
            result[0] = cast(uint)_sign;
            return result;
        }
        else if (_sign < 0)
        {
            highMark = I.max;
            auto result = UIntTempArray(_bits);
            return BigIntegerCalculator.makeTwosComplement(result);
        }
        else
        {
            highMark = 0;
            return UIntTempArray(_bits);
        }
    }

    static ptrdiff_t getDiffLength(const(uint)[] rgu1, const(uint)[] rgu2, ptrdiff_t cu) @nogc nothrow pure
    {
        for (ptrdiff_t iv = cu; --iv >= 0;)
        {
            if (rgu1[iv] != rgu2[iv])
                return iv + 1;
        }
        return 0;
    }

    /// <summary>
    /// Encapsulate the logic of normalizing the "small" and "large" forms of BigInteger
    /// into the "large" form so that Bit Manipulation algorithms can be simplified.
    /// </summary>
    /// <param name="x"></param>
    /// <param name="xd">
    /// The UInt32 array containing the entire big integer in "large" (denormalized) form.
    /// E.g., the number one (1) and negative one (-1) are both stored as 0x00000001
    /// BigInteger values Int32.MinValue &lt; x &lt;= Int32.MaxValue are converted to this
    /// format for convenience.
    /// </param>
    /// <param name="xl">The length of xd.</param>
    /// <returns>True for negative numbers.</returns>
    static bool getPartsForBitManipulation(const BigInteger x, out UIntTempArray xd, out int xl) nothrow pure
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

    bool isEmpty() const nothrow pure
    {
        return _sign == 0 && _bits.length == 0;
    }

    void setBytes(scope const(ubyte)[] value,
        const Flag!"unsigned" unsigned = No.unsigned,
        const Flag!"bigEndian" bigEndian = No.bigEndian) nothrow pure
    {
        bool isNegative;
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
        else
        {
            isNegative = false;
        }

        if (byteCount == 0)
        {
            // BigInteger.zero
            _sign = 0;
            _bits = null;

            debug assertValid();
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
                            setMinusOne();
                            return;

                        case kuMaskHighBit: // abs(int.min)
                            setMinInt();
                            return;

                        default:
                            if (cast(int)val[0] > 0)
                            {
                                _sign = (-1) * (cast(int)val[0]);
                                _bits = null;

                                debug assertValid();
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

        debug assertValid();
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

            debug assertValid();
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

            debug assertValid();
            return;
        }

        if (!isNegative)
        {
            // Handle the simple positive value cases where the input is already in sign magnitude
            _sign = +1;
            _bits = value[0..dwordCount].dup;

            debug assertValid();
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
                setMinusOne();
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

        debug assertValid();
    }

    // digits[0] must be a valid decimal digit
    void setDecimals(scope const(char)[] digits, const ParseFormat format, ref size_t errorAt) nothrow pure
    {
        const ten = BigInteger(10);

        foreach (i, c; digits)
        {
            if (c >= '0' && c <= '9')
            {
                this.opOpAssign!"*"(ten);
                this.opOpAssign!"+"(BigInteger(c - '0'));
            }
            else
            {
                if (format.isAllowThousandChar(c))
                    continue;
                else
                {
                    errorAt = i;
                    return;
                }
            }
        }
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
            _bits = new uint[cu + 2];
            _bits[cu + 1] = cast(uint)(man >> (cbit + kcbitUint));
            _bits[cu] = cast(uint)(man >> cbit);
            if (cbit > 0)
                _bits[cu - 1] = (cast(uint)man) << (kcbitUint - cbit);
            _sign = sign;
        }

        debug assertValid();
    }

    // digits[0] must be a valid hex character
    void setHexs(scope const(char)[] digits, const ParseFormat format, ref size_t errorAt) nothrow pure
    {
        const length = (digits.length / 2) + (digits.length % 2);
        auto resultBits = IndexedArray!(ubyte, allocationThreshold * uint.sizeof)(length);

        size_t bitIndex = 0;
        bool shift = false;
        ubyte b;

        // Parse the string into a little-endian two's complement byte array
        // string value     : O F E B 7 \0
        // string index (i) : 0 1 2 3 4 5 <--
        // byte[] (bitIndex): 2 1 1 0 0 <--
        //

        isHex(digits[0], b);
        const isNegative = (format.styles & ParseStyle.isUnsigned) == 0 && (b & 0x08) == 0x08;

        for (auto i = digits.length - 1; i > 0; i--)
        {
            if (!isHex(digits[i], b))
            {
                if (format.isAllowThousandChar(digits[i]))
                    continue;
                else
                {
                    errorAt = i;
                    return;
                }
            }

            if (shift)
            {
                resultBits[bitIndex] = cast(ubyte)(resultBits[bitIndex] | (b << 4));
                bitIndex++;
            }
            else
            {
                resultBits[bitIndex] = b;
            }
            shift = !shift;
        }

        isHex(digits[0], b);
        if (shift)
            resultBits[bitIndex] = cast(ubyte)(resultBits[bitIndex] | (b << 4));
        else
            resultBits[bitIndex] = isNegative ? cast(ubyte)(b | 0xF0) : b;

        setBytes(resultBits[], isNegative ? No.unsigned : Yes.unsigned);
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

        debug assertValid();
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

        debug assertValid();
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

        debug assertValid();
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

        debug assertValid();
    }

    // We have to make a choice of how to represent int.MinValue. This is the one
    // value that fits in an int, but whose negation does not fit in an int.
    // We choose to use a large representation, so we're symmetric with respect to negation.
    void setMinInt() nothrow pure
    {
        _bits = [kuMaskHighBit];
        _sign = -1;
    }

    void setMinusOne() nothrow pure
    {
        _bits = null;
        _sign = -1;
    }

    void setNegativeInts(const Flag!"negative" negative, scope const(uint)[] value) nothrow pure
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
            _sign = (negative ? -cast(int)value[0] : cast(int)value[0]);
            _bits = null;
            // Although Int32.MinValue fits in _sign, we represent this case differently for negate
            if (_sign == int.min)
                setMinInt();
        }
        else
        {
            _sign = negative ? -1 : +1;
            _bits = value[0..len].dup;
        }

        debug assertValid();
    }

    void setOne() nothrow pure
    {
        _bits = null;
        _sign = 1;
    }

    void setSignInts(int sign, scope const(uint)[] bits) nothrow pure
    {
        _sign = sign;
        _bits = bits.dup;

        debug assertValid();
    }

    BigInteger subtractOpAssign(const(uint)[] rightBits, int rightSign) nothrow pure
    {
        const trivialLeft = _bits.length == 0;
        const trivialRight = rightBits.length == 0;

        if (trivialLeft && trivialRight)
            setInt(cast(long)_sign - rightSign);
        else if (trivialLeft)
        {
            auto resultBits = BigIntegerCalculator.subtract(rightBits, BigIntegerHelper.abs(_sign));
            setNegativeInts(toNegativeFlag(_sign >= 0), resultBits[]);
        }
        else if (trivialRight)
        {
            auto resultBits = BigIntegerCalculator.subtract(_bits, BigIntegerHelper.abs(rightSign));
            setNegativeInts(toNegativeFlag(_sign < 0), resultBits[]);
        }
        else if (BigIntegerCalculator.compare(_bits, rightBits) < 0)
        {
            auto resultBits = BigIntegerCalculator.subtract(rightBits, _bits);
            setNegativeInts(toNegativeFlag(_sign >= 0), resultBits[]);
        }
        else
        {
            auto resultBits = BigIntegerCalculator.subtract(_bits, rightBits);
            setNegativeInts(toNegativeFlag(_sign < 0), resultBits[]);
        }

        return this;
    }

    void toString(ref Appender!string writer, const ref FormatSpec!char f) const nothrow pure
    {
        try
        {
            const ptrdiff_t cuSrc = _bits.length;

            if (cuSrc == 0)
            {
                formatValue(writer, _sign, f);
                return;
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
                writer.put('0');
                ++resultLength;
            }

            if (signChar != 0)
                writer.put(signChar);

            auto digits = rgch[ichDst..rgch.length];
            if (f.flSeparator)
            {
                for (size_t j = 0; j < digits.length; ++j)
                {
                    if (j != 0 && (digits.length - j) % f.separators == 0)
                        writer.put(f.separatorChar);
                    writer.put(digits[j]);
                }
            }
            else
                writer.put(digits);
        }
        catch (Exception)
        {
            assert(0);
        }
    }

    void toHexString(ref Appender!string writer, const ref FormatSpec!char f, const Flag!"includeSign" includeSign) const nothrow pure
    {
        const isUpper = f.spec == 'X';
        const hexDigitSources = isUpper ? upperHexDigits : lowerHexDigits;

        try
        {
            UByteTempArray bytesHolder;
            getUBytesLittleEndian(includeSign, GetBytesMode.allocateArray, bytesHolder);
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
                        : isUpper
                            ? cast(char)((head & 0xF) - 10 + 'A')
                            : cast(char)((head & 0xF) - 10 + 'a');
                    cur--;
                }
            }

            if (cur >= 0)
            {
                while (cur >= 0)
                {
                    const b = bytes[cur--];
                    hexDigits[charsPos++] = hexDigitSources[b >> 4];
                    hexDigits[charsPos++] = hexDigitSources[b & 0xF];
                }
            }

            ptrdiff_t resultLength = charsPos;
            while (resultLength < f.width)
            {
                writer.put('0');
                ++resultLength;
            }

            if (f.flSeparator)
            {
                const len = hexDigits.length;
                for (size_t j = 0; j < len; ++j)
                {
                    if (j != 0 && (len - j) % f.separators == 0)
                        writer.put(f.separatorChar);
                    writer.put(hexDigits[j]);
                }
            }
            else
                writer.put(hexDigits[]);
        }
        catch (Exception)
        {
            assert(0);
        }
    }

    /// <summary>Mode used to enable sharing <see cref="tryGetUBytes(GetBytesMode, Span{ubyte}, bool, bool, ref int)"/> for multiple purposes.</summary>
    enum GetBytesMode : byte
    {
        allocateArray,
        count
    }

    size_t getUBytesLittleEndian(const Flag!"includeSign" includeSign, GetBytesMode mode, ref UByteTempArray bytes) const nothrow pure
    {
        if (isEmpty())
        {
            if (mode == GetBytesMode.allocateArray)
            {
                bytes.clear(1);
                bytes[0] = 0;
            }
            return 1;
        }

        // We could probably make this more efficient by eliminating one of the passes.
        // The current code does one pass for uint array -> byte array conversion,
        // and then another pass to remove unneeded bytes at the top of the array.
        ubyte highByte;
        auto dwords = cloneForConvert!ubyte(highByte);
        bytes = UByteTempArray(4 * dwords.length);
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
        if (mode == GetBytesMode.allocateArray)
        {
            bytes.length = resultLength;
            if (needExtraByte)
                bytes[resultLength - 1] = highByte;
        }
        return resultLength;
    }

private:
    // For values int.MinValue < n <= int.MaxValue, the value is stored in sign
    // and _bits is null. For all other values, sign is +1 or -1 and the bits are in _bits
    uint[] _bits;
    int _sign;
}

int compare(const BigInteger left, const BigInteger right) @nogc nothrow pure
{
    return left.opCmp(right);
}

BigInteger add(const BigInteger left, const BigInteger right) nothrow pure
{
    return left + right;
}

BigInteger subtract(const BigInteger left, const BigInteger right) nothrow pure
{
    debug left.assertValid();
    debug right.assertValid();

    auto result = BigInteger(left._sign, left._bits);
    if ((left._sign < 0) != (right._sign < 0))
        return result.addOpAssign(right._bits, -1 * right._sign);
    else
        return result.subtractOpAssign(right._bits, right._sign);
}

BigInteger multiply(const BigInteger left, const BigInteger right) nothrow pure
{
    return left * right;
}

BigInteger divide(const BigInteger dividend, const BigInteger divisor) nothrow pure
{
    return dividend / divisor;
}

BigInteger remainder(const BigInteger dividend, const BigInteger divisor) nothrow pure
{
    return dividend % divisor;
}

BigInteger divRem(const BigInteger dividend, const BigInteger divisor, out BigInteger remainder) nothrow pure
{
    debug dividend.assertValid();
    debug divisor.assertValid();

    const trivialDividend = dividend._bits.length == 0;
    const trivialDivisor = divisor._bits.length == 0;

    if (trivialDividend && trivialDivisor)
    {
        remainder = BigInteger(dividend._sign % divisor._sign);
        return BigInteger(dividend._sign / divisor._sign);
    }

    if (trivialDividend)
    {
        // The divisor is non-trivial and therefore the bigger one
        remainder = BigInteger(dividend._sign, dividend._bits);
        return BigInteger.zero();
    }

    if (trivialDivisor)
    {
        uint rest;
        auto resultBits = BigIntegerCalculator.divide(dividend._bits, BigIntegerHelper.abs(divisor._sign), rest);

        remainder = BigInteger(dividend._sign < 0 ? -1 * rest : rest);
        return BigInteger(resultBits[], toNegativeFlag((dividend._sign < 0) ^ (divisor._sign < 0)));
    }

    if (dividend._bits.length < divisor._bits.length)
    {
        remainder = BigInteger(dividend._sign, dividend._bits);
        return BigInteger.zero();
    }
    else
    {
        UIntTempArray rest;
        auto resultBits = BigIntegerCalculator.divide(dividend._bits, divisor._bits, rest);

        remainder = BigInteger(rest[], toNegativeFlag(dividend._sign < 0));
        return BigInteger(resultBits[], toNegativeFlag((dividend._sign < 0) ^ (divisor._sign < 0)));
    }
}

BigInteger abs(const BigInteger value) nothrow pure
{
    auto result = BigInteger(value._sign, value._bits);
    if (result < BigInteger.zero)
        return -result;
    else
        return result;
}

double log(const BigInteger value, double baseValue) nothrow pure
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

double log(const BigInteger value) nothrow pure
{
    import std.math : E;

    return log(value, E);
}

double log10(const BigInteger value) nothrow pure
{
    return log(value, 10);
}

BigInteger negate(const BigInteger value) nothrow pure
{
    auto result = BigInteger(value._sign, value._bits);
    return -result;
}

BigInteger modPow(const BigInteger value, const BigInteger exponent, const BigInteger modulus) nothrow pure
in
{
    assert(exponent.sign >= 0);
}
do
{
    debug value.assertValid();
    debug exponent.assertValid();
    debug modulus.assertValid();

    const trivialValue = value._bits.length == 0;
    const trivialExponent = exponent._bits.length == 0;
    const trivialModulus = modulus._bits.length == 0;

    if (trivialModulus)
    {
        auto resultBits = trivialValue && trivialExponent ?
            BigIntegerCalculator.pow(BigIntegerHelper.abs(value._sign), BigIntegerHelper.abs(exponent._sign), BigIntegerHelper.abs(modulus._sign)) :
            trivialValue ?
                BigIntegerCalculator.pow(BigIntegerHelper.abs(value._sign), exponent._bits, BigIntegerHelper.abs(modulus._sign)) :
                trivialExponent ?
                    BigIntegerCalculator.pow(value._bits, BigIntegerHelper.abs(exponent._sign), BigIntegerHelper.abs(modulus._sign)) :
                    BigIntegerCalculator.pow(value._bits, exponent._bits, BigIntegerHelper.abs(modulus._sign));

        return value._sign < 0 && !exponent.isEven ? BigInteger.minusOne() * BigInteger(resultBits) : BigInteger(resultBits);
    }
    else
    {
        auto resultBits = trivialValue && trivialExponent ?
            BigIntegerCalculator.pow(BigIntegerHelper.abs(value._sign), BigIntegerHelper.abs(exponent._sign), modulus._bits) :
            trivialValue ?
                BigIntegerCalculator.pow(BigIntegerHelper.abs(value._sign), exponent._bits, modulus._bits) :
                trivialExponent ?
                    BigIntegerCalculator.pow(value._bits, BigIntegerHelper.abs(exponent._sign), modulus._bits) :
                    BigIntegerCalculator.pow(value._bits, exponent._bits, modulus._bits);

        return BigInteger(resultBits[], toNegativeFlag(value._sign < 0 && !exponent.isEven));
    }
}

BigInteger pow(const BigInteger value, int exponent) nothrow pure
{
    auto result = BigInteger(value._sign, value._bits);
    return result ^^ exponent;
}

inout(BigInteger) max(inout(BigInteger) left, inout(BigInteger) right) nothrow pure
{
    if (left < right)
        return right;
    else
        return left;
}

inout(BigInteger) min(inout(BigInteger) left, inout(BigInteger) right) nothrow pure
{
    if (left <= right)
        return left;
    else
        return right;
}

BigInteger greatestCommonDivisor(const BigInteger left, const BigInteger right) nothrow pure
{
    debug left.assertValid();
    debug right.assertValid();

    const trivialLeft = left._bits.length == 0;
    const trivialRight = right._bits.length == 0;

    if (trivialLeft && trivialRight)
    {
        return BigInteger(BigIntegerCalculator.gcd(BigIntegerHelper.abs(left._sign), BigIntegerHelper.abs(right._sign)));
    }

    if (trivialLeft)
    {
        return left._sign != 0
            ? BigInteger(BigIntegerCalculator.gcd(right._bits, BigIntegerHelper.abs(left._sign)))
            : BigInteger(right._bits, No.negative);
    }

    if (trivialRight)
    {
        return right._sign != 0
            ? BigInteger(BigIntegerCalculator.gcd(left._bits, BigIntegerHelper.abs(right._sign)))
            : BigInteger(left._bits, No.negative);
    }

    if (BigIntegerCalculator.compare(left._bits, right._bits) < 0)
        return greatestCommonDivisor(right._bits, left._bits);
    else
        return greatestCommonDivisor(left._bits, right._bits);
}


// Any below codes are private
private:


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

        ulong left = (cast(ulong)rightBits[1] << 32) | rightBits[0];
        ulong right = (cast(ulong)tempBits[1] << 32) | tempBits[0];

        return BigInteger(BigIntegerCalculator.gcd(left, right));
    }

    auto resultBits = BigIntegerCalculator.gcd(leftBits, rightBits);
    return BigInteger(resultBits[], No.negative);
}

version (unittest)
string toString(const BigInteger n,
    string format = null,
    char separator = '_') nothrow @safe
{
    try
    {
        return format.length ? n.toString(format, separator) : n.toString();
    }
    catch (Exception)
    {
        assert(0);
    }
}


nothrow unittest
{
    import std.conv : to;
    import pham.utl.utltest;
    dgWriteln("unittest cp.biginteger.BigInteger.toString('%d')");

    static void check(T)(T value, string checkedValue,
        string format = null,
        char separator = '_',
        size_t line = __LINE__) nothrow @safe
    {
        auto v = BigInteger(value);
        auto s = toString(v, format, separator);
        assert(s == checkedValue, "from line: " ~ to!string(line) ~ ": " ~ s ~ " ? " ~ checkedValue);
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

unittest
{
    import std.conv : to;
    import pham.utl.utltest;
    dgWriteln("unittest cp.biginteger.BigInteger.toString('%X')");

    static void check(T)(T value, string checkedValue,
        string format = "%X",
        char separator = '_',
        size_t line = __LINE__)
    {
        auto v = BigInteger(value);
        auto s = toString(v, format, separator);
        assert(s == checkedValue, "from line: " ~ to!string(line) ~ ": " ~ s ~ " ? " ~ checkedValue);
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

unittest
{
    import std.conv : to;
    import pham.utl.utltest;
    dgWriteln("unittest cp.biginteger.BigInteger(parse integer)");

    static void check(string value,
        size_t line = __LINE__) @safe
    {
        auto v = BigInteger(value);
        auto s = toString(v);
        assert(s == value, "from line: " ~ to!string(line) ~ ": " ~ s ~ " ? " ~ value);
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

unittest
{
    import std.conv : to;
    import pham.utl.utltest;
    dgWriteln("unittest cp.biginteger.BigInteger(parse hex)");

    static void check(string value,
        size_t line = __LINE__)
    {
        auto v = BigInteger("0x" ~ value);
        auto s = toString(v, "%X");
        assert(s == value, "from line: " ~ to!string(line) ~ ": " ~ s ~ " ? " ~ value);
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

unittest
{
    import pham.utl.utltest;
    dgWriteln("unittest cp.biginteger.BigInteger(compare)");

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

unittest
{
    import std.conv : to, ConvException;
    import std.exception : assertThrown;
    import pham.utl.utltest;
    dgWriteln("unittest cp.biginteger.BigInteger(cast)");

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

unittest
{
    import std.conv : to;
    import pham.utl.utltest;
    dgWriteln("unittest cp.biginteger.BigInteger(operator + - ~ )");

    static void check(const BigInteger value, string checkedValue,
        size_t line = __LINE__)
    {
        auto s = toString(value, "%,3d", '_');
        assert(s == checkedValue, "from line: " ~ to!string(line) ~ ": " ~ s ~ " ? " ~ checkedValue);
        assert(value == BigInteger(checkedValue), "from line: " ~ to!string(line) ~ ": " ~ s ~ " ? " ~ checkedValue);
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

unittest
{
    import std.conv : to;
    import pham.utl.utltest;
    dgWriteln("unittest cp.biginteger.BigInteger(operator * / %)");

    static void check(const BigInteger value, string checkedValue,
        size_t line = __LINE__)
    {
        auto s = toString(value, "%,3d", '_');
        assert(s == checkedValue, "from line: " ~ to!string(line) ~ ": " ~ s ~ " ? " ~ checkedValue);
        assert(value == BigInteger(checkedValue), "from line: " ~ to!string(line) ~ ": " ~ s ~ " ? " ~ checkedValue);
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

unittest
{
    import std.conv : to;
    import pham.utl.utltest;
    dgWriteln("unittest cp.biginteger.BigInteger(operator << >> ^^)");

    static void check(const BigInteger value, string checkedValue,
        size_t line = __LINE__)
    {
        auto s = toString(value, "%,3d", '_');
        assert(s == checkedValue, "from line: " ~ to!string(line) ~ ": " ~ s ~ " ? " ~ checkedValue);
        assert(value == BigInteger(checkedValue), "from line: " ~ to!string(line) ~ ": " ~ s ~ " ? " ~ checkedValue);
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

unittest
{
    import pham.utl.utltest;
    dgWriteln("unittest cp.biginteger.randomDecimalDigits");

    string s;

    s = randomDecimalDigits(0);
    assert(BigInteger(s) == 0, s ~ " ? " ~ BigInteger(s).toString());

    s = randomDecimalDigits(1);
    assert(BigInteger(s) > 0, s ~ " ? " ~ BigInteger(s).toString());

    s = randomDecimalDigits(10);
    assert(BigInteger(s) > 0, s ~ " ? " ~ BigInteger(s).toString());

    s = randomDecimalDigits(33);
    assert(BigInteger(s) > 0, s ~ " ? " ~ BigInteger(s).toString());
}

unittest
{
    import pham.utl.utltest;
    dgWriteln("unittest cp.biginteger.randomHexDigits");

    string s;

    s = randomHexDigits(0);
    assert(BigInteger(s) == 0, s ~ " ? " ~ BigInteger(s).toString());

    s = randomHexDigits(1);
    assert(BigInteger(s) > 0, s ~ " ? " ~ BigInteger(s).toString());

    s = randomHexDigits(10);
    assert(BigInteger(s) > 0, s ~ " ? " ~ BigInteger(s).toString());

    s = randomHexDigits(33);
    assert(BigInteger(s) > 0, s ~ " ? " ~ BigInteger(s).toString());
}

unittest
{
    import std.conv : to;
    import pham.utl.utltest;
    dgWriteln("unittest cp.biginteger.BigInteger(multiply)");

    static void check(const BigInteger value, string checkedValue,
        size_t line = __LINE__)
    {
        auto s = toString(value);
        assert(s == checkedValue, "from line: " ~ to!string(line) ~ ": " ~ s ~ " ? " ~ checkedValue);
        assert(value == BigInteger(checkedValue), "from line: " ~ to!string(line) ~ ": " ~ s ~ " ? " ~ checkedValue);
    }

    BigInteger v, x;

    v = multiply(BigInteger("241127122100380210001001124020210001001100000200003101000062221012075223052000021042250111300200000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"),
            BigInteger("70020000000050041832100040114001011000002200722143200000014102001132330110410406020210020045721000160014200000101224530010000111021520000000012000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"));
    check(v, "16883721089480688747229011802283756823349870758229387365814728471518346136944894862961035756393632618073413910091006778604956808730652275328822700182498926542563654351871390166691461743896850906716336187966456064270200717632811001335602400000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000");
}

unittest
{
    import pham.utl.utltest;
    dgWriteln("unittest cp.biginteger.BigInteger.enum");

    enum b = BigInteger("0x123");
    enum b2 = BigInteger("291");
    assert(b == b2);
}

unittest
{
    import pham.utl.utltest;
    dgWriteln("unittest cp.biginteger.BigInteger.toBytes");

    auto b = BigInteger("148607213746748888433115898774488125434956021884951532398437063594981690133657747515764650183781235940657054608881977858196568765979755791042029635107364589767082851027596594595936524517171068826751265581664247659551324634745120309986368437908665195084578221129443657946400665125676458397984792168049771254957");

    assert(bytesToHexs(b.toBytes()) == "AD9487795C33B20BE5A7D7011A954790747A3E248DBA651EBDBEFBC61872A6C9ACB9B8F6DB3381DF0433652892049293D5D28124ED3B9A5FB410A2A071FACEC5C7E980DC18EF281A53421C83B56B7A97DDD098D3F0436FD08F0D727272827BB78BA005F3F16902A3200B6CF7009F8A69DD895E87F4673D8AEB96E68B9AAA9FD300");
}

unittest
{
    import std.conv : to;
    import pham.utl.utltest;
    dgWriteln("unittest cp.biginteger.BigInteger(RSP Calculation)");

    static void check(string caseNumber, const BigInteger value, string checkedValue,
        size_t line = __LINE__)
    {
        auto s = toString(value);
        assert(s == checkedValue, caseNumber ~ " from line s: " ~ to!string(line) ~ ": " ~ s ~ " ? " ~ checkedValue);
        assert(value == BigInteger(checkedValue), caseNumber ~ " from line b: " ~ to!string(line) ~ ": " ~ s ~ " ? " ~ checkedValue);
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
