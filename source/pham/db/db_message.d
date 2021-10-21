/*
 *
 * License: $(HTTP www.boost.org/LICENSE_1_0.txt, Boost License 1.0).
 * Authors: An Pham
 *
 * Copyright An Pham 2017 - xxxx.
 * Distributed under the Boost Software License, Version 1.0.
 * (See accompanying file LICENSE.txt or copy at http://www.boost.org/LICENSE_1_0.txt)
 *
 */

module pham.db.message;

@safe:

enum DbErrorCode : byte
{
    connect = 1,
    read = 2,
    write = 3
}

struct DbMessage
{
@safe:

    static immutable eErrorCode = "Error code: %d";
    static immutable eErrorDetail = "Detail";
    static immutable eErrorHint = "Hint";

    static immutable eNotEnoughData = "Not enough data for reading %d bytes; remainding %d bytes";
    static immutable eReadData = "Unable to receive data from '%s'\n%s";
    static immutable eWriteData = "Unable to send data to '%s'\n%s";
    static immutable eUnexpectReadOperation = "Unexpected received operation code %d; expecting %d";
    static immutable eUnexpectReadValue = "Unexpected %s for datatype %s with length %d; expecting %d";
    static immutable eUnhandleOperation = "Unable to process operation %d";
    static immutable eUnsupportDataType = "Unsupport %s for datatype %s";

    static immutable eInvalidCommandText = "Command text is not set/empty";
    static immutable eInvalidCommandConnection = "Cannot perform %s when connection is not set or not active";
    static immutable eInvalidCommandConnectionDif = "Command-connection is not the same as transaction-connection";
    static immutable eInvalidCommandActive = "Cannot perform %s when command is open";
    static immutable eInvalidCommandActiveReader = "Command-Reader is still active. Must be closed first";
    static immutable eInvalidCommandInactive = "Cannot perform %s when command is closed";
    static immutable eInvalidCommandSuspended = "Command is suspended";
    static immutable eInvalidCommandUnfit = "Command is unfit for this function call %s";

    static immutable eInvalidConnectionActive = "Cannot perform %s when connection '%s.%s' is opened";
    static immutable eInvalidConnectionAuthServerData = "Malform/Invalid authenticated server data for authenticated type: %s.\n%s";
    static immutable eInvalidConnectionAuthUnsupportedName = "Unsupported authenticated type: %s";
    static immutable eInvalidConnectionAuthVerificationFailed = "Unable to verify server signature for type: %s";
    static immutable eInvalidConnectionHostName = "Unable to resolve host '%s'";
    static immutable eInvalidConnectionInactive = "Cannot perform %s when connection to '%s' is closed";
    static immutable eInvalidConnectionName = "Connection element name '%s' is invalid";
    static immutable eInvalidConnectionStatus = "Connection status '%s' is invalid";
    static immutable eInvalidConnectionRequiredEncryption = "Wire encryption to '%s' is required but not support";
    static immutable eInvalidConnectionPoolMaxUsed = "All connections are used: %d / %d";

    static immutable eInvalidSQLDAFieldIndex = "Invalid/Unsupported SQLDA type %d. FieldIndex, %d, is invalid";
    static immutable eInvalidSQLDAIndex = "Invalid/Unsupported SQLDA type %d. Index is not set";
    static immutable eInvalidSQLDANotEnoughData = "Invalid/Unsupported SQLDA type %d. Not enough data for reading %d bytes";
    static immutable eInvalidSQLDAType = "Invalid/Unsupported SQLDA type %d";

    static immutable eCompletedTransaction = "Cannot perform %s when transaction is already completed";
    static immutable eInvalidTransactionState = "Cannot perform %s when transaction state is %s; expecting %s";

    static immutable eInvalidName = "Name '%s' is not found for '%s'";
    static immutable eInvalidSchemeName = "Database scheme name '%s' is not found";
}

string fmtMessage(Args...)(string fmt, Args args)
{
    import std.format : format;
    return format(fmt, args);
}
