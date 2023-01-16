/**
 * Windows API header module
 *
 * Translated from MinGW Windows headers
 *
 * Authors: Ellery Newcomer
 * License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
 * Source: $(DRUNTIMESRC src/core/sys/windows/_sspi.d)
 */
module pham.external.std.windows.sspi;

version (Windows):
nothrow:
@system:

version (ANSI)
{}
else
{
    version = Unicode;
}

import core.sys.windows.windef : LUID, PLUID, PVOID, USHORT;
public import core.sys.windows.windef : HANDLE, ULONG, PULONG, ULONG_PTR;
import core.sys.windows.ntdef : UNICODE_STRING;
import core.sys.windows.w32api : _WIN32_WINNT;
import core.sys.windows.security : SEC_CHAR, SEC_WCHAR;
public import core.sys.windows.security : SEC_E_OK, SEC_I_CONTINUE_NEEDED, SEC_I_COMPLETE_NEEDED, SEC_I_COMPLETE_AND_CONTINUE, SECURITY_STATUS;
//import core.sys.windows.ntsecapi;
//import core.sys.windows.subauth;

pragma(lib, "Secur32.lib");

enum : ULONG
{
    SECPKG_CRED_INBOUND = 1,
    SECPKG_CRED_OUTBOUND = 2,
    SECPKG_CRED_BOTH = SECPKG_CRED_OUTBOUND | SECPKG_CRED_INBOUND,
    SECPKG_CRED_ATTR_NAMES = 1,
}

enum : ULONG
{
    SECPKG_FLAG_INTEGRITY = 1,
    SECPKG_FLAG_PRIVACY = 2,
    SECPKG_FLAG_TOKEN_ONLY = 4,
    SECPKG_FLAG_DATAGRAM = 8,
    SECPKG_FLAG_CONNECTION = 16,
    SECPKG_FLAG_MULTI_REQUIRED = 32,
    SECPKG_FLAG_CLIENT_ONLY = 64,
    SECPKG_FLAG_EXTENDED_ERROR = 128,
    SECPKG_FLAG_IMPERSONATION = 256,
    SECPKG_FLAG_ACCEPT_WIN32_NAME = 512,
    SECPKG_FLAG_STREAM = 1024,
}

enum : ULONG
{
    SECPKG_ATTR_AUTHORITY = 6,
    SECPKG_ATTR_CONNECTION_INFO = 90,
    SECPKG_ATTR_ISSUER_LIST = 80,
    SECPKG_ATTR_ISSUER_LIST_EX = 89,
    SECPKG_ATTR_KEY_INFO = 5,
    SECPKG_ATTR_LIFESPAN = 2,
    SECPKG_ATTR_LOCAL_CERT_CONTEXT = 84,
    SECPKG_ATTR_LOCAL_CRED = 82,
    SECPKG_ATTR_NAMES = 1,
    SECPKG_ATTR_PROTO_INFO = 7,
    SECPKG_ATTR_REMOTE_CERT_CONTEXT = 83,
    SECPKG_ATTR_REMOTE_CRED = 81,
    SECPKG_ATTR_SIZES = 0,
    SECPKG_ATTR_STREAM_SIZES = 4,
}

enum : ULONG
{
    SECBUFFER_EMPTY = 0,
    SECBUFFER_DATA = 1,
    SECBUFFER_TOKEN = 2,
    SECBUFFER_PKG_PARAMS = 3,
    SECBUFFER_MISSING = 4,
    SECBUFFER_EXTRA = 5,
    SECBUFFER_STREAM_TRAILER = 6,
    SECBUFFER_STREAM_HEADER = 7,
    SECBUFFER_PADDING = 9,
    SECBUFFER_STREAM = 10,
    SECBUFFER_READONLY = 0x80000000,
    SECBUFFER_ATTRMASK = 0xf0000000,
}

