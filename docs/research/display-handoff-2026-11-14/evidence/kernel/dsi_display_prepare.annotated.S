000000000013d308 <dsi_display_prepare>:
  13d308:      	paciasp
  13d30c:      	str	x30, [x18], #0x8
  13d310:      	stp	x29, x30, [sp, #-0x60]!
  13d314:      	stp	x28, x27, [sp, #0x10]
  13d318:      	stp	x26, x25, [sp, #0x20]
  13d31c:      	stp	x24, x23, [sp, #0x30]
  13d320:      	stp	x22, x21, [sp, #0x40]
  13d324:      	stp	x20, x19, [sp, #0x50]
  13d328:      	mov	x29, sp
  13d32c:      	cbz	x0, 0x13d414 <dsi_display_prepare+0x10c>
  13d330:      	ldr	x8, [x0, #0x108]
  13d334:      	mov	x20, x0
  13d338:      	ldr	x8, [x8, #0x520]
  13d33c:      	cbz	x8, 0x13d428 <dsi_display_prepare+0x120>
  13d340:      	adrp	x25, 0x13d000 <dsi_display_set_mode+0xff0>
		000000000013d340:  R_AARCH64_ADR_PREL_PG_HI21	sde_dbg_base_evtlog
  13d344:      	ldr	x0, [x25]
		000000000013d344:  R_AARCH64_LDST64_ABS_LO12_NC	sde_dbg_base_evtlog
  13d348:      	adrp	x1, 0x13d000 <dsi_display_set_mode+0xff0>
		000000000013d348:  R_AARCH64_ADR_PREL_PG_HI21	.rodata+0x4b9f1 // 'dsi_display_prepare'
  13d34c:      	mov	w5, #0xbeef             // =48879
  13d350:      	add	x1, x1, #0x0
		000000000013d350:  R_AARCH64_ADD_ABS_LO12_NC	.rodata+0x4b9f1 // 'dsi_display_prepare'
  13d354:      	mov	w2, #0x2100             // =8448
  13d358:      	mov	w3, #-0x1               // =-1
  13d35c:      	mov	w4, #0x1111             // =4369
  13d360:      	movk	w5, #0xc0de, lsl #16
  13d364:      	bl	0x13d364 <dsi_display_prepare+0x5c>
		000000000013d364:  R_AARCH64_CALL26	sde_evtlog_log
  13d368:      	add	x19, x20, #0x48
  13d36c:      	mov	x0, x19
  13d370:      	bl	0x13d370 <dsi_display_prepare+0x68>
		000000000013d370:  R_AARCH64_CALL26	mutex_lock
  13d374:      	ldr	x9, [x20, #0x108]
  13d378:      	mov	w8, #0x1                // =1
  13d37c:      	strb	w8, [x20, #0x652]
  13d380:      	ldr	w8, [x20, #0xa0]
  13d384:      	ldr	x21, [x9, #0x520]
  13d388:      	cbz	w8, 0x13d448 <dsi_display_prepare+0x140>
  13d38c:      	add	x9, x20, #0xa8
  13d390:      	mov	w10, #0x1               // =1
  13d394:      	cbz	x9, 0x13d3a4 <dsi_display_prepare+0x9c>
  13d398:      	ldr	x8, [x9]
  13d39c:      	strb	wzr, [x8, #0x701]
  13d3a0:      	ldr	w8, [x20, #0xa0]
  13d3a4:      	cmp	x10, #0x1
  13d3a8:      	b.ne	0x13d3c0 <dsi_display_prepare+0xb8>
  13d3ac:      	mov	w11, w8
  13d3b0:      	cmp	x10, x11
  13d3b4:      	add	x10, x10, #0x1
  13d3b8:      	add	x9, x9, #0x30
  13d3bc:      	b.lo	0x13d394 <dsi_display_prepare+0x8c>
  13d3c0:      	add	x24, x20, #0x651
  13d3c4:      	cbz	w8, 0x13d408 <dsi_display_prepare+0x100>
  13d3c8:      	ldrb	w9, [x20, #0x651]
  13d3cc:      	cbnz	w9, 0x13d408 <dsi_display_prepare+0x100>
  13d3d0:      	add	x22, x20, #0xa8
  13d3d4:      	mov	w23, #0x1               // =1
  13d3d8:      	cbz	x22, 0x13d3ec <dsi_display_prepare+0xe4>
  13d3dc:      	ldr	x0, [x22]
  13d3e0:      	mov	w1, #0x1                // =1
  13d3e4:      	bl	0x13d3e4 <dsi_display_prepare+0xdc>
		000000000013d3e4:  R_AARCH64_CALL26	dsi_ctrl_isr_configure
  13d3e8:      	ldr	w8, [x20, #0xa0]
  13d3ec:      	cmp	x23, #0x1
  13d3f0:      	b.ne	0x13d408 <dsi_display_prepare+0x100>
  13d3f4:      	mov	w9, w8
  13d3f8:      	cmp	x23, x9
  13d3fc:      	add	x23, x23, #0x1
  13d400:      	add	x22, x22, #0x30
  13d404:      	b.lo	0x13d3d8 <dsi_display_prepare+0xd0>
  13d408:      	ldrb	w8, [x21, #0x94]
  13d40c:      	tbnz	w8, #0x3, 0x13d454 <dsi_display_prepare+0x14c>
  13d410:      	b	0x13d490 <dsi_display_prepare+0x188>
  13d414:      	adrp	x1, 0x13d000 <dsi_display_set_mode+0xff0>
		000000000013d414:  R_AARCH64_ADR_PREL_PG_HI21	.rodata+0x48144 // '\x013'
  13d418:      	adrp	x2, 0x13d000 <dsi_display_set_mode+0xff0>
		000000000013d418:  R_AARCH64_ADR_PREL_PG_HI21	.rodata+0x1bf30 // '*ERROR* [msm-dsi-error]: Invalid params\n'
  13d41c:      	add	x1, x1, #0x0
		000000000013d41c:  R_AARCH64_ADD_ABS_LO12_NC	.rodata+0x48144 // '\x013'
  13d420:      	add	x2, x2, #0x0
		000000000013d420:  R_AARCH64_ADD_ABS_LO12_NC	.rodata+0x1bf30 // '*ERROR* [msm-dsi-error]: Invalid params\n'
  13d424:      	b	0x13d43c <dsi_display_prepare+0x134>
  13d428:      	adrp	x1, 0x13d000 <dsi_display_set_mode+0xff0>
		000000000013d428:  R_AARCH64_ADR_PREL_PG_HI21	.rodata+0x48144 // '\x013'
  13d42c:      	adrp	x2, 0x13d000 <dsi_display_set_mode+0xff0>
		000000000013d42c:  R_AARCH64_ADR_PREL_PG_HI21	.rodata+0x36dc4 // '*ERROR* [msm-dsi-error]: no valid mode set for the display\n'
  13d430:      	add	x1, x1, #0x0
		000000000013d430:  R_AARCH64_ADD_ABS_LO12_NC	.rodata+0x48144 // '\x013'
  13d434:      	add	x2, x2, #0x0
		000000000013d434:  R_AARCH64_ADD_ABS_LO12_NC	.rodata+0x36dc4 // '*ERROR* [msm-dsi-error]: no valid mode set for the display\n'
  13d438:      	mov	x0, xzr
  13d43c:      	bl	0x13d43c <dsi_display_prepare+0x134>
		000000000013d43c:  R_AARCH64_CALL26	drm_dev_printk
  13d440:      	mov	w21, #-0x16             // =-22
  13d444:      	b	0x13da7c <dsi_display_prepare+0x774>
  13d448:      	add	x24, x20, #0x651
  13d44c:      	ldrb	w8, [x21, #0x94]
  13d450:      	tbz	w8, #0x3, 0x13d490 <dsi_display_prepare+0x188>
  13d454:      	ldrb	w8, [x20, #0x40]
  13d458:      	cbz	w8, 0x13d488 <dsi_display_prepare+0x180>
  13d45c:      	ldr	w8, [x20, #0x330]
  13d460:      	cmp	w8, #0x1
  13d464:      	b.ne	0x13d490 <dsi_display_prepare+0x188>
  13d468:      	adrp	x1, 0x13d000 <dsi_display_set_mode+0xff0>
		000000000013d468:  R_AARCH64_ADR_PREL_PG_HI21	.rodata+0x48144 // '\x013'
  13d46c:      	adrp	x2, 0x13d000 <dsi_display_set_mode+0xff0>
		000000000013d46c:  R_AARCH64_ADR_PREL_PG_HI21	.rodata+0x2adb8 // '*ERROR* [msm-dsi-error]: DMS not supported on first frame\n'
  13d470:      	add	x1, x1, #0x0
		000000000013d470:  R_AARCH64_ADD_ABS_LO12_NC	.rodata+0x48144 // '\x013'
  13d474:      	add	x2, x2, #0x0
		000000000013d474:  R_AARCH64_ADD_ABS_LO12_NC	.rodata+0x2adb8 // '*ERROR* [msm-dsi-error]: DMS not supported on first frame\n'
  13d478:      	mov	x0, xzr
  13d47c:      	bl	0x13d47c <dsi_display_prepare+0x174>
		000000000013d47c:  R_AARCH64_CALL26	drm_dev_printk
  13d480:      	mov	w21, #-0x16             // =-22
  13d484:      	b	0x13da50 <dsi_display_prepare+0x748>
  13d488:      	ldrb	w8, [x24]
  13d48c:      	cbz	w8, 0x13d530 <dsi_display_prepare+0x228>
  13d490:      	ldrb	w8, [x20, #0x469]
  13d494:      	cbnz	w8, 0x13d4a8 <dsi_display_prepare+0x1a0>
  13d498:      	ldrb	w8, [x20, #0x40]
  13d49c:      	cbnz	w8, 0x13d4a8 <dsi_display_prepare+0x1a0>
  13d4a0:      	ldrb	w8, [x24]
  13d4a4:      	cbz	w8, 0x13d734 <dsi_display_prepare+0x42c>
  13d4a8:      	ldr	x0, [x20, #0x4d0]
  13d4ac:      	mov	w1, #0x1                // =1
  13d4b0:      	mov	w2, #0x1                // =1
  13d4b4:      	bl	0x13d4b4 <dsi_display_prepare+0x1ac>
		000000000013d4b4:  R_AARCH64_CALL26	dsi_display_clk_ctrl
  13d4b8:      	cbz	w0, 0x13d4e4 <dsi_display_prepare+0x1dc>
  13d4bc:      	ldr	x3, [x20, #0x20]
  13d4c0:      	mov	w21, w0
  13d4c4:      	adrp	x1, 0x13d000 <dsi_display_set_mode+0xff0>
		000000000013d4c4:  R_AARCH64_ADR_PREL_PG_HI21	.rodata+0x48144 // '\x013'
  13d4c8:      	adrp	x2, 0x13d000 <dsi_display_set_mode+0xff0>
		000000000013d4c8:  R_AARCH64_ADR_PREL_PG_HI21	.rodata+0x4ee8b // '*ERROR* [msm-dsi-error]: [%s] failed to enable DSI core clocks, rc=%d\n'
  13d4cc:      	add	x1, x1, #0x0
		000000000013d4cc:  R_AARCH64_ADD_ABS_LO12_NC	.rodata+0x48144 // '\x013'
  13d4d0:      	add	x2, x2, #0x0
		000000000013d4d0:  R_AARCH64_ADD_ABS_LO12_NC	.rodata+0x4ee8b // '*ERROR* [msm-dsi-error]: [%s] failed to enable DSI core clocks, rc=%d\n'
  13d4d4:      	mov	x0, xzr
  13d4d8:      	mov	w4, w21
  13d4dc:      	bl	0x13d4dc <dsi_display_prepare+0x1d4>
		000000000013d4dc:  R_AARCH64_CALL26	drm_dev_printk
  13d4e0:      	b	0x13da48 <dsi_display_prepare+0x740>
  13d4e4:      	ldr	x8, [x20, #0x108]
  13d4e8:      	ldrb	w8, [x8, #0x7aa]
  13d4ec:      	cbz	w8, 0x13d508 <dsi_display_prepare+0x200>
  13d4f0:      	ldrb	w8, [x20, #0x46a]
  13d4f4:      	cbz	w8, 0x13d508 <dsi_display_prepare+0x200>
  13d4f8:      	ldrb	w8, [x20, #0x40]
  13d4fc:      	cbz	w8, 0x13d5a0 <dsi_display_prepare+0x298>
  13d500:      	mov	w22, #0x1               // =1
  13d504:      	b	0x13d5ac <dsi_display_prepare+0x2a4>
  13d508:      	mov	x0, x20
  13d50c:      	bl	0x13d50c <dsi_display_prepare+0x204>
		000000000013d50c:  R_AARCH64_CALL26	.text+0x137318 // dsi_display_phy_sw_reset
  13d510:      	cbz	w0, 0x13d56c <dsi_display_prepare+0x264>
  13d514:      	ldr	x3, [x20, #0x20]
  13d518:      	adrp	x1, 0x13d000 <dsi_display_set_mode+0xff0>
		000000000013d518:  R_AARCH64_ADR_PREL_PG_HI21	.rodata+0x48144 // '\x013'
  13d51c:      	adrp	x2, 0x13d000 <dsi_display_set_mode+0xff0>
		000000000013d51c:  R_AARCH64_ADR_PREL_PG_HI21	.rodata+0x3a0b1 // '*ERROR* [msm-dsi-error]: [%s] failed to reset phy, rc=%d\n'
  13d520:      	mov	w21, w0
  13d524:      	add	x1, x1, #0x0
		000000000013d524:  R_AARCH64_ADD_ABS_LO12_NC	.rodata+0x48144 // '\x013'
  13d528:      	add	x2, x2, #0x0
		000000000013d528:  R_AARCH64_ADD_ABS_LO12_NC	.rodata+0x3a0b1 // '*ERROR* [msm-dsi-error]: [%s] failed to reset phy, rc=%d\n'
  13d52c:      	b	0x13d590 <dsi_display_prepare+0x288>
  13d530:      	ldr	x0, [x20, #0x4d0]
  13d534:      	mov	w1, #0x1                // =1
  13d538:      	mov	w2, #0x1                // =1
  13d53c:      	bl	0x13d53c <dsi_display_prepare+0x234>
		000000000013d53c:  R_AARCH64_CALL26	dsi_display_clk_ctrl
  13d540:      	cbz	w0, 0x13d8fc <dsi_display_prepare+0x5f4>
  13d544:      	ldr	x3, [x20, #0x20]
  13d548:      	mov	w21, w0
  13d54c:      	adrp	x1, 0x13d000 <dsi_display_set_mode+0xff0>
		000000000013d54c:  R_AARCH64_ADR_PREL_PG_HI21	.rodata+0x48144 // '\x013'
  13d550:      	adrp	x2, 0x13d000 <dsi_display_set_mode+0xff0>
		000000000013d550:  R_AARCH64_ADR_PREL_PG_HI21	.rodata+0x4ee8b // '*ERROR* [msm-dsi-error]: [%s] failed to enable DSI core clocks, rc=%d\n'
  13d554:      	add	x1, x1, #0x0
		000000000013d554:  R_AARCH64_ADD_ABS_LO12_NC	.rodata+0x48144 // '\x013'
  13d558:      	add	x2, x2, #0x0
		000000000013d558:  R_AARCH64_ADD_ABS_LO12_NC	.rodata+0x4ee8b // '*ERROR* [msm-dsi-error]: [%s] failed to enable DSI core clocks, rc=%d\n'
  13d55c:      	mov	x0, xzr
  13d560:      	mov	w4, w21
  13d564:      	bl	0x13d564 <dsi_display_prepare+0x25c>
		000000000013d564:  R_AARCH64_CALL26	drm_dev_printk
  13d568:      	b	0x13db68 <dsi_display_prepare+0x860>
  13d56c:      	mov	x0, x20
  13d570:      	bl	0x13d570 <dsi_display_prepare+0x268>
		000000000013d570:  R_AARCH64_CALL26	.text+0x13dc54 // dsi_display_phy_enable
  13d574:      	cbz	w0, 0x13d4f8 <dsi_display_prepare+0x1f0>
  13d578:      	ldr	x3, [x20, #0x20]
  13d57c:      	adrp	x1, 0x13d000 <dsi_display_set_mode+0xff0>
		000000000013d57c:  R_AARCH64_ADR_PREL_PG_HI21	.rodata+0x48144 // '\x013'
  13d580:      	adrp	x2, 0x13d000 <dsi_display_set_mode+0xff0>
		000000000013d580:  R_AARCH64_ADR_PREL_PG_HI21	.rodata+0x3cdf5 // '*ERROR* [msm-dsi-error]: [%s] failed to enable DSI PHY, rc=%d\n'
  13d584:      	mov	w21, w0
  13d588:      	add	x1, x1, #0x0
		000000000013d588:  R_AARCH64_ADD_ABS_LO12_NC	.rodata+0x48144 // '\x013'
  13d58c:      	add	x2, x2, #0x0
		000000000013d58c:  R_AARCH64_ADD_ABS_LO12_NC	.rodata+0x3cdf5 // '*ERROR* [msm-dsi-error]: [%s] failed to enable DSI PHY, rc=%d\n'
  13d590:      	mov	x0, xzr
  13d594:      	mov	w4, w21
  13d598:      	bl	0x13d598 <dsi_display_prepare+0x290>
		000000000013d598:  R_AARCH64_CALL26	drm_dev_printk
  13d59c:      	b	0x13da38 <dsi_display_prepare+0x730>
  13d5a0:      	ldrb	w8, [x24]
  13d5a4:      	cmp	w8, #0x0
  13d5a8:      	cset	w22, ne
  13d5ac:      	ldr	x8, [x20, #0x108]
  13d5b0:      	ldrb	w8, [x8, #0x7aa]
  13d5b4:      	cbz	w8, 0x13d638 <dsi_display_prepare+0x330>
  13d5b8:      	ldrb	w8, [x20, #0x46a]
  13d5bc:      	cbz	w8, 0x13d638 <dsi_display_prepare+0x330>
  13d5c0:      	ldr	w8, [x20, #0xa0]
  13d5c4:      	cbz	w8, 0x13d670 <dsi_display_prepare+0x368>
  13d5c8:      	adrp	x22, 0x13d000 <dsi_display_set_mode+0xff0>
		000000000013d5c8:  R_AARCH64_ADR_PREL_PG_HI21	.rodata+0x2b0cf // '[msm-dsi-debug]: host init update failed rc=%d\n'
  13d5cc:      	mov	x23, xzr
  13d5d0:      	mov	w26, #0x30              // =48
  13d5d4:      	add	x22, x22, #0x0
		000000000013d5d4:  R_AARCH64_ADD_ABS_LO12_NC	.rodata+0x2b0cf // '[msm-dsi-debug]: host init update failed rc=%d\n'
  13d5d8:      	madd	x8, x23, x26, x20
  13d5dc:      	ldr	x0, [x8, #0xa8]
  13d5e0:      	mov	w1, #0x5                // =5
  13d5e4:      	mov	w2, #0x1                // =1
  13d5e8:      	bl	0x13d5e8 <dsi_display_prepare+0x2e0>
		000000000013d5e8:  R_AARCH64_CALL26	dsi_ctrl_update_host_state
  13d5ec:      	cbz	w0, 0x13d620 <dsi_display_prepare+0x318>
  13d5f0:      	mov	w21, w0
  13d5f4:      	mov	w1, #0x1                // =1
  13d5f8:      	mov	x0, xzr
  13d5fc:      	mov	x2, x22
  13d600:      	mov	w3, w21
  13d604:      	bl	0x13d604 <dsi_display_prepare+0x2fc>
		000000000013d604:  R_AARCH64_CALL26	drm_dev_dbg
  13d608:      	cbnz	x23, 0x13da10 <dsi_display_prepare+0x708>
  13d60c:      	ldr	w8, [x20, #0xa0]
  13d610:      	add	x23, x23, #0x1
  13d614:      	cmp	x23, x8
  13d618:      	b.lo	0x13d5d8 <dsi_display_prepare+0x2d0>
  13d61c:      	b	0x13da10 <dsi_display_prepare+0x708>
  13d620:      	cbnz	x23, 0x13d670 <dsi_display_prepare+0x368>
  13d624:      	ldr	w8, [x20, #0xa0]
  13d628:      	add	x23, x23, #0x1
  13d62c:      	cmp	x23, x8
  13d630:      	b.lo	0x13d5d8 <dsi_display_prepare+0x2d0>
  13d634:      	b	0x13d670 <dsi_display_prepare+0x368>
  13d638:      	ldr	w8, [x20, #0xa0]
  13d63c:      	cbz	w8, 0x13d670 <dsi_display_prepare+0x368>
  13d640:      	mov	x23, xzr
  13d644:      	add	x26, x20, #0xa8
  13d648:      	ldr	x0, [x26]
  13d64c:      	mov	w1, w22
  13d650:      	bl	0x13d650 <dsi_display_prepare+0x348>
		000000000013d650:  R_AARCH64_CALL26	dsi_ctrl_host_init
  13d654:      	cbnz	w0, 0x13d9cc <dsi_display_prepare+0x6c4>
  13d658:      	cbnz	x23, 0x13d670 <dsi_display_prepare+0x368>
  13d65c:      	ldr	w8, [x20, #0xa0]
  13d660:      	add	x23, x23, #0x1
  13d664:      	add	x26, x26, #0x30
  13d668:      	cmp	x23, x8
  13d66c:      	b.lo	0x13d648 <dsi_display_prepare+0x340>
  13d670:      	adrp	x0, 0x13d000 <dsi_display_set_mode+0xff0>
		000000000013d670:  R_AARCH64_ADR_PREL_PG_HI21	.rodata+0xee0e // '%s'
  13d674:      	adrp	x3, 0x13d000 <dsi_display_set_mode+0xff0>
		000000000013d674:  R_AARCH64_ADR_PREL_PG_HI21	.rodata+0x4632c // 'dsi_err_workq'
  13d678:      	mov	w1, #0xa                // =10
  13d67c:      	add	x0, x0, #0x0
		000000000013d67c:  R_AARCH64_ADD_ABS_LO12_NC	.rodata+0xee0e // '%s'
  13d680:      	add	x3, x3, #0x0
		000000000013d680:  R_AARCH64_ADD_ABS_LO12_NC	.rodata+0x4632c // 'dsi_err_workq'
  13d684:      	movk	w1, #0xe, lsl #16
  13d688:      	mov	w2, #0x1                // =1
  13d68c:      	bl	0x13d68c <dsi_display_prepare+0x384>
		000000000013d68c:  R_AARCH64_CALL26	alloc_workqueue
  13d690:      	str	x0, [x20, #0x4f8]
  13d694:      	cbz	x0, 0x13d75c <dsi_display_prepare+0x454>
  13d698:      	mov	x8, #0xfffffffe0        // =68719476704
  13d69c:      	add	x9, x20, #0x508
  13d6a0:      	str	x8, [x20, #0x500]
  13d6a4:      	str	x9, [x20, #0x508]
  13d6a8:      	str	x9, [x20, #0x510]
  13d6ac:      	adrp	x9, 0x13d000 <dsi_display_set_mode+0xff0>
		000000000013d6ac:  R_AARCH64_ADR_PREL_PG_HI21	dsi_display_handle_fifo_underflow$4022fdf6e8c0d16dd5fc5f18ee4adc5a.cfi_jt
  13d6b0:      	add	x9, x9, #0x0
		000000000013d6b0:  R_AARCH64_ADD_ABS_LO12_NC	dsi_display_handle_fifo_underflow$4022fdf6e8c0d16dd5fc5f18ee4adc5a.cfi_jt
  13d6b4:      	str	x9, [x20, #0x518]
  13d6b8:      	add	x9, x20, #0x538
  13d6bc:      	str	x8, [x20, #0x530]
  13d6c0:      	str	x9, [x20, #0x538]
  13d6c4:      	str	x9, [x20, #0x540]
  13d6c8:      	adrp	x9, 0x13d000 <dsi_display_set_mode+0xff0>
		000000000013d6c8:  R_AARCH64_ADR_PREL_PG_HI21	dsi_display_handle_fifo_overflow$4022fdf6e8c0d16dd5fc5f18ee4adc5a.cfi_jt
  13d6cc:      	add	x9, x9, #0x0
		000000000013d6cc:  R_AARCH64_ADD_ABS_LO12_NC	dsi_display_handle_fifo_overflow$4022fdf6e8c0d16dd5fc5f18ee4adc5a.cfi_jt
  13d6d0:      	str	x9, [x20, #0x548]
  13d6d4:      	add	x9, x20, #0x568
  13d6d8:      	str	x8, [x20, #0x560]
  13d6dc:      	str	x9, [x20, #0x568]
  13d6e0:      	ldr	w8, [x20, #0xa0]
  13d6e4:      	str	x9, [x20, #0x570]
  13d6e8:      	adrp	x9, 0x13d000 <dsi_display_set_mode+0xff0>
		000000000013d6e8:  R_AARCH64_ADR_PREL_PG_HI21	dsi_display_handle_lp_rx_timeout$4022fdf6e8c0d16dd5fc5f18ee4adc5a.cfi_jt
  13d6ec:      	add	x9, x9, #0x0
		000000000013d6ec:  R_AARCH64_ADD_ABS_LO12_NC	dsi_display_handle_lp_rx_timeout$4022fdf6e8c0d16dd5fc5f18ee4adc5a.cfi_jt
  13d6f0:      	str	x9, [x20, #0x578]
  13d6f4:      	cbz	w8, 0x13d770 <dsi_display_prepare+0x468>
  13d6f8:      	adrp	x10, 0x13d000 <dsi_display_set_mode+0xff0>
		000000000013d6f8:  R_AARCH64_ADR_PREL_PG_HI21	dsi_display_cb_error_handler$4022fdf6e8c0d16dd5fc5f18ee4adc5a.cfi_jt
  13d6fc:      	add	x8, x20, #0xa8
  13d700:      	mov	w9, #0x1                // =1
  13d704:      	add	x10, x10, #0x0
		000000000013d704:  R_AARCH64_ADD_ABS_LO12_NC	dsi_display_cb_error_handler$4022fdf6e8c0d16dd5fc5f18ee4adc5a.cfi_jt
  13d708:      	ldr	x11, [x8], #0x30
  13d70c:      	cmp	x9, #0x1
  13d710:      	str	xzr, [x11, #0x400]
  13d714:      	str	x20, [x11, #0x408]
  13d718:      	str	x10, [x11, #0x410]
  13d71c:      	b.ne	0x13d770 <dsi_display_prepare+0x468>
  13d720:      	ldr	w11, [x20, #0xa0]
  13d724:      	cmp	x9, x11
  13d728:      	add	x9, x9, #0x1
  13d72c:      	b.lo	0x13d708 <dsi_display_prepare+0x400>
  13d730:      	b	0x13d770 <dsi_display_prepare+0x468>
  13d734:      	ldr	x0, [x20, #0x108]
  13d738:      	bl	0x13d738 <dsi_display_prepare+0x430>
		000000000013d738:  R_AARCH64_CALL26	dsi_panel_pre_prepare
  13d73c:      	cbz	w0, 0x13d4a8 <dsi_display_prepare+0x1a0>
  13d740:      	ldr	x3, [x20, #0x20]
  13d744:      	adrp	x1, 0x13d000 <dsi_display_set_mode+0xff0>
		000000000013d744:  R_AARCH64_ADR_PREL_PG_HI21	.rodata+0x48144 // '\x013'
  13d748:      	adrp	x2, 0x13d000 <dsi_display_set_mode+0xff0>
		000000000013d748:  R_AARCH64_ADR_PREL_PG_HI21	.rodata+0x31317 // '*ERROR* [msm-dsi-error]: [%s] panel pre-prepare failed, rc=%d\n'
  13d74c:      	mov	w21, w0
  13d750:      	add	x1, x1, #0x0
		000000000013d750:  R_AARCH64_ADD_ABS_LO12_NC	.rodata+0x48144 // '\x013'
  13d754:      	add	x2, x2, #0x0
		000000000013d754:  R_AARCH64_ADD_ABS_LO12_NC	.rodata+0x31317 // '*ERROR* [msm-dsi-error]: [%s] panel pre-prepare failed, rc=%d\n'
  13d758:      	b	0x13db7c <dsi_display_prepare+0x874>
  13d75c:      	adrp	x1, 0x13d000 <dsi_display_set_mode+0xff0>
		000000000013d75c:  R_AARCH64_ADR_PREL_PG_HI21	.rodata+0x48144 // '\x013'
  13d760:      	adrp	x2, 0x13d000 <dsi_display_set_mode+0xff0>
		000000000013d760:  R_AARCH64_ADR_PREL_PG_HI21	.rodata+0x43176 // '*ERROR* [msm-dsi-error]: failed to create dsi workq!\n'
  13d764:      	add	x1, x1, #0x0
		000000000013d764:  R_AARCH64_ADD_ABS_LO12_NC	.rodata+0x48144 // '\x013'
  13d768:      	add	x2, x2, #0x0
		000000000013d768:  R_AARCH64_ADD_ABS_LO12_NC	.rodata+0x43176 // '*ERROR* [msm-dsi-error]: failed to create dsi workq!\n'
  13d76c:      	bl	0x13d76c <dsi_display_prepare+0x464>
		000000000013d76c:  R_AARCH64_CALL26	drm_dev_printk
  13d770:      	ldrb	w8, [x20, #0x40]
  13d774:      	cbz	w8, 0x13d780 <dsi_display_prepare+0x478>
  13d778:      	mov	w22, #0x1               // =1
  13d77c:      	b	0x13d78c <dsi_display_prepare+0x484>
  13d780:      	ldrb	w8, [x24]
  13d784:      	cmp	w8, #0x0
  13d788:      	cset	w22, ne
  13d78c:      	ldr	w26, [x20, #0x308]
  13d790:      	cmp	w26, #0x3
  13d794:      	b.hs	0x13dc50 <dsi_display_prepare+0x948>
  13d798:      	mov	w8, #0x30               // =48
  13d79c:      	madd	x23, x26, x8, x20
  13d7a0:      	ldr	x0, [x23, #0xa8]!
  13d7a4:      	mov	w1, #0x1                // =1
  13d7a8:      	mov	w2, w22
  13d7ac:      	bl	0x13d7ac <dsi_display_prepare+0x4a4>
		000000000013d7ac:  R_AARCH64_CALL26	dsi_ctrl_set_host_engine_state
  13d7b0:      	cbz	w0, 0x13d800 <dsi_display_prepare+0x4f8>
  13d7b4:      	ldr	x3, [x20, #0x20]
  13d7b8:      	mov	w21, w0
  13d7bc:      	adrp	x1, 0x13d000 <dsi_display_set_mode+0xff0>
		000000000013d7bc:  R_AARCH64_ADR_PREL_PG_HI21	.rodata+0x48144 // '\x013'
  13d7c0:      	adrp	x2, 0x13d000 <dsi_display_set_mode+0xff0>
		000000000013d7c0:  R_AARCH64_ADR_PREL_PG_HI21	.rodata+0x167b6 // '*ERROR* [msm-dsi-error]: [%s]enable host engine failed, skip_op:%d rc:%d\n'
  13d7c4:      	add	x1, x1, #0x0
		000000000013d7c4:  R_AARCH64_ADD_ABS_LO12_NC	.rodata+0x48144 // '\x013'
  13d7c8:      	add	x2, x2, #0x0
		000000000013d7c8:  R_AARCH64_ADD_ABS_LO12_NC	.rodata+0x167b6 // '*ERROR* [msm-dsi-error]: [%s]enable host engine failed, skip_op:%d rc:%d\n'
  13d7cc:      	mov	x0, xzr
  13d7d0:      	mov	w4, w22
  13d7d4:      	mov	w5, w21
  13d7d8:      	bl	0x13d7d8 <dsi_display_prepare+0x4d0>
		000000000013d7d8:  R_AARCH64_CALL26	drm_dev_printk
  13d7dc:      	ldr	x3, [x20, #0x20]
  13d7e0:      	adrp	x1, 0x13d000 <dsi_display_set_mode+0xff0>
		000000000013d7e0:  R_AARCH64_ADR_PREL_PG_HI21	.rodata+0x48144 // '\x013'
  13d7e4:      	adrp	x2, 0x13d000 <dsi_display_set_mode+0xff0>
		000000000013d7e4:  R_AARCH64_ADR_PREL_PG_HI21	.rodata+0x40020 // '*ERROR* [msm-dsi-error]: [%s] failed to enable DSI host, rc=%d\n'
  13d7e8:      	add	x1, x1, #0x0
		000000000013d7e8:  R_AARCH64_ADD_ABS_LO12_NC	.rodata+0x48144 // '\x013'
  13d7ec:      	add	x2, x2, #0x0
		000000000013d7ec:  R_AARCH64_ADD_ABS_LO12_NC	.rodata+0x40020 // '*ERROR* [msm-dsi-error]: [%s] failed to enable DSI host, rc=%d\n'
  13d7f0:      	mov	x0, xzr
  13d7f4:      	mov	w4, w21
  13d7f8:      	bl	0x13d7f8 <dsi_display_prepare+0x4f0>
		000000000013d7f8:  R_AARCH64_CALL26	drm_dev_printk
  13d7fc:      	b	0x13d898 <dsi_display_prepare+0x590>
  13d800:      	ldr	w8, [x20, #0xa0]
  13d804:      	cbz	w8, 0x13d858 <dsi_display_prepare+0x550>
  13d808:      	add	x9, x26, x26, lsl #1
  13d80c:      	add	x26, x20, #0xa8
  13d810:      	lsl	x27, x9, #4
  13d814:      	mov	w28, #0x1               // =1
  13d818:      	cbz	x27, 0x13d838 <dsi_display_prepare+0x530>
  13d81c:      	ldr	x0, [x26]
  13d820:      	cbz	x0, 0x13d838 <dsi_display_prepare+0x530>
  13d824:      	mov	w1, #0x1                // =1
  13d828:      	mov	w2, w22
  13d82c:      	bl	0x13d82c <dsi_display_prepare+0x524>
		000000000013d82c:  R_AARCH64_CALL26	dsi_ctrl_set_host_engine_state
  13d830:      	cbnz	w0, 0x13db8c <dsi_display_prepare+0x884>
  13d834:      	ldr	w8, [x20, #0xa0]
  13d838:      	cmp	x28, #0x1
  13d83c:      	b.ne	0x13d858 <dsi_display_prepare+0x550>
  13d840:      	mov	w9, w8
  13d844:      	cmp	x28, x9
  13d848:      	add	x28, x28, #0x1
  13d84c:      	sub	x27, x27, #0x30
  13d850:      	add	x26, x26, #0x30
  13d854:      	b.lo	0x13d818 <dsi_display_prepare+0x510>
  13d858:      	ldr	x0, [x20, #0x4d0]
  13d85c:      	mov	w1, #0x2                // =2
  13d860:      	mov	w2, #0x1                // =1
  13d864:      	bl	0x13d864 <dsi_display_prepare+0x55c>
		000000000013d864:  R_AARCH64_CALL26	dsi_display_clk_ctrl
  13d868:      	cbz	w0, 0x13daa4 <dsi_display_prepare+0x79c>
  13d86c:      	ldr	x3, [x20, #0x20]
  13d870:      	mov	w21, w0
  13d874:      	adrp	x1, 0x13d000 <dsi_display_set_mode+0xff0>
		000000000013d874:  R_AARCH64_ADR_PREL_PG_HI21	.rodata+0x48144 // '\x013'
  13d878:      	adrp	x2, 0x13d000 <dsi_display_set_mode+0xff0>
		000000000013d878:  R_AARCH64_ADR_PREL_PG_HI21	.rodata+0x164d5 // '*ERROR* [msm-dsi-error]: [%s] failed to enable DSI link clocks, rc=%d\n'
  13d87c:      	add	x1, x1, #0x0
		000000000013d87c:  R_AARCH64_ADD_ABS_LO12_NC	.rodata+0x48144 // '\x013'
  13d880:      	add	x2, x2, #0x0
		000000000013d880:  R_AARCH64_ADD_ABS_LO12_NC	.rodata+0x164d5 // '*ERROR* [msm-dsi-error]: [%s] failed to enable DSI link clocks, rc=%d\n'
  13d884:      	mov	x0, xzr
  13d888:      	mov	w4, w21
  13d88c:      	bl	0x13d88c <dsi_display_prepare+0x584>
		000000000013d88c:  R_AARCH64_CALL26	drm_dev_printk
  13d890:      	mov	x0, x20
  13d894:      	bl	0x13d894 <dsi_display_prepare+0x58c>
		000000000013d894:  R_AARCH64_CALL26	.text+0x13ddd8 // dsi_display_ctrl_host_disable
  13d898:      	ldr	w8, [x20, #0xa0]
  13d89c:      	cbz	w8, 0x13da30 <dsi_display_prepare+0x728>
  13d8a0:      	adrp	x23, 0x13d000 <dsi_display_set_mode+0xff0>
		000000000013d8a0:  R_AARCH64_ADR_PREL_PG_HI21	.rodata+0x48144 // '\x013'
  13d8a4:      	adrp	x24, 0x13d000 <dsi_display_set_mode+0xff0>
		000000000013d8a4:  R_AARCH64_ADR_PREL_PG_HI21	.rodata+0x4f0bd // '*ERROR* [msm-dsi-error]: [%s] failed to deinit host_%d, rc=%d\n'
  13d8a8:      	mov	x22, xzr
  13d8ac:      	add	x26, x20, #0xa8
  13d8b0:      	add	x23, x23, #0x0
		000000000013d8b0:  R_AARCH64_ADD_ABS_LO12_NC	.rodata+0x48144 // '\x013'
  13d8b4:      	add	x24, x24, #0x0
		000000000013d8b4:  R_AARCH64_ADD_ABS_LO12_NC	.rodata+0x4f0bd // '*ERROR* [msm-dsi-error]: [%s] failed to deinit host_%d, rc=%d\n'
  13d8b8:      	ldr	x0, [x26]
  13d8bc:      	bl	0x13d8bc <dsi_display_prepare+0x5b4>
		000000000013d8bc:  R_AARCH64_CALL26	dsi_ctrl_host_deinit
  13d8c0:      	cbz	w0, 0x13d8e0 <dsi_display_prepare+0x5d8>
  13d8c4:      	ldr	x3, [x20, #0x20]
  13d8c8:      	mov	w5, w0
  13d8cc:      	mov	x0, xzr
  13d8d0:      	mov	x1, x23
  13d8d4:      	mov	x2, x24
  13d8d8:      	mov	w4, w22
  13d8dc:      	bl	0x13d8dc <dsi_display_prepare+0x5d4>
		000000000013d8dc:  R_AARCH64_CALL26	drm_dev_printk
  13d8e0:      	cbnz	x22, 0x13da30 <dsi_display_prepare+0x728>
  13d8e4:      	ldr	w8, [x20, #0xa0]
  13d8e8:      	add	x22, x22, #0x1
  13d8ec:      	add	x26, x26, #0x30
  13d8f0:      	cmp	x22, x8
  13d8f4:      	b.lo	0x13d8b8 <dsi_display_prepare+0x5b0>
  13d8f8:      	b	0x13da30 <dsi_display_prepare+0x728>
  13d8fc:      	ldr	w8, [x20, #0xa0]
  13d900:      	cbz	w8, 0x13d930 <dsi_display_prepare+0x628>
  13d904:      	mov	x22, xzr
  13d908:      	add	x23, x20, #0xa8
  13d90c:      	ldr	x0, [x23]
  13d910:      	bl	0x13d910 <dsi_display_prepare+0x608>
		000000000013d910:  R_AARCH64_CALL26	dsi_ctrl_host_timing_update
  13d914:      	cbnz	w0, 0x13daf8 <dsi_display_prepare+0x7f0>
  13d918:      	cbnz	x22, 0x13d930 <dsi_display_prepare+0x628>
  13d91c:      	ldr	w8, [x20, #0xa0]
  13d920:      	add	x22, x22, #0x1
  13d924:      	add	x23, x23, #0x30
  13d928:      	cmp	x22, x8
  13d92c:      	b.lo	0x13d90c <dsi_display_prepare+0x604>
  13d930:      	ldr	x0, [x20, #0x4d0]
  13d934:      	mov	w1, #0x2                // =2
  13d938:      	mov	w2, #0x1                // =1
  13d93c:      	bl	0x13d93c <dsi_display_prepare+0x634>
		000000000013d93c:  R_AARCH64_CALL26	dsi_display_clk_ctrl
  13d940:      	mov	w21, w0
  13d944:      	cbz	w0, 0x13da50 <dsi_display_prepare+0x748>
  13d948:      	ldr	x3, [x20, #0x20]
  13d94c:      	adrp	x1, 0x13d000 <dsi_display_set_mode+0xff0>
		000000000013d94c:  R_AARCH64_ADR_PREL_PG_HI21	.rodata+0x48144 // '\x013'
  13d950:      	adrp	x2, 0x13d000 <dsi_display_set_mode+0xff0>
		000000000013d950:  R_AARCH64_ADR_PREL_PG_HI21	.rodata+0x164d5 // '*ERROR* [msm-dsi-error]: [%s] failed to enable DSI link clocks, rc=%d\n'
  13d954:      	add	x1, x1, #0x0
		000000000013d954:  R_AARCH64_ADD_ABS_LO12_NC	.rodata+0x48144 // '\x013'
  13d958:      	add	x2, x2, #0x0
		000000000013d958:  R_AARCH64_ADD_ABS_LO12_NC	.rodata+0x164d5 // '*ERROR* [msm-dsi-error]: [%s] failed to enable DSI link clocks, rc=%d\n'
  13d95c:      	mov	x0, xzr
  13d960:      	mov	w4, w21
  13d964:      	bl	0x13d964 <dsi_display_prepare+0x65c>
		000000000013d964:  R_AARCH64_CALL26	drm_dev_printk
  13d968:      	ldr	w8, [x20, #0xa0]
  13d96c:      	cbz	w8, 0x13db58 <dsi_display_prepare+0x850>
  13d970:      	adrp	x23, 0x13d000 <dsi_display_set_mode+0xff0>
		000000000013d970:  R_AARCH64_ADR_PREL_PG_HI21	.rodata+0x48144 // '\x013'
  13d974:      	adrp	x24, 0x13d000 <dsi_display_set_mode+0xff0>
		000000000013d974:  R_AARCH64_ADR_PREL_PG_HI21	.rodata+0x4f0bd // '*ERROR* [msm-dsi-error]: [%s] failed to deinit host_%d, rc=%d\n'
  13d978:      	mov	x22, xzr
  13d97c:      	add	x26, x20, #0xa8
  13d980:      	add	x23, x23, #0x0
		000000000013d980:  R_AARCH64_ADD_ABS_LO12_NC	.rodata+0x48144 // '\x013'
  13d984:      	add	x24, x24, #0x0
		000000000013d984:  R_AARCH64_ADD_ABS_LO12_NC	.rodata+0x4f0bd // '*ERROR* [msm-dsi-error]: [%s] failed to deinit host_%d, rc=%d\n'
  13d988:      	ldr	x0, [x26]
  13d98c:      	bl	0x13d98c <dsi_display_prepare+0x684>
		000000000013d98c:  R_AARCH64_CALL26	dsi_ctrl_host_deinit
  13d990:      	cbz	w0, 0x13d9b0 <dsi_display_prepare+0x6a8>
  13d994:      	ldr	x3, [x20, #0x20]
  13d998:      	mov	w5, w0
  13d99c:      	mov	x0, xzr
  13d9a0:      	mov	x1, x23
  13d9a4:      	mov	x2, x24
  13d9a8:      	mov	w4, w22
  13d9ac:      	bl	0x13d9ac <dsi_display_prepare+0x6a4>
		000000000013d9ac:  R_AARCH64_CALL26	drm_dev_printk
  13d9b0:      	cbnz	x22, 0x13db58 <dsi_display_prepare+0x850>
  13d9b4:      	ldr	w8, [x20, #0xa0]
  13d9b8:      	add	x22, x22, #0x1
  13d9bc:      	add	x26, x26, #0x30
  13d9c0:      	cmp	x22, x8
  13d9c4:      	b.lo	0x13d988 <dsi_display_prepare+0x680>
  13d9c8:      	b	0x13db58 <dsi_display_prepare+0x850>
  13d9cc:      	ldr	x3, [x20, #0x20]
  13d9d0:      	mov	w21, w0
  13d9d4:      	adrp	x1, 0x13d000 <dsi_display_set_mode+0xff0>
		000000000013d9d4:  R_AARCH64_ADR_PREL_PG_HI21	.rodata+0x48144 // '\x013'
  13d9d8:      	adrp	x2, 0x13d000 <dsi_display_set_mode+0xff0>
		000000000013d9d8:  R_AARCH64_ADR_PREL_PG_HI21	.rodata+0x1676d // '*ERROR* [msm-dsi-error]: [%s] failed to init host_%d, skip_op=%d, rc=%d\n'
  13d9dc:      	add	x1, x1, #0x0
		000000000013d9dc:  R_AARCH64_ADD_ABS_LO12_NC	.rodata+0x48144 // '\x013'
  13d9e0:      	add	x2, x2, #0x0
		000000000013d9e0:  R_AARCH64_ADD_ABS_LO12_NC	.rodata+0x1676d // '*ERROR* [msm-dsi-error]: [%s] failed to init host_%d, skip_op=%d, rc=%d\n'
  13d9e4:      	mov	x0, xzr
  13d9e8:      	mov	w4, w23
  13d9ec:      	mov	w5, w22
  13d9f0:      	mov	w6, w21
  13d9f4:      	bl	0x13d9f4 <dsi_display_prepare+0x6ec>
		000000000013d9f4:  R_AARCH64_CALL26	drm_dev_printk
  13d9f8:      	cbz	w23, 0x13da10 <dsi_display_prepare+0x708>
  13d9fc:      	sub	w8, w23, #0x1
  13da00:      	mov	w9, #0x30               // =48
  13da04:      	umaddl	x8, w8, w9, x20
  13da08:      	ldr	x0, [x8, #0xa8]
  13da0c:      	bl	0x13da0c <dsi_display_prepare+0x704>
		000000000013da0c:  R_AARCH64_CALL26	dsi_ctrl_host_deinit
  13da10:      	ldr	x3, [x20, #0x20]
  13da14:      	adrp	x1, 0x13d000 <dsi_display_set_mode+0xff0>
		000000000013da14:  R_AARCH64_ADR_PREL_PG_HI21	.rodata+0x48144 // '\x013'
  13da18:      	adrp	x2, 0x13d000 <dsi_display_set_mode+0xff0>
		000000000013da18:  R_AARCH64_ADR_PREL_PG_HI21	.rodata+0x51d8b // '*ERROR* [msm-dsi-error]: [%s] failed to setup DSI controller, rc=%d\n'
  13da1c:      	add	x1, x1, #0x0
		000000000013da1c:  R_AARCH64_ADD_ABS_LO12_NC	.rodata+0x48144 // '\x013'
  13da20:      	add	x2, x2, #0x0
		000000000013da20:  R_AARCH64_ADD_ABS_LO12_NC	.rodata+0x51d8b // '*ERROR* [msm-dsi-error]: [%s] failed to setup DSI controller, rc=%d\n'
  13da24:      	mov	x0, xzr
  13da28:      	mov	w4, w21
  13da2c:      	bl	0x13da2c <dsi_display_prepare+0x724>
		000000000013da2c:  R_AARCH64_CALL26	drm_dev_printk
  13da30:      	mov	x0, x20
  13da34:      	bl	0x13da34 <dsi_display_prepare+0x72c>
		000000000013da34:  R_AARCH64_CALL26	.text+0x13e010 // dsi_display_phy_disable
  13da38:      	ldr	x0, [x20, #0x4d0]
  13da3c:      	mov	w1, #0x1                // =1
  13da40:      	mov	w2, wzr
  13da44:      	bl	0x13da44 <dsi_display_prepare+0x73c>
		000000000013da44:  R_AARCH64_CALL26	dsi_display_clk_ctrl
  13da48:      	ldr	x0, [x20, #0x108]
  13da4c:      	bl	0x13da4c <dsi_display_prepare+0x744>
		000000000013da4c:  R_AARCH64_CALL26	dsi_panel_post_unprepare
  13da50:      	mov	x0, x19
  13da54:      	bl	0x13da54 <dsi_display_prepare+0x74c>
		000000000013da54:  R_AARCH64_CALL26	mutex_unlock
  13da58:      	ldr	x0, [x25]
		000000000013da58:  R_AARCH64_LDST64_ABS_LO12_NC	sde_dbg_base_evtlog
  13da5c:      	adrp	x1, 0x13d000 <dsi_display_set_mode+0xff0>
		000000000013da5c:  R_AARCH64_ADR_PREL_PG_HI21	.rodata+0x4b9f1 // 'dsi_display_prepare'
  13da60:      	mov	w5, #0xbeef             // =48879
  13da64:      	add	x1, x1, #0x0
		000000000013da64:  R_AARCH64_ADD_ABS_LO12_NC	.rodata+0x4b9f1 // 'dsi_display_prepare'
  13da68:      	mov	w2, #0x218d             // =8589
  13da6c:      	mov	w3, #-0x1               // =-1
  13da70:      	mov	w4, #0x2222             // =8738
  13da74:      	movk	w5, #0xc0de, lsl #16
  13da78:      	bl	0x13da78 <dsi_display_prepare+0x770>
		000000000013da78:  R_AARCH64_CALL26	sde_evtlog_log
  13da7c:      	mov	w0, w21
  13da80:      	ldp	x20, x19, [sp, #0x50]
  13da84:      	ldp	x22, x21, [sp, #0x40]
  13da88:      	ldp	x24, x23, [sp, #0x30]
  13da8c:      	ldp	x26, x25, [sp, #0x20]
  13da90:      	ldp	x28, x27, [sp, #0x10]
  13da94:      	ldp	x29, x30, [sp], #0x60
  13da98:      	ldr	x30, [x18, #-0x8]!
  13da9c:      	autiasp
  13daa0:      	ret
  13daa4:      	ldrb	w8, [x20, #0x40]
  13daa8:      	cbnz	w8, 0x13daf0 <dsi_display_prepare+0x7e8>
  13daac:      	ldrb	w8, [x24]
  13dab0:      	cbnz	w8, 0x13daf0 <dsi_display_prepare+0x7e8>
  13dab4:      	ldr	w8, [x20, #0xa0]
  13dab8:      	cbz	w8, 0x13dae8 <dsi_display_prepare+0x7e0>
  13dabc:      	mov	x22, xzr
  13dac0:      	add	x23, x20, #0xa8
  13dac4:      	ldr	x0, [x23]
  13dac8:      	bl	0x13dac8 <dsi_display_prepare+0x7c0>
		000000000013dac8:  R_AARCH64_CALL26	dsi_ctrl_soft_reset
  13dacc:      	cbnz	w0, 0x13dbc8 <dsi_display_prepare+0x8c0>
  13dad0:      	cbnz	x22, 0x13dae8 <dsi_display_prepare+0x7e0>
  13dad4:      	ldr	w8, [x20, #0xa0]
  13dad8:      	add	x22, x22, #0x1
  13dadc:      	add	x23, x23, #0x30
  13dae0:      	cmp	x22, x8
  13dae4:      	b.lo	0x13dac4 <dsi_display_prepare+0x7bc>
  13dae8:      	ldrb	w8, [x20, #0x469]
  13daec:      	cbz	w8, 0x13dc0c <dsi_display_prepare+0x904>
  13daf0:      	mov	w21, wzr
  13daf4:      	b	0x13da50 <dsi_display_prepare+0x748>
  13daf8:      	ldr	x3, [x20, #0x20]
  13dafc:      	mov	w21, w0
  13db00:      	adrp	x1, 0x13d000 <dsi_display_set_mode+0xff0>
		000000000013db00:  R_AARCH64_ADR_PREL_PG_HI21	.rodata+0x48144 // '\x013'
  13db04:      	adrp	x2, 0x13d000 <dsi_display_set_mode+0xff0>
		000000000013db04:  R_AARCH64_ADR_PREL_PG_HI21	.rodata+0x5ae72 // '*ERROR* [msm-dsi-error]: [%s] failed to update host_%d, rc=%d\n'
  13db08:      	add	x1, x1, #0x0
		000000000013db08:  R_AARCH64_ADD_ABS_LO12_NC	.rodata+0x48144 // '\x013'
  13db0c:      	add	x2, x2, #0x0
		000000000013db0c:  R_AARCH64_ADD_ABS_LO12_NC	.rodata+0x5ae72 // '*ERROR* [msm-dsi-error]: [%s] failed to update host_%d, rc=%d\n'
  13db10:      	mov	x0, xzr
  13db14:      	mov	w4, w22
  13db18:      	mov	w5, w21
  13db1c:      	bl	0x13db1c <dsi_display_prepare+0x814>
		000000000013db1c:  R_AARCH64_CALL26	drm_dev_printk
  13db20:      	cbz	w22, 0x13db38 <dsi_display_prepare+0x830>
  13db24:      	sub	w8, w22, #0x1
  13db28:      	mov	w9, #0x30               // =48
  13db2c:      	umaddl	x8, w8, w9, x20
  13db30:      	ldr	x0, [x8, #0xa8]
  13db34:      	bl	0x13db34 <dsi_display_prepare+0x82c>
		000000000013db34:  R_AARCH64_CALL26	dsi_ctrl_host_deinit
  13db38:      	ldr	x3, [x20, #0x20]
  13db3c:      	adrp	x1, 0x13d000 <dsi_display_set_mode+0xff0>
		000000000013db3c:  R_AARCH64_ADR_PREL_PG_HI21	.rodata+0x48144 // '\x013'
  13db40:      	adrp	x2, 0x13d000 <dsi_display_set_mode+0xff0>
		000000000013db40:  R_AARCH64_ADR_PREL_PG_HI21	.rodata+0x31593 // '*ERROR* [msm-dsi-error]: [%s] failed to update DSI controller, rc=%d\n'
  13db44:      	add	x1, x1, #0x0
		000000000013db44:  R_AARCH64_ADD_ABS_LO12_NC	.rodata+0x48144 // '\x013'
  13db48:      	add	x2, x2, #0x0
		000000000013db48:  R_AARCH64_ADD_ABS_LO12_NC	.rodata+0x31593 // '*ERROR* [msm-dsi-error]: [%s] failed to update DSI controller, rc=%d\n'
  13db4c:      	mov	x0, xzr
  13db50:      	mov	w4, w21
  13db54:      	bl	0x13db54 <dsi_display_prepare+0x84c>
		000000000013db54:  R_AARCH64_CALL26	drm_dev_printk
  13db58:      	ldr	x0, [x20, #0x4d0]
  13db5c:      	mov	w1, #0x1                // =1
  13db60:      	mov	w2, wzr
  13db64:      	bl	0x13db64 <dsi_display_prepare+0x85c>
		000000000013db64:  R_AARCH64_CALL26	dsi_display_clk_ctrl
  13db68:      	ldr	x3, [x20, #0x20]
  13db6c:      	adrp	x1, 0x13d000 <dsi_display_set_mode+0xff0>
		000000000013db6c:  R_AARCH64_ADR_PREL_PG_HI21	.rodata+0x48144 // '\x013'
  13db70:      	adrp	x2, 0x13d000 <dsi_display_set_mode+0xff0>
		000000000013db70:  R_AARCH64_ADR_PREL_PG_HI21	.rodata+0x13bd6 // '*ERROR* [msm-dsi-error]: [%s] panel pre-switch failed, rc=%d\n'
  13db74:      	add	x1, x1, #0x0
		000000000013db74:  R_AARCH64_ADD_ABS_LO12_NC	.rodata+0x48144 // '\x013'
  13db78:      	add	x2, x2, #0x0
		000000000013db78:  R_AARCH64_ADD_ABS_LO12_NC	.rodata+0x13bd6 // '*ERROR* [msm-dsi-error]: [%s] panel pre-switch failed, rc=%d\n'
  13db7c:      	mov	x0, xzr
  13db80:      	mov	w4, w21
  13db84:      	bl	0x13db84 <dsi_display_prepare+0x87c>
		000000000013db84:  R_AARCH64_CALL26	drm_dev_printk
  13db88:      	b	0x13da50 <dsi_display_prepare+0x748>
  13db8c:      	ldr	x3, [x20, #0x20]
  13db90:      	mov	w21, w0
  13db94:      	adrp	x1, 0x13d000 <dsi_display_set_mode+0xff0>
		000000000013db94:  R_AARCH64_ADR_PREL_PG_HI21	.rodata+0x48144 // '\x013'
  13db98:      	adrp	x2, 0x13d000 <dsi_display_set_mode+0xff0>
		000000000013db98:  R_AARCH64_ADR_PREL_PG_HI21	.rodata+0x431ac // '*ERROR* [msm-dsi-error]: [%s] enable host engine failed, skip_op:%d rc:%d\n'
  13db9c:      	add	x1, x1, #0x0
		000000000013db9c:  R_AARCH64_ADD_ABS_LO12_NC	.rodata+0x48144 // '\x013'
  13dba0:      	add	x2, x2, #0x0
		000000000013dba0:  R_AARCH64_ADD_ABS_LO12_NC	.rodata+0x431ac // '*ERROR* [msm-dsi-error]: [%s] enable host engine failed, skip_op:%d rc:%d\n'
  13dba4:      	mov	x0, xzr
  13dba8:      	mov	w4, w22
  13dbac:      	mov	w5, w21
  13dbb0:      	bl	0x13dbb0 <dsi_display_prepare+0x8a8>
		000000000013dbb0:  R_AARCH64_CALL26	drm_dev_printk
  13dbb4:      	ldr	x0, [x23]
  13dbb8:      	mov	w1, wzr
  13dbbc:      	mov	w2, w22
  13dbc0:      	bl	0x13dbc0 <dsi_display_prepare+0x8b8>
		000000000013dbc0:  R_AARCH64_CALL26	dsi_ctrl_set_host_engine_state
  13dbc4:      	b	0x13d7dc <dsi_display_prepare+0x4d4>
  13dbc8:      	ldr	x3, [x20, #0x20]
  13dbcc:      	adrp	x23, 0x13d000 <dsi_display_set_mode+0xff0>
		000000000013dbcc:  R_AARCH64_ADR_PREL_PG_HI21	.rodata+0x48144 // '\x013'
  13dbd0:      	mov	w21, w0
  13dbd4:      	add	x23, x23, #0x0
		000000000013dbd4:  R_AARCH64_ADD_ABS_LO12_NC	.rodata+0x48144 // '\x013'
  13dbd8:      	adrp	x2, 0x13d000 <dsi_display_set_mode+0xff0>
		000000000013dbd8:  R_AARCH64_ADR_PREL_PG_HI21	.rodata+0x42eea // '*ERROR* [msm-dsi-error]: [%s] failed to soft reset host_%d, rc=%d\n'
  13dbdc:      	add	x2, x2, #0x0
		000000000013dbdc:  R_AARCH64_ADD_ABS_LO12_NC	.rodata+0x42eea // '*ERROR* [msm-dsi-error]: [%s] failed to soft reset host_%d, rc=%d\n'
  13dbe0:      	mov	x0, xzr
  13dbe4:      	mov	x1, x23
  13dbe8:      	mov	w4, w22
  13dbec:      	mov	w5, w21
  13dbf0:      	bl	0x13dbf0 <dsi_display_prepare+0x8e8>
		000000000013dbf0:  R_AARCH64_CALL26	drm_dev_printk
  13dbf4:      	ldr	x3, [x20, #0x20]
  13dbf8:      	adrp	x2, 0x13d000 <dsi_display_set_mode+0xff0>
		000000000013dbf8:  R_AARCH64_ADR_PREL_PG_HI21	.rodata+0x5ac4f // '*ERROR* [msm-dsi-error]: [%s] failed soft reset, rc=%d\n'
  13dbfc:      	add	x2, x2, #0x0
		000000000013dbfc:  R_AARCH64_ADD_ABS_LO12_NC	.rodata+0x5ac4f // '*ERROR* [msm-dsi-error]: [%s] failed soft reset, rc=%d\n'
  13dc00:      	mov	x0, xzr
  13dc04:      	mov	x1, x23
  13dc08:      	b	0x13dc34 <dsi_display_prepare+0x92c>
  13dc0c:      	ldr	x0, [x20, #0x108]
  13dc10:      	bl	0x13dc10 <dsi_display_prepare+0x908>
		000000000013dc10:  R_AARCH64_CALL26	dsi_panel_prepare
  13dc14:      	mov	w21, w0
  13dc18:      	cbz	w0, 0x13da50 <dsi_display_prepare+0x748>
  13dc1c:      	ldr	x3, [x20, #0x20]
  13dc20:      	adrp	x1, 0x13d000 <dsi_display_set_mode+0xff0>
		000000000013dc20:  R_AARCH64_ADR_PREL_PG_HI21	.rodata+0x48144 // '\x013'
  13dc24:      	adrp	x2, 0x13d000 <dsi_display_set_mode+0xff0>
		000000000013dc24:  R_AARCH64_ADR_PREL_PG_HI21	.rodata+0x57cd4 // '*ERROR* [msm-dsi-error]: [%s] panel prepare failed, rc=%d\n'
  13dc28:      	add	x1, x1, #0x0
		000000000013dc28:  R_AARCH64_ADD_ABS_LO12_NC	.rodata+0x48144 // '\x013'
  13dc2c:      	add	x2, x2, #0x0
		000000000013dc2c:  R_AARCH64_ADD_ABS_LO12_NC	.rodata+0x57cd4 // '*ERROR* [msm-dsi-error]: [%s] panel prepare failed, rc=%d\n'
  13dc30:      	mov	x0, xzr
  13dc34:      	mov	w4, w21
  13dc38:      	bl	0x13dc38 <dsi_display_prepare+0x930>
		000000000013dc38:  R_AARCH64_CALL26	drm_dev_printk
  13dc3c:      	ldr	x0, [x20, #0x4d0]
  13dc40:      	mov	w1, #0x2                // =2
  13dc44:      	mov	w2, wzr
  13dc48:      	bl	0x13dc48 <dsi_display_prepare+0x940>
		000000000013dc48:  R_AARCH64_CALL26	dsi_display_clk_ctrl
  13dc4c:      	b	0x13d890 <dsi_display_prepare+0x588>
  13dc50:      	brk	#0x5512

