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

module pham.cp.cipher_rc4;

import std.algorithm.mutation : swap;

version (unittest) import pham.utl.test;
import pham.cp.cipher;

nothrow @safe:

class CipherRC4 : Cipher
{
nothrow @safe:

public:
    this(CipherParameters parameters)
    in
    {
        assert(parameters.privateKey.length != 0);
    }
    do
    {
        this._parameters = parameters;
        initKey();
    }

    final override ubyte[] decrypt(scope const(ubyte)[] input, return ref ubyte[] output)
    {
        if (input.length)
            return process(input, output);
        else
            return null;
    }

    final override ubyte[] encrypt(scope const(ubyte)[] input, return ref ubyte[] output)
    {
        if (input.length)
            return process(input, output);
        else
            return null;
    }

    final override Cipher reInit()
    in
    {
        assert(_parameters.privateKey.length != 0);
    }
    do
    {
        initKey();
        return this;
    }

    @property final override bool isSymantic() const
    {
        return false;
    }

    @property final override string name() const
    {
        return "RC4";
    }

protected:
    override void doDispose(bool disposing)
    {
        _stateData[] = 0;
        x = y = 0;
        super.doDispose(disposing);
    }

private:
    final void initKey()
    {
        x = y = 0;
        foreach (i; 0..stateLength)
            _stateData[i] = cast(ubyte)i;

        int iKey, i2;
        foreach (i; 0..stateLength)
        {
            i2 = (_parameters.privateKey[iKey] + _stateData[i] + i2) & 0xff;
            swap(_stateData[i], _stateData[i2]);
            if (++iKey >= _parameters.privateKey.length)
                iKey = 0;
        }
    }

    final ubyte[] process(scope const(ubyte)[] input, return ref ubyte[] output)
    {
        const resultLength = input.length;
        if (output.length < resultLength)
            output.length = resultLength;

        foreach (i, p; input)
            output[i] = processImpl(p);

        return output[0..resultLength];
    }

    pragma(inline, true)
    final ubyte processImpl(const(ubyte) input)
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
    import pham.utl.object : bytesFromHexs;
    import pham.utl.test;
    traceUnitTest("unittest pham.cp.cipher_rc4.CipherRC4");

    {
        ubyte[] key = [ 0x01, 0x23, 0x45, 0x67, 0x89, 0xab, 0xcd, 0xef ];
        ubyte[] test = [ 0x01, 0x23, 0x45, 0x67, 0x89, 0xab, 0xcd, 0xef ];
        ubyte[] testEncrypted = [ 0x75, 0xb7, 0x87, 0x80, 0x99, 0xe0, 0xc5, 0x96 ];
        ubyte[] testResult;

        auto cipherRC4 = new CipherRC4(CipherParameters(key));

        assert(cipherRC4.encrypt(test, testResult) == testEncrypted);
        assert(cipherRC4.reInit().decrypt(testEncrypted, testResult) == test);

        cipherRC4.dispose();
        cipherRC4 = null;
    }

    {
        auto key = bytesFromHexs("1234ABCD43211234ABCD432112345678");
        auto cipherRC4 = new CipherRC4(CipherParameters(key));

        auto input = key;
        ubyte[] output;
        assert(cipherRC4.encrypt(input, output) == bytesFromHexs("4B8E9F295B071B7239ABC838B3E4DC9B"));

        cipherRC4.dispose();
        cipherRC4 = null;
    }
}
