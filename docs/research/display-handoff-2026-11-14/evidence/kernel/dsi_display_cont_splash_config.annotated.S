00000000001376b4 <dsi_display_cont_splash_config>:
  1376b4:      	paciasp
  1376b8:      	str	x30, [x18], #0x8
  1376bc:      	stp	x29, x30, [sp, #-0x40]!
  1376c0:      	str	x23, [sp, #0x10]
  1376c4:      	stp	x22, x21, [sp, #0x20]
  1376c8:      	stp	x20, x19, [sp, #0x30]
  1376cc:      	mov	x29, sp
  1376d0:      	cbz	x0, 0x13781c <dsi_display_cont_splash_config+0x168>
  1376d4:      	ldr	x8, [x0, #0x8]
  1376d8:      	mov	x19, x0
  1376dc:      	mov	w1, #0x4                // =4
  1376e0:      	ldr	x0, [x8, #0x18]
  1376e4:      	bl	0x1376e4 <dsi_display_cont_splash_config+0x30>
		00000000001376e4:  R_AARCH64_CALL26	__pm_runtime_resume
  1376e8:      	tbnz	w0, #0x1f, 0x137838 <dsi_display_cont_splash_config+0x184>
  1376ec:      	add	x20, x19, #0x48
  1376f0:      	mov	x0, x20
  1376f4:      	bl	0x1376f4 <dsi_display_cont_splash_config+0x40>
		00000000001376f4:  R_AARCH64_CALL26	mutex_lock
  1376f8:      	ldr	x0, [x19, #0x4c8]
  1376fc:      	mov	w8, #0x1                // =1
  137700:      	mov	w1, #0x1                // =1
  137704:      	strb	w8, [x19, #0x40]
  137708:      	bl	0x137708 <dsi_display_cont_splash_config+0x54>
		0000000000137708:  R_AARCH64_CALL26	dsi_display_clk_mngr_update_splash_status
  13770c:      	adrp	x8, 0x137000 <dsi_post_clkon_cb+0x308>
		000000000013770c:  R_AARCH64_ADR_PREL_PG_HI21	sde_dbg_base_evtlog
  137710:      	ldr	x0, [x8]
		0000000000137710:  R_AARCH64_LDST64_ABS_LO12_NC	sde_dbg_base_evtlog
  137714:      	ldrb	w5, [x19, #0x40]
  137718:      	adrp	x1, 0x137000 <dsi_post_clkon_cb+0x308>
		0000000000137718:  R_AARCH64_ADR_PREL_PG_HI21	.rodata+0x1f3c1 // 'dsi_display_cont_splash_config'
  13771c:      	mov	w6, #0xbeef             // =48879
  137720:      	add	x1, x1, #0x0
		0000000000137720:  R_AARCH64_ADD_ABS_LO12_NC	.rodata+0x1f3c1 // 'dsi_display_cont_splash_config'
  137724:      	mov	w2, #0x15d1             // =5585
  137728:      	mov	w3, #-0x1               // =-1
  13772c:      	mov	w4, #0x1111             // =4369
  137730:      	movk	w6, #0xc0de, lsl #16
  137734:      	bl	0x137734 <dsi_display_cont_splash_config+0x80>
		0000000000137734:  R_AARCH64_CALL26	sde_evtlog_log
  137738:      	ldr	w8, [x19, #0xa0]
  13773c:      	cbz	w8, 0x137778 <dsi_display_cont_splash_config+0xc4>
  137740:      	add	x21, x19, #0xa8
  137744:      	mov	w22, #0x1               // =1
  137748:      	cbz	x21, 0x13775c <dsi_display_cont_splash_config+0xa8>
  13774c:      	ldr	x0, [x21]
  137750:      	mov	w1, #0x1                // =1
  137754:      	bl	0x137754 <dsi_display_cont_splash_config+0xa0>
		0000000000137754:  R_AARCH64_CALL26	dsi_ctrl_isr_configure
  137758:      	ldr	w8, [x19, #0xa0]
  13775c:      	cmp	x22, #0x1
  137760:      	b.ne	0x137778 <dsi_display_cont_splash_config+0xc4>
  137764:      	mov	w9, w8
  137768:      	cmp	x22, x9
  13776c:      	add	x22, x22, #0x1
  137770:      	add	x21, x21, #0x30
  137774:      	b.lo	0x137748 <dsi_display_cont_splash_config+0x94>
  137778:      	ldr	x0, [x19, #0x4d0]
  13777c:      	mov	w1, #0x3                // =3
  137780:      	mov	w2, #0x1                // =1
  137784:      	bl	0x137784 <dsi_display_cont_splash_config+0xd0>
		0000000000137784:  R_AARCH64_CALL26	dsi_display_clk_ctrl
  137788:      	mov	w21, w0
  13778c:      	cbz	w0, 0x13785c <dsi_display_cont_splash_config+0x1a8>
  137790:      	ldr	x3, [x19, #0x20]
  137794:      	adrp	x1, 0x137000 <dsi_post_clkon_cb+0x308>
		0000000000137794:  R_AARCH64_ADR_PREL_PG_HI21	.rodata+0x48144 // '\x013'
  137798:      	adrp	x2, 0x137000 <dsi_post_clkon_cb+0x308>
		0000000000137798:  R_AARCH64_ADR_PREL_PG_HI21	.rodata+0x164d5 // '*ERROR* [msm-dsi-error]: [%s] failed to enable DSI link clocks, rc=%d\n'
  13779c:      	add	x1, x1, #0x0
		000000000013779c:  R_AARCH64_ADD_ABS_LO12_NC	.rodata+0x48144 // '\x013'
  1377a0:      	add	x2, x2, #0x0
		00000000001377a0:  R_AARCH64_ADD_ABS_LO12_NC	.rodata+0x164d5 // '*ERROR* [msm-dsi-error]: [%s] failed to enable DSI link clocks, rc=%d\n'
  1377a4:      	mov	x0, xzr
  1377a8:      	mov	w4, w21
  1377ac:      	bl	0x1377ac <dsi_display_cont_splash_config+0xf8>
		00000000001377ac:  R_AARCH64_CALL26	drm_dev_printk
  1377b0:      	ldr	w8, [x19, #0xa0]
  1377b4:      	cbz	w8, 0x1377f0 <dsi_display_cont_splash_config+0x13c>
  1377b8:      	add	x22, x19, #0xa8
  1377bc:      	mov	w23, #0x1               // =1
  1377c0:      	cbz	x22, 0x1377d4 <dsi_display_cont_splash_config+0x120>
  1377c4:      	ldr	x0, [x22]
  1377c8:      	mov	w1, wzr
  1377cc:      	bl	0x1377cc <dsi_display_cont_splash_config+0x118>
		00000000001377cc:  R_AARCH64_CALL26	dsi_ctrl_isr_configure
  1377d0:      	ldr	w8, [x19, #0xa0]
  1377d4:      	cmp	x23, #0x1
  1377d8:      	b.ne	0x1377f0 <dsi_display_cont_splash_config+0x13c>
  1377dc:      	mov	w9, w8
  1377e0:      	cmp	x23, x9
  1377e4:      	add	x23, x23, #0x1
  1377e8:      	add	x22, x22, #0x30
  1377ec:      	b.lo	0x1377c0 <dsi_display_cont_splash_config+0x10c>
  1377f0:      	ldr	x0, [x19, #0x4c8]
  1377f4:      	mov	w1, wzr
  1377f8:      	bl	0x1377f8 <dsi_display_cont_splash_config+0x144>
		00000000001377f8:  R_AARCH64_CALL26	dsi_display_clk_mngr_update_splash_status
  1377fc:      	ldr	x8, [x19, #0x8]
  137800:      	mov	w1, #0x4                // =4
  137804:      	ldr	x0, [x8, #0x18]
  137808:      	bl	0x137808 <dsi_display_cont_splash_config+0x154>
		0000000000137808:  R_AARCH64_CALL26	__pm_runtime_idle
  13780c:      	mov	x0, x20
  137810:      	strb	wzr, [x19, #0x40]
  137814:      	bl	0x137814 <dsi_display_cont_splash_config+0x160>
		0000000000137814:  R_AARCH64_CALL26	mutex_unlock
  137818:      	b	0x13786c <dsi_display_cont_splash_config+0x1b8>
  13781c:      	adrp	x1, 0x137000 <dsi_post_clkon_cb+0x308>
		000000000013781c:  R_AARCH64_ADR_PREL_PG_HI21	.rodata+0x48144 // '\x013'
  137820:      	adrp	x2, 0x137000 <dsi_post_clkon_cb+0x308>
		0000000000137820:  R_AARCH64_ADR_PREL_PG_HI21	.rodata+0xb5ff // '*ERROR* [msm-dsi-error]: invalid input display param\n'
  137824:      	add	x1, x1, #0x0
		0000000000137824:  R_AARCH64_ADD_ABS_LO12_NC	.rodata+0x48144 // '\x013'
  137828:      	add	x2, x2, #0x0
		0000000000137828:  R_AARCH64_ADD_ABS_LO12_NC	.rodata+0xb5ff // '*ERROR* [msm-dsi-error]: invalid input display param\n'
  13782c:      	bl	0x13782c <dsi_display_cont_splash_config+0x178>
		000000000013782c:  R_AARCH64_CALL26	drm_dev_printk
  137830:      	mov	w21, #-0x16             // =-22
  137834:      	b	0x13786c <dsi_display_cont_splash_config+0x1b8>
  137838:      	mov	w21, w0
  13783c:      	adrp	x1, 0x137000 <dsi_post_clkon_cb+0x308>
		000000000013783c:  R_AARCH64_ADR_PREL_PG_HI21	.rodata+0x48144 // '\x013'
  137840:      	adrp	x2, 0x137000 <dsi_post_clkon_cb+0x308>
		0000000000137840:  R_AARCH64_ADR_PREL_PG_HI21	.rodata+0x5ab2d // '*ERROR* [msm-dsi-error]: failed to vote gdsc for continuous splash, rc=%d\n'
  137844:      	add	x1, x1, #0x0
		0000000000137844:  R_AARCH64_ADD_ABS_LO12_NC	.rodata+0x48144 // '\x013'
  137848:      	add	x2, x2, #0x0
		0000000000137848:  R_AARCH64_ADD_ABS_LO12_NC	.rodata+0x5ab2d // '*ERROR* [msm-dsi-error]: failed to vote gdsc for continuous splash, rc=%d\n'
  13784c:      	mov	x0, xzr
  137850:      	mov	w3, w21
  137854:      	bl	0x137854 <dsi_display_cont_splash_config+0x1a0>
		0000000000137854:  R_AARCH64_CALL26	drm_dev_printk
  137858:      	b	0x13786c <dsi_display_cont_splash_config+0x1b8>
  13785c:      	mov	x0, x20
  137860:      	bl	0x137860 <dsi_display_cont_splash_config+0x1ac>
		0000000000137860:  R_AARCH64_CALL26	mutex_unlock
  137864:      	ldr	x0, [x19, #0x108]
  137868:      	bl	0x137868 <dsi_display_cont_splash_config+0x1b4>
		0000000000137868:  R_AARCH64_CALL26	dsi_panel_bl_handoff
  13786c:      	mov	w0, w21
  137870:      	ldp	x20, x19, [sp, #0x30]
  137874:      	ldp	x22, x21, [sp, #0x20]
  137878:      	ldr	x23, [sp, #0x10]
  13787c:      	ldp	x29, x30, [sp], #0x40
  137880:      	ldr	x30, [x18, #-0x8]!
  137884:      	autiasp
  137888:      	ret

