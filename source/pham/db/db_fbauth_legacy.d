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

import pham.cp.auth_crypt3;
import pham.db.type : DbScheme;
import pham.db.auth;
import pham.db.fbauth;

nothrow @safe:

class FbAuthLegacy : FbAuth
{
nothrow @safe:

public:
    final override const(ubyte)[] getAuthData(scope const(char)[] userName, scope const(char)[] userPassword, const(ubyte)[] serverAuthData)
    {
        // Exclude the 2 salt chars
        return crypt3(userPassword, salt)[2..$];
    }

    final override size_t maxSizeServerAuthData(out size_t maxSaltLength) const pure
    {
        maxSaltLength = saltLength * 2;
        // ((saltLength + 1) * 2) + ((keyLength + 1) * 2)
        return (saltLength + keyLength + 2) * 2;  //+2 for leading size data
    }

    @property final override string name() const
    {
        return authLegacyName;
    }

public:
    static immutable string authLegacyName = "Legacy_Auth";

private:
    enum keyLength = 0;
    enum salt = "9z";
    enum saltLength = 2;
}


// Any below codes are private
private:

shared static this()
{
    DbAuth.registerAuthMap(DbAuthMap(DbScheme.fb ~ FbAuthLegacy.authLegacyName, &createAuthLegacy));
}

DbAuth createAuthLegacy()
{
    return new FbAuthLegacy();
}
