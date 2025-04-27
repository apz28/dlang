module pham.external.dec.dec_type;

import std.traits : isFloatingPoint;

import pham.external.dec.dec_integral : uint128;

nothrow @safe:

enum CheckInfinity : byte
{
    no = 0,         /// The value is $(B NaN) (quiet or signaling) or any finite value
    yes = 1,        /// The value is infinite
    negative = -1,  /// The value is negative infinite
}

enum CheckNaN : byte
{
    no = 0,         /// The value is not $(B NaN) (quiet or signaling)
    qNaN = 1,       /// The value is $(B NaN) quiet
    sNaN = 2,       /// The value is $(B NaN) signaling
    negQNaN = -1,   /// The value is negative $(B NaN) quiet
    negSNaN = -2,   /// The value is negative $(B NaN) signaling
}

enum ExceptionFlag : ubyte
{
    invalidOperation,
    divisionByZero,
    overflow,
    underflow,
    inexact,
}

/**
 * These flags indicate that an error has occurred. They indicate that a 0, $(B NaN) or an infinity value has been generated,
 * that a result is inexact, or that a signalling $(B NaN) has been encountered.
 * If the corresponding traps are set using $(MYREF DecimalControl),
 * an exception will be thrown after setting these error flags.
 * By default the context will have all error flags lowered and exceptions are thrown only for severe errors.
 */
enum ExceptionFlags : uint
{
    ///no error
    none             = 0U,
    ///$(MYREF InvalidOperationException) is thrown if trap is set
	invalidOperation = 1U << ExceptionFlag.invalidOperation,
    ///$(MYREF DivisionByZeroException) is thrown if trap is set
	divisionByZero   = 1U << ExceptionFlag.divisionByZero,
    ///$(MYREF OverflowException) is thrown if trap is set
	overflow         = 1U << ExceptionFlag.overflow,
    ///$(MYREF UnderflowException) is thrown if trap is set
	underflow        = 1U << ExceptionFlag.underflow,
    ///$(MYREF InexactException) is thrown if trap is set
	inexact          = 1U << ExceptionFlag.inexact,
    ///group of errors considered severe: invalidOperation, divisionByZero, overflow, underflow
	severe           = invalidOperation | divisionByZero | overflow | underflow,
    ///all errors
	all              = severe | inexact,
}

static immutable string[ExceptionFlag.max + 1] exceptionMessages = [
    "Invalid operation",
    "Division by zero",
    "Overflow",
    "Underflow",
    "Inexact",
];

string getExceptionMessage(string throwingMsg, const(ExceptionFlag) kind) @nogc nothrow pure @safe
{
    return throwingMsg.length != 0 ? throwingMsg : exceptionMessages[kind];
}

version(D_BetterC)
string getExceptionMessage(return char[] bufferMsg, string throwingMsg, const(ExceptionFlag) kind, string file, size_t line) @nogc nothrow pure @safe
{
    import std.format : sformat;

    return sformat(bufferMsg, "%s in %s [%d]", getExceptionMessage(throwingMsg, kind), file, line);
}

template DataType(int bytes)
if (bytes == 4 || bytes == 8 || bytes == 16)
{
    static if (bytes == 4)
        alias DataType = uint;
    else static if (bytes == 8)
        alias DataType = ulong;
    else static if (bytes == 16)
        alias DataType = uint128;
    else
        static assert(0);
}

///IEEE-754-2008 floating point categories
enum DecimalClass : ubyte
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

///IEEE-754-2008 subset of floating point categories
enum DecimalSubClass : ubyte
{
    signalingNaN,
    quietNaN,
    negativeInfinity,
    positiveInfinity,
    finite,
}

enum FastClass : ubyte
{
    signalingNaN,
    quietNaN,
    infinite,
    zero,
    finite,
}

/**
 * Precision used to round decimal operation results. Every result will be adjusted
 * to fit the specified precision. Use $(MYREF DecimalControl) to query or set the
 * context precision
 */
