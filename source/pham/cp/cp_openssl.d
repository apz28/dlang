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

module pham.cp.openssl;

import std.string : fromStringz, toStringz;

public import pham.utl.result : ResultStatus;
import pham.cp.cipher : calculateBufferLength;
import pham.cp.openssl_binding;

@safe:

struct OpenSSLKeyInfo
{
nothrow @safe:

public:
    this(string name, OpenSSLCipherType ct, ushort blockLength, uint keyBitLength) pure
    {
        this.name = name;
        this.ct = ct;
        this.blockLength = blockLength;
        this.keyBitLength = keyBitLength;
    }

    static OpenSSLKeyInfo bf_cbc()
    {
        return OpenSSLKeyInfo("bf_cbc", &opensslApi.EVP_bf_cbc, 64 / 8, 448);
    }

    static OpenSSLKeyInfo bf_cfb()
    {
        return OpenSSLKeyInfo("bf_cfb", &opensslApi.EVP_bf_cfb, 64 / 8, 448);
    }

    static OpenSSLKeyInfo bf_ecb()
    {
        return OpenSSLKeyInfo("bf_ecb", &opensslApi.EVP_bf_ecb, 64 / 8, 448);
    }

    static OpenSSLKeyInfo bf_ofb()
    {
        return OpenSSLKeyInfo("bf_ofb", &opensslApi.EVP_bf_ofb, 64 / 8, 448);
    }

    static OpenSSLKeyInfo cast5_cbc()
    {
        return OpenSSLKeyInfo("cast5_cbc", &opensslApi.EVP_cast5_cbc, 64 / 8, 128);
    }

    static OpenSSLKeyInfo cast5_cfb()
    {
        return OpenSSLKeyInfo("cast5_cfb", &opensslApi.EVP_cast5_cfb, 64 / 8, 128);
    }

    static OpenSSLKeyInfo cast5_ecb()
    {
        return OpenSSLKeyInfo("cast5_ecb", &opensslApi.EVP_cast5_ecb, 64 / 8, 128);
    }

    static OpenSSLKeyInfo cast5_ofb()
    {
        return OpenSSLKeyInfo("cast5_ofb", &opensslApi.EVP_cast5_ofb, 64 / 8, 128);
    }

    static OpenSSLKeyInfo des_cbc()
    {
        return OpenSSLKeyInfo("des_cbc", &opensslApi.EVP_des_cbc, 64 / 8, 64);
    }

    static OpenSSLKeyInfo des_cfb()
    {
        return OpenSSLKeyInfo("des_cfb", &opensslApi.EVP_des_cfb, 64 / 8, 64);
    }

    static OpenSSLKeyInfo des_ecb()
    {
        return OpenSSLKeyInfo("des_ecb", &opensslApi.EVP_des_ecb, 64 / 8, 64);
    }

    static OpenSSLKeyInfo des_ofb()
    {
        return OpenSSLKeyInfo("des_ofb", &opensslApi.EVP_des_ofb, 64 / 8, 64);
    }

    static OpenSSLKeyInfo des_ede3_cbc()
    {
        return OpenSSLKeyInfo("des_ede3_cbc", &opensslApi.EVP_des_ede3_cbc, 64 / 8, 192);
    }

    static OpenSSLKeyInfo des_ede3_cfb()
    {
        return OpenSSLKeyInfo("des_ede3_cfb", &opensslApi.EVP_des_ede3_cfb, 64 / 8, 192);
    }

    static OpenSSLKeyInfo des_ede3_ecb()
    {
        return OpenSSLKeyInfo("des_ede3_ecb", &opensslApi.EVP_des_ede3_ecb, 64 / 8, 192);
    }

    static OpenSSLKeyInfo des_ede3_ofb()
    {
        return OpenSSLKeyInfo("des_ede3_ofb", &opensslApi.EVP_des_ede3_ofb, 64 / 8, 192);
    }

    static OpenSSLKeyInfo aes_cbc(uint keyBitLength) pure
    {
        if (keyBitLength <= 128)
            return OpenSSLKeyInfo("aes_128_cbc", &opensslApi.EVP_aes_128_cbc, 128 / 8, 128);
        else if (keyBitLength <= 192)
            return OpenSSLKeyInfo("aes_192_cbc", &opensslApi.EVP_aes_192_cbc, 128 / 8, 192);
        else //if (keyBitLength <= 256)
            return OpenSSLKeyInfo("aes_256_cbc", &opensslApi.EVP_aes_256_cbc, 128 / 8, 256);
    }

    static OpenSSLKeyInfo aes_cfb(uint keyBitLength) pure
    {
        if (keyBitLength <= 128)
            return OpenSSLKeyInfo("aes_128_cfb", &opensslApi.EVP_aes_128_cfb, 128 / 8, 128);
        else if (keyBitLength <= 192)
            return OpenSSLKeyInfo("aes_192_cfb", &opensslApi.EVP_aes_192_cfb, 128 / 8, 192);
        else //if (keyBitLength <= 256)
            return OpenSSLKeyInfo("aes_256_cfb", &opensslApi.EVP_aes_256_cfb, 128 / 8, 256);
    }

    static OpenSSLKeyInfo aes_ecb(uint keyBitLength) pure
    {
        if (keyBitLength <= 128)
            return OpenSSLKeyInfo("aes_128_ecb", &opensslApi.EVP_aes_128_ecb, 128 / 8, 128);
        else if (keyBitLength <= 192)
            return OpenSSLKeyInfo("aes_192_ecb", &opensslApi.EVP_aes_192_ecb, 128 / 8, 192);
        else //if (keyBitLength <= 256)
            return OpenSSLKeyInfo("aes_256_ecb", &opensslApi.EVP_aes_256_ecb, 128 / 8, 256);
    }

    static OpenSSLKeyInfo aes_ofb(uint keyBitLength) pure
    {
        if (keyBitLength <= 128)
            return OpenSSLKeyInfo("aes_128_ofb", &opensslApi.EVP_aes_128_ofb, 128 / 8, 128);
        else if (keyBitLength <= 192)
            return OpenSSLKeyInfo("aes_192_ofb", &opensslApi.EVP_aes_192_ofb, 128 / 8, 192);
        else //if (keyBitLength <= 256)
            return OpenSSLKeyInfo("aes_256_ofb", &opensslApi.EVP_aes_256_ofb, 128 / 8, 256);
    }

    /**
     * Key length in bytes
     */
    pragma(inline, true)
    @property uint keyByteLength() const @nogc pure
    {
        return (keyBitLength + 7) / 8;
    }

public:
    string name;
    uint keyBitLength;
    OpenSSLCipherType ct;
    ushort blockLength;
}

struct OpenSSLClientSocket
{
    import std.array : join;
    import std.socket : socket_t;

    import pham.utl.system : lastSocketError;

nothrow @safe:

public:
    @disable this(ref typeof(this));
    @disable void opAssign(typeof(this));

    ~this()
    {
        dispose(false);
    }

