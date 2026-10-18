# 纹理生成插件的输出设置

Soil Baker、Leaf Baker、Trunk Baker 共用输出控件和文件分配逻辑，各自仍可独立启用。材质参数和纹理生成算法保持在各自插件中。

## 使用

在面板的 **素材名称** 中填写不含扩展名的名称，在 **输出父目录** 中填写或选择项目内的目录，然后点击生成。

- 名称留空：自动使用下一个可用的 `Soil_001`、`Leaf_001`、`Trunk_001` 等编号。
- 父目录留空：分别使用 `res://Generated/Soil`、`res://Generated/Leaf`、`res://Generated/Trunk`。
- 可填写 `res://` 路径、项目相对路径，或项目内的绝对路径。输出位于项目中，以供 Godot 导入贴图并保存场景资源引用。
- **父目录是素材文件夹的上一级**，不必再手动追加素材名称。
- 指定名称的目标目录已存在时直接拒绝，空目录也算冲突；同名文件同样会导致拒绝。不会覆盖或自动修改指定的名称。

例如名称为 `Soil_02`，父目录为 `res://Component/Object/Soil`：

```text
Component/Object/Soil/Soil_02/
  Soil_02.tscn
  Soil_02_001.png
  Soil_02_002.png
  ...
  Soil_02.tres
  Soil_02.recipe.json
```

PNG 按实际生成顺序从 001 连续编号。Soil 跳过没有装饰的分块时，编号仍连续。Godot 导入时还会在素材目录中生成 PNG 的 `.import` 文件。

生成记录和参数随素材保存，便于追溯设置；游戏只加载场景与保存的贴图。生成期间输出设置不可编辑。取消或写入失败时可能留下部分文件，面板会提示状态；再次使用相同名称也会拒绝输出，需要另取名称或自行处理残留目录。

## 验证

```powershell
& "C:\Program Files\Godot\Godot_v4.7.2-stable_win64.exe" --headless --path . --script res://addons/texture_baker_common/tests/test_bake_output.gd
```

测试覆盖自定义名称和父目录、默认编号、Trunk 前缀、Unicode 名称、路径验证、已存在目录/文件冲突以及元数据拒绝覆盖。测试文件写入忽略的 `.godot/baker_output_tests/`。
