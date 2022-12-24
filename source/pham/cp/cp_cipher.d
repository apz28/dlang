/*
 *
 * License: $(HTTP www.boost.org/LICENSE_1_0.txt, Boost License 1.0).
 * Authors: An Pham
 *
 * Copyright An Pham 2020 - xxxx.
 * Distributed under the Boost Software License, Version 1.0.
 * (See accompanying file LICENSE.txt or copy at http://www.boost.org/LICENSE_1_0.txt)
 *
 */

module pham.cp.cipher;

import std.algorithm.searching : all;
import std.range.primitives : isOutputRange, put;
import std.traits : isUnsigned, Unqual;
import std.typecons : No, Yes;

version (profile) import pham.utl.test : PerfFunction;
import pham.utl.big_integer : BigInteger, defaultParseBigIntegerOptions;
import pham.utl.disposable : DisposableObject, DisposingReason;
import pham.utl.numeric_parser : NumericLexerFlag, NumericLexerOptions;
import pham.utl.object : bytesToHexs;
import pham.utl.utf8 : NoDecodeInputRange, NoDecodeOutputRange, ShortStringBuffer,
    ShortStringBufferSize, UTF8CharRange;
import pham.cp.cipher_digest : DigestId;

nothrow @safe:

struct CipherBuffer
{
@safe:

public:
    this(scope const(ubyte)[] values) nothrow pure
    {
        this.data.opAssign(values);
    }

    ~this() nothrow pure
    {
        dispose(DisposingReason.destructor);
    }

    ref typeof(this) opAssign(scope const(ubyte)[] values) nothrow pure return
    {
        data.opAssign(values);
        return this;
    }

    pragma(inline, true)
    ref typeof(this) chopFront(const(size_t) chopLength) nothrow pure return
    {
        data.chopFront(chopLength);
        return this;
    }

    pragma(inline, true)
    ref typeof(this) chopTail(const(size_t) chopLength) nothrow pure return
    {
        data.chopTail(chopLength);
        return this;
    }

    ref typeof(this) clear(bool setShortLength = false, bool disposing = false) nothrow pure return
    {
        data.clear(setShortLength, disposing);
        return this;
    }

    // For security reason, need to clear the secrete information
    void dispose(const(DisposingReason) disposingReason = DisposingReason.dispose) nothrow pure @safe
    {
        data.dispose(disposingReason);
    }

    string toString() const nothrow pure @trusted
    {
        return cast(string)bytesToHexs(data[]);
    }

public:
    private enum overheadSize = ShortStringBufferSize!(ubyte, 1u).sizeof;
    ShortStringBufferSize!(ubyte, 1_024u - overheadSize) data;
    alias data this;
}

struct CipherKey
{
nothrow @safe:

public:
    this(this) pure
    {
        _exponent = _exponent.dup;
        _modulus = _modulus.dup;
        _d = _d.dup;
        _p = _p.dup;
        _q = _q.dup;
        _dp = _dp.dup;
        _dq = _dq.dup;
        _inversedq = _inversedq.dup;
    }

    this(uint keyBitLength, scope const(ubyte)[] key) pure
    {
        this._keyBitLength = keyBitLength;
        this._modulus = key.dup;
    }

    this(uint keyBitLength, scope const(ubyte)[] modulus, scope const(ubyte)[] exponent) pure
    {
        this._keyBitLength = keyBitLength;
        this._modulus = modulus.dup;
        this._exponent = exponent.dup;
    }

    this(uint keyBitLength, scope const(ubyte)[] modulus, scope const(ubyte)[] exponent,
        scope const(ubyte)[] d, scope const(ubyte)[] p, scope const(ubyte)[] q,
        scope const(ubyte)[] dp, scope const(ubyte)[] dq, scope const(ubyte)[] inversedq) pure
    {
        this._keyBitLength = keyBitLength;
        this._modulus = modulus.dup;
        this._exponent = exponent.dup;
        this._d = d.dup;
        this._p = p.dup;
        this._q = q.dup;
        this._dp = dp.dup;
        this._dq = dq.dup;
        this._inversedq = inversedq.dup;
    }

    ~this() pure
    {
        dispose(DisposingReason.destructor);
    }

    static ubyte[] bytesFromBigInteger(scope const(BigInteger) n) pure
    {
        return n.toBytes(No.includeSign);
    }

