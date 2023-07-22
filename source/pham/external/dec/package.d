
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
module pham.external.dec;

public import pham.external.dec.decimal;
public import pham.external.dec.type;
