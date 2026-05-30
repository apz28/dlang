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

debug(debug_pham_db_db_auth) import pham.db.db_debug;
public import pham.cp.cp_cipher : CipherBuffer, CipherRawKey;
import pham.utl.utl_disposable : DisposingReason;
public import pham.utl.utl_result : ResultCode, ResultStatus;
import pham.utl.utl_version : VersionString;
import pham.db.db_database : DbConnectionStringBuilder;
import pham.db.db_message : DbMessage, fmtMessage;
import pham.db.db_object : DbDisposableObject;
import pham.db.db_type : DbScheme;

@safe:

enum DbAuthState : int
{
    initial = 0,
    continue_ = 1,
    final_ = 2,
}

struct DbAuthStateData
{
@safe:

public:
    void fill(DbScheme scheme)(DbConnectionStringBuilder csb) nothrow
    {
        userName = csb.userName;
        userPassword = csb.userPassword;

        static if (scheme == DbScheme.pg)
        {
            oauthAccessToken = csb.oauthAccessToken;
            oauthClientId = csb.oauthClientId;
            oauthAuthorizerURL = csb.oauthAuthorizerURL;
            oauthIssuerURL = csb.oauthIssuerURL;
            oauthScopes = csb.oauthScopes;
            oauthProviderName = csb.oauthProviderName;
        }
    }

    int isOAuthAccessToken(ref const(char)[] accessToken) const nothrow
    {
        const result = oauthClientId.length != 0
            && oauthAuthorizerURL.length != 0
            && oauthIssuerURL.length != 0;
        if (result)
        {
            if (oauthAccessToken.length != 0)
            {
                accessToken = oauthAccessToken[];
                return 2;
            }
            return 1;
        }
        return 0;
    }

    string toString() const nothrow
    {
        return "{"
            ~ "userName=" ~ userName.toString()
            ~ ", userPassword=?..."
            ~ ", authData=" ~ authData.toString()
            ~ ", serverAuthData=" ~ serverAuthData.toString()
            ~ ", oauthAccessToken=" ~ oauthAccessToken.toString()
            ~ ", oauthClientId=" ~ oauthClientId.toString()
            ~ ", oauthAuthorizerURL=" ~ oauthAuthorizerURL
            ~ ", oauthIssuerURL=" ~ oauthIssuerURL
            ~ ", oauthScopes=" ~ oauthScopes
            ~ ", oauthProviderName=" ~ oauthProviderName
            ~ "}";
    }

public:
    CipherRawKey!ubyte authData;
    CipherRawKey!ubyte serverAuthData;
    CipherRawKey!ubyte serverAuthKey;

    CipherRawKey!char userName;
    CipherRawKey!char userPassword;

    CipherRawKey!char oauthAccessToken;
    CipherRawKey!char oauthClientId;
    string oauthAuthorizerURL;
    string oauthIssuerURL;
    string oauthScopes;
    string oauthProviderName;
}

abstract class DbAuth : DbDisposableObject
{
@safe:

public:
    ResultStatus getAuthData(const(int) state, ref DbAuthStateData stateData) nothrow;

    CipherRawKey!ubyte sessionKey() nothrow
    {
        return CipherRawKey!ubyte.init;
    }

    DbAuth setServerPublicKey(const(ubyte)[] serverPublicKey) nothrow pure
    {
        debug(debug_pham_db_db_auth) debug writeln(__FUNCTION__, "(serverPublicKey=", serverPublicKey.dgToHex(), ")");

        this._serverPublicKey = serverPublicKey;
        return this;
    }

    DbAuth setServerSalt(const(ubyte)[] serverSalt) nothrow pure
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

    final ResultStatus invalidAuthState(const(int) state) nothrow
    {
        auto msg = DbMessage.eInvalidConnectionAuthServerData.fmtMessage(name, "invalid state: " ~ state.to!string());
        return ResultStatus.error(state + 1, msg);
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
    final ResultStatus checkAdvanceState(const(int) state) nothrow
    {
        if (state != _nextState || state >= multiStates)
            return invalidAuthState(state);

        _nextState++;
        return ResultStatus.ok();
    }

    override int doDispose(const(DisposingReason) disposingReason) nothrow @safe
    {
        serverVersion = VersionString("");
        isSSLConnection = false;
        _serverPublicKey.dispose(disposingReason);
        _serverSalt.dispose(disposingReason);
        _nextState = DbAuthState.initial;
        return ResultCode.ok;
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
    pragma(inline, true)
    bool isEqual(scope const(char)[] otherName, scope const(DbScheme) otherScheme) const pure
    {
        return name == otherName && scheme == otherScheme;
    }

    pragma(inline, true)
    bool isValid() const pure
    {
        return name.length != 0 && scheme.length != 0 && createAuth !is null;
    }

public:
    string name;
    DbScheme scheme;
    DbAuth function() nothrow @safe createAuth;
}
