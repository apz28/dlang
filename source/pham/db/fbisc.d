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

module pham.db.fbisc;

nothrow @safe:

enum FbIsc
{
	// Protocol Types (accept_type)
    ptype_rpc = 2,
	ptype_batch_send = 3, // Batch sends, no asynchrony
	ptype_out_of_band = 4, // Batch sends w/ out of band notification
	ptype_lazy_send = 5, // Deferred packets delivery
	ptype_compress_flag = 0x100, // Set on max type - start on protocol_version13

    // Connection Version
	//connect_version2 = 2, // Obsolete
	connect_version3 = 3,
    connect_version = connect_version3,

    connect_generic_achitecture_client = 1,

	// Protocol Version
	protocol_flag = 0x8000,
	protocol_mask = ~protocol_flag,
	protocol_version10 = 10, // Obsolete
	protocol_version11 = protocol_flag | 11, // Obsolete
	protocol_version12 = protocol_flag | 12, // Obsolete
	protocol_version13 = protocol_flag | 13,
    protocol_version = protocol_version13,

	CNCT_user = 1,
	//CNCT_passwd = 2,
	CNCT_host = 4,
	CNCT_group = 5,
	CNCT_user_verification = 6,
	CNCT_specific_data = 7,
	CNCT_plugin_name = 8,
	CNCT_login = 9,
	CNCT_plugin_list = 10,
	CNCT_client_crypt = 11,

    connect_crypt_disabled = 0,
    connect_crypt_enabled = 1,
    connect_crypt_required = 2,

	isc_info_end = 1,
	isc_info_truncated = 2,
	isc_info_error = 3,
	isc_info_data_not_ready = 4,
	isc_info_length = 126,
	isc_info_flag_end = 127,

	isc_info_db_id = 4,
	isc_info_reads = 5,
	isc_info_writes = 6,
	isc_info_fetches = 7,
	isc_info_marks = 8,
	isc_info_implementation = 11,
	isc_info_version = 12,
	isc_info_base_level = 13,
	isc_info_page_size = 14,
	isc_info_num_buffers = 15,
	isc_info_limbo = 16,
	isc_info_current_memory = 17,
	isc_info_max_memory = 18,
	isc_info_window_turns = 19,
	isc_info_license = 20,
	isc_info_allocation = 21,
	isc_info_attachment_id = 22,
	isc_info_read_seq_count = 23,
	isc_info_read_idx_count = 24,
	isc_info_insert_count = 25,
	isc_info_update_count = 26,
	isc_info_delete_count = 27,
	isc_info_backout_count = 28,
	isc_info_purge_count = 29,
	isc_info_expunge_count = 30,
	isc_info_sweep_interval = 31,
	isc_info_ods_version = 32,
	isc_info_ods_minor_version = 33,
	isc_info_no_reserve = 34,
	isc_info_logfile = 35,
	isc_info_cur_logfile_name = 36,
	isc_info_cur_log_part_offset = 37,
	isc_info_num_wal_buffers = 38,
	isc_info_wal_buffer_size = 39,
	isc_info_wal_ckpt_length = 40,
	isc_info_wal_cur_ckpt_interval = 41,
	isc_info_wal_prv_ckpt_fname = 42,
	isc_info_wal_prv_ckpt_poffset = 43,
	isc_info_wal_recv_ckpt_fname = 44,
	isc_info_wal_recv_ckpt_poffset = 45,
	isc_info_wal_grpc_wait_usecs = 47,
	isc_info_wal_num_io = 48,
	isc_info_wal_avg_io_size = 49,
	isc_info_wal_num_commits = 50,
	isc_info_wal_avg_grpc_size = 51,
	isc_info_forced_writes = 52,
	isc_info_user_names = 53,
	isc_info_page_errors = 54,
	isc_info_record_errors = 55,
	isc_info_bpage_errors = 56,
	isc_info_dpage_errors = 57,
	isc_info_ipage_errors = 58,
	isc_info_ppage_errors = 59,
	isc_info_tpage_errors = 60,
	isc_info_set_page_buffers = 61,
	isc_info_db_sql_dialect = 62,
	isc_info_db_read_only = 63,
	isc_info_db_size_in_pages = 64,
	isc_info_att_charset = 101,
	isc_info_db_class = 102,
	isc_info_firebird_version = 103,
	isc_info_oldest_transaction = 104,
	isc_info_oldest_active = 105,
	isc_info_oldest_snapshot = 106,
	isc_info_next_transaction = 107,
	isc_info_db_provider = 108,
	isc_info_active_transactions = 109,
	isc_info_active_tran_count = 110,
	isc_info_creation_date = 111,
	isc_info_db_file_size = 112,

