/*
 *
 * License: $(HTTP www.boost.org/LICENSE_1_0.txt, Boost License 1.0).
 * Authors: An Pham
 *
 * Copyright An Pham 2022 - xxxx.
 * Distributed under the Boost Software License, Version 1.0.
 * (See accompanying file LICENSE.txt or copy at http://www.boost.org/LICENSE_1_0.txt)
 *
 */

module pham.cp.cp_codec_asn1;

import std.string : representation;
import std.traits : isIntegral, isSigned, Unqual;

import pham.dtm.dtm_date : Date, DateTime;
import pham.dtm.dtm_date_time_parse : DateTimeParser, DateTimePattern, tryParse;
import pham.dtm.dtm_tick : DateTimeZoneKind;
import pham.dtm.dtm_time : Time;
import pham.utl.utl_array_static : ShortStringBuffer;
import pham.utl.utl_big_integer : BigInteger;
import pham.utl.utl_convert : toString;
import pham.utl.utl_result : cmp, ResultStatus;
import pham.var.var_variant : Variant;
import pham.cp.cp_cipher_buffer : CipherBuffer;

nothrow @safe:

enum emptyError = 1;
enum truncatedError = 2;
enum invalidError = 3;

/**
 * ASN.1 Class Tags
 */
enum ASN1Class : ubyte
{
	universal       = 0,
	application     = 1,
	contextSpecific = 2,
	private_        = 3,
    eoc             = 4,
    undefined       = ubyte.max, // Only used while decoding
}

/**
 * ASN.1 Type Tags
 */
enum ASN1Tag : ubyte
{
    eoc                  = 0x00,
    boolean              = 0x01,
    integer              = 0x02,
    bitString            = 0x03,
    octetString          = 0x04,
    null_                = 0x05,
    oid                  = 0x06,
    //float_               = 0x09,
    enum_                = 0x0A,
    time                 = 0x0E,
    utf8String           = 0x0C,
    sequence             = 0x10,
    set                  = 0x11,
    numericString        = 0x12,
    printableString      = 0x13,
    t61String            = 0x14,
    iA5String            = 0x16,
    utcTime              = 0x17,
    generalizedTime      = 0x18,
    //visibleString        = 0x1A,
    generalString        = 0x1B,
    bmpString            = 0x1E,
    date                 = 0x1F,
    //dateTime             = 0x21,
    //duration             = 0x22,
    undefined            = ubyte.max, // Only used while decoding
}

ResultStatus ASN1IsBMPString(scope const(ubyte)[] x) @nogc pure
{
    import pham.utl.utl_utf8 : nextUTF16Char;

    if (x.length == 0)
        return ResultStatus.ok();
    else if (x.length % 2 != 0)
        return ResultStatus.error(truncatedError, "BMP-string is truncated");

    auto x2 = cast(const(ushort)[])x;

    // Truncate trailing zero
    while (x2.length && x2[$ - 1] == 0)
        x2 = x2[0..$ - 1];

    size_t p;
    dchar cCode;
    ubyte cCount;
    while (p < x2.length)
    {
        if (!nextUTF16Char(x2, p, cCode, cCount))
            return p + cCount > x2.length
                ? ResultStatus.error(truncatedError, "BMP-string is truncated")
                : ResultStatus.error(invalidError, "Invalid BMP-string");
        p += cCount;
    }
    return ResultStatus.ok();
}

pragma(inline, true)
bool ASN1IsIA5Char(const(ubyte) x) @nogc pure
{
    return x < 128;
}

ResultStatus ASN1IsIA5String(scope const(ubyte)[] x) @nogc pure
{
    foreach (b; x)
    {
        if (!ASN1IsIA5Char(b))
            return ResultStatus.error(invalidError, "Invalid IA5-string");
    }
    return ResultStatus.ok();
}

pragma(inline, true)
bool ASN1IsNumericChar(const(ubyte) x) @nogc pure
{
    return ('0' <= x && x <= '9') || x == ' ';
}

ResultStatus ASN1IsNumericString(scope const(ubyte)[] x) @nogc pure
{
    foreach (b; x)
    {
        if (!ASN1IsNumericChar(b))
            return ResultStatus.error(invalidError, "Invalid Numeric-string");
    }
    return ResultStatus.ok();
}

ResultStatus ASN1IsOctetString(scope const(ubyte)[] x) @nogc pure
{
    if (x.length % 2 != 0)
        return ResultStatus.error(truncatedError, "Octet-string is truncated");
    else
        return ResultStatus.ok();
}

pragma(inline, true)
bool ASN1IsPrintableChar(const(ubyte) x) @nogc pure
{
	return ('a' <= x && x <= 'z')
        || ('A' <= x && x <= 'Z')
        || ('0' <= x && x <= '9')
        || ('\'' <= x && x <= ')')
        || ('+' <= x && x <= '/')
        || x == ' '
        || x == ':'
        || x == '='
        || x == '?'
		// This is technically not allowed in a PrintableString.
		// However, x509 certificates with wildcard strings don't
		// always use the correct string type so we permit it.
        || x == '*'
		// This is not technically allowed either. However, not
		// only is it relatively common, but there are also a
		// handful of CA certificates that contain it. At least
		// one of which will not expire until 2027.
		|| x == '&';
}

ResultStatus ASN1IsPrintableString(scope const(ubyte)[] x) @nogc pure
{
    foreach (b; x)
    {
        if (!ASN1IsPrintableChar(b))
            return ResultStatus.error(invalidError, "Invalid Printable-string");
    }
    return ResultStatus.ok();
}

ResultStatus ASN1IsUTF8String(scope const(ubyte)[] x) @nogc pure
{
    import pham.utl.utl_utf8 : nextUTF8Char, UTF8Iterator;

    UTF8Iterator interator;
    size_t p;
    while (p < x.length)
    {
        if (!nextUTF8Char(x, p, interator.code, interator.count))
            return p + interator.count > x.length
                ? ResultStatus.error(truncatedError, "UTF8-string is truncated")
                : ResultStatus.error(invalidError, "Invalid UTF8-string");
        p += interator.count;
    }
    return ResultStatus.ok();
}

struct ASN1BitString
{
nothrow @safe:

public:
    this(ubyte[] bytes) pure
    {
        this(bytes, calBitLength(bytes));
    }

    this(ubyte[] bytes, size_t bitLength) pure
    in
    {
        assert(bitLength <= bytes.length * 8);
    }
    do
    {
        this._bitBytes = bytes;
        this._bitLength = bitLength;
    }

    int opCmp(scope const(ASN1BitString) rhs) const @nogc pure
    {
        const rhsBytes = rhs._bitBytes;
        const cmpLen = rhsBytes.length > _bitBytes.length ? _bitBytes.length : rhsBytes.length;
        foreach (i; 0..cmpLen)
        {
            const c = cmp(_bitBytes[i], rhsBytes[i]);
            if (c != 0)
                return c;
        }

        const c = cmp(_bitBytes.length, rhsBytes.length);
        return c != 0 ? c : cmp(_bitLength, rhs._bitLength);
    }

    bool opEquals(scope const(ASN1BitString) rhs) const @nogc pure
    {
        return opCmp(rhs) == 0;
    }

    /**
     * Returns the bit at the given index.
     * If the index is out of range it returns false.
     */
    bool opIndex(size_t index) const @nogc pure
    {
        if (index > _bitLength)
            return false;

        const e = index / 8;
        const b = (8 - 1) - (index % 8);
        return (_bitBytes[e] >> b) & 1u;
    }

    // Returns the bit-length of bitString by considering the
    // most-significant bit in a byte to be the "first" bit. This convention
    // matches ASN.1, but differs from almost everything else.
    static size_t calBitLength(scope const(ubyte)[] x) @nogc pure
    {
	    size_t result = x.length * 8;
        foreach (i; 0..x.length)
	    {
		    const b = x[x.length - i - 1];
		    foreach (bit; 0..8)
            {
			    if (((b >> bit) & 1) == 1)
				    return result;
			    result--;
		    }
	    }
	    return 0;
    }

    // RightAlign returns a slice where the padding bits are at the beginning. The
    // slice may share memory with the BitString.
    const(ubyte)[] rightAlign() const pure return scope
    {
	    const shift = 8 - (_bitLength % 8);
	    if (shift == 8 || _bitBytes.length == 0)
		    return _bitBytes;

    	ubyte[] result = new ubyte[](_bitBytes.length);
	    result[0] = _bitBytes[0] >> shift;
	    foreach (i; 1.._bitBytes.length)
        {
		    result[i] = cast(ubyte)(_bitBytes[i - 1] << (8 - shift));
		    result[i] |= _bitBytes[i] >> shift;
	    }
	    return result;
    }

    size_t toHash() const @nogc pure
    {
        size_t result = _bitLength;
        foreach (v; _bitBytes)
        {
            result = hashOf(v, result);
        }
        return result;
    }

    string toString() const pure
    {
        ShortStringBuffer!char buffer;
        buffer.put('[');
        foreach (i; 0..bitLength)
        {
            buffer.put(opIndex(i) ? '1' : '0');
        }
        buffer.put(']');
        return buffer.toString();
    }

    pragma(inline, true)
    @property size_t bitLength() const @nogc pure
    {
        return _bitLength;
    }

    @property const(ubyte)[] bytes() const pure
    {
        return _bitBytes;
    }

private:
    size_t _bitLength;
    ubyte[] _bitBytes;
}

