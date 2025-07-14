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

module pham.cp.cp_cipher;

import std.range.primitives : isOutputRange, put;
import std.traits : isUnsigned, Unqual;
import std.typecons : No, Yes;

version(profile) import pham.utl.utl_test : PerfFunction;
import pham.utl.utl_array_static : ShortStringBuffer;
import pham.utl.utl_big_integer : BigInteger, defaultParseBigIntegerOptions;
import pham.utl.utl_disposable : DisposableObject, DisposingReason;
import pham.utl.utl_numeric_parser : NumericLexerFlag, NumericLexerOptions;
import pham.utl.utl_utf8 : NoDecodeInputRange, NoDecodeOutputRange, UTF8CharRange;
public import pham.cp.cp_cipher_buffer;
import pham.cp.cp_cipher_digest : DigestId;

nothrow @safe:


struct CipherChaChaKey
{
nothrow @safe:

    enum keySize128 = 16;
    enum keySize256 = 32;
    enum nonceSizeCounter32 = 12;
    enum nonceSizeCounter64 = 8;

public:
    this(uint keyBitLength, scope const(ubyte)[] key, scope const(ubyte)[] nonce, uint counter32,
        int rounds = 0) pure
    {
        this.keyBitLength = keyBitLength;
        this.key = CipherRawKey!ubyte(key);
        this.nonce = CipherRawKey!ubyte(nonce);
        this.rounds = calRounds(rounds);
        this.counter32 = counter32;
        this.counterSize = CounterSize.counter32;
    }
    
    this(uint keyBitLength, CipherRawKey!ubyte key, CipherRawKey!ubyte nonce, uint counter32,
        int rounds = 0) pure
    {
        this.keyBitLength = keyBitLength;
        this.key = key;
        this.nonce = nonce;
        this.rounds = calRounds(rounds);
        this.counter32 = counter32;
        this.counterSize = CounterSize.counter32;
    }
    
    this(uint keyBitLength, scope const(ubyte)[] key, scope const(ubyte)[] nonce, ulong counter64,
        int rounds = 0) pure
    {
        this.keyBitLength = keyBitLength;
        this.key = CipherRawKey!ubyte(key);
        this.nonce = CipherRawKey!ubyte(nonce);
        this.rounds = calRounds(rounds);
        this.counter64 = counter64;
        this.counterSize = CounterSize.counter64;
    }
    
    this(uint keyBitLength, CipherRawKey!ubyte key, CipherRawKey!ubyte nonce, ulong counter64,
        int rounds = 0) pure
    {
        this.keyBitLength = keyBitLength;
        this.key = key;
        this.nonce = nonce;
        this.rounds = calRounds(rounds);
        this.counter64 = counter64;
        this.counterSize = CounterSize.counter64;
    }    
    
    ~this() pure
    {
        dispose(DisposingReason.destructor);
    }

    ref typeof(this) opAssign(ref typeof(this) rhs) pure return
    {
        this.keyBitLength = rhs.keyBitLength;
        this.key = rhs.key;
        this.nonce = rhs.nonce;
        this.rounds = rhs.rounds;
        this.counter64 = rhs.counter64;
        this.counterSize = rhs.counterSize;
        return this;
    }

    static int calRounds(const(int) rounds) @nogc pure
    {
        enum chacha20 = 20;
        return rounds == 0 ? chacha20 : rounds;
    }

    void dispose(const(DisposingReason) disposingReason = DisposingReason.dispose) nothrow pure @safe
    {
        clear();
    }

    bool isValid() const @nogc pure
    {
        return isValidKey() && isValidNonce();
    }
    
    bool isValidKey() const @nogc pure
    {
        return (key.length == keySize128 || key.length == keySize256) && key.isValid();
    }
    
    bool isValidNonce() const @nogc pure
    {
        return ((counterSize == CounterSize.counter32 && nonce.length == nonceSizeCounter32)
                || (counterSize == CounterSize.counter64 && nonce.length == nonceSizeCounter64))
            && nonce.isValid();
    }
    
private:
    void clear() pure
    {
        counter64 = 0;
        rounds = 0;
        keyBitLength = 0;
        key.clear();
        nonce.clear();
    }
    
    void unique() pure
    {
        key.unique();
        nonce.unique();
    }
    
public:
    enum CounterSize : ubyte
    {
        counter32,
        counter64,
    }
    
