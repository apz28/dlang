// Written in the D programming language.

/**

IEEE 754-2008 implementation of _decimal floating point data types.
_Decimal values are represented in memory using an $(B integral coefficient) and a $(B 10-based exponent).
Implementation is based on
$(LINK2 https://en.wikipedia.org/wiki/Binary_Integer_Decimal, binary integer _decimal encoding), supported by Intel.

_Decimal data types use the same semantics as the built-in floating point data type (NaNs, infinities, etc.),
the main difference being that they use internally a 10 exponent instead of a 2 exponent.

The current implementation supports three _decimal data types, as specified by IEEE 754-2008 standard.
The supported types are: $(MYREF Decimal32), $(MYREF Decimal64) and $(MYREF Decimal128), but they can be easily extended
to other bit widths if a underlying unsigned integral type is provided.

_Decimal data types are best used in financial applications because arithmetic operation results are exact.

$(SCRIPT inhibitQuickIndex = 1;)
$(DIVC quickindex,
 $(BOOKTABLE ,
  $(TR $(TH Category) $(TH Members) )
    $(TR $(TDNW Classics) $(TD
        $(MYREF copysign) $(MYREF fabs) $(MYREF fdim)
        $(MYREF fmod) $(MYREF fma) $(MYREF getNaNPayload)
        $(MYREF modf) $(MYREF NaN)
        $(MYREF nextAfter)
        $(MYREF nextDown) $(MYREF nextToward)  $(MYREF nextUp) $(MYREF remainder) $(MYREF sgn)
    ))
    $(TR $(TDNW Comparison) $(TD
        $(MYREF approxEqual)
        $(MYREF cmp)
        $(MYREF fmax) $(MYREF fmaxAbs) $(MYREF fmin) $(MYREF fminAbs)
        $(MYREF isEqual) $(MYREF isGreater) $(MYREF isGreaterOrEqual) $(MYREF isGreaterOrUnordered)
        $(MYREF isIdentical)
        $(MYREF isLess) $(MYREF isLessOrEqual) $(MYREF isLessOrUnordered)
        $(MYREF isNotEqual)
        $(MYREF isUnordered)
        $(MYREF sameQuantum)
        $(MYREF totalOrder) $(MYREF totalOrderAbs)
    ))
    $(TR $(TDNW Conversion) $(TD
        $(MYREF fromDPD) $(MYREF fromMsCurrency) $(MYREF fromMsDecimal) $(MYREF to) $(MYREF toDPD) $(MYREF toExact)
        $(MYREF toMsCurrency) $(MYREF toMsDecimal)
    ))
    $(TR $(TDNW Data types) $(TD
        $(MYREF Decimal) $(MYREF Decimal32) $(MYREF Decimal64)  $(MYREF Decimal128)
        $(MYREF DecimalClass) $(MYREF DecimalControl) $(MYREF ExceptionFlags)  $(MYREF Precision)
        $(MYREF RoundingMode)
    ))
    $(TR $(TDNW Exceptions) $(TD
        $(MYREF DecimalException) $(MYREF DivisionByZeroException)
        $(MYREF InexactException) $(MYREF InvalidOperationException)
        $(MYREF OverflowException) $(MYREF UnderflowException)
    ))
    $(TR $(TDNW Exponentiations & logarithms) $(TD
        $(MYREF cbrt) $(MYREF compound)
        $(MYREF exp) $(MYREF exp10) $(MYREF exp10m1) $(MYREF exp2) $(MYREF exp2m1) $(MYREF expm1) $(MYREF frexp)
        $(MYREF ilogb) $(MYREF ldexp) $(MYREF log) $(MYREF log10) $(MYREF log10p1) $(MYREF log2) $(MYREF log2p1)
        $(MYREF logp1) $(MYREF nextPow10) $(MYREF pow) $(MYREF quantexp) $(MYREF root)
        $(MYREF rsqrt) $(MYREF scalbn) $(MYREF sqrt)
        $(MYREF truncPow10)
    ))
    $(TR $(TDNW Introspection) $(TD
        $(MYREF decimalClass)
        $(MYREF isCanonical) $(MYREF isFinite) $(MYREF isInfinity) $(MYREF isNaN) $(MYREF isNormal)
        $(MYREF isPowerOf10) $(MYREF isSignaling) $(MYREF isSubnormal) $(MYREF isZero)
        $(MYREF signbit)
    ))
    $(TR $(TDNW Reduction) $(TD
        $(MYREF dot) $(MYREF poly) $(MYREF scaledProd) $(MYREF scaledProdSum) $(MYREF scaledProdDiff)
        $(MYREF sum) $(MYREF sumAbs) $(MYREF sumSquare)
    ))
    $(TR $(TDNW Rounding) $(TD
        $(MYREF ceil) $(MYREF floor) $(MYREF lrint) $(MYREF lround) $(MYREF nearbyint) $(MYREF quantize) $(MYREF rint)
        $(MYREF rndtonl) $(MYREF round) $(MYREF trunc)
    ))
    $(TR $(TDNW Trigonometry) $(TD
        $(MYREF acos) $(MYREF acosh) $(MYREF asin) $(MYREF asinh) $(MYREF atan) $(MYREF atan2) $(MYREF atan2pi)
        $(MYREF atanh) $(MYREF atanpi) $(MYREF cos) $(MYREF cosh) $(MYREF cospi)
        $(MYREF hypot) $(MYREF sin) $(MYREF sinh) $(MYREF sinpi) $(MYREF tan) $(MYREF tanh)
    ))
 )
)


Context:

All arithmetic operations are performed using a $(U thread local context). The context is setting various
environment options:
$(UL
 $(LI $(B precision) - number of digits used. Each _decimal data type has a default precision and all the calculations
                  are performed using this precision. Setting the precision to a custom value will affect
                  any subsequent operation and all the calculations will be performed using the specified
                  number of digits. See $(MYREF Precision) for details;)
 $(LI $(B rounding)  - rounding method used to adjust operation results. If a result will have more digits than the
                  current context precision, it will be rounded using the specified method. For available rounding
                  modes, see $(MYREF RoundingMode);)
 $(LI $(B flags)     - error flags. Every _decimal operation may signal an error. The context will gather these errors
                  for later introspection. See $(MYREF ExceptionFlags) for details;)
 $(LI $(B traps)     - exception traps. Any error flag which is set may trigger a $(MYREF DecimalException) if
                  the corresponding trap is installed. See $(MYREF ExceptionFlags) for details;)
)

Operators:

All floating point operators are implemented. Binary operators accept as left or right side argument any _decimal,
integral, character or binary floating point value.

Initialization:

Creating _decimal floating point values can be done in several ways:
$(UL
 $(LI by assigning a binary floating point, integral, char, bool, string or character range (including strings) value:
---
Decimal32 d = 123;
Decimal64 e = 12.34;
Decimal128 f = "24.9";
Decimal32 g = 'Y';
Decimal32 h = true;
---
)
 $(LI by using one of the available contructors.
   Suported type are binary floating point, integrals, chars, bool, strings or character ranges:
---
auto d = Decimal32(7500);
auto e = Decimal64(52.16);
auto f - Decimal128("199.4E-12");
auto g = Decimal32('a');
auto h = Decimal32(false);
---
)
 $(LI using one of predefined constants:
---
auto d = Decimal32.nan;
auto e = Decimal64.PI;
auto f - Decimal128.infinity;
---
)
)

Error_handling:

Errors occuring in arithmetic operations using _decimal values can be handled in two ways. By default, the thread local
context will throw exceptions for errors considered severe ($(MYREF InvalidOperationException),
$(MYREF DivisionByZeroException) or $(MYREF OverflowException)).
Any other error is considered silent and the context will only
set corresponding error flags ($(MYREF ExceptionFlags.inexact) or $(MYREF ExceptionFlags.underflow))<br/>
Most of the operations will throw $(MYREF InvalidOperationException) if a $(B signaling NaN) is encountered,
if not stated otherwise in the documentation. This behaviour is intended in order to avoid usage of unitialized variables
(_decimal values being by default always initialized to $(B signaling NaN))
---
//these will throw:
auto a = Decimal32() + 12;    //InvalidOperationException
auto b = Decimal32.min / 0;   //DivisionByZeroException
auto c = Decimal32.max * 2;   //OverflowException

//these will not throw:
auto d = Decimal32(123456789);                  //inexact
auto e = Decimal32.min_normal / Decimal32.max;  //underflow
---

Default behaviour can be altered using $(MYREF DecimalControl) by setting or clearing corresponding traps:
---
DecimalControl.disableExceptions(ExceptionFlags.overflow)
//from now on OverflowException will not be thrown;

DecimalControl.enableExceptions(ExceptionFlags.inexact)
//from now on InexactException will be thrown
---

$(UL
  $(LI Catching exceptions)
  ---
  try
  {
     auto a = Decimal32.min / 0;
  }
  catch (DivisionByZeroException)
  {
     //error occured
  }
  ---
  $(LI Checking for errors)
  ---
  DecimalControl.disableExceptions(ExceptionFlags.divisionByZero)
  DecimalControl.resetFlags();
  auto a = Decimal32.min / 0;
  if (DecimalControl.divisionByZero)
  {
     //error occured
  }
  ---
)

Exceptions_and_results:

Values returned after an exception is thrown or after an error flag is set, depend on the current $(MYREF RoundingMode).

$(BOOKTABLE,
  $(TR $(TH Exception) $(TH tiesToEven) $(TH tiesToAway) $(TH towardPositive) $(TH towardNegative) $(TH towardZero))
  $(TR $(TD $(MYREF OverflowException))  $(TD +∞) $(TD +∞) $(TD +∞) $(TD $(B +max)) $(TD $(B +max)) )
  $(TR $(TD $(MYREF OverflowException))  $(TD -∞) $(TD -∞) $(TD $(B -max)) $(TD -∞) $(TD $(B -max)) )
  $(TR $(TD $(MYREF UnderflowException)) $(TD ±0.0) $(TD ±0.0) $(TD $(B +min_normal * epsilon)) $(TD $(B -min_normal * epsilon)) $(TD ±0.0) )
  $(TR $(TD $(MYREF DivisionByZeroException)) $(TD ±∞) $(TD ±∞) $(TD ±∞) $(TD ±∞) $(TD ±∞) )
  $(TR $(TD $(MYREF InvalidOperationException)) $(TD $(B NaN)) $(TD $(B NaN)) $(TD $(B NaN)) $(TD $(B NaN)) $(TD $(B NaN)) )
 )

$(MYREF InexactException) does not have a specific value associated.

The subnormal exception is not implemented because it is not part of the IEEE-754-2008 standard.
If an operation results in a subnormal value (absolute value is smaller than $(B min_normal)),
$(MYREF UnderflowException) is always thrown or $(MYREF ExceptionFlag.underflow) is always set. It's better to avoid
subnormal values when performing calculations, the results of the operations involving such values are not exact.


Properties:

The following properties are defined for each _decimal type:

$(BOOKTABLE,
 $(TR $(TH Constant) $(TH Name) $(TH Decimal32) $(TH Decimal64) $(TH Decimal128))
 $(TR $(TD $(D init)) $(TD initial value) $(TD $(B signaling NaN)) $(TD $(B signaling NaN)) $(TD $(B signaling NaN)))
 $(TR $(TD $(D nan)) $(TD Not a Number) $(TD $(B NaN)) $(TD $(B NaN)) $(TD $(B NaN)))
 $(TR $(TD $(D infinity)) $(TD positive infinity) $(TD +∞) $(TD +∞) $(TD +∞))
 $(TR $(TD $(D dig)) $(TD precision) $(TD 7) $(TD 16) $(TD 34))
 $(TR $(TD $(D epsilon)) $(TD smallest increment to the value 1) $(TD 10$(SUPERSCRIPT-6)) $(TD 10$(SUPERSCRIPT-15)) $(TD 10$(SUPERSCRIPT-33)))
 $(TR $(TD $(D mant_dig)) $(TD number of bits in mantissa) $(TD 24) $(TD 54) $(TD 114))
 $(TR $(TD $(D max_10_exp)) $(TD maximum int value such that 10$(SUPERSCRIPT max_10_exp) is representable) $(TD 96) $(TD 384) $(TD 6144))
 $(TR $(TD $(D min_10_exp)) $(TD minimum int value such that 10$(SUPERSCRIPT min_10_exp) is representable and normalized) $(TD -95) $(TD -383) $(TD -6143))
 $(TR $(TD $(D max_2_exp)) $(TD maximum int value such that 2$(SUPERSCRIPT max_2_exp) is representable) $(TD 318) $(TD 1275) $(TD 20409))
 $(TR $(TD $(D min_2_exp)) $(TD minimum int value such that 2$(SUPERSCRIPT min_2_exp) is representable and normalized) $(TD -315) $(TD -1272) $(TD -20406))
 $(TR $(TD $(D max)) $(TD largest representable value that's not infinity) $(TD 9.(9) * 10$(SUPERSCRIPT 96)) $(TD 9.(9) * 10$(SUPERSCRIPT 384)) $(TD 9.(9) * 10$(SUPERSCRIPT 6144)))
 $(TR $(TD $(D min_normal)) $(TD smallest normalized value that's not 0) $(TD 10$(SUPERSCRIPT -95)) $(TD 10$(SUPERSCRIPT -383)) $(TD 10$(SUPERSCRIPT -6143)))
)


Useful_constants:

There are common constants defined for each type. Values int the tablebelow have 34 digits of precision corresponding
to Decimal128 data type; for Decimal64 and Decimal32, they are rounded away from 0 according to their respecive precision.
---
auto a = Decimal32.PI;
auto b = Decimal64.LN2;
auto c = Decimal128.E;
---

$(BOOKTABLE,
 $(TR $(TH Constant) $(TH Formula) $(TH Value))
 $(TR $(TD $(D E)) $(TD e) $(TD 2.7182818284590452353602874713526625))
 $(TR $(TD $(D PI)) $(TD π) $(TD 3.1415926535897932384626433832795029))
 $(TR $(TD $(D PI_2)) $(TD π/2) $(TD 1.5707963267948966192313216916397514))
 $(TR $(TD $(D PI_4)) $(TD π/4) $(TD 0.7853981633974483096156608458198757))
 $(TR $(TD $(D M_1_PI)) $(TD 1/π) $(TD 0.3183098861837906715377675267450287))
 $(TR $(TD $(D M_2_PI)) $(TD 2/π) $(TD 0.6366197723675813430755350534900574))
 $(TR $(TD $(D M_2_SQRTPI)) $(TD 2/√π) $(TD 1.1283791670955125738961589031215452))
 $(TR $(TD $(D SQRT2)) $(TD √2) $(TD 1.4142135623730950488016887242096981))
 $(TR $(TD $(D SQRT1_2)) $(TD √½) $(TD 0.7071067811865475244008443621048490))
 $(TR $(TD $(D LN10)) $(TD log$(SUBSCRIPT e)10) $(TD 2.3025850929940456840179914546843642))
 $(TR $(TD $(D LOG2T)) $(TD log$(SUBSCRIPT 2)10) $(TD 3.3219280948873623478703194294893902))
 $(TR $(TD $(D LOG2E)) $(TD log$(SUBSCRIPT 2)e) $(TD 1.4426950408889634073599246810018921))
 $(TR $(TD $(D LOG2)) $(TD log$(SUBSCRIPT 10)2) $(TD 0.3010299956639811952137388947244930))
 $(TR $(TD $(D LOG10E)) $(TD log$(SUBSCRIPT 10)e) $(TD 0.4342944819032518276511289189166051))
 $(TR $(TD $(D LN2)) $(TD log$(SUBSCRIPT e)2) $(TD 0.6931471805599453094172321214581766))
)

Interaction_with_binary_floating_point:

Even all _decimal operations allows the usage of binary floating point values, such mixing must be avoided;
Internally, binary floating point values are converted to _decimal counterparts before any operation:
---
float f = 1.1;
Decimal32 d = "2.5";
Decimal32 e = d + f;
//behind the scene this is roughly equivalent with e = d + Decimal32(f);
---

It is impossible to represent binary floating point values in full _decimal precision.
By default, $(B float) values are converted using 9 digits of precision, $(B double) values using 17 digits of precision and $(B real) values using 21 digits of precision;
---
float f = 1.1; //internal representation is 1.10000002384185791015625;
Decimal32 d1 = d;  //1.100000, 9 digits from float, but Decimal32 has a 7 digits precision
Decimal64 d2 = d;  //1.10000002000000, 9 digits from float
Decimal128 d3 = d; //1.10000002000000000000000000000000, 9 digits from float;
---

An exact conversion is possible only if the binary floating point value is an exact power of 2
and fits in the destination type precision or if it's a power of 5.
---
float f = 4.0;   //internally represented as 1.0 * 2^^2
Decimal32 d = f; //internally represented as 0.4 * 10^^1

float f = 25.0;  //internally represented as 1.5625 * 2^^4
Decimal32 d = f; //internally represented as 0.25 * 10^^2

float f = 2147483648; //internally represented as 1.0 * 2^^31
Decimal32 d = f;      //inexact, internally represented as 0.2147484 * 10^^7
---

Binary floating point conversion is dependent on the $(MYREF RoundingMode):
---
double d = 2.7; //internal representation is 2.7000000476837158203125;
DecimalControl.rounding = RoundingMode.tiesToAway;
Decimal64 d1 = d;  //d1 will be 2.700000047683716;
DecimalControl.rounding = RoundingMode.towardZero;
Decimal64 d2 = d;  //d2 will be 2.700000047683715;
---

Only Intel 80-bit $(B reals) are supported. Any other $(B real) type is cast to $(B double) before any conversion.

Special_remarks:

$(UL
 $(LI As stated above, avoid mixing binary floating point values with _decimal values, binary foating point values cannot exactly represent 10-based exponents;)
 $(LI There are many representations for the same number (IEEE calls them cohorts). Comparing bit by bit two _decimal values is error prone;)
 $(LI The comparison operator will return float.nan for an unordered result; There is no operator overloading for unordered comparisons;)
 $(LI Hexadecimal notation allows to define uncanonical coefficients (> 10 $(SUPERSCRIPT $(B dig)) - 1). According to IEEE standard, these values are considered equal to 0;)
 $(LI All operations are available at compile time; Avoid exponential or trigonometry functions in CTFE, using them will significantly increase the compile time;)
 $(LI Under CTFE, operations are performed in full precision, values are rounded to nearest. $(MYREF InexactException) and $(MYREF UnderflowException) are never thrown during CTFE;)
)

Performance_tips:

$(UL
 $(LI When performing _decimal calculations, avoid binary floating point;
      conversion base-2 from/to base-10 is costly and error prone, especially if the exponents are very big or very small;)
 $(LI Avoid custom precisions; rounding is expensive since most of the time will involve a division operation;)
 $(LI Use $(MYREF Decimal128) only if you truly need 34 digits of precision. $(MYREF Decimal64) and $(MYREF Decimal32) arithmetic is much faster;)
 $(LI Avoid traps and check yourself for flags; throwing and catching exceptions is expensive;)
 $(LI Contrary to usual approach, multiplication/division by 10 for _decimal values is faster than multiplication/division by 2;)
)


Copyright: Copyright (c) Răzvan Ștefănescu 2018.
License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
Authors:   Răzvan Ștefănescu
Source:    $(LINK2 https://github.com/rumbu13/decimal/blob/master/src/package.d, _decimal.d)

*/
module decimal.decimal;

import core.checkedint: adds, subs;
import std.format: FormatException, FormatSpec, singleSpec;
import std.math: fabs, FloatingPointControl, getNaNPayload, ieeeFlags, isNaN, isInfinity, ldexp, resetIeeeFlags, signbit;
import std.range.primitives: ElementType, empty, isInputRange;
import std.traits: isFloatingPoint, isIntegral, isSigned, isSomeChar, isSomeString, isUnsigned, Unqual, Unsigned;

version(Windows)
{
    public import core.sys.windows.wtypes: DECIMAL;
}
else
{
    struct DECIMAL {
        ushort wReserved;
        struct {
            ubyte scale;
            ubyte sign;
            enum ubyte DECIMAL_NEG = 0x80;
        }
        uint Hi32;
        union {
            struct {
                uint Lo32;
                uint Mid32;
            }
            ulong Lo64;
        }
    }
}

import decimal.floats;
import decimal.integrals;
import decimal.ranges;

private alias fma = decimal.integrals.fma;

version(D_BetterC)
{
}
else
{
    import decimal.sinks;
}

version (unittest)
{
    import std.format;
    import std.stdio;
    import std.typetuple;
}

enum CheckInfinity : byte
{
    no = 0,         /// The value is $(B NaN) (quiet or signaling) or any finite value
    yes = 1,        /// The value is infinite
    negative = -1   /// The value is negative infinite
}

enum CheckNaN : byte
{
    no = 0,         /// The value is not $(B NaN) (quiet or signaling)
    qNaN = 1,       /// The value is $(B NaN) quiet
    sNaN = 2,       /// The value is $(B NaN) signaling
    negQNaN = -1,   /// The value is negative $(B NaN) quiet
    negSNaN = -2    /// The value is negative $(B NaN) signaling
}

/**
These flags indicate that an error has occurred. They indicate that a 0, $(B NaN) or an infinity value has been generated,
that a result is inexact, or that a signalling $(B NaN) has been encountered.
If the corresponding traps are set using $(MYREF DecimalControl),
an exception will be thrown after setting these error flags.

By default the context will have all error flags lowered and exceptions are thrown only for severe errors.
*/
enum ExceptionFlags : uint
{
    ///no error
    none             = 0U,
    ///$(MYREF InvalidOperationException) is thrown if trap is set
	invalidOperation = 1U << 0,
    ///$(MYREF DivisionByZeroException) is thrown if trap is set
	divisionByZero   = 1U << 1,
    ///$(MYREF OverflowException) is thrown if trap is set
	overflow         = 1U << 2,
    ///$(MYREF UnderflowException) is thrown if trap is set
	underflow        = 1U << 3,
    ///$(MYREF InexactException) is thrown if trap is set
	inexact          = 1U << 4,
    ///group of errors considered severe: invalidOperation, divisionByZero, overflow
	severe           = invalidOperation | divisionByZero | overflow,
    ///all errors
	all              = severe | underflow | inexact
}

/**
* Rounding modes. To better understand how rounding is performed, consult the table below.
*
* $(BOOKTABLE,
*  $(TR $(TH Value) $(TH tiesToEven) $(TH tiesToAway) $(TH towardPositive) $(TH towardNegative) $(TH towardZero))
*  $(TR $(TD +1.3)  $(TD +1)         $(TD +1)         $(TD +2)             $(TD +1)             $(TD +1))
*  $(TR $(TD +1.5)  $(TD +2)         $(TD +2)         $(TD +2)             $(TD +1)             $(TD +1))
*  $(TR $(TD +1.8)  $(TD +2)         $(TD +2)         $(TD +2)             $(TD +1)             $(TD +1))
*  $(TR $(TD -1.3)  $(TD -1)         $(TD -1)         $(TD -1)             $(TD -2)             $(TD -1))
*  $(TR $(TD -1.5)  $(TD -2)         $(TD -2)         $(TD -1)             $(TD -2)             $(TD -1))
*  $(TR $(TD -1.8)  $(TD -2)         $(TD -2)         $(TD -1)             $(TD -2)             $(TD -1))
*  $(TR $(TD +2.3)  $(TD +2)         $(TD +2)         $(TD +3)             $(TD +2)             $(TD +2))
*  $(TR $(TD +2.5)  $(TD +2)         $(TD +3)         $(TD +3)             $(TD +2)             $(TD +2))
*  $(TR $(TD +2.8)  $(TD +3)         $(TD +3)         $(TD +3)             $(TD +2)             $(TD +2))
*  $(TR $(TD -2.3)  $(TD -2)         $(TD -2)         $(TD -2)             $(TD -3)             $(TD -2))
*  $(TR $(TD -2.5)  $(TD -2)         $(TD -3)         $(TD -2)             $(TD -3)             $(TD -2))
*  $(TR $(TD -2.8)  $(TD -3)         $(TD -3)         $(TD -2)             $(TD -3)             $(TD -2))
* )
*/
enum RoundingMode : byte
{
    ///rounded away from zero; halfs are rounded to the nearest even number
	tiesToEven,
    ///rounded away from zero
	tiesToAway,
    ///truncated toward positive infinity
	towardPositive,
    ///truncated toward negative infinity
	towardNegative,
    ///truncated toward zero
	towardZero,

    implicit = tiesToEven,
    banking = tiesToEven
}

/**
_Precision used to round _decimal operation results. Every result will be adjusted
to fit the specified precision. Use $(MYREF DecimalControl) to query or set the
context precision
*/
enum Precision : int
{
    ///use the default precision of the current type
    ///(7 digits for Decimal32, 16 digits for Decimal64 or 34 digits for Decimal128)
	precisionDefault = 0,
    ///use 32 bits precision (7 digits)
	precision32 = Decimal!32.PRECISION,
    ///use 64 bits precision (16 digits)
	precision64 = Decimal!64.PRECISION,
    ////use 128 bits precision (34 digits)
    precision128 = Decimal!128.PRECISION,
    ////
    banking = 4
}

/**
    Container for _decimal context control, provides methods to alter exception handling,
    manually edit error flags, adjust arithmetic precision and rounding mode
*/
struct DecimalControl
{
private:
	static ExceptionFlags flags;
	static ExceptionFlags traps;

    version(D_BetterC)
    {}
    else
    {
        static immutable EInvalidOperationException = new InvalidOperationException("Invalid operation");
        static immutable EDivisionByZeroException = new DivisionByZeroException("Division by zero");
        static immutable EOverflowException = new OverflowException("Overflow");
        static immutable EUnderflowException = new UnderflowException("Underflow");
        static immutable EInexactException = new InexactException("Inexact");
    }

    static void checkFlags(const ExceptionFlags group, const ExceptionFlags traps) @nogc pure @safe
    {
        version(D_BetterC)
        {
            if (__ctfe)
            {
                if ((group & ExceptionFlags.invalidOperation) && (traps & ExceptionFlags.invalidOperation))
                    assert(0, "Invalid operation");
                if ((group & ExceptionFlags.divisionByZero) && (traps & ExceptionFlags.divisionByZero))
                    assert(0, "Division by zero");
                if ((group & ExceptionFlags.overflow) && (traps & ExceptionFlags.overflow))
                    assert(0, "Overflow");
            }
        }
        else
        {
            if ((group & ExceptionFlags.invalidOperation) && (traps & ExceptionFlags.invalidOperation))
                throw EInvalidOperationException;
            if ((group & ExceptionFlags.divisionByZero) && (traps & ExceptionFlags.divisionByZero))
                throw EDivisionByZeroException;
            if ((group & ExceptionFlags.overflow) && (traps & ExceptionFlags.overflow))
                throw EOverflowException;
            if ((group & ExceptionFlags.underflow) && (traps & ExceptionFlags.underflow))
                throw EUnderflowException;
            if ((group & ExceptionFlags.inexact) && (traps & ExceptionFlags.inexact))
                throw EInexactException;
        }
    }

public:
    /**
    Gets or sets the rounding mode used when the result of an operation exceeds the _decimal precision.
    See $(MYREF RoundingMode) for details.
    ---
    DecimalControl.rounding = RoundingMode.tiesToEven;
    Decimal32 d1 = 123456789;
    assert(d1 == 123456800);

    DecimalControl.rounding = RoundingMode.towardNegative;
    Decimal32 d2 = 123456789;
    assert(d2 == 123456700);
    ---
    */
    @IEEECompliant("defaultModes", 46)
    @IEEECompliant("getDecimalRoundingDirection", 46)
    @IEEECompliant("restoreModes", 46)
    @IEEECompliant("saveModes", 46)
    @IEEECompliant("setDecimalRoundingDirection", 46)
    static RoundingMode rounding;

    /**
    Gets or sets the precision applied to peration results.
    See $(MYREF Precision) for details.
    ---
    DecimalControl.precision = precisionDefault;
    Decimal32 d1 = 12345;
    assert(d1 == 12345);

    DecimalControl.precision = 4;
    Decimal32 d2 = 12345;
    assert(d2 == 12350);
    ---
    */
    static int precision;

    /**
    Sets specified error flags. Multiple errors may be ORed together.
    ---
    DecimalControl.raiseFlags(ExceptionFlags.overflow | ExceptionFlags.underflow);
    assert (DecimalControl.overflow);
    assert (DecimalControl.underflow);
    ---
	*/
    @IEEECompliant("raiseFlags", 26)
	static void raiseFlags(const ExceptionFlags group) @nogc @safe
	{
        if (__ctfe)
            checkFlags(group, ExceptionFlags.severe);
        else
        {
            const newFlags = flags ^ (group & ExceptionFlags.all);
            flags |= group & ExceptionFlags.all;
		    checkFlags(newFlags, traps);
        }
	}

    /**
    Unsets specified error flags. Multiple errors may be ORed together.
    ---
    DecimalControl.resetFlags(ExceptionFlags.inexact);
    assert(!DecimalControl.inexact);
    ---
	*/
    @IEEECompliant("lowerFlags", 26)
    @nogc @safe nothrow
	static void resetFlags(const ExceptionFlags group)
	{
		flags &= ~(group & ExceptionFlags.all);
	}

    ///ditto
    @IEEECompliant("lowerFlags", 26)
    @nogc @safe nothrow
	static void resetFlags()
	{
		flags = ExceptionFlags.none;
	}

    /**
    Enables specified error flags (group) without throwing corresponding exceptions.
    ---
    DecimalControl.restoreFlags(ExceptionFlags.underflow | ExceptionsFlags.inexact);
    assert (DecimalControl.testFlags(ExceptionFlags.underflow | ExceptionFlags.inexact));
    ---
	*/
    @IEEECompliant("restoreFlags", 26)
	@nogc @safe nothrow
	static void restoreFlags(const ExceptionFlags group)
	{
		flags |= group & ExceptionFlags.all;
	}

    /**
    Checks if the specified error flags are set. Multiple exceptions may be ORed together.
    ---
    DecimalControl.raiseFlags(ExceptionFlags.overflow | ExceptionFlags.underflow | ExceptionFlags.inexact);
    assert (DecimalControl.hasFlags(ExceptionFlags.overflow | ExceptionFlags.inexact));
    ---
	*/
    @IEEECompliant("testFlags", 26)
    @IEEECompliant("testSavedFlags", 26)
	static bool hasFlags(const ExceptionFlags group) @nogc nothrow @safe
	{
		return (flags & (group & ExceptionFlags.all)) != 0;
	}

     /**
    Returns the current set flags.
    ---
    DecimalControl.restoreFlags(ExceptionFlags.inexact);
    assert (DecimalControl.saveFlags() & ExceptionFlags.inexact);
    ---
	*/
    @IEEECompliant("saveAllFlags", 26)
	static ExceptionFlags saveFlags() @nogc nothrow @safe
	{
		return flags;
	}

	static void setFlags(const ExceptionFlags group) @nogc nothrow @safe
	{
        if (__ctfe)
        {}
        else
        {
            flags |= group & ExceptionFlags.all;
        }
	}

    /**
    Disables specified exceptions. Multiple exceptions may be ORed together.
    ---
    DecimalControl.disableExceptions(ExceptionFlags.overflow);
    auto d = Decimal64.max * Decimal64.max;
    assert (DecimalControl.overflow);
    assert (d.isInfinity);
    ---
	*/
	@nogc @safe nothrow
	static void disableExceptions(const ExceptionFlags group)
	{
		traps &= ~(group & ExceptionFlags.all);
	}

    ///ditto
    @nogc @safe nothrow
	static void disableExceptions()
	{
		traps = ExceptionFlags.none;
	}

    /**
    Enables specified exceptions. Multiple exceptions may be ORed together.
    ---
    DecimalControl.enableExceptions(ExceptionFlags.overflow);
    try
    {
        auto d = Decimal64.max * 2;
    }
    catch (OverflowException)
    {
        writeln("Overflow error")
    }
    ---
	*/
	@nogc @safe nothrow
	static void enableExceptions(const ExceptionFlags group)
	{
		traps |= group & ExceptionFlags.all;
	}

    /**
    Extracts current enabled exceptions.
    ---
    auto saved = DecimalControl.enabledExceptions;
    DecimalControl.disableExceptions(ExceptionFlags.all);
    DecimalControl.enableExceptions(saved);
    ---
	*/
	static @property ExceptionFlags enabledExceptions() @nogc nothrow @safe
	{
		return traps;
	}

    /**
    IEEE _decimal context errors. By default, no error is set.
    ---
    DecimalControl.disableExceptions(ExceptionFlags.all);
    Decimal32 uninitialized;
    Decimal64 d = Decimal64.max * 2;
    Decimal32 e = uninitialized + 5.0;
    assert(DecimalControl.overflow);
    assert(DecimalControl.invalidOperation);
    ---
    */
	static @property bool invalidOperation() @nogc nothrow @safe
	{
		return (flags & ExceptionFlags.invalidOperation) != 0;
	}

    ///ditto
	static @property bool divisionByZero() @nogc nothrow @safe
	{
		return (flags & ExceptionFlags.divisionByZero) != 0;
	}

    ///ditto
	static @property bool overflow() @nogc nothrow @safe
	{
		return (flags & ExceptionFlags.overflow) != 0;
	}

    ///ditto
	static @property bool underflow() @nogc nothrow @safe
	{
		return (flags & ExceptionFlags.underflow) != 0;
	}

    ///ditto
	static @property bool inexact() @nogc nothrow @safe
	{
		return (flags & ExceptionFlags.inexact) != 0;
	}

    ///true if this programming environment conforms to IEEE 754-1985
    @IEEECompliant("is754version1985", 24)
    enum is754version1985 = true;

    ///true if this programming environment conforms to IEEE 754-2008
    @IEEECompliant("is754version2008", 24)
    enum is754version2008 = true;
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
        static assert(0, "Unsupport floating point type");
}

