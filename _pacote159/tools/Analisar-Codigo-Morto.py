import re,os,sys,collections
SRC=sys.argv[1]
files=[f for f in sorted(os.listdir(SRC)) if f.endswith(('.ps1','.cs'))]
raw={f:open(os.path.join(SRC,f),encoding='utf-8',newline='').read() for f in files}

def scan(t):
    """devolve (codigo_sem_comentarios_com_strings, codigo_sem_strings_nem_comentarios) preservando posicoes"""
    n=len(t);a=list(t);b=list(t);i=0
    def blank(arr,s,e):
        for k in range(s,e):
            if arr[k] not in '\r\n': arr[k]=' '
    while i<n:
        c=t[i]
        if c=='<' and t[i+1:i+2]=='#':
            j=t.find('#>',i+2); j=n if j<0 else j+2
            blank(a,i,j);blank(b,i,j);i=j;continue
        if c=='#':
            j=t.find('\n',i); j=n if j<0 else j
            blank(a,i,j);blank(b,i,j);i=j;continue
        if c=="'":
            j=i+1
            while j<n:
                if t[j]=="'":
                    if t[j+1:j+2]=="'": j+=2;continue
                    break
                j+=1
            blank(b,i+1,j);i=j+1;continue
        if c=='"':
            j=i+1
            while j<n:
                if t[j]=='`': j+=2;continue
                if t[j]=='"':
                    if t[j+1:j+2]=='"': j+=2;continue
                    break
                j+=1
            blank(b,i+1,j);i=j+1;continue
        i+=1
    return ''.join(a),''.join(b)
withstr={};nostr={}
for f in files:
    withstr[f],nostr[f]=scan(raw[f])
allw='\n'.join(withstr.values())
DEADLINES=[]  # (arquivo, linha_ini, linha_fim)
if len(sys.argv)>2:
    L=raw['Launcher.ps1'].split('\n')
    # Launch: depois do 'return' do modo Hydra
    a=next(i for i,l in enumerate(L) if l.startswith('function Launch(')); 
    r=next(i for i in range(a,a+20) if 'GameStart $g;return' in L[i])
    DEADLINES.append(('Launcher.ps1',r+3,next(i for i in range(r,a+60) if L[i].startswith('}'))))
    # GameLinkOpen: depois do return
    g=next(i for i,l in enumerate(L) if l.startswith('function GameLinkOpen'))
    DEADLINES.append(('Launcher.ps1',g+3,g+4))
    # menu de contexto: depois do bloco Hydra ate o fim do handler
    c=next(i for i,l in enumerate(L) if l.startswith('$cm.Add_Opening('))
    t=nostr['Launcher.ps1'];off=sum(len(x)+1 for x in L[:c]);j=t.index('{',off);d=0
    for k in range(j,len(t)):
        if t[k]=='{':d+=1
        elif t[k]=='}':
            d-=1
            if d==0:break
    endln=t.count('\n',0,k)
    ret=next(i for i in range(c,c+30) if L[i].strip()=='return' and L[i+1].strip()=='}')
    DEADLINES.append(('Launcher.ps1',ret+2,endln))
    print('faixas mortas (modo Hydra):',[(f,a+1,b+1) for f,a,b in DEADLINES])


# funcoes
defs=[]
for f in files:
    if not f.endswith('.ps1'): continue
    for m in re.finditer(r'(?im)^[ \t]*function[ \t]+([\w\-:]+)',nostr[f]):
        defs.append((f,m.group(1),m.start()))
def body_range(f,start):
    t=nostr[f];i=t.index('{',start);d=0
    for j in range(i,len(t)):
        if t[j]=='{':d+=1
        elif t[j]=='}':
            d-=1
            if d==0:return i,j+1
    return i,len(t)
bodies={}
for f,name,pos in defs:
    s,e=body_range(f,pos); bodies[(f,name)]=(pos,e)
def refs(name,exclude):
    pat=re.compile(r'(?<![\w\-$])'+re.escape(name)+r'(?![\w\-])',re.I)
    cnt=0
    for f in files:
        t=withstr[f]
        for m in pat.finditer(t):
            p=m.start()
            skip=False
            for (ff,nn),(s,e) in exclude.items():
                if ff==f and s<=p<e: skip=True;break
            if not skip:
                ln=withstr[f].count('\n',0,p)
                if any(ff==f and a<=ln<=b for ff,a,b in DEADLINES): skip=True
            if not skip: cnt+=1
    return cnt
dead={}
SEEDS=['ExtraRun','RunTick','DelTick']   # consumidores de filas que nunca recebem itens no modo Hydra
for (f,name),rng in bodies.items():
    if name in SEEDS: dead[(f,name)]=rng
changed=True
while changed:
    changed=False
    for (f,name),rng in bodies.items():
        if (f,name) in dead: continue
        # referencias fora do proprio corpo e fora de funcoes ja mortas
        excl=dict(dead_ranges:={k:v for k,v in bodies.items() if k in dead})
        excl[(f,name)]=rng
        # nome tambem aparece na declaracao (esta dentro do range: pos..e) -> ja excluida
        if refs(name,excl)==0:
            dead[(f,name)]=rng;changed=True
print('== FUNCOES SEM NENHUMA CHAMADA (incluindo cadeias mortas) ==')
for (f,name),(s,e) in sorted(dead.items(),key=lambda x:(x[0][0],x[1][0])):
    lines=withstr[f].count('\n',s,e)+1
    ln=withstr[f].count('\n',0,s)+1
    print(f'{f}:{ln}\t{name}\t({lines} linhas)')
print('total',len(dead),'funcoes /',sum(withstr[f].count('\n',s,e)+1 for (f,n),(s,e) in dead.items()),'linhas')

# variaveis atribuidas e nunca lidas
print('\n== VARIAVEIS ATRIBUIDAS UMA UNICA VEZ E NUNCA USADAS ==')
cnt=collections.Counter()
first={}
for f in files:
    if not f.endswith('.ps1'): continue
    for m in re.finditer(r'\$(?:script:|global:)?([A-Za-z_]\w*)',nostr[f]):
        k=m.group(1).lower();cnt[k]+=1;first.setdefault(k,[]).append((f,m.start()))
# tambem conta usos dentro de strings ("$var", "${var}", "$($var)")
for f in files:
    for m in re.finditer(r'\$\{?(?:script:|global:)?([A-Za-z_]\w*)',withstr[f]):
        pass
strc=collections.Counter()
for f in files:
    for m in re.finditer(r'\$\{?(?:script:|global:)?([A-Za-z_]\w*)',withstr[f]): strc[m.group(1).lower()]+=1
auto={'_','args','error','null','true','false','this','psscriptroot','pscmdlet','input','matches','env','psitem','home','pid','host','profile','sender','e','i','j','k'}
for k,v in sorted(strc.items()):
    if v!=1 or k in auto: continue
    f,p=first[k][0] if k in first else (None,None)
    if f is None: continue
    t=nostr[f]; line=t[t.rfind('\n',0,p)+1:t.find('\n',p)]
    if re.match(r'\s*\$(?:script:|global:)?'+re.escape(k)+r'\s*=[^=]',line,re.I):
        ln=t.count('\n',0,p)+1
        print(f'{f}:{ln}\t${k}\t{line.strip()[:110]}')
