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

module pham.db.db_auth;

import std.conv : to;

debug(debug_pham_db_db_auth) import std.stdio : writeln;

public import pham.cp.cp_cipher : CipherBuffer, CipherRawKey;
import pham.utl.utl_disposable : DisposingReason;
import pham.utl.utl_object : VersionString;
public import pham.utl.utl_result : ResultStatus;
import pham.db.db_message : DbMessage, fmtMessage;
import pham.db.db_object : DbDisposableObject;
import pham.db.db_type : DbScheme;

nothrow @safe:

abstract class DbAuth : DbDisposableObject
{
@safe:

public:
    ResultStatus getAuthData(const(int) state, scope const(char)[] userName, scope const(char)[] userPassword,
        scope const(ubyte)[] serverAuthData, ref CipherBuffer!ubyte authData) nothrow;

    CipherRawKey!ubyte sessionKey() nothrow
    {
        return CipherRawKey!ubyte.init;
    }

    DbAuth setServerPublicKey(scope const(ubyte)[] serverPublicKey) nothrow pure
    {
        debug(debug_pham_db_db_auth) debug writeln(__FUNCTION__, "(serverPublicKey=", serverPublicKey.dgToHex(), ")");

        this._serverPublicKey = serverPublicKey; 
        return this;
    }

    DbAuth setServerSalt(scope const(ubyte)[] serverSalt) nothrow pure
    {
        debug(debug_pham_db_db_auth) debug writeln(__FUNCTION__, "(serverSalt=", serverSalt.dgToHex(), ")");

        this._serverSalt = serverSalt;
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

    @property const(CipherRawKey!ubyte) privateKey() const nothrow
    {
        return CipherRawKey!ubyte([]);
    }

    @property const(CipherRawKey!ubyte) publicKey() const nothrow
    {
        return CipherRawKey!ubyte([]);
    }

    @property DbScheme scheme() const nothrow pure;

    @property final const(CipherRawKey!ubyte) serverPublicKey() const nothrow pure
    {
        return _serverPublicKey;
    }

    @property final const(CipherRawKey!ubyte) serverSalt() const nothrow pure
    {
        return _serverSalt;
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
        scope (failure) assert(0, "Assume nothrow failed");
        
        if (state != _nextState || state >= multiStates)
            return ResultStatus.error(state + 1, DbMessage.eInvalidConnectionAuthServerData.fmtMessage(name, "invalid state: " ~ state.to!string()));
        else
        {
            _nextState++;
            return ResultStatus.ok();
        }
    }

    override void doDispose(const(DisposingReason) disposingReason) nothrow @safe
    {
        _serverPublicKey.dispose(disposingReason);
        _serverSalt.dispose(disposingReason);
        _nextState = 0;
    }

public:
    VersionString serverVersion;
    bool isSSLConnection;

protected:
    CipherRawKey!ubyte _serverPublicKey;
    CipherRawKey!ubyte _serverSalt;
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
