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

import core.sys.windows.sspi;
import std.conv : to;
import std.string : toStringz;

import pham.db.type : DbScheme;
import pham.db.auth;
import pham.db.fbauth;

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

    final override const(ubyte)[] getAuthData(scope const(char)[] userName, scope const(char)[] userPassword, const(ubyte)[] serverAuthData)
    in
    {
        assert(errorCode == 0);
        assert(isValid(_clientContext));
    }
    do
    {
        ULONG contextAttributes;
        RequestSecBufferDesc requestSecBufferDesc, serverSecBufferDesc;
        scope (exit)
        {
            requestSecBufferDesc.dispose();
            serverSecBufferDesc.dispose();
        }

		errorCode = InitializeSecurityContextA(&_clientCredentials, &_clientContext, remotePrincipalz(),
            ISC_REQ_STANDARD_CONTEXT_ATTRIBUTES, 0, SECURITY_NATIVE_DREP, serverSecBufferDesc.initServerContext(serverAuthData), 0,
			&_clientContext, requestSecBufferDesc.initClientContext(), &contextAttributes, &_clientContextTimestamp);
		if (errorCode != 0 && errorCode != SEC_I_CONTINUE_NEEDED)
        {
            this.errorMessage = "InitializeSecurityContextA failed: " ~ to!string(errorCode);
            return null;
        }

        errorCode = 0;
        _proof = requestSecBufferDesc.getSecBytes();
        return _proof;
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

    @property final override string name() const
    {
        return authSSPIName;
    }

    @property final string remotePrincipal() const pure
    {
        return _remotePrincipal;
    }

    @property final string secPackage() const pure
    {
        return _secPackage;
    }

public:
    static immutable string authSSPIName = "Win_Sspi";

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

        errorCode = InitializeSecurityContextA(&_clientCredentials, null, remotePrincipalz(),
            ISC_REQ_STANDARD_CONTEXT_ATTRIBUTES, 0, SECURITY_NATIVE_DREP, null, 0,
            &_clientContext, requestSecBufferDesc.initClientContext(), &contextAttributes, &_clientContextTimestamp);
		if (errorCode != 0 && errorCode != SEC_I_CONTINUE_NEEDED)
        {
            this.errorMessage = "InitializeSecurityContextA failed: " ~ to!string(errorCode);
            return false;
        }

        errorCode = 0;
        _publicKey = requestSecBufferDesc.getSecBytes();
        return true;
    }

    final bool initClientCredentials()
    {
		errorCode = AcquireCredentialsHandleA(null, secPackagez(), SECPKG_CRED_OUTBOUND,
            null, null, null, null, &_clientCredentials, &_clientCredentialsTimestamp);
		if (errorCode != 0)
        {
            this.errorMessage = "AcquireCredentialsHandleA failed: %d" ~ to!string(errorCode);
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
    DbAuth.registerAuthMap(DbAuthMap(DbScheme.fb ~ FbAuthSspi.authSSPIName, &createAuthSSPI));
}

DbAuth createAuthSSPI()
{
    return new FbAuthSspi();
}
