import re,struct,pathlib,subprocess
p=pathlib.Path(__file__).parent
src=p/'msm_drm-dump.ko'; b=src.read_bytes()
shoff=struct.unpack_from('<Q',b,40)[0]; shsz,n,idx=struct.unpack_from('<HHH',b,58)
ss=[struct.unpack_from('<IIQQQQIIQQ',b,shoff+i*shsz) for i in range(n)]
ns=b[ss[idx][4]:ss[idx][4]+ss[idx][5]]
sections={ns[x[0]:].split(b'\0')[0].decode():x for x in ss}
r=sections['.rodata']; ro=b[r[4]:r[4]+r[5]]
symbols={}
for line in subprocess.check_output(['readelf','-sW',str(src)],text=True).splitlines():
 m=re.match(r'\s*\d+: ([0-9a-f]+)\s+\d+ FUNC\s+\S+\s+\S+\s+1 (.+)',line)
 if m: symbols[int(m[1],16)]=m[2]
for f in p.glob('*.S'):
 if '.annotated' in f.name: continue
 s=f.read_text()
 def a(m):
  key=int(m[1],16);return m[0]+' // '+symbols.get(key,'?')
 s=re.sub(r'\.text\+0x([0-9a-f]+)',a,s)
 def c(m):
  at=int(m[1],16);t=ro[at:at+300].split(b'\0')[0]
  try:return m[0]+' // '+repr(t.decode())
  except:return m[0]
 s=re.sub(r'\.rodata\+0x([0-9a-f]+)',c,s)
 f.with_suffix('.annotated.S').write_text(s)
print('annotated',len(list(p.glob('*.S'))),'files')
