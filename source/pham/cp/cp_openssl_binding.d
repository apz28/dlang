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

module pham.cp.openssl_binding;

public import core.stdc.config : c_long, c_ulong;

import pham.utl.object : ResultStatus, VersionString;

nothrow:

version (Windows)
{
    import core.sys.windows.windows : FreeLibrary, GetProcAddress, LoadLibrary;

    alias LibName = wstring;
    alias loadFct = GetProcAddress;
    alias unloadLibFct = FreeLibrary;
}
else
{
    import core.sys.posix.dlfcn : dlclose, dlopen, dlsym;

    alias LibName = string;
    alias loadFct = dlsym;
    alias unloadLibFct = dlclose;
}

version (Windows)
{
    private enum loadLib = "LoadLibrary(lib.ptr)";

    static immutable LibName[] libSslNames = libSslNamesImpl();
    private LibName[] libSslNamesImpl() pure @safe
    {
        static if (size_t.sizeof == 8)
            return ["libssl-3-x64.dll"w, "libssl-1_1-x64.dll"w];
        else
            return ["libssl-3.dll"w, "libssl-1_1.dll"w];
    }

    static immutable LibName[] libCryptoNames = libCryptoNamesImpl();
    private LibName[] libCryptoNamesImpl() pure @safe
    {
        static if (size_t.sizeof == 8)
            return ["libcrypto-3-x64.dll"w, "libcrypto-1_1-x64.dll"w];
        else
            return ["libcrypto-3.dll"w, "libcrypto-1_1.dll"w];
    }
}
else version (OSX)
{
    private enum loadLib = "dlopen(lib.ptr, RTLD_LAZY)";

    static immutable LibName[] libSslNames = [
        "libssl.46.dylib", "libssl.44.dylib", "libssl.43.dylib",
        "libssl.35.dylib"];

    static immutable LibName[] libCryptoNames = [
        "libcrypto.44.dylib", "libcrypto.42.dylib", "libcrypto.41.dylib",
        "libcrypto.35.dylib"];
}
else version (Posix)
{
    private enum loadLib = "dlopen(lib.ptr, RTLD_LAZY)";

    static immutable LibName[] libSslNames = ["libssl.so.3.0", "libssl.so.1.1"];

    static immutable LibName[] libCryptoNames = ["libcrypto.so.3.0", "libcrypto.so.1.1"];
}
else
    static assert(0, "Unsupported system");

/*
 * tls1.h
 */
//enum int TLS1_VERSION = 0x0301;
//enum int TLS1_1_VERSION = 0x0302;
enum int TLS1_2_VERSION = 0x0303;
enum int TLS_ANY_VERSION = 0x1_0000;

/*
 * ssl.h
 */
enum int SSL_CTRL_SET_MIN_PROTO_VERSION = 123;
enum int SSL_CTRL_SET_MAX_PROTO_VERSION = 124;

enum SSL_OP_NO_SSLv2 = 0x01000000U; // removed from v1.1.0
enum SSL_OP_NO_SSLv3 = 0x02000000U;
enum SSL_OP_NO_TLSv1 = 0x04000000U;
enum SSL_OP_NO_TLSv1_1 = 0x10000000U;
enum SSL_OP_NO_COMPRESSION = 0x00020000U;

enum int SSL_VERIFY_NONE = 0x00;
enum int SSL_VERIFY_PEER = 0x01;
enum int SSL_VERIFY_FAIL_IF_NO_PEER_CERT = 0x02;
enum int SSL_VERIFY_CLIENT_ONCE = 0x04;
alias SSL_FILETYPE_PEM = X509_FILETYPE_PEM;
alias SSL_FILETYPE_ASN1 = X509_FILETYPE_ASN1;

enum int X509_FILETYPE_PEM = 1;
enum int X509_FILETYPE_ASN1 = 2;
enum int X509_FILETYPE_DEFAULT = 3;

enum X509_V_OK = 0;

/* rsa.h */
enum RSA_PKCS1_PADDING = 1; /// PKCS #1 v1.5 padding. This currently is the most widely used mode
enum RSA_PKCS1_PADDING_SIZE = 11;
//enum RSA_SSLV23_PADDING = 2;
enum RSA_NO_PADDING = 3;
enum RSA_PKCS1_OAEP_PADDING = 4; /// EME-OAEP as defined in PKCS #1 v2.0 with SHA-1, MGF1 and an empty encoding parameter. This mode is recommended for all new applications.
enum RSA_PKCS1_OAEP_PADDING_SIZE = 42;
enum RSA_X931_PADDING = 5;
enum RSA_PKCS1_PSS_PADDING = 6; /// EVP_PKEY_ only
enum RSA_MAX_PADDING_SIZE = RSA_PKCS1_OAEP_PADDING_SIZE;

enum int SSL_ERROR_NONE = 0;
enum int SSL_ERROR_SSL = 1;
enum int SSL_ERROR_WANT_READ = 2;
enum int SSL_ERROR_WANT_WRITE = 3;
enum int SSL_ERROR_SYSCALL = 5;

/**
 * ssl.h
 * Standard initialization options
 */
enum OPENSSL_INIT_LOAD_SSL_STRINGS = 0x0020_0000L;
//enum OPENSSL_INIT_LOAD_CRYPTO_STRINGS = 0x0000_0002L;

/**
 * crypto.h
 * Standard initialization options
 */
enum OPENSSL_INIT_LOAD_CRYPTO_STRINGS = 0x0000_0002L;
enum OPENSSL_INIT_ADD_ALL_CIPHERS = 0x0000_0004L;
enum OPENSSL_INIT_ADD_ALL_DIGESTS = 0x0000_0008L;
enum OPENSSL_INIT_ENGINE_OPENSSL = 0x0000_0800L;

enum loadCryptDefault = OPENSSL_INIT_ADD_ALL_CIPHERS | OPENSSL_INIT_ADD_ALL_DIGESTS | OPENSSL_INIT_LOAD_CRYPTO_STRINGS | OPENSSL_INIT_ENGINE_OPENSSL;
enum loadSslDefault = OPENSSL_INIT_LOAD_SSL_STRINGS | OPENSSL_INIT_LOAD_CRYPTO_STRINGS;

/**
 * evp.h
 */
enum EVP_MAX_BLOCK_LENGTH = 32;
enum EVP_MAX_IV_LENGTH = 16;   // 128 / 8
enum EVP_MAX_KEY_BIT_LENGTH = 512;  // 512
enum EVP_MAX_KEY_LENGTH = EVP_MAX_KEY_BIT_LENGTH / 8;

/*
 * types.h
 */
struct EVP_CIPHER {}
struct EVP_CIPHER_CTX {}
struct EVP_PKEY {}

/*
 * ssl.h
 */
struct BIGNUM {}
struct BIO {}
struct BIO_METHOD {}
struct BN_GENCB {}
struct CRYPTO_EX_DATA{}
struct DH{}
struct OPENSSL_INIT_SETTINGS {}
struct RSA {}
struct SSL {}
struct SSL_CIPHER {}
struct SSL_CTX {}
struct SSL_METHOD {}
struct X509 {}
struct X509_STORE_CTX {}
struct X509_VERIFY_PARAM {}

alias OpenSSLCipherType = EVP_CIPHER* delegate() const nothrow;
alias OpenSSLPemPasswordCallback = int function(char* buffer, int size, int rwFlag, void* cbu) nothrow;
alias OpenSSLVerifyCallback = int function(int preverify_ok, X509_STORE_CTX* sctx) nothrow;

alias CRYPTOExDup = int function(CRYPTO_EX_DATA* to, CRYPTO_EX_DATA* from, void* from_d, int idx, c_long argl, void* argp) nothrow;
alias CRYPTOExFree = void function(void* parent, void* ptr, CRYPTO_EX_DATA* ad, int idx, c_long argl, void* argp) nothrow;
alias CRYPTOExNew = int function(void* parent, void* ptr, CRYPTO_EX_DATA* ad, int idx, c_long argl, void* argp) nothrow;

