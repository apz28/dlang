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

module pham.db.db_myauth_sspi;

version(Windows):

debug(debug_pham_db_db_myauth_sspi) import pham.db.db_debug;
import pham.external.std.windows.sspi_ex : RequestSecClient, RequestSecResult;
import pham.utl.utl_disposable : DisposingReason;
import pham.db.db_auth;
import pham.db.db_message;
import pham.db.db_type : DbScheme;
import pham.db.db_myauth;
import pham.db.db_mytype : myAuthSSPIName;

nothrow @safe:

class MyAuthSspi : MyAuth
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

    final override ResultStatus getAuthData(const(int) state, ref DbAuthStateData stateData)
    {
        debug(debug_pham_db_db_myauth_sspi) debug writeln(__FUNCTION__, "(_nextState=", _nextState,
            ", state=", state, ", stateData=", stateData.toString(), ")");

        auto status = checkAdvanceState(state);
        if (status.isError)
            return status;

        if (state == 0)
            return calculateAuth(stateData.userName[], stateData.userPassword[], stateData.authData);
        else if (state == 1)
            return calculateProof(stateData.userName[], stateData.userPassword[], stateData.serverAuthData[], stateData.authData);
        else
            return invalidAuthState(state);
    }

    @property final override int multiStates() const @nogc pure
    {
        return 2;
    }

    @property final override string name() const pure
    {
        return myAuthSSPIName;
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
    final ResultStatus calculateAuth(scope const(char)[] userName, scope const(char)[] userPassword, ref CipherRawKey!ubyte authData)
    {
        ubyte[] result;
        RequestSecResult errorStatus;
        if (!_secClient.init(secPackage, remotePrincipal, errorStatus, result))
            return ResultStatus.error(errorStatus.status, DbMessage.eInvalidConnectionAuthClientData.fmtMessage(name, errorStatus.message));
        authData = result;
        return ResultStatus.ok();
    }

    final ResultStatus calculateProof(scope const(char)[] userName, scope const(char)[] userPassword,
        scope const(ubyte)[] serverAuthData, ref CipherRawKey!ubyte authData)
    {
        debug(debug_pham_db_db_myauth_sspi) debug writeln(__FUNCTION__, "(userName=", userName, ", serverAuthData=", serverAuthData.dgToHex(), ")");

        ubyte[] result;
        RequestSecResult errorStatus;
        if (!_secClient.authenticate(remotePrincipal, serverAuthData, errorStatus, result))
            return ResultStatus.error(errorStatus.status, DbMessage.eInvalidConnectionAuthServerData.fmtMessage(name, errorStatus.message));
        authData = result;
        return ResultStatus.ok();
    }

    override int doDispose(const(DisposingReason) disposingReason) nothrow @safe
    {
        _secClient.dispose(disposingReason);
        _remotePrincipal = _secPackage = null;
        return super.doDispose(disposingReason);
    }

private:
    RequestSecClient _secClient;
    string _remotePrincipal;
    string _secPackage;
}


// Any below codes are private
private:

shared static this() nothrow @safe
{
    DbAuth.registerAuthMap(DbAuthMap(myAuthSSPIName, DbScheme.my, &createAuthSSPI));
}

DbAuth createAuthSSPI()
{
    return new MyAuthSspi();
}