    void close() @trusted
    {
        if (_connected && _ssl)
        {
            opensslApi.SSL_set_quiet_shutdown(_ssl, 1);
            if (1 != opensslApi.SSL_shutdown(_ssl))
            {
                //TODO log the error message
                //auto error = currentError("SSL_shutdown");
            }
        }

        _connected = false;
    }

    ResultStatus connect(socket_t socketHandle) @trusted
    in
    {
        assert(isInitialized && !isConnected);
    }
    do
    {
        //opensslApi.SSL_set_ex_data(_ssl, sslDataIndex(), &this);

        if (1 != opensslApi.SSL_set_fd(_ssl, cast(int)socketHandle))
            return currentError("SSL_set_fd");

        int r = opensslApi.SSL_connect(_ssl);
        if (1 != r)
            return r < 0 ? currentSSLError(_ssl, r, "SSL_connect") : currentError("SSL_connect");

        while (true)
        {
            r = opensslApi.SSL_accept(_ssl);
            if (r == 1)
                break;
            else if (r <= 0)
                return r < 0 ? currentSSLError(_ssl, r, "SSL_accept") : currentError("SSL_accept");
        }

        version (none)
        {
            auto cipher = opensslApi.SSL_get_current_cipher(_ssl);
            if (cipher !is null)
            {
                import pham.utl.test; dgWriteln("SSL_name=", fromStringz(opensslApi.SSL_CIPHER_get_name(cipher)), ", version=", fromStringz(opensslApi.SSL_CIPHER_get_version(cipher)));
            }
        }

        _connected = true;
        return ResultStatus.ok();
    }

    void dispose(bool disposing = true) @trusted
    {
        disposeSSLResources();
        sslCa = null;
        sslCaDir = null;
        sslCert = null;
        sslKey = null;
        sslKeyPassword = null;
        verificationHost = null;
        ciphers = null;
        dhp = null;
        dhg = null;
        dhq = null;
    }

    ResultStatus initialize() @trusted
    in
    {
        assert(!isInitialized);
    }
    do
    {
        _connected = false;

        auto apiStatus = opensslApi.status();
        if (apiStatus.isError)
            return apiStatus;

        auto initedCTX = initializeCTX();
        if (initedCTX.isError)
            return initedCTX;

        _ssl = opensslApi.SSL_new(_ctx);
        if (_ssl is null)
            return initializeError("SSL_new");

        return ResultStatus.ok();
    }

    ResultStatus receive(ubyte[] data, out size_t readSize) @trusted
    in
    {
        assert(isInitialized);
        assert(isConnected);
        assert(data.length < int.max);
    }
    do
    {
        //opensslApi.ERR_clear_error();
        readSize = 0;
        int tryCount;
        while (readSize < data.length)
        {
            const readingingSize = cast(int)(data.length - readSize);
            const int r = opensslApi.SSL_read(_ssl, &data[readSize], readingingSize);
            if (r > 0)
            {
                readSize += r;
                return ResultStatus.ok();
            }

            auto code = opensslApi.SSL_get_error(_ssl, r);
            switch (code)
            {
                case SSL_ERROR_NONE:
                case SSL_ERROR_WANT_READ:
                    if (++tryCount >= tryReadWriteMax)
                        return currentError("SSL_read", code);
                    opensslApi.ERR_clear_error();
                    break;
                case SSL_ERROR_SYSCALL:
                    auto sysStatus = lastSocketError("SSL_read");
                    if (sysStatus.errorCode == 0)
                    {
                        if (++tryCount >= tryReadWriteMax)
                            return ResultStatus.error(code, "SSL_read failed");
                        opensslApi.ERR_clear_error();
                    }
                    else
                        return sysStatus;
                    break;
                default:
                    return currentError("SSL_read", code);
            }
        }

        return ResultStatus.error(0, "SSL_read failed");
    }

    version (none)
    int receivePending() @trusted
    {
        return opensslApi.SSL_pending(_ssl);
    }

    ResultStatus send(scope const(ubyte)[] data, out size_t writtenSize) @trusted
    in
    {
        assert(isInitialized);
        assert(isConnected);
        assert(data.length < int.max);
    }
    do
    {
        //opensslApi.ERR_clear_error();
        writtenSize = 0;
        int tryCount;
        while (data.length)
        {
            const writtingSize = cast(int)data.length;
            const int r = opensslApi.SSL_write(_ssl, cast(void*)&data[0], writtingSize);
            if (r > 0)
            {
                writtenSize += r;
                if (r >= writtingSize)
                    return ResultStatus.ok();
                data = data[r..$];
                continue;
            }
            else
            {
                auto code = opensslApi.SSL_get_error(_ssl, r);
                switch (code)
                {
                    case SSL_ERROR_NONE:
                    case SSL_ERROR_WANT_WRITE:
                        if (++tryCount >= tryReadWriteMax)
                            return currentError("SSL_write", code);
                        opensslApi.ERR_clear_error();
                        break;
                    case SSL_ERROR_SYSCALL:
                        auto sysStatus = lastSocketError("SSL_write");
                        if (sysStatus.errorCode == 0)
                        {
                            if (++tryCount >= tryReadWriteMax)
                                return ResultStatus.error(code, "SSL_write failed");
                            opensslApi.ERR_clear_error();
                        }
                        else
                            return sysStatus;
                        break;
                    default:
                        return currentError("SSL_write", code);
                }
            }
        }

        return ResultStatus.ok();
    }

    static int sslDataIndex() @trusted
    {
        __gshared int idx = -1;
        if (idx == -1)
            idx = opensslApi.SSL_get_ex_new_index(0, cast(void*)"pham.cp.openssl.OpenSSLClientSocket".ptr, null, null, null);
        return idx;
    }

    void uninitialize()
    {
        close();
        disposeSSLResources();
    }

    ResultStatus verifyCertificate() @trusted
    in
    {
        assert(isInitialized);
        assert(isConnected);
    }
    do
    {
        X509* x509 = opensslApi.SSL_get_peer_certificate(_ssl);
        if (x509 is null)
            return currentError("SSL_get_peer_certificate");
        scope (exit)
            opensslApi.X509_free(x509);

        const vr = opensslApi.SSL_get_verify_result(_ssl);
        if (X509_V_OK != vr)
            return currentError("SSL_get_verify_result");

        if (verificationHost.length)
        {
            auto verificationHostz = toStringz(verificationHost);
            if (1 != opensslApi.X509_check_ip(x509, verificationHostz, verificationHost.length, 0))
            {
                if (1 != opensslApi.X509_check_host(x509, verificationHostz, verificationHost.length, 0, null))
                    return currentError("X509_check_host");
            }
        }

        return ResultStatus.ok();
    }