struct ASN1BerDecoder
{
nothrow @safe:

public:
    this(ubyte[] data) pure
    {
        this._data = data;
        //this._error = false;
        //this._errorMessage = null;
        this._currentTag = ASN1Tag.undefined;
        this._currentTagClass = ASN1Class.undefined;
        //this._currentTagId = 0;
        //this._p = this._dataSize = this._headerSize = 0;
        this._empty = data.length == 0;
        if (!this._empty)
        {
            this._currentDataBuffer = new ubyte[](1_000);
            //popFront();
        }
    }

    version(none)
    void popFront() pure
    in
    {
        assert(!empty);
    }
    do
    {
        _currentData = null;
        _dataSize = _headerSize = 0;
        _currentTagClass = ASN1Class.undefined;
        if (_p >= _data.length)
        {
            _currentTag = ASN1Tag.undefined;
            _currentTagId = 0;
            _empty = true;
            return;
        }

        _currentTagId = _data[_p++];
        if (_currentTagId == 0)
        {
            _currentTag = ASN1Tag.eoc;
            _empty = _p >= _data.length;
            const tl = _empty ? 0xFF : _data[_p++];
            if (tl != 0)
            {
                _error = true;
                _errorMessage = "Invalid ASN1 sequence";
            }
            return;
        }

        _currentTag = cast(ASN1Tag)(_currentTagId & 0x1F);
        _currentTagClass = cast(ASN1Class)((_currentTagId >> 6) + ASN1Class.universal);
        const constrained = (_currentTagId & 0x20) != 0;
        if (_currentTag < 0x1F)
        {
            _currentDataBuffer[0] = _currentTag;
            _currentData = _currentDataBuffer[0..1];
        }
        else
        {
            //ReadRepackedBits(lTag, lTagSize, asn1MaxTagSize, asn1RevertTagBytes);
        }
    }

    /**
     * Parses a base-128 encoded int from the given offset in the
     * given byte slice.
     */
    static ResultStatus parseBase128Integer(scope const(ubyte)[] bytes, ref int rResult, out size_t nBytes) pure
    {
        nBytes = 0;
        if (bytes.length == 0)
            return ResultStatus.error(emptyError, "Base-128-integer is truncated");

        long tempResult = 0;
        while (bytes.length)
        {
		    // 5 * 7 bits per byte == 35 bits of data
		    // Thus the representation is either non-minimal or too large for an int32
            if (nBytes == 5)
                return ResultStatus.error(invalidError, "Base-128-integer is too large");

		    tempResult <<= 7;
		    const b = bytes[0];
		    // integers should be minimally encoded, so the leading octet should
		    // never be 0x80
		    if (nBytes == 0 && b == 0x80)
                return ResultStatus.error(invalidError, "Base-128-integer is not minimally encoded");

		    tempResult |= (b & 0x7F);
		    nBytes++;
            bytes = bytes[1..$];

		    if ((b & 0x80) == 0)
            {
			    // Ensure that the returned value fits in an int on all platforms
                // base 128 integer too large?
                if (tempResult > int.max)
                    return ResultStatus.error(invalidError, "Base-128-integer is too large");

                rResult = cast(int)tempResult;
			    return ResultStatus.ok();
		    }
        }

	    // truncated base 128 integer
	    return ResultStatus.error(truncatedError, "Invalid Base-128-integer");
    }

    /// parseBigInteger treats the given bytes as a big-endian
    static ResultStatus parseBigInteger(scope const(ubyte)[] bytes, ref BigInteger result) pure
    {
        import std.typecons : No, Yes;

        auto checkStatus = checkInteger(bytes);
        if (!checkStatus)
            return checkStatus;

        result = BigInteger(bytes, No.unsigned, Yes.bigEndian);
        return ResultStatus.ok();
    }

    static ResultStatus parseBitString(scope const(ubyte)[] bytes, ref ASN1BitString result) pure
    {
        if (bytes.length == 0)
            return ResultStatus.error(emptyError, "Bit-string is truncated");

	    const paddingBits = bytes[0];

        // invalid padding bits?
	    if (paddingBits > 7
            || (paddingBits > 0 && bytes.length == 1)
            || ((bytes[$ - 1] & ((1 << bytes[0]) - 1)) != 0))
            return ResultStatus.error(emptyError, "Invalid padding bits in Bit-string");

        result._bitLength = (bytes.length - 1) * 8 - paddingBits;
	    result._bitBytes = bytes[1..$].dup;

        return ResultStatus.ok();
    }

    static ResultStatus parseBMPString(scope const(ubyte)[] bytes, ref string result) pure
    {
        import pham.utl.utl_utf8 : nextUTF16Char;

        if (bytes.length == 0)
        {
            result = null;
            return ResultStatus.ok();
        }
        else if (bytes.length % 2 != 0)
            return ResultStatus.error(truncatedError, "BMP-string is truncated");

        auto x2 = cast(const(ushort)[])bytes;

        // Truncate trailing zero
        while (x2.length && x2[$ - 1] == 0)
            x2 = x2[0..$ - 1];

        ShortStringBuffer!char tempResult;
        size_t p;
        dchar cCode;
        ubyte cCount;
        while (p < x2.length)
        {
            if (!nextUTF16Char(x2, p, cCode, cCount))
                return p + cCount > x2.length
                    ? ResultStatus.error(truncatedError, "BMP-string is truncated")
                    : ResultStatus.error(truncatedError, "Invalid BMP-string");
            tempResult.put(cCode);
            p += cCount;
        }
        result = tempResult.toString();
        return ResultStatus.ok();
    }

    static ResultStatus parseBoolean(scope const(ubyte)[] bytes, ref bool result) pure
    {
        if (bytes.length != 1)
            return bytes.length == 0
                ? ResultStatus.error(emptyError, "Boolean is truncated")
                : ResultStatus.error(invalidError, "Invalid Boolean");

        const b = bytes[0];
        if (b == 0 || b == 0xFF)
        {
            result = b == 0xFF;
            return ResultStatus.ok();
        }
        else
            return ResultStatus.error(invalidError, "Invalid Boolean");
    }

    /**
     * YYMMDD
     * YYYYMMDD
     */
    static ResultStatus parseDate(scope const(ubyte)[] bytes, ref Date result) @trusted
    {
        // Minimum length - YYMMDD?
        if (bytes.length < 6)
            return ResultStatus.error(bytes.length == 0 ? emptyError : truncatedError, "Date is truncated");

        static DateTimePattern utcPattern(string patternText) nothrow pure @safe
        {
            // Use DateTimePattern.usShortDateTime
            // Any text month format is fine since it only use digits format
            DateTimePattern result = DateTimePattern.usShortDateTime;
            result.defaultKind = DateTimeZoneKind.local;
            result.patternText = patternText;
            return result;
        }

        static immutable DateTimePattern[] patterns = [
            utcPattern("yyyymmdd"),
            utcPattern("yymmdd"),
            ];

        return tryParse!Date(cast(const(char)[])bytes, patterns, result) == DateTimeParser.noError
            ? ResultStatus.ok()
            : ResultStatus.error(invalidError, "Invalid Date");
    }

    /**
     * YYYYMMDDHH[MM[SS[.fff]]] --Local time only
     * YYYYMMDDHH[MM[SS[.fff]]]Z --Universal time (UTC time).
     * YYYYMMDDHH[MM[SS[.fff]]]+-HHMM
     */
    static ResultStatus parseGeneralizedTime(scope const(ubyte)[] bytes, ref DateTime result) @trusted
    {
        // Minimum length - YYYYMMDDHH?
        if (bytes.length < 10)
            return ResultStatus.error(bytes.length == 0 ? emptyError : truncatedError, "Generalized-time is truncated");

        static DateTimePattern utcPattern(string patternText, DateTimeZoneKind kind) nothrow pure @safe
        {
            // Use DateTimePattern.usShortDateTime
            // Any text month format is fine since it only use digits format
            DateTimePattern result = DateTimePattern.usShortDateTime;
            result.defaultKind = kind;
            result.patternText = patternText;
            return result;
        }

        static immutable DateTimePattern[] patterns = [
            // Try these 4 likely formats first
            utcPattern("yyyymmddhhnnss", DateTimeZoneKind.local),
            utcPattern("yyyymmddhhnnssZ", DateTimeZoneKind.utc),
            utcPattern("yyyymmddhhnnss+hhnn", DateTimeZoneKind.utc), utcPattern("yyyymmddhhnnss-hhnn", DateTimeZoneKind.utc),

            utcPattern("yyyymmddhh", DateTimeZoneKind.local),
            utcPattern("yyyymmddhhnn", DateTimeZoneKind.local),
            utcPattern("yyyymmddhhnnss.zzz", DateTimeZoneKind.local),

            utcPattern("yyyymmddhhZ", DateTimeZoneKind.utc),
            utcPattern("yyyymmddhhnnZ", DateTimeZoneKind.utc),
            utcPattern("yyyymmddhhnnss.zzzZ", DateTimeZoneKind.utc),

            utcPattern("yyyymmddhh+hhnn", DateTimeZoneKind.utc), utcPattern("yyyymmddhh-hhnn", DateTimeZoneKind.utc),
            utcPattern("yyyymmddhhnn+hhnn", DateTimeZoneKind.utc), utcPattern("yyyymmddhhnn-hhnn", DateTimeZoneKind.utc),
            utcPattern("yyyymmddhhnnss.zzz+hhnn", DateTimeZoneKind.utc), utcPattern("yyyymmddhhnnss.zzz-hhnn", DateTimeZoneKind.utc),
            ];

        return tryParse!DateTime(cast(const(char)[])bytes, patterns, result) == DateTimeParser.noError
            ? ResultStatus.ok()
            : ResultStatus.error(invalidError, "Invalid Generalized-time");
    }

