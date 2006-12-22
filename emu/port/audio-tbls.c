svp_t audio_bits_tbl[] = {
	{ "8", 8 } ,	 /* 8 bits per sample */
	{ "16", 16 },  /* 16 bits per sample */
	{nil},
};

svp_t audio_chan_tbl[] = {
	{ "1", 1 },		/* 1 channel */
	{ "2", 2 },	/* 2 channels */
	{nil},
};

svp_t audio_indev_tbl[] = {
	{ "mic", Audio_Mic_Val }, 		/* input microphone */
	{ "line", Audio_Linein_Val }, 	/* line in */
	{nil},
};

svp_t audio_outdev_tbl[] = {
	{ "spkr", Audio_Speaker_Val },	/* output speaker */
	{ "hdph", Audio_Headphone_Val },/* head phones */
	{ "line", Audio_Lineout_Val },	/* line out */
	{nil},
};

svp_t audio_enc_tbl[] = {
	{ "ulaw", Audio_Ulaw_Val },	/* u-law encoding */
	{ "alaw", Audio_Alaw_Val },	/* A-law encoding */
	{ "pcm", Audio_Pcm_Val },	/* Pulse Code Modulation */
	{nil},
};

svp_t audio_rate_tbl[] = {
	{ "8000", 8000 },	/* 8000 samples per second */
	{ "11025", 11025 },	/* 11025 samples per second */
	{ "22050", 22050 },	/* 22050 samples per second */
	{ "44100", 44100 },	/* 44100 samples per second */
	{nil},
};

Audio_d Default_Audio_Format =  {
	0,
	16,				/* bits per sample */
	Audio_Max_Val,			/* buffer size (as percentage) */
	2,				/* number of channels */
	-1,				/* device */
	Audio_Pcm_Val,			/* encoding format */
	8000,				/* samples per second */
	Audio_Max_Val,			/* left channel gain */
	Audio_Max_Val,			/* right channel gain */
};
int Default_Audio_Input = Audio_Mic_Val;
int Default_Audio_Output = Audio_Speaker_Val;
