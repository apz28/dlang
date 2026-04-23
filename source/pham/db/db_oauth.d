/*
 *
 * License: $(HTTP www.boost.org/LICENSE_1_0.txt, Boost License 1.0).
 * Authors: An Pham
 *
 * Copyright An Pham 2026 - xxxx.
 * Distributed under the Boost Software License, Version 1.0.
 * (See accompanying file LICENSE.txt or copy at http://www.boost.org/LICENSE_1_0.txt)
 *
 */

module pham.db.db_oauth;

version(pham_db_db_oauth):

import core.atomic : atomicLoad, atomicStore;
import core.time : Duration, dur;
import std.conv : text;
import std.process : Pid;

import pham.dtm.dtm_date : DateTime;
import pham.io.io_socket;
import pham.io.io_socket_service;
import pham.utl.utl_array_append : Appender;
import pham.utl.utl_html;
import pham.utl.utl_result : ResultIf;

debug(debug_pham_db_db_oauth) import pham.db.db_debug;
import pham.db.db_auth;
import pham.db.db_message;
import pham.db.db_type : DbScheme;

@safe:

class DbOAuth : DbAuth
{
@safe:

public:
    override ResultStatus getAuthData(const(int) state, scope const(char)[] userName, scope const(char)[] userPassword,
        const(ubyte)[] serverAuthData, ref CipherBuffer!ubyte authData) nothrow
    {
    //todo

        return ResultStatus.ok();
    }

    final void requestAccessToken(string authorizerURL, string clientId, string scopes, string providerName)
    {
        //todo check for error
        data.prepareAuthorizing(authorizerURL, clientId, scopes, providerName);
        data.startAuthorizing();
    }

    @property final override int multiStates() const @nogc nothrow pure
    {
        // init, bearerSent, requestingToken, serverError
        return 3;
    }

    @property final override string name() const nothrow pure
    {
        return "OAuth/OIDC";
    }

    @property final override DbScheme scheme() const nothrow pure
    {
        return _scheme;
    }

    @property final string mechanism() const nothrow pure
    {
        return _mechanism;
    }

public:
    static ResultIf!string createInitialResponse(bool discover, string bearerToken)
    {
        string authScheme, lToken;

        if (discover)
        {
            authScheme = lToken = "";
        }
        else
        {
            if (bearerToken.length == 0)
                return ResultIf!string.error(DbErrorCode.connect, "No OAuth token was set for the connection");

            authScheme = "Bearer ";
            lToken = bearerToken;
        }

        // "n,,[kvSep]auth=[authScheme ][token][kvSep][kvSep]"
        auto result = Appender!string();
        result.put("n,,")
            .put(kvSep)
            .put("auth=")
            .put(authScheme)
            .put(lToken)
            .put(kvSep)
            .put(kvSep);

        return ResultIf!string.ok(result.data);
    }

public:
    DbOAuthData data;

protected:
    static immutable string kvSep = "\x01";
    static immutable string errorStatusField = "status";
    static immutable string errorScopeField = "scope";
    static immutable string errorOpenIdConfigField = "openid-configuration";

    string _mechanism = "OAUTHBEARER";
    DbScheme _scheme;
}

struct DbOAuthData
{
public:
    ref DbOAuthData prepareAuthorizing(string authorizerURL, string clientId, string scopes, string providerName) return @safe
    {
        import pham.utl.utl_text : simpleEndWithAny;

        this.clientId = clientId;
        this.scopes = scopes;
        this.providerName = providerName;

        accessCode = bearerToken = refreshToken = null;
        expiredIn = 0;
        expiredStarted = DateTime.min;
        accessState = randomUUIDString(); // Some random text

        if (responseType.length == 0)
            responseType = "token";

        if (this.authorizingServerCallbackInfo.port == 0)
            this.authorizingServerCallbackInfo.port = Socket.getUnusedPort();
        string redirectURL = text(loopbackHost, ":", authorizingServerCallbackInfo.port);

        verifierCode = randomUUIDString();
        while (verifierCode.length < 64)
            verifierCode ~= randomUUIDString();

        // construct url and run a browser with the constructed url
        // https://developers.google.com/identity/protocols/oauth2/javascript-implicit-flow
        string actualAuthorizerURL = authorizerURL;
        if (actualAuthorizerURL.simpleEndWithAny("?&") < 0)
            actualAuthorizerURL ~= "?";
        actualAuthorizerURL ~=
            "&client_id=" ~ uriEncode(clientId)
            ~ "&scope=" ~ uriEncode(scopes)
            ~ "&state=" ~ uriEncode(accessState)
            ~ "&redirect_uri=" ~ uriEncode(redirectURL)
            ~ "&response_type=" ~ uriEncode(responseType)
            ~ "&code_challenge=" ~ digestVerifierCode()
            ~ "&code_challenge_method=S256";
            //~ "&include_granted_scopes=true"

        if (extraAuthorizerParams.length)
            actualAuthorizerURL ~= "&" ~ uriParameters(extraAuthorizerParams);

        return this;
    }

