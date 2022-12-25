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

version (unittest) import pham.utl.test;
import pham.external.std.windows.sspi_ex : RequestSecClient, RequestSecResult;
import pham.utl.disposable : DisposingReason;
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
    in
    {
        assert(secPackage.length != 0);
    }
    do
    {
        this._secPackage = secPackage;
        this._remotePrincipal = remotePrincipal;
    }

    final ResultStatus calculateAuth(scope const(char)[] userName, scope const(char)[] userPassword, ref CipherBuffer authData)
    {
        ubyte[] result;
        RequestSecResult errorStatus;
        if (!_secClient.init(secPackage, remotePrincipal, errorStatus, result))
            return ResultStatus.error(errorStatus.status, errorStatus.message, DbMessage.eInvalidConnectionAuthClientData);
        authData = CipherBuffer(result);
        return ResultStatus.ok();
    }

    final ResultStatus calculateProof(scope const(char)[] userName, scope const(char)[] userPassword,
        scope const(ubyte)[] serverAuthData, ref CipherBuffer authData)
    {
        version (TraceFunction) traceFunction!("pham.db.fbdatabase")("userName=", userName, ", serverAuthData=", serverAuthData.dgToHex());

        ubyte[] result;
        RequestSecResult errorStatus;
        if (!_secClient.authenticate(remotePrincipal, serverAuthData, errorStatus, result))
            return ResultStatus.error(errorStatus.status, errorStatus.message, DbMessage.eInvalidConnectionAuthServerData);
        authData = CipherBuffer(result);
        return ResultStatus.ok();
    }

    final override ResultStatus getAuthData(const(int) state, scope const(char)[] userName, scope const(char)[] userPassword,
        scope const(ubyte)[] serverAuthData, ref CipherBuffer authData)
    {
        version (TraceFunction) traceFunction!("pham.db.fbdatabase")("_nextState=", _nextState, ", state=", state, ", userName=", userName, ", serverAuthData=", serverAuthData.dgToHex());

        auto status = checkAdvanceState(state);
        if (status.isError)
            return status;

        if (state == 0)
            return calculateAuth(userName, userPassword, authData);
        else if (state == 1)
            return calculateProof(userName, userPassword, serverAuthData, authData);
        else
            assert(0);
    }

    final override size_t maxSizeServerAuthData(out size_t maxSaltLength) const nothrow pure
    {
        maxSaltLength = 0;
        return size_t.max;
    }

    @property final override int multiStates() const @nogc pure
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
    override void doDispose(const(DisposingReason) disposingReason) nothrow @safe
    {
        _secClient.dispose(disposingReason);
        _remotePrincipal = _secPackage = null;
        super.doDispose(disposingReason);
    }

private:
    RequestSecClient _secClient;
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