    static ResultStatus parseIA5String(scope const(ubyte)[] bytes, ref string result) pure
    {
        auto checkStatus = ASN1IsIA5String(bytes);
        if (!checkStatus)
            return checkStatus;

        result = (cast(const(char)[])bytes).idup;
        return ResultStatus.ok();
    }

    /// parseInteger treats the given bytes as a big-endian
    static ResultStatus parseInteger(T)(scope const(ubyte)[] bytes, ref T result) pure
    if (isIntegral!T && (T.sizeof == 8 || T.sizeof == 4))
    {
        // Too large?
        if (bytes.length > T.sizeof)
            return ResultStatus.error(invalidError, "Integer is too large");

        auto checkStatus = checkInteger(bytes);
        if (!checkStatus)
            return checkStatus;

        result = 0;
        foreach (i; 0..bytes.length)
        {
            result = (result << 8) | bytes[i];
        }

        // Shift up and down in order to sign extend the result.
        static if (isSigned!T)
        {
	        result <<= (T.sizeof * 8) - (cast(ubyte)bytes.length * 8);
	        result >>= (T.sizeof * 8) - (cast(ubyte)bytes.length * 8);
        }

        return ResultStatus.ok();
    }

    static ResultStatus parseNumericString(scope const(ubyte)[] bytes, ref string result) pure
    {
        auto checkStatus = ASN1IsNumericString(bytes);
        if (!checkStatus)
            return checkStatus;

        result = (cast(const(char)[])bytes).idup;
        return ResultStatus.ok();
    }

    static ResultStatus parseObjectIdentifier(scope const(ubyte)[] bytes, ref ASN1ObjectIdentifier result) pure
    {
        if (bytes.length == 0)
            return ResultStatus.error(emptyError, "Object-identifier is truncated");

        size_t len = 2;
        size_t fCount;
        int fValue;

        auto checkStatus = parseBase128Integer(bytes, fValue, fCount);
        if (!checkStatus)
            return checkStatus;

        int[] tempValue = new int[](bytes.length + 1);
    	if (fValue < 80)
        {
		    tempValue[0] = fValue / 40;
		    tempValue[1] = fValue % 40;
	    }
        else
        {
		    tempValue[0] = 2;
		    tempValue[1] = fValue - 80;
	    }
        bytes = bytes[fCount..$];

        while (bytes.length)
        {
            auto checkStatus2 = parseBase128Integer(bytes, fValue, fCount);
            if (!checkStatus2)
                return checkStatus2;

            tempValue[len++] = fValue;
            bytes = bytes[fCount..$];
        }

        result._value = tempValue[0..len];
        return ResultStatus.ok();
    }

    static ResultStatus parseOctetString(scope const(ubyte)[] bytes, ref ubyte[] result) pure
    {
        auto checkStatus = ASN1IsOctetString(bytes);
        if (!checkStatus)
            return checkStatus;

        result = bytes.dup;
        return ResultStatus.ok();
    }

    static ResultStatus parsePrintableString(scope const(ubyte)[] bytes, ref string result) pure
    {
        auto checkStatus = ASN1IsPrintableString(bytes);
        if (!checkStatus)
            return checkStatus;

        result = (cast(const(char)[])bytes).idup;
        return ResultStatus.ok();
    }

    static ResultStatus parseSequenceOf(scope const(ubyte)[] bytes, ref ASN1Value[] result)
    {
        if (bytes.length == 0)
        {
            result.length = 0;
            return ResultStatus.ok();
        }

        size_t count, offset, nBytes;
        ASN1TagAndLength tagLength;
        ASN1Tag tag = ASN1Tag.undefined;
        while (offset < bytes.length)
        {
            auto checkTag = parseTagAndLength(bytes[offset..$], tagLength, nBytes);
            if (!checkTag)
                return checkTag;

            count++;
            if (tag == ASN1Tag.undefined)
                tag = cast(ASN1Tag)tagLength.tagId;
            offset += nBytes + tagLength.length;
        }

        result.length = count;
        offset = 0;
        ASN1FieldParameters parameters;
        parameters.tag = tag;
        foreach (i; 0..count)
        {
            auto checkValue = parseValue(bytes[offset..$], parameters, result[i], nBytes);
            if (!checkValue)
                return checkValue;
            offset += nBytes;
        }
        return ResultStatus.ok();
    }

    static ResultStatus parseTagAndLength(scope const(ubyte)[] bytes, ref ASN1TagAndLength result, out size_t nBytes) pure
    {
        nBytes = 0;
        if (bytes.length == 0)
            return ResultStatus.error(emptyError, "Tag & length is truncated");

        ubyte b = bytes[0];
	    result.classId = b >> 6;
	    result.tagId = b & 0x1F;
    	result.isCompound = (b & 0x20) == 0x20;
        result.length = 0;
        nBytes += 1;
        bytes = bytes[1..$];

	    // If the bottom five bits are set, then the tag number is actually base 128
	    // encoded afterwards
	    if (result.tagId == 0x1F)
        {
            size_t newTagSize;
            auto checkTag = parseBase128Integer(bytes, result.tagId, newTagSize);
            if (!checkTag)
            {
                nBytes += newTagSize;
                return checkTag;
            }
            nBytes += newTagSize;
            bytes = bytes[newTagSize..$];

		    // Tags should be encoded in minimal form.
            // non-minimal tag
		    if (result.tagId < 0x1F)
                return ResultStatus.error(invalidError, "Tag is not minimally encoded");
	    }

        // truncated tag or length?
        if (bytes.length == 0)
            return ResultStatus.error(truncatedError, "Tag & length is truncated");

	    b = bytes[0];
        nBytes += 1;
        bytes = bytes[1..$];

        // The length is encoded in the bottom 7 bits?
    	if ((b & 0x80) == 0)
        {
		    result.length = b & 0x7F;
            return ResultStatus.ok();
	    }

		// Bottom 7 bits give the number of length bytes to follow.
		const numBytes = b & 0x7F;

        // indefinite length found (not DER)?
		if (numBytes == 0)
            return ResultStatus.error(invalidError, "Indefinite length");

        foreach (i; 0..numBytes)
		{
            // truncated tag or length?
            if (bytes.length == 0)
                return ResultStatus.error(truncatedError, "Tag & length is truncated");

			b = bytes[0];
            nBytes += 1;
            bytes = bytes[1..$];

			// We can't shift ret.length up without overflowing.
            // length too large
			if (result.length >= 1 << 23)
                return ResultStatus.error(invalidError, "Length is too large");

			result.length <<= 8;
			result.length |= b;

            // DER requires that lengths be minimal.
            // superfluous leading zeros in length?
			if (result.length == 0)
                return ResultStatus.error(invalidError, "Superfluous leading zeros in length");
		}

		// Short lengths must be encoded in short form.
        // non-minimal length?
		if (result.length < 0x80)
			return ResultStatus.error(invalidError, "Length is not minimally encoded");

        return ResultStatus.ok();
	}

    static ResultStatus parseT61String(scope const(ubyte)[] bytes, ref ubyte[] result) pure
    {
        result = bytes.dup;
        return ResultStatus.ok();
    }

    /*
     * hhmm
     * hhmmss
     * hhmmssZ
     * hhmmss+hh[mm]
     * hhmmss-hh[mm]
     */
    static ResultStatus parseTime(scope const(ubyte)[] bytes, ref Time result) @trusted
    {
        // Minimum length - hhmm?
        if (bytes.length < 4)
            return ResultStatus.error(bytes.length == 0 ? emptyError : truncatedError, "Time is truncated");

        static DateTimePattern utcPattern(string patternText, DateTimeZoneKind kind) nothrow pure @safe
        {
            // Use DateTimePattern.usShortDateTime
            // Any text month format is fine since it only use digits format
            DateTimePattern result = DateTimePattern.usShortDateTime;
            result.defaultKind = kind;
            result.patternText = patternText;
            return result;
        }

        static immutable DateTimePattern[] patterns = [
            // Try these three likely formats first
            utcPattern("hhmmss", DateTimeZoneKind.local),
            utcPattern("hhmmssZ", DateTimeZoneKind.utc),

            utcPattern("hhmm", DateTimeZoneKind.local),
            utcPattern("hhmmss+hh", DateTimeZoneKind.utc), utcPattern("hhmmss-hh", DateTimeZoneKind.utc),
            utcPattern("hhmmss+hhnn", DateTimeZoneKind.utc), utcPattern("hhmmss-hhnn", DateTimeZoneKind.utc),
            ];

        return tryParse!Time(cast(const(char)[])bytes, patterns, result) == DateTimeParser.noError
            ? ResultStatus.ok()
            : ResultStatus.error(invalidError, "Invalid Time");
    }