    ResultStatus startAuthorizing() nothrow @safe
    {
        import pham.utl.utl_system : runDefaultBrowser, waitFor;

        auto rdb = runDefaultBrowser(actualAuthorizerURL);
        if (rdb.isError)
            return ResultStatus.error;

        authorizingServerCallback = new DbOAuthAuthorizingServerCallback(authorizingServerCallbackInfo);
        authorizingServerCallback.run();

        // todo wait for
        auto wfr = waitFor(rdb.value, authorizingServerCallbackInfo.getTimeOut(), &checkAuthorizing, null);

        // todo check for error & result state
    }

    ResultStatus requestAccessToken(string issuerURL) nothrow @trusted
    {
        import std.net.curl : HTTP, httpPost = post;

        string postAccessData =
            "client_id=" ~ uriEncode(clientId)
            ~ "&scope=" ~ uriEncode(scopes)
            ~ "&code=" ~ uriEncode(accessCode)
            ~ "&grant_type=authorization_code"
            ~ "&code_verifier=" ~ uriEncode(verifierCode);

        if (extraRequestAccessParams.length)
            accessPostData ~= "&" ~ uriParameters(extraRequestAccessParams);

        char[] receiveAccessData;
        try
        {
            HTTP http;
            http.method = HTTP.Method.post;
            http.addRequestHeader("Content-Type", "application/x-www-form-urlencoded");
            receiveAccessData = httpPost(issuerURL, postAccessData, http);
        }
        catch (Exception ex)
        {
        //todo
        }

        /* receiveAccessData should be a json data as below
        {
          "access_token": "eyJ0eXAiOiJKV1QiLCJhbGciOiJSUzI1NiIsIng1dCI6Ik5HVEZ2ZEstZnl0aEV1Q...",
          "token_type": "Bearer",
          "expires_in": 3599,
          "scope": "https%3A%2F%2Fgraph.microsoft.com%2Fmail.read",
          "refresh_token": "AwABAAAAvPM1KaPlrEqdFSBzjqfTGAMxZGUTdM0t4B4...",
          "id_token": "eyJ0eXAiOiJKV1QiLCJhbGciOiJub25lIn0.eyJhdWQiOiIyZDRkMTFhMi1mODE0LTQ2YTctOD..."
        }
        or
        {
          "error": "invalid_scope",
          "error_description": "AADSTS70011: The provided value for the input parameter 'scope' is not valid. The scope https://foo.microsoft.com/mail.read is not valid.\r\nTrace ID: 0000aaaa-11bb-cccc-dd22-eeeeee333333\r\nCorrelation ID: aaaa0000-bb11-2222-33cc-444444dddddd\r\nTimestamp: 2016-01-09 02:02:12Z",
          "error_codes": [
            70011
          ],
          "timestamp": "2016-01-09 02:02:12Z",
          "trace_id": "0000aaaa-11bb-cccc-dd22-eeeeee333333",
          "correlation_id": "aaaa0000-bb11-2222-33cc-444444dddddd"
        }
        */
    }

public:
    int checkAuthorizing(void*, long) nothrow @safe
    {
        return authorizingServerCallback is null
            ? -1
            : (authorizingServerCallback.result.isSet() ? 1 : 0);
    }

    string digestVerifierCode() nothrow @safe
    {
        import pham.cp.cp_cipher_digest;
        import pham.utl.utl_convert : bytesToHexs;

        DigestResult outBuffer;
        auto digester = Digester(DigestId.sha256);
        return digester.begin()
            .digest(verifierCode)
            .finish(outBuffer)
            .bytesToHexs();
    }

