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

module pham.db.fbauth;

import pham.db.auth;

nothrow @safe:

abstract class FbAuth : DbAuth
{
nothrow @safe:

public:
    abstract size_t maxSizeServerAuthData(out size_t maxSaltLength) const pure;

    bool parseServerAuthData(ubyte[] serverAuthData, ref ubyte[] serverSalt, ref ubyte[] serverPublicKey)
    {
        version (TraceAuth)
            auto serverAuthDataOrg = serverAuthData;

        enum minLength = 3; // two leading size data + at least 1 byte data

        // Min & Max length?
        size_t maxSaltLength;
        if (serverAuthData.length < minLength || serverAuthData.length > maxSizeServerAuthData(maxSaltLength))
            return false;

		const saltLength = serverAuthData[0] + (cast(size_t)serverAuthData[1] << 8);
        serverAuthData = serverAuthData[2..$]; // Skip the length data
        if (saltLength > maxSaltLength || saltLength > serverAuthData.length)
            return false;
        serverSalt = serverAuthData[0..saltLength];
        serverAuthData = serverAuthData[saltLength..$]; // Skip salt data
        if (serverAuthData.length < minLength)
            return false;

		const keyLength = serverAuthData[0] + (cast(size_t)serverAuthData[1] << 8);
        if (keyLength + 2 > serverAuthData.length)
            return false;

        serverPublicKey = serverAuthData[2..keyLength + 2];

        this._serverPublicKey = serverPublicKey;
        this._serverSalt = serverSalt;

        version (TraceAuth)
        {
            import pham.utl.utltest;
            dgFunctionTrace("keyLength=", keyLength,
                ", saltLength=", saltLength,
                ", serverAuthDataLength=", serverAuthDataOrg.length,
                ", serverPublicKey=", serverPublicKey.dgToString(),
                ", serverSalt=", serverSalt.dgToString(),
                ", serverAuthData=", serverAuthDataOrg.dgToString());
        }

        return true;
    }

    final override const(ubyte)[] serverPublicKey() const
    {
        return _serverPublicKey;
    }

    final override const(ubyte)[] serverSalt() const
    {
        return _serverSalt;
    }

protected:
    override void doDispose(bool disposing) nothrow
    {
        _serverPublicKey[] = 0;
        _serverSalt[] = 0;
    }

private:
    ubyte[] _serverPublicKey;
    ubyte[] _serverSalt;
}