enum : ULONG
{
    ISC_REQ_DELEGATE = 0x00000001,
    ISC_REQ_MUTUAL_AUTH = 0x00000002,
    ISC_REQ_REPLAY_DETECT = 0x00000004,
    ISC_REQ_SEQUENCE_DETECT = 0x00000008,
    ISC_REQ_CONFIDENTIALITY = 0x00000010,
    ISC_REQ_USE_SESSION_KEY = 0x00000020,
    ISC_REQ_PROMPT_FOR_CREDS = 0x00000040,
    ISC_REQ_USE_SUPPLIED_CREDS = 0x00000080,
    ISC_REQ_ALLOCATE_MEMORY = 0x00000100,
    ISC_REQ_USE_DCE_STYLE = 0x00000200,
    ISC_REQ_DATAGRAM = 0x00000400,
    ISC_REQ_CONNECTION = 0x00000800,
    ISC_REQ_CALL_LEVEL = 0x00001000,
    ISC_REQ_FRAGMENT_SUPPLIED = 0x00002000,
    ISC_REQ_EXTENDED_ERROR = 0x00004000,
    ISC_REQ_STREAM = 0x00008000,
    ISC_REQ_INTEGRITY = 0x00010000,
    ISC_REQ_IDENTIFY = 0x00020000,
    ISC_REQ_NULL_SESSION = 0x00040000,
    ISC_REQ_MANUAL_CRED_VALIDATION = 0x00080000,
    ISC_REQ_RESERVED1 = 0x00100000,
    ISC_REQ_FRAGMENT_TO_FIT = 0x00200000,

    ISC_REQ_STANDARD_CONTEXT_ATTRIBUTES
        = ISC_REQ_CONFIDENTIALITY | ISC_REQ_REPLAY_DETECT
        | ISC_REQ_SEQUENCE_DETECT | ISC_REQ_CONNECTION,
}

enum : ULONG
{
    SECURITY_NATIVE_DREP = 0x10
}

enum UNISP_NAME_A = "Microsoft Unified Security Protocol Provider";
enum UNISP_NAME_W = "Microsoft Unified Security Protocol Provider"w;
enum SECBUFFER_VERSION = 0;

alias SECURITY_STRING = UNICODE_STRING;
alias PSECURITY_STRING = UNICODE_STRING*;


extern (Windows):

struct SecHandle
{
    ULONG_PTR dwLower;
    ULONG_PTR dwUpper;

    bool isValid() @nogc nothrow pure @trusted
    {
        return dwLower != 0 || dwUpper != 0;
    }

    void reset() @nogc nothrow pure @trusted
    {
        dwLower = dwUpper = 0;
    }
}
alias PSecHandle = SecHandle*;

struct SecBuffer
{
    ULONG cbBuffer;
    ULONG BufferType;
    PVOID pvBuffer;
}
alias PSecBuffer = SecBuffer*;

alias CredHandle = SecHandle;
alias PCredHandle = PSecHandle;
alias CtxtHandle = SecHandle;
alias PCtxtHandle = PSecHandle;

struct SECURITY_INTEGER
{
    uint LowPart;
    int HighPart;
}

alias TimeStamp = SECURITY_INTEGER;
alias PTimeStamp = SECURITY_INTEGER*;

struct SecBufferDesc
{
    ULONG ulVersion;
    ULONG cBuffers;
    PSecBuffer pBuffers;
}
alias PSecBufferDesc = SecBufferDesc*;

struct SecPkgContext_StreamSizes
{
    ULONG cbHeader;
    ULONG cbTrailer;
    ULONG cbMaximumMessage;
    ULONG cBuffers;
    ULONG cbBlockSize;
}
alias PSecPkgContext_StreamSizes = SecPkgContext_StreamSizes*;

struct SecPkgContext_Sizes
{
    ULONG cbMaxToken;
    ULONG cbMaxSignature;
    ULONG cbBlockSize;
    ULONG cbSecurityTrailer;
}
alias PSecPkgContext_Sizes = SecPkgContext_Sizes*;

struct SecPkgContext_AuthorityW
{
    SEC_WCHAR* sAuthorityName;
}
alias PSecPkgContext_AuthorityW = SecPkgContext_AuthorityW*;

struct SecPkgContext_AuthorityA
{
    SEC_CHAR* sAuthorityName;
}
alias PSecPkgContext_AuthorityA = SecPkgContext_AuthorityA*;