    uint keyBitLength;
    CipherRawKey!ubyte key, nonce;
    union 
    {
        ulong counter64;
        uint counter32;
    }
    int rounds;
    CounterSize counterSize;
}

struct CipherPrivateRSAKey
{
nothrow @safe:

public:
    this(uint keyBitLength, scope const(ubyte)[] modulus, scope const(ubyte)[] exponent) pure
    {
        this.keyBitLength = keyBitLength;
        this.modulus = CipherRawKey!ubyte(modulus);
        this.exponent = CipherRawKey!ubyte(exponent);
    }
    
    this(uint keyBitLength, CipherRawKey!ubyte modulus, CipherRawKey!ubyte exponent) pure
    {
        this.keyBitLength = keyBitLength;
        this.modulus = modulus;
        this.exponent = exponent;
    }
    
    this(uint keyBitLength, scope const(ubyte)[] modulus, scope const(ubyte)[] exponent,
        scope const(ubyte)[] d, scope const(ubyte)[] p, scope const(ubyte)[] q, scope const(ubyte)[] dp,
        scope const(ubyte)[] dq, scope const(ubyte)[] inversedq) pure
    {
        this.keyBitLength = keyBitLength;
        this.modulus = CipherRawKey!ubyte(modulus);
        this.exponent = CipherRawKey!ubyte(exponent);
        this.d = CipherRawKey!ubyte(d);
        this.p = CipherRawKey!ubyte(p);
        this.q = CipherRawKey!ubyte(q);
        this.dp = CipherRawKey!ubyte(dp);
        this.dq = CipherRawKey!ubyte(dq);
        this.inversedq = CipherRawKey!ubyte(inversedq);
    }
    
    this(uint keyBitLength, CipherRawKey!ubyte modulus, CipherRawKey!ubyte exponent,
        CipherRawKey!ubyte d, CipherRawKey!ubyte p, CipherRawKey!ubyte q, CipherRawKey!ubyte dp,
        CipherRawKey!ubyte dq, CipherRawKey!ubyte inversedq) pure
    {
        this.keyBitLength = keyBitLength;
        this.modulus = modulus;
        this.exponent = exponent;
        this.d = d;
        this.p = p;
        this.q = q;
        this.dp = dp;
        this.dq = dq;
        this.inversedq = inversedq;
    }
    
    ~this() pure
    {
        dispose(DisposingReason.destructor);
    }

    ref typeof(this) opAssign(ref typeof(this) rhs) pure return
    {
        this.keyBitLength = rhs.keyBitLength;
        this.modulus = rhs.modulus;
        this.exponent = rhs.exponent;
        this.d = rhs.d;
        this.p = rhs.p;
        this.q = rhs.q;
        this.dp = rhs.dp;
        this.dq = rhs.dq;
        this.inversedq = rhs.inversedq;
        return this;
    }

    void dispose(const(DisposingReason) disposingReason = DisposingReason.dispose) nothrow pure @safe
    {
        clear();
    }

    bool isValid() const @nogc pure
    {
        return modulus.isValid() && exponent.isValid();
    }

private:
    void clear() pure
    {
        keyBitLength = 0;
        modulus.clear();
        exponent.clear();
        d.clear();
        p.clear();
        q.clear();
        dp.clear();
        dq.clear();
        inversedq.clear();
    }

    void unique() pure
    {
        modulus.unique();
        exponent.unique();
        d.unique();
        p.unique();
        q.unique();
        dp.unique();
        dq.unique();
        inversedq.unique();
    }

public:
    uint keyBitLength;
    CipherRawKey!ubyte modulus, exponent;
    CipherRawKey!ubyte d, p, q, dp, dq, inversedq;
}

struct CipherPublicRSAKey
{
nothrow @safe:

public:
    this(uint keyBitLength, scope const(ubyte)[] modulus, scope const(ubyte)[] exponent) pure
    {
        this.keyBitLength = keyBitLength;
        this.modulus = CipherRawKey!ubyte(modulus);
        this.exponent = CipherRawKey!ubyte(exponent);
    }
    
    this(uint keyBitLength, CipherRawKey!ubyte modulus, CipherRawKey!ubyte exponent) pure
    {
        this.keyBitLength = keyBitLength;
        this.modulus = modulus;
        this.exponent = exponent;
    }
    
    ~this() pure
    {
        dispose(DisposingReason.destructor);
    }

