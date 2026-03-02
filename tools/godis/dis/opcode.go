// Package dis provides types and encoding/decoding for the Dis virtual machine
// bytecode format used by Inferno OS.
package dis

// Op is a Dis VM opcode.
type Op byte

// All 181 Dis VM opcodes, from include/isa.h.
const (
	INOP    Op = iota // 0
	IALT              // 1
	INBALT            // 2
	IGOTO             // 3
	ICALL             // 4
	IFRAME            // 5
	ISPAWN            // 6
	IRUNT             // 7
	ILOAD             // 8
	IMCALL            // 9
	IMSPAWN           // 10
	IMFRAME           // 11
	IRET              // 12
	IJMP              // 13
	ICASE             // 14
	IEXIT             // 15
	INEW              // 16
	INEWA             // 17
	INEWCB            // 18
	INEWCW            // 19
	INEWCF            // 20
	INEWCP            // 21
	INEWCM            // 22
	INEWCMP           // 23
	ISEND             // 24
	IRECV             // 25
	ICONSB            // 26
	ICONSW            // 27
	ICONSP            // 28
	ICONSF            // 29
	ICONSM            // 30
	ICONSMP           // 31
	IHEADB            // 32
	IHEADW            // 33
	IHEADP            // 34
	IHEADF            // 35
	IHEADM            // 36
	IHEADMP           // 37
	ITAIL             // 38
	ILEA              // 39
	IINDX             // 40
	IMOVP             // 41
	IMOVM             // 42
	IMOVMP            // 43
	IMOVB             // 44
	IMOVW             // 45
	IMOVF             // 46
	ICVTBW            // 47
	ICVTWB            // 48
	ICVTFW            // 49
	ICVTWF            // 50
	ICVTCA            // 51
	ICVTAC            // 52
	ICVTWC            // 53
	ICVTCW            // 54
	ICVTFC            // 55
	ICVTCF            // 56
	IADDB             // 57
	IADDW             // 58
	IADDF             // 59
	ISUBB             // 60
	ISUBW             // 61
	ISUBF             // 62
	IMULB             // 63
	IMULW             // 64
	IMULF             // 65
	IDIVB             // 66
	IDIVW             // 67
	IDIVF             // 68
	IMODW             // 69
	IMODB             // 70
	IANDB             // 71
	IANDW             // 72
	IORB              // 73
	IORW              // 74
	IXORB             // 75
	IXORW             // 76
	ISHLB             // 77
	ISHLW             // 78
	ISHRB             // 79
	ISHRW             // 80
	IINSC             // 81
	IINDC             // 82
	IADDC             // 83
	ILENC             // 84
	ILENA             // 85
	ILENL             // 86
	IBEQB             // 87
	IBNEB             // 88
	IBLTB             // 89
	IBLEB             // 90
	IBGTB             // 91
	IBGEB             // 92
	IBEQW             // 93
	IBNEW             // 94
	IBLTW             // 95
	IBLEW             // 96
	IBGTW             // 97
	IBGEW             // 98
	IBEQF             // 99
	IBNEF             // 100
	IBLTF             // 101
	IBLEF             // 102
	IBGTF             // 103
	IBGEF             // 104
	IBEQC             // 105
	IBNEC             // 106
	IBLTC             // 107
	IBLEC             // 108
	IBGTC             // 109
	IBGEC             // 110
	ISLICEA           // 111
	ISLICELA          // 112
	ISLICEC           // 113
	IINDW             // 114
	IINDF             // 115
	IINDB             // 116
	INEGF             // 117
	IMOVL             // 118
	IADDL             // 119
	ISUBL             // 120
	IDIVL             // 121
	IMODL             // 122
	IMULL             // 123
	IANDL             // 124
	IORL              // 125
	IXORL             // 126
	ISHLL             // 127
	ISHRL             // 128
	IBNEL             // 129
	IBLTL             // 130
	IBLEL             // 131
	IBGTL             // 132
	IBGEL             // 133
	IBEQL             // 134
	ICVTLF            // 135
	ICVTFL            // 136
	ICVTLW            // 137
	ICVTWL            // 138
	ICVTLC            // 139
	ICVTCL            // 140
	IHEADL            // 141
	ICONSL            // 142
	INEWCL            // 143
	ICASEC            // 144
	IINDL             // 145
	IMOVPC            // 146
	ITCMP             // 147
	IMNEWZ            // 148
	ICVTRF            // 149
	ICVTFR            // 150
	ICVTWS            // 151
	ICVTSW            // 152
	ILSRW             // 153
	ILSRL             // 154
	IECLR             // 155
	INEWZ             // 156
	INEWAZ            // 157
	IRAISE            // 158
	ICASEL            // 159
	IMULX             // 160
	IDIVX             // 161
	ICVTXX            // 162
	IMULX0            // 163
	IDIVX0            // 164
	ICVTXX0           // 165
	IMULX1            // 166
	IDIVX1            // 167
	ICVTXX1           // 168
	ICVTFX            // 169
	ICVTXF            // 170
	IEXPW             // 171
	IEXPL             // 172
	IEXPF             // 173
	ISELF             // 174

	MaxDis = ISELF + 1
)

