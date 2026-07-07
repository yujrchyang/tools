# Opencode Prompt

## Markdown

### HTML

将 `{markdown文件路径}` 转换为 HTML，要求：

1. **颜色主题**：整体渲染为浅色（`color-scheme: light`），白色背景，代码块、表格用浅灰背景（`#f6f8fa`），边框用 `#d0d7de`
2. **SVG 图片**：文档中嵌入的本地 SVG 图片需要读取文件内容，以内联 `<svg>` 标签方式嵌入 HTML，不能保留 `<img src="...">` 引用方式
3. **Markdown 支持**：使用 Python `markdown` 库，启用 `fenced_code` 和 `tables` 扩展以正确渲染代码块和表格
4. **样式**：字体用系统无衬线字体，最大宽度 1000px 居中显示，标题带底部边框，表格交替行背景色

### 代码调用栈

在输出调用栈时，请严格遵守以下格式要求：

1. 必须使用标准的 Unicode 制表符（Box-drawing characters）（如 `│`, `├─`, `└──`）来可视化层级和调用关系；
2. 严禁使用普通键盘符号（如 `+`, `-`, `|`, `/`）来拼接树状图；
3. 每个缩进层级请对齐；

输出格式示例：

```text
main()
├── init_settings()
│   └── load_config_file()
├── execute_process()
│   ├── fetch_data()
│   │   └── connect_database()
│   └── process_data()
└── cleanup()
```
