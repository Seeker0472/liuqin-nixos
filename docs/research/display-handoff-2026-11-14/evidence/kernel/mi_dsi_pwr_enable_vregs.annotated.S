0000000000176658 <mi_dsi_pwr_enable_vregs>:
  176658:      	paciasp
  17665c:      	str	x30, [x18], #0x8
  176660:      	stp	x29, x30, [sp, #-0x60]!
  176664:      	str	x27, [sp, #0x10]
  176668:      	stp	x26, x25, [sp, #0x20]
  17666c:      	stp	x24, x23, [sp, #0x30]
  176670:      	stp	x22, x21, [sp, #0x40]
  176674:      	stp	x20, x19, [sp, #0x50]
  176678:      	mov	x29, sp
  17667c:      	ldr	x27, [x0]
  176680:      	mov	w5, w2
  176684:      	mov	x19, x0
  176688:      	sxtw	x23, w5
  17668c:      	mov	w8, #0x50               // =80
  176690:      	tbz	w1, #0x0, 0x176754 <mi_dsi_pwr_enable_vregs+0xfc>
  176694:      	madd	x26, x23, x8, x27
  176698:      	mov	x25, x26
  17669c:      	ldr	w20, [x26, #0x3c]
  1766a0:      	ldr	w24, [x25, #0x40]!
  1766a4:      	add	x21, x26, #0x8
  1766a8:      	adrp	x1, 0x176000 <mi_dsi_panel_parse_flatmode_configs+0x128>
		00000000001766a8:  R_AARCH64_ADR_PREL_PG_HI21	.rodata+0x48144 // '\x013'
  1766ac:      	adrp	x2, 0x176000 <mi_dsi_panel_parse_flatmode_configs+0x128>
		00000000001766ac:  R_AARCH64_ADR_PREL_PG_HI21	.rodata+0x22ae2 // '*ERROR* [msm-dsi-error]: M80/M81 Setting optimum mode for %s, enable:%d\n'
  1766b0:      	add	x1, x1, #0x0
		00000000001766b0:  R_AARCH64_ADD_ABS_LO12_NC	.rodata+0x48144 // '\x013'
  1766b4:      	add	x2, x2, #0x0
		00000000001766b4:  R_AARCH64_ADD_ABS_LO12_NC	.rodata+0x22ae2 // '*ERROR* [msm-dsi-error]: M80/M81 Setting optimum mode for %s, enable:%d\n'
  1766b8:      	mov	w4, #0x1                // =1
  1766bc:      	mov	x0, xzr
  1766c0:      	mov	x3, x21
  1766c4:      	bl	0x1766c4 <mi_dsi_pwr_enable_vregs+0x6c>
		00000000001766c4:  R_AARCH64_CALL26	drm_dev_printk
  1766c8:      	mov	w8, #0x3e8              // =1000
  1766cc:      	mul	w0, w20, w8
  1766d0:      	add	w1, w0, #0xa
  1766d4:      	bl	0x1766d4 <mi_dsi_pwr_enable_vregs+0x7c>
		00000000001766d4:  R_AARCH64_CALL26	usleep_range
  1766d8:      	ldr	x0, [x26]
  1766dc:      	ldr	w1, [x26, #0x30]
  1766e0:      	bl	0x1766e0 <mi_dsi_pwr_enable_vregs+0x88>
		00000000001766e0:  R_AARCH64_CALL26	regulator_set_load
  1766e4:      	tbnz	w0, #0x1f, 0x1767fc <mi_dsi_pwr_enable_vregs+0x1a4>
  1766e8:      	ldr	x0, [x26]
  1766ec:      	bl	0x1766ec <mi_dsi_pwr_enable_vregs+0x94>
		00000000001766ec:  R_AARCH64_CALL26	regulator_count_voltages
  1766f0:      	mov	w22, w0
  1766f4:      	cmp	w0, #0x1
  1766f8:      	b.lt	0x176820 <mi_dsi_pwr_enable_vregs+0x1c8>
  1766fc:      	mov	w8, #0x50               // =80
  176700:      	madd	x8, x23, x8, x27
  176704:      	ldr	x0, [x26]
  176708:      	ldp	w1, w2, [x8, #0x28]
  17670c:      	bl	0x17670c <mi_dsi_pwr_enable_vregs+0xb4>
		000000000017670c:  R_AARCH64_CALL26	regulator_set_voltage
  176710:      	cbz	w0, 0x176820 <mi_dsi_pwr_enable_vregs+0x1c8>
  176714:      	mov	w20, w0
  176718:      	adrp	x1, 0x176000 <mi_dsi_panel_parse_flatmode_configs+0x128>
		0000000000176718:  R_AARCH64_ADR_PREL_PG_HI21	.rodata+0x48144 // '\x013'
  17671c:      	adrp	x2, 0x176000 <mi_dsi_panel_parse_flatmode_configs+0x128>
		000000000017671c:  R_AARCH64_ADR_PREL_PG_HI21	.rodata+0x161e6 // '*ERROR* [msm-dsi-error]: Set voltage(%s) fail, rc=%d\n'
  176720:      	add	x1, x1, #0x0
		0000000000176720:  R_AARCH64_ADD_ABS_LO12_NC	.rodata+0x48144 // '\x013'
  176724:      	add	x2, x2, #0x0
		0000000000176724:  R_AARCH64_ADD_ABS_LO12_NC	.rodata+0x161e6 // '*ERROR* [msm-dsi-error]: Set voltage(%s) fail, rc=%d\n'
  176728:      	mov	x0, xzr
  17672c:      	mov	x3, x21
  176730:      	mov	w4, w20
  176734:      	bl	0x176734 <mi_dsi_pwr_enable_vregs+0xdc>
		0000000000176734:  R_AARCH64_CALL26	drm_dev_printk
  176738:      	ldr	x8, [x19]
  17673c:      	mov	w9, #0x50               // =80
  176740:      	madd	x8, x23, x9, x8
  176744:      	ldr	x0, [x8]
  176748:      	ldr	w1, [x8, #0x34]
  17674c:      	bl	0x17674c <mi_dsi_pwr_enable_vregs+0xf4>
		000000000017674c:  R_AARCH64_CALL26	regulator_set_load
  176750:      	b	0x176858 <mi_dsi_pwr_enable_vregs+0x200>
  176754:      	madd	x8, x23, x8, x27
  176758:      	ldp	w21, w20, [x8, #0x44]
  17675c:      	adrp	x1, 0x176000 <mi_dsi_panel_parse_flatmode_configs+0x128>
		000000000017675c:  R_AARCH64_ADR_PREL_PG_HI21	.rodata+0x48144 // '\x013'
  176760:      	adrp	x2, 0x176000 <mi_dsi_panel_parse_flatmode_configs+0x128>
		0000000000176760:  R_AARCH64_ADR_PREL_PG_HI21	.rodata+0x2b813 // '*ERROR* [msm-dsi-error]: M80/M81 Setting optimum mode  for %s, enable:%d\n'
  176764:      	add	x3, x8, #0x8
  176768:      	add	x1, x1, #0x0
		0000000000176768:  R_AARCH64_ADD_ABS_LO12_NC	.rodata+0x48144 // '\x013'
  17676c:      	add	x2, x2, #0x0
		000000000017676c:  R_AARCH64_ADD_ABS_LO12_NC	.rodata+0x2b813 // '*ERROR* [msm-dsi-error]: M80/M81 Setting optimum mode  for %s, enable:%d\n'
  176770:      	mov	x0, xzr
  176774:      	mov	w4, wzr
  176778:      	bl	0x176778 <mi_dsi_pwr_enable_vregs+0x120>
		0000000000176778:  R_AARCH64_CALL26	drm_dev_printk
  17677c:      	cbz	w21, 0x176790 <mi_dsi_pwr_enable_vregs+0x138>
  176780:      	mov	w8, #0x3e8              // =1000
  176784:      	mul	w0, w21, w8
  176788:      	add	w1, w0, #0xa
  17678c:      	bl	0x17678c <mi_dsi_pwr_enable_vregs+0x134>
		000000000017678c:  R_AARCH64_CALL26	usleep_range
  176790:      	ldr	x8, [x19]
  176794:      	mov	w9, #0x50               // =80
  176798:      	madd	x9, x23, x9, x8
  17679c:      	ldr	w1, [x9, #0x38]
  1767a0:      	cbz	w1, 0x1767bc <mi_dsi_pwr_enable_vregs+0x164>
  1767a4:      	mov	w9, #0x50               // =80
  1767a8:      	madd	x8, x23, x9, x8
  1767ac:      	ldr	x0, [x8]
  1767b0:      	ldr	w2, [x8, #0x2c]
  1767b4:      	bl	0x1767b4 <mi_dsi_pwr_enable_vregs+0x15c>
		00000000001767b4:  R_AARCH64_CALL26	regulator_set_voltage
  1767b8:      	ldr	x8, [x19]
  1767bc:      	add	x9, x23, x23, lsl #2
  1767c0:      	lsl	x21, x9, #4
  1767c4:      	add	x8, x8, x21
  1767c8:      	ldr	x0, [x8]
  1767cc:      	ldr	w1, [x8, #0x34]
  1767d0:      	bl	0x1767d0 <mi_dsi_pwr_enable_vregs+0x178>
		00000000001767d0:  R_AARCH64_CALL26	regulator_set_load
  1767d4:      	ldr	x8, [x19]
  1767d8:      	ldr	x0, [x8, x21]
  1767dc:      	bl	0x1767dc <mi_dsi_pwr_enable_vregs+0x184>
		00000000001767dc:  R_AARCH64_CALL26	regulator_disable
  1767e0:      	cbz	w20, 0x17690c <mi_dsi_pwr_enable_vregs+0x2b4>
  1767e4:      	mov	w8, #0x3e8              // =1000
  1767e8:      	mul	w0, w20, w8
  1767ec:      	add	w1, w0, #0xa
  1767f0:      	bl	0x1767f0 <mi_dsi_pwr_enable_vregs+0x198>
		00000000001767f0:  R_AARCH64_CALL26	usleep_range
  1767f4:      	mov	w20, wzr
  1767f8:      	b	0x17690c <mi_dsi_pwr_enable_vregs+0x2b4>
  1767fc:      	adrp	x1, 0x176000 <mi_dsi_panel_parse_flatmode_configs+0x128>
		00000000001767fc:  R_AARCH64_ADR_PREL_PG_HI21	.rodata+0x48144 // '\x013'
  176800:      	adrp	x2, 0x176000 <mi_dsi_panel_parse_flatmode_configs+0x128>
		0000000000176800:  R_AARCH64_ADR_PREL_PG_HI21	.rodata+0x48abc // '*ERROR* [msm-dsi-error]: Setting optimum mode failed for %s\n'
  176804:      	mov	w20, w0
  176808:      	add	x1, x1, #0x0
		0000000000176808:  R_AARCH64_ADD_ABS_LO12_NC	.rodata+0x48144 // '\x013'
  17680c:      	add	x2, x2, #0x0
		000000000017680c:  R_AARCH64_ADD_ABS_LO12_NC	.rodata+0x48abc // '*ERROR* [msm-dsi-error]: Setting optimum mode failed for %s\n'
  176810:      	mov	x0, xzr
  176814:      	mov	x3, x21
  176818:      	bl	0x176818 <mi_dsi_pwr_enable_vregs+0x1c0>
		0000000000176818:  R_AARCH64_CALL26	drm_dev_printk
  17681c:      	b	0x176874 <mi_dsi_pwr_enable_vregs+0x21c>
  176820:      	ldr	x0, [x26]
  176824:      	bl	0x176824 <mi_dsi_pwr_enable_vregs+0x1cc>
		0000000000176824:  R_AARCH64_CALL26	regulator_enable
  176828:      	cbz	w0, 0x176934 <mi_dsi_pwr_enable_vregs+0x2dc>
  17682c:      	mov	w20, w0
  176830:      	adrp	x1, 0x176000 <mi_dsi_panel_parse_flatmode_configs+0x128>
		0000000000176830:  R_AARCH64_ADR_PREL_PG_HI21	.rodata+0x48144 // '\x013'
  176834:      	adrp	x2, 0x176000 <mi_dsi_panel_parse_flatmode_configs+0x128>
		0000000000176834:  R_AARCH64_ADR_PREL_PG_HI21	.rodata+0x51aec // '*ERROR* [msm-dsi-error]: enable failed for %s, rc=%d\n'
  176838:      	add	x1, x1, #0x0
		0000000000176838:  R_AARCH64_ADD_ABS_LO12_NC	.rodata+0x48144 // '\x013'
  17683c:      	add	x2, x2, #0x0
		000000000017683c:  R_AARCH64_ADD_ABS_LO12_NC	.rodata+0x51aec // '*ERROR* [msm-dsi-error]: enable failed for %s, rc=%d\n'
  176840:      	mov	x0, xzr
  176844:      	mov	x3, x21
  176848:      	mov	w4, w20
  17684c:      	bl	0x17684c <mi_dsi_pwr_enable_vregs+0x1f4>
		000000000017684c:  R_AARCH64_CALL26	drm_dev_printk
  176850:      	cmp	w22, #0x1
  176854:      	b.lt	0x176874 <mi_dsi_pwr_enable_vregs+0x21c>
  176858:      	ldr	x8, [x19]
  17685c:      	mov	w9, #0x50               // =80
  176860:      	mov	w1, wzr
  176864:      	madd	x8, x23, x9, x8
  176868:      	ldr	x0, [x8]
  17686c:      	ldr	w2, [x8, #0x2c]
  176870:      	bl	0x176870 <mi_dsi_pwr_enable_vregs+0x218>
		0000000000176870:  R_AARCH64_CALL26	regulator_set_voltage
  176874:      	ldr	x8, [x19]
  176878:      	mov	w9, #0x50               // =80
  17687c:      	madd	x10, x23, x9, x8
  176880:      	ldp	w9, w21, [x10, #0x44]
  176884:      	cbz	w9, 0x17689c <mi_dsi_pwr_enable_vregs+0x244>
  176888:      	mov	w8, #0x3e8              // =1000
  17688c:      	mul	w0, w9, w8
  176890:      	add	w1, w0, #0xa
  176894:      	bl	0x176894 <mi_dsi_pwr_enable_vregs+0x23c>
		0000000000176894:  R_AARCH64_CALL26	usleep_range
  176898:      	ldr	x8, [x19]
  17689c:      	add	x9, x23, x23, lsl #2
  1768a0:      	lsl	x22, x9, #4
  1768a4:      	add	x8, x8, x22
  1768a8:      	ldr	x0, [x8]
  1768ac:      	ldr	w1, [x8, #0x34]
  1768b0:      	bl	0x1768b0 <mi_dsi_pwr_enable_vregs+0x258>
		00000000001768b0:  R_AARCH64_CALL26	regulator_set_load
  1768b4:      	ldr	x8, [x19]
  1768b8:      	ldr	x0, [x8, x22]
  1768bc:      	bl	0x1768bc <mi_dsi_pwr_enable_vregs+0x264>
		00000000001768bc:  R_AARCH64_CALL26	regulator_count_voltages
  1768c0:      	cmp	w0, #0x1
  1768c4:      	b.lt	0x1768e4 <mi_dsi_pwr_enable_vregs+0x28c>
  1768c8:      	ldr	x8, [x19]
  1768cc:      	mov	w9, #0x50               // =80
  1768d0:      	mov	w1, wzr
  1768d4:      	madd	x8, x23, x9, x8
  1768d8:      	ldr	x0, [x8]
  1768dc:      	ldr	w2, [x8, #0x2c]
  1768e0:      	bl	0x1768e0 <mi_dsi_pwr_enable_vregs+0x288>
		00000000001768e0:  R_AARCH64_CALL26	regulator_set_voltage
  1768e4:      	ldr	x8, [x19]
  1768e8:      	mov	w9, #0x50               // =80
  1768ec:      	mul	x9, x23, x9
  1768f0:      	ldr	x0, [x8, x9]
  1768f4:      	bl	0x1768f4 <mi_dsi_pwr_enable_vregs+0x29c>
		00000000001768f4:  R_AARCH64_CALL26	regulator_disable
  1768f8:      	cbz	w21, 0x17690c <mi_dsi_pwr_enable_vregs+0x2b4>
  1768fc:      	mov	w8, #0x3e8              // =1000
  176900:      	mul	w0, w21, w8
  176904:      	add	w1, w0, #0xa
  176908:      	bl	0x176908 <mi_dsi_pwr_enable_vregs+0x2b0>
		0000000000176908:  R_AARCH64_CALL26	usleep_range
  17690c:      	mov	w0, w20
  176910:      	ldp	x20, x19, [sp, #0x50]
  176914:      	ldp	x22, x21, [sp, #0x40]
  176918:      	ldp	x24, x23, [sp, #0x30]
  17691c:      	ldp	x26, x25, [sp, #0x20]
  176920:      	ldr	x27, [sp, #0x10]
  176924:      	ldp	x29, x30, [sp], #0x60
  176928:      	ldr	x30, [x18, #-0x8]!
  17692c:      	autiasp
  176930:      	ret
  176934:      	ldr	w8, [x25]
  176938:      	cbz	w8, 0x176948 <mi_dsi_pwr_enable_vregs+0x2f0>
  17693c:      	mov	w8, #0x3e8              // =1000
  176940:      	mul	w0, w24, w8
  176944:      	b	0x1767ec <mi_dsi_pwr_enable_vregs+0x194>
  176948:      	mov	w20, wzr
  17694c:      	b	0x17690c <mi_dsi_pwr_enable_vregs+0x2b4>

