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
import pham.db.fbauth;

nothrow @safe:

class FbAuthLegacy : FbAuth
{
nothrow @safe:

public:
    final override bool canCryptedConnection() const pure
    {
        return false;
    }

    final override ubyte[] getAuthData(const(char)[] userName, const(char)[] userPassword, ubyte[] serverAuthData)
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

    final override const(ubyte)[] privateKey() const
    {
        return null;
    }

    final override const(ubyte)[] publicKey() const
    {
        return null;
    }

    final override const(ubyte)[] sessionKey() const
    {
        return null;
    }

    @property final override bool isSymantic() const
    {
        return false;
    }

    @property final override string name() const
    {
        return authLegacyName;
    }

    @property final override string sessionKeyName() const
    {
        return null;
    }

private:
    static immutable string authLegacyName = "Legacy_Auth";
    enum keyLength = 0;
    enum saltLength = 2;
    enum salt = "9z";
}


// Any below codes are private
private:


shared static this()
{
    FbAuth.registerAuthMap(FbAuthMap(FbAuthLegacy.authLegacyName, &createAuthLegacy));
}

FbAuth createAuthLegacy()
{
    return new FbAuthLegacy();
}