    /*
     * YYMMDDhhmmZ
     * YYMMDDhhmm+hh[mm]
     * YYMMDDhhmm-hh[mm]
     * YYMMDDhhmmssZ
     * YYMMDDhhmmss+hh[mm]
     * YYMMDDhhmmss-hh[mm]
     */
    static ResultStatus parseUTCTime(scope const(ubyte)[] bytes, ref DateTime result) @trusted
    {
        // Minimum length - YYMMDDhhmmZ?
        if (bytes.length < 11)
            return ResultStatus.error(bytes.length == 0 ? emptyError : truncatedError, "UTC-time is truncated");

        static DateTimePattern utcPattern(string patternText) nothrow pure @safe
        {
            // Use DateTimePattern.usShortDateTime
            // Any text month format is fine since it only use digits format
            DateTimePattern result = DateTimePattern.usShortDateTime;
            result.defaultKind = DateTimeZoneKind.utc;
            result.patternText = patternText;
            return result;
        }

        static immutable DateTimePattern[] patterns = [
            // Try these three likely formats first
            utcPattern("yymmddhhnnssZ"),
            utcPattern("yymmddhhnnss+hhnn"), utcPattern("yymmddhhnnss-hhnn"),

            utcPattern("yymmddhhnnZ"),
            utcPattern("yymmddhhnn+hh"), utcPattern("yymmddhhnn-hh"),
            utcPattern("yymmddhhnn+hhnn"), utcPattern("yymmddhhnn-hhnn"),
            utcPattern("yymmddhhnnss+hh"), utcPattern("yymmddhhnnss-hh"),
            ];

        return tryParse!DateTime(cast(const(char)[])bytes, patterns, result) == DateTimeParser.noError
            ? ResultStatus.ok()
            : ResultStatus.error(invalidError, "Invalid UTC-time");
    }

    static ResultStatus parseUTF8String(scope const(ubyte)[] bytes, ref string result) pure
    {
        auto checkStatus = ASN1IsUTF8String(bytes);
        if (!checkStatus)
            return checkStatus;

        result = (cast(const(char)[])bytes).idup;
        return ResultStatus.ok();
    }

    static ResultStatus parseValue(scope const(ubyte)[] bytes, scope const(ASN1FieldParameters) parameters, ref ASN1Value result, out size_t nBytes)
    {
        import pham.utl.utl_enum_set : toName;

        nBytes = 0;
        if (bytes.length == 0)
        {
            if (result.setDefaultValue(parameters))
                return ResultStatus.ok();
            else
                return ResultStatus.error(emptyError, "Field is truncated");
        }

        ASN1TagAndLength tagLength;
        auto checkTagLengh = parseTagAndLength(bytes, tagLength, nBytes);
        if (!checkTagLengh)
        {
            nBytes += tagLength.length;
            return checkTagLengh;
        }

        bytes = bytes[nBytes..$];
        nBytes += tagLength.length;

        final switch (parameters.tag)
        {
            case ASN1Tag.boolean:
                bool bV;
                auto bS = parseBoolean(bytes, bV);
                if (!bS)
                    return bS;
                result.kind = ASN1Tag.boolean;
                result.value = bV;
                return ResultStatus.ok();

            case ASN1Tag.integer:
                long iV;
                auto iS = parseInteger!long(bytes, iV);
                if (!iS)
                    return iS;
                result.kind = ASN1Tag.integer;
                result.setInteger(iV);
                return ResultStatus.ok();

            case ASN1Tag.bitString:
                ASN1BitString bsV;
                auto bsS = parseBitString(bytes, bsV);
                if (!bsS)
                    return bsS;
                result.kind = ASN1Tag.bitString;
                result.value = bsV;
                return ResultStatus.ok();

            case ASN1Tag.octetString:
                ubyte[] ocV;
                auto ocS = parseOctetString(bytes, ocV);
                if (!ocS)
                    return ocS;
                result.kind = ASN1Tag.octetString;
                result.value = ocV;
                return ResultStatus.ok();

            case ASN1Tag.oid:
                ASN1ObjectIdentifier oiV;
                auto oiS = parseObjectIdentifier(bytes, oiV);
                if (!oiS)
                    return oiS;
                result.kind = ASN1Tag.oid;
                result.value = oiV;
                return ResultStatus.ok();

            case ASN1Tag.enum_:
                int eV;
                auto eS = parseInteger!int(bytes, eV);
                if (!eS)
                    return eS;
                result.kind = ASN1Tag.enum_;
                result.value = eV;
                return ResultStatus.ok();

            case ASN1Tag.time:
                Time tV;
                auto tS = parseTime(bytes, tV);
                if (!tS)
                    return tS;
                result.kind = ASN1Tag.time;
                result.value = tV;
                return ResultStatus.ok();

            case ASN1Tag.null_:
                result.reset();
                return ResultStatus.ok();

            case ASN1Tag.utf8String:
                string utf8V;
                auto utf8S = parseUTF8String(bytes, utf8V);
                if (!utf8S)
                    return utf8S;
                result.kind = ASN1Tag.utf8String;
                result.value = utf8V;
                return ResultStatus.ok();

            //TODO case ASNITag.sequence:
            //TODO case ASNITag.set:

            case ASN1Tag.numericString:
                string numV;
                auto numS = parseNumericString(bytes, numV);
                if (!numS)
                    return numS;
                result.kind = ASN1Tag.numericString;
                result.value = numV;
                return ResultStatus.ok();

            case ASN1Tag.printableString:
                string prtV;
                auto prtS = parsePrintableString(bytes, prtV);
                if (!prtS)
                    return prtS;
                result.kind = ASN1Tag.printableString;
                result.value = prtV;
                return ResultStatus.ok();

            case ASN1Tag.t61String:
                ubyte[] t61V;
                auto t61S = parseT61String(bytes, t61V);
                if (!t61S)
                    return t61S;
                result.kind = ASN1Tag.t61String;
                result.value = t61V;
                return ResultStatus.ok();

            case ASN1Tag.iA5String:
                string ia5V;
                auto ia5S = parseIA5String(bytes, ia5V);
                if (!ia5S)
                    return ia5S;
                result.kind = ASN1Tag.iA5String;
                result.value = ia5V;
                return ResultStatus.ok();

            case ASN1Tag.utcTime:
                DateTime utcV;
                auto utcS = parseUTCTime(bytes, utcV);
                if (!utcS)
                    return utcS;
                result.kind = ASN1Tag.utcTime;
                result.value = utcV;
                return ResultStatus.ok();

            case ASN1Tag.generalizedTime:
                DateTime gtV;
                auto gtS = parseGeneralizedTime(bytes, gtV);
                if (!gtS)
                    return gtS;
                result.kind = ASN1Tag.generalizedTime;
                result.value = gtV;
                return ResultStatus.ok();

            case ASN1Tag.generalString:
                ubyte[] gsV;
                auto gsS = parseT61String(bytes, gsV);
                if (!gsS)
                    return gsS;
                result.kind = ASN1Tag.generalString;
                result.value = gsV;
                return ResultStatus.ok();

            case ASN1Tag.bmpString:
                string bmpV;
                auto bmpS = parseBMPString(bytes, bmpV);
                if (!bmpS)
                    return bmpS;
                result.kind = ASN1Tag.bmpString;
                result.value = bmpV;
                return ResultStatus.ok();

            case ASN1Tag.date:
                Date dtV;
                auto dtS = parseDate(bytes, dtV);
                if (!dtS)
                    return dtS;
                result.kind = ASN1Tag.date;
                result.value = dtV;
                return ResultStatus.ok();

            case ASN1Tag.eoc:
            //case ASN1Tag.float_:
            case ASN1Tag.sequence:
            case ASN1Tag.set:
            //case ASN1Tag.visibleString:
            //case ASN1Tag.dateTime:
            //case ASN1Tag.duration:
            case ASN1Tag.undefined:
                return ResultStatus.error(invalidError, "Field of tag is not supported: " ~ toName!ASN1Tag(parameters.tag));
        }
    }

    pragma(inline, true)
    @property bool empty() const @nogc pure
    {
        return _empty;
    }

    pragma(inline, true)
    @property bool error() const @nogc pure
    {
        return _error;
    }

    pragma(inline, true)
    @property ASN1Tag tag() const @nogc pure
    {
        return _currentTag;
    }

    pragma(inline, true)
    @property ASN1Class tagClass() const @nogc pure
    {
        return _currentTagClass;
    }

    pragma(inline, true)
    @property size_t tagDataSize() const @nogc pure
    {
        return _dataSize;
    }

    pragma(inline, true)
    @property size_t tagHeaderSize() const @nogc pure
    {
        return _headerSize;
    }

    pragma(inline, true)
    @property ubyte tagId() const @nogc pure
    {
        return _currentTagId;
    }

private:
    static ResultStatus checkInteger(scope const(ubyte)[] bytes) @nogc pure
    {
        // Empty?
        if (bytes.length == 0)
            return ResultStatus.error(emptyError, "Integer is empty");
        else if (bytes.length == 1)
            return ResultStatus.ok();
        // Not minimally-encoded?
	    else if ((bytes[0] == 0 && (bytes[1] & 0x80) == 0)
            || (bytes[0] == 0xFF && (bytes[1] & 0x80) == 0x80))
            return ResultStatus.error(invalidError, "Integer is not minimally encoded");
        else
	        return ResultStatus.ok();
    }

    bool readDataSize() @nogc pure
    {
        bool invalidDataSize() @nogc pure
        {
            _empty = _p >= _data.length;
            _error = true;
            _errorMessage = "Invalid ASN1 length";
            return false;
        }

        if (_p >= _data.length)
            return invalidDataSize();

        ubyte f = _data[_p++];
        if (f > 0x80)
        {
            f &= 0x7F; // Count

            if (f > size_t.sizeof)
                return invalidDataSize();

            _headerSize = f + 2;
            _dataSize = 0;
            int shift = 0;
            while (f-- != 0 && _p < _data.length)
            {
                _dataSize = (_dataSize << shift) | _data[_p++];
                shift += 8;
            }
            // Not enough data?
            if (f)
                return invalidDataSize();
        }
        else if (f == 0x80)
        {
            _dataSize = size_t.max; // Undefined length
            _headerSize = 2;
        }
        else
        {
            _dataSize = f;
            _headerSize = 2;
        }

        return true;
    }

public:
    bool revertTagBytes = true;

private:
    string _errorMessage;
    ubyte[] _data, _currentData, _currentDataBuffer;
    size_t _dataSize, _headerSize, _p;
    ASN1Tag _currentTag;
    ASN1Class _currentTagClass;
    ubyte _currentTagId;
    bool _empty, _error;
}

