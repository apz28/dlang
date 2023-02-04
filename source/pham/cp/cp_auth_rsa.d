/*
 *
 * License: $(HTTP www.boost.org/LICENSE_1_0.txt, Boost License 1.0).
 * Authors: An Pham
 *
 * Copyright An Pham 2021 - xxxx.
 * Distributed under the Boost Software License, Version 1.0.
 * (See accompanying file LICENSE.txt or copy at http://www.boost.org/LICENSE_1_0.txt)
 *
 */

module pham.cp.auth_rsa;

import std.typecons : No;

import pham.utl.big_integer : BigInteger, modInverse, modPow;
import pham.utl.disposable : DisposingReason;
import pham.cp.cipher;
import pham.cp.openssl;
import pham.cp.pad;

nothrow @safe:

enum CipherRSAValidState
{
    ok,
    missModulus,
    smallExponent,
    largeExponent,
}

struct CipherRSAPrivateKey
{
public:
    ~this() nothrow pure
    {
        dispose(DisposingReason.destructor);
    }

    // For security reason, need to clear the secrete information
    void dispose(const(DisposingReason) disposingReason = DisposingReason.dispose) nothrow pure @safe
    {
        publicKey.dispose(disposingReason);
        d.dispose(disposingReason);
        foreach (ref prime; primes)
             prime.dispose(disposingReason);
    }

public:
	CipherRSAPublicKey publicKey; // public part.
	BigInteger d;   // private exponent
	BigInteger[] primes; // prime factors of N, has >= 2 elements.
}

struct CipherRSAPublicKey
{
public:
    ~this() nothrow @safe pure
    {
        dispose(DisposingReason.destructor);
    }

    // For security reason, need to clear the secrete information
    void dispose(const(DisposingReason) disposingReason = DisposingReason.dispose) nothrow pure @safe
    {
        N.dispose(disposingReason);
        E = 0;
    }

    @property CipherRSAValidState isValidState() const @nogc pure
    {
        if (N.isZero || N.sign < 0)
            return CipherRSAValidState.missModulus;
        else if (E < 2)
            return CipherRSAValidState.smallExponent;
        else if (E > 1U<<31-1)
            return CipherRSAValidState.largeExponent;
        else
            return CipherRSAValidState.ok;
    }

    pragma(inline, true)
    @property size_t keyByteLength() const @nogc pure
    {
        return (N.bitLength + 7) / 8;
    }

public:
    BigInteger N; // modulus
    int E; // public exponent
}

class CipherRSA : Cipher
{
nothrow @safe:

public:
    alias padPKCS1_5Length = CipherPaddingPKCS1_5.padPKCS1_5Length;

    this(CipherParameters parameters)
    in
    {
        assert(parameters.publicKey.publicRSA.isValid());
    }
    do
    {
        this._parameters = parameters;
        this.publicExponent = CipherKey.bytesToBigInteger(parameters.publicKey.publicRSA.exponent);
        this.publicModulus = CipherKey.bytesToBigInteger(parameters.publicKey.publicRSA.modulus);
        if (parameters.privateKey.publicRSA.isValid())
        {
            this.privateExponent = CipherKey.bytesToBigInteger(parameters.privateKey.publicRSA.exponent);
            this.privateModulus = CipherKey.bytesToBigInteger(parameters.privateKey.publicRSA.modulus);
        }
    }

    final override ubyte[] decrypt(scope const(ubyte)[] input, return ref ubyte[] output)
    {
        const kLen = keyByteLength;
        const bLen = kLen - padPKCS1_5Length;

        // No input or invalid input?
        if (input.length == 0 || (input.length % kLen != 0))
            return [];

         // Calculate the max result length to avoid resize buffer multiple times
        output.length = (input.length / kLen) * bLen;

        size_t i, r;
        CipherBuffer!ubyte iBlock;
        while (i < input.length)
        {
            iBlock.clear().put(input[i..i + kLen]);
            const rLen = decrypt(iBlock).length;
            output[r..r + rLen] = iBlock[];
            r += rLen;
            i += kLen;
        }

        if (r < output.length)
            output = output[0..r];
        return output;
    }

    final ref CipherBuffer!ubyte decrypt(return ref CipherBuffer!ubyte dataBlock)
    in
    {
        assert(dataBlock.length == keyByteLength);
    }
    do
    {
        const dataBlockInt = CipherKey.bytesToBigInteger(dataBlock[]);
        const resultInt = hasPrivateKey
            ? modPow(dataBlockInt, privateExponent, privateModulus)
            : modPow(dataBlockInt, publicExponent, publicModulus);

        tempBlock.clear();
        dataBlock.clear().put(unpadPKCS1_5(CipherKey.bytesFromBigInteger(tempBlock, resultInt))[]);
        return dataBlock;
    }

    final override ubyte[] encrypt(scope const(ubyte)[] input, return ref ubyte[] output)
    {
        if (input.length == 0)
            return null;

        const kLen = keyByteLength;
        const bLen = kLen - padPKCS1_5Length;

        // Calculate the result length to avoid resize buffer multiple times
        size_t rLen = (input.length / bLen) * kLen;
        if (input.length % bLen != 0)
            rLen += kLen;
        output.length = rLen;

        size_t i, r;
        CipherBuffer!ubyte iBlock;
        while (i < input.length)
        {
            const leftLen = input.length - i;
            const n = leftLen > bLen ? bLen : leftLen;
            iBlock.clear().put(input[i..i + n]);
            output[r..r + kLen] = encrypt(iBlock)[];
            r += kLen;
            i += n;
        }

        return output;
    }

