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

module pham.db.db_fbauth_legacy;

import std.conv : to;

version (unittest) import pham.utl.utl_test;
import pham.cp.cp_auth_crypt3;
import pham.db.db_auth;
import pham.db.db_message;
import pham.db.db_type : DbScheme;
import pham.db.db_fbauth;
import pham.db.db_fbisc : FbIscText;

nothrow @safe:

class FbAuthLegacy : FbAuth
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

shared static this() nothrow @safe
{
    DbAuth.registerAuthMap(DbAuthMap(FbIscText.authLegacyName, DbScheme.fb, &createAuthLegacy));
}

DbAuth createAuthLegacy()
{
    return new FbAuthLegacy();
}
