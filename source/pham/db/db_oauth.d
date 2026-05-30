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

import core.sys.windows.dpapi;
import core.atomic : atomicLoad, atomicStore;
import core.time : Duration, dur;
import std.conv : text;
import std.process : Pid;
import std.string : representation;

import pham.dtm.dtm_date : DateTime;
import pham.io.io_socket;
import pham.io.io_socket_service;
import pham.json.json_value;
import pham.utl.utl_array_append : Appender;
import pham.utl.utl_html;
import pham.utl.utl_result : ResultIf, ResultStatus;

debug(debug_pham_db_db_oauth) import pham.db.db_debug;
import pham.db.db_auth;
import pham.db.db_message;
import pham.db.db_type : DbScheme;

@safe:

struct DbOAuth
{
@safe:

public:
    this(string name, string mechanism, DbScheme scheme) nothrow
    {
        this._name = name;
        this._mechanism = mechanism;
        this._scheme = scheme;
    }

    ResultIf!string authorizeAccessToken(string authorizerURL, const(char)[] clientId, string scopes, string providerName)
    {
        auto actualAuthorizerURL = request.startAuthorizingURL(authorizerURL, clientId, scopes, providerName);
        return request.startAuthorizing(actualAuthorizerURL[]);
    }

    ResultIf!DbOAuthDataResponse requestAccessToken(string issuerURL, const(char)[] accessCode)
    {
        auto requestAccessTokenData = request.requestAccessTokenPostData(accessCode);
        return request.requestAccessToken(issuerURL, requestAccessTokenData[]);
    }

    @property int multiStates() const @nogc nothrow pure
    {
        // init, bearerSent, requestingToken, serverError
        return 3;
    }

    @property string name() const nothrow pure
    {
        return _name;
    }

    @property DbScheme scheme() const nothrow pure
    {
        return _scheme;
    }

    @property string mechanism() const nothrow pure
    {
        return _mechanism;
    }

public:
    DbOAuthDataRequest request;

private:
    static immutable string errorStatusField = "status";
    static immutable string errorScopeField = "scope";
    static immutable string errorOpenIdConfigField = "openid-configuration";

    string _mechanism;
    string _name;
    DbScheme _scheme;
}

struct DbOAuthDataRequest
{
public:
    /**
     * Returns authorized access-code if successful
     */
    ResultIf!string startAuthorizing(const(char)[] actualAuthorizerURL) nothrow @safe
    {
        import pham.utl.utl_system : runDefaultBrowser, waitFor;

        auto rdb = runDefaultBrowser(actualAuthorizerURL.idup);
        if (rdb.isError)
            return ResultIf!string.error(DbErrorCode.connect, rdb.errorMessage);

        authorizingServerCallback = new DbOAuthAuthorizingServerCallback(authorizingServerCallbackInfo);
        authorizingServerCallback.run();
        auto wfr = waitFor(rdb.value, authorizingServerCallbackInfo.getTimeOut(), &checkAuthorizing, null);
        if (authorizingServerCallback.isResultDataSet())
        {
            if (authorizingServerCallback.callbackResult.isError)
                return ResultIf!string.error(DbErrorCode.connect, authorizingServerCallback.callbackResult.errorMessage);

            return ResultIf!string.ok(authorizingServerCallback.callbackResult.value);
        }
        else
            return ResultIf!string.error(DbErrorCode.connect, wfr.errorMessage);
    }

    CipherBuffer!char startAuthorizingURL(string authorizerURL, const(char)[] clientId, string scopes, string providerName) nothrow @safe
    {
        import pham.utl.utl_text : simpleEndWithAny;

        this.clientId = clientId;
        this.scopes = scopes;
        this.providerName = providerName;

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
        CipherBuffer!char result;

        result.put(authorizerURL);
        if (authorizerURL.simpleEndWithAny("?&") < 0)
            result.put("?");

        result.put("&client_id=").put(uriEncode(clientId))
            .put("&scope=").put(uriEncode(scopes))
            .put("&state=").put(uriEncode(accessState))
            .put("&redirect_uri=").put(uriEncode(redirectURL))
            .put("&response_type=").put(uriEncode(responseType))
            .put("&code_challenge=").put(digestVerifierCode())
            .put("&code_challenge_method=S256");
            //~ "&include_granted_scopes=true"

        if (extraAuthorizerParams.length)
            result.put("&").put(uriParameters(extraAuthorizerParams));

        return result;
    }

