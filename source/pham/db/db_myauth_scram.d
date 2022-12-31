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

module pham.db.myauth_scram;

import std.algorithm.searching : startsWith;
import std.array : Appender, split;
import std.base64 : Base64, Base64Impl;
import std.conv : to;
import std.string : representation;

version (unittest) import pham.utl.test;
import pham.cp.cipher : CipherHelper;
import pham.cp.cipher_digest : Digester, DigestId, DigestResult, HMACS;
import pham.cp.random : CipherRandomGenerator;
import pham.utl.array : ShortStringBuffer;
import pham.utl.disposable : DisposingReason;
import pham.utl.numeric_parser : NumericParsedKind, parseHexDigits, parseIntegral;
import pham.db.auth;
import pham.db.message;
import pham.db.type : DbScheme;
import pham.db.myauth;
import pham.db.mytype : myAuthScramSha1Name, myAuthScramSha256Name;

nothrow @safe:

abstract class MyAuthScram : MyAuth
{
nothrow @safe:

public:
    this(DigestId digestId) pure
    in
    {
        assert(digestId == DigestId.sha1
               || digestId == DigestId.sha256
               || digestId == DigestId.sha384
               || digestId == DigestId.sha512);
    }
    do
    {
        this.digestId = digestId;
    }

    final ResultStatus calculateProof(scope const(char)[] userName, scope const(char)[] userPassword,
        scope const(ubyte)[] serverAuthData, ref CipherBuffer authData)
    {
        version (TraceFunction) traceFunction!("pham.db.mydatabase")("_nextState=", _nextState, ", userName=", userName, ", serverAuthData=", serverAuthData.dgToHex());

        ShortStringBuffer!ubyte serverSalt;
        const(char)[] serverNonce;
        uint serverCount;
        auto parsedServerAuthData = parseServerAuthData(serverAuthData);
        auto status = isInvalidServerAuthData(parsedServerAuthData, serverSalt, serverNonce, serverCount);
        if (status.isError)
            return status;

        this.salted = hi(userPassword.representation(), serverSalt[], serverCount);
        alias Base64NoPadding = Base64Impl!('!', '=', Base64.NoPadding);
        const userProof = Base64NoPadding.encode(("n,a=" ~ userName ~ ",").representation());
        const withoutProof = "c=" ~ userProof ~ ",r=" ~ serverNonce;
        this.auth = (this.client ~ "," ~ cast(const(char)[])serverAuthData ~ "," ~ withoutProof).representation();
        auto ckey = hmacOf(salted, "Client Key".representation());
        ckey ^= hmacOf(hashOf(ckey[])[], auth)[];

        enum padding = false;
        auto result = withoutProof ~ ",p=" ~ CipherHelper.base64Encode!padding(ckey[]);
        authData = CipherBuffer(result.representation());
        return ResultStatus.ok();
    }

    final override ResultStatus getAuthData(const(int) state, scope const(char)[] userName, scope const(char)[] userPassword,
        scope const(ubyte)[] serverAuthData, ref CipherBuffer authData)
    {
        version (TraceFunction) traceFunction!("pham.db.mydatabase")("_nextState=", _nextState, ", state=", state, ", userName=", userName, ", serverAuthData=", serverAuthData.dgToHex());

        auto status = checkAdvanceState(state);
        if (status.isError)
            return status;

        if (state == 0)
        {
            authData = getInitial(userName, userPassword);
            return ResultStatus.ok();
        }
        else if (state == 1)
            return calculateProof(userName, userPassword, serverAuthData, authData);
        else if (state == 2)
        {
            authData = CipherBuffer.init;
            return isValidSignature(serverAuthData);
        }
        else
            assert(0);
    }

    final CipherBuffer getInitial(scope const(char)[] userName, scope const(char)[] userPassword)
    {
        if (this.cnonce.length == 0)
        {
            CipherRandomGenerator generator;
            ShortStringBuffer!char buffer;
            this.cnonce = generator.nextAlphaNumCharacters(buffer, 32)[].dup;
        }
        this.client = "n=" ~ normalize(userName) ~ ",r=" ~ this.cnonce;
        return CipherBuffer(("n,a=" ~ normalize(userName) ~ "," ~ this.client).representation());
    }

    final ResultStatus isValidSignature(scope const(ubyte)[] serverAuthData)
    {
    try {
        const scope response = cast(const(char)[])serverAuthData;

        if (!response.startsWith("v="))
            return ResultStatus.error(2, "challenge did not start with a signature", DbMessage.eInvalidConnectionAuthServerData);

        enum padding = false;
        const signature = CipherHelper.base64Decode!padding(response[2..$]);
        const skey = hmacOf(this.salted, "Server Key".representation());
        const calculated = hmacOf(skey[], this.auth);

        if (signature.length != calculated.length)
            return ResultStatus.error(3, "challenge contained a signature with an invalid length", DbMessage.eInvalidConnectionAuthServerData);
        if (signature != calculated[])
            return ResultStatus.error(3, "challenge contained an invalid signature", DbMessage.eInvalidConnectionAuthServerData);

        return ResultStatus.ok();
    } catch (Exception) return ResultStatus.error(1, "challenge is not valid", DbMessage.eInvalidConnectionAuthServerData);
    }

    static string normalize(scope const(char)[] str)
    {
        auto buffer = Appender!string();
        buffer.reserve(str.length);

        foreach (char c; str)
        {
            switch (c)
            {
                case ',':
                    buffer.put("=2C");
                    break;
                case '=':
                    buffer.put("=3D");
                    break;
                default:
                    buffer.put(c);
                    break;
            }
        }

        return buffer.data;
    }