enum Precision : int
{
    ///use the default precision of the current type
    ///(7 digits for Decimal32, 16 digits for Decimal64 or 34 digits for Decimal128)
	precisionDefault = 0,
    ///use 32 bits precision (7 digits)
	precision32 = precisionOf(4),
    ///use 64 bits precision (16 digits)
	precision64 = precisionOf(8),
    ///use 128 bits precision (34 digits)
    precision128 = precisionOf(16),

    ////
    bankingScale = 4,
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
enum RoundingMode : ubyte
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
    banking = tiesToEven,
}

/**
 * Container for _decimal context control, provides methods to alter exception handling,
 * manually edit error flags, adjust arithmetic precision and rounding mode
 */
struct DecimalControl
{
@safe:

private:
	static DecimalControlFlags _state;

public:
    /**
     * Gets or sets the rounding mode used when the result of an operation exceeds the _decimal precision.
     * See $(MYREF RoundingMode) for details.
     * ---
     * DecimalControl.rounding = RoundingMode.tiesToEven;
     * Decimal32 d1 = 123456789;
     * assert(d1 == 123456800);

     * DecimalControl.rounding = RoundingMode.towardNegative;
     * Decimal32 d2 = 123456789;
     * assert(d2 == 123456700);
     * ---
     */
    @IEEECompliant("defaultModes", 46)
    @IEEECompliant("getDecimalRoundingDirection", 46)
    @IEEECompliant("restoreModes", 46)
    @IEEECompliant("saveModes", 46)
    @IEEECompliant("setDecimalRoundingDirection", 46)
    static RoundingMode rounding;

    /**
     * Gets or sets the precision applied to peration results.
     * See $(MYREF Precision) for details.
     * ---
     * DecimalControl.precision = precisionDefault;
     * Decimal32 d1 = 12345;
     * assert(d1 == 12345);

     * DecimalControl.precision = 4;
     * Decimal32 d2 = 12345;
     * assert(d2 == 12350);
     * ---
     */
    static int precision;

    /**
     * Check flags for traps value and raise exception if set
     * Order of flag to be checked:
     *  invalidOperation, divisionByZero, overflow, underflow and inexact
     * ---
     * DecimalControl.enableTraps();
     * try
     * {
     *     const flags = ExceptionFlags.divisionByZero | ExceptionFlags.overflow;
     *     const traps = ExceptionFlags.severe;
     *     checkFlags(flags, traps);
     * }
     * catch (DivisionByZeroException)
     * {
     * }
     * ---
     */
    static void checkFlags(const(ExceptionFlags) flags, const(ExceptionFlags) traps,
        string msg = null, string file = __FILE__, uint line = __LINE__) pure @trusted
    {
        if (isFlagTrapped(flags, traps, ExceptionFlags.invalidOperation))
            throwFlags(ExceptionFlags.invalidOperation, msg, file, line);
        else if (isFlagTrapped(flags, traps, ExceptionFlags.divisionByZero))
            throwFlags(ExceptionFlags.divisionByZero, msg, file, line);
        else if (isFlagTrapped(flags, traps, ExceptionFlags.overflow))
            throwFlags(ExceptionFlags.overflow, msg, file, line);
        else if (isFlagTrapped(flags, traps, ExceptionFlags.underflow))
            throwFlags(ExceptionFlags.underflow, msg, file, line);
        else if (isFlagTrapped(flags, traps, ExceptionFlags.inexact))
            throwFlags(ExceptionFlags.inexact, msg, file, line);


    }

    pragma(inline, true)
    static bool isFlagTrapped(const(ExceptionFlags) flags, const(ExceptionFlags) traps, const(ExceptionFlags) checkingFlag) @nogc nothrow pure
    {
        return (flags & checkingFlag) && (traps & checkingFlag);
    }

    /**
     * Return true if flags contain overflow or underflow value
     */
    static bool isOverUnderFlow(const(ExceptionFlags) flags) @nogc nothrow pure
    {
        return (flags & (ExceptionFlags.overflow || ExceptionFlags.underflow)) != 0;
    }