    static string randomUUIDString(const(bool) upper = false) nothrow @safe
    {
        import std.uuid : UUID, randomUUID;

        static char toHexChar(const(ubyte) i, const(bool) upper) @nogc nothrow pure @safe
        {
            assert(i <= 15);

            static immutable string upperChars = "aA";
            if (i <= 9)
                return cast(char)('0' + i);
            else
                return cast(char)(upperChars[upper == true] + (i - 10));
        }

        const uuidData = randomUUID().data;
        assert(uuidData.length == 16);
        char[32] result = void;
        foreach (i, e; uuidData)
        {
            const i2 = i * 2;
            const ubyte hi = e >> 4;
            result[i2] = toHexChar(hi, upper);
            const ubyte lo = e & 0x0F;
            result[i2 + 1] = toHexChar(lo, upper);
        }
        return result.idup;
    }

public:
    string accessCode;
    string accessState;
    string bearerToken;
    string clientId;
    NamedValue!string[] extraAuthorizerParams;
    NamedValue!string[] extraRequestAccessParams;
    string providerName;
    string refreshToken;
    string responseType;
    string scopes;
    string verifierCode;
    DateTime expiredStarted;
    uint expiredIn;

    DbOAuthAuthorizingServerCallbackInfo authorizingServerCallbackInfo;
    DbOAuthAuthorizingServerCallback authorizingServerCallback;
}

struct DbOAuthAuthorizingServerCallbackInfo
{
    SocketPort port;
    Duration timeOut;
    string errorLabel;
    string headerError;
    string headerOther;
    string headerSuccess;
    string messageSuccess;

    string getErrorLabel() nothrow
    {
        return errorLabel.length != 0 ? errorLabel : "Error";
    }

    string getHeaderError() nothrow
    {
        return headerError.length != 0 ? headerError : "Authorization Failed";
    }

    string getHeaderOther() nothrow
    {
        return headerOther.length != 0 ? headerOther : "Authorization Callback";
    }

    string getHeaderSuccess() nothrow
    {
        return headerSuccess.length != 0 ? headerSuccess : "Authorization Successful";
    }

    string getMessageSuccess() nothrow
    {
        return messageSuccess.length != 0 ? messageSuccess : "You can close this window.";
    }

    Duration getTimeOut() nothrow
    {
        return timeOut.isTimeout() ? timeOut : dur!"seconds"(90);
    }
}

enum DbOAuthAuthorizingServerCallbackStatus : ubyte
{
    unknown,
    ok,
    error,
}

struct DbOAuthAuthorizingServerCallbackResult
{
    string code;
    string state;
    string error;
    string errorDescription;
    int done;

    bool isSet() const nothrow @safe
    {
        return atomicLoad(done) != 0;
    }

    void reset() nothrow @safe
    {
        code = state = error = errorDescription = null;
        atomicStore(done, 0);
    }

    DbOAuthAuthorizingServerCallbackStatus status() const nothrow @safe
    {
        if (code.length)
            return DbOAuthAuthorizingServerCallbackStatus.ok;
        else if (error.length)
            return DbOAuthAuthorizingServerCallbackStatus.error;
        else
            return DbOAuthAuthorizingServerCallbackStatus.unknown;
    }
}

class DbOAuthAuthorizingServerCallback
{
    import std.string : representation;
    import pham.utl.utl_text : NamedValue, simpleIndexOf, simpleStartWith, simpleTrim, simpleTrimLeft;

public:
    this(DbOAuthAuthorizingServerCallbackInfo info) nothrow @safe
    {
        this._info = info;
    }

    final void run() @safe
    {
        debug(debug_pham_db_db_oauth) debug writeln(__FUNCTION__, "()");

        auto serverInfo = new SocketServerInfo();
        serverInfo.address = loopbackHost;
        serverInfo.port = _info.port;
        serverInfo.acceptTimeout = _info.getTimeOut();
        serverInfo.serviceHandler = &serverService;
        serverInfo.errorHandler = &serverError;
        serverInfo.doneQueryHandler = &serverDoneQuery;
        serverInfo.endHandler = &serverEnd;
        auto server = new SocketServer(serverInfo);
        server.start();
    }

    @property final DbOAuthAuthorizingServerCallbackInfo info() const nothrow @safe
    {
        return _info;
    }

    @property final DbOAuthAuthorizingServerCallbackResult result() const nothrow @safe
    {
        return _result;
    }

public:
    ResultStatus lastError;

protected:
    final bool serverDoneQuery(SocketServer server) nothrow
    {
        const timeOut = _info.getTimeOut();
        _timeOuted = server.startTime.peek() >= timeOut;
        return _timeOuted;
    }

    final void serverEnd(SocketServer server) nothrow
    {
        if (_timeOuted && lastError.isOK && _result.status == DbOAuthAuthorizingServerCallbackStatus.unknown)
            lastError.set(eTimeout, null);
    }

    final int serverError(ResultStatus error, SocketServerClient, SocketServer, Exception) nothrow
    {
        this.lastError = error;
        return 1; // 1=Stop servicing further
    }

