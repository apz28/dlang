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

import pham.db.message;
import pham.db.auth;

nothrow @safe:

struct FbAuthMap
{
nothrow @safe:

public:
    bool isValid() const pure
    {
        return name.length != 0 && createAuth !is null;
    }

public:
    string name;
    FbAuth function() nothrow @safe createAuth;
}

abstract class FbAuth : DbAuth
{
nothrow @safe:

public:
    abstract bool canCryptedConnection() const pure;
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

    bool parseServerAuthData(ubyte[] serverAuthData, ref ubyte[] serverSalt, ref ubyte[] serverPublicKey)
    {
        version (TraceAuth)
        auto serverAuthDataOrg = serverAuthData;

        enum minLength = 3; // two leading size data + at least 1 byte data

        // Min & Max length?
        size_t maxSaltLength;
        if (serverAuthData.length < minLength || serverAuthData.length > maxSizeServerAuthData(maxSaltLength))
        {
            setError(1, DbMessage.eInvalidConnectionMalformServerData);
            return false;
        }

		const saltLength = serverAuthData[0] + (cast(size_t)serverAuthData[1] << 8);
        serverAuthData = serverAuthData[2..$]; // Skip the length data
        if (saltLength > maxSaltLength || saltLength > serverAuthData.length)
        {
            setError(1, DbMessage.eInvalidConnectionMalformServerData);
            return false;
        }
        serverSalt = serverAuthData[0..saltLength];
        serverAuthData = serverAuthData[saltLength..$]; // Skip salt data
        if (serverAuthData.length < minLength)
        {
            setError(1, DbMessage.eInvalidConnectionMalformServerData);
            return false;
        }

		const keyLength = serverAuthData[0] + (cast(size_t)serverAuthData[1] << 8);
        if (keyLength + 2 > serverAuthData.length)
        {
            setError(1, DbMessage.eInvalidConnectionMalformServerData);
            return false;
        }

        serverPublicKey = serverAuthData[2..keyLength + 2];

        this._serverPublicKey = serverPublicKey;
        this._serverSalt = serverSalt;

        version (TraceAuth)
        {
            import pham.utl.utltest;
            dgFunctionTrace("keyLength=", keyLength,
                ", saltLength=", saltLength,
                ", serverAuthDataLength=", serverAuthDataOrg.length,
                ", serverPublicKey=", serverPublicKey.dgToHex(),
                ", serverSalt=", serverSalt.dgToHex(),
                ", serverAuthData=", serverAuthDataOrg.dgToHex());
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

    static FbAuthMap findAuthMap(string name) @trusted //@trusted=__gshared
    {
        foreach (m; _authMaps)
        {
            if (m.name == name)
                return m;
        }
        return FbAuthMap.init;
    }

    static void registerAuthMap(FbAuthMap authMap) @trusted //@trusted=__gshared
    in
    {
        assert(authMap.isValid());
    }
    do
    {
        foreach (i, m; _authMaps)
        {
            if (m.name == authMap.name)
            {
                _authMaps[i].createAuth = authMap.createAuth;
                return;
            }
        }
        _authMaps ~= authMap;
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

private:
    __gshared static FbAuthMap[] _authMaps;
}

unittest // FbAuth.normalizeUserName
{
    import pham.utl.utltest;
    traceUnitTest("unittest db.FbAuth.normalizeUserName");

    assert(FbAuth.normalizeUserName("sysdba") == "SYSDBA");
    assert(FbAuth.normalizeUserName("\"sysdba\"") == "sysdba");
}
