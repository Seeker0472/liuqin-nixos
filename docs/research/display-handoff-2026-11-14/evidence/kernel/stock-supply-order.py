import pathlib,struct,json
p=pathlib.Path('/tmp/liuqin-display-systematic-20261114/kernel')
b=pathlib.Path('/home/seeker/Develop/liuqin/liuqin-stock-dump/images/dtbo_a.img').read_bytes()
h=struct.unpack_from('>8I',b)
assert h[0]==0xd7b7ab1e
out=[]
for i in range(h[4]):
 size,off,*_=struct.unpack_from('>8I',b,h[5]+i*h[3]);d=b[off:off+size]
 if d[:4]!=bytes.fromhex('d00dfeed'): continue
 magic,total,sto,sso,reso,ver,lver,boot,sslen,stlen=struct.unpack_from('>10I',d)
 strs=d[sso:sso+sslen]; pos=sto; stack=[];nodes=[]
 while pos<sto+stlen:
  token=struct.unpack_from('>I',d,pos)[0];pos+=4
  if token==1:
   end=d.index(0,pos);name=d[pos:end].decode();pos=(end+4)&~3
   parent=stack[-1] if stack else None;n={'name':name,'path':('' if parent is None else parent['path'])+'/'+name,'props':{},'children':[]}
   if parent:parent['children'].append(n)
   stack.append(n);nodes.append(n)
  elif token==2: stack.pop()
  elif token==3:
   nbytes,no=struct.unpack_from('>II',d,pos);pos+=8;pn=strs[no:].split(b'\0')[0].decode();stack[-1]['props'][pn]=d[pos:pos+nbytes];pos=(pos+nbytes+3)&~3
  elif token==4: pass
  elif token==9: break
  else: raise ValueError((i,pos,token))
 for n in nodes:
  if n['name']=='dsi_panel_pwr_supply_M81':
   out.append({'dtbo_index':i,'offset':off,'root_props':{k:v.hex(' ') for k,v in nodes[0]['props'].items() if k in ['qcom,msm-id','qcom,board-id','compatible','model']},'path':n['path'],'children':[{'index':k,'node':v['name'],'supply':v['props'].get('qcom,supply-name',b'').rstrip(b'\0').decode(),'reg':v['props'].get('reg',b'').hex(' ')} for k,v in enumerate(n['children'])]})
(p/'stock-supply-order.json').write_text(json.dumps(out,indent=2)+'\n');print(json.dumps(out,indent=2))
