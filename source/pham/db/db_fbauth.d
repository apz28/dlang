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

import std.exception : assumeWontThrow;
import std.format : format;

import pham.db.message;
import pham.db.auth;

nothrow @safe:

abstract class FbAuth : DbAuth
{
nothrow @safe:

public:
    abstract size_t maxSizeServerAuthData(out size_t maxSaltLength) const pure;

    final static const(char)[] normalizeUserName(const(char)[] userName) pure
    {
        import std.range : Appender;
	    import std.uni : toUpper;

        if (userName.length == 0)
            return userName;

        if (userName.length > 2 && userName[0] == '"' && userName[userName.length - 1] == '"')
        {
            Appender!string quotedS;
            quotedS.reserve(userName.length);
            int i = 1;
            for (; i < (userName.length - 1); i++)
            {
                auto c = userName[i];
                if (c == '"')
                {
                    // Strip double quote escape
                    i++;
                    if (i < (userName.length - 1))
                    {
                        // Retain escaped double quote?
                        if ('"' == userName[i])
                            quotedS.put('"');
                        else
        					// The character after escape is not a double quote,
                            // we terminate the conversion and truncate.
		    				// Firebird does this as well (see common/utils.cpp#dpbItemUpper)
                            break;
                    }
                }
                else
                    quotedS.put(c);
            }
            return quotedS.data;
        }
        else
            return assumeWontThrow(toUpper(userName));
    }

    bool parseServerAuthData(const(ubyte)[] serverAuthData, ref const(ubyte)[] serverSalt, ref const(ubyte)[] serverPublicKey)
    {
        version (TraceAuth)
        const serverAuthDataOrg = serverAuthData;

        enum minLength = 3; // two leading size data + at least 1 byte data

        // Min & Max length?
        size_t maxSaltLength;
        if (serverAuthData.length < minLength || serverAuthData.length > maxSizeServerAuthData(maxSaltLength))
        {
            auto msg = assumeWontThrow(format(DbMessage.eInvalidConnectionAuthServerData, name));
            setError(DbErrorCode.connect, msg);
            return false;
        }

		const saltLength = serverAuthData[0] + (cast(size_t)serverAuthData[1] << 8);
        serverAuthData = serverAuthData[2..$]; // Skip the length data
        if (saltLength > maxSaltLength || saltLength > serverAuthData.length)
        {
            auto msg = assumeWontThrow(format(DbMessage.eInvalidConnectionAuthServerData, name));
            setError(DbErrorCode.connect, msg);
            return false;
        }
        serverSalt = serverAuthData[0..saltLength];
        serverAuthData = serverAuthData[saltLength..$]; // Skip salt data
        if (serverAuthData.length < minLength)
        {
            auto msg = assumeWontThrow(format(DbMessage.eInvalidConnectionAuthServerData, name));
            setError(DbErrorCode.connect, msg);
            return false;
        }

		const keyLength = serverAuthData[0] + (cast(size_t)serverAuthData[1] << 8);
        if (keyLength + 2 > serverAuthData.length)
        {
            auto msg = assumeWontThrow(format(DbMessage.eInvalidConnectionAuthServerData, name));
            setError(DbErrorCode.connect, msg);
            return false;
        }

        serverPublicKey = serverAuthData[2..keyLength + 2];

        this._serverPublicKey = serverPublicKey.dup;
        this._serverSalt = serverSalt.dup;

        version (TraceAuth)
        {
            import pham.utl.test;
            dgFunctionTrace("keyLength=", keyLength,
                ", saltLength=", saltLength,
                ", serverAuthDataLength=", serverAuthDataOrg.length,
                ", serverPublicKey=", serverPublicKey.dgToHex(),
                ", serverSalt=", serverSalt.dgToHex(),
                ", serverAuthData=", serverAuthDataOrg.dgToHex());
        }

        return true;
    }
}

unittest // FbAuth.normalizeUserName
{
    import pham.utl.test;
    traceUnitTest("unittest db.FbAuth.normalizeUserName");

    assert(FbAuth.normalizeUserName("sysdba") == "SYSDBA");
    assert(FbAuth.normalizeUserName("\"sysdba\"") == "sysdba");
}
