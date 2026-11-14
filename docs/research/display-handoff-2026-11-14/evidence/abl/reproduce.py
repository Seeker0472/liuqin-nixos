#!/usr/bin/env python3
"""Read-only firmware extraction/disassembly for Liuqin display handoff research.

Run via reproduce.sh. Original firmware is never modified. Results go beside
this script; use LIUQIN_RESEARCH_OUT to choose a separate output directory.
"""
from pathlib import Path
import contextlib, hashlib, importlib.metadata, json, lzma, os, struct, uuid
import capstone, pefile, uefi_firmware

root=Path(os.environ.get('LIUQIN_RESEARCH_OUT',str(Path(__file__).resolve().parent)))
root.mkdir(parents=True,exist_ok=True)
dump=Path('/home/seeker/Develop/liuqin/liuqin-stock-dump/images')
rom=Path('/home/seeker/Develop/liuqin/liuqin_images_V14.0.9.0.TMYCNXM_13.0/images')
sources={}
outputs={}
def sha(b): return hashlib.sha256(b).hexdigest()
def source(p):
 b=p.read_bytes();sources[str(p)]={'size':len(b),'sha256':sha(b)};return b
def output(n,b):
 p=root/n;p.write_bytes(b);outputs[n]={'size':len(b),'sha256':sha(b)};return b

for n in ['abl_a.img','abl_b.img','uefi_a.img','uefi_b.img','imagefv_a.img','xbl_a.img']:
 source(dump/n)
abl=lzma.decompress((dump/'abl_a.img').read_bytes()[0x1078:],format=lzma.FORMAT_ALONE)
output('abl_a.decompressed',abl)
pepos=abl.rfind(b'MZ',0,abl.find(b'PE\0\0'))
assert pepos==0xb8
ablpe=output('abl.pe',abl[pepos:])
for label,p in [('uefi_a',dump/'uefi_a.img'),('rom-uefi.elf',rom/'uefi.elf')]:
 b=source(p)
 with (root/(label+'-extract.log')).open('w') as log,contextlib.redirect_stdout(log),contextlib.redirect_stderr(log):
  fw=uefi_firmware.AutoParser(b[0x1000:]).parse()
  assert fw is not None
  fw.dump(str(root/label));fw.showinfo()
 for ui in (root/label).rglob('*.ui'):
  name=ui.read_bytes().decode('utf-16-le',errors='replace').strip('\0')
  prefix='rom-' if label.startswith('rom-') else ''
  if name=='DisplayDxe':
   for pe in ui.parent.glob('*.pe'):output(prefix+'DisplayDxe.pe',pe.read_bytes())
  elif name.startswith('Panel_M81'):
   for raw in ui.parent.glob('*.raw'):output(prefix+name,raw.read_bytes())
for n in ['abl.elf','imagefv.elf']:source(rom/n)
for n in ['Panel_M81_36_02_0a_dualdsi_dsc_lcd_video.xml','Panel_M81_42_02_0b_dualdsi_dsc_lcd_video.xml']:
 assert (root/n).read_bytes()==(root/('rom-'+n)).read_bytes()

instructions={}
for name in ['abl','DisplayDxe']:
 b=(root/(name+'.pe')).read_bytes();pe=pefile.PE(data=b)
 md=capstone.Cs(capstone.CS_ARCH_ARM64,capstone.CS_MODE_LITTLE_ENDIAN);md.skipdata=True
 allins=[]
 for section in pe.sections:
  if section.Characteristics & 0x20:
   allins.extend(md.disasm(b[section.PointerToRawData:section.PointerToRawData+section.SizeOfRawData],section.VirtualAddress))
 lines=[(i.address,f'{i.address:08x} {i.mnemonic:10s} {i.op_str}') for i in allins]
 instructions[name]=lines
 output(name+'.disasm',('\n'.join(x[1] for x in lines)+'\n').encode())

