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

module pham.db.pgauth_scram;

import std.algorithm : startsWith;
import std.base64 : Base64;
import std.conv : to;
import std.string : representation;

version (unittest) import pham.utl.test;
import pham.cp.cipher_digest : DigestId, DigestResult, HMACS, digestOf;
import pham.cp.random : CipherRandomGenerator;
import pham.utl.object : bytesFromHexs, bytesToHexs;
import pham.utl.utf8 : ShortStringBuffer;
import pham.db.auth;
import pham.db.message;
import pham.db.type : DbScheme;
import pham.db.pgauth;
import pham.db.pgtype : pgAuthScram256Name, PgOIdScramSHA256FinalMessage, PgOIdScramSHA256FirstMessage;

nothrow @safe:

class PgAuthScram256 : PgAuth
{
nothrow @safe:

public:
    this()
    {
        reset();
    }

    final const(ubyte)[] calculateProof(scope const(char)[] userName, scope const(char)[] userPassword, const(ubyte)[] serverAuthData)
    {
        version (TraceFunction) traceFunction!("pham.db.pgdatabase")("userName=", userName, ", serverAuthData=", serverAuthData);

         auto firstMessage = PgOIdScramSHA256FirstMessage(serverAuthData);
         if (!firstMessage.isValid() || !firstMessage.nonce.startsWith(this.nonce))
         {
             setError(_nextState + 1, to!string(_nextState), DbMessage.eInvalidConnectionAuthServerData);
             return null;
         }
         return calculateProof(userName, userPassword, firstMessage).representation();
    }

    final override const(ubyte)[] getAuthData(const(int) state, scope const(char)[] userName, scope const(char)[] userPassword,
        const(ubyte)[] serverAuthData)
    {
        version (TraceFunction) traceFunction!("pham.db.pgdatabase")("_nextState=", _nextState, ", state=", state, ", userName=", userName, ", serverAuthData=", serverAuthData);

        if (state != _nextState || state > 2)
        {
            setError(state + 1, to!string(state), DbMessage.eInvalidConnectionAuthServerData);
            return null;
        }

        _nextState++;
        if (state == 0)
            return initialRequest().representation();
        else if (state == 1)
            return calculateProof(userName, userPassword, serverAuthData);
        else if (state == 2)
        {
            if (!verifyServerSignature(serverAuthData))
                setError(state + 1, null, DbMessage.eInvalidConnectionAuthVerificationFailed);
            return null;
        }
        else
            assert(0);
    }

    final const(char)[] initialRequest() const pure scope
    {
        return _cbindFlag ~ ",,n=,r=" ~ _nonce;
    }

    final typeof(this) reset()
    {
        CipherRandomGenerator generator;
        ShortStringBuffer!ubyte buffer;

        _nextState = 0;
        _cbind = ['b', 'i', 'w', 's'];
        _cbindFlag = ['n'];
        _nonce = Base64.encode(generator.nextBytes(buffer, 18)[]);
        return this;
    }

    final bool verifyServerSignature(const(ubyte)[] serverAuthData) const pure
    {
        auto finalMessage = PgOIdScramSHA256FinalMessage(serverAuthData);
        return finalMessage.signature == Base64.encode(_serverSignature[]);
    }

    @property final override int multiSteps() const @nogc pure
    {
        return 3;
    }

    @property final override string name() const pure
    {
        return pgAuthScram256Name;
    }