    /**
     * Clear current traps & flags to none state and return its' previous state
     */
    static DecimalControlFlags clearState() @nogc nothrow
    {
        const result = _state;
        _state.flags = _state.traps = ExceptionFlags.none;
        return result;
    }

    /**
     * Set the traps & flags to 'state' value and return its's previous state
     */
    static DecimalControlFlags restoreState(const(DecimalControlFlags) state) @nogc nothrow
    {
        const result = _state;
        _state = state;
        return result;
    }

    /**
     * Sets specified error flags. Multiple errors may be ORed together.
     * ---
     * DecimalControl.raiseFlags(ExceptionFlags.overflow | ExceptionFlags.underflow);
     * assert(DecimalControl.overflow);
     * assert(DecimalControl.underflow);
     * ---
	 */
    @IEEECompliant("raiseFlags", 26)
	static void raiseFlags(const(ExceptionFlags) raisingFlags,
        string msg = null, string file = __FILE__, uint line = __LINE__)
	{
        const validFlags = raisingFlags & ExceptionFlags.all;
        if (__ctfe)
            checkFlags(validFlags, ExceptionFlags.severe, msg, file, line);
        else
        {
            const newFlags = _state.flags ^ validFlags;
            _state.flags |= validFlags;
		    checkFlags(newFlags, traps, msg, file, line);
        }
	}

    /**
     * Unsets specified error flags. Multiple errors may be ORed together.
     * ---
     * DecimalControl.resetFlags(ExceptionFlags.inexact);
     * assert(!DecimalControl.inexact);
     * ---
	 */
    @IEEECompliant("lowerFlags", 26)
	static ExceptionFlags resetFlags(const(ExceptionFlags) resetingFlags) @nogc nothrow
	{
        const result = _state.flags;
        _state.flags &= ~(resetingFlags & ExceptionFlags.all);
        return result;
	}

    /**
     * Enables specified error flags (group) without throwing corresponding exceptions.
     * ---
     * DecimalControl.restoreFlags(ExceptionFlags.underflow | ExceptionsFlags.inexact);
     * assert(DecimalControl.testFlags(ExceptionFlags.underflow | ExceptionFlags.inexact));
     * ---
	 */
    @IEEECompliant("restoreFlags", 26)
	static ExceptionFlags restoreFlags(const(ExceptionFlags) restoringFlags) @nogc nothrow
	{
        if (__ctfe)
        {
            return ExceptionFlags.none;
        }
        else
        {
            const result = _state.flags;
            _state.flags |= restoringFlags & ExceptionFlags.all;
            return result;
        }
	}

    version(D_BetterC)
    {}
    else
    {
        import pham.external.dec.dec_decimal :
            InvalidOperationException, DivisionByZeroException, OverflowException, UnderflowException, InexactException;

        version(decNogcException)
        {
            static immutable eDivisionByZeroException = new DivisionByZeroException(exceptionMessages[ExceptionFlag.divisionByZero]);
            static immutable eInexactException = new InexactException(exceptionMessages[ExceptionFlag.inexact]);
            static immutable eInvalidOperationException = new InvalidOperationException(exceptionMessages[ExceptionFlag.invalidOperation]);
            static immutable eOverflowException = new OverflowException(exceptionMessages[ExceptionFlag.overflow]);
            static immutable eUnderflowException = new UnderflowException(exceptionMessages[ExceptionFlag.underflow]);
        }
    }

    static void throwFlags(const(ExceptionFlags) flags,
        string msg = null, string file = __FILE__, uint line = __LINE__) pure @trusted
    {
        if (flags & ExceptionFlags.invalidOperation)
            throwInvalidOperationError(msg, file, line);
        else if (flags & ExceptionFlags.divisionByZero)
            throwDivisionByZeroError(msg, file, line);
        else if (flags & ExceptionFlags.overflow)
            throwOverflowError(msg, file, line);
        else if (flags & ExceptionFlags.underflow)
            throwUnderflowError(msg, file, line);
        else if (flags & ExceptionFlags.inexact)
            throwInexactError(msg, file, line);
    }

