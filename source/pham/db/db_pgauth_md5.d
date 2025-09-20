/*
*
* License: $(HTTP www.boost.org/LICENSE_1_0.txt, Boost License 1.0).
* Authors: An Pham
*
* Copyright An Pham 2021 - xxxx.
* Distributed under the Boost Software License, Version 1.0.
* (See accompanying file LICENSE.txt or copy at http://www.boost.org/LICENSE_1_0.txt)
*
*/

module pham.db.db_pgauth_md5;

import std.ascii : LetterCase;
import std.conv : to;
import std.digest.md : md5Of;
import std.string : representation;

debug(debug_pham_db_db_pgauth_md5) import pham.db.db_debug;
import pham.utl.utl_numeric_parser : cvtBytesBase16;
import pham.db.db_auth;
import pham.db.db_message;
import pham.db.db_type : DbScheme;
import pham.db.db_pgauth;
import pham.db.db_pgtype : pgAuthMD5Name;

nothrow @safe:

class PgAuthMD5 : PgAuth
{
nothrow @safe:

public:
    /**
     * MD5-hashed password is required
     * Formatted as:
     *  "md5" + md5(md5(password + username) + salt)
     *  where md5() returns lowercase hex-string
     * Params:
     *  serverAuthData = is server salt
     */
    final override ResultStatus getAuthData(const(int) state, scope const(char)[] userName, scope const(char)[] userPassword,
        scope const(ubyte)[] serverAuthData, ref CipherBuffer!ubyte authData)
    {
        debug(debug_pham_db_db_pgauth_md5) debug writeln(__FUNCTION__, "(_nextState=", _nextState, ", state=", state, ", userName=", userName,
            ", serverAuthData=", serverAuthData.dgToHex(), ")");

        auto status = checkAdvanceState(state);
        if (status.isError)
            return status;

        const md5Password = MD5toHex(userPassword, userName);
        char[3 + 32] result;
        result[0..3] = "md5";
        result[3..$] = MD5toHex(md5Password, serverAuthData);
        authData = result[].representation();
        return ResultStatus.ok();
    }

    @property final override int multiStates() const @nogc pure
    {
        return 1;
    }

    @property final override string name() const pure
    {
        return pgAuthMD5Name;
    }

private:
    //char[32]
    static char[] MD5toHex(T...)(scope const(T) data) nothrow @safe
    {
        return md5Of(data).cvtBytesBase16(LetterCase.lower);
    }
}


// Any below codes are private
private:

shared static this() nothrow @safe
{
    DbAuth.registerAuthMap(DbAuthMap(pgAuthMD5Name, DbScheme.pg, &createAuthMD5));
}

DbAuth createAuthMD5()
{
    return new PgAuthMD5();
}

unittest // PgAuthMD5
{
    import std.string : representation;
    import pham.utl.utl_convert : bytesFromHexs;

    auto salt = bytesFromHexs("9F170CAC");
    auto auth = new PgAuthMD5();
    CipherBuffer!ubyte encp;
    assert(auth.getAuthData(0, "postgres", "masterkey", salt, encp).isOK);
    assert(encp == "md549f0896152ed83ec298a6c09b270be02".representation(), encp.toString());
}
