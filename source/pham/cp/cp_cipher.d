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

import pham.utl.object : DisposableObject;

nothrow @safe:

struct CipherParameters
{
nothrow @safe:

public:
    this(ubyte[] privateKey)
    {
        this(privateKey, null, null);
    }

    this(ubyte[] privateKey, ubyte[] publicKey, ubyte[] salt)
    {
        this._privateKey = privateKey;
        this._publicKey = publicKey;
        this._salt = salt;
    }

    // For security reason, need to clear the secrete information
    void dispose(bool disposing = true)
    {
        _privateKey[] = 0;
        _publicKey[] = 0;
        _salt[] = 0;
    }

    @property const(ubyte)[] privateKey() const
    {
        return _privateKey;
    }

    @property const(ubyte)[] publicKey() const
    {
        return _publicKey;
    }

    @property const(ubyte)[] salt() const
    {
        return _salt;
    }

private:
    ubyte[] _privateKey;
    ubyte[] _publicKey;
    ubyte[] _salt;
}

abstract class Cipher : DisposableObject
{
nothrow @safe:

public:
    ubyte[] decrypt(scope const(ubyte)[] input, return ref ubyte[] output);
    ubyte[] encrypt(scope const(ubyte)[] input, return ref ubyte[] output);
    Cipher reInit();

    @property bool isSymantic() const;
    @property string name() const;

protected:
    override void doDispose(bool disposing)
    {
        _parameters.dispose(disposing);
    }

protected:
    CipherParameters _parameters;
}
