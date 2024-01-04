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

module pham.db.db_pgauth_cleartext;

import std.conv : to;
import std.string : representation;

version (unittest) import pham.utl.utl_test;
import pham.db.db_auth;
import pham.db.db_message;
import pham.db.db_type : DbScheme;
import pham.db.db_pgauth;
import pham.db.db_pgtype : pgAuthClearTextName;

nothrow @safe:

class PgAuthClearText : PgAuth
{
nothrow @safe:

public:
    final override ResultStatus getAuthData(const(int) state, scope const(char)[] userName, scope const(char)[] userPassword,
        scope const(ubyte)[] serverAuthData, ref CipherBuffer!ubyte authData)
    {
        version (TraceFunction) traceFunction("_nextState=", _nextState, ", state=", state, ", userName=", userName, ", serverAuthData=", serverAuthData.dgToHex());

        auto status = checkAdvanceState(state);
        if (status.isError)
            return status;

        authData = CipherBuffer!ubyte(userPassword.representation());
        return ResultStatus.ok();
    }

    @property final override int multiStates() const @nogc pure
    {
        return 1;
    }

    @property final override string name() const pure
    {
        return pgAuthClearTextName;
    }
}


// Any below codes are private
private:

shared static this() nothrow @safe
{
    DbAuth.registerAuthMap(DbAuthMap(pgAuthClearTextName, DbScheme.pg, &createAuthClearText));
}

DbAuth createAuthClearText()
{
    return new PgAuthClearText();
}
