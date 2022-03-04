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
import std.string : assumeUTF, representation;

version (unittest) import pham.utl.test;
import pham.cp.cipher : CipherHelper;
import pham.cp.cipher_digest : Digester, DigestId, DigestResult, HMACS;
import pham.cp.random : CipherRandomGenerator;
import pham.utl.utf8 : NumericParsedKind, parseHexDigits, parseIntegral, ShortStringBuffer;
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
    this(DigestId digestId)
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

    final const(ubyte)[] calculateProof(scope const(char)[] userName, scope const(char)[] userPassword, const(ubyte)[] serverAuthData)
    {
        version (TraceFunction) traceFunction!("pham.db.mydatabase")("_nextState=", _nextState, ", userName=", userName, ", serverAuthData=", serverAuthData);

        ShortStringBuffer!ubyte serverSalt;
        const(char)[] serverNonce;
        uint serverCount;
        auto parsedServerAuthData = parseServerAuthData(serverAuthData);
        if (isInvalidServerAuthData(parsedServerAuthData, serverSalt, serverNonce, serverCount))
            return null;

        this.salted = hi(userPassword.representation, serverSalt[], serverCount);
        alias Base64NoPadding = Base64Impl!('!', '=', Base64.NoPadding);
        const userProof = Base64NoPadding.encode(("n,a=" ~ userName ~ ",").representation);
        const withoutProof = "c=" ~ userProof ~ ",r=" ~ serverNonce;
        this.auth = (this.client ~ "," ~ serverAuthData.assumeUTF ~ "," ~ withoutProof).representation;
        auto ckey = hmacOf(salted, "Client Key".representation);
        ckey ^= hmacOf(hashOf(ckey[])[], auth)[];

        enum padding = false;
        auto result = withoutProof ~ ",p=" ~ CipherHelper.base64Encode!padding(ckey[]);
        return result.representation;
    }

    final override const(ubyte)[] getAuthData(const(int) state, scope const(char)[] userName, scope const(char)[] userPassword,
        const(ubyte)[] serverAuthData)
    {
        version (TraceFunction) traceFunction!("pham.db.mydatabase")("_nextState=", _nextState, ", state=", state, ", userName=", userName, ", serverAuthData=", serverAuthData);

        if (state != _nextState || state > 2)
        {
            setError(state + 1, to!string(state), DbMessage.eInvalidConnectionAuthServerData);
            return null;
        }

        _nextState++;
        if (state == 0)
            return getInitial(userName, userPassword);
        else if (state == 1)
            return calculateProof(userName, userPassword, serverAuthData);
        else if (state == 2)
        {
            isValidSignature(serverAuthData);
            return null;
        }
        else
            assert(0);
    }

    final const(ubyte)[] getInitial(scope const(char)[] userName, scope const(char)[] userPassword)
    {
        if (this.cnonce.length == 0)
        {
            CipherRandomGenerator generator;
            ShortStringBuffer!char buffer;
            this.cnonce = generator.nextAlphaNumCharacters(buffer, 32)[].dup;
        }
        this.client = "n=" ~ normalize(userName) ~ ",r=" ~ this.cnonce;
        return ("n,a=" ~ normalize(userName) ~ "," ~ this.client).representation;
    }

    final override const(ubyte)[] getPassword(scope const(char)[] userName, scope const(char)[] userPassword, const(ubyte)[] serverAuthData)
    {
        return null;
    }

    final int isValidSignature(scope const(ubyte)[] serverAuthData)
    {
        scope (failure)
            return setError(1, "challenge is not valid", DbMessage.eInvalidConnectionAuthServerData).errorCode;

        const scope response = cast(const(char)[])serverAuthData;

        if (!response.startsWith("v="))
            return setError(2, "challenge did not start with a signature", DbMessage.eInvalidConnectionAuthServerData).errorCode;

        enum padding = false;
        const signature = CipherHelper.base64Decode!padding(response[2..$]);
        const skey = hmacOf(this.salted, "Server Key".representation);
        const calculated = hmacOf(skey[], this.auth);

        if (signature.length != calculated.length)
            return setError(3, "challenge contained a signature with an invalid length", DbMessage.eInvalidConnectionAuthServerData).errorCode;
        if (signature != calculated[])
            return setError(3, "challenge contained an invalid signature", DbMessage.eInvalidConnectionAuthServerData).errorCode;

        return 0;
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

    static const(char)[][char] parseServerAuthData(const(ubyte)[] serverAuthData)
    {
        auto buffer = Appender!string();
        const(char)[][char] result;

        foreach (part; serverAuthData.assumeUTF.split(","))
        {
            if (part.length >= 2 && part[1] == '=')
                result[part[0]] = part[2..$];
        }

        return result;
    }

    @property final override int multiSteps() const @nogc pure
    {
        return 3;
    }

protected:
    override void doDispose(bool disposing)
    {
        client[] = 0;
        cnonce[] = 0;
        auth[] = 0;
        salted[] = 0;
        if (disposing)
        {
            client = null;
            cnonce = null;
            auth = null;
            salted = null;
        }
        super.doDispose(disposing);
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

    final int isInvalidServerAuthData(const(char)[][char] serverAuthData,
        ref ShortStringBuffer!ubyte salt, ref const(char)[] nonce, ref uint count)
    {
        // salt is missing?
        if (auto val = 's' in serverAuthData)
        {
            auto s = *val;
            if (parseHexDigits(s, salt) == 0)
                return setError(1, "salt is invalid", DbMessage.eInvalidConnectionAuthServerData).errorCode;
        }
        else
            return setError(1, "salt is missing", DbMessage.eInvalidConnectionAuthServerData).errorCode;

        // nonce is missing?
        if (auto val = 'r' in serverAuthData)
        {
            nonce = *val;
            // invalid nonce?
            if (!nonce.startsWith(this.cnonce))
                return setError(3, "nonce is invalid", DbMessage.eInvalidConnectionAuthServerData).errorCode;
        }
        else
            return setError(2, "nonce is missing", DbMessage.eInvalidConnectionAuthServerData).errorCode;

        // iteration count is missing?
        if (auto val = 'i' in serverAuthData)
        {
            auto s = *val;
            // invalid iteration count?
            if (parseIntegral(s, count) != NumericParsedKind.ok)
                return setError(5, "iteration count is invalid", DbMessage.eInvalidConnectionAuthServerData).errorCode;
        }
        else
            return setError(4, "iteration count is missing", DbMessage.eInvalidConnectionAuthServerData).errorCode;

        return 0;
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