struct SecPkgContext_KeyInfoW
{
    SEC_WCHAR* sSignatureAlgorithmName;
    SEC_WCHAR* sEncryptAlgorithmName;
    ULONG KeySize;
    ULONG SignatureAlgorithm;
    ULONG EncryptAlgorithm;
}
alias PSecPkgContext_KeyInfoW = SecPkgContext_KeyInfoW*;

struct SecPkgContext_KeyInfoA
{
    SEC_CHAR* sSignatureAlgorithmName;
    SEC_CHAR* sEncryptAlgorithmName;
    ULONG KeySize;
    ULONG SignatureAlgorithm;
    ULONG EncryptAlgorithm;
}
alias PSecPkgContext_KeyInfoA = SecPkgContext_KeyInfoA*;

struct SecPkgContext_LifeSpan
{
    TimeStamp tsStart;
    TimeStamp tsExpiry;
}
alias PSecPkgContext_LifeSpan = SecPkgContext_LifeSpan*;

struct SecPkgContext_NamesW
{
    SEC_WCHAR* sUserName;
}
alias PSecPkgContext_NamesW = SecPkgContext_NamesW*;

struct SecPkgContext_NamesA
{
    SEC_CHAR* sUserName;
}
alias PSecPkgContext_NamesA = SecPkgContext_NamesA*;

struct SecPkgInfoW
{
    ULONG fCapabilities;
    USHORT wVersion;
    USHORT wRPCID;
    ULONG cbMaxToken;
    SEC_WCHAR* Name;
    SEC_WCHAR* Comment;
}
alias PSecPkgInfoW = SecPkgInfoW*;

struct SecPkgInfoA
{
    ULONG fCapabilities;
    USHORT wVersion;
    USHORT wRPCID;
    ULONG cbMaxToken;
    SEC_CHAR* Name;
    SEC_CHAR* Comment;
}
alias PSecPkgInfoA = SecPkgInfoA*;

/* supported only in win2k+, so it should be a PSecPkgInfoW */
/* PSDK does not say it has ANSI/Unicode versions */
struct SecPkgContext_PackageInfo
{
    PSecPkgInfoW PackageInfo;
}
alias PSecPkgContext_PackageInfo = SecPkgContext_PackageInfo*;

struct SecPkgCredentials_NamesW
{
    SEC_WCHAR* sUserName;
}
alias PSecPkgCredentials_NamesW = SecPkgCredentials_NamesW*;

struct SecPkgCredentials_NamesA
{
    SEC_CHAR* sUserName;
}
alias PSecPkgCredentials_NamesA = SecPkgCredentials_NamesA*;

/* TODO: missing type in SDK */

alias SEC_GET_KEY_FN = void function();
alias ENUMERATE_SECURITY_PACKAGES_FN_W = SECURITY_STATUS function(PULONG, PSecPkgInfoW*);
alias ENUMERATE_SECURITY_PACKAGES_FN_A = SECURITY_STATUS function(PULONG, PSecPkgInfoA*);
alias QUERY_CREDENTIALS_ATTRIBUTES_FN_W = SECURITY_STATUS function(PCredHandle, ULONG, PVOID);
alias QUERY_CREDENTIALS_ATTRIBUTES_FN_A = SECURITY_STATUS function(PCredHandle, ULONG, PVOID);
alias ACQUIRE_CREDENTIALS_HANDLE_FN_W = SECURITY_STATUS function(SEC_WCHAR*, SEC_WCHAR*, ULONG, PLUID, PVOID,
    SEC_GET_KEY_FN, PVOID, PCredHandle, PTimeStamp);
alias ACQUIRE_CREDENTIALS_HANDLE_FN_A = SECURITY_STATUS function(const(SEC_CHAR)*, const(SEC_CHAR)*, ULONG,
    PLUID, PVOID, SEC_GET_KEY_FN, PVOID, PCredHandle, PTimeStamp);
alias FREE_CREDENTIALS_HANDLE_FN = SECURITY_STATUS function(PCredHandle);
alias INITIALIZE_SECURITY_CONTEXT_FN_W = SECURITY_STATUS function(PCredHandle, PCtxtHandle, SEC_WCHAR*, ULONG, ULONG,
    ULONG, PSecBufferDesc, ULONG, PCtxtHandle, PSecBufferDesc, PULONG, PTimeStamp);