	// BLR Codes
	blr_version5 = 5,
	blr_version = blr_version5,
	blr_begin = 2,
	blr_message = 4,
	blr_eoc = 76,
	blr_end = 255,

	//blr_domain_name = 18,
	//blr_domain_name2 = 19,
	//blr_not_nullable = 20,
	//blr_column_name = 21,
	//blr_column_name2 = 22,

	// Server Class
	isc_info_db_class_classic_access = 13,
	isc_info_db_class_server_access = 14,

	// isc_info_sql_records items
	isc_info_req_select_count = 13,
	isc_info_req_insert_count = 14,
	isc_info_req_update_count = 15,
	isc_info_req_delete_count = 16,

	isc_info_svc_svr_db_info = 50,
	isc_info_svc_get_license = 51,
	isc_info_svc_get_license_mask = 52,
	isc_info_svc_get_config = 53,
	isc_info_svc_version = 54,
	isc_info_svc_server_version = 55,
	isc_info_svc_implementation = 56,
	isc_info_svc_capabilities = 57,
	isc_info_svc_user_dbpath = 58,
	isc_info_svc_get_env = 59,
	isc_info_svc_get_env_lock = 60,
	isc_info_svc_get_env_msg = 61,
	isc_info_svc_line = 62,
	isc_info_svc_to_eof = 63,
	isc_info_svc_timeout = 64,
	isc_info_svc_get_licensed_users = 65,
	isc_info_svc_limbo_trans = 66,
	isc_info_svc_running = 67,
	isc_info_svc_get_users = 68,

	// Transaction operators
	op_transaction = 29,
	op_commit = 30,
	op_rollback = 31,
	op_prepare = 32,
	op_reconnect = 33,
	op_info_transaction	= 42,
	op_commit_retaining = 50,
	op_rollback_retaining = 86,

    // Transaction items
	isc_tpb_version1 = 1,
	isc_tpb_version3 = 3,
    isc_tpb_version = isc_tpb_version3,
	isc_tpb_consistency = 1,
	isc_tpb_concurrency = 2,
	isc_tpb_shared = 3,
	isc_tpb_protected = 4,
	isc_tpb_exclusive = 5,
	isc_tpb_wait = 6,
	isc_tpb_nowait = 7,
	isc_tpb_read = 8,
	isc_tpb_write = 9,
	isc_tpb_lock_read = 10,
	isc_tpb_lock_write = 11,
	isc_tpb_verb_time = 12,
	isc_tpb_commit_time = 13,
	isc_tpb_ignore_limbo = 14,
	isc_tpb_read_committed = 15,
	isc_tpb_autocommit = 16,
	isc_tpb_rec_version = 17,
	isc_tpb_no_rec_version = 18,
	isc_tpb_restart_requests = 19,
	isc_tpb_no_auto_undo = 20,
	isc_tpb_lock_timeout = 21,

	// Transaction information items
	isc_info_tra_id = 4,
	isc_info_tra_oldest_interesting = 5,
	isc_info_tra_oldest_snapshot = 6,
	isc_info_tra_oldest_active = 7,
	isc_info_tra_isolation = 8,
	isc_info_tra_access = 9,
	isc_info_tra_lock_timeout = 10,

	// Service Parameter Block parameter
	isc_spb_version1 = 1,
    isc_spb_version2 = 2,
	isc_spb_version = isc_spb_version2,
	isc_spb_user_name = 28, // isc_dpb_user_name
	isc_spb_sys_user_name = 19, // isc_dpb_sys_user_name
	isc_spb_sys_user_name_enc = 31, // isc_dpb_sys_user_name_enc
	isc_spb_password = 29, // isc_dpb_password
	isc_spb_password_enc = 30, // isc_dpb_password_enc
	isc_spb_command_line = 105,
	isc_spb_dbname = 106,
	isc_spb_verbose = 107,
	isc_spb_options = 108,
	isc_spb_address_path = 109,
	isc_spb_process_id = 110,
	isc_spb_trusted_auth = 111,
	isc_spb_process_name = 112,
	isc_spb_trusted_role = 113,
	isc_spb_connect_timeout = 57, // isc_dpb_connect_timeout
	isc_spb_dummy_packet_interval = 58, // isc_dpb_dummy_packet_interval
	isc_spb_sql_role_name = 60, // isc_dpb_sql_role_name

