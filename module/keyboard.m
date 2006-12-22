Keyboard : module {
	# Inferno Generic Scan Conversions
	# this file needs to be kept in sync with include/keyboard.h 

	No: con -1;
	Esc: con 16r1b;

	Spec: con 16rE000;		# Special Function Keys - mapped to Unicode reserved range
	Shift: con Spec|16r00;	# Shifter (Held) Keys 
	View: con Spec|16r10;	# View Keys
	PF: con	Spec|16r20;	# num pad
	KF: con	Spec|16r40;	# function keys

	LShift: con Shift|0;
	RShift: con Shift|1;
	LCtrl: con Shift|2;
	RCtrl: con Shift|3;
	Caps: con Shift|4;
	Num: con Shift|5;
	Meta: con Shift|6;
	LAlt: con Shift|7;
	RAlt: con Shift|8;
	NShifts: con 9;			# total number of shift keys

	Home: con View|0;
	End: con View|1;
	Up: con View|2;
	Down: con View|3;
	Left: con View|4;
	Right: con View|5;
	Pgup: con View|6;
	Pgdown: con View|7;
	BackTab: con View|8;

	Scroll: con Spec|16r62;
	Ins: con Spec|16r63;
	Del: con Spec|16r64;
	Print: con Spec|16r65;
	Pause: con Spec|16r66;
	Middle: con Spec|16r67;
	Break: con Spec|16r66;
	SysRq: con Spec|16r69;
	PwrOn: con Spec|16r6c;
	PwrOff: con Spec|16r6d;
	PwrLow: con Spec|16r6e;
	Latin: con Spec|16r6f;

	APP: con Spec|16r200;	# for application use (ALT keys)
};