struct OpenSSLApi
{
nothrow:

public:
    c_long BIO_ctrl(BIO* bio, int cmd, c_long larg, void* parg) const @nogc
    {
        return adapter_BIO_ctrl(bio, cmd, larg, parg);
    }

    int BIO_eof(BIO* bio) const @nogc
    {
        return cast(int)BIO_ctrl(bio, 2, 0, null); // BIO_CTRL_EOF=2
    }

    int BIO_free(BIO* bio) const @nogc
    {
        return adapter_BIO_free(bio);
    }

    BIO* BIO_new(BIO_METHOD* method) const
    {
        return adapter_BIO_new(method);
    }

    BIO* BIO_new_file(const(char)* filename, const(char)* mode) const
    {
        return adapter_BIO_new_file(filename, mode);
    }

    // If len is -1 then the buf is assumed to be null terminated
    BIO* BIO_new_mem_buf(const(void)* buf, int len) const
    {
        return adapter_BIO_new_mem_buf(buf, len);
    }

    int BIO_pending(BIO* bio) const @nogc
    {
        return cast(int)BIO_ctrl(bio, 10, 0, null); // BIO_CTRL_PENDING=10
    }

    int BIO_read(BIO* bio, void* buf, int len) const @nogc
    {
        return adapter_BIO_read(bio, buf, len);
    }

    int BIO_reset(BIO* bio) const
    {
        return cast(int)BIO_ctrl(bio, 1, 0, null); // BIO_CTRL_RESET=1
    }

    BIO_METHOD* BIO_s_mem() const
    {
        return adapter_BIO_s_mem();
    }

    int BIO_seek(BIO* bio, int offset) const @nogc
    {
        return cast(int)BIO_ctrl(bio, 128, offset, null); // BIO_C_FILE_SEEK=128
    }

    int BIO_tell(BIO* bio) const @nogc
    {
        return cast(int)BIO_ctrl(bio, 133, 0, null); // BIO_C_FILE_TELL=133
    }

    int BIO_write(BIO* bio, const(void)* buf, int len) const @nogc
    {
        return adapter_BIO_write(bio, buf, len);
    }

    BIGNUM* BN_bin2bn(const(ubyte)* s, int len, BIGNUM* ret) const
    {
        return adapter_BN_bin2bn(s, len, ret);
    }

    void BN_free(BIGNUM* n) const @nogc
    {
        adapter_BN_free(n);
    }

    char* BN_bn2dec(BIGNUM* n) const
    {
        return adapter_BN_bn2dec(n);
    }

    char* BN_bn2hex(BIGNUM* n) const
    {
        return adapter_BN_bn2hex(n);
    }

    int BN_generate_prime_ex(BIGNUM* ret, int bits, int safe, BIGNUM* add, BIGNUM* rem,
        BN_GENCB* cb) const
    {
        return adapter_BN_generate_prime_ex(ret, bits, safe, add, rem, cb);
    }

    int BN_hex2bn(BIGNUM** n, const(char)* hex) const
    {
        return adapter_BN_hex2bn(n, hex);
    }

    BIGNUM* BN_new() const
    {
        return adapter_BN_new();
    }

    int BN_set_word(BIGNUM* n, c_ulong w) const @nogc
    {
        return adapter_BN_set_word(n, w);
    }

    void CONF_modules_unload() const
    {
        return adapter_CONF_modules_unload();
    }

    void CRYPTO_free(void* p, char* file = null, int line = 0) const
    {
        adapter_CRYPTO_free(p, file, line);
    }

    int CRYPTO_get_ex_new_index(int classIdx, c_long argl, void* argp, CRYPTOExNew newFunc, CRYPTOExDup dupFunc, CRYPTOExFree freeFunc) const
    {
        return adapter_CRYPTO_get_ex_new_index(classIdx, argl, argp, newFunc, dupFunc, freeFunc);
    }

    void DH_free(DH* dh) const
    {
        adapter_DH_free(dh);
    }

    DH* DH_new() const
    {
        return adapter_DH_new();
    }

    int DH_set0_pqg(DH* dh, BIGNUM* p, BIGNUM* q, BIGNUM* g) const
    {
        return adapter_DH_set0_pqg(dh, p, q, g);
    }

    EVP_CIPHER* EVP_bf_cbc() const
    {
        return adapter_EVP_bf_cbc();
    }

    EVP_CIPHER* EVP_bf_cfb() const
    {
        return adapter_EVP_bf_cfb();
    }

    EVP_CIPHER* EVP_bf_ecb() const
    {
        return adapter_EVP_bf_ecb();
    }

    EVP_CIPHER* EVP_bf_ofb() const
    {
        return adapter_EVP_bf_ofb();
    }

    EVP_CIPHER* EVP_cast5_cbc() const
    {
        return adapter_EVP_cast5_cbc();
    }

    EVP_CIPHER* EVP_cast5_cfb() const
    {
        return adapter_EVP_cast5_cfb();
    }

    EVP_CIPHER* EVP_cast5_ecb() const
    {
        return adapter_EVP_cast5_ecb();
    }

    EVP_CIPHER* EVP_cast5_ofb() const
    {
        return adapter_EVP_cast5_ofb();
    }

    EVP_CIPHER* EVP_des_cbc() const
    {
        return adapter_EVP_des_cbc();
    }

    EVP_CIPHER* EVP_des_cfb() const
    {
        return adapter_EVP_des_cfb();
    }

    EVP_CIPHER* EVP_des_ecb() const
    {
        return adapter_EVP_des_ecb();
    }

    EVP_CIPHER* EVP_des_ofb() const
    {
        return adapter_EVP_des_ofb();
    }

    EVP_CIPHER* EVP_des_ede3_cbc() const
    {
        return adapter_EVP_des_ede3_cbc();
    }

    EVP_CIPHER* EVP_des_ede3_cfb() const
    {
        return adapter_EVP_des_ede3_cfb();
    }

    EVP_CIPHER* EVP_des_ede3_ecb() const
    {
        return adapter_EVP_des_ede3_ecb();
    }

    EVP_CIPHER* EVP_des_ede3_ofb() const
    {
        return adapter_EVP_des_ede3_ofb();
    }

    EVP_CIPHER* EVP_aes_128_cbc() const
    {
        return adapter_EVP_aes_128_cbc();
    }

    EVP_CIPHER* EVP_aes_192_cbc() const
    {
        return adapter_EVP_aes_192_cbc();
    }

    EVP_CIPHER* EVP_aes_256_cbc() const
    {
        return adapter_EVP_aes_256_cbc();
    }

    EVP_CIPHER* EVP_aes_128_cfb() const
    {
        return adapter_EVP_aes_128_cfb();
    }

    EVP_CIPHER* EVP_aes_192_cfb() const
    {
        return adapter_EVP_aes_192_cfb();
    }

    EVP_CIPHER* EVP_aes_256_cfb() const
    {
        return adapter_EVP_aes_256_cfb();
    }

    EVP_CIPHER* EVP_aes_128_ecb() const
    {
        return adapter_EVP_aes_128_ecb();
    }

    EVP_CIPHER* EVP_aes_192_ecb() const
    {
        return adapter_EVP_aes_192_ecb();
    }

    EVP_CIPHER* EVP_aes_256_ecb() const
    {
        return adapter_EVP_aes_256_ecb();
    }

    EVP_CIPHER* EVP_aes_128_ofb() const
    {
        return adapter_EVP_aes_128_ofb();
    }

    EVP_CIPHER* EVP_aes_192_ofb() const
    {
        return adapter_EVP_aes_192_ofb();
    }

    EVP_CIPHER* EVP_aes_256_ofb() const
    {
        return adapter_EVP_aes_256_ofb();
    }

    void EVP_CIPHER_CTX_free(EVP_CIPHER_CTX* ctx) const @nogc
    {
        adapter_EVP_CIPHER_CTX_free(ctx);
    }

    EVP_CIPHER_CTX* EVP_CIPHER_CTX_new() const
    {
        return adapter_EVP_CIPHER_CTX_new();
    }