    static const(char)[][char] parseServerAuthData(scope const(ubyte)[] serverAuthData) @trusted
    {
        const(char)[][char] result;
        foreach (scope part; (cast(string)serverAuthData).split(","))
        {
            if (part.length >= 2 && part[1] == '=')
                result[part[0]] = part[2..$].dup;
        }

        return result;
    }

    @property final override int multiStates() const @nogc pure
    {
        return 3;
    }

protected:
    override void doDispose(const(DisposingReason) disposingReason) nothrow @safe
    {
        client[] = 0;
        client = null;
        cnonce[] = 0;
        cnonce = null;
        auth[] = 0;
        auth = null;
        salted[] = 0;
        salted = null;
        super.doDispose(disposingReason);
    }

    final DigestResult hashOf(scope const(ubyte)[] str)
    {
        auto digester = Digester(digestId);
        DigestResult result;
        digester.begin().digest(str).finish(result);
        return result;
    }

    // Hi(str, salt, i):
    //
    // U1   := HMACSHA1(str, salt + INT(1))
    // U2   := HMACSHA1(str, U1)
    // ...
    // Ui-1 := HMACSHA1(str, Ui-2)
    // Ui   := HMACSHA1(str, Ui-1)
    //
    // Hi := U1 XOR U2 XOR ... XOR Ui
    //
    // where "i" is the iteration count, "+" is the string concatenation
    // operator, and INT(g) is a 4-octet encoding of the integer g, most
    // significant octet first.
    //
    // Hi() is, essentially, PBKDF2 [RFC2898] with HMACSHA1() as the
    // pseudorandom function (PRF) and with dkLen == output length of
    // HMACSHA1() == output length of H().
    final ubyte[] hi(scope const(ubyte)[] key, scope const(ubyte)[] salt, uint count)
    {
        auto hmac = HMACS(digestId, key);

        auto salt1 = ShortStringBuffer!ubyte(salt);
        salt1.put(0);
        salt1.put(0);
        salt1.put(0);
        salt1.put(1);

        DigestResult result;
        hmac.begin().digest(salt1[]).finish(result);
        auto u1 = result;
        while (--count)
        {
            DigestResult u2;
            hmac.begin().digest(u1[]).finish(u2);
            result ^= u2[];
            u1 = u2;
        }
        return result[].dup;
    }

    final DigestResult hmacOf(scope const(ubyte)[] key, scope const(ubyte)[] str)
    {
        auto hmac = HMACS(digestId, key);
        DigestResult result;
        hmac.begin().digest(str).finish(result);
        return result;
    }

    final ResultStatus isInvalidServerAuthData(const(char)[][char] serverAuthData,
        ref ShortStringBuffer!ubyte salt, ref const(char)[] nonce, ref uint count)
    {
        // salt is missing?
        if (auto val = 's' in serverAuthData)
        {
            auto s = *val;
            if (parseHexDigits(s, salt) == 0)
                return ResultStatus.error(1, "salt is invalid", DbMessage.eInvalidConnectionAuthServerData);
        }
        else
            return ResultStatus.error(1, "salt is missing", DbMessage.eInvalidConnectionAuthServerData);

        // nonce is missing?
        if (auto val = 'r' in serverAuthData)
        {
            nonce = *val;
            // invalid nonce?
            if (!nonce.startsWith(this.cnonce))
                return ResultStatus.error(3, "nonce is invalid", DbMessage.eInvalidConnectionAuthServerData);
        }
        else
            return ResultStatus.error(2, "nonce is missing", DbMessage.eInvalidConnectionAuthServerData);

        // iteration count is missing?
        if (auto val = 'i' in serverAuthData)
        {
            auto s = *val;
            // invalid iteration count?
            if (parseIntegral(s, count) != NumericParsedKind.ok)
                return ResultStatus.error(5, "iteration count is invalid", DbMessage.eInvalidConnectionAuthServerData);
        }
        else
            return ResultStatus.error(4, "iteration count is missing", DbMessage.eInvalidConnectionAuthServerData);

        return ResultStatus.ok();
    }

private:
    DigestId digestId;
    char[] client, cnonce;
    ubyte[] auth, salted;
}

class MyAuthScramSha1 : MyAuthScram
{
nothrow @safe:

public:
    this()
    {
        super(DigestId.sha1);
    }

    @property final override string name() const pure
    {
        return myAuthScramSha1Name;
    }
}

class MyAuthScramSha256 : MyAuthScram
{
nothrow @safe:

public:
    this()
    {
        super(DigestId.sha256);
    }

    @property final override string name() const pure
    {
        return myAuthScramSha256Name;
    }
}


// Any below codes are private
private:

shared static this()
{
    DbAuth.registerAuthMap(DbAuthMap(myAuthScramSha1Name, DbScheme.my, &createAuthScramSha1));
    DbAuth.registerAuthMap(DbAuthMap(myAuthScramSha256Name, DbScheme.my, &createAuthScramSha256));
}

DbAuth createAuthScramSha1()
{
    return new MyAuthScramSha1();
}

DbAuth createAuthScramSha256()
{
    return new MyAuthScramSha256();
}


private:

unittest // MyAuthScramSha1
{
    import pham.utl.test;
    traceUnitTest!("pham.db.mydatabase")("unittest pham.db.myauth_scram.MyAuthScramSha1");

}

unittest // MyAuthScramSha256
{
    import pham.utl.test;
    traceUnitTest!("pham.db.mydatabase")("unittest pham.db.myauth_scram.MyAuthScramSha256");

}
