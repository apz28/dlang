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

module pham.db.db_message;

@safe:

enum DbErrorCode : int
{
    connect = 1,
    read = 2,
    write = 3,
    parse = 4,
}

struct DbMessage
{
@safe:

    static immutable eErrorCode = "Error code: %d";
    static immutable eErrorDetail = "Detail";
    static immutable eErrorHint = "Hint";
    static immutable eErrorSqlState = "SQL state: %s";

    static immutable eNoReadingData = "No data for reading %d bytes";
    static immutable eNoReadingDataRemaining = "Not enough data for reading %d bytes; remainding %d bytes";
    static immutable eNoSendingData = "Unable to send data for %d bytes";

    static immutable eConnect = "Unable to connect to '%s'\n%s";
    static immutable eConnectTimeoutRaw = "Connection timeout";
    static immutable eReadData = "Unable to receive data from '%s'\n%s";
    static immutable eReadInvalidData = "Unable to convert data from '%s' to type '%s'";
    static immutable eWriteData = "Unable to send data to '%s'\n%s";
    static immutable eUnexpectReadOperation = "Unexpected received operation code %d; expecting %d";
    static immutable eUnexpectReadValue = "Unexpected %s for datatype %s with length %d; expecting %d";
    static immutable eUnhandleIntOperation = "Unable to process operation %d for %s";
    static immutable eUnhandleStrOperation = "Unable to process operation %s for %s";
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
    static immutable eInvalidConnectionActiveReader = "Connection-Reader is still active. Must be closed first";
    static immutable eInvalidConnectionAuthClientData = "Unable to initialize authenticated type: %s.\n%s";
    static immutable eInvalidConnectionAuthServerData = "Malform/Invalid authenticated server data for authenticated type: %s.\n%s";
    static immutable eInvalidConnectionAuthUnsupportedName = "Unsupported authenticated type: %s";
    static immutable eInvalidConnectionAuthVerificationFailed = "Unable to verify authenticated server signature for type: %s";
    static immutable eInvalidConnectionHostName = "Unable to resolve host '%s'";
    static immutable eInvalidConnectionFatal = "Cannot perform %s when connection to '%s' is in fatal state";
    static immutable eInvalidConnectionInactive = "Cannot perform %s when connection to '%s' is closed";
    static immutable eInvalidConnectionStatus = "Connection status '%s' is invalid";
    //static immutable eInvalidConnectionString = "Connection-String is invalid";
    static immutable eInvalidConnectionRequiredEncryption = "Wire encryption to '%s' is required but not support";
    static immutable eInvalidConnectionPoolMaxUsed = "All connections are in used: %d / %d"; // Second %d is the max value
    static immutable eInvalidConnectionStringName = "Invalid %s connection element '%s'"; // First %s is scheme name
    static immutable eInvalidConnectionStringNameDup = "Duplicate %s connection element '%s'"; // First %s is scheme name
    static immutable eInvalidConnectionStringValue = "Invalid %s element %s value '%s'"; // First %s is scheme name

    static immutable eInvalidSQLDAColumnIndex = "Invalid/Unsupported SQLDA type %d. ColumnIndex, %d, is invalid";
    static immutable eInvalidSQLDAIndex = "Invalid/Unsupported SQLDA type %d. Index is not set";
    static immutable eInvalidSQLDANotEnoughData = "Invalid/Unsupported SQLDA type %d. Not enough data for reading %d bytes";
    static immutable eInvalidSQLDAType = "Invalid/Unsupported SQLDA type %d";
    
    static immutable eMalformSQLStatementConversion = "Malformed '%s' statement. Unable to convert '%s' to '%s'";
    static immutable eMalformSQLStatementEos = "Malformed '%s' statement. Not enough data for parsing";
    static immutable eMalformSQLStatementKeyword = "Malformed '%s' statement. Expected keyword '%s' but '%s' found";
    static immutable eMalformSQLStatementOther = "Malformed '%s' statement. Expected '%s' but '%s' found";
    static immutable eMalformSQLStatementReKeyword = "Malformed '%s' statement. Recurrence keyword '%s'";

    static immutable eCompletedTransaction = "Cannot perform %s when transaction was already completed";
    static immutable eInvalidTransactionState = "Cannot perform %s when transaction state is %s; expecting %s";
    static immutable eInvalidTransactionSavePoint = "Cannot perform %s; invalid transaction savepoint %s";

    static immutable eInvalidName = "Name '%s' not found for '%s'";
    static immutable eInvalidSchemeName = "Database scheme name '%s' not found";
}

string addMessageLine(ref string messageLines, string messageLine) nothrow pure
{
    import std.ascii : newline;
    
    if (messageLines.length == 0)
        messageLines = messageLine;
    else
        messageLines ~= newline ~ messageLine;
    return messageLines;
}

package(pham.db) string fmtMessage(Args...)(string fmt, Args args) nothrow
{
    import std.format : format;
    
    scope (failure) assert(0, "Assume nothrow failed");
    
    return format(fmt, args);
}
