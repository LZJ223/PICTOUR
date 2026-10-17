## 一条只读台词；在 Level 的 dialogue 数组中创建和编辑。
class_name DialogueLine
extends Resource

enum Speaker { VOICEOVER, BOOK_SPIRIT, PLAYER }

@export var speaker: Speaker = Speaker.VOICEOVER
@export_multiline var text: String = ""
