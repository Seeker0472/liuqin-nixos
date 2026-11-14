000000000013788c <dsi_display_splash_res_cleanup>:
  13788c:      	paciasp
  137890:      	str	x30, [x18], #0x8
  137894:      	stp	x29, x30, [sp, #-0x20]!
  137898:      	stp	x20, x19, [sp, #0x10]
  13789c:      	mov	x29, sp
  1378a0:      	ldrb	w8, [x0, #0x40]
  1378a4:      	cbz	w8, 0x137934 <dsi_display_splash_res_cleanup+0xa8>
  1378a8:      	mov	x20, x0
  1378ac:      	ldr	x0, [x0, #0x4d0]
  1378b0:      	mov	w1, #0x3                // =3
  1378b4:      	mov	w2, wzr
  1378b8:      	bl	0x1378b8 <dsi_display_splash_res_cleanup+0x2c>
		00000000001378b8:  R_AARCH64_CALL26	dsi_display_clk_ctrl
  1378bc:      	mov	w19, w0
  1378c0:      	cbz	w0, 0x1378e4 <dsi_display_splash_res_cleanup+0x58>
  1378c4:      	ldr	x3, [x20, #0x20]
  1378c8:      	adrp	x1, 0x137000 <dsi_post_clkon_cb+0x308>
		00000000001378c8:  R_AARCH64_ADR_PREL_PG_HI21	.rodata+0x48144 // '\x013'
  1378cc:      	adrp	x2, 0x137000 <dsi_post_clkon_cb+0x308>
		00000000001378cc:  R_AARCH64_ADR_PREL_PG_HI21	.rodata+0x1651c // '*ERROR* [msm-dsi-error]: [%s] failed to disable DSI link clocks, rc=%d\n'
  1378d0:      	add	x1, x1, #0x0
		00000000001378d0:  R_AARCH64_ADD_ABS_LO12_NC	.rodata+0x48144 // '\x013'
  1378d4:      	add	x2, x2, #0x0
		00000000001378d4:  R_AARCH64_ADD_ABS_LO12_NC	.rodata+0x1651c // '*ERROR* [msm-dsi-error]: [%s] failed to disable DSI link clocks, rc=%d\n'
  1378d8:      	mov	x0, xzr
  1378dc:      	mov	w4, w19
  1378e0:      	bl	0x1378e0 <dsi_display_splash_res_cleanup+0x54>
		00000000001378e0:  R_AARCH64_CALL26	drm_dev_printk
  1378e4:      	ldr	x8, [x20, #0x8]
  1378e8:      	mov	w1, #0x4                // =4
  1378ec:      	ldr	x0, [x8, #0x18]
  1378f0:      	bl	0x1378f0 <dsi_display_splash_res_cleanup+0x64>
		00000000001378f0:  R_AARCH64_CALL26	__pm_runtime_idle
  1378f4:      	ldr	x0, [x20, #0x4c8]
  1378f8:      	mov	w1, wzr
  1378fc:      	strb	wzr, [x20, #0x40]
  137900:      	bl	0x137900 <dsi_display_splash_res_cleanup+0x74>
		0000000000137900:  R_AARCH64_CALL26	dsi_display_clk_mngr_update_splash_status
  137904:      	adrp	x8, 0x137000 <dsi_post_clkon_cb+0x308>
		0000000000137904:  R_AARCH64_ADR_PREL_PG_HI21	sde_dbg_base_evtlog
  137908:      	ldr	x0, [x8]
		0000000000137908:  R_AARCH64_LDST64_ABS_LO12_NC	sde_dbg_base_evtlog
  13790c:      	ldrb	w5, [x20, #0x40]
  137910:      	adrp	x1, 0x137000 <dsi_post_clkon_cb+0x308>
		0000000000137910:  R_AARCH64_ADR_PREL_PG_HI21	.rodata+0x5ab78 // 'dsi_display_splash_res_cleanup'
  137914:      	mov	w6, #0xbeef             // =48879
  137918:      	add	x1, x1, #0x0
		0000000000137918:  R_AARCH64_ADD_ABS_LO12_NC	.rodata+0x5ab78 // 'dsi_display_splash_res_cleanup'
  13791c:      	mov	w2, #0x160c             // =5644
  137920:      	mov	w3, #-0x1               // =-1
  137924:      	mov	w4, #0x2222             // =8738
  137928:      	movk	w6, #0xc0de, lsl #16
  13792c:      	bl	0x13792c <dsi_display_splash_res_cleanup+0xa0>
		000000000013792c:  R_AARCH64_CALL26	sde_evtlog_log
  137930:      	b	0x137938 <dsi_display_splash_res_cleanup+0xac>
  137934:      	mov	w19, wzr
  137938:      	mov	w0, w19
  13793c:      	ldp	x20, x19, [sp, #0x10]
  137940:      	ldp	x29, x30, [sp], #0x20
  137944:      	ldr	x30, [x18, #-0x8]!
  137948:      	autiasp
  13794c:      	ret

