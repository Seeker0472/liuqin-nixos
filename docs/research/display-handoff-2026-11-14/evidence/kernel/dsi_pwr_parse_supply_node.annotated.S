0000000000112744 <dsi_pwr_parse_supply_node>:
  112744:      	paciasp
  112748:      	sub	sp, sp, #0x80
  11274c:      	str	x30, [x18], #0x8
  112750:      	stp	x29, x30, [sp, #0x20]
  112754:      	stp	x28, x27, [sp, #0x30]
  112758:      	stp	x26, x25, [sp, #0x40]
  11275c:      	stp	x24, x23, [sp, #0x50]
  112760:      	stp	x22, x21, [sp, #0x60]
  112764:      	stp	x20, x19, [sp, #0x70]
  112768:      	add	x29, sp, #0x20
  11276c:      	adrp	x8, 0x112000 <dsi_phy_driver_probe$f82802b0bf108c90655d299f84d4d244+0x678>
		000000000011276c:  R_AARCH64_ADR_PREL_PG_HI21	__stack_chk_guard
  112770:      	ldr	x8, [x8]
		0000000000112770:  R_AARCH64_LDST64_ABS_LO12_NC	__stack_chk_guard
  112774:      	adrp	x27, 0x112000 <dsi_phy_driver_probe$f82802b0bf108c90655d299f84d4d244+0x678>
		0000000000112774:  R_AARCH64_ADR_PREL_PG_HI21	__typeid__ZTSFP11device_nodePKS_S0_E_global_addr
  112778:      	add	x27, x27, #0x0
		0000000000112778:  R_AARCH64_ADD_ABS_LO12_NC	__typeid__ZTSFP11device_nodePKS_S0_E_global_addr
  11277c:      	mov	x19, x2
  112780:      	stur	x8, [x29, #-0x8]
  112784:      	stur	wzr, [x29, #-0xc]
  112788:      	ldr	x22, [x0, #0x68]
  11278c:      	mov	x20, x0
  112790:      	mov	x21, x1
  112794:      	sub	x8, x22, x27
  112798:      	ror	x8, x8, #0x3
  11279c:      	cmp	x8, #0x2
  1127a0:      	b.hs	0x112d0c <dsi_pwr_parse_supply_node+0x5c8>
  1127a4:      	mov	x0, x21
  1127a8:      	mov	x1, xzr
  1127ac:      	blr	x22
  1127b0:      	cbz	x0, 0x112c44 <dsi_pwr_parse_supply_node+0x500>
  1127b4:      	adrp	x25, 0x112000 <dsi_phy_driver_probe$f82802b0bf108c90655d299f84d4d244+0x678>
		00000000001127b4:  R_AARCH64_ADR_PREL_PG_HI21	__typeid__ZTSFiPK11device_nodePKcPjE_global_addr
  1127b8:      	mov	x22, x0
  1127bc:      	mov	w26, wzr
  1127c0:      	mov	w24, #0x50              // =80
  1127c4:      	add	x25, x25, #0x0
		00000000001127c4:  R_AARCH64_ADD_ABS_LO12_NC	__typeid__ZTSFiPK11device_nodePKcPjE_global_addr
  1127c8:      	str	xzr, [sp, #0x8]
  1127cc:      	ldr	x28, [x20, #0x40]
  1127d0:      	adrp	x8, 0x112000 <dsi_phy_driver_probe$f82802b0bf108c90655d299f84d4d244+0x678>
		00000000001127d0:  R_AARCH64_ADR_PREL_PG_HI21	__typeid__ZTSFiPK11device_nodePKcPS3_E_global_addr
  1127d4:      	add	x8, x8, #0x0
		00000000001127d4:  R_AARCH64_ADD_ABS_LO12_NC	__typeid__ZTSFiPK11device_nodePKcPS3_E_global_addr
  1127d8:      	sub	x8, x28, x8
  1127dc:      	ror	x8, x8, #0x3
  1127e0:      	cmp	x8, #0x2
  1127e4:      	b.hs	0x112b10 <dsi_pwr_parse_supply_node+0x3cc>
  1127e8:      	adrp	x1, 0x112000 <dsi_phy_driver_probe$f82802b0bf108c90655d299f84d4d244+0x678>
		00000000001127e8:  R_AARCH64_ADR_PREL_PG_HI21	.rodata+0x1d191 // 'qcom,supply-name'
  1127ec:      	add	x2, sp, #0x8
  1127f0:      	mov	x0, x22
  1127f4:      	add	x1, x1, #0x0
		00000000001127f4:  R_AARCH64_ADD_ABS_LO12_NC	.rodata+0x1d191 // 'qcom,supply-name'
  1127f8:      	blr	x28
  1127fc:      	cbnz	w0, 0x112c4c <dsi_pwr_parse_supply_node+0x508>
  112800:      	ldr	x8, [x19]
  112804:      	ldr	x3, [sp, #0x8]
  112808:      	adrp	x2, 0x112000 <dsi_phy_driver_probe$f82802b0bf108c90655d299f84d4d244+0x678>
		0000000000112808:  R_AARCH64_ADR_PREL_PG_HI21	.rodata+0xee0e // '%s'
  11280c:      	mov	w1, #0x20               // =32
  112810:      	smaddl	x8, w26, w24, x8
  112814:      	add	x0, x8, #0x8
  112818:      	add	x2, x2, #0x0
		0000000000112818:  R_AARCH64_ADD_ABS_LO12_NC	.rodata+0xee0e // '%s'
  11281c:      	bl	0x11281c <dsi_pwr_parse_supply_node+0xd8>
		000000000011281c:  R_AARCH64_CALL26	snprintf
  112820:      	ldr	x28, [x20, #0x20]
  112824:      	sub	x8, x28, x25
  112828:      	ror	x8, x8, #0x3
  11282c:      	cmp	x8, #0x3
  112830:      	b.hs	0x112b2c <dsi_pwr_parse_supply_node+0x3e8>
  112834:      	adrp	x1, 0x112000 <dsi_phy_driver_probe$f82802b0bf108c90655d299f84d4d244+0x678>
		0000000000112834:  R_AARCH64_ADR_PREL_PG_HI21	.rodata+0x16f6f // 'qcom,supply-min-voltage'
  112838:      	sub	x2, x29, #0xc
  11283c:      	mov	x0, x22
  112840:      	add	x1, x1, #0x0
		0000000000112840:  R_AARCH64_ADD_ABS_LO12_NC	.rodata+0x16f6f // 'qcom,supply-min-voltage'
  112844:      	blr	x28
  112848:      	cbnz	w0, 0x112c64 <dsi_pwr_parse_supply_node+0x520>
  11284c:      	ldr	x8, [x19]
  112850:      	ldur	w9, [x29, #-0xc]
  112854:      	sxtw	x23, w26
  112858:      	madd	x8, x23, x24, x8
  11285c:      	str	w9, [x8, #0x28]
  112860:      	ldr	x28, [x20, #0x20]
  112864:      	sub	x8, x28, x25
  112868:      	ror	x8, x8, #0x3
  11286c:      	cmp	x8, #0x3
  112870:      	b.hs	0x112b48 <dsi_pwr_parse_supply_node+0x404>
  112874:      	adrp	x1, 0x112000 <dsi_phy_driver_probe$f82802b0bf108c90655d299f84d4d244+0x678>
		0000000000112874:  R_AARCH64_ADR_PREL_PG_HI21	.rodata+0xc0b7 // 'qcom,supply-max-voltage'
  112878:      	sub	x2, x29, #0xc
  11287c:      	mov	x0, x22
  112880:      	add	x1, x1, #0x0
		0000000000112880:  R_AARCH64_ADD_ABS_LO12_NC	.rodata+0xc0b7 // 'qcom,supply-max-voltage'
  112884:      	blr	x28
  112888:      	cbnz	w0, 0x112c7c <dsi_pwr_parse_supply_node+0x538>
  11288c:      	ldr	x8, [x19]
  112890:      	ldur	w9, [x29, #-0xc]
  112894:      	madd	x8, x23, x24, x8
  112898:      	str	w9, [x8, #0x2c]
  11289c:      	ldr	x28, [x20, #0x20]
  1128a0:      	sub	x8, x28, x25
  1128a4:      	ror	x8, x8, #0x3
  1128a8:      	cmp	x8, #0x3
  1128ac:      	b.hs	0x112b64 <dsi_pwr_parse_supply_node+0x420>
  1128b0:      	adrp	x1, 0x112000 <dsi_phy_driver_probe$f82802b0bf108c90655d299f84d4d244+0x678>
		00000000001128b0:  R_AARCH64_ADR_PREL_PG_HI21	.rodata+0x608f // 'qcom,supply-enable-load'
  1128b4:      	sub	x2, x29, #0xc
  1128b8:      	mov	x0, x22
  1128bc:      	add	x1, x1, #0x0
		00000000001128bc:  R_AARCH64_ADD_ABS_LO12_NC	.rodata+0x608f // 'qcom,supply-enable-load'
  1128c0:      	blr	x28
  1128c4:      	cbnz	w0, 0x112c94 <dsi_pwr_parse_supply_node+0x550>
  1128c8:      	ldr	x8, [x19]
  1128cc:      	ldur	w9, [x29, #-0xc]
  1128d0:      	madd	x8, x23, x24, x8
  1128d4:      	str	w9, [x8, #0x30]
  1128d8:      	ldr	x28, [x20, #0x20]
  1128dc:      	sub	x8, x28, x25
  1128e0:      	ror	x8, x8, #0x3
  1128e4:      	cmp	x8, #0x3
  1128e8:      	b.hs	0x112b80 <dsi_pwr_parse_supply_node+0x43c>
  1128ec:      	adrp	x1, 0x112000 <dsi_phy_driver_probe$f82802b0bf108c90655d299f84d4d244+0x678>
		00000000001128ec:  R_AARCH64_ADR_PREL_PG_HI21	.rodata+0x4fbbe // 'qcom,supply-disable-load'
  1128f0:      	sub	x2, x29, #0xc
  1128f4:      	mov	x0, x22
  1128f8:      	add	x1, x1, #0x0
		00000000001128f8:  R_AARCH64_ADD_ABS_LO12_NC	.rodata+0x4fbbe // 'qcom,supply-disable-load'
  1128fc:      	blr	x28
  112900:      	cbnz	w0, 0x112cac <dsi_pwr_parse_supply_node+0x568>
  112904:      	ldr	x8, [x19]
  112908:      	ldur	w9, [x29, #-0xc]
  11290c:      	madd	x8, x23, x24, x8
  112910:      	str	w9, [x8, #0x34]
  112914:      	ldr	x28, [x20, #0x20]
  112918:      	sub	x8, x28, x25
  11291c:      	ror	x8, x8, #0x3
  112920:      	cmp	x8, #0x3
  112924:      	b.hs	0x112b9c <dsi_pwr_parse_supply_node+0x458>
  112928:      	adrp	x1, 0x112000 <dsi_phy_driver_probe$f82802b0bf108c90655d299f84d4d244+0x678>
		0000000000112928:  R_AARCH64_ADR_PREL_PG_HI21	.rodata+0x21a9 // 'qcom,supply-off-min-voltage'
  11292c:      	sub	x2, x29, #0xc
  112930:      	mov	x0, x22
  112934:      	add	x1, x1, #0x0
		0000000000112934:  R_AARCH64_ADD_ABS_LO12_NC	.rodata+0x21a9 // 'qcom,supply-off-min-voltage'
  112938:      	blr	x28
  11293c:      	cbz	w0, 0x112958 <dsi_pwr_parse_supply_node+0x214>
  112940:      	adrp	x2, 0x112000 <dsi_phy_driver_probe$f82802b0bf108c90655d299f84d4d244+0x678>
		0000000000112940:  R_AARCH64_ADR_PREL_PG_HI21	.rodata+0x4b5d2 // '[msm-dsi-debug]: off-min-voltage not specified\n'
  112944:      	mov	w1, #0x1                // =1
  112948:      	mov	x0, xzr
  11294c:      	add	x2, x2, #0x0
		000000000011294c:  R_AARCH64_ADD_ABS_LO12_NC	.rodata+0x4b5d2 // '[msm-dsi-debug]: off-min-voltage not specified\n'
  112950:      	bl	0x112950 <dsi_pwr_parse_supply_node+0x20c>
		0000000000112950:  R_AARCH64_CALL26	drm_dev_dbg
  112954:      	b	0x112968 <dsi_pwr_parse_supply_node+0x224>
  112958:      	ldr	x8, [x19]
  11295c:      	ldur	w9, [x29, #-0xc]
  112960:      	madd	x8, x23, x24, x8
  112964:      	str	w9, [x8, #0x38]
  112968:      	ldr	x28, [x20, #0x20]
  11296c:      	sub	x8, x28, x25
  112970:      	ror	x8, x8, #0x3
  112974:      	cmp	x8, #0x3
  112978:      	b.hs	0x112bb8 <dsi_pwr_parse_supply_node+0x474>
  11297c:      	adrp	x1, 0x112000 <dsi_phy_driver_probe$f82802b0bf108c90655d299f84d4d244+0x678>
		000000000011297c:  R_AARCH64_ADR_PREL_PG_HI21	.rodata+0x54350 // 'qcom,supply-pre-on-sleep'
  112980:      	sub	x2, x29, #0xc
  112984:      	mov	x0, x22
  112988:      	add	x1, x1, #0x0
		0000000000112988:  R_AARCH64_ADD_ABS_LO12_NC	.rodata+0x54350 // 'qcom,supply-pre-on-sleep'
  11298c:      	blr	x28
  112990:      	cbz	w0, 0x1129ac <dsi_pwr_parse_supply_node+0x268>
  112994:      	adrp	x2, 0x112000 <dsi_phy_driver_probe$f82802b0bf108c90655d299f84d4d244+0x678>
		0000000000112994:  R_AARCH64_ADR_PREL_PG_HI21	.rodata+0xddf8 // '[msm-dsi-debug]: pre-on-sleep not specified\n'
  112998:      	mov	w1, #0x1                // =1
  11299c:      	mov	x0, xzr
  1129a0:      	add	x2, x2, #0x0
		00000000001129a0:  R_AARCH64_ADD_ABS_LO12_NC	.rodata+0xddf8 // '[msm-dsi-debug]: pre-on-sleep not specified\n'
  1129a4:      	bl	0x1129a4 <dsi_pwr_parse_supply_node+0x260>
		00000000001129a4:  R_AARCH64_CALL26	drm_dev_dbg
  1129a8:      	b	0x1129bc <dsi_pwr_parse_supply_node+0x278>
  1129ac:      	ldr	x8, [x19]
  1129b0:      	ldur	w9, [x29, #-0xc]
  1129b4:      	madd	x8, x23, x24, x8
  1129b8:      	str	w9, [x8, #0x3c]
  1129bc:      	ldr	x28, [x20, #0x20]
  1129c0:      	sub	x8, x28, x25
  1129c4:      	ror	x8, x8, #0x3
  1129c8:      	cmp	x8, #0x3
  1129cc:      	b.hs	0x112bd4 <dsi_pwr_parse_supply_node+0x490>
  1129d0:      	adrp	x1, 0x112000 <dsi_phy_driver_probe$f82802b0bf108c90655d299f84d4d244+0x678>
		00000000001129d0:  R_AARCH64_ADR_PREL_PG_HI21	.rodata+0x3c710 // 'qcom,supply-pre-off-sleep'
  1129d4:      	sub	x2, x29, #0xc
  1129d8:      	mov	x0, x22
  1129dc:      	add	x1, x1, #0x0
		00000000001129dc:  R_AARCH64_ADD_ABS_LO12_NC	.rodata+0x3c710 // 'qcom,supply-pre-off-sleep'
  1129e0:      	blr	x28
  1129e4:      	cbz	w0, 0x112a00 <dsi_pwr_parse_supply_node+0x2bc>
  1129e8:      	adrp	x2, 0x112000 <dsi_phy_driver_probe$f82802b0bf108c90655d299f84d4d244+0x678>
		00000000001129e8:  R_AARCH64_ADR_PREL_PG_HI21	.rodata+0x18dc0 // '[msm-dsi-debug]: pre-off-sleep not specified\n'
  1129ec:      	mov	w1, #0x1                // =1
  1129f0:      	mov	x0, xzr
  1129f4:      	add	x2, x2, #0x0
		00000000001129f4:  R_AARCH64_ADD_ABS_LO12_NC	.rodata+0x18dc0 // '[msm-dsi-debug]: pre-off-sleep not specified\n'
  1129f8:      	bl	0x1129f8 <dsi_pwr_parse_supply_node+0x2b4>
		00000000001129f8:  R_AARCH64_CALL26	drm_dev_dbg
  1129fc:      	b	0x112a10 <dsi_pwr_parse_supply_node+0x2cc>
  112a00:      	ldr	x8, [x19]
  112a04:      	ldur	w9, [x29, #-0xc]
  112a08:      	madd	x8, x23, x24, x8
  112a0c:      	str	w9, [x8, #0x44]
  112a10:      	ldr	x28, [x20, #0x20]
  112a14:      	sub	x8, x28, x25
  112a18:      	ror	x8, x8, #0x3
  112a1c:      	cmp	x8, #0x3
  112a20:      	b.hs	0x112bf0 <dsi_pwr_parse_supply_node+0x4ac>
  112a24:      	adrp	x1, 0x112000 <dsi_phy_driver_probe$f82802b0bf108c90655d299f84d4d244+0x678>
		0000000000112a24:  R_AARCH64_ADR_PREL_PG_HI21	.rodata+0xae8c // 'qcom,supply-post-on-sleep'
  112a28:      	sub	x2, x29, #0xc
  112a2c:      	mov	x0, x22
  112a30:      	add	x1, x1, #0x0
		0000000000112a30:  R_AARCH64_ADD_ABS_LO12_NC	.rodata+0xae8c // 'qcom,supply-post-on-sleep'
  112a34:      	blr	x28
  112a38:      	cbz	w0, 0x112a54 <dsi_pwr_parse_supply_node+0x310>
  112a3c:      	adrp	x2, 0x112000 <dsi_phy_driver_probe$f82802b0bf108c90655d299f84d4d244+0x678>
		0000000000112a3c:  R_AARCH64_ADR_PREL_PG_HI21	.rodata+0xb304 // '[msm-dsi-debug]: post-on-sleep not specified\n'
  112a40:      	mov	w1, #0x1                // =1
  112a44:      	mov	x0, xzr
  112a48:      	add	x2, x2, #0x0
		0000000000112a48:  R_AARCH64_ADD_ABS_LO12_NC	.rodata+0xb304 // '[msm-dsi-debug]: post-on-sleep not specified\n'
  112a4c:      	bl	0x112a4c <dsi_pwr_parse_supply_node+0x308>
		0000000000112a4c:  R_AARCH64_CALL26	drm_dev_dbg
  112a50:      	b	0x112a64 <dsi_pwr_parse_supply_node+0x320>
  112a54:      	ldr	x8, [x19]
  112a58:      	ldur	w9, [x29, #-0xc]
  112a5c:      	madd	x8, x23, x24, x8
  112a60:      	str	w9, [x8, #0x40]
  112a64:      	ldr	x28, [x20, #0x20]
  112a68:      	sub	x8, x28, x25
  112a6c:      	ror	x8, x8, #0x3
  112a70:      	cmp	x8, #0x3
  112a74:      	b.hs	0x112c0c <dsi_pwr_parse_supply_node+0x4c8>
  112a78:      	adrp	x1, 0x112000 <dsi_phy_driver_probe$f82802b0bf108c90655d299f84d4d244+0x678>
		0000000000112a78:  R_AARCH64_ADR_PREL_PG_HI21	.rodata+0x1eba7 // 'qcom,supply-post-off-sleep'
  112a7c:      	sub	x2, x29, #0xc
  112a80:      	mov	x0, x22
  112a84:      	add	x1, x1, #0x0
		0000000000112a84:  R_AARCH64_ADD_ABS_LO12_NC	.rodata+0x1eba7 // 'qcom,supply-post-off-sleep'
  112a88:      	blr	x28
  112a8c:      	cbz	w0, 0x112aa8 <dsi_pwr_parse_supply_node+0x364>
  112a90:      	adrp	x2, 0x112000 <dsi_phy_driver_probe$f82802b0bf108c90655d299f84d4d244+0x678>
		0000000000112a90:  R_AARCH64_ADR_PREL_PG_HI21	.rodata+0x27914 // '[msm-dsi-debug]: post-off-sleep not specified\n'
  112a94:      	mov	w1, #0x1                // =1
  112a98:      	mov	x0, xzr
  112a9c:      	add	x2, x2, #0x0
		0000000000112a9c:  R_AARCH64_ADD_ABS_LO12_NC	.rodata+0x27914 // '[msm-dsi-debug]: post-off-sleep not specified\n'
  112aa0:      	bl	0x112aa0 <dsi_pwr_parse_supply_node+0x35c>
		0000000000112aa0:  R_AARCH64_CALL26	drm_dev_dbg
  112aa4:      	b	0x112ab8 <dsi_pwr_parse_supply_node+0x374>
  112aa8:      	ldr	x8, [x19]
  112aac:      	ldur	w9, [x29, #-0xc]
  112ab0:      	madd	x8, x23, x24, x8
  112ab4:      	str	w9, [x8, #0x48]
  112ab8:      	ldr	x8, [x19]
  112abc:      	adrp	x2, 0x112000 <dsi_phy_driver_probe$f82802b0bf108c90655d299f84d4d244+0x678>
		0000000000112abc:  R_AARCH64_ADR_PREL_PG_HI21	.rodata+0x4ea58 // '[msm-dsi-debug]: [%s] minv=%d maxv=%d, en_load=%d, dis_load=%d\n'
  112ac0:      	mov	w1, #0x1                // =1
  112ac4:      	mov	x0, xzr
  112ac8:      	madd	x8, x23, x24, x8
  112acc:      	ldp	w4, w5, [x8, #0x28]
  112ad0:      	ldp	w6, w7, [x8, #0x30]
  112ad4:      	add	x3, x8, #0x8
  112ad8:      	add	x2, x2, #0x0
		0000000000112ad8:  R_AARCH64_ADD_ABS_LO12_NC	.rodata+0x4ea58 // '[msm-dsi-debug]: [%s] minv=%d maxv=%d, en_load=%d, dis_load=%d\n'
  112adc:      	bl	0x112adc <dsi_pwr_parse_supply_node+0x398>
		0000000000112adc:  R_AARCH64_CALL26	drm_dev_dbg
  112ae0:      	ldr	x28, [x20, #0x68]
  112ae4:      	sub	x8, x28, x27
  112ae8:      	ror	x8, x8, #0x3
  112aec:      	cmp	x8, #0x2
  112af0:      	b.hs	0x112c28 <dsi_pwr_parse_supply_node+0x4e4>
  112af4:      	mov	x0, x21
  112af8:      	mov	x1, x22
  112afc:      	add	w26, w26, #0x1
  112b00:      	blr	x28
  112b04:      	mov	x22, x0
  112b08:      	cbnz	x0, 0x1127c8 <dsi_pwr_parse_supply_node+0x84>
  112b0c:      	b	0x112c44 <dsi_pwr_parse_supply_node+0x500>
  112b10:      	mov	x0, #0xd543             // =54595
  112b14:      	movk	x0, #0xc5ed, lsl #16
  112b18:      	movk	x0, #0x6c25, lsl #32
  112b1c:      	movk	x0, #0x99d, lsl #48
  112b20:      	mov	x1, x28
  112b24:      	bl	0x112b24 <dsi_pwr_parse_supply_node+0x3e0>
		0000000000112b24:  R_AARCH64_CALL26	__cfi_slowpath
  112b28:      	b	0x1127e8 <dsi_pwr_parse_supply_node+0xa4>
  112b2c:      	mov	x0, #0xe44a             // =58442
  112b30:      	movk	x0, #0xc440, lsl #16
  112b34:      	movk	x0, #0xff33, lsl #32
  112b38:      	movk	x0, #0xa2d4, lsl #48
  112b3c:      	mov	x1, x28
  112b40:      	bl	0x112b40 <dsi_pwr_parse_supply_node+0x3fc>
		0000000000112b40:  R_AARCH64_CALL26	__cfi_slowpath
  112b44:      	b	0x112834 <dsi_pwr_parse_supply_node+0xf0>
  112b48:      	mov	x0, #0xe44a             // =58442
  112b4c:      	movk	x0, #0xc440, lsl #16
  112b50:      	movk	x0, #0xff33, lsl #32
  112b54:      	movk	x0, #0xa2d4, lsl #48
  112b58:      	mov	x1, x28
  112b5c:      	bl	0x112b5c <dsi_pwr_parse_supply_node+0x418>
		0000000000112b5c:  R_AARCH64_CALL26	__cfi_slowpath
  112b60:      	b	0x112874 <dsi_pwr_parse_supply_node+0x130>
  112b64:      	mov	x0, #0xe44a             // =58442
  112b68:      	movk	x0, #0xc440, lsl #16
  112b6c:      	movk	x0, #0xff33, lsl #32
  112b70:      	movk	x0, #0xa2d4, lsl #48
  112b74:      	mov	x1, x28
  112b78:      	bl	0x112b78 <dsi_pwr_parse_supply_node+0x434>
		0000000000112b78:  R_AARCH64_CALL26	__cfi_slowpath
  112b7c:      	b	0x1128b0 <dsi_pwr_parse_supply_node+0x16c>
  112b80:      	mov	x0, #0xe44a             // =58442
  112b84:      	movk	x0, #0xc440, lsl #16
  112b88:      	movk	x0, #0xff33, lsl #32
  112b8c:      	movk	x0, #0xa2d4, lsl #48
  112b90:      	mov	x1, x28
  112b94:      	bl	0x112b94 <dsi_pwr_parse_supply_node+0x450>
		0000000000112b94:  R_AARCH64_CALL26	__cfi_slowpath
  112b98:      	b	0x1128ec <dsi_pwr_parse_supply_node+0x1a8>
  112b9c:      	mov	x0, #0xe44a             // =58442
  112ba0:      	movk	x0, #0xc440, lsl #16
  112ba4:      	movk	x0, #0xff33, lsl #32
  112ba8:      	movk	x0, #0xa2d4, lsl #48
  112bac:      	mov	x1, x28
  112bb0:      	bl	0x112bb0 <dsi_pwr_parse_supply_node+0x46c>
		0000000000112bb0:  R_AARCH64_CALL26	__cfi_slowpath
  112bb4:      	b	0x112928 <dsi_pwr_parse_supply_node+0x1e4>
  112bb8:      	mov	x0, #0xe44a             // =58442
  112bbc:      	movk	x0, #0xc440, lsl #16
  112bc0:      	movk	x0, #0xff33, lsl #32
  112bc4:      	movk	x0, #0xa2d4, lsl #48
  112bc8:      	mov	x1, x28
  112bcc:      	bl	0x112bcc <dsi_pwr_parse_supply_node+0x488>
		0000000000112bcc:  R_AARCH64_CALL26	__cfi_slowpath
  112bd0:      	b	0x11297c <dsi_pwr_parse_supply_node+0x238>
  112bd4:      	mov	x0, #0xe44a             // =58442
  112bd8:      	movk	x0, #0xc440, lsl #16
  112bdc:      	movk	x0, #0xff33, lsl #32
  112be0:      	movk	x0, #0xa2d4, lsl #48
  112be4:      	mov	x1, x28
  112be8:      	bl	0x112be8 <dsi_pwr_parse_supply_node+0x4a4>
		0000000000112be8:  R_AARCH64_CALL26	__cfi_slowpath
  112bec:      	b	0x1129d0 <dsi_pwr_parse_supply_node+0x28c>
  112bf0:      	mov	x0, #0xe44a             // =58442
  112bf4:      	movk	x0, #0xc440, lsl #16
  112bf8:      	movk	x0, #0xff33, lsl #32
  112bfc:      	movk	x0, #0xa2d4, lsl #48
  112c00:      	mov	x1, x28
  112c04:      	bl	0x112c04 <dsi_pwr_parse_supply_node+0x4c0>
		0000000000112c04:  R_AARCH64_CALL26	__cfi_slowpath
  112c08:      	b	0x112a24 <dsi_pwr_parse_supply_node+0x2e0>
  112c0c:      	mov	x0, #0xe44a             // =58442
  112c10:      	movk	x0, #0xc440, lsl #16
  112c14:      	movk	x0, #0xff33, lsl #32
  112c18:      	movk	x0, #0xa2d4, lsl #48
  112c1c:      	mov	x1, x28
  112c20:      	bl	0x112c20 <dsi_pwr_parse_supply_node+0x4dc>
		0000000000112c20:  R_AARCH64_CALL26	__cfi_slowpath
  112c24:      	b	0x112a78 <dsi_pwr_parse_supply_node+0x334>
  112c28:      	mov	x0, #0x78d6             // =30934
  112c2c:      	movk	x0, #0xe799, lsl #16
  112c30:      	movk	x0, #0xe11c, lsl #32
  112c34:      	movk	x0, #0x5fed, lsl #48
  112c38:      	mov	x1, x28
  112c3c:      	bl	0x112c3c <dsi_pwr_parse_supply_node+0x4f8>
		0000000000112c3c:  R_AARCH64_CALL26	__cfi_slowpath
  112c40:      	b	0x112af4 <dsi_pwr_parse_supply_node+0x3b0>
  112c44:      	mov	w28, wzr
  112c48:      	b	0x112ccc <dsi_pwr_parse_supply_node+0x588>
  112c4c:      	adrp	x1, 0x112000 <dsi_phy_driver_probe$f82802b0bf108c90655d299f84d4d244+0x678>
		0000000000112c4c:  R_AARCH64_ADR_PREL_PG_HI21	.rodata+0x48144 // '\x013'
  112c50:      	adrp	x2, 0x112000 <dsi_phy_driver_probe$f82802b0bf108c90655d299f84d4d244+0x678>
		0000000000112c50:  R_AARCH64_ADR_PREL_PG_HI21	.rodata+0x18d89 // '*ERROR* [msm-dsi-error]: failed to read name, rc = %d\n'
  112c54:      	mov	w28, w0
  112c58:      	add	x1, x1, #0x0
		0000000000112c58:  R_AARCH64_ADD_ABS_LO12_NC	.rodata+0x48144 // '\x013'
  112c5c:      	add	x2, x2, #0x0
		0000000000112c5c:  R_AARCH64_ADD_ABS_LO12_NC	.rodata+0x18d89 // '*ERROR* [msm-dsi-error]: failed to read name, rc = %d\n'
  112c60:      	b	0x112cc0 <dsi_pwr_parse_supply_node+0x57c>
  112c64:      	adrp	x1, 0x112000 <dsi_phy_driver_probe$f82802b0bf108c90655d299f84d4d244+0x678>
		0000000000112c64:  R_AARCH64_ADR_PREL_PG_HI21	.rodata+0x48144 // '\x013'
  112c68:      	adrp	x2, 0x112000 <dsi_phy_driver_probe$f82802b0bf108c90655d299f84d4d244+0x678>
		0000000000112c68:  R_AARCH64_ADR_PREL_PG_HI21	.rodata+0x3ca17 // '*ERROR* [msm-dsi-error]: failed to read min voltage, rc = %d\n'
  112c6c:      	mov	w28, w0
  112c70:      	add	x1, x1, #0x0
		0000000000112c70:  R_AARCH64_ADD_ABS_LO12_NC	.rodata+0x48144 // '\x013'
  112c74:      	add	x2, x2, #0x0
		0000000000112c74:  R_AARCH64_ADD_ABS_LO12_NC	.rodata+0x3ca17 // '*ERROR* [msm-dsi-error]: failed to read min voltage, rc = %d\n'
  112c78:      	b	0x112cc0 <dsi_pwr_parse_supply_node+0x57c>
  112c7c:      	adrp	x1, 0x112000 <dsi_phy_driver_probe$f82802b0bf108c90655d299f84d4d244+0x678>
		0000000000112c7c:  R_AARCH64_ADR_PREL_PG_HI21	.rodata+0x48144 // '\x013'
  112c80:      	adrp	x2, 0x112000 <dsi_phy_driver_probe$f82802b0bf108c90655d299f84d4d244+0x678>
		0000000000112c80:  R_AARCH64_ADR_PREL_PG_HI21	.rodata+0x42a78 // '*ERROR* [msm-dsi-error]: failed to read max voltage, rc = %d\n'
  112c84:      	mov	w28, w0
  112c88:      	add	x1, x1, #0x0
		0000000000112c88:  R_AARCH64_ADD_ABS_LO12_NC	.rodata+0x48144 // '\x013'
  112c8c:      	add	x2, x2, #0x0
		0000000000112c8c:  R_AARCH64_ADD_ABS_LO12_NC	.rodata+0x42a78 // '*ERROR* [msm-dsi-error]: failed to read max voltage, rc = %d\n'
  112c90:      	b	0x112cc0 <dsi_pwr_parse_supply_node+0x57c>
  112c94:      	adrp	x1, 0x112000 <dsi_phy_driver_probe$f82802b0bf108c90655d299f84d4d244+0x678>
		0000000000112c94:  R_AARCH64_ADR_PREL_PG_HI21	.rodata+0x48144 // '\x013'
  112c98:      	adrp	x2, 0x112000 <dsi_phy_driver_probe$f82802b0bf108c90655d299f84d4d244+0x678>
		0000000000112c98:  R_AARCH64_ADR_PREL_PG_HI21	.rodata+0x4ea1a // '*ERROR* [msm-dsi-error]: failed to read enable load, rc = %d\n'
  112c9c:      	mov	w28, w0
  112ca0:      	add	x1, x1, #0x0
		0000000000112ca0:  R_AARCH64_ADD_ABS_LO12_NC	.rodata+0x48144 // '\x013'
  112ca4:      	add	x2, x2, #0x0
		0000000000112ca4:  R_AARCH64_ADD_ABS_LO12_NC	.rodata+0x4ea1a // '*ERROR* [msm-dsi-error]: failed to read enable load, rc = %d\n'
  112ca8:      	b	0x112cc0 <dsi_pwr_parse_supply_node+0x57c>
  112cac:      	adrp	x1, 0x112000 <dsi_phy_driver_probe$f82802b0bf108c90655d299f84d4d244+0x678>
		0000000000112cac:  R_AARCH64_ADR_PREL_PG_HI21	.rodata+0x48144 // '\x013'
  112cb0:      	adrp	x2, 0x112000 <dsi_phy_driver_probe$f82802b0bf108c90655d299f84d4d244+0x678>
		0000000000112cb0:  R_AARCH64_ADR_PREL_PG_HI21	.rodata+0x51aad // '*ERROR* [msm-dsi-error]: failed to read disable load, rc = %d\n'
  112cb4:      	mov	w28, w0
  112cb8:      	add	x1, x1, #0x0
		0000000000112cb8:  R_AARCH64_ADD_ABS_LO12_NC	.rodata+0x48144 // '\x013'
  112cbc:      	add	x2, x2, #0x0
		0000000000112cbc:  R_AARCH64_ADD_ABS_LO12_NC	.rodata+0x51aad // '*ERROR* [msm-dsi-error]: failed to read disable load, rc = %d\n'
  112cc0:      	mov	x0, xzr
  112cc4:      	mov	w3, w28
  112cc8:      	bl	0x112cc8 <dsi_pwr_parse_supply_node+0x584>
		0000000000112cc8:  R_AARCH64_CALL26	drm_dev_printk
  112ccc:      	adrp	x9, 0x112000 <dsi_phy_driver_probe$f82802b0bf108c90655d299f84d4d244+0x678>
		0000000000112ccc:  R_AARCH64_ADR_PREL_PG_HI21	__stack_chk_guard
  112cd0:      	ldur	x8, [x29, #-0x8]
  112cd4:      	ldr	x9, [x9]
		0000000000112cd4:  R_AARCH64_LDST64_ABS_LO12_NC	__stack_chk_guard
  112cd8:      	cmp	x9, x8
  112cdc:      	b.ne	0x112d28 <dsi_pwr_parse_supply_node+0x5e4>
  112ce0:      	ldp	x29, x30, [sp, #0x20]
  112ce4:      	mov	w0, w28
  112ce8:      	ldp	x20, x19, [sp, #0x70]
  112cec:      	ldp	x22, x21, [sp, #0x60]
  112cf0:      	ldp	x24, x23, [sp, #0x50]
  112cf4:      	ldp	x26, x25, [sp, #0x40]
  112cf8:      	ldp	x28, x27, [sp, #0x30]
  112cfc:      	ldr	x30, [x18, #-0x8]!
  112d00:      	add	sp, sp, #0x80
  112d04:      	autiasp
  112d08:      	ret
  112d0c:      	mov	x0, #0x78d6             // =30934
  112d10:      	movk	x0, #0xe799, lsl #16
  112d14:      	movk	x0, #0xe11c, lsl #32
  112d18:      	movk	x0, #0x5fed, lsl #48
  112d1c:      	mov	x1, x22
  112d20:      	bl	0x112d20 <dsi_pwr_parse_supply_node+0x5dc>
		0000000000112d20:  R_AARCH64_CALL26	__cfi_slowpath
  112d24:      	b	0x1127a4 <dsi_pwr_parse_supply_node+0x60>
  112d28:      	bl	0x112d28 <dsi_pwr_parse_supply_node+0x5e4>
		0000000000112d28:  R_AARCH64_CALL26	__stack_chk_fail