    @property final const(char)[] nonce() const pure
    {
        return _nonce;
    }

protected:
    final const(char)[] calculateProof(scope const(char)[] userName, scope const(char)[] userPassword, const(PgOIdScramSHA256FirstMessage) firstMessage)
    {
        version (TraceFunction) traceFunction!("pham.db.pgdatabase")();

        const clientInitialRequestBare = initialRequestBare();
        const clientFinalMessageWithoutProof = finalRequestWithoutProof(firstMessage.nonce);
        const serverMessage = firstMessage.getMessage();
        const serverSalt = firstMessage.getSalt();
        _saltedPassword = computeScramSHA256HashPassword(userPassword, serverSalt, firstMessage.getIteration());

        auto clientKey = computeScramSHA256Hash(_saltedPassword[], "Client Key".representation);
        const storedKey = digestOf!(DigestId.sha256)(clientKey[]);
        DigestResult clientSignature;
        auto hmac = HMACS(DigestId.sha256, storedKey);
        hmac.begin()
            .digest(clientInitialRequestBare.representation)
            .digest(",".representation)
            .digest(serverMessage.representation)
            .digest(",".representation)
            .digest(clientFinalMessageWithoutProof.representation)
            .finish(clientSignature);

        auto clientProofBytes = clientKey;
        computeScramSHA256XOr(clientProofBytes, clientSignature);
        const clientProof = Base64.encode(clientProofBytes[]);

        const serverKey = computeScramSHA256Hash(_saltedPassword[], "Server Key".representation);
        hmac = HMACS(DigestId.sha256, serverKey[]);
        hmac.begin()
            .digest(clientInitialRequestBare.representation)
            .digest(",".representation)
            .digest(serverMessage.representation)
            .digest(",".representation)
            .digest(clientFinalMessageWithoutProof.representation)
            .finish(_serverSignature);

        const result = clientFinalMessageWithoutProof ~ ",p=" ~ clientProof;

        version (TraceFunction)
        traceFunction!("pham.db.pgdatabase")("clientKey=", clientKey[],
            ", clientProofBytes=", clientProofBytes[],
            ", clientProofBytes.length=", clientProofBytes.length,
            ", result.length=", result.length, ", result=", result);

        return result;
    }

    override void doDispose(bool disposing) nothrow
    {
        _cbind[] = 0;
        _cbindFlag[] = 0;
        _nonce[] = 0;
        _saltedPassword.dispose(disposing);
        _serverSignature.dispose(disposing);

        if (disposing)
        {
            _cbind = null;
            _cbindFlag = null;
            _nonce = null;
        }

        super.doDispose(disposing);
    }

    final const(char)[] finalRequestWithoutProof(scope const(char)[] serverNonce) const pure scope
    {
        return "c=" ~ _cbind ~ ",r=" ~ serverNonce;
    }

    final const(char)[] initialRequestBare() const pure scope
    {
        return "n=,r=" ~ _nonce;
    }

private:
    static DigestResult computeScramSHA256Hash(scope const(ubyte)[] key, scope const(ubyte)[] data)
    {
        DigestResult result;
        auto hmac = HMACS(DigestId.sha256, key);
        hmac.begin()
            .digest(data)
            .finish(result);
        return result;
    }

    static DigestResult computeScramSHA256HashPassword(scope const(char)[] userPassword, scope const(ubyte)[] serverSalt, const(int) iteration)
    {
        enum ubyte[4] one = [0, 0, 0, 1]; // uint=1 in BigEndian

        DigestResult result;
        auto hmac = HMACS(DigestId.sha256, userPassword.representation);
        hmac.begin()
            .digest(serverSalt)
            .digest(one)
            .finish(result);

        if (iteration > 1)
        {
            DigestResult iterationTemp = result;
            foreach (_; 1..iteration)
            {
                DigestResult temp;
                hmac.begin().digest(iterationTemp[]).finish(temp);
                computeScramSHA256XOr(result, temp);
                iterationTemp = temp;
            }
        }

        return result;
    }

    pragma(inline, true)
    static void computeScramSHA256XOr(ref DigestResult holder, scope const(DigestResult) other) pure
    in
    {
        assert(holder.length == other.length);
    }
    do
    {
        foreach (i; 0..holder.length)
            holder.buffer[i] ^= other.buffer[i];
    }

private:
    char[] _cbind;
    char[] _cbindFlag;
    char[] _nonce;
    DigestResult _saltedPassword;
    DigestResult _serverSignature;
}


// Any below codes are private
private:

shared static this()
{
    DbAuth.registerAuthMap(DbAuthMap(pgAuthScram256Name, DbScheme.pg, &createAuthScram256));
}

DbAuth createAuthScram256()
{
    return new PgAuthScram256();
}