    int EVP_CIPHER_CTX_set_key_length(EVP_CIPHER_CTX* ctx, int keyLen) const
    {
        return adapter_EVP_CIPHER_CTX_set_key_length(ctx, keyLen);
    }

    int EVP_DecryptFinal_ex(EVP_CIPHER_CTX* ctx, ubyte* outData, int* outLen) const
    {
        return adapter_EVP_DecryptFinal_ex(ctx, outData, outLen);
    }

    int EVP_DecryptInit_ex(EVP_CIPHER_CTX* ctx, EVP_CIPHER* type, void* engineImpl, const(ubyte)* key, const(ubyte)* iv) const
    {
        return adapter_EVP_DecryptInit_ex(ctx, type, engineImpl, key, iv);
    }

    int EVP_DecryptUpdate(EVP_CIPHER_CTX* ctx, ubyte* outData, int* outLen, const(ubyte)* inData, int inLen) const
    {
        return adapter_EVP_DecryptUpdate(ctx, outData, outLen, inData, inLen);
    }

    int EVP_EncryptFinal_ex(EVP_CIPHER_CTX* ctx, ubyte* outData, int* outLen) const
    {
        return adapter_EVP_EncryptFinal_ex(ctx, outData, outLen);
    }

    int EVP_EncryptInit_ex(EVP_CIPHER_CTX* ctx, EVP_CIPHER* type, void* engineImpl, const(ubyte)* key, const(ubyte)* iv) const
    {
        return adapter_EVP_EncryptInit_ex(ctx, type, engineImpl, key, iv);
    }

    int EVP_EncryptUpdate(EVP_CIPHER_CTX* ctx, ubyte* outData, int* outLen, const(ubyte)* inData, int inLen) const
    {
        return adapter_EVP_EncryptUpdate(ctx, outData, outLen, inData, inLen);
    }

    void EVP_PKEY_free(EVP_PKEY* key) const @nogc
    {
        adapter_EVP_PKEY_free(key);
    }

    EVP_PKEY* EVP_PKEY_new() const
    {
        return adapter_EVP_PKEY_new();
    }

    void OPENSSL_free(void* p) const
    {
        CRYPTO_free(p);
    }

    EVP_PKEY* PEM_read_bio_PrivateKey(BIO* bio, EVP_PKEY** x, OpenSSLPemPasswordCallback cb, void* cbu) const
    {
        return adapter_PEM_read_bio_PrivateKey(bio, x, cb, cbu);
    }

    EVP_PKEY* PEM_read_bio_PUBKEY(BIO* bio, EVP_PKEY** x, OpenSSLPemPasswordCallback cb, void* cbu) const
    {
        return adapter_PEM_read_bio_PUBKEY(bio, x, cb, cbu);
    }

    RSA* PEM_read_bio_RSAPrivateKey(BIO* bio, RSA** x, OpenSSLPemPasswordCallback cb, void* cbu) const
    {
        return adapter_PEM_read_bio_RSAPrivateKey(bio, x, cb, cbu);
    }

    RSA* PEM_read_bio_RSA_PUBKEY(BIO* bio, RSA** x, OpenSSLPemPasswordCallback cb, void* cbu) const
    {
        return adapter_PEM_read_bio_RSA_PUBKEY(bio, x, cb, cbu);
    }

    int PEM_write_bio_RSAPrivateKey(BIO* bio, RSA* rsa,
        EVP_CIPHER* enCTX, const(ubyte)* keyStr, int keyLen, OpenSSLPemPasswordCallback cb, void* cbu) const
    {
        return adapter_PEM_write_bio_RSAPrivateKey(bio, rsa, enCTX, keyStr, keyLen, cb, cbu);
    }

    int PEM_write_bio_RSA_PUBKEY(BIO* bio, RSA* rsa) const
    {
        return adapter_PEM_write_bio_RSA_PUBKEY(bio, rsa);
    }

    void RAND_seed(const(void)* buf, int bufSize) const
    {
        adapter_RAND_seed(buf, bufSize);
    }

    void RSA_free(RSA* rsa) const @nogc
    {
        adapter_RSA_free(rsa);
    }

    int RSA_generate_key_ex(RSA* rsa, int bits, BIGNUM* e, void* cb) const
    {
        return adapter_RSA_generate_key_ex(rsa, bits, e, cb);
    }

    RSA* RSA_new() const
    {
        return adapter_RSA_new();
    }

    int RSA_private_decrypt(int fromLen, const(ubyte)* from, ubyte* to, RSA* rsa, int paddingMode) const
    {
        return adapter_RSA_private_decrypt(fromLen, from, to, rsa, paddingMode);
    }

    int RSA_private_encrypt(int fromLen, const(ubyte)* from, ubyte* to, RSA* rsa, int paddingMode) const
    {
        return adapter_RSA_private_encrypt(fromLen, from, to, rsa, paddingMode);
    }

    int RSA_public_decrypt(int fromLen, const(ubyte)* from, ubyte* to, RSA* rsa, int paddingMode) const
    {
        return adapter_RSA_public_decrypt(fromLen, from, to, rsa, paddingMode);
    }

    int RSA_public_encrypt(int fromLen, const(ubyte)* from, ubyte* to, RSA* rsa, int paddingMode) const
    {
        return adapter_RSA_public_encrypt(fromLen, from, to, rsa, paddingMode);
    }

    int RSA_security_bits(const(RSA)* rsa) const
    {
        return adapter_RSA_security_bits(rsa);
    }

    int RSA_size(const(RSA)* rsa) const
    {
        return adapter_RSA_size(rsa);
    }

    SSL_METHOD* TLS_method() const
    {
        return adapter_TLS_method();
    }

    SSL_METHOD* TLS_client_method() const
    {
        return adapter_TLS_client_method();
    }

    char* SSL_CIPHER_get_name(SSL_CIPHER* c) const
    {
        return adapter_SSL_CIPHER_get_name(c);
    }

    char* SSL_CIPHER_get_version(SSL_CIPHER* c) const
    {
        return adapter_SSL_CIPHER_get_version(c);
    }

    int SSL_CTX_check_private_key(SSL_CTX* ctx) const
    {
        return adapter_SSL_CTX_check_private_key(ctx);
    }

    c_long SSL_CTX_ctrl(SSL_CTX* ctx, int cmd, c_long larg, void* parg) const
    {
        return adapter_SSL_CTX_ctrl(ctx, cmd, larg, parg);
    }

    void SSL_CTX_free(SSL_CTX* ctx) const @nogc
    {
        adapter_SSL_CTX_free(ctx);
    }

    int SSL_CTX_load_verify_locations(SSL_CTX* ctx, const(char)* CAFile, const(char)* CAPath) const @nogc
    {
        return adapter_SSL_CTX_load_verify_locations(ctx, CAFile, CAPath);
    }

    SSL_CTX* SSL_CTX_new(SSL_METHOD* method) const
    {
        return adapter_SSL_CTX_new(method);
    }

    int SSL_CTX_get_ex_new_index(c_long argl, void* argp, CRYPTOExNew newFunc, CRYPTOExDup dupFunc, CRYPTOExFree freeFunc) const
    {
        //CRYPTO_EX_INDEX_SSL_CTX=1
        return CRYPTO_get_ex_new_index(1, argl, argp, newFunc, dupFunc, freeFunc);
    }

    X509_VERIFY_PARAM* SSL_CTX_get0_param(SSL_CTX* ctx) const
    {
        return adapter_SSL_CTX_get0_param(ctx);
    }

    // "TLS_AES_256_GCM_SHA384:TLS_CHACHA20_POLY1305_SHA256..."
    int SSL_CTX_set_cipher_list(SSL_CTX* ctx, const(char)* list) const @nogc
    {
        return adapter_SSL_CTX_set_cipher_list(ctx, list);
    }