    ResultIf!DbOAuthDataResponse requestAccessToken(string issuerURL, const(char)[] postAccessData) nothrow @trusted
    {
        import std.net.curl : HTTP, httpPost = post;

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
            return ResultIf!DbOAuthDataResponse.error(DbErrorCode.connect, ex.msg);
        }

        if (receiveAccessData.length == 0)
            return ResultIf!DbOAuthDataResponse.error(DbErrorCode.connect, "No authorization data");

        DbOAuthDataResponse result;
        try
        {
            result = DbOAuthDataResponse.parse(receiveAccessData);
        }
        catch (Exception ex)
        {
            return ResultIf!DbOAuthDataResponse.error(DbErrorCode.connect, ex.msg);
        }
        if (result.isEmpty)
            return ResultIf!DbOAuthDataResponse.error(DbErrorCode.connect, "Invalid authorization data");

        return ResultIf!DbOAuthDataResponse.ok(result);

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

    CipherBuffer!char requestAccessTokenPostData(const(char)[] accessCode) nothrow @safe
    {
        CipherBuffer!char result;

        result.put("client_id=").put(uriEncode!(const(char)[])(clientId[]))
            .put("&scope=").put(uriEncode(scopes))
            .put("&code=").put(uriEncode(accessCode))
            .put("&grant_type=authorization_code")
            .put("&code_verifier=").put(uriEncode(verifierCode));

        if (extraRequestAccessParams.length)
            result.put("&").put(uriParameters(extraRequestAccessParams));

        return result;
    }

public:
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
    string accessState;
    CipherRawKey!char clientId;
    NamedValue!string[] extraAuthorizerParams;
    NamedValue!string[] extraRequestAccessParams;
    string providerName;
    string responseType;
    string scopes;
    string verifierCode;

    DbOAuthAuthorizingServerCallbackInfo authorizingServerCallbackInfo;

private:
    int checkAuthorizing(void*, long) nothrow @safe
    {
        assert(authorizingServerCallback !is null);

        return authorizingServerCallback.isResultDataSet() ? 1 : 0;
    }

private:
    DbOAuthAuthorizingServerCallback authorizingServerCallback;
}

struct DbOAuthDataResponse
{
@safe:

public:
    bool isEmpty() const nothrow
    {
        return errorResponse.error.length == 0 && okResponse.accessCode.length == 0;
    }

    bool isError() const nothrow
    {
        return errorResponse.error.length != 0 || okResponse.accessCode.length == 0;
    }

    static bool isError(ref JSONValue jsonObjectResponse, ref DbOAuthDataResponseError errorResponse)
    {
        auto error_ = "error" in jsonObjectResponse;
        auto errorDescription = "error_description" in jsonObjectResponse;
        auto errorCodes = "error_codes" in jsonObjectResponse;
        auto timestamp = "timestamp" in jsonObjectResponse;
        auto traceId = "trace_id" in jsonObjectResponse;
        auto correlationId = "correlation_id" in jsonObjectResponse;

        if (error_ is null || error_.type != JSONType.string
            || errorDescription is null || errorDescription.type != JSONType.string
            || errorCodes is null || errorCodes.type != JSONType.array
            || timestamp is null || timestamp.type != JSONType.string
            || traceId is null || traceId.type != JSONType.string
            || correlationId is null || correlationId.type != JSONType.string)
            return false;

        errorResponse.error = error_.get!string();
        errorResponse.errorDescription = errorDescription.get!string();
        errorResponse.errorCodes = errorCodes.get!(int[])();
        errorResponse.timeStamp = timestamp.get!string();
        errorResponse.traceId = traceId.get!string();
        errorResponse.correlationId = correlationId.get!string();
        return true;
    }

    bool isOK() const nothrow
    {
        return !isError;
    }

    static bool isOK(ref JSONValue jsonObjectResponse, ref DbOAuthDataResponseOK okResponse)
    {
        auto accessToken = "access_token" in jsonObjectResponse;
        auto tokenType = "token_type" in jsonObjectResponse;
        auto expiresIn = "expires_in" in jsonObjectResponse;
        auto scope_ = "scope" in jsonObjectResponse;
        auto refreshToken = "refresh_token" in jsonObjectResponse;
        auto idToken = "id_token" in jsonObjectResponse;

        if (accessToken is null || accessToken.type != JSONType.string
            || tokenType is null || tokenType.type != JSONType.string
            || expiresIn is null || expiresIn.type != JSONType.integer
            || scope_ is null || scope_.type != JSONType.string
            || refreshToken is null || refreshToken.type != JSONType.string
            || idToken is null || idToken.type != JSONType.string)
            return false;

        okResponse.accessCode = accessToken.get!string();
        okResponse.idToken = idToken.get!string();
        okResponse.refreshToken = refreshToken.get!string();
        okResponse.scopes = scope_.get!string();
        okResponse.tokenType = tokenType.get!string();
        okResponse.expiredStarted = DateTime.utcNow;
        okResponse.expiredIn = expiresIn.get!int();
        return true;
    }