    static ref Writer bytesFromBigInteger(Writer)(scope const(BigInteger) n, return ref Writer sink) pure
    if (isOutputRange!(Writer, ubyte))
    {
        return n.toBytes(sink, No.includeSign);
    }

    static BigInteger bytesToBigInteger(scope const(ubyte)[] bytes) pure
    {
        return BigInteger(bytes, Yes.unsigned);
    }

    static BigInteger digitsToBigInteger(scope const(char)[] validDigits) pure
    {
        scope (failure) assert(0);

        auto parseOptions = defaultParseBigIntegerOptions!char();
        parseOptions.flags |= NumericLexerFlag.skipInnerBlank;
        return BigInteger(validDigits, parseOptions);
    }

    // For security reason, need to clear the secrete information
    void dispose(const(DisposingReason) disposingReason = DisposingReason.dispose) nothrow pure @safe
    {
        _exponent[] = 0;
        _exponent = null;
        _modulus[] = 0;
        _modulus = null;
        _d[] = 0;
        _d = null;
        _p[] = 0;
        _p = null;
        _q[] = 0;
        _q = null;
        _dp[] = 0;
        _dp = null;
        _dq[] = 0;
        _dq = null;
        _inversedq[] = 0;
        _inversedq = null;
        _keyBitLength = 0;
    }

    static char[] hexDigitsFromBigInteger(scope const(BigInteger) n) pure
    {
        ShortStringBuffer!char buffer;
        return n.toHexString!(ShortStringBuffer!char, char)(buffer, No.includeSign)[].dup;
    }

    static BigInteger hexDigitsToBigInteger(scope const(ubyte)[] validHexDigits) pure
    {
        return hexDigitsToBigInteger(cast(const(char)[])validHexDigits);
    }

    static BigInteger hexDigitsToBigInteger(scope const(char)[] validHexDigits) pure
    {
        scope (failure) assert(0);

        auto parseOptions = defaultParseBigIntegerOptions!char();
        parseOptions.flags |= NumericLexerFlag.skipInnerBlank
            | NumericLexerFlag.hexDigit
            | NumericLexerFlag.unsigned;
        return BigInteger(validHexDigits, parseOptions);
    }

    /**
     * Returns true if if an Integer, x, is a power of two
     */
    static bool isPowerOf2(uint x) @nogc pure
    {
        // While x is even and > 1
        while (((x % 2) == 0) && x > 1)
            x /= 2;
        return x == 1;
    }

    /**
     * Returns true if v is not empty and not all zeros
     */
    static bool isValidKey(scope const(ubyte)[] v) @nogc pure
    {
        // Must not empty
        if (v.length == 0)
            return false;

        // Must not all zero
        return !v.all!((a) => (a == 0));
    }

    @property isValidRSAPublicKey() const @nogc pure
    {
        return isValidKey(_modulus) && isValidKey(_exponent);
    }

    @property const(ubyte)[] exponent() const @nogc pure
    {
        return _exponent;
    }

    //TODO remove
    pragma(inline, true)
    @property bool isRSA() const @nogc pure
    {
        return exponent.length != 0 && modulus.length != 0 && keyByteLength != 0;
    }

    @property const(ubyte)[] key() const @nogc pure
    {
        return _modulus;
    }

    /**
     * Key length in bits
     */
    pragma(inline, true)
    @property uint keyBitLength() const @nogc pure
    {
        return _keyBitLength;
    }

    /**
     * Key length in bytes
     */
    pragma(inline, true)
    @property uint keyByteLength() const @nogc pure
    {
        return (_keyBitLength + 7) / 8;
    }

    @property const(ubyte)[] modulus() const @nogc pure
    {
        return _modulus;
    }

    @property const(ubyte)[] d() const @nogc pure
    {
        return _d;
    }

    @property const(ubyte)[] p() const @nogc pure
    {
        return _p;
    }

    @property const(ubyte)[] q() const @nogc pure
    {
        return _q;
    }

    @property const(ubyte)[] dp() const @nogc pure
    {
        return _dp;
    }

    @property const(ubyte)[] dq() const @nogc pure
    {
        return _dq;
    }

    @property const(ubyte)[] inversedq() const @nogc pure
    {
        return _inversedq;
    }

private:
    ubyte[] _exponent, _modulus;
    ubyte[] _d, _p, _q, _dp, _dq, _inversedq;
    uint _keyBitLength;
}

struct CipherParameters
{
nothrow @safe:

public:
    this(this)
    {
        // Keys will be cleared on destructor,
        // so need to make copy because D Slice is a reference value
        _salt = _salt.dup;
    }