    version(D_BetterC)
    private static char[500] errorMessageBuffer;

    static noreturn throwDivisionByZeroError(string msg = null, string file = __FILE__, uint line = __LINE__) pure @trusted
    {
        version(D_BetterC)
        {
            assert(0, getExceptionMessage(errorMessageBuffer[], msg, ExceptionFlag.divisionByZero, file, line));
        }
        else
        {
            version(decNogcException)
                throw (cast()eDivisionByZeroException).set(msg, file, line);
            else
                throw new DivisionByZeroException(getExceptionMessage(msg, ExceptionFlag.divisionByZero), file, line);
        }
    }

    static noreturn throwInexactError(string msg = null, string file = __FILE__, uint line = __LINE__) pure @trusted
    {
        version(D_BetterC)
        {
            assert(0, getExceptionMessage(errorMessageBuffer[], msg, ExceptionFlag.inexact, file, line));
        }
        else
        {
            version(decNogcException)
                throw (cast()eInexactException).set(msg, file, line);
            else
                throw new InexactException(getExceptionMessage(msg, ExceptionFlag.inexact), file, line);
        }
    }

    static noreturn throwInvalidOperationError(string msg = null, string file = __FILE__, uint line = __LINE__) pure @trusted
    {
        version(D_BetterC)
        {
            assert(0, getExceptionMessage(errorMessageBuffer[], msg, ExceptionFlag.invalidOperation, file, line));
        }
        else
        {
            version(decNogcException)
                throw (cast()eInvalidOperationException).set(msg, file, line);
            else
                throw new InvalidOperationException(getExceptionMessage(msg, ExceptionFlag.invalidOperation), file, line);
        }
    }

    static noreturn throwOverflowError(string msg = null, string file = __FILE__, uint line = __LINE__) pure @trusted
    {
        version(D_BetterC)
        {
            assert(0, getExceptionMessage(errorMessageBuffer[], msg, ExceptionFlag.overflow, file, line));
        }
        else
        {
            version(decNogcException)
                throw (cast()eOverflowException).set(msg, file, line);
            else
                throw new OverflowException(getExceptionMessage(msg, ExceptionFlag.overflow), file, line);
        }
    }

    static noreturn throwUnderflowError(string msg = null, string file = __FILE__, uint line = __LINE__) pure @trusted
    {
        version(D_BetterC)
        {
            assert(0, getExceptionMessage(errorMessageBuffer[], msg, ExceptionFlag.underflow, file, line));
        }
        else
        {
            version(decNogcException)
                throw (cast()eUnderflowException).set(msg, file, line);
            else
                throw new UnderflowException(getExceptionMessage(msg, ExceptionFlag.underflow), file, line);
        }
    }

    /**
     * Checks if the specified error flags are set. Multiple exceptions may be ORed together.
     * ---
     * DecimalControl.raiseFlags(ExceptionFlags.overflow | ExceptionFlags.underflow | ExceptionFlags.inexact);
     * assert(DecimalControl.hasFlags(ExceptionFlags.overflow | ExceptionFlags.inexact));
     * ---
	 */
    @IEEECompliant("testFlags", 26)
    @IEEECompliant("testSavedFlags", 26)
	static bool hasFlags(const(ExceptionFlags) checkingFlags) @nogc nothrow
	{
		return (_state.flags & checkingFlags) != 0;
	}

	static ExceptionFlags setFlags(const(ExceptionFlags) settingFlags) @nogc nothrow
	{
        if (__ctfe)
        {
            return ExceptionFlags.none;
        }
        else
        {
            const result = _state.flags;
            _state.flags |= (settingFlags & ExceptionFlags.all);
            return result;
        }
	}

