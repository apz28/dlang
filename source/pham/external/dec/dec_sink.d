module pham.external.dec.sink;

import std.algorithm.mutation : swapAt;
import std.ascii : upHexChars = hexDigits, loHexChars = lowerHexDigits;
import std.format : FormatSpec;
import std.range.primitives : isOutputRange, put;
import std.traits : isIntegral, isSomeChar, Unqual;

import pham.external.dec.decimal : fastDecode, isDecimal;
import pham.external.dec.integral : divrem, isAnyUnsignedBit, isUnsignedBit, prec;
import pham.external.dec.math : coefficientAdjust, coefficientShrink, divpow10;
import pham.external.dec.type;

nothrow @safe:

struct ShortStringBufferSize(T, ushort ShortSize)
if (ShortSize > 0 && (isSomeChar!T || isIntegral!T))
{
@safe:

public:
    this(this) nothrow pure
    {
        _longData = _longData.dup;
    }

    this(bool setShortLength)
    {
        if (setShortLength)
            this._length = ShortSize;
    }

    ref typeof(this) opAssign(scope const(T)[] values) nothrow return
    {
        clear();
        _length = values.length;
        if (_length)
        {
            if (useShortSize)
            {
                _shortData[0.._length] = values[0.._length];
            }
            else
            {
                if (_longData.length < _length)
                    _longData.length = _length;
                _longData[0.._length] = values[0.._length];
            }
        }
        return this;
    }

    ref typeof(this) opOpAssign(string op)(T c) nothrow pure return
    if (op == "~" || op == "+")
    {
        return put(c);
    }

    ref typeof(this) opOpAssign(string op)(scope const(T)[] s) nothrow pure return
    if (op == "~" || op == "+")
    {
        return put(s);
    }

    size_t opDollar() const @nogc nothrow pure
    {
        return _length;
    }

    inout(T)[] opIndex() inout nothrow pure return
    {
        return useShortSize ? _shortData[0.._length] : _longData[0.._length];
    }

    T opIndex(size_t i) const @nogc nothrow pure
    in
    {
        assert(i < length);
    }
    do
    {
        return useShortSize ? _shortData[i] : _longData[i];
    }

    ref typeof(this) opIndexAssign(T c, size_t i) return
    in
    {
        assert(i < length);
    }
    do
    {
        if (useShortSize)
            _shortData[i] = c;
        else
            _longData[i] = c;
        return this;
    }

    ref typeof(this) clear(bool setShortLength = false) nothrow pure
    {
        if (setShortLength)
        {
            _shortData[] = 0;
            _longData[] = 0;
            _length = ShortSize;
        }
        else
            _length = 0;

        return this;
    }

    inout(T)[] left(size_t len) inout nothrow pure return
    {
        if (len >= _length)
            return opIndex();
        else
            return opIndex()[0..len];
    }

    ref typeof(this) put(T c) nothrow pure return
    {
        const newLength = _length + 1;

        // Still in short?
        if (useShortSize(newLength))
            _shortData[_length++] = c;
        else
        {
            if (useShortSize)
                switchToLongData(1);
            else if (_longData.length < newLength)
                _longData.length = alignAddtionalLength(newLength);
            _longData[_length++] = c;
        }
        return this;
    }

    ref typeof(this) put(scope const(T)[] s) nothrow pure return
    {
        if (!s.length)
            return this;

        const newLength = _length + s.length;
        // Still in short?
        if (useShortSize(newLength))
        {
            _shortData[_length..newLength] = s[0..$];
        }
        else
        {
            if (useShortSize)
                switchToLongData(s.length);
            else if (_longData.length < newLength)
                _longData.length = alignAddtionalLength(newLength);
            _longData[_length..newLength] = s[0..$];
        }
        _length = newLength;
        return this;
    }

    ref typeof(this) reverse() @nogc nothrow pure
    {
        if (const len = length)
        {
            const last = len - 1;
            const steps = len / 2;
            if (useShortSize)
            {
                for (size_t i = 0; i < steps; i++)
                    _shortData.swapAt(i, last - i);
            }
            else
            {
                for (size_t i = 0; i < steps; i++)
                    _longData.swapAt(i, last - i);
            }
        }
        return this;
    }

    inout(T)[] right(size_t len) inout nothrow pure return
    {
        if (len >= _length)
            return opIndex();
        else
            return opIndex()[_length - len.._length];
    }

    static if (isSomeChar!T)
    immutable(T)[] toString() const nothrow pure
    {
        return _length != 0
            ? (useShortSize ? _shortData[0.._length].idup : _longData[0.._length].idup)
            : [];
    }

    static if (isSomeChar!T)
    ref Writer toString(Writer)(return ref Writer sink) const pure
    {
        if (_length)
            put(sink, opIndex());
        return sink;
    }

    pragma (inline, true)
    @property bool empty() const @nogc nothrow pure
    {
        return _length == 0;
    }

    pragma(inline, true)
    @property size_t length() const @nogc nothrow pure
    {
        return _length;
    }

    pragma(inline, true)
    @property static size_t shortSize() @nogc nothrow pure
    {
        return ShortSize;
    }

    pragma(inline, true)
    @property bool useShortSize() const @nogc nothrow pure
    {
        return _length <= ShortSize;
    }

    pragma(inline, true)
    @property bool useShortSize(const(size_t) checkLength) const @nogc nothrow pure
    {
        return checkLength <= ShortSize;
    }

private:
    size_t alignAddtionalLength(const(size_t) additionalLength) @nogc nothrow pure
    {
        if (additionalLength <= overReservedLength)
            return overReservedLength;
        else
            return ((additionalLength + overReservedLength - 1) / overReservedLength) * overReservedLength;
    }

    void switchToLongData(const(size_t) additionalLength) nothrow pure
    {
        const capacity = alignAddtionalLength(_length + additionalLength);
        if (_longData.length < capacity)
            _longData.length = capacity;
        if (_length)
            _longData[0.._length] = _shortData[0.._length];
    }

private:
    enum overReservedLength = 1_000u;
    size_t _length;
    T[] _longData;
    T[ShortSize] _shortData = 0;
}