    final int serverService(SocketServerClient client, SocketServer) @trusted // cast(string)
    {
        Appender!(ubyte[]) requestBuffer;
        requestBuffer.reserve(500);
        const len = receiveData(client, requestBuffer);
        if (len)
        {
            auto nameValues = parseGetRequest(cast(string)requestBuffer.data);
            extractRequest(nameValues);
        }

        responseRequest(client);
        return 1; // 1=Stop servicing further
    }

    final void extractRequest(NamedValue!string[] nameValues)
    {
        extractRequest(nameValues, _result);
    }

    static void extractRequest(NamedValue!string[] nameValues, out DbOAuthAuthorizingServerCallbackResult resultData)
    {
        debug(debug_pham_db_db_oauth)
        {
            import pham.utl.utl_text : toString;
            debug writeln(__FUNCTION__, "(nameValues=", nameValues.toString(), ")");
        }

        resultData.reset();
        foreach (ref nameValue; nameValues)
        {
            if (sameName(nameValue.name, "code"))
                resultData.code = uriDecode(nameValue.value);
            else if (sameName(nameValue.name, "state"))
                resultData.state = uriDecode(nameValue.value);
            else if (sameName(nameValue.name, "error"))
                resultData.error = uriDecode(nameValue.value);
            else if (sameName(nameValue.name, "error_description"))
                resultData.errorDescription = uriDecode(nameValue.value);
        }
        atomicStore(resultData.done, 1);
    }


    // Extract query string from GET request
    // Ex: GET /somewhere/fun HTTP/1.1 -> "somewhere/fun"
    static NamedValue!string[] parseGetRequest(string request) nothrow
    {
        debug(debug_pham_db_db_oauth) debug writeln(__FUNCTION__, "(request=", request, ")");

        // Check for minimum length
        if (request.length <= "GET / HTTP/".length)
            return null;

        auto pGetText = "GET ";
        auto pGet = request.simpleIndexOf(pGetText);
        if (pGet >= 0)
        {
            pGet = -1;
            request = request[pGetText.length..$].simpleTrimLeft();
            foreach (s; ["/?", "?", "/"])
            {
                if (request.simpleStartWith(s))
                {
                    pGetText = s;
                    pGet = 0;
                    break;
                }
            }
        }
        debug(debug_pham_db_db_oauth) debug writeln("\t", "pGet=", pGet, ", pGetText=", pGetText);
        if (pGet < 0)
            return null;

        auto pHttp = request.simpleIndexOf(" HTTP/");
        debug(debug_pham_db_db_oauth) debug writeln("\t", "pHttp=", pHttp);
        if (pHttp < 0 || pHttp <= pGet)
            return null;

        const queryStart = pGet + pGetText.length;
        const queryLength = pHttp - queryStart;
        auto queryString = request[queryStart..queryStart + queryLength].simpleTrim();
        debug(debug_pham_db_db_oauth) debug writeln("\t", "queryStart=", queryStart, ", queryLength=", queryLength, ", queryString='", queryString, "'");
        return uriSplitParameters(queryString);
    }

    /* Sample raw get data
    GET /index.html HTTP/1.1\r\n
    Host: www.example.com\r\n
    User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/58.0.3029.110 Safari/537.36\r\n
    Accept: text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*//*;q=0.8\r\n
    Connection: close\r\n
    \r\n
    */
    final size_t receiveData(SocketServerClient client, ref Appender!(ubyte[]) buffer)
    {
        debug(debug_pham_db_db_oauth) debug writeln(__FUNCTION__, "()");

        size_t result;
        ubyte[500] readBuffer = void;
        while (true)
        {
            auto bytes = client.socket.receive(readBuffer);
            if (bytes <= 0)
                return result;

            buffer.put(readBuffer[0..bytes]);
            result += bytes;

            if (simpleIndexOf(buffer.data, [13,10,13,10]) >= 0)
                break;
        }
        return result;
    }