/**
_Decimal floating-point computer numbering format that occupies 4, 8 or 16 bytes in computer memory.
*/
struct Decimal(int bits)
if (bits == 32 || bits == 64 || bits == 128)
{
private:
    alias D = typeof(this);

package:
    alias U = DataType!D;

public:
    enum PRECISION      = 9 * bits / 32 - 2;             //7, 16, 34
    enum EMAX           = 3 * (2 ^^ (bits / 16 + 3));    //96, 384, 6144
    enum EXP_BIAS       = EMAX + PRECISION - 2;          //101, 398, 6176
    enum EXP_MIN        = -EXP_BIAS;
    enum EXP_MAX        = EMAX - PRECISION + 1;          //90, 369, 6111
    enum COEF_MAX       = pow10!U[PRECISION] - 1U;
    enum COEF_MAX_RAW   = MASK_COE2 | MASK_COEX;

	enum bitLength      = bits;
	enum byteLength     = bits / 8;

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

    enum E              = buildin(s_e);
    enum PI             = buildin(s_pi);
    enum PI_2           = buildin(s_pi_2);
    enum PI_4           = buildin(s_pi_4);
    enum M_1_PI         = buildin(s_m_1_pi);
    enum M_2_PI         = buildin(s_m_2_pi);
    enum M_2_SQRTPI     = buildin(s_m_2_sqrtpi);
    enum SQRT2          = buildin(s_sqrt2);
    enum SQRT1_2        = buildin(s_sqrt1_2);
    enum LN10           = buildin(s_ln10);
    enum LOG2T          = buildin(s_log2t);
    enum LOG2E          = buildin(s_log2e);
    enum LOG2           = buildin(s_log2);
    enum LOG10E         = buildin(s_log10e);
    enum LN2            = buildin(s_ln2);

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
            assert (d1 == d2);
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

        auto c = to!Decimal32(false); //phobos to!(bool, Decimal32)
        auto d = to!Decimal128('Z');  //phobos to!(char, Decimal128)
        ---
    */
    @IEEECompliant("convertFormat", 22)
    @IEEECompliant("convertFromDecimalCharacter", 22)
    @IEEECompliant("convertFromHexCharacter", 22)
    @IEEECompliant("convertFromInt", 21)
    @IEEECompliant("decodeBinary", 23)
    this(T)(auto const ref T value)
    if (isSomeChar!T || isSomeString!T || (isInputRange!T && isSomeChar!(ElementType!T) && !isSomeString!T))
    {
        static if (isSomeChar!T)
        {
            const flags = packIntegral(cast(uint)value,
                            __ctfe ? 0 : DecimalControl.precision,
                            __ctfe ? RoundingMode.implicit : DecimalControl.rounding);
            if (!__ctfe)
                DecimalControl.raiseFlags(flags);
        }
        else static if (isSomeString!T)
        {
            const flags = packString(value,
                            __ctfe ? 0 : DecimalControl.precision,
                            __ctfe ? RoundingMode.implicit : DecimalControl.rounding);
            if (!__ctfe)
                DecimalControl.raiseFlags(flags);
        }
        else static if (isInputRange!T && isSomeChar!(ElementType!T) && !isSomeString!T)
        {
            const flags = packRange(value,
                            __ctfe ? 0 : DecimalControl.precision,
                            __ctfe ? RoundingMode.implicit : DecimalControl.rounding);
            if (!__ctfe)
                DecimalControl.raiseFlags(flags);
        }
        else
            static assert (0, "Cannot convert expression of type '" ~ Unqual!T.stringof ~ "' to '" ~ Unqual!D.stringof ~ "'");
    }

    ///ditto
    this(T)(auto const ref T value)
    if (!(isSomeChar!T || isSomeString!T || (isInputRange!T && isSomeChar!(ElementType!T) && !isSomeString!T)))
    {
        static if (isIntegral!T)
        {
            const flags = packIntegral(value,
                            __ctfe ? 0 : DecimalControl.precision,
                            __ctfe ? RoundingMode.implicit : DecimalControl.rounding);
            if (!__ctfe)
                DecimalControl.raiseFlags(flags);
        }
        else static if (isFloatingPoint!T)
        {
            const flags = packFloatingPoint(value,
                            __ctfe ? 0 : DecimalControl.precision,
                            __ctfe ? RoundingMode.implicit : DecimalControl.rounding);
            if (!__ctfe)
                DecimalControl.raiseFlags(flags);
        }
        else static if (is(T: D))
            this.data = value.data;
        else static if (is(T: bool))
            this.data = value ? one.data : zero.data;
        else static if (isDecimal!T)
        {
            const flags = decimalToDecimal(value, this,
                            __ctfe ? 0 : DecimalControl.precision,
                            __ctfe ? RoundingMode.implicit : DecimalControl.rounding);
            if (!__ctfe)
                DecimalControl.raiseFlags(flags);
        }
        else
            static assert (0, "Cannot convert expression of type '" ~ Unqual!T.stringof ~ "' to '" ~ Unqual!D.stringof ~ "'");
    }

    ///ditto
    /// Ignore the flags because explicit precision & rounding request
    this(T)(auto const ref T value, const int precision, const RoundingMode mode) @nogc nothrow pure @safe
    if (isIntegral!T || isFloatingPoint!T || isDecimal!T)
    {
        static if (isIntegral!T)
            packIntegral(value, precision, mode);
        else static if (isFloatingPoint!T)
            packFloatingPoint(value, precision, mode);
        else static if (isDecimal!T)
            decimalToDecimal(value, this, precision, mode);
        else
            static assert (0);
    }

    /**
    Implementation of assignnment operator. It supports the same semantics as the constructor.
    */
    @IEEECompliant("copy", 23)
    auto ref opAssign(T)(auto const ref T value)
    {
        auto result = Unqual!D(value);
        this.data = result.data;
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
        static if (isUnsigned!T)
        {
            const flags = decimalToUnsigned(this, result,
                            __ctfe ? RoundingMode.implicit : DecimalControl.rounding);
            if (!__ctfe)
                DecimalControl.setFlags(flags);
        }
        else static if (isIntegral!T)
        {
            const flags = decimalToSigned(this, result,
                            __ctfe ? RoundingMode.implicit : DecimalControl.rounding);
            if (!__ctfe)
                DecimalControl.setFlags(flags);
        }
        else static if (isFloatingPoint!T)
        {
            const flags = decimalToFloat(this, result,
                            __ctfe ? RoundingMode.implicit : DecimalControl.rounding);
            if (!__ctfe)
                DecimalControl.setFlags(flags);
        }
        else static if (is(T: D))
            result = this;
        else static if (is(D: Decimal32) && (is(T: Decimal64) || is(T: Decimal128)))
            decimalToDecimal(this, result, 0, RoundingMode.implicit);
        else static if (is(D: Decimal64) && is(T: Decimal128))
            decimalToDecimal(this, result, 0, RoundingMode.implicit);
        else static if (isDecimal!T)
        {
            const flags = decimalToDecimal(this, result,
                            __ctfe ? 0 : DecimalControl.precision,
                            __ctfe ? RoundingMode.implicit : DecimalControl.rounding);
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
            static assert(0, "Cannot cast a value of type '" ~
                              Unqual!D.stringof ~ "' to '" ~
                              Unqual!T.stringof ~ "'");

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
        static if (bits == 128)
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
    auto ref opUnary(string op: "++")() @nogc @safe
    {
        const flags = decimalInc(this,
                        __ctfe ? 0 : DecimalControl.precision,
                        __ctfe ? RoundingMode.implicit : DecimalControl.rounding);
        if (!__ctfe)
            DecimalControl.raiseFlags(flags);
        return this;
    }

    ///ditto
    auto ref opUnary(string op: "--")() @nogc @safe
    {
        const flags = decimalDec(this,
                        __ctfe ? 0 : DecimalControl.precision,
                        __ctfe ? RoundingMode.implicit : DecimalControl.rounding);
        if (!__ctfe)
            DecimalControl.raiseFlags(flags);
        return this;
    }

    /**
    Implementation of == operator. This operation is silent, no exceptions are thrown.
    Supported types : _decimal, floating point, integral, char
    */
    @IEEECompliant("compareQuietEqual", 24)
    @IEEECompliant("compareQuietNotEqual", 24)
    bool opEquals(T)(auto const ref T value) const @nogc nothrow @safe
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
                    __ctfe ? RoundingMode.implicit : DecimalControl.rounding);
        }
        else static if (isSomeChar!T)
            return opEquals(cast(uint)value);
        else
            static assert (0, "Cannot compare values of type '" ~
                                Unqual!D.stringof ~ "' and '" ~
                                Unqual!T.stringof ~ "'");
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
    float opCmp(T)(auto const ref T value) const @nogc nothrow @safe
    {
        static if (isDecimal!T || isIntegral!T)
            return cmp(this, value);
        else static if (isFloatingPoint!T)
        {
            enum fltPrecision = maxPrecision!T();
            const decPrecision = __ctfe ? PRECISION : DecimalControl.precision;
            return cmp(this, value,
                    decPrecision > fltPrecision ? fltPrecision : decPrecision,
                    __ctfe ? RoundingMode.implicit : DecimalControl.rounding);
        }
        else static if (isSomeChar!T)
            return cmp(this, cast(uint)value);
        else
            static assert (0, "Cannot compare values of type '" ~
                               Unqual!D.stringof ~ "' and '" ~
                               Unqual!T.stringof ~ "'");
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
    auto opBinary(string op, T)(auto const ref T value) const @nogc @safe
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
            static assert (0, "Cannot perform binary operation: '" ~
                                Unqual!D.stringof ~ "' " ~ op ~" '" ~
                                Unqual!T.stringof ~ "'");
        if (!__ctfe)
            DecimalControl.raiseFlags(flags);
        return result;
    }

    ///ditto
    auto opBinaryRight(string op, T)(auto const ref T value) const @nogc @safe
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
            static assert (0, "Cannot perform binary operation: '" ~
                                Unqual!T.stringof ~ "' " ~ op ~" '" ~
                                Unqual!D.stringof ~ "'");
        if (!__ctfe)
            DecimalControl.raiseFlags(flags);
        return result;
    }

    ///ditto
    auto opOpAssign(string op, T)(auto const ref T value) @nogc @safe
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
            static assert (0, "Cannot perform assignment operation: '" ~
                                Unqual!D.stringof ~ "' " ~ op ~"= '" ~
                                Unqual!T.stringof ~ "'");

        if (!__ctfe)
            DecimalControl.raiseFlags(flags);
        return this;
    }

    /**
    Returns a unique hash of the _decimal value suitable for use in a hash table.
    Notes:
       This function is not intended for direct use, it's provided as support for associative arrays.
    */
    @safe pure nothrow @nogc
    size_t toHash()
    {
        static if (bits == 32)
            return data;
        else static if (bits == 64)
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

    version (D_BetterC)
    {}
    else {

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
    void toString(C)(scope void delegate(const(C)[]) sink, FormatSpec!C fmt) const
    if (isSomeChar!C)
    {
        sinkDecimal(fmt, sink, this, __ctfe ? RoundingMode.implicit : DecimalControl.rounding);
    }

    ///ditto
    @IEEECompliant("convertToDecimalCharacter", 22)
    void toString(C)(scope void delegate(const(C)[]) sink) const
    if (isSomeChar!C)
    {
        sinkDecimal(singleSpec("%g"), sink, this, __ctfe ? RoundingMode.implicit : DecimalControl.rounding);
    }

    ///Converts current value to string in floating point or scientific notation,
    ///which one is shorter.
    @IEEECompliant("convertToDecimalCharacter", 22)
    string toString() const nothrow @safe
    {
        return decimalToString!char(this, __ctfe ? RoundingMode.implicit : DecimalControl.rounding);
    }

    ///Converts current value to string according to the
    ///format specification
    @IEEECompliant("convertToDecimalCharacter", 22)
    @IEEECompliant("convertToHexCharacter", 22)
    string toString(C)(FormatSpec!C fmt) const
    {
        return decimalToString!C(fmt, this, __ctfe ? RoundingMode.implicit : DecimalControl.rounding);
    }

    ///ditto
    @IEEECompliant("convertToDecimalCharacter", 22)
    @IEEECompliant("convertToHexCharacter", 22)
    string toString(C)(const(C)[] fmt) const
    {
        FormatSpec!C spec = singleSpec(fmt);
        return decimalToString!C(spec, this, __ctfe ? RoundingMode.implicit : DecimalControl.rounding);
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
        static if (bits == 128)
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
        static if (bits == 128)
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
        static if (bits == 128)
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
        static if (bits == 128)
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
        static if (bits == 128)
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

package:
    static D buildin(const U coefficientMask, const U exponentMask, const U signMask) @nogc nothrow pure @safe
    {
        D result = void;
        result.data = signMask | exponentMask | coefficientMask;
        return result;
    }

    static D buildin(const U coefficient, const int biasedExponent, const bool isNegative) @nogc nothrow pure @safe
    {
        D result = void;
        result.pack(coefficient, biasedExponent, isNegative);
        return result;
    }

    static D buildin(C)(scope const(C)[] validDecimal) @nogc nothrow pure @safe
    if (isSomeChar!C)
    {
        Unqual!D result = void;
        result.packString(validDecimal, D.PRECISION, RoundingMode.implicit);
        return result;
    }

    //packs valid components
    void pack(const U coefficient, const int biasedExponent, const bool isNegative) @nogc nothrow pure @safe
    in
    {
        assert (coefficient <= COEF_MAX_RAW);
        assert (biasedExponent >= EXP_MIN && biasedExponent <= EXP_MAX);
    }
    out
    {
        assert ((this.data & MASK_INF) != MASK_INF);
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

    void packRaw(const U coefficient, const uint unbiasedExponent, const bool isNegative)
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
        assert (coefficient <= (MASK_COE2 | MASK_COEX));
        assert (biasedExponent >= EXP_MIN && biasedExponent <= EXP_MAX);
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

private:
    U data = MASK_SNAN;

    enum expBits        = bits / 16 + 6;                 //8, 10, 14
    enum trailingBits   = bits - expBits - 1;            //23, 53, 113

    enum SHIFT_EXP1     = trailingBits;                  //23, 53, 113
    enum SHIFT_EXP2     = trailingBits - 2;              //21, 51, 111

    enum MASK_QNAN      = U(0b01111100U) << (bits - 8);
    enum MASK_SNAN      = U(0b01111110U) << (bits - 8);
    enum MASK_SNANBIT   = U(0b00000010U) << (bits - 8);
    enum MASK_INF       = U(0b01111000U) << (bits - 8);
    enum MASK_SGN       = U(0b10000000U) << (bits - 8);
    enum MASK_EXT       = U(0b01100000U) << (bits - 8);
    enum MASK_EXP1      = ((U(1U) << expBits) - 1U) << SHIFT_EXP1;
    enum MASK_EXP2      = ((U(1U) << expBits) - 1U) << SHIFT_EXP2;
    enum MASK_COE1      = ~(MASK_SGN | MASK_EXP1);
    enum MASK_COE2      = ~(MASK_SGN | MASK_EXP2 | MASK_EXT);
    enum MASK_COEX      = U(1U) << trailingBits;
    enum MASK_ZERO      = U(cast(uint)EXP_BIAS) << SHIFT_EXP1;
    enum MASK_PAYL      = (U(1U) << (trailingBits - 3)) - 1U;
    enum MASK_NONE      = U(0U);

    enum PAYL_MAX       = pow10!U[PRECISION - 1] - 1U;

    enum LOG10_2        = 0.30102999566398119521L;

    //packs components, but checks the limits before
    @nogc nothrow pure @safe
    ExceptionFlags checkedPack(const U coefficient, const int exponent, const bool isNegative,
        int precision, const RoundingMode mode, const bool acceptNonCanonical)
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
    bool errorPack(const bool isNegative, const ExceptionFlags flags, const int precision,
        const RoundingMode mode, const U payload = U(0U))
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
    ExceptionFlags maxPack(const bool isNegative, const int precision)
    {
        data = isNegative ? MASK_SGN : MASK_NONE;
        auto p = realPrecision(precision);
        if (p >= PRECISION)
            data |= max.data;
        else
        {
            const U coefficient = (COEF_MAX / pow10!U[PRECISION - p]) * pow10!U[PRECISION - p];
            const int exponent = EXP_MAX;
            pack(coefficient, exponent, isNegative);
            return ExceptionFlags.inexact;
        }
        return ExceptionFlags.none;
    }

    @nogc nothrow pure @safe
    ExceptionFlags minPack(const bool isNegative)
    {
        data = (isNegative ? MASK_SGN : MASK_NONE) | subn.data;
        return ExceptionFlags.underflow;
    }

    //packs infinity or max, depending on the rounding mode
    @nogc nothrow pure @safe
    ExceptionFlags overflowPack(const bool isNegative, const int precision, const RoundingMode mode)
    {
        switch (mode)
        {
            case RoundingMode.towardZero:
                return maxPack(isNegative, precision) | ExceptionFlags.overflow;
            case RoundingMode.towardNegative:
                if (!isNegative)
                    return maxPack(false, precision) | ExceptionFlags.overflow;
                goto default;
            case RoundingMode.towardPositive:
                if (isNegative)
                    return maxPack(true, precision) | ExceptionFlags.overflow;
                goto default;
            default:
                data = isNegative ? (MASK_INF | MASK_SGN) : MASK_INF;
                break;
        }
        return ExceptionFlags.overflow;
    }

    @nogc nothrow pure @safe
    ExceptionFlags infinityPack(const bool isNegative)
    {
        data = isNegative ? (MASK_INF | MASK_SGN) : MASK_INF;
        return ExceptionFlags.none;
    }

    //packs zero or min, depending on the rounding mode
    @nogc nothrow pure @safe
    ExceptionFlags underflowPack(const bool isNegative, const RoundingMode mode)
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

    //packs $(B NaN)
    @nogc nothrow pure @safe
    ExceptionFlags invalidPack(const bool isNegative, const U payload)
    {
        data = isNegative ? (MASK_QNAN | (payload & MASK_PAYL) | MASK_SGN) : (MASK_QNAN | (payload & MASK_PAYL));
        return ExceptionFlags.invalidOperation;
    }

    //packs infinity
    @nogc nothrow pure @safe
    ExceptionFlags div0Pack(const bool isNegative)
    {
        data = isNegative ? (MASK_INF | MASK_SGN) : MASK_INF;
        return ExceptionFlags.divisionByZero;
    }

    @nogc nothrow pure @safe
    ExceptionFlags adjustedPack(T)(const T coefficient, const int exponent, const bool isNegative,
        const int precision, const RoundingMode mode,
        const ExceptionFlags previousFlags = ExceptionFlags.none)
    {
        if (!errorPack(isNegative, previousFlags, precision, mode, cvt!U(coefficient)))
        {
            const bool stickyUnderflow = coefficient && (exponent < int.max - EXP_BIAS && exponent + EXP_BIAS < PRECISION - 1 && prec(coefficient) < PRECISION - (exponent + EXP_BIAS));
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

    @nogc nothrow pure @safe
    static int realPrecision(const int precision)
    {
        if (precision <= 0 || precision > PRECISION)
            return PRECISION;
        else
            return precision;
    }

    ExceptionFlags packIntegral(T)(const T value, const int precision, const RoundingMode mode) @nogc nothrow pure @safe
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
                bool isNegative = void;
                V coefficient = unsign!V(value, isNegative);
            }
            else
            {
                bool isNegative = false;
                V coefficient = value;
            }
            int exponent = 0;
            const flags = coefficientAdjust(coefficient, exponent, cvt!V(COEF_MAX), isNegative, mode);
            return adjustedPack(cvt!U(coefficient), exponent, isNegative, precision, mode, flags);
        }
    }

    ExceptionFlags packFloatingPoint(T)(const T value, const int precision, const RoundingMode mode) @nogc nothrow pure @safe
    if (isFloatingPoint!T)
    {
        ExceptionFlags flags;
        DataType!D cx; int ex; bool sx;
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
                enum fltTargetPrecision = maxPrecision!T();
                auto targetPrecision = realPrecision(precision);
                if (targetPrecision > fltTargetPrecision)
                    targetPrecision = fltTargetPrecision;
                flags |= coefficientAdjust(cx, ex, targetPrecision, sx, mode);
                flags = adjustedPack(cx, ex, sx, precision, mode, flags);
                // We want less precision?
                if (precision < fltTargetPrecision && flags == ExceptionFlags.inexact)
                    return ExceptionFlags.none;
                else
                    return flags;
            default:
                assert(0);
        }
    }

    ExceptionFlags packString(C)(scope const(C)[] value, const int precision, const RoundingMode mode)
    if (isSomeChar!C)
    {
        U coefficient;
        bool isinf, isnan, issnan, isnegative, wasHex;
        int exponent;
        const(C)[] ss = value;
        auto flags = parseDecimal(ss, coefficient, exponent, isinf, isnan, issnan, isnegative, wasHex);

        if (!ss.empty)
            return invalidPack(isnegative, coefficient) | flags;

        if (flags & ExceptionFlags.invalidOperation)
            return invalidPack(isnegative, coefficient) | flags;

        if (issnan)
            data = MASK_SNAN | (coefficient & MASK_PAYL);
        else if (isnan)
            data = MASK_QNAN | (coefficient & MASK_PAYL);
        else if (isinf)
            data = MASK_INF;
        else
        {
            if (!wasHex)
                return adjustedPack(coefficient, exponent, isnegative, precision, mode, flags);
            else
                return flags | checkedPack(coefficient, exponent, isnegative, precision, mode, true);
        }

        if (isnegative)
            data |= MASK_SGN;

        return flags;
    }

    ExceptionFlags packRange(R)(ref R range, const int precision, const RoundingMode mode)
    if (isInputRange!R && isSomeChar!(ElementType!R) && !isSomeString!range)
    {
        U coefficient;
        bool isinf, isnan, issnan, isnegative, wasHex;
        int exponent;
        auto flags = parseDecimal(range, coefficient, exponent, isinf, isnan, issnan, isnegative, wasHex);

        if (!ss.empty)
            flags |= ExceptionFlags.invalidOperation;

        if (flags & ExceptionFlags.invalidOperation)
        {
            packErrors(isnegative, flags, coefficient);
            return flags;
        }

        if (issnan)
            data = MASK_SNAN | (coefficient & MASK_PAYL);
        else if (isnan)
            data = MASK_QNAN | (coefficient & MASK_PAYL);
        else if (isinf)
            data = MASK_INF;
        if (flags & ExceptionFlags.underflow)
            data = MASK_ZERO;
        else if (flags & ExceptionFlags.overflow)
            data = MASK_INF;
        else
        {
            flags |= adjustCoefficient(coefficient, exponent, EXP_MIN, EXP_MAX, COEF_MAX, isnegative, mode);
            flags |= adjustPrecision(coefficient, exponent, EXP_MIN, EXP_MAX, precision, isnegative, mode);
        }

        if (flags & ExceptionFlags.underflow)
            data = MASK_ZERO;
        else if (flags & ExceptionFlags.overflow)
            data = MASK_INF;

        if (isnegative)
            data |= MASK_SGN;

        return flags;
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

    static if (bits == 128)
    {
        enum maxFloat   = buildin(s_max_float);
        enum maxDouble  = buildin(s_max_double);
        enum maxReal    = buildin(s_max_real);
        enum minFloat   = buildin(s_min_float);
        enum minDouble  = buildin(s_min_double);
        enum minReal    = buildin(s_min_real);
    }

    enum SQRT3          = buildin(s_sqrt3);
    enum M_SQRT3        = buildin(s_m_sqrt3);
    enum PI_3           = buildin(s_pi_3);
    enum PI_6           = buildin(s_pi_6);
    enum _5PI_6         = buildin(s_5pi_6);
    enum _3PI_4         = buildin(s_3pi_4);
    enum _2PI_3         = buildin(s_2pi_3);
    enum SQRT3_2        = buildin(s_sqrt3_2);
    enum SQRT2_2        = buildin(s_sqrt2_2);
    enum onethird       = buildin(s_onethird);
    enum twothirds      = buildin(s_twothirds);
    enum _5_6           = buildin(s_5_6);
    enum _1_6           = buildin(s_1_6);
    enum M_1_2PI        = buildin(s_m_1_2pi);
    enum PI2            = buildin(s_pi2);
}

///Shorthand notations for $(MYREF Decimal) types
alias Decimal32 = Decimal!32;
///ditto
alias Decimal64 = Decimal!64;
///ditto
alias Decimal128 = Decimal!128;

///Returns true if all specified types are Decimal... types.
template isDecimal(T...)
{
    enum isDecimal =
    {
        bool result = T.length > 0;
        static foreach (t; T)
        {
            if (!(is(t == Decimal32) || is(t == Decimal64) || is(t == Decimal128)))
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
    static assert(!isDecimal!int);
    static assert(!isDecimal!(Decimal128, byte));
}

@("Compilation tests")
unittest
{
    struct DumbRange(C)
    {
        bool empty;
        C front;
        void popFront() {}
    }

    alias DecimalTypes = TypeTuple!(Decimal32, Decimal64, Decimal128);
    alias IntegralTypes = TypeTuple!(byte, short, int, long, ubyte, ushort, uint, ulong);
    alias FloatTypes = TypeTuple!(float, double, real);
    alias CharTypes = TypeTuple!(char, wchar, dchar);
    alias StringTypes = TypeTuple!(string, wstring, dstring);
    alias RangeTypes = TypeTuple!(DumbRange!char, DumbRange!wchar, DumbRange!dchar);

    auto x = Decimal32(double.nan);

    //constructors
    foreach (D; DecimalTypes)
    {
        foreach (T; DecimalTypes)
            static assert (is(typeof(D(T.init)) == D));
        foreach (T; IntegralTypes)
            static assert (is(typeof(D(T.init)) == D));
        foreach (T; FloatTypes)
            static assert (is(typeof(D(T.init)) == D));
        foreach (T; CharTypes)
            static assert (is(typeof(D(T.init)) == D));
        foreach (T; StringTypes)
            static assert (is(typeof(D(T.init)) == D));
        static assert (is(typeof(D(true)) == D));
    }

    //assignment
    foreach (D; DecimalTypes)
    {
        foreach (T; DecimalTypes)
            static assert (__traits(compiles, { D d = T.init; }));
        foreach (T; IntegralTypes)
            static assert (__traits(compiles, { D d = T.init; }));
        foreach (T; FloatTypes)
            static assert (__traits(compiles, { D d = T.init; }));
        foreach (T; CharTypes)
            static assert (__traits(compiles, { D d = T.init; }));
        foreach (T; StringTypes)
            static assert (__traits(compiles, { D d = T.init; }));
        static assert (__traits(compiles, { D d = true; }));
    }

    auto b = cast(float)Decimal32();
    //cast
    foreach (D; DecimalTypes)
    {
        foreach (T; DecimalTypes)
            static assert (is(typeof(cast(T)(D.init)) == T));
        foreach (T; IntegralTypes)
            static assert (is(typeof(cast(T)(D.init)) == T));
        foreach (T; FloatTypes)
            static assert (is(typeof(cast(T)(D.init)) == T));
        foreach (T; CharTypes)
            static assert (is(typeof(cast(T)(D.init)) == T));
        static assert (is(typeof(cast(bool)(D.init)) == bool));
    }

    //unary ops
    foreach (D; DecimalTypes)
    {
        static assert(is(typeof(+D.init) == const D));
        static assert(is(typeof(-D.init) == D));
        static assert(is(typeof(++D.init) == D));
        static assert(is(typeof(--D.init) == D));
    }

    //equality
    foreach (D; DecimalTypes)
    {
        foreach (T; DecimalTypes)
            static assert (is(typeof(D.init == T.init) == bool));
        foreach (T; IntegralTypes)
            static assert (is(typeof(D.init == T.init) == bool));
        foreach (T; FloatTypes)
            static assert (is(typeof(D.init == cast(T)0.0) == bool));
        foreach (T; CharTypes)
            static assert (is(typeof(D.init == T.init) == bool));
    }

    auto c = Decimal128() > 0.0;

    //comparison
    foreach (D; DecimalTypes)
    {
        foreach (T; DecimalTypes)
            static assert (is(typeof(D.init > T.init) == bool));
        foreach (T; IntegralTypes)
            static assert (is(typeof(D.init > T.init) == bool));
        foreach (T; FloatTypes)
            static assert (is(typeof(D.init > cast(T)0.0) == bool));
        foreach (T; CharTypes)
            static assert (is(typeof(D.init > T.init) == bool));
    }

    //binary left
    foreach (D; DecimalTypes)
    {
        foreach (T; DecimalTypes)
        {
            static assert (is(typeof(D.init + T.init) == CommonDecimal!(D, T)));
            static assert (is(typeof(D.init - T.init) == CommonDecimal!(D, T)));
            static assert (is(typeof(D.init * T.init) == CommonDecimal!(D, T)));
            static assert (is(typeof(D.init / T.init) == CommonDecimal!(D, T)));
            static assert (is(typeof(D.init % T.init) == CommonDecimal!(D, T)));
            // pragma(msg, typeof(D.init ^^ T.init).stringof);
            // pragma(msg, CommonDecimal!(D, T).stringof);
            static assert (is(typeof(D.init ^^ T.init) == CommonDecimal!(D, T)));
        }

        foreach (T; IntegralTypes)
        {
            static assert (is(typeof(D.init + T.init) == D));
            static assert (is(typeof(D.init - T.init) == D));
            static assert (is(typeof(D.init * T.init) == D));
            static assert (is(typeof(D.init / T.init) == D));
            static assert (is(typeof(D.init % T.init) == D));
            static assert (is(typeof(D.init ^^ T.init) == D));
        }

        auto z = Decimal32.nan + float.nan;

        foreach (T; FloatTypes)
        {
            static assert (is(typeof(D.init + T.init) == D));
            static assert (is(typeof(D.init - T.init) == D));
            static assert (is(typeof(D.init * T.init) == D));
            static assert (is(typeof(D.init / T.init) == D));
            static assert (is(typeof(D.init % T.init) == D));
            static assert (is(typeof(D.init ^^ T.init) == D));
        }

        foreach (T; CharTypes)
        {
            static assert (is(typeof(D.init + T.init) == D));
            static assert (is(typeof(D.init - T.init) == D));
            static assert (is(typeof(D.init * T.init) == D));
            static assert (is(typeof(D.init / T.init) == D));
            static assert (is(typeof(D.init % T.init) == D));
            static assert (is(typeof(D.init ^^ T.init) == D));
        }
    }

    //binary right
    foreach (D; DecimalTypes)
    {
        foreach (T; DecimalTypes)
        {
            static assert (is(typeof(T.init + D.init) == CommonDecimal!(D, T)));
            static assert (is(typeof(T.init - D.init) == CommonDecimal!(D, T)));
            static assert (is(typeof(T.init * D.init) == CommonDecimal!(D, T)));
            static assert (is(typeof(T.init / D.init) == CommonDecimal!(D, T)));
            static assert (is(typeof(T.init % D.init) == CommonDecimal!(D, T)));
            static assert (is(typeof(T.init ^^ D.init) == CommonDecimal!(D, T)));
        }


        foreach (T; IntegralTypes)
        {
            static assert (is(typeof(T.init + D.init) == D));
            static assert (is(typeof(T.init - D.init) == D));
            static assert (is(typeof(T.init * D.init) == D));
            static assert (is(typeof(T.init / D.init) == D));
            static assert (is(typeof(T.init % D.init) == D));
            static assert (is(typeof(T.init ^^ D.init) == D));
        }

        foreach (T; FloatTypes)
        {
            static assert (is(typeof(T.init + D.init) == D));
            static assert (is(typeof(T.init - D.init) == D));
            static assert (is(typeof(T.init * D.init) == D));
            static assert (is(typeof(T.init / D.init) == D));
            static assert (is(typeof(T.init % D.init) == D));
            static assert (is(typeof(T.init ^^ D.init) == D));
        }

        foreach (T; CharTypes)
        {
            static assert (is(typeof(T.init + D.init) == D));
            static assert (is(typeof(T.init - D.init) == D));
            static assert (is(typeof(T.init * D.init) == D));
            static assert (is(typeof(T.init / D.init) == D));
            static assert (is(typeof(T.init % D.init) == D));
            static assert (is(typeof(T.init ^^ D.init) == D));
        }
    }

    //op assignment
    foreach (D; DecimalTypes)
    {
        foreach (T; DecimalTypes)
        {
            static assert (is(typeof(D.init += T.init) == D));
            static assert (is(typeof(D.init -= T.init) == D));
            static assert (is(typeof(D.init *= T.init) == D));
            static assert (is(typeof(D.init /= T.init) == D));
            static assert (is(typeof(D.init %= T.init) == D));
            static assert (is(typeof(D.init ^^= T.init) == D));
        }

        foreach (T; IntegralTypes)
        {
           static assert (is(typeof(D.init += T.init) == D));
            static assert (is(typeof(D.init -= T.init) == D));
            static assert (is(typeof(D.init *= T.init) == D));
            static assert (is(typeof(D.init /= T.init) == D));
            static assert (is(typeof(D.init %= T.init) == D));
            static assert (is(typeof(D.init ^^= T.init) == D));
        }

        foreach (T; FloatTypes)
        {
            static assert (is(typeof(D.init += T.init) == D));
            static assert (is(typeof(D.init -= T.init) == D));
            static assert (is(typeof(D.init *= T.init) == D));
            static assert (is(typeof(D.init /= T.init) == D));
            static assert (is(typeof(D.init %= T.init) == D));
            static assert (is(typeof(D.init ^^= T.init) == D));
        }

        foreach (T; CharTypes)
        {
            static assert (is(typeof(D.init += T.init) == D));
            static assert (is(typeof(D.init -= T.init) == D));
            static assert (is(typeof(D.init *= T.init) == D));
            static assert (is(typeof(D.init /= T.init) == D));
            static assert (is(typeof(D.init %= T.init) == D));
            static assert (is(typeof(D.init ^^= T.init) == D));
        }
    }

    //expected constants
    foreach (D; DecimalTypes)
    {
        static assert (is(typeof(D.init) == D));
        static assert (is(typeof(D.nan) == D));
        static assert (is(typeof(D.infinity) == D));
        static assert (is(typeof(D.max) == D));
        static assert (is(typeof(D.min_normal) == D));
        static assert (is(typeof(D.epsilon) == D));
        static assert (is(typeof(D.dig) == int));
        static assert (is(typeof(D.mant_dig) == int));
        static assert (is(typeof(D.min_10_exp) == int));
        static assert (is(typeof(D.max_10_exp) == int));
        static assert (is(typeof(D.min_exp) == int));
        static assert (is(typeof(D.max_exp) == int));

        static assert (is(typeof(D.E) == D));
        static assert (is(typeof(D.PI) == D));
        static assert (is(typeof(D.PI_2) == D));
        static assert (is(typeof(D.PI_4) == D));
        static assert (is(typeof(D.M_1_PI) == D));
        static assert (is(typeof(D.M_2_PI) == D));
        static assert (is(typeof(D.M_2_SQRTPI) == D));
        static assert (is(typeof(D.LN10) == D));
        static assert (is(typeof(D.LN2) == D));
        static assert (is(typeof(D.LOG2) == D));
        static assert (is(typeof(D.LOG2E) == D));
        static assert (is(typeof(D.LOG2T) == D));
        static assert (is(typeof(D.LOG10E) == D));
        static assert (is(typeof(D.SQRT2) == D));
        static assert (is(typeof(D.SQRT1_2) == D));
    }

    //expected members
    foreach (D; DecimalTypes)
    {
        static assert (is(typeof(D.init.toHash()) == size_t));
        static assert (is(typeof(D.init.toString()) == string));
    }
}

@("Decimal should support decimal + float")
unittest
{
    immutable expected = Decimal128("2");

    auto sut = Decimal128("1");
    auto result = sut + 1.0f;

    assert(expected == result);
}

@("Decimal should support decimal - float")
unittest
{
    immutable expected = Decimal128("5");

    auto sut = Decimal128("9");
    auto result = sut - 4.0f;

    assert(expected == result);
}

@("Decimal should support decimal * float")
unittest
{
    immutable expected = Decimal128("13.3");

    auto sut = Decimal128("1.33");
    auto result = sut * 10.0f;

    assert(expected == result);
}

@("Decimal should support decimal / float")
unittest
{
    immutable expected = Decimal128("0.5");

    auto sut = Decimal128("1");
    auto result = sut / 2.0f;

    assert(expected == result);
}

@("Decimal should support decimal % float")
unittest
{
    immutable expected = Decimal128("1");

    auto sut = Decimal128("10");
    auto result = sut % 3.0f;

    assert(expected == result);
}

@("Decimal should support decimal + integral")
unittest
{
    immutable expected = Decimal128("3");

    auto sut = Decimal128("2");
    auto result = sut + 1;

    assert(expected == result);
}

@("Decimal should support decimal - integral")
unittest
{
    immutable expected = Decimal128("1");

    auto sut = Decimal128("3");
    auto result = sut - 2;

    assert(expected == result);
}

@("Decimal should support decimal * integral")
unittest
{
    immutable expected = Decimal128("123.4");

    auto sut = Decimal128("12.34");
    auto result = sut * 10;

    assert(expected == result);
}

@("Decimal should support decimal / integral")
unittest
{
    immutable expected = Decimal128("0.5");

    auto sut = Decimal128("1");
    auto result = sut / 2;

    assert(expected == result);
}

@("Decimal should support decimal % integral")
unittest
{
    immutable expected = Decimal128("1");

    auto sut = Decimal128("10");
    auto result = sut % 3;

    assert(expected == result);
}

@("Decimal should support decimal % unsigned integral")
unittest
{
    immutable expected = Decimal128("1");

    auto sut = Decimal128("10");
    auto result = sut % 3u;

    assert(expected == result);
}

///Returns the most wide Decimal... type among the specified types
template CommonDecimal(T...)
if (isDecimal!T)
{
    static if (T.length == 0)
        alias CommonDecimal = Decimal128;
    else static if (T.length == 1)
        alias CommonDecimal = T[0];
    else static if (T.length == 2)
    {
        static if (T[0].sizeof > T[1].sizeof)
            alias CommonDecimal = T[0];
        else
            alias CommonDecimal = T[1];
    }
    else
        alias CommonDecimal = CommonDecimal!(CommonDecimal!(T[0 .. 1], CommonDecimal!(T[2 .. $])));
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

version(D_BetterC)
{}
else
{
    ///Root object for all _decimal exceptions
    abstract class DecimalException : Exception
    {
        mixin ExceptionConstructors;
    }

    ///Thrown if any operand of a _decimal operation is not a number or si not finite
    class InvalidOperationException : DecimalException
    {
	    mixin ExceptionConstructors;
    }

    ///Thrown if the denominator of a _decimal division operation is zero.
    class DivisionByZeroException : DecimalException
    {
	    mixin ExceptionConstructors;
    }

    ///Thrown if the result of a _decimal operation exceeds the largest finite number of the destination format.
    class OverflowException : DecimalException
    {
	    mixin ExceptionConstructors;
    }

    ///Thrown if the result of a _decimal operation is smaller the smallest finite number of the destination format.
    class UnderflowException : DecimalException
    {
	    mixin ExceptionConstructors;
    }

    ///Thrown if the result of a _decimal operation was rounded to fit in the destination format.
    class InexactException : DecimalException
    {
	    mixin ExceptionConstructors;
    }
}

///IEEE-754-2008 floating point categories
enum DecimalClass : byte
{
    ///a signalling $(B NaN) represents most of the time an uninitialized variable;
    ///a quiet $(B NaN) represents the result of an invalid operation
    signalingNaN,
    ///ditto
    quietNaN,
    ///value represents infinity
    negativeInfinity,
    ///ditto
    positiveInfinity,
    ///value represents a normalized _decimal value
    negativeNormal,
    ///ditto
    positiveNormal,
    ///value represents a subnormal _decimal value
    negativeSubnormal,
    ///ditto
    positiveSubnormal,
    ///value is 0
    negativeZero,
    ///ditto
    positiveZero,
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
DecimalClass decimalClass(D)(auto const ref D x)
if (isDecimal!D)
{
    DataType!D coefficient;
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
    foreach(T; TypeTuple!(Decimal32, Decimal64, Decimal128))
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

///IEEE-754-2008 subset of floating point categories
enum DecimalSubClass : byte
{
    signalingNaN,
    quietNaN,
    negativeInfinity,
    positiveInfinity,
    finite,
}

/**
Returns the decimal class where x falls into.
This operation is silent, no exception flags are set and no exceptions are thrown.
Params:
    x = a _decimal value
Returns:
    One of the members of $(MYREF DecimalSubClass) enumeration
*/
DecimalSubClass decimalSubClass(D)(auto const ref D x)
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
bool approxEqual(D1, D2, D3, D4)(auto const ref D1 x, auto const ref D2 y,
    auto const ref D3 maxRelDiff, auto const ref D4 maxAbsDiff) @nogc nothrow @safe
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
bool approxEqual(D1, D2, D3)(auto const ref D1 x, auto const ref D2 y,
    auto const ref D3 maxRelDiff) @nogc nothrow @safe
if (isDecimal!(D1, D2, D3))
{
    enum maxAbsDiff = CommonDecimal!(D1, D2, D3)("1e-5");
    return approxEqual(x, y, maxRelDiff, maxAbsDiff);
}

///ditto
bool approxEqual(D1, D2)(auto const ref D1 x, auto const ref D2 y) @nogc nothrow @safe
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
float cmp(D1, D2)(auto const ref D1 x, auto const ref D2 y) @nogc nothrow pure @safe
if (isDecimal!(D1, D2))
{
    static if (is(D1 : D2))
    {
        if (x.data == y.data)
            return 0;
    }

    alias U = CommonStorage!(D1, D2);
    U cx, cy; int ex, ey; bool sx, sy;
    const fx = fastDecode(x, cx, ex, sx);
    const fy = fastDecode(y, cy, ey, sy);

    if (sx != sy)
        return sx ? -1 : 1;

    if (fx == FastClass.quietNaN)
    {
        if (fy == FastClass.quietNaN)
        {
            if (cx > cy)
                return sx ? -1 : 1;
            else if (cx < cy)
                return sx ? 1 : -1;
            return 0;
        }
        return sx ? -1 : 1;
    }

    if (fy == FastClass.quietNaN)
        return sx ? 1 : -1;

    if (fx == FastClass.signalingNaN)
    {
        if (fy == FastClass.signalingNaN)
        {
            if (cx > cy)
                return sx ? -1 : 1;
            else if (cx < cy)
                return sx ? 1 : -1;
            return 0;
        }
        return sx ? -1 : 1;
    }

    if (fy == FastClass.signalingNaN)
        return sx ? 1 : -1;

    if (fx == FastClass.infinite)
    {
        if (fy == FastClass.infinite)
            return 0;
        return sx ? -1 : 1;
    }

    if (fy == FastClass.infinite)
        return sx ? 1 : -1;

    //if (fx == FastClass.zero)
    //{
    //    if (fy == FastClass.zero)
    //        return 0;
    //    return sx ? 1 : -1;
    //}
    //
    //if (fy == FastClass.zero)
    //    return sx ? -1 : 1;

    int c = coefficientCmp(cx, ex, cy, ey);

    if (c == 0)
    {
        if (ex > ey)
            c = sx ? -1 : 1;
        else if (ex < ey)
            c = sx ? 1 : -1;
    }
    else if (sx)
        c = -c;

    version (none)
    if (c < -1)
        DecimalControl.setFlags(ExceptionFlags.invalidOperation);

    return c < -1 ? float.nan : cast(float)(c);
}

///
unittest
{
    assert (cmp(-Decimal32.nan, Decimal64.max) == -1);
    assert (cmp(Decimal32.max, Decimal128.min_normal) == 1);
    assert (cmp(Decimal64(0), -Decimal64(0)) == 1);
}

///
float cmp(D, F)(auto const ref D x, auto const ref F y, const int yPrecision, const RoundingMode yMode) @nogc nothrow pure @safe
if (isDecimal!D && isFloatingPoint!F)
{
    const c = decimalCmp(x, y, yPrecision, yMode);

    version (none)
    if (c < -1)
        DecimalControl.setFlags(ExceptionFlags.invalidOperation);

    return c < -1 ? float.nan : cast(float)(c);
}

///
unittest
{
    static Decimal128 toFloatDecimal(long scaleNumber)
    {
        Decimal128 result = scaleNumber;
        result = result / 100L;
        return result;
    }

    assert(cmp(toFloatDecimal(540), 5.40, Precision.banking, RoundingMode.banking) == 0);
    assert(cmp(toFloatDecimal(640), 6.40, Precision.banking, RoundingMode.banking) == 0);
}

///
float cmp(D, I)(auto const ref D x, auto const ref I y) @nogc nothrow pure @safe
if (isDecimal!D && isIntegral!I)
{
    const c = decimalCmp(x, y);

    version (none)
    if (c < -1)
        DecimalControl.setFlags(ExceptionFlags.invalidOperation);

    return c < -1 ? float.nan : cast(float)(c);
}

///
unittest
{
    assert (cmp(Decimal32(540), 540) == 0);
}

/**
Compares two _decimal operands for equality
Returns:
    true if the specified condition is satisfied, false otherwise or if any of the operands is $(B NaN).

version (none)
Notes:
    By default, $(MYREF Decimal.opEquals) is silent, returning false if a $(B NaN) value is encountered.
    isEqual and isNotEqual will throw $(MYREF InvalidOperationException) or will
    set the $(MYREF ExceptionFlags.invalidOperation) context flag if a trap is not set.
*/

@IEEECompliant("compareSignalingEqual", 24)
bool isEqual(D1, D2)(auto const ref D1 x, auto const ref D2 y) @nogc nothrow pure @safe
if (isDecimal!(D1, D2))
{
    const c = decimalEqu(x, y);

    // Not accept NaN?
    version (none)
    if (c < -1)
        DecimalControl.setFlags(ExceptionFlags.invalidOperation);

    return c == 1;
}

///
unittest
{
    assert (isEqual(Decimal32.max, Decimal32.max));
    assert (isEqual(Decimal64.min, Decimal64.min));
}

@IEEECompliant("compareSignalingEqual", 24)
bool isEqual(D, F)(auto const ref D x, auto const ref F y, const int yPrecision, const RoundingMode yMode) @nogc nothrow pure @safe
if (isDecimal!D && isFloatingPoint!F)
{
    const c = decimalEqu(x, y, yPrecision, yMode);

    // Not accept NaN?
    version (none)
    if (c < -1)
        DecimalControl.setFlags(ExceptionFlags.invalidOperation);

    return c == 1;
}

///
unittest
{
    static Decimal32 toFloatDecimal(int scaleNumber)
    {
        Decimal32 result = scaleNumber;
        result = result / 100;
        return result;
    }

    assert (isEqual(toFloatDecimal(540), 5.40, Precision.banking, RoundingMode.banking));
}

@IEEECompliant("compareSignalingEqual", 24)
bool isEqual(D, I)(auto const ref D x, auto const ref I y) @nogc nothrow pure @safe
if (isDecimal!D && isIntegral!I)
{
    const c = decimalEqu(x, y);

    // Not accept NaN?
    version (none)
    if (c < -1)
        DecimalControl.setFlags(ExceptionFlags.invalidOperation);

    return c == 1;
}

///
unittest
{
    assert (isEqual(Decimal32(540), 540));
}

///ditto
@IEEECompliant("compareSignalingNotEqual", 24)
bool isNotEqual(D1, D2)(auto const ref D1 x, auto const ref D2 y) @nogc nothrow pure @safe
if (isDecimal!(D1, D2))
{
    const c = decimalEqu(x, y);

    if (c < -1)
    {
        version (none)
        DecimalControl.setFlags(ExceptionFlags.invalidOperation);

        return false;
    }

    return c != 1;
}

///
unittest
{
    assert (isNotEqual(Decimal32.max, Decimal32.min));
    assert (isNotEqual(Decimal32.max, Decimal32.min_normal));
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
bool isGreater(D1, D2)(auto const ref D1 x, auto const ref D2 y) @nogc nothrow pure @safe
if (isDecimal!(D1, D2))
{
    const c = decimalCmp(x, y);

    version (none)
    if (c < -1)
        DecimalControl.setFlags(ExceptionFlags.invalidOperation);

    return c > 0;
}

///ditto
@IEEECompliant("compareQuietGreaterEqual", 24)
bool isGreaterOrEqual(D1, D2)(auto const ref D1 x, auto const ref D2 y) @nogc nothrow pure @safe
if (isDecimal!(D1, D2))
{
    const c = decimalCmp(x, y);

    version (none)
    if (c < -1)
        DecimalControl.setFlags(ExceptionFlags.invalidOperation);

    return c >= 0;
}

///ditto
@IEEECompliant("compareQuietGreaterUnordered", 24)
bool isGreaterOrUnordered(D1, D2)(auto const ref D1 x, auto const ref D2 y) @nogc nothrow pure @safe
if (isDecimal!(D1, D2))
{
    const c = decimalCmp(x, y);

    if (c == -3)
    {
        version (none)
        DecimalControl.setFlags(ExceptionFlags.invalidOperation);

        return false;
    }

    return c > 0 || c < -1;
}

///ditto
@IEEECompliant("compareQuietLess", 24)
@IEEECompliant("compareQuietNotLess", 24)
bool isLess(D1, D2)(auto const ref D1 x, auto const ref D2 y) @nogc nothrow pure @safe
if (isDecimal!(D1, D2))
{
    const c = decimalCmp(x, y);

    version (none)
    if (c < -1)
        DecimalControl.setFlags(ExceptionFlags.invalidOperation);

    return c == -1;
}

///ditto
@IEEECompliant("compareQuietLessEqual", 24)
bool isLessOrEqual(D1, D2)(auto const ref D1 x, auto const ref D2 y) @nogc nothrow pure @safe
if (isDecimal!(D1, D2))
{
    const c = decimalCmp(x, y);

    if (c < -1)
    {
        version (none)
        DecimalControl.setFlags(ExceptionFlags.invalidOperation);

        return false;
    }

    return c <= 0 && c > -2;
}

///ditto
@IEEECompliant("compareQuietLessUnordered", 24)
bool isLessOrUnordered(D1, D2)(auto const ref D1 x, auto const ref D2 y) @nogc nothrow pure @safe
if (isDecimal!(D1, D2))
{
    const c = decimalCmp(x, y);

    if (c == -3)
    {
        version (none)
        DecimalControl.setFlags(ExceptionFlags.invalidOperation);

        return false;
    }

    return c < 0;
}

///ditto
@IEEECompliant("compareQuietOrdered", 24)
@IEEECompliant("compareQuietUnordered", 24)
bool isUnordered(D1, D2)(auto const ref D1 x, auto const ref D2 y) @nogc nothrow pure @safe
if (isDecimal!(D1, D2))
{
    const c = decimalCmp(x, y);

    version (none)
    if (c == -3)
        DecimalControl.setFlags(ExceptionFlags.invalidOperation);

    return c < -1;
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
    foreach(T; TypeTuple!(Decimal32, Decimal64, Decimal128))
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
auto compound(D)(auto const ref D x, const int n)
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
    foreach(T; TypeTuple!(Decimal32, Decimal64, Decimal128))
    {
        assert (compound(T.ten, 0) == 1);
        assert (compound(T.infinity, 0) == 1);
        assert (compound(-T.one, 0) == 1);
        assert (compound(T.zero, 0) == 1);
        assert (compound(-T.one, 5) == 0);
        assert (compound(T.infinity, 5) == T.infinity);
    }
}

///
unittest
{
    Decimal32 x = "0.2";
    assert (compound(x, 2) == Decimal32("1.44"));
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
D1 copysign(D1, D2)(auto const ref D1 to, auto const ref D2 from)
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
D acos(D)(auto const ref D x)
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
    assert(acos(x) == Decimal32.PI_2);
}

unittest
{
    foreach(T; TypeTuple!(Decimal32, Decimal64, Decimal128))
    {
        assert (acos(-T.one) == T.PI);
        assert (acos(T.one) == 0);
        assert (acos(T.zero) == T.PI_2);
        assert (acos(T.nan).isNaN);
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
D acosh(D)(auto const ref D x)
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
    assert (acosh(x) == 0);
}

unittest
{
    foreach(T; TypeTuple!(Decimal32, Decimal64, Decimal128))
    {
        assert (acosh(T.one) == T.zero);
        assert (acosh(T.infinity) == T.infinity);
        assert (acosh(T.nan).isNaN);
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
D cos(D)(auto const ref D x)
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
D cosh(D)(auto const ref D x)
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
D cospi(D)(auto const ref D x)
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
D asin(D)(auto const ref D x)
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
    assert(asin(x) == Decimal32.PI_2);
    assert(asin(-x) == -Decimal32.PI_2);
}

unittest
{
    foreach(T; TypeTuple!(Decimal32, Decimal64, Decimal128))
    {
        assert (asin(-T.one) == -T.PI_2);
        assert (asin(T.zero) == 0);
        assert (asin(T.one) == T.PI_2);
        assert (asin(T.nan).isNaN);
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
D asinh(D)(auto const ref D x)
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
    assert (asinh(x) == 0);
}

unittest
{
    foreach(T; TypeTuple!(Decimal32, Decimal64, Decimal128))
    {
        assert (asinh(T.zero) == T.zero);
        assert (asinh(T.infinity) == T.infinity);
        assert (asinh(T.nan).isNaN);
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
D atan(D)(auto const ref D x)
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
    assert(atan(radians) == Decimal32.PI_4);
}

unittest
{
    foreach(T; TypeTuple!(Decimal32, Decimal64, Decimal128))
    {
        assert (isIdentical(atan(T.zero), T.zero));
        assert (isIdentical(atan(-T.zero), -T.zero));
        assert (isIdentical(atan(T.infinity), T.PI_2));
        assert (isIdentical(atan(-T.infinity), -T.PI_2));
        assert (atan(T.nan).isNaN);
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
auto atan2(D1, D2)(auto const ref D1 y, auto const ref D2 x)
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
    assert (atan2(y, x) == Decimal32.PI_2);
}

unittest
{
    foreach(T; TypeTuple!(Decimal32, Decimal64, Decimal128))
    {
        assert (atan2(T.nan, T.zero).isNaN);
        assert (atan2(T.one, T.nan).isNaN);
        assert (atan2(T.zero, -T.zero) == T.PI);
        assert (atan2(-T.zero, -T.zero) == -T.PI);
        assert (atan2(T.zero, T.zero) == T.zero);
        assert (atan2(-T.zero, T.zero) == -T.zero);
        assert (atan2(T.zero, -T.one) == T.PI);
        assert (atan2(-T.zero, -T.one) == -T.PI);
        assert (atan2(T.zero, T.one) == T.zero);
        assert (atan2(-T.zero, T.one) == -T.zero);
        assert (atan2(-T.one, T.zero) == -T.PI_2);
        assert (atan2(T.one, T.zero) == T.PI_2);
        assert (atan2(T.one, -T.infinity) == T.PI);
        assert (atan2(-T.one, -T.infinity) == -T.PI);
        assert (atan2(T.one, T.infinity) == T.zero);
        assert (atan2(-T.one, T.infinity) == -T.zero);
        assert (atan2(-T.infinity, T.one) == -T.PI_2);
        assert (atan2(T.infinity, T.one) == T.PI_2);
        assert (atan2(-T.infinity, -T.infinity) == -T._3PI_4);
        assert (atan2(T.infinity, -T.infinity) == T._3PI_4);
        assert (atan2(-T.infinity, T.infinity) == -T.PI_4);
        assert (atan2(T.infinity, T.infinity) == T.PI_4);
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
auto atan2pi(D1, D2)(auto const ref D1 y, auto const ref D2 x)
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
    assert (atan2pi(y, x) == Decimal32("0.5"));
}

unittest
{
    foreach(T; TypeTuple!(Decimal32, Decimal64, Decimal128))
    {
        assert (atan2(T.nan, T.zero).isNaN);
        assert (atan2(T.one, T.nan).isNaN);
        assert (atan2pi(T.zero, -T.zero) == T.one);
        assert (atan2pi(-T.zero, -T.zero) == -T.one);
        assert (atan2pi(T.zero, T.zero) == T.zero);
        assert (atan2pi(-T.zero, T.zero) == -T.zero);
        assert (atan2pi(T.zero, -T.one) == T.one);
        assert (atan2pi(-T.zero, -T.one) == -T.one);
        assert (atan2pi(T.zero, T.one) == T.zero);
        assert (atan2pi(-T.zero, T.one) == -T.zero);
        assert (atan2pi(-T.one, T.zero) == -T.half);
        assert (atan2pi(T.one, T.zero) == T.half);
        assert (atan2pi(T.one, -T.infinity) == T.one);
        assert (atan2pi(-T.one, -T.infinity) == -T.one);
        assert (atan2pi(T.one, T.infinity) == T.zero);
        assert (atan2pi(-T.one, T.infinity) == -T.zero);
        assert (atan2pi(-T.infinity, T.one) == -T.half);
        assert (atan2pi(T.infinity, T.one) == T.half);
        assert (atan2pi(-T.infinity, -T.infinity) == -T.threequarters);
        assert (atan2pi(T.infinity, -T.infinity) == T.threequarters);
        assert (atan2pi(-T.infinity, T.infinity) == -T.quarter);
        assert (atan2pi(T.infinity, T.infinity) == T.quarter);
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
D atanh(D)(auto const ref D x)
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
    assert (atanh(x) == 0);
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
D atanpi(D)(auto const ref D x)
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
    assert (atanpi(radians) == Decimal32("0.25"));
}

unittest
{
    foreach(T; TypeTuple!(Decimal32, Decimal64, Decimal128))
    {
        assert (isIdentical(atanpi(T.zero), T.zero));
        assert (isIdentical(atanpi(-T.zero), -T.zero));
        assert (isIdentical(atanpi(T.infinity), T.half));
        assert (isIdentical(atanpi(-T.infinity), -T.half));
        assert (atanpi(T.nan).isNaN);
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
D cbrt(D)(auto const ref D x)
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
    assert (cbrt(x) == 3);
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
D ceil(D)(auto const ref D x)
if (isDecimal!D)
{
    Unqual!D result = x;
    decimalRound(result, 0, RoundingMode.towardPositive);
    return result;
}

///
unittest
{
    assert (ceil(Decimal32("123.456")) == 124);
    assert (ceil(Decimal32("-123.456")) == -123);
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
D exp(D)(auto const ref D x)
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
    assert (exp(power) == Decimal32.E);
}

unittest
{
    foreach(T; TypeTuple!(Decimal32, Decimal64, Decimal128))
    {
        assert (exp(T.zero) == T.one);
        assert (exp(-T.infinity) == T.zero);
        assert (exp(T.infinity) == T.infinity);
        assert (exp(T.nan).isNaN);
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
D exp10(D)(auto const ref D x)
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
D exp10m1(D)(auto const ref D x)
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
D exp2(D)(auto const ref D x)
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
D exp2m1(D)(auto const ref D x)
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
D expm1(D)(auto const ref D x)
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
D fabs(D)(auto const ref D x) @nogc nothrow pure @safe
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
auto fdim(D1, D2)(auto const ref D1 x, auto const ref D2 y)
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

    assert (fdim(x, y) == Decimal32("3.1"));
    assert (fdim(y, x) == 0);
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
D floor(D)(auto const ref D x)
if (isDecimal!D)
{
    Unqual!D result = x;
    decimalRound(result, 0, RoundingMode.towardNegative);
    return result;
}

///
unittest
{
    assert (floor(Decimal32("123.456")) == 123);
    assert (floor(Decimal32("-123.456")) == -124);
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
auto fma(D1, D2, D3)(auto const ref D1 x, auto const ref D2 y, auto const ref D3 z)
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
    assert (fma(x, y, z) == 11);
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
auto fmax(D1, D2)(auto const ref D1 x, auto const ref D2 y)
if (isDecimal!D1 && isDecimal!D2)
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
    assert (fmax(x, y) == 3);
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
auto fmaxAbs(D1, D2)(auto const ref D1 x, auto const ref D2 y)
if (isDecimal!D1 && isDecimal!D2)
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
    assert (fmaxAbs(x, y) == -4);
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
auto fmin(D1, D2)(auto const ref D1 x, auto const ref D2 y)
if (isDecimal!D1 && isDecimal!D2)
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
    assert (fmin(x, y) == -4);
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
auto fminAbs(D1, D2)(auto const ref D1 x, auto const ref D2 y)
if (isDecimal!D1 && isDecimal!D2)
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
    assert (fminAbs(x, y) == 3);
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
auto fmod(D1, D2)(auto const ref D1 x, auto const ref D2 y)
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
    assert (fmod(x, y) == Decimal32("1.7"));
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
D frexp(D)(auto const ref D x, out int y)
{
    DataType!D cx; int ex; bool sx;
    Unqual!D result;
    final switch(fastDecode(x, cx, ex, sx))
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
@nogc nothrow pure @safe
uint getNaNPayload(const Decimal32 x)
{
    return x.data & Decimal32.MASK_PAYL;
}

///ditto
@nogc nothrow pure @safe
ulong getNaNPayload(const Decimal64 x)
{
    return x.data & Decimal64.MASK_PAYL;
}

///ditto
@nogc nothrow pure @safe
ulong getNaNPayload(const Decimal128 x, out ulong payloadHi)
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

    assert (getNaNPayload(x) == 123);
    assert (getNaNPayload(y) == 456);
    ulong hi;
    assert (getNaNPayload(z, hi) == 789 && hi == 0);

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
auto hypot(D1, D2)(auto const ref D1 x, auto const ref D2 y)
if (isDecimal!D1 && isDecimal!D2)
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
    assert (hypot(x, y) == 5);
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
int ilogb(D)(auto const ref D x)
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
    assert (ilogb(Decimal32(1234)) == 3);
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
bool isCanonical(D)(auto const ref D x)
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

    foreach(T; TypeTuple!(Decimal32, Decimal64, Decimal128))
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
    foreach(T; TypeTuple!(Decimal32, Decimal64, Decimal128))
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
bool isIdentical(D)(auto const ref D x, auto const ref D y)
if (isDecimal!D)
{
    return x.data == y.data;
}

///
unittest
{
    assert (isIdentical(Decimal32.min_normal, Decimal32.min_normal));
    assert (!isIdentical(Decimal64("nan"), Decimal64("nan<200>")));
}

///isInfinity
unittest // isInfinity
{
    assert(Decimal32.infinity.isInfinity);
    assert(Decimal32.negInfinity.isInfinity);
    assert(!Decimal128.nan.isInfinity);
}

unittest // isInfinity
{
    foreach(T; TypeTuple!(Decimal32, Decimal64, Decimal128))
    {
        assert(T.infinity.isInfinity);
        assert(T.negInfinity.isInfinity);
        assert((-T.infinity).isInfinity);
        assert(!T.ten.isInfinity);
        assert(!T.sNaN.isInfinity);
        assert(!T.qNaN.isInfinity);
    }
}

///isNaN
unittest // isNaN
{
    assert(Decimal32().isNaN);
    assert(Decimal64.nan.isNaN);
    assert(!Decimal128.max.isNaN);
}

unittest // isNaN
{
    foreach(T; TypeTuple!(Decimal32, Decimal64, Decimal128))
    {
        assert(T.sNaN.isNaN);
        assert(T().isNaN);
        assert(T.qNaN.isNaN);
        assert(!T.ten.isNaN);
        assert(!T.min_normal.isSignalNaN);
    }
}

///isNeg
unittest // isNeg
{
    assert(Decimal32(-1).isNeg);
    assert(Decimal64(-2).isNeg);
    assert(Decimal128(-3).isNeg);

    assert(!Decimal32(0).isNeg);
    assert(!Decimal64(0).isNeg);
    assert(!Decimal128(0).isNeg);

    assert(!Decimal32(1).isNeg);
    assert(!Decimal64(2).isNeg);
    assert(!Decimal128(3).isNeg);
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
bool isNormal(D)(auto const ref D x)
if (isDecimal!D)
{
    DataType!D coefficient;
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

    foreach(T; TypeTuple!(Decimal32, Decimal64, Decimal128))
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
bool isPowerOf10(D)(auto const ref D x)
if (isDecimal!D)
{
    if (x.isNaN || x.isInfinity || x.isZero || signbit(x) != 0U)
        return false;

    alias U = DataType!D;
    U c; int e;
    x.unpack(c, e);
    coefficientShrink(c, e);
    return c == 1U;
}

///
unittest
{
    assert (isPowerOf10(Decimal32("1000")));
    assert (isPowerOf10(Decimal32("0.001")));
}

///isSignalingNaN
unittest // isSignalingNaN
{
    assert(Decimal32().isSignalNaN);
    assert(!Decimal64.nan.isSignalNaN);
    assert(!Decimal128.max.isSignalNaN);
}

unittest // isSignalingNaN
{
    foreach(T; TypeTuple!(Decimal32, Decimal64, Decimal128))
    {
        assert(T.sNaN.isSignalNaN);
        assert(T().isSignalNaN);
        assert(!T.ten.isSignalNaN);
        assert(!T.min_normal.isSignalNaN);
        assert(!T.qNaN.isSignalNaN);
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
bool isSubnormal(D)(auto const ref D x)
if (isDecimal!D)
{
    DataType!D coefficient;
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
    foreach(T; TypeTuple!(Decimal32, Decimal64, Decimal128))
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
    foreach(T; TypeTuple!(Decimal32, Decimal64, Decimal128))
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
D ldexp(D)(auto const ref D x, const int n)
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
    assert (ldexp(d, 3) == 8);
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
D log(D)(auto const ref D x)
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
    assert (log(Decimal32.E) == 1);
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
D log10(D)(auto const ref D x)
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
D log10p1(D)(auto const ref D x)
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
D log2(D)(auto const ref D x)
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
D log2p1(D)(auto const ref D x)
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
D logp1(D)(auto const ref D x)
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
long lrint(D)(auto const ref D x, const RoundingMode mode)
if (isDecimal!D)
{
    enum checkFlags = ExceptionFlags.invalidOperation | ExceptionFlags.inexact;
    long result;
    const flags = decimalToSigned(x, result, mode);
    DecimalControl.raiseFlags(flags & checkFlags);
    return result;
}

///ditto
long lrint(D)(auto const ref D x)
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
long lround(D)(auto const ref D x)
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
D modf(D)(auto const ref D x, ref D y)
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
    result.data = D.MASK_QNAN | (cast(DataType!D)payload & D.MASK_PAYL);
    return result;
}

///ditto
Decimal128 NaN(T)(const T payloadHi, const T payloadLo)
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
D nearbyint(D)(auto const ref D x, const RoundingMode mode)
if (isDecimal!D)
{
    Unqual!D result = x;
    const flags = decimalRound(result, __ctfe ? D.PRECISION : DecimalControl.precision, mode);
    DecimalControl.raiseFlags(flags & ExceptionFlags.invalidOperation);
    return result;
}

///ditto
D nearbyint(D)(auto const ref D x)
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
D nextDown(D)(auto const ref D x)
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
D nextPow10(D)(auto const ref D x)
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
        alias U = DataType!D;
        U c;
        int e;
        bool s = x.unpack(c, e);
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
D1 nextAfter(D1, D2)(auto const ref D1 x, auto const ref D2 y)
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
D nextUp(D)(auto const ref D x)
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
auto poly(D1, D2)(auto const ref D1 x, const(D2)[] a)
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
D pow(D, T)(auto const ref D x, const T n)
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
auto pow(D1, D2)(auto const ref D1 x, auto const ref D2 x)
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
D1 quantize(D1, D2)(auto const ref D1 x, auto const ref D2 y)
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
int quantexp(D)(auto const ref D x)
if (isDecimal!D)
{
    DataType!D cx; int ex; bool sx;
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
    assert (calculatedExponent == 13  && rawExponent == 12);

    //z is 0.0
    frexp(z, calculatedExponent);
    rawExponent = quantexp(z);
    assert (calculatedExponent == 0  && rawExponent == -3);
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
auto remainder(D1, D2)(auto const ref D1 x, auto const ref D2 y)
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
D rint(D)(auto const ref D x, const RoundingMode mode)
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
D rint(D)(auto const ref D x)
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
D rndtonl(D)(auto const ref D x, const RoundingMode mode)
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
D rndtonl(D)(auto const ref D x)
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
D root(D)(auto const ref D x, const T n)
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
D round(D)(auto const ref D x)
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
D rsqrt(D)(auto const ref D x)
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
bool sameQuantum(D1, D2)(auto const ref D1 x, auto const ref D2 y)
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

    const expx = (x.data & D1.MASK_EXT) == D1.MASK_EXT ?
        (x.data & D1.MASK_EXP2) >>> D1.SHIFT_EXP2 :
        (x.data & D1.MASK_EXP1) >>> D1.SHIFT_EXP1;
    const expy = (x.data & D2.MASK_EXT) == D2.MASK_EXT ?
        (y.data & D2.MASK_EXP2) >>> D2.SHIFT_EXP2 :
        (y.data & D2.MASK_EXP1) >>> D2.SHIFT_EXP1;

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
D scalbn(D)(auto const ref D x, const int n)
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

D scaleFrom(D)(auto const ref D value, int scale, RoundingMode roundingMode = RoundingMode.banking) @nogc nothrow pure @safe
if (isDecimal!D)
{
    import std.math : pow;

    alias UD = Unqual!D;
    UD result = value;
	if (scale < 0 && result != 0)
    {
		const UD scaleD = D(pow(10L, -scale), 0, roundingMode);
        decimalDiv(result, scaleD, 0, roundingMode);
    }
    return result;
}

T scaleTo(D, T)(auto const ref D value, int scale, RoundingMode roundingMode = RoundingMode.banking) @nogc nothrow @safe
if (isDecimal!D && (is(T == short) || is(T == int) || is(T == long) || is(T == float) || is(T == double)))
{
    import std.math : pow;

    alias UD = Unqual!D;
    alias UT = Unqual!T;
    UT result = 0;
    static if (is(T == short) || is(T == int) || is(T == long))
    {
        UD scaleResult = value;
        if (scale < 0 && scaleResult != 0)
        {
            const UD scaleD = D(pow(10L, -scale), 0, roundingMode);
            decimalMul(scaleResult, scaleD, 0, roundingMode);
        }
        decimalToSigned(scaleResult, result, roundingMode);
    }
    else
    {
        decimalToFloat(value, result, roundingMode);
    }
    return result;
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
D sgn(D: Decimal!bits, int bits)(auto const ref D x)
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
    foreach(T; TypeTuple!(Decimal32, Decimal64, Decimal128))
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
    foreach(T; TypeTuple!(Decimal32, Decimal64, Decimal128))
    {
        assert(T.sNaN.sign == 1);
        assert(T.negInfinity.sign == -1);
        assert(T.zero.sign == 0);
        assert(T.negZero.sign == -1);
    }
}

/**
Returns the sign bit of the specified value.
This operation is silent, no error flags are set and no exceptions are thrown.
Params:
    x = a _decimal value
Returns:
    1 if the sign bit is set, 0 otherwise
*/
@IEEECompliant("isSignMinus", 25)
int signbit(D: Decimal!bits, int bits)(auto const ref D x)
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
    foreach(T; TypeTuple!(Decimal32, Decimal64, Decimal128))
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
D sin(D)(auto const ref D x)
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
D sinh(D)(auto const ref D x)
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
D sinPi(D)(auto const ref D x)
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
D sqrt(D)(auto const ref D x)
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
D tan(D)(auto const ref D x)
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
D tanh(D)(auto const ref D x)
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
T to(T, D)(auto const ref D x, const RoundingMode mode)
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
F to(F, D)(auto const ref D x, const RoundingMode mode)
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
Decimal32 toDPD(const Decimal32 x)
{
    if (x.isNaN || x.isInfinity || x.isZero)
        return canonical(x);

    uint cx;
    int ex;
    bool sx = x.unpack(cx, ex);

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
Decimal64 toDPD(const Decimal64 x)
{
    if (x.isNaN || x.isInfinity || x.isZero)
        return canonical(x);

    ulong cx;
    int ex;
    bool sx = x.unpack(cx, ex);

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
Decimal128 toDPD(const Decimal128 x)
{
    if (x.isNaN || x.isInfinity || x.isZero)
        return canonical(x);

    uint128 cx;
    int ex;
    bool sx = x.unpack(cx, ex);

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
Decimal32 fromDPD(const Decimal32 x)
{
    if (x.isNaN || x.isInfinity || x.isZero)
        return canonical(x);

    uint[7] digits;
    uint cx;
    int ex;
    bool sx = x.unpack(cx, ex);

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
Decimal64 fromDPD(const Decimal64 x)
{
    if (x.isNaN || x.isInfinity || x.isZero)
        return canonical(x);

    uint[16] digits;
    ulong cx;
    int ex;
    bool sx = x.unpack(cx, ex);

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
Decimal128 fromDPD(const Decimal128 x)
{
    if (x.isNaN || x.isInfinity || x.isZero)
        return canonical(x);

    uint[34] digits;
    uint128 cx;
    int ex;
    bool sx = x.unpack(cx, ex);

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
T toExact(T, D)(auto const ref D x, const RoundingMode mode)
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
F toExact(F, D)(auto const ref D x, const RoundingMode mode)
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
long toMsCurrency(D)(auto const ref D x)
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
D fromMsCurrency(D)(const ulong x)
if (isDecimal!D)
{
    Unqual!D result;
    auto flags = result.packIntegral(result, D.PRECISION, RoundingMode.implicit);
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
DECIMAL toMsDecimal(D)(auto const ref D x)
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

    DataType!D cx;
    int ex;
    bool sx = x.unpack(cx, ex);

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
D fromMsDecimal(D)(auto const ref DECIMAL x)
{
    Unqual!D result;

    uint128 cx = uint128(cast(ulong)(x.Hi32), x.Lo64);
    int ex = -x.scale;
    bool sx = (x.sign & DECIMAL.DECIMAL_NEG) == DECIMAL.DECIMAL_NEG;

    auto flags = coefficientAdjust(cx, ex, cvt!uint128(D.COEF_MAX), RoundingMode.implicit);
    flags |= result.adjustedPack(cvt!(DataType!D)(cx), ex, sx,
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
bool totalOrder(D1, D2)(auto const ref D1 x, auto const ref D2 y)
if (isDecimal!(D1, D2))
{
    return cmp(x, y) <= 0;
}

///ditto
@IEEECompliant("totalOrderAbs", 25)
bool totalOrderAbs(D1, D2)(auto const ref D1 x, auto const ref D2 y)
if (isDecimal!(D1, D2))
{
    return cmp(fabs(x), fabs(y)) <= 0;
}

///
unittest
{
    assert (totalOrder(Decimal32.min_normal, Decimal64.max));
    assert (!totalOrder(Decimal32.max, Decimal128.min_normal));
    assert (totalOrder(-Decimal64(0), Decimal64(0)));
    assert (totalOrderAbs(Decimal64(0), -Decimal64(0)));
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
D trunc(D)(auto const ref D x)
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
D truncPow10(D)(auto const ref D x)
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
        alias U = DataType!D;
        U c;
        int e;
        bool s = x.unpack(c, e);
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
        flags = adjustCoefficient(c, e, D.EXP_MIN, D.EXP_MAX, D.COEF_MAX, s, RoundingMode.towardZero);
        flags |= result.pack(c, e, s, flags);
    }

    if (__ctfe)
        DecimalControl.checkFlags(flags, ExceptionFlags.severe);
    else
        DecimalControl.raiseFlags(flags);
    return result;
}


package:


template DataType(D)
{
    alias UD = Unqual!D;
    static if (is(UD == Decimal32))
        alias DataType = uint;
    else static if (is(UD == Decimal64))
        alias DataType = ulong;
    else static if (is(UD == Decimal128))
        alias DataType = uint128;
    else
        static assert(0);
}

mixin template ExceptionConstructors()
{
    @nogc @safe pure nothrow this(string msg, string file = __FILE__, size_t line = __LINE__, Throwable next = null)
    {
        super(msg, file, line, next);
    }

    @nogc @safe pure nothrow this(string msg, Throwable next, string file = __FILE__, size_t line = __LINE__)
    {
        super(msg, file, line, next);
    }
}

/* ****************************************************************************************************************** */
/* DECIMAL STRING CONVERSION                                                                                          */
/* ****************************************************************************************************************** */


//sinks %a
void sinkHexadecimal(C, T)(auto const ref FormatSpec!C spec, scope ToStringSink!C sink,
    auto const ref T coefficient, const int exponent, const bool signed) nothrow @safe
if (isSomeChar!C && isAnyUnsigned!T)
{
    int w = 4; //0x, p, exponent sign
    if (spec.flPlus || spec.flSpace || signed)
        ++w;

    int p = prec(coefficient);
    if (p == 0)
        p = 1;

    int precision = spec.precision == spec.UNSPECIFIED || spec.precision <= 0 ? p : spec.precision;
    Unqual!T c = coefficient;
    int e = exponent;

    coefficientAdjust(c, e, precision, signed, __ctfe ? RoundingMode.implicit : DecimalControl.rounding);

    Unqual!C[(T.sizeof / 2) + 1] buffer;
    Unqual!C[prec(uint.max)] exponentBuffer;

    const digits = dumpUnsignedHex(buffer, c, spec.spec <= 'Z');
    const bool signedExponent = e < 0;
    const uint ex = signedExponent ? -e : e;
    const exponentDigits = dumpUnsigned(exponentBuffer, ex);

    w += digits;
    w += exponentDigits;

    int pad = spec.width - w;
    sinkPadLeft!C(spec, sink, pad);
    sinkSign!C(spec, sink, signed);
    sink("0");
    sink(spec.spec <= 'Z' ? "X" : "x");
    sinkPadZero!C(spec, sink, pad);
    sink(buffer[$ - digits .. $]);
    sink(spec.spec < 'Z' ? "P" : "p");
    sink(signedExponent ? "-" : "+");
    sink(exponentBuffer[$ - exponentDigits .. $]);
    sinkPadRight!C(sink, pad);
}

//sinks %f
void sinkFloat(C, T)(auto const ref FormatSpec!C spec, scope ToStringSink!C sink,
    const T coefficient, const int exponent, const bool signed, const RoundingMode mode,
    const bool skipTrailingZeros = false) nothrow @safe
if (isSomeChar!C)
{
    if (coefficient == 0U)
        sinkZero!C(spec, sink, signed, skipTrailingZeros);
    else
    {
        Unqual!T c = coefficient;
        int e = exponent;
        coefficientShrink(c, e);

        Unqual!C[200] buffer;
        int w = spec.flPlus || spec.flSpace || signed ? 1 : 0;

        if (e >= 0) //coefficient[0...].[0...]
        {
            const digits = dumpUnsigned(buffer, c);
            w += digits;
            w += e;
            const int requestedDecimals = skipTrailingZeros
                ? 0
                : spec.precision == spec.UNSPECIFIED ? 6 : spec.precision;
            if (requestedDecimals || spec.flHash)
                w += requestedDecimals + 1;
            int pad = spec.width - w;
            sinkPadLeft!C(spec, sink, pad);
            sinkSign!C(spec, sink, signed);
            sinkPadZero!C(spec, sink, pad);
            sink(buffer[$ - digits .. $]);
            sinkRepeat!C(sink, '0', e);
            if (requestedDecimals || spec.flHash)
            {
                sink(".");
                sinkRepeat!C(sink, '0', requestedDecimals);
            }
            sinkPadRight!C(sink, pad);
        }
        else
        {
            int digits = prec(c);
            int requestedDecimals = spec.precision == spec.UNSPECIFIED ? 6 : spec.precision;

            if (-e < digits) //coef.ficient[0...]
            {
                int integralDigits = digits + e;
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
                if (requestedDecimals > fractionalDigits && skipTrailingZeros)
                    requestedDecimals = fractionalDigits;
                w += integralDigits;
                if (requestedDecimals || spec.flHash)
                    w += requestedDecimals + 1;
                int pad = spec.width - w;
                sinkPadLeft!C(spec, sink, pad);
                sinkSign!C(spec, sink, signed);
                sinkPadZero!C(spec, sink, pad);
                dumpUnsigned(buffer, c);
                sink(buffer[$ - digits .. $ - fractionalDigits]);
                if (requestedDecimals || spec.flHash)
                {
                    sink(".");
                    if (fractionalDigits)
                        sink(buffer[$ - fractionalDigits .. $]);
                    sinkRepeat!C(sink, '0', requestedDecimals - fractionalDigits);
                }
                sinkPadRight!C(sink, pad);
            }
            else if (-e == digits) //0.coefficient[0...]
            {
                if (skipTrailingZeros && requestedDecimals > digits)
                    requestedDecimals = digits;
                if (requestedDecimals == 0) //special case, no decimals, round
                {
                    divpow10(c, digits - 1, signed, mode);
                    divpow10(c, 1, signed, mode);
                    w += 1;
                    if (spec.flHash)
                        ++w;
                    int pad = spec.width - w;
                    sinkPadLeft!C(spec, sink, pad);
                    sinkSign!C(spec, sink, signed);
                    sinkPadZero!C(spec, sink, pad);
                    sink(c != 0U ? "1": "0");
                    if (spec.flHash)
                        sink(".");
                    sinkPadRight!C(sink, pad);
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
                    int pad = spec.width - w;
                    sinkPadLeft!C(spec, sink, pad);
                    sinkSign!C(spec, sink, signed);
                    sinkPadZero!C(spec, sink, pad);
                    sink("0.");
                    dumpUnsigned(buffer, c);
                    sink(buffer[$ - digits .. $]);
                    sinkRepeat!C(sink, '0', requestedDecimals - digits);
                    sinkPadRight!C(sink, pad);
                }
            }
            else //-e > 0.[0...][coefficient]
            {
                int zeros = -e - digits;

                if (requestedDecimals > digits - e && skipTrailingZeros)
                    requestedDecimals = digits - e - 1;

                if (requestedDecimals <= zeros) //special case, coefficient does not fit
                {
                    divpow10(c, digits - 1, signed, mode);
                    divpow10(c, 1, signed, mode);
                    if (requestedDecimals == 0)  //special case, 0 or 1
                    {
                        w += 1;
                        int pad = spec.width - w;
                        sinkPadLeft!C(spec, sink, pad);
                        sinkSign!C(spec, sink, signed);
                        sinkPadZero!C(spec, sink, pad);
                        sink(c != 0U ? "1": "0");
                        sinkPadRight!C(sink, pad);
                    }
                    else  //special case 0.[0..][0/1]
                    {
                        w += 2;
                        w += requestedDecimals;
                        int pad = spec.width - w;
                        sinkPadLeft!C(spec, sink, pad);
                        sinkSign!C(spec, sink, signed);
                        sinkPadZero!C(spec, sink, pad);
                        sink("0.");
                        sinkRepeat!C(sink, '0', requestedDecimals - 1);
                        sink(c != 0U ? "1": "0");
                        sinkPadRight!C(sink, pad);
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
                    w += 2;
                    w += requestedDecimals;
                    int pad = spec.width - w;
                    sinkPadLeft!C(spec, sink, pad);
                    sinkSign!C(spec, sink, signed);
                    sinkPadZero!C(spec, sink, pad);
                    sink("0.");
                    sinkRepeat!C(sink, '0', zeros);
                    digits = dumpUnsigned(buffer, c);
                    sink(buffer[$ - digits .. $]);
                    sinkRepeat!C(sink, '0', requestedDecimals - digits - zeros);
                    sinkPadRight!C(sink, pad);
                }
            }
        }
    }
}

//sinks %e
void sinkExponential(C, T)(auto const ref FormatSpec!C spec, scope ToStringSink!C sink,
    const T coefficient, const int exponent, const bool signed, const RoundingMode mode,
    const bool skipTrailingZeros = false) nothrow @safe
if (isSomeChar!C)
{
    int w = 3; /// N e +/-
    if (spec.flPlus || spec.flSpace || signed)
        ++w;
    Unqual!C[(T.sizeof * 8 / 3) + 1] buffer;
    Unqual!C[20] exponentBuffer;
    Unqual!T c = coefficient;
    int ex = exponent;
    coefficientShrink(c, ex);
    int digits = prec(c);
    const int e = digits == 0 ? 0 : ex + (digits - 1);
    int requestedDecimals = spec.precision == spec.UNSPECIFIED ? 6 : spec.precision;
    const int targetPrecision = requestedDecimals + 1;

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
    const exponentDigits = dumpUnsigned(exponentBuffer, ue);
    w += exponentDigits <= 2 ? 2 : exponentDigits;
    digits = dumpUnsigned(buffer, c);

    if (skipTrailingZeros && requestedDecimals > digits - 1)
        requestedDecimals = digits - 1;

    if (requestedDecimals || spec.flHash)
        w += requestedDecimals + 1;

    int pad = spec.width - w;
    sinkPadLeft!C(spec, sink, pad);
    sinkSign!C(spec, sink, signed);
    sinkPadZero!C(spec, sink, pad);
    sink(buffer[$ - digits .. $ - digits + 1]);
    if (requestedDecimals || spec.flHash)
    {
        sink(".");
        if (digits > 1)
            sink(buffer[$ - digits + 1 .. $]);
        sinkRepeat!C(sink, '0', requestedDecimals - (digits - 1));
    }
    sink(spec.spec <= 'Z' ? "E" : "e");
    sink(signedExponent ? "-" : "+");
    if (exponentDigits < 2)
        sink("0");
    sink(exponentBuffer[$ - exponentDigits .. $]);
    sinkPadRight!C(sink, pad);
}

//sinks %g
void sinkGeneral(C, T)(auto const ref FormatSpec!C spec, scope ToStringSink!C sink,
    const T coefficient, const int exponent, const bool signed, const RoundingMode mode) nothrow @safe
if (isSomeChar!C)
{
    int precision = spec.precision == spec.UNSPECIFIED ? 6 : (spec.precision <= 0 ? 1 : spec.precision);
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
        FormatSpec!C fspec = spec;
        fspec.precision = precision - 1 - expe;
        sinkFloat!(C, Unqual!T)(fspec, sink, coefficient, exponent, signed, mode, !fspec.flHash);
    }
    else
    {
        FormatSpec!C espec = spec;
        espec.precision = precision - 1;
        sinkExponential!(C, Unqual!T)(espec, sink, coefficient, exponent, signed, mode, !espec.flHash);
    }
}

//sinks a decimal value
void sinkDecimal(C, D)(auto const ref FormatSpec!C spec, scope ToStringSink!C sink,
    auto const ref D decimal, const RoundingMode mode) nothrow @safe
if (isSomeChar!C && isDecimal!D)
{
    DataType!D coefficient;
    int exponent;
    bool isNegative;

    const fx = fastDecode(decimal, coefficient, exponent, isNegative);
    if (fx == FastClass.signalingNaN)
        sinkNaN!(C, DataType!D)(spec, sink, isNegative, true, coefficient, spec.spec == 'a' || spec.spec == 'A');
    else if (fx == FastClass.quietNaN)
        sinkNaN!(C, DataType!D)(spec, sink, isNegative, false, coefficient, spec.spec == 'a' || spec.spec == 'A');
    else if (fx == FastClass.infinite)
        sinkInfinity!C(spec, sink, decimal.isNeg);
    else
    {
        switch (spec.spec)
        {
            case 'f':
            case 'F':
                sinkFloat!(C, DataType!D)(spec, sink, coefficient, exponent, isNegative, mode);
                break;
            case 'e':
            case 'E':
                sinkExponential!(C, DataType!D)(spec, sink, coefficient, exponent, isNegative, mode);
                break;
            case 'g':
            case 'G':
            case 's':
            case 'S':
                sinkGeneral!(C, DataType!D)(spec, sink, coefficient, exponent, isNegative, mode);
                break;
            case 'a':
            case 'A':
                sinkHexadecimal!(C, DataType!D)(spec, sink, coefficient, exponent, isNegative);
                break;
            default:
                assert(0, "Unsupported format specifier");
        }
    }
}

//converts decimal to string using %g
immutable(C)[] decimalToString(C, D)(auto const ref D decimal, const RoundingMode mode) nothrow @safe
if (isSomeChar!C && isDecimal!D)
{
    auto spec = FormatSpec!C("%g");
    return decimalToString!(C, D)(spec, decimal, mode);
}

//converts decimal to string
immutable(C)[] decimalToString(C, D)(auto const ref FormatSpec!C spec, auto const ref D decimal, const RoundingMode mode) nothrow @safe
if (isSomeChar!C && isDecimal!D)
{
    struct Buffer
    {
    nothrow @safe:

        C[] value;
        size_t offset;

        this(size_t capacity)
        {
            this.offset = 0;
            this.value.length = capacity;
        }

        void localSink(scope const(C)[] s) nothrow @safe
        {
            if (offset == size_t.max || offset + s.length > value.length)
            {
                value ~= s;
                offset = size_t.max;
            }
            else
            {
                value[offset..offset + s.length] = s[0..$];
                offset += s.length;
            }
        }

        immutable(C)[] toResult() @trusted
        {
            if (offset == size_t.max)
                return value.idup;
            else
                return value[0..offset].idup;
        }
    }

    auto buffer = Buffer(1000);
    sinkDecimal!(C, D)(spec, &buffer.localSink, decimal, mode);
    return buffer.toResult();
}

version (none)
unittest
{
    import std.format;
    Decimal32 x = "1.234567";
    assert (format("%0.7f", x) == "1.2345670", "\"" ~ format("%0.7f", x) ~ "\"");
    assert (format("%0.6f", x) == "1.234567");
    assert (format("%0.5f", x) == "1.23457");
    assert (format("%0.4f", x) == "1.2346");
    assert (format("%0.3f", x) == "1.235");
    assert (format("%0.2f", x) == "1.23");
    assert (format("%0.1f", x) == "1.2");
    assert (format("%0.0f", x) == "1");
    assert (format("%+0.1f", x) == "+1.2");
    assert (format("%+0.1f", -x) == "-1.2");
    assert (format("% 0.1f", x) == " 1.2");
    assert (format("% 0.1f", -x) == "-1.2");
    assert (format("%8.2f", x) == "    1.23");
    assert (format("%+8.2f", x) == "   +1.23");
    assert (format("%+8.2f", -x) == "   -1.23");
    assert (format("% 8.2f", x) == "    1.23");
    assert (format("%-8.2f", x) == "1.23    ");
    assert (format("%-8.2f", -x) == "-1.23   ");

    struct S
    {
        string fmt;
        string v;
        string expected;
    }

    S[] tests =
    [
        S("%+.3e","0.0","+0.000e+00"),
  	    S("%+.3e","1.0","+1.000e+00"),
  	    S("%+.3f","-1.0","-1.000"),
  	    S("%+.3F","-1.0","-1.000"),
  	    S("%+07.2f","1.0","+001.00"),
  	    S("%+07.2f","-1.0","-001.00"),
  	    S("%-07.2f","1.0","1.00   "),
  	    S("%-07.2f","-1.0","-1.00  "),
  	    S("%+-07.2f","1.0","+1.00  "),
  	    S("%+-07.2f","-1.0","-1.00  "),
  	    S("%-+07.2f","1.0","+1.00  "),
  	    S("%-+07.2f","-1.0","-1.00  "),
  	    S("%+10.2f","+1.0","     +1.00"),
  	    S("%+10.2f","-1.0","     -1.00"),
  	    S("% .3E","-1.0","-1.000E+00"),
  	    S("% .3e","1.0"," 1.000e+00"),
  	    S("%+.3g","0.0","+0"),
  	    S("%+.3g","1.0","+1"),
  	    S("%+.3g","-1.0","-1"),
  	    S("% .3g","-1.0","-1"),
  	    S("% .3g","1.0"," 1"),
  	    S("%a","1","0x1p+0"),
  	    S("%#g","1e-32","1.00000e-32"),
  	    S("%#g","-1.0","-1.00000"),
  	    S("%#g","1.1","1.10000"),
  	    S("%#g","123456.0","123456."),
  	    S("%#g","1234567.0","1.23457e+06"),
  	    S("%#g","1230000.0","1.23000e+06"),
  	    S("%#g","1000000.0","1.00000e+06"),
  	    S("%#.0f","1.0","1."),
  	    S("%#.0e","1.0","1.e+00"),
  	    S("%#.0g","1.0","1."),
  	    S("%#.0g","1100000.0","1.e+06"),
  	    S("%#.4f","1.0","1.0000"),
  	    S("%#.4e","1.0","1.0000e+00"),
  	    S("%#.4g","1.0","1.000"),
  	    S("%#.4g","100000.0","1.000e+05"),
  	    S("%#.0f","123.0","123."),
  	    S("%#.0e","123.0","1.e+02"),
  	    S("%#.0g","123.0","1.e+02"),
  	    S("%#.4f","123.0","123.0000"),
  	    S("%#.4e","123.0","1.2300e+02"),
  	    S("%#.4g","123.0","123.0"),
  	    S("%#.4g","123000.0","1.230e+05"),
  	    S("%#9.4g","1.0","    1.000"),
  	    S("%.4a","1","0x1p+0"),
  	    S("%.4a","-1","-0x1p+0"),
  	    S("%f","+inf","inf"),
  	    S("%.1f","-inf","-inf"),
  	    S("% f","$(B NaN)"," nan"),
  	    S("%20f","+inf","                 inf"),
  	    S("% 20F","+inf","                 INF"),
  	    S("% 20e","-inf","                -inf"),
  	    S("%+20E","-inf","                -INF"),
  	    S("% +20g","-Inf","                -inf"),
  	    S("%+-20G","+inf","+INF                "),
  	    S("%20e","$(B NaN)","                 nan"),
  	    S("% +20E","$(B NaN)","                +NAN"),
  	    S("% -20g","$(B NaN)"," nan                "),
  	    S("%+-20G","$(B NaN)","+NAN                "),
  	    S("%+020e","+inf","                +inf"),
  	    S("%-020f","-inf","-inf                "),
  	    S("%-020E","$(B NaN)","NAN                 "),
        S("%e","1.0","1.000000e+00"),
  	    S("%e","1234.5678e3","1.234568e+06"),
  	    S("%e","1234.5678e-8","1.234568e-05"),
  	    S("%e","-7.0","-7.000000e+00"),
  	    S("%e","-1e-9","-1.000000e-09"),
  	    S("%f","1234.567e2","123456.700000"),
  	    S("%f","1234.5678e-8","0.000012"),
  	    S("%f","-7.0","-7.000000"),
  	    S("%f","-1e-9","-0.000000"),
  	    S("%g","1234.5678e3","1.23457e+06"),
  	    S("%g","1234.5678e-8","1.23457e-05"),
  	    S("%g","-7.0","-7"),
  	    S("%g","-1e-9","-1e-09"),
  	    S("%E","1.0","1.000000E+00"),
  	    S("%E","1234.5678e3","1.234568E+06"),
  	    S("%E","1234.5678e-8","1.234568E-05"),
  	    S("%E","-7.0","-7.000000E+00"),
  	    S("%E","-1e-9","-1.000000E-09"),
  	    S("%G","1234.5678e3","1.23457E+06"),
  	    S("%G","1234.5678e-8","1.23457E-05"),
  	    S("%G","-7.0","-7"),
  	    S("%G","-1e-9","-1E-09"),
  	    S("%20.6e","1.2345e3","        1.234500e+03"),
  	    S("%20.6e","1.2345e-3","        1.234500e-03"),
  	    S("%20e","1.2345e3","        1.234500e+03"),
  	    S("%20e","1.2345e-3","        1.234500e-03"),
  	    S("%20.8e","1.2345e3","      1.23450000e+03"),
  	    S("%20f","1.23456789e3","         1234.568000"),
  	    S("%20f","1.23456789e-3","            0.001235"),
  	    S("%20f","12345678901.23456789","  12345680000.000000"),
  	    S("%-20f","1.23456789e3","1234.568000         "),
        S("%20.8f","1.23456789e3","       1234.56800000"),
        S("%20.8f","1.23456789e-3","          0.00123457"),
        S("%g","1.23456789e3","1234.57"),
        S("%g","1.23456789e-3","0.00123457"),
        S("%g","1.23456789e20","1.23457e+20"),
        S("%.2f","1.0","1.00"),
  	    S("%.2f","-1.0","-1.00"),
  	    S("% .2f","1.0"," 1.00"),
  	    S("% .2f","-1.0","-1.00"),
  	    S("%+.2f","1.0","+1.00"),
  	    S("%+.2f","-1.0","-1.00"),
  	    S("%7.2f","1.0","   1.00"),
  	    S("%7.2f","-1.0","  -1.00"),
  	    S("% 7.2f","1.0","   1.00"),
  	    S("% 7.2f","-1.0","  -1.00"),
  	    S("%+7.2f","1.0","  +1.00"),
  	    S("%+7.2f","-1.0","  -1.00"),
  	    S("% +7.2f","1.0","  +1.00"),
  	    S("% +7.2f","-1.0","  -1.00"),
  	    S("%07.2f","1.0","0001.00"),
  	    S("%07.2f","-1.0","-001.00"),
  	    S("% 07.2f","1.0"," 001.00"),
  	    S("% 07.2f","-1.0","-001.00"),
  	    S("%+07.2f","1.0","+001.00"),
  	    S("%+07.2f","-1.0","-001.00"),
  	    S("% +07.2f","1.0","+001.00"),
  	    S("% +07.2f","-1.0","-001.00"),


    ];

    foreach(s; tests)
    {
        string result = format(s.fmt, Decimal32(s.v));
        assert(result == s.expected, "value: '" ~ s.v ~ "', format: '" ~ s.fmt ~ "', result :'" ~ result ~ "', expected: '" ~ s.expected ~ "'");
    }
}

//returns true if a decimal number can be read in value, stops if doesn't fit in value
ExceptionFlags parseNumberAndExponent(R, T)(ref R range, out T value, out int exponent, bool zeroPrefix)
if (isInputRange!R && isSomeChar!(ElementType!R))
{
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
            bool overflow = false;
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
        //return atLeastOneFractionalDigit ? flags : flags | ExceptionFlags.invalidOperation;
    else
        return atLeastOneDigit ? flags : flags | ExceptionFlags.invalidOperation;
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

@safe
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

ExceptionFlags parseDecimalFloat(R, T)(ref R range, out T coefficient, out int exponent,
    const bool zeroPrefix)
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
                flags |= ExceptionFlags.invalidOperation;
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

@safe
ExceptionFlags parseDecimal(R, T)(ref R range, out T coefficient, out int exponent,
    out bool isinf, out bool isnan, out bool signaling, out bool signed, out bool wasHex)
if (isInputRange!R && isSomeChar!(ElementType!R))
{
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

ExceptionFlags parse(D, R)(ref R range, out D decimal, const int precision, const RoundingMode mode)
if (isInputRange!R && isSomeChar!(ElementType!R) && isDecimal!D)
{
    DataType!D coefficient;
    bool isinf, isnan, signaling, signed;
    int exponent;
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
        flags |= adjustCoefficient(coefficient, exponent, D.EXP_MIN, D.EXP_MAX, D.COEF_MAX, isnegative, mode);
        flags |= adjustPrecision(coefficient, exponent, D.EXP_MIN, D.EXP_MAX, precision, isnegative, mode);
        if (flags & ExceptionFlags.overflow)
            decimal.data = D.MASK_INF;
        else if ((flags & ExceptionFlags.underflow)  || coefficient == 0)
            decimal.data = D.MASK_ZERO;
        else
        {
            flags |= decimal.pack(coefficient, exponent, isnegative);
            if (flags & ExceptionFlags.overflow)
                decimal.data = D.MASK_INF;
            else if ((flags & ExceptionFlags.underflow)  || coefficient == 0)
                decimal.data = D.MASK_ZERO;
        }
    }

    if (isNegative)
        decimal.data |= D.MASK_SGN;
    return flags;
}

/* ****************************************************************************************************************** */
/* DECIMAL TO DECIMAL CONVERSION                                                                                      */
/* ****************************************************************************************************************** */

ExceptionFlags decimalToDecimal(D1, D2)(auto const ref D1 source, out D2 target,
    const int precision, const RoundingMode mode) @nogc nothrow pure @safe
if (isDecimal!(D1, D2))
{
    DataType!D1 cx; int ex; bool sx;
    final switch(fastDecode(source, cx, ex, sx))
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

ExceptionFlags decimalToUnsigned(D, T)(auto const ref D source, out T target, const RoundingMode mode)
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

ExceptionFlags decimalToSigned(D, T)(auto const ref D source, out T target, const RoundingMode mode)
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

ExceptionFlags decimalToFloat(D, T)(auto const ref D source, out T target, const RoundingMode mode)
if (isDecimal!D && isFloatingPoint!T)
{
    DataType!D cx; int ex; bool sx;
    final switch (fastDecode(source, cx, ex, sx))
    {
        case FastClass.finite:
//s_max_float     = "3.402823466385288598117041834845169e+0038",
//    s_min_float     = "1.401298464324817070923729583289916e-0045",
//    s_max_double    = "1.797693134862315708145274237317043e+0308",
//    s_min_double    = "4.940656458412465441765687928682213e-0324",
//    s_max_real      = "1.189731495357231765021263853030970e+4932",
//    s_min_real      = "3.645199531882474602528405933619419e-4951",

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
if (isDecimal!D1 && isDecimal!D2)
{
    static if (D1.sizeof >= D2.sizeof)
        alias CommonStorage = DataType!D1;
    else
        alias CommonStorage = DataType!D2;
}

template CommonStorage(D, I)
if (isDecimal!D && isIntegral!I)
{
    static if (D.sizeof >= I.sizeof)
        alias CommonStorage = DataType!D;
    else
        alias CommonStorage = Unsigned!I;
}

template CommonStorage(D, F)
if (isDecimal!D && isFloatingPoint!F)
{
    alias UF = Unqual!F;
    static if (is(UF == float) || is(UF == double))
        alias CommonStorage = DataType!D;
    else
        alias CommonStorage = CommonStorage!(D, ulong);
}

@safe pure nothrow @nogc
D canonical(D)(auto const ref D x)
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
DecimalClass decimalDecode(D, T)(auto const ref D x, out T cx, out int ex, out bool sx)
if (isDecimal!D && is(T: DataType!D))
{
    sx = cast(bool)(x.data & D.MASK_SGN);

    if ((x.data & D.MASK_INF) == D.MASK_INF)
        if ((x.data & D.MASK_QNAN) == D.MASK_QNAN)
            if ((x.data & D.MASK_SNAN) == D.MASK_SNAN)
                return DecimalClass.signalingNaN;
            else
                return DecimalClass.quietNaN;
        else
            return sx ? DecimalClass.negativeInfinity : DecimalClass.positiveInfinity;
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

enum FastClass : byte
{
    signalingNaN,
    quietNaN,
    infinite,
    zero,
    finite,
}

@safe pure nothrow @nogc
FastClass fastDecode(D, T)(auto const ref D x, out T cx, out int ex, out bool sx)
if ((is(D: Decimal32) || is(D: Decimal64)) && isAnyUnsigned!T)
{
    static assert (T.sizeof >= D.sizeof);

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
FastClass fastDecode(D, T)(auto const ref D x, out T cx, out int ex, out bool sx)
if (is(D: Decimal128) && isAnyUnsigned!T)
{
    static assert (T.sizeof >= D.sizeof);

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
FastClass fastDecode(F, T)(auto const ref F x, out T cx, out int ex, out bool sx,
    const RoundingMode mode, out ExceptionFlags flags)
if (isFloatingPoint!F && isAnyUnsigned!T)
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

    final switch(mode)
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

@safe pure nothrow @nogc
ExceptionFlags decimalInc(D)(ref D x, const int precision, const RoundingMode mode)
{
    DataType!D cx; int ex; bool sx;
    final switch(fastDecode(x, cx, ex, sx))
    {
        case FastClass.finite:
            const flags = coefficientAdd(cx, ex, sx, DataType!D(1U), 0, false, RoundingMode.implicit);
            return x.adjustedPack(cx, ex, sx, precision, mode, flags);
        case FastClass.zero:
            x = D.one;
            return ExceptionFlags.none;
        case FastClass.quietNaN:
        case FastClass.infinite:
            return ExceptionFlags.none;
        case FastClass.signalingNaN:
            unsignalize(x);
            return ExceptionFlags.invalidOperation;
    }
}

@safe pure nothrow @nogc
ExceptionFlags decimalDec(D)(ref D x, const int precision, const RoundingMode mode)
{
    DataType!D cx; int ex; bool sx;
    final switch(fastDecode(x, cx, ex, sx))
    {
        case FastClass.finite:
            const flags = coefficientAdd(cx, ex, sx, DataType!D(1U), 0, true, RoundingMode.implicit);
            return x.adjustedPack(cx, ex, sx, precision, mode, flags);
        case FastClass.zero:
            x = -D.one;
            return ExceptionFlags.none;
        case FastClass.infinite:
        case FastClass.quietNaN:
            return ExceptionFlags.none;
        case FastClass.signalingNaN:
            unsignalize(x);
            return ExceptionFlags.invalidOperation;
    }
}

@safe pure nothrow @nogc
ExceptionFlags decimalRound(D)(ref D x, const int precision, const RoundingMode mode)
if (isDecimal!D)
{
    DataType!D cx; int ex; bool sx;
    final switch(fastDecode(x, cx, ex, sx))
    {
        case FastClass.finite:
            const flags = coefficientAdjust(cx, ex, 0, D.EXP_MAX, D.COEF_MAX, sx, mode);
            return x.adjustedPack(cx, ex, sx, precision, mode, flags);
        case FastClass.zero:
        case FastClass.infinite:
        case FastClass.quietNaN:
            return ExceptionFlags.none;
        case FastClass.signalingNaN:
            unsignalize(x);
            return ExceptionFlags.invalidOperation;
    }
}

@safe pure nothrow @nogc
ExceptionFlags decimalAdjust(D)(ref D x, const int precision, const RoundingMode mode)
{
    DataType!D cx; int ex; bool sx;
    final switch(fastDecode(x, cx, ex, sx))
    {
        case FastClass.finite:
            return x.adjustedPack(cx, ex, sx, precision, mode, ExceptionFlags.none);
        case FastClass.zero:
        case FastClass.infinite:
        case FastClass.quietNaN:
            return ExceptionFlags.none;
        case FastClass.signalingNaN:
            unsignalize(x);
            return ExceptionFlags.invalidOperation;
    }
}

@safe pure nothrow @nogc
ExceptionFlags decimalNextUp(D)(ref D x)
if (isDecimal!D)
{
    DataType!D cx; int ex; bool sx;
    final switch(fastDecode(x, cx, ex, sx))
    {
        case FastClass.finite:
            coefficientExpand(cx, ex);
            if (sx)
                --cx;
            else
                ++cx;
            return x.adjustedPack(cx, ex, sx, 0, RoundingMode.towardPositive, ExceptionFlags.none);
        case FastClass.zero:
            x.pack(DataType!D(1U), D.EXP_MIN, false);
            return ExceptionFlags.none;
        case FastClass.infinite:
            if (sx)
                x = -D.max;
            return ExceptionFlags.none;
        case FastClass.quietNaN:
            return ExceptionFlags.none;
        case FastClass.signalingNaN:
            unsignalize(x);
            return ExceptionFlags.invalidOperation;
    }
}

@safe pure nothrow @nogc
ExceptionFlags decimalNextDown(D)(ref D x)
if (isDecimal!D)
{
    DataType!D cx; int ex; bool sx;
    final switch(fastDecode(x, cx, ex, sx))
    {
        case FastClass.finite:
            coefficientExpand(cx, ex);
            if (!sx)
                --cx;
            else
                ++cx;
            return x.adjustedPack(cx, ex, sx, 0, RoundingMode.towardNegative, ExceptionFlags.none);
        case FastClass.zero:
            x.pack(DataType!D(1U), D.EXP_MIN, true);
            return ExceptionFlags.none;
        case FastClass.infinite:
            if (!sx)
                x = D.max;
            return ExceptionFlags.none;
        case FastClass.quietNaN:
            return ExceptionFlags.none;
        case FastClass.signalingNaN:
            unsignalize(x);
            return ExceptionFlags.invalidOperation;
    }
}

ExceptionFlags decimalMin(D1, D2, D)(auto const ref D1 x, auto const ref D2 y, out D z)
if (isDecimal!(D1, D2, D) && is(D: CommonDecimal!(D1, D2)))
{
    DataType!D cx, cy; int ex, ey; bool sx, sy;
    const fx = fastDecode(x, cx, ex, sx);
    const fy = fastDecode(y, cy, ey, sy);

    if (fx == FastClass.signalingNaN)
    {
        z = copysign(D.nan, x);
        return ExceptionFlags.invalidOperation;
    }

    if (fy == FastClass.signalingNaN)
    {
        if (fx == FastClass.quietNaN)
            z = copysign(D.nan, x);
        else
            z = copysign(D.nan, y);
        return ExceptionFlags.invalidOperation;
    }

    if (fx == FastClass.quietNaN)
    {
        if (fy == FastClass.quietNaN)
            z = x;
        else
            z = y;
        return ExceptionFlags.none;
    }

    if (fy == FastClass.quietNaN)
    {
        z = x;
        return ExceptionFlags.none;
    }

    if (fx == FastClass.infinite)
    {
        if (sx)
            z = x;
        else
            z = y;
        return ExceptionFlags.none;
    }

    if (fy == FastClass.infinite)
    {
        if (sy)
            z = y;
        else
            z = x;
        return ExceptionFlags.none;
    }

    if (fx == FastClass.zero)
    {
        if (sy)
            z = y;
        else
            z = x;
        return ExceptionFlags.none;
    }

    if (fy == FastClass.zero)
    {
        if (sx)
            z = x;
        else
            z = y;
        return ExceptionFlags.none;
    }

    const c = coefficientCmp(cx, ex, sx, cy, ey, sy);
    if (c <= 0)
        z = x;
    else
        z = y;
    return ExceptionFlags.none;
}

ExceptionFlags decimalMinAbs(D1, D2, D)(auto const ref D1 x, auto const ref D2 y, out D z)
if (isDecimal!(D1, D2, D) && is(D: CommonDecimal!(D1, D2)))
{
    DataType!D cx, cy; int ex, ey; bool sx, sy;
    const fx = fastDecode(x, cx, ex, sx);
    const fy = fastDecode(y, cy, ey, sy);

    if (fx == FastClass.signalingNaN)
    {
        z = copysign(D.nan, x);
        return ExceptionFlags.invalidOperation;
    }

    if (fy == FastClass.signalingNaN)
    {
        if (fx == FastClass.quietNaN)
            z = copysign(D.nan, x);
        else
            z = copysign(D.nan, y);
        return ExceptionFlags.invalidOperation;
    }

    if (fx == FastClass.quietNaN)
    {
        if (fy == FastClass.quietNaN)
            z = x;
        else
            z = y;
        return ExceptionFlags.none;
    }

    if (fy == FastClass.quietNaN)
    {
        z = x;
        return ExceptionFlags.none;
    }

    if (fx == FastClass.infinite)
    {
        if (fy == FastClass.infinite && sx)
            z = x;
        else
            z = y;
        return ExceptionFlags.none;
    }

    if (fy == FastClass.infinite)
    {
        z = x;
        return ExceptionFlags.none;
    }

    if (fx == FastClass.zero)
    {
        z = x;
        return ExceptionFlags.none;
    }

    if (fy == FastClass.zero)
    {
        z = y;
        return ExceptionFlags.none;
    }

    const c = coefficientCmp(cx, ex, cy, ey);
    if (c < 0)
        z = x;
    else if (c == 0 && sx)
        z = x;
    else
        z = y;
    return ExceptionFlags.none;
}

ExceptionFlags decimalMax(D1, D2, D)(auto const ref D1 x, auto const ref D2 y, out D z)
if (isDecimal!(D1, D2, D) && is(D: CommonDecimal!(D1, D2)))
{
    DataType!D cx, cy; int ex, ey; bool sx, sy;
    const fx = fastDecode(x, cx, ex, sx);
    const fy = fastDecode(y, cy, ey, sy);

    if (fx == FastClass.signalingNaN)
    {
        z = copysign(D.nan, x);
        return ExceptionFlags.invalidOperation;
    }

    if (fy == FastClass.signalingNaN)
    {
        if (fx == FastClass.quietNaN)
            z = copysign(D.nan, x);
        else
            z = copysign(D.nan, y);
        return ExceptionFlags.invalidOperation;
    }

    if (fx == FastClass.quietNaN)
    {
        if (fy == FastClass.quietNaN)
            z = x;
        else
            z = y;
        return ExceptionFlags.none;
    }

    if (fy == FastClass.quietNaN)
    {
        z = x;
        return ExceptionFlags.none;
    }

    if (fx == FastClass.infinite)
    {
        if (sx)
            z = y;
        else
            z = x;
        return ExceptionFlags.none;
    }

    if (fy == FastClass.infinite)
    {
        if (sy)
            z = x;
        else
            z = y;
        return ExceptionFlags.none;
    }

    if (fx == FastClass.zero)
    {
        if (sy)
            z = x;
        else
            z = y;
        return ExceptionFlags.none;
    }

    if (fy == FastClass.zero)
    {
        if (sx)
            z = y;
        else
            z = x;
        return ExceptionFlags.none;
    }

    const c = coefficientCmp(cx, ex, sx, cy, ey, sy);
    if (c >= 0)
        z = x;
    else
        z = y;
    return ExceptionFlags.none;
}

ExceptionFlags decimalMaxAbs(D1, D2, D)(auto const ref D1 x, auto const ref D2 y, out D z)
if (isDecimal!(D1, D2, D) && is(D: CommonDecimal!(D1, D2)))
{
    DataType!D cx, cy; int ex, ey; bool sx, sy;
    const fx = fastDecode(x, cx, ex, sx);
    const fy = fastDecode(y, cy, ey, sy);

    if (fx == FastClass.signalingNaN)
    {
        z = copysign(D.nan, x);
        return ExceptionFlags.invalidOperation;
    }

    if (fy == FastClass.signalingNaN)
    {
        if (fx == FastClass.quietNaN)
            z = copysign(D.nan, x);
        else
            z = copysign(D.nan, y);
        return ExceptionFlags.invalidOperation;
    }

    if (fx == FastClass.quietNaN)
    {
        if (fy == FastClass.quietNaN)
            z = x;
        else
            z = y;
        return ExceptionFlags.none;
    }

    if (fy == FastClass.quietNaN)
    {
        z = x;
        return ExceptionFlags.none;
    }

    if (fx == FastClass.infinite)
    {
        if (!sx || fy != FastClass.infinite)
            z = x;
        else
            z = y;
        return ExceptionFlags.none;
    }

    if (fy == FastClass.infinite)
    {
        z = y;
        return ExceptionFlags.none;
    }

    if (fx == FastClass.zero)
    {
        z = y;
        return ExceptionFlags.none;
    }

    if (fy == FastClass.zero)
    {
        z = x;
        return ExceptionFlags.none;
    }

    const c = coefficientCmp(cx, ex, cy, ey);
    if (c > 0)
        z = x;
    else if (c == 0 && !sx)
        z = x;
    else
        z = y;
    return ExceptionFlags.none;
}

@safe pure nothrow @nogc
ExceptionFlags decimalQuantize(D1, D2)(ref D1 x, auto const ref D2 y, const int precision, const RoundingMode mode)
if (isDecimal!(D1, D2))
{
    alias U = CommonStorage!(D1, D2);
    U cx, cy; int ex, ey; bool sx, sy;
    const fx = fastDecode(x, cx, ex, sx);
    const fy = fastDecode(y, cy, ey, sy);

    if (fx == FastClass.signalingNaN)
    {
        unsignalize(x);
        return ExceptionFlags.invalidOperation;
    }

    if (fy == FastClass.signalingNaN)
    {
        x = D1.nan;
        return ExceptionFlags.invalidOperation;
    }

    if (fx == FastClass.quietNaN)
        return ExceptionFlags.none;

    if (fy == FastClass.quietNaN)
    {
        x = D1.nan;
        return ExceptionFlags.none;
    }

    if (fx == FastClass.infinite)
    {
        if (fy == FastClass.infinite)
            return ExceptionFlags.none;
        x = D1.nan;
        return ExceptionFlags.invalidOperation;
    }

    if (fy == FastClass.infinite)
    {
        x = D1.nan;
        return ExceptionFlags.invalidOperation;
    }

    auto flags = coefficientAdjust(cx, ex, ey, ey, cvt!U(D1.COEF_MAX), sx, mode);
    if (flags & ExceptionFlags.overflow)
        flags = ExceptionFlags.invalidOperation;
    return x.adjustedPack(cx, ex, sx, precision, mode, flags);

}

@safe pure nothrow @nogc
ExceptionFlags decimalScale(D)(ref D x, const int n, const int precision, const RoundingMode mode)
if (isDecimal!D)
{
    DataType!D cx; int ex; bool sx;
    final switch(fastDecode(x, cx, ex, sx))
    {
        case FastClass.finite:
            if (!n)
                return ExceptionFlags.none;
            const remainder = cappedAdd(ex, n) - n;
            ExceptionFlags flags;
            if (remainder)
            {
                if (remainder < 0)
                    coefficientShrink(cx, ex);
                else
                    coefficientExpand(cx, ex);
                if (cappedAdd(ex, remainder) != remainder)
                    flags = ex < 0 ? ExceptionFlags.underflow : ExceptionFlags.overflow;
            }
            return x.adjustedPack(cx, ex, sx, precision, mode, flags);
        case FastClass.zero:
        case FastClass.infinite:
        case FastClass.quietNaN:
            return ExceptionFlags.none;
        case FastClass.signalingNaN:
            unsignalize(x);
            return ExceptionFlags.invalidOperation;
    }
}

@safe pure nothrow @nogc
ExceptionFlags decimalMulPow2(D)(ref D x, const int n, const int precision, const RoundingMode mode)
if (isDecimal!D)
{
    DataType!D cx; int ex; bool sx;
    final switch(fastDecode(x, cx, ex, sx))
    {
        case FastClass.finite:
            if (!n)
                return ExceptionFlags.none;
            DataType!D cy = 1U;
            int ey = n;
            ExceptionFlags flags;
            final switch(mode)
            {
                case RoundingMode.tiesToAway:
                    flags = exp2to10!(RoundingMode.tiesToAway)(cy, ey, false);
                    break;
                case RoundingMode.tiesToEven:
                    flags = exp2to10!(RoundingMode.tiesToEven)(cy, ey, false);
                    break;
                case RoundingMode.towardZero:
                    flags = exp2to10!(RoundingMode.towardZero)(cy, ey, false);
                    break;
                case RoundingMode.towardNegative:
                    flags = exp2to10!(RoundingMode.towardNegative)(cy, ey, false);
                    break;
                case RoundingMode.towardPositive:
                    flags = exp2to10!(RoundingMode.towardPositive)(cy, ey, false);
                    break;
            }
            flags |= coefficientMul(cx, ex, sx, cy, ey, false, mode);
            return x.adjustedPack(cx, ex, sx, precision, mode, flags);
        case FastClass.zero:
        case FastClass.infinite:
        case FastClass.quietNaN:
            return ExceptionFlags.none;
        case FastClass.signalingNaN:
            unsignalize(x);
            return ExceptionFlags.invalidOperation;
    }
}

@safe pure nothrow @nogc
ExceptionFlags decimalLog(D)(auto const ref D x, out int y)
if (isDecimal!D)
{
    DataType!D cx; int ex; bool sx;
    final switch(fastDecode(x, cx, ex, sx))
    {
        case FastClass.finite:
            y = prec(cx) + ex - 1;
            return ExceptionFlags.none;
        case FastClass.zero:
            y = int.min;
            return ExceptionFlags.invalidOperation;
        case FastClass.infinite:
            y = int.max;
            return ExceptionFlags.invalidOperation;
        case FastClass.quietNaN:
        case FastClass.signalingNaN:
            y = int.min;
            return ExceptionFlags.invalidOperation;
    }
}

@safe pure nothrow @nogc
ExceptionFlags decimalMul(D1, D2)(ref D1 x, auto const ref D2 y, const int precision, const RoundingMode mode)
if (isDecimal!(D1, D2))
{
    alias D = CommonDecimal!(D1, D2);
    alias T = DataType!D;
    alias T1 = DataType!D1;

    T cx, cy; int ex, ey; bool sx, sy;

    const fx = fastDecode(x, cx, ex, sx);
    const fy = fastDecode(y, cy, ey, sy);

    if (fx == FastClass.signalingNaN || fy == FastClass.signalingNaN)
    {
        x = sx ^ sy ? -D1.nan : D1.nan;
        return ExceptionFlags.invalidOperation;
    }

    if (fx == FastClass.quietNaN || fy == FastClass.quietNaN)
    {
        x = sx ^ sy ? -D1.nan : D1.nan;
        return ExceptionFlags.none;
    }

    if (fx == FastClass.infinite)
    {
        if (fy == FastClass.zero)
        {
            x = sx ^ sy ? -D1.nan : D1.nan;
            return ExceptionFlags.invalidOperation;
        }
        x = sx ^ sy ? -D1.infinity : D1.infinity;
        return ExceptionFlags.none;
    }

    if (fy == FastClass.infinite)
    {
        if (fx == FastClass.zero)
        {
            x = sx ^ sy ? -D1.nan : D1.nan;
            return ExceptionFlags.invalidOperation;
        }
        x = sx ^ sy ? -D1.infinity : D1.infinity;
        return ExceptionFlags.none;
    }

    if (fx == FastClass.zero || fy == FastClass.zero)
    {
        x = sx ^ sy ? -D1.zero : D1.zero;
        return ExceptionFlags.none;
    }

    const flags = coefficientMul(cx, ex, sx, cy, ey, sy, mode);
    return x.adjustedPack(cx, ex, sx, precision, mode, flags);
}

@safe pure nothrow @nogc
ExceptionFlags decimalMul(D, T)(ref D x, auto const ref T y, const int precision, const RoundingMode mode)
if (isDecimal!D && isIntegral!T)
{
    alias U = CommonStorage!(D, T);
    alias X = DataType!D;
    U cx; int ex; bool sx;
    bool sy;
    U cy = unsign!U(y, sy);
    final switch(fastDecode(x, cx, ex, sx))
    {
        case FastClass.finite:
            if (!y)
            {
                x = sx ^ sy ? -D.zero : D.zero;
                return ExceptionFlags.none;
            }
            auto flags = coefficientMul(cx, ex, sx, cy, 0, sy, RoundingMode.implicit);
            flags |= coefficientAdjust(cx, ex, cvt!U(X.max), sx, RoundingMode.implicit);
            return x.adjustedPack(cvt!X(cx), ex, sx, precision, mode, flags);
        case FastClass.zero:
            x = sx ^ sy ? -D.zero : D.zero;
            return ExceptionFlags.none;
        case FastClass.infinite:
            if (!y)
            {
                x = sx ^ sy ? -D.nan : D.nan;
                return ExceptionFlags.invalidOperation;
            }
            return ExceptionFlags.none;
        case FastClass.quietNaN:
            return ExceptionFlags.none;
        case FastClass.signalingNaN:
            unsignalize(x);
            return ExceptionFlags.invalidOperation;
    }
}

@safe pure nothrow @nogc
ExceptionFlags decimalMul(D, F)(ref D x, auto const ref F y, const int precision, const RoundingMode mode)
if (isDecimal!D && isFloatingPoint!F)
{
    alias T = CommonStorage!(D, F);

    T cx, cy; int ex, ey; bool sx, sy;
    ExceptionFlags flags;
    const fx = fastDecode(x, cx, ex, sx);
    const fy = fastDecode(y, cy, ey, sy, mode, flags);

    if (fx == FastClass.signalingNaN)
    {
        x = sx ^ sy ? -D.nan : D.nan;
        return ExceptionFlags.invalidOperation;
    }

    if (fx == FastClass.quietNaN || fy == FastClass.quietNaN)
    {
        x = sx ^ sy ? -D.nan : D.nan;
        return ExceptionFlags.none;
    }

    if (fx == FastClass.infinite)
    {
        if (fy == FastClass.zero)
        {
            x = sx ^ sy ? -D.nan : D.nan;
            return ExceptionFlags.invalidOperation;
        }
        x = sx ^ sy ? -D.infinity : D.infinity;
        return ExceptionFlags.none;
    }

    if (fy == FastClass.infinite)
    {
        if (fx == FastClass.zero)
        {
            x = sx ^ sy ? -D.nan : D.nan;
            return ExceptionFlags.invalidOperation;
        }
        x = sx ^ sy ? -D.infinity : D.infinity;
        return ExceptionFlags.none;
    }

    if (fx == FastClass.zero || fy == FastClass.zero)
    {
        x = sx ^ sy ? -D.zero : D.zero;
        return ExceptionFlags.none;
    }
    flags |= coefficientAdjust(cy, ey, realFloatPrecision!F(0), sy, mode);
    flags |= coefficientMul(cx, ex, sx, cy, ey, sy, mode);
    return x.adjustedPack(cx, ex, sx, precision, mode, flags);
}

@safe pure nothrow @nogc
ExceptionFlags decimalMul(T, D)(auto const ref T x, auto const ref D y, out D z, const int precision, const RoundingMode mode)
if (isDecimal!D && isIntegral!T)
{
   z = y;
   return decimalMul(z, x, precision, mode);
}

@safe pure nothrow @nogc
ExceptionFlags decimalMul(F, D)(auto const ref F x, auto const ref D y, out D z, const int precision, const RoundingMode mode)
if (isDecimal!D && isFloatingPoint!F)
{
    z = y;
    return decimalMul(z, x, precision, mode);
}

@safe pure nothrow @nogc
ExceptionFlags decimalDiv(D1, D2)(ref D1 x, auto const ref D2 y, const int precision, const RoundingMode mode)
if (isDecimal!(D1, D2))
{
    alias D = CommonDecimal!(D1, D2);
    alias T = DataType!D;
    alias T1 = DataType!D1;

    T cx, cy; int ex, ey; bool sx, sy;

    const fx = fastDecode(x, cx, ex, sx);
    const fy = fastDecode(y, cy, ey, sy);

    if (fx == FastClass.signalingNaN || fy == FastClass.signalingNaN)
    {
        x = sx ^ sy ? -D1.nan : D1.nan;
        return ExceptionFlags.invalidOperation;
    }

    if (fx == FastClass.quietNaN || fy == FastClass.quietNaN)
    {
        x = sx ^ sy ? -D1.nan : D1.nan;
        return ExceptionFlags.none;
    }

    if (fx == FastClass.infinite)
    {
        if (fy == FastClass.infinite)
        {
            x = sx ^ sy ? -D1.nan : D1.nan;
            return ExceptionFlags.invalidOperation;
        }
        x = sx ^ sy ? -D1.infinity : D1.infinity;
        return ExceptionFlags.none;
    }

    if (fx == FastClass.zero)
    {
        if (fy == FastClass.zero)
        {
            x = sx ^ sy ? -D1.nan : D1.nan;
            return ExceptionFlags.invalidOperation;
        }

        x = sx ^ sy ? -D1.zero : D1.zero;
        return ExceptionFlags.none;
    }

    if (fy == FastClass.infinite)
    {
        x = sx ^ sy ? -D1.zero : D1.zero;
        return ExceptionFlags.none;
    }

    if (fy == FastClass.zero)
    {
        x = sx ^ sy ? -D1.infinity : D1.infinity;
        return ExceptionFlags.divisionByZero;
    }

    auto flags = coefficientDiv(cx, ex, sx, cy, ey, sy, RoundingMode.implicit);
    flags |= coefficientAdjust(cx, ex, cvt!T(T1.max), sx, RoundingMode.implicit);
    return x.adjustedPack(cvt!T1(cx), ex, sx, precision, mode, flags);
}

@safe pure nothrow @nogc
ExceptionFlags decimalDiv(D, T)(ref D x, auto const ref T y, const int precision, const RoundingMode mode)
if (isDecimal!D && isIntegral!T)
{
    alias U = CommonStorage!(D, T);
    U cx; int ex; bool sx;
    bool sy;
    U cy = unsign!U(y, sy);
    final switch (fastDecode(x, cx, ex, sx))
    {
        case FastClass.finite:
            if (!y)
            {
                x = sx ^ sy ? -D.infinity : D.infinity;
                return ExceptionFlags.divisionByZero;
            }
            const flags = coefficientDiv(cx, ex, sx, cy, 0, sy, mode);
            return x.adjustedPack(cx, ex, sx, precision, mode, flags);
        case FastClass.zero:
            x = sx ^ sy ? -D.zero : D.zero;
            return ExceptionFlags.none;
        case FastClass.infinite:
            if (!y)
            {
                x = sx ^ sy ? -D.nan : D.nan;
                return ExceptionFlags.invalidOperation | ExceptionFlags.divisionByZero;
            }
            return ExceptionFlags.none;
        case FastClass.quietNaN:
            return ExceptionFlags.none;
        case FastClass.signalingNaN:
            unsignalize(x);
            return ExceptionFlags.invalidOperation;
    }
}

@safe pure nothrow @nogc
ExceptionFlags decimalDiv(T, D)(auto const ref T x, auto const ref D y, out D z, const int precision, const RoundingMode mode)
if (isDecimal!D && isIntegral!T)
{
    alias U = CommonStorage!(D, T);
    U cy; int ey; bool sy;
    int ex = 0;
    bool sx;
    U cx = unsign!U(x, sx);
    final switch (fastDecode(y, cy, ey, sy))
    {
        case FastClass.finite:
            auto flags = coefficientDiv(cx, ex, sx, cy, 0, sy, RoundingMode.implicit);
            flags |= coefficientAdjust(cx, ex, cvt!U(DataType!D.max), sx, RoundingMode.implicit);
            return z.adjustedPack(cvt!(DataType!D)(cx), ex, sx, precision, mode, flags);
        case FastClass.zero:
            z = sx ^ sy ? -D.infinity : D.infinity;
            return ExceptionFlags.divisionByZero;
        case FastClass.infinite:
            z = y;
            return ExceptionFlags.none;
        case FastClass.quietNaN:
            z = sx ^ sy ? -D.nan : D.nan;
            return ExceptionFlags.none;
        case FastClass.signalingNaN:
            z = sx ^ sy ? -D.nan : D.nan;
            return ExceptionFlags.invalidOperation;
    }
}

@safe pure nothrow @nogc
ExceptionFlags decimalDiv(D, F)(ref D x, auto const ref F y, const int precision, const RoundingMode mode)
if (isDecimal!D && isFloatingPoint!F)
{
    alias T = CommonStorage!(D, F);

    T cx, cy; int ex, ey; bool sx, sy;

    ExceptionFlags flags;
    const fx = fastDecode(x, cx, ex, sx);
    const fy = fastDecode(y, cy, ey, sy, mode, flags);

    if (fx == FastClass.signalingNaN)
    {
        x = sx ^ sy ? -D.nan : D.nan;
        return ExceptionFlags.invalidOperation;
    }

    if (fx == FastClass.quietNaN || fy == FastClass.quietNaN)
    {
        x = sx ^ sy ? -D.nan : D.nan;
        return ExceptionFlags.none;
    }

    if (fx == FastClass.infinite)
    {
        if (fy == FastClass.zero)
        {
            x = sx ^ sy ? -D.nan : D.nan;
            return ExceptionFlags.invalidOperation | ExceptionFlags.divisionByZero;
        }

        if (fy == FastClass.infinite)
        {
            x = sx ^ sy ? -D.nan : D.nan;
            return ExceptionFlags.invalidOperation;
        }
        x = sx ^ sy ? -D.infinity : D.infinity;
        return ExceptionFlags.none;
    }

    if (fy == FastClass.infinite)
    {
        x = sx ^ sy ? -D.infinity : D.infinity;
        return ExceptionFlags.none;
    }

    if (fx == FastClass.zero)
    {
        x = sx ^ sy ? -D.zero : D.zero;
        return ExceptionFlags.none;
    }

    if (fy == FastClass.zero)
    {
        x = sx ^ sy ? -D.infinity : D.infinity;
        return ExceptionFlags.divisionByZero;
    }

    flags |= coefficientAdjust(cy, ey, realFloatPrecision!F(0), sy, mode);
    flags |= coefficientDiv(cx, ex, sx, cy, ey, sy, mode);
    return x.adjustedPack(cx, ex, sx, precision, mode, flags);
}

@safe pure nothrow @nogc
ExceptionFlags decimalDiv(F, D)(auto const ref F x, auto const ref D y, out D z, const int precision, const RoundingMode mode)
if (isDecimal!D && isFloatingPoint!F)
{
    alias T = CommonStorage!(D, F);

    T cx, cy; int ex, ey; bool sx, sy;
    ExceptionFlags flags;
    const fx = fastDecode(x, cx, ex, sx, mode, flags);
    const fy = fastDecode(y, cy, ey, sy);

    if (fy == FastClass.signalingNaN)
    {
        z = sx ^ sy ? -D.nan : D.nan;
        return ExceptionFlags.invalidOperation;
    }

    if (fx == FastClass.quietNaN || fy == FastClass.quietNaN)
    {
        z = sx ^ sy ? -D.nan : D.nan;
        return ExceptionFlags.none;
    }

    if (fx == FastClass.infinite)
    {
        if (fy == FastClass.zero)
        {
            z = sx ^ sy ? -D.nan : D.nan;
            return ExceptionFlags.invalidOperation | ExceptionFlags.divisionByZero;
        }

        if (fy == FastClass.infinite)
        {
            z = sx ^ sy ? -D.nan : D.nan;
            return ExceptionFlags.invalidOperation;
        }
        z = sx ^ sy ? -D.infinity : D.infinity;
        return ExceptionFlags.none;
    }

    if (fy == FastClass.infinite)
    {
        z = sx ^ sy ? -D.infinity : D.infinity;
        return ExceptionFlags.none;
    }

    if (fx == FastClass.zero)
    {
        z = sx ^ sy ? -D.zero : D.zero;
        return ExceptionFlags.none;
    }

    if (fy == FastClass.zero)
    {
        z = sx ^ sy ? -D.infinity : D.infinity;
        return ExceptionFlags.divisionByZero;
    }
    flags |= coefficientAdjust(cx, ex, realFloatPrecision!F(0), sx, mode);
    flags |= coefficientDiv(cx, ex, sx, cy, ey, sy, mode);
    return z.adjustedPack(cx, ex, sx, precision, mode, flags);
}

@safe pure nothrow @nogc
ExceptionFlags decimalAdd(D1, D2)(ref D1 x, auto const ref D2 y, const int precision, const RoundingMode mode)
if (isDecimal!(D1, D2))
{
    alias D = CommonDecimal!(D1, D2);
    alias T = DataType!D;
    alias T1 = DataType!D1;

    T cx, cy; int ex, ey; bool sx, sy;

    const fx = fastDecode(x, cx, ex, sx);
    const fy = fastDecode(y, cy, ey, sy);

    if (fx == FastClass.signalingNaN)
    {
        x = sx  ? -D1.nan : D1.nan;
        return ExceptionFlags.invalidOperation;
    }

    if (fy == FastClass.signalingNaN)
    {
        x = sy && (fx == FastClass.quietNaN ? sx : true) ? -D1.nan : D1.nan;
        return ExceptionFlags.invalidOperation;
    }

    if (fx == FastClass.quietNaN)
        return ExceptionFlags.none;

    if (fy == FastClass.quietNaN)
    {
        x = sy ? -D1.nan : D1.nan;
        return ExceptionFlags.none;
    }

    if (fx == FastClass.infinite)
    {
        if (fy == FastClass.infinite && sx != sy)
        {
            x = D1.nan;
            return ExceptionFlags.invalidOperation;
        }
        return ExceptionFlags.none;
    }

    if (fy == FastClass.infinite)
    {
        x = sy ? -D1.infinity : D1.infinity;
        return ExceptionFlags.none;
    }

    if (fx == FastClass.zero)
    {
        if (fy == FastClass.zero)
        {
            x = (mode == RoundingMode.towardNegative && sx != sy)  || (sx && sy) ? -D1.zero : D1.zero;
            return ExceptionFlags.none;
        }
        return decimalToDecimal(y, x, precision, mode);
    }

    if (fy == FastClass.zero)
        return ExceptionFlags.none;

    auto flags = coefficientAdd(cx, ex, sx, cy, ey, sy, mode);
    flags = x.adjustedPack(cx, ex, sx, precision, mode, flags);
    if (x.isZero)
        x = (mode == RoundingMode.towardNegative && sx != sy)  || (sx && sy) ? -D1.zero : D1.zero;
    return flags;
}

@safe pure nothrow @nogc
ExceptionFlags decimalAdd(D, T)(ref D x, auto const ref T y, const int precision, const RoundingMode mode)
if (isDecimal!D && isIntegral!T)
{
    alias U = CommonStorage!(D, T);
    alias X = DataType!D;
    U cx; int ex; bool sx;
    final switch(fastDecode(x, cx, ex, sx))
    {
        case FastClass.finite:
            if (!y)
                return ExceptionFlags.none;
            bool sy;
            U cy = unsign!U(y, sy);
            auto flags = coefficientAdd(cx, ex, sx, cy, 0, sy, RoundingMode.implicit);
            flags |= coefficientAdjust(cx, ex, cvt!U(X.max), sx, RoundingMode.implicit);
            return x.adjustedPack(cvt!X(cx), ex, sx, precision, mode, flags);
        case FastClass.zero:
            return x.packIntegral(y, precision, mode);
        case FastClass.infinite:
        case FastClass.quietNaN:
            return ExceptionFlags.none;
        case FastClass.signalingNaN:
            unsignalize(x);
            return ExceptionFlags.invalidOperation;
    }
}

int realFloatPrecision(F)(const int precision) @nogc nothrow pure @safe
{
    static if (is(F == float))
        return precision == 0 ? 9 : (precision > 9 ? 9 : precision);
    else static if (is(F == double))
        return precision == 0 ? 17 : (precision > 17 ? 17 : precision);
    else
        return precision == 0 ? 21 : (precision > 21 ? 21 : precision);
}

@safe pure nothrow @nogc
ExceptionFlags decimalAdd(D, F)(ref D x, auto const ref F y, const int precision, const RoundingMode mode)
if (isDecimal!D && isFloatingPoint!F)
{
    alias T = CommonStorage!(D, F);
    alias X = DataType!D;

    T cx, cy; int ex, ey; bool sx, sy;
    ExceptionFlags flags;
    const fx = fastDecode(x, cx, ex, sx);
    const fy = fastDecode(y, cy, ey, sy, mode, flags);

    if (fx == FastClass.signalingNaN)
    {
        x = sy ? -D.nan : D.nan;
        return ExceptionFlags.invalidOperation;
    }

    if (fx == FastClass.quietNaN)
        return ExceptionFlags.none;

    if (fy == FastClass.quietNaN)
    {
        x = sy ? -D.nan : D.nan;
        return ExceptionFlags.invalidOperation;
    }

    if (fx == FastClass.infinite)
    {
        if (fy == FastClass.infinite && sx != sy)
        {
            x = sx ? -D.nan : D.nan;
            return ExceptionFlags.invalidOperation;
        }
        return ExceptionFlags.none;
    }

    if (fy == FastClass.infinite)
    {
        x = sy ? -D.infinity : D.infinity;
        return ExceptionFlags.none;
    }

    if (fx == FastClass.zero)
        return x.adjustedPack(cy, ey, sy, realFloatPrecision!F(precision), mode, flags);

    if (fy == FastClass.zero)
        return x.adjustedPack(cx, ex, sx, precision, mode, flags);

    flags |= coefficientAdjust(cy, ey, realFloatPrecision!F(0), sy, mode);
    flags |= coefficientAdd(cx, ex, sx, cy, ey, sy, mode);
    return x.adjustedPack(cx, ex, sx, precision, mode, flags);
}

@safe pure nothrow @nogc
ExceptionFlags decimalAdd(T, D)(auto const ref T x, auto const ref D y, out D z, const int precision, const RoundingMode mode)
if (isDecimal!D && isIntegral!T)
{
    z = y;
    return decimalAdd(z, x, precision, mode);
}

@safe pure nothrow @nogc
ExceptionFlags decimalAdd(F, D)(auto const ref F x, auto const ref D y, out D z, const int precision, const RoundingMode mode)
if (isDecimal!D && isFloatingPoint!F)
{
    z = y;
    return decimalAdd(z, x, precision, mode);
}

@safe pure nothrow @nogc
ExceptionFlags decimalSub(D1, D2)(ref D1 x, auto const ref D2 y, const int precision, const RoundingMode mode)
if (isDecimal!(D1, D2))
{
   return decimalAdd(x, -y, precision, mode);
}

@safe pure nothrow @nogc
ExceptionFlags decimalSub(D, T)(ref D x, auto const ref T y, const int precision, const RoundingMode mode)
if (isDecimal!D && isIntegral!T)
{
    alias U = CommonStorage!(D, T);
    alias X = DataType!D;
    U cx; int ex; bool sx;
    final switch(fastDecode(x, cx, ex, sx))
    {
        case FastClass.finite:
            if (!y)
                return x.adjustedPack(cvt!X(cx), ex, sx, precision, mode, ExceptionFlags.none);
            bool sy;
            U cy = unsign!U(y, sy);
            auto flags = coefficientAdd(cx, ex, sx, cy, 0, !sy, RoundingMode.implicit);
            flags |= coefficientAdjust(cx, ex, cvt!U(X.max), sx, RoundingMode.implicit);
            return x.adjustedPack(cvt!X(cx), ex, sx, precision, mode, flags);
        case FastClass.zero:
            const flags = x.packIntegral(y, precision, mode);
            x = -x;
            return flags;
        case FastClass.infinite:
        case FastClass.quietNaN:
            return ExceptionFlags.none;
        case FastClass.signalingNaN:
            unsignalize(x);
            return ExceptionFlags.invalidOperation;
    }
}

@safe pure nothrow @nogc
ExceptionFlags decimalSub(D, F)(ref D x, auto const ref F y, const int precision, const RoundingMode mode)
if (isDecimal!D && isFloatingPoint!F)
{
    return decimalAdd(x, -y, precision, mode);
}

@safe pure nothrow @nogc
ExceptionFlags decimalSub(T, D)(auto const ref T x, auto const ref D y, out D z, const int precision, const RoundingMode mode)
if (isDecimal!D && isIntegral!T)
{
    z = -y;
    return decimalAdd(z, x, precision, mode);
}

@safe pure nothrow @nogc
ExceptionFlags decimalSub(F, D)(auto const ref F x, auto const ref D y, out D z, const int precision, const RoundingMode mode)
if (isDecimal!D && isFloatingPoint!F)
{
    z = -y;
    return decimalAdd(z, x, precision, mode);
}

@safe pure nothrow @nogc
ExceptionFlags decimalMod(D1, D2)(ref D1 x, auto const ref D2 y, const int precision, const RoundingMode mode)
if (isDecimal!(D1, D2))
{
    alias D = CommonDecimal!(D1, D2);
    alias T = DataType!D;
    alias T1 = DataType!D1;

    T cx, cy; int ex, ey; bool sx, sy;

    const fx = fastDecode(x, cx, ex, sx);
    const fy = fastDecode(y, cy, ey, sy);
    const sxx = sx;

    if (fx == FastClass.signalingNaN)
    {
        unsignalize(x);
        return ExceptionFlags.invalidOperation;
    }

    if (fy == FastClass.signalingNaN)
    {
        x = sy ? -D1.nan : D1.nan;
        return ExceptionFlags.invalidOperation;
    }

    if (fx == FastClass.quietNaN)
        return ExceptionFlags.none;

    if (fy == FastClass.quietNaN)
    {
        x = sy ? -D1.nan : D1.nan;
        return ExceptionFlags.none;
    }

    if (fx == FastClass.infinite)
    {
        x = sx ? -D1.nan : D1.nan;
        return ExceptionFlags.invalidOperation;
    }

    if (fy == FastClass.zero)
    {
        x = sx ? -D1.nan : D1.nan;
        return ExceptionFlags.invalidOperation;
    }

    if (fx == FastClass.zero)
        return ExceptionFlags.none;

    if (fy == FastClass.infinite)
        return ExceptionFlags.none;

    ////coefficientShrink(cx, ex);
    //coefficientShrink(cy, ey);
    //
    //if (cy == 1U && ey == 0)
    //{
    //    //if (cx == 1U && ex == 0)
    //        x = sx ? -D1.zero : D1.zero;
    //    return ExceptionFlags.none;
    //}

    auto flags = coefficientMod(cx, ex, sx, cy, ey, sy, mode);
    flags = x.adjustedPack(cx, ex, sx, precision, mode, flags);
    if (x.isZero)
        x = sxx ? -D1.zero : D1.zero;
    return flags;
}

@safe pure nothrow @nogc
ExceptionFlags decimalMod(D, T)(ref D x, auto const ref T y, const int precision, const RoundingMode mode)
if (isDecimal!D && isIntegral!T)
{
    alias U = CommonStorage!(D, T);
    alias X = DataType!D;

    U cx; int ex; bool sx;
    bool sy;
    U cy = unsign!U(y, sy);

    if (!y)
    {
        x = sx ^ sy ? -D.nan : D.nan;
        return ExceptionFlags.invalidOperation;
    }

    final switch (fastDecode(x, cx, ex, sx))
    {
        case FastClass.finite:
            const flags = coefficientMod(cx, ex, sx, cy, 0, sy, mode);
            return x.adjustedPack(cx, ex, sx, precision, mode, flags);
        case FastClass.zero:
            return ExceptionFlags.none;
        case FastClass.infinite:
            x = sx ? -D.nan : D.nan;
            return ExceptionFlags.invalidOperation;
        case FastClass.quietNaN:
            return ExceptionFlags.none;
        case FastClass.signalingNaN:
            unsignalize(x);
            return ExceptionFlags.invalidOperation;
    }
}

@safe pure nothrow @nogc
ExceptionFlags decimalMod(T, D)(auto const ref T x, auto const ref D y, out D z, const int precision, const RoundingMode mode)
if (isDecimal!D && isIntegral!T)
{
    alias U = CommonStorage!(D, T);
    alias X = DataType!D;
    U cy; int ey; bool sy;
    int ex = 0;
    bool sx;
    U cx = unsign!U(x, sx);
    final switch (fastDecode(y, cy, ey, sy))
    {
        case FastClass.finite:
            if (x == 0)
            {
                z = D.zero;
                return ExceptionFlags.none;
            }
            auto flags = coefficientMod(cx, ex, sx, cy, 0, sy, mode);
            flags |= coefficientAdjust(cx, ex, cvt!U(X.max), sx, RoundingMode.implicit);
            return z.adjustedPack(cvt!X(cx), ex, sx, precision, mode, flags);
        case FastClass.zero:
            z = sy ? -D.nan : D.nan;
            return ExceptionFlags.invalidOperation;
        case FastClass.infinite:
            return z.packIntegral(x, precision, mode);
        case FastClass.quietNaN:
            z = sy ? -D.nan : D.nan;
            return ExceptionFlags.none;
        case FastClass.signalingNaN:
            z = sy ? -D.nan : D.nan;
            return ExceptionFlags.invalidOperation;
    }
}

@safe pure nothrow @nogc
ExceptionFlags decimalMod(D, F)(ref D x, auto const ref F y, const int precision, const RoundingMode mode)
if (isDecimal!D && isFloatingPoint!F)
{
    alias T = CommonStorage!(D, F);

    T cx, cy; int ex, ey; bool sx, sy;
    ExceptionFlags flags;
    const fx = fastDecode(x, cx, ex, sx);
    const fy = fastDecode(y, cy, ey, sy, mode, flags);

    if (fx == FastClass.signalingNaN)
    {
        unsignalize(x);
        return ExceptionFlags.invalidOperation;
    }

    if (fx == FastClass.quietNaN)
        return ExceptionFlags.none;

    if (fy == FastClass.quietNaN)
    {
        x = sy ? -D.nan : D.nan;
        return ExceptionFlags.none;
    }

    if (fx == FastClass.infinite || fy == FastClass.zero)
    {
        x = sx ? -D.nan : D.nan;
        return ExceptionFlags.invalidOperation;
    }

    if (fx == FastClass.zero)
        return ExceptionFlags.none;

    if (fy == FastClass.infinite)
        return ExceptionFlags.none;

    flags |= coefficientAdjust(cy, ey, realFloatPrecision!F(0), sy, mode);
    flags |= coefficientMod(cx, ex, sx, cy, ey, sy, mode);
    return x.adjustedPack(cx, ex, sx, precision, mode, flags);
}

@safe pure nothrow @nogc
ExceptionFlags decimalMod(F, D)(auto const ref F x, auto const ref D y, out D z, const int precision, const RoundingMode mode)
if (isDecimal!D && isFloatingPoint!F)
{
    alias T = CommonStorage!(D, F);
    alias X = DataType!D;

    T cx, cy; int ex, ey; bool sx, sy;
    ExceptionFlags flags;
    const fx = fastDecode(x, cx, ex, sx, mode, flags);
    const fy = fastDecode(y, cy, ey, sy);

    if (fy == FastClass.signalingNaN)
    {
        z = sy ? -D.nan : D.nan;
        return ExceptionFlags.invalidOperation;
    }

    if (fx == FastClass.quietNaN)
    {
        z = sx ? -D.nan : D.nan;
        return ExceptionFlags.none;
    }

    if (fy == FastClass.quietNaN)
    {
        z = sy ? -D.nan : D.nan;
        return ExceptionFlags.none;
    }

    if (fx == FastClass.infinite || fy == FastClass.zero)
    {
        z = sx ? -D.nan : D.nan;
        return ExceptionFlags.invalidOperation;
    }

    if (fy == FastClass.infinite)
        return ExceptionFlags.none;

    flags |= coefficientAdjust(cx, ex, realFloatPrecision!F(0), sx, mode);
    flags |= coefficientMod(cx, ex, sx, cy, ey, sy, mode);
    return z.adjustedPack(cx, ex, sx, precision, mode, flags);
}

@safe pure nothrow @nogc
int decimalCmp(D1, D2)(auto const ref D1 x, auto const ref D2 y)
if (isDecimal!(D1, D2))
{
    //-3 signan
    //-2 nan
    alias D = CommonDecimal!(D1, D2);
    DataType!D cx, cy; int ex, ey; bool sx, sy;
    const fx = fastDecode(x, cx, ex, sx);
    const fy = fastDecode(y, cy, ey, sy);
    final switch(fx)
    {
        case FastClass.finite:
            if (fy == FastClass.finite)
                return coefficientCmp(cx, ex, sx, cy, ey, sy);
            if (fy == FastClass.zero)
                return sx ? -1: 1;
            if (fy == FastClass.infinite)
                return sy ? 1 : -1;
            return fy == FastClass.signalingNaN ? -3 : -2;
        case FastClass.zero:
            if (fy == FastClass.finite || fy == FastClass.infinite)
                return sy ? 1 : -1;
            if (fy == FastClass.zero)
                return 0;
            return fy == FastClass.signalingNaN ? -3 : -2;
        case FastClass.infinite:
            if (fy == FastClass.finite || fy == FastClass.zero)
                return sx ? -1 : 1;
            if (fy == FastClass.infinite)
                return sx == sy ? 0 : (sx ? -1 : 1);
            return fy == FastClass.signalingNaN ? -3 : -2;
        case FastClass.quietNaN:
            return fy == FastClass.signalingNaN ? -3 : -2;
        case FastClass.signalingNaN:
            return -3;
    }
}

@safe pure nothrow @nogc
int decimalCmp(D, T)(auto const ref D x, auto const ref T y)
if (isDecimal!D && isIntegral!T)
{
    alias U = CommonStorage!(D, T);
    U cx; int ex; bool sx;
    final switch(fastDecode(x, cx, ex, sx))
    {
        case FastClass.finite:
            bool sy;
            const cy = unsign!U(y, sy);
            return coefficientCmp(cx, ex, sx, cy, 0, sy);
        case FastClass.zero:
            static if (isUnsigned!T)
                return y == 0 ? 0 : -1;
            else
                return y == 0 ? 0 : (y < 0 ? 1 : -1);
        case FastClass.infinite:
            return sx ? -1 : 1;
        case FastClass.quietNaN:
        case FastClass.signalingNaN:
            return -2;
    }
}

@safe pure nothrow @nogc
int decimalCmp(D, F)(auto const ref D x, auto const ref F y, const int yPrecision, const RoundingMode yMode)
if (isDecimal!D && isFloatingPoint!F)
{
    if (x.isSignalNaN)
        return -3;
    if (x.isNaN || y.isNaN)
        return -2;

    const sx = cast(bool)signbit(x);
    const sy = cast(bool)signbit(y);

    if (x.isZero)
    {
        if (y == 0.0)
            return 0;
        return sy ? 1 : -1;
    }

    if (y == 0.0)
        return sx ? -1 : 1;

    if (sx != sy)
        return sx ? -1 : 1;

    if (x.isInfinity)
    {
        if (y.isInfinity)
            return 0;
        return sx ? -1 : 1;
    }

    if (y.isInfinity)
        return sx ? 1 : -1;

    Unqual!D v = void;
    const flags = v.packFloatingPoint(y, yPrecision, yMode);
    if (flags & ExceptionFlags.overflow)
    {
        //floating point is too big
        return sx ? 1 : -1;
    }
    else if (flags & ExceptionFlags.underflow)
    {
        //floating point is too small
        return sx ? -1 : 1;
    }

    const result = decimalCmp(x, v);

    version (none)
    if (result == 0 && (flags & ExceptionFlags.inexact))
    {
        //seems equal, but float was truncated toward zero, so it's smaller
        return sx ? -1 : 1;
    }

    return result;
}

@safe pure nothrow @nogc
int decimalEqu(D1, D2)(auto const ref D1 x, auto const ref D2 y)
if (isDecimal!(D1, D2))
{
    alias D = CommonDecimal!(D1, D2);
    DataType!D cx, cy; int ex, ey; bool sx, sy;
    const fx = fastDecode(x, cx, ex, sx);
    const fy = fastDecode(y, cy, ey, sy);

    final switch(fx)
    {
        case FastClass.finite:
            if (fy == FastClass.finite)
                return coefficientEqu(cx, ex, sx, cy, ey, sy);
            if (fy == FastClass.zero || fy == FastClass.infinite)
                return 0;
            return fy == FastClass.signalingNaN ? -3 : -2;
        case FastClass.zero:
            if (fy == FastClass.zero)
                return 1;
            if (fy == FastClass.finite || fy == FastClass.infinite)
                return 0;
            return fy == FastClass.signalingNaN ? -3 : -2;
        case FastClass.infinite:
            if (fy == FastClass.infinite)
                return sx == sy ? 1 : 0;
            if (fy == FastClass.finite || fy == FastClass.zero)
                return 0;
            return fy == FastClass.signalingNaN ? -3 : -2;
        case FastClass.quietNaN:
            return fy == FastClass.signalingNaN ? -3 : -2;
        case FastClass.signalingNaN:
            return -3;
    }
}

@safe pure nothrow @nogc
int decimalEqu(D, T)(auto const ref D x, auto const ref T y)
if (isDecimal!D && isIntegral!T)
{
    alias U = CommonStorage!(D, T);
    U cx; int ex; bool sx;
    final switch(fastDecode(x, cx, ex, sx))
    {
        case FastClass.finite:
            bool sy;
            const cy = unsign!U(y, sy);
            return coefficientEqu(cx, ex, sx, cy, 0, sy) ? 1 : 0;
        case FastClass.zero:
            return y == 0 ? 1 : 0;
        case FastClass.infinite:
            return 0;
        case FastClass.quietNaN:
            return -2;
        case FastClass.signalingNaN:
            return -3;
    }
}

@safe pure nothrow @nogc
int decimalEqu(D, F)(auto const ref D x, auto const ref F y, const int yPrecision, const RoundingMode yMode)
if (isDecimal!D && isFloatingPoint!F)
{
    if (x.isSignalNaN)
        return -3;
    if (x.isNaN || y.isNaN)
        return -2;
    if (x.isZero)
        return y == 0.0 ? 1 : 0;
    if (y == 0.0)
        return 0;

    const sx = cast(bool)signbit(x);
    const sy = cast(bool)signbit(y);
    if (sx != sy)
        return 0;

    if (x.isInfinity)
        return y.isInfinity ? 1 : 0;
    if (y.isInfinity)
        return 0;

    Unqual!D v = void;
    const flags = v.packFloatingPoint(y, yPrecision, yMode);
    if (flags)
        return 0;
    else
        return decimalEqu(x, v);
}

@safe pure nothrow @nogc
ExceptionFlags decimalSqrt(D)(ref D x, const int precision, const RoundingMode mode)
if (isDecimal!D)
{
    DataType!D cx; int ex; bool sx;
    final switch(fastDecode(x, cx, ex, sx))
    {
        case FastClass.finite:
            if (sx)
            {
                x = -D.nan;
                return ExceptionFlags.invalidOperation;
            }
            const flags = coefficientSqrt(cx, ex);
            return x.adjustedPack(cx, ex, false, precision, mode, flags);
        case FastClass.zero:
            return ExceptionFlags.none;
        case FastClass.infinite:
            if (sx)
            {
                x = -D.nan;
                return ExceptionFlags.invalidOperation;
            }
            return ExceptionFlags.none;
        case FastClass.quietNaN:
            return ExceptionFlags.none;
        case FastClass.signalingNaN:
            unsignalize(x);
            return ExceptionFlags.invalidOperation;
    }
 }

@safe pure nothrow @nogc
ExceptionFlags decimalRSqrt(D)(ref D x, const int precision, const RoundingMode mode)
if (isDecimal!D)
{
    DataType!D cx; int ex; bool sx;
    final switch(fastDecode(x, cx, ex, sx))
    {
        case FastClass.finite:
            if (sx)
            {
                x = -D.nan;
                return ExceptionFlags.invalidOperation;
            }
            const flags = coefficientRSqrt(cx, ex);
            return x.adjustedPack(cx, ex, false, precision, mode, flags);
        case FastClass.zero:
            x = D.infinity;
            return ExceptionFlags.divisionByZero;
        case FastClass.infinite:
            if (sx)
            {
                x = -D.nan;
                return ExceptionFlags.invalidOperation;
            }
            x = D.zero;
            return ExceptionFlags.none;
        case FastClass.quietNaN:
            return ExceptionFlags.none;
        case FastClass.signalingNaN:
            unsignalize(x);
            return ExceptionFlags.invalidOperation;
    }
}

@safe pure nothrow @nogc
ExceptionFlags decimalSqr(D)(ref D x, const int precision, const RoundingMode mode)
if (isDecimal!D)
{
    DataType!D cx; int ex; bool sx;
    final switch(fastDecode(x, cx, ex, sx))
    {
        case FastClass.finite:
            const flags = coefficientSqr(cx, ex, RoundingMode.implicit);
            return x.adjustedPack(cx, ex, false, precision, mode, flags);
        case FastClass.zero:
            x = D.zero;
            return ExceptionFlags.none;
        case FastClass.infinite:
            x = D.infinity;
            return ExceptionFlags.none;
        case FastClass.quietNaN:
            return ExceptionFlags.none;
        case FastClass.signalingNaN:
            unsignalize(x);
            return ExceptionFlags.invalidOperation;
    }
}

@safe pure nothrow @nogc
ExceptionFlags decimalCbrt(D)(ref D x, const int precision, const RoundingMode mode)
if (isDecimal!D)
{
    DataType!D cx; int ex; bool sx;
    final switch(fastDecode(x, cx, ex, sx))
    {
        case FastClass.finite:
            const flags = coefficientCbrt(cx, ex);
            return x.adjustedPack(cx, ex, sx, precision, mode, flags);
        case FastClass.zero:
        case FastClass.infinite:
        case FastClass.quietNaN:
            return ExceptionFlags.none;
        case FastClass.signalingNaN:
            unsignalize(x);
            return ExceptionFlags.invalidOperation;
    }
}

@safe pure nothrow @nogc
ExceptionFlags decimalHypot(D1, D2, D)(auto const ref D1 x, auto const ref D2 y, out D z,
    const int precision, const RoundingMode mode)
if (isDecimal!(D1, D2) && is(D: CommonDecimal!(D1, D2)))
{
    alias U = DataType!D;

    U cx, cy; int ex, ey; bool sx, sy;

    const fx = fastDecode(x, cx, ex, sx);
    const fy = fastDecode(y, cy, ey, sy);

    if (fx == FastClass.signalingNaN || fy == FastClass.signalingNaN)
    {
        z = D.nan;
        return ExceptionFlags.invalidOperation;
    }

    if (fx == FastClass.infinite || fy == FastClass.infinite)
    {
        z = D.infinity;
        return ExceptionFlags.none;
    }

    if (fx == FastClass.quietNaN || fy == FastClass.quietNaN)
    {
        z = D.nan;
        return ExceptionFlags.none;
    }

    if (fx == FastClass.zero)
        return z.adjustedPack(cy, cy ? ey : 0, false, precision, mode, ExceptionFlags.none);

    if (fy == FastClass.zero)
        return z.adjustedPack(cx, cx ? ex : 0, false, precision, mode, ExceptionFlags.none);

    auto flags = coefficientHypot(cx, ex, cy, ey);
    return z.adjustedPack(cx, ex, false, precision, mode, flags);
}

@safe pure nothrow @nogc
ExceptionFlags decimalFMA(D1, D2, D3, D)(auto const ref D1 x, auto const ref D2 y, auto const ref D3 z,
    out D result, const int precision, const RoundingMode mode)
if (isDecimal!(D1, D2, D3) && is(D : CommonDecimal!(D1, D2, D3)))
{
    alias U = DataType!D;

    U cx, cy, cz; int ex, ey, ez; bool sx, sy, sz;

    const fx = fastDecode(x, cx, ex, sx);
    const fy = fastDecode(y, cy, ey, sy);
    const fz = fastDecode(z, cz, ez, sz);

    if (fx == FastClass.signalingNaN || fy == FastClass.signalingNaN || fz == FastClass.signalingNaN)
    {
        result = D.nan;
        return ExceptionFlags.invalidOperation;
    }

    if (fx == FastClass.quietNaN || fy == FastClass.quietNaN || fz == FastClass.quietNaN)
    {
        result = D.nan;
        return ExceptionFlags.none;
    }

    if (fx == FastClass.infinite)
    {
        if (fy == FastClass.zero)
        {
            result = D.nan;
            return ExceptionFlags.invalidOperation;
        }

        if (fz == FastClass.infinite)
        {
            if ((sx ^ sy) != sz)
            {
                result = D.nan;
                return ExceptionFlags.invalidOperation;
            }
        }
        result = sx ^ sy ? -D.infinity : D.infinity;
        return ExceptionFlags.none;
    }

    if (fy == FastClass.infinite)
    {
        if (fx == FastClass.zero)
        {
            result = D.nan;
            return ExceptionFlags.invalidOperation;
        }

        if (fz == FastClass.infinite)
        {
            if ((sx ^ sy) != sz)
            {
                result = D.nan;
                return ExceptionFlags.invalidOperation;
            }
        }
        result = sx ^ sy ? -D.infinity : D.infinity;
        return ExceptionFlags.none;
    }

    if (fz == FastClass.infinite)
    {
        const flags = coefficientMul(cx, ex, sx, cy, ey, sy, mode);
        if (flags & ExceptionFlags.overflow)
        {
            if (sy != sx)
                return result.invalidPack(sz, U(0U));
            else
                return result.infinityPack(sz);
        }
        return result.infinityPack(sz);
    }

    if (fx == FastClass.zero || fy == FastClass.zero)
        return result.adjustedPack(cz, ez, sz, precision, mode, ExceptionFlags.none);

    if (fz == FastClass.zero)
    {
        const flags = coefficientMul(cx, ex, sx, cy, ey, sy, RoundingMode.implicit);
        return result.adjustedPack(cx, ex, sx, precision, mode, flags);
    }

    const flags = coefficientFMA(cx, ex, sx, cy, ey, sy, cz, ez, sz, mode);
    return result.adjustedPack(cx, ex, sx, precision, mode, flags);
}

ExceptionFlags decimalPow(D, T)(ref D x, const T n, const int precision, const RoundingMode mode)
if (isDecimal!D & isIntegral!T)
{
    DataType!D cx; int ex; bool sx;

    final switch (fastDecode(x, cx, ex, sx))
    {
        case FastClass.finite:
            if (!n)
            {
                x = D.one;
                return ExceptionFlags.none;
            }

            DataType!D cv; int ev; bool sv;
            ExceptionFlags flags;
            static if (isSigned!T)
            {
                auto m = unsign!(Unsigned!T)(n);
                if (n < 0)
                {
                    cv = 1U;
                    ev = 0;
                    sv = false;
                    flags = coefficientDiv(cv, ev, sv, cx, ex, sx, RoundingMode.implicit);
                }
                else
                {
                    cv = cx;
                    ev = ex;
                    sv = sx;
                }
            }
            else
            {
                Unqual!T m = n;
                cv = cx;
                ev = ex;
                sv = sx;
            }

            cx = 1U;
            ex = 0;
            sx = false;

            ExceptionFlags sqrFlags;
            while (m)
            {
                if (m & 1)
                {
                    flags |= sqrFlags | coefficientMul(cx, ex, sx, cv, ev, sv, RoundingMode.implicit);
                    sqrFlags = ExceptionFlags.none;
                    if (flags & (ExceptionFlags.overflow | ExceptionFlags.underflow))
                        break;
                }
                m >>>= 1;
                sqrFlags |= coefficientSqr(cv, ev, RoundingMode.implicit);
                sv = false;
            }

            return x.adjustedPack(cx, ex, sx, precision, mode, flags);
        case FastClass.zero:
            if (!n)
                x = D.one;
            else
            {
                if (n & 1) //odd
                    return n < 0 ? ExceptionFlags.divisionByZero : ExceptionFlags.none;
                else //even
                {
                    if (n < 0)
                        return ExceptionFlags.divisionByZero;
                    else
                    {
                        x = D.zero;
                        return ExceptionFlags.none;
                    }
                }
            }
            return ExceptionFlags.none;
        case FastClass.infinite:
            if (!n)
                x = D.one;
            else
                x = !sx || (n & 1) ? D.infinity : -D.infinity;
            return ExceptionFlags.none;
        case FastClass.quietNaN:
            if (!n)
                x = D.one;
            return ExceptionFlags.none;
        case FastClass.signalingNaN:
            unsignalize(x);
            return ExceptionFlags.invalidOperation;
    }
}

ExceptionFlags decimalPow(D1, D2)(ref D1 x, auto const ref D2 y, const int precision, const RoundingMode mode)
if (isDecimal!(D1, D2))
{
    long ip;
    auto flags = decimalToSigned(y, ip, mode);
    if (flags == ExceptionFlags.none)
        return decimalPow(x, ip, precision, mode);

    flags = decimalLog(x, 0, mode);
    flags |= decimalMul(x, y, 0, mode);
    flags |= decimalExp(x, precision, mode);
    return flags;
}

ExceptionFlags decimalPow(D, F)(ref D x, auto const ref F y, const int precision, const RoundingMode mode)
if (isDecimal!D && isFloatingPoint!F)
{
    Unqual!D z;
    auto flags = z.packFloatingPoint(y, precision, mode);
    flags |= decimalPow(x, z, precision, mode);
    return flags;
}

ExceptionFlags decimalPow(T, D)(auto const ref T x, auto const ref D y, out D result, const int precision, const RoundingMode mode)
if (isDecimal!D && isIntegral!T)
{
    Decimal128 r = x;
    auto flags = decimalPow(r, y, precision, mode);
    flags |= decimalToDecimal(r, result, precision, mode);
    return flags;
}

ExceptionFlags decimalPow(F, D)(auto const ref F x, auto const ref D y, out D result, const int precision, const RoundingMode mode)
if (isDecimal!D && isFloatingPoint!F)
{
    Decimal128 r = x;
    auto flags = decimalPow(r, y, precision, mode);
    flags |= decimalToDecimal(r, result, precision, mode);
    return flags;
}

ExceptionFlags decimalExp(D)(ref D x, const int precision, const RoundingMode mode)
if (isDecimal!D)
{
    if (x.isSignalNaN)
    {
        x = D.nan;
        return ExceptionFlags.invalidOperation;
    }

    if (x.isZero)
    {
        x = D.one;
        return ExceptionFlags.none;
    }

    if (x.isNaN)
        return ExceptionFlags.none;

    if (x.isInfinity)
    {
        x = signbit(x) ? D.zero : D.infinity;
        return ExceptionFlags.none;
    }

    long n;
    const flags = decimalToSigned(x, n, mode);
    if (flags == ExceptionFlags.none)
    {
        x = D.E;
        return decimalPow(x, n, precision, mode);
    }

    static if (is(D : Decimal32))
    {
        enum lnmax = Decimal32("+223.3507");
        enum lnmin = Decimal32("-232.5610");
    }
    else static if (is(D: Decimal64))
    {
        enum lnmax = Decimal64("+886.4952608027075");
        enum lnmin = Decimal64("-916.4288670116301");
    }
    else
    {
        enum lnmax = Decimal128("+14149.38539644841072829055748903541");
        enum lnmin = Decimal128("-14220.76553433122614449511522413063");
    }

    if (isLess(x, lnmin))
    {
        x = D.zero;
        return ExceptionFlags.underflow | ExceptionFlags.inexact;
    }

    if (isGreater(x, lnmax))
    {
        x = D.infinity;
        return ExceptionFlags.overflow | ExceptionFlags.inexact;
    }

    DataType!D cx;
    int ex;
    bool sx = x.unpack(cx, ex);
    const flags2 = coefficientExp(cx, ex, sx);
    return x.adjustedPack(cx, ex, sx, precision, mode, flags2);
}

ExceptionFlags decimalLog(D)(ref D x, const int precision, const RoundingMode mode)
if (isDecimal!D)
{
    if (x.isSignalNaN)
    {
        x = D.nan;
        return ExceptionFlags.invalidOperation;
    }

    if (x.isNaN)
        return ExceptionFlags.none;

    if (signbit(x))
    {
        x = D.nan;
        return ExceptionFlags.invalidOperation;
    }

    if (x.isInfinity)
    {
        x = D.infinity;
        return ExceptionFlags.none;
    }

    if (x.isZero)
    {
        x = -D.infinity;
        return ExceptionFlags.divisionByZero;
    }

    DataType!D cx;
    int ex;
    bool sx = x.unpack(cx, ex);
    const flags = coefficientLog(cx, ex, sx);
    return x.adjustedPack(cx, ex, sx, precision, mode, flags);
}

ExceptionFlags decimalExp10(D)(out D x, int n, const int precision, const RoundingMode mode)
if (isDecimal!D)
{
    if (n == 0)
    {
        x = D.one;
        return ExceptionFlags.none;
    }
    alias T = DataType!D;
    return x.adjustedPack(T(1U), n, false, precision, mode, ExceptionFlags.none);
}

ExceptionFlags decimalExp10(D)(ref D x, const int precision, const RoundingMode mode)
if (isDecimal!D)
{
    if (x.isSignalNaN)
    {
        x = D.nan;
        return ExceptionFlags.invalidOperation;
    }

    if (x.isZero)
    {
        x = D.one;
        return ExceptionFlags.none;
    }

    if (x.isNaN)
        return ExceptionFlags.none;

    if (x.isInfinity)
    {
        x = signbit(x) ? D.zero : D.infinity;
        return ExceptionFlags.none;
    }

    int n;
    auto flags = decimalToSigned(x, n, RoundingMode.implicit);
    if (flags == ExceptionFlags.none)
        return decimalExp10(x, n, precision, mode);

    flags = decimalMul(x, D.LN10, 0, mode);
    flags |= decimalExp(x, precision, mode);
    return flags;
}

ExceptionFlags decimalExp10m1(D)(ref D x, const int precision, const RoundingMode mode)
if (isDecimal!D)
{
    if (x.isSignalNaN)
    {
        x = D.nan;
        return ExceptionFlags.invalidOperation;
    }

    if (x.isZero)
        return ExceptionFlags.none;

    if (x.isNaN)
        return ExceptionFlags.none;

    if (x.isInfinity)
    {
        x = signbit(x) ? -D.one : D.infinity;
        return ExceptionFlags.none;
    }

    auto flags = decimalExp10(x, 0, mode);
    flags |= decimalAdd(x, -1, precision, mode);
    return flags;
}

ExceptionFlags decimalExpm1(D)(ref D x, const int precision, const RoundingMode mode)
if (isDecimal!D)
{
    if (x.isSignalNaN)
    {
        x = D.nan;
        return ExceptionFlags.invalidOperation;
    }

    if (x.isZero)
        return ExceptionFlags.none;

    if (x.isNaN)
        return ExceptionFlags.none;

    if (x.isInfinity)
    {
        x = signbit(x) ? -D.one : D.infinity;
        return ExceptionFlags.none;
    }

    auto flags = decimalExp(x, 0, mode);
    flags |= decimalAdd(x, -1, precision, mode);
    return flags;
}

ExceptionFlags decimalExp2(D)(ref D x, const int precision, const RoundingMode mode)
if (isDecimal!D)
{
    if (x.isSignalNaN)
    {
        x = D.nan;
        return ExceptionFlags.invalidOperation;
    }

    if (x.isZero)
    {
        x = D.one;
        return ExceptionFlags.none;
    }

    if (x.isNaN)
        return ExceptionFlags.none;

    if (x.isInfinity)
    {
        x = signbit(x) ? D.zero : D.infinity;
        return ExceptionFlags.none;
    }

    int n;
    auto flags = decimalToSigned(x, n, RoundingMode.implicit);
    if (flags == ExceptionFlags.none)
    {
        x = D.two;
        return decimalPow(x, n, precision, mode);
    }

    flags = decimalMul(x, D.LN2, 0, mode);
    flags |= decimalExp(x, precision, mode);
    return flags;
}

ExceptionFlags decimalExp2m1(D)(ref D x, const int precision, const RoundingMode mode)
if (isDecimal!D)
{
    if (x.isSignalNaN)
    {
        x = D.nan;
        return ExceptionFlags.invalidOperation;
    }

    if (x.isZero)
        return ExceptionFlags.none;

    if (x.isNaN)
        return ExceptionFlags.none;

    if (x.isInfinity)
    {
        x = signbit(x) ? -D.one : D.infinity;
        return ExceptionFlags.none;
    }

    auto flags = decimalExp2(x, 0, mode);
    flags |= decimalAdd(x, -1, precision, mode);
    return flags;
}

ExceptionFlags decimalLog2(D)(ref D x, const int precision, const RoundingMode mode)
if (isDecimal!D)
{
    auto flags = decimalLog(x, 0, mode);
    flags |= decimalDiv(x, D.LN2, precision, mode);
    return flags;
}

ExceptionFlags decimalLog10(D)(ref D x, const int precision, const RoundingMode mode)
if (isDecimal!D)
{
    if (x.isSignalNaN)
    {
        x = D.nan;
        return ExceptionFlags.invalidOperation;
    }

    if (x.isNaN)
        return ExceptionFlags.none;

    if (signbit(x))
    {
        x = D.nan;
        return ExceptionFlags.invalidOperation;
    }

    if (x.isInfinity)
    {
        x = D.infinity;
        return ExceptionFlags.none;
    }

    if (x.isZero)
    {
        x = -D.infinity;
        return ExceptionFlags.divisionByZero;
    }

    DataType!D c;
    int e;
    x.unpack(c, e);
    coefficientShrink(c, e);

    Unqual!D y = e;
    auto flags = decimalMul(y, D.LN10, 0, RoundingMode.implicit);
    x = c;
    flags |= decimalLog(x, 0, mode);
    flags |= decimalAdd(x, y, precision, mode);
    return flags;
}

ExceptionFlags decimalLogp1(D)(ref D x, const int precision, const RoundingMode mode)
if (isDecimal!D)
{
    auto flags = decimalAdd(x, 1U, 0, mode);
    flags |= decimalLog(x);
    return flags;
}

ExceptionFlags decimalLog2p1(D)(ref D x, const int precision, const RoundingMode mode)
if (isDecimal!D)
{
    auto flags = decimalAdd(x, 1U, 0, mode);
    flags |= decimalLog2(x, precision, mode);
    return flags;
}

ExceptionFlags decimalLog10p1(D)(ref D x, const int precision, const RoundingMode mode)
if (isDecimal!D)
{
    auto flags = decimalAdd(x, 1U, 0, mode);
    flags |= decimalLog10(x, precision, mode);
    return flags;
}

ExceptionFlags decimalCompound(D)(ref D x, const int n, const int precision, const RoundingMode mode)
if (isDecimal!D)
{
    if (x.isSignalNaN)
    {
        x = D.nan;
        return ExceptionFlags.invalidOperation;
    }

    if (isLess(x, -D.one))
    {
        x = D.nan;
        return ExceptionFlags.invalidOperation;
    }

    if (n == 0)
    {
        x = D.one;
        return ExceptionFlags.none;
    }

    if (x == -1 && n < 0)
    {
        x = D.infinity;
        return ExceptionFlags.divisionByZero;
    }

    if (x == -1)
    {
        x = D.zero;
        return ExceptionFlags.none;
    }

    if (x.isNaN)
        return ExceptionFlags.none;

    if (x.isInfinity)
    {
        if (signbit(x))
            x = n & 1 ? -D.infinity : D.infinity;
        else
            x = D.infinity;
        return ExceptionFlags.none;
    }

    Unqual!D y = x;
    auto flags = decimalAdd(x, 1U, 0, mode);
    if ((flags & ExceptionFlags.overflow) && n < 0)
    {
        x = y;
        flags &= ~ExceptionFlags.overflow;
    }

    if (flags & ExceptionFlags.overflow)
        return flags;

    flags |= decimalPow(x, n, precision, mode);
    return flags;
}

ExceptionFlags decimalRoot(D, T)(ref D x, const T n, const int precision, const RoundingMode mode)
if (isDecimal!D && isIntegral!T)
{
    if (x.isSignalNaN)
    {
        x = D.nan;
        return ExceptionFlags.invalidOperation;
    }

    if (!n)
    {
        x = D.nan;
        return ExceptionFlags.invalidOperation;
    }

    if (n == -1)
    {
        return ExceptionFlags.overflow | ExceptionFlags.underflow;
    }

    if (x.isNaN)
        return ExceptionFlags.none;

    if (x.isInfinity)
    {
        x = !signbit(x) || (n & 1) ? D.infinity : -D.infinity;
    }

    if (x.isZero)
    {
        if (n & 1) //odd
        {
            if (n < 0)
            {
                x = signbit(x) ? -D.infinity : D.infinity;
                return ExceptionFlags.divisionByZero;
            }
            else
                return ExceptionFlags.none;
        }
        else //even
        {
            if (n < 0)
            {
                x = D.infinity;
                return ExceptionFlags.divisionByZero;
            }
            else
            {
                x = D.zero;
                return ExceptionFlags.none;
            }
        }
    }

    if (n == 1)
        return ExceptionFlags.none;
    Unqual!D y = 1U;
    auto flags = decimalDiv(y, n, 0, mode);
    flags |= decimalPow(x, y, precision, mode);
    return flags;
}

ExceptionFlags decimalSin(D)(ref D x, const int precision, const RoundingMode mode)
if (isDecimal!D)
{
    DataType!D cx; int ex; bool sx;
    switch(fastDecode(x, cx, ex, sx))
    {
        case FastClass.signalingNaN:
            unsignalize(x);
            return ExceptionFlags.invalidOperation;
        case FastClass.infinite:
            x = sx ? -D.nan : D.nan;
            return ExceptionFlags.invalidOperation;
        case FastClass.quietNaN:
        case FastClass.zero:
            return ExceptionFlags.none;
        default:
            int quadrant;
            auto flags = coefficientCapAngle(cx, ex, sx, quadrant);
            switch (quadrant)
            {
                case 1:
                    flags |= coefficientSinQ(cx, ex, sx);
                    break;
                case 2:
                    flags |= coefficientCosQ(cx, ex, sx);
                    break;
                case 3:
                    flags |= coefficientSinQ(cx, ex, sx);
                    sx = !sx;
                    break;
                case 4:
                    flags |= coefficientCosQ(cx, ex, sx);
                    sx = !sx;
                    break;
                default:
                    assert(0);
            }
            return x.adjustedPack(cx, ex, sx, precision, mode, flags);
    }
}

ExceptionFlags decimalCos(D)(ref D x, const int precision, const RoundingMode mode)
if (isDecimal!D)
{
    DataType!D cx; int ex; bool sx;
    switch(fastDecode(x, cx, ex, sx))
    {
        case FastClass.signalingNaN:
            return ExceptionFlags.invalidOperation;
        case FastClass.infinite:
            x = sx ? -D.nan : D.nan;
            return ExceptionFlags.invalidOperation;
        case FastClass.quietNaN:
            return ExceptionFlags.none;
        case FastClass.zero:
            x = D.one;
            return ExceptionFlags.none;
        default:
            int quadrant;
            auto flags = coefficientCapAngle(cx, ex, sx, quadrant);
            switch (quadrant)
            {
                case 1:
                    flags |= coefficientCosQ(cx, ex, sx);
                    break;
                case 2:
                    flags |= coefficientSinQ(cx, ex, sx);
                    sx = !sx;
                    break;
                case 3:
                    flags |= coefficientCosQ(cx, ex, sx);
                    sx = !sx;
                    break;
                case 4:
                    flags |= coefficientSinQ(cx, ex, sx);
                    break;
                default:
                    assert(0);
            }
            return x.adjustedPack(cx, ex, sx, precision, mode, flags);
    }
}

ExceptionFlags decimalTan(D)(ref D x, const int precision, const RoundingMode mode)
if (isDecimal!D)
{
    DataType!D cx; int ex; bool sx;
    switch(fastDecode(x, cx, ex, sx))
    {
        case FastClass.signalingNaN:
            return ExceptionFlags.invalidOperation;
        case FastClass.infinite:
            x = sx ? -D.nan : D.nan;
            return ExceptionFlags.invalidOperation;
        case FastClass.quietNaN:
        case FastClass.zero:
            return ExceptionFlags.none;
        default:
            int quadrant;
            auto flags = coefficientCapAngle(cx, ex, sx, quadrant);
            DataType!D csin, ccos; int esin, ecos; bool ssin, scos;
            flags |= coefficientSinCosQ(cx, ex, sx, csin, esin, ssin, ccos, ecos, scos);
            switch (quadrant)
            {
                case 1:
                    //sin/cos, -sin/-cos
                case 3:
                    cx = csin; ex = esin; sx = ssin;
                    flags |= coefficientDiv(cx, ex, sx, ccos, ecos, scos, RoundingMode.implicit);
                    break;
                case 2:
                    //cos/-sin
                    cx = ccos; ex = ecos; sx = scos;
                    flags |= coefficientDiv(cx, ex, sx, csin, esin, !ssin, RoundingMode.implicit);
                    break;
                case 4://-cos/sin
                    cx = ccos; ex = ecos; sx = !scos;
                    flags |= coefficientDiv(cx, ex, sx, csin, esin, ssin, RoundingMode.implicit);
                    break;
                default:
                    assert(0);
            }
            return x.adjustedPack(cx, ex, sx, precision, mode, flags);
    }
}

ExceptionFlags decimalAtan(D)(ref D x, const int precision, const RoundingMode mode)
if (isDecimal!D)
{
    DataType!D cx; int ex; bool sx;
    switch (fastDecode(x, cx, ex, sx))
    {
        case FastClass.signalingNaN:
            return ExceptionFlags.invalidOperation;
        case FastClass.quietNaN:
        case FastClass.zero:
            return ExceptionFlags.none;
        case FastClass.infinite:
            x = signbit(x) ? -D.PI_2 : D.PI_2;
            return decimalAdjust(x, precision, mode);
        default:
            DataType!D reductions;
            coefficientCapAtan(cx, ex, sx, reductions);
            auto flags = coefficientAtan(cx, ex, sx);
            if (reductions)
            {
                flags |= coefficientMul(cx, ex, sx, reductions, 0, false, RoundingMode.implicit);
                flags |= coefficientMul(cx, ex, sx, DataType!D(2U), 0, false, RoundingMode.implicit);
            }
            return x.adjustedPack(cx, ex, sx, precision, mode, flags);
    }
}

ExceptionFlags decimalSinPi(D)(ref D x, const int precision, const RoundingMode mode)
if (isDecimal!D)
{
    if (x.isSignalNaN || x.isInfinity)
    {
        x = D.nan;
        return ExceptionFlags.invalidOperation;
    }

    if (x.isNaN)
        return ExceptionFlags.none;

    decimalReduceAngle(x);

    auto flags = decimalMul(x, D.PI, 0, mode);
    flags |= decimalSin(x, precision, mode);
    return flags;
}

ExceptionFlags decimalCosPi(D)(ref D x, const int precision, const RoundingMode mode)
if (isDecimal!D)
{
    if (x.isSignalNaN || x.isInfinity)
    {
        x = D.nan;
        return ExceptionFlags.invalidOperation;
    }

    if (x.isNaN)
        return ExceptionFlags.none;

    decimalReduceAngle(x);

    auto flags = decimalMul(x, D.PI, 0, mode);
    flags |= decimalCos(x, precision, mode);
    return flags;
}

ExceptionFlags decimalAtanPi(D)(ref D x, const int precision, const RoundingMode mode)
if (isDecimal!D)
{
    if (x.isSignalNaN)
    {
        x = D.nan;
        return ExceptionFlags.invalidOperation;
    }

    if (x.isNaN || x.isZero)
        return ExceptionFlags.none;

    if (x.isInfinity)
    {
        x = signbit(x) ? -D.half : D.half;
        return ExceptionFlags.none;
    }

    const bool sx = cast(bool)signbit(x);
    x = fabs(x);

    //if (decimalEqu(x, D.SQRT3))
    //{
    //    x = sx ? -D.onethird : D.onethird;
    //    return ExceptionFlags.none;
    //}
    //
    //if (decimalEqu(x, D.one))
    //{
    //    x = sx ? -D.quarter : D.quarter;
    //    return ExceptionFlags.none;
    //}
    //
    //if (decimalEqu(x, D.M_SQRT3))
    //{
    //    x = sx ? -D._1_6 : D._1_6;
    //    return ExceptionFlags.none;
    //}

    auto flags = decimalAtan(x, 0, mode);
    flags |= decimalDiv(x, D.PI, precision, mode);
    return flags;
}

ExceptionFlags decimalAtan2(D1, D2, D3)(auto const ref D1 y, auto const ref D2 x, out D3 z, const int precision, const RoundingMode mode)
{
    alias D = CommonDecimal!(D1, D2);

    if (x.isSignalNaN || y.isSignalNaN)
    {
        z = D.nan;
        return ExceptionFlags.invalidOperation;
    }

    if (x.isNaN || y.isNaN)
    {
        z = D.nan;
        return ExceptionFlags.none;
    }

    if (y.isZero)
    {
        if (signbit(x))
            z = signbit(y) ? -D.PI : D.PI;
        else
            z = signbit(y) ? -D.zero : D.zero;
        return ExceptionFlags.inexact;
    }

    if (x.isZero)
    {
        z = signbit(y) ? -D.PI_2 : D.PI_2;
        return ExceptionFlags.inexact;
    }

    if (y.isInfinity)
    {
        if (x.isInfinity)
        {
            if (signbit(x))
                z = signbit(y) ? -D._3PI_4 : D._3PI_4;
            else
                z = signbit(y) ? -D.PI_4 : D.PI_4;
        }
        else
            z = signbit(y) ? -D.PI_2 : D.PI_2;
        return ExceptionFlags.inexact;
    }

    if (x.isInfinity)
    {
        if (signbit(x))
            z = signbit(y) ? -D.PI : D.PI;
        else
            z = signbit(y) ? -D.zero : D.zero;
        return ExceptionFlags.inexact;
    }

    z = y;
    D xx = x;
    auto flags = decimalDiv(z, xx, 0, mode);
    z = fabs(z);
    flags |= decimalAtan(z, 0, mode);

    if (signbit(x))
    {
        z = -z;
        flags |= decimalAdd(z, D.PI, precision, mode);
        return flags & ExceptionFlags.inexact;
    }
    else
    {
        flags |= decimalAdjust(z, precision, mode);
        return flags & (ExceptionFlags.inexact | ExceptionFlags.underflow);
    }
}

ExceptionFlags decimalAtan2Pi(D1, D2, D3)(auto const ref D1 y, auto const ref D2 x, out D3 z, const int precision, const RoundingMode mode)
if (isDecimal!(D1, D2, D3))
{
    alias D = CommonDecimal!(D1, D2);

    if (x.isSignalNaN || y.isSignalNaN)
    {
        z = D.nan;
        return ExceptionFlags.invalidOperation;
    }

    if (x.isNaN || y.isNaN)
    {
        z = D.nan;
        return ExceptionFlags.none;
    }

    if (y.isZero)
    {
        if (signbit(x))
            z = signbit(y) ? -D.one : D.one;
        else
            z = signbit(y) ? -D.zero : D.zero;
        return ExceptionFlags.inexact;
    }

    if (x.isZero)
    {
        z = signbit(y) ? -D.half : D.half;
        return ExceptionFlags.inexact;
    }

    if (y.isInfinity)
    {
        if (x.isInfinity)
        {
            if (signbit(x))
                z = signbit(y) ? -D.threequarters : D.threequarters;
            else
                z = signbit(y) ? -D.quarter : D.quarter;
        }
        else
            z = signbit(y) ? -D.half : D.half;
        return ExceptionFlags.inexact;
    }

    if (x.isInfinity)
    {
        if (signbit(x))
            z = signbit(y) ? -D.one : D.one;
        else
            z = signbit(y) ? -D.zero : D.zero;
        return ExceptionFlags.inexact;
    }
    auto flags = decimalAtan2(y, x, z, 0, mode);
    flags |= decimalDiv(z, D.PI, precision, mode);
    return flags;
}

ExceptionFlags decimalAsin(D)(ref D x, const int precision, const RoundingMode mode)
{
    if (x.isSignalNaN)
    {
        x = D.nan;
        return ExceptionFlags.invalidOperation;
    }

    if (x.isNaN)
        return ExceptionFlags.none;

    if (isLess(x, -D.one) || isGreater(x, D.one))
    {
        x = D.nan;
        return ExceptionFlags.invalidOperation;
    }

    if (x.isZero)
        return ExceptionFlags.none;

    if (x == -D.one)
    {
        x = -D.PI_2;
        return decimalAdjust(x, precision, mode);
    }

    if (x == D.one)
    {
        x = D.PI_2;
        return ExceptionFlags.none;
    }

    if (x == -D.SQRT3_2)
    {
        x = -D.PI_3;
        return ExceptionFlags.none;
    }

    if (x == -D.SQRT2_2)
    {
        x = -D.PI_4;
        return ExceptionFlags.none;
    }

    if (x == -D.half)
    {
        x  = -D.PI_6;
        return ExceptionFlags.none;
    }

    if (x == D.half)
    {
        x  = D.PI_6;
        return ExceptionFlags.none;
    }

    if (x == D.SQRT2_2)
    {
        x = D.PI_4;
        return ExceptionFlags.none;
    }

    if (x == D.SQRT3_2)
    {
        x = D.PI_6;
        return ExceptionFlags.none;
    }

    //asin(x) = 2 * atan(x / ( 1 + sqrt(1 - x* x))
    Unqual!D x2 = x;
    auto flags = decimalSqr(x2, 0, mode);
    x2 = -x2;
    flags |= decimalAdd(x2, 1U, 0, mode);
    flags |= decimalSqrt(x2, 0, mode);
    flags |= decimalAdd(x2, 1U, 0, mode);
    flags |= decimalDiv(x, x2, 0, mode);
    flags |= decimalAtan(x, 0, mode);
    flags |= decimalMul(x, 2U, precision, mode);
    return flags;
}

ExceptionFlags decimalAcos(D)(ref D x, const int precision, const RoundingMode mode)
{
    if (x.isSignalNaN)
    {
        x = D.nan;
        return ExceptionFlags.invalidOperation;
    }

    if (x.isNaN)
        return ExceptionFlags.none;

    if (isLess(x, -D.one) || isGreater(x, D.one))
    {
        x = D.nan;
        return ExceptionFlags.invalidOperation;
    }

    if (x.isZero)
    {
        x = D.PI_2;
        return decimalAdjust(x, precision, mode);
    }

    if (x == -D.one)
    {
        x = D.PI;
        return decimalAdjust(x, precision, mode);
    }

    if (x == D.one)
    {
        x = D.zero;
        return ExceptionFlags.none;
    }

    if (x == -D.SQRT3_2)
    {
        x = D._5PI_6;
        return ExceptionFlags.none;
    }

    if (x == -D.SQRT2_2)
    {
        x = D._3PI_4;
        return ExceptionFlags.none;
    }

    if (x == -D.half)
    {
        x  = D._2PI_3;
        return ExceptionFlags.none;
    }

    if (x == D.half)
    {
        x  = D.PI_2;
        return ExceptionFlags.none;
    }

    if (x == D.SQRT2_2)
    {
        x = D.PI_4;
        return ExceptionFlags.none;
    }

    if (x == D.SQRT3_2)
    {
        x = D.PI_6;
        return ExceptionFlags.none;
    }

    Unqual!D x2 = x;
    auto flags = decimalSqr(x2, 0, mode);
    x2 = -x2;
    flags |= decimalAdd(x2, 1U, 0, mode);
    flags |= decimalSqrt(x2, 0, mode);
    flags |= decimalAdd(x, 1U, 0, mode);
    flags |= decimalDiv(x2, x, 0, mode);
    x = x2;
    flags |= decimalAtan(x, 0, mode);
    flags |= decimalMul(x, 2U, precision, mode);
    return flags;
}

ExceptionFlags decimalSinh(D)(ref D x, const int precision, const RoundingMode mode)
{
    if (x.isSignalNaN)
    {
        x = D.nan;
        return ExceptionFlags.invalidOperation;
    }

    if (x.isNaN)
        return ExceptionFlags.none;

    if (x.isInfinity)
    {
        x = D.infinity;
        return ExceptionFlags.none;
    }

    if (x.isZero)
        return ExceptionFlags.none;

    Unqual!D x1 = x;
    Unqual!D x2 = -x;

    auto flags = decimalExp(x1, 0, mode);
    flags |= decimalExp(x2, 0, mode);
    flags |= decimalSub(x1, x2, 0, mode);
    x = x1;
    flags |= decimalMul(x, 2U, precision, mode);
    return flags;
}

ExceptionFlags decimalCosh(D)(ref D x, const int precision, const RoundingMode mode)
{
    if (x.isSignalNaN)
    {
        x = D.nan;
        return ExceptionFlags.invalidOperation;
    }

    if (x.isNaN)
        return ExceptionFlags.none;

    if (x.isInfinity)
    {
        x = D.infinity;
        return ExceptionFlags.none;
    }

    if (x.isZero)
    {
        x = D.one;
        return ExceptionFlags.none;
    }

    Unqual!D x1 = x;
    Unqual!D x2 = -x;
    auto flags = decimalExp(x1, 0, mode);
    flags |= decimalExp(x2, 0, mode);
    flags |= decimalAdd(x1, x2, 0, mode);
    x = x1;
    flags |= decimalMul(x, D.half, precision, mode);
    return flags;
}

ExceptionFlags decimalTanh(D)(ref D x, const int precision, const RoundingMode mode)
{
    if (x.isSignalNaN)
    {
        x = D.nan;
        return ExceptionFlags.invalidOperation;
    }

    if (x.isNaN)
        return ExceptionFlags.none;

    if (x.isInfinity)
    {
        x = signbit(x) ? -D.one : D.one;
        return ExceptionFlags.none;
    }

    if (x.isZero)
        return ExceptionFlags.none;

    Unqual!D x1 = x;
    Unqual!D x2 = -x;
    auto flags = decimalSinh(x1, 0, mode);
    flags |= decimalCosh(x2, 0, mode);
    x = x1;
    flags |= decimalDiv(x, x2, precision, mode);
    return flags;
}

ExceptionFlags decimalAsinh(D)(ref D x, const int precision, const RoundingMode mode)
{
    if (x.isSignalNaN)
    {
        x = D.nan;
        return ExceptionFlags.invalidOperation;
    }

    if (x.isNaN || x.isZero || x.isInfinity)
        return ExceptionFlags.none;

    //+- ln(|x| + sqrt(x*x + 1))
    //+-[ln(2) + ln(|x|)] for very big x,

    //sqrt(D.max)/2
    static if (is(D: Decimal32))
    {
        enum asinhmax = Decimal32("1.581138e51");
    }
    else static if (is(D: Decimal64))
    {
        enum asinhmax = Decimal64("1.581138830084189e192");
    }
    else
    {
        enum asinhmax = Decimal128("1.581138830084189665999446772216359e3072");
    }

    bool sx = cast(bool)signbit(x);
    x = fabs(x);

    ExceptionFlags flags;
    if (isGreater(x, asinhmax))
    {
        flags = decimalLog(x, 0, mode) | ExceptionFlags.inexact;
        flags |= decimalAdd(x, D.LN2, 0, mode);
    }
    else
    {
        Unqual!D x1 = x;
        flags = decimalSqr(x1, 0, mode);
        flags |= decimalAdd(x1, 1U, 0, mode);
        flags |= decimalSqrt(x1, 0, mode);
        flags |= decimalAdd(x, x1, 0, mode);
        flags |= decimalLog(x, 0, mode);
    }

    if (sx)
        x = -x;
    flags |= decimalAdjust(x, precision, mode);
    return flags;
}

ExceptionFlags decimalAcosh(D)(ref D x, const int precision, const RoundingMode mode)
{
    if (x.isSignalNaN)
    {
        x = D.nan;
        return ExceptionFlags.invalidOperation;
    }

    if (x.isNaN)
        return ExceptionFlags.none;

    if (isLess(x, D.one))
    {
        x = D.nan;
        return ExceptionFlags.invalidOperation;
    }

    if (x == D.one)
    {
        x = D.zero;
        return ExceptionFlags.none;
    }

    if (x.isInfinity)
        return ExceptionFlags.none;

    /*
        ln(x+sqrt(x*x - 1))
        for very big x: (ln(x + x) = ln(2) + ln(x), otherwise will overflow
    */

    //sqrt(D.max)/2
    static if (is(D: Decimal32))
    {
        enum acoshmax = Decimal32("1.581138e51");
    }
    else static if (is(D: Decimal64))
    {
        enum acoshmax = Decimal64("1.581138830084189e192");
    }
    else
    {
        enum acoshmax = Decimal128("1.581138830084189665999446772216359e3072");
    }

    ExceptionFlags flags;
    if (isGreater(x, acoshmax))
    {
        flags = decimalLog(x, 0, mode) | ExceptionFlags.inexact;
        flags |= decimalAdd(x, D.LN2, precision, mode);
        return flags;
    }
    else
    {
        Unqual!D x1 = x;
        flags = decimalSqr(x1, 0, mode);
        flags |= decimalSub(x1, 1U, 0, mode);
        flags |= decimalSqrt(x1, 0, mode);
        flags |= decimalAdd(x, x1, 0, mode);
        flags |= decimalLog(x, precision, mode);
        return flags;
    }
}

ExceptionFlags decimalAtanh(D)(ref D x, const int precision, const RoundingMode mode)
{
    if (x.isSignalNaN)
    {
        x = D.nan;
        return ExceptionFlags.invalidOperation;
    }

    if (x.isNaN || x.isZero)
        return ExceptionFlags.none;

    alias T = DataType!D;
    T cx;
    int ex;
    bool sx = x.unpack(cx, ex);

    const cmp = coefficientCmp(cx, ex, false, T(1U), 0, false);

    if (cmp > 0)
    {
        x = signbit(x) ? -D.nan : D.nan;
        return ExceptionFlags.none;
    }

    if (cmp == 0)
    {
        x = signbit(x) ? -D.infinity : D.infinity;
        return ExceptionFlags.none;
    }

    const flags = coefficientAtanh(cx, ex, sx);
    return x.adjustedPack(cx, ex, sx, precision, mode, flags);
}

ExceptionFlags decimalSum(D)(const(D)[] x, out D result, const int precision, const RoundingMode mode)
if (isDecimal!D)
{
    alias T = MakeUnsigned!(D.sizeof * 16);

    DataType!D cx;
    T cxx, cr;
    int ex, er;
    bool sx, sr;
    ExceptionFlags flags;

    result = 0;
    bool hasPositiveInfinity, hasNegativeInfinity;
    size_t i = 0;
    while (i < x.length)
    {
        if (x[i].isSignalNaN)
        {
            result = D.nan;
            return ExceptionFlags.invalidOperation;
        }

        if (x[i].isNaN)
        {
            result = D.nan;
            return ExceptionFlags.none;
        }

        if (x[i].isInfinity)
        {
            if (signbit(x[i]))
                hasNegativeInfinity = true;
            else
                hasPositiveInfinity = true;
            ++i;
            break;
        }

        if (x[i].isZero)
        {
            ++i;
            continue;
        }

        sx = x.unpack(cx, ex);
        cxx = cx;
        flags |= coefficientAdd(cr, er, sr, cxx, ex, sx, mode);
        ++i;

        if (flags & ExceptionFlags.overflow)
            break;
    }

    while (i < x.length)
    {
        //infinity or overflow detected
        if (x[i].isSignalNaN)
        {
            result = D.nan;
            return ExceptionFlags.invalidOperation;
        }

        if (x[i].isNaN)
        {
            result = D.nan;
            return ExceptionFlags.none;
        }

        if (x[i].isInfinity)
        {
            if (signbit(x[i]))
                hasNegativeInfinity = true;
            else
                hasPositiveInfinity = true;
        }
        ++i;
    }

    if (hasPositiveInfinity)
    {
        if (hasNegativeInfinity)
        {
            result = D.nan;
            return ExceptionFlags.invalidOperation;
        }
        result = D.infinity;
        return ExceptionFlags.none;
    }

    if (hasNegativeInfinity)
    {
        result = -D.infinity;
        return ExceptionFlags.none;
    }

    flags |= coefficientAdjust(cr, er, cvt!T(DataType!D.max), sr, mode);
    return result.adjustedPack(cvt!(DataType!D)(cr), er, sr, precision, mode, flags);
}

ExceptionFlags decimalSumSquare(D)(const(D)[] x, out D result, const int precision, const RoundingMode mode)
if (isDecimal!D)
{
    alias T = MakeUnsigned!(D.sizeof * 16);
    DataType!D cx;
    T cxx, cr;
    ExceptionFlags flags;
    int ex, er;
    bool sr;
    result = 0;
    bool hasInfinity;
    size_t i = 0;
    while (i < x.length)
    {
        if (x[i].isSignalNaN)
        {
            result = D.nan;
            return ExceptionFlags.invalidOperation;
        }

        if (x[i].isNaN)
        {
            result = D.nan;
            return ExceptionFlags.none;
        }

        if (x[i].isInfinity)
        {
            hasInfinity = true;
            ++i;
            break;
        }

        if (x[i].isZero)
        {
            ++i;
            continue;
        }

        x.unpack(cx, ex);
        cxx = cx;
        flags |= coefficientSqr(cxx, ex);
        flags |= coefficientAdd(cr, er, sr, cxx, ex, false, mode);
        ++i;

        if (flags & ExceptionFlags.overflow)
            break;
    }

    while (i < x.length)
    {
        //infinity or overflow detected
        if (x[i].isSignalNaN)
        {
            result = D.nan;
            return ExceptionFlags.invalidOperation;
        }

        if (x[i].isNaN)
        {
            result = D.nan;
            return ExceptionFlags.none;
        }

        if (x[i].isInfinity)
            hasInfinity = true;
        ++i;
    }

    if (hasInfinity)
    {
        result = D.infinity;
        return ExceptionFlags.none;
    }

    flags |= coefficientAdjust(cr, er, cvt!T(DataType!D.max), sr, mode);
    return result.adjustedPack(cvt!(DataType!D)(cr), er, sr, precision, mode, flags);
}

ExceptionFlags decimalSumAbs(D)(const(D)[] x, out D result, const int precision, const RoundingMode mode)
if (isDecimal!D)
{
    alias T = MakeUnsigned!(D.sizeof * 16);
    DataType!D cx;
    T cxx, cr;
    ExceptionFlags flags;
    int ex, er;
    bool sr;

    result = 0;
    bool hasInfinity;
    size_t i = 0;
    while (i < x.length)
    {
        if (x[i].isSignalNaN)
        {
            result = D.nan;
            return ExceptionFlags.invalidOperation;
        }

        if (x[i].isNaN)
        {
            result = D.nan;
            return ExceptionFlags.none;
        }

        if (x[i].isInfinity)
        {
            hasInfinity = true;
            ++i;
            break;
        }

        if (x[i].isZero)
        {
            ++i;
            continue;
        }

        x.unpack(cx, ex);
        cxx = cx;
        flags |= coefficientAdd(cr, er, sr, cxx, ex, false, mode);
        ++i;

        if (flags & ExceptionFlags.overflow)
            break;
    }

    while (i < x.length)
    {
        //infinity or overflow detected
        if (x[i].isSignalNaN)
        {
            result = D.nan;
            return ExceptionFlags.invalidOperation;
        }

        if (x[i].isNaN)
        {
            result = D.nan;
            return ExceptionFlags.none;
        }

        if (x[i].isInfinity)
            hasInfinity = true;
        ++i;
    }

    if (hasInfinity)
    {
        result = D.infinity;
        return ExceptionFlags.none;
    }

    flags |= coefficientAdjust(cr, er, cvt!T(DataType!D.max), sr, mode);
    return result.adjustedPack(cvt!(DataType!D)(cr), er, sr, precision, mode, flags);
}

ExceptionFlags decimalDot(D)(const(D)[] x, const(D)[] y, out D result, const int precision, const RoundingMode mode)
if (isDecimal!D)
{
    const len = x.length > y.length ? y.length : x.length;

    bool hasPositiveInfinity, hasNegativeInfinity;

    alias T = MakeUnsigned!(D.sizeof * 16);
    DataType!D cx, cy;
    T cxx, cyy, cr;
    int ex, ey, er;
    bool sx, sy, sr;

    size_t i = 0;
    while (i < len)
    {
        if (x[i].isSignalNaN || y[i].isSignalNaN)
        {
            result = D.nan;
            return ExceptionFlags.invalidOperation;
        }

        if (x[i].isNaN || y[i].isNaN)
        {
            result = D.nan;
            return ExceptionFlags.none;
        }

        if (x[i].isInfinity)
        {
            if (y[i].isZero)
            {
                result = D.nan;
                return ExceptionFlags.invalidOperation;
            }

            if (y[i].isInfinity)
            {
                if (signbit(x[i]) ^ signbit(y[i]))
                    hasNegativeInfinity = true;
                else
                    hasPositiveInfinity = true;

            }
            else
            {
                if (signbit(x[i]))
                    hasNegativeInfinity = true;
                else
                    hasPositiveInfinity = true;
            }
            ++i;
            break;
        }

        if (y[i].isInfinity)
        {
            if (x[i].isZero)
            {
                result = D.nan;
                return ExceptionFlags.invalidOperation;
            }

            if (signbit(y[i]))
                hasNegativeInfinity = true;
            else
                hasPositiveInfinity = true;

            ++i;
            break;
        }

        if (x[i].isZero || y[i].isZero)
        {
            ++i;
            continue;
        }

        sx = x[i].unpack(cx, ex);
        sy = y[i].unpack(cy, ey);
        cxx = cx; cyy = cy;
        flags |= coefficientMul(cx, ex, sx, cy, ey, sy, mode);
        flags |= coefficientAdd(cr, er, sr, cx, ex, sx, mode);
        ++i;
        if (flags & ExceptionFlags.overflow)
            break;
    }

    while (i < len)
    {
        if (x[i].isSignalNaN || y[i].isSignalNaN)
        {
            result = D.nan;
            return ExceptionFlags.invalidOperation;
        }

        if (x[i].isNaN || y[i].isNaN)
        {
            result = D.nan;
            return ExceptionFlags.none;
        }

        if (x[i].isInfinity)
        {
            if (y[i].isZero)
            {
                result = D.nan;
                return ExceptionFlags.invalidOperation;
            }

            if (y[i].isInfinity)
            {
                if (signbit(x[i]) ^ signbit(y[i]))
                    hasNegativeInfinity = true;
                else
                    hasPositiveInfinity = true;
            }
            else
            {
                if (signbit(x[i]))
                    hasNegativeInfinity = true;
                else
                    hasPositiveInfinity = true;
            }
        }

        if (y[i].isInfinity)
        {
            if (x[i].isZero)
            {
                result = D.nan;
                return ExceptionFlags.invalidOperation;
            }

            if (signbit(y[i]))
                hasNegativeInfinity = true;
            else
                hasPositiveInfinity = true;
        }

        ++i;
    }

    if (hasPositiveInfinity)
    {
        if (hasNegativeInfinity)
        {
            result = D.nan;
            return ExceptionFlags.invalidOperation;
        }
        result = D.infinity;
        return ExceptionFlags.none;
    }

    if (hasNegativeInfinity)
    {
        result = -D.infinity;
        return ExceptionFlags.none;
    }

    flags |= coefficientAdjust(cr, er, cvt!T(DataType!D.max), sr, mode);
    return result.adjustedPack(cvt!(DataType!D)(cr), er, sr, precision, mode, flags);
}

ExceptionFlags decimalProd(D)(const(D)[] x, out D result, out int scale, const int precision, const RoundingMode mode)
if (isDecimal!D)
{
    alias T = MakeUnsigned!(D.sizeof * 16);
    DataType!D cx;
    T cxx, cr;
    ExceptionFlags flags;
    int ex, er;
    bool sx, sr;

    result = 0;
    scale = 0;
    bool hasInfinity;
    bool hasZero;
    bool infinitySign;
    bool zeroSign;
    size_t i = 0;
    while (i < x.length)
    {
        if (x[i].isSignalNaN)
        {
            result = D.nan;
            return ExceptionFlags.invalidOperation;
        }

        if (x[i].isNaN)
        {
            result = D.nan;
            return ExceptionFlags.none;
        }

        if (x[i].isInfinity)
        {
            hasInfinity = true;
            infinitySign = cast(bool)(signbit(x[i]));
            ++i;
            break;
        }

        if (x[i].isZero)
        {
            hasZero = true;
            zeroSign = cast(bool)(signbit(x[i]));
            ++i;
            break;
        }

        sx = x.unpack(cx, ex);
        cxx = cx;
        flags |= coefficientMul(cr, er, sr, cxx, ex, sx, mode);
        er -= cappedAdd(scale, er);
        ++i;

        if (flags & ExceptionFlags.overflow)
            break;
    }

    while (i < x.length)
    {
        //infinity or overflow detected
        if (x[i].isSignalNaN)
        {
            result = D.nan;
            return ExceptionFlags.invalidOperation;
        }

        if (x[i].isNaN)
        {
            result = D.nan;
            return ExceptionFlags.none;
        }

        if (x[i].isInfinity)
        {
            hasInfinity = true;
            infinitySign ^= cast(bool)(signbit(x[i]));
        }
        else if (x[i].isZero)
        {
            hasZero = true;
            zeroSign ^= cast(bool)(signbit(x[i]));
        }
        else
        {
            zeroSign ^= cast(bool)(signbit(x[i]));
        }

        ++i;
    }

    if (hasInfinity & hasZero)
    {
        result = D.nan;
        return ExceptionFlags.invalidOperation;
    }

    if (hasInfinity)
    {
        result = infinitySign ? -D.infinity : D.infinity;
        return ExceptionFlags.none;
    }

    if (hasZero)
    {
        result = zeroSign ? -D.zero : D.zero;
        return ExceptionFlags.none;
    }

    flags |= coefficientAdjust(cr, er, cvt!T(DataType!D.max), sr, mode);
    return result.adjustedPack(cvt!(DataType!D)(cr), er, sr, precision, mode, flags);
}

ExceptionFlags decimalProdSum(D)(const(D)[] x, const(D)[] y, out D result, out int scale, const int precision, const RoundingMode mode)
if (isDecimal!D)
{
    const len = x.length > y.length ? y.length : x.length;

    bool hasInfinity;
    bool hasZero;
    bool infinitySign;
    bool invalidSum;

    alias T = MakeUnsigned!(D.sizeof * 16);
    DataType!D cx, cy;
    T cxx, cyy, cr;
    int ex, ey, er;
    bool sx, sy, sr;

    size_t i = 0;
    while (i < len)
    {
        if (x[i].isSignalNaN || y[i].isSignalNaN)
        {
            result = D.nan;
            return ExceptionFlags.invalidOperation;
        }

        if (x[i].isNaN || y[i].isNaN)
        {
            result = D.nan;
            return ExceptionFlags.none;
        }

        if (x[i].isInfinity)
        {
            if (y[i].isInfinity && signbit(x) != signbit(y))
            {
                invalidSum = true;
                ++i;
                break;
            }

            hasInfinity = true;
            infinitySign = cast(bool)signbit(x[i]);
            ++i;
            break;
        }

        if (y[i].isInfinity)
        {
            hasInfinity = true;
            infinitySign = cast(bool)signbit(x[i]);
            ++i;
            break;
        }

        if (x[i] == -y[i])
        {
            hasZero = true;
            ++i;
            break;
        }
        sx = x[i].unpack(cx, ex);
        sy = y[i].unpack(cy, ey);
        cxx = cx; cyy = cy;
        flags |= coefficientAdd(cx, ex, sx, cy, ey, sy, mode);
        flags |= coefficientMul(cr, er, sr, cx, ex, sx, mode);
        er -= cappedAdd(scale, er);
        ++i;
        if (flags & (ExceptionFlags.overflow | ExceptionFlags.underflow))
            break;
    }

    while (i < len)
    {
        //inf, zero or overflow, underflow, invalidSum;
        if (x[i].isSignalNaN || y[i].isSignalNaN)
        {
            result = D.nan;
            return ExceptionFlags.invalidOperation;
        }

        if (x[i].isNaN || y[i].isNaN)
        {
            result = D.nan;
            return ExceptionFlags.none;
        }

        if (x[i].isInfinity)
        {
            if (y[i].isInfinity && signbit(x) != signbit(y))
                invalidSum = true;
            else
            {
                hasInfinity = true;
                infinitySign ^= cast(bool)signbit(x[i]);
            }
        }
        else if (y[i].isInfinity)
        {
            hasInfinity = true;
            infinitySign ^= cast(bool)signbit(y[i]);
        }
        else if (x[i] == -y[i])
            hasZero = true;
        ++i;
    }

    if (invalidSum)
    {
        result = D.nan;
        return ExceptionFlags.invalidOperation;
    }

    if (hasInfinity & hasZero)
    {
        result = D.nan;
        return ExceptionFlags.invalidOperation;
    }

    if (hasInfinity)
    {
        result = infinitySign ? -D.infinity : D.infinity;
        return ExceptionFlags.none;
    }

    if (hasZero)
    {
        result = D.zero;
        return ExceptionFlags.none;
    }

    flags |= coefficientAdjust(cr, er, cvt!T(DataType!D.max), sr, mode);
    return result.adjustedPack(cvt!(DataType!D)(cr), er, sr, precision, mode, flags);
}

ExceptionFlags decimalProdDiff(D)(const(D)[] x, const(D)[] y, out D result, out int scale, const int precision, const RoundingMode mode)
if (isDecimal!D)
{
    const len = x.length > y.length ? y.length : x.length;

    bool hasInfinity;
    bool hasZero;
    bool infinitySign;
    bool invalidSum;

    alias T = MakeUnsigned!(D.sizeof * 16);
    DataType!D cx, cy;
    T cxx, cyy, cr;
    int ex, ey, er;
    bool sx, sy, sr;

    size_t i = 0;
    while (i < len)
    {
        if (x[i].isSignalNaN || y[i].isSignalNaN)
        {
            result = D.nan;
            return ExceptionFlags.invalidOperation;
        }

        if (x[i].isNaN || y[i].isNaN)
        {
            result = D.nan;
            return ExceptionFlags.none;
        }

        if (x[i].isInfinity)
        {
            if (y[i].isInfinity && signbit(x) != signbit(y))
            {
                invalidSum = true;
                ++i;
                break;
            }

            hasInfinity = true;
            infinitySign = cast(bool)signbit(x[i]);
            ++i;
            break;
        }

        if (y[i].isInfinity)
        {
            hasInfinity = true;
            infinitySign = cast(bool)signbit(x[i]);
            ++i;
            break;
        }

        if (x[i] == y[i])
        {
            hasZero = true;
            ++i;
            break;
        }
        sx = x[i].unpack(cx, ex);
        sy = y[i].unpack(cy, ey);
        cxx = cx; cyy = cy;
        flags |= coefficientSub(cx, ex, sx, cy, ey, sy, mode);
        flags |= coefficientMul(cr, er, sr, cx, ex, sx, mode);
        er -= cappedAdd(scale, er);
        ++i;
        if (flags & (ExceptionFlags.overflow | ExceptionFlags.underflow))
            break;
    }

    while (i < len)
    {
        //inf, zero or overflow, underflow, invalidSum;
        if (x[i].isSignalNaN || y[i].isSignalNaN)
        {
            result = D.nan;
            return ExceptionFlags.invalidOperation;
        }

        if (x[i].isNaN || y[i].isNaN)
        {
            result = D.nan;
            return ExceptionFlags.none;
        }

        if (x[i].isInfinity)
        {
            if (y[i].isInfinity && signbit(x) != signbit(y))
                invalidSum = true;
            else
            {
                hasInfinity = true;
                infinitySign ^= cast(bool)signbit(x[i]);
            }
        }
        else if (y[i].isInfinity)
        {
            hasInfinity = true;
            infinitySign ^= cast(bool)signbit(y[i]);
        }
        else if (x[i] == y[i])
            hasZero = true;
        ++i;
    }

    if (invalidSum)
    {
        result = D.nan;
        return ExceptionFlags.invalidOperation;
    }

    if (hasInfinity & hasZero)
    {
        result = D.nan;
        return ExceptionFlags.invalidOperation;
    }

    if (hasInfinity)
    {
        result = infinitySign ? -D.infinity : D.infinity;
        return ExceptionFlags.none;
    }

    if (hasZero)
    {
        result = D.zero;
        return ExceptionFlags.none;
    }

    flags |= coefficientAdjust(cr, er, cvt!T(DataType!D.max), sr, mode);
    return result.adjustedPack(cvt!(DataType!D)(cr), er, sr, precision, mode, flags);
}

ExceptionFlags decimalPoly(D1, D2, D)(auto const ref D1 x, const(D2)[] a, out D result)
if (isDecimal!(D1, D2) && is(D: CommonDecimal!(D1, D2)))
{
    if (!a.length)
    {
        result = 0;
        return ExceptionFlags.none;
    }
    ptrdiff_t i = a.length - 1;
    D result = a[i];
    ExceptionFlags flags;
    while (--i >= 0)
    {
        flags |= decimalMul(result, x);
        flags |= decimalAdd(result, a[i]);
    }
    return flags;
}

/* ****************************************************************************************************************** */
/* COEFFICIENT ARITHMETIC                                                                                            */
/* ****************************************************************************************************************** */
//divPow10          - inexact
//mulPow10          - overflow
//coefficientAdjust - inexact, overflow, underflow
//coefficientExpand - none
//coefficientShrink - inexact
//coefficientAdd    - inexact, overflow
//coefficientMul    - inexact, overflow, underflow
//coefficientDiv    - inexact, overflow, underflow, div0
//coefficientMod    - inexact, overflow, underflow, invalid
//coefficientFMA    - inexact, overflow, underflow
//coefficientCmp    - none
//coefficientEqu    - none
//coefficientSqr    - inexact, overflow, underflow

ExceptionFlags exp2to10(RoundingMode mode = RoundingMode.implicit, U)(ref U coefficient, ref int exponent, const bool isNegative)
{
    enum maxMultiplicable = U.max / 5U;
    enum hibit = U(1U) << (U.sizeof * 8 - 1);
    ExceptionFlags flags;
    auto e5 = -exponent;

    if (e5 > 0)
    {
        const tz = ctz(coefficient);
        if (tz)
        {
            const shift = e5 > tz ? tz : e5;
            e5 -= shift;
            exponent += shift;
            coefficient >>= shift;
        }

        while (e5 > 0)
        {
            --e5;
            if (coefficient < maxMultiplicable)
                coefficient *= 5U;
            else
            {
                ++exponent;
                bool mustRound = cast(bool)(coefficient & 1U);
                coefficient >>= 1;
                if (mustRound)
                {
                    flags = ExceptionFlags.inexact;
                    static if (mode == RoundingMode.tiesToAway)
                    {
                        ++coefficient;
                    }
                    else static if (mode == RoundingMode.tiesToEven)
                    {
                        if ((coefficient & 1U))
                            ++coefficient;
                    }
                    else static if (mode == RoundingMode.towardNegative)
                    {
                        if (isNegative)
                            ++coefficient;
                    }
                    else static if (mode == RoundingMode.towardPositive)
                    {
                        if (!isNegative)
                            ++coefficient;
                    }
                }
            }
        }
    }

    if (e5 < 0)
    {
        const lz = clz(coefficient);
        if (lz)
        {
            const shift = -e5 > lz ? lz : -e5;
            exponent -= shift;
            e5 += shift;
            coefficient <<= shift;
        }

        while (e5 < 0)
        {
            ++e5;
            if (coefficient & hibit)
            {
                auto r = divrem(coefficient, 5U);
                if (r)
                {
                    flags = ExceptionFlags.inexact;
                    static if (mode == RoundingMode.towardNegative)
                    {
                        if (isNegative)
                            ++coefficient;
                    }
                    else static if (mode == RoundingMode.towardPositive)
                    {
                        if (!isNegative)
                            ++coefficient;
                    }
                    else static if (mode == RoundingMode.tiesToAway || mode == RoundingMode.tiesToEven)
                    {
                        if (r >= 3U)
                            ++coefficient;
                    }
                }
            }
            else
            {
                coefficient <<= 1;
                --exponent;
            }
        }
    }

    return flags;
}

ExceptionFlags exp10to2(RoundingMode mode = RoundingMode.implicit, U)(ref U coefficient, ref int exponent, const bool isNegative)
{
    enum maxMultiplicable = U.max / 5U;
    enum hibit = U(1U) << (U.sizeof * 8 - 1);
    ExceptionFlags flags;
    auto e5 = exponent;

    if (e5 > 0)
    {
        while (e5 > 0)
        {
            if (coefficient < maxMultiplicable)
            {
                --e5;
                coefficient *= 5U;
            }
            else
            {
                ++exponent;
                const bool mustRound = cast(bool)(coefficient & 1U);
                coefficient >>= 1;
                if (mustRound)
                {
                    flags = ExceptionFlags.inexact;
                    static if (mode == RoundingMode.tiesToAway)
                    {
                        ++coefficient;
                    }
                    else static if (mode == RoundingMode.tiesToEven)
                    {
                        if ((coefficient & 1U))
                            ++coefficient;
                    }
                    else static if (mode == RoundingMode.towardNegative)
                    {
                        if (isNegative)
                            ++coefficient;
                    }
                    else static if (mode == RoundingMode.towardPositive)
                    {
                        if (!isNegative)
                            ++coefficient;
                    }
                }
            }
        }
    }

    if (e5 < 0)
    {
        while (e5 < 0)
        {
            if (coefficient & hibit)
            {
                ++e5;
                auto r = divrem(coefficient, 5U);
                if (r)
                {
                    flags = ExceptionFlags.inexact;
                    static if (mode == RoundingMode.towardNegative)
                    {
                        if (isNegative)
                            ++coefficient;
                    }
                    else static if (mode == RoundingMode.towardPositive)
                    {
                        if (!isNegative)
                            ++coefficient;
                    }
                    else static if (mode == RoundingMode.tiesToAway || mode == RoundingMode.tiesToEven)
                    {
                        if (r >= 3U)
                            ++coefficient;
                    }
                }
            }
            else
            {
                coefficient <<= 1;
                --exponent;
            }
        }
    }

    return flags;
}

unittest
{
    uint cx = 3402823;
    int ex = 32;

    exp10to2!(RoundingMode.towardZero)(cx, ex, false);
}

//divides coefficient by 10^power
//inexact
@safe pure nothrow @nogc
ExceptionFlags divpow10(T)(ref T coefficient, const int power, const bool isNegative, const RoundingMode mode)
if (isAnyUnsigned!T)
in
{
    assert (power >= 0);
}
do
{
    if (coefficient == 0U)
        return ExceptionFlags.none;

    if (power == 0)
        return ExceptionFlags.none;

    Unqual!T remainder;

    if (power >= pow10!T.length)
    {
        remainder = coefficient;
        coefficient = 0U;
    }
    else
        remainder = divrem(coefficient, pow10!T[power]);

    if (remainder == 0U)
        return ExceptionFlags.none;

    const half = power >= pow10!T.length ? T.max : pow10!T[power] >>> 1;
    final switch (mode)
    {
        case RoundingMode.tiesToEven:
            if (remainder > half)
                ++coefficient;
            else if ((remainder == half) && ((coefficient & 1U) != 0U))
                ++coefficient;
            break;
        case RoundingMode.tiesToAway:
            if (remainder >= half)
                ++coefficient;
            break;
        case RoundingMode.towardNegative:
            if (isNegative)
                ++coefficient;
            break;
        case RoundingMode.towardPositive:
            if (!isNegative)
                ++coefficient;
            break;
        case RoundingMode.towardZero:
            break;
    }

    return ExceptionFlags.inexact;
}

unittest
{
    struct S {uint c; int p; bool n; RoundingMode r; uint outc; bool inexact; }

    S[] test =
    [
        S (0, 0, false, RoundingMode.tiesToAway, 0, false),
        S (0, 0, false, RoundingMode.tiesToEven, 0, false),
        S (0, 0, false, RoundingMode.towardNegative, 0, false),
        S (0, 0, false, RoundingMode.towardPositive, 0, false),
        S (0, 0, false, RoundingMode.towardZero, 0, false),

        S (10, 1, false, RoundingMode.tiesToAway, 1, false),
        S (10, 1, false, RoundingMode.tiesToEven, 1, false),
        S (10, 1, false, RoundingMode.towardNegative, 1, false),
        S (10, 1, false, RoundingMode.towardPositive, 1, false),
        S (10, 1, false, RoundingMode.towardZero, 1, false),

        S (13, 1, false, RoundingMode.tiesToAway, 1, true),
        S (13, 1, false, RoundingMode.tiesToEven, 1, true),
        S (13, 1, false, RoundingMode.towardNegative, 1, true),
        S (13, 1, false, RoundingMode.towardPositive, 2, true),
        S (13, 1, false, RoundingMode.towardZero, 1, true),

        S (13, 1, true, RoundingMode.tiesToAway, 1, true),
        S (13, 1, true, RoundingMode.tiesToEven, 1, true),
        S (13, 1, true, RoundingMode.towardNegative, 2, true),
        S (13, 1, true, RoundingMode.towardPositive, 1, true),
        S (13, 1, true, RoundingMode.towardZero, 1, true),

        S (15, 1, false, RoundingMode.tiesToAway, 2, true),
        S (15, 1, false, RoundingMode.tiesToEven, 2, true),
        S (15, 1, false, RoundingMode.towardNegative, 1, true),
        S (15, 1, false, RoundingMode.towardPositive, 2, true),
        S (15, 1, false, RoundingMode.towardZero, 1, true),

        S (15, 1, true, RoundingMode.tiesToAway, 2, true),
        S (15, 1, true, RoundingMode.tiesToEven, 2, true),
        S (15, 1, true, RoundingMode.towardNegative, 2, true),
        S (15, 1, true, RoundingMode.towardPositive, 1, true),
        S (15, 1, true, RoundingMode.towardZero, 1, true),

        S (18, 1, false, RoundingMode.tiesToAway, 2, true),
        S (18, 1, false, RoundingMode.tiesToEven, 2, true),
        S (18, 1, false, RoundingMode.towardNegative, 1, true),
        S (18, 1, false, RoundingMode.towardPositive, 2, true),
        S (18, 1, false, RoundingMode.towardZero, 1, true),

        S (18, 1, true, RoundingMode.tiesToAway, 2, true),
        S (18, 1, true, RoundingMode.tiesToEven, 2, true),
        S (18, 1, true, RoundingMode.towardNegative, 2, true),
        S (18, 1, true, RoundingMode.towardPositive, 1, true),
        S (18, 1, true, RoundingMode.towardZero, 1, true),

        S (25, 1, false, RoundingMode.tiesToAway, 3, true),
        S (25, 1, false, RoundingMode.tiesToEven, 2, true),
        S (25, 1, false, RoundingMode.towardNegative, 2, true),
        S (25, 1, false, RoundingMode.towardPositive, 3, true),
        S (25, 1, false, RoundingMode.towardZero, 2, true),

        S (25, 1, true, RoundingMode.tiesToAway, 3, true),
        S (25, 1, true, RoundingMode.tiesToEven, 2, true),
        S (25, 1, true, RoundingMode.towardNegative, 3, true),
        S (25, 1, true, RoundingMode.towardPositive, 2, true),
        S (25, 1, true, RoundingMode.towardZero, 2, true),
    ];

    foreach (ref s; test)
    {
        auto flags = divpow10(s.c, s.p, s.n, s.r);
        assert (s.c == s.outc);
        assert (flags == ExceptionFlags.inexact ? s.inexact : !s.inexact);
    }
}

//multiplies coefficient by 10^^power, returns possible overflow
//overflow
@safe pure nothrow @nogc
ExceptionFlags mulpow10(T)(ref T coefficient, const int power)
if (isAnyUnsigned!T)
in
{
    assert (power >= 0);
}
do
{
    if (coefficient == 0U || power == 0)
        return ExceptionFlags.none;
    if (power >= pow10!T.length || coefficient > maxmul10!T[power])
        return ExceptionFlags.overflow;
    coefficient *= pow10!T[power];
    return ExceptionFlags.none;
}

//adjusts coefficient to fit minExponent <= exponent <= maxExponent and coefficient <= maxCoefficient
//inexact, overflow, underflow
@safe pure nothrow @nogc
ExceptionFlags coefficientAdjust(T)(ref T coefficient, ref int exponent, const int minExponent, const int maxExponent,
    const T maxCoefficient, const bool isNegative, const RoundingMode mode)
if (isAnyUnsigned!T)
in
{
    assert (minExponent <= maxExponent);
    assert (maxCoefficient >= 1U);
}
do
{
    if (coefficient == 0U)
    {
        if (exponent < minExponent)
            exponent = minExponent;
        if (exponent > maxExponent)
            exponent = maxExponent;
        return ExceptionFlags.none;
    }

    bool overflow;
    ExceptionFlags flags;

    if (exponent < minExponent)
    {
        //increase exponent, divide coefficient
        const dif = minExponent - exponent;
        flags = divpow10(coefficient, dif, isNegative, mode);
        if (coefficient == 0U)
            flags |= ExceptionFlags.underflow | ExceptionFlags.inexact;
        exponent += dif;
    }
    else if (exponent > maxExponent)
    {
        //decrease exponent, multiply coefficient
        const dif = exponent - maxExponent;
        flags = mulpow10(coefficient, dif);
        if (flags & ExceptionFlags.overflow)
            return flags | ExceptionFlags.inexact;
        else
            exponent -= dif;
    }

    if (coefficient > maxCoefficient)
    {
        //increase exponent, divide coefficient
        auto dif = prec(coefficient) - prec(maxCoefficient);
        if (!dif)
            dif = 1;
        flags |= divpow10(coefficient, dif, isNegative, mode);
        if (coefficient > maxCoefficient)
        {
            //same precision but greater
            flags |= divpow10(coefficient, 1, isNegative, mode);
            ++dif;
        }
        if (cappedAdd(exponent, dif) != dif)
        {
            if (coefficient != 0U)
                return flags | ExceptionFlags.overflow | ExceptionFlags.inexact;
        }
    }

    //coefficient became 0, dont' bother with exponents;
    if (coefficient == 0U)
    {
        exponent = 0;
        if (exponent < minExponent)
            exponent = minExponent;
        if (exponent > maxExponent)
            exponent = maxExponent;
        return flags;
    }

    if (exponent < minExponent)
        return flags | ExceptionFlags.underflow | ExceptionFlags.inexact;

    if (exponent > maxExponent)
        return flags | ExceptionFlags.overflow | ExceptionFlags.inexact;

    return flags;
}

//adjusts coefficient to fit minExponent <= exponent <= maxExponent
//inexact, overflow, underflow
@safe pure nothrow @nogc
ExceptionFlags coefficientAdjust(T)(ref T coefficient, ref int exponent, const int minExponent, const int maxExponent,
    const bool isNegative, const RoundingMode mode)
if (isAnyUnsigned!T)
in
{
    assert (minExponent <= maxExponent);
}
do
{
    return coefficientAdjust(coefficient, exponent, minExponent, maxExponent, T.max, isNegative, mode);
}

//adjusts coefficient to fit coefficient in maxCoefficient
//inexact, overflow, underflow
@safe pure nothrow @nogc
ExceptionFlags coefficientAdjust(T)(ref T coefficient, ref int exponent, const T maxCoefficient, const bool isNegative, const RoundingMode mode)
if (isAnyUnsigned!T)
in
{
    assert (maxCoefficient >= 1U);
}
do
{
    return coefficientAdjust(coefficient, exponent, int.min, int.max, maxCoefficient, isNegative, mode);
}

//adjusts coefficient to fit minExponent <= exponent <= maxExponent and to fit precision
//inexact, overflow, underflow
@safe pure nothrow @nogc
ExceptionFlags coefficientAdjust(T)(ref T coefficient, ref int exponent, const int minExponent, const int maxExponent,
    const int precision, const bool isNegative, const RoundingMode mode)
if (isAnyUnsigned!T)
in
{
    assert (precision >= 1);
    assert (minExponent <= maxExponent);
}
do
{
    const maxCoefficient = precision >= pow10!T.length ? T.max : pow10!T[precision] - 1U;
    auto flags = coefficientAdjust(coefficient, exponent, minExponent, maxExponent, maxCoefficient, isNegative, mode);
    if (flags & (ExceptionFlags.overflow | ExceptionFlags.underflow))
        return flags;

    const p = prec(coefficient);
    if (p > precision)
    {
        flags |= divpow10(coefficient, 1, isNegative, mode);
        if (coefficient == 0U)
        {
            exponent = 0;
            if (exponent < minExponent)
                exponent = minExponent;
            if (exponent > maxExponent)
                exponent = maxExponent;
            return flags;
        }
        else
        {
            if (cappedAdd(exponent, 1) != 1)
                return flags | ExceptionFlags.overflow;
            if (exponent > maxExponent)
                return flags | ExceptionFlags.overflow;
        }
    }
    return flags;
}

//adjusts coefficient to fit precision
//inexact, overflow, underflow
@safe pure nothrow @nogc
ExceptionFlags coefficientAdjust(T)(ref T coefficient, ref int exponent,
    const int precision, const bool isNegative, const RoundingMode mode)
if (isAnyUnsigned!T)
in
{
    assert (precision >= 1);
}
do
{
    return coefficientAdjust(coefficient, exponent, int.min, int.max, precision, isNegative, mode);
}

//shrinks coefficient by cutting out terminating zeros and increasing exponent
@safe pure nothrow @nogc
void coefficientShrink(T)(ref T coefficient, ref int exponent)
{
    if (coefficient > 9U && (coefficient & 1U) == 0U && exponent < int.max)
    {
        Unqual!T c = coefficient;
        Unqual!T r = divrem(c, 10U);
        int e = exponent + 1;
        while (r == 0U)
        {
            coefficient = c;
            exponent = e;
            if ((c & 1U) || e == int.max)
                break;
            r = divrem(c, 10U);
            ++e;
        }
    }
}

//expands cx with 10^^target if possible
@safe pure nothrow @nogc
void coefficientExpand(T)(ref T cx, ref int ex, ref int target)
in
{
    assert (cx);
    assert (target > 0);
}
do
{
    const int px = prec(cx);
    int maxPow10 = cast(int)pow10!T.length - px;
    const maxCoefficient = maxmul10!T[$ - px];
    if (cx > maxCoefficient)
        --maxPow10;
    auto pow = target > maxPow10 ? maxPow10 : target;
    pow = cappedSub(ex, pow);
    if (pow)
    {
        cx *= pow10!T[pow];
        target -= pow;
    }
}

//expands cx to maximum available digits
@safe pure nothrow @nogc
void coefficientExpand(T)(ref T cx, ref int ex)
{
    if (cx)
    {
        const int px = prec(cx);
        int pow = cast(int)pow10!T.length - px;
        const maxCoefficient = maxmul10!T[$ - px];
        if (cx > maxCoefficient)
            --pow;
        pow = cappedSub(ex, pow);
        if (pow)
        {
            cx *= pow10!T[pow];
        }
    }
}

unittest
{
    struct S {uint x1; int ex1; int target1; uint x2; int ex2; int target2; }
    S[] tests =
    [
        S(1, 0, 4, 10000, -4, 0),
        S(429496729, 0, 1, 4294967290, -1, 0),
        S(429496739, 0, 1, 429496739, 0, 1),
        S(429496729, 0, 2, 4294967290, -1, 1),
        S(42949672, 0, 1, 429496720, -1, 0),
        S(42949672, 0, 2, 4294967200, -2, 0),
        S(42949672, 0, 3, 4294967200, -2, 1),
    ];

    foreach( s; tests)
    {
        coefficientExpand(s.x1, s.ex1, s.target1);
        assert (s.x1 == s.x2);
        assert (s.ex1 == s.ex2);
        assert (s.target1 == s.target2);
    }
}

//shrinks cx with 10^^target
//inexact
@safe pure nothrow @nogc
ExceptionFlags coefficientShrink(T)(ref T cx, ref int ex, const bool sx, ref int target, const RoundingMode mode)
in
{
    assert (cx);
    assert (target > 0);
}
do
{
    const pow = cappedAdd(ex, target);
    if (pow)
    {
        const flags = divpow10(cx, pow, sx, mode);
        target -= pow;
        return flags;
    }
    else
        return ExceptionFlags.none;
}

//inexact
@safe pure nothrow @nogc
ExceptionFlags exponentAlign(T)(ref T cx, ref int ex, const bool sx, ref T cy, ref int ey, const bool sy, const RoundingMode mode)
out
{
    assert (ex == ey);
}
do
{
    if (ex == ey)
        return ExceptionFlags.none;

    if (!cx)
    {
        ex = ey;
        return ExceptionFlags.none;
    }

    if (!cy)
    {
        ey = ex;
        return ExceptionFlags.none;
    }

    ExceptionFlags flags;
    int dif = ex - ey;
    if (dif > 0) //ex > ey
    {
        coefficientExpand(cx, ex, dif);
        if (dif)
            flags = coefficientShrink(cy, ey, sy, dif, mode);
        assert(!dif);
    }
    else //ex < ey
    {
        dif = -dif;
        coefficientExpand(cy, ey, dif);
        if (dif)
            flags = coefficientShrink(cx, ex, sx, dif, mode);
        assert(!dif);
    }
    return flags;
}

//inexact, overflow, underflow
@safe pure nothrow @nogc
ExceptionFlags coefficientAdd(T)(ref T cx, ref int ex, ref bool sx, const T cy, const int ey, const bool sy, const RoundingMode mode)
{
    if (!cy)
        return ExceptionFlags.none;

    if (!cx)
    {
        cx = cy;
        ex = ey;
        sx = sy;
        return ExceptionFlags.none;
    }

    Unqual!T cyy = cy;
    int eyy = ey;

    //if cx or cy underflowed, don't propagate
    auto flags = exponentAlign(cx, ex, sx, cyy, eyy, sy, mode) & ~ExceptionFlags.underflow;

    if (!cyy)
    {
        //cx is very big
        switch (mode)
        {
            case RoundingMode.towardPositive:
                if (!sx && !sy)
                    ++cx;
                else if (sx && !sy)
                    --cx;
                break;
            case RoundingMode.towardNegative:
                if (sx && sy)
                    ++cx;
                else if (!sx && sy)
                    --cx;
                break;
            case RoundingMode.towardZero:
                if (sx != sy)
                    --cx;
                break;
            default:
                break;
        }

        //if (sx == sy)
        //{
        //    //cx + 0.0.....001 => cx0000.0....001
        //    if (sx && mode == RoundingMode.towardNegative)
        //        ++cx;
        //    else if (!sx && mode == RoundingMode.towardPositive)
        //        ++cx;
        //}
        //else
        //{
        //    //cx - 0.0.....001 => (cx-1)9999.9...999
        //    if (sx && mode == RoundingMode.towardZero)
        //        --cx;
        //    else if (!sx && mode == RoundingMode.towardNegative)
        //        --cx;
        //}
    }

    if (!cx)
    {
        //cy is very big, cx is tiny
        switch (mode)
        {
            case RoundingMode.towardPositive:
                if (!sx && !sy)
                    ++cyy;
                else if (!sx && sy)
                    --cyy;
                break;
            case RoundingMode.towardNegative:
                if (sx && sy)
                    ++cyy;
                else if (sx && !sy)
                    --cyy;
                break;
            case RoundingMode.towardZero:
                if (sx != sy)
                    --cyy;
                break;
            default:
                break;
        }

        //if (sx == sy)
        //{
        //    //0.0.....001 + cyy => cyy0000.0....001
        //    if (sy && mode == RoundingMode.towardNegative)
        //        ++cyy;
        //    else if (!sy && mode == RoundingMode.towardPositive)
        //        ++cyy;
        //}
        //else
        //{
        //    //0.0.....001 - cyy => -(cyy + 0.0.....001)
        //    if (sy && mode == RoundingMode.towardZero)
        //        --cyy;
        //    else if (!sy && mode == RoundingMode.towardNegative)
        //        --cyy;
        //}
    }

    if (sx == sy)
    {
        Unqual!T savecx = cx;
        const carry = xadd(cx, cyy);
        if (carry)
        {
            if (!cappedAdd(ex, 1))
                return flags | ExceptionFlags.overflow;
            flags |= divpow10(savecx, 1, sx, mode);
            flags |= divpow10(cyy, 1, sy, mode);
            cx = savecx + cyy;
        }
        return flags;
    }
    else
    {
        if (cx == cyy)
        {
            cx = T(0U);
            ex = 0;
            sx = false;
            return flags;
        }

        if (cx > cyy)
            cx -= cyy;
        else
        {
            cx = cyy - cx;
            sx = sy;
        }
        return flags;
    }
}

unittest
{
    int x = 0;
}

//inexact, overflow, underflow
@safe pure nothrow @nogc
ExceptionFlags coefficientMul(T)(ref T cx, ref int ex, ref bool sx, const T cy, const int ey, const bool sy, const RoundingMode mode)
{
    if (!cy || !cy)
    {
        cx = T(0U);
        sx ^= sy;
        return ExceptionFlags.none;
    }

    auto r = xmul(cx, cy);

    if (cappedAdd(ex, ey) != ey)
        return ex < 0 ? ExceptionFlags.underflow : ExceptionFlags.overflow;

    sx ^= sy;

    if (r > T.max)
    {
        const px = prec(r);
        const pm = prec(T.max) - 1;
        const flags = divpow10(r, px - pm, sx, mode);
        if (cappedAdd(ex, px - pm) != px - pm)
            return ex < 0 ? ExceptionFlags.underflow : ExceptionFlags.overflow;
        cx = cvt!T(r);
        return flags;
    }
    else
    {
        cx = cvt!T(r);
        return ExceptionFlags.none;
    }
}

//div0, overflow, underflow
@safe pure nothrow @nogc
ExceptionFlags coefficientDiv(T)(ref T cx, ref int ex, ref bool sx, const T cy, const int ey, const bool sy, const RoundingMode mode)
{
    if (!cy)
    {
        sx ^= sy;
        return ExceptionFlags.divisionByZero;
    }

    if (!cx)
    {
        ex = 0;
        sx ^= sy;
        return ExceptionFlags.none;
    }

    if (cy == 1U)
    {
        if (cappedSub(ex, ey) != ey)
            return ex < 0 ? ExceptionFlags.underflow : ExceptionFlags.overflow;
        sx ^= sy;
        return ExceptionFlags.none;
    }

    Unqual!T savecx = cx;
    sx ^= sy;
    auto r = divrem(cx, cy);
    if (!r)
    {
        if (cappedSub(ex, ey) != ey)
           return ex < 0 ? ExceptionFlags.underflow : ExceptionFlags.overflow;
        return ExceptionFlags.none;
    }

    alias U = MakeUnsigned!(T.sizeof * 16);
    U cxx = savecx;
    const px = prec(savecx);
    const pm = prec(U.max) - 1;
    mulpow10(cxx, pm - px);
    const scale = pm - px - cappedSub(ex, pm - px);
    auto s = divrem(cxx, cy);
    ExceptionFlags flags;
    if (s)
    {
        const half = cy >>> 1;
        final switch (mode)
        {
            case RoundingMode.tiesToEven:
                if (s > half)
                    ++cxx;
                else if ((s == half) && ((cxx & 1U) == 0U))
                    ++cxx;
                break;
            case RoundingMode.tiesToAway:
                if (s >= half)
                    ++cxx;
                break;
            case RoundingMode.towardNegative:
                if (sx)
                    ++cxx;
                break;
            case RoundingMode.towardPositive:
                if (!sx)
                    ++cxx;
                break;
            case RoundingMode.towardZero:
                break;
        }
        flags = ExceptionFlags.inexact;
    }

    flags |= coefficientAdjust(cxx, ex, U(T.max), sx, mode);

    if (flags & ExceptionFlags.underflow)
    {
        cx = 0U;
        ex = 0U;
        return flags;
    }

    if (flags & ExceptionFlags.overflow)
        return flags;

    cx = cast(T)cxx;
    if (cappedSub(ex, ey) != ey)
        flags |= ex < 0 ? ExceptionFlags.underflow : ExceptionFlags.overflow;
    if (cappedSub(ex, scale) != scale)
        flags |= ex < 0 ? ExceptionFlags.underflow : ExceptionFlags.overflow;

    return flags;
}

//inexact, overflow, underflow
@safe pure nothrow @nogc
ExceptionFlags coefficientFMA(T)(ref T cx, ref int ex, ref bool sx, const T cy, const int ey, const bool sy, const T cz, const int ez, const bool sz, const RoundingMode mode)
{
    if (!cx || !cy)
    {
        cx = cz;
        ex = ez;
        sx = sz;
        return ExceptionFlags.none;
    }

    if (!cz)
        return coefficientMul(cx, ex, sx, cy, ey, sy, mode);

    if (cappedAdd(ex, ey) != ey)
        return ex < 0 ? ExceptionFlags.underflow : ExceptionFlags.overflow;
    auto m = xmul(cx, cy);
    sx ^= sy;

    typeof(m) czz = cz;
    auto flags = coefficientAdd(m, ex, sx, czz, ez, sz, mode);
    const pm = prec(m);
    const pmax = prec(T.max) - 1;
    if (pm > pmax)
    {
        flags |= divpow10(m, pm - pmax, sx, mode);
        if (cappedAdd(ex, pm - pmax) != pm - pmax)
            return ex < 0 ? ExceptionFlags.underflow : ExceptionFlags.overflow;
    }
    cx = cast(Unqual!T)m;
    return flags;
}

//inexact
@safe pure nothrow @nogc
ExceptionFlags coefficientRound(T)(ref T cx, ref int ex, const bool sx, const RoundingMode mode)
{
    if (ex < 0)
    {
        const flags = divpow10(cx, -ex, sx, mode);
        ex = 0;
        return flags;
    }
    return ExceptionFlags.none;
}

//inexact, overflow, underflow
@safe pure nothrow @nogc
ExceptionFlags coefficientMod(T)(ref T cx, ref int ex, ref bool sx, const T cy, const int ey, const bool sy, const RoundingMode mode)
{
    if (!cy)
        return ExceptionFlags.invalidOperation;
    Unqual!T rcx = cx;
    int rex = ex;
    bool rsx = sx;
    coefficientDiv(rcx, rex, rsx, cy, ey, sy, mode);   //16
    coefficientRound(rcx, rex, rsx, mode);             //00
    coefficientMul(rcx, rex, rsx, cy, ey, sy, mode);   //16
    return coefficientAdd(cx, ex, sx, rcx, rex, !rsx, mode);  //0
}

@safe pure nothrow @nogc
int coefficientCmp(T)(const T cx, const int ex, const bool sx, const T cy, const int ey, const bool sy)
{
    if (!cx)
        return cy ? (sy ? 1 : -1) : 0;
    if (!cy)
        return sx ? -1 : 1;

    if (sx && !sy)
        return -1;
    else if (!sx && sy)
        return 1;
    else
        return sx ? -coefficientCmp(cx, ex, cy, ey) : coefficientCmp(cx, ex, cy, ey);
}

@safe pure nothrow @nogc
int coefficientCmp(T)(const T cx, const int ex, const T cy, const int ey)
{
    if (!cx)
        return cy ? -1 : 0;
    if (!cy)
        return 1;

    const int px = prec(cx);
    const int py = prec(cy);

    if (px > py)
    {
        const int eyy = ey - (px - py);
        if (ex > eyy)
            return 1;
        if (ex < eyy)
            return -1;
        Unqual!T cyy = cy;
        mulpow10(cyy, px - py);
        if (cx > cyy)
            return 1;
        if (cx < cyy)
            return -1;
        return 0;
    }

    if (px < py)
    {
        const int exx = ex - (py - px);
        if (exx > ey)
            return 1;
        if (exx < ey)
            return -1;
        Unqual!T cxx = cx;
        mulpow10(cxx, py - px);
        if (cxx > cy)
            return 1;
        if (cxx < cy)
            return -1;
        return 0;
    }

    if (ex > ey)
        return 1;
    if (ex < ey)
        return -1;

    if (cx > cy)
        return 1;
    else if (cx < cy)
        return -1;
    return 0;
}

@safe pure nothrow @nogc
bool coefficientEqu(T)(const T cx, const int ex, const bool sx, const T cy, const int ey, const bool sy)
{
    if (!cx)
        return cy == 0U;

    if (sx != sy)
        return false;
    else
    {
        const int px = prec(cx);
        const int py = prec(cy);

        if (px > py)
        {
            int eyy = ey - (px - py);
            if (ex != eyy)
                return false;
            Unqual!T cyy = cy;
            mulpow10(cyy, px - py);
            return cx == cyy;
        }

        if (px < py)
        {
            int exx = ex - (py - px);
            if (exx != ey)
                return false;
            Unqual!T cxx = cx;
            mulpow10(cxx, py - px);
            return cxx == cy;
        }

        return cx == cy && ex == ey;
    }
}

@safe pure nothrow @nogc
bool coefficientApproxEqu(T)(const T cx, const int ex, const bool sx, const T cy, const int ey, const bool sy)
{
    //same as coefficientEqu, but we ignore the last digit if coefficient > 10^max
    //this is useful in convergence loops to not become infinite
    if (!cx)
        return cy == 0U;

    if (sx != sy)
        return false;
    else
    {
        const int px = prec(cx);
        const int py = prec(cy);

        if (px > py)
        {
            const int eyy = ey - (px - py);
            if (ex != eyy)
                return false;
            Unqual!T cyy = cy;
            mulpow10(cyy, px - py);
            if (cx > pow10!T[$ - 2])
                return cx >= cy ? cx - cy < 10U : cy - cx < 10U;
            return cx == cy;
        }

        if (px < py)
        {
            const int exx = ex - (py - px);
            if (exx != ey)
                return false;
            Unqual!T cxx = cx;
            mulpow10(cxx, py - px);
            if (cxx > pow10!T[$ - 2])
                return cxx >= cy ? cxx - cy < 10U : cy - cxx < 10U;
            return cx == cy;
        }

        if (cx > pow10!T[$ - 2])
            return cx >= cy ? cx - cy < 10U : cy - cx < 10U;

        return cx == cy;
    }
}

//inexact, overflow, underflow
@safe pure nothrow @nogc
ExceptionFlags coefficientSqr(T)(ref T cx, ref int ex, const RoundingMode mode)
{
    if (!cx)
    {
        cx = T(0U);
        ex = 0;
        return ExceptionFlags.none;
    }

    auto r = xsqr(cx);

    const int ey = ex;
    if (cappedAdd(ex, ey) != ey)
        return ex < 0 ? ExceptionFlags.underflow : ExceptionFlags.overflow;

    if (r > T.max)
    {
        const px = prec(r);
        const pm = prec(T.max) - 1;
        const flags = divpow10(r, px - pm, false, mode);
        if (cappedAdd(ex, px - pm) != px - pm)
            return ex < 0 ? ExceptionFlags.underflow : ExceptionFlags.overflow;
        cx = cvt!T(r);
        return flags;
    }
    else
    {
        cx = cvt!T(r);
        return ExceptionFlags.none;
    }
}

//inexact, underflow
@safe pure nothrow @nogc
ExceptionFlags coefficientSqrt(T)(ref T cx, ref int ex)
{
    // Newton-Raphson: x = (x + n/x) / 2;
    if (!cx)
    {
        cx = 0U;
        ex = 0;
        return ExceptionFlags.none;
    }

    alias U = MakeUnsigned!(T.sizeof * 16);

    U cxx = cx;
    ExceptionFlags flags;

    //we need full precision
    coefficientExpand(cxx, ex);

    if (ex & 1)
    {
        //exponent is odd, make it even
        flags = divpow10(cxx, 1, false, RoundingMode.implicit);
        ++ex;
    }

    ex /= 2;
    const bool inexact = decimal.integrals.sqrt(cxx);
    flags |= coefficientAdjust(cxx, ex, cvt!U(T.max), false, RoundingMode.implicit);
    cx = cast(T)cxx;
    return inexact ? flags | ExceptionFlags.inexact : flags;
}

//inexact, underflow
@safe pure nothrow @nogc
ExceptionFlags coefficientRSqrt(T)(ref T cx, ref int ex)
{
    bool sx = false;
    if (!cx)
        return ExceptionFlags.divisionByZero;
    Unqual!T cy = cx; int ey = ex;
    const flags = coefficientSqrt(cy, ey);
    if (flags & ExceptionFlags.underflow)
        return ExceptionFlags.overflow;
    cx = 1U;
    ex = 0;
    return flags | coefficientDiv(cx, ex, sx, cy, ey, false, RoundingMode.implicit);
}

@safe pure nothrow @nogc
ExceptionFlags coefficientCbrt(T)(ref T cx, ref int ex)
{
    // Newton-Raphson: x = (2x + N/x2)/3

    if (!cx)
    {
        cx = 0U;
        ex = 0;
        return ExceptionFlags.none;
    }

    alias U = MakeUnsigned!(T.sizeof * 16);

    U cxx = cx;
    ExceptionFlags flags;

    //we need full precision
    coefficientExpand(cxx, ex);

    const r = ex % 3;
    if (r)
    {
        //exponent is not divisible by 3, make it
        flags = divpow10(cxx, 3 - r, false, RoundingMode.implicit);
        ex += 3 - r;
    }

    ex /= 3;
    const bool inexact = decimal.integrals.cbrt(cxx);
    flags |= coefficientAdjust(cxx, ex, cvt!U(T.max), false, RoundingMode.implicit);
    cx = cast(T)cxx;
    return inexact ? flags | ExceptionFlags.inexact : flags;
}

@safe pure nothrow @nogc
ExceptionFlags coefficientHypot(T)(ref T cx, ref int ex, auto const ref T cy, const int ey)
{
    Unqual!T cyy = cy;
    int eyy = ey;
    bool sx;
    auto flags = coefficientSqr(cx, ex, RoundingMode.implicit);
    flags |= coefficientSqr(cyy, eyy, RoundingMode.implicit);
    flags |= coefficientAdd(cx, ex, sx, cyy, eyy, false, RoundingMode.implicit);
    flags |= coefficientSqrt(cx, ex);
    return flags;
}

@safe pure nothrow @nogc
ExceptionFlags coefficientExp(T)(ref T cx, ref int ex, ref bool sx)
{
    //e^x = 1 + x + x2/2! + x3/3! + x4/4! ...
    //to avoid overflow and underflow:
    //x^n/n! = (x^(n-1)/(n-1)! * x/n

    //save x for repeated multiplication
    const Unqual!T cxx = cx;
    const exx = ex;
    const sxx = sx;

    //shadow value
    Unqual!T cy;
    int ey = 0;
    bool sy = false;

    Unqual!T cf = cx;
    int ef = ex;
    bool sf = sx;

    if (coefficientAdd(cx, ex, sx, T(1U), 0, false, RoundingMode.implicit) & ExceptionFlags.overflow)
        return ExceptionFlags.overflow;

    Unqual!T n = 1U;

    do
    {
        cy = cx;
        ey = ex;
        sy = sx;

        Unqual!T cp = cxx;
        int ep = exx;
        bool sp = sxx;

        coefficientDiv(cp, ep, sp, ++n, 0, false, RoundingMode.implicit);
        coefficientMul(cf, ef, sf, cp, ep, sp, RoundingMode.implicit);
        coefficientAdd(cx, ex, sx, cf, ef, sf, RoundingMode.implicit);
    }
    while (!coefficientApproxEqu(cx, ex, sx, cy, ey, sy));

    return ExceptionFlags.inexact;
}

@safe pure nothrow @nogc
ExceptionFlags coefficientLog(T)(ref T cx, ref int ex, ref bool sx)
in
{
    assert(!sx); //only positive
    assert(cx);
}
do
{
    //ln(coefficient * 10^exponent) = ln(coefficient) + exponent * ln(10);

    static if (is(T:uint))
    {
        immutable uint ce = 2718281828U;
        immutable int ee = -9;
        immutable uint cl = 2302585093U;
        immutable int el = -9;
    }
    else static if (is(T:ulong))
    {
        immutable ulong ce = 2718281828459045235UL;
        immutable int ee = -18;
        immutable ulong cl = 2302585092994045684UL;
        immutable int el = -18;
    }
    else static if (is(T:uint128))
    {
        immutable uint128 ce = uint128("271828182845904523536028747135266249776");
        immutable int ee = -38;
        immutable uint128 cl = uint128("230258509299404568401799145468436420760");
        immutable int el = -38;
    }
    else
        static assert(0);

    //ln(x) = ln(n*e) = ln(n) + ln(e);
    //we divide x by e to find out how many times (n) we must add ln(e) = 1
    //ln(x + 1) taylor series works in the interval (-1 .. 1]
    //so our taylor series is valid for x in (0 .. 2]

    //save exponent for later
    int exponent = ex;
    ex = 0;

    enum one = T(1U);
    enum two = T(2U);

    Unqual!T n = 0U;
    bool ss = false;

    const aaa = cx;

    while (coefficientCmp(cx, ex, false, two, 0, false) >= 0)
    {
        coefficientDiv(cx, ex, sx, ce, ee, false, RoundingMode.implicit);
        ++n;
    }

    coefficientDiv(cx, ex, sx, ce, ee, false, RoundingMode.implicit);
    ++n;

    //ln(x) = (x - 1) - [(x - 1)^2]/2 + [(x - 1)^3]/3 - ....

    //initialize our result to x - 1;
    coefficientAdd(cx, ex, sx, one, 0, true, RoundingMode.implicit);

    //store cx in cxm1, this will be used for repeated multiplication
    //we negate the sign to alternate between +/-
    Unqual!T cxm1 = cx;
    int exm1 = ex;
    bool sxm1 = !sx;

    //shadow
    Unqual!T cy;
    int ey;
    bool sy;

    Unqual!T cd = cxm1;
    int ed = exm1;
    bool sd = !sxm1;

    Unqual!T i = 2U;

    do
    {
        cy = cx;
        ey = ex;
        sy = sx;

        coefficientMul(cd, ed, sd, cxm1, exm1, sxm1, RoundingMode.implicit);

        Unqual!T cf = cd;
        int ef = ed;
        bool sf = sd;

        coefficientDiv(cf, ef, sf, i++, 0, false, RoundingMode.implicit);
        coefficientAdd(cx, ex, sx, cf, ef, sf, RoundingMode.implicit);

        //writefln("%10d %10d %10d %10d %10d %10d", cx, ex, cy, ey, cx - cy, i);
    }
    while (!coefficientApproxEqu(cx, ex, sx, cy, ey, sy));

    coefficientAdd(cx, ex, sx, n, 0, false, RoundingMode.implicit);

    if (exponent != 0)
    {
        sy = exponent < 0;
        cy = sy ? cast(uint)(-exponent) : cast(uint)(exponent);
        ey = 0;
        coefficientMul(cy, ey, sy, cl, el, false, RoundingMode.implicit);
        coefficientAdd(cx, ex, sx, cy, ey, sy, RoundingMode.implicit);
    }

    //iterations
    //Decimal32 min:         15, max:         48 avg:      30.03
    //Decimal64 min:         30, max:        234 avg:     149.25
    return ExceptionFlags.inexact;
}

@safe pure nothrow @nogc
ExceptionFlags coefficientAtanh(T)(ref T cx, ref int ex, ref bool sx)
{
    //1/2*ln[(1 + x)/(1 - x)]

    assert (coefficientCmp(cx, ex, sx, T(1U), 0, true) > 0);
    assert (coefficientCmp(cx, ex, sx, T(1U), 0, false) < 0);

    //1/2*ln[(1 + x)/(1 - x)]

    Unqual!T cm1 = cx;
    int em1 = ex;
    bool sm1 = !sx;
    coefficientAdd(cm1, em1, sm1, T(1U), 0, false, RoundingMode.implicit);
    coefficientAdd(cx, ex, sx, T(1U), 0, false, RoundingMode.implicit);
    coefficientDiv(cx, ex, sx, cm1, em1, sm1, RoundingMode.implicit);
    coefficientLog(cx, ex, sx);
    coefficientMul(cx, ex, sx, T(5U), -1, false, RoundingMode.implicit);
    return ExceptionFlags.inexact;
}

//caps angle to -2π ... +2π
@safe pure nothrow @nogc
ExceptionFlags coefficientCapAngle(T)(ref T cx, ref int ex, ref bool sx)
{
    if (coefficientCmp(cx, ex, Constants!T.c2π, Constants!T.e2π) > 0)
    {
        alias U = MakeUnsigned!(T.sizeof * 16);
        U cxx = cx;
        auto flags = coefficientMod2PI(cxx, ex);
        flags |= coefficientAdjust(cxx, ex, cvt!U(T.max), sx, RoundingMode.implicit);
        cx = cvt!T(cxx);
    }
    return ExceptionFlags.none;
}

//caps angle to -π/2  .. +π/2
@safe pure nothrow @nogc
ExceptionFlags coefficientCapAngle(T)(ref T cx, ref int ex, ref bool sx, out int quadrant)
{
    quadrant = 1;
    if (coefficientCmp(cx, ex, Constants!T.cπ_2, Constants!T.eπ_2) > 0)
    {
        ExceptionFlags flags;
        if (coefficientCmp(cx, ex, Constants!T.c2π, Constants!T.e2π) > 0)
        {
            alias U = MakeUnsigned!(T.sizeof * 16);
            U cxx = cx;
            flags = coefficientMod2PI(cxx, ex);
            flags |= coefficientAdjust(cxx, ex, cvt!U(T.max), sx, RoundingMode.implicit);
            cx = cvt!T(cxx);
            if (coefficientCmp(cx, ex, Constants!T.cπ_2, Constants!T.eπ_2) <= 0)
                return flags;
        }
        Unqual!T cy = cx;
        int ey = ex;
        bool sy = sx;
        flags |= coefficientMul(cy, ey, sy, Constants!T.c2_π, Constants!T.e2_π, false, RoundingMode.towardZero);
        flags |= coefficientRound(cy, ey, sy, RoundingMode.towardZero);
        quadrant = cast(uint)(cy % 4U) + 1;
        flags |= coefficientMul(cy, ey, sy, Constants!T.cπ_2, Constants!T.eπ_2, false, RoundingMode.implicit);
        flags |= coefficientAdd(cx, ex, sx, cy, ey, !sy, RoundingMode.implicit);
        return flags;
    }
    return ExceptionFlags.none;
}

@safe pure nothrow @nogc
ExceptionFlags coefficientSinQ(T)(ref T cx, ref int ex, ref bool sx)
{
    //taylor series: sin(x) = x - x^3/3! + x^5/5! - x^7/7! ...

    Unqual!T cx2 = cx; int ex2 = ex; bool sx2 = true;
    coefficientSqr(cx2, ex2, RoundingMode.implicit);

    Unqual!T cy; int ey; bool sy;
    Unqual!T cf = cx; int ef = ex; bool sf = sx;
    Unqual!T n = 2U;

    do
    {
        cy = cx;
        ey = ex;
        sy = sx;

        coefficientMul!T(cf, ef, sf, cx2, ex2, sx2, RoundingMode.implicit);
        coefficientDiv!T(cf, ef, sf, n++, 0, false, RoundingMode.implicit);
        coefficientDiv!T(cf, ef, sf, n++, 0, false, RoundingMode.implicit);
        coefficientAdd!T(cx, ex, sx, cf, ef, sf, RoundingMode.implicit);
        //writefln("%10d %10d %10d %10d", cx, ex, cy, ey);
       // writefln("%016x%016x %10d %016x%016x %10d", cx.hi, cx.lo, ex, cy.hi, cy.lo, ey);
    }
    while (!coefficientApproxEqu!T(cx, ex, sx, cy, ey, sy));
    return ExceptionFlags.inexact;
}

unittest
{
    ulong cx = 11000000000000000855UL;
    int ex = -19;
    bool sx;

    coefficientSinQ!ulong(cx, ex, sx);

    //writefln("%35.34f", sin(Decimal128("1.1000000000000000855000000000000000")));
    //writefln("%35.34f", Decimal128(1.1));
}

@safe pure nothrow @nogc
ExceptionFlags coefficientCosQ(T)(ref T cx, ref int ex, ref bool sx)
{
    //taylor series: cos(x) = 1 - x^2/2! + x^4/4! - x^6/6! ...

    Unqual!T cx2 = cx; int ex2 = ex; bool sx2 = true;
    coefficientSqr(cx2, ex2, RoundingMode.implicit);

    cx = 1U;
    ex = 0;
    sx = false;
    Unqual!T cy; int ey; bool sy;
    Unqual!T cf = cx; int ef = ex; bool sf = sx;
    Unqual!T n = 1U;

    do
    {
        cy = cx;
        ey = ex;
        sy = sx;

        coefficientMul(cf, ef, sf, cx2, ex2, sx2, RoundingMode.implicit);
        coefficientDiv(cf, ef, sf, n++, 0, false, RoundingMode.implicit);
        coefficientDiv(cf, ef, sf, n++, 0, false, RoundingMode.implicit);
        coefficientAdd(cx, ex, sx, cf, ef, sf, RoundingMode.implicit);
        //writefln("%10d %10d %10d %10d", cx, ex, cy, ey);
    }
    while (!coefficientApproxEqu(cx, ex, sx, cy, ey, sy));
    return ExceptionFlags.inexact;
}

@safe pure nothrow @nogc
ExceptionFlags coefficientSinCosQ(T)(const T cx, const int ex, const bool sx,
    out T csin, out int esin, out bool ssin,
    out T ccos, out int ecos, out bool scos)
{
    csin = cx; esin = ex; ssin = sx;
    ccos = 1U; ecos = 0; scos = false;
    Unqual!T cs, cc; int es, ec; bool ss, sc;
    Unqual!T cf = cx; int ef = ex; bool sf = sx;
    Unqual!T n = 2U;
    do
    {
        cs = csin; es = esin; ss = ssin;
        cc = ccos; ec = ecos; sc = scos;
        coefficientMul(cf, ef, sf, cx, ex, !sx, RoundingMode.implicit);
        coefficientDiv(cf, ef, sf, n++, 0, false, RoundingMode.implicit);
        coefficientAdd(ccos, ecos, scos, cf, ef, sf, RoundingMode.implicit);
        coefficientMul(cf, ef, sf, cx, ex, sx, RoundingMode.implicit);
        coefficientDiv(cf, ef, sf, n++, 0, false, RoundingMode.implicit);
        coefficientAdd(csin, esin, ssin, cf, ef, sf, RoundingMode.implicit);
        //writefln("%10d %10d %10d %10d %10d %10d %10d %10d", csin, esin, cs, es, ccos, ecos, cc, ec);
    }
    while(!coefficientApproxEqu(csin, esin, ssin, cs, es, ss) &&
          !coefficientApproxEqu(ccos, ecos, scos, cc, ec, sc));

    return ExceptionFlags.inexact;
}

@safe pure nothrow @nogc
ExceptionFlags coefficientCapAtan(T)(ref T cx, ref int ex, ref bool sx, out T reductions)
{
    //half angle formula: atan(x/2) = 2 * atan(x/(1 + sqrt(1 +x^^2))))
    //reduce x = x / (sqrt(x * x + 1) + 1);

    reductions = 0U;
    while (coefficientCmp(cx, ex, T(1U), 0) >= 0)
    {
        Unqual!T cy = cx; int ey = ex; bool sy = false;
        coefficientSqr(cy, ey, RoundingMode.implicit);
        coefficientAdd(cy, ey, sy, T(1U), 0, false, RoundingMode.implicit);
        coefficientSqrt(cy, ey);
        coefficientAdd(cy, ey, sy, T(1U), 0, false, RoundingMode.implicit);
        coefficientDiv(cx, ex, sx, cy, ey, false, RoundingMode.implicit);
        ++reductions;
    }

    return ExceptionFlags.inexact;
}

@safe pure nothrow @nogc
ExceptionFlags coefficientAtan(T)(ref T cx, ref int ex, bool sx)
{
    //taylor series:
    //atan(x) = x - x^3/3 + x^5/5 - x^7/7 ...

    Unqual!T cx2 = cx; int ex2 = ex;
    coefficientSqr(cx2, ex2, RoundingMode.implicit);

    Unqual!T cy; int ey; bool sy;
    Unqual!T cxx = cx; int exx = ex; bool sxx = sx;
    Unqual!T n = 3U;

    do
    {
        cy = cx;
        ey = ex;
        sy = sx;

        coefficientMul(cxx, exx, sxx, cx2, ex2, true, RoundingMode.implicit);

        Unqual!T cf = cxx;
        int ef = exx;
        bool sf = sxx;

        coefficientDiv(cf, ef, sf, n, 0, false, RoundingMode.implicit);
        coefficientAdd(cx, ex, sx, cf, ef, sf, RoundingMode.implicit);
        n += 2U;
    }
    while (!coefficientApproxEqu(cx, ex, sx, cy, ey, sy));
    return ExceptionFlags.inexact;
}

ExceptionFlags coefficientFrac(T)(ref T cx, ref int ex)
{
    if (ex >= 0)
    {
        cx = 0U;
        ex = 0;
        return ExceptionFlags.none;
    }
    const p = prec(cx);
    if (ex < -p)
       return ExceptionFlags.none;
    cx %= pow10!T[-ex];
    return ExceptionFlags.none;
}

ExceptionFlags coefficientMod2PI(T)(ref T cx, ref int ex)
{
    ExceptionFlags flags;
    if (coefficientCmp(cx, ex, Constants!T.c2π, Constants!T.e2π) > 0)
    {
        bool sx = false;
        Unqual!T cy = cx;
        cx = get_mod2pi!T(ex);
        flags |= coefficientMul(cx, ex, sx, cy, 0, false, RoundingMode.implicit);
        flags |= coefficientFrac(cx, ex);
        flags |= coefficientMul(cx, ex, sx, Constants!T.c2π, Constants!T.e2π, false, RoundingMode.implicit);
    }
    return flags;
}

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
        enum uint128    c1_2π       = uint128("159154943091895335768883763372514362034");
        enum int        e1_2π       = -39;
        enum uint128    c2π         = uint128("62831853071795864769252867665590057684");
        enum int        e2π         = -37;
        enum uint128    c2_π        = uint128("63661977236758134307553505349005744814");
        enum int        e2_π        = -38;
        enum uint128    cπ_2        = uint128("157079632679489661923132169163975144210");
        enum int        eπ_2        = -38;
        enum uint128    chalf       = 5U;
        enum int        ehalf       = -1;
        enum uint128    cthird      = uint128("333333333333333333333333333333333333333");
        enum int        ethird      = -39;
        enum uint128    ce          = uint128("271828182845904523536028747135266249776");
        enum int        ee          = -38;
        enum uint128    cln10       = uint128("230258509299404568401799145468436420760");
        enum int        eln10       = -38;
    }
    else static if (is(T:uint256))
    {
        enum uint256    c1_2π       = uint256("15915494309189533576888376337251436203445964574045644874766734405889679763423");
        enum int        e1_2π       = -77;
        enum uint256    c2π         = uint256("62831853071795864769252867665590057683943387987502116419498891846156328125724");
        enum int        e2π         = -76;
        enum uint256    c2_π        = uint256("63661977236758134307553505349005744813783858296182579499066937623558719053691");
        enum int        e2_π        = -77;
        enum uint256    cπ_2        = uint256("15707963267948966192313216916397514420985846996875529104874722961539082031431");
        enum int        eπ_2        = -76;
        enum uint256    chalf       = 5U;
        enum int        ehalf       = -1;
        enum uint256    cthird      = uint256("33333333333333333333333333333333333333333333333333333333333333333333333333333");
        enum int        ethird      = -77;
        enum uint256    ce          = uint256("27182818284590452353602874713526624977572470936999595749669676277240766303536");
        enum int        ee          = -76;
        enum uint256    cln10       = uint256("23025850929940456840179914546843642076011014886287729760333279009675726096774");
        enum int        eln10       = -76;
    }
    else
        static assert(0);
}

enum
{
    s_e             = "2.7182818284590452353602874713526625",
    s_pi            = "3.1415926535897932384626433832795029",
    s_pi_2          = "1.5707963267948966192313216916397514",
    s_pi_4          = "0.7853981633974483096156608458198757",
    s_m_1_pi        = "0.3183098861837906715377675267450287",
    s_m_2_pi        = "0.6366197723675813430755350534900574",
    s_m_2_sqrtpi    = "1.1283791670955125738961589031215452",
    s_sqrt2         = "1.4142135623730950488016887242096981",
    s_sqrt1_2       = "0.7071067811865475244008443621048490",
    s_ln10          = "2.3025850929940456840179914546843642",
    s_log2t         = "3.3219280948873623478703194294893902",
    s_log2e         = "1.4426950408889634073599246810018921",
    s_log2          = "0.3010299956639811952137388947244930",
    s_log10e        = "0.4342944819032518276511289189166051",
    s_ln2           = "0.6931471805599453094172321214581766",

    s_sqrt3         = "1.7320508075688772935274463415058723",
    s_m_sqrt3       = "0.5773502691896257645091487805019574",
    s_pi_3          = "1.0471975511965977461542144610931676",
    s_pi_6          = "0.5235987755982988730771072305465838",

    s_sqrt2_2       = "0.7071067811865475244008443621048490",
    s_sqrt3_2       = "0.8660254037844386467637231707529361",
    s_5pi_6         = "2.6179938779914943653855361527329190",
    s_3pi_4         = "2.3561944901923449288469825374596271",
    s_2pi_3         = "2.0943951023931954923084289221863352",
    s_onethird      = "0.3333333333333333333333333333333333",
    s_twothirds     = "0.6666666666666666666666666666666667",
    s_5_6           = "0.8333333333333333333333333333333333",
    s_1_6           = "0.1666666666666666666666666666666667",
    s_m_1_2pi       = "0.1591549430918953357688837633725144",
    s_pi2           = "6.2831853071795864769252867665590058",

    s_max_float     = "3.402823466385288598117041834845169e+0038",
    s_min_float     = "1.401298464324817070923729583289916e-0045",
    s_max_double    = "1.797693134862315708145274237317043e+0308",
    s_min_double    = "4.940656458412465441765687928682213e-0324",
    s_max_real      = "1.189731495357231765021263853030970e+4932",
    s_min_real      = "3.645199531882474602528405933619419e-4951",
}

    //to find mod(10^n/2pi; 1): take digits[n .. n + precision], exponent -n
    //example mod(10^3/2pi; 1): 1549430918953357688e-19, precision = 19
    //example mod(10^9/2pi; 1): 0918953357688837633e-19, precision = 19 = 918953357688837633[7]e-20
    //example mode(10^-8/2pi;1):0000000015915494309e-19, precision = 19 = 15915494309[18953357]e-27
    //limit: 9866, that means nmax = 9866 - precision;
    //mod(c * 10^n mod 2pi) = frac(c * mod(10^n/2pi; 1)) * 2pi;
    //example for Decimal32 -> mod(10^n/2pi; 1) => 19 digits
    //   c * mod(10^n/2pi; 1) => 19 + 7 = 26 digits =>

immutable s_mod_1_2pi =
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
        static assert (0, "Unsupported" ~ U.stringof);

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

struct IEEECompliant
{
    string name;
    int page;
}

D parse(D, R)(ref R range)
if (isInputRange!R && isSomeChar!(ElementType!R) && isDecimal!D)
{
    Unqual!D result;
    const flags = parse(range, result, D.realPrecision(DecimalControl.precision), DecimalControl.rounding);
    if (flags)
        DecimalControl.raiseFlags(flags);
    return result;
}

//10 bit encoding
@safe pure nothrow @nogc
private uint packDPD(const uint d1, const uint d2, const uint d3)
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
@safe pure nothrow @nogc
private void unpackDPD(const uint declet, out uint d1, out uint d2, out uint d3)
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
