def lin(c):
    c = c/255
    return c/12.92 if c <= 0.04045 else ((c+0.055)/1.055)**2.4
def L(hexs):
    h = hexs.lstrip('#')
    r,g,b = (int(h[i:i+2],16) for i in (0,2,4))
    return 0.2126*lin(r)+0.7152*lin(g)+0.0722*lin(b)
def ratio(a,b):
    la,lb = L(a),L(b)
    hi,lo = max(la,lb),min(la,lb)
    return (hi+0.05)/(lo+0.05)

pairs = [
 ("LIGHT label      #1D1D1F on #FFFFFF", "#1D1D1F","#FFFFFF"),
 ("LIGHT secondary  #6E6E73 on #FFFFFF", "#6E6E73","#FFFFFF"),
 ("LIGHT secondary  #6E6E73 on #F5F5F7", "#6E6E73","#F5F5F7"),
 ("LIGHT tertiary   #86868B on #FFFFFF", "#86868B","#FFFFFF"),
 ("LIGHT link       #0060DF on #FFFFFF", "#0060DF","#FFFFFF"),
 ("LIGHT link       #007AFF on #FFFFFF", "#007AFF","#FFFFFF"),
 ("LIGHT CTA  white on #0060DF        ", "#FFFFFF","#0060DF"),
 ("LIGHT CTA  white on #007AFF        ", "#FFFFFF","#007AFF"),
 ("DARK  label      #F5F5F7 on #1C1C1E", "#F5F5F7","#1C1C1E"),
 ("DARK  secondary  #A1A1A6 on #1C1C1E", "#A1A1A6","#1C1C1E"),
 ("DARK  tertiary   #8E8E93 on #1C1C1E", "#8E8E93","#1C1C1E"),
 ("DARK  link       #0A84FF on #1C1C1E", "#0A84FF","#1C1C1E"),
 ("DARK  link       #4DA3FF on #1C1C1E", "#4DA3FF","#1C1C1E"),
 ("DARK  CTA  white on #0A84FF        ", "#FFFFFF","#0A84FF"),
 ("DARK  CTA  white on #0A6ADF        ", "#FFFFFF","#0A6ADF"),
 ("DARK  CTA  white on #0A5FCC        ", "#FFFFFF","#0A5FCC"),
 ("DARK  CTA  #001A33 on #0A84FF      ", "#001A33","#0A84FF"),
]
for name,a,b in pairs:
    r = ratio(a,b)
    print(f"{name}  {r:5.2f}:1  {'OK-4.5' if r>=4.5 else ('OK-3.0(large/bold only)' if r>=3.0 else 'FAIL')}")
