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

import std.conv : to;

version (unittest) import pham.utl.test;
public import pham.cp.cipher : CipherBuffer;
import pham.utl.object : VersionString;
public import pham.utl.object : ResultStatus;
import pham.db.message : DbMessage, fmtMessage;
import pham.db.object : DbDisposableObject;
import pham.db.type : DbScheme;

nothrow @safe:

abstract class DbAuth : DbDisposableObject
{
@safe:

public:
    ResultStatus getAuthData(const(int) state, scope const(char)[] userName, scope const(char)[] userPassword,
        scope const(ubyte)[] serverAuthData, ref CipherBuffer authData) nothrow;

    static string getErrorMessage(ResultStatus errorStatus, scope const(char)[] authName) pure
    {
        return errorStatus.errorFormat.length != 0
            ? errorStatus.errorFormat.fmtMessage(authName, errorStatus.errorMessage)
            : errorStatus.errorMessage;
    }

    DbAuth setServerPublicKey(scope const(ubyte)[] serverPublicKey) nothrow pure
    {
        version (TraceFunction) traceFunction!("pham.db.database")("serverPublicKey=", serverPublicKey.dgToHex());

        this._serverPublicKey[] = 0; // Clear previous value for security reason
        this._serverPublicKey = serverPublicKey.dup;
        return this;
    }

    DbAuth setServerSalt(scope const(ubyte)[] serverSalt) nothrow pure
    {
        version (TraceFunction) traceFunction!("pham.db.database")("serverSalt=", serverSalt.dgToHex());

        this._serverSalt[] = 0; // Clear previous value for security reason
        this._serverSalt = serverSalt.dup;
        return this;
    }

    @property bool canCryptedConnection() const nothrow pure
    {
        return false;
    }

    @property int multiStates() const @nogc nothrow pure;

    @property bool isSymantic() const @nogc nothrow pure
    {
        return false;
    }

    @property string name() const nothrow pure;

    @property const(ubyte)[] privateKey() const nothrow
    {
        return null;
    }

    @property const(ubyte)[] publicKey() const nothrow
    {
        return null;
    }

    @property DbScheme scheme() const nothrow pure;

    @property final const(ubyte)[] serverPublicKey() const nothrow pure
    {
        return _serverPublicKey;
    }

    @property final const(ubyte)[] serverSalt() const nothrow pure
    {
        return _serverSalt;
    }

    @property const(ubyte)[] sessionKey() const nothrow
    {
        return null;
    }

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
    final ResultStatus checkAdvanceState(const(int) state) nothrow pure
    {
        if (state != _nextState || state >= multiStates)
            return ResultStatus.error(state + 1, to!string(state), DbMessage.eInvalidConnectionAuthServerData);
        else
        {
            _nextState++;
            return ResultStatus.ok();
        }
    }

    override void doDispose(bool disposing) nothrow
    {
        _serverPublicKey[] = 0;
        _serverPublicKey = null;
        _serverSalt[] = 0;
        _serverSalt = null;
        _nextState = 0;
    }

public:
    VersionString serverVersion;
    bool isSSLConnection;

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