    ref typeof(this) opAssign(ref typeof(this) rhs) pure return
    {
        this.keyBitLength = rhs.keyBitLength;
        this.modulus = rhs.modulus;
        this.exponent = rhs.exponent;
        return this;
    }

    void dispose(const(DisposingReason) disposingReason = DisposingReason.dispose) nothrow pure @safe
    {
        clear();
    }

    bool isValid() const @nogc pure
    {
        return modulus.isValid() && exponent.isValid();
    }

private:
    void clear() pure
    {
        keyBitLength = 0;
        modulus.clear();
        exponent.clear();
    }
    
    void unique() pure
    {
        modulus.unique();
        exponent.unique();
    }

public:
    uint keyBitLength;
    CipherRawKey!ubyte modulus, exponent;
}

struct CipherSimpleKey
{
nothrow @safe:

public:
    this(uint keyBitLength, scope const(ubyte)[] key) pure
    {
        this.keyBitLength = keyBitLength;
        this.key = CipherRawKey!ubyte(key);
    }
    
    this(uint keyBitLength, CipherRawKey!ubyte key) pure
    {
        this.keyBitLength = keyBitLength;
        this.key = key;
    }
    
    ~this() pure
    {
        dispose(DisposingReason.destructor);
    }

    ref typeof(this) opAssign(ref typeof(this) rhs) pure return
    {
        this.keyBitLength = rhs.keyBitLength;
        this.key = rhs.key;
        return this;
    }

    void dispose(const(DisposingReason) disposingReason = DisposingReason.dispose) nothrow pure @safe
    {
        clear();
    }

    bool isValid() const @nogc pure
    {
        return key.isValid();
    }

private:
    void clear() pure
    {
        keyBitLength = 0;
        key.clear();
    }
    
    void unique() pure
    {
        key.unique();
    }

public:
    uint keyBitLength;
    CipherRawKey!ubyte key;
}

struct CipherVectorKey
{
nothrow @safe:

public:
    this(uint keyBitLength, scope const(ubyte)[] key, scope const(ubyte)[] nonce) pure
    {
        this.keyBitLength = keyBitLength;
        this.key = CipherRawKey!ubyte(key);
        this.nonce = CipherRawKey!ubyte(nonce);
    }
    
    this(uint keyBitLength, CipherRawKey!ubyte key, CipherRawKey!ubyte nonce) pure
    {
        this.keyBitLength = keyBitLength;
        this.key = key;
        this.nonce = nonce;
    }
    
    ~this() pure
    {
        dispose(DisposingReason.destructor);
    }

    ref typeof(this) opAssign(ref typeof(this) rhs) pure return
    {
        this.keyBitLength = rhs.keyBitLength;
        this.key = rhs.key;
        this.nonce = rhs.nonce;
        return this;
    }

    void dispose(const(DisposingReason) disposingReason = DisposingReason.dispose) nothrow pure @safe
    {
        clear();
    }

    bool isValid() const @nogc pure
    {
        return key.isValid() && nonce.isValid();
    }

private:
    void clear() pure
    {
        keyBitLength = 0;
        key.clear();
        nonce.clear();
    }
    
    void unique() pure
    {
        key.unique();
        nonce.unique();
    }

public:
    uint keyBitLength;
    CipherRawKey!ubyte key, nonce;
}

enum CipherKeyKind : ubyte
{
    chacha,
    privateRSA,
    publicRSA,
    simpleKey,
    vectorKey,
}

struct CipherKey
{
nothrow @safe:

public:
    this(this) pure
    {
        unique();
    }

    this(CipherSimpleKey key) pure
    {
        this._kind = CipherKeyKind.simpleKey;
        this._keyBitLength = key.keyBitLength;
        this._simple = key;
    }

    this(CipherChaChaKey chacha) pure
    {
        this._kind = CipherKeyKind.chacha;
        this._keyBitLength = chacha.keyBitLength;
        this._chacha = chacha;
    }

    this(CipherPrivateRSAKey privateRSA) pure
    {
        this._kind = CipherKeyKind.privateRSA;
        this._keyBitLength = privateRSA.keyBitLength;
        this._privateRSA = privateRSA;
    }

    this(CipherPublicRSAKey publicRSA) pure
    {
        this._kind = CipherKeyKind.publicRSA;
        this._keyBitLength = publicRSA.keyBitLength;
        this._publicRSA = publicRSA;
    }

    this(CipherVectorKey vector) pure
    {
        this._kind = CipherKeyKind.vectorKey;
        this._keyBitLength = vector.keyBitLength;
        this._vector = vector;
    }

