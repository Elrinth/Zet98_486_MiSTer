-- Reference: Puu/Zet98 data bus as of f6efcbc, before DMA feedback removal.
-- Updated for block-RAM graphics VRAM (single-plane reads on their own
-- G_RD1 lane after the SDRAM lane, which CPU font reads do not drive) and
-- FONT.ROM banks 0/1 from SDRAM (one KNJ0 lane carries FONT_BYTE).
	legacy_bus(15 downto 8)<=
		LDR_WDAT				when LDR_OE='1' else
		cpuod(15 downto 8)		when cpuoe='1' and cpusel(1)='1' and DMAen='0' else
		DMA_ODAT				when DMA_DOE='1' else
		GCG_ODAT(15 downto 8)	when GCG_DOE='1' else
		DBIO_ODAT(15 downto 8)	when DBIO_DOE='1' else
		CB_RDAT0(15 downto 8)	when CB_RD1='1' and FONT_CB='0' and bussel(1)='1' else
		G_RDAT0(15 downto 8)	when G_RD1='1' and bussel(1)='1' else
		tramdo(15 downto 8)		when tramdoe(1)='1' else
		BNK89_ODAT				when BNK89_DOE='1' else
		BNKAB_ODAT				when BNKAB_DOE='1' else
		KBod					when KBoe='1' else
		SYSP_RDAT				when SYSP_DOE='1' else
		PTC_ODAT				when PTC_DOE='1' else
		MOUS_ODAT				when MOUS_DOE='1' else
		IO439_ODAT				when IO439_DOE='1' else
		x"04"					when ioaddr_odd=x"043b" and iord='1' else
		FONT_BYTE				when KNJ0_DOE='1' else
		KNJ2_ODAT				when KNJ2_DOE='1' else
		IDE_ODAT(15 downto 8)	when IDE_DOE='1' else
		TSTMP_ODAT(15 downto 8)	when TSTMP_DOE='1' else
		legacy_bus(7 downto 0)		when DMA_L2H='1' else
		x"ff";

	legacy_bus(7 downto 0)<=
		LDR_WDAT				when LDR_OE='1' else
		cpuod(7 downto 0)		when cpuoe='1' and cpusel(0)='1' and DMAen='0'  else
        INTM_ODAT           when INTM_OE='1' and tgca='0' else
        INTS_ODAT           when INTS_OE='1' and tgca='0' else
		GCG_ODAT(7 downto 0)	when GCG_DOE='1' else
		DBIO_ODAT(7 downto 0)	when DBIO_DOE='1' else
		CB_RDAT0(7 downto 0)	when CB_RD1='1' and FONT_CB='0' and bussel(0)='1' else
		G_RDAT0(7 downto 0)	when G_RD1='1' and bussel(0)='1' else
		tramdo(7 downto 0)		when tramdoe(0)='1' else
		aramdo(7 downto 0)		when aramdoe(0)='1' else
		NVR_ODAT				when NVR_DOE='1' else
		prnod					when prnoe='1' else
		COM_ODAT				when COM_DOE='1' else
		tGDCod					when tGDCoe='1' else
		gGDCod					when gGDCoe='1' else
		GPAL_ODAT				when GPAL_DOE='1' else
		IN00f0_ODAT				when IN00f0_DOE='1' else
		FDC_ODAT				when FDC_DOE='1' else
		FDCNT_ODAT				when FDCNT_DOE='1' else
		FDCIFS_ODAT				when FDCIFS_DOE='1' else
		FDIBM_ODAT				when FDIBM_DOE='1' else
		OPN_ODAT				when OPN_DOE='1' else
		SNDID_ODAT			when SNDID_OE='1' else
		IDE_ODAT(7 downto 0)	when IDE_DOE='1' else
		TSTMP_ODAT(7 downto 0)	when TSTMP_DOE='1' else
		legacy_bus(15 downto 8)		when DMA_H2L='1' else
		x"ff";
