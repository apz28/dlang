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

module pham.db.db_pgauth_scram;

import std.algorithm : startsWith;
import std.conv : to;
import std.string : representation;

debug(debug_pham_db_db_pgauth_scram) import std.stdio : writeln;

import pham.cp.cp_cipher : CipherHelper;
import pham.cp.cp_cipher_digest : DigestId, DigestResult, HMACS, digestOf;
import pham.cp.cp_random : CipherRandomGenerator;
import pham.utl.utl_array : ShortStringBuffer;
import pham.utl.utl_disposable : DisposingReason;
import pham.utl.utl_object : bytesFromHexs, bytesToHexs;
import pham.db.db_auth;
import pham.db.db_message;
import pham.db.db_type : DbScheme;
import pham.db.db_pgauth;
import pham.db.db_pgtype : pgAuthScram256Name, PgOIdScramSHA256FinalMessage, PgOIdScramSHA256FirstMessage;

nothrow @safe:

class PgAuthScram256 : PgAuth
{
nothrow @safe:

public:
    this()
    {
        reset();
    }

    final ResultStatus calculateProof(scope const(char)[] userName, scope const(char)[] userPassword,
        scope const(ubyte)[] serverAuthData, ref CipherBuffer!ubyte authData)
    {
        debug(debug_pham_db_db_pgauth_scram) debug writeln(__FUNCTION__, "(userName=", userName, ", serverAuthData=", serverAuthData.dgToHex(), ")");

        auto firstMessage = PgOIdScramSHA256FirstMessage(serverAuthData);
        if (!firstMessage.isValid() || !firstMessage.nonce.startsWith(this.nonce))
            return ResultStatus.error(_nextState + 1, DbMessage.eInvalidConnectionAuthServerData.fmtMessage(name, "invalid state: " ~ _nextState.to!string()));
        calculateProof(authData, userName, userPassword, firstMessage);
        return ResultStatus.ok();
    }

    final override ResultStatus getAuthData(const(int) state, scope const(char)[] userName, scope const(char)[] userPassword,
        scope const(ubyte)[] serverAuthData, ref CipherBuffer!ubyte authData)
    {
        debug(debug_pham_db_db_pgauth_scram) debug writeln(__FUNCTION__, "(_nextState=", _nextState, ", state=", state, ", userName=", userName,
            ", serverAuthData=", serverAuthData.dgToHex(), ")");

        auto status = checkAdvanceState(state);
        if (status.isError)
            return status;

        if (state == 0)
        {
            initialRequest(authData);
            return ResultStatus.ok();
        }
        else if (state == 1)
            return calculateProof(userName, userPassword, serverAuthData, authData);
        else if (state == 2)
        {
            if (!verifyServerSignature(serverAuthData))
                return ResultStatus.error(state + 1, DbMessage.eInvalidConnectionAuthVerificationFailed.fmtMessage(name));
            authData.clear();
            return ResultStatus.ok();
        }
        else
            assert(0);
    }

    final void initialRequest(ref CipherBuffer!ubyte authData) const pure scope
    {
        authData = (_cbindFlag ~ ",,n=,r=" ~ _nonce).representation();
    }

    final typeof(this) reset()
    {
        CipherRandomGenerator generator;
        ShortStringBuffer!ubyte buffer;

        _nextState = 0;
        _cbind = ['b', 'i', 'w', 's'];
        _cbindFlag = ['n'];

        enum padding = true;
        _nonce = CipherHelper.base64Encode!padding(generator.nextBytes(buffer, 18)[]);

        return this;
    }

    final bool verifyServerSignature(scope const(ubyte)[] serverAuthData) const pure
    {
        enum padding = true;

        auto finalMessage = PgOIdScramSHA256FinalMessage(serverAuthData);
        return finalMessage.signature == CipherHelper.base64Encode!padding(_serverSignature[]);
    }

