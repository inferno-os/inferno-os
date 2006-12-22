
PPPClient:	module {
	PATH:	con "/dis/ip/ppp/pppclient.dis";

	PPPInfo: adt {
		ipaddr:			string;
		ipmask:			string;
		peeraddr:		string;
		maxmtu:			string;
		username:		string;
		password:		string;
	};
	
	connect:	fn( mi: ref Modem->ModemInfo, number: string, 
					scriptinfo: ref Script->ScriptInfo, 
					pppinfo: ref PPPInfo, logchan: chan of int);
	reset:		fn();

	lasterror :string;

	s_Error: con -666;
	s_Initialized,			# Module Initialized
	s_StartModem,			# Modem Initialized
	s_SuccessModem,			# Modem Connected
	s_StartScript,			# Script Executing
	s_SuccessScript,		# Script Executed Sucessfully
	s_StartPPP,				# PPP Started
	s_LoginPPP,				# CHAP/PAP Authentication
	s_SuccessPPP,			# PPP Session Established
	s_Done: con iota;		# PPPClient Cleaningup & Exiting
};