    final void responseRequest(SocketServerClient client)
    {
        debug(debug_pham_db_db_oauth) debug writeln(__FUNCTION__, "(code=", _result.code,
            ", state=", _result.state, ", error=", _result.error, ", errorDescription=", _result.errorDescription, ")");

        string htmlContent;

        final switch (_result.status())
        {
            case DbOAuthAuthorizingServerCallbackStatus.ok:
                htmlContent =
                  "<html>" ~
                    "<body>" ~
                      "<h1>" ~ htmlEncode(_info.getHeaderSuccess()) ~ "</h1>" ~
                      "<p>" ~ htmlEncode(_info.getMessageSuccess()) ~ "</p>" ~
                    "</body>" ~
                  "</html>";
                break;

            case DbOAuthAuthorizingServerCallbackStatus.error:
                htmlContent =
                  "<html>" ~
                    "<body>" ~
                      "<h1>" ~ htmlEncode(_info.getHeaderError()) ~ "</h1>" ~
                      "<p>" ~ htmlEncode(_info.getErrorLabel()) ~ ": " ~ htmlEncode(_result.error) ~ "</p>" ~
                      "<p>" ~ htmlEncode(_result.errorDescription) ~ "</p>" ~
                    "</body>" ~
                  "</html>";
                break;

            case DbOAuthAuthorizingServerCallbackStatus.unknown:
                htmlContent =
                  "<html>" ~
                    "<body>" ~
                      "<h1>" ~ htmlEncode(_info.getHeaderOther()) ~ "</h1>" ~
                    "</body>" ~
                  "</html>";
                break;
        }

        auto response =
            "HTTP/1.1 200 OK" ~ htmlNewline ~
            "Content-Type: text/html; charset=utf-8" ~ htmlNewline ~
            "Content-Length: " ~ text(htmlContent.length) ~ htmlNewline ~ htmlNewline ~
            htmlContent;

        debug(debug_pham_db_db_oauth) debug writeln("\t", "'", response, "'");

        auto sendData = response.representation();
        client.socket.send(sendData);
    }

private:
    DbOAuthAuthorizingServerCallbackInfo _info;
    DbOAuthAuthorizingServerCallbackResult _result;
    bool _timeOuted;
}


private:

unittest // DbOAuth.createInitialResponse
{
    auto s = DbOAuth.createInitialResponse(true, "");
    assert(s.isOK);
    assert(s == "n,,\x01auth=\x01\x01", "\"" ~ s ~ "\"");

    s = DbOAuth.createInitialResponse(true, "XyZ");
    assert(s.isOK);
    assert(s == "n,,\x01auth=\x01\x01", "\"" ~ s ~ "\"");

    s = DbOAuth.createInitialResponse(false, "XyZ");
    assert(s.isOK);
    assert(s == "n,,\x01auth=Bearer XyZ\x01\x01", "\"" ~ s ~ "\"");

    s = DbOAuth.createInitialResponse(false, "");
    assert(s.isError);
}

unittest // DbOAuthAuthorizingServerCallback.parseGetRequest
{
    //import std.stdio : writeln;

    auto nvs = DbOAuthAuthorizingServerCallback.parseGetRequest("GET /code=123&state=xyz HTTP/1.1\r\n");
    assert(nvs.length == 2);
    assert(nvs[0].name == "code");
    assert(nvs[0].value == "123");
    assert(nvs[1].name == "state");
    assert(nvs[1].value == "xyz");

    nvs = DbOAuthAuthorizingServerCallback.parseGetRequest("GET /?error=Error123&error_description=Errorxyz HTTP/1.1\r\n");
    assert(nvs.length == 2);
    assert(nvs[0].name == "error");
    assert(nvs[0].value == "Error123");
    assert(nvs[1].name == "error_description");
    assert(nvs[1].value == "Errorxyz");

    nvs = DbOAuthAuthorizingServerCallback.parseGetRequest("GET ?error=Error123   HTTP/1.1\r\n");
    assert(nvs.length == 1);
    assert(nvs[0].name == "error");
    assert(nvs[0].value == "Error123");
}

unittest // DbOAuthAuthorizingServerCallback.extractRequest
{
    import pham.utl.utl_text : NamedValue;

    alias Pair = NamedValue!string;

    DbOAuthAuthorizingServerCallbackResult resultData;
    DbOAuthAuthorizingServerCallback.extractRequest([Pair("code", "Code123"), Pair("state", "Statexyz")], resultData);
    assert(resultData.code == "Code123");
    assert(resultData.state == "Statexyz");
    assert(resultData.error.length == 0);
    assert(resultData.errorDescription.length == 0);

    resultData.reset();
    DbOAuthAuthorizingServerCallback.extractRequest([Pair("error", "Error123"), Pair("error_description", "Errorxyz")], resultData);
    assert(resultData.code.length == 0);
    assert(resultData.state.length == 0);
    assert(resultData.error == "Error123");
    assert(resultData.errorDescription == "Errorxyz");

    resultData.reset();
    DbOAuthAuthorizingServerCallback.extractRequest([Pair("Code123", "Code123"), Pair("Statexyz", "Statexyz"), Pair("error123", "Error123"), Pair("Errorxyz", "Errorxyz")], resultData);
    assert(resultData.code.length == 0);
    assert(resultData.state.length == 0);
    assert(resultData.error.length == 0);
    assert(resultData.errorDescription.length == 0);
}