    static DbOAuthDataResponse parse(scope const(char)[] jsonResponse)
    {
        DbOAuthDataResponse result;
        auto json = JSONValue.parse(jsonResponse);
        if (json.type != JSONType.object)
            return result;

        if (isOK(json, result.okResponse))
            return result;
        else if (isError(json, result.errorResponse))
            return result;
        else
            return result;
    }

    void reset() nothrow
    {
        errorResponse.reset();
        okResponse.reset();
    }

public:
    DbOAuthDataResponseError errorResponse;
    DbOAuthDataResponseOK okResponse;
}

struct DbOAuthDataResponseError
{
@safe:

public:
    void reset() nothrow
    {
        error = errorDescription = timeStamp = traceId = correlationId = null;
        errorCodes = null;
    }

public:
    string error;
    string errorDescription;
    int[] errorCodes;
    string timeStamp;
    string traceId;
    string correlationId;
}

struct DbOAuthDataResponseOK
{
@safe:

public:
    void reset() nothrow
    {
        accessCode.clear();
        refreshToken.clear();
        idToken = scopes = tokenType = null;
        expiredStarted = DateTime.min;
        expiredIn = 0;
    }

public:
    string idToken;
    string scopes;
    string tokenType; // Bearer
    CipherRawKey!char accessCode;
    CipherRawKey!char refreshToken;
    DateTime expiredStarted;
    uint expiredIn;
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

    final bool isResultDataSet() const nothrow @safe
    {
        return _resultData.isSet();
    }

    final void run() nothrow @safe
    {
        debug(debug_pham_db_db_oauth) debug writeln(__FUNCTION__, "()");

        this._resultData.reset();
        this._lastStatus.reset();
        this.callbackResult = ResultIf!string.error(ResultCode.uninitialized, "Uninitialized");

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

public:
    ResultIf!string callbackResult;

protected:
    final bool serverDoneQuery(SocketServer server) nothrow
    {
        if (_lastStatus.isError || _resultData.isSet())
            return true;

        const timeOut = _info.getTimeOut();
        if (server.startTime.peek() >= timeOut)
        {
            _lastStatus = ResultStatus.error(ResultCode.timeOut, "TimeOut");
            return true;
        }

        return false;
    }

    final void serverEnd(SocketServer server) nothrow
    {
        if (!_resultData.isSet())
        {
            if (_lastStatus.isError)
                callbackResult = ResultIf!string.error(_lastStatus);
            else
                callbackResult = ResultIf!string.error(ResultCode.timeOut, "TimeOut");
        }
    }

    final int serverError(ResultStatus error, SocketServerClient, SocketServer, Exception) nothrow
    {
        if (_lastStatus.isOK && !_resultData.isSet())
            this._lastStatus = error;
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
        else if (_lastStatus.isError)
            callbackResult = ResultIf!string.error(_lastStatus);
        else
            callbackResult = ResultIf!string.error(ResultCode.timeOut, "TimeOut");

        responseRequest(client);
        return 1; // 1=Stop servicing further
    }

    final void extractRequest(NamedValue!string[] nameValues)
    {
        extractRequest(nameValues, _resultData);
        if (_resultData.status == DbOAuthAuthorizingServerCallbackStatus.ok)
            callbackResult = ResultIf!string.ok(_resultData.code);
        else
        {
            auto msg = _resultData.errorDescription.length != 0
                ? _resultData.errorDescription
                : _resultData.error;
            callbackResult = ResultIf!string.error(ResultCode.error, msg);
        }
    }

    static void extractRequest(NamedValue!string[] nameValues, ref DbOAuthAuthorizingServerCallbackResult resultData)
    {
        debug(debug_pham_db_db_oauth)
        {
            import pham.utl.utl_text : toString;
            debug writeln(__FUNCTION__, "(nameValues=", nameValues.toString(), ")");
        }

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

            if (simpleIndexOf(buffer.data, [13, 10, 13, 10]) >= 0)
                break;
        }
        return result;
    }

