/*
*
* License: $(HTTP www.boost.org/LICENSE_1_0.txt, Boost License 1.0).
* Authors: An Pham
*
* Copyright An Pham 2022 - xxxx.
* Distributed under the Boost Software License, Version 1.0.
* (See accompanying file LICENSE.txt or copy at http://www.boost.org/LICENSE_1_0.txt)
*
*/

module pham.db.db_myauth;

debug(debug_pham_db_db_myauth) import std.stdio : writeln;

public import pham.cp.cp_cipher : CipherBuffer;
import pham.db.db_auth;
import pham.db.db_type : DbScheme;

nothrow @safe:

abstract class MyAuth : DbAuth
{
nothrow @safe:

public:
    static DbAuthMap findAuthMap(scope const(char)[] name)
    {
        return DbAuth.findAuthMap(name, DbScheme.my);
    }

    ResultStatus getPassword(scope const(char)[] userName, scope const(char)[] userPassword,
        ref CipherBuffer!ubyte authData)
    {
        debug(debug_pham_db_db_myauth) debug writeln(__FUNCTION__, "(userName=", userName, ")");

        authData = CipherBuffer!ubyte.init;
        return ResultStatus.ok();
    }

    @property final override DbScheme scheme() const pure
    {
        return DbScheme.my;
    }
}
