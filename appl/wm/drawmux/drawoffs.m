# allocate image (old)
#OPa_id		: con 1;
#OPa_screenid	: con 5;
#OPa_refresh	: con 9;
#OPa_ldepth	: con 10;
#OPa_repl		: con 12;
#OPa_R		: con 13;
#OPa_clipR		: con 29;
#OPa_value	: con 45;

# allocate image (new)
OPb_id		: con 1;
OPb_screenid	: con 5;
OPb_refresh	: con 9;
OPb_chans	: con 10;
OPb_repl		: con 14;
OPb_R		: con 15;
OPb_clipR	: con 31;
OPb_rrggbbaa	: con 47;

# allocate screen
OPA_id		: con 1;
OPA_imageid	: con 5;
OPA_fillid		: con 9;
OPA_public	: con 13;

# set repl & clipr
OPc_dstid		: con 1;
OPc_repl		: con 5;
OPc_clipR		: con 6;

# set cursor image and hotspot
#OPC_id		: con 1;
#OPC_hotspot	: con 5;

# the primitive draw op
OPd_dstid	: con 1;
OPd_srcid		: con 5;
OPd_maskid	: con 9;
OPd_R		: con 13;
OPd_P0		: con 29;
OPd_P1		: con 37;

# enable debug messages
OPD_val		: con 1;

# ellipse
OPe_dstid	: con 1;
OPe_srcid		: con 5;
OPe_center	: con 9;
OPe_a		: con 17;
OPe_b		: con 21;
OPe_thick		: con 25;
OPe_sp		: con 29;
OPe_alpha	: con 37;
OPe_phi		: con 41;

# filled ellipse
OPE_dstid	: con 1;
OPE_srcid		: con 5;
OPE_center	: con 9;
OPE_a		: con 17;
OPE_b		: con 21;
OPE_thick		: con 25;
OPE_sp		: con 29;
OPE_alpha	: con 37;
OPE_phi		: con 41;

# free image
OPf_id		: con 1;

# free screen
OPF_id		: con 1;

# init font
OPi_fontid	: con 1;
OPi_nchars	: con 5;
OPi_ascent	: con 9;

# load font char
OPl_fontid	: con 1;
OPl_srcid		: con 5;
OPl_index	: con 9;
OPl_R		: con 11;
OPl_P		: con 27;
OPl_left		: con 35;
OPl_width	: con 36;

# line
OPL_dstid		: con 1;
OPL_P0		: con 5;
OPL_P1		: con 13;
OPL_end0		: con 21;
OPL_end1		: con 25;
OPL_radius	: con 29;
OPL_srcid		: con 33;
OPL_sp		: con 37;

# attach to named image
OPn_dstid	: con 1;
OPn_j		: con 5;
OPn_name	: con 6;

# name image
OPN_dstid	: con 1;
OPN_in		: con 5;
OPN_j		: con 6;
OPN_name	: con 7;

# set window origins
OPo_id		: con 1;
OPo_rmin		: con 5;
OPo_screenrmin	: con 13;

# set next compositing operator
OPO_op		: con 1;

# polygon
OPp_dstid	: con 1;
OPp_n		: con 5;
OPp_end0	: con 7;
OPp_end1	: con 11;
OPp_radius	: con 15;
OPp_srcid		: con 19;
OPp_sp		: con 23;
OPp_P0		: con 31;
OPp_dp		: con 39;

# filled polygon
OPP_dstid	: con 1;
OPP_n		: con 5;
OPP_wind	: con 7;
OPP_ignore	: con 11;
OPP_srcid		: con 19;
OPP_sp		: con 23;
OPP_P0		: con 31;
OPP_dp		: con 39;

# read
OPr_id		: con 1;
OPr_R		: con 5;

# string
OPs_dstid		: con 1;
OPs_srcid		: con 5;
OPs_fontid	: con 9;
OPs_P		: con 13;
OPs_clipR		: con 21;
OPs_sp		: con 37;
OPs_ni		: con 45;
OPs_index	: con 47;

# stringbg
OPx_dstid	: con 1;
OPx_srcid		: con 5;
OPx_fontid	: con 9;
OPx_P		: con 13;
OPx_clipR		: con 21;
OPx_sp		: con 37;
OPx_ni		: con 45;
OPx_bgid		: con 47;
OPx_bgpt		: con 51;
OPx_index	: con 59;

# attach to public screen
OPS_id		: con 1;
OPS_chans		: con 5;

# visible
# top or bottom windows
OPt_top		: con 1;
OPt_nw		: con 2;
OPt_id		: con 4;

#OPv		no fields

# write
OPy_id		: con 1;
OPy_R		: con 5;
OPy_data		: con 21;

# write compressed
OPY_id		: con 1;
OPY_R		: con 5;
OPY_data		: con 21;