    final void responseRequest(SocketServerClient client)
    {
        debug(debug_pham_db_db_oauth) debug writeln(__FUNCTION__, "(code=", _resultData.code,
            ", state=", _resultData.state, ", error=", _resultData.error, ", errorDescription=", _resultData.errorDescription, ")");

        string htmlContent;

        final switch (_resultData.status())
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
                      "<p>" ~ htmlEncode(_info.getErrorLabel()) ~ ": " ~ htmlEncode(_resultData.error) ~ "</p>" ~
                      "<p>" ~ htmlEncode(_resultData.errorDescription) ~ "</p>" ~
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
    DbOAuthAuthorizingServerCallbackResult _resultData;
    ResultStatus _lastStatus;
}

struct DbOAuthEndPoint
{
    string providerName;
    string authorizerURL;
    string issuerURL;
}

static immutable DbOAuthEndPoint[] oauthEndPoints = [
    DbOAuthEndPoint("Amazon", "https://www.amazon.com/ap/oa", "https://api.amazon.com/auth/o2/token"),
    // https://developer.apple.com/documentation/signinwithapplerestapi
    DbOAuthEndPoint("Apple", "https://appleid.apple.com/auth/authorize", "https://appleid.apple.com/auth/token"),
    DbOAuthEndPoint("Bitbucket", "https://bitbucket.org/site/oauth2/authorize", "https://bitbucket.org/site/oauth2/access_token"),
    DbOAuthEndPoint("Coinbase", "https://login.coinbase.com/oauth2/auth", "https://login.coinbase.com/oauth2/token"),
    // https://docs.cdp.coinbase.com/coinbase-app/docs/coinbase-app-reference
    DbOAuthEndPoint("Discord", "https://discord.com/oauth2/authorize", "https://discord.com/api/oauth2/token"),
    // https://developers.dropbox.com/oauth-guide
    DbOAuthEndPoint("Dropbox", "https://www.dropbox.com/oauth2/authorize", "https://api.dropboxapi.com/oauth2/token"),
    // https://developer.ebay.com/api-docs/static/authorization_guide_landing.html
    DbOAuthEndPoint("Ebay", "https://auth.ebay.com/oauth2/authorize", "https://api.ebay.com/identity/v1/oauth2/token"),
    // https://developers.facebook.com/docs/facebook-login/guides/advanced/manual-flow
    DbOAuthEndPoint("Facebook", "https://www.facebook.com/v22.0/dialog/oauth", "https://graph.facebook.com/v22.0/oauth/access_token"),
    DbOAuthEndPoint("Foursquare", "https://foursquare.com/oauth2/authorize", "https://foursquare.com/oauth2/access_token"),
    DbOAuthEndPoint("Github", "https://github.com/login/oauth/authorize", "https://github.com/login/oauth/access_token"),
    DbOAuthEndPoint("GitLab", "https://gitlab.com/oauth/authorize", "https://gitlab.com/oauth/token"),
    DbOAuthEndPoint("Google", "https://accounts.google.com/o/oauth2/auth", "https://oauth2.googleapis.com/token"),
    DbOAuthEndPoint("Heroku", "https://id.heroku.com/oauth/authorize", "https://id.heroku.com/oauth/token"),
    DbOAuthEndPoint("Instagram", "https://api.instagram.com/oauth/authorize", "https://api.instagram.com/oauth/access_token"),
    DbOAuthEndPoint("LinkedIn", "https://www.linkedin.com/oauth/v2/authorization", "https://www.linkedin.com/oauth/v2/accessToken"),
    DbOAuthEndPoint("Microsoft", "https://login.live.com/oauth20_authorize.srf", "https://login.live.com/oauth20_token.srf"),
    // https://wiki.openstreetmap.org/wiki/OAuth
    DbOAuthEndPoint("OpenStreetMap.org", "https://www.openstreetmap.org/oauth2/authorize", "https://www.openstreetmap.org/oauth2/token"),
    DbOAuthEndPoint("PayPal", "https://www.paypal.com/webapps/auth/protocol/openidconnect/v1/authorize", "https://api.paypal.com/v1/identity/openidconnect/tokenservice"),
    // https://api.slack.com/authentication/oauth-v2
    DbOAuthEndPoint("Slack", "https://slack.com/oauth/v2/authorize", "https://slack.com/api/oauth.v2.access"),
    DbOAuthEndPoint("Spotify", "https://accounts.spotify.com/authorize", "https://accounts.spotify.com/api/token"),
    DbOAuthEndPoint("Uber", "https://login.uber.com/oauth/v2/authorize", "https://login.uber.com/oauth/v2/token"),
    // https://docs.x.com/resources/fundamentals/authentication/oauth-2-0/user-access-token
    DbOAuthEndPoint("Twitter", "https://x.com/i/oauth2/authorize", "https://api.x.com/2/oauth2/token"),
    DbOAuthEndPoint("Yahoo", "https://api.login.yahoo.com/oauth2/request_auth", "https://api.login.yahoo.com/oauth2/get_token"),
    DbOAuthEndPoint("Zoom", "https://zoom.us/oauth/authorize", "https://zoom.us/oauth/token"),
    //DbOAuthEndPoint("", "", ""),
    ];


// Any below codes are private
private:

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

unittest // DbOAuthDataResponse.isOK
{
    static immutable string jsonResponseOK = q"JSON
{
  "access_token": "eyJ0eXAiOiJKV1QiLCJhbGciOiJSUzI1NiIsIng1dCI6Ik5HVEZ2ZEstZnl0aEV1Q...",
  "token_type": "Bearer",
  "expires_in": 3599,
  "scope": "https://graph.microsoft.com/mail.read",
  "refresh_token": "AwABAAAAvPM1KaPlrEqdFSBzjqfTGAMxZGUTdM0t4B4...",
  "id_token": "eyJ0eXAiOiJKV1QiLCJhbGciOiJub25lIn0.eyJhdWQiOiIyZDRkMTFhMi1mODE0LTQ2YTctOD..."
}
JSON";

    auto p = DbOAuthDataResponse.parse(jsonResponseOK);
    assert(!p.isError());
    assert(p.isOK());
    assert(p.okResponse.accessCode == "eyJ0eXAiOiJKV1QiLCJhbGciOiJSUzI1NiIsIng1dCI6Ik5HVEZ2ZEstZnl0aEV1Q...");
    assert(p.okResponse.idToken == "eyJ0eXAiOiJKV1QiLCJhbGciOiJub25lIn0.eyJhdWQiOiIyZDRkMTFhMi1mODE0LTQ2YTctOD...");
    assert(p.okResponse.refreshToken == "AwABAAAAvPM1KaPlrEqdFSBzjqfTGAMxZGUTdM0t4B4...");
    assert(p.okResponse.scopes == "https://graph.microsoft.com/mail.read");
    assert(p.okResponse.tokenType == "Bearer");
    assert(p.okResponse.expiredIn == 3599);
    assert(p.okResponse.expiredStarted != DateTime.min);
}

unittest // DbOAuthDataResponse.isError
{
    static immutable string jsonResponseError = q"JSON
{
  "error": "invalid_scope",
  "error_description": "AADSTS70011: The provided value for the input parameter 'scope' is not valid. The scope https://foo.microsoft.com/mail.read is not valid.\nTrace ID: 0000aaaa-11bb-cccc-dd22-eeeeee333333\nCorrelation ID: aaaa0000-bb11-2222-33cc-444444dddddd\nTimestamp: 2016-01-09 02:02:12Z",
  "error_codes": [70011],
  "timestamp": "2016-01-09 02:02:12Z",
  "trace_id": "0000aaaa-11bb-cccc-dd22-eeeeee333333",
  "correlation_id": "aaaa0000-bb11-2222-33cc-444444dddddd"
}
JSON";

    auto p = DbOAuthDataResponse.parse(jsonResponseError);
    assert(!p.isOK());
    assert(p.isError());
    assert(p.errorResponse.error == "invalid_scope");
    assert(p.errorResponse.errorDescription == "AADSTS70011: The provided value for the input parameter 'scope' is not valid. The scope https://foo.microsoft.com/mail.read is not valid.\nTrace ID: 0000aaaa-11bb-cccc-dd22-eeeeee333333\nCorrelation ID: aaaa0000-bb11-2222-33cc-444444dddddd\nTimestamp: 2016-01-09 02:02:12Z");
    assert(p.errorResponse.errorCodes == [70011]);
    assert(p.errorResponse.timeStamp == "2016-01-09 02:02:12Z");
    assert(p.errorResponse.traceId == "0000aaaa-11bb-cccc-dd22-eeeeee333333");
    assert(p.errorResponse.correlationId == "aaaa0000-bb11-2222-33cc-444444dddddd");
}
