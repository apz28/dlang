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
import pham.utl.object : DisposableObject;
import pham.utl.utf8 : NumericLexerFlag, NumericLexerOptions, ShortStringBuffer, ShortStringBufferSize, UTF8CharRange;
import pham.cp.cipher_digest : DigestId;
//import pham.cp.cipher_prime_number;

nothrow @safe:

alias CipherBuffer = ShortStringBufferSize!(ubyte, 2000);

struct CipherKey
{
nothrow @safe:

public:
    this(this) pure
    {
        _exponent = _exponent.dup;
        _modulus = _modulus.dup;
    }

    this(size_t keyBitLength, scope const(ubyte)[] key) pure
    {
        this._keyBitLength = keyBitLength;
        this._modulus = key.dup;
    }

    this(size_t keyBitLength, scope const(ubyte)[] modulus, scope const(ubyte)[] exponent) pure
    {
        this._keyBitLength = keyBitLength;
        this._modulus = modulus.dup;
        this._exponent = exponent.dup;
    }

    ~this() pure
    {
        dispose(false);
    }

    // For security reason, need to clear the secrete information
    void dispose(bool disposing = true) pure
    {
        _exponent[] = 0;
        _modulus[] = 0;
        _keyBitLength = 0;
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

        NumericLexerOptions!char parseOptions = defaultParseBigIntegerOptions();
        parseOptions.flags |= NumericLexerFlag.skipInnerBlank;
        return BigInteger(validDigits, parseOptions);
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

        NumericLexerOptions!char parseOptions = defaultParseBigIntegerOptions();
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

    @property const(ubyte)[] exponent() const @nogc pure
    {
        return _exponent;
    }

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
    @property size_t keyBitLength() const @nogc pure
    {
        return _keyBitLength;
    }

    /**
     * Key length in bytes
     */
    pragma(inline, true)
    @property size_t keyByteLength() const @nogc pure
    {
        return _keyBitLength / 8;
    }

    @property const(ubyte)[] modulus() const @nogc pure
    {
        return _modulus;
    }

private:
    ubyte[] _exponent;
    ubyte[] _modulus;
    size_t _keyBitLength;
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

    this(DigestId digestId, CipherKey privateKey, CipherKey publicKey, const(ubyte)[] salt) pure
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
        dispose(false);
    }

    // For security reason, need to clear the secrete information
    void dispose(bool disposing = true) pure
    {
        _privateKey.dispose(disposing);
        _publicKey.dispose(disposing);
        _salt[] = 0;
    }

    @property DigestId digestId() const @nogc pure
    {
        return _digestId;
    }

    pragma(inline, true)
    @property size_t keyBitLength() const @nogc pure
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
    override void doDispose(bool disposing)
    {
        _parameters.dispose(disposing);
    }

protected:
    CipherParameters _parameters;
}

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

        struct ValueInputRange
        {
        @nogc nothrow @safe:

            @property bool empty() const pure
            {
                return i >= value.length;
            }

            @property size_t length() const pure
            {
                return value.length - i;
            }

            char front()
            {
                return value[i];
            }

            void popFront() pure
            {
                i++;
            }

            size_t i;
        }

        struct ResultOutputRange
        {
        @nogc nothrow @safe:

            void put(ubyte c)
            {
                result[i++] = c;
            }

            size_t i;
        }

        ValueInputRange inputRange;
        ResultOutputRange outputRange;

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

        return result;
    }

    static char[] base64Encode(bool padding)(scope const(ubyte)[] value) nothrow
    {
        char[] result;

        struct ValueInputRange
        {
        @nogc nothrow @safe:

            @property bool empty() const pure
            {
                return i >= value.length;
            }

            @property size_t length() const pure
            {
                return value.length - i;
            }

            ubyte front()
            {
                return value[i];
            }

            void popFront() pure
            {
                i++;
            }

            size_t i;
        }

        struct ResultOutputRange
        {
        @nogc nothrow @safe:

            void put(char c)
            {
                result[i++] = c;
            }

            size_t i;
        }

        ValueInputRange inputRange;
        ResultOutputRange outputRange;

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

        return result;
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

version (none) //TODO
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