    @property final override int multiStates() const @nogc pure
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
    final void calculateProof(ref CipherBuffer!ubyte authData, scope const(char)[] userName, scope const(char)[] userPassword,
        const ref PgOIdScramSHA256FirstMessage firstMessage)
    {
        debug(debug_pham_db_db_pgauth_scram) debug writeln(__FUNCTION__, "(userName=", userName, ")");

        const clientInitialRequestBare = initialRequestBare();
        const clientFinalMessageWithoutProof = finalRequestWithoutProof(firstMessage.nonce);
        scope const serverMessage = firstMessage.getMessage();
        setServerSalt(firstMessage.getSalt());
        _saltedPassword = computeScramSHA256HashPassword(userPassword, serverSalt, firstMessage.iteration);

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

        enum padding = true;
        auto clientProofBytes = clientKey;
        computeScramSHA256XOr(clientProofBytes, clientSignature);
        const clientProof = CipherHelper.base64Encode!padding(clientProofBytes[]);

        const serverKey = computeScramSHA256Hash(_saltedPassword[], "Server Key".representation);
        hmac = HMACS(DigestId.sha256, serverKey[]);
        hmac.begin()
            .digest(clientInitialRequestBare.representation())
            .digest(",".representation())
            .digest(serverMessage.representation())
            .digest(",".representation())
            .digest(clientFinalMessageWithoutProof.representation())
            .finish(_serverSignature);

        authData = (clientFinalMessageWithoutProof ~ ",p=" ~ clientProof).representation();

        debug(debug_pham_db_db_pgauth_scram) debug writeln("\t", "clientKey=", clientKey[].dgToHex(),
            ", clientProofBytes=", clientProofBytes[],
            ", clientProofBytes.length=", clientProofBytes.length,
            ", authData.length=", authData.length, ", authData=", cast(const(char)[])(authData[]));
    }

    override void doDispose(const(DisposingReason) disposingReason) nothrow @safe
    {
        _cbind[] = 0;
        _cbind = null;
        _cbindFlag[] = 0;
        _cbindFlag = null;
        _nonce[] = 0;
        _nonce = null;
        _saltedPassword.dispose(disposingReason);
        _serverSignature.dispose(disposingReason);
        super.doDispose(disposingReason);
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
        DigestResult result;
        computeScramSHA256HashPasswordInitial(result, userPassword, serverSalt);
        if (iteration > 1)
            computeScramSHA256HashPasswordIteration(result, userPassword, iteration);

        return result;
    }

    static void computeScramSHA256HashPasswordInitial(ref DigestResult result, scope const(char)[] userPassword, scope const(ubyte)[] serverSalt)
    {
        debug(debug_pham_db_db_pgauth_scram) debug writeln(__FUNCTION__, "(serverSalt=", serverSalt.dgToHex(), ")");

        enum ubyte[4] one = [0, 0, 0, 1]; // uint=1 in BigEndian

        auto hmac = HMACS(DigestId.sha256, userPassword.representation());
        hmac.begin()
            .digest(serverSalt)
            .digest(one)
            .finish(result);
    }

    static void computeScramSHA256HashPasswordIteration(ref DigestResult result, scope const(char)[] userPassword, const(int) iteration)
    {
        debug(debug_pham_db_db_pgauth_scram) debug writeln(__FUNCTION__, "(iteration=", iteration, ", result=", result[].dgToHex(), ")");

        auto hmac = HMACS(DigestId.sha256, userPassword.representation());
        DigestResult hmacResult;
        DigestResult iterationTemp = result;
        foreach (_; 1..iteration)
        {
            hmac.begin().digest(iterationTemp[]).finish(hmacResult);
            computeScramSHA256XOr(result, hmacResult);
            iterationTemp = hmacResult;
        }
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

shared static this() nothrow @safe
{
    DbAuth.registerAuthMap(DbAuthMap(pgAuthScram256Name, DbScheme.pg, &createAuthScram256));
}

DbAuth createAuthScram256()
{
    return new PgAuthScram256();
}

unittest // PgAuthScram256.computeScramSHA256HashPassword
{
    auto r = PgAuthScram256.computeScramSHA256HashPassword("masterkey", bytesFromHexs("12745ADF31A15F417F1496DA6F285551"), 4096);
    assert(r[] == bytesFromHexs("C7025D14F64AFCD68B504E933FEF597BAAD89F35E7F7167FC0F5809B21018C05"));
}