struct ASN1DerEncoder
{
nothrow @safe:

public:
    static void writeBoolean(ref CipherBuffer!ubyte destination, const(bool) x,
        const(ASN1Tag) tag = ASN1Tag.boolean) pure
    {
        destination.put(tag);
        destination.put(x ? 0xff : 0x00);
    }

    static void writeGeneralizedTime(ref CipherBuffer!ubyte destination, const(DateTime) x,
        const(ASN1Tag) tag = ASN1Tag.generalizedTime) pure
    {
        int y, m, d, h, n, s;
        x.getDate(y, m, d);
        x.getTime(h, n, s);

        ShortStringBuffer!char buffer;
        toString(buffer, y, 4);
        toString(buffer, m, 2);
        toString(buffer, d, 2);
        toString(buffer, h, 2);
        toString(buffer, n, 2);
        toString(buffer, s, 2);
        buffer.put('Z');

        writeTagValue(destination, tag, buffer[].representation);
    }

    static void writeInteger(T)(ref CipherBuffer!ubyte destination, const(T) x,
        const(ASN1Tag) tag = ASN1Tag.integer) pure
    if (isIntegral!T)
    {
        destination.put(tag);
	    const n = x.lengthInteger();
	    foreach (j; 0..n)
		    destination.put(cast(ubyte)(x >> ((n - 1 - j) * 8)));
    }

    static void writeNull(ref CipherBuffer!ubyte destination,
        const(ASN1Tag) tag = ASN1Tag.null_) pure
    {
        destination.put(tag);
        destination.put(0x00);
    }

    static void writeOctetString(ref CipherBuffer!ubyte destination, scope const(char)[] x,
        const(ASN1Tag) tag = ASN1Tag.octetString) pure
    {
        writeTagValue(destination, tag, x.representation);
    }

    static void writePrintableString(ref CipherBuffer!ubyte destination, scope const(char)[] x,
        const(ASN1Tag) tag = ASN1Tag.printableString) pure
    {
        writeTagValue(destination, tag, x.representation);
    }

    static void writeSequence(ref CipherBuffer!ubyte destination, scope const(char)[][] x,
        const(ASN1Tag) tag = ASN1Tag.sequence) pure
    {
        writeTagStrings(destination, tag, x);
    }

    static void writeSet(ref CipherBuffer!ubyte destination, scope const(char)[][] x,
        const(ASN1Tag) tag = ASN1Tag.set) pure
    {
        writeTagStrings(destination, tag, x);
    }

    static void writeTagStrings(ref CipherBuffer!ubyte destination, const(ASN1Tag) tag, scope const(char)[][] xs) pure
    {
        size_t totalLength = 0;
        foreach (x; xs)
            totalLength += x.length;

        destination.put(tag);
        writeLength(destination, totalLength);
        foreach (x; xs)
            destination.put(x.representation);
    }

    static void writeUTFString(ref CipherBuffer!ubyte destination, scope const(char)[] x,
        const(ASN1Tag) tag = ASN1Tag.utf8String) pure
    {
        writeTagValue(destination, tag, x.representation);
    }

    static void writeTagValue(ref CipherBuffer!ubyte destination, const(ASN1Tag) tag, scope const(ubyte)[] x) pure
    {
        destination.put(tag);
        writeLength(destination, x.length);
        destination.put(x);
    }

    version(none)
    static void writeVisibleString(ref CipherBuffer!ubyte destination, scope const(char)[] x,
        const(ASN1Tag) tag = ASN1Tag.visibleString) pure
    {
        destination.put(tag);
        writeLength(destination, x.length + 1);
        destination.put(x.representation);
        destination.put(' ');
    }

private:
    static ubyte lengthBase128Int64(long x) @nogc pure
    {
	    if (x == 0)
		    return 1;

	    ubyte result = 0;
        while (x > 0)
        {
            result++;
            x >>= 7;
        }

	    return result;
    }

    static size_t lengthBitString(scope const(ubyte)[] x) @nogc pure
    {
        return x.length + 1;
    }

    static ubyte lengthInteger(T)(const(T) x) @nogc pure
    if (isIntegral!T)
    {
        Unqual!T ux = x;

	    ubyte result = 1;

	    while (ux > 127)
        {
		    result++;
		    ux >>= 8;
	    }

        static if (isSigned!T)
	    while (ux < -128)
        {
		    result++;
		    ux >>= 8;
	    }

	    return result;
    }

    static ubyte lengthLength(size_t n) @nogc pure
    {
        // Unspecified length
        if (n == size_t.max)
            return 0;

        ubyte result = 1;
	    while (n > 0xFF)
        {
		    result++;
		    n >>= 8;
	    }
        return result;
    }

    static void writeBase128Int64(ref CipherBuffer!ubyte destination, const(long) x)
    {
	    const n = lengthBase128Int64(x);
	    for (int i = n - 1; i >= 0; i--)
        {
		    ubyte b = cast(ubyte)((x >> (i*7)) & 0x7F);
		    if (i != 0)
			    b |= 0x80;
            destination.put(b);
    	}
    }

    static void writeLength(ref CipherBuffer!ubyte destination, const(size_t) n) pure
    {
        if (n >= 0x80)
        {
		    ubyte count = lengthLength(n);
            destination.put(cast(ubyte)(0x80 | count));
            while (count--)
            {
                destination.put(cast(ubyte)(n >> (count * 8)));
            }
        }
        else
            destination.put(cast(ubyte)n);
    }
}

struct ASN1FieldParameters
{
nothrow @safe:

	long* defaultValue;   // a default value for INTEGER typed fields (maybe nil).
	ASN1Tag stringType;   // the string tag to use when marshaling.
	ASN1Tag tag;          // the EXPLICIT or IMPLICIT tag.
	ASN1Tag timeType;     // the time tag to use when marshaling.
	bool application;     // true iff an APPLICATION tag is in use.
	bool explicit;        // true iff an EXPLICIT tag is in use.
	bool omitEmpty;       // true iff this should be omitted if empty when marshaling.
	bool optional;        // true iff the field is OPTIONAL
	bool private_;        // true iff a PRIVATE tag is in use.
	bool set;             // true iff this should be encoded as a SET

    bool canSetDefaultValue() const @nogc pure scope
    {
        return defaultValue == null
            ? false
            : (tag == ASN1Tag.boolean || tag == ASN1Tag.integer || tag == ASN1Tag.enum_);
    }
}

struct ASN1ObjectIdentifier
{
nothrow @safe:

public:
    this(int[] value) pure
    {
        this._value = value;
    }

    int opCmp(scope const(int)[] rhs) const @nogc pure
    {
        const cmpLen = rhs.length > _value.length ? _value.length : rhs.length;
        foreach (i; 0..cmpLen)
        {
            const c = cmp(_value[i], rhs[i]);
            if (c != 0)
                return c;
        }

        return cmp(_value.length, rhs.length);
    }

    int opCmp(scope const(ASN1ObjectIdentifier) rhs) const @nogc pure
    {
        return opCmp(rhs._value);
    }

    bool opEquals(scope const(int)[] rhs) const @nogc pure
    {
        return opCmp(rhs) == 0;
    }

    bool opEquals(scope const(ASN1ObjectIdentifier) rhs) const @nogc pure
    {
        return opCmp(rhs) == 0;
    }

    size_t toHash() const @nogc pure
    {
        size_t result = 0;
        foreach (v; _value)
        {
            result = hashOf(v, result);
        }
        return result;
    }

    string toString() const pure
    {
        if (_value.length == 0)
            return null;

        ShortStringBuffer!char buffer;
        .toString(buffer, _value[0]);
        foreach (i; 1.._value.length)
        {
            buffer.put('.');
            .toString(buffer, _value[i]);
        }
        return buffer.toString();
    }

    @property const(int)[] value() const @nogc pure
    {
        return _value;
    }

private:
    int[] _value;
}

struct ASN1OIdInfo
{
nothrow @safe:

    string id; // Same as ASN1ObjectIdentifier in string form
    string name;
}

class ASN1OId
{
nothrow @safe:

public:
    this(string id, string name) pure
    {
        this.value.id = id;
        this.value.name = name;
    }

    this(ASN1OIdInfo value) pure
    {
        this.value = value;
    }

    static ASN1OId add(string id, string name) @trusted
    in
    {
        assert(id.length != 0);
        assert(name.length != 0);
    }
    do
    {
        auto oid = new ASN1OId(id, name);
        _idMaps[oid.id] = oid;
        _nameMaps[oid.name] = oid;
        return oid;
    }

    static ASN1OId idOf(scope const(char)[] id) @trusted
    {
        if (auto e = id in _idMaps)
            return *e;
        else
            return null;
    }

    static ASN1OId nameOf(scope const(char)[] name) @trusted
    {
        if (auto e = name in _nameMaps)
            return *e;
        else
            return null;
    }