    this(CipherKey privateKey) pure
    {
        this._privateKey = privateKey;
    }

    this(DigestId digestId, CipherKey privateKey, CipherKey publicKey, scope const(ubyte)[] salt) pure
    {
        // Keys will be cleared on destructor,
        // so need to make copy because D Slice is a reference value
        this._digestId = digestId;
        this._privateKey = privateKey;
        this._publicKey = publicKey;
        this._salt = salt.dup;
    }

    ~this() pure
    {
        dispose(DisposingReason.destructor);
    }

    // For security reason, need to clear the secrete information
    void dispose(const(DisposingReason) disposingReason = DisposingReason.dispose) nothrow pure @safe
    {
        _privateKey.dispose(disposingReason);
        _publicKey.dispose(disposingReason);
        _salt[] = 0;
        _salt = null;
    }

    @property DigestId digestId() const @nogc pure
    {
        return _digestId;
    }

    pragma(inline, true)
    @property uint keyBitLength() const @nogc pure
    {
        return _privateKey.keyBitLength;
    }

    @property ref const(CipherKey) privateKey() const @nogc pure return
    {
        return _privateKey;
    }

    @property ref const(CipherKey) publicKey() const @nogc pure return
    {
        return _publicKey;
    }

    @property const(ubyte)[] salt() const @nogc pure
    {
        return _salt;
    }

private:
    DigestId _digestId;
    CipherKey _privateKey;
    CipherKey _publicKey;
    ubyte[] _salt;
}

abstract class Cipher : DisposableObject
{
nothrow @safe:

public:
    ubyte[] decrypt(scope const(ubyte)[] input, return ref ubyte[] output);
    ubyte[] encrypt(scope const(ubyte)[] input, return ref ubyte[] output);

    @property bool isSymantic() const @nogc pure;
    @property string name() const pure;

protected:
    override void doDispose(const(DisposingReason) disposingReason) nothrow @safe
    {
        _parameters.dispose(disposingReason);
    }

protected:
    CipherParameters _parameters;
}

version (none)
struct CipherPrimeCheck
{
import std.algorithm.iteration : each;
import std.algorithm.mutation : swap;
import std.math : abs;

import pham.utl.big_integer;

nothrow @safe:

public:
    version (none)
    static bool isComposit(const(BigInteger) n, const(ushort) testIterations)
    {
        CipherRandomGenerator rnd;

        // find w = 1 + (2^a) * m
        // where m is odd and 2^a is the largest power of 2 dividing w - 1
        BigInteger w = n + 0; // + 0 = avoid converting from const error
        BigInteger wminus1 = w - 1;
        if (wminus1.isZero)
            return true;

        BigInteger m = wminus1;
        size_t a = 0;
        while (!wminus1.peekBit(a++))
        {
            m >>= 1;
            if (m.isZero)
                return true;
        }

        int i = 1;
        while (true)
        {
            // generate random number b: 1 < b < w
            BigInteger b = rnd.nextBigInteger(BigInteger.one, w);

            // z = b^m mod w
            BigInteger z = modPow(b, m, w);

            int j = 0;
            while (true)
            {
                // if j = 0 and z = 1 or z = w - 1
                if ((j == 0 && z.isOne) || z == wminus1)
                {
                    if (i < testIterations) // inc i and start over
                    {
                        i++;
                        break;
                    }
                    else // probably prime
                        return false;
                }
                else
                {
                    if (j > 0 && z.isOne) // not prime
                        return true;
                    else
                    {
                        if (++j < a)
                        {
                            z *= z;
                            z %= w;
                        }
                        else
                            return true; // not prime
                    }
                }
            }
        }
    }

    static bool isProbablyPrime(const(BigInteger) n, const(ushort) testIterations = 20)
    {
        /* TODO
        BigInteger remain;
        foreach (p; smallPrimes)
        {
            // Enough check?
            if (p >= 20_011)
                break;

            BigInteger n2 = p;
            if (n == n2)
                return true;

            const quotient = divRem(n, n2, remain);
            if (!quotient.isZero && !quotient.isOne && remain.isZero)
                return false;
        } */
        return true;
    }
}

struct CipherHelper
{
import std.base64 : Base64Impl;
import std.uni : toUpperChar = toUpper;

@safe:

