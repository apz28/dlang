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

module pham.db.myauth_sha;

import std.string : representation;

version (unittest) import pham.utl.test;
import pham.cp.cipher_digest : Digester, DigestId, DigestResult;
import pham.db.auth;
import pham.db.message;
import pham.db.type : DbScheme;
import pham.db.myauth;
import pham.db.mytype : myAuthSha256Mem, myAuthSha2Caching;

nothrow @safe:

abstract class MyAuthSha : MyAuth
{
nothrow @safe:

public:
    final CipherBuffer!ubyte calculateAuth(scope const(char)[] userName, scope const(char)[] userPassword,
        scope const(ubyte)[] nonce)
    {
        version (TraceFunction) traceFunction("userName=", userName, ", nonce=", nonce.dgToHex());

        if (userPassword.length == 0)
            return CipherBuffer!ubyte.init;

        auto digester = Digester(DigestId.sha256);

        DigestResult firstHash = void;
        digester.begin().digest(userPassword).finish(firstHash);

        DigestResult secondHash = void;
        digester.begin().digest(firstHash[]).finish(secondHash);

        DigestResult thirdHash = void;
        digester.begin().digest(secondHash[]).digest(nonce).finish(thirdHash);

        return xor(firstHash[], thirdHash[]);
    }

    final override ResultStatus getPassword(scope const(char)[] userName, scope const(char)[] userPassword,
        ref CipherBuffer!ubyte authData)
    {
        version (TraceFunction) traceFunction("userName=", userName);

        return getPasswordEx(userName, userPassword, true, authData);
    }

    final override DbAuth setServerSalt(scope const(ubyte)[] serverSalt) pure
    {
        version (TraceFunction) traceFunction("serverSalt=", serverSalt.dgToHex());

        // if the data given to us is a null terminated string,
        // we need to trim off the trailing zero
        if (serverSalt.length && serverSalt[$ - 1] == 0)
            serverSalt = serverSalt[0..$ - 1];
        return super.setServerSalt(serverSalt);
    }

protected:
    final ResultStatus getPasswordEx(scope const(char)[] userName, scope const(char)[] userPassword,
        bool leadingIndicator, ref CipherBuffer!ubyte authData)
    {
        if (userPassword.length == 0)
            authData = CipherBuffer!ubyte([0x00]);
        else
        {
            auto auth = calculateAuth(userName, userPassword, serverSalt);
            authData = leadingIndicator ? CipherBuffer!ubyte([0x20]) : CipherBuffer!ubyte([]);
            authData.put(auth[]);
        }

        version (TraceFunction) traceFunction("userName=", userName, ", leadingIndicator=", leadingIndicator, ", result=", authData[].dgToHex());

        return ResultStatus.ok();
    }

    static CipherBuffer!ubyte xor(scope const(ubyte)[] left, scope const(ubyte)[] right) pure
    {
        const len = left.length;
        if (len == 0 || len != right.length)
            return CipherBuffer!ubyte.init;

        CipherBuffer!ubyte result;
        foreach (i; 0..len)
        {
            result.put(left[i] ^ right[i]);
        }

        version (TraceFunction) traceFunction("left=", left.dgToHex(), ", right=", right.dgToHex(), ", result=", result[].dgToHex());

        return result;
    }

    static CipherBuffer!ubyte xorNonce(scope const(ubyte)[] src, scope const(ubyte)[] nonce) pure
    {
        CipherBuffer!ubyte result;
        foreach (i; 0..src.length)
        {
            result.put(src[i] ^ nonce[i % nonce.length]);
        }
        result.put(0x00 ^ nonce[src.length % nonce.length]); // null terminated

        version (TraceFunction) traceFunction("src=", src.dgToHex(), ", nonce=", nonce.dgToHex(), ", result=", result[].dgToHex());

        return result;
    }
}

version (none)
class MyAuthSha256Mem : MyAuthSha
{
nothrow @safe:

public:
    final override ResultStatus getAuthData(const(int) state, scope const(char)[] userName, scope const(char)[] userPassword,
        scope const(ubyte)[] serverAuthData, ref CipherBuffer!ubyte authData)
    {
        authData = CipherBuffer!ubyte.init;
        return ResultStatus.ok();
    }