alias INITIALIZE_SECURITY_CONTEXT_FN_A = SECURITY_STATUS function(PCredHandle, PCtxtHandle, const(SEC_CHAR)*, ULONG, ULONG,
    ULONG, PSecBufferDesc, ULONG, PCtxtHandle, PSecBufferDesc, PULONG, PTimeStamp);
alias ACCEPT_SECURITY_CONTEXT_FN = SECURITY_STATUS function(PCredHandle, PCtxtHandle, PSecBufferDesc, ULONG,
    ULONG, PCtxtHandle, PSecBufferDesc, PULONG, PTimeStamp);
alias COMPLETE_AUTH_TOKEN_FN = SECURITY_STATUS function(PCtxtHandle, PSecBufferDesc);
alias DELETE_SECURITY_CONTEXT_FN = SECURITY_STATUS function(PCtxtHandle);
alias APPLY_CONTROL_TOKEN_FN_W = SECURITY_STATUS function(PCtxtHandle, PSecBufferDesc);
alias APPLY_CONTROL_TOKEN_FN_A = SECURITY_STATUS function(PCtxtHandle, PSecBufferDesc);
alias QUERY_CONTEXT_ATTRIBUTES_FN_A = SECURITY_STATUS function(PCtxtHandle, ULONG, PVOID);
alias QUERY_CONTEXT_ATTRIBUTES_FN_W = SECURITY_STATUS function(PCtxtHandle, ULONG, PVOID);
alias IMPERSONATE_SECURITY_CONTEXT_FN = SECURITY_STATUS function(PCtxtHandle);
alias REVERT_SECURITY_CONTEXT_FN = SECURITY_STATUS function(PCtxtHandle);
alias MAKE_SIGNATURE_FN = SECURITY_STATUS function(PCtxtHandle, ULONG, PSecBufferDesc, ULONG);
alias VERIFY_SIGNATURE_FN = SECURITY_STATUS function(PCtxtHandle, PSecBufferDesc, ULONG, PULONG);
alias FREE_CONTEXT_BUFFER_FN = SECURITY_STATUS function(PVOID);
alias QUERY_SECURITY_PACKAGE_INFO_FN_A = SECURITY_STATUS function(const(SEC_CHAR)*, scope PSecPkgInfoA*);
alias QUERY_SECURITY_CONTEXT_TOKEN_FN = SECURITY_STATUS function(scope PCtxtHandle, scope HANDLE*);
alias QUERY_SECURITY_PACKAGE_INFO_FN_W = SECURITY_STATUS function(const(SEC_WCHAR)*, scope PSecPkgInfoW*);
alias ENCRYPT_MESSAGE_FN = SECURITY_STATUS function(PCtxtHandle, ULONG, PSecBufferDesc, ULONG);
alias DECRYPT_MESSAGE_FN = SECURITY_STATUS function(PCtxtHandle, PSecBufferDesc, ULONG, PULONG);

/* No, it really is FreeCredentialsHandle, see the thread beginning
 * http://sourceforge.net/mailarchive/message.php?msg_id=4321080 for a
 * discovery discussion. */