	// Database Parameter Block Types
	isc_dpb_version1 = 1,
	isc_dpb_version2 = 2,
    isc_dpb_version = isc_dpb_version1,
	isc_dpb_page_size = 4,
	isc_dpb_num_buffers = 5,
	isc_dpb_no_garbage_collect = 16,
	isc_dpb_force_write = 24,
	isc_dpb_user_name = 28,
	isc_dpb_password = 29,
	isc_dpb_password_enc = 30,
	isc_dpb_lc_ctype = 48,
	isc_dpb_overwrite = 54,
	isc_dpb_connect_timeout = 57,
	isc_dpb_dummy_packet_interval = 58,
	isc_dpb_sql_role_name = 60,
	isc_dpb_set_page_buffers = 61,
	isc_dpb_sql_dialect = 63,
	isc_dpb_set_db_charset = 68,
	isc_dpb_process_id = 71,
	isc_dpb_no_db_triggers = 72,
	isc_dpb_trusted_auth = 73,
	isc_dpb_process_name = 74,
	isc_dpb_org_filename = 76,
	isc_dpb_utf8_filename = 77,
	isc_dpb_client_version		 = 80,
	isc_dpb_specific_auth_data = 84,

	// backup
	isc_spb_bkp_file = 5,
	isc_spb_bkp_factor = 6,
	isc_spb_bkp_length = 7,
	isc_spb_bkp_ignore_checksums = 0x01,
	isc_spb_bkp_ignore_limbo = 0x02,
	isc_spb_bkp_metadata_only = 0x04,
	isc_spb_bkp_no_garbage_collect = 0x08,
	isc_spb_bkp_old_descriptions = 0x10,
	isc_spb_bkp_non_transportable = 0x20,
	isc_spb_bkp_convert = 0x40,
	isc_spb_bkp_expand = 0x8,

	// restore
	isc_spb_res_buffers = 9,
	isc_spb_res_page_size = 10,
	isc_spb_res_length = 11,
	isc_spb_res_access_mode = 12,
	isc_spb_res_deactivate_idx = 0x0100,
	isc_spb_res_no_shadow = 0x0200,
	isc_spb_res_no_validity = 0x0400,
	isc_spb_res_one_at_a_time = 0x0800,
	isc_spb_res_replace = 0x1000,
	isc_spb_res_create = 0x2000,
	isc_spb_res_use_all_space = 0x4000,

	// trace
	isc_spb_trc_id = 1,
	isc_spb_trc_name = 2,
	isc_spb_trc_cfg = 3,

	// isc_info_svc_svr_db_info params
	isc_spb_num_att = 5,
	isc_spb_num_db = 6,

	// isc_info_svc_db_stats params
	isc_spb_sts_data_pages = 0x01,
	isc_spb_sts_db_log = 0x02,
	isc_spb_sts_hdr_pages = 0x04,
	isc_spb_sts_idx_pages = 0x08,
	isc_spb_sts_sys_relations = 0x10,
	isc_spb_sts_record_versions = 0x20,
	isc_spb_sts_table = 0x40,
	isc_spb_sts_nocreation = 0x80,

	// isc_action_svc_repair params
	isc_spb_rpr_validate_db = 0x01,
	isc_spb_rpr_sweep_db = 0x02,
	isc_spb_rpr_mend_db = 0x04,
	isc_spb_rpr_list_limbo_trans = 0x08,
	isc_spb_rpr_check_db = 0x10,
	isc_spb_rpr_ignore_checksum = 0x20,
	isc_spb_rpr_kill_shadows = 0x40,
	isc_spb_rpr_full = 0x80,

	// Service action items
	isc_action_svc_backup = 1,
	isc_action_svc_restore = 2,
	isc_action_svc_repair = 3,
	isc_action_svc_add_user = 4,
	isc_action_svc_delete_user = 5,
	isc_action_svc_modify_user = 6,
	isc_action_svc_display_user = 7,
	isc_action_svc_properties = 8,
	isc_action_svc_add_license = 9,
	isc_action_svc_remove_license = 10,
	isc_action_svc_db_stats = 11,
	isc_action_svc_get_ib_log = 12,
	isc_action_svc_get_fb_log = 12,
	isc_action_svc_nbak = 20,
	isc_action_svc_nrest = 21,
	isc_action_svc_trace_start = 22,
	isc_action_svc_trace_stop = 23,
	isc_action_svc_trace_suspend = 24,
	isc_action_svc_trace_resume = 25,
	isc_action_svc_trace_list = 26,
	isc_action_svc_set_mapping = 27,
	isc_action_svc_drop_mapping = 28,
	isc_action_svc_display_user_adm = 29,
	isc_action_svc_last = 30,

	DSQL_close = 1,
	DSQL_drop = 2,

