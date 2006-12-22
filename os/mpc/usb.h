/*
 * USB packet definitions
 */

#define	GET2(p)	((((p)[1]&0xFF)<<8)|((p)[0]&0xFF))
#define	PUT2(p,v)	{((p)[0] = (v)); ((p)[1] = (v)>>8);}

enum {
	/* request type */
	RH2D = 0<<7,
	RD2H = 1<<7,
	Rstandard = 0<<5,
	Rclass = 1<<5,
	Rvendor = 2<<5,
	Rdevice = 0,
	Rinterface = 1,
	Rendpt = 2,
	Rother = 3,

	/* standard requests */
	GET_STATUS = 0,
	CLEAR_FEATURE = 1,
	SET_FEATURE = 3,
	SET_ADDRESS = 5,
	GET_DESCRIPTOR = 6,
	SET_DESCRIPTOR = 7,
	GET_CONFIGURATION = 8,
	SET_CONFIGURATION = 9,
	GET_INTERFACE = 10,
	SET_INTERFACE = 11,
	SYNCH_FRAME = 12,

	/* hub class feature selectors */
	C_HUB_LOCAL_POWER = 0,
	C_HUB_OVER_CURRENT,
	PORT_CONNECTION = 0,
	PORT_ENABLE = 1,
	PORT_SUSPEND = 2,
	PORT_OVER_CURRENT = 3,
	PORT_RESET = 4,
	PORT_POWER = 8,
	PORT_LOW_SPEED = 9,
	C_PORT_CONNECTION = 16,
	C_PORT_ENABLE,
	C_PORT_SUSPEND,
	C_PORT_OVER_CURRENT,
	C_PORT_RESET,

	/* descriptor types */
	DEVICE = 1,
	CONFIGURATION = 2,
	STRING = 3,
	INTERFACE = 4,
	ENDPOINT = 5,
	HID = 0x21,
	REPORT = 0x22,
	PHYSICAL = 0x23,

	/* feature selectors */
	DEVICE_REMOTE_WAKEUP = 1,
	ENDPOINT_STALL = 0,
};
