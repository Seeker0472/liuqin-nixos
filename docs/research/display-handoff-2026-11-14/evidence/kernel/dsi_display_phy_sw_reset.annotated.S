0000000000137318 <dsi_display_phy_sw_reset>:
  137318:      	paciasp
  13731c:      	str	x30, [x18], #0x8
  137320:      	stp	x29, x30, [sp, #-0x40]!
  137324:      	str	x23, [sp, #0x10]
  137328:      	stp	x22, x21, [sp, #0x20]
  13732c:      	stp	x20, x19, [sp, #0x30]
  137330:      	mov	x29, sp
  137334:      	mov	x19, x0
  137338:      	cbz	x0, 0x137368 <dsi_display_phy_sw_reset+0x50>
  13733c:      	ldrb	w8, [x19, #0x40]
  137340:      	cbnz	w8, 0x13734c <dsi_display_phy_sw_reset+0x34>
  137344:      	ldrb	w8, [x19, #0x651]
  137348:      	cbz	w8, 0x137368 <dsi_display_phy_sw_reset+0x50>
  13734c:      	adrp	x2, 0x137000 <dsi_post_clkon_cb+0x308>
		000000000013734c:  R_AARCH64_ADR_PREL_PG_HI21	.rodata+0x1c41e // '[msm-dsi-debug]: cont splash/trusted vm use case, phy sw reset not required\n'
  137350:      	add	x2, x2, #0x0
		0000000000137350:  R_AARCH64_ADD_ABS_LO12_NC	.rodata+0x1c41e // '[msm-dsi-debug]: cont splash/trusted vm use case, phy sw reset not required\n'
  137354:      	mov	w1, #0x1                // =1
  137358:      	mov	x0, xzr
  13735c:      	bl	0x13735c <dsi_display_phy_sw_reset+0x44>
		000000000013735c:  R_AARCH64_CALL26	drm_dev_dbg
  137360:      	mov	w20, wzr
  137364:      	b	0x1373ac <dsi_display_phy_sw_reset+0x94>
  137368:      	ldr	w21, [x19, #0x308]
  13736c:      	cmp	w21, #0x3
  137370:      	b.hs	0x13742c <dsi_display_phy_sw_reset+0x114>
  137374:      	mov	w8, #0x30               // =48
  137378:      	madd	x8, x21, x8, x19
  13737c:      	ldr	x0, [x8, #0xa8]
  137380:      	bl	0x137380 <dsi_display_phy_sw_reset+0x68>
		0000000000137380:  R_AARCH64_CALL26	dsi_ctrl_phy_sw_reset
  137384:      	cbz	w0, 0x1373cc <dsi_display_phy_sw_reset+0xb4>
  137388:      	ldr	x3, [x19, #0x20]
  13738c:      	mov	w20, w0
  137390:      	adrp	x1, 0x137000 <dsi_post_clkon_cb+0x308>
		0000000000137390:  R_AARCH64_ADR_PREL_PG_HI21	.rodata+0x48144 // '\x013'
  137394:      	adrp	x2, 0x137000 <dsi_post_clkon_cb+0x308>
		0000000000137394:  R_AARCH64_ADR_PREL_PG_HI21	.rodata+0x3a0b1 // '*ERROR* [msm-dsi-error]: [%s] failed to reset phy, rc=%d\n'
  137398:      	add	x1, x1, #0x0
		0000000000137398:  R_AARCH64_ADD_ABS_LO12_NC	.rodata+0x48144 // '\x013'
  13739c:      	add	x2, x2, #0x0
		000000000013739c:  R_AARCH64_ADD_ABS_LO12_NC	.rodata+0x3a0b1 // '*ERROR* [msm-dsi-error]: [%s] failed to reset phy, rc=%d\n'
  1373a0:      	mov	x0, xzr
  1373a4:      	mov	w4, w20
  1373a8:      	bl	0x1373a8 <dsi_display_phy_sw_reset+0x90>
		00000000001373a8:  R_AARCH64_CALL26	drm_dev_printk
  1373ac:      	mov	w0, w20
  1373b0:      	ldp	x20, x19, [sp, #0x30]
  1373b4:      	ldp	x22, x21, [sp, #0x20]
  1373b8:      	ldr	x23, [sp, #0x10]
  1373bc:      	ldp	x29, x30, [sp], #0x40
  1373c0:      	ldr	x30, [x18, #-0x8]!
  1373c4:      	autiasp
  1373c8:      	ret
  1373cc:      	ldr	w8, [x19, #0xa0]
  1373d0:      	cbz	w8, 0x137424 <dsi_display_phy_sw_reset+0x10c>
  1373d4:      	add	x9, x21, x21, lsl #1
  1373d8:      	add	x21, x19, #0xa8
  1373dc:      	lsl	x22, x9, #4
  1373e0:      	mov	w23, #0x1               // =1
  1373e4:      	cbz	x22, 0x1373fc <dsi_display_phy_sw_reset+0xe4>
  1373e8:      	ldr	x0, [x21]
  1373ec:      	cbz	x0, 0x1373fc <dsi_display_phy_sw_reset+0xe4>
  1373f0:      	bl	0x1373f0 <dsi_display_phy_sw_reset+0xd8>
		00000000001373f0:  R_AARCH64_CALL26	dsi_ctrl_phy_sw_reset
  1373f4:      	cbnz	w0, 0x137388 <dsi_display_phy_sw_reset+0x70>
  1373f8:      	ldr	w8, [x19, #0xa0]
  1373fc:      	cmp	x23, #0x1
  137400:      	mov	w20, wzr
  137404:      	b.ne	0x1373ac <dsi_display_phy_sw_reset+0x94>
  137408:      	mov	w9, w8
  13740c:      	cmp	x23, x9
  137410:      	add	x23, x23, #0x1
  137414:      	sub	x22, x22, #0x30
  137418:      	add	x21, x21, #0x30
  13741c:      	b.lo	0x1373e4 <dsi_display_phy_sw_reset+0xcc>
  137420:      	b	0x1373ac <dsi_display_phy_sw_reset+0x94>
  137424:      	mov	w20, wzr
  137428:      	b	0x1373ac <dsi_display_phy_sw_reset+0x94>
  13742c:      	brk	#0x5512

