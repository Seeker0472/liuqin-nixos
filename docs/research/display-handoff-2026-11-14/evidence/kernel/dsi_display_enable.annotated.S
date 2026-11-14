000000000013ebf8 <dsi_display_enable>:
  13ebf8:      	paciasp
  13ebfc:      	sub	sp, sp, #0xa0
  13ec00:      	str	x30, [x18], #0x8
  13ec04:      	stp	x29, x30, [sp, #0x50]
  13ec08:      	str	x25, [sp, #0x60]
  13ec0c:      	stp	x24, x23, [sp, #0x70]
  13ec10:      	stp	x22, x21, [sp, #0x80]
  13ec14:      	stp	x20, x19, [sp, #0x90]
  13ec18:      	add	x29, sp, #0x50
  13ec1c:      	adrp	x8, 0x13e000 <dsi_display_ctrl_host_disable+0x228>
		000000000013ec1c:  R_AARCH64_ADR_PREL_PG_HI21	__stack_chk_guard
  13ec20:      	ldr	x8, [x8]
		000000000013ec20:  R_AARCH64_LDST64_ABS_LO12_NC	__stack_chk_guard
  13ec24:      	stur	x8, [x29, #-0x8]
  13ec28:      	stp	xzr, xzr, [sp, #0x38]
  13ec2c:      	stp	xzr, xzr, [sp, #0x28]
  13ec30:      	stp	xzr, xzr, [sp, #0x18]
  13ec34:      	stp	xzr, xzr, [sp, #0x8]
  13ec38:      	cbz	x0, 0x13ecc4 <dsi_display_enable+0xcc>
  13ec3c:      	ldr	x8, [x0, #0x108]
  13ec40:      	mov	x19, x0
  13ec44:      	cbz	x8, 0x13ecc4 <dsi_display_enable+0xcc>
  13ec48:      	ldr	x24, [x19, #0x10]
  13ec4c:      	cbz	x24, 0x13ecc4 <dsi_display_enable+0xcc>
  13ec50:      	ldr	x8, [x8, #0x520]
  13ec54:      	cbz	x8, 0x13ed1c <dsi_display_enable+0x124>
  13ec58:      	adrp	x23, 0x13e000 <dsi_display_ctrl_host_disable+0x228>
		000000000013ec58:  R_AARCH64_ADR_PREL_PG_HI21	sde_dbg_base_evtlog
  13ec5c:      	ldr	x0, [x23]
		000000000013ec5c:  R_AARCH64_LDST64_ABS_LO12_NC	sde_dbg_base_evtlog
  13ec60:      	adrp	x1, 0x13e000 <dsi_display_ctrl_host_disable+0x228>
		000000000013ec60:  R_AARCH64_ADR_PREL_PG_HI21	.rodata+0x27c3f // 'dsi_display_enable'
  13ec64:      	mov	w5, #0xbeef             // =48879
  13ec68:      	add	x1, x1, #0x0
		000000000013ec68:  R_AARCH64_ADD_ABS_LO12_NC	.rodata+0x27c3f // 'dsi_display_enable'
  13ec6c:      	mov	w2, #0x22b6             // =8886
  13ec70:      	mov	w3, #-0x1               // =-1
  13ec74:      	mov	w4, #0x1111             // =4369
  13ec78:      	movk	w5, #0xc0de, lsl #16
  13ec7c:      	bl	0x13ec7c <dsi_display_enable+0x84>
		000000000013ec7c:  R_AARCH64_CALL26	sde_evtlog_log
  13ec80:      	ldrb	w8, [x19, #0x40]
  13ec84:      	cbnz	w8, 0x13ec90 <dsi_display_enable+0x98>
  13ec88:      	ldrb	w8, [x19, #0x651]
  13ec8c:      	cbz	w8, 0x13eecc <dsi_display_enable+0x2d4>
  13ec90:      	mov	x0, x19
  13ec94:      	bl	0x13ec94 <dsi_display_enable+0x9c>
		000000000013ec94:  R_AARCH64_CALL26	dsi_display_config_ctrl_for_cont_splash
  13ec98:      	mov	x0, x19
  13ec9c:      	bl	0x13ec9c <dsi_display_enable+0xa4>
		000000000013ec9c:  R_AARCH64_CALL26	dsi_display_splash_res_cleanup
  13eca0:      	cbz	w0, 0x13ed30 <dsi_display_enable+0x138>
  13eca4:      	adrp	x1, 0x13e000 <dsi_display_ctrl_host_disable+0x228>
		000000000013eca4:  R_AARCH64_ADR_PREL_PG_HI21	.rodata+0x48144 // '\x013'
  13eca8:      	adrp	x2, 0x13e000 <dsi_display_ctrl_host_disable+0x228>
		000000000013eca8:  R_AARCH64_ADR_PREL_PG_HI21	.rodata+0x2e33f // '*ERROR* [msm-dsi-error]: Continuous splash res cleanup failed, rc=%d\n'
  13ecac:      	mov	w3, w0
  13ecb0:      	add	x1, x1, #0x0
		000000000013ecb0:  R_AARCH64_ADD_ABS_LO12_NC	.rodata+0x48144 // '\x013'
  13ecb4:      	add	x2, x2, #0x0
		000000000013ecb4:  R_AARCH64_ADD_ABS_LO12_NC	.rodata+0x2e33f // '*ERROR* [msm-dsi-error]: Continuous splash res cleanup failed, rc=%d\n'
  13ecb8:      	mov	x0, xzr
  13ecbc:      	bl	0x13ecbc <dsi_display_enable+0xc4>
		000000000013ecbc:  R_AARCH64_CALL26	drm_dev_printk
  13ecc0:      	b	0x13ecdc <dsi_display_enable+0xe4>
  13ecc4:      	adrp	x1, 0x13e000 <dsi_display_ctrl_host_disable+0x228>
		000000000013ecc4:  R_AARCH64_ADR_PREL_PG_HI21	.rodata+0x48144 // '\x013'
  13ecc8:      	adrp	x2, 0x13e000 <dsi_display_ctrl_host_disable+0x228>
		000000000013ecc8:  R_AARCH64_ADR_PREL_PG_HI21	.rodata+0x1bf30 // '*ERROR* [msm-dsi-error]: Invalid params\n'
  13eccc:      	add	x1, x1, #0x0
		000000000013eccc:  R_AARCH64_ADD_ABS_LO12_NC	.rodata+0x48144 // '\x013'
  13ecd0:      	add	x2, x2, #0x0
		000000000013ecd0:  R_AARCH64_ADD_ABS_LO12_NC	.rodata+0x1bf30 // '*ERROR* [msm-dsi-error]: Invalid params\n'
  13ecd4:      	mov	x0, xzr
  13ecd8:      	bl	0x13ecd8 <dsi_display_enable+0xe0>
		000000000013ecd8:  R_AARCH64_CALL26	drm_dev_printk
  13ecdc:      	mov	w22, #-0x16             // =-22
  13ece0:      	adrp	x9, 0x13e000 <dsi_display_ctrl_host_disable+0x228>
		000000000013ece0:  R_AARCH64_ADR_PREL_PG_HI21	__stack_chk_guard
  13ece4:      	ldur	x8, [x29, #-0x8]
  13ece8:      	ldr	x9, [x9]
		000000000013ece8:  R_AARCH64_LDST64_ABS_LO12_NC	__stack_chk_guard
  13ecec:      	cmp	x9, x8
  13ecf0:      	b.ne	0x13f2b0 <dsi_display_enable+0x6b8>
  13ecf4:      	ldp	x29, x30, [sp, #0x50]
  13ecf8:      	mov	w0, w22
  13ecfc:      	ldp	x20, x19, [sp, #0x90]
  13ed00:      	ldp	x22, x21, [sp, #0x80]
  13ed04:      	ldp	x24, x23, [sp, #0x70]
  13ed08:      	ldr	x25, [sp, #0x60]
  13ed0c:      	ldr	x30, [x18, #-0x8]!
  13ed10:      	add	sp, sp, #0xa0
  13ed14:      	autiasp
  13ed18:      	ret
  13ed1c:      	adrp	x1, 0x13e000 <dsi_display_ctrl_host_disable+0x228>
		000000000013ed1c:  R_AARCH64_ADR_PREL_PG_HI21	.rodata+0x48144 // '\x013'
  13ed20:      	adrp	x2, 0x13e000 <dsi_display_ctrl_host_disable+0x228>
		000000000013ed20:  R_AARCH64_ADR_PREL_PG_HI21	.rodata+0x36dc4 // '*ERROR* [msm-dsi-error]: no valid mode set for the display\n'
  13ed24:      	add	x1, x1, #0x0
		000000000013ed24:  R_AARCH64_ADD_ABS_LO12_NC	.rodata+0x48144 // '\x013'
  13ed28:      	add	x2, x2, #0x0
		000000000013ed28:  R_AARCH64_ADD_ABS_LO12_NC	.rodata+0x36dc4 // '*ERROR* [msm-dsi-error]: no valid mode set for the display\n'
  13ed2c:      	b	0x13ecd4 <dsi_display_enable+0xdc>
  13ed30:      	ldr	x8, [x19, #0x108]
  13ed34:      	mov	w9, #0x1                // =1
  13ed38:      	adrp	x1, 0x13e000 <dsi_display_ctrl_host_disable+0x228>
		000000000013ed38:  R_AARCH64_ADR_PREL_PG_HI21	.rodata+0x214be // '\x016'
  13ed3c:      	adrp	x2, 0x13e000 <dsi_display_ctrl_host_disable+0x228>
		000000000013ed3c:  R_AARCH64_ADR_PREL_PG_HI21	.rodata+0x1f450 // '[msm-dsi-info]: cont splash enabled, display enable not required\n'
  13ed40:      	strb	w9, [x8, #0x7b4]
  13ed44:      	ldr	x8, [x19, #0x108]
  13ed48:      	add	x1, x1, #0x0
		000000000013ed48:  R_AARCH64_ADD_ABS_LO12_NC	.rodata+0x214be // '\x016'
  13ed4c:      	add	x2, x2, #0x0
		000000000013ed4c:  R_AARCH64_ADD_ABS_LO12_NC	.rodata+0x1f450 // '[msm-dsi-info]: cont splash enabled, display enable not required\n'
  13ed50:      	mov	x0, xzr
  13ed54:      	str	wzr, [x8, #0x884]
  13ed58:      	ldr	x8, [x19, #0x108]
  13ed5c:      	str	w9, [x8, #0xc3c]
  13ed60:      	bl	0x13ed60 <dsi_display_enable+0x168>
		000000000013ed60:  R_AARCH64_CALL26	drm_dev_printk
  13ed64:      	ldr	x4, [x19, #0x648]
  13ed68:      	cmn	x4, #0x1
  13ed6c:      	b.eq	0x13edb0 <dsi_display_enable+0x1b8>
  13ed70:      	ldr	x8, [x19, #0xa8]
  13ed74:      	ldr	x20, [x8, #0x4c0]
  13ed78:      	cbz	x20, 0x13edb0 <dsi_display_enable+0x1b8>
  13ed7c:      	adrp	x9, 0x13e000 <dsi_display_ctrl_host_disable+0x228>
		000000000013ed7c:  R_AARCH64_ADR_PREL_PG_HI21	__typeid__ZTSFiPvjjjjjjE_global_addr
  13ed80:      	add	x9, x9, #0x0
		000000000013ed80:  R_AARCH64_ADD_ABS_LO12_NC	__typeid__ZTSFiPvjjjjjjE_global_addr
  13ed84:      	sub	x9, x20, x9
  13ed88:      	ror	x9, x9, #0x3
  13ed8c:      	cmp	x9, #0x2
  13ed90:      	b.hs	0x13f2b4 <dsi_display_enable+0x6bc>
  13ed94:      	ldr	x0, [x8, #0x4b8]
  13ed98:      	ldr	w1, [x8, #0x4b0]
  13ed9c:      	lsr	x3, x4, #32
  13eda0:      	mov	w2, wzr
  13eda4:      	mov	w5, wzr
  13eda8:      	mov	w6, wzr
  13edac:      	blr	x20
  13edb0:      	ldr	x0, [x19, #0x108]
  13edb4:      	bl	0x13edb4 <dsi_display_enable+0x1bc>
		000000000013edb4:  R_AARCH64_CALL26	mi_get_panel_id_by_dsi_panel
  13edb8:      	cmp	w0, #0x14
  13edbc:      	b.ne	0x13edec <dsi_display_enable+0x1f4>
  13edc0:      	mov	x0, x19
  13edc4:      	bl	0x13edc4 <dsi_display_enable+0x1cc>
		000000000013edc4:  R_AARCH64_CALL26	mi_dsi_display_read_panel_build_id
  13edc8:      	cmp	w0, #0x0
  13edcc:      	b.gt	0x13edec <dsi_display_enable+0x1f4>
  13edd0:      	ldr	x3, [x19, #0x20]
  13edd4:      	adrp	x1, 0x13e000 <dsi_display_ctrl_host_disable+0x228>
		000000000013edd4:  R_AARCH64_ADR_PREL_PG_HI21	.rodata+0x214be // '\x016'
  13edd8:      	adrp	x2, 0x13e000 <dsi_display_ctrl_host_disable+0x228>
		000000000013edd8:  R_AARCH64_ADR_PREL_PG_HI21	.rodata+0x31356 // '[msm-dsi-info]: [%s] DSI display read panel build id failed\n'
  13eddc:      	add	x1, x1, #0x0
		000000000013eddc:  R_AARCH64_ADD_ABS_LO12_NC	.rodata+0x214be // '\x016'
  13ede0:      	add	x2, x2, #0x0
		000000000013ede0:  R_AARCH64_ADD_ABS_LO12_NC	.rodata+0x31356 // '[msm-dsi-info]: [%s] DSI display read panel build id failed\n'
  13ede4:      	mov	x0, xzr
  13ede8:      	bl	0x13ede8 <dsi_display_enable+0x1f0>
		000000000013ede8:  R_AARCH64_CALL26	drm_dev_printk
  13edec:      	ldr	x0, [x19, #0x108]
  13edf0:      	bl	0x13edf0 <dsi_display_enable+0x1f8>
		000000000013edf0:  R_AARCH64_CALL26	mi_get_panel_id_by_dsi_panel
  13edf4:      	cmp	w0, #0x5
  13edf8:      	b.eq	0x13ee0c <dsi_display_enable+0x214>
  13edfc:      	ldr	x0, [x19, #0x108]
  13ee00:      	bl	0x13ee00 <dsi_display_enable+0x208>
		000000000013ee00:  R_AARCH64_CALL26	mi_get_panel_id_by_dsi_panel
  13ee04:      	cmp	w0, #0x6
  13ee08:      	b.ne	0x13ee50 <dsi_display_enable+0x258>
  13ee0c:      	ldr	x8, [x19, #0x108]
  13ee10:      	ldrb	w8, [x8, #0xa3d]
  13ee14:      	cbnz	w8, 0x13ee50 <dsi_display_enable+0x258>
  13ee18:      	adrp	x1, 0x13e000 <dsi_display_ctrl_host_disable+0x228>
		000000000013ee18:  R_AARCH64_ADR_PREL_PG_HI21	.rodata+0x214be // '\x016'
  13ee1c:      	adrp	x2, 0x13e000 <dsi_display_ctrl_host_disable+0x228>
		000000000013ee1c:  R_AARCH64_ADR_PREL_PG_HI21	.rodata+0x5d81d // '[msm-dsi-info]: uefi_read_lhbm_success is false, read in kernel.\n'
  13ee20:      	add	x1, x1, #0x0
		000000000013ee20:  R_AARCH64_ADD_ABS_LO12_NC	.rodata+0x214be // '\x016'
  13ee24:      	add	x2, x2, #0x0
		000000000013ee24:  R_AARCH64_ADD_ABS_LO12_NC	.rodata+0x5d81d // '[msm-dsi-info]: uefi_read_lhbm_success is false, read in kernel.\n'
  13ee28:      	mov	x0, xzr
  13ee2c:      	bl	0x13ee2c <dsi_display_enable+0x234>
		000000000013ee2c:  R_AARCH64_CALL26	drm_dev_printk
  13ee30:      	ldr	x20, [x19, #0x108]
  13ee34:      	add	x21, x20, #0x3e8
  13ee38:      	mov	x0, x21
  13ee3c:      	bl	0x13ee3c <dsi_display_enable+0x244>
		000000000013ee3c:  R_AARCH64_CALL26	mutex_lock
  13ee40:      	mov	x0, x20
  13ee44:      	bl	0x13ee44 <dsi_display_enable+0x24c>
		000000000013ee44:  R_AARCH64_CALL26	mi_dsi_panel_read_lhbm_white_param_locked
  13ee48:      	mov	x0, x21
  13ee4c:      	bl	0x13ee4c <dsi_display_enable+0x254>
		000000000013ee4c:  R_AARCH64_CALL26	mutex_unlock
  13ee50:      	ldr	x0, [x19, #0x108]
  13ee54:      	bl	0x13ee54 <dsi_display_enable+0x25c>
		000000000013ee54:  R_AARCH64_CALL26	mi_get_panel_id_by_dsi_panel
  13ee58:      	cmp	w0, #0x1
  13ee5c:      	b.eq	0x13ee80 <dsi_display_enable+0x288>
  13ee60:      	ldr	x0, [x19, #0x108]
  13ee64:      	bl	0x13ee64 <dsi_display_enable+0x26c>
		000000000013ee64:  R_AARCH64_CALL26	mi_get_panel_id_by_dsi_panel
  13ee68:      	cmp	w0, #0x8
  13ee6c:      	b.eq	0x13ee80 <dsi_display_enable+0x288>
  13ee70:      	ldr	x0, [x19, #0x108]
  13ee74:      	bl	0x13ee74 <dsi_display_enable+0x27c>
		000000000013ee74:  R_AARCH64_CALL26	mi_get_panel_id_by_dsi_panel
  13ee78:      	cmp	w0, #0x9
  13ee7c:      	b.ne	0x13ee88 <dsi_display_enable+0x290>
  13ee80:      	mov	x0, x19
  13ee84:      	bl	0x13ee84 <dsi_display_enable+0x28c>
		000000000013ee84:  R_AARCH64_CALL26	mi_dsi_display_manufacturer_info_init
  13ee88:      	ldr	x0, [x19, #0x108]
  13ee8c:      	bl	0x13ee8c <dsi_display_enable+0x294>
		000000000013ee8c:  R_AARCH64_CALL26	mi_get_panel_id_by_dsi_panel
  13ee90:      	cmp	w0, #0xc
  13ee94:      	b.ne	0x13eec4 <dsi_display_enable+0x2cc>
  13ee98:      	ldr	x0, [x19, #0x108]
  13ee9c:      	bl	0x13ee9c <dsi_display_enable+0x2a4>
		000000000013ee9c:  R_AARCH64_CALL26	mi_dsi_panel_update_vdc_param
  13eea0:      	cbz	w0, 0x13eec4 <dsi_display_enable+0x2cc>
  13eea4:      	ldr	x3, [x19, #0x20]
  13eea8:      	adrp	x1, 0x13e000 <dsi_display_ctrl_host_disable+0x228>
		000000000013eea8:  R_AARCH64_ADR_PREL_PG_HI21	.rodata+0x48144 // '\x013'
  13eeac:      	adrp	x2, 0x13e000 <dsi_display_ctrl_host_disable+0x228>
		000000000013eeac:  R_AARCH64_ADR_PREL_PG_HI21	.rodata+0x1c330 // '*ERROR* [msm-dsi-error]: [%s] failed to update vdc_enabled param, rc=%d\n'
  13eeb0:      	mov	w4, w0
  13eeb4:      	add	x1, x1, #0x0
		000000000013eeb4:  R_AARCH64_ADD_ABS_LO12_NC	.rodata+0x48144 // '\x013'
  13eeb8:      	add	x2, x2, #0x0
		000000000013eeb8:  R_AARCH64_ADD_ABS_LO12_NC	.rodata+0x1c330 // '*ERROR* [msm-dsi-error]: [%s] failed to update vdc_enabled param, rc=%d\n'
  13eebc:      	mov	x0, xzr
  13eec0:      	bl	0x13eec0 <dsi_display_enable+0x2c8>
		000000000013eec0:  R_AARCH64_CALL26	drm_dev_printk
  13eec4:      	mov	w22, wzr
  13eec8:      	b	0x13ece0 <dsi_display_enable+0xe8>
  13eecc:      	add	x20, x19, #0x48
  13eed0:      	mov	x0, x20
  13eed4:      	bl	0x13eed4 <dsi_display_enable+0x2dc>
		000000000013eed4:  R_AARCH64_CALL26	mutex_lock
  13eed8:      	ldr	x21, [x19, #0x108]
  13eedc:      	ldr	x25, [x21, #0x520]
  13eee0:      	ldrb	w8, [x25, #0x94]
  13eee4:      	tbnz	w8, #0x3, 0x13ef18 <dsi_display_enable+0x320>
  13eee8:      	ldrb	w8, [x19, #0x469]
  13eeec:      	cbnz	w8, 0x13ef2c <dsi_display_enable+0x334>
  13eef0:      	mov	x0, x21
  13eef4:      	bl	0x13eef4 <dsi_display_enable+0x2fc>
		000000000013eef4:  R_AARCH64_CALL26	dsi_panel_enable
  13eef8:      	cbz	w0, 0x13ef2c <dsi_display_enable+0x334>
  13eefc:      	ldr	x3, [x19, #0x20]
  13ef00:      	adrp	x1, 0x13e000 <dsi_display_ctrl_host_disable+0x228>
		000000000013ef00:  R_AARCH64_ADR_PREL_PG_HI21	.rodata+0x48144 // '\x013'
  13ef04:      	adrp	x2, 0x13e000 <dsi_display_ctrl_host_disable+0x228>
		000000000013ef04:  R_AARCH64_ADR_PREL_PG_HI21	.rodata+0x54ab9 // '*ERROR* [msm-dsi-error]: [%s] failed to enable DSI panel, rc=%d\n'
  13ef08:      	mov	w22, w0
  13ef0c:      	add	x1, x1, #0x0
		000000000013ef0c:  R_AARCH64_ADD_ABS_LO12_NC	.rodata+0x48144 // '\x013'
  13ef10:      	add	x2, x2, #0x0
		000000000013ef10:  R_AARCH64_ADD_ABS_LO12_NC	.rodata+0x54ab9 // '*ERROR* [msm-dsi-error]: [%s] failed to enable DSI panel, rc=%d\n'
  13ef14:      	b	0x13f1f8 <dsi_display_enable+0x600>
  13ef18:      	mov	x0, x21
  13ef1c:      	bl	0x13ef1c <dsi_display_enable+0x324>
		000000000013ef1c:  R_AARCH64_CALL26	dsi_panel_post_switch
  13ef20:      	cbz	w0, 0x13ef2c <dsi_display_enable+0x334>
  13ef24:      	mov	w22, w0
  13ef28:      	b	0x13f1e4 <dsi_display_enable+0x5ec>
  13ef2c:      	ldr	x4, [x19, #0x648]
  13ef30:      	cmn	x4, #0x1
  13ef34:      	b.eq	0x13ef78 <dsi_display_enable+0x380>
  13ef38:      	ldr	x8, [x19, #0xa8]
  13ef3c:      	ldr	x22, [x8, #0x4c0]
  13ef40:      	cbz	x22, 0x13ef78 <dsi_display_enable+0x380>
  13ef44:      	adrp	x9, 0x13e000 <dsi_display_ctrl_host_disable+0x228>
		000000000013ef44:  R_AARCH64_ADR_PREL_PG_HI21	__typeid__ZTSFiPvjjjjjjE_global_addr
  13ef48:      	add	x9, x9, #0x0
		000000000013ef48:  R_AARCH64_ADD_ABS_LO12_NC	__typeid__ZTSFiPvjjjjjjE_global_addr
  13ef4c:      	sub	x9, x22, x9
  13ef50:      	ror	x9, x9, #0x3
  13ef54:      	cmp	x9, #0x2
  13ef58:      	b.hs	0x13f2d8 <dsi_display_enable+0x6e0>
  13ef5c:      	ldr	x0, [x8, #0x4b8]
  13ef60:      	ldr	w1, [x8, #0x4b0]
  13ef64:      	lsr	x3, x4, #32
  13ef68:      	mov	w2, wzr
  13ef6c:      	mov	w5, wzr
  13ef70:      	mov	w6, wzr
  13ef74:      	blr	x22
  13ef78:      	ldr	x8, [x25, #0xa8]
  13ef7c:      	ldrb	w9, [x8, #0xd10]
  13ef80:      	cbnz	w9, 0x13ef8c <dsi_display_enable+0x394>
  13ef84:      	ldrb	w8, [x8, #0xd11]
  13ef88:      	cbz	w8, 0x13efbc <dsi_display_enable+0x3c4>
  13ef8c:      	ldrb	w8, [x25, #0x94]
  13ef90:      	tbnz	w8, #0x6, 0x13efbc <dsi_display_enable+0x3c4>
  13ef94:      	ldr	x0, [x19, #0x108]
  13ef98:      	bl	0x13ef98 <dsi_display_enable+0x3a0>
		000000000013ef98:  R_AARCH64_CALL26	dsi_panel_update_pps
  13ef9c:      	cbz	w0, 0x13efbc <dsi_display_enable+0x3c4>
  13efa0:      	ldr	x3, [x19, #0x20]
  13efa4:      	adrp	x1, 0x13e000 <dsi_display_ctrl_host_disable+0x228>
		000000000013efa4:  R_AARCH64_ADR_PREL_PG_HI21	.rodata+0x48144 // '\x013'
  13efa8:      	adrp	x2, 0x13e000 <dsi_display_ctrl_host_disable+0x228>
		000000000013efa8:  R_AARCH64_ADR_PREL_PG_HI21	.rodata+0x46055 // '*ERROR* [msm-dsi-error]: [%s] panel pps cmd update failed, rc=%d\n'
  13efac:      	mov	w22, w0
  13efb0:      	add	x1, x1, #0x0
		000000000013efb0:  R_AARCH64_ADD_ABS_LO12_NC	.rodata+0x48144 // '\x013'
  13efb4:      	add	x2, x2, #0x0
		000000000013efb4:  R_AARCH64_ADD_ABS_LO12_NC	.rodata+0x46055 // '*ERROR* [msm-dsi-error]: [%s] panel pps cmd update failed, rc=%d\n'
  13efb8:      	b	0x13f1f8 <dsi_display_enable+0x600>
  13efbc:      	ldr	x0, [x19, #0x108]
  13efc0:      	bl	0x13efc0 <dsi_display_enable+0x3c8>
		000000000013efc0:  R_AARCH64_CALL26	is_target_fps_support_dc
  13efc4:      	ldr	x8, [x19, #0x108]
  13efc8:      	tbz	w0, #0x0, 0x13f000 <dsi_display_enable+0x408>
  13efcc:      	ldr	w9, [x8, #0x90c]
  13efd0:      	cmp	w9, #0x1
  13efd4:      	b.ne	0x13f030 <dsi_display_enable+0x438>
  13efd8:      	ldr	w9, [x8, #0xbf8]
  13efdc:      	cbnz	w9, 0x13f030 <dsi_display_enable+0x438>
  13efe0:      	mov	w1, #0x1                // =1
  13efe4:      	mov	x0, x8
  13efe8:      	bl	0x13efe8 <dsi_display_enable+0x3f0>
		000000000013efe8:  R_AARCH64_CALL26	mi_dsi_panel_set_dc_mode
  13efec:      	adrp	x1, 0x13e000 <dsi_display_ctrl_host_disable+0x228>
		000000000013efec:  R_AARCH64_ADR_PREL_PG_HI21	.rodata+0x214be // '\x016'
  13eff0:      	adrp	x2, 0x13e000 <dsi_display_ctrl_host_disable+0x228>
		000000000013eff0:  R_AARCH64_ADR_PREL_PG_HI21	.rodata+0x4ef17 // '[msm-dsi-info]: turn on DC mode\n'
  13eff4:      	add	x1, x1, #0x0
		000000000013eff4:  R_AARCH64_ADD_ABS_LO12_NC	.rodata+0x214be // '\x016'
  13eff8:      	add	x2, x2, #0x0
		000000000013eff8:  R_AARCH64_ADD_ABS_LO12_NC	.rodata+0x4ef17 // '[msm-dsi-info]: turn on DC mode\n'
  13effc:      	b	0x13f028 <dsi_display_enable+0x430>
  13f000:      	ldr	w9, [x8, #0xbf8]
  13f004:      	cmp	w9, #0x1
  13f008:      	b.ne	0x13f030 <dsi_display_enable+0x438>
  13f00c:      	mov	x0, x8
  13f010:      	mov	w1, wzr
  13f014:      	bl	0x13f014 <dsi_display_enable+0x41c>
		000000000013f014:  R_AARCH64_CALL26	mi_dsi_panel_set_dc_mode
  13f018:      	adrp	x1, 0x13f000 <dsi_display_enable+0x408>
		000000000013f018:  R_AARCH64_ADR_PREL_PG_HI21	.rodata+0x214be // '\x016'
  13f01c:      	adrp	x2, 0x13f000 <dsi_display_enable+0x408>
		000000000013f01c:  R_AARCH64_ADR_PREL_PG_HI21	.rodata+0x4302e // '[msm-dsi-info]: turn off DC mode\n'
  13f020:      	add	x1, x1, #0x0
		000000000013f020:  R_AARCH64_ADD_ABS_LO12_NC	.rodata+0x214be // '\x016'
  13f024:      	add	x2, x2, #0x0
		000000000013f024:  R_AARCH64_ADD_ABS_LO12_NC	.rodata+0x4302e // '[msm-dsi-info]: turn off DC mode\n'
  13f028:      	mov	x0, xzr
  13f02c:      	bl	0x13f02c <dsi_display_enable+0x434>
		000000000013f02c:  R_AARCH64_CALL26	drm_dev_printk
  13f030:      	ldr	x8, [x19, #0x108]
  13f034:      	ldr	w9, [x8, #0x93c]
  13f038:      	cbz	w9, 0x13f06c <dsi_display_enable+0x474>
  13f03c:      	ldr	w8, [x8, #0xbfc]
  13f040:      	cmp	w8, w9
  13f044:      	b.eq	0x13f06c <dsi_display_enable+0x474>
  13f048:      	ldr	w1, [x21, #0x93c]
  13f04c:      	mov	x0, x21
  13f050:      	bl	0x13f050 <dsi_display_enable+0x458>
		000000000013f050:  R_AARCH64_CALL26	mi_dsi_panel_gray_by_temperature
  13f054:      	adrp	x8, 0x13f000 <dsi_display_enable+0x408>
		000000000013f054:  R_AARCH64_ADR_PREL_PG_HI21	disp_debugfs.llvm.7998175196853619090+0x1
  13f058:      	ldrb	w8, [x8]
		000000000013f058:  R_AARCH64_LDST8_ABS_LO12_NC	disp_debugfs.llvm.7998175196853619090+0x1
  13f05c:      	cbz	w8, 0x13f06c <dsi_display_enable+0x474>
  13f060:      	adrp	x0, 0x13f000 <dsi_display_enable+0x408>
		000000000013f060:  R_AARCH64_ADR_PREL_PG_HI21	.rodata+0x13c14 // '[D]turn on DBI mode\n'
  13f064:      	add	x0, x0, #0x0
		000000000013f064:  R_AARCH64_ADD_ABS_LO12_NC	.rodata+0x13c14 // '[D]turn on DBI mode\n'
  13f068:      	bl	0x13f068 <dsi_display_enable+0x470>
		000000000013f068:  R_AARCH64_CALL26	mi_disp_dbg
  13f06c:      	ldrb	w8, [x25, #0x94]
  13f070:      	tbnz	w8, #0x3, 0x13f0cc <dsi_display_enable+0x4d4>
  13f074:      	ldr	w8, [x19, #0x330]
  13f078:      	cmp	w8, #0x2
  13f07c:      	b.eq	0x13f234 <dsi_display_enable+0x63c>
  13f080:      	cmp	w8, #0x1
  13f084:      	b.ne	0x13f284 <dsi_display_enable+0x68c>
  13f088:      	adrp	x2, 0x13f000 <dsi_display_enable+0x408>
		000000000013f088:  R_AARCH64_ADR_PREL_PG_HI21	.rodata+0x46097 // '[msm-dsi-debug]: %s:enable video timing eng\n'
  13f08c:      	adrp	x3, 0x13f000 <dsi_display_enable+0x408>
		000000000013f08c:  R_AARCH64_ADR_PREL_PG_HI21	.rodata+0x27c3f // 'dsi_display_enable'
  13f090:      	add	x2, x2, #0x0
		000000000013f090:  R_AARCH64_ADD_ABS_LO12_NC	.rodata+0x46097 // '[msm-dsi-debug]: %s:enable video timing eng\n'
  13f094:      	add	x3, x3, #0x0
		000000000013f094:  R_AARCH64_ADD_ABS_LO12_NC	.rodata+0x27c3f // 'dsi_display_enable'
  13f098:      	mov	w1, #0x1                // =1
  13f09c:      	mov	x0, xzr
  13f0a0:      	bl	0x13f0a0 <dsi_display_enable+0x4a8>
		000000000013f0a0:  R_AARCH64_CALL26	drm_dev_dbg
  13f0a4:      	mov	x0, x19
  13f0a8:      	bl	0x13f0a8 <dsi_display_enable+0x4b0>
		000000000013f0a8:  R_AARCH64_CALL26	.text+0x13e778 // dsi_display_vid_engine_enable
  13f0ac:      	mov	w22, w0
  13f0b0:      	cbz	w0, 0x13f204 <dsi_display_enable+0x60c>
  13f0b4:      	ldr	x3, [x19, #0x20]
  13f0b8:      	adrp	x1, 0x13f000 <dsi_display_enable+0x408>
		000000000013f0b8:  R_AARCH64_ADR_PREL_PG_HI21	.rodata+0x48144 // '\x013'
  13f0bc:      	adrp	x2, 0x13f000 <dsi_display_enable+0x408>
		000000000013f0bc:  R_AARCH64_ADR_PREL_PG_HI21	.rodata+0x1c2e9 // '*ERROR* [msm-dsi-error]: [%s]failed to enable DSI video engine, rc=%d\n'
  13f0c0:      	add	x1, x1, #0x0
		000000000013f0c0:  R_AARCH64_ADD_ABS_LO12_NC	.rodata+0x48144 // '\x013'
  13f0c4:      	add	x2, x2, #0x0
		000000000013f0c4:  R_AARCH64_ADD_ABS_LO12_NC	.rodata+0x1c2e9 // '*ERROR* [msm-dsi-error]: [%s]failed to enable DSI video engine, rc=%d\n'
  13f0c8:      	b	0x13f274 <dsi_display_enable+0x67c>
  13f0cc:      	ldr	w4, [x25, #0x10]
  13f0d0:      	mrs	x21, SP_EL0
  13f0d4:      	cbz	w4, 0x13f170 <dsi_display_enable+0x578>
  13f0d8:      	nop
  13f0dc:      	b	0x13f178 <dsi_display_enable+0x580>
  13f0e0:      	bti	j
  13f0e4:      	adrp	x9, 0x13f000 <dsi_display_enable+0x408>
		000000000013f0e4:  R_AARCH64_ADR_PREL_PG_HI21	cpu_number
  13f0e8:      	mrs	x8, TPIDR_EL1
  13f0ec:      	add	x9, x9, #0x0
		000000000013f0ec:  R_AARCH64_ADD_ABS_LO12_NC	cpu_number
  13f0f0:      	ldr	w8, [x8, x9]
  13f0f4:      	adrp	x10, 0x13f000 <dsi_display_enable+0x408>
		000000000013f0f4:  R_AARCH64_ADR_PREL_PG_HI21	__cpu_online_mask
  13f0f8:      	add	x10, x10, #0x0
		000000000013f0f8:  R_AARCH64_ADD_ABS_LO12_NC	__cpu_online_mask
  13f0fc:      	add	w9, w8, #0x3f
  13f100:      	cmp	w8, #0x0
  13f104:      	csel	w9, w9, w8, lt
  13f108:      	asr	w9, w9, #6
  13f10c:      	ldr	x9, [x10, w9, sxtw #3]
  13f110:      	lsr	x8, x9, x8
  13f114:      	tbz	w8, #0x0, 0x13f178 <dsi_display_enable+0x580>
  13f118:      	add	x22, x21, #0x18
  13f11c:      	ldar	w8, [x22]
  13f120:      	add	w8, w8, #0x1
  13f124:      	str	w8, [x21, #0x18]
  13f128:      	adrp	x8, 0x13f000 <dsi_display_enable+0x408>
		000000000013f128:  R_AARCH64_ADR_PREL_PG_HI21	__tracepoint_tracing_mark_write+0x40
  13f12c:      	add	x8, x8, #0x0
		000000000013f12c:  R_AARCH64_ADD_ABS_LO12_NC	__tracepoint_tracing_mark_write+0x40
  13f130:      	ldar	x8, [x8]
  13f134:      	cbz	x8, 0x13f150 <dsi_display_enable+0x558>
  13f138:      	ldr	x0, [x8, #0x8]
  13f13c:      	adrp	x3, 0x13f000 <dsi_display_enable+0x408>
		000000000013f13c:  R_AARCH64_ADR_PREL_PG_HI21	.rodata+0x48f00 // 'ddic_fps'
  13f140:      	add	x3, x3, #0x0
		000000000013f140:  R_AARCH64_ADD_ABS_LO12_NC	.rodata+0x48f00 // 'ddic_fps'
  13f144:      	mov	w1, #0x43               // =67
  13f148:      	mov	x2, x21
  13f14c:      	bl	0x13f14c <dsi_display_enable+0x554>
		000000000013f14c:  R_AARCH64_CALL26	__traceiter_tracing_mark_write
  13f150:      	ldar	x8, [x22]
  13f154:      	subs	x8, x8, #0x1
  13f158:      	str	w8, [x21, #0x18]
  13f15c:      	b.eq	0x13f4b0 <dsi_display_enable+0x8b8>
  13f160:      	add	x8, x21, #0x18
  13f164:      	ldar	x8, [x8]
  13f168:      	cbnz	x8, 0x13f178 <dsi_display_enable+0x580>
  13f16c:      	b	0x13f4b0 <dsi_display_enable+0x8b8>
  13f170:      	ldr	w4, [x25, #0x2c]
  13f174:      	nop
  13f178:      	ldr	w3, [x25]
  13f17c:      	ldr	w4, [x25, #0x18]
  13f180:      	ldr	w5, [x25, #0x2c]
  13f184:      	ldr	w6, [x25, #0x10]
  13f188:      	adrp	x2, 0x13f000 <dsi_display_enable+0x408>
		000000000013f188:  R_AARCH64_ADR_PREL_PG_HI21	.rodata+0x24af // 'dsi_panel_switch:%dx%dx%d:%d'
  13f18c:      	add	x2, x2, #0x0
		000000000013f18c:  R_AARCH64_ADD_ABS_LO12_NC	.rodata+0x24af // 'dsi_panel_switch:%dx%dx%d:%d'
  13f190:      	add	x0, sp, #0x8
  13f194:      	mov	w1, #0x40               // =64
  13f198:      	bl	0x13f198 <dsi_display_enable+0x5a0>
		000000000013f198:  R_AARCH64_CALL26	snprintf
  13f19c:      	nop
  13f1a0:      	ldr	x0, [x19, #0x108]
  13f1a4:      	bl	0x13f1a4 <dsi_display_enable+0x5ac>
		000000000013f1a4:  R_AARCH64_CALL26	dsi_panel_switch
  13f1a8:      	ldr	x8, [x19, #0x108]
  13f1ac:      	mov	w22, w0
  13f1b0:      	mov	x0, x8
  13f1b4:      	bl	0x13f1b4 <dsi_display_enable+0x5bc>
		000000000013f1b4:  R_AARCH64_CALL26	mi_get_panel_id_by_dsi_panel
  13f1b8:      	cmp	w0, #0xa
  13f1bc:      	b.eq	0x13f1d0 <dsi_display_enable+0x5d8>
  13f1c0:      	ldr	x0, [x19, #0x108]
  13f1c4:      	bl	0x13f1c4 <dsi_display_enable+0x5cc>
		000000000013f1c4:  R_AARCH64_CALL26	mi_get_panel_id_by_dsi_panel
  13f1c8:      	cmp	w0, #0xb
  13f1cc:      	b.ne	0x13f1dc <dsi_display_enable+0x5e4>
  13f1d0:      	ldr	x0, [x24, #0x728]
  13f1d4:      	mov	w1, #0x2                // =2
  13f1d8:      	bl	0x13f1d8 <dsi_display_enable+0x5e0>
		000000000013f1d8:  R_AARCH64_CALL26	sde_encoder_wait_for_event
  13f1dc:      	nop
  13f1e0:      	cbz	w22, 0x13f204 <dsi_display_enable+0x60c>
  13f1e4:      	ldr	x3, [x19, #0x20]
  13f1e8:      	adrp	x1, 0x13f000 <dsi_display_enable+0x408>
		000000000013f1e8:  R_AARCH64_ADR_PREL_PG_HI21	.rodata+0x48144 // '\x013'
  13f1ec:      	adrp	x2, 0x13f000 <dsi_display_enable+0x408>
		000000000013f1ec:  R_AARCH64_ADR_PREL_PG_HI21	.rodata+0x25220 // '*ERROR* [msm-dsi-error]: [%s] failed to switch DSI panel mode, rc=%d\n'
  13f1f0:      	add	x1, x1, #0x0
		000000000013f1f0:  R_AARCH64_ADD_ABS_LO12_NC	.rodata+0x48144 // '\x013'
  13f1f4:      	add	x2, x2, #0x0
		000000000013f1f4:  R_AARCH64_ADD_ABS_LO12_NC	.rodata+0x25220 // '*ERROR* [msm-dsi-error]: [%s] failed to switch DSI panel mode, rc=%d\n'
  13f1f8:      	mov	x0, xzr
  13f1fc:      	mov	w4, w22
  13f200:      	bl	0x13f200 <dsi_display_enable+0x608>
		000000000013f200:  R_AARCH64_CALL26	drm_dev_printk
  13f204:      	mov	x0, x20
  13f208:      	bl	0x13f208 <dsi_display_enable+0x610>
		000000000013f208:  R_AARCH64_CALL26	mutex_unlock
  13f20c:      	ldr	x0, [x23]
		000000000013f20c:  R_AARCH64_LDST64_ABS_LO12_NC	sde_dbg_base_evtlog
  13f210:      	adrp	x1, 0x13f000 <dsi_display_enable+0x408>
		000000000013f210:  R_AARCH64_ADR_PREL_PG_HI21	.rodata+0x27c3f // 'dsi_display_enable'
  13f214:      	mov	w5, #0xbeef             // =48879
  13f218:      	add	x1, x1, #0x0
		000000000013f218:  R_AARCH64_ADD_ABS_LO12_NC	.rodata+0x27c3f // 'dsi_display_enable'
  13f21c:      	mov	w2, #0x2352             // =9042
  13f220:      	mov	w3, #-0x1               // =-1
  13f224:      	mov	w4, #0x2222             // =8738
  13f228:      	movk	w5, #0xc0de, lsl #16
  13f22c:      	bl	0x13f22c <dsi_display_enable+0x634>
		000000000013f22c:  R_AARCH64_CALL26	sde_evtlog_log
  13f230:      	b	0x13ece0 <dsi_display_enable+0xe8>
  13f234:      	adrp	x2, 0x13f000 <dsi_display_enable+0x408>
		000000000013f234:  R_AARCH64_ADR_PREL_PG_HI21	.rodata+0x36e00 // '[msm-dsi-debug]: %s:enable command timing eng\n'
  13f238:      	adrp	x3, 0x13f000 <dsi_display_enable+0x408>
		000000000013f238:  R_AARCH64_ADR_PREL_PG_HI21	.rodata+0x27c3f // 'dsi_display_enable'
  13f23c:      	add	x2, x2, #0x0
		000000000013f23c:  R_AARCH64_ADD_ABS_LO12_NC	.rodata+0x36e00 // '[msm-dsi-debug]: %s:enable command timing eng\n'
  13f240:      	add	x3, x3, #0x0
		000000000013f240:  R_AARCH64_ADD_ABS_LO12_NC	.rodata+0x27c3f // 'dsi_display_enable'
  13f244:      	mov	w1, #0x1                // =1
  13f248:      	mov	x0, xzr
  13f24c:      	bl	0x13f24c <dsi_display_enable+0x654>
		000000000013f24c:  R_AARCH64_CALL26	drm_dev_dbg
  13f250:      	mov	x0, x19
  13f254:      	bl	0x13f254 <dsi_display_enable+0x65c>
		000000000013f254:  R_AARCH64_CALL26	.text+0x13e8e0 // dsi_display_cmd_engine_enable
  13f258:      	mov	w22, w0
  13f25c:      	cbz	w0, 0x13f204 <dsi_display_enable+0x60c>
  13f260:      	ldr	x3, [x19, #0x20]
  13f264:      	adrp	x1, 0x13f000 <dsi_display_enable+0x408>
		000000000013f264:  R_AARCH64_ADR_PREL_PG_HI21	.rodata+0x48144 // '\x013'
  13f268:      	adrp	x2, 0x13f000 <dsi_display_enable+0x408>
		000000000013f268:  R_AARCH64_ADR_PREL_PG_HI21	.rodata+0x4eed2 // '*ERROR* [msm-dsi-error]: [%s]failed to enable DSI cmd engine, rc=%d\n'
  13f26c:      	add	x1, x1, #0x0
		000000000013f26c:  R_AARCH64_ADD_ABS_LO12_NC	.rodata+0x48144 // '\x013'
  13f270:      	add	x2, x2, #0x0
		000000000013f270:  R_AARCH64_ADD_ABS_LO12_NC	.rodata+0x4eed2 // '*ERROR* [msm-dsi-error]: [%s]failed to enable DSI cmd engine, rc=%d\n'
  13f274:      	mov	x0, xzr
  13f278:      	mov	w4, w22
  13f27c:      	bl	0x13f27c <dsi_display_enable+0x684>
		000000000013f27c:  R_AARCH64_CALL26	drm_dev_printk
  13f280:      	b	0x13f2a4 <dsi_display_enable+0x6ac>
  13f284:      	ldr	x3, [x19, #0x20]
  13f288:      	adrp	x1, 0x13f000 <dsi_display_enable+0x408>
		000000000013f288:  R_AARCH64_ADR_PREL_PG_HI21	.rodata+0x48144 // '\x013'
  13f28c:      	adrp	x2, 0x13f000 <dsi_display_enable+0x408>
		000000000013f28c:  R_AARCH64_ADR_PREL_PG_HI21	.rodata+0x27cf7 // '*ERROR* [msm-dsi-error]: [%s] Invalid configuration\n'
  13f290:      	add	x1, x1, #0x0
		000000000013f290:  R_AARCH64_ADD_ABS_LO12_NC	.rodata+0x48144 // '\x013'
  13f294:      	add	x2, x2, #0x0
		000000000013f294:  R_AARCH64_ADD_ABS_LO12_NC	.rodata+0x27cf7 // '*ERROR* [msm-dsi-error]: [%s] Invalid configuration\n'
  13f298:      	mov	x0, xzr
  13f29c:      	bl	0x13f29c <dsi_display_enable+0x6a4>
		000000000013f29c:  R_AARCH64_CALL26	drm_dev_printk
  13f2a0:      	mov	w22, #-0x16             // =-22
  13f2a4:      	ldr	x0, [x19, #0x108]
  13f2a8:      	bl	0x13f2a8 <dsi_display_enable+0x6b0>
		000000000013f2a8:  R_AARCH64_CALL26	dsi_panel_disable
  13f2ac:      	b	0x13f204 <dsi_display_enable+0x60c>
  13f2b0:      	bl	0x13f2b0 <dsi_display_enable+0x6b8>
		000000000013f2b0:  R_AARCH64_CALL26	__stack_chk_fail
  13f2b4:      	mov	x0, #0x9213             // =37395
  13f2b8:      	movk	x0, #0xcfa3, lsl #16
  13f2bc:      	movk	x0, #0x6f9b, lsl #32
  13f2c0:      	movk	x0, #0x1e33, lsl #48
  13f2c4:      	mov	x1, x20
  13f2c8:      	bl	0x13f2c8 <dsi_display_enable+0x6d0>
		000000000013f2c8:  R_AARCH64_CALL26	__cfi_slowpath
  13f2cc:      	ldr	x8, [x19, #0xa8]
  13f2d0:      	ldr	x4, [x19, #0x648]
  13f2d4:      	b	0x13ed94 <dsi_display_enable+0x19c>
  13f2d8:      	mov	x0, #0x9213             // =37395
  13f2dc:      	movk	x0, #0xcfa3, lsl #16
  13f2e0:      	movk	x0, #0x6f9b, lsl #32
  13f2e4:      	movk	x0, #0x1e33, lsl #48
  13f2e8:      	mov	x1, x22
  13f2ec:      	bl	0x13f2ec <dsi_display_enable+0x6f4>
		000000000013f2ec:  R_AARCH64_CALL26	__cfi_slowpath
  13f2f0:      	ldr	x8, [x19, #0xa8]
  13f2f4:      	ldr	x4, [x19, #0x648]
  13f2f8:      	b	0x13ef5c <dsi_display_enable+0x364>
  13f2fc:      	bti	j
  13f300:      	adrp	x9, 0x13f000 <dsi_display_enable+0x408>
		000000000013f300:  R_AARCH64_ADR_PREL_PG_HI21	cpu_number
  13f304:      	mrs	x8, TPIDR_EL1
  13f308:      	add	x9, x9, #0x0
		000000000013f308:  R_AARCH64_ADD_ABS_LO12_NC	cpu_number
  13f30c:      	ldr	w8, [x8, x9]
  13f310:      	adrp	x10, 0x13f000 <dsi_display_enable+0x408>
		000000000013f310:  R_AARCH64_ADR_PREL_PG_HI21	__cpu_online_mask
  13f314:      	add	x10, x10, #0x0
		000000000013f314:  R_AARCH64_ADD_ABS_LO12_NC	__cpu_online_mask
  13f318:      	add	w9, w8, #0x3f
  13f31c:      	cmp	w8, #0x0
  13f320:      	csel	w9, w9, w8, lt
  13f324:      	asr	w9, w9, #6
  13f328:      	ldr	x9, [x10, w9, sxtw #3]
  13f32c:      	lsr	x8, x9, x8
  13f330:      	tbz	w8, #0x0, 0x13f1a0 <dsi_display_enable+0x5a8>
  13f334:      	add	x22, x21, #0x18
  13f338:      	ldar	w8, [x22]
  13f33c:      	add	w8, w8, #0x1
  13f340:      	str	w8, [x21, #0x18]
  13f344:      	adrp	x8, 0x13f000 <dsi_display_enable+0x408>
		000000000013f344:  R_AARCH64_ADR_PREL_PG_HI21	__tracepoint_tracing_mark_write+0x40
  13f348:      	add	x8, x8, #0x0
		000000000013f348:  R_AARCH64_ADD_ABS_LO12_NC	__tracepoint_tracing_mark_write+0x40
  13f34c:      	ldar	x8, [x8]
  13f350:      	cbz	x8, 0x13f36c <dsi_display_enable+0x774>
  13f354:      	ldr	x0, [x8, #0x8]
  13f358:      	add	x3, sp, #0x8
  13f35c:      	mov	w1, #0x42               // =66
  13f360:      	mov	x2, x21
  13f364:      	mov	w4, wzr
  13f368:      	bl	0x13f368 <dsi_display_enable+0x770>
		000000000013f368:  R_AARCH64_CALL26	__traceiter_tracing_mark_write
  13f36c:      	ldar	x8, [x22]
  13f370:      	subs	x8, x8, #0x1
  13f374:      	str	w8, [x21, #0x18]
  13f378:      	b.eq	0x13f388 <dsi_display_enable+0x790>
  13f37c:      	add	x8, x21, #0x18
  13f380:      	ldar	x8, [x8]
  13f384:      	cbnz	x8, 0x13f1a0 <dsi_display_enable+0x5a8>
  13f388:      	bl	0x13f388 <dsi_display_enable+0x790>
		000000000013f388:  R_AARCH64_CALL26	preempt_schedule_notrace
  13f38c:      	b	0x13f1a0 <dsi_display_enable+0x5a8>
  13f390:      	bti	j
  13f394:      	adrp	x9, 0x13f000 <dsi_display_enable+0x408>
		000000000013f394:  R_AARCH64_ADR_PREL_PG_HI21	cpu_number
  13f398:      	mrs	x8, TPIDR_EL1
  13f39c:      	add	x9, x9, #0x0
		000000000013f39c:  R_AARCH64_ADD_ABS_LO12_NC	cpu_number
  13f3a0:      	ldr	w8, [x8, x9]
  13f3a4:      	adrp	x10, 0x13f000 <dsi_display_enable+0x408>
		000000000013f3a4:  R_AARCH64_ADR_PREL_PG_HI21	__cpu_online_mask
  13f3a8:      	add	x10, x10, #0x0
		000000000013f3a8:  R_AARCH64_ADD_ABS_LO12_NC	__cpu_online_mask
  13f3ac:      	add	w9, w8, #0x3f
  13f3b0:      	cmp	w8, #0x0
  13f3b4:      	csel	w9, w9, w8, lt
  13f3b8:      	asr	w9, w9, #6
  13f3bc:      	ldr	x9, [x10, w9, sxtw #3]
  13f3c0:      	lsr	x8, x9, x8
  13f3c4:      	tbz	w8, #0x0, 0x13f1e0 <dsi_display_enable+0x5e8>
  13f3c8:      	add	x24, x21, #0x18
  13f3cc:      	ldar	w8, [x24]
  13f3d0:      	add	w8, w8, #0x1
  13f3d4:      	str	w8, [x21, #0x18]
  13f3d8:      	adrp	x8, 0x13f000 <dsi_display_enable+0x408>
		000000000013f3d8:  R_AARCH64_ADR_PREL_PG_HI21	__tracepoint_tracing_mark_write+0x40
  13f3dc:      	add	x8, x8, #0x0
		000000000013f3dc:  R_AARCH64_ADD_ABS_LO12_NC	__tracepoint_tracing_mark_write+0x40
  13f3e0:      	ldar	x8, [x8]
  13f3e4:      	cbz	x8, 0x13f400 <dsi_display_enable+0x808>
  13f3e8:      	ldr	x0, [x8, #0x8]
  13f3ec:      	add	x3, sp, #0x8
  13f3f0:      	mov	w1, #0x45               // =69
  13f3f4:      	mov	x2, x21
  13f3f8:      	mov	w4, wzr
  13f3fc:      	bl	0x13f3fc <dsi_display_enable+0x804>
		000000000013f3fc:  R_AARCH64_CALL26	__traceiter_tracing_mark_write
  13f400:      	ldar	x8, [x24]
  13f404:      	subs	x8, x8, #0x1
  13f408:      	str	w8, [x21, #0x18]
  13f40c:      	b.eq	0x13f41c <dsi_display_enable+0x824>
  13f410:      	add	x8, x21, #0x18
  13f414:      	ldar	x8, [x8]
  13f418:      	cbnz	x8, 0x13f1e0 <dsi_display_enable+0x5e8>
  13f41c:      	bl	0x13f41c <dsi_display_enable+0x824>
		000000000013f41c:  R_AARCH64_CALL26	preempt_schedule_notrace
  13f420:      	b	0x13f1e0 <dsi_display_enable+0x5e8>
  13f424:      	bti	j
  13f428:      	adrp	x9, 0x13f000 <dsi_display_enable+0x408>
		000000000013f428:  R_AARCH64_ADR_PREL_PG_HI21	cpu_number
  13f42c:      	mrs	x8, TPIDR_EL1
  13f430:      	add	x9, x9, #0x0
		000000000013f430:  R_AARCH64_ADD_ABS_LO12_NC	cpu_number
  13f434:      	ldr	w8, [x8, x9]
  13f438:      	adrp	x10, 0x13f000 <dsi_display_enable+0x408>
		000000000013f438:  R_AARCH64_ADR_PREL_PG_HI21	__cpu_online_mask
  13f43c:      	add	x10, x10, #0x0
		000000000013f43c:  R_AARCH64_ADD_ABS_LO12_NC	__cpu_online_mask
  13f440:      	add	w9, w8, #0x3f
  13f444:      	cmp	w8, #0x0
  13f448:      	csel	w9, w9, w8, lt
  13f44c:      	asr	w9, w9, #6
  13f450:      	ldr	x9, [x10, w9, sxtw #3]
  13f454:      	lsr	x8, x9, x8
  13f458:      	tbz	w8, #0x0, 0x13f178 <dsi_display_enable+0x580>
  13f45c:      	add	x22, x21, #0x18
  13f460:      	ldar	w8, [x22]
  13f464:      	add	w8, w8, #0x1
  13f468:      	str	w8, [x21, #0x18]
  13f46c:      	adrp	x8, 0x13f000 <dsi_display_enable+0x408>
		000000000013f46c:  R_AARCH64_ADR_PREL_PG_HI21	__tracepoint_tracing_mark_write+0x40
  13f470:      	add	x8, x8, #0x0
		000000000013f470:  R_AARCH64_ADD_ABS_LO12_NC	__tracepoint_tracing_mark_write+0x40
  13f474:      	ldar	x8, [x8]
  13f478:      	cbz	x8, 0x13f494 <dsi_display_enable+0x89c>
  13f47c:      	ldr	x0, [x8, #0x8]
  13f480:      	adrp	x3, 0x13f000 <dsi_display_enable+0x408>
		000000000013f480:  R_AARCH64_ADR_PREL_PG_HI21	.rodata+0x48f00 // 'ddic_fps'
  13f484:      	add	x3, x3, #0x0
		000000000013f484:  R_AARCH64_ADD_ABS_LO12_NC	.rodata+0x48f00 // 'ddic_fps'
  13f488:      	mov	w1, #0x43               // =67
  13f48c:      	mov	x2, x21
  13f490:      	bl	0x13f490 <dsi_display_enable+0x898>
		000000000013f490:  R_AARCH64_CALL26	__traceiter_tracing_mark_write
  13f494:      	ldar	x8, [x22]
  13f498:      	subs	x8, x8, #0x1
  13f49c:      	str	w8, [x21, #0x18]
  13f4a0:      	b.eq	0x13f4b0 <dsi_display_enable+0x8b8>
  13f4a4:      	add	x8, x21, #0x18
  13f4a8:      	ldar	x8, [x8]
  13f4ac:      	cbnz	x8, 0x13f178 <dsi_display_enable+0x580>
  13f4b0:      	bl	0x13f4b0 <dsi_display_enable+0x8b8>
		000000000013f4b0:  R_AARCH64_CALL26	preempt_schedule_notrace
  13f4b4:      	b	0x13f178 <dsi_display_enable+0x580>
  13f4b8:      	mrs	x8, TPIDR_EL2
  13f4bc:      	ldapr	w8, [x22]
  13f4c0:      	ldapr	x8, [x8]
  13f4c4:      	ldapr	x8, [x22]
  13f4c8:      	ldapr	x8, [x8]
  13f4cc:      	mrs	x8, TPIDR_EL2
  13f4d0:      	ldapr	w8, [x22]
  13f4d4:      	ldapr	x8, [x8]
  13f4d8:      	ldapr	x8, [x22]
  13f4dc:      	ldapr	x8, [x8]
  13f4e0:      	mrs	x8, TPIDR_EL2
  13f4e4:      	ldapr	w8, [x24]
  13f4e8:      	ldapr	x8, [x8]
  13f4ec:      	ldapr	x8, [x24]
  13f4f0:      	ldapr	x8, [x8]
  13f4f4:      	mrs	x8, TPIDR_EL2
  13f4f8:      	ldapr	w8, [x22]
  13f4fc:      	ldapr	x8, [x8]
  13f500:      	ldapr	x8, [x22]
  13f504:      	ldapr	x8, [x8]