template ShortStringBuffer(T)
if (isSomeChar!T || isIntegral!T)
{
    private enum overheadSize = ShortStringBufferSize!(T, 1u).sizeof;
    alias ShortStringBuffer = ShortStringBufferSize!(T, 256u - overheadSize);
}

char[] dataTypeToString(T)(return ref ShortStringBuffer!char buffer, auto const ref T value) @nogc nothrow pure @safe
if (isUnsignedBit!T)
{
    size_t i = buffer.clear(true).length;
    T.THIS v = value;
    do
    {
        const r = divrem(v, 10U);
        buffer[--i] = cast(char)('0' + cast(uint)r);
    } while (v != 0U);
    return buffer.right(buffer.length - i);
}

char[] dataTypeToString(T)(return ref ShortStringBuffer!char buffer, auto const ref T value) @nogc nothrow pure @safe
if (is(Unqual!T == ushort) || is(Unqual!T == uint) || is(Unqual!T == ulong))
{
    size_t i = buffer.clear(true).length;
    Unqual!T v = value;
    do
    {
        const r = v % 10U;
        buffer[--i] = cast(char)('0' + cast(uint)r);
        v /= 10U;
    } while (v != 0U);
    return buffer.right(buffer.length - i);
}

pragma(inline, true)
bool hasPrecision(Char)(scope const ref FormatSpec!Char spec) @nogc pure
if (isSomeChar!Char)
{
    const precision = spec.precision;
    return precision != spec.UNSPECIFIED && precision != spec.DYNAMIC && precision >= 0;
}

pragma(inline, true)
int isSize(Char)(scope const ref FormatSpec!Char spec, const(int) n, int defaultSize) @nogc pure
if (isSomeChar!Char)
{
    return n == spec.UNSPECIFIED || n == spec.DYNAMIC
        ? defaultSize
        : n;
}

/**
 * Return true if specifier is supported by Decimal format
 * Params:
 *  spec = Format specification that being tested for
 */
bool isValidDecimalSpec(Char)(scope const ref FormatSpec!Char spec) @nogc nothrow pure @safe
{
    const s = spec.spec;
    return s == 'f' || s == 'F' || s == 'e' || s == 'E' || s == 'g' || s == 'G'
        || s == 'a' || s == 'A' || s == 's' || s == 'S';
}

/**
 * Repeats sinking of value count times
 * Params:
 *  sink = Output range
 *  value = The repeating character to output range
 *  count = Indicate how many times the value for count > 0
 */
void sinkRepeat(Writer, Char)(auto scope ref Writer sink, const(Char) value, int count)
if (isOutputRange!(Writer, Char) && isSomeChar!Char)
{
    if (count <= 0)
        return;

    enum bufferSize = 30;
    Unqual!Char[bufferSize] buffer = value;
    while (count > 0)
    {
        const n = count > bufferSize ? bufferSize : count;
        put(sink, buffer[0..n]);
        count -= n;
    }
}

package(pham.external.dec):

