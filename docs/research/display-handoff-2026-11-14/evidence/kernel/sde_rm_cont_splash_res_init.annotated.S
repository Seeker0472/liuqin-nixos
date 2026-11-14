0000000000091774 <sde_rm_cont_splash_res_init>:
   91774:      	paciasp
   91778:      	sub	sp, sp, #0xc0
   9177c:      	str	x30, [x18], #0x8
   91780:      	stp	x29, x30, [sp, #0x60]
   91784:      	stp	x28, x27, [sp, #0x70]
   91788:      	stp	x26, x25, [sp, #0x80]
   9178c:      	stp	x24, x23, [sp, #0x90]
   91790:      	stp	x22, x21, [sp, #0xa0]
   91794:      	stp	x20, x19, [sp, #0xb0]
   91798:      	add	x29, sp, #0x60
   9179c:      	adrp	x8, 0x91000 <sde_rm_init+0x20c>
		000000000009179c:  R_AARCH64_ADR_PREL_PG_HI21	__stack_chk_guard
   917a0:      	ldr	x8, [x8]
		00000000000917a0:  R_AARCH64_LDST64_ABS_LO12_NC	__stack_chk_guard
   917a4:      	stur	x8, [x29, #-0x8]
   917a8:      	stp	xzr, xzr, [sp, #0x18]
   917ac:      	str	xzr, [sp, #0x10]
   917b0:      	cbz	x2, 0x91bc8 <sde_rm_cont_splash_res_init+0x454>
   917b4:      	mov	x21, x0
   917b8:      	cbz	x0, 0x91bc8 <sde_rm_cont_splash_res_init+0x454>
   917bc:      	mov	x20, x1
   917c0:      	cbz	x1, 0x91bc8 <sde_rm_cont_splash_res_init+0x454>
   917c4:      	cbz	x3, 0x91bc8 <sde_rm_cont_splash_res_init+0x454>
   917c8:      	adrp	x8, 0x91000 <sde_rm_init+0x20c>
		00000000000917c8:  R_AARCH64_ADR_PREL_PG_HI21	__drm_debug
   917cc:      	ldrb	w8, [x8]
		00000000000917cc:  R_AARCH64_LDST8_ABS_LO12_NC	__drm_debug
   917d0:      	mov	x19, x2
   917d4:      	tbz	w8, #0x2, 0x917f8 <sde_rm_cont_splash_res_init+0x84>
   917d8:      	ldr	w8, [x3, #0x1e48]
   917dc:      	ldr	w2, [x3, #0x23f8]
   917e0:      	ldr	w4, [x3, #0x30b0]
   917e4:      	adrp	x1, 0x91000 <sde_rm_init+0x20c>
		00000000000917e4:  R_AARCH64_ADR_PREL_PG_HI21	.rodata+0x47db9 // 'mixer_count=%d, ctl_count=%d, dsc_count=%d\n'
   917e8:      	add	x1, x1, #0x0
		00000000000917e8:  R_AARCH64_ADD_ABS_LO12_NC	.rodata+0x47db9 // 'mixer_count=%d, ctl_count=%d, dsc_count=%d\n'
   917ec:      	mov	w0, #0x1                // =1
   917f0:      	mov	w3, w8
   917f4:      	bl	0x917f4 <sde_rm_cont_splash_res_init+0x80>
		00000000000917f4:  R_AARCH64_CALL26	__drm_dbg
   917f8:      	ldr	x8, [x21, #0x8]
   917fc:      	cbz	x8, 0x91bd4 <sde_rm_cont_splash_res_init+0x460>
   91800:      	mov	x8, #0x500000000        // =21474836480
   91804:      	add	x1, sp, #0x10
   91808:      	mov	x0, x20
   9180c:      	stp	xzr, xzr, [sp, #0x10]
   91810:      	str	x8, [sp, #0x20]
   91814:      	bl	0x91814 <sde_rm_cont_splash_res_init+0xa0>
		0000000000091814:  R_AARCH64_CALL26	_sde_rm_get_hw_locked.llvm.5422434062232633979
   91818:      	tbz	w0, #0x0, 0x91b88 <sde_rm_cont_splash_res_init+0x414>
   9181c:      	mov	w21, wzr
   91820:      	mov	w23, wzr
   91824:      	mov	w22, #0x50              // =80
   91828:      	b	0x91840 <sde_rm_cont_splash_res_init+0xcc>
   9182c:      	add	x1, sp, #0x10
   91830:      	mov	x0, x20
   91834:      	add	w21, w21, #0x1
   91838:      	bl	0x91838 <sde_rm_cont_splash_res_init+0xc4>
		0000000000091838:  R_AARCH64_CALL26	_sde_rm_get_hw_locked.llvm.5422434062232633979
   9183c:      	tbz	w0, #0x0, 0x91b88 <sde_rm_cont_splash_res_init+0x414>
   91840:      	ldr	w8, [x19, #0x8]
   91844:      	cmp	w23, w8
   91848:      	b.hs	0x91b88 <sde_rm_cont_splash_res_init+0x414>
   9184c:      	ldr	x8, [sp, #0x18]
   91850:      	ldr	x27, [x8, #0x28]
   91854:      	ldr	x24, [x27, #0x178]
   91858:      	cbz	x24, 0x91bf0 <sde_rm_cont_splash_res_init+0x47c>
   9185c:      	adrp	x8, 0x91000 <sde_rm_init+0x20c>
		000000000009185c:  R_AARCH64_ADR_PREL_PG_HI21	__typeid__ZTSFjP10sde_hw_ctlE_global_addr
   91860:      	add	x8, x8, #0x0
		0000000000091860:  R_AARCH64_ADD_ABS_LO12_NC	__typeid__ZTSFjP10sde_hw_ctlE_global_addr
   91864:      	sub	x8, x24, x8
   91868:      	ror	x8, x8, #0x3
   9186c:      	cmp	x8, #0x6
   91870:      	b.hs	0x91b50 <sde_rm_cont_splash_res_init+0x3dc>
   91874:      	mov	x0, x27
   91878:      	blr	x24
   9187c:      	tst	w0, #0xff
   91880:      	b.eq	0x9182c <sde_rm_cont_splash_res_init+0xb8>
   91884:      	adrp	x8, 0x91000 <sde_rm_init+0x20c>
		0000000000091884:  R_AARCH64_ADR_PREL_PG_HI21	__drm_debug
   91888:      	ldrb	w8, [x8]
		0000000000091888:  R_AARCH64_LDST8_ABS_LO12_NC	__drm_debug
   9188c:      	cmp	w21, #0x0
   91890:      	str	w23, [sp, #0x4]
   91894:      	cset	w23, ne
   91898:      	tbz	w8, #0x2, 0x918bc <sde_rm_cont_splash_res_init+0x148>
   9189c:      	ldr	x8, [sp, #0x18]
   918a0:      	adrp	x1, 0x91000 <sde_rm_init+0x20c>
		00000000000918a0:  R_AARCH64_ADR_PREL_PG_HI21	.rodata+0x17fb9 // 'finding resources for display=%d ctl=%d\n'
   918a4:      	mov	w0, #0x1                // =1
   918a8:      	add	x1, x1, #0x0
		00000000000918a8:  R_AARCH64_ADD_ABS_LO12_NC	.rodata+0x17fb9 // 'finding resources for display=%d ctl=%d\n'
   918ac:      	ldr	w8, [x8, #0x24]
   918b0:      	mov	w2, w21
   918b4:      	sub	w3, w8, #0x1
   918b8:      	bl	0x918b8 <sde_rm_cont_splash_res_init+0x144>
		00000000000918b8:  R_AARCH64_CALL26	__drm_dbg
   918bc:      	umaddl	x8, w23, w22, x19
   918c0:      	add	x8, x8, #0xb0
   918c4:      	stp	xzr, xzr, [x29, #-0x18]
   918c8:      	stur	xzr, [x29, #-0x20]
   918cc:      	stp	xzr, xzr, [sp, #0x30]
   918d0:      	str	xzr, [sp, #0x28]
   918d4:      	str	x8, [sp, #0x8]
   918d8:      	cbz	x8, 0x91af8 <sde_rm_cont_splash_res_init+0x384>
   918dc:      	cbz	x27, 0x91af8 <sde_rm_cont_splash_res_init+0x384>
   918e0:      	mov	x8, #0x200000000        // =8589934592
   918e4:      	stur	x8, [x29, #-0x10]
   918e8:      	mov	x8, #0xa00000000        // =42949672960
   918ec:      	sub	x1, x29, #0x20
   918f0:      	mov	x0, x20
   918f4:      	stp	xzr, xzr, [x29, #-0x20]
   918f8:      	stp	xzr, xzr, [sp, #0x28]
   918fc:      	str	x8, [sp, #0x38]
   91900:      	bl	0x91900 <sde_rm_cont_splash_res_init+0x18c>
		0000000000091900:  R_AARCH64_CALL26	_sde_rm_get_hw_locked.llvm.5422434062232633979
   91904:      	tbz	w0, #0x0, 0x919ec <sde_rm_cont_splash_res_init+0x278>
   91908:      	madd	x8, x23, x22, x19
   9190c:      	add	x26, x8, #0xf9
   91910:      	add	x24, x8, #0xe0
   91914:      	add	x28, x8, #0xf0
   91918:      	b	0x9192c <sde_rm_cont_splash_res_init+0x1b8>
   9191c:      	sub	x1, x29, #0x20
   91920:      	mov	x0, x20
   91924:      	bl	0x91924 <sde_rm_cont_splash_res_init+0x1b0>
		0000000000091924:  R_AARCH64_CALL26	_sde_rm_get_hw_locked.llvm.5422434062232633979
   91928:      	tbz	w0, #0x0, 0x919ec <sde_rm_cont_splash_res_init+0x278>
   9192c:      	ldrb	w8, [x26]
   91930:      	cmp	w8, #0x3
   91934:      	b.hi	0x919ec <sde_rm_cont_splash_res_init+0x278>
   91938:      	ldr	x8, [x27, #0x1a0]
   9193c:      	cbz	x8, 0x9191c <sde_rm_cont_splash_res_init+0x1a8>
   91940:      	strb	wzr, [x28]
   91944:      	ldr	x25, [x27, #0x1a0]
   91948:      	adrp	x8, 0x91000 <sde_rm_init+0x20c>
		0000000000091948:  R_AARCH64_ADR_PREL_PG_HI21	__typeid__ZTSFjP10sde_hw_ctl6sde_lmP19sde_sspp_index_infoE_global_addr
   9194c:      	add	x8, x8, #0x0
		000000000009194c:  R_AARCH64_ADD_ABS_LO12_NC	__typeid__ZTSFjP10sde_hw_ctl6sde_lmP19sde_sspp_index_infoE_global_addr
   91950:      	cmp	x25, x8
   91954:      	b.ne	0x919d0 <sde_rm_cont_splash_res_init+0x25c>
   91958:      	ldur	x8, [x29, #-0x18]
   9195c:      	mov	x0, x27
   91960:      	mov	x2, x24
   91964:      	ldr	w1, [x8, #0x24]
   91968:      	blr	x25
   9196c:      	cbnz	w0, 0x91978 <sde_rm_cont_splash_res_init+0x204>
   91970:      	ldrb	w8, [x28]
   91974:      	cbz	w8, 0x9191c <sde_rm_cont_splash_res_init+0x1a8>
   91978:      	ldur	x8, [x29, #-0x18]
   9197c:      	ldrb	w10, [x26]
   91980:      	ldr	w9, [x8, #0x24]
   91984:      	add	w11, w10, #0x1
   91988:      	cmp	x10, #0x4
   9198c:      	strb	w11, [x26]
   91990:      	b.hs	0x91bfc <sde_rm_cont_splash_res_init+0x488>
   91994:      	madd	x11, x23, x22, x19
   91998:      	add	x10, x11, x10
   9199c:      	strb	w9, [x10, #0xd4]
   919a0:      	adrp	x9, 0x91000 <sde_rm_init+0x20c>
		00000000000919a0:  R_AARCH64_ADR_PREL_PG_HI21	__drm_debug
   919a4:      	ldrb	w9, [x9]
		00000000000919a4:  R_AARCH64_LDST8_ABS_LO12_NC	__drm_debug
   919a8:      	tbz	w9, #0x2, 0x9191c <sde_rm_cont_splash_res_init+0x1a8>
   919ac:      	ldr	w8, [x8, #0x24]
   919b0:      	ldrb	w2, [x26]
   919b4:      	adrp	x1, 0x91000 <sde_rm_init+0x20c>
		00000000000919b4:  R_AARCH64_ADR_PREL_PG_HI21	.rodata+0x53951 // 'lm_cnt=%d lm_id %d pipe_cnt%d\n'
   919b8:      	mov	w4, w0
   919bc:      	sub	w3, w8, #0x1
   919c0:      	mov	w0, #0x1                // =1
   919c4:      	add	x1, x1, #0x0
		00000000000919c4:  R_AARCH64_ADD_ABS_LO12_NC	.rodata+0x53951 // 'lm_cnt=%d lm_id %d pipe_cnt%d\n'
   919c8:      	bl	0x919c8 <sde_rm_cont_splash_res_init+0x254>
		00000000000919c8:  R_AARCH64_CALL26	__drm_dbg
   919cc:      	b	0x9191c <sde_rm_cont_splash_res_init+0x1a8>
   919d0:      	mov	x0, #0x2b14             // =11028
   919d4:      	movk	x0, #0x44d4, lsl #16
   919d8:      	movk	x0, #0x4036, lsl #32
   919dc:      	movk	x0, #0xd789, lsl #48
   919e0:      	mov	x1, x25
   919e4:      	bl	0x919e4 <sde_rm_cont_splash_res_init+0x270>
		00000000000919e4:  R_AARCH64_CALL26	__cfi_slowpath
   919e8:      	b	0x91958 <sde_rm_cont_splash_res_init+0x1e4>
   919ec:      	ldr	x24, [x27, #0x1c0]
   919f0:      	cbz	x24, 0x91a1c <sde_rm_cont_splash_res_init+0x2a8>
   919f4:      	adrp	x8, 0x91000 <sde_rm_init+0x20c>
		00000000000919f4:  R_AARCH64_ADR_PREL_PG_HI21	__typeid__ZTSFjP10sde_hw_ctlE_global_addr
   919f8:      	add	x8, x8, #0x0
		00000000000919f8:  R_AARCH64_ADD_ABS_LO12_NC	__typeid__ZTSFjP10sde_hw_ctlE_global_addr
   919fc:      	sub	x8, x24, x8
   91a00:      	ror	x8, x8, #0x3
   91a04:      	cmp	x8, #0x6
   91a08:      	b.hs	0x91b6c <sde_rm_cont_splash_res_init+0x3f8>
   91a0c:      	mov	x0, x27
   91a10:      	blr	x24
   91a14:      	mov	w1, w0
   91a18:      	b	0x91a20 <sde_rm_cont_splash_res_init+0x2ac>
   91a1c:      	mov	w1, wzr
   91a20:      	ldr	x0, [sp, #0x8]
   91a24:      	bl	0x91a24 <sde_rm_cont_splash_res_init+0x2b0>
		0000000000091a24:  R_AARCH64_CALL26	.text+0x94240 // _sde_rm_update_active_only_pipes
   91a28:      	cbnz	w0, 0x91b0c <sde_rm_cont_splash_res_init+0x398>
   91a2c:      	add	x1, sp, #0x28
   91a30:      	mov	x0, x20
   91a34:      	bl	0x91a34 <sde_rm_cont_splash_res_init+0x2c0>
		0000000000091a34:  R_AARCH64_CALL26	_sde_rm_get_hw_locked.llvm.5422434062232633979
   91a38:      	tbz	w0, #0x0, 0x91b0c <sde_rm_cont_splash_res_init+0x398>
   91a3c:      	madd	x8, x23, x22, x19
   91a40:      	add	x25, x8, #0xfa
   91a44:      	b	0x91a58 <sde_rm_cont_splash_res_init+0x2e4>
   91a48:      	add	x1, sp, #0x28
   91a4c:      	mov	x0, x20
   91a50:      	bl	0x91a50 <sde_rm_cont_splash_res_init+0x2dc>
		0000000000091a50:  R_AARCH64_CALL26	_sde_rm_get_hw_locked.llvm.5422434062232633979
   91a54:      	tbz	w0, #0x0, 0x91b0c <sde_rm_cont_splash_res_init+0x398>
   91a58:      	ldr	x24, [x27, #0x188]
   91a5c:      	cbz	x24, 0x91a88 <sde_rm_cont_splash_res_init+0x314>
   91a60:      	adrp	x8, 0x91000 <sde_rm_init+0x20c>
		0000000000091a60:  R_AARCH64_ADR_PREL_PG_HI21	__typeid__ZTSFbP10sde_hw_ctl15sde_hw_blk_typeiE_global_addr
   91a64:      	add	x8, x8, #0x0
		0000000000091a64:  R_AARCH64_ADD_ABS_LO12_NC	__typeid__ZTSFbP10sde_hw_ctl15sde_hw_blk_typeiE_global_addr
   91a68:      	cmp	x24, x8
   91a6c:      	b.ne	0x91adc <sde_rm_cont_splash_res_init+0x368>
   91a70:      	ldr	x8, [sp, #0x30]
   91a74:      	mov	w1, #0xa                // =10
   91a78:      	mov	x0, x27
   91a7c:      	ldr	w2, [x8, #0x24]
   91a80:      	blr	x24
   91a84:      	tbz	w0, #0x0, 0x91a48 <sde_rm_cont_splash_res_init+0x2d4>
   91a88:      	ldr	x8, [sp, #0x30]
   91a8c:      	ldrb	w10, [x25]
   91a90:      	ldr	w9, [x8, #0x24]
   91a94:      	add	w11, w10, #0x1
   91a98:      	cmp	x10, #0x3
   91a9c:      	strb	w11, [x25]
   91aa0:      	b.hi	0x91bfc <sde_rm_cont_splash_res_init+0x488>
   91aa4:      	madd	x11, x23, x22, x19
   91aa8:      	add	x10, x11, x10
   91aac:      	strb	w9, [x10, #0xd8]
   91ab0:      	adrp	x9, 0x91000 <sde_rm_init+0x20c>
		0000000000091ab0:  R_AARCH64_ADR_PREL_PG_HI21	__drm_debug
   91ab4:      	ldrb	w9, [x9]
		0000000000091ab4:  R_AARCH64_LDST8_ABS_LO12_NC	__drm_debug
   91ab8:      	tbz	w9, #0x2, 0x91a48 <sde_rm_cont_splash_res_init+0x2d4>
   91abc:      	ldr	w8, [x8, #0x24]
   91ac0:      	ldr	w2, [x27, #0x50]
   91ac4:      	adrp	x1, 0x91000 <sde_rm_init+0x20c>
		0000000000091ac4:  R_AARCH64_ADR_PREL_PG_HI21	.rodata+0x50eeb // 'CTL[%d] path, using dsc[%d]\n'
   91ac8:      	mov	w0, #0x1                // =1
   91acc:      	sub	w3, w8, #0x1
   91ad0:      	add	x1, x1, #0x0
		0000000000091ad0:  R_AARCH64_ADD_ABS_LO12_NC	.rodata+0x50eeb // 'CTL[%d] path, using dsc[%d]\n'
   91ad4:      	bl	0x91ad4 <sde_rm_cont_splash_res_init+0x360>
		0000000000091ad4:  R_AARCH64_CALL26	__drm_dbg
   91ad8:      	b	0x91a48 <sde_rm_cont_splash_res_init+0x2d4>
   91adc:      	mov	x0, #0xc5d4             // =50644
   91ae0:      	movk	x0, #0x55db, lsl #16
   91ae4:      	movk	x0, #0x233c, lsl #32
   91ae8:      	movk	x0, #0x7a4, lsl #48
   91aec:      	mov	x1, x24
   91af0:      	bl	0x91af0 <sde_rm_cont_splash_res_init+0x37c>
		0000000000091af0:  R_AARCH64_CALL26	__cfi_slowpath
   91af4:      	b	0x91a70 <sde_rm_cont_splash_res_init+0x2fc>
   91af8:      	adrp	x0, 0x91000 <sde_rm_init+0x20c>
		0000000000091af8:  R_AARCH64_ADR_PREL_PG_HI21	.rodata+0x4145 // '\x013[drm:%s] [sde error]invalid input parameters\n'
   91afc:      	adrp	x1, 0x91000 <sde_rm_init+0x20c>
		0000000000091afc:  R_AARCH64_ADR_PREL_PG_HI21	.rodata+0x30089 // '_sde_rm_get_hw_blk_for_cont_splash'
   91b00:      	add	x0, x0, #0x0
		0000000000091b00:  R_AARCH64_ADD_ABS_LO12_NC	.rodata+0x4145 // '\x013[drm:%s] [sde error]invalid input parameters\n'
   91b04:      	add	x1, x1, #0x0
		0000000000091b04:  R_AARCH64_ADD_ABS_LO12_NC	.rodata+0x30089 // '_sde_rm_get_hw_blk_for_cont_splash'
   91b08:      	bl	0x91b08 <sde_rm_cont_splash_res_init+0x394>
		0000000000091b08:  R_AARCH64_CALL26	printk
   91b0c:      	ldr	x9, [sp, #0x8]
   91b10:      	mov	w8, #0x1                // =1
   91b14:      	madd	x10, x23, x22, x19
   91b18:      	strb	w8, [x9]
   91b1c:      	ldr	x8, [sp, #0x18]
   91b20:      	ldrb	w9, [x10, #0xf8]
   91b24:      	ldr	w8, [x8, #0x24]
   91b28:      	add	w11, w9, #0x1
   91b2c:      	cmp	x9, #0x3
   91b30:      	strb	w11, [x10, #0xf8]
   91b34:      	b.hi	0x91bfc <sde_rm_cont_splash_res_init+0x488>
   91b38:      	madd	x10, x23, x22, x19
   91b3c:      	ldr	w23, [sp, #0x4]
   91b40:      	add	x9, x10, x9
   91b44:      	strb	w8, [x9, #0xd0]
   91b48:      	add	w23, w23, #0x1
   91b4c:      	b	0x9182c <sde_rm_cont_splash_res_init+0xb8>
   91b50:      	mov	x0, #0x7321             // =29473
   91b54:      	movk	x0, #0x3c8f, lsl #16
   91b58:      	movk	x0, #0x4123, lsl #32
   91b5c:      	movk	x0, #0x2628, lsl #48
   91b60:      	mov	x1, x24
   91b64:      	bl	0x91b64 <sde_rm_cont_splash_res_init+0x3f0>
		0000000000091b64:  R_AARCH64_CALL26	__cfi_slowpath
   91b68:      	b	0x91874 <sde_rm_cont_splash_res_init+0x100>
   91b6c:      	mov	x0, #0x7321             // =29473
   91b70:      	movk	x0, #0x3c8f, lsl #16
   91b74:      	movk	x0, #0x4123, lsl #32
   91b78:      	movk	x0, #0x2628, lsl #48
   91b7c:      	mov	x1, x24
   91b80:      	bl	0x91b80 <sde_rm_cont_splash_res_init+0x40c>
		0000000000091b80:  R_AARCH64_CALL26	__cfi_slowpath
   91b84:      	b	0x91a0c <sde_rm_cont_splash_res_init+0x298>
   91b88:      	mov	w0, wzr
   91b8c:      	adrp	x9, 0x91000 <sde_rm_init+0x20c>
		0000000000091b8c:  R_AARCH64_ADR_PREL_PG_HI21	__stack_chk_guard
   91b90:      	ldur	x8, [x29, #-0x8]
   91b94:      	ldr	x9, [x9]
		0000000000091b94:  R_AARCH64_LDST64_ABS_LO12_NC	__stack_chk_guard
   91b98:      	cmp	x9, x8
   91b9c:      	b.ne	0x91c00 <sde_rm_cont_splash_res_init+0x48c>
   91ba0:      	ldp	x29, x30, [sp, #0x60]
   91ba4:      	ldp	x20, x19, [sp, #0xb0]
   91ba8:      	ldp	x22, x21, [sp, #0xa0]
   91bac:      	ldp	x24, x23, [sp, #0x90]
   91bb0:      	ldp	x26, x25, [sp, #0x80]
   91bb4:      	ldp	x28, x27, [sp, #0x70]
   91bb8:      	ldr	x30, [x18, #-0x8]!
   91bbc:      	add	sp, sp, #0xc0
   91bc0:      	autiasp
   91bc4:      	ret
   91bc8:      	adrp	x0, 0x91000 <sde_rm_init+0x20c>
		0000000000091bc8:  R_AARCH64_ADR_PREL_PG_HI21	.rodata+0x4145 // '\x013[drm:%s] [sde error]invalid input parameters\n'
   91bcc:      	add	x0, x0, #0x0
		0000000000091bcc:  R_AARCH64_ADD_ABS_LO12_NC	.rodata+0x4145 // '\x013[drm:%s] [sde error]invalid input parameters\n'
   91bd0:      	b	0x91bdc <sde_rm_cont_splash_res_init+0x468>
   91bd4:      	adrp	x0, 0x91000 <sde_rm_init+0x20c>
		0000000000091bd4:  R_AARCH64_ADR_PREL_PG_HI21	.rodata+0x2fff2 // '\x013[drm:%s] [sde error]invalid kms\n'
   91bd8:      	add	x0, x0, #0x0
		0000000000091bd8:  R_AARCH64_ADD_ABS_LO12_NC	.rodata+0x2fff2 // '\x013[drm:%s] [sde error]invalid kms\n'
   91bdc:      	adrp	x1, 0x91000 <sde_rm_init+0x20c>
		0000000000091bdc:  R_AARCH64_ADR_PREL_PG_HI21	.rodata+0x1e102 // 'sde_rm_cont_splash_res_init'
   91be0:      	add	x1, x1, #0x0
		0000000000091be0:  R_AARCH64_ADD_ABS_LO12_NC	.rodata+0x1e102 // 'sde_rm_cont_splash_res_init'
   91be4:      	bl	0x91be4 <sde_rm_cont_splash_res_init+0x470>
		0000000000091be4:  R_AARCH64_CALL26	printk
   91be8:      	mov	w0, #-0x16              // =-22
   91bec:      	b	0x91b8c <sde_rm_cont_splash_res_init+0x418>
   91bf0:      	adrp	x0, 0x91000 <sde_rm_init+0x20c>
		0000000000091bf0:  R_AARCH64_ADR_PREL_PG_HI21	.rodata+0x4dbed // '\x013[drm:%s] [sde error]get_ctl_intf not initialized\n'
   91bf4:      	add	x0, x0, #0x0
		0000000000091bf4:  R_AARCH64_ADD_ABS_LO12_NC	.rodata+0x4dbed // '\x013[drm:%s] [sde error]get_ctl_intf not initialized\n'
   91bf8:      	b	0x91bdc <sde_rm_cont_splash_res_init+0x468>
   91bfc:      	brk	#0x5512
   91c00:      	bl	0x91c00 <sde_rm_cont_splash_res_init+0x48c>
		0000000000091c00:  R_AARCH64_CALL26	__stack_chk_fail