    version (none)
    static int verifyCallback(int preverify_ok, X509_STORE_CTX* sctx)
    {
        return 1; //1=OK

        version (none)
        {
        auto ssl = cast(SSL*)opensslApi.X509_STORE_CTX_get_ex_data(sctx, opensslApi.SSL_get_ex_data_X509_STORE_CTX_idx());
        auto clientSocket = cast(OpenSSLClientSocket*)opensslApi.SSL_get_ex_data(ssl, sslDataIndex());

        enum bufSize = 500;
        char[bufSize] buf;
        auto cert = X509_STORE_CTX_get_current_cert(sctx);
        int currentError = X509_STORE_CTX_get_error(sctx);

        const depth = X509_STORE_CTX_get_error_depth(sctx);
        X509_NAME_oneline(X509_get_subject_name(cert), buf, bufSize);

        /*
         * Catch a too long certificate chain. The depth limit set using
         * SSL_CTX_set_verify_depth() is by purpose set to "limit+1" so
         * that whenever the "depth>verify_depth" condition is met, we
         * have violated the limit and want to log this error condition.
         * We must do it here, because the CHAIN_TOO_LONG error would not
         * be found explicitly; only errors introduced by cutting off the
         * additional certificates would be logged.
         */
        //if (*clientSocket.verificationDepth && depth > *clientSocket.verificationDepth)
        //{
        //    X509_STORE_CTX_set_error(sctx, X509_V_ERR_CERT_CHAIN_TOO_LONG);
        //    preverify_ok = 0;
        //}

        if (!preverify_ok)
        {
            //printf("verify error:num=%d:%s:depth=%d:%s\n", err,
            //        X509_verify_cert_error_string(err), depth, buf);
        }


        /*
         * At this point, err contains the last verification error. We can use
         * it for something special
         */
        //if (!preverify_ok && (err == X509_V_ERR_UNABLE_TO_GET_ISSUER_CERT))
        //{
        //    X509_NAME_oneline(X509_get_issuer_name(sctx->current_cert), buf, bufSize);
        //    printf("issuer= %s\n", buf);
        //}

        //if (mydata->always_continue)
        //    return 1;
        //else
        //     return preverify_ok;
        }
    }

    @property SSL_CTX* ctx() @nogc pure
    {
        return _ctx;
    }

    pragma(inline, true)
    @property bool isConnected() const @nogc pure
    {
        return _connected;
    }

    pragma(inline, true)
    @property bool isInitialized() const @nogc pure
    {
        return _ssl !is null && _ctx !is null;
    }

    @property SSL* ssl() @nogc pure
    {
        return _ssl;
    }

public:
    string sslCa, sslCaDir;
    string sslCert;
    string sslKey;
    string sslKeyPassword;
    int sslCertType = SSL_FILETYPE_PEM; // if 0, sslCert is considered certificate_chain_file
    int sslKeyType = SSL_FILETYPE_PEM;

    OpenSSLVerifyCallback verificationCallback;
    string verificationHost;
    int verificationDepth;
    int verificationMode = -1; // SSL_VERIFY_NONE=0

    const(string)[] ciphers;
    const(ubyte)[] dhp, dhg, dhq; // dhq is optional

private:
    void disposeSSLResources() @trusted
    {
        if (_ssl !is null)
        {
            close();

            opensslApi.SSL_free(_ssl);
            _ssl = null;
        }

        if (_ctx !is null)
        {
            opensslApi.SSL_CTX_free(_ctx);
            _ctx = null;
        }
    }

    ResultStatus initializeCTX() @trusted
    {
        _ctx = opensslApi.SSL_CTX_new(opensslApi.TLS_client_method());
        if (_ctx is null)
            return initializeError("SSL_CTX_new");

        /*
        _ctx = opensslApi.SSL_CTX_new(opensslApi.TLS_method());
        if (_ctx is null)
            return initializeError("SSL_CTX_new");
        const flags = SSL_OP_NO_SSLv2 | SSL_OP_NO_SSLv3 | SSL_OP_NO_TLSv1 | SSL_OP_NO_TLSv1_1 | SSL_OP_NO_COMPRESSION;
        opensslApi.SSL_CTX_set_options(_ctx, flags);
        */

        if (ciphers.length)
        {
            auto cs = ciphers.join(":");
            auto csz = toStringz(cs);
            if (1 != opensslApi.SSL_CTX_set_cipher_list(_ctx, csz))
                return initializeError("SSL_CTX_set_cipher_list");
        }

        if (dhp.length && dhg.length)
        {
            auto dh = OpenSSLExt.createDH(dhp, dhq, dhg);
            if (dh !is null)
            {
                opensslApi.SSL_CTX_set_tmp_dh(_ctx, dh);
                opensslApi.DH_free(dh);
            }
        }

        string useSslCert = sslCert.length ? sslCert : sslKey;
        string useSslKey = sslKey.length ? sslKey : sslCert;

        if (useSslCert.length)
        {
            auto useSslCertz = toStringz(useSslCert);
            if (sslCertType == 0)
            {
                if (1 != opensslApi.SSL_CTX_use_certificate_chain_file(_ctx, useSslCertz))
                    return initializeError("SSL_CTX_use_certificate_chain_file");
            }
            else
            {
                if (1 != opensslApi.SSL_CTX_use_certificate_file(_ctx, useSslCertz, sslCertType))
                    return initializeError("SSL_CTX_use_certificate_file");
            }
        }

        if (useSslKey.length)
        {
            if (sslKeyPassword.length)
            {
                opensslApi.SSL_CTX_set_default_passwd_cb_userdata(_ctx, &this);
                opensslApi.SSL_CTX_set_default_passwd_cb(_ctx, &loadSslKeyPassword);
            }
            scope (exit)
            {
                if (sslKeyPassword.length)
                {
                    opensslApi.SSL_CTX_set_default_passwd_cb_userdata(_ctx, null);
                    opensslApi.SSL_CTX_set_default_passwd_cb(_ctx, null);
                }
            }

            auto useSslKeyz = toStringz(useSslKey);
            if (1 != opensslApi.SSL_CTX_use_PrivateKey_file(_ctx, useSslKeyz, sslKeyType))
                return initializeError("SSL_CTX_use_PrivateKey_file");
        }

        if (sslCa.length || sslCaDir.length)
        {
            auto sslCaz = sslCa.length ? toStringz(sslCa) : null;
            auto sslCaDirz = sslCaDir.length ? toStringz(sslCaDir) : null;
            if (1 != opensslApi.SSL_CTX_load_verify_locations(_ctx, sslCaz, sslCaDirz))
                return initializeError("SSL_CTX_load_verify_locations");
        }
        else if (1 != opensslApi.SSL_CTX_set_default_verify_paths(_ctx))
            return initializeError("SSL_CTX_set_default_verify_paths");

        if (verificationDepth > 0)
            opensslApi.SSL_CTX_set_verify_depth(_ctx, verificationDepth);

        if (verificationMode >= 0)
            opensslApi.SSL_CTX_set_verify(_ctx, verificationMode, verificationCallback);

        if (sslCert.length && sslKey.length)
        {
            if (1 != opensslApi.SSL_CTX_check_private_key(_ctx))
                return initializeError("SSL_CTX_check_private_key");
        }

        if (verificationHost.length)
        {
            X509_VERIFY_PARAM* param = opensslApi.SSL_CTX_get0_param(_ctx);

            /*
             * As we don't know if the server_host contains IP addr or hostname
             * call X509_VERIFY_PARAM_set1_ip_asc() first and if it returns an error
             * (not valid IP address), call X509_VERIFY_PARAM_set1_host().
             */
            auto verificationHostz = toStringz(verificationHost);
            if (1 != opensslApi.X509_VERIFY_PARAM_set1_ip_asc(param, verificationHostz))
            {
                if (1 != opensslApi.X509_VERIFY_PARAM_set1_host(param, verificationHostz, verificationHost.length))
                    return initializeError("X509_VERIFY_PARAM_set1_host");
            }
        }

        return ResultStatus.ok();
    }

