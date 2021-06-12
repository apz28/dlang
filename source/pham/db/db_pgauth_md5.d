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

module pham.db.pgauth_md5;

import std.ascii : LetterCase;
import std.digest.md : md5Of;
import std.string : representation;

import pham.utl.object : bytesToHexs;
import pham.db.type : DbScheme;
import pham.db.auth;

nothrow @safe:

class PgAuthMD5 : DbAuth
{
nothrow @safe:

    static immutable string authMD5Name = "md5";

public:
    /**
     * MD5-hashed password is required
     * Formatted as:
     *  "md5" + md5(md5(password + username) + salt)
     *  where md5() returns lowercase hex-string
     * Params:
     *  serverAuthData = is server salt
     */
    final override const(ubyte)[] getAuthData(scope const(char)[] userName, scope const(char)[] userPassword, const(ubyte)[] serverAuthData)
    {
        //char[32]
        static char[] MD5toHex(T...)(in T data) nothrow @safe
        {
            return md5Of(data).bytesToHexs!(LetterCase.lower);
        }

        const md5Password = MD5toHex(userPassword, userName);
        auto result = new char[3 + 32];
        result[0..3] = "md5";
        result[3..$] = MD5toHex(md5Password, serverAuthData);
        return result.representation;
    }

    @property final override string name() const
    {
        return authMD5Name;
    }
}


// Any below codes are private
private:


shared static this()
{
    DbAuth.registerAuthMap(DbAuthMap(DbScheme.pg ~ PgAuthMD5.authMD5Name, &createAuthMD5));
}

DbAuth createAuthMD5()
{
    return new PgAuthMD5();
}

unittest // PgAuthMD5
{
    import pham.utl.object : bytesFromHexs;
    import pham.utl.test;
    traceUnitTest("unittest pham.db.pgauth_md5.PgAuthMD5");

    auto salt = bytesFromHexs("9F170CAC");
    auto auth = new PgAuthMD5();
    auto encp = cast(const(char)[])auth.getAuthData("postgres", "masterkey", salt);
    assert(encp == "md549f0896152ed83ec298a6c09b270be02", encp);
}