    @property string id() const pure @nogc
    {
        return value.id;
    }

    @property string name() const pure @nogc
    {
        return value.name;
    }

private:
    static void initializeDefaults()
    {
        /* Public key types */
        add("2.5.8.1.1", "RSA"); // RSA alternate
        add("1.2.840.10040.4.1", "DSA");
        add("1.2.840.10046.2.1", "DH");
        add("1.3.6.1.4.1.3029.1.2.1", "ElGamal");
        add("1.3.6.1.4.1.25258.1.1", "RW");
        add("1.3.6.1.4.1.25258.1.2", "NR");
		add("1.3.6.1.4.1.25258.1.4", "Curve25519");
		add("1.3.6.1.4.1.11591.15.1", "Curve25519");

        // X9.62 ecPublicKey, valid for ECDSA and ECDH (RFC 3279 sec 2.3.5)
        add("1.2.840.10045.2.1", "ECDSA");

        /*
        * This is an OID defined for ECDH keys though rarely used for such.
        * In this configuration it is accepted on decoding, but not used for
        * encoding. You can enable it for encoding by calling
        * ASN1OId.add("ECDH", "1.3.132.1.12")
        * from your application code.
        */
        add("1.3.132.1.12", "ECDH");

        add("1.2.643.2.2.19", "GOST-34.10"); // RFC 4491

        /* Ciphers */
        add("1.3.14.3.2.7", "DES/CBC");
        add("1.2.840.113549.3.7", "TripleDES/CBC");
        add("1.2.840.113549.3.2", "RC2/CBC");
        add("1.2.840.113533.7.66.10", "CAST-128/CBC");
        add("2.16.840.1.101.3.4.1.2", "AES-128/CBC");
        add("2.16.840.1.101.3.4.1.22", "AES-192/CBC");
        add("2.16.840.1.101.3.4.1.42", "AES-256/CBC");
        add("1.2.410.200004.1.4", "SEED/CBC"); // RFC 4010
        add("1.3.6.1.4.1.25258.3.1", "Serpent/CBC");
		add("1.3.6.1.4.1.25258.3.2", "Threefish-512/CBC");
		add("1.3.6.1.4.1.25258.3.3", "Twofish/CBC");
		add("2.16.840.1.101.3.4.1.6", "AES-128/GCM");
		add("2.16.840.1.101.3.4.1.26", "AES-192/GCM");
		add("2.16.840.1.101.3.4.1.46", "AES-256/GCM");
		add("1.3.6.1.4.1.25258.3.101", "Serpent/GCM");
		add("1.3.6.1.4.1.25258.3.102", "Twofish/GCM");
		add("1.3.6.1.4.1.25258.3.2.1", "AES-128/OCB");
		add("1.3.6.1.4.1.25258.3.2.2", "AES-192/OCB");
		add("1.3.6.1.4.1.25258.3.2.3", "AES-256/OCB");
		add("1.3.6.1.4.1.25258.3.2.4", "Serpent/OCB");
		add("1.3.6.1.4.1.25258.3.2.5", "Twofish/OCB");

		/* Hash Functions */
        add("1.2.840.113549.2.5", "MD5");
        add("1.3.6.1.4.1.11591.12.2", "Tiger(24,3)");

        add("1.3.14.3.2.26", "SHA-160");
        add("2.16.840.1.101.3.4.2.4", "SHA-224");
        add("2.16.840.1.101.3.4.2.1", "SHA-256");
        add("2.16.840.1.101.3.4.2.2", "SHA-384");
        add("2.16.840.1.101.3.4.2.3", "SHA-512");

        /* MACs */
        add("1.2.840.113549.2.7", "HMAC(SHA-160)");
        add("1.2.840.113549.2.8", "HMAC(SHA-224)");
        add("1.2.840.113549.2.9", "HMAC(SHA-256)");
        add("1.2.840.113549.2.10", "HMAC(SHA-384)");
        add("1.2.840.113549.2.11", "HMAC(SHA-512)");

        /* Key Wrap */
        add("1.2.840.113549.1.9.16.3.6", "KeyWrap.TripleDES");
        add("1.2.840.113549.1.9.16.3.7", "KeyWrap.RC2");
        add("1.2.840.113533.7.66.15", "KeyWrap.CAST-128");
        add("2.16.840.1.101.3.4.1.5", "KeyWrap.AES-128");
        add("2.16.840.1.101.3.4.1.25", "KeyWrap.AES-192");
        add("2.16.840.1.101.3.4.1.45", "KeyWrap.AES-256");

        /* Compression */
        add("1.2.840.113549.1.9.16.3.8", "Compression.Zlib");

        /* Public key signature schemes */
        add("1.2.840.113549.1.1.1", "RSA/EME-PKCS1-v1_5");
        add("1.2.840.113549.1.1.2", "RSA/EMSA3(MD2)");
        add("1.2.840.113549.1.1.4", "RSA/EMSA3(MD5)");
        add("1.2.840.113549.1.1.5", "RSA/EMSA3(SHA-160)");
        add("1.2.840.113549.1.1.11", "RSA/EMSA3(SHA-256)");
        add("1.2.840.113549.1.1.12", "RSA/EMSA3(SHA-384)");
        add("1.2.840.113549.1.1.13", "RSA/EMSA3(SHA-512)");
        add("1.3.36.3.3.1.2", "RSA/EMSA3(RIPEMD-160)");

        add("1.2.840.10040.4.3", "DSA/EMSA1(SHA-160)");
        add("2.16.840.1.101.3.4.3.1", "DSA/EMSA1(SHA-224)");
        add("2.16.840.1.101.3.4.3.2", "DSA/EMSA1(SHA-256)");

        add("0.4.0.127.0.7.1.1.4.1.1", "ECDSA/EMSA1_BSI(SHA-160)");
        add("0.4.0.127.0.7.1.1.4.1.2", "ECDSA/EMSA1_BSI(SHA-224)");
        add("0.4.0.127.0.7.1.1.4.1.3", "ECDSA/EMSA1_BSI(SHA-256)");
        add("0.4.0.127.0.7.1.1.4.1.4", "ECDSA/EMSA1_BSI(SHA-384)");
        add("0.4.0.127.0.7.1.1.4.1.5", "ECDSA/EMSA1_BSI(SHA-512)");
        add("0.4.0.127.0.7.1.1.4.1.6", "ECDSA/EMSA1_BSI(RIPEMD-160)");

        add("1.2.840.10045.4.1", "ECDSA/EMSA1(SHA-160)");
        add("1.2.840.10045.4.3.1", "ECDSA/EMSA1(SHA-224)");
        add("1.2.840.10045.4.3.2", "ECDSA/EMSA1(SHA-256)");
        add("1.2.840.10045.4.3.3", "ECDSA/EMSA1(SHA-384)");
        add("1.2.840.10045.4.3.4", "ECDSA/EMSA1(SHA-512)");

        add("1.2.643.2.2.3", "GOST-34.10/EMSA1(GOST-R-34.11-94)");

        add("1.3.6.1.4.1.25258.2.1.1.1", "RW/EMSA2(RIPEMD-160)");
        add("1.3.6.1.4.1.25258.2.1.1.2", "RW/EMSA2(SHA-160)");
        add("1.3.6.1.4.1.25258.2.1.1.3", "RW/EMSA2(SHA-224)");
        add("1.3.6.1.4.1.25258.2.1.1.4", "RW/EMSA2(SHA-256)");
        add("1.3.6.1.4.1.25258.2.1.1.5", "RW/EMSA2(SHA-384)");
        add("1.3.6.1.4.1.25258.2.1.1.6", "RW/EMSA2(SHA-512)");

        add("1.3.6.1.4.1.25258.2.1.2.1", "RW/EMSA4(RIPEMD-160)");
        add("1.3.6.1.4.1.25258.2.1.2.2", "RW/EMSA4(SHA-160)");
        add("1.3.6.1.4.1.25258.2.1.2.3", "RW/EMSA4(SHA-224)");
        add("1.3.6.1.4.1.25258.2.1.2.4", "RW/EMSA4(SHA-256)");
        add("1.3.6.1.4.1.25258.2.1.2.5", "RW/EMSA4(SHA-384)");
        add("1.3.6.1.4.1.25258.2.1.2.6", "RW/EMSA4(SHA-512)");

        add("1.3.6.1.4.1.25258.2.2.1.1", "NR/EMSA2(RIPEMD-160)");
        add("1.3.6.1.4.1.25258.2.2.1.2", "NR/EMSA2(SHA-160)");
        add("1.3.6.1.4.1.25258.2.2.1.3", "NR/EMSA2(SHA-224)");
        add("1.3.6.1.4.1.25258.2.2.1.4", "NR/EMSA2(SHA-256)");
        add("1.3.6.1.4.1.25258.2.2.1.5", "NR/EMSA2(SHA-384)");
        add("1.3.6.1.4.1.25258.2.2.1.6", "NR/EMSA2(SHA-512)");

        add("2.5.4.3",  "X520.CommonName");
        add("2.5.4.4",  "X520.Surname");
        add("2.5.4.5",  "X520.SerialNumber");
        add("2.5.4.6",  "X520.Country");
        add("2.5.4.7",  "X520.Locality");
        add("2.5.4.8",  "X520.State");
        add("2.5.4.10", "X520.Organization");
        add("2.5.4.11", "X520.OrganizationalUnit");
        add("2.5.4.12", "X520.Title");
        add("2.5.4.42", "X520.GivenName");
        add("2.5.4.43", "X520.Initials");
        add("2.5.4.44", "X520.GenerationalQualifier");
        add("2.5.4.46", "X520.DNQualifier");
        add("2.5.4.65", "X520.Pseudonym");

        add("1.2.840.113549.1.5.12", "PKCS5.PBKDF2");
        add("1.2.840.113549.1.5.13", "PBE-PKCS5v20");

        add("1.2.840.113549.1.9.1", "PKCS9.EmailAddress");
        add("1.2.840.113549.1.9.2", "PKCS9.UnstructuredName");
        add("1.2.840.113549.1.9.3", "PKCS9.ContentType");
        add("1.2.840.113549.1.9.4", "PKCS9.MessageDigest");
        add("1.2.840.113549.1.9.7", "PKCS9.ChallengePassword");
        add("1.2.840.113549.1.9.14", "PKCS9.ExtensionRequest");

        add("1.2.840.113549.1.7.1", "CMS.DataContent");
        add("1.2.840.113549.1.7.2", "CMS.SignedData");
        add("1.2.840.113549.1.7.3", "CMS.EnvelopedData");
        add("1.2.840.113549.1.7.5", "CMS.DigestedData");
        add("1.2.840.113549.1.7.6", "CMS.EncryptedData");
        add("1.2.840.113549.1.9.16.1.2", "CMS.AuthenticatedData");
        add("1.2.840.113549.1.9.16.1.9", "CMS.CompressedData");

        add("2.5.29.14", "X509v3.SubjectKeyIdentifier");
        add("2.5.29.15", "X509v3.KeyUsage");
        add("2.5.29.17", "X509v3.SubjectAlternativeName");
        add("2.5.29.18", "X509v3.IssuerAlternativeName");
        add("2.5.29.19", "X509v3.BasicConstraints");
        add("2.5.29.20", "X509v3.CRLNumber");
        add("2.5.29.21", "X509v3.ReasonCode");
        add("2.5.29.23", "X509v3.HoldInstructionCode");
        add("2.5.29.24", "X509v3.InvalidityDate");
        add("2.5.29.31", "X509v3.CRLDistributionPoints");
        add("2.5.29.32", "X509v3.CertificatePolicies");
        add("2.5.29.35", "X509v3.AuthorityKeyIdentifier");
        add("2.5.29.36", "X509v3.PolicyConstraints");
        add("2.5.29.37", "X509v3.ExtendedKeyUsage");
        add("1.3.6.1.5.5.7.1.1", "PKIX.AuthorityInformationAccess");

        add("2.5.29.32.0", "X509v3.AnyPolicy");

        add("1.3.6.1.5.5.7.3.1", "PKIX.ServerAuth");
        add("1.3.6.1.5.5.7.3.2", "PKIX.ClientAuth");
        add("1.3.6.1.5.5.7.3.3", "PKIX.CodeSigning");
        add("1.3.6.1.5.5.7.3.4", "PKIX.EmailProtection");
        add("1.3.6.1.5.5.7.3.5", "PKIX.IPsecEndSystem");
        add("1.3.6.1.5.5.7.3.6", "PKIX.IPsecTunnel");
        add("1.3.6.1.5.5.7.3.7", "PKIX.IPsecUser");
        add("1.3.6.1.5.5.7.3.8", "PKIX.TimeStamping");
        add("1.3.6.1.5.5.7.3.9", "PKIX.OCSPSigning");

        add("1.3.6.1.5.5.7.8.5", "PKIX.XMPPAddr");

        add("1.3.6.1.5.5.7.48.1", "PKIX.OCSP");
        add("1.3.6.1.5.5.7.48.1.1", "PKIX.OCSP.BasicResponse");

        /* ECC domain parameters */
        add("1.3.132.0.6",  "secp112r1");
        add("1.3.132.0.7",  "secp112r2");
        add("1.3.132.0.8",  "secp160r1");
        add("1.3.132.0.9",  "secp160k1");
        add("1.3.132.0.10", "secp256k1");
        add("1.3.132.0.28", "secp128r1");
        add("1.3.132.0.29", "secp128r2");
        add("1.3.132.0.30", "secp160r2");
        add("1.3.132.0.31", "secp192k1");
        add("1.3.132.0.32", "secp224k1");
        add("1.3.132.0.33", "secp224r1");
        add("1.3.132.0.34", "secp384r1");
        add("1.3.132.0.35", "secp521r1");

        add("1.2.840.10045.3.1.1", "secp192r1");
        add("1.2.840.10045.3.1.2", "x962_p192v2");
        add("1.2.840.10045.3.1.3", "x962_p192v3");
        add("1.2.840.10045.3.1.4", "x962_p239v1");
        add("1.2.840.10045.3.1.5", "x962_p239v2");
        add("1.2.840.10045.3.1.6", "x962_p239v3");
        add("1.2.840.10045.3.1.7", "secp256r1");

        add("1.3.36.3.3.2.8.1.1.1", "brainpool160r1");
        add("1.3.36.3.3.2.8.1.1.3", "brainpool192r1");
        add("1.3.36.3.3.2.8.1.1.5", "brainpool224r1");
        add("1.3.36.3.3.2.8.1.1.7", "brainpool256r1");
        add("1.3.36.3.3.2.8.1.1.9", "brainpool320r1");
        add("1.3.36.3.3.2.8.1.1.11", "brainpool384r1");
        add("1.3.36.3.3.2.8.1.1.13", "brainpool512r1");

        add("1.2.643.2.2.35.1", "gost_256A");
        add("1.2.643.2.2.36.0", "gost_256A");

        /* CVC */
        add("0.4.0.127.0.7.3.1.2.1", "CertificateHolderAuthorizationTemplate");
    }

private:
    ASN1OIdInfo value;

