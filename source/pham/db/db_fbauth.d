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
public import pham.cp.cipher : CipherBuffer, CipherChaChaKey, CipherKey, CipherSimpleKey;
public import pham.cp.cipher_buffer : CipherRawKey;
import pham.utl.array : ShortStringBuffer;
import pham.utl.utf8 : UTF8CharRange;
import pham.db.auth;
import pham.db.message;
import pham.db.type : DbScheme;
import pham.db.fbtype : FbIscServerKey;

nothrow @safe:


CipherKey createCryptKey(scope const(char)[] cryptAlgorithm, scope const(ubyte)[] sessionKey, scope const(FbIscServerKey)[] serverAuthKeys)
{
    import std.system : Endian;
    import pham.cp.cipher_digest : DigestId, digestOf;
    import pham.db.convert : uintDecode;
    import pham.db.type : uint32, uint64;
    import pham.db.fbisc : FbIscText;    

    const(ubyte)[] findPluginKey(scope const(char)[] pluginName)
    {
        foreach (ref p; serverAuthKeys)
        {
            const i = p.indexOf(pluginName);
            if (i >= 0 && p.pluginKeys[i].specificData.length != 0)
                return p.pluginKeys[i].specificData;
        }
        return null;
    }

    CipherRawKey!ubyte toChaChaKey()
    {
        return digestOf!(DigestId.sha256)(sessionKey);
    }

    switch (cryptAlgorithm)
    {
        case FbIscText.filterCryptChachaName:
            enum withCounter32 = CipherChaChaKey.nonceSizeCounter32 + 4;
            const serverKey = findPluginKey(cryptAlgorithm);
            const nonce = serverKey[0..CipherChaChaKey.nonceSizeCounter32];
            const uint32 counter32 = serverKey.length == withCounter32
                ? uintDecode!(uint32, Endian.bigEndian)(serverKey[CipherChaChaKey.nonceSizeCounter32..withCounter32])
                : 0u;
            const k = toChaChaKey();
            return CipherKey(CipherChaChaKey(cast(uint)(k.length * 8), k, nonce, counter32));

        case FbIscText.filterCryptChacha64Name:
            enum withCounter64 = CipherChaChaKey.nonceSizeCounter64 + 8;
            const serverKey = findPluginKey(cryptAlgorithm);
            const nonce = serverKey[0..CipherChaChaKey.nonceSizeCounter64];
            const uint64 counter64 = serverKey.length == withCounter64
                ? uintDecode!(uint64, Endian.bigEndian)(serverKey[CipherChaChaKey.nonceSizeCounter64..withCounter64])
                : 0u;
            const k = toChaChaKey();
            return CipherKey(CipherChaChaKey(cast(uint)(k.length * 8), k, nonce, counter64));

        //case FbIscText.filterCryptArc4Name:
        default:
            return CipherKey(CipherSimpleKey(cast(uint)(sessionKey.length * 8), sessionKey));
    }
}

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