//sinks a decimal value
void sinkDecimal(Writer, Char, D)(ref Writer sink, scope const ref FormatSpec!Char spec,
    auto const ref D decimal, const(RoundingMode) mode) @safe
if (isOutputRange!(Writer, Char) && isSomeChar!Char && isDecimal!D)
in
{
    assert(isValidDecimalSpec(spec));
}
do
{
    DataType!(D.sizeof) coefficient;
    int exponent;
    bool isNegative;

    const fx = fastDecode(decimal, coefficient, exponent, isNegative);
    if (fx == FastClass.signalingNaN)
        sinkNaN!(Writer, Char, DataType!(D.sizeof))(sink, spec, isNegative, true, coefficient, spec.spec == 'a' || spec.spec == 'A');
    else if (fx == FastClass.quietNaN)
        sinkNaN!(Writer, Char, DataType!(D.sizeof))(sink, spec, isNegative, false, coefficient, spec.spec == 'a' || spec.spec == 'A');
    else if (fx == FastClass.infinite)
        sinkInfinity!(Writer, Char)(sink, spec, decimal.isNeg);
    else
    {
        switch (spec.spec)
        {
            case 'f':
            case 'F':
            case 's':
            case 'S':
                return sinkFloat!(Writer, Char, DataType!(D.sizeof))(sink, spec, coefficient, exponent, isNegative, mode);
            case 'e':
            case 'E':
                return sinkExponential!(Writer, Char, DataType!(D.sizeof))(sink, spec, coefficient, exponent, isNegative, mode);
            case 'g':
            case 'G':
                return sinkGeneral!(Writer, Char, DataType!(D.sizeof))(sink, spec, coefficient, exponent, isNegative, mode);
            case 'a':
            case 'A':
                return sinkHexadecimal!(Writer, Char, DataType!(D.sizeof))(sink, spec, coefficient, exponent, isNegative);
            default:
                assert(0, "Unsupported format specifier: " ~ spec.spec);
        }
    }
}

//sinks %e
void sinkExponential(Writer, Char, T)(ref Writer sink, scope const ref FormatSpec!Char spec,
    const(T) coefficient, const(int) exponent, const(bool) signed, const(RoundingMode) mode,
    const(bool) skipTrailingZeros = false) nothrow @safe
if (isOutputRange!(Writer, Char) && isSomeChar!Char)
{
    int w = 3; /// N e +/-
    if (spec.flPlus || spec.flSpace || signed)
        ++w;

    Unqual!T c = coefficient;
    int ex = exponent;
    coefficientShrink(c, ex);
    int digits = prec(c);
    const int e = digits == 0 ? 0 : ex + (digits - 1);
    int requestedDecimals = floatFractionPrecision!Char(spec);
    const targetPrecision = requestedDecimals + 1;

    if (digits > targetPrecision)
    {
        divpow10(c, digits - targetPrecision, signed, mode);
        digits = prec(c);
        if (digits > targetPrecision)
            c /= 10U;
        --digits;
    }

    const bool signedExponent = e < 0;
    const uint ue = signedExponent ? -e : e;
    Unqual!Char[50] exponentBuffer;
    const exponentDigits = dumpUnsigned(exponentBuffer, ue, false);
    w += exponentDigits <= 2 ? 2 : exponentDigits;

    Unqual!Char[(T.sizeof * 8 / 3) + 1] digitsBuffer;
    digits = dumpUnsigned(digitsBuffer, c, false);

    if (requestedDecimals > digits - 1 && skipTrailingZeros)
        requestedDecimals = digits - 1;

    if (requestedDecimals || spec.flHash)
        w += requestedDecimals + 1;
    int pad = isSize!Char(spec, spec.width, w) - w;

    sinkPadLeft(sink, spec, pad);
    sinkSign(sink, spec, signed);
    sinkPadZero(sink, spec, pad);
    put(sink, digitsBuffer[$ - digits .. $ - digits + 1]);
    if (requestedDecimals || spec.flHash)
    {
        put(sink, decimalChar);
        if (digits > 1)
            put(sink, digitsBuffer[$ - digits + 1 .. $]);
        sinkRepeat(sink, '0', requestedDecimals - (digits - 1));
    }
    put(sink, spec.spec <= 'Z' ? "E" : "e");
    put(sink, signedExponent ? "-" : "+");
    if (exponentDigits < 2)
        put(sink, "0");
    put(sink, exponentBuffer[$ - exponentDigits .. $]);
    sinkPadRight!(Writer, Char)(sink, pad);
}

