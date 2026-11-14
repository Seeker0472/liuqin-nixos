000000000014c1c0 <dsi_panel_pre_prepare>:
  14c1c0:      	paciasp
  14c1c4:      	str	x30, [x18], #0x8
  14c1c8:      	stp	x29, x30, [sp, #-0x30]!
  14c1cc:      	stp	x22, x21, [sp, #0x10]
  14c1d0:      	stp	x20, x19, [sp, #0x20]
  14c1d4:      	mov	x29, sp
  14c1d8:      	cbz	x0, 0x14c228 <dsi_panel_pre_prepare+0x68>
  14c1dc:      	add	x19, x0, #0x3e8
  14c1e0:      	mov	x20, x0
  14c1e4:      	mov	x0, x19
  14c1e8:      	bl	0x14c1e8 <dsi_panel_pre_prepare+0x28>
		000000000014c1e8:  R_AARCH64_CALL26	mutex_lock
  14c1ec:      	ldrb	w8, [x20, #0x8e8]
  14c1f0:      	cbz	w8, 0x14c244 <dsi_panel_pre_prepare+0x84>
  14c1f4:      	ldrb	w8, [x20, #0x8e9]
  14c1f8:      	cbz	w8, 0x14c204 <dsi_panel_pre_prepare+0x44>
  14c1fc:      	ldrb	w8, [x20, #0x8ea]
  14c200:      	cbz	w8, 0x14c27c <dsi_panel_pre_prepare+0xbc>
  14c204:      	add	x0, x20, #0x538
  14c208:      	mov	w1, #0x1                // =1
  14c20c:      	bl	0x14c20c <dsi_panel_pre_prepare+0x4c>
		000000000014c20c:  R_AARCH64_CALL26	dsi_pwr_enable_regulator
  14c210:      	ldrb	w8, [x20, #0x8ea]
  14c214:      	mov	w21, w0
  14c218:      	cbz	w8, 0x14c220 <dsi_panel_pre_prepare+0x60>
  14c21c:      	strb	wzr, [x20, #0x8ea]
  14c220:      	cbnz	w21, 0x14c258 <dsi_panel_pre_prepare+0x98>
  14c224:      	b	0x14c3a4 <dsi_panel_pre_prepare+0x1e4>
  14c228:      	adrp	x1, 0x14c000 <dsi_panel_get_dfps_cmdsets+0x2ac>
		000000000014c228:  R_AARCH64_ADR_PREL_PG_HI21	.rodata+0x48144 // '\x013'
  14c22c:      	adrp	x2, 0x14c000 <dsi_panel_get_dfps_cmdsets+0x2ac>
		000000000014c22c:  R_AARCH64_ADR_PREL_PG_HI21	.rodata+0x5aace // '*ERROR* [msm-dsi-error]: invalid params\n'
  14c230:      	add	x1, x1, #0x0
		000000000014c230:  R_AARCH64_ADD_ABS_LO12_NC	.rodata+0x48144 // '\x013'
  14c234:      	add	x2, x2, #0x0
		000000000014c234:  R_AARCH64_ADD_ABS_LO12_NC	.rodata+0x5aace // '*ERROR* [msm-dsi-error]: invalid params\n'
  14c238:      	bl	0x14c238 <dsi_panel_pre_prepare+0x78>
		000000000014c238:  R_AARCH64_CALL26	drm_dev_printk
  14c23c:      	mov	w21, #-0x16             // =-22
  14c240:      	b	0x14c4b4 <dsi_panel_pre_prepare+0x2f4>
  14c244:      	add	x0, x20, #0x538
  14c248:      	mov	w1, #0x1                // =1
  14c24c:      	bl	0x14c24c <dsi_panel_pre_prepare+0x8c>
		000000000014c24c:  R_AARCH64_CALL26	dsi_pwr_enable_regulator
  14c250:      	mov	w21, w0
  14c254:      	cbz	w21, 0x14c3a4 <dsi_panel_pre_prepare+0x1e4>
  14c258:      	ldr	x3, [x20]
  14c25c:      	adrp	x1, 0x14c000 <dsi_panel_get_dfps_cmdsets+0x2ac>
		000000000014c25c:  R_AARCH64_ADR_PREL_PG_HI21	.rodata+0x48144 // '\x013'
  14c260:      	adrp	x2, 0x14c000 <dsi_panel_get_dfps_cmdsets+0x2ac>
		000000000014c260:  R_AARCH64_ADR_PREL_PG_HI21	.rodata+0x27e0d // '*ERROR* [msm-dsi-error]: [%s] failed to enable vregs, rc=%d\n'
  14c264:      	add	x1, x1, #0x0
		000000000014c264:  R_AARCH64_ADD_ABS_LO12_NC	.rodata+0x48144 // '\x013'
  14c268:      	add	x2, x2, #0x0
		000000000014c268:  R_AARCH64_ADD_ABS_LO12_NC	.rodata+0x27e0d // '*ERROR* [msm-dsi-error]: [%s] failed to enable vregs, rc=%d\n'
  14c26c:      	mov	x0, xzr
  14c270:      	mov	w4, w21
  14c274:      	bl	0x14c274 <dsi_panel_pre_prepare+0xb4>
		000000000014c274:  R_AARCH64_CALL26	drm_dev_printk
  14c278:      	b	0x14c48c <dsi_panel_pre_prepare+0x2cc>
  14c27c:      	ldr	x8, [x20, #0x8e0]
  14c280:      	mov	x9, #0x200              // =512
  14c284:      	movk	x9, #0x5042, lsl #16
  14c288:      	movk	x9, #0x3831, lsl #32
  14c28c:      	movk	x9, #0x4d, lsl #48
  14c290:      	cmp	x8, x9
  14c294:      	b.eq	0x14c32c <dsi_panel_pre_prepare+0x16c>
  14c298:      	mov	x9, #0x200              // =512
  14c29c:      	movk	x9, #0x5036, lsl #16
  14c2a0:      	movk	x9, #0x3831, lsl #32
  14c2a4:      	movk	x9, #0x4d, lsl #48
  14c2a8:      	cmp	x8, x9
  14c2ac:      	b.eq	0x14c32c <dsi_panel_pre_prepare+0x16c>
  14c2b0:      	mov	x9, #0x200              // =512
  14c2b4:      	movk	x9, #0x42, lsl #16
  14c2b8:      	movk	x9, #0x3830, lsl #32
  14c2bc:      	movk	x9, #0x4d, lsl #48
  14c2c0:      	cmp	x8, x9
  14c2c4:      	b.ne	0x14c3a4 <dsi_panel_pre_prepare+0x1e4>
  14c2c8:      	ldr	w8, [x20, #0x5c4]
  14c2cc:      	cmp	w8, #0x1ff
  14c2d0:      	b.hi	0x14c304 <dsi_panel_pre_prepare+0x144>
  14c2d4:      	ldrb	w8, [x20, #0x7ac]
  14c2d8:      	cbnz	w8, 0x14c304 <dsi_panel_pre_prepare+0x144>
  14c2dc:      	adrp	x1, 0x14c000 <dsi_panel_get_dfps_cmdsets+0x2ac>
		000000000014c2dc:  R_AARCH64_ADR_PREL_PG_HI21	.rodata+0x48144 // '\x013'
  14c2e0:      	adrp	x2, 0x14c000 <dsi_panel_get_dfps_cmdsets+0x2ac>
		000000000014c2e0:  R_AARCH64_ADR_PREL_PG_HI21	.rodata+0x28404 // '*ERROR* [msm-dsi-error]: M80 reset 0 !!\n'
  14c2e4:      	add	x1, x1, #0x0
		000000000014c2e4:  R_AARCH64_ADD_ABS_LO12_NC	.rodata+0x48144 // '\x013'
  14c2e8:      	add	x2, x2, #0x0
		000000000014c2e8:  R_AARCH64_ADD_ABS_LO12_NC	.rodata+0x28404 // '*ERROR* [msm-dsi-error]: M80 reset 0 !!\n'
  14c2ec:      	mov	x0, xzr
  14c2f0:      	bl	0x14c2f0 <dsi_panel_pre_prepare+0x130>
		000000000014c2f0:  R_AARCH64_CALL26	drm_dev_printk
  14c2f4:      	ldr	w0, [x20, #0x5c4]
  14c2f8:      	bl	0x14c2f8 <dsi_panel_pre_prepare+0x138>
		000000000014c2f8:  R_AARCH64_CALL26	gpio_to_desc
  14c2fc:      	mov	w1, wzr
  14c300:      	bl	0x14c300 <dsi_panel_pre_prepare+0x140>
		000000000014c300:  R_AARCH64_CALL26	gpiod_set_raw_value
  14c304:      	adrp	x1, 0x14c000 <dsi_panel_get_dfps_cmdsets+0x2ac>
		000000000014c304:  R_AARCH64_ADR_PREL_PG_HI21	.rodata+0x48144 // '\x013'
  14c308:      	adrp	x2, 0x14c000 <dsi_panel_get_dfps_cmdsets+0x2ac>
		000000000014c308:  R_AARCH64_ADR_PREL_PG_HI21	.rodata+0x1fa8c // '*ERROR* [msm-dsi-error]: M80 dsi_panel_power_on mi_dsi_pwr_enable_vregs 1.3v\n'
  14c30c:      	add	x1, x1, #0x0
		000000000014c30c:  R_AARCH64_ADD_ABS_LO12_NC	.rodata+0x48144 // '\x013'
  14c310:      	add	x2, x2, #0x0
		000000000014c310:  R_AARCH64_ADD_ABS_LO12_NC	.rodata+0x1fa8c // '*ERROR* [msm-dsi-error]: M80 dsi_panel_power_on mi_dsi_pwr_enable_vregs 1.3v\n'
  14c314:      	mov	x0, xzr
  14c318:      	bl	0x14c318 <dsi_panel_pre_prepare+0x158>
		000000000014c318:  R_AARCH64_CALL26	drm_dev_printk
  14c31c:      	add	x0, x20, #0x538
  14c320:      	mov	w1, #0x1                // =1
  14c324:      	mov	w2, #0x2                // =2
  14c328:      	b	0x14c3a0 <dsi_panel_pre_prepare+0x1e0>
  14c32c:      	ldr	w8, [x20, #0x5c4]
  14c330:      	cmp	w8, #0x1ff
  14c334:      	b.hi	0x14c368 <dsi_panel_pre_prepare+0x1a8>
  14c338:      	ldrb	w8, [x20, #0x7ac]
  14c33c:      	cbnz	w8, 0x14c368 <dsi_panel_pre_prepare+0x1a8>
  14c340:      	adrp	x1, 0x14c000 <dsi_panel_get_dfps_cmdsets+0x2ac>
		000000000014c340:  R_AARCH64_ADR_PREL_PG_HI21	.rodata+0x48144 // '\x013'
  14c344:      	adrp	x2, 0x14c000 <dsi_panel_get_dfps_cmdsets+0x2ac>
		000000000014c344:  R_AARCH64_ADR_PREL_PG_HI21	.rodata+0x2842d // '*ERROR* [msm-dsi-error]: M81 reset 0 !!\n'
  14c348:      	add	x1, x1, #0x0
		000000000014c348:  R_AARCH64_ADD_ABS_LO12_NC	.rodata+0x48144 // '\x013'
  14c34c:      	add	x2, x2, #0x0
		000000000014c34c:  R_AARCH64_ADD_ABS_LO12_NC	.rodata+0x2842d // '*ERROR* [msm-dsi-error]: M81 reset 0 !!\n'
  14c350:      	mov	x0, xzr
  14c354:      	bl	0x14c354 <dsi_panel_pre_prepare+0x194>
		000000000014c354:  R_AARCH64_CALL26	drm_dev_printk
  14c358:      	ldr	w0, [x20, #0x5c4]
  14c35c:      	bl	0x14c35c <dsi_panel_pre_prepare+0x19c>
		000000000014c35c:  R_AARCH64_CALL26	gpio_to_desc
  14c360:      	mov	w1, wzr
  14c364:      	bl	0x14c364 <dsi_panel_pre_prepare+0x1a4>
		000000000014c364:  R_AARCH64_CALL26	gpiod_set_raw_value
  14c368:      	adrp	x1, 0x14c000 <dsi_panel_get_dfps_cmdsets+0x2ac>
		000000000014c368:  R_AARCH64_ADR_PREL_PG_HI21	.rodata+0x48144 // '\x013'
  14c36c:      	adrp	x2, 0x14c000 <dsi_panel_get_dfps_cmdsets+0x2ac>
		000000000014c36c:  R_AARCH64_ADR_PREL_PG_HI21	.rodata+0x22730 // '*ERROR* [msm-dsi-error]: M81 dsi_panel_power_on mi_dsi_pwr_enable_vregs 1.3v\n'
  14c370:      	add	x1, x1, #0x0
		000000000014c370:  R_AARCH64_ADD_ABS_LO12_NC	.rodata+0x48144 // '\x013'
  14c374:      	add	x2, x2, #0x0
		000000000014c374:  R_AARCH64_ADD_ABS_LO12_NC	.rodata+0x22730 // '*ERROR* [msm-dsi-error]: M81 dsi_panel_power_on mi_dsi_pwr_enable_vregs 1.3v\n'
  14c378:      	mov	x0, xzr
  14c37c:      	bl	0x14c37c <dsi_panel_pre_prepare+0x1bc>
		000000000014c37c:  R_AARCH64_CALL26	drm_dev_printk
  14c380:      	add	x21, x20, #0x538
  14c384:      	mov	w1, #0x1                // =1
  14c388:      	mov	w2, #0x1                // =1
  14c38c:      	mov	x0, x21
  14c390:      	bl	0x14c390 <dsi_panel_pre_prepare+0x1d0>
		000000000014c390:  R_AARCH64_CALL26	mi_dsi_pwr_enable_vregs
  14c394:      	mov	w1, #0x1                // =1
  14c398:      	mov	w2, #0x2                // =2
  14c39c:      	mov	x0, x21
  14c3a0:      	bl	0x14c3a0 <dsi_panel_pre_prepare+0x1e0>
		000000000014c3a0:  R_AARCH64_CALL26	mi_dsi_pwr_enable_vregs
  14c3a4:      	ldrb	w8, [x20, #0x486]
  14c3a8:      	cbz	w8, 0x14c3bc <dsi_panel_pre_prepare+0x1fc>
  14c3ac:      	ldrb	w8, [x20, #0x7a8]
  14c3b0:      	cbz	w8, 0x14c418 <dsi_panel_pre_prepare+0x258>
  14c3b4:      	mov	w21, wzr
  14c3b8:      	b	0x14c4ac <dsi_panel_pre_prepare+0x2ec>
  14c3bc:      	ldr	x0, [x20, #0x5d8]
  14c3c0:      	cbz	x0, 0x14c3ac <dsi_panel_pre_prepare+0x1ec>
  14c3c4:      	ldr	x1, [x20, #0x5e0]
  14c3c8:      	bl	0x14c3c8 <dsi_panel_pre_prepare+0x208>
		000000000014c3c8:  R_AARCH64_CALL26	pinctrl_select_state
  14c3cc:      	cbz	w0, 0x14c3ac <dsi_panel_pre_prepare+0x1ec>
  14c3d0:      	ldr	x3, [x20]
  14c3d4:      	adrp	x22, 0x14c000 <dsi_panel_get_dfps_cmdsets+0x2ac>
		000000000014c3d4:  R_AARCH64_ADR_PREL_PG_HI21	.rodata+0x48144 // '\x013'
  14c3d8:      	mov	w21, w0
  14c3dc:      	add	x22, x22, #0x0
		000000000014c3dc:  R_AARCH64_ADD_ABS_LO12_NC	.rodata+0x48144 // '\x013'
  14c3e0:      	adrp	x2, 0x14c000 <dsi_panel_get_dfps_cmdsets+0x2ac>
		000000000014c3e0:  R_AARCH64_ADR_PREL_PG_HI21	.rodata+0x3a5ff // '*ERROR* [msm-dsi-error]: [%s] failed to set pin state, rc=%d\n'
  14c3e4:      	add	x2, x2, #0x0
		000000000014c3e4:  R_AARCH64_ADD_ABS_LO12_NC	.rodata+0x3a5ff // '*ERROR* [msm-dsi-error]: [%s] failed to set pin state, rc=%d\n'
  14c3e8:      	mov	x0, xzr
  14c3ec:      	mov	x1, x22
  14c3f0:      	mov	w4, w21
  14c3f4:      	bl	0x14c3f4 <dsi_panel_pre_prepare+0x234>
		000000000014c3f4:  R_AARCH64_CALL26	drm_dev_printk
  14c3f8:      	ldr	x3, [x20]
  14c3fc:      	adrp	x2, 0x14c000 <dsi_panel_get_dfps_cmdsets+0x2ac>
		000000000014c3fc:  R_AARCH64_ADR_PREL_PG_HI21	.rodata+0x49475 // '*ERROR* [msm-dsi-error]: [%s] failed to set pinctrl, rc=%d\n'
  14c400:      	add	x2, x2, #0x0
		000000000014c400:  R_AARCH64_ADD_ABS_LO12_NC	.rodata+0x49475 // '*ERROR* [msm-dsi-error]: [%s] failed to set pinctrl, rc=%d\n'
  14c404:      	mov	x0, xzr
  14c408:      	mov	x1, x22
  14c40c:      	mov	w4, w21
  14c410:      	bl	0x14c410 <dsi_panel_pre_prepare+0x250>
		000000000014c410:  R_AARCH64_CALL26	drm_dev_printk
  14c414:      	b	0x14c480 <dsi_panel_pre_prepare+0x2c0>
  14c418:      	mov	x0, x20
  14c41c:      	bl	0x14c41c <dsi_panel_pre_prepare+0x25c>
		000000000014c41c:  R_AARCH64_CALL26	.text+0x14cd4c // dsi_panel_reset
  14c420:      	mov	w21, w0
  14c424:      	cbz	w0, 0x14c4ac <dsi_panel_pre_prepare+0x2ec>
  14c428:      	ldr	x3, [x20]
  14c42c:      	adrp	x1, 0x14c000 <dsi_panel_get_dfps_cmdsets+0x2ac>
		000000000014c42c:  R_AARCH64_ADR_PREL_PG_HI21	.rodata+0x48144 // '\x013'
  14c430:      	adrp	x2, 0x14c000 <dsi_panel_get_dfps_cmdsets+0x2ac>
		000000000014c430:  R_AARCH64_ADR_PREL_PG_HI21	.rodata+0x467b6 // '*ERROR* [msm-dsi-error]: [%s] failed to reset panel, rc=%d\n'
  14c434:      	add	x1, x1, #0x0
		000000000014c434:  R_AARCH64_ADD_ABS_LO12_NC	.rodata+0x48144 // '\x013'
  14c438:      	add	x2, x2, #0x0
		000000000014c438:  R_AARCH64_ADD_ABS_LO12_NC	.rodata+0x467b6 // '*ERROR* [msm-dsi-error]: [%s] failed to reset panel, rc=%d\n'
  14c43c:      	mov	x0, xzr
  14c440:      	mov	w4, w21
  14c444:      	bl	0x14c444 <dsi_panel_pre_prepare+0x284>
		000000000014c444:  R_AARCH64_CALL26	drm_dev_printk
  14c448:      	ldr	w0, [x20, #0x5c8]
  14c44c:      	cmp	w0, #0x1ff
  14c450:      	b.hi	0x14c460 <dsi_panel_pre_prepare+0x2a0>
  14c454:      	bl	0x14c454 <dsi_panel_pre_prepare+0x294>
		000000000014c454:  R_AARCH64_CALL26	gpio_to_desc
  14c458:      	mov	w1, wzr
  14c45c:      	bl	0x14c45c <dsi_panel_pre_prepare+0x29c>
		000000000014c45c:  R_AARCH64_CALL26	gpiod_set_raw_value
  14c460:      	ldr	w0, [x20, #0x58c]
  14c464:      	cmp	w0, #0x1ff
  14c468:      	b.hi	0x14c478 <dsi_panel_pre_prepare+0x2b8>
  14c46c:      	bl	0x14c46c <dsi_panel_pre_prepare+0x2ac>
		000000000014c46c:  R_AARCH64_CALL26	gpio_to_desc
  14c470:      	mov	w1, wzr
  14c474:      	bl	0x14c474 <dsi_panel_pre_prepare+0x2b4>
		000000000014c474:  R_AARCH64_CALL26	gpiod_set_raw_value
  14c478:      	ldrb	w8, [x20, #0x486]
  14c47c:      	cbz	w8, 0x14c4d0 <dsi_panel_pre_prepare+0x310>
  14c480:      	add	x0, x20, #0x538
  14c484:      	mov	w1, wzr
  14c488:      	bl	0x14c488 <dsi_panel_pre_prepare+0x2c8>
		000000000014c488:  R_AARCH64_CALL26	dsi_pwr_enable_regulator
  14c48c:      	ldr	x3, [x20]
  14c490:      	adrp	x1, 0x14c000 <dsi_panel_get_dfps_cmdsets+0x2ac>
		000000000014c490:  R_AARCH64_ADR_PREL_PG_HI21	.rodata+0x48144 // '\x013'
  14c494:      	adrp	x2, 0x14c000 <dsi_panel_get_dfps_cmdsets+0x2ac>
		000000000014c494:  R_AARCH64_ADR_PREL_PG_HI21	.rodata+0x403cb // '*ERROR* [msm-dsi-error]: [%s] panel power on failed, rc=%d\n'
  14c498:      	add	x1, x1, #0x0
		000000000014c498:  R_AARCH64_ADD_ABS_LO12_NC	.rodata+0x48144 // '\x013'
  14c49c:      	add	x2, x2, #0x0
		000000000014c49c:  R_AARCH64_ADD_ABS_LO12_NC	.rodata+0x403cb // '*ERROR* [msm-dsi-error]: [%s] panel power on failed, rc=%d\n'
  14c4a0:      	mov	x0, xzr
  14c4a4:      	mov	w4, w21
  14c4a8:      	bl	0x14c4a8 <dsi_panel_pre_prepare+0x2e8>
		000000000014c4a8:  R_AARCH64_CALL26	drm_dev_printk
  14c4ac:      	mov	x0, x19
  14c4b0:      	bl	0x14c4b0 <dsi_panel_pre_prepare+0x2f0>
		000000000014c4b0:  R_AARCH64_CALL26	mutex_unlock
  14c4b4:      	mov	w0, w21
  14c4b8:      	ldp	x20, x19, [sp, #0x20]
  14c4bc:      	ldp	x22, x21, [sp, #0x10]
  14c4c0:      	ldp	x29, x30, [sp], #0x30
  14c4c4:      	ldr	x30, [x18, #-0x8]!
  14c4c8:      	autiasp
  14c4cc:      	ret
  14c4d0:      	ldr	x0, [x20, #0x5d8]
  14c4d4:      	cbz	x0, 0x14c480 <dsi_panel_pre_prepare+0x2c0>
  14c4d8:      	ldr	x1, [x20, #0x5e8]
  14c4dc:      	bl	0x14c4dc <dsi_panel_pre_prepare+0x31c>
		000000000014c4dc:  R_AARCH64_CALL26	pinctrl_select_state
  14c4e0:      	cbz	w0, 0x14c480 <dsi_panel_pre_prepare+0x2c0>
  14c4e4:      	ldr	x3, [x20]
  14c4e8:      	adrp	x1, 0x14c000 <dsi_panel_get_dfps_cmdsets+0x2ac>
		000000000014c4e8:  R_AARCH64_ADR_PREL_PG_HI21	.rodata+0x48144 // '\x013'
  14c4ec:      	adrp	x2, 0x14c000 <dsi_panel_get_dfps_cmdsets+0x2ac>
		000000000014c4ec:  R_AARCH64_ADR_PREL_PG_HI21	.rodata+0x3a5ff // '*ERROR* [msm-dsi-error]: [%s] failed to set pin state, rc=%d\n'
  14c4f0:      	mov	w4, w0
  14c4f4:      	add	x1, x1, #0x0
		000000000014c4f4:  R_AARCH64_ADD_ABS_LO12_NC	.rodata+0x48144 // '\x013'
  14c4f8:      	add	x2, x2, #0x0
		000000000014c4f8:  R_AARCH64_ADD_ABS_LO12_NC	.rodata+0x3a5ff // '*ERROR* [msm-dsi-error]: [%s] failed to set pin state, rc=%d\n'
  14c4fc:      	mov	x0, xzr
  14c500:      	b	0x14c410 <dsi_panel_pre_prepare+0x250>