    alias Base64Padding = Base64Impl!('+', '/', '=');
    alias Base64PaddingNo = Base64Impl!('+', '/', Base64Padding.NoPadding);

    static ubyte[] base64Decode(bool padding)(scope const(char)[] value)
    {
        ubyte[] result;

        NoDecodeInputRange!(value, char) inputRange;
        NoDecodeOutputRange!(result, ubyte) outputRange;

        static if (padding)
        {
            result = new ubyte[Base64Padding.decodeLength(value.length)];
            Base64Padding.decode(inputRange, outputRange);
        }
        else
        {
            result = new ubyte[Base64PaddingNo.decodeLength(value.length)];
            Base64PaddingNo.decode(inputRange, outputRange);
        }

        return result[0..outputRange.offset];
    }

    static char[] base64Encode(bool padding)(scope const(ubyte)[] value) nothrow
    {
        char[] result;

        NoDecodeInputRange!(value, ubyte) inputRange;
        NoDecodeOutputRange!(result, char) outputRange;

        static if (padding)
        {
            result = new char[Base64Padding.encodeLength(value.length)];
            Base64Padding.encode(inputRange, outputRange);
        }
        else
        {
            result = new char[Base64PaddingNo.encodeLength(value.length)];
            Base64PaddingNo.encode(inputRange, outputRange);
        }

        return result[0..outputRange.offset];
    }

    // This list was obtained from http://tools.ietf.org/html/rfc3454#appendix-B.1
    pragma(inline, true)
    static bool isCommonlyMappedToNothing(const(dchar) c) @nogc nothrow pure
    {
        return c == '\u00AD'
            || c == '\u034F'
            || c == '\u1806'
            || c >= '\u180B' && c <= '\u180D'
            || c >= '\u200B' && c <= '\u200D'
            || c == '\u2060'
            || c >= '\uFE00' && c <= '\uFE0F'
            || c == '\uFEFF';
    }

    // This list was obtained from http://tools.ietf.org/html/rfc3454#appendix-C.1.2
    pragma(inline, true)
    static bool isNonAsciiSpace(const(dchar) c) @nogc nothrow pure
    {
        return c == '\u00A0' // NO-BREAK SPACE
            || c == '\u1680' // OGHAM SPACE MARK
            || c == '\u2000' // EN QUAD
            || c == '\u2001' // EM QUAD
            || c == '\u2002' // EN SPACE
            || c == '\u2003' // EM SPACE
            || c == '\u2004' // THREE-PER-EM SPACE
            || c == '\u2005' // FOUR-PER-EM SPACE
            || c == '\u2006' // SIX-PER-EM SPACE
            || c == '\u2007' // FIGURE SPACE
            || c == '\u2008' // PUNCTUATION SPACE
            || c == '\u2009' // THIN SPACE
            || c == '\u200A' // HAIR SPACE
            || c == '\u200B' // ZERO WIDTH SPACE
            || c == '\u202F' // NARROW NO-BREAK SPACE
            || c == '\u205F' // MEDIUM MATHEMATICAL SPACE
            || c == '\u3000';// IDEOGRAPHIC SPACE
    }

    static string saslNormalize(string s) nothrow pure
    {
        auto chars = UTF8CharRange(s);
        while (!chars.empty)
        {
            const c = chars.front;
            if (isNonAsciiSpace(c) || isCommonlyMappedToNothing(c))
                break;
            chars.popFront();
        }
        if (chars.empty)
            return s;

        ShortStringBuffer!char result;
        if (chars.previousPosition)
            result.put(s[0..chars.previousPosition]);

        while (!chars.empty)
        {
            const c = chars.front;
            if (isNonAsciiSpace(c))
                result.put(' ');
            else if (!isCommonlyMappedToNothing(c))
                result.put(s[chars.previousPosition..chars.position]);
            chars.popFront();
        }

        return result.consumeUnique();
    }

    static string srpNormalize(string s) nothrow pure
    {
        s = saslNormalize(s);

        auto chars = UTF8CharRange(s);
        while (!chars.empty)
        {
            const c = chars.front;
            if (c == ',' || c == '=')
                break;
            chars.popFront();
        }
        if (chars.empty)
            return s;

        ShortStringBuffer!char result;
        if (chars.previousPosition)
            result.put(s[0..chars.previousPosition]);

        while (!chars.empty)
        {
            const c = chars.front;
            if (c == ',')
                result.put("=2C");
            else if (c == '=')
                result.put("=3D");
            else
                result.put(s[chars.previousPosition..chars.position]);
            chars.popFront();
        }

        return result.consumeUnique();
    }