    __gshared static ASN1OId[string] _idMaps, _nameMaps;
}

struct ASN1RawValue
{
nothrow @safe:

public:
    static ASN1RawValue nullValue() pure
    {
        return ASN1RawValue(ASN1Class.universal, ASN1Tag.null_, false, null, null);
    }

public:
    int classId;
    int tagId;
	bool isCompound;
    ubyte[] valueBytes;
    ubyte[] fullBytes; // includes the tag and length
}

struct ASN1TagAndLength
{
    int classId, tagId, length;
	bool isCompound;
}

struct ASN1Value
{
    Variant value;
    ASN1Tag kind = ASN1Tag.null_;

    void reset() nothrow
    {
        value.nullify();
        kind = ASN1Tag.null_;
    }

    void setInteger(long iV) nothrow
    {
        if (iV >= int.min && iV <= int.max)
            value = cast(int)iV;
        else
            value = iV;
    }

    bool setDefaultValue(scope const(ASN1FieldParameters) parameters) nothrow
    {
        if (!parameters.optional)
            return false;

        this.kind = kind;
        if (parameters.canSetDefaultValue())
        {
            const dfv = *parameters.defaultValue;
            if (kind == ASN1Tag.boolean)
                value = dfv != 0;
            else if (kind == ASN1Tag.integer)
                setInteger(dfv);
            else if (kind == ASN1Tag.enum_)
                value = cast(int)dfv;
            else
                assert(0);
        }
        return true;
    }
}


private:

import core.attribute : standalone;

@standalone
shared static this() nothrow @trusted
{
    ASN1OId.initializeDefaults();
}

unittest // ASN1BitString.opIndex
{
    import std.conv : to;

    static void test(size_t index, bool expectedValue, int line = __LINE__)
    {
        enum v = ASN1BitString([0x82, 0x40], 16);
        assert(v[index] == expectedValue, "Failed from line# " ~ line.to!string() ~ ": " ~ v[index].to!string() ~ " vs " ~ expectedValue.to!string());
    }

    test(0, true);
    test(1, false);
    test(6, true);
    test(9, true);
    test(17, false);
}

unittest // ASN1BitString.rightAlign
{
    import std.conv : to;
    import pham.utl.utl_convert : bytesToHexs;

    static void test(scope const(ASN1BitString) v, scope const(ubyte)[] expectedValue, int line = __LINE__) @safe
    {
        assert(v.rightAlign() == expectedValue, "Failed from line# " ~ line.to!string() ~ ": " ~ v.rightAlign().bytesToHexs() ~ " vs " ~ expectedValue.bytesToHexs());
    }

    test(ASN1BitString([0x80]), [0x01]);
    test(ASN1BitString([0x80, 0x80], 9), [0x01, 0x01]);
    test(ASN1BitString([], 0), []);
    test(ASN1BitString([0xce], 8), [0xce]);
    test(ASN1BitString([0xce, 0x47], 16), [0xce, 0x47]);
    test(ASN1BitString([0x34, 0x50], 12), [0x03, 0x45]);
}

unittest // ASN1BerDecoder.parseBoolean
{
    import std.conv : to;

    static void test(scope const(ubyte)[] bytes, bool parsedResult, bool expectedValue, int line = __LINE__)
    {
        bool v;
        assert(ASN1BerDecoder.parseBoolean(bytes, v).isOK == parsedResult, "Failed from line: " ~ line.to!string());
        assert(!parsedResult || v == expectedValue, "Failed from line# " ~ line.to!string() ~ ": " ~ v.to!string() ~ " vs " ~ expectedValue.to!string());
    }

    test([0x00], true, false);
    test([0xff], true, true);
    test([0x00, 0x00], false, false);
    test([0xff, 0xff], false, false);
    test([0x01], false, false);
}

