0000000000110968 <dsi_phy_enable>:
  110968:      	paciasp
  11096c:      	sub	sp, sp, #0x50
  110970:      	str	x30, [x18], #0x8
  110974:      	stp	x29, x30, [sp, #0x10]
  110978:      	stp	x24, x23, [sp, #0x20]
  11097c:      	stp	x22, x21, [sp, #0x30]
  110980:      	stp	x20, x19, [sp, #0x40]
  110984:      	add	x29, sp, #0x10
  110988:      	mov	x20, x0
  11098c:      	cbz	x0, 0x110aa4 <dsi_phy_enable+0x13c>
  110990:      	mov	x22, x1
  110994:      	cbz	x1, 0x110aa4 <dsi_phy_enable+0x13c>
  110998:      	add	x19, x20, #0x20
  11099c:      	mov	x0, x19
  1109a0:      	mov	w21, w4
  1109a4:      	mov	w23, w3
  1109a8:      	mov	w24, w2
  1109ac:      	bl	0x1109ac <dsi_phy_enable+0x44>
		00000000001109ac:  R_AARCH64_CALL26	mutex_lock
  1109b0:      	tbnz	w23, #0x0, 0x1109cc <dsi_phy_enable+0x64>
  1109b4:      	ldr	w3, [x20, #0x8]
  1109b8:      	adrp	x2, 0x110000 <dsi_phy_drv_init+0xbc>
		00000000001109b8:  R_AARCH64_ADR_PREL_PG_HI21	.rodata+0x3c96d // '[msm-dsi-debug]: DSI_%d: TODO: perform validation\n'
  1109bc:      	add	x2, x2, #0x0
		00000000001109bc:  R_AARCH64_ADD_ABS_LO12_NC	.rodata+0x3c96d // '[msm-dsi-debug]: DSI_%d: TODO: perform validation\n'
  1109c0:      	mov	w1, #0x1                // =1
  1109c4:      	mov	x0, xzr
  1109c8:      	bl	0x1109c8 <dsi_phy_enable+0x60>
		00000000001109c8:  R_AARCH64_CALL26	drm_dev_dbg
  1109cc:      	add	x23, x20, #0x308
  1109d0:      	add	x1, x22, #0x90
  1109d4:      	mov	w2, #0x90               // =144
  1109d8:      	mov	x0, x23
  1109dc:      	bl	0x1109dc <dsi_phy_enable+0x74>
		00000000001109dc:  R_AARCH64_CALL26	memcpy
  1109e0:      	ldr	x8, [x22, #0x120]
  1109e4:      	str	x8, [x20, #0x2b0]
  1109e8:      	ldr	w8, [x22, #0x8]
  1109ec:      	str	w8, [x20, #0x398]
  1109f0:      	ldr	w8, [x22, #0x4]!
  1109f4:      	str	w24, [x20, #0x2ac]
  1109f8:      	ldrb	w9, [x20, #0x260]
  1109fc:      	str	w8, [x20, #0x39c]
  110a00:      	ldur	x8, [x22, #0x7c]
  110a04:      	str	x8, [x20, #0x2c0]
  110a08:      	ldr	w8, [x22, #0x54]
  110a0c:      	str	x8, [x20, #0x2e0]
  110a10:      	ldr	w8, [x22, #0x58]
  110a14:      	str	x8, [x20, #0x2e8]
  110a18:      	cbz	w9, 0x110ab0 <dsi_phy_enable+0x148>
  110a1c:      	tbnz	w21, #0x0, 0x110a94 <dsi_phy_enable+0x12c>
  110a20:      	ldr	x22, [x20, #0x90]
  110a24:      	add	x21, x20, #0x58
  110a28:      	cbz	x22, 0x110a50 <dsi_phy_enable+0xe8>
  110a2c:      	adrp	x8, 0x110000 <dsi_phy_drv_init+0xbc>
		0000000000110a2c:  R_AARCH64_ADR_PREL_PG_HI21	__typeid__ZTSFvP10dsi_phy_hwP21dsi_phy_per_lane_cfgsE_global_addr
  110a30:      	add	x8, x8, #0x0
		0000000000110a30:  R_AARCH64_ADD_ABS_LO12_NC	__typeid__ZTSFvP10dsi_phy_hwP21dsi_phy_per_lane_cfgsE_global_addr
  110a34:      	sub	x8, x22, x8
  110a38:      	ror	x8, x8, #0x3
  110a3c:      	cmp	x8, #0x2
  110a40:      	b.hs	0x110b78 <dsi_phy_enable+0x210>
  110a44:      	add	x1, x20, #0x264
  110a48:      	mov	x0, x21
  110a4c:      	blr	x22
  110a50:      	ldr	x22, [x20, #0xa0]
  110a54:      	cbz	x22, 0x110a7c <dsi_phy_enable+0x114>
  110a58:      	adrp	x8, 0x110000 <dsi_phy_drv_init+0xbc>
		0000000000110a58:  R_AARCH64_ADR_PREL_PG_HI21	__typeid__ZTSFvP10dsi_phy_hwP11dsi_phy_cfgE_global_addr
  110a5c:      	add	x8, x8, #0x0
		0000000000110a5c:  R_AARCH64_ADD_ABS_LO12_NC	__typeid__ZTSFvP10dsi_phy_hwP11dsi_phy_cfgE_global_addr
  110a60:      	sub	x8, x22, x8
  110a64:      	ror	x8, x8, #0x3
  110a68:      	cmp	x8, #0x4
  110a6c:      	b.hs	0x110b94 <dsi_phy_enable+0x22c>
  110a70:      	add	x1, x20, #0x188
  110a74:      	mov	x0, x21
  110a78:      	blr	x22
  110a7c:      	ldr	w3, [x20, #0x8]
  110a80:      	adrp	x2, 0x110000 <dsi_phy_drv_init+0xbc>
		0000000000110a80:  R_AARCH64_ADR_PREL_PG_HI21	.rodata+0x30de2 // '[msm-dsi-debug]: DSI_%d: cont splash not enabled, phy enable required\n'
  110a84:      	add	x2, x2, #0x0
		0000000000110a84:  R_AARCH64_ADD_ABS_LO12_NC	.rodata+0x30de2 // '[msm-dsi-debug]: DSI_%d: cont splash not enabled, phy enable required\n'
  110a88:      	mov	w1, #0x1                // =1
  110a8c:      	mov	x0, xzr
  110a90:      	bl	0x110a90 <dsi_phy_enable+0x128>
		0000000000110a90:  R_AARCH64_CALL26	drm_dev_dbg
  110a94:      	mov	w22, wzr
  110a98:      	mov	w8, #0x1                // =1
  110a9c:      	str	w8, [x20, #0x300]
  110aa0:      	b	0x110b04 <dsi_phy_enable+0x19c>
  110aa4:      	cbz	x20, 0x110b10 <dsi_phy_enable+0x1a8>
  110aa8:      	ldr	w3, [x20, #0x8]
  110aac:      	b	0x110b14 <dsi_phy_enable+0x1ac>
  110ab0:      	ldr	x24, [x20, #0xc0]
  110ab4:      	adrp	x8, 0x110000 <dsi_phy_drv_init+0xbc>
		0000000000110ab4:  R_AARCH64_ADR_PREL_PG_HI21	__typeid__ZTSFiP10dsi_phy_hwP13dsi_mode_infoP19dsi_host_common_cfgP21dsi_phy_per_lane_cfgsbE_global_addr
  110ab8:      	add	x8, x8, #0x0
		0000000000110ab8:  R_AARCH64_ADD_ABS_LO12_NC	__typeid__ZTSFiP10dsi_phy_hwP13dsi_mode_infoP19dsi_host_common_cfgP21dsi_phy_per_lane_cfgsbE_global_addr
  110abc:      	add	x0, x20, #0x58
  110ac0:      	cmp	x24, x8
  110ac4:      	b.ne	0x110b54 <dsi_phy_enable+0x1ec>
  110ac8:      	add	x3, x20, #0x218
  110acc:      	mov	x1, x23
  110ad0:      	mov	x2, x22
  110ad4:      	mov	w4, wzr
  110ad8:      	blr	x24
  110adc:      	cbz	w0, 0x110a1c <dsi_phy_enable+0xb4>
  110ae0:      	ldr	w3, [x20, #0x8]
  110ae4:      	mov	w22, w0
  110ae8:      	adrp	x1, 0x110000 <dsi_phy_drv_init+0xbc>
		0000000000110ae8:  R_AARCH64_ADR_PREL_PG_HI21	.rodata+0x48144 // '\x013'
  110aec:      	adrp	x2, 0x110000 <dsi_phy_drv_init+0xbc>
		0000000000110aec:  R_AARCH64_ADR_PREL_PG_HI21	.rodata+0x48a7e // '*ERROR* [msm-dsi-error]: DSI_%d: failed to set timing, rc=%d\n'
  110af0:      	add	x1, x1, #0x0
		0000000000110af0:  R_AARCH64_ADD_ABS_LO12_NC	.rodata+0x48144 // '\x013'
  110af4:      	add	x2, x2, #0x0
		0000000000110af4:  R_AARCH64_ADD_ABS_LO12_NC	.rodata+0x48a7e // '*ERROR* [msm-dsi-error]: DSI_%d: failed to set timing, rc=%d\n'
  110af8:      	mov	x0, xzr
  110afc:      	mov	w4, w22
  110b00:      	bl	0x110b00 <dsi_phy_enable+0x198>
		0000000000110b00:  R_AARCH64_CALL26	drm_dev_printk
  110b04:      	mov	x0, x19
  110b08:      	bl	0x110b08 <dsi_phy_enable+0x1a0>
		0000000000110b08:  R_AARCH64_CALL26	mutex_unlock
  110b0c:      	b	0x110b30 <dsi_phy_enable+0x1c8>
  110b10:      	mov	w3, #-0x1               // =-1
  110b14:      	adrp	x1, 0x110000 <dsi_phy_drv_init+0xbc>
		0000000000110b14:  R_AARCH64_ADR_PREL_PG_HI21	.rodata+0x48144 // '\x013'
  110b18:      	adrp	x2, 0x110000 <dsi_phy_drv_init+0xbc>
		0000000000110b18:  R_AARCH64_ADR_PREL_PG_HI21	.rodata+0x48a4d // '*ERROR* [msm-dsi-error]: DSI_%d: Invalid params\n'
  110b1c:      	add	x1, x1, #0x0
		0000000000110b1c:  R_AARCH64_ADD_ABS_LO12_NC	.rodata+0x48144 // '\x013'
  110b20:      	add	x2, x2, #0x0
		0000000000110b20:  R_AARCH64_ADD_ABS_LO12_NC	.rodata+0x48a4d // '*ERROR* [msm-dsi-error]: DSI_%d: Invalid params\n'
  110b24:      	mov	x0, xzr
  110b28:      	bl	0x110b28 <dsi_phy_enable+0x1c0>
		0000000000110b28:  R_AARCH64_CALL26	drm_dev_printk
  110b2c:      	mov	w22, #-0x16             // =-22
  110b30:      	ldp	x29, x30, [sp, #0x10]
  110b34:      	mov	w0, w22
  110b38:      	ldp	x20, x19, [sp, #0x40]
  110b3c:      	ldp	x22, x21, [sp, #0x30]
  110b40:      	ldp	x24, x23, [sp, #0x20]
  110b44:      	ldr	x30, [x18, #-0x8]!
  110b48:      	add	sp, sp, #0x50
  110b4c:      	autiasp
  110b50:      	ret
  110b54:      	str	x0, [sp, #0x8]
  110b58:      	mov	x0, #0xad06             // =44294
  110b5c:      	movk	x0, #0xf2bb, lsl #16
  110b60:      	movk	x0, #0x224a, lsl #32
  110b64:      	movk	x0, #0x235d, lsl #48
  110b68:      	mov	x1, x24
  110b6c:      	bl	0x110b6c <dsi_phy_enable+0x204>
		0000000000110b6c:  R_AARCH64_CALL26	__cfi_slowpath
  110b70:      	ldr	x0, [sp, #0x8]
  110b74:      	b	0x110ac8 <dsi_phy_enable+0x160>
  110b78:      	mov	x0, #0xb113             // =45331
  110b7c:      	movk	x0, #0xc962, lsl #16
  110b80:      	movk	x0, #0xaaca, lsl #32
  110b84:      	movk	x0, #0xeb54, lsl #48
  110b88:      	mov	x1, x22
  110b8c:      	bl	0x110b8c <dsi_phy_enable+0x224>
		0000000000110b8c:  R_AARCH64_CALL26	__cfi_slowpath
  110b90:      	b	0x110a44 <dsi_phy_enable+0xdc>
  110b94:      	mov	x0, #0x64e              // =1614
  110b98:      	movk	x0, #0xf52d, lsl #16
  110b9c:      	movk	x0, #0x4bd3, lsl #32
  110ba0:      	movk	x0, #0xdb7c, lsl #48
  110ba4:      	mov	x1, x22
  110ba8:      	bl	0x110ba8 <dsi_phy_enable+0x240>
		0000000000110ba8:  R_AARCH64_CALL26	__cfi_slowpath
  110bac:      	b	0x110a70 <dsi_phy_enable+0x108>

