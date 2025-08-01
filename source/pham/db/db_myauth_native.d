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

module pham.db.db_myauth_native;

import std.conv : to;

debug(debug_pham_db_db_myauth_native) import std.stdio : writeln;

import pham.cp.cp_cipher_digest : Digester, DigestId, DigestResult;
import pham.db.db_auth;
import pham.db.db_message;
import pham.db.db_type : DbScheme;
import pham.db.db_mytype : myAuthNativeName;
import pham.db.db_myauth;

nothrow @safe:

class MyAuthNative : MyAuth
{
nothrow @safe:

public:
    final override ResultStatus getAuthData(const(int) state, scope const(char)[] userName, scope const(char)[] userPassword,
        scope const(ubyte)[] serverAuthData, ref CipherBuffer!ubyte authData)
    {
        debug(debug_pham_db_db_myauth_native) debug writeln(__FUNCTION__, "(_nextState=", _nextState, ", state=", state,
            ", userName=", userName, ", serverAuthData=", serverAuthData.dgToHex(), ")");

        if (state == 0)
        {
            if (serverAuthData.length)
                setServerSalt(serverAuthData);
            return getPassword(userName, userPassword, authData);
        }
        else
        {
            authData.clear();
            return ResultStatus.ok();
        }
    }

    final override ResultStatus getPassword(scope const(char)[] userName, scope const(char)[] userPassword,
        ref CipherBuffer!ubyte authData)
    {
        debug(debug_pham_db_db_myauth_native) debug writeln(__FUNCTION__, "(userName=", userName, ")");

        if (userPassword.length == 0)
        {
            authData.clear();
            return ResultStatus.ok();
        }

        Digester digester = Digester(DigestId.sha1);

        DigestResult firstHash;
        digester.begin().digest(userPassword).finish(firstHash);

        DigestResult secondHash;
        digester.begin().digest(firstHash[]).finish(secondHash);

        DigestResult thirdHash;
        digester.begin().digest(serverSalt).digest(secondHash[]).finish(thirdHash);

        DigestResult finalHash;
        finalHash.length = thirdHash.length + 1;
        finalHash.buffer[0] = 0x14;
        finalHash.buffer[1..finalHash.length] = thirdHash[];
        foreach (i; 1..finalHash.length)
            finalHash.buffer[i] = cast(ubyte)(finalHash.buffer[i] ^ firstHash.buffer[i - 1]);
        authData = finalHash[];
        return ResultStatus.ok();
    }

    final override DbAuth setServerSalt(scope const(ubyte)[] serverSalt) pure
    {
        // if the data given to us is a null terminated string,
        // we need to trim off the trailing zero
        if (serverSalt.length && serverSalt[$ - 1] == 0)
            serverSalt = serverSalt[0..$ - 1];
        return super.setServerSalt(serverSalt);
    }

    @property final override int multiStates() const @nogc pure
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

shared static this() nothrow @safe
{
    DbAuth.registerAuthMap(DbAuthMap(myAuthNativeName, DbScheme.my, &createAuthNative));
}

DbAuth createAuthNative()
{
    return new MyAuthNative();
}

unittest // MyAuthNative.getPassword
{
    import pham.utl.utl_convert : bytesFromHexs;
    
    auto auth = new MyAuthNative();
    auth.setServerSalt(bytesFromHexs("625A1C30712F1F333E6A732543335E6A5C252613"));
    CipherBuffer!ubyte proof;
    assert(auth.getPassword("root", "masterkey", proof).isOK());
    assert(proof == bytesFromHexs("14578C3E295CC566EBD151EB8FB708A21972E80A6C"), proof.toString());
}
