"""Write original-texture UV crop resources. No raster image is modified."""
from pathlib import Path

ROOT = Path(__file__).resolve().parent
HERO = 'res://Art/PaperStage/Generated/Hero_Fan_Tree.png'
WOOD = 'res://Art/SceneryFamilies/Generated/Oldwood_Family.png'
ROCK = 'res://Art/SceneryFamilies/Generated/Strata_Family.png'
ARCH = 'res://Art/SceneryFamilies/Generated/Arcade_Family.png'

CROPS = [
    dict(id='rose_fan',name='粉墨落扇',source=HERO,region=[230,140,370,355],size=[140,134.32],non_solid=True,
         note='从主树左上粉扇单独提取，沿扇叶本身边缘掩片，细连接尖端保留。',
         role='轻薄可搬的落叶与冠片，不承重；可作为枝头、草丛或岸边卷叶。',
         masks=[[[235,310],[256,271],[283,235],[310,208],[343,183],[372,163],[405,145],[443,191],[474,241],[508,299],[552,387],[595,489],[543,453],[489,421],[415,384],[342,348],[281,325]]],feet=[]),
    dict(id='twin_fan',name='折叠双扇',source=HERO,region=[40,288,565,465],size=[210,172.83],non_solid=True,
         note='提取左侧深墨扇与下方粉扇，保留两片原有角度和短连接。',
         role='可搬的低冠与落叶团；与单扇产生不同的疏密与朝向。',
         masks=[[[42,535],[63,472],[94,412],[130,354],[181,296],[230,321],[310,365],[386,407],[466,455],[549,503],[600,520],[537,522],[501,514],[447,515],[375,525],[278,533],[179,539]],[[120,544],[211,537],[297,527],[429,521],[389,567],[345,609],[300,656],[248,708],[210,744],[184,716],[159,660],[136,592]]],feet=[]),
    dict(id='branch_elbow',name='折枝肘',source=WOOD,region=[363,678,178,133],size=[165,123.29],
         note='从三向断枝取右肩，切口沿细颈木纹折线，不包含整根树干。',
         role='宽锯面与斜腹形成矮枝台；左右翻向可改变接路方向。',
         masks=[[[379,688],[397,694],[404,687],[455,682],[538,684],[514,730],[458,758],[434,761],[402,791],[391,807],[376,800],[383,786],[371,780],[377,766],[365,755],[371,744],[364,735],[371,714]]],
         feet=[[[406,689],[525,686]]]),
    dict(id='low_root',name='余根',source=WOOD,region=[987,366,260,138],size=[170,90.23],
         note='从伏根桥提取最右低根，窄颈沿不齐裂口断开，根足原形保留。',
         role='单独的小根座，顶部可站立；可与高根或石片组合出低路。',
         masks=[[[1015,371],[1036,370],[1195,371],[1206,380],[1205,441],[1244,493],[1181,491],[1179,499],[1146,502],[1115,494],[1058,494],[1048,476],[1025,474],[1013,452],[995,439],[990,418],[1004,412],[996,397],[1009,392],[1004,380]]],
         feet=[[[1048,377],[1188,377]]]),
    dict(id='slate_shelf',name='断层薄页',source=ROCK,region=[602,240,315,145],size=[190,87.46],
         note='取浮页岩左上肩，右断口顺岩理斜向破开，保留原生侵蚀下缘。',
         role='长而低的碎岩踏面，适合岸边短缝；上沿来自父岩的平层。',
         masks=[[[603,258],[617,242],[846,241],[860,245],[879,270],[896,275],[912,291],[897,308],[870,305],[857,320],[824,318],[811,334],[779,330],[756,347],[729,343],[710,362],[696,371],[681,384],[662,376],[654,352],[638,346],[630,325],[615,314]]],
         feet=[[[621,248],[842,248]]]),
    dict(id='slate_chip',name='倾斜片岩',source=ROCK,region=[364,300,192,149],size=[150,116.41],
         note='从斜页岩低端提取，保留右斜面，左侧沿斜层纹理拆成不齐断缘。',
         role='小尺度的斜肩与低端；作石缝过渡或与根座组合的短踏石。',
         masks=[[[384,302],[409,331],[441,351],[483,362],[496,387],[526,398],[554,443],[441,443],[429,429],[406,426],[415,410],[395,402],[397,385],[386,377],[389,360],[374,354],[381,338],[366,330],[377,318]]],
         feet=[[[444,355],[482,365]]]),
    dict(id='wall_cap',name='旧墙冠',source=ARCH,region=[111,554,173,149],size=[120,103.35],
         note='取半券上端的砖冠，沿破损横缝结束；不保留整根高墙。',
         role='小型残柱头，上端可停步；可组合在岸边、半券或其他矮台旁。',
         masks=[[[115,571],[153,556],[181,558],[192,580],[216,591],[225,625],[246,640],[278,644],[276,665],[281,672],[269,682],[251,676],[242,689],[222,682],[212,697],[190,690],[171,699],[163,687],[143,692],[132,679],[117,678]]],
         feet=[[[124,568],[178,565]]]),
    dict(id='broken_lintel',name='悬檐碎片',source=ARCH,region=[860,279,364,171],size=[230,108.05],
         note='取长挑落檐的右端，沿斜向裂口与厚基分离，长上沿和弧形下缘保留。',
         role='细长的局部檐片，可作为接路短桥；与整廊形成不同轮廓。',
         masks=[[[862,283],[1201,281],[1220,308],[1204,332],[1156,326],[1142,337],[1102,341],[1060,360],[1030,394],[1008,448],[965,448],[968,430],[952,421],[961,409],[940,398],[944,380],[926,369],[931,353],[909,343],[912,327],[890,319],[889,300],[875,295]]],
         feet=[[[882,288],[1190,288]]]),
]

def packed(points, region):
    x,y,w,h=region
    values=[]
    for px,py in points:
        values.extend([(px-x)/w,(py-y)/h])
    return 'PackedVector2Array('+', '.join(f'{v:.6f}' for v in values)+')'

def array(polys,region):
    return 'Array[PackedVector2Array](['+', '.join(packed(p,region) for p in polys)+'])'

def write(entry):
    region=entry['region']
    non_solid=entry.get('non_solid',False)
    lines=[
        '[gd_resource type="Resource" script_class="DerivedCropPiece" load_steps=3 format=3]','',
        '[ext_resource type="Script" path="res://Component/SceneryFamilies/Derived_Crop_Piece.gd" id="1"]',
        f'[ext_resource type="Texture2D" path="{entry["source"]}" id="2"]','',
        '[resource]','script = ExtResource("1")',
        f'piece_id = &"{entry["id"]}"',f'display_name = "{entry["name"]}"','family = &"derived_crop"',
        f'silhouette_note = "{entry["note"]}"',f'derivation_note = "{entry["note"]}"',
        f'affordance_note = "{entry["role"]}"','parent_texture = ExtResource("2")',
        'region = Rect2('+', '.join(map(str,region))+')',
        'display_size = Vector2('+', '.join(map(str,entry['size']))+')',
        'non_solid = '+str(non_solid).lower(),
        'visual_masks = '+array(entry['masks'],region),
        'picks = '+array(entry['masks'],region),
        'solids = '+array([] if non_solid else entry['masks'],region),
        'footholds = '+array(entry['feet'],region),
    ]
    (ROOT/(entry['id']+'.tres')).write_text('\n'.join(lines)+'\n',encoding='utf-8',newline='\n')
    print(entry['id'],entry['size'])

if __name__=='__main__':
    for crop in CROPS:
        write(crop)
