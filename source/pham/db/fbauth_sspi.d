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

module pham.db.fbauth_sspi;

import pham.db.fbauth;

class FbAuthSspi : FbAuth
{
nothrow @safe:

public:
    final override ubyte[] getAuthData(const(char)[] userName, const(char)[] userPassword, ubyte[] serverAuthData)
    {
        //todo
        return null; //todo
    }

    final override size_t maxSizeServerAuthData(out size_t maxSaltLength) const nothrow pure
    {
        maxSaltLength = 0;
        return size_t.max;
    }

    final override const(ubyte)[] privateKey() const
    {
        return null;
    }

    final override const(ubyte)[] publicKey() const
    {
        //todo
        return null;
    }

    final override const(ubyte)[] sessionKey() const
    {
        //todo
        return null;
    }

    @property final override bool isSymantic() const
    {
        return false;
    }

    @property final override string name() const
    {
        return "Win_Sspi";
    }

    @property final override string sessionKeyName() const
    {
        return null;
    }

private:
}