//sinks %f
void sinkFloat(Writer, Char, T)(ref Writer sink, scope const ref FormatSpec!Char spec,
    const(T) coefficient, const(int) exponent, const(bool) signed, const(RoundingMode) mode,
    const(bool) skipTrailingZeros = false) nothrow @safe
if (isOutputRange!(Writer, Char) && isSomeChar!Char)
{
    if (coefficient == 0U)
    {
        sinkZero!(Writer, Char)(sink, spec, signed, skipTrailingZeros);
        return;
    }

    Unqual!T c = coefficient;
    int e = exponent;
    coefficientShrink(c, e);
    int w = spec.flPlus || spec.flSpace || signed ? 1 : 0;

    Unqual!Char[250] digitsBuffer;
    Unqual!Char[50] fractionalsBuffer;

    if (e >= 0) //coefficient[0...].[0...]
    {
        const digits = dumpUnsigned(digitsBuffer, c, false);
        w += digits;
        w += e;
        const requestedDecimals = skipTrailingZeros ? 0 : floatFractionPrecision!Char(spec, 1);

        if (requestedDecimals || spec.flHash)
            w += requestedDecimals + 1;
        int pad = isSize!Char(spec, spec.width, w) - w;

        sinkPadLeft(sink, spec, pad);
        sinkSign(sink, spec, signed);
        sinkPadZero(sink, spec, pad);
        put(sink, digitsBuffer[$ - digits .. $]);
        sinkRepeat(sink, '0', e);
        if (requestedDecimals || spec.flHash)
        {
            put(sink, decimalChar);
            sinkRepeat(sink, '0', requestedDecimals);
        }
        sinkPadRight!(Writer, Char)(sink, pad);

        return;
    }

    int digits = prec(c);
    int requestedDecimals = floatFractionPrecision!Char(spec);

    if (-e < digits) //coef.ficient[0...]
    {
        const int integralDigits = digits + e;
        int fractionalDigits = digits - integralDigits;

        if (fractionalDigits > requestedDecimals)
        {
            divpow10(c, fractionalDigits - requestedDecimals, signed, mode);
            digits = prec(c);
            fractionalDigits = digits - integralDigits;
            if (fractionalDigits > requestedDecimals)
            {
                c /= 10U;
                --fractionalDigits;
            }
        }

        dumpUnsigned(digitsBuffer, c, false);
        const integralBuffer = digitsBuffer[$ - digits .. $ - fractionalDigits];
        auto fractionalBuffer = fractionalDigits ? digitsBuffer[$ - fractionalDigits .. $] : null;
        if (fractionalDigits > 1 && (skipTrailingZeros || !hasPrecision!Char(spec)))
        {
            auto n = fractionalDigits;
            while (n > 1 && fractionalBuffer[n - 1] == '0')
                n--;
            if (n != fractionalDigits)
            {
                fractionalDigits = n;
                fractionalBuffer = fractionalBuffer[0..n];
            }
        }

        if (requestedDecimals > fractionalDigits && (skipTrailingZeros || !hasPrecision!Char(spec)))
            requestedDecimals = fractionalDigits;

        w += integralDigits;
        if (requestedDecimals || spec.flHash)
            w += requestedDecimals + 1;
        int pad = isSize!Char(spec, spec.width, w) - w;

        sinkPadLeft(sink, spec, pad);
        sinkSign(sink, spec, signed);
        sinkPadZero(sink, spec, pad);
        put(sink, integralBuffer);
        if (requestedDecimals || spec.flHash)
        {
            put(sink, decimalChar);
            if (fractionalDigits)
                put(sink, fractionalBuffer);
            sinkRepeat(sink, '0', requestedDecimals - fractionalDigits);
        }
        sinkPadRight!(Writer, Char)(sink, pad);
    }
    else if (-e == digits) //0.coefficient[0...]
    {
        if (requestedDecimals > digits && (skipTrailingZeros || !hasPrecision!Char(spec)))
            requestedDecimals = digits;

        if (requestedDecimals == 0) //special case, no decimals, round
        {
            divpow10(c, digits - 1, signed, mode);
            divpow10(c, 1, signed, mode);
            w += 1;
            if (spec.flHash)
                ++w;
            int pad = isSize!Char(spec, spec.width, w) - w;

            sinkPadLeft(sink, spec, pad);
            sinkSign(sink, spec, signed);
            sinkPadZero(sink, spec, pad);
            put(sink, c != 0U ? "1": "0");
            if (spec.flHash)
                put(sink, decimalChar);
            sinkPadRight!(Writer, Char)(sink, pad);
        }
        else
        {
            w += 2;
            w += requestedDecimals;
            if (digits > requestedDecimals)
            {
                divpow10(c, digits - requestedDecimals, signed, mode);
                digits = prec(c);
                if (digits > requestedDecimals)
                {
                    c /= 10U;
                    --digits;
                }
            }
            int pad = isSize!Char(spec, spec.width, w) - w;

            sinkPadLeft(sink, spec, pad);
            sinkSign(sink, spec, signed);
            sinkPadZero(sink, spec, pad);
            put(sink, "0");
            put(sink, decimalChar);
            dumpUnsigned(digitsBuffer, c, skipTrailingZeros);
            put(sink, digitsBuffer[$ - digits .. $]);
            sinkRepeat(sink, '0', requestedDecimals - digits);
            sinkPadRight!(Writer, Char)(sink, pad);
        }
    }
    else //-e > 0.[0...][coefficient]
    {
        int zeros = -e - digits;

        if (requestedDecimals > digits - e && (skipTrailingZeros || !hasPrecision!Char(spec)))
            requestedDecimals = digits - e - 1;

        if (requestedDecimals <= zeros) //special case, coefficient does not fit
        {
            divpow10(c, digits - 1, signed, mode);
            divpow10(c, 1, signed, mode);
            if (requestedDecimals == 0)  //special case, 0 or 1
            {
                w += 1;
                int pad = isSize!Char(spec, spec.width, w) - w;

                sinkPadLeft(sink, spec, pad);
                sinkSign(sink, spec, signed);
                sinkPadZero(sink, spec, pad);
                put(sink, c != 0U ? "1": "0");
                sinkPadRight!(Writer, Char)(sink, pad);
            }
            else  //special case 0.[0..][0/1]
            {
                if (!hasPrecision!Char(spec))
                    requestedDecimals = 1;

                w += 2;
                w += requestedDecimals;
                int pad = isSize!Char(spec, spec.width, w) - w;

                sinkPadLeft(sink, spec, pad);
                sinkSign(sink, spec, signed);
                sinkPadZero(sink, spec, pad);
                put(sink, "0");
                put(sink, decimalChar);
                sinkRepeat(sink, '0', requestedDecimals - 1);
                put(sink, c != 0U ? "1": "0");
                sinkPadRight!(Writer, Char)(sink, pad);
            }
        }
        else //0.[0...]coef
        {
            if (digits > requestedDecimals - zeros)
            {
                divpow10(c, digits - (requestedDecimals - zeros), signed, mode);
                digits = prec(c);
                if (digits > requestedDecimals - zeros)
                    c /= 10U;
                digits = prec(c);
            }

            const fractionals = dumpUnsigned(fractionalsBuffer, c, skipTrailingZeros || !hasPrecision!Char(spec));
            requestedDecimals = fractionals;

            w += 2;
            w += requestedDecimals;
            int pad = isSize!Char(spec, spec.width, w) - w - zeros;

            sinkPadLeft(sink, spec, pad);
            sinkSign(sink, spec, signed);
            sinkPadZero(sink, spec, pad);
            put(sink, "0");
            put(sink, decimalChar);
            sinkRepeat(sink, '0', zeros);
            put(sink, fractionalsBuffer[$ - fractionals .. $]);
            sinkPadRight!(Writer, Char)(sink, pad);
        }
    }
}

