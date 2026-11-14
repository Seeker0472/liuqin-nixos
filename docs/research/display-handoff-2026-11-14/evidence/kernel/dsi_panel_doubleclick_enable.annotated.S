0000000000176d48 <dsi_panel_doubleclick_enable>:
  176d48:      	paciasp
  176d4c:      	adrp	x8, 0x176000 <mi_dsi_panel_parse_flatmode_configs+0x128>
		0000000000176d4c:  R_AARCH64_ADR_PREL_PG_HI21	g_panel
  176d50:      	ldr	x8, [x8]
		0000000000176d50:  R_AARCH64_LDST64_ABS_LO12_NC	g_panel
  176d54:      	and	w9, w0, #0x1
  176d58:      	strb	w9, [x8, #0x8e9]
  176d5c:      	autiasp
  176d60:      	ret

