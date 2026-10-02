# Cut a crate off a dark, glowing backdrop: background = dark pixels reachable from the
# border once thin dark lines (the black outline) are eroded away, so the inside stays solid.
import numpy as np, sys
from PIL import Image, ImageFilter
from scipy import ndimage as nd
src,out,T,K=sys.argv[1],sys.argv[2],int(sys.argv[3]),int(sys.argv[4])
im=np.array(Image.open(src).convert("RGB")).astype(int)
dark=im.max(2)<T
core=nd.binary_erosion(dark,iterations=K,border_value=1)
lab,_=nd.label(core)
edge=np.unique(np.r_[lab[0],lab[-1],lab[:,0],lab[:,-1]]);edge=edge[edge>0]
bg=nd.binary_dilation(np.isin(lab,edge),iterations=K)&dark
mask=nd.binary_fill_holes(nd.binary_dilation(nd.binary_opening(~bg,iterations=3),iterations=K))
lab2,n=nd.label(mask);sz=nd.sum(mask,lab2,range(1,n+1));mask=lab2==1+np.argmax(sz)
mask=nd.binary_fill_holes(mask)
a=Image.fromarray((mask*255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(1.2))
img=Image.open(src).convert("RGBA");img.putalpha(a)
img=img.crop(img.getbbox());w,h=img.size;s=max(w,h)
c=Image.new("RGBA",(s,s));c.paste(img,((s-w)//2,(s-h)//2))
c.resize((512,512),Image.LANCZOS).save(out)
p=Image.new("RGBA",(512,512),(120,200,120,255));p.alpha_composite(Image.open(out));p.save(out.replace(".png","-preview.png"))