    ResultStatus initializeError(string apiName) @trusted
    {
        auto error = currentError(apiName);
        disposeSSLResources();
        return error;
    }

    static int loadSslKeyPassword(char* buffer, int size, int rwFlag, void* cbu) @trusted
    {
        import core.stdc.string : memcpy;

        auto self = cast(OpenSSLClientSocket*)cbu;
        const maxLen = size - 1;
        const len = cast(int)self.sslKeyPassword.length <= maxLen ? cast(int)self.sslKeyPassword.length : maxLen;
        memcpy(buffer, &self.sslKeyPassword[0], len);
        buffer[len] = '\0';
        return len;
    }

private:
    enum tryReadWriteMax = 3;
    SSL_CTX* _ctx; // Client context
    SSL* _ssl;
    bool _connected;
}

struct OpenSSLCrypt
{
nothrow @safe:

public:
    @disable this(this);
    @disable void opAssign(typeof(this));

    this(OpenSSLKeyInfo info, scope const(ubyte)[] key, scope const(ubyte)[] iv) pure
    {
        this._info = info;
        this._key = key.dup;
        this._iv = iv.dup;
    }

    this(ref typeof(this) rhs)
    {
        this.disposeSSLResources();
        this._ctx = rhs._ctx;
        rhs._ctx = null;
        this._info = rhs._info;
        this._iv[] = 0;
        this._iv = rhs._iv.dup;
        this._key[] = 0;
        this._key = rhs._key.dup;
        this._isEncrypted = rhs._isEncrypted;
    }

    ~this()
    {
        dispose(false);
    }

    void dispose(bool disposing = true) @trusted
    {
        disposeSSLResources();
        _iv[] = 0;
        _iv = null;
        _key[] = 0;
        _key = null;
    }

    ResultStatus initialize(bool isEncrypted) @trusted
    in
    {
        assert(!isInitialized);
    }
    do
    {
        this._isEncrypted = isEncrypted;

        const initIVLength = _iv.length > EVP_MAX_IV_LENGTH ? EVP_MAX_IV_LENGTH : _iv.length;
        ubyte[EVP_MAX_IV_LENGTH] initIV = 0;
        if (initIVLength)
            initIV[0..initIVLength] = _iv[0..initIVLength];

        const initMaxKeyLength = _info.keyByteLength > EVP_MAX_KEY_LENGTH ? EVP_MAX_KEY_LENGTH : _info.keyByteLength;
        const initKeyLength = _key.length > initMaxKeyLength ? initMaxKeyLength : _key.length;
        ubyte[EVP_MAX_KEY_LENGTH] initKey = 0;
        initKey[0..initKeyLength] = _key[0..initKeyLength];

        scope (exit)
        {
            initIV[] = 0;
            initKey[] = 0;
        }

        auto apiStatus = opensslApi.status();
        if (apiStatus.isError)
            return apiStatus;

        _ctx = opensslApi.EVP_CIPHER_CTX_new();
        if (_ctx is null)
            return initializeError("EVP_CIPHER_CTX_new");

        if (isEncrypted)
        {
	        if (!opensslApi.EVP_EncryptInit_ex(_ctx, _info.ct(), null, null, null))
		        return initializeError("EVP_EncryptInit_ex");
	        if (!opensslApi.EVP_CIPHER_CTX_set_key_length(_ctx, cast(int)initKeyLength))
		        return initializeError("EVP_CIPHER_CTX_set_key_length");
	        if (!opensslApi.EVP_EncryptInit_ex(_ctx, null, null, &initKey[0], initIVLength ? &initIV[0] : null))
		        return initializeError("EVP_EncryptInit_ex");
        }
        else
        {
	        if (!opensslApi.EVP_DecryptInit_ex(_ctx, _info.ct(), null, null, null))
		        return initializeError("EVP_DecryptInit_ex");
	        if (!opensslApi.EVP_CIPHER_CTX_set_key_length(_ctx, cast(int)initKeyLength))
		        return initializeError("EVP_CIPHER_CTX_set_key_length");
	        if (!opensslApi.EVP_DecryptInit_ex(_ctx, null, null, &initKey[0], initIVLength ? &initIV[0] : null))
		        return initializeError("EVP_DecryptInit_ex");
        }

        return ResultStatus.ok();
    }

    ResultStatus initializeDecrypted()
    {
        return initialize(false);
    }

    ResultStatus initializeEncrypted()
    {
        return initialize(true);
    }

    ResultStatus process(scope const(ubyte)[] input, ref ubyte[] output, out size_t outputLength, const(bool) finalBlock) @trusted
    in
    {
        assert(isInitialized);
        assert(input.length < int.max / 2);
    }
    do
    {
        outputLength = 0;
        if (input.length == 0)
            return ResultStatus.ok();
        const maxOutputLength = isEncrypted
            ? calculateBufferLength(input.length, _info.blockLength, 0)
            : input.length;
        if (output.length < maxOutputLength)
            output.length = maxOutputLength;

        int tempLength;
        if (isEncrypted)
        {
            tempLength = 0;
            if (1 != opensslApi.EVP_EncryptUpdate(_ctx, &output[0], &tempLength, &input[0], cast(int)input.length))
                return currentError("EVP_EncryptUpdate");
            outputLength = tempLength;

            if (finalBlock)
            {
                tempLength = 0;
                if (1 != opensslApi.EVP_EncryptFinal_ex(_ctx, &output[outputLength], &tempLength))
                    return currentError("EVP_EncryptFinal_ex");
                outputLength += tempLength;
            }
        }
        else
        {
            tempLength = 0;
            if (1 != opensslApi.EVP_DecryptUpdate(_ctx, &output[0], &tempLength, &input[0], cast(int)input.length))
                return currentError("EVP_DecryptUpdate");
            outputLength = tempLength;

            if (finalBlock)
            {
                tempLength = 0;
                if (1 != opensslApi.EVP_DecryptFinal_ex(_ctx, &output[outputLength], &tempLength))
                    return currentError("EVP_DecryptFinal_ex");
                outputLength += tempLength;
            }
        }

        return ResultStatus.ok();
    }

    @property uint blockLength() const @trusted
    {
        return _info.blockLength;
    }

    @property EVP_CIPHER_CTX* ctx() @nogc pure
    {
        return _ctx;
    }

    @property const(OpenSSLKeyInfo) info() const @nogc pure
    {
        return _info;
    }