    c_long SSL_CTX_set_tmp_dh(SSL_CTX* ctx, DH* dh) const
    {
        //SSL_CTRL_SET_DH_AUTO=118
        //SSL_CTX_ctrl(ctx, 118, 1, null);

        //SSL_CTRL_SET_TMP_DH=3
        return SSL_CTX_ctrl(ctx, 3, 0, dh);
    }

    void SSL_CTX_set_default_passwd_cb(SSL_CTX* ctx, OpenSSLPemPasswordCallback cb) const @nogc
    {
        adapter_SSL_CTX_set_default_passwd_cb(ctx, cb);
    }

    void SSL_CTX_set_default_passwd_cb_userdata(SSL_CTX* ctx, void* cbu) const @nogc
    {
        adapter_SSL_CTX_set_default_passwd_cb_userdata(ctx, cbu);
    }

    int SSL_CTX_set_default_verify_paths(SSL_CTX* ctx) const @nogc
    {
        return adapter_SSL_CTX_set_default_verify_paths(ctx);
    }

    int SSL_CTX_set_max_proto_version(SSL_CTX* ctx, int v) const @nogc
    {
        return adapter_SSL_CTX_ctrl(ctx, SSL_CTRL_SET_MAX_PROTO_VERSION, v, null);
    }

    int SSL_CTX_set_min_proto_version(SSL_CTX* ctx, int v) const @nogc
    {
        return adapter_SSL_CTX_ctrl(ctx, SSL_CTRL_SET_MIN_PROTO_VERSION, v, null);
    }

    c_long SSL_CTX_set_mode(SSL_CTX* ctx, int mode) const
    {
        //SSL_CTRL_MODE=33
        return SSL_CTX_ctrl(ctx, 33, mode, null);
    }

    c_ulong SSL_CTX_set_options(SSL_CTX* ctx, c_ulong options) const @nogc
    {
        return adapter_SSL_CTX_set_options(ctx, options);
    }

    void SSL_CTX_set_verify(SSL_CTX* ctx, int mode, OpenSSLVerifyCallback cb) const @nogc
    {
        adapter_SSL_CTX_set_verify(ctx, mode, cb);
    }

    void SSL_CTX_set_verify_depth(SSL_CTX* ctx, int depth) const @nogc
    {
        adapter_SSL_CTX_set_verify_depth(ctx, depth);
    }

    int SSL_CTX_use_certificate(SSL_CTX* ctx, X509* x) const @nogc
    {
        return adapter_SSL_CTX_use_certificate(ctx, x);
    }

    int SSL_CTX_use_certificate_chain_file(SSL_CTX* ctx, const(char)* file) const @nogc
    {
        return adapter_SSL_CTX_use_certificate_chain_file(ctx, file);
    }

    int SSL_CTX_use_certificate_file(SSL_CTX* ctx, const(char)* file, int type) const @nogc
    {
        return adapter_SSL_CTX_use_certificate_file(ctx, file, type);
    }

    int SSL_CTX_use_PrivateKey_file(SSL_CTX* ctx, const(char)* file, int type) const @nogc
    {
        return adapter_SSL_CTX_use_PrivateKey_file(ctx, file, type);
    }

    int SSL_accept(SSL* ssl) const
    {
        return adapter_SSL_accept(ssl);
    }

    int SSL_connect(SSL* ssl) const
    {
        return adapter_SSL_connect(ssl);
    }

    c_long SSL_ctrl(SSL* ssl, int cmd, c_long larg, void* parg) const
    {
        return adapter_SSL_ctrl(ssl, cmd, larg, parg);
    }

    void SSL_free(SSL* ssl) const @nogc
    {
        adapter_SSL_free(ssl);
    }

    SSL_CIPHER* SSL_get_current_cipher(SSL* ssl) const
    {
        return adapter_SSL_get_current_cipher(ssl);
    }

    int SSL_get_error(SSL* ssl, int err) const @nogc
    {
        return adapter_SSL_get_error(ssl, err);
    }

    void* SSL_get_ex_data(SSL* ssl, int idx) const
    {
        return adapter_SSL_get_ex_data(ssl, idx);
    }

    int SSL_get_ex_data_X509_STORE_CTX_idx() const
    {
        return adapter_SSL_get_ex_data_X509_STORE_CTX_idx();
    }

    int SSL_get_ex_new_index(c_long argl, void* argp, CRYPTOExNew newFunc, CRYPTOExDup dupFunc, CRYPTOExFree freeFunc) const
    {
        //CRYPTO_EX_INDEX_SSL=0
        return CRYPTO_get_ex_new_index(0, argl, argp, newFunc, dupFunc, freeFunc);
    }

    X509* SSL_get_peer_certificate(SSL* ssl) const
    {
        return adapter_SSL_get_peer_certificate(ssl);
    }

    c_long SSL_get_verify_result(SSL* ssl) const
    {
        return adapter_SSL_get_verify_result(ssl);
    }

    SSL* SSL_new(SSL_CTX* ctx) const @nogc
    {
        return adapter_SSL_new(ctx);
    }

    int SSL_pending(SSL* ssl) const @nogc
    {
        return adapter_SSL_pending(ssl);
    }

    int SSL_read(SSL* ssl, void* b, int n) const @nogc
    {
        return adapter_SSL_read(ssl, b, n);
    }

    int SSL_set_ex_data(SSL* ssl, int idx, void* arg) const
    {
        return adapter_SSL_set_ex_data(ssl, idx, arg);
    }

    int SSL_set_fd(SSL* ssl, int fd) const @nogc
    {
        return adapter_SSL_set_fd(ssl, fd);
    }

    c_ulong SSL_set_options(SSL* ssl, c_ulong options) const @nogc
    {
        return adapter_SSL_set_options(ssl, options);
    }

    void SSL_set_quiet_shutdown(SSL* ssl, int mode) const @nogc
    {
        adapter_SSL_set_quiet_shutdown(ssl, mode);
    }

    c_long SSL_set_tlsext_host_name(SSL* ssl, const(char)* host) const @nogc
    {
        enum SSL_CTRL_SET_TLSEXT_HOSTNAME = 55; // ssl.h
        enum TLSEXT_NAMETYPE_host_name = 0; // tls1.h
        return adapter_SSL_ctrl(ssl, SSL_CTRL_SET_TLSEXT_HOSTNAME, TLSEXT_NAMETYPE_host_name, cast(void*)host);
    }

    int SSL_shutdown(SSL* ssl) const @nogc
    {
        return adapter_SSL_shutdown(ssl);
    }

    int SSL_write(SSL* ssl, const(void)* b, int n) const @nogc
    {
        return adapter_SSL_write(ssl, b, n);
    }

    int X509_check_host(X509* x509, const(char)* name, size_t nameLen, uint flags, char** peerName) const
    {
        return adapter_X509_check_host(x509, name, nameLen, flags, peerName);
    }

    int X509_check_ip(X509* x509, const(char)* address, size_t addressLen, uint flags) const @nogc
    {
        return adapter_X509_check_ip(x509, address, addressLen, flags);
    }

    void X509_free(X509* x509) const @nogc
    {
        adapter_X509_free(x509);
    }

    int X509_VERIFY_PARAM_set1_host(X509_VERIFY_PARAM* param, const(char)* name, size_t nameLen) const
    {
        return adapter_X509_VERIFY_PARAM_set1_host(param, name, nameLen);
    }

    int X509_VERIFY_PARAM_set1_ip_asc(X509_VERIFY_PARAM* param, const(char)* ipasc) const
    {
        return adapter_X509_VERIFY_PARAM_set1_ip_asc(param, ipasc);
    }

    void ERR_clear_error() const
    {
        adapter_ERR_clear_error();
    }

    c_ulong ERR_get_error() const @nogc
    {
        return adapter_ERR_get_error();
    }

    char* ERR_reason_error_string(c_ulong code) const @nogc
    {
        return adapter_ERR_reason_error_string(code);
    }

public:
    ResultStatus status() const pure @safe
    {
        ResultStatus result = _loadSslStatus.isError
            ? _loadSslStatus
            : (_loadCryptoStatus.isError ? _loadCryptoStatus : ResultStatus.ok());
        return result;
    }

