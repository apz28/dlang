/*
*
* License: $(HTTP www.boost.org/LICENSE_1_0.txt, Boost License 1.0).
* Authors: An Pham
*
* Copyright An Pham 2022 - xxxx.
* Distributed under the Boost Software License, Version 1.0.
* (See accompanying file LICENSE.txt or copy at http://www.boost.org/LICENSE_1_0.txt)
*
*/

module pham.external.std.windows.sspi_ex;

version (Windows):

import pham.external.std.windows.sspi;

nothrow @safe:

struct RequestSecBufferDesc
{
nothrow @safe:

public
    enum secBufferSize = 16_000;

public:
    void dispose(bool disposing = true) pure
    {
        secBuffer.cbBuffer = 0;
        secBuffer.BufferType = 0;
        secBuffer.pvBuffer = null;

        secBufferDesc.ulVersion = 0;
        secBufferDesc.cBuffers = 0;
        secBufferDesc.pBuffers = null;

        secBufferData[] = 0;
    }

    ubyte[] getSecBytes() pure
    {
        return secBufferData[0..secBuffer.cbBuffer].dup;
    }

    PSecBufferDesc initServerContext(scope const(ubyte)[] secBytes) pure return @trusted
    {
        secBufferData = secBytes.dup;

        secBuffer.cbBuffer = cast(uint)secBufferData.length;
        secBuffer.BufferType = SECBUFFER_TOKEN;
        secBuffer.pvBuffer = secBufferData.length != 0 ? &secBufferData[0] : null;

        secBufferDesc.ulVersion = SECBUFFER_VERSION;
        secBufferDesc.cBuffers = 1;
        secBufferDesc.pBuffers = &secBuffer;

        return &secBufferDesc;
    }

    PSecBufferDesc initClientContext() pure return @trusted
    {
        secBufferData.length = secBufferSize;

        secBuffer.cbBuffer = secBufferSize;
        secBuffer.BufferType = SECBUFFER_TOKEN;
        secBuffer.pvBuffer = &secBufferData[0];

        secBufferDesc.ulVersion = SECBUFFER_VERSION;
        secBufferDesc.cBuffers = 1;
        secBufferDesc.pBuffers = &secBuffer;

        return &secBufferDesc;
    }

public:
    SecBuffer secBuffer;
    SecBufferDesc secBufferDesc;
    ubyte[] secBufferData;
}

struct RequestSecResult
{
nothrow @safe:

    SECURITY_STATUS status;
    string message;
}

struct RequestSecClient
{
import std.conv : to;
import std.string : toStringz;

nothrow @safe:

public:
    ~this()
    {
        dispose(false);
    }

    void dispose(bool disposing = true)
    {
        disposeClientContext(disposing);
        disposeClientCredentials(disposing);
    }

    void disposeClientContext(bool disposing) @trusted
    {
        if (clientContext.isValid())
        {
            DeleteSecurityContext(&clientContext);
            clientContext.reset();
        }
    }

    void disposeClientCredentials(bool disposing) @trusted
    {
        if (clientCredentials.isValid())
        {
            FreeCredentialsHandle(&clientCredentials);
            clientCredentials.reset();
        }
    }

    bool authenticate(string remotePrincipal, scope const(ubyte)[] serverAuthData, ref RequestSecResult errorStatus, ref ubyte[] authData) @trusted
    {
        ULONG contextAttributes;
        RequestSecBufferDesc requestSecBufferDesc, serverSecBufferDesc;
        scope (exit)
        {
            requestSecBufferDesc.dispose();
            serverSecBufferDesc.dispose();
        }

        auto remotePrincipalz = remotePrincipal.length != 0 ? remotePrincipal.toStringz() : null;
		errorStatus.status = InitializeSecurityContextA(&clientCredentials, &clientContext, remotePrincipalz,
            ISC_REQ_STANDARD_CONTEXT_ATTRIBUTES, 0, SECURITY_NATIVE_DREP, serverSecBufferDesc.initServerContext(serverAuthData), 0,
			&clientContext, requestSecBufferDesc.initClientContext(), &contextAttributes, &clientContextTimestamp);

        if (errorStatus.status == SEC_I_COMPLETE_NEEDED || errorStatus.status == SEC_I_COMPLETE_AND_CONTINUE)
        {
            errorStatus.status = CompleteAuthToken(&clientContext, requestSecBufferDesc.initClientContext());
            if (errorStatus.status != SEC_E_OK)
            {
                errorStatus.message = "CompleteAuthToken() failed: " ~ to!string(errorStatus.status);
                return false;
            }
        }

		if (errorStatus.status == SEC_E_OK || errorStatus.status == SEC_I_CONTINUE_NEEDED)
        {
            authData = requestSecBufferDesc.getSecBytes();
            return true;
        }
        else
        {
            errorStatus.message = "InitializeSecurityContextA() failed: " ~ to!string(errorStatus.status);
            return false;
        }
    }

    bool init(string secPackage, string remotePrincipal, ref RequestSecResult errorStatus, ref ubyte[] authData)
    in
    {
        assert(secPackage.length != 0);
    }
    do
    {
        if (initClientCredentials(secPackage, errorStatus))
            return initClientContext(remotePrincipal, errorStatus, authData);
        else
            return false;
    }

private:
    bool initClientContext(string remotePrincipal, ref RequestSecResult errorStatus, ref ubyte[] authData) @trusted
    {
        ULONG contextAttributes;
        RequestSecBufferDesc requestSecBufferDesc;
        scope (exit)
            requestSecBufferDesc.dispose();

        auto remotePrincipalz = remotePrincipal.length != 0 ? remotePrincipal.toStringz() : null;
        errorStatus.status = InitializeSecurityContextA(&clientCredentials, null, remotePrincipalz,
            ISC_REQ_STANDARD_CONTEXT_ATTRIBUTES, 0, SECURITY_NATIVE_DREP, null, 0,
            &clientContext, requestSecBufferDesc.initClientContext(), &contextAttributes, &clientContextTimestamp);

        if (errorStatus.status == SEC_I_COMPLETE_NEEDED || errorStatus.status == SEC_I_COMPLETE_AND_CONTINUE)
        {
            errorStatus.status = CompleteAuthToken(&clientContext, requestSecBufferDesc.initClientContext());
            if (errorStatus.status != SEC_E_OK)
            {
                errorStatus.message = "CompleteAuthToken() failed: " ~ to!string(errorStatus.status);
                return false;
            }
        }

		if (errorStatus.status == SEC_E_OK || errorStatus.status == SEC_I_CONTINUE_NEEDED)
        {
            authData = requestSecBufferDesc.getSecBytes();
            return true;
        }
        else
        {
            errorStatus.message = "InitializeSecurityContextA() failed: " ~ to!string(errorStatus.status);
            return false;
        }
    }

    bool initClientCredentials(string secPackage, ref RequestSecResult errorStatus) @trusted
    {
        auto secPackagez = secPackage.length != 0 ? secPackage.toStringz() : null;
		errorStatus.status = AcquireCredentialsHandleA(null, secPackagez, SECPKG_CRED_OUTBOUND,
            null, null, null, null, &clientCredentials, &clientCredentialsTimestamp);
		if (errorStatus.status != SEC_E_OK)
        {
            errorStatus.message = "AcquireCredentialsHandleA() failed: " ~ to!string(errorStatus.status);
            return false;
        }
        else
            return true;
    }

public:
	CtxtHandle clientContext;
	SecHandle clientCredentials;
    TimeStamp clientCredentialsTimestamp, clientContextTimestamp;
}
