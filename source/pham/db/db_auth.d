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

import pham.db.message : fmtMessage;
import pham.db.object : DbDisposableObject;
import pham.db.type : DbScheme;

nothrow @safe:

abstract class DbAuth : DbDisposableObject
{
@safe:

public:
    bool canCryptedConnection() const nothrow pure
    {
        return false;
    }

    final typeof(this) clearError() nothrow
    {
        errorMessage = null;
        errorMessageFormat = null;
        errorCode = 0;
        return this;
    }

    final string getErrorMessage(scope const(char)[] authName) pure
    {
        return errorMessageFormat.length != 0
            ? errorMessageFormat.fmtMessage(authName, errorMessage)
            : errorMessage;
    }

    final typeof(this) setError(int errorCode, string errorMessage, string errorMessageFormat) nothrow
    {
        this.errorCode = errorCode;
        this.errorMessage = errorMessage;
        this.errorMessageFormat = errorMessageFormat;
        return this;
    }

    const(ubyte)[] getAuthData(const(int) state, scope const(char)[] userName, scope const(char)[] userPassword,
        const(ubyte)[] serverAuthData) nothrow;

    const(ubyte)[] privateKey() const nothrow
    {
        return null;
    }

    const(ubyte)[] publicKey() const nothrow
    {
        return null;
    }

    final const(ubyte)[] serverPublicKey() const nothrow pure
    {
        return _serverPublicKey;
    }

    final const(ubyte)[] serverSalt() const nothrow pure
    {
        return _serverSalt;
    }

    const(ubyte)[] sessionKey() const nothrow
    {
        return null;
    }

    @property bool isError() const @nogc nothrow pure
    {
        return errorCode != 0;
    }

    @property int multiSteps() const @nogc nothrow pure;

    @property bool isSymantic() const @nogc nothrow pure
    {
        return false;
    }

    @property string name() const nothrow pure;

    @property DbScheme scheme() const nothrow pure;

    @property string sessionKeyName() const nothrow pure
    {
        return null;
    }

public:
    static DbAuthMap findAuthMap(scope const(char)[] name, scope const(DbScheme) scheme) nothrow @trusted //@trusted=__gshared
    {
        foreach (ref m; _authMaps)
        {
            if (m.isEqual(name, scheme))
                return m;
        }
        return DbAuthMap.init;
    }

    static void registerAuthMap(DbAuthMap authMap) nothrow @trusted //@trusted=__gshared
    in
    {
        assert(authMap.isValid());
    }
    do
    {
        foreach (i, ref m; _authMaps)
        {
            if (m.isEqual(authMap.name, authMap.scheme))
            {
                _authMaps[i].createAuth = authMap.createAuth;
                return;
            }
        }
        _authMaps ~= authMap;
    }

protected:
    override void doDispose(bool disposing) nothrow
    {
        _serverPublicKey[] = 0;
        _serverSalt[] = 0;

        if (disposing)
        {
            _serverPublicKey = null;
            _serverSalt = null;
        }
    }

public:
    string errorMessage;
    string errorMessageFormat;
    int errorCode;

protected:
    ubyte[] _serverPublicKey;
    ubyte[] _serverSalt;
    int _nextState;

private:
    __gshared static DbAuthMap[] _authMaps;
}

struct DbAuthMap
{
nothrow @safe:

public:
    bool isEqual(scope const(char)[] otherName, scope const(DbScheme) otherScheme) const pure
    {
        return name == otherName && scheme == otherScheme;
    }

    bool isValid() const pure
    {
        return name.length != 0 && scheme.length != 0 && createAuth !is null;
    }

public:
    string name;
    DbScheme scheme;
    DbAuth function() nothrow @safe createAuth;
}