    pragma(inline, true)
    @property bool isEncrypted() const @nogc pure
    {
        return _isEncrypted;
    }

    pragma(inline, true)
    @property bool isInitialized() const @nogc pure
    {
        return _ctx !is null;
    }

    @property const(ubyte)[] iv() const pure
    {
        return _iv;
    }

    @property const(ubyte)[] key() const pure
    {
        return _key;
    }

    @property uint keyBitLength() const @trusted
    {
        return _info.keyBitLength;
    }

private:
    void disposeSSLResources() @trusted
    {
        if (_ctx !is null)
        {
            opensslApi.EVP_CIPHER_CTX_free(_ctx);
            _ctx = null;
        }
    }

    ResultStatus initializeError(string apiName) @trusted
    {
        auto error = currentError(apiName);
        disposeSSLResources();
        return error;
    }

private:
    EVP_CIPHER_CTX* _ctx;
    OpenSSLKeyInfo _info;
    ubyte[] _iv;
    ubyte[] _key;
    bool _isEncrypted;
}

struct OpenSSLExt
{
nothrow @safe:

public:
    static DH* createDH(scope const(ubyte)[] pData, scope const(ubyte)[] qData, scope const(ubyte)[] gData) @trusted
    {
        auto apiStatus = opensslApi.status();
        if (apiStatus.isError)
            return null;

        DH* result = opensslApi.DH_new();
        if (result is null)
            return null;

        BIGNUM* p = opensslApi.BN_bin2bn(&pData[0], cast(int)pData.length, null);
        BIGNUM* g = opensslApi.BN_bin2bn(&gData[0], cast(int)gData.length, null);
        BIGNUM* q = qData.length != 0 ? opensslApi.BN_bin2bn(&qData[0], cast(int)qData.length, null) : null;

        if (p is null
            || g is null
            || 1 != opensslApi.DH_set0_pqg(result, p, q, g))
        {
            if (p !is null)
                opensslApi.BN_free(p);
            if (q !is null)
                opensslApi.BN_free(q);
            if (g !is null)
                opensslApi.BN_free(g);
            opensslApi.DH_free(result);
            return null;
        }

        return result;
    }

    // keyBitLength=128, 256, 512, 1_024, 2_048, 4_096
    static ResultStatus generateKeyPair(ref char[] pemPrivateKey, ref char[] pemPublicKey, int keyBitLength) @trusted
    {
        auto apiStatus = opensslApi.status();
        if (apiStatus.isError)
            return apiStatus;

        BIGNUM* bn = null;
        RSA* rsa = null;
        BIO* bio = null;
        scope (exit)
        {
            if (bio !is null)
                opensslApi.BIO_free(bio);
            if (rsa !is null)
                opensslApi.RSA_free(rsa);
            if (bn !is null)
                opensslApi.BN_free(bn);
        }

	    bn = opensslApi.BN_new();
        if (bn is null)
            return currentError("BN_new");
        if (1 != opensslApi.BN_set_word(bn, cast(c_ulong)bn | 1))
            return currentError("BN_set_word");

        rsa = opensslApi.RSA_new();
        if (rsa is null)
            return currentError("RSA_new");

	    if (1 != opensslApi.RSA_generate_key_ex(rsa, keyBitLength, bn, null))
            return currentError("RSA_generate_key_ex");

        bio = opensslApi.BIO_new(opensslApi.BIO_s_mem());
        if (bio is null)
            return currentError("BIO_new");

        //opensslApi.BIO_reset(bio); // Just created, no need to reset
        if (1 != opensslApi.PEM_write_bio_RSAPrivateKey(bio, rsa, null, null, 0, null, null))
            return currentError("PEM_write_bio_RSAPrivateKey");
        ResultStatus rs = readAll(bio, pemPrivateKey);
        if (rs.isError)
            return rs;

        opensslApi.BIO_reset(bio);
        if (1 != opensslApi.PEM_write_bio_RSA_PUBKEY(bio, rsa))
            return currentError("PEM_write_bio_RSA_PUBKEY");
        rs = readAll(bio, pemPublicKey);
        if (rs.isError)
            return rs;

        return ResultStatus.ok();
    }

    static ResultStatus generatePrimNumber(uint bitLength, const(ubyte)[] randomSeed,
        ref char[] hexPrim,
        const(char)[] hexAdd = null,
        bool safe = false) @trusted
    {
        auto apiStatus = opensslApi.status();
        if (apiStatus.isError)
            return apiStatus;

        if (randomSeed.length)
            opensslApi.RAND_seed(&randomSeed[0], cast(int)randomSeed.length);

        BIGNUM* bn = null;
        BIGNUM* bnAdd = null;
        char* bnHex = null;
        scope (exit)
        {
            if (bnHex !is null)
                opensslApi.OPENSSL_free(bnHex);

            if (bnAdd !is null)
                opensslApi.BN_free(bnAdd);

            if (bn !is null)
                opensslApi.BN_free(bn);
        }

        if (hexAdd.length)
        {
            auto hexAddz = toStringz(hexAdd);
            if (0 == opensslApi.BN_hex2bn(&bnAdd, hexAddz))
                return currentError("BN_hex2bn");
        }

	    bn = opensslApi.BN_new();
        if (bn is null)
            return currentError("BN_new");

        if (1 != opensslApi.BN_generate_prime_ex(bn, cast(int)bitLength, safe ? 1 : 0, bnAdd, null, null))
            return currentError("BN_generate_prime_ex");

        bnHex = opensslApi.BN_bn2hex(bn);
        if (bnHex is null)
            return currentError("BN_bn2hex");

        //char* bnDec = opensslApi.BN_bn2dec(bn);
        //auto decPrim = fromStringz(bnDec);
        //opensslApi.OPENSSL_free(bnDec);
        //import pham.utl.test; dgWriteln("dec ", decPrim.length, ": ", decPrim);

        hexPrim = fromStringz(bnHex);
        //import pham.utl.test; dgWriteln("hex ", hexPrim.length, ": ", hexPrim);

        return ResultStatus.ok();
    }

    static int getSize(BIO* bio) @nogc @trusted
    {
        return opensslApi.BIO_pending(bio);
    }

    static bool isEof(BIO* bio) @nogc @trusted
    {
        return opensslApi.BIO_eof(bio) == 1;
    }

    static ResultStatus readAll(BIO* bio, ref ubyte[] data) @trusted
    {
        const bioSize = getSize(bio);
        opensslApi.BIO_seek(bio, 0);

        if (data.length == 0 || data.length < bioSize)
            data.length = bioSize;

        const r = opensslApi.BIO_read(bio, &data[0], bioSize);
        if (r < 0 || r != bioSize)
            return currentError("BIO_read");

        return ResultStatus.ok();
    }

    static ResultStatus readAll(BIO* bio, ref char[] data) @trusted
    {
        const bioSize = getSize(bio);
        opensslApi.BIO_seek(bio, 0);

        if (data.length == 0 || data.length < bioSize)
            data.length = bioSize;

        const r = opensslApi.BIO_read(bio, &data[0], bioSize);
        if (r < 0 || r != bioSize)
            return currentError("BIO_read");

        return ResultStatus.ok();
    }
}