// Magic numbers for .dis files.
const (
	XMAGIC = 819248 // Normal (unsigned) module
	SMAGIC = 923426 // Signed module
)

// Src/Dst operand addressing modes.
const (
	AMP  byte = 0x00 // Module pointer relative
	AFP  byte = 0x01 // Frame pointer relative
	AIMM byte = 0x02 // Immediate value
	AXXX byte = 0x03 // No operand
	AIND byte = 0x04 // Indirect (ORed with AMP or AFP)

	AMASK byte = 0x07 // Mask for src/dst mode
)

// Middle operand addressing modes (bits 6-7 of address byte).
const (
	AXNON byte = 0x00 // No middle operand
	AXIMM byte = 0x40 // Immediate
	AXINF byte = 0x80 // Frame pointer relative
	AXINM byte = 0xC0 // Module pointer relative

	ARM byte = 0xC0 // Mask for middle mode
)

// Data section item types.
const (
	DEFZ  byte = 0 // Zero fill
	DEFB  byte = 1 // Byte
	DEFW  byte = 2 // Word (4 bytes on disk, pointer-sized in memory)
	DEFS  byte = 3 // UTF string
	DEFF  byte = 4 // Real (float64, IEEE754)
	DEFA  byte = 5 // Array
	DIND  byte = 6 // Set array index
	DAPOP byte = 7 // Restore address register
	DEFL  byte = 8 // Big (int64)
)

// Runtime flags for module header.
const (
	MUSTCOMPILE = 1 << 0
	DONTCOMPILE = 1 << 1
	SHAREMP     = 1 << 2
	DYNMOD      = 1 << 3
	HASLDT0     = 1 << 4 // Obsolete
	HASEXCEPT   = 1 << 5
	HASLDT      = 1 << 6
)

// Frame register offsets (in units of IBY2WD).
const (
	REGLINK  = 0
	REGFRAME = 1
	REGMOD   = 2
	REGTYP   = 3
	REGRET   = 4
	NREG     = 5
)

// IBY2WD is the number of bytes per word (pointer size).
// On 64-bit Dis VMs (like Infernode on ARM64), this is 8.
const IBY2WD = 8

// MaxTemp is the byte offset where local variables start in a frame.
// NREG registers (40 bytes) + 3 scratch temps (24 bytes) = 64 bytes.
const MaxTemp = (NREG + 3) * IBY2WD // 64

// DMAX is the maximum count that fits in the low nibble of a data item header.
const DMAX = 1 << 4

