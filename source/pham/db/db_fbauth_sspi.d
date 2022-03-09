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

version (unittest) import pham.utl.test;
import pham.external.std.windows.sspi : RequestSecClient;
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

        string errMsg;
        int errSts;
        this._publicKey = this._secClient.init(secPackage, remotePrincipal, errSts, errMsg);
        if (this._publicKey.length == 0)
            setError(errSts, errMsg, DbMessage.eInvalidConnectionAuthClientData);
    }

    final const(ubyte)[] calculateProof(scope const(char)[] userName, scope const(char)[] userPassword, const(ubyte)[] serverAuthData)
    {
        version (TraceFunction) traceFunction!("pham.db.fbdatabase")("userName=", userName, ", serverAuthData=", serverAuthData);

        string errMsg;
        int errSts;
        _proof = _secClient.authenticate(remotePrincipal, serverAuthData, errSts, errMsg);
        if (_proof.length == 0)
            setError(errSts, errMsg, DbMessage.eInvalidConnectionAuthServerData);
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
    override void doDispose(bool disposing) nothrow
    {
        _proof[] = 0;
        _publicKey[] = 0;
        _secClient.dispose(disposing);
        super.doDispose(disposing);
    }

private:
    RequestSecClient _secClient;
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