    final ref CipherBuffer!ubyte encrypt(return ref CipherBuffer!ubyte dataBlock)
    in
    {
        assert(dataBlock.length < keyByteLength - padPKCS1_5Length);
    }
    do
    {
        const dataBlockInt = CipherKey.bytesToBigInteger(padPKCS1_5(dataBlock)[]);
        const resultInt = hasPrivateKey
            ? modPow(dataBlockInt, privateExponent, privateModulus)
            : modPow(dataBlockInt, publicExponent, publicModulus);

        tempBlock.clear();
        dataBlock.clear().put(CipherKey.bytesFromBigInteger(tempBlock, resultInt)[]);
        const kLen = keyByteLength;
        while (dataBlock.length < kLen)
            dataBlock.put(0);
        return dataBlock;
    }

    static void generateKey(out CipherKey privateKey, out CipherKey publicKey, uint keySize,
        ushort primeTestIterations = 20)
    in
    {
        assert(keySize >= 128 && CipherKey.isPowerOf2(keySize));
    }
    do
    {
        //TODO
        //const nBytes = CipherKey.bytesFromBigInteger(n);
        //privateKey = CipherKey(keySize, nBytes, CipherKey.bytesFromBigInteger(d));
        //publicKey = CipherKey(keySize, nBytes, CipherKey.bytesFromBigInteger(e));
    }

    final ref CipherBuffer!ubyte padPKCS1_5(return ref CipherBuffer!ubyte dataBlock)
    in
    {
        assert(dataBlock.length < keyByteLength - padPKCS1_5Length);
    }
    do
    {
        return pkcs1_5Pad.pad(dataBlock, keyByteLength);
    }

    final ref CipherBuffer!ubyte unpadPKCS1_5(return ref CipherBuffer!ubyte dataBlock) const pure
    {
        return pkcs1_5Pad.unpad(dataBlock, keyByteLength);
    }

    pragma(inline, true)
    @property final bool hasPrivateKey() const pure
    {
        return _parameters.privateKey.publicRSA.isValid();
    }

    @property final size_t keyByteLength() const pure
    {
        return _parameters.publicKey.keyByteLength;
    }

    @property final override bool isSymantic() const pure
    {
        return true;
    }

    @property override string name() const pure
    {
        return "RSA";
    }

protected:
    override void doDispose(const(DisposingReason) disposingReason) nothrow @safe
    {
        privateExponent.dispose(disposingReason);
        privateModulus.dispose(disposingReason);
        publicExponent.dispose(disposingReason);
        publicModulus.dispose(disposingReason);
        tempBlock.dispose(disposingReason);
        super.doDispose(disposingReason);
    }

protected:
    BigInteger privateExponent, privateModulus, publicExponent, publicModulus;

private:
    CipherPaddingPKCS1_5 pkcs1_5Pad;
    CipherBuffer!ubyte tempBlock;
//    CipherRandomGenerator rnd;
}

version (none)
class CipherRSA128 : CipherRSA
{
nothrow @safe:

public:
    this(CipherParameters parameters)
    in
    {
        assert(parameters.publicKey.keyBitLength == 128);
    }
    do
    {
        super(parameters);
    }

    @property final override string name() const pure
    {
        return "RSA128";
    }
}

version (none)
class CipherRSA256 : CipherRSA
{
nothrow @safe:

public:
    this(CipherParameters parameters)
    in
    {
        assert(parameters.publicKey.keyBitLength == 256);
    }
    do
    {
        super(parameters);
    }

    @property final override string name() const pure
    {
        return "RSA256";
    }
}

version (none)
class CipherRSA512 : CipherRSA
{
nothrow @safe:

public:
    this(CipherParameters parameters)
    in
    {
        assert(parameters.publicKey.keyBitLength == 512);
    }
    do
    {
        super(parameters);
    }

    @property final override string name() const pure
    {
        return "RSA512";
    }
}

class CipherRSA1024 : CipherRSA
{
nothrow @safe:

public:
    this(CipherParameters parameters)
    in
    {
        assert(parameters.publicKey.keyBitLength == 1_024);
    }
    do
    {
        super(parameters);
    }

    @property final override string name() const pure
    {
        return "RSA1024";
    }
}

class CipherRSA2048 : CipherRSA
{
nothrow @safe:

public:
    this(CipherParameters parameters)
    in
    {
        assert(parameters.publicKey.keyBitLength == 2_048);
    }
    do
    {
        super(parameters);
    }

    @property final override string name() const pure
    {
        return "RSA2048";
    }
}

class CipherRSA4096 : CipherRSA
{
nothrow @safe:

public:
    this(CipherParameters parameters)
    in
    {
        assert(parameters.publicKey.keyBitLength == 4_096);
    }
    do
    {
        super(parameters);
    }

    @property final override string name() const pure
    {
        return "RSA4096";
    }
}


// Any below codes are private
private:

unittest // CipherRSA.generateKey
{
    import pham.utl.test;
    traceUnitTest!("pham.cp")("unittest pham.cp.auth_rsa.CipherRSA.generateKey");

    CipherKey privateKey, publicKey;
    //CipherRSA.generateKey(privateKey, publicKey, 128);

    //dgWriteln("privateKey");
    //dgWriteln(CipherKey.bytesToBigInteger(privateKey.modulus).toString());
    //dgWriteln(CipherKey.bytesToBigInteger(privateKey.exponent).toString());

    //dgWriteln("publicKey");
    //dgWriteln(CipherKey.bytesToBigInteger(publicKey.modulus).toString());
    //dgWriteln(CipherKey.bytesToBigInteger(publicKey.exponent).toString());
}
