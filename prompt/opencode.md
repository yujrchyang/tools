## Markdown

### HTML

将 `{markdown文件路径}` 转换为 HTML，要求：

1. **颜色主题**：整体渲染为浅色（`color-scheme: light`），白色背景，代码块、表格用浅灰背景（`#f6f8fa`），边框用 `#d0d7de`
2. **SVG 图片**：文档中嵌入的本地 SVG 图片需要读取文件内容，以内联 `<svg>` 标签方式嵌入 HTML，不能保留 `<img src="...">` 引用方式
3. **Markdown 支持**：使用 Python `markdown` 库，启用 `fenced_code` 和 `tables` 扩展以正确渲染代码块和表格
4. **样式**：字体用系统无衬线字体，最大宽度 1000px 居中显示，标题带底部边框，表格交替行背景色
