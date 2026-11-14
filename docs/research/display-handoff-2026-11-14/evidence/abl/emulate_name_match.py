#!/usr/bin/env python3
"""Run the dump's actual AArch64 node-name comparator under Unicorn.
Only FDT structure access (returns supplied name), debug-assert-enabled (false),
and the final return sentinel are intercepted. CompareMem/ScanMem8 machine code
are executed unmodified. This is not a tablet boot or full FDT parser emulation.
"""
from pathlib import Path
import hashlib,json
import pefile,unicorn
from unicorn.arm64_const import *
root=Path(__file__).resolve().parent
pebytes=(root/'abl.pe').read_bytes();mapped=pefile.PE(data=pebytes).get_memory_mapped_image()
results=[]
for node in ['splash_region','splash_region@b8000000','linux_splash@b8000000','splash_region2@b8000000']:
 u=unicorn.Uc(unicorn.UC_ARCH_ARM64,unicorn.UC_MODE_ARM)
 u.mem_map(0,0x200000);u.mem_write(0,mapped)
 u.mem_map(0x2000000,0x10000);u.mem_map(0x3000000,0x10000);u.mem_map(0x4000000,0x1000)
 u.mem_write(0x2001000,node.encode()+bytes(256-len(node)))
 u.reg_write(UC_ARM64_REG_SP,0x3008000);u.reg_write(UC_ARM64_REG_LR,0x4000000)
 u.reg_write(UC_ARM64_REG_X0,0x2002000);u.reg_write(UC_ARM64_REG_X1,0)
 u.reg_write(UC_ARM64_REG_X2,0xb38b2);u.reg_write(UC_ARM64_REG_X3,13)
 seen=[];state={'instructions':0}
 def hook(uc,addr,size,data):
  state['instructions']+=1
  if addr==0x69100:
   uc.reg_write(UC_ARM64_REG_X0,0x2001000);uc.reg_write(UC_ARM64_REG_PC,uc.reg_read(UC_ARM64_REG_LR))
  elif addr==0x70ac:
   uc.reg_write(UC_ARM64_REG_X0,0);uc.reg_write(UC_ARM64_REG_PC,uc.reg_read(UC_ARM64_REG_LR))
  elif addr in [0x65d74,0x66034]:
   seen.append({'rva':hex(addr),'x0':hex(uc.reg_read(UC_ARM64_REG_X0)),'x1':uc.reg_read(UC_ARM64_REG_X1),'x2':uc.reg_read(UC_ARM64_REG_X2)})
  elif addr==0x4000000:uc.emu_stop()
 u.hook_add(unicorn.UC_HOOK_CODE,hook)
 u.emu_start(0x52368,0x4000004,count=100000)
 assert u.reg_read(UC_ARM64_REG_PC)==0x4000000
 results.append({'query':'splash_region','node':node,'match':bool(u.reg_read(UC_ARM64_REG_X0)),'scan_helper_arguments':seen,**state})
assert [v['match'] for v in results]==[True,True,False,False]
out={'unicorn':unicorn.__version__,'abl_pe_sha256':hashlib.sha256(pebytes).hexdigest(),'comparator_rva':'0x52368','query_rva':'0xb38b2','query_length':13,'intercepted_functions':{'0x69100':'return a valid supplied node-name pointer for FDT structure access','0x70ac':'debug assertions disabled'},'results':results}
(root/'unit-address-emulation.json').write_text(json.dumps(out,indent=2)+'\n')
print(json.dumps(out,indent=2))
