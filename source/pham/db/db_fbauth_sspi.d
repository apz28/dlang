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

module pham.db.fbauth_sspi;

version (Windows):

import std.conv : to;
import std.string : toStringz;

version (unittest) import pham.utl.test;
import pham.external.std.windows.sspi;
import pham.db.auth;
import pham.db.message;
import pham.db.type : DbScheme;
import pham.db.fbauth;
import pham.db.fbtype : fbAuthSSPIName;

nothrow @safe:

class FbAuthSspi : FbAuth
{
nothrow @safe:

public:
    this(string secPackage = "NTLM", string remotePrincipal = null)
    {
        this._secPackage = secPackage;
        this._remotePrincipal = remotePrincipal;
        if (initClientCredentials())
            initClientContext();
    }

    final const(ubyte)[] calculateProof(scope const(char)[] userName, scope const(char)[] userPassword, const(ubyte)[] serverAuthData)
    {
        version (TraceFunction) traceFunction!("pham.db.fbdatabase")("userName=", userName, ", serverAuthData=", serverAuthData);

        ULONG contextAttributes;
        RequestSecBufferDesc requestSecBufferDesc, serverSecBufferDesc;
        scope (exit)
        {
            requestSecBufferDesc.dispose();
            serverSecBufferDesc.dispose();
        }

		const r = InitializeSecurityContextA(&_clientCredentials, &_clientContext, remotePrincipalz(),
            ISC_REQ_STANDARD_CONTEXT_ATTRIBUTES, 0, SECURITY_NATIVE_DREP, serverSecBufferDesc.initServerContext(serverAuthData), 0,
			&_clientContext, requestSecBufferDesc.initClientContext(), &contextAttributes, &_clientContextTimestamp);
		if (r != 0 && r != SEC_I_CONTINUE_NEEDED)
        {
            setError(r, "InitializeSecurityContextA failed: " ~ to!string(r), DbMessage.eInvalidConnectionAuthServerData);
            return null;
        }

        _proof = requestSecBufferDesc.getSecBytes();
        return _proof;
    }

    final override const(ubyte)[] getAuthData(const(int) state, scope const(char)[] userName, scope const(char)[] userPassword,
        const(ubyte)[] serverAuthData)
    {
        version (TraceFunction) traceFunction!("pham.db.fbdatabase")("_nextState=", _nextState, ", state=", state, ", userName=", userName, ", serverAuthData=", serverAuthData);

        if (state != _nextState || state > 1)
        {
            setError(state + 1, to!string(state), DbMessage.eInvalidConnectionAuthServerData);
            return null;
        }

        _nextState++;
        if (state == 0)
            return publicKey();
        else if (state == 1)
            return calculateProof(userName, userPassword, serverAuthData);
        else
            assert(0);
    }

    final override size_t maxSizeServerAuthData(out size_t maxSaltLength) const nothrow pure
    {
        maxSaltLength = 0;
        return size_t.max;
    }

    final override const(ubyte)[] publicKey() const
    {
        return _publicKey;
    }

    @property final override int multiSteps() const @nogc pure
    {
        return 2;
    }

    @property final override string name() const pure
    {
        return fbAuthSSPIName;
    }

    @property final string remotePrincipal() const pure
    {
        return _remotePrincipal;
    }

    @property final string secPackage() const pure
    {
        return _secPackage;
    }

protected:
    final void disposeClientContext()
    {
        if (isValid(_clientContext))
        {
            DeleteSecurityContext(&_clientContext);
            reset(_clientContext);
        }
    }

    final void disposeClientCredentials()
    {
        if (isValid(_clientCredentials))
        {
            FreeCredentialsHandle(&_clientCredentials);
            reset(_clientCredentials);
        }
    }

    override void doDispose(bool disposing) nothrow
    {
        _proof[] = 0;
        _publicKey[] = 0;
        disposeClientContext();
        disposeClientCredentials();
        super.doDispose(disposing);
    }

    final bool initClientContext() @trusted
    {
        ULONG contextAttributes;
        RequestSecBufferDesc requestSecBufferDesc;
        scope (exit)
            requestSecBufferDesc.dispose();

        const r = InitializeSecurityContextA(&_clientCredentials, null, remotePrincipalz(),
            ISC_REQ_STANDARD_CONTEXT_ATTRIBUTES, 0, SECURITY_NATIVE_DREP, null, 0,
            &_clientContext, requestSecBufferDesc.initClientContext(), &contextAttributes, &_clientContextTimestamp);
		if (r != 0 && r != SEC_I_CONTINUE_NEEDED)
        {
            setError(r, "InitializeSecurityContextA failed: " ~ to!string(r), DbMessage.eInvalidConnectionAuthServerData);
            return false;
        }

        _publicKey = requestSecBufferDesc.getSecBytes();
        return true;
    }

    final bool initClientCredentials()
    {
		const r = AcquireCredentialsHandleA(null, secPackagez(), SECPKG_CRED_OUTBOUND,
            null, null, null, null, &_clientCredentials, &_clientCredentialsTimestamp);
		if (r != 0)
        {
            setError(r, "AcquireCredentialsHandleA failed: " ~ to!string(r), DbMessage.eInvalidConnectionAuthServerData);
            return false;
        }

        return true;
    }

    final char* remotePrincipalz() @trusted
    {
        if (_remotePrincipal.length)
            return cast(char*)(_remotePrincipal.toStringz());
        else
            return null;
    }

    // This is required value
    final char* secPackagez() @trusted
    {
        return cast(char*)(_secPackage.toStringz());
    }

private:
	CtxtHandle _clientContext;
	SecHandle _clientCredentials;
    TimeStamp _clientCredentialsTimestamp, _clientContextTimestamp;
    ubyte[] _proof;
    ubyte[] _publicKey;
    string _remotePrincipal;
    string _secPackage;
}


// Any below codes are private
private:

shared static this()
{
    DbAuth.registerAuthMap(DbAuthMap(fbAuthSSPIName, DbScheme.fb, &createAuthSSPI));
}

DbAuth createAuthSSPI()
{
    return new FbAuthSspi();
}