//sinks %g
void sinkGeneral(Writer, Char, T)(ref Writer sink, scope const ref FormatSpec!Char spec,
    const(T) coefficient, const(int) exponent, const(bool) signed, const(RoundingMode) mode) nothrow @safe
if (isOutputRange!(Writer, Char) && isSomeChar!Char)
{
    const precision = generalFractionPrecision!Char(spec);
    Unqual!T c = coefficient;
    int e = exponent;
    coefficientShrink(c, e);
    coefficientAdjust(c, e, precision, signed, mode);
    if (c == 0U)
        e = 0;
    const int cp = prec(c);
    const int expe = cp > 0 ? e + cp - 1 : 0;

    if (precision > expe && expe >= -4)
    {
        FormatSpec!Char fspec = spec;
        fspec.precision = precision - 1 - expe;
        return sinkFloat!(Writer, Char, Unqual!T)(sink, fspec, coefficient, exponent, signed, mode, !fspec.flHash);
    }
    else
    {
        FormatSpec!Char espec = spec;
        espec.precision = precision - 1;
        return sinkExponential!(Writer, Char, Unqual!T)(sink, espec, coefficient, exponent, signed, mode, !espec.flHash);
    }
}

//sinks %a
void sinkHexadecimal(Writer, Char, T)(ref Writer sink, scope const ref FormatSpec!Char spec,
    auto const ref T coefficient, const(int) exponent, const(bool) signed) nothrow @safe
