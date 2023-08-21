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

module pham.cp.cp_cipher_rc4;

import std.algorithm.mutation : swap;

version (unittest) import pham.utl.utl_test;
import pham.utl.utl_disposable : DisposingReason;
import pham.cp.cp_cipher : Cipher, CipherKey, CipherKeyKind, CipherParameters, CipherRawKey, CipherSimpleKey;

nothrow @safe:

class CipherRC4 : Cipher
{
nothrow @safe:

public:
	this(scope const(ubyte)[] key) pure
    in
    {        
        assert(CipherRawKey!ubyte.isValid(key));
    }
    do
    {
        auto k = CipherSimpleKey(cast(uint)(key.length * 8), key);
		this(CipherKey(k));
    }

    this(CipherKey key) pure
    in
    {
        assert(key.kind == CipherKeyKind.simpleKey);
        assert(key.isValid());
    }
    do
    {
        this._parameters = CipherParameters(key);
        initKey();
    }

    final override ubyte[] decrypt(scope const(ubyte)[] input, return ref ubyte[] output)
    {
        const resultLength = input.length;
        if (output.length < resultLength)
            output.length = resultLength;

        return resultLength != 0 ? process(input, output) : null;
    }

    final override ubyte[] encrypt(scope const(ubyte)[] input, return ref ubyte[] output)
    {
        const resultLength = input.length;
        if (output.length < resultLength)
            output.length = resultLength;

        return resultLength != 0 ? process(input, output) : null;
    }

    @property final override bool isSymantic() const @nogc pure
    {
        return true;
    }

    @property final override string name() const pure
    {
        return "RC4";
    }

protected:
    override void doDispose(const(DisposingReason) disposingReason) nothrow @safe
    {
        _stateData[] = 0;
        x = y = 0;
        super.doDispose(disposingReason);
    }

private:
    final void initKey() pure
    {
        x = y = 0;
        foreach (i; 0..stateLength)
            _stateData[i] = cast(ubyte)i;

        int iKey, i2;
        const key = _parameters.privateKey.simple.key;
        foreach (i; 0..stateLength)
        {
            i2 = (key[iKey] + _stateData[i] + i2) & 0xff;
            swap(_stateData[i], _stateData[i2]);
            if (++iKey >= key.length)
                iKey = 0;
        }
    }

    final ubyte[] process(scope const(ubyte)[] input, return ref ubyte[] output) @nogc pure
    in
    {
        assert(input.length != 0);
    }
    do
    {
        foreach (i, p; input)
            output[i] = processImpl(p);

        return output[0..input.length];
    }

    pragma(inline, true)
    final ubyte processImpl(const(ubyte) input) @nogc pure
    {
        x = (x + 1) & 0xff;
        y = (_stateData[x] + y) & 0xff;
        swap(_stateData[x], _stateData[y]);

        // xor
        return cast(ubyte)(input ^ _stateData[(_stateData[x] + _stateData[y]) & 0xff]);
    }

private:
    enum stateLength = 256;

    ubyte[stateLength] _stateData;
    int x, y;
}


// Any below codes are private
private:

unittest // CipherRC4
{
    {
        ubyte[] key = [ 0x01, 0x23, 0x45, 0x67, 0x89, 0xab, 0xcd, 0xef ];
        ubyte[] test = [ 0x01, 0x23, 0x45, 0x67, 0x89, 0xab, 0xcd, 0xef ];
        ubyte[] testEncrypted = [ 0x75, 0xb7, 0x87, 0x80, 0x99, 0xe0, 0xc5, 0x96 ];
        ubyte[] testResult;

        auto cipherRC4E = new CipherRC4(key);
        auto cipherRC4D = new CipherRC4(key);

        assert(cipherRC4E.encrypt(test, testResult) == testEncrypted);
        assert(cipherRC4D.decrypt(testEncrypted, testResult) == test);

        cipherRC4E.dispose();
        cipherRC4E = null;
        cipherRC4D.dispose();
        cipherRC4D = null;
    }

    {
        auto key = dgFromHex("1234ABCD43211234ABCD432112345678");
        auto input = key.dup;
        ubyte[] output;

        auto cipherRC4 = new CipherRC4(key);
        assert(cipherRC4.encrypt(input, output) == dgFromHex("4B8E9F295B071B7239ABC838B3E4DC9B"));

        cipherRC4.dispose();
        cipherRC4 = null;
    }
}
