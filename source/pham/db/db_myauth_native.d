/*
*
* License: $(HTTP www.boost.org/LICENSE_1_0.txt, Boost License 1.0).
* Authors: An Pham
*
* Copyright An Pham 2021 - xxxx.
* Distributed under the Boost Software License, Version 1.0.
* (See accompanying file LICENSE.txt or copy at http://www.boost.org/LICENSE_1_0.txt)
*
*/

module pham.db.myauth_native;

import std.conv : to;

version (unittest) import pham.utl.test;
import pham.cp.cipher_digest;
import pham.db.auth;
import pham.db.message;
import pham.db.type : DbScheme;
import pham.db.mytype : myAuthNativeName;
import pham.db.myauth;

nothrow @safe:

class MyAuthNative : MyAuth
{
nothrow @safe:

public:
    final override const(ubyte)[] getAuthData(const(int) state, scope const(char)[] userName, scope const(char)[] userPassword,
        const(ubyte)[] serverAuthData)
    {
        version (TraceFunction) traceFunction!("pham.db.mydatabase")("_nextState=", _nextState, ", state=", state, ", userName=", userName, ", serverAuthData=", serverAuthData);

        if (state != _nextState || state != 0)
        {
            setError(state + 1, to!string(state), DbMessage.eInvalidConnectionAuthServerData);
            return null;
        }

        _nextState++;
        return getPassword(userName, userPassword, serverAuthData);
    }

    final override const(ubyte)[] getPassword(scope const(char)[] userName, scope const(char)[] userPassword, const(ubyte)[] serverAuthData)
    {
        if (userPassword.length == 0)
            return null;

        // if the data given to us is a null terminated string, we need to trim off the trailing zero
        size_t seedLength = serverAuthData.length;
        while (seedLength && serverAuthData[seedLength - 1] == 0)
            seedLength--;

        Digester digester = Digester(DigestId.sha1);

        DigestResult firstHash;
        digester.begin().digest(userPassword).finish(firstHash);

        DigestResult secondHash;
        digester.begin().digest(firstHash[]).finish(secondHash);

        DigestResult thirdHash;
        digester.begin().digest(serverAuthData[0..seedLength]).digest(secondHash[]).finish(thirdHash);

        DigestResult finalHash;
        finalHash.length = thirdHash.length + 1;
        finalHash.buffer[0] = 0x14;
        finalHash.buffer[1..finalHash.length] = thirdHash[];
        foreach (i; 1..finalHash.length)
            finalHash.buffer[i] = cast(ubyte)(finalHash.buffer[i] ^ firstHash.buffer[i - 1]);
        return finalHash[].dup;
    }

    @property final override int multiSteps() const @nogc pure
    {
        return 1;
    }

    @property final override string name() const pure
    {
        return myAuthNativeName;
    }
}


// Any below codes are private
private:

shared static this()
{
    DbAuth.registerAuthMap(DbAuthMap(myAuthNativeName, DbScheme.my, &createAuthNative));
}

DbAuth createAuthNative()
{
    return new MyAuthNative();
}

unittest
{
    import pham.utl.test;
    traceUnitTest!("pham.db.mydatabase")("unittest pham.db.myauth_native.MyAuthNative.getPassword");

    auto auth = new MyAuthNative();
    auto proof = auth.getPassword("root", "masterkey", bytesFromHexs("625A1C30712F1F333E6A732543335E6A5C252613"));
    assert(proof == bytesFromHexs("14578C3E295CC566EBD151EB8FB708A21972E80A6C"), bytesToHexs(proof));
}
