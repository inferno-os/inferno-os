#
# Copyright © 1998 Vita Nuova Limited.  All rights reserved.
#

# Common control bytes
NUL:		con 16r00;
SOH:		con 16r01;
EOT:		con 16r04;
ENQ:		con 16r05;
BEL:		con 16r07;
BS:		con 16r08;
HT:		con 16r09;
LF:		con 16r0a;
VT:		con 16r0b;
FF:		con 16r0c;
CR:		con 16r0d;
SO:		con 16r0e;
SI:		con 16r0f;
DLE:		con 16r10;
CON:	con 16r11;
XON:		con 16r11;
REP:		con 16r12;
SEP:		con 16r13;
XOFF:	con 16r13;
COFF:	con 16r14;
NACK:	con 16r15;
SYN:		con 16r16;
CAN:		con 16r18;
SS2:		con 16r19;
SUB:		con 16r1a;
ESC:		con 16r1b;
SS3:		con 16r1d;
RS:		con 16r1e;
US:		con 16r1f;

SP:		con 16r20;
DEL:		con 16r7f;

# Minitel Protocol - some are duplicated (chapter 6)
ASCII:			con 16r31;
MIXED:			con 16r32;
ETEN:			con 16r41;
C0:				con 16r43;
SCROLLING:		con 16r43;
PROCEDURE:		con 16r44;
LOWERCASE:		con 16r45;
OFF:				con 16r60;
ON:				con 16r61;
TO:				con 16r62;
FROM:			con 16r63;
NOBROADCAST:	con 16r64;
BROADCAST:		con 16r65;
NONRETURN:		con 16r64;
RETURN:			con 16r65;
TRANSPARENCY:	con 16r66;
DISCONNECT:		con 16r67;
CONNECT:		con 16r68;
START:			con 16r69;
STOP:			con 16r6a;
KEYBOARDSTATUS:	con 16r72;
REPKEYBOARDSTATUS:	con 16r73;
FUNCTIONINGSTATUS:	con 16r72;
REPFUNCTIONINGSTATUS:	con 16r73;
EXCHANGERATESTATUS:	con 16r74;
REPEXCHANGERATESTATUS:	con 16r75;
PROTOCOLSTATUS:	con 16r76;
REPPROTOCOLSTATUS: 	con 16r77;
SETRAM1:			con 16r78;
SETRAM2:			con 16r79;
ENQROM:			con 16r7b;
COPY:			con 16r7c;
ASCII1:			con 16r7d;
MIXED1:			con 16r7d;
MIXED2:			con 16r7e;
RESET:			con 16r7f;

# Module send and receive codes (chapter 6)
TxScreen:			con 16r50;
TxKeyb:			con 16r51;
TxModem:		con 16r52;
TxSocket:			con 16r53;
RxScreen:			con 16r58;
RxKeyb:			con 16r59;
RxModem:		con 16r5a;
RxSocket:			con 16r5b;

# Internal Event.Eproto command constants
Cplay,			# for testing
Cconnect,			# e.s contains the address to dial
Cdisconnect,		# 
Crequestecp,		# ask server to start ecp
Creset,			# reset module
Cstartecp,			# start error correction
Cstopecp,			# stop error correction
Cproto,			# minitel protocol
Ccursor,			# update screen cursor
Cindicators,		# update row 0 indicators

# softmodem bug: Cscreenoff, Cscreenon
Cscreenoff,		# screen: ignore data
Cscreenon,		# screen: don't ignore data

Clast
	: con iota;

# Special keys - hardware returned byte
KupPC:		con	16r0203;		# pc emu
KdownPC:		con	16r0204;		# pc emu
Kup:		con	16rE012;
Kdown:	con	16rE013;
Kenter:	con	16r000a;
Kback:	con	16r0008;
Kesc:	con	16r001b;
KF1:		con	16rE041;
KF2:		con	16rE042;
KF3:		con	16rE043;
KF4:		con	16rE044;
KF13:	con	16rE04D;