    ~this() pure
    {
        dispose(DisposingReason.destructor);
    }

    ref typeof(this) opAssign(ref CipherSimpleKey rhs) pure return @trusted
    {
        this.clearKey();
        this._kind = CipherKeyKind.simpleKey;
        this._keyBitLength = rhs.keyBitLength;
        this._simple = rhs;
        return this;
    }

    ref typeof(this) opAssign(ref CipherChaChaKey rhs) pure return @trusted
    {
        this.clearKey();
        this._kind = CipherKeyKind.chacha;
        this._keyBitLength = rhs.keyBitLength;
        this._chacha = rhs;
        return this;
    }

    ref typeof(this) opAssign(ref CipherPrivateRSAKey rhs) pure return @trusted
    {
        this.clearKey();
        this._kind = CipherKeyKind.privateRSA;
        this._keyBitLength = rhs.keyBitLength;
        this._privateRSA = rhs;
        return this;
    }

    ref typeof(this) opAssign(ref CipherPublicRSAKey rhs) pure return @trusted
    {
        this.clearKey();
        this._kind = CipherKeyKind.publicRSA;
        this._keyBitLength = rhs.keyBitLength;
        this._publicRSA = rhs;
        return this;
    }

    ref typeof(this) opAssign(ref CipherVectorKey rhs) pure return @trusted
    {
        this.clearKey();
        this._kind = CipherKeyKind.vectorKey;
        this._keyBitLength = rhs.keyBitLength;
        this._vector = rhs;
        return this;
    }
    
    ref typeof(this) opAssign(ref typeof(this) rhs) pure return @trusted
    {
        this.clearKey();
        this._kind = rhs._kind;
        this._keyBitLength = rhs._keyBitLength;
        final switch (rhs._kind) with (CipherKeyKind)
        {
            case chacha:
                this._chacha = rhs._chacha;
                break;
            case privateRSA:
                this._privateRSA = rhs._privateRSA;
                break;
            case publicRSA:
                this._publicRSA = rhs._publicRSA;
                break;
            case simpleKey:
                this._simple = rhs._simple;
                break;
            case vectorKey:
                this._vector = rhs._vector;
                break;
        }
        return this;
    }

    static CipherRawKey!ubyte bytesFromBigInteger(scope const(BigInteger) n) pure
    {
        CipherBuffer!ubyte result;
        return bytesFromBigInteger(result, n).toRawKey();
    }

    static ref Writer bytesFromBigInteger(Writer)(return ref Writer sink, scope const(BigInteger) n) pure
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
        scope (failure) assert(0, "Assume nothrow failed");

