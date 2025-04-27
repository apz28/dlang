module pham.external.dec.dec_decimal;

import std.math : FloatingPointControl, getNaNPayload, ieeeFlags,
    ldexp, resetIeeeFlags, signStd = signbit;
import std.math.traits : isNaN;
import std.range.primitives : ElementType, isInputRange, isOutputRange, put;
import std.traits : isFloatingPoint, isIntegral, isSigned, isSomeChar, isSomeString,
    isUnsigned, Unqual, Unsigned;

import pham.external.dec.dec_compare;
import pham.external.dec.dec_integral;
import pham.external.dec.dec_integral : fromBigEndianBytesImpl = fromBigEndianBytes;
import pham.external.dec.dec_math;
import pham.external.dec.dec_numeric;
import pham.external.dec.dec_parse;
import pham.external.dec.dec_range;
public import pham.external.dec.dec_type;

version(D_BetterC) {}
else
{
  public import std.format : FormatSpec;
  import pham.external.dec.dec_sink;
}

private alias fma = pham.external.dec.dec_integral.fma;

version(Windows)
{
    public import core.sys.windows.wtypes: DECIMAL;
}
else
{
    struct DECIMAL
    {
        ushort wReserved;
        struct
        {
            ubyte scale;
            ubyte sign;
            enum ubyte DECIMAL_NEG = 0x80;
        }
        uint Hi32;
        union
        {
            struct
            {
                uint Lo32;
                uint Mid32;
            }
            ulong Lo64;
        }
    }
}

int maxPrecision(T)() @nogc nothrow pure @safe
if (isFloatingPoint!T)
{
    alias UT = Unqual!T;

    static if (is(UT == float))
        return 9;
    else static if (is(UT == double))
        return 17;
    else static if (is(UT == real))
        return 21;
    else
        static assert(0, "Unsupport system for " ~ __FUNCTION__ ~ "." ~ T.stringof);
}

/**
_* Decimal floating-point computer numbering format that occupies 4, 8 or 16 bytes in computer memory.
 */
struct Decimal(int Bytes)
if (Bytes == 4 || Bytes == 8 || Bytes == 16)
{
private:
    alias D = typeof(this);
    enum explicitModeTraps = ExceptionFlags.invalidOperation | ExceptionFlags.overflow | ExceptionFlags.underflow;

public:
    enum PRECISION      = precisionOf(Bytes);        //7, 16, 34
    enum EMAX           = 3 * (2 ^^ (Bytes * 8 / 16 + 3));    //96, 384, 6144
    enum EXP_BIAS       = EMAX + PRECISION - 2;          //101, 398, 6176
    enum EXP_MIN        = -EXP_BIAS;
    enum EXP_MAX        = EMAX - PRECISION + 1;          //90, 369, 6111
    enum COEF_MAX       = pow10!U[PRECISION] - 1U;
    enum COEF_MAX_RAW   = MASK_COE2 | MASK_COEX;

    enum dig            = PRECISION;
    enum epsilon        = buildin(U(1U), -PRECISION + 1, false);
    enum infinity       = buildin(MASK_INF, MASK_NONE, MASK_NONE);
    enum max            = buildin(COEF_MAX, EXP_MAX, false);
    enum max_10_exp     = EMAX;
    enum max_exp        = cast(int)(max_10_exp / LOG10_2);
    enum mant_dig       = trailingBits;
    enum min            = buildin(COEF_MAX, EXP_MAX, true);
    enum min_10_exp     = -(max_10_exp - 1);
    enum min_exp        = cast(int)(min_10_exp / LOG10_2);
    enum min_normal     = buildin(U(1U), min_10_exp, false);
    enum nan            = qNaN;
    enum negInfinity    = buildin(MASK_INF, MASK_NONE, MASK_SGN);
    enum negOne         = buildin(U(1U), 0, true);
    enum negQNaN        = buildin(MASK_QNAN, MASK_NONE, MASK_SGN);
    enum negSNaN        = buildin(MASK_SNAN, MASK_NONE, MASK_SGN);
    enum one            = buildin(U(1U), 0, false);
    enum qNaN           = buildin(MASK_QNAN, MASK_NONE, MASK_NONE);
    enum sNaN           = buildin(MASK_SNAN, MASK_NONE, MASK_NONE);
    enum zero           = buildin(U(0U), 0, false);

    enum E              = fromBigEndianBytes(SEnumBytes!Bytes.s_E); // buildin(s_E);
    enum PI             = fromBigEndianBytes(SEnumBytes!Bytes.s_PI); // buildin(s_PI);
    enum LN10           = fromBigEndianBytes(SEnumBytes!Bytes.s_LN10); // buildin(s_LN10);
    enum LOG2T          = fromBigEndianBytes(SEnumBytes!Bytes.s_LOG2T); // buildin(s_LOG2T);
    enum LOG2E          = fromBigEndianBytes(SEnumBytes!Bytes.s_LOG2E); // buildin(s_LOG2E);
    enum LOG2           = fromBigEndianBytes(SEnumBytes!Bytes.s_LOG2); // buildin(s_LOG2);
    enum LOG10E         = fromBigEndianBytes(SEnumBytes!Bytes.s_LOG10E); // buildin(s_LOG10E);
    enum LN2            = fromBigEndianBytes(SEnumBytes!Bytes.s_LN2); // buildin(s_LN2);

    ///always 10 for _decimal data types
    @IEEECompliant("radix", 25)
    enum radix          = 10;

    /**
    Constructs a Decimal data type using the specified _value
    Params:
        value = any integral, char, bool, floating point, decimal, string or character range _value
    Exceptions:
        $(BOOKTABLE,
            $(TR $(TH Data type) $(TH Invalid) $(TH Overflow) $(TH Underflow) $(TH Inexact))
            $(TR $(TD integral)  $(TD        ) $(TD         ) $(TD          ) $(TD ✓     ))
            $(TR $(TD char    )  $(TD        ) $(TD         ) $(TD          ) $(TD ✓     ))
            $(TR $(TD float   )  $(TD        ) $(TD ✓      ) $(TD ✓       ) $(TD ✓     ))
            $(TR $(TD bool    )  $(TD        ) $(TD         ) $(TD          ) $(TD        ))
            $(TR $(TD decimal )  $(TD        ) $(TD ✓      ) $(TD ✓       ) $(TD ✓     ))
            $(TR $(TD string  )  $(TD ✓     ) $(TD ✓      ) $(TD ✓       ) $(TD ✓     ))
            $(TR $(TD range   )  $(TD ✓     ) $(TD ✓      ) $(TD ✓       ) $(TD ✓     ))
        )
    Using_integral_values:
        ---
        auto a = Decimal32(112);       //represented as 112 x 10^^0;
        auto b = Decimal32(123456789); //inexact, represented as 1234568 * x 10^^2
        ---
    Using_floating_point_values:
        ---
        auto a = Decimal32(1.23);
        //inexact, represented as 123 x 10^^-2,
        //because floating point data cannot exactly represent 1.23
        //in fact 1.23 as float is 1.230000019073486328125
        auto b = Decimal64(float.nan);
        ---
    Using_other_decimal_values:
        ---
        auto a = Decimal32(Decimal64(10));
        auto b = Decimal64(a);
        auto c = Decimal64(Decimal128.nan);
        ---
    Using_strings_or_ranges:
        A _decimal value can be defined based on _decimal, scientific or hexadecimal representation:
        $(UL
            $(LI values are rounded away from zero in case of precision overflow;)
            ---
            auto d = Decimal32("2.3456789")
            //internal representation will be 2.345679
            //because Decimal32 has a 7-digit precision
            ---
            $(LI the exponent in hexadecimal notation is 10-based;)
            ---
            auto d1 = Decimal64("0x00003p+21");
            auto d2 = Decimal64("3e+21");
            assert(d1 == d2);
            ---
            $(LI the hexadecimal notation doesn't have any _decimal point,
                because there is no leading 1 as for binary floating point values;)
            $(LI there is no octal notation, any leading zero before the decimal point is ignored;)
            $(LI digits can be grouped using underscores;)
            $(LI case insensitive special values are accepted: $(B nan, qnan, snan, inf, infinity);)
            $(LI there is no digit count limit for _decimal representation, very large values are rounded and adjusted by
                increasing the 10-exponent;)
            ---
            auto d1 = Decimal32("123_456_789_123_456_789_123_456_789_123"); //30 digits
            //internal representation will be 1.234568 x 10^^30
            ---
            $(LI $(B NaN) payloads can be defined betwen optional brackets ([], (), {}, <>).
            The payload is unsigned and is accepted in decimal or hexadecimal format;)
        )
            ---
            auto d = Decimal32("10");              //integral
            auto e = Decimal64("125.43")           //floating point
            auto f = Decimal128("123.456E-32");    //scientific
            auto g = Decimal32("0xABCDEp+21");     //hexadecimal 0xABCD * 10^^21
            auto h = Decimal64("NaN1234");         //$(B NaN) with 1234 payload
            auto i = Decimal128("sNaN<0xABCD>")    //signaling $(B NaN) with a 0xABCD payload
            auto j = Decimal32("inf");             //infinity
            ---
    Using_char_or_bool_values:
        These constructors are provided only from convenience, and to
        offer support for conversion function $(PHOBOS conv, to, to).
        Char values are cast to unsigned int.
        Bool values are converted to 0.0 (false) or 1.0 (true)
        ---
        auto a = Decimal32(true); //1.0
        auto b = Decimal32('a');  //'a' ascii code (97)

        auto c = false.to!Decimal32(); //phobos to!(bool, Decimal32)
        auto d = 'Z'.to!Decimal128();  //phobos to!(char, Decimal128)
        ---
    */
    @IEEECompliant("convertFormat", 22)
    @IEEECompliant("convertFromDecimalCharacter", 22)
    @IEEECompliant("convertFromHexCharacter", 22)
    @IEEECompliant("convertFromInt", 21)
    @IEEECompliant("decodeBinary", 23)
    this(T)(const auto ref T value) @safe
    if (isSomeString!T || (isInputRange!T && isSomeChar!(ElementType!T)))
    {
        ExceptionFlags flags;
        static if (isSomeString!T)
        {
            const valid = packString(value, flags,
                            __ctfe ? PRECISION : DecimalControl.precision,
                            __ctfe ? RoundingMode.implicit : DecimalControl.rounding);
        }
        else //static if (isInputRange!T && isSomeChar!(ElementType!T))
        {
            const valid = packRange(value, flags,
                            __ctfe ? PRECISION : DecimalControl.precision,
                            __ctfe ? RoundingMode.implicit : DecimalControl.rounding);
        }

        if (!valid)
        {
            static if (isSomeString!T)
            {
                import std.conv : to;
                DecimalControl.throwFlags(ExceptionFlags.invalidOperation, value.to!string());
            }
            else
                DecimalControl.throwFlags(ExceptionFlags.invalidOperation);
        }

        if (!__ctfe)
        {
            static if (isSomeString!T)
            {
                import std.conv : to;
                DecimalControl.raiseFlags(flags, value.to!string());
            }
            else
                DecimalControl.raiseFlags(flags);
        }
    }

    ///ditto
    this(T)(const auto ref T value, const(RoundingMode) mode) @safe
    if (isSomeString!T || (isInputRange!T && isSomeChar!(ElementType!T)))
    {
        ExceptionFlags flags;
        static if (isSomeString!T)
        {
            const valid = packString(value, flags, PRECISION, mode);
        }
        else //static if (isInputRange!T && isSomeChar!(ElementType!T) && !isSomeString!T)
        {
            const valid = packRange(value, flags, PRECISION, mode);
        }

        if (!valid)
        {
            static if (isSomeString!T)
            {
                import std.conv : to;
                DecimalControl.throwFlags(ExceptionFlags.invalidOperation, value.to!string());
            }
            else
                DecimalControl.throwFlags(ExceptionFlags.invalidOperation);
        }

        if (!__ctfe)
        {
            static if (isSomeString!T)
            {
                import std.conv : to;
                DecimalControl.checkFlags(explicitModeTraps, flags, value.to!string());
            }
            else
                DecimalControl.checkFlags(explicitModeTraps, flags);
        }
    }

    ///ditto
    this(T)(const auto ref T value)
    if (!(isSomeString!T || (isInputRange!T && isSomeChar!(ElementType!T))))
    {
        static if (isIntegral!T)
        {
            const flags = packIntegral(value,
                            __ctfe ? PRECISION : DecimalControl.precision,
                            __ctfe ? RoundingMode.implicit : DecimalControl.rounding);

            static if (D.sizeof <= T.sizeof)
            if (!__ctfe)
                DecimalControl.raiseFlags(flags);
        }
        else static if (isFloatingPoint!T)
        {
            const flags = packFloatingPoint(value,
                            __ctfe ? PRECISION : DecimalControl.precision,
                            __ctfe ? RoundingMode.implicit : DecimalControl.rounding,
                            0);

            static if (D.sizeof <= T.sizeof)
            if (!__ctfe)
                DecimalControl.raiseFlags(flags);
        }
        else static if (isDecimal!T)
        {
            const flags = decimalToDecimal(value, this,
                            __ctfe ? PRECISION : DecimalControl.precision,
                            __ctfe ? RoundingMode.implicit : DecimalControl.rounding);

            static if (D.sizeof < T.sizeof)
            if (!__ctfe)
                DecimalControl.raiseFlags(flags);
        }
        else static if (isSomeChar!T)
        {
            const flags = packIntegral(cast(uint)value,
                            __ctfe ? PRECISION : DecimalControl.precision,
                            __ctfe ? RoundingMode.implicit : DecimalControl.rounding);

            static if (D.sizeof <= uint.sizeof)
            if (!__ctfe)
                DecimalControl.raiseFlags(flags);
        }
        else static if (is(T: D))
            this.data = value.data;
        else static if (is(T: bool))
            this.data = value ? one.data : zero.data;
        else
            static assert(0, "Cannot convert expression of type '" ~ T.stringof ~ "' to '" ~ D.stringof ~ "'");
    }

    /** ditto
     * Ignore the DecimalControl flags because explicitly rounding request
     * Params:
     *  mode = Rounding mode
     */
    this(T)(const auto ref T value, const(RoundingMode) mode) pure @safe
    if (isIntegral!T || isDecimal!T || isSomeChar!T)
    {
        static if (isIntegral!T)
        {
            const flags = packIntegral(value, PRECISION, mode);

            static if (D.sizeof <= T.sizeof)
            if (!__ctfe)
                DecimalControl.checkFlags(explicitModeTraps, flags);
        }
        else static if (isDecimal!T)
        {
            const flags = decimalToDecimal(value, this, PRECISION, mode);

            static if (D.sizeof < T.sizeof)
            if (!__ctfe)
                DecimalControl.checkFlags(explicitModeTraps, flags);
        }
        else // isSomeChar!T
        {
            const flags = packIntegral(cast(uint)value, PRECISION, mode);

            static if (D.sizeof <= uint.sizeof)
            if (!__ctfe)
                DecimalControl.checkFlags(explicitModeTraps, flags);
        }
    }

    /** ditto
     * Ignore the flags because explicitly fractional scale & rounding request
     * Params:
     *  maxFractionalDigits = perform round-up/truncate at specified fractional position
     *                        if the value <= 0 or value > PRECESION will be ignore
     *                        This enable construct Decimal values will make it work for equal/compare
     *                        Ex:  Decimal64("34567.89") vs Decimal64(34567.89) => won't be matched because of different rounding
     *                             Decimal64("34567.89") vs Decimal64(34567.89, 2) => matched
     *  mode = Rounding mode
     */
    this(T)(const auto ref T value, const(RoundingMode) mode, const(int) maxFractionalDigits) pure @safe
    if (isFloatingPoint!T)
    {
        const flags = packFloatingPoint(value, PRECISION, mode, maxFractionalDigits);

        static if (D.sizeof <= T.sizeof)
        if (!__ctfe)
            DecimalControl.checkFlags(explicitModeTraps, flags);
    }

    /**
    Implementation of assignnment operator. It supports the same semantics as the constructor.
    */
    @IEEECompliant("copy", 23)
    auto ref opAssign(T)(const auto ref T value)
    {
        // Allow @nogc/nothrow/pure assignment
        static if (isDecimal!T && D.sizeof == T.sizeof)
            this.data = value.data;
        else
        {
            auto result = Unqual!D(value);
            this.data = result.data;
        }
    }

    /**
    Implementation of cast operator. Supported casts: integral, floating point, _decimal, char, bool
    Exceptions:
        $(BOOKTABLE,
            $(TR $(TH Data type) $(TH Invalid) $(TH Overflow) $(TH Underflow) $(TH Inexact))
            $(TR $(TD integral)  $(TD      ✓) $(TD ✓      ) $(TD ✓       ) $(TD ✓     ))
            $(TR $(TD char    )  $(TD      ✓) $(TD ✓      ) $(TD ✓       ) $(TD ✓     ))
            $(TR $(TD float   )  $(TD        ) $(TD ✓      ) $(TD ✓       ) $(TD ✓     ))
            $(TR $(TD bool    )  $(TD        ) $(TD         ) $(TD          ) $(TD        ))
            $(TR $(TD decimal )  $(TD        ) $(TD ✓      ) $(TD ✓       ) $(TD ✓     ))
        )
    */
    @IEEECompliant("convertFormat", 22)
    @IEEECompliant("encodeBinary", 23)
    T opCast(T)() const @nogc nothrow
    {
        Unqual!T result;
        static if (is(T: D))
            result = this;
        else static if (is(D: Decimal32) && (is(T: Decimal64) || is(T: Decimal128)))
            decimalToDecimal(this, result, T.PRECISION, RoundingMode.implicit);
        else static if (is(D: Decimal64) && is(T: Decimal128))
            decimalToDecimal(this, result, T.PRECISION, RoundingMode.implicit);
        else static if (isDecimal!T)
        {
            const flags = decimalToDecimal(this, result,
                            __ctfe ? T.PRECISION : DecimalControl.precision,
                            __ctfe ? RoundingMode.implicit : DecimalControl.rounding);
            if (!__ctfe)
                DecimalControl.setFlags(flags);
        }
        else static if (isFloatingPoint!T)
        {
            const flags = decimalToFloat(this, result,
                            __ctfe ? RoundingMode.implicit : DecimalControl.rounding);

            static if (D.sizeof > T.sizeof)
            if (!__ctfe)
                DecimalControl.setFlags(flags);
        }
        else static if (isUnsigned!T)
        {
            const flags = decimalToUnsigned(this, result,
                            __ctfe ? RoundingMode.implicit : DecimalControl.rounding);

            static if (D.sizeof > T.sizeof)
            if (!__ctfe)
                DecimalControl.setFlags(flags);
        }
        else static if (isIntegral!T)
        {
            const flags = decimalToSigned(this, result,
                            __ctfe ? RoundingMode.implicit : DecimalControl.rounding);

            static if (D.sizeof > T.sizeof)
            if (!__ctfe)
                DecimalControl.setFlags(flags);
        }
        else static if (isSomeChar!T)
        {
            uint r;
            const flags = decimalToUnsigned(this, r,
                            __ctfe ? RoundingMode.implicit : DecimalControl.rounding);
            result = cast(Unqual!T)r;
            if (!__ctfe)
                DecimalControl.setFlags(flags);
        }
        else static if (is(T: bool))
            result = !this.isZero;
        else
            static assert(0, "Cannot cast a value of type '" ~ Unqual!D.stringof ~ "' to '" ~ Unqual!T.stringof ~ "'");

        return result;
    }

    /**
    Implementation of +/- unary operators. These operations are silent, no exceptions are thrown
    */
    @safe pure nothrow @nogc
    auto opUnary(string op: "+")() const
    {
        return this;
    }

    ///ditto
    @IEEECompliant("negate", 23)
    @safe pure nothrow @nogc
    auto opUnary(string op: "-")() const
    {
        D result = this;
        static if (Bytes == 16)
            result.data.hi ^= D.MASK_SGN.hi;
        else
            result.data ^= D.MASK_SGN;
        return result;
    }

    /**
    Implementation of ++/-- unary operators.
    Exceptions:
        $(BOOKTABLE,
            $(TR $(TH Value) $(TH ++/-- ) $(TH Invalid) $(TH Overflow) $(TH Inexact))
            $(TR $(TD $(B NaN)  ) $(TD $(B NaN)   ) $(TD ✓     ) $(TD         ) $(TD        ))
            $(TR $(TD ±∞   ) $(TD ±∞    ) $(TD        ) $(TD         ) $(TD        ))
            $(TR $(TD any  ) $(TD any   ) $(TD        ) $(TD ✓      ) $(TD ✓     ))
        )
    */
    auto ref opUnary(string op: "++")() @safe
    {
        const flags = decimalInc(this,
                        __ctfe ? 0 : DecimalControl.precision,
                        __ctfe ? RoundingMode.implicit : DecimalControl.rounding);
        if (!__ctfe)
            DecimalControl.raiseFlags(flags);
        return this;
    }

    ///ditto
    auto ref opUnary(string op: "--")() @safe
    {
        const flags = decimalDec(this,
                        __ctfe ? 0 : DecimalControl.precision,
                        __ctfe ? RoundingMode.implicit : DecimalControl.rounding);
        if (!__ctfe)
            DecimalControl.raiseFlags(flags);
        return this;
    }

    /**
     * Implementation of == operator. This operation is silent, no exceptions are thrown.
     * Supported types : decimal, floating point, integral, char
     */
    @IEEECompliant("compareQuietEqual", 24)
    @IEEECompliant("compareQuietNotEqual", 24)
    bool opEquals(T)(const auto ref T value) const @nogc nothrow @safe
    {
        static if (isDecimal!T || isIntegral!T)
        {
            return isEqual(this, value);
        }
        else static if (isFloatingPoint!T)
        {
            enum fltPrecision = maxPrecision!T();
            const decPrecision = __ctfe ? PRECISION : DecimalControl.precision;
            return isEqual(this, value,
                    decPrecision > fltPrecision ? fltPrecision : decPrecision,
                    __ctfe ? RoundingMode.implicit : DecimalControl.rounding,
                    0);
        }
        else static if (isSomeChar!T)
            return opEquals(cast(uint)value);
        else
            static assert(0, "Cannot compare values of type '" ~ Unqual!D.stringof ~ "' and '" ~ Unqual!T.stringof ~ "'");
    }

    /**
    Implementation of comparison operator.
    Supported types : _decimal, floating point, integral, char
    $(BOOKTABLE,
            $(TR $(TH this) $(TH Value) $(TH Result)    $(TH Invalid))
            $(TR $(TD $(B NaN) ) $(TD any  ) $(TD $(B NaN)   )    $(TD ✓     ))
            $(TR $(TD any ) $(TD $(B NaN)  ) $(TD $(B NaN)   )    $(TD ✓     ))
            $(TR $(TD any ) $(TD any  ) $(TD ±1.0, 0.0) $(TD        ))
        )
    */
    @IEEECompliant("compareSignalingGreater", 24)
    @IEEECompliant("compareSignalingGreaterEqual", 24)
    @IEEECompliant("compareSignalingGreaterUnordered", 24)
    @IEEECompliant("compareSignalingLess", 24)
    @IEEECompliant("compareSignalingLessEqual", 24)
    @IEEECompliant("compareSignalingLessUnordered", 24)
    @IEEECompliant("compareSignalingNotGreater", 24)
    @IEEECompliant("compareSignalingNotLess", 24)
    float opCmp(T)(const auto ref T value) const @nogc nothrow @safe
    {
        static if (isDecimal!T || isIntegral!T)
            return cmp(this, value);
        else static if (isFloatingPoint!T)
        {
            enum fltPrecision = maxPrecision!T();
            const decPrecision = __ctfe ? PRECISION : DecimalControl.precision;
            return cmp(this, value,
                    decPrecision > fltPrecision ? fltPrecision : decPrecision,
                    __ctfe ? RoundingMode.implicit : DecimalControl.rounding,
                    0);
        }
        else static if (isSomeChar!T)
            return cmp(this, cast(uint)value);
        else
            static assert(0, "Cannot compare values of type '" ~ Unqual!D.stringof ~ "' and '" ~ Unqual!T.stringof ~ "'");
    }

    /**
    Implementation of binary and assignment operators (+, -, *, /, %, ^^).
    Returns:
        the widest _decimal value as result of the operation
    Supported_types:
        _decimal, floating point, integral, char
    Exceptions:
    $(BOOKTABLE,
        $(TR $(TH Left) $(TH Op) $(TH Right) $(TH Result) $(TH Invalid) $(TH Div0) $(TH Overflow) $(TH Underflow) $(TH Inexact))
        $(TR $(TD $(B NaN)) $(TD any) $(TD any) $(TD $(B NaN))      $(TD ✓     ) $(TD     ) $(TD         ) $(TD         )  $(TD        ))
        $(TR $(TD any) $(TD any) $(TD $(B NaN)) $(TD $(B NaN))      $(TD ✓     ) $(TD     ) $(TD         ) $(TD         )  $(TD        ))
        $(TR $(TD +∞) $(TD +) $(TD -∞) $(TD $(B NaN))          $(TD ✓     ) $(TD     ) $(TD         ) $(TD         )  $(TD        ))
        $(TR $(TD +∞) $(TD +) $(TD any) $(TD +∞)          $(TD        ) $(TD     ) $(TD         ) $(TD         )  $(TD        ))
        $(TR $(TD any) $(TD +) $(TD +∞) $(TD +∞)          $(TD        ) $(TD     ) $(TD         ) $(TD         )  $(TD        ))
        $(TR $(TD -∞) $(TD +) $(TD +∞) $(TD $(B NaN))          $(TD ✓     ) $(TD     ) $(TD         ) $(TD         )  $(TD        ))
        $(TR $(TD -∞) $(TD +) $(TD any) $(TD -∞)          $(TD        ) $(TD     ) $(TD         ) $(TD         )  $(TD        ))
        $(TR $(TD any) $(TD +) $(TD -∞) $(TD -∞)          $(TD        ) $(TD     ) $(TD         ) $(TD         )  $(TD        ))
        $(TR $(TD any) $(TD +) $(TD any) $(TD any)        $(TD        ) $(TD     ) $(TD ✓      ) $(TD ✓      )  $(TD ✓     ))
        $(TR $(TD +∞) $(TD -) $(TD +∞) $(TD $(B NaN))          $(TD ✓     ) $(TD     ) $(TD         ) $(TD         )  $(TD        ))
        $(TR $(TD +∞) $(TD -) $(TD any) $(TD +∞)          $(TD        ) $(TD     ) $(TD         ) $(TD         )  $(TD        ))
        $(TR $(TD any) $(TD -) $(TD +∞) $(TD -∞)          $(TD        ) $(TD     ) $(TD         ) $(TD         )  $(TD        ))
        $(TR $(TD -∞) $(TD -) $(TD -∞) $(TD $(B NaN))          $(TD ✓     ) $(TD     ) $(TD         ) $(TD         )  $(TD        ))
        $(TR $(TD -∞) $(TD -) $(TD any) $(TD -∞)          $(TD        ) $(TD     ) $(TD         ) $(TD         )  $(TD        ))
        $(TR $(TD any) $(TD -) $(TD -∞) $(TD -∞)          $(TD        ) $(TD     ) $(TD         ) $(TD         )  $(TD        ))
        $(TR $(TD any) $(TD -) $(TD any) $(TD any)        $(TD        ) $(TD     ) $(TD ✓      ) $(TD ✓      )  $(TD ✓     ))
        $(TR $(TD ±∞) $(TD *) $(TD 0.0) $(TD $(B NaN))         $(TD ✓     ) $(TD     ) $(TD         ) $(TD         )  $(TD        ))
        $(TR $(TD ±∞) $(TD *) $(TD any) $(TD ±∞)          $(TD        ) $(TD     ) $(TD         ) $(TD         )  $(TD        ))
        $(TR $(TD any) $(TD *) $(TD any) $(TD any)        $(TD        ) $(TD     ) $(TD         ) $(TD         )  $(TD        ))
        $(TR $(TD ±∞) $(TD /) $(TD ±∞) $(TD $(B NaN))          $(TD ✓     ) $(TD     ) $(TD         ) $(TD         )  $(TD        ))
        $(TR $(TD 0.0) $(TD /) $(TD 0.0) $(TD $(B NaN))        $(TD ✓     ) $(TD     ) $(TD         ) $(TD         )  $(TD        ))
        $(TR $(TD ±∞) $(TD /) $(TD any) $(TD ±∞)          $(TD        ) $(TD     ) $(TD         ) $(TD         )  $(TD        ))
        $(TR $(TD any) $(TD /) $(TD 0.0) $(TD ±∞)         $(TD        ) $(TD ✓  ) $(TD         ) $(TD         )  $(TD        ))
        $(TR $(TD any) $(TD /) $(TD any) $(TD any)        $(TD        ) $(TD     ) $(TD ✓      ) $(TD ✓      )  $(TD ✓     ))
        $(TR $(TD ±∞) $(TD %) $(TD any) $(TD $(B NaN))         $(TD ✓     ) $(TD     ) $(TD         ) $(TD         )  $(TD        ))
        $(TR $(TD any) $(TD %) $(TD ±∞) $(TD $(B NaN))         $(TD ✓     ) $(TD     ) $(TD         ) $(TD         )  $(TD        ))
        $(TR $(TD any) $(TD %) $(TD 0.0) $(TD $(B NaN))        $(TD ✓     ) $(TD     ) $(TD         ) $(TD         )  $(TD        ))
        $(TR $(TD any) $(TD %) $(TD any) $(TD any)        $(TD        ) $(TD     ) $(TD ✓      ) $(TD ✓      )  $(TD ✓     ))
    )
    */
    @IEEECompliant("addition", 21)
    @IEEECompliant("division", 21)
    @IEEECompliant("multiplication", 21)
    @IEEECompliant("pow", 42)
    @IEEECompliant("pown", 42)
    @IEEECompliant("powr", 42)
    @IEEECompliant("remainder", 25)
    @IEEECompliant("substraction", 21)
    auto opBinary(string op, T)(const auto ref T value) const @safe
    if (op == "+" || op == "-" || op == "*" || op == "/" || op == "%" || op == "^^")
    {
        static if (isDecimal!T)
            CommonDecimal!(D, T) result = this;
        else
            Unqual!D result = this;

        static if (op == "+")
            alias decimalOp = decimalAdd;
        else static if (op == "-")
            alias decimalOp = decimalSub;
        else static if (op == "*")
            alias decimalOp = decimalMul;
        else static if (op == "/")
            alias decimalOp = decimalDiv;
        else static if (op == "%")
            alias decimalOp = decimalMod;
        else static if (op == "^^")
            alias decimalOp = decimalPow;
        else
            static assert(0);

        static if (isIntegral!T || isFloatingPoint!T || isDecimal!T)
            const flags = decimalOp(result, value,
                            __ctfe ? 0 : DecimalControl.precision,
                            __ctfe ? RoundingMode.implicit : DecimalControl.rounding);
        else static if (isSomeChar!T)
            const flags = decimalOp(result, cast(uint)value,
                            __ctfe ? 0 : DecimalControl.precision,
                            __ctfe ? RoundingMode.implicit : DecimalControl.rounding);
        else
            static assert(0, "Cannot perform binary operation: '" ~ Unqual!D.stringof ~ "' " ~ op ~" '" ~ Unqual!T.stringof ~ "'");
        if (!__ctfe)
            DecimalControl.raiseFlags(flags);
        return result;
    }

    ///ditto
    auto opBinaryRight(string op, T)(const auto ref T value) const @safe
    if (op == "+" || op == "-" || op == "*" || op == "/" || op == "%" || op == "^^")
    {
        static if (isDecimal!T)
            CommonDecimal!(D, T) result = value;
        else
            Unqual!D result;

        static if (op == "+")
            alias decimalOp = decimalAdd;
        else static if (op == "-")
            alias decimalOp = decimalSub;
        else static if (op == "*")
            alias decimalOp = decimalMul;
        else static if (op == "/")
            alias decimalOp = decimalDiv;
        else static if (op == "%")
            alias decimalOp = decimalMod;
        else static if (op == "^^")
            alias decimalOp = decimalPow;
        else
            static assert(0);

        static if (isDecimal!T)
            const flags = decimalOp(result, this,
                            __ctfe ? 0 : DecimalControl.precision,
                            __ctfe ? RoundingMode.implicit : DecimalControl.rounding);
        else static if (isIntegral!T || isFloatingPoint!T)
            const flags = decimalOp(value, this, result,
                            __ctfe ? 0 : DecimalControl.precision,
                            __ctfe ? RoundingMode.implicit : DecimalControl.rounding);
        else static if (isSomeChar!T)
            const flags = decimalOp(cast(uint)value, this, result,
                            __ctfe ? 0 : DecimalControl.precision,
                            __ctfe ? RoundingMode.implicit : DecimalControl.rounding);
        else
            static assert(0, "Cannot perform binary operation: '" ~ Unqual!T.stringof ~ "' " ~ op ~" '" ~ Unqual!D.stringof ~ "'");
        if (!__ctfe)
            DecimalControl.raiseFlags(flags);
        return result;
    }

    ///ditto
    auto opOpAssign(string op, T)(const auto ref T value) @safe
    if (op == "+" || op == "-" || op == "*" || op == "/" || op == "%" || op == "^^")
    {
        static if (op == "+")
            alias decimalOp = decimalAdd;
        else static if (op == "-")
            alias decimalOp = decimalSub;
        else static if (op == "*")
            alias decimalOp = decimalMul;
        else static if (op == "/")
            alias decimalOp = decimalDiv;
        else static if (op == "%")
            alias decimalOp = decimalMod;
        else static if (op == "^^")
            alias decimalOp = decimalPow;
        else
            static assert(0);

        static if (isIntegral!T || isFloatingPoint!T || isDecimal!T)
            const flags = decimalOp(this, value,
                            __ctfe ? 0 : DecimalControl.precision,
                            __ctfe ? RoundingMode.implicit : DecimalControl.rounding);
        else static if (isSomeChar!T)
            const flags = decimalOp(this, cast(uint)value,
                            __ctfe ? 0 : DecimalControl.precision,
                            __ctfe ? RoundingMode.implicit : DecimalControl.rounding);
        else
            static assert(0, "Cannot perform assignment operation: '" ~ Unqual!D.stringof ~ "' " ~ op ~"= '" ~ Unqual!T.stringof ~ "'");

        if (!__ctfe)
            DecimalControl.raiseFlags(flags);
        return this;
    }

    /**
     * Constructs a Decimal data type using the specified value using
     * Decimal.PRECISION and RoundingMode.banking
     * Params:
     *  value = any integral
     */
    static typeof(this) money(T)(const auto ref T value) @nogc nothrow pure @safe
    if (isIntegral!T)
    {
        return D(value, RoundingMode.banking);
    }

    /**
     * Constructs a Decimal data type using the specified value using
     * Decimal.PRECISION and RoundingMode.banking
     * Params:
     *  value = any integral or floating point
     *  maxFractionalDigits = perform round-up/truncate at specified fractional position
     *                        if the value <= 0 or value > PRECESION will be ignore
     */
    static typeof(this) money(T)(const auto ref T value,
        const(int) maxFractionalDigits = Precision.bankingScale) pure @safe
    if (isFloatingPoint!T)
    {
        return D(value, RoundingMode.banking, maxFractionalDigits);
    }

    static D fromBigEndianBytes(scope const(ubyte)[] bigEndianBytes) @nogc nothrow pure @safe
    {
        Unqual!D result = void;
        result.data = fromBigEndianBytesImpl!U(bigEndianBytes);
        return result;
    }

    ubyte[] toBigEndianBytes(return ubyte[] bytes) const @nogc nothrow pure @safe
    in
    {
        assert(bytes.length == U.sizeof);
    }
    do
    {
        return data.toBigEndianBytes(bytes);
    }

    /**
    Returns a unique hash of the _decimal value suitable for use in a hash table.
    Notes:
       This function is not intended for direct use, it's provided as support for associative arrays.
    */
    size_t toHash() @safe pure nothrow @nogc
    {
        static if (Bytes == 4)
            return data;
        else static if (Bytes == 8)
        {
            static if (size_t.sizeof == uint.sizeof)
                return cast(uint)data ^ cast(uint)(data >>> 32);
            else
                return data;
        }
        else
        {
            static if (size_t.sizeof == uint.sizeof)
                return cast(uint)data.hi ^ cast(uint)(data.hi >>> 32) ^
                       cast(uint)data.lo ^ cast(uint)(data.lo >>> 32);
            else
                return data.hi ^ data.lo;
        }
    }

    version(D_BetterC)
    {}
    else
    {
        static immutable char defaultFmtSpec = 'f';
        static immutable string defaultFmt = "%f";
        static immutable string defaultMoneyFmt =
            () {
                import std.conv : to;
                scope (failure) assert(0, "Assume nothrow failed");

                return "%." ~ (cast(int)Precision.bankingScale).to!string() ~ "f";
            } ();

        ///Converts current value to string in floating point or scientific notation,
        ///which one is shorter.
        @IEEECompliant("convertToDecimalCharacter", 22)
        string toString() const nothrow @safe
        {
            FormatSpec!char spec;
            spec.spec = defaultFmtSpec;
            ShortStringBuffer!char resultBuffer;
            sinkDecimal(resultBuffer, spec, this, __ctfe ? RoundingMode.implicit : DecimalControl.rounding);
            return resultBuffer.toString();
        }

        ///ditto
        @IEEECompliant("convertToDecimalCharacter", 22)
        @IEEECompliant("convertToHexCharacter", 22)
        string toString(scope const(char)[] fmt) const @safe
        {
            auto spec = FormatSpec!char(fmt);
            ShortStringBuffer!char resultBuffer;
            spec.writeUpToNextSpec(resultBuffer);
            assert(isValidDecimalSpec(spec));
            sinkDecimal(resultBuffer, spec, this, __ctfe ? RoundingMode.implicit : DecimalControl.rounding);
            return resultBuffer.toString();
        }

        ///Converts current value to string according to the
        ///format specification
        @IEEECompliant("convertToDecimalCharacter", 22)
        @IEEECompliant("convertToHexCharacter", 22)
        string toString(scope const ref FormatSpec!char spec) const @safe
        in
        {
            assert(isValidDecimalSpec(spec));
        }
        do
        {
            ShortStringBuffer!char resultBuffer;
            sinkDecimal(resultBuffer, spec, this, __ctfe ? RoundingMode.implicit : DecimalControl.rounding);
            return resultBuffer.toString();
        }

        /// Since this template function does not use Char in parameter,
        /// D won't infer the call so caller need to explicitly specify the template argument types
        /// Ex: D.toString!(OutputRange..., char)(sink...);
        @IEEECompliant("convertToDecimalCharacter", 22)
        ref Writer toString(Writer, Char)(return ref Writer sink) const nothrow @safe
        if (isOutputRange!(Writer, Char) && isSomeChar!Char)
        {
            FormatSpec!Char spec;
            spec.spec = defaultFmtSpec;
            sinkDecimal(sink, spec, this, __ctfe ? RoundingMode.implicit : DecimalControl.rounding);
            return sink;
        }

        @IEEECompliant("convertToDecimalCharacter", 22)
        @IEEECompliant("convertToHexCharacter", 22)
        ref Writer toString(Writer, Char)(return ref Writer sink, scope const(Char)[] fmt) const @safe
        if (isOutputRange!(Writer, Char) && isSomeChar!Char)
        {
            auto spec = FormatSpec!Char(fmt);
            spec.writeUpToNextSpec(sink);
            assert(isValidDecimalSpec(spec));
            sinkDecimal(sink, spec, this, __ctfe ? RoundingMode.implicit : DecimalControl.rounding);
            return sink;
        }

        /**
        Converts current value to string, passing it to the given sink using
        the specified format.
        Params:
          sink = a delegate used to sink character arrays;
          fmt  = a format specification;
        Notes:
          This function is not intended to be used directly, it is used by the format, output or conversion
          family of functions from Phobos. All standard format options are supported, except digit grouping.
        Supported_formats:
          $(UL
            $(LI $(B f, F) - floating point notation)
            $(LI $(B e, E) - scientific notation)
            $(LI $(B a, A) - hexadecimal floating point notation)
            $(LI $(B g, G) - shortest representation between floating point and scientific notation)
            $(LI $(B s, S) - same as $(B g, G))
          )
        Throws:
          $(PHOBOS format, FormatException, FormatException) if the format specifier is not supported
        See_Also:
           $(PHOBOS format, FormatSpec, FormatSpec)
           $(PHOBOS format, format, format)
           $(PHOBOS conv, to, to)
           $(PHOBOS stdio, writef, writef)
           $(PHOBOS stdio, writefln, writefln)
        */
        @IEEECompliant("convertToDecimalCharacter", 22)
        @IEEECompliant("convertToHexCharacter", 22)
        ref Writer toString(Writer, Char)(return ref Writer sink, scope const ref FormatSpec!Char spec) const @safe
        if (isOutputRange!(Writer, Char) && isSomeChar!Char)
        in
        {
            assert(isValidDecimalSpec(spec));
        }
        do
        {
            sinkDecimal(sink, spec, this, __ctfe ? RoundingMode.implicit : DecimalControl.rounding);
            return sink;
        }
    } //!D_BetterC

    /**
    Determines if _decimal is a finite value.
    This operation is silent, no error flags are set and no exceptions are thrown.
    Returns:
        true if finite, false otherwise ($(B NaN) or infinity)
    */
    @IEEECompliant("isFinite", 25)
    @property bool isFinite() const @nogc nothrow pure @safe
    // @("this must be fast")
    {
        static if (Bytes == 16)
            return (data.hi & MASK_INF.hi) != MASK_INF.hi;
        else
            return (data & MASK_INF) != MASK_INF;
    }

    /**
    Determines if _decimal represents a infinity.
    This operation is silent, no error flags are set and no exceptions are thrown.
    Returns:
        One of the value of enum $(B CheckInfinity)
    */
    @IEEECompliant("isInfinite", 25)
    @property CheckInfinity isInfinity() const @nogc nothrow pure @safe
    // @("this must be fast")
    {
        static if (Bytes == 16)
            const isInf = (data.hi & MASK_SNAN.hi) == MASK_INF.hi;
        else
            const isInf = (data & MASK_SNAN) == MASK_INF;
        return isInf ? (isNeg ? CheckInfinity.negative : CheckInfinity.yes) : CheckInfinity.no;
    }

    /**
    Determines if _decimal represents a $(B NaN).
    This operation is silent, no error flags are set and no exceptions are thrown.
    Returns:
        One of the value of enum $(B CheckNaN)
    */
    @IEEECompliant("isNaN", 25)
    @property CheckNaN isNaN() const @nogc nothrow pure @safe
    // @("this must be fast")
    {
        static if (Bytes == 16)
        {
            enum qnanMask = MASK_QNAN.hi;
            enum snanMask = MASK_SNAN.hi;
            const nanBits = data.hi & snanMask;
        }
        else
        {
            enum qnanMask = MASK_QNAN;
            enum snanMask = MASK_SNAN;
            const nanBits = data & snanMask;
        }
        return nanBits == snanMask
            ? (isNeg ? CheckNaN.negSNaN : CheckNaN.sNaN)
            : (nanBits == qnanMask
                ? (isNeg ? CheckNaN.negQNaN : CheckNaN.qNaN)
                : CheckNaN.no);
    }

    /**
    Determines if _decimal is a negative.
    This operation is silent, no error flags are set and no exceptions are thrown.
    Returns:
        true if is negative, false otherwise
    */
    @property bool isNeg() const @nogc nothrow pure @safe
    // @("this must be fast")
    {
        static if (Bytes == 16)
            return (data.hi & MASK_SGN.hi) == MASK_SGN.hi;
        else
            return (data & MASK_SGN) == MASK_SGN;
    }

    /**
    Determines if _decimal represents a quiet $(B NaN).
    This operation is silent, no error flags are set and no exceptions are thrown.
    Returns:
        true if $(B NaN) and is quiet, false otherwise (signaling $(B NaN), any other value)
    */
    @IEEECompliant("isQuietNaN", 25)
    @property bool isQuietNaN() const @nogc nothrow pure @safe
    {
        const n = isNaN;
        return n == CheckNaN.negQNaN || n == CheckNaN.qNaN;
    }

    /**
    Determines if _decimal represents a signaling $(B NaN).
    This operation is silent, no error flags are set and no exceptions are thrown.
    Returns:
        true if $(B NaN) and is signaling, false otherwise (quiet $(B NaN), any other value)
    */
    @IEEECompliant("isSignalNaN", 25)
    @property bool isSignalNaN() const @nogc nothrow pure @safe
    {
        const n = isNaN;
        return n == CheckNaN.negSNaN || n == CheckNaN.sNaN;
    }

    /**
    Determines if _decimal represents the value zero.
    This operation is silent, no error flags are set and no exceptions are thrown.
    Returns:
        true if is zero, false otherwise (any other value than zero)
    Standards:
        If the internal representation of the _decimal data type has a coefficient
        greater that 10$(SUPERSCRIPT precision) - 1, is considered 0 according to
        IEEE standard.
    */
    @IEEECompliant("isZero", 25)
    @property bool isZero() const @nogc nothrow pure
    // @("this must be fast")
    {
        static if (Bytes == 16)
        {
            if ((data.hi & MASK_INF.hi) != MASK_INF.hi)
            {
                if ((data.hi & MASK_EXT.hi) == MASK_EXT.hi)
                    return true;
                else
                {
                    const cx = data & MASK_COE1;
                    return !cx || cx > COEF_MAX;
                }
            }
            else
                return false;
        }
        else
        {
            if ((data & MASK_INF) != MASK_INF)
            {
                if ((data & MASK_EXT) == MASK_EXT)
                    return ((data & MASK_COE2) | MASK_COEX) > COEF_MAX;
                else
                    return (data & MASK_COE1) == 0;
            }
            else
                return false;
        }
    }

    /**
    Returns a number that indicates the sign (negative, positive, or zero)
    Returns:
        -1  The value is negative.
        0   The value is 0 (zero).
        1 	The value is positive.
    */
    @IEEECompliant("sign", 25)
    @property int sign() const @nogc nothrow pure
    // @("this must be fast")
    {
        return isNeg ? -1 : (isZero ? 0 : 1);
    }

package(pham.external.dec):
    alias U = DataType!Bytes;

    static D buildin(const(U) coefficientMask, const(U) exponentMask, const(U) signMask) @nogc nothrow pure @safe
    {
        D result = void;
        result.data = signMask | exponentMask | coefficientMask;
        return result;
    }

    static D buildin(const(U) coefficient, const(int) biasedExponent, const(bool) isNegative) @nogc nothrow pure @safe
    {
        D result = void;
        result.pack(coefficient, biasedExponent, isNegative);
        return result;
    }

    static D buildin(C)(scope const(C)[] validDecimal) nothrow pure @safe
    if (isSomeChar!C)
    {
        Unqual!D result = void;
        ExceptionFlags flags;
        const valid = result.packString(validDecimal, flags, D.PRECISION, RoundingMode.implicit);
        assert(valid, validDecimal.idup);
        version(ShowEnumDecBytes) version(none)
        {
            import std.stdio : writeln;
            ubyte[Bytes] b;
            if (!__ctfe)
                debug writeln(U.stringof, "::", validDecimal, ": ", result.data.toBigEndianBytes(b[]));
        }
        return result;
    }

    ExceptionFlags adjustedPack(T)(const(T) coefficient, const(int) exponent, const(bool) isNegative,
        const(int) precision, const(RoundingMode) mode,
        const(ExceptionFlags) previousFlags = ExceptionFlags.none) @nogc nothrow pure @safe
    {
        if (!errorPack(isNegative, previousFlags, precision, mode, cvt!U(coefficient)))
        {
            const bool stickyUnderflow = coefficient
                && (exponent < int.max - EXP_BIAS
                    && exponent + EXP_BIAS < PRECISION - 1
                    && prec(coefficient) < PRECISION - (exponent + EXP_BIAS));
            static if (T.sizeof <= U.sizeof)
                U cx = coefficient;
            else
                Unqual!T cx = coefficient;
            int ex = exponent;
            ExceptionFlags flags = coefficientAdjust(cx, ex, EXP_MIN, EXP_MAX, realPrecision(precision), isNegative, mode) | previousFlags;
            if (stickyUnderflow)
                flags |= ExceptionFlags.underflow;
            return checkedPack(cvt!U(cx), ex, isNegative, precision, mode, false) | flags;
        }
        return previousFlags;
    }

    ExceptionFlags infinityPack(const(bool) isNegative) @nogc nothrow pure @safe
    {
        return maskPack(MASK_INF, isNegative);
    }

    //packs $(B NaN)
    ExceptionFlags invalidPack(const(bool) isNegative, const(U) payload = U(0U)) @nogc nothrow pure @safe
    {
        data = isNegative ? (MASK_QNAN | (payload & MASK_PAYL) | MASK_SGN) : (MASK_QNAN | (payload & MASK_PAYL));
        return ExceptionFlags.invalidOperation;
    }

    ExceptionFlags maskPack(U mask, const(bool) isNegative) @nogc nothrow pure @safe
    {
        data = isNegative ? (mask | MASK_SGN) : mask;
        return ExceptionFlags.none;
    }

    //packs valid components
    void pack(const(U) coefficient, const(int) biasedExponent, const(bool) isNegative) @nogc nothrow pure @safe
    in
    {
        assert(coefficient <= COEF_MAX_RAW);
        assert(biasedExponent >= EXP_MIN && biasedExponent <= EXP_MAX);
    }
    out
    {
        assert((this.data & MASK_INF) != MASK_INF);
    }
    do
    {
        const U expMask = U(cast(uint)(biasedExponent + EXP_BIAS));
        const U sgnMask = isNegative ? MASK_SGN : MASK_NONE;

        if (coefficient <= MASK_COE1)
            this.data = sgnMask | (expMask << SHIFT_EXP1) | coefficient;
        else
            this.data = sgnMask | (expMask << SHIFT_EXP2) | (coefficient & MASK_COE2) | MASK_EXT;
    }

    ExceptionFlags packFloatingPoint(T)(const(T) value, const(int) precision, const(RoundingMode) mode,
        const(int) maxFractionalDigits) @nogc nothrow pure @safe
    if (isFloatingPoint!T)
    {
        import std.math : abs;

        ExceptionFlags flags;
        DataType!Bytes cx; int ex; bool sx;
        switch (fastDecode(value, cx, ex, sx, mode, flags))
        {
            case FastClass.quietNaN:
                data = (sx ? (MASK_QNAN | MASK_SGN) : MASK_QNAN) | (cx & MASK_PAYL);
                return ExceptionFlags.none;
            case FastClass.infinite:
                data = sx ? (MASK_INF | MASK_SGN) : MASK_INF;
                return ExceptionFlags.none;
            case FastClass.zero:
                data = sx ? (MASK_ZERO | MASK_SGN) : MASK_ZERO;
                return ExceptionFlags.none;
            case FastClass.finite:
                enum maxTPrecision = maxPrecision!T();
                const targetPrecision = realPrecision(realPrecision(precision), maxTPrecision);

                if (maxFractionalDigits)
                {
                    const exAbs = abs(ex);
                    if (maxFractionalDigits < exAbs)
                    {
                        const clearFractions = exAbs - maxFractionalDigits;
                        const roundDigits = pow10Index!(DataType!Bytes)(clearFractions - 1);

                        // Round it up/down first
                        const roundValue = mode == RoundingMode.tiesToEven
                            ? pow10RoundEven!(DataType!Bytes)[roundDigits]
                            : pow10!(DataType!Bytes)[roundDigits];
                        xadd(cx, roundValue);

                        // Clear subsequence fractional digits to be zero
                        bool overflow;
                        ShortStringBuffer!char buffer;
                        auto cxDigits = dataTypeToString(buffer, cx);
                        if (cxDigits.length > clearFractions)
                            cxDigits[$ - clearFractions..$] = '0';
                        cx = toUnsign!(DataType!Bytes)(cxDigits, overflow);
                        assert(!overflow, "Overflow");
                    }
                }

                flags |= coefficientAdjust(cx, ex, targetPrecision, sx, mode);
                flags = adjustedPack(cx, ex, sx, precision, mode, flags);
                // We want less precision?
                if (precision < maxTPrecision)
                    flags &= ~ExceptionFlags.inexact;
                return flags;
            default:
                assert(0);
        }
    }

    ExceptionFlags packIntegral(T)(const(T) value, const(int) precision, const(RoundingMode) mode) @nogc nothrow pure @safe
    if (isIntegral!T)
    {
        alias V = CommonStorage!(D, T);
        if (!value)
        {
            this.data = MASK_ZERO;
            return ExceptionFlags.none;
        }
        else
        {
            static if (isSigned!T)
            {
                bool isNegative;
                V coefficient = unsign!V(value, isNegative);
            }
            else
            {
                bool isNegative = false;
                V coefficient = value;
            }
            int exponent = 0;
            const flags1 = coefficientAdjust(coefficient, exponent, cvt!V(COEF_MAX), isNegative, mode);
            return adjustedPack(cvt!U(coefficient), exponent, isNegative, precision, mode, flags1);
        }
    }

    void packRaw(const(U) coefficient, const(uint) unbiasedExponent, const(bool) isNegative)
    {
        const U expMask = U(unbiasedExponent);
        const U sgnMask = isNegative ? MASK_SGN : MASK_NONE;

        if (coefficient <= MASK_COE1)
            this.data = sgnMask | (expMask << SHIFT_EXP1) | coefficient;
        else
            this.data = sgnMask | (expMask << SHIFT_EXP2) | (coefficient & MASK_COE2) | MASK_EXT;
    }

    bool unpack(out U coefficient, out int biasedExponent) const @nogc nothrow pure @safe
    out
    {
        assert(coefficient <= (MASK_COE2 | MASK_COEX));
        assert(biasedExponent >= EXP_MIN && biasedExponent <= EXP_MAX);
    }
    do
    {
        uint e;
        const bool isNegative = unpackRaw(coefficient, e);
        biasedExponent = cast(int)(e - EXP_BIAS);
        return isNegative;
    }

    bool unpackRaw(out U coefficient, out uint unbiasedExponent) const @nogc nothrow pure @safe
    {
        if ((data & MASK_EXT) == MASK_EXT)
        {
            coefficient = data & MASK_COE2 | MASK_COEX;
            unbiasedExponent = cast(uint)((data & MASK_EXP2) >>> SHIFT_EXP2);
        }
        else
        {
            coefficient = data & MASK_COE1;
            unbiasedExponent = cast(uint)((data & MASK_EXP1) >>> SHIFT_EXP1);
        }
        return (data & MASK_SGN) != 0U;
    }

    enum half           = buildin(U(5U), -1, false);
    enum negZero        = buildin(U(0U), 0, true);
    enum two            = buildin(U(2U), 0, false);
    enum three          = buildin(U(3U), 0, false);
    enum ten            = buildin(U(10U), 0, false);
    enum negSubn        = buildin(U(1U), EXP_MIN, true);
    enum negTen         = buildin(U(10U), 0, true);
    enum quarter        = buildin(U(25U), -2, false);
    enum subn           = buildin(U(1U), EXP_MIN, false);
    enum threequarters  = buildin(U(75U), -2, false);

    enum sqrt1_2        = fromBigEndianBytes(SEnumBytes!Bytes.s_sqrt1_2); // buildin(s_sqrt1_2);
    enum sqrt2          = fromBigEndianBytes(SEnumBytes!Bytes.s_sqrt2); // buildin(s_sqrt2);
    enum sqrt3          = fromBigEndianBytes(SEnumBytes!Bytes.s_sqrt3); // buildin(s_sqrt3);
    enum m_sqrt3        = fromBigEndianBytes(SEnumBytes!Bytes.s_m_sqrt3); // buildin(s_m_sqrt3);
    enum m_2_sqrtpi     = fromBigEndianBytes(SEnumBytes!Bytes.s_m_2_sqrtpi); // buildin(s_m_2_sqrtpi);
    enum pi_2           = fromBigEndianBytes(SEnumBytes!Bytes.s_pi_2); // buildin(s_pi_2);
    enum pi_3           = fromBigEndianBytes(SEnumBytes!Bytes.s_pi_3); // buildin(s_pi_3);
    enum pi_4           = fromBigEndianBytes(SEnumBytes!Bytes.s_pi_4); // buildin(s_pi_4);
    enum pi_6           = fromBigEndianBytes(SEnumBytes!Bytes.s_pi_6); // buildin(s_pi_6);
    enum pi2            = fromBigEndianBytes(SEnumBytes!Bytes.s_pi2); // buildin(s_pi2);
    enum pi2_3          = fromBigEndianBytes(SEnumBytes!Bytes.s_pi2_3); // buildin(s_pi2_3);
    enum pi3_4          = fromBigEndianBytes(SEnumBytes!Bytes.s_pi3_4); // buildin(s_pi3_4);
    enum pi5_6          = fromBigEndianBytes(SEnumBytes!Bytes.s_pi5_6); // buildin(s_pi5_6);
    enum sqrt3_2        = fromBigEndianBytes(SEnumBytes!Bytes.s_sqrt3_2); // buildin(s_sqrt3_2);
    enum sqrt2_2        = fromBigEndianBytes(SEnumBytes!Bytes.s_sqrt2_2); // buildin(s_sqrt2_2);
    enum onethird       = fromBigEndianBytes(SEnumBytes!Bytes.s_onethird); // buildin(s_onethird);
    enum twothirds      = fromBigEndianBytes(SEnumBytes!Bytes.s_twothirds); // buildin(s_twothirds);
    enum n5_6           = fromBigEndianBytes(SEnumBytes!Bytes.s_n5_6); // buildin(s_n5_6);
    enum n1_6           = fromBigEndianBytes(SEnumBytes!Bytes.s_n1_6); // buildin(s_n1_6);
    enum m_1_pi         = fromBigEndianBytes(SEnumBytes!Bytes.s_m_1_pi); // buildin(s_m_1_pi);
    enum m_1_2pi        = fromBigEndianBytes(SEnumBytes!Bytes.s_m_1_2pi); // buildin(s_m_1_2pi);
    enum m_2_pi         = fromBigEndianBytes(SEnumBytes!Bytes.s_m_2_pi); // buildin(s_m_2_pi);

    static if (Bytes == 16)
    {
        enum maxFloat   = fromBigEndianBytes(SEnumBytes!Bytes.s_maxFloat128); // buildin(s_maxFloat128);
        enum maxDouble  = fromBigEndianBytes(SEnumBytes!Bytes.s_maxDouble128); // buildin(s_maxDouble128);
        enum maxReal    = fromBigEndianBytes(SEnumBytes!Bytes.s_maxReal128); // buildin(s_maxReal128);
        enum minFloat   = fromBigEndianBytes(SEnumBytes!Bytes.s_minFloat128); // buildin(s_minFloat128);
        enum minDouble  = fromBigEndianBytes(SEnumBytes!Bytes.s_minDouble128); // buildin(s_minDouble128);
        enum minReal    = fromBigEndianBytes(SEnumBytes!Bytes.s_minReal128); // buildin(s_minReal128);
    }

    enum MASK_INF       = U(0b01111000U) << (Bytes * 8 - 8);
    enum MASK_QNAN      = U(0b01111100U) << (Bytes * 8 - 8);
    enum MASK_SNAN      = U(0b01111110U) << (Bytes * 8 - 8);
    enum MASK_ZERO      = U(cast(uint)EXP_BIAS) << SHIFT_EXP1;

private:
    enum expBits        = Bytes * 8 / 16 + 6;                 //8, 10, 14
    enum trailingBits   = Bytes * 8 - expBits - 1;            //23, 53, 113

    enum SHIFT_EXP1     = trailingBits;                  //23, 53, 113
    enum SHIFT_EXP2     = trailingBits - 2;              //21, 51, 111

    enum MASK_SNANBIT   = U(0b00000010U) << (Bytes * 8 - 8);
    enum MASK_SGN       = U(0b10000000U) << (Bytes * 8 - 8);
    enum MASK_EXT       = U(0b01100000U) << (Bytes * 8 - 8);
    enum MASK_EXP1      = ((U(1U) << expBits) - 1U) << SHIFT_EXP1;
    enum MASK_EXP2      = ((U(1U) << expBits) - 1U) << SHIFT_EXP2;
    enum MASK_COE1      = ~(MASK_SGN | MASK_EXP1);
    enum MASK_COE2      = ~(MASK_SGN | MASK_EXP2 | MASK_EXT);
    enum MASK_COEX      = U(1U) << trailingBits;
    enum MASK_PAYL      = (U(1U) << (trailingBits - 3)) - 1U;
    enum MASK_NONE      = U(0U);

    enum PAYL_MAX       = pow10!U[PRECISION - 1] - 1U;

    enum LOG10_2        = 0.30102999566398119521L;

    U data; //MASK_SNAN;

    //packs components, but checks the limits before
    @nogc nothrow pure @safe
    ExceptionFlags checkedPack(const(U) coefficient, const(int) exponent, const(bool) isNegative,
        int precision, const(RoundingMode) mode, const(bool) acceptNonCanonical)
    {
        if (exponent > EXP_MAX)
            return overflowPack(isNegative, precision, mode);
        if (exponent < EXP_MIN)
            return underflowPack(isNegative, mode);
        if (coefficient > COEF_MAX && !acceptNonCanonical)
            return overflowPack(isNegative, precision, mode);
        if (coefficient > (MASK_COE2 | MASK_COEX) && acceptNonCanonical)
            return overflowPack(isNegative, precision, mode);

        const U expMask = U(cast(uint)(exponent + EXP_BIAS));
        const U sgnMask = isNegative ? MASK_SGN : MASK_NONE;

        if (coefficient <= MASK_COE1)
            this.data = sgnMask | (expMask << SHIFT_EXP1) | coefficient;
        else
            this.data = sgnMask | (expMask << SHIFT_EXP2) | (coefficient & MASK_COE2) | MASK_EXT;

        if (expMask < cast(uint)(D.PRECISION - 1) && prec(coefficient) < D.PRECISION - cast(uint)expMask)
            return ExceptionFlags.underflow;

        return ExceptionFlags.none;
    }

    //returns true if data was packed according to flags
    @nogc nothrow pure @safe
    bool errorPack(const(bool) isNegative, const(ExceptionFlags) flags, const(int) precision,
        const(RoundingMode) mode, const(U) payload = U(0U))
    {
        if (flags & ExceptionFlags.invalidOperation)
            invalidPack(isNegative, payload);
        else if (flags & ExceptionFlags.divisionByZero)
            div0Pack(isNegative);
        else if (flags & ExceptionFlags.overflow)
            overflowPack(isNegative, precision, mode);
        else if (flags & ExceptionFlags.underflow)
            underflowPack(isNegative, mode);
        else
            return false;
        return true;
    }

    @nogc nothrow pure @safe
    ExceptionFlags maxPack(const(bool) isNegative, const(int) precision)
    {
        data = isNegative ? MASK_SGN : MASK_NONE;
        const p = realPrecision(precision);
        if (p >= PRECISION)
        {
            data |= max.data;
            return ExceptionFlags.overflow | ExceptionFlags.inexact;
        }
        else
        {
            const U coefficient = (COEF_MAX / pow10!U[PRECISION - p]) * pow10!U[PRECISION - p];
            const int exponent = EXP_MAX;
            pack(coefficient, exponent, isNegative);
            return ExceptionFlags.overflow;
        }
    }

    @nogc nothrow pure @safe
    ExceptionFlags minPack(const(bool) isNegative)
    {
        data = (isNegative ? MASK_SGN : MASK_NONE) | subn.data;
        return ExceptionFlags.underflow;
    }

    //packs infinity or max, depending on the rounding mode
    @nogc nothrow pure @safe
    ExceptionFlags overflowPack(const(bool) isNegative, const(int) precision, const(RoundingMode) mode)
    {
        switch (mode)
        {
            case RoundingMode.towardZero:
                return maxPack(isNegative, precision);
            case RoundingMode.towardNegative:
                if (!isNegative)
                    return maxPack(false, precision);
                goto default;
            case RoundingMode.towardPositive:
                if (isNegative)
                    return maxPack(true, precision);
                goto default;
            default:
                data = isNegative ? (MASK_INF | MASK_SGN) : MASK_INF;
                break;
        }
        return ExceptionFlags.overflow;
    }

    //packs zero or min, depending on the rounding mode
    @nogc nothrow pure @safe
    ExceptionFlags underflowPack(const(bool) isNegative, const(RoundingMode) mode)
    {
        switch (mode)
        {
            case RoundingMode.towardPositive:
                if (!isNegative)
                    return minPack(false);
                goto default;
            case RoundingMode.towardNegative:
                if (isNegative)
                    return minPack(true);
                goto default;
            default:
                data = isNegative ? (MASK_ZERO | MASK_SGN) : MASK_ZERO;
                break;
        }
        return ExceptionFlags.underflow;
    }

    //packs infinity
    @nogc nothrow pure @safe
    ExceptionFlags div0Pack(const(bool) isNegative)
    {
        data = isNegative ? (MASK_INF | MASK_SGN) : MASK_INF;
        return ExceptionFlags.divisionByZero;
    }

    pragma(inline, true)
    static int realPrecision(const(int) precision, const(int) maxPrecision = PRECISION) @nogc nothrow pure @safe
    {
        return (precision <= 0 || precision > maxPrecision) ? maxPrecision : precision;
    }

    bool packString(C)(scope const(C)[] value, out ExceptionFlags flags, const(int) precision, const(RoundingMode) mode) @safe
    if (isSomeChar!C)
    {
        const(C)[] ss = value;
        U coefficient;
        int exponent;
        bool isinf, isnan, issnan, isnegative, wasHex;
        if (!parseDecimal(ss, coefficient, exponent, flags, isinf, isnan, issnan, isnegative, wasHex))
        {
            flags |= invalidPack(isnegative);
            return false;
        }

        if (flags & ExceptionFlags.invalidOperation)
        {
            flags |= invalidPack(isnegative, coefficient);
            return true;
        }

        if (issnan)
            data = MASK_SNAN | (coefficient & MASK_PAYL);
        else if (isnan)
            data = MASK_QNAN | (coefficient & MASK_PAYL);
        else if (isinf || flags & ExceptionFlags.overflow)
            data = MASK_INF;
        else if (flags & ExceptionFlags.underflow)
            data = MASK_ZERO;
        else
        {
            if (!wasHex)
                flags |= adjustedPack(coefficient, exponent, isnegative, precision, mode, flags);
            else
                flags |= checkedPack(coefficient, exponent, isnegative, precision, mode, true);
        }

        if (isnegative)
            data |= MASK_SGN;

        return true;
    }

    bool packRange(R)(ref R range, out ExceptionFlags flags, const(int) precision, const(RoundingMode) mode) @safe
    if (isInputRange!R && isSomeChar!(ElementType!R) && !isSomeString!range)
    {
        U coefficient;
        int exponent;
        bool isinf, isnan, issnan, isnegative, wasHex;
        if (!parseDecimal(range, coefficient, exponent, flags, isinf, isnan, issnan, isnegative, wasHex))
        {
            flags |= invalidPack(isnegative);
            return false;
        }

        if (flags & ExceptionFlags.invalidOperation)
        {
            flags |= invalidPack(isnegative, coefficient);
            return true;
        }

        if (issnan)
            data = MASK_SNAN | (coefficient & MASK_PAYL);
        else if (isnan)
            data = MASK_QNAN | (coefficient & MASK_PAYL);
        else if (isinf || flags & ExceptionFlags.overflow)
            data = MASK_INF;
        else if (flags & ExceptionFlags.underflow)
            data = MASK_ZERO;
        else
        {
            flags |= coefficientAdjust(coefficient, exponent, EXP_MIN, EXP_MAX, COEF_MAX, isnegative, mode);
            flags |= coefficientAdjust(coefficient, exponent, EXP_MIN, EXP_MAX, precision, isnegative, mode);
            if (flags & ExceptionFlags.underflow)
                data = MASK_ZERO;
            else if (flags & ExceptionFlags.overflow)
                data = MASK_INF;
        }

        if (isnegative)
            data |= MASK_SGN;

        return true;
    }
}

///Shorthand notations for $(MYREF Decimal) types
alias Decimal32 = Decimal!4;
///ditto
alias Decimal64 = Decimal!8;
///ditto
alias Decimal128 = Decimal!16;

version(D_BetterC)
{}
else
{
    mixin template ExceptionConstructors()
    {
        this(string msg, string file = __FILE__, size_t line = __LINE__, Throwable next = null) @nogc nothrow pure @safe
        {
            super(msg, file, line, next);
        }

        this(string msg, Throwable next, string file = __FILE__, size_t line = __LINE__) @nogc nothrow pure @safe
        {
            super(msg, file, line, next);
        }
    }

    ///Root object for all _decimal exceptions
    abstract class DecimalException : Exception
    {
        mixin ExceptionConstructors;

        version(decNogcException)
        {
            final typeof(this) set(string msg, string file, uint line) @nogc nothrow pure @safe
            {
                this.file = file;
                this.line = line;
                this.msg = getExceptionMessage(msg, this.kind);
                return this;
            }

            @property ExceptionFlag kind() @nogc nothrow pure @safe;
        }
    }

    ///Thrown if the denominator of a _decimal division operation is zero.
    class DivisionByZeroException : DecimalException
    {
	    mixin ExceptionConstructors;

        version(decNogcException)
        {
            @property final override ExceptionFlag kind() @nogc nothrow pure @safe
            {
                return ExceptionFlag.divisionByZero;
            }
        }
    }

    ///Thrown if the result of a _decimal operation was rounded to fit in the destination format.
    class InexactException : DecimalException
    {
	    mixin ExceptionConstructors;

        version(decNogcException)
        {
            @property final override ExceptionFlag kind() @nogc nothrow pure @safe
            {
                return ExceptionFlag.inexact;
            }
        }
    }

    ///Thrown if any operand of a _decimal operation is not a number or si not finite
    class InvalidOperationException : DecimalException
    {
	    mixin ExceptionConstructors;

        version(decNogcException)
        {
            @property final override ExceptionFlag kind() @nogc nothrow pure @safe
            {
                return ExceptionFlag.invalidOperation;
            }
        }
    }

    ///Thrown if the result of a _decimal operation exceeds the largest finite number of the destination format.
    class OverflowException : DecimalException
    {
	    mixin ExceptionConstructors;

        version(decNogcException)
        {
            @property final override ExceptionFlag kind() @nogc nothrow pure @safe
            {
                return ExceptionFlag.overflow;
            }
        }
    }

    ///Thrown if the result of a _decimal operation is smaller the smallest finite number of the destination format.
    class UnderflowException : DecimalException
    {
	    mixin ExceptionConstructors;

        version(decNogcException)
        {
            @property final override ExceptionFlag kind() @nogc nothrow pure @safe
            {
                return ExceptionFlag.underflow;
            }
        }
    }
}

///Returns true if all specified types are Decimal... types.
template isDecimal(Ts...)
{
    enum isDecimal =
    {
        bool result = Ts.length > 0;
        static foreach (t; Ts)
        {
            if (!(is(Unqual!t == Decimal32) || is(Unqual!t == Decimal64) || is(Unqual!t == Decimal128)))
                result = false;
        }
        return result;
    }();
}

///
unittest
{
    static assert(isDecimal!Decimal32);
    static assert(isDecimal!(Decimal32, Decimal64));
    static assert(isDecimal!(Decimal32, Decimal64, Decimal128));
    static assert(!isDecimal!int);
    static assert(!isDecimal!(Decimal128, byte));
}

@("Compilation tests")
unittest
{
    import std.meta : AliasSeq;

    static struct DumbRange(C)
    {
        bool empty;
        C front;
        void popFront() {}
    }

    alias DecimalTypes = AliasSeq!(Decimal32, Decimal64, Decimal128);
    alias IntegralTypes = AliasSeq!(byte, short, int, long, ubyte, ushort, uint, ulong);
    alias FloatTypes = AliasSeq!(float, double, real);
    alias CharTypes = AliasSeq!(char, wchar, dchar);
    alias StringTypes = AliasSeq!(string, wstring, dstring);
    alias RangeTypes = AliasSeq!(DumbRange!char, DumbRange!wchar, DumbRange!dchar);

    //constructors
    auto x = Decimal32(double.nan);
    static foreach (D; DecimalTypes)
    {
        static foreach (T; DecimalTypes)
            static assert(is(typeof(D(T.init)) == D));
        static foreach (T; IntegralTypes)
        {
            //pragma(msg, T.stringof ~ " vs " ~ D.stringof ~ " vs " ~ typeof(D(T.init)).stringof);
            static assert(is(typeof(D(T.init)) == D));
        }
        static foreach (T; FloatTypes)
            static assert(is(typeof(D(T.init)) == D));
        static foreach (T; CharTypes)
            static assert(is(typeof(D(T.init)) == D));
        static foreach (T; StringTypes)
        {
            //pragma(msg, T.stringof ~ " vs " ~ D.stringof ~ " vs " ~ typeof(D(T.init)).stringof);
            static assert(is(typeof(D(T.init)) == D));
        }
        static assert(is(typeof(D(true)) == D));
    }

    //assignment
    static foreach (D; DecimalTypes)
    {
        static foreach (T; DecimalTypes)
            static assert(__traits(compiles, { D d = T.init; }));
        static foreach (T; IntegralTypes)
            static assert(__traits(compiles, { D d = T.init; }));
        static foreach (T; FloatTypes)
            static assert(__traits(compiles, { D d = T.init; }));
        static foreach (T; CharTypes)
            static assert(__traits(compiles, { D d = T.init; }));
        static foreach (T; StringTypes)
            static assert(__traits(compiles, { D d = T.init; }));
        static assert(__traits(compiles, { D d = true; }));
    }

    //cast
    auto b = cast(float)Decimal32();
    static foreach (D; DecimalTypes)
    {
        static foreach (T; DecimalTypes)
            static assert(is(typeof(cast(T)(D.init)) == T));
        static foreach (T; IntegralTypes)
            static assert(is(typeof(cast(T)(D.init)) == T));
        static foreach (T; FloatTypes)
            static assert(is(typeof(cast(T)(D.init)) == T));
        static foreach (T; CharTypes)
            static assert(is(typeof(cast(T)(D.init)) == T));
        static assert(is(typeof(cast(bool)(D.init)) == bool));
    }

    //unary ops
    static foreach (D; DecimalTypes)
    {
        //pragma(msg, typeof(++D.init).stringof);
        static assert(is(typeof(+D.init) == const D));
        static assert(is(typeof(-D.init) == D));
        static assert(is(typeof(++D.init) == D));
        static assert(is(typeof(--D.init) == D));
    }

    //equality
    static foreach (D; DecimalTypes)
    {
        static foreach (T; DecimalTypes)
            static assert(is(typeof(D.init == T.init) == bool));
        static foreach (T; IntegralTypes)
            static assert(is(typeof(D.init == T.init) == bool));
        static foreach (T; FloatTypes)
            static assert(is(typeof(D.init == cast(T)0.0) == bool));
        static foreach (T; CharTypes)
            static assert(is(typeof(D.init == T.init) == bool));
    }

    //comparison
    auto c = Decimal128() > 0.0;
    static foreach (D; DecimalTypes)
    {
        static foreach (T; DecimalTypes)
            static assert(is(typeof(D.init > T.init) == bool));
        static foreach (T; IntegralTypes)
            static assert(is(typeof(D.init > T.init) == bool));
        static foreach (T; FloatTypes)
            static assert(is(typeof(D.init > cast(T)0.0) == bool));
        static foreach (T; CharTypes)
            static assert(is(typeof(D.init > T.init) == bool));
    }

    //binary left
    static foreach (D; DecimalTypes)
    {
        static foreach (T; DecimalTypes)
        {
            //pragma(msg, typeof(D.init ^^ T.init).stringof);
            static assert(is(typeof(D.init + T.init) == CommonDecimal!(D, T)));
            static assert(is(typeof(D.init - T.init) == CommonDecimal!(D, T)));
            static assert(is(typeof(D.init * T.init) == CommonDecimal!(D, T)));
            static assert(is(typeof(D.init / T.init) == CommonDecimal!(D, T)));
            static assert(is(typeof(D.init % T.init) == CommonDecimal!(D, T)));
            static assert(is(typeof(D.init ^^ T.init) == CommonDecimal!(D, T)));
        }

        static foreach (T; IntegralTypes)
        {
            //pragma(msg, typeof(D.init / T.init).stringof);
            static assert(is(typeof(D.init + T.init) == D));
            static assert(is(typeof(D.init - T.init) == D));
            static assert(is(typeof(D.init * T.init) == D));
            static assert(is(typeof(D.init / T.init) == D));
            static assert(is(typeof(D.init % T.init) == D));
            static assert(is(typeof(D.init ^^ T.init) == D));
        }

        {
            auto z = Decimal32.nan + float.nan;
        }

        static foreach (T; FloatTypes)
        {
            //pragma(msg, typeof(D.init ^^ T.init).stringof);
            static assert(is(typeof(D.init + T.init) == D));
            static assert(is(typeof(D.init - T.init) == D));
            static assert(is(typeof(D.init * T.init) == D));
            static assert(is(typeof(D.init / T.init) == D));
            static assert(is(typeof(D.init % T.init) == D));
            static assert(is(typeof(D.init ^^ T.init) == D));
        }

        static foreach (T; CharTypes)
        {
            static assert(is(typeof(D.init + T.init) == D));
            static assert(is(typeof(D.init - T.init) == D));
            static assert(is(typeof(D.init * T.init) == D));
            static assert(is(typeof(D.init / T.init) == D));
            static assert(is(typeof(D.init % T.init) == D));
            static assert(is(typeof(D.init ^^ T.init) == D));
        }
    }

    //binary right
    static foreach (D; DecimalTypes)
    {
        static foreach (T; DecimalTypes)
        {
            //pragma(msg, typeof(T.init ^^ D.init).stringof);
            static assert(is(typeof(T.init + D.init) == CommonDecimal!(D, T)));
            static assert(is(typeof(T.init - D.init) == CommonDecimal!(D, T)));
            static assert(is(typeof(T.init * D.init) == CommonDecimal!(D, T)));
            static assert(is(typeof(T.init / D.init) == CommonDecimal!(D, T)));
            static assert(is(typeof(T.init % D.init) == CommonDecimal!(D, T)));
            static assert(is(typeof(T.init ^^ D.init) == CommonDecimal!(D, T)));
        }

        static foreach (T; IntegralTypes)
        {
            //pragma(msg, typeof(T.init ^^ D.init).stringof);
            //pragma(msg, typeof(T.init / D.init).stringof);
            static assert(is(typeof(T.init + D.init) == D));
            static assert(is(typeof(T.init - D.init) == D));
            static assert(is(typeof(T.init * D.init) == D));
            static assert(is(typeof(T.init / D.init) == D));
            static assert(is(typeof(T.init % D.init) == D));
            static assert(is(typeof(T.init ^^ D.init) == D));
        }

        static foreach (T; FloatTypes)
        {
            pragma(msg, typeof(T.init ^^ D.init).stringof);
            static assert(is(typeof(T.init + D.init) == D));
            static assert(is(typeof(T.init - D.init) == D));
            static assert(is(typeof(T.init * D.init) == D));
            static assert(is(typeof(T.init / D.init) == D));
            static assert(is(typeof(T.init % D.init) == D));
            static assert(is(typeof(T.init ^^ D.init) == D));
        }

        static foreach (T; CharTypes)
        {
            //pragma(msg, typeof(T.init ^^ D.init).stringof);
            static assert(is(typeof(T.init + D.init) == D));
            static assert(is(typeof(T.init - D.init) == D));
            static assert(is(typeof(T.init * D.init) == D));
            static assert(is(typeof(T.init / D.init) == D));
            static assert(is(typeof(T.init % D.init) == D));
            static assert(is(typeof(T.init ^^ D.init) == D));
        }
    }

    //op assignment
    static foreach (D; DecimalTypes)
    {
        static foreach (T; DecimalTypes)
        {
            static assert(is(typeof(D.init += T.init) == D));
            static assert(is(typeof(D.init -= T.init) == D));
            static assert(is(typeof(D.init *= T.init) == D));
            static assert(is(typeof(D.init /= T.init) == D));
            static assert(is(typeof(D.init %= T.init) == D));
            static assert(is(typeof(D.init ^^= T.init) == D));
        }

        static foreach (T; IntegralTypes)
        {
            static assert(is(typeof(D.init += T.init) == D));
            static assert(is(typeof(D.init -= T.init) == D));
            static assert(is(typeof(D.init *= T.init) == D));
            static assert(is(typeof(D.init /= T.init) == D));
            static assert(is(typeof(D.init %= T.init) == D));
            static assert(is(typeof(D.init ^^= T.init) == D));
        }

        static foreach (T; FloatTypes)
        {
            static assert(is(typeof(D.init += T.init) == D));
            static assert(is(typeof(D.init -= T.init) == D));
            static assert(is(typeof(D.init *= T.init) == D));
            static assert(is(typeof(D.init /= T.init) == D));
            static assert(is(typeof(D.init %= T.init) == D));
            static assert(is(typeof(D.init ^^= T.init) == D));
        }

        static foreach (T; CharTypes)
        {
            static assert(is(typeof(D.init += T.init) == D));
            static assert(is(typeof(D.init -= T.init) == D));
            static assert(is(typeof(D.init *= T.init) == D));
            static assert(is(typeof(D.init /= T.init) == D));
            static assert(is(typeof(D.init %= T.init) == D));
            static assert(is(typeof(D.init ^^= T.init) == D));
        }
    }

    //expected constants
    static foreach (D; DecimalTypes)
    {
        static assert(is(typeof(D.init) == D));
        static assert(is(typeof(D.nan) == D));
        static assert(is(typeof(D.infinity) == D));
        static assert(is(typeof(D.max) == D));
        static assert(is(typeof(D.min_normal) == D));
        static assert(is(typeof(D.epsilon) == D));
        static assert(is(typeof(D.dig) == int));
        static assert(is(typeof(D.mant_dig) == int));
        static assert(is(typeof(D.min_10_exp) == int));
        static assert(is(typeof(D.max_10_exp) == int));
        static assert(is(typeof(D.min_exp) == int));
        static assert(is(typeof(D.max_exp) == int));

        static assert(is(typeof(D.E) == D));
        static assert(is(typeof(D.PI) == D));
        static assert(is(typeof(D.pi_2) == D));
        static assert(is(typeof(D.pi_4) == D));
        static assert(is(typeof(D.m_1_pi) == D));
        static assert(is(typeof(D.m_2_pi) == D));
        static assert(is(typeof(D.m_2_sqrtpi) == D));
        static assert(is(typeof(D.LN10) == D));
        static assert(is(typeof(D.LN2) == D));
        static assert(is(typeof(D.LOG2) == D));
        static assert(is(typeof(D.LOG2E) == D));
        static assert(is(typeof(D.LOG2T) == D));
        static assert(is(typeof(D.LOG10E) == D));
        static assert(is(typeof(D.sqrt2) == D));
        static assert(is(typeof(D.sqrt1_2) == D));
    }

    //expected members
    static foreach (D; DecimalTypes)
    {
        static assert(is(typeof(D.init.toHash()) == size_t));
        static assert(is(typeof(D.init.toString()) == string));
    }
}

unittest // Default value
{
    import std.meta : AliasSeq;

    foreach (T; AliasSeq!(Decimal32, Decimal64, Decimal128))
    {
        assert(T().isZero);
        assert(T.init.isZero);
    }

    static assert(Decimal32.sizeof == 4);
    static assert(Decimal64.sizeof == 8);
    static assert(Decimal128.sizeof == 16);
}

unittest
{
    version(D_BetterC)
    {}
    else
    {
        import std.exception : assertThrown;

        assertThrown!InvalidOperationException(Decimal128(""));
        assertThrown!InvalidOperationException(Decimal128(" "));
        assertThrown!InvalidOperationException(Decimal128("_"));
        assertThrown!InvalidOperationException(Decimal128("+"));
        assertThrown!InvalidOperationException(Decimal128("-"));
        assertThrown!InvalidOperationException(Decimal128("."));
        assertThrown!InvalidOperationException(Decimal128("294574L20484.87"));
    }
}

@("Decimal should support decimal + float")
unittest
{
    auto sut = Decimal128("1");
    auto result = sut + 1.0f;

    assert(result == Decimal128("2"));
}

@("Decimal should support decimal - float")
unittest
{
    auto sut = Decimal128("9");
    auto result = sut - 4.0f;

    assert(result == Decimal128("5"));
}

@("Decimal should support decimal * float")
unittest
{
    auto sut = Decimal128("1.33");
    auto result = sut * 10.0f;

    assert(result == Decimal128("13.3"));
}

@("Decimal should support decimal / float")
unittest
{
    auto sut = Decimal128("1");
    auto result = sut / 2.0f;

    assert(result == Decimal128("0.5"), result.toString());
}

@("Decimal should support decimal % float")
unittest
{
    auto sut = Decimal128("10");
    auto result = sut % 3.0f;

    assert(result == Decimal128("1"), result.toString());
}

@("Decimal should support decimal + integral")
unittest
{
    auto sut = Decimal128("2");
    auto result = sut + 1;

    assert(result == Decimal128("3"));
}

@("Decimal should support decimal - integral")
unittest
{
    auto sut = Decimal128("3");
    auto result = sut - 2;

    assert(result == Decimal128("1"));
}

@("Decimal should support decimal * integral")
unittest
{
    auto sut = Decimal128("12.34");
    auto result = sut * 10;

    assert(result == Decimal128("123.4"));
}

@("Decimal should support decimal / integral")
unittest
{
    auto sut = Decimal128("1");
    auto result = sut / 2;

    assert(result == Decimal128("0.5"), result.toString());
}

@("Decimal should support decimal % integral")
unittest
{
    auto sut = Decimal128("10");
    auto result = sut % 3;

    assert(result == Decimal128("1"), result.toString());
}

@("Decimal should support decimal % unsigned integral")
unittest
{
    auto sut = Decimal128("10");
    auto result = sut % 3u;

    assert(result == Decimal128("1"), result.toString());
}

///Returns the most wide Decimal... type among the specified types
template CommonDecimal(Ts...)
if (isDecimal!Ts)
{
    static if (Ts.length == 0)
        alias CommonDecimal = Decimal128;
    else static if (Ts.length == 1)
        alias CommonDecimal = Ts[0];
    else static if (Ts.length == 2)
    {
        static if (Ts[0].sizeof > Ts[1].sizeof)
            alias CommonDecimal = Ts[0];
        else
            alias CommonDecimal = Ts[1];
    }
    else
        alias CommonDecimal = CommonDecimal!(CommonDecimal!(Ts[0 .. 1], CommonDecimal!(Ts[2 .. $])));
}

///
unittest
{
    static assert(is(CommonDecimal!(Decimal32, Decimal32) == Decimal32));
    static assert(is(CommonDecimal!(Decimal32, Decimal64) == Decimal64));
    static assert(is(CommonDecimal!(Decimal32, Decimal128) == Decimal128));
    static assert(is(CommonDecimal!(Decimal64, Decimal64) == Decimal64));
    static assert(is(CommonDecimal!(Decimal64, Decimal128) == Decimal128));
    static assert(is(CommonDecimal!(Decimal128, Decimal128) == Decimal128));
}

/**
Returns the decimal class where x falls into.
This operation is silent, no exception flags are set and no exceptions are thrown.
Params:
    x = a _decimal value
Returns:
    One of the members of $(MYREF DecimalClass) enumeration
*/
@IEEECompliant("class", 25)
DecimalClass decimalClass(D)(const auto ref D x)
if (isDecimal!D)
{
    DataType!(D.sizeof) coefficient;
    uint exponent;

    static if (is(D: Decimal32) || is(D: Decimal64))
    {
        if ((x.data & D.MASK_INF) == D.MASK_INF)
        {
            if ((x.data & D.MASK_QNAN) == D.MASK_QNAN)
                return (x.data & D.MASK_SNAN) == D.MASK_SNAN ? DecimalClass.signalingNaN : DecimalClass.quietNaN;
            else
                return (x.data & D.MASK_SGN) ? DecimalClass.negativeInfinity : DecimalClass.positiveInfinity;
        }
        else if ((x.data & D.MASK_EXT) == D.MASK_EXT)
        {
            coefficient = (x.data & D.MASK_COE2) | D.MASK_COEX;
            if (coefficient > D.COEF_MAX)
                return x.data & D.MASK_SGN ? DecimalClass.negativeZero : DecimalClass.positiveZero;
            exponent = cast(uint)((x.data & D.MASK_EXP2) >>> D.SHIFT_EXP2);
        }
        else
        {
            coefficient = x.data & D.MASK_COE1;
            if (coefficient == 0U)
                return (x.data & D.MASK_SGN) == D.MASK_SGN ? DecimalClass.negativeZero : DecimalClass.positiveZero;
            exponent = cast(uint)((x.data & D.MASK_EXP1) >>> D.SHIFT_EXP1);
        }
        const bool sx = (x.data & D.MASK_SGN) == D.MASK_SGN;
    }
    else
    {
        if ((x.data.hi & D.MASK_INF.hi) == D.MASK_INF.hi)
        {
            if ((x.data.hi & D.MASK_QNAN.hi) == D.MASK_QNAN.hi)
                return (x.data.hi & D.MASK_SNAN.hi) == D.MASK_SNAN.hi ? DecimalClass.signalingNaN : DecimalClass.quietNaN;
            else
                return (x.data.hi & D.MASK_SGN.hi) ? DecimalClass.negativeInfinity : DecimalClass.positiveInfinity;
        }
        else if ((x.data.hi & D.MASK_EXT.hi) == D.MASK_EXT.hi)
            return (x.data.hi & D.MASK_SGN.hi) == D.MASK_SGN.hi ? DecimalClass.negativeZero : DecimalClass.positiveZero;
        else
        {
            coefficient = x.data & D.MASK_COE1;
            if (coefficient == 0U || coefficient > D.COEF_MAX)
                return (x.data.hi & D.MASK_SGN.hi) == D.MASK_SGN.hi ? DecimalClass.negativeZero : DecimalClass.positiveZero;
            exponent = cast(uint)((x.data & D.MASK_EXP1) >>> D.SHIFT_EXP1);
        }
        const bool sx = (x.data.hi & D.MASK_SGN.hi) == D.MASK_SGN.hi;
    }

    if (exponent < D.PRECISION - 1)
    {
        if (prec(coefficient) < D.PRECISION - exponent)
            return sx ? DecimalClass.negativeSubnormal : DecimalClass.positiveSubnormal;
    }

    return sx ? DecimalClass.negativeNormal : DecimalClass.positiveNormal;
}

///
unittest
{
    assert(decimalClass(Decimal32.nan) == DecimalClass.quietNaN);
    assert(decimalClass(Decimal64.infinity) == DecimalClass.positiveInfinity);
    assert(decimalClass(Decimal128.max) == DecimalClass.positiveNormal);
    assert(decimalClass(-Decimal32.max) == DecimalClass.negativeNormal);
    assert(decimalClass(Decimal128.epsilon) == DecimalClass.positiveNormal);
}

unittest
{
    import std.meta : AliasSeq;

    foreach (T; AliasSeq!(Decimal32, Decimal64, Decimal128))
    {
        assert(decimalClass(T.sNaN) == DecimalClass.signalingNaN);
        assert(decimalClass(T.qNaN) == DecimalClass.quietNaN);
        assert(decimalClass(T.negInfinity) == DecimalClass.negativeInfinity);
        assert(decimalClass(T.infinity) == DecimalClass.positiveInfinity);
        assert(decimalClass(T.zero) == DecimalClass.positiveZero);
        assert(decimalClass(T.negZero) == DecimalClass.negativeZero);
        assert(decimalClass(T.subn) == DecimalClass.positiveSubnormal);
        assert(decimalClass(T.negSubn) == DecimalClass.negativeSubnormal);
        assert(decimalClass(T.ten) == DecimalClass.positiveNormal);
        assert(decimalClass(T.negTen) == DecimalClass.negativeNormal);
        assert(decimalClass(T.max) == DecimalClass.positiveNormal);
        assert(decimalClass(-T.max) == DecimalClass.negativeNormal);
        assert(decimalClass(T.min_normal) == DecimalClass.positiveNormal);
        assert(decimalClass(T.epsilon) == DecimalClass.positiveNormal);
    }
}

/**
Returns the decimal class where x falls into.
This operation is silent, no exception flags are set and no exceptions are thrown.
Params:
    x = a _decimal value
Returns:
    One of the members of $(MYREF DecimalSubClass) enumeration
*/
DecimalSubClass decimalSubClass(D)(const auto ref D x)
if (isDecimal!D)
{
    static if (is(D: Decimal128))
    {
        if ((x.data.hi & D.MASK_INF.hi) == D.MASK_INF.hi)
        {
            if ((x.data.hi & D.MASK_QNAN.hi) == D.MASK_QNAN.hi)
                return (x.data.hi & D.MASK_SNAN.hi) == D.MASK_SNAN.hi ? DecimalSubClass.signalingNaN : DecimalSubClass.quietNaN;
            else
                return (x.data.hi & D.MASK_SGN.hi) ? DecimalSubClass.negativeInfinity : DecimalSubClass.positiveInfinity;
        }
        else
            return DecimalSubClass.finite;
    }
    else
    {
        if ((x.data & D.MASK_INF) == D.MASK_INF)
        {
            if ((x.data & D.MASK_QNAN) == D.MASK_QNAN)
                return (x.data & D.MASK_SNAN) == D.MASK_SNAN ? DecimalSubClass.signalingNaN : DecimalSubClass.quietNaN;
            else
                return (x.data & D.MASK_SGN) ? DecimalSubClass.negativeInfinity : DecimalSubClass.positiveInfinity;
        }
        else
            return DecimalSubClass.finite;
    }
}

/* Logical functions */

/**
Computes whether two values are approximately equal, admitting a maximum relative difference,
or a maximum absolute difference.
Params:
    x = First item to compare
    y = Second item to compare
    maxRelDiff = Maximum allowable relative difference (defaults to 1e-5)
    maxAbsDiff = Maximum allowable absolute difference (defaults to 1e-2)
Returns:
    true if the two items are approximately equal under either criterium.
Notes:
    This operation is silent, does not throw any exceptions and it doesn't set any error flags.
*/
bool approxEqual(D1, D2, D3, D4)(const auto ref D1 x, const auto ref D2 y,
    const auto ref D3 maxRelDiff, const auto ref D4 maxAbsDiff) @nogc nothrow @safe
if (isDecimal!(D1, D2, D3, D4))
{
    if (x.isInfinity != 0 && y.isInfinity != 0)
        return signbit(x) == signbit(y);
    else
    {
        const rounding = __ctfe ? RoundingMode.implicit : DecimalControl.rounding;
        alias D = CommonDecimal!(D1, D2, D3, D4);

        D d;
        decimalToDecimal(x, d, D.PRECISION, rounding);
        decimalSub(d, y, D.PRECISION, rounding);

        d = fabs(d);
        if (decimalCmp(maxAbsDiff, d) >= 0)
            return true;

        decimalDiv(d, y, D.PRECISION, rounding);
        if (decimalCmp(maxRelDiff, d) >= 0)
            return true;
    }
    return false;
}

///ditto
bool approxEqual(D1, D2, D3)(const auto ref D1 x, const auto ref D2 y,
    const auto ref D3 maxRelDiff) @nogc nothrow @safe
if (isDecimal!(D1, D2, D3))
{
    enum maxAbsDiff = CommonDecimal!(D1, D2, D3)("1e-5");
    return approxEqual(x, y, maxRelDiff, maxAbsDiff);
}

///ditto
bool approxEqual(D1, D2)(const auto ref D1 x, const auto ref D2 y) @nogc nothrow @safe
if (isDecimal!(D1, D2))
{
    enum maxAbsDiff = CommonDecimal!(D1, D2)("1e-5");
    enum maxRelDiff = CommonDecimal!(D1, D2)("1e-2");
    return approxEqual(x, y, maxRelDiff, maxAbsDiff);
}

/**
Defines a total order on all _decimal values.
Params:
    x = a _decimal value
    y = a _decimal value
Returns:
    -1 if x precedes y, 0 if x is equal to y, +1 if x follows y
Notes:
    The total order is defined as:<br/>
    - -sNaN < -$(B NaN) < -infinity < -finite < -0.0 < +0.0 < +finite < +infinity < +$(B NaN) < +sNaN<br/>
    - for two $(B NaN) values the total order is defined based on the payload
*/
pragma(inline, true)
float cmp(D1, D2)(const auto ref D1 x, const auto ref D2 y) @nogc nothrow pure @safe
if (isDecimal!(D1, D2))
{
    return decimalCmp(x, y);

    /*
    const c = decimalCmp(x, y);

    // Not accept NaN?
    version(none)
    if (.isNaN(c))
        DecimalControl.setFlags(ExceptionFlags.invalidOperation);

    return .isNaN(c) ? float.nan : c;
    */
}

///
unittest
{
    assert(isNaN(cmp(-Decimal32.nan, Decimal64.max)));
    assert(cmp(Decimal32.max, Decimal128.min_normal) == 1);
    assert(cmp(Decimal64(0), -Decimal64(0)) == 0);

    static Decimal64 toFloatDecimal(long scaleNumber)
    {
        auto result = Decimal64(scaleNumber);
        result /= 100L;

        Decimal64 result2 = scaleNumber;
        result2 /= 100L;
        assert(result ==  result2);

        return result;
    }

    string s1, s2;

    s1 = toFloatDecimal(540).toString();
    assert(s1 == "5.40" || s1 == "5.4", s1);
    s2 = Decimal64.money(5.40, 2).toString();
    assert(s2 == "5.40" || s2 == "5.4", s2);
    assert(cmp(toFloatDecimal(540), Decimal64.money(5.40, 2)) == 0, s1 ~ " vs " ~ s2);

    s1 = toFloatDecimal(640).toString();
    assert(s1 == "6.40" || s1 == "6.4", s1);
    s2 = Decimal64.money(6.40, 2).toString();
    assert(s2 == "6.40" || s2 == "6.4", s2);
    assert(cmp(toFloatDecimal(640), Decimal64.money(6.40, 2)) == 0, s1 ~ " vs " ~ s2);

    assert(cmp(Decimal64("5.40"), Decimal64.money(5.40, 2)) == 0);
    assert(cmp(Decimal64("6.40"), Decimal64.money(6.40, 2)) == 0);
}

///
pragma(inline, true)
float cmp(D, F)(const auto ref D x, const auto ref F y, const(int) yPrecision, const(RoundingMode) yMode,
    const(int) yMaxFractionalDigits) @nogc nothrow pure @safe
if (isDecimal!D && isFloatingPoint!F)
{
    return decimalCmp(x, y, yPrecision, yMode, yMaxFractionalDigits);
    /*
    const c = decimalCmp(x, y, yPrecision, yMode, yMaxFractionalDigits);

    version(none)
    if (.isNaN(c))
        DecimalControl.setFlags(ExceptionFlags.invalidOperation);

    return .isNaN(c) ? float.nan : c;
    */
}

///
pragma(inline, true)
float cmp(D, I)(const auto ref D x, const auto ref I y) @nogc nothrow pure @safe
if (isDecimal!D && isIntegral!I)
{
    return decimalCmp(x, y);

    /*
    const c = decimalCmp(x, y);

    version(none)
    if (.isNaN(c))
        DecimalControl.setFlags(ExceptionFlags.invalidOperation);

    return .isNaN(c) ? float.nan : c;
    */
}

///
unittest
{
    assert(cmp(Decimal32(540), 540) == 0);
}

/**
Compares two _decimal operands for equality
Returns:
    true if the specified condition is satisfied, false otherwise or if any of the operands is $(B NaN).

version(none)
Notes:
    By default, $(MYREF Decimal.opEquals) is silent, returning false if a $(B NaN) value is encountered.
    isEqual and isNotEqual will throw $(MYREF InvalidOperationException) or will
    set the $(MYREF ExceptionFlags.invalidOperation) context flag if a trap is not set.
*/

@IEEECompliant("compareSignalingEqual", 24)
bool isEqual(D1, D2)(const auto ref D1 x, const auto ref D2 y) @nogc nothrow pure @safe
if (isDecimal!(D1, D2))
{
    return decimalEqu(x, y) == 1;

    /*
    const c = decimalEqu(x, y);

    // Not accept NaN?
    version(none)
    if (.isNaN(c))
        DecimalControl.setFlags(ExceptionFlags.invalidOperation);

    return c == 1;
    */
}

///
unittest
{
    assert(isEqual(Decimal32.max, Decimal32.max));
    assert(isEqual(Decimal64.min, Decimal64.min));
    assert(isEqual(Decimal64(0), -Decimal64(0)));

    static Decimal64 toFloatDecimal(long scaleNumber)
    {
        Decimal64 result = scaleNumber;
        result = result / 100L;
        return result;
    }

    assert(isEqual(toFloatDecimal(540), Decimal64.money(5.40, 2)));
    assert(isEqual(toFloatDecimal(640), Decimal64.money(6.40, 2)));
    assert(isEqual(Decimal64("5.40"), Decimal64.money(5.40, 2)));
    assert(isEqual(Decimal64("6.40"), Decimal64.money(6.40, 2)));
}

@IEEECompliant("compareSignalingEqual", 24)
bool isEqual(D, F)(const auto ref D x, const auto ref F y, const(int) yPrecision, const(RoundingMode) yMode,
    const(int) yMaxFractionalDigits) @nogc nothrow pure @safe
if (isDecimal!D && isFloatingPoint!F)
{
    return decimalEqu(x, y, yPrecision, yMode, yMaxFractionalDigits) == 1;

    /*
    const c = decimalEqu(x, y, yPrecision, yMode, yMaxFractionalDigits);

    // Not accept NaN?
    version(none)
    if (.isNaN(c))
        DecimalControl.setFlags(ExceptionFlags.invalidOperation);

    return c == 1;
    */
}

@IEEECompliant("compareSignalingEqual", 24)
bool isEqual(D, I)(const auto ref D x, const auto ref I y) @nogc nothrow pure @safe
if (isDecimal!D && isIntegral!I)
{
    return decimalEqu(x, y) == 1;

    /*
    const c = decimalEqu(x, y);

    // Not accept NaN?
    version(none)
    if (.isNaN(c))
        DecimalControl.setFlags(ExceptionFlags.invalidOperation);

    return c == 1;
    */
}

///
unittest
{
    assert(isEqual(Decimal32(540), 540));
}

///ditto
@IEEECompliant("compareSignalingNotEqual", 24)
bool isNotEqual(D1, D2)(const auto ref D1 x, const auto ref D2 y) @nogc nothrow pure @safe
if (isDecimal!(D1, D2))
{
    const c = decimalEqu(x, y);

    if (.isNaN(c))
    {
        version(none)
        DecimalControl.setFlags(ExceptionFlags.invalidOperation);

        return false;
    }

    return c != 1;
}

///
unittest
{
    assert(isNotEqual(Decimal32.max, Decimal32.min));
    assert(isNotEqual(Decimal32.max, Decimal32.min_normal));
}

/**
Compares two _decimal operands.
This operation is silent, no exception flags are set and no exceptions are thrown.
Returns:
    true if the specified condition is satisfied
Notes:
    By default, comparison operators will throw $(MYREF InvalidOperationException) or will
    set the $(MYREF ExceptionFlags.invalidOperation) context flag if a trap is not set.
    The equivalent functions are silent and will not throw any exception (or will not set any flag)
    if a $(B NaN) value is encountered.
*/
@IEEECompliant("compareQuietGreater", 24)
bool isGreater(D1, D2)(const auto ref D1 x, const auto ref D2 y) @nogc nothrow pure @safe
if (isDecimal!(D1, D2))
{
    const c = decimalCmp(x, y);

    version(none)
    if (.isNaN(c))
        DecimalControl.setFlags(ExceptionFlags.invalidOperation);

    return c > 0;
}

///ditto
@IEEECompliant("compareQuietGreaterEqual", 24)
bool isGreaterOrEqual(D1, D2)(const auto ref D1 x, const auto ref D2 y) @nogc nothrow pure @safe
if (isDecimal!(D1, D2))
{
    const c = decimalCmp(x, y);

    version(none)
    if (.isNaN(c))
        DecimalControl.setFlags(ExceptionFlags.invalidOperation);

    return c >= 0;
}

///ditto
@IEEECompliant("compareQuietGreaterUnordered", 24)
bool isGreaterOrUnordered(D1, D2)(const auto ref D1 x, const auto ref D2 y) @nogc nothrow pure @safe
if (isDecimal!(D1, D2))
{
    const c = decimalCmp(x, y);
    return .isNaN(c) || c > 0;
}

///ditto
@IEEECompliant("compareQuietLess", 24)
@IEEECompliant("compareQuietNotLess", 24)
bool isLess(D1, D2)(const auto ref D1 x, const auto ref D2 y) @nogc nothrow pure @safe
if (isDecimal!(D1, D2))
{
    const c = decimalCmp(x, y);

    version(none)
    if (.isNaN(c))
        DecimalControl.setFlags(ExceptionFlags.invalidOperation);

    return c < 0;
}

///ditto
@IEEECompliant("compareQuietLessEqual", 24)
bool isLessOrEqual(D1, D2)(const auto ref D1 x, const auto ref D2 y) @nogc nothrow pure @safe
if (isDecimal!(D1, D2))
{
    const c = decimalCmp(x, y);

    if (.isNaN(c))
    {
        version(none)
        DecimalControl.setFlags(ExceptionFlags.invalidOperation);

        return false;
    }

    return c <= 0;
}

///ditto
@IEEECompliant("compareQuietLessUnordered", 24)
bool isLessOrUnordered(D1, D2)(const auto ref D1 x, const auto ref D2 y) @nogc nothrow pure @safe
if (isDecimal!(D1, D2))
{
    const c = decimalCmp(x, y);
    return .isNaN(c) || c < 0;
}

///ditto
@IEEECompliant("compareQuietOrdered", 24)
@IEEECompliant("compareQuietUnordered", 24)
bool isUnordered(D1, D2)(const auto ref D1 x, const auto ref D2 y) @nogc nothrow pure @safe
if (isDecimal!(D1, D2))
{
    return isNaN(decimalCmp(x, y));
}

///
unittest
{
    assert(isUnordered(Decimal32.nan, Decimal64.max));
    assert(isGreater(Decimal32.infinity, Decimal128.max));
    assert(isGreaterOrEqual(Decimal32.infinity, Decimal64.infinity));
    assert(isLess(Decimal64.max, Decimal128.max));
    assert(isLessOrEqual(Decimal32.min_normal, Decimal32.min_normal));
}

unittest
{
    import std.meta : AliasSeq;

    foreach (T; AliasSeq!(Decimal32, Decimal64, Decimal128))
    {
        assert(isUnordered(T.nan, T.one));
        assert(isUnordered(T.one, T.nan));
        assert(isUnordered(T.nan, T.nan));

        assert(isGreater(T.max, T.ten));
        assert(isGreater(T.ten, T.one));
        assert(isGreater(-T.ten, -T.max));
        assert(isGreater(T.zero, -T.max));
        assert(isGreater(T.max, T.zero));

        assert(isLess(T.one, T.ten), T.stringof);
        assert(isLess(T.ten, T.max));
        assert(isLess(-T.max, -T.one));
        assert(isLess(T.zero, T.max));
        assert(isLess(T.max, T.infinity));
    }
}

/* Other helper functions */

/**
Computes (1 + x)$(SUPERSCRIPT n) where n is an integer
Throws:
$(BOOKTABLE,
    $(TR $(TD $(MYREF InvalidOperationException))
         $(TD x is signaling $(B NaN) or x < -1.0))
    $(TR $(TD $(MYREF DivisionByZeroException))
         $(TD x = -1.0 and n < 0))
    $(TR $(TD $(MYREF OverflowException))
         $(TD result is too big to be represented))
    $(TR $(TD $(MYREF UnderflowException))
         $(TD result is too small to be represented))
    $(TR $(TD $(MYREF InexactException))
         $(TD the result is inexact))
)
Special_values:
$(BOOKTABLE,
    $(TR $(TH x) $(TH n) $(TH compound(x, n)))
    $(TR $(TD sNaN) $(TD any) $(TD $(B NaN)))
    $(TR $(TD any) $(TD 0) $(TD +1.0))
    $(TR $(TD -1.0) $(TD <0) $(TD +∞))
    $(TR $(TD -1.0) $(TD >0) $(TD +0.0))
    $(TR $(TD +∞) $(TD any) $(TD +∞))
)
*/
@IEEECompliant("compound", 42)
auto compound(D)(const auto ref D x, const(int) n)
if (isDecimal!D)
{
    Unqual!D result = x;
    auto flags = decimalCompound(result, n,
                               __ctfe ? D.PRECISION : DecimalControl.precision,
                               __ctfe ? RoundingMode.implicit: DecimalControl.rounding);
    DecimalControl.raiseFlags(flags);
    return result;
}

unittest
{
    import std.meta : AliasSeq;

    foreach (T; AliasSeq!(Decimal32, Decimal64, Decimal128))
    {
        assert(compound(T.ten, 0) == 1);
        assert(compound(T.infinity, 0) == 1);
        assert(compound(-T.one, 0) == 1);
        assert(compound(T.zero, 0) == 1);
        assert(compound(-T.one, 5) == 0);
        assert(compound(T.infinity, 5) == T.infinity);
    }
}

///
unittest
{
    Decimal32 x = "0.2";
    assert(compound(x, 2) == Decimal32("1.44"));
}

/**
Copies the sign of a _decimal value _to another.
This operation is silent, no error flags are set and no exceptions are thrown.
Params:
    to = a _decimal value to copy
    from = a _decimal value from which the sign is copied
Returns:
    to with the sign of from
*/
@IEEECompliant("copySign", 23)
D1 copysign(D1, D2)(const auto ref D1 to, const auto ref D2 from) @nogc nothrow pure @safe
if (isDecimal!(D1, D2))
{
    Unqual!D1 result = to;
    const bool sx = cast(bool)((from.data & D2.MASK_SGN) == D2.MASK_SGN);

    static if (is(D1: Decimal32) || is(D1: Decimal64))
    {
        if (sx)
            result.data |= D1.MASK_SGN;
        else
            result.data &= ~D1.MASK_SGN;
    }
    else
    {
        if (sx)
            result.data.hi |= D1.MASK_SGN.hi;
        else
            result.data.hi &= ~D1.MASK_SGN.hi;
    }

    return result;
}

///
unittest
{
    Decimal32 negative = -Decimal32.min_normal;
    Decimal64 test = Decimal64.max;
    assert(copysign(test, negative) == -Decimal64.max);
}


/* Math functions */

/**
Calculates the arc cosine of x, returning a value ranging from 0 to π.
Exceptions:
$(BOOKTABLE,
    $(TR $(TD $(MYREF InvalidOperationException))
         $(TD x is signaling $(B NaN) or |x| > 1.0))
    $(TR $(TD $(MYREF InexactException))
         $(TD the result is inexact))
)
Special_values:
$(BOOKTABLE,
    $(TR $(TH x) $(TH acos(x)))
    $(TR $(TD $(B NaN)) $(TD $(B NaN)))
    $(TR $(TD -1.0) $(TD π))
    $(TR $(TD +1.0) $(TD +0.0))
    $(TR $(TD < -1.0) $(TD $(B NaN)))
    $(TR $(TD > +1.0) $(TD $(B NaN)))
)
*/
@IEEECompliant("acos", 43)
D acos(D)(const auto ref D x)
if (isDecimal!D)
{
    enum checkFlags = ExceptionFlags.inexact | ExceptionFlags.invalidOperation;
    Unqual!D result = x;
    const flags = decimalAcos(result,
                             __ctfe ? D.PRECISION : DecimalControl.precision,
                             __ctfe ? RoundingMode.implicit: DecimalControl.rounding);
    DecimalControl.raiseFlags(flags & checkFlags);
    return result;
}

///
unittest
{
    Decimal32 x = 0;
    assert(acos(x) == Decimal32.pi_2);
}

unittest
{
    import std.meta : AliasSeq;

    foreach (T; AliasSeq!(Decimal32, Decimal64, Decimal128))
    {
        assert(acos(-T.one) == T.PI);
        assert(acos(T.one) == 0);
        assert(acos(T.zero) == T.pi_2);
        assert(acos(T.nan).isNaN);
    }
}

/**
Calculates the inverse hyperbolic cosine of x
Exceptions:
$(BOOKTABLE,
    $(TR $(TD $(MYREF InvalidOperationException))
         $(TD x is signaling $(B NaN) or x < 1.0))
    $(TR $(TD $(MYREF InexactException))
         $(TD the result is inexact))
)
Special_values:
$(BOOKTABLE,
    $(TR $(TH x) $(TH acosh(x)))
    $(TR $(TD $(B NaN)) $(TD $(B NaN)))
    $(TR $(TD +1.0) $(TD +0.0))
    $(TR $(TD +∞) $(TD +∞))
    $(TR $(TD < 1.0) $(TD $(B NaN)))
)
*/
@IEEECompliant("acosh", 43)
D acosh(D)(const auto ref D x)
if (isDecimal!D)
{
    enum checkFlags = ExceptionFlags.inexact | ExceptionFlags.invalidOperation;
    Unqual!D result = x;
    const flags = decimalAcosh(result,
                             __ctfe ? D.PRECISION : DecimalControl.precision,
                             __ctfe ? RoundingMode.implicit: DecimalControl.rounding);
    DecimalControl.raiseFlags(flags & checkFlags);
    return result;
}

///
unittest
{
    Decimal32 x = 1;
    assert(acosh(x) == 0);
}

unittest
{
    import std.meta : AliasSeq;

    foreach (T; AliasSeq!(Decimal32, Decimal64, Decimal128))
    {
        assert(acosh(T.one) == T.zero);
        assert(acosh(T.infinity) == T.infinity);
        assert(acosh(T.nan).isNaN);
    }
}

/**
Returns cosine of x.
Throws:
$(BOOKTABLE,
    $(TR $(TD $(MYREF InvalidOperationException))
         $(TD x is signaling $(B NaN) or ±∞))
    $(TR $(TD $(MYREF UnderflowException))
         $(TD result is too small to be represented))
    $(TR $(TD $(MYREF InexactException))
         $(TD the result is inexact))
)
Special_values:
$(BOOKTABLE,
    $(TR $(TH x) $(TH cos(x)))
    $(TR $(TD $(B NaN)) $(TD $(B NaN)))
    $(TR $(TD ±∞) $(TD $(B NaN)))
    $(TR $(TD ±0.0) $(TD +1.0))
    $(TR $(TD π/6) $(TD +√3/2))
    $(TR $(TD π/4) $(TD +√2/2))
    $(TR $(TD π/3) $(TD +0.5))
    $(TR $(TD π/2) $(TD +0.0))
    $(TR $(TD 2π/3) $(TD -0.5))
    $(TR $(TD 3π/4) $(TD -√2/2))
    $(TR $(TD 5π/6) $(TD -√3/2))
    $(TR $(TD π) $(TD -1.0))
)
*/
@IEEECompliant("cos", 42)
D cos(D)(const auto ref D x)
if (isDecimal!D)
{
    Unqual!D result = x;
    const flags = decimalCos(result,
                             __ctfe ? D.PRECISION : DecimalControl.precision,
                             __ctfe ? RoundingMode.implicit: DecimalControl.rounding);
    DecimalControl.raiseFlags(flags);
    return result;
}

/**
Calculates the hyperbolic cosine of x.
Throws:
$(BOOKTABLE,
    $(TR $(TD $(MYREF InvalidOperationException))
         $(TD x is signaling $(B NaN)))
    $(TR $(TD $(MYREF OverflowException))
         $(TD result is too big to be represented))
    $(TR $(TD $(MYREF InexactException))
         $(TD the result is inexact))
)
Special_values:
$(BOOKTABLE,
    $(TR $(TH x) $(TH cosh(x)))
    $(TR $(TD $(B NaN)) $(TD $(B NaN)))
    $(TR $(TD ±∞) $(TD +∞))
    $(TR $(TD ±0.0) $(TD +1.0))
)
*/
@IEEECompliant("cosh", 42)
D cosh(D)(const auto ref D x)
if (isDecimal!D)
{
    Unqual!D result = x;
    const flags = decimalCosh(result,
                            __ctfe ? D.PRECISION : DecimalControl.precision,
                            __ctfe ? RoundingMode.implicit: DecimalControl.rounding);
    DecimalControl.raiseFlags(flags);
    return result;
}

//unittest
//{
//    import std.stdio;
//    import std.math;
//    for(int i = 1; i < 10; ++i)
//    {
//        writefln("+%3.2f %35.34f %35.34f", i/10.0, cosh(Decimal128(i)/10), std.math.cosh(i/10.0));
//    }
//}

/**
Returns cosine of xπ.
Throws:
$(BOOKTABLE,
    $(TR $(TD $(MYREF InvalidOperationException))
         $(TD x is signaling $(B NaN) or ±∞))
    $(TR $(TD $(MYREF UnderflowException))
         $(TD result is too small to be represented))
    $(TR $(TD $(MYREF InexactException))
         $(TD the result is inexact))
)
Special_values:
$(BOOKTABLE,
    $(TR $(TH x) $(TH cospi(x)))
    $(TR $(TD $(B NaN)) $(TD $(B NaN)))
    $(TR $(TD ±∞) $(TD $(B NaN)))
    $(TR $(TD ±0.0) $(TD +1.0))
    $(TR $(TD 1/6) $(TD +√3/2))
    $(TR $(TD 1/4) $(TD +√2/2))
    $(TR $(TD 1/3) $(TD +0.5))
    $(TR $(TD 1/2) $(TD +0.0))
    $(TR $(TD 2/3) $(TD -0.5))
    $(TR $(TD 3/4) $(TD -√2/2))
    $(TR $(TD 5/6) $(TD -√3/2))
    $(TR $(TD 1.0) $(TD -1.0))
)
*/
@IEEECompliant("cosPi", 42)
D cospi(D)(const auto ref D x)
if (isDecimal!D)
{
    Unqual!D result = x;
    const flags = decimalCosPi(result,
                             __ctfe ? D.PRECISION : DecimalControl.precision,
                             __ctfe ? RoundingMode.implicit: DecimalControl.rounding);
    DecimalControl.raiseFlags(flags);
    return result;
}

/**
Calculates the arc sine of x, returning a value ranging from -π/2 to +π/2.
Exceptions:
$(BOOKTABLE,
    $(TR $(TD $(MYREF InvalidOperationException))
         $(TD x is signaling $(B NaN) or |x| > 1.0))
    $(TR $(TD $(MYREF InexactException))
         $(TD the result is inexact))
)
Special_values:
$(BOOKTABLE,
    $(TR $(TH x) $(TH asin(x)))
    $(TR $(TD $(B NaN)) $(TD $(B NaN)))
    $(TR $(TD -1.0) $(TD -π/2))
    $(TR $(TD +1.0) $(TD +π/2))
    $(TR $(TD < -1.0) $(TD $(B NaN)))
    $(TR $(TD > +1.0) $(TD $(B NaN)))
)
*/
@IEEECompliant("asin", 43)
D asin(D)(const auto ref D x)
if (isDecimal!D)
{
    enum checkFlags = ExceptionFlags.inexact | ExceptionFlags.invalidOperation;
    Unqual!D result = x;
    const flags = decimalAsin(result,
                              __ctfe ? D.PRECISION : DecimalControl.precision,
                              __ctfe ? RoundingMode.implicit: DecimalControl.rounding);
    DecimalControl.raiseFlags(flags & checkFlags);
    return result;
}

///
unittest
{
    Decimal32 x = 1;
    assert(asin(x) == Decimal32.pi_2);
    assert(asin(-x) == -Decimal32.pi_2);
}

unittest
{
    import std.meta : AliasSeq;

    foreach (T; AliasSeq!(Decimal32, Decimal64, Decimal128))
    {
        assert(asin(-T.one) == -T.pi_2);
        assert(asin(T.zero) == 0);
        assert(asin(T.one) == T.pi_2);
        assert(asin(T.nan).isNaN);
    }
}

/**
Calculates the inverse hyperbolic sine of x
Exceptions:
$(BOOKTABLE,
    $(TR $(TD $(MYREF InvalidOperationException))
         $(TD x is signaling $(B NaN)))
    $(TR $(TD $(MYREF UnderflowException))
         $(TD the result is too small to be represented))
    $(TR $(TD $(MYREF InexactException))
         $(TD the result is inexact))
)
Special_values:
$(BOOKTABLE,
    $(TR $(TH x) $(TH asinh(x)))
    $(TR $(TD $(B NaN)) $(TD $(B NaN)))
    $(TR $(TD ±0.0) $(TD ±0.0))
    $(TR $(TD ±∞) $(TD ±∞))
)
*/
@IEEECompliant("asinh", 43)
D asinh(D)(const auto ref D x)
if (isDecimal!D)
{
    enum checkFlags = ExceptionFlags.inexact | ExceptionFlags.invalidOperation | ExceptionFlags.underflow;
    Unqual!D result = x;
    const flags = decimalAsinh(result,
                             __ctfe ? D.PRECISION : DecimalControl.precision,
                             __ctfe ? RoundingMode.implicit: DecimalControl.rounding);
    DecimalControl.raiseFlags(flags & checkFlags);
    return result;
}

///
unittest
{
    Decimal32 x = 0;
    assert(asinh(x) == 0);
}

unittest
{
    import std.meta : AliasSeq;

    foreach (T; AliasSeq!(Decimal32, Decimal64, Decimal128))
    {
        assert(asinh(T.zero) == T.zero);
        assert(asinh(T.infinity) == T.infinity);
        assert(asinh(T.nan).isNaN);
    }
}

/**
Calculates the arc tangent of x, returning a value ranging from -π/2 to π/2.
Exceptions:
$(BOOKTABLE,
    $(TR $(TD $(MYREF InvalidOperationException))
         $(TD x is signaling $(B NaN)))
    $(TR $(TD $(MYREF InexactException))
         $(TD the result is inexact))
    $(TR $(TD $(MYREF UnderflowException))
         $(TD the result is too small to be represented))
)
Special_values:
$(BOOKTABLE,
    $(TR $(TH x) $(TH atan(x)))
    $(TR $(TD $(B NaN)) $(TD $(B NaN)))
    $(TR $(TD ±0.0) $(TD ±0.0))
    $(TR $(TD ±∞) $(TD ±π/2))
)
*/
@IEEECompliant("atan", 43)
D atan(D)(const auto ref D x)
if (isDecimal!D)
{
    enum checkFlags = ExceptionFlags.invalidOperation | ExceptionFlags.underflow | ExceptionFlags.inexact;
    Unqual!D result = x;
    const flags = decimalAtan(result,
                             __ctfe ? D.PRECISION : DecimalControl.precision,
                             __ctfe ? RoundingMode.implicit: DecimalControl.rounding);
    DecimalControl.raiseFlags(flags & checkFlags);
    return result;
}

///
unittest
{
    Decimal32 radians = 1;
    assert(atan(radians) == Decimal32.pi_4);
}

unittest
{
    import std.meta : AliasSeq;

    foreach (T; AliasSeq!(Decimal32, Decimal64, Decimal128))
    {
        assert(isIdentical(atan(T.zero), T.zero));
        assert(isIdentical(atan(-T.zero), -T.zero));
        assert(isIdentical(atan(T.infinity), T.pi_2));
        assert(isIdentical(atan(-T.infinity), -T.pi_2));
        assert(atan(T.nan).isNaN);
    }
}

/**
Calculates the arc tangent of y / x, returning a value ranging from -π to π.
Exceptions:
$(BOOKTABLE,
    $(TR $(TD $(MYREF InvalidOperationException))
         $(TD x or y is signaling $(B NaN)))
    $(TR $(TD $(MYREF InexactException))
         $(TD the result is inexact))
    $(TR $(TD $(MYREF UnderflowException))
         $(TD the result is too small to be represented))
)
Special_values:
$(BOOKTABLE,
    $(TR $(TH y) $(TH x) $(TH atan2(y, x)))
    $(TR $(TD $(B NaN)) $(TD any) $(TD $(B NaN)))
    $(TR $(TD any) $(TD $(B NaN)) $(TD $(B NaN)))
    $(TR $(TD ±0.0) $(TD -0.0) $(TD ±π))
    $(TR $(TD ±0.0) $(TD +0.0) $(TD ±0.0))
    $(TR $(TD ±0.0) $(TD <0.0) $(TD ±π))
    $(TR $(TD ±0.0) $(TD >0.0) $(TD ±0.0))
    $(TR $(TD ±∞) $(TD -∞) $(TD ±3π/4))
    $(TR $(TD ±∞) $(TD +∞) $(TD ±π/4))
    $(TR $(TD ±∞) $(TD any) $(TD ±π/2))
    $(TR $(TD any) $(TD -∞) $(TD ±π))
    $(TR $(TD any) $(TD +∞) $(TD ±0.0))
)
*/
@IEEECompliant("atan2", 43)
auto atan2(D1, D2)(const auto ref D1 y, const auto ref D2 x)
if (isDecimal!(D1, D2))
{
    enum checkFlags = ExceptionFlags.invalidOperation | ExceptionFlags.underflow | ExceptionFlags.inexact;
    alias D = CommonDecimal!(D1, D2);
    D result;
    const flags = decimalAtan2(y, x, result,
                             __ctfe ? D.PRECISION : DecimalControl.precision,
                             __ctfe ? RoundingMode.implicit: DecimalControl.rounding);
    DecimalControl.raiseFlags(flags & checkFlags);
    return result;
}

///
unittest
{
    Decimal32 y = 10;
    Decimal32 x = 0;
    assert(atan2(y, x) == Decimal32.pi_2);
}

unittest
{
    import std.meta : AliasSeq;

    foreach (T; AliasSeq!(Decimal32, Decimal64, Decimal128))
    {
        assert(atan2(T.nan, T.zero).isNaN);
        assert(atan2(T.one, T.nan).isNaN);
        assert(atan2(T.zero, -T.zero) == T.PI);
        assert(atan2(-T.zero, -T.zero) == -T.PI);
        assert(atan2(T.zero, T.zero) == T.zero);
        assert(atan2(-T.zero, T.zero) == -T.zero);
        assert(atan2(T.zero, -T.one) == T.PI);
        assert(atan2(-T.zero, -T.one) == -T.PI);
        assert(atan2(T.zero, T.one) == T.zero);
        assert(atan2(-T.zero, T.one) == -T.zero);
        assert(atan2(-T.one, T.zero) == -T.pi_2);
        assert(atan2(T.one, T.zero) == T.pi_2);
        assert(atan2(T.one, -T.infinity) == T.PI);
        assert(atan2(-T.one, -T.infinity) == -T.PI);
        assert(atan2(T.one, T.infinity) == T.zero);
        assert(atan2(-T.one, T.infinity) == -T.zero);
        assert(atan2(-T.infinity, T.one) == -T.pi_2);
        assert(atan2(T.infinity, T.one) == T.pi_2);
        assert(atan2(-T.infinity, -T.infinity) == -T.pi3_4);
        assert(atan2(T.infinity, -T.infinity) == T.pi3_4);
        assert(atan2(-T.infinity, T.infinity) == -T.pi_4);
        assert(atan2(T.infinity, T.infinity) == T.pi_4);
    }
}

/**
Calculates the arc tangent of y / x divided by π, returning a value ranging from -1 to 1.
Exceptions:
$(BOOKTABLE,
    $(TR $(TD $(MYREF InvalidOperationException))
         $(TD x or y is signaling $(B NaN)))
    $(TR $(TD $(MYREF InexactException))
         $(TD the result is inexact))
    $(TR $(TD $(MYREF UnderflowException))
         $(TD the result is too small to be represented))
)
Special_values:
$(BOOKTABLE,
    $(TR $(TH y) $(TH x) $(TH atan2pi(y, x)))
    $(TR $(TD $(B NaN)) $(TD any) $(TD $(B NaN)))
    $(TR $(TD any) $(TD $(B NaN)) $(TD $(B NaN)))
    $(TR $(TD ±0.0) $(TD -0.0) $(TD ±1.0))
    $(TR $(TD ±0.0) $(TD +0.0) $(TD ±0.0))
    $(TR $(TD ±0.0) $(TD <0.0) $(TD ±1.0))
    $(TR $(TD ±0.0) $(TD >0.0) $(TD ±0.0))
    $(TR $(TD ±∞) $(TD -∞) $(TD ±3/4))
    $(TR $(TD ±∞) $(TD +∞) $(TD ±1/4))
    $(TR $(TD ±∞) $(TD any) $(TD ±1/2))
    $(TR $(TD any) $(TD -∞) $(TD ±1.0))
    $(TR $(TD any) $(TD +∞) $(TD ±0.0))
)
*/
@IEEECompliant("atan2Pi", 43)
auto atan2pi(D1, D2)(const auto ref D1 y, const auto ref D2 x)
if (isDecimal!(D1, D2))
{
    enum checkFlags = ExceptionFlags.invalidOperation | ExceptionFlags.underflow | ExceptionFlags.inexact;
    alias D = CommonDecimal!(D1, D2);
    D result;
    const flags = decimalAtan2Pi(y, x, result,
                              __ctfe ? D.PRECISION : DecimalControl.precision,
                              __ctfe ? RoundingMode.implicit: DecimalControl.rounding);
    DecimalControl.raiseFlags(flags & checkFlags);
    return result;
}

///
unittest
{
    Decimal32 y = 10;
    Decimal32 x = 0;
    assert(atan2pi(y, x) == Decimal32("0.5"));
}

unittest
{
    import std.meta : AliasSeq;

    foreach (T; AliasSeq!(Decimal32, Decimal64, Decimal128))
    {
        assert(atan2(T.nan, T.zero).isNaN);
        assert(atan2(T.one, T.nan).isNaN);
        assert(atan2pi(T.zero, -T.zero) == T.one);
        assert(atan2pi(-T.zero, -T.zero) == -T.one);
        assert(atan2pi(T.zero, T.zero) == T.zero);
        assert(atan2pi(-T.zero, T.zero) == -T.zero);
        assert(atan2pi(T.zero, -T.one) == T.one);
        assert(atan2pi(-T.zero, -T.one) == -T.one);
        assert(atan2pi(T.zero, T.one) == T.zero);
        assert(atan2pi(-T.zero, T.one) == -T.zero);
        assert(atan2pi(-T.one, T.zero) == -T.half);
        assert(atan2pi(T.one, T.zero) == T.half);
        assert(atan2pi(T.one, -T.infinity) == T.one);
        assert(atan2pi(-T.one, -T.infinity) == -T.one);
        assert(atan2pi(T.one, T.infinity) == T.zero);
        assert(atan2pi(-T.one, T.infinity) == -T.zero);
        assert(atan2pi(-T.infinity, T.one) == -T.half);
        assert(atan2pi(T.infinity, T.one) == T.half);
        assert(atan2pi(-T.infinity, -T.infinity) == -T.threequarters);
        assert(atan2pi(T.infinity, -T.infinity) == T.threequarters);
        assert(atan2pi(-T.infinity, T.infinity) == -T.quarter);
        assert(atan2pi(T.infinity, T.infinity) == T.quarter);
    }
}

/**
Calculates the inverse hyperbolic tangent of x
Exceptions:
$(BOOKTABLE,
    $(TR $(TD $(MYREF InvalidOperationException))
         $(TD x is signaling $(B NaN) or |x| > 1.0))
    $(TR $(TD $(MYREF DivisionByZeroException))
         $(TD |x| = 1.0))
    $(TR $(TD $(MYREF UnderflowException))
         $(TD the result is too small to be represented))
    $(TR $(TD $(MYREF InexactException))
         $(TD the result is inexact))
)
Special_values:
$(BOOKTABLE,
    $(TR $(TH x) $(TH atanh(x)))
    $(TR $(TD $(B NaN)) $(TD $(B NaN)))
    $(TR $(TD ±0.0) $(TD ±0.0))
    $(TR $(TD ±1.0) $(TD ±∞))
    $(TR $(TD >1.0) $(TD $(B NaN)))
    $(TR $(TD <1.0) $(TD $(B NaN)))
)
*/
@IEEECompliant("atanh", 43)
D atanh(D)(const auto ref D x)
if (isDecimal!D)
{
    enum checkFlags = ExceptionFlags.invalidOperation | ExceptionFlags.underflow |
        ExceptionFlags.inexact | ExceptionFlags.divisionByZero;
    Unqual!D result = x;
    const flags = decimalAtanh(result,
                             __ctfe ? D.PRECISION : DecimalControl.precision,
                             __ctfe ? RoundingMode.implicit: DecimalControl.rounding);
    DecimalControl.raiseFlags(flags & checkFlags);
    return result;
}

///
unittest
{
    Decimal32 x = 0;
    assert(atanh(x) == 0);
}

/**
Calculates the arc tangent of x divided by π, returning a value ranging from -1/2 to 1/2.
Exceptions:
$(BOOKTABLE,
    $(TR $(TD $(MYREF InvalidOperationException))
         $(TD x is signaling $(B NaN)))
    $(TR $(TD $(MYREF InexactException))
         $(TD the result is inexact))
    $(TR $(TD $(MYREF UnderflowException))
         $(TD the result is too small to be represented))
)
Special_values:
$(BOOKTABLE,
    $(TR $(TH x) $(TH atan(x)))
    $(TR $(TD $(B NaN)) $(TD $(B NaN)))
    $(TR $(TD ±0.0) $(TD ±0.0))
    $(TR $(TD ±∞) $(TD ±1/2))
)
*/
@IEEECompliant("atanPi", 43)
D atanpi(D)(const auto ref D x)
if (isDecimal!D)
{
    enum checkFlags = ExceptionFlags.invalidOperation | ExceptionFlags.underflow | ExceptionFlags.inexact;
    Unqual!D result = x;
    const flags = decimalAtanPi(result,
                              __ctfe ? D.PRECISION : DecimalControl.precision,
                              __ctfe ? RoundingMode.implicit: DecimalControl.rounding);
    DecimalControl.raiseFlags(flags & checkFlags);
    return result;
}

///
unittest
{
    Decimal32 radians = 1;
    assert(atanpi(radians) == Decimal32("0.25"));
}

unittest
{
    import std.meta : AliasSeq;

    foreach (T; AliasSeq!(Decimal32, Decimal64, Decimal128))
    {
        assert(isIdentical(atanpi(T.zero), T.zero));
        assert(isIdentical(atanpi(-T.zero), -T.zero));
        assert(isIdentical(atanpi(T.infinity), T.half));
        assert(isIdentical(atanpi(-T.infinity), -T.half));
        assert(atanpi(T.nan).isNaN);
    }
}

/**
Computes the cubic root of x
Throws:
$(BOOKTABLE,
    $(TR $(TD $(MYREF InvalidOperationException))
         $(TD x is signaling $(B NaN)))
    $(TR $(TD $(MYREF UnderflowException))
         $(TD cubic root of x is too small to be represented))
    $(TR $(TD $(MYREF InexactException))
         $(TD the result is inexact))
)
Special_values:
$(BOOKTABLE,
    $(TR $(TH x) $(TH cbrt(x)))
    $(TR $(TD $(B NaN)) $(TD $(B NaN)))
    $(TR $(TD ±0.0) $(TD ±0.0))
    $(TR $(TD ±∞) $(TD ±∞))
)
*/
D cbrt(D)(const auto ref D x)
if (isDecimal!D)
{
    Unqual!D result = x;
    const flags = decimalCbrt(result,
                            __ctfe ? D.PRECISION : DecimalControl.precision,
                            __ctfe ? RoundingMode.implicit: DecimalControl.rounding);
    DecimalControl.raiseFlags(flags);
    return result;
}

///
unittest
{
    Decimal32 x = 27;
    assert(cbrt(x) == 3);
}

/**
Returns the value of x rounded upward to the next integer (toward positive infinity).
This operation is silent, doesn't throw any exception.
Special_values:
$(BOOKTABLE,
    $(TR $(TH x) $(TH ceil(x)))
    $(TR $(TD $(B NaN)) $(TD $(B NaN)))
    $(TR $(TD ±0.0) $(TD ±0.0))
    $(TR $(TD ±∞) $(TD ±∞))
)
*/
D ceil(D)(const auto ref D x)
if (isDecimal!D)
{
    Unqual!D result = x;
    decimalRound(result, 0, RoundingMode.towardPositive);
    return result;
}

///
unittest
{
    assert(ceil(Decimal32("123.456")) == 124);
    assert(ceil(Decimal32("-123.456")) == -123);
}

/**
Sums x$(SUBSCRIPT i) * y$(SUBSCRIPT i) using a higher precision, rounding only once at the end.
Returns:
    x$(SUBSCRIPT 0) * y$(SUBSCRIPT 0) + x$(SUBSCRIPT 1) * y$(SUBSCRIPT 1) + ... + x$(SUBSCRIPT n) * y$(SUBSCRIPT n)
Notes:
    If x and y arrays are not of the same length, operation is performed for min(x.length, y.length);
Throws:
$(BOOKTABLE,
    $(TR $(TD $(MYREF InvalidOperationException))
         $(TD any x is signaling $(B NaN)))
    $(TR $(TD $(MYREF InvalidOperationException))
         $(TD any combination of elements is (±∞, ±0.0) or (±0.0, ±∞)))
    $(TR $(TD $(MYREF InvalidOperationException))
         $(TD there are two products resulting in infinities of different sign))
    $(TR $(TD $(MYREF OverflowException))
         $(TD result is too big to be represented))
    $(TR $(TD $(MYREF UnderflowException))
         $(TD result is too small to be represented))
    $(TR $(TD $(MYREF InexactException))
         $(TD result is inexact))
)
*/
@IEEECompliant("dot", 47)
D dot(D)(const(D)[] x, const(D)[] y)
if (isDecimal!D)
{
    enum checkFlags = ExceptionFlags.inexact | ExceptionFlags.invalidOperation
        | ExceptionFlags.overflow | ExceptionFlags.underflow;
    Unqual!D result = x;
    const flags = decimalDot(x, y, result,
                            __ctfe ? D.PRECISION : DecimalControl.precision,
                            __ctfe ? RoundingMode.implicit: DecimalControl.rounding);
    DecimalControl.raiseFlags(flags & checkFlags);
    return result;
}

/**
Calculates e$(SUPERSCRIPT x)
Throws:
$(BOOKTABLE,
    $(TR $(TD $(MYREF InvalidOperationException))
         $(TD x is signaling $(B NaN)))
    $(TR $(TD $(MYREF UnderflowException))
         $(TD e$(SUPERSCRIPT x) is too small to be represented))
    $(TR $(TD $(MYREF OverflowException))
         $(TD e$(SUPERSCRIPT x) is too big to be represented))
    $(TR $(TD $(MYREF InexactException))
         $(TD the result is inexact))
)
Special_values:
$(BOOKTABLE,
    $(TR $(TH x) $(TH exp(x)))
    $(TR $(TD $(B NaN)) $(TD $(B NaN)))
    $(TR $(TD ±0.0) $(TD +1.0))
    $(TR $(TD -∞) $(TD 0))
    $(TR $(TD +∞) $(TD +∞))
)
*/
@IEEECompliant("exp", 42)
D exp(D)(const auto ref D x)
if (isDecimal!D)
{
    enum checkFlags = ExceptionFlags.inexact | ExceptionFlags.invalidOperation
        | ExceptionFlags.overflow | ExceptionFlags.underflow;
    Unqual!D result = x;
    const flags = decimalExp(result,
                            __ctfe ? D.PRECISION : DecimalControl.precision,
                            __ctfe ? RoundingMode.implicit: DecimalControl.rounding);
    DecimalControl.raiseFlags(flags & checkFlags);
    return result;
}

///
unittest
{
    Decimal32 power = 1;
    assert(exp(power) == Decimal32.E);
}

unittest
{
    import std.meta : AliasSeq;

    foreach (T; AliasSeq!(Decimal32, Decimal64, Decimal128))
    {
        assert(exp(T.zero) == T.one);
        assert(exp(-T.infinity) == T.zero);
        assert(exp(T.infinity) == T.infinity);
        assert(exp(T.nan).isNaN);
    }
}

/**
Calculates 10$(SUPERSCRIPT x)
Throws:
$(BOOKTABLE,
    $(TR $(TD $(MYREF InvalidOperationException))
         $(TD x is signaling $(B NaN)))
    $(TR $(TD $(MYREF UnderflowException))
         $(TD 10$(SUPERSCRIPT x) is too small to be represented))
    $(TR $(TD $(MYREF OverflowException))
         $(TD 10$(SUPERSCRIPT x) is too big to be represented))
    $(TR $(TD $(MYREF InexactException))
         $(TD the result is inexact))
)
Special_values:
$(BOOKTABLE,
    $(TR $(TH x) $(TH exp10(x)))
    $(TR $(TD $(B NaN)) $(TD $(B NaN)))
    $(TR $(TD ±0.0) $(TD +1.0))
    $(TR $(TD -∞) $(TD +0.0))
    $(TR $(TD +∞) $(TD +∞))
)
*/
@IEEECompliant("exp10", 42)
D exp10(D)(const auto ref D x)
if (isDecimal!D)
{
    enum checkFlags = ExceptionFlags.inexact | ExceptionFlags.invalidOperation
        | ExceptionFlags.overflow | ExceptionFlags.underflow;
    Unqual!D result = x;
    const flags = decimalExp10(result,
                            __ctfe ? D.PRECISION : DecimalControl.precision,
                            __ctfe ? RoundingMode.implicit: DecimalControl.rounding);
    DecimalControl.raiseFlags(flags & checkFlags);
    return result;
}

///
unittest
{
    Decimal32 x = 3;
    assert(exp10(x) == 1000);
}

/**
Calculates 10$(SUPERSCRIPT x) - 1
Throws:
$(BOOKTABLE,
    $(TR $(TD $(MYREF InvalidOperationException))
         $(TD x is signaling $(B NaN)))
    $(TR $(TD $(MYREF UnderflowException))
         $(TD 10$(SUPERSCRIPT x) - 1 is too small to be represented))
    $(TR $(TD $(MYREF OverflowException))
         $(TD 10$(SUPERSCRIPT x) - 1 is too big to be represented))
    $(TR $(TD $(MYREF InexactException))
         $(TD the result is inexact))
)
Special_values:
$(BOOKTABLE,
    $(TR $(TH x) $(TH exp10m1(x)))
    $(TR $(TD $(B NaN)) $(TD $(B NaN)))
    $(TR $(TD ±0.0) $(TD ±0.0))
    $(TR $(TD -∞) $(TD -1.0))
    $(TR $(TD +∞) $(TD +∞))
)
*/
@IEEECompliant("exp10m1", 42)
D exp10m1(D)(const auto ref D x)
if (isDecimal!D)
{
    enum checkFlags = ExceptionFlags.inexact | ExceptionFlags.invalidOperation
        | ExceptionFlags.overflow | ExceptionFlags.underflow;
    Unqual!D result = x;
    const flags = decimalExp10m1(result,
                              __ctfe ? D.PRECISION : DecimalControl.precision,
                              __ctfe ? RoundingMode.implicit: DecimalControl.rounding);
    DecimalControl.raiseFlags(flags & checkFlags);
    return result;
}

///
unittest
{
    Decimal32 x = 3;
    assert(exp10m1(x) == 999);
}

/**
Calculates 2$(SUPERSCRIPT x)
Throws:
$(BOOKTABLE,
    $(TR $(TD $(MYREF InvalidOperationException))
         $(TD x is signaling $(B NaN)))
    $(TR $(TD $(MYREF UnderflowException))
         $(TD 2$(SUPERSCRIPT x) is too small to be represented))
    $(TR $(TD $(MYREF OverflowException))
         $(TD 2$(SUPERSCRIPT x) is too big to be represented))
    $(TR $(TD $(MYREF InexactException))
         $(TD the result is inexact))
)
Special_values:
$(BOOKTABLE,
    $(TR $(TH x) $(TH exp2(x)))
    $(TR $(TD $(B NaN)) $(TD $(B NaN)))
    $(TR $(TD ±0.0) $(TD +1.0))
    $(TR $(TD -∞) $(TD +0.0))
    $(TR $(TD +∞) $(TD +∞))
)
*/
@IEEECompliant("exp2", 42)
D exp2(D)(const auto ref D x)
if (isDecimal!D)
{
    enum checkFlags = ExceptionFlags.inexact | ExceptionFlags.invalidOperation
        | ExceptionFlags.overflow | ExceptionFlags.underflow;
    Unqual!D result = x;
    const flags = decimalExp2(result,
                              __ctfe ? D.PRECISION : DecimalControl.precision,
                              __ctfe ? RoundingMode.implicit: DecimalControl.rounding);
    DecimalControl.raiseFlags(flags & checkFlags);
    return result;
}

///
unittest
{
    Decimal32 x = 3;
    assert(exp2(x) == 8);
}

/**
Calculates 2$(SUPERSCRIPT x) - 1
Throws:
$(BOOKTABLE,
    $(TR $(TD $(MYREF InvalidOperationException))
         $(TD x is signaling $(B NaN)))
    $(TR $(TD $(MYREF UnderflowException))
         $(TD 2$(SUPERSCRIPT x) - 1 is too small to be represented))
    $(TR $(TD $(MYREF OverflowException))
         $(TD 2$(SUPERSCRIPT x) - 1 is too big to be represented))
    $(TR $(TD $(MYREF InexactException))
         $(TD the result is inexact))
)
Special_values:
$(BOOKTABLE,
    $(TR $(TH x) $(TH exp2m1(x)))
    $(TR $(TD $(B NaN)) $(TD $(B NaN)))
    $(TR $(TD ±0.0) $(TD ±0.0))
    $(TR $(TD -∞) $(TD -1.0))
    $(TR $(TD +∞) $(TD +∞))
)
*/
@IEEECompliant("exp2m1", 42)
D exp2m1(D)(const auto ref D x)
if (isDecimal!D)
{
    enum checkFlags = ExceptionFlags.inexact | ExceptionFlags.invalidOperation
        | ExceptionFlags.overflow | ExceptionFlags.underflow;
    Unqual!D result = x;
    const flags = decimalExp2m1(result,
                             __ctfe ? D.PRECISION : DecimalControl.precision,
                             __ctfe ? RoundingMode.implicit: DecimalControl.rounding);
    DecimalControl.raiseFlags(flags & checkFlags);
    return result;
}

///
unittest
{
    Decimal32 x = 3;
    assert(exp2m1(x) == 7);
}

/**
Calculates e$(SUPERSCRIPT x) - 1
Throws:
$(BOOKTABLE,
    $(TR $(TD $(MYREF InvalidOperationException))
         $(TD x is signaling $(B NaN)))
    $(TR $(TD $(MYREF UnderflowException))
         $(TD e$(SUPERSCRIPT x) - 1 is too small to be represented))
    $(TR $(TD $(MYREF OverflowException))
         $(TD e$(SUPERSCRIPT x) - 1 is too big to be represented))
    $(TR $(TD $(MYREF InexactException))
         $(TD the result is inexact))
)
Special_values:
$(BOOKTABLE,
    $(TR $(TH x) $(TH expm1(x)))
    $(TR $(TD $(B NaN)) $(TD $(B NaN)))
    $(TR $(TD ±0.0) $(TD ±0.0))
    $(TR $(TD -∞) $(TD -1.0))
    $(TR $(TD +∞) $(TD +∞))
)
*/
@IEEECompliant("expm1", 42)
D expm1(D)(const auto ref D x)
if (isDecimal!D)
{
    enum checkFlags = ExceptionFlags.inexact | ExceptionFlags.invalidOperation
        | ExceptionFlags.overflow | ExceptionFlags.underflow;
    Unqual!D result = x;
    const flags = decimalExpm1(result,
                               __ctfe ? D.PRECISION : DecimalControl.precision,
                               __ctfe ? RoundingMode.implicit: DecimalControl.rounding);
    DecimalControl.raiseFlags(flags & checkFlags);
    return result;
}

/**
Calculates |x|.
This operation is silent, no error flags are set and no exceptions are thrown.
*/
@IEEECompliant("abs", 23)
D fabs(D)(const auto ref D x) @nogc nothrow pure @safe
if (isDecimal!D)
{
    Unqual!D result = x;
    static if (is(D: Decimal128))
        result.data.hi &= ~D.MASK_SGN.hi;
    else
        result.data &= ~D.MASK_SGN;
    return result;
}

///
unittest
{
    assert(fabs(-Decimal32.max) == Decimal32.max);
    assert(fabs(Decimal64.infinity) == Decimal64.infinity);
}

/**
Returns the positive difference between x and y. If x ≤ y, retuns 0.0
Throws:
$(BOOKTABLE,
    $(TR $(TD $(MYREF InvalidOperationException))
         $(TD either x or y is $(B signaling NaN)))
    $(TR $(TD $(MYREF UnderflowException))
         $(TD result is subnormal))
    $(TR $(TD $(MYREF InexactException))
         $(TD result is inexact))
)
Special_values:
$(BOOKTABLE,
    $(TR $(TH x) $(TH y) $(TH fdim(x, y)))
    $(TR $(TD $(B NaN)) $(TD any) $(TD $(B NaN)))
    $(TR $(TD any) $(TD $(B NaN)) $(TD $(B NaN)))
    $(TR $(TD x > y) $(TD) $(TD x - y))
    $(TR $(TD x ≤ y) $(TD) $(TD 0.0))
)
*/
auto fdim(D1, D2)(const auto ref D1 x, const auto ref D2 y)
{
    alias D = CommonDecimal!(D1, D2);
    D result = x;

    if (x.isInfinity != 0 && y.isInfinity != 0)
    {
        if (signbit(x) == signbit(y))
            return D.zero;
        else
            return result;
    }

    if (decimalCmp(y, x) >= 0)
        return D.zero;

    const flags = decimalSub(result, y,
                       __ctfe ? 0 : DecimalControl.precision,
                       __ctfe ? RoundingMode.implicit : DecimalControl.rounding);
    if (!result.isNaN && signbit(result))
        result = D.zero;
    DecimalControl.raiseFlags(flags);
    return result;
}

///
unittest
{
    Decimal32 x = "10.4";
    Decimal32 y = "7.3";

    assert(fdim(x, y) == Decimal32("3.1"));
    assert(fdim(y, x) == 0);
}

/**
Returns the value of x rounded downward to the previous integer (toward negative infinity).
This operation is silent, doesn't throw any exception.
Special_values:
$(BOOKTABLE,
    $(TR $(TH x) $(TH floor(x)))
    $(TR $(TD $(B NaN)) $(TD $(B NaN)))
    $(TR $(TD ±0.0) $(TD ±0.0))
    $(TR $(TD ±∞) $(TD ±∞))
)
*/
D floor(D)(const auto ref D x)
if (isDecimal!D)
{
    Unqual!D result = x;
    decimalRound(result, 0, RoundingMode.towardNegative);
    return result;
}

///
unittest
{
    assert(floor(Decimal32("123.456")) == 123);
    assert(floor(Decimal32("-123.456")) == -124);
}

/**
Returns (x * y) + z, rounding only once according to the current precision and rounding mode
Throws:
$(BOOKTABLE,
    $(TR $(TD $(MYREF InvalidOperationException))
         $(TD x, y or z is signaling $(B NaN)))
    $(TR $(TD $(MYREF InvalidOperationException))
         $(TD (x, y) = (±∞, ±0.0) or (±0.0, ±∞)))
    $(TR $(TD $(MYREF InvalidOperationException))
         $(TD x or y is infinite, z is infinite but has opposing sign))
    $(TR $(TD $(MYREF UnderflowException))
         $(TD result is too small to be represented))
    $(TR $(TD $(MYREF OverflowException))
         $(TD result is too big to be represented))
    $(TR $(TD $(MYREF InexactException))
         $(TD the result is inexact))
)
Special_values:
$(BOOKTABLE,
    $(TR $(TH x) $(TH y) $(TH z) $(TH fma(x, y, z)))
    $(TR $(TD $(B NaN)) $(TD any) $(TD any) $(TD $(B NaN)))
    $(TR $(TD any) $(TD $(B NaN)) $(TD any) $(TD $(B NaN)))
    $(TR $(TD any) $(TD any) $(TD $(B NaN)) $(TD $(B NaN)))
    $(TR $(TD ±∞) $(TD ±0.0) $(TD any) $(TD $(B NaN)))
    $(TR $(TD ±0.0) $(TD ±∞) $(TD any) $(TD $(B NaN)))
    $(TR $(TD +∞) $(TD >0.0) $(TD -∞) $(TD $(B NaN)))
    $(TR $(TD -∞) $(TD <0.0) $(TD -∞) $(TD $(B NaN)))
    $(TR $(TD -∞) $(TD <0.0) $(TD -∞) $(TD $(B NaN)))
    $(TR $(TD +∞) $(TD >0.0) $(TD -∞) $(TD $(B NaN)))
    $(TR $(TD -∞) $(TD >0.0) $(TD +∞) $(TD $(B NaN)))
    $(TR $(TD +∞) $(TD <0.0) $(TD +∞) $(TD $(B NaN)))
    $(TR $(TD +∞) $(TD <0.0) $(TD +∞) $(TD $(B NaN)))
    $(TR $(TD -∞) $(TD >0.0) $(TD +∞) $(TD $(B NaN)))
    $(TR $(TD >0.0) $(TD +∞) $(TD -∞) $(TD $(B NaN)))
    $(TR $(TD <0.0) $(TD -∞) $(TD -∞) $(TD $(B NaN)))
    $(TR $(TD <0.0) $(TD -∞) $(TD -∞) $(TD $(B NaN)))
    $(TR $(TD >0.0) $(TD +∞) $(TD -∞) $(TD $(B NaN)))
    $(TR $(TD >0.0) $(TD -∞) $(TD +∞) $(TD $(B NaN)))
    $(TR $(TD <0.0) $(TD +∞) $(TD +∞) $(TD $(B NaN)))
    $(TR $(TD <0.0) $(TD +∞) $(TD +∞) $(TD $(B NaN)))
    $(TR $(TD >0.0) $(TD -∞) $(TD +∞) $(TD $(B NaN)))
    $(TR $(TD +∞) $(TD >0.0) $(TD +∞) $(TD +∞))
    $(TR $(TD -∞) $(TD <0.0) $(TD +∞) $(TD +∞))
    $(TR $(TD +∞) $(TD <0.0) $(TD -∞) $(TD -∞))
    $(TR $(TD -∞) $(TD >0.0) $(TD -∞) $(TD -∞))
    $(TR $(TD >0.0) $(TD +∞) $(TD +∞) $(TD +∞))
    $(TR $(TD <0.0) $(TD -∞) $(TD +∞) $(TD +∞))
    $(TR $(TD <0.0) $(TD +∞) $(TD -∞) $(TD -∞))
    $(TR $(TD >0.0) $(TD -∞) $(TD -∞) $(TD -∞))
    $(TR $(TD +∞) $(TD >0.0) $(TD any) $(TD +∞))
    $(TR $(TD -∞) $(TD <0.0) $(TD any) $(TD +∞))
    $(TR $(TD +∞) $(TD <0.0) $(TD any) $(TD -∞))
    $(TR $(TD -∞) $(TD >0.0) $(TD any) $(TD -∞))
    $(TR $(TD >0.0) $(TD +∞) $(TD any) $(TD +∞))
    $(TR $(TD <0.0) $(TD -∞) $(TD any) $(TD +∞))
    $(TR $(TD <0.0) $(TD +∞) $(TD any) $(TD -∞))
    $(TR $(TD >0.0) $(TD -∞) $(TD any) $(TD -∞))
)
*/
@IEEECompliant("fusedMultiplyAdd", 4)
auto fma(D1, D2, D3)(const auto ref D1 x, const auto ref D2 y, const auto ref D3 z)
if (isDecimal!(D1, D2, D3))
{
    alias D = CommonDecimal!(D1, D2, D3);
    D result;
    const flags = decimalFMA!(D1, D2, D3)(x, y, z, result,
                        __ctfe ? D.PRECISION : DecimalControl.precision,
                        __ctfe ? RoundingMode.implicit : DecimalControl.rounding);
    DecimalControl.raiseFlags(flags);
    return result;
}

///
unittest
{
    Decimal32 x = 2;
    Decimal64 y = 3;
    Decimal128 z = 5;
    assert(fma(x, y, z) == 11);
}

/**
Returns the larger _decimal value between x and y
Throws:
    $(MYREF InvalidOperationException) if x or y is signaling $(B NaN)
Special_values:
$(BOOKTABLE,
    $(TR $(TH x) $(TH y) $(TH fmax(x, y)))
    $(TR $(TD $(B NaN)) $(TD any) $(TD y))
    $(TR $(TD any) $(TD $(B NaN)) $(TD x))
)
*/
@IEEECompliant("maxNum", 19)
auto fmax(D1, D2)(const auto ref D1 x, const auto ref D2 y)
if (isDecimal!(D1, D2))
{
    CommonDecimal!(D1, D2) result;
    const flags = decimalMax(x, y, result);
    DecimalControl.raiseFlags(flags);
    return result;
}

///
unittest
{
    Decimal32 x = 3;
    Decimal64 y = -4;
    assert(fmax(x, y) == 3);
}

/**
Returns the larger _decimal value between absolutes of x and y
Throws:
    $(MYREF InvalidOperationException) if x or y is signaling $(B NaN)
Special_values:
$(BOOKTABLE,
    $(TR $(TH x) $(TH y) $(TH fmaxAbs(x, y)))
    $(TR $(TD $(B NaN)) $(TD any) $(TD y))
    $(TR $(TD any) $(TD $(B NaN)) $(TD x))
)
*/
@IEEECompliant("maxNumMag", 19)
auto fmaxAbs(D1, D2)(const auto ref D1 x, const auto ref D2 y)
if (isDecimal!(D1, D2))
{
    CommonDecimal!(D1, D2) result;
    const flags = decimalMaxAbs(x, y, result);
    DecimalControl.raiseFlags(flags & ExceptionFlags.invalidOperation);
    return result;
}

///
unittest
{
    Decimal32 x = 3;
    Decimal64 y = -4;
    assert(fmaxAbs(x, y) == -4);
}

/**
Returns the smaller _decimal value between x and y
Throws:
    $(MYREF InvalidOperationException) if x or y is signaling $(B NaN)
Special_values:
$(BOOKTABLE,
    $(TR $(TH x) $(TH y) $(TH fmin(x, y)))
    $(TR $(TD $(B NaN)) $(TD any) $(TD y))
    $(TR $(TD any) $(TD $(B NaN)) $(TD x))
)
*/
@IEEECompliant("minNum", 19)
auto fmin(D1, D2)(const auto ref D1 x, const auto ref D2 y)
if (isDecimal!(D1, D2))
{
    CommonDecimal!(D1, D2) result;
    const flags = decimalMin(x, y, result);
    DecimalControl.raiseFlags(flags & ExceptionFlags.invalidOperation);
    return result;
}

///
unittest
{
    Decimal32 x = 3;
    Decimal64 y = -4;
    assert(fmin(x, y) == -4);
}

/**
Returns the smaller _decimal value between absolutes of x and y
Throws:
    $(MYREF InvalidOperationException) if x or y is signaling $(B NaN)
Special_values:
$(BOOKTABLE,
    $(TR $(TH x) $(TH y) $(TH fminAbs(x, y)))
    $(TR $(TD $(B NaN)) $(TD any) $(TD y))
    $(TR $(TD any) $(TD $(B NaN)) $(TD x))
)
*/
@IEEECompliant("minNumMag", 19)
auto fminAbs(D1, D2)(const auto ref D1 x, const auto ref D2 y)
if (isDecimal!(D1, D2))
{
    CommonDecimal!(D1, D2) result;
    const flags = decimalMinAbs(x, y, result);
    DecimalControl.raiseFlags(flags & ExceptionFlags.invalidOperation);
    return result;
}

///
unittest
{
    Decimal32 x = 3;
    Decimal64 y = -4;
    assert(fminAbs(x, y) == 3);
}

/**
Calculates the remainder of the division x / y
Params:
    x = dividend
    y = divisor
Returns:
    The value of x - n * y, where n is the quotient rounded toward zero of the division x / y
Throws:
$(BOOKTABLE,
    $(TR $(TD $(MYREF InvalidOperationException))
         $(TD x or y is signaling $(B NaN), x = ±∞, y = ±0.0))
    $(TR $(TD $(MYREF UnderflowException))
         $(TD result is too small to be represented))
    $(TR $(TD $(MYREF DivisionByZeroException))
         $(TD y = 0.0))
    $(TR $(TD $(MYREF InexactException))
         $(TD the result is inexact))
)
Special_values:
$(BOOKTABLE,
    $(TR $(TH x) $(TH y) $(TH fmod(x, y)))
    $(TR $(TD $(B NaN)) $(TD any) $(TD $(B NaN)))
    $(TR $(TD any) $(TD $(B NaN)) $(TD $(B NaN)))
    $(TR $(TD ±∞) $(TD any) $(TD $(B NaN)))
    $(TR $(TD any) $(TD 0.0) $(TD $(B NaN)))
    $(TR $(TD any) $(TD ±∞) $(TD $(B NaN)))
)
*/
auto fmod(D1, D2)(const auto ref D1 x, const auto ref D2 y)
{
    alias D = CommonDecimal!(D1, D2);
    D result = x;
    const flags = decimalMod(result, y,
                            __ctfe ? D.PRECISION : DecimalControl.precision,
                            RoundingMode.towardZero);
    DecimalControl.raiseFlags(flags & ~ExceptionFlags.underflow);
    return result;
}

///
unittest
{
    Decimal32 x = "18.5";
    Decimal32 y = "4.2";
    assert(fmod(x, y) == Decimal32("1.7"));
}

/**
Separates _decimal _value into coefficient and exponent.
This operation is silent, doesn't throw any exception.
Returns:
    a result such as x = result * 10$(SUPERSCRIPT y) and |result| < 1.0
Special_values:
$(BOOKTABLE,
    $(TR $(TH x) $(TH y) $(TH frexp(x, y)))
    $(TR $(TD $(B NaN)) $(TD 0) $(TD $(B NaN)))
    $(TR $(TD +∞) $(TD 0) $(TD +∞))
    $(TR $(TD -∞) $(TD 0) $(TD -∞))
    $(TR $(TD ±0.0) $(TD 0) $(TD ±0.0))
)
Notes:
    This operation is silent, doesn't throw any exceptions and doesn't set any error flags.
    Signaling NaNs are quieted by this operation

*/
D frexp(D)(const auto ref D x, out int y)
{
    DataType!(D.sizeof) cx; int ex; bool sx;
    Unqual!D result;
    final switch (fastDecode(x, cx, ex, sx))
    {
        case FastClass.signalingNaN:
            result.invalidPack(sx, cx);
            return result;
        case FastClass.quietNaN:
            y = 0;
            return x;
        case FastClass.infinite:
            y = 0;
            return x;
        case FastClass.zero:
            y = 0;
            return sx ? -D.zero : D.zero;
        case FastClass.finite:
            auto targetPower = -prec(cx);
            y = ex - targetPower;
            result.adjustedPack(cx, targetPower, sx, 0, RoundingMode.implicit);
            return result;
    }
}

/**
Extracts the current payload from a $(B NaN) value
Note:
    These functions do not check if x is truly a $(B NaN) value
    before extracting the payload. Using them on finite values will extract a part of the coefficient
*/
pragma(inline, true)
uint getNaNPayload(const(Decimal32) x) @nogc nothrow pure @safe
{
    return x.data & Decimal32.MASK_PAYL;
}

///ditto
pragma(inline, true)
ulong getNaNPayload(const(Decimal64) x) @nogc nothrow pure @safe
{
    return x.data & Decimal64.MASK_PAYL;
}

///ditto
@nogc nothrow pure @safe
ulong getNaNPayload(const(Decimal128) x, out ulong payloadHi)
{
    auto payload = x.data & Decimal128.MASK_PAYL;
    payloadHi = payload.hi;
    return payload.lo;
}

///
unittest
{
    Decimal32 x = Decimal32("nan(123)");
    Decimal64 y = Decimal64("nan(456)");
    Decimal128 z = Decimal128("nan(789)");

    assert(getNaNPayload(x) == 123);
    assert(getNaNPayload(y) == 456);
    ulong hi;
    assert(getNaNPayload(z, hi) == 789 && hi == 0);

}

/**
Calculates the length of the hypotenuse of a right-angled triangle with sides
of length x and y. The hypotenuse is the value of the square root of the sums
of the squares of x and y.
Throws:
$(BOOKTABLE,
    $(TR $(TD $(MYREF InvalidOperationException))
         $(TD x, y is signaling $(B NaN)))
    $(TR $(TD $(MYREF OverflowException))
         $(TD result is too big to be represented))
    $(TR $(TD $(MYREF InexactException))
         $(TD the result is inexact))
)
Special_values:
$(BOOKTABLE,
    $(TR $(TH x) $(TH y) $(TH hypot(x, y)))
    $(TR $(TD ±∞) $(TD any) $(TD +∞))
    $(TR $(TD any) $(TD ±∞) $(TD +∞))
    $(TR $(TD $(B NaN)) $(TD $(B NaN)) $(TD nan))
    $(TR $(TD $(B NaN)) $(TD any) $(TD nan))
    $(TR $(TD any) $(TD $(B NaN)) $(TD nan))
    $(TR $(TD 0.0) $(TD any) $(TD y))
    $(TR $(TD any) $(TD 0.0) $(TD x))
)
*/
@IEEECompliant("hypot", 42)
auto hypot(D1, D2)(const auto ref D1 x, const auto ref D2 y)
if (isDecimal!(D1, D2))
{
    alias D = CommonDecimal!(D1, D2);
    D result;
    const flags = decimalHypot(x, y, result,
                              __ctfe ? D.PRECISION : DecimalControl.precision,
                              __ctfe ? RoundingMode.implicit : DecimalControl.rounding);
    DecimalControl.raiseFlags(flags);
    return result;
}

///
unittest
{
    Decimal32 x = 3;
    Decimal32 y = 4;
    assert(hypot(x, y) == 5);
}

/**
Returns the 10-exponent of x as a signed integral value..
Throws:
    $(MYREF InvalidOperationException) if x is $(B NaN), infinity or 0
Special_values:
$(BOOKTABLE,
    $(TR $(TH x) $(TH ilogb(x)))
    $(TR $(TD $(B NaN)) $(TD int.min))
    $(TR $(TD ±∞) $(TD int min + 1))
    $(TR $(TD ±0.0) $(TD int.min + 2))
    $(TR $(TD ±1.0) $(TD 0))
)
*/
@IEEECompliant("logB", 17)
int ilogb(D)(const auto ref D x)
if (isDecimal!D)
{
    int result;
    const flags = decimalLog(x, result);
    DecimalControl.raiseFlags(flags);
    return result;
}

///
unittest
{
    assert(ilogb(Decimal32(1234)) == 3);
}

/**
Determines if x is canonical.
This operation is silent, no error flags are set and no exceptions are thrown.
Params:
x = a _decimal value
Returns:
    true if x is canonical, false otherwise
Notes:
    A _decimal value is considered canonical:<br/>
    - if the value is $(B NaN), the payload must be less than 10 $(SUPERSCRIPT precision - 1);<br/>
    - if the value is infinity, no trailing bits are accepted;<br/>
    - if the value is finite, the coefficient must be less than 10 $(SUPERSCRIPT precision).
*/
@IEEECompliant("isCanonical", 25)
bool isCanonical(D)(const auto ref D x)
if (isDecimal!D)
{
    static if (is(D: Decimal32) || is(D: Decimal64))
    {
        if ((x.data & D.MASK_QNAN) == D.MASK_QNAN)
            return (x.data & D.MASK_PAYL) <= D.PAYL_MAX && (x.data & ~(D.MASK_SNAN | D.MASK_SGN | D.MASK_PAYL)) == 0U;
        if ((x.data & D.MASK_INF) == D.MASK_INF)
            return (x.data & ~(D.MASK_INF | D.MASK_SGN)) == 0U;
        if ((x.data & D.MASK_EXT) == D.MASK_EXT)
            return ((x.data & D.MASK_COE2) | D.MASK_COEX) <= D.COEF_MAX;
        else
            return ((x.data & D.MASK_COE1) <= D.COEF_MAX);
    }
    else
    {
        if ((x.data.hi & D.MASK_QNAN.hi) == D.MASK_QNAN.hi)
            return (x.data & D.MASK_PAYL) <= D.PAYL_MAX && (x.data & ~(D.MASK_SNAN | D.MASK_SGN | D.MASK_PAYL)) == 0U;
        if ((x.data.hi & D.MASK_INF.hi) == D.MASK_INF.hi)
            return (x.data.hi & ~(D.MASK_INF.hi | D.MASK_SGN.hi)) == 0U && x.data.lo == 0U;
        if ((x.data.hi & D.MASK_EXT.hi) == D.MASK_EXT.hi)
            return false;
        else
            return ((x.data & D.MASK_COE1) <= D.COEF_MAX);
    }
}

///
unittest
{
    assert(isCanonical(Decimal32.max));
    assert(isCanonical(Decimal64.max));
    assert(!isCanonical(Decimal32("nan(0x3fffff)")));

}

unittest
{
    import std.meta : AliasSeq;

    foreach (T; AliasSeq!(Decimal32, Decimal64, Decimal128))
    {
        assert(isCanonical(T.zero));
        assert(isCanonical(T.max));
        assert(isCanonical(T.nan));
        assert(isCanonical(T.sNaN));
        assert(isCanonical(T.infinity));
    }
}

///isFinite
unittest // isFinite
{
    assert(Decimal32.max.isFinite);
    assert(!Decimal64.nan.isFinite);
    assert(!Decimal128.infinity.isFinite);
}

unittest // isFinite
{
    import std.meta : AliasSeq;

    foreach (T; AliasSeq!(Decimal32, Decimal64, Decimal128))
    {
        assert(T.max.isFinite);
        assert(!T.infinity.isFinite);
        assert(!T.sNaN.isFinite);
        assert(!T.qNaN.isFinite);
    }
}

/**
Checks if two _decimal values are identical
Params:
    x = a _decimal value
    y = a _decimal value
Returns:
    true if x has the same internal representation as y
Notes:
    Even if two _decimal values are equal, their internal representation can be different:<br/>
    - $(B NaN) values must have the same sign and the same payload to be considered identical;
      $(B NaN)(12) is not identical to $(B NaN)(13)<br/>
    - Zero values must have the same sign and the same exponent to be considered identical;
      0 * 10$(SUPERSCRIPT 3) is not identical to 0 * 10$(SUPERSCRIPT 5)<br/>
    - Finite _values must be represented based on same exponent to be considered identical;
      123 * 10$(SUPERSCRIPT -3) is not identical to 1.23 * 10$(SUPERSCRIPT -1)
*/
bool isIdentical(D)(const auto ref D x, const auto ref D y)
if (isDecimal!D)
{
    return x.data == y.data;
}

///
unittest
{
    assert(isIdentical(Decimal32.min_normal, Decimal32.min_normal));
    assert(!isIdentical(Decimal64("nan"), Decimal64("nan<200>")));
}

unittest // isInfinity
{
    import std.meta : AliasSeq;

    foreach (T; AliasSeq!(Decimal32, Decimal64, Decimal128))
    {
        assert(T.infinity.isInfinity);
        assert(T.negInfinity.isInfinity);
        assert((-T.infinity).isInfinity);
        assert(!T.ten.isInfinity);
        assert(!T.nan.isInfinity);
        assert(!T.sNaN.isInfinity);
        assert(!T.qNaN.isInfinity);
    }
}

///isNaN
unittest // isNaN
{
    import std.meta : AliasSeq;

    foreach (T; AliasSeq!(Decimal32, Decimal64, Decimal128))
    {
        assert(T.nan.isNaN);
        assert(T.sNaN.isNaN);
        assert(T.qNaN.isNaN);
        assert(!T.ten.isNaN);
        assert(!T.max.isNaN);
        assert(!T.min_normal.isSignalNaN);
    }
}

///isNeg
unittest // isNeg
{
    import std.meta : AliasSeq;

    foreach (T; AliasSeq!(Decimal32, Decimal64, Decimal128))
    {
        assert(T(-1).isNeg);
        assert(T(-3).isNeg);

        assert(!T(0).isNeg);
        assert(!T(1).isNeg);
        assert(!T(3).isNeg);
    }
}

///isZero
unittest // isZero
{
    import std.meta : AliasSeq;

    foreach (T; AliasSeq!(Decimal32, Decimal64, Decimal128))
    {
        assert(T(0).isZero);
        assert(T(0.0).isZero);

        assert(!T(-1).isZero);
        assert(!T(-3).isZero);
        assert(!T(1).isZero);
        assert(!T(3).isZero);
    }
}

/**
Determines if x is normalized.
This operation is silent, no error flags are set and no exceptions are thrown.
Params:
    x = a _decimal value
Returns:
    true if x is normal, false otherwise ($(B NaN), infinity, zero, subnormal)
*/
@IEEECompliant("isNormal", 25)
bool isNormal(D)(const auto ref D x)
if (isDecimal!D)
{
    DataType!(D.sizeof) coefficient;
    uint exponent;

    static if (is(D: Decimal32) || is(D: Decimal64))
    {
        if ((x.data & D.MASK_INF) == D.MASK_INF)
            return false;
        if ((x.data & D.MASK_EXT) == D.MASK_EXT)
        {
            coefficient = (x.data & D.MASK_COE2) | D.MASK_COEX;
            if (coefficient > D.COEF_MAX)
                return false;
            exponent = cast(uint)((x.data & D.MASK_EXP2) >>> D.SHIFT_EXP2);
        }
        else
        {
            coefficient = x.data & D.MASK_COE1;
            if (coefficient == 0U)
                return false;
            exponent = cast(uint)((x.data & D.MASK_EXP1) >>> D.SHIFT_EXP1);
        }
    }
    else
    {
        if ((x.data.hi & D.MASK_INF.hi) == D.MASK_INF.hi)
            return false;
        if ((x.data.hi & D.MASK_EXT.hi) == D.MASK_EXT.hi)
            return false;
        coefficient = x.data & D.MASK_COE1;
        if (coefficient == 0U || coefficient > D.COEF_MAX)
            return false;
        exponent = cast(uint)((x.data.hi & D.MASK_EXP1.hi) >>> (D.SHIFT_EXP1 - 64));
    }

    if (exponent < D.PRECISION - 1)
        return prec(coefficient) >= D.PRECISION - exponent;

    return true;
}

///
unittest
{
    assert(isNormal(Decimal32.max));
    assert(!isNormal(Decimal64.nan));
    assert(!isNormal(Decimal32("0x1p-101")));
}

unittest
{
    import std.meta : AliasSeq;

    foreach (T; AliasSeq!(Decimal32, Decimal64, Decimal128))
    {
        assert(!isNormal(T.zero));
        assert(isNormal(T.ten));
        assert(!isNormal(T.nan));
        assert(isNormal(T.min_normal));
        assert(!isNormal(T.subn));
    }
}

/**
Checks whether a _decimal value is a power of ten. This operation is silent,
no exception flags are set and no exceptions are thrown.
Params:
    x = any _decimal value
Returns:
    true if x is power of ten, false otherwise ($(B NaN), infinity, 0, negative)
*/
bool isPowerOf10(D)(const auto ref D x)
if (isDecimal!D)
{
    if (x.isNaN || x.isInfinity || x.isZero || signbit(x) != 0U)
        return false;

    alias U = DataType!(D.sizeof);
    U c = void;
    int e = void;
    x.unpack(c, e);
    coefficientShrink(c, e);
    return c == 1U;
}

///
unittest
{
    assert(isPowerOf10(Decimal32("1000")));
    assert(isPowerOf10(Decimal32("0.001")));
}

unittest // isSignalingNaN
{
    import std.meta : AliasSeq;

    foreach (T; AliasSeq!(Decimal32, Decimal64, Decimal128))
    {
        //assert(T().isSignalNaN); // Default value
        assert(!T.nan.isSignalNaN);
        assert(T.sNaN.isSignalNaN);
        assert(!T.qNaN.isSignalNaN);
        assert(!T.ten.isSignalNaN);
        assert(!T.max.isSignalNaN);
        assert(!T.min_normal.isSignalNaN);
    }
}

/**
Determines if x is subnormal (denormalized).
This operation is silent, no error flags are set and no exceptions are thrown.
Params:
    x = a _decimal value
Returns:
    true if x is subnormal, false otherwise ($(B NaN), infinity, zero, normal)
*/
@IEEECompliant("isSubnormal", 25)
bool isSubnormal(D)(const auto ref D x)
if (isDecimal!D)
{
    DataType!(D.sizeof) coefficient;
    uint exponent;

    static if (is(D: Decimal32) || is(D: Decimal64))
    {
        if ((x.data & D.MASK_INF) == D.MASK_INF)
            return false;
        if ((x.data & D.MASK_EXT) == D.MASK_EXT)
        {
            coefficient = (x.data & D.MASK_COE2) | D.MASK_COEX;
            if (coefficient > D.COEF_MAX)
                return false;
            exponent = cast(uint)((x.data & D.MASK_EXP2) >>> D.SHIFT_EXP2);
        }
        else
        {
            coefficient = x.data & D.MASK_COE1;
            if (coefficient == 0U)
                return false;
            exponent = cast(uint)((x.data & D.MASK_EXP1) >>> D.SHIFT_EXP1);
        }
    }
    else
    {
        if ((x.data.hi & D.MASK_INF.hi) == D.MASK_INF.hi)
            return false;
        if ((x.data.hi & D.MASK_EXT.hi) == D.MASK_EXT.hi)
            return false;
        coefficient = x.data & D.MASK_COE1;
        if (coefficient == 0U || coefficient > D.COEF_MAX)
            return false;
        exponent = cast(uint)((x.data.hi & D.MASK_EXP1.hi) >>> (D.SHIFT_EXP1 - 64));
    }

    if (exponent < D.PRECISION - 1)
        return prec(coefficient) < D.PRECISION - exponent;

    return false;
}

///
unittest
{
    assert(isSubnormal(Decimal32("0x1p-101")));
    assert(!isSubnormal(Decimal32.max));
    assert(!isSubnormal(Decimal64.nan));

}

unittest
{
    import std.meta : AliasSeq;

    foreach (T; AliasSeq!(Decimal32, Decimal64, Decimal128))
    {
        assert(!isSubnormal(T.zero));
        assert(!isSubnormal(T.ten));
        assert(!isSubnormal(T.nan));
        assert(!isSubnormal(T.min_normal));
        assert(isSubnormal(T.subn));
        assert(isSubnormal(-T.subn));
    }
}

///isZero
unittest // isZero
{
    assert(Decimal32(0).isZero);
    assert(!Decimal64.nan.isZero);
    assert(Decimal32("0x9FFFFFp+10").isZero);
}

unittest // isZero
{
    import std.meta : AliasSeq;

    foreach (T; AliasSeq!(Decimal32, Decimal64, Decimal128))
    {
        assert(T.zero.isZero);
        assert(T.negZero.isZero);
        assert(!T.ten.isZero);
        assert(T.buildin(T.MASK_COE2 | T.MASK_COEX, T.MASK_EXT, T.MASK_NONE).isZero);
    }
}

/**
Efficiently calculates 2 * 10$(SUPERSCRIPT n).
$(BOOKTABLE,
    $(TR $(TD $(MYREF InvalidOperationException))
         $(TD x is $(B signaling NaN)))
    $(TR $(TD $(MYREF UnderflowException))
         $(TD result is subnormal or too small to be represented)
    $(TR $(TD $(MYREF OverflowException))
         $(TD result is too big to be represented)
    $(TR $(TD $(MYREF InexactException))
         $(TD result is inexact)
)
Special_values:
$(BOOKTABLE,
    $(TR $(TH x) $(TH n) $(TH ldexp(x, n)))
    $(TR $(TD $(B NaN)) $(TD any) $(TD $(B NaN)))
    $(TR $(TD ±∞) $(TD any) $(TD ±∞))
    $(TR $(TD ±0) $(TD any) $(TD ±0))
    $(TR $(TD any) $(TD 0) $(TD x))
)
*/
D ldexp(D)(const auto ref D x, const(int) n)
if (isDecimal!D)
{
    Unqual!D result = x;
    const flags = decimalMulPow2(result, n,
                                __ctfe ? D.PRECISION : DecimalControl.precision,
                                __ctfe ? RoundingMode.implicit: DecimalControl.rounding);
    DecimalControl.raiseFlags(flags);
    return result;
}

///
unittest
{
    Decimal32 d = "1.0";
    assert(ldexp(d, 3) == 8);
}

/**
Calculates the natural logarithm of log$(SUBSCRIPT e)x.
Throws:
$(BOOKTABLE,
    $(TR $(TD $(MYREF InvalidOperationException))
         $(TD x is signaling $(B NaN) or x < 0))
    $(TR $(TD $(MYREF DivisionByZero))
         $(TD x is ±0.0))
    $(TR $(TD $(MYREF Underflow))
         $(TD result is too small to be represented))
    $(TR $(TD $(MYREF InexactException))
         $(TD the result is inexact))
)
Special_values:
$(BOOKTABLE,
    $(TR $(TH x) $(TH log(x)))
    $(TR $(TD $(B NaN)) $(TD $(B NaN)))
    $(TR $(TD ±0.0) $(TD -∞))
    $(TR $(TD -∞) $(TD $(B NaN)))
    $(TR $(TD +∞) $(TD +∞))
    $(TR $(TD e) $(TD +1.0))
    $(TR $(TD < 0.0) $(TD $(B NaN)))
)
*/
@IEEECompliant("log", 42)
D log(D)(const auto ref D x)
if (isDecimal!D)
{
    enum checkFlags = ExceptionFlags.inexact | ExceptionFlags.invalidOperation | ExceptionFlags.divisionByZero;
    Unqual!D result = x;
    const flags = decimalLog(result,
                             __ctfe ? D.PRECISION : DecimalControl.precision,
                             __ctfe ? RoundingMode.implicit: DecimalControl.rounding);
    DecimalControl.raiseFlags(flags & checkFlags);
    return result;
}

///
unittest
{
    assert(log(Decimal32.E) == 1);
}

/**
Calculates log$(SUBSCRIPT 10)x.
Throws:
$(BOOKTABLE,
    $(TR $(TD $(MYREF InvalidOperationException))
         $(TD x is signaling $(B NaN) or x < 0.0))
    $(TR $(TD $(MYREF DivisionByZero))
         $(TD x is ±0.0))
    $(TR $(TD $(MYREF Underflow))
         $(TD result is too small to be represented))
    $(TR $(TD $(MYREF InexactException))
         $(TD the result is inexact))
)
Special_values:
$(BOOKTABLE,
    $(TR $(TH x) $(TH log(x)))
    $(TR $(TD $(B NaN)) $(TD $(B NaN)))
    $(TR $(TD ±0.0) $(TD -∞))
    $(TR $(TD -∞) $(TD $(B NaN)))
    $(TR $(TD +∞) $(TD +∞))
    $(TR $(TD +10.0) $(TD +1.0))
    $(TR $(TD < 0.0) $(TD $(B NaN)))
)
*/
@IEEECompliant("log10", 42)
D log10(D)(const auto ref D x)
if (isDecimal!D)
{
    enum checkFlags = ExceptionFlags.inexact | ExceptionFlags.invalidOperation | ExceptionFlags.divisionByZero;
    Unqual!D result = x;
    const flags = decimalLog10(result,
                            __ctfe ? D.PRECISION : DecimalControl.precision,
                            __ctfe ? RoundingMode.implicit: DecimalControl.rounding);
    DecimalControl.raiseFlags(flags & checkFlags);
    return result;
}

/**
Calculates log$(SUBSCRIPT 10)(x + 1).
Throws:
$(BOOKTABLE,
    $(TR $(TD $(MYREF InvalidOperationException))
         $(TD x is signaling $(B NaN) or x < 1.0))
    $(TR $(TD $(MYREF DivisionByZero))
         $(TD x is -1.0))
    $(TR $(TD $(MYREF Underflow))
         $(TD result is too small to be represented))
    $(TR $(TD $(MYREF InexactException))
         $(TD the result is inexact))
)
Special_values:
$(BOOKTABLE,
    $(TR $(TH x) $(TH log(x)))
    $(TR $(TD $(B NaN)) $(TD $(B NaN)))
    $(TR $(TD -1.0) $(TD -∞))
    $(TR $(TD -∞) $(TD $(B NaN)))
    $(TR $(TD +∞) $(TD +∞))
    $(TR $(TD +9.0) $(TD +1.0))
    $(TR $(TD < -1.0) $(TD $(B NaN)))
)
*/
@IEEECompliant("log10p1", 42)
D log10p1(D)(const auto ref D x)
if (isDecimal!D)
{
    enum checkFlags = ExceptionFlags.inexact | ExceptionFlags.invalidOperation | ExceptionFlags.divisionByZero;
    Unqual!D result = x;
    const flags = decimalLog10p1(result,
                              __ctfe ? D.PRECISION : DecimalControl.precision,
                              __ctfe ? RoundingMode.implicit: DecimalControl.rounding);
    DecimalControl.raiseFlags(flags & checkFlags);
    return result;
}

/**
Calculates log$(SUBSCRIPT 2)x.
Throws:
$(BOOKTABLE,
    $(TR $(TD $(MYREF InvalidOperationException))
         $(TD x is signaling $(B NaN) or x < 0))
    $(TR $(TD $(MYREF DivisionByZero))
         $(TD x is ±0.0))
    $(TR $(TD $(MYREF Underflow))
         $(TD result is too small to be represented))
    $(TR $(TD $(MYREF InexactException))
         $(TD the result is inexact))
)
Special_values:
$(BOOKTABLE,
    $(TR $(TH x) $(TH log(x)))
    $(TR $(TD $(B NaN)) $(TD $(B NaN)))
    $(TR $(TD ±0.0) $(TD -∞))
    $(TR $(TD -∞) $(TD $(B NaN)))
    $(TR $(TD +∞) $(TD +∞))
    $(TR $(TD +2.0) $(TD +1.0))
    $(TR $(TD < 0.0) $(TD $(B NaN)))
)
*/
@IEEECompliant("log2", 42)
D log2(D)(const auto ref D x)
if (isDecimal!D)
{
    enum checkFlags = ExceptionFlags.inexact | ExceptionFlags.invalidOperation | ExceptionFlags.divisionByZero;
    Unqual!D result = x;
    const flags = decimalLog2(result,
                              __ctfe ? D.PRECISION : DecimalControl.precision,
                              __ctfe ? RoundingMode.implicit: DecimalControl.rounding);
    DecimalControl.raiseFlags(flags & checkFlags);
    return result;
}

/**
Calculates log$(SUBSCRIPT 2)(x + 1).
Throws:
$(BOOKTABLE,
    $(TR $(TD $(MYREF InvalidOperationException))
         $(TD x is signaling $(B NaN) or x < 0))
    $(TR $(TD $(MYREF DivisionByZero))
         $(TD x is -1.0))
    $(TR $(TD $(MYREF Underflow))
         $(TD result is too small to be represented))
    $(TR $(TD $(MYREF InexactException))
         $(TD the result is inexact))
)
Special_values:
$(BOOKTABLE,
    $(TR $(TH x) $(TH log(x)))
    $(TR $(TD $(B NaN)) $(TD $(B NaN)))
    $(TR $(TD ±0.0) $(TD -∞))
    $(TR $(TD -∞) $(TD $(B NaN)))
    $(TR $(TD +∞) $(TD +∞))
    $(TR $(TD +1.0) $(TD +1.0))
    $(TR $(TD < -1.0) $(TD $(B NaN)))
)
*/
@IEEECompliant("log2p1", 42)
D log2p1(D)(const auto ref D x)
if (isDecimal!D)
{
    enum checkFlags = ExceptionFlags.inexact | ExceptionFlags.invalidOperation | ExceptionFlags.divisionByZero;
    Unqual!D result = x;
    const flags = decimalLog2p1(result,
                             __ctfe ? D.PRECISION : DecimalControl.precision,
                             __ctfe ? RoundingMode.implicit: DecimalControl.rounding);
    DecimalControl.raiseFlags(flags & checkFlags);
    return result;
}

/**
Calculates log$(SUBSCRIPT e)(x + 1).
Throws:
$(BOOKTABLE,
    $(TR $(TD $(MYREF InvalidOperationException))
         $(TD x is signaling $(B NaN) or x < 0))
    $(TR $(TD $(MYREF DivisionByZero))
         $(TD x is -1.0))
    $(TR $(TD $(MYREF Underflow))
         $(TD result is too small to be represented))
    $(TR $(TD $(MYREF InexactException))
         $(TD the result is inexact))
)
Special_values:
$(BOOKTABLE,
    $(TR $(TH x) $(TH log(x)))
    $(TR $(TD $(B NaN)) $(TD $(B NaN)))
    $(TR $(TD ±0.0) $(TD -∞))
    $(TR $(TD -∞) $(TD $(B NaN)))
    $(TR $(TD +∞) $(TD +∞))
    $(TR $(TD e - 1) $(TD +1.0))
    $(TR $(TD < -1.0) $(TD $(B NaN)))
)
*/
@IEEECompliant("logp1", 42)
D logp1(D)(const auto ref D x)
if (isDecimal!D)
{
    enum checkFlags = ExceptionFlags.inexact | ExceptionFlags.invalidOperation | ExceptionFlags.divisionByZero;
    Unqual!D result = x;
    const flags = decimalLogp1(result,
                               __ctfe ? D.PRECISION : DecimalControl.precision,
                               __ctfe ? RoundingMode.implicit: DecimalControl.rounding);
    DecimalControl.raiseFlags(flags & checkFlags);
    return result;
}

/**
Returns the value of x rounded using the specified rounding _mode.
If no rounding _mode is specified the default context rounding _mode is used instead.
Throws:
$(BOOKTABLE,
    $(TR $(TD $(MYREF InvalidOperationException))
         $(TD x is $(B NaN) or ±∞))
   $(TR $(TD $(MYREF OverflowException))
         $(TD result is too big to be represented))
    $(TR $(TD $(MYREF InexactException))
         $(TD the result is inexact))
)
Special_values:
$(BOOKTABLE,
    $(TR $(TH x) $(TH lrint(x)))
    $(TR $(TD $(B NaN)) $(TD 0))
    $(TR $(TD -∞) $(TD long.min))
    $(TR $(TD +∞) $(TD long.max))
)
*/
long lrint(D)(const auto ref D x, const(RoundingMode) mode)
if (isDecimal!D)
{
    enum checkFlags = ExceptionFlags.invalidOperation | ExceptionFlags.inexact;
    long result;
    const flags = decimalToSigned(x, result, mode);
    DecimalControl.raiseFlags(flags & checkFlags);
    return result;
}

///ditto
long lrint(D)(const auto ref D x)
if (isDecimal!D)
{
    return lrint(x, __ctfe ? RoundingMode.implicit : DecimalControl.rounding);
}

/**
Returns the value of x rounded away from zero.
Throws:
    $(BOOKTABLE,
    $(TR $(TD $(MYREF InvalidOperationException))
         $(TD x is $(B NaN) or ±∞))
    $(TR $(TD $(MYREF OverflowException))
         $(TD result is too big to be represented))
)
Special_values:
$(BOOKTABLE,
    $(TR $(TH x) $(TH lround(x)))
    $(TR $(TD $(B NaN)) $(TD 0))
    $(TR $(TD -∞) $(TD long.min))
    $(TR $(TD +∞) $(TD long.max))
)
*/
long lround(D)(const auto ref D x)
{
    long result;
    const flags = decimalToSigned(x, result, RoundingMode.tiesToAway);
    DecimalControl.raiseFlags(flags & ExceptionFlags.invalidOperation);
    //todo: intel does not set ovf, is that correct?
    return result;
}

/**
Splits x in integral and fractional part.
Params:
    x = value to split
    y = value of x truncated toward zero
Returns:
    Fractional part of x.
Throws:
$(BOOKTABLE,
    $(TR $(TD $(MYREF InvalidOperationException))
         $(TD x is $(B signaling NaN)))
Special_values:
$(BOOKTABLE,
    $(TR $(TH x) $(TH modf(x)) $(TH y))
    $(TR $(TD $(B NaN)) $(TD $(B NaN)) $(TD $(B NaN)))
    $(TR $(TD 0.0) $(TD 0.0) $(TD 0.0))
    $(TR $(TD ±∞) $(TD 0.0) $(TD ±∞))
)
*/
D modf(D)(const auto ref D x, ref D y)
if (isDecimal!D)
{
    if (x.isSignalNaN)
    {
        y = copysign(D.nan, x);
        DecimalControl.raiseFlags(ExceptionFlags.invalidOperation);
        return y;
    }
    else if (x.isNaN)
    {
        y = copysign(D.nan, x);
        return y;
    }
    else if (x.isZero)
    {
        y = copysign(D.zero, x);
        return y;
    }
    else if (x.isInfinity)
    {
        y = x;
        return copysign(D.zero, x);
    }
    else
    {
        Unqual!D fractional = x;
        y = x;
        decimalRound(y, 0, RoundingMode.towardZero);
        decimalSub(fractional, y, 0, RoundingMode.tiesToAway);
        return copysign(fractional, x);
    }
}

/**
Creates a quiet $(B NaN) value using the specified payload
Notes:
   Payloads are masked to fit the current representation, having a limited bit width of to $(B mant_dig) - 2;
*/
D NaN(D, T)(const T payload)
if (isDecimal!D && isUnsigned!T)
{
    D result = void;
    result.data = D.MASK_QNAN | (cast(DataType!(D.sizeof))payload & D.MASK_PAYL);
    return result;
}

///ditto
Decimal128 NaN(T)(const(T) payloadHi, const(T) payloadLo)
if (isUnsigned!T)
{
    Decimal128 result = void;
    result.data = Decimal128.MASK_QNAN | (uint128(payloadHi, payloadLo) & Decimal128.MASK_PAYL);
    return result;
}

///
unittest
{
    auto a = NaN!Decimal32(12345U);
    auto b = NaN!Decimal64(12345UL);
    Decimal128 c = NaN(123U, 456U);
}

/**
Returns the value of x rounded using the specified rounding _mode.
If no rounding _mode is specified the default context rounding _mode is used instead.
Throws:
    $(MYREF InvalidOperationException) if x is signaling $(B NaN)
Special_values:
$(BOOKTABLE,
    $(TR $(TH x) $(TH nearbyint(x)))
    $(TR $(TD $(B NaN)) $(TD $(B NaN)))
    $(TR $(TD ±∞) $(TD ±∞))
    $(TR $(TD ±0.0) $(TD ±0.0))
)
*/
@IEEECompliant("roundToIntegralTiesToAway", 19)
@IEEECompliant("roundToIntegralTiesToEven", 19)
@IEEECompliant("roundToIntegralTowardNegative", 19)
@IEEECompliant("roundToIntegralTowardPositive", 19)
@IEEECompliant("roundToIntegralTowardZero", 19)
D nearbyint(D)(const auto ref D x, const(RoundingMode) mode)
if (isDecimal!D)
{
    Unqual!D result = x;
    const flags = decimalRound(result, __ctfe ? D.PRECISION : DecimalControl.precision, mode);
    DecimalControl.raiseFlags(flags & ExceptionFlags.invalidOperation);
    return result;
}

///ditto
D nearbyint(D)(const auto ref D x)
if (isDecimal!D)
{
    return nearbyint(x, __ctfe ? RoundingMode.implicit : DecimalControl.rounding);
}

///
unittest
{
    assert(nearbyint(Decimal32("1.2"), RoundingMode.tiesToEven) == 1);
    assert(nearbyint(Decimal64("2.7"), RoundingMode.tiesToAway) == 3);
    assert(nearbyint(Decimal128("-7.9"), RoundingMode.towardZero) == -7);
    assert(nearbyint(Decimal128("6.66")) == 7);
}

/**
Returns the previous _decimal value before x.
Throws:
    $(MYREF InvalidOperationException) if x is signaling $(B NaN)
Special_values:
$(BOOKTABLE,
    $(TR $(TH x) $(TH nextDown(x)))
    $(TR $(TD $(B NaN)) $(TD $(B NaN)))
    $(TR $(TD -∞) $(TD -∞))
    $(TR $(TD -max) $(TD -∞))
    $(TR $(TD ±0.0) $(TD -min_normal * epsilon))
    $(TR $(TD +∞) $(TD D.max))
)
*/
@IEEECompliant("nextDown", 19)
D nextDown(D)(const auto ref D x)
if (isDecimal!D)
{
    Unqual!D result = x;
    const flags = decimalNextDown(result);
    DecimalControl.raiseFlags(flags & ExceptionFlags.invalidOperation);
    return result;
}

/**
Gives the next power of 10 after x.
Throws:
$(BOOKTABLE,
    $(TR $(TD $(MYREF InvalidOperationException))
         $(TD x is signaling $(B NaN)))
    $(TR $(TD $(MYREF OverflowException))
         $(TD result is too big to be represented))
)
Special_values:
$(BOOKTABLE,
    $(TR $(TH x) $(TH nextPow10(x)))
    $(TR $(TD $(B NaN)) $(TD $(B NaN)))
    $(TR $(TD ±∞) $(TD ±∞))
    $(TR $(TD ±0.0) $(TD +1.0))
)
*/
D nextPow10(D)(const auto ref D x)
if (isDecimal!D)
{
    Unqual!D result;
    ExceptionFlags flags;

    if (x.isSignalNaN)
    {
        result = D.nan;
        flags = ExceptionFlags.invalidOperation;
    }
    else if (x.isNaN || x.isInfinity)
        result = x;
    else if (x.isZero)
        result = D.one;
    else
    {
        alias U = DataType!(D.sizeof);
        U c = void;
        int e = void;
        const bool s = x.unpack(c, e);
        for (size_t i = 0; i < pow10!U.length; ++i)
        {
            if (c == pow10!U[i])
            {
                ++e;
                break;
            }
            else if (c < pow10!U[i])
            {
                c = pow10!U[i];
                break;
            }
        }
        if (i == pow10!U.length)
        {
            c = pow10!U[$ - 1];
            ++e;
        }

        flags = result.adjustedPack(c, e, s, RoundingMode.towardZero, ExceptionFlags.none);
    }

    DecimalControl.raiseFlags(flags);
    return result;
}

/**
Returns the next value after or before x, toward y.
Throws:
    $(BOOKTABLE,
    $(TR $(TD $(MYREF InvalidOperationException))
         $(TD either x or y is $(B signaling NaN)))
    $(TR $(TD $(MYREF OverflowException))
         $(TD result is ±∞))
    $(TR $(TD $(MYREF UnderflowException))
         $(TD result is subnormal or ±0.0))
    $(TR $(TD $(MYREF InexactException))
         $(TD result is ±∞, subnormal or ±0.0))
)
Special_values:
$(BOOKTABLE,
    $(TR $(TH x) $(TH y) $(TH nextAfter(x, y)))
    $(TR $(TD $(B NaN)) $(TD any) $(TD $(B NaN)) )
    $(TR $(TD any) $(TD $(B NaN)) $(TD $(B NaN)) )
    $(TR $(TD x = y)  $(TD) $(TD x) )
    $(TR $(TD x < y)  $(TD) $(TD $(MYREF nextUp)(x)) )
    $(TR $(TD x > y)  $(TD) $(TD $(MYREF nextDown)(x)) )
)
*/
D1 nextAfter(D1, D2)(const auto ref D1 x, const auto ref D2 y)
if (isDecimal!(D1, D2))
{
    if (x.isSignalNaN)
    {
        DecimalControl.raiseFlags(ExceptionFlags.invalidOperation);
        return copysign(D1.nan, x);
    }

    if (y.isSignalNaN)
    {
        DecimalControl.raiseFlags(ExceptionFlags.invalidOperation);
        return copysign(D1.nan, y);
    }

    if (x.isNaN)
        return copysign(D1.nan, x);

    if (y.isNaN)
        return copysign(D1.nan, y);

    Unqual!D1 result = x;
    ExceptionFlags flags;
    int c = decimalCmp(x, y);
    if (c == 0)
    {
        decimalToDecimal(y, result, 0, __ctfe ? RoundingMode.implicit : DecimalControl.rounding);
        DecimalControl.raiseFlags(flags);
        return result;
    }
    else
    {
        flags = c < 0 ? decimalNextUp(result) : decimalNextDown(result);
        flags &= ~ExceptionFlags.inexact;
    }
    if (result.isInfinity)
        flags |= ExceptionFlags.overflow | ExceptionFlags.inexact;
    else if (result.isZero || isSubnormal(result))
        flags |= ExceptionFlags.underflow | ExceptionFlags.inexact;
    DecimalControl.raiseFlags(flags);
    return result;
}

///ditto
alias nextToward = nextAfter;

/**
Returns the next representable _decimal value after x.
Throws:
    $(MYREF InvalidOperationException) if x is signaling $(B NaN)
Special_values:
$(BOOKTABLE,
    $(TR $(TH x) $(TH nextUp(x)))
    $(TR $(TD $(B NaN)) $(TD $(B NaN)))
    $(TR $(TD -∞) $(TD -D.max))
    $(TR $(TD ±0.0) $(TD D.min_normal * epsilon))
    $(TR $(TD D.max) $(TD +∞))
    $(TR $(TD +∞) $(TD +∞))
)
*/
@IEEECompliant("nextUp", 19)
D nextUp(D)(const auto ref D x)
if (isDecimal!D)
{
    Unqual!D result = x;
    const flags = decimalNextUp(result);
    DecimalControl.raiseFlags(flags & ExceptionFlags.invalidOperation);
    return result;
}

/**
Calculates a$(SUBSCRIPT 0) + a$(SUBSCRIPT 1)x + a$(SUBSCRIPT 2)x$(SUPERSCRIPT 2) + .. + a$(SUBSCRIPT n)x$(SUPERSCRIPT n)
Throws:
    $(BOOKTABLE,
    $(TR $(TD $(MYREF InvalidOperationException))
         $(TD x is signaling $(B NaN) or any a$(SUBSCRIPT i) is signaling $(B NaN)))
    $(TR $(TD $(MYREF InvalidOperationException))
         $(TD x is ±∞ and any a$(SUBSCRIPT i) is ±0.0))
    $(TR $(TD $(MYREF InvalidOperationException))
         $(TD x is ±0.0 and any a$(SUBSCRIPT i) is ±∞))
    $(TR $(TD $(MYREF OverflowException))
         $(TD result is too big to be represented))
    $(TR $(TD $(MYREF UnderflowException))
         $(TD result is too small to be represented))
    $(TR $(TD $(MYREF InexactException))
         $(TD result is inexact))
)
*/
auto poly(D1, D2)(const auto ref D1 x, const(D2)[] a)
if (isDecimal!(D1, D2))
{
    alias D = CommonDecimal!(D1, D2);
    D result;
    const flags = decimalPoly(x, a, result,
                            __ctfe ? D.PRECISION : DecimalControl.precision,
                            __ctfe ? RoundingMode.implicit : DecimalControl.rounding);
    DecimalControl.raiseFlags(flags);
    return result;
}

/**
Compute the value of x$(SUPERSCRIPT n), where n is integral
Throws:
    $(BOOKTABLE,
    $(TR $(TD $(MYREF InvalidOperationException))
         $(TD x is signaling $(B NaN)))
    $(TR $(TD $(MYREF DivisionByZeroException))
         $(TD x = ±0.0 and n < 0))
    $(TR $(TD $(MYREF OverflowException))
         $(TD result is too big to be represented))
    $(TR $(TD $(MYREF UnderflowException))
         $(TD result is too small to be represented))
    $(TR $(TD $(MYREF InexactException))
         $(TD result is inexact))
)
Special_values:
$(BOOKTABLE,
    $(TR $(TH x) $(TH n) $(TH pow(x, n)) )
    $(TR $(TD sNaN) $(TD any) $(TD $(B NaN)) )
    $(TR $(TD any) $(TD 0) $(TD +1.0) )
    $(TR $(TD $(B NaN)) $(TD any) $(TD $(B NaN)))
    $(TR $(TD ±∞) $(TD any) $(TD ±∞) )
    $(TR $(TD ±0.0) $(TD odd n < 0) $(TD ±∞))
    $(TR $(TD ±0.0) $(TD even n < 0) $(TD +∞) )
    $(TR $(TD ±0.0) $(TD odd n > 0) $(TD ±0.0)  )
    $(TR $(TD ±0.0) $(TD even n > 0) $(TD +0.0) )
)
*/
@IEEECompliant("pown", 42)
D pow(D, T)(const auto ref D x, const(T) n)
if (isDecimal!D && isIntegral!T)
{
    Unqual!D result = x;
    const flags = decimalPow(result, n,
                           __ctfe ? D.PRECISION : DecimalControl.precision,
                           __ctfe ? RoundingMode.implicit : DecimalControl.rounding);
    DecimalControl.raiseFlags(flags);
    return result;
}

/**
Compute the value of x$(SUPERSCRIPT y)
Throws:
    $(BOOKTABLE,
    $(TR $(TD $(MYREF InvalidOperationException))
         $(TD x is signaling $(B NaN)))
    $(TR $(TD $(MYREF DivisionByZeroException))
         $(TD x = ±0.0 and y < 0.0))
    $(TR $(TD $(MYREF OverflowException))
         $(TD result is too big to be represented))
    $(TR $(TD $(MYREF UnderflowException))
         $(TD result is too small to be represented))
    $(TR $(TD $(MYREF InexactException))
         $(TD result is inexact))
)
Special_values:
$(BOOKTABLE,
    $(TR $(TH x) $(TH y) $(TH pow(x, y)) )
    $(TR $(TD sNaN) $(TD any) $(TD $(B NaN)) )
    $(TR $(TD any) $(TD 0) $(TD +1.0) )
    $(TR $(TD $(B NaN)) $(TD any) $(TD $(B NaN)))
    $(TR $(TD ±∞) $(TD any) $(TD ±∞) )
    $(TR $(TD ±0.0) $(TD odd n < 0) $(TD ±∞))
    $(TR $(TD ±0.0) $(TD even n < 0) $(TD +∞) )
    $(TR $(TD ±0.0) $(TD odd n > 0) $(TD ±0.0)  )
    $(TR $(TD ±0.0) $(TD even n > 0) $(TD +0.0) )
)
*/
@IEEECompliant("pow", 42)
@IEEECompliant("powr", 42)
auto pow(D1, D2)(const auto ref D1 x, const auto ref D2 x)
{
    Unqual!D1 result = x;
    const flags = decimalPow(result, y,
                            __ctfe ? D.PRECISION : DecimalControl.precision,
                            __ctfe ? RoundingMode.implicit : DecimalControl.rounding);
    DecimalControl.raiseFlags(flags);
    return result;
}

/**
Express a value using another value exponent
Params:
    x = source value
    y = value used as exponent source
Returns:
    a value with the same numerical value as x but with the exponent of y
Throws:
    $(BOOKTABLE,
    $(TR $(TD $(MYREF InvalidOperationException))
         $(TD x is signaling $(B NaN)))
    $(TR $(TD $(MYREF InvalidOperationException))
         $(TD only one of x or y is ±∞))
    $(TR $(TD $(MYREF InexactException))
         $(TD result is inexact))
)
Special_values:
$(BOOKTABLE,
    $(TR $(TH x) $(TH y) $(TH quantize(x, y)))
    $(TR $(TD $(B NaN)) $(TD any) $(TD $(B NaN)))
    $(TR $(TD any) $(TD $(B NaN)) $(TD $(B NaN)))
    $(TR $(TD ±∞) $(TD ±∞) $(TD ±∞))
    $(TR $(TD ±∞) $(TD any) $(TD $(B NaN)))
    $(TR $(TD any) $(TD ±∞) $(TD $(B NaN)))
)
*/
@IEEECompliant("quantize", 18)
D1 quantize(D1, D2)(const auto ref D1 x, const auto ref D2 y)
if (isDecimal!(D1, D2))
{
    enum checkFlags = ExceptionFlags.invalidOperation | ExceptionFlags.inexact;
    D1 result = x;
    const flags = decimalQuantize(result, y,
                                 __ctfe ? D1.PRECISION : DecimalControl.precision,
                                 __ctfe ? RoundingMode.implicit : DecimalControl.rounding);
    DecimalControl.raiseFlags(flags & checkFlags);
    return result;
}

/**
Returns the exponent encoded into the specified _decimal value;
Throws:
    $(BOOKTABLE,
    $(TR $(TD $(MYREF InvalidOperationException))
         $(TD x is $(B NaN) or ±∞))
)
Special_values:
$(BOOKTABLE,
    $(TR $(TH x) $(TH quantexp(x)))
    $(TR $(TD $(B NaN)) $(TD int.min) )
    $(TR $(TD ±∞) $(TD int.min) )
)
Notes:
Unlike $(MYREF frexp) where the exponent is calculated for a |coefficient| < 1.0, this
functions returns the raw encoded exponent.
*/
int quantexp(D)(const auto ref D x)
if (isDecimal!D)
{
    DataType!(D.sizeof) cx; int ex; bool sx;
    switch (fastDecode(x, cx, ex, sx))
    {
        case FastClass.finite:
        case FastClass.zero:
            return ex;
        default:
            DecimalControl.raiseFlags(ExceptionFlags.invalidOperation);
            return int.min;
    }
}

///
unittest
{
    auto d = Decimal32("0x0001p+12"); //1 * 10^^12
    auto z = Decimal64("0x0000p-3");  //0 * 10^^-3

    int calculatedExponent, rawExponent;

    //d is 0.1 * 10^^13
    frexp(d, calculatedExponent);
    rawExponent = quantexp(d);
    assert(calculatedExponent == 13  && rawExponent == 12);

    //z is 0.0
    frexp(z, calculatedExponent);
    rawExponent = quantexp(z);
    assert(calculatedExponent == 0  && rawExponent == -3);
}

/**
Calculates the _remainder of the division x / y
Params:
    x = dividend
    y = divisor
Returns:
    The value of x - n * y, where n is the quotient rounded to nearest even of the division x / y
Throws:
$(BOOKTABLE,
    $(TR $(TD $(MYREF InvalidOperationException))
         $(TD x or y is signaling $(B NaN), x = ±∞, y = ±0.0))
    $(TR $(TD $(MYREF UnderflowException))
         $(TD result is too small to be represented))
    $(TR $(TD $(MYREF DivisionByZeroException))
         $(TD y = 0.0))
    $(TR $(TD $(MYREF InexactException))
         $(TD the result is inexact))
)
Special_values:
$(BOOKTABLE,
    $(TR $(TH x) $(TH y) $(TH remainder(x, y)))
    $(TR $(TD $(B NaN)) $(TD any) $(TD $(B NaN)))
    $(TR $(TD any) $(TD $(B NaN)) $(TD $(B NaN)))
    $(TR $(TD ±∞) $(TD any) $(TD $(B NaN)))
    $(TR $(TD any) $(TD 0.0) $(TD $(B NaN)))
    $(TR $(TD any) $(TD ±∞) $(TD $(B NaN)))
)
*/
@IEEECompliant("remainder", 25)
auto remainder(D1, D2)(const auto ref D1 x, const auto ref D2 y)
{
    CommonDecimal!(D1, D2) result = x;
    const flags = decimalMod(result, y,
                            __ctfe ? D1.PRECISION : DecimalControl.precision,
                            RoundingMode.tiesToEven);
    DecimalControl.raiseFlags(flags);
    return result;
}

/**
Returns the value of x rounded using the specified rounding _mode.
If no rounding _mode is specified the default context rounding _mode is used instead.
This function is similar to $(MYREF nearbyint), but if the rounded value is not exact it will throw
$(MYREF InexactException)
Throws:
    $(BOOKTABLE,
    $(TR $(TD $(MYREF InvalidOperationException))
         $(TD x is signaling $(B NaN)))
    $(TR $(TD $(MYREF InexactException))
         $(TD the result is inexact))
)
Special_values:
$(BOOKTABLE,
    $(TR $(TH x) $(TH rint(x)))
    $(TR $(TD $(B NaN)) $(TD $(B NaN)))
    $(TR $(TD ±∞) $(TD ±∞))
    $(TR $(TD ±0.0) $(TD ±0.0))
)
*/
@IEEECompliant("roundToIntegralExact", 25)
D rint(D)(const auto ref D x, const(RoundingMode) mode)
if (isDecimal!D)
{
    enum checkFlags = ExceptionFlags.invalidOperation | ExceptionFlags.inexact;
    Unqual!D result = x;
    const flags = decimalRound(result, __ctfe ? D.PRECISION : DecimalControl.precision, mode);
    DecimalControl.raiseFlags(flags & checkFlags);
    return result;
}

///ditto
@IEEECompliant("roundToIntegralExact", 25)
D rint(D)(const auto ref D x)
if (isDecimal!D)
{
    return rint(x, __ctfe ? RoundingMode.implicit : DecimalControl.rounding);
}

///
unittest
{
    DecimalControl.resetFlags(ExceptionFlags.inexact);
    assert(rint(Decimal32("9.9")) == 10);
    assert(DecimalControl.inexact);

    DecimalControl.resetFlags(ExceptionFlags.inexact);
    assert(rint(Decimal32("9.0")) == 9);
    assert(!DecimalControl.inexact);
}

/**
Returns the value of x rounded using the specified rounding _mode.
If no rounding _mode is specified the default context rounding _mode is used instead.
If the value doesn't fit in a long data type $(MYREF OverflowException) is thrown.
Throws:
$(BOOKTABLE,
    $(TR $(TD $(MYREF InvalidOperationException))
         $(TD x is $(B NaN)))
    $(TR $(TD $(MYREF OverflowException))
         $(TD result does not fit in a long data type))
    $(TR $(TD $(MYREF InexactException))
         $(TD the result is inexact))
)
Special_values:
$(BOOKTABLE,
    $(TR $(TH x) $(TH rndtonl(x)))
    $(TR $(TD $(B NaN)) $(TD $(B NaN)))
    $(TR $(TD ±∞) $(TD ±∞))
    $(TR $(TD ±0.0) $(TD ±0.0))
)
*/
D rndtonl(D)(const auto ref D x, const(RoundingMode) mode)
if (isDecimal!D)
{
    Unqual!D result = x;
    ExceptionFlags flags;
    long l;
    if (x.isNaN)
    {
        flags = ExceptionFlags.invalidOperation;
        result = signbit(x) ? -D.nan : D.nan;
    }
    else if (x.isInfinity)
        flags = ExceptionFlags.overflow;
    else
    {
        flags = decimalToSigned(x, l, mode);
        result.packIntegral(l, 0, mode);
    }
    DecimalControl.raiseFlags(flags);
    return result;
}

///ditto
@safe
D rndtonl(D)(const auto ref D x)
if (isDecimal!D)
{
    return rndtonl(x, __ctfe ? RoundingMode.tiesToAway : DecimalControl.rounding);
}

/**
Compute the value of x$(SUPERSCRIPT 1/n), where n is an integer
Throws:
$(BOOKTABLE,
    $(TR $(TD $(MYREF InvalidOperationException))
         $(TD x is signaling $(B NaN)))
    $(TR $(TD $(MYREF DivisionByZeroException))
         $(TD x = ±0.0 and n < 0.0))
    $(TR $(TD $(MYREF OverflowException))
         $(TD result is too big to be represented or n = -1))
    $(TR $(TD $(MYREF UnderflowException))
         $(TD result is too small to be represented or n = -1))
    $(TR $(TD $(MYREF InexactException))
         $(TD result is inexact))
)
Special_values:
$(BOOKTABLE,
    $(TR $(TH x) $(TH y) $(TH root(x, n)) )
    $(TR $(TD sNaN) $(TD any) $(TD $(B NaN)) )
    $(TR $(TD any) $(TD 0) $(TD $(B NaN)) )
    $(TR $(TD any) $(TD -1) $(TD $(B NaN)) )
    $(TR $(TD $(B NaN)) $(TD any) $(TD $(B NaN)))
    $(TR $(TD ±∞) $(TD any) $(TD ±∞) )
    $(TR $(TD ±0.0) $(TD odd n < 0) $(TD ±∞))
    $(TR $(TD ±0.0) $(TD even n < 0) $(TD +∞) )
    $(TR $(TD ±0.0) $(TD odd n > 0) $(TD ±0.0)  )
    $(TR $(TD ±0.0) $(TD even n > 0) $(TD +0.0) )
)
*/
@IEEECompliant("rootn", 42)
D root(D)(const auto ref D x, const(T) n)
if (isDecimal!D & isIntegral!T)
{
    Unqual!D1 result = x;
    const flags = decimalRoot(result, n,
                            __ctfe ? D.PRECISION : DecimalControl.precision,
                            __ctfe ? RoundingMode.implicit : DecimalControl.rounding);
    DecimalControl.raiseFlags(flags);
    return result;
}

/**
Returns the value of x rounded away from zero.
This operation is silent, doesn't throw any exception.
Special_values:
$(BOOKTABLE,
    $(TR $(TH x) $(TH round(x)))
    $(TR $(TD $(B NaN)) $(TD $(B NaN)))
    $(TR $(TD ±0.0) $(TD ±0.0))
    $(TR $(TD ±∞) $(TD ±∞))
)
*/
D round(D)(const auto ref D x)
if (isDecimal!D)
{
    Unqual!D result = x;
    decimalRound(result, 0, RoundingMode.tiesToAway);
    return result;
}

/**
Computes the inverse square root of x
Throws:
    $(MYREF InvalidOperationException) if x is signaling $(B NaN) or negative,
    $(MYREF InexactException), $(MYREF UnderflowException),
    $(MYREF DivisionByZeroException)
Special_values:
$(BOOKTABLE,
    $(TR $(TH x) $(TH rsqrt(x)))
    $(TR $(TD $(B NaN)) $(TD $(B NaN)))
    $(TR $(TD < 0.0) $(TD $(B NaN)))
    $(TR $(TD ±0.0) $(TD $(B NaN)))
    $(TR $(TD +∞) $(TD +∞))
)
*/
@IEEECompliant("rSqrt", 42)
D rsqrt(D)(const auto ref D x)
if (isDecimal!D)
{
    Unqual!D result = x;

    const flags = decimalRSqrt(result,
                            __ctfe ? D.PRECISION : DecimalControl.precision,
                            __ctfe ? RoundingMode.implicit : DecimalControl.rounding);
    DecimalControl.raiseFlags(flags);
    return result;
}

/**
Compares the exponents of two _decimal values
Params:
    x = a _decimal value
    y = a _decimal value
Returns:
    true if the internal representation of x and y use the same exponent, false otherwise
Notes:
    Returns also true if both operands are $(B NaN) or both operands are infinite.
*/
@IEEECompliant("sameQuantum", 26)
bool sameQuantum(D1, D2)(const auto ref D1 x, const auto ref D2 y)
if (isDecimal!(D1, D2))
{
    if ((x.data & D1.MASK_INF) == D1.MASK_INF)
    {
        if ((x.data & D1.MASK_QNAN) == D1.MASK_QNAN)
            return (y.data & D2.MASK_QNAN) == D2.MASK_QNAN;
        return (y.data & D2.MASK_SNAN) == D2.MASK_INF;
    }

    if ((y.data & D2.MASK_INF) == D2.MASK_INF)
        return false;

    const expx = (x.data & D1.MASK_EXT) == D1.MASK_EXT
        ? (x.data & D1.MASK_EXP2) >>> D1.SHIFT_EXP2
        : (x.data & D1.MASK_EXP1) >>> D1.SHIFT_EXP1;
    const expy = (x.data & D2.MASK_EXT) == D2.MASK_EXT
        ? (y.data & D2.MASK_EXP2) >>> D2.SHIFT_EXP2
        : (y.data & D2.MASK_EXP1) >>> D2.SHIFT_EXP1;

    const int ex = cast(int)cast(uint)expx;
    const int ey = cast(int)cast(uint)expy;
    return (ex - D1.EXP_BIAS) == (ey - D2.EXP_BIAS);
}

///
unittest
{
    assert(sameQuantum(Decimal32.infinity, -Decimal64.infinity));

    auto x = Decimal32("123456e+23");
    auto y = Decimal64("911911e+23");
    assert(sameQuantum(x, y));

}

/**
Returns:
    x efficiently multiplied by 10$(SUPERSCRIPT n)
Throws:
    $(MYREF InvalidOperationException) if x is signaling $(B NaN), $(MYREF OverflowException),
    $(MYREF UnderflowException), $(MYREF InexactException)
Special_values:
$(BOOKTABLE,
    $(TR $(TH x) $(TH n) $(TH scalbn(x, n)))
    $(TR $(TD $(B NaN)) $(TD any) $(TD $(B NaN)))
    $(TR $(TD ±∞) $(TD any) $(TD ±∞))
    $(TR $(TD ±0) $(TD any) $(TD ±0))
    $(TR $(TD any) $(TD 0) $(TD x))
)
*/
@IEEECompliant("scaleB", 17)
D scalbn(D)(const auto ref D x, const(int) n)
if (isDecimal!D)
{
    Unqual!D result = x;
    const flags = decimalScale(result, n,
                            __ctfe ? D.PRECISION : DecimalControl.precision,
                            __ctfe ? RoundingMode.implicit : DecimalControl.rounding);
    DecimalControl.raiseFlags(flags);
    return result;
}

/**
Multiplies elements of x using a higher precision, rounding only once at the end.
Returns:
    x$(SUBSCRIPT 0) * x$(SUBSCRIPT 1) * ... * x$(SUBSCRIPT n)
Notes:
    To avoid overflow, an additional scale is provided that the final result is to be multiplied py 10$(SUPERSCRIPT scale)
Throws:
$(BOOKTABLE,
    $(TR $(TD $(MYREF InvalidOperationException))
         $(TD any x is signaling $(B NaN)))
    $(TR $(TD $(MYREF InvalidOperationException))
         $(TD there is one infinite element and one 0.0 element))
    $(TR $(TD $(MYREF OverflowException))
         $(TD result is too big to be represented))
    $(TR $(TD $(MYREF UnderflowException))
         $(TD result is too small to be represented))
    $(TR $(TD $(MYREF InexactException))
         $(TD result is inexact))
)
*/
@IEEECompliant("scaledProd", 47)
D scaledProd(D)(const(D)[] x, out int scale)
if (isDecimal!D)
{
    Unqual!D result;
    const flags = decimalProd(x, result, scale,
                         __ctfe ? D.PRECISION : DecimalControl.precision,
                         __ctfe ? RoundingMode.implicit : DecimalControl.rounding);
    DecimalControl.raiseFlags(flags);
    return result;
}

/**
Multiplies results of x$(SUBSCRIPT i) + y$(SUBSCRIPT i) using a higher precision, rounding only once at the end.
Returns:
    (x$(SUBSCRIPT 0) + y$(SUBSCRIPT 0)) * (x$(SUBSCRIPT 1) + y$(SUBSCRIPT 1)) * ... * (x$(SUBSCRIPT n) + y$(SUBSCRIPT n))
Notes:
    To avoid overflow, an additional scale is provided that the final result is to be multiplied py 10$(SUPERSCRIPT scale).<br/>
    If x and y arrays are not of the same length, operation is performed for min(x.length, y.length);
Throws:
$(BOOKTABLE,
    $(TR $(TD $(MYREF InvalidOperationException))
         $(TD any x is signaling $(B NaN)))
    $(TR $(TD $(MYREF InvalidOperationException))
         $(TD any x[i] and y[i] are infinite and with different sign))
    $(TR $(TD $(MYREF InvalidOperationException))
         $(TD there is one infinite element and one x$(SUBSCRIPT i) + y$(SUBSCRIPT i) == 0.0))
    $(TR $(TD $(MYREF OverflowException))
         $(TD result is too big to be represented))
    $(TR $(TD $(MYREF UnderflowException))
         $(TD result is too small to be represented))
    $(TR $(TD $(MYREF InexactException))
         $(TD result is inexact))
)
*/
@IEEECompliant("scaledProdSum", 47)
D scaledProdSum(D)(const(D)[] x, const(D)[] y, out int scale)
if (isDecimal!D)
{
    Unqual!D result;
    const flags = decimalProdSum(x, y, result, scale,
                        __ctfe ? D.PRECISION : DecimalControl.precision,
                        __ctfe ? RoundingMode.implicit : DecimalControl.rounding);
    DecimalControl.raiseFlags(flags);
    return result;
}

/**
Multiplies results of x$(SUBSCRIPT i) - y$(SUBSCRIPT i) using a higher precision, rounding only once at the end.
Returns:
    (x$(SUBSCRIPT 0) - y$(SUBSCRIPT 0)) * (x$(SUBSCRIPT 1) - y$(SUBSCRIPT 1)) * ... * (x$(SUBSCRIPT n) - y$(SUBSCRIPT n))
Notes:
    To avoid overflow, an additional scale is provided that the final result is to be multiplied py 10$(SUPERSCRIPT scale)</br>
    If x and y arrays are not of the same length, operation is performed for min(x.length, y.length);
Throws:
$(BOOKTABLE,
    $(TR $(TD $(MYREF InvalidOperationException))
         $(TD any x is signaling $(B NaN)))
    $(TR $(TD $(MYREF InvalidOperationException))
         $(TD any x$(SUBSCRIPT i) and y$(SUBSCRIPT i) are infinite and with different sign))
    $(TR $(TD $(MYREF InvalidOperationException))
         $(TD there is one infinite element and one x$(SUBSCRIPT i) - y$(SUBSCRIPT i) == 0.0))
    $(TR $(TD $(MYREF OverflowException))
         $(TD result is too big to be represented))
    $(TR $(TD $(MYREF UnderflowException))
         $(TD result is too small to be represented))
    $(TR $(TD $(MYREF InexactException))
         $(TD result is inexact))
)
*/
@IEEECompliant("scaledProdDiff", 47)
D scaledProdDiff(D)(const(D)[] x, const(D)[] y, out int scale)
if (isDecimal!D)
{
    Unqual!D result;
    const flags = decimalProdDiff(x, y, result, scale,
                           __ctfe ? D.PRECISION : DecimalControl.precision,
                           __ctfe ? RoundingMode.implicit : DecimalControl.rounding);
    DecimalControl.raiseFlags(flags);
    return result;
}

bool isValidScale(D)(const(int) scale) @nogc nothrow pure @safe
if (isDecimal!D)
{
    alias UD = Unqual!D;

    static if (is(UD == Decimal32))
        return scale > -5 && scale < 5; // pow10_16
    else static if (is(UD == Decimal64))
        return scale > -10 && scale < 10; // pow10_32
    else static if (is(UD == Decimal128))
        return scale > -20 && scale < 20; // pow10_64
    else
        static assert(0);
}

D scaledPower10(D)(const(int) scale) @nogc nothrow pure @safe
if (isDecimal!D)
in
{
    assert(scale != 0 && isValidScale!D(scale));
}
do
{
    import std.math : abs;

    scope (failure) assert(0, "Assume nothrow failed");

    alias UD = Unqual!D;

    static if (is(UD == Decimal32))
        return UD(pow10_16[cast(int)abs(scale)], RoundingMode.banking);
    else static if (is(UD == Decimal64))
        return UD(pow10_32[cast(int)abs(scale)], RoundingMode.banking);
    else static if (is(UD == Decimal128))
        return UD(pow10_64[cast(int)abs(scale)], RoundingMode.banking);
    else
        static assert(0);
}

D scaleFrom(T, D)(const auto ref T value, const(int) scale,
    const(RoundingMode) roundingMode = RoundingMode.banking) pure @safe
if (isDecimal!D && (is(Unqual!T == short) || is(Unqual!T == int) || is(Unqual!T == long)))
in
{
    assert(isValidScale!D(scale));
}
do
{
    alias UD = Unqual!D;

    UD result = UD(value, roundingMode);
	if (scale != 0 && result != 0)
    {
		const UD scaleD = scaledPower10!D(scale);
        if (scale < 0)
            decimalDiv(result, scaleD, 0, roundingMode);
        else
            decimalMul(result, scaleD, 0, roundingMode);
    }
    return result;
}

unittest // scaleFrom
{
    assert(scaleFrom!(int, Decimal32)(-100, -2) == -1.0);
    assert(scaleFrom!(int, Decimal32)(0, -2) == 0.0);
    assert(scaleFrom!(int, Decimal32)(1234567, -2) == 12345.67);

    assert(scaleFrom!(long, Decimal64)(-100, -2) == -1.0);
    assert(scaleFrom!(long, Decimal64)(0, -2) == 0.0);
    assert(scaleFrom!(long, Decimal64)(1234567L, -2) == 12345.67);
}

T scaleTo(D, T)(const auto ref D value, const(int) scale,
    const(RoundingMode) roundingMode = RoundingMode.banking) @nogc nothrow pure @safe
if (isDecimal!D && (is(T == short) || is(T == int) || is(T == long)))
in
{
    assert(isValidScale!D(scale));
}
do
{
    import std.math : abs;

    alias UD = Unqual!D;
    alias UT = Unqual!T;

    UD scaledValue = value;
    if (scale != 0 && scaledValue != 0)
    {
        const UD scaleD = scaledPower10!D(scale);
        if (scale < 0)
            decimalMul(scaledValue, scaleD, 0, roundingMode);
        else
            decimalDiv(scaledValue, scaleD, 0, roundingMode);
    }
    UT result = 0;
    decimalToSigned(scaledValue, result, roundingMode);
    return result;
}

unittest // scaleTo
{
    assert(scaleTo!(Decimal32, int)(Decimal32(0), -2) == 0);
    assert(scaleTo!(Decimal32, int)(Decimal32(-1), -2) == -100);
    assert(scaleTo!(Decimal32, int)(Decimal32(12345.67), -2) == 1234567);

    assert(scaleTo!(Decimal64, long)(Decimal64(0), -2) == 0);
    assert(scaleTo!(Decimal64, long)(Decimal64(-1), -2) == -100);
    assert(scaleTo!(Decimal64, long)(Decimal64(12345.67), -2) == 1234567);
}

/**
Determines if x is negative
This operation is silent, no error flags are set and no exceptions are thrown.
Params:
    x = a _decimal value
Returns:
    -1.0 if x is negative, 0.0 if x is zero, 1.0 if x is positive
*/
@safe pure nothrow @nogc
D sgn(D: Decimal!bits, int bits)(const auto ref D x)
{
    return x.isNeg ? D.negOne : (x.isZero ? D.zero : D.one);
}

///
unittest
{
    assert(sgn(Decimal32.max) == 1);
    assert(sgn(-Decimal32.max) == -1);
    assert(sgn(Decimal64(0)) == 0);
}

unittest
{
    import std.meta : AliasSeq;

    foreach (T; AliasSeq!(Decimal32, Decimal64, Decimal128))
    {
        assert(sgn(T.nan) == 1);
        assert(sgn(T.infinity) == 1);
        assert(sgn(T.negInfinity) == -1);
    }
}

///sign
unittest // sign
{
    assert((-Decimal32.infinity).sign == -1);
    assert(Decimal64.min.sign == -1);
    assert(Decimal64.min_normal.sign == 1);
    assert(Decimal128.max.sign == 1);
    assert((-Decimal128.max).sign == -1);
}

unittest // sign
{
    import std.meta : AliasSeq;

    foreach (T; AliasSeq!(Decimal32, Decimal64, Decimal128))
    {
        assert(T.sNaN.sign == 1);
        assert(T.negInfinity.sign == -1);
        assert(T.zero.sign == 0);
        assert(T.negZero.sign == -1);
    }
}

alias signbit = signStd;

/**
Returns the sign bit of the specified value.
This operation is silent, no error flags are set and no exceptions are thrown.
Params:
    x = a _decimal value
Returns:
    1 if the sign bit is set, 0 otherwise
*/
@IEEECompliant("isSignMinus", 25)
int signbit(D: Decimal!bytes, int bytes)(const auto ref D x)
{
    static if (is(D: Decimal32) || is(D: Decimal64))
    {
        return cast(uint)((x.data & D.MASK_SGN) >>> ((D.sizeof * 8) - 1));
    }
    else
    {
        return cast(uint)((x.data.hi & D.MASK_SGN.hi) >>> ((D.sizeof * 4) - 1));
    }
}

///
unittest
{
    assert(signbit(-Decimal32.infinity) == 1);
    assert(signbit(Decimal64.min_normal) == 0);
    assert(signbit(-Decimal128.max) == 1);
}

unittest
{
    import std.meta : AliasSeq;

    foreach (T; AliasSeq!(Decimal32, Decimal64, Decimal128))
    {
        assert(signbit(T.sNaN) == 0);
        assert(signbit(T.negInfinity) == 1);
        assert(signbit(T.zero) == 0);
        assert(signbit(T.negZero) == 1);
    }
}

/**
Returns sine of x.
Throws:
$(BOOKTABLE,
    $(TR $(TD $(MYREF InvalidOperationException))
         $(TD x is signaling $(B NaN) or ±∞))
    $(TR $(TD $(MYREF UnderflowException))
         $(TD result is too small to be represented))
    $(TR $(TD $(MYREF InexactException))
         $(TD the result is inexact))
)
Special_values:
$(BOOKTABLE,
    $(TR $(TH x) $(TH sin(x)))
    $(TR $(TD $(B NaN)) $(TD $(B NaN)))
    $(TR $(TD ±∞) $(TD $(B NaN)))
    $(TR $(TD -π/2) $(TD -1.0))
    $(TR $(TD -π/3) $(TD -√3/2))
    $(TR $(TD -π/4) $(TD -√2/2))
    $(TR $(TD -π/6) $(TD -0.5))
    $(TR $(TD ±0.0) $(TD +0.0))
    $(TR $(TD +π/6) $(TD +0.5))
    $(TR $(TD +π/4) $(TD +√2/2))
    $(TR $(TD +π/3) $(TD +√3/2))
    $(TR $(TD +π/2) $(TD +1.0))
)
*/
@IEEECompliant("sin", 42)
D sin(D)(const auto ref D x)
if (isDecimal!D)
{
    Unqual!D result = x;
    const flags = decimalSin(result,
                             __ctfe ? D.PRECISION : DecimalControl.precision,
                             __ctfe ? RoundingMode.implicit : DecimalControl.rounding);
    DecimalControl.raiseFlags(flags);
    return result;
}

/**
Calculates the hyperbolic sine of x.
Throws:
$(BOOKTABLE,
    $(TR $(TD $(MYREF InvalidOperationException))
         $(TD x is signaling $(B NaN)))
    $(TR $(TD $(MYREF OverflowException))
         $(TD result is too big to be represented))
    $(TR $(TD $(MYREF InexactException))
         $(TD the result is inexact))
)
Special_values:
$(BOOKTABLE,
    $(TR $(TH x) $(TH sinh(x)))
    $(TR $(TD $(B NaN)) $(TD $(B NaN)))
    $(TR $(TD ±∞) $(TD +∞))
    $(TR $(TD ±0.0) $(TD +0.0))
)
*/
@IEEECompliant("sinh", 42)
D sinh(D)(const auto ref D x)
if (isDecimal!D)
{
    Unqual!D result = x;
    const flags = decimalSinh(result,
                            __ctfe ? D.PRECISION : DecimalControl.precision,
                            __ctfe ? RoundingMode.implicit : DecimalControl.rounding);
    DecimalControl.raiseFlags(flags);
    return result;
}

/**
Returns sine of x*π.
Throws:
$(BOOKTABLE,
    $(TR $(TD $(MYREF InvalidOperationException))
         $(TD x is signaling $(B NaN) or ±∞))
    $(TR $(TD $(MYREF UnderflowException))
         $(TD result is too small to be represented))
    $(TR $(TD $(MYREF InexactException))
         $(TD the result is inexact))
)
Special_values:
$(BOOKTABLE,
    $(TR $(TH x) $(TH sin(x)))
    $(TR $(TD $(B NaN)) $(TD $(B NaN)))
    $(TR $(TD ±∞) $(TD $(B NaN)))
    $(TR $(TD -1/2) $(TD -1.0))
    $(TR $(TD -1/3) $(TD -√3/2))
    $(TR $(TD -1/4) $(TD -√2/2))
    $(TR $(TD -1/6) $(TD -0.5))
    $(TR $(TD ±0.0) $(TD +0.0))
    $(TR $(TD +1/6) $(TD +0.5))
    $(TR $(TD +1/4) $(TD +√2/2))
    $(TR $(TD +1/3) $(TD +√3/2))
    $(TR $(TD +1/2) $(TD +1.0))
)
*/
@IEEECompliant("sinPi", 42)
D sinPi(D)(const auto ref D x)
if (isDecimal!D)
{
    Unqual!D result = x;
    const flags = decimalSinPi(result,
                             __ctfe ? D.PRECISION : DecimalControl.precision,
                             __ctfe ? RoundingMode.implicit : DecimalControl.rounding);
    DecimalControl.raiseFlags(flags);
    return result;
}

/**
Computes the square root of x
Throws:
    $(MYREF InvalidOperationException) if x is signaling $(B NaN) or negative,
    $(MYREF InexactException), $(MYREF UnderflowException)
Special_values:
$(BOOKTABLE,
    $(TR $(TH x) $(TH sqrt(x)))
    $(TR $(TD $(B NaN)) $(TD $(B NaN)))
    $(TR $(TD < 0.0) $(TD $(B NaN)))
    $(TR $(TD ±0.0) $(TD ±0.0))
    $(TR $(TD +∞) $(TD +∞))
)
*/
@IEEECompliant("squareRoot", 42)
D sqrt(D)(const auto ref D x)
if (isDecimal!D)
{
    Unqual!D result = x;
    const flags = decimalSqrt(result,
                        __ctfe ? D.PRECISION : DecimalControl.precision,
                        __ctfe ? RoundingMode.implicit : DecimalControl.rounding);
    DecimalControl.raiseFlags(flags);
    return result;
}

/**
Sums elements of x using a higher precision, rounding only once at the end.</br>
Returns:
    x$(SUBSCRIPT 0) + x$(SUBSCRIPT 1) + ... + x$(SUBSCRIPT n)
Throws:
$(BOOKTABLE,
    $(TR $(TD $(MYREF InvalidOperationException))
         $(TD any x is signaling $(B NaN)))
    $(TR $(TD $(MYREF InvalidOperationException))
         $(TD there are two infinite elements with different sign))
    $(TR $(TD $(MYREF OverflowException))
         $(TD result is too big to be represented))
    $(TR $(TD $(MYREF UnderflowException))
         $(TD result is too small to be represented))
    $(TR $(TD $(MYREF InexactException))
         $(TD result is inexact))
)
*/
@IEEECompliant("sum", 47)
D sum(D)(const(D)[] x)
if (isDecimal!D)
{
    Unqual!D result;
    const flags = decimalSum(x, result,
                             __ctfe ? D.PRECISION : DecimalControl.precision,
                             __ctfe ? RoundingMode.implicit : DecimalControl.rounding);
    DecimalControl.raiseFlags(flags);
    return result;
}

/**
Sums absolute elements of x using a higher precision, rounding only once at the end.
Returns:
    |x$(SUBSCRIPT 0)| + |x$(SUBSCRIPT 1)| + ... + |x$(SUBSCRIPT n)|
Throws:
$(BOOKTABLE,
    $(TR $(TD $(MYREF InvalidOperationException))
         $(TD any x is signaling $(B NaN)))
    $(TR $(TD $(MYREF OverflowException))
         $(TD result is too big to be represented))
    $(TR $(TD $(MYREF UnderflowException))
         $(TD result is too small to be represented))
    $(TR $(TD $(MYREF InexactException))
         $(TD result is inexact))
)
*/
@IEEECompliant("sumAbs", 47)
D sumAbs(D)(const(D)[] x)
if (isDecimal!D)
{
    Unqual!D result;
    const flags = decimalSumAbs(x, result,
                            __ctfe ? D.PRECISION : DecimalControl.precision,
                            __ctfe ? RoundingMode.implicit : DecimalControl.rounding);
    DecimalControl.raiseFlags(flags);
    return result;
}

/**
Sums squares of elements of x using a higher precision, rounding only once at the end.
Returns:
    x$(SUBSCRIPT 0)$(SUPERSCRIPT 2) + x$(SUBSCRIPT 1)$(SUPERSCRIPT 2) + ... + x$(SUBSCRIPT n)$(SUPERSCRIPT 2)
Throws:
$(BOOKTABLE,
    $(TR $(TD $(MYREF InvalidOperationException))
         $(TD any x is signaling $(B NaN)))
    $(TR $(TD $(MYREF OverflowException))
         $(TD result is too big to be represented))
    $(TR $(TD $(MYREF UnderflowException))
         $(TD result is too small to be represented))
    $(TR $(TD $(MYREF InexactException))
         $(TD result is inexact))
)
*/
@IEEECompliant("sumSquare", 47)
D sumSquare(D)(const(D)[] x)
if (isDecimal!D)
{
    Unqual!D result;
    const flags = decimalSumSquare(x, result,
                            __ctfe ? D.PRECISION : DecimalControl.precision,
                            __ctfe ? RoundingMode.implicit : DecimalControl.rounding);
    DecimalControl.raiseFlags(flags);
    return result;
}

/**
Returns tangent of x.
Throws:
$(BOOKTABLE,
    $(TR $(TD $(MYREF InvalidOperationException))
         $(TD x is signaling $(B NaN) or ±∞))
    $(TR $(TD $(MYREF UnderflowException))
         $(TD result is too small to be represented))
    $(TR $(TD $(MYREF OverflowException))
         $(TD result is too big to be represented))
    $(TR $(TD $(MYREF InexactException))
         $(TD the result is inexact))
)
Special_values:
$(BOOKTABLE,
    $(TR $(TH x) $(TH tan(x)))
    $(TR $(TD $(B NaN)) $(TD $(B NaN)))
    $(TR $(TD ±∞) $(TD $(B NaN)))
    $(TR $(TD -π/2) $(TD -∞))
    $(TR $(TD -π/3) $(TD -√3))
    $(TR $(TD -π/4) $(TD -1.0))
    $(TR $(TD -π/6) $(TD -1/√3))
    $(TR $(TD ±0.0) $(TD +0.0))
    $(TR $(TD +π/6) $(TD +1/√3))
    $(TR $(TD +π/4) $(TD +1.0))
    $(TR $(TD +π/3) $(TD +√3))
    $(TR $(TD +π/2) $(TD +∞))
)
*/
@IEEECompliant("tan", 42)
D tan(D)(const auto ref D x)
if (isDecimal!D)
{
    Unqual!D result = x;
    const flags = decimalTan(result,
                             __ctfe ? D.PRECISION : DecimalControl.precision,
                             __ctfe ? RoundingMode.implicit : DecimalControl.rounding);
    DecimalControl.raiseFlags(flags);
    return result;
}

/**
Returns tangent of x.
Throws:
$(BOOKTABLE,
    $(TR $(TD $(MYREF InvalidOperationException))
         $(TD x is signaling $(B NaN) ))
    $(TR $(TD $(MYREF UnderflowException))
         $(TD result is too small to be represented))
    $(TR $(TD $(MYREF OverflowException))
         $(TD result is too big to be represented))
    $(TR $(TD $(MYREF InexactException))
         $(TD the result is inexact))
)
Special_values:
$(BOOKTABLE,
    $(TR $(TH x) $(TH tanh(x)))
    $(TR $(TD $(B NaN)) $(TD $(B NaN)))
    $(TR $(TD ±∞) $(TD ±1.0))
    $(TR $(TD ±0.0) $(TD ±0.0))
)
*/
@IEEECompliant("tanh", 42)
D tanh(D)(const auto ref D x)
if (isDecimal!D)
{
    Unqual!D result = x;
    const flags = decimalTanh(result,
                            __ctfe ? D.PRECISION : DecimalControl.precision,
                            __ctfe ? RoundingMode.implicit : DecimalControl.rounding);
    DecimalControl.raiseFlags(flags);
    return result;
}

/**
Converts x to the specified integral type rounded if necessary by mode
Throws:
    $(MYREF InvalidOperationException) if x is $(B NaN),
    $(MYREF UnderflowException), $(MYREF OverflowException)
Special_values:
$(BOOKTABLE,
    $(TR $(TH x) $(TH to!T(x)))
    $(TR $(TD $(B NaN)) $(TD 0))
    $(TR $(TD +∞) $(TD T.max))
    $(TR $(TD -∞) $(TD T.min))
    $(TR $(TD ±0.0) $(TD 0))
)
*/
@IEEECompliant("convertToIntegerTiesToAway", 22)
@IEEECompliant("convertToIntegerTiesToEven", 22)
@IEEECompliant("convertToIntegerTowardNegative", 22)
@IEEECompliant("convertToIntegerTowardPositive", 22)
@IEEECompliant("convertToIntegerTowardZero", 22)
T to(T, D)(const auto ref D x, const(RoundingMode) mode)
if (isIntegral!T && isDecimal!D)
{
    Unqual!T result;
    static if (isUnsigned!T)
        const flags = decimalToUnsigned(x, result, mode);
    else
        const flags = decimalToSigned(x, result, mode);
    DecimalControl.raiseFlags(flags & ExceptionFlags.invalidOperation);
    return result;
}

/**
Converts x to the specified binary floating point type rounded if necessary by mode
Throws:
    $(MYREF UnderflowException), $(MYREF OverflowException)
*/
F to(F, D)(const auto ref D x, const(RoundingMode) mode)
if (isFloatingPoint!F && isDecimal!D)
{
    Unqual!F result;
    auto flags = decimalToFloat(x, result, mode);
    flags &= ~ExceptionFlags.inexact;
    if (__ctfe)
        DecimalControl.checkFlags(flags, ExceptionFlags.severe);
    else
        DecimalControl.raiseFlags(flags);
    return result;
}

/**
Converts the specified value from internal encoding from/to densely packed decimal encoding
Notes:
   _Decimal values are represented internaly using
   $(LINK2 https://en.wikipedia.org/wiki/Binary_Integer_Decimal, binary integer _decimal encoding),
   supported by Intel (BID).
   This function converts the specified value to/from
   $(LINK2 https://en.wikipedia.org/wiki/Densely_Packed_Decimal, densely packed _decimal encoding),
   supported by IBM (DPD).
   Please note that a DPD encoded _decimal cannot be passed to a function from this module, there is no way
   to determine if a _decimal value is BID-encoded or DPD-encoded, all functions will assume a BID-encoding.
*/
@IEEECompliant("encodeDecimal", 23)
@safe pure nothrow @nogc
Decimal32 toDPD(const(Decimal32) x)
{
    if (x.isNaN || x.isInfinity || x.isZero)
        return canonical(x);

    uint cx = void;
    int ex = void;
    const bool sx = x.unpack(cx, ex);

    uint[7] digits;
    size_t index = digits.length;
    while (cx)
        digits[--index] = divrem(cx, 10U);

    cx = packDPD(digits[$ - 3], digits[$ - 2], digits[$ - 1]);
    cx |= packDPD(digits[$ - 6], digits[$ - 5], digits[$ - 4]) << 10;
    cx |= cast(uint)digits[0] << 20;

    Decimal32 result;
    result.pack(cx, ex, sx);
    return result;
}

///ditto
@IEEECompliant("encodeDecimal", 23)
@safe pure nothrow @nogc
Decimal64 toDPD(const(Decimal64) x)
{
    if (x.isNaN || x.isInfinity || x.isZero)
        return canonical(x);

    ulong cx = void;
    int ex = void;
    const bool sx = x.unpack(cx, ex);

    uint[16] digits;
    size_t index = digits.length;
    while (cx)
        digits[--index] = cast(uint)(divrem(cx, 10U));

    cx = cast(ulong)(packDPD(digits[$ - 3], digits[$ - 2], digits[$ - 1]));
    cx |= cast(ulong)packDPD(digits[$ - 6], digits[$ - 5], digits[$ - 4]) << 10;
    cx |= cast(ulong)packDPD(digits[$ - 9], digits[$ - 8], digits[$ - 7]) << 20;
    cx |= cast(ulong)packDPD(digits[$ - 12], digits[$ - 11], digits[$ - 10]) << 30;
    cx |= cast(ulong)packDPD(digits[$ - 15], digits[$ - 14], digits[$ - 13]) << 40;
    cx |= cast(ulong)digits[0] << 50;

    Decimal64 result;
    result.pack(cx, ex, sx);
    return result;
}

///ditto
@IEEECompliant("encodeDecimal", 23)
@safe pure nothrow @nogc
Decimal128 toDPD(const(Decimal128) x)
{
    if (x.isNaN || x.isInfinity || x.isZero)
        return canonical(x);

    uint128 cx = void;
    int ex = void;
    const bool sx = x.unpack(cx, ex);

    uint[34] digits;
    size_t index = digits.length;
    while (cx)
        digits[--index] = cast(uint)(divrem(cx, 10U));

    cx = uint128(packDPD(digits[$ - 3], digits[$ - 2], digits[$ - 1]));
    cx |= uint128(packDPD(digits[$ - 6], digits[$ - 5], digits[$ - 4])) << 10;
    cx |= uint128(packDPD(digits[$ - 9], digits[$ - 8], digits[$ - 7])) << 20;
    cx |= uint128(packDPD(digits[$ - 12], digits[$ - 11], digits[$ - 10])) << 30;
    cx |= uint128(packDPD(digits[$ - 15], digits[$ - 14], digits[$ - 13])) << 40;
    cx |= uint128(packDPD(digits[$ - 18], digits[$ - 17], digits[$ - 16])) << 50;
    cx |= uint128(packDPD(digits[$ - 21], digits[$ - 20], digits[$ - 19])) << 60;
    cx |= uint128(packDPD(digits[$ - 24], digits[$ - 23], digits[$ - 22])) << 70;
    cx |= uint128(packDPD(digits[$ - 27], digits[$ - 26], digits[$ - 25])) << 80;
    cx |= uint128(packDPD(digits[$ - 30], digits[$ - 29], digits[$ - 28])) << 90;
    cx |= uint128(packDPD(digits[$ - 33], digits[$ - 32], digits[$ - 31])) << 100;
    cx |= uint128(digits[0]) << 110;

    Decimal128 result;
    result.pack(cx, ex, sx);
    return result;
}

///ditto
@IEEECompliant("decodeDecimal", 23)
@safe pure nothrow @nogc
Decimal32 fromDPD(const(Decimal32) x)
{
    if (x.isNaN || x.isInfinity || x.isZero)
        return canonical(x);

    uint[7] digits;
    uint cx = void;
    int ex = void;
    const bool sx = x.unpack(cx, ex);

    unpackDPD(cx & 1023, digits[$ - 1], digits[$ - 2], digits[$ - 3]);
    unpackDPD((cx >>> 10) & 1023, digits[$ - 4], digits[$ - 5], digits[$ - 6]);
    digits[0] = (cx >>> 20) & 15;

    cx = 0U;
    for (size_t i = 0; i < digits.length; ++i)
        cx += digits[i] * pow10!uint[6 - i];

    Decimal32 result;
    result.pack(cx, ex, sx);
    return result;
}

///ditto
@IEEECompliant("decodeDecimal", 23)
@safe pure nothrow @nogc
Decimal64 fromDPD(const(Decimal64) x)
{
    if (x.isNaN || x.isInfinity || x.isZero)
        return canonical(x);

    uint[16] digits;
    ulong cx = void;
    int ex = void;
    const bool sx = x.unpack(cx, ex);

    unpackDPD(cast(uint)cx & 1023, digits[$ - 1], digits[$ - 2], digits[$ - 3]);
    unpackDPD(cast(uint)(cx >>> 10) & 1023, digits[$ - 4], digits[$ - 5], digits[$ - 6]);
    unpackDPD(cast(uint)(cx >>> 20) & 1023, digits[$ - 7], digits[$ - 8], digits[$ - 9]);
    unpackDPD(cast(uint)(cx >>> 30) & 1023, digits[$ - 10], digits[$ - 11], digits[$ - 12]);
    unpackDPD(cast(uint)(cx >>> 40) & 1023, digits[$ - 13], digits[$ - 14], digits[$ - 15]);
    digits[0] = cast(uint)(cx >>> 50) & 15;

    cx = 0U;
    for (size_t i = 0; i < digits.length; ++i)
        cx += digits[i] * pow10!ulong[15 - i];

    Decimal64 result;
    result.pack(cx, ex, sx);
    return result;
}

///ditto
@safe pure nothrow @nogc
@IEEECompliant("decodeDecimal", 23)
Decimal128 fromDPD(const(Decimal128) x)
{
    if (x.isNaN || x.isInfinity || x.isZero)
        return canonical(x);

    uint[34] digits;
    uint128 cx = void;
    int ex = void;
    const bool sx = x.unpack(cx, ex);

    unpackDPD(cast(uint)cx & 1023U, digits[$ - 1], digits[$ - 2], digits[$ - 3]);
    unpackDPD(cast(uint)(cx >>> 10) & 1023, digits[$ - 4], digits[$ - 5], digits[$ - 6]);
    unpackDPD(cast(uint)(cx >>> 20) & 1023, digits[$ - 7], digits[$ - 8], digits[$ - 9]);
    unpackDPD(cast(uint)(cx >>> 30) & 1023, digits[$ - 10], digits[$ - 11], digits[$ - 12]);
    unpackDPD(cast(uint)(cx >>> 40) & 1023, digits[$ - 13], digits[$ - 14], digits[$ - 15]);
    unpackDPD(cast(uint)(cx >>> 50) & 1023, digits[$ - 16], digits[$ - 17], digits[$ - 18]);
    unpackDPD(cast(uint)(cx >>> 60) & 1023, digits[$ - 19], digits[$ - 20], digits[$ - 21]);
    unpackDPD(cast(uint)(cx >>> 70) & 1023, digits[$ - 22], digits[$ - 23], digits[$ - 24]);
    unpackDPD(cast(uint)(cx >>> 80) & 1023, digits[$ - 25], digits[$ - 26], digits[$ - 27]);
    unpackDPD(cast(uint)(cx >>> 90) & 1023, digits[$ - 28], digits[$ - 29], digits[$ - 30]);
    unpackDPD(cast(uint)(cx >>> 100) & 1023, digits[$ - 31], digits[$ - 32], digits[$ - 33]);
    digits[0] = cast(uint)(cx >>> 110) & 15;

    cx = 0U;
    for (size_t i = 0; i < digits.length; ++i)
        cx += pow10!uint128[34 - i] * digits[i];

    Decimal128 result;
    result.pack(cx, ex, sx);
    return result;
}

/**
Converts x to the specified integral type rounded if necessary by mode
Throws:
$(MYREF InvalidOperationException) if x is $(B NaN),
$(MYREF InexactException)
$(MYREF UnderflowException), $(MYREF OverflowException)
Special_values:
$(BOOKTABLE,
$(TR $(TH x) $(TH toExact!T(x)))
$(TR $(TD $(B NaN)) $(TD 0))
$(TR $(TD +∞) $(TD T.max))
$(TR $(TD -∞) $(TD T.min))
$(TR $(TD ±0.0) $(TD 0))
)
*/
@IEEECompliant("convertToIntegerExactTiesToAway", 22)
@IEEECompliant("convertToIntegerExactTiesToEven", 22)
@IEEECompliant("convertToIntegerExactTowardNegative", 22)
@IEEECompliant("convertToIntegerExactTowardPositive", 22)
@IEEECompliant("convertToIntegerExactTowardZero", 22)
T toExact(T, D)(const auto ref D x, const(RoundingMode) mode)
if (isIntegral!T && isDecimal!D)
{
    enum checkFlags = ExceptionFlags.invalidOperation | ExceptionFlags.inexact;
    Unqual!T result;
    static if (isUnsigned!T)
        const flags = decimalToUnsigned(x, result, mode);
    else
        const flags = decimalToSigned(x, result, mode);
    DecimalControl.raiseFlags(flags & checkFlags);
    return result;
}

/**
Converts x to the specified binary floating point type rounded if necessary by mode
Throws:
    $(MYREF UnderflowException), $(MYREF OverflowException),
    $(MYREF InexactException)
*/
F toExact(F, D)(const auto ref D x, const(RoundingMode) mode)
if (isFloatingPoint!F && isDecimal!D)
{
    Unqual!F result;
    const flags = decimalToFloat(x, result, __ctfe ? RoundingMode.implicit : DecimalControl.rounding);
    DecimalControl.raiseFlags(flags);
    return result;
}

/**
Converts the specified value to/from Microsoft currency data type;
Throws:
$(BOOKTABLE,
    $(TR $(TD $(MYREF InvalidOperationException))
        $(TD x is $(B NaN)))
    $(TR $(TD $(MYREF OverflowException))
        $(TD x is infinite or outside the Currency limits))
    $(TR $(TD $(MYREF UnderflowException))
        $(TD x is too small to be represented as Currency))
    $(TR $(TD $(MYREF InexactException))
         $(TD x cannot be represented exactly))
)
Notes:
    The Microsoft currency data type is stored as long
    always scaled by 10$(SUPERSCRIPT -4)
*/
long toMsCurrency(D)(const auto ref D x)
if (isDecimal!D)
{
    if (x.isNaN)
    {
        DecimalControl.raiseFlags(ExceptionFlags.invalidOperation);
        return 0;
    }

    if (x.isInfinity)
    {
        DecimalControl.raiseFlags(ExceptionFlags.overflow);
        return signbit(x) ? long.max : long.min;
    }

    if (x.isZero)
        return 0;

    ex +=4;

    long result;
    const flags = decimalToSigned!long(x, result,
                __ctfe ? RoundingMode.implicit : DecimalControl.rounding);
    DecimalControl.raiseFlags(flags);
    return result;
}

///ditto
D fromMsCurrency(D)(const(ulong) x)
if (isDecimal!D)
{
    Unqual!D result;
    auto flags = result.packIntegral(x, D.PRECISION, RoundingMode.implicit);
    flags |= decimalDiv(result, 100,
                        __ctfe ? D.PRECISION : DecimalControl.precision,
                        __ctfe ? RoundingMode.implicit : DecimalControl.rounding);
    DecimalControl.raiseFlags(flags);
    return result;
}

/**
Converts the specified value to/from Microsoft _decimal data type;
Throws:
$(BOOKTABLE,
    $(TR $(TD $(MYREF InvalidOperationException))
        $(TD x is $(B NaN)))
    $(TR $(TD $(MYREF OverflowException))
        $(TD x is infinite or outside the DECIMAL limits))
    $(TR $(TD $(MYREF UnderflowException))
        $(TD x is too small to be represented as DECIMAL))
    $(TR $(TD $(MYREF InexactException))
         $(TD x cannot be represented exactly))
)
Notes:
    The Microsoft _decimal data type is stored as a 96 bit integral
    scaled by a variable exponent between 10$(SUPERSCRIPT -28) and 10$(SUPERSCRIPT 0).
*/
DECIMAL toMsDecimal(D)(const auto ref D x)
{
    DECIMAL result;

    if (x.isNaN)
    {
        if (__ctfe)
            DecimalControl.checkFlags(ExceptionFlags.invalidOperation, ExceptionFlags.severe);
        else
            DecimalControl.raiseFlags(ExceptionFlags.invalidOperation);
        return result;
    }

    if (x.isInfinity)
    {
        if (__ctfe)
            DecimalControl.checkFlags(ExceptionFlags.overflow, ExceptionFlags.severe);
        else
            DecimalControl.raiseFlags(ExceptionFlags.overflow);
        result.Lo64 = ulong.max;
        result.Hi32 = uint.max;
        if (signbit(x))
            result.sign = DECIMAL.DECIMAL_NEG;
        return result;
    }

    if (x.isZero)
        return result;

    DataType!(D.sizeof) cx = void;
    int ex = void;
    const bool sx = x.unpack(cx, ex);

    static if (is(D == Decimal128))
        alias cxx = cx;
    else
        uint128 cxx = cx;

    enum cmax = uint128(cast(ulong)(uint.max), ulong.max);

    const flags = coefficientAdjust(cxx, ex, -28, 0, cmax, sx,
                                __ctfe ? RoundingMode.implicit : DecimalControl.rounding);

    if (flags & ExceptionFlags.overflow)
    {
        result.Lo64 = ulong.max;
        result.Hi32 = uint.max;
        if (signbit(x))
            result.sign = DECIMAL.DECIMAL_NEG;
    }
    else if (flags & ExceptionFlags.underflow)
    {
        result.Lo64 = 0;
        result.Hi32 = 0;
        if (sx)
            result.sign = DECIMAL.DECIMAL_NEG;
    }
    else
    {
        result.Lo64 = cxx.lo;
        result.Hi32 = cast(uint)(cxx.hi);
        result.scale = -ex;
        if (sx)
            result.sign = DECIMAL.DECIMAL_NEG;
    }

    DecimalControl.raiseFlags(flags);
    return result;
}

///ditto
D fromMsDecimal(D)(const auto ref DECIMAL x)
{
    Unqual!D result;

    uint128 cx = uint128(cast(ulong)(x.Hi32), x.Lo64);
    int ex = -x.scale;
    bool sx = (x.sign & DECIMAL.DECIMAL_NEG) == DECIMAL.DECIMAL_NEG;

    auto flags = coefficientAdjust(cx, ex, cvt!uint128(D.COEF_MAX), RoundingMode.implicit);
    flags |= result.adjustedPack(cvt!(DataType!(D.sizeof))(cx), ex, sx,
                                    __ctfe ?  D.PRECISION : DecimalControl.precision,
                                    __ctfe ? RoundingMode.implicit  : DecimalControl.rounding,
                                    flags);
    DecimalControl.raiseFlags(flags);
    return result;
}

/**
Checks the order between two _decimal values
Params:
    x = a _decimal value
    y = a _decimal value
Returns:
    true if x precedes y, false otherwise
Notes:
    totalOrderAbs checks the order between |x| and |y|
See_Also:
    $(MYREF cmp)
*/
@IEEECompliant("totalOrder", 25)
bool totalOrder(D1, D2)(const auto ref D1 x, const auto ref D2 y)
if (isDecimal!(D1, D2))
{
    return cmp(x, y) <= 0;
}

///ditto
@IEEECompliant("totalOrderAbs", 25)
bool totalOrderAbs(D1, D2)(const auto ref D1 x, const auto ref D2 y)
if (isDecimal!(D1, D2))
{
    return cmp(fabs(x), fabs(y)) <= 0;
}

///
unittest
{
    assert(totalOrder(Decimal32.min_normal, Decimal64.max));
    assert(!totalOrder(Decimal32.max, Decimal128.min_normal));
    assert(totalOrder(-Decimal64(0), Decimal64(0)));
    assert(totalOrderAbs(Decimal64(0), -Decimal64(0)));
}

/**
Returns the value of x rounded up or down, depending on sign (toward zero).
This operation is silent, doesn't throw any exception.
Special_values:
$(BOOKTABLE,
$(TR $(TH x) $(TH trunc(x)))
$(TR $(TD $(B NaN)) $(TD $(B NaN)))
$(TR $(TD ±0.0) $(TD ±0.0))
$(TR $(TD ±∞) $(TD ±∞))
)
*/
@safe pure nothrow @nogc
D trunc(D)(const auto ref D x)
if (isDecimal!D)
{
    Unqual!D result = x;
    decimalRound(result, 0, RoundingMode.towardZero);
    return result;
}

/**
Gives the previous power of 10 before x.
Throws:
    $(MYREF InvalidOperationException),
    $(MYREF OverflowException),
    $(MYREF UnderflowException),
    $(MYREF InexactException)
Special_values:
$(BOOKTABLE,
    $(TR $(TH x) $(TH truncPow10(x)))
    $(TR $(TD $(B NaN)) $(TD $(B NaN)))
    $(TR $(TD ±∞) $(TD ±∞))
    $(TR $(TD ±0.0) $(TD ±0.0))
)
*/
D truncPow10(D)(const auto ref D x)
if (isDecimal!D)
{
    Unqual!D result;
    ExceptionFlags flags;

    if (x.isSignalNaN)
    {
        result = D.nan;
        flags = ExceptionFlags.invalidOperation;
    }
    else if (x.isNaN || x.isInfinity || x.isZero)
        result = x;
    else
    {
        alias U = DataType!(D.sizeof);
        U c = void;
        int e = void;
        const bool s = x.unpack(c, e);
        for (size_t i = 0; i < pow10!U.length; ++i)
        {
            if (c == pow10!U[i])
                break;
            else if (c < pow10!U[i])
            {
                c = pow10!U[i - 1];
                break;
            }
        }
        if (i == pow10!U.length)
            c = pow10!U[$ - 1];
        flags = coefficientAdjust(c, e, D.EXP_MIN, D.EXP_MAX, D.COEF_MAX, s, RoundingMode.towardZero);
        flags |= result.pack(c, e, s, flags);
    }

    if (__ctfe)
        DecimalControl.checkFlags(flags, ExceptionFlags.severe);
    else
        DecimalControl.raiseFlags(flags);
    return result;
}

/// format, toString()
version(D_BetterC) {}
else
{
    unittest
    {
        static struct S
        {
            string fmt;
            string v;
            string expected;
            string line;
        }

        import std.format : format;
        import std.conv : to;

        static string callerLine(int line = __LINE__) nothrow pure @safe
        {
            return line.to!string();
        }

        static double toDouble(const(char)[] s)
        {
            // Special try construct for grep
            try {
                return s.to!double();
            } catch (Exception) return double.nan;
        }

        static void checkResult(const ref S s, string result)
        {
            string resultStd = format(s.fmt, toDouble(s.v));
            assert(result == s.expected,
                "fmt: '" ~ s.fmt ~ "', value: '" ~ s.v ~ "', case-line: " ~ s.line ~
                "\nresult: '" ~ result ~ "'" ~
                "\nexpect: '" ~ s.expected ~ "'" ~
                "\nstandd: '" ~ resultStd ~ "'");
        }

        S[] testf = [
            S("%0.7f", "1.234567", "1.2345670", callerLine),
            S("%0.6f", "1.234567", "1.234567", callerLine),
            S("%0.5f", "1.234567", "1.23457", callerLine),
            S("%0.4f", "1.234567", "1.2346", callerLine),
            S("%0.3f", "1.234567", "1.235", callerLine),
            S("%0.2f", "1.234567", "1.23", callerLine),
            S("%0.1f", "1.234567", "1.2", callerLine),
            S("%0.0f", "1.234567", "1", callerLine),
            S("%+0.1f", "1.234567", "+1.2", callerLine),
            S("% 0.1f", "1.234567", " 1.2", callerLine),
            S("%8.2f", "1.234567", "    1.23", callerLine),
            S("%+8.2f", "1.234567", "   +1.23", callerLine),
            S("% 8.2f", "1.234567", "    1.23", callerLine),
            S("%-8.2f", "1.234567", "1.23    ", callerLine),
            S("%+0.1f", "-1.234567", "-1.2", callerLine),
            S("% 0.1f", "-1.234567", "-1.2", callerLine),
            S("%+8.2f", "-1.234567", "   -1.23", callerLine),
            S("%-8.2f", "-1.234567", "-1.23   ", callerLine),
        ];

        foreach (f; testf)
        {
            string result = format(f.fmt, Decimal32(f.v));
            checkResult(f, result);
        }

        S[] tests = [
            S("%+.3e", "0.0", "+0.000e+00", callerLine),
  	        S("%+.3e", "1.0", "+1.000e+00", callerLine),
  	        S("%+.3f", "-1.0", "-1.000", callerLine),
  	        S("%+.3F", "-1.0", "-1.000", callerLine),
  	        S("%+07.2f", "1.0", "+001.00", callerLine),
  	        S("%+07.2f", "-1.0", "-001.00", callerLine),
  	        S("%-07.2f", "1.0", "1.00   ", callerLine),
  	        S("%-07.2f", "-1.0", "-1.00  ", callerLine),
  	        S("%+-07.2f", "1.0", "+1.00  ", callerLine),
  	        S("%+-07.2f", "-1.0", "-1.00  ", callerLine),
  	        S("%-+07.2f", "1.0", "+1.00  ", callerLine),
  	        S("%-+07.2f", "-1.0", "-1.00  ", callerLine),
  	        S("%+10.2f", "+1.0", "     +1.00", callerLine),
  	        S("%+10.2f", "-1.0", "     -1.00", callerLine),
  	        S("% .3E", "-1.0", "-1.000E+00", callerLine),
  	        S("% .3e", "1.0", " 1.000e+00", callerLine),
  	        S("%+.3g", "0.0", "+0", callerLine),
  	        S("%+.3g", "1.0", "+1", callerLine),
  	        S("%+.3g", "-1.0", "-1", callerLine),
  	        S("% .3g", "-1.0", "-1", callerLine),
  	        S("% .3g", "1.0", " 1", callerLine),
  	        S("%a", "1", "0x1p+0", callerLine),
  	        S("%#g", "1e-32", "1.00000e-32", callerLine),
  	        S("%#g", "-1.0", "-1.00000", callerLine),
  	        S("%#g", "1.1", "1.10000", callerLine),
  	        S("%#g", "123456.0", "123456.", callerLine),
  	        S("%#g", "1234567.0", "1.23457e+06", callerLine),
  	        S("%#g", "1230000.0", "1.23000e+06", callerLine),
  	        S("%#g", "1000000.0", "1.00000e+06", callerLine),
  	        S("%#.0f", "1.0", "1.", callerLine),
  	        S("%#.0e", "1.0", "1.e+00", callerLine),
  	        S("%#.0g", "1.0", "1.", callerLine),
  	        S("%#.0g", "1100000.0", "1.e+06", callerLine),
  	        S("%#.4f", "1.0", "1.0000", callerLine),
  	        S("%#.4e", "1.0", "1.0000e+00", callerLine),
  	        S("%#.4g", "1.0", "1.000", callerLine),
  	        S("%#.4g", "100000.0", "1.000e+05", callerLine),
  	        S("%#.0f", "123.0", "123.", callerLine),
  	        S("%#.0e", "123.0", "1.e+02", callerLine),
  	        S("%#.0g", "123.0", "1.e+02", callerLine),
  	        S("%#.4f", "123.0", "123.0000", callerLine),
  	        S("%#.4e", "123.0", "1.2300e+02", callerLine),
  	        S("%#.4g", "123.0", "123.0", callerLine),
  	        S("%#.4g", "123000.0", "1.230e+05", callerLine),
  	        S("%#9.4g", "1.0", "    1.000", callerLine),
  	        S("%.4a", "1", "0x1p+0", callerLine),
  	        S("%.4a", "-1", "-0x1p+0", callerLine),
  	        S("%f", "+inf", "inf", callerLine),
  	        S("%.1f", "-inf", "-inf", callerLine),
  	        S("% f", "nan", " nan", callerLine), //S("% f", "$(B NaN)", " nan", callerLine),
  	        S("%20f", "+inf", "                 inf", callerLine),
  	        S("% 20F", "+inf", "                 INF", callerLine),
  	        S("% 20e", "-inf", "                -inf", callerLine),
  	        S("%+20E", "-inf", "                -INF", callerLine),
  	        S("% +20g", "-Inf", "                -inf", callerLine),
  	        S("%+-20G", "+inf", "+INF                ", callerLine),
  	        S("%20e", "nan", "                 nan", callerLine), // S("%20e", "$(B NaN)", "                 nan", callerLine),
  	        S("% +20E", "NAN", "                +NAN", callerLine), // S("% +20E", "$(B NaN)", "                +NAN", callerLine),
  	        S("% -20g", "nan", " nan                ", callerLine), // S("% -20g", "$(B NaN)", " nan                ", callerLine),
  	        S("%+-20G", "NAN", "+NAN                ", callerLine), // S("%+-20G", "$(B NaN)", "+NAN                ", callerLine),
  	        S("%+020e", "+inf", "                +inf", callerLine),
  	        S("%-020f", "-inf", "-inf                ", callerLine),
  	        S("%-020E", "NAN", "NAN                 ", callerLine), // S("%-020E", "$(B NaN)", "NAN                 ", callerLine),
            S("%e", "1.0", "1.000000e+00", callerLine),
  	        S("%e", "1234.5678e3", "1.234568e+06", callerLine),
  	        S("%e", "1234.5678e-8", "1.234568e-05", callerLine),
  	        S("%e", "-7.0", "-7.000000e+00", callerLine),
  	        S("%e", "-1e-9", "-1.000000e-09", callerLine),
  	        S("%f", "1234.567e2", "123456.7", callerLine),
  	        S("%f", "1234.5678e-8", "0.000012", callerLine),
  	        S("%f", "-7.0", "-7.0", callerLine),
  	        S("%f", "-1e-9", "-0.0", callerLine),
  	        S("%g", "1234.5678e3", "1.23457e+06", callerLine),
  	        S("%g", "1234.5678e-8", "1.23457e-05", callerLine),
  	        S("%g", "-7.0", "-7", callerLine),
  	        S("%g", "-1e-9", "-1e-09", callerLine),
  	        S("%E", "1.0", "1.000000E+00", callerLine),
  	        S("%E", "1234.5678e3", "1.234568E+06", callerLine),
  	        S("%E", "1234.5678e-8", "1.234568E-05", callerLine),
  	        S("%E", "-7.0", "-7.000000E+00", callerLine),
  	        S("%E", "-1e-9", "-1.000000E-09", callerLine),
  	        S("%G", "1234.5678e3", "1.23457E+06", callerLine),
  	        S("%G", "1234.5678e-8", "1.23457E-05", callerLine),
  	        S("%G", "-7.0", "-7", callerLine),
  	        S("%G", "-1e-9", "-1E-09", callerLine),
  	        S("%20.6e", "1.2345e3", "        1.234500e+03", callerLine),
  	        S("%20.6e", "1.2345e-3", "        1.234500e-03", callerLine),
  	        S("%20e", "1.2345e3", "        1.234500e+03", callerLine),
  	        S("%20e", "1.2345e-3", "        1.234500e-03", callerLine),
  	        S("%20.8e", "1.2345e3", "      1.23450000e+03", callerLine),
  	        S("%20f", "1.23456789e3", "            1234.568", callerLine),
  	        S("%20f", "1.23456789e-3", "            0.001235", callerLine),
  	        S("%20f", "12345678901.23456789", "       12345680000.0", callerLine),
  	        S("%-20f", "1.23456789e3", "1234.568            ", callerLine),
            S("%20.8f", "1.23456789e3", "       1234.56800000", callerLine),
            S("%20.8f", "1.23456789e-3", "          0.00123457", callerLine),
            S("%g", "1.23456789e3", "1234.57", callerLine),
            S("%g", "1.23456789e-3", "0.00123457", callerLine),
            S("%g", "1.23456789e20", "1.23457e+20", callerLine),
            S("%.2f", "1.0", "1.00", callerLine),
  	        S("%.2f", "-1.0", "-1.00", callerLine),
  	        S("% .2f", "1.0", " 1.00", callerLine),
  	        S("% .2f", "-1.0", "-1.00", callerLine),
  	        S("%+.2f", "1.0", "+1.00", callerLine),
  	        S("%+.2f", "-1.0", "-1.00", callerLine),
  	        S("%7.2f", "1.0", "   1.00", callerLine),
  	        S("%7.2f", "-1.0", "  -1.00", callerLine),
  	        S("% 7.2f", "1.0", "   1.00", callerLine),
  	        S("% 7.2f", "-1.0", "  -1.00", callerLine),
  	        S("%+7.2f", "1.0", "  +1.00", callerLine),
  	        S("%+7.2f", "-1.0", "  -1.00", callerLine),
  	        S("% +7.2f", "1.0", "  +1.00", callerLine),
  	        S("% +7.2f", "-1.0", "  -1.00", callerLine),
  	        S("%07.2f", "1.0", "0001.00", callerLine),
  	        S("%07.2f", "-1.0", "-001.00", callerLine),
  	        S("% 07.2f", "1.0", " 001.00", callerLine),
  	        S("% 07.2f", "-1.0", "-001.00", callerLine),
  	        S("%+07.2f", "1.0", "+001.00", callerLine),
  	        S("%+07.2f", "-1.0", "-001.00", callerLine),
  	        S("% +07.2f", "1.0", "+001.00", callerLine),
  	        S("% +07.2f", "-1.0", "-001.00", callerLine),
        ];

        foreach (s; tests)
        {
            string result = Decimal32(s.v).toString(s.fmt);
            checkResult(s, result);
        }
    }
}

/* ****************************************************************************************************************** */
/* DECIMAL TO DECIMAL CONVERSION                                                                                      */
/* ****************************************************************************************************************** */

ExceptionFlags decimalToDecimal(D1, D2)(const auto ref D1 source, out D2 target,
    const(int) precision, const(RoundingMode) mode) @nogc nothrow pure @safe
if (isDecimal!(D1, D2))
{
    DataType!(D1.sizeof) cx; int ex; bool sx;
    final switch (fastDecode(source, cx, ex, sx))
    {
        case FastClass.finite:
            static if (D2.sizeof == D1.sizeof)
            {
                target.data = source.data;
                return ExceptionFlags.none;
            }
            else
                return target.adjustedPack(cx, ex, sx, precision, mode);
        case FastClass.zero:
            target = sx ? -D2.zero : D2.zero;
            return ExceptionFlags.none;
        case FastClass.infinite:
            target = sx ? -D2.infinity : D2.infinity;
            return ExceptionFlags.none;
        case FastClass.quietNaN:
            target = sx ? -D2.nan : D2.nan;
            return ExceptionFlags.none;
        case FastClass.signalingNaN:
            target = sx ? -D2.nan : D2.nan;
            return ExceptionFlags.invalidOperation;
    }
}

ExceptionFlags decimalToUnsigned(D, T)(const auto ref D source, out T target, const(RoundingMode) mode)
if (isDecimal!D && isUnsigned!T)
{
    alias U = CommonStorage!(D, T);
    U cx; int ex; bool sx;
    final switch (fastDecode(source, cx, ex, sx))
    {
        case FastClass.finite:
            auto flags = coefficientAdjust(cx, ex, 0, 0, U(T.max), sx, mode);
            if (flags & ExceptionFlags.overflow)
            {
                target = T(1) << (T.sizeof * 8 - 1);
                flags = ExceptionFlags.overflow | ExceptionFlags.invalidOperation;
            }
            else if (flags & ExceptionFlags.underflow)
                target = 0;
            else if (sx)
            {
                target = T(1) << (T.sizeof * 8 - 1);
                return ExceptionFlags.overflow | ExceptionFlags.invalidOperation;
            }
            else
                target = cast(T)cx;
            return flags;
        case FastClass.zero:
            target = 0;
            return ExceptionFlags.none;
        case FastClass.infinite:
            target = T(1) << (T.sizeof * 8 - 1);
            return ExceptionFlags.overflow | ExceptionFlags.invalidOperation;
        case FastClass.quietNaN:
        case FastClass.signalingNaN:
            target = T(1) << (T.sizeof * 8 - 1);
            return ExceptionFlags.invalidOperation;
    }
}

ExceptionFlags decimalToSigned(D, T)(const auto ref D source, out T target, const(RoundingMode) mode)
if (isDecimal!D && isSigned!T)
{
    alias U = CommonStorage!(D, T);
    U cx; int ex; bool sx;
    final switch (fastDecode(source, cx, ex, sx))
    {
        case FastClass.finite:
            const U max = sx ? unsign!U(T.min) : unsign!U(T.max);
            auto flags = coefficientAdjust(cx, ex, 0, 0, max, sx, mode);
            if (flags & ExceptionFlags.overflow)
            {
                target = T.min;
                flags = ExceptionFlags.overflow | ExceptionFlags.invalidOperation;
            }
            else if (flags & ExceptionFlags.underflow)
                target = 0;
            else
                target = sign!T(cx, sx);
            return flags;
        case FastClass.zero:
            target = 0;
            return ExceptionFlags.none;
        case FastClass.infinite:
            target = T.min;
            return ExceptionFlags.overflow | ExceptionFlags.invalidOperation;
        case FastClass.quietNaN:
        case FastClass.signalingNaN:
            target = T.min;
            return ExceptionFlags.invalidOperation;
    }
}

ExceptionFlags decimalToFloat(D, T)(const auto ref D source, out T target, const(RoundingMode) mode)
if (isDecimal!D && isFloatingPoint!T)
{
    DataType!(D.sizeof) cx; int ex; bool sx;
    final switch (fastDecode(source, cx, ex, sx))
    {
        case FastClass.finite:
//    s_maxFloat128     = "3.402823466385288598117041834845169e+0038",
//    s_minFloat128     = "1.401298464324817070923729583289916e-0045",
//    s_maxDouble128    = "1.797693134862315708145274237317043e+0308",
//    s_minDouble128    = "4.940656458412465441765687928682213e-0324",
//    s_maxReal128      = "1.189731495357231765021263853030970e+4932",
//    s_minReal128      = "3.645199531882474602528405933619419e-4951",

            alias UT = Unqual!T;
            static if (is(UT == float) ||
                       (is(UT == double) && D.sizeof > 4) ||
                       (is(UT == real) && real.mant_dig == 64 && D.sizeof > 8) ||
                       (is(UT == real) && real.mant_dig != 64 && D.sizeof > 4))
            {
                static if (is(T == float))
                {
                    const c1 = decimalCmp(fabs(source), Decimal128.maxFloat);
                    const c2 = decimalCmp(fabs(source), Decimal128.minFloat);
                }
                else static if (is(T == real) && (real.mant_dig == 64))
                {
                    const c1 = decimalCmp(fabs(source), Decimal128.maxReal);
                    const c2 = decimalCmp(fabs(source), Decimal128.minReal);
                }
                else
                {
                    const c1 = decimalCmp(fabs(source), Decimal128.maxDouble);
                    const c2 = decimalCmp(fabs(source), Decimal128.minDouble);
                }

                if (c1 > 0)
                {
                    target = sx ? -T.infinity: T.infinity;
                    return ExceptionFlags.overflow;
                }

                if (c2 < 0)
                {
                    target = sx ? -0.0 : +0.0;
                    return ExceptionFlags.underflow | ExceptionFlags.inexact;
                }

                if (c1 == 0)
                {
                    target = sx ? -T.max: T.max;
                    return ExceptionFlags.inexact;
                }

                if (c2 == 0)
                {
                    target = (sx ? -T.min_normal : T.min_normal) * T.epsilon;
                    return ExceptionFlags.inexact;
                }
            }

            ExceptionFlags flags;
            static if (is(D: Decimal128))
                flags = coefficientAdjust(cx, ex, uint128(ulong.max), sx, mode);
            ulong m = cvt!ulong(cx);
            final switch (mode)
            {
                case RoundingMode.tiesToAway:
                    flags |= exp10to2!(RoundingMode.tiesToAway)(m, ex, sx);
                    break;
                case RoundingMode.tiesToEven:
                    flags |= exp10to2!(RoundingMode.tiesToEven)(m, ex, sx);
                    break;
                case RoundingMode.towardNegative:
                    flags |= exp10to2!(RoundingMode.towardNegative)(m, ex, sx);
                    break;
                case RoundingMode.towardPositive:
                    flags |= exp10to2!(RoundingMode.towardPositive)(m, ex, sx);
                    break;
                case RoundingMode.towardZero:
                    flags |= exp10to2!(RoundingMode.towardZero)(m, ex, sx);
                    break;
            }

            // synchronized - No need to sync since thread local var
            {
                FloatingPointControl fpctrl;
                auto savedExceptions = fpctrl.enabledExceptions;
                fpctrl.disableExceptions(FloatingPointControl.allExceptions);
                const savedMode = fpctrl.rounding;
                switch (mode)
                {
                    case RoundingMode.tiesToAway:
                    case RoundingMode.tiesToEven:
                        fpctrl.rounding = FloatingPointControl.roundToNearest;
                        break;
                    case RoundingMode.towardNegative:
                        fpctrl.rounding = FloatingPointControl.roundDown;
                        break;
                    case RoundingMode.towardPositive:
                        fpctrl.rounding = FloatingPointControl.roundUp;
                        break;
                    case RoundingMode.towardZero:
                        fpctrl.rounding = FloatingPointControl.roundToZero;
                        break;
                    default:
                        break;
                }
                resetIeeeFlags();

                real r = m;
                if (sx)
                    r = -r;
                target = ldexp(r, ex);

                if (ieeeFlags.inexact)
                    flags |= ExceptionFlags.inexact;
                if (ieeeFlags.underflow)
                    flags |= ExceptionFlags.underflow;
                if (ieeeFlags.overflow)
                    flags |= ExceptionFlags.overflow;
                if (ieeeFlags.invalid)
                    flags |= ExceptionFlags.invalidOperation;
                if (ieeeFlags.divByZero)
                    flags |= ExceptionFlags.divisionByZero;

                fpctrl.enableExceptions(savedExceptions);
            }

            return flags;
        case FastClass.zero:
            target = sx ? -0.0: 0.0;
            return ExceptionFlags.none;
        case FastClass.infinite:
            target = sx ? -T.infinity : T.infinity;
            return ExceptionFlags.none;
        case FastClass.quietNaN:
        case FastClass.signalingNaN:
            target = T.nan;
            return ExceptionFlags.none;
    }
}

/* ****************************************************************************************************************** */
/* DECIMAL ARITHMETIC                                                                                      */
/* ****************************************************************************************************************** */

template CommonStorage(D1, D2)
if (isDecimal!(D1, D2))
{
    static if (D1.sizeof >= D2.sizeof)
        alias CommonStorage = DataType!(D1.sizeof);
    else
        alias CommonStorage = DataType!(D2.sizeof);
}

template CommonStorage(D, I)
if (isDecimal!D && isIntegral!I)
{
    static if (D.sizeof >= I.sizeof)
        alias CommonStorage = DataType!(D.sizeof);
    else
        alias CommonStorage = Unsigned!I;
}

template CommonStorage(D, F)
if (isDecimal!D && isFloatingPoint!F)
{
    alias UF = Unqual!F;
    static if (is(UF == float) || is(UF == double))
        alias CommonStorage = DataType!(D.sizeof);
    else
        alias CommonStorage = CommonStorage!(D, ulong);
}

@safe pure nothrow @nogc
D canonical(D)(const auto ref D x)
if (isDecimal!D)
{
    Unqual!D result = x;
    canonicalize(result);
    return x;
}

@safe pure nothrow @nogc
void canonicalize(D)(ref D x)
if (isDecimal!D)
{
    if ((x.data & D.MASK_INF) == D.MASK_INF)
    {
        if ((x.data & D.MASK_QNAN) == D.MASK_QNAN)
            x.data &= D.MASK_SNAN | D.MASK_SGN | D.MASK_PAYL;
        else
            x.data &= D.MASK_INF | D.MASK_SGN;
    }
    else if ((x.data & D.MASK_EXT) == D.MASK_EXT &&
             (((x.data & D.MASK_COE2) | D.MASK_COEX) > D.COEF_MAX))
        x.data &= D.MASK_ZERO | D.MASK_SGN;
    else if ((x.data & D.MASK_COE1) == 0U)
        x.data &= D.MASK_ZERO | D.MASK_SGN;
}

@safe pure nothrow @nogc
void unsignalize(D)(ref D x)
if (isDecimal!D)
{
    x.data &= ~D.MASK_SNANBIT;
}

@safe pure nothrow @nogc
DecimalClass decimalDecode(D, T)(const auto ref D x, out T cx, out int ex, out bool sx)
if (isDecimal!D && is(T: DataType!(D.sizeof)))
{
    sx = cast(bool)(x.data & D.MASK_SGN);

    if ((x.data & D.MASK_INF) == D.MASK_INF)
    {
        if ((x.data & D.MASK_QNAN) == D.MASK_QNAN)
        {
            if ((x.data & D.MASK_SNAN) == D.MASK_SNAN)
                return DecimalClass.signalingNaN;
            else
                return DecimalClass.quietNaN;
        }
        else
            return sx ? DecimalClass.negativeInfinity : DecimalClass.positiveInfinity;
    }
    else if ((x.data & D.MASK_EXT) == D.MASK_EXT)
    {
        cx = (x.data & D.MASK_COE2) | D.MASK_COEX;
        if (cx > D.COEF_MAX)
        {
            return sx ? DecimalClass.negativeZero : DecimalClass.positiveZero;
        }
        ex = cast(uint)((x.data & D.MASK_EXP2) >>> D.SHIFT_EXP2) - D.EXP_BIAS;
    }
    else
    {
        cx = x.data & D.MASK_COE1;
        if (cx == 0U || cx > D.COEF_MAX)
        {
            ex = 0;
            return sx ? DecimalClass.negativeZero : DecimalClass.positiveZero;
        }
        ex = cast(uint)((x.data & D.MASK_EXP1) >>> D.SHIFT_EXP1) - D.EXP_BIAS;
    }

    if (ex + D.EXP_BIAS < D.PRECISION - 1)
    {
        if (prec(cx) < D.PRECISION - ex + D.EXP_BIAS)
            return sx ? DecimalClass.negativeSubnormal : DecimalClass.positiveSubnormal;
    }
    return sx ? DecimalClass.negativeNormal : DecimalClass.positiveNormal;
}

@safe pure nothrow @nogc
FastClass fastDecode(D, T)(const auto ref D x, out T cx, out int ex, out bool sx)
if ((is(D: Decimal32) || is(D: Decimal64)) && isAnyUnsignedBit!T)
{
    static assert(T.sizeof >= D.sizeof);

    sx = cast(bool)(x.data & D.MASK_SGN);

    if ((x.data & D.MASK_INF) == D.MASK_INF)
    {
        ex = 0;
        if ((x.data & D.MASK_QNAN) == D.MASK_QNAN)
        {
            cx = x.data & D.MASK_PAYL;
            if (cx > D.PAYL_MAX)
                cx = 0U;
            if ((x.data & D.MASK_SNAN) == D.MASK_SNAN)
                return FastClass.signalingNaN;
            else
                return FastClass.quietNaN;
        }
        else
            return FastClass.infinite;
    }
    else if ((x.data & D.MASK_EXT) == D.MASK_EXT)
    {
        cx = (x.data & D.MASK_COE2) | D.MASK_COEX;
        if (cx > D.COEF_MAX)
            cx = 0U;
        ex = cast(uint)((x.data & D.MASK_EXP2) >>> D.SHIFT_EXP2) - D.EXP_BIAS;
    }
    else
    {
        cx = x.data & D.MASK_COE1;
        ex = cast(uint)((x.data & D.MASK_EXP1) >>> D.SHIFT_EXP1) - D.EXP_BIAS;
    }

    return cx == 0U ? FastClass.zero : FastClass.finite;
}

@safe pure nothrow @nogc
FastClass fastDecode(D, T)(const auto ref D x, out T cx, out int ex, out bool sx)
if (is(D: Decimal128) && isAnyUnsignedBit!T)
{
    static assert(T.sizeof >= D.sizeof);

    sx = cast(bool)(x.data.hi & D.MASK_SGN.hi);

    if ((x.data.hi & D.MASK_INF.hi) == D.MASK_INF.hi)
    {
        ex = 0;
        if ((x.data.hi & D.MASK_QNAN.hi) == D.MASK_QNAN.hi)
        {
            cx = x.data & D.MASK_PAYL;
            if (cx > D.PAYL_MAX)
                cx = 0U;
            if ((x.data.hi & D.MASK_SNAN.hi) == D.MASK_SNAN.hi)
                return FastClass.signalingNaN;
            else
                return FastClass.quietNaN;
        }
        else
            return FastClass.infinite;
    }
    else if ((x.data.hi & D.MASK_EXT.hi) == D.MASK_EXT.hi)
    {
        cx = 0U;
        ex = cast(uint)((x.data.hi & D.MASK_EXP2.hi) >>> (D.SHIFT_EXP2 - 64)) - D.EXP_BIAS;
    }
    else
    {
        cx = x.data & D.MASK_COE1;
        if (cx > D.COEF_MAX)
            cx = 0U;
        ex = cast(uint)((x.data.hi & D.MASK_EXP1.hi) >>> (D.SHIFT_EXP1 - 64)) - D.EXP_BIAS;
    }

    return cx == 0U ? FastClass.zero : FastClass.finite;
}

@safe pure nothrow @nogc
FastClass fastDecode(F, T)(const auto ref F x, out T cx, out int ex, out bool sx,
    const(RoundingMode) mode, out ExceptionFlags flags)
if (isFloatingPoint!F && isAnyUnsignedBit!T)
{
    alias UF = Unqual!F;
    bool nan, inf;
    static if (is(UF == float))
    {
        uint m;
        sx = funpack(x, ex, m, inf, nan);
    }
    else static if (is(UF == real) && real.mant_dig == 64)
    {
        ulong m;
        sx = runpack(x, ex, m, inf, nan);
    }
    else
    {
        ulong m;
        sx = dunpack(cast(double)x, ex, m, inf, nan);
    }

    if (x == 0.0)
        return FastClass.zero;

    if (inf)
        return FastClass.infinite;

    if (nan)
    {
        cx = cvt!T(m);
        return FastClass.quietNaN;
    }

    static if (is(UF == float) && T.sizeof > uint.sizeof)
        alias U = uint;
    else static if (is(UF == double) && T.sizeof > ulong.sizeof)
        alias U = ulong;
    else static if (is(UF == real) && T.sizeof > uint128.sizeof)
        alias U = uint128;
    else static if (T.sizeof < typeof(m).sizeof)
        alias U = typeof(m);
    else
        alias U = T;

    U u = m;

    final switch (mode)
    {
        case RoundingMode.tiesToAway:
            flags = exp2to10!(RoundingMode.tiesToAway)(u, ex, sx);
            break;
        case RoundingMode.tiesToEven:
            flags = exp2to10!(RoundingMode.tiesToEven)(u, ex, sx);
            break;
        case RoundingMode.towardZero:
            flags = exp2to10!(RoundingMode.towardZero)(u, ex, sx);
            break;
        case RoundingMode.towardNegative:
            flags = exp2to10!(RoundingMode.towardNegative)(u, ex, sx);
            break;
        case RoundingMode.towardPositive:
            flags = exp2to10!(RoundingMode.towardPositive)(u, ex, sx);
            break;
    }

    static if (T.sizeof < U.sizeof)
    {
        flags |= coefficientAdjust(u, ex, cvt!U(T.max), sx, mode);
    }

    cx = cvt!T(u);
    return cx ? FastClass.finite : FastClass.zero;
}

int realFloatPrecision(F)(const(int) precision) @nogc nothrow pure @safe
{
    alias UF = Unqual!F;
    static if (is(UF == float))
        return precision == 0 ? 9 : (precision > 9 ? 9 : precision);
    else static if (is(UF == double))
        return precision == 0 ? 17 : (precision > 17 ? 17 : precision);
    else
        return precision == 0 ? 21 : (precision > 21 ? 21 : precision);
}

version(none)
struct Constants(T)
{
    static if (is(T:uint))
    {
        enum uint       c1_2π       = 1591549431U;
        enum int        e1_2π       = -10;
        enum uint       c2π         = 628318531U;
        enum int        e2π         = -8;
        enum uint       c2_π        = 636619772U;
        enum int        e2_π        = -9;
        enum uint       cπ_2        = 1570796327U;
        enum int        eπ_2        = -9;
        enum uint       chalf       = 5;
        enum int        ehalf       = -1;
        enum uint       cthird      = 3333333333;
        enum int        ethird      = -10;
        enum uint       ce          = 2718281828U;
        enum int        ee          = -9;
        enum uint       cln10       = 2302585093U;
        enum int        eln10       = -9;
    }
    else static if (is(T:ulong))
    {
        enum ulong      c1_2π       = 15915494309189533577UL;
        enum int        e1_2π       = -20;
        enum ulong      c2π         = 6283185307179586477UL;
        enum int        e2π         = -18;
        enum ulong      c2_π        = 6366197723675813431UL;
        enum int        e2_π        = -19;
        enum ulong      cπ_2        = 15707963267948966192UL;
        enum int        eπ_2        = -19;
        enum ulong      chalf       = 5;
        enum int        ehalf       = -1;
        enum ulong      cthird      = 3333333333333333333UL;
        enum int        ethird      = -19;
        enum ulong      ce          = 2718281828459045235UL;
        enum int        ee          = -18;
        enum ulong      cln10       = 2302585092994045684UL;
        enum int        eln10       = -18;
    }
    else static if (is(T:uint128))
    {
        static immutable uint128    c1_2π       = uint128("159154943091895335768883763372514362034");
        enum int        e1_2π       = -39;
        static immutable uint128    c2π         = uint128("62831853071795864769252867665590057684");
        enum int        e2π         = -37;
        static immutable uint128    c2_π        = uint128("63661977236758134307553505349005744814");
        enum int        e2_π        = -38;
        static immutable uint128    cπ_2        = uint128("157079632679489661923132169163975144210");
        enum int        eπ_2        = -38;
        enum uint128    chalf       = 5U;
        enum int        ehalf       = -1;
        static immutable uint128    cthird      = uint128("333333333333333333333333333333333333333");
        enum int        ethird      = -39;
        static immutable uint128    ce          = uint128("271828182845904523536028747135266249776");
        enum int        ee          = -38;
        static immutable uint128    cln10       = uint128("230258509299404568401799145468436420760");
        enum int        eln10       = -38;

        version(ShowEnumDecBytes)
        unittest
        {
            import std.stdio;
            scope (failure) assert(0, "Assume nothrow failed");

            ubyte[16] b128;
            writeln("128 c1_2π: ", c1_2π.toBigEndianBytes(b128[]));
            writeln("128 c2π: ", c2π.toBigEndianBytes(b128[]));
            writeln("128 c2_π: ", c2_π.toBigEndianBytes(b128[]));
            writeln("128 cπ_2: ", cπ_2.toBigEndianBytes(b128[]));
            writeln("128 cthird: ", cthird.toBigEndianBytes(b128[]));
            writeln("128 ce: ", ce.toBigEndianBytes(b128[]));
            writeln("128 cln10: ", cln10.toBigEndianBytes(b128[]));
        }
    }
    else static if (is(T:uint256))
    {
        static immutable uint256    c1_2π       = uint256("15915494309189533576888376337251436203445964574045644874766734405889679763423");
        enum int        e1_2π       = -77;
        static immutable uint256    c2π         = uint256("62831853071795864769252867665590057683943387987502116419498891846156328125724");
        enum int        e2π         = -76;
        static immutable uint256    c2_π        = uint256("63661977236758134307553505349005744813783858296182579499066937623558719053691");
        enum int        e2_π        = -77;
        static immutable uint256    cπ_2        = uint256("15707963267948966192313216916397514420985846996875529104874722961539082031431");
        enum int        eπ_2        = -76;
        enum uint256    chalf       = 5U;
        enum int        ehalf       = -1;
        static immutable uint256    cthird      = uint256("33333333333333333333333333333333333333333333333333333333333333333333333333333");
        enum int        ethird      = -77;
        static immutable uint256    ce          = uint256("27182818284590452353602874713526624977572470936999595749669676277240766303536");
        enum int        ee          = -76;
        static immutable uint256    cln10       = uint256("23025850929940456840179914546843642076011014886287729760333279009675726096774");
        enum int        eln10       = -76;

        version(ShowEnumDecBytes)
        unittest
        {
            import std.stdio;
            scope (failure) assert(0, "Assume nothrow failed");

            ubyte[32] b256;
            writeln("256 c1_2π: ", c1_2π.toBigEndianBytes(b256[]));
            writeln("256 c2π: ", c2π.toBigEndianBytes(b256[]));
            writeln("256 c2_π: ", c2_π.toBigEndianBytes(b256[]));
            writeln("256 cπ_2: ", cπ_2.toBigEndianBytes(b256[]));
            writeln("256 cthird: ", cthird.toBigEndianBytes(b256[]));
            writeln("256 ce: ", ce.toBigEndianBytes(b256[]));
            writeln("256 cln10: ", cln10.toBigEndianBytes(b256[]));
        }
    }
    else
        static assert(0);
}

template SEnumBytes(int Bytes)
{
    static if (Bytes == 4)
    {
        static immutable s_E = cast(const(ubyte)[])[47, 169, 122, 74];
        static immutable s_PI = cast(const(ubyte)[])[47, 175, 239, 217];
        static immutable s_LN10 = cast(const(ubyte)[])[47, 163, 34, 121];
        static immutable s_LOG2T = cast(const(ubyte)[])[47, 178, 176, 72];
        static immutable s_LOG2E = cast(const(ubyte)[])[47, 150, 3, 135];
        static immutable s_LOG2 = cast(const(ubyte)[])[47, 45, 238, 252];
        static immutable s_LOG10E = cast(const(ubyte)[])[47, 66, 68, 161];
        static immutable s_LN2 = cast(const(ubyte)[])[47, 105, 196, 16];
        static immutable s_pi_2 = cast(const(ubyte)[])[47, 151, 247, 236];
        static immutable s_pi_4 = cast(const(ubyte)[])[47, 119, 215, 158];
        static immutable s_m_1_pi = cast(const(ubyte)[])[47, 48, 145, 251];
        static immutable s_m_2_pi = cast(const(ubyte)[])[47, 97, 35, 246];
        static immutable s_m_2_sqrtpi = cast(const(ubyte)[])[47, 145, 55, 187];
        static immutable s_sqrt2 = cast(const(ubyte)[])[47, 149, 148, 70];
        static immutable s_sqrt1_2 = cast(const(ubyte)[])[47, 107, 229, 92];
        static immutable s_sqrt3 = cast(const(ubyte)[])[47, 154, 109, 211];
        static immutable s_m_sqrt3 = cast(const(ubyte)[])[47, 88, 24, 191];
        static immutable s_pi_3 = cast(const(ubyte)[])[47, 143, 250, 158];
        static immutable s_pi_6 = cast(const(ubyte)[])[47, 79, 229, 20];
        static immutable s_sqrt2_2 = cast(const(ubyte)[])[47, 107, 229, 92];
        static immutable s_sqrt3_2 = cast(const(ubyte)[])[107, 196, 37, 30];
        static immutable s_pi5_6 = cast(const(ubyte)[])[47, 167, 242, 138];
        static immutable s_pi3_4 = cast(const(ubyte)[])[47, 163, 243, 226];
        static immutable s_pi2_3 = cast(const(ubyte)[])[47, 159, 245, 59];
        static immutable s_onethird = cast(const(ubyte)[])[47, 50, 220, 213];
        static immutable s_twothirds = cast(const(ubyte)[])[47, 101, 185, 171];
        static immutable s_n5_6 = cast(const(ubyte)[])[47, 127, 40, 21];
        static immutable s_n1_6 = cast(const(ubyte)[])[47, 25, 110, 107];
        static immutable s_m_1_2pi = cast(const(ubyte)[])[47, 24, 72, 253];
        static immutable s_pi2 = cast(const(ubyte)[])[47, 223, 223, 177];
    }
    else static if (Bytes == 8)
    {
        static immutable s_E = cast(const(ubyte)[])[47, 233, 168, 67, 78, 200, 226, 37];
        static immutable s_PI = cast(const(ubyte)[])[47, 235, 41, 67, 10, 37, 109, 33];
        static immutable s_LN10 = cast(const(ubyte)[])[47, 232, 46, 48, 94, 136, 115, 254];
        static immutable s_LOG2T = cast(const(ubyte)[])[47, 235, 205, 70, 168, 16, 173, 194];
        static immutable s_LOG2E = cast(const(ubyte)[])[47, 229, 32, 31, 157, 110, 112, 131];
        static immutable s_LOG2 = cast(const(ubyte)[])[47, 202, 177, 218, 19, 149, 56, 68];
        static immutable s_LOG10E = cast(const(ubyte)[])[47, 207, 109, 226, 163, 55, 177, 198];
        static immutable s_LN2 = cast(const(ubyte)[])[47, 216, 160, 35, 10, 190, 78, 221];
        static immutable s_pi_2 = cast(const(ubyte)[])[47, 229, 148, 161, 133, 18, 182, 145];
        static immutable s_pi_4 = cast(const(ubyte)[])[47, 219, 231, 39, 153, 93, 144, 211];
        static immutable s_m_1_pi = cast(const(ubyte)[])[47, 203, 79, 2, 244, 241, 222, 83];
        static immutable s_m_2_pi = cast(const(ubyte)[])[47, 214, 158, 5, 233, 227, 188, 165];
        static immutable s_m_2_sqrtpi = cast(const(ubyte)[])[47, 228, 2, 65, 63, 109, 58, 217];
        static immutable s_sqrt2 = cast(const(ubyte)[])[47, 229, 6, 56, 65, 5, 147, 231];
        static immutable s_sqrt1_2 = cast(const(ubyte)[])[47, 217, 31, 25, 69, 27, 227, 131];
        static immutable s_sqrt3 = cast(const(ubyte)[])[47, 230, 39, 74, 129, 30, 57, 237];
        static immutable s_m_sqrt3 = cast(const(ubyte)[])[47, 212, 130, 248, 89, 15, 107, 194];
        static immutable s_pi_3 = cast(const(ubyte)[])[47, 227, 184, 107, 174, 12, 121, 182];
        static immutable s_pi_6 = cast(const(ubyte)[])[47, 210, 154, 26, 102, 62, 96, 141];
        static immutable s_sqrt2_2 = cast(const(ubyte)[])[47, 217, 31, 25, 69, 27, 227, 131];
        static immutable s_sqrt3_2 = cast(const(ubyte)[])[47, 222, 196, 116, 133, 151, 33, 162];
        static immutable s_pi5_6 = cast(const(ubyte)[])[47, 233, 77, 13, 51, 31, 48, 70];
        static immutable s_pi3_4 = cast(const(ubyte)[])[47, 232, 94, 242, 71, 156, 17, 217];
        static immutable s_pi2_3 = cast(const(ubyte)[])[47, 231, 112, 215, 92, 24, 243, 107];
        static immutable s_onethird = cast(const(ubyte)[])[47, 203, 215, 166, 37, 64, 85, 85];
        static immutable s_twothirds = cast(const(ubyte)[])[47, 215, 175, 76, 74, 128, 170, 171];
        static immutable s_n5_6 = cast(const(ubyte)[])[47, 221, 155, 31, 93, 32, 213, 85];
        static immutable s_n1_6 = cast(const(ubyte)[])[47, 197, 235, 211, 18, 160, 42, 171];
        static immutable s_m_1_2pi = cast(const(ubyte)[])[47, 197, 167, 129, 122, 120, 239, 41];
        static immutable s_pi2 = cast(const(ubyte)[])[47, 246, 82, 134, 20, 74, 218, 66];
    }
    else static if (Bytes == 16)
    {
        static immutable s_E = cast(const(ubyte)[])[47, 254, 134, 5, 138, 75, 244, 222, 78, 144, 106, 204, 178, 106, 187, 86];
        static immutable s_PI = cast(const(ubyte)[])[47, 254, 154, 228, 121, 87, 150, 167, 186, 190, 85, 100, 230, 243, 159, 143];
        static immutable s_LN10 = cast(const(ubyte)[])[47, 254, 113, 134, 181, 179, 173, 164, 20, 77, 7, 155, 146, 117, 244, 204];
        static immutable s_LOG2T = cast(const(ubyte)[])[47, 254, 163, 200, 160, 148, 98, 211, 143, 1, 212, 185, 207, 71, 18, 238];
        static immutable s_LOG2E = cast(const(ubyte)[])[47, 254, 71, 33, 95, 23, 166, 85, 227, 137, 147, 211, 222, 131, 75, 164];
        static immutable s_LOG2 = cast(const(ubyte)[])[47, 252, 148, 107, 83, 194, 26, 7, 50, 34, 162, 191, 204, 189, 135, 130];
        static immutable s_LOG10E = cast(const(ubyte)[])[47, 252, 214, 31, 171, 139, 176, 250, 28, 107, 133, 185, 11, 217, 107, 227];
        static immutable s_LN2 = cast(const(ubyte)[])[47, 253, 85, 191, 121, 86, 12, 191, 116, 131, 43, 138, 34, 255, 76, 6];
        static immutable s_pi_2 = cast(const(ubyte)[])[47, 254, 77, 114, 60, 171, 203, 83, 221, 95, 42, 178, 115, 121, 207, 199];
        static immutable s_pi_4 = cast(const(ubyte)[])[47, 253, 131, 59, 47, 90, 248, 163, 82, 219, 213, 124, 65, 97, 14, 229];
        static immutable s_m_1_pi = cast(const(ubyte)[])[47, 252, 156, 240, 91, 34, 90, 23, 191, 203, 190, 12, 236, 151, 165, 175];
        static immutable s_m_2_pi = cast(const(ubyte)[])[47, 253, 57, 224, 182, 68, 180, 47, 127, 151, 124, 25, 217, 47, 75, 94];
        static immutable s_m_2_sqrtpi = cast(const(ubyte)[])[47, 254, 55, 162, 37, 186, 161, 80, 240, 9, 160, 153, 245, 193, 182, 137];
        static immutable s_sqrt2 = cast(const(ubyte)[])[47, 254, 69, 185, 226, 120, 205, 248, 180, 62, 15, 15, 16, 20, 128, 34];
        static immutable s_sqrt1_2 = cast(const(ubyte)[])[47, 253, 92, 161, 108, 92, 5, 219, 133, 54, 75, 75, 80, 102, 128, 170];
        static immutable s_sqrt3 = cast(const(ubyte)[])[47, 254, 85, 101, 141, 255, 250, 80, 117, 24, 247, 247, 126, 151, 83, 80];
        static immutable s_m_sqrt3 = cast(const(ubyte)[])[47, 253, 28, 167, 217, 85, 66, 97, 134, 83, 58, 142, 80, 163, 21, 182];
        static immutable s_pi_3 = cast(const(ubyte)[])[47, 254, 51, 161, 125, 199, 220, 226, 147, 148, 199, 33, 162, 81, 53, 48];
        static immutable s_pi_6 = cast(const(ubyte)[])[47, 253, 2, 39, 116, 231, 80, 108, 225, 231, 227, 168, 43, 150, 9, 238];
        static immutable s_sqrt2_2 = cast(const(ubyte)[])[47, 253, 92, 161, 108, 92, 5, 219, 133, 54, 75, 75, 80, 102, 128, 170];
        static immutable s_sqrt3_2 = cast(const(ubyte)[])[47, 253, 170, 251, 197, 255, 227, 146, 73, 124, 215, 213, 120, 244, 160, 145];
        static immutable s_pi5_6 = cast(const(ubyte)[])[47, 254, 129, 19, 186, 115, 168, 54, 112, 243, 241, 212, 21, 203, 4, 247];
        static immutable s_pi3_4 = cast(const(ubyte)[])[47, 254, 116, 43, 91, 1, 176, 253, 204, 14, 192, 11, 173, 54, 183, 171];
        static immutable s_pi2_3 = cast(const(ubyte)[])[47, 254, 103, 66, 251, 143, 185, 197, 39, 41, 142, 67, 68, 162, 106, 95];
        static immutable s_onethird = cast(const(ubyte)[])[47, 252, 164, 88, 148, 228, 130, 149, 103, 217, 218, 33, 85, 85, 85, 85];
        static immutable s_twothirds = cast(const(ubyte)[])[47, 253, 72, 177, 41, 201, 5, 42, 207, 179, 180, 66, 170, 170, 170, 171];
        static immutable s_n5_6 = cast(const(ubyte)[])[47, 253, 154, 221, 116, 59, 70, 117, 131, 160, 161, 83, 85, 85, 85, 85];
        static immutable s_n1_6 = cast(const(ubyte)[])[47, 252, 82, 44, 74, 114, 65, 74, 179, 236, 237, 16, 170, 170, 170, 171];
        static immutable s_m_1_2pi = cast(const(ubyte)[])[47, 252, 78, 120, 45, 145, 45, 11, 223, 229, 223, 6, 118, 75, 210, 216];
        static immutable s_pi2 = cast(const(ubyte)[])[47, 255, 53, 200, 242, 175, 45, 79, 117, 124, 170, 201, 205, 231, 63, 30];
        static immutable s_maxFloat128 = cast(const(ubyte)[])[48, 74, 167, 197, 171, 159, 85, 155, 61, 7, 200, 75, 93, 204, 99, 241];
        static immutable s_minFloat128 = cast(const(ubyte)[])[47, 164, 69, 22, 223, 138, 22, 254, 99, 213, 183, 26, 180, 153, 54, 60];
        static immutable s_maxDouble128 = cast(const(ubyte)[])[50, 102, 88, 162, 19, 204, 122, 79, 250, 224, 60, 72, 37, 21, 111, 179];
        static immutable s_minDouble128 = cast(const(ubyte)[])[45, 118, 243, 151, 218, 3, 175, 6, 170, 131, 63, 210, 87, 21, 246, 229];
        static immutable s_maxReal128 = cast(const(ubyte)[])[86, 134, 58, 168, 133, 203, 26, 108, 236, 243, 134, 52, 204, 240, 142, 58];
        static immutable s_minReal128 = cast(const(ubyte)[])[9, 80, 179, 184, 226, 237, 169, 26, 35, 45, 217, 80, 16, 41, 120, 219];
    }
}

enum
{
    s_E             = "2.7182818284590452353602874713526625",
    s_PI            = "3.1415926535897932384626433832795029",
    s_LN10          = "2.3025850929940456840179914546843642",
    s_LOG2T         = "3.3219280948873623478703194294893902",
    s_LOG2E         = "1.4426950408889634073599246810018921",
    s_LOG2          = "0.3010299956639811952137388947244930",
    s_LOG10E        = "0.4342944819032518276511289189166051",
    s_LN2           = "0.6931471805599453094172321214581766",

    s_pi_2          = "1.5707963267948966192313216916397514",
    s_pi_4          = "0.7853981633974483096156608458198757",
    s_m_1_pi        = "0.3183098861837906715377675267450287",
    s_m_2_pi        = "0.6366197723675813430755350534900574",
    s_m_2_sqrtpi    = "1.1283791670955125738961589031215452",
    s_sqrt2         = "1.4142135623730950488016887242096981",
    s_sqrt1_2       = "0.7071067811865475244008443621048490",

    s_sqrt3         = "1.7320508075688772935274463415058723",
    s_m_sqrt3       = "0.5773502691896257645091487805019574",
    s_pi_3          = "1.0471975511965977461542144610931676",
    s_pi_6          = "0.5235987755982988730771072305465838",

    s_sqrt2_2       = "0.7071067811865475244008443621048490",
    s_sqrt3_2       = "0.8660254037844386467637231707529361",
    s_pi5_6         = "2.6179938779914943653855361527329190",
    s_pi3_4         = "2.3561944901923449288469825374596271",
    s_pi2_3         = "2.0943951023931954923084289221863352",
    s_onethird      = "0.3333333333333333333333333333333333",
    s_twothirds     = "0.6666666666666666666666666666666667",
    s_n5_6          = "0.8333333333333333333333333333333333",
    s_n1_6          = "0.1666666666666666666666666666666667",
    s_m_1_2pi       = "0.1591549430918953357688837633725144",
    s_pi2           = "6.2831853071795864769252867665590058",

    // Only for Decimal128
    s_maxFloat128   = "3.402823466385288598117041834845169e+0038",
    s_minFloat128   = "1.401298464324817070923729583289916e-0045",
    s_maxDouble128  = "1.797693134862315708145274237317043e+0308",
    s_minDouble128  = "4.940656458412465441765687928682213e-0324",
    s_maxReal128    = "1.189731495357231765021263853030970e+4932",
    s_minReal128    = "3.645199531882474602528405933619419e-4951",
}

version(ShowEnumDecBytes)
unittest
{
    import std.meta : AliasSeq;

    static foreach (D; AliasSeq!(Decimal32, Decimal64, Decimal128))
    {
        {
            static assert(D.E == D.buildin(s_E));
            static assert(D.PI == D.buildin(s_PI));
            static assert(D.LN10 == D.buildin(s_LN10));
            static assert(D.LOG2T == D.buildin(s_LOG2T));
            static assert(D.LOG2E == D.buildin(s_LOG2E));
            static assert(D.LOG2 == D.buildin(s_LOG2));
            static assert(D.LOG10E == D.buildin(s_LOG10E));
            static assert(D.LN2 == D.buildin(s_LN2));

            static assert(D.pi_2 == D.buildin(s_pi_2));
            static assert(D.pi_4 == D.buildin(s_pi_4));
            static assert(D.m_1_pi == D.buildin(s_m_1_pi));
            static assert(D.m_2_pi == D.buildin(s_m_2_pi));
            static assert(D.m_2_sqrtpi == D.buildin(s_m_2_sqrtpi));
            static assert(D.sqrt2 == D.buildin(s_sqrt2));
            static assert(D.sqrt1_2 == D.buildin(s_sqrt1_2));

            static assert(D.sqrt3 == D.buildin(s_sqrt3));
            static assert(D.m_sqrt3 == D.buildin(s_m_sqrt3));
            static assert(D.pi_3 == D.buildin(s_pi_3));
            static assert(D.pi_6 == D.buildin(s_pi_6));

            static assert(D.sqrt2_2 == D.buildin(s_sqrt2_2));
            static assert(D.sqrt3_2 == D.buildin(s_sqrt3_2));
            static assert(D.pi5_6 == D.buildin(s_pi5_6));
            static assert(D.pi3_4 == D.buildin(s_pi3_4));
            static assert(D.pi2_3 == D.buildin(s_pi2_3));
            static assert(D.onethird == D.buildin(s_onethird));
            static assert(D.twothirds == D.buildin(s_twothirds));
            static assert(D.n5_6 == D.buildin(s_n5_6));
            static assert(D.n5_6 == D.buildin(s_n5_6));
            static assert(D.m_1_2pi == D.buildin(s_m_1_2pi));
            static assert(D.pi2 == D.buildin(s_pi2));

            static if (D.sizeof == 16)
            {
                static assert(D.maxFloat == D.buildin(s_maxFloat128));
                static assert(D.minFloat == D.buildin(s_minFloat128));
                static assert(D.maxDouble == D.buildin(s_maxDouble128));
                static assert(D.minDouble == D.buildin(s_minDouble128));
                static assert(D.maxReal == D.buildin(s_maxReal128));
                static assert(D.minReal == D.buildin(s_minReal128));
            }
        }
    }
}

version(ShowEnumDecBytes) version(none)
unittest
{
    import std.meta : AliasSeq;
    import std.stdio;
    scope (failure) assert(0, "Assume nothrow failed");

    static foreach (D; AliasSeq!(Decimal32, Decimal64, Decimal128))
    {
        {
            ubyte[D.sizeof] bytes;
            debug writeln(D.stringof, " enum s_E = cast(const(ubyte)[])", D.E.data.toBigEndianBytes(bytes), ";");
            debug writeln(D.stringof, " enum s_PI = cast(const(ubyte)[])", D.PI.data.toBigEndianBytes(bytes), ";");
            debug writeln(D.stringof, " enum s_LN10 = cast(const(ubyte)[])", D.LN10.data.toBigEndianBytes(bytes), ";");
            debug writeln(D.stringof, " enum s_LOG2T = cast(const(ubyte)[])", D.LOG2T.data.toBigEndianBytes(bytes), ";");
            debug writeln(D.stringof, " enum s_LOG2E = cast(const(ubyte)[])", D.LOG2E.data.toBigEndianBytes(bytes), ";");
            debug writeln(D.stringof, " enum s_LOG2 = cast(const(ubyte)[])", D.LOG2.data.toBigEndianBytes(bytes), ";");
            debug writeln(D.stringof, " enum s_LOG10E = cast(const(ubyte)[])", D.LOG10E.data.toBigEndianBytes(bytes), ";");
            debug writeln(D.stringof, " enum s_LN2 = cast(const(ubyte)[])", D.LN2.data.toBigEndianBytes(bytes), ";");

            debug writeln(D.stringof, " enum s_pi_2 = cast(const(ubyte)[])", D.pi_2.data.toBigEndianBytes(bytes), ";");
            debug writeln(D.stringof, " enum s_pi_4 = cast(const(ubyte)[])", D.pi_4.data.toBigEndianBytes(bytes), ";");
            debug writeln(D.stringof, " enum s_m_1_pi = cast(const(ubyte)[])", D.m_1_pi.data.toBigEndianBytes(bytes), ";");
            debug writeln(D.stringof, " enum s_m_2_pi = cast(const(ubyte)[])", D.m_2_pi.data.toBigEndianBytes(bytes), ";");
            debug writeln(D.stringof, " enum s_m_2_sqrtpi = cast(const(ubyte)[])", D.m_2_sqrtpi.data.toBigEndianBytes(bytes), ";");
            debug writeln(D.stringof, " enum s_sqrt2 = cast(const(ubyte)[])", D.sqrt2.data.toBigEndianBytes(bytes), ";");
            debug writeln(D.stringof, " enum s_sqrt1_2 = cast(const(ubyte)[])", D.sqrt1_2.data.toBigEndianBytes(bytes), ";");

            debug writeln(D.stringof, " enum s_sqrt3 = cast(const(ubyte)[])", D.sqrt3.data.toBigEndianBytes(bytes), ";");
            debug writeln(D.stringof, " enum s_m_sqrt3 = cast(const(ubyte)[])", D.m_sqrt3.data.toBigEndianBytes(bytes), ";");
            debug writeln(D.stringof, " enum s_pi_3 = cast(const(ubyte)[])", D.pi_3.data.toBigEndianBytes(bytes), ";");
            debug writeln(D.stringof, " enum s_pi_6 = cast(const(ubyte)[])", D.pi_6.data.toBigEndianBytes(bytes), ";");

            debug writeln(D.stringof, " enum s_sqrt2_2 = cast(const(ubyte)[])", D.sqrt2_2.data.toBigEndianBytes(bytes), ";");
            debug writeln(D.stringof, " enum s_sqrt3_2 = cast(const(ubyte)[])", D.sqrt3_2.data.toBigEndianBytes(bytes), ";");
            debug writeln(D.stringof, " enum s_pi5_6 = cast(const(ubyte)[])", D.pi5_6.data.toBigEndianBytes(bytes), ";");
            debug writeln(D.stringof, " enum s_pi3_4 = cast(const(ubyte)[])", D.pi3_4.data.toBigEndianBytes(bytes), ";");
            debug writeln(D.stringof, " enum s_pi2_3 = cast(const(ubyte)[])", D.pi2_3.data.toBigEndianBytes(bytes), ";");
            debug writeln(D.stringof, " enum s_onethird = cast(const(ubyte)[])", D.onethird.data.toBigEndianBytes(bytes), ";");
            debug writeln(D.stringof, " enum s_twothirds = cast(const(ubyte)[])", D.twothirds.data.toBigEndianBytes(bytes), ";");
            debug writeln(D.stringof, " enum s_n5_6 = cast(const(ubyte)[])", D.n5_6.data.toBigEndianBytes(bytes), ";");
            debug writeln(D.stringof, " enum s_n1_6 = cast(const(ubyte)[])", D.n1_6.data.toBigEndianBytes(bytes), ";");
            debug writeln(D.stringof, " enum s_m_1_2pi = cast(const(ubyte)[])", D.m_1_2pi.data.toBigEndianBytes(bytes), ";");
            debug writeln(D.stringof, " enum s_pi2 = cast(const(ubyte)[])", D.pi2.data.toBigEndianBytes(bytes), ";");

            static if (D.sizeof == 16)
            {
                debug writeln(D.stringof, " enum s_maxFloat128 = cast(const(ubyte)[])", D.maxFloat.data.toBigEndianBytes(bytes), ";");
                debug writeln(D.stringof, " enum s_minFloat128 = cast(const(ubyte)[])", D.minFloat.data.toBigEndianBytes(bytes), ";");
                debug writeln(D.stringof, " enum s_maxDouble128 = cast(const(ubyte)[])", D.maxDouble.data.toBigEndianBytes(bytes), ";");
                debug writeln(D.stringof, " enum s_minDouble128 = cast(const(ubyte)[])", D.minDouble.data.toBigEndianBytes(bytes), ";");
                debug writeln(D.stringof, " enum s_maxReal128 = cast(const(ubyte)[])", D.maxReal.data.toBigEndianBytes(bytes), ";");
                debug writeln(D.stringof, " enum s_minReal128 = cast(const(ubyte)[])", D.minReal.data.toBigEndianBytes(bytes), ";");
            }
        }
        debug writeln("");
    }
}

//to find mod(10^n/2pi; 1): take digits[n .. n + precision], exponent -n
//example mod(10^3/2pi; 1): 1549430918953357688e-19, precision = 19
//example mod(10^9/2pi; 1): 0918953357688837633e-19, precision = 19 = 918953357688837633[7]e-20
//example mode(10^-8/2pi;1):0000000015915494309e-19, precision = 19 = 15915494309[18953357]e-27
//limit: 9866, that means nmax = 9866 - precision;
//mod(c * 10^n mod 2pi) = frac(c * mod(10^n/2pi; 1)) * 2pi;
//example for Decimal32 -> mod(10^n/2pi; 1) => 19 digits
//   c * mod(10^n/2pi; 1) => 19 + 7 = 26 digits =>
static immutable s_mod_1_2pi =
    "15915494309189533576888376337251436203445964574045644874766734405889679763422653509011380276625308595607284" ~
    "27267579580368929118461145786528779674107316998392292399669374090775730777463969253076887173928962173976616" ~
    "93362390241723629011832380114222699755715940461890086902673956120489410936937844085528723099946443400248672" ~
    "34773945961089832309678307490616698646280469944865218788157478656696424103899587413934860998386809919996244" ~
    "28755851711788584311175187671605465475369880097394603647593337680593024944966353053271567755032203247778163" ~
    "97166022946748119598165840606016803035998133911987498832786654435279755070016240677564388849571310880122199" ~
    "37614768137776473789063306804645797848176131242731406996077502450029775985708905690279678513152521001631774" ~
    "60209248116062405614562031464840892484591914352115754075562008715266068022171591407574745827225977462853998" ~
    "75155329390813981772409358254797073328719040699975907657707849347039358982808717342564036689511662545705943" ~
    "32763126865002612271797115321125995043866794503762556083631711695259758128224941623334314510612353687856311" ~
    "36366921671420697469601292505783360531196085945098395567187099547465104316238155175808394429799709995052543" ~
    "87566129445883306846050785291515141040489298850638816077619699307341038999578691890598093737772061875432227" ~
    "18930136625526123878038753888110681406765434082827852693342679955607079038606035273899624512599574927629702" ~
    "35940955843011648296411855777124057544494570217897697924094903272947702166496035653181535440038406898747176" ~
    "91588763190966506964404776970687683656778104779795450353395758301881838687937766124814953059965580219083598" ~
    "75103512712904323158049871968687775946566346221034204440855497850379273869429353661937782928735937843470323" ~
    "02371458379235571186363419294601831822919641650087830793313534977909974586492902674506098936890945883050337" ~
    "03053805473123215809431976760322831314189809749822438335174356989847501039500683880039786723599608024002739" ~
    "01087495485478792356826113994890326899742708349611492082890377678474303550456845608367147930845672332703548" ~
    "53925562020868393240995622117533183940209707935707749654988086860663609686619670374745421028312192518462248" ~
    "34991161149566556037969676139931282996077608277990100783036002338272987908540238761557445430926011910054337" ~
    "99838904654921248295160707285300522721023601752331317317975931105032815510937391363964530579260718008361795" ~
    "48767246459804739772924481092009371257869183328958862839904358686666397567344514095036373271917431138806638" ~
    "30725923027597345060548212778037065337783032170987734966568490800326988506741791464683508281616853314336160" ~
    "73099514985311981973375844420984165595415225064339431286444038388356150879771645017064706751877456059160871" ~
    "68578579392262347563317111329986559415968907198506887442300575191977056900382183925622033874235362568083541" ~
    "56517297108811721795936832564885187499748708553116598306101392144544601614884527702511411070248521739745103" ~
    "86673640387286009967489317356181207117404788993688865569230784850230570571440636386320236852010741005748592" ~
    "28111572196800397824759530016695852212303464187736504354676464565659719011230847670993097085912836466691917" ~
    "76938791433315566506698132164152100895711728623842607067845176011134508006994768422356989624880515775980953" ~
    "39708085475059753626564903439445420581788643568304200031509559474343925254485067491429086475144230332133245" ~
    "69511634945677539394240360905438335528292434220349484366151466322860247766666049531406573435755301409082798" ~
    "80914786693434922737602634997829957018161964321233140475762897484082891174097478263789918169993948749771519" ~
    "89818726662946018305395832752092363506853889228468247259972528300766856937583659722919824429747406163818311" ~
    "39583067443485169285973832373926624024345019978099404021896134834273613676449913827154166063424829363741850" ~
    "61226108613211998633462847099418399427429559156283339904803821175011612116672051912579303552929241134403116" ~
    "13411249531838592695849044384680784909739828088552970451530539914009886988408836548366522246686240872540140" ~
    "40091178742122045230753347397253814940388419058684231159463227443390661251623931062831953238833921315345563" ~
    "81511752035108745955820112375435976815534018740739434036339780388172100453169182951948795917673954177879243" ~
    "52761740724605939160273228287946819364912894971495343255272359165929807247998580612690073321884452679433504" ~
    "55801952492566306204876616134365339920287545208555344144099051298272745465911813222328405116661565070983755" ~
    "74337295486312041121716380915606161165732000083306114606181280326258695951602463216613857661480471993270777" ~
    "13164412015949601106328305207595834850305079095584982982186740289838551383239570208076397550429225984764707" ~
    "10164269743845043091658645283603249336043546572375579161366324120457809969715663402215880545794313282780055" ~
    "24613208890187421210924489104100521549680971137207540057109634066431357454399159769435788920793425617783022" ~
    "23701148642492523924872871313202176673607566455982726095741566023437874362913210974858971507130739104072643" ~
    "54141797057222654798038151275957912400253446804822026173422990010204830624630337964746781905018118303751538" ~
    "02879523433419550213568977091290561431787879208620574499925789756901849210324206471385191138814756402097605" ~
    "54895793785141404145305151583964282326540602060331189158657027208625026991639375152788736060811455694842103" ~
    "22407772727421651364234366992716340309405307480652685093016589213692141431293713410615715371406203978476184" ~
    "26502978078606266969960809184223476335047746719017450451446166382846208240867359510237130290444377940853503" ~
    "44544263341306263074595138303102293146934466832851766328241515210179422644395718121717021756492196444939653" ~
    "22221876584882445119094013405044321398586286210831793939608443898019147873897723310286310131486955212620518" ~
    "27806349457118662778256598831005351552316659843940902218063144545212129789734471488741258268223860236027109" ~
    "98119152056882347239835801336606837863288679286197323672536066852168563201194897807339584191906659583867852" ~
    "94124187182172798750610394606481958574562006089212284163943738465495899320284812364334661197073243095458590" ~
    "73361878629063185016510626757685121635758869630745199922001077667683094698149756226824347936713108412102195" ~
    "20899481912444048751171059184413990788945577518462161904153093454380280893862807323757861526779711433232419" ~
    "69857805637630180884386640607175368321362629671224260942854011096321826276512011702255292928965559460820493" ~
    "84090690760692003954646191640021567336017909631872891998634341086903200579663710312861235698881764036425254" ~
    "08370981081483519031213186247228181050845123690190646632235938872454630737272808789830041018948591367374258" ~
    "94181240567291912380033063449982196315803863810542457893450084553280313511884341007373060595654437362488771" ~
    "29262898074235390740617869057844431052742626417678300582214864622893619296692992033046693328438158053564864" ~
    "07318444059954968935377318367266131301086235880212880432893445621404797894542337360585063270439981932635916" ~
    "68734194365678390128191220281622950033301223609185875592019590812241536794990954488810997589198908115811635" ~
    "38891633940292372204984837522423620910083409756679171008416795702233178971071029288848970130995339954244153" ~
    "35060625843921452433864640343244065731747755340540448100617761256908474646143297654390000838265211452101623" ~
    "66431119798731902751191441213616962045693602633610235596214046702901215679641873574683587317233100474596333" ~
    "97732477044918885134415363760091537564267438450166221393719306748706288159546481977519220771023674328906269" ~
    "07091179194127762122451172354677115640433357720616661564674474627305622913332030953340551384171819460532150" ~
    "14263280008795518132967549728467018836574253425016994231069156343106626043412205213831587971115075454063290" ~
    "65702484886486974028720372598692811493606274038423328749423321785787750735571857043787379693402336902911446" ~
    "96144864976971943452746744296030894371925405266588907106620625755099303799766583679361128137451104971506153" ~
    "78374357955586797212935876446309375720322132024605656611299713102758691128460432518434326915529284585734959" ~
    "71504256539930211218494723213238051654980290991967681511802248319251273721997921343310676421874844262159851" ~
    "21676396779352982985195854539210695788058685312327754543322916198905318905372539158222292325972781334278182" ~
    "56064882333760719681014481453198336237910767125501752882635183649210357258741035657389469487544469401817592" ~
    "30609370828146501857425324969212764624247832210765473750568198834564103545802726125228550315432503959184891" ~
    "89826304987591154063210354263890012837426155187877318375862355175378506956599570028011584125887015003017025" ~
    "91674630208424124491283923805257725147371412310230172563968305553583262840383638157686828464330456805994018" ~
    "70010719520929701779905832164175798681165865471477489647165479488312140431836079844314055731179349677763739" ~
    "89893022776560705853040837477526409474350703952145247016838840709087061471944372256502823145872995869738316" ~
    "89712685193904229711072135075697803726254581410950382703889873645162848201804682882058291353390138356491443" ~
    "00401570650988792671541745070668688878343805558350119674586234080595327247278438292593957715840368859409899" ~
    "39255241688378793572796795165407667392703125641876096219024304699348598919906001297774692145329704216778172" ~
    "61517850653008552559997940209969455431545274585670440368668042864840451288118230979349696272183649293551620" ~
    "29872469583299481932978335803459023227052612542114437084359584944338363838831775184116088171125127923337457" ~
    "72193398208190054063292937775306906607415304997682647124407768817248673421685881509913342207593094717385515" ~
    "93408089571244106347208931949128807835763115829400549708918023366596077070927599010527028150868897828549434" ~
    "03726427292621034870139928688535500620615143430786653960859950058714939141652065302070085265624074703660736" ~
    "60533380526376675720188394972770472221536338511354834636246198554259938719333674820422097449956672702505446" ~
    "42324395750686959133019374691914298099934242305501726652120924145596259605544275909519968243130842796937113" ~
    "2070210498232381957459";

U get_mod2pi(U)(ref int power)
{
    static if (is(U: uint))
        enum int digits = 9;
    else static if (is(U: ulong))
        enum int digits = 19;
    else static if (is(U: uint128))
        enum int digits = 38;
    else static if (is(U: uint256))
        enum digits = 77;
    else
        static assert(0, "Unsupport system for " ~ __FUNCTION__ ~ "." ~ U.stringof);

    if (power >= 0)
    {
        auto p = power;
        while (s_mod_1_2pi[p] == '0')
            ++p;
        string s =  s_mod_1_2pi[p .. p + digits];
        U result = uparse!U(s);
        power = -digits - (p - power);
        return result;
    }
    else
    {
        string s = s_mod_1_2pi[0 .. digits];
        U result = uparse!U(s);
        power -= digits;
        return result;
    }
}

//10 bit encoding
private uint packDPD(const(uint) d1, const(uint) d2, const(uint) d3) @nogc nothrow pure @safe
{
    const uint x = ((d1 & 8) >>> 1) | ((d2 & 8) >>> 2) | ((d3 & 8) >>> 3);
    switch (x)
    {
        case 0:
            return (d1 << 7) | (d2 << 4) | d3;
        case 1:
            return (d1 << 7) | (d2 << 4) | (d3 & 1) | 8;
        case 2:
            return (d1 << 7) | ((d3 & 6) << 4) | ((d2 & 1) << 4) | (d3 & 1) | 10;
        case 3:
            return (d1 << 7) | ((d2 & 1) << 4) | (d3 & 1) | 78;
        case 4:
            return ((d3 & 6) << 7) | ((d1 & 1) << 7) | (d2 << 4) | (d3 & 1) | 12;
        case 5:
            return ((d2 & 6) << 7) | ((d1 & 1) << 7) | ((d2 & 1) << 4) | (d3 & 1) | 46;
        case 6:
            return ((d3 & 6) << 7) | ((d1 & 1) << 7) | ((d2 & 1) << 4) | (d3 & 1) | 14;
        case 7:
            return ((d1 & 1) << 7) | ((d2 & 1) << 4) | (d3 & 1) | 110;
        default:
            assert(0);
    }
}

//10 bit decoding
private void unpackDPD(const uint declet, out uint d1, out uint d2, out uint d3) @nogc nothrow pure @safe
{
    uint decoded;
    const uint x = declet & 14;
    switch (x)
    {
        case 0:
            decoded = ((declet & 896) << 1) | (declet & 119);
            break;
        case 1:
            decoded = ((declet & 128) << 1) | (declet & 113) | ((declet & 768) >> 7) | 2048;
            break;
        case 2:
            decoded = ((declet & 896) << 1) | (declet & 17) | ((declet & 96) >> 4) | 128;
            break;
        case 3:
            decoded = ((declet & 896) << 1) | (declet & 113) | 8;
            break;
        case 4:
            decoded = ((declet & 128) << 1) | (declet & 17) | ((declet & 768) >> 7) | 2176;
            break;
        case 5:
            decoded = ((declet & 128) << 1) | (declet & 17) | ((declet & 768) >> 3) | 2056;
            break;
        case 6:
            decoded = ((declet & 896) << 1) | (declet & 17) | 136;
            break;
        case 7:
            decoded = ((declet & 128) << 1) | (declet & 17) | 2184;
            break;
        default:
            assert(0);
    }

    d1 = (decoded & 3840) >> 8;
    d2 = (decoded & 240) >> 4;
    d3 = (decoded & 15);
}

unittest // Decimal.opCast - up cast
{
    import std.conv : to;

    assert(cast(Decimal64)Decimal32(1234) == Decimal64(1234));
    assert(cast(Decimal128)Decimal64(12345678) == Decimal128(12345678));

    assert(to!Decimal64(Decimal32(1234)) == Decimal64(1234));
    assert(to!Decimal128(Decimal64(12345678)) == Decimal128(12345678));
}

version(none)
unittest
{
    import std.meta : AliasSeq;
    import std.stdio : writeln;
    writeln("Decimal32.min=", Decimal32.min.toString());
    writeln("Decimal32.max=", Decimal32.max.toString());
    writeln("Decimal64.min=", Decimal64.min.toString());
    writeln("Decimal64.max=", Decimal64.max.toString());
    writeln("Decimal128.min=", Decimal128.min.toString());
    writeln("Decimal128.max=", Decimal128.max.toString());

    static foreach (S; AliasSeq!(int, uint, long, ulong))
    {
        static foreach (D; AliasSeq!(Decimal32, Decimal64, Decimal128))
        {
            writeln(D.stringof, "(", S.stringof, ".min)", D(S.min).toString());
            writeln(D.stringof, "(", S.stringof, ".max)", D(S.max).toString());
        }
    }

    static foreach (S; AliasSeq!(float, double, real))
    {
        static foreach (D; AliasSeq!(Decimal32, Decimal64, Decimal128))
        {
            writeln(D.stringof, "(-", S.stringof, ".max)", D(-S.max).toString());
            writeln(D.stringof, "(", S.stringof, ".max)", D(S.max).toString());
        }
    }

/*
Decimal32.min=-9999999000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000.0
Decimal32.max= 9999999000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000.0
Decimal64.min=-9999999999999999000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000.0
Decimal64.max= 9999999999999999000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000.0
Decimal128.min=-9999999999999999999999999999999999000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000.0
Decimal128.max= 9999999999999999999999999999999999000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000.0
Decimal!32(int.min)-2147484000.0
Decimal!32(int.max) 2147484000.0
Decimal!64(int.min)-2147483648.0
Decimal!64(int.max) 2147483647.0
Decimal!128(int.min)-2147483648.0
Decimal!128(int.max) 2147483647.0
Decimal!32(uint.min)0.0
Decimal!32(uint.max)4294967000.0
Decimal!64(uint.min)0.0
Decimal!64(uint.max)4294967295.0
Decimal!128(uint.min)0.0
Decimal!128(uint.max)4294967295.0
Decimal!32(long.min)-9223372000000000000.0
Decimal!32(long.max) 9223372000000000000.0
Decimal!64(long.min)-9223372036854776000.0
Decimal!64(long.max) 9223372036854776000.0
Decimal!128(long.min)-9223372036854775808.0
Decimal!128(long.max) 9223372036854775807.0
Decimal!32(ulong.min)0.0
Decimal!32(ulong.max)18446740000000000000.0
Decimal!64(ulong.min)0.0
Decimal!64(ulong.max)18446744073709550000.0
Decimal!128(ulong.min)0.0
Decimal!128(ulong.max)18446744073709551615.0
Decimal!32(-float.max)-340282300000000000000000000000000000000.0
Decimal!32(float.max)340282300000000000000000000000000000000.0
Decimal!64(-float.max)-340282346000000000000000000000000000000.0
Decimal!64(float.max)340282346000000000000000000000000000000.0
Decimal!128(-float.max)-340282346000000000000000000000000000000.0
Decimal!128(float.max)340282346000000000000000000000000000000.0
Decimal!32(-double.max)-inf
Decimal!32(double.max)inf
Decimal!64(-double.max)-179769313486231600000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000.0
Decimal!64(double.max)179769313486231600000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000.0
Decimal!128(-double.max)-179769313486231570000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000.0
Decimal!128(double.max)179769313486231570000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000.0
Decimal!32(-real.max)-inf
Decimal!32(real.max)inf
Decimal!64(-real.max)-inf
Decimal!64(real.max)inf
Decimal!128(-real.max)-1189731495357231765020000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000.0
Decimal!128(real.max)1189731495357231765020000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000.0
*/
}