    @property final override int multiStates() const @nogc pure
    {
        return 0;
    }

    @property final override string name() const pure
    {
        return myAuthSha256Mem;
    }
}

class MyAuthSha2Caching : MyAuthSha
{
import pham.cp.openssl : OpenSSLRSACrypt, OpenSSLRSAPem;
import pham.cp.openssl_binding : RSA_PKCS1_PADDING;

nothrow @safe:

public:
    final override ResultStatus getAuthData(const(int) state, scope const(char)[] userName, scope const(char)[] userPassword,
        scope const(ubyte)[] serverAuthData, ref CipherBuffer!ubyte authData)
    {
        version (TraceFunction) traceFunction("state=", state, ", userName=", userName, ", serverAuthData=", serverAuthData.dgToHex());

        if (state == 0)
        {
            if (serverAuthData.length)
                setServerSalt(serverAuthData);

            return getPasswordEx(userName, userPassword, false, authData);
        }
        else if (serverAuthData.length && serverAuthData[0] == 3)
            authData = CipherBuffer!ubyte.init;
        else
            return getAuthDataPassword2(userName, userPassword, serverAuthData, authData);
        return ResultStatus.ok();
    }

    @property final override int multiStates() const @nogc pure
    {
        return 3;
    }

    @property final override string name() const pure
    {
        return myAuthSha2Caching;
    }

protected:
    // serverAuthData is the server public key at this state
    final ResultStatus getAuthDataPassword2(scope const(char)[] userName, scope const(char)[] userPassword,
        scope const(ubyte)[] serverAuthData, ref CipherBuffer!ubyte authData)
    {
        version (TraceFunction)
        {
            scope (exit) traceFunction("userName=", userName, ", serverAuthData=", serverAuthData.dgToHex(), ", result=", authData[].dgToHex());
        }

        // Send as clear text since the channel is already encrypted?
        if (isSSLConnection)
        {
            authData = CipherBuffer!ubyte(userPassword.representation());
            authData.put(0x00);
            return ResultStatus.ok();
        }

        if (serverAuthData.length && serverAuthData[0] == 4)
        {
            authData = CipherBuffer!ubyte([0x02]);
            return ResultStatus.ok();
        }

        if (userPassword.length == 0)
        {
            authData = CipherBuffer!ubyte([0x00]);
            return ResultStatus.ok();
        }

        if (serverAuthData.length == 0)
        {
            authData = CipherBuffer!ubyte.init;
            return ResultStatus.ok();
        }

        // Obfuscate the plain text password with the session scramble.
        auto obfuscatedUserPassword = xorNonce(userPassword.representation(), serverSalt);

        version (TraceFunction) traceFunction("obfuscatedUserPassword=", obfuscatedUserPassword.toString());

        auto pem = OpenSSLRSAPem.publicKey(cast(const(char)[])serverAuthData, null);
        auto rsa = OpenSSLRSACrypt(pem);
        if (!serverVersion.empty && serverVersion < "8.0.5")
        {
            version (TraceFunction) traceFunction("paddingMode=PRSA_PKCS1_PADDING");
            rsa.paddingMode = RSA_PKCS1_PADDING;
        }

        auto status = rsa.initialize();
        if (status.isError)
            return status;

        ubyte[] output;
        size_t outputLength;
        status = rsa.encrypt(obfuscatedUserPassword[], output, outputLength);
        if (status.isError)
            return ResultStatus.error(status.errorCode, status.errorMessage, DbMessage.eInvalidConnectionAuthServerData);

        authData = CipherBuffer!ubyte(output[0..outputLength]);
        return ResultStatus.ok();
    }
}


// Any below codes are private
private:

shared static this()
{
    DbAuth.registerAuthMap(DbAuthMap(myAuthSha2Caching, DbScheme.my, &createAuthSha2Caching));
}

DbAuth createAuthSha2Caching()
{
    return new MyAuthSha2Caching();
}

