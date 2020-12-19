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
    final override ubyte[] getAuthData(const(char)[] userName, const(char)[] userPassword, ubyte[] serverAuthData)
    {
        // Exclude the 2 salt chars
        return crypt3(userPassword, fbSalt)[2..$];
    }

    final override size_t maxSizeServerAuthData(out size_t maxSaltLength) const pure
    {
        maxSaltLength = fbSaltLength * 2;
        // ((fbSaltLength + 1) * 2) + ((fbKeyLength + 1) * 2)
        return (fbSaltLength + fbKeyLength + 2) * 2;  //+2 for leading size data
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
        return "Legacy_Auth";
    }

    @property final override string sessionKeyName() const
    {
        return null;
    }
}

private enum fbKeyLength = 0;
private enum fbSaltLength = 2;
private enum fbSalt = "9z";
