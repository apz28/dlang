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

module pham.db.fbauth_legacy;

import std.conv : to;

version (unittest) import pham.utl.test;
import pham.cp.auth_crypt3;
import pham.db.auth;
import pham.db.message;
import pham.db.type : DbScheme;
import pham.db.fbauth;
import pham.db.fbisc : FbIscText;

nothrow @safe:

class FbAuthLegacy : FbAuth
{
nothrow @safe:

public:
    final override ResultStatus getAuthData(const(int) state, scope const(char)[] userName, scope const(char)[] userPassword,
        scope const(ubyte)[] serverAuthData, ref CipherBuffer!ubyte authData)
    {
        version (TraceFunction) traceFunction!("pham.db.fbdatabase")("_nextState=", _nextState, ", state=", state, ", userName=", userName, ", serverAuthData=", serverAuthData.dgToHex());

        auto status = checkAdvanceState(state);
        if (status.isError)
            return status;

        authData = crypt3(userPassword, salt).chopFront(2); // Exclude the 2 leading salt chars
        return ResultStatus.ok();
    }

    final override size_t maxSizeServerAuthData(out size_t maxSaltLength) const pure
    {
        maxSaltLength = saltLength * 2;
        // ((saltLength + 1) * 2) + ((keyLength + 1) * 2)
        return (saltLength + keyLength + 2) * 2;  //+2 for leading size data
    }

    @property final override int multiStates() const @nogc pure
    {
        return 1;
    }

    @property final override string name() const pure
    {
        return FbIscText.authLegacyName;
    }

private:
    enum keyLength = 0;
    enum salt = "9z";
    enum saltLength = 2;
}


// Any below codes are private
private:

shared static this()
{
    DbAuth.registerAuthMap(DbAuthMap(FbIscText.authLegacyName, DbScheme.fb, &createAuthLegacy));
}

DbAuth createAuthLegacy()
{
    return new FbAuthLegacy();
}