// opNames maps opcodes to their string names.
var opNames = [MaxDis]string{
	INOP: "nop", IALT: "alt", INBALT: "nbalt", IGOTO: "goto",
	ICALL: "call", IFRAME: "frame", ISPAWN: "spawn", IRUNT: "runt",
	ILOAD: "load", IMCALL: "mcall", IMSPAWN: "mspawn", IMFRAME: "mframe",
	IRET: "ret", IJMP: "jmp", ICASE: "case", IEXIT: "exit",
	INEW: "new", INEWA: "newa", INEWCB: "newcb", INEWCW: "newcw",
	INEWCF: "newcf", INEWCP: "newcp", INEWCM: "newcm", INEWCMP: "newcmp",
	ISEND: "send", IRECV: "recv",
	ICONSB: "consb", ICONSW: "consw", ICONSP: "consp", ICONSF: "consf",
	ICONSM: "consm", ICONSMP: "consmp",
	IHEADB: "headb", IHEADW: "headw", IHEADP: "headp", IHEADF: "headf",
	IHEADM: "headm", IHEADMP: "headmp",
	ITAIL: "tail", ILEA: "lea", IINDX: "indx",
	IMOVP: "movp", IMOVM: "movm", IMOVMP: "movmp",
	IMOVB: "movb", IMOVW: "movw", IMOVF: "movf",
	ICVTBW: "cvtbw", ICVTWB: "cvtwb", ICVTFW: "cvtfw", ICVTWF: "cvtwf",
	ICVTCA: "cvtca", ICVTAC: "cvtac", ICVTWC: "cvtwc", ICVTCW: "cvtcw",
	ICVTFC: "cvtfc", ICVTCF: "cvtcf",
	IADDB: "addb", IADDW: "addw", IADDF: "addf",
	ISUBB: "subb", ISUBW: "subw", ISUBF: "subf",
	IMULB: "mulb", IMULW: "mulw", IMULF: "mulf",
	IDIVB: "divb", IDIVW: "divw", IDIVF: "divf",
	IMODW: "modw", IMODB: "modb",
	IANDB: "andb", IANDW: "andw", IORB: "orb", IORW: "orw",
	IXORB: "xorb", IXORW: "xorw",
	ISHLB: "shlb", ISHLW: "shlw", ISHRB: "shrb", ISHRW: "shrw",
	IINSC: "insc", IINDC: "indc", IADDC: "addc", ILENC: "lenc",
	ILENA: "lena", ILENL: "lenl",
	IBEQB: "beqb", IBNEB: "bneb", IBLTB: "bltb", IBLEB: "bleb",
	IBGTB: "bgtb", IBGEB: "bgeb",
	IBEQW: "beqw", IBNEW: "bnew", IBLTW: "bltw", IBLEW: "blew",
	IBGTW: "bgtw", IBGEW: "bgew",
	IBEQF: "beqf", IBNEF: "bnef", IBLTF: "bltf", IBLEF: "blef",
	IBGTF: "bgtf", IBGEF: "bgef",
	IBEQC: "beqc", IBNEC: "bnec", IBLTC: "bltc", IBLEC: "blec",
	IBGTC: "bgtc", IBGEC: "bgec",
	ISLICEA: "slicea", ISLICELA: "slicela", ISLICEC: "slicec",
	IINDW: "indw", IINDF: "indf", IINDB: "indb",
	INEGF: "negf",
	IMOVL: "movl", IADDL: "addl", ISUBL: "subl", IDIVL: "divl",
	IMODL: "modl", IMULL: "mull",
	IANDL: "andl", IORL: "orl", IXORL: "xorl",
	ISHLL: "shll", ISHRL: "shrl",
	IBNEL: "bnel", IBLTL: "bltl", IBLEL: "blel",
	IBGTL: "bgtl", IBGEL: "bgel", IBEQL: "beql",
	ICVTLF: "cvtlf", ICVTFL: "cvtfl", ICVTLW: "cvtlw", ICVTWL: "cvtwl",
	ICVTLC: "cvtlc", ICVTCL: "cvtcl",
	IHEADL: "headl", ICONSL: "consl", INEWCL: "newcl",
	ICASEC: "casec", IINDL: "indl",
	IMOVPC: "movpc", ITCMP: "tcmp", IMNEWZ: "mnewz",
	ICVTRF: "cvtrf", ICVTFR: "cvtfr", ICVTWS: "cvtws", ICVTSW: "cvtsw",
	ILSRW: "lsrw", ILSRL: "lsrl",
	IECLR: "eclr", INEWZ: "newz", INEWAZ: "newaz",
	IRAISE: "raise", ICASEL: "casel",
	IMULX: "mulx", IDIVX: "divx", ICVTXX: "cvtxx",
	IMULX0: "mulx0", IDIVX0: "divx0", ICVTXX0: "cvtxx0",
	IMULX1: "mulx1", IDIVX1: "divx1", ICVTXX1: "cvtxx1",
	ICVTFX: "cvtfx", ICVTXF: "cvtxf",
	IEXPW: "expw", IEXPL: "expl", IEXPF: "expf",
	ISELF: "self",
}

func (op Op) String() string {
	if int(op) < len(opNames) && opNames[op] != "" {
		return opNames[op]
	}
	return "???"
}

// IsBranch returns true if the opcode is a branch/jump that takes a PC target.
func (op Op) IsBranch() bool {
	switch op {
	case ICALL, IJMP, ISPAWN,
		IBEQW, IBNEW, IBLTW, IBLEW, IBGTW, IBGEW,
		IBEQB, IBNEB, IBLTB, IBLEB, IBGTB, IBGEB,
		IBEQF, IBNEF, IBLTF, IBLEF, IBGTF, IBGEF,
		IBEQC, IBNEC, IBLTC, IBLEC, IBGTC, IBGEC,
		IBEQL, IBNEL, IBLTL, IBLEL, IBGTL, IBGEL:
		return true
	}
	return false
}