    static const(char)[] toUpper(scope const(char)[] s) nothrow pure
    {
        ShortStringBuffer!char result;
        auto chars = UTF8CharRange(s);
        while (!chars.empty)
        {
            result.put(toUpperChar(chars.front));
            chars.popFront();
        }
        return result.consumeUnique();
    }
}

pragma(inline, true);
size_t calculateBufferLength(const(size_t) n, const(size_t) blockLength, const(size_t) paddingSize) @nogc nothrow pure @safe
in
{
    assert(blockLength != 0);
}
do
{
    return ((n + (blockLength - 1) + paddingSize) / blockLength) * blockLength;
}


// Any below codes are private
private:

unittest // CipherParameters.isValidKey
{
    import pham.utl.test;
    traceUnitTest!("pham.cp")("unittest pham.cp.cipher.CipherParameters.isValidKey");

    assert(CipherKey.isValidKey([9]));
    assert(CipherKey.isValidKey([0, 1]));
    assert(CipherKey.isValidKey([1, 0, 2]));

    assert(!CipherKey.isValidKey([]));
    assert(!CipherKey.isValidKey([0]));
    assert(!CipherKey.isValidKey([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]));
}

version (none)
unittest // CipherPrimeCheck.isProbablePrime
{
    import pham.utl.test;
    traceUnitTest!("pham.cp")("unittest pham.cp.cipher.CipherPrimeCheck.isProbablePrime");

    static BigInteger toBigInteger(string digits) nothrow @safe
    {
        scope (failure) assert(0);

        return BigInteger(digits);
    }

    // Sample from https://bigprimes.org

    // 128
    assert(CipherPrimeCheck.isProbablePrime(toBigInteger("227927702452399882050247049241977661937")));
    assert(CipherPrimeCheck.isProbablePrime(toBigInteger("258258447720935979066068786310035035733")));

    // 256
    assert(CipherPrimeCheck.isProbablePrime(toBigInteger("90908275246293971318411601589072934800224357707103841825589604124184887628503")));
    assert(CipherPrimeCheck.isProbablePrime(toBigInteger("70053312038416596009431654879034713924003903759831063485942503361201374364619")));

    // 512
    assert(CipherPrimeCheck.isProbablePrime(toBigInteger("10881213638512312646171143956318323019085570089755426028184351904113537782683160877295731135004570090490877376262095574492327663247260835568636042710653691")));
    assert(CipherPrimeCheck.isProbablePrime(toBigInteger("9593623114697012589632910958447639342611244267486392264238581558917736417642788636453179451623212726955557513152076579890685381288008077334324266512018187")));

    // 768
    assert(CipherPrimeCheck.isProbablePrime(toBigInteger("1359423791757156914198120491876634582370874831011078061915422158784024172727180420928760430372836033642653622338104146557012232554143501871861884062614562985441211325583178750787855382346273588013018295869359664283130567382547523479")));
    assert(CipherPrimeCheck.isProbablePrime(toBigInteger("1501008841506008035696993562184617608094638427946208559416483787795859572274469887080441994823817023872977735517263272824561732855709475789138963102292207507589778529881355881195860190009712319593494546526634045998868768062451614059")));

    // 1024
    //assert(CipherPrimeCheck.isProbablePrime(toBigInteger("")));
    //assert(CipherPrimeCheck.isProbablePrime(toBigInteger("")));
}

unittest // CipherHelper.base64Decode & base64Encode
{
    import std.string : representation;
    import pham.utl.test;
    traceUnitTest!("pham.cp")("unittest pham.cp.cipher.CipherHelper.base64Decode & base64Encode");

    scope (failure) assert(0);

    assert(CipherHelper.base64Decode!true("VGhvdSBzaGFsdCBuZXZlciBjb250aW51ZSBhZnRlciBhc3NlcnRpbmcgbnVsbA==") == "Thou shalt never continue after asserting null".representation());
    assert(CipherHelper.base64Encode!true("Thou shalt never continue after asserting null".representation()) == "VGhvdSBzaGFsdCBuZXZlciBjb250aW51ZSBhZnRlciBhc3NlcnRpbmcgbnVsbA==");

    assert(CipherHelper.base64Decode!false("Zm9v") == "foo".representation());
    assert(CipherHelper.base64Encode!false("foo".representation()) == "Zm9v");
}