struct OpenSSLRSAPem
{
nothrow @safe:

public:
    @disable this(this);
    @disable void opAssign(typeof(this));

    this(scope const(char)[] pemData, scope const(char)[] pemFile, bool isPublic) pure
    {
        this._pemData = pemData.dup;
        this._pemFile = pemFile.dup;
        this._isPublic = isPublic;
    }

    this(ref typeof(this) rhs) pure
    {
        this._pemData[] = 0;
        this._pemData = rhs._pemData.dup;
        this._pemFile[] = 0;
        this._pemFile = rhs._pemFile.dup;
        this._isPublic = rhs._isPublic;
    }

    ~this() pure
    {
        dispose(false);
    }

    void dispose(bool disposing = true) pure
    {
        _pemData[] = 0;
        _pemData = null;
        _pemFile[] = 0;
        _pemFile = null;
    }

    pragma(inline, true)
    bool isValid() const @nogc pure
    {
        return _pemData.length != 0 || _pemFile.length != 0;
    }

    static OpenSSLRSAPem privateKey(scope const(char)[] pemData, scope const(char)[] pemFile) pure
    {
        return OpenSSLRSAPem(pemData, pemFile, false);
    }

    static OpenSSLRSAPem publicKey(scope const(char)[] pemData, scope const(char)[] pemFile) pure
    {
        return OpenSSLRSAPem(pemData, pemFile, true);
    }

    pragma(inline, true)
    bool useData() const @nogc pure
    {
        return _pemData.length != 0;
    }

    @property const(char)[] pemData() const @nogc pure
    {
        return _pemData;
    }

    @property const(char)[] pemFile() const @nogc pure
    {
        return _pemFile;
    }

    pragma(inline, true)
    @property bool isPublic() const @nogc pure
    {
        return _isPublic;
    }

private:
    char[] _pemData;
    char[] _pemFile;
    bool _isPublic;
}

struct OpenSSLRSACrypt
{
nothrow @safe:

public:
    @disable this(this);
    @disable void opAssign(typeof(this));

    this(OpenSSLRSAPem pem) pure
    {
        this._pem = pem;
    }

    this(ref typeof(this) rhs)
    {
        this.disposeSSLResources();
        this.paddingMode = rhs.paddingMode;
        this._rsa = rhs._rsa;
        rhs._rsa = null;
        this._pem = rhs._pem;
    }

    ~this()
    {
        dispose(false);
    }

    void dispose(bool disposing = true) @trusted
    {
        disposeSSLResources();
        _pem.dispose(disposing);
    }

    ResultStatus decrypt(scope const(ubyte)[] input, ref ubyte[] output, out size_t outputLength) @trusted
    in
    {
        assert(isInitialized);
        assert(input.length < int.max / 2);
    }
    do
    {
        outputLength = 0;
        if (input.length == 0)
            return ResultStatus.ok();
        if (output.length < input.length)
            output.length = input.length;

        const tempLength = _pem.isPublic
            ? opensslApi.RSA_public_decrypt(cast(int)input.length, &input[0], &output[0], _rsa, paddingMode)
            : opensslApi.RSA_private_decrypt(cast(int)input.length, &input[0], &output[0], _rsa, paddingMode);

        if (tempLength < 0)
            return _pem.isPublic ? currentError("RSA_public_decrypt") : currentError("RSA_private_decrypt");

        outputLength = tempLength;
        return ResultStatus.ok();
    }

    ResultStatus encrypt(scope const(ubyte)[] input, ref ubyte[] output, out size_t outputLength) @trusted
    in
    {
        assert(isInitialized);
        assert(input.length < int.max / 2);
    }
    do
    {
        outputLength = 0;
        if (input.length == 0)
            return ResultStatus.ok();
        const maxOutputLength = calculateBufferLength(input.length, blockLength, paddingSize);
        if (output.length < maxOutputLength)
            output.length = maxOutputLength;

        const tempLength = _pem.isPublic
            ? opensslApi.RSA_public_encrypt(cast(int)input.length, &input[0], &output[0], _rsa, paddingMode)
            : opensslApi.RSA_private_encrypt(cast(int)input.length, &input[0], &output[0], _rsa, paddingMode);

        if (tempLength < 0)
            return _pem.isPublic ? currentError("RSA_public_encrypt") : currentError("RSA_private_encrypt");

        outputLength = tempLength;
        return ResultStatus.ok();
    }

    ResultStatus initialize() @trusted
    in
    {
        assert(!isInitialized);
    }
    do
    {
        auto apiStatus = opensslApi.status();
        if (apiStatus.isError)
            return apiStatus;

        BIO* keyBio;
        if (_pem.useData)
        {
            keyBio = opensslApi.BIO_new_mem_buf(&_pem.pemData[0], cast(int)_pem.pemData.length);
            if (keyBio is null)
                return initializeError("BIO_new_mem_buf");
        }
        else
        {
            auto pemFilez = toStringz(_pem.pemFile);
            keyBio = opensslApi.BIO_new_file(pemFilez, "r".ptr);
            if (keyBio is null)
                return initializeError("BIO_new_file");
        }
        scope (exit)
            opensslApi.BIO_free(keyBio);

        if (_pem.isPublic)
        {
            _rsa = opensslApi.PEM_read_bio_RSA_PUBKEY(keyBio, null, null, null);
            if (_rsa is null)
                return initializeError("PEM_read_bio_RSA_PUBKEY");
        }
        else
        {
            _rsa = opensslApi.PEM_read_bio_RSAPrivateKey(keyBio, null, null, null);
            if (_rsa is null)
                return initializeError("PEM_read_bio_RSAPrivateKey");
        }

        return ResultStatus.ok();
    }

    @property uint blockLength() const @trusted
    in
    {
        assert(isInitialized);
    }
    do
    {
        return opensslApi.RSA_size(_rsa);
    }

    pragma(inline, true)
    @property bool isInitialized() const @nogc pure
    {
        return _rsa !is null;
    }

    @property uint keyBitLength() const @trusted
    in
    {
        assert(isInitialized);
    }
    do
    {
        return opensslApi.RSA_security_bits(_rsa);
    }

    @property uint paddingSize() const @trusted
    {
        switch (paddingMode)
        {
            case RSA_PKCS1_PADDING:
                return RSA_PKCS1_PADDING_SIZE;
            case RSA_NO_PADDING:
                return 0;
            case RSA_PKCS1_OAEP_PADDING:
                return RSA_PKCS1_OAEP_PADDING_SIZE;
            default:
                return RSA_MAX_PADDING_SIZE;
        }
    }

    @property ref const(OpenSSLRSAPem) pem() const pure return
    {
        return _pem;
    }

public:
    int paddingMode = RSA_PKCS1_OAEP_PADDING;

private:
    void disposeSSLResources() @trusted
    {
        if (_rsa !is null)
        {
            opensslApi.RSA_free(_rsa);
            _rsa = null;
        }
    }