if (isOutputRange!(Writer, Char) && isSomeChar!Char && isAnyUnsignedBit!T)
{
    int w = 4; //0x, p, exponent sign
    if (spec.flPlus || spec.flSpace || signed)
        ++w;

    int p = prec(coefficient);
    if (p == 0)
        p = 1;

    const precision = floatFractionPrecision!Char(spec, p);
    Unqual!T c = coefficient;
    int e = exponent;

    coefficientAdjust(c, e, precision, signed, __ctfe ? RoundingMode.implicit : DecimalControl.rounding);

    Unqual!Char[(T.sizeof / 2) + 1] digitsBuffer;
    const digits = dumpUnsignedHex(digitsBuffer, c, spec.spec <= 'Z');

    const bool signedExponent = e < 0;
    const uint ex = signedExponent ? -e : e;
    Unqual!Char[prec(uint.max)] exponentBuffer;
    const exponentDigits = dumpUnsigned(exponentBuffer, ex, !hasPrecision!Char(spec));

    w += digits;
    w += exponentDigits;

    int pad = isSize!Char(spec, spec.width, w) - w;
    sinkPadLeft(sink, spec, pad);
    sinkSign(sink, spec, signed);
    put(sink, "0");
    put(sink, spec.spec <= 'Z' ? "X" : "x");
    sinkPadZero(sink, spec, pad);
    put(sink, digitsBuffer[$ - digits .. $]);
    put(sink, spec.spec < 'Z' ? "P" : "p");
    put(sink, signedExponent ? "-" : "+");
    put(sink, exponentBuffer[$ - exponentDigits .. $]);
    sinkPadRight!(Writer, Char)(sink, pad);
}

static immutable string decimalChar = ".";
enum defaultFractionPrecision = 6;

pragma(inline, true)
int floatFractionPrecision(C)(scope const ref FormatSpec!C spec,
    const(int) defaultPrecision = defaultFractionPrecision) @nogc pure
if (isSomeChar!C)
{
    const precision = spec.precision;
    return precision == spec.UNSPECIFIED || precision == spec.DYNAMIC || precision < 0
        ? defaultPrecision
        : precision;
}

pragma(inline, true)
int generalFractionPrecision(C)(scope const ref FormatSpec!C spec) @nogc pure
if (isSomeChar!C)
{
    const precision = spec.precision;
    return precision == spec.UNSPECIFIED || precision == spec.DYNAMIC
        ? defaultFractionPrecision
        : (precision <= 0 ? 1 : precision);
}

//dumps value to buffer right aligned, assumes buffer has enough space
int dumpUnsigned(C, T)(C[] buffer, auto const ref T value, bool skipTrailingZeros) @nogc pure
if (isSomeChar!C && isAnyUnsignedBit!T)
in
{
    assert(buffer.length < int.max);
    assert(buffer.length > 0 && buffer.length >= prec(value));
}
do
{
    auto i = buffer.length;
    Unqual!T v = value;
    do
    {
        auto r = divrem(v, 10U);
        buffer[--i] = cast(C)(r + cast(uint)'0');
    } while (v);

    if (skipTrailingZeros && buffer.length - i > 1 && buffer[buffer.length - 1] == '0')
    {
        ptrdiff_t j = buffer.length - 1;
        while (j >= i && buffer[j] == '0')
            j--;
        if (j != buffer.length - 1)
        {
            // all zero?
            if (j < i)
                return 1;
            // one digit left?
            else if (j == i)
            {
                buffer[buffer.length - 1] = buffer[i];
                return 1;
            }
            else
            {
                // move digits to the right
                auto p = buffer.length;
                while (j >= i)
                {
                    buffer[--p] = buffer[j];
                    j--;
                }
                i = p;
            }
        }
    }

    return cast(int)(buffer.length - i);
}

//static immutable char[] loHexChars = ['0', '1', '2', '3', '4', '5', '6', '7', '8', '9', 'a', 'b', 'c', 'd', 'e', 'f'];
//static immutable char[] upHexChars = ['0', '1', '2', '3', '4', '5', '6', '7', '8', '9', 'A', 'B', 'C', 'D', 'E', 'F'];

