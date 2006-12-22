
#
# desktop/Pilot link protocol
#

Desklink: module {

	PATH1:	con "/dis/palm/desklink.dis";

	User: adt {
		userid:	int;
		viewerid:	int;
		lastsyncpc:	int;
		succsynctime:	int;
		lastsynctime:	int;
		username: string;
		password:	array of byte;
	};

	SysInfo: adt {
		romversion:	int;
		locale:	int;
		product:	string;
	};

	CardInfo: adt {
		cardno:	int;
		version:	int;
		creation:	int;
		romsize:	int;
		ramsize:	int;
		ramfree:	int;
		name:	string;
		maker:	string;
	};

	connect:	fn(srvfile: string): (Palmdb, string);
	hangup:	fn(): int;

	#
	# Desk Link Protocol functions (usually with the same names as in PalmOS)
	#

	ReadUserInfo:	fn(): ref User;
	WriteUserInfo:	fn(u: ref User, flags: int): int;

	# WriteUserInfo update flags
	UserInfoModUserID:	con 16r80;
	UserInfoModSyncPC:	con 16r40;
	UserInfoModSyncDate:	con 16r20;
	UserInfoModName:	con 16r10;
	UserInfoModViewerID:	con 16r08;

	ReadSysInfo:	fn(): ref SysInfo;
	ReadSysInfoVer:	fn(): (int, int, int);	# DLP 1.2

	GetSysDateTime:	fn(): int;
	SetSysDateTime:	fn(nil: int): int;

	ReadStorageInfo:	fn(cardno: int): (array of ref CardInfo, int, string);
	ReadDBCount:		fn(cardno: int): (int, int);

	ReadDBList:	fn(cardno: int, flags: int, start: int): (array of ref Palm->DBInfo, int, string);	# flags must contain DBListRAM and/or DBListROM
	FindDBInfo:	fn(cardno: int, start: int, name: string, dtype, creator: string): ref Palm->DBInfo;

	# list location and options
	DBListRAM:	con 16r80;
	DBListROM:	con 16r40;
	DBListMultiple:	con 16r20;	# ok to return multiple entries

	# OpenDB, CreateDB, ReadAppBlock, ... ResetSyncFlags, ReadOpenDBInfo, MoveCategory are functions in DB
	CloseDB_All:	fn(): int;
	DeleteDB:		fn(name: string): int;

	ResetSystem:	fn(): int;

	OpenConduit:	fn(): int;
	EndOfSync:	fn(status: int): int;

	# EndOfSync status parameter
	SyncNormal, SyncOutOfMemory, SyncCancelled, SyncError, SyncIncompatible:	con iota;

	AddSyncLogEntry:	fn(entry: string): int;

	#
	# Palmdb implementation
	#

	init:	fn(m: Palm): string;
};
