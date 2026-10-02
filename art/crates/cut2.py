import numpy as np, sys
from PIL import Image, ImageDraw, ImageFilter
from scipy import ndimage as nd
from scipy.spatial import ConvexHull
src,out,T,minA=sys.argv[1],sys.argv[2],int(sys.argv[3]),int(sys.argv[4])
im=np.array(Image.open(src).convert("RGB")).astype(int)
bright=im.max(2)>T
lab,n=nd.label(bright)
sizes=nd.sum(bright,lab,range(1,n+1))
big=np.isin(lab,1+np.where(sizes>minA)[0])
ys,xs=np.nonzero(big);pts=np.c_[xs,ys]
hull=pts[ConvexHull(pts).vertices]
m=Image.new("L",(im.shape[1],im.shape[0]),0);ImageDraw.Draw(m).polygon([tuple(p) for p in hull],fill=255)
mask=np.array(m)>0
# peel the dark glow/background off the hull: dark pixels reachable from outside it
dark=im.max(2)<int(sys.argv[5]) if len(sys.argv)>5 else None
if dark is not None:
    lab2,_=nd.label(dark|~mask)
    outside=np.isin(lab2,np.unique(np.r_[lab2[0],lab2[-1],lab2[:,0],lab2[:,-1]]))
    outside&=lab2>0
    mask=nd.binary_fill_holes(mask&~outside)
mask=nd.binary_dilation(mask,iterations=10)
# small bright bits outside the hull (sparkles), with a little outline
small=np.isin(lab,1+np.where((sizes>40)&(sizes<=minA))[0])
mask|=nd.binary_dilation(small,iterations=5)
a=Image.fromarray((mask*255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(1.5))
img=Image.open(src).convert("RGBA");img.putalpha(a)
img=img.crop(img.getbbox());w,h=img.size;s=max(w,h)
c=Image.new("RGBA",(s,s));c.paste(img,((s-w)//2,(s-h)//2))
c.resize((512,512),Image.LANCZOS).save(out)
p=Image.new("RGBA",(512,512),(120,200,120,255));p.alpha_composite(Image.open(out));p.save(out.replace(".png","-preview.png"))