//dumps value to buffer right aligned, assumes buffer has enough space
int dumpUnsignedHex(C, T)(C[] buffer, auto const ref T value, const(bool) uppercase = true) @nogc pure
if (isSomeChar!C && isAnyUnsignedBit!T)
in
{
    assert(buffer.length < int.max);
    assert(buffer.length > 0 && buffer.length >= prec(value));
}
do
{
    const chars = uppercase ? upHexChars : loHexChars;
    auto i = buffer.length;
    Unqual!T v = value;
    do
    {
        const digit = (cast(uint)v & 0xFU);
        buffer[--i] = cast(C)(chars[digit]);
        v >>= 4;
    } while (v);
    return cast(int)(buffer.length - i);
}

//sinks +/-/space
void sinkSign(Writer, Char)(auto scope ref Writer sink, scope const ref FormatSpec!Char spec, const(bool) signed)
if (isOutputRange!(Writer, Char) && isSomeChar!Char)
{
    if (!signed && spec.flPlus)
        put(sink, "+");
    else if (!signed && spec.flSpace)
        put(sink, " ");
    else if (signed)
        put(sink, "-");
}

//pads left according to spec
void sinkPadLeft(Writer, Char)(auto scope ref Writer sink, scope const ref FormatSpec!Char spec, ref int pad)
if (isOutputRange!(Writer, Char) && isSomeChar!Char)
{
    if (pad > 0 && !spec.flDash && !spec.flZero)
    {
        sinkRepeat(sink, ' ', pad);
        pad = 0;
    }
}

//zero pads left according to spec
void sinkPadZero(Writer, Char)(auto scope ref Writer sink, scope const ref FormatSpec!Char spec, ref int pad)
if (isOutputRange!(Writer, Char) && isSomeChar!Char)
{
    if (pad > 0 && spec.flZero && !spec.flDash)
    {
        sinkRepeat(sink, '0', pad);
        pad = 0;
    }
}

//pads right according to spec
void sinkPadRight(Writer, Char)(auto scope ref Writer sink, ref int pad)
if (isOutputRange!(Writer, Char) && isSomeChar!Char)
{
    if (pad > 0)
    {
        sinkRepeat(sink, ' ', pad);
        pad = 0;
    }
}

//sinks +/-(s)nan;
void sinkNaN(Writer, Char, T)(auto scope ref Writer sink, scope const ref FormatSpec!Char spec, const(bool) signed,
    const(bool) signaling, T payload, bool hex)
if (isOutputRange!(Writer, Char) && isSomeChar!Char)
{
    FormatSpec!Char nanspec = spec;
    nanspec.flZero = false;
    nanspec.flHash = false;
    Char[100] digitsBuffer;
    ptrdiff_t digits;
    if (payload)
    {
        if (hex)
            digits = dumpUnsignedHex(digitsBuffer, payload, nanspec.spec < 'Z');
        else
            digits = dumpUnsigned(digitsBuffer, payload, false);
    }
    int w = signaling ? 4 : 3;
    if (payload)
    {
        if (hex)
            w += digits + 4;
        else
            w += digits + 2;
    }
    if (nanspec.flPlus || nanspec.flSpace || signed)
        ++w;
    int pad = isSize!Char(nanspec, nanspec.width, w) - w;
    sinkPadLeft!(Writer, Char)(sink, nanspec, pad);
    sinkSign!(Writer, Char)(sink, nanspec, signed);
    if (signaling)
        put(sink, nanspec.spec < 'Z' ? "S" : "s");
    put(sink, nanspec.spec < 'Z' ? "NAN" : "nan");
    if (payload)
    {
        put(sink, "[");
        if (hex)
        {
            put(sink, "0");
            put(sink, nanspec.spec < 'Z' ? "X" : "x");
        }
        put(sink, digitsBuffer[$ - digits .. $ - 1]);
        put(sink, "]");
    }
    sinkPadRight!(Writer, Char)(sink, pad);
}

//sinks +/-(s)inf;
void sinkInfinity(Writer, Char)(auto scope ref Writer sink, scope const ref FormatSpec!Char spec, const(bool) signed)
if (isOutputRange!(Writer, Char) && isSomeChar!Char)
{
    FormatSpec!Char infspec = spec;
    infspec.flZero = false;
    infspec.flHash = false;
    const w = infspec.flPlus || infspec.flSpace || signed ? 4 : 3;
    int pad = isSize!Char(infspec, infspec.width, w) - w;
    sinkPadLeft!(Writer, Char)(sink, infspec, pad);
    sinkSign!(Writer, Char)(sink, infspec, signed);
    put(sink, infspec.spec < 'Z' ? "INF" : "inf");
    sinkPadRight!(Writer, Char)(sink, pad);
}