    @property VersionString sslVersion() const @nogc pure @safe
    {
        return _sslVersion;
    }

    @property LibName usedLibCryptoName() const @nogc pure @safe
    {
        return _usedLibCryptoName;
    }

    @property LibName usedLibSslName() const @nogc pure @safe
    {
        return _usedLibSslName;
    }

private:
    VersionString detectVersion() const
    {
        alias OpenSSL_version_num_fct = c_ulong function() @nogc nothrow;
        auto OpenSSL_version_num = cast(OpenSSL_version_num_fct)loadFct(cast(void*)_libCrypto, "OpenSSL_version_num".ptr);
        const v = OpenSSL_version_num();
        if (v)
        {
            const v2 = v & 0xFFFF_FFFF;
            return VersionString((v2 >> 20) & 0xFF, (v2 >> 12) & 0xFF);
        }
        else
            return VersionString(1, 0);
    }

    void initLib() const @nogc
    {
        if (_sslVersion.opEquals(1, 0))
            opensslApi.initLib1_0();
        else if (_sslVersion.opEquals(1, 1))
            opensslApi.initLib1_1();
        else
            opensslApi.initLib1_1();

        //opensslApi.loadSslStatus = ResultStatus.error(0, "Failed to init libssl. Unknown version");
    }

    void initLib1_0() const @nogc
    {
        adapter_SSL_library_init();
        adapter_OpenSSL_add_all_ciphers();
        adapter_OpenSSL_add_all_digests();
        adapter_SSL_load_error_strings();
    }

    void initLib1_1() const @nogc
    {
        adapter_OPENSSL_init_ssl(loadSslDefault, null);
        adapter_OPENSSL_init_crypto(loadCryptDefault, null);
    }

private:
    void* _libCrypto, _libSsl;
    ResultStatus _loadCryptoStatus, _loadSslStatus;
    VersionString _sslVersion;
    LibName _usedLibCryptoName, _usedLibSslName;

    // openssl 1.0.x init functions
    mixin(Function_decl!("SSL_library_init", int));
    mixin(Function_decl!("SSL_load_error_strings", void));
    mixin(Function_decl!("OpenSSL_add_all_ciphers", void));
    mixin(Function_decl!("OpenSSL_add_all_digests", void));

    // openssl 1.1.x init functions
    mixin(Function_decl!("OPENSSL_init_crypto", int, ulong, OPENSSL_INIT_SETTINGS*)); // fixed width 64 bit arg
    mixin(Function_decl!("OPENSSL_init_ssl", int, ulong, OPENSSL_INIT_SETTINGS*)); // fixed width 64 bit arg

    mixin(Function_decl!("BIO_ctrl", c_long, BIO*, int, c_long, void*));
    mixin(Function_decl!("BIO_free", int, BIO*));
    mixin(Function_decl!("BIO_new", BIO*, BIO_METHOD*));
    mixin(Function_decl!("BIO_new_file", BIO*, const(char)*, const(char)*));
    mixin(Function_decl!("BIO_new_mem_buf", BIO*, const(void)*, int));
    mixin(Function_decl!("BIO_read", int, BIO*, void*, int));
    mixin(Function_decl!("BIO_s_mem", BIO_METHOD*));
    mixin(Function_decl!("BIO_write", int, BIO*, const(void)*, int));

    mixin(Function_decl!("BN_bin2bn", BIGNUM*, const(ubyte)*, int, BIGNUM*));
    mixin(Function_decl!("BN_bn2dec", char*, BIGNUM*));
    mixin(Function_decl!("BN_bn2hex", char*, BIGNUM*));
    mixin(Function_decl!("BN_free", void, BIGNUM*));
    mixin(Function_decl!("BN_generate_prime_ex", int, BIGNUM*, int, int, BIGNUM*, BIGNUM*, void*));
    mixin(Function_decl!("BN_hex2bn", int, BIGNUM**, const(char)*));
    mixin(Function_decl!("BN_new", BIGNUM*));
    mixin(Function_decl!("BN_set_word", int, BIGNUM*, c_ulong));

    mixin(Function_decl!("CONF_modules_unload", void));

    mixin(Function_decl!("CRYPTO_free", void, void*, char*, int));
    mixin(Function_decl!("CRYPTO_get_ex_new_index", int, int, c_long, void*, void*, void*, void*));

    mixin(Function_decl!("DH_free", void, DH*));
    mixin(Function_decl!("DH_new", DH*));
    mixin(Function_decl!("DH_set0_pqg", int, DH*, BIGNUM*, BIGNUM*, BIGNUM*));

    mixin(Function_decl!("EVP_bf_cbc", EVP_CIPHER*));
    mixin(Function_decl!("EVP_bf_cfb", EVP_CIPHER*));
    mixin(Function_decl!("EVP_bf_ecb", EVP_CIPHER*));
    mixin(Function_decl!("EVP_bf_ofb", EVP_CIPHER*));

    mixin(Function_decl!("EVP_cast5_cbc", EVP_CIPHER*));
    mixin(Function_decl!("EVP_cast5_cfb", EVP_CIPHER*));
    mixin(Function_decl!("EVP_cast5_ecb", EVP_CIPHER*));
    mixin(Function_decl!("EVP_cast5_ofb", EVP_CIPHER*));

    mixin(Function_decl!("EVP_des_cbc", EVP_CIPHER*));
    mixin(Function_decl!("EVP_des_cfb", EVP_CIPHER*));
    mixin(Function_decl!("EVP_des_ecb", EVP_CIPHER*));
    mixin(Function_decl!("EVP_des_ofb", EVP_CIPHER*));
    mixin(Function_decl!("EVP_des_ede3_cbc", EVP_CIPHER*));
    mixin(Function_decl!("EVP_des_ede3_cfb", EVP_CIPHER*));
    mixin(Function_decl!("EVP_des_ede3_ecb", EVP_CIPHER*));
    mixin(Function_decl!("EVP_des_ede3_ofb", EVP_CIPHER*));

    mixin(Function_decl!("EVP_aes_128_cbc", EVP_CIPHER*));
    mixin(Function_decl!("EVP_aes_192_cbc", EVP_CIPHER*));
    mixin(Function_decl!("EVP_aes_256_cbc", EVP_CIPHER*));
    mixin(Function_decl!("EVP_aes_128_cfb", EVP_CIPHER*));
    mixin(Function_decl!("EVP_aes_192_cfb", EVP_CIPHER*));
    mixin(Function_decl!("EVP_aes_256_cfb", EVP_CIPHER*));
    mixin(Function_decl!("EVP_aes_128_ecb", EVP_CIPHER*));
    mixin(Function_decl!("EVP_aes_192_ecb", EVP_CIPHER*));
    mixin(Function_decl!("EVP_aes_256_ecb", EVP_CIPHER*));
    mixin(Function_decl!("EVP_aes_128_ofb", EVP_CIPHER*));
    mixin(Function_decl!("EVP_aes_192_ofb", EVP_CIPHER*));
    mixin(Function_decl!("EVP_aes_256_ofb", EVP_CIPHER*));

    mixin(Function_decl!("EVP_CIPHER_CTX_free", void, EVP_CIPHER_CTX*));
    mixin(Function_decl!("EVP_CIPHER_CTX_new", EVP_CIPHER_CTX*));
    mixin(Function_decl!("EVP_CIPHER_CTX_set_key_length", int, EVP_CIPHER_CTX*, int));
    mixin(Function_decl!("EVP_DecryptFinal_ex", int, EVP_CIPHER_CTX*, ubyte*, int*));
    mixin(Function_decl!("EVP_DecryptInit_ex", int, EVP_CIPHER_CTX*, EVP_CIPHER*, void*, const(ubyte)*, const(ubyte)*));
    mixin(Function_decl!("EVP_DecryptUpdate", int, EVP_CIPHER_CTX*, ubyte*, int*, const(ubyte)*, int));
    mixin(Function_decl!("EVP_EncryptFinal_ex", int, EVP_CIPHER_CTX*, ubyte*, int*));
    mixin(Function_decl!("EVP_EncryptInit_ex", int, EVP_CIPHER_CTX*, EVP_CIPHER*, void*, const(ubyte)*, const(ubyte)*));
    mixin(Function_decl!("EVP_EncryptUpdate", int, EVP_CIPHER_CTX*, ubyte*, int*, const(ubyte)*, int));