    ResultStatus initializeError(string apiName) @trusted
    {
        auto error = currentError(apiName);
        disposeSSLResources();
        return error;
    }

private:
    RSA* _rsa;
    OpenSSLRSAPem _pem;
}

version (none)
ubyte[] toTerminatedzIf(scope const(ubyte)[] s, const(size_t) maxLengh) nothrow pure
{
    const len = maxLengh && s.length > maxLengh ? maxLengh : s.length;
    if (len)
    {
        auto result = new ubyte[len + 1];
        result[0..len] = s[0..len];
        result[len] = 0;
        return result;
    }
    else
        return null;
}

static immutable OpenSSLKeyInfo[string] mappedKeyInfos;


// Any below codes are private
private:

shared static this()
{
    if (opensslApi.status().isOK)
    {
        mappedKeyInfos["bf_cbc"] = OpenSSLKeyInfo.bf_cbc();
        mappedKeyInfos["bf-cbc"] = OpenSSLKeyInfo.bf_cbc();
        mappedKeyInfos["bf_cfb"] = OpenSSLKeyInfo.bf_cfb();
        mappedKeyInfos["bf-cfb"] = OpenSSLKeyInfo.bf_cfb();
        mappedKeyInfos["bf_ecb"] = OpenSSLKeyInfo.bf_ecb();
        mappedKeyInfos["bf-ecb"] = OpenSSLKeyInfo.bf_ecb();
        mappedKeyInfos["bf_ofb"] = OpenSSLKeyInfo.bf_ofb();
        mappedKeyInfos["bf-ofb"] = OpenSSLKeyInfo.bf_ofb();

        mappedKeyInfos["cast5_cbc"] = OpenSSLKeyInfo.cast5_cbc();
        mappedKeyInfos["cast5-cbc"] = OpenSSLKeyInfo.cast5_cbc();
        mappedKeyInfos["cast5_cfb"] = OpenSSLKeyInfo.cast5_cfb();
        mappedKeyInfos["cast5-cfb"] = OpenSSLKeyInfo.cast5_cfb();
        mappedKeyInfos["cast5_ecb"] = OpenSSLKeyInfo.cast5_ecb();
        mappedKeyInfos["cast5-ecb"] = OpenSSLKeyInfo.cast5_ecb();
        mappedKeyInfos["cast5_ofb"] = OpenSSLKeyInfo.cast5_ofb();
        mappedKeyInfos["cast5-ofb"] = OpenSSLKeyInfo.cast5_ofb();

        mappedKeyInfos["des_cbc"] = OpenSSLKeyInfo.des_cbc();
        mappedKeyInfos["des-cbc"] = OpenSSLKeyInfo.des_cbc();
        mappedKeyInfos["des_cfb"] = OpenSSLKeyInfo.des_cfb();
        mappedKeyInfos["des-cfb"] = OpenSSLKeyInfo.des_cfb();
        mappedKeyInfos["des_ecb"] = OpenSSLKeyInfo.des_ecb();
        mappedKeyInfos["des-ecb"] = OpenSSLKeyInfo.des_ecb();
        mappedKeyInfos["des_ofb"] = OpenSSLKeyInfo.des_ofb();
        mappedKeyInfos["des-ofb"] = OpenSSLKeyInfo.des_ofb();

        mappedKeyInfos["des_ede3_cbc"] = OpenSSLKeyInfo.des_ede3_cbc();
        mappedKeyInfos["des-ede3-cbc"] = OpenSSLKeyInfo.des_ede3_cbc();
        mappedKeyInfos["des_ede3_cfb"] = OpenSSLKeyInfo.des_ede3_cfb();
        mappedKeyInfos["des-ede3-cfb"] = OpenSSLKeyInfo.des_ede3_cfb();
        mappedKeyInfos["des_ede3_ecb"] = OpenSSLKeyInfo.des_ede3_ecb();
        mappedKeyInfos["des-ede3-ecb"] = OpenSSLKeyInfo.des_ede3_ecb();
        mappedKeyInfos["des_ede3_ofb"] = OpenSSLKeyInfo.des_ede3_ofb();
        mappedKeyInfos["des-ede3-ofb"] = OpenSSLKeyInfo.des_ede3_ofb();

        mappedKeyInfos["aes_cbc_128"] = OpenSSLKeyInfo.aes_cbc(128 / 8);
        mappedKeyInfos["aes-cbc-128"] = OpenSSLKeyInfo.aes_cbc(128 / 8);
        mappedKeyInfos["aes_cbc_192"] = OpenSSLKeyInfo.aes_cbc(192 / 8);
        mappedKeyInfos["aes-cbc-192"] = OpenSSLKeyInfo.aes_cbc(192 / 8);
        mappedKeyInfos["aes_cbc_256"] = OpenSSLKeyInfo.aes_cbc(256 / 8);
        mappedKeyInfos["aes-cbc-256"] = OpenSSLKeyInfo.aes_cbc(256 / 8);

        mappedKeyInfos["aes_cfb_128"] = OpenSSLKeyInfo.aes_cfb(128 / 8);
        mappedKeyInfos["aes-cfb-128"] = OpenSSLKeyInfo.aes_cfb(128 / 8);
        mappedKeyInfos["aes_cfb_192"] = OpenSSLKeyInfo.aes_cfb(192 / 8);
        mappedKeyInfos["aes-cfb-192"] = OpenSSLKeyInfo.aes_cfb(192 / 8);
        mappedKeyInfos["aes_cfb_256"] = OpenSSLKeyInfo.aes_cfb(256 / 8);
        mappedKeyInfos["aes-cfb-256"] = OpenSSLKeyInfo.aes_cfb(256 / 8);

        mappedKeyInfos["aes_ecb_128"] = OpenSSLKeyInfo.aes_ecb(128 / 8);
        mappedKeyInfos["aes-ecb-128"] = OpenSSLKeyInfo.aes_ecb(128 / 8);
        mappedKeyInfos["aes_ecb_192"] = OpenSSLKeyInfo.aes_ecb(192 / 8);
        mappedKeyInfos["aes-ecb-192"] = OpenSSLKeyInfo.aes_ecb(192 / 8);
        mappedKeyInfos["aes_ecb_256"] = OpenSSLKeyInfo.aes_ecb(256 / 8);
        mappedKeyInfos["aes-ecb-256"] = OpenSSLKeyInfo.aes_ecb(256 / 8);

        mappedKeyInfos["aes_ofb_128"] = OpenSSLKeyInfo.aes_ofb(128 / 8);
        mappedKeyInfos["aes-ofb-128"] = OpenSSLKeyInfo.aes_ofb(128 / 8);
        mappedKeyInfos["aes_ofb_192"] = OpenSSLKeyInfo.aes_ofb(192 / 8);
        mappedKeyInfos["aes-ofb-192"] = OpenSSLKeyInfo.aes_ofb(192 / 8);
        mappedKeyInfos["aes_ofb_256"] = OpenSSLKeyInfo.aes_ofb(256 / 8);
        mappedKeyInfos["aes-ofb-256"] = OpenSSLKeyInfo.aes_ofb(256 / 8);
    }
}

