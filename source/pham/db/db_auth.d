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

import pham.db.object : DbDisposableObject;

nothrow @safe:

abstract class DbAuth : DbDisposableObject
{
nothrow @safe:

public:
    bool canCryptedConnection() const pure
    {
        return false;
    }

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

    const(ubyte)[] getAuthData(scope const(char)[] userName, scope const(char)[] userPassword, const(ubyte)[] serverAuthData);

    const(ubyte)[] privateKey() const
    {
        return null;
    }

    const(ubyte)[] publicKey() const
    {
        return null;
    }

    final const(ubyte)[] serverPublicKey() const pure
    {
        return _serverPublicKey;
    }

    final const(ubyte)[] serverSalt() const pure
    {
        return _serverSalt;
    }

    const(ubyte)[] sessionKey() const
    {
        return null;
    }

    @property bool isSymantic() const
    {
        return false;
    }

    @property string name() const;

    @property string sessionKeyName() const
    {
        return null;
    }

public:
    static DbAuthMap findAuthMap(scope const(char)[] name) @trusted //@trusted=__gshared
    {
        foreach (ref m; _authMaps)
        {
            if (m.name == name)
                return m;
        }
        return DbAuthMap.init;
    }

    static void registerAuthMap(DbAuthMap authMap) @trusted //@trusted=__gshared
    in
    {
        assert(authMap.isValid());
    }
    do
    {
        foreach (i, ref m; _authMaps)
        {
            if (m.name == authMap.name)
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
    int errorCode;

protected:
    ubyte[] _serverPublicKey;
    ubyte[] _serverSalt;

private:
    __gshared static DbAuthMap[] _authMaps;
}

struct DbAuthMap
{
nothrow @safe:

public:
    bool isValid() const pure
    {
        return name.length != 0 && createAuth !is null;
    }

public:
    string name;
    DbAuth function() nothrow @safe createAuth;
}