    mixin(Function_decl!("EVP_PKEY_free", void, EVP_PKEY*));
    mixin(Function_decl!("EVP_PKEY_new", EVP_PKEY*));

    mixin(Function_decl!("PEM_read_bio_PrivateKey", EVP_PKEY*, BIO*, EVP_PKEY**, void*, void*));
    mixin(Function_decl!("PEM_read_bio_PUBKEY", EVP_PKEY*, BIO*, EVP_PKEY**, void*, void*));
    mixin(Function_decl!("PEM_read_bio_RSAPrivateKey", RSA*, BIO*, RSA**, void*, void*));
    mixin(Function_decl!("PEM_read_bio_RSA_PUBKEY", RSA*, BIO*, RSA**, void*, void*));
    mixin(Function_decl!("PEM_write_bio_RSAPrivateKey", int, BIO*, RSA*, EVP_CIPHER*, const(ubyte)*, int, void*, void*));
    mixin(Function_decl!("PEM_write_bio_RSA_PUBKEY", int, BIO*, RSA*));

    mixin(Function_decl!("RAND_seed", void, const(void)*, int));

    mixin(Function_decl!("RSA_free", void, RSA*));
    mixin(Function_decl!("RSA_generate_key_ex", int, RSA*, int, BIGNUM*, void*));
    mixin(Function_decl!("RSA_new", RSA*));
    mixin(Function_decl!("RSA_private_decrypt", int, int, const(ubyte)*, ubyte*, RSA*, int));
    mixin(Function_decl!("RSA_private_encrypt", int, int, const(ubyte)*, ubyte*, RSA*, int));
    mixin(Function_decl!("RSA_public_decrypt", int, int, const(ubyte)*, ubyte*, RSA*, int));
    mixin(Function_decl!("RSA_public_encrypt", int, int, const(ubyte)*, ubyte*, RSA*, int));
    mixin(Function_decl!("RSA_security_bits", int, const(RSA)*));
    mixin(Function_decl!("RSA_size", int, const(RSA)*));

    // all other functions
    mixin(Function_decl!("TLS_method", SSL_METHOD*));
    mixin(Function_decl!("TLS_client_method", SSL_METHOD*));

    mixin(Function_decl!("SSL_CIPHER_get_name", char*, SSL_CIPHER*));
    mixin(Function_decl!("SSL_CIPHER_get_version", char*, SSL_CIPHER*));

    mixin(Function_decl!("SSL_CTX_check_private_key", int, SSL_CTX*));
    mixin(Function_decl!("SSL_CTX_ctrl", c_long, SSL_CTX*, int, c_long, void*));
    mixin(Function_decl!("SSL_CTX_free", void, SSL_CTX*));
    mixin(Function_decl!("SSL_CTX_load_verify_locations", int, SSL_CTX*, const(char)*, const(char)*));
    mixin(Function_decl!("SSL_CTX_new", SSL_CTX*, SSL_METHOD*));
    mixin(Function_decl!("SSL_CTX_get0_param", X509_VERIFY_PARAM*, SSL_CTX*));
    mixin(Function_decl!("SSL_CTX_set_cipher_list", int, SSL_CTX*, const(char)*));
    mixin(Function_decl!("SSL_CTX_set_default_passwd_cb", void, SSL_CTX*, void*));
    mixin(Function_decl!("SSL_CTX_set_default_passwd_cb_userdata", void, SSL_CTX*, void*));
    mixin(Function_decl!("SSL_CTX_set_default_verify_paths", int, SSL_CTX*));
    mixin(Function_decl!("SSL_CTX_set_options", c_ulong, SSL_CTX*, c_ulong));
    mixin(Function_decl!("SSL_CTX_set_verify", void, SSL_CTX*, int, void*));
    mixin(Function_decl!("SSL_CTX_set_verify_depth", void, SSL_CTX*, int));
    mixin(Function_decl!("SSL_CTX_use_certificate", int, SSL_CTX*, X509*));
    mixin(Function_decl!("SSL_CTX_use_certificate_chain_file", int, SSL_CTX*, const(char)*));
    mixin(Function_decl!("SSL_CTX_use_certificate_file", int, SSL_CTX*, const(char)*, int));
    mixin(Function_decl!("SSL_CTX_use_PrivateKey_file", int, SSL_CTX*, const(char)*, int));

    mixin(Function_decl!("SSL_accept", int, SSL*));
    mixin(Function_decl!("SSL_connect", int, SSL*));
    mixin(Function_decl!("SSL_ctrl", c_long, SSL*, int, c_long, void*));
    mixin(Function_decl!("SSL_free", void, SSL*));
    mixin(Function_decl!("SSL_get_current_cipher", SSL_CIPHER*, SSL*));
    mixin(Function_decl!("SSL_get_error", int, SSL*, int));
    mixin(Function_decl!("SSL_get_ex_data", void*, SSL*, int));
    mixin(Function_decl!("SSL_get_ex_data_X509_STORE_CTX_idx", int));
    mixin(Function_decl!("SSL_get_peer_certificate", X509*, SSL*));
    mixin(Function_decl!("SSL_get_verify_result", c_long, SSL*));
    mixin(Function_decl!("SSL_new", SSL*, SSL_CTX*));
    mixin(Function_decl!("SSL_pending", int, SSL*));
    mixin(Function_decl!("SSL_read", int, SSL*, void*, int));
    mixin(Function_decl!("SSL_set_ex_data", int, SSL*, int, void*));
    mixin(Function_decl!("SSL_set_fd", int, SSL*, int));
    mixin(Function_decl!("SSL_set_options", c_ulong, SSL*, c_ulong));
    mixin(Function_decl!("SSL_set_quiet_shutdown", void, SSL*, int));
    mixin(Function_decl!("SSL_shutdown", int, SSL*));
    mixin(Function_decl!("SSL_write", int, SSL*, const void*, int));

    mixin(Function_decl!("X509_check_host", int, X509*, const(char)*, size_t, uint, char**));
    mixin(Function_decl!("X509_check_ip", int, X509*, const(char)*, size_t, uint));
    mixin(Function_decl!("X509_free", void, X509*));
    mixin(Function_decl!("X509_VERIFY_PARAM_set1_host", int, X509_VERIFY_PARAM*, const(char)*, size_t));
    mixin(Function_decl!("X509_VERIFY_PARAM_set1_ip_asc", int, X509_VERIFY_PARAM*, const(char)*));

    mixin(Function_decl!("ERR_clear_error", void));
    mixin(Function_decl!("ERR_get_error", c_ulong));
    mixin(Function_decl!("ERR_reason_error_string", char*, c_ulong));
}

static immutable OpenSSLApi opensslApi;


private:

shared static this()
{
    foreach (lib; libSslNames)
    {
        opensslApi._libSsl = cast(typeof(opensslApi._libSsl))mixin(loadLib);
        if (opensslApi._libSsl !is null)
        {
            opensslApi._usedLibSslName = lib;
            break;
        }
    }

    foreach (lib; libCryptoNames)
    {
        opensslApi._libCrypto = cast(typeof(opensslApi._libCrypto))mixin(loadLib);
        if (opensslApi._libCrypto !is null)
        {
            opensslApi._usedLibCryptoName = lib;
            break;
        }
    }

    opensslApi._loadSslStatus = opensslApi._libSsl is null
        ? ResultStatus.error(0, "Failed to load libssl")
        : ResultStatus.ok();

    opensslApi._loadCryptoStatus = opensslApi._libCrypto is null
        ? ResultStatus.error(0, "Failed to load libcrypto")
        : ResultStatus.ok();

    if (opensslApi.status().isError)
        return;

    mixin(SSL_Function_set!("SSL_library_init", int));
    mixin(SSL_Function_set!("SSL_load_error_strings", void));
    mixin(CRYPTO_Function_set!("OpenSSL_add_all_ciphers", void));
    mixin(CRYPTO_Function_set!("OpenSSL_add_all_digests", void));

    mixin(SSL_Function_set!("OPENSSL_init_ssl", int, ulong, OPENSSL_INIT_SETTINGS*));
    mixin(CRYPTO_Function_set!("OPENSSL_init_crypto", int, ulong, OPENSSL_INIT_SETTINGS*));

    mixin(CRYPTO_Function_set!("BIO_ctrl", c_long, BIO*, int, c_long, void*));
    mixin(CRYPTO_Function_set!("BIO_free", int, BIO*));
    mixin(CRYPTO_Function_set!("BIO_new", BIO*, BIO_METHOD*));
    mixin(CRYPTO_Function_set!("BIO_new_file", BIO*, const(char)*, const(char)*));
    mixin(CRYPTO_Function_set!("BIO_new_mem_buf", BIO*, const(void)*, int));
    mixin(CRYPTO_Function_set!("BIO_read", int, BIO*, void*, int));
    mixin(CRYPTO_Function_set!("BIO_s_mem", BIO_METHOD*));
    mixin(CRYPTO_Function_set!("BIO_write", int, BIO*, const(void)*, int));

    mixin(CRYPTO_Function_set!("BN_bin2bn", BIGNUM*, const(ubyte)*, int, BIGNUM*));
    mixin(CRYPTO_Function_set!("BN_bn2dec", char*, BIGNUM*));
    mixin(CRYPTO_Function_set!("BN_bn2hex", char*, BIGNUM*));
    mixin(CRYPTO_Function_set!("BN_free", void, BIGNUM*));
    mixin(CRYPTO_Function_set!("BN_generate_prime_ex", int, BIGNUM*, int, int, BIGNUM*, BIGNUM*, void*));
    mixin(CRYPTO_Function_set!("BN_hex2bn", int, BIGNUM**, char*));
    mixin(CRYPTO_Function_set!("BN_new", BIGNUM*));
    mixin(CRYPTO_Function_set!("BN_set_word", int, BIGNUM*, c_ulong));

    mixin(CRYPTO_Function_set!("CONF_modules_unload", void));

    mixin(CRYPTO_Function_set!("CRYPTO_free", void, void*, char*, int));
    mixin(CRYPTO_Function_set!("CRYPTO_get_ex_new_index", int, int, c_long, void*, void*, void*, void*));

    mixin(CRYPTO_Function_set!("DH_free", void, DH*));
    mixin(CRYPTO_Function_set!("DH_new", DH*));
    mixin(CRYPTO_Function_set!("DH_set0_pqg", int, DH*, BIGNUM*, BIGNUM*, BIGNUM*));

    mixin(CRYPTO_Function_set!("EVP_bf_cbc", EVP_CIPHER*));
    mixin(CRYPTO_Function_set!("EVP_bf_cfb", EVP_CIPHER*));
    mixin(CRYPTO_Function_set!("EVP_bf_ecb", EVP_CIPHER*));
    mixin(CRYPTO_Function_set!("EVP_bf_ofb", EVP_CIPHER*));

    mixin(CRYPTO_Function_set!("EVP_cast5_cbc", EVP_CIPHER*));
    mixin(CRYPTO_Function_set!("EVP_cast5_cfb", EVP_CIPHER*));
    mixin(CRYPTO_Function_set!("EVP_cast5_ecb", EVP_CIPHER*));
    mixin(CRYPTO_Function_set!("EVP_cast5_ofb", EVP_CIPHER*));

    mixin(CRYPTO_Function_set!("EVP_des_cbc", EVP_CIPHER*));
    mixin(CRYPTO_Function_set!("EVP_des_cfb", EVP_CIPHER*));
    mixin(CRYPTO_Function_set!("EVP_des_ecb", EVP_CIPHER*));
    mixin(CRYPTO_Function_set!("EVP_des_ofb", EVP_CIPHER*));
    mixin(CRYPTO_Function_set!("EVP_des_ede3_cbc", EVP_CIPHER*));
    mixin(CRYPTO_Function_set!("EVP_des_ede3_cfb", EVP_CIPHER*));
    mixin(CRYPTO_Function_set!("EVP_des_ede3_ecb", EVP_CIPHER*));
    mixin(CRYPTO_Function_set!("EVP_des_ede3_ofb", EVP_CIPHER*));

    mixin(CRYPTO_Function_set!("EVP_aes_128_cbc", EVP_CIPHER*));
    mixin(CRYPTO_Function_set!("EVP_aes_192_cbc", EVP_CIPHER*));
    mixin(CRYPTO_Function_set!("EVP_aes_256_cbc", EVP_CIPHER*));
    mixin(CRYPTO_Function_set!("EVP_aes_128_cfb", EVP_CIPHER*));
    mixin(CRYPTO_Function_set!("EVP_aes_192_cfb", EVP_CIPHER*));
    mixin(CRYPTO_Function_set!("EVP_aes_256_cfb", EVP_CIPHER*));
    mixin(CRYPTO_Function_set!("EVP_aes_128_ecb", EVP_CIPHER*));
    mixin(CRYPTO_Function_set!("EVP_aes_192_ecb", EVP_CIPHER*));
    mixin(CRYPTO_Function_set!("EVP_aes_256_ecb", EVP_CIPHER*));
    mixin(CRYPTO_Function_set!("EVP_aes_128_ofb", EVP_CIPHER*));
    mixin(CRYPTO_Function_set!("EVP_aes_192_ofb", EVP_CIPHER*));
    mixin(CRYPTO_Function_set!("EVP_aes_256_ofb", EVP_CIPHER*));

    mixin(CRYPTO_Function_set!("EVP_CIPHER_CTX_free", void, EVP_CIPHER_CTX*));
    mixin(CRYPTO_Function_set!("EVP_CIPHER_CTX_new", EVP_CIPHER_CTX*));
    mixin(CRYPTO_Function_set!("EVP_CIPHER_CTX_set_key_length", int, EVP_CIPHER_CTX*, int));
    mixin(CRYPTO_Function_set!("EVP_DecryptFinal_ex", int, EVP_CIPHER_CTX*, ubyte*, int*));
    mixin(CRYPTO_Function_set!("EVP_DecryptInit_ex", int, EVP_CIPHER_CTX*, EVP_CIPHER*, void*, const(ubyte)*, const(ubyte)*));
    mixin(CRYPTO_Function_set!("EVP_DecryptUpdate", int, EVP_CIPHER_CTX*, ubyte*, int*, const(ubyte)*, int));
    mixin(CRYPTO_Function_set!("EVP_EncryptFinal_ex", int, EVP_CIPHER_CTX*, ubyte*, int*));
    mixin(CRYPTO_Function_set!("EVP_EncryptInit_ex", int, EVP_CIPHER_CTX*, EVP_CIPHER*, void*, const(ubyte)*, const(ubyte)*));
    mixin(CRYPTO_Function_set!("EVP_EncryptUpdate", int, EVP_CIPHER_CTX*, ubyte*, int*, const(ubyte)*, int));

    mixin(CRYPTO_Function_set!("EVP_PKEY_free", void, EVP_PKEY*));
    mixin(CRYPTO_Function_set!("EVP_PKEY_new", EVP_PKEY*));

    mixin(CRYPTO_Function_set!("PEM_read_bio_PrivateKey", EVP_PKEY*, BIO*, EVP_PKEY**, void*, void*));
    mixin(CRYPTO_Function_set!("PEM_read_bio_PUBKEY", EVP_PKEY*, BIO*, EVP_PKEY**, void*, void*));
    mixin(CRYPTO_Function_set!("PEM_read_bio_RSAPrivateKey", RSA*, BIO*, RSA**, void*, void*));
    mixin(CRYPTO_Function_set!("PEM_read_bio_RSA_PUBKEY", RSA*, BIO*, RSA**, void*, void*));
    mixin(CRYPTO_Function_set!("PEM_write_bio_RSAPrivateKey", int, BIO*, RSA*, EVP_CIPHER*, const(ubyte)*, int, void*, void*));
    mixin(CRYPTO_Function_set!("PEM_write_bio_RSA_PUBKEY", int, BIO*, RSA*));

    mixin(CRYPTO_Function_set!("RAND_seed", void, void*, int));

    mixin(CRYPTO_Function_set!("RSA_free", void, RSA*));
    mixin(CRYPTO_Function_set!("RSA_generate_key_ex", int, RSA*, int, BIGNUM*, void*));
    mixin(CRYPTO_Function_set!("RSA_new", RSA*));
    mixin(CRYPTO_Function_set!("RSA_private_decrypt", int, int, const(ubyte)*, ubyte*, RSA*, int));
    mixin(CRYPTO_Function_set!("RSA_private_encrypt", int, int, const(ubyte)*, ubyte*, RSA*, int));
    mixin(CRYPTO_Function_set!("RSA_public_decrypt", int, int, const(ubyte)*, ubyte*, RSA*, int));
    mixin(CRYPTO_Function_set!("RSA_public_encrypt", int, int, const(ubyte)*, ubyte*, RSA*, int));
    mixin(CRYPTO_Function_set!("RSA_security_bits", int, const(RSA)*));
    mixin(CRYPTO_Function_set!("RSA_size", int, const(RSA)*));

    mixin(SSL_Function_set!("TLS_method", SSL_METHOD*));
    mixin(SSL_Function_set!("TLS_client_method", SSL_METHOD*));

    mixin(SSL_Function_set!("SSL_CIPHER_get_name", char*, SSL_CIPHER*));
    mixin(SSL_Function_set!("SSL_CIPHER_get_version", char*, SSL_CIPHER*));

    mixin(SSL_Function_set!("SSL_CTX_check_private_key", int, SSL_CTX*));
    mixin(SSL_Function_set!("SSL_CTX_ctrl", c_long, SSL_CTX*, int, c_long, void*));
    mixin(SSL_Function_set!("SSL_CTX_free", void, SSL_CTX*));
    mixin(SSL_Function_set!("SSL_CTX_load_verify_locations", int, SSL_CTX*, const(char)*, const(char)*));
    mixin(SSL_Function_set!("SSL_CTX_new", SSL_CTX*, SSL_METHOD*));
    mixin(SSL_Function_set!("SSL_CTX_get0_param", X509_VERIFY_PARAM*, SSL_CTX*));
    mixin(SSL_Function_set!("SSL_CTX_set_default_verify_paths", int, SSL_CTX*));
    mixin(SSL_Function_set!("SSL_CTX_set_cipher_list", int, SSL_CTX*, const(char)*));
    mixin(SSL_Function_set!("SSL_CTX_set_options", c_ulong, SSL_CTX*, c_ulong));
    mixin(SSL_Function_set!("SSL_CTX_set_verify", void, SSL_CTX*, int, void*));
    mixin(SSL_Function_set!("SSL_CTX_set_verify_depth", void, SSL_CTX*, int));
    mixin(SSL_Function_set!("SSL_CTX_use_certificate", int, SSL_CTX*, X509*));
    mixin(SSL_Function_set!("SSL_CTX_use_certificate_chain_file", int, SSL_CTX*, const(char)*));
    mixin(SSL_Function_set!("SSL_CTX_use_certificate_file", int, SSL_CTX*, const(char)*, int));
    mixin(SSL_Function_set!("SSL_CTX_use_PrivateKey_file", int, SSL_CTX*, const(char)*, int));

    mixin(SSL_Function_set!("SSL_accept", int, SSL*));
    mixin(SSL_Function_set!("SSL_connect", int, SSL*));
    mixin(SSL_Function_set!("SSL_ctrl", c_long, SSL*, int, c_long, void*));
    mixin(SSL_Function_set!("SSL_free", void, SSL*));
    mixin(SSL_Function_set!("SSL_get_current_cipher", SSL_CIPHER*, SSL*));
    mixin(SSL_Function_set!("SSL_get_error", int, SSL*, int));
    mixin(SSL_Function_set!("SSL_get_ex_data", void*, SSL*, int));
    mixin(SSL_Function_set!("SSL_get_ex_data_X509_STORE_CTX_idx", int));
    mixin(SSL_Function_set!("SSL_get_peer_certificate", X509*, SSL*));
    mixin(SSL_Function_set!("SSL_get_verify_result", c_long, SSL*));
    mixin(SSL_Function_set!("SSL_new", SSL*, SSL_CTX*));
    mixin(SSL_Function_set!("SSL_pending", int, SSL*));
    mixin(SSL_Function_set!("SSL_read", int, SSL*, void*, int));
    mixin(SSL_Function_set!("SSL_CTX_set_default_passwd_cb", void, SSL_CTX*, void*));
    mixin(SSL_Function_set!("SSL_CTX_set_default_passwd_cb_userdata", void, SSL_CTX*, void*));
    mixin(SSL_Function_set!("SSL_set_ex_data", int, SSL*, int, void*));
    mixin(SSL_Function_set!("SSL_set_fd", int, SSL*, int));
    mixin(SSL_Function_set!("SSL_set_options", c_ulong, SSL*, c_ulong));
    mixin(SSL_Function_set!("SSL_set_quiet_shutdown", void, SSL*, int));
    mixin(SSL_Function_set!("SSL_shutdown", int, SSL*));
    mixin(SSL_Function_set!("SSL_write", int, SSL*, const void*, int));

    mixin(CRYPTO_Function_set!("X509_check_host", int, X509*, const(char)*, size_t, uint, char**));
    mixin(CRYPTO_Function_set!("X509_check_ip", int, X509*, const(char)*, size_t, uint));
    mixin(CRYPTO_Function_set!("X509_free", void, X509*));
    mixin(CRYPTO_Function_set!("X509_VERIFY_PARAM_set1_host", int, X509_VERIFY_PARAM*, const(char)*, size_t));
    mixin(CRYPTO_Function_set!("X509_VERIFY_PARAM_set1_ip_asc", int, X509_VERIFY_PARAM*, const(char)*));

    mixin(CRYPTO_Function_set!("ERR_clear_error", void));
    mixin(CRYPTO_Function_set!("ERR_get_error", c_ulong));
    mixin(CRYPTO_Function_set!("ERR_reason_error_string", char*, c_ulong));

    opensslApi._sslVersion = opensslApi.detectVersion();
    opensslApi.initLib();
}