ResultStatus currentError(string apiName) nothrow @trusted
{
    return currentError(apiName, opensslApi.ERR_get_error());
}

ResultStatus currentError(string apiName, int code) nothrow @trusted
{
    const msg = fromStringz(opensslApi.ERR_reason_error_string(code));
    return ResultStatus.error(cast(int)code, msg.length != 0 ? msg.idup : apiName);
}

ResultStatus currentSSLError(SSL* ssl, int r, string apiName) nothrow @trusted
{
    const code = opensslApi.SSL_get_error(ssl, r);
    const msg = fromStringz(opensslApi.ERR_reason_error_string(code));
    return ResultStatus.error(code, msg.length != 0 ? msg.idup : apiName);
}

version (unittest)
{
    bool isOpenSSLIntalled() @nogc nothrow @safe
    {
        import std.file : exists;
        import pham.cp.openssl_binding : libCryptoNames, libSslNames;

        bool lib1;
        foreach (lib; libSslNames)
        {
            if (exists(lib))
            {
                lib1 = true;
                break;
            }
        }

        bool lib2;
        foreach (lib; libCryptoNames)
        {
            if (exists(lib))
            {
                lib2 = true;
                break;
            }
        }

        return lib1 && lib2;
    }
}

unittest // OpenSSLExt.generateKeyPair
{
    import std.file : write;
    import pham.utl.test;
    traceUnitTest!("pham.cp")("unittest pham.cp.openssl.OpenSSLExt.generateKeyPair");

    if (isOpenSSLIntalled())
    {
        char[] pemPrivateKey, pemPublicKey;
        auto status = OpenSSLExt.generateKeyPair(pemPrivateKey, pemPublicKey, 1_024);
        assert(status.isOK, status.toString());
        assert(pemPrivateKey.length != 0);
        assert(pemPublicKey.length != 0);
        //write("pemPrivateKey.pem", pemPrivateKey);
        //write("pemPublicKey.pem", pemPublicKey);
    }
}

unittest // OpenSSLCrypt
{
    import std.string : representation;
    import pham.utl.test;
    traceUnitTest!("pham.cp")("unittest pham.cp.openssl.OpenSSLCrypt");

    if (isOpenSSLIntalled())
    {
        ubyte[] key = [0x01, 0x23, 0x45, 0x67, 0x89, 0xab, 0xcd, 0xef, 0x01, 0x23, 0x45, 0x67, 0x89, 0xab, 0xcd, 0xef];
        ubyte[] iv = [0x01, 0x23, 0x45, 0x67, 0x89, 0xab, 0xcd, 0xef];
        auto text = "This is an openssl TEST".representation;
        ubyte[] output1 = new ubyte[500], output2 = new ubyte[500];
        size_t output1Length, output2Length;
        ResultStatus status;

        auto keyInfo1 = OpenSSLKeyInfo.aes_cbc(128);
        auto crypt1e = OpenSSLCrypt(keyInfo1, key, iv);
        status = crypt1e.initialize(true);
        assert(status.isOK, status.toString());
        status = crypt1e.process(text, output1, output1Length, true);
        assert(status.isOK, status.toString());
        auto crypt1d = OpenSSLCrypt(keyInfo1, key, iv);
        status = crypt1d.initialize(false);
        assert(status.isOK, status.toString());
        status = crypt1d.process(output1[0..output1Length], output2, output2Length, true);
        assert(status.isOK, status.toString());
        assert(text == output2[0..output2Length]);

        auto keyInfo2 = mappedKeyInfos["aes-ofb-128"];
        auto crypt2e = OpenSSLCrypt(keyInfo2, key, null);
        status = crypt2e.initialize(true);
        assert(status.isOK, status.toString());
        status = crypt2e.process(text, output1, output1Length, true);
        assert(status.isOK, status.toString());
        auto crypt2d = OpenSSLCrypt(keyInfo2, key, null);
        status = crypt2d.initialize(false);
        assert(status.isOK, status.toString());
        status = crypt2d.process(output1[0..output1Length], output2, output2Length, true);
        assert(status.isOK, status.toString());
        assert(text == output2[0..output2Length]);
    }
}

unittest // OpenSSLRSACrypt
{
    import std.string : representation;
    import pham.utl.test;
    traceUnitTest!("pham.cp")("unittest pham.cp.openssl.OpenSSLRSACrypt");

    if (isOpenSSLIntalled())
    {
        static immutable string plainText = "Thou shalt never continue after asserting null";
        ResultStatus status;

        // Generate key for testing
        char[] pemPrivateKey, pemPublicKey;
        {
            status = OpenSSLExt.generateKeyPair(pemPrivateKey, pemPublicKey, 1_024);
            assert(status.isOK, status.toString());
            assert(pemPrivateKey.length != 0);
            assert(pemPublicKey.length != 0);
        }

        auto publicKey = OpenSSLRSAPem.publicKey(pemPublicKey, null);
        OpenSSLRSACrypt publicRSA = OpenSSLRSACrypt(publicKey);
        status = publicRSA.initialize();
        assert(status.isOK, status.toString());

        ubyte[] cryptedData;
        size_t cryptedLength;
        status = publicRSA.encrypt(plainText.representation(), cryptedData, cryptedLength);
        assert(status.isOK, status.toString());
        assert(cryptedLength > 0);

        auto privateKey = OpenSSLRSAPem.privateKey(pemPrivateKey, null);
        OpenSSLRSACrypt privateRSA = OpenSSLRSACrypt(privateKey);
        status = privateRSA.initialize();
        assert(status.isOK, status.toString());

        ubyte[] uncryptedData;
        size_t uncryptedLength;
        status = privateRSA.decrypt(cryptedData[0..cryptedLength], uncryptedData, uncryptedLength);
        assert(status.isOK, status.toString());
        assert(uncryptedLength > 0);
        assert(uncryptedData[0..uncryptedLength] == plainText.representation());

        // Test empty
        status = publicRSA.encrypt(null, cryptedData, cryptedLength);
        assert(status.isOK, status.toString());
        assert(cryptedLength == 0);
        status = privateRSA.decrypt(cryptedData[0..cryptedLength], uncryptedData, uncryptedLength);
        assert(status.isOK, status.toString());
        assert(uncryptedLength == 0);
    }
}

unittest // OpenSSLExt.generatePrimNumber
{
    import std.string : representation;
    import pham.utl.test;
    traceUnitTest!("pham.cp")("unittest pham.cp.openssl.OpenSSLExt.generatePrimNumber");

    if (isOpenSSLIntalled())
    {
        char[] hexPrim;
        auto status = OpenSSLExt.generatePrimNumber(2048, "generatePrimNumber".representation(), hexPrim);
        assert(status.isOK, status.toString());
        assert(hexPrim.length == 2048 / 4);
    }
}
