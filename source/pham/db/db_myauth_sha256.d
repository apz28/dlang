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

module pham.db.myauth_sha256;

version (unittest) import pham.utl.test;
import pham.db.auth;
import pham.db.message;
import pham.db.type : DbScheme;
import pham.db.myauth;

nothrow @safe:

class MyAuthSha256 : MyAuth
{
nothrow @safe:

    static immutable string authSha256Name = "sha256_password";

public:
    final override const(ubyte)[] getAuthData(const(int) state, scope const(char)[] userName, scope const(char)[] userPassword,
        const(ubyte)[] serverAuthData)
    {
        version (TraceFunction) traceFunction!("pham.db.mydatabase")("_nextState=", _nextState, ", state=", state, ", userName=", userName, ", serverAuthData=", serverAuthData);

        //TODO
        return null;
    }

    final override const(ubyte)[] getPassword(scope const(char)[] userName, scope const(char)[] userPassword, const(ubyte)[] serverAuthData)
    {
        return null;
    }

    @property final override int multiSteps() const @nogc pure
    {
        return 0; //TODO
    }

    @property final override string name() const pure
    {
        return authSha256Name;
    }
}
