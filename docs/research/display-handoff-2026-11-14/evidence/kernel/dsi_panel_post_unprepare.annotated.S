000000000014e6e4 <dsi_panel_post_unprepare>:
  14e6e4:      	paciasp
  14e6e8:      	str	x30, [x18], #0x8
  14e6ec:      	stp	x29, x30, [sp, #-0x30]!
  14e6f0:      	stp	x22, x21, [sp, #0x10]
  14e6f4:      	stp	x20, x19, [sp, #0x20]
  14e6f8:      	mov	x29, sp
  14e6fc:      	cbz	x0, 0x14e7c8 <dsi_panel_post_unprepare+0xe4>
  14e700:      	add	x19, x0, #0x3e8
  14e704:      	mov	x20, x0
  14e708:      	mov	x0, x19
  14e70c:      	bl	0x14e70c <dsi_panel_post_unprepare+0x28>
		000000000014e70c:  R_AARCH64_CALL26	mutex_lock
  14e710:      	ldr	w0, [x20, #0x5c8]
  14e714:      	cmp	w0, #0x1ff
  14e718:      	b.hi	0x14e728 <dsi_panel_post_unprepare+0x44>
  14e71c:      	bl	0x14e71c <dsi_panel_post_unprepare+0x38>
		000000000014e71c:  R_AARCH64_CALL26	gpio_to_desc
  14e720:      	mov	w1, wzr
  14e724:      	bl	0x14e724 <dsi_panel_post_unprepare+0x40>
		000000000014e724:  R_AARCH64_CALL26	gpiod_set_raw_value
  14e728:      	mov	x0, x20
  14e72c:      	bl	0x14e72c <dsi_panel_post_unprepare+0x48>
		000000000014e72c:  R_AARCH64_CALL26	mi_get_panel_id_by_dsi_panel
  14e730:      	cmp	w0, #0xa
  14e734:      	b.ne	0x14e744 <dsi_panel_post_unprepare+0x60>
  14e738:      	mov	w0, #0x8958             // =35160
  14e73c:      	movk	w0, #0x41, lsl #16
  14e740:      	bl	0x14e740 <dsi_panel_post_unprepare+0x5c>
		000000000014e740:  R_AARCH64_CALL26	__const_udelay
  14e744:      	mov	x0, x20
  14e748:      	bl	0x14e748 <dsi_panel_post_unprepare+0x64>
		000000000014e748:  R_AARCH64_CALL26	mi_get_panel_id_by_dsi_panel
  14e74c:      	cmp	w0, #0xf
  14e750:      	b.ne	0x14e760 <dsi_panel_post_unprepare+0x7c>
  14e754:      	mov	w0, #0x9c08             // =39944
  14e758:      	movk	w0, #0xc4, lsl #16
  14e75c:      	bl	0x14e75c <dsi_panel_post_unprepare+0x78>
		000000000014e75c:  R_AARCH64_CALL26	__const_udelay
  14e760:      	mov	x0, x20
  14e764:      	bl	0x14e764 <dsi_panel_post_unprepare+0x80>
		000000000014e764:  R_AARCH64_CALL26	mi_get_panel_id_by_dsi_panel
  14e768:      	cmp	w0, #0x10
  14e76c:      	b.eq	0x14e780 <dsi_panel_post_unprepare+0x9c>
  14e770:      	mov	x0, x20
  14e774:      	bl	0x14e774 <dsi_panel_post_unprepare+0x90>
		000000000014e774:  R_AARCH64_CALL26	mi_get_panel_id_by_dsi_panel
  14e778:      	cmp	w0, #0x11
  14e77c:      	b.ne	0x14e78c <dsi_panel_post_unprepare+0xa8>
  14e780:      	mov	w0, #0x12b0             // =4784
  14e784:      	movk	w0, #0x83, lsl #16
  14e788:      	bl	0x14e788 <dsi_panel_post_unprepare+0xa4>
		000000000014e788:  R_AARCH64_CALL26	__const_udelay
  14e78c:      	ldrb	w8, [x20, #0x8e8]
  14e790:      	cbz	w8, 0x14e7a4 <dsi_panel_post_unprepare+0xc0>
  14e794:      	ldrb	w8, [x20, #0x8e9]
  14e798:      	cbz	w8, 0x14e7a4 <dsi_panel_post_unprepare+0xc0>
  14e79c:      	ldrb	w8, [x20, #0x8ea]
  14e7a0:      	cbz	w8, 0x14e7e4 <dsi_panel_post_unprepare+0x100>
  14e7a4:      	ldr	w0, [x20, #0x5c4]
  14e7a8:      	cmp	w0, #0x1ff
  14e7ac:      	b.hi	0x14e85c <dsi_panel_post_unprepare+0x178>
  14e7b0:      	ldrb	w8, [x20, #0x7ac]
  14e7b4:      	cbnz	w8, 0x14e85c <dsi_panel_post_unprepare+0x178>
  14e7b8:      	bl	0x14e7b8 <dsi_panel_post_unprepare+0xd4>
		000000000014e7b8:  R_AARCH64_CALL26	gpio_to_desc
  14e7bc:      	mov	w1, wzr
  14e7c0:      	bl	0x14e7c0 <dsi_panel_post_unprepare+0xdc>
		000000000014e7c0:  R_AARCH64_CALL26	gpiod_set_raw_value
  14e7c4:      	b	0x14e85c <dsi_panel_post_unprepare+0x178>
  14e7c8:      	adrp	x1, 0x14e000 <dsi_panel_enable+0x30>
		000000000014e7c8:  R_AARCH64_ADR_PREL_PG_HI21	.rodata+0x48144 // '\x013'
  14e7cc:      	adrp	x2, 0x14e000 <dsi_panel_enable+0x30>
		000000000014e7cc:  R_AARCH64_ADR_PREL_PG_HI21	.rodata+0x5aace // '*ERROR* [msm-dsi-error]: invalid params\n'
  14e7d0:      	add	x1, x1, #0x0
		000000000014e7d0:  R_AARCH64_ADD_ABS_LO12_NC	.rodata+0x48144 // '\x013'
  14e7d4:      	add	x2, x2, #0x0
		000000000014e7d4:  R_AARCH64_ADD_ABS_LO12_NC	.rodata+0x5aace // '*ERROR* [msm-dsi-error]: invalid params\n'
  14e7d8:      	bl	0x14e7d8 <dsi_panel_post_unprepare+0xf4>
		000000000014e7d8:  R_AARCH64_CALL26	drm_dev_printk
  14e7dc:      	mov	w21, #-0x16             // =-22
  14e7e0:      	b	0x14ea68 <dsi_panel_post_unprepare+0x384>
  14e7e4:      	ldr	x8, [x20, #0x8e0]
  14e7e8:      	mov	x9, #0x200              // =512
  14e7ec:      	movk	x9, #0x5042, lsl #16
  14e7f0:      	movk	x9, #0x3831, lsl #32
  14e7f4:      	movk	x9, #0x4d, lsl #48
  14e7f8:      	cmp	x8, x9
  14e7fc:      	b.eq	0x14e844 <dsi_panel_post_unprepare+0x160>
  14e800:      	mov	x9, #0x200              // =512
  14e804:      	movk	x9, #0x5036, lsl #16
  14e808:      	movk	x9, #0x3831, lsl #32
  14e80c:      	movk	x9, #0x4d, lsl #48
  14e810:      	cmp	x8, x9
  14e814:      	b.eq	0x14e844 <dsi_panel_post_unprepare+0x160>
  14e818:      	mov	x9, #0x200              // =512
  14e81c:      	movk	x9, #0x42, lsl #16
  14e820:      	movk	x9, #0x3830, lsl #32
  14e824:      	movk	x9, #0x4d, lsl #48
  14e828:      	cmp	x8, x9
  14e82c:      	b.ne	0x14e85c <dsi_panel_post_unprepare+0x178>
  14e830:      	adrp	x1, 0x14e000 <dsi_panel_enable+0x30>
		000000000014e830:  R_AARCH64_ADR_PREL_PG_HI21	.rodata+0x48144 // '\x013'
  14e834:      	adrp	x2, 0x14e000 <dsi_panel_enable+0x30>
		000000000014e834:  R_AARCH64_ADR_PREL_PG_HI21	.rodata+0x2b44e // '*ERROR* [msm-dsi-error]: M80 dont reset !!\n'
  14e838:      	add	x1, x1, #0x0
		000000000014e838:  R_AARCH64_ADD_ABS_LO12_NC	.rodata+0x48144 // '\x013'
  14e83c:      	add	x2, x2, #0x0
		000000000014e83c:  R_AARCH64_ADD_ABS_LO12_NC	.rodata+0x2b44e // '*ERROR* [msm-dsi-error]: M80 dont reset !!\n'
  14e840:      	b	0x14e854 <dsi_panel_post_unprepare+0x170>
  14e844:      	adrp	x1, 0x14e000 <dsi_panel_enable+0x30>
		000000000014e844:  R_AARCH64_ADR_PREL_PG_HI21	.rodata+0x48144 // '\x013'
  14e848:      	adrp	x2, 0x14e000 <dsi_panel_enable+0x30>
		000000000014e848:  R_AARCH64_ADR_PREL_PG_HI21	.rodata+0x346b6 // '*ERROR* [msm-dsi-error]: M81 dont reset !!\n'
  14e84c:      	add	x1, x1, #0x0
		000000000014e84c:  R_AARCH64_ADD_ABS_LO12_NC	.rodata+0x48144 // '\x013'
  14e850:      	add	x2, x2, #0x0
		000000000014e850:  R_AARCH64_ADD_ABS_LO12_NC	.rodata+0x346b6 // '*ERROR* [msm-dsi-error]: M81 dont reset !!\n'
  14e854:      	mov	x0, xzr
  14e858:      	bl	0x14e858 <dsi_panel_post_unprepare+0x174>
		000000000014e858:  R_AARCH64_CALL26	drm_dev_printk
  14e85c:      	ldr	w0, [x20, #0x5cc]
  14e860:      	cmp	w0, #0x1ff
  14e864:      	b.hi	0x14e874 <dsi_panel_post_unprepare+0x190>
  14e868:      	bl	0x14e868 <dsi_panel_post_unprepare+0x184>
		000000000014e868:  R_AARCH64_CALL26	gpio_to_desc
  14e86c:      	mov	w1, wzr
  14e870:      	bl	0x14e870 <dsi_panel_post_unprepare+0x18c>
		000000000014e870:  R_AARCH64_CALL26	gpiod_set_raw_value
  14e874:      	ldr	w0, [x20, #0x880]
  14e878:      	cmp	w0, #0x1ff
  14e87c:      	b.hi	0x14e88c <dsi_panel_post_unprepare+0x1a8>
  14e880:      	bl	0x14e880 <dsi_panel_post_unprepare+0x19c>
		000000000014e880:  R_AARCH64_CALL26	gpio_to_desc
  14e884:      	bl	0x14e884 <dsi_panel_post_unprepare+0x1a0>
		000000000014e884:  R_AARCH64_CALL26	gpiod_direction_input
  14e888:      	cbnz	w0, 0x14ea84 <dsi_panel_post_unprepare+0x3a0>
  14e88c:      	mov	x0, x20
  14e890:      	bl	0x14e890 <dsi_panel_post_unprepare+0x1ac>
		000000000014e890:  R_AARCH64_CALL26	mi_get_panel_id_by_dsi_panel
  14e894:      	cmp	w0, #0x11
  14e898:      	b.ne	0x14e8a8 <dsi_panel_post_unprepare+0x1c4>
  14e89c:      	mov	w0, #0x8958             // =35160
  14e8a0:      	movk	w0, #0x41, lsl #16
  14e8a4:      	bl	0x14e8a4 <dsi_panel_post_unprepare+0x1c0>
		000000000014e8a4:  R_AARCH64_CALL26	__const_udelay
  14e8a8:      	ldrb	w8, [x20, #0x486]
  14e8ac:      	cbz	w8, 0x14e900 <dsi_panel_post_unprepare+0x21c>
  14e8b0:      	mov	w21, wzr
  14e8b4:      	ldrb	w8, [x20, #0x8e8]
  14e8b8:      	cbz	w8, 0x14e95c <dsi_panel_post_unprepare+0x278>
  14e8bc:      	ldrb	w8, [x20, #0x8e9]
  14e8c0:      	cbz	w8, 0x14e8cc <dsi_panel_post_unprepare+0x1e8>
  14e8c4:      	ldrb	w8, [x20, #0x8ea]
  14e8c8:      	cbz	w8, 0x14e970 <dsi_panel_post_unprepare+0x28c>
  14e8cc:      	add	x0, x20, #0x538
  14e8d0:      	mov	w1, wzr
  14e8d4:      	bl	0x14e8d4 <dsi_panel_post_unprepare+0x1f0>
		000000000014e8d4:  R_AARCH64_CALL26	dsi_pwr_enable_regulator
  14e8d8:      	mov	w21, wzr
  14e8dc:      	cbz	w0, 0x14ea60 <dsi_panel_post_unprepare+0x37c>
  14e8e0:      	ldr	x1, [x20]
  14e8e4:      	mov	w22, w0
  14e8e8:      	adrp	x0, 0x14e000 <dsi_panel_enable+0x30>
		000000000014e8e8:  R_AARCH64_ADR_PREL_PG_HI21	.rodata+0x5a90 // '\x013[%s] failed to enable vregs, rc=%d\n'
  14e8ec:      	add	x0, x0, #0x0
		000000000014e8ec:  R_AARCH64_ADD_ABS_LO12_NC	.rodata+0x5a90 // '\x013[%s] failed to enable vregs, rc=%d\n'
  14e8f0:      	mov	w2, w22
  14e8f4:      	bl	0x14e8f4 <dsi_panel_post_unprepare+0x210>
		000000000014e8f4:  R_AARCH64_CALL26	printk
  14e8f8:      	mov	w21, w22
  14e8fc:      	b	0x14ea20 <dsi_panel_post_unprepare+0x33c>
  14e900:      	ldr	x0, [x20, #0x5d8]
  14e904:      	cbz	x0, 0x14e8b0 <dsi_panel_post_unprepare+0x1cc>
  14e908:      	ldr	x1, [x20, #0x5e8]
  14e90c:      	bl	0x14e90c <dsi_panel_post_unprepare+0x228>
		000000000014e90c:  R_AARCH64_CALL26	pinctrl_select_state
  14e910:      	mov	w21, w0
  14e914:      	cbz	w0, 0x14e8b4 <dsi_panel_post_unprepare+0x1d0>
  14e918:      	ldr	x3, [x20]
  14e91c:      	adrp	x22, 0x14e000 <dsi_panel_enable+0x30>
		000000000014e91c:  R_AARCH64_ADR_PREL_PG_HI21	.rodata+0x48144 // '\x013'
  14e920:      	add	x22, x22, #0x0
		000000000014e920:  R_AARCH64_ADD_ABS_LO12_NC	.rodata+0x48144 // '\x013'
  14e924:      	adrp	x2, 0x14e000 <dsi_panel_enable+0x30>
		000000000014e924:  R_AARCH64_ADR_PREL_PG_HI21	.rodata+0x3a5ff // '*ERROR* [msm-dsi-error]: [%s] failed to set pin state, rc=%d\n'
  14e928:      	add	x2, x2, #0x0
		000000000014e928:  R_AARCH64_ADD_ABS_LO12_NC	.rodata+0x3a5ff // '*ERROR* [msm-dsi-error]: [%s] failed to set pin state, rc=%d\n'
  14e92c:      	mov	x0, xzr
  14e930:      	mov	x1, x22
  14e934:      	mov	w4, w21
  14e938:      	bl	0x14e938 <dsi_panel_post_unprepare+0x254>
		000000000014e938:  R_AARCH64_CALL26	drm_dev_printk
  14e93c:      	ldr	x3, [x20]
  14e940:      	adrp	x2, 0x14e000 <dsi_panel_enable+0x30>
		000000000014e940:  R_AARCH64_ADR_PREL_PG_HI21	.rodata+0x2277e // '*ERROR* [msm-dsi-error]: [%s] failed set pinctrl state, rc=%d\n'
  14e944:      	add	x2, x2, #0x0
		000000000014e944:  R_AARCH64_ADD_ABS_LO12_NC	.rodata+0x2277e // '*ERROR* [msm-dsi-error]: [%s] failed set pinctrl state, rc=%d\n'
  14e948:      	mov	x0, xzr
  14e94c:      	mov	x1, x22
  14e950:      	mov	w4, w21
  14e954:      	bl	0x14e954 <dsi_panel_post_unprepare+0x270>
		000000000014e954:  R_AARCH64_CALL26	drm_dev_printk
  14e958:      	b	0x14e8b4 <dsi_panel_post_unprepare+0x1d0>
  14e95c:      	add	x0, x20, #0x538
  14e960:      	mov	w1, wzr
  14e964:      	bl	0x14e964 <dsi_panel_post_unprepare+0x280>
		000000000014e964:  R_AARCH64_CALL26	dsi_pwr_enable_regulator
  14e968:      	mov	w21, w0
  14e96c:      	b	0x14ea1c <dsi_panel_post_unprepare+0x338>
  14e970:      	ldr	x8, [x20, #0x8e0]
  14e974:      	mov	x9, #0x200              // =512
  14e978:      	movk	x9, #0x5042, lsl #16
  14e97c:      	movk	x9, #0x3831, lsl #32
  14e980:      	movk	x9, #0x4d, lsl #48
  14e984:      	cmp	x8, x9
  14e988:      	b.eq	0x14e9e0 <dsi_panel_post_unprepare+0x2fc>
  14e98c:      	mov	x9, #0x200              // =512
  14e990:      	movk	x9, #0x5036, lsl #16
  14e994:      	movk	x9, #0x3831, lsl #32
  14e998:      	movk	x9, #0x4d, lsl #48
  14e99c:      	cmp	x8, x9
  14e9a0:      	b.eq	0x14e9e0 <dsi_panel_post_unprepare+0x2fc>
  14e9a4:      	mov	x9, #0x200              // =512
  14e9a8:      	movk	x9, #0x42, lsl #16
  14e9ac:      	movk	x9, #0x3830, lsl #32
  14e9b0:      	movk	x9, #0x4d, lsl #48
  14e9b4:      	cmp	x8, x9
  14e9b8:      	b.ne	0x14ea1c <dsi_panel_post_unprepare+0x338>
  14e9bc:      	adrp	x1, 0x14e000 <dsi_panel_enable+0x30>
		000000000014e9bc:  R_AARCH64_ADR_PREL_PG_HI21	.rodata+0x48144 // '\x013'
  14e9c0:      	adrp	x2, 0x14e000 <dsi_panel_enable+0x30>
		000000000014e9c0:  R_AARCH64_ADR_PREL_PG_HI21	.rodata+0x494b1 // '*ERROR* [msm-dsi-error]: M80 dsi_panel_power_off mi_dsi_pwr_enable_vregs 1.3v\n'
  14e9c4:      	add	x1, x1, #0x0
		000000000014e9c4:  R_AARCH64_ADD_ABS_LO12_NC	.rodata+0x48144 // '\x013'
  14e9c8:      	add	x2, x2, #0x0
		000000000014e9c8:  R_AARCH64_ADD_ABS_LO12_NC	.rodata+0x494b1 // '*ERROR* [msm-dsi-error]: M80 dsi_panel_power_off mi_dsi_pwr_enable_vregs 1.3v\n'
  14e9cc:      	mov	x0, xzr
  14e9d0:      	bl	0x14e9d0 <dsi_panel_post_unprepare+0x2ec>
		000000000014e9d0:  R_AARCH64_CALL26	drm_dev_printk
  14e9d4:      	add	x0, x20, #0x538
  14e9d8:      	mov	w2, #0x2                // =2
  14e9dc:      	b	0x14ea14 <dsi_panel_post_unprepare+0x330>
  14e9e0:      	adrp	x1, 0x14e000 <dsi_panel_enable+0x30>
		000000000014e9e0:  R_AARCH64_ADR_PREL_PG_HI21	.rodata+0x48144 // '\x013'
  14e9e4:      	adrp	x2, 0x14e000 <dsi_panel_enable+0x30>
		000000000014e9e4:  R_AARCH64_ADR_PREL_PG_HI21	.rodata+0x4357c // '*ERROR* [msm-dsi-error]: M81 dsi_panel_power_off mi_dsi_pwr_enable_vregs 1.3v\n'
  14e9e8:      	add	x1, x1, #0x0
		000000000014e9e8:  R_AARCH64_ADD_ABS_LO12_NC	.rodata+0x48144 // '\x013'
  14e9ec:      	add	x2, x2, #0x0
		000000000014e9ec:  R_AARCH64_ADD_ABS_LO12_NC	.rodata+0x4357c // '*ERROR* [msm-dsi-error]: M81 dsi_panel_power_off mi_dsi_pwr_enable_vregs 1.3v\n'
  14e9f0:      	mov	x0, xzr
  14e9f4:      	bl	0x14e9f4 <dsi_panel_post_unprepare+0x310>
		000000000014e9f4:  R_AARCH64_CALL26	drm_dev_printk
  14e9f8:      	add	x22, x20, #0x538
  14e9fc:      	mov	w2, #0x2                // =2
  14ea00:      	mov	x0, x22
  14ea04:      	mov	w1, wzr
  14ea08:      	bl	0x14ea08 <dsi_panel_post_unprepare+0x324>
		000000000014ea08:  R_AARCH64_CALL26	mi_dsi_pwr_enable_vregs
  14ea0c:      	mov	w2, #0x1                // =1
  14ea10:      	mov	x0, x22
  14ea14:      	mov	w1, wzr
  14ea18:      	bl	0x14ea18 <dsi_panel_post_unprepare+0x334>
		000000000014ea18:  R_AARCH64_CALL26	mi_dsi_pwr_enable_vregs
  14ea1c:      	cbz	w21, 0x14ea60 <dsi_panel_post_unprepare+0x37c>
  14ea20:      	ldr	x3, [x20]
  14ea24:      	adrp	x22, 0x14e000 <dsi_panel_enable+0x30>
		000000000014ea24:  R_AARCH64_ADR_PREL_PG_HI21	.rodata+0x48144 // '\x013'
  14ea28:      	add	x22, x22, #0x0
		000000000014ea28:  R_AARCH64_ADD_ABS_LO12_NC	.rodata+0x48144 // '\x013'
  14ea2c:      	adrp	x2, 0x14e000 <dsi_panel_enable+0x30>
		000000000014ea2c:  R_AARCH64_ADR_PREL_PG_HI21	.rodata+0x27e0d // '*ERROR* [msm-dsi-error]: [%s] failed to enable vregs, rc=%d\n'
  14ea30:      	add	x2, x2, #0x0
		000000000014ea30:  R_AARCH64_ADD_ABS_LO12_NC	.rodata+0x27e0d // '*ERROR* [msm-dsi-error]: [%s] failed to enable vregs, rc=%d\n'
  14ea34:      	mov	x0, xzr
  14ea38:      	mov	x1, x22
  14ea3c:      	mov	w4, w21
  14ea40:      	bl	0x14ea40 <dsi_panel_post_unprepare+0x35c>
		000000000014ea40:  R_AARCH64_CALL26	drm_dev_printk
  14ea44:      	ldr	x3, [x20]
  14ea48:      	adrp	x2, 0x14e000 <dsi_panel_enable+0x30>
		000000000014ea48:  R_AARCH64_ADR_PREL_PG_HI21	.rodata+0x4bf5b // '*ERROR* [msm-dsi-error]: [%s] panel power_Off failed, rc=%d\n'
  14ea4c:      	add	x2, x2, #0x0
		000000000014ea4c:  R_AARCH64_ADD_ABS_LO12_NC	.rodata+0x4bf5b // '*ERROR* [msm-dsi-error]: [%s] panel power_Off failed, rc=%d\n'
  14ea50:      	mov	x0, xzr
  14ea54:      	mov	x1, x22
  14ea58:      	mov	w4, w21
  14ea5c:      	bl	0x14ea5c <dsi_panel_post_unprepare+0x378>
		000000000014ea5c:  R_AARCH64_CALL26	drm_dev_printk
  14ea60:      	mov	x0, x19
  14ea64:      	bl	0x14ea64 <dsi_panel_post_unprepare+0x380>
		000000000014ea64:  R_AARCH64_CALL26	mutex_unlock
  14ea68:      	mov	w0, w21
  14ea6c:      	ldp	x20, x19, [sp, #0x20]
  14ea70:      	ldp	x22, x21, [sp, #0x10]
  14ea74:      	ldp	x29, x30, [sp], #0x30
  14ea78:      	ldr	x30, [x18, #-0x8]!
  14ea7c:      	autiasp
  14ea80:      	ret
  14ea84:      	mov	w1, w0
  14ea88:      	adrp	x0, 0x14e000 <dsi_panel_enable+0x30>
		000000000014ea88:  R_AARCH64_ADR_PREL_PG_HI21	.rodata+0x28456 // '\x014[drm] [msm-dsi-warn]: set dir for panel test gpio failed rc=%d\n'
  14ea8c:      	add	x0, x0, #0x0
		000000000014ea8c:  R_AARCH64_ADD_ABS_LO12_NC	.rodata+0x28456 // '\x014[drm] [msm-dsi-warn]: set dir for panel test gpio failed rc=%d\n'
  14ea90:      	bl	0x14ea90 <dsi_panel_post_unprepare+0x3ac>
		000000000014ea90:  R_AARCH64_CALL26	printk
  14ea94:      	b	0x14e88c <dsi_panel_post_unprepare+0x1a8>