ranges={
'abl':[
 ('GetVariable DisplaySplashBufferInfo, size 12',0x2a7e0,0x2a820),
 ('Actual GetMemoryMap and ExitBootServices ABI call',0x16370,0x163e8),
 ('BootServices shutdown success check and raw AArch64 entry',0x1b8fc,0x1ba54),
 ('DT path lookup, negative return goes to Off',0x2a8ec,0x2a978),
 ('Node name comparator including unit address branch',0x52368,0x5245c),
 ('Actual scan helper argument and backend',0x65d74,0x65e4c),
 ('Scan backend uses x1 length and w2 value',0x66034,0x66058),
 ('reg property check, errors do not go to Off',0x2a9e4,0x2aaf8),
 ('caller ignores splash update result',0x29208,0x29224),
 ('Locate Display Power Protocol; SetDisplayPowerState(Off=1)',0x2cd7c,0x2cdb4),
 ('power protocol indirect call at +8',0x2ce10,0x2ce30),
],
'DisplayDxe':[
 ('ExitBootServices event registration callback 0x154c',0x17ac,0x1818),
 ('SetDisplayPowerState Off branch',0x39b8,0x3a34),
 ('MDPDeInit: stop pipe then panel deinit',0x1cbe0,0x1cc64),
 ('panel deinit: polling, controller update, reset, TERM buffer',0x13888,0x13970),
 ('DSI property13 calls host reset before TERM',0x1404c,0x14054),
 ('TERM parser: FF -> delay; FD -> controller mask',0x12e00,0x12e70),
 ('TERM parser: iterate controller mask and write',0x12fb8,0x13008),
 ('M81 board powerdown, not a five-rail cold power cycle',0x106a4,0x107b4),
 ('ResetInfo reorder and defaults',0x13714,0x13788),
 ('M81 ResetInfo default sequence selection',0x10de4,0x10e70),
 ('M81 reset writes and microsecond delays',0x10e7c,0x10f10),
 ('DSIDriver_Close display/clock/device calls',0x12440,0x12578),
 ('DSI Display_Close and clock release',0x149d0,0x14a98),
 ('DSI Device_Close and PHY callback',0x146ec,0x14778),
 ('DSI backend HW_VERSION 2.6 selection',0x17e90,0x17f80),
 ('PHY PLL_CNTRL and CTRL_0 zero writes',0x180a8,0x180e4),
 ('Host soft reset and timer reset writes',0x15cec,0x15d84),
 ('MDPStopPipe top level and polling',0x1f8e4,0x1fb30),
 ('HAL interface timing enable writer',0x33744,0x33794),
 ('Clock group selector and reverse release',0x1acf0,0x1ae58),
 ('GDSC and common-clock cleanup',0x1ae58,0x1afc8),
 ('millisecond vs microsecond Stall wrappers',0x21928,0x21968),
 ('DisplaySplashBufferInfo variable writer',0x21be4,0x21c34),
 ('MDPExitBoot conditional shutdown flag',0x1ce00,0x1ce9c),
 ('MDPExitBoot common clocks only when all displays permit',0x1cf28,0x1cf58),
]}
text=[]
for name,groups in ranges.items():
 for title,lo,hi in groups:
  text.extend(['',f'## {name}: {title}',f'## RVA 0x{lo:x} .. 0x{hi:x} (exclusive)'])
  text.extend(line for addr,line in instructions[name] if lo<=addr<hi)
output('annotated-excerpts.txt',('\n'.join(text)+'\n').encode())
manifest={'sources':sources,'outputs':outputs,'tools':{n:importlib.metadata.version(n) for n in ['capstone','pefile','uefi_firmware']},'abl_mapping':{'lzma_file_offset':'0x1078','pe_offset_in_decompressed':'0xb8','imagebase':'0x0','text_rva_equals_pe_file_offset':True},'DisplayDxe_power_protocol':{'guid':'f352021d-9593-4432-bf04-67b9f3b76008','guid_rva':'0x48108','interface_rva':'0x48370','revision':'0x10000','set_power_rva':'0x36a0','get_power_rva':'0x3a34'}}
dxe=pefile.PE(data=(root/'DisplayDxe.pe').read_bytes()).get_memory_mapped_image()
def q(off): return struct.unpack_from('<Q',dxe,off)[0]
major8=q(0x3fdc0+8*8)
resource=q(q(major8+1*16+8))
clock_resources={}
for name,off,stride in [('power-domains',0,0x44),('common',8,0x58),('mdp-type0',16,0x58),('dsi0-type1',24,0x58),('dsi1-type2',32,0x58)]:
 a=q(resource+off);items=[]
 if a:
  for idx in range(32):
   raw=dxe[a+idx*stride:a+idx*stride+0x40].split(b'\0')[0]
   if not raw: break
   items.append(raw.decode('ascii'))
 clock_resources[name]={'array_rva':hex(a),'entries':items}
(root/'clock-resources-8.1.json').write_text(json.dumps(clock_resources,indent=2)+'\n')
(root/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
print(json.dumps({'output':str(root),'sources':len(sources),'core_outputs':len(outputs),'M81_XML_identical_between_dump_and_ROM':True},indent=2))
