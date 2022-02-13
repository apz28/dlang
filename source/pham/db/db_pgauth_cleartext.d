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

module pham.db.pgauth_cleartext;

import std.conv : to;
import std.string : representation;

version (unittest) import pham.utl.test;
import pham.db.auth;
import pham.db.message;
import pham.db.type : DbScheme;
import pham.db.pgauth;
import pham.db.pgtype : pgAuthClearTextName;

nothrow @safe:

class PgAuthClearText : PgAuth
{
nothrow @safe:

public:
    final override const(ubyte)[] getAuthData(const(int) state, scope const(char)[] userName, scope const(char)[] userPassword,
        const(ubyte)[] serverAuthData)
    {
        version (TraceFunction) traceFunction!("pham.db.pgdatabase")("_nextState=", _nextState, ", state=", state, ", userName=", userName, ", serverAuthData=", serverAuthData);

        if (state != _nextState || state != 0)
        {
            setError(state + 1, to!string(state), DbMessage.eInvalidConnectionAuthServerData);
            return null;
        }

        _nextState++;
        return userPassword.dup.representation();
    }

    @property final override int multiSteps() const @nogc pure
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

shared static this()
{
    DbAuth.registerAuthMap(DbAuthMap(pgAuthClearTextName, DbScheme.pg, &createAuthClearText));
}

DbAuth createAuthClearText()
{
    return new PgAuthClearText();
}