struct SecurityFunctionTableW
{
    uint dwVersion;
    ENUMERATE_SECURITY_PACKAGES_FN_W EnumerateSecurityPackagesW;
    QUERY_CREDENTIALS_ATTRIBUTES_FN_W QueryCredentialsAttributesW;
    ACQUIRE_CREDENTIALS_HANDLE_FN_W AcquireCredentialsHandleW;
    FREE_CREDENTIALS_HANDLE_FN FreeCredentialsHandle;
    void* Reserved2;
    INITIALIZE_SECURITY_CONTEXT_FN_W InitializeSecurityContextW;
    ACCEPT_SECURITY_CONTEXT_FN AcceptSecurityContext;
    COMPLETE_AUTH_TOKEN_FN CompleteAuthToken;
    DELETE_SECURITY_CONTEXT_FN DeleteSecurityContext;
    APPLY_CONTROL_TOKEN_FN_W ApplyControlTokenW;
    QUERY_CONTEXT_ATTRIBUTES_FN_W QueryContextAttributesW;
    IMPERSONATE_SECURITY_CONTEXT_FN ImpersonateSecurityContext;
    REVERT_SECURITY_CONTEXT_FN RevertSecurityContext;
    MAKE_SIGNATURE_FN MakeSignature;
    VERIFY_SIGNATURE_FN VerifySignature;
    FREE_CONTEXT_BUFFER_FN FreeContextBuffer;
    QUERY_SECURITY_PACKAGE_INFO_FN_W QuerySecurityPackageInfoW;
    void* Reserved3;
    void* Reserved4;
    void* Reserved5;
    void* Reserved6;
    void* Reserved7;
    void* Reserved8;
    QUERY_SECURITY_CONTEXT_TOKEN_FN QuerySecurityContextToken;
    ENCRYPT_MESSAGE_FN EncryptMessage;
    DECRYPT_MESSAGE_FN DecryptMessage;
}
alias PSecurityFunctionTableW = SecurityFunctionTableW*;
alias INIT_SECURITY_INTERFACE_W = PSecurityFunctionTableW function();

struct SecurityFunctionTableA
{
    uint dwVersion;
    ENUMERATE_SECURITY_PACKAGES_FN_A EnumerateSecurityPackagesA;
    QUERY_CREDENTIALS_ATTRIBUTES_FN_A QueryCredentialsAttributesA;
    ACQUIRE_CREDENTIALS_HANDLE_FN_A AcquireCredentialsHandleA;
    FREE_CREDENTIALS_HANDLE_FN FreeCredentialsHandle;
    void* Reserved2;
    INITIALIZE_SECURITY_CONTEXT_FN_A InitializeSecurityContextA;
    ACCEPT_SECURITY_CONTEXT_FN AcceptSecurityContext;
    COMPLETE_AUTH_TOKEN_FN CompleteAuthToken;
    DELETE_SECURITY_CONTEXT_FN DeleteSecurityContext;
    APPLY_CONTROL_TOKEN_FN_A ApplyControlTokenA;
    QUERY_CONTEXT_ATTRIBUTES_FN_A QueryContextAttributesA;
    IMPERSONATE_SECURITY_CONTEXT_FN ImpersonateSecurityContext;
    REVERT_SECURITY_CONTEXT_FN RevertSecurityContext;
    MAKE_SIGNATURE_FN MakeSignature;
    VERIFY_SIGNATURE_FN VerifySignature;
    FREE_CONTEXT_BUFFER_FN FreeContextBuffer;
    QUERY_SECURITY_PACKAGE_INFO_FN_A QuerySecurityPackageInfoA;
    void* Reserved3;
    void* Reserved4;
    void* Unknown1;
    void* Unknown2;
    void* Unknown3;
    void* Unknown4;
    void* Unknown5;
    ENCRYPT_MESSAGE_FN EncryptMessage;
    DECRYPT_MESSAGE_FN DecryptMessage;
}
alias PSecurityFunctionTableA = SecurityFunctionTableA*;
alias INIT_SECURITY_INTERFACE_A = PSecurityFunctionTableA function();

SECURITY_STATUS FreeCredentialsHandle(PCredHandle);
SECURITY_STATUS EnumerateSecurityPackagesA(scope PULONG, scope PSecPkgInfoA*);
SECURITY_STATUS EnumerateSecurityPackagesW(scope PULONG, scope PSecPkgInfoW*);
SECURITY_STATUS AcquireCredentialsHandleA(scope const(SEC_CHAR)*, scope const(SEC_CHAR)*, ULONG,
    scope PLUID, PVOID, SEC_GET_KEY_FN, PVOID, scope PCredHandle, scope PTimeStamp);
SECURITY_STATUS AcquireCredentialsHandleW(scope const(SEC_WCHAR)*, scope const(SEC_WCHAR)*, ULONG,
    scope PLUID, PVOID, SEC_GET_KEY_FN, PVOID, scope PCredHandle, scope PTimeStamp);