unittest
{
    import pham.utl.test;
    traceUnitTest("unittest pham.db.myauth_sha.MyAuthSha2Caching");

    auto obfuscated = MyAuthSha.xorNonce("masterkey".representation(), dgFromHex("773529605513697D2E3F02211E41096D1E4F5E40"));
    assert(obfuscated[] == dgFromHex("1A545A1430610218573F"), obfuscated.toString());

    {
        auto auth = new MyAuthSha2Caching();
        auth.setServerSalt(dgFromHex("773529605513697D2E3F02211E41096D1E4F5E4000"));
        CipherBuffer!ubyte pwAuth;
        assert(auth.getPassword("caching_sha2_password", "masterkey", pwAuth).isOK());
        assert(pwAuth[] == dgFromHex("20235CE4068AEF19D30C37784D968A4D489E46AE8D6CB6B9B5CB5FF3AA044FDD99"), pwAuth.toString());
    }

    {
        auto auth = new MyAuthSha2Caching();
        CipherBuffer!ubyte state1;
        assert(auth.getAuthData(0, "caching_sha2_password", "masterkey", dgFromHex("2C4A135B7618231F1E6D1C12204E7F1A6A261B5F00"), state1).isOK());
        assert(state1[] == dgFromHex("9558075C2D7DC2FDFBB306442A71378E3908793609084D3E4A66C7691A0EDE62"), state1.toString());
    }

    {
        auto auth = new MyAuthSha2Caching();
        CipherBuffer!ubyte state1;
        assert(auth.getAuthData(0, "caching_sha2_password", "masterkey", dgFromHex("773529605513697D2E3F02211E41096D1E4F5E4000"), state1).isOK());
        assert(state1[] == dgFromHex("235CE4068AEF19D30C37784D968A4D489E46AE8D6CB6B9B5CB5FF3AA044FDD99"), state1.toString());

        CipherBuffer!ubyte state2;
        assert(auth.getAuthData(1, "caching_sha2_password", "masterkey", dgFromHex("04"), state2).isOK());
        assert(state2[] == dgFromHex("02"), state2.toString());

        // Not able to unittest for this case because of random padding data
        //auto state3 = auth.getAuthData(2, "caching_sha2_password", "masterkey", dgFromHex("2D2D2D2D2D424547494E205055424C4943204B45592D2D2D2D2D0A4D494942496A414E42676B71686B6947397730424151454641414F43415138414D49494243674B4341514541355242567065474D5369743365634D36436355360A6A6461706161584D4B496B5450443562687459582F6E5A45503557546F72704B6B67776359487371646F453879726D596841524374563079466A752B39534A2F0A30654C766D3553625761564F39664B3053336D71546450436B5251717547586D374575797A3374664734743432716B5971456765314670676950394C694A44510A4B425A6A68475061384A306A6F72574243654C364472685651642F524A68676B43613543547843574C7259674943786A58726D494A565872674E755067734D410A516E433848386349466D5236734B4D563241573949574B7A6E31753950774E434443505A764777352B303130344E33796B2F654A5776303858317569783166540A4B426B45387A715566464E3449454374704E76486A377578614F735772527A68305876776E6A4D436B454A664C69674D4F31696A674D564776493839304564310A39774944415141420A2D2D2D2D2D454E44205055424C4943204B45592D2D2D2D2D0A"));
        //assert(state3[] == dgFromHex("173FA77A68396EB1C690F4D216CCC2F8211C50357665668DC1EE8DD160B021DC77F3A6D5BCD14BEF0902817C58B539DE9A476517C6234F0022D4D4191B6A0C3FCA5DC80BB46D05F03DA75C2B696C55A9A03752551AED255351788392E4D8CECC362414A3B0572870A8912351AE6FF748B4269E2429E6C45B4C7F02EE50C607B428A4D8D70E2FF66F89FC6C2E2B64780241E4A4B03AC145E4198FA69B737996AFE1E6CDF797EFAECDF641C73AAD5E80D28ADE2269201311433D0E47C098F79F71E73C81FD5BC29438550F997DCD94ACAA3B3FE6A8CDEFE79E01016B156812E8A34E4F152F386ED77323FC45433611708F8487B1DD56E5778C241F25E6577D0DBB"), state3.toString());
    }
}