shared static ~this()
{
    if (opensslApi._libCrypto !is null)
    {
        opensslApi.CONF_modules_unload();

        unloadLibFct(cast(void*)opensslApi._libCrypto);
        (cast()opensslApi)._libCrypto = null;
    }

    if (opensslApi._libSsl !is null)
    {
        unloadLibFct(cast(void*)opensslApi._libSsl);
        (cast()opensslApi)._libSsl = null;
    }
}

/**
 * N - function name
 * R - return type
 * A - args
 */
string Function_decl(string N, R, A...)()
{
    // A.stringof will add beginning '(' and ending ')' automatically
    return "extern (C) " ~ R.stringof ~ " function" ~ A.stringof ~ " @nogc nothrow adapter_" ~ N ~ ";";
}

string SSL_Function_set(string N, R, A...)()
{
    enum qutName = '"' ~ N ~ '"';
    enum varName = "opensslApi.adapter_" ~ N;
    return varName ~ " = cast(typeof(" ~ varName ~ "))loadFct(cast(void*)opensslApi._libSsl, " ~ qutName ~ ");";
}

string CRYPTO_Function_set(string N, R, A...)()
{
    enum qutName = '"' ~ N ~ '"';
    enum varName = "opensslApi.adapter_" ~ N;
    return varName ~ " = cast(typeof(" ~ varName ~ "))loadFct(cast(void*)opensslApi._libCrypto, " ~ qutName ~ ");";
}
