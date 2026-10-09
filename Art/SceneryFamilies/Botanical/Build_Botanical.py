"""Serialize alpha-bounded botanical AtlasTexture resources, without changing PNG pixels."""
from pathlib import Path
import cv2
import numpy as np
from PIL import Image

ROOT=Path(__file__).resolve().parent
RGBA=np.asarray(Image.open(ROOT/'Generated'/'Botanical_Fragments.png').convert('RGBA'))
PLANTS=[
    ('fern_mat','匍匐扇蕨',[39,231,501,227],[150,67.96],'宽而低的沿地枝条，形成矮层植物群。'),
    ('moon_reeds','月轮芦苇',[619,14,193,463],[90,215.91],'三枚大小不同的圆穗与细长叶片，形成高处节奏。'),
    ('bell_spray','弯铃荚',[966,55,282,406],[100,143.97],'向一侧弯垂的钟形果实，形成中层方向感。'),
    ('broken_fan_bough','缺扇枝',[1314,21,434,443],[170,173.53],'参差破扇与带根细枝，是独立植物而非整树缩小。'),
    ('flower_clump','星花簇',[87,537,298,324],[90,97.85],'低矮叶簇、细星花与单枚高花苞。'),
    ('root_sprout','细根芽',[543,507,299,351],[86,100.96],'细长弯茎与三片叶子，用在密集簇旁留出呼吸。'),
    ('hanging_seeds','垂种带',[937,486,318,370],[105,122.17],'从上方根颈悬下的细长种荚；使用附着点定位。'),
    ('twin_leaf','双叶苗',[1392,515,326,341],[105,109.83],'一灰绿一粉墨的两片圆叶与不对称细根。'),
]

def area(points):
    return abs(sum(points[i][0]*points[(i+1)%len(points)][1]-points[(i+1)%len(points)][0]*points[i][1] for i in range(len(points))))*.5

def split_touching(points, depth=0):
    """Repair only contour vectors at narrow alpha junctions; never change image pixels."""
    clean=[]
    for point in points:
        if not clean or np.linalg.norm(np.asarray(point)-clean[-1])>0.01:
            clean.append(np.asarray(point,dtype=float))
    if len(clean)>1 and np.linalg.norm(clean[0]-clean[-1])<.01:
        clean.pop()
    if len(clean)<3 or area(clean)<2 or depth>40:
        return []
    def cross(a,b):
        return float(a[0]*b[1]-a[1]*b[0])
    count=len(clean)
    for i in range(count):
        a,b=clean[i],clean[(i+1)%count]
        r=b-a
        for j in range(i+2,count):
            if i==0 and j==count-1:
                continue
            c,d=clean[j],clean[(j+1)%count]
            s=d-c
            denominator=cross(r,s)
            if abs(denominator)<1e-8:
                continue
            t=cross(c-a,s)/denominator
            u=cross(c-a,r)/denominator
            if -1e-8<=t<=1+1e-8 and -1e-8<=u<=1+1e-8:
                hit=a+r*t
                return split_touching([hit]+clean[i+1:j+1],depth+1)+split_touching([hit]+clean[j+1:]+clean[:i+1],depth+1)
    return [clean]

def pick_polygons(region):
    x,y,w,h=region
    contours,_=cv2.findContours((RGBA[y:y+h,x:x+w,3]>38).astype(np.uint8),cv2.RETR_EXTERNAL,cv2.CHAIN_APPROX_SIMPLE)
    result=[]
    for contour in contours:
        if cv2.contourArea(contour)<8:
            continue
        points=cv2.approxPolyDP(contour,1.8,True).reshape(-1,2)
        result.extend(split_touching(points))
    packed=[]
    for polygon in result:
        values=[]
        for px,py in polygon:
            values.extend([px/w,py/h])
        packed.append('PackedVector2Array('+', '.join(f'{v:.8f}' for v in values)+')')
    return 'Array[PackedVector2Array](['+', '.join(packed)+'])'

for ident,name,region,size,note in PLANTS:
    attach='Vector2(0.062893,0.378378)' if ident=='hanging_seeds' else 'Vector2(0.5,1)'
    lines=[
        '[gd_resource type="Resource" script_class="DerivedCropPiece" load_steps=3 format=3]','',
        '[ext_resource type="Script" path="res://Component/SceneryFamilies/Derived_Crop_Piece.gd" id="1"]',
        '[ext_resource type="Texture2D" path="res://Art/SceneryFamilies/Botanical/Generated/Botanical_Fragments.png" id="2"]','',
        '[resource]','script = ExtResource("1")',f'piece_id = &"{ident}"',f'display_name = "{name}"','family = &"botanical"',
        f'silhouette_note = "{note}"',f'affordance_note = "可选取和换层的薄植物，不形成实体阻挡。"',
        'derivation_note = "按完整 alpha 主连通块外框裁取父图中的独立植物，保留完整根叶。"',
        'parent_texture = ExtResource("2")','region = Rect2('+', '.join(map(str,region))+')',
        'display_size = Vector2('+', '.join(map(str,size))+')','non_solid = true','attachment_point = '+attach,
        'picks = '+pick_polygons(region),
    ]
    destination=ROOT/'Pieces'/(ident+'.tres')
    destination.parent.mkdir(parents=True,exist_ok=True)
    destination.write_text('\n'.join(lines)+'\n',encoding='utf-8',newline='\n')
    print(ident,size)