	// SQL information items
	isc_info_sql_select = 4,
	isc_info_sql_bind = 5,
	isc_info_sql_num_variables = 6,
	isc_info_sql_describe_vars = 7,
	isc_info_sql_describe_end = 8,
	isc_info_sql_sqlda_seq = 9,
	isc_info_sql_message_seq = 10,
	isc_info_sql_type = 11,
	isc_info_sql_sub_type = 12,
	isc_info_sql_scale = 13,
	isc_info_sql_length = 14,
	isc_info_sql_null_ind = 15,
	isc_info_sql_field = 16,
	isc_info_sql_relation = 17,
	isc_info_sql_owner = 18,
	isc_info_sql_alias = 19,
	isc_info_sql_sqlda_start = 20,
	isc_info_sql_stmt_type = 21,
	isc_info_sql_get_plan = 22,
	isc_info_sql_records = 23,
	isc_info_sql_batch_fetch = 24,
	isc_info_sql_explain_plan = 26,

	isc_info_sql_stmt_select = 1,
	isc_info_sql_stmt_insert = 2,
	isc_info_sql_stmt_update = 3,
	isc_info_sql_stmt_delete = 4,
	isc_info_sql_stmt_ddl = 5,
	isc_info_sql_stmt_get_segment = 6,
	isc_info_sql_stmt_put_segment = 7,
	isc_info_sql_stmt_exec_procedure = 8,
	isc_info_sql_stmt_start_trans = 9,
	isc_info_sql_stmt_commit = 10,
	isc_info_sql_stmt_rollback = 11,
	isc_info_sql_stmt_select_for_upd = 12,
	isc_info_sql_stmt_set_generator = 13,
	isc_info_sql_stmt_savepoint = 14,

	// Array Description
	isc_sdl_version1 = 1,
	isc_sdl_eoc = 255,
	isc_sdl_relation = 2,
	isc_sdl_rid = 3,
	isc_sdl_field = 4,
	isc_sdl_fid = 5,
	isc_sdl_struct = 6,
	isc_sdl_variable = 7,
	isc_sdl_scalar = 8,
	isc_sdl_tiny_integer = 9,
	isc_sdl_short_integer = 10,
	isc_sdl_long_integer = 11,
	isc_sdl_literal = 12,
	isc_sdl_add = 13,
	isc_sdl_subtract = 14,
	isc_sdl_multiply = 15,
	isc_sdl_divide = 16,
	isc_sdl_negate = 17,
	isc_sdl_eql = 18,
	isc_sdl_neq = 19,
	isc_sdl_gtr = 20,
	isc_sdl_geq = 21,
	isc_sdl_lss = 22,
	isc_sdl_leq = 23,
	isc_sdl_and = 24,
	isc_sdl_or = 25,
	isc_sdl_not = 26,
	isc_sdl_while = 27,
	isc_sdl_assignment = 28,
	isc_sdl_label = 29,
	isc_sdl_leave = 30,
	isc_sdl_begin = 31,
	isc_sdl_end = 32,
	isc_sdl_do3 = 33,
	isc_sdl_do2 = 34,
	isc_sdl_do1 = 35,
	isc_sdl_element = 36,

	isc_arg_end = 0,
	isc_arg_gds = 1,
	isc_arg_string = 2,
	isc_arg_cstring = 3,
	isc_arg_number = 4,
	isc_arg_interpreted = 5,
	isc_arg_vms = 6,
	isc_arg_unix = 7,
	isc_arg_domain = 8,
	isc_arg_dos = 9,
	isc_arg_mpexl = 10,
	isc_arg_mpexl_ipc = 11,
	isc_arg_next_mach = 15,
	isc_arg_netware = 16,
	isc_arg_win32 = 17,
	isc_arg_warning = 18,
	isc_arg_sql_state = 19,

	op_connect = 1,
	op_exit = 2,
	op_accept = 3,
	op_reject = 4,
	op_protocrol = 5,
	op_disconnect = 6,
	op_response = 9,
	op_attach = 19,
	op_create = 20,
	op_detach = 21,

	// Blob	operations
	op_create_blob = 34,
	op_open_blob = 35,
	op_get_segment = 36,
	op_put_segment = 37,
	op_cancel_blob = 38,
	op_close_blob = 39,
	op_info_blob = 43,
	op_batch_segments = 44, // For putting all blob
	op_create_blob2 = 57,

	// Blob information items for op_info_blob
    isc_info_blob_num_segments = 4,
    isc_info_blob_max_segment = 5,
    isc_info_blob_total_length = 6,
    isc_info_blob_type = 7,

	// Array operations
	op_get_slice = 58,
	op_put_slice = 59,
	op_slice = 60, // Successful response to public const int op_get_slice

