/*
*
* License: $(HTTP www.boost.org/LICENSE_1_0.txt, Boost License 1.0).
* Authors: An Pham
*
* Copyright An Pham 2019 - xxxx.
* Distributed under the Boost Software License, Version 1.0.
* (See accompanying file LICENSE.txt or copy at http://www.boost.org/LICENSE_1_0.txt)
*
*/

module pham.db.auth;

import pham.db.dbobject;

nothrow @safe:

abstract class DbAuth : DbDisposableObject
{
nothrow @safe:

public:
    final typeof(this) clearError()
    {
        errorMessage = null;
        errorCode = 0;
        return this;
    }

    final typeof(this) setError(int errorCode, string errorMessage)
    {
        this.errorCode = errorCode;
        this.errorMessage = errorMessage;
        return this;
    }

    ubyte[] getAuthData(const(char)[] userName, const(char)[] userPassword, ubyte[] serverAuthData);
    const(ubyte)[] privateKey() const;
    const(ubyte)[] publicKey() const;
    const(ubyte)[] sessionKey() const;
    const(ubyte)[] serverPublicKey() const;
    const(ubyte)[] serverSalt() const;

    @property bool isSymantic() const;
    @property string name() const;
    @property string sessionKeyName() const;

public:
    string errorMessage;
    int errorCode;
}