//sinks 0
void sinkZero(Writer, Char)(auto scope ref Writer sink, scope const ref FormatSpec!Char spec, const(bool) signed,
    const(bool) skipTrailingZeros)
if (isOutputRange!(Writer, Char) && isSomeChar!Char)
{
    const requestedDecimals = skipTrailingZeros ? 0 : floatFractionPrecision!Char(spec, 1);

    int w = requestedDecimals == 0 ? 1 : requestedDecimals + 2;
    if (requestedDecimals == 0 && spec.flHash)
        ++w;
    if (spec.flPlus || spec.flSpace || signed)
        ++w;
    int pad = isSize!Char(spec, spec.width, w) - w;
    sinkPadLeft!(Writer, Char)(sink, spec, pad);
    sinkSign!(Writer, Char)(sink, spec, signed);
    sinkPadZero!(Writer, Char)(sink, spec, pad);
    put(sink, "0");
    if (requestedDecimals || spec.flHash)
    {
        put(sink, decimalChar);
        sinkRepeat(sink, '0', requestedDecimals);
    }
    sinkPadRight!(Writer, Char)(sink, pad);
}

unittest // dumpUnsigned
{
    char[] buffer;
    buffer.length = 100;

    auto n = dumpUnsigned!(char, uint)(buffer, 1u, false);
    assert(n == 1);
    assert(buffer[$-n..$] == "1");

    n = dumpUnsigned!(char, uint)(buffer, 1234567u, false);
    assert(n == 7);
    assert(buffer[$-n..$] == "1234567");

    n = dumpUnsigned!(char, uint)(buffer, 0u, false);
    assert(n == 1);
    assert(buffer[$-n..$] == "0");

    n = dumpUnsigned!(char, uint)(buffer, 12345000u, false);
    assert(n == 8);
    assert(buffer[$-n..$] == "12345000");

    n = dumpUnsigned!(char, uint)(buffer, 1u, true);
    assert(n == 1);
    assert(buffer[$-n..$] == "1");

    n = dumpUnsigned!(char, uint)(buffer, 1234567u, true);
    assert(n == 7);
    assert(buffer[$-n..$] == "1234567");

    n = dumpUnsigned!(char, uint)(buffer, 0u, true);
    assert(n == 1);
    assert(buffer[$-n..$] == "0");

    n = dumpUnsigned!(char, uint)(buffer, 12345000u, true);
    assert(n == 5);
    assert(buffer[$-n..$] == "12345");
}

@safe unittest // ShortStringBufferSize
{
    alias TestBuffer = ShortStringBufferSize!(char, 5);

    TestBuffer s;
    assert(s.length == 0);
    s.put('1');
    assert(s.length == 1);
    s.put("234");
    assert(s.length == 4);
    assert(s.toString() == "1234");
    assert(s[] == "1234");
    s.clear();
    assert(s.length == 0);
    s.put("abc");
    assert(s.length == 3);
    assert(s.toString() == "abc");
    assert(s[] == "abc");
    assert(s.left(1) == "a");
    assert(s.left(10) == "abc");
    assert(s.right(2) == "bc");
    assert(s.right(10) == "abc");
    s.put("defghijklmnopqrstuvxywz");
    assert(s.length == 26);
    assert(s.toString() == "abcdefghijklmnopqrstuvxywz");
    assert(s[] == "abcdefghijklmnopqrstuvxywz");
    assert(s.left(5) == "abcde");
    assert(s.left(20) == "abcdefghijklmnopqrst");
    assert(s.right(5) == "vxywz");
    assert(s.right(20) == "ghijklmnopqrstuvxywz");

    TestBuffer s2;
    s2 ~= s[];
    assert(s2.length == 26);
    assert(s2.toString() == "abcdefghijklmnopqrstuvxywz");
    assert(s2[] == "abcdefghijklmnopqrstuvxywz");
}

nothrow @safe unittest // ShortStringBufferSize.reverse
{
    ShortStringBufferSize!(int, 3) a;

    a.clear().put([1, 2]);
    assert(a.reverse()[] == [2, 1]);

    a.clear().put([1, 2, 3, 4, 5]);
    assert(a.reverse()[] == [5, 4, 3, 2, 1]);
}

unittest // dataTypeToString
{
    import pham.external.dec.integral : uint128;
    ShortStringBuffer!char buffer;

    assert(dataTypeToString(buffer, 0U) == "0");
    assert(dataTypeToString(buffer, 12345U) == "12345");
    assert(dataTypeToString(buffer, uint128("10000000000000000000000000")) == "10000000000000000000000000");
}
