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
import std.string : representation;

version (unittest) import pham.utl.test;
import pham.cp.cipher_digest : DigestId, DigestResult, HMACS, digestOf;
import pham.utl.object : bytesFromHexs, bytesToHexs, randomCharacters;
import pham.db.type : DbScheme;
import pham.db.auth;
import pham.db.pgtype;

nothrow @safe:

class PgAuthScram256 : DbAuth
{
nothrow @safe:

public:
    this() pure
    {
        reset();
    }

    final override const(ubyte)[] getAuthData(scope const(char)[] userName, scope const(char)[] userPassword, const(ubyte)[] serverAuthData)
    {
        auto firstMessage = PgOIdScramSHA256FirstMessage(serverAuthData);
        if (!firstMessage.isValid() || !firstMessage.nonce.startsWith(this.nonce))
            return null;

        return cast(const(ubyte)[])calculateProof(userPassword, firstMessage);
    }

    const(char)[] finalRequestWithoutProof(scope const(char)[] serverNonce) const pure scope
    {
        return "c=" ~ _cbind ~ ",r=" ~ serverNonce;
    }

    const(char)[] initialRequest() const pure scope
    {
        return _cbindFlag ~ ",,n=,r=" ~ _nonce;
    }

    const(char)[] initialRequestBare() const pure scope
    {
        return "n=,r=" ~ _nonce;
    }

    typeof(this) reset() pure
    {
        _cbind = ['b', 'i', 'w', 's'];
        _cbindFlag = ['n'];
        _mechanism = ['S', 'C', 'R', 'A', 'M', '-', 'S', 'H', 'A', '-', '2', '5', '6'];
        _nonce = Base64.encode(randomCharacters(18).representation);
        return this;
    }

    final bool verifyServerSignature(const(ubyte)[] serverAuthData) const pure
    {
        auto finalMessage = PgOIdScramSHA256FinalMessage(serverAuthData);
        return finalMessage.signature == Base64.encode(_serverSignature.value());
    }

    @property final const(char)[] mechanism() const pure
    {
        return _mechanism;
    }

    @property final override string name() const
    {
        return authScram256Name;
    }

    @property final const(char)[] nonce() const pure
    {
        return _nonce;
    }

public:
    static immutable string authScram256Name = "scram-sha-256";

protected:
    final const(char)[] calculateProof(scope const(char)[] userPassword, const(PgOIdScramSHA256FirstMessage) firstMessage)
    {
        const clientInitialRequestBare = initialRequestBare();
        const clientFinalMessageWithoutProof = finalRequestWithoutProof(firstMessage.nonce);
        const serverMessage = firstMessage.getMessage();
        const serverSalt = firstMessage.getSalt();
        _saltedPassword = computeScramSHA256HashPassword(userPassword, serverSalt, firstMessage.getIteration());

        auto clientKey = computeScramSHA256Hash(_saltedPassword.value(), "Client Key".representation);
        const storedKey = digestOf!(DigestId.sha256)(clientKey.value());
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
        const clientProof = Base64.encode(clientProofBytes.value());

        const serverKey = computeScramSHA256Hash(_saltedPassword.value(), "Server Key".representation);
        hmac = HMACS(DigestId.sha256, serverKey.value());
        hmac.begin()
            .digest(clientInitialRequestBare.representation)
            .digest(",".representation)
            .digest(serverMessage.representation)
            .digest(",".representation)
            .digest(clientFinalMessageWithoutProof.representation)
            .finish(_serverSignature);

        const result = clientFinalMessageWithoutProof ~ ",p=" ~ clientProof;

        version (TraceFunction)
        dgFunctionTrace("clientKey=", bytesToHexs(clientKey.value()),
            ", clientProofBytes=", bytesToHexs(clientProofBytes.value()),
            ", clientProofBytes.length=", clientProofBytes.length,
            ", result.length=", result.length, ", result=", result);

        return result;
    }

    override void doDispose(bool disposing) nothrow
    {
        _cbind[] = 0;
        _cbindFlag[] = 0;
        _mechanism[] = 0;
        _nonce[] = 0;
        _saltedPassword.dispose(disposing);
        _serverSignature.dispose(disposing);

        if (disposing)
        {
            _cbind = null;
            _cbindFlag = null;
            _mechanism = null;
            _nonce = null;
        }

        super.doDispose(disposing);
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
                hmac.begin()
                    .digest(iterationTemp.value())
                    .finish(temp);
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
    char[] _mechanism;
    char[] _nonce;
    DigestResult _saltedPassword;
    DigestResult _serverSignature;
}


// Any below codes are private
private:

shared static this()
{
    DbAuth.registerAuthMap(DbAuthMap(DbScheme.pg ~ PgAuthScram256.authScram256Name, &createAuthScram256));
}

DbAuth createAuthScram256()
{
    return new PgAuthScram256();
}