	op_info_database = 40,
	op_que_events = 48,
	op_cancel_events = 49,
	op_event = 52,
	op_connect_request = 53,
	op_aux_connect = 53,
	op_allocate_statement = 62,
	op_execute = 63,
	op_execute_immediate = 64,
	op_fetch = 65,
	op_fetch_response = 66,
	op_free_statement = 67,
	op_prepare_statement = 68,
	op_info_sql = 70,
	op_dummy = 71,
	op_execute2 = 76,
	op_sql_response = 78,
	op_drop_database = 81,
	op_service_attach = 82,
	op_service_detach = 83,
	op_service_info = 84,
	op_service_start = 85,
	op_update_account_info = 87, // FB3
	op_authenticate_user = 88, // FB3
	op_partial = 89, // FB3
	op_trusted_auth = 90, // FB3
	op_cont_auth = 92, // FB3
	op_ping = 93, // FB3
	op_accept_data = 94, // FB3
	op_abort_aux_connection = 95, // FB3
	op_crypt = 96, // FB3
	op_crypt_key_callback = 97, // FB3
	op_cond_accept = 98, // FB3

	// Cancel operators
	op_cancel = 91, // FB3

	// Cancel types
	fb_cancel_disable = 1,
	fb_cancel_enable = 2,
	fb_cancel_raise = 3,
	fb_cancel_abort = 4,

	GMT_ZONE = 65_535,
	defaultDialect = 3,
}

enum FbIscSize
{
    iscStatusLength = 20,
	iscTimeSecondsPrecision = 10_000,

    /**
     * Sizes in bytes
     */
	blobSizeInfoBufferLength = 100,
    executePlanBufferLength = 32_000,
	parameterBufferLength = 16_000,
	prepareInfoBufferLength = 32_000,
	rowsEffectedBufferLength = 100,
	statementTypeBufferLength = 100,
}

enum FbIscResultCode
{
	isc_net_connect_err = 335544722,
    isc_dsql_sqlda_err = 335544583,
    isc_except = 335544517,
    isc_except2 = 335544848,
    isc_net_read_err = 335544726,
    isc_net_write_err = 335544727,
    isc_stack_trace = 335544842,
	isc_auth_data = 335545069,
	isc_wirecrypt_incompatible = 335545064,
}

enum FbIscText
{
	isc_info_db_class_classic_text = "CLASSIC SERVER",
	isc_info_db_class_server_text = "SUPER SERVER",

	isc_filter_arc4_name = "Arc4",
	isc_filter_zip_name = "zlib"
}

// BLR Type Codes
enum FbBlrType
{
	blr_short = 7,
	blr_long = 8,
	blr_quad = 9,
	blr_float = 10,
	blr_d_float = 11,
	blr_sql_date = 12,
	blr_sql_time = 13,
	blr_text = 14,
	blr_text2 = 15,
	blr_int64 = 16,
	blr_blob2 = 17,
	blr_bool = 23,
	blr_dec64 = 24,
	blr_dec128 = 25,
	blr_int128 = 26,
	blr_double = 27,
	blr_sql_time_tz	= 28,
	blr_timestamp_tz = 29,
	blr_ex_time_tz = 30,
	blr_ex_timestamp_tz = 31,
	blr_timestamp = 35,
	blr_varying = 37,
	blr_varying2 = 38,
	blr_cstring = 40,
	blr_cstring2 = 41,
	blr_blob_id = 45,
	blr_blob = 261,
}

enum FbIscType
{
	SQL_VARYING = 448, // varchar
	SQL_TEXT = 452, // fixed length char[]
	SQL_DOUBLE = 480, // 64 bits
	SQL_FLOAT = 482, // 32 bits
	SQL_LONG = 496, // 32 bits
	SQL_SHORT = 500, // 16 bits
	SQL_TIMESTAMP = 510,
	SQL_BLOB = 520, // unlimit ubyte[] & char[]=BLOB SUB_TYPE TEXT
	SQL_D_FLOAT = 530,
	SQL_ARRAY = 540,
	SQL_QUAD = 550, // similar to SQL_INT64
	SQL_TIME = 560,
	SQL_DATE = 570,
	SQL_INT64 = 580,
	SQL_INT128 = 32752,
	SQL_TIMESTAMP_TZ = 32754,
	SQL_TIMESTAMP_TZ_EX = 32748,
	SQL_TIME_TZ = 32756,
	SQL_TIME_TZ_EX = 32750,
	//SQL_DEC_FIXED = 32758,
	SQL_DEC64 = 32760,
	SQL_DEC128 = 32762,
	SQL_BOOLEAN = 32764,
	SQL_NULL = 32766
}
