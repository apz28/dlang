/*
*
* License: $(HTTP www.boost.org/LICENSE_1_0.txt, Boost License 1.0).
* Authors: An Pham
*
* Copyright An Pham 2026 - xxxx.
* Distributed under the Boost Software License, Version 1.0.
* (See accompanying file LICENSE.txt or copy at http://www.boost.org/LICENSE_1_0.txt)
*
*/

module pham.db.db_pgauth_oauth;

version(pham_db_db_oauth):

import std.string : representation;

debug(debug_pham_db_db_pgauth_oauth) import pham.db.db_debug;
import pham.utl.utl_array_append : Appender;
import pham.db.db_auth;
import pham.db.db_message;
import pham.db.db_oauth;
import pham.db.db_type : DbScheme;
import pham.db.db_pgauth;
import pham.db.db_pgtype : pgAuthOAuthName;

nothrow @safe:

class PgAuthOAuth : PgAuth
{
nothrow @safe:

public:
    final override ResultStatus getAuthData(const(int) state, ref DbAuthStateData stateData)
    {
        debug(debug_pham_db_db_pgauth_oauth) debug writeln(__FUNCTION__, "(_nextState=", _nextState,
            ", state=", state, ", stateData=", stateData.toString(), ")");

        const(char)[] accessToken;
        const status = stateData.isOAuthAccessToken(accessToken);
        if (status == 2)
        {
            assert(accessToken.length != 0);

            stateData.authData = createAuthDataBearerToken(accessToken).representation();
            return ResultStatus.ok();
        }
        else if (status == 1)
        {
            stateData.authData.clear();
            //todo check for result
            auto authorizedToken = oauth.authorizeAccessToken(stateData.oauthAuthorizerURL, stateData.oauthClientId[], stateData.oauthScopes, stateData.oauthProviderName);
            if (authorizedToken.isError)
                return ResultStatus.error(DbErrorCode.connect, authorizedToken.errorMessage);
                
            auto accessTokenData = oauth.requestAccessToken(stateData.oauthIssuerURL, authorizedToken.value);
            if (accessTokenData.isError)
                return ResultStatus.error(DbErrorCode.connect, accessTokenData.errorMessage);
                
            return ResultStatus.ok(); //todo
        }
        else
        {
            //todo failed or query server for oauth info
            auto msg = DbMessage.eInvalidConnectionAuthMissingInfo.fmtMessage(name);
            return ResultStatus.error(DbErrorCode.connect, msg);
        }
    }

    static immutable string kvSep = "\x01";

    static string createAuthDataDiscover() nothrow
    {
        // "n,,[kvSep]auth=[authScheme ][token][kvSep][kvSep]"
        ShortStringBuffer!char result;
        return result.put("n,,")
            .put(kvSep)
            .put("auth=")
            .put("")
            .put("")
            .put(kvSep)
            .put(kvSep)
            .toString();
    }

    static string createAuthDataBearerToken(scope const(char)[] bearerToken) nothrow
    in
    {
        assert(bearerToken.length != 0);
    }
    do
    {
        //if (bearerToken.length == 0)
        //    return ResultIf!string.error(DbErrorCode.connect, "No OAuth token was set for the connection");

        // "n,,[kvSep]auth=[authScheme ][token][kvSep][kvSep]"
        auto result = Appender!string(3 + 1 + 5 + 7 + bearerToken.length + 1 + 1);
        result.put("n,,")
            .put(kvSep)
            .put("auth=")
            .put("Bearer ")
            .put(bearerToken)
            .put(kvSep)
            .put(kvSep);

        return result.data;
    }

    @property final override int multiStates() const @nogc pure
    {
        return oauth.multiStates;
    }

    @property final override string name() const pure
    {
        return pgAuthOAuthName;
    }

public:
    DbOAuth oauth = DbOAuth("OAuth/OIDC", pgAuthOAuthName, DbScheme.pg);
}


// Any below codes are private
private:

shared static this() nothrow @safe
{
    DbAuth.registerAuthMap(DbAuthMap(pgAuthOAuthName, DbScheme.pg, &createAuthOAuth));
}

DbAuth createAuthOAuth()
{
    return new PgAuthOAuth();
}

unittest // PgAuthOAuth.createDiscover
{
    auto s = PgAuthOAuth.createAuthDataDiscover();
    assert(s == "n,,\x01auth=\x01\x01", "\"" ~ s ~ "\"");

    s = PgAuthOAuth.createAuthDataDiscover();
    assert(s == "n,,\x01auth=\x01\x01", "\"" ~ s ~ "\"");
}

unittest // PgAuthOAuth.createToken
{
    auto s = PgAuthOAuth.createAuthDataBearerToken("XyZ");
    assert(s == "n,,\x01auth=Bearer XyZ\x01\x01", "\"" ~ s ~ "\"");
}
