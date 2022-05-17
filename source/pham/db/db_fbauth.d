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

version (TraceFunction) import pham.utl.test;
import pham.cp.cipher : CipherHelper;
public import pham.cp.cipher : CipherBuffer, CipherKey;
import pham.utl.utf8 : ShortStringBuffer, UTF8CharRange;
import pham.db.auth;
import pham.db.message;
import pham.db.type : DbScheme;

nothrow @safe:

abstract class FbAuth : DbAuth
{
nothrow @safe:

public:
    static DbAuthMap findAuthMap(scope const(char)[] name)
    {
        return DbAuth.findAuthMap(name, DbScheme.fb);
    }

    abstract size_t maxSizeServerAuthData(out size_t maxSaltLength) const pure;

    static const(char)[] normalizeUserName(scope const(char)[] userName) pure
    {
        if (userName.length == 0)
            return null;

        if (userName.length > 2 && userName[0] == '"' && userName[userName.length - 1] == '"')
        {
            ShortStringBuffer!char quotedUserName;
            auto chars = UTF8CharRange(userName);
            chars.popFront(); // Skip first quote
            while (!chars.empty)
            {
                if (chars.front == '"')
                {
                    // Strip double quote escape
                    chars.popFront();
                    // Last quote?
                    if (chars.isLast)
                        break;

                    // Retain escaped double quote?
                    if (chars.front == '"')
                        quotedUserName.put('"');
                    else
        				// The character after escape is not a double quote,
                        // we terminate the conversion and truncate.
		    			// Firebird does this as well (see common/utils.cpp#dpbItemUpper)
                        break;
                }
                else
                {
                    quotedUserName.put(userName[chars.previousPosition..chars.position]);
                }

                chars.popFront();
                // Last quote?
                if (chars.isLast)
                    break;
            }
            return quotedUserName.consumeUnique();
        }
        else
            return CipherHelper.toUpper(userName);
    }

    ResultStatus parseServerAuthData(scope const(ubyte)[] serverAuthData)
    {
        version (TraceFunction)
        const serverAuthDataOrg = serverAuthData;

        enum minLength = 3; // two leading size data + at least 1 byte data

        // Min & Max length?
        size_t maxSaltLength;
        if (serverAuthData.length < minLength || serverAuthData.length > maxSizeServerAuthData(maxSaltLength))
            return ResultStatus.error(DbErrorCode.connect, "invalid length", DbMessage.eInvalidConnectionAuthServerData);

		const saltLength = serverAuthData[0] + (cast(size_t)serverAuthData[1] << 8);
        serverAuthData = serverAuthData[2..$]; // Skip the length data
        if (saltLength > maxSaltLength || saltLength > serverAuthData.length)
            return ResultStatus.error(DbErrorCode.connect, "invalid length", DbMessage.eInvalidConnectionAuthServerData);
        _serverSalt = serverAuthData[0..saltLength].dup;

        serverAuthData = serverAuthData[saltLength..$]; // Skip salt data
        if (serverAuthData.length < minLength)
            return ResultStatus.error(DbErrorCode.connect, "invalid length", DbMessage.eInvalidConnectionAuthServerData);
		const keyLength = serverAuthData[0] + (cast(size_t)serverAuthData[1] << 8);
        if (keyLength + 2 > serverAuthData.length)
            return ResultStatus.error(DbErrorCode.connect, "invalid length", DbMessage.eInvalidConnectionAuthServerData);
        _serverPublicKey = serverAuthData[2..keyLength + 2].dup;

        version (TraceFunction)
        {
            traceFunction!("pham.db.fbdatabase")("keyLength=", keyLength,
                ", saltLength=", saltLength,
                ", serverAuthDataLength=", serverAuthDataOrg.length,
                ", serverPublicKey=", _serverPublicKey.dgToHex(),
                ", serverSalt=", _serverSalt.dgToHex(),
                ", serverAuthData=", serverAuthDataOrg.dgToHex());
        }

        return ResultStatus.ok();
    }

    @property final override DbScheme scheme() const pure
    {
        return DbScheme.fb;
    }
}

unittest // FbAuth.normalizeUserName
{
    import pham.utl.test;
    traceUnitTest!("pham.db.fbdatabase")("unittest pham.db.FbAuth.normalizeUserName");

    assert(FbAuth.normalizeUserName("sysDba") == "SYSDBA");
    assert(FbAuth.normalizeUserName("\"sysdba\"") == "sysdba");
    assert(FbAuth.normalizeUserName("\"\"\"a\"\"\"") == "\"a\"");
}