unittest // ASN1BerDecoder.parseInteger.int
{
    import std.conv : to;

    static void test(scope const(ubyte)[] bytes, bool parsedResult, int expectedValue, int line = __LINE__)
    {
        int v;
        assert(ASN1BerDecoder.parseInteger!int(bytes, v).isOK == parsedResult, "Failed from line: " ~ line.to!string());
        assert(!parsedResult || v == expectedValue, "Failed from line# " ~ line.to!string() ~ ": " ~ v.to!string() ~ " vs " ~ expectedValue.to!string());
    }

    test([0x00], true, 0);
    test([0x7f], true, 127);
    test([0x00, 0x80], true, 128);
    test([0x01, 0x00], true, 256);
    test([0x80], true, -128);
    test([0xff, 0x7f], true, -129);
    test([0xff], true, -1);
    test([0x80, 0x00, 0x00, 0x00], true, -2_147_483_648);
    test([0x80, 0x00, 0x00, 0x00, 0x00], false, 0);
    test([], false, 0);
    test([0x00, 0x7f], false, 0);
    test([0xff, 0xf0], false, 0);
}

unittest // ASN1BerDecoder.parseInteger.long
{
    import std.conv : to;

    static void test(scope const(ubyte)[] bytes, bool parsedResult, long expectedValue, int line = __LINE__)
    {
        long v;
        assert(ASN1BerDecoder.parseInteger!long(bytes, v).isOK == parsedResult, "Failed from line: " ~ line.to!string());
        assert(!parsedResult || v == expectedValue, "Failed from line# " ~ line.to!string() ~ ": " ~ v.to!string() ~ " vs " ~ expectedValue.to!string());
    }

    test([0x00], true, 0);
    test([0x7f], true, 127);
    test([0x00, 0x80], true, 128);
    test([0x01, 0x00], true, 256);
    test([0x80], true, -128);
    test([0xff, 0x7f], true, -129);
    test([0xff], true, -1);
    test([0x80, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00], true, -9_223_372_036_854_775_808);
    test([0x80, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00], false, 0);
    test([], false, 0);
    test([0x00, 0x7f], false, 0);
    test([0xff, 0xf0], false, 0);
}

unittest // ASN1BerDecoder.parseBigInteger
{
    import std.conv : to;

    static void test(scope const(ubyte)[] bytes, bool parsedResult, long expectedValue, int line = __LINE__) nothrow
    {
        BigInteger v;
        assert(ASN1BerDecoder.parseBigInteger(bytes, v).isOK == parsedResult, "Failed from line: " ~ line.to!string());
        assert(!parsedResult || v == expectedValue, "Failed from line# " ~ line.to!string() ~ ": " ~ v.toString() ~ " vs " ~ expectedValue.to!string());
    }

    test([0xff], true, -1);
    test([0x00], true, 0);
    test([0x01], true, 1);
    test([0x00, 0xff], true, 255);
    test([0xff, 0x00], true, -256);
    test([0x01, 0x00], true, 256);
    test([], false, 0);
    test([0x00, 0x7f], false, 0);
    test([0xff, 0xf0], false, 0);
}

unittest // ASN1BerDecoder.parseBitString
{
    import std.conv : to;

    static void test(scope const(ubyte)[] bytes, bool parsedResult, const(ASN1BitString) expectedValue, int line = __LINE__) @safe
    {
        ASN1BitString v;
        assert(ASN1BerDecoder.parseBitString(bytes, v).isOK == parsedResult, "Failed from line: " ~ line.to!string());
        assert(!parsedResult || v == expectedValue, "Failed from line# " ~ line.to!string() ~ ": " ~ v.toString() ~ " vs " ~ expectedValue.toString());
    }

    test([], false, ASN1BitString.init);
    test([0x00], true, ASN1BitString.init);
    test([0x07, 0x00], true, ASN1BitString([0x00], 1));
    test([0x07, 0x01], false, ASN1BitString.init);
    test([0x07, 0x40], false, ASN1BitString.init);
    test([0x08, 0x00], false, ASN1BitString.init);
}

unittest // ASN1BerDecoder.parseObjectIdentifier
{
    import std.conv : to;

    static void test(scope const(ubyte)[] bytes, bool parsedResult, int[] expectedValue, int line = __LINE__)
    {
        ASN1ObjectIdentifier v;
        assert(ASN1BerDecoder.parseObjectIdentifier(bytes, v).isOK == parsedResult, "Failed from line: " ~ line.to!string());
        assert(!parsedResult || v == expectedValue, "Failed from line# " ~ line.to!string() ~ ": " ~ v.toString() ~ " vs " ~ ASN1ObjectIdentifier(expectedValue).toString());
    }

    test([], false, []);
    test([0x55], true, [2, 5]);
    test([0x55, 0x02], true, [2, 5, 2]);
    test([0x55, 0x02, 0xc0, 0x00], true, [2, 5, 2, 0x2000]);
    test([0x81, 0x34, 0x03], true, [2, 100, 3]);
    test([0x55, 0x02, 0xc0, 0x80, 0x80, 0x80, 0x80], false, []);
}

unittest // ASN1BerDecoder.parseUTCTime
{
    import std.conv : to;
    import pham.dtm.dtm_tick : DateTimeZoneKind;
    import pham.dtm.dtm_date_time_parse : twoDigitYearCenturyWindowDefault;

    static void test(string bytes, bool parsedResult, scope const(DateTime) expectedValue, int line = __LINE__)
    {
        DateTime v;
        assert(ASN1BerDecoder.parseUTCTime(bytes.representation, v).isOK == parsedResult, "Failed from line: " ~ line.to!string());
        assert(!parsedResult || v == expectedValue, "Failed from line# " ~ line.to!string() ~ ": " ~ v.toString() ~ " vs " ~ expectedValue.toString());
    }

    static int year(int twoDigitYear) nothrow
    {
        return DateTime.adjustTwoDigitYear(twoDigitYear, twoDigitYearCenturyWindowDefault);
    }

	test("910506164540+0730", true, DateTime(year(91), 05, 06, 16, 45, 40, 0, DateTimeZoneKind.utc).addBias(1, 07, 30));
	test("910506164540-0700", true, DateTime(year(91), 05, 06, 16, 45, 40, 0, DateTimeZoneKind.utc).addBias(-1, 07, 00));
	test("910506234540Z", true, DateTime(year(91), 05, 06, 23, 45, 40, 0, DateTimeZoneKind.utc));
	test("9105062345Z", true, DateTime(year(91), 05, 06, 23, 45, 0, 0, DateTimeZoneKind.utc));
	test("5105062345Z", true, DateTime(year(51), 05, 06, 23, 45, 0, 0, DateTimeZoneKind.utc));
	test("a10506234540Z", false, DateTime.init);
	test("91a506234540Z", false, DateTime.init);
	test("9105a6234540Z", false, DateTime.init);
	test("910506a34540Z", false, DateTime.init);
	test("910506334a40Z", false, DateTime.init);
	test("91050633444aZ", false, DateTime.init);
	test("910506334461Z", false, DateTime.init);
	test("910506334400Za", false, DateTime.init);
}

unittest // ASN1BerDecoder.parseGeneralizedTime
{
    import std.conv : to;
    import pham.dtm.dtm_tick : DateTimeZoneKind;

    static void test(string bytes, bool parsedResult, scope const(DateTime) expectedValue, int line = __LINE__)
    {
        DateTime v;
        assert(ASN1BerDecoder.parseGeneralizedTime(bytes.representation, v).isOK == parsedResult, "Failed from line: " ~ line.to!string());
        assert(!parsedResult || v == expectedValue, "Failed from line# " ~ line.to!string() ~ ": " ~ v.toString() ~ " vs " ~ expectedValue.toString());
    }

	test("20100102030405Z", true, DateTime(2010, 01, 02, 03, 04, 05, 0, DateTimeZoneKind.utc));
	test("20100102030405+0607", true, DateTime(2010, 01, 02, 03, 04, 05, 0, DateTimeZoneKind.utc).addBias(1, 06, 07));
	test("20100102030405-0607", true, DateTime(2010, 01, 02, 03, 04, 05, 0, DateTimeZoneKind.utc).addBias(-1, 06, 07));
	test("20100102030405", true, DateTime(2010, 01, 02, 03, 04, 05, 0, DateTimeZoneKind.local));
}

unittest // ASN1OId.initializeDefaults, ASN1OId.idOf, ASN1OId.nameOf
{
    auto v = ASN1OId.idOf("2.5.8.1.1");
    assert(v !is null);
    assert(v.name == "RSA");

    v = ASN1OId.idOf("1.3.132.0.10");
    assert(v !is null);
    assert(v.name == "secp256k1");

    v = ASN1OId.idOf("0.4.0.127.0.7.3.1.2.1");
    assert(v !is null);
    assert(v.name == "CertificateHolderAuthorizationTemplate");

    v = ASN1OId.nameOf("RSA");
    assert(v !is null);
    assert(v.id == "2.5.8.1.1");

    v = ASN1OId.nameOf("secp256k1");
    assert(v !is null);
    assert(v.id == "1.3.132.0.10");

    v = ASN1OId.nameOf("CertificateHolderAuthorizationTemplate");
    assert(v !is null);
    assert(v.id == "0.4.0.127.0.7.3.1.2.1");

    v = ASN1OId.idOf("This is invalid id?");
    assert(v is null);
    v = ASN1OId.idOf(null);
    assert(v is null);

    v = ASN1OId.nameOf("This is invalid name?");
    assert(v is null);
    v = ASN1OId.nameOf(null);
    assert(v is null);
}