SECURITY_STATUS AcceptSecurityContext(scope PCredHandle, scope PCtxtHandle, scope PSecBufferDesc,
    ULONG, ULONG, scope PCtxtHandle, scope PSecBufferDesc, scope PULONG, scope PTimeStamp);
SECURITY_STATUS InitializeSecurityContextA(scope PCredHandle, scope PCtxtHandle, scope const(SEC_CHAR)*, ULONG, ULONG,
    ULONG, scope PSecBufferDesc, ULONG, scope PCtxtHandle, scope PSecBufferDesc, scope PULONG, scope PTimeStamp);
SECURITY_STATUS InitializeSecurityContextW(scope PCredHandle, scope PCtxtHandle, scope const(SEC_WCHAR)*, ULONG, ULONG,
    ULONG, scope PSecBufferDesc, ULONG, scope PCtxtHandle, scope PSecBufferDesc, scope PULONG, scope PTimeStamp);
SECURITY_STATUS FreeContextBuffer(PVOID);
SECURITY_STATUS QueryContextAttributesA(scope PCtxtHandle, ULONG, PVOID);
SECURITY_STATUS QueryContextAttributesW(scope PCtxtHandle, ULONG, PVOID);
SECURITY_STATUS QueryCredentialsAttributesA(scope PCredHandle, ULONG, PVOID);
SECURITY_STATUS QueryCredentialsAttributesW(scope PCredHandle, ULONG, PVOID);
static if (_WIN32_WINNT >= 0x500)
{
    SECURITY_STATUS QuerySecurityContextToken(scope PCtxtHandle, scope HANDLE*);
}
SECURITY_STATUS DecryptMessage(scope PCtxtHandle, scope PSecBufferDesc, ULONG, scope PULONG);
SECURITY_STATUS EncryptMessage(scope PCtxtHandle, ULONG, scope PSecBufferDesc, ULONG);
SECURITY_STATUS DeleteSecurityContext(PCtxtHandle);
SECURITY_STATUS CompleteAuthToken(scope PCtxtHandle, scope PSecBufferDesc);
SECURITY_STATUS ApplyControlTokenA(scope PCtxtHandle, scope PSecBufferDesc);
SECURITY_STATUS ApplyControlTokenW(scope PCtxtHandle, scope PSecBufferDesc);
SECURITY_STATUS ImpersonateSecurityContext(scope PCtxtHandle);
SECURITY_STATUS RevertSecurityContext(scope PCtxtHandle);
SECURITY_STATUS MakeSignature(scope PCtxtHandle, ULONG, scope PSecBufferDesc, ULONG);
SECURITY_STATUS VerifySignature(scope PCtxtHandle, scope PSecBufferDesc, ULONG, scope PULONG);
SECURITY_STATUS QuerySecurityPackageInfoA(scope const(SEC_CHAR)*, scope PSecPkgInfoA*);
SECURITY_STATUS QuerySecurityPackageInfoW(scope const(SEC_WCHAR)*, scope PSecPkgInfoW*);
PSecurityFunctionTableA InitSecurityInterfaceA();
PSecurityFunctionTableW InitSecurityInterfaceW();