    /**
     * Disables specified exceptions. Multiple exceptions may be ORed together.
     * ---
     * DecimalControl.disableExceptions(ExceptionFlags.overflow);
     * auto d = Decimal64.max * Decimal64.max;
     * assert(DecimalControl.overflow);
     * assert(d.isInfinity);
     * ---
	 */
	static ExceptionFlags disableTraps(const(ExceptionFlags) disablingTraps) @nogc nothrow
	{
        const result = _state.traps;
		_state.traps &= ~(disablingTraps & ExceptionFlags.all);
        return result;
	}

    /**
     * Enables specified exceptions. Multiple exceptions may be ORed together.
     * ---
     * DecimalControl.enableTraps(ExceptionFlags.overflow);
     * try
     * {
     *     auto d = Decimal64.max * 2;
     * }
     * catch (OverflowException)
     * {
     * }
     * ---
	 */
	static ExceptionFlags enableTraps(const(ExceptionFlags) enablingTraps) @nogc nothrow
	{
        const result = _state.traps;
		_state.traps |= enablingTraps & ExceptionFlags.all;
        return result;
	}

    /**
     * Extracts current enabled exceptions.
     * ---
     * auto saved = DecimalControl.traps;
     * DecimalControl.disableExceptions(ExceptionFlags.all);
     * DecimalControl.enableExceptions(saved);
     * ---
	 */
	static @property ExceptionFlags traps() @nogc nothrow
	{
        return _state.traps;
	}

    /**
     * Returns the current set flags.
     * ---
     * DecimalControl.restoreFlags(ExceptionFlags.inexact);
     * assert(DecimalControl.flags & ExceptionFlags.inexact);
     * ---
	 */
    @IEEECompliant("saveAllFlags", 26)
	static @property ExceptionFlags flags() @nogc nothrow
	{
        if (__ctfe)
            return ExceptionFlags.none;
        else
            return _state.flags;
	}

    /**
     * IEEE _decimal context errors. By default, no error is set.
     * ---
     * DecimalControl.disableExceptions(ExceptionFlags.all);
     * Decimal32 uninitialized;
     * Decimal64 d = Decimal64.max * 2;
     * Decimal32 e = uninitialized + 5.0;
     * assert(DecimalControl.overflow);
     * assert(DecimalControl.invalidOperation);
     * ---
     */
	static @property bool divisionByZero() @nogc nothrow
	{
		return (_state.flags & ExceptionFlags.divisionByZero) != 0;
	}

    ///ditto
	static @property bool inexact() @nogc nothrow
	{
		return (_state.flags & ExceptionFlags.inexact) != 0;
	}

    ///ditto
	static @property bool invalidOperation() @nogc nothrow
	{
		return (_state.flags & ExceptionFlags.invalidOperation) != 0;
	}

    ///ditto
	static @property bool overflow() @nogc nothrow
	{
		return (_state.flags & ExceptionFlags.overflow) != 0;
	}

    ///ditto
	static @property bool severe() @nogc nothrow
	{
		return (_state.flags & ExceptionFlags.severe) != 0;
	}

    ///ditto
	static @property bool underflow() @nogc nothrow
	{
		return (_state.flags & ExceptionFlags.underflow) != 0;
	}

    ///true if this programming environment conforms to IEEE 754-1985
    @IEEECompliant("is754version1985", 24)
    enum is754version1985 = true;

    ///true if this programming environment conforms to IEEE 754-2008
    @IEEECompliant("is754version2008", 24)
    enum is754version2008 = true;
}

struct DecimalControlFlags
{
	ExceptionFlags flags;
	ExceptionFlags traps;
}

struct IEEECompliant
{
@safe:

    string name;
    int page;
}

int precisionOf(int bytes) @nogc pure
in
{
    assert(bytes == 4 || bytes == 8 || bytes == 16);
}
do
{
    return 9 * bytes * 8 / 32 - 2; //7, 16, 34
}

// real use 10 bytes but has 16 bytes storage
uint floatSizeOf(T)() @nogc pure
if (isFloatingPoint!T)
{
    static if (is(T == real))
        return 10;
    else
        return T.sizeof;
}