        auto parseOptions = defaultParseBigIntegerOptions!char();
        parseOptions.flags |= NumericLexerFlag.skipInnerBlank;
        return BigInteger(validDigits, parseOptions);
    }

    // For security reason, need to clear the secrete information
    void dispose(const(DisposingReason) disposingReason = DisposingReason.dispose) nothrow pure @safe
    {
        _keyBitLength = 0;
        clearKey();
    }

    static CipherRawKey!char hexDigitsFromBigInteger(scope const(BigInteger) n) pure
    {
        CipherBuffer!char result;
        return n.toHexString!(CipherBuffer!char, char)(result, No.includeSign).toRawKey();
    }

    static BigInteger hexDigitsToBigInteger(scope const(ubyte)[] validHexDigits) pure
    {
        return hexDigitsToBigInteger(cast(const(char)[])validHexDigits);
    }

    static BigInteger hexDigitsToBigInteger(scope const(char)[] validHexDigits) pure
    {
        scope (failure) assert(0, "Assume nothrow failed");

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

    bool isValid() const @nogc pure @trusted
    {
        final switch (_kind) with (CipherKeyKind)
        {
            case chacha:
                return _chacha.isValid();
            case privateRSA:
                return _privateRSA.isValid();
            case publicRSA:
                return _publicRSA.isValid();
            case simpleKey:
                return _simple.isValid();
            case vectorKey:
                return _vector.isValid();
        }
    }
    
    @property ref const(CipherChaChaKey) chacha() const pure return @trusted
    {
        static immutable CipherChaChaKey dummy;
        return _kind == CipherKeyKind.chacha ? _chacha : dummy;
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

    @property CipherKeyKind kind() const @nogc pure
    {
        return _kind;
    }

    @property ref const(CipherPrivateRSAKey) privateRSA() const pure return @trusted
    {
        static immutable CipherPrivateRSAKey dummy;
        return _kind == CipherKeyKind.privateRSA ? _privateRSA : dummy;
    }

    @property ref const(CipherPublicRSAKey) publicRSA() const pure return @trusted
    {
        static immutable CipherPublicRSAKey dummy;
        return _kind == CipherKeyKind.publicRSA ? _publicRSA : dummy;
    }

    @property ref const(CipherSimpleKey) simple() const pure return @trusted
    {
        static immutable CipherSimpleKey dummy;
        return _kind == CipherKeyKind.simpleKey ? _simple : dummy;
    }

    @property ref const(CipherVectorKey) vector() const pure return @trusted
    {
        static immutable CipherVectorKey dummy;
        return _kind == CipherKeyKind.vectorKey ? _vector : dummy;
    }

private:
    void clearKey() pure @trusted
    {
        final switch (_kind) with (CipherKeyKind)
        {
            case chacha:
                _chacha.clear();
                break;
            case privateRSA:
                _privateRSA.clear();
                break;
            case publicRSA:
                _publicRSA.clear();
                break;
            case simpleKey:
                _simple.clear();
                break;
            case vectorKey:
                _vector.clear();
                break;
        }
    }
    
    void unique() pure @trusted
    {
        final switch (_kind) with (CipherKeyKind)
        {
            case chacha:
                _chacha.unique();
                break;
            case privateRSA:
                _privateRSA.unique();
                break;
            case publicRSA:
                _publicRSA.unique();
                break;
            case simpleKey:
                _simple.unique();
                break;
            case vectorKey:
                _vector.unique();
                break;
        }
    }

private:
    union
    {
        CipherChaChaKey _chacha;
        CipherPrivateRSAKey _privateRSA;
        CipherPublicRSAKey _publicRSA;
        CipherSimpleKey _simple;
        CipherVectorKey _vector;
    }
    uint _keyBitLength;
    CipherKeyKind _kind;
}

struct CipherParameters
{
nothrow @safe:

public:
    this(CipherKey privateKey) pure
    {
        this._privateKey = privateKey;
    }

    this(DigestId digestId, CipherKey privateKey, CipherKey publicKey, scope const(ubyte)[] salt) pure
    {
        this._digestId = digestId;
        this._privateKey = privateKey;
        this._publicKey = publicKey;
        this._salt = CipherRawKey!ubyte(salt);
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
        _salt.dispose(disposingReason);
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

    @property ref const(CipherRawKey!ubyte) salt() const @nogc pure return
    {
        return _salt;
    }

private:
    DigestId _digestId;
    CipherKey _privateKey;
    CipherKey _publicKey;
    CipherRawKey!ubyte _salt;
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

version(none)
struct CipherPrimeCheck
{
    import std.algorithm.iteration : each;
    import std.algorithm.mutation : swap;
    import std.math : abs;

    import pham.utl.utl_big_integer;

nothrow @safe:

public:
    version(none)
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

    version(none)
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
            result = new ubyte[](Base64Padding.decodeLength(value.length));
            Base64Padding.decode(inputRange, outputRange);
        }
        else
        {
            result = new ubyte[](Base64PaddingNo.decodeLength(value.length));
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
            result = new char[](Base64Padding.encodeLength(value.length));
            Base64Padding.encode(inputRange, outputRange);
        }
        else
        {
            result = new char[](Base64PaddingNo.encodeLength(value.length));
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

version(none)
unittest // CipherPrimeCheck.isProbablePrime
{
    static BigInteger toBigInteger(string digits) nothrow @safe
    {
        scope (failure) assert(0, "Assume nothrow failed");

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

    scope (failure) assert(0, "Assume nothrow failed");

    assert(CipherHelper.base64Decode!true("VGhvdSBzaGFsdCBuZXZlciBjb250aW51ZSBhZnRlciBhc3NlcnRpbmcgbnVsbA==") == "Thou shalt never continue after asserting null".representation());
    assert(CipherHelper.base64Encode!true("Thou shalt never continue after asserting null".representation()) == "VGhvdSBzaGFsdCBuZXZlciBjb250aW51ZSBhZnRlciBhc3NlcnRpbmcgbnVsbA==");

    assert(CipherHelper.base64Decode!false("Zm9v") == "foo".representation());
    assert(CipherHelper.base64Encode!false("foo".representation()) == "Zm9v");
}