version (Unicode)
{
    alias UNISP_NAME = UNISP_NAME_W;
    alias SecPkgInfo = SecPkgInfoW;
    alias PSecPkgInfo = PSecPkgInfoW;
    alias SecPkgCredentials_Names = SecPkgCredentials_NamesW;
    alias PSecPkgCredentials_Names = PSecPkgCredentials_NamesW;
    alias SecPkgContext_Authority = SecPkgContext_AuthorityW;
    alias PSecPkgContext_Authority = PSecPkgContext_AuthorityW;
    alias SecPkgContext_KeyInfo = SecPkgContext_KeyInfoW;
    alias PSecPkgContext_KeyInfo = PSecPkgContext_KeyInfoW;
    alias SecPkgContext_Names = SecPkgContext_NamesW;
    alias PSecPkgContext_Names = PSecPkgContext_NamesW;
    alias SecurityFunctionTable = SecurityFunctionTableW;
    alias PSecurityFunctionTable = PSecurityFunctionTableW;
    alias AcquireCredentialsHandle = AcquireCredentialsHandleW;
    alias EnumerateSecurityPackages = EnumerateSecurityPackagesW;
    alias InitializeSecurityContext = InitializeSecurityContextW;
    alias QueryContextAttributes = QueryContextAttributesW;
    alias QueryCredentialsAttributes = QueryCredentialsAttributesW;
    alias QuerySecurityPackageInfo = QuerySecurityPackageInfoW;
    alias ApplyControlToken = ApplyControlTokenW;

    alias ENUMERATE_SECURITY_PACKAGES_FN = ENUMERATE_SECURITY_PACKAGES_FN_W;
    alias QUERY_CREDENTIALS_ATTRIBUTES_FN = QUERY_CREDENTIALS_ATTRIBUTES_FN_W;
    alias ACQUIRE_CREDENTIALS_HANDLE_FN = ACQUIRE_CREDENTIALS_HANDLE_FN_W;
    alias INITIALIZE_SECURITY_CONTEXT_FN = INITIALIZE_SECURITY_CONTEXT_FN_W;
    alias APPLY_CONTROL_TOKEN_FN = APPLY_CONTROL_TOKEN_FN_W;
    alias QUERY_CONTEXT_ATTRIBUTES_FN = QUERY_CONTEXT_ATTRIBUTES_FN_W;
    alias QUERY_SECURITY_PACKAGE_INFO_FN = QUERY_SECURITY_PACKAGE_INFO_FN_W;
    alias INIT_SECURITY_INTERFACE = INIT_SECURITY_INTERFACE_W;
}
else
{
    alias UNISP_NAME = UNISP_NAME_A;
    alias SecPkgInfo = SecPkgInfoA;
    alias PSecPkgInfo = PSecPkgInfoA;
    alias SecPkgCredentials_Names = SecPkgCredentials_NamesA;
    alias PSecPkgCredentials_Names = PSecPkgCredentials_NamesA;
    alias SecPkgContext_Authority = SecPkgContext_AuthorityA;
    alias PSecPkgContext_Authority = PSecPkgContext_AuthorityA;
    alias SecPkgContext_KeyInfo = SecPkgContext_KeyInfoA;
    alias PSecPkgContext_KeyInfo = PSecPkgContext_KeyInfoA;
    alias SecPkgContext_Names = SecPkgContext_NamesA;
    alias PSecPkgContext_Names = PSecPkgContext_NamesA;
    alias SecurityFunctionTable = SecurityFunctionTableA;
    alias PSecurityFunctionTable = PSecurityFunctionTableA;
    alias AcquireCredentialsHandle = AcquireCredentialsHandleA;
    alias EnumerateSecurityPackages = EnumerateSecurityPackagesA;
    alias InitializeSecurityContext = InitializeSecurityContextA;
    alias QueryContextAttributes = QueryContextAttributesA;
    alias QueryCredentialsAttributes = QueryCredentialsAttributesA;
    alias QuerySecurityPackageInfo = QuerySecurityPackageInfoA;
    alias ApplyControlToken = ApplyControlTokenA;

    alias ENUMERATE_SECURITY_PACKAGES_FN = ENUMERATE_SECURITY_PACKAGES_FN_A;
    alias QUERY_CREDENTIALS_ATTRIBUTES_FN = QUERY_CREDENTIALS_ATTRIBUTES_FN_A;
    alias ACQUIRE_CREDENTIALS_HANDLE_FN = ACQUIRE_CREDENTIALS_HANDLE_FN_A;
    alias INITIALIZE_SECURITY_CONTEXT_FN = INITIALIZE_SECURITY_CONTEXT_FN_A;
    alias APPLY_CONTROL_TOKEN_FN = APPLY_CONTROL_TOKEN_FN_A;
    alias QUERY_CONTEXT_ATTRIBUTES_FN = QUERY_CONTEXT_ATTRIBUTES_FN_A;
    alias QUERY_SECURITY_PACKAGE_INFO_FN = QUERY_SECURITY_PACKAGE_INFO_FN_A;
    alias INIT_SECURITY_INTERFACE = INIT_SECURITY_INTERFACE_A;
}
